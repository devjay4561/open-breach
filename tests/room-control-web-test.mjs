import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

// Exercise actual web projections, settings import/export and rendering without
// Godot, a browser, timers or an alternate implementation of those contracts.
const app = await readFile(new URL('../web/app.js', import.meta.url), 'utf8');
const css = await readFile(new URL('../web/style.css', import.meta.url), 'utf8');
const source = await readFile(new URL('../web/i18n.js', import.meta.url), 'utf8');
const i18n = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
let checks = 0;
const plain = value => JSON.parse(JSON.stringify(value));
const equal = (actual, expected, message) => { assert.deepEqual(plain(actual), plain(expected), message); checks++; };
const check = (value, message) => { assert(value, message); checks++; };
function section(start, end) {
  const begin = app.indexOf(start), finish = app.indexOf(end, begin);
  assert(begin >= 0 && finish > begin, `Actual source section ${start} remains available`);
  return app.slice(begin, finish).replaceAll('export function', 'function');
}
const escapeHTML = value => String(value ?? '').replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));
const formatTime = value => { const time = Math.max(0, Number(value) || 0); return `${String(Math.floor(time / 60)).padStart(2, '0')}:${String(Math.floor(time % 60)).padStart(2, '0')}`; };
const projection = vm.runInNewContext(`${section('export function observedRoomStates', 'let lastUnitHP')}\nobservedRoomStates;`);
const rooms = ['visible', 'hidden', 'string', 'invalid', 'unknown', 'constructor'].map(id => ({ id }));
const snapshot = {
  room_states: {
    visible: { state: 'CLEAR', observed: true, enemies: ['secret'], search_elapsed: 1.5 },
    hidden: { state: 'MARKED', observed: false }, string: { state: 'CLEAR', observed: 'true' },
    invalid: { state: 'OTHER', observed: true }, unknown: { state: 'UNKNOWN', observed: true },
    constructor: { state: 'CONTACT', observed: true }, outsider: { state: 'MARKED', observed: true },
  },
  enemies: [{ id: 'secret', x: 14, z: 6 }],
};
const before = JSON.stringify(snapshot), projected = projection(snapshot, rooms);
equal(projected, {
  visible: { id: 'visible', state: 'CLEAR', observed: true },
  unknown: { id: 'unknown', state: 'UNKNOWN', observed: true },
  constructor: { id: 'constructor', state: 'CONTACT', observed: true },
}, 'Only authored, explicitly observed valid room states are public');
projected.visible.state = 'MARKED';
equal(JSON.stringify(snapshot), before, 'Presentation owns copies and cannot mutate the authoritative room state');
for (const value of [undefined, null, {}, [], { room_states: [] }, { room_states: { visible: null } }]) equal(projection(value, rooms), {}, 'Legacy or malformed room state does not infer observation');
equal(projection(snapshot, []), {}, 'Absent authored rooms reveals no room state');
const many = Array.from({ length: 65 }, (_, index) => ({ id: `room${index}` }));
equal(Object.keys(projection({ room_states: Object.fromEntries(many.map(room => [room.id, { state: 'MARKED', observed: true }])) }, many)).length, 64, 'Room presentation preserves the authored 64-room bound');

