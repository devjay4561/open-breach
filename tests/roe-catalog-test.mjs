import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';

const metaSource=await readFile(new URL('../web/meta.js',import.meta.url),'utf8');
const meta=await import('data:text/javascript;base64,'+Buffer.from(metaSource).toString('base64'));
const catalog=JSON.parse(await readFile(new URL('../game/data/equipment_catalog.json',import.meta.url),'utf8'));
let checks=0;
const equal=(actual,expected,label)=>{assert.deepEqual(actual,expected,label);checks++;};
const truth=(value,label)=>{assert.ok(value,label);checks++;};
const pairs=['M01_PRECISION','M01_HIGH_INTENSITY'];
equal(meta.CATALOG,catalog,'Generated equipment stays identical to the authoritative catalog');
equal(meta.ROE_MISSIONS,pairs,'ROE missions are separate selectable identities');
equal(catalog.version,1,'Equipment file version stays compatible');
equal(catalog.slots,{small:2,large:1,legacy_total:2},'Slot limits retain two-charge legacy support');
equal(catalog.defaults.equipment,{stun:1},'New gear does not replace default flashbang');
equal(catalog.equipment.map(item=>item.id),['stun','smoke','breach','probe_c1','frag'],'Frag appends after the original tools');
const frag=catalog.equipment.at(-1);
equal([frag.slot,frag.weight,frag.stars],['small',0.4,0],'One frag uses one small slot and is available without an unlock');
truth(!Object.hasOwn(frag,'model'),'No new external model dependency');
for(const key of ['label','label_en','note','note_en'])truth(typeof frag[key]==='string'&&frag[key].length>0,`Frag has ${key}`);
const campaign=meta.newCampaign(),original=structuredClone(campaign);
const profile=meta.progressionState([]);
for(const id of pairs){
  equal(meta.missionBase(id),id,'Pair cannot count as campaign M01');
  equal(meta.isProgressionMission(id),false,'Comparison pair cannot farm campaign unlocks');
  equal(meta.missionAccess(id,profile).unlocked,true,'Both comparison operations are immediately selectable');
  truth(!meta.CAMPAIGN_MISSIONS.includes(meta.missionBase(id)),'Pair stays outside the campaign sequence');
  for(const difficulty of ['normal','challenge'])for(const variant of ['standard',...meta.VARIANTS.map(item=>item.id)]){
    equal(meta.missionId(id,difficulty,variant),id,'Difficulty or legacy variant controls cannot replace an ROE identity');
  }
  equal(meta.progressionProblem({map_id:id,loadout:{alpha:{equipment:{frag:1}}}},profile),null,'ROE frag requires no extra unlock');
}
equal(campaign,original,'Pair metadata does not alter existing campaign fields');
equal(meta.missionBase('M01_HOSTAGE'),'M01','Legacy variant base stays unchanged');
equal(meta.missionId('M01H','challenge','escort'),'M01_ESCORT','Legacy variant resolution stays unchanged');
equal(meta.missionId('M09','challenge','escort'),'M09H','Expanded map challenge stays unchanged');
equal(meta.missionId('H36','challenge','escort'),'H36','Historical IDs stay unchanged');
const options={seed:1049,variant:'normal',modifiers:[],loadout:{alpha:{weapon:'standard',equipment:{stun:1}}},roster:[]};
const precisionKey=meta.conditionKey({...options,mission:pairs[0]}),highKey=meta.conditionKey({...options,mission:pairs[1]});
truth(precisionKey!==highKey,'Same seed/gear pair records remain separate');
truth(precisionKey!==meta.conditionKey({...options,mission:'M01'}),'Comparison does not overwrite the original house record');
equal(meta.conditionKey({...options,mission:pairs[0]}),precisionKey,'Identical pair conditions have a stable record key');
const preparation={roster:[{id:'raven',base_id:'alpha',trait:'breacher'}],loadout:{alpha:{weapon:'standard',equipment:{stun:1}}}};
for(const [equipment,expected] of [
  [{frag:1,stun:1},{stun:1,frag:1}],
  [['frag','stun'],{stun:1,smoke:0,breach:0,frag:1}],
  [['frag','frag'],{stun:0,smoke:0,breach:0,frag:2}],
  [['stun','breach'],{stun:1,smoke:0,breach:1}],
  [{breach:2},{breach:2}],
  [{frag:0},{frag:0}],
  [{frag:20,unknown:1},{frag:2}],
  [{frag:NaN},{frag:0}],
  [{frag:Infinity},{frag:0}],
  [{frag:'1'},{frag:0}],
]){
  const plan={map_id:pairs[1],loadout:{alpha:{equipment}}},before=structuredClone(plan);
  const result=meta.normalizeCampaignPlan(plan,preparation,campaign);
  equal(result.map_id,pairs[1],'Plan normalization preserves the exact ROE map ID');
  equal(result.loadout.alpha.equipment,expected,'Frag and legacy tool counts normalize without extra legacy keys');
  equal(plan,before,'Plan normalization owns its output');
}
equal(meta.normalizeCampaignPlan({loadout:{}},preparation,campaign).loadout.alpha.equipment,{stun:1},'Absent equipment keeps the existing one-flash default');
equal(meta.newCampaign(),original,'Catalog changes do not add inventory or alter campaign defaults');
console.log(`ROE catalog: ${checks} checks passed`);
