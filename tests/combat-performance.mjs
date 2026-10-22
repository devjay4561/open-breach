import { chromium } from 'playwright';
import assert from 'node:assert/strict';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import os from 'node:os';

// Generate the fixture first:
// Godot --headless --path game --script res://tests/create_combat_benchmark.gd
// BREACH_URL=http://127.0.0.1:8081 BREACH_RECORD=1 node tests/combat-performance.mjs
// The fixture is synthetic render load, never claimed as a completed mission.
const url = process.env.BREACH_URL || 'http://127.0.0.1:8081';
const out = 'tests/artifacts/combat-performance';
const viewport = { width: 1440, height: 900 };
const fixture = JSON.parse(await readFile('tests/artifacts/combat-benchmark.breach-replay.json', 'utf8'));
await mkdir(out, { recursive: true });
const errors = [];
const requestsFailed = [];
const externalRequests = [];
const report = {
  testedAt: new Date().toISOString(), url, viewport,
  platform: `${os.platform()} ${os.release()} ${os.arch()}`,
  cpu: os.cpus()[0]?.model, systemMemoryBytes: os.totalmem(),
  workload: 'Synthetic full-reveal M01 replay, 4 living operatives + 6 living threats + 2 civilians. All ten combatants move, with overlapping firing, hit reactions and periodic rifle reloads.',
  limitations: [
    'This measures browser render workload via ordinary replay import, not AI/combat simulation or a successful mission.',
    'requestAnimationFrame intervals and engine-reported FPS are measured; no GPU timer-query or Windows reference-device certification is claimed.',
    'Current shared macOS host; concurrent work can influence frame times.',
    'The optional preview video is recorded in a separate pass after measurement, so recording overhead does not contaminate performance samples.',
  ],
};
const browser = await chromium.launch({
  channel: process.env.BREACH_CHANNEL || 'chrome',
  headless: process.env.BREACH_HEADLESS !== '0',
  args: ['--enable-unsafe-swiftshader'],
});
report.browser = browser.version();
const context = await browser.newContext({ viewport });
async function observe(ctx) {
  await ctx.addInitScript(() => {
    window.combatPerf = { state: null, fps: [], samples: [], collect: false, messages: [] };
    let ui;
    Object.defineProperty(window, 'BreachUI', {
      configurable: true, get: () => ui,
      set(value) {
        ui = value;
        if (typeof value?.receive !== 'function') return;
        const receive = value.receive;
        value.receive = function(raw) {
          const state = JSON.parse(raw);
          if (state.type === 'state') {
            window.combatPerf.state = state;
            if (window.combatPerf.collect) {
              window.combatPerf.fps.push(state.fps);
              window.combatPerf.samples.push({
                time: state.time, mode: state.mode,
                operatives: state.units.filter(x => x.hp > 0).length,
                visibleThreats: state.enemies.filter(x => x.hp > 0 && x.visible).length,
                moving: [...state.units, ...state.enemies].filter(x => x.status === 'MOVING').length,
                reloading: state.units.filter(x => x.status === 'RELOADING').length,
              });
            }
          } else if (state.type === 'toast') window.combatPerf.messages.push(state);
          return receive.call(value, raw);
        };
      },
    });
  });
}
await observe(context);
const page = await context.newPage();
function trackErrors(target) {
  target.on('pageerror', error => errors.push(error.message));
  target.on('console', message => {
    if (message.type() === 'error' || /SCRIPT ERROR|^ERROR:|Parse Error|Failed loading/.test(message.text())) errors.push(message.text());
  });
  target.on('requestfailed', request => requestsFailed.push({ url: request.url(), reason: request.failure()?.errorText }));
  target.on('request', request => {
    if (/^https?:/.test(request.url()) && new URL(request.url()).origin !== new URL(url).origin) externalRequests.push(request.url());
  });
}
trackErrors(page);
async function loadFixture(target) {
  await target.goto(url, { waitUntil: 'domcontentloaded' });
  await target.waitForFunction(() => window.BreachBridge?.send && !document.querySelector('#start-mission').disabled, null, { timeout: 120_000 });
  await target.evaluate(data => {
    window.BreachBridge.send(JSON.stringify({ action: 'import_replay', data }));
    window.BreachBridge.send(JSON.stringify({ action: 'replay_reveal', value: true }));
  }, fixture);
  await target.waitForFunction(() => {
    const state = window.combatPerf.state;
    return state?.mode === 'REPLAY' && state?.replay?.reveal && state.units.length === 4 && state.enemies.length === 6;
  }, null, { timeout: 15_000 });
  await target.waitForTimeout(1500);
}
const percentile = (values, p) => {
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.max(0, Math.ceil(sorted.length * p) - 1)] ?? null;
};
try {
  await loadFixture(page);
  await page.screenshot({ path: `${out}/ten-combatants.png` });
  report.runtime = await page.evaluate(() => {
    const gl = document.querySelector('#canvas').getContext('webgl2');
    const debug = gl?.getExtension('WEBGL_debug_renderer_info');
    return {
      renderer: debug ? gl.getParameter(debug.UNMASKED_RENDERER_WEBGL) : null,
      vendor: debug ? gl.getParameter(debug.UNMASKED_VENDOR_WEBGL) : null,
      devicePixelRatio,
      canvas: { width: gl?.drawingBufferWidth, height: gl?.drawingBufferHeight },
      userAgent: navigator.userAgent,
    };
  });
  console.log('BENCHMARK_START ten live combatants; 30 seconds; renderer:', report.runtime.renderer);
  const measurements = await page.evaluate(() => new Promise(resolve => {
    const intervals = [];
    let last;
    let started;
    window.combatPerf.collect = true;
    function sample(now) {
      if (last !== undefined) intervals.push(now - last);
      if (started === undefined) started = now;
      last = now;
      if (now - started < 30_000) requestAnimationFrame(sample);
      else {
        window.combatPerf.collect = false;
        resolve({ intervals, elapsedMs: now - started, fps: window.combatPerf.fps, states: window.combatPerf.samples });
      }
    }
    requestAnimationFrame(sample);
  }));
  assert(measurements.states.length > 20, 'The engine must emit samples throughout the measurement');
  assert(measurements.states.every(s => s.mode === 'REPLAY' && s.operatives === 4 && s.visibleThreats === 6), 'Every measured observation must contain all ten living rendered combatants');
  assert(measurements.states.some(s => s.reloading > 0), 'Measurement must include authored rifle reloads');
  const fps = measurements.fps.filter(Number.isFinite);
  report.frameSample = {
    elapsedMs: measurements.elapsedMs, frames: measurements.intervals.length,
    averageFps: measurements.intervals.length * 1000 / measurements.elapsedMs,
    medianMs: percentile(measurements.intervals, 0.5), p95Ms: percentile(measurements.intervals, 0.95),
    p99Ms: percentile(measurements.intervals, 0.99), maximumMs: Math.max(...measurements.intervals),
    engineFpsMedian: percentile(fps, 0.5), engineFpsMinimum: Math.min(...fps),
    engineSamples: measurements.states.length,
    renderedOperativesMinimum: Math.min(...measurements.states.map(s => s.operatives)),
    renderedThreatsMinimum: Math.min(...measurements.states.map(s => s.visibleThreats)),
    movingCombatantsMaximum: Math.max(...measurements.states.map(s => s.moving)),
    reloadObservationCount: measurements.states.filter(s => s.reloading > 0).length,
    simulationRange: [measurements.states[0].time, measurements.states.at(-1).time],
  };
  report.targets = { p95Under25ms: report.frameSample.p95Ms <= 25, averageAtLeast55fps: report.frameSample.averageFps >= 55 };
  await writeFile(`${out}/frame-samples.json`, JSON.stringify(measurements));
  assert.deepEqual(errors, [], 'No browser or engine errors');
  assert.deepEqual(requestsFailed, [], 'No missing runtime files');
  assert.deepEqual(externalRequests, [], 'No external asset dependency');
  report.status = 'measured';
  console.log('BENCHMARK_MEASURED', JSON.stringify(report.frameSample));
  if (process.env.BREACH_RECORD === '1') {
    const videoContext = await browser.newContext({ viewport, recordVideo: { dir: `${out}/raw-video`, size: viewport } });
    await observe(videoContext);
    const videoStart = Date.now();
    const videoPage = await videoContext.newPage();
    trackErrors(videoPage);
    await loadFixture(videoPage);
    const previewStart = (Date.now() - videoStart) / 1000;
    await videoPage.waitForTimeout(20_500);
    await videoContext.close();
    const rawPath = await videoPage.video().path();
    const videoPath = `${out}/combat-preview-20s.mp4`;
    execFileSync('ffmpeg', ['-y', '-ss', String(previewStart), '-i', rawPath, '-t', '20', '-an', '-c:v', 'libx264', '-preset', 'fast', '-crf', '20', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', videoPath], { stdio: 'ignore' });
    report.preview = { path: videoPath, seconds: 20, note: 'Separate synthetic workload recording; not benchmark frame samples.' };
    console.log('BENCHMARK_PREVIEW', videoPath);
  }
} catch (error) {
  report.status = 'failed';
  report.error = error.stack || String(error);
  process.exitCode = 1;
  console.error(report.error);
  await page.screenshot({ path: `${out}/failure.png` }).catch(() => {});
} finally {
  report.errors = errors;
  report.failedRequests = requestsFailed;
  report.externalRequests = externalRequests;
  await writeFile(`${out}/report.json`, JSON.stringify(report, null, 2));
  let shutdownTimer;
  const stopped = await Promise.race([
    (async () => { await context.close().catch(() => {}); await browser.close(); return true; })(),
    new Promise(resolve => { shutdownTimer = setTimeout(() => resolve(false), 5000); }),
  ]);
  clearTimeout(shutdownTimer);
  if (!stopped) {
    report.cleanupWarning = 'Chrome closed but Playwright shutdown did not settle within five seconds; measurement artifacts are complete.';
    await writeFile(`${out}/report.json`, JSON.stringify(report, null, 2));
  }
  process.exit(process.exitCode || 0);
}
