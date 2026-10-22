import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import {mkdir,mkdtemp,rm,writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import os from 'node:os';

const baseline=process.env.BREACH_BASELINE_URL||'http://127.0.0.1:8080';
const candidate=process.env.BREACH_URL||'http://127.0.0.1:8099';
const output=process.env.BREACH_ARTIFACTS||'tests/artifacts/loading-optimization';
await mkdir(output,{recursive:true});
const report={date:new Date().toISOString(),cpu:os.cpus()[0].model,network:{download_mbps:10,latency_ms:40},samples:[],errors:[],limitations:'Temporary Chrome profiles on this Mac with normal disk caching and synthetic network throttling. Private browsing may still redownload large files.'};
let context,profile;
try{
 for(const [label,url] of [['before',baseline],['after',candidate]]){
  // Incognito contexts do not retain these large binaries; exercise normal disk caching.
  profile=await mkdtemp(join(os.tmpdir(),'breach-loading-profile-'));
  context=await chromium.launchPersistentContext(profile,{channel:'chrome',headless:true,args:['--enable-unsafe-swiftshader'],viewport:{width:1440,height:900},deviceScaleFactor:1});
  report.browser=context.browser().version();
  await context.addInitScript(()=>{
   window.loadingQA={ready:null,state:null};let ui;
   Object.defineProperty(window,'BreachUI',{configurable:true,get:()=>ui,set(value){ui=value;const receive=value.receive;value.receive=function(raw){const data=JSON.parse(raw);if(data.type==='ready')window.loadingQA.ready=performance.now();if(data.type==='state')window.loadingQA.state=data;return receive.call(value,raw)}}});
  });
  const page=await context.newPage(),cdp=await context.newCDPSession(page),warnings=[];
  page.on('pageerror',error=>report.errors.push(`${label}: ${error.message}`));
  page.on('console',message=>{
   if(message.type()==='error'||/SCRIPT ERROR|Parse Error/.test(message.text()))report.errors.push(`${label}: ${message.text()}`);
   if(message.type()==='warning'&&/preload/i.test(message.text()))warnings.push(message.text());
  });
  await cdp.send('Network.enable');
  await cdp.send('Network.emulateNetworkConditions',{offline:false,latency:40,downloadThroughput:10_000_000/8,uploadThroughput:2_000_000/8});
  for(const phase of ['first-visit','reload']){
   const responses=[];const capture=response=>responses.push({path:new URL(response.url()).pathname,status:response.status(),encoding:response.headers()['content-encoding']||null});
   page.on('response',capture);
   if(phase==='first-visit')await page.goto(url,{waitUntil:'domcontentloaded'});
   else await page.reload({waitUntil:'domcontentloaded'});
   await page.waitForFunction(()=>window.loadingQA.ready&&window.BreachBridge&&!document.querySelector('#start-mission').disabled,null,{timeout:60000});
   const metrics=await page.evaluate(()=>({ready_ms:window.loadingQA.ready,resources:performance.getEntriesByType('resource').map(entry=>({path:new URL(entry.name).pathname,start_ms:entry.startTime,end_ms:entry.responseEnd,transfer_bytes:entry.transferSize,encoded_bytes:entry.encodedBodySize,decoded_bytes:entry.decodedBodySize}))}));
   const engine=metrics.resources.filter(entry=>/\/engine\.(wasm|pck)$/.test(entry.path));
   const sample={label,url,phase,ready_ms:metrics.ready_ms,engine_transfer_bytes:engine.reduce((total,entry)=>total+entry.transfer_bytes,0),engine,encodings:responses.filter(entry=>/\/engine\.(wasm|pck)$/.test(entry.path)),warnings:[...warnings]};
   report.samples.push(sample);console.log(JSON.stringify(sample));
   if(label==='after'){
    for(const name of ['engine.wasm','engine.pck'])assert.equal(engine.filter(entry=>entry.path===`/${name}`).length,1,`${name} must download once despite preloading`);
    assert.deepEqual(warnings,[],'Preloads must be reused without credential or type mismatches');
    if(phase==='first-visit')assert(sample.encodings.every(entry=>entry.encoding==='br'),'Current Chrome must receive Brotli');
    else assert(sample.engine_transfer_bytes<2000,'Unchanged engine and pack must revalidate without their payloads');
   }
   page.off('response',capture);
  }
  if(label==='after'){
   await cdp.send('Network.emulateNetworkConditions',{offline:false,latency:0,downloadThroughput:-1,uploadThroughput:-1});
   await page.locator('#title-start').click();
   await page.locator('[data-mission="M01"]').click();
   await page.waitForFunction(()=>!document.querySelector('#transition-loading').open);
   await page.locator('#select-to-briefing').click();
   await page.locator('#start-mission').click();
   await page.waitForFunction(()=>window.loadingQA.state?.mission==='M01'&&window.loadingQA.state.mode==='PLANNING'&&!document.querySelector('#transition-loading').open);
   await page.screenshot({path:`${output}/mission-ready.png`});
   report.gameplay_check='M01 starts through the menu and briefing after a cached reload';
  }
  await context.close();
  context=null;await rm(profile,{recursive:true,force:true});profile=null;
 }
 const firstBefore=report.samples.find(sample=>sample.label==='before'&&sample.phase==='first-visit');
 const firstAfter=report.samples.find(sample=>sample.label==='after'&&sample.phase==='first-visit');
 report.improvement={first_visit_ms:firstBefore.ready_ms-firstAfter.ready_ms,first_visit_percent:100*(1-firstAfter.ready_ms/firstBefore.ready_ms),engine_bytes_saved:firstBefore.engine_transfer_bytes-firstAfter.engine_transfer_bytes};
 assert(firstAfter.engine_transfer_bytes<firstBefore.engine_transfer_bytes*.9,'First-visit engine payload must shrink by at least 10%');
 assert(firstAfter.ready_ms<firstBefore.ready_ms,'First visit must become faster under the same network condition');
 assert.deepEqual(report.errors,[]);report.status='PASS';
}catch(error){report.status='FAIL';report.error=error.stack;process.exitCode=1;console.error(error.stack)}finally{
 await writeFile(`${output}/report.json`,JSON.stringify(report,null,2));
 if(context)await context.close();
 if(profile)await rm(profile,{recursive:true,force:true});
 console.log(JSON.stringify({status:report.status,improvement:report.improvement,output}));
}
