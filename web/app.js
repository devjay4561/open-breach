import { summarizeRun, roomDoctrineReport, doctrineReplaySeek, priorAttemptPresentation } from './debrief.js';
import { BreachStorage, createLeaderboardAdapter } from './storage.js';
import { createQualityMetrics, gradeRoomDoctrine } from './quality-metrics.js';
import { CAMPAIGN_MISSIONS, campaignMissions, MODIFIERS, VARIANTS, EQUIPMENT, WEAPONS, ROSTER, hashSeed, localDate, dailyOperation, missionBase, missionId, migrateMedals, mergeStars, conditionKey, newCampaign, availableRoster, finishCampaign, checkCampaignLoadout, normalizeCampaignPlan, HISTORICAL_UNLOCKS, isProgressionMission, progressionState, missionAccess, progressionRewards, progressionDiff, progressionProblem, SHOOT_HOUSE_MISSIONS, CQB_MISSIONS, isCQBContentMission } from './meta.js';
import { createEditorMission, renderMapEditor, bindMapEditor } from './map-editor.js';
import { t, setLanguage, applyStaticI18n, translateEvent, translateCommandReason, localize, getLanguage } from './i18n.js';
import { CATALOG, ARMORS, HELMETS, ATTACHMENTS, SIDEARMS, PRESETS, normalizeOperatorLoadout, deriveLoadoutStats } from './operator-equipment.js';
const quality = createQualityMetrics({buildId:'quality-2026-10-06',enabled:new URLSearchParams(location.search).get('qa')==='1'});

const $ = id => document.getElementById(id);
const $$ = selector => Array.from(document.querySelectorAll(selector));
const hudNodes=new Map(),hudHTML=new Map();
const hudNode=id=>{if(!hudNodes.has(id))hudNodes.set(id,$(id));return hudNodes.get(id);};
function writeText(id,value){const node=hudNode(id),text=String(value??'');if(node.textContent!==text)node.textContent=text;}
function writeHTML(id,html){if(hudHTML.get(id)===html)return;hudNode(id).innerHTML=html;hudHTML.set(id,html);}
function setHidden(id,hidden){const node=hudNode(id);if(node.hidden!==hidden)node.hidden=hidden;}
function setPressed(button,active){const value=String(active);if(button.getAttribute('aria-pressed')!==value)button.setAttribute('aria-pressed',value);}
const escapeHTML = value => String(value ?? '').replace(/[&<>"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
const formatTime = (value, precise = false) => { const time = Math.max(0, Number(value) || 0); return `${String(Math.floor(time / 60)).padStart(2, '0')}:${String(Math.floor(time % 60)).padStart(2, '0')}${precise ? `.${Math.floor(time * 10) % 10}` : ''}`; };
export function cqbFamily(id){
  if(!isCQBContentMission(id))return '';
  if(id.startsWith('CQB'))return 'puzzle';
  return id.startsWith('SH05_')?'5':String(Number(id.slice(2)));
}
export function shootHouseCompetition(snapshot={},authoredRooms=[]){
  const result=snapshot?.result;
  if(!SHOOT_HOUSE_MISSIONS.includes(snapshot?.mission)||result?.success!==true||typeof snapshot.time!=='number'||!Number.isFinite(snapshot.time)||snapshot.time<=0||snapshot.replay?.complete!==true)return null;
  const rows=roomDoctrineReport(snapshot,authoredRooms,gradeRoomDoctrine).flatMap(room=>room.rows).filter(row=>['good','caution','fail'].includes(row.grade));
  if(!rows.length)return null;
  const quality=rows.reduce((sum,row)=>sum+(row.grade==='good'?1:row.grade==='caution'?.5:0),0)/rows.length;
  if(quality<=0)return null;
  const adjusted_time=snapshot.time/Math.max(quality,.125);if(!Number.isFinite(adjusted_time))return null;
  const condition_key=conditionKey({...snapshot,loadout:snapshot.loadout||{},roster:snapshot.roster||[]});
  return {id:'cqb-competition:'+condition_key,kind:'cqb-competition',mission:snapshot.mission,condition_key,
    elapsed:snapshot.time,quality,known:rows.length,adjusted_time};
}
export function missionRoe(metadata) {return metadata?.roe==='high_intensity'?'high_intensity':'precision';}
export function equipmentPermitted(id,metadata) {return id!=='frag'||missionRoe(metadata)==='high_intensity';}
function runtimeRoe(){return missionRoe({roe:state.roe??catalog.get(state.mission)?.roe});}
function roeBadge(metadata){const roe=missionRoe(metadata);return `<span class="roe-badge" data-roe="${roe}" title="${escapeHTML(t('roe.'+roe+'_note'))}">${t('roe.'+roe)}</span>`;}
export function availableFrags(unit,metadata) {
  if(!unit||!equipmentPermitted('frag',metadata))return 0;
  if(Object.hasOwn(unit,'available_frags'))return Number.isInteger(unit.available_frags)?Math.max(0,unit.available_frags):0;
  const reserved=(unit.commands||[]).filter(command=>command.type==='THROW_FRAG'&&['PENDING','RUNNING','WAITING'].includes(command.state)).length;
  return Math.max(0,(Number(unit.frags)||0)-reserved);
}
export function doorStructureLines(info) {
  if(!info||!Array.isArray(info.walls))return [];
  const materials=['wood','concrete','metal','fabric','glass','masonry','plaster','foliage','steel','drywall','brick','cloth'];
  const walls=info.walls.filter(wall=>wall&&typeof wall==='object'&&typeof wall.id==='string'&&typeof wall.rifle_penetrable==='boolean').slice(0,64);
  if(!walls.length)return [t('door.no_adjacent_walls')];
  return walls.map(wall=>`${t('door.material.'+(materials.includes(wall.material)?wall.material:wall.thin===true?'thin':'unspecified'))} · ${t(wall.rifle_penetrable?'door.rifle_penetrable':'door.rifle_blocked')}`);
}
const icons = {
  settings:'<path d="M10 2h4l.6 3 2.2 1.3 2.9-1 2 3.4-2.3 2V13l2.3 2-2 3.5-2.9-1-2.2 1.3-.6 3h-4l-.6-3-2.2-1.3-2.9 1-2-3.5 2.3-2v-2.3l-2.3-2 2-3.4 2.9 1L9.4 5z"/><circle cx="12" cy="12" r="3"/>',
  focus:'<path d="M8 3H3v5m13-5h5v5M3 16v5h5m13-5v5h-5M12 7v10M7 12h10"/>',
  help:'<circle cx="12" cy="12" r="9"/><path d="M9.5 9a2.5 2.5 0 0 1 5 0c0 2-2.5 2-2.5 4m0 3v.1"/>',
  queue:'<path d="M8 5h13M8 12h13M8 19h13M3 5h.1M3 12h.1M3 19h.1"/>',
  play:'<path d="m7 4 14 8-14 8z" fill="currentColor" stroke="none"/>',
  pause:'<path d="M7 5v14m10-14v14" stroke-width="4"/>',
  move:'<path d="M4 20 20 4M9 4h11v11M3 13v8h8"/>',
  face:'<circle cx="8" cy="16" r="3"/><path d="m6 7 13-3-3 13M10 14l6-6"/>',
  door:'<path d="M3 21h18M6 20V4l11-2v18M17 5h3v15M13 11v2"/>',
  stun:'<circle cx="12" cy="13" r="6"/><path d="M10 7V3h4v4m2-4h3M2 7l2 2m16-1 2-2M3 18l-2 1m18 0 2 2"/>',
  secure:'<path d="M12 3 3 7v6c0 4 9 8 9 8s9-4 9-8V7zM8 12l3 3 5-6"/>',
  wait:'<circle cx="12" cy="12" r="9"/><path d="M12 6v6l4 3"/>',
  reload:'<path d="M20 8a8 8 0 1 0 0 8M20 3v6h-6"/>',
  signal:'<path d="M5 21V3l14 1-4 4 4 4-14-1"/>',
  save:'<path d="M4 3h13l4 4v14H3V3h1M7 3v6h9V3M7 21v-8h10v8"/>',
  restart:'<path d="M5 4v16m15-16L8 12l12 8z"/>'
};
const icon = name => `<svg viewBox="0 0 24 24" aria-hidden="true">${icons[name] || icons.focus}</svg>`;
$$('[data-icon]').forEach(element => element.innerHTML = icon(element.dataset.icon));
const missions = {
  M07:{name:'지하주차장',name_en:'Underground Garage',title:'차량 사이, 연결된 관리실.',title_en:'Parking lanes and linked service rooms.',english:'UNDERGROUND GARAGE',description:'차량과 기둥이 시야를 나누는 주차 구역입니다. 남쪽 두 출입구와 서쪽 서비스문을 통해 위협 8명을 처리하고 민간인 2명을 확보하세요.',description_en:'Vehicles and pillars split the parking lanes. Clear 8 hostiles and secure 2 civilians through two southern entrances or the western service door.',units:'04',rooms:'07',time:'5–12',objectives:['위협 8명 처리 · 민간인 2명 확보','잠긴 정비실에는 관리실을 통한 우회 연결이 있습니다.'],objectives_en:['Neutralize 8 hostiles · secure 2 civilians','A route through security bypasses the locked maintenance door.']},
  M08:{name:'연결 상가',name_en:'Linked Shops',title:'공용 복도와 점포 사이.',title_en:'Common passage and linked shops.',english:'LINKED SHOPS',description:'서점·카페·수리점과 공용 복도가 연결됩니다. 직원 2명을 확보하고 남쪽 집결 구역까지 호송하세요.',description_en:'A bookshop, cafe and workshops connect through a common passage. Secure both staff members and escort them to the southern extraction area.',units:'04',rooms:'07',time:'5–12',objectives:['직원 2명 확보 후 남쪽 구역까지 호송','서비스 출입구와 점포 사이 연결문을 함께 확인하세요.'],objectives_en:['Secure both staff and escort them to the southern zone','Check the service entrances and inter-shop connections.']},
  M09:{name:'중정의 건물',name_en:'Courtyard Block',title:'밝은 중정, 주변의 실내.',title_en:'An open courtyard and indoor wings.',english:'COURTYARD BLOCK',description:'실외 중정과 양쪽 건물이 연결된 임무입니다. 위협 9명을 처리하고 민간인을 확보한 뒤 북쪽 관리실에 도달하세요.',description_en:'An outdoor courtyard links both indoor wings. Clear 9 hostiles, secure the civilian and reach the northern administration room.',units:'04',rooms:'09',time:'5–12',objectives:['위협 처리 · 민간인 확보','북쪽 관리실의 지정 구역에 도달하세요.'],objectives_en:['Clear the hostiles and secure the civilian','Reach the marked area in the northern administration room.']},
  T01:{name:'조작 익히기',name_en:'Basic Training',title:'모든 작전의 시작.',title_en:'Where every operation starts.',english:'INTRODUCTION',description:'반격하지 않는 표적을 대상으로 이동·시야·문 열기 조작을 익히세요. 적이 반격하는 게임은 작은 주택에서 플레이할 수 있습니다.',description_en:'Learn movement, sightlines and door control against targets that never fire back. Hostiles that fight back are waiting in the house mission.',units:'02',rooms:'03',time:'3–5',objectives:['대원을 선택하고 이동 경로를 계획하세요.','반격하지 않는 조작 표적 3개를 처리하세요.'],objectives_en:['Select an operator and plan a move route.','Neutralize the 3 non-retaliating training targets.']},
  M02:{name:'닫힌 기록실',name_en:'Sealed Archive',title:'두 대원. 세 개의 방.',title_en:'Two operators. Three rooms.',english:'ARCHIVE',description:'접수실과 두 기록실이 연결된 소규모 임무입니다. 두 대원으로 위협 3명을 처리하고 직원을 확보하세요.',description_en:'A small operation linking a front desk and two record rooms. Clear 3 hostiles and secure the staff member with two operators.',units:'02',rooms:'03',time:'2–4',objectives:['위협 3명 처리 · 직원 1명 확보','전원 생존과 실행 시간 150초에 도전하세요.'],objectives_en:['Neutralize 3 hostiles · secure 1 staff member','Go for a full-squad survival and a sub-150s run time.']},
  M03:{name:'화물 보관소',name_en:'Cargo Depot',title:'상자 사이, 다른 선택.',title_en:'Between the crates, another choice.',english:'DEPOT',description:'넓은 적재 구역과 닫힌 사무실이 이어집니다. 세 대원으로 위협 4명을 처리하고 직원을 확보하세요.',description_en:'A wide loading bay leads into a closed office. Clear 4 hostiles and secure the staff member with three operators.',units:'03',rooms:'03',time:'3–5',objectives:['위협 4명 처리 · 직원 1명 확보','전원 생존과 실행 시간 180초에 도전하세요.'],objectives_en:['Neutralize 4 hostiles · secure 1 staff member','Go for a full-squad survival and a sub-180s run time.']},
  M01:{name:'작은 주택',name_en:'Quiet House',title:'하나의 팀. 하나의 계획.',title_en:'One team. One plan.',english:'RESIDENTIAL COMPOUND',description:'정적이 흐르는 주택에 네 명의 대원을 투입합니다. 닫힌 문 뒤의 상황은 알 수 없습니다. 구역을 확인하고 민간인을 안전하게 확보하세요.',description_en:'Deploy four operators into a silent house. You cannot know what waits behind a closed door. Clear each room and secure the civilians safely.',units:'04',rooms:'06',time:'3–8',objectives:['구역 내 모든 위협을 처리하세요.','민간인을 확보하고 대원 전원을 보호하세요.'],objectives_en:['Neutralize every hostile in the compound.','Secure the civilians and keep your whole squad alive.']}
};
for(const [id,count] of [['M01',8],['M02',5],['M03',6]]) {
  const base=missions[id];
  missions[id+'H']={...base,name:base.name+' · 도전',name_en:base.name_en+' · Challenge',english:base.english+' / CHALLENGE',description:`${Number(base.units)}명의 대원으로 위협 ${count}명과 민간인 목표에 도전합니다. 일반과 다른 적 배치·순찰, 빠른 대응과 강화된 공격을 적용합니다.`,description_en:`Take on ${count} hostiles and the civilian objective with ${Number(base.units)} operators. Enemy placement, patrols, reaction speed and damage are all increased over normal.`,objectives:[`위협 ${count}명 처리 · 모든 민간인 확보`,'도전 기록은 일반 난이도와 별도로 저장됩니다.'],objectives_en:[`Neutralize ${count} hostiles · secure every civilian`,'Challenge records are tracked separately from normal difficulty.']};
}
const parTimes={T01:120,M01:240,M02:150,M03:180,M01H:360,M02H:240,M03H:270};
const STAR_LABELS_EN = {no_hits:'No hits',no_kills:'No kills',no_reload:'No reload',no_stun:'No stun used',single_plan:'Single plan',small_team:'Small team',no_civilian_damage:'No civilian damage',capture_surrendered:'Capture a surrendered hostile',no_unit_damage:'No operator injuries',roe_time:'Finish within 240s'};
const commandNames_ko ={MOVE:'이동',FACE:'주시 방향',WAIT:'대기',OPEN_DOOR:'조용히 열기',OPEN_AND_FLASH:'문 열고 섬광탄 던지기',KICK_DOOR:'문 차기',PEEK_DOOR:'들여다보기',PEEK_CAMERA:'정찰 카메라',SWITCH_WEAPON:'무기 전환',RELOAD:'재장전',THROW_STUN:'섬광탄 투척',THROW_SMOKE:'연막',BREACH_DOOR:'문 파괴 장약',WAIT_FOR_SIGNAL:'신호 대기',SECURE_CIVILIAN:'민간인 확보',ESCORT_CIVILIAN:'민간인 호송',ARREST:'체포',CANCEL_PENDING:'미실행 취소',HOLD_AT_DOOR:'문 앞 정지'};
const commandNames_en = {MOVE:'Move',FACE:'Face',WAIT:'Wait',OPEN_DOOR:'Quiet open',OPEN_AND_FLASH:'Open door and throw flashbang',KICK_DOOR:'Kick door',PEEK_DOOR:'Peek',PEEK_CAMERA:'Scout camera',SWITCH_WEAPON:'Switch weapon',RELOAD:'Reload',THROW_STUN:'Throw flashbang',THROW_SMOKE:'Smoke',BREACH_DOOR:'Breach charge',WAIT_FOR_SIGNAL:'Wait for signal',SECURE_CIVILIAN:'Secure civilian',ESCORT_CIVILIAN:'Escort civilian',ARREST:'Arrest',CANCEL_PENDING:'Cancel pending',HOLD_AT_DOOR:'Hold at door'};
const commandStates_ko = {PENDING:'대기열',RUNNING:'진행 중',WAITING:'조건 대기',SUCCEEDED:'완료',FAILED:'실패',CANCELLED:'취소'};
const commandStates_en = {PENDING:'Queued',RUNNING:'Running',WAITING:'Waiting',SUCCEEDED:'Done',FAILED:'Failed',CANCELLED:'Cancelled'};
const commandNamesOf = () => ({...(getLanguage()==='en'?commandNames_en:commandNames_ko),SHOTGUN_BREACH:t('command.shotgun_breach'),THROW_FRAG:t('command.THROW_FRAG')});
const commandStatesOf = () => getLanguage()==='en'?commandStates_en:commandStates_ko;
const toolHints = {pan:['지도를 왼쪽 드래그해 화면을 옮기세요. WASD 이동 · 휠 확대/축소 · Home 초기화','DRAG'],select:['대원을 선택한 후, 우클릭으로 이동 경로를 지정하세요.','RMB'],move:['지도에서 이동할 위치를 클릭하세요. Shift로 경유점을 추가합니다.','CLICK'],face:['바라볼 방향을 클릭하세요. 다음 이동에서는 이동 방향으로 돌아봅니다.','F'],face_lock:['바라볼 방향을 클릭하세요. 이동 중에도 이 방향을 유지합니다.','F'],door:['처리할 문을 클릭하세요. 조용히 열기·차기·들여다보기 중 선택한 방식을 적용합니다.','CLICK'],stun:['투척할 위치를 클릭하세요. 벽으로 가려진 지점에는 던질 수 없습니다.','CLICK'],smoke:['연막을 투척할 위치를 클릭하세요. 4초 동안 양쪽의 시야를 차단합니다.','CLICK'],breach:['문 파괴 장약을 사용할 문을 클릭하세요. 큰 소리가 발생합니다.','CLICK'],arrest:['투항한 적을 클릭하세요. 감시가 끊기면 5초 후 다시 무장합니다.','CLICK'],escort:['호송할 민간인을 클릭하세요. 확보 후 선택 대원을 따라갑니다.','CLICK'],secure:['확보할 민간인을 클릭하세요. 대원이 접근해 안전을 확보합니다.','CLICK']};
const toolHints_en = {pan:['Drag the map to pan. WASD to move, wheel to zoom, Home to reset.','DRAG'],select:['Select an operator, then right-click to set a move route.','RMB'],move:['Click a spot on the map to move to. Hold Shift to add waypoints.','CLICK'],face:['Click a direction to watch. The next move restores movement facing.','F'],face_lock:['Click a direction to keep watching while moving.','F'],door:['Click the door to act on. Applies whichever mode — quiet open, kick, or peek — is selected.','CLICK'],stun:['Click where to throw. You cannot throw to a spot blocked by a wall.','CLICK'],smoke:['Click where to throw smoke. Blocks sightlines both ways for 4 seconds.','CLICK'],breach:['Click the door to breach. This makes a loud noise.','CLICK'],arrest:['Click a surrendered hostile. They rearm after 5 seconds unwatched.','CLICK'],escort:['Click the civilian to escort. They follow the selected operator once secured.','CLICK'],secure:['Click the civilian to secure. An operator moves in to secure them.','CLICK']};
toolHints.camera=['카메라로 정찰할 문을 클릭하세요. 마지막 관측 정보는 기억으로 표시됩니다.','CLICK'];
toolHints.flash_target=['효과 범위를 확인하고 섬광탄이 떨어질 지점을 클릭하세요.','CLICK'];
toolHints.door=['문을 클릭해 선택한 열기·차기·엿보기·섬광 진입 행동을 예약하세요.','CLICK'];
toolHints_en.camera=['Click a door to scout with the camera. Last observations are remembered information.','CLICK'];
toolHints_en.flash_target=['Check the effect radius and click the flashbang landing point.','CLICK'];
toolHints_en.door=['Click a door to queue quiet open, kick, peek or open-and-flash.','CLICK'];
const tutorials = [
  {title:'대원을 선택하세요',description:'지도 위 대원이나 아래 대원 카드를 선택하세요. 숫자 1·2로도 선택할 수 있습니다.',key:'1 / 2'},
  {title:'먼저, 이동을 계획하세요',description:'지도를 우클릭하면 이동 경로가 만들어집니다. Shift + 우클릭으로 다음 경유점을 추가하세요.',key:'우클릭'},
  {title:'시간은 당신의 편입니다',description:'작전 실행이나 Space를 눌러 계획을 실행하세요. 다시 누르면 즉시 정지하고 계획을 수정할 수 있습니다.',key:'SPACE'},
  {title:'닫힌 문 앞에서는 천천히',description:'다음 방을 우클릭하면 경로에 있는 문을 순서대로 열고 이동합니다. 문만 미리 열고 싶으면 문을 클릭하세요.',key:'문 열기'},
  {title:'주시 방향을 지정하세요',description:'주시 도구 또는 F를 누른 뒤 확인할 방향을 클릭하세요. 시야 안에 들어온 위협에 자동으로 대응합니다.',key:'F + 클릭'},
  {title:'같은 신호에 움직이세요',description:'대원들에게 같은 신호 대기를 추가하세요. 모두 준비되면 우측 A·B·C 버튼으로 동시 실행할 수 있습니다.',key:'SIGNAL'}
];
const tutorials_en = [
  {title:'Select an operator',description:'Select an operator on the map or a roster card below. You can also press 1 or 2.',key:'1 / 2'},
  {title:'Plan a move first',description:'Right-click the map to lay a move route. Shift + right-click adds another waypoint.',key:'RMB'},
  {title:'Time is on your side',description:'Press Run Operation or Space to execute the plan. Press again to pause instantly and revise it.',key:'SPACE'},
  {title:'Take it slow at closed doors',description:'Right-clicking the next room opens every door on the route in order as you move through. Click a door alone to just queue the open.',key:'Open door'},
  {title:'Set a facing direction',description:'Pick the Face tool or press F, then click the direction to watch. Threats that enter that sightline are reacted to automatically.',key:'F + click'},
  {title:'Move together on a signal',description:'Queue the same wait-for-signal on multiple operators. Once everyone is ready, fire the A/B/C buttons to act in sync.',key:'SIGNAL'}
];
const store = new BreachStorage();
const leaderboard=createLeaderboardAdapter(store);
let selectedDifficulty='normal';
let state = {}, selectedMission = 'T01', engineReady = false, engineBooted = false;
let settingsVersion = 0, storeAvailable = false, pendingPlanPurpose = 'save', pendingImport = 'replay';
let resultKey = '', resultLanguage = '', savedReplayKey = '', settingsChain = Promise.resolve(), loadingTimeout;
let lastUnitHTML = '', lastQueueHTML = '', lastLogHTML = '', lastReplayFollow = '';
let roomDrillDraft=null, roomDrillPreview={}, roomDrillPending=0, roomDrillSequence=0, lastRoomDrillHTML='', lastDrillHTML='', drillTimelineGroup='', drillDelayDrag=null;
let formationDraft=null, formationPreview={}, formationPending=false, formationSequence=0, lastFormationHTML='';
const FORMATION_KINDS=['AUTO','SERPENTINE','ROLLING_T','T_JUNCTION'];
const DRILL_METHODS=['OPEN_DOOR','KICK_DOOR','OPEN_AND_FLASH','SHOTGUN_BREACH','BREACH_DOOR'];
const DRILL_STAGES=['stack','ready','door','entry'];
// These projections only consume public own-unit plans. Geometry and resource
// validation stay authoritative in the simulation; no contacts are consulted.
export function selectedOwnUnitIds(snapshot={}){
  const units=Array.isArray(snapshot?.units)?snapshot.units:[];
  const alive=new Set(units.filter(unit=>unit&&typeof unit.id==='string'&&unit.id.length>0&&Number.isFinite(Number(unit.hp))&&Number(unit.hp)>0).map(unit=>unit.id));
  const ids=Array.isArray(snapshot?.selected_units)?snapshot.selected_units:[snapshot?.selected];
  return [...new Set(ids)].filter(id=>alive.has(id)).slice(0,4);
}
export function reorderDrillIds(ids,id,direction){
  const next=[...ids],index=next.indexOf(id),target=index+Math.sign(direction);
  if(index>=0&&target>=0&&target<next.length)[next[index],next[target]]=[next[target],next[index]];
  return next;
}
export function clampDrillDelay(value){return Math.min(3600,Math.max(0,Math.round(Number(value)||0)));}
export function roomDrillTimeline(snapshot={}){
  const groups=new Map();
  for(const unit of Array.isArray(snapshot?.units)?snapshot.units:[])for(const [index,command] of (Array.isArray(unit?.commands)?unit.commands:[]).entries()){
    const drill=command?.args?.drill;if(!drill||typeof drill.sync_id!=='string'||!drill.sync_id||typeof unit.id!=='string')continue;
    if(!groups.has(drill.sync_id))groups.set(drill.sync_id,{id:drill.sync_id,door_id:drill.door_id,rows:new Map(),ready:[]});
    const group=groups.get(drill.sync_id);
    if(!group.rows.has(unit.id))group.rows.set(unit.id,{unit,order:Number(drill.order)||1,commands:[]});
    const row=group.rows.get(unit.id);row.commands.push({command,index});
    // A casualty can replace entry nodes without rewriting completed stack
    // history. Display the latest remaining plan's rank, preserving history.
    if(['PENDING','RUNNING','WAITING','FAILED'].includes(command.state)&&Number.isInteger(Number(drill.order))&&Number(drill.order)>=1&&Number(drill.order)<=4)row.order=Number(drill.order);
    if(command.type==='WAIT_FOR_SIGNAL'&&drill.stage==='ready'&&command.args.sync_id===`${drill.sync_id}:ready`)group.ready.push(command);
  }
  return [...groups.values()].map(group=>({...group,rows:[...group.rows.values()].map(row=>{if(Number.isFinite(Number(row.unit.hp))&&Number(row.unit.hp)<=0)row.order=null;return row;}).sort((a,b)=>(a.order??5)-(b.order??5)),
    sync_id:group.ready[0]?.args?.sync_id||`${group.id}:ready`,delay_ticks:clampDrillDelay(group.ready[0]?.args?.delay_ticks),
    editable:group.ready.length>0&&group.ready.every(command=>command.state==='PENDING')}));
}
// Room presentation only uses authored room IDs with explicit observation.
// Return owned, minimal records so search timers and hidden occupants never
// become web state or mutate the authoritative snapshot through an alias.
export function observedRoomStates(snapshot={},authoredRooms=[]){
  const result=Object.create(null),states=snapshot?.room_states;
  if(!states||typeof states!=='object'||Array.isArray(states)||!Array.isArray(authoredRooms))return result;
  for(const room of authoredRooms.slice(0,64)){
    const id=room?.id;if(typeof id!=='string'||!id||!Object.hasOwn(states,id))continue;
    const record=states[id];
    if(record?.observed===true&&['UNKNOWN','CONTACT','DOMINATED','CLEAR','MARKED'].includes(record.state))result[id]={id,state:record.state,observed:true};
  }
  return result;
}
export function formationDraftForTarget(snapshot={},target,order){
  const selected=selectedOwnUnitIds(snapshot);
  if(snapshot.mode!=='PLANNING'||snapshot.tool!=='formation'||!Array.isArray(target)||target.length!==2||!target.every(value=>typeof value==='number'&&Number.isFinite(value))||!Array.isArray(order)||order.length<2||order.length>4||new Set(order).size!==order.length||order.some(id=>!selected.includes(id))||selected.length!==order.length)return null;
  return {mission:snapshot.mission,target:[...target],order:[...order],kind:'AUTO',signal:'AUTO',delay_ticks:0};
}
export function formationInputKey(snapshot={},draft={}){
  const own=new Map((Array.isArray(snapshot.units)?snapshot.units:[]).map(unit=>[unit.id,unit]));
  return JSON.stringify((draft.order||[]).map(id=>{const unit=own.get(id);return [id,unit?.hp,unit?.x,unit?.z,unit?.position,unit?.stance,(unit?.commands||[]).map(command=>[command.type,command.state,command.args])];}));
}
export function formationPreviewCurrent(draft,message){return !!draft&&typeof message?.preview_id==='string'&&message.preview_id===draft.preview_id;}
export function formationSignalPolicy(preview={},mission={},snapshot={}){
  return (preview.noise_discipline??mission.noise_discipline??snapshot.noise_discipline)==='hand_signals'?'hand_signals':'verbal';
}
let lastUnitHP = new Map(), hitFlash = new Map(), logSeen = new Map();
let replayEntered = false;
const commandIcon = {MOVE:'move',FACE:'face',WAIT:'wait',OPEN_DOOR:'door',OPEN_AND_FLASH:'stun',KICK_DOOR:'door',PEEK_DOOR:'door',PEEK_CAMERA:'face',SWITCH_WEAPON:'reload',BREACH_DOOR:'door',SHOTGUN_BREACH:'door',RELOAD:'reload',THROW_STUN:'stun',THROW_SMOKE:'stun',THROW_FRAG:'stun',WAIT_FOR_SIGNAL:'signal',SECURE_CIVILIAN:'secure',ESCORT_CIVILIAN:'secure',ARREST:'secure'};
let tutorialStep = 0, tutorialClosed = false, seenEvents = new Set(), lastMission = '';
let progress = new Map(), missionProgress = new Map(), planPendingLoad = null;
let audioContext, audioBuffers = new Map(), audioUnlocked = false, ambientSource, effectGain, musicGain, combatBus;
let currentModal = '', settingsDirty = false;
let catalog = new Map(), selectedVariant = 'standard', seedMode = 'fixed', customSeed = 1, randomSeed = 1;
let operationCollection = 'base';
// RB: 3-stage menu flow state (title / select / briefing / campaign). Purely
// client-side navigation inside the single #menu screen (engine mode stays
// 'MENU' throughout); see showMenuScreen().
const MENU_SCREENS = ['title','select','briefing','campaign'];
let menuScreen = 'title', titleNavIndex = 0;
let selectedModifiers = new Set(), squadIds = [], loadoutChoices = {}, campaign = null, context = null, editorController = null;
let customizationId='', profileSaveChain=Promise.resolve();
const profileSaveStatus=new Map(),profileSaveVersions=new Map(),comparisonLoadouts=new Map(),appearanceOpen=new Map();
const equipmentText=(ko,en)=>getLanguage()==='en'?en:ko;
function rosterName(unit){return unit?.appearance?.name||(unit?.roster_id&&unit?.name)||loadoutChoices[unit?.roster_id||unit?.id]?.appearance?.name||localize(ROSTER.find(item=>item.id===(unit?.roster_id||unit?.id))||unit||{},'name')||unit?.name||unit?.id||'';}
let campaignResultKey = '', preparedForBase = '';
let unlockProfile=progressionState([]), rewardedResultKey='', resultRewards=null, progressSaveFailed=false;
let editorTemplates = new Map(), catalogRevision=0, lastMissionGridKey='';
const missionThumbCache=new Map();
// RD1: default key bindings (plan §9 조작 / bridge contract `bindings`). `face`
// is the one action the web itself dispatches locally (tool-mode toggle); the
// rest are raw keys the Godot engine reads directly off the canvas, so web's
// job for those is display (hotbar badges) + forwarding via `settings`.
const DEFAULT_BINDINGS = {face:'KeyF',reload:'KeyR',move:'KeyQ',door:'KeyE',equipment:'KeyG',secure:'KeyC',wait:'KeyT',signal:'KeyZ'};
// M3: shared binding whitelist (web+Godot). KeyA-KeyZ except the WASD camera
// keys, Digit0 and Digit5-9 (1-4 are reserved for quick-select), and the
// punctuation codes Godot can map. Anything else (arrows, Home/Delete/
// Enter/F-keys/Shift/...) is rejected by the capture UI.
const VALID_BINDING_CODES = new Set([
  ...'BCEFGHIJKLMNOPQRTUVXYZ'.split('').map(letter=>`Key${letter}`),
  'Digit0','Digit5','Digit6','Digit7','Digit8','Digit9',
  'Comma','Period','Semicolon','Quote','BracketLeft','BracketRight','Minus','Equal','Backquote',
]);
const BINDING_LABELS = {move:'이동',face:'주시',door:'문 처리',equipment:'장비',secure:'확보',wait:'대기',reload:'재장전',signal:'신호 대기'};
function codeLabel(code) {
  if (!code) return '—';
  if (/^Key[A-Z]$/.test(code)) return code.slice(3);
  if (/^Digit[0-9]$/.test(code)) return code.slice(5);
  return {Space:'SPACE',Escape:'ESC',ShiftLeft:'SHIFT',ShiftRight:'SHIFT',ControlLeft:'CTRL',ControlRight:'CTRL',Tab:'TAB'}[code] || code.replace(/^Key|^Digit/,'');
}
const DEFAULT_SETTINGS = {volume:.65,music_volume:.18,muted:false,ui_scale:1,ui_scale_auto:true,line_width:1,fov:true,enemy_alerts:true,auto_pause_man_down:false,reduced_flash:matchMedia('(prefers-reduced-motion: reduce)').matches,screen_shake:true,palette:'default',language:'ko',bindings:{...DEFAULT_BINDINGS}};
// RD2 (plan 2-4): on ultra-tall/ultrawide displays the fixed 13px base font
// and compact HUD chrome read small, so --ui-scale steps up automatically
// with viewport height (1.25 at >=1300px, 1.5 at >=1800px) unless the player
// has manually picked a scale in Settings (ui_scale_auto flips off then).
function autoUiScale(){const h=window.innerHeight||0;return h>=1800?1.5:h>=1300?1.25:1;}
let settings = {...DEFAULT_SETTINGS,bindings:{...DEFAULT_BINDINGS}};
let settingsTab = 'gameplay', bindingCapture = null;
const tabId = globalThis.crypto?.randomUUID?.() || `${Date.now()}-${Math.random().toString(16).slice(2)}`;
const settingsChannel = typeof BroadcastChannel !== 'undefined' ? new BroadcastChannel('breach-settings') : null;
window.BreachBridge = window.BreachBridge || {};
window.BreachBridge.qualityEnabled = quality.enabled;
window.BreachUI = {receive(payload) {try{receive(typeof payload === 'string' ? JSON.parse(payload) : payload);}catch(error){quality.recordError(error,'ui-message');console.error('Breach UI message:',error);toast('상태 데이터를 읽지 못했습니다. 작전을 일시정지하고 다시 시도하세요.','error');}}};

const LOADING_ACTIONS = new Set(['start','preview','retry','retry_plan','load_plan','import_replay','replay','custom_mission','import_mission','lab']);
let activeTransition = null, transitionSequence = 0;
const afterLoadingPaint = () => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(() => setTimeout(resolve,0))));
function beginTransition(id, action, stage = 'engine') {
  const previous = activeTransition;
  if(previous)clearTimeout(previous.timeout);
  activeTransition = {id,stage};
  const replay = ['import_replay','replay'].includes(action), plan = ['load_plan','retry_plan'].includes(action);
  $('transition-title').textContent=t(replay?'transition.replay':plan?'transition.plan':'transition.mission');
  $('transition-message').textContent=t(stage==='file'?'transition.file':'transition.preparing');
  $('transition-reload').hidden=true;$('transition-reload').textContent=t('loading.retry');
  const overlay=$('transition-loading');if(!overlay.open)overlay.showModal();
  activeTransition.timeout=setTimeout(()=>{if(activeTransition?.id!==id)return;$('transition-message').textContent=t('transition.slow');$('transition-reload').hidden=false;},45000);
  return id;
}
function finishTransition(id) {
  if(activeTransition?.id!==id)return;
  clearTimeout(activeTransition.timeout);activeTransition=null;$('transition-loading').close();
  if(!$('modal').open&&['PLANNING','EXECUTING','REPLAY'].includes(state.mode))$('canvas').focus({preventScroll:true});
}
function send(data, focus = true, loadingPrepared = false) {
  if (!engineReady || typeof window.BreachBridge.send !== 'function') {toast('작전 환경을 준비하고 있습니다. 잠시만 기다려 주세요.','warning');return false;}
  if(LOADING_ACTIONS.has(data.action)&&!loadingPrepared){
    if(activeTransition&&activeTransition.stage!=='file')return false;
    const id=activeTransition?.id||`web-${++transitionSequence}`;
    beginTransition(id,data.action);
    // Paint before JSON serialization and the bridge's synchronous parse too.
    afterLoadingPaint().then(()=>{if(activeTransition?.id===id)send({...data,_loading_id:id},focus,true);});
    return true;
  }
  try { const token=quality.trackIntent(data);if(token)data={...data,_quality_token:token};window.BreachBridge.send(JSON.stringify(data)); if (focus && !$('modal').open&&!activeTransition) $('canvas').focus({preventScroll:true}); return true; }
  catch(error) {if(data._loading_id)finishTransition(data._loading_id);console.error(error);toast('명령을 전달하지 못했습니다. 다시 시도하세요.','error');return false;}
}
// 1-1: tell the engine how much of the viewport the 3-column HUD reserves so
// it can fit the map camera into the remaining rectangle. Additive bridge
// message; the current engine build may ignore it (falls back to its own
// reserved_height), so this must never block rendering if unsupported.
let lastSafeArea='';
let safeAreaFrame=null;
const safeAreaNodes={nav:document.querySelector('.title-nav'),wordmark:document.querySelector('.title-wordmark'),select:document.querySelector('.select-body'),briefing:document.querySelector('.briefing-map'),top:document.querySelector('.hud-topbar'),left:document.querySelector('.hud-left'),right:document.querySelector('.hud-right'),bottom:document.querySelector('.hud-hotbar')};
function scheduleSafeArea(){if(safeAreaFrame===null)safeAreaFrame=requestAnimationFrame(()=>{safeAreaFrame=null;sendSafeArea();if(['PLANNING','EXECUTING'].includes(state.mode)&&!$('face-options').hidden){lastToolKey='';renderTool();}});}
// RB2: menu-screen diorama safe areas (plan item 1). Each of the three menu
// sub-screens reserves a different rectangle for the live diorama; derived
// straight from the on-screen rects of the panels that must NOT be covered,
// so it tracks any future layout tweak without a second source of truth.
// The old engine build ignores set_safe_area entirely, so style.css also
// gives every overlapping panel its own opaque/scrim backdrop — this must
// never be the only thing keeping panel text readable over the 3D view.
function menuSafeAreaRect(){
  if(menuScreen==='title'){
    // .title-brand is a row-flex child of the column-flex .title-screen, so
    // (unlike .title-nav, which has an explicit width) it stretches to the
    // full screen width as a flex item even though its visible content
    // (icon + wordmark) is much narrower — measure the wordmark itself,
    // which sizes to its text content, not the stretched container.
    const {nav,wordmark}=safeAreaNodes;
    const navRect=nav?.getBoundingClientRect(),wordmarkRect=wordmark?.getBoundingClientRect();
    const colRight=Math.max(navRect?.right||0,wordmarkRect?.right||0);
    if(!colRight)return null;
    return {left:Math.round(colRight+32),top:0,right:0,bottom:0};
  }
  if(menuScreen==='select'){
    const body=safeAreaNodes.select;if(!body)return null;
    const rect=body.getBoundingClientRect();
    return {left:Math.round(Math.max(0,rect.left)),top:Math.round(Math.max(0,rect.top)),right:Math.round(Math.max(0,window.innerWidth-rect.right)),bottom:Math.round(Math.max(0,window.innerHeight-rect.bottom))};
  }
  if(menuScreen==='briefing'){
    const map=safeAreaNodes.briefing;if(!map)return null;
    const rect=map.getBoundingClientRect();
    return {left:Math.round(Math.max(0,rect.left)),top:Math.round(Math.max(0,rect.top)),right:Math.round(Math.max(0,window.innerWidth-rect.right)),bottom:Math.round(Math.max(0,window.innerHeight-rect.bottom))};
  }
  return null;
}
function sendSafeArea(){
  if(state.mode==='MENU'){
    if($('menu').hidden)return;
    const area=menuSafeAreaRect();if(!area)return;
    if(menuScreen==='briefing')for(const [edge,value] of Object.entries(area))$('canvas').style.setProperty(`--briefing-map-${edge}`,`${value}px`);
    const key=JSON.stringify(area);if(key===lastSafeArea)return;lastSafeArea=key;
    send({action:'set_safe_area',data:area},false);return;
  }
  if(!['PLANNING','EXECUTING'].includes(state.mode)||$('hud').hidden)return;
  const {top:topbar,left:leftCol,right:rightCol,bottom:hotbar}=safeAreaNodes;
  const deckHeight=Math.round(hotbar?.getBoundingClientRect().height||72);
  $('hud').style.setProperty('--drill-deck-height',`${deckHeight}px`);
  // Use the actual on-screen rect (not just CSS width) so a collapsed/off-
  // canvas right column (translateX at <1400px) correctly reports 0 inset.
  const rightRect=rightCol?.getBoundingClientRect();
  const area={
    left:Math.round(leftCol?.getBoundingClientRect().width||0),
    top:Math.round(topbar?.getBoundingClientRect().height||0),
    right:rightRect?Math.max(0,Math.round(window.innerWidth-Math.max(rightRect.left,0))):0,
    bottom:deckHeight
  };
  const key=JSON.stringify(area);if(key===lastSafeArea)return;lastSafeArea=key;
  send({action:'set_safe_area',data:area},false);
}
// RD1: `ui_focus` (bridge contract) — true whenever a DOM menu/overlay owns
// input (title/select/briefing, any dialog, pause panel, debrief/result,
// replay controls), false in the live HUD so Godot regains gamepad input.
// Centralised here (instead of the scattered per-transition sends this
// started as) so every caller agrees on one source of truth and we never
// send a redundant duplicate.
let lastUiFocus = null;
function domOverlayOpen(){return state.mode==='MENU'||state.mode==='RESULT'||state.mode==='REPLAY'||$('modal')?.open||!$('pause-panel')?.hidden||!$('room-drill-panel')?.hidden||!$('formation-panel')?.hidden;}
function syncUiFocus(){
  if(!engineReady)return;
  const active=domOverlayOpen();
  if(active===lastUiFocus)return;
  lastUiFocus=active;
  send({action:'ui_focus',data:{active},active},false);
}
function toast(message, kind = 'info') {
  const node = document.createElement('div'); node.className=`toast ${['error','warning'].includes(kind)?kind:''}`;node.textContent=String(message);$('toasts').append(node);
  while($('toasts').children.length>4)$('toasts').firstChild.remove();setTimeout(()=>node.remove(),kind==='error'?7000:4200);
}
function receive(message) {
  if (!message || typeof message !== 'object') return;
  if(message.type==='loading'){if(message.active){if(!activeTransition||activeTransition.id===message.id)beginTransition(message.id,message.action);}else finishTransition(message.id);return;}
  if (message.type === 'ready') {
    quality.noteState(message);
    ingestCatalog(message.catalog);ingestCatalog(message.briefings);engineReady=true;$('start-mission').disabled=false;send({action:'settings',settings},false);updateBrief();showLoaded();lastSafeArea='';scheduleSafeArea();setTimeout(scheduleSafeArea,220);return;
  }
  if (message.type === 'fx_reset') {clearTransientFx();return;}
  if (message.type === 'fx_clock') {flushHitFeedback(message.time,message.paused);return;}
  if (message.type === 'state') {
    const live=mode=>mode==='EXECUTING'||mode==='PLANNING';
    if(state.mission!==message.mission||(['RESULT','MENU'].includes(message.mode)&&state.mode!==message.mode))clearTransientFx(message.mode==='RESULT'&&state.mission===message.mission);
    else if(state.mode!==message.mode&&!(live(state.mode)&&live(message.mode)))cancelPendingHitFeedback();
    state=message;renderState();flushHitFeedback(feedbackTime(),feedbackPaused());quality.noteState(message);return;
  }
  if (message.type === 'toast') {toast(message.i18n_key?t(message.i18n_key):message.message,message.kind);return;}
  if (message.type === 'formation_target') {openFormation(message.target,message.order);return;}
  if (message.type === 'formation_preview') {
    if(!formationPreviewCurrent(formationDraft,message))return;
    formationPending=false;formationPreview=message.data||{};
    if(formationPreview.ok&&Array.isArray(formationPreview.order_ids))formationDraft.order=[...formationPreview.order_ids];
    formationDraft.input_key=formationInputKey(state,formationDraft);renderFormation();return;
  }
  if (message.type === 'room_drill_preview') {
    if(message.preview_id&&message.preview_id!==roomDrillDraft?.preview_id)return;
    roomDrillPending=Math.max(0,roomDrillPending-1);
    if(roomDrillDraft&&roomDrillPending===0){roomDrillPreview=message.data||{};if(roomDrillPreview.ok&&Array.isArray(roomDrillPreview.order_ids)){roomDrillDraft.order=[...roomDrillPreview.order_ids];roomDrillDraft.input_key=roomDrillInputKey();}renderRoomDrill();}
    return;
  }
  if (message.type === 'catalog_update') {ingestCatalog(message.catalog);if(state.mode==='MENU')updateBrief();return;}
  if (message.type === 'editor_catalog') {editorTemplates=new Map(Object.entries(message.catalog||{}));if(currentModal==='editor')renderEditorTemplatePicker();return;}
  if (message.type === 'context') {openContext(message);return;}
  if (message.type === 'context_close') {closeContext(false);return;}
  if (message.type === 'waypoint_select') {state.selected_command=message.index;state.selected=message.unit_id||state.selected;lastQueueHTML='';renderCommands();return;}
  if (message.type === 'sound') {if(['RESULT','MENU'].includes(state.mode)&&['hit','armour_block'].includes(message.name))return;if(message.react_at>0)queueHitFeedback(message,()=>playSound(message.name,message));else playSound(message.name,message);return;}
  if (message.type === 'fx') {handleFx(message);return;}
  if (message.type === 'command_failed') {if(message.unit_id)send({action:'select',id:message.unit_id},false);$('queue-panel').hidden=false;$('queue-toggle').setAttribute('aria-expanded','true');toast(t('command.failed_edit_hint'),'warning');return;}
  if (message.type === 'menu_request') {openModal('pause');return;}
  if (message.type === 'replay_data') {handleReplayData(message).catch(error=>storageError(error));return;}
  if (message.type === 'plan_data') {handlePlanData(message.data).catch(error=>storageError(error));}
}
function showLoaded() {clearTimeout(loadingTimeout);$('load-progress').style.width='100%';$('load-percent').textContent='100%';$('load-status').textContent='READY';$('loading').classList.add('loading-out');$('menu').hidden=false;setTimeout(()=>$('loading').hidden=true,450);}
function fatalError(title, message) {$('loading').hidden=false;$('loading').classList.remove('loading-out');$('loading').classList.add('error');$('loading-title').textContent=title;$('loading-message').textContent=message;$('load-retry').hidden=false;clearTimeout(loadingTimeout);}
function storageError(error) {console.warn(error);const keys={COMPETITION_INVALID:'competition.invalid',COMPETITION_SAVE_FAILED:'competition.save_failed',LEADERBOARD_UNAVAILABLE:'competition.unavailable'};toast(keys[error?.code]?t(keys[error.code]):error?.message || '저장에 실패했습니다. 파일 내보내기로 기록을 보관하세요.','warning');$('storage-status').textContent='SESSION MODE / 저장 실패';$('storage-status').classList.add('storage-warning');}

