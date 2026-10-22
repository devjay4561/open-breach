import {chromium} from 'playwright';
import {readFile,writeFile} from 'node:fs/promises';
const url=process.env.BREACH_URL||'http://127.0.0.1:8080',out=process.env.BREACH_PERF_OUT||'tests/artifacts/performance-deep/diagnostics-before.json';
const browser=await chromium.launch({channel:'chrome',headless:true,args:['--enable-unsafe-swiftshader']});
const context=await browser.newContext({viewport:{width:1440,height:900}});
await context.addInitScript(()=>{
 window.diag={state:null,gpu:[],pending:[],collect:false,draws:0,disjoint:0};let ui;
 Object.defineProperty(window,'BreachUI',{configurable:true,get:()=>ui,set(v){ui=v;const fn=v.receive;v.receive=function(raw){const d=JSON.parse(raw);if(d.type==='state')window.diag.state=d;const r=fn.call(v,raw);if(d.type==='state'&&window.diag.ack&&d.tool===window.diag.ack.tool){const ack=window.diag.ack;window.diag.ack=null;requestAnimationFrame(()=>ack.resolve(performance.now()-ack.start))}return r}}});
 for(const name of ['drawArrays','drawElements','drawArraysInstanced','drawElementsInstanced']){const fn=WebGL2RenderingContext.prototype[name];WebGL2RenderingContext.prototype[name]=function(...args){window.diag.draws++;return fn.apply(this,args)}}
 const raf=window.requestAnimationFrame.bind(window);
 window.requestAnimationFrame=callback=>raf(time=>{
  const d=window.diag,g=d.gl,e=d.ext;
  if(g&&e){const invalid=g.getParameter(e.GPU_DISJOINT_EXT);if(invalid)d.disjoint++;
   d.pending=d.pending.filter(q=>{if(invalid){g.deleteQuery(q);return false}if(g.getQueryParameter(q,g.QUERY_RESULT_AVAILABLE)){d.gpu.push(g.getQueryParameter(q,g.QUERY_RESULT)/1e6);g.deleteQuery(q);return false}return true})}
  const q=g&&e&&d.collect&&d.pending.length<8&&!g.getQuery(e.TIME_ELAPSED_EXT,g.CURRENT_QUERY)?g.createQuery():null;
  const draws=d.draws;if(q)g.beginQuery(e.TIME_ELAPSED_EXT,q);
  try{return callback(time)}finally{if(q){g.endQuery(e.TIME_ELAPSED_EXT);if(d.draws>draws)d.pending.push(q);else g.deleteQuery(q)}}
 });
});
const page=await context.newPage(),cdp=await context.newCDPSession(page),errors=[];await cdp.send('Performance.enable');
page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error'||/SCRIPT ERROR|Parse Error/.test(m.text()))errors.push(m.text())});
const send=d=>page.evaluate(d=>window.BreachBridge.send(JSON.stringify(d)),d);
const metric=async()=>Object.fromEntries((await cdp.send('Performance.getMetrics')).metrics.map(m=>[m.name,m.value]));
const pct=(a,p)=>[...a].sort((a,b)=>a-b)[Math.min(a.length-1,Math.floor(a.length*p))]??null;
const report={url,memory:[],limitations:['GPU query times cover WebGL commands submitted by drawing RAF callbacks; samples marked disjoint are discarded.','Heap/DOM readings are after explicit diagnostic garbage collection and exclude GPU/WASM allocations.','Response time is a DOM toolbar click through engine acknowledgment and next RAF, not an OS-to-photon measurement.']};
try{
 await page.goto(url);await page.waitForFunction(()=>window.BreachBridge&&!document.querySelector('#start-mission').disabled);
 await send({action:'import_replay',data:JSON.parse(await readFile('tests/artifacts/combat-benchmark.breach-replay.json','utf8'))});
 await page.waitForFunction(()=>window.diag.state?.mode==='REPLAY');await send({action:'replay_reveal',value:true});
 if(!await page.evaluate(()=>window.diag.state.replay.playing))await send({action:'replay_toggle'});
 await page.waitForTimeout(500);await page.evaluate(()=>{const d=window.diag;d.gl=document.querySelector('canvas').getContext('webgl2');d.ext=d.gl.getExtension('EXT_disjoint_timer_query_webgl2');d.collect=true});
 await page.waitForTimeout(8000);await page.evaluate(()=>window.diag.collect=false);await page.waitForTimeout(300);
 const gpu=await page.evaluate(()=>({samples:window.diag.gpu,disjoint:window.diag.disjoint,supported:!!window.diag.ext}));
 report.gpu={supported:gpu.supported,samples:gpu.samples.length,median_ms:pct(gpu.samples,.5),p95_ms:pct(gpu.samples,.95),max_ms:Math.max(0,...gpu.samples),disjoint:gpu.disjoint};
 for(let i=0;i<8;i++){
  const id=i%2?'M01':'M06',t=performance.now();await send({action:'start',mission:id});
  await page.waitForFunction(id=>window.diag.state?.mode==='PLANNING'&&window.diag.state.mission===id,id);const start_ms=performance.now()-t;
  await page.waitForTimeout(200);await cdp.send('HeapProfiler.collectGarbage');const m=await metric();
  report.memory.push({cycle:i,mission:id,start_ms,js_heap:m.JSHeapUsedSize,dom_nodes:m.Nodes});
 }
 const latencies=[];
 for(let i=0;i<16;i++)latencies.push(await page.evaluate(()=>new Promise((resolve,reject)=>{const tool=window.diag.state.tool==='pan'?'select':'pan';const timeout=setTimeout(()=>reject(new Error('Toolbar ack timeout')),5000);window.diag.ack={tool,start:performance.now(),resolve:value=>{clearTimeout(timeout);resolve(value)}};document.querySelector('#pan-camera').click()})));
 report.response={samples:latencies,p50_ms:pct(latencies,.5),p95_ms:pct(latencies,.95)};
 report.errors=errors;report.status=errors.length?'FAIL':'PASS';
}catch(e){report.status='FAIL';report.error=e.stack;report.errors=errors;process.exitCode=1}finally{await writeFile(out,JSON.stringify(report,null,2));await browser.close();console.log(JSON.stringify(report))}
