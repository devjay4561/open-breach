import assert from 'node:assert/strict';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { chromium } from 'playwright';

const url = process.env.BREACH_URL || 'http://127.0.0.1:8080';
const out = process.env.BREACH_ARTIFACTS || 'tests/artifacts/flash-feedback';
await mkdir(out, { recursive: true });
const browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--enable-unsafe-swiftshader'] });
const page = await browser.newPage({ viewport: { width: 1600, height: 1000 } });
const errors = [];
page.on('pageerror', error => errors.push(error.message));
page.on('console', message => {
  if (message.type() === 'error' || /SCRIPT ERROR|Parse Error|Failed loading resource/.test(message.text())) errors.push(message.text());
});
await page.addInitScript(() => {
  let ui;
  window.flashQA = { states: [], messages: [], stop: '' };
  Object.defineProperty(window, 'BreachUI', {
    configurable: true, get: () => ui,
    set(value) {
      ui = value;
      const receive = value.receive;
      value.receive = function(raw) {
        const message = typeof raw === 'string' ? JSON.parse(raw) : raw;
        const qa = window.flashQA;
        if (message.type === 'state') { qa.state = message; qa.states.push(message); }
        else qa.messages.push(message);
        const result = receive.call(this, raw);
        if (message.type === 'state' && message.mode === 'EXECUTING') {
          const prepare = qa.stop === 'prepare' && message.units.some(unit => unit.status === 'THROWING');
          const detonate = qa.stop === 'detonate' && message.events.some(event => event.type === 'STUN');
          const recover = qa.stop === 'recover' && message.time >= qa.recoveryTime;
          const pose = qa.stop === 'pose' && message.time >= qa.poseTime;
          const surrender = qa.stop === 'surrender' && message.time >= 0.3 && message.enemies.some(enemy => enemy.status === 'SURRENDERED');
          if (prepare || detonate || recover || pose || surrender) {
            qa.stop = '';
            setTimeout(() => window.BreachBridge.send(JSON.stringify({ action: 'pause' })), 0);
          }
        }
        return result;
      };
    },
  });
});
const send = message => page.evaluate(message => window.BreachBridge.send(JSON.stringify(message)), message);
const wait = predicate => page.waitForFunction(predicate, null, { timeout: 120000 });
const report = { url, errors };
try {
  await page.goto(url, { waitUntil: 'domcontentloaded' });
  await wait(() => window.BreachBridge && !document.querySelector('#start-mission').disabled);
  await send({ action: 'start', id: 'M04', seed: 42 });
  await wait(() => window.flashQA.state?.mission === 'M04' && window.flashQA.state.mode === 'PLANNING');
  await send({ action: 'command', unit_id: 'alpha', type: 'OPEN_AND_FLASH', args: { door_id: 'M04_d8' } });
  await wait(() => window.flashQA.state.units.find(unit => unit.id === 'alpha').commands.some(command => command.type === 'OPEN_AND_FLASH'));
  const planned = await page.evaluate(() => window.flashQA.state.units.find(unit => unit.id === 'alpha').commands);
  assert(planned.some(command => command.type === 'OPEN_AND_FLASH'), 'Motel door flash is queued');
  await page.evaluate(() => { window.flashQA.stop = 'prepare'; });
  await send({ action: 'toggle' });
  await wait(() => !window.flashQA.stop && window.flashQA.state.mode === 'PLANNING');
  report.preparation = await page.evaluate(() => window.flashQA.state);
  await page.screenshot({ path: `${out}/motel-preparation.png` });
  await page.evaluate(() => { window.flashQA.stop = 'detonate'; });
  await send({ action: 'toggle' });
  await wait(() => !window.flashQA.stop && window.flashQA.state.mode === 'PLANNING');
  report.detonation = await page.evaluate(() => window.flashQA.state);
  await page.screenshot({ path: `${out}/motel-detonation.png` });
  report.events = await page.evaluate(() => window.flashQA.states.flatMap(state => state.events || []).filter(event => ['FLASH_RELEASE', 'STUN'].includes(event.type)));

  // Preserve the motel's walls, doors and furniture; place a passive target on
  // the visible side of its reception desk so range/cover cannot hide the cue.
  const fixture = JSON.parse(await readFile('game/data/motel.json', 'utf8'));
  fixture.id = 'EDIT_MOTEL_FLASH_QA';
  fixture.units = [
    { id: 'alpha', name: 'ALPHA', role: 'operator', x: 16, z: 27.5, facing: -Math.PI / 2, weapon: 'standard', ammo: 0, reserve_ammo: 0, stuns: 2 },
    { id: 'bravo', name: 'BRAVO', role: 'operator', x: 15.8, z: 28.5, facing: -Math.PI / 2, weapon: 'standard', ammo: 0, reserve_ammo: 0, stuns: 0 },
  ];
  fixture.enemies = [{ id: 'flash_target', name: '섬광 표적', x: 16, z: 24, facing: 0, passive: true, ammo: 0, reserve_ammo: 0, hp: 100 }];
  fixture.civilians = [];
  fixture.win = [{ type: 'reach_zone', zone: [5, 5, 1, 1] }];
  fixture.fail = [];
  fixture.stars = [];
  await send({ action: 'import_mission', data: fixture, seed: 42 });
  await wait(() => window.flashQA.state.mission === 'EDIT_MOTEL_FLASH_QA' && window.flashQA.state.mode === 'PLANNING');
  await send({ action: 'command', unit_id: 'alpha', type: 'OPEN_AND_FLASH', args: { door_id: 'M04_d8' } });
  await wait(() => window.flashQA.state.units[0].commands.length > 0);
  await page.evaluate(() => { window.flashQA.stop = 'detonate'; });
  await send({ action: 'toggle' });
  await wait(() => !window.flashQA.stop && window.flashQA.state.mode === 'PLANNING');
  report.stunned = await page.evaluate(() => window.flashQA.state);
  const target = report.stunned.enemies.find(enemy => enemy.id === 'flash_target');
  assert(target?.stunned > 1.5 && target.stunned <= 2, 'Visible target actually receives the two-second stun');
  assert.equal(target.hp, 100, 'Flashbang does not inflict health damage');
  await page.screenshot({ path: `${out}/motel-stunned.png` });
  await page.evaluate(() => {
    window.flashQA.stop = 'pose';
    window.flashQA.poseTime = window.flashQA.state.time + 0.3;
  });
  await send({ action: 'toggle' });
  await wait(() => !window.flashQA.stop && window.flashQA.state.mode === 'PLANNING');
  report.stunPose = await page.evaluate(() => window.flashQA.state.enemies.find(enemy => enemy.id === 'flash_target'));
  assert(report.stunPose.stunned > 1, 'Stun remains active after the posture transition');
  await page.screenshot({ path: `${out}/motel-stun-pose.png` });
  await page.evaluate(() => {
    window.flashQA.stop = 'recover';
    window.flashQA.recoveryTime = window.flashQA.state.time + 2.2;
  });
  await send({ action: 'toggle' });
  await wait(() => !window.flashQA.stop && window.flashQA.state.mode === 'PLANNING');
  report.recovered = await page.evaluate(() => window.flashQA.state.enemies.find(enemy => enemy.id === 'flash_target'));
  assert.equal(report.recovered.stunned, 0, 'Stun expires after two seconds');
  await page.screenshot({ path: `${out}/motel-recovered.png` });

  // Two observers behind an armed hostage taker trigger the real surrender
  // rule. Keep ammunition empty so the render can be inspected without deaths.
  await send({ action: 'import_mission', seed: 42, data: {
    schema_version: 1, revision: 1, seed: 42, id: 'EDIT_SURRENDER_POSE_QA', title: '투항 자세 확인',
    bounds: [12, 12], focus: [6, 6],
    rooms: [{ id: 'room', x: 6, z: 6, w: 12, d: 12, lighting: 1, color: '#716c60' }],
    walls: [], doors: [], props: [], civilians: [], objectives: ['투항 자세 확인'],
    units: [
      { id: 'alpha', name: 'ALPHA', role: 'operator', weapon: 'standard', x: 5, z: 8, facing: -Math.PI / 2, ammo: 0, reserve_ammo: 0 },
      { id: 'bravo', name: 'BRAVO', role: 'operator', weapon: 'standard', x: 7, z: 8, facing: -Math.PI / 2, ammo: 0, reserve_ammo: 0 },
    ],
    enemies: [{ id: 'surrender_target', name: '투항 인원', x: 6, z: 5, facing: -Math.PI / 2, enemy_type: 'hostage_taker', ammo: 0, reserve_ammo: 0 }],
    win: [{ type: 'reach_zone', zone: [1, 1, 1, 1] }], fail: [], stars: [],
  } });
  await wait(() => window.flashQA.state.mission === 'EDIT_SURRENDER_POSE_QA' && window.flashQA.state.mode === 'PLANNING');
  const initialSurrenderHp = await page.evaluate(() => window.flashQA.state.enemies.find(enemy => enemy.id === 'surrender_target').hp);
  await page.evaluate(() => { window.flashQA.stop = 'surrender'; });
  await send({ action: 'toggle' });
  await wait(() => !window.flashQA.stop && window.flashQA.state.mode === 'PLANNING');
  report.surrendered = await page.evaluate(() => window.flashQA.state.enemies.find(enemy => enemy.id === 'surrender_target'));
  assert.equal(report.surrendered.status, 'SURRENDERED', 'Actual simulation surrender reaches the rendered actor');
  assert.equal(report.surrendered.hp, initialSurrenderHp, 'Surrender happens without health damage');
  await page.screenshot({ path: `${out}/surrender-pose.png` });
  assert.deepEqual(errors, []);
  report.passed = true;
} catch (error) {
  report.passed = false;
  report.error = error.stack;
  report.diagnostic = await page.evaluate(() => window.flashQA).catch(() => null);
  await page.screenshot({ path: `${out}/failure.png` }).catch(() => {});
  process.exitCode = 1;
} finally {
  await writeFile(`${out}/report.json`, JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ passed: report.passed, error: report.error, errors, preparationTime: report.preparation?.time, detonationTime: report.detonation?.time, blast: report.detonation?.events?.find(event => event.type === 'STUN'), enemies: report.detonation?.enemies?.map(enemy => ({ id: enemy.id, stunned: enemy.stunned })) }));
  await browser.close();
}