async function initStorage() {
  try {if(quality.enabled&&new URLSearchParams(location.search).get('qa_storage')==='unavailable')throw new Error('QA: local storage unavailable');await store.open();storeAvailable=true;const [saved,records,profiles]=await Promise.all([store.get('settings','current'),store.all('progress'),store.operatorProfiles()]);
    loadoutChoices=profiles||{};
    if(saved?.data){settings=validateSettings(saved.data);settingsVersion=Number(saved.version)||0;}
    progress=new Map(records.map(record=>[record.id,{...record,stars:migrateMedals(record.stars||record.medals),medals:migrateMedals(record.stars||record.medals)}]));missionProgress=new Map([...progress].filter(([id,record])=>record.kind!=='run'&&record.kind!=='campaign'&&record.kind!=='cqb-competition'&&!String(id).startsWith('run:')&&!String(id).startsWith('cqb-competition:')&&id!=='campaign'));campaign=progress.get('campaign')||null;refreshProgression();applySettings();updateBrief();const migrations=await Promise.allSettled(records.filter(record=>Array.isArray(record.medals)).map(record=>store.put('progress',progress.get(record.id))));for(const migration of migrations)if(migration.status==='rejected')storageError(migration.reason);
  } catch(error){storeAvailable=false;$('storage-status').textContent='SESSION MODE / 저장 불가';$('storage-status').classList.add('storage-warning');toast('브라우저 저장소를 사용할 수 없습니다. 게임은 계속할 수 있으며 기록은 파일로 내보내세요.','warning');}
}
// M3: validates a whole bindings object against the shared whitelist. Any
// unknown action, invalid code, or internal duplicate rejects the bindings
// as a whole (returns null) rather than silently falling an individual
// action back to its default, which could otherwise collide with another
// custom binding (e.g. importing {face:'KeyR'} when reload is already R).
function validateBindings(input) {
  if(!input||typeof input!=='object')return null;
  const result={},used=new Set();
  for(const action of Object.keys(DEFAULT_BINDINGS)){
    const code=input[action];
    if(typeof code!=='string'||!VALID_BINDING_CODES.has(code)||used.has(code))return null;
    result[action]=code;used.add(code);
  }
  return result;
}
let lastBindingsRejected = false;
function validateSettings(input, fallbackBindings=DEFAULT_BINDINGS) {
  lastBindingsRejected=false;
  const result={...DEFAULT_SETTINGS,bindings:{...fallbackBindings}};
  for(const key of ['muted','fov','enemy_alerts','auto_pause_man_down','reduced_flash','screen_shake'])if(typeof input?.[key]==='boolean')result[key]=input[key];
  for(const key of ['volume','music_volume'])if(Number.isFinite(input?.[key]))result[key]=Math.min(1,Math.max(0,input[key]));
  if([1,1.25,1.5].includes(input?.ui_scale))result.ui_scale=input.ui_scale;
  if(typeof input?.ui_scale_auto==='boolean')result.ui_scale_auto=input.ui_scale_auto;
  if([1,1.5,2].includes(input?.line_width))result.line_width=input.line_width;
  if(['default','deutan','protan','tritan'].includes(input?.palette))result.palette=input.palette;
  if(['ko','en'].includes(input?.language))result.language=input.language;
  if(input?.bindings!==undefined){
    const validated=validateBindings(input.bindings);
    if(validated)result.bindings=validated;
    else lastBindingsRejected=true;
  }
  return result;
}
let appliedSettings=null;
function applyAudioSettings(){if(effectGain)effectGain.gain.value=settings.muted?0:settings.volume;if(musicGain)musicGain.gain.value=settings.muted?0:settings.music_volume;}
function applySettings() {
  if(settings.ui_scale_auto)settings.ui_scale=autoUiScale();
  const previous=appliedSettings,changed=key=>!previous||previous[key]!==settings[key];
  const languageChanged=changed('language'),bindingsChanged=!previous||JSON.stringify(previous.bindings)!==JSON.stringify(settings.bindings);
  if(changed('ui_scale')){document.documentElement.style.setProperty('--ui-scale',settings.ui_scale);document.body.dataset.uiScale=String(settings.ui_scale);lastToolKey='';scheduleSafeArea();}
  if(changed('reduced_flash'))document.body.classList.toggle('reduced-motion',settings.reduced_flash);
  if(changed('palette'))document.body.dataset.palette=settings.palette||'default';
  if(languageChanged){setLanguage(settings.language==='en'?'en':'ko');applyStaticI18n();document.title=t('doc.title');updateBrief();scheduleSafeArea();}
  applyAudioSettings();
  if(languageChanged||bindingsChanged)renderHotbarBindings();
  if(languageChanged||changed('enemy_alerts'))renderState();
  else if(changed('ui_scale')&&['PLANNING','EXECUTING'].includes(state.mode))renderTool();
  if(engineReady&&(bindingsChanged||['fov','line_width','auto_pause_man_down','reduced_flash','screen_shake','palette','language'].some(changed)))send({action:'settings',settings},false);
  appliedSettings={...settings,bindings:{...settings.bindings}};
}
// RD1: hotbar key badges (plan 2-2 "조작 탭") reflect the live bindings so a
// rebind is visible immediately, not just inside the settings dialog.
function renderHotbarBindings(){
  const map={move:'hotbar-key-move',face:'hotbar-key-face',door:'hotbar-key-door',equipment:'hotbar-key-equipment',secure:'hotbar-key-secure',wait:'hotbar-key-wait',reload:'hotbar-key-reload',signal:'hotbar-key-signal'};
  for(const [action,id] of Object.entries(map)){const el=$(id);if(el)el.textContent=codeLabel(settings.bindings?.[action]||DEFAULT_BINDINGS[action]);}
}
function persistSettings() {
  const value={...settings};settingsDirty=true;
  settingsChain=settingsChain.then(async()=>{if(!storeAvailable)throw new Error('설정이 이 세션에만 적용됩니다. 설정 파일로 내보낼 수 있습니다.');const saved=await store.saveSettings(value,settingsVersion);settingsVersion=saved.version;settingsDirty=false;settingsChannel?.postMessage({tabId,version:settingsVersion});}).catch(async error=>{if(error.code==='SETTINGS_CONFLICT'){const latest=await store.get('settings','current').catch(()=>null);if(latest){settings=validateSettings(latest.data);settingsVersion=latest.version;applySettings();if(currentModal==='settings')renderSettings();}toast('다른 탭에서 설정이 변경되어 최신 설정을 불러왔습니다.','warning');}else storageError(error);});return settingsChain;
}
settingsChannel?.addEventListener('message',async event=>{if(event.data?.tabId===tabId||!storeAvailable)return;const latest=await store.get('settings','current').catch(()=>null);if(latest&&latest.version>settingsVersion){settingsVersion=latest.version;settings=validateSettings(latest.data);applySettings();if(currentModal==='settings')renderSettings();toast('다른 탭에서 저장한 설정을 적용했습니다.');}});

async function preloadAudio() {
  try {const AC=window.AudioContext||window.webkitAudioContext;if(!AC)return;audioContext=new AC();effectGain=audioContext.createGain();musicGain=audioContext.createGain();effectGain.connect(audioContext.destination);musicGain.connect(audioContext.destination);applyAudioSettings();
    combatBus=audioContext.createDynamicsCompressor();combatBus.threshold.value=-10;combatBus.knee.value=9;combatBus.ratio.value=4;combatBus.attack.value=.003;combatBus.release.value=.12;combatBus.connect(effectGain);
    await Promise.all(['select','order','door','door_alt','door_alt2','door_latch','door_latch_alt','door_latch_alt2','shot','shot_alt','shot_close','shot_close_alt','hit','hit_alt','stun','win','fail','ambient',...['concrete','wood'].flatMap(surface=>Array.from({length:5},(_,index)=>`footstep_${surface}_${String(index).padStart(3,'0')}`))].map(async name=>{try{const response=await fetch(`assets/audio/${name}.wav`);if(!response.ok)return;const buffer=await response.arrayBuffer();audioBuffers.set(name,await audioContext.decodeAudioData(buffer));}catch{}}));
    if(audioUnlocked)startAmbient();
  }catch(error){console.info('Audio unavailable',error);}
}
function unlockAudio(){if(!audioContext)return;audioUnlocked=true;audioContext.resume().then(startAmbient).catch(()=>{});}
function startAmbient(){if(!audioContext||!audioUnlocked||ambientSource||!audioBuffers.has('ambient'))return;ambientSource=audioContext.createBufferSource();ambientSource.buffer=audioBuffers.get('ambient');ambientSource.loop=true;ambientSource.connect(musicGain);ambientSource.start();}
const combatVoices=[],contactVoices=[];
const soundPools={
  shot:['shot_close','shot_close_alt','shot','shot_alt'],hit:['hit','hit_alt'],kill_confirm:['hit'],
  door:['door','door_alt','door_alt2'],door_latch:['door_latch','door_latch_alt','door_latch_alt2'],
  footstep_concrete:Array.from({length:5},(_,i)=>`footstep_concrete_${String(i).padStart(3,'0')}`),
  footstep_wood:Array.from({length:5},(_,i)=>`footstep_wood_${String(i).padStart(3,'0')}`),
};
let soundVariation=0;
function armourBlockBuffer(){
  const buffer=audioContext.createBuffer(1,Math.ceil(audioContext.sampleRate*.09),audioContext.sampleRate);
  const samples=buffer.getChannelData(0);let seed=731,previous=0;
  for(let i=0;i<samples.length;i++){
    const time=i/audioContext.sampleRate;
    seed=(Math.imul(seed,1664525)+1013904223)>>>0;
    const noise=seed/2147483648-1;
    const click=(noise-previous)*.09*Math.exp(-time/.0015);previous=noise;
    samples[i]=(.48*Math.sin(2*Math.PI*2710*time)+.3*Math.sin(2*Math.PI*4130*time)+.2*Math.sin(2*Math.PI*5870*time))*Math.exp(-time/.014)*Math.min(1,time/.0004)+click;
  }
  return buffer;
}
function playSound(name,details={}){
  if(!audioUnlocked||!audioContext||settings.muted||name==='ambient')return;
  if(name==='armour_block'&&!audioBuffers.has(name))audioBuffers.set(name,armourBlockBuffer());
  const combat=['shot','hit','armour_block','kill_confirm','door','stun'].includes(name);
  const contact=name.startsWith('footstep_')||name==='door_latch';
  const spatial=combat||contact;
  const voices=contact?contactVoices:combat?combatVoices:null;
  const eventSeed=Number.isFinite(details.event_seq)?details.event_seq:++soundVariation;
  let seed=eventSeed>>>0;for(const letter of String(details.attacker_id||name))seed=(Math.imul(seed,31)+letter.charCodeAt(0))>>>0;
  const available=(soundPools[name]||[name]).filter(candidate=>audioBuffers.has(candidate));
  if(!available.length)return;
  try{
    const now=audioContext.currentTime;
    // Footfalls have their own voice budget, so a moving squad never steals
    // the attack or impact that communicates a combat result.
    if(voices&&voices.length>=(contact?8:12)){
      const oldest=voices.shift();oldest.gain.gain.cancelScheduledValues(now);oldest.gain.gain.setTargetAtTime(0,now,.006);oldest.source.stop(now+.025);
    }
    const source=audioContext.createBufferSource(),gain=audioContext.createGain();
    source.buffer=audioBuffers.get(available[seed%available.length]);
    source.playbackRate.value=spatial?1+((seed%25)-12)*(contact?.0015:.001):1;
    if(name==='kill_confirm')source.playbackRate.value=1.45;
    const base={shot:.68,hit:.42,armour_block:.18,kill_confirm:.24,door:.48,door_latch:.28,footstep_concrete:.19,footstep_wood:.17,stun:.7}[name]??1;
    const attenuation=Number.isFinite(details.gain)?Math.min(1,Math.max(.25,details.gain)):1;
    gain.gain.value=base*attenuation*(spatial?.96+((seed>>>4)%9)*.01:1);
    source.connect(gain);
    let panner;
    if(spatial&&audioContext.createStereoPanner){panner=audioContext.createStereoPanner();panner.pan.value=Number.isFinite(details.pan)?Math.min(.8,Math.max(-.8,details.pan)):0;gain.connect(panner);panner.connect(combatBus||effectGain);}
    else gain.connect(spatial?combatBus||effectGain:effectGain);
    const voice={source,gain,panner};if(voices)voices.push(voice);
    source.onended=()=>{if(voices){const index=voices.indexOf(voice);if(index>=0)voices.splice(index,1);}source.disconnect();gain.disconnect();panner?.disconnect();};
    source.start(now);
  }catch{}
}
function stopAudio(){audioContext?.suspend().catch(()=>{});}

// --- RC: fx consumer (plan §5 / 2-1) --------------------------------------
// Godot emits {type:'fx',kind,time,...,screen:[x,y]} identically during live
// play and replay playback. The engine build currently staged may not send
// these at all yet, so every handler here is purely additive: no fx message
// ever changes sim/replay state, and nothing here blocks input (#fx-layer is
// pointer-events:none; dynamic nodes are plain absolutely-positioned divs).
let replayFx = [], unitHitCount = new Map(), replayFxKeys=new Set(), replayMarkerVersion=0, lastReplayMarkerKey='', replayMarkerFrame=null;
// world_view.gd TRACER_TRAVEL is 0.05s; web timers use milliseconds.
const HIT_REACTION_DELAY = 50;
let pendingHitFeedback = [];
function cancelPendingHitFeedback(){pendingHitFeedback=[];}
const transientFx=new Map(),cardFxTimers=new Map();
function clearTransientFx(keepLetterbox=false){
  cancelPendingHitFeedback();
  for(const [node,timer] of transientFx){if(keepLetterbox&&node.className.split(' ').includes('fx-letterbox'))continue;clearTimeout(timer);node.remove();transientFx.delete(node);}
  for(const [card,timer] of cardFxTimers){clearTimeout(timer);card.classList.remove('hit-flash','fx-shake','fx-incap');}
  cardFxTimers.clear();document.querySelectorAll('.unit-card.hit-flash,.unit-card.fx-shake,.unit-card.fx-incap').forEach(card=>card.classList.remove('hit-flash','fx-shake','fx-incap'));hitFlash.clear();
}
function feedbackTime(){return Number(state.mode==='REPLAY'?state.replay?.time:state.presentation_time??state.time)||0;}
function feedbackPaused(){return state.mode==='REPLAY'?state.replay?.playing===false:state.mode==='PLANNING';}
function flushHitFeedback(time,paused){
  if(paused||!Number.isFinite(time))return;
  const due=pendingHitFeedback.filter(item=>item.at<=time+1e-9);
  pendingHitFeedback=pendingHitFeedback.filter(item=>item.at>time+1e-9);
  for(const item of due)item.present();
}
function queueHitFeedback(fx,present){
  // Older staged engines omit react_at; only the in-game flash setting affects timing.
  const delay=fx.kind==='hit'||fx.after_shot===true;
  const at=Number.isFinite(fx.react_at)?fx.react_at:delay?(Number(fx.time)||0)+HIT_REACTION_DELAY*(settings.reduced_flash?.7:1)/1000:0;
  if(at<=0){present();return;}
  pendingHitFeedback.push({at,present});
  flushHitFeedback(feedbackTime(),feedbackPaused());
}
function resetReplayMarkers(){replayFx=[];replayFxKeys.clear();replayMarkerVersion++;lastReplayMarkerKey='';if(replayMarkerFrame!==null){cancelAnimationFrame(replayMarkerFrame);replayMarkerFrame=null;}}
function scheduleReplayMarkers(){if(replayMarkerFrame===null)replayMarkerFrame=requestAnimationFrame(()=>{replayMarkerFrame=null;if(state.mode==='REPLAY')renderReplayMarkers();});}
function fxSpawn(el, duration) {
  $('fx-layer').append(el);
  requestAnimationFrame(() => el.classList.add('show'));
  transientFx.set(el,setTimeout(()=>{el.remove();transientFx.delete(el);},duration));
}
function fxPoint(fx) { return Array.isArray(fx.screen) && fx.screen.length === 2 && fx.screen.every(Number.isFinite) ? { left: fx.screen[0], top: fx.screen[1] } : null; }
function hitConfirm(fx) {
  const point=fxPoint(fx);if(!point)return;
  const marker=document.createElement('div');
  marker.className=`fx-hit-confirm${fx.protection==='blocked'?' fx-blocked-confirm':''}`;
  marker.setAttribute('aria-hidden','true');
  marker.style.left=`${point.left}px`;marker.style.top=`${point.top}px`;
  fxSpawn(marker,120);
}
function presentHitFeedback(fx) {
  const reduced=settings.reduced_flash||document.body.classList.contains('reduced-motion')||matchMedia('(prefers-reduced-motion: reduce)').matches;
  if(fx.kind==='neutralized'){
    if(fx.cause!=='arrest')playSound('kill_confirm',{event_seq:fx.event_seq,attacker_id:fx.id,gain:.8});
  }else if(fx.kind==='unit_down'){
    const banner=document.createElement('div');banner.className='fx-banner fx-banner-down';banner.textContent=t('fx.unit_down');fxSpawn(banner,2200);
    const card=document.querySelector(`.unit-card[data-unit="${CSS.escape(String(fx.unit_id??fx.id??''))}"]`);
    if(card){clearTimeout(cardFxTimers.get(card));card.classList.add('fx-incap');cardFxTimers.delete(card);}
  }else if(fx.friendly){
    const vignette=document.createElement('div');vignette.className=`fx-vignette${reduced?' fx-subtle':''}`;fxSpawn(vignette,420);
    const card=document.querySelector(`.unit-card[data-unit="${CSS.escape(String(fx.target_id??fx.unit_id??fx.id??''))}"]`);
    hitFlash.set(String(fx.target_id??fx.unit_id??fx.id??''),performance.now()+500);
    if(card){clearTimeout(cardFxTimers.get(card));card.classList.add('hit-flash');if(settings.screen_shake!==false&&!reduced)card.classList.add('fx-shake');cardFxTimers.set(card,setTimeout(()=>{card.classList.remove('hit-flash','fx-shake');cardFxTimers.delete(card);},500));}
  }else hitConfirm(fx);
}
function handleFx(fx) {
  if(['MENU','RESULT'].includes(state.mode)&&fx.kind!=='mission_end')return;
  if (state.mode === 'REPLAY') {
    // L3: seeking/looping a replay can re-deliver the same fx message; key on
    // kind+time+id (whichever id field the kind carries) so the timeline
    // markers don't grow duplicate entries.
    const fxId = fx.unit_id ?? fx.target_id ?? fx.entity_id ?? fx.door_id ?? fx.id ?? fx.room_name ?? fx.room ?? '';
    const fxKey = `${fx.kind}:${Number(fx.time) || 0}:${fxId}:${fx.event_seq ?? ''}`;
    if (fxMarkerKind[fx.kind]&&!replayFxKeys.has(fxKey)) {
      replayFxKeys.add(fxKey);replayFx.push(fx);replayMarkerVersion++;scheduleReplayMarkers();
    }
  }
  if(['hit','neutralized','unit_down'].includes(fx.kind)){queueHitFeedback(fx,()=>presentHitFeedback(fx));return;}
  switch (fx.kind) {
    case 'room_clear': {
      const stamp = document.createElement('div'); stamp.className = 'fx-stamp';
      stamp.innerHTML = `<strong>${escapeHTML(t('fx.room_clear'))}</strong>${fx.room_name || fx.room ? `<span>${escapeHTML(fx.room_name || fx.room)}</span>` : ''}`;
      const point = fxPoint(fx);
      if (point) { stamp.style.left = `${point.left}px`; stamp.style.top = `${point.top}px`; } else stamp.classList.add('top-center');
      fxSpawn(stamp, 1600);
      break;
    }
    case 'enemy_spotted': {
      const banner = document.createElement('div'); banner.className = 'fx-banner fx-banner-threat'; banner.textContent = t('fx.enemy_spotted');
      fxSpawn(banner, 2000);
      break;
    }
    case 'mission_end': {
      const letterbox = document.createElement('div'); letterbox.className = 'fx-letterbox'; letterbox.innerHTML = '<i></i><i></i>';
      fxSpawn(letterbox, 900);
      break;
    }
  }
}
// Timeline event markers (plan §8): prefer fx messages actually observed
// during this replay session; fall back to the replay's own event log (same
// categorisation as the operation log) so markers still appear on a fresh
// replay load before any fx has streamed in.
const fxMarkerKind = { room_clear: null, enemy_spotted: 'spotted', hit: 'hit', neutralized: 'neutralized', breach: 'breach', unit_down: 'hit' };
function replayMarkerList() {
  const duration = Number(state.replay?.duration) || 0; if (duration <= 0) return [];
  const fromFx = replayFx.map(fx => ({ time: Number(fx.time) || 0, kind: fxMarkerKind[fx.kind] })).filter(m => m.kind);
  if (fromFx.length) return fromFx;
  return (state.events || []).map(event => {
    const type = event.type || '';
    const kind = /enemy|contact/i.test(type) ? 'spotted' : /hit|down/i.test(type) ? 'hit' : /clear|neutral/i.test(type) ? 'neutralized' : /door|breach/i.test(type) ? 'breach' : null;
    return kind ? { time: Number(event.time) || 0, kind } : null;
  }).filter(Boolean);
}
function renderReplayMarkers() {
  const container = $('replay-markers'); if (!container) return;
  const duration = Number(state.replay?.duration) || 0;
  const fallbackKey=replayFx.length?'':JSON.stringify((state.events||[]).map(event=>[event.type,event.time]));
  const key=`${duration}:${getLanguage()}:${replayMarkerVersion}:${fallbackKey}`;
  if(key===lastReplayMarkerKey)return;lastReplayMarkerKey=key;
  if (duration <= 0) { container.innerHTML = ''; return; }
  const labels = { spotted: t('fx.marker.spotted'), neutralized: t('fx.marker.neutralized'), hit: t('fx.marker.hit'), breach: t('fx.marker.breach') };
  container.innerHTML = replayMarkerList().map(marker => `<button type="button" class="replay-marker" data-kind="${marker.kind}" data-seek="${marker.time}" style="left:${Math.min(100, Math.max(0, marker.time / duration * 100)).toFixed(2)}%" title="${labels[marker.kind] || marker.kind} · ${formatTime(marker.time)}" aria-label="${t('fx.marker.goto',{label:labels[marker.kind] || marker.kind})}"></button>`).join('');
}

