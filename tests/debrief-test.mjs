import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const {summarizeRun}=await import('data:text/javascript;base64,'+Buffer.from(await readFile(new URL('../web/debrief.js',import.meta.url))).toString('base64'));
const state={result:{success:true,score:100},time:75,units:[{hp:100},{hp:20}]};
assert(summarizeRun(state).comparison.includes('첫 임무 완료'));
assert(summarizeRun(state,{completed:true,bestTime:90,bestScore:90}).comparison.includes('15.0초 단축'));
assert(summarizeRun(state,{completed:true,bestTime:60,bestScore:100}).comparison.includes('15.0초 더 소요'));
assert(summarizeRun(state,{completed:true,bestTime:75,bestScore:100}).comparison.includes('동률'));
assert.equal(summarizeRun(state).goals.filter(x=>x.done).length,3);
assert.equal(summarizeRun({...state,result:{success:false}}).goals.filter(x=>x.done).length,0);
assert(!summarizeRun({...state,units:[{hp:0}]}).goals[1].done);
assert(!summarizeRun(state,{},60).goals[2].done);
assert(summarizeRun(state,{},75).goals[2].done);
assert(!summarizeRun({...state,time:0}).goals[2].done);
assert(!summarizeRun({...state,time:NaN}).goals[2].done);
assert(!summarizeRun({...state,units:[]}).goals[1].done);
console.log('Debrief: 12 checks passed');
const starState={...state,result:{success:true,score:100,plan_revisions:0,stuns_used:0,hits_taken:0,reloads:0,units_deployed:2,kills:0}};
const stars=[
 {id:'single_plan',label:'단일 계획',stat:'plan_revisions',op:'eq',value:0},
 {id:'no_stun',label:'스턴 미사용',stat:'stuns_used',op:'eq',value:0},
 {id:'no_hits',label:'피격 0',stat:'hits_taken',op:'eq',value:0},
 {id:'small_team',label:'소수 투입',stat:'units_deployed',op:'lte',value:2},
 {id:'no_reload',label:'재장전 0',stat:'reloads',op:'eq',value:0},
 {id:'no_kills',label:'무사살',stat:'kills',op:'eq',value:0}
];
assert.equal(summarizeRun({...starState,stars}).goals.filter(goal=>goal.done).length,6);
for(const star of stars) {
 const good={...starState,stars:[star]};assert.equal(summarizeRun(good).goals[0].done,true,star.id+' success');
 const value=star.stat==='units_deployed'?3:1;
 const bad={...good,result:{...good.result,[star.stat]:value}};
 assert.equal(summarizeRun(bad).goals[0].done,false,star.id+' failed condition');
 assert.equal(summarizeRun({...good,result:{...good.result,success:false}}).goals[0].done,false,star.id+' failed mission');
}
assert.equal(summarizeRun({...starState,stars:[{id:'unknown',stat:'kills',op:'unknown',value:0}]}).goals[0].done,false);
assert.equal(summarizeRun({...starState,stars:[{id:'bad_value',stat:'hits_taken',op:'eq',value:'oops'}]}).goals[0].done,false);
assert.equal(summarizeRun({...starState,stars:[{id:'no_hits',label:'피격 0',stat:'hits_taken',op:'eq',value:0}]}).goals[0].id,'no_hits');
console.log('Debrief stars: 22 additional checks passed');

// Both modules remain independently loadable through data: URLs. Doctrine
// feedback is injected into debrief as a callback rather than a relative import.
const {gradeRoomDoctrine}=await import('data:text/javascript;base64,'+Buffer.from(await readFile(new URL('../web/quality-metrics.js',import.meta.url))).toString('base64'));
const {roomDoctrineReport,doctrineReplaySeek}=await import('data:text/javascript;base64,'+Buffer.from(await readFile(new URL('../web/debrief.js',import.meta.url))).toString('base64'));
const metricIds=['stealth','doorway_dwell','time_to_dominate','threat_order_violations','identification','control','marked','rear_hits'];
let doctrineChecks=0;
function doctrineEqual(actual,expected,label){doctrineChecks++;assert.deepEqual(actual,expected,label);}
function graded(id,value,extras={}){return gradeRoomDoctrine({[id]:{value,tick:43,time:43/30,...extras}}).find(row=>row.id===id);}
function grade(id,value,expected,extras={}){doctrineEqual(graded(id,value,extras).grade,expected,`${id} at ${String(value)}`);}

