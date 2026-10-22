// 0-4: minimum font size 12px at --ui-scale 1, everywhere in the game UI
// (map editor excluded). Loads the main menu and the in-game HUD (planning
// and executing) and asserts no visible element has a computed font-size
// below 12px.
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
});
const page = await context.newPage();
const errors = [];
page.on('pageerror', e => errors.push(e.message));
const wait = fn => page.waitForFunction(fn, null, { timeout: 45000 });

async function scanMinFontSize(label) {
  const violations = await page.evaluate(() => {
    const results = [];
    for (const el of document.querySelectorAll('body *')) {
      if (el.closest('.map-editor')) continue;
      const rects = el.getClientRects();
      if (!rects.length) continue;
      const style = getComputedStyle(el);
      if (style.visibility === 'hidden' || style.display === 'none') continue;
      // Only count elements carrying their own visible text node.
      const hasOwnText = Array.from(el.childNodes).some(n => n.nodeType === 3 && n.textContent.trim().length);
      if (!hasOwnText) continue;
      const size = parseFloat(style.fontSize);
      if (size < 12) results.push({ selector: el.tagName + (el.id ? `#${el.id}` : '') + (el.className ? `.${String(el.className).split(' ').join('.')}` : ''), size, text: el.textContent.trim().slice(0, 30) });
    }
    return results;
  });
  if (violations.length) console.error(`Violations in ${label}:`, violations);
  assert.equal(violations.length, 0, `${label}: ${violations.length} element(s) below 12px`);
  console.log(`PASS ${label}: no visible text below 12px`);
}

try {
  await page.goto(url);
  await page.locator('#title-start').waitFor({ state: 'visible' });
  await page.waitForFunction(() => !document.querySelector('#start-mission').disabled);
  await page.waitForTimeout(300);
  await scanMinFontSize('title screen');

  await page.locator('#title-start').click();
  await page.locator('#tab-M01').waitFor({ state: 'visible' });
  await scanMinFontSize('mission select');
  await page.locator('#tab-M01').click();
  await page.locator('#select-to-briefing').click();
  await page.waitForTimeout(150);
  await scanMinFontSize('briefing');
  await page.locator('#start-mission').click();
  await wait(() => window.__qa.states.at(-1)?.mode === 'PLANNING');
  await page.waitForTimeout(400);
  await scanMinFontSize('HUD / planning');

  await page.locator('#toggle-execution').click();
  await wait(() => window.__qa.states.at(-1)?.mode === 'EXECUTING');
  await page.waitForTimeout(400);
  await scanMinFontSize('HUD / executing');

  assert.deepEqual(errors, []);
  console.log('Typography check: all passed');
} finally {
  await browser.close();
}
