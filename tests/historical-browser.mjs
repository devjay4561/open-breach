import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import {mkdir,readFile,writeFile} from 'node:fs/promises';

const url=process.env.BREACH_URL||'http://127.0.0.1:8085';
const out=process.env.FICTION_SHOTS||'tests/artifacts/historical-browser';
await mkdir(out,{recursive:true});
const browser=await chromium.launch({channel:'chrome',headless:true,args:['--enable-unsafe-swiftshader']});
const context=await browser.newContext({viewport:{width:1920,height:1080}});
await context.addInitScript(()=>{let ui;window.qa={state:null};Object.defineProperty(window,'BreachUI',{configurable:true,get:()=>ui,set(value){ui=value;const receive=value.receive;value.receive=function(raw){const data=JSON.parse(raw);if(data.type==='state')window.qa.state=data;return receive.call(value,raw)}}})});
const page=await context.newPage(),errors=[],report={url,missions:[],checks:[]};
page.on('pageerror',error=>errors.push(error.message));
page.on('console',message=>{if(message.type()==='error'||/SCRIPT ERROR|Parse Error/.test(message.text()))errors.push(message.text())});
const send=data=>page.evaluate(data=>window.BreachBridge.send(JSON.stringify(data)),data);
const wait=(predicate,arg)=>page.waitForFunction(predicate,arg,{timeout:90000});
try{
  await page.goto(url);
  await wait(()=>window.BreachBridge&&!document.querySelector('#start-mission').disabled);
  await page.evaluate(async()=>{
    const {BreachStorage}=await import('./storage.js');const storage=new BreachStorage();await storage.open();
    for(let i=1;i<=36;i++)await storage.put('progress',{id:`H${String(i).padStart(2,'0')}`,kind:'mission',completed:true,stars:{complete:true,survival:true,par_time:true}});
  });
  await page.reload();await wait(()=>window.BreachBridge&&!document.querySelector('#start-mission').disabled);
  await page.locator('#title-start').click();
  assert.equal(await page.locator('.mission-card').count(),12,'Existing operations and ROE pair remain available');
  await page.locator('[data-collection="history"]').click();
  assert.equal(await page.locator('.mission-card').count(),12);
  assert.match(await page.locator('#operation-scale-note').textContent(),/12/);
  await page.locator('[data-mission="H01"]').click();
  assert.match(await page.locator('#historical-map-facts').textContent(),/네르바스크/);
  assert.match(await page.locator('#historical-map-facts').textContent(),/크렐바스크/);
  assert.doesNotMatch(await page.locator('#historical-map-facts').textContent(),/ship_length/);
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
  await page.screenshot({path:`${out}/12-operations.png`});
  await page.evaluate(async()=>{const i18n=await import('./i18n.js');i18n.setLanguage('en');i18n.applyStaticI18n()});
  await page.locator('[data-mission="H04"]').click();
  assert.match(await page.locator('#historical-map-facts').textContent(),/Drevnik/);
  assert.match(await page.locator('#brief-title').textContent(),/IRON VESPER/);
  assert.equal(await page.locator('[data-collection="history"]').textContent(),'Special Ops 12');
  await page.screenshot({path:`${out}/special-ops-en.png`});
  await page.evaluate(async()=>{const i18n=await import('./i18n.js');i18n.setLanguage('ko');i18n.applyStaticI18n()});
  await page.locator('[data-mission="H01"]').click();
  await page.locator('#select-to-briefing').click();
  await page.locator('#briefing-screen').waitFor({state:'visible'});
  await wait(()=>!document.querySelector('#transition-loading').open);
  await page.screenshot({path:`${out}/briefing.png`});
  await page.locator('#start-mission').click();
  await wait(()=>window.qa.state?.mode==='PLANNING'&&window.qa.state.mission==='H01');
  for(const [index,id] of ["H01", "H02", "H03", "H04", "H06", "H07", "H09", "H11", "H16", "H26", "H29", "H36"].entries()){
    const mission=JSON.parse(await readFile(`game/data/historical/${id}.json`,'utf8'));
    if(index!==0){await send({action:'start',id});await wait(id=>window.qa.state?.mode==='PLANNING'&&window.qa.state.mission===id,id)}
    const state=await page.evaluate(()=>window.qa.state);
    assert.equal(state.units.length,4);
    assert.equal(state.time,0);
    assert.equal(state.objectives.total,mission.enemies.length);
    assert.equal(state.objectives.targets_total||0,mission.interactive_targets?.length||0);
    assert(state.units.every(unit=>unit.hp>0&&unit.x>=0&&unit.z>=0&&unit.x<=mission.bounds[0]&&unit.z<=mission.bounds[1]));
    const topbar=await page.evaluate(()=>({left:document.querySelector('.topbar-left').getBoundingClientRect().right,center:document.querySelector('.topbar-center').getBoundingClientRect().left}));
    assert(topbar.left<=topbar.center,'Objectives stay clear of the mode and clock');
    if(true){
      await page.waitForTimeout(150);
      await page.screenshot({path:`${out}/${id}-planning.png`});
    }
    report.missions.push({id,bounds_m:mission.bounds,units:state.units.length,targets:state.objectives.targets_total||0});
  }
  await send({action:'start',id:'H16'});
  await wait(()=>window.qa.state?.mode==='PLANNING'&&window.qa.state.mission==='H16');
  const initial=await page.evaluate(()=>window.qa.state.units[0]);
  await send({action:'command',unit_id:initial.id,type:'MOVE',args:{target:[initial.x+5,initial.z]}});
  await wait(()=>window.qa.state.units[0].commands.length>0);
  await page.locator('#toggle-execution').click();
  await wait(()=>window.qa.state?.time>=4);
  await page.locator('#toggle-execution').click();
  await wait(()=>window.qa.state?.mode==='PLANNING');
  const paused=await page.evaluate(()=>window.qa.state);
  assert(Math.hypot(paused.units[0].x-initial.x,paused.units[0].z-initial.z)>=3,'A metre-scale route moves a real operator');
  assert.equal(paused.objectives.targets_completed,0,'Remote objective zones cannot complete at insertion');
  assert.equal(await page.locator('#target-objective').isVisible(),true);
  await page.waitForTimeout(300);
  assert.equal(await page.evaluate(()=>window.qa.state.time),paused.time,'Planning stops objective and movement clocks');
  await page.setViewportSize({width:1280,height:800});
  await page.waitForTimeout(200);
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
  assert.equal(await page.locator('#objective-next').isVisible(),true);
  await page.screenshot({path:`${out}/H16-movement-paused.png`});
  assert.deepEqual(errors,[]);
  report.status='PASS';
  report.checks=['12 special operations cards and original collection','fictional location and dossier visible','all 12 start in actual Godot Web','units and objectives match authored missions','real movement and pause','no browser or engine errors'];
}catch(error){report.status='FAIL';report.error=error.stack;report.state=await page.evaluate(()=>window.qa?.state).catch(()=>null);await page.screenshot({path:`${out}/failure.png`});process.exitCode=1}
finally{report.errors=errors;await writeFile(`${out}/report.json`,JSON.stringify(report,null,2));await browser.close();console.log(JSON.stringify(report))}
