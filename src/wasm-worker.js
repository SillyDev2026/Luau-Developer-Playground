// Dedicated workers keep Luau runs stoppable and type checking independent.
// The /public source folder is flattened to the site root by scripts/build.mjs.
// Resolve relative to this worker to support GitHub Pages project subdirectories.
import { bundleProject, extractRequireTimings } from './module-bundle.js';
export const RUNTIME_VERSION = '0.3.3';
// A Pages Actions artifact contains /wasm/*, whereas Jekyll branch publishing
// preserves public/wasm/*. Detect the actual layout rather than guessing.
const RUNTIME_LOCATIONS = [
  new URL('../wasm/', import.meta.url),
  new URL('../public/wasm/', import.meta.url),
];
let runtimePromise;

async function fetchAsset(url, description) {
  const response = await fetch(url, { cache: 'no-store' });
  if (!response.ok) throw new Error(`${description}: HTTP ${response.status} (${url.pathname})`);
  if ((response.headers.get('content-type') || '').includes('text/html')) {
    throw new Error(`${description}: HTML returned instead of a runtime asset (${url.pathname})`);
  }
  return response;
}

async function locateRuntime() {
  const failures = [];
  for (const base of RUNTIME_LOCATIONS) {
    const loaderUrl = new URL(`luau-module.js?v=${RUNTIME_VERSION}`, base);
    const wasmUrl = new URL(`luau.wasm?v=${RUNTIME_VERSION}`, base);
    try {
      // Verify both assets BEFORE importing the ES module.
      const [loaderResponse, wasmResponse] = await Promise.all([
        fetchAsset(loaderUrl, 'Luau loader'),
        fetchAsset(wasmUrl, 'Luau WASM')
      ]);
      const [loaderText, wasmBytes] = await Promise.all([loaderResponse.text(), wasmResponse.arrayBuffer()]);
      if (!loaderText.includes('createLuauModule') || !loaderText.includes('export default')) {
        throw new Error(`Invalid Luau loader at ${loaderUrl.pathname}`);
      }
      const magic = new Uint8Array(wasmBytes.slice(0, 4));
      if (wasmBytes.byteLength < 1_000_000 || magic.join(',') !== '0,97,115,109') {
        throw new Error(`Invalid Luau WebAssembly binary at ${wasmUrl.pathname}`);
      }
      return { loaderUrl, wasmBytes };
    } catch (error) {
      failures.push(error instanceof Error ? error.message : String(error));
    }
  }
  throw new Error(`Luau WASM files are not available in this GitHub Pages deployment. ${failures.join(' | ')}. Verify that public/wasm assets are committed, or select GitHub Actions under Settings → Pages.`);
}

async function loadRuntime() {
  if (!runtimePromise) runtimePromise = (async () => {
    const { loaderUrl, wasmBytes } = await locateRuntime();
    const compiled = await WebAssembly.compile(wasmBytes);
    let createLuauModule;
    try {
      ({ default: createLuauModule } = await import(loaderUrl.href));
    } catch (error) {
      throw new Error(`Luau module import failed at ${loaderUrl.pathname}: ${error.message}`);
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
  const { id, type, code = '', files = {}, active = 'main.luau', mode = 'strict', optimization = 1, modulePath } = event.data;
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
      const bundle = bundleProject({ files, active }, { instrument: true });
      register(module, bundle.modules, true);
      result = extractRequireTimings(JSON.parse(ccall(module, 'luau_execute', 'string', ['string'], [bundle.code])));
    } else if (type === 'diagnostics') {
      const bundle = bundleProject({ files, active });
      register(module, bundle.sources, false);
      result = JSON.parse(ccall(module, 'luau_get_diagnostics', 'string', ['string'], [bundle.code]));
      const names = Object.fromEntries(Object.entries(bundle.aliases).map(([name, key]) => [key, name]));
      for (const item of result.diagnostics || []) item.moduleName = names[item.moduleName] || item.moduleName;
    } else if (type === 'bytecode') {
      result = JSON.parse(ccall(module, 'luau_dump_bytecode', 'string',
        ['string', 'number', 'number', 'number', 'number'], [code, optimization, 1, 0, 0]));
    } else if (type === 'autocomplete') {
      const bundle = bundleProject({ files, active });
      register(module, bundle.sources, false);
      result = JSON.parse(ccall(module, 'luau_autocomplete', 'string', ['string', 'number', 'number'], [bundle.code, event.data.line, event.data.col]));
    } else if (type === 'benchmarkModule') {
      if (!Object.hasOwn(files, modulePath)) throw new Error('Select an existing Luau module to benchmark.');
      const benchName = '__lf_bench_entry.luau';
      if (Object.hasOwn(files, benchName)) throw new Error('Reserved benchmark filename exists in project.');
      const benchmarkFiles = { ...files, [benchName]: `local first = require(${JSON.stringify('./' + modulePath)})\nlocal cached = require(${JSON.stringify('./' + modulePath)})\nassert(first == cached, 'require cache mismatch')` };
      const bundle = bundleProject({ files: benchmarkFiles, active: benchName }, { instrument: true });
      const samples = [];
      for (let round = 0; round < 12; round++) {
        register(module, bundle.modules, true);
        const measurement = extractRequireTimings(JSON.parse(ccall(module, 'luau_execute', 'string', ['string'], [bundle.code])));
        if (!measurement.success) throw new Error(`Benchmark failed: ${measurement.error || 'Unknown Luau runtime error'}`);
        const targeted = measurement.requireTimings.filter(item => item.module === modulePath);
        if (targeted.length !== 2) throw new Error(`Module ${modulePath} did not produce both cold and cached measurements.`);
        samples.push({ coldMs: targeted[0].milliseconds, cachedMs: targeted[1].milliseconds });
      }
      result = { module: modulePath, samples, runtime: 'Luau WASM VM os.clock (CPU time)', roundCount: samples.length };
    } else throw new Error(`Unknown engine command: ${type}`);
    self.postMessage({ id, type, result, elapsed: performance.now() - started });
  } catch (error) {
    self.postMessage({ id, type: 'error', error: error instanceof Error ? error.message : String(error) });
  }
};
