import assert from 'node:assert/strict';
import { readFile, writeFile, mkdir } from 'node:fs/promises';

// Pure observation contracts with a deterministic clock. No browser automation
// or synthetic numbers are presented as measured game/browser performance.
const source = await readFile(new URL('../web/quality-metrics.js', import.meta.url), 'utf8');
const { createQualityMetrics } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
let checks = 0;
const check = (condition, message) => { checks++; assert.ok(condition, message); };
class Target {
  constructor() { this.listeners = new Map(); }
  addEventListener(type, callback) { if (!this.listeners.has(type)) this.listeners.set(type, new Set()); this.listeners.get(type).add(callback); }
  removeEventListener(type, callback) { this.listeners.get(type)?.delete(callback); }
  emit(type, fields = {}) { for (const callback of [...(this.listeners.get(type) || [])]) callback({ type, ...fields }); }
}
function environment(search = '?qa=1') {
  let clock = 0, nextId = 0, nodeCount = 15;
  const callbacks = new Map();
  const resources = [];
  const elements = [];
  const doc = new Target(); doc.hidden = false; doc.querySelectorAll = () => Array(nodeCount + elements.length).fill(null);
  doc.createElement = tag => ({ tagName: tag.toUpperCase(), textContent: '', remove() { const index = elements.indexOf(this); if (index >= 0) elements.splice(index, 1); } });
  doc.body = { append: node => elements.push(node) };
  const win = new Target();
  Object.assign(win, { document: doc, innerWidth: 1440, innerHeight: 900, devicePixelRatio: 2,
    navigator: { userAgent: 'deterministic-test' }, location: { href: `http://local.test/${search}`, origin: 'http://local.test', search },
    console: { error() {}, warn() {} },
    requestAnimationFrame: callback => { callbacks.set(++nextId, callback); return nextId; },
    cancelAnimationFrame: id => callbacks.delete(id),
    performance: { now: () => clock, memory: { usedJSHeapSize: 1000, totalJSHeapSize: 2000 }, getEntriesByType: kind => kind === 'resource' ? resources : [] },
  });
  return { win, doc, resources, callbacks, elements,
    time: () => clock,
    advance: (amount, paint = true, frameTimestamp = undefined) => { clock += amount; if (paint) { const batch = [...callbacks.values()]; callbacks.clear(); for (const callback of batch) callback(frameTimestamp ?? clock); } },
    input: (type = 'pointerdown', fields = {}) => doc.emit(type, { isTrusted: true, timeStamp: clock, target: { id: 'canvas', tagName: 'CANVAS' }, ...fields }),
    nodes: count => { nodeCount = count; },
  };
}
const state = (changes = {}) => ({ type: 'state', mode: 'PLANNING', mission: 'M01', selected: 'bravo', tool: 'select', time: 0,
  units: [{ id: 'alpha', commands: [] }, { id: 'bravo', commands: [] }], enemies: [], civilians: [], events: [], ...changes });

