import { createDefaultProject, loadProject, saveProject, validateProject, addFile, renameFile, deleteFile, normalizePath, countLines, formatBytes, projectSize, projectToJSON } from './store.js';
import { highlightLuau } from './highlight.js';
import { buildPlaygroundURL } from './runner.js';

const $ = id => document.getElementById(id);
let project = loadProject();
let toastTimer = 0;
let saveTimer = 0;
let fileReadBusy = false;
const openedTabs = new Set([project.active]);
const editor = $('code-input');
const highlight = $('syntax-code');
const highlightLayer = $('syntax-layer');
const gutter = $('line-gutter');

function toast(message, warning = false) {
  const el = $('toast');
  el.textContent = message;
  el.className = `toast${warning ? ' warning' : ''}`;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.add('hidden'), 3800);
}

function consoleMessage(message, cls = 'system-line') {
  const element = document.createElement('p');
  element.className = cls;
  element.textContent = message;
  $('console-content').appendChild(element);
  $('console-content').scrollTop = $('console-content').scrollHeight;
}

function markPending() {
  $('save-status').textContent = 'Saving…';
  clearTimeout(saveTimer);
  saveTimer = setTimeout(persist, 350);
}

function persist() {
  clearTimeout(saveTimer);
  try {
    project = saveProject(project);
    $('save-status').textContent = '✓ Saved locally';
  } catch (error) {
    $('save-status').textContent = '⚠ Not saved';
    toast(`Unable to save: ${error.message}`, true);
  }
}

function updateProject(next) {
  project = validateProject(next);
  openedTabs.add(project.active);
  markPending();
  renderAll();
}

function enterFile(path) {
  if (!(path in project.files)) return;
  project.active = path;
  openedTabs.add(path);
  renderAll();
  markPending();
  editor.focus();
}

function setTitle() {
  $('project-title').textContent = project.name;
  $('project-folder').textContent = project.name.toUpperCase();
  $('breadcrumb-file').textContent = project.active;
  document.title = `${project.active} — LuauForge`;
}

function button(label, css, fn, title = '') {
  const b = document.createElement('button');
  b.className = css;
  b.type = 'button';
  b.textContent = label;
  if (title) b.title = title;
  b.addEventListener('click', fn);
  return b;
}

function renderFiles() {
  const fileTree = $('file-tree');
  fileTree.replaceChildren();
  const sorted = Object.keys(project.files).sort((a, b) => a.localeCompare(b));
  const folders = new Set();
  sorted.forEach(path => {
    const bits = path.split('/');
    for (let i = 0; i < bits.length - 1; i++) {
      const folder = bits.slice(0, i + 1).join('/');
      if (!folders.has(folder)) {
        folders.add(folder);
        const folderLabel = document.createElement('div');
        folderLabel.className = 'folder-item';
        folderLabel.style.paddingLeft = `${12 + i * 13}px`;
        folderLabel.textContent = `⌄  ${bits[i]}`;
        fileTree.append(folderLabel);
      }
    }
    const line = button('', `file-item${project.active === path ? ' active' : ''}`, () => enterFile(path), path);
    line.style.paddingLeft = `${14 + (bits.length - 1) * 13}px`;
    const icon = document.createElement('span');
    icon.className = 'file-icon';
    icon.textContent = '◇';
    const label = document.createElement('span');
    label.className = 'file-label';
    label.textContent = bits.at(-1);
    line.append(icon, label);
    fileTree.append(line);
  });
}