const timelineSource = section('export function roomDrillTimeline', '// Room presentation');
const timeline = vm.runInNewContext(`${timelineSource}\nroomDrillTimeline;`, { clampDrillDelay: value => value ?? 0 });
const base = 'entry-3-person';
const drill = (order, stage, state) => ({ type: stage === 'guard' ? 'FACE' : 'MOVE', state, args: { drill: { sync_id: base, door_id: 'entry', room_id: 'visible', order, stage } } });
const reform = {
  mode: 'PLANNING', units: [
    { id: 'alpha', hp: 0, commands: [drill(1, 'stack', 'SUCCEEDED'), drill(1, 'entry', 'CANCELLED')] },
    { id: 'bravo', hp: 100, commands: [drill(2, 'stack', 'SUCCEEDED'), drill(1, 'domination', 'PENDING'), drill(2, 'entry', 'CANCELLED')] },
    { id: 'charlie', hp: 100, commands: [drill(3, 'stack', 'SUCCEEDED'), drill(2, 'domination', 'RUNNING'), drill(3, 'entry', 'CANCELLED')] },
    { id: 'delta', hp: 100, commands: [drill(4, 'stack', 'SUCCEEDED'), drill(3, 'guard', 'WAITING'), drill(4, 'entry', 'CANCELLED')] },
  ],
};
const reformBefore = JSON.stringify(reform), reformed = timeline(reform)[0];
equal(reformed.rows.map(row => [row.unit.id, row.order]), [['bravo', 1], ['charlie', 2], ['delta', 3], ['alpha', null]], 'Current three-person ranks replace old completed stack ranks; the down operator has no current rank');
equal(reformed.rows.length, 4, 'The down operator history remains in the timeline');
equal(reformed.rows.find(row => row.unit.id === 'bravo').commands.map(item => item.index), [0, 1, 2], 'Reformation retains completed/cancelled command indices for review');
equal(JSON.stringify(reform), reformBefore, 'Rank presentation does not rewrite the authoritative plan');
for (const state of ['PENDING', 'RUNNING', 'WAITING', 'FAILED']) {
  const value = structuredClone(reform); value.units[1].commands[1].state = state;
  equal(timeline(value)[0].rows.find(row => row.unit.id === 'bravo').order, 1, `A ${state} current entry rank takes precedence over old history`);
}
equal(timeline({ units: [{ id: 'legacy', hp: 100, commands: [drill(2, 'stack', 'SUCCEEDED')] }] })[0].rows[0].order, 2, 'A completed legacy plan retains its original history rank');

const defaultSource = section('const DEFAULT_BINDINGS =', 'const BINDING_LABELS');
const settingsSource = app.match(/^const DEFAULT_SETTINGS = .*;$/m)?.[0];
assert(settingsSource, 'Actual settings defaults are available');
const sent = [], notices = [], writes = [], downloads = [];
const settingsContext = vm.createContext({
  matchMedia: () => ({ matches: false }), settings: {}, state: { mode: 'MENU' }, engineReady: true,
  document: { title: '', documentElement: { style: { setProperty() {} } }, body: { dataset: {}, classList: { toggle() {} } } },
  autoUiScale: () => 1, effectGain: null, musicGain: null, lastToolKey: '',
  setLanguage: i18n.setLanguage, t: i18n.t, getLanguage: i18n.getLanguage, applyStaticI18n() {},
  updateBrief() {}, scheduleSafeArea() {}, renderHotbarBindings() {}, renderState() {}, renderTool() {},
  send: message => sent.push(plain(message)), pendingImport: 'settings', currentModal: '',
  toast: (...args) => notices.push(args), downloadJSON: (data, name) => downloads.push({ data: plain(data), name }),
});
vm.runInContext(`${defaultSource}\n${settingsSource}\n${section('function validateBindings', '// RD1: hotbar key badges')}\n${section('async function readImport(', '// RD1: key-rebinding capture')}`, settingsContext);
settingsContext.persistSettings = async () => { writes.push(plain(settingsContext.settings)); };
const validate = value => settingsContext.validateSettings(value);
equal(validate({}).auto_pause_man_down, false, 'Legacy settings keep the optional pause disabled');
for (const value of [undefined, null, 'true', 'false', 0, 1, [], {}]) equal(validate({ auto_pause_man_down: value }).auto_pause_man_down, false, 'Only a boolean enables automatic pause');
for (const enabled of [false, true]) equal(validate({ auto_pause_man_down: enabled }).auto_pause_man_down, enabled, 'Both explicit boolean values are retained');
settingsContext.settings = validate({}); settingsContext.applySettings(); sent.length = 0;
for (const enabled of [true, false]) {
  settingsContext.settings.auto_pause_man_down = enabled; settingsContext.applySettings();
  equal(sent.at(-1).settings.auto_pause_man_down, enabled, 'Both toggle directions reach the native settings bridge');
}
equal(sent.length, 2, 'Each native pause preference change sends exactly one settings intent');
sent.length = 0; settingsContext.settings.volume = .43; settingsContext.applySettings();
equal(sent, [], 'Audio-only settings preserve the existing no-engine-roundtrip contract');
const exportSource = app.match(/case 'export-settings':([^\n]+)/)?.[1];
assert(exportSource, 'Actual settings export case is available');
for (const enabled of [true, false]) {
  settingsContext.settings = validate({ auto_pause_man_down: enabled, volume: .43, language: 'en' });
  vm.runInContext(exportSource.replace(/break;\s*$/, ''), settingsContext);
  const payload = downloads.at(-1).data;
  equal(payload.kind, 'breach-settings', 'Settings export retains the existing kind');
  equal(payload.schema_version, 1, 'Settings export retains schema version 1');
  equal(payload.settings.auto_pause_man_down, enabled, 'Settings export preserves the explicit optional boolean');
  settingsContext.settings = validate({ auto_pause_man_down: !enabled });
  await settingsContext.readImport({ size: 100, text: async () => JSON.stringify(payload) });
  equal(settingsContext.settings.auto_pause_man_down, enabled, 'Actual schema1 import restores the optional boolean');
  equal(writes.at(-1).auto_pause_man_down, enabled, 'Actual import persists its validated settings');
  equal(sent.at(-1).settings.auto_pause_man_down, enabled, 'Actual import applies the native preference');
}
await settingsContext.readImport({ size: 100, text: async () => JSON.stringify({ kind: 'breach-settings', schema_version: 1, settings: { volume: .25 } }) });
equal(settingsContext.settings.auto_pause_man_down, false, 'Old schema1 exports without the field still import with default false');

