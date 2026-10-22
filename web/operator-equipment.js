import {CATALOG} from './meta.js';

export {CATALOG};
export const ARMORS=CATALOG.armor, HELMETS=CATALOG.helmets, ATTACHMENTS=CATALOG.attachments;
export const SIDEARMS=CATALOG.sidearms, PRESETS=CATALOG.presets;
const clone=value=>JSON.parse(JSON.stringify(value));
const own=(object,key)=>Object.prototype.hasOwnProperty.call(object,key);
const safeObject=value=>value&&typeof value==='object'&&!Array.isArray(value);
const cleanText=(value,max)=>typeof value==='string'?value.replace(/[\u0000-\u001f\u007f]/g,'').trim().slice(0,max):'';
const item=(list,id,fallback)=>list.some(entry=>entry.id===id)?id:fallback;

/** Migration accepts former single-tool strings and arrays without losing empty slots. */
export function normalizeOperatorLoadout(raw={}, {fresh=true}={}) {
  if(!safeObject(raw))raw={};
  const result=clone(CATALOG.defaults);
  if(!fresh)result.sidearm=result.armor=result.helmet='none';
  result.weapon=item(CATALOG.weapons,raw.weapon,result.weapon);
  for(const [field,list] of [['sidearm',SIDEARMS],['armor',ARMORS],['helmet',HELMETS]]) {
    if(own(raw,field))result[field]=raw[field]==='none'?'none':item(list,raw[field],result[field]);
  }
  if(own(raw,'equipment')){
    let tools=raw.equipment;
    if(typeof tools==='string')tools=tools==='none'?{}:{[tools]:1};
    // Preserve the four legacy zero-count keys; new frag keys belong only
    // to profiles that actually selected this newly added equipment.
    if(Array.isArray(tools))tools=Object.fromEntries(CATALOG.equipment.filter(entry=>entry.id!=='frag'||tools.includes('frag')).map(entry=>[entry.id,tools.filter(id=>id===entry.id).length]));
    result.equipment={};
    let small=0,large=0;
    const valid=CATALOG.equipment.map(entry=>({entry,count:Number.isFinite(tools?.[entry.id])?Math.max(0,Math.min(2,Math.trunc(tools[entry.id]))):0}));
    const legacy=valid.reduce((sum,{count})=>sum+count,0)<=CATALOG.slots.legacy_total;
    for(const {entry,count} of valid){
      const used=entry.slot==='large'?large:small;
      const limit=entry.slot==='large'?(legacy?2:CATALOG.slots.large):CATALOG.slots.small;
      const kept=Math.min(count,Math.max(0,limit-used));
      if(kept>0||safeObject(tools)&&own(tools,entry.id))result.equipment[entry.id]=kept;
      if(entry.slot==='large')large+=kept;else small+=kept;
    }
  }
  const slots=new Set();
  result.attachments=[];
  for(const attachment of ATTACHMENTS){
    if(Array.isArray(raw.attachments)&&raw.attachments.includes(attachment.id)&&attachment.weapons.includes(result.weapon)&&!slots.has(attachment.slot)){
      result.attachments.push(attachment.id);slots.add(attachment.slot);
    }
  }
  const appearance=safeObject(raw.appearance)?raw.appearance:{};
  result.appearance={name:cleanText(appearance.name,48),callsign:cleanText(appearance.callsign,32),color:/^#[0-9a-fA-F]{6}$/.test(appearance.color||'')?appearance.color.toLowerCase():result.appearance.color,patch:CATALOG.appearance.patches.includes(appearance.patch)?appearance.patch:result.appearance.patch};
  result.preset=raw.preset==='custom'||PRESETS.some(preset=>preset.id===raw.preset)?raw.preset:'custom';
  return result;
}

export function applyOperatorPreset(raw,presetId){
  const previous=normalizeOperatorLoadout(raw),preset=PRESETS.find(entry=>entry.id===presetId);
  return preset?normalizeOperatorLoadout({...previous,...clone(preset.loadout),appearance:previous.appearance,preset:preset.id}):previous;
}

export function weaponStats(id,attachments=[]){
  const definition=[...CATALOG.weapons,...SIDEARMS].find(entry=>entry.id===id)||CATALOG.weapons[0];
  const stats={...definition.stats,id:definition.id,label:definition.label,label_en:definition.label_en,model:definition.model,weight:definition.weight};
  const slots=new Set();
  for(const attachment of ATTACHMENTS){
    if(!attachments.includes(attachment.id)||!attachment.weapons.includes(definition.id)||slots.has(attachment.slot))continue;
    slots.add(attachment.slot);stats.weight+=attachment.weight;
    for(const [modifier,value] of Object.entries(attachment.modifiers)){
      if(modifier.endsWith('_add')){const key=modifier.slice(0,-4);stats[key]=(stats[key]||0)+value;}
      else if(modifier.endsWith('_multiplier')){const key=modifier.slice(0,-11);stats[key]=(stats[key]||0)*value;}
    }
  }
  stats.accuracy=Math.min(.99,Math.max(0,stats.accuracy));
  stats.ammo=Math.trunc(stats.ammo);
  return stats;
}

/** Uses the same modifier order and bounded stats as equipment_catalog.gd. */
export function deriveLoadoutStats(raw,{trait=''}={}){
  const loadout=normalizeOperatorLoadout(raw,{fresh:false}),weapon=weaponStats(loadout.weapon,loadout.attachments);
  const armor=ARMORS.find(entry=>entry.id===loadout.armor)||{id:'none',weight:0,panels:[],movement_multiplier:1,action_multiplier:1};
  const helmet=HELMETS.find(entry=>entry.id===loadout.helmet)||{id:'none',weight:0,resistance:0,reduction:0};
  const sidearm=SIDEARMS.find(entry=>entry.id===loadout.sidearm),tools=CATALOG.equipment.reduce((sum,entry)=>sum+entry.weight*(loadout.equipment[entry.id]||0),0);
  const stats={...weapon,normal_moving_accuracy:weapon.accuracy*CATALOG.friendly_movement_accuracy.normal,weight:weapon.weight+armor.weight+helmet.weight+(sidearm?.weight||0)+tools,weapon_weight:weapon.weight,movement_multiplier:(armor.movement_multiplier||1)*(helmet.movement_multiplier||1),action_multiplier:(armor.action_multiplier||1)*(helmet.action_multiplier||1),armor:clone(armor),helmet:clone(helmet),sidearm_stats:sidearm?weaponStats(sidearm.id):{},loadout};
  const lengthFactor=1+Math.max(0,weapon.length-CATALOG.handling.reference_length)*CATALOG.handling.length_aim_penalty;
  stats.final_aim_time=weapon.aim_time*lengthFactor*stats.action_multiplier;
  stats.final_reload_time=weapon.reload*stats.action_multiplier;
  stats.primary_switch_time=weapon.switch_time*stats.action_multiplier;
  stats.secondary_switch_time=(stats.sidearm_stats.switch_time||0)*stats.action_multiplier;
  const effects=CATALOG.traits[trait||raw?.trait||'']||{};
  stats.range=weapon.range+(effects.range_add||0);
  stats.interval=weapon.interval*(effects.interval_multiplier||1);
  return stats;
}

export function updateOperatorProfile(profiles,rosterId,choice){
  if(!/^[A-Za-z][A-Za-z0-9_-]{0,63}$/.test(rosterId))throw new Error('대원 ID가 올바르지 않습니다.');
  return {...profiles,[rosterId]:normalizeOperatorLoadout(choice)};
}

/** Identity belongs to the roster, deployment keys belong to the current mission slots. */
export function deploymentLoadout(roster,profiles={},legacyLoadout={}){
  return Object.fromEntries(roster.map(member=>{
    const base=member.base_id||member.id,profile=profiles[member.id];
    return [base,profile?normalizeOperatorLoadout(profile):normalizeOperatorLoadout(legacyLoadout[base]||legacyLoadout[member.id]||{},{fresh:false})];
  }));
}

export const normalizeProfile=normalizeOperatorLoadout;
export const deriveStats=deriveLoadoutStats;
export const applyPreset=applyOperatorPreset;