function ingestCatalog(input) {
  if(!input)return;
  const entries=Array.isArray(input)?input:Object.entries(input).map(([id,value])=>typeof value==='object'?{id,...value}:null).filter(Boolean);
  for(const incoming of entries) {
    if(!incoming?.id)continue;
    const previous=catalog.get(incoming.id),entry={...previous,...incoming};
    // Briefings provide a room count; keep the catalog's actual floorplan.
    if(Number.isFinite(incoming.rooms)&&Array.isArray(previous?.rooms))entry.rooms=previous.rooms;
    catalog.set(entry.id,entry);
    catalogRevision++;missionThumbCache.delete(entry.id);
    const base=missions[missionBase(entry.id)]||missions.M01,variant=VARIANTS.find(item=>item.id===entry.variant);
    missions[entry.id]={...base,time:entry.briefing?.estimated_minutes||base.time,english:entry.subtitle||entry.title_en||base.english,name_en:entry.title_en||base.name_en,name:entry.name||entry.title||`${base.name} · ${localize(variant||{},'label')||'작전'}`,title:entry.title||`${base.title} ${variant?.label||''}`,title_en:entry.title_en||(entry.title?null:base.title_en),description:typeof entry.briefing==='string'?entry.briefing:entry.briefing?.description||entry.description||base.description,description_en:entry.description_en||(entry.description||entry.briefing?null:base.description_en),units:String(Array.isArray(entry.units)?entry.units.length:Number(entry.units)||Number(base.units)).padStart(2,'0'),rooms:String(Array.isArray(entry.rooms)?entry.rooms.length:Number(entry.rooms)||Number(base.rooms)).padStart(2,'0'),objectives:entry.objectives||base.objectives,objectives_en:entry.objectives_en||base.objectives_en};
    parTimes[entry.id]=entry.par_time||parTimes[missionBase(entry.id)]||180;
  }
}
function ensureSquad() {
  const base=missionBase(selectedMission),available=availableRoster(campaign?.active&&!campaign.suspended?campaign:null).map(unit=>unit.id);
  const max=Math.min(4,Math.max(1,Number(missions[selectedMission]?.units)||4)),min=1;
  squadIds=squadIds.filter(id=>available.includes(id)).slice(0,max);
  if(preparedForBase!==base||squadIds.length<min){squadIds=available.slice(0,max);preparedForBase=base;}
  for(const id of squadIds)loadoutChoices[id]=normalizeOperatorLoadout(loadoutChoices[id]||{weapon:'standard',equipment:'stun'});
}
function currentPreparation() {
  ensureSquad();const configured=catalog.get(selectedMission)?.units,bases=Array.isArray(configured)&&configured.length?configured.map(unit=>unit.id):['alpha','bravo','charlie','delta'],roster=squadIds.map((id,index)=>({...ROSTER.find(unit=>unit.id===id),base_id:bases[index]}));
  const stars=unlockProfile.stars,loadout={};
  for(const unit of roster) {
    const choice=normalizeOperatorLoadout(loadoutChoices[unit.id]||{}),weapon=WEAPONS.find(item=>item.id===choice.weapon);
    loadout[unit.base_id]={...choice,weapon:weapon&&weapon.stars<=stars?weapon.id:'standard',equipment:{}};
    for(const [id,count] of Object.entries(choice.equipment||{})){const equipment=EQUIPMENT.find(item=>item.id===id);if(equipment&&equipment.stars<=stars&&equipmentPermitted(id,catalog.get(selectedMission))&&!(id==='stun'&&selectedModifiers.has('no_stun')))loadout[unit.base_id].equipment[id]=count;}
  }
  return {loadout,roster:roster.map(unit=>({id:unit.id,name:rosterName(unit),trait:unit.trait,base_id:unit.base_id}))};
}
function resolvedSeed(id=selectedMission) {
  if(seedMode==='custom')return customSeed;
  if(seedMode==='random')return randomSeed;
  if(seedMode==='daily')return (hashSeed(`breach-seed:${localDate()}`)%2147483646)+1;
  return Number(catalog.get(id)?.seed)||undefined;
}
function preparationMeta(id=selectedMission) {return {mission:id,id,seed:resolvedSeed(id),variant:selectedVariant==='standard'?(catalog.get(id)?.variant||(id.endsWith('H')?'challenge':'normal')):selectedVariant,modifiers:[...selectedModifiers].sort(),...currentPreparation()};}
function renderCQBPreparation(){
  const family=cqbFamily(selectedMission);$('cqb-share').hidden=!family;
  if(!family)return;
  $('cqb-shared-seed').textContent=t('cqb.shared_seed',{mission:selectedMission,seed:resolvedSeed()??t('seed.default')});
}
function useCQBDailySeed(){
  if(!isCQBContentMission(selectedMission))return;
  seedMode='daily';renderPreparation();
}
async function copyCQBSeed(){
  if(!isCQBContentMission(selectedMission))return;
  const seed=resolvedSeed();if(!Number.isSafeInteger(seed))return;
  try{await navigator.clipboard.writeText(`${selectedMission} · ${seed}`);toast(t('cqb.seed_copied'));}catch{toast(t('cqb.seed_copy_failed'),'warning');}
}
function rulesDescription(metadata) {
  const names=getLanguage()==='en'
    ?{neutralize_all:'Neutralize every hostile (arrests count)',secure_all_civilians:'Secure every civilian',reach_zone:'Reach the marked objective zone',before_alert:'Finish before the alert is raised',time_limit:'Time limit',escort_to_zone:'Escort the civilian to the objective zone',no_civilian_loss:'Complete with no civilian losses',targets_complete:'Visit marked objectives in order and stop inside each zone',no_shots:'Complete without firing'}
    :{neutralize_all:'모든 위협 무력화 (체포 포함)',secure_all_civilians:'모든 민간인 확보',reach_zone:'표시된 목적 구역 도달',before_alert:'적 경보 이전 완료',time_limit:'시간 제한',escort_to_zone:'민간인을 목적 구역으로 호송',no_civilian_loss:'민간인 손실 없이 완료',targets_complete:'표시된 목표를 순서대로 방문해 안에서 멈춰 완료',no_shots:'사격 없이 작전 완료'};
  return [...(metadata?.win||[]),...(metadata?.fail||[])].map(rule=>rule.type==='rooms_cleared'?t(Array.isArray(rule.room_ids)?'room.goal_selected':'room.goal_all',{count:rule.room_ids?.length}):`${names[rule.type]||rule.type}${rule.type==='time_limit'?` ${rule.seconds}${getLanguage()==='en'?'s':'초'}`:''}`);
}
async function persistCampaign() {if(!campaign)return false;progress.set('campaign',campaign);refreshProgression();if(!storeAvailable)return false;try{await store.put('progress',campaign);return true;}catch(error){storageError(error);return false;}}
function campaignRestoreProblem() {
  if(!campaign?.active||campaign.suspended)return null;
  if(missionBase(state.mission)!==campaign.mission)return `캠페인의 다음 작전은 ${campaign.mission}입니다.`;
  const unavailable=new Set([...(campaign.injured||[]),...(campaign.lost||[])]);
  if((state.units||[]).some(unit=>unavailable.has(unit.roster_id||unit.id)))return '결장 대원이 포함된 초기 계획을 사용할 수 없습니다. 새 계획으로 대원을 다시 선발하세요.';
  return checkCampaignLoadout(campaign,state.loadout||{});
}
// --- RB: Cycler component (replaces <select>) ----------------------------
// `name` identifies a shared cyclerDefs entry (difficulty/variant/seedmode);
// pass `name=null` with `extraData={loadout,slot}` for a per-unit loadout
// cycler instead. ◀/▶ step through non-disabled options; clicking the
// output opens a quick-pick list (keeps mouse users and tests one click
// away from any value without losing keyboard/gamepad stepping).
function renderCycler(name, options, value, disabled = false, extraData = null) {
  const list = options.map(o => ({ id: o.id, label: o.label, disabled: !!o.disabled }));
  const current = list.find(o => o.id === value) || list[0] || { label: '' };
  const photos=!!extraData?.photos,gallery=!!extraData?.gallery;
  const dataAttrs = name ? ` data-cycler="${name}"` : ` data-cycler="loadout" data-loadout="${escapeHTML(extraData.loadout)}" data-slot="${escapeHTML(extraData.slot)}"`;
  return `<div class="cycler${photos?' gear-picker':''}${gallery?' gear-gallery':''}"${dataAttrs}${gallery?' data-gallery="true"':''}${disabled ? ' data-disabled="true"' : ''}>`
    + (photos&&!gallery?`<div class="gear-current-photo">${equipmentPhoto(current.id,current.label)}</div>`:'')
    + `<button type="button" class="cycler-prev" data-cycle-dir="-1" aria-label="${equipmentText('이전 값','Previous option')}"${disabled ? ' disabled' : ''}>◀</button>`
    + `<output tabindex="0" role="button" aria-haspopup="listbox" aria-expanded="${gallery}">${escapeHTML(current.label)}</output>`
    + `<button type="button" class="cycler-next" data-cycle-dir="1" aria-label="${equipmentText('다음 값','Next option')}"${disabled ? ' disabled' : ''}>▶</button>`
    + `<div class="cycler-list panel" role="listbox"${gallery?'':' hidden'}>${list.map(o => `<button type="button" role="option" data-cycle-set="${escapeHTML(o.id)}" aria-selected="${o.id === value}"${o.disabled ? ' disabled' : ''}>${photos?equipmentPhoto(o.id,o.label):''}<span>${escapeHTML(o.label)}</span>${photos?`<small>${o.disabled?equipmentText('사용 불가','Unavailable'):o.id===value?equipmentText('장착 중','Equipped'):equipmentText('선택','Select')}</small>`:''}</button>`).join('')}</div>`
    + `</div>`;
}
function equipmentPhoto(id,label,loading='lazy'){
  return id==='none'?`<span class="gear-empty">${equipmentText('장착 안 함','Not equipped')}</span>`:`<img src="assets/equipment/${escapeHTML(id)}.jpg" alt="${escapeHTML(label)}" loading="${loading}" decoding="async" width="1200" height="800">`;
}
const cyclerDefs = {
  difficulty: {
    options: () => [{ id: 'normal', label: t('cycler.normal') }, { id: 'challenge', label: t('variant.challenge') }],
    get: () => missionBase(selectedMission) === 'T01' ? 'normal' : selectedDifficulty,
    set: value => { selectedDifficulty = value; chooseMission(selectedMission); },
  },
  variant: {
    options: () => VARIANTS.filter(item => Number(missionBase(selectedMission).slice(1)) < 4 || item.id === 'standard').map(item => ({ id: item.id, label: localize(item,'label') })),
    get: () => selectedVariant,
    set: value => { selectedVariant = value; chooseMission(missionBase(selectedMission)); },
  },
  seedmode: {
    options: () => [{ id: 'fixed', label: t('cycler.fixed') }, { id: 'random', label: t('cycler.random') }, { id: 'custom', label: t('cycler.custom') }, { id: 'daily', label: t('cycler.daily') }],
    get: () => seedMode,
    set: value => { seedMode = value; if (value === 'random') randomSeed = (globalThis.crypto.getRandomValues(new Uint32Array(1))[0] % 2147483646) + 1; renderPreparation(); },
  },
  // RD1: settings-screen cyclers (plan 2-2) — replace the old <select> fields
  // with the shared Cycler component. Each setter mutates `settings`,
  // persists, applies, and re-renders the settings dialog in place.
  ui_scale: {
    options: () => [{ id: '1', label: '100%' }, { id: '1.25', label: '125%' }, { id: '1.5', label: '150%' }],
    get: () => String(settings.ui_scale),
    set: value => { settings.ui_scale = Number(value); settings.ui_scale_auto = false; applySettings(); persistSettings(); if (currentModal === 'settings') renderSettings(); },
  },
  line_width: {
    options: () => getLanguage()==='en'
      ? [{ id: '1', label: 'Default' }, { id: '1.5', label: 'Bold' }, { id: '2', label: 'Extra bold' }]
      : [{ id: '1', label: '기본' }, { id: '1.5', label: '굵게' }, { id: '2', label: '아주 굵게' }],
    get: () => String(settings.line_width),
    set: value => { settings.line_width = Number(value); applySettings(); persistSettings(); if (currentModal === 'settings') renderSettings(); },
  },
  palette: {
    options: () => getLanguage()==='en'
      ? [{ id: 'default', label: 'Normal' }, { id: 'deutan', label: 'Red-green (deutan)' }, { id: 'protan', label: 'Red-green (protan)' }, { id: 'tritan', label: 'Blue-yellow (tritan)' }]
      : [{ id: 'default', label: '일반' }, { id: 'deutan', label: '적록(녹색맹)' }, { id: 'protan', label: '적록(적색맹)' }, { id: 'tritan', label: '청황(청색맹)' }],
    get: () => settings.palette,
    set: value => { settings.palette = value; applySettings(); persistSettings(); if (currentModal === 'settings') renderSettings(); },
  },
  language: {
    options: () => [{ id: 'ko', label: '한국어' }, { id: 'en', label: 'English' }],
    get: () => settings.language,
    set: value => { settings.language = value; applySettings(); persistSettings(); if (currentModal === 'settings') renderSettings(); },
  },
};
function profileTool(choice){if(typeof choice?.equipment==='string')return choice.equipment;return ['stun','smoke','breach','frag'].find(id=>Number(choice?.equipment?.[id])>0)||'none';}
function profileSlotValue(choice,slot){return slot==='equipment'?profileTool(choice):choice?.[slot];}
function loadoutCyclerOptions(slot) {
  const stars = unlockProfile.stars;
  const lists={weapon:WEAPONS,equipment:[{id:'none',label:'없음',label_en:'None',stars:0},...EQUIPMENT.filter(item=>item.id!=='probe_c1')],sidearm:[{id:'none',label:'없음',label_en:'None',stars:0},...SIDEARMS],armor:ARMORS,helmet:[{id:'none',label:'없음',label_en:'None',stars:0},...HELMETS],preset:[{id:'custom',label:'개인 설정',label_en:'Custom',stars:0},...PRESETS]};
  return (lists[slot]||[]).map(item => ({ id: item.id, label: `${localize(item,'label')}${item.stars > stars ? ` (${t('progress.star_short',{stars:item.stars})})` : ''}${slot==='equipment'&&!equipmentPermitted(item.id,catalog.get(selectedMission))?` · ${t('roe.frag_prohibited')}`:''}`, disabled: (Number(item.stars)||0)>stars || (slot==='equipment'&&!equipmentPermitted(item.id,catalog.get(selectedMission))) || (slot === 'equipment' && item.id === 'stun' && selectedModifiers.has('no_stun')) || (slot==='preset'&&selectedModifiers.has('no_stun')&&Number(item.loadout?.equipment?.stun)>0) }));
}
function showProfileSaveStatus(id){const node=$('profile-save-status');if(node&&customizationId===id)node.textContent=profileSaveStatus.get(id)||equipmentText('선택한 장비는 대원별로 저장됩니다.','Equipment is saved for this operator.');}
function persistOperatorProfile(id){
  const value=structuredClone(normalizeOperatorLoadout(loadoutChoices[id])),version=(profileSaveVersions.get(id)||0)+1;profileSaveVersions.set(id,version);
  const finish=message=>{if(profileSaveVersions.get(id)!==version)return;profileSaveStatus.set(id,message);showProfileSaveStatus(id);};
  profileSaveStatus.set(id,equipmentText('저장 중…','Saving…'));showProfileSaveStatus(id);
  profileSaveChain=profileSaveChain.catch(()=>{}).then(async()=>{
    if(!storeAvailable){finish(equipmentText('이번 세션에 적용됨 · 브라우저 저장 불가','Applied for this session · storage unavailable'));return;}
    try{await store.saveOperatorProfile(id,value);finish(equipmentText('대원 장비 저장됨','Operator profile saved'));}catch(error){finish(equipmentText('이번 세션에 적용됨 · 저장 실패','Applied for this session · save failed'));storageError(error);}
  });return profileSaveChain;
}
function updateProfile(id,changes,{render=true}={}){
  const previous=normalizeOperatorLoadout(loadoutChoices[id]||{});comparisonLoadouts.set(id,structuredClone(previous));
  loadoutChoices[id]=normalizeOperatorLoadout({...previous,...changes});
  persistOperatorProfile(id);if(render)renderSquad();else updateOperatorPreview();
}
function setProfileSlot(id,slot,value){
  if(!loadoutCyclerOptions(slot).some(item=>item.id===value&&!item.disabled))return;
  const choice=normalizeOperatorLoadout(loadoutChoices[id]||{});
  if(slot==='equipment'){const equipment={};if(choice.equipment.probe_c1)equipment.probe_c1=1;if(value!=='none')equipment[value]=1;updateProfile(id,{equipment,preset:'custom'});return;}
  if(slot==='preset'){if(value==='custom'){updateProfile(id,{preset:'custom'});return;}const preset=PRESETS.find(item=>item.id===value);if(!preset)return;const normalized=normalizeOperatorLoadout({...choice,...preset.loadout,appearance:choice.appearance,preset:value});if(!WEAPONS.some(item=>item.id===normalized.weapon&&item.stars<=unlockProfile.stars)){toast(equipmentText('이 역할의 주무기를 먼저 해금하세요.','Unlock the primary weapon for this role first.'),'warning');return;}updateProfile(id,normalized);return;}
  updateProfile(id,{[slot]:value,preset:'custom'});
}
function cyclerStep(root, dir) {
  if (!root || root.hasAttribute('data-disabled')) return;
  const name = root.dataset.cycler;
  if (name === 'loadout') {
    const unitId = root.dataset.loadout, slot = root.dataset.slot, options = loadoutCyclerOptions(slot).filter(item => !item.disabled);
    if (!options.length) return;
    let index = options.findIndex(item => item.id === profileSlotValue(loadoutChoices[unitId],slot)); if (index < 0) index = 0;
    setProfileSlot(unitId,slot,options[(index + dir + options.length) % options.length].id);return;
  }
  const def = cyclerDefs[name]; if (!def) return;
  const options = def.options().filter(item => !item.disabled); if (!options.length) return;
  let index = options.findIndex(item => item.id === def.get()); if (index < 0) index = 0;
  def.set(options[(index + dir + options.length) % options.length].id);
}
function cyclerSet(root, value) {
  if (!root || root.hasAttribute('data-disabled')) return;
  const name = root.dataset.cycler;
  if (name === 'loadout') {setProfileSlot(root.dataset.loadout,root.dataset.slot,value);return;}
  cyclerDefs[name]?.set(value);
}
// --- RB: Toggle Card (replaces checkboxes) --------------------------------
function renderToggleCard(item, active) {
  const label=localize(item,'label'),description=localize(item,'description');
  return `<button type="button" class="toggle-card" data-modifier="${item.id}" aria-pressed="${active}" title="${escapeHTML(description)}"><span class="toggle-icon">${active ? '✓' : ''}</span><span><strong>${escapeHTML(label)}</strong><small>${escapeHTML(description)}</small></span></button>`;
}
function toggleModifier(id) { if (selectedModifiers.has(id)) selectedModifiers.delete(id); else selectedModifiers.add(id); renderPreparation(); }
function toggleRoster(id) {
  const max = Math.min(4, Math.max(1, Number(missions[selectedMission]?.units) || 4)), min = 1;
  if (squadIds.includes(id)) { if (squadIds.length <= min) { toast(t('progress.min_squad'), 'warning'); return; } squadIds = squadIds.filter(unitId => unitId !== id); }
  else { if (squadIds.length >= max) { toast(`이 임무는 최대 ${max}명까지 선발할 수 있습니다.`, 'warning'); return; } squadIds.push(id); }
  renderSquad(); renderDeploySlots();
}
// --- RB2: mission thumbnail art (plan item 2) ------------------------------
// Prefer a true top-down floor plan traced from the mission's own
// rooms/walls rectangles when the engine has exposed them on the catalog
// entry (ingestCatalog merges `catalog_update`/`ready` payloads into
// `catalog`); rooms/walls carry no enemy/civilian/door-state info so this
// never violates the fog-of-war rule. Falls back to a distinctive hand-set
// glyph + code + room-count card when geometry isn't available yet (e.g.
// right after boot, before the first catalog_update lands).
const missionGlyphs = {
  T01: '<circle cx="54" cy="54" r="30"/><circle cx="54" cy="54" r="13"/><path d="M54 8v20M54 78v20M8 54h20M78 54h20"/>',
  M01: '<path d="M26 58 54 32l28 26"/><path d="M34 54v32h40V54"/><path d="M48 86V68h12v18"/>',
  M02: '<rect x="22" y="28" width="64" height="52"/><path d="M22 46h64M42 46v34M66 46v34"/>',
  M03: '<path d="M18 38 54 20l36 18-36 18-36-18Z"/><path d="M18 38v36l36 18 36-18V38M54 56v36"/>'
};
function missionThumbMarkup(id) {
  const base = missionBase(id), entry = catalog.get(id) || catalog.get(base);
  const cached=missionThumbCache.get(id),roomCount=(missions[id]||missions[base])?.rooms;
  if(cached&&cached.entry===entry&&cached.roomCount===roomCount)return cached.html;
  const remember=html=>{missionThumbCache.set(id,{entry,roomCount,html});return html;};
  const rooms = Array.isArray(entry?.rooms) ? entry.rooms.filter(r => Number.isFinite(r?.x) && Number.isFinite(r?.z) && Number.isFinite(r?.w) && Number.isFinite(r?.d)) : [];
  if (rooms.length) {
    const walls = Array.isArray(entry?.walls) ? entry.walls.filter(w => Number.isFinite(w?.x) && Number.isFinite(w?.z) && Number.isFinite(w?.w) && Number.isFinite(w?.d)) : [];
    let minX = Infinity, minZ = Infinity, maxX = -Infinity, maxZ = -Infinity;
    for (const r of rooms) { minX = Math.min(minX, r.x-r.w/2); minZ = Math.min(minZ, r.z-r.d/2); maxX = Math.max(maxX, r.x+r.w/2); maxZ = Math.max(maxZ, r.z+r.d/2); }
    const span = Math.max(1, maxX - minX, maxZ - minZ), scale = 92 / span, padX = (100 - (maxX - minX) * scale) / 2, padY = (100 - (maxZ - minZ) * scale) / 2;
    const toX = x => ((x - minX) * scale + padX).toFixed(1), toY = z => ((z - minZ) * scale + padY).toFixed(1);
    const roomRects = rooms.map(r => `<rect x="${toX(r.x-r.w/2)}" y="${toY(r.z-r.d/2)}" width="${(r.w * scale).toFixed(1)}" height="${(r.d * scale).toFixed(1)}"/>`).join('');
    const wallRects = walls.map(w => `<rect x="${toX(w.x-w.w/2)}" y="${toY(w.z-w.d/2)}" width="${Math.max(1, w.w * scale).toFixed(1)}" height="${Math.max(1, w.d * scale).toFixed(1)}"/>`).join('');
    return remember(`<svg class="mission-floorplan" viewBox="0 0 100 100" preserveAspectRatio="xMidYMid meet" aria-hidden="true"><g class="fp-rooms">${roomRects}</g><g class="fp-walls">${wallRects}</g></svg>`);
  }
  const mission = missions[id] || missions[base] || {};
  return remember(`<svg class="mission-glyph" viewBox="0 0 108 108" aria-hidden="true">${missionGlyphs[base] || missionGlyphs.T01}</svg><span class="thumb-code">${escapeHTML(base)}</span><span class="thumb-rooms">${escapeHTML(mission.rooms || '—')}<small> ROOMS</small></span>`);
}
// --- RB: Mission grid (작전 선택) and Operator deployment slots (브리핑) ---
function refreshProgression(){unlockProfile=progressionState(missionProgress,campaign);}
function missionLockText(id){const access=missionAccess(id,unlockProfile);return access.stars?t('progress.need_stars',{stars:access.stars,current:unlockProfile.stars}):t('progress.need_clear',{mission:localize(missions[access.previous]||{},'name')||access.previous});}
function checkProgression(plan){
  const problem=progressionProblem(plan,unlockProfile);if(!problem)return true;
  toast(problem.kind==='mission'?missionLockText(problem.id):t('progress.gear_locked',{name:localize(problem,'label'),stars:problem.stars,current:unlockProfile.stars}),'warning');return false;
}
function rewardName(item){return item.kind==='mission'?`${item.id} · ${localize(missions[item.id]||{},'name')||item.id}`:item.kind==='history'?t('progress.history_pack',{missions:item.missions.join(' · ')}):localize(item,'label');}
function nextStarReward(){return progressionRewards(unlockProfile).filter(item=>item.stars>unlockProfile.stars).sort((a,b)=>a.stars-b.stars)[0];}
function renderProgressionSummary(){
  const ids=['T01',...CAMPAIGN_MISSIONS,...HISTORICAL_UNLOCKS.flatMap(item=>item.missions)];
  $('progression-summary').textContent=t('progress.summary',{stars:unlockProfile.stars,open:ids.filter(id=>missionAccess(id,unlockProfile).unlocked).length,total:ids.length});
}
function renderProgression(){
  const next=nextStarReward(),maps=CAMPAIGN_MISSIONS.map(id=>({id,kind:'mission',...missionAccess(id,unlockProfile)}));
  const gear=[...WEAPONS.map(item=>({...item,kind:'weapon'})),...EQUIPMENT.map(item=>({...item,kind:'equipment'}))];
  showModal(t('progress.armory'),'OPERATION REWARDS',`<div class="progression-overview"><strong>★ ${unlockProfile.stars}</strong><div><b>${t('progress.total')}</b><p>${t('progress.rule')}</p></div></div><p class="progression-next">${next?t('progress.next',{name:rewardName(next),remaining:next.stars-unlockProfile.stars}):t('progress.all_stars_unlocked')}</p><h3>${t('progress.gear')}</h3><div class="unlock-grid">${gear.map(item=>{const owned=unlockProfile.stars>=item.stars;return `<article class="unlock-card${owned?' owned':''}" data-unlock-gear="${item.id}"><span class="unlock-status">${t(owned?'progress.available':'progress.locked')}</span><h4>${escapeHTML(localize(item,'label'))}</h4><p>${escapeHTML(localize(item,'note'))}</p><progress max="${Math.max(1,item.stars)}" value="${owned?Math.max(1,item.stars):unlockProfile.stars}" aria-label="${escapeHTML(localize(item,'label'))}"></progress><small>${item.stars?t('progress.need_stars',{stars:item.stars,current:unlockProfile.stars}):t('progress.starting')}</small></article>`;}).join('')}</div><h3>${t('progress.maps')}</h3><div class="unlock-map-list">${maps.map(item=>`<div><strong>${escapeHTML(rewardName(item))}</strong><span>${item.unlocked?t('progress.available'):escapeHTML(missionLockText(item.id))}</span></div>`).join('')}${HISTORICAL_UNLOCKS.map(item=>`<div><strong>${escapeHTML(rewardName(item))}</strong><span>${unlockProfile.stars>=item.stars?t('progress.available'):t('progress.need_stars',{stars:item.stars,current:unlockProfile.stars})}</span></div>`).join('')}</div><p class="note">${t(storeAvailable&&!progressSaveFailed?'progress.local_save':'progress.session')}</p><div class="dialog-footer"><button id="progression-equip" class="primary">${t('progress.equip')}</button></div>`);
}
function renderResultProgression(){
  const rewards=resultRewards||{stars:0,unlocks:[]},next=nextStarReward();
  $('result-progression').innerHTML=`<strong>${isProgressionMission(state.mission)?t('progress.earned',{earned:rewards.stars,total:unlockProfile.stars}):t('progress.sandbox')}</strong>${rewards.unlocks.length?`<ul>${rewards.unlocks.map(item=>`<li>${t('progress.new_unlock',{name:escapeHTML(rewardName(item))})}</li>`).join('')}</ul>`:''}<p>${next?t('progress.next',{name:escapeHTML(rewardName(next)),remaining:next.stars-unlockProfile.stars}):t('progress.all_stars_unlocked')}</p><button data-open="progression">${t('progress.rewards')}</button><p id="result-progression-save" class="note">${storeAvailable&&!progressSaveFailed?'':t('progress.session')}</p>`;
}
function renderMissionGrid() {
  const grid = $('mission-grid'); if (!grid) return;
  const historyIds = [...catalog.keys()].filter(id=>/^H\d{2}$/.test(id)).sort();
  const roeIds=['M01_PRECISION','M01_HIGH_INTENSITY'].filter(id=>catalog.has(id));
  const ids = operationCollection==='history'?historyIds:operationCollection==='cqb'?CQB_MISSIONS.filter(id=>catalog.has(id)):['T01', ...CAMPAIGN_MISSIONS,...roeIds];
  const key=JSON.stringify([operationCollection,catalogRevision,getLanguage(),unlockProfile.stars,[...unlockProfile.completedBases],[...unlockProfile.campaignAccess],ids.map(id=>{const record=progress.get(id);return [id,record?.completed,record?.bestScore,record?.stars||record?.medals];})]);
  if(key===lastMissionGridKey)return;lastMissionGridKey=key;
  $$('[data-collection]').forEach(button=>button.setAttribute('aria-pressed',String(button.dataset.collection===operationCollection)));
  $('operation-scale-note').textContent=operationCollection==='history'?t('select.collection_scale',{count:historyIds.length}):operationCollection==='cqb'?t('cqb.collection_scale',{count:ids.length}):'';
  grid.innerHTML = ids.filter(id => missions[id]).map(id => {
    const mission = missions[id] || {}, record = progress.get(id), achieved = migrateMedals(record?.stars || record?.medals);
    const bounds=catalog.get(id)?.bounds, dimensions=Array.isArray(bounds)?`${bounds[0]} × ${bounds[1]} m`:'';
    const starCount = Object.values(achieved).filter(Boolean).length,goalCount=Math.max(catalog.get(id)?.stars?.length||3,starCount),access=missionAccess(id,unlockProfile);
    const stars = '★'.repeat(starCount) + '☆'.repeat(Math.max(0, goalCount - starCount));
    return `<button type="button" id="tab-${id}" class="mission-card${access.unlocked?'':' locked'}" data-unlocked="${access.unlocked}" role="tab" aria-selected="false" aria-controls="mission-detail" data-mission="${id}">`
      + `<div class="mission-thumb" data-thumb="${id}">${missionThumbMarkup(id)}${roeBadge(catalog.get(id))}</div>`
      + `<div class="mission-card-info"><span class="mission-code">${id}</span><strong>${escapeHTML(localize(mission,'name') || id)}</strong>${dimensions?`<span class="mission-map-size">${dimensions}</span>`:''}<span class="mission-stars${starCount ? ' achieved' : ''}">${stars}</span>${!access.unlocked?`<span class="mission-lock">${escapeHTML(missionLockText(id))}</span>`:''}${record?.completed ? `<span class="mission-rank">${t('mission.best',{score:record.bestScore||0})}</span>` : ''}</div>`
      + `</button>`;
  }).join('');
}
// --- RB2: variant chip row (plan item 2 — H/challenge, escort, hostage…
// shown on the detail panel so a player can preview/pick a variant before
// reaching the briefing's full cyclers). Reuses the existing difficulty/
// variant setters so the two stay in sync everywhere.
function renderBriefVariants() {
  const row = $('brief-variants'); if (!row) return;
  const base = missionBase(selectedMission), locked = base === 'T01' || /^H\d{2}$/.test(base) || ['M01_PRECISION','M01_HIGH_INTENSITY'].includes(base) || isCQBContentMission(base);
  const chips = [];
  if (!locked) chips.push({ id: 'challenge', label: t('variant.challenge'), active: selectedDifficulty === 'challenge' });
  for (const variant of VARIANTS) {
    if ((locked || Number(base.slice(1)) >= 4) && variant.id !== 'standard') continue;
    chips.push({ id: `variant:${variant.id}`, label: localize(variant,'label'), active: selectedVariant === variant.id });
  }
  row.innerHTML = chips.map(chip => `<button type="button" class="variant-chip${chip.active ? ' active' : ''}" data-variant-chip="${chip.id}">${escapeHTML(chip.label)}</button>`).join('');
}
function renderDeploySlots() {
  ensureSquad();
  const max = Math.min(4, Math.max(1, Number(missions[selectedMission]?.units) || 4));
  $('squad-count-briefing').textContent = String(squadIds.length).padStart(2, '0');
  $('deploy-slots').innerHTML = Array.from({ length: max }, (_, index) => {
    const unit = ROSTER.find(item => item.id === squadIds[index]);
    if (!unit) return `<button type="button" class="deploy-slot empty" data-slot-index="${index}">+ ${t('deploy.add')}</button>`;
    const uname=rosterName(unit); return `<button type="button" class="deploy-slot filled" data-slot-index="${index}"><span class="slot-portrait">${escapeHTML(uname[0])}</span><strong>${escapeHTML(uname)}</strong><small>${escapeHTML(localize(unit,'label'))}</small></button>`;
  }).join('');
}
function renderPreparation() {
  ensureSquad();
  const base = missionBase(selectedMission), locked = base === 'T01' || /^H\d{2}$/.test(base) || ['M01_PRECISION','M01_HIGH_INTENSITY'].includes(base) || isCQBContentMission(base);
  $('difficulty-cycler-slot').innerHTML = renderCycler('difficulty', cyclerDefs.difficulty.options(), cyclerDefs.difficulty.get(), locked||selectedVariant!=='standard');
  $('variant-cycler-slot').innerHTML = renderCycler('variant', cyclerDefs.variant.options(), selectedVariant, locked);
  $('seedmode-cycler-slot').innerHTML = renderCycler('seedmode', cyclerDefs.seedmode.options(), seedMode);
  $('custom-seed-row').hidden = seedMode !== 'custom'; $('custom-seed').value = customSeed;
  $('seed-preview').textContent = t('seed.preview',{seed:resolvedSeed() ?? t('seed.default')});
  $('modifier-options').innerHTML = MODIFIERS.map(item => renderToggleCard(item, selectedModifiers.has(item.id))).join('');
  $('preparation-summary').textContent = getLanguage()==='en'?`${squadIds.length} selected · ${unlockProfile.stars} stars total · ${squadIds.map(id => localize(ROSTER.find(unit => unit.id === id)||{},'name')).join(' / ')}`:`${squadIds.length}명 선발 · 누적 별 ${unlockProfile.stars}개 · ${squadIds.map(id => ROSTER.find(unit => unit.id === id)?.name).join(' / ')}`;
  $('campaign-summary').hidden = !campaign?.active || campaign.suspended; $('campaign-summary').textContent = campaign?.active ? `캠페인 ${campaign.index + 1}/${campaignMissions(campaign).length} · 다음 ${campaign.mission} · 스턴 ${campaign.inventory.stun} / 장약 ${campaign.inventory.breach}${campaign.ironman ? ' · 아이언맨' : ''}` : '';
  renderDeploySlots();
  renderCQBPreparation();
}
function updateOperatorPreview(){
  const node=$('operator-preview');if(currentModal!=='squad'||!node||!engineReady)return;
  const rect=node.getBoundingClientRect(),modalRect=$('modal').getBoundingClientRect();
  const top=Math.max(0,rect.top,modalRect.top),bottom=Math.min(innerHeight,rect.bottom,modalRect.bottom),left=Math.max(0,rect.left,modalRect.left),right=Math.min(innerWidth,rect.right,modalRect.right);
  const visible=bottom>top&&right>left;
  // The portrait shares the game's canvas; clip it so the mission cannot leak through the dialog.
  for(const [edge,value] of Object.entries(visible?{top,right:innerWidth-right,bottom:innerHeight-bottom,left}:{top:innerHeight,right:0,bottom:0,left:0}))$('canvas').style.setProperty(`--operator-preview-${edge}`,`${value}px`);
  if(!visible){send({action:'preview_operator',profile:null},false);return;}
  send({action:'preview_operator',roster_id:customizationId,profile:normalizeOperatorLoadout(loadoutChoices[customizationId]||{}),rect:{x:rect.x,y:rect.y,width:rect.width,height:rect.height}},false);
}
function equipmentStatRows(choice,previous){
  const trait=ROSTER.find(unit=>unit.id===customizationId)?.trait||'',stats=deriveLoadoutStats(choice,{trait}),before=deriveLoadoutStats(previous||normalizeOperatorLoadout({weapon:choice.weapon}),{trait});
  const rows=[['accuracy',equipmentText('정지 명중률','Stationary accuracy'),100,1,'%'],['normal_moving_accuracy',equipmentText('보통 이동 명중률','Normal moving accuracy'),100,1,'%'],['range',equipmentText('유효 거리','Effective range'),1,1,'m'],['damage',equipmentText('기본 피해','Base damage'),1,0,''],['penetration',equipmentText('관통력','Penetration'),1,0,''],['interval',equipmentText('발사 간격','Fire interval'),1,2,'s'],['final_aim_time',equipmentText('조준 준비','Aim preparation'),1,2,'s'],['secondary_switch_time',equipmentText('권총 전환','Switch to sidearm'),1,2,'s'],['primary_switch_time',equipmentText('주무기 복귀','Return to primary'),1,2,'s'],['final_reload_time',equipmentText('재장전','Reload'),1,2,'s'],['ammo',equipmentText('장탄수','Magazine'),1,0,''],['sound',equipmentText('발사 소음 반경','Shot noise radius'),1,1,'m'],['length',equipmentText('총 길이','Weapon length'),1,2,'m'],['movement_multiplier',equipmentText('이동 속도','Move speed'),100,0,'%'],['action_multiplier',equipmentText('장비 조작 시간','Handling time'),100,0,'%'],['weight',equipmentText('전체 장비 무게','Total gear weight'),1,1,'kg']];
  return `<dl class="equipment-stats">${rows.map(([key,label,mult,digits,suffix])=>{const value=Number(stats[key]),old=Number(before[key]);if(!Number.isFinite(value))return '';const delta=(value-old)*mult;return `<div><dt>${label}</dt><dd><output data-stat="${key}">${(value*mult).toFixed(digits)}${suffix}</output>${Number.isFinite(delta)&&Math.abs(delta)>10**(-digits)/2?`<small class="stat-delta">${delta>0?'+':''}${delta.toFixed(digits)}${suffix}</small>`:''}</dd></div>`;}).join('')}</dl>`;
}
function armorCoverage(choice){
  const stats=deriveLoadoutStats(choice),panels=stats.armor?.panels||[];
  const regionLabels={torso:equipmentText('몸통','Torso'),chest:equipmentText('가슴','Chest'),head:equipmentText('머리','Head'),abdomen:equipmentText('복부','Abdomen'),arms:equipmentText('팔','Arms'),legs:equipmentText('다리','Legs')};
  const panelLabels={front:equipmentText('전면','Front'),back:equipmentText('후면','Back'),side:equipmentText('측면','Sides'),sides:equipmentText('측면','Sides'),soft:equipmentText('전 방향 연질 방호','All-around soft armor'),head:equipmentText('머리','Head')};
  const helmet=HELMETS.find(item=>item.id===choice.helmet),helmetOn=choice.helmet!=='none';
  return `<div id="armor-coverage" class="armor-coverage"><svg viewBox="0 0 86 130" role="img" aria-label="${equipmentText('몸통 패널과 머리 방호','Torso panels and head protection')}"><circle cx="43" cy="17" r="11" class="${helmetOn?'protected':''}"/><path d="M25 36 14 63 20 68 28 48 28 85 22 122 33 122 43 91 53 122 64 122 58 85 58 48 66 68 72 63 61 36Z"/><path d="M30 38H56V76H30Z" class="${panels.length?'protected':''}"/></svg><div><strong>${equipmentText('실제 보호 범위','Protection coverage')}</strong>${panels.length?panels.map(panel=>`<p>${escapeHTML(panelLabels[panel.panel]||panel.panel||'')}${Array.isArray(panel.arc)?` · ${panel.arc.join('…')}°`:''} · ${escapeHTML((panel.regions||[]).map(region=>regionLabels[region]||region).join(' / '))}</p>`).join(''):`<p>${equipmentText('방탄판 없음','No ballistic panels')}</p>`}<p>${equipmentText('머리','Head')} · ${escapeHTML(helmetOn?localize(helmet||{},'label'):equipmentText('헬멧 없음','No helmet'))}</p><small>${equipmentText('패널 밖 피격과 관통에는 보호가 줄어듭니다.','Hits outside panels and penetrating rounds reduce protection.')}</small></div></div>`;
}
function refreshEquipmentMenuLabels(){
  const labels=[['[data-door-mode="OPEN_AND_FLASH"]',equipmentText('문 열고 섬광탄 던지기','Open door and throw flashbang'),equipmentText('폭발 후 예약 경로 진행','Continue queued route after blast')],['#equipment-submenu [data-tool="stun"]',equipmentText('섬광탄 투척','Throw flashbang')],['#equipment-submenu [data-tool="camera"]',equipmentText('정찰 카메라','Scout camera')],['#switch-weapon',equipmentText('주무기 / 보조무기 전환','Switch primary / sidearm')]];
  for(const [selector,label,note] of labels){const node=document.querySelector(selector);if(!node)continue;node.querySelector('span').textContent=label;if(note&&node.querySelector('small'))node.querySelector('small').textContent=note;}
}
function availableShotgunBreaches(unit) {
  if(!unit)return 0;
  // New snapshots project queued switches/reloads and consumed attempts in
  // the simulation. Legacy snapshots only expose the currently held weapon.
  if(Object.hasOwn(unit,'available_shotgun_breaches'))return Number.isInteger(unit.available_shotgun_breaches)?Math.max(0,unit.available_shotgun_breaches):0;
  if((unit.active_weapon||'primary')!=='primary'||(unit.current_weapon||unit.weapon)!=='shotgun')return 0;
  const reserved=(unit.commands||[]).filter(command=>command.type==='SHOTGUN_BREACH'&&(command.state==='PENDING'||(['RUNNING','WAITING'].includes(command.state)&&command.phase==='APPROACH'))).length;
  return Math.max(0,(Number(unit.ammo)||0)-reserved);
}
function availableBreachCharges(unit) {
  if(!unit)return 0;
  if(Object.hasOwn(unit,'available_breaches'))return Number.isInteger(unit.available_breaches)?Math.max(0,unit.available_breaches):0;
  const initialPhases=['','APPROACH','KICK_RECOVER','BREACH_INSTALL'];
  const reserved=(unit.commands||[]).filter(command=>(command.type==='BREACH_DOOR'||(command.type==='KICK_DOOR'&&command.args?.fallback==='breach'))&&(command.state==='PENDING'||(['RUNNING','WAITING'].includes(command.state)&&initialPhases.includes(command.phase||'')))).length;
  return Math.max(0,(Number(unit.breaches)||0)-reserved);
}
function renderOperatorCustomizer(){
  const id=customizationId,unit=ROSTER.find(item=>item.id===id),choice=normalizeOperatorLoadout(loadoutChoices[id]||{}),appearance=choice.appearance||{};
  const colors=CATALOG.appearance.colors;
  const fields=[['sidearm',equipmentText('보조무기','Sidearm')],['armor',equipmentText('방어구','Armor')],['helmet',equipmentText('헬멧','Helmet')],['equipment',equipmentText('투척 · 진입 도구','Throwable · entry tool')]];
  const tool=EQUIPMENT.find(item=>item.id===profileTool(choice)),weapon=WEAPONS.find(item=>item.id===choice.weapon),stats=deriveLoadoutStats(choice,{trait:unit?.trait});
  return `<section class="operator-workbench" data-profile="${id}" aria-label="${equipmentText('개인 장비와 외형','Personal gear and appearance')}">
    <aside class="operator-preview-column">
      <figure class="weapon-showcase"><figcaption><span class="eyebrow">${equipmentText('장착한 주무기','Equipped primary')}</span><strong>${escapeHTML(localize(weapon||{},'label'))}</strong></figcaption>${equipmentPhoto(choice.weapon,localize(weapon||{},'label'),'eager')}<p>${escapeHTML(localize(weapon||{},'note'))}</p><div class="weapon-quick-stats"><span>${equipmentText('장탄','Magazine')} <b>${stats.ammo}</b></span><span>${equipmentText('거리','Range')} <b>${stats.range} m</b></span><span>${equipmentText('무게','Weight')} <b>${stats.weapon_weight.toFixed(1)} kg</b></span></div></figure>
      <div class="customizer-heading"><div><span class="eyebrow">${escapeHTML(appearance.callsign||id.toUpperCase())}</span><h3>${escapeHTML(rosterName(unit))}</h3></div><small>${escapeHTML(localize(unit||{},'label'))}</small></div>
      <div id="operator-preview" class="operator-preview" role="img" aria-label="${equipmentText('현재 장비를 착용한 대원 3D 미리보기','3D preview of operator with selected gear')}"><span>${equipmentText('현재 장비 · 3D 대원 미리보기','CURRENT LOADOUT · 3D OPERATOR')}</span></div>
    </aside>
    <div class="customization-controls">
      <div class="customization-toolbar"><div><span class="eyebrow">LOADOUT</span><h3>${equipmentText('장비 구성','Equipment')}</h3></div><div class="loadout-field preset-field"><span>${equipmentText('역할 프리셋','Role preset')}</span>${renderCycler(null,loadoutCyclerOptions('preset'),choice.preset,false,{loadout:id,slot:'preset'})}</div></div>
      <div class="primary-gear-field loadout-field"><span>${t('progress.weapon')} <small>${equipmentText('사진을 눌러 장착','Select a photo to equip')}</small></span>${renderCycler(null,loadoutCyclerOptions('weapon'),choice.weapon,false,{loadout:id,slot:'weapon',photos:true,gallery:true})}</div>
      <div class="customization-fields">${fields.map(([slot,label])=>`<div class="loadout-field"><span>${label}</span>${renderCycler(null,loadoutCyclerOptions(slot),profileSlotValue(choice,slot),false,{loadout:id,slot,photos:true})}</div>`).join('')}</div>
      <fieldset class="attachment-options"><legend>${equipmentText('부착물','Attachments')} <small>${equipmentText('조준기는 하나만 장착','One optic at a time')}</small></legend>${ATTACHMENTS.map(item=>`<button type="button" data-attachment="${escapeHTML(item.id)}"${item.weapons.includes(choice.weapon)?'':' disabled'} aria-pressed="${choice.attachments.includes(item.id)}" title="${escapeHTML(localize(item,'note')||localize(item,'description'))}">${equipmentPhoto(item.id,localize(item,'label'))}<strong><span>${choice.attachments.includes(item.id)?'✓':'+'}</span>${escapeHTML(localize(item,'label'))}</strong><small>${escapeHTML(localize(item,'note'))}</small></button>`).join('')}</fieldset>
      <div class="camera-tool"><button type="button" data-equipment-extra="probe_c1" aria-pressed="${Number(choice.equipment.probe_c1)>0}">${equipmentPhoto('probe_c1',equipmentText('프로브 C1 정찰 카메라','Probe C1 scout camera'))}<span><strong>${Number(choice.equipment.probe_c1)>0?'✓':'+'} ${equipmentText('프로브 C1 정찰 카메라','Probe C1 scout camera')}</strong><small>${equipmentText('닫힌 문 안쪽을 짧게 정찰합니다.','Briefly scouts through a closed door.')}</small></span><b>${Number(choice.equipment.probe_c1)>0?equipmentText('장착 중','Equipped'):equipmentText('장착','Equip')}</b></button></div>
      <p class="selected-tool-note">${tool?`${escapeHTML(localize(tool,'label'))} — ${escapeHTML(localize(tool,'note'))}`:equipmentText('선택한 투척·진입 도구 없음','No throwable or entry tool selected')}</p>
      <details class="performance-settings"><summary>${equipmentText('최종 성능 · 보호 범위','Performance · protection')}<small>${equipmentText('변경 전 장비와 비교','Compare with previous gear')}</small></summary><div class="stat-heading"><small>${equipmentText('건강·정지 기준 · 부상·거리·이동에 따라 달라짐','Healthy, stationary baseline · injury, distance and movement change results')}</small></div>${equipmentStatRows(choice,comparisonLoadouts.get(id))}${armorCoverage(choice)}</details>
      <details class="appearance-settings"${appearanceOpen.get(id)?' open':''}><summary>${equipmentText('이름 · 콜사인 · 색상 · 패치','Name · callsign · color · patch')} <small>${equipmentText('외형 전용','Cosmetic only')}</small></summary><div class="appearance-inputs">${[['name',equipmentText('이름','Name'),48],['callsign',equipmentText('콜사인','Callsign'),32]].map(([field,label,max])=>`<label>${label}<input data-appearance="${field}" maxlength="${max}" value="${escapeHTML(appearance[field]||'')}" placeholder="${field==='name'?escapeHTML(localize(unit||{},'name')):field==='callsign'?id.toUpperCase():'BREACH'}"></label>`).join('')}</div><div class="appearance-patches" role="group" aria-label="${equipmentText('패치','Patch')}">${CATALOG.appearance.patches.map(patch=>`<button type="button" data-appearance-patch="${patch}" aria-pressed="${appearance.patch===patch}">${patch.toUpperCase()}</button>`).join('')}</div><div class="appearance-colors" role="group" aria-label="${equipmentText('복장 색상','Uniform color')}">${colors.map(color=>`<button type="button" data-appearance-color="${color}" style="--swatch:${color}" aria-label="${color}" aria-pressed="${appearance.color===color}"></button>`).join('')}</div></details><div class="profile-save"><span id="profile-save-status" role="status">${escapeHTML(profileSaveStatus.get(id)||equipmentText('선택한 장비는 대원별로 저장됩니다.','Equipment is saved for this operator.'))}</span><button id="profile-save" class="secondary">${equipmentText('개인 설정 저장','Save operator profile')}</button></div>
    </div></section>`;
}
function renderSquad() {
  const previousWorkbench=document.querySelector('.operator-workbench'),previousAppearance=previousWorkbench?.querySelector('.appearance-settings');if(previousAppearance)appearanceOpen.set(previousWorkbench.dataset.profile,previousAppearance.open);
  const performanceOpen=previousWorkbench?.querySelector('.performance-settings')?.open;
  ensureSquad();if(!squadIds.includes(customizationId))customizationId=squadIds[0]||'';
  const available=new Set(availableRoster(campaign?.active&&!campaign.suspended?campaign:null).map(unit=>unit.id)),stars=unlockProfile.stars,scroll=$('modal').scrollTop,active=document.activeElement,focusRoot=active?.closest?.('[data-loadout]'),focus=focusRoot?{id:focusRoot.dataset.loadout,slot:focusRoot.dataset.slot}:null;
  const membersOpen=document.querySelector('.squad-members')?.open;
  showModal(t('progress.prepare'),'OPERATOR PREPARATION',`<div class="squad-selection"><div class="squad-selection-header"><span>${equipmentText('대원을 선택해 장비를 구성하세요.','Select an operator to configure their gear.')}</span><details class="squad-members"${membersOpen?' open':''}><summary>${equipmentText('분대 구성 변경','Edit squad')} <b>${squadIds.length} / ${Number(missions[selectedMission]?.units)||4}</b></summary><div class="squad-members-body"><p class="modal-intro">${t('progress.squad_intro',{max:Number(missions[selectedMission]?.units)||4})}</p><div class="squad-roster">${ROSTER.map(unit=>{const slot=squadIds.indexOf(unit.id),name=rosterName(unit),label=localize(unit,'label'),unavailable=available.has(unit.id)?'':t(campaign?.lost?.includes(unit.id)?'progress.lost':'progress.injured');return `<button type="button" class="operator-card" data-roster="${unit.id}" aria-pressed="${slot>=0}"${available.has(unit.id)?'':' disabled'} title="${escapeHTML(label+unavailable)}"><span class="operator-portrait-wrap"><span class="operator-portrait">${escapeHTML(name[0])}</span>${slot>=0?`<i class="slot-badge">${slot+1}</i>`:''}</span><strong>${escapeHTML(name)}</strong><small>${escapeHTML(label)}</small>${unavailable?`<small class="roster-unavailable">${escapeHTML(unavailable)}</small>`:''}</button>`;}).join('')}</div><p class="note">${t('progress.squad_stars',{stars})}</p></div></details></div><nav class="operator-tabs" aria-label="${equipmentText('개인 장비를 설정할 대원','Operator to customize')}">${squadIds.map((id,index)=>{const unit=ROSTER.find(item=>item.id===id),choice=normalizeOperatorLoadout(loadoutChoices[id]||{}),weapon=WEAPONS.find(item=>item.id===choice.weapon);return `<button type="button" class="customize-operator" data-customize="${id}" aria-pressed="${id===customizationId}"><span class="operator-tab-number">${String(index+1).padStart(2,'0')}</span><span><strong>${escapeHTML(rosterName(unit))}</strong><small>${escapeHTML(localize(weapon||{},'label'))}</small></span><span class="operator-tab-status">${id===customizationId?equipmentText('편집 중','Editing'):'→'}</span></button>`;}).join('')}</nav></div>${renderOperatorCustomizer()}<div class="dialog-footer"><span class="note">${t('progress.selected',{count:squadIds.length})} · ${equipmentText('장비는 대원별로 자동 저장됩니다.','Gear is saved automatically per operator.')}</span><button id="squad-done" class="primary">${t('progress.squad_done')}</button></div>`);
  $('modal').classList.add('squad-modal');if(performanceOpen)document.querySelector('.performance-settings').open=true;requestAnimationFrame(()=>{$('modal').scrollTop=scroll;if(focus)$(`modal-content`).querySelector(`[data-loadout="${focus.id}"][data-slot="${focus.slot}"] output`)?.focus({preventScroll:true});updateOperatorPreview();});
}
function renderCampaignScreen() {
  const body = $('campaign-body'); if (!body) return;
  body.innerHTML = `<p class="modal-intro">아홉 작전의 스턴·문 파괴 장약 재고를 공유합니다. 체력 30 이하로 종료한 대원은 다음 임무에 결장하며, 아이언맨에서는 행동 불능 대원이 영구 결장합니다.</p>${campaign ? `<p class="campaign-record">${campaign.active ? `${campaign.index + 1}/${campaignMissions(campaign).length} 진행 · 다음 ${campaign.mission}` : '캠페인 완료'} · 스턴 ${campaign.inventory.stun} · 장약 ${campaign.inventory.breach}<br>결장: ${campaign.injured.map(id => ROSTER.find(unit => unit.id === id)?.name || id).join(', ') || '없음'} / 손실: ${campaign.lost.map(id => ROSTER.find(unit => unit.id === id)?.name || id).join(', ') || '없음'}</p>` : ''}<div class="plan-options">${campaign?.active ? '<button id="continue-campaign"><strong>현재 캠페인 계속 →</strong><small>저장된 재고·명부로 다음 작전 준비</small></button>' : ''}<button id="new-campaign"><strong>새 캠페인</strong><small>스턴 16개 · 장약 8개 · 모든 대원 복귀</small></button><button id="new-ironman"><strong>아이언맨 캠페인</strong><small>손실 대원의 다음 투입 불가</small></button>${campaign?.active ? '<button id="leave-campaign"><strong>개별 작전으로 전환</strong><small>현재 캠페인은 저장됩니다.</small></button>' : ''}</div>`;
}
// --- RB: screen navigation (title / select / briefing / campaign) --------
function titleNavButtons() { return $$('#title-nav .title-nav-item'); }
function focusTitleNav(index) {
  const buttons = titleNavButtons(); if (!buttons.length) return;
  titleNavIndex = ((index % buttons.length) + buttons.length) % buttons.length;
  buttons.forEach((button, i) => button.classList.toggle('focused', i === titleNavIndex));
  buttons[titleNavIndex]?.focus({ preventScroll: true });
}
function showMenuScreen(name) {
  if (!MENU_SCREENS.includes(name)) return;
  menuScreen = name;
  for (const screen of MENU_SCREENS) { const el = $(`${screen}-screen`); if (el) el.hidden = screen !== name; }
  if (name === 'campaign') renderCampaignScreen();
  if (name === 'title') focusTitleNav(titleNavIndex);
  syncUiFocus();
  lastSafeArea='';scheduleSafeArea();setTimeout(scheduleSafeArea,220);
}
function handleTitleNav(action) {
  if (action === 'select' || action === 'title' || action === 'campaign') { showMenuScreen(action); return; }
  if (action === 'daily') { startDaily(); return; }
  if (action === 'editor') { openEditor(); return; }
}
function startDaily() {
  const operation=dailyOperation(undefined,CAMPAIGN_MISSIONS.filter(id=>missionAccess(id,unlockProfile).unlocked));selectedVariant=operation.variant;selectedDifficulty='normal';seedMode='custom';customSeed=operation.seed;selectedModifiers=new Set(operation.modifiers);selectedMission=operation.id;updateBrief();send({action:'preview',mission:selectedMission},false);toast(`${operation.date} 오늘의 작전 · 시드 ${operation.seed}`);showMenuScreen('briefing');
}
function roomDrillInputKey(){
  return JSON.stringify((roomDrillDraft?.order||[]).map(id=>{const unit=(state.units||[]).find(item=>item.id===id);return [id,unit?.hp,unit?.position,unit?.active_weapon,unit?.ammo,unit?.available_shotgun_breaches,unit?.available_breaches,unit?.stuns,(unit?.commands||[]).map(command=>[command.type,command.state,command.args])];}));
}
function roomDrillRequest(action='room_drill_preview'){
  if(!roomDrillDraft)return;
  roomDrillPreview={};roomDrillPending=1;roomDrillDraft.preview_id=`web-drill-${++roomDrillSequence}`;
  roomDrillDraft.input_key=roomDrillInputKey();
  if(!send({action,preview_id:roomDrillDraft.preview_id,door_id:roomDrillDraft.door_id,method:roomDrillDraft.method,order:[...roomDrillDraft.order],options:{append:true,signal:roomDrillDraft.signal,go_long:roomDrillDraft.go_long,operator_id:roomDrillDraft.operator_id,delay_ticks:roomDrillDraft.delay_ticks}},false))roomDrillPending=0;
  renderRoomDrill();
}
function openRoomDrill(door_id){
  closeFormation(false,false);send({action:'formation_preview',clear:true,preview_id:`web-formation-clear-${++formationSequence}`},false);
  const order=selectedOwnUnitIds(state);
  roomDrillDraft={door_id,order,method:'OPEN_DOOR',signal:'AUTO',go_long:false,operator_id:order[0]||'',delay_ticks:0};
  roomDrillPending=0;roomDrillPreview={};$('room-drill-panel').hidden=false;syncUiFocus();
  send({action:'input_focus',blocked:true},false);roomDrillRequest();
  $('room-drill-panel').querySelector('button[data-drill-method]:not(:disabled)')?.focus({preventScroll:true});
}
function closeRoomDrill(keepPreview=false){
  const wasOpen=!$('room-drill-panel').hidden;roomDrillDraft=null;roomDrillPending=0;roomDrillPreview={};lastRoomDrillHTML='';$('room-drill-panel').hidden=true;
  if(wasOpen&&!keepPreview)send({action:'room_drill_preview',clear:true,preview_id:`web-drill-clear-${++roomDrillSequence}`},false);
  syncUiFocus();if(wasOpen){send({action:'input_focus',blocked:domOverlayOpen()},false);if(!domOverlayOpen())$('canvas').focus({preventScroll:true});}
}
function renderRoomDrill(){
  if(!roomDrillDraft)return;
  const focused=document.activeElement,focusKey=['drillMethod','drillOperator','drillOrder','drillSignal'].find(key=>focused?.dataset?.[key]),focusValue=focusKey?focused.dataset[focusKey]:null,focusDirection=focused?.dataset?.direction,focusId=focused?.id;
  const draft=roomDrillDraft,units=new Map((state.units||[]).map(unit=>[unit.id,unit])),operator=units.get(draft.operator_id),preview=roomDrillPreview;
  const methods={OPEN_DOOR:'door.open',KICK_DOOR:'door.kick',OPEN_AND_FLASH:'drill.flash',SHOTGUN_BREACH:'door.shotgun',BREACH_DOOR:'equip.breach'};
  const order=draft.order.map((id,index)=>{const unit=units.get(id),slot=(preview.slots||[]).find(item=>item.unit_id===id);return `<div data-drill-unit="${escapeHTML(id)}"><b class="drill-number">${index+1}</b><strong>${escapeHTML(rosterName(unit))}</strong>${slot?.entry===false?`<small>${t('drill.guard')}</small>`:''}<button type="button" data-drill-operator="${escapeHTML(id)}" aria-pressed="${id===draft.operator_id}" title="${escapeHTML(t('drill.operator_label'))}">${t('drill.operator_short')}</button><button type="button" data-drill-order="${escapeHTML(id)}" data-direction="-1" aria-label="${escapeHTML(t('drill.order_up',{name:rosterName(unit)}))}"${index===0?' disabled':''}>↑</button><button type="button" data-drill-order="${escapeHTML(id)}" data-direction="1" aria-label="${escapeHTML(t('drill.order_down',{name:rosterName(unit)}))}"${index===draft.order.length-1?' disabled':''}>↓</button></div>`;}).join('');
  const html=`<p class="drill-intro">${t('drill.intro')}</p><fieldset><legend>${t('drill.method_label')}</legend><div class="drill-methods">${DRILL_METHODS.map(method=>{const unavailable=(method==='SHOTGUN_BREACH'&&availableShotgunBreaches(operator)===0)||(method==='BREACH_DOOR'&&availableBreachCharges(operator)===0);return `<button type="button" data-drill-method="${method}" aria-pressed="${method===draft.method}"${unavailable?' disabled':''}>${t(methods[method])}</button>`;}).join('')}</div></fieldset><fieldset><legend>${t('drill.order_label')}</legend><div id="drill-order">${order}</div></fieldset><fieldset><legend>${t('drill.signal_label')}</legend><div class="drill-signals">${['AUTO','A','B','C'].map(signal=>`<button type="button" data-drill-signal="${signal}" aria-pressed="${signal===draft.signal}">${signal==='AUTO'?t('drill.auto'):signal}</button>`).join('')}</div><p class="note">${t('drill.auto_note')}</p></fieldset><div class="drill-options"><button id="drill-go-long" type="button" aria-pressed="${draft.go_long}">${draft.go_long?'✓':'+'} ${t('drill.go_long')}</button><span id="drill-short" class="drill-short"${preview.short_room?'':' hidden'}>${t('drill.short')}</span></div><p class="note">${t('drill.go_long_note')}</p>${draft.method==='SHOTGUN_BREACH'?`<p class="note">${t('drill.shotgun_last')}</p>`:''}<div id="drill-preview-summary" class="drill-preview-summary">${preview.ok?`<strong>${escapeHTML(draft.door_id)} → ${escapeHTML(preview.room_id||'')}</strong><p>${t(preview.short_room?'drill.short_note':'drill.preview_note')}</p><div class="drill-preview-legend">${(preview.slots||[]).map(slot=>`<span><b class="drill-number">${slot.index}</b>${escapeHTML(rosterName(units.get(slot.unit_id)))} · ${t(slot.entry?'drill.entry_position':'drill.guard')}</span>`).join('')}</div><small>${t('drill.funnel_note')}</small>`:t('drill.preview_pending')}</div><p class="drill-doctrine-note">${t('drill.doctrine')}</p>`;
  const changed=html!==lastRoomDrillHTML;if(changed){$('drill-editor-content').innerHTML=html;lastRoomDrillHTML=html;}
  $('drill-preview-error').textContent=roomDrillPending?t('drill.preview_pending'):preview.ok?'':t(preview.message_key||'drill.roster');
  $('drill-commit').disabled=roomDrillPending>0||!preview.ok||state.mode!=='PLANNING';
  if(changed&&focusKey)[...$('drill-editor-content').querySelectorAll('button')].find(button=>button.dataset[focusKey]===focusValue&&button.dataset.direction===focusDirection)?.focus({preventScroll:true});
  else if(changed&&focusId==='drill-go-long')$('drill-go-long')?.focus({preventScroll:true});
}
function startFormationTool(){
  if(state.mode!=='PLANNING'||selectedOwnUnitIds(state).length<2)return;
  closeRoomDrill();closeFormation(false,false);closeContext();
  send({action:'room_drill_preview',clear:true,preview_id:`web-drill-clear-${++roomDrillSequence}`},false);
  send({action:'tool',tool:'formation'},false);$('canvas').focus({preventScroll:true});
}
function openFormation(target,order){
  const draft=formationDraftForTarget(state,target,order);if(!draft)return;
  closeRoomDrill();closeContext(false);formationDraft=draft;formationPreview={};formationPending=false;
  $('formation-panel').hidden=false;syncUiFocus();send({action:'input_focus',blocked:true},false);formationRequest();
  $('formation-panel').querySelector('[data-formation-kind]')?.focus({preventScroll:true});
}
function closeFormation(keepPreview=false,resetTool=true){
  const wasOpen=!$('formation-panel').hidden;formationDraft=null;formationPreview={};formationPending=false;lastFormationHTML='';$('formation-panel').hidden=true;
  if(!keepPreview&&(wasOpen||state.tool==='formation')){
    send({action:'formation_preview',clear:true,preview_id:`web-formation-clear-${++formationSequence}`},false);
    if(resetTool&&state.tool==='formation')send({action:'tool',tool:'select'},false);
  }
  syncUiFocus();if(wasOpen){send({action:'input_focus',blocked:domOverlayOpen()},false);if(!domOverlayOpen())$('canvas').focus({preventScroll:true});}
}
function formationRequest(action='formation_preview'){
  if(!formationDraft)return;
  formationPreview={};formationPending=true;formationDraft.preview_id=`web-formation-${++formationSequence}`;
  formationDraft.input_key=formationInputKey(state,formationDraft);
  if(!send({action,preview_id:formationDraft.preview_id,target:[...formationDraft.target],order:[...formationDraft.order],kind:formationDraft.kind,options:{append:true,signal:formationDraft.signal,delay_ticks:clampDrillDelay(formationDraft.delay_ticks)}},false))formationPending=false;
  renderFormation();
}
function renderFormation(){
  if(!formationDraft)return;
  const focused=document.activeElement,focusKey=['formationKind','formationOrder','formationSignal','formationDelay'].find(key=>focused?.dataset?.[key]!==undefined),focusValue=focusKey?focused.dataset[focusKey]:null,focusDirection=focused?.dataset?.direction;
  const draft=formationDraft,preview=formationPreview,units=new Map((state.units||[]).map(unit=>[unit.id,unit]));
  const policy=formationSignalPolicy(preview,catalog.get(state.mission)||{},state);
  const order=draft.order.map((id,index)=>{const unit=units.get(id),slot=(preview.slots||[]).find(item=>item.unit_id===id);return `<div data-formation-unit="${escapeHTML(id)}"><b class="drill-number">${index+1}</b><strong>${escapeHTML(rosterName(unit))}</strong>${slot?.stance?`<small>${t('formation.'+slot.stance)}</small>`:''}<button type="button" data-formation-order="${escapeHTML(id)}" data-direction="-1" aria-label="${escapeHTML(t('formation.order_up',{name:rosterName(unit)}))}"${index===0?' disabled':''}>↑</button><button type="button" data-formation-order="${escapeHTML(id)}" data-direction="1" aria-label="${escapeHTML(t('formation.order_down',{name:rosterName(unit)}))}"${index===draft.order.length-1?' disabled':''}>↓</button></div>`;}).join('');
  const kind=preview.resolved??preview.kind,width=Number(preview.corridor_width),recommendation=preview.recommended_kind||kind;
  const html=`<p class="drill-intro">${t('formation.intro')}</p><fieldset><legend>${t('formation.method')}</legend><div class="drill-methods">${FORMATION_KINDS.map(kind=>`<button type="button" data-formation-kind="${kind}" aria-pressed="${kind===draft.kind}"${kind==='T_JUNCTION'&&draft.order.length!==4?' disabled':''}>${t('formation.'+kind)}</button>`).join('')}</div><p class="note">${t('formation.'+draft.kind+'_note')}</p></fieldset><fieldset><legend>${t('formation.order')}</legend><div id="formation-order">${order}</div></fieldset><fieldset><legend>${t('drill.signal_label')}</legend><div class="drill-signals">${['AUTO','A','B','C'].map(signal=>`<button type="button" data-formation-signal="${signal}" aria-pressed="${signal===draft.signal}">${signal==='AUTO'?t('drill.auto'):signal}</button>`).join('')}</div><p class="note">${t('drill.auto_note')}</p></fieldset><div class="formation-delay"><span>${t('drill.delay_label')}</span><button type="button" data-formation-delay="-30" aria-label="${escapeHTML(t('formation.delay_less'))}"${draft.delay_ticks<=0?' disabled':''}>−</button><output id="formation-delay-value">${t('drill.delay_value',{seconds:(draft.delay_ticks/30).toFixed(1)})}</output><button type="button" data-formation-delay="30" aria-label="${escapeHTML(t('formation.delay_more'))}"${draft.delay_ticks>=3600?' disabled':''}>+</button><button type="button" data-formation-delay="reset"${draft.delay_ticks===0?' disabled':''}>${t('formation.delay_reset')}</button></div><p class="formation-delay-note">${t('formation.delay_note')}</p><div id="formation-preview-summary" class="drill-preview-summary">${preview.ok?`<strong>${t('formation.'+kind)}</strong>${recommendation&&Number.isFinite(width)?`<p>${t('formation.recommended',{kind:t('formation.'+recommendation),width:width.toFixed(2)})}</p>`:''}<div class="drill-preview-legend">${(preview.slots||[]).map(slot=>`<span><b class="drill-number">${slot.index}</b>${escapeHTML(rosterName(units.get(slot.unit_id)))} · ${t('formation.'+slot.stance)}</span>`).join('')}</div><small>${t('formation.preview_note')}</small>`:t('formation.preview_pending')}</div><p class="drill-intro"><strong>${t('noise.'+policy)}</strong> · ${t('noise.'+policy+'_note')}</p><p class="drill-doctrine-note">${t('formation.doctrine')}</p>`;
  const changed=html!==lastFormationHTML;if(changed){$('formation-editor-content').innerHTML=html;lastFormationHTML=html;}
  $('formation-preview-error').textContent=formationPending?t('formation.preview_pending'):preview.ok?'':t(preview.message_key||'formation.error.team');
  $('formation-commit').disabled=formationPending||!preview.ok||state.mode!=='PLANNING';
  if(changed&&focusKey)[...$('formation-editor-content').querySelectorAll('button')].find(button=>button.dataset[focusKey]===focusValue&&button.dataset.direction===focusDirection)?.focus({preventScroll:true});
}
function timelineCommand(unit,command,index){
  const editable=['PENDING','FAILED'].includes(command.state)||(['RUNNING','WAITING'].includes(command.state)&&['MOVE','FACE','WAIT','WAIT_FOR_SIGNAL'].includes(command.type));
  const unit_id=escapeHTML(unit.id),name=escapeHTML(commandNamesOf()[command.type]||command.type),selected=state.selected===unit.id&&Number(state.selected_command)===index;
  return `<div class="drill-command${selected?' selected-command':''}${command.state==='FAILED'?' failed':''}" title="${escapeHTML(commandDescription(command))}"><button type="button" data-select-command="${index}" data-command-unit="${unit_id}" aria-pressed="${selected}" aria-label="${escapeHTML(rosterName(unit))} ${index+1} ${name}">${icon(commandIcon[command.type]||'wait')}<span>${name}</span></button>${editable?`<div class="drill-command-edit"><button type="button" data-reorder="${index}" data-command-unit="${unit_id}" data-direction="-1" aria-label="${escapeHTML(t('drill.command_up'))}"${command.state!=='PENDING'||unit.commands[index-1]?.state!=='PENDING'?' disabled':''}>↑</button><button type="button" data-reorder="${index}" data-command-unit="${unit_id}" data-direction="1" aria-label="${escapeHTML(t('drill.command_down'))}"${command.state!=='PENDING'||unit.commands[index+1]?.state!=='PENDING'?' disabled':''}>↓</button><button type="button" data-remove="${index}" data-command-unit="${unit_id}" aria-label="${escapeHTML(t('drill.command_remove'))}">×</button></div>`:''}</div>`;
}
function renderDrillTimeline(){
  if(drillDelayDrag)return;
  const groups=roomDrillTimeline(state),selected=selectedOwnUnitIds(state);
  const group=groups.find(item=>item.id===drillTimelineGroup)||groups.at(-1);
  drillTimelineGroup=group?.id||'';
  const rows=group?.rows||(selected.length>=2?selected.map((id,index)=>({unit:(state.units||[]).find(unit=>unit.id===id),order:index+1,commands:[]})):[]);
  const visible=['PLANNING','EXECUTING'].includes(state.mode)&&rows.length>=2;
  // Keep the existing release-facing control directly accessible without
  // taking width from the eight tools when a group adds a header row.
  const facingRelease=$('unlock-facing');
  if(!visible&&facingRelease?.id==='unlock-facing')$('hotbar-controls').append(facingRelease);
  const panel=$('drill-timeline');if(panel.hidden===visible){panel.hidden=!visible;scheduleSafeArea();}
  if(!visible){lastDrillHTML='';return;}
  const delay=group?.delay_ticks||0,seconds=(delay/30).toFixed(1);
  const formationButton=selected.length>=2&&state.mode==='PLANNING'?`<button type="button" id="formation-tool" data-tool="formation" aria-pressed="${state.tool==='formation'}" title="${escapeHTML(t('formation.pick_target'))}">${t('formation.tool')}</button>`:'';
  const html=`<header><strong>${t('drill.timeline')}</strong>${formationButton}${group?`<button type="button" id="drill-group-next" title="${escapeHTML(t('drill.other_group'))}"${groups.length<2?' disabled':''}>${escapeHTML(group.door_id||group.id)} ${groups.length>1?'↻':''}</button><div class="drill-delay-control"><span>${t('drill.delay_label')}</span><button type="button" class="drill-delay-track" data-sync-delay="${escapeHTML(group.sync_id)}" role="slider" aria-label="${escapeHTML(t('drill.delay_label'))}" aria-valuemin="0" aria-valuemax="3600" aria-valuenow="${delay}" aria-valuetext="${escapeHTML(t('drill.delay_value',{seconds}))}" title="${escapeHTML(t('drill.delay_hint'))}"${!group.editable||state.mode!=='PLANNING'?' disabled':''}><i style="left:${delay/36}%"></i></button><output data-sync-output="${escapeHTML(group.sync_id)}">${t('drill.delay_value',{seconds})}</output></div>`:`<span>${t('drill.timeline_empty')}</span>`}<small>${t('drill.timeline_edit')}</small></header><div class="drill-timeline-grid"><div class="drill-timeline-head"><span>${t('drill.order_label')}</span>${DRILL_STAGES.map(stage=>`<span>${t('drill.stage.'+stage)}</span>`).join('')}</div>${rows.map(row=>`<div class="drill-timeline-row" data-drill-row="${escapeHTML(row.unit.id)}"><button type="button" data-drill-primary="${escapeHTML(row.unit.id)}"${row.order===null?' class="drill-unit-down" disabled':''} title="${escapeHTML(rosterName(row.unit)+(row.order===null?' · '+t('stat.incapacitated'):''))}"><b class="drill-number"${row.order===null?` aria-label="${escapeHTML(t('stat.incapacitated'))}"`:''}>${row.order??'×'}</b><span>${escapeHTML(rosterName(row.unit))}</span>${row.order===null?`<small>${t('stat.incapacitated')}</small>`:''}</button>${DRILL_STAGES.map(stage=>`<div class="drill-stage" data-drill-stage="${stage}">${row.commands.filter(({command})=>{const actual=command.args.drill.stage;return stage==='door'?['door','safe'].includes(actual):stage==='entry'?['entry','domination','guard','go_long'].includes(actual):actual===stage;}).map(({command,index})=>timelineCommand(row.unit,command,index)).join('')||'<span class="drill-stage-empty">—</span>'}</div>`).join('')}</div>`).join('')}</div>`;
  if(html!==lastDrillHTML){const active=document.activeElement,focus=active?.dataset?.syncDelay;panel.innerHTML=html;lastDrillHTML=html;if(focus)panel.querySelector('[data-sync-delay]')?.focus({preventScroll:true});scheduleSafeArea();}
  if(facingRelease?.id==='unlock-facing')panel.querySelector('header')?.append(facingRelease);
}
function updateDrillDelayHandle(handle,value){
  const ticks=clampDrillDelay(value),text=t('drill.delay_value',{seconds:(ticks/30).toFixed(1)});handle.setAttribute('aria-valuenow',String(ticks));handle.setAttribute('aria-valuetext',text);handle.querySelector('i').style.left=`${ticks/36}%`;handle.closest('.drill-delay-control').querySelector('output').textContent=text;return ticks;
}
function commitDrillDelay(handle,value){
  const ticks=updateDrillDelayHandle(handle,value);send({action:'sync_delay',sync_id:handle.dataset.syncDelay,delay_ticks:ticks},false);
}
function cancelDrillDelayDrag(){
  const drag=drillDelayDrag;if(!drag)return false;
  // Clear before releasing capture: its lostpointercapture event must not
  // cancel a later gesture or commit the temporary pointer preview value.
  drillDelayDrag=null;
  if(drag.handle.hasPointerCapture(drag.pointer))drag.handle.releasePointerCapture(drag.pointer);
  lastDrillHTML='';renderDrillTimeline();return true;
}
function closeContext(notify=true) {
  const hadContext=!!context,hadMenu=!!visibleSubmenu();context=null;$('context-popover').hidden=true;for(const name of ['door','equipment','secure']){$(`${name}-submenu`).hidden=true;$(`${name}-modes`).setAttribute('aria-expanded','false');}
  if(notify&&hadContext)send({action:'context_close'},false);
  if(engineReady&&!$('modal').open)send({action:'input_focus',blocked:false},false);
  if(notify&&(hadContext||hadMenu)&&!$('modal').open)$('canvas').focus({preventScroll:true});
}
function visibleSubmenu() {return ['door','equipment','secure'].map(name=>$(`${name}-submenu`)).find(menu=>!menu.hidden);}
function openSubmenu(name,button) {const wasOpen=!$(`${name}-submenu`).hidden;closeContext();if(wasOpen)return;const menu=$(`${name}-submenu`),rect=button.getBoundingClientRect();menu.hidden=false;menu.style.left=`${Math.max(8,Math.min(innerWidth-menu.offsetWidth-8,rect.left))}px`;menu.style.top=`${Math.max(8,rect.top-menu.offsetHeight-8)}px`;button.setAttribute('aria-expanded','true');send({action:'input_focus',blocked:true},false);menu.querySelector('button:not(:disabled)')?.focus({preventScroll:true});}
function contextAction(action) {
  const item=typeof action==='object'?action:{type:action};let type=item.type||item.action,args={...(context?.args||{}),...(item.args||{})};
  if(type==='KICK_DOOR'&&item.door_fallback==='breach')args.fallback='breach';
  if(/^WAIT_\d+$/.test(type)){args.duration=Number(type.split('_')[1]);type='WAIT';}
  if(/^WAIT_FOR_SIGNAL_[ABC]$/.test(type)){args.signal=type.slice(-1);type='WAIT_FOR_SIGNAL';}
  if(context?.target==='door')args.door_id=context.id;
  if(context?.target==='civilian')args.civilian_id=context.id;
  if(context?.target==='enemy')args.enemy_id=context.id;
  if(context?.point&&!args.target&&['FACE','MOVE','THROW_STUN','THROW_SMOKE','THROW_FRAG'].includes(type))args.target=context.point;
  if(type==='ESCORT')type='ESCORT_CIVILIAN';
  return {type,args};
}
function contextLabel(action) {
  if((typeof action==='object'?action.type:action)==='ENTER_ROOM')return t('drill.title');
  if((typeof action==='object'?action.type:action)==='SHOTGUN_BREACH')return t('command.shotgun_breach');
  if(typeof action==='object'&&action.type==='KICK_DOOR'&&(action.args?.fallback==='breach'||action.door_fallback==='breach'))return t('door.kick_breach');
  if(typeof action==='object'&&action.label)return action.label;
  const type=typeof action==='object'?action.type:action;
  if(/^WAIT_\d+$/.test(type))return `${type.split('_')[1]}${equipmentText('초 대기','s wait')}`;
  if(/^WAIT_FOR_SIGNAL_[ABC]$/.test(type))return `${type.slice(-1)} ${equipmentText('신호 대기','wait for signal')}`;
  return {DELETE_NODE:equipmentText('노드 삭제','Delete node'),DELETE:equipmentText('노드 삭제','Delete node'),REMOVE:equipmentText('노드 삭제','Delete node'),ESCORT:equipmentText('민간인 호송','Escort civilian')}[type]||commandNamesOf()[type]||type;
}
function openContext(message) {
  if(state.mode==='REPLAY')return;closeContext(false);context=message;
  const names=getLanguage()==='en'?{door:'Door',civilian:'Civilian',unit:'Operator',enemy:'Surrendered hostile',waypoint:'Waypoint',ground:'Ground'}:{door:'문',civilian:'민간인',unit:'대원',enemy:'투항 적',waypoint:'경유점',ground:'바닥'};
  const structure=message.target==='door'?doorStructureLines(message.door_info):[];
  $('context-popover').innerHTML=`<p>${names[message.target]||'지도 행동'} · ${escapeHTML(message.id||message.unit_id||'')}</p>${structure.length?`<div class="door-structure" data-door-structure>${structure.map(line=>`<p>${escapeHTML(line)}</p>`).join('')}<small>${t('door.rifle_single_wall')}</small></div>`:''}${(message.actions||[]).map((action,index)=>{const type=typeof action==='object'?action.type:action,reason=message.disabled?.[type]||(typeof action==='object'?action.disabled:'');return `<button role="menuitem" data-context-index="${index}"${reason?' disabled':''} title="${escapeHTML(reason||contextLabel(action))}"><kbd>${index+1}</kbd><span>${escapeHTML(contextLabel(action))}</span>${reason?`<small>${escapeHTML(reason)}</small>`:''}</button>`;}).join('')}`;
  $('context-popover').hidden=false;const [x,y]=message.screen||[innerWidth/2,innerHeight/2],rect=$('context-popover').getBoundingClientRect();
  $('context-popover').style.left=`${Math.max(8,Math.min(innerWidth-rect.width-8,x))}px`;$('context-popover').style.top=`${Math.max(8,Math.min(innerHeight-rect.height-8,y))}px`;
  send({action:'input_focus',blocked:true},false);$('context-popover').querySelector('button:not(:disabled)')?.focus({preventScroll:true});
}
function chooseContext(index) {
  const action=context?.actions?.[index];if(!action)return;const rawType=typeof action==='object'?action.type:action;if(context.disabled?.[rawType]||action.disabled)return;
  const {type,args}=contextAction(action),target=context.target,unit_id=context.unit_id,indexValue=context.index,origin=context.point;
  closeContext(false);
  if(type==='ENTER_ROOM'){openRoomDrill(args.door_id);return;}
  if(['DELETE_NODE','DELETE','REMOVE'].includes(type)){send({action:'remove',unit_id,index:indexValue});return;}
  if(target==='waypoint'&&type==='FACE'){send({action:'tool',tool:'face',unit_id,index:Number(indexValue)+1,origin});return;}
  if(target==='waypoint'){send({action:'insert',unit_id,index:Number(indexValue)+1,type,args});return;}
  send({action:'command',unit_id,type,args});
}
function renderEditorTemplatePicker() {
  if(currentModal!=='editor')return;
  $('editor-template-row')?.remove();const row=document.createElement('label');row.id='editor-template-row';row.className='editor-template-row';row.innerHTML=`맵 템플릿 <select id="editor-template"><option value="">새 지도</option>${[...editorTemplates].map(([id,data])=>`<option value="${escapeHTML(id)}">${escapeHTML(data.title||id)} (${escapeHTML(id)})</option>`).join('')}</select><small>템플릿은 사용자 맵으로 복사합니다.</small>`;$('modal-content').prepend(row);
}
function openEditor() {currentModal='editor';editorController?.destroy();showModal('맵 에디터','LOCAL MAP WORKSHOP',renderMapEditor(createEditorMission()));editorController=bindMapEditor($('modal-content'),{onPlay:data=>{closeModal();send({action:'import_mission',data});},onExport:(data,name)=>downloadJSON(data,name),toast});renderEditorTemplatePicker();send({action:'editor_catalog'},false);}

