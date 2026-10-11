import test from 'node:test';
import assert from 'node:assert/strict';
import { completionContext, staticCompletions, applyCompletion } from '../src/intellisense.js';
import { typeAliases, exportedTypeNames, exportedTypeMembers, workspaceTypeSuggestions } from '../src/module-types.js';
import { CORE_API } from '../src/roblox-api.js';

const moduleSource=[
  '--!strict',
  'local data = {',
  '  Coins = 0,',
  '  Rebirths = 0,',
  '  Profile = { Level = 1, Title = "Rookie" },',
  '  Enabled = true,',
  '}',
  'type Private = { Secret: number }',
  'export type Data = typeof(data)',
  'export type Public = { Coins: number, Name: string?, Meta: { Rank: number }, Save: (id: number) -> boolean }',
  'export type Shared = Private',
  'local Module = {}',
  'function Module.run() end',
  'return Module'
].join('\n');
const makeProject=(active,source)=>({active,files:{[active]:source,'modules/PlayersData.luau':moduleSource}});
const suggestions=(source,project)=>{
  const context=completionContext(source,source.length);
  return {context,result:workspaceTypeSuggestions(source,source.length,context,project)};
};

test('export type declarations are distinguishable from private aliases and comments',()=>{
  const aliases=typeAliases(moduleSource);
  assert.equal(aliases.get('Private').exported,false);
  assert.equal(aliases.get('Data').expression,'typeof(data)');
  assert.deepEqual(exportedTypeNames(moduleSource),['Data','Public','Shared']);
  assert.deepEqual(exportedTypeNames('-- export type Fake = {}'+'\nlocal source = "export type No = {}"'),[]);
  assert.deepEqual([...exportedTypeMembers(moduleSource,'Public').keys()],['Coins','Name','Meta','Save']);
  assert.equal(exportedTypeMembers(moduleSource,'Private'),null);
  assert.deepEqual([...exportedTypeMembers(moduleSource,'Shared').keys()],['Secret']);
});

test('Module. in type annotations suggests ONLY export type names, never module functions or private types',()=>{
  for(const source of [
    'local Module = require("../modules/PlayersData.luau")\nlocal data: Module.',
    'local Module = require("../modules/PlayersData.luau")\nlocal data: Module.D',
    'local Module = require("../modules/PlayersData.luau")\ntype Current = Module.',
    'local Module = require("../modules/PlayersData.luau")\nfunction use(data: Module.'
  ]){
    const project=makeProject('scripts/Client.lua',source);
    const {context,result}=suggestions(source,project);
    assert.equal(context.mode,'type-member',source);
    assert.equal(result.authoritative,true);
    assert.ok(result.items.every(x=>['Data','Public','Shared'].includes(x.label)),source);
    assert.ok(!result.items.some(x=>['Private','run','tonumber'].includes(x.label)),source);
  }
  const source='local Module = require("../modules/PlayersData.luau")\nlocal data: Module.D';
  const project=makeProject('scripts/Client.lua',source);
  const {context,result}=suggestions(source,project);
  assert.deepEqual(result.items.map(x=>x.label),['Data']);
  const applied=applyCompletion(source,context,result.items[0]);
  assert.equal(applied.source,'local Module = require("../modules/PlayersData.luau")\nlocal data: Module.Data');
  assert.equal(applied.cursor,applied.source.length);
});

test('annotated data: Module.Data suggests only fields inferred from module typeof(data)',()=>{
  const source='local Module = require("../modules/PlayersData.luau")\nlocal data: Module.Data = PlayersData\ndata.';
  const project=makeProject('scripts/Client.lua',source);
  const {context,result}=suggestions(source,project);
  assert.equal(context.mode,'member');
  assert.equal(result.authoritative,true);
  assert.deepEqual(result.items.map(x=>x.label),['Coins','Enabled','Profile','Rebirths']);
  assert.ok(!result.items.some(x=>['Secret','run','print','tonumber'].includes(x.label)));
  assert.equal(result.items.find(x=>x.label==='Coins').detail,'Coins: number');
  assert.equal(result.items.find(x=>x.label==='Enabled').detail,'Enabled: boolean');
});

