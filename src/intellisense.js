import { DEFAULT_PARENTS } from './roblox-api.js?v=0.4.0';
// Lightweight lexical completions run immediately; WASM Luau type information
// augments these asynchronously. Locals are lexical, NOT globals.
const KEYWORDS = 'and break continue do else elseif end export false for function if in local nil not or repeat return then true type typeof until while'.split(' ');
export const GLOBALS = ['print','warn','assert','error','require','type','typeof','tostring','tonumber','pairs','ipairs','next','select','pcall','xpcall','setmetatable','getmetatable','rawget','rawset','rawequal','unpack','math','string','table','buffer','utf8','bit32','coroutine','os','debug','task','Enum','Instance','Vector3','Vector2','CFrame','Color3','UDim2','UDim','BrickColor','RaycastParams','OverlapParams','Random','game','workspace','script','plugin'];

export function maskLuau(source) {
  // Preserve string contents' positions, mask comments and strings so phantom
  // declarations inside quoted text/comments do not pollute symbol completion.
  let output = '', i = 0;
  while (i < source.length) {
    if (source.startsWith('--',i)) {
      const block = source.slice(i).match(/^--\[(=*)\[/);
      if (block) {
        const close = ']' + block[1] + ']';
        const at = source.indexOf(close,i+block[0].length);
        const end = at < 0 ? source.length : at+close.length;
        output += source.slice(i,end).replace(/[^\n]/g,' ');i=end;continue;
      }
      const end = source.indexOf('\n',i);
      const last = end<0?source.length:end;
      output += ' '.repeat(last-i);i=last;continue;
    }
    const ch=source[i];
    if(ch==='\"'||ch==="'"||ch==='`'){
      const quote=ch;let j=i+1;
      while(j<source.length){if(source[j]==='\\'){j+=2;continue;}if(source[j]===quote){j++;break;}j++;}
      output+=source.slice(i,j).replace(/[^\n]/g,' ');i=j;continue;
    }
    output+=ch;i++;
  }
  return output;
}

function detectType(rhs, symbols) {
  if(!rhs) return '';
  const expr=rhs.trim();
  if (/^game\s*:\s*GetService\s*\(\s*["']([\w]+)["']/.test(expr)) return expr.match(/GetService\s*\(\s*["']([\w]+)["']/)[1];
  if (/^Instance\.new\s*\(\s*["']([\w]+)["']/.test(expr)) return expr.match(/Instance\.new\s*\(\s*["']([\w]+)["']/)[1];
  const constructor=expr.match(/^([A-Za-z_]\w*)\.new\s*\(/);
  if(constructor)return constructor[1];
  if (/^\{/.test(expr)) return 'table';
  if (/^["'`]/.test(expr)) return 'string';
  if (/^[-+]?\d/.test(expr)) return 'number';
  if (/^(?:true|false)\b/.test(expr)) return 'boolean';
  const reference=expr.match(/^([A-Za-z_]\w*)\b/);
  if(reference) return symbols.get(reference[1])?.type || (reference[1]==='workspace'?'Workspace':'');
  return '';
}

function tableFields(source, declarationEnd) {
  const fragment=source.slice(declarationEnd).trimStart();
  if(!fragment.startsWith('{')) return [];
  const until=fragment.indexOf('}');
  if(until<0 || until>4000)return [];
  return [...fragment.slice(1,until).matchAll(/(?:^|[,;\n])\s*([A-Za-z_]\w*)\s*=/g)].map(x=>x[1]);
}

export function localsInScope(source, cursor) {
  const masked=maskLuau(source), before=masked.slice(0,cursor);
  const original=source.slice(0,cursor);
  const lines=before.split('\n'), originalLines=original.split('\n');
  const scopes=[new Map()], names=()=>new Map(scopes.flatMap(s=>[...s]));
  const add=(name,type='',kind='local',fields=[])=>{if(/^[A-Za-z_]\w*$/.test(name))scopes.at(-1).set(name,{name,type,kind,fields});};
  for(let n=0;n<lines.length;n++){
    const line=lines[n], raw=originalLines[n];
    // A closing token ends the current lexical scope. Elseif/else introduce a
    // fresh sibling branch; symbols in another branch must not leak into it.
    if(/^\s*(?:end\b|until\b)/.test(line)) {if(scopes.length>1) scopes.pop();continue;}
    if(/^\s*(?:else\b|elseif\b)/.test(line)) {if(scopes.length>1)scopes.pop();scopes.push(new Map());continue;}
    const fn=line.match(/^\s*(local\s+)?function\s+([\w.:]+)\s*\(([^)]*)\)/);
    if(fn){
      if(fn[1])add(fn[2], 'function','function');
      scopes.push(new Map());
      for(const param of fn[3].split(',')){
        const match=param.match(/^\s*([A-Za-z_]\w*)\s*(?::\s*([\w.?]+))?/);
        if(match)add(match[1], match[2]||'', 'parameter');
      }
      continue;
    }
    const loop=line.match(/^\s*for\s+(.+?)\s+(?:in\b|=)/);
    if(loop){scopes.push(new Map());for(const segment of loop[1].split(',')){const v=segment.trim();if(/^[A-Za-z_]\w*$/.test(v))add(v,'number','loop');}continue;}
    if(/^\s*(?:if\b.*\bthen\s*$|while\b.*\bdo\s*$|repeat\b|do\s*$)/.test(line)) {scopes.push(new Map());continue;}
    const local=line.match(/^\s*local\s+(?!function\b)([A-Za-z_]\w*)\s*(?::\s*([\w.?]+))?\s*(=\s*)?/);
    if(local){
      const start=local[0].length;
      const rhs=local[3]?raw.slice(start):'';
      const typed=local[2]||detectType(rhs,names());
      add(local[1],typed,'local',/^\s*\{/.test(rhs)?tableFields(rhs,0):[]);
      // Support local a, b and local a, b = ... in a single line.
      const tail=line.slice(start);
      if(!local[3] && /^\s*,/.test(tail))for(const extra of tail.split('=')[0].split(',').slice(1)){
        const v=extra.match(/^\s*([A-Za-z_]\w*)\s*(?::\s*([\w.?]+))?/);
        if(v)add(v[1],v[2]||'','local');
      }
      continue;
    }
    const typeAlias=line.match(/^\s*(?:export\s+)?type\s+([A-Za-z_]\w*)\s*=/);
    if(typeAlias) add(typeAlias[1], 'type','type');
  }
  return [...names().values()];
}

export function completionContext(source,cursor) {
  const masked=maskLuau(source), prefix=masked.slice(0,cursor);
  const original=source.slice(0,cursor);
  const part=prefix.split('\n').at(-1);
  const endPart=original.split('\n').at(-1);
  // Do not complete while inside comments and string literals.
  if(part.trim()==='' && endPart.trim()!=='')return null;
  const type=part.match(/(?:\blocal\s+\w+\s*:\s*|::\s*|\btype\s+\w+\s*=\s*)([A-Za-z_]\w*)?$/);
  if(type)return {mode:'type',query:type[1]||'',from:cursor-(type[1]||'').length,to:cursor};
  const member=part.match(/(?:^|[^\w])([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s*([.:])\s*([A-Za-z_]\w*)?$/);
  if(member)return {mode:'member',base:member[1],separator:member[2],query:member[3]||'',from:cursor-(member[3]||'').length,to:cursor};
  const word=part.match(/(?:^|[^\w.])([A-Za-z_]\w*)$/);
  if(word&&word[1])return {mode:'identifier',query:word[1],from:cursor-word[1].length,to:cursor};
  return null;
}

function relevance(query,label){const q=query.toLowerCase(),l=label.toLowerCase();if(!q)return 1;if(l===q)return 110;if(l.startsWith(q))return 75;if(l.includes(q))return 25;return 0;}
function classMembers(api, type) {
  const members=new Map();const seen=new Set();
  for(let current=type;current&&!seen.has(current);){
    seen.add(current);
    const entry=api?.classes?.[current];
    for(const item of (Array.isArray(entry)?entry:entry?.members)||[])if(!members.has(item[0]))members.set(item[0],item);
    current=entry?.parent || DEFAULT_PARENTS[current];
  }
  return [...members.values()];
}

export function staticCompletions(source,cursor,api) {
  const context=completionContext(source,cursor);
  if(!context)return null;
  const locals=localsInScope(source,cursor),byName=new Map(locals.map(x=>[x.name,x]));
  const proposals=[];
  const push=(label,kind,detail,type='',suffix='')=>{const score=relevance(context.query,label);if(score)proposals.push({label,kind,detail,type,suffix,score:score+(kind==='local'?15:0)});};
  if(context.mode==='identifier'){
    for(const item of locals)push(item.name,item.kind,item.type||'local',item.type);
    for(const name of GLOBALS)push(name,'global','Luau / Roblox global');
    for(const name of KEYWORDS)push(name,'keyword','Luau keyword');
  }else if(context.mode==='type'){
    for(const name of ['any','unknown','never','nil','boolean','number','string','buffer','thread','table','Vector3','Vector2','CFrame','Color3','UDim2','UDim','Instance','Player','Part','Model','Humanoid','RBXScriptSignal','EnumItem'])push(name,'type','Luau / Roblox type');
    for(const name of api?.types||[])push(name,'type','Roblox engine class');
    for(const x of locals.filter(x=>x.kind==='type'))push(x.name,'type','Workspace type');
  }else{
    const [first,...rest]=context.base.split('.');
    if(first==='Enum'){
      if(!rest.length)for(const name of Object.keys(api?.enums||{}))push(name,'enum','Enum.'+name);
      else if(rest.length===1)for(const name of api?.enums?.[rest[0]]||[])push(name,'enum-item','Enum.'+rest[0]+'.'+name);
    }else{
      let type=byName.get(first)?.type||({'workspace':'Workspace','game':'DataModel','Instance':'Instance','Vector3':'Vector3','Vector2':'Vector2','CFrame':'CFrame','Color3':'Color3','math':'math','table':'table','string':'string','buffer':'buffer','task':'task','os':'os'}[first]||'');
      let fields=byName.get(first)?.fields||[];
      for(const property of rest)type=(classMembers(api,type).find(x=>x[0]===property)?.[3]||'');
      const members=classMembers(api,type);
      for(const [name,kind,signature,result] of members)if(context.separator!==':'||kind==='function')push(name,kind,signature||type,result);
      if(!rest.length)for(const field of fields)push(field,'property','Workspace table field');
      const standard=api?.standard?.[type]||[];
      for(const [name,kind,signature,result] of standard)push(name,kind,signature,result);
    }
  }
  const unique=new Map();
  for(const item of proposals)if(!unique.has(item.label)||unique.get(item.label).score<item.score)unique.set(item.label,item);
  const items=[...unique.values()].sort((a,b)=>b.score-a.score||a.label.localeCompare(b.label)).slice(0,12);
  return items.length?{...context,items}:null;
}

export function applyCompletion(source,context,choice){
  if(!context || !choice)return null;
  const call=choice.kind==='function'||choice.kind==='method';
  const snippet=choice.label+(call?'()':'');
  return {source:source.slice(0,context.from)+snippet+source.slice(context.to),cursor:context.from+snippet.length-(call?1:0)};
}

export function mergeCompletions(primary,wasm){
  if(!primary)return primary;
  const matches=new Map(primary.items.map(x=>[x.label,x]));
  for(const item of wasm||[]){
    if(!item.label||!relevance(primary.query,item.label)||matches.has(item.label))continue;
    matches.set(item.label,{label:item.label,kind:item.kind||'variable',detail:item.detail||'Luau type checker',score:80});
  }
  return {...primary,items:[...matches.values()].sort((a,b)=>b.score-a.score||a.label.localeCompare(b.label)).slice(0,12)};
}
