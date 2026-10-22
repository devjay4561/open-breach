import { chromium } from 'playwright';
import assert from 'node:assert/strict';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { setCycler } from './lib/menu.mjs';

// P1 exercises the shipped engine and DOM. The imported, fixed-seed room has
// no combatants, so menu/resource/plan contracts cannot depend on AI timing.
// All waits observe real messages or DOM state; no elapsed delay is a pass condition.
const url = process.env.BREACH_URL || 'http://127.0.0.1:8080';
const out = process.env.BREACH_ARTIFACTS || 'tests/artifacts/cqb-contact-browser';
await mkdir(out, { recursive: true });
const browser = await chromium.launch({
  channel: process.env.BREACH_CHANNEL || 'chrome', headless: process.env.BREACH_HEADLESS !== '0',
  args: ['--enable-unsafe-swiftshader'],
});
const context = await browser.newContext({ viewport: { width: 1440, height: 900 }, acceptDownloads: true });
await context.addInitScript(() => {
  let ui;
  window.cqbContactQA = { state: null, states: 0, messages: [], plans: [], catalog: {}, sent: [] };
  Object.defineProperty(window, 'BreachUI', {
    configurable: true, get: () => ui,
    set(value) {
      ui = value;
      const receive = value.receive;
      value.receive = function(raw) {
        const message = typeof raw === 'string' ? JSON.parse(raw) : raw;
        const qa = window.cqbContactQA;
        if (message.type === 'state') { qa.state = message; qa.states++; }
        else {
          qa.messages.push(message);
          if (qa.messages.length > 500) qa.messages.shift();
        }
        if (message.type === 'plan_data') qa.plans.push(message.data);
        if (['ready', 'catalog_update'].includes(message.type)) Object.assign(qa.catalog, message.catalog || {});
        return receive.call(this, raw);
      };
    },
  });
});
const page = await context.newPage();
const errors = [], failedRequests = [];
page.on('pageerror', error => errors.push(error.message));
page.on('console', message => {
  if (message.type() === 'error' || /SCRIPT ERROR|Parse Error|Failed loading resource/.test(message.text())) errors.push(message.text());
});
page.on('response', response => { if (response.status() >= 400) errors.push(`HTTP ${response.status()} ${response.url()}`); });
page.on('requestfailed', request => failedRequests.push({ url: request.url(), failure: request.failure()?.errorText }));
const report = { url, version: browser.version(), checks: [], warnings: [], failureToasts: [], errors, failedRequests };
const pass = name => { report.checks.push(name); console.log(`PASS ${name}`); };
const latest = () => page.evaluate(() => window.cqbContactQA.state);
const wait = (predicate, argument = null, timeout = 60000) => page.waitForFunction(predicate, argument, { timeout });
const send = data => page.evaluate(data => window.BreachBridge.send(JSON.stringify(data)), data);
const selectedUnit = async () => { const state = await latest(); return state.units.find(unit => unit.id === state.selected); };
const shotgunSelector = '[data-door-mode="SHOTGUN_BREACH"]';
const fallbackSelector = '[data-door-mode="KICK_DOOR"][data-door-fallback="breach"]';
const plainKickSelector = '[data-door-mode="KICK_DOOR"]:not([data-door-fallback])';

