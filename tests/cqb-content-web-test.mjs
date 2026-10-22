import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';

const read=name=>readFile(new URL('../'+name,import.meta.url),'utf8');
const [app,html,css,metaSource,debriefSource,qualitySource,i18nSource]=await Promise.all(['web/app.js','web/index.html','web/style.css','web/meta.js','web/debrief.js','web/quality-metrics.js','web/i18n.js'].map(read));
const load=source=>import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
const [meta,debrief,quality,i18n]=await Promise.all([load(metaSource),load(debriefSource),load(qualitySource),load(i18nSource)]);
let checks=0;
const plain=value=>value===undefined?undefined:JSON.parse(JSON.stringify(value));
const equal=(actual,expected,note)=>{assert.deepEqual(plain(actual),plain(expected),note);checks++;};
const check=(value,note)=>{assert(value,note);checks++;};
const section=(start,end)=>{const a=app.indexOf(start),b=app.indexOf(end,a);assert(a>=0&&b>a,'Actual source '+start);return app.slice(a,b).replaceAll('export function','function');};
const escapeHTML=value=>String(value??'').replace(/[&<>"']/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
const helpers=vm.createContext({...meta,roomDoctrineReport:debrief.roomDoctrineReport,gradeRoomDoctrine:quality.gradeRoomDoctrine});
vm.runInContext(section('export function cqbFamily','export function missionRoe'),helpers);
const expectedSH=['SH01','SH02','SH03','SH04','SH05_PRECISION','SH05_HIGH_INTENSITY'];
const expectedCQB=Array.from({length:12},(_,i)=>'CQB'+String(i+1).padStart(2,'0'));
equal(meta.SHOOT_HOUSE_MISSIONS,expectedSH,'Six drills share five shoot-house families');
equal(meta.CQB_MISSIONS,[...expectedSH,...expectedCQB],'The content collection contains exactly eighteen authored IDs');
for(const id of expectedSH){equal(helpers.cqbFamily(id),id.startsWith('SH05_')?'5':String(Number(id.slice(2))));equal(meta.missionId(id,'challenge','escort'),id,'Standalone content keeps its exact authored ID');}
for(const id of expectedCQB)equal(helpers.cqbFamily(id),'puzzle');
for(const id of ['M01','M01_PRECISION','H01','SH00','SH06','SH05','CQB00','CQB13','sh01','CQB01_ESCORT',null])equal(helpers.cqbFamily(id),'','Only registered exact IDs have CQB presentation');

const nodes=new Map();
const node=id=>{if(!nodes.has(id))nodes.set(id,{textContent:'',innerHTML:'',hidden:false,style:{},offsetWidth:1,classList:{toggle(){}},querySelector:()=>({classList:{toggle(){}}})});return nodes.get(id);};
const allIds=['T01',...meta.CAMPAIGN_MISSIONS,'M01_PRECISION','M01_HIGH_INTENSITY','H01','H02',...meta.CQB_MISSIONS];
const catalog=new Map(allIds.map(id=>[id,{id,seed:1049,bounds:[24,24],roe:id.includes('HIGH_INTENSITY')?'high_intensity':'precision',rooms:[{id:'observed',label:'관측한 방',label_en:'Observed room'}]}]));
const grid=vm.createContext({...meta,$:node,$$:()=>[],catalog,missions:Object.fromEntries(allIds.map(id=>[id,{name:id,name_en:id}])),operationCollection:'cqb',catalogRevision:1,getLanguage:i18n.getLanguage,unlockProfile:{stars:0,completedBases:new Set(),campaignAccess:new Set()},lastMissionGridKey:'',progress:new Map(),missionAccess:()=>({unlocked:true}),missionThumbMarkup:()=>'<svg></svg>',roeBadge:()=>'',localize:i18n.localize,escapeHTML,t:i18n.t});
vm.runInContext(section('function renderMissionGrid()','// --- RB2: variant chip row'),grid);
const renderedIds=()=>[...node('mission-grid').innerHTML.matchAll(/data-mission="([^"]+)"/g)].map(match=>match[1]);
for(const language of ['ko','en']){i18n.setLanguage(language);grid.renderMissionGrid();equal(renderedIds(),meta.CQB_MISSIONS,'All new cards use exact bridge IDs');equal(node('operation-scale-note').textContent,i18n.t('cqb.collection_scale',{count:18}));}
grid.operationCollection='base';grid.renderMissionGrid();equal(renderedIds(),['T01',...meta.CAMPAIGN_MISSIONS,'M01_PRECISION','M01_HIGH_INTENSITY'],'The original base collection preserves its twelve cards');
grid.operationCollection='history';grid.renderMissionGrid();equal(renderedIds(),['H01','H02'],'The existing historical collection is unchanged');
const choose=vm.createContext({...meta,selectedVariant:'escort',selectedDifficulty:'challenge',selectedMission:'M01',operationCollection:'history',updateBrief(){},engineReady:true,sent:[],send:value=>choose.sent.push(plain(value))});
vm.runInContext(section('function chooseMission(','function nextMission('),choose);
for(const id of meta.CQB_MISSIONS){choose.chooseMission(id);equal([choose.selectedMission,choose.selectedDifficulty,choose.selectedVariant,choose.operationCollection],[id,'normal','standard','cqb']);equal(choose.sent.at(-1),{action:'menu_focus',data:{mission_id:id}},'Selection sends the exact authored mission ID');}
choose.chooseMission('M01_PRECISION');equal(choose.operationCollection,'base','Original ROE comparisons retain their existing collection');
choose.chooseMission('H01');equal([choose.selectedMission,choose.operationCollection],['H01','history'],'Legacy historical selection retains its path');

// Use the actual public projection and grader. Unknown/hidden rows never
// enter the mean, and N/A contributes neither points nor a denominator.
const row=value=>({value,tick:60,time:2,unit_id:'alpha',hidden_enemy:{id:'secret',x:99,z:99}});
const partial={stealth:row(0),doorway_dwell:row(1),threat_order_violations:row(1),marked:row(1)};
const authored=[{id:'observed',label:'Observed'},{id:'hidden',label:'Hidden'},{id:'missing',label:'Missing'}];
const snapshot={mode:'RESULT',mission:'SH01',seed:42,tick:600,time:20,variant:'normal',modifiers:['night'],loadout:{alpha:{weapon:'standard',armor:'light',equipment:{stun:1}}},roster:[{id:'raven',trait:'steady',base_id:'alpha',enemy_id:'secret'}],units:[{id:'alpha',hp:100}],replay:{complete:true,duration:20},room_states:{observed:{state:'MARKED',observed:true},hidden:{state:'MARKED',observed:false},missing:{state:'CLEAR',observed:true},outsider:{state:'MARKED',observed:true}},result:{success:true,room_doctrine:{observed:partial,hidden:{marked:row(1)},outsider:{marked:row(1)}}},room_doctrine_private:{hidden:partial},enemies:[{id:'secret',x:99,z:99}]};
const newStars=[['course_time','90초 이내 완료'],['arrest','투항자 체포'],['reload_cover','재장전 후 완수'],['team_damage','아군 피해 0']].map(([id,label])=>({id,label}));
snapshot.stars=newStars;
const before=JSON.stringify(snapshot),entry=helpers.shootHouseCompetition(snapshot,authored);
equal([entry.elapsed,entry.quality,entry.known,entry.adjusted_time],[20,.625,4,32],'Good=1, caution=.5 and fail=0; N/A is excluded');
equal(entry.id,'cqb-competition:'+meta.conditionKey(snapshot),'Competition uses the canonical same-condition key');
check(!JSON.stringify(entry).includes('secret'),'Competition saves aggregates and canonical own preparation, never NPC evidence');
equal(JSON.stringify(snapshot),before,'Competition grading never mutates the authoritative public snapshot');
const hiddenChanged=structuredClone(snapshot);hiddenChanged.result.room_doctrine.hidden=Object.fromEntries(['stealth','doorway_dwell','time_to_dominate','threat_order_violations','marked','rear_hits'].map(id=>[id,row(999)]));hiddenChanged.enemies=[];equal(helpers.shootHouseCompetition(hiddenChanged,authored),entry,'Hidden occupants and unobserved metrics cannot change a score');
for(const observed of [false,'true',1,null]){const state=structuredClone(snapshot);state.room_states.observed.observed=observed;equal(helpers.shootHouseCompetition(state,authored),null,'Explicit public observation is required');}
for(const mutation of [state=>state.mission='CQB01',state=>state.mission='M01',state=>state.result.success=false,state=>state.result.success='true',state=>{delete state.result.success;state.result.status='SUCCESS';},state=>state.time=0,state=>state.time=-1,state=>state.time=NaN,state=>state.time=Infinity,state=>state.time='20',state=>state.replay.complete=false,state=>state.replay.complete='true',state=>delete state.replay.complete,state=>state.room_states={},state=>state.result.room_doctrine={},state=>{state.result.room_doctrine={};state.result.room_doctrine_private={observed:partial};}]){const state=structuredClone(snapshot);mutation(state);equal(helpers.shootHouseCompetition(state,authored),null,'Failed, partial, invalid or unknown-only runs are ineligible');}
const zero=structuredClone(snapshot);zero.result.room_doctrine.observed={stealth:row(2),marked:row(0)};equal(helpers.shootHouseCompetition(zero,authored),null,'A fully failed score cannot rank through the denominator floor');
const failedMetrics={stealth:row(2),doorway_dwell:row(2),time_to_dominate:row(6),threat_order_violations:row(1),identification:{...row(1),civilian_damage:1,unlawful_shots:1},control:{...row(0),arrested:0,surrendered:1,secured:0,civilians:0},marked:row(0),rear_hits:row(1)};
const low=structuredClone(snapshot);low.time=10;low.room_states.missing={state:'CLEAR',observed:true};low.result.room_doctrine={observed:structuredClone(failedMetrics),missing:structuredClone(failedMetrics)};low.result.room_doctrine.observed.doorway_dwell=row(1);const lowEntry=helpers.shootHouseCompetition(low,authored);
equal([lowEntry.quality,lowEntry.known,lowEntry.adjusted_time],[.03125,16,80],'Positive quality below .125 uses the specified denominator floor');
low.time=Number.MAX_VALUE;equal(helpers.shootHouseCompetition(low,authored),null,'A numeric overflow is rejected before local persistence');
for(const mutation of [state=>state.seed++,state=>state.variant='challenge',state=>state.loadout.alpha.armor='heavy',state=>state.loadout.alpha.equipment.stun=2,state=>state.roster[0].id='viper',state=>state.mission='SH05_PRECISION',state=>state.mission='SH05_HIGH_INTENSITY']){const state=structuredClone(snapshot);mutation(state);check(helpers.shootHouseCompetition(state,authored).condition_key!==entry.condition_key,'A changed authored mission, seed, variant, roster or complete loadout separates competition');}
const reordered=structuredClone(snapshot);reordered.loadout={alpha:{equipment:{stun:1},armor:'light',weapon:'standard'}};reordered.modifiers=['night','night'];equal(helpers.shootHouseCompetition(reordered,authored).condition_key,entry.condition_key,'Object ordering and duplicate modifiers do not split identical conditions');

const seed=vm.createContext({...meta,cqbFamily:helpers.cqbFamily,catalog,selectedMission:'CQB12',seedMode:'default',customSeed:77,randomSeed:88,$:node,t:i18n.t,localDate:()=> '2026-10-11',renderPreparation(){seed.renders++;},renders:0,navigator:{clipboard:{async writeText(value){seed.copied=value;}}},toast:(...args)=>seed.toasts.push(args),toasts:[]});
vm.runInContext(section('function resolvedSeed(','function rulesDescription('),seed);
equal(seed.resolvedSeed(),1049,'Authored default seed remains available');
seed.useCQBDailySeed();equal([seed.seedMode,seed.selectedMission,seed.renders],['daily','CQB12',1],'Shared daily seed preserves the selected standalone mission');
const shared=seed.resolvedSeed();seed.selectedMission='SH05_PRECISION';equal(seed.resolvedSeed(),shared,'All new content can share the same daily seed without legacy daily-operation routing');
await seed.copyCQBSeed();equal(seed.copied,`SH05_PRECISION · ${shared}`,'Copy shares the exact mission and seed');
seed.renderCQBPreparation();equal(node('cqb-share').hidden,false);check(node('cqb-shared-seed').textContent.includes(String(shared)));
seed.selectedMission='M01';seed.seedMode='custom';seed.useCQBDailySeed();equal([seed.seedMode,seed.renders],['custom',1],'A legacy mission does not enter the new seed action');seed.renderCQBPreparation();equal(node('cqb-share').hidden,true);
seed.selectedMission='CQB01';seed.navigator.clipboard.writeText=async()=>{throw new Error('Clipboard unavailable');};await seed.copyCQBSeed();equal(seed.toasts.at(-1),[i18n.t('cqb.seed_copy_failed'),'warning'],'Clipboard failure keeps an actionable translated message');

// Exercise the actual RESULT reward guard with the new submission path.
// Language repaint and duplicate snapshots must not add competition attempts.
let submissions=0;const resultWrites=[];
const result=vm.createContext({...meta,state:snapshot,resultKey:'',resultLanguage:'',rewardedResultKey:'',campaignResultKey:'',$:node,t:i18n.t,getLanguage:i18n.getLanguage,localize:i18n.localize,escapeHTML,formatTime:value=>String(value),catalog,roomDoctrineReport:debrief.roomDoctrineReport,doctrineReplaySeek:debrief.doctrineReplaySeek,gradeRoomDoctrine:quality.gradeRoomDoctrine,shootHouseCompetition:helpers.shootHouseCompetition,progress:new Map(),missionProgress:new Map(),parTimes:{},summarizeRun:debrief.summarizeRun,STAR_LABELS_EN:{},requestAnimationFrame:callback=>callback(),animateCountUp(element,value){element.textContent=String(value);},renderResultOperators(){},renderResultReplayPreview(){},storeAvailable:true,store:{put:async(table,record)=>{resultWrites.push(plain(record));}},leaderboard:{async submitScore(value){submissions++;return {...plain(value),attempts:1,version:1,updatedAt:0};}},storageError:error=>{throw error;},unlockProfile:{stars:0},resultRewards:null,refreshProgression(){},progressionDiff:()=>({stars:0,unlocks:[]}),campaign:null,campaignRestoreProblem:()=>'',nextMission:()=>null,missions:{},renderResultProgression(){}});
vm.runInContext(section('export function resultStatistics','// RC: score counts up'),result);
for(const language of ['ko','en','ko']){i18n.setLanguage(language);result.renderResult();await Promise.resolve();result.renderResult();await Promise.resolve();equal(submissions,1,'Repeated RESULT and language changes submit exactly one attempt');check(!node('result-competition').hidden);check(node('result-competition').textContent.includes('32.00'),'The displayed adjusted time matches the public grader');if(language==='en'){check(!/[가-힣]/.test(node('result-competition').textContent),'New result text follows English completely');for(const star of newStars)check(node('result-goals').innerHTML.includes(i18n.t('star.'+star.id)),'New authored result star follows the English key');}}
equal(resultWrites.length,2,'Original mission and condition records remain once each');
result.state={...snapshot,mission:'CQB01'};result.renderCompetition();equal(node('result-competition').hidden,true,'Puzzles do not submit or display a shoot-house leaderboard');
result.state=zero;result.renderCompetition();equal(node('result-competition').textContent,i18n.t('competition.ineligible'),'Zero quality displays the explicit eligibility rule');
result.saveCompetition();await Promise.resolve();equal(submissions,1,'Ineligible results never reach the adapter');

const briefStars=app.split('\n').find(line=>line.includes("$('brief-stars').innerHTML=stars.map"));
const brief=vm.createContext({$:node,stars:newStars,achieved:{},escapeHTML,t:i18n.t,getLanguage:i18n.getLanguage,STAR_LABELS_EN:{}});
for(const language of ['ko','en']){i18n.setLanguage(language);vm.runInContext(briefStars,brief);for(const star of newStars)check(node('brief-stars').innerHTML.includes(language==='en'?i18n.t('star.'+star.id):star.label),'Actual briefing star labels follow the active language');}
brief.stars=[{id:'custom',label:'Authored custom star'}];vm.runInContext(briefStars,brief);check(node('brief-stars').innerHTML.includes('Authored custom star'),'Legacy custom authored label fallback is preserved');

const keys=[...newStars.map(star=>'star.'+star.id),'cqb.collection','cqb.collection_scale',...['1','2','3','4','5','puzzle'].flatMap(family=>[`cqb.family.${family}_title`,`cqb.family.${family}_note`]),'cqb.shared_seed','cqb.daily_seed','cqb.copy_seed','cqb.seed_copied','cqb.seed_copy_failed',...['note','result','best','first','ineligible','local','invalid','save_failed','unavailable'].map(key=>'competition.'+key)];
for(const language of ['ko','en']){i18n.setLanguage(language);for(const key of keys){const value=i18n.t(key,{count:18,mission:'SH01',seed:42,score:'32.00',quality:63,known:4,attempts:1});check(value!==key,'Every new key exists in '+language);check(!/\{\w+\}/.test(value),'Every new placeholder is resolved');if(language==='en')check(!/[가-힣]/.test(value),'English new copy contains no untranslated Korean');}}
for(const id of ['cqb-family-note','cqb-share','cqb-shared-seed','cqb-daily-seed','cqb-copy-seed','result-competition'])check(html.includes(`id="${id}"`),'New UI hook '+id+' exists');
check(html.includes('data-collection="cqb"'),'The new collection is discoverable');
check(css.includes('.cqb-share>div')&&css.includes('flex-wrap:wrap'),'New seed controls wrap inside the existing scrolling briefing');
check(app.includes("record.kind!=='cqb-competition'")&&app.includes("!String(id).startsWith('cqb-competition:')"),'Competition records remain outside mission progression');
check(app.includes('const leaderboard=createLeaderboardAdapter(store)')||app.includes('const leaderboard = createLeaderboardAdapter(store)'),'UI constructs the default local adapter');
i18n.setLanguage('ko');
console.log(`BREACH_CQB_CONTENT_WEB_RESULT checks=${checks} failures=0 status=PASS`);