function updateBrief() {
  renderProgressionSummary();
  const base=missionBase(selectedMission);if(!missions[selectedMission])missions[selectedMission]={...missions[base],name:`${missions[base]?.name||selectedMission} · ${VARIANTS.find(item=>item.id===selectedVariant)?.label||'작전'}`};
  renderMissionGrid();
  $('difficulty-note').textContent=t(selectedMission==='T01'?'difficulty.t01':selectedMission.endsWith('H')?'difficulty.challenge':'difficulty.normal');
  const mission=missions[selectedMission];$$('[data-mission]').forEach(button=>{const active=button.dataset.mission===base;button.classList.toggle('active',active);button.setAttribute('aria-selected',String(active));button.tabIndex=active?0:-1;});
  $('mission-detail').setAttribute('aria-labelledby',`tab-${base}`);$('brief-title').textContent=localize(mission,'title');$('brief-description').textContent=localize(mission,'description');
  const strengths=catalog.get(selectedMission)?.enemy_strengths;
  $('brief-enemy-strengths').hidden=!strengths||!Object.values(strengths).some(Boolean);
  $('brief-enemy-strengths').textContent=strengths?equipmentText(`적 전력 · 약 ${strengths.weak} / 중 ${strengths.medium} / 강 ${strengths.strong}`,`Enemy strength · Weak ${strengths.weak} / Medium ${strengths.medium} / Strong ${strengths.strong}`):'';
  const history=catalog.get(selectedMission)?.historical,historyBounds=catalog.get(selectedMission)?.bounds;
  const hasHistory=Boolean(history&&typeof history.location==='string'&&history.location.trim());
  $('historical-map-facts').hidden=!hasHistory;
  $('historical-map-facts').textContent=hasHistory?`${localize(history,'location')}\n${t('select.battlefield',{width:historyBounds?.[0],depth:historyBounds?.[1]})}\n${localize(history,'accuracy_note')||''}`:'';
  $('briefing-mission-name').textContent=localize(mission,'name');
  const family=cqbFamily(selectedMission);$('cqb-family-note').hidden=!family;
  $('cqb-family-note').textContent=family?t('cqb.family.'+family+'_title')+' · '+t('cqb.family.'+family+'_note'):'';
  const roe=missionRoe(catalog.get(selectedMission));
  const omittedFrag=roe==='precision'&&squadIds.some(id=>Number(loadoutChoices[id]?.equipment?.frag)>0);
  for(const prefix of ['select','briefing']){writeHTML(prefix+'-roe',roeBadge(catalog.get(selectedMission)));writeText(prefix+'-roe-note',t('roe.'+roe+'_note')+(omittedFrag?' '+t('roe.profile_preserved'):''));}
  $('brief-units').innerHTML=`${mission.units} <small>OPERATORS</small>`;$('brief-rooms').innerHTML=`${mission.rooms} <small>ROOMS</small>`;$('brief-time').innerHTML=`${mission.time} <small>MIN</small>`;
  const metadata=catalog.get(selectedMission),rules=rulesDescription(metadata);$('brief-objectives').innerHTML=(rules.length?rules:(getLanguage()==='en'&&mission.objectives_en)||mission.objectives).map(item=>`<li>${escapeHTML(item)}</li>`).join('');$('preview-map').textContent=`${mission.english} / ${selectedMission}`;const record=progress.get(selectedMission),stars=metadata?.stars||[],achieved=migrateMedals(record?.stars||record?.medals);$('mission-complete').hidden=!record?.completed;$('mission-complete').textContent=record?.completed?t('brief.complete_badge',{count:Object.values(achieved).filter(Boolean).length}):'';
  $('brief-stars').innerHTML=stars.map(star=>`<span class="${achieved[star.id]?'achieved':''}">${achieved[star.id]?'★':'☆'} ${escapeHTML((getLanguage()==='en'&&(star.label_en||(['course_time','arrest','reload_cover','team_damage'].includes(star.id)?t('star.'+star.id):STAR_LABELS_EN[star.id])))||star.label||star.id)}</span>`).join('');
  $('brief-record').textContent=record?.completed?t('brief.record',{score:record.bestScore||0,time:formatTime(record.bestTime),attempts:record.attempts||1}):t('brief.record_empty');renderBriefVariants();renderPreparation();
  const access=missionAccess(selectedMission,unlockProfile);$('mission-unlock-note').textContent=access.unlocked?t('progress.map_ready'):missionLockText(selectedMission);$('mission-unlock-note').classList.toggle('locked',!access.unlocked);$('select-to-briefing').disabled=!access.unlocked;$('start-mission').disabled=!engineReady||!access.unlocked;
}
function chooseMission(id){if(['M01_PRECISION','M01_HIGH_INTENSITY'].includes(id)){selectedVariant='standard';selectedDifficulty='normal';operationCollection='base';}else if(isCQBContentMission(id)){selectedVariant='standard';selectedDifficulty='normal';operationCollection='cqb';}else if(/^H\d{2}$/.test(missionBase(id))){selectedVariant='standard';selectedDifficulty='normal';operationCollection='history';}else if(missionBase(id)==='T01'||Number(missionBase(id).slice(1))>=4)selectedVariant='standard';id=missionId(id,selectedDifficulty,selectedVariant);selectedMission=id;updateBrief();if(engineReady)send({action:'menu_focus',data:{mission_id:id}},false);}
function nextMission(id){if(campaign?.active&&!campaign.suspended)return missionId(campaign.mission,selectedDifficulty,selectedVariant);const sequence=/^H\d{2}$/.test(missionBase(id))?[...catalog.keys()].filter(key=>/^H\d{2}$/.test(key)).sort():['T01',...CAMPAIGN_MISSIONS],index=sequence.indexOf(missionBase(id)),base=index>=0?sequence[index+1]:null;const next=base?missionId(base,selectedDifficulty,selectedVariant):null;return next&&missionAccess(next,unlockProfile).unlocked?next:null;}
function startMission(id=selectedMission,override=null){if(!engineReady)return;if(!checkProgression({...override,mission:id}))return;if(campaign?.active&&!campaign.suspended&&missionBase(id)!==campaign.mission){toast(`캠페인의 다음 작전은 ${campaign.mission}입니다.`,'warning');return;}selectedMission=id;updateBrief();const meta=override||preparationMeta(id);if(!checkProgression({...meta,mission:id}))return;const problem=checkCampaignLoadout(campaign?.suspended?null:campaign,meta.loadout||{});if(problem){toast(problem,'warning');renderSquad();return;}if((meta.roster||[]).length<1){toast('투입 가능한 대원이 부족합니다. 새 캠페인을 시작하거나 개별 작전을 선택하세요.','warning');return;}unlockAudio();closeModal();closePausePanel();closeContext();send({action:'ui_focus',data:{active:false},active:false},false);tutorialStep=0;tutorialClosed=false;seenEvents.clear();resultKey='';savedReplayKey='';campaignResultKey='';rewardedResultKey='';resultRewards=null;lastUnitHTML='';lastQueueHTML='';unitHitCount=new Map();resetReplayMarkers();if(send({action:'start',...meta,mission:id,id})&&seedMode==='random'&&!override)randomSeed=(globalThis.crypto.getRandomValues(new Uint32Array(1))[0]%2147483646)+1;}

