import { chromium } from 'playwright';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import assert from 'node:assert/strict';

// --prepare-only checks actual renderers without Chrome or export files.
// --build-ready checks the frozen package, then uses one static DOM browser.
const prepareOnly = process.argv.includes('--prepare-only');
assert(prepareOnly || process.argv.includes('--build-ready'), 'Wait for the final package before static Chrome preflight');
const root = fileURLToPath(new URL('../', import.meta.url));
const sourceRoot = resolve(root, prepareOnly ? 'web' : 'dist');
const out = resolve(process.env.BREACH_ARTIFACTS || 'tests/artifacts/cqb-p4/static-preflight');
if (!prepareOnly) for (const name of ['index.html', 'app.js', 'style.css', 'i18n.js']) {
  assert.equal(await readFile(resolve(sourceRoot, name), 'utf8'), await readFile(resolve(root, 'web', name), 'utf8'), `Final packaged ${name} matches frozen source`);
}
const app = await readFile(resolve(sourceRoot, 'app.js'), 'utf8');
const i18nSource = await readFile(resolve(sourceRoot, 'i18n.js'), 'utf8');
const i18n = await import(`data:text/javascript;base64,${Buffer.from(i18nSource).toString('base64')}`);
const original = await readFile(resolve(sourceRoot, 'index.html'), 'utf8');
let css = await readFile(resolve(sourceRoot, 'style.css'), 'utf8');
for (const match of [...css.matchAll(/url\((?:"([^"]*)"|'([^']*)'|([^)]*))\)/g)]) {
  const path = match[1] ?? match[2] ?? match[3];
  if (path.startsWith('data:') || path.startsWith('http')) continue;
  const bytes = await readFile(resolve(sourceRoot, path));
  const mime = path.endsWith('.woff2') ? 'font/woff2' : path.endsWith('.png') ? 'image/png' : path.endsWith('.svg') ? 'image/svg+xml' : 'application/octet-stream';
  css = css.replace(match[0], `url('data:${mime};base64,${bytes.toString('base64')}')`);
}
const html = original.replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, '').replace(/<link\b[^>]*>/gi, '').replace('</head>', `<style>${css}</style></head>`);
const icons = vm.runInNewContext(`${app.slice(app.indexOf('const icons = '), app.indexOf('const icon = '))}\nicons;`);
const escapeHTML = value => String(value ?? '').replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));
function section(start, end) {
  const begin = app.indexOf(start), finish = app.indexOf(end, begin);
  assert(begin >= 0 && finish > begin, `${start} actual renderer remains available`);
  return app.slice(begin, finish).replaceAll('export function', 'function');
}
const own = ['alpha', 'bravo', 'charlie', 'delta'];
function fixture(lang, group, viewport) {
  i18n.setLanguage(lang);
  const nodes = new Map();
  let releaseInHeader = false;
  const node = id => {
    if (id === 'unlock-facing') return nodes.get(id) || null;
    if (!nodes.has(id)) nodes.set(id, {
      id, innerHTML: '', textContent: '', hidden: id === 'drill-timeline', disabled: false,
      classList: { toggle() {} }, querySelectorAll: () => [],
      querySelector: selector => selector === 'header' ? { append: () => { releaseInHeader = true; } } : null,
      append: button => { nodes.set(button.id, button); },
    });
    return nodes.get(id);
  };
  const state = {
    mode: 'PLANNING', mission: 'STATIC_FORMATION', tool: group ? 'formation' : 'select', selected: 'alpha', selected_units: group ? own : ['alpha'],
    units: own.map((id, index) => ({ id, name: id.toUpperCase(), hp: 100, facing_locked: group && index === 0, facing_persistent: group && index === 0,
      commands: group ? ['stack', 'ready', 'door', 'entry'].map((stage, commandIndex) => ({
        type: stage === 'ready' ? 'WAIT_FOR_SIGNAL' : stage === 'door' ? 'OPEN_DOOR' : 'MOVE', state: 'PENDING',
        args: { target: [6, 4], signal: 'B', delay_ticks: 0, sync_id: 'entry:ready', drill: { sync_id: 'entry', door_id: 'd1', room_id: 'room', order: index + 1, stage } },
        id: commandIndex + 1,
      })) : [] })),
  };
  const context = {
    state, $: node, $$: () => [], document: { activeElement: null, createElement: () => ({ addEventListener() {} }) },
    window: { innerWidth: viewport.width, innerHeight: viewport.height },
    t: i18n.t, getLanguage: i18n.getLanguage, translateCommandReason: i18n.translateCommandReason, escapeHTML,
    rosterName: unit => unit.name, catalog: new Map(),
    FORMATION_KINDS: ['AUTO', 'SERPENTINE', 'ROLLING_T', 'T_JUNCTION'], DRILL_STAGES: ['stack', 'ready', 'door', 'entry'],
    formationDraft: { mission: state.mission, target: [10, 4], order: own, kind: 'T_JUNCTION', signal: 'B', delay_ticks: 3600 },
    formationPreview: { ok: true, kind: 'T_JUNCTION', recommended_kind: 'ROLLING_T', corridor_width: 2.4, noise_discipline: 'hand_signals',
      slots: own.map((unit_id, index) => ({ unit_id, index: index + 1, stance: index % 2 ? 'standing' : 'crouched', target: [10, 4] })) },
    formationPending: false, lastFormationHTML: '', drillDelayDrag: null, drillTimelineGroup: '', lastDrillHTML: '',
    lastToolKey: '', toolButtons: [], faceButtons: [], refreshEquipmentMenuLabels() {}, setPressed() {}, scheduleSafeArea() {},
  };
  const icon = name => `<svg viewBox="0 0 24 24" aria-hidden="true">${icons[name] || icons.wait}</svg>`;
  context.icon = icon;
  const commandIcon = app.match(/^const commandIcon = .*;$/m)?.[0];
  assert(commandIcon);
  vm.runInNewContext(`${section('export function selectedOwnUnitIds', 'let lastUnitHP')}\n${section('const commandNames_ko', 'const toolHints =')}\n${section('const toolHints =', 'const tutorials =')}\n${commandIcon}\n${section('function commandDescription(', 'function renderCommands(')}\n${section('function renderTool()', 'function renderTutorial(')}\n${section('function renderFormation()', 'function timelineCommand(')}\n${section('function timelineCommand(', 'function updateDrillDelayHandle(')}\nrenderTool();renderDrillTimeline();renderFormation();`, context);
  const release = node('unlock-facing');
  return {
    timeline: node('drill-timeline').innerHTML,
    editor: node('formation-editor-content').innerHTML,
    error: node('formation-preview-error').textContent,
    commitDisabled: node('formation-commit').disabled,
    release: release ? `<button id="unlock-facing" class="${escapeHTML(release.className)}" title="${escapeHTML(release.title)}">${escapeHTML(release.textContent)}</button>` : '',
    releaseInHeader,
  };
}
const screens = [];
for (const viewport of [{ width: 900, height: 600 }, { width: 1280, height: 720 }, { width: 1440, height: 900 }]) {
  for (const lang of ['ko', 'en']) for (const group of [false, true]) {
    const data = fixture(lang, group, viewport);
    assert.equal(data.timeline.includes('id="formation-tool"'), group);
    assert.equal(data.releaseInHeader, group);
    assert.equal(data.commitDisabled, false);
    if (lang === 'en') assert(!/[가-힣]/.test(data.editor));
    screens.push({ viewport, lang, group, data });
  }
}
if (prepareOnly) {
  console.log(`BREACH_FORMATION_STATIC_PREPARED fixtures=${screens.length} chrome=0 status=PASS`);
} else {
  await mkdir(out, { recursive: true });
  const report = { engineLoaded: false, productScriptsExecuted: false, errors: [], requests: [], cases: [] };
  const browser = await chromium.launch({ channel: process.env.BREACH_CHANNEL || 'chrome', headless: process.env.BREACH_HEADLESS !== '0' });
  try {
    const page = await browser.newPage();
    page.on('request', request => report.requests.push(request.url()));
    page.on('pageerror', error => report.errors.push(error.message));
    await page.route('**/*', route => route.abort());
    for (const { viewport, lang, group, data } of screens) {
      i18n.setLanguage(lang);
      const labels = Object.fromEntries([...html.matchAll(/data-i18n="([^"<>]+)"/g)].map(match => [match[1], i18n.t(match[1])]));
      await page.setViewportSize(viewport); await page.setContent(html);
      await page.evaluate(({ labels, icons, group, data, lang }) => {
        document.documentElement.lang = lang;
        for (const id of ['loading', 'menu', 'result', 'replay-hud', 'pause-panel', 'restore-hud', 'room-drill-panel']) document.getElementById(id).hidden = true;
        document.getElementById('hud').hidden = false;
        for (const node of document.querySelectorAll('[data-i18n]')) node.textContent = labels[node.dataset.i18n];
        for (const node of document.querySelectorAll('[data-icon]')) node.innerHTML = `<svg viewBox="0 0 24 24" aria-hidden="true">${icons[node.dataset.icon] || icons.focus}</svg>`;
        const timeline = document.getElementById('drill-timeline'); timeline.hidden = !group; timeline.innerHTML = data.timeline;
        if (data.release) timeline.querySelector('header').insertAdjacentHTML('beforeend', data.release);
        document.getElementById('formation-panel').hidden = !group;
        document.getElementById('formation-editor-content').innerHTML = data.editor;
        document.getElementById('formation-preview-error').textContent = data.error;
        document.getElementById('formation-commit').disabled = data.commitDisabled;
      }, { labels, icons, group, data, lang });
      await page.evaluate(() => document.fonts.ready);
      await page.evaluate(async () => {
        await Promise.all(document.getAnimations().filter(animation => Number.isFinite(animation.effect?.getComputedTiming().iterations)).map(animation => animation.finished.catch(() => {})));
        document.getElementById('hud').style.setProperty('--drill-deck-height', `${Math.round(document.querySelector('.hud-hotbar').getBoundingClientRect().height)}px`);
      });
      const result = await page.evaluate(group => {
        const rect = node => { const r = node.getBoundingClientRect(); return { left: r.left, right: r.right, top: r.top, bottom: r.bottom, width: r.width, height: r.height }; };
        const inBounds = node => { const r = rect(node); return r.left >= -1 && r.right <= innerWidth + 1 && r.top >= -1 && r.bottom <= innerHeight + 1; };
        const hit = node => { const r = rect(node); return node.contains(document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2)); };
        const controls = [...document.querySelectorAll('#hotbar-controls .tools>button,#hotbar-controls .hotbar-utility>button,#hotbar-controls .signals>button,#toggle-execution,#formation-tool,#unlock-facing')].filter(node => node.getClientRects().length).map(node => ({ id: node.id || node.dataset.tool || node.dataset.signal, ...rect(node), inBounds: inBounds(node), hit: hit(node) }));
        const overlaps = [];
        for (let i = 0; i < controls.length; i++) for (let j = i + 1; j < controls.length; j++) {
          const a = controls[i], b = controls[j];
          if (Math.min(a.right, b.right) - Math.max(a.left, b.left) > .5 && Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top) > .5) overlaps.push([a.id, b.id]);
        }
        const scope = document.getElementById('formation-panel'), editor = document.getElementById('formation-editor-content');
        const editorControls = group ? [...editor.querySelectorAll('button')].map(node => { node.scrollIntoView({ block: 'nearest' }); return { id: node.dataset.formationKind || node.dataset.formationOrder || node.dataset.formationSignal || node.dataset.formationDelay, inBounds: inBounds(node), hit: hit(node), disabled: node.disabled }; }) : [];
        const note = editor.querySelector('.drill-doctrine-note');
        let noteReachable = false;
        if (group) {
          // A long doctrine paragraph may exceed the short editor viewport.
          // Its final text line must remain reachable through real scrolling.
          note.scrollIntoView({ block: 'end' });
          const range = document.createRange(); range.selectNodeContents(note);
          const line = [...range.getClientRects()].at(-1), area = rect(editor);
          noteReachable = !!line && line.top >= area.top - 1 && line.bottom <= area.bottom + 1;
        }
        const smallText = [...document.querySelectorAll('#hotbar-controls *,#drill-timeline>header *,#formation-panel *')].filter(node => node.getClientRects().length && !node.closest('[hidden]') && [...node.childNodes].some(child => child.nodeType === Node.TEXT_NODE && child.textContent.trim()) && parseFloat(getComputedStyle(node).fontSize) < 12).map(node => ({ text: node.textContent, size: getComputedStyle(node).fontSize }));
        const hotbar = rect(document.querySelector('.hud-hotbar'));
        const panel = group ? { bounds: rect(scope), headerInBounds: inBounds(scope.querySelector('header')), closeHit: hit(document.getElementById('formation-close')), commitInBounds: inBounds(document.getElementById('formation-commit')), commitHit: hit(document.getElementById('formation-commit')), noteReachable, controls: editorControls } : null;
        editor.scrollTop = 0;
        return { group, hotbar, panel, controls, overlaps, smallText, documentWidth: document.documentElement.scrollWidth, width: innerWidth, scripts: document.scripts.length, nativeInputs: scope.querySelectorAll('select,input').length, rows: document.querySelectorAll('[data-drill-row]').length };
      }, group);
      const label = `${lang}-${group ? 'formation-editor-group' : 'legacy-no-group'}-${viewport.width}x${viewport.height}`;
      report.cases.push({ label, viewport, lang, ...result });
      await page.screenshot({ path: resolve(out, `${label}.png`) });
      await writeFile(resolve(out, 'report.json'), JSON.stringify(report, null, 2));
      assert.equal(result.controls.length, group ? 16 : 14);
      assert(result.controls.every(control => control.inBounds && control.hit), `${label}: every original/new control receives its center click`);
      assert.deepEqual(result.overlaps, []); assert.deepEqual(result.smallText, []);
      assert(result.documentWidth <= viewport.width + 1); assert.equal(result.scripts, 0); assert.equal(result.nativeInputs, 0);
      if (group) {
        assert.equal(result.rows, 4);
        assert(result.panel.bounds.bottom <= result.hotbar.top - 10, `${label}: editor clears the full deck`);
        assert(result.panel.headerInBounds && result.panel.closeHit && result.panel.commitInBounds && result.panel.commitHit && result.panel.noteReachable);
        assert(result.panel.controls.every(control => control.inBounds && control.hit), `${label}: every editor choice remains reachable by actual scrolling`);
      } else { assert.equal(result.rows, 0); assert.equal(result.hotbar.height, 72); }
      console.log(`PASS ${label}`);
    }
    assert.equal(report.cases.length, 12); assert.deepEqual(report.errors, []); assert.deepEqual(report.requests, []);
    console.log(`BREACH_FORMATION_STATIC_RESULT screens=12 failures=0 status=PASS artifact=${resolve(out, 'report.json')}`);
  } finally { await browser.close(); }
}
