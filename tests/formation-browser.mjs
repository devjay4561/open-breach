import { chromium } from 'playwright';
import assert from 'node:assert/strict';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { setCycler } from './lib/menu.mjs';

// Native fixed-STEP evidence proves authored routes, posture, body spacing and
// completion before Chrome starts. Godot JSON writes 15 significant digits.
const native = JSON.parse(await readFile('tests/artifacts/formation-browser/preflight.json', 'utf8'));
assert.equal(native.status, 'PASS'); assert.deepEqual(native.failures, []);
assert.equal(native.step, Number((1 / 30).toPrecision(15))); assert.equal(native.seed, 42);
const ids = ['alpha', 'bravo', 'charlie', 'delta'];
const types = ['MOVE', 'FACE', 'WAIT_FOR_SIGNAL'];
const metaKeys = ['kind', 'order', 'source_unit_id', 'stage', 'sync_id'];
// _canonical_args JSON-roundtrips every formation command. Godot's fractional
// formatter uses 17 decimal places on the already-published JSON numbers; this
// includes tiny FACE coordinates as well as angles. Native positive controls
// below require exact equality for the entire expanded recipe.
const canonicalArgs = value => typeof value === 'number' ? Number(value.toFixed(17)) : Array.isArray(value)
  ? value.map(canonicalArgs) : value && typeof value === 'object'
    ? Object.fromEntries(Object.entries(value).map(([key, item]) => [key, canonicalArgs(item)])) : value;
