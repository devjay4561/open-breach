import assert from 'node:assert/strict';
import {mkdir,writeFile} from 'node:fs/promises';
import {chromium} from 'playwright';
const url=process.env.BREACH_URL||'http://127.0.0.1:8091';
const out=process.env.BREACH_ARTIFACTS||'.runtime/ui-enemy-tiers-2026-10-16/browser';
await mkdir(out,{recursive:true});
const browser=await chromium.launch({channel:'chrome',headless:true,args:['--enable-unsafe-swiftshader']});
const context=await browser.newContext({viewport:{width:1024,height:768}});
await context.addInitScript(()=>{
  let ui;window.tierQA={};
  Object.defineProperty(window,'BreachUI',{get:()=>ui,set(value){ui=value;const receive=value.receive;value.receive=function(raw){const message=JSON.parse(raw);if(message.type==='state')window.tierQA.state=message;return receive.apply(this,arguments);};}});
});
const page=await context.newPage(),errors=[],checks=[];
page.on('pageerror',error=>errors.push(error.message));
page.on('console',message=>{if(message.type()==='error'||/SCRIPT ERROR|Parse Error/.test(message.text()))errors.push(message.text());});
const send=message=>page.evaluate(message=>window.BreachBridge.send(JSON.stringify(message)),message);
const mode=value=>page.waitForFunction(value=>window.tierQA.state?.mode===value,value,{timeout:60000});
const shot=async name=>{await page.waitForTimeout(250);await page.screenshot({path:`${out}/${name}.png`});};
try{
  await page.goto(url);
  await page.locator('#loading').waitFor({state:'hidden',timeout:120000});
  await page.locator('#title-start').click();
  await page.locator('#tab-M01').click();
  assert.match(await page.locator('#brief-enemy-strengths').innerText(),/약 4 \/ 중 2 \/ 강 0/);
  await shot('1024-board');
  await page.locator('#mission-detail').evaluate(node=>{node.scrollTop=node.scrollHeight;});
  const lastGoal=page.locator('#brief-stars span').last();
  assert.equal(await lastGoal.evaluate(node=>{const r=node.getBoundingClientRect();return r.top>=0&&r.bottom<=innerHeight&&node.contains(document.elementFromPoint(r.x+r.width/2,r.y+r.height/2));}),true);
  checks.push('Small-window briefing scroll exposes the final goal without CTA overlap');
  await page.locator('#tab-T01').click();
  await page.locator('#select-to-briefing').click();
  await page.locator('#start-mission').click();
  await mode('PLANNING');
  checks.push('1024×768 visible mission CTA reaches actual planning');
  await shot('1024-planning');
  // Public command bridge only advances the real tutorial to its real result;
  // the UI paths under regression are all exercised by normal DOM clicks.
  await send({action:'select',id:'alpha'});
  for(const [index,target] of [[6.4,9],[12,9],[18.4,9]].entries()){
    await send({action:'command',type:'MOVE',args:{target}});
    await send({action:'toggle'});
    await page.waitForFunction(n=>(window.tierQA.state?.objectives?.neutralized||0)>=n,index+1,{timeout:60000});
    if(index<2){await send({action:'pause'});await mode('PLANNING');}
  }
  await mode('RESULT');
  await page.locator('#result').waitFor({state:'visible'});
  await page.setViewportSize({width:1440,height:900});
  await page.locator('#result-progression [data-open="progression"]').click();
  await page.locator('#progression-equip').click();
  await page.locator('#operator-preview').scrollIntoViewIfNeeded();
  await shot('result-operator-preview');
  assert.equal(await page.locator('#result').evaluate(node=>getComputedStyle(node).visibility),'hidden');
  assert.equal(await page.evaluate(()=>window.tierQA.state.mode),'RESULT');
  checks.push('Result gear preview hides debrief without losing RESULT state');
  await page.locator('[data-loadout="raven"][data-slot="weapon"] [data-cycle-set="shotgun"]').click();
  await shot('result-new-shotgun');
  await page.locator('#squad-done').click();
  assert.equal(await page.locator('#result').evaluate(node=>getComputedStyle(node).visibility),'visible');
  await page.locator('#result [data-action="retry"]').click();
  await mode('PLANNING');
  const retry=await page.evaluate(()=>window.tierQA.state);
  assert.equal(retry.mission,'T01');
  assert.equal(retry.units[0].weapon,'shotgun');
  assert.equal(retry.units[0].ammo,8);
  assert.equal(retry.time,0);
  await shot('retry-new-shotgun');
  checks.push('Real tutorial reward → new shotgun → retry equips shotgun with 8 rounds');
  await send({action:'menu'});await mode('MENU');
  for(let i=0;i<3&&await page.locator('.menu-screen:not([hidden]) .back-button').count();i++)await page.locator('.menu-screen:not([hidden]) .back-button').click();
  await page.locator('#title-editor').click();
  await page.locator('[data-editor-tool="enemies"]').click();
  const canvas=page.locator('[data-editor-canvas]');
  await canvas.click({position:{x:250,y:250}});
  await page.locator('[data-editor-field="strength"]').selectOption('strong');
  await page.locator('[data-editor-field="strength"]').scrollIntoViewIfNeeded();
  await shot('editor-strong-enemy');
  assert.equal(await page.locator('[data-editor-field="strength"]').inputValue(),'strong');
  checks.push('Map editor exposes editable weak/medium/strong NPC tiers');
  assert.deepEqual(errors,[]);
}catch(error){errors.push(error.stack);await shot('failure').catch(()=>{});process.exitCode=1;}
finally{await writeFile(`${out}/report.json`,JSON.stringify({url,checks,errors,passed:!errors.length,limits:['Focused Chrome/SwiftShader checks; no full campaign or performance certification.','Tutorial result was reached with public command inputs, never forced state.']},null,2));await browser.close();console.log(JSON.stringify({checks,errors}));}
