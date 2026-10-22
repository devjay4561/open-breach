import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import {mkdir,writeFile} from 'node:fs/promises';
const out='tests/artifacts/combat-effects';await mkdir(out,{recursive:true});
const browser=await chromium.launch({channel:'chrome',headless:true,args:['--enable-unsafe-swiftshader']});
const context=await browser.newContext({viewport:{width:1440,height:900}});
await context.addInitScript(()=>{let ui;window.qa={state:null};Object.defineProperty(window,'BreachUI',{get:()=>ui,set(v){ui=v;const receive=v.receive;v.receive=function(raw){const d=JSON.parse(raw);if(d.type==='state')window.qa.state=d;if(d.type==='sound'&&d.name==='shot'&&!window.qa.caught){window.qa.caught=true;window.BreachBridge.send(JSON.stringify({action:'pause'}));}return receive.call(v,raw)}}})});
const page=await context.newPage();const errors=[];
page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error'||/SCRIPT ERROR/.test(m.text()))errors.push(m.text())});
const send=async value=>page.evaluate(v=>window.BreachBridge.send(JSON.stringify(v)),value);
const state=()=>page.evaluate(()=>window.qa.state);
const report=[];
try{
await page.goto(process.env.BREACH_URL||'http://127.0.0.1:8080');
await page.waitForFunction(()=>window.BreachBridge?.send&&!document.querySelector('#start-mission').disabled,null,{timeout:120000});
for(const mission of ['T01']){
 await send({action:'start',mission});await page.waitForFunction(m=>window.qa.state?.mission===m&&window.qa.state.mode==='PLANNING',mission);
 await send({action:'select',id:'alpha'});
 if(mission==='T01')await page.mouse.click(512,473,{button:'right'});
 else await send({action:'command',type:'MOVE',args:{target:[12,15.5]}});
 await page.waitForFunction(()=>window.qa.state?.units[0].commands.some(c=>c.type==='MOVE'));
 const planned=await state();const commands=planned.units[0].commands;
 assert.equal(commands.at(-1).type,'MOVE');
 assert.equal(planned.time,0);await page.screenshot({path:out+'/'+mission+'-plan.png'});
 await send({action:'toggle'});
 await page.waitForFunction(()=>window.qa.caught&&window.qa.state?.mode==='PLANNING'&&window.qa.state?.events?.some(e=>e.type==='SHOT'),null,{timeout:30000});
 await send({action:'pause'});
 await page.waitForTimeout(100);await page.screenshot({path:out+'/combat-effects.png'});await page.screenshot({path:out+'/combat-closeup.png',clip:{x:465,y:540,width:120,height:140}});
 await send({action:'settings',settings:{reduced_flash:true}});await page.waitForTimeout(150);await page.screenshot({path:out+'/combat-reduced-flash.png'});
 report.push({shots:(await state()).events.filter(e=>e.type==='SHOT'),normal:'combat-effects.png',reduced:'combat-reduced-flash.png'});
 console.log('PASS combat effects',JSON.stringify((await state()).events.filter(e=>e.type==='SHOT')));

}
assert.deepEqual(errors,[]);
}finally{await writeFile(out+'/report.json',JSON.stringify({report,errors},null,2));await browser.close()}
