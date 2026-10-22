import { chromium, firefox, webkit } from 'playwright';
import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';

// Run against an already built, locally served game: npm run test:browser.
// These hooks observe the ordinary UI messages; the release exposes no test API.
const url = process.env.BREACH_URL || 'http://127.0.0.1:8080';
const browserName = process.env.BREACH_BROWSER || 'chromium';
const runName = `${browserName}${process.env.BREACH_CHANNEL ? `-${process.env.BREACH_CHANNEL}` : ''}`;
const browserType = { chromium, firefox, webkit }[browserName];
assert(browserType, `Unsupported BREACH_BROWSER=${browserName}`);
const artifacts = new URL(`./artifacts/${runName}/`, import.meta.url);
await mkdir(artifacts, { recursive: true });
const errors = [];
const warnings = [];
const failedRequests = [];
const externalRequests = [];
const report = { browser: browserName, startedAt: new Date().toISOString(), url, checks: [], measurements: {}, limitations: ['Browser automation is not Windows hardware certification or GPU performance measurement.'] };

const browser = await browserType.launch({
  headless: process.env.BREACH_HEADLESS !== '0',
  ...(process.env.BREACH_CHANNEL ? { channel: process.env.BREACH_CHANNEL } : {}),
  ...(process.env.BREACH_EXECUTABLE_PATH ? { executablePath: process.env.BREACH_EXECUTABLE_PATH } : {}),
  ...(browserName === 'chromium' ? { args: ['--enable-unsafe-swiftshader'] } : {}),
});
report.version = browser.version();
const context = await browser.newContext({ viewport: { width: 1366, height: 768 }, acceptDownloads: true });
await context.addInitScript(() => {
  window.__breachTest = { states: [], messages: [] };
  let ui;
  Object.defineProperty(window, 'BreachUI', {
    configurable: true,
    get: () => ui,
    set: value => {
      ui = value;
      if (!value || typeof value.receive !== 'function') return;
      const original = value.receive;
      value.receive = function (raw) {
        try {
          const message = typeof raw === 'string' ? JSON.parse(raw) : raw;
          if (message?.type === 'state') {
            window.__breachTest.states.push(structuredClone(message));
            if (window.__breachTest.states.length > 300) window.__breachTest.states.shift();
          } else {
            window.__breachTest.messages.push(structuredClone(message));
            if (window.__breachTest.messages.length > 100) window.__breachTest.messages.shift();
          }
        } catch {}
        return original.apply(this, arguments);
      };
    },
  });
});
const page = await context.newPage();
page.on('pageerror', error => errors.push(error.message));
page.on('console', message => {
  if (message.type() === 'error') errors.push(message.text());
  if (message.type() === 'warning') {
    warnings.push(message.text());
    if (/SCRIPT ERROR|^ERROR:|Parse Error|Failed loading resource/.test(message.text())) errors.push(message.text());
  }
});
page.on('requestfailed', request => failedRequests.push({ url: request.url(), failure: request.failure()?.errorText }));
page.on('request', request => {
  if (/^https?:/.test(request.url()) && new URL(request.url()).origin !== new URL(url).origin) externalRequests.push(request.url());
});
page.on('response', response => {
  if (response.status() >= 400) errors.push(`HTTP ${response.status()} ${response.url()}`);
});

const latest = () => page.evaluate(() => window.__breachTest.states.at(-1));
async function waitMode(mode) {
  await page.waitForFunction(expected => window.__breachTest.states.at(-1)?.mode === expected, mode, { timeout: 45_000 });
}
function passed(name) {
  report.checks.push({ name, status: 'passed' });
  console.log(`PASS ${name}`);
}
async function send(action) {
  await page.evaluate(message => window.BreachBridge.send(JSON.stringify(message)), action);
}