function fixture() {
  const unit = (id, x, z, weapon, ammo, breaches) => ({
    id, name: id.toUpperCase(), role: 'TEST', x, z, facing: 0, weapon, ammo,
    reserve_ammo: 0, equipment: { breach: breaches }, breaches, stuns: 0, smokes: 0,
    sidearm: 'pico_p1', armor: 'none', helmet: 'none', stance: 'standing', movement_mode: 'normal',
  });
  return {
    schema_version: 3, id: 'CQB_CONTACT_UI', revision: 1, title: '문 처리 검증', title_en: 'Door Contact Check',
    description: '고정 시드 문 처리 검증 방입니다.', description_en: 'Fixed-seed door contract room.',
    seed: 42, default_seed: 42, bounds: [18, 14], focus: [9, 7], custom: true,
    rooms: [
      { id: 'ready_room', x: 5, z: 7, w: 8, d: 12, label: 'READY', indoor: true, lighting: 1 },
      { id: 'target_room', x: 13, z: 7, w: 8, d: 12, label: 'ROOM', indoor: true, lighting: 1 },
    ],
    walls: [
      { id: 'north', x: 9, z: 1, w: 16, d: 0.24 }, { id: 'south', x: 9, z: 13, w: 16, d: 0.24 },
      { id: 'west', x: 1, z: 7, w: 0.24, d: 12 }, { id: 'east', x: 17, z: 7, w: 0.24, d: 12 },
      { id: 'partition_a', x: 9, z: 2.2, w: 0.24, d: 2.4 },
      { id: 'partition_b', x: 9, z: 5.5, w: 0.24, d: 1.8 },
      { id: 'partition_c', x: 9, z: 8.5, w: 0.24, d: 1.8 },
      { id: 'partition_d', x: 9, z: 11.8, w: 0.24, d: 2.4 },
    ].map(wall => ({ ...wall, material: 'concrete', height: 2.8 })),
    doors: [4, 7, 10].map((z, index) => ({
      id: `d${index + 1}`, x: 9, z, w: 0.24, d: 1.2, axis: 'z', label: `DOOR ${index + 1}`,
      state: 'CLOSED', material: 'wood', height: 2.1, hp: 100, locked: false,
      hinge_side: -1, swing_sign: -1, kick_resistance: 0, reinforced: false,
    })),
    props: [], units: [
      unit('alpha', 7.7, 6.8, 'shotgun', 2, 2), unit('bravo', 7.25, 7.9, 'standard', 24, 1),
      unit('charlie', 6.4, 5.7, 'shotgun', 0, 0), unit('delta', 6.1, 8.8, 'shotgun', 1, 0),
    ],
    enemies: [], civilians: [], objectives: ['문 처리 명령을 검증하세요.'],
    win: [{ type: 'reach_zone', zone: [15.5, 11, 1, 1] }], fail: [], stars: [],
    variant: 'normal', modifiers: [], environment: { time_of_day: 'day', lighting: 1 },
  };
}

async function loadFixture() {
  const before = await page.evaluate(() => window.cqbContactQA.states);
  await send({ action: 'import_mission', data: fixture() });
  await wait(before => {
    const qa = window.cqbContactQA, state = qa.state;
    return qa.states > before && state?.mode === 'PLANNING' && state.mission === 'CQB_CONTACT_UI'
      && state.time === 0 && state.units.length === 4 && state.units.every(unit => !unit.commands.length)
      && state.units.find(unit => unit.id === 'alpha')?.ammo === 2;
  }, before);
  assert.equal((await latest()).seed, 42);
  assert.equal((await latest()).door_fallback, '');
}
async function selectUnit(id) {
  await page.locator(`.unit-card[data-unit="${id}"]`).click();
  await wait(id => window.cqbContactQA.state?.selected === id, id);
}
async function showDoorMenu() {
  if (!(await page.locator('#door-submenu').isVisible())) await page.locator('#door-modes').click();
  await page.locator('#door-submenu').waitFor({ state: 'visible' });
}
async function chooseDoorMode(selector, type, fallback = '') {
  await showDoorMenu();
  await page.locator(selector).click();
  await page.locator('#door-submenu').waitFor({ state: 'hidden' });
  await wait(({ type, fallback }) => {
    const state = window.cqbContactQA.state;
    return state?.tool === 'door' && state.door_mode === type && state.door_fallback === fallback;
  }, { type, fallback });
}

