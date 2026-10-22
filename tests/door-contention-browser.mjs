import { chromium } from 'playwright';
import assert from 'node:assert/strict';
import { mkdir, readFile, writeFile } from 'node:fs/promises';

const out = process.env.BREACH_ARTIFACTS || 'tests/artifacts/door-contention/browser';
await mkdir(out,{recursive:true});
const build = JSON.parse(await readFile('dist/engine-export-manifest.json','utf8'));
const url = process.env.BREACH_URL || 'http://127.0.0.1:8098';
const ids = ['alpha','bravo','charlie','delta'];
const browser = await chromium.launch({channel:'chrome',headless:true,args:['--enable-unsafe-swiftshader']});
const context = await browser.newContext({viewport:{width:1440,height:1000}});
await context.addInitScript(() => {
  let ui;
  window.doorQA = {state:null,samples:[],capture:false};
  Object.defineProperty(window,'BreachUI',{get:()=>ui,set(value){
    ui=value;
    const receive=value.receive;
    value.receive=function(raw){
      const data=JSON.parse(raw);
      if(data.type==='state'){
        window.doorQA.state=data;
        if(window.doorQA.capture)window.doorQA.samples.push(data);
      }
      return receive.call(value,raw);
    };
  }});
});
const page = await context.newPage();
const errors = [];
page.on('pageerror',error=>errors.push(error.message));
page.on('console',message=>{if(message.type()==='error'||/SCRIPT ERROR|Parse Error/.test(message.text()))errors.push(message.text());});
const send = data=>page.evaluate(value=>window.BreachBridge.send(JSON.stringify(value)),data);
const rows = [];
let passed = false;

function fixture(drill,axis){
  const data={schema_version:3,id:`PORTAL_${drill?'DRILL':'CHAIN'}_${axis}`,revision:1,title:'문 통과 검증',seed:51,bounds:[12,12],focus:[6,6],
    rooms:drill?[{id:'room',x:6,z:3.5,w:5,d:5,indoor:true},{id:'outside',x:6,z:9,w:12,d:6,indoor:false}]:[
      {id:'outside',x:6,z:9,w:12,d:6,indoor:false},{id:'hall',x:6,z:4.5,w:12,d:3,indoor:true},{id:'room',x:6,z:1.5,w:12,d:3,indoor:true}],
    walls:[{id:'left',x:2.5,z:6,w:5,d:0.2},{id:'right',x:9.5,z:6,w:5,d:0.2}],props:[],
    doors:[{id:'d1',x:6,z:6,axis:'x',w:drill?1.8:2,d:0.2,state:'CLOSED',hinge_side:-1,swing_sign:drill?1:-1,hp:100,locked:false,material:'wood'}],
    units:ids.map((id,index)=>({id,name:id.toUpperCase(),role:'TEST',x:6,z:8+index*0.75,facing:-Math.PI/2,weapon:'standard',ammo:24,reserve_ammo:0})),
    enemies:[],civilians:[],objectives:['순서대로 문을 통과하세요.'],win:[{type:'reach_zone',zone:[11,11,0.2,0.2]}],fail:[]};
  if(drill){
    const starts=[[7.3,6.45],[4.7,6.45],[7.3,7.15],[4.7,7.15]];
    data.units.forEach((unit,index)=>{[unit.x,unit.z]=starts[index];unit.facing=Math.atan2(6-unit.z,6-unit.x);});
    data.walls.push({id:'west',x:3.5,z:3.5,w:0.2,d:5},{id:'east',x:8.5,z:3.5,w:0.2,d:5},{id:'north',x:6,z:1,w:5,d:0.2});
  }else{
    data.doors.push({...data.doors[0],id:'d2',z:3});
    data.walls.push({id:'left2',x:2.5,z:3,w:5,d:0.2},{id:'right2',x:9.5,z:3,w:5,d:0.2});
  }
  if(axis==='z'){
    for(const actor of [...data.units,...data.walls,...data.rooms,...data.doors]){
      [actor.x,actor.z]=[actor.z,actor.x];
      if(actor.w!==undefined)[actor.w,actor.d]=[actor.d,actor.w];
      if(actor.axis){actor.axis='z';actor.swing_sign*=-1;}
      if(actor.facing!==undefined)actor.facing=Math.PI/2-actor.facing;
    }
  }
  return data;
}