for(const source of [undefined,null,{},[],false,1,'unknown']) {
 const rows=gradeRoomDoctrine(source);
 doctrineEqual(rows.map(row=>row.id),metricIds,'stable eight doctrine rows');
 doctrineEqual(rows.map(row=>row.grade),metricIds.map(()=>'na'),'missing doctrine has no invented success');
 doctrineEqual(rows.map(row=>[row.value,row.tick,row.time,row.replay_time]),metricIds.map(()=>[null,null,null,null]),'unknown measurements and clocks stay null');
}
for(const id of metricIds) {
 for(const value of [undefined,null,-.001,NaN,Infinity,-Infinity,true,false,'0',[],{}]) {
  const row=graded(id,value,{civilian_damage:0,unlawful_shots:0,arrested:1,surrendered:1,secured:1,civilians:1});
  doctrineEqual(row.grade,'na',`${id} rejects invalid measurement ${String(value)}`);
  doctrineEqual(row.value,null,`${id} does not display an unknown measurement as zero`);
 }
 for(const source of [null,[],true,1,'0'])doctrineEqual(gradeRoomDoctrine({[id]:source}).find(row=>row.id===id).grade,'na',`${id} needs a measurement object`);
}
for(const [value,expected] of [[0,'good'],[1,'caution'],[2,'fail'],[.5,'na'],[3,'na']])grade('stealth',value,expected);
for(const [value,expected] of [[0,'good'],[.75-1e-9,'good'],[.75,'good'],[.75+1e-9,'caution'],[1.5-1e-9,'caution'],[1.5,'caution'],[1.5+1e-9,'fail'],[Number.MAX_VALUE,'fail']])grade('doorway_dwell',value,expected);
for(const [value,expected] of [[0,'good'],[3-1e-9,'good'],[3,'good'],[3+1e-9,'caution'],[5-1e-9,'caution'],[5,'caution'],[5+1e-9,'fail'],[Number.MAX_VALUE,'fail']])grade('time_to_dominate',value,expected);
for(const id of ['threat_order_violations','rear_hits'])for(const [value,expected] of [[0,'good'],[Number.MIN_VALUE,'fail'],[1,'fail'],[Number.MAX_VALUE,'fail']])grade(id,value,expected);
for(const [value,expected] of [[0,'fail'],[1,'good'],[.5,'na'],[2,'na']])grade('marked',value,expected);

grade('identification',0,'good',{civilian_damage:0,unlawful_shots:0});
grade('identification',1,'fail',{civilian_damage:Number.MIN_VALUE,unlawful_shots:0});
grade('identification',1,'fail',{civilian_damage:0,unlawful_shots:1});
grade('identification',1,'fail',{civilian_damage:Number.MAX_VALUE,unlawful_shots:Number.MAX_SAFE_INTEGER});
grade('identification',0,'fail',{civilian_damage:.25,unlawful_shots:0});
for(const extras of [{},{civilian_damage:0},{unlawful_shots:0},{civilian_damage:null,unlawful_shots:0},{civilian_damage:0,unlawful_shots:null}]) {
 const row=graded('identification',0,extras);doctrineEqual(row.grade,'na','identification requires both observed receipts');doctrineEqual(row.value,null,'unknown civilian damage does not imply zero');
}
for(const value of [-1,NaN,Infinity,true,'0',null])grade('identification',0,'na',{civilian_damage:value,unlawful_shots:0});
for(const value of [-1,.5,NaN,Infinity,true,'0',null,Number.MAX_SAFE_INTEGER+1])grade('identification',0,'na',{civilian_damage:0,unlawful_shots:value});
grade('identification',2,'na',{civilian_damage:0,unlawful_shots:0});

const controlled={arrested:1,surrendered:1,secured:1,civilians:1};
grade('control',1,'good',controlled);
grade('control',1,'caution',{...controlled,secured:0});
grade('control',1,'fail',{...controlled,arrested:0,secured:0});
const partial=graded('control',1,{arrested:1,surrendered:2,secured:2,civilians:3});
doctrineEqual(partial.value,3/5,'control derives the combined ratio from observed counts');
doctrineEqual(partial.details.arrest_rate,1/2,'capture and civilian rates remain separate');
doctrineEqual(partial.details.secure_rate,2/3,'civilian control rate uses civilian population');
doctrineEqual(partial.grade,'caution','incomplete control is caution');
const noPeople=graded('control',0,{arrested:0,surrendered:0,secured:0,civilians:0});
doctrineEqual(noPeople.grade,'na','an empty control denominator is not success');
doctrineEqual(noPeople.value,null,'an empty control denominator is unknown applicability');
grade('control',null,'na',controlled);
grade('control',2,'na',controlled);
grade('control',1,'good',{arrested:1,surrendered:1,secured:0,civilians:0});
doctrineEqual(graded('control',1,{arrested:1,surrendered:1,secured:0,civilians:0}).details.secure_rate,null,'absent civilians have no invented rate');
grade('control',1,'good',{arrested:0,surrendered:0,secured:1,civilians:1});
grade('control',0,'caution',{arrested:1,surrendered:2,secured:0,civilians:0});
for(const key of Object.keys(controlled)) {
 const missing={...controlled};delete missing[key];grade('control',1,'na',missing);
 for(const value of [-1,.5,NaN,Infinity,true,'1',null,Number.MAX_SAFE_INTEGER+1])grade('control',1,'na',{...controlled,[key]:value});
}
grade('control',1,'na',{...controlled,arrested:2});
grade('control',1,'na',{...controlled,secured:2});
grade('control',1,'good',{arrested:Number.MAX_SAFE_INTEGER,surrendered:Number.MAX_SAFE_INTEGER,secured:0,civilians:0});
grade('control',1,'na',{arrested:Number.MAX_SAFE_INTEGER,surrendered:Number.MAX_SAFE_INTEGER,secured:1,civilians:1});

