import { chromium } from 'playwright';
import assert from 'node:assert/strict';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { setCycler, backToTitle, clearModifiers } from './lib/menu.mjs';

// All actions use the shipped DOM and canvas. The bridge wrapper only observes
// public messages; this suite never injects commands, results or enemy positions.
const url = process.env.BREACH_URL || 'http://127.0.0.1:8081';
const out = process.env.BREACH_ARTIFACTS || 'tests/artifacts/sustained-browser';
await mkdir(out, { recursive: true });
const browser = await chromium.launch({ channel: process.env.BREACH_CHANNEL || 'chrome', headless: process.env.BREACH_HEADLESS !== '0', args: ['--enable-unsafe-swiftshader'] });
const context = await browser.newContext({ viewport: { width: 1440, height: 900 }, acceptDownloads: true });
await context.addInitScript(() => {
  let ui;
  window.sustainedQA = { state: null, messages: [], catalog: {} };
  Object.defineProperty(window, 'BreachUI', {
    configurable: true, get: () => ui,
    set(value) {
      ui = value;
      const receive = value.receive;
      value.receive = function(raw) {
        const message = JSON.parse(raw);
        if (message.type === 'state') window.sustainedQA.state = message;
        else {
          window.sustainedQA.messages.push(message);
          if (window.sustainedQA.messages.length > 300) window.sustainedQA.messages.shift();
        }
        if (message.type === 'ready') window.sustainedQA.catalog = message.catalog || {};
        if (message.type === 'catalog_update') Object.assign(window.sustainedQA.catalog, message.catalog || {});
        return receive.call(this, raw);
      };
    }
  });
});
const page = await context.newPage();
const errors = [];
page.on('pageerror', error => errors.push(error.message));
page.on('console', message => { if (message.type() === 'error' || /SCRIPT ERROR|Parse Error|Failed loading resource/.test(message.text())) errors.push(message.text()); });
page.on('response', response => { if (response.status() >= 400) errors.push(`HTTP ${response.status()} ${response.url()}`); });
const report = { url, startedAt: new Date().toISOString(), checks: [], errors, limitations: ['Uses native Chrome canvas and DOM actions; Does not measure hardware rendering performance.'] };
const latest = () => page.evaluate(() => window.sustainedQA.state);
const wait = (predicate, argument = null) => page.waitForFunction(predicate, argument, { timeout: 60000 });
const mode = expected => wait(value => window.sustainedQA.state?.mode === value, expected);
const pass = name => { report.checks.push(name); console.log(`PASS ${name}`); };
async function returnMenu() {
  const current = await latest();
  if (current?.mode === 'REPLAY') await page.locator('#replay-hud [data-action="menu"]').click();
  else if (current?.mode === 'RESULT') await page.locator('#result [data-action="menu"]').click();
  else await page.locator('.hud-brand[data-action="menu"]').click();
  await mode('MENU');
}
// Reproduce the public camera framing from authored rooms/walls and viewport.
// It uses the menu catalog only, never simulation internals or hidden enemies.
async function project(x, z, y = 0.25) {
  return page.evaluate(({ x, z, y }) => {
    const state = window.sustainedQA.state, data = window.sustainedQA.catalog[state.mission];
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
    const fraction = Math.max(0.4, Math.min(0.87, (height - 190) / height));
    const size = Math.max(((bottom - top) * 0.905 + 1.1) / fraction, (right - left + 0.75) / Math.max(width / height - 0.12, 0.65));
    const centerX = (left + right) / 2, centerZ = (top + bottom) / 2 + size * 0.030 / 0.905;
    const norm = Math.hypot(34, 15.5), upY = 15.5 / norm, upZ = -34 / norm;
    return { x: canvas.left + width / 2 + (x - centerX) * height / size, y: canvas.top + height / 2 - (y * upY + (z - centerZ) * upZ) * height / size };
  }, { x, z, y });
}
async function mapClick(x, z, options = {}, y = 0.25) { const position = await project(x, z, y); await page.mouse.click(position.x, position.y, options); }
async function activeUnit() { const state = await latest(); return state.units.find(unit => unit.id === state.selected); }
async function moveTo(x, z) { await mapClick(x, z, { button: 'right' }); await wait(() => window.sustainedQA.state?.units.find(unit => unit.id === window.sustainedQA.state.selected)?.commands.some(command => command.type === 'MOVE' && command.state === 'PENDING')); }
async function doorContext(id) {
  const door = (await latest()).doors.find(item => item.id === id);
  assert(door?.observed !== false, `${id} must first be observed by the actual operative`);
  await mapClick(door.x, door.z, { button: 'right' }, 0.7);
  await page.locator('#context-popover').waitFor({ state: 'visible' });
  assert.match(await page.locator('#context-popover').textContent(), /문/);
}
async function runUntil(predicate) { await page.locator('#toggle-execution').click(); await wait(predicate); if ((await latest()).mode === 'EXECUTING') { await page.locator('#toggle-execution').click(); await mode('PLANNING'); } }

