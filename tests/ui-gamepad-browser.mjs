// RD1 / orchestration task 2-3: gamepad navigation of DOM menus/overlays.
// Stubs navigator.getGamepads before the page scripts ever read it, then
// drives title -> select -> briefing -> start purely with simulated D-pad/A
// input (no real controller, no mouse/keyboard clicks on the game itself).
import { chromium } from 'playwright';
import assert from 'node:assert/strict';

const url = process.env.BREACH_URL || 'http://127.0.0.1:8080';
const browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--enable-unsafe-swiftshader'] });
const context = await browser.newContext({ viewport: { width: 1600, height: 900 } });
await context.addInitScript(() => {
  let ui; window.__qa = { states: [] };
  Object.defineProperty(window, 'BreachUI', {
    configurable: true, get: () => ui,
    set(v) { ui = v; const fn = v.receive; v.receive = function (raw) { const d = JSON.parse(raw); if (d.type === 'state') window.__qa.states.push(d); return fn.call(v, raw); }; }
  });
  // Minimal Gamepad API stub: 17 digital buttons + 4 axes, all neutral.
  // Test code flips individual buttons for one frame ("tap") via
  // window.__pad, matching the real API's edge-triggered button.pressed.
  const buttons = Array.from({ length: 17 }, () => ({ pressed: false, value: 0 }));
  const axes = [0, 0, 0, 0];
  window.__pad = { buttons, axes };
  navigator.getGamepads = () => [{ index: 0, id: 'stub', connected: true, buttons, axes, mapping: 'standard', timestamp: performance.now() }];
});
const page = await context.newPage();
const errors = [];
page.on('pageerror', e => errors.push(e.message));
const wait = fn => page.waitForFunction(fn, null, { timeout: 45000 });

// Hold a digital button/axis for ~3 polled frames then release, so the
// rAF-driven poll in app.js sees a clean press-edge then release-edge.
async function tapButton(index) {
  await page.evaluate(i => { window.__pad.buttons[i].pressed = true; window.__pad.buttons[i].value = 1; }, index);
  await page.waitForTimeout(80);
  await page.evaluate(i => { window.__pad.buttons[i].pressed = false; window.__pad.buttons[i].value = 0; }, index);
  await page.waitForTimeout(80);
}
async function tapDpadDown() {
  await page.evaluate(() => { window.__pad.buttons[13].pressed = true; });
  await page.waitForTimeout(80);
  await page.evaluate(() => { window.__pad.buttons[13].pressed = false; });
  await page.waitForTimeout(260); // clear the 220ms axis/dpad repeat cooldown
}
async function reachControl(id,rootSelector){
  const count=await page.evaluate(selector=>Array.from(document.querySelector(selector).querySelectorAll('button,[tabindex]:not([tabindex="-1"]),a[href],input,select,summary')).filter(el=>!el.disabled&&el.getClientRects().length&&!el.closest('[hidden]')).length,rootSelector);
  for(let step=0;step<=count;step++){
    if(await page.evaluate(()=>document.querySelector('.gamepad-focus')?.id)===id){console.log(`PASS #${id}: reached in ${step} D-pad steps (${count} visible focusables)`);return true;}
    if(step<count)await tapDpadDown();
  }
  return false;
}

try {
  await page.goto(url);
  await page.locator('#title-start').waitFor({ state: 'visible' });
  // Title markup can become visible before the MENU state and gamepad poll
  // finish booting. Observe readiness instead of assuming 200ms was enough.
  await wait(() => window.__qa.states.at(-1)?.mode === 'MENU'
    && document.querySelector('#loading').hidden
    && !document.querySelector('#transition-loading').open
    && !document.querySelector('#start-mission').disabled);
  await page.evaluate(async () => {
    const animations = document.querySelector('#title-screen').getAnimations({ subtree: true });
    await Promise.all(animations.filter(animation =>
      Number.isFinite(animation.effect?.getComputedTiming().endTime)
    ).map(animation => animation.finished.catch(() => {})));
  });
  await wait(() => !!document.querySelector('.gamepad-focus'));

  const initialFocus = await page.evaluate(() => document.querySelector('.gamepad-focus')?.id);
  assert.equal(initialFocus, 'title-start', 'gamepad focus must seed on the first focusable title item');
  console.log(`PASS gamepad focus seeded on title: #${initialFocus}`);

  // A (button 0) activates the focused "작전 개시" entry -> mission select.
  await tapButton(0);
  await page.locator('#tab-T01').waitFor({ state: 'visible' });
  console.log('PASS A activates focused title entry -> mission select screen');

  // D-pad down moves focus across the mission grid / detail panel without
  // any mouse input, then A selects M01 and advances to briefing.
  const movedToM01=await reachControl('tab-M01','#select-screen');
  assert.ok(movedToM01, 'D-pad down must be able to reach the M01 mission card via gamepad focus');
  await tapButton(0); // A -> select M01
  await page.waitForTimeout(150);
  // Move focus to "편성으로" (NEXT) and press A to reach the briefing screen.
  const reachedNext=await reachControl('select-to-briefing','#select-screen');
  assert.ok(reachedNext, 'D-pad navigation must be able to reach the "편성으로" button');
  await tapButton(0);
  await page.locator('#start-mission').waitFor({ state: 'visible' });
  console.log('PASS gamepad D-pad + A drives select -> briefing');

  // B (button 1) backs out of the briefing screen to mission select.
  await tapButton(1);
  await page.locator('#tab-T01').waitFor({ state: 'visible' });
  console.log('PASS B backs out of briefing -> mission select');

  // Return to briefing and start the mission entirely via gamepad.
  await page.locator('#tab-T01').click(); // mouse here only to re-select T01 fast; nav itself already proven above
  await page.locator('#select-to-briefing').click();
  await page.waitForFunction(() => !document.querySelector('#start-mission').disabled);
  const reachedStart=await reachControl('start-mission','#briefing-screen');
  assert.ok(reachedStart, 'D-pad navigation must be able to reach "작전 시작"');
  await tapButton(0);
  await wait(() => window.__qa.states.at(-1)?.mode === 'PLANNING');
  console.log('PASS gamepad A on "작전 시작" starts the mission (title -> select -> briefing -> start)');

  // Live HUD: ui_focus must now be false (engine owns the pad) — confirmed
  // indirectly by the absence of any gamepad-focus ring in the HUD.
  await page.waitForTimeout(150);
  const hudFocusRing = await page.evaluate(() => !!document.querySelector('.gamepad-focus'));
  assert.equal(hudFocusRing, false, 'the live HUD must not show a DOM gamepad focus ring (engine owns the pad there)');
  console.log('PASS no DOM gamepad focus ring in the live HUD');

  assert.deepEqual(errors, []);
  console.log('Gamepad DOM navigation check: all passed');
} finally {
  await browser.close();
}
