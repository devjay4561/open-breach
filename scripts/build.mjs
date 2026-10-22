import { access, cp, mkdir, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { constants } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { sha256, sourceFingerprint, verifyEngine } from './build_fingerprint.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const runtime = join(root, 'runtime', 'web');
const output = join(root, 'dist');
const nativeOutput = resolve(root, process.env.BREACH_WEB_DIR || 'build/web');
const required = ['engine.js', 'engine.wasm', 'engine.pck'];

async function syncRuntime() {
  const files = (await readdir(nativeOutput)).filter(name =>
    name.startsWith('engine.') && !name.endsWith('.gz') && !name.endsWith('.br'));
  for (const name of required) {
    if (!files.includes(name)) throw new Error(`Native export is missing ${name}`);
  }
  await mkdir(runtime, { recursive: true });
  const hashes = {};
  for (const name of files) {
    const bytes = await readFile(join(nativeOutput, name));
    await writeFile(join(runtime, name), bytes);
    hashes[name] = sha256(bytes);
  }
  const fingerprint = await sourceFingerprint();
  const manifest = JSON.stringify({
    ...fingerprint,
    engineVersion: '4.7.2',
    exportedAt: new Date().toISOString(),
    files: hashes,
  }, null, 2) + '\n';
  await writeFile(join(runtime, 'export-manifest.json'), manifest);
  await writeFile(join(nativeOutput, 'engine-export-manifest.json'), manifest);
  console.log(`Godot Web export synchronized (${files.length} runtime files).`);
}

async function verifyRuntime() {
  try {
    return await verifyEngine(runtime, 'export-manifest.json');
  } catch (error) {
    if (error.code === 'ENOENT') throw new Error('No verified Godot Web export. Run npm run build:engine on the machine with Godot.');
    throw error;
  }
}

async function nativeEngineAvailable() {
  const candidates = process.platform === 'darwin'
    ? ['.tools/Godot.app/Contents/MacOS/Godot', '.tools/godot']
    : ['.tools/godot'];
  for (const path of candidates) {
    try { await access(join(root, path), constants.X_OK); return true; } catch {}
  }
  return Boolean(process.env.GODOT_BIN) || spawnSync('godot', ['--version'], { cwd: root, stdio: 'ignore' }).status === 0;
}

async function main() {
  const catalog = spawnSync(process.execPath, ['scripts/sync_equipment_catalog.mjs'], { cwd: root, stdio: 'inherit' });
  if (catalog.error) throw catalog.error;
  if (catalog.status !== 0) throw new Error('Equipment catalog generation failed.');
  if (process.argv.includes('--sync-runtime')) {
    await syncRuntime();
    return;
  }
  if (!process.argv.includes('--portable') && await nativeEngineAvailable()) {
    const result = spawnSync('bash', ['scripts/build.sh'], { cwd: root, stdio: 'inherit', env: process.env });
    if (result.error) throw result.error;
    if (result.status !== 0) throw new Error(`Godot export failed (${result.status}).`);
  }
  const manifest = await verifyRuntime();
  // Only dist is generated here; source assets and the original export survive.
  await rm(output, { recursive: true, force: true });
  await mkdir(output, { recursive: true });
  for (const name of Object.keys(manifest.files)) {
    await cp(join(runtime, name), join(output, name));
  }
  await cp(join(runtime, 'export-manifest.json'), join(output, 'engine-export-manifest.json'));
  const packaged = spawnSync('python3', ['scripts/package_web.py', '--directory', output], { cwd: root, stdio: 'inherit' });
  if (packaged.error) throw packaged.error;
  if (packaged.status !== 0) throw new Error(`Web packaging failed (${packaged.status}).`);
  console.log('Playable browser build: dist/ (verified Godot export + current web UI).');
}

main().catch(error => { console.error(error.message); process.exitCode = 1; });
