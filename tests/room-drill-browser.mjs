import { chromium } from 'playwright';
import assert from 'node:assert/strict';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { setCycler } from './lib/menu.mjs';

// P2 uses the shipped bridge, DOM controls and native engine. Fixed seed 42,
// a genuinely unseen sealed-room hostile, and actual command acknowledgements
// keep these checks independent of AI luck and elapsed browser delays.
const url = new URL(process.env.BREACH_URL || 'http://127.0.0.1:8080');
url.searchParams.set('qa', '1');
const out = process.env.BREACH_ARTIFACTS || 'tests/artifacts/room-drill-browser';
await mkdir(out, { recursive: true });
const browser = await chromium.launch({
  channel: process.env.BREACH_CHANNEL || 'chrome', headless: process.env.BREACH_HEADLESS !== '0',
  args: ['--enable-unsafe-swiftshader'],
});
const context = await browser.newContext({ viewport: { width: 1440, height: 900 }, acceptDownloads: true });
await context.addInitScript(() => {
  let ui;
  window.roomDrillQA = { state: null, states: [], messages: [], plans: [], replays: [], catalog: {}, sent: [], events: [], eventKeys: new Set() };
  Object.defineProperty(window, 'BreachUI', {
    configurable: true, get: () => ui,
    set(value) {
      ui = value;
      const receive = value.receive;
      value.receive = function(raw) {
        const message = typeof raw === 'string' ? JSON.parse(raw) : raw, qa = window.roomDrillQA;
        if (message.type === 'state') {
          qa.state = message; qa.states.push(message);
          if (qa.states.length > 600) qa.states.shift();
          for (const event of message.events || []) {
            const key = `${message.mission}:${event.seq}:${event.tick}:${event.type}:${event.sync_id || ''}`;
            if (!qa.eventKeys.has(key)) { qa.eventKeys.add(key); qa.events.push(event); }
          }
        } else {
          qa.messages.push(message);
          if (qa.messages.length > 500) qa.messages.shift();
        }
        if (message.type === 'plan_data') qa.plans.push(message.data);
        if (message.type === 'replay_data') qa.replays.push(message.data);
        if (['ready', 'catalog_update'].includes(message.type)) Object.assign(qa.catalog, message.catalog || {});
        return receive.call(this, raw);
      };
    },
  });
});
const page = await context.newPage();
// Preserve actionability and navigation checks while allowing native-render
// CDP replies the same bounded budget as the existing complete UI suite.
page.setDefaultTimeout(300000);
const errors = [], failedRequests = [];
page.on('pageerror', error => errors.push(error.message));
page.on('console', message => {
  if (message.type() === 'error' || /SCRIPT ERROR|Parse Error|Failed loading resource/.test(message.text())) errors.push(message.text());
});
page.on('response', response => { if (response.status() >= 400) errors.push(`HTTP ${response.status()} ${response.url()}`); });
page.on('requestfailed', request => failedRequests.push({ url: request.url(), failure: request.failure()?.errorText }));
const report = { url: url.href, version: browser.version(), checks: [], errors, failedRequests, previews: [], delays: [] };
const pass = name => { report.checks.push(name); console.log(`PASS ${name}`); };
const latest = () => page.evaluate(() => window.roomDrillQA.state);
const waitDom = (predicate, argument = null) => page.waitForFunction(predicate, argument, { timeout: 45000 });
const waitNative = (predicate, argument = null) => page.waitForFunction(predicate, argument, { timeout: 300000 });
const send = data => page.evaluate(data => window.BreachBridge.send(JSON.stringify(data)), data);
const ids = ['alpha', 'bravo', 'charlie', 'delta'];
const primitiveTypes = new Set(['MOVE', 'WAIT_FOR_SIGNAL', 'OPEN_DOOR', 'KICK_DOOR', 'OPEN_AND_FLASH', 'BREACH_DOOR', 'SHOTGUN_BREACH', 'FACE']);

function fixture(shortRoom = false) {
  const width = shortRoom ? 2.4 : 5, depth = shortRoom ? 3.6 : 5;
  const wall = (id, x, z, w, d) => ({ id, x, z, w, d, material: 'concrete', height: 2.8 });
  return {
    schema_version: 3, id: shortRoom ? 'ROOM_DRILL_SHORT_UI' : 'ROOM_DRILL_UI', revision: 1,
    title: '진입 드릴 검증', title_en: 'Room Entry Drill Check',
    description: '고정 시드 진입 드릴 검증 방입니다.', description_en: 'Fixed-seed room entry drill room.',
    seed: 42, default_seed: 42, bounds: [18, 14], focus: [9, 7], custom: true,
    rooms: [
      { id: 'ready_room', x: 4, z: 6, w: 6, d: 10, label: 'READY', indoor: true, lighting: 1 },
      { id: 'target_room', x: 7 + width / 2, z: 6, w: width, d: depth, label: 'ROOM', indoor: true, lighting: 1 },
      { id: 'sealed_room', x: (24 + width) / 2, z: 6, w: 10 - width, d: 5, label: 'SEALED', indoor: true, lighting: 1 },
    ],
    walls: [
      wall('ready_north', 4, 1, 6, 0.24), wall('ready_south', 4, 11, 6, 0.24), wall('ready_west', 1, 6, 0.24, 10),
      wall('partition_a', 7, 3.05, 0.24, 4.1), wall('partition_b', 7, 8.95, 0.24, 4.1),
      wall('target_north', 7 + width / 2, 6 - depth / 2, width, 0.24),
      wall('target_south', 7 + width / 2, 6 + depth / 2, width, 0.24),
      wall('private_partition_a', 7 + width, 4.45, 0.24, 1.9), wall('private_partition_b', 7 + width, 7.55, 0.24, 1.9),
      wall('sealed_north', (24 + width) / 2, 3.5, 10 - width, 0.24),
      wall('sealed_south', (24 + width) / 2, 8.5, 10 - width, 0.24), wall('sealed_east', 17, 6, 0.24, 5),
    ],
    doors: [{ id: 'entry', x: 7, z: 6, w: 0.24, d: 1.8, axis: 'z', label: 'ENTRY', state: 'CLOSED',
      material: 'wood', height: 2.1, hp: 100, locked: false, hinge_side: -1, swing_sign: -1,
      kick_resistance: 1, reinforced: false },
      { id: 'private_door', x: 7 + width, z: 6, w: 0.24, d: 1.2, axis: 'z', label: 'PRIVATE', state: 'CLOSED',
        material: 'wood', height: 2.1, hp: 100, locked: false, hinge_side: -1, swing_sign: -1,
        kick_resistance: 1, reinforced: false }],
    props: [],
    units: ids.map((id, index) => ({
      id, name: id.toUpperCase(), role: 'TEST', x: 5.4 - (index % 2) * 0.7, z: index < 2 ? 5.2 : 6.8,
      facing: 0, weapon: index === 0 ? 'shotgun' : 'standard', ammo: index === 0 ? 5 : 24,
      reserve_ammo: 0, equipment: { breach: 1 }, breaches: 1, stuns: 1, smokes: 0,
      sidearm: 'pico_p1', armor: 'none', helmet: 'none', stance: 'standing', movement_mode: 'normal',
    })),
    enemies: [{ id: 'unseen', name: 'UNSEEN', x: 15, z: 6, facing: Math.PI, weapon: 'standard', ammo: 24,
      hp: 100, enemy_type: 'sentry', passive: true }],
    civilians: [], objectives: ['진입 드릴을 검증하세요.'],
    // Existing inspection targets require stationary operators in both deep
    // corners after GO_LONG. The result therefore cannot interrupt the final
    // MOVE merely because its actor crossed a reach-zone boundary first.
    interactive_targets: shortRoom ? [] : [
      { id: 'finish_left', x: 11.0, z: 4.4, w: 0.25, d: 0.25, label: 'END LEFT', action: 'inspect', duration: 0.2 },
      { id: 'finish_right', x: 11.0, z: 7.6, w: 0.25, d: 0.25, label: 'END RIGHT', action: 'inspect', duration: 0.2 },
    ],
    win: shortRoom ? [{ type: 'reach_zone', zone: [1.8, 1.8, 0.4, 0.4] }]
      : [{ type: 'targets_complete', targets: ['finish_left', 'finish_right'] }], fail: [], stars: [],
    variant: 'normal', modifiers: [], environment: { time_of_day: 'day', lighting: 1 },
  };
}