function renderState() {
  const mode=state.mode||'MENU';const live=mode==='PLANNING'||mode==='EXECUTING';const mission=missions[state.mission]||missions.T01;
  if(roomDrillDraft&&(mode!=='PLANNING'||lastMission!==state.mission||JSON.stringify([...selectedOwnUnitIds(state)].sort())!==JSON.stringify([...roomDrillDraft.order].sort())))closeRoomDrill();
  if(formationDraft&&(mode!=='PLANNING'||formationDraft.mission!==state.mission||state.tool!=='formation'||JSON.stringify([...selectedOwnUnitIds(state)].sort())!==JSON.stringify([...formationDraft.order].sort())))closeFormation(false,false);
  const modeChanged=document.body.dataset.mode!==mode;
  if(!live&&context)closeContext();
  setHidden('motion-lab',mode!=='LAB');
  if(mode==='LAB'){$('lab-time').textContent=`${Number(state.time||0).toFixed(2)}초`;if(!$('lab-seek').matches(':active'))$('lab-seek').value=state.time||0;$('lab-toggle').textContent=state.playing?t('mode.paused'):t('lab.play');$('lab-scene').value=state.scene;$('lab-view').value=state.view;}
  setHidden('menu',mode!=='MENU');setHidden('hud',!live);setHidden('result',mode!=='RESULT');setHidden('replay-hud',mode!=='REPLAY'||!$('restore-hud').hidden);
  if(!live)$('cursor-hint').classList.remove('visible');
  if(mode!=='REPLAY')setHidden('restore-hud',true);
  const wasMenu=document.body.dataset.mode==='MENU';
  if(mode==='MENU'&&!wasMenu){updateBrief();showMenuScreen(menuScreen);}
  syncUiFocus();
  if(modeChanged){document.body.dataset.mode=mode;lastSafeArea='';lastToolKey='';scheduleSafeArea();if(mode!=='REPLAY'){replayScrubbing=false;replayScrubPointer=null;flushReplaySeek();}}
  if(mode==='REPLAY'&&!replayEntered){resetReplayMarkers();replayEntered=true;}else if(mode!=='REPLAY')replayEntered=false;
  if(mode!=='PLANNING'&&mode!=='EXECUTING')closePausePanel();
  if(live){
    if(lastMission!==state.mission){tutorialStep=0;tutorialClosed=false;lastMission=state.mission;seenEvents.clear();}
    writeText('hud-code',`${state.mission} / SEED ${state.seed??'—'}`);writeText('hud-mission',localize(mission,'name'));writeText('game-time',formatTime(state.time,true));
    const objectives=state.objectives||{};writeText('objective-threat',`${objectives.neutralized||0} / ${objectives.total||0}`);writeText('objective-civilian',`${objectives.rescued||0} / ${objectives.civilians_total||0}`);setHidden('civilian-objective',!objectives.civilians_total);
    setHidden('target-objective',!objectives.targets_total);writeText('objective-target',`${objectives.targets_completed||0} / ${objectives.targets_total||0}`);
    const nextTarget=(state.interactive_targets||[]).find(target=>!target.completed),targetTitle=nextTarget?`${nextTarget.label} · ${Number(nextTarget.progress||0).toFixed(1)} / ${nextTarget.duration}s`:'';if($('target-objective').title!==targetTitle)$('target-objective').title=targetTitle;writeText('objective-next',nextTarget?`${String((objectives.targets_completed||0)+1).padStart(2,'0')} · ${nextTarget.label}`:'모든 현장 목표 완료');
    const executing=mode==='EXECUTING',paused=!$('pause-panel').hidden;$('mode-pill').classList.toggle('executing',executing&&!paused);$('mode-pill').classList.toggle('paused',paused);writeHTML('mode-pill',`<span></span>${paused?t('mode.paused'):executing?t('mode.executing'):t('mode.planning')}`);
    writeText('mode-banner',executing?t('mode.banner_live'):t('mode.banner_planning'));
    $('toggle-execution').classList.toggle('executing',executing);writeHTML('toggle-execution',`<span>${icon(executing?'pause':'play')}</span><span><strong>${executing?t('execute.stop'):t('execute.go')}</strong><small>SPACE</small></span>`);
    renderUnits();renderCommands();renderTool();renderTutorial();renderLog();renderDrillTimeline();if(roomDrillDraft){if(roomDrillDraft.input_key!==roomDrillInputKey())roomDrillRequest();else renderRoomDrill();}
    if(formationDraft){if(formationDraft.input_key!==formationInputKey(state,formationDraft))formationRequest();else renderFormation();}
  }
  if(!live)renderDrillTimeline();
  renderPriorAttempt();
  if(mode==='REPLAY')renderReplay();
  if(mode==='RESULT')renderResult();
  applyDoctrineReplaySeek();
  if(planPendingLoad && mode==='PLANNING' && state.mission===(planPendingLoad.map_id||planPendingLoad.mission)){const plan=planPendingLoad;planPendingLoad=null;send({action:'load_plan',data:plan});}
}
function renderUnits() {
  const units=Array.isArray(state.units)?state.units:[];const colors=['#a1d6c3','#92b9e3','#d2bc87','#c2a5d4'];
  const now=performance.now();
  const html=units.map((unit,index)=>{
    const groupIds=selectedOwnUnitIds(state),selected=groupIds.includes(unit.id),primary=unit.id===state.selected;const hp=Math.max(0,Math.min(100,Number(unit.hp)||0));const down=hp<=0;const commands=unit.commands||[];const current=commands.find(command=>['RUNNING','WAITING','PENDING','FAILED'].includes(command.state));
    const activity=(getLanguage()==='en'?{ENGAGING:'Engaging',HOLD_FIRE:'Sightline blocked - holding',EMPTY:'Out of ammo - reload needed',RELOADING:'Reloading',AIMING:'Identifying and aiming',OUT_OF_AMMO:'No ammunition remaining',YIELDING:'Making room for teammate',OPENING:'Opening door',MOVING:'Moving',WAITING:'Waiting',BLOCKED:'Checking path'}:{ENGAGING:'대응 중',HOLD_FIRE:'사선이 막혀 대기',EMPTY:'탄창 소진 · 재장전 필요',RELOADING:'재장전 중',AIMING:'식별 · 조준 중',OUT_OF_AMMO:'모든 탄약 소진',YIELDING:'팀원에게 통로 양보',OPENING:'문 여는 중',MOVING:'이동 중',WAITING:'대기 중',BLOCKED:'이동 공간 확인 중'})[unit.status]||(unit.status==='COVERING_RELOAD'?t('team.covering_reload'):'');
    const statusReason=translateCommandReason(unit.status_reason),commandReason=translateCommandReason(current?.reason);
    const liveActivity=['READY','IDLE'].includes(unit.status)?'':(getLanguage()==='en'?(statusReason!==unit.status_reason?statusReason:activity):statusReason||activity);
    let status=down?t('stat.incapacitated'):unit.stunned>0?t('unit.stunned',{seconds:Number(unit.stunned).toFixed(1)}):current?.reason?(getLanguage()==='en'&&commandReason===current.reason?t('unit.command_failed'):commandReason):liveActivity|| (current?`${commandNamesOf()[current.type]||current.type} · ${commandStatesOf()[current.state]||''}`:t('unit.awaiting_command'));
    const prevHP=lastUnitHP.get(unit.id);if(prevHP!=null&&hp<prevHP-0.5){unitHitCount.set(unit.id,(unitHitCount.get(unit.id)||0)+1);}
    lastUnitHP.set(unit.id,hp);
    const hit=(hitFlash.get(unit.id)||0)>now;
    const pending=commands.filter(command=>command.state==='PENDING').length;
    const ROLE_EN={'선봉':'Point','엄호':'Cover','대원':'Operator','지원':'Support','돌입':'Breach'};
    const uname=rosterName(unit);
    const urole=(getLanguage()==='en'&&ROLE_EN[unit.role])||unit.role||(getLanguage()==='en'?'Operator':'대원');
    const initial=escapeHTML((uname||unit.id||'?').trim().slice(0,1).toUpperCase());
    const segments=Array.from({length:4},(_,i)=>`<i class="${hp>i*25?'filled':''}"></i>`).join('');
    return `<button class="unit-card${selected?' selected':''}${primary?' primary-selected':''}${down?' down':''}${hit?' hit-flash':''}" data-unit="${escapeHTML(unit.id)}" style="--unit-color:${colors[index%4]}" aria-pressed="${selected}" data-selection-order="${selected?groupIds.indexOf(unit.id)+1:0}" title="${escapeHTML(t('drill.select_hint'))}" aria-label="${index+1} ${escapeHTML(uname)}, HP ${Math.round(hp)}, ${escapeHTML(status)}"><span class="unit-portrait" aria-hidden="true">${initial}</span><span class="unit-main"><strong>${escapeHTML(uname)}</strong><small>${escapeHTML(urole)}</small></span><span class="unit-hp-segments" title="체력 ${Math.round(hp)}">${segments}</span><span class="unit-readout"><span title="${escapeHTML(t('posture.ammo'))}">${Number(unit.ammo)||0}<span style="opacity:.6"> + ${Number(unit.reserve_ammo)||0}</span></span>${[['stuns','스턴','◈'],['smokes','연막','☁'],['breaches','문 파괴 장약','▣']].filter(([field])=>Number(unit[field])>0).map(([field,label,mark])=>`<span title="${label}">${mark} ${Number(unit[field])}</span>`).join('')}</span><span class="unit-action" title="${escapeHTML(status)}">${current&&!down?icon(commandIcon[current.type]||'wait'):''}<b>${!down&&pending?pending:''}</b></span><span class="unit-status" title="${escapeHTML(status)}">${escapeHTML(status)}</span></button>`;
  }).join('');
  if(html!==lastUnitHTML){$('unit-cards').innerHTML=html;lastUnitHTML=html;}$('squad-count').textContent=String(units.length).padStart(2,'0');
  const selected=units.find(unit=>unit.id===state.selected);const disabled=!selected||selected.hp<=0;
  $$('.tools>button').forEach(button=>{if(!button.dataset.baseTitle)button.dataset.baseTitle=button.title;button.disabled=disabled;if(disabled)button.setAttribute('title',!selected?'먼저 대원을 선택하세요.':'행동 불능 대원은 명령을 수행할 수 없습니다.');else button.title=button.dataset.tool?(toolHints[button.dataset.tool]?.[0]||''):button.dataset.baseTitle;});
  $('operator-stance').disabled=disabled;$('operator-pace').disabled=disabled;$('operator-hold').disabled=disabled;
  $('operator-stance').value=selected?.stance||'standing';$('operator-pace').value=selected?.movement_mode||'normal';
  for(const [id,field] of [['operator-stance','stance'],['operator-pace','pace']]){const button=$(id),value=t('posture.'+button.value);writeText(id,`${value} ↻`);button.setAttribute('aria-label',t('posture.cycle_label',{field:t('posture.'+field),value}));}
  $('operator-hold').setAttribute('aria-pressed',String(!!selected?.hold_position));
  $('operator-awareness').textContent=selected?`${t('posture.'+(selected.injury_status||'none'))} · ${t('posture.'+(selected.awareness_state||'UNAWARE'))} · ${t('posture.'+(selected.aim_state||'idle'))}`:'';
  $('clear-commands').disabled=disabled;
  $$('#equipment-submenu [data-tool]').forEach(button=>{const frag=button.dataset.tool==='frag',count=button.dataset.tool==='breach'?availableBreachCharges(selected):frag?availableFrags(selected,{roe:runtimeRoe()}):Number(selected?.[{stun:'stuns',smoke:'smokes',camera:'cameras'}[button.dataset.tool]]||0);button.disabled=disabled||count<=0;button.title=frag?t(runtimeRoe()==='precision'?'roe.frag_prohibited':count<=0?'equipment.frag_required':'equipment.frag_stock',{count}):button.dataset.tool==='breach'?t(button.disabled?'door.charge_required':'door.charge_stock',{count}):count<=0?equipmentText('선택한 대원의 장비가 없습니다.','This operator does not have this tool.'):`${count} ${equipmentText('개 남음','available')}`;});
  $('switch-weapon').disabled=disabled||(!selected?.sidearm||selected.sidearm==='none');
  $('switch-weapon').title=selected?.active_weapon==='secondary'?equipmentText('주무기로 전환','Switch to primary'):equipmentText('보조권총으로 전환','Switch to sidearm');
  const flashDoor=document.querySelector('[data-door-mode="OPEN_AND_FLASH"]');flashDoor.disabled=disabled||Number(selected?.stuns)<=0||(state.modifiers||[]).includes('no_stun');flashDoor.title=flashDoor.disabled?equipmentText('섬광탄을 가진 행동 가능한 대원이 필요합니다.','Requires an active operator carrying a flashbang.'):equipmentText('문 개방 → 투척 → 폭발 대기','Open → throw → wait for blast');
  const shotgunDoor=document.querySelector('[data-door-mode="SHOTGUN_BREACH"]'),shotgunCount=availableShotgunBreaches(selected);
  shotgunDoor.disabled=disabled||shotgunCount<=0;shotgunDoor.title=t(shotgunDoor.disabled?'door.shotgun_required':'door.shotgun_stock',{count:shotgunCount});const shotgunNote=`${t('door.shotgun_sub')} · ${t('door.shotgun_stock',{count:shotgunCount})}`,shotgunNoteNode=shotgunDoor.querySelector('small');if(shotgunNoteNode.textContent!==shotgunNote)shotgunNoteNode.textContent=shotgunNote;
  const fallbackDoor=document.querySelector('[data-door-fallback="breach"]'),chargeCount=availableBreachCharges(selected);
  fallbackDoor.disabled=disabled||chargeCount<=0;fallbackDoor.title=t(fallbackDoor.disabled?'door.charge_required':'door.charge_stock',{count:chargeCount});const chargeNote=`${t('door.kick_breach_sub')} · ${t('door.charge_stock',{count:chargeCount})}`,chargeNoteNode=fallbackDoor.querySelector('small');if(chargeNoteNode.textContent!==chargeNote)chargeNoteNode.textContent=chargeNote;
  $$('#door-submenu [data-door-mode]').forEach(button=>{if(!['SHOTGUN_BREACH','OPEN_AND_FLASH'].includes(button.dataset.doorMode)&&!button.dataset.doorFallback)button.disabled=disabled;});
  $$('#secure-submenu [data-tool]').forEach(button=>button.disabled=disabled);
}
function commandDescription(command) {
  const args=command.args||{};
  if(command.type==='THROW_FRAG'&&['RUNNING','WAITING'].includes(command.state)&&['PREPARE','WAIT_EXPLOSION'].includes(command.phase))return `${t(command.phase==='PREPARE'?'frag.prepare':'frag.waiting')} · ${commandStatesOf()[command.state]||''}`;
  if(['KICK_RECOVER','SHOTGUN_PREPARE','BREACH_INSTALL','BREACH_RETREAT','BREACH_SAFE_WAIT','SHOTGUN_RETREAT'].includes(command.phase)&&['RUNNING','WAITING'].includes(command.state))return `${t('phase.'+command.phase)} · ${commandStatesOf()[command.state]||''}`;
  if(command.reason)return translateCommandReason(command.reason);
  if(command.type==='THROW_FRAG')return `${t('equipment.frag_note')} · ${commandStatesOf()[command.state]||''}${Array.isArray(args.target)?` · ${args.target.map(value=>Number(value).toFixed(1)).join(', ')}`:''}`;
  if(command.type==='KICK_DOOR'&&args.fallback==='breach')return `${t('command.kick_breach')} · ${commandStatesOf()[command.state]||''}`;
  if(command.type==='OPEN_AND_FLASH')return `${getLanguage()==='en'?'Open → throw → wait for blast':'개방 → 투척 → 폭발 대기'} · ${commandStatesOf()[command.state]||''}${Array.isArray(args.target)?` · ${args.target.map(value=>Number(value).toFixed(1)).join(', ')}`:''}`;
  if(command.type==='SWITCH_WEAPON')return `${args.slot==='secondary'?(getLanguage()==='en'?'Sidearm':'보조무기'):(getLanguage()==='en'?'Primary':'주무기')} · ${commandStatesOf()[command.state]||''}`;
  if(command.type==='PEEK_CAMERA')return `${getLanguage()==='en'?'Observe through this door; snapshots are remembered':'이 문을 정찰 · 과거 관측은 기억 정보로 표시'} · ${commandStatesOf()[command.state]||''}`;
  if(command.type==='FACE')return `${args.unlock?(getLanguage()==='en'?'Release facing':'주시 해제'):args.persistent?(getLanguage()==='en'?'Keep facing while moving':'이동 중 방향 유지'):(getLanguage()==='en'?'Released on next move':'다음 이동에서 해제')}${['standing','crouched'].includes(args.stance)?` · ${t('formation.'+args.stance)}`:''} · ${commandStatesOf()[command.state]||''}`;
  if(command.type==='WAIT')return `${Number(args.duration)||0}${getLanguage()==='en'?'s':'초'} · ${commandStatesOf()[command.state]||''}`;
  if(command.type==='WAIT_FOR_SIGNAL')return `${args.auto_signal?t('drill.auto'):args.signal||'A'} ${t('command.signal_suffix')}${args.drill?` · ${t('drill.stage.'+args.drill.stage)} · ${t('drill.delay_value',{seconds:(Number(args.delay_ticks||0)/30).toFixed(1)})}`:''}${args.formation?` · ${t('formation.'+args.formation.kind)} · ${t('drill.delay_value',{seconds:(Number(args.delay_ticks||0)/30).toFixed(1)})}`:''} · ${commandStatesOf()[command.state]||''}`;
  return commandStatesOf()[command.state]||t('cycler.fixed');
}
function renderCommands(){
  const selected=(state.units||[]).find(unit=>unit.id===state.selected);const commands=selected?.commands||[];$('queue-name').textContent=(selected?rosterName(selected):'')||selected?.name||t('queue.select_operator');$('queue-count').textContent=String(commands.filter(command=>!['SUCCEEDED','CANCELLED'].includes(command.state)).length);
  const html=commands.length?commands.map((command,index)=>{const canEdit=['PENDING','FAILED'].includes(command.state)||(['RUNNING','WAITING'].includes(command.state)&&['MOVE','FACE','WAIT','WAIT_FOR_SIGNAL','OPEN_DOOR','KICK_DOOR','PEEK_DOOR'].includes(command.type));const canUp=command.state==='PENDING'&&commands[index-1]?.state==='PENDING';const canDown=command.state==='PENDING'&&commands[index+1]?.state==='PENDING';return `<div class="command-row${['RUNNING','WAITING'].includes(command.state)?' running':''}${command.state==='FAILED'?' failed':''}${['SUCCEEDED','CANCELLED'].includes(command.state)?' done':''}${Number(state.selected_command)===index?' selected-command':''}" data-select-command="${index}" data-command-unit="${escapeHTML(selected.id)}" tabindex="0" role="button" aria-label="${index+1} ${escapeHTML(commandNamesOf()[command.type]||command.type)}"><span>${String(index+1).padStart(2,'0')}</span><div><strong>${escapeHTML(commandNamesOf()[command.type]||command.type)}</strong><small>${escapeHTML(commandDescription(command))}</small></div><div class="queue-row-buttons">${command.type==='OPEN_AND_FLASH'&&command.state==='PENDING'?`<button data-flash-target="${index}" title="${equipmentText('지도에서 투척 지점 조정','Adjust landing point on map')}" aria-label="${equipmentText('섬광탄 투척 지점 조정','Adjust flashbang landing point')}">⌖</button>`:''}${canEdit?`<button data-reorder="${index}" data-direction="-1" title="명령 위로" aria-label="${index+1}번 명령 위로"${!canUp?' disabled':''}>↑</button><button data-reorder="${index}" data-direction="1" title="명령 아래로" aria-label="${index+1}번 명령 아래로"${!canDown?' disabled':''}>↓</button><button data-remove="${index}" title="명령 삭제" aria-label="${index+1}번 명령 삭제">×</button>`:''}</div></div>`;}).join(''):`<div class="empty-state">${selected?t('queue.empty_selected'):t('queue.empty_unselected')}</div>`;
  if(html!==lastQueueHTML){$('command-list').innerHTML=html;lastQueueHTML=html;}
}
let lastToolKey='',lastTutorialKey='';
const toolButtons=$$('[data-tool]'),faceButtons=$$('[data-face-mode]'),speedButtons=$$('[data-speed]'),revealButtons=$$('#replay-view-group [data-reveal]');
function renderTool(){
  refreshEquipmentMenuLabels();
  const tool=state.tool||'select',selected=(state.units||[]).find(unit=>unit.id===state.selected);
  const key=JSON.stringify([tool,state.door_mode,state.door_fallback,state.selected,!selected||selected.hp<=0,selected?.facing_locked,selected?.facing_persistent,getLanguage(),window.innerWidth,window.innerHeight]);
  if(key===lastToolKey)return;lastToolKey=key;
  $('canvas').classList.toggle('camera-pan-tool',tool==='pan');toolButtons.forEach(button=>{const active=button.dataset.tool===tool||(button.dataset.tool==='face'&&tool==='face_lock');button.classList.toggle('active',active);setPressed(button,active);});
  $$('#door-submenu [data-door-mode]').forEach(button=>{const active=tool==='door'&&button.dataset.doorMode===(state.door_mode||'OPEN_DOOR')&&(button.dataset.doorFallback||'')===(state.door_fallback||'');button.classList.toggle('active',active);setPressed(button,active);});
  const hints=getLanguage()==='en'?toolHints_en:toolHints;let hint=hints[tool]||hints.select;if(tool==='formation')hint=[t('formation.pick_target'),'CLICK'];else if(tool==='frag')hint=[t('equipment.frag_hint'),'CLICK'];else if(tool==='door'&&state.door_mode==='SHOTGUN_BREACH')hint=[t('door.shotgun_hint'),'CLICK'];else if(tool==='door'&&state.door_mode==='KICK_DOOR'&&state.door_fallback==='breach')hint=[t('door.kick_breach_hint'),'CLICK'];$('world-hint-text').textContent=hint[0];$('world-hint-key').textContent=hint[1];
  $('cursor-hint-text').textContent=hint[0];$('cursor-hint-key').textContent=hint[1];
  for(const [name,tools] of [['door',['door']],['equipment',['stun','smoke','breach','camera','flash_target','frag']],['secure',['secure','escort','arrest']]])$(`${name}-modes`).classList.toggle('submenu-active',tools.includes(tool));
  const faceOptions=$('face-options');faceOptions.hidden=!['face','face_lock'].includes(tool)||!selected||selected.hp<=0;
  if(!faceOptions.hidden){const rect=document.querySelector('[data-tool="face"]').getBoundingClientRect();faceOptions.style.left=`${Math.max(8,Math.min(innerWidth-faceOptions.offsetWidth-8,rect.left))}px`;faceOptions.style.top=`${Math.max(8,rect.top-faceOptions.offsetHeight-8)}px`;}
  faceButtons.forEach(button=>setPressed(button,(button.dataset.faceMode==='persistent')===(tool==='face_lock')));
  if(selected?.facing_locked){if(!$('unlock-facing')){const button=document.createElement('button');button.id='unlock-facing';button.className='unlock-facing';button.addEventListener('click',()=>send({action:'unlock_facing'}));$('hotbar-controls').append(button);}const button=$('unlock-facing');button.textContent=getLanguage()==='en'?'Release facing':selected.facing_persistent?'주시 고정 해제':'주시 해제';button.title=getLanguage()==='en'?'Follow movement direction':'이동 방향을 따라 주시하도록 변경';}else $('unlock-facing')?.remove();
}
function renderTutorial(){
  setHidden('tutorial',state.mission!=='T01'||tutorialClosed);if($('tutorial').hidden)return;
  const commands=(state.units||[]).flatMap(unit=>unit.commands||[]);
  if(tutorialStep===0&&state.selected)tutorialStep=1;
  if(tutorialStep===1&&commands.some(command=>command.type==='MOVE'))tutorialStep=2;
  if(tutorialStep===2&&state.time>1)tutorialStep=3;
  if(tutorialStep===3&&(state.doors||[]).some(door=>door.state==='OPEN'))tutorialStep=4;
  if(tutorialStep===4&&commands.some(command=>command.type==='FACE'))tutorialStep=5;
  const key=`${tutorialStep}:${getLanguage()}`;if(key===lastTutorialKey)return;lastTutorialKey=key;
  const tutorial=(getLanguage()==='en'?tutorials_en:tutorials)[tutorialStep];$('tutorial-number').textContent=`${String(tutorialStep+1).padStart(2,'0')} / 06`;$('tutorial-progress').style.width=`${(tutorialStep+1)/6*100}%`;$('tutorial-title').textContent=tutorial.title;$('tutorial-description').textContent=tutorial.description;$('tutorial-key').textContent=tutorial.key;$('tutorial-next').textContent=tutorialStep===5?t('tutorial.collapse'):t('tutorial.next');
}
function renderLog(){
  const now=performance.now();
  const events=(state.events||[]).filter(event=>(event.message||/^CALL_/.test(event.type||''))&&(!/shot|shoot|step|move/i.test(event.type||''))).slice(-8);
  const own=new Map((state.units||[]).map(unit=>[unit.id,unit])),rooms=Array.isArray(catalog.get(state.mission)?.rooms)?catalog.get(state.mission).rooms:[];
  const observed=observedRoomStates(state,rooms),roomById=new Map(rooms.map(room=>[room.id,room]));
  const unitName=id=>{const unit=own.get(id);return unit?localize(ROSTER.find(r=>r.id===(unit.roster_id||unit.id))||unit,'name')||unit.name||unit.id:id;};
  const evCtx={missionName:localize(missions[state.mission]||{},'name'),unitName,ownUnitName:id=>own.has(id)?unitName(id):'',observedRoomName:id=>Object.hasOwn(observed,id)?localize(roomById.get(id),'label')||id:''};
  const seenKeys=new Set();
  const html=events.map(event=>{
    const message=translateEvent(event,evCtx);if(!message)return '';
    const key=`${event.time}|${event.message}`;seenKeys.add(key);
    if(!logSeen.has(key))logSeen.set(key,now);
    const age=(now-logSeen.get(key))/1000;
    const type=event.type||'';
    const category=/enemy|contact/i.test(type)?'threat':/hit|down/i.test(type)?'danger':/civilian/i.test(type)?'civ':/clear|neutral/i.test(type)?'success':/door|breach|stun|smoke/i.test(type)?'action':'info';
    const glyph={threat:'⌖',danger:'✕',civ:'◇',success:'✓',action:'▣',info:'·'}[category];
    return `<div class="log-entry ${category}${age<.4?' entering':''}${age>8?' fading':''}"><i class="log-glyph" aria-hidden="true">${glyph}</i><time>${formatTime(event.time)}</time><span>${escapeHTML(message)}</span></div>`;
  }).join('');
  if(html!==lastLogHTML){$('operation-log').innerHTML=html;lastLogHTML=html;}
  $('operation-log').hidden=!settings.enemy_alerts;
  if(logSeen.size>60)for(const key of logSeen.keys())if(!seenKeys.has(key))logSeen.delete(key);
}
let pendingReplaySeek=null,replaySeekFrame=null,replayScrubbing=false,replayScrubPointer=null;
let pendingDoctrineSeek=null;
function requestDoctrineReplay(tick){
  const intent=doctrineReplaySeek(state,tick);if(!intent)return false;
  if(state.mode==='REPLAY'){pendingDoctrineSeek=null;flushReplaySeek();send({action:'pause'},false);send(intent,false);}
  else{const start=!pendingDoctrineSeek;pendingDoctrineSeek={mission:state.mission,seed:state.seed,tick};if(start)send({action:'replay'});}
  return true;
}
function applyDoctrineReplaySeek(){
  if(!pendingDoctrineSeek)return;
  if(state.mission!==pendingDoctrineSeek.mission||state.seed!==pendingDoctrineSeek.seed||!['RESULT','REPLAY'].includes(state.mode)){pendingDoctrineSeek=null;return;}
  if(state.mode!=='REPLAY')return;
  const intent=doctrineReplaySeek(state,pendingDoctrineSeek.tick);pendingDoctrineSeek=null;
  if(intent){flushReplaySeek();send({action:'pause'},false);send(intent,false);}
}
function renderPriorAttempt(){
  const presentation=priorAttemptPresentation(state),button=$('prior-attempt-toggle');
  button.hidden=!presentation.available;setPressed(button,presentation.visible);
}
function togglePriorAttempt(){
  const presentation=priorAttemptPresentation(state);
  if(presentation.available)send({action:'prior_attempt_visible',value:!presentation.visible},false);
}
function flushReplaySeek(){
  if(replaySeekFrame!==null){cancelAnimationFrame(replaySeekFrame);replaySeekFrame=null;}
  if(pendingReplaySeek===null)return;
  const time=pendingReplaySeek;pendingReplaySeek=null;if(state.mode==='REPLAY')send({action:'replay_seek',time},false);
}
function queueReplaySeek(time){pendingReplaySeek=time;if(replaySeekFrame===null)replaySeekFrame=requestAnimationFrame(flushReplaySeek);}
function renderReplay(){
  const replay=state.replay||{},seek=hudNode('replay-seek');
  writeText('replay-time',formatTime(replayScrubbing||pendingReplaySeek!==null?seek.value:replay.time));writeText('replay-duration',formatTime(replay.duration));
  const max=String(Math.max(.05,Number(replay.duration)||0));if(seek.max!==max)seek.max=max;
  if(!replayScrubbing&&pendingReplaySeek===null&&!seek.matches(':active'))seek.value=String(replay.time||0);
  writeHTML('replay-toggle',icon(replay.playing?'pause':'play'));
  const label=getLanguage()==='en'?(replay.playing?'Pause replay':'Play replay'):(replay.playing?'리플레이 일시정지':'리플레이 재생');if($('replay-toggle').getAttribute('aria-label')!==label)$('replay-toggle').setAttribute('aria-label',label);
  speedButtons.forEach(button=>button.classList.toggle('active',Number(button.dataset.speed)===Number(replay.speed||1)));
  revealButtons.forEach(button=>setPressed(button,button.dataset.reveal===String(Boolean(replay.reveal))));
  setHidden('replay-partial',replay.complete!==false);writeText('replay-mission',`${state.mission} / ${localize(missions[state.mission]||{},'name')||t('replay.title')}`);
  const html=`<option value="">${t('replay.free')}</option>`+(state.units||[]).map(unit=>`<option value="${escapeHTML(unit.id)}">${escapeHTML(unit.name||unit.id)} ${getLanguage()==='en'?'follow':'따라가기'}</option>`).join('');
  if(html!==lastReplayFollow){$('replay-follow').innerHTML=html;lastReplayFollow=html;}if(document.activeElement!==$('replay-follow'))$('replay-follow').value=replay.follow||'';
  renderReplayMarkers();
}
export function resultStatistics(snapshot={}){
  const result=snapshot.result||{},units=Array.isArray(snapshot.units)?snapshot.units:[],objectives=snapshot.objectives||{};
  const stats=[[t('stat.time'),formatTime(snapshot.time)],[t('stat.survivors'),`${units.filter(unit=>unit.hp>0).length} / ${units.length}`],[t('stat.threats'),`${objectives.neutralized||0} / ${objectives.total||0}`],[t('stat.civilians'),objectives.civilians_total?`${objectives.rescued||0} / ${objectives.civilians_total}`:'—'],[t('stat.failed_cmds'),String(result.command_failures??result.failed_commands??0)],[t('stat.plan_revisions'),String(result.plan_revisions??result.plan_changes??result.planning_changes??0)],[t('stat.stuns'),String(result.stuns_used??0)],[t('stat.reloads'),String(result.reloads??0)],[t('stat.hits'),String(result.hits_taken??0)],[t('stat.rear_hits'),String(result.rear_hits??0)],[t('stat.deployed'),String(result.units_deployed??units.length)],[t('stat.first_alert'),result.first_alert_time>=0?formatTime(result.first_alert_time):t('stat.none')],[t('stat.arrests_kills'),`${result.arrests??0} / ${result.kills??0}`],[t('stat.shots_losses'),`${result.shots_fired??0} / ${result.losses??0}`]];
  if(result.unlawful_shots)stats.push([t('stat.unlawful_shots'),String(result.unlawful_shots)]);
  return stats;
}
export function roomDoctrineMarkup(report=[],snapshot={}){
  if(!Array.isArray(report)||!report.length)return `<p class="note">${escapeHTML(t('debrief.unavailable'))}</p>`;
  const measurement=row=>{
    if(row.grade==='na'||!Number.isFinite(row.value))return t('debrief.na');
    if(row.id==='stealth')return t('debrief.stealth.'+row.value);
    if(['doorway_dwell','time_to_dominate'].includes(row.id))return t('debrief.seconds',{seconds:row.value.toFixed(2)});
    if(row.id==='identification')return t('debrief.identification_value',{damage:row.details.civilian_damage.toFixed(2),shots:row.details.unlawful_shots});
    if(row.id==='control')return t('debrief.control_value',row.details);
    if(row.id==='marked')return `${(row.value*100).toFixed(0)}%`;
    return String(row.value);
  };
  return report.map(room=>`<section class="doctrine-room" data-doctrine-room="${escapeHTML(room.id)}"><h3>${escapeHTML(getLanguage()==='en'?(room.label_en||room.id):room.label)}</h3><table class="doctrine-table"><thead><tr>${['item','grade','measurement','doctrine'].map(key=>`<th scope="col">${t('debrief.'+key)}</th>`).join('')}</tr></thead><tbody>${room.rows.map(row=>{
    const seek=row.grade==='fail'&&doctrineReplaySeek(snapshot,row.tick)?`<button type="button" class="doctrine-seek" data-doctrine-tick="${row.tick}" title="${escapeHTML(t('debrief.tick',{tick:row.tick}))}">${escapeHTML(t('debrief.replay',{time:formatTime(row.tick/30)}))}</button>`:'';
    const rate=value=>typeof value==='number'&&Number.isFinite(value)?(value*100).toFixed(0):t('debrief.na');
    const rates=row.id==='control'&&row.grade!=='na'?`<small>${escapeHTML(t('debrief.control_rates',{arrest:rate(row.details.arrest_rate),secure:rate(row.details.secure_rate)}))}</small>`:'';
    return `<tr data-doctrine-metric="${row.id}"><th scope="row">${t('debrief.'+row.id)}</th><td class="doctrine-grade ${row.grade}">${t('debrief.'+row.grade)}</td><td>${escapeHTML(measurement(row))}${rates}${seek}</td><td>${t('debrief.'+row.id+'_note')}</td></tr>`;
  }).join('')}</tbody></table></section>`).join('');
}
function renderRoomDoctrine(){
  // A legacy result has no observation/measurement records. Avoid consulting
  // the authored catalog to invent an unobserved room list in that case.
  const report=state.room_states?roomDoctrineReport(state,catalog.get(state.mission)?.rooms||[],gradeRoomDoctrine):[];
  $('result-doctrine-rooms').innerHTML=roomDoctrineMarkup(report,state);
}
function renderCompetition(){
  const node=$('result-competition');node.hidden=!/^SH(?:0[1-4]|05_(?:PRECISION|HIGH_INTENSITY))$/.test(state.mission);
  if(node.hidden)return;
  const entry=shootHouseCompetition(state,catalog.get(state.mission)?.rooms||[]);
  if(!entry){node.textContent=t('competition.ineligible');return;}
  const best=progress.get(entry.id);
  node.textContent=t('competition.result',{score:entry.adjusted_time.toFixed(2),quality:(entry.quality*100).toFixed(0),known:entry.known})+' '+(best?t('competition.best',{score:best.adjusted_time.toFixed(2),attempts:best.attempts}):t('competition.first'))+' '+t('competition.note');
}
function saveCompetition(){
  if(!/^SH(?:0[1-4]|05_(?:PRECISION|HIGH_INTENSITY))$/.test(state.mission))return;
  const entry=shootHouseCompetition(state,catalog.get(state.mission)?.rooms||[]);if(!entry)return;
  if(!storeAvailable)return;
  leaderboard.submitScore(entry).then(record=>{progress.set(record.id,record);if(state.mode==='RESULT'&&state.mission===entry.mission)renderCompetition();}).catch(storageError);
}
function renderResult(){
  const result=state.result||{};const key=`${state.mission}:${state.seed}:${state.tick}:${JSON.stringify(result)}`;if(key===resultKey&&resultLanguage===getLanguage())return;resultKey=key;resultLanguage=getLanguage();
  const success=result.success===true||result.status==='SUCCESS'||result.outcome==='SUCCESS',units=state.units||[],objectives=state.objectives||{};
  $('result-code').textContent=`${state.mission||'T01'} · SEED ${state.seed??'—'} · ${state.variant||'standard'}${state.modifiers?.length?' · '+state.modifiers.join(' / '):''}`;
  $('result-title').textContent=success?t('result.complete'):t('result.ended');
  // Engine-supplied result.reason/message (simulation.gd's `result.reason`)
  // is free-form Korean text with no stable code to translate by, so
  // English mode always uses the localized default line instead of
  // passing that text through untranslated.
  $('result-message').textContent=getLanguage()==='en'?(success?t('result.default_success'):t('result.default_fail')):(result.reason||result.message||(success?t('result.default_success'):t('result.default_fail')));
  // RC debrief: rank letter stamp (engine's own S/A/B/C when present; score-
  // derived fallback keeps older engine builds that don't send result.rank
  // from showing a blank stamp). Re-trigger the CSS stamp-in animation by
  // forcing a reflow between removing/adding the element (class toggles on
  // the same frame don't restart a running animation).
  // Failure always shows a clear ✕ (the engine's literal '—' em-dash reads as
  // a stray line at this stamp's >=120px size, see plan §7). Success prefers
  // the engine's own rank letter, falling back to a score-derived one for
  // older engine builds that don't send result.rank yet.
  const rank=!success?'✕':typeof result.rank==='string'&&result.rank&&result.rank!=='—'?result.rank:(Number(result.score)>=95?'S':Number(result.score)>=80?'A':Number(result.score)>=65?'B':'C');
  const symbol=$('result-symbol');symbol.textContent=rank;symbol.style.animation='none';void symbol.offsetWidth;symbol.style.animation='';
  $('result').querySelector('.result-card').classList.toggle('failed',!success);
  animateCountUp($('result-score'),Math.round(Number(result.score)||0));
  const runId=conditionKey({...state,loadout:state.loadout||{},roster:state.roster||[]}),debrief=summarizeRun(state,progress.get(runId),parTimes[state.mission],getLanguage());
  $('result-goals').innerHTML=debrief.goals.map(goal=>`<span class="${goal.done?'achieved':''}">${escapeHTML((getLanguage()==='en'&&(['course_time','arrest','reload_cover','team_damage'].includes(goal.id)?t('star.'+goal.id):STAR_LABELS_EN[goal.id]))||goal.label)}</span>`).join('');
  $('result-comparison').textContent=debrief.comparison;$('retry-plan').hidden=!state.can_retry_plan;
  renderResultOperators(units);
  renderResultReplayPreview();
  const stats=resultStatistics(state);
  $('result-stats').innerHTML=stats.map(([label,value])=>`<div><dt>${escapeHTML(label)}</dt><dd>${escapeHTML(value)}</dd></div>`).join('');$('result-partial').hidden=state.replay?.complete!==false;
  renderRoomDoctrine();
  renderCompetition();
  // P0-5 cont.: fade hint only while the detail grid actually overflows, so the
  // cut-off boundary reads as "more below" instead of a half-visible row.
  requestAnimationFrame(()=>{const el=$('result-stats');el.classList.toggle('has-overflow',el.scrollHeight>el.clientHeight+1);});
  const saveRecord=(id,kind)=>{const old=progress.get(id)||{},stars=mergeStars(old,debrief.goals),record={id,kind,updatedAt:Date.now(),completed:old.completed||success,bestScore:success?Math.max(Number(old.bestScore)||0,Number(result.score)||0):Number(old.bestScore)||0,bestTime:success?Math.min(Number(old.bestTime)||Infinity,Number(state.time)||Infinity):old.bestTime||null,stars,medals:stars,attempts:(Number(old.attempts)||0)+1};if(kind==='run')record.conditions={mission:state.mission,seed:state.seed,variant:state.variant,modifiers:state.modifiers||[],loadout:state.loadout||{},roster:state.roster||[]};progress.set(id,record);if(kind==='mission')missionProgress.set(id,record);if(storeAvailable)store.put('progress',record).catch(error=>{if(kind==='mission'){progressSaveFailed=true;renderResultProgression();if(currentModal==='progression')renderProgression();}storageError(error);});};
  if(rewardedResultKey!==key){
    const before=unlockProfile;rewardedResultKey=key;
    saveRecord(state.mission,'mission');saveRecord(runId,'run');
    saveCompetition();
    if(campaign?.active&&!campaign.suspended&&missionBase(state.mission)===campaign.mission&&campaignResultKey!==key){campaignResultKey=key;campaign=finishCampaign(campaign,state);$('next-mission').disabled=true;persistCampaign().finally(()=>$('next-mission').disabled=false);preparedForBase='';}
    refreshProgression();resultRewards=progressionDiff(before,unlockProfile);
  }
  renderResultProgression();
  if(campaignRestoreProblem()){$('retry-plan').hidden=true;$('result-comparison').textContent+=` · ${campaignRestoreProblem()}`;}
  const next=nextMission(state.mission);$('next-mission').hidden=!next;$('next-mission').textContent=next?t('result.next',{name:localize(missions[next]||{},'name')||next}):'';
}
// RC: score counts up from 0 on debrief entry (plan §7); instant under
// reduced motion rather than skipped, so the final number still appears.
function animateCountUp(el,target){
  if(settings.reduced_flash||matchMedia('(prefers-reduced-motion: reduce)').matches){el.textContent=String(target);return;}
  const start=performance.now(),duration=900;
  const step=now=>{const t=Math.min(1,(now-start)/duration),eased=1-Math.pow(1-t,3);el.textContent=String(Math.round(target*eased));if(t<1)requestAnimationFrame(step);};
  requestAnimationFrame(step);
}
// RC: per-operator debrief cards (center column). kills/arrests are only
// mission-wide totals today (the engine doesn't expose per-unit attribution
// yet), so each card shows what the web actually knows about that
// operator — commands completed and hits taken (tracked client-side as hp
// drops land on that unit during the run, see renderUnits/unitHitCount) —
// and falls back to any future per-unit unit.kills/unit.arrests fields if
// the engine ever adds them. MVP = most commands completed among the
// survivors, tie-broken by fewest hits taken.
function renderResultOperators(units){
  const rows=units.map(unit=>{
    const completed=(unit.commands||[]).filter(command=>command.state==='SUCCEEDED').length;
    const hits=unit.hits_taken??unitHitCount.get(unit.id)??0;
    const down=Number(unit.hp)<=0;
    return {unit,completed,hits,down,kills:unit.kills,arrests:unit.arrests};
  });
  const mvp=rows.filter(row=>!row.down).sort((a,b)=>b.completed-a.completed||a.hits-b.hits)[0];
  $('result-operators').innerHTML=rows.map(row=>{
    const {unit}=row,uname=localize(ROSTER.find(r=>r.id===(unit.roster_id||unit.id))||unit,'name')||unit.name||unit.id;
    const initial=escapeHTML((uname||'?').trim().slice(0,1).toUpperCase()),isMvp=mvp&&row.unit===mvp.unit;
    const chips=[[t('stat.op_commands'),row.completed],[t('stat.hits'),row.hits]];
    if(Number.isFinite(row.kills))chips.push([t('stat.op_kills'),row.kills]);
    if(Number.isFinite(row.arrests))chips.push([t('stat.op_arrests'),row.arrests]);
    return `<div class="result-operator${isMvp?' mvp':''}${row.down?' incap':''}"><span class="op-portrait">${initial}</span><div class="result-operator-body"><span class="op-name">${escapeHTML(uname)}${isMvp?'<span class="op-mvp-badge">MVP</span>':''}<span class="op-status">${row.down?t('stat.incapacitated'):t('stat.hp',{hp:Math.round(Number(unit.hp)||0)})}</span></span><span class="op-stats">${chips.map(([label,value])=>`<span class="op-stat">${escapeHTML(label)} <b>${escapeHTML(String(value))}</b></span>`).join('')}</span></div></div>`;
  }).join('');
}
// RC: replay preview (right column) — a final-frame thumbnail grabbed off
// the live WebGL canvas when one is available, falling back to the
// stylized placeholder panel otherwise (headless/software renderers and
// contexts created without preserveDrawingBuffer can both come back blank).
function renderResultReplayPreview(){
  const host=$('result-replay-preview');if(!host)return;
  host.querySelector('img')?.remove();
  try{
    const canvas=$('canvas');if(!canvas||!canvas.width||!canvas.height)return;
    const dataUrl=canvas.toDataURL('image/jpeg',.72);if(!dataUrl||dataUrl.length<64)return;
    const img=document.createElement('img');img.alt='';img.src=dataUrl;host.prepend(img);
  }catch{/* tainted/unavailable canvas: keep the placeholder glyph+label */}
}
function closeModal(){if($('modal').open)$('modal').close();editorController?.destroy();editorController=null;currentModal='';bindingCapture=null;$('modal').classList.remove('squad-modal');if(engineReady)send({action:'preview_operator',profile:null},false);syncUiFocus();if(engineReady){send({action:'input_focus',blocked:false},false);$('canvas').focus({preventScroll:true});}}
function showModal(title,eyebrow,html){$('modal').classList.toggle('squad-modal',currentModal==='squad');$('modal-title').textContent=title;$('modal-eyebrow').textContent=eyebrow;$('modal-content').innerHTML=html;if(!$('modal').open)$('modal').showModal();syncUiFocus();if(engineReady)send({action:'input_focus',blocked:true},false);}
function openModal(name){closeFormation();closeContext();currentModal=name;if(state.mode==='EXECUTING')send({action:'pause'},false);if(state.mode==='REPLAY'&&state.replay?.playing)send({action:'pause'},false);
  if(name==='settings')renderSettings();
  if(name==='help')renderHelp();
  if(name==='library')renderLibrary();
  if(name==='credits')renderCredits();
  if(name==='plan')renderPlan();
  if(name==='progression')renderProgression();
  if(name==='pause')openPausePanel();
}
// RC: pause — left slide-in menu (plan §6), not a <dialog>, so the game
// scene stays visible (desaturated via body.pause-active) instead of being
// covered by the dialog's blurred backdrop. data-open="settings"/"help"
// buttons inside it open the normal dialog on top without closing this panel.
function openPausePanel(){
  const panel=$('pause-panel');panel.hidden=false;requestAnimationFrame(()=>panel.classList.add('open'));
  document.body.classList.add('pause-active');
  $('mode-pill').classList.remove('executing');$('mode-pill').classList.add('paused');writeHTML('mode-pill',`<span></span>${t('mode.paused')}`);
  send({action:'input_focus',blocked:true},false);
  syncUiFocus();
  panel.querySelector('#resume-game')?.focus({preventScroll:true});
}
function closePausePanel(){
  const panel=$('pause-panel');if(panel.hidden&&!panel.classList.contains('open'))return;
  panel.classList.remove('open');setTimeout(()=>{panel.hidden=true;syncUiFocus();},220);
  document.body.classList.remove('pause-active');
  $('mode-pill').classList.remove('paused');
  if(['PLANNING','EXECUTING'].includes(state.mode)){const executing=state.mode==='EXECUTING';$('mode-pill').classList.toggle('executing',executing);writeHTML('mode-pill',`<span></span>${executing?t('mode.executing'):t('mode.planning')}`);}
  if(engineReady&&!$('modal').open)send({action:'input_focus',blocked:false},false);
}
// RD1: settings dialog rewritten as 5 tabs (plan §9 / orchestration task 2-2).
// Every existing field keeps its storage key and behaviour; only the chrome
// (select/checkbox → Cycler/Toggle, one flat list → tabs) changes.
const SETTINGS_TABS = [['gameplay','settings.tab.gameplay'],['graphics','settings.tab.graphics'],['audio','settings.tab.audio'],['controls','settings.tab.controls'],['accessibility','settings.tab.accessibility']];
function settingToggleCard(key,label,note=''){
  const active=!!settings[key];
  return `<button type="button" class="toggle-card" data-setting-toggle="${key}" aria-pressed="${active}" title="${escapeHTML(note||label)}"><span class="toggle-icon">${active?'✓':''}</span><span><strong data-applied="${escapeHTML(t('settings.applied'))}">${escapeHTML(label)}</strong>${note?`<small>${escapeHTML(note)}</small>`:''}</span></button>`;
}
function settingSlider(key,label){return `<div class="setting-row"><label for="setting-${key}">${label}</label><div class="setting-control"><input id="setting-${key}" data-setting="${key}" type="range" min="0" max="100" step="1" value="${Math.round(settings[key]*100)}"><output id="value-${key}">${Math.round(settings[key]*100)}%</output></div></div>`;}
function settingCyclerRow(name,label){return `<div class="setting-row"><label>${label}</label>${renderCycler(name,cyclerDefs[name].options(),cyclerDefs[name].get())}</div>`;}
function renderBindingRow(action){
  const code=settings.bindings?.[action]||DEFAULT_BINDINGS[action];
  const capturing=bindingCapture===action;
  return `<div class="binding-row${capturing?' capturing':''}"><span class="binding-label">${t('binding.'+action)}</span><button type="button" class="binding-key" data-bind-action="${action}">${capturing?t('binding.capture'):codeLabel(code)}</button></div>`;
}
function gamepadDiagramSVG(){
  // Plan "해상도·입력 대응" mapping: left stick cursor, right stick pan,
  // LB/RB cycle squad select, A move, X door, Y equipment, B cancel, Start
  // GO, Back pause. Schematic, not a literal controller render.
  return `<svg class="gamepad-diagram" viewBox="0 0 320 170" aria-label="${t('gamepad.aria')}" role="img">
    <rect x="18" y="38" width="284" height="100" rx="46" class="gp-body"/>
    <circle cx="70" cy="88" r="20" class="gp-stick"/><text x="70" y="124" class="gp-label">${t('gamepad.stick_l')}</text>
    <circle cx="250" cy="88" r="20" class="gp-stick"/><text x="250" y="124" class="gp-label">${t('gamepad.stick_r')}</text>
    <rect x="30" y="54" width="26" height="12" rx="3" class="gp-shoulder"/><text x="43" y="48" class="gp-label">${t('gamepad.lb')}</text>
    <rect x="264" y="54" width="26" height="12" rx="3" class="gp-shoulder"/><text x="277" y="48" class="gp-label">${t('gamepad.rb')}</text>
    <g class="gp-face">
      <circle cx="210" cy="60" r="9"/><text x="210" y="63" class="gp-face-label">Y</text><text x="210" y="33" class="gp-label">${t('gamepad.equip')}</text>
      <circle cx="210" cy="96" r="9"/><text x="210" y="99" class="gp-face-label">A</text><text x="210" y="122" class="gp-label">${t('gamepad.move')}</text>
      <circle cx="192" cy="78" r="9"/><text x="192" y="81" class="gp-face-label">X</text><text x="170" y="81" class="gp-label">${t('gamepad.door')}</text>
      <circle cx="228" cy="78" r="9"/><text x="228" y="81" class="gp-face-label">B</text><text x="250" y="81" class="gp-label">${t('gamepad.cancel')}</text>
    </g>
    <rect x="140" y="80" width="18" height="10" rx="2" class="gp-center"/><text x="149" y="100" class="gp-label">${t('gamepad.back')}</text>
    <rect x="162" y="80" width="18" height="10" rx="2" class="gp-center"/><text x="171" y="68" class="gp-label">${t('gamepad.start')}</text>
  </svg>`;
}
function settingsTabBody(){
  if(settingsTab==='gameplay')return `<div class="settings-group"><h3>${t('settings.tab.gameplay')}</h3>${settingCyclerRow('language',t('settings.language'))}${settingToggleCard('fov',t('settings.fov'),t('settings.fov.note'))}${settingToggleCard('enemy_alerts',t('settings.alerts'),t('settings.alerts.note'))}${settingToggleCard('auto_pause_man_down',t('settings.auto_pause_man_down'),t('settings.auto_pause_man_down.note'))}<p class="note" style="margin-top:12px">${t('settings.language.note')}</p></div>`;
  if(settingsTab==='graphics')return `<div class="settings-group"><h3>${t('settings.tab.graphics')}</h3>${settingCyclerRow('line_width',t('settings.linewidth'))}<p class="note" style="margin-top:12px">${t('settings.graphics.note')}</p></div>`;
  if(settingsTab==='audio')return `<div class="settings-group"><h3>${t('settings.tab.audio')}</h3>${settingSlider('volume',t('settings.volume'))}${settingSlider('music_volume',t('settings.music'))}${settingToggleCard('muted',t('settings.mute'))}<p class="note" style="margin-top:15px">${t('settings.audio.note')}</p></div>`;
  if(settingsTab==='controls')return `<div class="settings-group"><h3>${t('settings.tab.controls')}</h3><div class="binding-list">${Object.keys(DEFAULT_BINDINGS).map(renderBindingRow).join('')}</div><p class="note" style="margin:12px 0">${t('settings.controls.note')}</p><button id="reset-bindings" class="secondary">${t('settings.reset_bindings')}</button><div class="settings-group" style="margin-top:22px"><h3>${t('settings.gamepad')}</h3>${gamepadDiagramSVG()}</div></div>`;
  return `<div class="settings-group"><h3>${t('settings.tab.accessibility')}</h3>${settingCyclerRow('ui_scale',t('settings.uiscale'))}${settingCyclerRow('palette',t('settings.palette'))}${settingToggleCard('screen_shake',t('settings.shake'),t('settings.shake.note'))}${settingToggleCard('reduced_flash',t('settings.reduced_flash'),t('settings.reduced_flash.note'))}<p class="note" style="margin-top:12px">${t('settings.accessibility.note')}</p></div>`;
}
function renderSettings(){
  currentModal='settings';
  const tabs=`<nav class="settings-tabs" role="tablist" aria-label="설정 탭">${SETTINGS_TABS.map(([id,key])=>`<button type="button" role="tab" class="settings-tab${settingsTab===id?' active':''}" aria-selected="${settingsTab===id}" data-settings-tab="${id}">${t(key)}</button>`).join('')}</nav>`;
  showModal(t('settings.title'),'SYSTEM PREFERENCES',`${tabs}<div class="settings-tab-body">${settingsTabBody()}</div><div class="dialog-footer"><p class="note">${t('settings.autosave')}</p><button id="import-settings" class="secondary">${t('settings.import')}</button><button id="export-settings" class="secondary">${t('settings.export')}</button></div>`);
}
function renderHelp(){
  const tx=equipmentText;
  const steps=[['01',tx('계획','Plan'),tx('대원을 선택하고 이동 경로와 행동을 순서대로 추가합니다.','Select an operator and queue routes and actions.')],['02',tx('실행','Execute'),tx('작전을 실행합니다. 새로운 상황을 발견하면 즉시 정지하세요.','Run the operation. Pause as soon as the situation changes.')],['03',tx('복기','Review'),tx('리플레이에서 장비·관측·투척 타이밍을 확인합니다.','Review equipment, observations and throw timing in the replay.')]];
  const controls=[['<kbd>1</kbd> – <kbd>4</kbd> / '+tx('좌클릭','LMB'),tx('대원 선택','Select operator')],['<kbd>'+tx('우클릭','RMB')+'</kbd>',tx('바닥: 이동 · 문: 행동 메뉴 · Shift로 경유점 추가','Ground: move · door: action menu · Shift adds waypoints')],['<kbd>'+codeLabel(settings.bindings?.face||DEFAULT_BINDINGS.face)+'</kbd> + '+tx('좌클릭','LMB'),tx('주시 방향 지정','Set facing')],['<kbd>Space</kbd>',tx('작전 실행 / 계획 정지','Run / pause to plan')],['<kbd>W</kbd> <kbd>A</kbd> <kbd>S</kbd> <kbd>D</kbd> / '+tx('휠','wheel'),tx('카메라 이동 / 확대·축소','Pan / zoom camera')],[tx('휠 버튼 / Alt·Option + 드래그','Middle button / Alt·Option + drag'),tx('지도를 잡아 화면 이동','Grab and pan the map')],['<kbd>Home</kbd>',tx('전체 지도 시점으로 복귀','Reset map view')],['<kbd>Esc</kbd>',tx('도구 취소 / 일시정지 메뉴','Cancel tool / pause menu')],[tx('장비 메뉴','Equipment menu'),tx('섬광탄 · 연막 · 진입 장약 · 카메라 · 무기 전환','Flashbang · smoke · entry charge · camera · weapon switch')],[tx('신호 대기 → A / B / C','Wait for signal → A / B / C'),tx('지정 신호 후 동시에 다음 행동','Continue together after the assigned signal')]];
  showModal(tx('작전 가이드','Operation guide'),'FIELD MANUAL',`<p class="modal-intro">${tx('일시정지로 다음 행동을 계획하세요. 대원은 시야 안에서 발견한 위협에 자동으로 대응합니다.','Pause to plan the next action. Operators automatically engage threats they can see.')}</p><div class="help-callout"><strong>${t('drill.title')}</strong><p>${t('drill.intro')}</p><p>${t('drill.doctrine')}</p><p>${t('drill.delay_hint')}</p></div><div class="help-callout"><strong>${t('formation.title')}</strong><p>${t('formation.intro')}</p><p>${t('formation.doctrine')}</p><p>${t('noise.wall_note')}</p></div><div class="guide-steps">${steps.map(([number,title,note])=>`<div><span>${number}</span><strong>${title}</strong><p>${note}</p></div>`).join('')}</div><table class="controls-table"><tbody>${controls.map(([key,action])=>`<tr><th>${key}</th><td>${action}</td></tr>`).join('')}</tbody></table><div class="help-callout"><strong>${tx('문 열고 섬광탄 던지기','Open door and throw flashbang')}</strong><br>${tx('대원을 선택하고 문을 우클릭하세요. 개방·투척·폭발 대기를 한 행동으로 예약합니다. 명령 목록의 ⌖ 버튼으로 투척 지점을 조정할 수 있습니다. 같은 문에 진입하는 팀도 폭발을 기다립니다. 이후 이동을 예약하지 않았다면 문 밖에 머뭅니다.','Select an operator and right-click a door. Queue opening, throwing and waiting for the blast as one action. Use ⌖ in the command queue to adjust the landing point. Teammates entering through that door wait for the blast. Without a following move, the thrower stays outside.')}</div><div class="help-callout"><strong>${tx('섬광탄 · 카메라 · 보조권총','Flashbang · camera · sidearm')}</strong><br>${tx('섬광탄은 적과 민간인을 잠시 기절시키며 아군과 체력에는 피해를 주지 않습니다. 벽·닫힌 문은 효과를 막습니다. 카메라는 실제 문 안쪽에서 얻은 정보만 정찰하며 관측이 끝나면 과거 기억으로 표시합니다. 권총은 별도 탄약을 사용하고 장비 메뉴에서 전환합니다.','Flashbangs briefly stun hostiles and civilians without health damage; allies are immune. Walls and closed doors block the effect. Cameras scout only through an actual door opening; contacts become remembered information after observation. Sidearms have separate ammunition and are switched from the equipment menu.')}</div><div class="help-callout"><strong>${tx('대원별 장비와 보호 범위','Personal gear and protection')}</strong><br>${tx('출동 준비의 개인 설정에서 무기·방어구·헬멧·부착물·역할 프리셋을 고르세요. 변경한 장비의 최종 성능과 전후 차이를 확인할 수 있습니다. 방어구는 표시한 방향·부위만 보호하며 관통 여부에 따라 효과가 달라집니다. 이름·콜사인·색상·패치는 외형 전용입니다. 개인 설정은 대원별로 저장되고 해금은 모든 대원이 공유합니다.','Choose weapons, armor, helmets, attachments and role presets in preparation. Compare the final performance before and after a change. Armor protects the shown directions and body regions; penetrating rounds change its effectiveness. Names, callsigns, colors and patches are cosmetic. Profiles persist per operator and unlocks are shared across the roster.')}</div><p class="note">${tx('명령은 대원당 최대 32개입니다. 단축키는 지도에 포커스가 있을 때 작동합니다. 탭을 벗어나면 자동 정지하며 복귀 후 직접 재개해야 합니다.','Each operator can queue up to 32 commands. Shortcuts work while the map has focus. Leaving the tab pauses automatically; resume manually on return.')}</p><div class="dialog-footer"><button id="fullscreen" class="secondary">${tx('전체화면 전환 ↗','Toggle fullscreen ↗')}</button><button id="show-tutorial" class="secondary">${tx('조작 도움말 다시 보기','Show tutorial again')}</button></div>`);
}
async function renderLibrary(){showModal('기록 보관함','AFTER ACTION ARCHIVE',`<div class="library-toolbar"><span>RECENT OPERATIONS</span><button id="import-replay" class="secondary">리플레이 가져오기 +</button></div><div id="replay-list" class="replay-list"><div class="empty-state">기록을 불러오고 있습니다.</div></div><p class="note">최근 10개 또는 총 100MB까지 자동 보관합니다. 한도를 넘으면 오래된 기록부터 정리됩니다. 보관할 기록은 파일로 내보내세요. 저장 데이터는 현재 브라우저·주소에만 남으며 영구 백업이 아닙니다.</p>`);
  try{if(!storeAvailable)throw new Error('브라우저 저장소를 사용할 수 없습니다. 파일을 가져와 리플레이를 볼 수 있습니다.');const records=(await store.listReplays()).sort((a,b)=>String(b.createdAt).localeCompare(String(a.createdAt)));if(currentModal!=='library')return;$('replay-list').innerHTML=records.length?records.map(record=>`<div class="replay-record"><div class="record-icon">${escapeHTML(record.mapId||'REC')}</div><div class="record-details"><strong>${escapeHTML(missions[record.mapId]?.name||'작전 기록')}${record.complete===false?' · 부분 기록':''}</strong><small>${escapeHTML(new Date(record.createdAt).toLocaleString('ko-KR'))} / ${formatTime(record.duration)} / SEED ${record.seed??record.data?.seed??'기본'} / ${escapeHTML(record.variant||record.data?.variant||'standard')} / ${(record.bytes/1024/1024).toFixed(2)} MB</small></div><div class="record-actions"><button data-load-replay="${escapeHTML(record.id)}">재생 ▷</button><button data-export-saved="${escapeHTML(record.id)}" aria-label="리플레이 파일 저장">저장 ↗</button><button data-delete-replay="${escapeHTML(record.id)}" aria-label="리플레이 삭제">×</button></div></div>`).join(''):'<div class="empty-state">아직 보관된 작전이 없습니다.<br>첫 임무를 완료하면 리플레이가 여기에 저장됩니다.</div>';}catch(error){if($('replay-list'))$('replay-list').textContent=error.message;}
}
function renderPlan(){showModal('작전 계획','OPERATION PLANNING',`<p class="modal-intro">첫 실행 전의 초기 명령 계획을 저장하고 다음 시도에 활용하세요. 실행 후 저장해도 임무 시작 전 계획이 보관됩니다. 불러오면 같은 임무를 처음부터 시작합니다. 전투 중 체력·탄약·적 상태는 복원하지 않습니다.</p><div class="plan-options"><button id="modal-save-plan"><strong>초기 계획 저장 ↓</strong><small>첫 실행 전의 명령 계획을 브라우저에 저장</small></button><button id="modal-load-plan"><strong>저장 계획 불러오기 ↻</strong><small>${escapeHTML(missions[state.mission||selectedMission]?.name||'임무')}을 저장된 계획으로 재시작</small></button><button id="export-plan"><strong>계획 파일 내보내기 ↗</strong><small>JSON 파일로 계획 보관</small></button><button id="import-plan"><strong>계획 파일 가져오기 +</strong><small>다른 브라우저에서 저장한 계획 사용</small></button></div><p class="note" style="margin-top:22px">브라우저 데이터 삭제, 비공개 모드, 주소·포트 변경 시 기록이 유지되지 않을 수 있습니다. 파일 내보내기를 권장합니다.</p>`);}
function renderCredits(){const tx=equipmentText;showModal(tx('크레딧','Credits'),'OPEN BREACH',`<div class="credits"><p>${tx('멈추고, 계획하고, 함께 진입하는 싱글플레이 전술 게임. 장비 이름과 대원 패치는 가상입니다.','A single-player tactical game about pausing, planning and entering together. Equipment names and operator patches are fictional.')}</p><p>Code: MIT · Original assets: CC0</p><h3>Engine & technology</h3><p>Godot Engine · <a href="licenses/Godot-MIT.txt" target="_blank" rel="noopener">MIT License</a> · <a href="licenses/Godot-COPYRIGHT.txt" target="_blank" rel="noopener">${tx('서드파티 고지','Third-party notices')}</a><br>GDScript · WebGL 2 · WebAssembly<br>HTML / CSS / JavaScript · IndexedDB</p><h3>Art & sound</h3><p>${tx('장비 선택 사진 20종: GPT 이미지 생성.','20 equipment catalog photographs: GPT image generation.')} <a href="licenses/Equipment-Images.txt" target="_blank" rel="noopener">${tx('생성 출처','Generation provenance')}</a>.<br>${tx('자체 제작 3D 환경·민간인과 UI 효과음.','Original 3D environments, civilians and UI sounds.')}<br>${tx('병사·총기·사망 모션: Quaternius (CC0).','Soldier, weapon and death-animation sources: Quaternius (CC0).')}<br>${tx('테른 C1·미카 S2·플린트 B1·피코 P1 총기와 크라운 헬멧: Quaternius CC0 모델 가공. 방어구·부착물·도구: OPEN BREACH 자체 제작(CC0).','Tern C1, Mica S2, Flint B1, Pico P1 weapons and Crown helmets: adapted Quaternius CC0 models. Armor, attachments and tools: original OPEN BREACH models (CC0).')} <a href="licenses/Operator-Equipment-CC0.txt" target="_blank" rel="noopener">${tx('출처와 수정 내역','Sources and modifications')}</a>.<br>${tx('병사 모션(CC0): Quaternius Toon Shooter, KayKit Character Animations(던지기, Kay Lousberg), 자체 제작 키','Soldier motion (CC0): Quaternius Toon Shooter, KayKit Character Animations (Throw) by Kay Lousberg, plus project-authored keys')} · <a href="licenses/Quaternius-Toon-Shooter.txt" target="_blank" rel="noopener">Toon Shooter</a> · <a href="licenses/Quaternius-Universal-Animation-Library.txt" target="_blank" rel="noopener">UAL</a> · <a href="licenses/KayKit-Character-Animations.txt" target="_blank" rel="noopener">KayKit</a>.<br>${tx('실내 가구·접촉음: Kenney Furniture Kit / Impact Sounds (CC0). 연기·섬광: Kenney Particle Pack (CC0).','Furniture and contact sounds: Kenney Furniture Kit / Impact Sounds (CC0). Smoke and flash particles: Kenney Particle Pack (CC0).')}<br>Free Firearm Sound Library — Ben Jaszczak, Brian Nelson, Kevin Heras, Matthew Nanney (CC0).</p><h3>Typography</h3><p>Noto Sans KR · Google / Adobe<br><a href="licenses/NotoSansKR-OFL.txt" target="_blank" rel="noopener">SIL Open Font License 1.1</a><br>Oswald · <a href="licenses/Oswald-OFL.txt" target="_blank" rel="noopener">SIL Open Font License 1.1</a><br>JetBrains Mono · <a href="licenses/JetBrainsMono-OFL.txt" target="_blank" rel="noopener">SIL Open Font License 1.1</a></p><h3>${tx('기록과 개인정보','Records and privacy')}</h3><p>${tx('플레이 기록·대원별 장비·설정은 이 브라우저에 보관됩니다. 서버로 플레이 정보를 보내지 않습니다. 리플레이는 JSON 기록 파일이며 영상 파일이 아닙니다.','Play records, operator profiles and settings stay in this browser. Play information is not sent to a server. Replays are JSON recordings, not video files.')}</p><p class="note">${tx('게임 내 점수는 목표 달성 기록이며 실제 전술 숙련도 평가가 아닙니다.','Scores record in-game objective completion, not real-world tactical proficiency.')}</p></div>`);}
async function handlePlanData(data){if(!data||typeof data!=='object')return;if(pendingPlanPurpose==='export'){downloadJSON(data,`breach-plan-${data.map_id||state.mission||'mission'}.json`);pendingPlanPurpose='save';return;}if(!storeAvailable){downloadJSON(data,`breach-plan-${data.map_id||state.mission||'mission'}.json`);toast('저장소를 사용할 수 없어 계획 파일을 내보냈습니다.','warning');return;}const mapId=data.map_id||state.mission;await store.put('plans',{id:mapId,updatedAt:Date.now(),data});toast('초기 작전 계획을 저장했습니다.');}
async function loadSavedPlan(missionId){try{if(!storeAvailable)throw new Error('브라우저 저장소를 사용할 수 없습니다. 계획 파일을 가져오세요.');const record=await store.get('plans',missionId);if(!record?.data){toast('이 임무에 저장된 계획이 없습니다.','warning');return;}loadPlan(record.data);}catch(error){storageError(error);}}
function loadPlan(data){
  if(data?.kind!=='breach-plan'||data?.schema_version!==1||(!missions[data.map_id]&&!data.mission_data)){toast('지원하지 않는 계획 파일입니다. OPEN BREACH v1 계획만 사용할 수 있습니다.','error');return;}
  if(data.mission_data)ingestCatalog([data.mission_data]);
  if(!checkProgression(data))return;
  let payload=data;
  if(campaign?.active&&!campaign.suspended){
    if(missionBase(data.map_id)!==campaign.mission){toast(`캠페인의 다음 임무는 ${campaign.mission}입니다.`,'warning');return;}
    const previousMission=selectedMission;selectedMission=data.map_id;const prepared=currentPreparation();selectedMission=previousMission;
    try{payload=normalizeCampaignPlan(data,prepared,campaign);}catch(error){toast(error.message,'warning');return;}
  }
  if(!checkProgression(payload))return;
  closeModal();closeContext();unlockAudio();selectedMission=data.map_id;selectedVariant=data.variant||catalog.get(data.map_id)?.variant||'standard';if(['base','normal','challenge'].includes(selectedVariant))selectedVariant='standard';selectedDifficulty=data.map_id.endsWith('H')?'challenge':'normal';selectedModifiers=new Set(data.modifiers||[]);
  if(Number.isSafeInteger(data.seed)&&data.seed>0){seedMode='custom';customSeed=data.seed;}else seedMode='fixed';
  if(data.roster?.length){squadIds=data.roster.map(unit=>unit.id);preparedForBase=missionBase(data.map_id);}
  resultKey='';savedReplayKey='';campaignResultKey='';rewardedResultKey='';resultRewards=null;lastUnitHTML='';lastQueueHTML='';planPendingLoad=null;
  send({action:'load_plan',data:payload});
}

