// Manages two independent Luau VM instances. Stopping a run never kills the
// analysis worker. All source code stays in the browser.
export class LuauRuntime {
  constructor({ workerFactory = () => new Worker(new URL('./wasm-worker.js', import.meta.url), { type: 'module' }), timeoutMs = 8000 } = {}) {
    this.workerFactory = workerFactory;
    this.timeoutMs = timeoutMs;
    this.executing = false;
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
    worker.onerror = event => this.reset(kind, event.message || 'Luau worker crashed');
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
      catch (error) { clearTimeout(timer); state.pending.delete(id); reject(error); }
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
  stop() { this.reset('execution', 'Execution stopped'); this.executing = false; }
  async run(project) {
    if (this.executing) throw new Error('An execution is already running');
    this.executing = true;
    try {
      // Initialization (WASM load/compile) can be longer than a normal execution.
      if (!this.execution) await this.request('execution', 'init', {}, 60000);
      const { result, elapsed } = await this.request('execution', 'execute', {
        code: project.files[project.active], files: project.files, mode: project.mode
      });
      return { result, elapsed };
    } finally { this.executing = false; }
  }
  async diagnostics(project) {
    const { result, elapsed } = await this.request('analysis', 'diagnostics', {
      code: project.files[project.active], files: project.files, mode: project.mode
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
    const { result } = await this.request('analysis', 'autocomplete', {
      code: project.files[project.active], files: project.files, mode: project.mode, line, col
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
