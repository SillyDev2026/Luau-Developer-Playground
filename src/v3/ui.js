// LuauForge v3 Workbench: additive functionality, no workspace migrations.
import { workspaceSearch, formatWhitespace, qualityAudit, compareSources, createLockfile, parseLockfile, projectReport } from './core.js';
import { readGithubPins, previewGithubModule, saveGithubPin } from '../github-modules.js';

const $ = id => document.getElementById(id);
const element = (tag,text,className='')=>{const x=document.createElement(tag); if(text!==undefined)x.textContent=String(text);if(className)x.className=className;return x;};
const button=(label,handle,className='v3-item')=>{const x=element('button',label,className);x.type='button';x.addEventListener('click',handle);return x;};
const row=(body,text)=>body.append(element('p',text,'v3-muted'));
const field=(body,placeholder,value='')=>{const input=element('input',undefined,'v3-input');input.placeholder=placeholder;input.value=value;input.autocomplete='off';input.spellcheck=false;body.append(input);return input;};
const list=body=>{const d=element('div',undefined,'v3-list');body.append(d);return d;};
const safeMessage = e => typeof e?.message === 'string' ? e.message : 'Unable to complete action.';

export function mountV3({ workspace, editor, modal, closeModal, notify, download, openFile, runTests, checkCurrent, addPublicGithubModule, setSide, renderLibrary, importGithubSpecifier }) {
  const showError=err=>notify(safeMessage(err),true);
  function search() {
    modal('Search entire workspace',body=>{
      row(body,'Literal search across all Lua and Luau files. File names and line numbers are clickable.');
      const input=field(body,'Search code, comments and strings');
      const options=element('div',undefined,'v3-grid-row');
      const whole=element('input');whole.type='checkbox';const sensitive=element('input');sensitive.type='checkbox';
      const words=element('label');words.append(whole,document.createTextNode('Whole word'));
      const casing=element('label');casing.append(sensitive,document.createTextNode('Case sensitive'));
      options.append(words,casing);body.append(options);
      const output=list(body);
      const render=()=>{
        output.replaceChildren();if(!input.value.trim())return;
        try {const result=workspaceSearch(workspace.project.files,input.value,{wholeWord:whole.checked,caseSensitive:sensitive.checked});
          if(!result.matches.length)return output.append(element('p','No matching source.','v3-muted'));
          for(const hit of result.matches)output.append(button(`${hit.file}:${hit.line}:${hit.column}  ${hit.preview}`,()=>{closeModal();openFile(hit.file);editor.selectLine(hit.line);}));
          if(result.truncated)output.append(element('p','Showing first 250 results. Narrow the search to see more.','v3-muted'));
        }catch(error){output.append(element('p',safeMessage(error),'v3-muted'));}
      };
      input.addEventListener('input',render);whole.addEventListener('change',render);sensitive.addEventListener('change',render);input.focus();
    });
  }
  function audit() {
    modal('Project quality review',body=>{
      row(body,'Advisory static checks, not authoritative Luau type checking. Confirm errors in the WASM checker or Roblox Studio.');
      const result=qualityAudit(workspace.project.files);
      row(body,`${result.scanned} files · ${result.findings.length} findings · ${result.cycles} dependency cycles · ${result.unresolved} unresolved module paths`);
      const items=list(body);
      for(const finding of result.findings)items.append(button(`${finding.severity.toUpperCase()} ${finding.file}:${finding.line} — ${finding.message}`,()=>{closeModal();openFile(finding.file);editor.selectLine(finding.line);}));
      if(!result.findings.length)items.append(element('p','No issues detected by these conservative checks.','v3-muted'));
      if(result.truncated)row(body,'The report is capped; additional findings may exist.');
      body.append(button('Check current file with Luau WASM',()=>{closeModal();checkCurrent();},'dialog-cta'));
    });
  }
  function format() {
    modal('Safe whitespace cleanup',body=>{
      row(body,'Normalizes line endings, removes trailing whitespace outside string content and ensures a final newline. Does not reflow assignments or modify indentation.');
      const file=workspace.project.active;
      const before=workspace.project.files[file],after=formatWhitespace(before);
      const changed=before!==after;
      row(body,changed?`Ready to clean ${file} (${before.length} → ${after.length} characters). A snapshot is created before changing code.`:'No whitespace changes needed.');
      if(!changed)return;
      body.append(button('Review diff',()=>showDiff(before,after,`Whitespace preview · ${file}`),'dialog-row'));
      body.append(button('Create snapshot and apply',()=>{
        try{if(workspace.project.active!==file||workspace.project.files[file]!==before)throw Error('File changed since the preview. Reopen cleanup before applying.');workspace.snapshot();workspace.source(after);closeModal();notify('Whitespace cleaned; recovery snapshot saved.');}
        catch(err){showError(err);}
      },'dialog-cta'));
    });
  }
  function showDiff(before,after,title='Source diff') {
    const diff=compareSources(before,after);
    modal(title,body=>{
      row(body,diff.limited?diff.message:`${diff.before} → ${diff.after} lines. Green = added, red = removed. Unchanged context is collapsed.`);
      if(diff.limited)return;
      const items=list(body);
      let skipped=false;
      for(const part of diff.changes){
        if(part.kind==='same') {if(!skipped){items.append(element('div','⋯ unchanged lines ⋯','v3-muted'));skipped=true;}continue;}
        skipped=false;
        items.append(element('div',`${part.kind==='added'?'+':'−'} ${part.line}  ${part.text}`,'v3-item v3-diff-'+part.kind));
      }
      if(diff.truncated)row(body,'Diff truncated to the first 240 lines of output.');
      if(!diff.changes.some(x=>x.kind!=='same'))row(body,'Files have identical content.');
    });
  }
  function compare() {
    modal('Compare workspace files',body=>{
      row(body,'Compare the current file against another project file (up to 320 lines each). No files are modified.');
      const files=Object.keys(workspace.project.files).filter(x=>x!==workspace.project.active).sort();
      if(!files.length)return row(body,'Create another file first.');
      const input=element('select',undefined,'v3-input');for(const filename of files){const option=element('option',filename);option.value=filename;input.append(option);}body.append(input);
      body.append(button('Compare selected files',()=>showDiff(workspace.project.files[input.value],workspace.project.files[workspace.project.active],`${input.value} → ${workspace.project.active}`),'dialog-cta'));
    });
  }
  function lockExport() {
    try {const pins=readGithubPins(),lock=createLockfile(workspace.project.files,pins,{projectName:workspace.project.name});
      download('luauforge.lock.json',JSON.stringify(lock,null,2)+'\n','application/json');notify(`Exported lockfile for ${pins.length} pinned GitHub modules.`);
    }catch(err){showError(err);}
  }
  function lockImport() {
    modal('Review module lockfile',body=>{
      row(body,'Paste a LuauForge lockfile to inspect its immutable module pins. Imports are not installed or executed automatically. Each must be reviewed individually.');
      const input=element('textarea',undefined,'v3-input');input.rows=5;input.placeholder='{ "schema": "luauforge-lockfile", ... }';body.append(input);
      const items=list(body);
      body.append(button('Inspect lockfile',()=>{
        items.replaceChildren();let manifest;try{manifest=parseLockfile(input.value);}catch(err){return showError(err);}
        if(!manifest.packages.length)return items.append(element('p','No public module pins in this lockfile.','v3-muted'));
        for(const pin of manifest.packages){
          items.append(button(`Preview ${pin.specifier} @ ${pin.sha.slice(0,12)}`,async()=>{
            try{
              const source=await previewGithubModule(`https://github.com/${pin.specifier.slice(1).split('/').slice(0,2).join('/')}/blob/${pin.sha}/${pin.specifier.slice(1).split('/').slice(2).join('/')}`);
              if(source.sha!==pin.sha.toLowerCase()||source.specifier!==pin.specifier)throw Error('Resolved source does not match the lockfile path and commit.');
              if(pin.size && source.size!==pin.size)throw Error('Source file size differs from the reviewed lockfile.');
              modal('Review imported source',review=>{
                row(review,`${pin.specifier} · exact commit ${pin.sha} · ${source.size} bytes${source.studioOnly?' · Studio only':''}`);
                const pre=element('pre',source.source.slice(0,50000),'github-source-preview');review.append(pre);
                const approval=element('label',undefined,'github-consent');const check=element('input');check.type='checkbox';approval.append(check,document.createTextNode('I reviewed and trust this exact commit.'));review.append(approval);
                const commit=button('Pin approved source',()=>{
                  try{if(!check.checked)throw Error('Review and approve the module before importing.');const saved=saveGithubPin(source);renderLibrary();closeModal();importGithubSpecifier(saved.specifier,saved.path.split('/').at(-1).replace(/\.luau?$/i,''));notify('Pinned reviewed module.');}
                  catch(err){showError(err);}
                },'dialog-cta');commit.disabled=source.studioOnly;review.append(commit);
              });
            }catch(err){showError(err);}
          }));
        }
      },'dialog-cta'));
    });
  }
  function report() {
    try{download('luauforge-project-report.md',projectReport(workspace.project,readGithubPins()),'text/markdown');notify('Downloaded project report.');}
    catch(err){showError(err);}
  }
  function githubStatus() {
    modal('Public GitHub Actions status',body=>{
      row(body,'Read-only status for a public GitHub repository. No account tokens or private data are required.');
      const input=field(body,'Owner/Repository','SillyDev2026/Luau-Developer-Playground');const items=list(body);
      body.append(button('Check recent workflows',async()=>{
        items.replaceChildren();const repo=input.value.trim();if(!/^[A-Za-z\d-]{1,39}\/[A-Za-z\d_.-]{1,100}$/.test(repo))return showError(new Error('Use Owner/Repository.'));
        const action=body.querySelector('.dialog-cta');action.disabled=true;
        try{const r=await fetch(`https://api.github.com/repos/${repo}/actions/runs?per_page=10`,{headers:{Accept:'application/vnd.github+json'},signal:AbortSignal.timeout(12000)});
          if(!r.ok)throw Error(`Public GitHub workflow status HTTP ${r.status}.`);
          const data=await r.json();for(const run of (data.workflow_runs||[]).slice(0,10)) {
            const url=new URL(run.html_url||'https://github.com');if(url.hostname!=='github.com')continue;
            items.append(button(`${run.name||'Workflow'} · ${run.conclusion||run.status} · ${new Date(run.created_at).toLocaleString()}`,()=>window.open(url.href,'_blank','noopener,noreferrer')));
          }
          if(!items.children.length)row(items,'No public workflow runs found.');
        }catch(err){showError(err);}finally{action.disabled=false;}
      },'dialog-cta'));
    });
  }
  function shortcuts() {
    modal('Keyboard shortcuts and navigation',body=>{
      for(const [keys,what] of [['Ctrl / Cmd + P','Open command palette'],['Ctrl / Cmd + Enter','Run current Luau file'],['Ctrl / Cmd + S','Save workspace'],['Ctrl / Cmd + F','Find in current file'],['Ctrl / Cmd + B','Open module benchmark'],['F12','Go to declaration (supported symbols)'],['Escape','Close open dialog or mobile drawer']])row(body,`${keys} — ${what}`);
      row(body,'Phone users can access these tools in Settings → V3 Workbench; no desktop keyboard is required.');
    });
  }
  const actions=[
    ['Search all files',search],['Review project quality',audit],['Safe source cleanup',format],['Compare two files',compare],
    ['Export module lockfile',lockExport],['Review / import lockfile',lockImport],['Export project report',report],
    ['GitHub build status',githubStatus],['Run project tests',runTests],['Check Luau types',checkCurrent],
    ['Add GitHub module',addPublicGithubModule],['View modules',()=>setSide('libraries')],['Keyboard shortcuts',shortcuts]
  ];
  const root=$('v3-actions');
  if(root)for(const [name,fn] of actions)root.append(button(name,()=>{try{fn();}catch(err){showError(err);}},''));
  return { actions, search, audit, format, compare, lockExport, lockImport, report, githubStatus, shortcuts };
}
