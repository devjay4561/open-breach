import assert from 'node:assert/strict';
import {mkdir,writeFile} from 'node:fs/promises';
import {chromium} from 'playwright';
import {goToBriefing,setCycler} from './lib/menu.mjs';

const url=process.env.BREACH_URL||'http://127.0.0.1:8084';
const out=process.env.BREACH_ARTIFACTS||'tests/artifacts/equipment-photo-ui';
await mkdir(out,{recursive:true});
const browser=await chromium.launch({channel:'chrome',headless:true,args:['--enable-unsafe-swiftshader']});
const page=await browser.newPage({viewport:{width:1288,height:953}}),errors=[],checks=[];
page.on('pageerror',error=>errors.push(error.message));
page.on('response',response=>{if(response.status()>=400)errors.push(`HTTP ${response.status()} ${response.url()}`);});
page.setDefaultTimeout(60000);
await page.addInitScript(()=>{
  let bridge;
  Object.defineProperty(window,'BreachUI',{configurable:true,get:()=>bridge,set(value){
    bridge=value;const receive=value.receive;
    value.receive=function(raw){const message=typeof raw==='string'?JSON.parse(raw):raw;if(message.type==='state')window.photoQAState=structuredClone(message);return receive.apply(this,arguments);};
  }});
});
const passed=name=>{checks.push(name);console.log(`PASS ${name}`);};
try{
  await page.goto(url);await page.locator('#loading').waitFor({state:'hidden',timeout:180000});
  const assets=await page.evaluate(async()=>{
    const {CATALOG}=await import('./operator-equipment.js'),generation=await (await fetch('assets/equipment/generation.json')).json();
    const ids=['weapons','sidearms','armor','helmets','attachments','equipment'].flatMap(key=>CATALOG[key].map(item=>item.id));
    const photos=await Promise.all(generation.assets.map(asset=>new Promise((resolve,reject)=>{const photo=new Image();photo.onload=()=>resolve({id:asset.id,width:photo.naturalWidth,height:photo.naturalHeight});photo.onerror=()=>reject(new Error(asset.path));photo.src=asset.path;})));
    return {ids,photos};
  });
  assert.deepEqual(assets.photos.map(photo=>photo.id).sort(),assets.ids.sort());
  assert.equal(assets.photos.length,20);assert(assets.photos.every(photo=>photo.width===1200&&photo.height>=700));
  passed('All 20 catalog items decode their own generated photograph');
  await goToBriefing(page,'M01');await page.locator('#prepare-squad').click();
  assert.equal(await page.locator('[data-customize]').count(),4);
  assert.equal(await page.locator('[data-slot="weapon"] [data-cycle-set="shotgun"]').isDisabled(),true);
  assert.equal(await page.locator('[data-slot="weapon"] [data-cycle-set="suppressed"]').isDisabled(),true);
  await page.locator('[data-slot="weapon"] [data-cycle-set="light"] img').click();
  assert.equal(await page.locator('.weapon-showcase img').getAttribute('src'),'assets/equipment/light.jpg');
  await page.locator('[data-attachment="extended_mag"] img').click();
  assert.equal(await page.locator('[data-stat="ammo"]').textContent(),'40');
  await page.locator('[data-slot="armor"] .gear-current-photo img').click();
  await page.locator('[data-slot="armor"] [data-cycle-set="swift_v3"] img').click();
  await setCycler(page,'[data-slot="helmet"]','crown_h2');
  await page.locator('[data-equipment-extra="probe_c1"] img').click();
  assert.equal(await page.locator('[data-slot="armor"] .gear-current-photo img').getAttribute('src'),'assets/equipment/swift_v3.jpg');
  passed('Clicking equipment photos updates weapon, attachments, armor, helmet and camera');
  await page.locator('[data-customize="echo"]').click();
  assert.equal(await page.locator('.weapon-showcase img').getAttribute('src'),'assets/equipment/standard.jpg');
  await page.locator('[data-customize="raven"]').click();
  assert.equal(await page.locator('.weapon-showcase img').getAttribute('src'),'assets/equipment/light.jpg');
  assert.equal(await page.locator('[data-attachment="extended_mag"]').getAttribute('aria-pressed'),'true');
  await page.waitForFunction(()=>document.querySelector('#profile-save-status')?.textContent==='대원 장비 저장됨');
  await page.reload();await page.locator('#loading').waitFor({state:'hidden',timeout:180000});
  await goToBriefing(page,'M01');await page.locator('#prepare-squad').click();
  assert.equal(await page.locator('.weapon-showcase img').getAttribute('src'),'assets/equipment/light.jpg');
  assert.equal(await page.locator('[data-slot="armor"] output').textContent(),'스위프트 V3');
  passed('Operator tabs preserve independent gear across a browser reload');
  const geometry=[];
  for(const viewport of [{width:1288,height:953},{width:1280,height:720},{width:430,height:860}]){
    await page.setViewportSize(viewport);await page.locator('#modal').evaluate(node=>node.scrollTop=0);
    await page.waitForTimeout(500);
    await page.waitForFunction(()=>[...document.querySelectorAll('#modal img')].filter(img=>{const r=img.getBoundingClientRect();return img.getClientRects().length&&r.y<innerHeight&&r.bottom>0;}).every(img=>img.complete&&img.naturalWidth>0));
    const result=await page.evaluate(()=>{
      const rect=selector=>{const r=document.querySelector(selector).getBoundingClientRect();return {x:r.x,y:r.y,right:r.right,bottom:r.bottom,width:r.width,height:r.height};};
      const modal=document.querySelector('#modal'),controls=document.querySelector('.customization-controls');
      return {modalOverflow:modal.scrollWidth-modal.clientWidth,controlsOverflow:controls.scrollWidth-controls.clientWidth,photo:rect('.weapon-showcase'),operator:rect('#operator-preview'),controls:rect('.customization-controls'),footer:rect('.dialog-footer'),header:rect('#modal>header')};
    });
    assert(result.modalOverflow<=1);assert(result.controlsOverflow<=1);
    assert(result.operator.width>150&&result.operator.height>=150);
    assert(result.operator.y>=result.header.bottom);
    if(viewport.width>700){assert(result.operator.bottom<=result.footer.y+1,`3D preview clears the fixed footer: ${JSON.stringify({viewport,operator:result.operator,footer:result.footer})}`);assert(result.photo.bottom<=result.operator.y);assert(result.operator.right<=result.controls.x+1);assert(result.photo.right<=result.controls.x+1);}
    assert(await page.locator('#squad-done').isVisible());
    await page.screenshot({path:`${out}/equipment-${viewport.width}.png`});geometry.push({viewport,...result});
  }
  passed('Photo and 3D preview layout fits desktop, short desktop and narrow screens');
  await page.setViewportSize({width:1288,height:953});await page.locator('#squad-done').click();
  await page.locator('#start-mission').click();await page.waitForFunction(()=>window.photoQAState?.mode==='PLANNING');
  const operators=await page.evaluate(()=>window.photoQAState.units.filter(unit=>unit.kind==='unit'||unit.roster_id));
  const raven=operators.find(unit=>unit.roster_id==='raven'),echo=operators.find(unit=>unit.roster_id==='echo');
  assert(raven);assert(echo);assert.equal(raven.weapon,'light');assert.equal(raven.armor,'swift_v3');assert.equal(raven.helmet,'crown_h2');assert.equal(raven.max_ammo,40);assert(raven.attachments.includes('extended_mag'));assert.equal(echo.weapon,'standard');assert.equal(raven.cameras,1);
  passed('The real Godot mission receives each operator’s selected equipment');
  assert.deepEqual(errors,[]);
  await writeFile(`${out}/photo-report.json`,JSON.stringify({status:'PASS',url,browser:browser.version(),checks,assets:assets.photos,geometry,errors},null,2));
}catch(error){await page.screenshot({path:`${out}/photo-failure.png`}).catch(()=>{});throw error;}finally{await browser.close();}
