import {chromium} from 'playwright';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import os from 'node:os';
import {sourceFingerprint} from '../scripts/build_fingerprint.mjs';
const url=process.env.BREACH_URL||'http://127.0.0.1:8080';
const out=process.env.BREACH_PERF_OUT||'tests/artifacts/performance-deep/browser-before.json';
const fixture=JSON.parse(await readFile('tests/artifacts/combat-benchmark.breach-replay.json','utf8'));
const rounds=Number(process.env.BREACH_PERF_ROUNDS||2),duration=Number(process.env.BREACH_PERF_MS||8000);
const rates=(process.env.BREACH_PERF_RATES||'1,4').split(',').map(Number),kinds=(process.env.BREACH_PERF_KINDS||'squad,replay').split(',');
await mkdir('tests/artifacts/performance-deep',{recursive:true});
const browser=await chromium.launch({channel:'chrome',headless:true,args:['--enable-unsafe-swiftshader']});
const context=await browser.newContext({viewport:{width:1440,height:900},deviceScaleFactor:1});
await context.addInitScript(()=>{
 let ui;window.deep={state:null,collect:false,ui:[],long:[],moving:[],shots:[],draws:0};
 new PerformanceObserver(list=>{if(window.deep.collect)window.deep.long.push(...list.getEntries().map(e=>e.duration))}).observe({entryTypes:['longtask']});
 for(const name of ['drawArrays','drawElements','drawArraysInstanced','drawElementsInstanced']){const fn=WebGL2RenderingContext.prototype[name];WebGL2RenderingContext.prototype[name]=function(...args){window.deep.draws++;return fn.apply(this,args)}}
 Object.defineProperty(window,'BreachUI',{configurable:true,get:()=>ui,set(value){ui=value;const receive=value.receive;value.receive=function(raw){const start=performance.now(),d=JSON.parse(raw);if(d.type==='state'){window.deep.state=d;if(window.deep.collect){window.deep.moving.push(d.units.filter(u=>u.status==='MOVING').length);window.deep.shots.push(d.shots_fired||0)}}const result=receive.call(value,raw);if(window.deep.collect)window.deep.ui.push(performance.now()-start);return result}}});
});
const page=await context.newPage(),cdp=await context.newCDPSession(page),errors=[];
page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error'||/SCRIPT ERROR|Parse Error/.test(m.text()))errors.push(m.text())});
await cdp.send('Performance.enable');
const send=data=>page.evaluate(d=>window.BreachBridge.send(JSON.stringify(d)),data);
const wait=fn=>page.waitForFunction(fn,null,{timeout:60000});
const report={url,host:os.cpus()[0].model,browser:browser.version(),rounds,rates,kinds,duration_ms:duration,samples:[],limitations:['RAF intervals are not GPU execution time.','CDP CPU slowdown is synthetic headroom testing, not an emulation of a specific device.','JSHeapUsedSize excludes GPU and WebAssembly heaps. Native replay retention is measured separately.','Navigation and simulator profiler timings are inclusive and must not be summed.']};
report.startedAt=new Date().toISOString();
report.fingerprint=await sourceFingerprint();
report.releaseQualification=false;
report.budget={normal_cpu_p95_ms:Number(process.env.BREACH_PERF_P95_MS||33.3),scope:'Short regression on the recorded host; excludes synthetic slowdown and does not replace the PRD minimum-spec five-minute qualification.'};
const pct=(a,p)=>[...a].sort((x,y)=>x-y)[Math.min(a.length-1,Math.floor(a.length*p))]??0;
const metrics=async()=>Object.fromEntries((await cdp.send('Performance.getMetrics')).metrics.map(m=>[m.name,m.value]));
async function prepare(kind){
 await cdp.send('Emulation.setCPUThrottlingRate',{rate:1});
 const start=performance.now();
 if(kind.includes('replay')){
  await send({action:'import_replay',data:fixture});await wait(()=>window.deep.state?.mode==='REPLAY');
  await send({action:'replay_reveal',value:true});await send({action:'replay_seek',time:1});
  await send({action:'replay_speed',speed:1});
  if(!await page.evaluate(()=>window.deep.state.replay.playing))await send({action:'replay_toggle'});
 }else{
  await send({action:'start',mission:'M06'});await wait(()=>window.deep.state?.mode==='PLANNING'&&window.deep.state.mission==='M06');
  report.lastStart_ms=performance.now()-start;
  if(kind.includes('squad')){
   for(const [i,x] of [7.1,8.6,24.1,25.6].entries())for(const z of [27.2,23,14])await send({action:'command',unit_id:['alpha','bravo','charlie','delta'][i],type:'MOVE',args:{target:[i===2&&z===14?25:x,z]}});
   await send({action:'toggle'});await wait(()=>window.deep.state.mode==='EXECUTING');
  }
 }
 await page.waitForTimeout(350);
 if(kind.startsWith('paused_')){
  await send({action:kind.includes('replay')?'replay_toggle':'toggle'});
  await wait(()=>window.deep.state.mode==='PLANNING'||window.deep.state.mode==='REPLAY'&&!window.deep.state.replay.playing);
 }
}
async function sample(kind,rate,round){
 await prepare(kind);await cdp.send('Emulation.setCPUThrottlingRate',{rate});await page.waitForTimeout(350);
 const before=await metrics();
 const values=await page.evaluate(({duration,kind})=>new Promise(resolve=>{
  const d=window.deep;d.ui=[];d.long=[];d.moving=[];d.shots=[];d.collect=true;const frames=[],fps=[],draws=[];let last,start,lastDraws=d.draws;
  const simulationStart=d.state.time;const panTimer=kind==='pan'?setInterval(()=>{const n=Math.floor(performance.now()/1000)%2;window.BreachBridge.send(JSON.stringify({action:'reset_camera'}));document.querySelector('canvas').dispatchEvent(new WheelEvent('wheel',{deltaY:n?-50:50,bubbles:true,cancelable:true}))},1000):null;
  function tick(now){start??=now;if(last){frames.push(now-last);draws.push(d.draws-lastDraws)}last=now;lastDraws=d.draws;fps.push(d.state.fps);if(now-start<duration)requestAnimationFrame(tick);else{clearInterval(panTimer);d.collect=false;resolve({frames,fps,draws,ui:d.ui,long:d.long,moving:d.moving,shots:d.shots,simulationSeconds:d.state.time-simulationStart,elapsed_ms:now-start,mode:d.state.mode})}}requestAnimationFrame(tick);
 }),{duration,kind});
 const after=await metrics(),seconds=values.elapsed_ms/1000;
 report.samples.push({kind,rate,round,start_ms:kind==='replay'?null:report.lastStart_ms,frames:values.frames.length,elapsed_ms:values.elapsed_ms,raf_fps:values.frames.length/seconds,median_ms:pct(values.frames,.5),p95_ms:pct(values.frames,.95),p99_ms:pct(values.frames,.99),max_ms:Math.max(...values.frames),over33:values.frames.filter(v=>v>33.5).length,fps:pct(values.fps,.5),task_ms_per_second:(after.TaskDuration-before.TaskDuration)*1000/seconds,script_ms_per_second:(after.ScriptDuration-before.ScriptDuration)*1000/seconds,layout_ms:(after.LayoutDuration-before.LayoutDuration)*1000,ui_p95_ms:pct(values.ui,.95),long_tasks:values.long.length,long_task_max_ms:Math.max(0,...values.long),draws_per_frame:pct(values.draws,.5),js_heap_start:before.JSHeapUsedSize,js_heap_end:after.JSHeapUsedSize,dom_nodes:after.Nodes,max_moving:Math.max(0,...values.moving),shots_delta:Math.max(0,...values.shots)-Math.min(...values.shots),simulation_seconds:values.simulationSeconds,mode:values.mode});
 console.log('SAMPLE',JSON.stringify(report.samples.at(-1)));
}
try{
 report.engine_manifest=await (await fetch(`${url}/engine-export-manifest.json`)).json();
 if(report.engine_manifest.sourceHash!==report.fingerprint.sourceHash)throw new Error('Served engine does not match current game source. Rebuild before measuring.');
 await page.goto(url);await wait(()=>window.BreachBridge&&!document.querySelector('#start-mission').disabled);
 report.runtime=await page.evaluate(()=>{const gl=document.querySelector('canvas').getContext('webgl2'),ext=gl.getExtension('WEBGL_debug_renderer_info');return {renderer:ext?gl.getParameter(ext.UNMASKED_RENDERER_WEBGL):null,width:gl.drawingBufferWidth,height:gl.drawingBufferHeight,gpu_timer_available:!!gl.getExtension('EXT_disjoint_timer_query_webgl2')}});
 for(let round=0;round<rounds;round++)for(const rate of rates)for(const kind of kinds)await sample(kind,rate,round);
 // Real camera gestures in a stationary large map; separate from combat timing.
 await prepare('pan');await cdp.send('Emulation.setCPUThrottlingRate',{rate:1});
 await page.mouse.move(700,420);await page.mouse.down({button:'middle'});const pre=await metrics();
 for(let i=0;i<30;i++)await page.mouse.move(700+Math.sin(i*.35)*140,420+Math.cos(i*.35)*80,{steps:2});await page.mouse.up({button:'middle'});
 const post=await metrics();report.camera={task_ms:(post.TaskDuration-pre.TaskDuration)*1000,commands:await page.evaluate(()=>window.deep.state.units.flatMap(u=>u.commands).length)};
 report.errors=errors;report.correctnessStatus=errors.length?'FAIL':'PASS';
 report.budgetChecks=report.samples.filter(s=>s.rate===1).map(s=>({kind:s.kind,round:s.round,p95_ms:s.p95_ms,budget_ms:report.budget.normal_cpu_p95_ms,passed:s.frames>=60&&s.p95_ms<=report.budget.normal_cpu_p95_ms&&(s.kind.startsWith('paused_')?s.simulation_seconds===0:s.kind!=='squad'||s.max_moving===4&&s.shots_delta>0)}));
 report.performanceStatus=report.budgetChecks.length&&report.budgetChecks.every(s=>s.passed)?'PASS':'FAIL';
 report.sourceUnchanged=report.fingerprint.sourceHash===(await sourceFingerprint()).sourceHash;
 report.status=report.correctnessStatus==='PASS'&&report.performanceStatus==='PASS'&&report.sourceUnchanged?'PASS':'FAIL';
 if(report.status==='FAIL')process.exitCode=1;
}catch(e){report.status='FAIL';report.error=e.stack;process.exitCode=1}finally{await writeFile(out,JSON.stringify(report,null,2));await browser.close();console.log('REPORT',out,report.status)}
