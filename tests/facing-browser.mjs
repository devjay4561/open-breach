import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import {mkdir,writeFile} from 'node:fs/promises';
const url=process.env.BREACH_URL||'http://127.0.0.1:8082';
const out=process.env.BREACH_ARTIFACTS||'tests/artifacts/facing';
await mkdir(out,{recursive:true});
const browser=await chromium.launch({channel:'chrome',headless:true,args:['--enable-unsafe-swiftshader']});
const context=await browser.newContext({viewport:{width:1440,height:900}});
await context.addInitScript(()=>{let ui;window.qa={states:[],messages:[]};Object.defineProperty(window,'BreachUI',{configurable:true,get:()=>ui,set(value){ui=value;const receive=value.receive;value.receive=function(raw){const data=JSON.parse(raw);if(data.type==='state'){window.qa.states.push(data);if(window.qa.states.length>100)window.qa.states.shift()}else window.qa.messages.push(data);return receive.call(value,raw)}}})});
const page=await context.newPage(),errors=[],report={url,modes:[]};
page.on('pageerror',e=>errors.push(e.message));
page.on('console',m=>{if(m.type()==='error'||/SCRIPT ERROR|Parse Error/.test(m.text()))errors.push(m.text())});
const send=data=>page.evaluate(data=>window.BreachBridge.send(JSON.stringify(data)),data);
const state=()=>page.evaluate(()=>window.qa.states.at(-1));
const angleDistance=(a,b)=>Math.abs(Math.atan2(Math.sin(a-b),Math.cos(a-b)));
try{
for(const persistent of [false,true]){
 await page.goto(url);
 await page.waitForFunction(()=>window.BreachBridge&&!document.querySelector('#start-mission').disabled);
 await page.locator('#title-start').click();await page.locator('[data-mission="T01"]').click();
 await page.locator('#select-to-briefing').click();await page.locator('#start-mission').click();
 await page.waitForFunction(()=>window.qa.states.at(-1)?.mode==='PLANNING');
 await page.keyboard.press('Digit1');
 await page.locator('[data-tool="face"]').click();
 await page.locator('#face-options').waitFor({state:'visible'});
 assert.equal(await page.locator('[data-face-mode="normal"]').getAttribute('aria-pressed'),'true');
 if(persistent){await page.locator('[data-face-mode="persistent"]').click();await page.waitForFunction(()=>window.qa.states.at(-1)?.tool==='face_lock'&&document.querySelector('[data-face-mode="persistent"]').getAttribute('aria-pressed')==='true')}
 await page.waitForTimeout(200);
 await page.screenshot({path:`${out}/${persistent?'persistent':'normal'}-options.png`});
 await page.mouse.click(512,473);
 await page.waitForFunction(()=>window.qa.states.at(-1)?.units[0].commands.some(c=>c.type==='FACE'));
 let before=(await state()).units[0];
 const face=before.commands.find(c=>c.type==='FACE');
 assert.equal(Boolean(face.args.persistent),persistent);
 const lookAngle=Math.atan2(face.args.target[1]-before.z,face.args.target[0]-before.x);
 await send({action:'command',unit_id:'alpha',type:'MOVE',args:{target:[3.5,17.65]}});
 await page.waitForFunction(()=>window.qa.states.at(-1)?.units[0].commands.some(c=>c.type==='MOVE'));
 // Plans must preserve the explicit mode when saved and restored before execution.
 await send({action:'get_plan'});
 await page.waitForFunction(()=>window.qa.messages.some(m=>m.type==='plan_data'));
 const plan=await page.evaluate(()=>window.qa.messages.findLast(m=>m.type==='plan_data').data);
 await send({action:'load_plan',data:plan});
 await page.waitForFunction(()=>window.qa.states.at(-1)?.units[0].commands.length===2);
 assert.equal(Boolean((await state()).units[0].commands[0].args.persistent),persistent);
 await page.locator('#toggle-execution').click();
 await page.waitForFunction(()=>window.qa.states.at(-1)?.time>=0.6);
 await page.locator('#toggle-execution').click();
 await page.waitForFunction(()=>window.qa.states.at(-1)?.mode==='PLANNING');
 const after=await state(),unit=after.units[0];
 assert(unit.x<before.x-0.2,'Unit actually moves west');
 assert.equal(unit.facing_locked,persistent);assert.equal(unit.facing_persistent,persistent);
 assert(angleDistance(unit.facing,persistent?lookAngle:Math.PI)<0.1,'Facing matches the chosen mode while moving');
 await page.screenshot({path:`${out}/${persistent?'persistent':'normal'}-moving.png`});
 if(persistent){
   await page.locator('#unlock-facing').click();
   await page.waitForFunction(()=>!window.qa.states.at(-1)?.units[0].facing_locked);
   assert.equal((await state()).units[0].facing_persistent,false);assert.equal((await state()).time,after.time);
 }
 report.modes.push({persistent,time:after.time,facing:unit.facing,lookAngle,position:[unit.x,unit.z],planRoundTrip:true});
}
assert.deepEqual(errors,[]);report.status='PASS';
}catch(e){report.status='FAIL';report.error=e.stack;report.state=await state().catch(()=>null);await page.screenshot({path:`${out}/failure.png`});process.exitCode=1;}
finally{report.errors=errors;await writeFile(`${out}/report.json`,JSON.stringify(report,null,2));await browser.close();console.log(JSON.stringify(report));}
