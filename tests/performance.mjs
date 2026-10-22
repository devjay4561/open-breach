import { chromium } from 'playwright';
import { mkdir, writeFile } from 'node:fs/promises';
import os from 'node:os';

const url = process.env.BREACH_URL || 'http://127.0.0.1:8080';
const report = {
  testedAt: new Date().toISOString(),
  platform: `${os.platform()} ${os.release()} ${os.arch()}`,
  cpu: os.cpus()[0]?.model,
  systemMemoryBytes: os.totalmem(),
  viewport: { width: 1366, height: 768 },
  network: { downloadMbps: 50, uploadMbps: 10, latencyMs: 50, cacheDisabled: true },
  limitations: [
    'Installed Chrome in headless automation on the current shared macOS host; not the PRD Windows/Iris Xe reference laptop.',
    'Frame samples are requestAnimationFrame callback intervals for ten seconds of M01 after thirty warm-up callbacks, not a five-minute GPU render timing trace.',
    'Reported JavaScript heap is not browser tab/process memory or an isolated WebAssembly heap measurement.',
    'Other work on the host can affect timing. These measurements do not certify all target hardware.',
  ],
};
const errors = [];
const browser = await chromium.launch({ channel: process.env.BREACH_CHANNEL || 'chrome', headless: true, args: ['--enable-unsafe-swiftshader'] });
report.browser = browser.version();
const context = await browser.newContext({ viewport: report.viewport });
await context.addInitScript(() => {
  window.__breachPerf = { state: null, readyAt: null, fps: [] };
  let ui;
  Object.defineProperty(window, 'BreachUI', {
    configurable: true, get: () => ui,
    set(value) {
      ui = value;
      if (typeof value?.receive !== 'function') return;
      const original = value.receive;
      value.receive = function (raw) {
        const message = typeof raw === 'string' ? JSON.parse(raw) : raw;
        if (message.type === 'ready') window.__breachPerf.readyAt = performance.now();
        if (message.type === 'state') {
          window.__breachPerf.state = message;
          if (window.__breachPerf.collect && Number.isFinite(message.fps)) window.__breachPerf.fps.push(message.fps);
        }
        return original.apply(this, arguments);
      };
    },
  });
});
const page = await context.newPage();
page.on('pageerror', error => errors.push(error.message));
page.on('console', message => {
  if (message.type() === 'error' || /SCRIPT ERROR|^ERROR:|Parse Error/.test(message.text())) errors.push(message.text());
});
const cdp = await context.newCDPSession(page);
await cdp.send('Network.enable');
await cdp.send('Network.setCacheDisabled', { cacheDisabled: true });
await cdp.send('Network.emulateNetworkConditions', {
  offline: false, latency: 50, downloadThroughput: 50_000_000 / 8,
  uploadThroughput: 10_000_000 / 8, connectionType: 'wifi',
});
await cdp.send('Performance.enable');
let transferBytes = 0;
cdp.on('Network.loadingFinished', event => { transferBytes += event.encodedDataLength; });

const percentile = (values, percentileValue) => {
  const sorted = [...values].sort((a, b) => a - b);
  return sorted.length ? sorted[Math.ceil(percentileValue * sorted.length) - 1] : null;
};

