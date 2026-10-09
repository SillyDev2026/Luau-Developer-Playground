import { Workspace, findProjectTests, classifyScript } from './v1-model.js';
import { CodeEditor, matchBracket } from './v1-editor.js';
import { makeZip } from './v1-zip.js';
import { analyzeDependencies } from './v1-graph.js';
import { LuauRuntime, normalizeDiagnostics, renderOutput } from './wasm-client.js';
import { BUILTIN_LIBRARIES } from './builtin-libraries.js';
import { mountAutoRequire, boundVariable } from './auto-require.js';
import { outlineSymbols } from './editor-intelligence.js';
import { findMatches, replaceAllLiteral } from './editor-utils.js';
import { countLines, projectSize, formatBytes, validateProject, projectToJSON } from './store.js';
import { summarizeSamples } from './module-bundle.js';

const $ = id => document.getElementById(id);
const runtime = new LuauRuntime();
const state = { side: 'files', output: 'console', dialogs: false, busy: false, runToken: 0, checking: 0, problems: [], outputLogs: [], bytecode: null, bench: null, tests: null, liveCheck: false, lastFile: null, toastTimer: 0, liveTimer: 0, outputHeight: 202, sideWidth: 266, disposed: false };
const settingsKey = 'luauforge:v1:settings';
try { Object.assign(state, JSON.parse(localStorage.getItem(settingsKey) || '{}')); } catch { /* no saved settings */ }
const workspace = new Workspace({ onChange: refresh, onSave: () => { $('save-status').textContent = '✓ Saved locally'; }, onError: error => { $('save-status').textContent = '⚠ Not saved'; notify('Local storage failed: ' + error.message, true); } });
const editor = new CodeEditor({ input: $('code-input'), highlight: $('syntax-code'), gutter: $('line-gutter'), onChange: text => { try { workspace.source(text); liveDiagnostics(); } catch (error) { notify(error.message, true); } }, onCursor: updateCursor, onShortcut: key => { if (key === 'enter') runCurrent(); else if (key === 's') save(); else if (key === 'p') palette(); else if (key === 'b') benchmarkPicker(); else if (key === 'f') openFind(); } });

