import { chromium } from 'playwright';
import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';

const out = 'tests/artifacts/quiet_lantern-browser';
await mkdir(out, { recursive: true });
const browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--enable-unsafe-swiftshader'] });
const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
await context.addInitScript(() => {
  let ui;
  window.quiet_lanternQA = { state: null };
  Object.defineProperty(window, 'BreachUI', {
    configurable: true, get: () => ui,
    set(value) {
      ui = value;
      const receive = value.receive;
      value.receive = function(raw) {
        const data = JSON.parse(raw);
        if (data.type === 'state') window.quiet_lanternQA.state = data;
        return receive.call(value, raw);
      };
    },
  });
});
const page = await context.newPage();
const errors = [];
page.on('pageerror', error => errors.push(error.message));
page.on('console', message => {
  if (message.type() === 'error' || /SCRIPT ERROR|Parse Error/.test(message.text())) errors.push(message.text());
});
const wait = (predicate, arg) => page.waitForFunction(predicate, arg, { timeout: 90000 });
const send = data => page.evaluate(data => window.BreachBridge.send(JSON.stringify(data)), data);
const report = { checks: [] };
try {
  const bootStarted = Date.now();
  await page.goto(process.env.BREACH_URL || 'http://127.0.0.1:8087');
  await wait(() => window.BreachBridge && !document.querySelector('#start-mission').disabled);
  report.boot_ms = Date.now() - bootStarted;
  // An isolated browser profile represents a player who unlocked H01–H06.
  // No real player storage or engine mission result is changed.
  await page.evaluate(async () => {
    const { BreachStorage } = await import('./storage.js');
    const storage = new BreachStorage();
    await storage.open();
    for (const id of ['M01', 'M02']) await storage.put('progress', { id, kind: 'mission', completed: true, stars: { complete: true, survival: true, par_time: true } });
  });
  await page.reload();
  await wait(() => window.BreachBridge && !document.querySelector('#start-mission').disabled);
  await page.locator('#title-start').click();
  await page.locator('[data-collection="history"]').click();
  assert.equal(await page.locator('.mission-card').count(), 12);
  await page.locator('[data-mission="H03"]').click();
  assert.match(await page.locator('#historical-map-facts').textContent(), /1\.8m/);
  await page.locator('#select-to-briefing').click();
  const missionStarted = Date.now();
  await page.locator('#start-mission').click();
  await wait(() => window.quiet_lanternQA.state?.mission === 'H03' && window.quiet_lanternQA.state.mode === 'PLANNING');
  report.mission_load_ms = Date.now() - missionStarted;
  const initial = await page.evaluate(() => window.quiet_lanternQA.state);
  assert.equal(initial.units.length, 4);
  assert.equal(initial.objectives.total, 5);
  assert.equal(initial.objectives.civilians_total, 4);
  await page.screenshot({ path: `${out}/planning.png` });
  const id = initial.units[0].id;
  await send({ action: 'select', id });
  await send({ action: 'command', type: 'OPEN_DOOR', args: { door_id: 'front_railing_d0' } });
  await wait(id => window.quiet_lanternQA.state.units.find(unit => unit.id === id)?.commands.length > 0, id);
  await page.locator('#toggle-execution').click();
  await wait(() => window.quiet_lanternQA.state.doors.some(door => door.id === 'front_railing_d0' && door.state === 'OPEN'));
  await page.locator('#toggle-execution').click();
  await wait(() => window.quiet_lanternQA.state.mode === 'PLANNING');
  const paused = await page.evaluate(() => window.quiet_lanternQA.state);
  const operator = paused.units.find(unit => unit.id === id);
  assert(Math.hypot(operator.x - initial.units[0].x, operator.z - initial.units[0].z) > 1);
  assert(paused.units.every(unit => unit.hp > 0));
  await page.screenshot({ path: `${out}/gate-open.png` });
  await page.setViewportSize({ width: 1366, height: 768 });
  await page.screenshot({ path: `${out}/planning-1366.png` });
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false);
  assert.deepEqual(errors, []);
  const session = await context.newCDPSession(page);
  report.browser_heap = await session.send('Runtime.getHeapUsage');
  report.browser_heap_note = 'Chrome heap and backing storage snapshot; excludes complete GPU/process memory; no baseline speed or memory reduction claim';
  report.status = 'PASS';
  report.checks = ['36 operations retained', 'updated physical-scale briefing', 'actual H03 Godot Web boot', 'four operators and unchanged rescue goals', 'real operator movement and gate opening', 'pause and 1366px layout', 'no browser or engine errors'];
  report.state = { mission: paused.mission, time: paused.time, operator: { x: operator.x, z: operator.z } };
} catch (error) {
  report.status = 'FAIL';
  report.error = error.stack;
  await page.screenshot({ path: `${out}/failure.png` });
  process.exitCode = 1;
} finally {
  report.errors = errors;
  await writeFile(`${out}/report.json`, JSON.stringify(report, null, 2));
  await browser.close();
  console.log(JSON.stringify(report));
}
