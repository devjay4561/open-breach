import {chromium} from 'playwright';
import {writeFile,mkdir} from 'node:fs/promises';
import os from 'node:os';
const url=process.env.BREACH_URL||'http://127.0.0.1:8080',out=process.env.BREACH_PERF_OUT||'tests/artifacts/performance-current/browser-before.json';
await mkdir('tests/artifacts/performance-current',{recursive:true});
const browser=await chromium.launch({channel:'chrome',headless:true,args:['--enable-unsafe-swiftshader']});
const context=await browser.newContext({viewport:{width:1440,height:900},deviceScaleFactor:1});
await context.addInitScript(()=>{let ui;window.perf={state:null,ui:[]};Object.defineProperty(window,'BreachUI',{configurable:true,get:()=>ui,set(value){ui=value;const receive=value.receive;value.receive=function(raw){const t=performance.now(),data=JSON.parse(raw);if(data.type==='state')window.perf.state=data;const result=receive.call(value,raw);if(window.perf.collect)window.perf.ui.push(performance.now()-t);return result}}})});
const page=await context.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error'||/SCRIPT ERROR|Parse Error/.test(m.text()))errors.push(m.text())});
const report={url,host:os.cpus()[0].model,viewport:[1440,900],browser:browser.version(),limitations:'Headless Chrome on this Mac; RAF intervals, not GPU timings or a guarantee for other devices.',samples:[]};
const send=data=>page.evaluate(data=>window.BreachBridge.send(JSON.stringify(data)),data);
async function sample(id,phase){
 await page.waitForTimeout(500);
 const r=await page.evaluate(()=>new Promise(resolve=>{let previous,start;const intervals=[],fps=[];window.perf.ui=[];window.perf.collect=true;const before=window.perf.state.time;function tick(t){start??=t;if(previous)intervals.push(t-previous);previous=t;fps.push(window.perf.state.fps);if(t-start<6000)requestAnimationFrame(tick);else{window.perf.collect=false;resolve({intervals,fps,ui:window.perf.ui,simulatedSeconds:window.perf.state.time-before,mode:window.perf.state.mode})}}requestAnimationFrame(tick)}));
 const pct=(a,q)=>[...a].sort((a,b)=>a-b)[Math.min(a.length-1,Math.floor(a.length*q))];
 report.samples.push({id,phase,frames:r.intervals.length,median_ms:pct(r.intervals,.5),p95_ms:pct(r.intervals,.95),max_ms:Math.max(...r.intervals),over33:r.intervals.filter(n=>n>33.5).length,engine_fps:pct(r.fps,.5),ui_p95_ms:pct(r.ui,.95),simulatedSeconds:r.simulatedSeconds,mode:r.mode});
}
try{
 await page.goto(url);await page.waitForFunction(()=>window.BreachBridge&&!document.querySelector('#start-mission').disabled);
 report.renderer=await page.evaluate(()=>{const g=document.querySelector('canvas').getContext('webgl2'),e=g.getExtension('WEBGL_debug_renderer_info');return e?g.getParameter(e.UNMASKED_RENDERER_WEBGL):null});
 for(const id of ['M01','M06']){
  await send({action:'start',mission:id});await page.waitForFunction(id=>window.perf.state?.mode==='PLANNING'&&window.perf.state.mission===id,id);
  await sample(id,'planning');
  // Real commands and AI. Move two operators toward the entrance on each map.
  const targets=id==='M06'?[[8,27.2],[8,23]]:[[12.2,14.6],[12.2,11.5]];
  for(const target of targets)await send({action:'command',unit_id:'alpha',type:'MOVE',args:{target}});
  await send({action:'toggle'});await sample(id,'moving');await send({action:'pause'});
 }
 report.errors=errors;report.status=errors.length?'FAIL':'PASS';
}catch(e){report.error=e.stack;report.status='FAIL';process.exitCode=1}finally{await writeFile(out,JSON.stringify(report,null,2));await browser.close();console.log(JSON.stringify(report))}
