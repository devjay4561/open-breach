import { chromium } from 'playwright';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import assert from 'node:assert/strict';

// Run only after the root reports the final native/package build ready.
// No engine or product script runs in the browser: actual product renderers
// generate the fixtures in Node, then Chrome checks their real DOM/CSS.
assert(process.argv.includes('--build-ready'), 'Wait for the final build before static Chrome preflight');
const root = fileURLToPath(new URL('../', import.meta.url));
const out = resolve(process.env.BREACH_ARTIFACTS || 'tests/artifacts/cqb-p3/static-preflight');
await mkdir(out, { recursive: true });
for (const file of ['index.html', 'style.css', 'app.js', 'i18n.js', 'debrief.js']) {
  assert.equal(await readFile(resolve(root, 'dist', file), 'utf8'), await readFile(resolve(root, 'web', file), 'utf8'), `Final packaged ${file} matches the frozen source`);
}
let css = await readFile(resolve(root, 'dist/style.css'), 'utf8');
// Quoted data SVGs can themselves contain url(%23fragment). Consume the
// whole quoted CSS URL before classifying it, preserving inline SVG filters.
for (const match of [...css.matchAll(/url\((?:"([^"]*)"|'([^']*)'|([^)]*))\)/g)]) {
  const path = match[1] ?? match[2] ?? match[3];
  if (!path.startsWith('data:') && !path.startsWith('http')) {
    const data = await readFile(resolve(root, 'dist', path));
    const mime = path.endsWith('.woff2') ? 'font/woff2' : path.endsWith('.png') ? 'image/png' : path.endsWith('.svg') ? 'image/svg+xml' : 'application/octet-stream';
    css = css.replace(match[0], `url('data:${mime};base64,${data.toString('base64')}')`);
  }
}
const original = await readFile(resolve(root, 'dist/index.html'), 'utf8');
const html = original.replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, '').replace(/<link\b[^>]*>/gi, '').replace('</head>', `<style>${css}</style></head>`);
const app = await readFile(resolve(root, 'dist/app.js'), 'utf8');
const i18nSource = await readFile(resolve(root, 'dist/i18n.js'), 'utf8');
const i18n = await import(`data:text/javascript;base64,${Buffer.from(i18nSource).toString('base64')}`);
const debriefSource = await readFile(resolve(root, 'dist/debrief.js'), 'utf8');
const debrief = await import(`data:text/javascript;base64,${Buffer.from(debriefSource).toString('base64')}`);
const icons = vm.runInNewContext(`${app.slice(app.indexOf('const icons = '), app.indexOf('const icon = '))}\nicons;`);
const escapeHTML = value => String(value ?? '').replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));
const formatTime = value => { const time = Math.max(0, Number(value) || 0); return `${String(Math.floor(time / 60)).padStart(2, '0')}:${String(Math.floor(time % 60)).padStart(2, '0')}`; };
function section(start, end) {
  const begin = app.indexOf(start), finish = app.indexOf(end, begin);
  assert(begin >= 0 && finish > begin, `${start} actual renderer remains present`);
  return app.slice(begin, finish).replaceAll('export function', 'function');
}
function settingsFixture(lang, active) {
  i18n.setLanguage(lang);
  let modal;
  const context = {
    settings: { language: lang, fov: true, enemy_alerts: true, auto_pause_man_down: active },
    settingsTab: 'gameplay', currentModal: '', t: i18n.t, escapeHTML, equipmentText: (ko, en) => lang === 'en' ? en : ko,
    cyclerDefs: { language: { options: () => [{ id: 'ko', label: '한국어' }, { id: 'en', label: 'English' }], get: () => lang } },
    showModal: (title, subtitle, body) => { modal = { title, subtitle, body }; },
  };
  vm.runInNewContext(`${section('function renderCycler(', 'const cyclerDefs =')}\n${section('const SETTINGS_TABS =', 'function renderHelp()')}\nrenderSettings();`, context);
  return modal;
}
function resultFixture(lang, legacy = false) {
  i18n.setLanguage(lang);
  const ids = ['alpha', 'bravo', 'charlie', 'delta'];
  const nodes = new Map();
  const node = id => {
    if (!nodes.has(id)) nodes.set(id, { textContent: '', innerHTML: '', hidden: false, style: {}, classList: { toggle() {} }, querySelector: () => ({ classList: { toggle() {} } }) });
    return nodes.get(id);
  };
  const state = {
    mode: 'RESULT', mission: 'M01', seed: 42, tick: 300, time: 78.2, variant: 'standard', can_retry_plan: true,
    units: ids.map((id, index) => ({ id, name: id.toUpperCase(), hp: 100 - index * 10, hits_taken: index, kills: index, arrests: 1, commands: [{ state: 'SUCCEEDED' }] })),
    result: { success: true, score: 94, rank: 'A', hits_taken: 6, rear_hits: legacy ? undefined : 3, units_deployed: 4, unlawful_shots: legacy ? 0 : 1, plan_revisions: 1, first_alert_time: 5, shots_fired: 47, kills: 4, arrests: 2, reloads: 3 },
    objectives: { neutralized: 6, total: 6, rescued: 2, civilians_total: 2 },
    stars: [{ id: 'complete', label: lang === 'en' ? 'Mission complete' : '임무 완료' }, { id: 'survival', label: lang === 'en' ? 'Full squad survives' : '전원 생존' }, { id: 'no_hits', label: '피격 0', stat: 'hits_taken', op: 'eq', value: 0 }, { id: 'no_kills', label: '사살 없이 완료', stat: 'kills', op: 'eq', value: 0 }, { id: 'single_plan', label: '한 번의 계획', stat: 'plan_revisions', op: 'eq', value: 0 }],
  };
  const context = {
    state, resultKey: '', $: node, t: i18n.t, getLanguage: i18n.getLanguage, localize: i18n.localize, escapeHTML, formatTime,
    conditionKey: () => 'fixture', progress: new Map(), parTimes: { M01: 240 }, summarizeRun: debrief.summarizeRun,
    STAR_LABELS_EN: { no_hits: 'No hits', no_kills: 'No kills', single_plan: 'Single plan' },
    ROSTER: [], unitHitCount: new Map(), requestAnimationFrame: fn => fn(),
    animateCountUp: (element, value) => { element.textContent = String(value); }, renderResultReplayPreview() {},
    resultRewards: { stars: 5, unlocks: [{ id: 'shotgun', label: '산탄총', label_en: 'Shotgun' }] },
    unlockProfile: { stars: 18 }, isProgressionMission: () => true, nextStarReward: () => ({ stars: 25, label: '신규 장비', label_en: 'New equipment' }),
    rewardName: item => i18n.localize(item, 'label'), storeAvailable: true, progressSaveFailed: false,
  };
  const resultRenderer = section('function renderResult(){', '  const saveRecord=') + '\n}';
  vm.runInNewContext(`${section('export function resultStatistics', 'function renderResult()')}\n${resultRenderer}\n${section('function renderResultOperators', '// RC: replay preview')}\n${section('function renderResultProgression()', 'function renderMissionGrid()')}\nrenderResult();renderResultProgression();`, context);
  node('next-mission').textContent = i18n.t('result.next', { name: lang === 'en' ? 'Sealed Archive' : '닫힌 기록실' });
  return Object.fromEntries([...nodes].map(([id, value]) => [id, { text: value.textContent, html: value.innerHTML, hidden: value.hidden }]));
}
const browser = await chromium.launch({ channel: process.env.BREACH_CHANNEL || 'chrome', headless: process.env.BREACH_HEADLESS !== '0' });
const report = { engineLoaded: false, productScriptsExecuted: false, errors: [], requests: [], cases: [] };
try {
  const context = await browser.newContext();
  const page = await context.newPage();
  page.on('request', request => report.requests.push(request.url()));
  page.on('pageerror', error => report.errors.push(error.message));
  await page.route('**/*', route => route.abort());
  for (const viewport of [{ width: 900, height: 600 }, { width: 1280, height: 720 }, { width: 1440, height: 900 }]) {
    await page.setViewportSize(viewport);
    for (const lang of ['ko', 'en']) for (const view of ['settings', 'result']) {
      i18n.setLanguage(lang);
      const fixture = view === 'settings' ? settingsFixture(lang, true) : resultFixture(lang);
      const labels = Object.fromEntries([...html.matchAll(/data-i18n(?:-html)?="([^"<>]+)"/g)].map(match => [match[1], i18n.t(match[1])]));
      await page.setContent(html);
      await page.evaluate(({ fixture, icons, labels, view, lang }) => {
        document.documentElement.lang = lang;
        for (const id of ['loading', 'menu', 'hud', 'replay-hud', 'pause-panel', 'restore-hud']) document.getElementById(id).hidden = true;
        for (const node of document.querySelectorAll('[data-i18n]')) node.textContent = labels[node.dataset.i18n];
        for (const node of document.querySelectorAll('[data-i18n-html]')) node.innerHTML = labels[node.dataset.i18nHtml];
        for (const node of document.querySelectorAll('[data-icon]')) node.innerHTML = `<svg viewBox="0 0 24 24" aria-hidden="true">${icons[node.dataset.icon] || icons.focus}</svg>`;
        if (view === 'settings') {
          document.getElementById('modal-title').textContent = fixture.title;
          document.getElementById('modal-eyebrow').textContent = fixture.subtitle;
          document.getElementById('modal-content').innerHTML = fixture.body;
          document.getElementById('modal').showModal();
        } else {
          for (const [id, value] of Object.entries(fixture)) {
            const node = document.getElementById(id); if (!node) continue;
            if (value.html) node.innerHTML = value.html; else if (value.text) node.textContent = value.text;
            node.hidden = value.hidden;
          }
          document.getElementById('result').hidden = false;
          document.querySelector('.result-details').open = true;
        }
      }, { fixture, icons, labels, view, lang });
      await page.evaluate(() => document.fonts.ready);
      await page.evaluate(async () => {
        await Promise.all(document.getAnimations().filter(animation => Number.isFinite(animation.effect?.getComputedTiming().iterations)).map(animation => animation.finished.catch(() => {})));
      });
      const result = await page.evaluate(({ view }) => {
        const rect = node => { const r = node.getBoundingClientRect(); return { left: r.left, right: r.right, top: r.top, bottom: r.bottom, width: r.width, height: r.height }; };
        const inBounds = node => { const r = rect(node); return r.left >= 0 && r.right <= innerWidth && r.top >= 0 && r.bottom <= innerHeight; };
        const hit = node => { const r = rect(node); return node.contains(document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2)); };
        const scope = document.querySelector(view === 'settings' ? '#modal' : '#result');
        const smallText = [...scope.querySelectorAll('*')].filter(node => node.getClientRects().length && !node.closest('[hidden]') && [...node.childNodes].some(child => child.nodeType === Node.TEXT_NODE && child.textContent.trim()) && parseFloat(getComputedStyle(node).fontSize) < 12).map(node => ({ tag: node.tagName, text: node.textContent.trim(), size: getComputedStyle(node).fontSize }));
        if (view === 'settings') {
          const modal = scope, header = modal.querySelector('header'), buttons = [...modal.querySelectorAll('button')].filter(node => node.getClientRects().length);
          const controls = buttons.map(node => { node.scrollIntoView({ block: 'nearest' }); return { id: node.id || node.dataset.settingsTab || node.dataset.settingToggle || node.className, inBounds: inBounds(node), hit: hit(node) }; });
          const toggle = modal.querySelector('[data-setting-toggle="auto_pause_man_down"]'); toggle.scrollIntoView({ block: 'nearest' });
          const suffix = getComputedStyle(toggle.querySelector('strong'), '::after').content;
          const toggleVisible = inBounds(toggle) && hit(toggle), pressed = toggle.getAttribute('aria-pressed');
          const footer = modal.querySelector('.dialog-footer');
          modal.scrollTop = modal.scrollHeight;
          const finalNote = modal.querySelector('.settings-tab-body .note:last-child');
          const finalNoteReachable = inBounds(finalNote) && rect(finalNote).bottom <= rect(footer).top + 1;
          const footerControls = [...footer.querySelectorAll('button')].every(node => inBounds(node) && hit(node));
          modal.scrollTop = 0;
          return { view, bounds: rect(modal), headerInBounds: inBounds(header), controls, toggleVisible, pressed, suffix, finalNoteReachable, footerControls, nativeControls: modal.querySelectorAll('select,input[type="checkbox"]').length, smallText, scriptCount: document.scripts.length };
        }
        const card = scope.querySelector('.result-card'), grid = scope.querySelector('.result-grid'), stats = scope.querySelector('.result-stats');
        const rows = [...stats.querySelectorAll('div')].map(node => ({ label: node.querySelector('dt').textContent, value: node.querySelector('dd').textContent }));
        const reachableRows = [...stats.querySelectorAll('div')].map(node => { node.scrollIntoView({ block: 'nearest' }); const r = rect(node), s = rect(stats), g = rect(grid); return r.top >= Math.max(s.top, g.top) - 1 && r.bottom <= Math.min(s.bottom, g.bottom) + 1; });
        stats.scrollTop = stats.scrollHeight; grid.scrollTop = grid.scrollHeight;
        const actions = [...scope.querySelectorAll('.result-actions button')].filter(node => node.getClientRects().length).map(node => ({ id: node.id || node.dataset.action, inBounds: inBounds(node), hit: hit(node) }));
        const note = card.querySelector(':scope>.note:last-child');
        grid.scrollTop = 0; stats.scrollTop = 0;
        return { view, bounds: rect(card), cardScrollOverflow: card.scrollHeight > card.clientHeight + 1, actions, noteInBounds: inBounds(note), rows, reachableRows, smallText, scriptCount: document.scripts.length };
      }, { view });
      result.lang = lang; result.viewport = viewport;
      report.cases.push(result);
      const label = `${lang}-${view}-${viewport.width}x${viewport.height}`;
      await page.screenshot({ path: resolve(out, `${label}.png`) });
      await writeFile(resolve(out, 'report.json'), JSON.stringify(report, null, 2));
      assert.equal(result.scriptCount, 0);
      assert.deepEqual(result.smallText, []);
      assert(result.bounds.top >= 0 && result.bounds.bottom <= viewport.height && result.bounds.left >= 0 && result.bounds.right <= viewport.width);
      if (view === 'settings') {
        assert(result.headerInBounds && result.toggleVisible && result.finalNoteReachable && result.footerControls);
        assert(result.controls.every(control => control.inBounds && control.hit));
        assert.equal(result.nativeControls, 0);
        assert.equal(result.pressed, 'true');
        assert(result.suffix.includes(i18n.t('settings.applied')));
        // The same actual renderer's false state removes the applied suffix.
        const inactive = settingsFixture(lang, false);
        await page.evaluate(body => { document.getElementById('modal-content').innerHTML = body; }, inactive.body);
        assert.equal(await page.locator('[data-setting-toggle="auto_pause_man_down"]').getAttribute('aria-pressed'), 'false');
      } else {
        assert(!result.cardScrollOverflow && result.noteInBounds && result.actions.every(action => action.inBounds && action.hit));
        assert.equal(result.rows.length, 15);
        assert(result.reachableRows.every(Boolean), 'Every stat row remains reachable by real DOM scrolling');
        assert.equal(result.rows.find(row => row.label === i18n.t('stat.rear_hits')).value, '3');
        const legacy = resultFixture(lang, true);
        await page.evaluate(content => { document.getElementById('result-stats').innerHTML = content; }, legacy['result-stats'].html);
        assert.equal(await page.locator('#result-stats>div').count(), 14);
        assert.equal(await page.locator('#result-stats>div').filter({ has: page.locator('dt', { hasText: i18n.t('stat.rear_hits') }) }).locator('dd').textContent(), '0');
      }
      console.log(`PASS ${label}`);
    }
  }
  assert.equal(report.cases.length, 12);
  assert.deepEqual(report.requests, []);
  assert.deepEqual(report.errors, []);
  console.log(`BREACH_ROOM_CONTROL_STATIC_RESULT screens=12 failures=0 status=PASS artifact=${out}/report.json`);
} finally {
  await browser.close();
}