async function storageChecks() {
  const result = await page.evaluate(async () => {
    const { BreachStorage } = await import('./storage.js');
    const storage = new BreachStorage();
    await storage.open();
    const current = await storage.get('settings', 'current');
    const version = current?.version || 0;
    const saved = await storage.saveSettings({ volume: 0.37, ui_scale: 125 }, version);
    const second = new BreachStorage();
    await second.open();
    const read = await second.get('settings', 'current');
    let conflict;
    try { await second.saveSettings({ volume: 0.9 }, version); }
    catch (error) { conflict = error.code; }
    const plan = { id: 'regression-plan', schema_version: 1, data: { mission: 'T01', units: [] } };
    await storage.put('plans', plan);
    await storage.put('progress', { id: 'regression-progress', completed: true, bestScore: 88 });
    const planRead = await second.get('plans', plan.id);
    for (let i = 0; i < 12; i++) await storage.saveReplay({ map_id: 'T01', duration: i, complete: true });
    const replays = await storage.all('replays');
    let oversize;
    try { await storage.saveReplay({ padding: 'x'.repeat(21 * 1024 * 1024) }); }
    catch (error) { oversize = error.code; }
    return { saved, read, conflict, plan, planRead, replayCount: replays.length, oversize };
  });
  assert.deepEqual(result.saved, result.read, 'Committed settings must read identically from another connection');
  assert.equal(result.conflict, 'SETTINGS_CONFLICT', 'Concurrent stale settings version must be refused');
  assert.deepEqual(result.planRead, result.plan, 'Saved plan must survive read-back');
  assert.equal(result.replayCount, 10, 'Replay retention must prune to ten records');
  assert.equal(result.oversize, 'REPLAY_TOO_LARGE', 'Replay files larger than 20 MB must be rejected');
  passed('IndexedDB commit/read-back, conflicts, replay retention and size limits');
}

async function persistenceAfterReload() {
  await page.reload({ waitUntil: 'domcontentloaded' });
  const restored = await page.evaluate(async () => {
    const { BreachStorage } = await import('./storage.js');
    const storage = new BreachStorage();
    return {
      settings: await storage.get('settings', 'current'),
      progress: await storage.get('progress', 'regression-progress'),
      plan: await storage.get('plans', 'regression-plan'),
      replays: await storage.all('replays'),
    };
  });
  assert.equal(restored.settings.data.volume, 0.37);
  assert.equal(restored.progress.bestScore, 88);
  assert.equal(restored.plan.data.mission, 'T01');
  assert.equal(restored.replays.length, 10);
  passed('Settings, progress, plan and replay library persist after a real page reload');
}

async function unavailableStorage() {
  const unavailable = await context.newPage();
  await unavailable.addInitScript(() => Object.defineProperty(window, 'indexedDB', { value: undefined, configurable: true }));
  const pageErrors = [];
  unavailable.on('pageerror', error => pageErrors.push(error.message));
  await unavailable.goto(url, { waitUntil: 'domcontentloaded' });
  await unavailable.locator('#storage-status').filter({ hasText: 'SESSION MODE' }).waitFor();
  // RB: title -> mission select -> briefing before the start button is reachable.
  await unavailable.locator('#title-start').click();
  await unavailable.locator('#select-to-briefing').click();
  await unavailable.locator('#start-mission').click({ timeout: 120_000 });
  await unavailable.waitForFunction(() => window.__breachTest.states.at(-1)?.mode === 'PLANNING', null, { timeout: 45_000 });
  assert.deepEqual(pageErrors, [], 'Blocked persistence must not cause an unhandled application error');
  await unavailable.screenshot({ path: new URL('storage-unavailable.png', artifacts).pathname });
  await unavailable.close();
  passed('Blocked IndexedDB clearly enters session mode while the mission remains playable');
}

