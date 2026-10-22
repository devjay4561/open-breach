// RD2 (plan 2-4): resolution audit. At each target viewport, visits title,
// select, briefing, HUD (planning), settings, pause and debrief and checks:
//  - no element overflows the viewport;
//  - no two visible interactive elements in the same layer overlap;
//  - no text is clipped (scrollWidth > clientWidth without ellipsis).
// Saves one screenshot per resolution per screen to
// tests/artifacts/ui-resolution/<WxH>-<screen>.png.
import { chromium } from 'playwright';
import assert from 'node:assert/strict';
import { mkdirSync, writeFileSync } from 'node:fs';

const url = new URL(process.env.BREACH_URL || 'http://127.0.0.1:8093');
url.searchParams.set('qa', '1');
// P2: the 2560px case exposed a modal-close/native-focus readiness race.
// Run that independent context first so a recurrence fails sooner; every
// original resolution and all 35 screens still run, including each debrief.
const SIZES = [[2560, 1440], [1280, 800], [1366, 768], [1600, 900], [1920, 1080]];
const OUT_DIR = 'tests/artifacts/ui-resolution';
mkdirSync(OUT_DIR, { recursive: true });

// Preserve an explicit software fallback while using the host's existing GPU
// by default. All five contexts and their original 35 audits still execute.
const browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--enable-unsafe-swiftshader', ...(process.env.BREACH_USE_SWIFTSHADER === '1' ? ['--use-angle=swiftshader'] : [])] });
let failures = [];
let auditedScreens = 0;
let activePage = null, activeTag = '';

// Native scene loads are deferred across render frames. Under SwiftShader a
// frame can take seconds; keep DOM/command checks bounded separately while
// waiting for the same native readiness and mission-completion conditions.
const DOM_WAIT_MS = 45000;
const NATIVE_WAIT_MS = 300000;
const waitDom = (page, predicate, argument = null) => page.waitForFunction(predicate, argument, { timeout: DOM_WAIT_MS });
const waitNative = (page, predicate, argument = null) => page.waitForFunction(predicate, argument, { timeout: NATIVE_WAIT_MS });

async function settleAnimations(page, selector) {
  await page.evaluate(async selector => {
    const animations = document.querySelector(selector).getAnimations({ subtree: true });
    await Promise.all(animations.filter(animation =>
      Number.isFinite(animation.effect?.getComputedTiming().endTime)
    ).map(animation => animation.finished.catch(() => {})));
  }, selector);
}

async function waitForLoadingClosed(page, mode) {
  await waitNative(page, mode => window.qa.states.at(-1)?.mode === mode
    && document.querySelector('#loading').hidden
    && !document.querySelector('#transition-loading').open
    && (mode !== 'MENU' || !document.querySelector('#start-mission').disabled), mode);
}

async function waitForCameraAck(page, screen, mode) {
  const token = await page.evaluate(screen => {
    let data;
    if (screen === 'hud') {
      const right = document.querySelector('.hud-right').getBoundingClientRect();
      data = {
        left: Math.round(document.querySelector('.hud-left').getBoundingClientRect().width),
        top: Math.round(document.querySelector('.hud-topbar').getBoundingClientRect().height),
        right: Math.max(0, Math.round(innerWidth - Math.max(right.left, 0))),
        bottom: Math.round(document.querySelector('.hud-hotbar').getBoundingClientRect().height),
      };
    } else if (screen === 'title') {
      const nav = document.querySelector('.title-nav').getBoundingClientRect();
      const wordmark = document.querySelector('.title-wordmark').getBoundingClientRect();
      data = { left: Math.round(Math.max(nav.right, wordmark.right) + 32), top: 0, right: 0, bottom: 0 };
    } else {
      const rect = document.querySelector(screen === 'select' ? '.select-body' : '.briefing-map').getBoundingClientRect();
      data = {
        left: Math.round(Math.max(0, rect.left)), top: Math.round(Math.max(0, rect.top)),
        right: Math.round(Math.max(0, innerWidth - rect.right)), bottom: Math.round(Math.max(0, innerHeight - rect.bottom)),
      };
    }
    const token = `resolution-layout-${screen}-${window.qa.cameraSequence = (window.qa.cameraSequence || 0) + 1}`;
    // Loading has closed before this intent enters the FIFO. Its post-render
    // ACK therefore confirms the deferred preview and these insets finished.
    window.BreachBridge.send(JSON.stringify({ action: 'set_safe_area', data, _quality_token: token }));
    return token;
  }, screen);
  await waitNative(page, ({ token, mode }) => window.qa.states.some(state =>
    state.mode === mode && state.quality?.ack_tokens?.includes(token)
  ), { token, mode });
}

