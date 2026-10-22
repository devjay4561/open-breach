import { chromium } from 'playwright';
import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';

const url = process.env.BREACH_URL || 'http://127.0.0.1:8081';
const out = 'tests/artifacts/immediate-fire';
await mkdir(out, { recursive: true });
const browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--enable-unsafe-swiftshader'] });
const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
await context.addInitScript(() => {
  let ui;
  window.qa = { state: null, events: [], messages: [] };
  Object.defineProperty(window, 'BreachUI', {
    get: () => ui,
    set(value) {
      ui = value;
      const receive = value.receive;
      value.receive = function(raw) {
        const message = JSON.parse(raw);
        if (message.type === 'state') {
          window.qa.state = message;
          window.qa.events.push(...(message.events || []));
        } else window.qa.messages.push(message);
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
const send = message => page.evaluate(value => window.BreachBridge.send(JSON.stringify(value)), message);
const report = { url, passed: false };
try {
  await page.goto(url);
  await page.waitForFunction(() => window.BreachBridge?.send && !document.querySelector('#start-mission').disabled, null, { timeout: 120000 });
  const mission = {
    schema_version: 1, id: 'IMMEDIATE_FIRE_QA', revision: 1, custom: true, title: 'Moving first contact', seed: 71,
    bounds: [20, 16], focus: [9, 6], walls: [], props: [], doors: [], rooms: [{ id: 'field', x: 10, z: 8, w: 20, d: 16 }], civilians: [], objectives: ['Reach the far corner'], stars: [],
    units: [{ id: 'alpha', name: 'ALPHA', role: 'Assault', weapon: 'standard', x: 4, z: 6, facing: 0, vision_range: 8 }],
    enemies: [{ id: 'e1', x: 12.05, z: 6, facing: Math.PI, hp: 1000, training: true, ammo: 0, reserve_ammo: 0 }],
    win: [{ type: 'reach_zone', zone: [18, 14, 0.2, 0.2] }], fail: [],
  };
  await send({ action: 'custom_mission', data: mission });
  await page.waitForFunction(() => window.qa.state?.mission === 'IMMEDIATE_FIRE_QA' && window.qa.state.mode === 'PLANNING', null, { timeout: 60000 });
  assert.equal(await page.evaluate(() => window.qa.state.enemies.length), 0, 'Enemy starts outside the operator sight range');
  await send({ action: 'select', id: 'alpha' });
  await send({ action: 'command', type: 'MOVE', args: { target: [13, 6] } });
  await page.waitForFunction(() => window.qa.state.units[0].commands.some(command => command.type === 'MOVE'));
  await page.evaluate(() => { window.qa.events = []; });
  await send({ action: 'toggle' });
  await page.waitForFunction(() => window.qa.state.shots_fired > 0, null, { timeout: 30000 });
  await send({ action: 'pause' });
  await page.waitForFunction(() => window.qa.state.mode === 'PLANNING');
  const result = await page.evaluate(() => ({ state: window.qa.state, events: window.qa.events }));
  const contact = result.events.find(event => event.type === 'CONTACT' && event.enemy_id === 'e1');
  const shot = result.events.find(event => event.type === 'SHOT' && event.attacker_id === 'alpha');
  assert.ok(contact && shot, 'Actual engine reports both first contact and a shot');
  assert.equal(shot.tick, contact.tick, 'Moving operator fires on the same tick as first sight');
  assert.ok(result.state.units[0].x > 4, 'Operator continues moving');
  assert.equal(result.state.command_failures, 0);
  assert.deepEqual(errors, []);
  report.passed = true;
  report.contact = contact;
  report.shot = shot;
  report.position = [result.state.units[0].x, result.state.units[0].z];
  await page.screenshot({ path: `${out}/moving-first-contact.png` });
} catch (error) {
  report.error = error.stack;
  report.diagnostic = await page.evaluate(() => window.qa).catch(() => null);
  await page.screenshot({ path: `${out}/failure.png` }).catch(() => {});
  process.exitCode = 1;
} finally {
  report.errors = errors;
  await writeFile(`${out}/browser-report.json`, JSON.stringify(report, null, 2));
  await browser.close();
  console.log(JSON.stringify(report));
}