// Same public geometry and live HUD safe area used by world_view._fit_camera.
// Test input is an ordinary canvas click, never a hidden simulation mutation.
async function mapClick(x, z, y = 0.7) {
  const point = await page.evaluate(({ x, z, y }) => {
    const qa = window.cqbContactQA, data = qa.catalog[qa.state.mission];
    if (!data) throw new Error('Missing public mission geometry');
    const focus = data.focus || data.bounds.map(value => value / 2);
    let left = focus[0], right = focus[0], top = focus[1], bottom = focus[1];
    for (const rect of [...data.rooms, ...data.walls]) {
      left = Math.min(left, rect.x - rect.w / 2); right = Math.max(right, rect.x + rect.w / 2);
      top = Math.min(top, rect.z - rect.d / 2); bottom = Math.max(bottom, rect.z + rect.d / 2);
    }
    for (const unit of data.units) {
      left = Math.min(left, unit.x); right = Math.max(right, unit.x);
      top = Math.min(top, unit.z); bottom = Math.max(bottom, unit.z);
    }
    left -= 0.75; right += 0.75; top -= 0.75; bottom += 0.8;
    // Schema 2/3 maps use the complete metre footprint even for this small room.
    if (Number(data.schema_version || 1) >= 2) {
      left = -1; right = data.bounds[0] + 1; top = -1; bottom = data.bounds[1] + 1;
    }
    const canvas = document.querySelector('#canvas').getBoundingClientRect();
    const rightRect = document.querySelector('.hud-right').getBoundingClientRect();
    const inset = {
      left: Math.round(document.querySelector('.hud-left').getBoundingClientRect().width),
      top: Math.round(document.querySelector('.hud-topbar').getBoundingClientRect().height),
      right: Math.max(0, Math.round(innerWidth - Math.max(rightRect.left, 0))),
      bottom: Math.round(document.querySelector('.hud-hotbar').getBoundingClientRect().height),
    };
    const margin = 16, aspect = innerWidth / innerHeight;
    const safeLeft = inset.left + margin, safeRight = inset.right + margin;
    const safeTop = inset.top + margin, safeBottom = inset.bottom + margin;
    const vertical = Math.min(0.97, Math.max(0.25, (innerHeight - safeTop - safeBottom) / innerHeight));
    const horizontal = Math.min(0.97, Math.max(0.25, (innerWidth - safeLeft - safeRight) / innerWidth));
    const size = Math.max((bottom - top) / vertical, (right - left) / Math.max(aspect * horizontal, 0.1));
    const scale = canvas.height / size, norm = Math.hypot(34, 15.5);
    return {
      x: canvas.left + canvas.width / 2 + (x - (left + right) / 2) * scale + (safeLeft - safeRight) / 2,
      y: canvas.top + canvas.height / 2 - (y * 15.5 / norm - (z - (top + bottom) / 2) * 34 / norm) * scale + (safeTop - safeBottom) / 2,
    };
  }, { x, z, y });
  await page.mouse.click(point.x, point.y);
}
async function appendDoorOrder(doorId, type, fallback = '') {
  const unit = await selectedUnit(), before = unit.commands.length;
  const door = (await latest()).doors.find(door => door.id === doorId);
  assert(door && door.observed !== false, `${doorId} must be observed before clicking it`);
  await mapClick(door.x, door.z);
  await wait(({ id, before, type, doorId, fallback }) => {
    const commands = window.cqbContactQA.state?.units.find(unit => unit.id === id)?.commands;
    const order = commands?.[before];
    return commands?.length === before + 1 && order?.type === type && order.state === 'PENDING'
      && order.args.door_id === doorId && (order.args.fallback || '') === fallback;
  }, { id: unit.id, before, type, doorId, fallback });
  const order = (await selectedUnit()).commands.at(-1);
  assert.deepEqual(order.args, fallback ? { door_id: doorId, fallback } : { door_id: doorId });
  return order;
}
async function setLanguage(language) {
  await page.locator('.hud-topbar [data-open="settings"]').click();
  await page.locator('[data-settings-tab="gameplay"]').click();
  await setCycler(page, '[data-cycler="language"]', language);
  await wait(language => document.documentElement.lang === language, language);
  await page.locator('#modal-close').click();
  await page.locator('#modal').waitFor({ state: 'hidden' });
}
async function planFromButton() {
  const before = await page.evaluate(() => window.cqbContactQA.plans.length);
  await page.locator('#save-plan').click();
  await wait(before => window.cqbContactQA.plans.length > before, before);
  const plan = await page.evaluate(() => window.cqbContactQA.plans.at(-1));
  await wait(async expected => {
    const { BreachStorage } = await import('./storage.js');
    const storage = new BreachStorage(); await storage.open();
    try { return JSON.stringify((await storage.get('plans', expected.map_id))?.data) === JSON.stringify(expected); }
    finally { storage.database.close(); }
  }, plan);
  return plan;
}
async function assertPlanCommands(expected) {
  const state = await latest();
  assert.equal(state.mode, 'PLANNING'); assert.equal(state.time, 0); assert.equal(state.seed, 42);
  for (const unit of expected.units) {
    const actual = state.units.find(candidate => candidate.id === unit.id);
    assert(actual, `Missing restored ${unit.id}`);
    assert.deepEqual(actual.commands.map(command => ({ type: command.type, args: command.args })), unit.commands);
    for (const key of ['stance', 'movement_mode', 'hold_position']) assert.equal(actual[key], unit[key]);
  }
}

