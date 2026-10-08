import { BUILTIN_LIBRARIES } from './builtin-libraries.js';

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
export function mountAutoRequire({editor,getProject,notify}) {
  const parent=editor.parentElement;
  const menu=document.createElement('div');
  menu.id='auto-require-menu'; menu.className='auto-require-menu hidden'; menu.setAttribute('role','listbox');
  menu.setAttribute('aria-label','AutoRequire and API suggestions');
  parent.append(menu);
  const setting=document.createElement('div');
  setting.className='setting-group';
  const heading=document.createElement('div'); heading.className='setting-heading'; heading.textContent='AUTO REQUIRE';
  const label=document.createElement('label'); label.className='auto-require-setting';
  const toggle=document.createElement('input'); toggle.type='checkbox';
  const key='luauforge:auto-require';
  let enabled=true;
  try{enabled=localStorage.getItem(key)!=='false';}catch{}
  toggle.checked=enabled;
  const copy=document.createElement('span'); copy.textContent='Slash commands and API suggestions';
  label.append(toggle,copy);
  const hint=document.createElement('small');
  hint.textContent='Type /Fast, /Nano, /Omega or /Module on a new line. Enter/Tab to insert. FastME. opens API completions.';
  setting.append(heading,label,hint);
  const inspector=document.querySelector('#inspector .setting-group');
  inspector?.before(setting);
  let options=null,selected=0;
  function hide(){options=null; menu.replaceChildren(); menu.classList.add('hidden'); editor.setAttribute('aria-expanded','false');}
  function update() {
    const project=getProject();
    if(!enabled || editor.selectionStart!==editor.selectionEnd || editor.dataset.path!==project.active){hide();return;}
    options=suggestions(editor.value,editor.selectionStart,project.files,project.active);
    if(!options){hide();return;}
    selected=Math.min(selected,options.items.length-1);
    menu.replaceChildren();
    const head=document.createElement('div');head.className='auto-require-caption';head.textContent=options.mode==='require'?'AUTO REQUIRE • Enter / Tab':'API COMPLETION • Enter / Tab';menu.append(head);
    options.items.forEach((item,index)=>{
      const row=document.createElement('button');row.type='button';row.className='auto-require-option'+(index===selected?' selected':'');row.setAttribute('role','option');
      const name=document.createElement('span');name.textContent=item.label;
      const detail=document.createElement('small');detail.textContent=item.detail;
      row.append(name,detail);
      row.addEventListener('pointerdown',event=>event.preventDefault());
      row.addEventListener('click',()=>choose(index));
      menu.append(row);
    });
    menu.classList.remove('hidden'); editor.setAttribute('aria-expanded','true');
  }
  function choose(index=selected) {
    if(!options?.items[index])return;
    const project=getProject(),item=options.items[index];
    const result=complete(editor.value,editor.selectionStart,item,project.files,project.active);
    if(!result){hide();return;}
    editor.value=result.source;
    editor.setSelectionRange(result.cursor,result.cursor);
    editor.dispatchEvent(new Event('input',{bubbles:true}));
    hide();editor.focus();
    if(item.kind!=='method')notify(result.created?'Module imported: '+result.variable:'Reused existing import: '+result.variable);
  }
  editor.addEventListener('input',update);
  editor.addEventListener('click',update);
  editor.addEventListener('keyup',update);
  editor.addEventListener('keydown',event=>{
    if(!options || event.isComposing || !['ArrowDown','ArrowUp','Enter','Tab','Escape'].includes(event.key))return;
    event.preventDefault();event.stopImmediatePropagation();
    if(event.key==='Escape')hide();
    else if(event.key==='ArrowDown'||event.key==='ArrowUp'){selected=(selected+(event.key==='ArrowDown'?1:-1)+options.items.length)%options.items.length;update();}
    else choose();
  },true);
  toggle.addEventListener('change',()=>{enabled=toggle.checked;try{localStorage.setItem(key,String(enabled));}catch{}if(!enabled)hide();else update();});
  document.addEventListener('click',event=>{if(event.target!==editor && !menu.contains(event.target))hide();});
  // Catalog buttons retain their full documentation action; add direct Import buttons.
  const catalog=document.querySelector('#builtin-catalog');
  if(catalog)for(const [index,lib]of BUILTIN_LIBRARIES.entries()){
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
  return {update,hide};
}