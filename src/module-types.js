// Lightweight offline Luau export-type index for local workspace modules.
// This does not evaluate source or replace Luau's authoritative type checker.
import { maskLuau, localsInScope } from './intellisense.js?v=0.4.0';
import { importedModule } from './symbol-hover.js';

const IDENT=/^[A-Za-z_]\w*$/;
function balancedEnd(clean,start,open='{',close='}') {
  if(clean[start]!==open)return -1;
  let depth=0;
  for(let i=start;i<clean.length;i++){
    if(clean[i]===open)depth++;
    else if(clean[i]===close && --depth===0)return i;
  }
  return -1;
}

function typeExpression(source,clean,start) {
  let i=start,started=false,depth=0;
  for(;i<clean.length;i++){
    const ch=clean[i];
    if(!started){
      if(/\s/.test(ch))continue;
      started=true;
    }
    if(ch==='{'||ch==='('||ch==='[')depth++;
    else if(ch==='}'||ch===')'||ch===']')depth=Math.max(0,depth-1);
    if(depth===0 && (ch==='\n'||ch===';'))break;
  }
  return source.slice(start,i).trim();
}

export function typeAliases(source) {
  const clean=maskLuau(source),aliases=new Map();
  const declarations=/^[ \t]*(export[ \t]+)?type[ \t]+([A-Za-z_]\w*)[ \t]*=[ \t]*/gm;
  for(const declaration of clean.matchAll(declarations)){
    const start=declaration.index+declaration[0].length;
    aliases.set(declaration[2],{name:declaration[2],exported:Boolean(declaration[1]),expression:typeExpression(source,clean,start),position:declaration.index});
  }
  return aliases;
}

function splitTable(source) {
  const clean=maskLuau(source);
  const start=clean.indexOf('{');
  if(start<0 || source.slice(0,start).trim())return [];
  const end=balancedEnd(clean,start);
  if(end<0)return [];
  const items=[];
  let from=start+1,depth=0;
  for(let i=from;i<=end;i++){
    const ch=clean[i];
    if(i===end || (depth===0 && (ch===','||ch===';'||ch==='\n'))){
      const value=source.slice(from,i).trim();
      if(value)items.push(value);
      from=i+1;
    }else if(ch==='{'||ch==='('||ch==='[')depth++;
    else if(ch==='}'||ch===')'||ch===']')depth=Math.max(0,depth-1);
  }
  return items;
}

function tableMembers(source,mode) {
  const fields=new Map();
  for(const segment of splitTable(source)){
    const match=mode==='type'
      ? /^(?:readonly\s+)?([A-Za-z_]\w*)(\?)?\s*:\s*([\s\S]+)$/.exec(segment)
      : /^([A-Za-z_]\w*)\s*=\s*([\s\S]+)$/.exec(segment);
    if(!match)continue;
    const name=match[1],optional=mode==='type'&&Boolean(match[2]);
    const value=mode==='type'?match[3].trim():match[2].trim();
    let kind='property',detail=name+(optional?'?':'')+': ';
    let nested=null;
    if(value.startsWith('{')){
      nested=tableMembers(value,mode);
      detail+=mode==='type'?value:'table';
    }else if(mode==='type'){
      if(/^\([^)]*\)\s*->/.test(value)){kind='function';detail=name+': '+value;}
      else detail+=value;
    }else{
      const inferred=/^[-+]?(?:\d|0[xX])/.test(value)?'number':/^(?:true|false)\b/.test(value)?'boolean':
        /^(?:"|'|\x60|\[(?:=*)\[)/.test(value)?'string':/^(?:function\b|\([^)]*\)\s*->)/.test(value)?'function':'unknown';
      if(inferred==='function')kind='function';
      detail+=inferred;
    }
    fields.set(name,{name,kind,detail,nested});
  }
  return fields;
}

function localInitializer(source,name,limit=source.length) {
  const clean=maskLuau(source);
  const re=new RegExp('^[ \\t]*local[ \\t]+'+name+'(?:[ \\t]*:[^=\\n]+)?[ \\t]*=[ \\t]*','gm');
  let result=null;
  for(const match of clean.matchAll(re)){
    if(match.index>=limit)break;
    const start=match.index+match[0].length;
    if(clean[start]!=='{')continue;
    const end=balancedEnd(clean,start);
    if(end>=0)result=tableMembers(source.slice(start,end+1),'value');
  }
  return result;
}

function resolveType(expression,moduleSource,aliases,seen=new Set()) {
  const value=expression.trim().replace(/\?$/,'').trim();
  if(value.startsWith('{'))return tableMembers(value,'type');
  const typeofMatch=/^typeof\s*\(\s*([A-Za-z_]\w*)\s*\)$/.exec(value);
  if(typeofMatch)return localInitializer(moduleSource,typeofMatch[1]);
  const reference=/^([A-Za-z_]\w*)$/.exec(value);
  if(reference && !seen.has(reference[1])){
    const alias=aliases.get(reference[1]);
    if(alias){
      seen.add(reference[1]);
      return resolveType(alias.expression,moduleSource,aliases,seen);
    }
  }
  return null;
}

// A private alias may define a public export, but it cannot be imported by name.
export function exportedTypeNames(moduleSource) {
  return [...typeAliases(moduleSource).values()].filter(x=>x.exported).map(x=>x.name);
}

export function exportedTypeMembers(moduleSource,name) {
  const aliases=typeAliases(moduleSource);
  const alias=aliases.get(name);
  return alias?.exported?resolveType(alias.expression,moduleSource,aliases):null;
}

function completions(fields,query,separator='.') {
  const q=query.toLowerCase();
  return [...(fields?.values()||[])]
    .filter(field=>(separator!==':'||field.kind==='function') && field.name.toLowerCase().startsWith(q))
    .map(field=>({label:field.name,kind:field.kind,detail:field.detail,score:field.name.toLowerCase()===q?110:80}))
    .sort((a,b)=>b.score-a.score||a.label.localeCompare(b.label)).slice(0,12);
}

export function workspaceTypeSuggestions(source,cursor,context,project) {
  if(!context || !project?.files)return null;
  if(context.mode==='type-member'){
    const imported=importedModule(source,context.base,cursor,project);
    if(imported?.kind!=='file')return {items:[],authoritative:true};
    const q=context.query.toLowerCase();
    const items=exportedTypeNames(imported.source).filter(name=>name.toLowerCase().startsWith(q))
      .map(label=>({label,kind:'type',detail:imported.path+' · exported Luau type',score:label.toLowerCase()===q?110:80}));
    return {items,authoritative:true};
  }
  if(context.mode!=='member')return null;
  const parts=context.base.split('.');
  const variable=localsInScope(source,cursor).find(x=>x.name===parts[0]);
  const type=variable?.type?.match(/^([A-Za-z_]\w*)\.([A-Za-z_]\w*)\??$/);
  let fields=null,authoritative=false;
  if(type){
    const imported=importedModule(source,type[1],cursor,project);
    if(imported?.kind==='file'){
      authoritative=true;
      fields=exportedTypeMembers(imported.source,type[2]);
    }
  }else if(variable?.type && IDENT.test(variable.type)){
    const aliases=typeAliases(source),alias=aliases.get(variable.type);
    if(alias){
      authoritative=true;
      fields=resolveType(alias.expression,source,aliases);
    }
  }
  if(!authoritative)return null;
  for(const name of parts.slice(1))fields=fields?.get(name)?.nested||null;
  return {items:completions(fields,context.query,context.separator),authoritative:true};
}
