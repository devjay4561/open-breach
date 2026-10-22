import { chromium } from 'playwright';
import assert from 'node:assert/strict';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { setCycler } from './lib/menu.mjs';

// P3 runs the same real fixed-seed missions/primitives proven by the native
// preflight. DOM, IndexedDB, download/import and queued native render ACKs are
// observed directly. No wall-clock sleeps or authority/hidden-state injection.
const native = JSON.parse(await readFile('tests/artifacts/room-control-browser/preflight.json', 'utf8'));
assert.equal(native.status, 'PASS', 'Run room_control_browser_preflight_test.gd before actual UI verification');
assert.deepEqual(native.failures, []);
// Godot JSON emits 15 significant decimal digits; compare that exact serialized
// STEP value while the native simulation continues to use its unchanged 1/30.
assert.equal(native.step, Number((1 / 30).toPrecision(15)));
const out = process.env.BREACH_ARTIFACTS || 'tests/artifacts/room-control-browser';
await mkdir(out, { recursive: true });
const url = new URL(process.env.BREACH_URL || 'http://127.0.0.1:8080');
url.searchParams.set('qa', '1');
const browser = await chromium.launch({ channel: process.env.BREACH_CHANNEL || 'chrome', headless: true,
  args: ['--enable-unsafe-swiftshader'] });
const context = await browser.newContext({ viewport: { width: 1440, height: 900 }, acceptDownloads: true });
await context.addInitScript(() => {
  let ui;
  window.roomControlQA = { state: null, states: [], events: [], eventKeys: new Set(), messages: [], sent: [], replays: [], run: 0 };
  Object.defineProperty(window, 'BreachUI', { configurable: true, get: () => ui, set(value) {
    ui = value;
    const receive = value.receive;
    value.receive = function(raw) {
      const message = typeof raw === 'string' ? JSON.parse(raw) : raw, qa = window.roomControlQA;
      if (message.type === 'state') {
        if (message.mission !== qa.state?.mission || message.tick < qa.state?.tick) qa.run += 1;
        qa.state = message; qa.states.push(message);
        if (qa.states.length > 1200) qa.states.shift();
        for (const event of message.events || []) {
          const key = `${qa.run}:${message.mission}:${event.seq}:${event.tick}:${event.type}`;
          if (!qa.eventKeys.has(key)) { qa.eventKeys.add(key); qa.events.push({ ...event, mission: message.mission, run: qa.run }); }
        }
      } else { qa.messages.push(message); if (qa.messages.length > 600) qa.messages.shift(); }
      if (message.type === 'replay_data') qa.replays.push(message.data);
      return receive.call(this, raw);
    };
  } });
});
const page = await context.newPage();
page.setDefaultTimeout(300000);
const errors = [], failedRequests = [];
page.on('pageerror', error => errors.push(error.message));
page.on('console', message => { if (message.type() === 'error' || /SCRIPT ERROR|Parse Error|Failed loading resource/.test(message.text())) errors.push(message.text()); });
page.on('response', response => { if (response.status() >= 400) errors.push(`HTTP ${response.status()} ${response.url()}`); });
page.on('requestfailed', request => failedRequests.push({ url: request.url(), failure: request.failure()?.errorText }));
const report = { status: 'RUNNING', url: url.href, checks: [], errors, failedRequests, calls: [], callTranslations: [], cases: [] };
const pass = name => { report.checks.push(name); console.log(`PASS ${name}`); };
const latest = () => page.evaluate(() => window.roomControlQA.state);
const waitDom = (predicate, argument = null) => page.waitForFunction(predicate, argument, { timeout: 45000 });
const waitNative = (predicate, argument = null) => page.waitForFunction(predicate, argument, { timeout: 300000 });
const send = value => page.evaluate(value => window.BreachBridge.send(JSON.stringify(value)), value);