async function mouseSelect(id) { await page.locator(`[data-unit="${id}"]`).click(); await wait(expected => window.sustainedQA.state?.selected === expected, id); }
async function mouseFaceAfterMove(x, z) {
  const unit = await activeUnit(), move = unit.commands.findLast(command => command.type === 'MOVE' && command.state === 'PENDING');
  assert(move, 'Facing gesture requires its pending map node');
  const start = await project(...move.args.target), end = await project(x, z);
  await page.mouse.move(start.x, start.y); await page.mouse.down({ button: 'right' }); await page.mouse.move(end.x, end.y, { steps: 8 }); await page.mouse.up({ button: 'right' });
  await wait(() => window.sustainedQA.state?.units.find(unit => unit.id === window.sustainedQA.state.selected)?.commands.some(command => command.type === 'FACE' && command.state === 'PENDING'));
}
async function mousePlan(id, x, z, faceX, faceZ, doorId = null) {
  await mouseSelect(id);
  if (doorId) { await doorContext(doorId); await page.locator('#context-popover button').filter({ hasText: '조용히 열기' }).click(); }
  await moveTo(x, z); await mouseFaceAfterMove(faceX, faceZ);
}
async function mouseSecure(unitId, civilianId) {
  await mouseSelect(unitId); const civilian = (await latest()).civilians.find(item => item.id === civilianId && item.visible);
  assert(civilian, `${civilianId} must be observed before its context action`);
  await mapClick(civilian.x, civilian.z, {button:'right'}, 0.95);
  await page.locator('#context-popover button').filter({hasText:'민간인 확보'}).click();
}
async function mousePhase(name, seconds) {
  let state = await latest(); const target = state.time + seconds, deadline = Date.now() + 90000;
  const arrests = new Set(); await page.locator('#toggle-execution').click();
  while (Date.now() < deadline) {
    state = await latest(); if (state.mode === 'RESULT') break;
    assert.equal(state.command_failures, 0, `${name} public command failure`);
    const enemy = state.enemies.find(item => item.visible && item.status === 'SURRENDERED' && !arrests.has(item.id) && !state.units.some(unit => unit.commands.some(command => command.type === 'ARREST' && command.args.enemy_id === item.id && ['PENDING','RUNNING','WAITING'].includes(command.state))));
    if (enemy) {
      await page.locator('#toggle-execution').click(); await mode('PLANNING');
      const candidates = state.units.filter(unit => unit.hp > 0 && !unit.commands.some(command => command.type === 'ARREST' && ['PENDING','RUNNING','WAITING'].includes(command.state)))
        .sort((a,b)=>Math.hypot(a.x-enemy.x,a.z-enemy.z)-Math.hypot(b.x-enemy.x,b.z-enemy.z));
      if (candidates.length) {
        await mouseSelect(candidates[0].id); await mapClick(enemy.x, enemy.z, {button:'right'}, 0.95);
        await page.locator('#context-popover button').filter({hasText:'체포'}).click(); arrests.add(enemy.id);
      }
      await page.locator('#toggle-execution').click();
      state = await latest();
    }
    const pendingArrest = state.units.some(unit => unit.commands.some(command => command.type === 'ARREST' && ['PENDING','RUNNING','WAITING'].includes(command.state)));
    if (state.time >= target && !pendingArrest) break;
    await page.waitForTimeout(120);
  }
  state = await latest(); assert(Date.now() < deadline, `${name} did not finish`);
  if (state.mode === 'EXECUTING') { await page.locator('#toggle-execution').click(); await mode('PLANNING'); }
  console.log(`PASS M01 ${name} time=${state.time.toFixed(1)} neutralized=${state.objectives.neutralized} arrests=${state.arrests}`);
}

