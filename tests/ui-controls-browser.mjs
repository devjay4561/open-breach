// P1 1-2: the title, mission-select, briefing and HUD screens must contain
// zero native <select> elements and zero checkbox inputs (the map editor is
// explicitly excluded — it keeps native form controls for data entry). The
// redesigned menu uses Cycler (<div class="cycler">) and Toggle Card /
// Operator Card (<button aria-pressed>) components instead.
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

async function scanControls(label) {
  const violations = await page.evaluate(() => {
    const results = [];
    for (const el of document.querySelectorAll('select, input[type=checkbox]')) {
      if (el.closest('.map-editor')) continue;
      const style = getComputedStyle(el);
      if (style.visibility === 'hidden' || style.display === 'none') continue;
      const rects = el.getClientRects(); if (!rects.length) continue;
      if (el.closest('[hidden]')) continue;
      results.push({ tag: el.tagName, type: el.type, id: el.id, name: el.name });
    }
    return results;
  });
  if (violations.length) console.error(`Violations in ${label}:`, violations);
  assert.equal(violations.length, 0, `${label}: ${violations.length} native select/checkbox control(s) visible`);
  console.log(`PASS ${label}: 0 visible select/checkbox controls`);
}

try {
  await page.goto(url);
  await page.locator('#title-start').waitFor({ state: 'visible' });
  await scanControls('title');

  await page.locator('#title-start').click();
  await page.locator('#tab-T01').waitFor({ state: 'visible' });
  await scanControls('mission select');

  await page.locator('#tab-M01').click();
  await page.locator('#select-to-briefing').click();
  await page.locator('#start-mission').waitFor({ state: 'visible' });
  await scanControls('briefing');

  // Operator roster drawer (opened from the briefing screen) must also be
  // control-free — it absorbed the old 대원·장비 modal's checkboxes/selects.
  await page.locator('#prepare-squad').click();
  await page.locator('.squad-roster').waitFor({ state: 'visible' });
  await scanControls('briefing (roster drawer open)');
  await page.locator('#squad-done').click();

  await page.waitForFunction(() => !document.querySelector('#start-mission').disabled);
  await page.locator('#start-mission').click();
  await wait(() => window.__qa.states.at(-1)?.mode === 'PLANNING');
  await page.waitForTimeout(300);
  await scanControls('HUD');

  assert.deepEqual(errors, []);
  console.log('Control audit: all passed');
} finally {
  await browser.close();
}