async function finishAnimations(selector) {
  await page.evaluate(async selector => Promise.all(document.querySelector(selector).getAnimations({ subtree: true })
    .filter(animation => Number.isFinite(animation.effect?.getComputedTiming().endTime))
    .map(animation => animation.finished.catch(() => {}))), selector);
}
async function renderAck() {
  const token = await page.evaluate(() => {
    const token = `room-control-render-${window.roomControlQA.sequence = (window.roomControlQA.sequence || 0) + 1}`;
    const right = document.querySelector('.hud-right').getBoundingClientRect();
    window.BreachBridge.send(JSON.stringify({ action: 'set_safe_area', _quality_token: token, data: {
      left: Math.round(document.querySelector('.hud-left').getBoundingClientRect().width),
      top: Math.round(document.querySelector('.hud-topbar').getBoundingClientRect().height),
      right: Math.max(0, Math.round(innerWidth - Math.max(right.left, 0))),
      bottom: Math.round(document.querySelector('.hud-hotbar').getBoundingClientRect().height),
    } }));
    return token;
  });
  await waitNative(token => window.roomControlQA.states.some(state => state.quality?.ack_tokens?.includes(token)), token);
}
async function boot() {
  await page.goto(url.href, { waitUntil: 'domcontentloaded' });
  await page.locator('#title-start').waitFor({ state: 'visible' });
  await waitNative(() => window.roomControlQA.state?.mode === 'MENU' && window.BreachBridge
    && document.querySelector('#loading').hidden && !document.querySelector('#transition-loading').open
    && !document.querySelector('#start-mission').disabled);
  await finishAnimations('#title-screen');
  await page.evaluate(() => {
    const send = window.BreachBridge.send;
    window.BreachBridge.send = function(raw) { window.roomControlQA.sent.push(JSON.parse(raw)); return send.call(this, raw); };
  });
  await page.locator('#title-start').click();
  await page.locator('#select-to-briefing').click();
  await page.locator('#start-mission').waitFor({ state: 'visible' });
  await page.locator('#start-mission').click();
  await waitNative(() => window.roomControlQA.state?.mode === 'PLANNING'
    && document.querySelector('#loading').hidden && !document.querySelector('#transition-loading').open);
  await finishAnimations('#hud'); await renderAck();
}
async function load(data) {
  await send({ action: 'import_mission', data });
  await waitNative(id => {
    const state = window.roomControlQA.state;
    return state?.mission === id && state.mode === 'PLANNING' && state.time === 0
      && state.units.every(unit => !unit.commands.length) && document.querySelector('#loading').hidden
      && !document.querySelector('#transition-loading').open;
  }, data.id);
  await finishAnimations('#hud'); await renderAck();
  assert.equal((await latest()).seed, data.seed);
}
async function settings() {
  await page.locator('.hud-topbar [data-open="settings"]').click();
  await page.locator('[data-settings-tab="gameplay"]').click();
  await page.locator('[data-setting-toggle="auto_pause_man_down"]').waitFor({ state: 'visible' });
}
async function closeSettings() {
  const before = await page.evaluate(() => window.roomControlQA.sent.length);
  await page.locator('#modal-close').click();
  // Closing DOM is not a native input-focus release. Observe both real outgoing
  // releases and canvas focus, then use a FIFO post-render acknowledgement.
  await waitDom(before => {
    const sent = window.roomControlQA.sent.slice(before);
    return !document.querySelector('#modal').open && document.activeElement === document.querySelector('#canvas')
      && sent.some(intent => intent.action === 'ui_focus' && intent.active === false)
      && sent.some(intent => intent.action === 'input_focus' && intent.blocked === false);
  }, before);
  await renderAck();
}
async function settingsAck(before, expected) {
  await waitDom(({ before, expected }) => window.roomControlQA.sent.slice(before).some(intent => intent.action === 'settings'
    && Object.entries(expected).every(([key, value]) => intent.settings?.[key] === value)), { before, expected });
  // quality-metrics deliberately excludes automatic settings intents. A
  // fresh real safe-area render ACK follows the observed settings in the
  // native FIFO and proves the setting was processed without fabricating it.
  await renderAck();
}
async function savedSettings(expected) {
  await waitDom(async expected => {
    const { BreachStorage } = await import('./storage.js'), storage = new BreachStorage();
    await storage.open();
    try {
      const record = await storage.get('settings', 'current');
      return Number.isInteger(record?.version) && record.version > 0
        && Object.entries(expected).every(([key, value]) => record.data?.[key] === value);
    } finally { storage.database.close(); }
  }, expected);
  return page.evaluate(async () => {
    const { BreachStorage } = await import('./storage.js'), storage = new BreachStorage(); await storage.open();
    try { return await storage.get('settings', 'current'); } finally { storage.database.close(); }
  });
}
async function autoPause(value) {
  const toggle = page.locator('[data-setting-toggle="auto_pause_man_down"]');
  if ((await toggle.getAttribute('aria-pressed')) !== String(value)) {
    const before = await page.evaluate(() => window.roomControlQA.sent.length);
    await toggle.click(); await settingsAck(before, { auto_pause_man_down: value });
  }
  assert.equal(await toggle.getAttribute('aria-pressed'), String(value));
  return savedSettings({ auto_pause_man_down: value });
}
async function language(value) {
  await settings();
  if ((await page.evaluate(() => document.documentElement.lang)) !== value) {
    const before = await page.evaluate(() => window.roomControlQA.sent.length);
    await setCycler(page, '[data-cycler="language"]', value);
    await settingsAck(before, { language: value });
  }
  await waitDom(value => document.documentElement.lang === value, value);
  await savedSettings({ language: value }); await closeSettings();
}
function publicRooms(state, privateRoom = null) {
  assert.equal(Object.hasOwn(state, 'room_states_observed'), false);
  assert.equal(Object.hasOwn(state.result || {}, 'room_states_observed'), false);
  if (privateRoom) {
    assert.equal(state.room_states[privateRoom]?.state, 'UNKNOWN');
    assert.equal(state.room_states[privateRoom]?.observed, false);
    assert.equal(state.enemies.some(enemy => enemy.id === 'unseen'), false);
  }
}
async function queue(commands) {
  // Main's schema-1 plan export/import issues each roster member's complete
  // queue in order. Use that same initial issue order so retry preserves the
  // global command IDs too; per-unit primitives/arguments remain unchanged.
  const roster = (await latest()).units;
  const grouped = roster.flatMap(unit => commands.filter(command => command.unit_id === unit.id));
  assert.equal(grouped.length, commands.length, 'Every fixture command must belong to the actual roster');
  for (const command of grouped) await send({ action: 'command', ...command });
  await renderAck();
  const state = await latest();
  for (const unit of state.units) assert.deepEqual(unit.commands.map(command => ({ type: command.type, args: command.args })),
    commands.filter(command => command.unit_id === unit.id).map(({ type, args }) => ({ type, args })));
  assert.deepEqual(state.units.flatMap(unit => unit.commands.map(command => ({ id: command.id,
    sequence: command.sequence, owner_id: command.owner_id }))), grouped.map((command, index) => ({
    id: `${command.unit_id}-${String(index + 1).padStart(4, '0')}`, sequence: index + 1, owner_id: command.unit_id,
  })));
}
async function retryPlan(missionId) {
  await page.locator('#retry-plan').click();
  await waitNative(id => window.roomControlQA.state?.mode === 'PLANNING' && window.roomControlQA.state.mission === id
    && window.roomControlQA.state.time === 0 && window.roomControlQA.state.units.some(unit => unit.commands.length), missionId);
  await renderAck();
}
async function callCopy(types, lang) {
  const result = await page.evaluate(async ({ types, lang }) => {
    const { t, translateEvent, getLanguage } = await import('./i18n.js');
    const qa = window.roomControlQA, own = new Map(qa.state.units.map(unit => [unit.id, unit.name]));
    const calls = qa.events.filter(event => event.mission === qa.state.mission && event.run === qa.run && types.includes(event.type));
    return { lang: getLanguage(), calls: calls.map(event => ({ type: event.type, translated: translateEvent(event, {
      ownUnitName: id => own.get(id) || '', observedRoomName: id => qa.state.room_states[id]?.observed ? id : '',
    }), text: t(`event.${event.type}`) })), log: document.querySelector('#operation-log').textContent };
  }, { types, lang });
  assert.equal(result.lang, lang);
  for (const type of types) {
    const call = result.calls.find(call => call.type === type);
    assert.ok(call, `Actual native ${type} must exist before translation checks`);
    assert.ok(call.translated.includes(call.text));
    assert.equal(/[가-힣]/.test(call.translated), lang === 'ko');
  }
  report.callTranslations.push({ language: lang, mission: (await latest()).mission, calls: result.calls });
  return result;
}
async function rearStat(expected, lang) {
  const stat = await page.evaluate(label => [...document.querySelectorAll('#result-stats div')]
    .find(row => row.querySelector('dt')?.textContent === label)?.querySelector('dd')?.textContent,
  lang === 'en' ? 'Rear hits' : '후방 피격');
  assert.equal(stat, String(expected));
}
function signedDegrees(angle) {
  const tau = Math.PI * 2;
  return Math.round((((angle + Math.PI) % tau + tau) % tau - Math.PI) * 180 / Math.PI);
}
function sectorWidthDegrees(sector) {
  const tau = Math.PI * 2;
  return Math.round(((sector.end - sector.start + tau) % tau) * 180 / Math.PI);
}
function assertPreviewAngles(preview, mission) {
  const door = mission.doors.find(door => door.id === preview.door_id);
  const inward = door.axis === 'x' ? [0, -preview.entry_side] : [-preview.entry_side, 0];
  const across = door.axis === 'x' ? [1, 0] : [0, 1];
  for (const slot of preview.slots) {
    const direction = [slot.face_target[0] - slot.domination[0], slot.face_target[1] - slot.domination[1]];
    const face = Math.atan2(direction[1], direction[0]);
    const side = Math.sign((slot.stack[0] - door.x) * across[0] + (slot.stack[1] - door.z) * across[1]);
    const entry = slot.index <= 2 || !slot.entry ? face
      : Math.atan2(inward[1] + across[1] * side * 0.6, inward[0] + across[0] * side * 0.6);
    // Geometry authors the cones in whole degrees (45/80-degree half angles).
    // Normalize only this semantic measurement: atan2's binary32 boundary and
    // cancellation of 15-digit JSON endpoints need not share native/WASM bits.
    // Command start/end values below still compare exactly to the raw preview.
    assert.equal(sectorWidthDegrees(slot.sector_entry), 90);
    assert.equal(sectorWidthDegrees(slot.sector_domination), 160);
    assert.equal(signedDegrees(slot.sector_entry.center), signedDegrees(entry));
    assert.equal(signedDegrees(slot.sector_domination.center), signedDegrees(face));
    assert.equal(slot.sector_entry.duration, 12); assert.equal(slot.sector_domination.duration, 12);
    assert.equal(slot.role, slot.entry ? 'entry' : 'guard');
  }
}
function staticPreviewGeometry(preview) {
  const geometry = structuredClone(preview);
  for (const slot of geometry.slots) for (const key of ['sector_entry', 'sector_domination', 'sector']) {
    for (const angle of ['start', 'end', 'center']) delete slot[key]?.[angle];
  }
  return geometry;
}
function canonicalPreviewAngle(angle) {
  // Command metadata takes an additional Godot JSON roundtrip. Its fractional
  // format turns the published ±2.18556950315474e-8 into ±2.185569503e-8.
  // Both the native positive control and actual WASM plan verify this exact
  // format below; this is serialization, not an angular comparison epsilon.
  return Number(angle.toFixed(17));
}
function commandsFromPreview(unitPlans, preview) {
  return unitPlans.map(unit => ({ ...unit, commands: unit.commands.map(command => {
    const node = structuredClone(command);
    if (node.args.sector) {
      assert.ok(['entry', 'domination', 'guard'].includes(node.args.drill.stage));
      const slot = preview.slots.find(slot => slot.unit_id === unit.id);
      const fan = node.type === 'FACE' ? slot.sector_domination : slot.sector_entry;
      assert.equal(fan.duration, node.args.sector.duration);
      assert.equal(sectorWidthDegrees(node.args.sector), node.type === 'FACE' ? 160 : 90);
      node.args.sector = { start: canonicalPreviewAngle(fan.start),
        end: canonicalPreviewAngle(fan.end), duration: fan.duration };
    }
    return node;
  }) }));
}
function remapFromPreview(reference, preview) {
  const answer = structuredClone(reference);
  for (const target of answer.preview.targets) {
    if (target.order < 3) {
      const source = preview.slots.find(slot => JSON.stringify(slot.domination) === JSON.stringify(target.target));
      assert.ok(source, 'Each near control point is retained from the actual four-person preview');
      assert.deepEqual(source.face_target, target.face_target);
      Object.assign(target.sector, { start: canonicalPreviewAngle(source.sector_domination.start),
        end: canonicalPreviewAngle(source.sector_domination.end), duration: source.sector_domination.duration });
    } else {
      const [third, fourth] = preview.slots.slice(2).map(slot => slot.sector_domination);
      // This authored fixture's far cones overlap around the forward heading.
      // Their union retains the exact original outer edges, with no epsilon.
      assert.ok(third.start < fourth.start && third.end > fourth.start && fourth.end < 0);
      assert.equal(target.role, 'merged_far');
      Object.assign(target.sector, { start: canonicalPreviewAngle(third.start), end: canonicalPreviewAngle(fourth.end),
        duration: Math.max(third.duration, fourth.duration) });
    }
  }
  return answer;
}
let previewSequence = 0;
async function requestDrillPreview(door_id, order) {
  const preview_id = `p3-live-preview-${++previewSequence}`;
  await send({ action: 'room_drill_preview', door_id, method: 'OPEN_DOOR', order,
    options: { append: true }, preview_id });
  await waitNative(id => window.roomControlQA.messages.some(message => message.type === 'room_drill_preview'
    && message.preview_id === id), preview_id);
  const preview = await page.evaluate(id => window.roomControlQA.messages.find(message => message.type === 'room_drill_preview'
    && message.preview_id === id).data, preview_id);
  assert.equal(preview.ok, true); return preview;
}
function remap(state, reference) {
  const alive = state.units.filter(unit => unit.hp > 0);
  assert.deepEqual(alive.map(unit => unit.id), reference.survivors);
  assert.equal(state.units.find(unit => unit.id === 'alpha').hp, 0);
  assert.equal(state.units.flatMap(unit => unit.commands).filter(command => command.type === 'OPEN_DOOR').length, 1);
  assert.equal(reference.preview.entry_count, 3);
  for (const target of reference.preview.targets) {
    const unit = alive.find(unit => unit.id === target.unit_id);
    const nodes = unit.commands.filter(command => command.args.drill?.stage === 'domination' && command.state !== 'CANCELLED');
    const move = nodes.find(command => command.type === 'MOVE'), face = nodes.find(command => command.type === 'FACE');
    assert.ok(move && face);
    assert.equal(move.args.drill.order, target.order); assert.equal(face.args.drill.order, target.order);
    assert.deepEqual(move.args.target, target.target); assert.deepEqual(face.args.target, target.face_target);
    const sector = { start: target.sector.start, end: target.sector.end, duration: target.sector.duration };
    assert.deepEqual(move.args.sector, sector); assert.deepEqual(face.args.sector, sector);
  }
  const far = reference.preview.targets.find(target => target.order === 3);
  assert.equal(far.role, 'merged_far');
}
async function remapTimeline(reference, lang) {
  const rows = await page.locator('#drill-timeline [data-drill-row]').evaluateAll(nodes => nodes.map(node => {
    const primary = node.querySelector('[data-drill-primary]');
    return { id: node.dataset.drillRow, number: primary.querySelector('.drill-number').textContent,
      disabled: primary.disabled, down: primary.classList.contains('drill-unit-down'),
      label: primary.querySelector('.drill-number').getAttribute('aria-label'),
      status: primary.querySelector('small')?.textContent || '' };
  }));
  // P3 retains the casualty's command history while only living operators own
  // ranks 1–3. A three-row expectation would incorrectly discard that history.
  assert.deepEqual(rows.map(row => row.id), [...reference.survivors, 'alpha']);
  for (const [index, id] of reference.survivors.entries()) {
    assert.deepEqual(rows[index], { id, number: String(index + 1), disabled: false,
      down: false, label: null, status: '' });
  }
  const incapacitated = lang === 'ko' ? '행동 불능' : 'Incapacitated';
  assert.deepEqual(rows.at(-1), { id: 'alpha', number: '×', disabled: true,
    down: true, label: incapacitated, status: incapacitated });
}
async function planContact(reference) {
  await load(reference.mission);
  const ids = reference.mission.units.map(unit => unit.id);
  await send({ action: 'select', unit_id: ids[0] });
  for (const id of ids.slice(1)) await send({ action: 'select', unit_id: id, extend: true });
  const preview = await requestDrillPreview('door', ids);
  assertPreviewAngles(preview, reference.mission);
  assert.equal(preview.slots.length, 4); assert.equal(preview.entry_count, 4);
  for (const slot of preview.slots) assert.equal(slot.sector_domination.radius, reference.preview.targets[0].sector.radius);
  await send({ action: 'room_drill', door_id: 'door', method: 'OPEN_DOOR', order: ids, options: { append: true } });
  await renderAck();
  const state = await latest(); assert.deepEqual(state.selected_units, ids);
  for (const unit of commandsFromPreview(reference.initial_commands, preview)) assert.deepEqual(state.units.find(actor => actor.id === unit.id).commands.map(command => ({ type: command.type, args: command.args })), unit.commands);
  return preview;
}
async function survivingGoals(reference) {
  for (const id of reference.survivors) await send({ action: 'command', unit_id: id, type: 'RELOAD', args: {} });
  await renderAck();
  if ((await latest()).mode === 'PLANNING') await page.locator('#toggle-execution').click();
  await waitNative(reference => {
    const state = window.roomControlQA.state;
    return state?.mode === 'EXECUTING' && reference.survivors.every(id => {
      const unit = state.units.find(unit => unit.id === id);
      const moves = unit?.commands.filter(command => command.type === 'MOVE' && command.args.drill?.stage === 'domination' && command.state !== 'CANCELLED');
      const goal = reference.targets[id];
      return unit?.hp > 0 && moves.length > 0 && moves.every(command => command.state === 'SUCCEEDED')
        && Math.hypot(unit.x - goal[0], unit.z - goal[1]) <= 0.1;
    });
  }, reference);
  await page.locator('#toggle-execution').click(); await waitNative(() => window.roomControlQA.state?.mode === 'PLANNING');
  const state = await latest(); remap(state, reference);
  assert.equal(state.command_failures, 0); return state;
}

