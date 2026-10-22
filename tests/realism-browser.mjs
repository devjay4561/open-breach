import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import {mkdir,writeFile} from 'node:fs/promises';
const url=process.env.BREACH_URL||'http://127.0.0.1:8082',out=process.env.BREACH_ARTIFACTS||'tests/artifacts/realism';await mkdir(out,{recursive:true});
const browser=await chromium.launch({channel:'chrome',headless:true,args:['--enable-unsafe-swiftshader']});
const context=await browser.newContext({viewport:{width:1440,height:900}});
await context.addInitScript(()=>{let ui;window.qa={state:null,plans:[]};Object.defineProperty(window,'BreachUI',{configurable:true,get:()=>ui,set(value){ui=value;const receive=value.receive;value.receive=function(raw){const data=JSON.parse(raw);if(data.type==='state')window.qa.state=data;if(data.type==='plan_data')window.qa.plans.push(data.data);return receive.call(value,raw)}}})});
const page=await context.newPage(),errors=[],report={url,missions:[],checks:[]};page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error'||/SCRIPT ERROR|Parse Error/.test(m.text()))errors.push(m.text())});
const send=d=>page.evaluate(d=>window.BreachBridge.send(JSON.stringify(d)),d);
const wait=(f,arg)=>page.waitForFunction(f,arg,{timeout:60000});
try{
 await page.goto(url);await wait(()=>window.BreachBridge&&!document.querySelector('#start-mission').disabled);
 // Realism uses late campaign maps; a fresh browser must have their normal completion prerequisites.
 await page.evaluate(async()=>{const {BreachStorage}=await import('./storage.js');const storage=new BreachStorage();await storage.open();for(const id of ['M01','M02','M03','M04','M05','M06','M07','M08'])await storage.put('progress',{id,kind:'mission',completed:true,stars:{complete:true}});storage.database.close();});
 await page.reload();await wait(()=>window.BreachBridge&&!document.querySelector('#start-mission').disabled);
 await page.locator('#title-start').click();assert.equal(await page.locator('.mission-card').count(),10);assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
 await page.screenshot({path:`${out}/mission-select.png`});
 for(const [id,rooms,total] of [['M07',7,8],['M08',7,8],['M09',9,9]]){
  await page.locator(`[data-mission="${id}"]`).click();
  if(await page.locator('[data-variant-chip="challenge"]').evaluate(e=>e.classList.contains('active')))await page.locator('[data-variant-chip="challenge"]').click();
  assert.equal(await page.locator(`[data-thumb="${id}"] .fp-rooms rect`).count(),rooms);
  await page.locator('#select-to-briefing').click();await page.locator('#start-mission').click();await wait(id=>window.qa.state?.mode==='PLANNING'&&window.qa.state?.mission===id,id);
  const initial=await page.evaluate(()=>window.qa.state);assert.equal(initial.objectives.total,total);assert.equal(initial.units.length,4);assert(initial.units.every(u=>Number.isInteger(u.reserve_ammo)&&u.reserve_ammo>0));
  // P0 UI gate: posture controls now use cycle buttons; keep the same authoritative state and plan expectations.
  await page.locator('.unit-card').first().click();await page.locator('#operator-stance').click();await wait(()=>window.qa.state.units.find(u=>u.id===window.qa.state.selected)?.stance==='crouched');
  await page.locator('#operator-pace').click();await wait(()=>window.qa.state.units.find(u=>u.id===window.qa.state.selected)?.movement_mode==='fast');await page.locator('#operator-pace').click();await wait(()=>window.qa.state.units.find(u=>u.id===window.qa.state.selected)?.movement_mode==='careful');
  await page.locator('#operator-hold').click();await wait(()=>window.qa.state.units.find(u=>u.id===window.qa.state.selected)?.hold_position===true);assert.equal(await page.locator('#operator-hold').getAttribute('aria-pressed'),'true');
  const planCount=await page.evaluate(()=>window.qa.plans.length);
  await send({action:'get_plan'});await wait(count=>window.qa.plans.length>count,planCount);
  const plan=await page.evaluate(()=>window.qa.plans.at(-1));assert.equal(plan.map_id,id);assert.equal(plan.units[0].stance,'crouched');assert.equal(plan.units[0].movement_mode,'careful');assert.equal(plan.units[0].hold_position,true);
  await page.locator('#operator-hold').click();await wait(()=>window.qa.state.units.find(u=>u.id===window.qa.state.selected)?.hold_position===false);
  await page.locator('#toggle-execution').click();await wait(()=>window.qa.state.time>=3);await page.locator('#toggle-execution').click();await wait(()=>window.qa.state.mode==='PLANNING');
  assert(!await page.evaluate(()=>window.qa.state.enemies.some(e=>e.status==='SURRENDERED')));
  await page.screenshot({path:`${out}/${id}-planning.png`});
  report.missions.push({id,rooms,total,elapsed:await page.evaluate(()=>window.qa.state.time)});
  await send({action:'load_plan',data:plan});await wait(id=>window.qa.state?.mode==='PLANNING'&&window.qa.state.mission===id&&window.qa.state.time===0,id);assert.equal(await page.evaluate(()=>window.qa.state.units[0].stance),'crouched');
  await send({action:'menu'});await wait(()=>window.qa.state.mode==='MENU');await page.locator('#briefing-screen [data-nav="select"]').click();
 }
 assert.deepEqual(errors,[]);report.status='PASS';report.checks=['10 selectable maps','new map floorplans and objectives','real Web engine execution','stance/pace/hold controls','finite reserve readouts','actor behavior plan roundtrip','surrender disabled','no page overflow or runtime errors'];
}catch(e){report.status='FAIL';report.error=e.stack;await page.screenshot({path:`${out}/failure.png`});process.exitCode=1;}
finally{report.errors=errors;await writeFile(`${out}/report.json`,JSON.stringify(report,null,2));await browser.close();console.log(JSON.stringify(report));}