function renderTabs() {
  const tabs = $('editor-tabs');
  tabs.replaceChildren();
  for (const path of [...openedTabs]) {
    if (!(path in project.files)) { openedTabs.delete(path); continue; }
    const tab = document.createElement('div');
    tab.className = `editor-tab${path === project.active ? ' selected' : ''}`;
    tab.setAttribute('role', 'tab');
    tab.setAttribute('aria-selected', String(path === project.active));
    tab.appendChild(button(`◇  ${path.split('/').at(-1)}`, 'tab-name', () => enterFile(path), path));
    if (openedTabs.size > 1) tab.appendChild(button('×', 'tab-close', () => {
      openedTabs.delete(path);
      if (project.active === path) enterFile([...openedTabs].at(-1));
      else renderTabs();
    }, 'Close editor tab'));
    tabs.appendChild(tab);
  }
}

function updateEditorDrawing() {
  const code = editor.value;
  const lineTotal = countLines(code);
  highlight.innerHTML = code.length <= 70000 ? highlightLuau(code) : escapeForHTML(code) + '\n';
  const gutterLimit = Math.min(lineTotal, 5000);
  gutter.textContent = Array.from({ length: gutterLimit }, (_, i) => String(i + 1)).join('\n') + (lineTotal > gutterLimit ? '\n…' : '');
  $('line-count').textContent = `${lineTotal} ${lineTotal === 1 ? 'line' : 'lines'}`;
  $('file-size').textContent = formatBytes(new TextEncoder().encode(code).byteLength);
  updateCursor();
  syncScroll();
}

