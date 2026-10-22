import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { chromium } from 'playwright';

// An isolated real IndexedDB origin, without loading the game or export files.
const source = await readFile(new URL('../web/storage.js', import.meta.url));
const server = createServer((request, response) => {
  response.setHeader('Cache-Control', 'no-store');
  response.setHeader('Content-Type', request.url === '/storage.js' ? 'text/javascript' : 'text/html');
  response.end(request.url === '/storage.js' ? source : '<!doctype html><title>Storage regression</title>');
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const origin = `http://127.0.0.1:${server.address().port}`;
const browser = await chromium.launch({ channel: process.env.BREACH_CHANNEL || 'chrome', headless: true });
const report = { testedAt: new Date().toISOString(), browser: browser.version(), checks: [], diagnostics: {} };
const errors = [];

async function test(name, work) {
  const context = await browser.newContext();
  const page = await context.newPage();
  page.on('pageerror', error => errors.push(error.message));
  try {
    await page.goto(origin);
    const result = await page.evaluate(work);
    assert.equal(result.ok, true, `${name}: ${JSON.stringify(result)}`);
    report.checks.push({ name, status: 'PASS', ...result });
    console.log(`PASS ${name}`);
    return result;
  } finally { await context.close(); }
}

try {
  const migration = await test('v1 migration preserves every body and other stores; later listing reads metadata only', async () => {
    const databaseName = 'project-breach-v1';
    const bytes = value => new TextEncoder().encode(JSON.stringify(value)).length;
    const records = Array.from({ length: 12 }, (_, index) => ({
      id: `legacy-${String(index).padStart(2, '0')}`, createdAt: `2025-01-${String(index + 1).padStart(2, '0')}T00:00:00.000Z`, mapId: 'M06',
      duration: index, complete: index !== 0,
      data: { seed: 42 + index, variant: 'legacy', padding: 'x'.repeat(index < 3 ? 1024 * 1024 : 16) },
      ...(index === 0 ? {} : { bytes: index === 1 ? null : 1024 * 1024 }),
    }));
    const extras = { settings: { id: 'current', version: 7, data: { volume: 0.4 } }, progress: { id: 'M06', bestScore: 99 }, plans: { id: 'M06', data: { units: [] } } };
    await new Promise((resolve, reject) => {
      const request = indexedDB.open(databaseName, 1);
      request.onupgradeneeded = () => {
        for (const name of ['settings', 'progress', 'plans', 'replays']) request.result.createObjectStore(name, { keyPath: 'id' });
      };
      request.onerror = () => reject(request.error);
      request.onsuccess = () => {
        const database = request.result;
        const transaction = database.transaction(['settings', 'progress', 'plans', 'replays'], 'readwrite');
        for (const record of records) transaction.objectStore('replays').put(record);
        for (const [name, record] of Object.entries(extras)) transaction.objectStore(name).put(record);
        transaction.oncomplete = () => { database.close(); resolve(); };
        transaction.onabort = () => reject(transaction.error);
      };
    });
    const reads = [];
    const cursors = [];
    const originalGetAll = IDBObjectStore.prototype.getAll;
    const originalCursor = IDBObjectStore.prototype.openCursor;
    IDBObjectStore.prototype.getAll = function (...args) {
      const request = originalGetAll.apply(this, args);
      const entry = { store: this.name, bytes: 0 };
      reads.push(entry);
      request.addEventListener('success', () => { entry.bytes = bytes(request.result); });
      return request;
    };
    IDBObjectStore.prototype.openCursor = function (...args) { cursors.push(this.name); return originalCursor.apply(this, args); };
    const { BreachStorage } = await import('/storage.js');
    const storage = new BreachStorage();
    const database = await storage.open();
    const metadata = await storage.listReplays();
    const migrationReads = reads.splice(0);
    const migrationCursors = cursors.splice(0);
    const originalBodies = await storage.all('replays');
    const allBytes = reads.at(-1).bytes;
    const metadataBytes = migrationReads.find(read => read.store === 'replay-metadata')?.bytes;
    const extraPreserved = await Promise.all(Object.entries(extras).map(async ([name, record]) => JSON.stringify(await storage.get(name, record.id)) === JSON.stringify(record)));
    const migrated = metadata.length === 12 && metadata.every((record, index) => !Object.hasOwn(record, 'data') && record.seed === 42 + index && record.variant === 'legacy' && record.bytes === (index >= 2 ? 1024 * 1024 : bytes(records[index].data)));
    database.close();
    storage.database = null;
    reads.length = 0;
    await storage.open();
    await storage.listReplays();
    await storage.listReplays();
    const laterReads = reads.splice(0);
    const laterCursors = cursors.splice(0);
    IDBObjectStore.prototype.getAll = originalGetAll;
    IDBObjectStore.prototype.openCursor = originalCursor;
    return {
      ok: database.version === 2 && JSON.stringify(originalBodies) === JSON.stringify(records) && migrated && extraPreserved.every(Boolean)
        && migrationReads.every(read => read.store !== 'replays') && migrationCursors.filter(name => name === 'replays').length === 1
        && laterReads.every(read => read.store === 'replay-metadata') && laterCursors.length === 0,
      bodyGetAllBytes: allBytes, metadataGetAllBytes: metadataBytes, migratedBodies: records.length,
      laterBodyGetAllCalls: laterReads.filter(read => read.store === 'replays').length, laterBodyCursorCalls: laterCursors.filter(name => name === 'replays').length,
    };
  });
  report.diagnostics = {
    legacyBodyReadBytes: migration.bodyGetAllBytes,
    listReadBytes: migration.metadataGetAllBytes,
    avoidedListingBodyBytes: migration.bodyGetAllBytes - migration.metadataGetAllBytes,
    laterListingBodyGetAllCalls: migration.laterBodyGetAllCalls,
  };

  await test('save/get/all compatibility and put/remove metadata consistency', async () => {
    const { BreachStorage } = await import('/storage.js');
    const storage = new BreachStorage();
    const data = { map_id: 'M06', duration: 7.5, seed: 77, variant: 'night', modifiers: ['night', 'night'], complete: true, nested: { value: [1, 2] } };
    const saved = await storage.saveReplay(data);
    data.nested.value.push(9);
    const stored = await storage.get('replays', saved.id);
    const all = await storage.all('replays');
    const details = await storage.listReplays();
    const compatibility = JSON.stringify(stored) === JSON.stringify(saved) && JSON.stringify(all[0]) === JSON.stringify(saved)
      && JSON.stringify(stored.data.nested.value) === '[1,2]' && !Object.hasOwn(details[0], 'data') && details[0].mapId === 'M06' && details[0].seed === 77;
    const replace = { ...saved, duration: 12, bytes: 4, data: { seed: 88, variant: 'replacement' } };
    delete replace.seed;
    delete replace.variant;
    await storage.put('replays', replace);
    const replaced = (await storage.listReplays())[0];
    const putSynced = replaced.duration === 12 && replaced.seed === 88 && replaced.variant === 'replacement' && JSON.stringify(await storage.get('replays', saved.id)) === JSON.stringify(replace);
    await storage.remove('replays', saved.id);
    return { ok: compatibility && putSynced && (await storage.listReplays()).length === 0 && (await storage.all('replays')).length === 0 };
  });

  await test('count and byte pruning use metadata; bodies and index commit together', async () => {
    const { BreachStorage } = await import('/storage.js');
    const storage = new BreachStorage();
    const originalGetAll = IDBObjectStore.prototype.getAll;
    let bodyReads = 0;
    IDBObjectStore.prototype.getAll = function (...args) { if (this.name === 'replays') bodyReads++; return originalGetAll.apply(this, args); };
    const ids = [];
    for (let index = 0; index < 12; index++) {
      const record = await storage.saveReplay({ duration: index });
      ids.push(record.id);
      // Same-millisecond writes intentionally use ID tie-breaking. Give this
      // chronological pruning fixture distinct dates rather than race it.
      await storage.put('replays', { ...record, createdAt: new Date(Date.UTC(2025, 0, index + 1)).toISOString() });
    }
    const metadata = await storage.listReplays();
    const countOk = metadata.length === 10 && !metadata.some(record => ids.slice(0, 2).includes(record.id)) && bodyReads === 0;
    for (const record of metadata) await storage.remove('replays', record.id);
    // Legacy/custom byte fields exercise the 100 MB pruning boundary without
    // allocating a 100 MB fixture. The existing API trusts saved byte fields.
    for (let index = 0; index < 3; index++) await storage.put('replays', { id: `sized-${index}`, createdAt: `2025-01-0${index + 1}`, bytes: 40 * 1024 * 1024, data: { index } });
    const latest = await storage.saveReplay({ duration: 1 });
    const byteMetadata = await storage.listReplays();
    IDBObjectStore.prototype.getAll = originalGetAll;
    const bodies = await storage.all('replays');
    return { ok: countOk && byteMetadata.length === 3 && !byteMetadata.some(record => record.id === 'sized-0') && byteMetadata.some(record => record.id === latest.id)
      && byteMetadata.map(record => record.id).sort().join() === bodies.map(record => record.id).sort().join(), pruningBodyGetAllCalls: bodyReads };
  });

  await test('metadata quota failure rolls back pending body write and pruning', async () => {
    const { BreachStorage } = await import('/storage.js');
    const storage = new BreachStorage();
    for (let index = 0; index < 10; index++) await storage.saveReplay({ duration: index });
    const beforeBodies = JSON.stringify(await storage.all('replays'));
    const beforeMetadata = JSON.stringify(await storage.listReplays());
    const originalDelete = IDBObjectStore.prototype.delete;
    IDBObjectStore.prototype.delete = function (...args) {
      if (this.name === 'replay-metadata') throw new DOMException('Injected quota failure during pruning', 'QuotaExceededError');
      return originalDelete.apply(this, args);
    };
    let code;
    try { await storage.saveReplay({ duration: 11 }); } catch (error) { code = error.code; }
    IDBObjectStore.prototype.delete = originalDelete;
    return { ok: code === 'QUOTA_EXCEEDED' && JSON.stringify(await storage.all('replays')) === beforeBodies && JSON.stringify(await storage.listReplays()) === beforeMetadata, code };
  });

  await test('write readback failures reject without pretending the committed save disappeared', async () => {
    const { BreachStorage } = await import('/storage.js');
    const storage = new BreachStorage();
    const originalGet = storage.get.bind(storage);
    storage.get = async (store, id) => store === 'replays' ? undefined : originalGet(store, id);
    let code;
    try { await storage.saveReplay({ map_id: 'T01', duration: 2 }); } catch (error) { code = error.code; }
    storage.get = originalGet;
    const metadata = await storage.listReplays();
    const saved = metadata.length === 1 && await storage.get('replays', metadata[0].id);
    return { ok: code === 'SAVE_VERIFICATION_FAILED' && saved?.data.map_id === 'T01' && storage.lastError?.code === code, code };
  });

  await test('independent connections serialize pruning and settings version checks', async () => {
    const { BreachStorage } = await import('/storage.js');
    const first = new BreachStorage();
    const second = new BreachStorage();
    for (let index = 0; index < 9; index++) await first.saveReplay({ duration: index });
    const saved = await Promise.all([first.saveReplay({ duration: 20 }), second.saveReplay({ duration: 21 })]);
    const metadata = await first.listReplays();
    const bodies = await second.all('replays');
    const settings = await first.saveSettings({ volume: 0.4 }, 0);
    let code;
    try { await second.saveSettings({ volume: 0.9 }, 0); } catch (error) { code = error.code; }
    return { ok: metadata.length === 10 && saved.every(record => metadata.some(item => item.id === record.id))
      && metadata.map(record => record.id).sort().join() === bodies.map(record => record.id).sort().join()
      && settings.version === 1 && code === 'SETTINGS_CONFLICT' && (await second.get('settings', 'current')).data.volume === 0.4 };
  });

  await test('failed upgrade rolls back metadata and keeps the complete version 1 database', async () => {
    const data = { id: 'legacy', createdAt: '2025-01-01', bytes: 8, data: { duration: 4 } };
    await new Promise((resolve, reject) => {
      const request = indexedDB.open('project-breach-v1', 1);
      request.onupgradeneeded = () => { for (const name of ['settings', 'progress', 'plans', 'replays']) request.result.createObjectStore(name, { keyPath: 'id' }); };
      request.onerror = () => reject(request.error);
      request.onsuccess = () => {
        const database = request.result;
        const transaction = database.transaction('replays', 'readwrite');
        transaction.objectStore('replays').put(data);
        transaction.oncomplete = () => { database.close(); resolve(); };
        transaction.onabort = () => reject(transaction.error);
      };
    });
    const originalPut = IDBObjectStore.prototype.put;
    IDBObjectStore.prototype.put = function (...args) {
      if (this.name === 'replay-metadata') throw new DOMException('Injected migration quota failure', 'QuotaExceededError');
      return originalPut.apply(this, args);
    };
    const { BreachStorage } = await import('/storage.js');
    const storage = new BreachStorage();
    let code;
    try { await storage.open(); } catch (error) { code = error.code; }
    IDBObjectStore.prototype.put = originalPut;
    const legacy = await new Promise((resolve, reject) => {
      const request = indexedDB.open('project-breach-v1', 1);
      request.onerror = () => reject(request.error);
      request.onsuccess = () => {
        const database = request.result;
        const requestRead = database.transaction('replays').objectStore('replays').get('legacy');
        requestRead.onsuccess = () => {
          const result = { version: database.version, hasMetadata: database.objectStoreNames.contains('replay-metadata'), record: requestRead.result };
          database.close(); resolve(result);
        };
        requestRead.onerror = () => reject(requestRead.error);
      };
    });
    await storage.open();
    const recovered = await storage.listReplays();
    return { ok: code === 'QUOTA_EXCEEDED' && legacy.version === 1 && !legacy.hasMetadata && JSON.stringify(legacy.record) === JSON.stringify(data) && recovered.length === 1, code };
  });
  assert.deepEqual(errors, [], 'Targeted storage page must not report unhandled script errors');
  report.status = 'PASS';
} catch (error) {
  report.status = 'FAIL';
  report.error = error.stack;
  throw error;
} finally {
  report.errors = errors;
  await mkdir(new URL('./artifacts/steam-optimization/', import.meta.url), { recursive: true });
  await writeFile(new URL('./artifacts/steam-optimization/storage-optimization.json', import.meta.url), JSON.stringify(report, null, 2));
  await browser.close();
  await new Promise(resolve => server.close(resolve));
}
