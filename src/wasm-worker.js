// Dedicated workers keep Luau runs stoppable and type checking independent.
// The /public source folder is flattened to the site root by scripts/build.mjs.
// Resolve relative to this worker to support GitHub Pages project subdirectories.
export const RUNTIME_VERSION = '0.3.2';
// GitHub Pages Actions builds publish /wasm, Jekyll branch builds publish
// /public/wasm. Locate and validate the matching pinned runtime assets.
const RUNTIME_LOCATIONS = [
  new URL('../wasm/', import.meta.url),
  new URL('../public/wasm/', import.meta.url)
];
let runtimePromise;

async function fetchAsset(url, label) {
  const res = await fetch(url, { cache: 'no-store' });
  if (!res.ok) throw new Error(`${label} HTTP ${res.status} at ${url.pathname}`);
  if ((res.headers.get('content-type') || '').includes('text/html')) {
    throw new Error(`${label} was replaced by HTML at ${url.pathname}`);
  }
  return res;
}

async function locateRuntime() {
  const failures = [];
  for (const base of RUNTIME_LOCATIONS) {
    const loaderUrl = new URL(`luau-module.js?v=${RUNTIME_VERSION}`, base);
    const wasmUrl = new URL(`luau.wasm?v=${RUNTIME_VERSION}`, base);
    try {
      const [js, wasm] = await Promise.all([
        fetchAsset(loaderUrl, 'Luau loader'),
        fetchAsset(wasmUrl, 'Luau WebAssembly engine')
      ]);
      const [script, buffer] = await Promise.all([js.text(), wasm.arrayBuffer()]);
      if (!script.includes('createLuauModule') || !script.includes('export default')) throw new Error('Invalid Luau loader');
      const magic = new Uint8Array(buffer.slice(0, 4));
      if (buffer.byteLength < 1000000 || magic.join(',') !== '0,97,115,109') throw new Error('Invalid Luau WASM');
      return { loaderUrl, wasmBytes: buffer };
    } catch (error) {
      failures.push(error instanceof Error ? error.message : String(error));
    }
  }
  throw new Error(`Luau WASM files are missing from the published GitHub Pages deployment. ${failures.join(' | ')}. Check Settings → Pages and ensure the pinned public/wasm files are committed.`);
}

async function loadRuntime() {
  if (!runtimePromise) runtimePromise = (async () => {
    const { loaderUrl, wasmBytes } = await locateRuntime();
    const compiled = await WebAssembly.compile(wasmBytes);
    let createLuauModule;
    try {
      ({ default: createLuauModule } = await import(loaderUrl.href));
    } catch (error) {
      throw new Error(`Luau JavaScript module import failed at ${loaderUrl.pathname}: ${error.message}`);
    }
    return createLuauModule({ instantiateWasm(imports, successCallback) {
      WebAssembly.instantiate(compiled, imports).then(successCallback).catch(error => {
        self.postMessage({ type: 'fatal', error: `WebAssembly initialization failed: ${error.message}` });
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
    if (type === 'health') {
      await loadRuntime();
      self.postMessage({ id, type, result: { ready: true, version: RUNTIME_VERSION } });
      return;
    }
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
