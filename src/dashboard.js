import { inspectProject, benchmarkComparison, DASHBOARD_WIDGETS, readDashboardSettings, saveDashboardSettings, readActivity, appendActivity } from './dashboard-model.js';
import { readV15 } from './v15-settings.js';
import { STUDIO_LIBRARIES, fetchStudioLibrary, fetchStudioPackage, studioLibraryURL } from './studio-libraries.js';
import { BUILTIN_LIBRARIES } from './builtin-libraries.js';
import { quickFixSuggestions } from './v15-analysis.js';
import { makeZip } from './v1-zip.js';
import { formatBytes } from './store.js';

export function mountDashboard({ workspace, state, runtime, openEditor, openFile, runCurrent, checkCurrent, runTests, benchmarkPicker, setSide, openModules, snapshotNow, snapshotDialog, createTemplate, exportZip, importProject, download, notify, showOutput }) {
  const root = document.getElementById('dashboard-view');
  const settings = readDashboardSettings(localStorage);
  let visible = false;
  let localRuntimeStatus = 'Not checked';
  let githubInfo = 'Not checked';
  let storageInfo = 'Estimate not requested';
  const el = (tag, text, cls) => { const n = document.createElement(tag); if (text != null) n.textContent = String(text); if (cls) n.className = cls; return n; };
  const btn = (label, action, cls = 'dash-action') => { const b = el('button', label, cls); b.type = 'button'; b.addEventListener('click', async () => { try { await action(); } catch (err) { notify(err.message || String(err), true); } }); return b; };
  const line = (card, text, cls) => card.append(el('p', text, cls || 'dash-line'));
  const link = (card, title, uri) => { const a = el('a', title, 'dash-link'); a.href = uri; a.rel = 'noopener noreferrer'; a.target = '_blank'; card.append(a); };
  const cardButtons = (card, ...items) => { const row = el('div', null, 'dash-controls'); for (const [title, handler] of items) row.append(btn(title, handler)); card.append(row); };
  const moment = stamp => { try { return new Date(stamp).toLocaleString(); } catch { return ''; } };
  const getModel = () => inspectProject(workspace.project, { problems: state.problems, testResults: state.tests, benchmark: state.bench, history: readV15(localStorage).history, snapshots: workspace.snapshots() });
  function log(label) { appendActivity(localStorage, label); if (visible) render(); }
  async function downloadStudio(lib) { const source = await fetchStudioLibrary(lib); download(lib.filename, source, 'text/plain'); log(`Downloaded ${lib.label} for Roblox Studio`); }
  async function downloadStudioPackage(lib) {const sources=await fetchStudioPackage(lib);download(lib.id+'-Studio-Package.zip',makeZip(sources),'application/zip');log('Downloaded complete Studio package: '+lib.label);}
  function studioExample(lib) {
    const path = `examples/studio/${lib.id}.server.luau`;
    if (Object.hasOwn(workspace.project.files, path)) workspace.open(path);
    else { workspace.snapshot(); workspace.create(path, lib.example); }
    log(`Opened Studio example: ${lib.label}`); openEditor();
  }
  const views = {
    overview(card, m) { line(card, `${m.name} · ${m.fileCount} files · ${m.modules} workspace modules`); line(card, `${m.lines.toLocaleString()} lines · ${formatBytes(m.bytes)}`); cardButtons(card, ['Open editor', openEditor], ['Export ZIP', exportZip]); },
    recent(card,m) { for(const path of [workspace.project.active, ...workspace.tabs.filter(x=>x!==workspace.project.active)].slice(0,6)) card.append(btn(path,()=>{openFile(path);openEditor();},'dash-list-btn')); line(card,'Currently opened files (the editor does not track edit timestamps).','dash-note'); },
    actions(card) { cardButtons(card,['New script',()=>{openEditor();createTemplate('script');}],['New module',()=>{openEditor();createTemplate('module');}],['Run',()=>{openEditor();runCurrent();}],['Check',()=>{openEditor();checkCurrent();}]); },
    runtime(card) { line(card,localRuntimeStatus); cardButtons(card,['Test WASM',async()=>{localRuntimeStatus='Checking WASM…';render();const x=await runtime.health();localRuntimeStatus=x?.ready?`Ready: Luau WASM ${x.version||''}`:'WASM response did not confirm readiness';render();}]); },
    errors(card,m) {line(card, m.diagnosticsLabel);cardButtons(card,['Run type check',async()=>{openEditor();await checkCurrent();showOutput('problems');}],['View problems',()=>{openEditor();showOutput('problems');}]);},
    performance(card,m) { line(card,m.benchmark?`Last require: ${m.benchmark.module}, ${m.benchmark.roundCount} samples`:'No module benchmark in this session');cardButtons(card,['Benchmark a module',()=>{openEditor();benchmarkPicker();}],['Results',()=>{openEditor();showOutput('benchmarks');}]);},
    history(card,m) { line(card,`${m.history.length} saved benchmarking result(s)`);for(const h of m.history.slice(-3).reverse())line(card,`${h.label}: ${h.medianNs.toFixed(1)} ns/op`);cardButtons(card,['Open benchmarks',()=>{openEditor();showOutput('benchmarks');}]);},
    modules(card,m) {line(card,`${m.wasmLibraries.length} standalone WASM modules · ${m.studioLibraries.length} Studio packages · ${m.modules} project modules`);line(card,`Used built-ins: ${m.referenced.map(x=>x.id).join(', ')||'none'}`);cardButtons(card,['Browse libraries',openModules]);},
    dependencies(card,m) {line(card,`${m.dependencies.cycles.length} circular dependency(s) · ${m.dependencies.problems.length} unresolved path(s)`);for(const c of m.dependencies.cycles.slice(0,2)) line(card,'Cycle: '+c.join(' → '));for(const x of m.dependencies.problems.slice(0,2))line(card,x.message);cardButtons(card,['Open module browser',openModules]);},
    api(card) {const input=el('input',null,'dash-search');input.type='search';input.placeholder='Search API names…';input.setAttribute('aria-label','Search library methods');const list=el('div',null,'dash-matches');const all=[...BUILTIN_LIBRARIES.flatMap(l=>l.categories.flatMap(c=>c.methods.map(method=>`${l.id}.${method}`))),...STUDIO_LIBRARIES.flatMap(l=>l.methods.map(method=>`${l.id}.${method} (Studio)`))];const draw=()=>{list.replaceChildren();const q=input.value.trim().toLowerCase();if(q.length<2)return;const matches=all.filter(x=>x.toLowerCase().includes(q)).slice(0,12);for(const m of matches)list.append(el('p',m,'dash-line'));if(!matches.length)line(list,'No methods matched the bundled metadata.');};input.addEventListener('input',draw);card.append(input,list);line(card,'Library APIs are suggestions; check upstream docs for exact signatures.','dash-note');},
    tests(card,m) {line(card,m.testsRun?`${m.testsRun.passed} passed · ${m.testsRun.failed} failed (this session)`:`${m.tests.length} test file(s) · no test result this session`);cardButtons(card,['Run project tests',()=>{openEditor();runTests();}],['Open results',()=>{openEditor();showOutput('tests');}]);},
    storage(card,m) {line(card,`${formatBytes(m.bytes)} workspace source · ${storageInfo}`);cardButtons(card,['Estimate storage',async()=>{const v=await navigator.storage?.estimate?.();storageInfo=v?`${formatBytes(v.usage||0)} used / ${formatBytes(v.quota||0)} estimated quota`:'Browser storage estimates unavailable';render();}],['Backup ZIP',exportZip]);},
    activity(card) {const events=readActivity(localStorage);for(const e of events.slice(0,5))line(card,`${moment(e.at)} · ${e.label}`);if(!events.length)line(card,'No dashboard activity logged yet.');},
    github(card) {line(card,githubInfo);cardButtons(card,['Check public repository',async()=>{githubInfo='Checking…';render();const res=await fetch('https://api.github.com/repos/SillyDev2026/Luau-Developer-Playground/commits/main',{headers:{Accept:'application/vnd.github+json'}});if(!res.ok)throw new Error(`GitHub returned HTTP ${res.status}`);const data=await res.json();githubInfo=`Latest public main commit: ${data.sha?.slice(0,9)||'unknown'} · ${moment(data.commit?.committer?.date)}`;render();}]);link(card,'Open GitHub repository','https://github.com/SillyDev2026/Luau-Developer-Playground');line(card,'Read-only public status, not authenticated repository sync.','dash-note');},
    templates(card) {cardButtons(card,['Script',()=>{openEditor();createTemplate('script');}],['Module',()=>{openEditor();createTemplate('module');}],['Test',()=>{openEditor();createTemplate('test');}],['Benchmark',()=>{openEditor();createTemplate('benchmark');}]);},
    quality(card,m) {const src=workspace.project.files[workspace.project.active]||'';const fixes=quickFixSuggestions(src);line(card,`${fixes.length} conservative quick fix suggestion(s) for ${workspace.project.active}`);for(const fix of fixes.slice(0,3))line(card,fix.label);line(card,'Heuristics are not a replacement for the Luau type checker.','dash-note');cardButtons(card,['Check code',()=>{openEditor();checkCurrent();}]);},
    comparisons(card,m) {const samples=benchmarkComparison(m.history);for(const s of samples.slice(0,5))line(card,`${s.label} · ${s.medianNs.toFixed(1)} ns/op`);if(!samples.length)line(card,'No saved comparable benchmarks yet.');line(card,'Results may reflect different workloads or devices.','dash-note');},
    health(card,m) {line(card,`${m.healthScore}/100 project checks passing (not a performance or code quality grade)`);for(const item of m.healthChecks)line(card,`${item.pass?'✓':'○'} ${item.name}`);},
    customize(card) {line(card,'Control which dashboard widgets appear. Preferences stay on this device.');const row=el('div',null,'dash-controls');row.append(btn('Choose widgets',()=>{const m=document.getElementById('dash-config');m.classList.toggle('hidden');}),btn('Reset order',()=>{settings.order=DASHBOARD_WIDGETS.map(x=>x[0]);saveDashboardSettings(localStorage,settings);render();}));card.append(row);},
    recovery(card,m) {line(card,`${m.snapshots.length} stored recovery snapshot(s)`);for(const s of m.snapshots.slice(0,3))line(card,`${s.name||'Workspace'} · ${moment(s.createdAt)}`);cardButtons(card,['Create snapshot',()=>{snapshotNow();log('Recovery snapshot created');}],['Restore snapshot',()=>{openEditor();snapshotDialog();}],['Export source',exportZip]);},
  };
  function render() {
    if(!visible)return;
    const m=getModel(), grid=document.getElementById('dashboard-grid');grid.replaceChildren();
    for(const id of settings.order){if(settings.hidden.includes(id))continue;const label=DASHBOARD_WIDGETS.find(([key])=>key===id)?.[1];if(!label||!views[id])continue;
      const card=el('article',null,'dash-card');card.dataset.widget=id;const title=el('h3',label);card.append(title);try{views[id](card,m);}catch(err){line(card,`Widget unavailable: ${err.message}`);}grid.append(card);
    }
    const toggle=document.getElementById('dash-config');toggle.replaceChildren();
    for(const [id,label] of DASHBOARD_WIDGETS){const row=el('label',null,'dash-setting');const check=el('input');check.type='checkbox';check.checked=!settings.hidden.includes(id);check.addEventListener('change',()=>{settings.hidden=check.checked?settings.hidden.filter(x=>x!==id):[...settings.hidden,id];saveDashboardSettings(localStorage,settings);render();});row.append(check,el('span',label));const earlier=btn('↑',()=>{const i=settings.order.indexOf(id);if(i>0){[settings.order[i-1],settings.order[i]]=[settings.order[i],settings.order[i-1]];saveDashboardSettings(localStorage,settings);render();}},'dash-move');row.append(earlier);toggle.append(row);}
  }
  function open() {visible=true;root.classList.remove('hidden');document.getElementById('main-surface').classList.add('dashboard-active');document.getElementById('dash-editor-open').focus();render();}
  function close() {visible=false;root.classList.add('hidden');document.getElementById('main-surface').classList.remove('dashboard-active');document.getElementById('code-input').focus();}
  document.getElementById('dash-editor-open').addEventListener('click',close);
  document.getElementById('dashboard-btn').addEventListener('click',()=>visible?close():open());
  document.getElementById('dash-refresh').addEventListener('click',render);
  document.getElementById('dash-studio-library').addEventListener('click',()=>{const target=document.getElementById('dash-studio-list');target.classList.toggle('hidden');});
  const container=document.getElementById('dash-studio-list');
  for(const lib of STUDIO_LIBRARIES) {const item=el('article',null,'dash-studio-item');item.append(el('strong',lib.label),el('p',lib.purpose),el('p',`Roblox Studio only · ${lib.dependencies.join(' · ')}`));const controls=el('div',null,'dash-controls');controls.append(btn('Studio example',()=>studioExample(lib)),btn('Download source',()=>downloadStudio(lib)),btn('Package ZIP',()=>downloadStudioPackage(lib)),btn('View repository',()=>window.open(`https://github.com/SillyDev2026/${lib.repo}`, '_blank','noopener,noreferrer')));item.append(controls);container.append(item);}
  return {open,close,render,log,isOpen:()=>visible};
}