const replaySource = await readFile(new URL('../game/scripts/replay.gd', import.meta.url), 'utf8');
assert.match(replaySource, /var defaults := \{[^\n]*"exposure":1\.0/, 'The legacy numeric decoder explicitly declares missing exposure as 1.0');
// Preserve every live field and add only the decoder's declared missing-own
// exposure default. Positions, commands, IDs, sectors and times remain exact.
const replayUnits = units => units.map(unit => ({ exposure: 1, ...unit }));
const ordered = value => Array.isArray(value) ? value.map(ordered) : value && typeof value === 'object'
  ? Object.fromEntries(Object.keys(value).sort().map(key => [key, ordered(value[key])])) : value;
const insideRectangle = ([x, z], rect) => x >= rect.x - rect.w / 2 && x <= rect.x + rect.w / 2
  && z >= rect.z - rect.d / 2 && z <= rect.z + rect.d / 2;
function assertAuthoredGoals(preview, item) {
  for (const slot of preview.slots) {
    const goal = item.mission.interactive_targets.find(goal => goal.id === `finish_${slot.unit_id}`);
    assert.ok(goal, 'Every coverer retains its existing authored objective');
    assert.ok(insideRectangle(slot.target, goal), 'Each final slot stays inside its unchanged authored inspection zone');
  }
}
function draft(preview, syncId) {
  return preview.slots.map(slot => {
    const nodes = [], node = (type, stage, args) => nodes.push({ type, args: canonicalArgs({ ...args, formation: {
      sync_id: syncId, kind: preview.kind, order: slot.index, stage, source_unit_id: preview.source_unit_id,
    } }) });
    node('FACE', 'stack', { target: slot.initial_face_target, persistent: true, sector: { start: 0, end: 0, duration: 0 } });
    for (const target of slot.stack_waypoints || []) node('MOVE', 'stack', { target });
    node('MOVE', 'stack', { target: slot.stack });
    node('FACE', 'ready', { target: preview.noise_discipline === 'hand_signals' ? slot.ready_face_target : slot.stack_face_target,
      persistent: true, ...(preview.kind === 'T_JUNCTION' ? { stance: slot.stance } : {}) });
    node('WAIT_FOR_SIGNAL', 'ready', { signal: preview.signal === 'AUTO' ? 'A' : preview.signal, sync_id: `${syncId}:ready`,
      auto_signal: preview.signal === 'AUTO', delay_ticks: preview.delay_ticks });
    const route = [...(slot.move_waypoints || slot.move_route || [])];
    if (!route.length || JSON.stringify(route.at(-1)) !== JSON.stringify(slot.target)) route.push(slot.target);
    for (const [index, target] of route.entries()) {
      node('FACE', 'move', { target: slot.move_face_targets[index] || slot.face_target, persistent: true });
      node('MOVE', 'move', { target });
    }
    node('FACE', 'cover', { target: slot.face_target, persistent: true,
      sector: { start: slot.sector.start, end: slot.sector.end, duration: slot.sector.duration } });
    return { id: slot.unit_id, commands: nodes };
  });
}
assert.deepEqual(native.cases.map(item => item.id), ['narrow_verbal', 'wide_verbal', 'wide_hand_signals', 'junction_hand_signals']);
for (const item of native.cases) {
  assert.equal(item.mission.schema_version, 5); assert.equal(item.preview.ok, true);
  assert.equal(item.result.status, 'SUCCESS'); assert.equal(item.result.command_failures, 0);
  assert.equal(item.signals.length, 1); assert.equal(item.signals[0].source_unit_id, 'delta');
  assert.ok(item.min_gap >= 0.48); assert.ok(item.release_tick >= item.ready_tick + 3);
  assert.ok(item.final_units.every(unit => unit.commands.every(command => command.state === 'SUCCEEDED')));
  const syncId = item.initial_commands[0].commands[0].args.formation.sync_id;
  // This positive control also proves the extra Godot fractional JSON format
  // for angular command metadata. Actual WASM values below come from its own
  // published preview; native atan2 bits are never cross-platform goldens.
  assert.deepEqual(draft(item.preview, syncId), item.initial_commands);
  assertAuthoredGoals(item.preview, item);
}
// Formation._point converts the clicked Array through Vector2 (float32), then
// the bridge writes 15 significant digits. These exact decimal controls include
// the actual preview target 7.98000001907349, with no comparison tolerance.
assert.deepEqual([7.98, 7.99, 0.01, 5.2, 4].map(value => Number(Math.fround(value).toPrecision(15))),
  [7.98000001907349, 7.98999977111816, 0.00999999977648258, 5.19999980926514, 4]);
if (process.argv.includes('--prepare-only')) {
  console.log('BREACH_FORMATION_UI_PREPARE_RESULT cases=4 status=PASS'); process.exit(0);
}

const out = process.env.BREACH_ARTIFACTS || 'tests/artifacts/formation-browser';
await mkdir(out, { recursive: true });
const url = new URL(process.env.BREACH_URL || 'http://127.0.0.1:8080'); url.searchParams.set('qa', '1');
const browser = await chromium.launch({ channel: process.env.BREACH_CHANNEL || 'chrome', headless: true,
  args: ['--enable-unsafe-swiftshader'] });
const context = await browser.newContext({ viewport: { width: 1440, height: 900 }, acceptDownloads: true });
await context.addInitScript(() => {
  let ui;
  window.formationQA = { state: null, states: [], messages: [], sent: [], catalog: {}, plans: [], replays: [], events: [], keys: new Set(), run: 0 };
  Object.defineProperty(window, 'BreachUI', { configurable: true, get: () => ui, set(value) {
    ui = value; const receive = value.receive;
    value.receive = function(raw) {
      const message = typeof raw === 'string' ? JSON.parse(raw) : raw, qa = window.formationQA;
      if (message.type === 'state') {
        if (message.mission !== qa.state?.mission || message.tick < qa.state?.tick) qa.run += 1;
        qa.state = message; qa.states.push({ ...message, qa_run: qa.run }); if (qa.states.length > 1200) qa.states.shift();
        for (const event of message.events || []) {
          const key = `${qa.run}:${message.mission}:${event.seq}:${event.tick}:${event.type}`;
          if (!qa.keys.has(key)) { qa.keys.add(key); qa.events.push({ ...event, run: qa.run, mission: message.mission }); }
        }
      } else { qa.messages.push(message); if (qa.messages.length > 1000) qa.messages.shift(); }
      if (message.type === 'plan_data') qa.plans.push(message.data);
      if (message.type === 'replay_data') qa.replays.push(message.data);
      if (['ready', 'catalog_update'].includes(message.type)) Object.assign(qa.catalog, message.catalog || {});
      return receive.call(this, raw);
    };
  } });
});
const page = await context.newPage(); page.setDefaultTimeout(300000);
const errors = [], failedRequests = [], externalRequests = [];
page.on('pageerror', error => errors.push(error.message));
page.on('console', message => { if (message.type() === 'error' || /SCRIPT ERROR|Parse Error|Failed loading resource/.test(message.text())) errors.push(message.text()); });
page.on('response', response => { if (response.status() >= 400) errors.push(`HTTP ${response.status()} ${response.url()}`); });
page.on('requestfailed', request => failedRequests.push({ url: request.url(), error: request.failure()?.errorText }));
page.on('request', request => { if (/^https?:/.test(request.url()) && new URL(request.url()).origin !== url.origin) externalRequests.push(request.url()); });
const report = { checks: [], errors, failedRequests, externalRequests, cases: [], geometry: [], version: browser.version() };
const pass = name => { report.checks.push(name); console.log(`PASS ${name}`); };
const latest = () => page.evaluate(() => window.formationQA.state);
const cursor = () => page.evaluate(() => window.formationQA.sent.length);
const send = intent => page.evaluate(intent => window.BreachBridge.send(JSON.stringify(intent)), intent);
const dom = (predicate, arg = null) => page.waitForFunction(predicate, arg, { timeout: 45000 });
const ack = (predicate, arg = null) => page.waitForFunction(predicate, arg, { timeout: 300000 });
async function animations(selector) {
  await page.locator(selector).evaluate(async element => {
    await Promise.all(element.getAnimations({ subtree: true }).filter(animation => animation.effect?.getTiming().iterations !== Infinity)
      .map(animation => animation.finished.catch(() => {})));
  });
}
async function hudLayoutReady() {
  // Native render tokens acknowledge the camera, while the product's
  // ResizeObserver updates its deck inset on the next animation frame.
  await dom(() => {
    const hud = document.querySelector('#hud');
    if (hud.hidden) return true;
    const height = Math.round(document.querySelector('.hud-hotbar').getBoundingClientRect().height);
    return parseFloat(getComputedStyle(hud).getPropertyValue('--drill-deck-height')) === height;
  });
}
async function renderAck() {
  await hudLayoutReady();
  const token = await page.evaluate(() => {
    const qa = window.formationQA, token = `formation-render-${qa.sequence = (qa.sequence || 0) + 1}`;
    const right = document.querySelector('.hud-right').getBoundingClientRect();
    window.BreachBridge.send(JSON.stringify({ action: 'set_safe_area', _quality_token: token, data: {
      left: Math.round(document.querySelector('.hud-left').getBoundingClientRect().width),
      top: Math.round(document.querySelector('.hud-topbar').getBoundingClientRect().height),
      right: Math.max(0, Math.round(innerWidth - Math.max(right.left, 0))),
      bottom: Math.round(document.querySelector('.hud-hotbar').getBoundingClientRect().height),
    } })); return token;
  });
  await ack(token => window.formationQA.states.some(state => state.quality?.ack_tokens?.includes(token)), token);
  await hudLayoutReady();
}
async function loaded(mode) {
  await ack(mode => window.formationQA.state?.mode === mode && document.querySelector('#loading').hidden
    && !document.querySelector('#transition-loading').open, mode);
  await animations(mode === 'REPLAY' ? '#replay-hud' : '#hud'); await renderAck();
}
async function boot() {
  await page.goto(url.href, { waitUntil: 'domcontentloaded' });
  await page.locator('#title-start').waitFor({ state: 'visible' });
  await ack(() => window.formationQA.state?.mode === 'MENU' && window.BreachBridge && document.querySelector('#loading').hidden
    && !document.querySelector('#transition-loading').open && !document.querySelector('#start-mission').disabled);
  await animations('#title-screen');
  await page.evaluate(() => { const send = window.BreachBridge.send;
    window.BreachBridge.send = function(raw) { window.formationQA.sent.push(JSON.parse(raw)); return send.call(this, raw); }; });
  await page.locator('#title-start').click(); await page.locator('#select-to-briefing').click();
  await page.locator('#start-mission').click(); await loaded('PLANNING');
}
function privacy(state) {
  assert.equal(state.enemies.some(enemy => enemy.id === 'unseen'), false);
  assert.equal(state.room_states.sealed.state, 'UNKNOWN'); assert.equal(state.room_states.sealed.observed, false);
  assert.equal(Object.hasOwn(state, 'room_states_observed'), false);
}
async function load(item) {
  await send({ action: 'import_mission', data: item.mission });
  await ack(id => window.formationQA.state?.mission === id && window.formationQA.state.mode === 'PLANNING'
    && window.formationQA.state.time === 0 && window.formationQA.state.units.every(unit => unit.commands.length === 0), item.mission.id);
  await loaded('PLANNING'); assert.equal((await latest()).seed, 42); privacy(await latest());
}
async function group(order) {
  await page.locator(`.unit-card[data-unit="${order[0]}"]`).click();
  await ack(id => window.formationQA.state?.selected === id && window.formationQA.state.selected_units?.length === 1, order[0]);
  for (let index = 1; index < order.length; index++) {
    await page.locator(`.unit-card[data-unit="${order[index]}"]`).click({ modifiers: ['Shift'] });
    await ack(order => JSON.stringify(window.formationQA.state?.selected_units) === JSON.stringify(order), order.slice(0, index + 1));
  }
  await renderAck(); assert.equal(await page.locator('.unit-card[aria-pressed="true"]').count(), order.length);
}
async function mapPoint([x, z]) {
  return page.evaluate(({ x, z }) => {
    const data = window.formationQA.catalog[window.formationQA.state.mission];
    if (!data) throw new Error('Actual public mission geometry missing');
    const canvas = document.querySelector('#canvas').getBoundingClientRect(), right = document.querySelector('.hud-right').getBoundingClientRect();
    const l = Math.round(document.querySelector('.hud-left').getBoundingClientRect().width) + 16;
    const t = Math.round(document.querySelector('.hud-topbar').getBoundingClientRect().height) + 16;
    const r = Math.max(0, Math.round(innerWidth - Math.max(right.left, 0))) + 16;
    const b = Math.round(document.querySelector('.hud-hotbar').getBoundingClientRect().height) + 16;
    const vertical = Math.min(.97, Math.max(.25, (innerHeight - t - b) / innerHeight));
    const horizontal = Math.min(.97, Math.max(.25, (innerWidth - l - r) / innerWidth));
    const scale = canvas.height / Math.max((data.bounds[1] + 2) / vertical, (data.bounds[0] + 2) / Math.max(innerWidth / innerHeight * horizontal, .1));
    return { x: canvas.left + canvas.width / 2 + (x - data.bounds[0] / 2) * scale + (l - r) / 2,
      y: canvas.top + canvas.height / 2 + ((z - data.bounds[1] / 2) * 34 - 0.2 * 15.5) / Math.hypot(34, 15.5) * scale + (t - b) / 2 };
  }, { x, z });
}
async function previewAfter(operation) {
  const before = await cursor(); await operation();
  await ack(before => {
    const qa = window.formationQA, request = qa.sent.slice(before).filter(intent => intent.action === 'formation_preview' && !intent.clear).at(-1);
    const response = qa.messages.findLast(message => message.type === 'formation_preview' && message.preview_id === request?.preview_id);
    return response && (!response.data?.ok || !document.querySelector('#formation-commit').disabled);
  }, before);
  const preview = await page.evaluate(before => {
    const qa = window.formationQA, request = qa.sent.slice(before).filter(intent => intent.action === 'formation_preview' && !intent.clear).at(-1);
    return qa.messages.findLast(message => message.type === 'formation_preview' && message.preview_id === request.preview_id).data;
  }, before);
  assert.equal(preview.ok, true, JSON.stringify(preview));
  assert.equal((await latest()).time, 0); assert.ok((await latest()).units.every(unit => !unit.commands.length));
  assert.equal(JSON.stringify(preview).includes('unseen'), false); privacy(await latest()); return preview;
}
async function open(item) {
  await page.locator('#formation-tool').click(); await ack(() => window.formationQA.state?.tool === 'formation');
  const point = await mapPoint(item.target), before = await page.evaluate(() => window.formationQA.messages.length), requestBefore = await cursor();
  const preview = await previewAfter(() => page.mouse.click(point.x, point.y));
  const target = await page.evaluate(before => window.formationQA.messages.slice(before).find(message => message.type === 'formation_target'), before);
  assert.ok(target); assert.deepEqual(target.order, (await latest()).selected_units);
  const request = await page.evaluate(before => window.formationQA.sent.slice(before).findLast(intent => intent.action === 'formation_preview' && !intent.clear), requestBefore);
  assert.deepEqual(request.target, target.target); assert.deepEqual(request.order, target.order);
  // Only the planner converts the raw clicked Array into Vector2 float32;
  // compare its published target with that exact JSON15 representation.
  assert.deepEqual(preview.target, target.target.map(value => Number(Math.fround(value).toPrecision(15))));
  // A real mouse-down uses integer client pixels: at 30.75px/m the authored
  // center projects to x=648.5, so adjacent clicks snap to 7.98 or 8.02 rather
  // than 8.00. Check the intended authored floor and direction; all published
  // targets, expanded arguments and final fixed objectives remain exact.
  const room = item.mission.rooms.find(room => ['hall', 'cross'].includes(room.id) && insideRectangle(item.target, room));
  assert.ok(room, 'The intended destination belongs to an authored corridor or junction');
  assert.ok(insideRectangle(target.target, room), 'The actual picked point stays on that same authored floor');
  assert.ok(target.target[1] < Math.min(...(await latest()).units.map(unit => unit.z)), 'The actual picked point is north of the owned stack');
  await page.locator('#formation-panel').waitFor({ state: 'visible' }); return preview;
}
async function focusReleased(before, overlay = '#formation-panel') {
  await dom(({ before, overlay }) => {
    const intents = window.formationQA.sent.slice(before);
    return document.querySelector(overlay).hidden && document.activeElement === document.querySelector('#canvas')
      && intents.some(intent => intent.action === 'ui_focus' && intent.active === false)
      && intents.some(intent => intent.action === 'input_focus' && intent.blocked === false);
  }, { before, overlay }); await renderAck();
}
async function language(value) {
  await page.locator('.hud-topbar [data-open="settings"]').click(); await page.locator('[data-settings-tab="gameplay"]').click();
  await setCycler(page, '[data-cycler="language"]', value); await dom(value => document.documentElement.lang === value, value);
  await closeModal();
}
async function closeModal() {
  const before = await cursor(); await page.locator('#modal-close').click();
  await dom(before => { const intents = window.formationQA.sent.slice(before);
    return !document.querySelector('#modal').open && document.activeElement === document.querySelector('#canvas')
      && intents.some(intent => intent.action === 'ui_focus' && intent.active === false)
      && intents.some(intent => intent.action === 'input_focus' && intent.blocked === false); }, before); await renderAck();
}
async function geometry(label) {
  const audit = await page.evaluate(() => {
    const failures = [], panel = document.querySelector('#formation-panel'), deck = document.querySelector('.hud-hotbar');
    const rect = element => { const r = element.getBoundingClientRect(); return { left: r.left, right: r.right, top: r.top, bottom: r.bottom, width: r.width, height: r.height }; };
    const visible = element => element.getClientRects().length && !element.closest('[hidden]');
    const hit = element => { const r = rect(element); return element.contains(document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2)); };
    const bounds = element => { const r = rect(element); return r.left >= 0 && r.top >= 0 && r.right <= innerWidth && r.bottom <= innerHeight; };
    if (panel.hidden) failures.push('expected visible editor');
    if (rect(panel).bottom > rect(deck).top - 10) failures.push('editor covers hotbar');
    const controls = [...document.querySelectorAll('#hotbar-controls .tools>button,#hotbar-controls .hotbar-utility>button,#hotbar-controls .signals>button,#toggle-execution,#formation-tool,#unlock-facing')]
      .filter(visible).map(element => ({ id: element.id || element.dataset.tool || element.dataset.signal, ...rect(element), hit: hit(element), bounds: bounds(element) }));
    if (controls.length !== (document.querySelector('#unlock-facing') ? 16 : 15)) failures.push('original/new controls missing');
    for (const control of controls) {
      if (!control.bounds) failures.push(`${control.id} outside viewport`);
      if (!control.hit) failures.push(`${control.id} center covered`);
    }
    for (let first = 0; first < controls.length; first++) for (let second = first + 1; second < controls.length; second++) {
      const a = controls[first], b = controls[second];
      if (Math.min(a.right, b.right) > Math.max(a.left, b.left) && Math.min(a.bottom, b.bottom) > Math.max(a.top, b.top)) failures.push(`${a.id}/${b.id} overlap`);
    }
    for (const element of panel.querySelectorAll('header button,footer button')) if (!bounds(element) || !hit(element)) failures.push(`${element.id} inaccessible`);
    const editor = document.querySelector('#formation-editor-content');
    for (const element of editor.querySelectorAll('button:not(:disabled)')) {
      element.scrollIntoView({ block: 'nearest' });
      if (!bounds(element) || !hit(element)) failures.push(`${element.dataset.formationKind || element.dataset.formationOrder || element.dataset.formationSignal || element.dataset.formationDelay} inaccessible`);
    }
    editor.scrollTop = 0;
    for (const element of document.querySelectorAll('#hotbar-controls *,#drill-timeline>header *,#formation-panel *')) {
      if (visible(element) && [...element.childNodes].some(node => node.nodeType === Node.TEXT_NODE && node.textContent.trim()) && parseFloat(getComputedStyle(element).fontSize) < 12) failures.push('visible type below 12px');
    }
    return { failures, controls, panel: rect(panel), deck: rect(deck), viewport: [innerWidth, innerHeight] };
  }); report.geometry.push({ label, ...audit }); assert.deepEqual(audit.failures, [], label);
  await page.screenshot({ path: `${out}/${label}.png` });
}
async function savePlan() {
  const before = await page.evaluate(() => window.formationQA.plans.length); await page.locator('#save-plan').click();
  await dom(before => window.formationQA.plans.length > before, before);
  const plan = await page.evaluate(() => window.formationQA.plans.at(-1));
  await dom(async expected => { const { BreachStorage } = await import('./storage.js'), storage = new BreachStorage(); await storage.open();
    try { return JSON.stringify((await storage.get('plans', expected.map_id))?.data) === JSON.stringify(expected); }
    finally { storage.database.close(); } }, plan); return plan;
}
async function loadPlan(plan) {
  await send({ action: 'load_plan', data: plan });
  // The same plan is already visible before loading. This FIFO native render
  // acknowledgement proves the deferred import occurred before comparison.
  await renderAck();
  await ack(expected => {
    const ordered = value => Array.isArray(value) ? value.map(ordered) : value && typeof value === 'object'
      ? Object.fromEntries(Object.keys(value).sort().map(key => [key, ordered(value[key])])) : value;
    const state = window.formationQA.state;
    return state?.mode === 'PLANNING' && state.time === 0 && state.mission === expected.map_id && expected.units.every(unit =>
      JSON.stringify(ordered(state.units.find(row => row.id === unit.id)?.commands.map(command => ({ type: command.type, args: command.args })))) === JSON.stringify(ordered(unit.commands)));
  }, plan); await loaded('PLANNING');
  const state = await latest();
  for (const unit of plan.units) {
    const actual = state.units.find(row => row.id === unit.id); assert.deepEqual(actual.commands.map(({ type, args }) => ({ type, args })), unit.commands);
    assert.ok(actual.commands.every(command => command.state === 'PENDING'));
    for (const key of ['stance', 'movement_mode', 'hold_position']) assert.equal(actual[key], unit[key]);
  }
}
async function fileAck(action, before, mode) {
  await dom(({ action, before }) => window.formationQA.sent.slice(before).some(intent => intent.action === action), { action, before });
  await renderAck(); await loaded(mode);
}
async function commit(preview) {
  const before = await cursor(); await page.locator('#formation-commit').click(); await focusReleased(before);
  await ack(() => window.formationQA.state?.tool === 'select' && window.formationQA.state.units.every(unit => unit.commands.length > 5));
  const state = await latest(), syncId = state.units[0].commands[0].args.formation.sync_id;
  assert.deepEqual(state.units.map(unit => ({ id: unit.id, commands: unit.commands.map(({ type, args }) => ({ type, args })) })), draft(preview, syncId));
  for (const unit of state.units) for (const command of unit.commands) {
    assert.ok(types.includes(command.type)); assert.deepEqual(Object.keys(command.args.formation).sort(), metaKeys);
    assert.equal(Object.hasOwn(command.args, 'drill'), false); assert.equal(command.state, 'PENDING');
  }
  return syncId;
}
async function execute(signal, preview) {
  const run = await page.evaluate(() => window.formationQA.run);
  await send({ action: 'select', unit_id: 'alpha', preserve_group: true }); await renderAck();
  assert.equal((await latest()).selected, 'alpha'); assert.deepEqual((await latest()).selected_units, ids);
  await page.locator('#toggle-execution').click();
  let readyTick = null, observedReadyTick = null, signalBefore = null;
  if (signal !== 'AUTO') {
    await ack(() => window.formationQA.state?.mode === 'EXECUTING' && window.formationQA.state.units.every(unit =>
      unit.commands.find(command => command.type === 'WAIT_FOR_SIGNAL')?.state === 'WAITING'));
    const ready = await latest(); observedReadyTick = ready.tick; signalBefore = await cursor();
    const waits = ready.units.map(unit => unit.commands.find(command => command.type === 'WAIT_FOR_SIGNAL'));
    assert.ok(waits.every(command => Number.isInteger(command.started_tick) && command.started_tick > 0));
    // State delivery may skip the first ready frame. The barrier's actual
    // epoch is the last WAIT start, rather than this later browser snapshot.
    readyTick = Math.max(...waits.map(command => command.started_tick));
    for (const slot of preview.slots) assert.equal(ready.units.find(unit => unit.id === slot.unit_id).stance, slot.stance,
      'All prescribed postures are authoritative before the single manual signal');
    await page.locator(`#hud [data-signal="${signal}"]`).click();
    await dom(({ before, signal }) => window.formationQA.sent.slice(before).some(intent => intent.action === 'signal'
      && intent.channel === signal && !Object.hasOwn(intent, 'sender_id')), { before: signalBefore, signal });
  }
  await ack(() => window.formationQA.state?.mode === 'RESULT');
  const final = await latest(); assert.equal(final.result.success, true); assert.equal(final.result.command_failures, 0);
  assert.ok(final.units.every(unit => unit.commands.every(command => command.state === 'SUCCEEDED'))); privacy(final);
  const signals = await page.evaluate(({ run, mission }) => window.formationQA.events.filter(event => event.run === run && event.mission === mission && event.type === 'SIGNAL'), { run, mission: final.mission });
  assert.equal(signals.length, 1); const event = signals[0];
  assert.equal(event.source_unit_id, 'delta'); assert.deepEqual([...event.receiver_unit_ids].sort(), [...ids].sort());
  assert.equal(event.signal_mode, final.noise_discipline); assert.equal(event.signal_radius, event.signal_mode === 'hand_signals' ? 0 : 6);
  assert.equal(event.released, 4);
  for (const unit of final.units) assert.equal(unit.commands.find(command => command.type === 'WAIT_FOR_SIGNAL').completed_tick, event.tick);
  (report.signalEpochs ||= []).push({ mission: final.mission, observedReadyTick, readyTick, signalTick: event.tick });
  if (readyTick !== null) assert.ok(event.tick >= readyTick + 3, 'The actual named receipt respects all three fixed delay ticks');
  const states = await page.evaluate(({ run, mission }) => window.formationQA.states.filter(state => state.qa_run === run && state.mission === mission && state.tick > 0
    && state.tick <= window.formationQA.state.tick && state.mode === 'EXECUTING'), { run, mission: final.mission });
  for (const state of states) {
    privacy(state);
    for (let first = 0; first < state.units.length; first++) for (let second = first + 1; second < state.units.length; second++) {
      assert.ok(Math.hypot(state.units[first].x - state.units[second].x, state.units[first].z - state.units[second].z) >= 0.48,
        'Every observed living body pair keeps the native spacing contract');
    }
  }
  return final;
}
async function primitiveSelection() {
  await send({ action: 'select', unit_id: 'alpha', preserve_group: true }); await renderAck();
  const unit = (await latest()).units.find(unit => unit.id === 'alpha');
  const index = unit.commands.findIndex(command => command.type === 'MOVE' && command.args.formation.stage === 'move');
  assert.ok(index >= 0);
  // The desktop HUD keeps its queue visible; both legacy queue toggles are
  // hidden. Wait for the actual primitive row instead of hidden controls.
  const row = page.locator(`.command-row[data-command-unit="alpha"][data-select-command="${index}"]>div`).first();
  await page.locator('#queue-panel').waitFor({ state: 'visible', timeout: 45000 });
  await row.waitFor({ state: 'visible', timeout: 45000 }); await row.click();
  await ack(index => window.formationQA.state?.selected === 'alpha' && window.formationQA.state.selected_command === index, index);
  assert.deepEqual((await latest()).selected_units, ids);
  assert.deepEqual((await latest()).units.find(row => row.id === 'alpha').commands, unit.commands);
  await renderAck();
  pass('Expanded MOVE remains selectable through the existing primitive queue without changing its cohort or arguments');
}
async function finalReplay(final) {
  await page.locator('#watch-replay').click(); await loaded('REPLAY'); await send({ action: 'pause' }); await renderAck();
  await send({ action: 'replay_seek', time: final.time });
  await ack(time => window.formationQA.state?.mode === 'REPLAY' && window.formationQA.state.replay.time === time, final.time);
  let state = await latest(); assert.equal(state.tick, final.tick);
  for (const unit of state.units) {
    const live = final.units.find(row => row.id === unit.id);
    assert.equal(Object.hasOwn(unit, 'exposure'), true);
    assert.equal(unit.exposure, Object.hasOwn(live, 'exposure') ? live.exposure : 1);
  }
  assert.deepEqual(state.units, replayUnits(final.units)); assert.deepEqual(state.result, final.result); privacy(state);
  const [download] = await Promise.all([page.waitForEvent('download'), page.locator('#export-replay').click()]);
  const path = `${out}/formation.replay.json`; await download.saveAs(path);
  const replay = JSON.parse(await readFile(path, 'utf8')); assert.equal(replay.schema_version, 1); assert.equal(replay.encoding, 'numeric-state-v1');
  assert.equal(replay.duration, final.time); assert.equal(replay.complete, true); assert.equal(replay.map_id, final.mission);
  await dom(async expected => {
    const { BreachStorage } = await import('./storage.js'), storage = new BreachStorage(); await storage.open();
    try { return (await storage.all('replays')).some(record => JSON.stringify(record.data) === JSON.stringify(expected)); }
    finally { storage.database.close(); }
  }, replay);
  const saved = await page.evaluate(async expected => {
    const { BreachStorage } = await import('./storage.js'), storage = new BreachStorage(); await storage.open();
    try { return (await storage.all('replays')).findLast(record => JSON.stringify(record.data) === JSON.stringify(expected)); }
    finally { storage.database.close(); }
  }, replay);
  assert.deepEqual(saved.data, replay); assert.equal(saved.complete, true); assert.equal(saved.duration, final.time);
  let before = await cursor(); await page.locator('#replay-library').click();
  await page.locator(`[data-load-replay="${saved.id}"]`).click(); await fileAck('import_replay', before, 'REPLAY');
  await send({ action: 'pause' }); await renderAck(); await send({ action: 'replay_seek', time: replay.duration });
  await ack(time => window.formationQA.state?.replay.time === time && window.formationQA.state.replay.playing === false, replay.duration);
  state = await latest(); assert.equal(state.tick, final.tick); assert.deepEqual(state.units, replayUnits(final.units));
  assert.deepEqual(state.result, final.result); assert.equal(state.replay.reveal, false); privacy(state);
  report.savedReplay = { id: saved.id, duration: saved.duration, complete: saved.complete };
  before = await cursor(); await page.locator('#replay-library').click(); await page.locator('#import-replay').click();
  await page.locator('#file-import').setInputFiles(path); await fileAck('import_replay', before, 'REPLAY');
  await send({ action: 'pause' }); await renderAck(); await send({ action: 'replay_seek', time: replay.duration });
  await ack(time => window.formationQA.state?.mode === 'REPLAY' && window.formationQA.state.replay.time === time, replay.duration);
  state = await latest(); assert.equal(state.tick, final.tick); assert.deepEqual(state.units, replayUnits(final.units)); assert.deepEqual(state.result, final.result); privacy(state);
  await page.locator('#replay-restart').click();
  await ack(() => window.formationQA.state?.replay.time === 0 && window.formationQA.state.tick === 0);
  state = await latest(); assert.ok(state.units.every(unit => unit.commands.every(command => command.state === 'PENDING'))); privacy(state);
  return replay;
}

