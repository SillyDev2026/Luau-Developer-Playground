import { createDefaultProject, loadProject, saveProject, validateProject, addFile, renameFile, deleteFile, normalizePath, countLines, formatBytes, projectSize, projectToJSON, FILE_SIZE_LIMIT, TOTAL_SIZE_LIMIT, STORAGE_KEY, LEGACY_STORAGE_KEY } from './store.js';
import { highlightLuau } from './highlight.js';
import { buildPlaygroundURL } from './runner.js';
import { findMatches, replaceAllLiteral, positionForLine, currentLineAndColumn, indentSelection } from './editor-utils.js';
import { listSnapshots, createSnapshot, restoreSnapshot, deleteSnapshot } from './snapshots.js';
import { LuauRuntime, normalizeDiagnostics, renderOutput } from './wasm-client.js?v=0.3.4';
import { summarizeSamples } from './module-bundle.js';
import { BUILTIN_LIBRARIES, builtinById } from './builtin-libraries.js';
import { mountAutoRequire } from './auto-require.js?v=0.4.0';
import { outlineSymbols } from './editor-intelligence.js?v=0.4.0';

const $ = id => document.getElementById(id);
let project = loadProject();
let toastTimer = 0;
let saveTimer = 0;
let fileReadBusy = false;
let findIndex = -1;
let commandItems = [];
let mobileDrawer = '';
let activeModal = '';
let previousFocus = null;
const luau = new LuauRuntime();
let outputView = 'console';
let checkSequence = 0;
let liveCheckTimer = 0;
const liveCheckKey = 'luauforge:live-check';
let liveCheckEnabled = false;
try { liveCheckEnabled = localStorage.getItem(liveCheckKey)==='true'; } catch {}
let executing = false;
let executionToken = 0;
const openedTabs = new Set([project.active]);
const collapsedFolders = new Set();
const editor = $('code-input');
const highlight = $('syntax-code');
const highlightLayer = $('syntax-layer');
const gutter = $('line-gutter');

function toast(message, warning = false) {
  const el = $('toast');
  el.textContent = message;
  el.className = `toast${warning ? ' warning' : ''}`;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.add('hidden'), 3700);
}

function consoleMessage(message, cls = 'system-line') {
  const element = document.createElement('p');
  element.className = cls;
  element.textContent = message;
  const output = $('console-content');
  output.appendChild(element);
  while (output.childElementCount > 120) output.firstElementChild.remove();
  output.scrollTop = output.scrollHeight;
}

function markPending() {
  $('save-status').textContent = 'Saving…';
  clearTimeout(saveTimer);
  saveTimer = setTimeout(persist, 400);
}

function persist() {
  clearTimeout(saveTimer);
  try {
    project = saveProject(project);
    $('save-status').textContent = '✓ Saved locally';
    return true;
  } catch (error) {
    $('save-status').textContent = '⚠ Not saved';
    toast(`Storage error: ${error.message}`, true);
    return false;
  }
}

function updateProject(next, options = {}) {
  try {
    const normalized = validateProject(next);
    const changed = normalized.active !== project.active;
    project = normalized;
    checkSequence++;
    if (changed) openedTabs.add(project.active);
    markPending();
    scheduleLiveCheck();
    renderAll(options);
    renderBenchmarkModules();
  } catch (error) { toast(error.message, true); }
}

function enterFile(path) {
  if (!Object.hasOwn(project.files, path)) return;
  project.active = path;
  openedTabs.add(path);
  renderAll();
  markPending();
  closeDrawer();
  editor.focus();
}

function setTitle() {
  $('project-title').textContent = project.name;
  $('project-folder').textContent = project.name.toUpperCase();
  $('breadcrumb-file').textContent = project.active;
  document.title = `${project.active} — LuauForge v0.4.0`;
}

function button(label, css, fn, title = '') {
  const item = document.createElement('button');
  item.className = css;
  item.type = 'button';
  item.textContent = label;
  if (title) item.title = title;
  item.addEventListener('click', fn);
  return item;
}

function renderFiles() {
  const tree = $('file-tree');
  tree.replaceChildren();
  const filter = $('file-filter').value.trim().toLowerCase();
  const sorted = Object.keys(project.files).sort((a, b) => a.localeCompare(b));
  const folders = new Set();
  let visible = 0;
  for (const path of sorted) {
    if (filter && !path.toLowerCase().includes(filter)) continue;
    const bits = path.split('/');
    for (let i = 0; i < bits.length - 1; i++) {
      const folder = bits.slice(0, i + 1).join('/');
      if (folders.has(folder)) continue;
      folders.add(folder);
      const toggler = button(`${collapsedFolders.has(folder) ? '▸' : '▾'}  ${bits[i]}`, 'folder-item', () => {
        if (collapsedFolders.has(folder)) collapsedFolders.delete(folder);
        else collapsedFolders.add(folder);
        renderFiles();
      }, folder);
      toggler.style.paddingLeft = `${11 + i * 12}px`;
      tree.append(toggler);
    }
    const hiddenByFolder = bits.slice(0, -1).some((_, i) => collapsedFolders.has(bits.slice(0, i + 1).join('/')));
    if (hiddenByFolder && !filter) continue;
    visible++;
    const row = button('', `file-item${project.active === path ? ' active' : ''}`, () => enterFile(path), path);
    row.style.paddingLeft = `${15 + (bits.length - 1) * 12}px`;
    const icon = document.createElement('span');
    icon.className = 'file-icon';
    icon.textContent = '◇';
    const label = document.createElement('span');
    label.className = 'file-label';
    label.textContent = bits.at(-1);
    row.append(icon, label);
    tree.append(row);
  }
  if (!visible && filter) {
    const msg = document.createElement('p');
    msg.className = 'no-files';
    msg.textContent = 'No matching files';
    tree.append(msg);
  }
}

