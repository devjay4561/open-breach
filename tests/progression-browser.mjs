// Public UI + IndexedDB contracts. A deterministic engine fixture isolates unlock rules.
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import {chromium} from 'playwright';
import {goToBriefing} from './lib/menu.mjs';
import {HISTORICAL_IDS} from '../web/meta.js';
const ids=['T01',...Array.from({length:9},(_,i)=>`M0${i+1}`),...HISTORICAL_IDS];
const goals=[{id:'complete',label:'작전 완료'},{id:'survival',label:'전원 생존'},{id:'no_stun',label:'스턴 미사용',stat:'stuns_used',op:'eq',value:0},{id:'no_hits',label:'피격 0',stat:'hits_taken',op:'eq',value:0}];
const catalog=ids.map(id=>({id,title:`${id} 작전`,title_en:`${id} operation`,bounds:[16,12],rooms:[],walls:[],units:['alpha','bravo'].map(id=>({id})),stars:goals,objectives:['모든 목표 완료'],objectives_en:['Complete all objectives']}));
const engine=`window.unlockTest={sent:[]};window.BreachBridge.send=raw=>{const message=JSON.parse(raw);window.unlockTest.sent.push(message);if(message._loading_id)window.BreachUI.receive({type:'loading',id:message._loading_id,active:false});if(message.action==='start')window.BreachUI.receive({type:'state',mode:'PLANNING',mission:message.mission,seed:message.seed||42,time:0,tick:0,selected:'alpha',loadout:message.loadout,roster:message.roster,units:message.roster.map(unit=>({id:unit.base_id,roster_id:unit.id,name:unit.name,hp:100,ammo:24,commands:[]})),doors:[],events:[],objectives:{}});if(message.action==='menu')window.BreachUI.receive({type:'state',mode:'MENU'});};window.Engine=class{async startGame(){window.BreachUI.receive({type:'ready',catalog:${JSON.stringify(catalog)}});window.BreachUI.receive({type:'state',mode:'MENU'});}};`;
const mime={'.js':'text/javascript','.css':'text/css','.html':'text/html','.svg':'image/svg+xml','.woff2':'font/woff2','.wav':'audio/wav'};
const server=createServer(async(req,res)=>{try{const url=new URL(req.url,'http://localhost');if(url.pathname==='/engine.js'){res.setHeader('content-type','text/javascript');res.end(engine);return;}const name=url.pathname==='/'?'index.html':url.pathname.slice(1);if(name.includes('..')){res.writeHead(400);res.end();return;}const bytes=await readFile(new URL('../web/'+name,import.meta.url));res.setHeader('content-type',mime[name.slice(name.lastIndexOf('.'))]||'application/octet-stream');res.end(bytes);}catch{res.writeHead(404);res.end();}});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const browser=await chromium.launch({channel:'chrome',headless:true});
const context=await browser.newContext({viewport:{width:1440,height:900}}),page=await context.newPage(),errors=[];
page.on('pageerror',error=>errors.push(error.message));let checks=0;
const check=(actual,expected,label)=>{assert.deepEqual(actual,expected,label);checks++;};
const artifacts=new URL('./artifacts/progression/',import.meta.url);await mkdir(artifacts,{recursive:true});
const sent=action=>page.evaluate(action=>window.unlockTest.sent.filter(message=>message.action===action),action);
const receive=data=>page.evaluate(data=>window.BreachUI.receive(data),data);
async function finish(mission,seed,success=true){await receive({type:'state',mode:'RESULT',mission,seed,tick:900+seed,time:30,stars:goals,units:[{id:'alpha',roster_id:'raven',name:'레이븐',hp:100,ammo:24,commands:[]},{id:'bravo',roster_id:'echo',name:'에코',hp:100,ammo:24,commands:[]}],result:{success,score:95,stuns_used:0,hits_taken:0},objectives:{total:2,neutralized:success?2:0},events:[]});await page.locator('#result').waitFor({state:'visible'});}
async function record(id){return page.evaluate(async id=>{const {BreachStorage}=await import('./storage.js');const storage=new BreachStorage();await storage.open();const value=await storage.get('progress',id);storage.db?.close();return value;},id);}
async function persisted(id){await page.waitForFunction(async id=>{const {BreachStorage}=await import('./storage.js');const storage=new BreachStorage();await storage.open();const value=await storage.get('progress',id);storage.db?.close();return value?.completed===true;},id);}
async function importPlan(data){await page.locator('#deck-more').click();await page.locator('#import-plan').click();await page.locator('#file-import').setInputFiles({name:'plan.json',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(data))});await page.locator('#transition-loading').waitFor({state:'hidden'});}
try{
  await page.goto(`http://127.0.0.1:${server.address().port}`);await page.locator('#loading').waitFor({state:'hidden'});
  await page.locator('#title-start').click();
  check(await page.locator('#tab-M01').getAttribute('data-unlocked'),'true');check(await page.locator('#tab-M02').getAttribute('data-unlocked'),'false');
  await page.locator('#tab-M02').click();check(await page.locator('#select-to-briefing').isDisabled(),true);
  check((await page.locator('#mission-unlock-note').textContent()).includes('M01'),true);
  const count=(await sent('start')).length;
  await page.evaluate(()=>{const button=document.querySelector('#start-mission');button.disabled=false;button.click();});
  check((await sent('start')).length,count,'start handler enforces unlock even when DOM is changed');
  await page.locator('#tab-M01').click();await page.locator('#select-to-briefing').click();await page.locator('#start-mission').click();await page.locator('#hud').waitFor({state:'visible'});
  const plan={kind:'breach-plan',schema_version:1,map_id:'M02',seed:42,units:[],loadout:{},roster:[]};
  const loadCount=(await sent('load_plan')).length;
  await importPlan(plan);check((await sent('load_plan')).length,loadCount,'imported plan cannot bypass locked map');await page.locator('#modal-close').click();
  await importPlan({...plan,map_id:'M01',loadout:{alpha:{weapon:'suppressed'}}});check((await sent('load_plan')).length,loadCount,'imported plan cannot bypass locked weapon');await page.locator('#modal-close').click();
  await finish('M01',42);await persisted('M01');
  check((await page.locator('#result-progression').textContent()).includes('+4★'),true);check((await page.locator('#result-progression').textContent()).includes('M02'),true);
  await page.locator('.result-details summary').click();
  for(const size of [{width:1280,height:720},{width:1366,height:768},{width:800,height:600}]){
    await page.setViewportSize(size);
    check(await page.locator('#result').evaluate(node=>{
      const card=node.querySelector('.result-card'),within=el=>{const r=el.getBoundingClientRect();return r.top>=0&&r.bottom<=innerHeight+1&&r.left>=0&&r.right<=innerWidth+1;};
      return card.scrollHeight<=card.clientHeight+1&&within(card)&&within(node.querySelector('.result-actions'))&&within(node.querySelector('.result-card>.note:last-child'));
    }),true,'reward debrief keeps actions visible even with expanded details');
  }
  await page.setViewportSize({width:1440,height:900});await page.waitForTimeout(1200);
  await page.screenshot({path:new URL('first-clear.png',artifacts).pathname});
  await page.locator('#result-progression [data-open="progression"]').click();
  check(await page.locator('[data-unlock-gear="shotgun"]').evaluate(node=>node.classList.contains('owned')),true);
  check(await page.locator('[data-unlock-gear="suppressed"]').evaluate(node=>node.classList.contains('owned')),false);
  await page.locator('#progression-equip').click();await page.locator('[data-loadout="raven"][data-slot="weapon"] output').click();await page.locator('[data-loadout="raven"][data-slot="weapon"] [data-cycle-set="shotgun"]').click();await page.locator('#squad-done').click();
  await page.locator('#next-mission').click();await page.locator('#hud').waitFor({state:'visible'});
  const start=(await sent('start')).at(-1);check(start.mission,'M02');check(start.loadout.alpha.weapon,'shotgun','new unlock is usable in the next operation');
  await page.locator('.hud-brand').click();await goToBriefing(page,'M02');await page.locator('#prepare-squad').click();await page.locator('.squad-members summary').click();await page.locator('[data-roster="echo"]').click();check(await page.locator('[data-customize]').count(),1,'one operator can attempt small-team star goals');await page.locator('[data-roster="raven"]').click();check(await page.locator('[data-customize]').count(),1,'empty deployment is blocked');await page.locator('#squad-done').click();await page.locator('#start-mission').click();await page.locator('#hud').waitFor({state:'visible'});check((await sent('start')).at(-1).roster.length,1,'solo deployment reaches the engine');
  await finish('M02',43,false);check((await page.locator('#result-progression').textContent()).includes('+0★'),true);check((await page.locator('#result-progression').textContent()).includes('누적 4★'),true);
  await finish('M02',44);await persisted('M02');check((await page.locator('#result-progression').textContent()).includes('누적 8★'),true);check((await page.locator('#result-progression').textContent()).includes('H01 · H02 · H03 · H04 · H06'),true);
  const attempts=(await record('M02')).attempts;
  await finish('M02',44);check((await record('M02')).attempts,attempts,'an identical result message is recorded only once');
  await receive({type:'state',mode:'REPLAY',mission:'M09',result:{success:true},units:[],events:[],replay:{duration:5,time:5,speed:1,playing:false}});
  check((await record('M02')).attempts,attempts,'watching a replay cannot award progress');check(await record('M09'),undefined);
  await finish('M02',45);check((await page.locator('#result-progression').textContent()).includes('+0★'),true,'same completed star objectives never grant repeat currency');await persisted('M02');
  await finish('EDIT_FARM',46);check((await page.locator('#result-progression').textContent()).includes('사용자 작전'),true);
  await finish('M09_ARREST',48);check((await page.locator('#result-progression').textContent()).includes('사용자 작전'),true,'custom IDs resembling unsupported official variants cannot farm unlocks');
  await page.reload();await page.locator('#loading').waitFor({state:'hidden'});await page.locator('#title-start').click();
  check(await page.locator('#tab-M03').getAttribute('data-unlocked'),'true','completed map unlock persists after reload');
  check((await page.locator('#progression-summary').textContent()).includes('★ 8'),true,'custom map grants no progression stars');
  await page.locator('[data-collection="history"]').click();check(await page.locator('#tab-H01').getAttribute('data-unlocked'),'true');check(await page.locator('#tab-H07').getAttribute('data-unlocked'),'false');
  await page.screenshot({path:new URL('historical-unlocks.png',artifacts).pathname});
  await page.locator('#select-screen [data-nav="title"]').click();await page.locator('#title-settings').click();await page.locator('[data-cycler="language"] output').click();await page.locator('[data-cycler="language"] [data-cycle-set="en"]').click();await page.locator('#modal-close').click();
  await page.locator('#title-progression').click();check(/[가-힣]/.test(await page.locator('#modal-content').textContent()),false,'new armory and unlock requirements are localized');
  check(await page.locator('[data-unlock-gear="suppressed"]').evaluate(node=>node.classList.contains('owned')),true);
  await page.screenshot({path:new URL('armory-en.png',artifacts).pathname});
  await page.locator('#progression-equip').click();check(/[가-힣]/.test(await page.locator('#modal-content').textContent()),false,'gear selection is localized');await page.locator('#squad-done').click();
  await page.locator('#title-progression').click();for(const size of [{width:1280,height:720},{width:800,height:600}]){await page.setViewportSize(size);check(await page.locator('#modal').evaluate(node=>{const rect=node.getBoundingClientRect();return rect.left>=0&&rect.right<=innerWidth+1&&rect.top>=0&&rect.bottom<=innerHeight+1;}),true,'armory stays inside the viewport');}
  await page.locator('#modal-close').click();
  await page.evaluate(async()=>{const {BreachStorage}=await import('./storage.js');const put=BreachStorage.prototype.put;BreachStorage.prototype.put=function(store,record){if(store==='progress'&&record.id==='M03')return Promise.reject(new Error('Injected storage failure'));return put.call(this,store,record);};});
  await finish('M03',47);await page.locator('#result-progression-save').getByText('Storage unavailable:',{exact:false}).waitFor();check((await page.locator('#result-progression').textContent()).includes('Total 12★'),true,'failed save keeps progress for this session with a clear warning');
  await page.reload();await page.locator('#loading').waitFor({state:'hidden'});await page.locator('#title-start').click();check((await page.locator('#progression-summary').textContent()).includes('★ 8'),true,'failed save does not pretend to persist unlocks');check(await page.locator('#tab-M04').getAttribute('data-unlocked'),'false');
  check(errors,[]);await writeFile(new URL('browser-report.json',artifacts),JSON.stringify({checks,errors,status:'PASS',browser:browser.version(),scope:'Public UI fixture + real isolated IndexedDB; excludes Godot gameplay/GPU.'},null,2));console.log(`Progression browser: ${checks} checks passed`);
}catch(error){await page.screenshot({path:new URL('failure.png',artifacts).pathname});await writeFile(new URL('browser-report.json',artifacts),JSON.stringify({checks,errors,status:'FAIL',error:error.stack},null,2));throw error;}finally{await browser.close();await new Promise(resolve=>server.close(resolve));}
