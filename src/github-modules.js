// Public GitHub modules for standalone Luau WASM. No user tokens, no write API,
// no arbitrary URLs. Public source is reviewed in the UI before local pinning.
import { findRequires } from './module-bundle.js';

export const GITHUB_PINS_KEY = 'luauforge:github-pins:v1';
export const GITHUB_VIRTUAL_ROOT = '__luauforge_github__/';
export const GITHUB_MODULE_MAX_BYTES = 200000;
const MAX_MODULES = 16;
const MAX_TOTAL_BYTES = 750000;
const OWNER = /^[A-Za-z\d](?:[A-Za-z\d-]{0,37})$/;
const REPO = /^[A-Za-z\d_.-]{1,100}$/;
const SHA = /^[a-f\d]{40}$/i;
const EXTENSION = /\.lua(u)?$/i;
const EXAMPLE_REPO = 'SillyDev2026/Luau-Developer-Playground';

export const PUBLIC_GITHUB_EXAMPLES = Object.freeze([
  Object.freeze({ owner:'SillyDev2026', repo:'Luau-Developer-Playground', path:'community/TestTools.luau', label:'TestTools', description:'Assertions and small test cases', local:true }),
  Object.freeze({ owner:'SillyDev2026', repo:'Luau-Developer-Playground', path:'community/MathKit.luau', label:'MathKit', description:'Small, self-contained math module', local:true }),
  Object.freeze({ owner:'SillyDev2026', repo:'Luau-Developer-Playground', path:'community/tests/MathKitTests.luau', label:'MathKitTests', description:'Require this test suite and run MathKitTests.run()', local:true }),
]);
function error(message) { throw new Error(message); }
function validatePath(input) {
  if(typeof input!=='string' || input.length>220 || !input || input.startsWith('/') || input.endsWith('/') || input.includes('\\') || /[?#%\x00-\x1f]/.test(input) || input.split('/').some(x=>!x || x==='.' || x==='..' || !/^[\w.-]+$/.test(x))) error('Invalid GitHub source path. Use a path inside the public repository.');
  return input;
}
function moduleSpec(owner,repo,path) { return `@${owner}/${repo}/${path}`; }
export function parseGithubSpecifier(value) {
  if(typeof value!=='string' || !value.startsWith('@')) return null;
  const parts=value.slice(1).split('/');
  if(parts.length<3) return null;
  const [owner,repo,...tail]=parts;
  if(!OWNER.test(owner)||!REPO.test(repo)||repo==='.'||repo==='..') return null;
  const path=validatePath(tail.join('/'));
  return {owner,repo,path,specifier:moduleSpec(owner,repo,path)};
}
export function githubVirtualFile(parsed) { return `${GITHUB_VIRTUAL_ROOT}${parsed.owner}/${parsed.repo}/${parsed.path}`; }
export function parseGithubInput(input) {
  const text=String(input||'').trim();
  if(text.startsWith('@')) {
    const spec=parseGithubSpecifier(text);
    if(!spec) error('Example: @Owner/Repo/modules/MyModule.luau');
    return {...spec,ref:'HEAD'};
  }
  if(/^https?:\/\//i.test(text)) {
    const url=new URL(text);
    if(url.protocol!=='https:') error('Only HTTPS GitHub source URLs are supported.');
    if(url.hostname==='github.com') {
      const seg=url.pathname.split('/').filter(Boolean);
      if(seg.length<5 || seg[2]!=='blob') error('Use a GitHub file URL with /blob/BRANCH/path.luau.');
      const [owner,repo,,ref,...rest]=seg;
      const parsed=parseGithubSpecifier(moduleSpec(owner,repo,rest.join('/')));
      if(!parsed) error('Invalid public repository/module URL.');
      return {...parsed,ref};
    }
    if(url.hostname==='raw.githubusercontent.com') {
      const [owner,repo,ref,...rest]=url.pathname.split('/').filter(Boolean);
      const parsed=parseGithubSpecifier(moduleSpec(owner,repo,rest.join('/')));
      if(!parsed||!ref) error('Invalid raw GitHub source URL.');
      return {...parsed,ref};
    }
    error('Only github.com and raw.githubusercontent.com source URLs are supported.');
  }
  const candidate=text.startsWith('@')?text:'@'+text;
  const parsed=parseGithubSpecifier(candidate);
  if(!parsed) error('Use @Owner/Repo/path/to/Module.luau or a public GitHub file URL.');
  return {...parsed,ref:'HEAD'};
}
function checkSource(source,filename) {
  const size=new TextEncoder().encode(source).byteLength;
  if(size<10 || size>GITHUB_MODULE_MAX_BYTES) error(`${filename} must be 10–${GITHUB_MODULE_MAX_BYTES} bytes.`);
  if(!/\breturn\b/.test(source)) error(`${filename} does not appear to return a module API.`);
  if(/\x00/.test(source)) error('Binary files cannot be imported as Luau modules.');
  return {size,studioOnly:/\b(?:game\s*[:.]|workspace\s*[.:]|script\s*[.:]|Instance\.new\s*\(|DataStoreService\b|RunService\b|RemoteEvent\b)/.test(source)};
}
function abortSignal() { return typeof AbortSignal?.timeout==='function'?AbortSignal.timeout(16000):undefined; }
// Immutable SHA sources may be reused for diagnostics, execution and autocomplete
// without re-fetching on every keystroke. Failed downloads are never cached.
const sourceCache=new Map();
async function fetchCachedSource(url, fetchImpl) {
  if(fetchImpl!==fetch) return checkedFetch(url,fetchImpl);
  if(!sourceCache.has(url)) {
    const pending=checkedFetch(url,fetchImpl).catch(err=>{if(sourceCache.get(url)===pending)sourceCache.delete(url);throw err;});
    if(sourceCache.size>=32)sourceCache.delete(sourceCache.keys().next().value);
    sourceCache.set(url,pending);
  }
  return sourceCache.get(url);
}
async function checkedFetch(url, fetchImpl, json=false) {
  const response=await fetchImpl(url,{signal:abortSignal(),cache:'no-store',headers:json?{Accept:'application/vnd.github+json'}:{}});
  if(!response.ok) throw new Error(`Public GitHub source unavailable (HTTP ${response.status}).`);
  const len=Number(response.headers?.get?.('content-length')||0);
  if(!json&&len>GITHUB_MODULE_MAX_BYTES) error('GitHub module exceeds the maximum source size.');
  const ct=response.headers?.get?.('content-type')||'';
  if(!json&&ct.includes('text/html')) error('GitHub returned HTML instead of Luau code.');
  return json?response.json():response.text();
}
export async function previewGithubModule(input,{fetchImpl=fetch}={}) {
  const parsed=parseGithubInput(input);
  if(!EXTENSION.test(parsed.path)) error('Paste a .luau or .lua file URL, or include its extension in @Owner/Repo/path.');
  const {owner,repo,path}=parsed;
  // HEAD discovers the current default branch; the resolved full SHA makes
  // imported code immutable until the user explicitly changes their pin.
  const revision=encodeURIComponent(parsed.ref);
  const metadata=await checkedFetch(`https://api.github.com/repos/${owner}/${repo}/commits/${revision}`,fetchImpl,true);
  if(!SHA.test(metadata.sha||'')) error('GitHub did not return a valid commit SHA.');
  const sha=metadata.sha.toLowerCase();
  const source=await checkedFetch(`https://raw.githubusercontent.com/${owner}/${repo}/${sha}/${path.split('/').map(encodeURIComponent).join('/')}`,fetchImpl);
  const details=checkSource(source,parsed.specifier);
  return {...parsed,sha,source,...details,repository:`https://github.com/${owner}/${repo}`,url:`https://github.com/${owner}/${repo}/blob/${sha}/${path}`};
}
export function validatePin(pin) {
  if(!pin||typeof pin!=='object') return null;
  const info=parseGithubSpecifier(pin.specifier);
  if(!info||!SHA.test(pin.sha||'')||pin.studioOnly===true) return null;
  if(!EXTENSION.test(info.path)) return null;
  return {...info,sha:pin.sha.toLowerCase(),size:Number(pin.size)||0};
}
export function readGithubPins(storage=globalThis.localStorage) {
  try {const obj=JSON.parse(storage?.getItem(GITHUB_PINS_KEY)||'[]');return Array.isArray(obj)?obj.slice(0,MAX_MODULES).map(validatePin).filter(Boolean):[];}catch{return [];}
}
export function saveGithubPin(preview,storage=globalThis.localStorage) {
  if(preview.studioOnly) error('This module uses Roblox Studio services; download its source for Studio instead of browser WASM.');
  const pin=validatePin(preview);
  if(!pin) error('Invalid module source or GitHub revision.');
  const previous=readGithubPins(storage).filter(x=>x.specifier!==pin.specifier);
  if(previous.length>=MAX_MODULES) error(`Maximum ${MAX_MODULES} public modules per device.`);
  storage.setItem(GITHUB_PINS_KEY,JSON.stringify([...previous,pin]));
  return pin;
}
export function removeGithubPin(specifier,storage=globalThis.localStorage) {
  const next=readGithubPins(storage).filter(x=>x.specifier!==specifier);
  storage.setItem(GITHUB_PINS_KEY,JSON.stringify(next));
  return next;
}
export function githubModuleTargets(storage=typeof localStorage==='undefined'?null:localStorage) {
  const pins=readGithubPins(storage);
  const builtin=PUBLIC_GITHUB_EXAMPLES.map(x=>({...x,specifier:moduleSpec(x.owner,x.repo,x.path)}));
  return [...builtin,...pins.filter(x=>!builtin.some(y=>y.specifier===x.specifier)).map(x=>({...x,label:x.path.split('/').at(-1).replace(EXTENSION,''),description:`Pinned ${x.sha.slice(0,9)}`}))];
}
function ownExample(specifier) {return PUBLIC_GITHUB_EXAMPLES.find(x=>moduleSpec(x.owner,x.repo,x.path)===specifier);}
export async function loadGithubForProject(project,{storage=typeof localStorage==='undefined'?null:localStorage,fetchImpl=fetch,moduleUrl=import.meta.url}={}) {
  const pins=new Map(readGithubPins(storage).map(x=>[x.specifier,x]));
  const files={...project.files};
  let total=0;
  let count=0;
  const pending=new Set();
  async function load(info,sha,local) {
    const key=githubVirtualFile(info);
    if(Object.hasOwn(files,key)) return;
    if(pending.has(key))return;
    if(++count>MAX_MODULES) error(`Public module graph exceeds ${MAX_MODULES} files.`);
    pending.add(key);
    try {
      const fileUrl=local ? new URL('../community/'+info.path.replace(/^community\//,''),moduleUrl).href : `https://raw.githubusercontent.com/${info.owner}/${info.repo}/${sha}/${info.path.split('/').map(encodeURIComponent).join('/')}`;
      const source=await fetchCachedSource(fileUrl,fetchImpl);
      const {size,studioOnly}=checkSource(source,key);
      if(studioOnly)error(`Module ${info.specifier} depends on Roblox Studio APIs and cannot run in standalone Luau WASM.`);
      total+=size;
      if(total>MAX_TOTAL_BYTES)error('Public module graph exceeds the maximum combined source size.');
      files[key]=source;
      for(const dep of findRequires(source)) {
        if(dep.requested.startsWith('@')) {
          const nested=parseGithubSpecifier(dep.requested);
          if(!nested)continue; // Bundled @FastNum, @NanoNum, ...
          await loadPinned(nested);
        } else if(dep.requested.startsWith('./')||dep.requested.startsWith('../')) {
          const base=info.path.split('/').slice(0,-1);
          for(const part of dep.requested.split('/')) {
            if(!part||part==='.')continue;
            if(part==='..'){if(!base.length)error(`Public module import escapes repository: ${dep.requested}`);base.pop();}
            else base.push(part);
          }
          const child=base.join('/');
          if(!EXTENSION.test(child))error(`In ${info.specifier}, use an explicit .luau or .lua extension for external relative imports: ${dep.requested}`);
          await load({...info,path:child,specifier:moduleSpec(info.owner,info.repo,child)},sha,local);
        }
      }
    } finally {pending.delete(key);}
  }
  async function loadPinned(info) {
    const own=ownExample(info.specifier);
    const pin=pins.get(info.specifier);
    if(own)return load(info,null,true);
    if(!pin)error(`Untrusted public GitHub module ${info.specifier}. Add and preview it from Libraries → Add public GitHub module before running.`);
    return load(info,pin.sha,false);
  }
  for(const source of Object.values(project.files)) for(const dep of findRequires(source)) {
    const info=parseGithubSpecifier(dep.requested);
    if(info)await loadPinned(info);
  }
  return {...project,files};
}
