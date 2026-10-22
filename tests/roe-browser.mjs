import { chromium } from 'playwright';
import assert from 'node:assert/strict';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { setCycler } from './lib/menu.mjs';

// A short actual UI smoke. Physics, fixed STEP and replay contracts are
// covered by the native ROE suites; this test verifies the new UI surfaces.
const native = JSON.parse(await readFile('tests/artifacts/roe-browser/preflight.json', 'utf8'));
assert.equal(native.seed, 42); assert.equal(native.step, Number((1 / 30).toPrecision(15)));
assert.deepEqual(native.cases.map(item => item.roe), ['precision', 'high_intensity']);
for (const item of native.cases) {
  assert.equal(item.mission.schema_version, 6); assert.equal(item.mission.roe, item.roe);
  assert.equal(item.preview.ok, item.roe === 'high_intensity');
}
if (process.argv.includes('--prepare-only')) { console.log('BREACH_ROE_UI_PREPARE_RESULT cases=2 status=PASS'); process.exit(0); }
const out = process.env.BREACH_ARTIFACTS || 'tests/artifacts/roe-browser'; await mkdir(out, { recursive: true });
const url = new URL(process.env.BREACH_URL || 'http://127.0.0.1:8080'); url.searchParams.set('qa', '1');
const browser = await chromium.launch({ channel: process.env.BREACH_CHANNEL || 'chrome', headless: true, args: ['--enable-unsafe-swiftshader'] });
const context = await browser.newContext({ viewport: { width: 1366, height: 768 } });
await context.addInitScript(() => {
  let ui; window.roeQA = { state: null, states: [], messages: [], sent: [] };
  Object.defineProperty(window, 'BreachUI', { configurable: true, get: () => ui, set(value) {
    ui = value; const receive = value.receive;
    value.receive = function(raw) {
      const message = typeof raw === 'string' ? JSON.parse(raw) : raw;
      if (message.type === 'state') { window.roeQA.state = message; window.roeQA.states.push(message); }
      else window.roeQA.messages.push(message);
      return receive.call(this, raw);
    };
  } });
});
const page = await context.newPage(); page.setDefaultTimeout(300000);
const errors = [], failedRequests = [], report = { checks: [], errors, failedRequests, cases: [] };
page.on('pageerror', error => errors.push(error.message));
page.on('console', message => { if (message.type() === 'error' || /SCRIPT ERROR|Parse Error/.test(message.text())) errors.push(message.text()); });
page.on('response', response => { if (response.status() >= 400) errors.push(`HTTP ${response.status()} ${response.url()}`); });
page.on('requestfailed', request => failedRequests.push({ url: request.url(), error: request.failure()?.errorText }));
const dom = (fn, arg = null) => page.waitForFunction(fn, arg, { timeout: 45000 });
const ack = (fn, arg = null) => page.waitForFunction(fn, arg, { timeout: 300000 });
const send = intent => page.evaluate(intent => window.BreachBridge.send(JSON.stringify(intent)), intent);
const latest = () => page.evaluate(() => window.roeQA.state);
const pass = name => { report.checks.push(name); console.log(`PASS ${name}`); };
async function finite(selector) {
  await page.locator(selector).evaluate(async element => Promise.all(element.getAnimations({ subtree: true })
    .filter(animation => Number.isFinite(animation.effect?.getComputedTiming().endTime)).map(animation => animation.finished.catch(() => {}))));
}
async function renderAck() {
  const ready = () => {
    const hud = document.querySelector('#hud');
    return hud.hidden || parseFloat(getComputedStyle(hud).getPropertyValue('--drill-deck-height')) === Math.round(document.querySelector('.hud-hotbar').getBoundingClientRect().height);
  };
  await dom(ready);
  const token = await page.evaluate(() => {
    const token = `roe-render-${window.roeQA.sequence = (window.roeQA.sequence || 0) + 1}`, right = document.querySelector('.hud-right').getBoundingClientRect();
    window.BreachBridge.send(JSON.stringify({ action: 'set_safe_area', _quality_token: token, data: {
      left: Math.round(document.querySelector('.hud-left').getBoundingClientRect().width), top: Math.round(document.querySelector('.hud-topbar').getBoundingClientRect().height),
      right: Math.max(0, Math.round(innerWidth - Math.max(right.left, 0))), bottom: Math.round(document.querySelector('.hud-hotbar').getBoundingClientRect().height),
    } })); return token;
  });
  await ack(token => window.roeQA.states.some(state => state.quality?.ack_tokens?.includes(token)), token); await dom(ready);
}
async function language(value) {
  await page.locator('.hud-topbar [data-open="settings"]').click(); await page.locator('[data-settings-tab="gameplay"]').click();
  await setCycler(page, '[data-cycler="language"]', value); await dom(value => document.documentElement.lang === value, value);
  await page.locator('#modal-close').click(); await dom(() => !document.querySelector('#modal').open && document.activeElement === document.querySelector('#canvas'));
  await renderAck();
}
async function point([x, z], bounds) {
  return page.evaluate(({ x, z, bounds }) => {
    const canvas = document.querySelector('#canvas').getBoundingClientRect(), right = document.querySelector('.hud-right').getBoundingClientRect();
    const l = Math.round(document.querySelector('.hud-left').getBoundingClientRect().width) + 16, t = Math.round(document.querySelector('.hud-topbar').getBoundingClientRect().height) + 16;
    const r = Math.max(0, Math.round(innerWidth - Math.max(right.left, 0))) + 16, b = Math.round(document.querySelector('.hud-hotbar').getBoundingClientRect().height) + 16;
    const vertical = Math.min(.97, Math.max(.25, (innerHeight - t - b) / innerHeight)), horizontal = Math.min(.97, Math.max(.25, (innerWidth - l - r) / innerWidth));
    const scale = canvas.height / Math.max((bounds[1] + 2) / vertical, (bounds[0] + 2) / Math.max(innerWidth / innerHeight * horizontal, .1));
    return { x: canvas.left + canvas.width / 2 + (x - bounds[0] / 2) * scale + (l - r) / 2,
      y: canvas.top + canvas.height / 2 + ((z - bounds[1] / 2) * 34 - .2 * 15.5) / Math.hypot(34, 15.5) * scale + (t - b) / 2 };
  }, { x, z, bounds });
}
try {
  await page.goto(url.href, { waitUntil: 'domcontentloaded' }); await page.locator('#title-start').waitFor({ state: 'visible' });
  await ack(() => window.roeQA.state?.mode === 'MENU' && document.querySelector('#loading').hidden && !document.querySelector('#transition-loading').open && !document.querySelector('#start-mission').disabled);
  await finite('#title-screen');
  await page.evaluate(() => { const send = window.BreachBridge.send; window.BreachBridge.send = function(raw) { window.roeQA.sent.push(JSON.parse(raw)); return send.call(this, raw); }; });
  await page.locator('#title-start').click();
  for (const id of ['M01_PRECISION', 'M01_HIGH_INTENSITY']) {
    await page.locator(`[data-mission="${id}"]`).click();
    await dom(id => document.querySelector('#mission-detail').getAttribute('aria-labelledby') === `tab-${id}`, id);
    assert.equal(await page.locator(`[data-mission="${id}"] [data-roe]`).count(), 1);
  }
  await page.locator('#select-to-briefing').click();
  assert.equal(await page.locator('#briefing-roe [data-roe="high_intensity"]').count(), 1);
  assert.match(await page.locator('#briefing-roe-note').innerText(), /작전 규칙/);
  await page.locator('#start-mission').click();
  await ack(() => window.roeQA.state?.mode === 'PLANNING' && document.querySelector('#loading').hidden && !document.querySelector('#transition-loading').open);
  await finite('#hud'); await renderAck(); pass('Both authored comparison cards and real deployment briefing retain exact policy IDs');
  for (const value of ['ko', 'en']) {
    await language(value);
    for (const item of native.cases) {
      await send({ action: 'import_mission', data: item.mission });
      await ack(id => window.roeQA.state?.mission === id && window.roeQA.state.mode === 'PLANNING' && window.roeQA.state.time === 0
        && document.querySelector('#loading').hidden && !document.querySelector('#transition-loading').open, item.mission.id);
      await finite('#hud'); await renderAck();
      await page.locator('.unit-card[data-unit="alpha"]').click(); await ack(() => window.roeQA.state?.selected === 'alpha');
      const frag = page.locator('#equipment-submenu [data-tool="frag"]');
      assert.equal((await latest()).roe, item.roe); assert.equal(await frag.isDisabled(), item.roe === 'precision');
      assert.equal((await latest()).enemies.some(enemy => enemy.id === 'unseen'), false);
      if (item.roe === 'high_intensity') {
        await page.locator('#equipment-modes').click(); await frag.click(); await ack(() => window.roeQA.state?.tool === 'frag'); await renderAck();
        const target = await point(item.target, item.mission.bounds); await page.mouse.click(target.x, target.y);
        await ack(() => window.roeQA.state?.units.find(unit => unit.id === 'alpha')?.commands.some(command => command.type === 'THROW_FRAG'));
        assert.equal((await latest()).units.find(unit => unit.id === 'alpha').available_frags, 0); assert.equal(await frag.isDisabled(), true);
        await page.locator('#toggle-execution').click();
        await ack(() => window.roeQA.state?.units.find(unit => unit.id === 'alpha')?.commands.find(command => command.type === 'THROW_FRAG')?.state === 'SUCCEEDED');
        await page.locator('#toggle-execution').click(); await ack(() => window.roeQA.state?.mode === 'PLANNING');
        assert.equal((await latest()).units.find(unit => unit.id === 'alpha').frags, 0);
        assert.equal((await latest()).enemies.some(enemy => enemy.id === 'unseen'), false);
      }
      await page.locator('[data-tool="move"]').click(); await ack(() => window.roeQA.state?.tool === 'move'); await renderAck();
      const doorway = await point([10, 5.8], item.mission.bounds); await page.mouse.click(doorway.x, doorway.y, { button: 'right' });
      await page.locator('[data-door-structure]').waitFor({ state: 'visible' });
      const wallText = await page.locator('[data-door-structure]').innerText();
      assert.match(wallText, value === 'en' ? /Thin wall.*Rifle penetration/ : /얇은 벽.*소총탄 관통 가능/);
      assert.match(wallText, value === 'en' ? /Concrete.*Rifle blocked/ : /콘크리트.*소총탄 관통 불가/);
      if (value === 'en') assert.equal(/[가-힣]/.test(wallText + await frag.innerText()), false);
      await page.screenshot({ path: `${out}/${value}-${item.roe}.png` }); await page.keyboard.press('Escape');
      report.cases.push({ language: value, roe: item.roe, state: await latest(), wallText });
    }
    pass(`${value}: precision restriction, authoritative frag reservation/execution, observed wall material and penetration`);
  }
  assert.deepEqual(errors, []); assert.deepEqual(failedRequests, []); pass('No page, native or resource errors'); report.status = 'PASS';
} catch (error) {
  report.status = 'FAIL'; report.failure = String(error.stack || error); report.latest = await latest().catch(() => null);
  await page.screenshot({ path: `${out}/failure.png` }).catch(() => {}); console.error(error); process.exitCode = 1;
} finally {
  await writeFile(`${out}/report.json`, JSON.stringify(report, null, 2)); await context.close(); await browser.close();
}
console.log(`BREACH_ROE_UI_RESULT checks=${report.checks.length} failures=${report.status === 'PASS' ? 0 : 1} status=${report.status}`);