for(const tick of [0,1,43,301,2147483647,Number.MAX_SAFE_INTEGER]) {
 const row=graded('doorway_dwell',1.8,{tick,time:999});
 doctrineEqual(row.tick,tick,'exact replay tick is retained');
 doctrineEqual(row.replay_time,tick*(1/30),'tick determines replay time even when display time is rounded or inconsistent');
}
for(const tick of [undefined,null,-1,1.5,NaN,Infinity,true,'43',Number.MAX_SAFE_INTEGER+1]) {
 const row=graded('doorway_dwell',1.8,{tick,time:1.4});
 doctrineEqual(row.tick,null,'invalid replay tick is not coerced');
 doctrineEqual(row.replay_time,null,'display time does not replace an exact replay tick');
}
for(const time of [undefined,null,-1,NaN,Infinity,true,'1.4'])doctrineEqual(graded('doorway_dwell',1.8,{time}).time,null,'invalid measurement time is not coerced');
const sourceMetrics={doorway_dwell:{value:1.8,tick:43,time:43/30,unit_id:'alpha',door_id:'entry',hidden_enemy:{x:7,z:8}},control:{value:1,...controlled}};
const sourceCopy=structuredClone(sourceMetrics),sourceRows=gradeRoomDoctrine(sourceMetrics);
doctrineEqual(sourceMetrics,sourceCopy,'grading never mutates the public input');
doctrineEqual(sourceRows[1].unit_id,'alpha','own-unit provenance can be copied');
doctrineEqual(sourceRows[1].door_id,'entry','door provenance can be copied');
doctrineEqual(Object.hasOwn(sourceRows[1],'hidden_enemy'),false,'unknown or private provenance is not copied');
sourceRows[5].details.arrested=99;
doctrineEqual(sourceMetrics.control.arrested,1,'returned details do not alias source receipts');
for(const id of ['bad id','../door','x'.repeat(65),null,true,1,{},[]])doctrineEqual(Object.hasOwn(graded('rear_hits',1,{unit_id:id,door_id:id}),'unit_id'),false,'malformed provenance is not copied');

const knownRoom={id:'front',label:'앞방',label_en:'Front room'};
const snapshot={mode:'RESULT',mission:'DOCTRINE_FIXTURE',tick:100,time:100/30,units:[{id:'alpha'}],doors:[{id:'entry'}],room_states:{front:{state:'MARKED',observed:true},hidden:{state:'UNKNOWN',observed:false}},room_doctrine:{front:sourceMetrics,hidden:{rear_hits:{value:1,tick:50,time:50/30}}}};
const report=roomDoctrineReport(snapshot,[knownRoom,{id:'hidden',label:'숨은 방'}],gradeRoomDoctrine);
doctrineEqual(report.length,1,'only observed authored rooms reach the grading callback');
doctrineEqual(report[0].id,'front','observed room identity is retained');
doctrineEqual(report[0].rows.map(row=>row.id),metricIds,'debrief callback produces the eight doctrine rows');
const failedDoorway=report[0].rows.find(row=>row.id==='doorway_dwell');
doctrineEqual(failedDoorway.grade,'fail','debrief receives the grader failure');
doctrineEqual(failedDoorway.tick,43,'debrief retains the evidence tick exactly');
doctrineEqual(failedDoorway.replay_time,43*(1/30),'debrief link uses exact fixed-step conversion');
doctrineEqual(roomDoctrineReport({...snapshot,room_states:{front:{state:'MARKED',observed:false}}},[knownRoom],gradeRoomDoctrine).length,0,'hidden room state does not disclose a report');
doctrineEqual(roomDoctrineReport({},[knownRoom],gradeRoomDoctrine).length,0,'legacy state does not disclose authored room list');
doctrineEqual(roomDoctrineReport(snapshot,[knownRoom]).map(room=>room.rows.map(row=>row.grade)),[metricIds.map(()=>'na')],'missing grader remains unavailable');
const seek=doctrineReplaySeek(snapshot,43);
doctrineEqual(seek?.tick,43,'native seek action receives the exact tick');
doctrineEqual(seek?.time,43*(1/30),'native seek time corresponds to that same tick');
for(const tick of [-1,1.5,NaN,Infinity,true,'43'])doctrineEqual(doctrineReplaySeek(snapshot,tick),null,'invalid seek evidence does not produce a replay action');
console.log(`Debrief room doctrine: ${doctrineChecks} additional checks passed`);