test('nested inferred records keep their public nested members without leaking root keys',()=>{
  const source='local Module = require("../modules/PlayersData.luau")\nlocal data: Module.Data\ndata.Profile.';
  const project=makeProject('scripts/Client.lua',source);
  const {result}=suggestions(source,project);
  assert.deepEqual(result.items.map(x=>x.label),['Level','Title']);
  assert.equal(result.items.find(x=>x.label==='Title').detail,'Title: string');
});

test('explicit export record types and function-valued members are respected',()=>{
  const source='local Module = require("../modules/PlayersData.luau")\nlocal data: Module.Public = {}\ndata.';
  const project=makeProject('scripts/Client.lua',source);
  const {result}=suggestions(source,project);
  assert.deepEqual(result.items.map(x=>x.label),['Coins','Meta','Name','Save']);
  assert.equal(result.items.find(x=>x.label==='Name').detail,'Name?: string');
  assert.equal(result.items.find(x=>x.label==='Save').kind,'function');
  const nested=source+'Meta.';
  const context=completionContext(nested,nested.length);
  assert.equal(context.mode,'member');
  assert.deepEqual(workspaceTypeSuggestions(nested,nested.length,context,project).items.map(x=>x.label),[]);
  const nestedCode='local Module = require("../modules/PlayersData.luau")\nlocal data: Module.Public\ndata.Meta.';
  assert.deepEqual(suggestions(nestedCode,makeProject('scripts/Client.lua',nestedCode)).result.items.map(x=>x.label),['Rank']);
});

test('private aliases are unavailable across modules even when annotated explicitly',()=>{
  const source='local Module = require("../modules/PlayersData.luau")\nlocal data: Module.Private = something\ndata.';
  const project=makeProject('scripts/Client.lua',source);
  const {result}=suggestions(source,project);
  assert.equal(result.authoritative,true);
  assert.deepEqual(result.items,[]);
  const partial='local Module = require("../modules/PlayersData.luau")\nlocal data: Module.Pri';
  assert.deepEqual(suggestions(partial,makeProject('scripts/Client.lua',partial)).result.items,[]);
});

test('same-file type aliases remain local and can shape local variable completions',()=>{
  const source='type Local = { Age: number, Name: string }\nlocal person: Local = {}\nperson.';
  const project={active:'main.luau',files:{'main.luau':source}};
  const {result}=suggestions(source,project);
  assert.deepEqual(result.items.map(x=>x.label),['Age','Name']);
  assert.equal(result.items.find(x=>x.label==='Age').detail,'Age: number');
});

test('source-based Luau type completion supports new .lua and .luau files in nested folders',()=>{
  for(const active of ['scripts/Run.luau','scripts/Run.lua','tests/Run.test.lua','src/deep/Run.luau']){
    const relative=active.startsWith('src/deep')?'../../modules/PlayersData.luau':'../modules/PlayersData.luau';
    const source='local M = require("'+relative+'")\nlocal value: M.Data\nvalue.Co';
    const {result}=suggestions(source,makeProject(active,source));
    assert.deepEqual(result.items.map(x=>x.label),['Coins'],active);
  }
});

test('ordinary Module. value completion is NOT confused with the Module.Type namespace',()=>{
  const source='local Module = require("../modules/PlayersData.luau")\nModule.';
  const context=completionContext(source,source.length);
  assert.equal(context.mode,'member');
  assert.equal(workspaceTypeSuggestions(source,source.length,context,makeProject('scripts/Client.lua',source)),null);
  assert.equal(staticCompletions('local input: nu','local input: nu'.length,CORE_API).mode,'type');
});

test('cyclic or unresolved aliases and missing import paths fail closed',()=>{
  const source='export type A = B\nexport type B = A\nexport type C = unknown';
  assert.equal(exportedTypeMembers(source,'A'),null);
  assert.equal(exportedTypeMembers(source,'C'),null);
  const code='local Module = require("../modules/Missing")\nlocal value: Module.Data\nvalue.';
  const result=suggestions(code,makeProject('scripts/Client.lua',code)).result;
  assert.equal(result,null);
});