async function waitForMenuCamera(page, screen) {
  const selector = screen === 'title' ? '#title-screen' : screen === 'select' ? '#select-screen' : '#briefing-screen';
  await page.locator(selector).waitFor({ state: 'visible', timeout: DOM_WAIT_MS });
  await waitForLoadingClosed(page, 'MENU');
  await settleAnimations(page, selector);
  await waitForCameraAck(page, screen, 'MENU');
  await waitForLoadingClosed(page, 'MENU');
}

async function waitForHudCamera(page) {
  await page.locator('#hud').waitFor({ state: 'visible', timeout: DOM_WAIT_MS });
  await waitForLoadingClosed(page, 'PLANNING');
  await settleAnimations(page, '#hud');
  await waitForCameraAck(page, 'hud', 'PLANNING');
}

async function recordBridgeIntents(page) {
  await page.evaluate(() => {
    const bridge = window.BreachBridge, send = bridge.send;
    // Observe the real UI intents without changing their payload or order.
    bridge.send = function (raw) {
      window.qa.sent.push(JSON.parse(raw));
      return send.call(this, raw);
    };
  });
}

async function waitForModalInputRelease(page, beforeClose) {
  // A native <dialog> becomes hidden before its queued close handler has
  // necessarily released Godot's input gates. The previous high-resolution
  // run passed 33 geometry checks but its second Escape never opened pause.
  // Observe both actual release intents and canvas focus, then use the
  // existing FIFO post-render ACK. No input release is injected by the test.
  await waitDom(page, before => {
    const sent = window.qa.sent.slice(before);
    return !document.querySelector('#modal').open
      && document.activeElement === document.querySelector('#canvas')
      && sent.some(message => message.action === 'input_focus' && message.blocked === false)
      && sent.some(message => message.action === 'ui_focus'
        && (message.data?.active === false || message.active === false));
  }, beforeClose);
  await waitForCameraAck(page, 'hud', 'PLANNING');
}

async function selectFirstUnit(page) {
  const id = await page.evaluate(() => window.qa.states.at(-1).units[0].id);
  await page.keyboard.press('Digit1');
  await waitDom(page, id => window.qa.states.at(-1)?.selected === id, id);
}

async function moveAt(page, sx, sy, target) {
  const count = await page.evaluate(() => window.qa.states.at(-1).units[0].commands.length);
  await page.mouse.click(sx, sy, { button: 'right' });
  await waitDom(page, ({ count, target }) => window.qa.states.at(-1)?.units[0]?.commands.slice(count).some(command =>
    command.type === 'MOVE' && command.state === 'PENDING'
    && Math.abs(command.args.target[0] - target[0]) < 0.12
    && Math.abs(command.args.target[1] - target[1]) < 0.12
  ), { count, target });
}

async function faceAt(page, sx, sy, target) {
  const count = await page.evaluate(() => window.qa.states.at(-1).units[0].commands.length);
  await page.locator('[data-tool="face"]').click();
  await waitDom(page, () => window.qa.states.at(-1)?.tool === 'face');
  await page.mouse.click(sx, sy);
  // Keep the original world target, and confirm FACE entered the real queue
  // before executing so a delayed toolbar intent cannot omit the command.
  await waitDom(page, ({ count, target }) => {
    const commands = window.qa.states.at(-1)?.units[0]?.commands;
    const command = commands?.at(-1);
    return commands?.length > count && command?.type === 'FACE' && command.state === 'PENDING'
      && Math.abs(command.args.target[0] - target[0]) < 0.12
      && Math.abs(command.args.target[1] - target[1]) < 0.12;
  }, { count, target });
}