try {
  await boot();
  await settings();
  assert.equal(await page.locator('[data-setting-toggle="auto_pause_man_down"]').getAttribute('aria-pressed'), 'false');
  const initial = await autoPause(true);
  pass('MAN DOWN 자동 정지는 기본 OFF이며 실제 버튼/네이티브 ACK/IDB boolean ON을 보존한다');
  const [download] = await Promise.all([page.waitForEvent('download'), page.locator('#export-settings').click()]);
  const settingsPath = out + '/settings-true.json'; await download.saveAs(settingsPath);
  const file = JSON.parse(await readFile(settingsPath, 'utf8'));
  assert.equal(file.kind, 'breach-settings'); assert.equal(file.schema_version, 1);
  assert.equal(file.settings.auto_pause_man_down, true);
  const disabled = await autoPause(false); assert.ok(disabled.version > initial.version);
  const beforeImport = await page.evaluate(() => window.roomControlQA.sent.length);
  await page.locator('#import-settings').click(); await page.locator('#file-import').setInputFiles(settingsPath);
  await settingsAck(beforeImport, { auto_pause_man_down: true });
  const imported = await savedSettings({ auto_pause_man_down: true }); assert.ok(imported.version > disabled.version);
  assert.equal(await page.locator('[data-setting-toggle="auto_pause_man_down"]').getAttribute('aria-pressed'), 'true');
  pass('동일 schema-1 설정 파일 내보내기/실제 입력 가져오기가 ON boolean과 증가한 저장 버전을 복원한다');
  await closeSettings();
  await boot(); await settings();
  assert.equal(await page.locator('[data-setting-toggle="auto_pause_man_down"]').getAttribute('aria-pressed'), 'true');
  await autoPause(false); await closeSettings();
  pass('같은 context 실제 페이지 재시작 뒤 IDB 설정을 복원하고 OFF도 네이티브에 적용한다');

  await language('ko'); await load(native.reload.mission); await queue(native.reload.commands);
  await page.locator('#toggle-execution').click();
  await waitNative(() => window.roomControlQA.state?.units.find(unit => unit.id === 'alpha')?.reload_remaining > 0
    && window.roomControlQA.state.units.find(unit => unit.id === 'bravo')?.status === 'COVERING_RELOAD');
  const lease = await latest();
  assert.deepEqual(lease.units.find(unit => unit.id === 'bravo').commands.map(command => ({ type: command.type, args: command.args })),
    native.reload.commands.filter(command => command.unit_id === 'bravo').map(({ type, args }) => ({ type, args })));
  const reloading = await callCopy(['CALL_CLEAR', 'CALL_RELOADING'], 'ko');
  for (const call of reloading.calls) assert.ok(reloading.log.includes(call.text));
  await page.screenshot({ path: out + '/reload-cover-ko.png' });
  pass('실제 재장전이 가장 가까운 아군의 기존 큐를 보존하며 RELOADING 한국어 로그를 표시한다');
  await waitNative(() => window.roomControlQA.state?.mode === 'EXECUTING' && window.roomControlQA.state.room_states.room.state === 'CLEAR');
  const liveClearKo = await callCopy(['CALL_GUN_UP', 'CALL_ROOM_CLEAR'], 'ko');
  for (const call of liveClearKo.calls) assert.ok(liveClearKo.log.includes(call.text));
  await page.screenshot({ path: out + '/searched-clear-ko.png' });
  await waitNative(() => window.roomControlQA.state?.mode === 'RESULT');
  const reloadResult = await latest(); publicRooms(reloadResult);
  assert.equal(reloadResult.result.success, true);
  assert.equal(reloadResult.units.find(unit => unit.id === 'alpha').ammo, 24);
  assert.equal(reloadResult.units.find(unit => unit.id === 'bravo').facing, native.reload.previous_cover.facing);
  assert.deepEqual(reloadResult.units.find(unit => unit.id === 'bravo').sector, native.reload.previous_cover.sector);
  await callCopy(['CALL_CLEAR', 'CALL_RELOADING', 'CALL_GUN_UP', 'CALL_ROOM_CLEAR'], 'ko');
  await rearStat(0, 'ko'); await page.screenshot({ path: out + '/reload-result-ko.png' });
  pass('GUN UP이 실제 엄호 FACE/sector를 복원하고 45 STEP 검색 뒤 관측된 CLEAR 및 후방 피격 0 결과를 표시한다');
  // RESULT hides the live settings button. Use the real saved-plan retry,
  // change language while planning, and run the identical native plan again.
  await retryPlan(native.reload.mission.id); await language('en');
  await page.locator('#toggle-execution').click();
  await waitNative(() => window.roomControlQA.state?.units.find(unit => unit.id === 'alpha')?.reload_remaining > 0
    && window.roomControlQA.state.units.find(unit => unit.id === 'bravo')?.status === 'COVERING_RELOAD');
  const reloadingEn = await callCopy(['CALL_CLEAR', 'CALL_RELOADING'], 'en');
  for (const call of reloadingEn.calls) assert.ok(reloadingEn.log.includes(call.text));
  await page.screenshot({ path: out + '/reload-cover-en.png' });
  await waitNative(() => window.roomControlQA.state?.mode === 'EXECUTING' && window.roomControlQA.state.room_states.room.state === 'CLEAR');
  const liveClearEn = await callCopy(['CALL_GUN_UP', 'CALL_ROOM_CLEAR'], 'en');
  for (const call of liveClearEn.calls) assert.ok(liveClearEn.log.includes(call.text));
  await waitNative(() => window.roomControlQA.state?.mode === 'RESULT');
  assert.equal((await latest()).tick, reloadResult.tick);
  assert.deepEqual((await latest()).units, reloadResult.units);
  await callCopy(['CALL_CLEAR', 'CALL_RELOADING', 'CALL_GUN_UP', 'CALL_ROOM_CLEAR'], 'en'); await rearStat(0, 'en');
  await page.screenshot({ path: out + '/reload-result-en.png' });
  pass('동일 실제 사건과 디브리핑 후방 피격을 영어로 재표시한다');

  await load(native.short.mission); publicRooms(await latest(), 'private');
  const ids = native.short.mission.units.map(unit => unit.id);
  await send({ action: 'select', unit_id: ids[0] });
  for (const id of ids.slice(1)) await send({ action: 'select', unit_id: id, extend: true });
  const preview = await requestDrillPreview('entry', ids);
  assert.equal(preview.ok, true); assert.equal(preview.short_room, true);
  assert.equal(preview.slots.filter(slot => slot.entry).length, 2);
  assertPreviewAngles(native.short.preview, native.short.mission);
  assertPreviewAngles(preview, native.short.mission);
  assert.deepEqual(staticPreviewGeometry(preview), staticPreviewGeometry(native.short.preview));
  assert.deepEqual(commandsFromPreview(native.short.initial_commands, native.short.preview), native.short.initial_commands);
  await send({ action: 'room_drill', door_id: 'entry', method: 'OPEN_DOOR', order: ids, options: { append: true } });
  await renderAck();
  const plan = await latest();
  for (const unit of commandsFromPreview(native.short.initial_commands, preview)) assert.deepEqual(plan.units.find(actor => actor.id === unit.id).commands.map(command => ({ type: command.type, args: command.args })), unit.commands);
  await page.locator('#toggle-execution').click();
  await waitNative(() => window.roomControlQA.state?.mode === 'EXECUTING' && window.roomControlQA.state.events.some(event => event.type === 'CALL_SHORT_ROOM'));
  const shortEntryEn = await callCopy(['CALL_SHORT_ROOM'], 'en'); assert.ok(shortEntryEn.log.includes(shortEntryEn.calls[0].text));
  await page.screenshot({ path: out + '/short-call-en.png' });
  await waitNative(() => window.roomControlQA.state?.mode === 'EXECUTING' && window.roomControlQA.state.room_states.target.state === 'CLEAR');
  const liveShortEn = await callCopy(['CALL_SHORT_ROOM', 'CALL_CLEAR', 'CALL_ROOM_CLEAR'], 'en');
  for (const call of liveShortEn.calls.filter(call => call.type === 'CALL_ROOM_CLEAR')) assert.ok(liveShortEn.log.includes(call.text));
  await waitNative(() => window.roomControlQA.state?.mode === 'RESULT');
  const shortResult = await latest(); publicRooms(shortResult, 'private');
  assert.equal(shortResult.result.success, true);
  assert.equal(shortResult.room_states.target.state, 'CLEAR');
  assert.equal(shortResult.room_states.target.observed, true);
  await callCopy(['CALL_SHORT_ROOM', 'CALL_CLEAR', 'CALL_ROOM_CLEAR'], 'en');
  const shortMessages = await page.evaluate(() => document.querySelector('#operation-log').textContent);
  assert.equal(shortMessages.includes('PRIVATE'), false); assert.equal(shortMessages.includes('UNSEEN'), false);
  await page.screenshot({ path: out + '/short-clear-en.png' });
  pass('실제 SHORT barrier와 2인 수색이 완료돼도 숨은 적과 관측하지 않은 방 정리 상태/이름을 노출하지 않는다');
  await retryPlan(native.short.mission.id); await language('ko');
  await page.locator('#toggle-execution').click();
  await waitNative(() => window.roomControlQA.state?.mode === 'EXECUTING' && window.roomControlQA.state.events.some(event => event.type === 'CALL_SHORT_ROOM'));
  const shortEntryKo = await callCopy(['CALL_SHORT_ROOM'], 'ko'); assert.ok(shortEntryKo.log.includes(shortEntryKo.calls[0].text));
  await page.screenshot({ path: out + '/short-call-ko.png' });
  await waitNative(() => window.roomControlQA.state?.mode === 'EXECUTING' && window.roomControlQA.state.room_states.target.state === 'CLEAR');
  const liveShortKo = await callCopy(['CALL_SHORT_ROOM', 'CALL_CLEAR', 'CALL_ROOM_CLEAR'], 'ko');
  for (const call of liveShortKo.calls.filter(call => call.type === 'CALL_ROOM_CLEAR')) assert.ok(liveShortKo.log.includes(call.text));
  await waitNative(() => window.roomControlQA.state?.mode === 'RESULT');
  const shortKorean = await latest(); publicRooms(shortKorean, 'private');
  assert.equal(shortKorean.tick, shortResult.tick); assert.deepEqual(shortKorean.units, shortResult.units);
  await callCopy(['CALL_SHORT_ROOM', 'CALL_CLEAR', 'CALL_ROOM_CLEAR'], 'ko');
  const shortHistory = await page.evaluate(id => ({
    states: window.roomControlQA.states.filter(state => state.mission === id),
    clearFX: window.roomControlQA.messages.filter(message => message.type === 'fx' && message.kind === 'room_clear'),
  }), native.short.mission.id);
  for (const state of shortHistory.states) publicRooms(state, 'private');
  assert.equal(shortHistory.clearFX.some(effect => effect.room_id === 'private'), false);
  pass('동일 실제 SHORT ROOM 신호가 한국어로도 표시된다');

  await retryPlan(native.short.mission.id); await settings(); await autoPause(true); await closeSettings();
  const enabled = remapFromPreview(native.man_down.true, await planContact(native.man_down.true));
  // A living primary remains selected after another operator falls. Select
  // the wounded point operator first so this fixture exercises the existing
  // dead-primary fallback to bravo while preserving the four-person group.
  await send({ action: 'select', unit_id: 'alpha', preserve_group: true });
  await renderAck();
  const beforeCasualty = await latest();
  assert.equal(beforeCasualty.selected, 'alpha');
  assert.deepEqual(beforeCasualty.selected_units, enabled.mission.units.map(unit => unit.id));
  await page.locator('#toggle-execution').click();
  await waitNative(() => window.roomControlQA.state?.mode === 'PLANNING'
    && window.roomControlQA.state.units.filter(unit => unit.hp <= 0).length === 1
    && window.roomControlQA.messages.some(message => message.type === 'toast' && message.i18n_key === 'team.man_down_paused'));
  const paused = await latest(); remap(paused, enabled);
  assert.equal(paused.tick, enabled.death.tick);
  assert.deepEqual(paused.selected_units, enabled.survivors);
  assert.equal(paused.selected, enabled.survivors[0]);
  assert.equal(paused.pause_requested, false); assert.equal(paused.pause_reason, '');
  await renderAck(); await renderAck(); assert.equal((await latest()).tick, paused.tick);
  await remapTimeline(enabled, 'ko');
  const downKo = await callCopy(['CALL_MAN_DOWN'], 'ko');
  assert.ok(downKo.log.includes(downKo.calls[0].text));
  await page.screenshot({ path: out + '/man-down-remap-ko.png' });
  report.cases.push({ case: 'auto-pause-on', paused, preview: enabled.preview });
  pass('실제 피격 MAN DOWN은 ON에서 같은 native STEP에 정지·ACK하고 살아있는 3인 선택/새 MOVE·FACE 목표·합친 구역을 표시한다');
  const survived = await survivingGoals(enabled);
  report.cases.push({ case: 'auto-pause-on-resumed', tick: survived.tick, units: survived.units });
  pass('자동 정지 뒤 실제 재개한 3인 전원이 새 MOVE 목표를 성공하고 문 처리는 정확히 한 번 유지된다');

  await language('en'); await settings(); await autoPause(false); await closeSettings();
  const disabledNative = native.man_down.false;
  const beforeDisabled = await page.evaluate(() => window.roomControlQA.messages.length);
  const disabledContact = remapFromPreview(disabledNative, await planContact(disabledNative));
  await page.locator('#toggle-execution').click();
  await waitNative(tick => window.roomControlQA.state?.mode === 'EXECUTING'
    && window.roomControlQA.state.tick > tick && window.roomControlQA.state.units.filter(unit => unit.hp <= 0).length === 1,
  disabledContact.death.tick);
  const continuing = await latest(); remap(continuing, disabledContact);
  assert.equal(await page.evaluate(before => window.roomControlQA.messages.slice(before).some(message => message.type === 'toast'
    && message.i18n_key === 'team.man_down_paused'), beforeDisabled), false);
  const downEn = await callCopy(['CALL_MAN_DOWN'], 'en'); assert.ok(downEn.log.includes(downEn.calls[0].text));
  await page.locator('#toggle-execution').click(); await waitNative(() => window.roomControlQA.state?.mode === 'PLANNING');
  await renderAck(); await remapTimeline(disabledContact, 'en');
  await page.screenshot({ path: out + '/man-down-remap-en.png' });
  report.cases.push({ case: 'auto-pause-off', tick: continuing.tick, preview: disabledContact.preview });
  pass('OFF에서 같은 실제 사상자와 3인 재편성 후 실행 시간이 계속 진행되고 영어 MAN DOWN 로그를 표시한다');

  // Real schema-1 numeric file import/seek exercises the decoder, then the
  // shipped debrief formatter receives that exact native legacy RESULT.
  // Missing optional counters mean zero without inventing room observations.
  const legacyPath = out + '/legacy-no-p3-fields.replay.json';
  await writeFile(legacyPath, JSON.stringify(native.legacy_replay));
  await send({ action: 'menu' }); await waitNative(() => window.roomControlQA.state?.mode === 'MENU');
  await page.locator('#briefing-screen [data-nav="select"]').click();
  await page.locator('#select-screen [data-nav="title"]').click();
  await finishAnimations('#title-screen'); await page.locator('#title-library').click();
  const beforeLegacy = await page.evaluate(() => window.roomControlQA.sent.length);
  await page.locator('#import-replay').click(); await page.locator('#file-import').setInputFiles(legacyPath);
  await waitNative(({ before, id }) => window.roomControlQA.state?.mode === 'REPLAY' && window.roomControlQA.state.mission === id
    && window.roomControlQA.sent.slice(before).some(intent => intent.action === 'import_replay')
    && document.querySelector('#loading').hidden && !document.querySelector('#transition-loading').open,
  { before: beforeLegacy, id: native.legacy_replay.map_id });
  if ((await latest()).replay.playing) await page.locator('#replay-toggle').click();
  await waitNative(() => window.roomControlQA.state?.replay.playing === false);
  const beforeEnd = await page.evaluate(() => window.roomControlQA.sent.length);
  await page.locator('#replay-seek').press('End');
  await waitDom(before => {
    const seek = window.roomControlQA.sent.slice(before).findLast(intent => intent.action === 'replay_seek');
    return seek && seek.time === Number(document.querySelector('#replay-seek').value);
  }, beforeEnd);
  const endInput = await page.evaluate(before => ({
    intent: window.roomControlQA.sent.slice(before).findLast(intent => intent.action === 'replay_seek'),
    value: Number(document.querySelector('#replay-seek').value),
  }), beforeEnd);
  assert.equal(endInput.intent.time, endInput.value);
  await waitNative(time => window.roomControlQA.state?.replay.time === time, endInput.intent.time);
  await renderAck();
  // The HTML range may align End to its final 0.05 step below a fractional
  // duration. Observe that real input first, then play the actual remaining
  // frames to the exact native endpoint; no seek value or state is injected.
  if ((await latest()).replay.time < (await latest()).replay.duration) await page.locator('#replay-toggle').click();
  await waitNative(() => window.roomControlQA.state?.replay.time === window.roomControlQA.state?.replay.duration
    && window.roomControlQA.state.replay.playing === false);
  await renderAck();
  const legacyState = await latest(); publicRooms(legacyState);
  assert.equal(legacyState.result.success, true); assert.equal(Object.hasOwn(legacyState.result, 'rear_hits'), false);
  assert.deepEqual(legacyState.room_states, {});
  const legacyStats = await page.evaluate(async () => {
    const { resultStatistics } = await import('./app.js');
    return resultStatistics(window.roomControlQA.state);
  });
  assert.deepEqual(legacyStats.find(([label]) => label === 'Rear hits'), ['Rear hits', '0']);
  assert.equal(native.legacy_replay.schema_version, 1); assert.equal(native.legacy_replay.encoding, 'numeric-state-v1');
  report.legacy = { endInput, tick: legacyState.tick, result: legacyState.result, stats: legacyStats };
  await page.screenshot({ path: out + '/legacy-observed-replay.png' });
  pass('실제 numeric-state-v1 파일 가져오기/끝 seek는 과거 RESULT를 보존하며 새 rear_hits가 없는 디브리핑은 0으로 해석한다');

  const callTypes = ['CALL_CLEAR', 'CALL_ROOM_CLEAR', 'CALL_SHORT_ROOM', 'CALL_RELOADING', 'CALL_GUN_UP', 'CALL_MAN_DOWN'];
  for (const lang of ['ko', 'en']) assert.deepEqual([...new Set(report.callTranslations.filter(item => item.language === lang)
    .flatMap(item => item.calls.map(call => call.type)))].sort(), [...callTypes].sort());
  pass('여섯 신규 CALL이 모두 실제 native 사건으로 발생하고 한국어·영어 번역을 검증한다');

  assert.deepEqual(errors, []); assert.deepEqual(failedRequests, []);
  report.calls = await page.evaluate(() => window.roomControlQA.events.filter(event => /^CALL_/.test(event.type)));
  report.status = 'PASS'; report.failures = 0;
  console.log(`BREACH_ROOM_CONTROL_UI_RESULT checks=${report.checks.length} failures=0`);
} catch (error) {
  report.status = 'FAIL'; report.failure = error.stack;
  report.diagnostic = await page.evaluate(() => ({ state: window.roomControlQA.state, sent: window.roomControlQA.sent.slice(-70), messages: window.roomControlQA.messages.slice(-70), events: window.roomControlQA.events,
    activeElement: document.activeElement?.outerHTML, modalOpen: document.querySelector('#modal')?.open })).catch(() => ({}));
  await page.screenshot({ path: out + '/failure.png' }).catch(() => {}); throw error;
} finally {
  await writeFile(out + '/report.json', JSON.stringify(report, null, 2)); await browser.close();
}
