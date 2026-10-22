import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import {mkdir,writeFile} from 'node:fs/promises';
const out='tests/artifacts/auto-doors';await mkdir(out,{recursive:true});
const browser=await chromium.launch({channel:'chrome',headless:true,args:['--enable-unsafe-swiftshader']});
const context=await browser.newContext({viewport:{width:1440,height:900}});
await context.addInitScript(()=>{let ui;window.qa={state:null};Object.defineProperty(window,'BreachUI',{get:()=>ui,set(v){ui=v;const receive=v.receive;v.receive=function(raw){const d=JSON.parse(raw);if(d.type==='state')window.qa.state=d;return receive.call(v,raw)}}})});
const page=await context.newPage();const errors=[];
page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error'||/SCRIPT ERROR/.test(m.text()))errors.push(m.text())});
const send=async value=>page.evaluate(v=>window.BreachBridge.send(JSON.stringify(v)),value);
const state=()=>page.evaluate(()=>window.qa.state);
const report=[];
try{
await page.goto(process.env.BREACH_URL||'http://127.0.0.1:8080');
await page.waitForFunction(()=>window.BreachBridge?.send&&!document.querySelector('#start-mission').disabled,null,{timeout:120000});
for(const mission of ['T01','M01']){
 await send({action:'start',mission});await page.waitForFunction(m=>window.qa.state?.mission===m&&window.qa.state.mode==='PLANNING',mission);
 await send({action:'select',id:'alpha'});
 if(mission==='T01')await page.mouse.click(928,422,{button:'right'});
 else await send({action:'command',type:'MOVE',args:{target:[12,15.5]}});
 await page.waitForFunction(()=>window.qa.state?.units[0].commands.some(c=>c.type==='MOVE'));
 const planned=await state();const commands=planned.units[0].commands;
 assert.deepEqual(commands.filter(c=>c.type==='OPEN_DOOR').map(c=>c.args.door_id),mission==='T01'?['d1','d2']:['d1']);
 assert.equal(planned.time,0);await page.screenshot({path:out+'/'+mission+'-plan.png'});
 await send({action:'toggle'});
 await page.waitForFunction(()=>{const s=window.qa.state;return s?.mode==='RESULT'||s?.units[0].commands.at(-1)?.state==='SUCCEEDED'||s?.command_failures>0},null,{timeout:60000});
 const done=await state();assert.equal(done.command_failures,0);assert.equal(done.units[0].commands.at(-1).state,'SUCCEEDED');
 await send({action:'pause'});await page.screenshot({path:out+'/'+mission+'-arrival.png'});
 report.push({mission,doors:commands.filter(c=>c.type==='OPEN_DOOR').length,time:done.time,failures:done.command_failures});console.log('PASS',JSON.stringify(report.at(-1)));
}
assert.deepEqual(errors,[]);
}finally{await writeFile(out+'/report.json',JSON.stringify({report,errors},null,2));await browser.close()}
