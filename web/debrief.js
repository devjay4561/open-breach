// Game objectives are evaluated from mission data; scores remain fictional mission points.
// No import of web/i18n.js here on purpose: tests/debrief-test.mjs loads
// this file through a base64 data: URL (to sandbox it from the rest of the
// app), and data: URLs have no base to resolve a relative `import` against.
// Localization is passed in as a plain `lang` argument instead, with both
// language's copy inlined below.
const successOf = state => state.result?.success === true || state.result?.status === 'SUCCESS' || state.result?.outcome === 'SUCCESS';
export function evaluateStar(star,state) {
  if(!successOf(state))return false;
  const result=state.result||{};
  // New results carry the simulation's authoritative authored-star verdicts.
  // A missing ID in that map is false; only legacy results without the map
  // use the former statistics calculation below.
  if(Object.prototype.hasOwnProperty.call(result,'stars'))return result.stars!==null&&typeof result.stars==='object'&&!Array.isArray(result.stars)&&Object.prototype.hasOwnProperty.call(result.stars,star.id)&&result.stars[star.id]===true;
  if(star.id==='complete')return true;
  if(star.id==='survival')return (state.units||[]).length>0&&(state.units||[]).every(unit=>unit.hp>0);
  const aliases={plan_revisions:['plan_changes','planning_changes'],command_failures:['failed_commands']};
  let actual=star.stat==='time'?state.time:star.stat==='units_deployed'?(result.units_deployed??(state.units||[]).length):result[star.stat];
  for(const alias of aliases[star.stat]||[])actual??=result[alias];
  // Old schema files omit the new counters. No counter means zero uses/hits.
  if(actual===undefined&&['stuns_used','reloads','hits_taken','kills','arrests','plan_revisions'].includes(star.stat))actual=0;
  actual=Number(actual);const expected=Number(star.value??star.limit??star.max??0);
  if(!Number.isFinite(actual)||!Number.isFinite(expected))return false;
  if(star.stat==='time'&&actual<=0)return false;
  switch(star.op||'eq') {
    case 'eq':return actual===expected;
    case 'lte':return actual<=expected;
    case 'gte':return actual>=expected;
    case 'lt':return actual<expected;
    case 'gt':return actual>expected;
    default:return false;
  }
}
const COPY = {
  ko: {
    star_complete:'임무 완료', star_survival:'전원 생존', star_par_time: time=>`${time}초 이내 완료`,
    first_attempt:'같은 조건의 첫 완료 기록에 도전하세요. 계획 중에는 시간이 흐르지 않습니다.',
    first_clear:'첫 임무 완료', new_best_score: delta=>`개인 최고 점수 +${delta}`,
    tied_best_time:'개인 최단 기록과 동률', faster_than_best: seconds=>`개인 최단 기록 ${seconds}초 단축`,
    slower_than_best: seconds=>`개인 최단 기록보다 ${seconds}초 더 소요`,
    cleared:'완료 기록을 남겼습니다.', previous_kept:'이전 완료 기록은 유지됩니다. 초기 계획을 수정해 다시 도전하세요.',
  },
  en: {
    star_complete:'Mission complete', star_survival:'Full squad survives', star_par_time: time=>`Finish within ${time}s`,
    first_attempt:'Go for the first clear under these conditions. Time does not pass while planning.',
    first_clear:'First clear', new_best_score: delta=>`New personal best +${delta}`,
    tied_best_time:'Tied your best time', faster_than_best: seconds=>`${seconds}s faster than your best`,
    slower_than_best: seconds=>`${seconds}s slower than your best`,
    cleared:'Operation cleared.', previous_kept:'Your previous clear record is kept. Revise the initial plan and try again.',
  },
};
export function summarizeRun(state, previous = {}, parTime = 180, lang = 'ko') {
  previous = previous || {};
  const c = COPY[lang] || COPY.ko;
  const result = state.result || {},success=successOf(state);
  const stars=Array.isArray(state.stars)&&state.stars.length?state.stars:[
    {id:'complete',label:c.star_complete}, {id:'survival',label:c.star_survival},
    {id:'par_time',label:c.star_par_time(parTime),stat:'time',op:'lte',value:parTime}
  ];
  const goals=stars.map(star=>({id:star.id,label:star.label||star.id,done:evaluateStar(star,state)}));
  let comparison = c.first_attempt;
  if (success) {
    const score = Number(result.score) || 0,elapsed = Number(state.time),best = Number(previous.bestTime),messages = [];
    if (!previous.completed) messages.push(c.first_clear);
    else if (score > (Number(previous.bestScore) || 0)) messages.push(c.new_best_score(score - Number(previous.bestScore || 0)));
    if (previous.completed && Number.isFinite(best) && best > 0 && Number.isFinite(elapsed) && elapsed > 0) {
      const difference = elapsed - best;
      messages.push(Math.abs(difference) < .05 ? c.tied_best_time : difference < 0 ? c.faster_than_best((-difference).toFixed(1)) : c.slower_than_best(difference.toFixed(1)));
    }
    comparison = messages.join(' · ') || c.cleared;
  } else if (previous.completed) comparison = c.previous_kept;
  return {goals, comparison};
}

