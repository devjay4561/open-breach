import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import {mkdir,readFile,writeFile} from 'node:fs/promises';
// Plan 2-1: {type:'fx',...} messages must fire identically during live play
// and replay playback (including after a seek never re-firing past events).
// This drives T01 once live, then replays the same recording, and asserts
// the two fx sequences (kind, in order) are exactly equal.
const out='tests/artifacts/combat-fx-determinism';await mkdir(out,{recursive:true});
// P3 room_clear follows a real 1.5s stationary search, not the last kill.
// Clone every T01 field except its test ID/schema and appended AND goal.
// Fixed STEP native preflight proves the unchanged route and added WAITs
// before this browser run. The original complete FX/time/speed/seek checks
// below remain strict; built-in T01 itself is not edited.
const native=JSON.parse(await readFile('tests/artifacts/room-control-browser/preflight.json','utf8'));
assert.equal(native.status,'PASS','Run the fixed-STEP P3 browser preflight first');
assert.deepEqual(native.failures,[]);
// Godot JSON writes STEP with 15 significant digits; compare that exact
// serialized value while the fixed native simulation still uses 1/30.
assert.equal(native.step,Number((1/30).toPrecision(15)));
const original=JSON.parse(await readFile('game/data/tutorial.json','utf8'));
const fixture=structuredClone(original);fixture.id='FX_DOCTRINE_P3';fixture.schema_version=4;
fixture.win.push({type:'rooms_cleared',room_ids:['t_ready','t_breach','t_signal']});
function godotJSONProjection(value){
  if(typeof value==='number')return Number(value.toPrecision(15));
  if(Array.isArray(value))return value.map(godotJSONProjection);
  if(value&&typeof value==='object')return Object.fromEntries(Object.entries(value).map(([key,item])=>[key,godotJSONProjection(item)]));
  return value;
}
// This new preflight comparison crosses Godot's 15-digit JSON export: only
// walls[1].w changes from the raw T01 1.9000000000000004 to serialized 1.9.
// Compare the complete projected dictionary; import the raw clone unchanged.
assert.deepEqual(native.fx.mission,godotJSONProjection(fixture),'Native and browser use the same complete T01 clone at the Godot JSON boundary');
assert.equal(Object.keys(native.fx.clear_calls).length,3);
const url=new URL(process.env.BREACH_URL||'http://127.0.0.1:8080');url.searchParams.set('qa','1');
const browser=await chromium.launch({channel:'chrome',headless:true,args:['--enable-unsafe-swiftshader']});
const ctx=await browser.newContext({viewport:{width:1600,height:900}});
await ctx.addInitScript(()=>{
  let ui;window.qa={states:[],fx:[],sent:[],events:[],eventKeys:new Set()};
  Object.defineProperty(window,'BreachUI',{configurable:true,get:()=>ui,set(v){
    ui=v;const orig=v.receive;
    v.receive=function(raw){
      const d=JSON.parse(raw);
      if(d.type==='state'){
        window.qa.states.push(d);if(window.qa.states.length>900)window.qa.states.shift();
        for(const event of d.events||[]){const key=`${d.mission}:${event.seq}:${event.tick}:${event.type}`;
          if(!window.qa.eventKeys.has(key)){window.qa.eventKeys.add(key);window.qa.events.push(event);}}
      }
      else if(d.type==='fx'){window.qa.fx.push(d);}
      return orig.call(v,raw);
    };
  }});
});
const p=await ctx.newPage();
p.setDefaultTimeout(300000);
const errors=[];p.on('pageerror',e=>errors.push('pageerror: '+e.message));p.on('console',m=>{if(m.type()==='error')errors.push('console: '+m.text());});
const wait=(fn,timeout=300000)=>p.waitForFunction(fn,null,{timeout});
const send=value=>p.evaluate(v=>window.BreachBridge.send(JSON.stringify(v)),value);
async function finishAnimations(selector){
  await p.evaluate(async selector=>Promise.all(document.querySelector(selector).getAnimations({subtree:true})
    .filter(animation=>Number.isFinite(animation.effect?.getComputedTiming().endTime))
    .map(animation=>animation.finished.catch(()=>{}))),selector);
}
async function renderAck(){
  const token=await p.evaluate(()=>{
    const token=`fx-render-${window.qa.sequence=(window.qa.sequence||0)+1}`;
    const right=document.querySelector('.hud-right').getBoundingClientRect();
    window.BreachBridge.send(JSON.stringify({action:'set_safe_area',_quality_token:token,data:{
      left:Math.round(document.querySelector('.hud-left').getBoundingClientRect().width),
      top:Math.round(document.querySelector('.hud-topbar').getBoundingClientRect().height),
      right:Math.max(0,Math.round(innerWidth-Math.max(right.left,0))),
      bottom:Math.round(document.querySelector('.hud-hotbar').getBoundingClientRect().height)}}));return token;
  });
  await p.waitForFunction(token=>window.qa.states.some(state=>state.quality?.ack_tokens?.includes(token)),token,{timeout:300000});
}
async function seek(time){
  const before=await p.evaluate(()=>window.qa.sent.length);
  await p.locator('#replay-seek').fill(String(time));
  await p.locator('#replay-seek').dispatchEvent('input');
  await p.waitForFunction(({before,time})=>window.qa.sent.slice(before).some(intent=>intent.action==='replay_seek'&&intent.time===time),{before,time},{timeout:300000});
  // A native render ACK follows the actual outgoing seek. Range fill/input
  // events need not receive a trusted-input token from quality-metrics.
  await p.waitForFunction(time=>{const state=window.qa.states.at(-1);return state?.mode==='REPLAY'&&state.replay.time===time;},time,{timeout:300000});
  await renderAck();
}
async function finishedReplay(){
  await wait(()=>window.qa.fx.some(fx=>fx.kind==='mission_end')&&window.qa.states.at(-1)?.mode==='REPLAY'
    &&window.qa.states.at(-1).replay.playing===false&&window.qa.states.at(-1).replay.time===window.qa.states.at(-1).replay.duration);
  await renderAck();
}

