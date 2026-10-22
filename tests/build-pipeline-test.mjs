import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { gzipSync, gunzipSync, brotliCompressSync, brotliDecompressSync } from 'node:zlib';
import { fingerprintVersion, projectRoot, sha256, sourceFingerprint, verifyPackage } from '../scripts/build_fingerprint.mjs';

const root = await mkdtemp(join(tmpdir(), 'breach-build-test-'));
const output = join(root, 'dist');
async function put(path, value) { await mkdir(join(root, path, '..'), { recursive: true }); await writeFile(join(root, path), value); }
const importer = uid => `[remap]\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\nuid="${uid}"\npath="res://.godot/${uid}.scn"\n[deps]\nsource_file="res://asset.glb"\ndest_files=["res://.godot/${uid}.scn"]\n[params]\nmeshes/generate_lods=true\n`;
try {
  await put('game/project.godot', '[application]\nconfig/name="Fixture"');
  await put('game/asset.glb', 'fixture-model');
  await put('game/asset.glb.import', importer('first'));
  await put('game/tests/ignored.gd', 'first test');
  await put('game/.godot/generated', 'first cache');
  await put('game/asset.gd.uid', 'uid://first');
  const first = await sourceFingerprint(root);
  await put('game/asset.glb.import', importer('regenerated'));
  await put('game/tests/ignored.gd', 'changed test');
  await put('game/.godot/generated', 'changed cache');
  await put('game/asset.gd.uid', 'uid://second');
  assert.deepEqual(await sourceFingerprint(root), first, 'Importer cache metadata and test/cache/UID files do not invalidate a runtime export');
  await put('game/asset.glb.import', importer('regenerated').replace('generate_lods=true', 'generate_lods=false'));
  assert.notEqual((await sourceFingerprint(root)).sourceHash, first.sourceHash, 'Changing a LOD import option invalidates the export');
  await put('game/asset.glb.import', importer('regenerated'));
  for (const [path, value] of Object.entries({
    'web/index.html': '<canvas></canvas>', 'web/app.js': 'window.fixture=true;', 'web/style.css': 'canvas{display:block}',
    'web/assets/audio/test.wav': 'audio-fixture', 'licenses/license.txt': 'Fixture license',
    'licenses/provenance/source.json': '{}', 'LICENSE': 'Fixture MIT notice',
    'ASSETS-LICENSE.md': 'Fixture asset notices', 'asset-manifest.json': '{}',
  })) await put(path, value);
  await mkdir(output);
  const files = {};
  for (const name of ['engine.js', 'engine.wasm', 'engine.pck']) {
    const value = `${name}-fixture`.repeat(100);
    await put(`dist/${name}`, value);
    files[name] = sha256(value);
  }
  const manifest = { ...first, schemaVersion: fingerprintVersion, engineVersion: '4.7.2', files };
  await put('dist/engine-export-manifest.json', JSON.stringify(manifest));
  const result = spawnSync('python3', ['-c',
    'import importlib.util,sys; spec=importlib.util.spec_from_file_location("package_web",sys.argv[1]); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m); m.package(__import__("pathlib").Path(sys.argv[2]),__import__("pathlib").Path(sys.argv[3]))',
    join(projectRoot, 'scripts/package_web.py'), output, root], { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(await readFile(join(output, '.nojekyll'), 'utf8'), '');
  assert.deepEqual(await verifyPackage(output, root), manifest, 'One canonical packager produces a fully verified shell and engine');
  for (const name of ['engine.wasm', 'engine.pck', 'app.js', 'engine-export-manifest.json', 'assets/audio/test.wav']) {
    const bytes = await readFile(join(output, name));
    assert.deepEqual(gunzipSync(await readFile(join(output, `${name}.gz`))), bytes, `${name} gzip payload matches the original`);
    try {
      assert.deepEqual(brotliDecompressSync(await readFile(join(output, `${name}.br`))), bytes, `${name} Brotli payload matches the original`);
    } catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
  await put('web/app.js', 'window.fixture=false;');
  await assert.rejects(verifyPackage(output, root), /Web package is stale: app.js/);
  await put('web/app.js', 'window.fixture=true;');
  await put('dist/app.js.gz', gzipSync('different content'));
  await assert.rejects(verifyPackage(output, root), /Stale gzip sidecar/);
  await put('dist/app.js.gz', gzipSync(await readFile(join(output, 'app.js'))));
  await put('dist/app.js.br', brotliCompressSync(Buffer.from('different content')));
  await assert.rejects(verifyPackage(output, root), /Stale Brotli sidecar/);
  await put('dist/app.js.br', brotliCompressSync(await readFile(join(output, 'app.js'))));
  await put('dist/engine.pck', 'changed export');
  await assert.rejects(verifyPackage(output, root), /Invalid Godot runtime file: engine.pck/);
  await put('dist/engine.pck', 'engine.pck-fixture'.repeat(100));
  await put('game/asset.glb.import', importer('regenerated').replace('generate_lods=true', 'generate_lods=false'));
  await assert.rejects(verifyPackage(output, root), /Godot export is stale: game\/asset.glb.import/);
  console.log('PASS build pipeline: import options, ownership, shell freshness, engine hashes and gzip payloads');
} finally { await rm(root, { recursive: true, force: true }); }
