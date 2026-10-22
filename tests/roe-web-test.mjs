import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import { normalizeOperatorLoadout, CATALOG } from '../web/operator-equipment.js';
import { CAMPAIGN_MISSIONS, EQUIPMENT, WEAPONS, ROSTER, missionBase, missionId, migrateMedals } from '../web/meta.js';
import { evaluateStar, summarizeRun } from '../web/debrief.js';
import * as i18n from '../web/i18n.js';

const app = await readFile(new URL('../web/app.js', import.meta.url), 'utf8');
const html = await readFile(new URL('../web/index.html', import.meta.url), 'utf8');
let checks = 0;
const plain = value => JSON.parse(JSON.stringify(value));
const equal = (value, expected, label) => { assert.deepEqual(plain(value), plain(expected), label); checks++; };
const check = (value, label) => { assert.ok(value, label); checks++; };
function section(start, end) {
  const begin = app.indexOf(start), finish = app.indexOf(end, begin);
  assert.ok(begin >= 0 && finish > begin, `Actual source ${start}`);
  return app.slice(begin, finish).replaceAll('export function', 'function');
}
const escapeHTML = value => String(value ?? '').replace(/[&<>"']/g, char => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[char]));
const catalog = new Map([['M01_PRECISION', { roe: 'precision' }], ['M01_HIGH_INTENSITY', { roe: 'high_intensity' }]]);
const ctx = vm.createContext({ t: i18n.t, escapeHTML, catalog, state: {}, Object, Number });
vm.runInContext(section('export function missionRoe', 'const icons ='), ctx);
for (const value of [undefined, null, {}, { roe: 'unknown' }, { roe: 'HIGH_INTENSITY' }]) equal(ctx.missionRoe(value), 'precision', 'Legacy or invalid policy stays conservative');
equal(ctx.missionRoe({ roe: 'high_intensity' }), 'high_intensity');
for (const id of ['stun', 'smoke', 'breach', 'probe_c1']) check(ctx.equipmentPermitted(id, {}), 'Legacy tools retain deployment permission');
equal(ctx.equipmentPermitted('frag', {}), false);
equal(ctx.equipmentPermitted('frag', { roe: 'high_intensity' }), true);
ctx.state = { mission: 'M01_HIGH_INTENSITY' }; equal(ctx.runtimeRoe(), 'high_intensity', 'Legacy snapshot may use authored public catalog policy');
ctx.state.roe = 'precision'; equal(ctx.runtimeRoe(), 'precision', 'Authority overrides catalog policy');

const high = { roe: 'high_intensity' };
equal(ctx.availableFrags({ frags: 2, available_frags: 0 }, high), 0, 'Reserved authority zero overrides raw stock');
equal(ctx.availableFrags({ frags: 0, available_frags: 8 }, high), 8, 'Do not clamp valid authoritative counts');
for (const value of [-1, 0.5, '2', null]) equal(ctx.availableFrags({ frags: 2, available_frags: value }, high), 0, 'Invalid authority cannot enable throws');
equal(ctx.availableFrags({ frags: 2, available_frags: 2 }, {}), 0, 'Precision never deploys frags');
equal(ctx.availableFrags({ frags: 2, commands: [{ type: 'THROW_FRAG', state: 'PENDING' }] }, high), 1, 'Legacy fallback reserves unfinished throws');
equal(ctx.availableFrags({ frags: 2, commands: [{ type: 'THROW_FRAG', state: 'SUCCEEDED' }] }, high), 2);

const profile = normalizeOperatorLoadout({ weapon: 'standard', equipment: { frag: 2 } });
const original = JSON.stringify(profile);
const rosterId = ROSTER[0].id;
const prep = vm.createContext({ ensureSquad() {}, catalog, selectedMission: 'M01_PRECISION', squadIds: [rosterId], ROSTER, WEAPONS, EQUIPMENT,
  unlockProfile: { stars: 0 }, loadoutChoices: { [rosterId]: profile }, selectedModifiers: new Set(), normalizeOperatorLoadout,
  rosterName: unit => unit.name, equipmentPermitted: ctx.equipmentPermitted });
vm.runInContext(section('function currentPreparation()', 'function resolvedSeed'), prep);
equal(prep.currentPreparation().loadout.alpha.equipment, {}, 'Precision filters deployment equipment only');
equal(JSON.stringify(profile), original, 'Mission policy never edits the stored operator profile');
prep.selectedMission = 'M01_HIGH_INTENSITY';
equal(prep.currentPreparation().loadout.alpha.equipment, { frag: 2 }, 'High intensity restores the same stored profile equipment');
equal(JSON.stringify(profile), original);
equal(normalizeOperatorLoadout({ equipment: ['stun', 'breach'] }).equipment, { stun: 1, smoke: 0, breach: 1, probe_c1: 0 }, 'Legacy arrays keep their exact zero-key shape');
equal(normalizeOperatorLoadout({ equipment: ['frag'] }).equipment.frag, 1, 'A newly selected frag is preserved');
check(CATALOG.equipment.some(item => item.id === 'frag' && item.weight === 0.4 && item.stars === 0), 'Catalog append retains the accepted weight/unlock');
const options = vm.createContext({ unlockProfile: { stars: 0 }, EQUIPMENT, WEAPONS, SIDEARMS: CATALOG.sidearms, ARMORS: CATALOG.armor,
  HELMETS: CATALOG.helmets, PRESETS: CATALOG.presets, catalog, selectedMission: 'M01_PRECISION', selectedModifiers: new Set(),
  localize: i18n.localize, t: i18n.t, equipmentPermitted: ctx.equipmentPermitted });
vm.runInContext(section('function profileTool(', 'function showProfileSaveStatus('), options);
equal(options.profileTool(profile), 'frag', 'The profile cycler continues to display its stored selection');
equal(options.loadoutCyclerOptions('equipment').find(item => item.id === 'frag').disabled, true, 'The actual precision equipment cycler blocks deployment selection');
options.selectedMission = 'M01_HIGH_INTENSITY';
equal(options.loadoutCyclerOptions('equipment').find(item => item.id === 'frag').disabled, false, 'The same actual high-intensity cycler enables the free-unlock frag');

const gridNodes = new Map();
const grid = vm.createContext({ $: id => { if (!gridNodes.has(id)) gridNodes.set(id, { innerHTML: '', textContent: '' }); return gridNodes.get(id); }, $$: () => [],
  catalog, missions: Object.fromEntries(['T01', ...CAMPAIGN_MISSIONS, ...catalog.keys()].map(id => [id, { name: id, name_en: id }])),
  operationCollection: 'base', CAMPAIGN_MISSIONS, catalogRevision: 1, getLanguage: i18n.getLanguage, unlockProfile: { stars: 0, completedBases: new Set(), campaignAccess: new Set() },
  lastMissionGridKey: '', progress: new Map(), migrateMedals, missionAccess: () => ({ unlocked: true }),
  missionThumbMarkup: () => '<svg aria-hidden="true"></svg>', roeBadge: ctx.roeBadge, localize: i18n.localize, escapeHTML, t: i18n.t });
vm.runInContext(section('function renderMissionGrid()', '// --- RB2: variant chip row'), grid);

const choose = vm.createContext({ missionBase, missionId, selectedVariant: 'escort', selectedDifficulty: 'challenge', selectedMission: 'M01', operationCollection: 'history',
  updateBrief() {}, engineReady: true, send: value => choose.sent.push(plain(value)), sent: [] });
vm.runInContext(section('function chooseMission(', 'function nextMission('), choose);
for (const id of catalog.keys()) {
  choose.chooseMission(id); equal(choose.selectedMission, id, 'Comparison missions retain distinct IDs');
  equal(choose.selectedDifficulty, 'normal'); equal(choose.selectedVariant, 'standard'); equal(choose.operationCollection, 'base');
  equal(choose.sent.at(-1).data.mission_id, id, 'The actual bridge receives the exact authored comparison ID');
}

const success = { time: 15, units: [{ hp: 100 }], result: { status: 'SUCCESS', civilian_damage: 0, unit_damage: 0, stars: { complete: true, no_civilian_damage: false } } };
equal(evaluateStar({ id: 'complete' }, success), true);
equal(evaluateStar({ id: 'no_civilian_damage', stat: 'civilian_damage', value: 0 }, success), false, 'Authoritative verdict has priority over a public zero counter');
equal(evaluateStar({ id: 'missing', stat: 'unit_damage', value: 0 }, success), false, 'Missing authored ID in a present authority map stays false');
for (const stars of [null, [], { complete: 'true' }, { complete: 1 }]) equal(evaluateStar({ id: 'complete' }, { ...success, result: { status: 'SUCCESS', stars } }), false, 'Authority map verdicts are strict booleans');
equal(evaluateStar({ id: 'complete' }, { ...success, result: { status: 'FAILURE', stars: { complete: true } } }), false, 'Failure cannot award even an authoritative true');
equal(evaluateStar({ id: 'no_civilian_damage', stat: 'civilian_damage', value: 0 }, { ...success, result: { status: 'SUCCESS', civilian_damage: 0 } }), true, 'Absent entire map preserves legacy computation');
equal(evaluateStar({ id: 'complete' }, { ...success, result: { status: 'SUCCESS', stars_observed: { complete: false } } }), true, 'Private auxiliary maps are never consulted');
equal(summarizeRun({ ...success, stars: [{ id: 'no_civilian_damage', stat: 'civilian_damage', value: 0 }] }).goals[0].done, false, 'Displayed goals use the authority verdict');

const lines = { walls: [{ id: 'drywall', material: 'drywall', thin: true, rifle_penetrable: true, resistance: 0.2 },
  { id: 'concrete', material: 'concrete', rifle_penetrable: false }, { id: 'thin', material: '', thin: true, rifle_penetrable: true },
  { id: 'unspecified', material: '', thin: false, rifle_penetrable: false }], rifle_budget: 0.6, enemies: [{ id: 'secret', x: 2 }] };
const reasonPairs = { 'frag.forbidden':'정밀 교전수칙에서는 파편 수류탄을 사용할 수 없습니다', 'frag.no_inventory':'예약분을 제외한 파편 수류탄이 없습니다',
  'frag.range':'파편 수류탄 투척 범위 8m를 벗어났습니다', 'frag.path':'벽 또는 닫힌 문이 파편 수류탄 투척 경로를 막습니다',
  'frag.changed':'파편 수류탄 재고 또는 투척 경로가 변경되었습니다', 'frag.waiting':'파편 수류탄 폭발까지 대기' };
const keys = ['command.THROW_FRAG', 'equipment.frag', 'equipment.frag_note', 'equipment.frag_hint', 'equipment.frag_required', 'equipment.frag_stock',
  'roe.precision', 'roe.high_intensity', 'roe.precision_note', 'roe.high_intensity_note', 'roe.frag_prohibited', 'roe.profile_preserved',
  'door.no_adjacent_walls', 'door.rifle_penetrable', 'door.rifle_blocked', 'door.rifle_single_wall', 'event.FRAG_RELEASE', 'event.FRAG', 'frag.prepare',
  'star.no_civilian_damage', 'star.capture_surrendered', 'star.no_unit_damage', 'star.roe_time', ...Object.keys(reasonPairs),
  ...['wood','concrete','metal','fabric','glass','masonry','plaster','foliage','steel','drywall','brick','cloth','thin','unspecified'].map(id => 'door.material.' + id)];
for (const language of ['ko', 'en']) {
  i18n.setLanguage(language);
  for (const key of keys) { check(i18n.t(key) !== key, `Paired ${language} key ${key}`); if (language === 'en') check(!/[가-힣]/.test(i18n.t(key)), 'English UI never falls back to Korean'); }
  const result = ctx.doorStructureLines(lines);
  grid.renderMissionGrid();
  const cards = gridNodes.get('mission-grid').innerHTML;
  for (const id of ['T01', ...CAMPAIGN_MISSIONS, ...catalog.keys()]) check(cards.includes(`data-mission="${id}"`), 'Actual card renderer preserves every old operation and appends both comparison IDs');
  for (const policy of ['precision','high_intensity']) check(cards.includes(`data-roe="${policy}"`) && cards.includes(i18n.t('roe.' + policy)), 'Actual comparison cards show localized policy badges');
  equal(result.length, 4); check(result[0].includes(i18n.t('door.material.drywall')) && result[0].includes(i18n.t('door.rifle_penetrable')));
  check(result[1].includes(i18n.t('door.rifle_blocked'))); check(result[2].includes(i18n.t('door.material.thin'))); check(result[3].includes(i18n.t('door.material.unspecified')));
  check(!JSON.stringify(result).includes('secret'), 'Structural display ignores hidden entities and raw auxiliary data');
  equal(ctx.doorStructureLines({ walls: [] }), [i18n.t('door.no_adjacent_walls')]); equal(ctx.doorStructureLines(null), []);
  for (const [key, reason] of Object.entries(reasonPairs)) equal(i18n.translateCommandReason(reason), i18n.t(key), 'Exact native reasons translate in both languages');
  for (const type of ['FRAG_RELEASE','FRAG']) {
    equal(i18n.translateEvent({ type, observed: true }), i18n.t('event.' + type));
    for (const observed of [undefined, false, 'true']) equal(i18n.translateEvent({ type, observed }), '', 'Unobserved fragmentation events are not presented');
  }
  check(ctx.roeBadge({ roe: 'high_intensity' }).includes('data-roe="high_intensity"'));
}
for (const id of ['select-roe','select-roe-note','briefing-roe','briefing-roe-note']) check(html.includes(`id="${id}"`), 'Both card detail and deployment briefing have actual policy surfaces');
check(html.includes('data-tool="frag"') && html.includes('data-i18n="equipment.frag"'), 'Fragmentation grenade uses the real equipment submenu');
check(app.includes("...roeIds]") && app.includes("'M01_PRECISION','M01_HIGH_INTENSITY'"), 'Both authored comparison cards are appended without replacing old cards');
i18n.setLanguage('ko');
console.log(`BREACH_ROE_WEB_RESULT checks=${checks} failures=0 status=PASS`);
