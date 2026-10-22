import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const source=await readFile(new URL('../web/map-editor.js',import.meta.url),'utf8');
const {bindMapEditor,createEditorMission}=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));

// Exercise the event contract with a controllable animation frame, without GPU timing.
let frameId=0,draws=0;
const frames=new Map();
globalThis.requestAnimationFrame=callback=>{const id=++frameId;frames.set(id,callback);return id;};
globalThis.cancelAnimationFrame=id=>frames.delete(id);
const paint=()=>{const callbacks=[...frames.values()];frames.clear();for(const callback of callbacks)callback();};
class Node {
  constructor(selector){this.selector=selector;this.listeners=new Map();this.dataset={};this.writes=0;this.htmlWrites=0;this.disabled=false;}
  addEventListener(type,handler){const handlers=this.listeners.get(type)||[];handlers.push(handler);this.listeners.set(type,handlers);}
  removeEventListener(type,handler){this.listeners.set(type,(this.listeners.get(type)||[]).filter(value=>value!==handler));}
  emit(type,event={}){for(const handler of this.listeners.get(type)||[])handler({target:this,preventDefault(){},...event});}
  set value(value){this.storedValue=value;this.writes++;}get value(){return this.storedValue;}
  set innerHTML(value){this.html=value;this.htmlWrites++;}get innerHTML(){return this.html;}
  hasAttribute(name){return this.selector===`[${name}]`;}
  closest(){return this;}
  focus(){}setPointerCapture(){}
}
const selectors=['canvas','json','properties','errors','title','seed','environment','lighting','play','export'];
const nodes=new Map(selectors.map(name=>{const selector=`[data-editor-${name}]`;return [selector,new Node(selector)];}));
const canvas=nodes.get('[data-editor-canvas]');canvas.width=640;canvas.height=360;
canvas.getBoundingClientRect=()=>({left:0,top:0,width:640,height:360});
canvas.getContext=()=>new Proxy({clearRect(){draws++;}},{get:(target,name)=>target[name]||(()=>{})});
const root=new Node('root');root.querySelector=selector=>{assert(nodes.has(selector),selector);return nodes.get(selector);};root.contains=node=>[...nodes.values()].includes(node);
const textarea=nodes.get('[data-editor-json]'),errors=nodes.get('[data-editor-errors]'),play=nodes.get('[data-editor-play]'),exports=nodes.get('[data-editor-export]');
const changes=[],plays=[],toasts=[];
const editor=bindMapEditor(root,{mission:createEditorMission(),onChange:map=>changes.push(map),onPlay:map=>plays.push(map),toast:(...message)=>toasts.push(message)});
const pointer=(type,x,z,pointerId=1)=>{const scale=320/12;canvas.emit(type,{button:0,pointerId,clientX:(640-16*scale)/2+x*scale,clientY:20+z*scale});};

pointer('pointerdown',3,9);
assert.equal(play.disabled,true);assert.equal(exports.disabled,true);
const start={draws,json:textarea.writes,status:errors.htmlWrites};
pointer('pointermove',3.01,9);
assert.equal(frames.size,0,'same snapped coordinate should do no drawing');
pointer('pointermove',3.25,9);pointer('pointermove',3.5,9);
assert.equal(frames.size,1,'a frame uses only the latest drag position');
assert.equal(draws,start.draws);assert.equal(textarea.writes,start.json);assert.equal(errors.htmlWrites,start.status);
root.emit('click',{target:play});assert.equal(plays.length,0,'synthetic play during drag must also be blocked');
paint();assert.equal(draws,start.draws+1);assert.equal(editor.getMission().units[0].x,3.5);
pointer('pointerup',3.5,9,2);assert.equal(play.disabled,true,'another pointer cannot commit the drag');
pointer('pointerup',3.5,9);
assert.equal(play.disabled,false);assert.equal(exports.disabled,false);assert.equal(JSON.parse(textarea.value).units[0].x,3.5);assert.equal(changes.length,1);
root.emit('click',{target:play});assert.equal(plays[0].units[0].x,3.5);

pointer('pointerdown',3.5,9);pointer('pointermove',20,9);pointer('pointerup',20,9);
assert.equal(play.disabled,true);assert.equal(exports.disabled,true);assert.match(errors.innerHTML,/지도 밖/);assert.equal(frames.size,0,'commit cancels its pending preview draw');
root.emit('click',{target:play});assert.equal(plays.length,1);assert.equal(toasts.at(-1)[1],'error');
editor.setMission(createEditorMission());pointer('pointerdown',3,9);pointer('pointermove',4,9);pointer('pointercancel',4,9,2);
assert.equal(frames.size,1,'another pointer cannot cancel the drag');
pointer('pointercancel',4,9);assert.equal(editor.getMission().units[0].x,3);assert.equal(play.disabled,false);assert.equal(frames.size,0);
pointer('pointerdown',3,9);pointer('pointermove',4,9);canvas.emit('keydown',{key:'Escape'});
assert.equal(editor.getMission().units[0].x,3);assert.equal(frames.size,0);assert.equal(play.disabled,false);
pointer('pointerdown',3,9);pointer('pointermove',4,9);editor.destroy();assert.equal(frames.size,0,'destroy must cancel a pending canvas draw');
console.log('Map editor drag: batching, commit validation, cancellation and destroy passed');
