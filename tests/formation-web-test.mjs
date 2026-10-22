import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

// Actual public projections and bridge/editor flows, without an engine,
// browser, timers or an alternate implementation of formation geometry.
const app = await readFile(new URL('../web/app.js', import.meta.url), 'utf8');
const source = await readFile(new URL('../web/i18n.js', import.meta.url), 'utf8');
const i18n = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
const plain = value => JSON.parse(JSON.stringify(value));
let checks = 0;
const equal = (actual, expected, message) => { assert.deepEqual(plain(actual), plain(expected), message); checks++; };
const check = (value, message) => { assert(value, message); checks++; };
const escapeHTML = value => String(value ?? '').replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));
function section(start, end) {
  const begin = app.indexOf(start), finish = app.indexOf(end, begin);
  assert(begin >= 0 && finish > begin, `${start} actual source remains available`);
  return app.slice(begin, finish).replaceAll('export function', 'function');
}
const own = ['alpha', 'bravo', 'charlie', 'delta'];
const snapshot = {
  mode: 'PLANNING', mission: 'FORMATION_UI', tool: 'formation', selected: 'alpha', selected_units: [...own],
  units: own.map((id, index) => ({ id, name: id.toUpperCase(), hp: 100, x: 2, z: 1 + index, stance: 'standing', commands: [] })),
  enemies: [{ id: 'secret', position: [11, 9] }], room_states: { hidden: { state: 'CLEAR', observed: false } },
};
const helpers = vm.runInNewContext(`${section('export function selectedOwnUnitIds', 'let lastUnitHP')}\n({selectedOwnUnitIds,reorderDrillIds,clampDrillDelay,roomDrillTimeline,formationDraftForTarget,formationInputKey,formationPreviewCurrent,formationSignalPolicy});`);
for (const size of [2, 3, 4]) {
  const state = { ...snapshot, selected_units: own.slice(0, size) }, target = [8, 4], order = [...state.selected_units].reverse();
  const draft = helpers.formationDraftForTarget(state, target, order);
  equal(draft, { mission: state.mission, target, order, kind: 'AUTO', signal: 'AUTO', delay_ticks: 0 }, 'Native target picks retain the actual own-group order');
  draft.target[0] = 0; draft.order.pop();
  equal(target, [8, 4], 'The draft owns its target array'); equal(order.length, size, 'The draft owns its order array');
}
for (const order of [[], ['alpha'], [...own, 'extra'], ['alpha', 'alpha'], ['alpha', 'secret'], ['alpha', 'bravo']]) {
  equal(helpers.formationDraftForTarget(snapshot, [8, 4], order), null, 'Invalid or stale target-pick groups never open an editor');
}
for (const target of [null, [], [8], [8, 4, 2], ['8', 4], [NaN, 4], [Infinity, 4]]) equal(helpers.formationDraftForTarget(snapshot, target, own), null, 'Targets must be finite native world coordinates');
for (const mode of ['MENU', 'EXECUTING', 'RESULT', 'REPLAY']) equal(helpers.formationDraftForTarget({ ...snapshot, mode }, [8, 4], own), null, 'Formation target picks open only while planning');
for (const tool of ['select', 'move', 'face', 'door', undefined]) equal(helpers.formationDraftForTarget({ ...snapshot, tool }, [8, 4], own), null, 'Late map picks cannot reopen an editor after the authoritative tool changed');
equal(helpers.formationDraftForTarget({ ...snapshot, units: snapshot.units.map(unit => unit.id === 'delta' ? { ...unit, hp: 0 } : unit) }, [8, 4], own), null, 'Incapacitated operators cannot enter a new formation');
const draft = helpers.formationDraftForTarget(snapshot, [8, 4], own), key = helpers.formationInputKey(snapshot, draft);
equal(helpers.formationInputKey({ ...snapshot, enemies: [{ id: 'other-secret', position: [1, 3] }], room_states: { hidden: { state: 'CONTACT', observed: false } } }, draft), key, 'Unobserved contacts and room states do not invalidate or affect formation previews');
check(helpers.formationInputKey({ ...snapshot, units: snapshot.units.map(unit => unit.id === 'alpha' ? { ...unit, commands: [{ type: 'MOVE', state: 'PENDING', args: { target: [5, 4] } }] } : unit) }, draft) !== key, 'Own primitive edits invalidate the authoritative preview');
check(!key.includes('secret') && !key.includes('hidden'), 'Preview invalidation keys contain no hidden information');
for (const preview of [undefined, {}, { preview_id: 'older' }, { preview_id: null }]) equal(helpers.formationPreviewCurrent({ preview_id: 'current' }, preview), false, 'Only the correlated current preview response is accepted');
equal(helpers.formationPreviewCurrent({ preview_id: 'current' }, { preview_id: 'current' }), true, 'The latest response can enable commit');
equal(helpers.formationPreviewCurrent(null, { preview_id: 'current' }), false, 'Cancelled editors reject late replies');
equal(helpers.formationSignalPolicy(), 'verbal', 'Legacy missions default to verbal policy');
equal(helpers.formationSignalPolicy({}, { noise_discipline: 'hand_signals' }), 'hand_signals', 'Public authored mission policy is presented');
equal(helpers.formationSignalPolicy({ noise_discipline: 'verbal' }, { noise_discipline: 'hand_signals' }), 'verbal', 'Authoritative preview policy takes precedence');
equal(helpers.formationSignalPolicy({}, {}, { noise_discipline: 'hand_signals' }), 'hand_signals', 'Public snapshot policy is supported');

