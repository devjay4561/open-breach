// H3: shared menu-navigation helpers for the browser test suites.
// The UI redesign replaced the old flat select-screen (`#seed-mode`,
// `#difficulty-select`, `#variant-select`, `#daily-operation`,
// `#campaign-settings`, `#open-map-editor` <select>/<button> elements that
// were always on screen) with a title screen -> mission select -> briefing
// flow, where difficulty/variant/seed-mode are `[data-cycler]` widgets on
// the briefing footer and daily-operation/campaign/map-editor are nav items
// on the title screen (`#title-daily`, `#title-campaign`, `#title-editor`).
// These helpers centralize the new navigation so every suite drives the
// same shipped DOM the same way (see tests/web-meta-ui-test.mjs, which
// already used this pattern before the other suites were ported).

// Opens a `[data-cycler]`/`[data-loadout]` root's quick-pick list and clicks
// the option for `value` (the option's `data-cycle-set`).
export async function setCycler(page, selector, value) {
  await page.locator(`${selector} output`).click();
  await page.locator(`${selector} [data-cycle-set="${value}"]`).click();
}

// Step through a cycler's next button to cover its alternate input path.
export async function stepCyclerTo(page, selector, value, maxSteps = 12) {
  for (let i = 0; i < maxSteps; i++) {
    const current = await page.locator(`${selector} [data-cycle-set]`).evaluateAll(
      buttons => buttons.find(b => b.getAttribute('aria-selected') === 'true')?.getAttribute('data-cycle-set'),
    );
    if (current === value) return;
    await page.locator(`${selector} .cycler-next`).click();
  }
  throw new Error(`stepCyclerTo: ${selector} did not reach "${value}" within ${maxSteps} steps`);
}

// Walks back to the title screen via each currently-visible screen's
// `.back-button`, however many hops that takes (select -> title,
// briefing -> select -> title, ...). No-ops if already on the title screen.
export async function backToTitle(page) {
  while (await page.locator('.menu-screen:not([hidden]) .back-button').count())
    await page.locator('.menu-screen:not([hidden]) .back-button').click();
}

// From the title screen (or anywhere — backs out first), opens mission
// select, picks `missionTab` (e.g. 'M01', 'T01') and advances to briefing.
export async function goToBriefing(page, missionTab = 'M01') {
  await backToTitle(page);
  await page.locator('#title-start').click();
  await page.locator(`#tab-${missionTab}`).waitFor({ state: 'visible' });
  await page.locator(`#tab-${missionTab}`).click();
  await page.locator('#select-to-briefing').click();
}

// Sets a single modifier toggle-card (`[data-modifier]`, aria-pressed) to
// the requested on/off state, clicking only if it isn't already there.
export async function setModifier(page, id, on) {
  const el = page.locator(`[data-modifier="${id}"]`);
  const pressed = (await el.getAttribute('aria-pressed')) === 'true';
  if (pressed !== on) await el.click();
}

// Clears every currently-active modifier toggle-card (replaces the old
// `for (checkbox of [data-modifier]) if checked -> uncheck()` loop).
export async function clearModifiers(page) {
  for (const el of await page.locator('[data-modifier][aria-pressed="true"]').all()) await el.click();
}