function notify(message, warning = false) {
  const toast = $('toast'); toast.textContent = String(message); toast.className = 'toast' + (warning ? ' warning' : '');
  clearTimeout(state.toastTimer); state.toastTimer = setTimeout(() => toast.classList.add('hidden'), 3200);
}
function preserveSettings() {
  try { localStorage.setItem(settingsKey, JSON.stringify({ side: state.side, output: state.output, liveCheck: state.liveCheck })); } catch { /* private mode: nonfatal */ }
}
function save() { const ok = workspace.flush(); $('save-status').textContent = ok ? '✓ Saved on this device' : '⚠ Storage unavailable'; if (ok) notify('Workspace saved locally'); }
function escapeText(text) { return String(text ?? ''); }
function download(name, content, type = 'application/octet-stream') {
  const blob = content instanceof Uint8Array ? new Blob([content], { type }) : new Blob([content], { type });
  const url = URL.createObjectURL(blob), link = document.createElement('a');
  link.href = url; link.download = name; document.body.append(link); link.click(); link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
function createElement(tag, text, className = '') { const node = document.createElement(tag); if (text !== undefined) node.textContent = escapeText(text); if (className) node.className = className; return node; }
function clickButton(text, callback, className = '') { const button = createElement('button', text, className); button.type = 'button'; button.addEventListener('click', callback); return button; }
function modal(title, render) {
  state.dialogs = true; $('dialog-title').textContent = title;
  const body = $('dialog-body'); body.replaceChildren(); render(body);
  $('modal-backdrop').classList.remove('hidden');
  document.addEventListener('keydown', modalEscape, true);
  const field = body.querySelector('input,textarea,select,button'); field?.focus();
}
function modalEscape(event) { if (event.key === 'Escape') { event.preventDefault(); closeModal(); } }
function closeModal() { state.dialogs = false; $('modal-backdrop').classList.add('hidden'); document.removeEventListener('keydown', modalEscape, true); $('code-input').focus(); }
function promptModal(title, label, value, action) {
  modal(title, body => {
    body.append(createElement('p', label, 'dialog-hint'));
    const input = createElement('input'); input.value = value; input.maxLength = 140; body.append(input);
    const submit = clickButton('Confirm', async () => {
      submit.disabled = true;
      try { const result = await action(input.value.trim()); if (result !== false && state.dialogs) closeModal(); }
      catch (error) { notify(error.message, true); }
      finally { submit.disabled = false; }
    }, 'dialog-cta'); body.append(submit);
    input.addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); submit.click(); } });
  });
}
function renderFiles() {
  const tree = $('file-tree'); tree.replaceChildren();
  const query = $('file-filter').value.toLowerCase();
  const files = Object.keys(workspace.project.files).sort((a, b) => a.localeCompare(b));
  let lastGroup = '';
  for (const file of files) {
    if (query && !file.toLowerCase().includes(query)) continue;
    const parts = file.split('/'), folder = parts.length > 1 ? parts.slice(0, -1).join('/') : 'root';
    if (lastGroup !== folder) { tree.append(createElement('div', folder, 'file-folder')); lastGroup = folder; }
    const row = clickButton('', () => openFile(file), 'file-node' + (file === workspace.project.active ? ' active' : ''));
    row.title = file; row.append(createElement('span', classifyScript(file) === 'test' ? '✓' : classifyScript(file) === 'module' ? '◇' : '▧', 'file-glyph'), createElement('span', parts.at(-1), 'file-name'));
    tree.append(row);
  }
  if (!tree.children.length) tree.append(createElement('p', 'No files match the filter.', 'output-empty'));
}
function renderTabs() {
  const tabs = $('tabs'); tabs.replaceChildren();
  for (const file of workspace.tabs) {
    const tab = clickButton('', () => openFile(file), 'tab' + (file === workspace.project.active ? ' active' : ''));
    tab.setAttribute('role', 'tab'); tab.setAttribute('aria-selected', String(file === workspace.project.active)); tab.title = file;
    tab.append(createElement('span', file.split('/').at(-1)));
    const close = createElement('small', '×'); close.title = 'Close tab'; close.addEventListener('click', e => { e.stopPropagation(); workspace.close(file); });
    tab.append(close); tabs.append(tab);
  }
}
function renderSymbols() {
  const body = $('symbol-tree'); body.replaceChildren();
  for (const symbol of outlineSymbols(workspace.project.files[workspace.project.active] || '').slice(0, 250)) {
    const row = clickButton('', () => { editor.selectLine(symbol.line); closeMobile(); }, 'symbol-node');
    row.append(createElement('span', symbol.kind === 'function' ? 'ƒ' : symbol.kind === 'type' ? '◇' : '•', 'symbol-kind'), createElement('span', symbol.name, 'file-name'), createElement('span', String(symbol.line), 'symbol-kind')); body.append(row);
  }
  if (!body.children.length) body.append(createElement('p', 'No declarations found in the active file.', 'output-empty'));
}
function renderLibrary() {
  const catalog = $('builtin-catalog'), query = $('library-filter').value.toLowerCase(); catalog.replaceChildren();
  for (const lib of BUILTIN_LIBRARIES) {
    if (query && !`${lib.id} ${lib.label} ${lib.description}`.toLowerCase().includes(query)) continue;
    const card = createElement('section', undefined, 'builtin-catalog-item');
    const heading = createElement('div', undefined, 'builtin-catalog-heading');
    heading.append(createElement('strong', lib.label), createElement('span', 'v' + lib.version));
    card.append(heading, createElement('p', lib.description));
    const actions = createElement('div', undefined, 'builtin-catalog-actions');
    actions.append(clickButton('Example', () => {
      const path = `examples/${lib.id.toLowerCase()}-example.luau`;
      try { Object.hasOwn(workspace.project.files, path) ? workspace.open(path) : workspace.create(path, lib.example); setSide('files'); closeMobile(); notify(lib.label + ' example is ready'); }
      catch (error) { notify(error.message, true); }
    }), clickButton('API', () => libraryAPI(lib)), clickButton('Import', () => { importLibrary(lib); if (matchMedia('(max-width:820px)').matches) closeMobile(); }));
    card.append(actions); catalog.append(card);
  }
}
function libraryAPI(lib) {
  modal(lib.label + ' API · v' + lib.version, body => {
    body.append(createElement('p', lib.description, 'dialog-hint'));
    for (const category of lib.categories) {
      body.append(createElement('strong', category.name));
      for (const signature of category.methods.slice(0, 60)) body.append(createElement('div', signature, 'tool-card'));
    }
    body.append(clickButton('Insert import', () => { importLibrary(lib); closeModal(); }, 'dialog-cta'));
  });
}
function importLibrary(lib) {
  const code = editor.input.value;
  if (boundVariable(code, '@' + lib.id)) { notify('Already imported: ' + lib.label); return; }
  const variable = lib.local;
  let name = variable, suffix = 2;
  while (new RegExp('\\blocal\\s+' + name + '\\b').test(code)) name = variable + suffix++;
  const statement = `local ${name} = require("@${lib.id}")\n`;
  const directive = code.match(/^--!\w+[^\n]*\n/);
  const at = directive ? directive[0].length : 0;
  editor.replace(at, at, statement, Math.max(at + statement.length, editor.input.selectionStart)); notify(lib.label + ' imported');
}
function metrics() {
  const p = workspace.project;
  $('project-metrics').textContent = `${Object.keys(p.files).length} files · ${formatBytes(projectSize(p))} · ${p.mode.toUpperCase()} · O${p.optimization}`;
  $('font-value').textContent = p.fontSize + 'px'; $('font-label').textContent = p.fontSize + 'px';
}
function refresh() {
  const p = workspace.project;
  $('project-title').textContent = p.name; $('current-file').textContent = p.active;
  $('breadcrumb-file').textContent = p.active;
  $('save-status').textContent = 'Saving locally…';
  if (state.lastFile !== p.active || editor.input.value !== p.files[p.active]) {
    state.lastFile = p.active; editor.load(p.files[p.active], p.active);
  }
  document.documentElement.style.setProperty('--editor-font', p.fontSize + 'px');
  $('code-input').wrap = p.wordWrap ? 'soft' : 'off';
  $('syntax-code').style.whiteSpace = p.wordWrap ? 'pre-wrap' : 'pre';
  $('highlight-scroll').style.whiteSpace = p.wordWrap ? 'pre-wrap' : 'pre';
  $('mode-select').value = p.mode;
  $('optimization-select').value = String(p.optimization);
  $('font-slider').value = String(p.fontSize);
  $('wrap-select').checked = p.wordWrap;
  metrics(); renderFiles(); renderTabs(); renderSymbols(); updateCursor();
}
function updateCursor() {
  if (!editor?.input) return;
  const text = editor.input.value, pos = editor.position;
  $('cursor-indicator').textContent = `Ln ${pos.line}, Col ${pos.column}`;
  $('line-indicator').textContent = `${countLines(text)} lines`;
  const brackets = matchBracket(text, editor.input.selectionStart);
  $('bracket-indicator').textContent = brackets ? `Brackets ${brackets[0] + 1} ↔ ${brackets[1] + 1}` : '';
}
function setSide(side) {
  state.side = side; preserveSettings();
  for (const name of ['files', 'libraries', 'symbols']) { $(name + '-pane').classList.toggle('hidden', side !== name); const button = document.querySelector(`[data-side="${name}"]`); button.classList.toggle('active', name === side); button.setAttribute('aria-selected', String(name === side)); }
  $('sidebar-title').textContent = side.toUpperCase();
  if (side === 'symbols') renderSymbols();
  if (side === 'libraries') renderLibrary();
}
function closeMobile() { $('sidebar').classList.remove('is-mobile-open'); $('inspector').classList.remove('is-mobile-open'); $('side-shade').classList.add('hidden'); }
function openMobile(which) {
  closeMobile();
  if (which === 'sidebar') { $('sidebar').classList.add('is-mobile-open'); $('side-shade').classList.remove('hidden'); }
  if (which === 'inspector') { $('inspector').classList.remove('is-hidden'); $('inspector').classList.add('is-mobile-open'); $('side-shade').classList.remove('hidden'); }
}
function openFile(path) { try { workspace.open(path); if (matchMedia('(max-width:820px)').matches) closeMobile(); editor.input.focus(); } catch (error) { notify(error.message, true); } }
function switchOutput(view) {
  state.output = view; preserveSettings();
  document.querySelectorAll('[data-output]').forEach(button => button.classList.toggle('active', button.dataset.output === view));
  renderOutputPanel();
}
function consoleLog(message, kind = '') {
  state.outputLogs.push({ message: String(message), kind });
  if (state.outputLogs.length > 260) state.outputLogs.splice(0, state.outputLogs.length - 260);
  if (state.output === 'console') renderOutputPanel();
}
function addToolCard(parent, title, subtitle, action, text) {
  const card = createElement('div', undefined, 'tool-card'); card.append(createElement('strong', title));
  if (subtitle) card.append(createElement('p', subtitle));
  if (action) card.append(clickButton(text || 'Open file', action));
  parent.append(card);
}
function renderOutputPanel() {
  const output = $('output-content'); output.replaceChildren();
  if (state.output === 'console') {
    if (!state.outputLogs.length) output.append(createElement('div', 'Welcome to LuauForge 1.0 · Press Run or Ctrl+Enter. All code stays in your browser.', 'output-empty'));
    for (const item of state.outputLogs) output.append(createElement('p', item.message, 'output-line ' + item.kind));
    output.scrollTop = output.scrollHeight;
  } else if (state.output === 'problems') {
    if (!state.problems.length) output.append(createElement('div', 'No diagnostics. Click ✓ Check to analyze the active file.', 'output-empty'));
    for (const diag of state.problems) addToolCard(output, `${diag.severity.toUpperCase()} · ${diag.module || workspace.project.active}:${diag.line}:${diag.column}`, diag.message, () => { if (Object.hasOwn(workspace.project.files, diag.module)) workspace.open(diag.module); editor.selectLine(diag.line); }, 'Go to line');
  } else if (state.output === 'bytecode') {
    if (!state.bytecode) output.append(createElement('div', 'Press Inspect bytecode to compile the active file.', 'output-empty'));
    else output.append(createElement('pre', state.bytecode));
  } else if (state.output === 'benchmarks') {
    if (!state.bench) output.append(createElement('div', 'Run a module benchmark from Settings. Samples are measured inside the Luau WASM VM, not JavaScript rendering.', 'output-empty'));
    else {
      addToolCard(output, 'Benchmark: ' + state.bench.module, `${state.bench.roundCount} fresh Lua states · Luau WASM os.clock`, null);
      for (const [label, field] of [['Cold load', 'coldMs'], ['Cached require', 'cachedMs']]) {
        const summary = summarizeSamples(state.bench.samples.map(x => x[field]));
        addToolCard(output, label + ': ' + (summary.medianMs ?? 0).toFixed(4) + ' ms median', `Min ${summary.minMs?.toFixed(4)} ms  ·  Max ${summary.maxMs?.toFixed(4)} ms · ${summary.samples} samples`, null);
      }
    }
  } else if (state.output === 'tests') {
    if (!state.tests) output.append(createElement('div', 'Create a file ending in .test.luau or .spec.luau, then click Run all tests.', 'output-empty'));
    else {
      addToolCard(output, `${state.tests.passed} passed · ${state.tests.failed} failed`, `${state.tests.results.length} files executed using real Luau WASM`, null);
      for (const result of state.tests.results) addToolCard(output, `${result.success ? '✓' : '✕'} ${result.file}`, result.output || result.error || 'Completed', () => openFile(result.file));
    }
  }
}
function setBusy(busy) { state.busy = busy; $('run-btn').disabled = busy; $('stop-btn').disabled = !busy; $('mobile-run').disabled = busy; }
function showRunError(error) { consoleLog(`Runtime: ${error instanceof Error ? error.message : String(error)}`, 'error'); $('runtime-indicator').textContent = '⚠ WASM error — check Console'; }
async function runCurrent() {
  if (state.busy) return;
  const token = ++state.runToken;
  workspace.flush(); setBusy(true); switchOutput('console'); consoleLog(`▶ Running ${workspace.project.active} with Luau WASM...`, 'system');
  try {
    const { result, elapsed } = await runtime.run({ ...workspace.project, files: { ...workspace.project.files } });
    if (token !== state.runToken) return;
    $('runtime-indicator').textContent = '● Luau WASM ready';
    const output = renderOutput(result);
    if (output) for (const line of output.split('\n')) consoleLog(line);
    if (result.success) consoleLog(`✓ Completed · Worker ${elapsed.toFixed(2)} ms (not a Roblox server benchmark)`, 'ok');
    else consoleLog(`✕ ${result.error || 'Unknown runtime failure'}`, 'error');
    for (const timing of result.requireTimings || []) consoleLog(`  require(${timing.module}): ${timing.milliseconds.toFixed(4)} ms [Luau VM clock]`, 'system');
  } catch (error) { if (token === state.runToken) showRunError(error); }
  finally { if (token === state.runToken) setBusy(false); }
}
function stopCurrent() { state.runToken++; runtime.stop(); setBusy(false); consoleLog('■ Script stopped; analysis worker remains available.', 'warn'); }
async function checkCurrent({ silent = false } = {}) {
  const generation = ++state.checking, revision = workspace.revision, filename = workspace.project.active;
  try {
    const { diagnostics } = await runtime.diagnostics({ ...workspace.project, files: { ...workspace.project.files } });
    if (generation !== state.checking || workspace.revision !== revision || workspace.project.active !== filename) return;
    state.problems = normalizeDiagnostics(diagnostics); $('problem-count').textContent = String(state.problems.length);
    if (state.output === 'problems') renderOutputPanel();
    if (!silent) { switchOutput('problems'); notify(state.problems.length ? `${state.problems.length} diagnostics` : 'No Luau diagnostics'); }
  } catch (error) { if (generation === state.checking && !silent) notify('Type check: ' + error.message, true); }
}
function liveDiagnostics() { clearTimeout(state.liveTimer); ++state.checking; if (state.liveCheck) state.liveTimer = setTimeout(() => checkCurrent({ silent: true }), 1200); }
async function bytecodeCurrent() {
  switchOutput('bytecode'); $('output-content').replaceChildren(createElement('div', 'Compiling Luau bytecode…', 'output-empty'));
  try { const { result } = await runtime.bytecode(workspace.project); state.bytecode = result.success ? result.bytecode : 'Compilation failed: ' + (result.error || 'Unknown error'); }
  catch (error) { state.bytecode = error.message; }
  renderOutputPanel();
}
function benchmarkPicker() {
  modal('Benchmark a ModuleScript', body => {
    body.append(createElement('p', 'Cold and cached require measurements are collected inside the Luau WASM VM with os.clock. For native Roblox-server timing, use the Studio benchmark script.', 'dialog-hint'));
    const choices = [ ...BUILTIN_LIBRARIES.map(x => ({ label: '@' + x.id + ' v' + x.version, value: '@' + x.id })), ...Object.keys(workspace.project.files).filter(x => x !== workspace.project.active).map(path => ({ label: path, value: path })) ];
    for (const choice of choices) body.append(clickButton(choice.label, () => { closeModal(); runModuleBenchmark(choice.value); }, 'dialog-row'));
  });
}
async function runModuleBenchmark(name) {
  if (state.busy) return;
  const token = ++state.runToken; setBusy(true); switchOutput('benchmarks');
  $('output-content').replaceChildren(createElement('div', 'Benchmarking ' + name + ' inside Luau WASM…', 'output-empty'));
  try { const result = await runtime.benchmarkModule(workspace.project, name); if (token === state.runToken) { state.bench = result; renderOutputPanel(); } }
  catch (error) { if (token === state.runToken) notify('Benchmark: ' + error.message, true); }
  finally { if (token === state.runToken) setBusy(false); }
}
async function runTests() {
  const files = findProjectTests(workspace.project);
  if (!files.length) { notify('Add a tests/*.luau or *.test.luau file first.', true); return; }
  if (state.busy) return;
  const token = ++state.runToken; setBusy(true); state.tests = { passed: 0, failed: 0, results: [] }; switchOutput('tests');
  for (const path of files) {
    if (token !== state.runToken) return;
    try {
      const project = { ...workspace.project, active: path, files: { ...workspace.project.files } };
      const { result } = await runtime.run(project);
      if (token !== state.runToken) return;
      state.tests.results.push({ file: path, success: result.success, output: renderOutput(result), error: result.error });
      state.tests[result.success ? 'passed' : 'failed']++;
    } catch (error) { if (token !== state.runToken) return; state.tests.failed++; state.tests.results.push({ file: path, success: false, error: error.message }); }
    renderOutputPanel();
  }
  if (token === state.runToken) { setBusy(false); notify(`${state.tests.passed} passed, ${state.tests.failed} failed`); }
}
function dependencyGraph() {
  const { nodes, edges, cycles, problems } = analyzeDependencies(workspace.project.files);
  modal('Module dependency graph', body => {
    body.append(createElement('p', `${nodes.length} workspace files · ${cycles.length} cycles · ${problems.length} unresolved paths. Edges are resolved by the same import resolver as Luau WASM.`, 'dialog-hint'));
    for (const file of nodes) {
      const node = createElement('div', undefined, 'tool-card');
      node.append(createElement('strong', file), createElement('p', (edges.get(file) || []).length ? (edges.get(file) || []).join(' → ') : 'No imports'));
      node.append(clickButton('Open', () => { closeModal(); openFile(file); })); body.append(node);
    }
    for (const cycle of cycles) body.append(createElement('p', '⚠ Circular require: ' + cycle.join(' → '), 'output-line error'));
    for (const item of problems) body.append(createElement('p', `⚠ ${item.file}: ${item.message}`, 'output-line error'));
  });
}
function openFind() { $('find-panel').classList.remove('hidden'); $('find-input').focus(); updateFindCount(); }
function updateFindCount() { const query = $('find-input').value; $('find-counter').textContent = query ? findMatches(editor.input.value, query).length + ' results' : '0 results'; }
function findNext() {
  const source = editor.input.value, q = $('find-input').value; if (!q) return;
  const indexes = findMatches(source, q); if (!indexes.length) return notify('No matches', true);
  const next = indexes.find(i => i > editor.input.selectionStart) ?? indexes[0]; editor.input.focus(); editor.input.setSelectionRange(next, next + q.length); updateCursor();
}
function replaceAll() {
  const { source, count } = replaceAllLiteral(editor.input.value, $('find-input').value, $('replace-input').value);
  if (count) editor.replace(0, editor.input.value.length, source, 0); notify(`Replaced ${count} occurrences`); updateFindCount();
}
function snapshotNow() { try { const snap = workspace.snapshot(); notify('Snapshot created: ' + new Date(snap.createdAt).toLocaleTimeString()); } catch (error) { notify(error.message, true); } }
function snapshotDialog() {
  modal('Restore a recovery snapshot', body => {
    const list = workspace.snapshots(); if (!list.length) return body.append(createElement('p', 'No snapshots saved yet. Create one in Settings first.', 'dialog-hint'));
    for (const item of list) body.append(clickButton(`${item.name} · ${new Date(item.createdAt).toLocaleString()}`, () => { try { workspace.restore(item.id); closeModal(); notify('Snapshot restored. A rollback snapshot was also saved.'); } catch (error) { notify(error.message, true); } }, 'dialog-row'));
  });
}
function exportProject() { const p = workspace.project; workspace.flush(); download((p.name.replace(/[^\w-]/g, '_') || 'luauforge') + '.json', projectToJSON(p), 'application/json'); }
function exportZip() { try { const p = workspace.project; download((p.name.replace(/[^\w-]/g, '_') || 'luauforge') + '.zip', makeZip(p.files), 'application/zip'); notify('Source ZIP exported'); } catch (error) { notify(error.message, true); } }
async function handleFiles(fileList) {
  for (const file of fileList) {
    try {
      if (file.size > 1_500_000) throw new Error('File is too large.');
      const raw = await file.text();
      if (file.name.toLowerCase().endsWith('.json')) {
        const data = JSON.parse(raw); const project = validateProject(data);
        workspace.snapshot(); workspace.replace(project); notify('Project imported from JSON');
      } else if (/\.(?:lua|luau|txt)$/i.test(file.name)) {
        const name = file.name.replace(/\.txt$/i, '.luau');
        if (Object.hasOwn(workspace.project.files, name)) promptModal('Replace file?', `${name} already exists. Type REPLACE to overwrite:`, '', answer => {
          if (answer !== 'REPLACE') return false;
          workspace.update(p => ({ ...p, files: { ...p.files, [name]: raw }, active: name }));
        });
        else workspace.create(name, raw);
      }
    } catch (error) { notify(`${file.name}: ${error.message}`, true); }
  }
}
function importGitHub() {
  promptModal('Import public GitHub source', 'Paste a public raw.githubusercontent.com URL to a .lua or .luau file. Private repositories and authenticated push require a separate secure integration.', '', async value => {
    try {
      const url = new URL(value);
      if (url.protocol !== 'https:' || url.hostname !== 'raw.githubusercontent.com' || !/\.lua(u)?$/i.test(url.pathname)) throw new Error('Use a public raw.githubusercontent.com .lua/.luau URL.');
      const response = await fetch(url.href, { signal: AbortSignal.timeout(12000) });
      if (!response.ok) throw new Error('GitHub returned HTTP ' + response.status);
      const text = await response.text(); if (text.length > 200_000) throw new Error('Source is larger than the workspace file cap.');
      const filename = url.pathname.split('/').at(-1);
      if (Object.hasOwn(workspace.project.files, filename)) throw new Error(`A file named ${filename} already exists.`);
      workspace.create(filename, text); closeModal(); notify('Imported ' + filename);
    } catch (error) { notify(error.message, true); }
    return false;
  });
}
function palette() {
  const commands = [
    ['Run current file', runCurrent], ['Stop execution', stopCurrent], ['Check types', () => checkCurrent()], ['Inspect bytecode', bytecodeCurrent],
    ['Find in file', openFind], ['Show file explorer', () => setSide('files')], ['Browse libraries', () => setSide('libraries')],
    ['Show symbols', () => setSide('symbols')], ['Dependency graph', dependencyGraph], ['Benchmark module', benchmarkPicker],
    ['Run project tests', runTests], ['Create snapshot', snapshotNow], ['Restore snapshot', snapshotDialog],
    ['Export JSON', exportProject], ['Export source ZIP', exportZip], ['New file', newFile], ['Rename file', renameCurrent],
    ['Delete file', deleteCurrent], ['Toggle theme', toggleTheme], ['Toggle word wrap', toggleWrap],
  ];
  modal('Command palette', body => {
    const input = createElement('input'); input.placeholder = 'Search commands or workspace files'; body.append(input);
    const results = createElement('div'); results.style.display = 'grid'; results.style.gap = '5px'; body.append(results);
    const render = () => {
      results.replaceChildren(); const q = input.value.toLowerCase();
      for (const [name, fn] of commands.filter(([label]) => label.toLowerCase().includes(q)).slice(0, 16)) results.append(clickButton(name, () => { closeModal(); fn(); }, 'dialog-row'));
      for (const path of Object.keys(workspace.project.files).filter(f => f.toLowerCase().includes(q)).slice(0, 12)) results.append(clickButton(path, () => { closeModal(); openFile(path); }, 'dialog-row'));
    };
    input.addEventListener('input', render); input.addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); results.querySelector('button')?.click(); } }); render(); input.focus();
  });
}
function newFile() { promptModal('New Luau file', 'Enter a relative path, e.g. modules/Currency.luau', 'modules/NewModule.luau', value => workspace.create(value, '--!strict\n\n')); }
function renameCurrent() { const previous = workspace.project.active; promptModal('Rename file', 'Enter a new relative filename:', previous, name => workspace.rename(previous, name)); }
function deleteCurrent() {
  const path = workspace.project.active;
  promptModal('Confirm deletion', `Type DELETE to permanently remove ${path}. Create a snapshot first if needed.`, '', answer => {
    if (answer !== 'DELETE') return false;
    workspace.snapshot(); workspace.remove(path); notify('Deleted ' + path);
  });
}
const templates = {
  script: ['scripts/NewScript.luau', `--!strict\nlocal message = "Hello, LuauForge!"\nprint(message)\n`],
  module: ['modules/NewModule.luau', `--!strict\nlocal Module = {}\n\nfunction Module.greet(name: string): string\n    return "Hello, " .. name\nend\n\nreturn Module\n`],
  test: ['tests/math.test.luau', `--!strict\nlocal Math = require("../modules/Math.luau")\nassert(Math.add(20, 22) == 42, "Expected 42")\nprint("PASS: Math.add")\n`],
  benchmark: ['examples/benchmark-v1.luau', `--!strict\nlocal iterations = 100000\nlocal start = os.clock()\nlocal sum = 0\nfor i = 1, iterations do\n    sum += i\nend\nprint("Iterations:", iterations)\nprint("Total:", sum)\nprint("CPU time (ms):", (os.clock() - start) * 1000)\n`],
};
function createTemplate(kind) {
  const [path, source] = templates[kind];
  const requested = Object.hasOwn(workspace.project.files, path) ? path.replace(/\.luau$/, '-' + Math.floor(Date.now() / 1000) + '.luau') : path;
  try { workspace.create(requested, source); closeMobile(); notify('Created ' + requested); } catch (error) { notify(error.message, true); }
}
function toggleWrap() { workspace.update({ wordWrap: !workspace.project.wordWrap }); $('code-input').style.whiteSpace = workspace.project.wordWrap ? 'pre-wrap' : 'pre'; editor.render(); }
function toggleTheme() { workspace.update({ theme: workspace.project.theme === 'dark' ? 'light' : 'dark' }); document.body.dataset.theme = workspace.project.theme; }
function resetLayout() { document.documentElement.style.setProperty('--sidebar-width', '266px'); document.documentElement.style.setProperty('--output-height', '202px'); workspace.update({ sidebarWidth: 266, outputHeight: 202, fontSize: 14 }); }
function enableResizing() {
  let pointer = null;
  const onDown = (kind, event) => { if (matchMedia('(max-width:820px)').matches) return; pointer = { kind, startX: event.clientX, startY: event.clientY, width: workspace.project.sidebarWidth, height: workspace.project.outputHeight }; event.target.setPointerCapture?.(event.pointerId); event.preventDefault(); };
  $('sidebar-resizer').addEventListener('pointerdown', event => onDown('sidebar', event));
  $('output-resizer').addEventListener('pointerdown', event => onDown('output', event));
  document.addEventListener('pointermove', event => {
    if (!pointer) return;
    if (pointer.kind === 'sidebar') document.documentElement.style.setProperty('--sidebar-width', Math.max(210, Math.min(400, pointer.width + event.clientX - pointer.startX)) + 'px');
    else document.documentElement.style.setProperty('--output-height', Math.max(110, Math.min(520, pointer.height + pointer.startY - event.clientY)) + 'px');
  });
  document.addEventListener('pointerup', event => {
    if (!pointer) return;
    const kind = pointer.kind; pointer = null;
    const value = parseInt(getComputedStyle(document.documentElement).getPropertyValue(kind === 'sidebar' ? '--sidebar-width' : '--output-height'), 10);
    if (Number.isFinite(value)) workspace.update(kind === 'sidebar' ? { sidebarWidth: value } : { outputHeight: value });
  });
}
function initialize() {
  document.body.dataset.theme = workspace.project.theme;
  document.documentElement.style.setProperty('--sidebar-width', workspace.project.sidebarWidth + 'px');
  document.documentElement.style.setProperty('--output-height', workspace.project.outputHeight + 'px');
  refresh(); setSide(state.side || 'files'); switchOutput(state.output || 'console');
  $('live-check').checked = state.liveCheck === true;
  $('run-btn').addEventListener('click', runCurrent); $('stop-btn').addEventListener('click', stopCurrent); $('mobile-run').addEventListener('click', runCurrent);
  $('check-btn').addEventListener('click', () => checkCurrent()); $('bytecode-btn').addEventListener('click', bytecodeCurrent);
  $('benchmark-btn').addEventListener('click', benchmarkPicker); $('test-btn').addEventListener('click', runTests); $('graph-btn').addEventListener('click', dependencyGraph);
  $('palette-btn').addEventListener('click', palette); $('outline-btn').addEventListener('click', () => { setSide('symbols'); openMobile('sidebar'); });
  $('theme-btn').addEventListener('click', toggleTheme); $('brand-home').addEventListener('click', palette); $('wrap-btn').addEventListener('click', toggleWrap);
  $('settings-btn').addEventListener('click', () => openMobile('inspector')); $('hide-inspector').addEventListener('click', () => { closeMobile(); $('inspector').classList.add('is-hidden'); });
  $('mode-select').addEventListener('change', event => workspace.update({ mode: event.target.value }));
  $('optimization-select').addEventListener('change', event => workspace.update({ optimization: Number(event.target.value) }));
  $('font-slider').addEventListener('input', event => workspace.update({ fontSize: Number(event.target.value) }));
  $('wrap-select').addEventListener('change', toggleWrap);
  $('live-check').addEventListener('change', event => { state.liveCheck = event.target.checked; preserveSettings(); if (state.liveCheck) liveDiagnostics(); });
  $('reset-layout').addEventListener('click', resetLayout);
  $('file-filter').addEventListener('input', renderFiles); $('library-filter').addEventListener('input', renderLibrary);
  $('new-file').addEventListener('click', newFile); $('import-file').addEventListener('click', () => $('file-picker').click());
  $('file-picker').addEventListener('change', event => { handleFiles([...event.target.files]); event.target.value = ''; });
  $('rename-project').addEventListener('click', () => promptModal('Rename workspace', 'Name your project:', workspace.project.name, name => workspace.update({ name })));
  $('snapshot-btn').addEventListener('click', snapshotNow); $('history-btn').addEventListener('click', snapshotDialog);
  $('export-json').addEventListener('click', exportProject); $('export-zip').addEventListener('click', exportZip); $('github-import').addEventListener('click', importGitHub);
  $('reset-project').addEventListener('click', () => promptModal('Reset project', 'Type RESET to restore default project files. A recovery snapshot will be saved.', '', value => value === 'RESET' ? workspace.reset() : false));
  for (const button of document.querySelectorAll('[data-side]')) button.addEventListener('click', () => setSide(button.dataset.side));
  for (const button of document.querySelectorAll('[data-output]')) button.addEventListener('click', () => switchOutput(button.dataset.output));
  for (const button of document.querySelectorAll('[data-template]')) button.addEventListener('click', () => createTemplate(button.dataset.template));
  $('find-btn').addEventListener('click', openFind); $('find-input').addEventListener('input', updateFindCount); $('find-input').addEventListener('keydown', event => { if (event.key === 'Enter') findNext(); });
  $('find-next').addEventListener('click', findNext); $('replace-all').addEventListener('click', replaceAll); $('find-close').addEventListener('click', () => $('find-panel').classList.add('hidden'));
  $('clear-output').addEventListener('click', () => { state.outputLogs = []; renderOutputPanel(); });
  $('mobile-files').addEventListener('click', () => { setSide('files'); openMobile('sidebar'); });
  $('mobile-library').addEventListener('click', () => { setSide('libraries'); openMobile('sidebar'); });
  $('mobile-tools').addEventListener('click', () => { switchOutput('benchmarks'); openMobile('inspector'); });
  $('mobile-settings').addEventListener('click', () => openMobile('inspector'));
  $('hide-sidebar').addEventListener('click', closeMobile); $('side-shade').addEventListener('click', closeMobile);
  $('dialog-close').addEventListener('click', closeModal); $('modal-backdrop').addEventListener('pointerdown', e => { if (e.target === $('modal-backdrop')) closeModal(); });
  $('code-undo').addEventListener('click', () => { editor.input.focus(); document.execCommand('undo'); });
  $('mobile-complete').addEventListener('click', () => { editor.input.focus(); editor.input.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true, ctrlKey: true, key: ' ' })); });
  for (const button of document.querySelectorAll('[data-insert]')) button.addEventListener('click', () => {
    const value = button.dataset.insert, start = editor.input.selectionStart, end = editor.input.selectionEnd;
    editor.replace(start, end, value, start + (value.length === 2 ? 1 : value.length));
  });
  document.addEventListener('keydown', event => { if (state.dialogs) return; if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'p') { event.preventDefault(); palette(); } if (event.key === 'Escape') closeMobile(); });
  window.addEventListener('pagehide', () => { workspace.dispose(); runtime.dispose(); state.disposed = true; });
  enableResizing();
  mountAutoRequire({ editor: editor.input, getProject: () => workspace.project, getRuntime: () => runtime, notify, catalogButtons: false });
  // Catalog actions are owned by v1. AutoRequire provides editor completions.
  renderLibrary();
  if (matchMedia('(max-width:1200px)').matches) $('inspector').classList.add('is-hidden');
  if ('serviceWorker' in navigator && location.protocol === 'https:') navigator.serviceWorker.register('./sw.js').catch(() => {});
  consoleLog('LuauForge v1.0 ready · Existing workspace restored.', 'system');
}
initialize();
