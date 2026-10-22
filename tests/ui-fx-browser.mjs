// RC 2-1: fx consumer smoke test — injects {type:'fx',...} messages directly
// (neither staged engine build emits fx yet) and asserts the DOM reaction
// appears and auto-clears, as part of the combat feedback contract.
import { chromium } from 'playwright';
import assert from 'node:assert/strict';

const url = process.env.BREACH_URL || 'http://127.0.0.1:8080';
const browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--enable-unsafe-swiftshader'] });
const page = await browser.newPage();
await page.addInitScript(()=>{
  let ui;Object.defineProperty(window,'BreachUI',{configurable:true,get:()=>ui,set(value){ui=value;const receive=ui.receive;ui.receive=function(raw){const data=JSON.parse(raw);if(data.type==='state')window.fxTestState=data;return receive.call(ui,raw);};}});
});
await page.goto(url);
await page.locator('#title-start').waitFor({ state: 'visible' });
await page.waitForFunction(() => !document.querySelector('#start-mission').disabled);
await page.locator('#title-start').click();
await page.locator('#tab-T01').click();
await page.locator('#select-to-briefing').click();
await page.waitForTimeout(150);
await page.locator('#start-mission').click();
await page.waitForFunction(() => document.querySelector('#hud')?.hidden === false);
await page.waitForTimeout(300);

let failures = 0;
function check(name, ok) { console.log(`${ok ? 'PASS' : 'FAIL'} ${name}`); if (!ok) failures++; }

// room_clear: stamp with room name appears at the given screen position.
await page.evaluate(() => window.BreachUI.receive(JSON.stringify({ type: 'fx', kind: 'room_clear', time: 1, room: 'r2', room_name: '02 / BREACH', screen: [800, 400] })));
await page.waitForTimeout(50);
check('room_clear stamp appears', await page.locator('#fx-layer .fx-stamp').count() > 0);
check('room_clear stamp shows room name', (await page.locator('#fx-layer .fx-stamp span').first().textContent() || '').includes('BREACH'));
await page.waitForTimeout(1700);
check('room_clear stamp auto-clears', await page.locator('#fx-layer .fx-stamp').count() === 0);

// room_clear without a screen position falls back to top-center.
await page.evaluate(() => window.BreachUI.receive(JSON.stringify({ type: 'fx', kind: 'room_clear', time: 2, room: 'r1', room_name: '01 / ENTRY' })));
await page.waitForTimeout(50);
check('room_clear without position uses top-center', await page.locator('#fx-layer .fx-stamp.top-center').count() > 0);
await page.waitForTimeout(1700);

// enemy_spotted: top banner + auto-clear.
await page.evaluate(() => window.BreachUI.receive(JSON.stringify({ type: 'fx', kind: 'enemy_spotted', time: 3 })));
await page.waitForTimeout(50);
check('enemy_spotted banner appears', await page.locator('#fx-layer .fx-banner-threat').count() > 0);
await page.waitForTimeout(2100);
check('enemy_spotted banner auto-clears', await page.locator('#fx-layer .fx-banner-threat').count() === 0);

// hit (friendly): red vignette pulse + matching unit card flashes/shakes.
const unitId = await page.evaluate(() => document.querySelector('.unit-card')?.dataset.unit);
await page.evaluate(id => window.BreachUI.receive(JSON.stringify({ type: 'fx', kind: 'hit', time: 4, react_at:4.05, friendly: true, target_id: id })), unitId);
await page.evaluate(()=>window.BreachUI.receive(JSON.stringify({type:'fx_clock',time:4.05,paused:false})));
await page.waitForTimeout(30);
check('hit(friendly) shows edge vignette', await page.locator('#fx-layer .fx-vignette').count() > 0);
check('hit(friendly) flashes the matching operator card', await page.locator(`.unit-card[data-unit="${unitId}"].hit-flash`).count() > 0);
await page.waitForTimeout(500);
check('hit vignette auto-clears', await page.locator('#fx-layer .fx-vignette').count() === 0);