const DOCTRINE_ROWS = ['stealth','doorway_dwell','time_to_dominate','threat_order_violations','identification','control','marked','rear_hits'];
const recordOf = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const finiteOf = value => typeof value === 'number' && Number.isFinite(value);
const tickOf = value => Number.isSafeInteger(value) && value >= 0;

// Both inputs are public snapshots. Authored room names alone are never
// evidence of observation, and unknown occupants/IDs are not copied to UI.
// The callback keeps this module independently loadable through a data URL.
export function roomDoctrineReport(snapshot = {}, authoredRooms = [], grader) {
  const states = snapshot?.room_states;
  if (!recordOf(states) || !Array.isArray(authoredRooms)) return [];
  const terminal = snapshot.mode === 'RESULT' || snapshot.mode === 'REPLAY' && finiteOf(snapshot.replay?.time) && finiteOf(snapshot.replay?.duration) && snapshot.replay.time >= snapshot.replay.duration;
  const source = terminal ? snapshot.result?.room_doctrine ?? snapshot.room_doctrine : snapshot.room_doctrine;
  const own = new Set((Array.isArray(snapshot.units) ? snapshot.units : []).map(unit => unit?.id).filter(id => typeof id === 'string'));
  const doors = new Set((Array.isArray(snapshot.doors) ? snapshot.doors : []).map(door => door?.id).filter(id => typeof id === 'string'));
  const report = [], seen = new Set();
  for (const room of authoredRooms.slice(0,64)) {
    const id = room?.id;
    if (typeof id !== 'string' || !id || seen.has(id) || !Object.hasOwn(states,id)) continue;
    seen.add(id);
    const observation = states[id];
    if (observation?.observed !== true || !['UNKNOWN','CONTACT','DOMINATED','CLEAR','MARKED'].includes(observation.state)) continue;
    const metrics = recordOf(source) && Object.hasOwn(source,id) && recordOf(source[id]) ? source[id] : {};
    const safe = Object.create(null);
    for (const metric of DOCTRINE_ROWS) {
      const row = Object.hasOwn(metrics,metric) && recordOf(metrics[metric]) ? metrics[metric] : {};
      const copy = {value:finiteOf(row.value)?row.value:null,tick:tickOf(row.tick)?row.tick:null,time:finiteOf(row.time)&&row.time>=0?row.time:null};
      for (const field of ['civilian_damage','unlawful_shots','arrested','surrendered','secured','civilians']) if (Object.hasOwn(row,field)) copy[field] = finiteOf(row[field]) ? row[field] : null;
      if (own.has(row.unit_id)) copy.unit_id = row.unit_id;
      if (doors.has(row.door_id)) copy.door_id = row.door_id;
      safe[metric] = copy;
    }
    const graded = typeof grader === 'function' ? grader(safe) : [];
    const rows = DOCTRINE_ROWS.map(metric => {
      const row = Array.isArray(graded) ? graded.find(item => item?.id === metric) : null;
      const grade = ['good','caution','fail','na'].includes(row?.grade) ? row.grade : 'na';
      const tick = tickOf(row?.tick) ? row.tick : null;
      const details = {...safe[metric]};
      for (const field of ['arrest_rate','secure_rate']) if (finiteOf(row?.details?.[field]) && row.details[field]>=0 && row.details[field]<=1) details[field] = row.details[field];
      const result = {id:metric,grade,value:finiteOf(row?.value)?row.value:null,tick,time:finiteOf(row?.time)&&row.time>=0?row.time:null,replay_time:tick===null?null:tick*(1/30),details};
      if (own.has(row?.unit_id)) result.unit_id = row.unit_id;
      if (doors.has(row?.door_id)) result.door_id = row.door_id;
      return result;
    });
    report.push({id,label:typeof room.label==='string'?room.label:id,label_en:typeof room.label_en==='string'?room.label_en:'',rows});
  }
  return report;
}

export function doctrineReplaySeek(snapshot = {}, tick) {
  if (!['RESULT','REPLAY'].includes(snapshot.mode) || typeof snapshot.mission !== 'string' || !snapshot.mission || !tickOf(tick)) return null;
  const replay = snapshot.replay;
  // A partial recording cannot reproduce a later failure. Refuse that tick
  // rather than seek to a different frame at the end of the available clip.
  if (recordOf(replay) && Object.hasOwn(replay,'duration') && (!finiteOf(replay.duration) || replay.duration<0 || tick>Math.round(replay.duration*30))) return null;
  return {action:'replay_seek',tick,time:tick/30};
}

export function priorAttemptPresentation(snapshot = {}) {
  const available = snapshot.mode === 'PLANNING' && snapshot.prior_attempt_available === true;
  return {available,visible:available && snapshot.prior_attempt_visible === true};
}
