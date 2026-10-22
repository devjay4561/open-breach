import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import {mkdir,writeFile,readFile} from 'node:fs/promises';
const out=process.env.BREACH_ARTIFACTS || 'tests/artifacts/playthrough';await mkdir(out,{recursive:true});
const url=process.env.BREACH_URL || 'http://127.0.0.1:8080';
const browser=await chromium.launch({channel:'chrome',headless:true,args:['--enable-unsafe-swiftshader']});
const ctx=await browser.newContext({viewport:{width:1440,height:900},acceptDownloads:true});
await ctx.addInitScript(()=>{let ui;window.qa={states:[],messages:[]};Object.defineProperty(window,'BreachUI',{configurable:true,get:()=>ui,set(v){ui=v;let fn=v.receive;v.receive=function(raw){const d=JSON.parse(raw);if(d.type==='state'){window.qa.states.push(d);if(window.qa.states.length>600)window.qa.states.shift()}else window.qa.messages.push(d);return fn.call(v,raw)}}})});
const p=await ctx.newPage();const errors=[];p.on('pageerror',e=>errors.push(e.message));p.on('console',m=>{if(m.type()==='error')errors.push(m.text())});
const latest=()=>p.evaluate(()=>window.qa.states.at(-1));
const wait=fn=>p.waitForFunction(fn,null,{timeout:45000});
let report={url};
try{
await p.goto(url);await p.locator('#title-start').waitFor({state:'visible'});await p.waitForFunction(()=>!document.querySelector('#start-mission').disabled);
await p.locator('#title-start').click();await p.locator('#select-to-briefing').click();await p.locator('#start-mission').waitFor({state:'visible'});
await p.screenshot({path:out+'/menu.png'});
await p.locator('#start-mission').click();await wait(()=>window.qa.states.at(-1)?.mode==='PLANNING');
await p.screenshot({path:out+'/planning.png'});
await p.keyboard.press('Digit1');
await p.mouse.click(512,473,{button:'right'});await wait(()=>window.qa.states.at(-1)?.units[0].commands.length>0);
let s=await latest();assert.equal(s.units[0].commands.at(-1).type,'MOVE');console.log('POINTER_TARGET',JSON.stringify(s.units[0].commands.at(-1).args));
await p.locator('#toggle-execution').click();await wait(()=>window.qa.states.at(-1)?.objectives.neutralized>=1);
await p.locator('#toggle-execution').click();await wait(()=>window.qa.states.at(-1)?.mode==='PLANNING');
await p.screenshot({path:out+'/first-room.png'});
await p.mouse.click(583,362);await wait(()=>window.qa.states.at(-1)?.units[0].commands.some(c=>c.type==='OPEN_DOOR'));
await p.mouse.click(720,428,{button:'right'});await wait(()=>window.qa.states.at(-1)?.units[0].commands.some(c=>c.type==='MOVE'&&c.state==='PENDING'&&c.args.target[0]>10));assert((await latest()).units[0].commands.some(c=>c.type==='OPEN_DOOR'&&c.state==='PENDING'));assert.equal((await latest()).mode,'PLANNING');console.log('PASS paused right-click preserves door plan');await p.locator('[data-tool="face"]').click();await p.mouse.click(720,310);
await p.locator('#toggle-execution').click();await wait(()=>window.qa.states.at(-1)?.objectives.neutralized>=2);
await p.locator('#toggle-execution').click();await wait(()=>window.qa.states.at(-1)?.mode==='PLANNING');
await p.screenshot({path:out+'/breach.png'});
await p.locator('#door-modes').click();await p.locator('[data-door-mode="OPEN_DOOR"]').click();await p.mouse.click(857,362);await p.mouse.click(928,422,{button:'right'});await p.locator('[data-tool="face"]').click();await p.mouse.click(928,310);
await p.locator('#toggle-execution').click();await wait(()=>window.qa.states.at(-1)?.mode==='RESULT');
s=await latest();assert.equal(s.result.success,true);assert.equal(s.objectives.neutralized,3);await p.screenshot({path:out+'/result.png'});report.result=s.result;console.log('PASS actual mouse T01 completion',JSON.stringify(s.result));
await p.locator('#watch-replay').click();await wait(()=>window.qa.states.at(-1)?.mode==='REPLAY');
await p.locator('#replay-toggle').click();await p.locator('[data-speed="4"]').click();await p.locator('[data-reveal="true"]').click();
for(let i=0;i<20;i++){await p.locator('#replay-seek').fill(String(Math.round((i%2?0.8:0.2)*s.time*20)/20));await p.locator('#replay-seek').dispatchEvent('input')}
await p.waitForTimeout(300);await p.screenshot({path:out+'/replay.png'});
const [download]=await Promise.all([p.waitForEvent('download'),p.locator('#export-replay').click()]);const path=out+'/roundtrip.breach-replay.json';await download.saveAs(path);const data=JSON.parse(await readFile(path,'utf8'));assert.equal(data.schema_version,1);assert.equal(data.map_id,'T01');assert(data.frames.length>1);report.replayBytes=(await readFile(path)).length;
await p.locator('#replay-library').click();const importButton=p.getByRole('button',{name:/리플레이.*가져|파일.*가져/}).first();await importButton.click();await p.locator('#file-import').setInputFiles(path);await p.waitForTimeout(700);assert.equal((await latest()).mode,'REPLAY');assert(!(await p.locator('#toasts').textContent()).includes('파일을 열 수 없습니다'));console.log('PASS replay 20 seeks + export + real file import');
await p.reload();await p.waitForFunction(()=>typeof window.BreachBridge?.send==='function'&&!document.querySelector('#start-mission').disabled);await p.getByRole('button',{name:/기록 보관함/}).click();await p.waitForTimeout(300);assert((await p.locator('#modal-content').textContent()).includes('T01'));console.log('PASS recorded replay persists across reload');
await p.evaluate(()=>window.BreachBridge.send(JSON.stringify({action:'load_plan',data:{schema_version:{bad:1},map_revision:1,map_id:'T01',game_build_id:'0.1.0',units:[]}})));await p.waitForTimeout(200);assert.equal((await latest()).mode,'MENU');console.log('PASS malformed plan version rejected without runtime error');
assert.deepEqual(errors,[]);report.status='passed';report.errors=errors;
}catch(e){report.status='failed';report.error=e.stack;report.lastState=await latest().catch(()=>null);report.messages=await p.evaluate(()=>window.qa.messages).catch(()=>[]);report.errors=errors;await p.screenshot({path:out+'/failure.png'});console.error(e);process.exitCode=1}
finally{await writeFile(out+'/report.json',JSON.stringify(report,null,2));await browser.close()}
process.exit(process.exitCode || 0);
