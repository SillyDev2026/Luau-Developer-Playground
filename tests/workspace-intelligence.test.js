import test from 'node:test';
import assert from 'node:assert/strict';
import { Workspace } from '../src/v1-model.js';
import { CodeEditor } from '../src/v1-editor.js';
import { completionContext, staticCompletions } from '../src/intellisense.js';
import { moduleMemberCompletions, hoverAt } from '../src/symbol-hover.js';
import { signatureFor } from '../src/editor-intelligence.js';
import { CORE_API } from '../src/roblox-api.js';

const math='--!strict\nlocal Math = {}\nfunction Math.add(a: number, b: number): number\n  return a + b\nend\nfunction Math.mul(a: number, b: number): number\n  return a * b\nend\nreturn Math\n';
const localStore=()=>{const entries=new Map();return {getItem:key=>entries.get(key)||null,setItem:(key,value)=>entries.set(key,value),removeItem:key=>entries.delete(key)};};
const suggestions=(source,cursor,project)=>{
  const context=completionContext(source,cursor);
  return moduleMemberCompletions(source,cursor,context,project);
};

test('new script and test files get Luau type completions regardless of path or extension',()=>{
  const w=new Workspace({storage:localStore()});
  for(const path of ['scripts/NewScript.luau','scripts/Client.lua','modules/Values.luau','tests/Math.test.lua','nested/deeper/Handler.luau']){
    const code='--!strict\nlocal Math = {}\nfunction Math.add(a: num';
    w.create(path,code);
    assert.equal(w.project.active,path);
    const choices=staticCompletions(code,code.length,CORE_API)?.items||[];
    assert.ok(choices.some(x=>x.label==='number'),path);
    assert.ok(!choices.some(x=>x.label==='tonumber'),path);
    w.source('local ready = true\nend');
    assert.equal(completionContext(w.project.files[path],w.project.files[path].length),null,path);
  }
  w.dispose();
});

test('new scripts complete functions exported by newly created .luau modules',()=>{
  const w=new Workspace({storage:localStore()});
  w.create('modules/Math.luau',math);
  for(const path of ['scripts/Run.luau','scripts/Client.lua','tests/run.test.luau']){
    const source='local Operations = require("../modules/Math.luau")\nOperations.a';
    w.create(path,source);
    const options=suggestions(source,source.length,w.project);
    assert.deepEqual(options.map(x=>x.label),['add']);
    assert.equal(options[0].kind,'function');
    assert.match(options[0].detail,/add\(a: number, b: number\): number/);
    w.source(source.slice(0,-1)+'mul(2, 3)');
    const code=w.project.files[path],at=code.lastIndexOf('mul')+1;
    const hover=hoverAt(code,at,w.project,CORE_API);
    assert.equal(hover.signature,'mul(a: number, b: number): number');
    assert.equal(hover.origin,'modules/Math.luau');
    assert.equal(signatureFor(code,code.indexOf('2, 3')+1,CORE_API,w.project).signature,'mul(a: number, b: number): number');
  }
  w.dispose();
});

test('all workspace source paths use the active file as import resolution root',()=>{
  const w=new Workspace({storage:localStore()});
  w.create('src/deep/util/Math.lua',math);
  const source='local M = require("../util/Math.lua")\nM.m';
  w.create('src/deep/tests/test.spec.luau',source);
  assert.deepEqual(suggestions(source,source.length,w.project).map(x=>x.label),['mul']);
  w.rename('src/deep/tests/test.spec.luau','src/deep/tests/test.spec.lua');
  assert.equal(w.project.active,'src/deep/tests/test.spec.lua');
  assert.deepEqual(suggestions(source,source.length,w.project).map(x=>x.label),['mul']);
  w.dispose();
});

test('module exports exclude private helper functions in each imported script',()=>{
  const project={active:'main.luau',files:{
    'main.luau':'local M = require("./modules/M")\nM.',
    'modules/M.luau':'local function private(x: number): number\n return x\nend\nlocal M = {}\nfunction M.public(x: number): number\n return x\nend\nreturn M'
  }};
  const source=project.files['main.luau'];
  assert.deepEqual(suggestions(source,source.length,project).map(x=>x.label),['public']);
  assert.equal(hoverAt(source,source.lastIndexOf('M.')+1,project,CORE_API),null);
  assert.equal(suggestions('local M = require("./missing")\nM.',35,project).length,0);
});

test('table-returned functions in a .lua module are available for hover and autocomplete',()=>{
  const source='local F = require("./src/M.lua")\nF.div';
  const project={active:'tests/check.lua',files:{
    'tests/check.lua':source,
    'tests/src/M.lua':'return {\n div = function(a: number, b: number): number\n return a/b\n end,\n}\n'
  }};
  assert.deepEqual(suggestions(source,source.length,project).map(x=>x.label),['div']);
  project.files['tests/check.lua']='local F = require("./src/M.lua")\nF.d';
  assert.deepEqual(suggestions(project.files['tests/check.lua'],project.files['tests/check.lua'].length,project).map(x=>x.label),['div']);
  const call='local F = require("./src/M.lua")\nF.div(1, 2)';
  assert.equal(hoverAt(call,call.lastIndexOf('div')+1,{...project,files:{...project.files,'tests/check.lua':call}},CORE_API)?.signature,'div(a: number, b: number): number');
});

test('CodeEditor emits a filechange event when a different script loads',()=>{
  const originalRequest=globalThis.requestAnimationFrame,originalCancel=globalThis.cancelAnimationFrame;
  globalThis.requestAnimationFrame=()=>1;
  globalThis.cancelAnimationFrame=()=>{};
  try{
    const events={};
    const input={
      dataset:{},value:'',selectionStart:0,selectionEnd:0,scrollTop:0,scrollLeft:0,
      addEventListener:(type,fn)=>{(events[type]??=[]).push(fn);},
      dispatchEvent:event=>{for(const fn of events[event.type]||[])fn(event);return true;}
    };
    const highlight={parentElement:{scrollTop:0,scrollLeft:0}};
    const gutter={scrollTop:0,textContent:''};
    const editor=new CodeEditor({input,highlight,gutter,onChange:()=>{},onCursor:()=>{},onShortcut:()=>{}});
    const seen=[];
    input.addEventListener('luauforge:filechange',()=>seen.push({file:input.dataset.path,value:input.value}));
    editor.load('local a = 1','scripts/New.lua');
    editor.load(math,'modules/Math.luau');
    editor.load('local b = 2','tests/check.test.luau');
    assert.deepEqual(seen.map(x=>x.file),['scripts/New.lua','modules/Math.luau','tests/check.test.luau']);
    assert.equal(seen[1].value,math);
  }finally{
    globalThis.requestAnimationFrame=originalRequest;
    globalThis.cancelAnimationFrame=originalCancel;
  }
});

test('workbench mounts one editor-wide intelligence provider, not one per script',async()=>{
  const {readFile}=await import('node:fs/promises');
  const html=await readFile(new URL('../src/v1.js',import.meta.url),'utf8');
  const intelligent=await readFile(new URL('../src/auto-require.js',import.meta.url),'utf8');
  assert.match(html,/mountAutoRequire\(\{ editor: editor\.input, getProject: \(\) => workspace\.project/);
  assert.match(intelligent,/editor\.addEventListener\('luauforge:filechange'/);
  assert.match(intelligent,/editor\.addEventListener\('focus',\(\)=>update\(\)\)/);
  assert.match(intelligent,/moduleMemberCompletions\(editor\.value,editor\.selectionStart,context,project\)/);
});
