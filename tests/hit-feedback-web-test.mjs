import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
const app=await readFile(new URL('../web/app.js',import.meta.url),'utf8');
function section(start,end){const begin=app.indexOf(start),finish=app.indexOf(end,begin);assert.ok(begin>=0&&finish>begin);return app.slice(begin,finish);}
const nodes=[],sources=[],panners=[],gains=[],timers=new Map(),cards=new Map();
let wall=0,nextTimer=0,osReduced=false;
function advance(ms){
  const until=wall+ms;
  while(true){const next=[...timers].filter(([,timer])=>timer.at<=until).sort((a,b)=>a[1].at-b[1].at)[0];if(!next)break;timers.delete(next[0]);wall=next[1].at;next[1].callback();}
  wall=until;
}
const gain=()=>{const node={gain:{value:0,cancelScheduledValues(){},setTargetAtTime(){}},connect(){},disconnect(){}};gains.push(node);return node;};
const card={classes:new Set()};card.classList={add:value=>card.classes.add(value),remove:(...values)=>values.forEach(value=>card.classes.delete(value))};cards.set('alpha',card);
const context=vm.createContext({
  performance:{now:()=>wall},hitFlash:new Map(),
  state:{mode:'REPLAY',mission:'T01',replay:{time:1,playing:true,speed:1}},settings:{muted:false,reduced_flash:false,screen_shake:true},
  audioUnlocked:true,audioContext:{currentTime:0,sampleRate:48000,createBuffer(channels,length,sampleRate){const data=new Float32Array(length);return {sampleRate,getChannelData:()=>data,synthetic:true};},createStereoPanner(){const node={pan:{value:0},connect(){},disconnect(){}};panners.push(node);return node;},createGain:gain,createBufferSource(){const s={playbackRate:{value:1},connect(){},disconnect(){},start(){sources.push(s);},stop(){}};return s;}},
  audioBuffers:new Map([['hit',{sample:'hit'}],['hit_alt',{sample:'hit_alt'}]]),combatBus:{},effectGain:{},
  document:{querySelectorAll:()=>[...cards.values()].filter(card=>['hit-flash','fx-shake','fx-incap'].some(name=>card.classes.has(name))),body:{classList:{contains:()=>false}},createElement:()=>({style:{},classList:{add(){}},setAttribute(){},remove(){const index=nodes.indexOf(this);if(index>=0)nodes.splice(index,1);}}),querySelector:selector=>cards.get(selector.match(/data-unit="([^"]+)"/)?.[1])},
  $:()=>({append:node=>nodes.push(node)}),matchMedia:()=>({matches:osReduced}),CSS:{escape:String},
  requestAnimationFrame:()=>1,cancelAnimationFrame(){},
  setTimeout(callback,duration){const id=++nextTimer;timers.set(id,{callback,at:wall+duration});return id;},clearTimeout:id=>timers.delete(id),
  renderReplayMarkers(){},escapeHTML:String,t:String,renderState(){},quality:{noteState(){}},
});
vm.runInContext(section('const combatVoices=', 'function stopAudio'),context);
vm.runInContext(section('let replayFx =', 'function replayMarkerList()'),context);
vm.runInContext(section('function receive(message)', 'function showLoaded()'),context);
let checks=0;
function check(value,label){assert.ok(value,label);checks++;}
const pending=()=>vm.runInContext('pendingHitFeedback.length',context);
const timeline=()=>vm.runInContext('replayFx.length',context);
const reset=()=>{context.receive({type:'fx_reset'});advance(3000);card.classes.clear();};
const replay=(time,speed=1,playing=true)=>context.receive({type:'state',mode:'REPLAY',mission:'T01',replay:{time,speed,playing}});
const clock=(time,paused=false)=>context.receive({type:'fx_clock',time,paused});
const hit={kind:'hit',time:1,target_id:'enemy',event_seq:1,screen:[600,350],protection:'blocked'};
// Timing uses reduced_flash alone, including the OS-on/in-game-off combination.
for(const reduced of [false,true])for(const os of [false,true]){
  reset();context.settings.reduced_flash=reduced;osReduced=os;replay(1);
  context.handleFx(hit);
  const expected=1+(reduced?.035:.05);
  check(Math.abs(vm.runInContext('pendingHitFeedback[0].at',context)-expected)<1e-10,'Web delay is exactly 50/35ms from the game setting alone');
  advance(1000);clock(expected-.001);check(nodes.length===0,'Wall time and OS preference cannot fire feedback before presentation contact');
  clock(expected);check(nodes.length===1&&nodes[0].style.left==='600px'&&nodes[0].className.includes('fx-blocked-confirm'),'Enemy tick starts at the agreed contact point');
  advance(119);check(nodes.length===1,'Enemy tick retains its full 120ms lifetime after contact');advance(1);check(nodes.length===0,'Tick clears after its lifetime');
}
context.settings.reduced_flash=false;osReduced=false;
for(const speed of [.5,2,4]){
  reset();replay(2,speed);context.handleFx({...hit,time:2,react_at:2.05});
  advance(1000);replay(2.049,speed);check(nodes.length===0,'Non-1x replay follows replay time rather than a scaled wall timer');
  replay(2.05,speed);check(nodes.length===1,'Non-1x replay fires exactly when replay time reaches react_at');
}
reset();replay(3);context.handleFx({...hit,time:3,react_at:3.05});
replay(3.02,1,false);advance(1000);clock(3.2,true);check(nodes.length===0&&pending()===1,'Paused replay holds pending feedback');
replay(3.02,4,true);check(nodes.length===0,'Resume does not fire before contact');clock(3.05);check(nodes.length===1,'Resume completes feedback using replay time');
reset();replay(4,4);context.handleFx({...hit,time:3.9,react_at:3.95});check(nodes.length===1,'A late 4x frame presents already-due feedback immediately');
reset();context.receive({type:'state',mode:'EXECUTING',mission:'T01',presentation_time:5});context.handleFx({...hit,time:5,react_at:5.05});
context.receive({type:'state',mode:'PLANNING',mission:'T01',presentation_time:5.02});advance(1000);
check(nodes.length===0&&pending()===1,'Live pause holds rather than cancels a pending hit');
context.receive({type:'state',mode:'EXECUTING',mission:'T01',presentation_time:5.04});clock(5.05);check(nodes.length===1,'Live resume retains and completes the same feedback');
// Rewinding inside one session replays all feedback; only timeline markers stay unique.
reset();replay(6);context.resetReplayMarkers();
const kill={kind:'neutralized',time:6,id:'enemy',event_seq:60,after_shot:true,react_at:6.05};
const down={kind:'unit_down',time:6,id:'alpha',event_seq:61,after_shot:true,react_at:6.05};
const spotted={kind:'enemy_spotted',time:6,event_seq:62,react_at:0};
const beforeSound=sources.length;
let markerCount=0;
for(let pass=0;pass<2;pass++){
  reset();replay(6);
  context.handleFx(kill);context.handleFx(down);context.handleFx(spotted);context.handleFx({...hit,time:6,event_seq:63,react_at:6.05});
  check(nodes.length===1&&nodes[0].className.includes('fx-banner-threat'),'Enemy spotted banner replays after rewind');
  check(!card.classes.has('fx-incap'),'Shot unit-down card waits for contact');
  clock(6.05);
  check(sources.length===beforeSound+pass+1&&card.classes.has('fx-incap')&&nodes.some(n=>n.className.includes('fx-banner-down')),'Kill sound and unit-down banner/card replay after fx_reset within the same session');
  check(nodes.some(n=>n.className.includes('fx-hit-confirm'))&&!nodes.some(n=>n.className.includes('fx-kill-confirm')),'Enemy tick remains while duplicate DOM kill X is absent');
  if(pass===0)markerCount=timeline();else check(timeline()===markerCount,'Replayed feedback does not duplicate timeline markers');
}
reset();replay(7);const silent=sources.length;
context.handleFx({kind:'neutralized',time:7,id:'arrest',cause:'arrest',after_shot:false,react_at:0});
check(pending()===0&&sources.length===silent,'ARREST is immediate and has no kill_confirm');
context.handleFx({kind:'neutralized',time:7,id:'frag',cause:'casualty',after_shot:false,react_at:0});
check(pending()===0&&sources.length===silent+1,'Frag/unlinked casualty confirmation has no tracer delay');
context.handleFx({kind:'unit_down',time:7,id:'alpha',after_shot:false,react_at:0});
check(card.classes.has('fx-incap')&&pending()===0,'Unlinked unit-down banner/card is immediate');
check(vm.runInContext('cardFxTimers.size',context)===0,'Unit down removes its timer entry rather than retaining a detached card');
context.receive({type:'fx_reset'});check(!card.classes.has('fx-incap'),'Transient reset still clears incapacitation styling without a timer entry');
reset();replay(8);const impact=sources.length;
context.receive({type:'sound',name:'hit',event_seq:80,react_at:8.05});
advance(1000);clock(8.049);check(sources.length===impact,'Positional hit sound waits for tracer arrival');clock(8.05);check(sources.length===impact+1,'Impact sound shares the presentation contact time');
reset();replay(8);const blockedStart=sources.length;
context.receive({type:'sound',name:'armour_block',event_seq:81,react_at:8.1,pan:-.6,gain:.7});
clock(8.099);check(sources.length===blockedStart,'Synthesized armour cue waits for react_at');clock(8.1);
check(sources.length===blockedStart+1&&sources.at(-1).buffer.synthetic,'Blocked hit uses the procedural buffer');
check(panners.at(-1).pan.value===-.6&&gains.at(-1).gain.value>=.18*.7*.96&&gains.at(-1).gain.value<=.18*.7*1.04,'Procedural cue shares positional pan and gain attenuation');
const samples=sources.at(-1).buffer.getChannelData(0);
check(samples.length===4320&&Math.max(...samples.map(Math.abs))<1&&samples.slice(-480).every(n=>Math.abs(n)<.006),'Metallic cue is bounded and decays within 90ms');
context.receive({type:'sound',name:'hit',event_seq:82,react_at:0});
check(sources.at(-1).buffer.sample?.startsWith('hit'),'Unprotected contact keeps the sampled hit');
context.settings.muted=true;const muted=sources.length;context.playSound('armour_block');check(sources.length===muted,'Mute suppresses the synthesized cue');context.settings.muted=false;
reset();replay(9);const cancelled=sources.length;context.handleFx({...kill,time:9,react_at:9.05});context.receive({type:'fx_reset'});clock(9.05);
check(sources.length===cancelled&&pending()===0,'Seek cancels pending sound via the single reset contract');
context.handleFx({...hit,time:9,react_at:9.1});context.receive({type:'state',mode:'MENU',mission:'T01',time:10});clock(10);
check(nodes.length===0&&pending()===0,'Leaving live/replay mode cancels pending feedback');
replay(10);context.handleFx({...hit,time:10,react_at:10.05});context.receive({type:'state',mode:'REPLAY',mission:'T02',replay:{time:10.05,playing:true}});
check(nodes.length===0&&pending()===0,'Mission change cancels pending feedback');
reset();replay(11);context.handleFx({...hit,time:11,screen:[600,NaN],react_at:11.05});clock(11.05);
check(nodes.length===0&&pending()===0,'Invalid coordinates do not create a marker');
check(!app.includes("replayFxKeys.has(fxKey)) return"),'Timeline deduplication cannot return before DOM/sound feedback');
for(const mode of ['RESULT','MENU']){
  reset();replay(12);context.handleFx({kind:'enemy_spotted',time:12});context.handleFx({kind:'hit',friendly:true,target_id:'alpha',react_at:0});
  context.handleFx({...hit,time:12,react_at:12.05});context.handleFx({kind:'mission_end',time:12});
  nodes.find(n=>n.className==='fx-letterbox').className+=' show';
  context.receive({type:'state',mode,mission:'T01',presentation_time:12});clock(13);
  check(pending()===0&&!nodes.some(n=>/fx-banner|fx-vignette|fx-hit-confirm/.test(n.className))&&!card.classes.has('hit-flash'),'Terminal transition clears active and pending transient feedback');
  check(nodes.some(n=>n.className.startsWith('fx-letterbox'))===(mode==='RESULT'),'Result preserves mission-end letterbox; menu clears it');
  context.handleFx({kind:'enemy_spotted',time:13});check(!nodes.some(n=>n.className.includes('fx-banner')),'Late combat messages cannot repopulate terminal banners');
  if(mode==='RESULT'){context.handleFx({kind:'mission_end',time:13});check(nodes.some(n=>n.className==='fx-letterbox'),'Mission end arriving after RESULT still plays');}
}
reset();replay(14);context.handleFx({kind:'hit',friendly:true,target_id:'alpha',react_at:0});
check(card.classes.has('hit-flash')&&nodes.some(n=>n.className.includes('fx-vignette')),'Non-shot friendly damage reacts immediately');
context.receive({type:'state',mode:'REPLAY',mission:'T02',replay:{time:14,playing:true}});
check(nodes.length===0&&!card.classes.has('hit-flash'),'Mission change clears active vignette and card feedback');
reset();replay(30);context.handleFx({kind:'hit',time:30,friendly:true,target_id:'alpha',react_at:0});
const replacement={classes:new Set(['hit-flash','fx-shake'])};replacement.classList={remove:(...names)=>names.forEach(name=>replacement.classes.delete(name))};
cards.set('alpha',replacement);context.receive({type:'fx_reset'});
check(replacement.classes.size===0&&vm.runInContext('cardFxTimers.size',context)===0,'Reset clears the current card after a HUD rebuild replaced the timed element');cards.set('alpha',card);
reset();context.resetReplayMarkers();
for(const offset of [.004,.03,.004,.03]){
  reset();replay(40+offset);
  context.handleFx({kind:'hit',time:40,event_seq:'hp:alpha:1200',target_id:'alpha',friendly:true,react_at:40.05});
  check(timeline()===1,'Tick-keyed fallback replay hit retains a single timeline marker across seek/replay passes');
  clock(40.05);check(card.classes.has('hit-flash'),'Marker dedupe does not suppress replayed friendly feedback');
}
context.handleFx({kind:'hit',time:40+1/30,event_seq:'hp:alpha:1201',target_id:'alpha',friendly:true,react_at:0});
check(timeline()===2,'A distinct HP damage tick keeps its own replay marker');
console.log(`BREACH_HIT_FEEDBACK_WEB_RESULT checks=${checks} failures=0`);