try {
  const start = Date.now();
  await page.goto(url, { waitUntil: 'domcontentloaded' });
  await page.locator('#canvas').waitFor({ state: 'attached' });
  await page.waitForFunction(() => typeof window.BreachBridge?.send === 'function' && typeof window.BreachUI?.receive === 'function');
  // The shell preloads the runtime; its disabled start button is enabled on ready.
  // RB: title -> mission select -> briefing before the start button is reachable.
  await page.locator('#title-start').click();
  await page.locator('#select-to-briefing').click();
  await page.locator('#start-mission').click({ timeout: 120_000 });
  await page.waitForFunction(() => window.__breachTest.messages.some(message => message?.type === 'ready') || window.__breachTest.states.length > 0, null, { timeout: 120_000 });
  report.measurements.firstReadyMs = Date.now() - start;
  passed('Fresh profile boots without sign-in, install or page errors');
  await waitMode('PLANNING');
  let state = await latest();
  assert.equal(state.units.length, 2, 'T01 must deploy two units');
  assert.equal(state.mission, 'T01');
  await page.screenshot({ path: new URL('planning-1366.png', artifacts).pathname });
  passed('T01 starts paused with two operatives');

  await send({ action: 'select', id: state.units[0].id });
  const initialCommands = state.units[0].commands.length;
  await page.locator('#wait-command').click();
  assert.equal((await latest()).units[0].commands.length, initialCommands, 'AC03: HUD click leaked a world command');
  await page.locator('#wait-duration').focus();
  await page.locator('#wait-duration').press('End');
  await page.locator('#confirm-wait').click();
  await page.waitForFunction(count => window.__breachTest.states.at(-1)?.units?.[0]?.commands?.length === count + 1, initialCommands);
  passed('HUD command dialog is keyboard-operable and does not leak a world click');
  await page.locator('#toggle-execution').click();
  await waitMode('EXECUTING');
  await page.waitForTimeout(700);
  await page.locator('#toggle-execution').click();
  await waitMode('PLANNING');
  const paused = await latest();
  await page.waitForTimeout(10_100);
  const later = await latest();
  for (const key of ['time', 'tick', 'units', 'doors', 'civilians']) assert.deepEqual(later[key], paused[key], `AC02: paused ${key} changed over ten wall-clock seconds`);
  passed('Ten seconds of planning freezes time, position, command timers and doors');

  await page.locator('#toggle-execution').click();
  await waitMode('EXECUTING');
  await page.evaluate(() => window.dispatchEvent(new Event('blur')));
  await waitMode('PLANNING');
  await page.evaluate(() => window.dispatchEvent(new Event('focus')));
  await page.waitForTimeout(300);
  assert.equal((await latest()).mode, 'PLANNING');
  passed('Focus loss pauses and focus return does not resume');

  await page.setViewportSize({ width: 1920, height: 1080 });
  await page.waitForTimeout(300);
  const overflow = await page.evaluate(() => ({ x: document.documentElement.scrollWidth > innerWidth, y: document.documentElement.scrollHeight > innerHeight }));
  assert.equal(overflow.x, false, '1080p layout has horizontal overflow');
  await page.screenshot({ path: new URL('planning-1920.png', artifacts).pathname });
  passed('1080p layout renders without horizontal document overflow');
  report.measurements.resources = await page.evaluate(() => performance.getEntriesByType('resource').map(entry => ({ name: new URL(entry.name).pathname, transferSize: entry.transferSize, duration: Math.round(entry.duration) })));
  await storageChecks();
  await persistenceAfterReload();
  await unavailableStorage();
  assert.deepEqual(externalRequests, [], 'Game should use no external services/CDNs');
  assert.deepEqual(failedRequests, [], 'No game resource should fail to load');
  assert.deepEqual(errors, [], 'No JavaScript, engine or HTTP errors are allowed');
  passed('No runtime errors, missing resources or external network dependencies');
  report.status = 'passed';
} catch (error) {
  report.status = 'failed';
  report.failure = error.stack || String(error);
  console.error(report.failure);
  try { await page.screenshot({ path: new URL('failure.png', artifacts).pathname }); } catch {}
  process.exitCode = 1;
} finally {
  report.errors = errors;
  report.warnings = warnings;
  report.failedRequests = failedRequests;
  report.externalRequests = externalRequests;
  report.finishedAt = new Date().toISOString();
  await writeFile(new URL('report.json', artifacts), JSON.stringify(report, null, 2));
  await browser.close();
}
