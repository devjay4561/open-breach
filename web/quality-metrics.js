/** Opt-in, local-only observation. This module never changes game state or sends data. */
const MAX_SAMPLES = 120_000;
const MAX_PENDING = 256;
const INPUT_TIMEOUT_MS = 2_000;
const AUTOMATIC_ACTIONS = new Set(['settings', 'input_focus', 'preview', 'get_plan', 'export_replay']);
const SCENE_TRANSITIONS = new Set(['start', 'retry', 'load_plan', 'import_replay', 'preview', 'menu', 'lab']);
const EMPTY = Object.freeze({ enabled: false, trackIntent: () => null, noteState() {}, recordError() {}, checkpoint() {}, report: () => ({ enabled: false }), dispose() {} });

function clone(value) {
  if (value === undefined) return undefined;
  return typeof structuredClone === 'function' ? structuredClone(value) : JSON.parse(JSON.stringify(value));
}
function finite(value) { return typeof value === 'number' && Number.isFinite(value); }
const ROOM_DOCTRINE_METRICS = Object.freeze(['stealth', 'doorway_dwell', 'time_to_dominate', 'threat_order_violations', 'identification', 'control', 'marked', 'rear_hits']);
const doctrineNumber = value => finite(value) && value >= 0;
const doctrineCount = value => doctrineNumber(value) && Number.isSafeInteger(value);
const doctrineObject = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const doctrineId = value => typeof value === 'string' && /^[A-Za-z][A-Za-z0-9_-]{0,63}$/.test(value);

/** Pure feedback grades for observed room measurements. These thresholds are
 * game feedback, not numerical thresholds quoted from the doctrine. The caller
 * controls which rooms are observed; this function reads no world or QA state. */