async function handleReplayData(message){const data=message.data;if(!data||typeof data!=='object')return;if(message.purpose==='export'){downloadJSON(data,`breach-replay-${data.map_id||state.mission||'mission'}-${Date.now()}.json`);return;}const key=`${data.map_id||state.mission}:${data.duration}:${data.created_at||data.recorded_at||resultKey}`;if(key===savedReplayKey)return;savedReplayKey=key;if(!storeAvailable){toast(t('replay.not_saved'),'warning');return;}await store.saveReplay(data);toast(t('replay.saved'));}
function downloadJSON(data,name){try{const text=JSON.stringify(data);const blob=new Blob([text],{type:'application/json'});if(blob.size>20*1024*1024){toast('파일이 20MB 한도를 초과해 내보낼 수 없습니다.','error');return;}const url=URL.createObjectURL(blob);const link=document.createElement('a');link.href=url;link.download=name;document.body.append(link);link.click();link.remove();setTimeout(()=>URL.revokeObjectURL(url),30000);toast('파일을 내보냈습니다. 브라우저 다운로드를 확인하세요.');}catch(error){toast(`파일 내보내기에 실패했습니다: ${error.message}`,'error');}}
function importFile(kind){pendingImport=kind;$('file-import').value='';$('file-import').click();}
async function readImport(file){if(!file)return;if(file.size>20*1024*1024){toast('가져올 수 있는 파일 크기는 최대 20MB입니다.','error');return;}const loadingId=pendingImport==='settings'?null:beginTransition(`file-${++transitionSequence}`,pendingImport==='plan'?'load_plan':'import_replay','file');if(loadingId)await afterLoadingPaint();try{const data=JSON.parse(await file.text());if(!data||typeof data!=='object'||Array.isArray(data))throw new Error('JSON 객체 형식이 아닙니다.');if(pendingImport==='settings'){if(data.kind!=='breach-settings'||data.schema_version!==1)throw new Error('지원하는 설정 파일이 아닙니다.');settings=validateSettings(data.settings,settings.bindings);applySettings();await persistSettings();if(currentModal==='settings')renderSettings();toast(lastBindingsRejected?'조작 키 설정에 잘못된 키나 중복이 있어 기존 조작 키를 유지했습니다.':'설정을 가져왔습니다.',lastBindingsRejected?'warning':'info');}else if(pendingImport==='plan'){loadPlan(data);}else{if(data.schema_version!==1||(!missions[data.map_id]&&!data.mission_data))throw new Error('지원하지 않는 버전 또는 임무의 리플레이입니다.');if(data.mission_data)ingestCatalog([data.mission_data]);if(!Number.isFinite(data.duration)||data.duration<0||data.duration>601)throw new Error('리플레이 기록 시간이 올바르지 않습니다.');if(!Array.isArray(data.frames)||data.frames.length===0)throw new Error('리플레이 샘플 데이터가 없습니다.');closeModal();unlockAudio();send({action:'import_replay',data});}}catch(error){toast(`파일을 열 수 없습니다. ${error.message}`,'error');}finally{if(loadingId&&activeTransition?.id===loadingId&&activeTransition.stage==='file')finishTransition(loadingId);}}

