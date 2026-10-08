// CI integration test against actual official WebAssembly, not a mock worker.
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
const root = new URL('../public/wasm/', import.meta.url);
const { default: createLuauModule } = await import(new URL('luau-module.js', root));
const bytes = await readFile(fileURLToPath(new URL('luau.wasm', root)));
const compiled = await WebAssembly.compile(bytes);
const runtime = await createLuauModule({ instantiateWasm(imports, ready) {
  WebAssembly.instantiate(compiled, imports).then(ready).catch(err => { console.error(err); process.exitCode = 1; });
  return {};
}});
const source = 'local result: number = 20 + 22\nprint(result)';
const result = JSON.parse(runtime.ccall('luau_execute', 'string', ['string'], [source]));
if (!result.success || !JSON.stringify(result).includes('42')) throw new Error('Native WASM Luau execution failed: ' + JSON.stringify(result));
const diagnostics = JSON.parse(runtime.ccall('luau_get_diagnostics', 'string', ['string'], [source]));
if (!Array.isArray(diagnostics.diagnostics)) throw new Error('Native WASM analysis returned an invalid response');
const bytecode = JSON.parse(runtime.ccall('luau_dump_bytecode', 'string', ['string','number','number','number','number'], [source, 1, 1, 0, 0]));
if (!bytecode.success) throw new Error('Native WASM bytecode compiler failed: ' + JSON.stringify(bytecode));
console.log('Native Luau WASM smoke PASS: execution, diagnostics, bytecode');
