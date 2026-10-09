import { wordAt, planRename, findReferences, inferSimpleTypes, generateModuleDocs, quickFixSuggestions } from './v15-analysis.js';
import { moduleReport, missingRequireCandidates, modulePinManifest } from './v15-modules.js';
import { makeBenchSource, parseBenchResult, formatBenchmarkCsv, compareBenchmarks } from './v15-bench.js';
import { readZip } from './v15-zip.js';
import { readV15, saveV15, registerSnippet, registerShelfModule } from './v15-settings.js';
import { BUILTIN_LIBRARIES } from './builtin-libraries.js';
import { makeZip } from './v1-zip.js';

export function mountV15({ workspace, editor, runtime, notify, modal, promptModal, download, openFile, closeMobile }) {
  const $ = id => document.getElementById(id);
  const store = readV15(localStorage);
  const persist = () => { if (!saveV15(localStorage, store)) notify('Toolbox history could not be saved; check storage permissions.', true); };
  const node = (tag, text, klass = '') => { const el = document.createElement(tag); if (text !== undefined) el.textContent = String(text); if (klass) el.className = klass; return el; };
  const button = (text, action, klass = 'dialog-row') => { const el = node('button', text, klass); el.type = 'button'; el.addEventListener('click', action); return el; };
  const hint = (parent, value) => parent.append(node('p', value, 'dialog-hint'));
  const title = (parent, value) => parent.append(node('strong', value));
  const textInput = (parent, placeholder, initial = '') => { const input = node('input'); input.placeholder = placeholder; input.value = initial; parent.append(input); return input; };
  const textArea = (parent, placeholder, initial = '') => { const input = node('textarea'); input.placeholder = placeholder; input.value = initial; parent.append(input); return input; };
  const safe = action => { try { return action(); } catch (err) { notify(err.message, true); return undefined; } };
  const active = () => workspace.project.active;
  const source = () => editor.input.value;
  const snapshot = () => workspace.snapshot();
  const applySource = (result, message = 'Source updated') => { snapshot(); editor.replace(0, source().length, result, 0); notify(message + ' · Recovery snapshot created'); };
  const activeWord = () => wordAt(source(), editor.input.selectionStart);

  function renameSymbol() {
    const name = activeWord();
    promptModal('Safe symbol rename (current file)', `Rename local/function '${name || '(select identifier)'}'. A source preview and recovery snapshot are required. Advanced lexical shadowing is not automatically resolved.`, name || '', replacement => {
      const plan = planRename(workspace.project.files, active(), editor.input.selectionStart, replacement);
      modal('Preview rename: ' + plan.name + ' → ' + replacement, body => {
        hint(body, `${plan.preview} token references in ${active()} · ${plan.cautious ? 'Review local scope boundaries carefully.' : 'Review replacements carefully.'} Strings, comments, and member properties are excluded.`);
        const preview = node('pre', plan.apply().slice(0, 5000), 'v15-preview'); body.append(preview);
        body.append(button('Apply rename + snapshot', () => { applySource(plan.apply(), `Renamed ${plan.name}`); $('dialog-close').click(); }, 'dialog-cta'));
      });
      return false;
    });
  }
  function references() {
    const word = activeWord();
    if (!word) return notify('Place the cursor on an identifier.', true);
    const items = findReferences(workspace.project.files, word).slice(0, 150);
    modal(`References: ${word}`, body => {
      hint(body, `${items.length} lexical matches (strings/comments/property names excluded). Dynamic access and shadowed locals need manual verification.`);
      for (const ref of items) body.append(button(`${ref.file}:${ref.line}`, () => { $('dialog-close').click(); openFile(ref.file); editor.selectLine(ref.line); }));
    });
  }
  function typeExplorer() {
    modal('Type Explorer', body => {
      hint(body, 'Declared and simple inferred types in the active file; strict diagnostics are available under ✓ Check.');
      for (const item of inferSimpleTypes(source()).slice(0, 100)) body.append(button(`${item.name} : ${item.type}     line ${item.line}`, () => { $('dialog-close').click(); editor.selectLine(item.line); }));
    });
  }
  function quickFixes() {
    modal('Quick fixes', body => {
      const fixes = quickFixSuggestions(source());
      hint(body, 'Conservative suggestions only. No mass automatic edits. Run ✓ Check for compiler diagnostics.');
      for (const fix of fixes) body.append(button(fix.label, () => { if (fix.insert) { applySource(fix.insert + source(), 'Inserted strict directive'); $('dialog-close').click(); } else notify(fix.note || fix.label); }));
      if (!fixes.length) hint(body, 'No safe automatic fix found.');
    });
  }
  function snippets() {
    modal('Reusable code snippets', body => {
      hint(body, 'Store up to 40 snippets locally. No snippet executes until inserted and Run is pressed.');
      for (const [key, snippet] of Object.entries(store.snippets)) {
        body.append(button(`Insert ${key} · ${snippet.length} characters`, () => { $('dialog-close').click(); editor.replace(editor.input.selectionStart, editor.input.selectionEnd, snippet); }));
      }
      const key = textInput(body, 'Shortcut name, e.g. bench'); const code = textArea(body, 'Luau snippet source');
      body.append(button('Save snippet', () => safe(() => { registerSnippet(store, key.value, code.value); persist(); $('dialog-close').click(); notify('Snippet saved'); }), 'dialog-cta'));
      body.append(button('Remove snippet', () => safe(() => { delete store.snippets[key.value]; persist(); $('dialog-close').click(); }), 'dialog-row'));
    });
  }
  function moduleInspector() {
    const report = moduleReport(workspace.project.files);
    modal('Module dependency inspector', body => {
      hint(body, `${report.count} files · ${report.cycles.length} cycles · ${report.unused.length} possibly unused modules. Unused findings are advisory.`);
      for (const file of report.nodes) {
        const incoming = report.incoming.get(file) || [];
        const outgoing = report.edges.get(file) || [];
        body.append(button(`${file}  ↘${outgoing.length}  ↗${incoming.length}${report.unused.includes(file) ? ' · Possibly unused' : ''}`, () => { $('dialog-close').click(); openFile(file); }));
      }
      for (const cycle of report.cycles) hint(body, '⚠ Cycle: ' + cycle.join(' → '));
      for (const warning of report.problems) hint(body, '⚠ ' + warning.file + ': ' + warning.message);
    });
  }
  function apiDocs() {
    modal('Generate module API docs', body => {
      const list = Object.keys(workspace.project.files).filter(x => /\.lua(u)?$/.test(x));
      hint(body, 'Generate a Markdown summary from source declarations. Types should be checked with Luau WASM.');
      for (const path of list) body.append(button(path, () => {
        download(path.split('/').at(-1).replace(/\.lua(u)?$/, '') + '-api.md', generateModuleDocs(path, workspace.project.files[path]), 'text/markdown');
        notify('API documentation exported');
      }));
    });
  }
  function pins() {
    modal('Pinned library versions', body => {
      hint(body, 'Built-ins use exact, audited source releases. Alternate versions are not fetched or invented. To test a different release, import its source as a workspace module.');
      for (const entry of modulePinManifest(BUILTIN_LIBRARIES, workspace.project.files)) body.append(button(`@${entry.id} — v${entry.version} · ${entry.referenced ? 'used' : 'available'} · pinned`, () => window.open(entry.repository, '_blank', 'noopener')));
    });
  }
  function shelf() {
    modal('My custom module shelf', body => {
      hint(body, 'Save small Lua/Luau modules locally and import them into other projects. Stored separately from workspace files.');
      for (const [name, code] of Object.entries(store.library)) body.append(button(`Import ${name}`, () => safe(() => {
        const path = `modules/${name}.luau`;
        if (Object.hasOwn(workspace.project.files, path)) throw new Error('Module exists: ' + path);
        snapshot(); workspace.create(path, code); $('dialog-close').click(); notify(path + ' imported');
      })));
      const name = textInput(body, 'Module name'); const code = textArea(body, 'Module source ending in return Module');
      body.append(button('Save to module shelf', () => safe(() => { registerShelfModule(store, name.value, code.value); persist(); $('dialog-close').click(); notify('Saved to module shelf'); }), 'dialog-cta'));
      body.append(button('Save current file to shelf', () => safe(() => { const base = active().split('/').at(-1).replace(/\.lua(u)?$/i, ''); registerShelfModule(store, base, source()); persist(); $('dialog-close').click(); notify('Current module added'); })));
    });
  }
  function importSuggestions() {
    const items = missingRequireCandidates(source(), Object.keys(workspace.project.files).filter(x => x !== active()));
    modal('Smart missing-import suggestions', body => {
      hint(body, 'Find candidate module references and insert missing paths only after confirmation.');
      if (!items.length) hint(body, 'No unbound module-name candidates found in this file.');
      for (const item of items) body.append(button(`${item.name} → ${item.path}`, () => safe(() => {
        const prefix = active().split('/').slice(0, -1), target = item.path.split('/');
        while (prefix.length && target.length && prefix[0] === target[0]) { prefix.shift(); target.shift(); }
        const relative = `${'../'.repeat(prefix.length)}${target.join('/')}`;
        applySource(`local ${item.name} = require("${relative.startsWith('.') ? relative : './' + relative}")\n` + source(), 'Inserted missing import'); $('dialog-close').click();
      })));
    });
  }
  function benchDialog() {
    modal('Benchmark Suite 3.0 · Luau WASM', body => {
      hint(body, 'Runs warmup and batched timed loops in Luau WASM using os.clock. Browser timings are not Roblox Studio server timings.');
      const expr = textInput(body, 'Expression evaluated for each i', 'math.sqrt(i)');
      const setup = textArea(body, 'Optional Luau setup declarations', ''); setup.rows = 3;
      const iterations = textInput(body, 'Iterations', '100000'); iterations.type = 'number';
      const warmup = textInput(body, 'Warmups', '10000'); warmup.type = 'number';
      const samples = textInput(body, 'Samples', '10'); samples.type = 'number';
      body.append(button('Stop active benchmark', () => { runtime.stop(); notify('Benchmark stopped'); }));
      const launch = button('Run WASM benchmark', async () => {
        if (launch.disabled) return;
        launch.disabled = true;
        try {
          const code = makeBenchSource({ setup: setup.value, expression: expr.value, iterations: Number(iterations.value), warmup: Number(warmup.value), samples: Number(samples.value) });
          const files = { ...workspace.project.files }, path = '__lf_profiler_v15.luau';
          if (Object.hasOwn(files, path)) throw new Error('Reserved profiler file already exists.');
          files[path] = code;
          const data = await runtime.run({ ...workspace.project, active: path, files, benchmark: true });
          if (!data.result.success) throw new Error(data.result.error || 'Luau benchmark failed');
          const result = parseBenchResult(data.result.output);
          const entry = { ...result, label: expr.value.slice(0, 100), timestamp: new Date().toISOString() };
          store.history.push(entry); store.history = store.history.slice(-50); persist();
          $('dialog-close').click();
          modal('Benchmark results · Luau WASM', target => {
            hint(target, 'Median ' + result.medianNs.toFixed(2) + ' ns/op · P95 ' + result.p95Ns.toFixed(2) + ' ns/op');
            hint(target, 'Min ' + result.minNs.toFixed(2) + ' · Max ' + result.maxNs.toFixed(2) + ' · ' + (result.opsPerSecond ? Math.round(result.opsPerSecond).toLocaleString() : 'n/a') + ' ops/s');
            target.append(button('Export CSV history', exportHistory));
          });
        } catch (error) { notify('Bench error: ' + error.message, true); }
        finally { launch.disabled = false; }
      }, 'dialog-cta'); body.append(launch);
    });
  }
  function exportHistory() { download('luauforge-v1.5-benchmarks.csv', formatBenchmarkCsv(store.history), 'text/csv'); }
  function history() {
    modal('Benchmark history and comparison', body => {
      hint(body, 'Last 50 runs stored locally. All numbers originate from Luau WASM os.clock. Compare matching operations on the same device.');
      for (const item of store.history.slice(-25).reverse()) hint(body, `${item.timestamp.slice(0, 16)} · ${item.label}: median ${item.medianNs.toFixed(2)} ns/op`);
      if (store.history.length >= 2) {
        const [a,b] = store.history.slice(-2); const comparison = compareBenchmarks(a, b);
        if (comparison) hint(body, `Previous/new median ratio: ${comparison.ratio.toFixed(3)}× · ${comparison.faster} faster`);
      }
      body.append(button('Export CSV', exportHistory));
      body.append(button('Export JSON', () => download('luauforge-v1.5-benchmarks.json', JSON.stringify(store.history, null, 2), 'application/json')));
      body.append(button('Clear history', () => { store.history = []; persist(); $('dialog-close').click(); notify('Benchmark history cleared'); }));
    });
  }
  function zipImporter() {
    const input = node('input'); input.type = 'file'; input.accept = '.zip,application/zip';
    input.addEventListener('change', async () => {
      const file = input.files?.[0]; if (!file) return;
      try {
        const files = await readZip(await file.arrayBuffer());
        modal('Preview ZIP import', body => {
          hint(body, `${Object.keys(files).length} validated Luau files. Only source files import; ZIP cannot run scripts on upload. A recovery snapshot will be created first.`);
          for (const filename of Object.keys(files)) hint(body, filename);
          body.append(button('Import all files', () => safe(() => {
            const collisions = Object.keys(files).filter(name => Object.hasOwn(workspace.project.files, name));
            if (collisions.length) throw new Error('Existing files would be replaced: ' + collisions.join(', ') + '. Rename them first.');
            snapshot(); workspace.update(p => ({ ...p, files: { ...p.files, ...files }, active: Object.keys(files)[0] }));
            $('dialog-close').click(); notify('Imported ' + Object.keys(files).length + ' files');
          }), 'dialog-cta'));
        });
      } catch (error) { notify('ZIP import failed: ' + error.message, true); }
    });
    input.click();
  }
  let secondary = null;
  function toggleSplit() {
    if (secondary) { secondary.remove(); secondary = null; $('editor-panel').classList.remove('v15-split'); $('editor-stage').style.flex = ''; notify('Split editor closed'); return; }
    if (matchMedia('(max-width:820px)').matches) return notify('Split editor is available on tablets/desktops; use Focus mode on phones.', true);
    const files = Object.keys(workspace.project.files);
    const pane = node('div', undefined, 'v15-secondary');
    const select = node('select');
    for (const file of files) { const option = node('option', file); option.value = file; select.append(option); }
    const chosen = files.find(x => x !== active()) || active(); select.value = chosen;
    const second = node('textarea'); second.spellcheck = false; second.value = workspace.project.files[chosen]; second.setAttribute('aria-label', 'Second Luau editor');
    select.addEventListener('change', () => { second.value = workspace.project.files[select.value] || ''; });
    second.addEventListener('input', () => { const path = select.value; if (!Object.hasOwn(workspace.project.files, path)) return notify('Secondary file no longer exists.', true); workspace.update(p => ({ ...p, files: { ...p.files, [path]: second.value } })); });
    const close = button('✕', () => toggleSplit());
    pane.append(select, close, second);
    $('editor-stage').after(pane);
    $('editor-panel').classList.add('v15-split');
    secondary = pane;
    close.addEventListener('click', () => $('editor-panel').classList.remove('v15-split'), { once: true });
    notify('Split editor opened');
  }
  function focusMode() {
    store.focus = !store.focus; persist();
    document.body.classList.toggle('v15-focus', store.focus);
    closeMobile();
    notify(store.focus ? 'Editor focus enabled · Console hidden' : 'Full workspace restored');
  }
  function recovery() {
    modal('Project and offline recovery', body => {
      hint(body, 'Your existing project data remains in the v1-compatible format. Use snapshots before bulk changes.');
      body.append(button('Create recovery snapshot', () => safe(() => { snapshot(); notify('Snapshot created'); })));
      body.append(button('Download JSON backup', () => download('luauforge-project-backup.json', JSON.stringify(workspace.project, null, 2), 'application/json')));
      body.append(button('Check WASM readiness', async () => { try { const r = await runtime.health(); notify(r?.ready ? 'Luau WASM ready' : 'WASM status unknown'); } catch (error) { notify(error.message, true); } }));
      body.append(button('Check offline cache', async () => { const names = await caches.keys().catch(() => []); notify(names.length ? `${names.length} cache entries found` : 'No cache available yet'); }));
    });
  }
  const actions = [
    ['Rename symbol · preview', renameSymbol], ['Find all references', references], ['Type explorer', typeExplorer], ['Quick fixes', quickFixes], ['Saved snippets', snippets],
    ['Missing import suggestions', importSuggestions], ['Module graph & unused files', moduleInspector], ['Generate module docs', apiDocs], ['Pinned library versions', pins], ['Custom module shelf', shelf],
    ['Benchmark Suite 3.0', benchDialog], ['Benchmark comparison & history', history], ['Export benchmark CSV', exportHistory],
    ['Run project tests', () => $('test-btn').click()], ['ZIP project import', zipImporter], ['Split editor', toggleSplit], ['Mobile focus mode', focusMode], ['Recovery manager', recovery],
    ['API documentation', () => { document.querySelector('[data-side="libraries"]').click(); document.getElementById('mobile-library').click(); }],
    ['Live Luau diagnostics', () => { $('live-check').checked = !$('live-check').checked; $('live-check').dispatchEvent(new Event('change')); notify('Live type checking ' + ($('live-check').checked ? 'enabled' : 'disabled')); }]
  ];
  const holder = $('v15-actions');
  if (!holder) throw new Error('Developer toolbox container is missing.');
  for (const [label, action] of actions) holder.append(button(label, () => safe(action), 'wide-btn v15-tool-button'));
  document.body.classList.toggle('v15-focus', store.focus);
  window.addEventListener('keydown', e => { if (e.key === 'F2' && document.activeElement === editor.input) { e.preventDefault(); renameSymbol(); } if ((e.ctrlKey || e.metaKey) && e.shiftKey && e.key.toLowerCase() === 'e') { e.preventDefault(); focusMode(); } });
  return { actions, store };
}
