import { loadBuiltinsForProject, builtinPath, builtinId } from "./builtin-libraries.js";
import { loadGithubForProject } from "./github-modules.js";
// Manages two independent Luau VM instances. Stopping a run never kills the
// analysis worker. All source code stays in the browser.
export class LuauRuntime {
  constructor({ workerFactory = () => new Worker(new URL('./wasm-worker.js?v=1.0.0', import.meta.url), { type: 'module' }), timeoutMs = 8000 } = {}) {
    this.workerFactory = workerFactory;
    this.timeoutMs = timeoutMs;
    this.executing = false;
    this.runGeneration = 0;
    this.counter = 0;
    this.execution = null;
    this.analysis = null;
  }
  getWorker(kind) {
    if (this[kind]) return this[kind];
    const worker = this.workerFactory();
    const state = { worker, pending: new Map() };
    worker.onmessage = ({ data }) => {
      if (data.type === 'fatal') { this.reset(kind, data.error); return; }
      const pending = state.pending.get(data.id);
      if (!pending) return;
      clearTimeout(pending.timer);
      state.pending.delete(data.id);
      if (data.type === 'error') pending.reject(new Error(data.error));
      else pending.resolve(data);
    };
    worker.onerror = event => {
      event.preventDefault?.();
      this.reset(kind, `Luau ${kind} worker failed: ${event.message || 'script could not load'}`);
    };
    worker.onmessageerror = () => this.reset(kind, `Luau ${kind} worker sent an unreadable message`);
    this[kind] = state;
    return state;
  }
  request(kind, type, payload = {}, timeout = this.timeoutMs) {
    const state = this.getWorker(kind);
    const id = ++this.counter;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => this.reset(kind, `${type} timed out after ${timeout}ms`), timeout);
      state.pending.set(id, { resolve, reject, timer });
      try { state.worker.postMessage({ id, type, ...payload }); }
      catch (error) { clearTimeout(timer); state.pending.delete(id); this.reset(kind, error.message); reject(error); }
    });
  }
  reset(kind, reason = 'Execution stopped') {
    const state = this[kind];
    if (!state) return;
    this[kind] = null;
    state.worker.terminate();
    for (const pending of state.pending.values()) {
      clearTimeout(pending.timer);
      pending.reject(new Error(reason));
    }
    state.pending.clear();
  }
  stop() { this.runGeneration++; this.reset('execution', 'Execution stopped'); this.executing = false; }
  async run(project) {
    if (this.executing) throw new Error('An execution is already running');
    this.executing = true;
    const generation = ++this.runGeneration;
    try {
      // Initialization (WASM load/compile) can be longer than a normal execution.
      const ready = await loadBuiltinsForProject(await loadGithubForProject(project));
      if (this.runGeneration !== generation) throw new Error('Execution stopped');
      if (!this.execution) await this.request('execution', 'init', {}, 60000);
      const { result, elapsed } = await this.request('execution', 'execute', {
        code: ready.files[ready.active], files: ready.files, active: ready.active, mode: ready.mode
      }, project.benchmark ? 120000 : this.timeoutMs);
      return { result, elapsed };
    } finally { if (this.runGeneration === generation) this.executing = false; }
  }
  async benchmarkModule(project, modulePath) {
    if (this.executing) throw new Error('A script is already running');
    this.executing = true;
    const generation = ++this.runGeneration;
    try {
      const special = builtinId(modulePath);
      if (modulePath.startsWith('@') && !special) throw new Error('GitHub module benchmarking: open a script with the module require and benchmark its load with os.clock().');
      const extra = special ? { ...project, files: { ...project.files, '__lf_bench_loader.luau': `local library = require(\"@${special}\")` } } : project;
      const ready = await loadBuiltinsForProject(await loadGithubForProject(extra));
      if (this.runGeneration !== generation) throw new Error('Execution stopped');
      const path = special ? builtinPath(special) : modulePath;
      const { result } = await this.request('execution', 'benchmarkModule', { files: ready.files, active: ready.active, mode: ready.mode, modulePath: path, displayName: special ? `@${special}` : modulePath }, 120000);
      return result;
    } finally { if (this.runGeneration === generation) this.executing = false; }
  }
  async health() {
    const { result } = await this.request('analysis', 'health', {}, 60000);
    return result;
  }
  async diagnostics(project) {
    const ready = await loadBuiltinsForProject(await loadGithubForProject(project));
    const { result, elapsed } = await this.request('analysis', 'diagnostics', {
      code: ready.files[ready.active], files: ready.files, active: ready.active, mode: ready.mode
    }, 60000);
    return { diagnostics: Array.isArray(result.diagnostics) ? result.diagnostics : [], elapsed };
  }
  async bytecode(project) {
    const { result, elapsed } = await this.request('analysis', 'bytecode', {
      code: project.files[project.active], mode: project.mode, optimization: project.optimization
    }, 60000);
    return { result, elapsed };
  }
  async autocomplete(project, line, col) {
    const ready = await loadBuiltinsForProject(await loadGithubForProject(project));
    const { result } = await this.request('analysis', 'autocomplete', {
      code: ready.files[ready.active], files: ready.files, active: ready.active, mode: ready.mode, line, col
    }, 60000);
    return Array.isArray(result.items) ? result.items : [];
  }
  dispose() { this.reset('execution', 'Disposed'); this.reset('analysis', 'Disposed'); }
}
export function normalizeDiagnostics(list) {
  return list.map(d => ({
    message: String(d.message ?? 'Diagnostic'),
    severity: d.severity === 'error' ? 'error' : d.severity === 'warning' ? 'warning' : 'info',
    line: Math.max(1, Number(d.startLine ?? 0) + 1),
    column: Math.max(1, Number(d.startCol ?? 0) + 1),
    module: d.moduleName ?? 'main'
  })).sort((a, b) => a.line - b.line || a.column - b.column);
}
export function renderOutput(result) {
  if (typeof result.output === 'string') return result.output;
  if (Array.isArray(result.prints)) return result.prints.map(args => args.map(arg =>
    typeof arg === 'object' && arg !== null ? JSON.stringify(arg) : String(arg)).join('\t')).join('\n');
  return '';
}
