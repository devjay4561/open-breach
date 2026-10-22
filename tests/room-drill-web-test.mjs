import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

// Exercise the exported public-plan projections without constructing a DOM or
// starting Godot. Native simulation tests own the geometric/resource rules.
const appSource = await readFile(new URL('../web/app.js', import.meta.url), 'utf8');
const start = appSource.indexOf('export function selectedOwnUnitIds');
const end = appSource.indexOf('let lastUnitHP', start);
assert(start >= 0 && end > start, 'The public drill projection exports must remain present');
const api = vm.runInNewContext(`${appSource.slice(start, end).replaceAll('export function', 'function')}
  ({ selectedOwnUnitIds, reorderDrillIds, clampDrillDelay, roomDrillTimeline })`);
const plain = value => JSON.parse(JSON.stringify(value));
let checks = 0;
const equal = (actual, expected, message) => { assert.deepEqual(plain(actual), plain(expected), message); checks++; };
const check = (condition, message) => { assert(condition, message); checks++; };
const freeze = value => {
  if (value && typeof value === 'object') { for (const child of Object.values(value)) freeze(child); Object.freeze(value); }
  return value;
};

const own = [
  { id: 'alpha', hp: 100 }, { id: 'bravo', hp: 1 }, { id: 'charlie', hp: 0 },
  { id: 'delta', hp: 50 }, { id: 'echo', hp: 75 }, { id: 'foxtrot', hp: 100 },
];
const selection = freeze({
  units: own, selected: 'delta', selected_units: ['bravo', 'unseen', 'bravo', 'charlie', 'alpha', 'civilian', 'delta', 'echo', 'foxtrot'],
  enemies: [{ id: 'unseen', hp: 100, x: 15, z: 6 }], civilians: [{ id: 'civilian', hp: 100 }],
});
const selectionBefore = JSON.stringify(selection);
equal(api.selectedOwnUnitIds(selection), ['bravo', 'alpha', 'delta', 'echo'], 'Only four distinct living own operators, in selected order');
equal(api.selectedOwnUnitIds({ units: own, selected: 'delta' }), ['delta'], 'Legacy primary selection defaults to one own operator');
equal(api.selectedOwnUnitIds({ units: own, selected: 'delta', selected_units: [] }), [], 'An explicit empty group remains empty');
equal(api.selectedOwnUnitIds({ units: own, selected: 'charlie' }), [], 'An incapacitated primary is excluded');
equal(api.selectedOwnUnitIds({ units: own, selected: 'unseen' }), [], 'A hidden hostile cannot become a selected operator');
equal(api.selectedOwnUnitIds({ units: own, selected_units: ['delta', 'alpha', 'bravo'] }), ['delta', 'alpha', 'bravo'], 'Tactical order is independent of roster order');
equal(api.selectedOwnUnitIds({ units: own, selected_units: ['alpha'] }), ['alpha']);
equal(api.selectedOwnUnitIds({ units: [], selected: 'alpha' }), []);
equal(api.selectedOwnUnitIds({}), []);
equal(api.selectedOwnUnitIds(null), []);
equal(api.selectedOwnUnitIds({ units: null, selected: 'alpha' }), []);
equal(api.selectedOwnUnitIds({ units: own, selected: 'alpha', selected_units: null }), ['alpha']);
equal(api.selectedOwnUnitIds({ units: [null, { id: 'ghost', hp: Infinity }, { id: 'valid', hp: 1 }, { id: 42, hp: 100 }], selected_units: ['ghost', 'valid', 42] }), ['valid'], 'Only valid finite own-operator records may be projected');
check(JSON.stringify(selection) === selectionBefore, 'Selection projection must not mutate its snapshot');

const order = freeze(['alpha', 'bravo', 'charlie', 'delta']);
equal(api.reorderDrillIds(order, 'bravo', -1), ['bravo', 'alpha', 'charlie', 'delta']);
equal(api.reorderDrillIds(order, 'bravo', 1), ['alpha', 'charlie', 'bravo', 'delta']);
equal(api.reorderDrillIds(order, 'alpha', -1), order, 'First operator cannot move before the group');
equal(api.reorderDrillIds(order, 'delta', 1), order, 'Last operator cannot move beyond the group');
equal(api.reorderDrillIds(order, 'unseen', 1), order, 'Foreign actor cannot alter tactical order');
equal(api.reorderDrillIds(order, 'bravo', 0), order);
equal(api.reorderDrillIds(order, 'bravo', 30), ['alpha', 'charlie', 'bravo', 'delta'], 'Direction means one adjacent slot');
equal(api.reorderDrillIds(order, 'bravo', -30), ['bravo', 'alpha', 'charlie', 'delta']);
equal(api.reorderDrillIds([], 'alpha', 1), []);
equal(api.reorderDrillIds(['alpha'], 'alpha', 1), ['alpha']);
check(api.reorderDrillIds(order, 'alpha', -1) !== order, 'Even a no-op returns an independent draft array');
equal(order, ['alpha', 'bravo', 'charlie', 'delta'], 'Reordering must not mutate the current draft');

