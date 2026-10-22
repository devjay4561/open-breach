// RD1 / orchestration task 2-2: settings screen — 5 tabs, persistence across
// reload, key-rebinding + conflict detection, and the colorblind palette
// swap actually changing the live --friendly/--threat tokens.
import { chromium } from 'playwright';
import assert from 'node:assert/strict';

const url = process.env.BREACH_URL || 'http://127.0.0.1:8080';
const browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--enable-unsafe-swiftshader'] });
const context = await browser.newContext({ viewport: { width: 1600, height: 900 } });
const page = await context.newPage();
const errors = [];
page.on('pageerror', e => errors.push(e.message));

try {
  await page.goto(url);
  await page.locator('#title-start').waitFor({ state: 'visible' });

  // --- open settings from the title menu ---------------------------------
  await page.locator('#title-settings').click();
  await page.locator('#modal').waitFor({ state: 'visible' });
  const tabs = await page.locator('.settings-tabs button').allTextContents();
  assert.deepEqual(tabs, ['게임플레이', '그래픽', '오디오', '조작', '접근성'], 'settings must expose exactly the 5 planned tabs in order');
  console.log('PASS settings has 5 tabs: 게임플레이/그래픽/오디오/조작/접근성');

  // Native <select>/checkbox ban extends to the settings dialog itself.
  const nativeControls = await page.evaluate(() => Array.from(document.querySelectorAll('#modal select, #modal input[type=checkbox]')).filter(el => el.getClientRects().length).length);
  assert.equal(nativeControls, 0, 'settings dialog must use Cycler/Toggle, not native select/checkbox');
  console.log('PASS settings dialog: 0 native select/checkbox controls');

  // --- 접근성 tab: UI scale + palette cyclers, screen-shake / reduced-motion toggles
  await page.locator('[data-settings-tab="accessibility"]').click();
  await page.locator('[data-cycler="palette"]').waitFor({ state: 'visible' });
  const before = await page.evaluate(() => getComputedStyle(document.body).getPropertyValue('--friendly').trim());
  await page.locator('[data-cycler="palette"] .cycler-next').click();
  await page.waitForTimeout(80);
  const after = await page.evaluate(() => getComputedStyle(document.body).getPropertyValue('--friendly').trim());
  assert.notEqual(before, after, 'switching the palette cycler must change the live --friendly token');
  const paletteAttr = await page.evaluate(() => document.body.dataset.palette);
  assert.notEqual(paletteAttr, 'default', 'body[data-palette] must reflect the selected colorblind palette');
  console.log(`PASS palette swap: --friendly ${before} -> ${after} (data-palette=${paletteAttr})`);

  // --- 조작 tab: rebinding + conflict detection + reset -------------------
  await page.locator('[data-settings-tab="controls"]').click();
  await page.locator('.gamepad-diagram').waitFor({ state: 'visible' });
  const moveKeyBefore = await page.locator('[data-bind-action="move"]').textContent();
  assert.equal(moveKeyBefore, 'Q', 'default move binding is Q per the bridge contract default');

  // Rebind "이동" (move) to "M" — must succeed and persist.
  await page.locator('[data-bind-action="move"]').click();
  await page.locator('.binding-row.capturing').waitFor({ state: 'visible' });
  await page.keyboard.press('KeyM');
  await page.waitForTimeout(80);
  const moveKeyAfter = await page.locator('[data-bind-action="move"]').textContent();
  assert.equal(moveKeyAfter, 'M', 'rebinding move to M must update the binding button label');
  console.log('PASS rebind move Q -> M');

  // Conflict: try to rebind "주시" (face) to the same M key — must be rejected.
  await page.locator('[data-bind-action="face"]').click();
  await page.locator('.binding-row.capturing').waitFor({ state: 'visible' });
  await page.keyboard.press('KeyM');
  await page.waitForTimeout(80);
  const faceKeyAfterConflict = await page.locator('[data-bind-action="face"]').textContent();
  assert.notEqual(faceKeyAfterConflict, 'M', 'a key already bound to another action must be rejected, not silently reassigned');
  console.log(`PASS rebinding conflict rejected: 주시 stays "${faceKeyAfterConflict}" when M (already 이동) is pressed`);

  // Reserved key: WASD/Space/Esc/1-4 must be rejected outright.
  await page.locator('[data-bind-action="signal"]').click();
  await page.locator('.binding-row.capturing').waitFor({ state: 'visible' });
  await page.keyboard.press('KeyW');
  await page.waitForTimeout(80);
  const signalKeyAfterReserved = await page.locator('[data-bind-action="signal"]').textContent();
  assert.notEqual(signalKeyAfterReserved, 'W', 'reserved keys (WASD/Space/Esc/1-4) must never be assignable');
  console.log(`PASS reserved-key rebind rejected: 신호 대기 stays "${signalKeyAfterReserved}" when W is pressed`);

  // Reset to default restores Q for move.
  await page.locator('#reset-bindings').click();
  await page.waitForTimeout(80);
  const moveKeyReset = await page.locator('[data-bind-action="move"]').textContent();
  assert.equal(moveKeyReset, 'Q', 'reset-to-default must restore the Q/F/E/G/C/T/R/Z defaults');
  console.log('PASS reset-to-default restores move = Q');

  // Hotbar badge in the live HUD must reflect the (now-default) binding.
  const hotbarFaceKey = await page.locator('#hotbar-key-face').textContent();
  assert.equal(hotbarFaceKey, 'F', 'hotbar key badge must track the current binding');
  console.log('PASS hotbar key badge reflects binding (face=F)');

  // --- persistence across reload ------------------------------------------
  await page.locator('[data-settings-tab="gameplay"]').click();
  await page.locator('[data-cycler="language"] .cycler-next').click();
  await page.waitForTimeout(400); // let the IndexedDB settings write settle
  const languageBefore = await page.locator('[data-cycler="language"] output').textContent();

  await page.reload();
  await page.locator('#title-start').waitFor({ state: 'visible' });
  await page.locator('#title-settings').click();
  await page.locator('[data-settings-tab="gameplay"]').click();
  const languageAfter = await page.locator('[data-cycler="language"] output').textContent();
  assert.equal(languageAfter, languageBefore, 'language setting must survive reload');
  const paletteAfterReload = await page.evaluate(() => document.body.dataset.palette);
  assert.notEqual(paletteAfterReload, 'default', 'palette setting must survive reload');
  console.log(`PASS settings persist across reload (language=${languageAfter}, palette=${paletteAfterReload})`);

  assert.deepEqual(errors, []);
  console.log('Settings screen check: all passed');
} finally {
  await browser.close();
}
