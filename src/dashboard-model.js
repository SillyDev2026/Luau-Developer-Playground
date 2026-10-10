import { analyzeDependencies } from './v1-graph.js';
import { findProjectTests } from './v1-model.js';
import { projectSize, countLines } from './store.js';
import { STUDIO_LIBRARIES } from './studio-libraries.js';
import { BUILTIN_LIBRARIES } from './builtin-libraries.js';

export const DASHBOARD_WIDGETS = Object.freeze([
  ['overview','Project overview'], ['recent','Recent files'], ['actions','Quick actions'], ['runtime','WASM runtime health'],
  ['errors','Diagnostics'], ['performance','Run performance'], ['history','Benchmark history'], ['modules','Library catalog'],
  ['dependencies','Dependency health'], ['api','API lookup'], ['tests','Test results'], ['storage','Device storage'],
  ['activity','Recent activity'], ['github','GitHub status'], ['templates','Script templates'], ['quality','Code quality'],
  ['comparisons','Library comparisons'], ['health','Project health'], ['customize','Dashboard preferences'], ['recovery','Recovery center'],
]);
export const DASHBOARD_STORAGE_KEY = 'luauforge:v16:dashboard';
export const DASHBOARD_ACTIVITY_KEY = 'luauforge:v16:activity';
export function readDashboardSettings(storage) {
  let raw = {};
  try { raw = JSON.parse(storage.getItem(DASHBOARD_STORAGE_KEY) || '{}'); } catch { /* fallback */ }
  const valid = new Set(DASHBOARD_WIDGETS.map(x => x[0]));
  const hidden = Array.isArray(raw?.hidden) ? raw.hidden.filter(x => valid.has(x)) : [];
  const order = [...new Set((Array.isArray(raw?.order) ? raw.order : []).filter(x => valid.has(x)))];
  return { hidden, order: [...order, ...DASHBOARD_WIDGETS.map(x => x[0]).filter(x => !order.includes(x))] };
}
export function saveDashboardSettings(storage, data) { storage.setItem(DASHBOARD_STORAGE_KEY, JSON.stringify(data)); }
export function readActivity(storage) {
  try {
    const raw = JSON.parse(storage.getItem(DASHBOARD_ACTIVITY_KEY) || '[]');
    return Array.isArray(raw) ? raw.filter(x => typeof x?.label === 'string' && Number.isFinite(x?.at)).slice(0, 40) : [];
  } catch { return []; }
}
export function appendActivity(storage, label, at = Date.now()) {
  const next = [{ label: String(label).slice(0, 120), at }, ...readActivity(storage)].slice(0, 40);
  try { storage.setItem(DASHBOARD_ACTIVITY_KEY, JSON.stringify(next)); } catch { /* private mode */ }
  return next;
}
export function inspectProject(project, { problems = [], testResults = null, benchmark = null, history = [], snapshots = [] } = {}) {
  const entries = Object.entries(project.files || {});
  const dependencies = analyzeDependencies(project.files);
  const lines = entries.reduce((sum, [,src]) => sum + countLines(src), 0);
  const tests = findProjectTests(project);
  const errors = problems.filter(x => x.severity === 'error');
  const warnings = problems.filter(x => x.severity === 'warning');
  const referenced = [...BUILTIN_LIBRARIES, ...STUDIO_LIBRARIES].filter(lib => entries.some(([,s]) => s.includes(`@${lib.id}`)));
  const healthChecks = [
    { name: 'No circular dependencies', pass: dependencies.cycles.length === 0 },
    { name: 'All static relative imports resolve', pass: dependencies.problems.length === 0 },
    { name: 'No reported diagnostics', pass: errors.length === 0 },
    { name: 'Test files provided', pass: tests.length > 0 },
    { name: 'Recovery snapshot available', pass: snapshots.length > 0 },
  ];
  const status = problems.length === 0 ? 'No recorded diagnostics (not necessarily checked)' : `${errors.length} errors, ${warnings.length} warnings`;
  return {
    name: project.name, fileCount: entries.length, lines, bytes: projectSize(project), modules: entries.filter(([p]) => /^(modules|lib|packages)\//i.test(p)).length,
    tests, testsRun: testResults, problems, errors, warnings, diagnosticsLabel: status, dependencies, referenced, healthChecks,
    healthScore: Math.round(healthChecks.filter(x => x.pass).length / healthChecks.length * 100),
    snapshots, benchmark, history, recentFiles: [...entries].reverse().slice(0, 8).map(([p]) => p),
    studioLibraries: STUDIO_LIBRARIES, wasmLibraries: BUILTIN_LIBRARIES,
  };
}
export function benchmarkComparison(history) {
  return history.filter(x => Number.isFinite(x.medianNs) && typeof x.label === 'string').slice(-30).sort((a,b) => a.medianNs-b.medianNs);
}
