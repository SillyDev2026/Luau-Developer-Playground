// Offline, workspace-aware hover signatures. This is advisory source analysis,
// not a substitute for the Luau type checker.
import { maskLuau, localsInScope } from './intellisense.js?v=0.4.0';
import { DEFAULT_PARENTS, getRobloxAPI } from './roblox-api.js?v=0.4.0';
import { BUILTIN_LIBRARIES } from './builtin-libraries.js';

function tokenAt(source, offset) {
  if (!Number.isInteger(offset) || offset<0 || offset>=source.length) return null;
  const masked=maskLuau(source);
  if (!/[A-Za-z_0-9]/.test(masked[offset])) return null;
  let start=offset,end=offset+1;
  while(start>0 && /\w/.test(masked[start-1]))start--;
  while(end<masked.length && /\w/.test(masked[end]))end++;
  const token=masked.slice(start,end);
  if(!/^[A-Za-z_]\w*$/.test(token))return null;
  const head=masked.slice(0,start);
  const member=head.match(/([A-Za-z_]\w*(?:[.:][A-Za-z_]\w*)*)\s*([.:])\s*$/);
  return {token,start,end,expression:member?member[1]+member[2]+token:token,base:member?.[1]||''};
}

function matchingParen(masked, open) {
  let depth=0;
  for(let i=open;i<masked.length;i++){
    if(masked[i]==='(')depth++;
    else if(masked[i]===')' && --depth===0)return i;
  }
  return -1;
}