const stats = vm.runInNewContext(`${section('export function resultStatistics', 'function renderResult()')}\nresultStatistics;`, { t: i18n.t, formatTime });
const rules = vm.runInNewContext(`${section('function rulesDescription', 'async function persistCampaign')}\nrulesDescription;`, { t: i18n.t, getLanguage: i18n.getLanguage });
const toggle = vm.runInNewContext(`${section('function settingToggleCard', 'function settingSlider')}\nsettingToggleCard;`, { settings: { auto_pause_man_down: true }, t: i18n.t, escapeHTML });
const dictStart = source.indexOf('const DICTS ='), dictEnd = source.indexOf('let currentLang', dictStart);
const dictionaries = vm.runInNewContext(`${source.slice(dictStart, dictEnd)}; DICTS`);
const calls = ['CLEAR', 'ROOM_CLEAR', 'SHORT_ROOM', 'RELOADING', 'GUN_UP', 'MAN_DOWN'].map(call => `CALL_${call}`);
const reasons = [
  ['사상자 발생 후 진입 재편성', 'team.entry_reformed'],
  ['사상자 발생 후 진입 지점을 안전하게 재편성할 수 없습니다', 'team.entry_reform_blocked'],
  ['문 조작 대원이 행동 불능이 되어 진입을 안전하게 중단했습니다', 'team.entry_operator_lost'],
];
// P4 adds seven formation/signal diagnostics. Keep this P3 suite's original
// ten exact diagnoses and assertions; formation-web-test covers the new seven.
const replayKeys = ['room_states', 'result_room_states', 'room_transition_time', 'pause_reason', 'pause_unit', 'rooms_cleared_rule', 'call_unit_observed', 'call_cover_unit', 'call_room', 'call_type'].map(key => `replay.error.${key}`);
equal(replayKeys.length, 10, 'All ten new room/team replay diagnostics remain translated');
const replay = await readFile(new URL('../game/scripts/replay.gd', import.meta.url), 'utf8');
for (const key of replayKeys) check(replay.includes(`_fail("${dictionaries.ko[key]}")`), 'Replay diagnosis maps the actual native source string exactly');
const keys = ['settings.auto_pause_man_down', 'settings.auto_pause_man_down.note', 'settings.applied', 'stat.rear_hits', 'team.covering', 'team.covering_reload', 'team.man_down_paused', 'team.invalid_settings', 'room.goal_all', 'room.goal_selected', ...['UNKNOWN', 'CONTACT', 'DOMINATED', 'CLEAR', 'MARKED'].map(state => `room.state.${state}`), ...calls.map(call => `event.${call}`), ...reasons.map(([, key]) => key), ...replayKeys];
for (const language of ['ko', 'en']) {
  i18n.setLanguage(language);
  for (const key of keys) {
    check(Object.hasOwn(dictionaries[language], key), `${language} defines the paired P3 key ${key}`);
    const value = i18n.t(key, { name: 'ALPHA', count: 2 });
    check(value.length > 0 && value !== key, `${language} translates ${key}`);
    if (language === 'en') check(!/[가-힣]/.test(value), `English ${key} contains no raw Korean`);
  }
  const own = new Map([['alpha', 'ALPHA'], ['bravo', 'BRAVO']]);
  const publicRooms = projection(snapshot, rooms);
  const context = { ownUnitName: id => own.get(id) || '', observedRoomName: id => Object.hasOwn(publicRooms, id) ? 'VISIBLE ROOM' : '' };
  for (const type of calls) {
    const event = { type, observed: true, unit_id: 'alpha', room_id: 'visible', cover_unit_id: 'bravo', message: '이 원시 문구는 출력하지 않음', from: [1, 2] };
    const text = i18n.translateEvent(event, context);
    check(text.includes('ALPHA') && text.includes(i18n.t(`event.${type}`)) && text.includes('VISIBLE ROOM'), `${language} translates ${type} before the Korean raw-message path`);
    check(!text.includes(event.message) && !text.includes('1,2'), 'Raw messages and own-position payloads never become call text');
    if (type === 'CALL_RELOADING') check(text.includes('BRAVO') && text.includes(i18n.t('team.covering', { name: 'BRAVO' })), 'Reload call names its own covering operator');
    equal(i18n.translateEvent({ ...event, observed: false }, context), '', 'Unobserved calls produce no log text');
    const hidden = i18n.translateEvent({ ...event, unit_id: 'secret', room_id: 'hidden', cover_unit_id: 'secret-coverer' }, context);
    check(!/secret|hidden|VISIBLE ROOM/.test(hidden), 'Unknown actors, coverers and unobserved rooms are omitted');
    equal(i18n.translateEvent({ ...event, observed: undefined }, context), '', 'An absent observation flag does not infer a call');
    if (language === 'en') check(!/[가-힣]/.test(text), `English ${type} contains no raw Korean`);
  }
  equal(i18n.translateCommandReason('재장전하는 대원의 구역을 엄호 중'), i18n.t('team.covering_reload'), 'The new native covering status has an exact paired translation');
  for (const [reason, key] of reasons) {
    equal(i18n.translateCommandReason(reason), i18n.t(key), 'Each casualty reformation/safe-halt reason maps exactly');
    if (language === 'en') check(i18n.translateEvent({ type: 'COMMAND_FAILED', unit_id: 'alpha', reason, message: `ALPHA · ${reason}` }, { unitName: () => 'ALPHA' }).includes(i18n.t(key)), 'Native safe-halt COMMAND_FAILED uses the exact English reason');
  }
  const panel = { hidden: false, innerHTML: '' };
  const rendererContext = { state: reform, drillDelayDrag: null, drillTimelineGroup: '', lastDrillHTML: '', document: { activeElement: null }, $: () => panel, roomDrillTimeline: timeline, selectedOwnUnitIds: () => [], DRILL_STAGES: ['stack', 'ready', 'door', 'entry'], escapeHTML, rosterName: unit => unit.id.toUpperCase(), t: i18n.t, scheduleSafeArea() {}, timelineCommand: () => '' };
  vm.runInNewContext(`${section('function renderDrillTimeline()', 'function updateDrillDelayHandle')}\nrenderDrillTimeline();`, rendererContext);
  const downRow = panel.innerHTML.split('data-drill-row="alpha"')[1];
  check(downRow.includes('class="drill-unit-down" disabled') && downRow.includes('>×</b>'), 'Actual timeline renderer preserves the down row as unnumbered disabled history');
  check(downRow.includes(`<small>${i18n.t('stat.incapacitated')}</small>`), 'Actual down-row status is visible in both languages');
  const rows = stats({ time: 75, units: [{ hp: 100 }, { hp: 0 }], result: { rear_hits: 3, hits_taken: 7, score: 90 } });
  equal(rows.length, 14, 'The debrief adds exactly one required statistic');
  equal(rows.find(([label]) => label === i18n.t('stat.rear_hits'))?.[1], '3', 'Rear hits displays the authoritative result count');
  equal(rows.find(([label]) => label === i18n.t('stat.hits'))?.[1], '7', 'The existing total-hit statistic remains independent');
  equal(stats({ result: {} }).find(([label]) => label === i18n.t('stat.rear_hits'))?.[1], '0', 'Old result/replay data displays rear hits zero');
  equal(stats({ result: { unlawful_shots: 1 } }).length, 15, 'The optional existing statistic is retained in the largest detail grid');
  check(rules({ win: [{ type: 'rooms_cleared' }, { type: 'rooms_cleared', room_ids: ['visible', 'unknown'] }] }).every(text => !text.includes('rooms_cleared')), 'Both all-room and explicit-room victory rules are explained');
  const html = toggle('auto_pause_man_down', i18n.t('settings.auto_pause_man_down'), i18n.t('settings.auto_pause_man_down.note'));
  check(html.includes('aria-pressed="true"') && html.includes('data-applied="'), 'The optional pause uses the existing pressed button contract');
  check(html.includes(escapeHTML(i18n.t('settings.applied'))), 'Pressed status uses the active-language paired text');
  check(!/<(?:select|input)/.test(html), 'The new gameplay setting introduces no native select/checkbox');
}
check(css.includes('strong[data-applied]:after{content:attr(data-applied)}'), 'The visual pressed suffix reads its translated attribute');