for (const [value, expected] of [
  [-20, 0], [-0.1, 0], [0, 0], [0.49, 0], [0.5, 1], [30.4, 30], [30.7, 31],
  [3599.49, 3599], [3599.5, 3600], [3600, 3600], [9000, 3600],
  [NaN, 0], [Infinity, 3600], [-Infinity, 0], [undefined, 0], [null, 0], ['31.7', 32], ['invalid', 0],
]) {
  const actual = api.clampDrillDelay(value);
  equal(actual, expected, `Delay boundary ${String(value)}`);
  check(Number.isInteger(actual) && actual >= 0 && actual <= 3600, 'Delay projection always stays within the integer tick contract');
}

const command = (type, group, rank, stage, extra = {}, state = 'PENDING') => ({
  type, state, args: { ...extra, ...(group ? { drill: { sync_id: group, door_id: 'entry', room_id: 'target_room', order: rank, stage } } : {}) },
});
const base = 'drill-0001', second = 'drill-0002';
const snapshot = freeze({
  selected: 'alpha', selected_units: ['alpha', 'bravo'],
  units: [
    { id: 'alpha', hp: 100, commands: [
      command('WAIT', null, 0, '', { duration: 0.5 }),
      command('MOVE', base, 2, 'stack', { target: [5.8, 7.3] }),
      command('WAIT_FOR_SIGNAL', base, 2, 'ready', { signal: 'B', sync_id: `${base}:ready`, auto_signal: false, delay_ticks: 31 }),
      command('WAIT_FOR_SIGNAL', base, 2, 'entry', { signal: 'B', sync_id: `${base}:entry`, auto_signal: true, delay_ticks: 0 }),
      command('MOVE', base, 2, 'domination', { target: [8.15, 7.6], sector: { start: -0.5, end: 0.5, duration: 12 } }),
      command('WAIT_FOR_SIGNAL', second, 1, 'ready', { signal: 'B', sync_id: `${second}:ready`, auto_signal: false, delay_ticks: 180 }),
      command('FACE', second, 1, 'guard', { target: [4, 6] }),
    ] },
    { id: 'bravo', hp: 100, commands: [
      command('MOVE', base, 1, 'stack', { target: [6.55, 4.7] }),
      command('WAIT_FOR_SIGNAL', base, 1, 'ready', { signal: 'B', sync_id: `${base}:ready`, auto_signal: false, delay_ticks: 31 }),
      command('OPEN_DOOR', base, 1, 'door', { door_id: 'entry' }),
      command('WAIT_FOR_SIGNAL', base, 1, 'entry', { signal: 'B', sync_id: `${base}:entry`, auto_signal: true, delay_ticks: 0 }),
      command('MOVE', base, 1, 'domination', { target: [7.9, 4.4] }),
      command('WAIT_FOR_SIGNAL', null, 0, '', { signal: 'B' }),
      command('WAIT_FOR_SIGNAL', second, 2, 'ready', { signal: 'B', sync_id: `${second}:ready`, auto_signal: false, delay_ticks: 180 }),
    ] },
  ],
});
const before = JSON.stringify(snapshot), groups = api.roomDrillTimeline(snapshot);
equal(groups.map(group => group.id), [base, second], 'Separate drill IDs remain separate even on the same B channel');
const group = groups[0];
equal(group.rows.map(row => row.unit.id), ['bravo', 'alpha'], 'Rows follow tactical rank, not roster traversal');
equal(group.rows.map(row => row.order), [1, 2]);
equal(group.rows.find(row => row.unit.id === 'alpha').commands.map(item => item.index), [1, 2, 3, 4], 'Timeline retains the original command indices after unrelated primitives');
equal(group.rows.find(row => row.unit.id === 'bravo').commands.map(item => item.index), [0, 1, 2, 3, 4]);
equal(group.ready.length, 2, 'Entry barrier and ordinary B waits are not ready handles');
equal(group.sync_id, `${base}:ready`);
equal(group.delay_ticks, 31);
equal(group.editable, true);
equal(groups[1].sync_id, `${second}:ready`);
equal(groups[1].delay_ticks, 180);
equal(groups[1].rows.map(row => row.unit.id), ['alpha', 'bravo']);
check(group.rows.find(row => row.unit.id === 'alpha').unit === snapshot.units[0], 'Projection retains authoritative own-unit records');
check(group.rows.find(row => row.unit.id === 'alpha').commands.at(-1).command === snapshot.units[0].commands[4], 'Edited primitive arguments are the actual command arguments');
equal(group.rows.find(row => row.unit.id === 'alpha').commands.at(-1).command.args.target, [8.15, 7.6]);
check(JSON.stringify(snapshot) === before, 'Timeline projection cannot mutate the source plan');

