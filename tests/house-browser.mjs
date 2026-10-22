import { chromium } from 'playwright';
import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';

const out = process.env.BREACH_ARTIFACTS || 'tests/artifacts/house-playthrough';
const url = process.env.BREACH_URL || 'http://127.0.0.1:8080';
await mkdir(out, { recursive: true });
const browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--enable-unsafe-swiftshader'] });
const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
await context.addInitScript(() => {
  let ui;
  window.houseQA = { states: [], messages: [] };
  Object.defineProperty(window, 'BreachUI', {
    configurable: true,
    get: () => ui,
    set(value) {
      ui = value;
      const original = value.receive;
      value.receive = function (raw) {
        const message = JSON.parse(raw);
        if (message.type === 'state') {
          window.houseQA.states.push(message);
          if (window.houseQA.states.length > 600) window.houseQA.states.shift();
        } else window.houseQA.messages.push(message);
        return original.call(value, raw);
      };
    },
  });
});
const page = await context.newPage();
const errors = [];
page.on('pageerror', error => errors.push(error.message));
page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
const latest = () => page.evaluate(() => window.houseQA.states.at(-1));
const send = intentions => page.evaluate(values => {
  for (const intention of values) window.BreachBridge.send(JSON.stringify(intention));
}, intentions);
const select = id => ({ action: 'select', id });
const command = (type, args = {}) => ({ action: 'command', type, args });
const move = (x, z) => [command('FACE', { unlock: true }), command('MOVE', { target: [x, z] })];
const face = (x, z) => command('FACE', { target: [x, z] });
const door = id => [command('FACE', { unlock: true }), command('OPEN_DOOR', { door_id: id })];
const report = { phases: [], url, input: 'ordinary BreachBridge intentions; observable UI states only', viewport: '1440x900' };

async function phase(name, duration, intentions, minimumThreats = 0) {
  const before = await latest();
  assert.equal(before.mode, 'PLANNING', `${name} must begin paused`);
  await send([...intentions, { action: 'toggle' }]);
  await page.waitForFunction(({ target }) => {
    const state = window.houseQA.states.at(-1);
    return state?.mode === 'RESULT' || state?.time >= target || state?.command_failures > 0;
  }, { target: before.time + duration }, { timeout: 45_000 });
  let state = await latest();
  assert.equal(state.command_failures, 0, `${name}: a public command failed`);
  if (state.mode !== 'RESULT') {
    await send([{ action: 'pause' }]);
    await page.waitForFunction(() => window.houseQA.states.at(-1)?.mode === 'PLANNING');
    state = await latest();
  }
  assert(state.objectives.neutralized >= minimumThreats, `${name}: expected ${minimumThreats} threats neutralized`);
  report.phases.push({ name, time: state.time, objectives: state.objectives, mode: state.mode });
  if (['living_and_kitchen', 'guest_room'].includes(name)) await page.screenshot({ path: `${out}/${name}.png` });
  console.log(`PASS ${name} t=${state.time.toFixed(2)} threats=${state.objectives.neutralized} rescued=${state.objectives.rescued}`);
  return state;
}

async function observedCivilian(id) {
  const state = await latest();
  assert(state.civilians.some(civilian => civilian.id === id && civilian.visible), `${id} must be visible before issuing rescue`);
}

