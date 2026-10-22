import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import {mkdir,writeFile} from 'node:fs/promises';
const url=process.env.BREACH_URL||'http://127.0.0.1:8082';
const out=process.env.BREACH_ARTIFACTS||'tests/artifacts/camera-pan';await mkdir(out,{recursive:true});
const browser=await chromium.launch({channel:'chrome',headless:true,args:['--enable-unsafe-swiftshader']});
const context=await browser.newContext({viewport:{width:1440,height:900}});
await context.addInitScript(()=>{let ui;window.qa={states:[]};Object.defineProperty(window,'BreachUI',{configurable:true,get:()=>ui,set(value){ui=value;const receive=value.receive;value.receive=function(raw){const data=JSON.parse(raw);if(data.type==='state'){window.qa.states.push(data);if(window.qa.states.length>100)window.qa.states.shift()}return receive.call(value,raw)}}})});
const page=await context.newPage(),errors=[],report={url,gestures:[]};
page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error'||/SCRIPT ERROR|Parse Error/.test(m.text()))errors.push(m.text())});
const send=data=>page.evaluate(data=>window.BreachBridge.send(JSON.stringify(data)),data);
const state=()=>page.evaluate(()=>window.qa.states.at(-1));
const settle=()=>page.waitForTimeout(180);
const liveCommands=s=>s.units.flatMap(u=>u.commands).filter(c=>!['CANCELLED','SUCCEEDED'].includes(c.state));
// Probe the real engine's screen-to-ground mapping via its public FACE input.
async function probe(){
 await send({action:'tool',tool:'face'});await page.waitForFunction(()=>window.qa.states.at(-1)?.tool==='face');
 const count=(await state()).units[0].commands.length;
 await page.mouse.click(720,450);
 await page.waitForFunction(count=>window.qa.states.at(-1)?.units[0].commands.length>count,count);
 const point=(await state()).units[0].commands.at(-1).args.target;
 await send({action:'clear'});await send({action:'tool',tool:'select'});await settle();return point;
}
async function reset(){await page.locator('#reset-camera').click();await settle()}
async function drag(button='middle',alt=false,to=[860,520],from=[720,450]){
 await page.mouse.move(...from);if(alt)await page.keyboard.down('Alt');
 await page.mouse.down({button});await page.mouse.move(...to,{steps:12});await page.mouse.up({button});
 if(alt)await page.keyboard.up('Alt');await settle();
}
try{
 await page.goto(url);await page.waitForFunction(()=>window.BreachBridge&&!document.querySelector('#start-mission').disabled);
 await page.locator('#title-start').click();await page.locator('[data-mission="M04"]').click();
 await page.locator('#select-to-briefing').click();await page.locator('#start-mission').click();
 await page.waitForFunction(()=>window.qa.states.at(-1)?.mode==='PLANNING');await settle();
 const baseline=await probe(),actors=(await state()).units.map(u=>[u.id,u.x,u.z]);
 await page.screenshot({path:`${out}/before.png`});
 let firstDelta;
 for(const method of ['middle','alt-left','pan-tool']){
  await reset();
  if(method==='pan-tool'){await page.locator('#pan-camera').click();await page.waitForFunction(()=>window.qa.states.at(-1)?.tool==='pan')}
  await drag(method==='middle'?'middle':'left',method==='alt-left');
  assert.equal(liveCommands(await state()).length,0,'Camera gesture adds no tactical orders');
  const point=await probe(),delta=point.map((v,i)=>v-baseline[i]);
  assert(delta[0]<-1&&delta[1]<-1,'Map follows the drag in both dimensions');
  if(firstDelta)assert(Math.hypot(...delta.map((v,i)=>v-firstDelta[i]))<0.05,'All gestures pan equally');else firstDelta=delta;
  assert.deepEqual((await state()).units.map(u=>[u.id,u.x,u.z]),actors);assert.equal((await state()).time,0);
  report.gestures.push({method,delta});
 }
 await page.screenshot({path:`${out}/panned.png`});
 await reset();await page.locator('#canvas').focus();await page.keyboard.down('KeyD');await page.waitForTimeout(300);await page.keyboard.up('KeyD');await settle();
 const keyboardPoint=await probe();assert(keyboardPoint[0]>baseline[0]+0.5,'Existing WASD actually pans in browser');
 await page.locator('#canvas').focus();await page.keyboard.press('Home');await settle();
 assert(Math.hypot(...(await probe()).map((v,i)=>v-baseline[i]))<0.03,'Home restores camera position and zoom');
 await page.mouse.move(720,450);await page.mouse.wheel(0,-200);await settle();
 const zoomBase=await probe();await drag();const zoomPoint=await probe();
 const zoomDelta=zoomPoint.map((v,i)=>v-zoomBase[i]);assert(Math.abs(zoomDelta[0])<Math.abs(firstDelta[0]),'Zoom changes world pan distance for the same screen drag');
 await page.screenshot({path:`${out}/zoomed-pan.png`});
 await reset();await drag('middle',false,[1250,450],[1110,450]);
 await page.mouse.move(720,450);await settle();const released=await probe();
 await page.mouse.move(900,550);await settle();const afterRelease=await probe();
 assert.deepEqual(afterRelease,released,'Releasing over HUD stops the grab');
 await reset();await page.locator('#pan-camera').click();await page.waitForFunction(()=>window.qa.states.at(-1)?.tool==='pan');
 await page.locator('#pan-camera').click();await page.waitForFunction(()=>window.qa.states.at(-1)?.tool==='select');
 await page.setViewportSize({width:1280,height:800});await settle();
 const layout=await page.locator('.topbar-right').evaluate(el=>{const a=el.getBoundingClientRect(),b=document.querySelector('.topbar-center').getBoundingClientRect();return {right:a.right,left:a.left,centerRight:b.right,width:innerWidth}});
 assert(layout.right<=layout.width&&layout.left>=layout.centerRight,'Camera button fits the HUD at 1280px');
 await page.screenshot({path:`${out}/controls-1280.png`});
 assert.deepEqual(errors,[]);report.status='PASS';report.keyboard=true;report.zoom=true;report.releaseOverHud=true;
}catch(e){report.status='FAIL';report.error=e.stack;report.state=await state().catch(()=>null);await page.screenshot({path:`${out}/failure.png`});process.exitCode=1;}
finally{report.errors=errors;await writeFile(`${out}/report.json`,JSON.stringify(report,null,2));await browser.close();console.log(JSON.stringify(report));}
