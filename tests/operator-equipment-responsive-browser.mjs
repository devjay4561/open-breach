import assert from 'node:assert/strict';
import {mkdir,writeFile} from 'node:fs/promises';
import {chromium} from 'playwright';
const url=process.env.BREACH_URL||'http://127.0.0.1:8083';
const out=process.env.BREACH_ARTIFACTS||'tests/artifacts/operator-customization-responsive';
await mkdir(out,{recursive:true});
const manifestResponse=await fetch(new URL('engine-export-manifest.json',url.endsWith('/')?url:`${url}/`));
assert.equal(manifestResponse.status,200,'Candidate serves its engine export manifest');
const manifest=await manifestResponse.json();
const browser=await chromium.launch({channel:'chrome',headless:true,args:['--enable-unsafe-swiftshader']});
const evidence={url,testedAt:new Date().toISOString(),sourceHash:manifest.sourceHash,enginePackageHash:manifest.files['engine.pck'],browser:browser.version()};
const page=await browser.newPage({viewport:{width:1600,height:1000}}),errors=[],results=[];
page.on('pageerror',error=>errors.push(error.message));page.setDefaultTimeout(60000);
try{
  await page.goto(url);await page.locator('#loading').waitFor({state:'hidden',timeout:180000});
  await page.locator('#title-start').click();await page.locator('#tab-T01').click();await page.locator('#select-to-briefing').click();await page.locator('#prepare-squad').click();await page.locator('[data-customize="raven"]').click();
  for(const viewport of [{width:1600,height:1000},{width:1280,height:720},{width:430,height:860}]){
    await page.setViewportSize(viewport);await page.locator('#operator-preview').evaluate(node=>node.scrollIntoView({block:'start'}));
    const geometry=await page.evaluate(()=>{const modal=document.querySelector('#modal'),controls=document.querySelector('.customization-controls'),preview=document.querySelector('#operator-preview'),rect=preview.getBoundingClientRect();return {modalOverflow:modal.scrollWidth-modal.clientWidth,controlsOverflow:controls.scrollWidth-controls.clientWidth,headerBottom:modal.querySelector('header').getBoundingClientRect().bottom,preview:{x:rect.x,y:rect.y,width:rect.width,height:rect.height},profile:document.querySelector('.operator-workbench').dataset.profile,briefingHidden:getComputedStyle(document.querySelector('#menu')).visibility==='hidden'};});
    assert.ok(geometry.modalOverflow<=1,`${viewport.width}px modal overflow ${geometry.modalOverflow}`);assert.ok(geometry.controlsOverflow<=1,`${viewport.width}px controls overflow ${geometry.controlsOverflow}`);assert.ok(geometry.preview.width>150&&geometry.preview.height>=150);assert.equal(geometry.profile,'raven');assert.equal(geometry.briefingHidden,true);
    assert.ok(geometry.preview.y>=geometry.headerBottom,`${viewport.width}px preview clears sticky modal header`);
    // Allow the viewport resize and isolated equipment camera one frame to settle.
    await page.waitForTimeout(600);await page.screenshot({path:`${out}/customizer-${viewport.width}.png`});await page.locator('#operator-preview').screenshot({path:`${out}/preview-${viewport.width}.png`});results.push({viewport,...geometry});
  }
  await page.locator('#squad-done').click();assert.equal(await page.locator('#modal').isVisible(),false);assert.equal(await page.locator('#menu').evaluate(node=>getComputedStyle(node).visibility),'visible');assert.deepEqual(errors,[]);
  const finalManifest=await (await fetch(new URL('engine-export-manifest.json',url.endsWith('/')?url:`${url}/`))).json();assert.equal(finalManifest.sourceHash,evidence.sourceHash,'Candidate stayed unchanged during responsive verification');
  await writeFile(`${out}/report.json`,JSON.stringify({...evidence,status:'PASS',results,errors},null,2));console.log('Operator equipment responsive browser: 3 viewports passed');
}catch(error){await page.screenshot({path:`${out}/failure.png`}).catch(()=>{});await writeFile(`${out}/report.json`,JSON.stringify({...evidence,status:'FAIL',error:error.stack,results,errors},null,2));throw error;}finally{await browser.close();}