try {
  await page.goto(url, { waitUntil: 'domcontentloaded' });
  await wait(() => window.BreachBridge && !document.querySelector('#start-mission').disabled, null, 120000);
  // Use normal completion records to unlock shotgun equipment for plan import.
  await page.evaluate(async () => {
    const { BreachStorage } = await import('./storage.js');
    const storage = new BreachStorage(); await storage.open();
    try {
      for (const id of ['M01', 'M02', 'M03', 'M04']) await storage.put('progress', {
        id, kind: 'mission', completed: true, stars: { complete: true, no_hits: true },
      });
    } finally { storage.database.close(); }
  });
  await page.reload({ waitUntil: 'domcontentloaded' });
  await wait(() => window.BreachBridge && !document.querySelector('#start-mission').disabled, null, 120000);
  await page.evaluate(() => {
    const bridge = window.BreachBridge, send = bridge.send;
    bridge.send = function(raw) { window.cqbContactQA.sent.push(JSON.parse(raw)); return send.call(this, raw); };
  });
  await loadFixture();
  pass('Official imported schema 3 mission starts at seed 42 with observed doors and no combatants');

  await selectUnit('bravo'); await showDoorMenu();
  assert.equal((await selectedUnit()).available_shotgun_breaches, 0);
  assert.equal(await page.locator(shotgunSelector).isDisabled(), true);
  assert.equal((await selectedUnit()).available_breaches, 1);
  assert.equal(await page.locator(fallbackSelector).isDisabled(), false);
  await selectUnit('charlie'); await showDoorMenu();
  assert.equal((await selectedUnit()).ammo, 0);
  assert.equal((await selectedUnit()).available_shotgun_breaches, 0);
  assert.equal(await page.locator(shotgunSelector).isDisabled(), true);
  assert.equal((await selectedUnit()).available_breaches, 0);
  assert.equal(await page.locator(fallbackSelector).isDisabled(), true);
  pass('Standard primary and empty shotgun disable shotgun breach; charge-less operator disables fallback');

  await selectUnit('delta'); await showDoorMenu();
  assert.equal((await selectedUnit()).available_shotgun_breaches, 1);
  assert.equal(await page.locator(shotgunSelector).isDisabled(), false);
  await page.keyboard.press('Escape');
  await page.locator('#equipment-modes').click();
  await page.locator('#switch-weapon').click();
  await wait(() => window.cqbContactQA.state.units.find(unit => unit.id === 'delta')?.commands.at(-1)?.type === 'SWITCH_WEAPON');
  await showDoorMenu();
  assert.equal((await selectedUnit()).available_shotgun_breaches, 0);
  assert.equal(await page.locator(shotgunSelector).isDisabled(), true);
  await page.keyboard.press('Escape');
  await page.locator('#toggle-execution').click();
  await wait(() => {
    const delta = window.cqbContactQA.state?.units.find(unit => unit.id === 'delta');
    return delta?.active_weapon === 'secondary' && delta.commands.at(-1)?.state === 'SUCCEEDED';
  });
  await page.locator('#toggle-execution').click();
  await wait(() => window.cqbContactQA.state?.mode === 'PLANNING');
  await showDoorMenu();
  assert.equal((await selectedUnit()).active_weapon, 'secondary');
  assert.equal((await selectedUnit()).available_shotgun_breaches, 0);
  assert.equal(await page.locator(shotgunSelector).isDisabled(), true);
  pass('Projected and executed sidearm switch both disable shotgun breach');

  await page.keyboard.press('Escape'); await loadFixture(); await selectUnit('alpha');
  assert.equal((await selectedUnit()).available_shotgun_breaches, 2);
  await chooseDoorMode(shotgunSelector, 'SHOTGUN_BREACH');
  await appendDoorOrder('d1', 'SHOTGUN_BREACH');
  assert.equal((await selectedUnit()).available_shotgun_breaches, 1);
  await chooseDoorMode(shotgunSelector, 'SHOTGUN_BREACH');
  await appendDoorOrder('d3', 'SHOTGUN_BREACH');
  await showDoorMenu();
  assert.equal((await selectedUnit()).available_shotgun_breaches, 0);
  assert.equal(await page.locator(shotgunSelector).isDisabled(), true);
  await page.keyboard.press('Escape');
  await send({ action: 'remove', unit_id: 'alpha', index: 1 });
  await wait(() => window.cqbContactQA.state.units.find(unit => unit.id === 'alpha')?.commands.length === 1);
  assert.equal((await selectedUnit()).available_shotgun_breaches, 1);
  await page.locator('#toggle-execution').click();
  await wait(() => {
    const alpha = window.cqbContactQA.state?.units.find(unit => unit.id === 'alpha');
    return alpha?.ammo === 1 && ['RUNNING', 'WAITING'].includes(alpha.commands[0]?.state);
  });
  const consumed = await selectedUnit();
  assert.equal(consumed.available_shotgun_breaches, 1, 'Consumed running breach must not reserve its round twice');
  await page.locator('#toggle-execution').click();
  await wait(() => window.cqbContactQA.state?.mode === 'PLANNING');
  report.consumed = { ammo: consumed.ammo, available: consumed.available_shotgun_breaches, phase: consumed.commands[0].phase };
  pass('Two rounds reserve two breaches, deletion restores one, and consumed running breach is not double charged');

  for (const language of ['ko', 'en']) {
    await loadFixture(); await setLanguage(language); await selectUnit('bravo');
    const before = await page.evaluate(() => window.cqbContactQA.messages.length);
    await page.locator('#equipment-modes').click();
    await page.locator('#equipment-submenu [data-tool="breach"]').click();
    await wait(() => window.cqbContactQA.state?.tool === 'breach');
    await appendDoorOrder('d2', 'BREACH_DOOR');
    await wait(before => window.cqbContactQA.messages.slice(before).some(message => message.type === 'toast' && message.i18n_key === 'door.breach_safety'), before);
    const expected = await page.evaluate(async () => { const { t } = await import('./i18n.js'); return t('door.breach_safety'); });
    assert.notEqual(expected, 'door.breach_safety');
    assert.equal(/[가-힣]/.test(expected), language === 'ko');
    await wait(expected => [...document.querySelectorAll('#toasts .toast')].some(node => node.textContent === expected), expected);
    const warning = await page.evaluate(() => window.cqbContactQA.messages.filter(message => message.type === 'toast' && message.i18n_key === 'door.breach_safety').at(-1));
    assert.equal(warning.kind, 'warning');
    assert.equal((await selectedUnit()).available_breaches, 0);
    await showDoorMenu(); assert.equal(await page.locator(fallbackSelector).isDisabled(), true);
    report.warnings.push({ language, text: expected, key: warning.i18n_key });
    await page.screenshot({ path: `${out}/breach-warning-${language}.png` });
    await page.keyboard.press('Escape');
    pass(`Unsafe charge emits actual keyed ${language} warning and consumes only its plan reservation`);

    await page.locator('#toggle-execution').click();
    await wait(() => {
      const bravo = window.cqbContactQA.state?.units.find(unit => unit.id === 'bravo');
      return bravo?.commands[0]?.state === 'WAITING' && bravo.commands[0].phase === 'BREACH_SAFE_WAIT';
    });
    const waiting = await selectedUnit();
    assert.equal(waiting.commands[0].reason, '안전거리 안 대원의 후퇴를 기다리는 중');
    assert.equal(waiting.breaches, 0); assert.equal(waiting.available_breaches, 0);
    assert.equal((await latest()).doors.find(door => door.id === 'd2').destroyed, false);
    const waitingCopy = await page.evaluate(async () => {
      const { t, translateCommandReason } = await import('./i18n.js');
      return {
        reason: t('door.breach_waiting'), phase: t('phase.BREACH_SAFE_WAIT'),
        translated: translateCommandReason(window.cqbContactQA.state.units.find(unit => unit.id === 'bravo').commands[0].reason),
      };
    });
    assert.notEqual(waitingCopy.reason, 'door.breach_waiting');
    assert.notEqual(waitingCopy.phase, 'phase.BREACH_SAFE_WAIT');
    assert.equal(waitingCopy.translated, waitingCopy.reason);
    assert.equal(/[가-힣]/.test(waitingCopy.reason), language === 'ko');
    await wait(copy => {
      const card = document.querySelector('.unit-card[data-unit="bravo"] .unit-status');
      const description = document.querySelector('#command-list .command-row small');
      return card?.textContent === copy.reason && description?.textContent.includes(copy.phase);
    }, waitingCopy);
    await page.screenshot({ path: `${out}/breach-waiting-${language}.png` });
    await page.locator('#toggle-execution').click();
    await wait(() => window.cqbContactQA.state?.mode === 'PLANNING');
    pass(`Installed charge waits for the real unsafe teammate with translated ${language} card and phase`);

    await loadFixture(); await selectUnit('alpha');
    await chooseDoorMode(plainKickSelector, 'KICK_DOOR');
    await appendDoorOrder('d2', 'KICK_DOOR');
    const beforeFailure = await page.evaluate(() => window.cqbContactQA.messages.length);
    await page.locator('#toggle-execution').click();
    await wait(() => {
      const state = window.cqbContactQA.state;
      return state?.mode === 'PLANNING' && state.units.find(unit => unit.id === 'alpha')?.commands[0]?.state === 'FAILED';
    });
    const failed = await selectedUnit();
    assert.equal(failed.commands[0].reason, '문 차기에 실패했습니다. 다시 차거나 다른 방법을 선택하세요');
    assert.equal(failed.breaches, 2); assert.equal(failed.available_breaches, 2);
    const failedCopy = await page.evaluate(async () => {
      const { t, translateCommandReason, translateEvent } = await import('./i18n.js');
      const state = window.cqbContactQA.state, event = state.events.find(event => event.type === 'COMMAND_FAILED');
      return {
        reason: t('reason.kick_failed'), translated: translateCommandReason(state.units.find(unit => unit.id === 'alpha').commands[0].reason),
        event: event && translateEvent(event, { unitName: () => 'ALPHA' }),
        editHint: t('command.failed_edit_hint'),
      };
    });
    assert.notEqual(failedCopy.reason, 'reason.kick_failed');
    assert.equal(failedCopy.translated, failedCopy.reason);
    assert.equal(/[가-힣]/.test(failedCopy.reason), language === 'ko');
    assert(failedCopy.event?.includes(failedCopy.reason), 'Actual failure event must retain the localized cause');
    await wait(expected => {
      const card = document.querySelector('.unit-card[data-unit="alpha"] .unit-status');
      const description = document.querySelector('#command-list .command-row.failed small');
      const log = document.querySelector('#operation-log');
      return card?.textContent === expected && description?.textContent === expected && log?.textContent.includes(expected);
    }, failedCopy.reason);
    const nativeFailureHint = language === 'en'
      ? 'Stopped because a command failed. Delete the failed command in the queue, then revise the plan.'
      : '명령을 완료할 수 없어 정지했습니다. 명령 목록에서 실패 명령을 삭제한 뒤 다시 계획하세요.';
    assert.notEqual(failedCopy.editHint, 'command.failed_edit_hint');
    assert.equal(/[가-힣]/.test(failedCopy.editHint), language === 'ko');
    // Both hints come from the actual failure: web's command_failed handler
    // and main.gd's native stop toast. Inspect their visible lifecycle now.
    await wait(({ beforeFailure, nativeFailureHint, editHint }) => {
      const messages = window.cqbContactQA.messages.slice(beforeFailure);
      const toasts = [...document.querySelectorAll('#toasts .toast.warning')].filter(node => node.getClientRects().length);
      return messages.some(message => message.type === 'command_failed' && message.unit_id === 'alpha')
        && messages.some(message => message.type === 'toast' && message.message === nativeFailureHint && message.kind === 'warning')
        && toasts.some(node => node.textContent === nativeFailureHint)
        && toasts.some(node => node.textContent === editHint);
    }, { beforeFailure, nativeFailureHint, editHint: failedCopy.editHint });
    const visibleHints = await page.evaluate(expected => [...document.querySelectorAll('#toasts .toast.warning')]
      .filter(node => node.getClientRects().length && expected.includes(node.textContent)).map(node => node.textContent), [nativeFailureHint, failedCopy.editHint]);
    assert.equal(visibleHints.length, 2);
    assert(visibleHints.every(text => /[가-힣]/.test(text) === (language === 'ko')));
    report.failureToasts.push({ language, texts: visibleHints });
    await page.screenshot({ path: `${out}/kick-failed-${language}.png` });
    pass(`Real failed kick exposes its translated ${language} cause in card, command, event log and both stop hints`);
  }

  await loadFixture(); await selectUnit('alpha');
  await chooseDoorMode(fallbackSelector, 'KICK_DOOR', 'breach');
  await chooseDoorMode(plainKickSelector, 'KICK_DOOR', '');
  await appendDoorOrder('d2', 'KICK_DOOR');
  assert.equal((await selectedUnit()).available_breaches, 2);
  await chooseDoorMode(fallbackSelector, 'KICK_DOOR', 'breach');
  await appendDoorOrder('d3', 'KICK_DOOR', 'breach');
  assert.equal((await selectedUnit()).available_breaches, 1);
  await chooseDoorMode(shotgunSelector, 'SHOTGUN_BREACH');
  assert.equal((await latest()).door_fallback, '');
  await appendDoorOrder('d1', 'SHOTGUN_BREACH');
  assert.equal((await selectedUnit()).available_shotgun_breaches, 1);
  const toolMessages = await page.evaluate(() => window.cqbContactQA.sent.filter(message => message.action === 'tool' && message.tool === 'door'));
  assert(toolMessages.some(message => message.door_mode === 'KICK_DOOR' && message.door_fallback === 'breach'));
  assert(toolMessages.some(message => message.door_mode === 'KICK_DOOR' && message.door_fallback === ''));
  pass('Plain kick clears fallback mode; fallback is stored only on its own actual primitive command');

  const plan = await planFromButton();
  assert.equal(plan.kind, 'breach-plan'); assert.equal(plan.schema_version, 1);
  assert.equal(plan.map_id, 'CQB_CONTACT_UI'); assert.equal(plan.seed, 42);
  assert.deepEqual(plan.units.find(unit => unit.id === 'alpha').commands, [
    { type: 'KICK_DOOR', args: { door_id: 'd2' } },
    { type: 'KICK_DOOR', args: { door_id: 'd3', fallback: 'breach' } },
    { type: 'SHOTGUN_BREACH', args: { door_id: 'd1' } },
  ]);
  await send({ action: 'clear', unit_id: 'alpha' });
  await wait(() => window.cqbContactQA.state.units.find(unit => unit.id === 'alpha')?.commands.every(command => command.state === 'CANCELLED'));
  await page.locator('#deck-more').click(); await page.locator('#modal-load-plan').click();
  await wait(() => window.cqbContactQA.state?.time === 0 && window.cqbContactQA.state.units.find(unit => unit.id === 'alpha')?.commands.length === 3 && window.cqbContactQA.state.units.find(unit => unit.id === 'alpha').commands.every(command => command.state === 'PENDING'));
  await assertPlanCommands(plan);
  pass('IndexedDB save and visible load action restore primitive commands, fallback, resources and schema 1 plan');

  await page.locator('#deck-more').click();
  const [download] = await Promise.all([page.waitForEvent('download'), page.locator('#export-plan').click()]);
  const planPath = `${out}/cqb-contact.plan.json`; await download.saveAs(planPath);
  const exported = JSON.parse(await readFile(planPath, 'utf8'));
  assert.equal(exported.schema_version, 1); assert.deepEqual(exported, plan);
  await page.locator('#modal-close').click();
  await send({ action: 'clear', unit_id: 'alpha' });
  await wait(() => window.cqbContactQA.state.units.find(unit => unit.id === 'alpha')?.commands.every(command => command.state === 'CANCELLED'));
  await page.locator('#deck-more').click(); await page.locator('#import-plan').click();
  await page.locator('#file-import').setInputFiles(planPath);
  await wait(() => window.cqbContactQA.state?.time === 0 && window.cqbContactQA.state.units.find(unit => unit.id === 'alpha')?.commands.length === 3 && window.cqbContactQA.state.units.find(unit => unit.id === 'alpha').commands.every(command => command.state === 'PENDING'));
  await assertPlanCommands(exported);
  assert.deepEqual(await planFromButton(), exported);
  await page.screenshot({ path: `${out}/restored-plan.png` });
  pass('Downloaded schema 1 JSON imports through file UI and exports an identical fresh plan');
  assert.deepEqual(errors, []); assert.deepEqual(failedRequests, []);
  report.status = 'PASS';
} catch (error) {
  report.status = 'FAIL'; report.error = error.stack;
  report.lastState = await latest().catch(() => null);
  report.messages = await page.evaluate(() => window.cqbContactQA.messages.filter(message => !['ready', 'catalog_update'].includes(message.type))).catch(() => []);
  await page.screenshot({ path: `${out}/failure.png` }).catch(() => {});
  console.error(error); process.exitCode = 1;
} finally {
  await writeFile(`${out}/report.json`, JSON.stringify(report, null, 2));
  await browser.close();
  console.log(`BREACH_CQB_CONTACT_BROWSER_RESULT checks=${report.checks.length} failures=${report.status === 'PASS' ? 0 : 1} status=${report.status}`);
}
