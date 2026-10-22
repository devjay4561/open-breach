import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {readFile} from 'node:fs/promises';
import {chromium} from 'playwright';

const storage=await readFile(new URL('../web/storage.js',import.meta.url));
const server=createServer((request,response)=>{
  response.setHeader('Content-Type',request.url==='/storage.js'?'text/javascript':'text/html');
  response.end(request.url==='/storage.js'?storage:'<!doctype html><title>Operator save regression</title>');
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const browser=await chromium.launch({channel:process.env.BREACH_CHANNEL||'chrome',headless:true});
try{
  const page=await browser.newPage(),url=`http://127.0.0.1:${server.address().port}`;
  await page.goto(url);
  const initial=await page.evaluate(async()=>{
    const {BreachStorage}=await import('/storage.js'),first=new BreachStorage(),second=new BreachStorage();
    await first.saveSettings({language:'ko'},0);
    await first.put('progress',{id:'campaign',inventory:{stun:7,breach:3},lost:['echo']});
    await Promise.all([first.saveOperatorProfile('raven',{weapon:'light',appearance:{callsign:'NOVA'}}),second.saveOperatorProfile('moss',{weapon:'standard',armor:'swift_v3'})]);
    return {profiles:await first.operatorProfiles(),settings:await first.get('settings','current'),campaign:await first.get('progress','campaign')};
  });
  assert.equal(initial.profiles.raven.appearance.callsign,'NOVA');
  assert.equal(initial.profiles.moss.armor,'swift_v3');
  assert.equal(initial.settings.data.language,'ko');
  assert.deepEqual(initial.campaign.inventory,{stun:7,breach:3});
  await page.reload();
  const reloaded=await page.evaluate(async()=>{
    const {BreachStorage}=await import('/storage.js'),store=new BreachStorage();
    const profiles=await store.operatorProfiles();
    let rejected=false;try{await store.saveOperatorProfile('../bad',{weapon:'light'});}catch{rejected=true;}
    return {profiles,rejected};
  });
  assert.deepEqual(reloaded.profiles,initial.profiles);assert.equal(reloaded.rejected,true);
  console.log('Operator persistence: 6 browser checks passed');
}finally{await browser.close();await new Promise(resolve=>server.close(resolve));}
