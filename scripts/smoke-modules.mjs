import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {bundleProject,extractRequireTimings,summarizeSamples} from '../src/module-bundle.js';
const root = new URL('../public/wasm/', import.meta.url);
const {default: create} = await import(new URL('luau-module.js', root));
const compiled = await WebAssembly.compile(await readFile(new URL('luau.wasm', root)));
const vm = await create({instantiateWasm(imports, ready) { WebAssembly.instantiate(compiled, imports).then(ready); return {}; }});
const call = (name, kind, types, values) => vm.ccall(name, kind, types, values);
function execute(files, active, instrument) {
  const bundle = bundleProject({files,active}, {instrument});
  call('luau_clear_modules', null, [], []);
  for (const [path, source] of Object.entries(bundle.modules)) call('luau_add_module', null, ['string','string'], [path, source]);
  return extractRequireTimings(JSON.parse(call('luau_execute', 'string', ['string'], [bundle.code])));
}
const files = {
  'tests/main.luau': '--!strict\nlocal number = require("../lib/Value.luau")\nlocal more = require("../lib/More")\nlocal cached = require("../lib/Value.luau")\nprint("TOTAL", more.multiply(number.value, 2), number == cached)',
  'lib/Value.luau': '--!strict\nlocal Module = {value = 21}\nreturn Module',
  'lib/More.luau': '--!strict\nlocal Value = require("./Value.luau")\nreturn {multiply = function(a, b) return a*b end, same = Value.value}',
};
for(const instrument of [false,true]) {
  const result=execute(files,'tests/main.luau',instrument);
  assert.equal(result.success, true, result.error);
  assert.match(result.output,/TOTAL\t42\ttrue/);
  if (instrument) {assert.equal(result.requireTimings.length,4); assert.ok(result.requireTimings.every(item=>item.milliseconds >= 0));}
  console.log('Integrated relative folder imports:',instrument?'profiled':'normal','PASS',result.requireTimings);
}
const analyzed = bundleProject({files, active: 'tests/main.luau'});
call('luau_clear_sources', null, [], []);
for (const [name, source] of Object.entries(analyzed.sources)) call('luau_set_source', null, ['string','string'], [name, source]);
call('luau_set_mode', null, ['number'], [1]);
const checked = JSON.parse(call('luau_get_diagnostics', 'string', ['string'], [analyzed.code]));
assert.ok(Array.isArray(checked.diagnostics));
console.log('Cross-file typechecker output:', checked.diagnostics.slice(0, 3));
const broken = {'main.luau':'local m = require("./DoesNotExist")'};
assert.throws(()=>bundleProject({files: broken, active:'main.luau'}),/Module not found/);
const sample=[];
for(let i=0;i<5;i++) {
 const x=execute(files,'tests/main.luau',true);
 sample.push(x.requireTimings[0].milliseconds);
}
console.log('WASM CPU clock module cold-load:',summarizeSamples(sample));
console.log('Native Luau WASM multi-file require smoke PASS');
