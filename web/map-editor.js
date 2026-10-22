// The editor stores the same mission document consumed by Godot. No account or
// server is involved; validation here complements the authoritative nav check.
export const EDITOR_GROUPS = Object.freeze(['rooms', 'walls', 'doors', 'props', 'units', 'enemies', 'civilians']);
export const PROP_TYPES = Object.freeze(['table', 'desk', 'sofa', 'bed', 'cabinet', 'bookshelf', 'plant', 'chair', 'crate', 'rug', 'vehicle', 'pillar']);
export const ENEMY_STRENGTHS = Object.freeze(['weak', 'medium', 'strong']);
export const ENEMY_TYPES = Object.freeze(['normal', 'sentry', 'rusher', 'hostage_taker']);
export const MATERIALS = Object.freeze(['wood','concrete','metal','fabric','glass','masonry','plaster','foliage','steel','drywall','brick','cloth']);
export const FLOOR_SURFACES = Object.freeze(['concrete','tile','wood','carpet','gravel']);
const RULE_TYPES = new Set(['neutralize_all', 'secure_all_civilians', 'reach_zone', 'before_alert', 'time_limit', 'escort_to_zone', 'no_civilian_loss']);
const MAX_COUNTS = {rooms:64, walls:512, doors:64, props:512, units:4, enemies:32, civilians:32};
const RECT_GROUPS = new Set(['rooms', 'walls', 'doors', 'props']);
const RECT_FIELDS = ['id','x','z','w','d'];
const GEOMETRY_FIELDS = ['height','base_height','material','opacity','resistance','opaque','penetration_resistance'];
const ACTOR_FIELDS = ['stance','movement_mode','hold_position','reserve_ammo','body_facing','aim_progress','injury','injury_status','mobility_multiplier','velocity_x','velocity_z','awareness_state','awareness_confidence','observation_source','exposure','aim_state','action_multiplier','reload_duration','weapon_height'];
const MISSION_FIELDS = ['schema_version','id','revision','title','seed','bounds','focus',...EDITOR_GROUPS,'objectives','briefing','subtitle','description','title_en','description_en','win','fail','stars','variant','modifiers','default_seed','base_id','challenge','custom','loadout','roster','environment'];
const ENTITY_FIELDS = {
  rooms:[...RECT_FIELDS,'label','color','indoor','lighting','floor_surface'], walls:[...RECT_FIELDS,'thin',...GEOMETRY_FIELDS],
  doors:[...RECT_FIELDS,'axis','label','state','swing_sign','hinge_side','locked','hp','durability','destroyed','progress','initial_states',...GEOMETRY_FIELDS], props:[...RECT_FIELDS,'type','rotation','solid','cover',...GEOMETRY_FIELDS],
  units:['id','name','role','x','z','facing','weapon','hp','ammo','stuns','smokes','breaches','charges','vision_range','fov','trait','roster_id','base_id','equipment',...ACTOR_FIELDS],
  enemies:['id','name','x','z','facing','weapon','hp','ammo','vision_range','fov','patrol','target','passive','training','strength','enemy_type','response_role','spawns',...ACTOR_FIELDS],
  civilians:['id','name','x','z','facing','hp','secured',...ACTOR_FIELDS]
};
const ID = /^[A-Za-z][A-Za-z0-9_-]{0,63}$/;
const finite = value => typeof value === 'number' && Number.isFinite(value);
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const clone = value => JSON.parse(JSON.stringify(value));
const escapeHTML = value => String(value).replace(/[&<>"']/g, c => ({'&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;'}[c]));
const DEFAULT_COVER = {table:'low', desk:'low', sofa:'low', bed:'low', cabinet:'full', bookshelf:'full', plant:'none', chair:'none', crate:'low', rug:'none',vehicle:'full',pillar:'full'};
const PROP_HEIGHTS = {table:.74,desk:.74,sofa:.86,bed:.77,cabinet:1.3,bookshelf:1.3,plant:1.1,chair:.92,crate:.68,rug:.025,vehicle:1.65,pillar:2.8};

/** Godot +Y rotation appears as a negative angle on the x/z editor plane. */
export function editorFootprint(entry) {
  const angle=-(entry.rotation||0),cos=Math.cos(angle),sin=Math.sin(angle);
  const axes=[[cos,sin],[-sin,cos]],half=[entry.w/2,entry.d/2];
  const extent=[Math.abs(cos)*half[0]+Math.abs(sin)*half[1],Math.abs(sin)*half[0]+Math.abs(cos)*half[1]];
  return {axes,half,extent};
}
export function editorRectOverlap(a,b) {
  const first=editorFootprint(a),second=editorFootprint(b),delta=[b.x-a.x,b.z-a.z];
  const dot=(p,q)=>p[0]*q[0]+p[1]*q[1];
  return [...first.axes,...second.axes].every(axis=>{
    const span=first.half.reduce((n,r,i)=>n+r*Math.abs(dot(first.axes[i],axis)),0)+second.half.reduce((n,r,i)=>n+r*Math.abs(dot(second.axes[i],axis)),0);
    return span-Math.abs(dot(delta,axis))>1e-6;
  });
}

export function createEditorMission() {
  return {
    schema_version:1, id:'EDIT_CUSTOM', revision:1, title:'나의 작전', subtitle:'SHARED TACTICAL PUZZLE',
    description:'지도와 목표를 편집하고 파일로 같은 조건의 퍼즐을 공유하세요.', seed:1049,
    bounds:[16,12], focus:[8,6],environment:{time_of_day:'day',lighting:1},
    rooms:[{id:'room_1', label:'01 / ROOM', x:8, z:6, w:14, d:10, color:'#656c64',indoor:true,lighting:1,floor_surface:'tile'}],
    walls:[], doors:[], props:[],
    units:[{id:'alpha', name:'ALPHA', role:'선봉', x:3, z:9, facing:-Math.PI/2, weapon:'standard'}],
    enemies:[{id:'enemy_1', name:'무장 인원', strength:'weak', enemy_type:'normal', x:11, z:3, facing:Math.PI/2}],
    civilians:[], objectives:['모든 위협을 무력화하세요.'],
    win:[{type:'neutralize_all'}, {type:'secure_all_civilians'}], fail:[{type:'no_civilian_loss'}],
    stars:[{id:'single_plan', label:'단일 계획', stat:'plan_revisions', op:'eq', value:0}]
  };
}

/** Structural safety only: real navigation is checked by Godot on play/import. */
export function validateEditorMission(data) {
  const errors = [];
  const check = (condition, path, message) => {if (!condition) errors.push(`${path}: ${message}`);};
  if (!object(data)) return {valid:false, errors:['임무: JSON 객체가 필요합니다.']};
  check(Object.keys(data).every(key=>MISSION_FIELDS.includes(key)),'mission','지원하지 않는 필드가 있습니다.');
  check(data.schema_version === 1, 'schema_version', '지원하는 버전은 1입니다.');
  check(typeof data.id === 'string' && ID.test(data.id), 'id', '영문으로 시작하는 1–64자의 고유 ID가 필요합니다.');
  check(Number.isInteger(data.revision) && data.revision >= 1, 'revision', '1 이상의 정수가 필요합니다.');
  check(typeof data.title === 'string' && data.title.length > 0 && data.title.length <= 128, 'title', '1–128자의 제목이 필요합니다.');
  check(Number.isInteger(data.seed) && data.seed >= 0 && data.seed<=2147483647, 'seed', '0–2147483647의 정수가 필요합니다.');
  const validBounds = Array.isArray(data.bounds) && data.bounds.length === 2 && data.bounds.every(n => finite(n) && n >= 1 && n <= 32);
  check(validBounds, 'bounds', '지도 크기는 각각 1–32m이어야 합니다.');
  if (!validBounds) return {valid:false, errors};
  function point(value, path) {
    const valid = Array.isArray(value) && value.length === 2 && value.every(finite);
    check(valid, path, '[x,z] 좌표가 필요합니다.');
    if (valid) check(value[0] >= 0 && value[1] >= 0 && value[0] <= data.bounds[0] && value[1] <= data.bounds[1], path, '좌표가 지도 밖입니다.');
    return valid;
  }
  point(data.focus, 'focus');
  if ('environment' in data) {
    check(object(data.environment),'environment','조명 환경 객체가 필요합니다.');
    if (object(data.environment)) {
      check(Object.keys(data.environment).every(key=>['time_of_day','lighting'].includes(key)),'environment','지원하지 않는 환경 필드가 있습니다.');
      if ('time_of_day' in data.environment) check(['day','dim','night'].includes(data.environment.time_of_day),'environment.time_of_day','day, dim, night 중 하나입니다.');
      if ('lighting' in data.environment) check(finite(data.environment.lighting)&&data.environment.lighting>=0&&data.environment.lighting<=1,'environment.lighting','조명은 0–1입니다.');
    }
  }
  check(Array.isArray(data.objectives) && data.objectives.length >= 1 && data.objectives.length <= 16 && data.objectives.every(v => typeof v === 'string' && v.length > 0 && v.length <= 500), 'objectives', '1–16개의 목표 문구가 필요합니다.');
  const ids = new Set();
  const actors = [];
  for (const group of EDITOR_GROUPS) {
    const entries = data[group];
    if (!Array.isArray(entries)) {errors.push(`${group}: 배열이 필요합니다.`); continue;}
    check(entries.length <= MAX_COUNTS[group], group, `최대 ${MAX_COUNTS[group]}개까지 배치할 수 있습니다.`);
    if (group === 'units' || group === 'rooms') check(entries.length > 0, group, '최소 1개가 필요합니다.');
    entries.forEach((entry,index) => {
      const path = `${group}[${index}]`;
      if (!object(entry)) {errors.push(`${path}: 객체가 필요합니다.`); return;}
      check(Object.keys(entry).every(key=>ENTITY_FIELDS[group].includes(key)), path, '지원하지 않는 필드가 있습니다.');
      check(typeof entry.id === 'string' && ID.test(entry.id), `${path}.id`, '유효한 영문 ID가 필요합니다.');
      check(!ids.has(entry.id), `${path}.id`, '임무 안에서 ID가 중복됩니다.');
      ids.add(entry.id);
      point([entry.x,entry.z], path);
      if (RECT_GROUPS.has(group)) {
        check(finite(entry.w) && finite(entry.d) && entry.w > 0 && entry.d > 0 && entry.w <= 32 && entry.d <= 32, path, '가로·세로 크기는 0 초과 32 이하입니다.');
        if ([entry.x,entry.z,entry.w,entry.d].every(finite)) {
          const {extent}=editorFootprint(entry);
          check(entry.x-extent[0] >= -1e-6 && entry.z-extent[1] >= -1e-6 && entry.x+extent[0] <= data.bounds[0]+1e-6 && entry.z+extent[1] <= data.bounds[1]+1e-6, path, '직사각형이 지도 밖으로 나갑니다.');
        }
      } else actors.push({entry,path});
      for (const key of ['facing','rotation','body_facing']) if (key in entry) check(finite(entry[key]), `${path}.${key}`, '유한한 각도가 필요합니다.');
      for (const key of ['name','label','role']) if (key in entry) check(typeof entry[key] === 'string' && entry[key].length > 0 && entry[key].length <= 128, `${path}.${key}`, '1–128자의 문구가 필요합니다.');
      if ('hp' in entry) check(finite(entry.hp) && entry.hp >= (group==='doors'?0:.1) && entry.hp <= 1000, `${path}.hp`, '체력 범위를 벗어났습니다.');
      for(const key of ['height','base_height','weapon_height']) if(key in entry)check(finite(entry[key])&&entry[key]>=0&&entry[key]<=8,`${path}.${key}`,'높이는 0–8입니다.');
      for(const key of ['lighting','opacity','progress','aim_progress','mobility_multiplier','awareness_confidence','exposure']) if(key in entry)check(finite(entry[key])&&entry[key]>=0&&entry[key]<=1,`${path}.${key}`,'0–1의 유한 수치가 필요합니다.');
      for(const key of ['resistance','durability','penetration_resistance'])if(key in entry)check(finite(entry[key])&&entry[key]>=0&&entry[key]<=1000,`${path}.${key}`,'0–1000의 유한 수치가 필요합니다.');
      for(const key of ['solid','thin','secured','target','training','passive','hold_position','locked','destroyed','indoor','opaque'])if(key in entry)check(typeof entry[key]==='boolean',`${path}.${key}`,'참/거짓 값이 필요합니다.');
      for(const key of ['ammo','stuns','smokes','breaches','charges','reserve_ammo'])if(key in entry)check(Number.isInteger(entry[key])&&entry[key]>=0&&entry[key]<=(key==='reserve_ammo'?10000:key==='ammo'?32:8),`${path}.${key}`,'장비 수량은 범위 안의 정수여야 합니다.');
      if('material' in entry)check(MATERIALS.includes(entry.material),`${path}.material`,'알 수 없는 재질입니다.');
      if('floor_surface' in entry)check(FLOOR_SURFACES.includes(entry.floor_surface),`${path}.floor_surface`,'알 수 없는 바닥 재질입니다.');
      if('stance' in entry)check(['standing','crouched'].includes(entry.stance),`${path}.stance`,'standing 또는 crouched입니다.');
      if('movement_mode' in entry)check(['careful','normal','fast'].includes(entry.movement_mode),`${path}.movement_mode`,'careful, normal, fast 중 하나입니다.');
      for(const key of ['velocity_x','velocity_z'])if(key in entry)check(finite(entry[key])&&Math.abs(entry[key])<=32,`${path}.${key}`,'속도는 -32–32입니다.');
      if('action_multiplier' in entry)check(finite(entry.action_multiplier)&&entry.action_multiplier>=1&&entry.action_multiplier<=4,`${path}.action_multiplier`,'행동 배율은 1–4입니다.');
      if('reload_duration' in entry)check(finite(entry.reload_duration)&&entry.reload_duration>=0&&entry.reload_duration<=600,`${path}.reload_duration`,'재장전 시간은 0–600입니다.');
      for(const key of ['injury','injury_status'])if(key in entry)check(['none','hurt','wounded'].includes(entry[key]),`${path}.${key}`,'알 수 없는 부상 상태입니다.');
      if('aim_state' in entry)check(['idle','acquiring','ready','lowered'].includes(entry.aim_state),`${path}.aim_state`,'알 수 없는 조준 상태입니다.');
      if('awareness_state' in entry)check(['UNAWARE','DETECTED','IDENTIFIED','TRACKING','SUSPICIOUS'].includes(entry.awareness_state),`${path}.awareness_state`,'알 수 없는 인지 상태입니다.');
      if('observation_source' in entry)check(['none','sight','sound','report'].includes(entry.observation_source),`${path}.observation_source`,'알 수 없는 관측 출처입니다.');
      if('response_role' in entry)check(['guard','patrol','reserve'].includes(entry.response_role),`${path}.response_role`,'알 수 없는 대응 역할입니다.');
      if('color' in entry)check(typeof entry.color==='string'&&/^#[0-9a-f]{6}$/i.test(entry.color),`${path}.color`,'#RRGGBB 색상이 필요합니다.');
      if ('weapon' in entry) check(['standard','light','shotgun','suppressed'].includes(entry.weapon), `${path}.weapon`, '알 수 없는 무기입니다.');
      if (group === 'units') for (const key of ['name','role','facing','weapon']) check(key in entry, `${path}.${key}`, '대원에 필요한 필드입니다.');
      if (group === 'props') {
        check(PROP_TYPES.includes(entry.type), `${path}.type`, '알 수 없는 가구 종류입니다.');
        check('cover' in entry || 'solid' in entry || entry.type in DEFAULT_COVER, `${path}.solid`, '이동 차단 분류가 필요합니다.');
        if ('cover' in entry) check(['none','low','full'].includes(entry.cover), `${path}.cover`, '엄폐는 none, low, full입니다.');
        if ('rotation' in entry && finite(entry.rotation)) check(Math.abs(entry.rotation/(Math.PI/2)-Math.round(entry.rotation/(Math.PI/2))) < 1e-5, `${path}.rotation`, '가구는 90도 단위로 회전합니다.');
      }
      if (group === 'walls' && 'thin' in entry) check(typeof entry.thin === 'boolean', `${path}.thin`, '관통 여부는 참/거짓입니다.');
      if (group === 'doors') {
        check(['x','z'].includes(entry.axis), `${path}.axis`, '문 방향은 x 또는 z입니다.');
        check(!('state' in entry) || ['OPEN','CLOSED','AJAR','DESTROYED'].includes(entry.state), `${path}.state`, '문 상태가 올바르지 않습니다.');
        for(const key of ['swing_sign','hinge_side'])if(key in entry)check(finite(entry[key])&&Math.abs(entry[key])===1,`${path}.${key}`,'-1 또는 1입니다.');
        if(entry.state==='AJAR'&&'progress' in entry)check(entry.progress>0&&entry.progress<1,`${path}.progress`,'부분 개방은 0과 1 사이입니다.');
        if('initial_states' in entry)check(Array.isArray(entry.initial_states)&&entry.initial_states.length>0&&entry.initial_states.length<=3&&entry.initial_states.every(state=>['OPEN','CLOSED','AJAR'].includes(state)),`${path}.initial_states`,'1–3개의 초기 문 상태 후보가 필요합니다.');
        const span = entry.axis === 'x' ? entry.w : entry.d, thickness = entry.axis === 'x' ? entry.d : entry.w;
        check(finite(span) && span > Math.max(thickness,0.46), path, '문 폭이 대원이 통과하기에 너무 작습니다.');
      }
      if (group === 'enemies') {
        if ('strength' in entry) check(['weak','medium','strong'].includes(entry.strength), `${path}.strength`, '알 수 없는 적 전투 등급입니다.');
        if ('enemy_type' in entry) check([...ENEMY_TYPES,'guard'].includes(entry.enemy_type), `${path}.enemy_type`, '알 수 없는 적 유형입니다.');
        function patrol(value, subpath) {
          check(Array.isArray(value) && value.length <= 64, subpath, '최대 64개의 순찰 좌표를 넣을 수 있습니다.');
          if (Array.isArray(value)) value.forEach((p,i) => point(p,`${subpath}[${i}]`));
        }
        if ('patrol' in entry) patrol(entry.patrol,`${path}.patrol`);
        if ('spawns' in entry) {
          check(Array.isArray(entry.spawns) && entry.spawns.length > 0 && entry.spawns.length <= 8, `${path}.spawns`, '1–8개의 등장 후보가 필요합니다.');
          if (Array.isArray(entry.spawns)) entry.spawns.forEach((spawn,i) => {
            const p = `${path}.spawns[${i}]`;
            if (!object(spawn)) {errors.push(`${p}: 객체가 필요합니다.`); return;}
            check(Object.keys(spawn).every(key=>['x','z','facing','patrol'].includes(key)),p,'지원하지 않는 등장 후보 필드가 있습니다.');
            point([spawn.x,spawn.z],p);
            check(finite(spawn.facing), `${p}.facing`, '유한한 각도가 필요합니다.');
            if ('patrol' in spawn) patrol(spawn.patrol,`${p}.patrol`);
          });
        }
      }
    });
  }
  const blockers=[...(Array.isArray(data.walls)?data.walls:[]),...(Array.isArray(data.props)?data.props:[]).filter(prop=>object(prop)&&(prop.cover||(prop.solid?'full':DEFAULT_COVER[prop.type]))!=='none')].filter(entry=>object(entry)&&[entry.x,entry.z,entry.w,entry.d].every(finite));
  const doors=(Array.isArray(data.doors)?data.doors:[]).filter(entry=>object(entry)&&[entry.x,entry.z,entry.w,entry.d].every(finite));
  for(let i=0;i<doors.length;i++) {
    for(const obstacle of blockers)check(!editorRectOverlap(doors[i],obstacle),doors[i].id,`출입구가 장애물 ${obstacle.id}와 겹칩니다.`);
    for(let j=i+1;j<doors.length;j++)check(!editorRectOverlap(doors[i],doors[j]),doors[i].id,'출입구가 겹칩니다.');
  }
  for (const field of ['win','fail']) {
    if (!(field in data)) continue; // v1 documents retain the original objectives.
    check(Array.isArray(data[field]) && data[field].length <= 16 && (field !== 'win' || data[field].length > 0), field, '최대 16개의 목표 규칙을 넣을 수 있습니다.');
    if (!Array.isArray(data[field])) continue;
    data[field].forEach((rule,i) => {
      const path = `${field}[${i}]`;
      if (!object(rule)) {errors.push(`${path}: 규칙 객체가 필요합니다.`); return;}
      check(RULE_TYPES.has(rule.type), `${path}.type`, '알 수 없는 목표 규칙입니다.');
      if (['reach_zone','escort_to_zone'].includes(rule.type)) {
        const zone = rule.zone;
        const valid = Array.isArray(zone) && zone.length === 4 && zone.every(finite) && zone[2] > 0 && zone[3] > 0;
        check(valid, `${path}.zone`, '[중심 x, 중심 z, 가로, 세로] 구역이 필요합니다.');
        if (valid) check(zone[0]-zone[2]/2 >= 0 && zone[1]-zone[3]/2 >= 0 && zone[0]+zone[2]/2 <= data.bounds[0] && zone[1]+zone[3]/2 <= data.bounds[1], `${path}.zone`, '목표 구역이 지도 밖입니다.');
      }
      const allowed=['type',...(['reach_zone','escort_to_zone'].includes(rule.type)?['zone']:rule.type==='time_limit'?['seconds']:[])];
      check(Object.keys(rule).every(key=>allowed.includes(key)),path,'지원하지 않는 규칙 필드가 있습니다.');
      if (rule.type === 'time_limit') check(finite(rule.seconds) && rule.seconds > 0 && rule.seconds <= 3600, `${path}.seconds`, '제한 시간은 0 초과 3600 이하입니다.');
    });
  }
  if ('stars' in data) {
    check(Array.isArray(data.stars) && data.stars.length <= 16, 'stars', '최대 16개의 별 과제를 넣을 수 있습니다.');
    const starIds = new Set(), stats = new Set(['plan_revisions','stuns_used','hits_taken','units_deployed','reloads','kills','arrests','shots_fired','command_failures','losses','time','duration','civilian_losses']);
    if (Array.isArray(data.stars)) data.stars.forEach((star,i) => {
      const path = `stars[${i}]`;
      if (!object(star)) {errors.push(`${path}: 과제 객체가 필요합니다.`); return;}
      check(typeof star.id === 'string' && ID.test(star.id) && !starIds.has(star.id), `${path}.id`, '중복 없는 과제 ID가 필요합니다.');
      starIds.add(star.id);
      check(typeof star.label === 'string' && star.label.length > 0 && star.label.length <= 128, `${path}.label`, '과제 이름이 필요합니다.');
      if ('type' in star) {
        check(['completion','survivors','par_time'].includes(star.type),`${path}.type`,'알 수 없는 기존 메달 종류입니다.');
        check(!('stat' in star) && !('op' in star),path,'기존 메달에는 stat/op를 함께 넣을 수 없습니다.');
        if(star.type==='par_time') check(finite(star.value) && star.value>0,`${path}.value`,'목표 시간이 필요합니다.');
      } else {
        check(stats.has(star.stat), `${path}.stat`, '알 수 없는 결과 통계입니다.');
        check(['eq','lte'].includes(star.op) && finite(star.value) && star.value>=0, path, 'eq/lte 연산자와 0 이상의 기준값이 필요합니다.');
      }
    });
  }
  // Do not imply reachability: the map can still have disconnected rooms.
  for (let i=0;i<actors.length;i++) for (let j=i+1;j<actors.length;j++) {
    const a=actors[i], b=actors[j];
    if ([a.entry.x,a.entry.z,b.entry.x,b.entry.z].every(finite)) check(Math.hypot(a.entry.x-b.entry.x,a.entry.z-b.entry.z) >= 0.46, `${a.path}, ${b.path}`, '인물 출발점이 겹칩니다.');
  }
  return {valid:errors.length === 0, errors};
}

export function parseEditorMission(text) {
  if (typeof text !== 'string' || text.length > 2*1024*1024) throw new Error('임무 파일은 최대 2MB의 JSON 텍스트여야 합니다.');
  const mission = JSON.parse(text);
  const validation = validateEditorMission(mission);
  if (!validation.valid) throw new Error(validation.errors.join('\n'));
  return clone(mission);
}

function nextId(mission,group) {
  const prefix={rooms:'room',walls:'wall',doors:'door',props:'prop',units:'unit',enemies:'enemy',civilians:'civilian'}[group];
  const used=new Set(EDITOR_GROUPS.flatMap(g=>mission[g].map(e=>e.id)));
  let n=1; while(used.has(`${prefix}_${n}`)) n++;
  return `${prefix}_${n}`;
}

/** Used by the canvas and by nonvisual authoring checks. */
export function placeEditorEntity(mission,group,x,z,options={}) {
  if (!EDITOR_GROUPS.includes(group)) throw new Error('알 수 없는 배치 도구입니다.');
  if (!finite(x) || !finite(z)) throw new Error('배치 좌표가 올바르지 않습니다.');
  if (mission[group].length >= MAX_COUNTS[group]) throw new Error(`최대 ${MAX_COUNTS[group]}개까지 배치할 수 있습니다.`);
  const entry={id:nextId(mission,group),x,z};
  if (group==='rooms') Object.assign(entry,{w:4,d:4,label:'ROOM',color:'#656c64',indoor:true,lighting:1,floor_surface:'tile'});
  if (group==='walls') Object.assign(entry,{w:3,d:0.24,thin:false,height:2.8,material:'concrete'});
  if (group==='doors') Object.assign(entry,{w:1.8,d:0.24,axis:'x',state:'CLOSED',label:'문',hinge_side:-1,swing_sign:-1,locked:false,hp:100,destroyed:false,height:2.1,material:'wood'});
  if (group==='props') {const type=options.type || 'crate', cover=DEFAULT_COVER[type] || 'low';Object.assign(entry,{w:type==='vehicle'?2:1,d:type==='vehicle'?4.2:1,type,cover,solid:cover!=='none',rotation:0,height:PROP_HEIGHTS[type]||.68,material:type==='vehicle'?'metal':type==='pillar'?'concrete':'wood'});}
  if (group==='units') Object.assign(entry,{name:entry.id.toUpperCase(),role:'대원',facing:-Math.PI/2,weapon:'standard',stance:'standing',movement_mode:'normal',reserve_ammo:72,hold_position:false});
  if (group==='enemies') Object.assign(entry,{name:'무장 인원',strength:'weak',enemy_type:'normal',facing:Math.PI/2,stance:'standing',movement_mode:'normal',reserve_ammo:72,response_role:'guard'});
  if (group==='civilians') Object.assign(entry,{name:'민간인',facing:0});
  Object.assign(entry,options);
  if (RECT_GROUPS.has(group)) {
    entry.w=Math.min(entry.w,mission.bounds[0]);entry.d=Math.min(entry.d,mission.bounds[1]);
    let {extent}=editorFootprint(entry);
    const shrink=Math.min(1,mission.bounds[0]/(2*extent[0]),mission.bounds[1]/(2*extent[1]));
    entry.w*=shrink;entry.d*=shrink;({extent}=editorFootprint(entry));
    entry.x=Math.min(mission.bounds[0]-extent[0],Math.max(extent[0],x));
    entry.z=Math.min(mission.bounds[1]-extent[1],Math.max(extent[1],z));
  } else {
    entry.x=Math.min(mission.bounds[0]-0.24,Math.max(0.24,x));
    entry.z=Math.min(mission.bounds[1]-0.24,Math.max(0.24,z));
  }
  mission[group].push(entry);
  return entry;
}

export function renderMapEditor(mission=createEditorMission()) {
  const tools=[['select','선택·이동'],['rooms','방'],['walls','벽'],['doors','문'],['units','대원'],['enemies','적'],['civilians','민간인'],['props','가구']];
  return `<div class="map-editor"><p class="modal-intro">지도를 클릭해 배치하고 선택·이동 도구로 옮기세요. 자세한 값은 속성이나 JSON에서 수정할 수 있습니다.</p>
    <div class="editor-tools" role="toolbar" aria-label="지도 편집 도구">${tools.map(([tool,label])=>`<button type="button" data-editor-tool="${tool}" aria-pressed="${tool==='select'}" class="secondary${tool==='select'?' active':''}">${label}</button>`).join('')}</div>
    <div class="editor-workspace"><div class="editor-stage"><canvas data-editor-canvas width="640" height="360" tabindex="0" aria-label="편집 지도. 좌우 방향키로 선택한 항목을 이동하고 Delete로 삭제합니다."></canvas><p class="note">0.25m 격자 · 방향키: 이동 · Delete: 삭제 · 빈 바닥: 선택 해제</p></div>
    <div class="editor-inspector"><label>임무 제목 <input data-editor-title value="${escapeHTML(mission.title)}" maxlength="128"></label><label>시드 <input data-editor-seed type="number" min="0" max="2147483647" value="${escapeHTML(mission.seed)}"></label><label>조명 환경 <select data-editor-environment>${['day','dim','night'].map(value=>`<option value="${value}"${(mission.environment?.time_of_day||'day')===value?' selected':''}>${value}</option>`).join('')}</select></label><label>환경 조도 (0–1) <input data-editor-lighting type="number" min="0" max="1" step="0.05" value="${escapeHTML(mission.environment?.lighting??1)}"></label><label>목표 유형 <select data-editor-preset><option value="">현재 규칙 유지</option><option value="clear">무력화·확보</option><option value="stealth">잠입</option><option value="timed">시간 제한</option><option value="escort">호송</option><option value="arrest">체포 작전</option></select></label><div data-editor-properties><p class="note">항목을 선택하면 속성이 나타납니다.</p></div></div></div>
    <details class="editor-json"><summary>임무 JSON 직접 편집</summary><label>전체 임무 데이터<textarea data-editor-json rows="10" spellcheck="false">${escapeHTML(JSON.stringify(mission,null,2))}</textarea></label><button type="button" data-editor-apply class="secondary">JSON 적용</button></details>
    <div data-editor-errors class="editor-errors" role="status" aria-live="polite"></div>
    <input data-editor-file type="file" accept="application/json,.json" hidden>
    <div class="dialog-footer"><button type="button" data-editor-new class="secondary">새 지도</button><button type="button" data-editor-import class="secondary">파일 가져오기</button><button type="button" data-editor-export class="secondary">파일 저장 ↗</button><button type="button" data-editor-play class="primary">이 지도 플레이 →</button></div></div>`;
}

export function bindMapEditor(root,{mission=createEditorMission(),onPlay=()=>{},onExport=()=>{},onImportFile,onChange,toast=()=>{}}={}) {
  let data=clone(mission), tool='select', selected=null, drag=null, jsonDirty=false;
  let drawFrame=null;
  const canvas=root.querySelector('[data-editor-canvas]'), textarea=root.querySelector('[data-editor-json]');
  const ctx=canvas.getContext('2d'), disposers=[];
  const listen=(target,type,handler)=>{target.addEventListener(type,handler);disposers.push(()=>target.removeEventListener(type,handler));};
  const q=selector=>root.querySelector(selector);
  function cancelDraw(){if(drawFrame!==null){cancelAnimationFrame(drawFrame);drawFrame=null;}}
  function scheduleDraw(){if(drawFrame===null)drawFrame=requestAnimationFrame(()=>{drawFrame=null;draw();});}
  function transform() {
    const scale=Math.min((canvas.width-40)/data.bounds[0],(canvas.height-40)/data.bounds[1]);
    return {scale,x:(canvas.width-data.bounds[0]*scale)/2,z:(canvas.height-data.bounds[1]*scale)/2};
  }
  function position(event) {
    const r=canvas.getBoundingClientRect(),t=transform();
    return {x:Math.round(((event.clientX-r.left)*canvas.width/r.width-t.x)/t.scale*4)/4,z:Math.round(((event.clientY-r.top)*canvas.height/r.height-t.z)/t.scale*4)/4};
  }
  function current() {return selected ? data[selected.group]?.find(e=>e.id===selected.id) : null;}
  function draw() {
    if (!ctx) return;
    const t=transform(),s=t.scale;
    ctx.clearRect(0,0,canvas.width,canvas.height);ctx.fillStyle='#151c1b';ctx.fillRect(0,0,canvas.width,canvas.height);
    ctx.save();ctx.translate(t.x,t.z);
    for(let x=0;x<=data.bounds[0];x++){ctx.beginPath();ctx.moveTo(x*s,0);ctx.lineTo(x*s,data.bounds[1]*s);ctx.strokeStyle='#293431';ctx.stroke();}
    for(let z=0;z<=data.bounds[1];z++){ctx.beginPath();ctx.moveTo(0,z*s);ctx.lineTo(data.bounds[0]*s,z*s);ctx.strokeStyle='#293431';ctx.stroke();}
    for(const group of EDITOR_GROUPS) for(const entry of data[group]) {
      const active=selected?.group===group && selected.id===entry.id;
      const colors={rooms:entry.color||'#656c64',walls:'#9b9c8f',doors:entry.state==='OPEN'?'#65ad86':'#dfae61',props:entry.cover==='full'?'#736750':entry.cover==='none'?'#465449':'#a18a62',units:'#89c2bb',enemies:'#dd8e7c',civilians:'#e2d99b'};
      ctx.fillStyle=colors[group];ctx.strokeStyle=active?'#fff2c8':'#171f1b';ctx.lineWidth=active?3:1;
      if(RECT_GROUPS.has(group)) {
        const w=entry.w*s,d=entry.d*s;
        ctx.save();ctx.translate(entry.x*s,entry.z*s);ctx.rotate(-(entry.rotation||0));
        if(group==='rooms') ctx.globalAlpha=.45;
        ctx.fillRect(-w/2,-d/2,w,d);ctx.globalAlpha=1;ctx.strokeRect(-w/2,-d/2,w,d);ctx.restore();
      } else {
        ctx.beginPath();ctx.arc(entry.x*s,entry.z*s,Math.max(5,s*.23),0,Math.PI*2);ctx.fill();ctx.stroke();
        const facing=entry.facing||0;ctx.beginPath();ctx.moveTo(entry.x*s,entry.z*s);ctx.lineTo((entry.x+Math.cos(facing)*.55)*s,(entry.z+Math.sin(facing)*.55)*s);ctx.strokeStyle=active?'#fff2c8':colors[group];ctx.stroke();
      }
      if(group!=='walls'&&group!=='props') {ctx.font='10px sans-serif';ctx.fillStyle='#efeedb';ctx.fillText(entry.label||entry.name||entry.id,entry.x*s+6,entry.z*s-8);}
    }
    for(const rule of data.win||[]) if(Array.isArray(rule.zone)&&rule.zone.length===4) {
      const [x,z,w,d]=rule.zone;ctx.setLineDash([6,4]);ctx.strokeStyle='#b8d8a0';ctx.strokeRect((x-w/2)*s,(z-d/2)*s,w*s,d*s);ctx.setLineDash([]);
    }
    ctx.strokeStyle='#98a19a';ctx.lineWidth=1;ctx.strokeRect(0,0,data.bounds[0]*s,data.bounds[1]*s);ctx.restore();
  }
  function field(key,label,value,options) {
    if(options) return `<label>${label}<select data-editor-field="${key}">${options.map(v=>`<option value="${escapeHTML(v)}"${value===v?' selected':''}>${escapeHTML(key==='strength'?({weak:'약한 적',medium:'중간 적',strong:'강한 적'}[v]):v)}</option>`).join('')}</select></label>`;
    if(typeof value==='boolean') return `<label><input data-editor-field="${key}" type="checkbox"${value?' checked':''}> ${label}</label>`;
    return `<label>${label}<input data-editor-field="${key}" type="${typeof value==='number'?'number':'text'}"${typeof value==='number'?' step="0.25"':''} value="${escapeHTML(value)}"></label>`;
  }
  function inspector() {
    const entry=current();
    if(!entry) {q('[data-editor-properties]').innerHTML='<p class="note">항목을 선택하면 속성이 나타납니다.</p>';return;}
    let html=`<h3>${escapeHTML(selected.group)} / ${escapeHTML(entry.id)}</h3>`;
    for(const [key,label] of [['id','ID'],['x','X 좌표'],['z','Z 좌표'],['w','가로'],['d','세로'],['facing','방향 (rad)'],['name','이름'],['label','표시 이름']]) if(key in entry) html+=field(key,label,entry[key]);
    if(['walls','doors','props'].includes(selected.group)) {html+=field('height','물체 높이 (m)',entry.height??(selected.group==='walls'?2.8:selected.group==='doors'?2.1:PROP_HEIGHTS[entry.type]||.68));html+=field('base_height','바닥에서 높이 (m)',entry.base_height??0);html+=field('material','재질',entry.material||'wood',MATERIALS);html+=field('opacity','불투명도 (0–1)',entry.opacity??1);}
    if(selected.group==='rooms') {html+=field('indoor','실내',entry.indoor??true);html+=field('lighting','방 조도 (0–1)',entry.lighting??1);html+=field('floor_surface','바닥 표면',entry.floor_surface||'tile',FLOOR_SURFACES);}
    if(selected.group==='doors') {html+=field('axis','문 방향',entry.axis,['x','z']);html+=field('state','문 상태',entry.state||'CLOSED',['CLOSED','AJAR','OPEN','DESTROYED']);html+=field('hinge_side','경첩 위치 (-1: 시작, 1: 끝)',entry.hinge_side??-1,[-1,1]);html+=field('swing_sign','회전 방향',entry.swing_sign??-1,[-1,1]);html+=field('locked','잠김',entry.locked??false);html+=field('hp','문 내구도',entry.hp??100);html+=field('destroyed','파손됨',entry.destroyed??false);if(entry.state==='AJAR')html+=field('progress','개방률 (0–1)',entry.progress??.52);}
    if(selected.group==='props') {html+=field('type','가구 종류',entry.type,PROP_TYPES);html+=field('cover','엄폐',entry.cover||(entry.solid?'full':'none'),['none','low','full']);html+=field('rotation','회전 (rad)',entry.rotation||0);}
    if(selected.group==='enemies') {html+=field('strength','전투 등급',entry.strength||'weak',ENEMY_STRENGTHS);html+=field('enemy_type','적 유형',entry.enemy_type==='guard'?'sentry':entry.enemy_type||'normal',ENEMY_TYPES);html+=field('response_role','경계 역할',entry.response_role||'guard',['guard','patrol','reserve']);}
    if(selected.group==='units') html+=field('weapon','무기',entry.weapon,['standard','light','shotgun','suppressed']);
    if(['units','enemies','civilians'].includes(selected.group)) {html+=field('stance','자세',entry.stance||'standing',['standing','crouched']);html+=field('movement_mode','이동 방식',entry.movement_mode||'normal',['careful','normal','fast']);if(selected.group!=='civilians')html+=field('reserve_ammo','예비 탄약',entry.reserve_ammo??72);if(selected.group==='units')html+=field('hold_position','위치 유지',entry.hold_position??false);}
    if(selected.group==='walls') html+=field('thin','사격 관통 허용',entry.thin||false);
    html+='<button type="button" data-editor-delete class="secondary">선택 항목 삭제</button>';
    q('[data-editor-properties]').innerHTML=html;
  }
  function status() {
    const result=validateEditorMission(data),box=q('[data-editor-errors]');
    box.innerHTML=result.valid?'<p class="note">구조 확인 완료. 플레이할 때 이동 경로를 확인합니다.</p>':`<ul>${result.errors.slice(0,8).map(error=>`<li>${escapeHTML(error)}</li>`).join('')}</ul>${result.errors.length>8?`<p>외 ${result.errors.length-8}개 오류</p>`:''}`;
    q('[data-editor-play]').disabled=!result.valid||!!drag;q('[data-editor-export]').disabled=!result.valid||!!drag;
  }
  function refresh({fields=true,notify=true}={}) {
    if(!jsonDirty) textarea.value=JSON.stringify(data,null,2);
    q('[data-editor-title]').value=data.title;q('[data-editor-seed]').value=data.seed;
    q('[data-editor-environment]').value=data.environment?.time_of_day||'day';q('[data-editor-lighting]').value=data.environment?.lighting??1;
    cancelDraw();if(fields) inspector();draw();status();if(notify) onChange?.(clone(data));
  }
  function setMission(next) {
    const validation=validateEditorMission(next);
    if(!validation.valid) throw new Error(validation.errors.join('\n'));
    data=clone(next);selected=null;drag=null;jsonDirty=false;refresh();
  }
  function applyJSON() {setMission(parseEditorMission(textarea.value));toast('임무 JSON을 적용했습니다.');}
  function selectedDelete() {
    if(!selected) return;data[selected.group]=data[selected.group].filter(e=>e.id!==selected.id);selected=null;jsonDirty=false;refresh();
  }
  function preset(value) {
    if(!value) return;
    const zone=[data.bounds[0]-2,data.bounds[1]/2,2,2];
    const base=[{type:'neutralize_all'},{type:'secure_all_civilians'}];
    data.win=value==='stealth'||value==='timed'?[{type:'reach_zone',zone}]:value==='escort'?[{type:'escort_to_zone',zone}]:base;
    data.fail=[{type:'no_civilian_loss'}];
    if(value==='stealth') data.fail.push({type:'before_alert'});
    if(value==='timed') data.fail.push({type:'time_limit',seconds:120});
    const labels={clear:'모든 위협 무력화·민간인 확보',stealth:'경보 전에 목표 구역 도달',timed:'120초 안에 목표 구역 도달',escort:'모든 민간인을 목표 구역으로 호송',arrest:'모든 위협 무력화, 무사살 별 과제'};
    data.variant={clear:'normal',stealth:'infiltration',timed:'timed',escort:'escort',arrest:'arrest'}[value];
    data.objectives=[labels[value]];
    if(value==='arrest') {data.stars ||= [];if(!data.stars.some(s=>s.id==='no_kills')) data.stars.push({id:'no_kills',label:'무사살',stat:'kills',op:'eq',value:0});}
    jsonDirty=false;refresh();
  }
  listen(root,'click',async event=>{
    const button=event.target.closest('button');if(!button||!root.contains(button))return;
    try {
      if(button.dataset.editorTool) {tool=button.dataset.editorTool;root.querySelectorAll('[data-editor-tool]').forEach(b=>{const active=b.dataset.editorTool===tool;b.classList.toggle('active',active);b.setAttribute('aria-pressed',String(active));});return;}
      if(button.hasAttribute('data-editor-delete')) return selectedDelete();
      if(button.hasAttribute('data-editor-new')) return setMission(createEditorMission());
      if(button.hasAttribute('data-editor-import')) return q('[data-editor-file]').click();
      if(button.hasAttribute('data-editor-apply')) return applyJSON();
      if(button.hasAttribute('data-editor-export')||button.hasAttribute('data-editor-play')) {
        if(drag)return;
        if(jsonDirty) applyJSON();
        const validation=validateEditorMission(data);if(!validation.valid) throw new Error(validation.errors[0]);
        if(button.hasAttribute('data-editor-export')) await onExport(clone(data),`breach-mission-${data.id}.json`);
        else await onPlay(clone(data));
      }
    } catch(error) {toast(error.message,'error');}
  });
  listen(root,'change',async event=>{
    const target=event.target;
    try {
      if(target.matches('[data-editor-file]')) {
        const file=target.files?.[0];if(!file)return;if(file.size>2*1024*1024)throw new Error('임무 파일은 최대 2MB입니다.');
        const imported=parseEditorMission(await file.text());setMission(imported);await onImportFile?.(file,clone(imported));toast('임무 파일을 가져왔습니다.');target.value='';return;
      }
      if(target.matches('[data-editor-title]')) data.title=target.value;
      else if(target.matches('[data-editor-seed]')) data.seed=Number(target.value);
      else if(target.matches('[data-editor-environment]')) data.environment={...(data.environment||{}),time_of_day:target.value,lighting:{day:1,dim:.55,night:.25}[target.value]};
      else if(target.matches('[data-editor-lighting]')) data.environment={...(data.environment||{time_of_day:'day'}),lighting:Number(target.value)};
      else if(target.matches('[data-editor-preset]')) return preset(target.value);
      else if(target.dataset.editorField) {
        const entry=current();if(!entry)return;
        const key=target.dataset.editorField;
        entry[key]=target.type==='checkbox'?target.checked:target.type==='number'||['hinge_side','swing_sign'].includes(key)?Number(target.value):target.value;
        if(key==='id')selected.id=entry.id;
        if(selected.group==='props'&&key==='type') {entry.cover=DEFAULT_COVER[entry.type];entry.solid=entry.cover!=='none';entry.height=PROP_HEIGHTS[entry.type];entry.material=entry.type==='vehicle'?'metal':entry.type==='pillar'?'concrete':'wood';}
        if(selected.group==='props'&&key==='cover')entry.solid=entry.cover!=='none';
        if(selected.group==='doors'&&key==='axis') [entry.w,entry.d]=[entry.d,entry.w];
        if(selected.group==='doors'&&key==='state'){entry.progress=entry.state==='OPEN'?1:entry.state==='AJAR'?.52:0;entry.destroyed=entry.state==='DESTROYED';if(entry.destroyed)entry.locked=false;}
      } else return;
      jsonDirty=false;refresh();
    } catch(error) {toast(error.message,'error');}
  });
  listen(textarea,'input',()=>{jsonDirty=true;});
  function pick(p) {
    for(const group of ['units','enemies','civilians','doors','props','walls','rooms']) for(const entry of [...data[group]].reverse()) {
      const footprint=RECT_GROUPS.has(group)?editorFootprint(entry):null,offset=[p.x-entry.x,p.z-entry.z];
      const hit=footprint?footprint.axes.every((axis,i)=>Math.abs(offset[0]*axis[0]+offset[1]*axis[1])<=footprint.half[i]+.12):Math.hypot(...offset)<=.65;
      if(hit)return {group,id:entry.id};
    }
    return null;
  }
  listen(canvas,'pointerdown',event=>{
    if(event.button!==0)return;event.preventDefault();canvas.focus();const p=position(event);
    if(p.x<0||p.z<0||p.x>data.bounds[0]||p.z>data.bounds[1])return;
    if(jsonDirty){toast('먼저 JSON 적용을 눌러 텍스트 변경을 반영하세요.','warning');return;}
    try {
      if(tool!=='select') {const entry=placeEditorEntity(data,tool,p.x,p.z);selected={group:tool,id:entry.id};refresh();}
      else {selected=pick(p);const entry=current();if(entry){drag={pointerId:event.pointerId,start:p,original:{x:entry.x,z:entry.z}};canvas.setPointerCapture(event.pointerId);}refresh({notify:false});}
    } catch(error){toast(error.message,'error');}
  });
  listen(canvas,'pointermove',event=>{
    if(!drag||event.pointerId!==drag.pointerId)return;const entry=current();if(!entry)return;const p=position(event);
    const x=drag.original.x+p.x-drag.start.x,z=drag.original.z+p.z-drag.start.z;
    if(entry.x===x&&entry.z===z)return;
    entry.x=x;entry.z=z;scheduleDraw();
  });
  const finish=event=>{if(!drag||event.pointerId!==drag.pointerId)return;drag=null;refresh();};
  listen(canvas,'pointerup',finish);
  listen(canvas,'pointercancel',event=>{if(!drag||event.pointerId!==drag.pointerId)return;Object.assign(current()||{},drag.original);drag=null;refresh({notify:false});});
  listen(canvas,'keydown',event=>{
    if(event.key==='Escape'&&drag){Object.assign(current()||{},drag.original);drag=null;refresh({notify:false});event.preventDefault();return;}
    if(['Delete','Backspace'].includes(event.key)){event.preventDefault();selectedDelete();return;}
    const delta={ArrowLeft:[-.25,0],ArrowRight:[.25,0],ArrowUp:[0,-.25],ArrowDown:[0,.25]}[event.key],entry=current();
    if(delta&&entry){event.preventDefault();entry.x+=delta[0];entry.z+=delta[1];jsonDirty=false;refresh();}
  });
  refresh({notify:false});
  return {getMission:()=>clone(data),setMission,destroy:()=>{cancelDraw();disposers.forEach(dispose=>dispose());}};
}