for (const readyState of ['WAITING', 'RUNNING', 'SUCCEEDED', 'FAILED', 'CANCELLED']) {
  const changed = structuredClone(snapshot);
  changed.units[1].commands[1].state = readyState;
  const projected = api.roomDrillTimeline(changed);
  equal(projected[0].editable, false, `A ${readyState} member prevents an atomic pending-group delay edit`);
  equal(projected[1].editable, true, 'The unrelated group remains editable');
}
const activeStack = structuredClone(snapshot);
activeStack.units[1].commands[0].state = 'RUNNING';
equal(api.roomDrillTimeline(activeStack)[0].editable, true, 'Pending ready delays may be edited while paused before the future barrier');
const noReady = freeze({ units: [{ id: 'alpha', hp: 100, commands: [command('MOVE', base, 1, 'stack', { target: [5.8, 7.3] })] }] });
equal(api.roomDrillTimeline(noReady)[0].editable, false);
equal(api.roomDrillTimeline(noReady)[0].sync_id, `${base}:ready`);
equal(api.roomDrillTimeline(noReady)[0].delay_ticks, 0);
equal(api.roomDrillTimeline({ units: [{ id: 'alpha', commands: [command('MOVE', null, 0, '', { target: [5.8, 7.3] })] }] }), [], 'Legacy non-drill plans add no timeline group');
equal(api.roomDrillTimeline({}), []);
equal(api.roomDrillTimeline(null), []);
equal(api.roomDrillTimeline({ units: null }), []);
equal(api.roomDrillTimeline({ units: [null, { id: 'alpha', commands: null }, { id: 'bravo', commands: [null, { type: 'MOVE', args: {} }] }] }), []);
equal(api.roomDrillTimeline({ units: [{ id: 'alpha', commands: [{ type: 'MOVE', args: { drill: { sync_id: '' } } }] }] }), [], 'An empty group ID cannot create a timeline');
const wrongReady = { units: [{ id: 'alpha', commands: [command('WAIT_FOR_SIGNAL', base, 1, 'ready', { signal: 'B', sync_id: `${second}:ready`, delay_ticks: 30 })] }] };
equal(api.roomDrillTimeline(wrongReady)[0].ready.length, 0, 'A foreign sync ID cannot become this group’s ready handle');
equal(api.roomDrillTimeline(wrongReady)[0].editable, false);

const secretA = { ...snapshot, enemies: [{ id: 'unseen', x: 15, z: 6 }], civilians: [{ id: 'hidden_civilian', x: 14, z: 6 }], room_states: { unseen_room: 'CLEAR' } };
const secretB = { ...snapshot, enemies: [{ id: 'unseen', x: 999, z: -999, hp: 0 }], civilians: [], room_states: { unseen_room: 'CONTACT' } };
equal(api.roomDrillTimeline(secretA), api.roomDrillTimeline(secretB), 'Hidden actor positions and unobserved room states cannot affect an own-plan timeline');
equal(api.selectedOwnUnitIds(secretA), api.selectedOwnUnitIds(secretB), 'Selection cannot reveal a changed hidden room');
check(!JSON.stringify(api.roomDrillTimeline(secretA)).includes('unseen'), 'No hidden contact is copied into the public timeline');

const i18nSource = await readFile(new URL('../web/i18n.js', import.meta.url), 'utf8');
const dictStart = i18nSource.indexOf('const DICTS ='), dictEnd = i18nSource.indexOf('let currentLang', dictStart);
assert(dictStart >= 0 && dictEnd > dictStart, 'The paired i18n dictionaries must remain readable');
const dictionaries = vm.runInNewContext(`${i18nSource.slice(dictStart, dictEnd)}; DICTS`);
const i18n = await import(`data:text/javascript;base64,${Buffer.from(i18nSource).toString('base64')}`);
const keys = Object.keys(dictionaries.ko).filter(key => key.startsWith('drill.')).sort();
check(keys.length >= 78, 'All P2 drill interface and reason keys remain present');
equal(Object.keys(dictionaries.en).filter(key => key.startsWith('drill.')).sort(), keys, 'Every drill key must exist in both languages');
for (const language of ['ko', 'en']) {
  const begin = i18nSource.indexOf(`${language}: {`), next = language === 'ko' ? i18nSource.indexOf('en: {', begin) : dictEnd;
  const declared = [...i18nSource.slice(begin, next).matchAll(/'(drill\.[^']+)'\s*:/g)].map(match => match[1]);
  equal(declared.length, new Set(declared).size, `${language} dictionary must not contain shadowed duplicate drill keys`);
  i18n.setLanguage(language);
  for (const key of keys) {
    const text = i18n.t(key, { name: 'ALPHA', seconds: '1.0' });
    check(typeof text === 'string' && text.trim().length > 0 && text !== key, `${language} resolves ${key}`);
    if (language === 'en') check(!/[가-힣]/.test(text), `English ${key} contains no untranslated Korean`);
  }
  const note = i18n.t('drill.doctrine');
  check(note.includes('2') && !/\b(?:19|20)\d{2}\b/.test(note), `${language} describes the fictional operation team leader position`);
}
i18n.setLanguage('en');
equal(i18n.translateCommandReason('앞 대원의 진입 간격 유지 중'), dictionaries.en['drill.entry_spacing']);
i18n.setLanguage('ko');
equal(i18n.translateCommandReason('앞 대원의 진입 간격 유지 중'), dictionaries.ko['drill.entry_spacing']);
console.log(`BREACH_ROOM_DRILL_WEB_RESULT checks=${checks} failures=0 status=PASS`);