{
  const env = environment(''); const before = env.win.console.error;
  const disabled = createQualityMetrics({ window: env.win });
  check(!disabled.enabled && env.callbacks.size === 0, 'Without opt-in there must be no sampling work');
  check(env.win.BreachQuality === undefined && env.win.console.error === before, 'Disabled metrics must not publish globals or replace logging');
  check(disabled.trackIntent({ action: 'select' }) === null, 'Disabled metrics must not mint a token');
}
{
  const env = environment(); const metrics = createQualityMetrics({ window: env.win, buildId: 'test-build' });
  metrics.noteState(state());
  env.advance(100, false); env.input();
  const token = env.win.BreachQuality.latestInputToken;
  check(typeof token === 'string', 'Trusted raw input should create a token');
  for (const action of ['input_focus', 'settings', 'preview', 'get_plan', 'export_replay']) check(metrics.trackIntent({ action }) === null, `${action} must not consume a raw input token`);
  check(env.win.BreachQuality.latestInputToken === token, 'Automatic focus messages must leave the canvas token intact');
  check(metrics.trackIntent({ action: 'select', id: 'alpha' }) === token, 'Intent should correlate to its preceding trusted input');
  env.advance(10, false);
  metrics.noteState(state({ selected: 'alpha', quality: { ack_tokens: [token], render_nodes: 50, render_entities: 2, active_effects: 0 } }));
  let report = metrics.report();
  check(report.input.inputToNextBridgeState.meanMs === 10, 'Transport receipt should have its own timing');
  check(report.input.inputToRenderAcknowledgement.meanMs === 10, 'Explicit render acknowledgement must preserve the token timing');
  check(report.input.inputToNextAnimationFrameAfterAck.count === 0, 'Receipt alone must not claim a paint opportunity');
  env.advance(6);
  report = metrics.report();
  check(report.input.inputToNextAnimationFrameAfterAck.meanMs === 16, 'Presentation opportunity must include the next animation-frame delay');
  check(report.input.inputToRelevantPublicStateChange.meanMs === 10, 'Selection feedback should correlate to an actual public-state change');
  check(JSON.parse(env.elements.find(node => node.id === 'quality-state').textContent).selected === 'alpha', 'DOM-only QA must receive the latest public state without accessing runtime globals');
  check(env.elements.every(node => node.type === 'application/json'), 'QA DOM records must be inert data, not executable scripts');
  check(report.input.recent[0].inputToNextBridgeMs === 10 && report.input.recent[0].inputToNextAnimationFrameMs === 16, 'The report must not conflate transport and presentation timing');
  metrics.noteState(state({ quality: { ack_tokens: [token] } }));
  check(metrics.report().input.duplicateAcks === 1 && metrics.report().input.renderAcknowledged === 1, 'Repeated acknowledgements must not duplicate latency samples');
  const copy = env.win.BreachQuality.latestState; copy.units[0].id = 'changed';
  check(env.win.BreachQuality.latestState.units[0].id === 'alpha', 'Read-only public snapshots must not expose mutable game references');
  check(Object.isFrozen(env.win.BreachQuality), 'Public observer API should be read-only');
  env.advance(5000);
  check(JSON.parse(env.elements.find(node => node.id === 'quality-report').textContent).input.renderAcknowledged === 1, 'The periodic DOM report must include the latest acknowledgement summary');
  metrics.dispose();
  check(env.callbacks.size === 0 && env.win.BreachQuality === undefined, 'Disposal must remove sampling callbacks and the observer API');
  check(env.elements.length === 0, 'Disposal must remove both observer DOM data nodes');
  env.input(); check(env.callbacks.size === 0, 'Disposal must remove input listeners');
}
{
  const env = environment(); const metrics = createQualityMetrics({ window: env.win });
  metrics.noteState(state({ mode: 'MENU' }));
  env.input(); const startToken = metrics.trackIntent({ action: 'start', id: 'M01' });
  env.advance(250, false);
  metrics.noteState(state({ quality: { ack_tokens: [startToken] } }));
  env.advance(8);
  env.input(); const selectToken = metrics.trackIntent({ action: 'select', id: 'alpha' });
  env.advance(10, false);
  metrics.noteState(state({ selected: 'alpha', quality: { ack_tokens: [selectToken] } }));
  env.advance(8);
  env.input(); const moveToken = env.win.BreachQuality.latestInputToken;
  env.advance(10, false);
  metrics.noteState(state({ selected: 'alpha', units: [{ id: 'alpha', commands: [{ id: 'cmd-1', type: 'MOVE', args: { x: 4, y: 6 } }] }, { id: 'bravo', commands: [] }], quality: { ack_tokens: [moveToken] } }));
  env.advance(8);
  const report = metrics.report().input;
  check(report.inputToNextAnimationFrameAfterAck.count === 3 && report.inputToNextAnimationFrameAfterAck.p95Ms === 258, 'The legacy aggregate must retain startup and gameplay measurements');
  check(report.byAction.start.inputToNextAnimationFrameAfterAck.p95Ms === 258 && report.byAction.select.inputToNextAnimationFrameAfterAck.p95Ms === 18, 'Action summaries must expose startup separately from selection');
  check(report.byAction['command:MOVE'].inputToNextAnimationFrameAfterAck.count === 1, 'An acknowledged native canvas queue insertion must be classified by the new command type');
  check(report.selectionAndPlanningResponse.inputToNextAnimationFrameAfterAck.count === 2 && report.selectionAndPlanningResponse.inputToNextAnimationFrameAfterAck.p95Ms === 18, 'Selection/planning p95 must exclude the slow mission-start sample');
  check(report.sceneTransitionResponse.inputToNextAnimationFrameAfterAck.count === 1 && report.sceneTransitionResponse.inputToNextAnimationFrameAfterAck.p95Ms === 258, 'Scene-transition samples must be retained in their own population');
  check(report.recent.map(sample => sample.action).join(',') === 'start,select,command:MOVE', 'Recent evidence must preserve resolved action labels for independent analysis');
  metrics.dispose();
}
{
  const env = environment(); const metrics = createQualityMetrics({ window: env.win });
  metrics.noteState(state());
  env.advance(100, false); env.input();
  const token = metrics.trackIntent({ action: 'select', id: 'alpha' });
  env.advance(17.9, false);
  metrics.noteState(state({ selected: 'alpha', quality: { ack_tokens: [token] } }));
  // Some rAF callbacks share a frame timestamp older than a prior Godot ACK.
  // Actual callback execution is later and must be timed with performance.now.
  env.advance(2.1, true, 113.1);
  const input = metrics.report().input, sample = input.recent[0];
  check(sample.inputToNextAnimationFrameMs === 20, 'Presentation opportunity must use callback execution time, not the stale shared frame timestamp');
  check(sample.inputToNextAnimationFrameMs >= sample.inputToRenderAckMs, 'Presentation opportunity cannot precede its triggering render acknowledgement');
  check(input.byAction.select.inputToNextAnimationFrameAfterAck.p95Ms === 20 && input.selectionAndPlanningResponse.inputToNextAnimationFrameAfterAck.p95Ms === 20, 'Per-action and selection/planning summaries must use the corrected callback clock');
  metrics.dispose();
}
{
  const env = environment(); const metrics = createQualityMetrics({ window: env.win });
  metrics.noteState(state()); env.input(); env.advance(10, false);
  // A periodic state message or another input's update is not evidence that this input worked.
  metrics.noteState(state({ selected: 'alpha', time: .1 }));
  check(metrics.report().input.bridgeObserved === 1, 'Periodic bridge observations may be measured');
  check(metrics.report().input.relevantStateChanged === 0, 'An unacknowledged input must not inherit an unrelated UI change');
  env.advance(2100);
  check(metrics.report().input.expiredInputs === 1, 'Unacknowledged inputs must expire rather than creating later false correlations');
  env.input('keydown', { isTrusted: false });
  check(metrics.report().input.syntheticInputsExcluded === 1, 'Programmatically dispatched input must not be reported as human input');
  env.input('keydown', { repeat: true });
  check(metrics.report().input.trustedInputs === 1, 'Held-key repeat must not inflate independent input samples');
  metrics.dispose();
}
{
  const env = environment(); const metrics = createQualityMetrics({ window: env.win });
  metrics.noteState(state({ mode: 'EXECUTING' }));
  for (let i = 0; i < 91; i++) env.advance(20);
  let group = metrics.report().frameGroups.find(group => group.mode === 'EXECUTING');
  check(group.warmupSkipped === 30 && group.count === 60, 'Frame group must exclude thirty initial callback intervals');
  check(group.meanMs === 20 && group.p95Ms === 20 && group.averageFps === 50, 'Mean FPS must be elapsed time divided into frames, with independently computed p95');
  check(group.sampleMeetsFrameBudget === false && group.durationRequirementMet === false, 'A short slow sample must not satisfy the ten-minute target');
  metrics.noteState(state({ mode: 'LAB' }));
  for (let i = 0; i < 40; i++) env.advance(16);
  const groups = metrics.report().frameGroups;
  check(groups.some(group => group.scope === 'synthetic-presentation') && groups.some(group => group.scope === 'authored-mission'), 'Synthetic presentation and real mission samples must remain separate');
  const before = groups.reduce((sum, group) => sum + group.count, 0);
  env.doc.hidden = true; env.doc.emit('visibilitychange'); env.advance(20_000);
  env.doc.hidden = false; env.doc.emit('visibilitychange'); env.advance(16);
  check(metrics.report().frameGroups.reduce((sum, group) => sum + group.count, 0) === before, 'A hidden-tab gap must not become an enormous rendered-frame sample');
  check(metrics.report().hiddenGaps === 1, 'The report should disclose excluded hidden periods');
  metrics.dispose();
}
{
  const env = environment(); const originalError = env.win.console.error;
  env.resources.push({ entryType: 'resource', name: 'http://local.test/engine.wasm?token=secret', startTime: 1, duration: 4, transferSize: 20, encodedBodySize: 12, decodedBodySize: 40, responseStatus: 200 });
  const metrics = createQualityMetrics({ window: env.win });
  metrics.noteState(state({ quality: { render_nodes: 50, render_entities: 2, active_effects: 1 } }));
  env.nodes(21); env.win.performance.memory.usedJSHeapSize = 1100; metrics.checkpoint('after-restart');
  env.win.console.error('a test error'); env.win.console.warn('SCRIPT ERROR: test');
  env.win.emit('unhandledrejection', { reason: new Error('test rejection') });
  env.win.emit('error', { target: { src: 'http://local.test/missing.glb' } });
  env.resources.push({ entryType: 'resource', name: 'http://local.test/fail.wav', startTime: 2, duration: 8, transferSize: 0, responseStatus: 404 });
  let report = metrics.report(); metrics.report();
  check(report.resources.count === 2 && metrics.report().resources.count === 2, 'Buffered resources must be deduplicated across report reads');
  check(report.resources.observedTransferBytes === 20 && report.resources.zeroTransferEntries === 1, 'Unknown/cache-zero resource bytes must remain explicit');
  check(report.resources.failures.length === 2, 'Resource element and HTTP-status failures should both be recorded');
  check(!JSON.stringify(report).includes('token=secret'), 'Resource query strings should not be retained');
  check(report.errors.observedErrorEvents === 3 && report.errors.observedWarnings === 1, 'Runtime, engine console and rejection observations must be counted');
  const last = report.lifecycle.at(-1);
  check(last.domElementCount === 23 && last.jsHeapUsedBytes === 1100 && last.engineNodeCount === 50, 'Lifecycle observations must record their distinct memory/node proxies including its two stable data nodes');
  check(report.interpretation.some(note => note.includes('not total process memory')), 'Proxy measurements must not be mislabeled as total memory');
  metrics.dispose(); check(env.win.console.error === originalError, 'Disposal must restore original logging');
}

const result = { kind: 'deterministic-observer-contract-tests', checks, failures: 0, browserPerformanceClaim: false, testedAt: new Date().toISOString() };
await mkdir('tests/artifacts/play-quality', { recursive: true });
await writeFile('tests/artifacts/play-quality/metrics-contract.json', JSON.stringify(result, null, 2));
console.log(`BREACH_QUALITY_METRICS_RESULT checks=${checks} failures=0`);
