import { textareaCaretOffset, placeCompletionPopup } from './completion-geometry.js';
import { BUILTIN_LIBRARIES } from './builtin-libraries.js';
import { githubModuleTargets } from './github-modules.js';
import { getRobloxAPI, loadRobloxAPI } from './roblox-api.js?v=0.4.0';
import { staticCompletions, applyCompletion, mergeCompletions, completionContext, localsInScope, GLOBALS } from './intellisense.js?v=0.4.0';
import { signatureFor, formatSignature, definitionAt } from './editor-intelligence.js?v=0.4.0';

const reserved = new Set('and break continue do else elseif end false for function if in local nil not or repeat return then true until while'.split(' '));
const safeVar = label => {
  let name = label.replace(/[^A-Za-z0-9_]/g, '_');
  if (!/^[A-Za-z_]/.test(name)) name = 'Module_' + name;
  return reserved.has(name) ? name + 'Module' : name;
};
const relative = (from, target) => {
  const a = from.split('/').slice(0,-1), b = target.split('/');
  while (a.length && b.length && a[0] === b[0]) { a.shift(); b.shift(); }
  const path = [...a.map(()=>'..'), ...b].join('/');
  return path.startsWith('.') ? path : './' + path;
};
const fuzzy = (q, word) => {
  q = q.toLowerCase(); word = word.toLowerCase();
  if (!q) return 1;
  if (word === q) return 100;
  if (word.startsWith(q)) return 80;
  if (word.includes(q)) return 55;
  let at = -1, score = 0;
  for (const c of q) { at = word.indexOf(c, at+1); if (at < 0) return 0; score++; }
  return score;
};
export function targets(files, active) {
  return [
    ...BUILTIN_LIBRARIES.map(lib=>({kind:'builtin',id:lib.id,label:lib.label,variable:lib.local,specifier:'@'+lib.id,detail:'Bundled v'+lib.version})),
    ...githubModuleTargets().map(lib=>({kind:'github',id:lib.specifier,label:lib.label,variable:safeVar(lib.label),specifier:lib.specifier,detail:'Public GitHub · '+(lib.description||'pinned')})),
    ...Object.keys(files).filter(path=>path!==active && /\.lua(u)?$/i.test(path)).map(path=>({kind:'module',id:path,label:path.split('/').at(-1).replace(/\.lua(u)?$/i,''),variable:safeVar(path.split('/').at(-1).replace(/\.lua(u)?$/i,'')),specifier:relative(active,path),detail:path}))
  ];
}
export function slashAt(source, cursor) {
  if (cursor < 0 || cursor > source.length) return null;
  const from = source.lastIndexOf('\n',cursor-1)+1;
  const match = source.slice(from,cursor).match(/^([ \t]*)\/([\w./-]*)$/);
  return match ? {from:from+match[1].length,to:cursor,query:match[2]} : null;
}
export function boundVariable(source, specifier) {
  for (const match of source.matchAll(/^[ \t]*local[ \t]+([A-Za-z_]\w*)[ \t]*=[ \t]*require[ \t]*\([ \t]*(["'])([^\n"']+)\2[ \t]*\)/gm)) {
    if (match[3] === specifier) return match[1];
  }
  return null;
}
export function suggestions(source,cursor,files,active) {
  const slash=slashAt(source,cursor);
  if (slash) {
    const items=targets(files,active).map(item=>({...item,score:Math.max(fuzzy(slash.query,item.label),fuzzy(slash.query,item.id),fuzzy(slash.query,item.detail))})).filter(item=>item.score>0).sort((a,b)=>b.score-a.score||a.id.localeCompare(b.id)).slice(0,9);
    return items.length?{mode:'require',from:slash.from,to:slash.to,items}:null;
  }
  const from=source.lastIndexOf('\n',cursor-1)+1;
  const match=source.slice(from,cursor).match(/(?:^|[^\w])([A-Za-z_]\w*)\.([A-Za-z_]\w*)?$/);
  if (!match) return null;
  const items=[];
  for (const lib of BUILTIN_LIBRARIES) {
    if (boundVariable(source,'@'+lib.id)!==match[1]) continue;
    for (const category of lib.categories) for (const signature of category.methods) {
      const method=signature.split('(')[0],score=fuzzy(match[2]||'',method);
      if(score) items.push({kind:'method',id:lib.id,label:signature,method,detail:category.name,score});
    }
  }
  items.sort((a,b)=>b.score-a.score||a.method.localeCompare(b.method));
  return items.length?{mode:'method',from:cursor-(match[2]||'').length,to:cursor,items:items.slice(0,9)}:null;
}
export function complete(source,cursor,choice,files,active) {
  const context=suggestions(source,cursor,files,active);
  if(!context) return null;
  if(choice.kind==='method') {
    const text=choice.method+'()';
    return {source:source.slice(0,context.from)+text+source.slice(context.to),cursor:context.from+text.length-1,created:false};
  }
  const found=targets(files,active).find(t=>t.kind===choice.kind && t.id===choice.id);
  if(!found || context.mode!=='require') return null;
  const existing=boundVariable(source,found.specifier);
  let variable=existing||found.variable;
  if(!existing) {
    const declared=new Set([...source.matchAll(/\blocal\s+([A-Za-z_]\w*)/g)].map(m=>m[1]));
    const name=variable; let suffix=2;
    while(declared.has(variable)) variable=name+suffix++;
  }
  const text=existing?variable:'local '+variable+' = require('+JSON.stringify(found.specifier)+')';
  return {source:source.slice(0,context.from)+text+source.slice(context.to),cursor:context.from+text.length,created:!existing,variable};
}
export function mountAutoRequire({editor,getProject,getRuntime,notify,catalogButtons=true}) {
  const parent=editor.parentElement;
  const menu=document.createElement('div');
  menu.id='auto-require-menu'; menu.className='auto-require-menu hidden'; menu.setAttribute('role','listbox');
  menu.setAttribute('aria-label','Luau IntelliSense, AutoRequire and Roblox API suggestions');
  parent.append(menu);
  const help=document.createElement('div');help.id='signature-help';help.className='signature-help hidden';help.setAttribute('role','status');help.setAttribute('aria-live','off');parent.append(help);
  const setting=document.createElement('div');
  setting.className='setting-group';
  const heading=document.createElement('div'); heading.className='setting-heading'; heading.textContent='INTELLISENSE + AUTO REQUIRE';
  const label=document.createElement('label'); label.className='auto-require-setting';
  const toggle=document.createElement('input'); toggle.type='checkbox';
  const key='luauforge:auto-require';
  let enabled=true;
  try{enabled=localStorage.getItem(key)!=='false';}catch{}
  toggle.checked=enabled;
  const copy=document.createElement('span'); copy.textContent='Local variables, type information, Roblox API and / imports';
  label.append(toggle,copy);
  const hint=document.createElement('small');
  hint.textContent='Type t to find local test; part. for members, Enum.Material. for enum values, or /Fast to import. Enter/Tab accepts.';
  setting.append(heading,label,hint);
  const inspector=document.querySelector('#inspector .setting-group');
  inspector?.before(setting);
  let options=null,selected=0,requestId=0,autoTimer=0;
  function positionSuggestions() {
    if(menu.classList.contains('hidden'))return;
    const caret=textareaCaretOffset(editor),position=placeCompletionPopup(caret,
      {width:parent.clientWidth,height:parent.clientHeight},
      {width:Math.min(425,parent.clientWidth-14),height:Math.min(menu.scrollHeight,290)});
    menu.style.left=`${position.left}px`;
    menu.style.top=`${position.top}px`;
    menu.style.width=`${position.width}px`;
    menu.style.maxHeight=`${position.height}px`;
    menu.dataset.placement=position.below?'below':'above';
  }
  const relocate=()=>{if(!menu.classList.contains('hidden'))positionSuggestions();};
  editor.addEventListener('scroll',relocate,{passive:true});
  window.addEventListener('resize',relocate,{passive:true});
  window.visualViewport?.addEventListener('resize',relocate,{passive:true});
  function updateSignature(){
    if(!enabled||editor.selectionStart!==editor.selectionEnd){help.classList.add('hidden');return;}
    const hint=signatureFor(editor.value,editor.selectionStart,getRobloxAPI());
    if(!hint){help.classList.add('hidden');return;}
    const parts=formatSignature(hint.signature,hint.activeParameter);
    const left=document.createElement('span');left.textContent=parts.before;
    const active=document.createElement('strong');active.textContent=parts.active;
    const right=document.createElement('span');right.textContent=parts.after;
    help.replaceChildren(left,active,right);help.classList.remove('hidden');
  }
  function goToDefinition(){
    const def=definitionAt(editor.value,editor.selectionStart);
    if(!def){notify('No visible local definition found for the current symbol.',true);return;}
    hide();editor.focus();editor.setSelectionRange(def.position,def.position+def.name.length);
    const lineHeight=parseFloat(getComputedStyle(editor).lineHeight)||23;
    editor.scrollTop=Math.max(0,(def.line-5)*lineHeight);
    notify('Definition: '+def.name+' · line '+def.line);
  }
  loadRobloxAPI().then(()=>{if(document.activeElement===editor)update();});
  function hide(){options=null;clearTimeout(autoTimer);requestId++;menu.replaceChildren();menu.classList.add('hidden');editor.setAttribute('aria-expanded','false');}
  function renderMenu() {
    if(!options?.items.length){menu.replaceChildren();menu.classList.add('hidden');editor.setAttribute('aria-expanded','false');return;}
    selected=Math.min(selected,options.items.length-1);
    menu.replaceChildren();
    const head=document.createElement('div');head.className='auto-require-caption';
    head.textContent=options.mode==='require'?'AUTO REQUIRE • Enter / Tab':options.mode==='method'?'LIBRARY API • Enter / Tab':'LUAU INTELLISENSE • Enter / Tab';
    menu.append(head);
    options.items.forEach((item,index)=>{
      const row=document.createElement('button');row.type='button';row.className='auto-require-option'+(index===selected?' selected':'');row.setAttribute('role','option');row.setAttribute('aria-selected',String(index===selected));
      const name=document.createElement('span');name.className='completion-name';name.textContent=item.label;
      const detail=document.createElement('small');detail.textContent=item.detail||item.kind;detail.title=item.detail||'';
      const kind=document.createElement('span');kind.className='completion-kind';kind.textContent=item.kind||'symbol';
      row.append(name,kind,detail);
      row.addEventListener('pointerdown',event=>event.preventDefault());
      row.addEventListener('click',()=>choose(index));
      menu.append(row);
    });
    menu.classList.remove('hidden');editor.setAttribute('aria-expanded','true');positionSuggestions();
  }
  function update(force=false) {
    updateSignature();
    const project=getProject();
    if(!enabled||editor.selectionStart!==editor.selectionEnd||editor.dataset.path!==project.active){hide();return;}
    const original=suggestions(editor.value,editor.selectionStart,project.files,project.active);
    // Slash imports always take priority. Documented builtin API method
    // completion takes priority over generic engine member inference.
    options=original||staticCompletions(editor.value,editor.selectionStart,getRobloxAPI());
    if(!options){const context=completionContext(editor.value,editor.selectionStart);if(context)options={...context,items:[]};}
    if(force && !options) {
      const from=editor.selectionStart;
      options={mode:'identifier',query:'',from,to:from,items:[...localsInScope(editor.value,from).map(x=>({label:x.name,kind:x.kind,detail:x.type||'local',score:100})),...GLOBALS.map(label=>({label,kind:'global',detail:'Luau / Roblox global',score:30}))].slice(0,12)};
    }
    if(!options){hide();return;}
    selected=0;renderMenu();
    clearTimeout(autoTimer);const generation=++requestId;
    if(original||!getRuntime||!['member','identifier','type'].includes(options.mode))return;
    const code=editor.value,cursor=editor.selectionStart,file=project.active;
    const snapshot={...project,files:{...project.files}};
    const completionMode=options.mode;
    const line=code.slice(0,cursor).split('\n');
    autoTimer=setTimeout(async()=>{
      try{
        const items=await getRuntime().autocomplete(snapshot,line.length-1,line.at(-1).length);
        if(generation!==requestId||editor.value!==code||editor.selectionStart!==cursor||getProject().active!==file||!options)return;
        if(options.mode!==completionMode)return;
        options=mergeCompletions(options,items);
        renderMenu();
      }catch{/* Local/Roblox suggestions remain usable without the WASM checker. */}
    },350);
  }
  function choose(index=selected) {
    if(!options?.items[index])return;
    const project=getProject(),item=options.items[index],wasImport=options.mode==='require';
    const result=options.mode==='require'||options.mode==='method' ? complete(editor.value,editor.selectionStart,item,project.files,project.active) : applyCompletion(editor.value,options,item);
    if(!result){hide();return;}
    editor.value=result.source;
    editor.setSelectionRange(result.cursor,result.cursor);
    editor.dispatchEvent(new Event('input',{bubbles:true}));
    hide();editor.focus();
    if(wasImport)notify(result.created?'Module imported: '+result.variable:'Reused existing import: '+result.variable);
  }
  editor.addEventListener('input',()=>update());
  editor.addEventListener('click',()=>update());
  editor.addEventListener('keyup',()=>update());
  editor.addEventListener('keydown',event=>{
    if(event.key==='F12'&&!event.shiftKey&&!event.ctrlKey&&!event.altKey){event.preventDefault();event.stopImmediatePropagation();goToDefinition();return;}
    if((event.ctrlKey||event.metaKey)&&event.key===' '){event.preventDefault();event.stopImmediatePropagation();update(true);return;}
    if(!options || event.isComposing || event.ctrlKey || event.altKey || event.metaKey || event.shiftKey || !['ArrowDown','ArrowUp','Enter','Tab','Escape'].includes(event.key))return;
    event.preventDefault();event.stopImmediatePropagation();
    if(event.key==='Escape')hide();
    else if(event.key==='ArrowDown'||event.key==='ArrowUp'){selected=(selected+(event.key==='ArrowDown'?1:-1)+options.items.length)%options.items.length;renderMenu();}
    else choose();
  },true);
  toggle.addEventListener('change',()=>{enabled=toggle.checked;try{localStorage.setItem(key,String(enabled));}catch{}if(!enabled)hide();else update();});
  document.addEventListener('click',event=>{if(event.target!==editor && !menu.contains(event.target))hide();});
  // Catalog buttons retain their full documentation action; add direct Import buttons.
  const catalog=document.querySelector('#builtin-catalog');
  if(catalog && catalogButtons)for(const [index,lib]of BUILTIN_LIBRARIES.entries()){
    const actions=catalog.querySelectorAll('.builtin-catalog-actions')[index];
    if(!actions)continue;
    const button=document.createElement('button');button.type='button';button.className='tiny-btn auto-import-button';button.textContent='Import';
    button.addEventListener('click',()=>{
      const project=getProject(),specifier='@'+lib.id;
      if(boundVariable(editor.value,specifier)){notify('Already imported');return;}
      const source=editor.value+(editor.value.endsWith('\n')?'':'\n')+'/'+lib.id;
      const item=targets(project.files,project.active).find(t=>t.id===lib.id&&t.kind==='builtin');
      const result=complete(source,source.length,item,project.files,project.active);
      if(!result)return;
      editor.value=result.source;editor.setSelectionRange(result.cursor,result.cursor);
      editor.dispatchEvent(new Event('input',{bubbles:true}));hide();editor.focus();notify('Module imported: '+result.variable);
    });
    actions.append(button);
  }
  return {update,hide,goToDefinition};
}