import { chromium } from 'playwright';
import assert from 'node:assert/strict';
import { mkdir, readFile, writeFile } from 'node:fs/promises';

const out = 'tests/artifacts/hit-reaction';
await mkdir(out, { recursive: true });
const url = process.env.BREACH_URL || 'http://127.0.0.1:8098';
const fixture = JSON.parse(await readFile(`${out}/fixture.json`, 'utf8'));
const build = JSON.parse(await readFile('dist/engine-export-manifest.json', 'utf8'));
const browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--enable-unsafe-swiftshader'] });
const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
await context.addInitScript(() => {
  let ui;
  window.qa = { state: null, samples: [], capture: false };
  Object.defineProperty(window, 'BreachUI', {
    get: () => ui,
    set(value) {
      ui = value;
      const receive = value.receive;
      value.receive = function(raw) {
        const data = JSON.parse(raw);
        if (data.type === 'state') {
          window.qa.state = data;
          if (window.qa.capture) window.qa.samples.push(data);
        }
        return receive.call(value, raw);
      };
    },
  });
});
const page = await context.newPage();
const errors = [];
page.on('pageerror', error => errors.push(error.message));
page.on('console', message => {
  if (message.type() === 'error' || /SCRIPT ERROR/.test(message.text())) errors.push(message.text());
});
const send = value => page.evaluate(data => window.BreachBridge.send(JSON.stringify(data)), value);
const state = () => page.evaluate(() => window.qa.state);
const angularDistance = (a, b) => Math.abs(Math.atan2(Math.sin(a - b), Math.cos(a - b)));
const scenarios = [];
let passed = false;
try {
  await page.goto(url);
  await page.waitForFunction(() => window.BreachBridge?.send && !document.querySelector('#start-mission').disabled, null, { timeout: 120000 });
  for (const mode of ['stationary', 'moving', 'fixed-watch']) {
    await page.evaluate(() => { window.qa.capture = false; window.qa.samples = []; });
    const mission = { ...fixture, id: `HIT_QA_${mode.replace('-', '_').toUpperCase()}` };
    await send({ action: 'custom_mission', data: mission, seed: 71 });
    await page.waitForFunction(id => window.qa.state?.mission === id && window.qa.state.mode === 'PLANNING' && window.qa.state.time === 0, mission.id, { timeout: 60000 });
    await send({ action: 'select', id: 'alpha' });
    if (mode === 'moving') await send({ action: 'command', type: 'MOVE', args: { target: [12, 6] } });
    if (mode === 'fixed-watch') await send({ action: 'command', type: 'FACE', args: { target: [10, 6], persistent: true } });
    if (mode !== 'stationary') await page.waitForFunction(() => window.qa.state.units[0].commands.length === 1);
    const before = await state();
    assert.equal(before.units[0].hp, 100);
    assert.equal(before.units[0].body_facing, 0);
    assert.equal(before.enemies.length, 0, 'Rear attacker starts outside the operator FOV');
    await page.screenshot({ path: `${out}/${mode}-before.png` });
    await page.evaluate(() => { window.qa.capture = true; });
    await send({ action: 'toggle' });
    await page.waitForFunction(() => window.qa.state.time >= 2 || window.qa.state.mode === 'RESULT', null, { timeout: 60000 });
    await send({ action: 'pause' });
    await page.waitForFunction(() => window.qa.state.mode !== 'EXECUTING');
    const after = await state();
    const samples = await page.evaluate(() => { window.qa.capture = false; return window.qa.samples; });
    await writeFile(`${out}/${mode}-browser-states.json`, JSON.stringify({ before, after, samples }, null, 2));
    await page.screenshot({ path: `${out}/${mode}-after.png` });
    const firstHit = samples.find(s => s.units[0].hp < 100);
    assert.ok(firstHit, 'The actual engine applies an incoming hit');
    assert.ok(after.units[0].hp > 0);
    assert.equal(after.command_failures, 0);
    if (mode === 'fixed-watch') {
      assert.equal(after.units[0].facing_locked, true);
      assert.equal(after.units[0].facing_persistent, true);
      assert.ok(angularDistance(after.units[0].body_facing, 0) < 0.1);
      assert.equal(after.shots_fired, 0);
    } else {
      const turned = samples.find(s => angularDistance(s.units[0].body_facing, Math.PI) < 0.15 && angularDistance(s.units[0].aim_facing, Math.PI) < 0.15);
      const returned = samples.find(s => s.shots_fired > 0);
      assert.ok(turned && turned.time >= firstHit.time && turned.time - firstHit.time < 1.5, 'Body and weapon turn after a rear hit');
      assert.ok(returned && returned.time > firstHit.time, 'Operator returns fire after looking back');
      assert.ok(returned.enemies.some(e => e.id === 'e1' && e.visible), 'Return fire requires a real revealed contact');
      if (mode === 'moving') {
        assert.ok(after.units[0].x > before.units[0].x + 0.4, 'Operator continues the original movement');
        assert.deepEqual(after.units[0].commands[0].args.target, [12, 6]);
      }
    }
    scenarios.push({ mode, time: after.time, firstHit: firstHit.time, hp: after.units[0].hp, bodyFacing: after.units[0].body_facing, aimFacing: after.units[0].aim_facing, shots: after.shots_fired, position: [after.units[0].x, after.units[0].z] });
    console.log('PASS', JSON.stringify(scenarios.at(-1)));
  }
  assert.deepEqual(errors, []);
  passed = true;
} catch (error) {
  await page.screenshot({ path: `${out}/browser-failure.png` }).catch(() => {});
  await writeFile(`${out}/browser-failure-state.json`, JSON.stringify(await state().catch(() => null), null, 2));
  throw error;
} finally {
  await writeFile(`${out}/browser-report.json`, JSON.stringify({ url, testedAt: new Date().toISOString(), sourceHash: build.sourceHash, enginePackageHash: build.files['engine.pck'], passed, scenarios, errors }, null, 2));
  await browser.close();
}
