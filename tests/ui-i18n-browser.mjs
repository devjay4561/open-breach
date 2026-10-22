// RD2 (plan 2-5): switches the web shell to English via the settings
// screen, walks title -> select -> briefing -> HUD -> pause -> settings ->
// debrief (reusing the T01 playthrough from tests/playthrough-browser.mjs),
// and asserts no visible text node contains Hangul anywhere along the way
// (the map editor is explicitly out of scope and never visited here).
// Finally switches back to Korean and confirms Korean text is restored.
import { chromium } from 'playwright';
import assert from 'node:assert/strict';
import { writeFile } from 'node:fs/promises';

const url = new URL(process.env.BREACH_URL || 'http://127.0.0.1:8093');
url.searchParams.set('qa', '1');
const HANGUL = /[가-힣]/;
// Explicit allowlist (plan 2-5): the language option keeps its native name.
const ALLOWLIST = new Set(['한국어']);

// Keep software rendering available for diagnosis without forcing it on hosts
// with a working GPU. Viewports, native readiness and assertions are identical.
const browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--enable-unsafe-swiftshader', ...(process.env.BREACH_USE_SWIFTSHADER === '1' ? ['--use-angle=swiftshader'] : [])] });
const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
await context.addInitScript(() => {
  let ui; window.qa = { states: [], messages: [] };
  Object.defineProperty(window, 'BreachUI', {
    configurable: true, get: () => ui,
    set(v) { ui = v; const fn = v.receive; v.receive = function (raw) { const d = JSON.parse(raw); if (d.type === 'state') { window.qa.states.push(d); if (window.qa.states.length > 600) window.qa.states.shift(); } else window.qa.messages.push(d); return fn.call(v, raw); }; }
  });
});
const page = await context.newPage();
// Keep pointer actionability and navigation guards: their CDP epilogue can
// exceed the default 30s while Godot is busy with software rendering.
page.setDefaultTimeout(300000);
const errors = [];
page.on('pageerror', e => errors.push(e.message));
const wait = fn => page.waitForFunction(fn, null, { timeout: 45000 });
const latest = () => page.evaluate(() => window.qa.states.at(-1));
// SwiftShader can render fewer than one frame per second under CPU load.
// The engine caps simulation catch-up at 0.12s per frame, so operation waits
// need a larger wall-clock budget while retaining the same completion rules.
const waitOperation = fn => page.waitForFunction(fn, null, { timeout: 300000 });
// Deferred native scene loading and its post-render ACK can also exceed the
// DOM interaction budget under cold software rendering. Keep their predicates
// unchanged and allow the same bounded native-work budget as operation waits.
const waitPreparation = fn => page.waitForFunction(fn, null, { timeout: 300000 });

async function waitForTitle() {
  await page.locator('#title-start').waitFor({ state: 'visible' });
  // A fresh load can expose title markup before the native menu is ready.
  // This applies equally to the initial visit and the persistence reload.
  await waitPreparation(() => window.qa.states.at(-1)?.mode === 'MENU'
    && document.querySelector('#loading').hidden
    && !document.querySelector('#transition-loading').open
    && !document.querySelector('#start-mission').disabled);
  const renderer = await page.evaluate(() => {
    const gl = document.querySelector('#canvas')?.getContext('webgl2');
    const debug = gl?.getExtension('WEBGL_debug_renderer_info');
    return { renderer: gl ? gl.getParameter(debug ? debug.UNMASKED_RENDERER_WEBGL : gl.RENDERER) : null, engineFps: window.qa.states.at(-1)?.fps };
  });
  console.log('i18n renderer:', JSON.stringify(renderer));
  await page.evaluate(async () => {
    await Promise.all(document.querySelector('#title-screen').getAnimations({ subtree: true })
      .filter(animation => Number.isFinite(animation.effect?.getComputedTiming().endTime))
      .map(animation => animation.finished.catch(() => {})));
  });
}

