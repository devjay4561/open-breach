// 0-5: the result/debrief overlay must fit within 100dvh at every target
// resolution; debrief content may scroll while its action buttons stay visible.
// Reuses the T01 playthrough flow to reach the result screen.
import { chromium } from 'playwright';
import assert from 'node:assert/strict';

const url = new URL(process.env.BREACH_URL || 'http://127.0.0.1:8080');
url.searchParams.set('qa', '1');
const sizes = [[1280,800],[1366,768],[1600,900],[1920,1080],[2560,1440]];
const browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--enable-unsafe-swiftshader'] });

// Projects a T01 world-space point (x,z, optional height y) to the on-screen
// pixel the engine renders it at. Mirrors game/scripts/world_view.gd's
// `_fit_camera` safe-area branch (waitForHudCamera below waits for the HUD's
// current insets to be rendered before projecting): the HUD's hud-left/hud-right/
// hud-topbar/hud-hotbar panels reserve real, independently-sized insets on
// all four sides, and the camera preserves the mission frame's aspect ratio
// while fitting it into that safe rect (centered, lens-shifted) rather than
// stretching it to fill the rect axis-independently. At most tested sizes
// the safe rect's aspect ratio is close enough to the frame's that a plain
// fraction-of-the-safe-rect approximation (the previous version of this
// helper) landed close enough to the intended point, but at 3440x1440 the
// safe rect is wide enough that the frame letterboxes (~700px of empty
// margin on each side), so that approximation clicks hundreds of pixels off
// target — e.g. missing the room entirely — and the mission flow stalls
// before reaching RESULT. Projecting the actual world coordinate like this
// is correct at any aspect ratio, since it's the same math the engine itself
// uses to place the frame.
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
  await waitNative(page, mode => window.__qa.states.at(-1)?.mode === mode
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
    const token = `result-layout-${screen}-${window.__qa.cameraSequence = (window.__qa.cameraSequence || 0) + 1}`;
    // Loading has closed before this intent enters the FIFO. Its post-render
    // ACK therefore confirms the deferred preview and these insets finished.
    window.BreachBridge.send(JSON.stringify({ action: 'set_safe_area', data, _quality_token: token }));
    return token;
  }, screen);
  await waitNative(page, ({ token, mode }) => window.__qa.states.some(state =>
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

async function selectFirstUnit(page) {
  const id = await page.evaluate(() => window.__qa.states.at(-1).units[0].id);
  await page.keyboard.press('Digit1');
  await waitDom(page, id => window.__qa.states.at(-1)?.selected === id, id);
}

async function moveAt(page, sx, sy, target) {
  const count = await page.evaluate(() => window.__qa.states.at(-1).units[0].commands.length);
  await page.mouse.click(sx, sy, { button: 'right' });
  await waitDom(page, ({ count, target }) => window.__qa.states.at(-1)?.units[0]?.commands.slice(count).some(command =>
    command.type === 'MOVE' && command.state === 'PENDING'
    && Math.abs(command.args.target[0] - target[0]) < 0.12
    && Math.abs(command.args.target[1] - target[1]) < 0.12
  ), { count, target });
}

async function faceAt(page, sx, sy, target) {
  const count = await page.evaluate(() => window.__qa.states.at(-1).units[0].commands.length);
  await page.locator('[data-tool="face"]').click();
  await waitDom(page, () => window.__qa.states.at(-1)?.tool === 'face');
  await page.mouse.click(sx, sy);
  // Keep the original world target, and confirm FACE entered the real queue
  // before executing so a delayed toolbar intent cannot omit the command.
  await waitDom(page, ({ count, target }) => {
    const commands = window.__qa.states.at(-1)?.units[0]?.commands;
    const command = commands?.at(-1);
    return commands?.length > count && command?.type === 'FACE' && command.state === 'PENDING'
      && Math.abs(command.args.target[0] - target[0]) < 0.12
      && Math.abs(command.args.target[1] - target[1]) < 0.12;
  }, { count, target });
}

async function execute(page) {
  await page.locator('#toggle-execution').click();
  await waitNative(page, () => ['EXECUTING', 'RESULT'].includes(window.__qa.states.at(-1)?.mode));
}

async function pause(page) {
  await page.locator('#toggle-execution').click();
  await waitNative(page, () => window.__qa.states.at(-1)?.mode === 'PLANNING');
}

async function project(page, x, z, y = 0.25) {
  const [sx, sy] = await page.evaluate(({ x, z, y }) => {
    const data = window.__qa.catalog.T01;
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

async function runAt(width, height) {
  const context = await browser.newContext({ viewport: { width, height } });
  await context.addInitScript(() => {
    let ui; window.__qa = { states: [], catalog: {} };
    Object.defineProperty(window, 'BreachUI', {
      configurable: true, get: () => ui,
      set(v) {
        ui = v; const fn = v.receive;
        v.receive = function (raw) {
          const d = JSON.parse(raw);
          if (d.type === 'state') window.__qa.states.push(d);
          if (d.type === 'ready') window.__qa.catalog = d.catalog || {};
          if (d.type === 'catalog_update') Object.assign(window.__qa.catalog, d.catalog || {});
          return fn.call(v, raw);
        }
      }
    });
  });
  const page = await context.newPage();
  // Playwright's click epilogue waits for a CDP render acknowledgement even
  // after the DOM action completes; SwiftShader can exceed its default 30s.
  page.setDefaultTimeout(NATIVE_WAIT_MS);
  await page.goto(url.toString());
  await waitForMenuCamera(page, 'title');
  await page.locator('#title-start').click();
  await waitForMenuCamera(page, 'select');
  await page.locator('#tab-T01').click();
  await page.locator('#select-to-briefing').click();
  await waitForMenuCamera(page, 'briefing');
  if(width===sizes[0][0]){
    await page.locator('#prepare-squad').click();
    await page.locator('.squad-members summary').click();
    await page.locator('[data-roster="echo"]').click();
    await page.locator('#squad-done').click();
    await page.locator('#modal').waitFor({ state: 'hidden', timeout: DOM_WAIT_MS });
    await waitForMenuCamera(page, 'briefing');
  }
  await page.locator('#start-mission').click();
  await waitNative(page, () => window.__qa.states.at(-1)?.mode === 'PLANNING');
  if(width===sizes[0][0])assert.equal(await page.evaluate(()=>window.__qa.states.at(-1)?.units.length),1,'Godot accepts a one-operator deployment');
  // Same three-room clear flow as tests/playthrough-browser.mjs's T01 run
  // (select unit, move, face, repeat per room — MOVE auto-queues OPEN_DOOR
  // for any door the path crosses, so no separate door click is needed) —
  // but with world-space points projected to the current size's actual
  // camera framing instead of hardcoded pixel coordinates, since the HUD's
  // side columns collapse/translate differently at each tested resolution.
  // A plain click that misses its target (e.g. a door icon) lands on empty
  // map and deselects the unit, so only right-click (move) and tool-armed
  // clicks are used here — never a bare left click on open floor. The world
  // coordinates below are tests/playthrough-browser.mjs's literal 1440x900
  // click coordinates, resolved once to the T01 world point the engine
  // places under them there (confirmed via the resulting command's `target`/
  // `args`); project() (above) re-derives the correct on-screen pixel for
  // that same world point at any tested size, so it stays correct even where
  // the mission frame letterboxes inside the safe rect (e.g. 3440x1440),
  // unlike a plain fraction-of-the-safe-rect approximation.
  await page.locator('#canvas').waitFor({ state: 'visible' });
  await waitForHudCamera(page);
  const [move1X, move1Y] = await project(page, 7.5, 12.08);
  const [move2X, move2Y] = await project(page, 12.23, 10.98);
  const [face2X, face2Y] = await project(page, 12.23, 8.03);
  const [move3X, move3Y] = await project(page, 16.96, 10.83);
  const [face3X, face3Y] = await project(page, 16.96, 8.03);

  await selectFirstUnit(page);
  await page.waitForFunction(() => !document.querySelector('[data-tool="face"]').disabled, null, { timeout: DOM_WAIT_MS });
  await moveAt(page, move1X, move1Y, [7.5, 12.08]);
  await execute(page);
  await waitNative(page, () => window.__qa.states.at(-1)?.objectives.neutralized >= 1);
  await pause(page);
  await moveAt(page, move2X, move2Y, [12.23, 10.98]);
  await faceAt(page, face2X, face2Y, [12.23, 8.03]);
  await execute(page);
  await waitNative(page, () => window.__qa.states.at(-1)?.objectives.neutralized >= 2);
  await pause(page);
  await moveAt(page, move3X, move3Y, [16.96, 10.83]);
  await faceAt(page, face3X, face3Y, [16.96, 8.03]);
  await execute(page);
  await waitNative(page, () => window.__qa.states.at(-1)?.mode === 'RESULT');
  await page.locator('#result').waitFor({ state: 'visible', timeout: DOM_WAIT_MS });
  await settleAnimations(page, '#result');
  // Read after RESULT and the visible debrief have arrived, so the original
  // solo/reward/goal assertions cannot be skipped by a stale fallback state.
  const state = await page.evaluate(() => window.__qa.states.at(-1));
  assert.equal(state.mode, 'RESULT', 'real gameplay reaches the result screen');
  assert.equal(await page.locator('#result-goals > span').count(),state.stars.length,'every star goal is visible in the debrief');
  if(width===sizes[0][0]){
    assert.equal(state.result.success,true,'solo tutorial completes through real gameplay');
    assert.equal(state.result.units_deployed,1);
    await waitDom(page, () => /\+[1-9]\d*★/.test(document.querySelector('#result-progression').textContent));
    assert.match(await page.locator('#result-progression').textContent(),/\+[1-9]\d*★/,'real completion grants progression stars');
    console.log('PASS solo deployment + real mission rewards');
  }

  const metrics = await page.evaluate(() => {
    const overlay = document.querySelector('#result');
    if (!overlay || overlay.hidden) return null;
    const card = overlay.querySelector('.result-card');
    const stats = overlay.querySelector('.result-stats');
    const actions = overlay.querySelector('.result-actions');
    const note = overlay.querySelector('.result-card > .note:last-child');
    const within = el => {
      if (!el) return true;
      const r = el.getBoundingClientRect();
      return r.top >= 0 && r.bottom <= window.innerHeight && r.left >= 0 && r.right <= window.innerWidth;
    };
    return {
      cardOverflowsViewport: card ? card.getBoundingClientRect().bottom > window.innerHeight + 1 : false,
      cardScrollOverflow: card ? card.scrollHeight > card.clientHeight + 1 : false,
      statsScrollOverflow: stats ? stats.scrollHeight > stats.clientHeight + 1 : false,
      actionsVisible: within(actions),
      noteVisible: within(note),
    };
  });
  await context.close();
  return metrics;
}

let failures = 0;
try {
  for (const [w, h] of sizes) {
    const m = await runAt(w, h);
    if (!m) { console.error(`FAIL ${w}x${h}: result overlay not reached`); failures++; continue; }
    const ok = !m.cardOverflowsViewport && !m.cardScrollOverflow && m.actionsVisible && m.noteVisible;
    console.log(`${ok ? 'PASS' : 'FAIL'} ${w}x${h}`, JSON.stringify(m));
    if (!ok) failures++;
  }
} finally {
  await browser.close();
}
assert.equal(failures, 0, `${failures} resolution(s) failed the result-overlay fit check`);
console.log('Result overflow check: all resolutions fit within the viewport');