export function gradeRoomDoctrine(roomMetrics = {}) {
  const source = doctrineObject(roomMetrics) ? roomMetrics : {};
  return ROOM_DOCTRINE_METRICS.map(id => {
    const raw = doctrineObject(source[id]) ? source[id] : {};
    const tick = doctrineCount(raw.tick) ? raw.tick : null;
    const row = { id, grade: 'na', value: doctrineNumber(raw.value) ? raw.value : null,
      tick, time: doctrineNumber(raw.time) ? raw.time : null,
      replay_time: tick === null ? null : tick * (1 / 30) };
    for (const key of ['unit_id', 'door_id']) if (doctrineId(raw[key])) row[key] = raw[key];
    if (id === 'identification') {
      const details = {};
      if (doctrineNumber(raw.civilian_damage)) details.civilian_damage = raw.civilian_damage;
      if (doctrineCount(raw.unlawful_shots)) details.unlawful_shots = raw.unlawful_shots;
      row.details = details;
      // Unknown civilian damage cannot be treated as an observed zero.
      if (![0, 1].includes(row.value) || !Object.hasOwn(details, 'civilian_damage') || !Object.hasOwn(details, 'unlawful_shots')) { row.value = null; return row; }
      row.value = details.civilian_damage > 0 || details.unlawful_shots > 0 ? 1 : 0;
      row.grade = row.value === 0 ? 'good' : 'fail';
      return row;
    }
    if (id === 'control') {
      const details = {};
      for (const key of ['arrested', 'surrendered', 'secured', 'civilians']) if (doctrineCount(raw[key])) details[key] = raw[key];
      row.details = details;
      if (row.value === null || row.value > 1 || Object.keys(details).length !== 4 || details.arrested > details.surrendered || details.secured > details.civilians) { row.value = null; return row; }
      const denominator = details.surrendered + details.civilians;
      const numerator = details.arrested + details.secured;
      if (!Number.isSafeInteger(denominator) || !Number.isSafeInteger(numerator) || denominator === 0) { row.value = null; return row; }
      row.value = numerator / denominator;
      details.arrest_rate = details.surrendered > 0 ? details.arrested / details.surrendered : null;
      details.secure_rate = details.civilians > 0 ? details.secured / details.civilians : null;
      row.grade = row.value === 1 ? 'good' : row.value > 0 ? 'caution' : 'fail';
      return row;
    }
    if (row.value === null) return row;
    switch (id) {
      case 'stealth':
        if (Number.isInteger(row.value) && row.value <= 2) row.grade = ['good', 'caution', 'fail'][row.value];
        else row.value = null;
        break;
      case 'doorway_dwell': row.grade = row.value <= .75 ? 'good' : row.value <= 1.5 ? 'caution' : 'fail'; break;
      case 'time_to_dominate': row.grade = row.value <= 3 ? 'good' : row.value <= 5 ? 'caution' : 'fail'; break;
      case 'threat_order_violations': case 'rear_hits': row.grade = row.value === 0 ? 'good' : 'fail'; break;
      case 'marked': if (row.value === 0 || row.value === 1) row.grade = row.value === 1 ? 'good' : 'fail'; else row.value = null; break;
    }
    return row;
  });
}
function text(value) { try { return String(value?.message ?? value ?? '').slice(0, 700); } catch { return '[unprintable]'; } }
function percentile(values, p) {
  if (!values.length) return null;
  const sorted = values.slice().sort((a, b) => a - b);
  return sorted[Math.max(0, Math.ceil(sorted.length * p) - 1)];
}
class Series {
  constructor(capacity = MAX_SAMPLES) { this.capacity = capacity; this.values = []; this.count = 0; this.sum = 0; this.max = 0; }
  add(value) {
    if (!finite(value) || value < 0) return;
    this.values[this.count % this.capacity] = value;
    this.count++; this.sum += value; this.max = Math.max(this.max, value);
  }
  summary() {
    return { count: this.count, retainedSamples: this.values.length, totalMs: this.sum,
      meanMs: this.count ? this.sum / this.count : null, p50Ms: percentile(this.values, .5),
      p95Ms: percentile(this.values, .95), maxMs: this.count ? this.max : null,
      percentileWindow: this.count > this.capacity ? 'most recent retained samples' : 'all samples' };
  }
}
function queueKey(state) {
  return JSON.stringify((state?.units || []).map(unit => [unit.id, (unit.commands || []).map(command => [command.id, command.type, command.args])]));
}
function signatures(state = {}) {
  return { selected: state.selected ?? '', tool: state.tool ?? '', mode: state.mode ?? 'BOOT',
    mission: state.mission ?? '', queue: queueKey(state),
    replayTime: state.replay?.time, replaySpeed: state.replay?.speed, replayPlaying: state.replay?.playing,
    replayReveal: state.replay?.reveal, replayFollow: state.replay?.follow };
}
function changedForInput(pending, state) {
  const now = signatures(state), before = pending.before, intent = pending.intent;
  if (!intent) return now.selected !== before.selected || now.queue !== before.queue || now.tool !== before.tool || now.mode !== before.mode;
  switch (intent.action) {
    case 'select': return now.selected === intent.id && now.selected !== before.selected;
    case 'tool': return now.tool === intent.tool && now.tool !== before.tool;
    case 'command': case 'clear': case 'remove': case 'reorder': return now.queue !== before.queue;
    case 'start': case 'retry': case 'load_plan': return now.mission !== before.mission || now.mode !== before.mode || now.queue !== before.queue;
    case 'toggle': case 'pause': case 'menu': case 'replay': return now.mode !== before.mode;
    case 'replay_seek': return finite(now.replayTime) && Math.abs(now.replayTime - Number(intent.time)) < .12 && now.replayTime !== before.replayTime;
    case 'replay_toggle': return now.replayPlaying !== before.replayPlaying;
    case 'replay_speed': return now.replaySpeed !== before.replaySpeed;
    case 'replay_reveal': return now.replayReveal !== before.replayReveal;
    case 'replay_follow': return now.replayFollow !== before.replayFollow;
    default: return false;
  }
}
function bucketFor(state = {}) {
  const mode = String(state.mode || 'BOOT').slice(0, 30);
  const mission = String(state.mission || '').slice(0, 30);
  const scope = mode === 'LAB' ? 'synthetic-presentation' : ['PLANNING', 'EXECUTING', 'RESULT', 'REPLAY'].includes(mode) ? 'authored-mission' : 'shell';
  return { key: `${scope}:${mission}:${mode}`, scope, mission, mode };
}
function actionForInput(record, state) {
  if (record.intent) return record.intent.action === 'command' ? `command:${record.intent.commandType || 'unknown'}` : record.intent.action;
  const after = signatures(state), before = record.before;
  if (after.selected !== before.selected) return 'select';
  if (after.queue !== before.queue) {
    const ids = new Set(JSON.parse(before.queue).flatMap(unit => unit[1].map(command => command[0])));
    const added = (state.units || []).flatMap(unit => unit.commands || []).filter(command => !ids.has(command.id));
    return added.length ? `command:${added.at(-1).type || 'unknown'}` : 'queue-edit';
  }
  if (after.tool !== before.tool) return 'tool';
  if (after.mode !== before.mode) return after.mode === 'MENU' ? 'menu' : 'toggle';
  if (record.event === 'wheel' || ['KeyW', 'KeyA', 'KeyS', 'KeyD'].includes(record.key)) return 'camera';
  return 'canvas-or-keyboard-no-state-change';
}
function isPlanningResponse(action) {
  return action === 'select' || action === 'tool' || action === 'queue-edit' || ['clear', 'remove', 'reorder'].includes(action) || action.startsWith('command:');
}
function responseSeries() { return { bridge: new Series(20_000), ack: new Series(20_000), paint: new Series(20_000), relevant: new Series(20_000) }; }
function summarizeResponse(series) {
  return { inputToNextBridgeState: series.bridge.summary(), inputToRenderAcknowledgement: series.ack.summary(),
    inputToNextAnimationFrameAfterAck: series.paint.summary(), inputToRelevantPublicStateChange: series.relevant.summary() };
}