function sourceSignatures(source) {
  const clean=maskLuau(source),out=[];
  const patterns=[
    /\b(?:local\s+)?function\s+([A-Za-z_]\w*(?:[.:][A-Za-z_]\w*)*)\s*\(/g,
    /\b([A-Za-z_]\w*(?:[.:][A-Za-z_]\w*)*)\s*=\s*function\s*\(/g
  ];
  for(const pattern of patterns)for(const m of clean.matchAll(pattern)){
    const open=m.index+m[0].lastIndexOf('('),close=matchingParen(clean,open);
    if(close<0)continue;
    const after=source.slice(close+1).split('\n')[0];
    const returnType=after.match(/^\s*:\s*([^\n;]+?)(?=\s*(?:--|$))/)?.[1]?.trim()||'';
    const label=m[1].split(/[.:]/).at(-1);
    out.push({name:m[1].replaceAll(':','.'),signature:label+'('+source.slice(open+1,close)+')'+(returnType?': '+returnType:''),position:m.index});
  }
  return out;
}

function memberSignature(api, type, member) {
  const standard=(api?.standard?.[type]||[]).find(x=>x[0]===member && x[1]==='function');
  if(standard)return standard[2];
  const seen=new Set();
  while(type&&!seen.has(type)){
    seen.add(type);
    const entry=api?.classes?.[type],members=Array.isArray(entry)?entry:entry?.members||[];
    const found=members.find(x=>x[0]===member && x[1]==='function');
    if(found)return found[2];
    type=entry?.parent||DEFAULT_PARENTS[type];
  }
  return '';
}

function normalize(path) {
  const parts=[];
  for(const part of path.replace(/\\/g,'/').split('/')){
    if(!part||part==='.')continue;
    if(part==='..'){if(!parts.length)return null;parts.pop();}
    else parts.push(part);
  }
  return parts.join('/');
}

export function importedModule(source,base,cursor,project) {
  if(!project?.files)return null;
  const clean=maskLuau(source);
  const pattern=/\blocal\s+([A-Za-z_]\w*)\s*=\s*require\s*\(\s*(["'])([^"'\n]+)\2\s*\)/g;
  let specifier='';
  for(const m of source.matchAll(pattern)){
    if(m.index>=cursor)break;
    if(clean.slice(m.index,m.index+5)!=='local'||m[1]!==base)continue;
    specifier=m[3];
  }
  if(!specifier)return null;
  if(specifier.startsWith('@'))return {kind:'builtin',specifier};
  if(!specifier.startsWith('.'))return null;
  const current=project.active||'main.luau';
  const basePath=normalize(current.split('/').slice(0,-1).concat(specifier.split('/')).join('/'));
  if(!basePath)return null;
  const candidates=[basePath,basePath+'.luau',basePath+'.lua',basePath+'/init.luau',basePath+'/init.lua'];
  const path=candidates.find(x=>Object.hasOwn(project.files,x));
  return path?{kind:'file',path,source:project.files[path]}:null;
}

function exportedName(source) {
  const clean=maskLuau(source);
  return clean.match(/\breturn\s+([A-Za-z_]\w*)\s*(?:;?\s*)$/)?.[1]||'';
}

function exportedSignatures(source) {
  const clean=maskLuau(source),returned=exportedName(source);
  const entries=sourceSignatures(source);
  if(returned)return entries.filter(entry=>entry.name.startsWith(returned+'.') && !entry.name.slice(returned.length+1).includes('.'));
  // A module returning a function-valued table literal can also provide API
  // signatures. Never expose private helper functions by default.
  const expression=/\breturn\s*\{([\s\S]*?)\}\s*;?\s*$/.exec(clean);
  if(!expression)return [];
  const names=new Set([...expression[1].matchAll(/(?:^|[,;\n])\s*([A-Za-z_]\w*)\s*=/g)].map(x=>x[1]));
  return entries.filter(entry=>!entry.name.includes('.') && names.has(entry.name));
}

export function moduleMemberCompletions(source,cursor,context,project) {
  if(context?.mode!=='member' || !/^[A-Za-z_]\w*$/.test(context.base||''))return [];
  const imported=importedModule(source,context.base,cursor,project);
  if(imported?.kind!=='file')return [];
  const query=context.query.toLowerCase();
  return exportedSignatures(imported.source)
    .map(entry=>({label:entry.name.split('.').at(-1),kind:'function',detail:entry.signature+' · '+imported.path,origin:imported.path,score:0}))
    .filter(item=>(context.separator!==':'||item.kind==='function') && item.label.toLowerCase().startsWith(query))
    .map(item=>({...item,score:item.label.toLowerCase()===query?115:85}))
    .sort((a,b)=>b.score-a.score||a.label.localeCompare(b.label)).slice(0,12);
}

export function lookupSignature(name,source,cursor,project,api=getRobloxAPI()) {
  if(!/^[A-Za-z_]\w*(?:[.:][A-Za-z_]\w*)*$/.test(name))return null;
  const normalized=name.replaceAll(':','.');
  const entries=sourceSignatures(source);
  const direct=entries.findLast(x=>x.name===normalized);
  if(direct)return {signature:direct.signature,origin:project?.active||'Current file'};
  const parts=normalized.split('.');
  if(parts.length===1){
    const local=entries.findLast(x=>x.name===parts[0]);
    return local?{signature:local.signature,origin:project?.active||'Current file'}:null;
  }
  const root=parts[0],method=parts.at(-1);
  const imported=importedModule(source,root,cursor,project);
  if(imported?.kind==='builtin'){
    const library=BUILTIN_LIBRARIES.find(x=>'@'+x.id===imported.specifier);
    const entry=library?.categories.flatMap(x=>x.methods).find(x=>x.startsWith(method+'('));
    if(entry)return {signature:entry,origin:library.label+' · bundled API'};
  }
  if(imported?.kind==='file'){
    const found=exportedSignatures(imported.source).findLast(x=>x.name.split('.').at(-1)===method);
    if(found)return {signature:found.signature,origin:imported.path};
  }
  const symbols=localsInScope(source,cursor);
  const aliases={game:'DataModel',workspace:'Workspace',Instance:'Instance',math:'math',table:'table',string:'string',buffer:'buffer',task:'task',Vector3:'Vector3',Vector2:'Vector2',CFrame:'CFrame',Color3:'Color3'};
  const type=symbols.find(x=>x.name===root)?.type||aliases[root]||root;
  const signature=memberSignature(api,type,method);
  return signature?{signature,origin:type+' · Luau / Roblox API'}:null;
}

export function hoverAt(source,offset,project,api=getRobloxAPI()) {
  const token=tokenAt(source,offset);
  if(!token)return null;
  const result=lookupSignature(token.expression,source,token.start,project,api);
  return result?{...result,token:token.token,start:token.start,end:token.end}:null;
}

// Textarea source index for a pointer coordinate. Editors use a monospace font
// and wrap=off; tab stops follow the CSS tab-size, including scrolled content.
export function sourceOffsetAtPoint(source,point,metrics) {
  const line=Math.floor((point.y+metrics.scrollTop-metrics.paddingTop)/metrics.lineHeight);
  if(line<0)return null;
  let start=0;
  for(let i=0;i<line;i++){
    const end=source.indexOf('\n',start);
    if(end<0)return null;
    start=end+1;
  }
  const end=source.indexOf('\n',start),last=end<0?source.length:end;
  const col=(point.x+metrics.scrollLeft-metrics.paddingLeft)/metrics.charWidth;
  if(col<0)return null;
  let cells=0;
  for(let i=start;i<last;i++){
    const width=source[i]==='\t'?metrics.tabSize-(cells%metrics.tabSize):1;
    if(col>=cells&&col<cells+width)return i;
    cells+=width;
  }
  return null;
}