try{
  await p.goto(url.href,{waitUntil:'domcontentloaded'});
  await p.locator('#title-start').waitFor({state:'visible'});
  await wait(()=>window.qa.states.at(-1)?.mode==='MENU'&&window.BreachBridge&&document.querySelector('#loading').hidden
    &&!document.querySelector('#transition-loading').open&&!document.querySelector('#start-mission').disabled);
  await finishAnimations('#title-screen');
  await p.evaluate(()=>{const send=window.BreachBridge.send;window.BreachBridge.send=function(raw){window.qa.sent.push(JSON.parse(raw));return send.call(this,raw);};});
  await p.locator('#title-start').click();
  await p.locator('#select-to-briefing').click();
  await p.locator('#start-mission').waitFor({state:'visible'});
  await p.locator('#start-mission').click();
  await wait(()=>window.qa.states.at(-1)?.mode==='PLANNING');
  await send({action:'import_mission',data:fixture});
  await p.waitForFunction(id=>{const state=window.qa.states.at(-1);return state?.mode==='PLANNING'&&state.mission===id&&state.time===0
    &&document.querySelector('#loading').hidden&&!document.querySelector('#transition-loading').open;},fixture.id,{timeout:300000});
  await finishAnimations('#hud');await renderAck();

  // Direct bridge commands (bypassing the tutorial's guided-click overlay and
  // the door-mode picker UI, both fragile to drive from a script): move alpha
  // into each of T01's three rooms, breach the first door with KICK_DOOR so
  // a 'breach' fx fires, then open the second door normally.
  await send({action:'select',id:'alpha'});
  for(const command of native.fx.commands)await send({action:'command',unit_id:'alpha',...command});
  await renderAck();
  assert.deepEqual(await p.evaluate(()=>window.qa.states.at(-1).units.find(unit=>unit.id==='alpha').commands.map(command=>({type:command.type,args:command.args}))),native.fx.commands);
  await p.locator('#toggle-execution').click();

  await wait(()=>(window.qa.fx||[]).some(f=>f.kind==='enemy_spotted'));
  await p.screenshot({path:out+'/fx-enemy-spotted.png'});
  await wait(()=>(window.qa.fx||[]).some(f=>f.kind==='breach'));
  await p.screenshot({path:out+'/fx-breach.png'});
  await wait(()=>(window.qa.fx||[]).some(f=>f.kind==='room_clear'));
  await p.screenshot({path:out+'/fx-room-clear.png'});
  await wait(()=>window.qa.states.at(-1)?.mode==='RESULT');
  const result=await p.evaluate(()=>window.qa.states.at(-1).result);
  assert.equal(result.success,true);
  const clears=await p.evaluate(()=>window.qa.events.filter(event=>event.type==='CALL_ROOM_CLEAR'));
  assert.equal(clears.length,3,'Live FX mission executes all three authoritative searches');
  assert.deepEqual(clears.map(event=>event.room_id).sort(),['t_breach','t_ready','t_signal']);
  await p.screenshot({path:out+'/fx-result.png'});

  const liveFx=await p.evaluate(()=>window.qa.fx);
  assert.ok(liveFx.length>0,'live play must produce at least one fx message');
  const expectedKinds=['breach','enemy_spotted','hit','neutralized','room_clear','mission_end'];
  for(const kind of expectedKinds) assert.ok(liveFx.some(f=>f.kind===kind),`live fx must include kind=${kind}`);
  for(const fx of liveFx){
    assert.equal(fx.type,'fx');
    assert.equal(typeof fx.kind,'string');
    assert.equal(typeof fx.time,'number');
    if(fx.screen) assert.equal(fx.screen.length,2);
  }

  // --- Replay the exact same recording and capture the fx sequence again.
  await p.evaluate(()=>{window.qa.fx=[];});
  await p.locator('#watch-replay').click();
  await wait(()=>window.qa.states.at(-1)?.mode==='REPLAY');
  // _start_replay() already begins playing; #replay-toggle would pause it.
  await p.locator('[data-speed="4"]').click();
  await finishedReplay();
  const replayFx=await p.evaluate(()=>window.qa.fx);

  await writeFile(out+'/fx-log.json',JSON.stringify({live:liveFx,replay:replayFx},null,2));
  assert.deepEqual(replayFx.map(f=>f.kind),liveFx.map(f=>f.kind),'live and replay fx sequences (kind, in order) must match exactly');
  for(let i=0;i<liveFx.length;i++){
    assert.equal(replayFx[i].time,liveFx[i].time,`fx[${i}] (${liveFx[i].kind}) time must match between live and replay`);
  }

  // --- M4 fix: room_clear used to be evaluated against a snapshot of
  // state.enemies for the whole frame, so whether multiple deaths landed in
  // the same frame (as a fast replay batches more ticks per frame) or
  // separate frames (live 1x play) could shift which event the fx fired on.
  // The 4x pass above already exercises heavy batching; replay the exact
  // same recording once more at 1x (minimal batching, closest to live) and
  // assert it produces the identical fx sequence too, so the fix is
  // verified at both speeds rather than only the already-passing 4x case.
  // Actual native seek/end acknowledgements replace the former fixed delays.
  await seek(0);
  await p.evaluate(()=>{window.qa.fx=[];});
  await p.locator('[data-speed="1"]').click();
  // The 4x pass above already ran to the end, which stops replay_playing;
  // seeking back to 0 does not resume it on its own, so explicitly resume.
  if(!(await p.evaluate(()=>window.qa.states.at(-1)?.replay?.playing))) await p.locator('#replay-toggle').click();
  await finishedReplay();
  const replayFx1x=await p.evaluate(()=>window.qa.fx);
  await writeFile(out+'/fx-log-1x.json',JSON.stringify({live:liveFx,replay:replayFx1x},null,2));
  assert.deepEqual(replayFx1x.map(f=>f.kind),liveFx.map(f=>f.kind),'live and a 1x replay fx sequence (kind, in order) must match exactly');
  for(let i=0;i<liveFx.length;i++){
    assert.equal(replayFx1x[i].time,liveFx[i].time,`1x replay fx[${i}] (${liveFx[i].kind}) time must match live`);
  }

  // --- Seeking back into already-played history must not re-fire fx: seek
  // to the start, then forward past every event once more, and the fx array
  // (still being watched) must gain no new entries beyond those already
  // captured, i.e. scrubbing never replays stale history.
  const beforeSeekCount=(await p.evaluate(()=>window.qa.fx)).length;
  await seek(0);
  await seek(Math.floor(result.time*20)/20);
  const afterSeekCount=(await p.evaluate(()=>window.qa.fx)).length;
  assert.equal(afterSeekCount,beforeSeekCount,'seeking back to the start and forward to the end must not re-fire fx messages');

  assert.deepEqual(errors,[]);
  console.log('PASS combat fx determinism (live vs replay)',JSON.stringify(liveFx.map(f=>f.kind)));
}catch(error){
  const diagnostic=await p.evaluate(()=>({state:window.qa.states.at(-1),sent:window.qa.sent.slice(-50),fx:window.qa.fx,events:window.qa.events})).catch(()=>({}));
  await writeFile(out+'/failure.json',JSON.stringify({error:error.stack,errors,...diagnostic},null,2));
  await p.screenshot({path:out+'/failure.png'}).catch(()=>{});throw error;
}finally{
  await browser.close();
}
