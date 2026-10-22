import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import {mkdir,writeFile} from 'node:fs/promises';
const out=process.env.BREACH_ARTIFACTS||'tests/artifacts/gameplay-expansion';await mkdir(out,{recursive:true});
const browser=await chromium.launch({channel:'chrome',headless:true,args:['--enable-unsafe-swiftshader']});
const context=await browser.newContext({viewport:{width:1366,height:900}});
await context.addInitScript(()=>{let ui;window.qa={states:[]};Object.defineProperty(window,'BreachUI',{configurable:true,get:()=>ui,set(value){ui=value;const receive=value.receive;value.receive=function(raw){const data=JSON.parse(raw);if(data.type==='state'){window.qa.states.push(data);if(window.qa.states.length>100)window.qa.states.shift()}return receive.call(value,raw)}}})});
const page=await context.newPage(),errors=[],report={url:process.env.BREACH_URL||'http://127.0.0.1:8080',missions:[],checks:[]};
page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error'||/SCRIPT ERROR|Parse Error/.test(m.text()))errors.push(m.text())});
try{
for(const [id,total] of [['M04',8],['M05',9],['M06',10]]){
 await page.goto(process.env.BREACH_URL||'http://127.0.0.1:8080');
 await page.waitForFunction(()=>window.BreachBridge&&!document.querySelector('#start-mission').disabled);
 await page.locator('#title-start').click();
 assert.equal(await page.locator('.mission-card').count(),7);
 await page.locator(`[data-mission="${id}"]`).click();
 if(await page.locator('[data-variant-chip="challenge"]').evaluate(e=>e.classList.contains("active")))await page.locator('[data-variant-chip="challenge"]').click();
 assert.match(await page.locator('#brief-rooms').textContent(),/08/);
 assert.equal(await page.locator(`[data-thumb="${id}"] .fp-rooms rect`).count(),8);
 assert.equal(await page.locator('#brief-variants [data-variant-chip="variant:arrest"]').count(),0);
 assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
 if(id==='M04')await page.screenshot({path:`${out}/mission-select.png`});
 await page.locator('#select-to-briefing').click();await page.locator('#start-mission').click();
 await page.waitForFunction(id=>window.qa.states.at(-1)?.mode==='PLANNING'&&window.qa.states.at(-1)?.mission===id,id);
 let state=await page.evaluate(()=>window.qa.states.at(-1));assert.equal(state.units.length,4);assert.equal(state.objectives.total,total);
 await page.waitForTimeout(400);await page.screenshot({path:`${out}/${id}-planning.png`});
 await page.locator('#toggle-execution').click();
 await page.waitForFunction(()=>window.qa.states.at(-1)?.time>=3,null,{timeout:30000});
 await page.locator('#toggle-execution').click();
 await page.waitForFunction(()=>window.qa.states.at(-1)?.mode==='PLANNING');
 state=await page.evaluate(()=>window.qa.states.at(-1));
 assert(!state.enemies.some(e=>e.status==='SURRENDERED'));
 report.missions.push({id,total,elapsed:state.time,mode:state.mode});
}
assert.deepEqual(errors,[]);report.status='PASS';report.checks=['7 selectable maps','8-room floor-plan thumbnails','three new missions start and execute in actual Godot Web','no horizontal page overflow','no browser/runtime errors'];
}catch(e){report.status='FAIL';report.error=e.stack;await page.screenshot({path:`${out}/failure.png`});process.exitCode=1;}
finally{report.errors=errors;await writeFile(`${out}/report.json`,JSON.stringify(report,null,2));await browser.close();console.log(JSON.stringify(report));}
