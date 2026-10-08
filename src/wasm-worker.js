// Separate workers for execution and analysis keep the editor responsive.
// The Emscripten wrapper and WASM are distributed together from the pinned
// luau-lang/playground revision fetched during the deployment build.
let runtimePromise;
async function loadRuntime() {
  if (!runtimePromise) runtimePromise = (async () => {
    const [{ default: createLuauModule }, response] = await Promise.all([
      import('../public/wasm/luau-module.js'),
      fetch(new URL('../public/wasm/luau.wasm', import.meta.url))
    ]);
    if (!response.ok) throw new Error(`Luau WASM missing (HTTP ${response.status}). Run npm run fetch:wasm during development.`);
    const module = await WebAssembly.compile(await response.arrayBuffer());
    return createLuauModule({ instantiateWasm(imports, successCallback) {
      WebAssembly.instantiate(module, imports).then(successCallback).catch(error => {
        self.postMessage({ type: 'fatal', error: String(error) });
      });
      return {};
    }});
  })().catch(error => { runtimePromise = null; throw error; });
  return runtimePromise;
}
function ccall(module, name, result, types, args) {
  return module.ccall(name, result, types, args);
}
function register(module, files, execution) {
  if (!files || typeof files !== 'object') return;
  const clear = execution ? 'luau_clear_modules' : 'luau_clear_sources';
  const set = execution ? 'luau_add_module' : 'luau_set_source';
  ccall(module, clear, null, [], []);
  for (const [name, content] of Object.entries(files)) {
    ccall(module, set, null, ['string', 'string'], [name, content]);
  }
}
self.onmessage = async event => {
  const { id, type, code = '', files = {}, mode = 'strict', optimization = 1 } = event.data;
  try {
    const module = await loadRuntime();
    const started = performance.now();
    ccall(module, 'luau_set_mode', null, ['number'], [mode === 'strict' ? 1 : mode === 'nocheck' ? 2 : 0]);
    let result;
    if (type === 'init') result = { ready: true };
    else if (type === 'execute') {
      register(module, files, true);
      result = JSON.parse(ccall(module, 'luau_execute', 'string', ['string'], [code]));
    } else if (type === 'diagnostics') {
      register(module, files, false);
      result = JSON.parse(ccall(module, 'luau_get_diagnostics', 'string', ['string'], [code]));
    } else if (type === 'bytecode') {
      result = JSON.parse(ccall(module, 'luau_dump_bytecode', 'string',
        ['string', 'number', 'number', 'number', 'number'], [code, optimization, 1, 0, 0]));
    } else if (type === 'autocomplete') {
      register(module, files, false);
      result = JSON.parse(ccall(module, 'luau_autocomplete', 'string', ['string', 'number', 'number'], [code, event.data.line, event.data.col]));
    } else throw new Error(`Unknown engine command: ${type}`);
    self.postMessage({ id, type, result, elapsed: performance.now() - started });
  } catch (error) {
    self.postMessage({ id, type: 'error', error: error instanceof Error ? error.message : String(error) });
  }
};