function occupancy(sample,door){
  return sample.units.filter(unit=>unit.hp>0&&Math.abs(unit.x-door.x)<=door.w/2+0.23&&Math.abs(unit.z-door.z)<=door.d/2+0.23).length;
}

function entryApproaches(sample,door){
  return sample.units.filter(unit=>{
    const command=unit.commands.find(command=>!['SUCCEEDED','CANCELLED'].includes(command.state));
    const outside=door.axis==='x'?unit.z>=door.z:unit.x>=door.x;
    return outside&&['entry','domination'].includes(command?.args?.drill?.stage)&&Math.hypot(unit.velocity_x,unit.velocity_z)>0.001;
  }).length;
}

try{
  await page.goto(url);
  await page.waitForFunction(()=>window.BreachBridge?.send&&!document.querySelector('#start-mission').disabled,null,{timeout:120000});
  for(const drill of [true,false])for(const axis of ['x','z']){
    const data=fixture(drill,axis),label=data.id;
    console.log('START',label);
    await page.evaluate(()=>{window.doorQA.capture=false;window.doorQA.samples=[];});
    await send({action:'import_mission',data});
    await page.waitForFunction(id=>window.doorQA.state?.mission===id&&window.doorQA.state.mode==='PLANNING',label,{timeout:60000});
    if(drill)await send({action:'room_drill',door_id:'d1',method:'OPEN_DOOR',order:ids});
    else for(let index=0;index<4;index++){
      await send({action:'select',id:ids[index]});
      await send({action:'command',type:'MOVE',args:{target:axis==='x'?[4.8+index*0.8,1.5]:[1.5,4.8+index*0.8]}});
    }
    await page.waitForFunction(()=>window.doorQA.state.units.every(unit=>unit.commands.length>0));
    await page.screenshot({path:`${out}/${label}-plan.png`});
    await page.evaluate(()=>{window.doorQA.capture=true;});
    await send({action:'toggle'});
    await page.waitForFunction(({door})=>{
      const s=window.doorQA.state;
      return s?.time>0&&s.units.some(u=>Math.abs(u.x-door.x)<door.w/2+0.23&&Math.abs(u.z-door.z)<door.d/2+0.23);
    },{door:data.doors[0]},{timeout:60000});
    await page.screenshot({path:`${out}/${label}-passage.png`});
    await page.waitForFunction(()=>{
      const s=window.doorQA.state;
      return s?.command_failures>0||s?.time>=40||s?.units.every(unit=>unit.commands.every(command=>['SUCCEEDED','CANCELLED'].includes(command.state)));
    },null,{timeout:120000});
    await send({action:'pause'});
    const result=await page.evaluate(()=>{window.doorQA.capture=false;return {done:window.doorQA.state,samples:window.doorQA.samples};});
    await page.screenshot({path:`${out}/${label}-done.png`});
    const maximum=Math.max(0,...result.samples.map(sample=>occupancy(sample,data.doors[0])));
    const maximumApproaches=drill?Math.max(0,...result.samples.map(sample=>entryApproaches(sample,data.doors[0]))):null;
    assert.equal(maximum,1,`${label}: only one living body intersects the doorway at a time`);
    if(drill)assert.equal(maximumApproaches,1,`${label}: followers wait while the current leader approaches the doorway`);
    assert.equal(result.done.command_failures,0,`${label}: no failed commands`);
    assert.ok(result.done.units.every(unit=>unit.commands.every(command=>command.state==='SUCCEEDED')),`${label}: all four complete`);
    await writeFile(`${out}/${label}-states.json`,JSON.stringify(result));
    rows.push({scenario:label,maximumPortalOccupancy:maximum,maximumEntryApproaches:maximumApproaches,time:result.done.time,samples:result.samples.length});
    console.log('PASS',JSON.stringify(rows.at(-1)));
  }
  assert.deepEqual(errors,[]);
  passed=true;
}catch(error){
  console.error(error);
  await page.screenshot({path:`${out}/failure.png`,timeout:5000}).catch(()=>{});
  const state=await Promise.race([page.evaluate(()=>window.doorQA.state).catch(()=>null),new Promise(resolve=>setTimeout(()=>resolve(null),2000))]);
  await writeFile(`${out}/failure-state.json`,JSON.stringify(state,null,2));
  throw error;
}finally{
  await writeFile(`${out}/report.json`,JSON.stringify({url,sourceHash:build.sourceHash,passed,rows,errors},null,2));
  await browser.close();
}