try {
  await page.goto(url);
  await page.waitForFunction(() => typeof window.BreachBridge?.send === 'function' && !document.querySelector('#start-mission').disabled, null, { timeout: 120_000 });
  await send([{ action: 'start', mission: 'M01' }]);
  await page.waitForFunction(() => window.houseQA.states.at(-1)?.mission === 'M01' && window.houseQA.states.at(-1)?.mode === 'PLANNING');
  await page.screenshot({ path: `${out}/start.png` });

  await phase('front_door', 5.5, [select('alpha'), ...door('d1'), ...move(11.2, 13.6), face(12, 10)], 1);
  await phase('second_operator_entry', 4.5, [select('bravo'), ...move(13.2, 13.6), face(15, 13.6)], 1);
  await phase('support_entry', 5, [
    select('charlie'), ...move(11.8, 15.6), face(9, 13.6),
    select('delta'), command('WAIT', { duration: 1.8 }), ...move(13, 15.6), face(15, 13.6),
  ], 1);
  await phase('living_and_kitchen', 7, [
    select('alpha'), ...door('d2'), ...move(7.7, 12.2), face(4.8, 11.6),
    select('bravo'), ...door('d3'), ...move(16.6, 12.1), face(19.5, 12),
  ], 3);
  await phase('bedroom_and_study', 8, [
    select('alpha'), ...door('d7'), ...move(6.6, 6.2), face(4.4, 8.5),
    select('charlie'), ...door('d4'), ...move(12, 7), face(13, 4.8),
  ], 5);
  await phase('observe_first_civilian', 2.5, [select('alpha'), ...move(7.5, 6.5), face(7.5, 4)], 5);
  await observedCivilian('c1');
  await phase('guest_room', 7, [
    select('alpha'), command('SECURE_CIVILIAN', { civilian_id: 'c1' }),
    select('charlie'), ...door('d6'), command('THROW_STUN', { target: [18.5, 7.5] }), ...move(17, 7), face(19.3, 7.5),
  ], 6);
  await phase('observe_second_civilian', 2.5, [select('charlie'), ...move(19.2, 6.7), face(19.8, 4.5)], 6);
  await observedCivilian('c2');
  const state = await phase('rescue', 8, [select('charlie'), command('SECURE_CIVILIAN', { civilian_id: 'c2' })], 6);
  assert.equal(state.mode, 'RESULT');
  assert.equal(state.result.success, true);
  assert.equal(state.result.neutralized, 6);
  assert.equal(state.result.rescued, 2);
  assert.equal(state.result.survivors, 4);
  assert.equal(state.result.losses, 0);
  assert(Number.isFinite(state.result.score) && state.result.score >= 0 && state.result.score <= 100);
  assert.equal(state.result.command_failures, 0);
  report.result = state.result;
  await page.screenshot({ path: `${out}/result.png` });

  const savedReplay = await page.evaluate(() => {
    const message = window.houseQA.messages.find(item => item.type === 'replay_data' && item.purpose === 'save');
    return message ? { map_id: message.data.map_id, frames: message.data.frames.length, duration: message.data.duration, schema_version: message.data.schema_version } : null;
  });
  assert(savedReplay, 'completed mission must emit its autosaved replay');
  assert.equal(savedReplay.map_id, 'M01');
  assert(savedReplay.frames > 100);
  report.savedReplay = savedReplay;
  await page.locator('#watch-replay').click();
  await page.waitForFunction(() => window.houseQA.states.at(-1)?.mode === 'REPLAY');
  await send([{ action: 'pause' }, { action: 'replay_reveal', value: true }, { action: 'replay_seek', time: state.result.time }]);
  await page.waitForFunction(() => window.houseQA.states.at(-1)?.mode === 'REPLAY' && window.houseQA.states.at(-1)?.enemies?.length === 6 && window.houseQA.states.at(-1)?.replay?.reveal === true);
  await page.screenshot({ path: `${out}/replay-full-reveal.png` });
  assert.deepEqual(errors, []);
  report.status = 'passed';
  report.errors = errors;
  console.log('PASS browser M01 full mission, autosaved replay, full reveal', JSON.stringify(state.result));
} catch (error) {
  report.status = 'failed';
  report.error = error.stack;
  report.lastState = await latest().catch(() => null);
  report.errors = errors;
  report.messages = await page.evaluate(() => window.houseQA.messages.filter(message => message.type !== 'replay_data')).catch(() => []);
  await page.screenshot({ path: `${out}/failure.png` });
  console.error(error);
  process.exitCode = 1;
} finally {
  await writeFile(`${out}/report.json`, JSON.stringify(report, null, 2));
  await browser.close();
}
process.exit(process.exitCode || 0);