async function waitForHudCamera() {
  await page.locator('#hud').waitFor({ state: 'visible' });
  await waitPreparation(() => document.querySelector('#loading').hidden && !document.querySelector('#transition-loading').open);
  // PLANNING can precede the HUD transition and its final camera insets.
  // Wait for finite animations and the existing post-render quality ACK,
  // rather than letting a timed delay decide when Escape/map input is ready.
  await page.evaluate(async () => {
    await Promise.all(document.querySelector('#hud').getAnimations({ subtree: true })
      .filter(animation => Number.isFinite(animation.effect?.getComputedTiming().endTime))
      .map(animation => animation.finished.catch(() => {})));
    const right = document.querySelector('.hud-right').getBoundingClientRect();
    window.BreachBridge.send(JSON.stringify({
      action: 'set_safe_area', _quality_token: 'i18n-camera-ready',
      data: {
        left: Math.round(document.querySelector('.hud-left').getBoundingClientRect().width),
        top: Math.round(document.querySelector('.hud-topbar').getBoundingClientRect().height),
        right: Math.max(0, Math.round(innerWidth - Math.max(right.left, 0))),
        bottom: Math.round(document.querySelector('.hud-hotbar').getBoundingClientRect().height),
      },
    }));
  });
  await waitPreparation(() => window.qa.states.some(state => state.mode === 'PLANNING' && state.quality?.ack_tokens?.includes('i18n-camera-ready')));
}

async function waitForBriefing() {
  await page.locator('#briefing-screen').waitFor({ state: 'visible' });
  await page.evaluate(async () => {
    await Promise.all(document.querySelector('#briefing-screen').getAnimations({ subtree: true })
      .filter(animation => Number.isFinite(animation.effect?.getComputedTiming().endTime))
      .map(animation => animation.finished.catch(() => {})));
    const map = document.querySelector('.briefing-map').getBoundingClientRect();
    // The preview request precedes this token in the engine inbox. Its
    // post-render ACK proves the deferred preview load finished before Start.
    window.BreachBridge.send(JSON.stringify({
      action: 'set_safe_area', _quality_token: 'i18n-briefing-ready',
      data: {
        left: Math.round(Math.max(0, map.left)),
        top: Math.round(Math.max(0, map.top)),
        right: Math.round(Math.max(0, innerWidth - map.right)),
        bottom: Math.round(Math.max(0, innerHeight - map.bottom)),
      },
    }));
  });
  await waitPreparation(() => window.qa.states.some(state => state.mode === 'MENU' && state.quality?.ack_tokens?.includes('i18n-briefing-ready')));
  await waitPreparation(() => document.querySelector('#loading').hidden
    && !document.querySelector('#transition-loading').open
    && !document.querySelector('#start-mission').disabled);
}

async function faceAt(sx, sy, target) {
  const count = (await latest()).units[0].commands.length;
  await page.locator('[data-tool="face"]').click();
  await wait(() => window.qa.states.at(-1)?.tool === 'face');
  await page.mouse.click(sx, sy);
  // The tool bridge and canvas input run asynchronously. Confirm the same
  // intended FACE target is registered before starting the operation.
  await page.waitForFunction(({ count, target }) => {
    const commands = window.qa.states.at(-1)?.units[0]?.commands;
    const command = commands?.at(-1);
    return commands?.length > count && command?.type === 'FACE'
      && Math.abs(command.args.target[0] - target[0]) < 0.12
      && Math.abs(command.args.target[1] - target[1]) < 0.12;
  }, { count, target }, { timeout: 45000 });
}

async function scanHangul(label) {
  const hits = await page.evaluate((allow) => {
    const found = [];
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
      acceptNode(node) {
        if (!node.textContent.trim()) return NodeFilter.FILTER_REJECT;
        const el = node.parentElement;
        if (!el) return NodeFilter.FILTER_REJECT;
        if (el.closest('.map-editor')) return NodeFilter.FILTER_REJECT;
        const style = getComputedStyle(el);
        if (style.visibility === 'hidden' || style.display === 'none') return NodeFilter.FILTER_REJECT;
        if (el.closest('[hidden]')) return NodeFilter.FILTER_REJECT;
        const rects = el.getClientRects();
        if (!rects.length) return NodeFilter.FILTER_REJECT;
        return NodeFilter.FILTER_ACCEPT;
      }
    });
    let node;
    while ((node = walker.nextNode())) {
      const text = node.textContent.trim();
      if (allow.includes(text)) continue;
      if (/[가-힣]/.test(text)) {
        found.push({ text: text.slice(0, 60), tag: node.parentElement.tagName, cls: node.parentElement.className });
      }
    }
    return found;
  }, [...ALLOWLIST]);
  if (hits.length) console.error(`Hangul found in ${label}:`, hits.slice(0, 15));
  assert.equal(hits.length, 0, `${label}: ${hits.length} visible text node(s) with Hangul`);
  console.log(`PASS ${label}: no unexpected Hangul`);
}

