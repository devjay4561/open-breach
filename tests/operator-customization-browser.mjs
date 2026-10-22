// M1–M3 integration: ordinary Chrome input and the real exported Godot engine.
// Only progression records are seeded; no simulation, renderer or receive calls
// are replaced. Custom actor/map fixtures enter through the public import API.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdir,readFile,writeFile} from 'node:fs/promises';
import {chromium} from 'playwright';
import {goToBriefing,setCycler} from './lib/menu.mjs';

const url=process.env.BREACH_URL||'http://127.0.0.1:8083';
const out=process.env.BREACH_ARTIFACTS||'tests/artifacts/operator-customization';
await mkdir(out,{recursive:true});
const report={url,startedAt:new Date().toISOString(),checks:[],limitations:[
  'Chrome on this Mac with SwiftShader; this is not hardware performance certification.',
  'Approximate two-second stun and documented interaction rules are checked; exact Door Kickers internal timing is not claimed.'
]};
const manifestResponse=await fetch(new URL('engine-export-manifest.json',url.endsWith('/')?url:`${url}/`));
assert.equal(manifestResponse.status,200,'Candidate serves its own engine export manifest');
const manifest=await manifestResponse.json();
report.sourceHash=manifest.sourceHash;report.enginePackageHash=manifest.files['engine.pck'];
const browser=await chromium.launch({channel:process.env.BREACH_CHANNEL||'chrome',headless:process.env.BREACH_HEADLESS!=='0',args:['--enable-unsafe-swiftshader']});
report.browser=browser.version();
const context=await browser.newContext({viewport:{width:1600,height:1000},acceptDownloads:true});
await context.addInitScript(()=>{
  let ui;window.operatorQA={states:[],messages:[],sent:[],contexts:[]};
  Object.defineProperty(window,'BreachUI',{configurable:true,get:()=>ui,set(value){
    ui=value;const receive=value.receive;value.receive=function(raw){
      const message=typeof raw==='string'?JSON.parse(raw):raw;
      if(message.type==='state'){window.operatorQA.state=structuredClone(message);window.operatorQA.states.push(structuredClone(message));}
      else window.operatorQA.messages.push(message.type==='ready'?{type:'ready'}:structuredClone(message));
      return receive.apply(this,arguments);
    };
  }});
  // A microtask can run between DOM event listeners. Observe cancellation only
  // after the full dispatch, including the application's later capture handler.
  document.addEventListener('contextmenu',event=>setTimeout(()=>{
    window.operatorQA.contexts.push({trusted:event.isTrusted,prevented:event.defaultPrevented,target:event.target.id||event.target.tagName});
  }),true);
});
const page=await context.newPage(),errors=[];
page.on('pageerror',error=>errors.push(error.message));
page.on('console',message=>{if(message.type()==='error'||/SCRIPT ERROR|Parse Error|Failed loading resource/.test(message.text()))errors.push(message.text());});
page.on('response',response=>{if(response.status()>=400)errors.push(`HTTP ${response.status()} ${response.url()}`);});
const state=()=>page.evaluate(()=>window.operatorQA.state);
const send=data=>page.evaluate(data=>window.BreachBridge.send(JSON.stringify(data)),data);
const settle=()=>page.waitForTimeout(200);
const waitMode=mode=>page.waitForFunction(mode=>window.operatorQA.state?.mode===mode,mode,{timeout:60000});
function passed(name,data){report.checks.push({name,...(data?{data}:{})});console.log(`PASS ${name}`);}
async function boot(){await page.goto(url);await page.locator('#loading').waitFor({state:'hidden',timeout:120000});await page.waitForFunction(()=>typeof window.BreachBridge?.send==='function');}
async function selectedValue(selector){return page.locator(`${selector} [data-cycle-set][aria-selected="true"]`).getAttribute('data-cycle-set');}
async function actualContext(selector){
  const before=await page.evaluate(()=>window.operatorQA.contexts.length);
  await page.locator(selector).click({button:'right'});
  await page.waitForFunction(count=>window.operatorQA.contexts.length>count,before);
  const event=await page.evaluate(()=>window.operatorQA.contexts.at(-1));
  assert.equal(event.trusted,true,`${selector}: context event came from actual browser input`);
  assert.equal(event.prevented,true,`${selector}: browser context menu was suppressed`);
  (report.contextChecks||=[]).push({surface:selector,...event});
}
async function exportPlan(){
  await page.locator('#deck-more').click();const pending=page.waitForEvent('download');await page.locator('#export-plan').click();
  const download=await pending,data=JSON.parse(await readFile(await download.path(),'utf8'));
  await page.locator('#modal-close').click();return data;
}
async function importPlan(data){
  await page.locator('#deck-more').click();await page.locator('#import-plan').click();
  await page.locator('#file-import').setInputFiles({name:'operator-plan.json',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(data))});
  await page.waitForFunction(()=>window.operatorQA.messages.some(m=>m.type==='toast'&&m.message?.includes('저장된 계획으로')));
  await waitMode('PLANNING');
}
// Sample the shipped FACE gesture to calibrate the orthographic camera. This
// avoids a renderer test API and survives safe-area/viewport changes.
async function screenMapping(){
  const samples=[];
  for(const screen of [[780,440],[880,440],[780,540]]){
    const count=(await state()).units[0].commands.length;
    await send({action:'tool',tool:'face'});await page.waitForFunction(()=>window.operatorQA.state?.tool==='face');
    await page.mouse.click(...screen);await page.waitForFunction(count=>window.operatorQA.state.units[0].commands.length>count,count);
    samples.push((await state()).units[0].commands.at(-1).args.target);
    await send({action:'clear'});await settle();
  }
  const [origin,px,py]=samples,a=(px[0]-origin[0])/100,b=(py[0]-origin[0])/100,c=(px[1]-origin[1])/100,d=(py[1]-origin[1])/100,det=a*d-b*c;
  assert(Math.abs(det)>1e-6,'Camera gesture calibration has non-zero area');
  return point=>{const x=point[0]-origin[0],z=point[1]-origin[1];return [780+(d*x-b*z)/det,440+(-c*x+a*z)/det];};
}
async function openDoorContext(mapping,doorId){
  const door=(await state()).doors.find(d=>d.id===doorId);assert(door?.observed,'Fixture door is known to the operator');
  const point=mapping([door.x,door.z]);
  for(const dy of [-18,-32,0,14,-48]){
    await send({action:'context_close'});await page.locator('#canvas').focus();await settle();
    const count=await page.evaluate(()=>window.operatorQA.messages.length);
    await page.mouse.click(point[0],point[1]+dy,{button:'right'});await settle();
    const message=await page.evaluate(count=>window.operatorQA.messages.slice(count).find(m=>m.type==='context'),count);
    if(message?.target==='door'&&message.id===doorId)return message;
    await send({action:'clear'});
  }
  throw new Error(`Actual right-click failed to pick observed door ${doorId}`);
}
async function importFixture(loadout,roster){
  const fixture=JSON.parse(await readFile('game/data/tutorial.json','utf8'));
  fixture.id='EDIT_OPERATOR_QA';fixture.revision=1;fixture.title='대원 장비 통합 확인';fixture.seed=16281;fixture.props=[];
  fixture.units=[
    {id:'alpha',name:'QA A',role:'선봉',x:7.4,z:9.3,facing:0,weapon:'light',ammo:0,reserve_ammo:0,stuns:2},
    {id:'bravo',name:'QA B',role:'지원',x:7.8,z:11,facing:0,weapon:'standard',ammo:0,reserve_ammo:0,stuns:1}
  ];
  fixture.enemies=[{id:'flash_enemy',name:'섬광 표적',x:10.8,z:10.1,facing:0,hp:1000,passive:true,target:true,ammo:0,reserve_ammo:0}];
  // Keep the civilian on the observed doorway sightline. Public snapshots
  // correctly omit actors behind the side wall even when a flash affects them.
  fixture.civilians=[{id:'flash_civilian',name:'섬광 민간인',x:11.5,z:10.0,facing:0,hp:100}];
  fixture.win=[{type:'reach_zone',zone:[12.3,12.4,0.8,0.8]}];fixture.fail=[{type:'no_civilian_loss'}];fixture.stars=[];
  const before=await page.evaluate(()=>({frames:window.operatorQA.states.length,messages:window.operatorQA.messages.length}));
  await send({action:'import_mission',data:fixture,loadout,roster});
  await page.waitForFunction(before=>window.operatorQA.states.slice(before.frames).some(frame=>frame.mission==='EDIT_OPERATOR_QA'&&frame.mode==='PLANNING'&&frame.time===0&&frame.units.every(unit=>unit.commands.length===0))||window.operatorQA.messages.slice(before.messages).some(message=>message.type==='toast'&&message.kind==='error'),before,{timeout:60000});
  const rejection=await page.evaluate(before=>window.operatorQA.messages.slice(before.messages).find(message=>message.type==='toast'&&message.kind==='error'),before);
  assert.equal(rejection,undefined,`Public fixture import accepted: ${rejection?.message||''}`);
  return fixture;
}

