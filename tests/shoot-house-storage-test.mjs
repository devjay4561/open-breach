import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';

const source=await readFile(new URL('../web/storage.js',import.meta.url),'utf8');
const {BreachStorage,createLeaderboardAdapter,LeaderboardAdapter}=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
const metaSource=await readFile(new URL('../web/meta.js',import.meta.url),'utf8');
const {conditionKey}=await import('data:text/javascript;base64,'+Buffer.from(metaSource).toString('base64'));
let checks=0;
const equal=(actual,expected,note)=>{assert.deepEqual(actual,expected,note);checks++;};
const check=(value,note)=>{assert(value,note);checks++;};
const copy=value=>value===undefined?undefined:structuredClone(value);

// Run the actual new storage methods against deterministic transaction
// boundaries. Existing browser storage suites exercise IndexedDB itself;
// this fixture does not launch Chrome, use timers or add a dependency.
const legacy={id:'M01',kind:'mission',stars:{complete:true},bestScore:99};
const shared={records:new Map([['M01',copy(legacy)],['campaign',{id:'campaign',active:true}]]),tail:Promise.resolve(),writes:0};
class MemoryStorage extends BreachStorage {
  _transaction(name,mode,work){
    assert.equal(name,'progress');
    const operation=shared.tail.then(()=>new Promise((resolve,reject)=>{
      const draft=new Map([...shared.records].map(([id,value])=>[id,copy(value)]));
      let pending=0,finished=false,result,done=false;
      const finish=()=>{if(done||!finished||pending)return;done=true;if(mode==='readwrite')shared.records=draft;resolve(result);};
      const objectStore={get:id=>{
        const request={result:copy(draft.get(id))};pending++;
        queueMicrotask(()=>{try{request.onsuccess?.();}catch(error){done=true;reject(error);}finally{pending--;finish();}});return request;
      },put:record=>{assert.equal(mode,'readwrite');draft.set(record.id,copy(record));shared.writes++;}};
      const context={result:value=>{result=value;},fail:error=>{done=true;reject(error);},store:()=>objectStore};
      try{work(objectStore,context);finished=true;finish();}catch(error){reject(error);}
    }));
    shared.tail=operation.catch(()=>{});return operation;
  }
}
const storage=new MemoryStorage(),other=new MemoryStorage();
const conditions={mission:'SH01',seed:42,variant:'normal',modifiers:[],loadout:{alpha:{weapon:'standard'}},roster:[{id:'raven',trait:'steady',base_id:'alpha'}]};
const entry=(elapsed=60,quality=.75,known=8,options=conditions)=>{
  const key=conditionKey(options);return {id:'cqb-competition:'+key,kind:'cqb-competition',mission:options.mission,condition_key:key,elapsed,quality,known,adjusted_time:elapsed/Math.max(quality,.125)};
};
const adapter=createLeaderboardAdapter(storage);
equal(adapter.kind,'local','Default leaderboard is local');
let outbound=0;const originalFetch=globalThis.fetch;globalThis.fetch=()=>{outbound++;throw new Error('Unexpected network');};
try{
  equal(await adapter.listScores(entry().condition_key),[],'New conditions have no record');
  const input={...entry(),enemies:[{id:'secret',x:99,z:99}],room_doctrine_private:{secret:1}};
  const first=await adapter.submitScore(input);
  equal([first.elapsed,first.quality,first.adjusted_time,first.attempts,first.version],[60,.75,80,1,1],'First valid score commits and verifies');
  check(!JSON.stringify(first).includes('secret'),'Record contains condition key and aggregates, not raw NPC or private fields');
  input.elapsed=900;
  equal((await adapter.listScores(entry().condition_key))[0].elapsed,60,'Stored record owns its data');
  const worse=await storage.saveShootHouseScore(entry(120));
  equal([worse.adjusted_time,worse.elapsed,worse.attempts,worse.version],[80,60,2,2],'Worse attempts increment counters while preserving the best');
  const better=await storage.saveShootHouseScore(entry(45));
  equal([better.adjusted_time,better.elapsed,better.attempts],[60,45,3],'Lower adjusted time becomes the best');
  const tied=await storage.saveShootHouseScore(entry(60,1));
  equal([tied.adjusted_time,tied.elapsed,tied.quality,tied.attempts],[60,45,.75,4],'Equal scores preserve the first best record');
  const concurrent=await Promise.all([storage.saveShootHouseScore(entry(30,1)),other.saveShootHouseScore(entry(15,1)),storage.saveShootHouseScore(entry(25,1)),other.saveShootHouseScore(entry(18,1))]);
  const final=(await adapter.listScores(entry().condition_key))[0];
  equal([final.adjusted_time,final.attempts,final.version],[15,8,8],'Independent instances atomically retain all concurrent attempts and the best');
  check(concurrent.every(record=>record.adjusted_time<=30&&record.attempts>=5),'Read-back allows a concurrent newer best without losing verification');
  const corruptExtra=shared.records.get(final.id);corruptExtra.enemies=[{id:'secret'}];
  check(!JSON.stringify(await adapter.listScores(entry().condition_key)).includes('secret'),'Listing returns only whitelisted aggregates even if an unrelated writer added extra data');
  for(const options of [{...conditions,seed:43},{...conditions,variant:'challenge'},{...conditions,loadout:{alpha:{weapon:'shotgun'}}},{...conditions,roster:[{id:'viper',trait:'calm',base_id:'alpha'}]},{...conditions,mission:'SH05_PRECISION'},{...conditions,mission:'SH05_HIGH_INTENSITY'}]){
    const score=entry(30,1,1,options);await storage.saveShootHouseScore(score);
    equal((await adapter.listScores(score.condition_key))[0].attempts,1,'A changed condition has a separate competition record');
  }
  equal((await adapter.listScores(entry().condition_key))[0].attempts,8,'Other conditions do not affect the original record');
  equal(shared.records.get('M01'),legacy,'Legacy mission progress is untouched');
  equal(shared.records.get('campaign'),{id:'campaign',active:true},'Campaign state is untouched');
  for(const change of [{mission:'CQB01'},{mission:'M01'},{id:'M01'},{kind:'mission'},{quality:0},{quality:-1},{quality:1.1},{quality:'1'},{elapsed:0},{elapsed:-1},{elapsed:NaN},{elapsed:'30'},{known:0},{known:513},{known:.5},{adjusted_time:999},{adjusted_time:Infinity,elapsed:Number.MAX_VALUE,quality:.125},{condition_key:'not-a-key'}]){
    const writes=shared.writes;
    await assert.rejects(storage.saveShootHouseScore({...entry(),...change}),error=>error.code==='COMPETITION_INVALID');checks++;
    equal(shared.writes,writes,'An invalid score is rejected before any write');
  }
  for(const conditions of [{mission:'SH01',seed:42,variant:'normal',modifiers:[],loadout:{},roster:[],enemies:[{id:'secret'}]},{mission:'SH01',seed:-1,variant:'normal',modifiers:[],loadout:{},roster:[]},{mission:'SH01',seed:42,variant:'normal',modifiers:[],loadout:[],roster:[]}]){
    const key='run:'+JSON.stringify(conditions);
    await assert.rejects(storage.saveShootHouseScore({...entry(),id:'cqb-competition:'+key,condition_key:key}),error=>error.code==='COMPETITION_INVALID');checks++;
  }
  const low=await storage.saveShootHouseScore(entry(10,.0625,16,{...conditions,seed:44}));
  equal(low.adjusted_time,80,'Positive quality below one eighth uses the specified denominator floor');
  const provider={submitScore(){outbound++;},listScores(){outbound++;}};
  equal(createLeaderboardAdapter(storage,provider),provider,'An optional future provider implements the same adapter contract');
  equal(outbound,0,'Constructing a provider and all default local operations perform no outbound calls');
  assert.throws(()=>createLeaderboardAdapter(storage,{}),error=>error.code==='LEADERBOARD_UNAVAILABLE');checks++;
  await assert.rejects(new LeaderboardAdapter().submitScore(entry()),error=>error.code==='LEADERBOARD_UNAVAILABLE');checks++;
  await assert.rejects(new LeaderboardAdapter().listScores(entry().condition_key),error=>error.code==='LEADERBOARD_UNAVAILABLE');checks++;
  check(source.includes('const DATABASE_VERSION = 2;'),'Database version remains 2');
  check(source.includes("const STORES = new Set(['settings', 'progress', 'plans', 'replays', REPLAY_METADATA]);"),'No new store or migration is introduced');
}finally{globalThis.fetch=originalFetch;}
console.log(`BREACH_SHOOT_HOUSE_STORAGE_RESULT checks=${checks} failures=0 status=PASS`);
