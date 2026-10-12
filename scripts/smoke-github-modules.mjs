// Real Luau WASM end-to-end test: a public module imported via @owner/repo/path.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { loadGithubForProject } from '../src/github-modules.js';
import { bundleProject } from '../src/module-bundle.js';
const root = new URL('../public/wasm/', import.meta.url);
const { default: createLuauModule } = await import(new URL('luau-module.js', root));
const compiled = await WebAssembly.compile(await readFile(new URL('luau.wasm',root)));
const vm = await createLuauModule({instantiateWasm(imports,ready){WebAssembly.instantiate(compiled,imports).then(ready);return {};}});
const call = (name, result, types, args)=>vm.ccall(name,result,types,args);
const project = {active:'tests/github-test.test.luau',files:{
  'tests/github-test.test.luau':'--!strict\nlocal T = require("@SillyDev2026/Luau-Developer-Playground/community/TestTools.luau")\nlocal Math = require("@SillyDev2026/Luau-Developer-Playground/community/MathKit.luau")\nT.run("public module test", function() T.equal(Math.add(20,22), 42) end)\nlocal Suite = require("@SillyDev2026/Luau-Developer-Playground/community/tests/MathKitTests.luau")\nSuite.run()\nlocal T2 = require("@SillyDev2026/Luau-Developer-Playground/community/TestTools.luau")\nprint("cached", T == T2)'
}};
const loaded = await loadGithubForProject(project,{storage:{getItem:()=>null},moduleUrl:'https://test.invalid/project/src/github-modules.js',fetchImpl:async url=>({ok:true,headers:{get:()=> 'text/plain'},text:async()=>readFile(new URL(url.includes('/community/tests/')?'tests/'+url.split('/').at(-1):url.split('/').at(-1),new URL('../public/community/',import.meta.url)),'utf8')})});
const bundle=bundleProject(loaded,{instrument:true});
call('luau_clear_modules',null,[],[]);
for(const [filename,source] of Object.entries(bundle.modules))call('luau_add_module',null,['string','string'],[filename,source]);
const result=JSON.parse(call('luau_execute','string',['string'],[bundle.code]));
assert.equal(result.success,true,result.error);
assert.match(result.output,/PASS\tpublic module test/);
assert.match(result.output,/cached\ttrue/);
assert.match(result.output,/PASS\tMathKit\.multiply/);
assert.equal(Object.keys(bundle.modules).length,3);
console.log('Public GitHub @-specifier WASM import, test helper and module cache PASS');


// Exercise both new public modules inside the real standalone Luau VM.
const extra = {active:'tests/catalog-v34.test.luau',files:{
  'tests/catalog-v34.test.luau':[
    '--!strict',
    'local SignalLite = require("@SillyDev2026/Luau-Developer-Playground/community/SignalLite.luau")',
    'local TableKit = require("@SillyDev2026/Luau-Developer-Playground/community/TableKit.luau")',
    'local signal = SignalLite.new()',
    'local total = 0',
    'local conn = signal:Connect(function(x) total += x end)',
    'signal:Fire(10)',
    'conn:Disconnect()',
    'signal:Fire(5)',
    'assert(total == 10, "SignalLite disconnect failed")',
    'local first = {Coins = 10, Level = 2}',
    'local combined = TableKit.merge(first, {Coins = 20, Enabled = true})',
    'assert(first.Coins == 10 and combined.Coins == 20 and combined.Level == 2)',
    'assert(#TableKit.keys(combined) == 3)',
    'assert(TableKit.copy(first).Coins == 10)',
    'signal:Destroy()',
    'print("PASS", "new public modules and module cache")'
  ].join('\n')
}};
const extraReady=await loadGithubForProject(extra,{storage:{getItem:()=>null},
  moduleUrl:'https://test.invalid/project/src/github-modules.js',fetchImpl:async url=>({
    ok:true,headers:{get:()=> 'text/plain'},
    text:async()=>readFile(new URL(url.split('/').at(-1),new URL('../public/community/',import.meta.url)),'utf8')
  })});
const extraBundle=bundleProject(extraReady,{instrument:true});
call('luau_clear_modules',null,[],[]);
for(const [filename,source] of Object.entries(extraBundle.modules))call('luau_add_module',null,['string','string'],[filename,source]);
const extraRun=JSON.parse(call('luau_execute','string',['string'],[extraBundle.code]));
assert.equal(extraRun.success,true,extraRun.error);
assert.match(extraRun.output,/PASS\tnew public modules and module cache/);
assert.equal(Object.keys(extraBundle.modules).length,2);
console.log('SignalLite + TableKit public imports and execution PASS');