try{
  await boot();
  // Stable progression-only fixture unlocks all existing weapons without
  // replacing the runtime engine or awarding arbitrary live results.
  await page.evaluate(async()=>{const {BreachStorage}=await import('./storage.js');const store=new BreachStorage();await store.open();for(const id of ['M01','M02','M03'])await store.put('progress',{id,completed:true,stars:{complete:true,survival:true,no_hits:true,single_plan:true,no_reload:true}});store.db?.close();});
  await page.reload();await page.locator('#loading').waitFor({state:'hidden',timeout:120000});
  await actualContext('#title-start');await goToBriefing(page,'T01');await actualContext('#prepare-squad');await page.locator('#prepare-squad').click();
  await page.locator('[data-customize="raven"]').click();
  const modelPreviews=[];
  for(const weapon of ['standard','light','shotgun','suppressed']){
    await setCycler(page,'[data-loadout="raven"][data-slot="weapon"]',weapon);
    await page.locator('#operator-preview').scrollIntoViewIfNeeded();await settle();
    const pixels=await page.locator('#operator-preview').screenshot();
    await writeFile(`${out}/preview-${weapon}.png`,pixels);
    modelPreviews.push({weapon,hash:createHash('sha256').update(pixels).digest('hex')});
  }
  assert.equal(new Set(modelPreviews.map(item=>item.hash)).size,4,'All four primary selections render different preview pixels');
  passed('Four existing primaries render distinct equipment previews',modelPreviews);
  await setCycler(page,'[data-loadout="raven"][data-slot="preset"]','breacher');
  assert.equal(await selectedValue('[data-loadout="raven"][data-slot="weapon"]'),'light');
  assert.equal(await selectedValue('[data-loadout="raven"][data-slot="armor"]'),'bastion_v4');
  assert.equal(await selectedValue('[data-loadout="raven"][data-slot="helmet"]'),'crown_h2');
  passed('Role preset changes primary, armor, helmet and tool loadout together');
  await setCycler(page,'[data-loadout="raven"][data-slot="armor"]','swift_v3');
  await setCycler(page,'[data-loadout="raven"][data-slot="helmet"]','crown_h1');
  await page.locator('[data-attachment="extended_mag"]').click();
  await page.locator('.appearance-settings summary').click();
  await page.locator('[data-appearance="name"]').fill('테스트 대원');await page.locator('[data-appearance="name"]').press('Tab');
  await page.locator('[data-appearance="callsign"]').fill('ALDER');await page.locator('[data-appearance="callsign"]').press('Tab');
  await page.locator('[data-appearance-patch="arrow"]').click();
  await page.locator('[data-appearance-color="#40516c"]').click();
  await page.locator('#profile-save').click();
  await page.waitForFunction(()=>document.querySelector('#profile-save-status')?.textContent==='대원 장비 저장됨');
  assert((await page.locator('#armor-coverage').textContent()).trim().length>0,'Armor protection is explained');
  const preview=page.locator('#operator-preview');await preview.waitFor({state:'visible'});
  await preview.evaluate(node=>node.scrollIntoView({block:'start'}));await settle();
  const previewPixels=await preview.screenshot();report.previewHash=createHash('sha256').update(previewPixels).digest('hex');
  await writeFile(`${out}/operator-preview.png`,previewPixels);await page.screenshot({path:`${out}/customization.png`});
  await actualContext('#profile-save');
  if(!await page.locator('.appearance-settings').evaluate(el=>el.open))await page.locator('.appearance-settings summary').click();
  await actualContext('[data-appearance="name"]');
  passed('Individual appearance, attachments, preview, coverage and save feedback are present');
  await page.locator('#squad-done').click();await page.reload();await page.locator('#loading').waitFor({state:'hidden',timeout:120000});
  await goToBriefing(page,'T01');await page.locator('#prepare-squad').click();await page.locator('[data-customize="raven"]').click();
  await page.locator('.appearance-settings summary').click();
  assert.equal(await selectedValue('[data-loadout="raven"][data-slot="weapon"]'),'light');
  assert.equal(await selectedValue('[data-loadout="raven"][data-slot="armor"]'),'swift_v3');
  assert.equal(await page.locator('[data-appearance="name"]').inputValue(),'테스트 대원');
  assert.equal(await page.locator('[data-appearance="callsign"]').inputValue(),'ALDER');
  assert.equal(await page.locator('[data-appearance-patch="arrow"]').getAttribute('aria-pressed'),'true');
  assert.equal(await page.locator('[data-appearance-color="#40516c"]').getAttribute('aria-pressed'),'true');
  assert.equal(await page.locator('[data-attachment="extended_mag"]').getAttribute('aria-pressed'),'true');
  // Removing and re-adding a roster identity must restore its own profile,
  // regardless of the new deployment slot.
  await page.locator('.squad-members summary').click();
  await page.locator('[data-roster="raven"]').click();await page.locator('[data-roster="raven"]').click();
  await page.locator('[data-customize="raven"]').click();
  assert.equal(await selectedValue('[data-loadout="raven"][data-slot="armor"]'),'swift_v3');
  passed('Reload and roster removal/reselection preserve the same operator profile');
  await page.locator('#squad-done').click();await page.locator('#start-mission').click();await waitMode('PLANNING');
  const deployed=await state(),raven=deployed.units.find(unit=>unit.roster_id==='raven');
  assert(raven,'Roster identity reached the engine');assert.equal(raven.weapon,'light');assert.equal(raven.armor,'swift_v3');assert.equal(raven.helmet,'crown_h1');assert.equal(raven.sidearm,'pico_p1');
  assert(raven.attachments.includes('extended_mag'));assert.equal(raven.name,'테스트 대원');assert.equal(raven.appearance.callsign,'ALDER');assert.equal(raven.appearance.patch,'arrow');assert.equal(raven.appearance.color,'#40516c');
  assert.equal(raven.max_ammo,40,'Extended magazine changes actual magazine capacity');
  passed('Saved customization reaches actual Godot actor, ammunition and identity',raven);
  await actualContext('#unit-cards');await actualContext('#deck-more');
  const plan=await exportPlan();const ravenSlot=plan.roster.find(unit=>unit.id==='raven').base_id;
  assert.equal(plan.loadout[ravenSlot].armor,'swift_v3');assert(plan.loadout[ravenSlot].attachments.includes('extended_mag'));
  await importPlan(plan);assert.equal((await state()).units.find(unit=>unit.roster_id==='raven').armor,'swift_v3');
  passed('Plan export/import preserves new equipment fields and roster mapping');
  // Use raven as the first fixture unit, while retaining the profile that was
  // actually selected and saved above. Their initially empty primary magazines
  // isolate flash damage from firearm damage until sidearm switching is tested.
  const fixtureRoster=[{id:'raven',base_id:'alpha',name:'테스트 대원',trait:'breacher'},{id:'echo',base_id:'bravo',name:'에코',trait:'marksman'}];
  const fixtureLoadout={alpha:{...plan.loadout[ravenSlot],equipment:{stun:1,probe_c1:1}},bravo:{weapon:'standard',equipment:{stun:1},sidearm:'pico_p1',armor:'frame_v2',helmet:'crown_h1',attachments:[]}};
  await importFixture(fixtureLoadout,fixtureRoster);await send({action:'select',id:'alpha'});await settle();
  let mapping=await screenMapping();
  await send({action:'tool',tool:'select'});await page.waitForFunction(()=>window.operatorQA.state.tool==='select');
  const floorPoint=mapping([6.2,10.4]),routeCount=(await state()).units[0].commands.length;
  await page.mouse.click(...floorPoint,{button:'right'});
  await page.waitForFunction(count=>window.operatorQA.state.units[0].commands.length>count,routeCount);
  const route=(await state()).units[0].commands.at(-1);assert.equal(route.type,'MOVE');
  assert(Math.hypot(route.args.target[0]-6.2,route.args.target[1]-10.4)<0.12,'Floor right-click uses the calibrated world location');
  await settle();await page.mouse.move(...floorPoint);await page.mouse.down({button:'right'});
  await page.mouse.move(floorPoint[0]+90,floorPoint[1]-40,{steps:5});await page.mouse.up({button:'right'});
  await page.waitForFunction(count=>window.operatorQA.state.units[0].commands.length>count,routeCount+1);
  assert.equal((await state()).units[0].commands.at(-1).type,'FACE','Right-dragging the route waypoint preserves facing control');
  await send({action:'clear'});await settle();
  passed('Floor right-click still plans movement and waypoint right-drag still sets facing');
  let menu=await openDoorContext(mapping,'d1');
  assert(menu.actions.some(action=>(typeof action==='string'?action:action.type)==='OPEN_AND_FLASH'));
  await actualContext('#context-popover');await page.keyboard.press('Escape');
  assert.equal(await page.locator('#context-popover').isVisible(),false);assert.equal(await page.locator('#canvas').evaluate(el=>document.activeElement===el),true);
  passed('Real door right-click exposes combined flash action; Escape restores canvas focus');
  menu=await openDoorContext(mapping,'d1');
  const cameraIndex=menu.actions.findIndex(action=>(typeof action==='string'?action:action.type)==='PEEK_CAMERA');
  assert(cameraIndex>=0,'Door menu exposes equipped scout camera');
  await page.locator(`#context-popover [data-context-index="${cameraIndex}"]`).click();await send({action:'toggle'});
  await page.waitForFunction(()=>window.operatorQA.state?.units[0].commands.some(c=>c.type==='PEEK_CAMERA'&&c.state==='SUCCEEDED'),null,{timeout:30000});
  await send({action:'pause'});await waitMode('PLANNING');const cameraState=await state();
  assert.equal(cameraState.doors.find(d=>d.id==='d1').state,'CLOSED','Camera scouting does not open the door');
  const cameraObservations=cameraState.units[0].camera_observations;
  assert(cameraObservations?.length>0,'Camera stores timestamped observations');
  assert(cameraObservations.every(row=>Number.isFinite(row.observed_at)),'Camera observations have acquisition times');
  passed('Closed-door camera records timestamped observations without opening the door',cameraObservations);
  // Reset commands by restarting the public fixture, so the composite command
  // is the first tactical command and accidental calibration moves are absent.
  await importFixture(fixtureLoadout,fixtureRoster);await send({action:'select',id:'alpha'});await settle();mapping=await screenMapping();menu=await openDoorContext(mapping,'d1');
  const actionIndex=menu.actions.findIndex(action=>(typeof action==='string'?action:action.type)==='OPEN_AND_FLASH');
  await page.locator(`#context-popover [data-context-index="${actionIndex}"]`).click();
  await page.waitForFunction(()=>window.operatorQA.state.units[0].commands.some(c=>c.type==='OPEN_AND_FLASH'));
  await send({action:'tool',tool:'select'});await send({action:'command',unit_id:'alpha',type:'WAIT',args:{duration:2.5}});
  await page.locator('#equipment-modes').click();
  await page.locator('#switch-weapon').click();
  const planned=await state();assert.equal(planned.units[0].commands.filter(c=>c.type==='OPEN_AND_FLASH'&&c.state!=='CANCELLED').length,1);
  await page.screenshot({path:`${out}/door-flash-plan.png`});await page.evaluate(()=>{window.operatorQA.states=[];});await send({action:'toggle'});
  await page.waitForFunction(()=>window.operatorQA.states.some(s=>s.flash_projectiles?.length>0),null,{timeout:30000});
  await page.waitForFunction(()=>window.operatorQA.states.some(s=>s.events?.some(e=>e.type==='STUN')),null,{timeout:30000});
  await page.waitForFunction(()=>window.operatorQA.state?.units[0].commands.some(c=>c.type==='SWITCH_WEAPON'&&c.state==='SUCCEEDED'),null,{timeout:30000});
  await send({action:'pause'});await waitMode('PLANNING');
  const samples=await page.evaluate(()=>window.operatorQA.states),done=await state(),flashSamples=samples.filter(s=>s.flash_projectiles?.length),stunned=samples.find(s=>s.enemies?.some(e=>e.id==='flash_enemy'&&e.stunned>0));
  assert(stunned,'Enemy entered actual stunned state');assert(stunned.civilians.some(c=>c.id==='flash_civilian'&&c.stunned>0),'Civilian was stunned by the same flash');
  assert.equal(stunned.enemies.find(e=>e.id==='flash_enemy').hp,1000,'Flash causes no enemy health damage while primaries are empty');
  assert(samples.every(s=>s.units.every(u=>u.stunned===0&&u.hp===100)),'Allies remain immune and unharmed');
  assert(samples.every(s=>s.civilians.every(c=>c.hp===100)),'Civilian receives no flash health damage');
  assert.equal(done.stuns_used,1);assert.equal(done.units[0].stuns,0);assert.equal(done.doors.find(d=>d.id==='d1').state,'OPEN');
  assert.equal(done.units[0].active_weapon,'secondary');assert.equal(done.units[0].current_weapon,'pico_p1');
  assert(flashSamples.some(s=>s.flash_projectiles.some(p=>p.phase==='FLIGHT')),'A real flight phase is sampled');
  assert(flashSamples.some(s=>s.flash_projectiles.some(p=>p.phase==='FUSE')),'A real fuse phase is sampled');
  assert.equal(done.command_failures,0);await page.screenshot({path:`${out}/flash-and-sidearm.png`});
  const stunEvent=samples.flatMap(s=>s.events||[]).find(e=>e.type==='STUN');
  assert(done.units[0].commands.find(c=>c.type==='OPEN_AND_FLASH').completed_tick>=stunEvent.tick,'Composite command waits for the actual explosion');
  const firstStun=stunned.enemies.find(e=>e.id==='flash_enemy').stunned;
  assert(firstStun>1.5&&firstStun<=2.0001,'The first sampled stun starts near the two-second target');
  assert(samples.some(frame=>frame.time>=stunEvent.time+2.05&&frame.enemies.some(enemy=>enemy.id==='flash_enemy'&&enemy.stunned===0)),'Hostile recovers after the two-second stun');
  passed('Door flash flies, detonates once, stuns hostile/civilian, spares allies and completes before sidearm transition',{stunEvent,firstSampleStun:firstStun,projectileSamples:flashSamples.length});
  await send({action:'command',unit_id:'alpha',type:'MOVE',args:{target:[12.3,12.4]}});await send({action:'toggle'});await waitMode('RESULT');
  await page.locator('#watch-replay').click();await waitMode('REPLAY');await send({action:'pause'});
  const pending=page.waitForEvent('download');await page.locator('#export-replay').click();const download=await pending,replay=JSON.parse(await readFile(await download.path(),'utf8'));
  await writeFile(`${out}/operator-replay.json`,JSON.stringify(replay));
  const importMessages=await page.evaluate(()=>window.operatorQA.messages.length);
  await send({action:'import_replay',data:replay});
  await page.waitForFunction(count=>window.operatorQA.messages.slice(count).some(m=>m.type==='toast'&&m.message==='리플레이를 불러왔습니다.'),importMessages,{timeout:30000});
  await waitMode('REPLAY');await send({action:'pause'});
  const seekTimes=[flashSamples[0].time,flashSamples.find(s=>s.flash_projectiles.some(p=>p.phase==='FUSE')).time,stunned.time,done.time];
  for(const time of [...seekTimes,...seekTimes.toReversed()]){
    await send({action:'replay_seek',time});await settle();const frame=await state();assert.equal(frame.mode,'REPLAY');
    const actor=frame.units.find(u=>u.roster_id==='raven');assert.equal(actor.armor,'swift_v3');assert.equal(actor.sidearm,'pico_p1');assert(actor.attachments.includes('extended_mag'));
    if(time===seekTimes[0])assert(frame.flash_projectiles.length>0,'Replay reconstructs in-flight grenade after import');
    if(time===stunned.time)assert(frame.enemies.some(e=>e.id==='flash_enemy'&&e.stunned>0),'Replay reconstructs stun');
    if(time===stunned.time)await page.screenshot({path:`${out}/replay-stun.png`});
    if(time===seekTimes[1])await page.screenshot({path:`${out}/replay-fuse.png`});
  }
  await page.screenshot({path:`${out}/replay-flight.png`});passed('Exported replay accepts new fields and seeks both directions through flight, fuse, stun and gear');
  assert.deepEqual(errors,[],'No page, engine or missing-resource errors');
  const inputEvents=await page.evaluate(()=>window.operatorQA.contexts);assert(inputEvents.length>=5&&inputEvents.every(e=>e.prevented));
  report.contextEvents=inputEvents;report.status='PASS';
}catch(error){report.status='FAIL';report.failure=error.stack;report.state=await state().catch(()=>null);report.messages=await page.evaluate(()=>window.operatorQA?.messages.slice(-20)).catch(()=>[]);await page.screenshot({path:`${out}/failure.png`}).catch(()=>{});process.exitCode=1;}
finally{report.errors=errors;report.finishedAt=new Date().toISOString();await writeFile(`${out}/browser-report.json`,JSON.stringify(report,null,2));await browser.close();console.log(JSON.stringify({status:report.status,checks:report.checks.length,failure:report.failure,errors,report:`${out}/browser-report.json`}));}