function renderTabs() {
  const tabs = $('editor-tabs');
  tabs.replaceChildren();
  for (const path of [...openedTabs]) {
    if (!Object.hasOwn(project.files, path)) { openedTabs.delete(path); continue; }
    const tab = document.createElement('div');
    tab.className = `editor-tab${path === project.active ? ' selected' : ''}`;
    tab.setAttribute('role', 'tab');
    tab.setAttribute('aria-selected', String(path === project.active));
    tab.appendChild(button(`◇  ${path.split('/').at(-1)}`, 'tab-name', () => enterFile(path), path));
    if (openedTabs.size > 1) tab.appendChild(button('×', 'tab-close', () => {
      openedTabs.delete(path);
      if (project.active === path) enterFile([...openedTabs].at(-1) ?? Object.keys(project.files)[0]);
      else renderTabs();
    }, `Close ${path} tab`));
    tabs.append(tab);
  }
}

function escapeForHTML(value) { return value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;'); }
function syncScroll() {
  highlightLayer.scrollTop = editor.scrollTop;
  highlightLayer.scrollLeft = editor.scrollLeft;
  gutter.scrollTop = editor.scrollTop;
}
function updateCursor() {
  const { line, column } = currentLineAndColumn(editor.value, editor.selectionStart);
  $('cursor-position').textContent = `Ln ${line}, Col ${column}`;
}
function updateEditorDrawing() {
  const code = editor.value;
  const lines = countLines(code);
  highlight.innerHTML = code.length < 70000 ? highlightLuau(code) : escapeForHTML(code) + '\n';
  gutter.textContent = Array.from({ length: Math.min(lines, 3000) }, (_, i) => i + 1).join('\n') + (lines > 3000 ? '\n…' : '');
  $('line-count').textContent = `${lines.toLocaleString()} ${lines === 1 ? 'line' : 'lines'}`;
  $('file-size').textContent = formatBytes(new TextEncoder().encode(code).byteLength);
  updateCursor();
  syncScroll();
}

function renderStats() {
  $('stat-files').textContent = Object.keys(project.files).length;
  $('stat-lines').textContent = Object.values(project.files).reduce((sum, code) => sum + countLines(code), 0).toLocaleString();
  $('stat-size').textContent = formatBytes(projectSize(project));
}

function renderAll() {
  document.body.dataset.theme = project.theme;
  document.documentElement.style.colorScheme = project.theme;
  $('app').style.setProperty('--sidebar-width', `${project.sidebarWidth}px`);
  $('app').style.setProperty('--output-height', `${project.outputHeight}px`);
  $('app').style.setProperty('--editor-font', `${project.fontSize}px`);
  $('font-size-label').textContent = `${project.fontSize} px`;
  $('font-readout').textContent = `${project.fontSize}px`;
  setTitle();
  renderFiles();
  renderTabs();
  if (editor.dataset.path !== project.active || editor.value !== project.files[project.active]) {
    editor.value = project.files[project.active];
    editor.dataset.path = project.active;
    editor.scrollTop = 0;
    editor.scrollLeft = 0;
  }
  editor.setAttribute('wrap', project.wordWrap ? 'soft' : 'off');
  document.querySelector('.editor-section').classList.toggle('wrapped', project.wordWrap);
  $('wrap-toggle').textContent = `Wrap: ${project.wordWrap ? 'on' : 'off'}`;
  $('mode-select').value = project.mode;
  $('optimization-select').value = String(project.optimization);
  $('sidebar').classList.toggle('collapsed', !project.sidebarOpen && !mobileDrawer);
  $('inspector').classList.toggle('closed', !project.inspectorOpen);
  $('inspector-toggle').setAttribute('aria-expanded', String(project.inspectorOpen));
  updateDrawer();
  updateEditorDrawing();
  renderStats();
  if (!$('search-panel').classList.contains('hidden')) updateFindResults(false);
}

function insertAtCursor(value, cursorBack = 0) {
  const start = editor.selectionStart;
  const end = editor.selectionEnd;
  editor.setRangeText(value, start, end, 'end');
  editor.setSelectionRange(start + value.length - cursorBack, start + value.length - cursorBack);
  editor.dispatchEvent(new Event('input', { bubbles: true }));
}

function commitTextChange(value) {
  checkSequence++;
  const prospective = { ...project, files: { ...project.files, [project.active]: value } };
  try {
    const bytes = new TextEncoder().encode(value).byteLength;
    if (bytes > FILE_SIZE_LIMIT || projectSize(prospective) > TOTAL_SIZE_LIMIT) throw new Error('The source exceeds the local project size limit. Export or split your files.');
    project = prospective;
    markPending();
    scheduleLiveCheck();
    updateEditorDrawing();
    renderStats();
    if (!$('search-panel').classList.contains('hidden')) updateFindResults(false);
  } catch (error) {
    editor.value = project.files[project.active];
    updateEditorDrawing();
    toast(error.message, true);
  }
}

editor.addEventListener('input', () => commitTextChange(editor.value));
editor.addEventListener('scroll', syncScroll, { passive: true });
editor.addEventListener('click', updateCursor);
editor.addEventListener('keyup', updateCursor);
editor.addEventListener('keydown', event => {
  if (event.key === 'Tab') {
    event.preventDefault();
    if (event.shiftKey || editor.value.slice(editor.selectionStart, editor.selectionEnd).includes('\n')) {
      const result = indentSelection(editor.value, editor.selectionStart, editor.selectionEnd, event.shiftKey);
      editor.value = result.source;
      editor.setSelectionRange(result.start, result.end);
      editor.dispatchEvent(new Event('input', { bubbles: true }));
    } else insertAtCursor('    ');
  }
  if (event.key === 'Enter' && !event.shiftKey && !event.ctrlKey && !event.metaKey && editor.selectionStart === editor.selectionEnd) {
    const before = editor.value.slice(0, editor.selectionStart);
    const indent = before.split('\n').at(-1).match(/^\s*/)?.[0] ?? '';
    if (indent) { event.preventDefault(); insertAtCursor(`\n${indent}`); }
  }
});

const TEMPLATES = {
  basic: '--!strict\n\nprint("Hello from LuauForge!")\n',
  module: '--!strict\n\nlocal Module = {}\n\nfunction Module.hello(name: string): string\n    return `Hello, {name}!`\nend\n\nreturn Module\n',
  type: '--!strict\n\ntype Item = { name: string, amount: number }\n\nlocal function describe(item: Item): string\n    return `{item.name}: {item.amount}`\nend\n\nprint(describe({ name = "Coins", amount = 100 }))\n',
  benchmark: '--!strict\n\nlocal iterations = 100000\nlocal start = os.clock()\nlocal result = 0\nfor i = 1, iterations do\n    result += i\nend\nprint("Result:", result)\nprint("Elapsed:", os.clock() - start)\n',
  roblox: '--!strict\n-- Roblox ModuleScript template. Requires Roblox Studio to run.\n\nlocal Module = {}\n\nfunction Module.init(): ()\n    print("Module initialized")\nend\n\nreturn Module\n',
};
function askNewFile(template = 'basic') {
  const name = prompt('New Luau filename (folders supported)', `new-${Object.keys(project.files).length + 1}.luau`);
  if (name === null) return;
  try { updateProject(addFile(project, name, TEMPLATES[template] || TEMPLATES.basic)); toast(`Created ${normalizePath(name)}`); }
  catch (error) { toast(error.message, true); }
}
function renameActive() {
  const requested = prompt('Rename file', project.active);
  if (requested === null) return;
  try {
    const old = project.active;
    const next = renameFile(project, old, requested);
    if (openedTabs.has(old)) { openedTabs.delete(old); openedTabs.add(next.active); }
    updateProject(next);
    toast('File renamed.');
  } catch (error) { toast(error.message, true); }
}
function deleteActive() {
  if (!confirm(`Delete ${project.active}? Consider saving a snapshot first.`)) return;
  try { const old = project.active; updateProject(deleteFile(project, old)); openedTabs.delete(old); openedTabs.add(project.active); renderTabs(); toast('File deleted.'); }
  catch (error) { toast(error.message, true); }
}

function downloadFile(name, contents, mime) {
  const url = URL.createObjectURL(new Blob([contents], { type: mime }));
  const link = document.createElement('a');
  link.href = url;
  link.download = name;
  document.body.appendChild(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 5000);
}
function exportProject() {
  if (!persist()) return;
  downloadFile(`${project.name.replace(/[^a-z0-9_-]+/gi, '-').toLowerCase() || 'luau-workspace'}.json`, projectToJSON(project), 'application/json');
  toast('Workspace exported.');
}

async function importFiles(chosen) {
  if (fileReadBusy || !chosen.length) return;
  fileReadBusy = true;
  let candidate = project;
  let wasReplaced = false;
  try {
    for (const file of chosen) {
      if (file.size > 1000000) throw new Error(`${file.name} is too large to import.`);
      const contents = await file.text();
      if (file.name.toLowerCase().endsWith('.json')) {
        const parsed = validateProject(JSON.parse(contents));
        if (!confirm(`Replace current workspace with ${parsed.name}? Consider an export first.`)) continue;
        candidate = parsed;
        wasReplaced = true;
      } else if (/\.lua(u)?$/i.test(file.name)) {
        const name = normalizePath(file.name);
        if (Object.hasOwn(candidate.files, name)) {
          if (!confirm(`Replace existing file ${name}?`)) continue;
          candidate = validateProject({ ...candidate, files: { ...candidate.files, [name]: contents }, active: name });
        } else candidate = addFile(candidate, name, contents);
      } else throw new Error('Only .lua, .luau, and workspace .json files are accepted.');
    }
    if (wasReplaced) { openedTabs.clear(); openedTabs.add(candidate.active); collapsedFolders.clear(); }
    updateProject(candidate);
    toast('Import completed.');
  } catch (error) { toast(`Import failed: ${error.message}`, true); }
  finally { fileReadBusy = false; }
}

function closeDrawer() { mobileDrawer = ''; updateDrawer(); }
function updateDrawer() {
  const isSmall = matchMedia('(max-width: 820px)').matches;
  const inspectorOverlay = matchMedia('(max-width: 1199px)').matches;
  $('sidebar').classList.toggle('mobile-visible', mobileDrawer === 'sidebar' && isSmall);
  $('inspector').classList.toggle('drawer-visible', mobileDrawer === 'inspector' && inspectorOverlay);
  $('drawer-overlay').classList.toggle('hidden', !((isSmall && mobileDrawer === 'sidebar') || (inspectorOverlay && mobileDrawer === 'inspector')));
}
function openDrawer(type) { mobileDrawer = mobileDrawer === type ? '' : type; updateDrawer(); }
function toggleInspector() {
  if (matchMedia('(max-width: 1199px)').matches) openDrawer('inspector');
  else updateProject({ ...project, inspectorOpen: !project.inspectorOpen });
}
function toggleSidebar() {
  if (matchMedia('(max-width: 820px)').matches) openDrawer('sidebar');
  else updateProject({ ...project, sidebarOpen: !project.sidebarOpen });
}

function openModal(id, focusId) {
  if (activeModal) closeModal(activeModal);
  previousFocus = document.activeElement;
  activeModal = id;
  $(id).classList.remove('hidden');
  document.body.classList.add('modal-open');
  if (focusId) $(focusId).focus();
}
function closeModal(id) {
  if (id === 'runner-modal') {
    $('runner-frame-container').replaceChildren();
    $('output-indicator').textContent = 'READY';
  }
  $(id).classList.add('hidden');
  activeModal = '';
  document.body.classList.remove('modal-open');
  if (previousFocus && typeof previousFocus.focus === 'function') previousFocus.focus();
}
function showRunner() {
  persist();
  const holder = $('runner-frame-container');
  holder.replaceChildren();
  let url = 'https://play.luau.org/';
  try {
    const fullURL = buildPlaygroundURL(project);
    if (fullURL.length < 24000) url = fullURL;
    else {
      const activeOnly = buildPlaygroundURL({ ...project, files: { 'main.luau': project.files[project.active] }, active: 'main.luau' });
      if (activeOnly.length < 24000) {
        url = activeOnly;
        consoleMessage('Project is large; the runner loaded only the active source.', 'notice-line');
      } else {
        consoleMessage('Source is too large to preload into the runner URL.', 'notice-line');
        toast('Source is too large for the runner share URL.', true);
      }
    }
  } catch (error) {
    consoleMessage(`Runner share codec unavailable: ${error.message}`, 'error-line');
    toast('Unable to preload code. The official runner can still be opened.', true);
  }
  $('runner-external').href = url.replace('embed=true&', '');
  const iframe = document.createElement('iframe');
  iframe.title = 'Official Luau Playground runner';
  iframe.src = url;
  iframe.loading = 'eager';
  iframe.referrerPolicy = 'no-referrer';
  iframe.allow = 'clipboard-write';
  holder.append(iframe);
  $('output-indicator').textContent = 'OFFICIAL';
  consoleMessage(`Opened ${project.active} in the official Playground. Execution output stays in that window.`);
  openModal('runner-modal', 'runner-close');
}


function setOutputView(next) {
  outputView = next;
  $('console-content').hidden = next !== 'console';
  $('diagnostics-list').hidden = next !== 'diagnostics';
  $('bytecode-view').hidden = next !== 'bytecode';
  $('diagnostics-btn').classList.toggle('selected-tool', next === 'diagnostics');
  $('bytecode-btn').classList.toggle('selected-tool', next === 'bytecode');
}
function setExecuting(value) {
  executing = value;
  $('run-btn').disabled = value;
  $('stop-btn').disabled = !value;
  $('mobile-run').disabled = value;
  $('benchmark-module-btn').disabled = value;
  $('output-indicator').textContent = value ? 'RUNNING' : 'READY';
}
async function runLocal() {
  if (executing) return;
  setOutputView('console');
  const token = ++executionToken;
  setExecuting(true);
  consoleMessage(`▶ Running ${project.active} with Luau WASM…`, 'notice-line');
  try {
    const current = project;
    const { result, elapsed } = await luau.run(current);
    if (result.output || result.prints) {
      const output = renderOutput(result);
      for (const line of output.slice(0, 50000).split('\n')) consoleMessage(line);
      if (output.length > 50000) consoleMessage('Output truncated to 50 KB.', 'notice-line');
    }
    if (result.requireTimings?.length) {
      const seen = new Set();
      for (const item of result.requireTimings) {
        const cached = seen.has(item.module);
        seen.add(item.module);
        consoleMessage(`↳ require ${item.module} — ${item.milliseconds.toFixed(4)} ms (${cached ? 'cached' : 'first load'}, Luau VM CPU)`, 'notice-line');
      }
    }
    if (result.error) consoleMessage(`Error: ${result.error}`, 'error-line');
    if (result.success) consoleMessage(`✓ Completed in ${elapsed.toFixed(2)} ms (browser WASM).`, 'system-line');
    else if (!result.error) consoleMessage('Execution did not complete successfully.', 'error-line');
  } catch (error) {
    if (error.message === 'Execution stopped') return;
    consoleMessage(`Runtime: ${error.message}`, 'error-line');
    toast(`Luau runtime: ${error.message}`, true);
  } finally { if (executionToken === token) setExecuting(false); }
}
async function benchmarkModule() {
  if (executing) return;
  const target = $('benchmark-module').value;
  if (!target || !(target.startsWith('@') ? builtinById(target.slice(1)) : Object.hasOwn(project.files, target))) { toast('Select a valid module to benchmark.', true); return; }
  const token = ++executionToken;
  setOutputView('console');
  setExecuting(true);
  consoleMessage(`⚡ Benchmarking require(${target}) in Luau WASM (12 fresh VMs)…`, 'notice-line');
  try {
    const result = await luau.benchmarkModule({ ...project, files: { ...project.files } }, target);
    const cold = summarizeSamples(result.samples.map(x => x.coldMs));
    const cached = summarizeSamples(result.samples.map(x => x.cachedMs));
    const fmt = value => value === null ? 'n/a' : `${value.toFixed(4)} ms`;
    consoleMessage(`✓ ${result.module} — ${cold.samples} cold loads; first require median: ${fmt(cold.medianMs)} (min ${fmt(cold.minMs)}, max ${fmt(cold.maxMs)})`, 'system-line');
    consoleMessage(`↳ Cached require median: ${fmt(cached.medianMs)} (min ${fmt(cached.minMs)}, max ${fmt(cached.maxMs)})`, 'system-line');
    consoleMessage(`Clock: ${result.runtime}. Excludes frontend rendering and network; not a Roblox server benchmark.`, 'notice-line');
  } catch (error) {
    if (error.message !== 'Execution stopped') {
      consoleMessage(`Benchmark: ${error.message}`, 'error-line');
      toast(error.message, true);
    }
  } finally { if (executionToken === token) setExecuting(false); }
}
function renderBuiltinCatalog() {
  const container = $('builtin-catalog');
  container.replaceChildren();
  for (const lib of BUILTIN_LIBRARIES) {
    const item = document.createElement('div');
    item.className = 'builtin-catalog-item';
    const heading = document.createElement('div');
    heading.className = 'builtin-catalog-heading';
    const name = document.createElement('strong');
    name.textContent = lib.label;
    const version = document.createElement('span');
    version.textContent = `v${lib.version}`;
    heading.append(name, version);
    const summary = document.createElement('p');
    summary.textContent = lib.description;
    const actions = document.createElement('div');
    actions.className = 'builtin-catalog-actions';
    actions.append(
      button('Example', 'tiny-btn', () => createBuiltinExample(lib.id), `Create ${lib.label} example`),
      button('API', 'tiny-btn', () => openBuiltinDocs(lib.id), `View ${lib.label} APIs`),
    );
    item.append(heading, summary, actions);
    container.append(item);
  }
}
function createBuiltinExample(id) {
  const lib = builtinById(id);
  if (!lib) return;
  const path = `examples/${id}.luau`;
  if (Object.hasOwn(project.files, path)) { enterFile(path); toast(`Opened existing ${path}.`); return; }
  try {
    updateProject(addFile(project, path, lib.example));
    closeDrawer();
    toast(`Created ${path}. Run it with Ctrl+Enter.`);
  } catch (error) { toast(error.message, true); }
}
function openBuiltinDocs(id) {
  const lib = builtinById(id);
  if (!lib) return;
  $('builtin-title').textContent = `${lib.label} API — v${lib.version}`;
  $('builtin-summary').textContent = lib.description;
  $('builtin-repository').href = lib.repository;
  $('builtin-require').textContent = `local ${lib.local} = require("@${lib.id}")`;
  const list = $('builtin-methods');
  list.replaceChildren();
  for (const category of lib.categories) {
    const group = document.createElement('section');
    const title = document.createElement('h3');
    title.textContent = category.name;
    group.append(title);
    for (const method of category.methods) {
      const row = button(`${lib.local}.${method}`, 'builtin-api-method', () => {
        insertAtCursor(`${lib.local}.${method.slice(0, method.indexOf('('))}(`);
        closeModal('builtin-modal');
      }, 'Insert method name in editor');
      group.append(row);
    }
    list.append(group);
  }
  $('builtin-create-example').onclick = () => { closeModal('builtin-modal'); createBuiltinExample(id); };
  $('builtin-insert-require').onclick = () => { closeModal('builtin-modal'); insertAtCursor(`local ${lib.local} = require("@${lib.id}")\n`); editor.focus(); };
  $('builtin-inspect').onclick = () => {
    closeModal('builtin-modal');
    const code = `local ${lib.local} = require("@${lib.id}")\nlocal methods = {}\nfor name, value in pairs(${lib.local}) do\n    if type(value) == "function" then table.insert(methods, name) end\nend\ntable.sort(methods)\nfor _, name in ipairs(methods) do print(name) end\n`;
    const path = `examples/${id}-api.luau`;
    if (Object.hasOwn(project.files, path)) { enterFile(path); toast('API inspector already exists.'); return; }
    try { updateProject(addFile(project, path, code)); closeDrawer(); } catch (error) { toast(error.message, true); }
  };
  openModal('builtin-modal', 'builtin-create-example');
}
function renderBenchmarkModules() {
  const select = $('benchmark-module');
  const before = select.value;
  const options = Object.keys(project.files).filter(name => !/^(main|examples\/benchmark)\.luau$/i.test(name));
  const names = [...BUILTIN_LIBRARIES.map(lib => `@${lib.id}`), ...(options.length ? options : Object.keys(project.files).filter(name => name !== project.active))];
  select.replaceChildren();
  for (const name of names) {
    const option = document.createElement('option');
    option.value = name;
    option.textContent = name;
    select.append(option);
  }
  if (names.includes(before)) select.value = before;
  select.disabled = !names.length;
}
function stopLocal() {
  if (!executing) return;
  executionToken++;
  luau.stop();
  setExecuting(false);
  consoleMessage('■ Execution stopped. Analyzer remains available.', 'notice-line');
}
function setLiveCheckStatus(label,errors=0){
  const badge=$('live-check-status');
  badge.textContent=label;
  badge.classList.toggle('live-error',errors>0);
  badge.title='Show Luau diagnostics';
}
function scheduleLiveCheck(){
  clearTimeout(liveCheckTimer);
  ++checkSequence;
  if(!liveCheckEnabled){setLiveCheckStatus('CHECK OFF');return;}
  const active=project.active,source=project.files[active];
  if(source.length>100000){setLiveCheckStatus('CHECK MANUALLY');return;}
  setLiveCheckStatus('CHECK PENDING');
  const serial=checkSequence;
  liveCheckTimer=setTimeout(async()=>{
    if(serial!==checkSequence||active!==project.active)return;
    try{
      const snapshot={...project,files:{...project.files}};
      const {diagnostics}=await luau.diagnostics(snapshot);
      if(serial!==checkSequence||active!==project.active||project.files[active]!==source)return;
      const relevant=normalizeDiagnostics(diagnostics).filter(item=>item.module===active||item.module==='main'||!item.module);
      const errors=relevant.filter(item=>item.severity==='error').length;
      const warnings=relevant.filter(item=>item.severity==='warning').length;
      setLiveCheckStatus(`${errors} ERR · ${warnings} WARN`,errors);
    }catch(error){if(serial===checkSequence)setLiveCheckStatus('CHECK FAILED');}
  },1500);
}
async function checkLocal() {
  const serial = ++checkSequence;
  const active = project.active;
  const snapshot = { ...project, files: { ...project.files } };
  setOutputView('diagnostics');
  const list = $('diagnostics-list');
  list.replaceChildren();
  list.append('Checking Luau types…');
  try {
    const { diagnostics, elapsed } = await luau.diagnostics(snapshot);
    if (serial !== checkSequence || active !== project.active || snapshot.files[active] !== project.files[active]) return;
    list.replaceChildren();
    const relevant = normalizeDiagnostics(diagnostics).filter(item => item.module === 'main' || item.module === active || !item.module);
    $('output-indicator').textContent = `${relevant.filter(item => item.severity === 'error').length} ERRORS`;
    if (!relevant.length) list.append(`✓ No diagnostics (${elapsed.toFixed(1)} ms)`);
    for (const item of relevant.slice(0, 150)) {
      const row = button(`${item.severity.toUpperCase()} · ${item.line}:${item.column} · ${item.message}`, `diagnostic-row ${item.severity}`, () => {
        const position = positionForLine(editor.value, item.line) + item.column - 1;
        editor.focus();
        editor.setSelectionRange(position, position);
        editor.scrollTop = Math.max(0, (item.line - 5) * project.fontSize * 1.78);
      });
      list.append(row);
    }
  } catch (error) {
    if (serial !== checkSequence || active !== project.active) return;
    list.replaceChildren();
    list.append(`Analysis error: ${error.message}`);
    toast(error.message, true);
  }
}
async function showBytecode() {
  setOutputView('bytecode');
  const pane = $('bytecode-view');
  pane.textContent = 'Compiling bytecode…';
  try {
    const { result, elapsed } = await luau.bytecode(project);
    pane.textContent = result.bytecode || result.error || JSON.stringify(result, null, 2);
    $('output-indicator').textContent = `O${project.optimization} · ${elapsed.toFixed(0)} MS`;
  } catch (error) { pane.textContent = `Bytecode error: ${error.message}`; toast(error.message, true); }
}

function showSearch() {
  $('search-panel').classList.remove('hidden');
  $('find-input').focus();
  $('find-input').select();
  updateFindResults(false);
}
function closeSearch() { $('search-panel').classList.add('hidden'); editor.focus(); }
function updateFindResults(selectFirst = false) {
  const matches = findMatches(editor.value, $('find-input').value, $('case-sensitive').checked);
  if (!matches.length) findIndex = -1;
  else if (selectFirst || findIndex >= matches.length) findIndex = -1;
  $('search-count').textContent = `${matches.length}${matches.length >= 10000 ? '+' : ''} ${matches.length === 1 ? 'match' : 'matches'}`;
  return matches;
}
function stepFind(direction = 1) {
  const matches = updateFindResults(false);
  if (!matches.length) return;
  findIndex = (findIndex + direction + matches.length) % matches.length;
  editor.focus();
  editor.setSelectionRange(matches[findIndex], matches[findIndex] + $('find-input').value.length);
  updateCursor();
}
function replaceCurrent() {
  const query = $('find-input').value;
  const matches = updateFindResults(false);
  if (!matches.length) return;
  const current = matches[Math.max(0, findIndex)];
  const replacement = $('replace-input').value;
  editor.setRangeText(replacement, current, current + query.length, 'end');
  editor.dispatchEvent(new Event('input', { bubbles: true }));
  updateFindResults(true);
  editor.focus();
}
function replaceAll() {
  const result = replaceAllLiteral(editor.value, $('find-input').value, $('replace-input').value, $('case-sensitive').checked);
  if (result.count) {
    editor.value = result.source;
    editor.dispatchEvent(new Event('input', { bubbles: true }));
    toast(`Replaced ${result.count} ${result.count === 1 ? 'match' : 'matches'}.`);
  }
}
function goToLine() {
  const raw = prompt('Go to line number', String(currentLineAndColumn(editor.value, editor.selectionStart).line));
  if (raw === null) return;
  const number = Number(raw);
  if (!Number.isFinite(number) || number < 1) { toast('Enter a valid line number.', true); return; }
  const position = positionForLine(editor.value, number);
  editor.focus();
  editor.setSelectionRange(position, position);
  updateCursor();
  const lineHeight = project.fontSize * 1.78;
  editor.scrollTop = Math.max(0, (Math.floor(number) - 5) * lineHeight);
}

function renderSnapshots() {
  const root = $('snapshot-list');
  root.replaceChildren();
  const snapshots = listSnapshots();
  if (!snapshots.length) {
    const empty = document.createElement('p');
    empty.className = 'empty-snapshots';
    empty.textContent = 'No snapshots yet. Save a recovery point before major changes.';
    root.append(empty);
  }
  for (const item of snapshots) {
    const row = document.createElement('div');
    row.className = 'snapshot-item';
    const info = document.createElement('div');
    const label = document.createElement('strong');
    label.textContent = item.name;
    const date = document.createElement('small');
    date.textContent = new Date(item.createdAt).toLocaleString();
    info.append(label, date);
    row.append(info);
    row.append(button('Restore', 'quiet-btn', () => {
      if (!confirm(`Restore snapshot ${new Date(item.createdAt).toLocaleString()}? Current unsaved edits will be overwritten.`)) return;
      try {
        const restored = restoreSnapshot(item.id);
        openedTabs.clear();
        openedTabs.add(restored.active);
        updateProject(restored);
        closeModal('snapshot-modal');
        toast('Snapshot restored.');
      } catch (error) { toast(error.message, true); }
    }, 'Restore snapshot'));
    row.append(button('×', 'tiny-btn', () => { deleteSnapshot(item.id); renderSnapshots(); }, 'Delete snapshot'));
    root.append(row);
  }
}
function openSnapshots() { renderSnapshots(); openModal('snapshot-modal', 'create-snapshot'); }

function buildCommands(query = '') {
  const commands = [
    ...outlineSymbols(editor.value).map(symbol=>({label:`${symbol.kind} ${symbol.name} — line ${symbol.line}`,action:()=>jumpToSymbol(symbol)})),
    { label: 'Run Luau in browser WebAssembly', action: runLocal },
    { label: 'Stop Luau execution', action: stopLocal },
    { label: 'Check Luau types', action: checkLocal },
    { label: 'Inspect Luau bytecode', action: showBytecode },
    { label: 'Benchmark module require using Luau VM', action: benchmarkModule },
    { label: 'Open official Playground', action: showRunner },
    { label: 'New Luau file', action: () => askNewFile() },
    { label: 'Find and replace', action: showSearch },
    { label: 'Go to line', action: goToLine },
    { label: 'Project snapshots', action: openSnapshots },
    { label: 'Export workspace', action: exportProject },
    { label: 'Toggle word wrap', action: () => updateProject({ ...project, wordWrap: !project.wordWrap }) },
    { label: 'Toggle theme', action: () => updateProject({ ...project, theme: project.theme === 'dark' ? 'light' : 'dark' }) },
    ...Object.keys(project.files).map(path => ({ label: `Open ${path}`, action: () => enterFile(path) })),
  ];
  commandItems = commands.filter(item => item.label.toLowerCase().includes(query.toLowerCase())).slice(0, 30);
  const root = $('command-results');
  root.replaceChildren();
  for (const item of commandItems) root.append(button(item.label, 'command-option', () => { closeModal('command-modal'); item.action(); }));
  if (!commandItems.length) { const empty = document.createElement('p'); empty.textContent = 'No commands found.'; root.append(empty); }
}
function jumpToSymbol(symbol){
  editor.focus();editor.setSelectionRange(symbol.position,symbol.position+symbol.name.length);
  editor.scrollTop=Math.max(0,(symbol.line-5)*(project.fontSize*1.7));updateCursor();
}
function openSymbols(){
  $('command-input').value='';
  const entries=outlineSymbols(editor.value);
  commandItems=entries.map(symbol=>({label:`${symbol.kind} ${symbol.name} — line ${symbol.line}`,action:()=>jumpToSymbol(symbol)}));
  const root=$('command-results');root.replaceChildren();
  if(!entries.length)root.textContent='No symbols in this file yet.';
  for(const item of commandItems)root.append(button(item.label,'command-option',()=>{closeModal('command-modal');item.action();}));
  openModal('command-modal','command-input');
}
function openCommands() { $('command-input').value = ''; buildCommands(); openModal('command-modal', 'command-input'); }

function setEditorFont(delta) { updateProject({ ...project, fontSize: project.fontSize + delta }); }
function resetLayout() { updateProject({ ...project, sidebarWidth: 258, outputHeight: 202, fontSize: 13, sidebarOpen: true, inspectorOpen: true }); toast('Layout sizes reset.'); }

function wireResizer(element, axis, onResize) {
  let initial = 0;
  let size = 0;
  let dragging = false;
  element.addEventListener('pointerdown', event => {
    if (event.button !== 0 || matchMedia('(max-width: 820px)').matches && axis === 'x') return;
    initial = axis === 'x' ? event.clientX : event.clientY;
    size = axis === 'x' ? project.sidebarWidth : project.outputHeight;
    dragging = true;
    element.setPointerCapture(event.pointerId);
    document.body.classList.add('resizing');
  });
  element.addEventListener('pointermove', event => {
    if (!dragging) return;
    const difference = (axis === 'x' ? event.clientX : -event.clientY) - (axis === 'x' ? initial : -initial);
    onResize(size + difference);
  });
  const stop = () => {
    if (!dragging) return;
    dragging = false;
    document.body.classList.remove('resizing');
    markPending();
  };
  element.addEventListener('pointerup', stop);
  element.addEventListener('pointercancel', stop);
  element.addEventListener('keydown', event => {
    if (!['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown'].includes(event.key)) return;
    event.preventDefault();
    const sign = axis === 'x' ? event.key === 'ArrowRight' ? 1 : -1 : event.key === 'ArrowUp' ? 1 : -1;
    onResize((axis === 'x' ? project.sidebarWidth : project.outputHeight) + sign * 16);
    markPending();
  });
}
wireResizer($('sidebar-resizer'), 'x', width => {
  project.sidebarWidth = Math.max(205, Math.min(430, Math.round(width)));
  $('app').style.setProperty('--sidebar-width', `${project.sidebarWidth}px`);
});
wireResizer($('output-resizer'), 'y', height => {
  project.outputHeight = Math.max(105, Math.min(Math.floor(window.innerHeight * 0.52), Math.round(height)));
  $('app').style.setProperty('--output-height', `${project.outputHeight}px`);
});

$('add-file').addEventListener('click', () => askNewFile());
document.querySelectorAll('[data-template]').forEach(item => item.addEventListener('click', () => askNewFile(item.dataset.template)));
renderBuiltinCatalog();
$('file-filter').addEventListener('input', renderFiles);
$('rename-file').addEventListener('click', renameActive);
$('delete-file').addEventListener('click', deleteActive);
$('rename-project').addEventListener('click', () => { const name = prompt('Workspace name', project.name); if (name !== null && name.trim()) updateProject({ ...project, name: name.trim() }); });
$('download-file').addEventListener('click', () => downloadFile(project.active.split('/').at(-1), project.files[project.active], 'text/plain'));
$('copy-file').addEventListener('click', async () => { try { await navigator.clipboard.writeText(editor.value); toast('File copied to clipboard.'); } catch { toast('Clipboard access unavailable. Select the source and copy it manually.', true); } });
$('export-btn').addEventListener('click', exportProject);
$('mobile-export').addEventListener('click', exportProject);
$('import-btn').addEventListener('click', () => $('import-input').click());
$('import-input').addEventListener('change', async event => { await importFiles([...event.target.files]); event.target.value = ''; });
$('clear-console').addEventListener('click', () => { $('console-content').replaceChildren(); $('diagnostics-list').replaceChildren(); $('bytecode-view').textContent = ''; setOutputView('console'); consoleMessage('Console cleared.'); });
$('stop-btn').addEventListener('click', stopLocal);
$('diagnostics-btn').addEventListener('click', checkLocal);
$('live-check-status').addEventListener('click',checkLocal);
$('live-check-toggle').checked=liveCheckEnabled;
$('live-check-toggle').addEventListener('change',event=>{liveCheckEnabled=event.target.checked;try{localStorage.setItem(liveCheckKey,String(liveCheckEnabled));}catch{}scheduleLiveCheck();});
$('bytecode-btn').addEventListener('click', showBytecode);
$('mode-select').addEventListener('change', event => updateProject({ ...project, mode: event.target.value }));
$('optimization-select').addEventListener('change', event => updateProject({ ...project, optimization: Number(event.target.value) }));
$('wrap-toggle').addEventListener('click', () => updateProject({ ...project, wordWrap: !project.wordWrap }));
$('theme-toggle').addEventListener('click', () => updateProject({ ...project, theme: project.theme === 'dark' ? 'light' : 'dark' }));
$('sidebar-toggle').addEventListener('click', toggleSidebar);
$('sidebar-close').addEventListener('click', closeDrawer);
$('mobile-files').addEventListener('click', toggleSidebar);
$('inspector-toggle').addEventListener('click', toggleInspector);
$('mobile-settings').addEventListener('click', toggleInspector);
$('inspector-close').addEventListener('click', () => matchMedia('(max-width: 1199px)').matches ? closeDrawer() : updateProject({ ...project, inspectorOpen: false }));
$('drawer-overlay').addEventListener('click', closeDrawer);
window.addEventListener('resize', updateDrawer);
$('run-btn').addEventListener('click', runLocal);
$('benchmark-module-btn').addEventListener('click', benchmarkModule);
$('mobile-run').addEventListener('click', runLocal);
$('expand-runner').addEventListener('click', showRunner);
$('runner-close').addEventListener('click', () => closeModal('runner-modal'));
$('snapshot-btn').addEventListener('click', openSnapshots);
$('create-snapshot').addEventListener('click', () => { try { persist(); createSnapshot(project); renderSnapshots(); toast('Snapshot saved.'); } catch (error) { toast(error.message, true); } });
$('snapshots-close').addEventListener('click', () => closeModal('snapshot-modal'));
$('search-toggle').addEventListener('click', showSearch);
$('mobile-find').addEventListener('click', showSearch);
$('search-close').addEventListener('click', closeSearch);
$('find-input').addEventListener('input', () => updateFindResults(true));
$('case-sensitive').addEventListener('change', () => updateFindResults(true));
$('find-next').addEventListener('click', () => stepFind(1));
$('find-prev').addEventListener('click', () => stepFind(-1));
$('replace-one').addEventListener('click', replaceCurrent);
$('replace-all').addEventListener('click', replaceAll);
$('go-line').addEventListener('click', goToLine);
$('font-minus').addEventListener('click', () => setEditorFont(-1));
$('font-plus').addEventListener('click', () => setEditorFont(1));
$('reset-layout').addEventListener('click', resetLayout);
$('command-open').addEventListener('click', openCommands);
$('symbol-outline').addEventListener('click',openSymbols);
$('command-input').addEventListener('input', event => buildCommands(event.target.value));
$('command-input').addEventListener('keydown', event => { if (event.key === 'Enter' && commandItems.length) { event.preventDefault(); const item = commandItems[0]; closeModal('command-modal'); item.action(); } });
$('find-input').addEventListener('keydown', event => { if (event.key === 'Enter') { event.preventDefault(); stepFind(event.shiftKey ? -1 : 1); } });
$('builtin-close').addEventListener('click', () => closeModal('builtin-modal'));
for (const id of ['runner-modal', 'command-modal', 'snapshot-modal', 'builtin-modal']) $(id).addEventListener('click', event => { if (event.target === $(id)) closeModal(id); });

document.addEventListener('keydown', event => {
  const cmd = event.ctrlKey || event.metaKey;
  const key = event.key.toLowerCase();
  if (cmd && key === 's') { event.preventDefault(); if (persist()) toast('Workspace saved locally.'); }
  else if (cmd && event.key === 'Enter') { event.preventDefault(); runLocal(); }
  else if (cmd && event.shiftKey && key === 'b') { event.preventDefault(); checkLocal(); }
  else if (cmd && key === 'f') { event.preventDefault(); showSearch(); }
  else if (cmd && key === 'p') { event.preventDefault(); openCommands(); }
  else if (cmd && event.shiftKey && key==='o'){event.preventDefault();openSymbols();}
  else if (cmd && key === 'g') { event.preventDefault(); goToLine(); }
  else if (event.key === '/' && !activeModal && !['INPUT', 'TEXTAREA'].includes(document.activeElement.tagName)) { event.preventDefault(); $('file-filter').focus(); }
  else if (event.key === 'Escape') {
    if (activeModal) closeModal(activeModal);
    else if (!$('search-panel').classList.contains('hidden')) closeSearch();
    else closeDrawer();
  }
});
window.addEventListener('pagehide', () => { if (saveTimer) persist(); luau.dispose(); });
window.addEventListener('storage', event => { if ([STORAGE_KEY, LEGACY_STORAGE_KEY].includes(event.key)) toast('Workspace changed in another tab. Export changes before reloading.', true); });

let dragCounter = 0;
const editorSection = document.querySelector('.editor-section');
editorSection.addEventListener('dragenter', event => { if (!event.dataTransfer?.types.includes('Files')) return; dragCounter++; event.preventDefault(); $('drop-indicator').classList.remove('hidden'); });
editorSection.addEventListener('dragover', event => { if (event.dataTransfer?.types.includes('Files')) event.preventDefault(); });
editorSection.addEventListener('dragleave', () => { dragCounter--; if (dragCounter <= 0) { dragCounter = 0; $('drop-indicator').classList.add('hidden'); } });
editorSection.addEventListener('drop', async event => { event.preventDefault(); dragCounter = 0; $('drop-indicator').classList.add('hidden'); await importFiles([...event.dataTransfer.files]); });

renderAll();
setOutputView('console');
renderBenchmarkModules();
mountAutoRequire({editor,getProject:()=>project,getRuntime:()=>luau,notify:toast});
if(liveCheckEnabled)scheduleLiveCheck();
consoleMessage('LuauForge v0.4.0 loaded. Ctrl+Enter runs locally in the Luau WASM engine; Ctrl+Shift+B checks types.');
