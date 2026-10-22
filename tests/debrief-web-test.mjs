import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';

const read = name => readFile(new URL('../'+name,import.meta.url),'utf8');
const [app,html,css,debriefSource,qualitySource,i18nSource,replaySource] = await Promise.all(['web/app.js','web/index.html','web/style.css','web/debrief.js','web/quality-metrics.js','web/i18n.js','game/scripts/replay.gd'].map(read));
const load = source => import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
const [debrief,quality,i18n] = await Promise.all([load(debriefSource),load(qualitySource),load(i18nSource)]);
let checks=0;
const plain=value=>value===undefined?undefined:JSON.parse(JSON.stringify(value));
const equal=(actual,expected,note)=>{assert.deepEqual(plain(actual),plain(expected),note);checks++;};
const check=(value,note)=>{assert(value,note);checks++;};
const escapeHTML=value=>String(value??'').replace(/[&<>"']/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
const formatTime=value=>`${Math.floor(value/60).toString().padStart(2,'0')}:${Math.floor(value%60).toString().padStart(2,'0')}.0`;
const section=(start,end)=>{const a=app.indexOf(start),b=app.indexOf(end,a);assert(a>=0&&b>a,'Actual app section '+start);return app.slice(a,b).replaceAll('export function','function');};
const ids=['stealth','doorway_dwell','time_to_dominate','threat_order_violations','identification','control','marked','rear_hits'];
const metric=(value,tick=61)=>({value,tick,time:1.9,unit_id:'alpha',door_id:'entry',hidden_enemy:{id:'secret',x:99,z:99}});
const values={stealth:2,doorway_dwell:1.8,time_to_dominate:3,threat_order_violations:1,identification:1,control:.5,marked:0,rear_hits:2};
const metrics=Object.fromEntries(ids.map(id=>[id,metric(values[id])]));
Object.assign(metrics.identification,{civilian_damage:0,unlawful_shots:1});
Object.assign(metrics.control,{arrested:1,surrendered:2,secured:1,civilians:2});
metrics.rear_hits.unit_id='secret';metrics.rear_hits.door_id='secret-door';
const authored=[{id:'known',label:'관측한 방',label_en:'Observed room'},{id:'hidden',label:'숨은 방',label_en:'Hidden room'},{id:'missing',label:'기록 없는 방',label_en:'Room without measurements'}];
const state={mode:'RESULT',mission:'M01',seed:42,tick:90,units:[{id:'alpha',hp:0}],doors:[{id:'entry'}],
  room_states:{known:{state:'MARKED',observed:true},hidden:{state:'MARKED',observed:false},missing:{state:'CLEAR',observed:true},outsider:{state:'CLEAR',observed:true}},
  room_doctrine:{known:Object.fromEntries(ids.map(id=>[id,metric(0)])),hidden:metrics,outsider:metrics},result:{room_doctrine:{known:metrics,hidden:metrics}},
  room_doctrine_private:{hidden:metrics},enemies:[{id:'secret',x:99,z:99}]};
const before=JSON.stringify(state);
const report=debrief.roomDoctrineReport(state,authored,quality.gradeRoomDoctrine);
equal(report.map(room=>room.id),['known','missing'],'Known authored rooms still require explicit public observation');
equal(report[0].rows.map(row=>row.id),ids,'Every observed room has exactly eight stable feedback rows');
equal(report[0].rows.map(row=>row.grade),['fail','fail','good','fail','fail','caution','fail','fail'],'The actual quality callback grades the public completed result');
equal(report[1].rows.map(row=>[row.grade,row.value]),ids.map(()=>['na',null]),'An observed room without measurements has eight N/A rows');
check(!JSON.stringify(report).includes('secret'),'Unknown occupants, units and doors never enter the report');
equal(report[0].rows.at(-1).unit_id,undefined,'Unknown unit reference is dropped');
equal(report[0].rows.at(-1).door_id,undefined,'Unknown door reference is dropped');
equal(report[0].rows[0].replay_time,61*(1/30),'Feedback uses the measured tick rather than the different raw time');
equal(report[0].rows[5].details.arrest_rate,.5,'Control exposes the derived arrest rate');
equal(report[0].rows[5].details.secure_rate,.5,'Control exposes the derived civilian secure rate');
report[0].rows[0].details.value=9;
equal(JSON.stringify(state),before,'Presentation owns its records and cannot mutate a snapshot');
for(const observed of [false,'true',1,null,undefined]){
  const snapshot=structuredClone(state);snapshot.room_states.known.observed=observed;
  check(!debrief.roomDoctrineReport(snapshot,authored,quality.gradeRoomDoctrine).some(room=>room.id==='known'),'Only observed:true reveals a room');
}
for(const malformed of [null,[],{}, {room_states:[]}, {room_states:{known:null}}])equal(debrief.roomDoctrineReport(malformed,authored,quality.gradeRoomDoctrine),[],'Legacy/malformed room evidence does not reveal an authored room');
equal(debrief.roomDoctrineReport(state,[],quality.gradeRoomDoctrine),[],'Absent authored catalog cannot be replaced by raw room IDs');
const privateOnly={...state,room_doctrine:undefined,result:{room_doctrine_private:{known:metrics}}};
equal(debrief.roomDoctrineReport(privateOnly,authored,quality.gradeRoomDoctrine)[0].rows.map(row=>row.grade),ids.map(()=>'na'),'Private auxiliary data never supplies missing public measurements');
const replay={...state,mode:'REPLAY',replay:{time:1,duration:3}};
equal(debrief.roomDoctrineReport(replay,authored,quality.gradeRoomDoctrine)[0].rows[0].value,0,'A replay before its end uses current public measurements');
replay.replay.time=3;
equal(debrief.roomDoctrineReport(replay,authored,quality.gradeRoomDoctrine)[0].rows[0].value,2,'A terminal replay uses the public completed result');
const many=Array.from({length:65},(_,index)=>({id:'room'+index}));
equal(debrief.roomDoctrineReport({room_states:Object.fromEntries(many.map(room=>[room.id,{state:'CLEAR',observed:true}]))},many,quality.gradeRoomDoctrine).length,64,'Report preserves the authored room bound');
equal(debrief.roomDoctrineReport(state,authored)[0].rows.map(row=>row.grade),ids.map(()=>'na'),'Absent grader does not invent a successful assessment');

const markup=vm.runInNewContext(section('export function roomDoctrineMarkup','function renderRoomDoctrine')+'\nroomDoctrineMarkup;',{t:i18n.t,getLanguage:i18n.getLanguage,escapeHTML,formatTime,doctrineReplaySeek:debrief.doctrineReplaySeek});
for(const language of ['ko','en']){
  i18n.setLanguage(language);
  const output=markup(debrief.roomDoctrineReport(state,authored,quality.gradeRoomDoctrine),state);
  equal((output.match(/data-doctrine-metric=/g)||[]).length,16,'Two observed rooms render exactly sixteen rows');
  equal((output.match(/data-doctrine-tick="61"/g)||[]).length,6,'Only failed rows with a measured tick offer replay links');
  check(output.includes(language==='ko'?'체포 1/2':'Arrests 1/2'),'Control shows both actual counts');
  check(output.includes(language==='ko'?'확보율 50%':'secure rate 50%'),'Control shows both derived rates');
  check(!output.includes('secret')&&!output.includes('Hidden room'),'Hidden room and raw occupant identities are absent from HTML');
  if(language==='en')check(!/[가-힣]/.test(output),'All dynamically rendered English room feedback is English');
  check(markup([]).includes('N/A'),'Legacy results render one N/A notice');
  const absentTick=debrief.roomDoctrineReport(state,authored,quality.gradeRoomDoctrine);absentTick[0].rows.forEach(row=>row.tick=null);
  check(!markup(absentTick,state).includes('data-doctrine-tick'),'Missing ticks never fall back to an approximate time link');
  check(!markup(debrief.roomDoctrineReport(state,authored,quality.gradeRoomDoctrine),{...state,replay:{duration:1,complete:false}}).includes('data-doctrine-tick'),'Failures beyond a partial recording never link to a different frame');
  const escaped=structuredClone(report);escaped[0].label=escaped[0].label_en='<script>unsafe</script>';
  check(!markup(escaped).includes('<script>'),'Authored room text is escaped');
}

const sent=[],nodes=new Map();
const node=id=>{if(!nodes.has(id))nodes.set(id,{hidden:false,pressed:false});return nodes.get(id);};
const context=vm.createContext({state:structuredClone(state),send:message=>sent.push(plain(message)),doctrineReplaySeek:debrief.doctrineReplaySeek,priorAttemptPresentation:debrief.priorAttemptPresentation,
  $:node,setPressed:(button,value)=>{button.pressed=value;},requestAnimationFrame:()=>1,cancelAnimationFrame(){}});
vm.runInContext(section('let pendingReplaySeek=','function renderReplay()'),context);
check(context.requestDoctrineReplay(61),'A valid failure tick starts replay from RESULT');
equal(sent,[{action:'replay'}],'Seek is deferred until native replay-start state is acknowledged');
context.applyDoctrineReplaySeek();equal(sent.length,1,'Another RESULT snapshot cannot prematurely seek');
context.state={...state,mode:'REPLAY',replay:{time:0,duration:3}};context.applyDoctrineReplaySeek();
equal(sent,[{action:'replay'},{action:'pause'},{action:'replay_seek',tick:61,time:61/30}],'Native replay ACK is followed by exact tick and time, while paused');
context.applyDoctrineReplaySeek();equal(sent.length,3,'The acknowledged seek is consumed exactly once');
sent.length=0;
context.requestDoctrineReplay(31);
equal(sent,[{action:'pause'},{action:'replay_seek',tick:31,time:31/30}],'An existing replay seeks immediately using the integer tick');
for(const invalid of [undefined,null,'61',-1,.5,NaN,Infinity,Number.MAX_SAFE_INTEGER+1]){
  sent.length=0;equal(context.requestDoctrineReplay(invalid),false,'Invalid tick input is rejected');equal(sent,[],'Invalid tick emits no bridge intent');
}
for(const change of [{mission:'other'},{seed:43},{mode:'PLANNING'}]){
  sent.length=0;context.state=structuredClone(state);context.requestDoctrineReplay(61);context.state={...state,mode:'REPLAY',...change};context.applyDoctrineReplaySeek();
  equal(sent,[{action:'replay'}],'A changed mission, seed or mode cancels a pending seek');
}
sent.length=0;context.state=structuredClone(state);context.requestDoctrineReplay(61);context.requestDoctrineReplay(31);
context.state={...state,mode:'REPLAY'};context.applyDoctrineReplaySeek();
equal(sent,[{action:'replay'},{action:'pause'},{action:'replay_seek',tick:31,time:31/30}],'A second link before replay ACK replaces the destination without restarting twice');
for(const mode of ['MENU','PLANNING','EXECUTING'])equal(debrief.doctrineReplaySeek({...state,mode},61),null,'Feedback seeks cannot affect a live plan');
equal(debrief.doctrineReplaySeek({...state,mission:''},61),null,'No mission means no replay request');
equal(debrief.doctrineReplaySeek({...state,replay:{duration:1,complete:false}},61),null,'Out-of-recording tick is rejected rather than clamped');
equal(debrief.doctrineReplaySeek({...state,replay:{duration:61/30,complete:false}},61),{action:'replay_seek',tick:61,time:61/30},'The exact last recorded tick remains available');
for(const duration of ['3',null,-1,NaN,Infinity])equal(debrief.doctrineReplaySeek({...state,replay:{duration}},61),null,'Malformed replay duration offers no seek');
for(const available of [false,'true',1,null,undefined]){
  sent.length=0;context.state={mode:'PLANNING',prior_attempt_available:available,prior_attempt_visible:true};context.renderPriorAttempt();context.togglePriorAttempt();
  equal([node('prior-attempt-toggle').hidden,node('prior-attempt-toggle').pressed,sent.length],[true,false,0],'Unavailable or malformed previous-attempt flags do not reveal an overlay');
}
for(const visible of [false,true]){
  sent.length=0;context.state={mode:'PLANNING',prior_attempt_available:true,prior_attempt_visible:visible};context.renderPriorAttempt();context.togglePriorAttempt();
  equal([node('prior-attempt-toggle').hidden,node('prior-attempt-toggle').pressed],[false,visible],'Button visibility and pressed state come from the native snapshot');
  equal(sent,[{action:'prior_attempt_visible',value:!visible}],'Both toggle directions send a strict boolean');
  equal(node('prior-attempt-toggle').pressed,visible,'The button does not optimistically replace the authoritative visibility');
}
for(const mode of ['EXECUTING','RESULT','REPLAY'])equal(debrief.priorAttemptPresentation({mode,prior_attempt_available:true,prior_attempt_visible:true}),{available:false,visible:false},'Previous-attempt overlay controls are planning-only');

const keys=[...ids.flatMap(id=>['debrief.'+id,'debrief.'+id+'_note']),...['title','source','unavailable','item','grade','measurement','doctrine','good','caution','fail','na','replay','tick','seconds','identification_value','control_value','control_rates'].map(key=>'debrief.'+key),'prior_attempt.title','prior_attempt.hint',...[0,1,2].map(value=>'debrief.stealth.'+value)];
for(const language of ['ko','en']){
  i18n.setLanguage(language);
  for(const key of keys){const text=i18n.t(key);check(text!==key&&text.length>0,'Paired '+language+' key '+key);if(language==='en')check(!/[가-힣]/.test(text),'English key '+key+' has no fallback Korean');}
  for(const key of ['frag_clock','frag_command','frag_projectiles','roe','observed_stats_missing','observed_stats_shape','observed_damage','observed_stats_value','frag_statistics','observed_stars','frag_event','room_doctrine_shape','room_doctrine_reference','room_doctrine_value','room_doctrine_evidence','room_doctrine_future']){
    const id='replay.error.'+key,text=i18n.t(id);check(text!==id,'Replay diagnostic '+id+' is localized in '+language);
    if(language==='ko')check(replaySource.includes(text),'Replay diagnostic matches actual native source');else check(!/[가-힣]/.test(text),'Replay diagnostic is English');
  }
}
check(html.indexOf('id="result-doctrine"')>html.indexOf('class="result-grid"')&&html.indexOf('id="result-doctrine"')<html.indexOf('id="result-partial"'),'Doctrine feedback stays inside the result grid before existing actions');
check(css.includes('.doctrine-rooms{max-height:min(280px,38dvh);overflow:auto;min-width:0'),'Room feedback has a bounded scrolling area');
check(css.includes('.prior-attempt-toggle{width:100%;min-width:0;flex:none;font-size:12px'),'Previous-attempt button stays within the existing sidebar width');
check(html.includes('id="prior-attempt-toggle"')&&html.includes('data-i18n-title="prior_attempt.hint"'),'Previous-attempt button includes paired visible and tooltip text');
console.log(`BREACH_DEBRIEF_WEB_RESULT checks=${checks} failures=0 status=PASS`);
