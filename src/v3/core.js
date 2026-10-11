// LuauForge v3: deterministic, offline, non-mutating workspace analysis.
// These helpers deliberately do not pretend to be a Luau language server.
import { analyzeDependencies } from '../v1-graph.js';
import { maskLuau } from '../v15-analysis.js';

const MAX_RESULT = 250;
const SHA = /^[a-f\d]{40}$/i;
const OWNER = /^[A-Za-z\d](?:[A-Za-z\d-]{0,37})$/;
const REPO = /^[A-Za-z\d_.-]{1,100}$/;
const PACKAGE = /^@([A-Za-z\d-]+)\/([A-Za-z\d_.-]+)\/([A-Za-z\d_.\/-]+\.luau?)$/i;
const utf8 = new TextEncoder();

export function workspaceSearch(files, term, { caseSensitive = false, wholeWord = false, includeComments = true, maxResults = MAX_RESULT } = {}) {
  if (typeof term !== 'string' || !term.trim() || term.length > 120) throw new Error('Enter a search term between 1 and 120 characters.');
  if (!files || typeof files !== 'object') throw new Error('Workspace files are unavailable.');
  const results = [], needle = caseSensitive ? term : term.toLowerCase();
  const limit = Math.min(MAX_RESULT, Math.max(1, Math.floor(maxResults) || MAX_RESULT));
  for (const [file, source] of Object.entries(files).sort(([a], [b]) => a.localeCompare(b))) {
    if (typeof source !== 'string') continue;
    const view = includeComments ? source : maskLuau(source);
    const haystack = caseSensitive ? view : view.toLowerCase();
    let at = 0;
    while ((at = haystack.indexOf(needle, at)) !== -1) {
      const end = at + needle.length;
      if (!wholeWord || (!/[\w]/.test(view[at-1] || '') && !/[\w]/.test(view[end] || ''))) {
        const line = source.slice(0, at).split('\n').length;
        const begin = source.lastIndexOf('\n', at - 1) + 1;
        const last = source.indexOf('\n', at);
        results.push({file,line,column:at-begin+1,preview:source.slice(begin,last<0?source.length:last).trim().slice(0,180)});
        if (results.length>limit) return {matches:results.slice(0,limit),truncated:true};
      }
      at = Math.max(at+1,end);
    }
  }
  return {matches:results,truncated:false};
}

export function formatWhitespace(source) {
  if (typeof source !== 'string') throw new TypeError('Expected Luau source text.');
  // Preserve original line ending style and literal contents. Do not change
  // indentation or reflow e.g. "local a = b" into multiple lines.
  const masked = maskLuau(source);
  const sourceLines = source.split(/(\r\n|\n|\r)/);
  const maskedLines = masked.split(/(\r\n|\n|\r)/);
  for (let i = 0; i < sourceLines.length; i += 2) {
    const code = sourceLines[i];
    const match = /[ \t]+$/.exec(code);
    if (!match) continue;
    const start = code.length - match[0].length;
    if (start === 0) continue;
    const previous = code[start - 1];
    // If the previous visible source character is masked then we are inside
    // a quoted string, long literal, or comment: leave the entire line alone.
    if (maskedLines[i]?.[start-1] !== previous) continue;
    sourceLines[i] = code.slice(0,start);
  }
  const fixed=sourceLines.join('');
  return /(?:\r\n|\n|\r)$/.test(fixed) ? fixed : fixed+(source.includes('\r\n')?'\r\n':'\n');
}

