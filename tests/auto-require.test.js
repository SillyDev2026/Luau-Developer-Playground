import test from 'node:test';
import assert from 'node:assert/strict';
import { targets, slashAt, boundVariable, suggestions, complete } from '../src/auto-require.js';
const files={'main.luau':'','modules/Math.luau':'return {}','examples/demo.luau':'print(1)'};
test('slash parser only runs at start of statement',()=>{
  assert.deepEqual(slashAt('  /Fast',7),{from:2,to:7,query:'Fast'});
  for(const sample of ['local x=a /Fast','-- /Fast','print("/Fast")']) assert.equal(slashAt(sample,sample.length),null);
});
test('fuzzy suggestions include builtins and relative modules',()=>{
  assert.ok(suggestions('/Fst',4,files,'main.luau').items.some(x=>x.id==='FastNum'));
  assert.equal(targets(files,'examples/demo.luau').find(x=>x.id==='modules/Math.luau').specifier,'../modules/Math.luau');
});
test('insert and reuse existing import',()=>{
  const source='/Fast';const choice=suggestions(source,source.length,files,'main.luau').items.find(x=>x.id==='FastNum');
  const result=complete(source,source.length,choice,files,'main.luau');
  assert.equal(result.source,'local FastME = require("@FastNum")');
  assert.equal(boundVariable(result.source,'@FastNum'),'FastME');
  const existing='local Another = require("@FastNum")\n/Fast';
  const again=complete(existing,existing.length,choice,files,'main.luau');
  assert.equal(again.source,'local Another = require("@FastNum")\nAnother');
});
test('API completion for explicitly imported builtins',()=>{
  const source='local F = require("@FastNum")\nF.add';
  const item=suggestions(source,source.length,files,'main.luau').items.find(x=>x.method==='add');
  assert.ok(item);
  assert.ok(complete(source,source.length,item,files,'main.luau').source.endsWith('F.add()'));
});
