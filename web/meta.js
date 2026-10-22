// BEGIN GENERATED EQUIPMENT CATALOG
// Source: game/data/equipment_catalog.json. Run node scripts/sync_equipment_catalog.mjs.
export const CATALOG = {"version":1,"defaults":{"weapon":"standard","equipment":{"stun":1},"sidearm":"pico_p1","armor":"frame_v2","helmet":"crown_h1","attachments":[],"appearance":{"name":"","callsign":"","color":"#2e5146","patch":"breach"},"preset":"custom"},"weapons":[{"id":"standard","label":"테른 C1","label_en":"Tern C1","stars":0,"stats":{"ammo":24,"damage":44,"interval":0.45,"accuracy":0.97,"reload":1.8,"range":10,"sound":10,"length":0.86,"aim_time":0.35,"switch_time":0.45,"penetration":22},"note":"균형 잡힌 소총 · 사거리 10m · 탄창 24발","note_en":"Balanced rifle · 10m range · 24-round magazine","model":"res://assets/equipment/tern_c1.glb","weight":2.8},{"id":"light","label":"미카 S2","label_en":"Mica S2","stars":0,"stats":{"ammo":32,"damage":32,"interval":0.3,"accuracy":0.95,"reload":1.4,"range":8.5,"sound":8,"length":0.62,"aim_time":0.26,"switch_time":0.35,"penetration":14},"note":"짧은 기관단총 · 빠른 조준과 연사 · 관통력 낮음","note_en":"Compact SMG · fast aiming and fire · lower penetration","model":"res://assets/equipment/mica_s2.glb","weight":2.1},{"id":"shotgun","label":"플린트 B1","label_en":"Flint B1","stars":4,"stats":{"ammo":8,"damage":84,"interval":0.9,"accuracy":0.97,"reload":2.4,"range":5,"sound":14,"length":1.02,"aim_time":0.43,"switch_time":0.55,"penetration":12},"note":"근거리 고피해 · 사거리 5m · 탄창 8발","note_en":"High close-range damage · 5m range · 8-round magazine","model":"res://assets/equipment/flint_b1.glb","weight":3.4},{"id":"suppressed","label":"테른 C1-Q","label_en":"Tern C1-Q","stars":8,"stats":{"ammo":18,"damage":44,"interval":0.45,"accuracy":0.97,"reload":2.2,"range":10,"sound":3,"length":1.06,"aim_time":0.41,"switch_time":0.5,"penetration":22},"note":"내장 소음기 · 소리 반경 3m · 작은 탄창과 긴 재장전","note_en":"Built-in suppressor · 3m sound radius · smaller magazine and longer reload","model":"res://assets/equipment/tern_c1.glb","weight":3.1}],"sidearms":[{"id":"pico_p1","label":"피코 P1","label_en":"Pico P1","stars":0,"weight":0.75,"model":"res://assets/equipment/pico_p1.glb","stats":{"ammo":12,"damage":26,"interval":0.36,"accuracy":0.94,"reload":1.2,"range":6,"sound":6,"length":0.23,"aim_time":0.2,"switch_time":0.3,"penetration":12},"note":"짧은 보조권총 · 별도 탄창 12발 · 전환 0.3초","note_en":"Compact sidearm · separate 12-round magazine · 0.3s switch"}],"armor":[{"id":"veil_v1","label":"베일 V1","label_en":"Veil V1","stars":0,"weight":1.6,"movement_multiplier":1,"action_multiplier":1,"panels":[{"panel":"soft","regions":["torso"],"arc":[-180,180],"resistance":15,"reduction":0.42}],"color":"#405947","note":"가벼운 연질 방호 · 몸통 전 방향 · 소총 관통에 취약","note_en":"Light soft armor; covers torso all around, limited protection against rifles.","model":"res://assets/equipment/veil_v1.glb"},{"id":"frame_v2","label":"프레임 V2","label_en":"Frame V2","stars":0,"weight":4,"movement_multiplier":0.94,"action_multiplier":1.04,"panels":[{"panel":"front","regions":["torso"],"arc":[-65,65],"resistance":32,"reduction":0.62},{"panel":"back","regions":["torso"],"arc":[115,245],"resistance":32,"reduction":0.62},{"panel":"side","regions":["torso"],"arc":[-180,180],"resistance":20,"reduction":0.38}],"color":"#35414b","note":"앞·뒤·측면 방호 · 이동과 보호의 균형","note_en":"Front, back and side plates; balanced protection and movement.","model":"res://assets/equipment/frame_v2.glb"},{"id":"swift_v3","label":"스위프트 V3","label_en":"Swift V3","stars":0,"weight":2.8,"movement_multiplier":0.98,"action_multiplier":1.01,"panels":[{"panel":"front","regions":["torso"],"arc":[-60,60],"resistance":34,"reduction":0.66},{"panel":"back","regions":["torso"],"arc":[120,240],"resistance":34,"reduction":0.66}],"color":"#a58b65","note":"앞·뒤 강화판 · 측면 노출 · 가벼운 이동 부담","note_en":"Strong front and back plates; exposed sides, less movement cost.","model":"res://assets/equipment/swift_v3.glb"},{"id":"bastion_v4","label":"바스천 V4","label_en":"Bastion V4","stars":0,"weight":6,"movement_multiplier":0.86,"action_multiplier":1.12,"panels":[{"panel":"front","regions":["torso"],"arc":[-80,80],"resistance":42,"reduction":0.74},{"panel":"back","regions":["torso"],"arc":[100,260],"resistance":42,"reduction":0.74},{"panel":"side","regions":["torso"],"arc":[-180,180],"resistance":30,"reduction":0.55}],"color":"#4f573c","note":"넓은 방탄판과 강한 방호 · 이동·조작 느림","note_en":"Wide plate coverage and high resistance; slower movement and actions.","model":"res://assets/equipment/bastion_v4.glb"}],"helmets":[{"id":"crown_h1","label":"크라운 H1","label_en":"Crown H1","stars":0,"weight":0.8,"color":"#35414b","resistance":18,"reduction":0.42,"regions":["head"],"note":"가벼운 머리 방호 · 소총 탄환에는 제한적","note_en":"Light head protection; limited against rifle rounds.","model":"res://assets/equipment/crown_h1.glb"},{"id":"crown_h2","label":"크라운 H2","label_en":"Crown H2","stars":0,"weight":1.4,"color":"#4f573c","resistance":28,"reduction":0.58,"regions":["head"],"action_multiplier":1.03,"movement_multiplier":0.98,"note":"강한 머리 방호 · 무게와 조작 부담 증가","note_en":"Stronger head protection; heavier and slightly slower actions.","model":"res://assets/equipment/crown_h2.glb"}],"attachments":[{"id":"dot","label":"포인트 D1 도트","label_en":"Point D1 dot sight","slot":"optic","stars":0,"weight":0.15,"weapons":["standard","light","shotgun","suppressed"],"modifiers":{"accuracy_add":0.01,"aim_time_multiplier":0.85},"note":"조준 준비 15% 단축 · 정확도 +1%p","note_en":"15% faster aiming · accuracy +1 percentage point","model":"res://assets/equipment/dot.glb"},{"id":"scope","label":"포커스 O2 조준경","label_en":"Focus O2 scope","slot":"optic","stars":0,"weight":0.35,"weapons":["standard","suppressed"],"modifiers":{"range_add":2,"aim_time_multiplier":1.15},"note":"사거리 +2m · 조준 준비 15% 증가","note_en":"Range +2m · 15% longer aiming","model":"res://assets/equipment/scope.glb"},{"id":"suppressor","label":"콰이어트 Q1 소음기","label_en":"Quiet Q1 suppressor","slot":"muzzle","stars":0,"weight":0.3,"weapons":["standard","light"],"modifiers":{"sound_multiplier":0.4,"length_add":0.2,"aim_time_multiplier":1.06},"note":"소음 반경 60% 감소 · 총 길이 +20cm","note_en":"60% smaller sound radius · weapon length +20cm","model":"res://assets/equipment/suppressor.glb"},{"id":"extended_mag","label":"리저브 M1 탄창","label_en":"Reserve M1 magazine","slot":"magazine","stars":0,"weight":0.3,"weapons":["standard","light","suppressed"],"modifiers":{"ammo_add":8,"reload_multiplier":1.15},"note":"장탄 +8발 · 재장전 15% 증가","note_en":"8 extra rounds · 15% longer reload","model":"res://assets/equipment/extended_mag.glb"}],"equipment":[{"id":"stun","label":"플레어 F1 섬광탄","label_en":"Flare F1 flashbang","stars":0,"slot":"small","weight":0.2,"note":"적·민간인 약 2초 기절 · 아군 면역 · 체력 피해 없음","note_en":"Stuns enemies and civilians for about 2s · allies immune · no health damage"},{"id":"smoke","label":"헤이즈 S1 연막","label_en":"Haze S1 smoke","stars":3,"slot":"small","weight":0.3,"note":"4초간 양쪽의 시야 차단","note_en":"Blocks sightlines both ways for 4 seconds"},{"id":"breach","label":"노크 B1 진입 장약","label_en":"Knock B1 breach charge","stars":6,"slot":"large","weight":1,"note":"문을 빠르게 개방 · 큰 소음 발생","note_en":"Rapid door opening · loud blast"},{"id":"probe_c1","label":"프로브 C1 카메라","label_en":"Probe C1 camera","stars":0,"slot":"small","weight":0.3,"note":"관측한 문 너머 정찰 · 과거 정보는 관측 시각 표시","note_en":"Scout beyond an observed door · remembered contacts carry timestamps","model":"res://assets/equipment/probe_c1.glb"},{"id":"frag","label":"파편 수류탄","label_en":"Fragmentation grenade","stars":0,"slot":"small","weight":0.4,"note":"고강도 작전 전용 · 파편은 석고 내벽을 관통하며 아군도 피해를 입음","note_en":"High intensity operations only · fragments penetrate plaster walls and can injure operators"}],"presets":[{"id":"assault","label":"균형 진입","label_en":"Balanced entry","loadout":{"weapon":"standard","sidearm":"pico_p1","armor":"frame_v2","helmet":"crown_h1","attachments":["dot"],"equipment":{"stun":2}}},{"id":"breacher","label":"근거리 돌파","label_en":"Close entry","loadout":{"weapon":"light","sidearm":"pico_p1","armor":"bastion_v4","helmet":"crown_h2","attachments":["dot"],"equipment":{"stun":1,"probe_c1":1}}},{"id":"scout","label":"조용한 정찰","label_en":"Quiet scout","loadout":{"weapon":"light","sidearm":"pico_p1","armor":"veil_v1","helmet":"crown_h1","attachments":["suppressor"],"equipment":{"probe_c1":1,"stun":1}}},{"id":"marksman","label":"거리 엄호","label_en":"Range support","loadout":{"weapon":"standard","sidearm":"pico_p1","armor":"swift_v3","helmet":"crown_h1","attachments":["scope"],"equipment":{"stun":1}}}],"appearance":{"colors":["#2e5146","#40516c","#746047","#663e48","#555b61"],"patches":["breach","raven","arrow","shield"]},"slots":{"small":2,"large":1,"legacy_total":2},"friendly_movement_accuracy":{"careful":0.94,"normal":0.84,"fast":0.68},"handling":{"reference_length":0.86,"length_aim_penalty":0.3},"traits":{"marksman":{"range_add":2,"interval_multiplier":1.5}}};
// END GENERATED EQUIPMENT CATALOG
// Local progression uses fixed rules and never changes an operator's base stats.
// `label_en`/`name_en`/`note_en`/`description_en` are read by web/app.js via
// `localize()` (web/i18n.js's getLanguage()) when settings.language==='en';
// Korean fields stay the fallback and source of truth.
export const MODIFIERS = [
  {id:'night',label:'야간',label_en:'Night',description:'야간 조명 · 관측과 식별 감소',description_en:'Night lighting · reduced visibility and identification'},
  {id:'dim',label:'낮은 조도',label_en:'Dim lighting',description:'낮은 조명 · 관측과 식별 감소',description_en:'Dim lighting · reduced visibility and identification'},
  {id:'low_ammo',label:'탄약 절반',label_en:'Half ammo',description:'시작 탄약 절반',description_en:'Starting ammo halved'},
  {id:'fast_reaction',label:'빠른 대응',label_en:'Fast reaction',description:'적 반응 시간 감소',description_en:'Reduced enemy reaction time'},
  {id:'no_stun',label:'스턴 금지',label_en:'No stun',description:'스턴을 사용할 수 없음',description_en:'Stun grenades disabled'}
];
export const VARIANTS = [
  {id:'standard',label:'구역 확보',label_en:'Area Secure',suffix:''}, {id:'infiltration',label:'잠입',label_en:'Infiltration',suffix:'INFILTRATION'},
  {id:'timed',label:'시간 제한',label_en:'Timed',suffix:'TIMED'}, {id:'hostage',label:'인질 구출',label_en:'Hostage Rescue',suffix:'HOSTAGE'},
  {id:'escort',label:'호송',label_en:'Escort',suffix:'ESCORT'}
];
export const EQUIPMENT = CATALOG.equipment;
export const WEAPONS = CATALOG.weapons;
export const CUSTOMIZATION_GEAR = [...CATALOG.sidearms,...CATALOG.armor,...CATALOG.helmets,...CATALOG.attachments];
export const ROSTER = [
  {id:'raven',name:'레이븐',name_en:'Raven',trait:'breacher',label:'문 열기 시간 절반',label_en:'Half door-open time'},
  {id:'echo',name:'에코',name_en:'Echo',trait:'marksman',label:'사거리 +2m · 발사 간격 1.5배',label_en:'Range +2m · fire interval ×1.5'},
  {id:'moss',name:'모스',name_en:'Moss',trait:'cautious',label:'제압 시 명중률 감소 완화',label_en:'Reduced accuracy loss under suppression'},
  {id:'lark',name:'라크',name_en:'Lark',trait:'rescuer',label:'민간인 확보 시간 절반',label_en:'Half civilian-secure time'},
  {id:'rook',name:'루크',name_en:'Rook',trait:'breacher',label:'문 열기 시간 절반',label_en:'Half door-open time'},
  {id:'kite',name:'카이트',name_en:'Kite',trait:'marksman',label:'사거리 +2m · 발사 간격 1.5배',label_en:'Range +2m · fire interval ×1.5'},
  {id:'fern',name:'펀',name_en:'Fern',trait:'cautious',label:'제압 시 명중률 감소 완화',label_en:'Reduced accuracy loss under suppression'},
  {id:'wren',name:'렌',name_en:'Wren',trait:'rescuer',label:'민간인 확보 시간 절반',label_en:'Half civilian-secure time'}
];
export function hashSeed(value) {
  let hash=2166136261;
  for (const character of String(value)) hash=Math.imul(hash^character.charCodeAt(0),16777619)>>>0;
  return hash || 1;
}
export function localDate(date = new Date()) {
  return `${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,'0')}-${String(date.getDate()).padStart(2,'0')}`;
}
export function dailyOperation(date = localDate(), bases = CAMPAIGN_MISSIONS) {
  bases=CAMPAIGN_MISSIONS.filter(id=>bases.includes(id));if(!bases.length)bases=['M01'];
  const seed=(hashSeed(`breach-daily:${date}`)%2147483646)+1;
  const variant=VARIANTS[1+(seed>>>3)%(VARIANTS.length-1)];
  const modifiers=MODIFIERS.filter((_,index)=>((seed>>>(index+10))&1)===1).map(item=>item.id).filter((id,_,all)=>id!=='dim'||!all.includes('night'));
  const base=bases[seed%bases.length], expanded=Number(base.slice(1))>=4;
  return {date,id:expanded?base:`${base}_${variant.suffix}`,seed,variant:expanded?'standard':variant.id,modifiers};
}
export const ROE_MISSIONS=['M01_PRECISION','M01_HIGH_INTENSITY'];
export const SHOOT_HOUSE_MISSIONS=['SH01','SH02','SH03','SH04','SH05_PRECISION','SH05_HIGH_INTENSITY'];
export const CQB_PUZZLE_MISSIONS=Array.from({length:12},(_,index)=>`CQB${String(index+1).padStart(2,'0')}`);
export const CQB_MISSIONS=[...SHOOT_HOUSE_MISSIONS,...CQB_PUZZLE_MISSIONS];
export function isCQBContentMission(id) {return CQB_MISSIONS.includes(String(id));}
export function isStandaloneMission(id) {return ROE_MISSIONS.includes(String(id))||isCQBContentMission(id);}
export function missionBase(id='M01') { return isStandaloneMission(id)?String(id):String(id).match(/^(T01|M\d{2})/)?.[0] || String(id); }
export function missionId(base, difficulty='normal',variant='standard') {
	base=missionBase(base);if(isStandaloneMission(base)||base==='T01'||/^H\d{2}$/.test(base))return base;
  const suffix=Number(base.slice(1))>=4?null:VARIANTS.find(item=>item.id===variant)?.suffix;
  return suffix?`${base}_${suffix}`:base+(difficulty==='challenge'?'H':'');
}
export function migrateMedals(value) {
  if(Array.isArray(value))return Object.fromEntries(['complete','survival','par_time'].map((id,index)=>[id,!!value[index]]));
  if(value&&typeof value==='object')return Object.fromEntries(Object.entries(value).map(([id,done])=>[id,done===true]));
  return {};
}
export function mergeStars(previous={},goals=[]) {
  const stars=migrateMedals(previous.stars||previous.medals);
  for (const goal of goals) stars[goal.id]=Boolean(stars[goal.id]||goal.done);
  return stars;
}
export function totalStars(records) {
  let total=0;
  for(const record of records instanceof Map?records.values():records||[]){
    if(record.kind==='run'||record.kind==='campaign'||String(record.id).startsWith('run:')||record.id==='campaign')continue;
    for(const done of Object.values(migrateMedals(record.stars||record.medals)))if(done)total++;
  }
  return total;
}
function canonical(value) {
  if(Array.isArray(value))return value.map(canonical);
  if(value&&typeof value==='object')return Object.fromEntries(Object.keys(value).sort().map(key=>[key,canonical(value[key])]));
  return value;
}
export function conditionKey({mission,map_id,id,seed=0,variant='standard',modifiers=[],loadout={},roster=[]}) {
  const missionName=mission||map_id||id;
  if(['standard','base'].includes(variant))variant=String(missionName).endsWith('H')?'challenge':'normal';
  return `run:${JSON.stringify(canonical({mission:missionName,seed:Number(seed),variant,modifiers:[...new Set(modifiers)].sort(),loadout,roster:roster.map(item=>({id:item.id,trait:item.trait,base_id:item.base_id})).sort((a,b)=>String(a.base_id).localeCompare(String(b.base_id)))}))}`;
}
export const CAMPAIGN_MISSIONS=['M01','M02','M03','M04','M05','M06','M07','M08','M09'];
export const HISTORICAL_IDS=["H01", "H02", "H03", "H04", "H06", "H07", "H09", "H11", "H16", "H26", "H29", "H36"];
export const HISTORICAL_UNLOCKS=Array.from({length:6},(_,index)=>({id:`history-${index+1}`,kind:'history',stars:(index+1)*6,missions:Array.from({length:6},(_,offset)=>`H${String(index*6+offset+1).padStart(2,'0')}`).filter(id=>HISTORICAL_IDS.includes(id))})).filter(item=>item.missions.length);
export function isProgressionMission(id) {
  return id==='T01'||/^M0[1-9]H?$/.test(id)||/^M0[1-3]_(?:HOSTAGE|ESCORT|INFILTRATION|TIMED|ARREST)$/.test(id)||/^H(?:0[1-9]|[12]\d|3[0-6])$/.test(id);
}
// Unlocks derive from saved best records; replaying a goal never spends or duplicates stars.
export function progressionState(records,campaign=null) {
  const missions=Array.from(records instanceof Map?records.values():records||[]).filter(record=>isProgressionMission(record.id)&&record.kind!=='run'&&record.kind!=='campaign');
  const completed=new Set(missions.filter(record=>record.completed===true||migrateMedals(record.stars||record.medals).complete===true).map(record=>record.id));
  const completedBases=new Set([...completed].map(missionBase)),campaignAccess=new Set();
  if(campaign){
    const sequence=campaignMissions(campaign),index=Math.max(0,Math.min(sequence.length,Math.trunc(Number(campaign.index)||0)));
    for(const id of sequence.slice(0,index))completedBases.add(id);
    if(campaign.active&&sequence.includes(campaign.mission))campaignAccess.add(campaign.mission);
    for(const run of campaign.history||[])if(run.success===true&&isProgressionMission(run.mission))completedBases.add(missionBase(run.mission));
  }
  return {stars:totalStars(missions),completed,completedBases,campaignAccess};
}
export function missionAccess(id,profile) {
  const base=missionBase(id),index=CAMPAIGN_MISSIONS.indexOf(base);
  const previous=index>0?CAMPAIGN_MISSIONS[index-1]:null;
  const sector=HISTORICAL_UNLOCKS.find(item=>item.missions.includes(base)),stars=sector?.stars||0;
  const unlocked=!isProgressionMission(id)||base==='T01'||base==='M01'||profile.completed.has(id)||profile.completedBases.has(base)||profile.campaignAccess.has(base)||(sector?profile.stars>=stars:previous&&profile.completedBases.has(previous));
  return {unlocked:Boolean(unlocked),previous,stars};
}
export function progressionRewards(profile) {
  return [...CAMPAIGN_MISSIONS.map(id=>({id,kind:'mission',unlocked:missionAccess(id,profile).unlocked})),...HISTORICAL_UNLOCKS.map(item=>({...item,unlocked:profile.stars>=item.stars})),...WEAPONS.map(item=>({...item,kind:'weapon',unlocked:profile.stars>=item.stars})),...EQUIPMENT.map(item=>({...item,kind:'equipment',unlocked:profile.stars>=item.stars})),...CUSTOMIZATION_GEAR.map(item=>({...item,kind:'gear',unlocked:profile.stars>=item.stars}))];
}
export function progressionDiff(before,after) {
  const owned=new Set(progressionRewards(before).filter(item=>item.unlocked).map(item=>`${item.kind}:${item.id}`));
  return {stars:Math.max(0,after.stars-before.stars),unlocks:progressionRewards(after).filter(item=>item.unlocked&&!owned.has(`${item.kind}:${item.id}`))};
}
export function progressionProblem(plan,profile) {
  const mission=plan.map_id||plan.mission||plan.id;
  if(mission&&!missionAccess(mission,profile).unlocked)return {kind:'mission',id:mission,...missionAccess(mission,profile)};
  for(const unit of Object.values(plan.loadout||{})){
    const weapon=WEAPONS.find(item=>item.id===unit?.weapon);
    if(weapon&&profile.stars<weapon.stars)return {...weapon,kind:'weapon'};
    for(const id of [unit?.sidearm,unit?.armor,unit?.helmet,...(Array.isArray(unit?.attachments)?unit.attachments:[])]){
      const gear=CUSTOMIZATION_GEAR.find(item=>item.id===id);
      if(gear&&profile.stars<gear.stars)return {...gear,kind:'gear'};
    }
    for(const item of EQUIPMENT){
      const count=Array.isArray(unit?.equipment)?unit.equipment.filter(id=>id===item.id).length:Number(unit?.equipment?.[item.id])||0;
      if(count>0&&profile.stars<item.stars)return {...item,kind:'equipment'};
    }
  }
  return null;
}
export const campaignMissions=campaign=>campaign?.missions||['M01','M02','M03'];
export function newCampaign(ironman=false) {
  return {id:'campaign',kind:'campaign',active:true,ironman,index:0,mission:'M01',injured:[],lost:[],missions:[...CAMPAIGN_MISSIONS],inventory:{stun:16,breach:8},history:[]};
}
export function availableRoster(campaign) {
  const unavailable=new Set([...(campaign?.injured||[]),...(campaign?.lost||[])]);
  return ROSTER.filter(unit=>!unavailable.has(unit.id));
}
export function finishCampaign(campaign,state) {
  if(!campaign?.active)return campaign;
  const result=state.result||{},success=result.success===true||result.status==='SUCCESS'||result.outcome==='SUCCESS';
  const inventory={...campaign.inventory};
  inventory.stun=Math.max(0,(inventory.stun||0)-Number(result.stuns_used||0));
  inventory.breach=Math.max(0,(inventory.breach||0)-Number(result.breaches_used||0));
  const lost=new Set(campaign.lost||[]),injured=[];
  for(const unit of state.units||[]) {
    const rosterId=unit.roster_id||unit.id;
    if(!ROSTER.some(item=>item.id===rosterId))continue;
    if(Number(unit.hp)<=0&&campaign.ironman)lost.add(rosterId);
    else if(Number(unit.hp)<=30)injured.push(rosterId);
  }
  const index=campaign.index+(success?1:0),active=index<campaignMissions(campaign).length;
  return {...campaign,active,index,mission:active?campaignMissions(campaign)[index]:null,inventory,injured,lost:[...lost],history:[...(campaign.history||[]),{mission:state.mission||campaign.mission,seed:Number(state.seed)||0,score:Number(result.score)||0,losses:Number(result.losses||0),success}]};
}
export function checkCampaignLoadout(campaign,loadout) {
  if(!campaign?.active)return null;
  for(const id of ['stun','breach']) {
    const requested=Object.values(loadout).reduce((sum,unit)=>sum+Number(unit.equipment?.[id]||0),0);
    if(requested>Number(campaign.inventory?.[id]||0))return `${id==='stun'?'스턴':'문 파괴 장약'} 재고가 부족합니다 (${requested} / ${campaign.inventory?.[id]||0}).`;
  }
  return null;
}

