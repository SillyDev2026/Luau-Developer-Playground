import test from 'node:test';
import assert from 'node:assert/strict';
import { hoverAt, lookupSignature, sourceOffsetAtPoint, documentationBefore, moduleMemberCompletions } from '../src/symbol-hover.js';
import { signatureFor } from '../src/editor-intelligence.js';
import { CORE_API } from '../src/roblox-api.js';

const moduleCode='local Math = {}\nfunction Math.add(a: number, b: number): number\n  return a + b\nend\nreturn Math\n';

test('hovering Math.add reads named argument and return types from this file',()=>{
  const code=moduleCode+'\nlocal value = Math.add(1, 2)';
  const at=code.lastIndexOf('Math.add')+'Math.'.length+1;
  const hint=hoverAt(code,at,{active:'Math.luau',files:{'Math.luau':code}},CORE_API);
  assert.equal(hint.signature,'add(a: number, b: number): number');
  assert.equal(hint.origin,'Math.luau');
  assert.equal(hoverAt(code,code.indexOf('return a + b')+'return '.length,{active:'Math.luau',files:{}},CORE_API),null);
});

test('hovering a require alias resolves the exported function in another workspace file',()=>{
  const source='local Operations = require("./lib/Math.luau")\nlocal answer = Operations.add(3, 5)\n';
  const project={active:'main.luau',files:{'main.luau':source,'lib/Math.luau':moduleCode}};
  const at=source.lastIndexOf('.add')+2;
  const hint=hoverAt(source,at,project,CORE_API);
  assert.equal(hint.signature,'add(a: number, b: number): number');
  assert.equal(hint.origin,'lib/Math.luau');
  const call=source.indexOf('(',source.indexOf('Operations.add('))+1;
  assert.equal(signatureFor(source,call,CORE_API,project).signature,'add(a: number, b: number): number');
});

test('anonymous functions exported as table members show their signature',()=>{
  const lib='return { add = function(a: number, b: number): number\n return a+b\n end }\n';
  const source='local Math = require("./math")\nprint(Math.add(1,2))';
  const project={active:'main.luau',files:{'main.luau':source,'math.luau':lib}};
  assert.equal(lookupSignature('Math.add',source,source.length,project,CORE_API).signature,'add(a: number, b: number): number');
});

test('hover uses Roblox standard-library and typed-instance metadata',()=>{
  const code='local part = Instance.new("Part")\nmath.sqrt(25)\npart:IsA("Part")';
  const project={active:'main.luau',files:{'main.luau':code}};
  assert.match(hoverAt(code,code.indexOf('sqrt')+2,project,CORE_API).signature,/sqrt\(x: number\): number/);
  assert.match(hoverAt(code,code.indexOf('IsA')+1,project,CORE_API).signature,/IsA\(className: string\): boolean/);
});

test('bundled module methods show documented API signatures',()=>{
  const source='local FastME = require("@FastNum")\nlocal c = FastME.add(a,b)';
  const project={active:'main.luau',files:{'main.luau':source}};
  const hint=hoverAt(source,source.indexOf('.add')+2,project,CORE_API);
  assert.equal(hint.signature,'add(a, b)');
  assert.match(hint.origin,/bundled API/);
});

test('hover ignores functions in comments and strings and refuses unresolved methods',()=>{
  const source='-- function Math.add(a: number, b: number): number\nlocal text = "function Math.add(a: number)"\nlocal value = Math.add(1,2)';
  const project={active:'main.luau',files:{'main.luau':source}};
  assert.equal(hoverAt(source,source.indexOf('function Math.add')+'function Math.'.length+1,project,CORE_API),null);
  assert.equal(hoverAt(source,source.lastIndexOf('.add')+2,project,CORE_API),null);
});

test('hover pointer mapping respects scroll offsets, line height and tabs',()=>{
  const metrics={paddingLeft:0,paddingTop:0,charWidth:10,lineHeight:20,scrollLeft:0,scrollTop:0,tabSize:4};
  const text='ab\tMath.add(1)\nreturn Math';
  assert.equal(sourceOffsetAtPoint(text,{x:43,y:10},metrics),3);
  assert.equal(sourceOffsetAtPoint(text,{x:23,y:10},metrics),2);
  assert.equal(sourceOffsetAtPoint(text,{x:25,y:30},metrics),text.indexOf('return')+2);
  assert.equal(sourceOffsetAtPoint(text,{x:-5,y:10},metrics),null);
  assert.equal(sourceOffsetAtPoint(text,{x:100,y:200},metrics),null);
  assert.equal(sourceOffsetAtPoint(text,{x:3,y:10},{...metrics,scrollLeft:40}),3);
});