async function execute(page) {
  await page.locator('#toggle-execution').click();
  await waitNative(page, () => ['EXECUTING', 'RESULT'].includes(window.qa.states.at(-1)?.mode));
}

async function pause(page) {
  await page.locator('#toggle-execution').click();
  await waitNative(page, () => window.qa.states.at(-1)?.mode === 'PLANNING');
}

// Use the same P0 projection and unchanged T01 world targets as the result
// overflow suite; a fraction of the safe rect does not account for letterboxing.
async function project(page, x, z, y = 0.25) {
  const [sx, sy] = await page.evaluate(({ x, z, y }) => {
    const data = window.qa.catalog.T01;
    const focus = data.focus || data.bounds.map(value => value / 2);
    let left = focus[0], right = focus[0], top = focus[1], bottom = focus[1];
    for (const rect of [...data.rooms, ...data.walls]) {
      left = Math.min(left, rect.x - rect.w / 2); right = Math.max(right, rect.x + rect.w / 2);
      top = Math.min(top, rect.z - rect.d / 2); bottom = Math.max(bottom, rect.z + rect.d / 2);
    }
    for (const unit of data.units) { left = Math.min(left, unit.x); right = Math.max(right, unit.x); top = Math.min(top, unit.z); bottom = Math.max(bottom, unit.z); }
    left -= 0.75; right += 0.75; top -= 0.75; bottom += 0.8;
    const canvas = document.querySelector('#canvas').getBoundingClientRect(), width = canvas.width, height = canvas.height;
    const viewW = innerWidth, viewH = innerHeight, aspect = viewW / viewH;
    // Live safe-area insets, computed the same way web/app.js's sendSafeArea
    // does for PLANNING/EXECUTING.
    const topbarRect = document.querySelector('.hud-topbar')?.getBoundingClientRect();
    const leftRect = document.querySelector('.hud-left')?.getBoundingClientRect();
    const rightRect = document.querySelector('.hud-right')?.getBoundingClientRect();
    const hotbarRect = document.querySelector('.hud-hotbar')?.getBoundingClientRect();
    const insetLeft = Math.round(leftRect?.width || 0);
    const insetTop = Math.round(topbarRect?.height || 0);
    const insetRight = rightRect ? Math.max(0, Math.round(viewW - Math.max(rightRect.left, 0))) : 0;
    const insetBottom = Math.round(hotbarRect?.height || 0);
    const MARGIN = 16; // SAFE_AREA_MARGIN_PX in world_view.gd
    const safeLeft = insetLeft + MARGIN, safeTop = insetTop + MARGIN, safeRight = insetRight + MARGIN, safeBottom = insetBottom + MARGIN;
    const safeWidth = Math.max(viewW - safeLeft - safeRight, 1), safeHeight = Math.max(viewH - safeTop - safeBottom, 1);
    const verticalFraction = Math.min(0.97, Math.max(0.25, safeHeight / viewH));
    const horizontalFraction = Math.min(0.97, Math.max(0.25, safeWidth / viewW));
    const heightSize = (bottom - top) / verticalFraction;
    const widthSize = (right - left) / Math.max(aspect * horizontalFraction, 0.1);
    const size = Math.max(heightSize, widthSize); // zoom=1, fit_multiplier=1 once a real safe area is active
    const pixelScale = height / size; // Camera3D KEEP_HEIGHT: uniform world->pixel scale
    const centerX = (left + right) / 2, centerZ = (top + bottom) / 2; // center_bias=0 once a real safe area is active
    const norm = Math.hypot(34, 15.5), upY = 15.5 / norm, upZ = -34 / norm;
    return [
      canvas.left + width / 2 + (x - centerX) * pixelScale + (safeLeft - safeRight) / 2,
      canvas.top + height / 2 - (y * upY + (z - centerZ) * upZ) * pixelScale + (safeTop - safeBottom) / 2,
    ];
  }, { x, z, y });
  return [Math.round(sx), Math.round(sy)];
}