async function finishAnimations(selector) {
  await page.evaluate(async selector => {
    await Promise.all(document.querySelector(selector).getAnimations({ subtree: true })
      .filter(animation => Number.isFinite(animation.effect?.getComputedTiming().endTime))
      .map(animation => animation.finished.catch(() => {})));
  }, selector);
}
async function waitTitle() {
  await page.locator('#title-start').waitFor({ state: 'visible' });
  await waitNative(() => window.roomDrillQA.state?.mode === 'MENU' && window.BreachBridge
    && document.querySelector('#loading').hidden && !document.querySelector('#transition-loading').open
    && !document.querySelector('#start-mission').disabled);
  await finishAnimations('#title-screen');
}
async function hudReady() {
  await page.locator('#hud').waitFor({ state: 'visible' });
  await waitNative(() => document.querySelector('#loading').hidden && !document.querySelector('#transition-loading').open);
  await finishAnimations('#hud');
  const token = await page.evaluate(() => {
    const qa = window.roomDrillQA, token = `room-drill-camera-${qa.cameraSequence = (qa.cameraSequence || 0) + 1}`;
    const right = document.querySelector('.hud-right').getBoundingClientRect();
    window.BreachBridge.send(JSON.stringify({ action: 'set_safe_area', _quality_token: token, data: {
      left: Math.round(document.querySelector('.hud-left').getBoundingClientRect().width),
      top: Math.round(document.querySelector('.hud-topbar').getBoundingClientRect().height),
      right: Math.max(0, Math.round(innerWidth - Math.max(right.left, 0))),
      bottom: Math.round(document.querySelector('.hud-hotbar').getBoundingClientRect().height),
    } }));
    return token;
  });
  await waitNative(token => window.roomDrillQA.states.some(state => state.mode === 'PLANNING' && state.quality?.ack_tokens?.includes(token)), token);
}
async function loadFixture(shortRoom = false) {
  const data = fixture(shortRoom);
  await send({ action: 'import_mission', data });
  await waitNative(id => {
    const state = window.roomDrillQA.state;
    return state?.mode === 'PLANNING' && state.mission === id && state.time === 0
      && state.units.length === 4 && state.units.every(unit => !unit.commands.length);
  }, data.id);
  await hudReady();
  assert.equal((await latest()).seed, 42);
  assert.deepEqual((await latest()).enemies, [], 'The sealed-room hostile must remain unseen');
}
async function selectGroup(group) {
  await page.locator(`.unit-card[data-unit="${group[0]}"]`).click();
  await waitDom(id => window.roomDrillQA.state?.selected === id && window.roomDrillQA.state.selected_units?.length === 1, group[0]);
  for (let index = 1; index < group.length; index++) {
    await page.locator(`.unit-card[data-unit="${group[index]}"]`).click({ modifiers: ['Shift'] });
    await waitDom(expected => JSON.stringify(window.roomDrillQA.state?.selected_units) === JSON.stringify(expected), group.slice(0, index + 1));
  }
  assert.equal(await page.locator('.unit-card[aria-pressed="true"]').count(), group.length);
}
async function setLanguage(language) {
  await page.locator('.hud-topbar [data-open="settings"]').click();
  await page.locator('[data-settings-tab="gameplay"]').click();
  await setCycler(page, '[data-cycler="language"]', language);
  await waitDom(language => document.documentElement.lang === language, language);
  await page.locator('#modal-close').click();
  await page.locator('#modal').waitFor({ state: 'hidden' });
}

