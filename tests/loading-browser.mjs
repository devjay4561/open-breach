import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import {mkdir,writeFile,readFile} from 'node:fs/promises';
const url=process.env.BREACH_URL||'http://127.0.0.1:8082',out=process.env.BREACH_ARTIFACTS||'tests/artifacts/loading';await mkdir(out,{recursive:true});
const browser=await chromium.launch({channel:'chrome',headless:true,args:['--enable-unsafe-swiftshader']});
const context=await browser.newContext({viewport:{width:1440,height:900}});
await context.addInitScript(()=>{
 window.qa={state:null,frames:0,messages:[],opens:[],held:[]};let ui;
 function frame(){window.qa.frames++;requestAnimationFrame(frame)}requestAnimationFrame(frame);
 Object.defineProperty(window,'BreachUI',{configurable:true,get:()=>ui,set(v){ui=v;const fn=v.receive;v.receive=function(raw){const data=JSON.parse(raw),r=fn.call(v,raw);if(data.type==='state')window.qa.state=data;if(data.type==='plan_data')window.qa.plan=data.data;if(data.type==='loading')window.qa.messages.push({...data,frame:window.qa.frames,visible:document.querySelector('#transition-loading').open});return r}}});
});
const page=await context.newPage(),errors=[],report={url,checks:[]};
page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error'||/SCRIPT ERROR|Parse Error/.test(m.text()))errors.push(m.text())});
const wait=fn=>page.waitForFunction(fn,null,{timeout:30000});
const send=d=>page.evaluate(d=>window.BreachBridge.send(JSON.stringify(d)),d);
const idle=()=>wait(()=>!document.querySelector('#transition-loading').open);
async function direct(action,extra={}){const n=await page.evaluate(()=>window.qa.messages.length);await send({action,...extra});await page.waitForFunction(n=>window.qa.messages.length>=n+2&&!document.querySelector('#transition-loading').open,n);}
try{
 await page.goto(url);await wait(()=>window.BreachBridge&&!document.querySelector('#start-mission').disabled);
 await page.evaluate(()=>{const overlay=document.querySelector('#transition-loading');new MutationObserver(()=>{if(overlay.open)window.qa.opens.push(window.qa.frames)}).observe(overlay,{attributes:true,attributeFilter:['open']});const original=window.BreachBridge.send;window.qa.original=original;window.BreachBridge.send=raw=>{const d=JSON.parse(raw);if(window.qa.hold===d.action){window.qa.held.push({raw,frame:window.qa.frames,visible:overlay.open});return}return original(raw)}});
 await page.locator('#title-start').click();await page.locator('[data-mission="M06"]').click();
 await page.waitForTimeout(600);await idle();await page.locator('#select-to-briefing').click();await idle();
 await page.evaluate(()=>window.qa.hold='start');await page.locator('#start-mission').click();
 await wait(()=>window.qa.held.length===1);assert.equal(await page.locator('#transition-loading').evaluate(e=>e.open),true);
 let held=await page.evaluate(()=>({call:window.qa.held[0],opened:window.qa.opens.at(-1)}));
 assert(held.call.visible&&held.call.frame>held.opened,'Loading paints before serialization/bridge dispatch');
 await page.screenshot({path:`${out}/mission-loading.png`});
 await page.keyboard.press('Escape');await page.keyboard.press('Space');
 assert.equal(await page.locator('#transition-loading').evaluate(e=>e.open),true);
 await page.evaluate(()=>document.querySelector('#start-mission').click());assert.equal(await page.evaluate(()=>window.qa.held.length),1);
 await page.evaluate(()=>{window.qa.hold=null;window.qa.original(window.qa.held.pop().raw)});
 await wait(()=>window.qa.state?.mission.startsWith('M06')&&window.qa.state.mode==='PLANNING'&&!document.querySelector('#transition-loading').open);
 assert.equal(await page.evaluate(()=>window.qa.state.units.flatMap(u=>u.commands).length),0);report.checks.push('paint-before-bridge, duplicate-start, input-lock, M06-ready');
 await direct('retry');await send({action:'get_plan'});await wait(()=>!!window.qa.plan);await direct('load_plan',{data:await page.evaluate(()=>window.qa.plan)});await direct('retry_plan');
 // Native bridge callers also get a painted loading gap and completion ack.
 await direct('load_plan',{data:{schema_version:999}});assert((await page.evaluate(()=>window.qa.state.mission)).startsWith('M06'));
 report.checks.push('retry, saved plan, retry-plan and rejected-plan recovery');
 await direct('import_replay',{data:JSON.parse(await readFile('tests/artifacts/combat-benchmark.breach-replay.json','utf8'))});
 assert.equal(await page.evaluate(()=>window.qa.state.mode),'REPLAY');
 await direct('replay');report.checks.push('replay import and restart');
 await page.locator('#replay-library').click();await page.locator('#import-replay').click();
 await page.locator('#file-import').setInputFiles({name:'broken.json',mimeType:'application/json',buffer:Buffer.from('{bad')});
 await wait(()=>document.querySelector('#toasts').textContent.includes('파일을 열 수 없습니다.'));await idle();
 assert.equal(await page.locator('#modal').evaluate(e=>e.open),true);report.checks.push('invalid file restores library without stuck overlay');
 await page.locator('#import-replay').click();await page.locator('#file-import').setInputFiles('tests/artifacts/combat-benchmark.breach-replay.json');
 await wait(()=>!document.querySelector('#modal').open&&!document.querySelector('#transition-loading').open&&window.qa.state.mode==='REPLAY');
 report.checks.push('actual replay file input');
 const events=await page.evaluate(()=>window.qa.messages);const starts=events.filter(e=>e.active);
 for(const start of starts){const end=events.find(e=>!e.active&&e.id===start.id);assert(end,`Completion exists for ${start.action}`);assert(end.frame-start.frame>=2,'Engine gives browser paint frames before work');}
 report.transitions=events;report.errors=errors;assert.deepEqual(errors,[]);report.status='PASS';
 await page.screenshot({path:`${out}/replay-ready.png`});
}catch(e){report.status='FAIL';report.error=e.stack;report.errors=errors;report.state=await page.evaluate(()=>window.qa.state).catch(()=>null);await page.screenshot({path:`${out}/failure.png`});process.exitCode=1}finally{await writeFile(`${out}/report.json`,JSON.stringify(report,null,2));await browser.close();console.log(JSON.stringify(report));}