// Checks run against whatever is currently visible on screen: overflow,
// overlap among same-layer interactive elements, and clipped text.
async function audit(page, label) {
  auditedScreens++;
  const result = await page.evaluate(() => {
    const vw = innerWidth, vh = innerHeight;
    const overflow = [];
    const all = Array.from(document.querySelectorAll('body *')).filter(el => {
      if (el.closest('.map-editor')) return false;
      if (el.closest('[hidden]')) return false;
      const style = getComputedStyle(el);
      if (style.position === 'fixed' && (style.width === '100%' || el.id === 'canvas' || el.id === 'vignette' || el.id === 'fx-layer')) return false;
      if (style.visibility === 'hidden' || style.display === 'none') return false;
      return true;
    });
    for (const el of all) {
      const r = el.getBoundingClientRect();
      if (r.width <= 0 || r.height <= 0) continue;
      // Entirely off-canvas elements (e.g. a slide-out drawer collapsed via
      // transform:translateX(100%), like .hud-right at narrow widths) are a
      // deliberate "currently hidden" state, not an overflow bug -- only
      // flag an element that is PARTIALLY on-screen and spills past an edge.
      const entirelyOffscreen = r.right <= 0 || r.bottom <= 0 || r.left >= vw || r.top >= vh;
      if (entirelyOffscreen) continue;
      // Allow a couple of px of rounding/antialiasing slack.
      const slack = 2;
      if (r.left < -slack || r.top < -slack || r.right > vw + slack || r.bottom > vh + slack) {
        overflow.push({ sel: el.id ? `#${el.id}` : el.className ? `.${String(el.className).split(' ')[0]}` : el.tagName, rect: { left: Math.round(r.left), top: Math.round(r.top), right: Math.round(r.right), bottom: Math.round(r.bottom) } });
      }
    }
    // Overlap: interactive elements (buttons/links/cards/panels) that are
    // both visible, in the same DOM "layer" (neither contains the other),
    // and whose boxes intersect by a non-trivial area.
    const interactive = Array.from(document.querySelectorAll('button, a, .mission-card, .unit-card, [role="tab"], [role="menuitem"]'))
      .filter(el => !el.closest('.map-editor') && !el.closest('[hidden]') && !el.disabled)
      .filter(el => { const s = getComputedStyle(el); return s.visibility !== 'hidden' && s.display !== 'none'; })
      .map(el => ({ el, r: el.getBoundingClientRect() }))
      .filter(o => o.r.width > 0 && o.r.height > 0);
    const overlaps = [];
    for (let i = 0; i < interactive.length; i++) {
      for (let j = i + 1; j < interactive.length; j++) {
        const a = interactive[i], b = interactive[j];
        if (a.el.contains(b.el) || b.el.contains(a.el)) continue;
        const ix = Math.min(a.r.right, b.r.right) - Math.max(a.r.left, b.r.left);
        const iy = Math.min(a.r.bottom, b.r.bottom) - Math.max(a.r.top, b.r.top);
        if (ix > 4 && iy > 4) {
          const areaA = a.r.width * a.r.height, areaB = b.r.width * b.r.height;
          const overlapArea = ix * iy;
          // Ignore trivial overlaps (e.g. a badge sitting a couple of px
          // into its parent button's edge) -- flag only when the overlap
          // is a meaningful fraction of the smaller element.
          if (overlapArea > 0.25 * Math.min(areaA, areaB)) {
            overlaps.push({ a: a.el.id || a.el.className, b: b.el.id || b.el.className });
          }
        }
      }
    }
    // Clipped text: scrollWidth > clientWidth on elements that aren't
    // intentionally using ellipsis/nowrap-with-overflow-visible patterns.
    const clipped = [];
    for (const el of all) {
      if (!el.textContent || !el.textContent.trim()) continue;
      const hasOwnText = Array.from(el.childNodes).some(n => n.nodeType === 3 && n.textContent.trim());
      if (!hasOwnText) continue;
      const style = getComputedStyle(el);
      if (style.textOverflow === 'ellipsis') continue;
      if (el.scrollWidth > el.clientWidth + 2 && style.overflow !== 'visible' && style.whiteSpace !== 'normal') {
        clipped.push({ sel: el.id ? `#${el.id}` : el.tagName, text: el.textContent.trim().slice(0, 40), scrollWidth: el.scrollWidth, clientWidth: el.clientWidth });
      }
    }
    return { overflow, overlaps, clipped };
  });
  const problems = [];
  if (result.overflow.length) problems.push(`${result.overflow.length} overflowing element(s): ${JSON.stringify(result.overflow.slice(0, 5))}`);
  if (result.overlaps.length) problems.push(`${result.overlaps.length} overlapping interactive pair(s): ${JSON.stringify(result.overlaps.slice(0, 5))}`);
  if (result.clipped.length) problems.push(`${result.clipped.length} clipped text element(s): ${JSON.stringify(result.clipped.slice(0, 5))}`);
  if (problems.length) {
    failures.push(`${label}: ${problems.join(' | ')}`);
    console.error(`FAIL ${label}:`, problems);
  } else {
    console.log(`PASS ${label}: no overflow/overlap/clipping`);
  }
}