export function qualityAudit(files,{maxFindings=160}={}) {
  const findings=[];
  const limit=Number.isInteger(maxFindings)?Math.max(1,Math.min(1000,maxFindings)):160;
  let truncated=false;
  const report=(file,line,severity,message)=>{if(findings.length<limit)findings.push({file,line,severity,message});else truncated=true;};
  for (const [file,code] of Object.entries(files||{})) {
    if (typeof code !== 'string') continue;
    const lines=code.split(/\r?\n/);
    lines.forEach((text,index)=>{
      if (text.length>160) report(file,index+1,'info',`Long line (${text.length} characters)`);
      if (/[ \t]+$/.test(text)) report(file,index+1,'info','Trailing whitespace');
      if (/\b(?:TODO|FIXME|HACK)\b/i.test(text)&&/^\s*--/.test(text)) report(file,index+1,'info','Unresolved developer note');
      if (/\b(?:print|warn)\s*\(/.test(maskLuau(text)) && !/(?:\.test|\.spec)\.luau?$/i.test(file)) report(file,index+1,'info','Debug output call (review before production)');
    });
    if (code.length > 100 && !/^\s*--!\s*(?:strict|nonstrict|nocheck)\b/m.test(code.slice(0,80))) report(file,1,'warning','No Luau type-checking directive');
  }
  const graph=analyzeDependencies(files||{});
  for (const cycle of graph.cycles) report(cycle[0]||'workspace',1,'warning',`Dependency cycle: ${cycle.join(' → ')}`);
  for (const issue of graph.problems) report(issue.file,1,'warning',issue.message);
  return {findings,cycles:graph.cycles.length,unresolved:graph.problems.length,scanned:Object.keys(files||{}).length,truncated};
}

export function compareSources(before, after, { maxLines = 320 }={}) {
  if (typeof before!=='string'||typeof after!=='string') throw new Error('Both comparison sources must be strings.');
  const a=before.split('\n'),b=after.split('\n');
  if (a.length>maxLines||b.length>maxLines) {
    return {limited:true,before:a.length,after:b.length,changes:[],message:`For safety, full diff is limited to ${maxLines} lines per file.`};
  }
  const dp=Array.from({length:a.length+1},()=>new Uint16Array(b.length+1));
  for(let i=a.length-1;i>=0;i--)for(let j=b.length-1;j>=0;j--)dp[i][j]=a[i]===b[j]?dp[i+1][j+1]+1:Math.max(dp[i+1][j],dp[i][j+1]);
  const changes=[];let i=0,j=0,truncated=false;
  const append=entry=>{if(changes.length<240)changes.push(entry);else truncated=true;};
  while(i<a.length||j<b.length){
    if(i<a.length&&j<b.length&&a[i]===b[j]){append({kind:'same',line:i+1,text:a[i]});i++;j++;}
    else if(j<b.length&&(i===a.length||dp[i][j+1]>=dp[i+1][j])){append({kind:'added',line:j+1,text:b[j]});j++;}
    else {append({kind:'removed',line:i+1,text:a[i]});i++;}
  }
  return {limited:false,before:a.length,after:b.length,changes,truncated};
}

export function createLockfile(files, pins=[],{projectName='Workspace'}={}) {
  if (!Array.isArray(pins)) throw new Error('Invalid imported module list.');
  const packages=pins.map(pin=>({specifier:pin.specifier,sha:pin.sha,size:pin.size||0}));
  const verified=packages.map(validatePackage);
  if(verified.length>16)throw new Error('Too many pinned modules for a lockfile.');
  if(new Set(verified.map(p=>p.specifier)).size!==verified.length)throw new Error('Duplicate module paths in lockfile.');
  const filesDigest=Object.entries(files||{}).sort(([a],[b])=>a.localeCompare(b)).map(([path,source])=>({path,bytes:utf8.encode(source).length}));
  return {schema:'luauforge-lockfile',version:1,generatedAt:new Date().toISOString(),project:String(projectName).slice(0,72),packages:verified,files:filesDigest};
}
function validatePackage(pkg) {
  if (!pkg || typeof pkg !== 'object' || Array.isArray(pkg)) throw new Error('Invalid module entry in lockfile.');
  const match = PACKAGE.exec(pkg.specifier || '');
  if (!match || !OWNER.test(match[1]) || !REPO.test(match[2]) || match[2] === '.' || match[2] === '..' ||
      !SHA.test(pkg.sha || '') || pkg.specifier.includes('..') || pkg.specifier.includes('//'))
    throw new Error('Invalid module path or commit SHA in lockfile.');
  const size = pkg.size === undefined ? 0 : pkg.size;
  if (!Number.isSafeInteger(size) || size < 0 || size > 200000)
    throw new Error('Invalid pinned package size.');
  return {specifier:pkg.specifier,sha:pkg.sha.toLowerCase(),size};
}

export function parseLockfile(raw) {
  if (typeof raw!=='string'||raw.length>60000) throw new Error('Lockfile is too large.');
  let data;try{data=JSON.parse(raw);}catch{throw new Error('Lockfile must be valid JSON.');}
  if(data?.schema!=='luauforge-lockfile'||data.version!==1||!Array.isArray(data.packages)||data.packages.length>16)throw new Error('Unsupported LuauForge lockfile.');
  const packages=data.packages.map(validatePackage);
  if(new Set(packages.map(p=>p.specifier)).size!==packages.length)throw new Error('Duplicate module paths in lockfile.');
  // Import is deliberately read-only. Each package requires preview + approval.
  return {packages,project:typeof data.project==='string'?data.project.slice(0,72):'Workspace'};
}

export function projectReport(project,pins=[]) {
  const audit=qualityAudit(project.files);
  const files=Object.entries(project.files).sort(([a],[b])=>a.localeCompare(b));
  const lines=files.reduce((n,[,s])=>n+s.split('\n').length,0);
  return [
    `# ${String(project.name).replace(/[\r\n#]/g,'').slice(0,70)} — LuauForge v3 report`,
    '',`- Files: ${files.length}`,`- Luau lines: ${lines}`,`- Pinned public modules: ${pins.length}`,
    `- Dependency cycles: ${audit.cycles}`,`- Dependency issues: ${audit.unresolved}`,`- Advisory findings: ${audit.findings.length}`,'',
    '## Workspace files',...files.map(([name,src])=>`- \`${name.replace(/`/g,'')}\`: ${src.split('\n').length} lines`),
    '','## Public module pins',...(pins.length?pins.map(p=>`- \`${p.specifier}\` @ \`${p.sha}\``):['- None']),
    '','## Review items',...(audit.findings.length?audit.findings.slice(0,50).map(f=>`- ${f.file}:${f.line} [${f.severity}] ${f.message}`):['- None detected by the lightweight audit.']),
    '', '> Advisory static analysis only. Run Luau diagnostics and Studio tests for authoritative results.',''
  ].join('\n');
}
