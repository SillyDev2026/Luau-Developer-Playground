// Dedicated workers keep Luau runs stoppable and type checking independent.
// The /public source folder is flattened to the site root by scripts/build.mjs.
// Resolve relative to this worker to support GitHub Pages project subdirectories.
export const RUNTIME_VERSION = '0.3.1';
const wasmUrl = new URL(`../wasm/luau.wasm?v=${RUNTIME_VERSION}`, import.meta.url);
const loaderUrl = new URL(`../wasm/luau-module.js?v=${RUNTIME_VERSION}`, import.meta.url);
let runtimePromise;

async function assetResponse(url, description) {
  let response;
  try {
    response = await fetch(url, { cache: 'no-store' });
  } catch (error) {
    throw new Error(`Unable to load ${description} (${url.pathname}). Check your connection. ${error.message}`);
  }
  if (!response.ok) {
    throw new Error(`${description} missing (HTTP ${response.status}) at ${url.pathname}. In GitHub Settings → Pages, select GitHub Actions as the publishing source, then redeploy.`);
  }
  const contentType = response.headers.get('content-type') || '';
  if (contentType.includes('text/html')) {
    throw new Error(`${description} was replaced by an HTML page at ${url.pathname}. Verify GitHub Pages is publishing the Actions build.`);
  }
  return response;
}

async function loadRuntime() {
  if (!runtimePromise) runtimePromise = (async () => {
    // Check the actual published JS file before import() so a 404 becomes an
    // actionable message instead of an unhelpful browser module-import error.
    const [loaderResponse, wasmResponse] = await Promise.all([
      assetResponse(loaderUrl, 'Luau JavaScript loader'),
      assetResponse(wasmUrl, 'Luau WebAssembly engine')
    ]);
    const jsText = await loaderResponse.text();
    if (!jsText.includes('createLuauModule')) throw new Error('Luau JavaScript loader is invalid. Redeploy GitHub Pages.');
    const wasmBytes = await wasmResponse.arrayBuffer();
    if (wasmBytes.byteLength < 1_000_000) throw new Error('Luau WebAssembly engine is incomplete. Redeploy GitHub Pages.');
    const compiled = await WebAssembly.compile(wasmBytes);
    let createLuauModule;
    try {
      ({ default: createLuauModule } = await import(loaderUrl.href));
    } catch (error) {
      throw new Error(`Luau loader import failed at ${loaderUrl.pathname}: ${error.message}. Ensure Pages uses the GitHub Actions build.`);
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