try {
  await page.goto(url, { waitUntil: 'domcontentloaded' });
  await page.evaluate(() => document.addEventListener('keydown', event => { window.sustainedQA.keyTrace ||= []; window.sustainedQA.keyTrace.push({key:event.key,code:event.code,target:event.target.id,active:document.activeElement?.id}); }, true));
  await page.waitForFunction(() => !document.querySelector('#start-mission').disabled, null, { timeout: 120000 });
  if (process.env.BREACH_HOUSE_ONLY !== '1') {
  const publicCatalog = await page.evaluate(() => window.sustainedQA.catalog); assert.equal(Object.keys(publicCatalog).length, 22); assert(Object.values(publicCatalog).every(mission => !('enemies' in mission) && !('civilians' in mission) && !('spawns' in mission)));
  await page.locator('#title-start').click();
  await page.locator('#tab-T01').waitFor({ state: 'visible' });
  await page.locator('#tab-T01').click();
  await page.locator('#select-to-briefing').click();
  for (const seedMode of ['fixed', 'random', 'daily', 'custom']) { await setCycler(page, '[data-cycler="seedmode"]', seedMode); assert.match(await page.locator('#seed-preview').textContent(), /시드/); }
  await page.locator('#custom-seed').fill('20261007');
  await page.locator('#custom-seed').press('Tab');
  await page.locator('#start-mission').click(); await mode('PLANNING');
  assert.equal((await latest()).seed, 20261007);
  assert.match(await page.locator('#hud-code').textContent(), /20261007/);
  if (await page.locator('#tutorial-close').isVisible()) await page.locator('#tutorial-close').click();
  pass('Catalog 22 missions and all four seed modes; custom seed reaches HUD');

  for (let attempt = 0; attempt < 3; attempt++) {
    await page.locator('[data-unit="alpha"]').click(); await wait(() => window.sustainedQA.state?.selected === 'alpha');
    await page.locator('#canvas').focus(); await page.keyboard.press('KeyF'); await mapClick(6,8);
    await wait(() => window.sustainedQA.state?.selected === 'alpha' && window.sustainedQA.state.units[0].commands.some(command=>command.type==='FACE'&&command.state==='PENDING'));
    await page.keyboard.press('Delete'); await wait(() => !window.sustainedQA.state?.units[0].commands.some(command=>command.state==='PENDING'));
  }
  pass('Rapid F plus map click preserves input ordering in three repetitions without a held-key workaround');
  await moveTo(6.1, 12.5);
  let unit = await activeUnit(), index = unit.commands.findLastIndex(command => command.type === 'MOVE' && command.state === 'PENDING');
  const oldTarget = unit.commands[index].args.target;
  let source = await project(...oldTarget), destination = await project(6.2, 12.2);
  await page.mouse.move(source.x, source.y); await page.mouse.down(); await page.mouse.move(destination.x, destination.y, { steps: 10 }); await page.mouse.up();
  await wait(expected => { const state = window.sustainedQA.state, unit = state?.units.find(item => item.id === state.selected); return unit?.commands[expected.index]?.args.target[1] < 12.4; }, { index });
  assert.equal((await latest()).selected_command, index);
  unit = await activeUnit(); const editedTarget = unit.commands[index].args.target;
  source = await project(...editedTarget); destination = await project(6.4, 13);
  await page.mouse.move(source.x, source.y); await page.mouse.down(); await page.mouse.move(destination.x, destination.y, { steps: 6 }); await page.keyboard.press('Escape'); await page.mouse.up();
  await page.waitForTimeout(100); // Observe the committed snapshot after the immediate release.
  assert.deepEqual((await activeUnit()).commands[index].args.target, editedTarget);
  await mapClick(...editedTarget, { button: 'right' });
  await page.locator('#context-popover button').filter({ hasText: '3초 대기' }).click();
  await wait(() => window.sustainedQA.state?.units[0].commands.some(command => command.type === 'WAIT'));
  source = await project(...editedTarget); destination = await project(7.8, 10);
  await page.mouse.move(source.x, source.y); await page.mouse.down({ button: 'right' }); await page.mouse.move(destination.x, destination.y, { steps: 8 }); await page.mouse.up({ button: 'right' });
  await wait(() => window.sustainedQA.state?.units[0].commands.some(command => command.type === 'FACE'));
  pass('Waypoint click/drag, Esc rollback, wait insertion and right-drag facing');

  unit = await activeUnit(); source = await project(unit.x, unit.z, 0.95);
  await page.mouse.move(source.x, source.y); await page.mouse.down();
  for (const [x, z] of [[5.9, 16], [6.1, 14], [6.2, 11.7]]) { destination = await project(x, z); await page.mouse.move(destination.x, destination.y, { steps: 10 }); }
  await page.mouse.up();
  await wait(() => window.sustainedQA.state?.units[0].commands.filter(command => command.state === 'PENDING' && command.type === 'MOVE').length >= 2);
  assert((await activeUnit()).commands.filter(command => !['SUCCEEDED', 'CANCELLED'].includes(command.state)).length <= 32);
  pass('Operative drag draws a validated route with bounded pending commands');

  await page.locator('#save-plan').click();
  await page.waitForFunction(() => document.querySelector('#toasts').textContent.includes('저장했습니다'));
  await page.locator('#deck-more').click();
  const [planDownload] = await Promise.all([page.waitForEvent('download'), page.locator('#export-plan').click()]);
  const planPath = `${out}/shared-plan.json`; await planDownload.saveAs(planPath);
  const plan = JSON.parse(await readFile(planPath, 'utf8')); assert.equal(plan.seed, 20261007); assert(plan.roster.length === 2);
  await page.locator('#import-plan').click(); await page.locator('#file-import').setInputFiles(planPath); await mode('PLANNING');
  await wait(() => window.sustainedQA.state?.seed === 20261007 && window.sustainedQA.state?.time === 0);
  pass('Ordinary plan save/export/file import restores seed, roster and commands');

  await runUntil(() => window.sustainedQA.state?.objectives.neutralized >= 1);
  await doorContext('d1');
  await page.locator('#context-popover button').filter({ hasText: '들여다보기' }).click();
  await runUntil(() => window.sustainedQA.state?.events.some(event => event.type === 'DOOR_PEEK'));
  assert.equal((await latest()).doors.find(door => door.id === 'd1').state, 'CLOSED');
  await page.locator('#toggle-execution').click(); await mode('EXECUTING');
  await doorContext('d1'); await mode('PLANNING');
  const frozen = (await latest()).time; await page.waitForTimeout(250); assert.equal((await latest()).time, frozen);
  await page.locator('#context-popover button').filter({ hasText: '문 차기' }).click();
  await runUntil(() => window.sustainedQA.state?.doors.some(door => door.id === 'd1' && door.state === 'OPEN'));
  await doorContext('d1');
  assert.equal(await page.locator('#context-popover button').filter({ hasText: '문 차기' }).isDisabled(), true);
  assert.equal(await page.locator('#context-popover button').filter({ hasText: '들여다보기' }).isDisabled(), true);
  await page.keyboard.press('Escape');
  await page.screenshot({ path: `${out}/door-actions.png` });
  pass('Door peek stays closed; executing context pauses; kick opens and disables unavailable actions');

  await moveTo(12, 10.9); await page.keyboard.press('KeyF'); await wait(() => window.sustainedQA.state?.tool==='face'); await mapClick(12, 7); await runUntil(() => window.sustainedQA.state?.objectives.neutralized >= 2);
  await page.keyboard.press('KeyF'); await wait(() => window.sustainedQA.state?.tool==='face'); await mapClick(16, 10);
  await runUntil(() => window.sustainedQA.state?.doors.some(door => door.id === 'd2' && door.observed));
  await doorContext('d2'); await page.locator('#context-popover button').filter({ hasText: '문 차기' }).click();
  await runUntil(() => window.sustainedQA.state?.doors.some(door => door.id === 'd2' && door.state === 'OPEN'));
  await moveTo(18.2, 10.9); await page.keyboard.press('KeyF'); await wait(() => window.sustainedQA.state?.tool==='face'); await mapClick(18.4, 7.7); await runUntil(() => window.sustainedQA.state?.mode === 'RESULT');
  assert.equal((await latest()).result.success, true);
  report.result = (await latest()).result;
  await page.locator('#watch-replay').click(); await mode('REPLAY');
  await page.locator('#replay-toggle').click(); await page.locator('[data-speed="4"]').click(); await page.locator('[data-reveal="true"]').click();
  await page.locator('#replay-seek').fill('0'); await page.locator('#replay-seek').dispatchEvent('input');
  await mapClick(9, 10, { button: 'right' }, 0.7); assert.equal(await page.locator('#context-popover').isVisible(), false);
  const [replayDownload] = await Promise.all([page.waitForEvent('download'), page.locator('#export-replay').click()]);
  const replayPath = `${out}/shared-replay.json`; await replayDownload.saveAs(replayPath);
  const replay = JSON.parse(await readFile(replayPath, 'utf8')); assert.equal(replay.seed, 20261007);
  assert(replay.events.some(event => (event.type === 'DOOR_KICK' || event.type === 'DOOR_ACTION' && event.kind === 'KICK_DOOR') && event.radius === 9) && replay.events.some(event => event.type === 'DOOR_PEEK'));
  await page.locator('#replay-library').click(); await page.locator('#import-replay').click(); await page.locator('#file-import').setInputFiles(replayPath); await mode('REPLAY');
  await page.screenshot({ path: `${out}/replay.png` });
  pass('Actual T01 completion and replay export/import retain door actions and seed; replay blocks popovers');

  await returnMenu(); await backToTitle(page); await page.locator('#title-start').click();
  await page.locator('#tab-M01').waitFor({ state: 'visible' }); await page.locator('#tab-M01').click(); await page.locator('#select-to-briefing').click();
  await setCycler(page, '[data-cycler="difficulty"]', 'normal');
  await setCycler(page, '[data-cycler="variant"]', 'timed'); assert.match(await page.locator('#brief-objectives').textContent(), /25|시간/);
  await backToTitle(page); await page.locator('#title-daily').click();
  await page.locator('#seed-preview').waitFor({ state: 'visible' });
  const dailySeed = Number((await page.locator('#seed-preview').textContent()).match(/시드\s+(\d+)/)[1]);
  await page.locator('#start-mission').click(); await mode('PLANNING'); assert.equal((await latest()).seed, dailySeed);
  await returnMenu(); await backToTitle(page); await page.locator('#title-campaign').click(); await page.locator('#new-ironman').click();
  await wait(() => /아이언맨/.test(document.querySelector('#campaign-summary').textContent));
  assert.match(await page.locator('#campaign-summary').textContent(), /아이언맨/);
  await page.reload({ waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => !document.querySelector('#start-mission').disabled, null, { timeout: 120000 });
  await page.locator('#title-campaign').click(); assert.match(await page.locator('#campaign-body').textContent(), /현재 캠페인 계속/);
  await page.locator('#leave-campaign').click();
  pass('Mission type rules, daily operation seed and campaign survive ordinary menus and reload');

  await backToTitle(page); await page.locator('#title-editor').click();
  await page.locator('[data-editor-title]').fill('UI 공유 지도'); await page.locator('[data-editor-title]').press('Tab');
  await page.locator('[data-editor-play]').click(); await mode('PLANNING');
  assert.equal((await latest()).mission, 'EDIT_CUSTOM'); assert.equal((await latest()).units.length, 1);
  await page.screenshot({ path: `${out}/custom-map.png` });
  pass('Map editor launches its validated local mission through the ordinary UI');
  }

  if ((await latest()).mode !== 'MENU') await returnMenu();
  await backToTitle(page); await page.locator('#title-start').click();
  await page.locator('#tab-M01').waitFor({ state: 'visible' }); await page.locator('#tab-M01').click(); await page.locator('#select-to-briefing').click();
  await setCycler(page, '[data-cycler="difficulty"]', 'normal');
  await setCycler(page, '[data-cycler="variant"]', 'standard'); await setCycler(page, '[data-cycler="seedmode"]', 'fixed');
  await clearModifiers(page);
  await page.locator('#start-mission').click(); await mode('PLANNING');
  await mousePlan('alpha',11.2,13.6,12,10,'d1'); await mousePhase('front_door',5.5);
  await mousePlan('bravo',13.2,13.6,15,13.6); await mousePhase('second_operator_entry',4.5);
  await mousePlan('charlie',11.8,15.6,9,13.6); await mousePlan('delta',13,15.6,15,13.6); await mousePhase('support_entry',5);
  await mousePlan('alpha',7.7,12.2,4.8,11.6,'d2'); await mousePlan('bravo',16.6,12.1,19.5,12,'d3'); await mousePhase('living_and_kitchen',7);
  await mousePlan('alpha',6.6,6.2,4.4,8.5,'d7'); await mousePlan('charlie',12,7,13,4.8,'d4'); await mousePhase('bedroom_and_study',8);
  await mousePlan('alpha',7.5,6.5,7.5,4); await mousePhase('observe_first_civilian',2.5);
  await mouseSecure('alpha','c1'); await mousePlan('charlie',17,7,19.3,7.5,'d6'); await mousePhase('guest_room',7);
  await mousePlan('charlie',19.2,6.7,19.8,4.5); await mousePhase('observe_second_civilian',2.5);
  await mouseSecure('charlie','c2'); await mousePhase('rescue',8);
  const house = await latest(); assert.equal(house.mode,'RESULT'); assert.equal(house.result.success,true); assert.equal(house.result.kills,0); assert.equal(house.result.arrests,6);
  report.house = {result:house.result, input:'Mouse cards, map moves, map facing drag, contextual doors/arrests/civilian secure; toolbar 0 and modal 0'};
  await page.waitForTimeout(4500);
  await wait(() => document.querySelector('#toasts').children.length === 0);
  await page.screenshot({path:`${out}/M01-mouse-only-no-kills.png`});
  await page.locator('#watch-replay').click(); await mode('REPLAY');
  const [houseReplayDownload] = await Promise.all([page.waitForEvent('download'),page.locator('#export-replay').click()]);
  await houseReplayDownload.saveAs(`${out}/M01-mouse-only-no-kills.replay.json`);
  pass('M01 mouse only completion with no kills, contextual arrests and saved replay');
  assert.deepEqual(errors, []);
  report.status = 'passed';
} catch (error) {
  report.status = 'failed'; report.error = error.stack; report.lastState = await latest().catch(() => null);
  report.messages = await page.evaluate(() => window.sustainedQA.messages).catch(() => []); report.keyTrace = await page.evaluate(() => window.sustainedQA.keyTrace).catch(() => []);
  await page.screenshot({ path: `${out}/failure.png` }).catch(() => {});
  console.error(error); process.exitCode = 1;
} finally {
  await writeFile(`${out}/report.json`, JSON.stringify(report, null, 2)); await browser.close();
}