// Enemy feedback stays at the confirmed screen point and clears promptly.
const tick = await page.evaluate(async () => {
  window.BreachUI.receive(JSON.stringify({type:'fx',kind:'hit',time:4.1,friendly:false,target_id:'enemy',screen:[600,350],protection:'blocked',react_at:4.15}));
  const before=document.querySelectorAll('.fx-hit-confirm').length;
  window.BreachUI.receive(JSON.stringify({type:'fx_clock',time:4.149,paused:false}));
  const early=document.querySelectorAll('.fx-hit-confirm').length;
  window.BreachUI.receive(JSON.stringify({type:'fx_clock',time:4.15,paused:false}));
  const marker=document.querySelector('.fx-hit-confirm');
  return {before,early,count:document.querySelectorAll('.fx-hit-confirm').length,left:marker?.style.left,steel:marker?.classList.contains('fx-blocked-confirm'),vignette:!!document.querySelector('.fx-vignette')};
});
check('enemy tick waits for tracer arrival',tick.before===0&&tick.early===0);
check('enemy hit creates a tiny steel tick without vignette', tick.count===1&&tick.left==='600px'&&tick.steel&&!tick.vignette);
await page.waitForTimeout(180);
check('enemy hit tick auto-clears within 120 ms', await page.locator('.fx-hit-confirm').count()===0);
await page.evaluate(() => {
  window.BreachUI.receive(JSON.stringify({type:'fx',kind:'neutralized',time:4.2,id:'enemy',event_seq:88,after_shot:true,react_at:4.25,screen:[600,350]}));
  window.BreachUI.receive(JSON.stringify({type:'fx_clock',time:4.25,paused:false}));
});
check('neutralized does not duplicate the world kill X in DOM',await page.locator('.fx-kill-confirm').count()===0);
await page.evaluate(() => {
  window.BreachUI.receive(JSON.stringify({type:'fx',kind:'hit',time:4.3,react_at:4.35,screen:[600,350]}));
  window.BreachUI.receive(JSON.stringify({type:'fx_reset'}));
  window.BreachUI.receive(JSON.stringify({type:'fx_clock',time:4.35,paused:false}));
});
check('seek reset cancels an unpresented tick',await page.locator('.fx-hit-confirm').count()===0);
await page.emulateMedia({reducedMotion:'reduce'});
const subtle=await page.evaluate(async () => {
  window.BreachUI.receive(JSON.stringify({type:'fx',kind:'hit',time:4.4,react_at:4.45,friendly:false,screen:[600,350]}));
  window.BreachUI.receive(JSON.stringify({type:'fx_clock',time:4.45,paused:false}));
  return getComputedStyle(document.querySelector('.fx-hit-confirm')).opacity;
});
check('OS reduced motion dims the stationary marker',Number(subtle)<=.35);
await page.waitForTimeout(180);
await page.emulateMedia({reducedMotion:'no-preference'});

// unit_down: incapacitated card style + banner.
await page.evaluate(id => window.BreachUI.receive(JSON.stringify({ type: 'fx', kind: 'unit_down', time: 5, react_at:5.05, after_shot:true, unit_id: id })), unitId);
check('shot unit_down waits for arrival',await page.locator('#fx-layer .fx-banner-down').count()===0);
await page.evaluate(()=>window.BreachUI.receive(JSON.stringify({type:'fx_clock',time:5.05,paused:false})));
await page.waitForTimeout(30);
check('unit_down banner appears', await page.locator('#fx-layer .fx-banner-down').count() > 0);
check('unit_down marks the operator card incapacitated', await page.locator(`.unit-card[data-unit="${unitId}"].fx-incap`).count() > 0);
await page.waitForTimeout(2300);
check('unit_down banner auto-clears', await page.locator('#fx-layer .fx-banner-down').count() === 0);

// mission_end: brief letterbox, non-blocking (input still reaches the canvas).
await page.evaluate(() => window.BreachUI.receive(JSON.stringify({ type: 'fx', kind: 'mission_end', time: 6, success: true })));
await page.waitForTimeout(50);
check('mission_end shows a letterbox', await page.locator('#fx-layer .fx-letterbox').count() > 0);
check('fx layer never blocks input (pointer-events:none)', await page.evaluate(() => getComputedStyle(document.querySelector('#fx-layer')).pointerEvents === 'none'));
await page.waitForTimeout(950);
check('mission_end letterbox auto-clears', await page.locator('#fx-layer .fx-letterbox').count() === 0);

// Result cleanup must work with mission_end both before and after its state message.
const terminal=await page.evaluate(async id=>{
  const receive=data=>window.BreachUI.receive(JSON.stringify(data));
  const current=structuredClone(window.fxTestState);
  receive({type:'fx',kind:'enemy_spotted',time:7});
  receive({type:'fx',kind:'hit',friendly:true,target_id:id,react_at:0,time:7});
  receive({type:'fx',kind:'hit',friendly:true,target_id:id,react_at:7.05,time:7});
  receive({type:'fx',kind:'mission_end',time:7});
  await new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)));
  receive({...current,type:'state',mode:'RESULT',result:{success:true,score:100,rank:'S'}});
  receive({type:'fx_clock',time:8,paused:false});
  const cleared=!document.querySelector('#fx-layer .fx-banner,#fx-layer .fx-vignette')&&!document.querySelector('.unit-card.hit-flash,.unit-card.fx-shake');
  const preserved=!!document.querySelector('#fx-layer .fx-letterbox');
  receive({type:'fx',kind:'enemy_spotted',time:8});
  const lateIgnored=!document.querySelector('#fx-layer .fx-banner');
  receive({...current,type:'state',mode:'MENU'});
  const menuClean=!document.querySelector('#fx-layer>*');
  receive({...current,type:'state',mode:'RESULT',result:{success:true,score:100}});
  receive({type:'fx',kind:'mission_end',time:8});
  return {cleared,preserved,lateIgnored,menuClean,after:!!document.querySelector('#fx-layer .fx-letterbox')};
},unitId);
check('RESULT clears stale banners, vignette, card flash and pending hit',terminal.cleared);
check('RESULT preserves an already-started mission_end letterbox',terminal.preserved);
check('late combat fx cannot restore a result banner',terminal.lateIgnored);
check('MENU clears all active transient fx',terminal.menuClean);
check('mission_end after RESULT still plays its letterbox',terminal.after);
await browser.close();
assert.equal(failures, 0, `${failures} fx check(s) failed`);
console.log('fx consumer check: all passed');
