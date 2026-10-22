import { chromium } from 'playwright';
import assert from 'node:assert/strict';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { setCycler, clearModifiers } from './lib/menu.mjs';

// Observe shipped messages only. Every order comes from keyboard, toolbar and
// canvas input; public catalog geometry supplies the same camera as the game.
const url = process.env.BREACH_URL || 'http://127.0.0.1:8081';
const out = process.env.BREACH_ARTIFACTS || 'tests/artifacts/house-toolbar-browser';
await mkdir(out, { recursive: true });
const browser = await chromium.launch({ channel: process.env.BREACH_CHANNEL || 'chrome', headless: process.env.BREACH_HEADLESS !== '0', args: ['--enable-unsafe-swiftshader'] });
const context = await browser.newContext({ viewport: { width: 1440, height: 900 }, acceptDownloads: true });
await context.addInitScript(() => {
  let ui;
  window.houseToolbarQA = { state: null, messages: [], catalog: {}, contextMessages: 0, keyTrace: [] };
  Object.defineProperty(window, 'BreachUI', {
    configurable: true, get: () => ui,
    set(value) {
      ui = value;
      const receive = value.receive;
      value.receive = function(raw) {
        const message = JSON.parse(raw);
        if (message.type === 'state') window.houseToolbarQA.state = message;
        else {
          window.houseToolbarQA.messages.push(message);
          if (window.houseToolbarQA.messages.length > 300) window.houseToolbarQA.messages.shift();
        }
        if (message.type === 'ready') window.houseToolbarQA.catalog = message.catalog || {};
        if (message.type === 'catalog_update') Object.assign(window.houseToolbarQA.catalog, message.catalog || {});
        if (message.type === 'context') window.houseToolbarQA.contextMessages++;
        return receive.call(this, raw);
      };
    }
  });
});
const page = await context.newPage();
const errors = [], failedRequests = [];
page.on('pageerror', error => errors.push(error.message));
page.on('console', message => { if (message.type() === 'error' || /SCRIPT ERROR|Parse Error|Failed loading resource/.test(message.text())) errors.push(message.text()); });
page.on('response', response => { if (response.status() >= 400) errors.push(`HTTP ${response.status()} ${response.url()}`); });
page.on('requestfailed', request => failedRequests.push({ url: request.url(), failure: request.failure()?.errorText }));
const report = {
  url, version: browser.version(), startedAt: new Date().toISOString(), checks: [], phases: [], input: [], errors, failedRequests,
  keyboardF: { attempts: 0, delivered: 0, toolbarFallbacks: 0, failures: [] },
  limitations: ['Native Chrome headless canvas and DOM automation does not measure Windows hardware or GPU performance.']
};
const latest = () => page.evaluate(() => window.houseToolbarQA.state);
const wait = (predicate, argument = null, timeout = 60000) => page.waitForFunction(predicate, argument, { timeout });
const mode = expected => wait(value => window.houseToolbarQA.state?.mode === value, expected);
const pass = name => { report.checks.push(name); console.log(`PASS ${name}`); };

