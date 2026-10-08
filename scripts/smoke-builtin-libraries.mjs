// Integration checks: actually load the three upstream Luau modules in WASM.
// A library merely existing as a file is NOT sufficient to pass.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {bundleProject} from '../src/module-bundle.js';
import {BUILTIN_LIBRARIES,builtinPath,adaptBuiltinSource} from '../src/builtin-libraries.js';
const wasm = new URL('../public/wasm/',import.meta.url);
const {default:create} = await import(new URL('luau-module.js',wasm));
const compiled = await WebAssembly.compile(await readFile(new URL('luau.wasm',wasm)));
const module = await create({instantiateWasm(imports,ready){WebAssembly.instantiate(compiled, imports).then(ready);return {};}});
const call = (name,result,types,args) => module.ccall(name,result,types,args);
for (const lib of BUILTIN_LIBRARIES) {
  const fullSource = await readFile(new URL(`../public/libraries/${lib.file}`,import.meta.url),'utf8');
  const source = adaptBuiltinSource(lib.id,fullSource);
  const project = {active:'main.luau',files:{'main.luau':lib.example,[builtinPath(lib.id)]:source}};
  const bundle = bundleProject(project,{instrument:false});
  call('luau_clear_modules',null,[],[]);
  for(const [name,text] of Object.entries(bundle.modules)) call('luau_add_module',null,['string','string'],[name,text]);
  const result = JSON.parse(call('luau_execute','string',['string'],[bundle.code]));
  assert.equal(result.success,true,`${lib.label} failed: ${result.error}\n${result.output}`);
  assert.match(result.output,new RegExp(lib.id,'i'));
  console.log(`PASS ${lib.label} v${lib.version}: ${result.output.slice(0,350).replaceAll('\n',' | ')}`);
}
console.log('ALL 3 built-in libraries execute successfully in real Luau WASM');