try {
  // -- title: switch language to English via settings, confirm live apply --
  await page.goto(url.toString());
  await waitForTitle();
  await page.locator('#title-settings').click();
  await page.waitForSelector('[data-settings-tab="gameplay"]', { state: 'visible' });
  await page.locator('[data-cycler="language"] output').click();
  await page.locator('[data-cycler="language"] [data-cycle-set="en"]').click();
  assert.equal(await page.evaluate(() => document.documentElement.lang), 'en', 'language cycler did not switch to English');
  await page.keyboard.press('Escape');
  await page.locator('#modal').waitFor({ state: 'hidden' }).catch(() => {});
  await scanHangul('title screen (English)');

  // -- select --
  await page.locator('#title-start').click();
  await page.locator('#tab-M01').waitFor({ state: 'visible' });
  await scanHangul('mission select (English)');

  // -- briefing --
  await page.locator('#tab-T01').click();
  await page.locator('#select-to-briefing').click();
  await waitForBriefing();
  await scanHangul('briefing (English)');

  // -- HUD / planning (T01 playthrough, mirrors tests/playthrough-browser.mjs) --
  await page.locator('#start-mission').click();
  await waitPreparation(() => window.qa.states.at(-1)?.mode === 'PLANNING');
  await waitForHudCamera();
  await scanHangul('HUD / planning (English)');

  // -- pause --
  await page.keyboard.press('Escape');
  await page.locator('#pause-panel').waitFor({ state: 'visible' });
  await scanHangul('pause menu (English)');

  // -- settings (reached from pause) --
  await page.locator('#pause-panel [data-open="settings"]').click();
  await page.waitForSelector('[data-settings-tab="gameplay"]', { state: 'visible' });
  await scanHangul('settings / gameplay tab (English)');
  await page.locator('[data-settings-tab="controls"]').click();
  await page.waitForTimeout(100);
  await scanHangul('settings / controls tab (English)');
  await page.locator('[data-settings-tab="accessibility"]').click();
  await page.waitForTimeout(100);
  await scanHangul('settings / accessibility tab (English)');
  await page.keyboard.press('Escape');
  await page.locator('#modal').waitFor({ state: 'hidden' }).catch(() => {});
  await page.locator('#resume-game').click();
  await page.locator('#pause-panel').waitFor({ state: 'hidden' });

  // -- drive the T01 operation to completion (same beats as playthrough-browser.mjs) --
  await page.keyboard.press('Digit1');
  await page.mouse.click(512, 473, { button: 'right' });
  await wait(() => window.qa.states.at(-1)?.units[0].commands.length > 0);
  await page.locator('#toggle-execution').click();
  await waitOperation(() => window.qa.states.at(-1)?.objectives.neutralized >= 1);
  await page.locator('#toggle-execution').click();
  await wait(() => window.qa.states.at(-1)?.mode === 'PLANNING');
  await scanHangul('HUD / planning after first contact (English)');

  await page.mouse.click(583, 362);
  await wait(() => window.qa.states.at(-1)?.units[0].commands.some(c => c.type === 'OPEN_DOOR'));
  await page.mouse.click(720, 428, { button: 'right' });
  await wait(() => window.qa.states.at(-1)?.units[0].commands.some(c => c.type === 'MOVE' && c.state === 'PENDING' && c.args.target[0] > 10));
  await faceAt(720, 310, [12.23, 8.03]);
  await page.locator('#toggle-execution').click();
  await waitOperation(() => window.qa.states.at(-1)?.objectives.neutralized >= 2);
  await page.locator('#toggle-execution').click();
  await wait(() => window.qa.states.at(-1)?.mode === 'PLANNING');
  await page.locator('#door-modes').click();
  await page.locator('[data-door-mode="OPEN_DOOR"]').click();
  await page.mouse.click(857, 362);
  await wait(() => window.qa.states.at(-1)?.units[0].commands.some(c => c.type === 'OPEN_DOOR' && c.args.door_id === 'd2'));
  await page.mouse.click(928, 422, { button: 'right' });
  await wait(() => window.qa.states.at(-1)?.units[0].commands.some(c => c.type === 'MOVE' && c.state === 'PENDING' && Math.abs(c.args.target[0] - 16.96) < 0.12 && Math.abs(c.args.target[1] - 10.83) < 0.12));
  await faceAt(928, 310, [16.96, 8.03]);
  await page.locator('#toggle-execution').click();
  await waitOperation(() => window.qa.states.at(-1)?.mode === 'RESULT');

  // -- debrief --
  await page.waitForTimeout(300);
  await scanHangul('debrief / result (English)');

  // -- switch back to Korean and confirm it is restored --
  // Reload fresh rather than navigating the live mission/menu state machine
  // back to the title screen (the result screen's own "menu" action leads
  // to whatever sub-screen was last shown, and that path proved unreliable
  // to drive deterministically in this harness). A fresh load also doubles
  // as a check that the English choice persisted across a reload.
  await page.goto(url.toString());
  await waitForTitle();
  assert.equal(await page.evaluate(() => document.documentElement.lang), 'en', 'English language choice did not persist across reload');
  await page.locator('#title-settings').click();
  await page.waitForSelector('[data-settings-tab="gameplay"]', { state: 'visible' });
  await page.waitForTimeout(150);
  await page.locator('[data-cycler="language"] output').click();
  await page.waitForSelector('[data-cycler="language"] [data-cycle-set="ko"]', { state: 'visible' });
  await page.locator('[data-cycler="language"] [data-cycle-set="ko"]').click();
  assert.equal(await page.evaluate(() => document.documentElement.lang), 'ko', 'language cycler did not switch back to Korean');
  const titleText = await page.locator('#nav-start-label, #title-start').first().textContent();
  assert.ok(/[가-힣]/.test(titleText || ''), 'Korean text was not restored after switching back');
  console.log('PASS language switch back to Korean restores Korean text');

  assert.deepEqual(errors, [], `console errors: ${JSON.stringify(errors)}`);
  console.log('i18n check: all passed');
} catch (e) {
  console.error(e);
  try {
    const trace = await page.evaluate(() => ({
      latest_state: window.qa?.states.at(-1) || null,
      last_states: (window.qa?.states || []).slice(-10).map(state => ({
        mode: state.mode, tick: state.tick, time: state.time,
        quality: state.quality || null,
      })),
      loading_messages: (window.qa?.messages || []).filter(message => message.type === 'loading').slice(-10),
      loading_dom: {
        initial_hidden: document.querySelector('#loading')?.hidden,
        transition_open: document.querySelector('#transition-loading')?.open,
        transition_title: document.querySelector('#transition-title')?.textContent,
        transition_message: document.querySelector('#transition-message')?.textContent,
        start_disabled: document.querySelector('#start-mission')?.disabled,
        hud_hidden: document.querySelector('#hud')?.hidden,
        active_element: document.activeElement?.id,
      },
    }));
    await writeFile('tests/artifacts/ui-i18n-failure.json', JSON.stringify({
      error: { name: e.name, message: e.message, stack: e.stack },
      page_errors: errors, ...trace,
    }, null, 2));
  } catch (diagnosisError) {
    console.error('Failed to save i18n diagnostics:', diagnosisError);
  }
  try { await page.screenshot({ path: 'tests/artifacts/ui-i18n-failure.png' }); } catch {}
  process.exitCode = 1;
} finally {
  await browser.close();
}