// The same deterministic result can arrive again after retry or while a
// language setting changes. Repaint its text without rewarding that result
// again; exercise the actual renderers and persistence guards together.
const debriefSource = await readFile(new URL('../web/debrief.js', import.meta.url), 'utf8');
const debrief = await import(`data:text/javascript;base64,${Buffer.from(debriefSource).toString('base64')}`);
const metaSource = await readFile(new URL('../web/meta.js', import.meta.url), 'utf8');
const meta = await import(`data:text/javascript;base64,${Buffer.from(metaSource).toString('base64')}`);
const resultNodes = new Map(), resultWrites = [];
const resultNode = id => {
  if (!resultNodes.has(id)) resultNodes.set(id, {
    textContent: '', innerHTML: '', hidden: false, style: {}, offsetWidth: 1,
    classList: { toggle() {} }, querySelector: () => ({ classList: { toggle() {} } }),
  });
  return resultNodes.get(id);
};
let resultAnimations = 0, campaignFinishes = 0, campaignSaves = 0;
const resultState = {
  mode: 'RESULT', mission: 'M01', seed: 42, tick: 150, time: 5, variant: 'standard', can_retry_plan: true,
  units: [{ id: 'alpha', name: 'ALPHA', hp: 100, hits_taken: 1, commands: [{ state: 'SUCCEEDED' }] }],
  objectives: { neutralized: 1, total: 1 },
  result: { success: true, reason: '모든 목표 완료', score: 94, rear_hits: 3, hits_taken: 1 },
  stars: [{ id: 'no_hits', label: '피격 없음', stat: 'hits_taken', op: 'eq', value: 0 }],
};
const resultContext = vm.createContext({
  state: resultState, resultKey: '', resultLanguage: '', rewardedResultKey: '', campaignResultKey: '',
  $: resultNode, t: i18n.t, getLanguage: i18n.getLanguage, localize: i18n.localize, escapeHTML, formatTime,
  conditionKey: () => 'same-run', progress: new Map(), missionProgress: new Map(), parTimes: { M01: 240 },
  summarizeRun: debrief.summarizeRun, mergeStars: meta.mergeStars, STAR_LABELS_EN: { no_hits: 'No hits' },
  ROSTER: [], unitHitCount: new Map(), requestAnimationFrame: callback => callback(),
  animateCountUp(element, value) { resultAnimations++; element.textContent = String(value); },
  renderResultReplayPreview() {}, storeAvailable: true, progressSaveFailed: false,
  store: { put: (table, record) => { resultWrites.push({ table, record: plain(record) }); return Promise.resolve(); } },
  unlockProfile: { stars: 5 }, resultRewards: null,
  refreshProgression() { resultContext.unlockProfile = { stars: 8 }; },
  progressionDiff: () => ({ stars: 3, unlocks: [{ label: '산탄총', label_en: 'Shotgun' }] }),
  campaign: { active: true, suspended: false, mission: 'M01' }, preparedForBase: 'M01',
  missionBase: id => id, finishCampaign: campaign => { campaignFinishes++; return { ...campaign, active: false }; },
  persistCampaign: () => { campaignSaves++; return Promise.resolve(); }, campaignRestoreProblem: () => '',
  isProgressionMission: () => true, nextStarReward: () => null, rewardName: item => i18n.localize(item, 'label'),
  nextMission: () => null, missions: {},
});
vm.runInContext(`${section('export function resultStatistics', '// RC: score counts up')}\n${section('function renderResultOperators', '// RC: replay preview')}\n${section('function renderResultProgression()', 'function renderMissionGrid()')}`, resultContext);
const resultIdentity = `${resultState.mission}:${resultState.seed}:${resultState.tick}:${JSON.stringify(resultState.result)}`;
for (const language of ['ko', 'en', 'ko']) {
  i18n.setLanguage(language); resultContext.renderResult();
  equal(resultNode('result-title').textContent, i18n.t('result.complete'), 'Identical RESULT titles follow each active language');
  check(resultNode('result-stats').innerHTML.includes(`<dt>${i18n.t('stat.rear_hits')}</dt><dd>3</dd>`), 'Identical RESULT repaint keeps the authoritative rear-hit count in the active language');
  check(resultNode('result-operators').innerHTML.includes(i18n.t('stat.op_commands')), 'Identical RESULT operator chips follow the active language');
  check(resultNode('result-progression').innerHTML.includes(i18n.t('progress.earned', { earned: 3, total: 8 })), 'Identical RESULT reward text follows the active language');
  if (language === 'en') {
    equal(resultNode('result-message').textContent, i18n.t('result.default_success'), 'English repaint replaces the free-form native Korean success reason');
    check(!/[가-힣]/.test([...resultNodes.values()].map(node => node.textContent + node.innerHTML).join('')), 'The actual English result render contains no stale Korean dynamic text');
  }
  const rendered = [...resultNodes].map(([id, node]) => [id, node.textContent, node.innerHTML]), animations = resultAnimations;
  resultContext.renderResult();
  equal([...resultNodes].map(([id, node]) => [id, node.textContent, node.innerHTML]), rendered, 'Repeating the same RESULT in the same language preserves the rendered DOM');
  equal(resultAnimations, animations, 'Repeating the same RESULT in the same language does not restart score animation');
  equal(resultWrites.length, 2, 'Language repaint saves the mission and condition record once each');
  equal(resultContext.progress.get('M01').attempts, 1, 'Language repaint does not add mission attempts');
  equal(resultContext.progress.get('same-run').attempts, 1, 'Language repaint does not add condition attempts');
  equal(campaignFinishes, 1, 'Language repaint finishes the campaign once');
  equal(campaignSaves, 1, 'Language repaint persists the campaign once');
  equal(resultContext.resultKey, resultIdentity, 'The original language-independent result identity is preserved');
  equal(resultContext.rewardedResultKey, resultIdentity, 'Reward identity stays independent of presentation language');
  equal(resultContext.campaignResultKey, resultIdentity, 'Campaign identity stays independent of presentation language');
}
equal(resultAnimations, 3, 'Each actual language change repaints the same result exactly once');
console.log(`BREACH_ROOM_CONTROL_WEB_RESULT checks=${checks} failures=0 status=PASS`);
