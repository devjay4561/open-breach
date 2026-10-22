// Deterministic bridge/UI regression; this fixture does not measure Godot or GPU performance.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import {chromium} from 'playwright';
const catalog=['T01','M01'].map(id=>({id,title:`${id} 작전`,title_en:`${id} operation`,historical:{},bounds:[16,12],rooms:[{id:'room',x:8,z:6,w:14,d:10}],walls:[],units:[{id:'alpha'},{id:'bravo'}],objectives:['모든 위협 무력화']}));
const engine=`window.optimizationTest={sent:[]};window.BreachBridge.send=text=>window.optimizationTest.sent.push(JSON.parse(text));window.Engine=class{async startGame(){window.BreachUI.receive({type:'ready',catalog:${JSON.stringify(catalog)}});window.BreachUI.receive({type:'state',mode:'MENU'});}};`;
const mime={'.js':'text/javascript','.css':'text/css','.html':'text/html','.svg':'image/svg+xml','.woff2':'font/woff2','.wav':'audio/wav'};
const server=createServer(async(req,res)=>{try{const url=new URL(req.url,'http://localhost');if(url.pathname==='/engine.js'){res.setHeader('content-type','text/javascript');res.end(engine);return;}const name=url.pathname==='/'?'index.html':url.pathname.slice(1);if(name.includes('..')){res.writeHead(400);res.end();return;}const bytes=await readFile(new URL('../web/'+name,import.meta.url));res.setHeader('content-type',mime[name.slice(name.lastIndexOf('.'))]||'application/octet-stream');res.end(bytes);}catch{res.writeHead(404);res.end();}});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const browser=await chromium.launch({headless:true,channel:process.env.BREACH_CHANNEL||'chrome',...(process.env.BREACH_EXECUTABLE_PATH?{executablePath:process.env.BREACH_EXECUTABLE_PATH}:{})});
const page=await browser.newPage({viewport:{width:1440,height:900}}),errors=[];page.on('pageerror',error=>errors.push(error.message));
await page.addInitScript(()=>{
  window.audioGains=[];
  window.AudioContext=class{constructor(){this.destination={};}createGain(){const gain={gain:{value:0},connect(){}};window.audioGains.push(gain);return gain;}createDynamicsCompressor(){return {threshold:{},knee:{},ratio:{},attack:{},release:{},connect(){}};}decodeAudioData(){return Promise.resolve({});}resume(){return Promise.resolve();}suspend(){return Promise.resolve();}createBufferSource(){return {connect(){},start(){},stop(){},disconnect(){}};}};
});
const paint=()=>page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
const check=(actual,expected,message)=>assert.deepEqual(actual,expected,message);
try{
  await page.goto(`http://127.0.0.1:${server.address().port}`);await page.locator('#loading').waitFor({state:'hidden'});
  await page.evaluate(()=>document.fonts.ready);await page.waitForTimeout(250);
  await page.locator('#title-start').click();await page.evaluate(()=>window.cardBefore=document.querySelector('#tab-M01'));
  check(await page.locator('#historical-map-facts').isVisible(),false,'empty historical metadata must not show undefined facts');
  await page.locator('#tab-M01').click();check(await page.evaluate(()=>window.cardBefore===document.querySelector('#tab-M01')),true,'selection must keep unchanged mission cards');
  check(await page.locator('#tab-M01').getAttribute('aria-selected'),'true','cached cards must still update tab selection');
  await page.locator('#select-screen [data-nav="title"]').click();await page.locator('#title-settings').click();await page.locator('[data-settings-tab="audio"]').click();
  const audio=await page.evaluate(()=>{
    const input=document.querySelector('[data-setting="volume"]'),modalChild=document.querySelector('.settings-tabs'),card=document.querySelector('#tab-M01');
    const before=window.optimizationTest.sent.filter(message=>message.action==='settings').length;
    for(let i=0;i<100;i++){input.value=String(i%70);input.dispatchEvent(new Event('input',{bubbles:true}));}input.value='43';input.dispatchEvent(new Event('input',{bubbles:true}));input.dispatchEvent(new Event('change',{bubbles:true}));
    return {settings:window.optimizationTest.sent.filter(message=>message.action==='settings').length-before,gain:window.audioGains[0].gain.value,output:document.querySelector('#value-volume').textContent,modalStable:modalChild===document.querySelector('.settings-tabs'),cardStable:card===document.querySelector('#tab-M01')};
  });
  check(audio,{settings:0,gain:.43,output:'43%',modalStable:true,cardStable:true},'audio dragging updates gain without engine roundtrip or DOM replacement');
  await page.locator('[data-setting-toggle="muted"]').click();check(await page.evaluate(()=>window.audioGains.map(node=>node.gain.value)),[0,0],'mute still updates both audio buses');
  await page.locator('[data-settings-tab="gameplay"]').click();await page.locator('[data-cycler="language"] output').click();await page.locator('[data-cycler="language"] [data-cycle-set="en"]').click();
  check(await page.evaluate(()=>window.optimizationTest.sent.filter(message=>message.action==='settings').at(-1).settings.language),'en','language still reaches the engine');
  check(await page.locator('[data-collection="base"]').textContent(),'Core operations','collection chrome must follow the active language');
  check(await page.locator('[data-collection="history"]').textContent(),'Special Ops 12');
  await page.locator('#modal-close').click();
  await page.evaluate(()=>{window.live={type:'state',mode:'PLANNING',mission:'M01',seed:1024,time:0,tool:'select',selected:'alpha',units:[{id:'alpha',name:'ALPHA',hp:100,ammo:12,commands:[]}],doors:[],events:[],objectives:{total:1,neutralized:0}};window.BreachUI.receive(window.live);});await paint();await page.waitForTimeout(250);
  const stableHUD=await page.evaluate(async()=>{
    const selectors=['.hud-topbar','.hud-left','.hud-right','.hud-hotbar'];let rectReads=0,mutations=0;
    for(const selector of selectors){const element=document.querySelector(selector),original=element.getBoundingClientRect;element.getBoundingClientRect=function(){rectReads++;return original.call(this);};}
    const modeChild=document.querySelector('#mode-pill').firstChild,executeChild=document.querySelector('#toggle-execution').firstChild;
    const observer=new MutationObserver(records=>mutations+=records.length);for(const id of ['hud-code','hud-mission','objective-threat','mode-pill','toggle-execution'])observer.observe(document.getElementById(id),{childList:true,subtree:true});
    for(let i=0;i<20;i++)window.BreachUI.receive({...window.live,time:i/10});await new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)));observer.disconnect();
    return {mutations,rectReads,modeStable:modeChild===document.querySelector('#mode-pill').firstChild,executeStable:executeChild===document.querySelector('#toggle-execution').firstChild};
  });
  check(stableHUD,{mutations:0,rectReads:0,modeStable:true,executeStable:true},'unchanged HUD content must not rebuild or measure layout every state');
  await page.evaluate(()=>{window.replay={...window.live,mode:'REPLAY',replay:{duration:12,time:2,playing:false,speed:1,complete:true},events:[{type:'enemy_spotted',time:1}]};window.BreachUI.receive(window.replay);});await paint();
  check(await page.locator('#replay-markers button').count(),1);
  const stableMarker=await page.evaluate(()=>{const marker=document.querySelector('#replay-markers button');marker.focus();for(let i=0;i<20;i++)window.BreachUI.receive({...window.replay,replay:{...window.replay.replay,time:2+i/10}});return marker===document.querySelector('#replay-markers button')&&document.activeElement===marker;});
  check(stableMarker,true,'unchanged markers retain their nodes and keyboard focus');
  await page.evaluate(()=>{for(let i=0;i<8;i++)window.BreachUI.receive({type:'fx',kind:'breach',time:3,door_id:'door_1'});});await paint();
  check(await page.locator('#replay-markers button').count(),1,'duplicate delivered FX must create one timeline marker');
  check(await page.locator('#replay-markers button').getAttribute('data-seek'),'3');
  const seek=await page.evaluate(async()=>{
    window.optimizationTest.sent=[];const input=document.querySelector('#replay-seek');input.dispatchEvent(new PointerEvent('pointerdown',{bubbles:true,pointerId:8}));
    for(let i=0;i<100;i++){input.value=String(i/10);input.dispatchEvent(new Event('input',{bubbles:true}));}
    window.BreachUI.receive({...window.replay,replay:{...window.replay.replay,time:1}});const optimistic=input.value,before=window.optimizationTest.sent.filter(message=>message.action==='replay_seek').length;
    await new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)));const first=window.optimizationTest.sent.filter(message=>message.action==='replay_seek').map(message=>message.time);
    document.dispatchEvent(new PointerEvent('pointerup',{bubbles:true,pointerId:9}));window.BreachUI.receive({...window.replay,replay:{...window.replay.replay,time:1}});const held=input.value;
    input.value='10.5';input.dispatchEvent(new Event('input',{bubbles:true}));document.dispatchEvent(new PointerEvent('pointerup',{bubbles:true,pointerId:8}));input.dispatchEvent(new Event('change',{bubbles:true}));
    const final=window.optimizationTest.sent.filter(message=>message.action==='replay_seek').map(message=>message.time);await new Promise(resolve=>requestAnimationFrame(resolve));
    return {before,optimistic,held,first,final,after:window.optimizationTest.sent.filter(message=>message.action==='replay_seek').map(message=>message.time)};
  });
  check(seek,{before:0,optimistic:'9.9',held:'9.9',first:[9.9],final:[9.9,10.5],after:[9.9,10.5]},'seek must coalesce per frame and flush its own final pointer value once');
  const keyboard=await page.evaluate(()=>{const input=document.querySelector('#replay-seek');input.value='9';input.dispatchEvent(new Event('input',{bubbles:true}));input.dispatchEvent(new Event('change',{bubbles:true}));return window.optimizationTest.sent.filter(message=>message.action==='replay_seek').at(-1).time;});check(keyboard,9,'keyboard change must flush without waiting for RAF');
  const exit=await page.evaluate(async()=>{const count=window.optimizationTest.sent.filter(message=>message.action==='replay_seek').length,input=document.querySelector('#replay-seek');input.value='11';input.dispatchEvent(new Event('input',{bubbles:true}));window.BreachUI.receive({type:'state',mode:'MENU'});await new Promise(resolve=>requestAnimationFrame(resolve));return window.optimizationTest.sent.filter(message=>message.action==='replay_seek').length-count;});check(exit,0,'leaving replay must cancel a pending seek');
  check(errors,[]);console.log('UI optimization: audio, i18n, mission identity, HUD layout, marker focus/dedup and seek batching passed');
}finally{await browser.close();await new Promise(resolve=>server.close(resolve));}
