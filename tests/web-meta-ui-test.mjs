// UI contract checks use the public bridge with a deterministic engine fixture.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { chromium } from 'playwright';
const fixture=[];
for(const id of ['T01','M01','M02','M03','M01H','M02H','M03H','M01_ESCORT','M01_INFILTRATION','M01_TIMED','M01_HOSTAGE','M01_ARREST'])fixture.push({id,title:id+' 작전',variant:id.includes('_')?id.split('_')[1].toLowerCase():'standard',seed:1024,units:Array.from({length:id.startsWith('M01')?4:2},(_,index)=>({id:['alpha','bravo','charlie','delta'][index]})),stars:[{id:'single_plan',label:'단일 계획 클리어',stat:'plan_revisions',op:'eq',value:0},{id:'no_hits',label:'피격 0',stat:'hits_taken',op:'eq',value:0}],win:[{type:id.endsWith('INFILTRATION')?'reach_zone':'neutralize_all'}],fail:[],objectives:['모든 목표 달성']});
const engine=`window.metaTest={sent:[]};window.BreachBridge.send=text=>{const data=JSON.parse(text);window.metaTest.sent.push(data);if(data._loading_id)window.BreachUI.receive({type:'loading',active:false,id:data._loading_id});};window.Engine=class{async startGame(){window.BreachUI.receive({type:'ready',briefings:${JSON.stringify(fixture)}});}};`;
const mime={'.js':'text/javascript','.css':'text/css','.html':'text/html','.svg':'image/svg+xml'};
const server=createServer(async(req,res)=>{try{const url=new URL(req.url,'http://localhost');if(url.pathname==='/engine.js'){res.setHeader('content-type','text/javascript');res.end(engine);return;}const name=url.pathname==='/'?'index.html':url.pathname.slice(1);if(name.includes('..')){res.writeHead(400);res.end();return;}const bytes=await readFile(new URL('../web/'+name,import.meta.url));res.setHeader('content-type',mime[name.slice(name.lastIndexOf('.'))]||'application/octet-stream');res.end(bytes);}catch{res.writeHead(404);res.end();}});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const browser=await chromium.launch({headless:true,...(process.env.BREACH_CHANNEL?{channel:process.env.BREACH_CHANNEL}:{})});
const page=await browser.newPage({viewport:{width:1440,height:1000}}),errors=[];page.on('pageerror',error=>errors.push(error.message));let checks=0;
const check=(actual,expected)=>{assert.deepEqual(actual,expected);checks++;};
const last=async action=>{await page.locator('#transition-loading').waitFor({state:'hidden'});await page.waitForFunction(action=>window.metaTest.sent.some(item=>item.action===action),action);return page.evaluate(action=>window.metaTest.sent.filter(item=>item.action===action).at(-1),action);};
// RB: Cycler helper — click the output to open the quick-pick list, then
// click the option. `selector` is any `[data-cycler]`/`[data-loadout]` root.
const setCycler=async(selector,value)=>{await page.locator(`${selector} output`).click();await page.locator(`${selector} [data-cycle-set="${value}"]`).click();};
const backToTitle=async()=>{while(await page.locator('.menu-screen:not([hidden]) .back-button').count())await page.locator('.menu-screen:not([hidden]) .back-button').click();};
try {
 await page.goto(`http://127.0.0.1:${server.address().port}`);await page.locator('#loading').waitFor({state:'hidden'});
 await page.locator('#title-start').click();
 check(await page.locator('.board-heading h1').textContent(),'작전현황판');
 check(await page.locator('#select-screen').evaluate(node=>getComputedStyle(node).backgroundColor),'rgb(13, 19, 16)');
 check(await page.locator('#mission-detail').evaluate(node=>getComputedStyle(node).backgroundColor),'rgb(20, 28, 23)');
 await page.locator('#tab-M01').click();await page.locator('#select-to-briefing').click();
 await setCycler('[data-cycler="difficulty"]','normal');
 await setCycler('[data-cycler="seedmode"]','custom');await page.locator('#custom-seed').fill('4242');await page.locator('#custom-seed').press('Tab');
 await setCycler('[data-cycler="variant"]','infiltration');
 check(await page.locator('[data-cycler="difficulty"] .cycler-prev').isDisabled(),true);check(await page.locator('#brief-objectives').textContent(),'표시된 목적 구역 도달');
 await page.locator('[data-modifier="night"]').click();await page.locator('#start-mission').click();const start=await last('start');check(start.mission,'M01_INFILTRATION');check(start.seed,4242);check(start.modifiers,['night']);check(start.roster.length,4);check(start.loadout.alpha.weapon,'standard');
 await page.evaluate(()=>window.BreachUI.receive({type:'state',mode:'PLANNING',mission:'M01_INFILTRATION',seed:4242,selected:'alpha',units:[{id:'alpha',name:'레이븐',hp:100,ammo:24,stuns:1,commands:[{type:'MOVE',state:'PENDING',args:{target:[5,4]}}]}],objectives:{total:3,civilians_total:0},selected_command:0}));
 check((await page.locator('#hud-code').textContent()).includes('4242'),true);check(await page.locator('.selected-command').count(),1);
 await page.evaluate(()=>window.BreachUI.receive({type:'context',target:'door',id:'d1',unit_id:'alpha',screen:[800,400],actions:['OPEN_DOOR','KICK_DOOR','PEEK_DOOR','HOLD_AT_DOOR'],disabled:{PEEK_DOOR:'이미 열린 문입니다'}}));
 check(await page.locator('#context-popover button').count(),4);check(await page.locator('#context-popover [data-context-index="2"]').isDisabled(),true);await page.keyboard.press('2');const command=await last('command');check(command.type,'KICK_DOOR');check(command.args.door_id,'d1');check(await page.locator('#context-popover').isVisible(),false);
 await page.evaluate(()=>window.BreachUI.receive({type:'context',target:'unit',id:'alpha',unit_id:'alpha',screen:[800,400],actions:['WAIT_3'],disabled:{}}));await page.keyboard.press('Escape');check(await page.locator('#context-popover').isVisible(),false);check((await last('context_close')).action,'context_close');
 await page.evaluate(()=>window.BreachUI.receive({type:'context',target:'waypoint',id:'alpha',unit_id:'alpha',index:0,point:[5,4],screen:[800,400],actions:['WAIT_5'],disabled:{}}));await page.locator('#context-popover button').click();const insert=await last('insert');check(insert.index,1);check(insert.type,'WAIT');check(insert.args.duration,5);
 await page.locator('#door-modes').click();check(await page.locator('#door-submenu button').count(),6);await page.keyboard.press('3');check((await last('tool')).door_mode,'PEEK_DOOR');
 const plan={kind:'breach-plan',schema_version:1,map_id:'M01_INFILTRATION',seed:4242,variant:'infiltration',modifiers:['night'],loadout:start.loadout,roster:start.roster,units:[]};
 await page.evaluate(data=>window.BreachUI.receive({type:'plan_data',data}),plan);await page.getByText('초기 작전 계획을 저장했습니다.',{exact:true}).waitFor();
 await page.locator('#deck-more').click();await page.locator('#modal-load-plan').click();await page.waitForFunction(()=>window.metaTest.sent.some(item=>item.action==='load_plan'));check((await last('load_plan')).data.seed,4242);check((await last('load_plan')).data.modifiers,['night']);
 await page.evaluate(()=>window.BreachUI.receive({type:'state',mode:'MENU'}));await backToTitle();await page.locator('#title-daily').click();const dailySeed=await page.locator('#custom-seed').inputValue();await backToTitle();await page.locator('#title-daily').click();check(await page.locator('#custom-seed').inputValue(),dailySeed);
 await backToTitle();await page.locator('#title-campaign').click();await page.locator('#new-ironman').click();await page.getByText('캠페인을 저장했습니다.',{exact:true}).waitFor();check((await page.locator('#campaign-summary').textContent()).includes('아이언맨'),true);
 await page.locator('#prepare-squad').click();check(await page.locator('[data-roster]').count(),8);check(await page.locator('[data-customize]').count(),4);await page.locator('#squad-done').click();
 await page.evaluate(()=>window.BreachUI.receive({type:'state',mode:'RESULT',mission:'M01',seed:42,variant:'normal',time:50,tick:1000,stars:[{id:'no_hits',label:'피격 0',stat:'hits_taken',op:'eq',value:0}],result:{success:true,score:90,stuns_used:2,breaches_used:1,hits_taken:0,kills:0},units:[{id:'alpha',roster_id:'raven',hp:30},{id:'bravo',roster_id:'echo',hp:0},{id:'charlie',roster_id:'moss',hp:100},{id:'delta',roster_id:'lark',hp:100}],objectives:{total:3,neutralized:3}}));
 check((await page.locator('#result-code').textContent()).includes('42'),true);check(await page.locator('#result-goals .achieved').count(),1);
 await page.locator('#next-mission').click();const campaignStart=await last('start');check(campaignStart.mission,'M02');check(campaignStart.roster.map(unit=>unit.id),['moss','lark']);
 await page.evaluate(()=>window.BreachUI.receive({type:'state',mode:'MENU'}));await page.locator('#prepare-squad').click();check(await page.locator('[data-roster="raven"]').isDisabled(),true);check(await page.locator('[data-roster="echo"]').isDisabled(),true);await page.locator('#squad-done').click();check((await page.locator('#campaign-summary').textContent()).includes('스턴 14 / 장약 7'),true);
 await backToTitle();await page.locator('#title-editor').click();check(await page.locator('[data-editor-canvas]').count(),1);check((await last('editor_catalog')).action,'editor_catalog');
 await page.evaluate(async()=>{const {createEditorMission}=await import('./map-editor.js');const source=createEditorMission();source.id='M01';window.BreachUI.receive({type:'editor_catalog',catalog:{M01:source}});});await page.locator('#editor-template').selectOption('M01');check(JSON.parse(await page.locator('[data-editor-json]').inputValue()).id,'EDIT_M01');check((await page.locator('[data-editor-title]').inputValue()).includes('사용자 맵'),true);await page.locator('#modal-close').click();
 check(errors,[]);console.log(`Web meta UI: ${checks} checks passed (public bridge fixture)`);
} finally {await browser.close();await new Promise(resolve=>server.close(resolve));}