// Same static mission footprint, live safe area and perspective as the existing
// P0/P1 browser input tests. This returns an ordinary map pointer coordinate.
async function mapPoint(x, z, y = 0.2) {
  return page.evaluate(({ x, z, y }) => {
    const qa = window.roomDrillQA, data = qa.catalog[qa.state.mission];
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
    if (Number(data.schema_version || 1) >= 2) { left = -1; right = data.bounds[0] + 1; top = -1; bottom = data.bounds[1] + 1; }
    const canvas = document.querySelector('#canvas').getBoundingClientRect(), rightRect = document.querySelector('.hud-right').getBoundingClientRect();
    const margin = 16, aspect = innerWidth / innerHeight;
    const safeLeft = Math.round(document.querySelector('.hud-left').getBoundingClientRect().width) + margin;
    const safeTop = Math.round(document.querySelector('.hud-topbar').getBoundingClientRect().height) + margin;
    const safeRight = Math.max(0, Math.round(innerWidth - Math.max(rightRect.left, 0))) + margin;
    const safeBottom = Math.round(document.querySelector('.hud-hotbar').getBoundingClientRect().height) + margin;
    const vertical = Math.min(0.97, Math.max(0.25, (innerHeight - safeTop - safeBottom) / innerHeight));
    const horizontal = Math.min(0.97, Math.max(0.25, (innerWidth - safeLeft - safeRight) / innerWidth));
    const size = Math.max((bottom - top) / vertical, (right - left) / Math.max(aspect * horizontal, 0.1));
    const scale = canvas.height / size, norm = Math.hypot(34, 15.5);
    return {
      x: canvas.left + canvas.width / 2 + (x - (left + right) / 2) * scale + (safeLeft - safeRight) / 2,
      y: canvas.top + canvas.height / 2 - (y * 15.5 / norm - (z - (top + bottom) / 2) * 34 / norm) * scale + (safeTop - safeBottom) / 2,
    };
  }, { x, z, y });
}
async function planFromButton() {
  const before = await page.evaluate(() => window.roomDrillQA.plans.length);
  await page.locator('#save-plan').click();
  await waitDom(before => window.roomDrillQA.plans.length > before, before);
  const plan = await page.evaluate(() => window.roomDrillQA.plans.at(-1));
  await waitDom(async expected => {
    const { BreachStorage } = await import('./storage.js'), storage = new BreachStorage();
    await storage.open();
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
    assert.deepEqual(actual.commands.map(command => ({ type: command.type, args: command.args })), unit.commands);
    assert(actual.commands.every(command => command.state === 'PENDING'));
    for (const key of ['stance', 'movement_mode', 'hold_position']) assert.equal(actual[key], unit[key]);
  }
}
async function loadingActionAck(action, before, mode) {
  await waitDom(({ action, before }) => window.roomDrillQA.sent.slice(before).some(message => message.action === action), { action, before });
  const token = `room-drill-load-${action}-${before}`;
  // File.text()/IndexedDB are asynchronous. Observe their actual load intent
  // first, then this FIFO post-render ACK proves the deferred load completed.
  await send({ action: 'pause', _quality_token: token });
  await waitNative(({ token, mode }) => window.roomDrillQA.states.some(state => state.mode === mode && state.quality?.ack_tokens?.includes(token)), { token, mode });
  await waitNative(() => document.querySelector('#loading').hidden && !document.querySelector('#transition-loading').open);
}
async function auditDrillGeometry(label) {
  const result = await page.evaluate(() => {
    const selectors = ['#drill-timeline', '#drill-timeline > header', '#hotbar-controls', '#toggle-execution',
      '#drill-timeline [data-sync-delay]', '#room-drill-panel', '#drill-commit'];
    const controlSelector = '#hotbar-controls .tools>button, #hotbar-controls .hotbar-utility>button, #hotbar-controls .hotbar-execute .signals>button, #toggle-execution';
    const controls = [...document.querySelectorAll(controlSelector)].filter(node => node.getClientRects().length).map(node => {
      const rect = node.getBoundingClientRect();
      const label = node.id || node.dataset.tool || `signal-${node.dataset.signal}`;
      const hit = document.elementFromPoint(rect.left + rect.width / 2, rect.top + rect.height / 2);
      return { label, left: rect.left, right: rect.right, top: rect.top, bottom: rect.bottom,
        width: rect.width, height: rect.height, hit: hit?.closest('button') === node, hitLabel: hit?.closest('button')?.id || hit?.tagName };
    });
    const rects = selectors.flatMap(selector => [...document.querySelectorAll(selector)]
      .filter(node => node.getClientRects().length).map(node => {
        const rect = node.getBoundingClientRect();
        return { selector, left: rect.left, right: rect.right, top: rect.top, bottom: rect.bottom, width: rect.width, height: rect.height };
      }));
    for (const node of document.querySelectorAll('#drill-timeline [data-drill-row]')) {
      const rect = node.getBoundingClientRect();
      rects.push({ selector: `[data-drill-row="${node.dataset.drillRow}"]`, left: rect.left, right: rect.right, top: rect.top, bottom: rect.bottom, width: rect.width, height: rect.height });
    }
    return { width: innerWidth, height: innerHeight, documentWidth: document.documentElement.scrollWidth, rects, controls };
  });
  report.geometry ||= [];
  report.geometry.push({ label, ...result });
  assert(result.documentWidth <= result.width + 1, `${label}: no horizontal page overflow`);
  assert.equal(result.rects.filter(rect => rect.selector.startsWith('[data-drill-row=')).length, 4);
  for (const rect of result.rects) {
    assert(rect.width > 0 && rect.height > 0, `${label}: ${rect.selector} has positive dimensions`);
    assert(rect.left >= -1 && rect.right <= result.width + 1 && rect.top >= -1 && rect.bottom <= result.height + 1,
      `${label}: ${rect.selector} must fit the visible viewport: ${JSON.stringify(rect)}`);
  }
  assert(result.controls.length >= 14, `${label}: all tool, utility, signal and execute controls remain visible`);
  for (const control of result.controls) {
    assert(control.width > 0 && control.height > 0, `${label}: ${control.label} has positive dimensions`);
    assert(control.left >= -1 && control.right <= result.width + 1 && control.top >= -1 && control.bottom <= result.height + 1,
      `${label}: individual ${control.label} control must fit the viewport: ${JSON.stringify(control)}`);
    assert(control.hit, `${label}: individual ${control.label} control must receive its center hit, got ${control.hitLabel}`);
  }
  for (const [index, first] of result.controls.entries()) for (const second of result.controls.slice(index + 1)) {
    const overlapX = Math.min(first.right, second.right) - Math.max(first.left, second.left);
    const overlapY = Math.min(first.bottom, second.bottom) - Math.max(first.top, second.top);
    assert(overlapX <= 1 || overlapY <= 1, `${label}: individual controls ${first.label} and ${second.label} overlap by ${overlapX}×${overlapY}px`);
  }
  pass(`${label}: the visible four-row timeline and drill panel fit, with every operation button unobscured and independently hittable`);
}

async function previewAfter(operation) {
  const before = await page.evaluate(() => window.roomDrillQA.sent.length);
  await operation();
  await waitNative(before => {
    const qa = window.roomDrillQA;
    const request = qa.sent.slice(before).filter(message => message.action === 'room_drill_preview' && message.preview_id).at(-1);
    if (!request) return false;
    const response = qa.messages.findLast(message => message.type === 'room_drill_preview' && message.preview_id === request.preview_id);
    return response && (!response.data?.ok || !document.querySelector('#drill-commit').disabled);
  }, before);
  const { preview, previewId } = await page.evaluate(before => {
    const qa = window.roomDrillQA;
    const request = qa.sent.slice(before).filter(message => message.action === 'room_drill_preview' && message.preview_id).at(-1);
    const response = qa.messages.findLast(message => message.type === 'room_drill_preview' && message.preview_id === request?.preview_id);
    return { preview: response?.data, previewId: response?.preview_id };
  }, before);
  assert(previewId, 'Preview must acknowledge the latest outgoing preview_id');
  assert.equal(preview?.ok, true, `Actual preview failed: ${JSON.stringify(preview)}`);
  await waitDom(() => !document.querySelector('#drill-commit').disabled);
  assert.equal((await latest()).time, 0);
  assert((await latest()).units.every(unit => unit.commands.length === 0), 'Preview must not add commands');
  assert(!JSON.stringify(preview).includes('unseen'), 'Preview must contain no hidden hostile information');
  report.previews.push(preview);
  return preview;
}
async function openDrill() {
  const door = (await latest()).doors.find(door => door.id === 'entry');
  assert(door && door.observed !== false, 'Entry door must be observed before opening its context');
  const point = await mapPoint(door.x, door.z, 0.7);
  await page.mouse.click(point.x, point.y, { button: 'right' });
  await page.locator('#context-popover').waitFor({ state: 'visible' });
  const index = await page.evaluate(() => {
    const menu = window.roomDrillQA.messages.filter(message => message.type === 'context').at(-1);
    if (menu?.target !== 'door' || menu.id !== 'entry') throw new Error('Expected actual entry-door context');
    return menu.actions.findIndex(action => (typeof action === 'string' ? action : action.type) === 'ENTER_ROOM');
  });
  assert(index >= 0, 'Observed door context must include ENTER_ROOM');
  const preview = await previewAfter(() => page.locator(`#context-popover [data-context-index="${index}"]`).click());
  await page.locator('#room-drill-panel').waitFor({ state: 'visible' });
  return preview;
}
async function chooseMethod(method) {
  const preview = await previewAfter(() => page.locator(`[data-drill-method="${method}"]`).click());
  assert.equal(preview.method, method);
  assert.equal(await page.locator(`[data-drill-method="${method}"]`).getAttribute('aria-pressed'), 'true');
  return preview;
}
async function waitGroupDelay(syncId, ticks) {
  await waitDom(({ syncId, ticks }) => {
    const matching = window.roomDrillQA.state?.units.flatMap(unit => unit.commands)
      .filter(command => command.type === 'WAIT_FOR_SIGNAL' && command.args.sync_id === syncId);
    return matching?.length === 4 && matching.every(command => command.args.delay_ticks === ticks);
  }, { syncId, ticks });
  assert.equal(await page.locator(`[data-sync-delay="${syncId}"]`).getAttribute('aria-valuenow'), String(ticks));
  report.delays.push(ticks);
}
function insideZone(point, zone) {
  return Math.abs(point[0] - zone[0]) <= zone[2] / 2 && Math.abs(point[1] - zone[1]) <= zone[3] / 2;
}
function assertObserved(state) {
  assert.equal(state.enemies.some(enemy => enemy.id === 'unseen'), false, 'Unseen hostile must stay absent from observed state');
}
async function importPlanFile(path, expected) {
  const before = await page.evaluate(() => window.roomDrillQA.sent.length);
  await page.locator('#deck-more').click();
  await page.locator('#import-plan').click();
  await page.locator('#file-import').setInputFiles(path);
  await loadingActionAck('load_plan', before, 'PLANNING');
  await waitNative(expected => {
    const state = window.roomDrillQA.state;
    // The actual JSON file roundtrip preserves every value, but the native
    // canonical args and exported JSON can insert dictionary keys in different
    // orders. The original direct-string wait timed out with all four complete
    // command arrays already assert.deepEqual; sort object keys recursively
    // without dropping fields or changing the ordered command/target arrays.
    const ordered = value => Array.isArray(value) ? value.map(ordered)
      : value && typeof value === 'object' ? Object.fromEntries(Object.keys(value).sort().map(key => [key, ordered(value[key])])) : value;
    return state?.mode === 'PLANNING' && state.time === 0 && state.mission === expected.map_id
      && expected.units.every(unit => JSON.stringify(ordered(state.units.find(candidate => candidate.id === unit.id)?.commands.map(command => ({ type: command.type, args: command.args })))) === JSON.stringify(ordered(unit.commands)));
  }, expected);
  await hudReady();
  await assertPlanCommands(expected);
}

try {
  await page.goto(url.href, { waitUntil: 'domcontentloaded' });
  await waitTitle();
  // Use the same legitimate local completion records as the existing P1
  // imported-mission test to unlock its ordinary shotgun equipment.
  await page.evaluate(async () => {
    const { BreachStorage } = await import('./storage.js'), storage = new BreachStorage();
    await storage.open();
    try {
      for (const id of ['M01', 'M02', 'M03', 'M04']) await storage.put('progress', {
        id, kind: 'mission', completed: true, stars: { complete: true, no_hits: true },
      });
    } finally { storage.database.close(); }
  });
  await page.reload({ waitUntil: 'domcontentloaded' });
  await waitTitle();
  await page.evaluate(() => {
    const bridge = window.BreachBridge, send = bridge.send;
    bridge.send = function(raw) { window.roomDrillQA.sent.push(JSON.parse(raw)); return send.call(this, raw); };
  });
  await loadFixture();
  pass('Official schema 3 fixture loads at fixed seed 42 with an observed entry door and an unseen adjacent-room hostile');

  for (const size of [2, 3, 4]) {
    await selectGroup(ids.slice(0, size));
    assert.deepEqual((await latest()).selected_units, ids.slice(0, size));
    assert.equal(await page.locator('#drill-timeline [data-drill-row]').count(), size);
    pass(`Actual Shift card clicks select ${size} operators and expose exactly ${size} timeline rows`);
  }
  await page.locator('.unit-card[data-unit="bravo"]').click({ modifiers: ['Shift'] });
  await waitDom(() => JSON.stringify(window.roomDrillQA.state?.selected_units) === JSON.stringify(['alpha', 'charlie', 'delta']));
  await page.locator('.unit-card[data-unit="bravo"]').click();
  await waitDom(() => JSON.stringify(window.roomDrillQA.state?.selected_units) === JSON.stringify(['bravo']));
  await selectGroup(ids); await hudReady();
  pass('Shift toggles one member while an ordinary card click returns to single selection');

  let preview = await openDrill();
  assert.equal(preview.method, 'OPEN_DOOR'); assert.equal(preview.short_room, false);
  assert.equal(preview.room_id, 'target_room'); assert.deepEqual(preview.order_ids, ids);
  assert.deepEqual(preview.slots.map(slot => slot.index), [1, 2, 3, 4]);
  assert(preview.slots.every(slot => slot.entry));
  const [fx, fz, fw, fd] = preview.funnel;
  for (const slot of preview.slots) {
    assert.equal(slot.stack[0] >= fx && slot.stack[0] <= fx + fw && slot.stack[1] >= fz && slot.stack[1] <= fz + fd, false);
    assert(Number.isFinite(slot.sector_entry.start) && Number.isFinite(slot.sector_entry.end));
    assert(Number.isFinite(slot.sector_domination.start) && Number.isFinite(slot.sector_domination.end));
    const angularWidth = sector => ((sector.end - sector.start) % (Math.PI * 2) + Math.PI * 2) % (Math.PI * 2);
    assert(angularWidth(slot.sector_domination) > angularWidth(slot.sector_entry));
  }
  assert.equal(await page.locator('#drill-preview-summary .drill-number').count(), 4);
  assert.equal(await page.locator('#drill-short').isVisible(), false);
  await page.screenshot({ path: `${out}/standard-preview-ko.png` });
  pass('Real door context opens a pure four-person preview with outside-funnel stacks and wider arrival sectors');

  for (const viewport of [{ width: 1280, height: 720 }, { width: 900, height: 600 }]) {
    await page.setViewportSize(viewport); await hudReady();
    await auditDrillGeometry(`${viewport.width}×${viewport.height} preview`);
    await page.screenshot({ path: `${out}/preview-${viewport.width}x${viewport.height}.png` });
  }
  await page.setViewportSize({ width: 1440, height: 900 }); await hudReady();

  for (const method of ['KICK_DOOR', 'OPEN_AND_FLASH', 'BREACH_DOOR', 'SHOTGUN_BREACH']) {
    preview = await chooseMethod(method);
    if (method === 'BREACH_DOOR') for (const slot of preview.slots) {
      assert(Math.hypot(slot.safe_retreat[0] - 7, slot.safe_retreat[1] - 6) >= 2.15 - 0.0001);
      assert(slot.safe_route.length > 0);
    }
    if (method === 'SHOTGUN_BREACH') {
      assert.equal(preview.operator_id, 'alpha');
      assert.deepEqual(preview.order_ids, ['bravo', 'charlie', 'delta', 'alpha']);
      assert.equal(preview.slots.at(-1).unit_id, 'alpha');
      assert.equal(preview.slots.at(-1).index, 4);
    }
    pass(`Actual ${method} control calculates its method-specific preview without queuing commands`);
  }
  await chooseMethod('OPEN_DOOR');
  for (let index = 0; index < 3; index++) {
    preview = await previewAfter(() => page.locator('[data-drill-order="alpha"][data-direction="-1"]').click());
  }
  assert.deepEqual(preview.order_ids, ids);
  preview = await previewAfter(() => page.locator('[data-drill-order="alpha"][data-direction="1"]').click());
  assert.deepEqual(preview.order_ids, ['bravo', 'alpha', 'charlie', 'delta']);
  preview = await previewAfter(() => page.locator('[data-drill-order="alpha"][data-direction="-1"]').click());
  assert.deepEqual(preview.order_ids, ids);
  pass('Order controls edit the real tactical order and restore the original four-person order');

  preview = await previewAfter(() => page.locator('[data-drill-signal="B"]').click());
  assert.equal(preview.signal, 'B');
  preview = await previewAfter(() => page.locator('#drill-go-long').click());
  assert.equal(preview.go_long.length, 2);
  assert.deepEqual(preview.go_long.map(goal => goal.unit_id), ['alpha', 'bravo']);
  for (const target of fixture().interactive_targets) assert(preview.go_long.some(goal => insideZone(goal.target, [target.x, target.z, target.w, target.d])), 'Both actual GO_LONG points must satisfy the fixed fixture objectives');
  pass('Manual B and GO_LONG controls produce two actual deep goals behind the domination barrier');

  for (const language of ['en', 'ko']) {
    await setLanguage(language);
    const copy = await page.evaluate(async () => {
      const { t } = await import('./i18n.js');
      return { title: t('drill.title'), apply: t('drill.apply'), doctrine: t('drill.doctrine') };
    });
    assert.equal(await page.locator('#drill-title').textContent(), copy.title);
    assert.equal(await page.locator('#drill-commit').textContent(), copy.apply);
    assert.equal(await page.locator('.drill-doctrine-note').textContent(), copy.doctrine);
    assert(copy.doctrine.includes('2') && !/\b(?:19|20)\d{2}\b/.test(copy.doctrine));
    assert.equal(/[가-힣]/.test(await page.locator('#room-drill-panel').innerText()), language === 'ko');
    await page.screenshot({ path: `${out}/standard-preview-${language}.png` });
    pass(`The actual ${language} drill editor translates every new visible control and the operation team leader guidance`);
  }

  await page.locator('#drill-commit').click();
  await page.locator('#room-drill-panel').waitFor({ state: 'hidden' });
  await waitDom(() => window.roomDrillQA.state?.units.every(unit => unit.commands.length > 0 && unit.commands.every(command => command.args.drill)));
  let state = await latest();
  assert.equal(state.mode, 'PLANNING'); assert.equal(state.time, 0); assertObserved(state);
  const commands = state.units.flatMap(unit => unit.commands), base = commands[0].args.drill.sync_id;
  const readyId = `${base}:ready`;
  assert(commands.every(command => primitiveTypes.has(command.type)), 'Macros must contain only existing primitive commands');
  assert.equal(commands.filter(command => command.type === 'OPEN_DOOR').length, 1);
  assert.equal(state.units.find(unit => unit.id === 'alpha').commands.find(command => command.type === 'OPEN_DOOR').args.door_id, 'entry');
  for (const [index, unit] of state.units.entries()) {
    const ready = unit.commands.find(command => command.args.drill.stage === 'ready');
    assert.equal(ready.type, 'WAIT_FOR_SIGNAL'); assert.equal(ready.args.signal, 'B');
    assert.equal(ready.args.sync_id, readyId); assert.equal(ready.args.auto_signal, false);
    assert.equal(ready.args.delay_ticks, 0);
    assert(unit.commands.every(command => command.args.drill.order === index + 1));
    const entry = unit.commands.find(command => command.type === 'WAIT_FOR_SIGNAL' && command.args.sync_id === `${base}:entry`);
    assert.equal(entry.args.auto_signal, true);
    assert(unit.commands.some(command => command.args.drill.stage === 'go_long'));
  }
  assert.equal(await page.locator('#drill-timeline [data-drill-row]').count(), 4);
  for (const id of ids) for (const stage of ['stack', 'ready', 'entry']) {
    assert(await page.locator(`#drill-timeline [data-drill-row="${id}"] [data-drill-stage="${stage}"] [data-select-command]`).count() > 0);
  }
  await hudReady();
  pass('Commit expands only existing primitives with separate manual-ready and automatic-door barriers in four editable timeline rows');

  let slider = page.locator(`[data-sync-delay="${readyId}"]`);
  await slider.focus(); await slider.press('ArrowRight'); await waitGroupDelay(readyId, 30);
  await slider.press('ArrowLeft'); await waitGroupDelay(readyId, 0);
  await slider.press('End'); await waitGroupDelay(readyId, 3600);
  await slider.press('Home'); await waitGroupDelay(readyId, 0);
  pass('Ready slider keyboard edits atomically update all four waits, including 0 and 3600 tick boundaries');

  for (const cancellation of ['Escape', 'lostpointercapture']) {
    const before = await page.evaluate(() => ({ sent: window.roomDrillQA.sent.length,
      pause: document.querySelector('#pause-panel').hidden, editor: document.querySelector('#room-drill-panel').hidden,
      modal: document.querySelector('#modal').open }));
    const cancelBox = await slider.boundingBox();
    assert(cancelBox && cancelBox.width > 20);
    const pixels = Math.max(1, Math.round(cancelBox.width / 24));
    await page.evaluate(() => {
      document.addEventListener('pointerdown', event => { window.roomDrillQA.dragPointer = event.pointerId; }, { once: true });
    });
    await page.mouse.move(cancelBox.x + cancelBox.width / 2, cancelBox.y + cancelBox.height / 2);
    await page.mouse.down();
    await page.mouse.move(cancelBox.x + cancelBox.width / 2 + pixels, cancelBox.y + cancelBox.height / 2, { steps: 5 });
    await waitDom(readyId => Number(document.querySelector(`[data-sync-delay="${readyId}"]`).getAttribute('aria-valuenow')) > 0, readyId);
    if (cancellation === 'Escape') {
      await page.keyboard.press('Escape');
    } else {
      // Release the actual native pointer capture. Its next real pointer
      // event must run lostpointercapture, never a direct app handler call.
      await page.evaluate(readyId => {
        const handle = document.querySelector(`[data-sync-delay="${readyId}"]`), pointer = window.roomDrillQA.dragPointer;
        if (!handle.hasPointerCapture(pointer)) throw new Error('Expected actual pointer capture before cancellation');
        handle.releasePointerCapture(pointer);
      }, readyId);
      await page.mouse.move(cancelBox.x + cancelBox.width / 2 + pixels + 1, cancelBox.y + cancelBox.height / 2);
    }
    await waitDom(readyId => document.querySelector(`[data-sync-delay="${readyId}"]`).getAttribute('aria-valuenow') === '0', readyId);
    await page.mouse.up();
    const token = `room-drill-cancel-${cancellation}`;
    await send({ action: 'pause', _quality_token: token });
    await waitNative(token => window.roomDrillQA.states.some(state => state.mode === 'PLANNING' && state.quality?.ack_tokens?.includes(token)), token);
    await waitGroupDelay(readyId, 0);
    const after = await page.evaluate(before => ({ commits: window.roomDrillQA.sent.slice(before).filter(message => message.action === 'sync_delay'),
      pause: document.querySelector('#pause-panel').hidden, editor: document.querySelector('#room-drill-panel').hidden,
      modal: document.querySelector('#modal').open }), before.sent);
    assert.deepEqual(after.commits, [], `${cancellation} must send no sync-delay intent on the later pointer release`);
    assert.equal(after.pause, before.pause); assert.equal(after.editor, before.editor); assert.equal(after.modal, before.modal);
    pass(`Actual ${cancellation} cancels the temporary slider drag, restores all four authoritative waits and leaves overlays unchanged`);
  }

  const box = await slider.boundingBox();
  assert(box && box.width > 20);
  const dragPixels = Math.max(1, Math.round(box.width / 24)), dragTicks = Math.round(dragPixels * 3600 / box.width);
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.down();
  await page.mouse.move(box.x + box.width / 2 + dragPixels, box.y + box.height / 2, { steps: 5 });
  await page.mouse.up();
  await waitDom(({ readyId, dragTicks }) => window.roomDrillQA.sent.some(message => message.action === 'sync_delay' && message.sync_id === readyId && message.delay_ticks === dragTicks), { readyId, dragTicks });
  await waitGroupDelay(readyId, dragTicks);
  const delayEdits = await page.evaluate(readyId => window.roomDrillQA.sent.filter(message => message.action === 'sync_delay' && message.sync_id === readyId), readyId);
  assert.equal(delayEdits.at(-1).delay_ticks, dragTicks);
  pass(`Actual pointer capture and release drag shifts the whole ready cohort by exactly ${dragTicks} fixed-step ticks`);

  state = await latest();
  const alpha = state.units.find(unit => unit.id === 'alpha');
  const goal = preview.slots.find(slot => slot.unit_id === 'alpha').domination;
  const moveIndex = alpha.commands.findIndex(command => command.type === 'MOVE' && command.args.target.every((value, index) => Math.abs(value - goal[index]) < 0.001));
  assert(moveIndex >= 0);
  const argsBefore = alpha.commands[moveIndex].args;
  await page.locator(`#drill-timeline [data-command-unit="alpha"][data-select-command="${moveIndex}"]`).click();
  await waitDom(index => window.roomDrillQA.state?.selected === 'alpha' && window.roomDrillQA.state.selected_command === index, moveIndex);
  assert.deepEqual((await latest()).selected_units, ids, 'Primitive selection must retain the cohort');
  const from = await mapPoint(goal[0], goal[1]), target = [goal[0] + 0.35, goal[1]], to = await mapPoint(...target);
  await page.screenshot({ path: `${out}/goal-before-edit.png` });
  await page.mouse.move(from.x, from.y); await page.mouse.down();
  await page.mouse.move(to.x, to.y, { steps: 8 }); await page.mouse.up();
  await waitDom(({ moveIndex, target }) => {
    const command = window.roomDrillQA.state?.units.find(unit => unit.id === 'alpha')?.commands[moveIndex];
    return command?.type === 'MOVE' && command.args.target.every((value, index) => Math.abs(value - target[index]) < 0.12);
  }, { moveIndex, target });
  const edited = (await latest()).units.find(unit => unit.id === 'alpha').commands[moveIndex];
  assert.deepEqual(edited.args.drill, argsBefore.drill); assert.deepEqual(edited.args.sector, argsBefore.sector);
  assert.notDeepEqual(edited.args.target, argsBefore.target);
  await hudReady(); await page.screenshot({ path: `${out}/goal-after-edit.png` });
  pass('Timeline selects the actual primitive and ordinary map dragging changes its domination goal while retaining drill and sector metadata');

  const plan = await planFromButton();
  assert.equal(plan.kind, 'breach-plan'); assert.equal(plan.schema_version, 1); assert.equal(plan.seed, 42);
  assert.equal(plan.map_id, 'ROOM_DRILL_UI');
  assert(plan.units.flatMap(unit => unit.commands).every(command => primitiveTypes.has(command.type) && command.args.drill));
  const beforeSavedLoad = await page.evaluate(() => window.roomDrillQA.sent.length);
  await page.locator('#deck-more').click();
  await page.locator('#modal-load-plan').click();
  await loadingActionAck('load_plan', beforeSavedLoad, 'PLANNING');
  await waitNative(() => window.roomDrillQA.state?.mode === 'PLANNING' && window.roomDrillQA.state.time === 0 && window.roomDrillQA.state.units.every(unit => unit.commands.length && unit.commands.every(command => command.state === 'PENDING')));
  await hudReady(); await assertPlanCommands(plan);
  pass('Visible IndexedDB save and load restore the edited primitive plan without changing schema 1');

  await page.locator('#deck-more').click();
  const [planDownload] = await Promise.all([page.waitForEvent('download'), page.locator('#export-plan').click()]);
  const planPath = `${out}/room-drill.plan.json`; await planDownload.saveAs(planPath);
  const exportedPlan = JSON.parse(await readFile(planPath, 'utf8'));
  assert.deepEqual(exportedPlan, plan);
  await page.locator('#modal-close').click();
  await importPlanFile(planPath, exportedPlan);
  assert.deepEqual(await planFromButton(), exportedPlan);
  pass('The actual downloaded JSON imports through the file UI and exports the identical edited macro plan');

  await selectGroup(ids); await hudReady();
  const beforeRun = await latest(), commandIds = beforeRun.units.flatMap(unit => unit.commands).map(command => command.id);
  await page.evaluate(() => { window.roomDrillQA.events = []; window.roomDrillQA.eventKeys.clear(); });
  await page.locator('#toggle-execution').click();
  await waitNative(readyId => {
    const state = window.roomDrillQA.state;
    return state?.mode === 'EXECUTING' && state.units.every(unit => unit.commands.some(command => command.type === 'WAIT_FOR_SIGNAL' && command.args.sync_id === readyId && command.state === 'WAITING'));
  }, readyId);
  state = await latest(); assertObserved(state);
  assert.equal(state.doors.find(door => door.id === 'entry').state, 'CLOSED');
  assert.equal(state.units.flatMap(unit => unit.commands).filter(command => command.args.drill.stage === 'door').every(command => command.state === 'PENDING'), true);
  await page.locator('#hud [data-signal="B"]').click();
  await waitNative(() => window.roomDrillQA.state?.mode === 'RESULT');
  const final = await latest();
  assert.equal(final.result.success, true); assert.equal(final.command_failures, 0);
  assert.deepEqual(final.units.flatMap(unit => unit.commands).map(command => command.id), commandIds);
  assert(final.units.every(unit => unit.commands.filter(command => command.type === 'MOVE').every(command => command.state === 'SUCCEEDED')));
  // The authoritative state retains only its latest 40 events. Validate all
  // actual state events received during this run so later MOVE/FACE events
  // cannot evict an earlier successful manual-ready release from the check.
  const runEvents = await page.evaluate(() => window.roomDrillQA.events);
  assert(runEvents.some(event => event.type === 'SIGNAL' && event.sync_id === readyId));
  assert(runEvents.some(event => event.type === 'SIGNAL' && event.sync_id === `${base}:entry` && event.auto_signal));
  assert(runEvents.some(event => event.type === 'SIGNAL' && event.sync_id === `${base}:go_long` && event.auto_signal));
  report.runEvents = runEvents;
  const live = await page.evaluate(() => window.roomDrillQA.states.filter(state => ['PLANNING', 'EXECUTING'].includes(state.mode)));
  for (const frame of live) assertObserved(frame);
  report.final = { tick: final.tick, time: final.time, result: final.result, units: final.units.map(unit => ({ id: unit.id, x: unit.x, z: unit.z })) };
  pass('The saved edited drill actually waits for manual B, clears its door barrier, reaches all goals and finishes GO_LONG without leaking the hidden hostile during live play');

  await page.locator('#watch-replay').click();
  await waitNative(() => window.roomDrillQA.state?.mode === 'REPLAY');
  await send({ action: 'pause' });
  await waitNative(() => window.roomDrillQA.state?.mode === 'REPLAY' && !window.roomDrillQA.state.replay.playing);
  await page.locator('#replay-view-group [data-reveal="false"]').click();
  // Actual first playback can pause at 1/60s while the legacy HTML range with
  // step=0.05 already displays 0. Home then changes nothing and emits no seek.
  // Use the visible restart control for exact zero, and preserve the keyboard
  // Home check by first proving End moved the authoritative playhead away.
  const beforeRestart = await page.evaluate(() => window.roomDrillQA.sent.length);
  await page.locator('#replay-restart').click();
  await waitNative(before => window.roomDrillQA.state?.mode === 'REPLAY' && window.roomDrillQA.state.replay.time === 0
    && window.roomDrillQA.sent.slice(before).some(message => message.action === 'replay_seek' && message.time === 0), beforeRestart);
  let zero = await latest(); assertObserved(zero); assert.equal(zero.tick, 0);
  assert(zero.units.every(unit => unit.commands.every(command => command.state === 'PENDING')));
  const beforeEnd = await page.evaluate(() => window.roomDrillQA.sent.length);
  await page.locator('#replay-seek').focus(); await page.locator('#replay-seek').press('End');
  await waitNative(before => window.roomDrillQA.state?.mode === 'REPLAY' && window.roomDrillQA.state.replay.time > 0
    && window.roomDrillQA.sent.slice(before).some(message => message.action === 'replay_seek' && message.time > 0), beforeEnd);
  const beforeHome = await page.evaluate(() => window.roomDrillQA.sent.length);
  await page.locator('#replay-seek').press('Home');
  await waitNative(before => window.roomDrillQA.state?.mode === 'REPLAY' && window.roomDrillQA.state.replay.time === 0
    && window.roomDrillQA.sent.slice(before).some(message => message.action === 'replay_seek' && message.time === 0), beforeHome);
  state = await latest(); assertObserved(state); assert.equal(state.replay.reveal, false); assert.equal(state.tick, 0);
  assert(state.units.every(unit => unit.commands.every(command => command.state === 'PENDING')));
  pass('The actual restart control seeks exact observed tick zero, and keyboard End then Home each produces its own authoritative seek');
  const [replayDownload] = await Promise.all([page.waitForEvent('download'), page.locator('#export-replay').click()]);
  const replayPath = `${out}/room-drill.replay.json`; await replayDownload.saveAs(replayPath);
  const exportedReplay = JSON.parse(await readFile(replayPath, 'utf8'));
  assert.equal(exportedReplay.schema_version, 1); assert.equal(exportedReplay.encoding, 'numeric-state-v1');
  assert.equal(exportedReplay.map_id, 'ROOM_DRILL_UI'); assert.equal(exportedReplay.seed, 42);
  assert.equal(exportedReplay.complete, true); assert.equal(exportedReplay.duration, final.time);
  assert(JSON.stringify(exportedReplay.commands).includes(readyId), 'Recorded commands must retain the real ready group');
  pass('Actual observed replay at tick zero restores pending macro commands and exports the legacy numeric-state-v1 format');

  const beforeReplayLoad = await page.evaluate(() => window.roomDrillQA.sent.length);
  await page.locator('#replay-library').click();
  await page.locator('#import-replay').click();
  await page.locator('#file-import').setInputFiles(replayPath);
  await loadingActionAck('import_replay', beforeReplayLoad, 'REPLAY');
  await waitNative(() => window.roomDrillQA.state?.mode === 'REPLAY' && window.roomDrillQA.state.replay.duration > 0);
  await send({ action: 'pause' });
  await waitNative(() => !window.roomDrillQA.state?.replay.playing && window.roomDrillQA.state?.mode === 'REPLAY');
  await page.locator('#replay-view-group [data-reveal="false"]').click();
  // The public replay_seek action accepts an exact recorded time. Unlike an
  // HTML range with 0.05s steps, it can request every 1/30s simulation tick.
  await send({ action: 'replay_seek', time: exportedReplay.duration });
  await waitNative(({ tick, time }) => window.roomDrillQA.state?.mode === 'REPLAY'
    && window.roomDrillQA.state.tick === tick && Math.abs(window.roomDrillQA.state.replay.time - time) < 0.00000001, { tick: final.tick, time: final.time });
  state = await latest(); assertObserved(state); assert.equal(state.replay.reveal, false);
  for (const expected of final.units) {
    const actual = state.units.find(unit => unit.id === expected.id);
    assert.equal(actual.x, expected.x); assert.equal(actual.z, expected.z);
    assert.deepEqual(actual.commands, expected.commands);
  }
  assert.deepEqual(state.result, final.result);
  await page.screenshot({ path: `${out}/restored-observed-replay.png` });
  pass('Downloaded replay imports through the visible file UI and exact final-tick observed seek reproduces every position, command and result');

  await loadFixture(true); await selectGroup(ids); await hudReady();
  preview = await openDrill();
  assert.equal(preview.short_room, true); assert.equal(preview.entry_count, 2);
  assert.deepEqual(preview.slots.map(slot => slot.entry), [true, true, false, false]);
  assert.equal(await page.locator('#drill-short').isVisible(), true);
  assert(preview.slots.slice(2).every(slot => slot.domination[0] < 7 && JSON.stringify(slot.stack) === JSON.stringify(slot.domination)));
  await page.screenshot({ path: `${out}/short-room-ko.png` });
  await setLanguage('en');
  assert.equal(/[가-힣]/.test(await page.locator('#room-drill-panel').innerText()), false);
  assert.equal(await page.locator('#drill-short').isVisible(), true);
  await page.screenshot({ path: `${out}/short-room-en.png` });
  await page.locator('#drill-commit').click();
  await waitDom(() => window.roomDrillQA.state?.units.every(unit => unit.commands.length > 0));
  state = await latest(); assertObserved(state);
  for (const id of ['charlie', 'delta']) {
    const guard = state.units.find(unit => unit.id === id);
    const slot = preview.slots.find(slot => slot.unit_id === id), moves = guard.commands.filter(command => command.type === 'MOVE');
    // Native exact-fixture preflight proved charlie needs one stack MOVE while
    // delta needs five, including four obstacle/teammate detour checkpoints.
    // The earlier count=1 assumption missed those required stack primitives.
    // Match every calculated route point exactly and reject all interior moves.
    assert.equal(moves.length, slot.stack_route.length);
    assert.deepEqual(moves.map(command => command.args.target), slot.stack_route);
    assert(moves.every(command => command.args.drill.stage === 'stack' && command.args.target[0] < 7));
    assert.deepEqual(moves.at(-1).args.target, slot.stack);
    assert.deepEqual(slot.domination, slot.stack);
    const face = guard.commands.find(command => command.type === 'FACE' && command.args.drill.stage === 'guard');
    assert(face); assert.deepEqual(face.args.target, slot.face_target);
    assert.equal(moves.filter(command => ['entry', 'domination', 'go_long'].includes(command.args.drill.stage)).length, 0);
    assert(guard.commands.every(command => command.args.drill.stage !== 'domination'));
  }
  assert.equal(await page.locator('#drill-timeline [data-drill-row]').count(), 4);
  pass('Actual SHORT ROOM preview in both languages keeps operators 3 and 4 outside and expands only their stack and guard primitives');

  await setLanguage('ko');
  assert.deepEqual(errors, []); assert.deepEqual(failedRequests, []);
  report.status = 'PASS';
} catch (error) {
  report.status = 'FAIL'; report.error = error.stack;
  report.lastState = await latest().catch(() => null);
  report.dom = await page.evaluate(() => {
    const seek = document.querySelector('#replay-seek'), active = document.activeElement;
    return { ready: document.readyState, active: { id: active?.id, tag: active?.tagName },
      loadingHidden: document.querySelector('#loading')?.hidden, transitionOpen: document.querySelector('#transition-loading')?.open,
      modalOpen: document.querySelector('#modal')?.open, pauseHidden: document.querySelector('#pause-panel')?.hidden,
      editorHidden: document.querySelector('#room-drill-panel')?.hidden,
      replaySeek: seek ? { value: seek.value, min: seek.min, max: seek.max, step: seek.step, disabled: seek.disabled } : null };
  }).catch(() => null);
  report.messages = await page.evaluate(() => window.roomDrillQA.messages.filter(message => !['ready', 'catalog_update'].includes(message.type))).catch(() => []);
  report.sent = await page.evaluate(() => window.roomDrillQA.sent).catch(() => []);
  await page.screenshot({ path: `${out}/failure.png` }).catch(() => {});
  console.error(error); process.exitCode = 1;
} finally {
  await writeFile(`${out}/report.json`, JSON.stringify(report, null, 2));
  await browser.close();
  console.log(`BREACH_ROOM_DRILL_BROWSER_RESULT checks=${report.checks.length} failures=${report.status === 'PASS' ? 0 : 1} status=${report.status}`);
}