function escapeForHTML(value) { return value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;'); }
function syncScroll() { highlightLayer.scrollTop = editor.scrollTop; highlightLayer.scrollLeft = editor.scrollLeft; gutter.scrollTop = editor.scrollTop; }

function updateCursor() {
  const before = editor.value.slice(0, editor.selectionStart);
  const lines = before.split('\n');
  $('cursor-position').textContent = `Ln ${lines.length}, Col ${lines.at(-1).length + 1}`;
}

function renderStats() {
  $('stat-files').textContent = Object.keys(project.files).length;
  $('stat-lines').textContent = Object.values(project.files).reduce((total, source) => total + countLines(source), 0).toLocaleString();
  $('stat-size').textContent = formatBytes(projectSize(project));
}

function renderAll() {
  document.body.dataset.theme = project.theme;
  document.documentElement.style.colorScheme = project.theme;
  setTitle();
  renderFiles();
  renderTabs();
  editor.value = project.files[project.active];
  editor.setAttribute('wrap', project.wordWrap ? 'soft' : 'off');
  document.querySelector('.editor-section').classList.toggle('wrapped', project.wordWrap);
  $('wrap-toggle').textContent = `Wrap: ${project.wordWrap ? 'on' : 'off'}`;
  $('mode-select').value = project.mode;
  $('optimization-select').value = String(project.optimization);
  $('sidebar').classList.toggle('collapsed', !project.sidebarOpen);
  updateEditorDrawing();
  renderStats();
}

function insertAtCursor(value, cursorBack = 0) {
  const start = editor.selectionStart;
  const end = editor.selectionEnd;
  editor.setRangeText(value, start, end, 'end');
  editor.setSelectionRange(start + value.length - cursorBack, start + value.length - cursorBack);
  editor.dispatchEvent(new Event('input', { bubbles: true }));
}

editor.addEventListener('input', () => {
  const next = { ...project, files: { ...project.files, [project.active]: editor.value } };
  project = next;
  markPending();
  updateEditorDrawing();
  renderStats();
});
editor.addEventListener('scroll', syncScroll, { passive: true });
editor.addEventListener('click', updateCursor);
editor.addEventListener('keyup', updateCursor);
editor.addEventListener('keydown', event => {
  if (event.key === 'Tab') { event.preventDefault(); insertAtCursor('    '); }
  if (event.key === 'Enter' && !event.shiftKey && !event.ctrlKey && !event.metaKey && editor.selectionStart === editor.selectionEnd) {
    const before = editor.value.slice(0, editor.selectionStart);
    const indent = before.split('\n').at(-1).match(/^\s*/)?.[0] ?? '';
    if (indent) { event.preventDefault(); insertAtCursor(`\n${indent}`); }
  }
});

function askNewFile(template = 'basic') {
  const name = prompt('New Luau filename (folders supported)', `new-${Object.keys(project.files).length + 1}.luau`);
  if (name === null) return;
  const templates = {
    basic: '--!strict\n\nprint("Hello from Luau!")\n',
    module: '--!strict\n\nlocal Module = {}\n\nfunction Module.hello(name: string): string\n    return `Hello, {name}!`\nend\n\nreturn Module\n',
    type: '--!strict\n\ntype Item = { name: string, amount: number }\n\nlocal function describe(item: Item): string\n    return `{item.name}: {item.amount}`\nend\n\nprint(describe({ name = "Coins", amount = 100 }))\n',
    benchmark: '--!strict\n\nlocal iterations = 100000\nlocal start = os.clock()\nlocal result = 0\nfor i = 1, iterations do\n    result += i\nend\nprint("Result:", result)\nprint("Elapsed:", os.clock() - start)\n',
  };
  try { updateProject(addFile(project, name, templates[template] || templates.basic)); toast(`Created ${normalizePath(name)}`); }
  catch (error) { toast(error.message, true); }
}

function renameActive() {
  const input = prompt('Rename file', project.active);
  if (input === null) return;
  try {
    const old = project.active;
    const next = renameFile(project, old, input);
    if (openedTabs.has(old)) { openedTabs.delete(old); openedTabs.add(next.active); }
    updateProject(next);
    toast('File renamed.');
  } catch (error) { toast(error.message, true); }
}

function deleteActive() {
  if (!confirm(`Delete ${project.active}? You can restore it only from an export.`)) return;
  try { updateProject(deleteFile(project, project.active)); toast('File deleted.'); }
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
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function exportProject() {
  persist();
  downloadFile('luau-workspace.json', projectToJSON(project), 'application/json');
  toast('Project exported as JSON.');
}

async function importSelection(event) {
  if (fileReadBusy) return;
  fileReadBusy = true;
  try {
    const chosen = Array.from(event.target.files || []);
    if (!chosen.length) return;
    for (const file of chosen) {
      if (file.size > 1000000) throw new Error(`${file.name} is too large to import.`);
      const contents = await file.text();
      if (file.name.toLowerCase().endsWith('.json')) {
        const parsed = JSON.parse(contents);
        const normalized = validateProject(parsed);
        if (!confirm(`Replace current workspace with ${normalized.name}? Export first if needed.`)) continue;
        project = normalized;
        openedTabs.clear();
        openedTabs.add(project.active);
      } else if (/\.lua(u)?$/i.test(file.name)) {
        const candidate = normalizePath(file.name);
        if (candidate in project.files) {
          if (!confirm(`Replace existing file ${candidate}?`)) continue;
          project = validateProject({ ...project, files: { ...project.files, [candidate]: contents }, active: candidate });
        } else project = addFile(project, candidate, contents);
      } else throw new Error('Only .lua, .luau and project .json files are accepted.');
    }
    openedTabs.add(project.active);
    markPending();
    renderAll();
    toast('Import completed.');
  } catch (error) { toast(`Import error: ${error.message}`, true); }
  finally { event.target.value = ''; fileReadBusy = false; }
}

function showRunner() {
  persist();
  const modal = $('runner-modal');
  const holder = $('runner-frame-container');
  holder.replaceChildren();
  modal.classList.remove('hidden');
  document.body.classList.add('modal-open');
  $('runner-close').focus();
  $('output-indicator').textContent = 'OPEN';
  let url = 'https://play.luau.org/';
  try {
    // Keep share URLs within reasonable browser limits. Large projects pass only the active source.
    const fullUrl = buildPlaygroundURL(project);
    if (fullUrl.length < 24000) url = fullUrl;
    else {
      const activeOnly = buildPlaygroundURL({ ...project, files: { 'main.luau': project.files[project.active] }, active: 'main.luau' });
      if (activeOnly.length < 24000) {
        url = activeOnly;
        consoleMessage('The project is large; only the active source was sent to the runner.', 'notice-line');
      } else {
        consoleMessage('Source is too large for a reliable share URL. Copy the code manually into the runner.', 'notice-line');
        toast('Current file is too large to preload into the runner.', true);
      }
    }
    consoleMessage(`Opened ${project.active} in the official Luau runner. Output appears in the embedded panel.`);
  } catch (error) {
    consoleMessage(`Share codec unavailable: ${error.message}`, 'error-line');
    toast('Unable to preload source. Copy it manually into the official runner.', true);
  }
  $('runner-external').href = url.replace('embed=true&', '');
  const iframe = document.createElement('iframe');
  iframe.title = 'Official Luau Playground compiler and runner';
  iframe.src = url;
  iframe.loading = 'eager';
  iframe.referrerPolicy = 'no-referrer';
  iframe.allow = 'clipboard-write';
  holder.append(iframe);
}

function closeRunner() {
  $('runner-frame-container').replaceChildren();
  $('runner-modal').classList.add('hidden');
  document.body.classList.remove('modal-open');
  $('output-indicator').textContent = 'READY';
  $('run-btn').focus();
}

$('add-file').addEventListener('click', () => askNewFile());
document.querySelectorAll('[data-template]').forEach(button => button.addEventListener('click', () => askNewFile(button.dataset.template)));
$('rename-file').addEventListener('click', renameActive);
$('delete-file').addEventListener('click', deleteActive);
$('rename-project').addEventListener('click', () => {
  const name = prompt('Workspace name', project.name);
  if (name !== null && name.trim()) updateProject({ ...project, name: name.trim() });
});
$('download-file').addEventListener('click', () => downloadFile(project.active.split('/').at(-1), project.files[project.active], 'text/plain'));
$('export-btn').addEventListener('click', exportProject);
$('mobile-export').addEventListener('click', exportProject);
$('import-btn').addEventListener('click', () => $('import-input').click());
$('import-input').addEventListener('change', importSelection);
$('clear-console').addEventListener('click', () => {
  $('console-content').replaceChildren();
  consoleMessage('Console cleared.');
});
$('mode-select').addEventListener('change', event => updateProject({ ...project, mode: event.target.value }));
$('optimization-select').addEventListener('change', event => updateProject({ ...project, optimization: Number(event.target.value) }));
$('wrap-toggle').addEventListener('click', () => updateProject({ ...project, wordWrap: !project.wordWrap }));
$('theme-toggle').addEventListener('click', () => updateProject({ ...project, theme: project.theme === 'dark' ? 'light' : 'dark' }));
$('sidebar-toggle').addEventListener('click', () => updateProject({ ...project, sidebarOpen: !project.sidebarOpen }));
$('mobile-files').addEventListener('click', () => $('sidebar').classList.toggle('mobile-visible'));
$('run-btn').addEventListener('click', showRunner);
$('mobile-run').addEventListener('click', showRunner);
$('expand-runner').addEventListener('click', showRunner);
$('runner-close').addEventListener('click', closeRunner);
$('runner-modal').addEventListener('click', event => { if (event.target === $('runner-modal')) closeRunner(); });
document.addEventListener('keydown', event => {
  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 's') { event.preventDefault(); persist(); toast('Saved locally.'); }
  if ((event.ctrlKey || event.metaKey) && event.key === 'Enter') { event.preventDefault(); showRunner(); }
  if (event.key === 'Escape' && !$('runner-modal').classList.contains('hidden')) closeRunner();
});
window.addEventListener('pagehide', persist);
window.addEventListener('storage', event => {
  if (event.key === 'luau-dev-playground:v1') toast('Workspace changed in another tab. Refresh to load it.', true);
});

renderAll();
consoleMessage('Workspace loaded. Ctrl + Enter to open the Luau runtime.');
