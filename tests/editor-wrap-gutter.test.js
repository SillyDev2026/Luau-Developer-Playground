import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {sourceLines,gutterHeights,isWrappingInput} from '../src/editor-line-layout.js';
import {CodeEditor} from '../src/v1-editor.js';

test('logical source lines remain numbered 1 to 7 even when a long line wraps twice',()=>{
 const source=['--!native','--!optimize 2','local NewModule =','require("../modules/NewModule.luau")','','local data = NewModule.Data','print(data)'].join('\n');
 const lines=sourceLines(source);
 assert.equal(lines.length,7);
 const heights=gutterHeights(lines,(_,i)=>i===3?72:24,24);
 assert.deepEqual(heights,[24,24,24,72,24,24,24]);
 assert.equal(heights.slice(0,6).reduce((a,b)=>a+b,0),192);
 assert.equal(heights.slice(0,7).reduce((a,b)=>a+b,0),216);
 assert.deepEqual(sourceLines('foo\n'),['foo','']);
 assert.deepEqual(gutterHeights(['','x'],()=>0,24),[24,24]);
 assert.equal(isWrappingInput({wrap:'soft',style:{whiteSpace:'pre-wrap'}}),true);
 assert.equal(isWrappingInput({wrap:'off',style:{whiteSpace:'pre'}}),false);
});

function domHarness(source,{width=200,charsPerRow=22}={}){
 const listeners={};
 let caret=source.length;
 function el(tag='div'){
   const node={tagName:tag,textContent:'',children:[],style:{},parentElement:null,
     append(child){this.children.push(child);child.parentElement=this;},
     replaceChildren(...children){
       this.children=[];
       for(const child of children){if(child?.isFragment){for(const inner of child.children)this.append(inner);}else this.append(child);}
     },
     getBoundingClientRect(){
       const value=this.textContent||'\u200b';
       const max=Math.max(1,Math.floor((input.clientWidth-20)/charsPerRow));
       const lines=Math.max(1,Math.ceil(value.length/max));
       return {height:lines*24};
     }
   };return node;
 }
 const doc={createElement:tag=>el(tag),createDocumentFragment:()=>({...el('fragment'),isFragment:true})};
 const stack=el(),highlightScroll=el(),highlight=el(),gutter=el();
 highlight.parentElement=highlightScroll;
 const input={value:source,wrap:'soft',style:{whiteSpace:'pre-wrap'},clientWidth:width,ownerDocument:doc,
   parentElement:stack,selectionStart:caret,selectionEnd:caret,scrollTop:0,scrollLeft:0,dataset:{},
   addEventListener:(k,cb)=>{(listeners[k]??=[]).push(cb);},
   dispatchEvent(event){for(const callback of listeners[event.type]||[])callback(event);return true;},
   focus(){},setRangeText(text,start,end){this.value=this.value.slice(0,start)+text+this.value.slice(end);this.selectionStart=this.selectionEnd=start+text.length;},
   setSelectionRange(start,end){this.selectionStart=start;this.selectionEnd=end;}
 };
 let cursorUpdates=0;
 const oldRaf=globalThis.requestAnimationFrame,oldCancel=globalThis.cancelAnimationFrame,oldComputed=globalThis.getComputedStyle;
 globalThis.requestAnimationFrame=fn=>{fn();return 1;};globalThis.cancelAnimationFrame=()=>{};
 globalThis.getComputedStyle=()=>({font:'16px monospace',lineHeight:'24px',letterSpacing:'0px',paddingLeft:'10px',paddingRight:'10px',tabSize:'4',whiteSpace:'pre-wrap'});
 const editor=new CodeEditor({input,highlight,gutter,onChange:()=>{},onCursor:()=>cursorUpdates++,onShortcut:()=>{}});
 const cleanup=()=>{globalThis.requestAnimationFrame=oldRaf;globalThis.cancelAnimationFrame=oldCancel;globalThis.getComputedStyle=oldComputed;};
 return {input,gutter,editor,cleanup};
}

test('editor displays line 7 at correct vertical offset after wrapped line 4',()=>{
 const source=['--!native','--!optimize 2','local NewModule =','require("../modules/NewModule.luau")','','local data = NewModule.Data','print(data)'].join('\n');
 const h=domHarness(source,{width:170,charsPerRow:10});
 try{
   h.editor.render();
   assert.equal(h.gutter.children.length,7);
   const heights=h.gutter.children.map(x=>Number.parseFloat(x.style.height));
   assert.ok(heights[3]>heights[0],'wrapped 4th source line reserves extra vertical height');
   assert.equal(h.gutter.children[6].textContent,'7');
   assert.equal(h.gutter.children.map(x=>x.textContent).join(','),'1,2,3,4,5,6,7');
   h.input.clientWidth=75;
   h.editor.syncLineNumbers();
   const narrower=h.gutter.children.map(x=>Number.parseFloat(x.style.height));
   assert.ok(narrower[3]>heights[3],'narrower phone width reflows gutter line heights');
   assert.equal(h.input.value,source);
   assert.deepEqual(h.editor.position,{line:7,column:12});
 }finally{h.cleanup();}
});

test('switching Wrap off returns gutter to exact logical 1..7 text layout',()=>{
 const source='a\nb\nc\nd\ne\nf\ng';
 const h=domHarness(source);
 try{
   h.editor.render();
   assert.equal(h.gutter.children.length,7);
   h.input.wrap='off';h.input.style.whiteSpace='pre';
   h.editor.syncLineNumbers();
   assert.equal(h.gutter.textContent,'1\n2\n3\n4\n5\n6\n7');
   assert.equal(h.input.value,source);
 }finally{h.cleanup();}
});

test('layout remains synchronized on saved-wrap restore and width change',async()=>{
 const read=path=>readFile(new URL('../'+path,import.meta.url),'utf8');
 const [js,css,editor]=await Promise.all(['src/v1.js','src/v1.css','src/v1-editor.js'].map(read));
 assert.match(js,/editor\.render\(\);\s*metrics\(\); renderFiles/);
 assert.match(js,/\$\('code-input'\)\.style\.overflowWrap = p\.wordWrap \? 'anywhere' : 'normal'/);
 assert.match(css,/\.editor-wrap-mirror\{position:absolute/);
 assert.match(css,/\.line-gutter \.gutter-number-row\{display:block/);
 assert.match(editor,/ResizeObserver/);
 assert.match(editor,/mirror\.children\[i\]\.getBoundingClientRect\(\)\.height/);
});