// RD1: key-rebinding capture (plan 2-2 조작 탭). Registered ahead of the
// main keydown listener and stops propagation while capturing so Escape,
// digit shortcuts, etc. never leak through to gameplay while the dialog is
// waiting for a new key.
function bindBindingCapture(){
  document.addEventListener('keydown',event=>{
    if(!bindingCapture)return;
    event.preventDefault();event.stopImmediatePropagation();
    const action=bindingCapture;
    if(event.code==='Escape'){bindingCapture=null;renderSettings();return;}
    if(!VALID_BINDING_CODES.has(event.code)){toast(`${codeLabel(event.code)}는 지정할 수 없는 키입니다.`,'warning');return;}
    const conflict=Object.entries(settings.bindings).find(([other,code])=>other!==action&&code===event.code);
    if(conflict){toast(`${codeLabel(event.code)}는 이미 '${BINDING_LABELS[conflict[0]]}'에 사용 중입니다.`,'warning');return;}
    settings.bindings={...settings.bindings,[action]:event.code};bindingCapture=null;
    applySettings();persistSettings();renderSettings();
  },true);
}
function bindEvents(){
  document.addEventListener('keydown',event=>{if(event.target.matches('.cycler > output')&&['Enter',' '].includes(event.key)){event.preventDefault();event.stopImmediatePropagation();event.target.click();}},true);
  $('transition-loading').addEventListener('cancel',event=>event.preventDefault());
  $('transition-reload').addEventListener('click',()=>location.reload());
  document.addEventListener('keydown',event=>{if(activeTransition&&event.key!=='Tab'&&event.target!==$('transition-reload')){event.preventDefault();event.stopImmediatePropagation();}},true);
  bindBindingCapture();
  document.addEventListener('pointerdown',event=>{
    const handle=event.target.closest('[data-sync-delay]');if(!handle||handle.disabled||event.button!==0)return;
    event.preventDefault();handle.focus({preventScroll:true});handle.setPointerCapture(event.pointerId);
    drillDelayDrag={handle,pointer:event.pointerId,x:event.clientX,value:Number(handle.getAttribute('aria-valuenow')),width:Math.max(1,handle.getBoundingClientRect().width)};
  });
  document.addEventListener('pointermove',event=>{
    if(!drillDelayDrag||event.pointerId!==drillDelayDrag.pointer)return;
    const drag=drillDelayDrag;updateDrillDelayHandle(drag.handle,drag.value+(event.clientX-drag.x)*3600/drag.width);
  });
  document.addEventListener('pointerup',event=>{
    if(!drillDelayDrag||event.pointerId!==drillDelayDrag.pointer)return;
    const drag=drillDelayDrag;drillDelayDrag=null;if(drag.handle.hasPointerCapture(event.pointerId))drag.handle.releasePointerCapture(event.pointerId);
    if(state.mode==='PLANNING')commitDrillDelay(drag.handle,drag.handle.getAttribute('aria-valuenow'));
  });
  document.addEventListener('pointercancel',event=>{if(drillDelayDrag?.pointer===event.pointerId)cancelDrillDelayDrag();});
  document.addEventListener('lostpointercapture',event=>{if(drillDelayDrag?.pointer===event.pointerId)cancelDrillDelayDrag();});
  document.addEventListener('keydown',event=>{
    if(event.key==='Escape'&&drillDelayDrag){event.preventDefault();event.stopImmediatePropagation();cancelDrillDelayDrag();return;}
    if(event.key==='Escape'&&formationDraft){event.preventDefault();event.stopImmediatePropagation();closeFormation();return;}
    if(event.key==='Escape'&&roomDrillDraft){event.preventDefault();event.stopImmediatePropagation();closeRoomDrill();return;}
    const handle=event.target.closest('[data-sync-delay]');if(!handle||handle.disabled||!['ArrowLeft','ArrowRight','ArrowUp','ArrowDown','Home','End'].includes(event.key))return;
    event.preventDefault();event.stopImmediatePropagation();const value=Number(handle.getAttribute('aria-valuenow')),step=event.shiftKey?1:30;
    commitDrillDelay(handle,event.key==='Home'?0:event.key==='End'?3600:value+(['ArrowRight','ArrowUp'].includes(event.key)?step:-step));
  },true);
  document.addEventListener('click',async event=>{
    // RB: cyclers (replace <select>) — close every open quick-pick list
    // outside the one the click landed in, then handle a click on the
    // output itself (toggles its own list) before the generic button logic.
    const withinCycler=event.target.closest('.cycler');
    $$('.cycler-list').forEach(list=>{if(!list.hidden&&!list.closest('[data-gallery]')&&(!withinCycler||!withinCycler.contains(list))){list.hidden=true;list.closest('.cycler').querySelector('output').setAttribute('aria-expanded','false');}});
    const cyclerOutput=event.target.closest('.cycler > output')||event.target.closest('.gear-current-photo')?.parentElement.querySelector('output');
    if(cyclerOutput){const root=cyclerOutput.closest('[data-cycler]');if(root&&!root.hasAttribute('data-disabled')&&!root.dataset.gallery){const list=root.querySelector('.cycler-list');list.hidden=!list.hidden;cyclerOutput.setAttribute('aria-expanded',String(!list.hidden));}return;}
    const commandRow=event.target.closest('[data-select-command]');if(commandRow&&!event.target.closest('button')){send({action:'select_command',unit_id:commandRow.dataset.commandUnit||state.selected,index:Number(commandRow.dataset.selectCommand)});return;}
    const button=event.target.closest('button');if(!button||button.disabled)return;
    if(button.id==='formation-tool'){startFormationTool();return;}
    if(button.id==='formation-close'){closeFormation();return;}
    if(button.id==='formation-commit'){formationRequest('formation');closeFormation(true);return;}
    if(button.dataset.formationKind){formationDraft.kind=button.dataset.formationKind;formationRequest();return;}
    if(button.dataset.formationOrder){formationDraft.order=reorderDrillIds(formationDraft.order,button.dataset.formationOrder,Number(button.dataset.direction));formationRequest();return;}
    if(button.dataset.formationSignal){formationDraft.signal=button.dataset.formationSignal;formationRequest();return;}
    if(button.dataset.formationDelay!==undefined){formationDraft.delay_ticks=button.dataset.formationDelay==='reset'?0:clampDrillDelay(formationDraft.delay_ticks+Number(button.dataset.formationDelay)*(event.shiftKey?1/30:1));formationRequest();return;}
    if(button.id==='drill-close'){closeRoomDrill();return;}
    if(button.id==='drill-commit'){roomDrillRequest('room_drill');closeRoomDrill(true);return;}
    if(button.dataset.drillMethod){roomDrillDraft.method=button.dataset.drillMethod;roomDrillRequest();return;}
    if(button.dataset.drillOperator){roomDrillDraft.operator_id=button.dataset.drillOperator;roomDrillRequest();return;}
    if(button.dataset.drillOrder){roomDrillDraft.order=reorderDrillIds(roomDrillDraft.order,button.dataset.drillOrder,Number(button.dataset.direction));roomDrillRequest();return;}
    if(button.dataset.drillSignal){roomDrillDraft.signal=button.dataset.drillSignal;roomDrillRequest();return;}
    if(button.id==='drill-go-long'){roomDrillDraft.go_long=!roomDrillDraft.go_long;roomDrillRequest();return;}
    if(button.id==='drill-group-next'){const groups=roomDrillTimeline(state),index=groups.findIndex(group=>group.id===drillTimelineGroup);drillTimelineGroup=groups[(index+1)%groups.length]?.id||'';lastDrillHTML='';renderDrillTimeline();return;}
    if(button.dataset.drillPrimary){send({action:'select',unit_id:button.dataset.drillPrimary,preserve_group:true});return;}
    if(button.dataset.selectCommand!==undefined){send({action:'select_command',unit_id:button.dataset.commandUnit||state.selected,index:Number(button.dataset.selectCommand)});return;}
    if(button.dataset.syncDelay)return;
    if(button.hasAttribute('data-context-index')){chooseContext(Number(button.dataset.contextIndex));return;}
    if(button.dataset.doorMode){closeContext(false);send({action:'tool',tool:'door',door_mode:button.dataset.doorMode,door_fallback:button.dataset.doorFallback||''});return;}
    if(button.dataset.nav){handleTitleNav(button.dataset.nav);return;}
    if(button.dataset.collection){operationCollection=button.dataset.collection;renderMissionGrid();const first=$('[data-mission]');if(first)chooseMission(first.dataset.mission);return;}
    if(button.dataset.cycleDir!==undefined){cyclerStep(button.closest('[data-cycler]'),Number(button.dataset.cycleDir));return;}
    if(button.dataset.cycleSet!==undefined){cyclerSet(button.closest('[data-cycler]'),button.dataset.cycleSet);return;}
    if(button.dataset.customize){document.querySelector('.squad-members').open=false;customizationId=button.dataset.customize;$('modal').scrollTop=0;renderSquad();requestAnimationFrame(()=>document.querySelector(`[data-customize="${customizationId}"]`)?.focus({preventScroll:true}));return;}
    if(button.dataset.attachment){const id=customizationId,choice=normalizeOperatorLoadout(loadoutChoices[id]||{}),attachment=button.dataset.attachment,attachments=choice.attachments.filter(value=>value!==attachment);if(!choice.attachments.includes(attachment)){if(['dot','scope'].includes(attachment))for(let index=attachments.length-1;index>=0;index--)if(['dot','scope'].includes(attachments[index]))attachments.splice(index,1);attachments.push(attachment);}updateProfile(id,{attachments,preset:'custom'});return;}
    if(button.dataset.equipmentExtra){const id=customizationId,choice=normalizeOperatorLoadout(loadoutChoices[id]||{}),equipment={...choice.equipment},key=button.dataset.equipmentExtra;if(equipment[key])delete equipment[key];else equipment[key]=1;updateProfile(id,{equipment,preset:'custom'});return;}
    if(button.dataset.appearanceColor){const id=customizationId,choice=normalizeOperatorLoadout(loadoutChoices[id]||{});updateProfile(id,{appearance:{...choice.appearance,color:button.dataset.appearanceColor}});return;}
    if(button.dataset.appearancePatch){const id=customizationId,choice=normalizeOperatorLoadout(loadoutChoices[id]||{});updateProfile(id,{appearance:{...choice.appearance,patch:button.dataset.appearancePatch}});return;}
    if(button.dataset.flashTarget!==undefined){const unit_id=button.closest('[data-command-unit]')?.dataset.commandUnit||state.selected;send({action:'select_command',unit_id,index:Number(button.dataset.flashTarget)});send({action:'tool',tool:'flash_target',unit_id,index:Number(button.dataset.flashTarget)});return;}
    if(button.dataset.modifier){toggleModifier(button.dataset.modifier);return;}
    if(button.dataset.settingsTab){settingsTab=button.dataset.settingsTab;bindingCapture=null;renderSettings();return;}
    if(button.dataset.settingToggle){const key=button.dataset.settingToggle;settings[key]=!settings[key];applySettings();persistSettings();if(currentModal==='settings')renderSettings();return;}
    if(button.dataset.bindAction){bindingCapture=button.dataset.bindAction;renderSettings();return;}
    if(button.dataset.variantChip){const id=button.dataset.variantChip;if(id==='challenge')cyclerDefs.difficulty.set(selectedDifficulty==='challenge'?'normal':'challenge');else cyclerDefs.variant.set(id.slice('variant:'.length));return;}
    if(button.dataset.roster){toggleRoster(button.dataset.roster);return;}
    if(button.dataset.slotIndex!==undefined){currentModal='squad';renderSquad();return;}
    if(button.dataset.open){openModal(button.dataset.open);return;}
    if(button.dataset.mission){chooseMission(button.dataset.mission);return;}
    if(button.dataset.action){if(button.dataset.action==='retry_plan'){const problem=campaignRestoreProblem();if(problem){toast(problem,'warning');return;}}if(button.dataset.action==='retry'){if(campaign?.active&&!campaign.suspended&&missionBase(state.mission)!==campaign.mission){toast(`캠페인의 다음 작전은 ${campaign.mission}입니다.`,'warning');return;}closePausePanel();startMission(state.mission,{...preparationMeta(state.mission),seed:state.seed,variant:state.variant,modifiers:state.modifiers||[]});return;}closeModal();closePausePanel();if(['retry','retry_plan'].includes(button.dataset.action)){tutorialStep=0;tutorialClosed=false;resultKey='';savedReplayKey='';campaignResultKey='';rewardedResultKey='';resultRewards=null;}send({action:button.dataset.action});return;}
    if(button.id==='operator-hold'){const unit=state.units?.find(item=>item.id===state.selected);send({action:'unit_posture',unit_id:state.selected,settings:{hold_position:!unit?.hold_position}});return;}
    if(button.dataset.postureCycle){const field=button.dataset.postureCycle,values=field==='stance'?['standing','crouched']:['careful','normal','fast'],index=values.indexOf(button.value);send({action:'unit_posture',unit_id:state.selected,settings:{[field]:values[(index+1)%values.length]}});return;}
    if(button.dataset.unit){send({action:'select',unit_id:button.dataset.unit,extend:event.shiftKey});return;}
    if(button.id==='pan-camera'&&state.tool==='pan'){send({action:'tool',tool:'select'});return;}
    if(button.dataset.faceMode){send({action:'tool',tool:button.dataset.faceMode==='persistent'?'face_lock':'face'});return;}
    if(button.dataset.tool&&button.id!=='door-modes'){closeFormation(false,false);closeContext(false);send({action:'tool',tool:button.dataset.tool});return;}
    if(button.dataset.signal){send({action:'signal',channel:button.dataset.signal});button.classList.add('signaled');setTimeout(()=>button.classList.remove('signaled'),400);return;}
    if(button.hasAttribute('data-remove')){send({action:'remove',unit_id:button.closest('[data-command-unit]')?.dataset.commandUnit||state.selected,index:Number(button.dataset.remove)});return;}
    if(button.hasAttribute('data-reorder')){send({action:'reorder',unit_id:button.closest('[data-command-unit]')?.dataset.commandUnit||state.selected,index:Number(button.dataset.reorder),direction:Number(button.dataset.direction)});return;}
    if(button.dataset.speed){send({action:'replay_speed',speed:Number(button.dataset.speed)});return;}
    if(button.dataset.reveal!==undefined){send({action:'replay_reveal',value:button.dataset.reveal==='true'},false);return;}
    if(button.dataset.seek!==undefined){send({action:'replay_seek',time:Number(button.dataset.seek)},false);$('replay-time').textContent=formatTime(button.dataset.seek);return;}
    if(button.dataset.doctrineTick!==undefined){const tick=/^(0|[1-9]\d*)$/.test(button.dataset.doctrineTick)?Number(button.dataset.doctrineTick):NaN;requestDoctrineReplay(tick);return;}
    if(button.dataset.waitSignal){closeModal();send({action:'command',type:'WAIT_FOR_SIGNAL',args:{signal:button.dataset.waitSignal}});return;}
    if(button.dataset.loadReplay){const id=beginTransition(`file-${++transitionSequence}`,'import_replay','file');await afterLoadingPaint();try{const record=await store.get('replays',button.dataset.loadReplay);if(record){closeModal();unlockAudio();send({action:'import_replay',data:record.data});}}catch(error){storageError(error);}finally{if(activeTransition?.id===id&&activeTransition.stage==='file')finishTransition(id);}return;}
    if(button.dataset.exportSaved){const record=await store.get('replays',button.dataset.exportSaved).catch(error=>storageError(error));if(record)downloadJSON(record.data,`breach-replay-${record.mapId}-${record.id.slice(0,8)}.json`);return;}
    if(button.dataset.deleteReplay){await store.remove('replays',button.dataset.deleteReplay).then(()=>{toast('리플레이를 삭제했습니다.');renderLibrary();}).catch(storageError);return;}
    switch(button.id){
      case 'select-to-briefing':if(!checkProgression({mission:selectedMission}))break;if(engineReady)send({action:'preview',mission:selectedMission},false);showMenuScreen('briefing');break;
      case 'progression-equip':case 'prepare-squad':currentModal='squad';renderSquad();break;
      case 'squad-done':closeModal();updateBrief();break;
      case 'profile-save':await persistOperatorProfile(customizationId);renderSquad();break;
      case 'switch-weapon':{const unit=(state.units||[]).find(item=>item.id===state.selected);closeContext(false);send({action:'command',type:'SWITCH_WEAPON',args:{slot:unit?.active_weapon==='secondary'?'primary':'secondary'}});break;}
      case 'new-campaign':case 'new-ironman':campaign=newCampaign(button.id==='new-ironman');campaignResultKey='';button.disabled=true;const campaignSaved=await persistCampaign();squadIds=[];preparedForBase='';selectedVariant='standard';selectedMission=missionId('M01',selectedDifficulty);updateBrief();send({action:'preview',mission:selectedMission},false);toast(campaignSaved?'캠페인을 저장했습니다.':'캠페인을 이 세션에서 시작합니다.');showMenuScreen('briefing');break;
      case 'continue-campaign':campaign.suspended=false;button.disabled=true;await persistCampaign();selectedMission=missionId(campaign.mission,selectedDifficulty,selectedVariant);updateBrief();send({action:'preview',mission:selectedMission},false);showMenuScreen('briefing');break;
      case 'leave-campaign':campaign.suspended=true;button.disabled=true;await persistCampaign();updateBrief();renderCampaignScreen();break;
      case 'door-modes':openSubmenu('door',button);break;
      case 'equipment-modes':openSubmenu('equipment',button);break;
      case 'secure-modes':openSubmenu('secure',button);break;
      case 'open-lab':send({action:'lab'},false);break;
      case 'lab-toggle':send({action:'lab_control',toggle:true},false);break;
      case 'start-mission':startMission();break;
      case 'load-menu-plan':loadSavedPlan(selectedMission);break;
      case 'toggle-execution':unlockAudio();send({action:'toggle'});break;
      case 'reset-camera':send({action:'reset_camera'});break;
      case 'queue-toggle':$('queue-panel').hidden=!$('queue-panel').hidden;button.setAttribute('aria-expanded',String(!$('queue-panel').hidden));break;
      case 'hud-right-toggle':{const open=$('hud-right').classList.toggle('open');button.setAttribute('aria-expanded',String(open));scheduleSafeArea();setTimeout(scheduleSafeArea,220);break;}
      case 'queue-close':$('queue-panel').hidden=true;$('queue-toggle').setAttribute('aria-expanded','false');break;
      case 'clear-commands':send({action:'clear'});break;
      case 'tutorial-close':tutorialClosed=true;$('tutorial').hidden=true;break;
      case 'tutorial-next':if(tutorialStep<5)tutorialStep++;else tutorialClosed=true;renderTutorial();break;
      case 'wait-command':currentModal='wait';if(state.mode==='EXECUTING')send({action:'pause'},false);showModal('대기 명령','COMMAND / WAIT',`<p class="modal-intro">이전 명령을 마친 뒤 지정한 시간만큼 기다립니다. 계획 정지 중에는 대기 시간이 줄어들지 않습니다.</p><div class="wait-time"><input id="wait-duration" type="range" min="0.5" max="15" step="0.5" value="2" aria-label="대기 시간"><output id="wait-value">2.0초</output></div><div class="dialog-footer"><button id="confirm-wait" class="primary">대기 명령 추가 +</button></div>`);break;
      case 'confirm-wait':{const duration=Number($('wait-duration').value);closeModal();send({action:'command',type:'WAIT',args:{duration}});break;}
      case 'reload-command':send({action:'command',type:'RELOAD',args:{}});break;
      case 'signal-command':currentModal='signal';if(state.mode==='EXECUTING')send({action:'pause'},false);showModal('신호 대기','COMMAND / SYNCHRONIZE',`<p class="modal-intro">대원이 선택한 신호를 기다립니다. 여러 대원에게 같은 신호를 지정하고 화면 우측의 신호 버튼을 누르면 준비된 대원들이 함께 다음 행동을 시작합니다.</p><div class="choice-grid">${['A','B','C'].map(channel=>`<button class="choice-button" data-wait-signal="${channel}">${channel}<small>${channel} 신호 대기</small></button>`).join('')}</div><p class="note" style="margin-top:20px">신호는 현재 대기 중인 명령에만 적용됩니다. 이후 도착한 대원에게는 다시 신호를 보내세요.</p>`);break;
      case 'save-plan':case 'modal-save-plan':case 'pause-save-plan':pendingPlanPurpose='save';send({action:'get_plan'},false);break;
      case 'deck-more':openModal('plan');break;
      case 'modal-load-plan':loadSavedPlan(state.mission||selectedMission);break;
      case 'export-plan':pendingPlanPurpose='export';send({action:'get_plan'},false);break;
      case 'import-plan':importFile('plan');break;
      case 'reset-bindings':settings.bindings={...DEFAULT_BINDINGS};bindingCapture=null;applySettings();persistSettings();renderSettings();toast('조작 키를 기본값으로 되돌렸습니다.');break;
      case 'export-settings':downloadJSON({kind:'breach-settings',schema_version:1,settings},'breach-settings.json');break;
      case 'import-settings':importFile('settings');break;
      case 'import-replay':importFile('replay');break;
      case 'watch-replay':send({action:'replay'});break;
      case 'prior-attempt-toggle':togglePriorAttempt();break;
      case 'cqb-daily-seed':useCQBDailySeed();break;
      case 'cqb-copy-seed':await copyCQBSeed();break;
      case 'next-mission':selectedMission=nextMission(state.mission)||'M01';startMission(selectedMission);break;
      case 'replay-toggle':unlockAudio();send({action:'replay_toggle'});break;
      case 'replay-restart':send({action:'replay_seek',time:0});break;
      case 'export-replay':send({action:'export_replay'});break;
      case 'replay-hide':$('replay-hud').hidden=true;$('restore-hud').hidden=false;break;
      case 'restore-hud':$('restore-hud').hidden=true;$('replay-hud').hidden=false;break;
      case 'modal-close':closeModal();break;
      case 'resume-game':closeModal();closePausePanel();break;
      case 'pause-menu':closeModal();closePausePanel();send({action:'menu'});break;
      case 'load-retry':location.reload();break;
      case 'fullscreen':try{if(document.fullscreenElement)await document.exitFullscreen();else await document.documentElement.requestFullscreen();}catch{toast('이 브라우저에서는 전체화면을 사용할 수 없습니다.','warning');}break;
      case 'show-tutorial':tutorialClosed=false;tutorialStep=0;closeModal();if(state.mission!=='T01'||state.mode==='MENU'){selectedMission='T01';startMission('T01');}else renderTutorial();break;
    }
  });
  document.addEventListener('input',event=>{const input=event.target;if(input.dataset.appearance){const choice=normalizeOperatorLoadout(loadoutChoices[customizationId]||{});updateProfile(customizationId,{appearance:{...choice.appearance,[input.dataset.appearance]:input.value}},{render:false});}if(input.id==='lab-seek')send({action:'lab_control',seek:Number(input.value)},false);if(input.id==='wait-duration')$('wait-value').textContent=`${Number(input.value).toFixed(1)}초`;if(input.dataset.setting){const key=input.dataset.setting;settings[key]=input.type==='checkbox'?input.checked:['volume','music_volume'].includes(key)?Number(input.value)/100:Number(input.value);if($(`value-${key}`))$(`value-${key}`).textContent=`${Math.round(settings[key]*100)}%`;if(['volume','music_volume'].includes(key))applyAudioSettings();else applySettings();}if(input.id==='replay-seek'){writeText('replay-time',formatTime(input.value));queueReplaySeek(Number(input.value));}});
  document.addEventListener('change',event=>{const input=event.target;if(input.id==='replay-seek')flushReplaySeek();
    if(input.id==='editor-template'){try{if(!input.value)editorController?.setMission(createEditorMission());else{const data=structuredClone(editorTemplates.get(input.value));data.id=`EDIT_${input.value.replace(/[^A-Za-z0-9_]/g,'_')}`;data.title=`${data.title||input.value} · 사용자 맵`;data.custom=true;editorController?.setMission(data);}}catch(error){toast(`템플릿을 열 수 없습니다. ${error.message}`,'error');}return;}
    if(input.id==='custom-seed'){const value=Number(input.value);if(!Number.isSafeInteger(value)||value<1||value>2147483647){toast('시드는 1~2147483647의 정수로 입력하세요.','warning');input.value=customSeed;}else customSeed=value;renderPreparation();}
    if(input.id==='lab-scene')send({action:'lab_control',scene:input.value},false);if(input.id==='lab-view')send({action:'lab_control',view:input.value},false);if(input.dataset.setting)persistSettings();if(input.id==='replay-view')send({action:'replay_reveal',value:input.value==='true'},false);if(input.id==='replay-follow')send({action:'replay_follow',id:input.value},false);if(input.id==='file-import')readImport(input.files?.[0]);});
  $('replay-seek').addEventListener('pointerdown',event=>{if(event.button!==0)return;replayScrubbing=true;replayScrubPointer=event.pointerId;});
  const finishReplayScrub=event=>{if(!replayScrubbing||(['pointerup','pointercancel'].includes(event.type)&&event.pointerId!==replayScrubPointer))return;replayScrubbing=false;replayScrubPointer=null;flushReplaySeek();};
  document.addEventListener('pointerup',finishReplayScrub);document.addEventListener('pointercancel',finishReplayScrub);$('replay-seek').addEventListener('blur',finishReplayScrub);
  if(typeof ResizeObserver!=='undefined'){const observer=new ResizeObserver(scheduleSafeArea);for(const node of Object.values(safeAreaNodes))if(node)observer.observe(node);}
  $('modal').addEventListener('click',event=>{if(event.target===$('modal')){const rect=$('modal').getBoundingClientRect();if(event.clientX<rect.left||event.clientX>rect.right||event.clientY<rect.top||event.clientY>rect.bottom)closeModal();}});
  $('modal').addEventListener('close',()=>{currentModal='';bindingCapture=null;$('modal').classList.remove('squad-modal');syncUiFocus();if(engineReady){send({action:'preview_operator',profile:null},false);send({action:'input_focus',blocked:false},false);$('canvas').focus({preventScroll:true});}});
  $('modal').addEventListener('scroll',()=>{if(currentModal==='squad')updateOperatorPreview();},{passive:true});
  window.addEventListener('resize',()=>{if(currentModal==='squad')requestAnimationFrame(updateOperatorPreview);});
  document.addEventListener('focusin',event=>{if(engineReady)send({action:'input_focus',blocked:domOverlayOpen()||event.target.matches('input,select,textarea,[data-select-command],[data-sync-delay]')},false);});
  // Capture map grabs so releasing over a HUD panel cannot leave the camera held.
  const mapCanvas=$('canvas');
  const finishCameraGrab=()=>{mapCanvas.classList.remove('camera-dragging');if(engineReady)send({action:'cancel_camera_drag'},false);};
  mapCanvas.addEventListener('pointerdown',event=>{
    if(!['PLANNING','EXECUTING','REPLAY'].includes(state.mode)||$('modal').open||!$('pause-panel').hidden||context||visibleSubmenu())return;
    if(event.button===1||(event.button===0&&(event.altKey||state.tool==='pan'))){
      mapCanvas.setPointerCapture(event.pointerId);mapCanvas.classList.add('camera-dragging');mapCanvas.focus({preventScroll:true});
    }
  });
  mapCanvas.addEventListener('pointerup',()=>mapCanvas.classList.remove('camera-dragging'));
  mapCanvas.addEventListener('pointercancel',finishCameraGrab);
  window.addEventListener('blur',finishCameraGrab);
  document.addEventListener('keydown',event=>{if(event.key==='Escape')mapCanvas.classList.remove('camera-dragging');});
  // Cancel only the native menu. Keep right-button pointer input available to
  // Godot for door menus, routes and waypoint-facing drags everywhere in game.
  document.addEventListener('contextmenu',event=>event.preventDefault(),{capture:true});
  $('canvas').addEventListener('pointerdown',event=>{if(context||visibleSubmenu()){event.preventDefault();event.stopImmediatePropagation();closeContext();}},true);
  $('canvas').addEventListener('keydown',event=>{if(event.code==='Space')event.preventDefault();});
  // 0-6: contextual cursor tooltip replaces the permanent hint bar; follow the
  // pointer only while the map is interactive (live play, no modal/menu open).
  $('canvas').addEventListener('pointermove',event=>{
    const hint=$('cursor-hint');
    if(!['PLANNING','EXECUTING'].includes(state.mode)||$('modal').open||context||visibleSubmenu()){hint.classList.remove('visible');return;}
    hint.style.left=`${event.clientX}px`;hint.style.top=`${event.clientY}px`;hint.classList.add('visible');
  });
  $('canvas').addEventListener('pointerleave',()=>$('cursor-hint').classList.remove('visible'));
  document.addEventListener('keydown',event=>{if(event.target.matches('[data-select-command]')&&['Enter',' '].includes(event.key)){event.preventDefault();event.stopImmediatePropagation();send({action:'select_command',unit_id:event.target.dataset.commandUnit||state.selected,index:Number(event.target.dataset.selectCommand)});return;}if(event.target.matches('input,select,textarea')||event.repeat)return;if(menuScreen==='title'&&!$('modal').open&&state.mode==='MENU'){if(event.key==='ArrowDown'){event.preventDefault();focusTitleNav(titleNavIndex+1);return;}if(event.key==='ArrowUp'){event.preventDefault();focusTitleNav(titleNavIndex-1);return;}if(event.key==='Enter'&&document.activeElement?.classList.contains('title-nav-item')){event.preventDefault();document.activeElement.click();return;}}if(event.key==='Escape'&&!$('pause-panel').hidden&&!$('modal').open){event.preventDefault();event.stopImmediatePropagation();closePausePanel();return;}if(context||visibleSubmenu()){if(event.key==='Escape'){event.preventDefault();event.stopImmediatePropagation();closeContext();$('canvas').focus();return;}if(/^[1-9]$/.test(event.key)){event.preventDefault();event.stopImmediatePropagation();const index=Number(event.key)-1;if(context)chooseContext(index);else visibleSubmenu()?.querySelectorAll('button')[index]?.click();return;}}if(event.code===(settings.bindings?.face||'KeyF')&&!event.ctrlKey&&!event.metaKey&&!event.altKey&&event.target===$('canvas')&&!$('modal').open&&['PLANNING','EXECUTING'].includes(state.mode)){event.preventDefault();event.stopImmediatePropagation();send({action:'tool',tool:'face'},false);return;}if(event.key==='Escape'&&event.target===$('canvas')&&!$('modal').open){event.preventDefault();event.stopImmediatePropagation();send({action:'escape'},false);return;}if(event.key==='?'&&!$('modal').open){event.preventDefault();openModal('help');}if(event.key.toLowerCase()==='h'&&state.mode==='REPLAY'&&!$('modal').open){$('restore-hud').hidden=!$('restore-hud').hidden;$('replay-hud').hidden=!$('restore-hud').hidden;}if(event.target.matches('[data-mission]')&&['ArrowLeft','ArrowRight'].includes(event.key)){event.preventDefault();const ids=$$('[data-mission]').map(button=>button.dataset.mission);const index=ids.indexOf(missionBase(selectedMission));chooseMission(ids[(index+(event.key==='ArrowRight'?1:ids.length-1))%ids.length]);$(`tab-${missionBase(selectedMission)}`).focus();}},true);
  function autoPause(){if(!engineReady)return;send({action:'input_focus',blocked:true},false);if(state.mode==='EXECUTING'){send({action:'pause'},false);toast('탭을 벗어나 작전을 일시정지했습니다.');}if(state.mode==='REPLAY'&&state.replay?.playing)send({action:'pause'},false);stopAudio();}
  document.addEventListener('visibilitychange',()=>{if(document.hidden)autoPause();});window.addEventListener('blur',autoPause);
  let resizeTimer;window.addEventListener('resize',()=>{clearTimeout(resizeTimer);resizeTimer=setTimeout(()=>{lastToolKey='';if(settings.ui_scale_auto&&settings.ui_scale!==autoUiScale())applySettings();else if(['PLANNING','EXECUTING'].includes(state.mode))renderTool();scheduleSafeArea();},120);});
  $('result-stats').addEventListener('scroll',()=>{const el=$('result-stats');el.classList.toggle('has-overflow',el.scrollHeight-el.scrollTop>el.clientHeight+2);});
  // RC: the stats grid lives inside a collapsed <details> now, so re-check
  // the overflow fade once it's actually opened (closed clientHeight is 0).
  document.querySelector('.result-details')?.addEventListener('toggle',()=>{const el=$('result-stats');el.classList.toggle('has-overflow',el.scrollHeight>el.clientHeight+1);});
  window.addEventListener('focus',()=>{if(engineReady)send({action:'input_focus',blocked:domOverlayOpen()||document.activeElement?.matches('input,select,textarea,[data-sync-delay]')},false);if(audioUnlocked&&!document.hidden)audioContext?.resume().catch(()=>{});});
  $('canvas').addEventListener('webglcontextlost',event=>{event.preventDefault();if(engineReady)send({action:'pause'},false);fatalError('그래픽 연결이 중단되었습니다','브라우저가 그래픽 컨텍스트를 잃었습니다. 다시 불러온 뒤 저장된 계획으로 임무를 시작할 수 있습니다.');});
}