async function runAt(width, height) {
  const tag = `${width}x${height}`;
  const context = await browser.newContext({ viewport: { width, height } });
  await context.addInitScript(() => {
    let ui; window.qa = { states: [], catalog: {}, sent: [], messages: [] };
    Object.defineProperty(window, 'BreachUI', {
      configurable: true, get: () => ui,
      set(v) { ui = v; const fn = v.receive; v.receive = function (raw) {
        const d = JSON.parse(raw);
        if (d.type === 'state') { window.qa.states.push(d); if (window.qa.states.length > 400) window.qa.states.shift(); }
        else { window.qa.messages.push(d); if (window.qa.messages.length > 100) window.qa.messages.shift(); }
        if (d.type === 'ready') window.qa.catalog = d.catalog || {};
        if (d.type === 'catalog_update') Object.assign(window.qa.catalog, d.catalog || {});
        return fn.call(v, raw);
      }; }
    });
  });
  const page = await context.newPage();
  activePage = page; activeTag = tag;
  // Playwright's click epilogue waits for a CDP render acknowledgement even
  // after the DOM action completes; SwiftShader can exceed its default 30s.
  page.setDefaultTimeout(NATIVE_WAIT_MS);
  const shot = async name => { try { await page.screenshot({ path: `${OUT_DIR}/${tag}-${name}.png` }); } catch (e) { console.error('screenshot failed', tag, name, e.message); } };

  await page.goto(url.toString());
  await waitForMenuCamera(page, 'title');
  console.log('resolution renderer:', JSON.stringify(await page.evaluate(() => {
    const gl = document.querySelector('#canvas')?.getContext('webgl2');
    const debug = gl?.getExtension('WEBGL_debug_renderer_info');
    return { viewport: [innerWidth, innerHeight], renderer: gl ? gl.getParameter(debug ? debug.UNMASKED_RENDERER_WEBGL : gl.RENDERER) : null, engineFps: window.qa.states.at(-1)?.fps };
  })));
  await audit(page, `${tag} / title`);
  await shot('title');

  await page.locator('#title-start').click();
  await page.locator('#tab-M01').waitFor({ state: 'visible' });
  await waitForMenuCamera(page, 'select');
  await audit(page, `${tag} / select`);
  await shot('select');

  await page.locator('#tab-T01').click();
  await page.locator('#select-to-briefing').click();
  await waitForMenuCamera(page, 'briefing');
  await audit(page, `${tag} / briefing`);
  await shot('briefing');

  await page.locator('#start-mission').click();
  await waitNative(page, () => window.qa.states.at(-1)?.mode === 'PLANNING');
  await waitForHudCamera(page);
  await audit(page, `${tag} / HUD planning`);
  await shot('hud-planning');
  await recordBridgeIntents(page);

  await page.locator('[data-open="settings"]:visible').click();
  await page.waitForSelector('[data-settings-tab="gameplay"]', { state: 'visible' });
  await settleAnimations(page, '#modal');
  await audit(page, `${tag} / settings`);
  await shot('settings');
  const beforeModalClose = await page.evaluate(() => window.qa.sent.length);
  await page.keyboard.press('Escape');
  await page.locator('#modal').waitFor({ state: 'hidden', timeout: DOM_WAIT_MS });
  await waitForModalInputRelease(page, beforeModalClose);

  await page.keyboard.press('Escape');
  await page.locator('#pause-panel').waitFor({ state: 'visible' });
  await settleAnimations(page, '#pause-panel');
  await audit(page, `${tag} / pause`);
  await shot('pause');
  await page.locator('#resume-game').click();
  await page.locator('#pause-panel').waitFor({ state: 'hidden' });

  // The P0 result projection selects the same original T01 world points at
  // every aspect ratio after the native HUD camera has acknowledged its insets.
  await waitForHudCamera(page);
  const [move1X, move1Y] = await project(page, 7.5, 12.08);
  const [move2X, move2Y] = await project(page, 12.23, 10.98);
  const [face2X, face2Y] = await project(page, 12.23, 8.03);
  const [move3X, move3Y] = await project(page, 16.96, 10.83);
  const [face3X, face3Y] = await project(page, 16.96, 8.03);
  await selectFirstUnit(page);
  await moveAt(page, move1X, move1Y, [7.5, 12.08]);
  await execute(page);
  await waitNative(page, () => window.qa.states.at(-1)?.objectives.neutralized >= 1);
  await pause(page);
  await moveAt(page, move2X, move2Y, [12.23, 10.98]);
  await faceAt(page, face2X, face2Y, [12.23, 8.03]);
  await execute(page);
  await waitNative(page, () => window.qa.states.at(-1)?.objectives.neutralized >= 2);
  await pause(page);
  await moveAt(page, move3X, move3Y, [16.96, 10.83]);
  await faceAt(page, face3X, face3Y, [16.96, 8.03]);
  await execute(page);
  // A missing debrief is a failed readiness/completion condition, rather than
  // a skipped geometry check; all five result screens are part of the gate.
  await waitNative(page, () => window.qa.states.at(-1)?.mode === 'RESULT');
  await page.locator('#result').waitFor({ state: 'visible', timeout: DOM_WAIT_MS });
  await settleAnimations(page, '#result');
  await audit(page, `${tag} / debrief`);
  await shot('debrief');

  await context.close();
  activePage = null;
}