/** Legacy plans acquire the campaign's visible identities and chosen gear. */
export function normalizeCampaignPlan(plan,preparation,campaign) {
  const roster=Array.isArray(plan.roster)&&plan.roster.length?plan.roster:preparation.roster;
  const available=new Set(availableRoster(campaign).map(unit=>unit.id)),loadout={};
  if(!roster?.length)throw new Error('캠페인에 투입할 수 있는 대원이 없습니다.');
  const count=value=>typeof value==='number'&&Number.isFinite(value)?Math.max(0,Math.min(2,Math.trunc(value))):0;
  for(const unit of roster) {
    if(!available.has(unit.id))throw new Error('계획에 캠페인에서 사용할 수 없는 대원이 포함되어 있습니다.');
    const base=unit.base_id||unit.id,defaults=preparation.loadout?.[base]||{weapon:'standard',equipment:{stun:1}};
    const choice=plan.loadout?.[base]||plan.loadout?.[unit.id]||{};
    let equipment=Object.prototype.hasOwnProperty.call(choice,'equipment')?choice.equipment:defaults.equipment;
    if(Array.isArray(equipment)){const ids=['stun','smoke','breach',...(equipment.includes('probe_c1')?['probe_c1']:[]),...(equipment.includes('frag')?['frag']:[])];equipment=Object.fromEntries(ids.map(id=>[id,equipment.filter(item=>item===id).length]));}
    if(!equipment||typeof equipment!=='object')equipment={};
    equipment=Object.fromEntries(['stun','smoke','breach','probe_c1','frag'].filter(id=>Object.prototype.hasOwnProperty.call(equipment,id)).map(id=>[id,count(equipment[id])]));
    loadout[base]={weapon:choice.weapon||defaults.weapon,equipment};
    for(const field of ['sidearm','armor','helmet','attachments','appearance','preset']){
      const source=Object.prototype.hasOwnProperty.call(choice,field)?choice:defaults;
      if(Object.prototype.hasOwnProperty.call(source,field))loadout[base][field]=JSON.parse(JSON.stringify(source[field]));
    }
  }
  const problem=checkCampaignLoadout(campaign,loadout);if(problem)throw new Error(problem);
  return {...plan,roster:roster.map(unit=>({...unit})),loadout};
}
