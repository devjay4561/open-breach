// Ordinary Chrome UI checks against the real exported Godot engine.
import assert from 'node:assert/strict';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import {chromium} from 'playwright';
import {setCycler,backToTitle,setModifier,stepCyclerTo} from './lib/menu.mjs';
const browser=await chromium.launch({headless:true,channel:process.env.BREACH_CHANNEL||'chrome',args:['--enable-unsafe-swiftshader']});
const context=await browser.newContext({viewport:{width:1440,height:1000},acceptDownloads:true});
await context.addInitScript(()=>{window.engineMeta={states:[],messages:[]};let ui;Object.defineProperty(window,'BreachUI',{configurable:true,get:()=>ui,set:value=>{ui=value;const original=value.receive;value.receive=function(raw){const message=typeof raw==='string'?JSON.parse(raw):raw;if(message.type==='state'){window.engineMeta.states.push(structuredClone(message));if(window.engineMeta.states.length>100)window.engineMeta.states.shift();}else window.engineMeta.messages.push(structuredClone(message));return original.apply(this,arguments);};}});});
const page=await context.newPage(),errors=[];page.on('pageerror',error=>errors.push(error.message));page.on('console',message=>{if(/SCRIPT ERROR|Parse Error/.test(message.text()))errors.push(message.text());});
const url=process.env.BREACH_URL||'http://127.0.0.1:8081';let checks=0;const check=(actual,expected)=>{assert.deepEqual(actual,expected);checks++;};
const latest=()=>page.evaluate(()=>window.engineMeta.states.at(-1));
const waitMode=mode=>page.waitForFunction(mode=>window.engineMeta.states.at(-1)?.mode===mode,mode,{timeout:45000});
async function menu(){await page.keyboard.press('Escape');await page.locator('#pause-menu').click();await waitMode('MENU');}
async function exportPlan(){await page.locator('#deck-more').click();const downloaded=page.waitForEvent('download');await page.locator('#export-plan').click();const download=await downloaded;const data=JSON.parse(await readFile(await download.path(),'utf8'));await page.locator('#modal-close').click();return data;}
async function importPlan(data){await page.locator('#deck-more').click();await page.locator('#import-plan').click();await page.locator('#file-import').setInputFiles({name:'shared-plan.json',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(data))});await waitMode('PLANNING');}
// H3: the select screen's old flat <select>/<button> controls
// (#difficulty-select/#variant-select/#seed-mode/#daily-operation/
// #campaign-settings/#open-map-editor) no longer exist. The flow is now
// title -> mission select (#tab-*) -> briefing (difficulty/variant/seedmode
// live as [data-cycler] widgets on the briefing footer); daily/campaign/
// editor are title-screen nav items (#title-daily/#title-campaign/
// #title-editor) reached via tests/lib/menu.mjs's backToTitle().
try {
 await page.goto(url);await page.locator('#loading').waitFor({state:'hidden',timeout:120000});
 check(await page.evaluate(()=>Object.values(window.engineMeta.messages.find(message=>message.type==='ready').catalog||{}).every(mission=>!('enemies' in mission)&&!('civilians' in mission))),true);
 await page.locator('#title-start').click();await page.locator('#tab-M01').waitFor({state:'visible'});await page.locator('#tab-M01').click();await page.locator('#select-to-briefing').click();
 await setCycler(page,'[data-cycler="difficulty"]','normal');await setCycler(page,'[data-cycler="variant"]','infiltration');
 check((await page.locator('#brief-objectives').textContent()).includes('적 경보 이전'),true);check(await page.locator('#brief-stars span').count()>=5,true);
 await setCycler(page,'[data-cycler="seedmode"]','custom');await page.locator('#custom-seed').fill('4242');await page.locator('#custom-seed').press('Tab');await setModifier(page,'night',true);
 await page.locator('#prepare-squad').click();await page.locator('.squad-members summary').click();await page.locator('[data-roster="raven"]').click();await page.locator('[data-roster="rook"]').click();await stepCyclerTo(page,'[data-loadout="echo"][data-slot="weapon"]','light');await stepCyclerTo(page,'[data-loadout="echo"][data-slot="equipment"]','none');await page.locator('#squad-done').click();await page.locator('#start-mission').click();await waitMode('PLANNING');
 let state=await latest();check(state.mission,'M01_INFILTRATION');check(state.seed,4242);check(state.variant,'infiltration');check(state.modifiers,['night']);check(state.units[0].roster_id,'echo');check(state.units[0].weapon,'light');check(state.units[0].stuns,0);check((await page.locator('#hud-code').textContent()).includes('4242'),true);
 await page.locator('#save-plan').click();await page.getByText('초기 작전 계획을 저장했습니다.',{exact:true}).waitFor();
 const plan=await exportPlan();check(plan.seed,4242);check(plan.variant,'infiltration');check(plan.modifiers,['night']);check(plan.roster[0].id,'echo');check(plan.loadout.alpha.equipment,{});
 await importPlan(plan);await page.waitForFunction(()=>window.engineMeta.messages.some(item=>item.type==='toast'&&item.message.includes('저장된 계획으로')));state=await latest();check(state.seed,4242);check(state.units[0].stuns,0);
 await menu();await backToTitle(page);await page.locator('#title-daily').click();await page.locator('#custom-seed').waitFor({state:'visible'});const daily=await page.locator('#custom-seed').inputValue();await backToTitle(page);await page.locator('#title-daily').click();await page.locator('#custom-seed').waitFor({state:'visible'});check(await page.locator('#custom-seed').inputValue(),daily);
 await backToTitle(page);await page.locator('#title-campaign').click();await page.locator('#new-ironman').click();await page.getByText('캠페인을 저장했습니다.',{exact:true}).waitFor();check((await page.locator('#campaign-summary').textContent()).includes('스턴 16 / 장약 8'),true);
 await page.reload();await page.locator('#loading').waitFor({state:'hidden',timeout:120000});check((await page.locator('#campaign-summary').textContent()).includes('아이언맨'),true);
 // Seed a valid saved campaign with losses and depleted stock, then restore it.
 await page.evaluate(async()=>{const {BreachStorage}=await import('./storage.js');const storage=new BreachStorage();await storage.open();const saved=await storage.get('progress','campaign');await storage.put('progress',{...saved,inventory:{stun:1,breach:0},injured:['raven'],lost:['echo']});});
 await page.reload();await page.locator('#loading').waitFor({state:'hidden',timeout:120000});await page.locator('#title-start').click();await page.locator('#tab-M01').waitFor({state:'visible'});await page.locator('#tab-M01').click();await page.locator('#select-to-briefing').click();await setCycler(page,'[data-cycler="difficulty"]','normal');await page.locator('#prepare-squad').click();check(await page.locator('[data-roster="raven"]').isDisabled(),true);check(await page.locator('[data-roster="echo"]').isDisabled(),true);
 for(const id of ['moss','lark','rook','kite'])await stepCyclerTo(page,`[data-loadout="${id}"][data-slot="equipment"]`,'none');await page.locator('#squad-done').click();await page.locator('#start-mission').click();await waitMode('PLANNING');
 const legacyCampaignPlan={...plan,roster:[],loadout:{}};await importPlan(legacyCampaignPlan);await page.waitForFunction(()=>window.engineMeta.states.at(-1)?.mission==='M01_INFILTRATION');state=await latest();check(state.units[0].roster_id,'moss');check(state.units.every(unit=>unit.stuns===0),true);check(state.roster.length,4);
 const overStock={...legacyCampaignPlan,loadout:{alpha:{weapon:'standard',equipment:['stun','stun']}}};await page.locator('#deck-more').click();await page.locator('#import-plan').click();await page.locator('#file-import').setInputFiles({name:'over-stock-plan.json',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(overStock))});await page.getByText('스턴 재고가 부족합니다 (2 / 1).',{exact:true}).waitFor();check((await latest()).units.every(unit=>unit.stuns===0),true);await page.locator('#modal-close').click();await menu();
 await backToTitle(page);await page.locator('#title-campaign').click();await page.locator('#leave-campaign').click();
 await backToTitle(page);await page.locator('#title-editor').click();await page.locator('#editor-template option[value="M01"]').waitFor({state:'attached'});await page.locator('#editor-template').selectOption('M01');
 const template=JSON.parse(await page.locator('[data-editor-json]').inputValue());check(template.id,'EDIT_M01');check(template.enemies.length>=6,true);check(template.enemies.some(enemy=>enemy.spawns?.length>1),true);
 await page.locator('[data-editor-play]').click();await waitMode('PLANNING');check((await latest()).mission,'EDIT_M01');check((await latest()).units.length,4);await menu();
 await backToTitle(page);await page.locator('#title-editor').click();await page.locator('.editor-json summary').click();const custom=JSON.parse(await page.locator('[data-editor-json]').inputValue());custom.win=[{type:'reach_zone',zone:[3,9,3,3]}];custom.fail=[{type:'no_civilian_loss'}];custom.seed=9876;custom.title='공유 지도';await page.locator('[data-editor-json]').fill(JSON.stringify(custom));await page.locator('[data-editor-apply]').click();await page.locator('[data-editor-play]').click();await waitMode('PLANNING');state=await latest();check(state.mission,'EDIT_CUSTOM');check(state.seed,9876);
 const customPlan=await exportPlan();check(customPlan.mission_data.id,'EDIT_CUSTOM');check(customPlan.mission_data.title,'공유 지도');
 await page.locator('#toggle-execution').click();await waitMode('RESULT');check((await latest()).result.success,true);check((await page.locator('#result-code').textContent()).includes('9876'),true);
 await page.locator('#watch-replay').click();await waitMode('REPLAY');const downloaded=page.waitForEvent('download');await page.locator('#export-replay').click();const replayDownload=await downloaded;const replay=JSON.parse(await readFile(await replayDownload.path(),'utf8'));check(replay.seed,9876);check(replay.mission_data.id,'EDIT_CUSTOM');
 await page.reload();await page.locator('#loading').waitFor({state:'hidden',timeout:120000});await page.locator('[data-open="library"]').first().click();await page.locator('#import-replay').click();await page.locator('#file-import').setInputFiles({name:'custom-replay.json',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(replay))});await waitMode('REPLAY');check((await latest()).mission,'EDIT_CUSTOM');
 await page.reload();await page.locator('#loading').waitFor({state:'hidden',timeout:120000});await page.locator('#title-start').click();await page.locator('#tab-T01').waitFor({state:'visible'});await page.locator('#tab-T01').click();await page.locator('#select-to-briefing').click();await page.locator('#load-menu-plan').click(); // No T01 plan: this remains a safe warning.
 // `[data-open="library"]` only exists on the title screen (#title-library)
 // and the replay header (#replay-library); the briefing screen the
 // previous line left us on has no library-open control of its own, so
 // back to the title screen first (H3's new title -> select -> briefing
 // flow, see tests/lib/menu.mjs) before opening the library from there.
 await backToTitle(page);await page.locator('[data-open="library"]').first().click();await page.locator('#modal-close').click();await backToTitle(page);await page.locator('#title-editor').click();await page.locator('#modal-close').click();
 // Opening the editor from the title screen leaves the T01 briefing (selectedMission is unchanged); re-enter it the ordinary way.
 await page.locator('#title-start').click();await page.locator('#tab-T01').waitFor({state:'visible'});await page.locator('#tab-T01').click();await page.locator('#select-to-briefing').click();
 // Import the saved custom plan through the ordinary menu plan picker.
 await page.locator('#prepare-squad').click();await page.locator('#squad-done').click();await page.locator('#start-mission').click();await waitMode('PLANNING');await importPlan(customPlan);await page.waitForFunction(()=>window.engineMeta.states.at(-1)?.mission==='EDIT_CUSTOM');check((await latest()).seed,9876);check((await latest()).time,0);
 check(errors,[]);await mkdir(new URL('./artifacts/',import.meta.url),{recursive:true});await page.screenshot({path:new URL('./artifacts/web-meta-engine.png',import.meta.url).pathname});await writeFile(new URL('./artifacts/web-meta-engine.json',import.meta.url),JSON.stringify({checks,errors,url},null,2));console.log(`Web meta real engine: ${checks} ordinary Chrome UI checks passed`);
} catch(error) {
 await mkdir(new URL('./artifacts/',import.meta.url),{recursive:true});
 await page.screenshot({path:new URL('./artifacts/web-meta-engine-failure.png',import.meta.url).pathname});
 await writeFile(new URL('./artifacts/web-meta-engine-failure.json',import.meta.url),JSON.stringify({checks,errors,message:error.message,state:await latest()},null,2));throw error;
} finally {await browser.close();}