try {
  await boot(); pass('Real native MENU and planning loading/render acknowledgements');
  await load(native.cases[0]); await group(ids.slice(0, 2));
  let preview = await open(native.cases[0]); assert.equal(preview.kind, 'SERPENTINE'); assert.equal(preview.source_unit_id, 'bravo');
  assert.equal(await page.locator('[data-formation-kind="T_JUNCTION"]').isDisabled(), true);
  let before = await cursor(); await page.keyboard.press('Escape'); await focusReleased(before);
  await dom(before => window.formationQA.sent.slice(before).some(intent => intent.action === 'formation_preview' && intent.clear), before);
  assert.equal((await latest()).tool, 'select'); assert.equal(await page.locator('#pause-panel').isVisible(), false);
  await group(ids.slice(0, 3)); preview = await open(native.cases[0]);
  assert.equal(preview.slots.length, 3); assert.equal(preview.source_unit_id, 'charlie');
  before = await cursor(); await page.locator('#formation-close').click(); await focusReleased(before);
  pass('Actual 2/3-person group target, narrower AUTO, last-rank source, disabled T and Escape/focus cancellation');
  for (const [index, item] of native.cases.entries()) {
    await load(item); await language('ko'); await group(ids); preview = await open(item);
    if (item.requested_kind !== 'AUTO') preview = await previewAfter(() => page.locator(`[data-formation-kind="${item.requested_kind}"]`).click());
    assert.equal(preview.kind, item.preview.kind); assert.equal(preview.source_unit_id, 'delta');
    assert.deepEqual(preview.slots.map(slot => slot.stance), item.preview.slots.map(slot => slot.stance));
    if (index === 0) {
      preview = await previewAfter(() => page.locator('[data-formation-order="delta"][data-direction="-1"]').click());
      assert.deepEqual(preview.order_ids, ['alpha', 'bravo', 'delta', 'charlie']); assert.equal(preview.source_unit_id, 'charlie');
      preview = await previewAfter(() => page.locator('[data-formation-order="delta"][data-direction="1"]').click()); assert.deepEqual(preview.order_ids, ids);
      preview = await previewAfter(() => page.locator('[data-formation-delay="30"]').click()); assert.equal(preview.delay_ticks, 30);
      preview = await previewAfter(() => page.locator('[data-formation-delay="-30"]').click({ modifiers: ['Shift'] })); assert.equal(preview.delay_ticks, 29);
      preview = await previewAfter(() => page.locator('[data-formation-delay="reset"]').click()); assert.equal(preview.delay_ticks, 0);
      for (const width of [900, 1440]) { await page.setViewportSize({ width, height: width === 900 ? 600 : 900 }); await renderAck(); await geometry(`ko-${width}-editor`); }
      before = await cursor(); await page.locator('#formation-close').click(); await focusReleased(before);
      await language('en'); preview = await open(item);
      const copy = await page.evaluate(async () => { const { t } = await import('./i18n.js'); return { title: t('formation.title'), apply: t('formation.apply') }; });
      assert.equal(await page.locator('#formation-panel [data-i18n="formation.title"]').textContent(), copy.title);
      assert.equal(await page.locator('#formation-commit').textContent(), copy.apply);
      assert.equal(/[가-힣]/.test(await page.locator('#formation-panel').innerText()), false);
      for (const width of [900, 1440]) { await page.setViewportSize({ width, height: width === 900 ? 600 : 900 }); await renderAck(); await geometry(`en-${width}-editor`); }
      before = await cursor(); await page.locator('#formation-close').click(); await focusReleased(before);
      await language('ko'); preview = await open(item);
      pass('Real reorder/delay controls, ko/en copy and 900/1440 editor/hotbar hit geometry');
    }
    if (item.options.signal !== 'AUTO') preview = await previewAfter(() => page.locator(`[data-formation-signal="${item.options.signal}"]`).click());
    for (let tick = 0; tick < 3; tick++) preview = await previewAfter(() => page.locator('[data-formation-delay="30"]').click({ modifiers: ['Shift'] }));
    assert.equal(preview.delay_ticks, 3); assertAuthoredGoals(preview, item); const syncId = await commit(preview);
    const plan = await savePlan(); assert.equal(plan.schema_version, 1); assert.equal(plan.kind, 'breach-plan');
    await loadPlan(plan); await group(ids); const initial = (await latest()).units;
    if (index === 0) {
      // The async IDB UI must emit load_plan before a fresh FIFO render ACK.
      before = await cursor(); await page.locator('#deck-more').click(); await page.locator('#modal-load-plan').click();
      await fileAck('load_plan', before, 'PLANNING'); await group(ids); assert.deepEqual((await latest()).units, initial);
      const [download] = await Promise.all([page.waitForEvent('download'), page.locator('#deck-more').click().then(() => page.locator('#export-plan').click())]);
      const path = `${out}/formation.plan.json`; await download.saveAs(path); assert.deepEqual(JSON.parse(await readFile(path, 'utf8')), plan);
      await closeModal();
      before = await cursor(); await page.locator('#deck-more').click(); await page.locator('#import-plan').click(); await page.locator('#file-import').setInputFiles(path);
      await fileAck('load_plan', before, 'PLANNING'); await group(ids); assert.deepEqual((await latest()).units, initial);
    }
    if (index === 0) await primitiveSelection();
    const final = await execute(item.options.signal, preview); report.cases.push({ id: item.id, preview, syncId, plan, initial, final });
    pass(`${item.id}: whole actual WASM primitive expansion, schema-1/IDB plan, physical signal and complete real SUCCESS`);
    if (index === 0) {
      // AUTO is a complete deterministic plan. Manual B is a separate real
      // user gesture whose wall-clock delivery tick is deliberately observed
      // in the other cases rather than assumed identical on a fresh attempt.
      before = await cursor(); await page.locator('#retry-plan').click(); await fileAck('retry_plan', before, 'PLANNING'); await group(ids);
      assert.deepEqual((await latest()).units, initial); await language('en'); const retried = await execute(item.options.signal, preview);
      assert.equal(retried.tick, final.tick); assert.deepEqual(retried.units, final.units); assert.deepEqual(retried.result, final.result);
      await finalReplay(retried); pass('Exact same-engine replay file/zero privacy and canonical AUTO retry IDs/whole values survive ko→en');
    }
  }
  assert.deepEqual(report.cases.map(item => item.id), native.cases.map(item => item.id));
  assert.deepEqual(errors, []); assert.deepEqual(failedRequests, []); assert.deepEqual(externalRequests, []);
  pass('No page/native/resource/network errors or external requests'); report.status = 'PASS';
} catch (error) {
  report.status = 'FAIL'; report.failure = error.stack || String(error);
  report.latest = await latest().catch(() => null);
  report.diagnostics = await page.evaluate(() => ({ sent: window.formationQA.sent.slice(-40), messages: window.formationQA.messages.slice(-20),
    focus: document.activeElement?.id, modal: document.querySelector('#modal')?.open, loading: document.querySelector('#loading')?.hidden,
    transition: document.querySelector('#transition-loading')?.open })).catch(() => null);
  await page.screenshot({ path: `${out}/failure.png` }).catch(() => {}); console.error(report.failure); process.exitCode = 1;
} finally {
  await writeFile(`${out}/report.json`, `${JSON.stringify(report, null, 2)}\n`);
  console.log(`BREACH_FORMATION_UI_RESULT checks=${report.checks.length} failures=${report.status === 'PASS' ? 0 : 1} status=${report.status}`);
  await context.close(); await browser.close();
}