const nodes = new Map(), sent = [];
let canvasFocuses = 0, drillCloses = 0;
const node = id => {
  if (!nodes.has(id)) nodes.set(id, {
    hidden: ['formation-panel', 'room-drill-panel', 'pause-panel'].includes(id), open: false,
    innerHTML: '', textContent: '', disabled: false,
    querySelector: () => null, querySelectorAll: () => [],
    focus() { if (id === 'canvas') canvasFocuses++; },
  });
  return nodes.get(id);
};
const context = vm.createContext({
  ...helpers, state: structuredClone(snapshot), $: node, t: i18n.t, getLanguage: i18n.getLanguage,
  rosterName: unit => unit?.name || '', escapeHTML, catalog: new Map([[snapshot.mission, { noise_discipline: 'hand_signals' }]]),
  formationDraft: null, formationPreview: {}, formationPending: false, formationSequence: 0, lastFormationHTML: '',
  roomDrillDraft: null, roomDrillSequence: 0, lastMission: snapshot.mission,
  FORMATION_KINDS: ['AUTO', 'SERPENTINE', 'ROLLING_T', 'T_JUNCTION'],
  document: { activeElement: null }, engineReady: true, lastUiFocus: null, missions: {},
  send: message => { sent.push(plain(message)); return true; },
  closeRoomDrill() { drillCloses++; }, closeContext() {},
});
vm.runInContext(`${section('function domOverlayOpen()', 'function toast(')}\n${section('function startFormationTool()', 'function timelineCommand(')}\n${section('function receive(message)', 'function showLoaded()')}`, context);
const preview = {
  ok: true, kind: 'ROLLING_T', corridor_width: 2.4, order_ids: own, noise_discipline: 'hand_signals',
  slots: own.map((unit_id, index) => ({ unit_id, index: index + 1, stance: index % 2 ? 'standing' : 'crouched', target: [8, 4] })),
};
for (const language of ['ko', 'en']) {
  i18n.setLanguage(language); sent.length = 0;
  context.state = structuredClone(snapshot); context.startFormationTool();
  equal(sent.at(-1), { action: 'tool', tool: 'formation' }, 'The hotbar tool requests native picking rather than a JS map projection');
  check(sent.some(intent => intent.action === 'room_drill_preview' && intent.clear), 'Starting formation clears a previous room-drill ghost');
  context.receive({ type: 'formation_target', target: [8, 4], order: own });
  const first = sent.findLast(intent => intent.action === 'formation_preview' && !intent.clear);
  equal({ ...first, preview_id: 'CORRELATED' }, { action: 'formation_preview', preview_id: 'CORRELATED', target: [8, 4], order: own, kind: 'AUTO', options: { append: true, signal: 'AUTO', delay_ticks: 0 } }, 'The external API has one top-level kind and only the agreed macro options');
  equal(node('formation-commit').disabled, true, 'Pending previews cannot be committed');
  check(sent.some(intent => intent.action === 'input_focus' && intent.blocked === true), 'The editor blocks native canvas input');
  context.formationDraft.signal = 'B'; context.formationDraft.delay_ticks = 3600; context.formationRequest();
  const current = sent.at(-1);
  context.receive({ type: 'formation_preview', preview_id: first.preview_id, data: preview });
  equal(node('formation-commit').disabled, true, 'An older successful preview cannot enable a newer editor request');
  context.receive({ type: 'formation_preview', preview_id: current.preview_id, data: preview });
  equal(node('formation-commit').disabled, false, 'The latest successful authoritative preview enables commit');
  const rendered = node('formation-editor-content').innerHTML;
  check(rendered.includes(i18n.t('formation.ROLLING_T')) && rendered.includes(i18n.t('formation.recommended', { kind: i18n.t('formation.ROLLING_T'), width: '2.40' })), 'Resolved kind and physical corridor width are displayed');
  check(rendered.includes(i18n.t('noise.hand_signals_note')), 'The editor explains the mission signal policy');
  check(rendered.includes(i18n.t('formation.crouched')) && rendered.includes(i18n.t('formation.standing')), 'The preview displays planned low and high stances');
  check(!/<(?:select|input)/.test(rendered), 'The formation editor uses existing button controls');
  if (language === 'en') check(!/[가-힣]/.test(rendered), 'The English editor has no raw Korean text');
  const beforeCommit = sent.length;
  context.formationRequest('formation');
  equal(sent.at(-1).options, { append: true, signal: 'B', delay_ticks: 3600 }, 'The maximum delay and manual signal reach the plan request unchanged');
  context.closeFormation(true);
  equal(node('formation-panel').hidden, true, 'Commit closes the editor');
  check(!sent.slice(beforeCommit).some(intent => intent.action === 'formation_preview' && intent.clear), 'Commit preserves the authoritative map preview');
  context.receive({ type: 'formation_preview', preview_id: current.preview_id, data: preview });
  equal(node('formation-panel').hidden, true, 'Late replies do not reopen a committed editor');
  equal(context.state.units.flatMap(unit => unit.commands), [], 'The web expands no primitive commands and changes no stance directly');
  context.openFormation([8, 4], own); sent.length = 0; context.closeFormation();
  check(sent.some(intent => intent.action === 'formation_preview' && intent.clear && intent.preview_id), 'Cancel clears the native ghost with a correlated intent');
  check(sent.some(intent => intent.action === 'tool' && intent.tool === 'select'), 'Cancel returns the native tool to selection');
  check(sent.some(intent => intent.action === 'input_focus' && intent.blocked === false), 'Cancel releases native canvas input');
  equal(context.formationDraft, null, 'Cancel discards its draft');
  context.openFormation([8, 4], own); context.formationPreview = { ok: true, resolved: 'SERPENTINE', slots: [] }; context.formationPending = false; context.renderFormation();
  check(node('formation-editor-content').innerHTML.includes(`<strong>${i18n.t('formation.SERPENTINE')}</strong>`), 'The resolved preview alias is supported without requiring a duplicate kind');
  context.closeFormation();
}
check(canvasFocuses > 0 && drillCloses > 0, 'Editor transitions restore canvas focus and close the other editor');
context.state = { ...structuredClone(snapshot), tool: 'move' }; sent.length = 0;
context.receive({ type: 'formation_target', target: [8, 4], order: own });
equal(context.formationDraft, null, 'A late native target event does not reopen a cancelled formation editor');
equal(sent, [], 'A late target event does not block input or send a preview for a different native tool');
vm.runInContext(`${section('function renderState() {', '  const modeChanged=')}\n}`, context);
for (const change of [{ mode: 'EXECUTING' }, { mission: 'OTHER' }, { tool: 'move' }, { selected_units: own.slice(0, 2) }]) {
  context.state = structuredClone(snapshot); context.openFormation([8, 4], own); sent.length = 0;
  Object.assign(context.state, change); context.renderState();
  equal(context.formationDraft, null, 'Mode, mission, tool and selection changes cancel the editor');
  check(sent.some(intent => intent.action === 'formation_preview' && intent.clear), 'An invalidated draft clears its native preview');
  check(!sent.some(intent => intent.action === 'tool'), 'An authoritative tool/mode change is not overwritten by web cancellation');
}
Object.assign(context, { drillDelayDrag: null, drillTimelineGroup: '', lastDrillHTML: '', DRILL_STAGES: ['stack', 'ready', 'door', 'entry'], scheduleSafeArea() {} });
vm.runInContext(section('function timelineCommand(', 'function updateDrillDelayHandle('), context);
for (const size of [0, 1, 2, 3, 4]) {
  context.state = { ...structuredClone(snapshot), selected_units: own.slice(0, size) }; context.renderDrillTimeline();
  equal(!node('drill-timeline').hidden && node('drill-timeline').innerHTML.includes('id="formation-tool"'), size >= 2, 'The actual hotbar offers formation only for a selected group');
}
context.state.mode = 'EXECUTING'; context.renderDrillTimeline();
check(!node('drill-timeline').innerHTML.includes('id="formation-tool"'), 'Execution does not offer a new planning macro');
let onKey;
context.document.addEventListener = (type, handler) => { assert.equal(type, 'keydown'); onKey = handler; };
context.cancelDrillDelayDrag = () => {};
const keyStart = "  document.addEventListener('keydown',event=>{\n    if(event.key==='Escape'&&drillDelayDrag)";
vm.runInContext(section(keyStart, "  document.addEventListener('click',async event=>"), context);
context.state = structuredClone(snapshot); context.openFormation([8, 4], own); sent.length = 0;
let prevented = 0, stopped = 0;
onKey({ key: 'Escape', preventDefault: () => prevented++, stopImmediatePropagation: () => stopped++ });
equal([prevented, stopped], [1, 1], 'Escape cancellation consumes the key before the native pause path');
equal(context.formationDraft, null, 'Escape closes the actual formation editor');
check(sent.some(intent => intent.action === 'formation_preview' && intent.clear), 'Escape clears the real preview intent');
const dictionaries = vm.runInNewContext(`${source.slice(source.indexOf('const DICTS ='), source.indexOf('let currentLang'))}; DICTS;`);
const commandContext = vm.createContext({ t: i18n.t, getLanguage: i18n.getLanguage, translateCommandReason: i18n.translateCommandReason });
vm.runInContext(`${section('const commandNames_ko', 'const toolHints =')}\n${section('function commandDescription(', 'function renderCommands(')}`, commandContext);
const replayKeys = ['formation', 'planned_stance', 'formation_signal', 'signal_delivery', 'signal_mode', 'signal_sender', 'signal_receivers'].map(key => `replay.error.${key}`);
equal(replayKeys.length, 7, 'P4 adds exactly seven formation/signal replay diagnoses');
const replay = await readFile(new URL('../game/scripts/replay.gd', import.meta.url), 'utf8');
for (const key of replayKeys) check(replay.includes(`_fail("${dictionaries.ko[key]}")`), 'Each P4 diagnosis matches the actual native replay failure string');
const keys = [...Object.keys(dictionaries.ko).filter(key => key.startsWith('formation.') || key.startsWith('noise.')), 'team.invalid_signal', 'team.invalid_sender', ...replayKeys];
for (const language of ['ko', 'en']) {
  i18n.setLanguage(language);
  for (const key of keys) {
    check(Object.hasOwn(dictionaries[language], key), `${language} defines ${key}`);
    const value = i18n.t(key, { name: 'ALPHA', kind: 'SERPENTINE', width: '1.70' });
    check(value && value !== key, `${language} translates ${key}`);
    if (language === 'en') check(!/[가-힣]/.test(value), `English ${key} contains no raw Korean`);
  }
  for (const [reason, key] of [['대형 명령 정보가 올바르지 않습니다', 'formation.error.metadata'], ['대형 대기 신호가 단계와 일치하지 않습니다', 'formation.error.wait'], ['자세 설정이 올바르지 않습니다', 'formation.error.stance'], ['벽·문·가구 때문에 대형 경로에 접근할 수 없습니다', 'formation.error.route']]) equal(i18n.translateCommandReason(reason), i18n.t(key), 'P4 raw command failure reasons use paired translations');
  for (const stance of ['standing', 'crouched']) check(commandContext.commandDescription({ type: 'FACE', state: 'PENDING', args: { stance } }).includes(i18n.t('formation.' + stance)), 'Queued FACE descriptions display the planned stance');
  const description = commandContext.commandDescription({ type: 'WAIT_FOR_SIGNAL', state: 'PENDING', args: { signal: 'B', delay_ticks: 3600, formation: { kind: 'T_JUNCTION', stage: 'ready' } } });
  check(description.includes(i18n.t('formation.T_JUNCTION')) && description.includes(i18n.t('drill.delay_value', { seconds: '120.0' })), 'Queued formation signal descriptions retain kind and delay');
}
console.log(`BREACH_FORMATION_WEB_RESULT checks=${checks} failures=0 status=PASS`);
