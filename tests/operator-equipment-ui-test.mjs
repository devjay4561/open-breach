// Public UI bridge fixture: durable roster gear and native-menu cancellation.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import {chromium} from 'playwright';
const briefing={id:'T01',title:'조작 익히기',seed:1024,units:[{id:'alpha'},{id:'bravo'}],objectives:['표적 처리'],win:[{type:'neutralize_all'}],fail:[]};
const engine=`window.gearTest={sent:[]};window.BreachBridge.send=text=>{const data=JSON.parse(text);window.gearTest.sent.push(data);if(data._loading_id)window.BreachUI.receive({type:'loading',active:false,id:data._loading_id});};window.Engine=class{async startGame(){window.BreachUI.receive({type:'ready',briefings:[${JSON.stringify(briefing)}]});}};`;
const mime={'.js':'text/javascript','.css':'text/css','.html':'text/html','.svg':'image/svg+xml','.jpg':'image/jpeg'};
const server=createServer(async(req,res)=>{try{const url=new URL(req.url,'http://localhost');if(url.pathname==='/engine.js'){res.setHeader('content-type','text/javascript');res.end(engine);return;}const name=url.pathname==='/'?'index.html':url.pathname.slice(1);if(name.includes('..')){res.writeHead(400);res.end();return;}const bytes=await readFile(new URL('../web/'+name,import.meta.url));res.setHeader('content-type',mime[name.slice(name.lastIndexOf('.'))]||'application/octet-stream');res.end(bytes);}catch{res.writeHead(404);res.end();}});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const browser=await chromium.launch({headless:true,channel:process.env.BREACH_CHANNEL||'chrome'}),page=await browser.newPage({viewport:{width:1440,height:1000}}),errors=[];
page.on('pageerror',error=>errors.push(error.message));let checks=0;
const check=(actual,expected)=>{assert.deepEqual(actual,expected);checks++;};
const setCycler=async(slot,value,id='raven')=>{const root=page.locator(`[data-loadout="${id}"][data-slot="${slot}"]`);await root.locator('output').click();await root.locator(`[data-cycle-set="${value}"]`).click();};
const latest=action=>page.evaluate(action=>window.gearTest.sent.filter(item=>item.action===action).at(-1),action);
const openPreparation=async()=>{await page.locator('#title-start').click();await page.locator('#select-to-briefing').click();await page.locator('#prepare-squad').click();};
const checkPreviewClip=async()=>{
  await page.waitForFunction(()=>{
    const canvas=document.querySelector('#canvas'),rect=document.querySelector('#operator-preview').getBoundingClientRect(),modal=document.querySelector('#modal').getBoundingClientRect();
    const top=Math.max(0,rect.top,modal.top),bottom=Math.min(innerHeight,rect.bottom,modal.bottom),left=Math.max(0,rect.left,modal.left),right=Math.min(innerWidth,rect.right,modal.right);
    const edges=bottom>top&&right>left?[top,innerWidth-right,innerHeight-bottom,left]:[innerHeight,0,0,0];
    return ['top','right','bottom','left'].every((edge,index)=>Math.abs(parseFloat(canvas.style.getPropertyValue(`--operator-preview-${edge}`))-edges[index])<1);
  });
  check(await page.locator('#canvas').evaluate(node=>getComputedStyle(node).clipPath.startsWith('inset(')),true);
};
const defaultMenuCheck=async selector=>page.evaluate(selector=>{const target=document.querySelector(selector);let seen=0;const handler=()=>seen++;target.addEventListener('contextmenu',handler,{once:true});const event=new MouseEvent('contextmenu',{bubbles:true,cancelable:true,button:2});const returned=target.dispatchEvent(event);return {prevented:event.defaultPrevented,returned,seen};},selector);
try{
  await page.goto(`http://127.0.0.1:${server.address().port}`);await page.locator('#loading').waitFor({state:'hidden'});await openPreparation();
  await checkPreviewClip();
  check(await page.locator('#modal').evaluate(node=>{const content=document.querySelector('#modal-content');return node.scrollHeight<=content.offsetTop+content.offsetHeight+1;}),true);
  check(await defaultMenuCheck('#canvas'),{prevented:true,returned:false,seen:1});check(await defaultMenuCheck('#profile-save'),{prevented:true,returned:false,seen:1});
  check(await page.locator('.weapon-showcase img').getAttribute('src'),'assets/equipment/standard.jpg');
  await page.locator('[data-customize="echo"]').click();await setCycler('weapon','light','echo');
  check(await page.locator('.operator-workbench').getAttribute('data-profile'),'echo');
  check(await page.locator('.weapon-showcase img').getAttribute('src'),'assets/equipment/light.jpg');
  await page.locator('[data-customize="raven"]').click();
  check(await page.locator('.weapon-showcase img').getAttribute('src'),'assets/equipment/standard.jpg');
  check(await page.locator('[data-slot="weapon"] .cycler-list').isVisible(),true);
  check(await page.locator('[data-slot="weapon"] [data-cycle-set="shotgun"]').isDisabled(),true);
  await page.locator('[data-slot="armor"] output').focus();await page.keyboard.press('Enter');
  check(await page.locator('[data-slot="armor"] .cycler-list').isVisible(),true);
  await page.locator('[data-slot="armor"] [data-cycle-set="veil_v1"]').click();
  check(await page.locator('[data-slot="armor"] .gear-current-photo img').getAttribute('src'),'assets/equipment/veil_v1.jpg');
  await page.locator('.performance-settings summary').click();
  await setCycler('preset','breacher');check(await page.locator('[data-slot="armor"] output').textContent(),'바스천 V4');
  check(await page.locator('.performance-settings').evaluate(node=>node.open),true);
  await setCycler('weapon','light');await setCycler('armor','veil_v1');await setCycler('helmet','crown_h2');await setCycler('sidearm','pico_p1');
  if(await page.locator('[data-attachment="dot"]').getAttribute('aria-pressed')==='true')await page.locator('[data-attachment="dot"]').click();
  await page.locator('[data-attachment="extended_mag"]').click();check(await page.locator('[data-stat="ammo"]').textContent(),'40');check(await page.locator('[data-attachment="scope"]').isDisabled(),true);
  await page.locator('.appearance-settings summary').click();await page.locator('[data-appearance="name"]').fill('테스트 대원');await page.locator('[data-appearance="callsign"]').fill('KITE');await page.locator('[data-appearance-patch="arrow"]').click();
  check(await page.locator('.appearance-settings').evaluate(node=>node.open),true);await page.locator('[data-appearance-color="#40516c"]').click();await page.locator('#profile-save').click();await page.waitForFunction(()=>document.querySelector('#profile-save-status')?.textContent.includes('저장됨'));
  check(await page.locator('[data-customize="raven"] strong').textContent(),'테스트 대원');check(await defaultMenuCheck('[data-appearance="name"]'),{prevented:true,returned:false,seen:1});
  for(const viewport of [{width:1280,height:720},{width:430,height:860}]){
    await page.setViewportSize(viewport);await page.locator('.operator-workbench').scrollIntoViewIfNeeded();
    check(await page.locator('#modal').evaluate(node=>node.scrollWidth<=node.clientWidth+1),true);
    check(await page.locator('.customization-controls').evaluate(node=>node.scrollWidth<=node.clientWidth+1),true);
    await checkPreviewClip();
    if(process.env.BREACH_CAPTURE_UI)await page.screenshot({path:`${process.env.BREACH_CAPTURE_UI}-${viewport.width}.png`});
  }
  await page.setViewportSize({width:1440,height:1000});
  await page.setViewportSize({width:1440,height:360});await page.locator('#modal').evaluate(node=>{node.scrollTop=node.scrollHeight;});await checkPreviewClip();
  check((await latest('preview_operator')).profile,null);
  await page.setViewportSize({width:1440,height:1000});
  await page.locator('#squad-done').click();await page.waitForFunction(()=>parseFloat(document.querySelector('#canvas').style.getPropertyValue('--briefing-map-left'))===Math.round(document.querySelector('.briefing-map').getBoundingClientRect().left));check(await page.locator('#canvas').evaluate(node=>getComputedStyle(node).clipPath.startsWith('inset(')),true);await page.locator('#start-mission').click();await page.waitForFunction(()=>window.gearTest.sent.some(item=>item.action==='start'));const start=await latest('start');
  check(start.roster[0].id,'raven');check(start.roster[0].name,'테스트 대원');check(start.loadout.alpha.weapon,'light');check(start.loadout.alpha.armor,'veil_v1');check(start.loadout.alpha.helmet,'crown_h2');check(start.loadout.alpha.attachments,['extended_mag']);check(start.loadout.alpha.equipment,{stun:1,probe_c1:1});check(start.loadout.alpha.appearance,{name:'테스트 대원',callsign:'KITE',color:'#40516c',patch:'arrow'});
  await page.reload();await page.locator('#loading').waitFor({state:'hidden'});await openPreparation();check(await page.locator('[data-loadout="raven"][data-slot="weapon"] output').textContent(),'미카 S2');check(await page.locator('[data-slot="armor"] output').textContent(),'베일 V1');check(await page.locator('[data-customize="raven"] strong').textContent(),'테스트 대원');
  await page.locator('#squad-done').click();await page.evaluate(()=>window.BreachUI.receive({type:'state',mode:'PLANNING',mission:'T01',selected:'alpha',units:[{id:'alpha',roster_id:'raven',name:'테스트 대원',hp:100,ammo:32,sidearm:'pico_p1',active_weapon:'primary',cameras:1,stuns:1,commands:[{type:'OPEN_AND_FLASH',state:'PENDING',args:{door_id:'d1',target:[5,6]}}]}]}));
  check(await page.locator('#canvas').evaluate(node=>getComputedStyle(node).clipPath),'none');
  check(await defaultMenuCheck('#unit-cards button'),{prevented:true,returned:false,seen:1});
  await page.locator('[data-flash-target="0"]').click();check((await latest('tool')).tool,'flash_target');
  await page.evaluate(()=>window.BreachUI.receive({type:'context',target:'door',id:'d1',unit_id:'alpha',screen:[700,350],actions:['OPEN_DOOR','OPEN_AND_FLASH','PEEK_CAMERA'],disabled:{}}));check(await defaultMenuCheck('#context-popover button'),{prevented:true,returned:false,seen:1});await page.locator('#context-popover [data-context-index="1"]').click();const flash=await latest('command');check(flash.type,'OPEN_AND_FLASH');check(flash.args.door_id,'d1');
  await page.locator('#equipment-modes').click();check(await page.locator('[data-tool="camera"]').isEnabled(),true);await page.locator('#switch-weapon').click();check((await latest('command')).args.slot,'secondary');
  check(errors,[]);console.log(`Operator equipment UI: ${checks} checks passed (public bridge fixture)`);
}finally{await browser.close();await new Promise(resolve=>server.close(resolve));}