try {
  for (const [w, h] of SIZES) await runAt(w, h);
  assert.equal(auditedScreens, SIZES.length * 7, 'all 35 resolution screens, including all five debriefs, are audited');
  if (failures.length) {
    console.error(`\n${failures.length} resolution/layout failure(s):\n` + failures.join('\n'));
    process.exitCode = 1;
  } else {
    console.log('\nResolution audit: all passed');
  }
} catch (error) {
  const directory = 'tests/artifacts/ui-resolution';
  mkdirSync(directory, { recursive: true });
  const diagnostic = { status: 'FAIL', viewport: activeTag, auditedScreens, requiredScreens: SIZES.length * 7, sizes: SIZES, error: error.stack };
  if (activePage && !activePage.isClosed()) {
    try {
      diagnostic.page = await activePage.evaluate(() => ({
        active: { tag: document.activeElement?.tagName, id: document.activeElement?.id },
        modalOpen: document.querySelector('#modal').open,
        pauseHidden: document.querySelector('#pause-panel').hidden,
        loadingHidden: document.querySelector('#loading').hidden,
        transitionOpen: document.querySelector('#transition-loading').open,
        sent: window.qa.sent,
        messages: window.qa.messages,
        state: window.qa.states.at(-1),
        recentStates: window.qa.states.slice(-5).map(state => ({ mode: state.mode, tick: state.tick, time: state.time, quality: state.quality })),
        quality: window.BreachQuality?.report(),
      }));
    } catch (readError) { diagnostic.readError = readError.message; }
    try { await activePage.screenshot({ path: `${directory}/failure.png`, timeout: DOM_WAIT_MS }); }
    catch (screenshotError) { diagnostic.screenshotError = screenshotError.message; }
  }
  writeFileSync(`${directory}/report.json`, JSON.stringify(diagnostic, null, 2));
  throw error;
} finally {
  await browser.close();
}
