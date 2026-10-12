import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { STUDIO_LIBRARIES } from '../src/studio-libraries.js';
import { targets, suggestions, complete, boundStudioVariable, studioRequireExpression } from '../src/auto-require.js';
import { githubModuleTargets, saveGithubPin, readGithubPins } from '../src/github-modules.js';
import { indexPublicModule, validateModuleIndex } from '../src/module-index.js';
import { moduleMemberCompletions, hoverAt, lookupSignature } from '../src/symbol-hover.js';
import { completionContext } from '../src/intellisense.js';
import { CORE_API } from '../src/roblox-api.js';

const files={'main.luau':'','modules/Local.luau':'return {}'};
const db=()=>{const data=new Map();return {getItem:key=>data.get(key)||null,setItem:(key,value)=>data.set(key,value)};};
const sha='a'.repeat(40);
const studio=lib=>STUDIO_LIBRARIES.find(x=>x.id===lib);
test('Auto Require discovers all seven curated Studio modules plus bundled and public helpers',()=>{
  const results=targets(files,'main.luau');
  for(const lib of STUDIO_LIBRARIES){
    const entry=results.find(x=>x.kind==='studio'&&x.id===lib.id);
    assert.ok(entry,'Missing '+lib.id);
    assert.match(entry.detail,/Studio only/);
    assert.ok(entry.dependencies.length>0);
  }
  assert.ok(results.some(x=>x.id==='FastNum'&&x.kind==='builtin'));
  for(const name of ['SignalLite','TableKit'])assert.ok(results.some(x=>x.label===name&&x.kind==='github'));
});
test('Studio import inserts an actual game:GetService require instead of an invalid @Studio specifier',()=>{
  const cases=[
    ['NexusDataStore','local NexusDataStore = require(game:GetService("ServerScriptService").NexusDataStore)'],
    ['NetStream','local NetStream = require(game:GetService("ReplicatedStorage").NetworkHandler.NetStream)'],
    ['ZonePlusV2','local ZonePlusNext = require(game:GetService("ReplicatedStorage").ZonePlusNext)'],
    ['BufferUtil','local BufferUtil = require(game:GetService("ReplicatedStorage").BufferUtil)']
  ];
  for(const [id,want] of cases){
    const lib=studio(id);
    const source='/'+lib.label;
    const option=suggestions(source,source.length,files,'main.luau').items.find(x=>x.id===id&&x.kind==='studio');
    assert.ok(option,'Expected option '+id);
    const result=complete(source,source.length,option,files,'main.luau');
    assert.equal(result.source,want);
    assert.equal(result.studioOnly,true);
    assert.ok(result.dependencies.length>0);
    assert.equal(studioRequireExpression(lib),want.slice(want.indexOf('require(')+8,-1));
    const already=want+'\n/'+lib.label;
    const previous=suggestions(already,already.length,files,'main.luau').items.find(x=>x.id===id&&x.kind==='studio');
    const reused=complete(already,already.length,previous,files,'main.luau');
    assert.equal(reused.source,want+'\n'+option.variable);
    assert.equal(reused.created,false);
  }
});
test('Studio aliases work with indented requires, ignore comments and cannot be executed as WASM imports',()=>{
  const lib=studio('BufferUtil'),expression=studioRequireExpression(lib);
  const code='  local Buf = require( game : GetService ( \'ReplicatedStorage\' ) . BufferUtil )\n';
  assert.equal(boundStudioVariable(code,expression),'Buf');
  assert.equal(boundStudioVariable('-- local Buf = require('+expression+')',expression),null);
  assert.equal(boundStudioVariable('local txt = "require('+expression+')"',expression),null);
  const imported='local BufferUtil = require('+expression+')\nBufferUtil.';
  const items=moduleMemberCompletions(imported,imported.length,completionContext(imported,imported.length),{active:'main.luau',files:{'main.luau':imported}});
  assert.ok(items.some(x=>x.label==='writeu8'));
  assert.match(items[0].documentation,/Studio only/);
  const code2='local BufferUtil = require('+expression+')\nBufferUtil.writeu8()';
  const result=hoverAt(code2,code2.indexOf('writeu8')+2,{active:'main.luau',files:{'main.luau':code2}},CORE_API);
  assert.match(result.origin,/Studio/);
});
test('source-reviewed GitHub modules retain only a compact API index and ignore private helpers',()=>{
  const source='--!strict\nlocal Lib = {}\n-- add two numbers\nfunction Lib.add(a: number, b: number): number\nreturn a+b\nend\nfunction Lib.mul(a: number, b: number): number\nreturn a*b\nend\nlocal function private(a) return a end\nreturn Lib';
  const api=indexPublicModule(source);
  assert.deepEqual(api.map(x=>x.name),['add','mul']);
  assert.equal(api[0].signature,'add(a: number, b: number): number');
  assert.equal(api[0].documentation,'add two numbers');
  const storage=db();
  saveGithubPin({specifier:'@Author/MathRepo/Math.luau',sha,size:source.length,source},storage);
  const [pin]=readGithubPins(storage);
  assert.equal(pin.api.length,2);
  assert.ok(!storage.getItem('luauforge:github-pins:v1').includes('local Lib'));
  const typed='local Operations = require("@Author/MathRepo/Math.luau")\nOperations.a';
  const context=completionContext(typed,typed.length);
  // A browser has localStorage; the API can also be indexed with the explicit
  // snapshots when a source has been previously reviewed and pinned.
  assert.deepEqual(validateModuleIndex(pin.api).map(x=>x.name),['add','mul']);
  assert.equal(context.mode,'member');
});
test('source index ignores commented-out/private APIs and rejects malformed persisted signatures',()=>{
  const source='local Math = {}\n-- function Math.fake(x) end\nlocal function hidden(x) end\nfunction Math.ok(x: number): number\n return x\nend\nreturn Math';
  assert.deepEqual(indexPublicModule(source).map(x=>x.name),['ok']);
  assert.deepEqual(validateModuleIndex([{name:'x',signature:'x()',documentation:''},{name:'bad!',signature:'bad!()',documentation:''},{name:'f',signature:'wrong()',documentation:''}]).map(x=>x.name),['x']);
  assert.deepEqual(indexPublicModule('local Math = {}\nfunction Math.foo() end'),[]);
});
test('built-in public examples offer real method suggestions and hover signatures',()=>{
  const spec='@SillyDev2026/Luau-Developer-Playground/community/TableKit.luau';
  const code='local TableKit = require("'+spec+'")\nTableKit.m';
  const project={active:'main.luau',files:{'main.luau':code}};
  const context=completionContext(code,code.length);
  const list=moduleMemberCompletions(code,code.length,context,project);
  assert.deepEqual(list.map(x=>x.label),['merge']);
  assert.match(list[0].documentation,/Merge two tables/);
  const final='local TableKit = require("'+spec+'")\nTableKit.merge({}, {})';
  const info=lookupSignature('TableKit.merge',final,final.length,{...project,files:{'main.luau':final}},CORE_API);
  assert.match(info.signature,/merge\(left:/);
  assert.match(info.origin,/public example/);
  assert.equal(githubModuleTargets(db()).filter(x=>x.local).length,5);
});
test('public starter module sources and registry are published in the same repository',async()=>{
  const [signal,table,registry]=await Promise.all(['SignalLite.luau','TableKit.luau','registry.json'].map(name=>readFile(new URL('../public/community/'+name,import.meta.url),'utf8')));
  assert.match(signal,/function SignalLite\.new\(/);
  assert.match(signal,/function signal:Connect\(/);
  assert.match(table,/function TableKit\.merge\(/);
  const json=JSON.parse(registry);
  for(const name of ['SignalLite','TableKit'])assert.ok(json.modules.some(x=>x.name===name&&x.environment==='wasm'));
});