// Mirrors game/scripts/world_view.gd's `_fit_camera` safe-area branch (which
// the shipped engine uses once web/app.js's `sendSafeArea` has sent a real
// set_safe_area message, i.e. for the whole PLANNING/EXECUTING flow this
// suite drives) rather than the pre-1-1 fixed-reserved-height fallback: the
// HUD redesign's hud-left/hud-right/hud-topbar/hud-hotbar panels now reserve
// real, independently-sized insets on all four sides, lens-shifting the
// camera so the mission frame centers inside that safe rect instead of the
// full canvas. A stale fixed-fraction formula here makes synthetic clicks
// land off their intended world target once the HUD's reserved space no
// longer matches the old assumption, which is what this helper must track.
async function project(x, z, y = 0.25) {
  return page.evaluate(({ x, z, y }) => {
    const state = window.houseToolbarQA.state, data = window.houseToolbarQA.catalog[state.mission];
    if (!data) throw new Error(`Missing public catalog geometry for ${state.mission}`);
    const focus = data.focus || data.bounds.map(value => value / 2);
    let left = focus[0], right = focus[0], top = focus[1], bottom = focus[1];
    for (const rect of [...data.rooms, ...data.walls]) {
      left = Math.min(left, rect.x - rect.w / 2); right = Math.max(right, rect.x + rect.w / 2);
      top = Math.min(top, rect.z - rect.d / 2); bottom = Math.max(bottom, rect.z + rect.d / 2);
    }
    for (const unit of data.units) { left = Math.min(left, unit.x); right = Math.max(right, unit.x); top = Math.min(top, unit.z); bottom = Math.max(bottom, unit.z); }
    left -= 0.75; right += 0.75; top -= 0.75; bottom += 0.8;
    const canvas = document.querySelector('#canvas').getBoundingClientRect(), width = canvas.width, height = canvas.height;
    const viewW = innerWidth, viewH = innerHeight, aspect = viewW / viewH;
    // Live safe-area insets, computed the same way web/app.js's sendSafeArea
    // does for PLANNING/EXECUTING (hud-left width, hud-topbar height,
    // hud-right's on-screen right inset, hud-hotbar height).
    const topbarRect = document.querySelector('.hud-topbar')?.getBoundingClientRect();
    const leftRect = document.querySelector('.hud-left')?.getBoundingClientRect();
    const rightRect = document.querySelector('.hud-right')?.getBoundingClientRect();
    const hotbarRect = document.querySelector('.hud-hotbar')?.getBoundingClientRect();
    const insetLeft = Math.round(leftRect?.width || 0);
    const insetTop = Math.round(topbarRect?.height || 0);
    const insetRight = rightRect ? Math.max(0, Math.round(viewW - Math.max(rightRect.left, 0))) : 0;
    const insetBottom = Math.round(hotbarRect?.height || 0);
    // SAFE_AREA_MARGIN_PX from world_view.gd, padding the raw insets.
    const MARGIN = 16;
    const safeLeft = insetLeft + MARGIN, safeTop = insetTop + MARGIN, safeRight = insetRight + MARGIN, safeBottom = insetBottom + MARGIN;
    const safeWidth = Math.max(viewW - safeLeft - safeRight, 1), safeHeight = Math.max(viewH - safeTop - safeBottom, 1);
    const verticalFraction = Math.min(0.97, Math.max(0.25, safeHeight / viewH));
    const horizontalFraction = Math.min(0.97, Math.max(0.25, safeWidth / viewW));
    const heightSize = (bottom - top) / verticalFraction;
    const widthSize = (right - left) / Math.max(aspect * horizontalFraction, 0.1);
    const size = Math.max(heightSize, widthSize); // zoom=1, fit_multiplier=1 once a real safe area is active
    const pixelScale = height / size; // Camera3D KEEP_HEIGHT: uniform world->pixel scale
    const centerX = (left + right) / 2, centerZ = (top + bottom) / 2; // center_bias=0 once a real safe area is active
    const norm = Math.hypot(34, 15.5), upY = 15.5 / norm, upZ = -34 / norm;
    return {
      x: canvas.left + width / 2 + (x - centerX) * pixelScale + (safeLeft - safeRight) / 2,
      y: canvas.top + height / 2 - (y * upY + (z - centerZ) * upZ) * pixelScale + (safeTop - safeBottom) / 2,
    };
  }, { x, z, y });
}
async function mapClick(x, z, y = 0.25) {
  const position = await project(x, z, y);
  await page.mouse.click(position.x, position.y);
}
async function activeUnit() { const state = await latest(); return state.units.find(unit => unit.id === state.selected); }
async function selectUnit(id) {
  const state = await latest(), index = state.units.findIndex(unit => unit.id === id);
  assert(index >= 0 && index < 4, `Missing numeric selection key for ${id}`);
  await page.locator('#canvas').focus();
  await page.keyboard.press(`Digit${index + 1}`);
  await wait(expected => window.houseToolbarQA.state?.selected === expected, id);
  report.input.push({ type: 'select', id, key: index + 1 });
}
async function appendOrder(type, click, args = {}) {
  const unit = await activeUnit(), before = unit.commands.at(-1)?.id || '';
  await click();
  await wait(({ id, before, type, args }) => {
    const order = window.houseToolbarQA.state?.units.find(unit => unit.id === id)?.commands.at(-1);
    return order && order.id !== before && order.type === type && order.state === 'PENDING'
      && Object.entries(args).every(([key, value]) => Array.isArray(value)
        ? value.every((coordinate, index) => Math.abs(order.args[key]?.[index] - coordinate) < 0.06)
        : order.args[key] === value);
  }, { id: unit.id, before, type, args });
  const order = (await activeUnit()).commands.at(-1);
  report.input.push({ type, unitId: unit.id, commandId: order.id, args: order.args });
  assert.equal(await page.locator('#context-popover').isVisible(), false);
}
async function moveTo(x, z) {
  await page.locator('[data-tool="move"]').click();
  await wait(() => window.houseToolbarQA.state?.tool === 'move');
  await appendOrder('MOVE', () => mapClick(x, z), { target: [x, z] });
}
async function faceTo(x, z) {
  await page.locator('#canvas').focus();
  report.keyboardF.attempts++;
  await page.keyboard.press('KeyF');
  try {
    await wait(() => window.houseToolbarQA.state?.tool === 'face', null, 1500);
    report.keyboardF.delivered++;
  } catch (error) {
    report.keyboardF.toolbarFallbacks++;
    report.keyboardF.failures.push({ unitId: (await latest()).selected, time: (await latest()).time, reason: error.message });
    await page.locator('[data-tool="face"]').click();
    await wait(() => window.houseToolbarQA.state?.tool === 'face');
  }
  await appendOrder('FACE', () => mapClick(x, z), { target: [x, z] });
}
async function openDoor(id) {
  const door = (await latest()).doors.find(item => item.id === id);
  assert(door && door.observed !== false, `${id} must first be observed by an actual operative`);
  await page.locator('#door-modes').click();
  await page.locator('[data-door-mode="OPEN_DOOR"]').click();
  await page.locator('#door-submenu').waitFor({ state: 'hidden' });
  await wait(() => window.houseToolbarQA.state?.tool === 'door' && window.houseToolbarQA.state?.door_mode === 'OPEN_DOOR');
  await appendOrder('OPEN_DOOR', () => mapClick(door.x, door.z, 0.7), { door_id: id });
}
async function plan(id, x, z, faceX, faceZ, doorId = null) {
  await selectUnit(id);
  if (doorId) await openDoor(doorId);
  await moveTo(x, z);
  await faceTo(faceX, faceZ);
}
async function secureActor(unitId, actorId, arrest = false) {
  await selectUnit(unitId);
  const state = await latest(), actor = (arrest ? state.enemies : state.civilians).find(item => item.id === actorId && item.visible);
  assert(actor, `${actorId} must be observed before an actor toolbar action`);
  if (arrest) assert.equal(actor.status, 'SURRENDERED');
  const tool = arrest ? 'arrest' : 'secure';
  await page.locator('#secure-modes').click();
  await page.locator(`#secure-submenu [data-tool="${tool}"]`).click();
  await page.locator('#secure-submenu').waitFor({ state: 'hidden' });
  await wait(expected => window.houseToolbarQA.state?.tool === expected, tool);
  await appendOrder(arrest ? 'ARREST' : 'SECURE_CIVILIAN', () => mapClick(actor.x, actor.z, 0.95), { [arrest ? 'enemy_id' : 'civilian_id']: actorId });
}
async function phase(name, seconds) {
  let state = await latest();
  const target = state.time + seconds, deadline = Date.now() + 90000, arrests = new Set();
  await page.locator('#toggle-execution').click();
  await mode('EXECUTING');
  while (Date.now() < deadline) {
    state = await latest();
    if (state.mode === 'RESULT') break;
    assert.equal(state.command_failures, 0, `${name} public command failure`);
    assert.equal(state.context_open, false, `${name} must use no context popover`);
    const enemy = state.enemies.find(item => item.visible && item.status === 'SURRENDERED' && !arrests.has(item.id) && !state.units.some(unit => unit.commands.some(command => command.type === 'ARREST' && command.args.enemy_id === item.id && ['PENDING', 'RUNNING', 'WAITING'].includes(command.state))));
    if (enemy) {
      await page.locator('#toggle-execution').click();
      await mode('PLANNING');
      const candidates = state.units.filter(unit => unit.hp > 0 && !unit.commands.some(command => command.type === 'ARREST' && ['PENDING', 'RUNNING', 'WAITING'].includes(command.state)))
        .sort((a, b) => Math.hypot(a.x - enemy.x, a.z - enemy.z) - Math.hypot(b.x - enemy.x, b.z - enemy.z));
      if (candidates.length) { await secureActor(candidates[0].id, enemy.id, true); arrests.add(enemy.id); }
      await page.locator('#toggle-execution').click();
      await mode('EXECUTING');
      state = await latest();
    }
    const pendingArrest = state.units.some(unit => unit.commands.some(command => command.type === 'ARREST' && ['PENDING', 'RUNNING', 'WAITING'].includes(command.state)));
    if (state.time >= target && !pendingArrest) break;
    await page.waitForTimeout(120);
  }
  state = await latest();
  assert(Date.now() < deadline, `${name} did not finish`);
  if (state.mode === 'EXECUTING') { await page.locator('#toggle-execution').click(); await mode('PLANNING'); }
  report.phases.push({ name, time: state.time, neutralized: state.objectives.neutralized, arrests: state.arrests });
  console.log(`PASS M01 toolbar ${name} time=${state.time.toFixed(1)} neutralized=${state.objectives.neutralized} arrests=${state.arrests}`);
}