export function createQualityMetrics(options = {}) {
  const win = options.window ?? globalThis.window;
  const doc = options.document ?? win?.document;
  const perf = options.performance ?? win?.performance;
  const enabled = options.enabled ?? (win && new URLSearchParams(win.location.search).get('qa') === '1');
  if (!enabled || !win || !doc || !perf || typeof win.requestAnimationFrame !== 'function') return EMPTY;
  const now = () => perf.now();
  const startedAt = now();
  let disposed = false, serial = 0, latestInput = null, latestState = null, lastFrame = null, frameRequest;
  let readyAt = null, totalErrors = 0, totalWarnings = 0, droppedInputs = 0, expiredInputs = 0;
  let lastLifecycleAt = -Infinity, lastLifecycleKey = '', hiddenGaps = 0;
  let lastDomReportAt = -Infinity;
  const makeDataNode = id => {
    if (!doc.createElement || !doc.body?.append) return null;
    const node = doc.createElement('script'); node.type = 'application/json'; node.id = id;
    doc.body.append(node); return node;
  };
  const stateNode = makeDataNode('quality-state'), reportNode = makeDataNode('quality-report');
  const pending = new Map(), buckets = new Map(), resources = new Map(), failures = new Map();
  const errors = [], lifecycle = [], listeners = [], observers = [], paintRequests = new Set();
  const inputToBridge = new Series(20_000), inputToRenderAck = new Series(20_000), inputToPaintProxy = new Series(20_000), inputToRelevantState = new Series(20_000);
  const recentInputs = [], longTasks = new Series(10_000);
  const byAction = new Map(), planningResponse = responseSeries(), sceneTransitionResponse = responseSeries();
  const counters = { trustedInputs: 0, syntheticInputsExcluded: 0, intents: 0, bridgeObserved: 0, renderAcknowledged: 0, relevantStateChanged: 0, duplicateAcks: 0, unknownAcks: 0 };
  const ackedTokens = new Set();
  const consoleObject = win.console;
  const originalError = consoleObject?.error, originalWarn = consoleObject?.warn;
  const on = (target, event, listener, capture = false) => { target.addEventListener(event, listener, capture); listeners.push(() => target.removeEventListener(event, listener, capture)); };
  const publicPath = value => { try { const parsed = new URL(value, win.location.href); return `${parsed.origin === win.location.origin ? '' : parsed.origin}${parsed.pathname}`; } catch { return text(value).split('?')[0]; } };

  function recordError(error, source = 'application') {
    if (disposed) return;
    totalErrors++;
    if (errors.length === 64) errors.shift();
    errors.push({ atMs: now() - startedAt, source: text(source), message: text(error) });
  }
  function resourceFailure(url, status = null, source = 'resource-error') {
    const key = `${publicPath(url)}:${status}:${source}`;
    if (!failures.has(key)) failures.set(key, { path: publicPath(url), status, source });
  }
  function recordResource(entry) {
    if (!entry || entry.entryType !== 'resource') return;
    const key = `${entry.name}:${entry.startTime}:${entry.duration}`;
    if (resources.has(key) || resources.size >= 2048) return;
    const status = finite(entry.responseStatus) ? entry.responseStatus : null;
    resources.set(key, { path: publicPath(entry.name), initiator: text(entry.initiatorType), startMs: entry.startTime,
      durationMs: entry.duration, transferBytes: finite(entry.transferSize) ? entry.transferSize : null,
      encodedBytes: finite(entry.encodedBodySize) ? entry.encodedBodySize : null,
      decodedBytes: finite(entry.decodedBodySize) ? entry.decodedBodySize : null, status });
    if (status >= 400) resourceFailure(entry.name, status, 'resource-timing-http');
  }
  function collectResources() { for (const entry of perf.getEntriesByType?.('resource') || []) recordResource(entry); }
  function checkpoint(label = 'manual') {
    if (disposed) return;
    const state = latestState || {}, quality = state.quality || {};
    const count = group => Array.isArray(state[group]) ? state[group].length : 0;
    const sample = { label: text(label), atMs: now() - startedAt, ...bucketFor(state), simulationSeconds: finite(state.time) ? state.time : null,
      domElementCount: doc.querySelectorAll?.('*').length ?? null,
      jsHeapUsedBytes: finite(perf.memory?.usedJSHeapSize) ? perf.memory.usedJSHeapSize : null,
      jsHeapTotalBytes: finite(perf.memory?.totalJSHeapSize) ? perf.memory.totalJSHeapSize : null,
      publicEntityRecords: count('units') + count('enemies') + count('civilians'),
      visibleActorRecords: count('units') + (state.enemies || []).filter(item => item.visible === true).length + (state.civilians || []).filter(item => item.visible === true || item.secured === true).length,
      publicCommandRecords: (state.units || []).reduce((sum, unit) => sum + (unit.commands?.length || 0), 0),
      publicEventRecords: state.events?.length || 0,
      engineNodeCount: finite(quality.render_nodes) ? quality.render_nodes : null,
      rendererEntityCount: finite(quality.render_entities) ? quality.render_entities : null,
      activeEffectCount: finite(quality.active_effects) ? quality.active_effects : null };
    if (lifecycle.length === 256) lifecycle.shift();
    lifecycle.push(sample); lastLifecycleAt = now();
  }
  function captureInput(event) {
    if (disposed || doc.hidden || event.repeat || (event.type === 'keydown' && ['Shift', 'Control', 'Alt', 'Meta'].includes(event.key))) return;
    if (!event.isTrusted) { counters.syntheticInputsExcluded++; return; }
    if (event.type === 'wheel' && latestInput && now() - latestInput.at < 80) return;
    const at = finite(event.timeStamp) && event.timeStamp >= 0 && event.timeStamp <= now() && now() - event.timeStamp < 60_000 ? event.timeStamp : now();
    const token = `qa-${++serial}`;
    const record = { token, at, before: signatures(latestState), event: event.type, key: text(event.code || ''), target: text(event.target?.id || event.target?.tagName || ''), intent: null, bridgeAt: null, ackAt: null, relevantAt: null };
    if (pending.size >= MAX_PENDING) { pending.delete(pending.keys().next().value); droppedInputs++; }
    pending.set(token, record); latestInput = record; counters.trustedInputs++;
  }
  function trackIntent(data) {
    if (disposed || !data || AUTOMATIC_ACTIONS.has(data.action) || !latestInput || now() - latestInput.at > 600 || !pending.has(latestInput.token)) return null;
    if (!latestInput.intent) counters.intents++;
    // Retain only the small attributes needed to recognize public UI changes.
    latestInput.intent = { action: text(data.action), commandType: text(data.type || ''), id: text(data.id || ''), tool: text(data.tool || ''), time: finite(data.time) ? data.time : null };
    return latestInput.token;
  }
  function paintAcknowledgement(record) {
    let request;
    request = win.requestAnimationFrame(() => {
      paintRequests.delete(request);
      if (disposed || doc.hidden) return;
      // The rAF argument denotes the frame's shared timeline timestamp, not
      // this callback's execution time. Godot may acknowledge later within that
      // same frame, so compare actual callback time on the same clock as ACK.
      const callbackAt = now();
      inputToPaintProxy.add(callbackAt - record.at);
      record.actionSeries.paint.add(callbackAt - record.at);
      if (record.groupSeries) record.groupSeries.paint.add(callbackAt - record.at);
      if (recentInputs.length === 64) recentInputs.shift();
      recentInputs.push({ token: record.token, event: record.event, action: record.action,
        inputToNextBridgeMs: record.bridgeAt === null ? null : record.bridgeAt - record.at,
        inputToRenderAckMs: record.ackAt - record.at, inputToNextAnimationFrameMs: callbackAt - record.at,
        inputToRelevantStateChangeMs: record.relevantAt === null ? null : record.relevantAt - record.at });
    });
    paintRequests.add(request);
  }
  function noteState(message) {
    if (disposed || !message || typeof message !== 'object') return;
    if (message.type === 'ready' && readyAt === null) readyAt = now();
    if (message.type !== 'state' && message.type !== 'visual_ack') return;
    const at = now();
    if (message.type === 'state') {
      latestState = message;
      if (stateNode) stateNode.textContent = JSON.stringify(message);
    }
    const currentAcks = new Set(message.quality?.ack_tokens || []);
    for (const record of pending.values()) {
      if (at - record.at > INPUT_TIMEOUT_MS) continue;
      if (record.bridgeAt === null) { record.bridgeAt = at; inputToBridge.add(at - record.at); counters.bridgeObserved++; }
      if (message.type === 'state' && currentAcks.has(record.token) && record.relevantAt === null && changedForInput(record, message)) {
        record.relevantAt = at; inputToRelevantState.add(at - record.at); counters.relevantStateChanged++;
      }
    }
    for (const token of message.quality?.ack_tokens || []) {
      if (typeof token !== 'string') continue;
      if (ackedTokens.has(token)) { counters.duplicateAcks++; continue; }
      const record = pending.get(token);
      if (!record || at - record.at > INPUT_TIMEOUT_MS) { counters.unknownAcks++; continue; }
      record.ackAt = at; inputToRenderAck.add(at - record.at); counters.renderAcknowledged++;
      record.action = actionForInput(record, latestState || {});
      if (!byAction.has(record.action)) byAction.set(record.action, responseSeries());
      record.actionSeries = byAction.get(record.action);
      record.groupSeries = isPlanningResponse(record.action) ? planningResponse : SCENE_TRANSITIONS.has(record.action) ? sceneTransitionResponse : null;
      for (const series of [record.actionSeries, record.groupSeries].filter(Boolean)) {
        if (record.bridgeAt !== null) series.bridge.add(record.bridgeAt - record.at);
        series.ack.add(at - record.at);
        if (record.relevantAt !== null) series.relevant.add(record.relevantAt - record.at);
      }
      ackedTokens.add(token); if (ackedTokens.size > 1024) ackedTokens.delete(ackedTokens.values().next().value);
      pending.delete(token); paintAcknowledgement(record);
    }
    const lifecycleKey = `${message.mission}:${message.mode}`;
    if (message.type === 'state' && lifecycleKey !== lastLifecycleKey) { checkpoint('mode-transition'); lastLifecycleKey = lifecycleKey; }
  }
  function frame(timestamp) {
    if (disposed) return;
    if (!doc.hidden) {
      if (lastFrame !== null && timestamp > lastFrame) {
        const description = bucketFor(latestState || {});
        if (!buckets.has(description.key)) buckets.set(description.key, { ...description, warmupSkipped: 0, frames: new Series() });
        const bucket = buckets.get(description.key);
        if (bucket.warmupSkipped < 30) bucket.warmupSkipped++;
        else bucket.frames.add(timestamp - lastFrame);
      }
      lastFrame = timestamp;
      for (const [token, record] of pending) if (timestamp - record.at > INPUT_TIMEOUT_MS) { pending.delete(token); expiredInputs++; }
      if (timestamp - lastLifecycleAt >= 5_000) checkpoint('five-second-sample');
      if (reportNode && timestamp - lastDomReportAt >= 5_000) { reportNode.textContent = JSON.stringify(report()); lastDomReportAt = timestamp; }
    } else lastFrame = null;
    frameRequest = win.requestAnimationFrame(frame);
  }
  function report() {
    collectResources();
    const frameReports = [...buckets.values()].map(bucket => {
      const summary = bucket.frames.summary();
      return { key: bucket.key, scope: bucket.scope, mission: bucket.mission, mode: bucket.mode, warmupSkipped: bucket.warmupSkipped, ...summary,
        averageFps: summary.meanMs > 0 ? 1000 / summary.meanMs : null,
        requiredDurationMs: bucket.scope === 'synthetic-presentation' ? 30_000 : bucket.mode === 'EXECUTING' ? 600_000 : null,
        sampleMeetsFrameBudget: summary.count > 0 ? 1000 / summary.meanMs >= 55 && summary.p95Ms <= 25 : null,
        durationRequirementMet: bucket.scope === 'synthetic-presentation' ? summary.totalMs >= 30_000 : bucket.mode === 'EXECUTING' ? summary.totalMs >= 600_000 : null };
    });
    const resourceList = [...resources.values()];
    return { enabled: true, schemaVersion: 1, buildId: text(options.buildId || 'unspecified'), buildHash: options.buildHash || null,
      generatedAt: new Date().toISOString(), elapsedMs: now() - startedAt,
      environment: { userAgent: text(win.navigator?.userAgent), viewport: { width: win.innerWidth, height: win.innerHeight }, devicePixelRatio: win.devicePixelRatio || 1, visibility: doc.hidden ? 'hidden' : 'visible' },
      readyMs: readyAt === null ? null : readyAt - startedAt, navigationToReadyMs: readyAt, frameGroups: frameReports,
      input: { ...counters, droppedInputs, expiredInputs, pendingInputs: pending.size,
        inputToNextBridgeState: inputToBridge.summary(), inputToRenderAcknowledgement: inputToRenderAck.summary(),
        inputToNextAnimationFrameAfterAck: inputToPaintProxy.summary(), inputToRelevantPublicStateChange: inputToRelevantState.summary(), recent: clone(recentInputs),
        byAction: Object.fromEntries([...byAction].map(([action, series]) => [action, summarizeResponse(series)])),
        selectionAndPlanningResponse: { ...summarizeResponse(planningResponse), includes: 'selection, tool changes, command registration and queue edits; not command execution duration', targetP95Ms: 100 },
        sceneTransitionResponse: { ...summarizeResponse(sceneTransitionResponse), includes: [...SCENE_TRANSITIONS] } },
      resources: { count: resources.size, observedTransferBytes: resourceList.reduce((sum, resource) => sum + (resource.transferBytes || 0), 0),
        zeroTransferEntries: resourceList.filter(resource => !resource.transferBytes).length, failures: clone([...failures.values()]), entries: clone(resourceList) },
      errors: { observedErrorEvents: totalErrors, observedWarnings: totalWarnings, recent: clone(errors) },
      hiddenGaps, longTasks: longTasks.summary(), lifecycle: clone(lifecycle),
      limits: { maxFrameSamplesPerGroup: MAX_SAMPLES, maxPendingInputs: MAX_PENDING, inputExpiryMs: INPUT_TIMEOUT_MS, maxLifecycleSamples: 256 },
      interpretation: [
        'Frame intervals are visible-tab requestAnimationFrame cadence, not direct GPU timestamps. Authored missions, replay, shell and synthetic presentation are separate groups.',
        'Input to next bridge message is a transport observation, not proof that the input was accepted. Relevant public-state changes and explicit post-world-display render acknowledgements are separate measures.',
        'The selection/planning response group excludes mission start/retry/import/menu/LAB transitions. Per-action samples require an explicit render acknowledgement; the aggregate also retains unacknowledged bridge observations.',
        'The next animation-frame callback after a render acknowledgement is a presentation opportunity; it does not prove physical display scan-out or GPU completion.',
        'Only trusted DOM input is counted. Automatically sent settings/input-focus/preview messages never consume an input token.',
        'JavaScript heap, DOM counts and public/renderer entity counts are lifecycle proxies, not total process memory or a leak diagnosis. Compare the same warmed checkpoint before and after repetition.',
        'ResourceTiming may report zero bytes for cache or unavailable timing data, and cannot establish every fetch failure. Error and resource-failure observations can overlap.',
        'A short sample meeting a budget does not meet the ten-minute authored-mission or thirty-second synthetic-load duration requirement. Human play quality remains separately assessed.',
      ] };
  }
  function dispose() {
    if (disposed) return;
    disposed = true; win.cancelAnimationFrame(frameRequest);
    for (const request of paintRequests) win.cancelAnimationFrame(request);
    for (const remove of listeners) remove();
    for (const observer of observers) observer.disconnect();
    stateNode?.remove(); reportNode?.remove();
    if (consoleObject?.error === wrappedError) consoleObject.error = originalError;
    if (consoleObject?.warn === wrappedWarn) consoleObject.warn = originalWarn;
    if (win.BreachQuality === publicApi) delete win.BreachQuality;
  }
  function wrappedError(...args) { recordError(args.map(text).join(' '), 'console.error'); return originalError?.apply(consoleObject, args); }
  function wrappedWarn(...args) { totalWarnings++; if (/SCRIPT ERROR|^ERROR:|Parse Error/.test(args.map(text).join(' '))) recordError(args.map(text).join(' '), 'engine-console'); return originalWarn?.apply(consoleObject, args); }
  for (const name of ['pointerdown', 'keydown', 'input', 'wheel']) on(doc, name, captureInput, true);
  on(doc, 'visibilitychange', () => { lastFrame = null; if (doc.hidden) { hiddenGaps++; pending.clear(); latestInput = null; } checkpoint('visibility-change'); });
  on(win, 'error', event => {
    const source = event.target?.src || event.target?.href;
    if (source && event.target !== win) resourceFailure(source);
    else recordError(event.error || event.message, 'window.error');
  }, true);
  on(win, 'unhandledrejection', event => recordError(event.reason, 'unhandledrejection'));
  if (consoleObject) { consoleObject.error = wrappedError; consoleObject.warn = wrappedWarn; }
  const Observer = options.PerformanceObserver ?? win.PerformanceObserver;
  if (Observer) for (const type of ['resource', 'longtask']) {
    try {
      const observer = new Observer(list => { for (const entry of list.getEntries()) type === 'resource' ? recordResource(entry) : longTasks.add(entry.duration); });
      observer.observe({ type, buffered: true }); observers.push(observer);
    } catch { /* Unsupported observation remains unmeasured, not an error. */ }
  }
  const publicApi = Object.freeze({ enabled: true, report,
    get latestInputToken() { return latestInput && now() - latestInput.at <= 600 && pending.has(latestInput.token) ? latestInput.token : null; },
    get latestState() { return clone(latestState); } });
  Object.defineProperty(win, 'BreachQuality', { value: publicApi, configurable: true, writable: false });
  collectResources(); checkpoint('instrumentation-start');
  if (reportNode) { reportNode.textContent = JSON.stringify(report()); lastDomReportAt = now(); }
  frameRequest = win.requestAnimationFrame(frame);
  return Object.freeze({ enabled: true, trackIntent, noteState, recordError, checkpoint, report, dispose });
}
