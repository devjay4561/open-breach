import { chromium } from 'playwright';
import assert from 'node:assert/strict';
import { mkdir, readFile, writeFile } from 'node:fs/promises';

const out = process.env.BREACH_ARTIFACTS || 'tests/artifacts/door-entry';
await mkdir(out, { recursive: true });
const url = process.env.BREACH_URL || 'http://127.0.0.1:8098';
const build = JSON.parse(await readFile('dist/engine-export-manifest.json', 'utf8'));
const browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--enable-unsafe-swiftshader'] });
const context = await browser.newContext({ viewport: { width: 1920, height: 1080 } });
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
const ids = ['alpha', 'bravo', 'charlie', 'delta'];
const names = ['레이븐', '에코', '모스', '라크'];
const traits = ['breacher', 'marksman', 'cautious', 'rescuer'];
const targets = [[11, 14.7], [12, 13.8], [13, 14.7], [12, 15.5]];
const scenarios = [];
let passed = false;
try {
  await page.goto(url);
  await page.waitForFunction(() => window.BreachBridge?.send && !document.querySelector('#start-mission').disabled, null, { timeout: 120000 });
  for (const mission of ['M01', 'M01H']) {
    for (const shared of [false, true]) {
      const label = `${mission}-${shared ? 'shared' : 'spread'}`;
      await page.evaluate(() => { window.qa.capture = false; window.qa.samples = []; });
      await send({
        action: 'start', mission, seed: 2130704788,
        loadout: Object.fromEntries(ids.map(id => [id, { weapon: 'standard' }])),
        roster: ids.map((id, index) => ({ id, base_id: id, name: names[index], trait: traits[index] })),
      });
      await page.waitForFunction(mission => {
        const s = window.qa.state;
        return s?.mission === mission && s.mode === 'PLANNING' && s.time === 0 && s.units.length === 4 && s.units.every(u => u.commands.length === 0);
      }, mission, { timeout: 60000 });
      for (let index = 0; index < ids.length; index++) {
        await send({ action: 'select', id: ids[index] });
        await send({ action: 'command', type: 'MOVE', args: { target: shared ? [12, 15.5] : targets[index] } });
        await page.waitForFunction(id => window.qa.state.units.find(u => u.id === id)?.commands.some(c => c.type === 'MOVE'), ids[index]);
      }
      const planned = await state();
      assert.equal(planned.seed, 2130704788);
      assert.equal(planned.time, 0);
      for (const unit of planned.units) {
        assert.deepEqual(unit.commands.map(c => c.type), ['OPEN_DOOR', 'MOVE']);
        assert.equal(unit.commands[0].args.door_id, 'd1');
      }
      await page.screenshot({ path: `${out}/${label}-plan.png` });
      await page.evaluate(() => { window.qa.capture = true; });
      await send({ action: 'toggle' });
      await page.waitForFunction(() => {
        const s = window.qa.state;
        return s?.mode === 'RESULT' || s?.command_failures > 0 || s?.time >= 30 || s?.units.every(u => u.commands.at(-1)?.state === 'SUCCEEDED');
      }, null, { timeout: 90000 });
      await send({ action: 'pause' });
      await page.waitForFunction(() => window.qa.state?.mode !== 'EXECUTING');
      const done = await state();
      const samples = await page.evaluate(() => { window.qa.capture = false; return window.qa.samples; });
      await writeFile(`${out}/${label}-browser-states.json`, JSON.stringify({ planned, done, samples }, null, 2));
      await page.screenshot({ path: `${out}/${label}-arrival.png` });
      assert.equal(done.command_failures, 0, `${label}: no door or movement failures`);
      assert.equal(done.units.length, 4);
      assert.ok(done.units.every(u => u.hp > 0 && u.z < 16.5 && u.commands.every(c => c.state === 'SUCCEEDED')), `${label}: all four finish their entry`);
      assert.equal(done.doors.find(d => d.id === 'd1').state, 'OPEN');
      let minimumSeparation = Infinity;
      for (const sample of samples) {
        for (let i = 0; i < sample.units.length; i++) {
          for (let j = i + 1; j < sample.units.length; j++) {
            const a = sample.units[i], b = sample.units[j];
            minimumSeparation = Math.min(minimumSeparation, Math.hypot(a.x - b.x, a.z - b.z));
          }
        }
      }
      assert.ok(minimumSeparation >= 0.46 - 0.0001, `${label}: live operators remain separated`);
      scenarios.push({ scenario: label, time: done.time, commandFailures: done.command_failures, minimumSeparation, samples: samples.length, allEntered: true });
      console.log('PASS', JSON.stringify(scenarios.at(-1)));
    }
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