// --- RD1: gamepad navigation for DOM menus/overlays (plan 2-3) -----------
// Polls navigator.getGamepads() every frame. While any DOM overlay owns
// input (per domOverlayOpen()/ui_focus), D-pad/left-stick moves a focus
// ring over the overlay's focusable elements, A activates, B backs out,
// LB/RB steps a focused Cycler or switches a focused settings tab. In the
// live HUD (overlay closed) Godot owns the gamepad entirely; the only
// button web still reacts to there is Start, routed through the same
// `escape` bridge action the keyboard Escape key already uses, so the
// engine — not web — decides what pause means (no double-handling).
let gamepadFocusables = [], gamepadFocusIndex = -1, gamepadAxisCooldown = 0, gamepadPolling = false, gamepadOverlayRoot = null, gamepadFocusDirty = true;
const gamepadButtonState = new Map();
const gamepadMutationObserver = typeof MutationObserver!=='undefined'?new MutationObserver(()=>{gamepadFocusDirty=true;}):null;
function overlayRoot(){
  if($('modal').open)return $('modal-content');
  if(!$('formation-panel').hidden)return $('formation-panel');
  if(!$('room-drill-panel').hidden)return $('room-drill-panel');
  if(!$('pause-panel').hidden)return $('pause-panel');
  if(state.mode==='RESULT')return $('result');
  if(state.mode==='REPLAY')return $('replay-hud');
  if(state.mode==='MENU'){const screen=$(`${menuScreen}-screen`);return screen&&!screen.hidden?screen:$('menu');}
  return null;
}
function focusableElements(root){
  if(!root)return [];
  return Array.from(root.querySelectorAll('button,[tabindex]:not([tabindex="-1"]),a[href],input,select,summary'))
    .filter(el=>!el.disabled&&el.getClientRects().length>0&&!el.closest('[hidden]'));
}
function setGamepadFocus(index){
  document.querySelectorAll('.gamepad-focus').forEach(el=>el.classList.remove('gamepad-focus'));
  if(!gamepadFocusables.length){gamepadFocusIndex=-1;return;}
  gamepadFocusIndex=((index%gamepadFocusables.length)+gamepadFocusables.length)%gamepadFocusables.length;
  const el=gamepadFocusables[gamepadFocusIndex];el.classList.add('gamepad-focus');el.focus?.({preventScroll:true});el.scrollIntoView?.({block:'nearest'});
}
function gamepadButtonEdge(pad,index){
  const pressed=!!pad.buttons[index]?.pressed,key=`${pad.index}:${index}`,was=gamepadButtonState.get(key)||false;
  gamepadButtonState.set(key,pressed);return pressed&&!was;
}
function setGamepadOverlayRoot(root){
  if(root===gamepadOverlayRoot)return;
  gamepadOverlayRoot=root;gamepadFocusDirty=true;
  gamepadMutationObserver?.disconnect();
  if(root)gamepadMutationObserver?.observe(root,{childList:true,subtree:true,attributes:true,attributeFilter:['hidden','disabled','open']});
}
function stopGamepadPolling(){gamepadPolling=false;setGamepadOverlayRoot(null);}
function startGamepadPolling(){if(gamepadPolling)return;gamepadPolling=true;requestAnimationFrame(pollGamepad);}
function pollGamepad(){
  if(!gamepadPolling)return;
  const pads=typeof navigator.getGamepads==='function'?navigator.getGamepads():[];
  const pad=Array.from(pads||[]).find(Boolean);
  if(!pad){stopGamepadPolling();return;}
  requestAnimationFrame(pollGamepad);
  const aPressed=gamepadButtonEdge(pad,0),bPressed=gamepadButtonEdge(pad,1),lbPressed=gamepadButtonEdge(pad,4),rbPressed=gamepadButtonEdge(pad,5);
  if(activeTransition)return;
  if(!domOverlayOpen()){
    if(gamepadFocusIndex!==-1){document.querySelectorAll('.gamepad-focus').forEach(el=>el.classList.remove('gamepad-focus'));gamepadFocusIndex=-1;gamepadFocusables=[];}
    setGamepadOverlayRoot(null);
    // ui_focus is false here: Godot owns Start/Back in the live HUD (JOY_BUTTON_START/BACK in main.gd). Don't double-handle them.
    return;
  }
  setGamepadOverlayRoot(overlayRoot());
  if(gamepadFocusDirty){gamepadFocusables=focusableElements(gamepadOverlayRoot);gamepadFocusDirty=false;}
  if(gamepadFocusIndex>=gamepadFocusables.length)gamepadFocusIndex=-1;
  if(gamepadFocusables.length){
    if(gamepadFocusIndex<0)setGamepadFocus(0);
    const now=performance.now(),stickY=pad.axes[1]||0,dpadDown=pad.buttons[13]?.pressed,dpadUp=pad.buttons[12]?.pressed;
    if(now>gamepadAxisCooldown&&(dpadDown||stickY>0.6)){setGamepadFocus(gamepadFocusIndex+1);gamepadAxisCooldown=now+220;}
    else if(now>gamepadAxisCooldown&&(dpadUp||stickY<-0.6)){setGamepadFocus(gamepadFocusIndex-1);gamepadAxisCooldown=now+220;}
  }
  const current=gamepadFocusables[gamepadFocusIndex];
  if(aPressed&&current)current.click();
  if(bPressed){
    if($('modal').open)closeModal();
    else if(!$('pause-panel').hidden)closePausePanel();
    else if(state.mode==='MENU'&&menuScreen!=='title')showMenuScreen(menuScreen==='briefing'?'select':'title');
  }
  if((lbPressed||rbPressed)&&current){
    const dir=rbPressed?1:-1,cyclerRoot=current.closest('[data-cycler]'),tabButton=current.closest?.('[data-settings-tab]');
    if(cyclerRoot)cyclerStep(cyclerRoot,dir);
    else if(tabButton){const tabs=SETTINGS_TABS.map(([id])=>id),idx=tabs.indexOf(settingsTab);settingsTab=tabs[((idx+dir)%tabs.length+tabs.length)%tabs.length];bindingCapture=null;renderSettings();}
  }
}

window.addEventListener('gamepadconnected',startGamepadPolling);
window.addEventListener('gamepaddisconnected',()=>{const pads=typeof navigator.getGamepads==='function'?navigator.getGamepads():[];if(!Array.from(pads||[]).some(Boolean))stopGamepadPolling();});
async function boot(){
  bindEvents();updateBrief();showMenuScreen('title');if(Array.from((typeof navigator.getGamepads==='function'?navigator.getGamepads():[])||[]).some(Boolean))startGamepadPolling();await initStorage();preloadAudio();
  if(typeof WebAssembly==='undefined'){fatalError('WebAssembly를 지원하지 않습니다','최신 Chrome, Edge, Firefox 또는 Safari에서 다시 열어 주세요.');return;}
  const probe=document.createElement('canvas');const gl=probe.getContext('webgl2');if(!gl){fatalError('WebGL 2를 사용할 수 없습니다','브라우저의 하드웨어 가속을 켜고 최신 Chrome, Edge, Firefox 또는 Safari에서 다시 열어 주세요.');return;}gl.getExtension('WEBGL_lose_context')?.loseContext();
  if(location.protocol==='file:'){fatalError('웹 서버에서 실행해 주세요','프로젝트 폴더에서 실행 서버를 시작한 뒤 http://localhost 주소로 접속하세요. HTML 파일을 직접 열면 엔진을 불러올 수 없습니다.');return;}
  $('load-status').textContent='LOADING ENGINE';
  loadingTimeout=setTimeout(()=>{$('loading-message').textContent='엔진 파일을 불러오는 데 시간이 걸리고 있습니다. 네트워크와 서버 연결을 확인하세요.';$('load-retry').hidden=false;},45000);
  const script=document.createElement('script');script.src='engine.js';script.onerror=()=>fatalError('엔진을 불러오지 못했습니다','engine.js 파일을 찾을 수 없습니다. 빌드가 완료되었는지 확인한 뒤 다시 시도해 주세요.');
  script.onload=async()=>{try{if(typeof window.Engine!=='function')throw new Error('Godot Engine이 준비되지 않았습니다.');const engine=new window.Engine({executable:'engine',canvas:$('canvas'),canvasResizePolicy:2,focusCanvas:false,experimentalVK:false,ensureCrossOriginIsolationHeaders:false,args:[],onPrintError:message=>{quality.recordError(message,'godot');console.error(message);}});engineBooted=true;await engine.startGame({onProgress:(current,total)=>{const percent=total>0?Math.min(98,Math.round(current/total*100)):12;$('load-progress').style.width=`${percent}%`;$('load-percent').textContent=`${percent}%`;$('load-status').textContent=total>0?`ENGINE / ${(current/1024/1024).toFixed(1)} MB`:'LOADING ASSETS';}});if(!engineReady){$('load-status').textContent='PREPARING TACTICAL WORLD';$('load-progress').style.width='98%';}}catch(error){fatalError('작전 환경을 시작하지 못했습니다',`${error?.message||String(error)} · 엔진 파일과 WebGL 2 지원 여부를 확인하고 다시 시도해 주세요.`);}};
  document.head.append(script);
}
boot().catch(error=>fatalError('초기화에 실패했습니다',error?.message||String(error)));

for(const [id,field] of [['operator-stance','stance'],['operator-pace','movement_mode']])$(id).addEventListener('change',event=>send({action:'unit_posture',unit_id:state.selected,settings:{[field]:event.target.value}}));