try {
  await page.goto(url, { waitUntil: 'domcontentloaded' });
  await page.evaluate(() => document.addEventListener('keydown', event => { window.houseToolbarQA.keyTrace.push({ key: event.key, code: event.code, target: event.target.id, active: document.activeElement?.id }); }, true));
  await page.waitForFunction(() => !document.querySelector('#start-mission').disabled, null, { timeout: 120000 });
  await page.locator('#title-start').click();
  await page.locator('#tab-M01').waitFor({ state: 'visible' });
  await page.locator('#tab-M01').click();
  await page.locator('#select-to-briefing').click();
  await setCycler(page, '[data-cycler="difficulty"]', 'normal');
  await setCycler(page, '[data-cycler="variant"]', 'standard');
  await setCycler(page, '[data-cycler="seedmode"]', 'fixed');
  await clearModifiers(page);
  await page.locator('#start-mission').click();
  await mode('PLANNING');
  const initial = await latest();
  assert.equal(initial.mission, 'M01'); assert.equal(initial.seed, 1049); assert.equal(initial.variant, 'normal');
  assert.equal(initial.units.length, 4); assert.deepEqual(initial.modifiers, []);
  assert(await page.evaluate(() => Object.values(window.houseToolbarQA.catalog).every(mission => !('enemies' in mission) && !('civilians' in mission) && !('spawns' in mission))));
  await page.screenshot({ path: `${out}/planning.png` });
  pass('Fresh M01 standard mission uses fixed seed 1049, no modifiers and four operatives');

  await plan('alpha', 11.2, 13.6, 12, 10, 'd1'); await phase('front_door', 5.5);
  await plan('bravo', 13.2, 13.6, 15, 13.6); await phase('second_operator_entry', 4.5);
  await plan('charlie', 11.8, 15.6, 9, 13.6); await plan('delta', 13, 15.6, 15, 13.6); await phase('support_entry', 5);
  await plan('alpha', 7.7, 12.2, 4.8, 11.6, 'd2'); await plan('bravo', 16.6, 12.1, 19.5, 12, 'd3'); await phase('living_and_kitchen', 7);
  await plan('alpha', 6.6, 6.2, 4.4, 8.5, 'd7'); await plan('charlie', 12, 7, 13, 4.8, 'd4'); await phase('bedroom_and_study', 8);
  await plan('alpha', 7.5, 6.5, 7.5, 4); await phase('observe_first_civilian', 2.5);
  await secureActor('alpha', 'c1'); await plan('charlie', 17, 7, 19.3, 7.5, 'd6'); await phase('guest_room', 7);
  await plan('charlie', 19.2, 6.7, 19.8, 4.5); await phase('observe_second_civilian', 2.5);
  await secureActor('charlie', 'c2'); await phase('rescue', 8);

  const house = await latest();
  assert.equal(house.mode, 'RESULT'); assert.equal(house.result.success, true);
  assert.equal(house.result.survivors, 4); assert.equal(house.result.kills, 0); assert.equal(house.result.arrests, 6);
  assert.equal(house.result.rescued, 2); assert.equal(house.result.command_failures, 0);
  report.result = house.result;
  report.contextPopoverUsage = await page.evaluate(() => window.houseToolbarQA.contextMessages);
  assert.equal(report.contextPopoverUsage, 0);
  await page.screenshot({ path: `${out}/M01-toolbar-no-kills.png` });
  pass('M01 numeric keys and toolbar complete with four survivors, six arrests, two civilians and zero context popovers');

  await page.locator('#watch-replay').click(); await mode('REPLAY');
  const [download] = await Promise.all([page.waitForEvent('download'), page.locator('#export-replay').click()]);
  const replayPath = `${out}/M01-toolbar-no-kills.replay.json`; await download.saveAs(replayPath);
  const replay = JSON.parse(await readFile(replayPath, 'utf8'));
  assert.equal(replay.schema_version, 1); assert.equal(replay.map_id, 'M01'); assert.equal(replay.seed, 1049); assert(replay.frames.length > 1);
  report.replayBytes = (await readFile(replayPath)).length;
  await page.screenshot({ path: `${out}/replay.png` });
  pass('Ordinary replay export retains M01 fixed seed and recorded frames');
  assert.deepEqual(errors, []); assert.deepEqual(failedRequests, []);
  report.status = 'passed';
} catch (error) {
  report.status = 'failed'; report.error = error.stack;
  report.lastState = await latest().catch(() => null);
  report.messages = await page.evaluate(() => window.houseToolbarQA.messages.filter(message => !['ready', 'catalog_update'].includes(message.type))).catch(() => []);
  report.contextPopoverUsage = await page.evaluate(() => window.houseToolbarQA.contextMessages).catch(() => null);
  await page.screenshot({ path: `${out}/failure.png` }).catch(() => {});
  console.error(error); process.exitCode = 1;
} finally {
  report.keyTrace = await page.evaluate(() => window.houseToolbarQA.keyTrace).catch(() => []);
  report.finishedAt = new Date().toISOString();
  await writeFile(`${out}/report.json`, JSON.stringify(report, null, 2));
  await browser.close();
}