try {
  await page.goto(url, { waitUntil: 'domcontentloaded' });
  await page.locator('#start-mission').waitFor();
  await page.waitForFunction(() => window.__breachPerf.readyAt !== null && !document.querySelector('#start-mission').disabled, null, { timeout: 120_000 });
  report.firstReadyMs = await page.evaluate(() => window.__breachPerf.readyAt);
  report.initialTransferBytes = transferBytes;
  report.initialResources = await page.evaluate(() => performance.getEntriesByType('resource').map(entry => ({ path: new URL(entry.name).pathname, transferBytes: entry.transferSize, encodedBodyBytes: entry.encodedBodySize, decodedBodyBytes: entry.decodedBodySize, durationMs: entry.duration })));
  await page.locator('[data-mission="M01"]').click();
  await page.locator('#start-mission').click();
  await page.waitForFunction(() => window.__breachPerf.state?.mode === 'PLANNING' && window.__breachPerf.state?.mission === 'M01');
  await page.evaluate(() => {
    const state = window.__breachPerf.state;
    window.BreachBridge.send(JSON.stringify({ action: 'select', id: state.units[0].id }));
    window.BreachBridge.send(JSON.stringify({ action: 'command', type: 'OPEN_DOOR', args: { door_id: state.doors[0].id } }));
  });
  await page.locator('#toggle-execution').click();
  await page.waitForFunction(() => window.__breachPerf.state?.mode === 'EXECUTING');
  const frames = await page.evaluate(() => new Promise(resolve => {
    let previous;
    let warmup = 30;
    let started;
    const intervals = [];
    function sample(now) {
      if (warmup > 0) { warmup--; previous = now; requestAnimationFrame(sample); return; }
      if (started === undefined) { started = now; window.__breachPerf.collect = true; }
      intervals.push(now - previous);
      previous = now;
      if (now - started < 10_000) requestAnimationFrame(sample);
      else { window.__breachPerf.collect = false; resolve({ intervals, elapsedMs: now - started, fps: window.__breachPerf.fps }); }
    }
    requestAnimationFrame(sample);
  }));
  report.frameSample = {
    mission: 'M01', scene: 'Four operatives, six threats and two civilians; front-door opening and automatic engagement',
    samples: frames.intervals.length, elapsedMs: frames.elapsedMs,
    medianMs: percentile(frames.intervals, 0.5), p95Ms: percentile(frames.intervals, 0.95),
    maximumMs: Math.max(...frames.intervals),
    engineFpsMedian: percentile(frames.fps, 0.5), engineFpsMinimum: Math.min(...frames.fps),
  };
  report.runtime = await page.evaluate(() => {
    const gl = document.querySelector('#canvas').getContext('webgl2');
    const debug = gl?.getExtension('WEBGL_debug_renderer_info');
    const module = window.Module || window.Godot;
    return {
      graphicsRenderer: debug ? gl.getParameter(debug.UNMASKED_RENDERER_WEBGL) : null,
      graphicsVendor: debug ? gl.getParameter(debug.UNMASKED_VENDOR_WEBGL) : null,
      jsHeapUsedBytes: performance.memory?.usedJSHeapSize ?? null,
      jsHeapTotalBytes: performance.memory?.totalJSHeapSize ?? null,
      wasmHeapBytes: module?.HEAPU8?.buffer?.byteLength ?? null,
      wasmHeapNote: module?.HEAPU8?.buffer ? 'Exposed runtime heap buffer' : 'The release runtime does not expose its WebAssembly heap; no estimate is claimed.',
      finalMode: window.__breachPerf.state?.mode,
      simulationSeconds: window.__breachPerf.state?.time,
    };
  });
  const metrics = await cdp.send('Performance.getMetrics');
  report.cdpMetrics = Object.fromEntries(metrics.metrics.filter(metric => ['JSHeapUsedSize', 'JSHeapTotalSize', 'Documents', 'Nodes', 'TaskDuration', 'ScriptDuration'].includes(metric.name)).map(metric => [metric.name, metric.value]));
  report.targets = {
    firstReadyUnder12Seconds: report.firstReadyMs <= 12_000,
    compressedTransferUnder30MiB: report.initialTransferBytes <= 30 * 1024 * 1024,
    sampledMedianUnder16Point7Ms: report.frameSample.medianMs <= 16.7,
    sampledP95Under33Point3Ms: report.frameSample.p95Ms <= 33.3,
    note: 'These booleans compare only the stated automated sample; PRD reference-hardware certification remains unverified.',
  };
  report.status = errors.length ? 'runtime-errors' : 'measured';
  if (errors.length) process.exitCode = 1;
} catch (error) {
  report.status = 'failed';
  report.error = error.stack || String(error);
  process.exitCode = 1;
} finally {
  report.errors = errors;
  await mkdir('tests/artifacts/performance', { recursive: true });
  await writeFile('tests/artifacts/performance/chrome-throttled.json', JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report, null, 2));
  await browser.close();
}
