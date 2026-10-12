import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { CodeEditor } from '../src/v1-editor.js';

function editorHarness(source,position=source.length){
  const listeners={};
  const input={
    value:source,selectionStart:position,selectionEnd:position,scrollTop:0,scrollLeft:0,focused:false,dataset:{},
    addEventListener(name,fn){(listeners[name]??=[]).push(fn);},
    dispatchEvent(event){for(const fn of listeners[event.type]||[])fn(event);return true;},
    setRangeText(text,start,end){this.value=this.value.slice(0,start)+text+this.value.slice(end);this.selectionStart=this.selectionEnd=start+text.length;},
    setSelectionRange(start,end){this.selectionStart=start;this.selectionEnd=end;},
    focus(){this.focused=true;}
  };
  const gutter={textContent:'',scrollTop:0};
  const highlight={innerHTML:'',parentElement:{scrollTop:0,scrollLeft:0}};
  let changes=[],positions=[];
  const raf=globalThis.requestAnimationFrame,cancel=globalThis.cancelAnimationFrame;
  globalThis.requestAnimationFrame=callback=>{callback();return 1;};
  globalThis.cancelAnimationFrame=()=>{};
  const editor=new CodeEditor({input,highlight,gutter,onChange:value=>changes.push(value),onCursor:()=>positions.push(editor.position),onShortcut:()=>{}});
  editor.render();
  const cleanup=()=>{globalThis.requestAnimationFrame=raf;globalThis.cancelAnimationFrame=cancel;};
  return {input,gutter,highlight,editor,changes,positions,emit:(type,event)=>{for(const fn of listeners[type]||[])fn(event);},cleanup};
}
const sevenLines=['--!native','--!optimize 2','local NewModule =','require("../modules/NewModule.luau")','','','local data = NewModule.Data print(data)'].join('\n');

test('Android insertParagraph creates actual line 8 rather than visual wrap on line 7',()=>{
 const caret=sevenLines.indexOf(' print(data)')+1;
 const h=editorHarness(sevenLines,caret);
 try {
   assert.equal(h.gutter.textContent.split('\n').length,7);
   const event={inputType:'insertParagraph',isComposing:false,cancelable:true,defaultPrevented:false,preventDefault(){this.defaultPrevented=true;}};
   h.emit('beforeinput',event);
   assert.equal(event.defaultPrevented,true);
   assert.equal(h.editor.position.line,8);
   assert.equal(h.gutter.textContent.split('\n').at(-1),'8');
   assert.match(h.input.value,/\bData \nprint\(data\)/);
   assert.equal(h.changes.length,1);
   assert.deepEqual(h.positions.at(-1),{line:8,column:1});
   assert.ok(h.highlight.innerHTML.includes('print'));
 } finally {h.cleanup();}
});

test('Android insertLineBreak and mobile ↵ Enter insert and save numbered lines',()=>{
 const h=editorHarness('local a = 10');
 try {
   const event={inputType:'insertLineBreak',isComposing:false,cancelable:true,preventDefault(){}};
   h.emit('beforeinput',event);
   assert.equal(h.editor.position.line,2);
   h.input.setRangeText('print(a)',h.input.selectionStart,h.input.selectionEnd);
   h.input.dispatchEvent(new Event('input'));
   h.editor.insertNewline();
   assert.equal(h.editor.position.line,3);
   assert.equal(h.gutter.textContent,'1\n2\n3');
   assert.equal(h.input.value,'local a = 10\nprint(a)\n');
   assert.equal(h.changes.at(-1),h.input.value);
 } finally {h.cleanup();}
});

test('hardware Enter uses same newline logic with Luau indent, but IME composition remains native',()=>{
 const h=editorHarness('if ready then');
 try{
   const event={key:'Enter',ctrlKey:false,metaKey:false,altKey:false,isComposing:false,preventDefault(){this.prevented=true;}};
   h.emit('keydown',event);
   assert.equal(event.prevented,true);
   assert.equal(h.input.value,'if ready then\n    ');
   assert.deepEqual(h.editor.position,{line:2,column:5});
   assert.equal(h.gutter.textContent,'1\n2');
   const composing={inputType:'insertParagraph',isComposing:true,cancelable:true,preventDefault(){this.prevented=true;}};
   h.emit('beforeinput',composing);
   assert.equal(composing.prevented,undefined);
 }finally{h.cleanup();}
});

test('visual wraps do not invent source newlines or misleading line numbers',()=>{
 const h=editorHarness(sevenLines);
 try {
  assert.equal(h.editor.position.line,7);
  assert.equal(h.gutter.textContent.split('\n').length,7);
  assert.equal(h.input.value,sevenLines);
 }finally{h.cleanup();}
});

test('mobile toolbar exposes a dedicated Enter and wrap-label remains accessible',async()=>{
 const read=name=>readFile(new URL('../'+name,import.meta.url),'utf8');
 const [html,js,css]=await Promise.all(['index.html','src/v1.js','src/v1.css'].map(read));
 assert.match(html,/id="mobile-enter"[^>]*aria-label="Insert new numbered line"/);
 assert.match(html,/id="wrap-indicator"[^>]*title="Visual wrapping does not create a new line/);
 assert.match(js,/\$\('mobile-enter'\)\.addEventListener\('click', \(\) => editor\.insertNewline\(\)\)/);
 assert.match(js,/\$\('mobile-enter'\)\.addEventListener\('pointerdown', event => event\.preventDefault\(\)\)/);
 assert.match(js,/\$\('code-input'\)\.style\.whiteSpace = p\.wordWrap \? 'pre-wrap' : 'pre'/);
 assert.match(js,/\$\('wrap-indicator'\)\.classList\.toggle\('hidden', !p\.wordWrap\)/);
 assert.match(css,/#mobile-enter/);
});