test('hover UI is present without changing or selecting textarea content',async()=>{
  const {readFile}=await import('node:fs/promises');
  const ui=await readFile(new URL('../src/auto-require.js',import.meta.url),'utf8');
  const css=await readFile(new URL('../src/auto-require.css',import.meta.url),'utf8');
  assert.match(ui,/pointermove/);
  assert.match(ui,/role','tooltip'/);
  assert.match(css,/\.symbol-hover\{[^}]*pointer-events:none/);
});


test('Luau -- comment on a function appears in same-file hover, imported hover and autocomplete',()=>{
  const module='local Math = {}\n-- add 2 numbers\nfunction Math.add(a: number, b: number): number\n return a + b\nend\nreturn Math';
  const source='local M = require("./Math")\nlocal total = M.add(1, 2)\nM.a';
  const project={active:'main.luau',files:{'main.luau':source,'Math.luau':module}};
  const same=hoverAt(module,module.indexOf('Math.add')+6,{active:'Math.luau',files:{'Math.luau':module}},CORE_API);
  assert.equal(same.signature,'add(a: number, b: number): number');
  assert.equal(same.documentation,'add 2 numbers');
  const imported=hoverAt(source,source.indexOf('M.add')+3,project,CORE_API);
  assert.equal(imported.documentation,'add 2 numbers');
  assert.equal(imported.origin,'Math.luau');
  const context={mode:'member',base:'M',query:'a',separator:'.'};
  const matches=moduleMemberCompletions(source,source.length,context,project);
  assert.deepEqual(matches.map(x=>x.label),['add']);
  assert.equal(matches[0].documentation,'add 2 numbers');
  assert.match(matches[0].detail,/add\(a: number, b: number\): number/);
  const signature=signatureFor(source,source.indexOf('1, 2')+1,CORE_API,project);
  assert.equal(signature.documentation,'add 2 numbers');
  assert.equal(signature.activeParameter,0);
});

test('multi-line -- and --- comments form one function documentation block',()=>{
  const source='local Math = {}\n--- Adds values together\n-- Handles two numeric values\n-- Returns their total\nfunction Math.add(a: number, b: number): number\n return a+b\nend\nreturn Math\nMath.add(1, 2)';
  const result=hoverAt(source,source.lastIndexOf('Math.add')+6,{active:'Math.luau',files:{'Math.luau':source}},CORE_API);
  assert.equal(result.documentation,'Adds values together\nHandles two numeric values\nReturns their total');
  assert.equal(signatureFor(source,source.lastIndexOf('Math.add(')+10,CORE_API,{active:'Math.luau',files:{'Math.luau':source}}).documentation,result.documentation);
});

test('only adjacent function comments are shown; separated and in-body comments are excluded',()=>{
  const cases=[
    ['-- unrelated\n\nfunction Math.add(a: number, b: number): number\nend',''],
    ['--!strict\nfunction Math.add(a: number, b: number): number\nend',''],
    ['local ignored = "-- not docs"\nfunction Math.add(a: number, b: number): number\nend',''],
    ['-- for other function\nlocal a = 1\nfunction Math.add(a: number, b: number): number\nend',''],
    ['function Math.add(a: number, b: number): number\n-- not documentation\nend','']
  ];
  for(const [source,documentation] of cases){
    const result=lookupSignature('Math.add',source,source.length,{active:'Math.luau'},CORE_API);
    assert.equal(result?.documentation,documentation,source);
  }
});

test('anonymous function assigned as table field retains adjacent Luau docs',()=>{
  const module='local Math = {}\n-- Multiply two values\nMath.mul = function(a: number, b: number): number\n return a*b\nend\nreturn Math';
  const project={active:'main.luau',files:{'main.luau':'local M = require("./Math")\nM.mul(2, 3)','Math.luau':module}};
  assert.equal(lookupSignature('M.mul',project.files['main.luau'],project.files['main.luau'].length,project,CORE_API).documentation,'Multiply two values');
});

test('Luau long block documentation is supported immediately before a function',()=>{
  const source='--[[\n  Adds two numbers\n  Returns a numeric result\n]]\nfunction Math.add(a: number,b: number): number\nend';
  assert.equal(documentationBefore(source,source.indexOf('function Math.add')),'Adds two numbers\n  Returns a numeric result');
});

test('hover and autocomplete render function descriptions as plain text',async()=>{
  const {readFile}=await import('node:fs/promises');
  const ui=await readFile(new URL('../src/auto-require.js',import.meta.url),'utf8');
  const css=await readFile(new URL('../src/auto-require.css',import.meta.url),'utf8');
  assert.match(ui,/documentation\.textContent=result\.documentation/);
  assert.match(ui,/docs\.textContent=item\.documentation/);
  assert.match(ui,/doc\.textContent=hint\.documentation/);
  assert.match(css,/\.symbol-hover-doc/);
  assert.match(css,/\.completion-doc/);
  assert.match(css,/\.signature-doc/);
});
