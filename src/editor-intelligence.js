// Editor navigation and signature hints. Static, side-effect-free, and offline.
// WASM diagnostics remains the authority for type correctness.
import { maskLuau, localsInScope } from './intellisense.js?v=0.4.0';
import { getRobloxAPI, DEFAULT_PARENTS } from './roblox-api.js?v=0.4.0';

const IDENT = /^[A-Za-z_]\w*$/;
const BUILTIN_CALLS = {
  print: 'print(...any): ()', warn: 'warn(...any): ()', assert: 'assert<T>(value: T, message: any?): T',
  require: 'require(module: string): any', type: 'type(value: any): string', typeof: 'typeof(value: any): string',
  tostring: 'tostring(value: any): string', tonumber: 'tonumber(value: any, base: number?): number?',
  pairs: 'pairs(t: table): iterator', ipairs: 'ipairs(t: table): iterator', pcall: 'pcall(callback: function, ...any): (boolean, ...any)',
  task: '',
};
const CONSTRUCTORS = {
  'Instance.new':'Instance.new(className: string, parent: Instance?): Instance',
  'Vector3.new':'Vector3.new(x: number, y: number, z: number): Vector3',
  'Vector2.new':'Vector2.new(x: number, y: number): Vector2',
  'UDim2.new':'UDim2.new(xScale: number, xOffset: number, yScale: number, yOffset: number): UDim2',
  'Color3.fromRGB':'Color3.fromRGB(r: number, g: number, b: number): Color3',
};

export function argumentContext(source, cursor) {
  const clean = maskLuau(source.slice(0, cursor));
  const stack = [];
  for (let i=0; i<clean.length; i++) {
    const ch = clean[i];
    if (ch==='(' || ch==='[' || ch==='{') stack.push({char:ch,position:i,arg:0});
    else if (ch===')'||ch===']'||ch==='}') {
      const wanted = ch===')'?'(':ch===']'?'[':'{';
      if (stack.at(-1)?.char===wanted) stack.pop();
    } else if (ch===',' && stack.at(-1)?.char==='(') stack.at(-1).arg++;
  }
  for (let i=stack.length-1; i>=0; i--) {
    if (stack[i].char!=='(') continue;
    const left = clean.slice(0,stack[i].position);
    const match = left.match(/([A-Za-z_]\w*(?:[.:][A-Za-z_]\w*)*)\s*$/);
    if (!match) return null;
    if (/\bfunction\s+$/.test(left.slice(0,match.index))) return null;
    return {name:match[1],activeParameter:stack[i].arg,open:stack[i].position};
  }
  return null;
}

function flattenMembers(api, className) {
  const all=[],seen=new Set();let cls=className;
  while(cls&&!seen.has(cls)) {
    seen.add(cls);
    const entry=api?.classes?.[cls];
    const members=Array.isArray(entry)?entry:entry?.members||[];
    all.push(...members);
    cls=entry?.parent || DEFAULT_PARENTS[cls];
  }
  return all;
}

function classForExpression(expression, source, cursor) {
  if (expression==='game') return 'DataModel';
  if (expression==='workspace') return 'Workspace';
  if (expression==='Instance') return 'Instance';
  const [first,...rest]=expression.split('.');
  const symbols=localsInScope(source,cursor);
  let type=symbols.find(x=>x.name===first)?.type||first;
  const api=getRobloxAPI();
  for(const member of rest) type=flattenMembers(api,type).find(x=>x[0]===member)?.[3]||'';
  return type;
}

export function signatureFor(source,cursor,api=getRobloxAPI()) {
  const context=argumentContext(source,cursor);
  if(!context) return null;
  const name=context.name,parts=name.split(/[.:]/);
  let signature=CONSTRUCTORS[name]||BUILTIN_CALLS[name]||'';
  if(!signature && parts.length>=2){
    const member=parts.at(-1),base=name.slice(0,-1-member.length);
    const type=classForExpression(base,source,cursor);
    signature=flattenMembers(api,type).find(x=>x[0]===member && x[1]==='function')?.[2]||
      (api?.standard?.[type]||[]).find(x=>x[0]===member)?.[2]||'';
  }
  if(!signature && parts.length===1) {
    // Support definitions: local function foo(x: number) and function foo(x: number).
    // Only declarations preceding the call can provide a signature.
    const before=source.slice(0,context.open);
    const re=new RegExp('\\b(?:local\\s+)?function\\s+'+name+'\\s*\\(([^)]*)\\)\\s*(?::\\s*([\\w.{}?]+))?','g');
    for(const match of before.matchAll(re)) signature=name+'('+match[1]+')'+(match[2]?': '+match[2]:'');
    if(!signature){
      const assignment=new RegExp('\\blocal\\s+'+name+'\\s*=\\s*function\\s*\\(([^)]*)\\)','g');
      for(const match of before.matchAll(assignment))signature=name+'('+match[1]+')';
    }
  }
  if(!signature)return null;
  return {...context,signature};
}

export function outlineSymbols(source) {
  const clean=maskLuau(source),symbols=[];
  const pattern=/^\s*(?:(local)\s+)?(function\s+([\w.:]+)\s*\(|(?:export\s+)?type\s+([A-Za-z_]\w*)\s*=|local\s+([A-Za-z_]\w*)\s*(?::[^\n=]+)?\s*=)/gm;
  for(const match of clean.matchAll(pattern)){
    const name=match[3]||match[4]||match[5];
    if(!name||!IDENT.test(name.split(/[.:]/).at(-1)))continue;
    const line=source.slice(0,match.index).split('\n').length;
    symbols.push({name,line,position:match.index+match[0].indexOf(name),kind:match[3]?'function':match[4]?'type':'local'});
  }
  return symbols;
}

export function definitionAt(source,cursor) {
  const clean=maskLuau(source);
  const before=clean.slice(0,cursor).match(/[A-Za-z_]\w*$/)?.[0]||'';
  const after=clean.slice(cursor).match(/^[A-Za-z_]\w*/)?.[0]||'';
  const token=before+after;
  if(!IDENT.test(token))return null;
  const symbolStart=cursor-before.length;
  const candidates=outlineSymbols(source).filter(x=>x.name===token && x.position<=symbolStart);
  if(!candidates.length)return null;
  // Prefer most recent visible local declaration; don't jump to future definitions.
  const visible=localsInScope(source,cursor).some(x=>x.name===token);
  if(!visible)return null;
  return candidates.at(-1);
}

export function formatSignature(signature,activeParameter) {
  const open=signature.indexOf('('),close=signature.lastIndexOf(')');
  if(open<0||close<0)return {before:signature,active:'',after:''};
  const params=signature.slice(open+1,close);
  const segments=[],stack=[];let start=0;
  for(let i=0;i<params.length;i++){
    const char=params[i];
    if('([{<'.includes(char))stack.push(char);
    else if(')]}>'.includes(char))stack.pop();
    else if(char===','&&!stack.length){segments.push(params.slice(start,i));start=i+1;}
  }
  segments.push(params.slice(start));
  const index=Math.min(activeParameter,segments.length-1);
  const left=segments.slice(0,index).join(',');
  return {before:signature.slice(0,open+1)+(index?left+',':''),active:segments[index]?.trim()||'',after:(index<segments.length-1?', '+segments.slice(index+1).join(','):'')+signature.slice(close)};
}
