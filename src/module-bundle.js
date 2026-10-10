import { builtinId, builtinPath } from "./builtin-libraries.js";
// The pinned official Playground WASM resolver supports a flat filesystem only.
// Resolve workspace-relative require literals and assign unique, flat Luau VM keys.
export const REQUIRE_METRIC_MARKER = '__LUAUFORGE_REQUIRE_TIMING_V1__';
const VALID_EXTENSION = /\.lua(u)?$/i;

function skipQuote(source, start) {
  const quote = source[start];
  let i = start + 1;
  while (i < source.length) {
    if (source[i] === '\\') { i += 2; continue; }
    if (source[i] === quote) return i + 1;
    i++;
  }
  return i;
}
function bracketEnd(source, start) {
  const open = source.slice(start).match(/^\[(=*)\[/);
  if (!open) return -1;
  const ending = `]${open[1]}]`;
  const close = source.indexOf(ending, start + open[0].length);
  return close === -1 ? source.length : close + ending.length;
}
function skipTrivia(source, start) {
  let i = start;
  while (i < source.length) {
    if (/\s/.test(source[i])) { i++; continue; }
    if (source.slice(i, i + 2) === '--') {
      const block = bracketEnd(source, i + 2);
      if (block !== -1) { i = block; continue; }
      const end = source.indexOf('\n', i + 2);
      i = end === -1 ? source.length : end;
      continue;
    }
    break;
  }
  return i;
}
export function findRequires(source) {
  const found = [];
  let i = 0;
  while (i < source.length) {
    if (source.slice(i, i + 2) === '--') {
      const block = bracketEnd(source, i + 2);
      i = block !== -1 ? block : (source.indexOf('\n', i + 2) === -1 ? source.length : source.indexOf('\n', i + 2));
      continue;
    }
    if (source[i] === '"' || source[i] === "'" || source[i] === '`') { i = skipQuote(source, i); continue; }
    const bracket = source[i] === '[' ? bracketEnd(source, i) : -1;
    if (bracket !== -1) { i = bracket; continue; }
    if (source.startsWith('require', i) && !/[\w.:]/.test(source[i - 1] || '') && !/[\w]/.test(source[i + 7] || '')) {
      let cursor = skipTrivia(source, i + 7);
      if (source[cursor] !== '(') { i += 7; continue; }
      cursor = skipTrivia(source, cursor + 1);
      if (source[cursor] !== '"' && source[cursor] !== "'") { i += 7; continue; }
      const end = skipQuote(source, cursor);
      const closing = skipTrivia(source, end);
      if (source[closing] !== ')') { i += 7; continue; }
      const expression = source.slice(cursor, end);
      // JSON supports escapes for double-quoted literals; Lua single quotes are handled below.
      let requested;
      try {
        requested = expression[0] === '"' ? JSON.parse(expression) : expression.slice(1, -1).replace(/\\([\\'"nrt])/g, (match, c) => ({n:'\n',r:'\r',t:'\t'}[c] || c));
      } catch { i = closing + 1; continue; }
      found.push({ start: i, end: closing + 1, requested });
      i = closing + 1;
      continue;
    }
    i++;
  }
  return found;
}
export function resolveModule(importer, requested, files) {
  const builtin = builtinId(requested);
  if (builtin) {
    const virtual = builtinPath(builtin);
    if (!Object.hasOwn(files, virtual)) throw new Error(`Missing built-in library ${requested}. The library must be loaded before the script runs.`);
    return virtual;
  }
  if (typeof requested === 'string' && /^@[A-Za-z0-9-]+\/[A-Za-z0-9._-]+\//.test(requested)) {
    const path = '__luauforge_github__/' + requested.slice(1);
    const candidates = VALID_EXTENSION.test(path) ? [path] : [path+'.luau', path+'.lua', path+'/init.luau', path+'/init.lua'];
    const matching = candidates.filter(name => Object.hasOwn(files, name));
    if (!matching.length) throw new Error(`GitHub module ${requested} is not registered or could not be fetched. Add it from Libraries → Add public GitHub module.`);
    if (matching.length > 1) throw new Error(`Ambiguous GitHub import ${requested}; add an extension.`);
    return matching[0];
  }
  if (typeof requested !== 'string' || !requested.startsWith('./') && !requested.startsWith('../')) {
    throw new Error(`Unsupported require(${JSON.stringify(requested)}) in ${importer}. Use a relative path such as require("./modules/Math.luau").`);
  }
  const segments = importer.split('/').slice(0, -1);
  for (const piece of requested.split('/')) {
    if (!piece || piece === '.') continue;
    if (piece === '..') {
      if (!segments.length) throw new Error(`Require path escapes the workspace: ${importer} → ${requested}`);
      segments.pop();
    } else segments.push(piece);
  }
  const joined = segments.join('/');
  const candidates = VALID_EXTENSION.test(joined) ? [joined] : [joined+'.luau',joined+'.lua',joined+'/init.luau',joined+'/init.lua'];
  const matching = candidates.filter(path => Object.hasOwn(files, path));
  if (matching.length > 1) throw new Error(`Ambiguous require in ${importer}: ${requested} matches ${matching.join(', ')}. Use a file extension.`);
  if (!matching.length) throw new Error(`Module not found in ${importer}: ${requested}. Expected ${candidates.join(' or ')}.`);
  return matching[0];
}

// Keep paths as strings only in the editor: the backend still uses regular require caches.
export function bundleProject(project, { instrument = false } = {}) {
  const files = project.files;
  const all = Object.keys(files).sort();
  const aliases = new Map(all.map((name, i) => [name, `__lf_m${i}.luau`]));
  const transformed = Object.create(null);
  const dependencies = [];
  const visited = new Set();
  const visit = name => {
    if (visited.has(name)) return;
    visited.add(name);
    const source = files[name];
    let offset = 0;
    let output = '';
    for (const match of findRequires(source)) {
      const target = resolveModule(name, match.requested, files);
      visit(target);
      const flat = './' + aliases.get(target);
      output += source.slice(offset, match.start);
      output += instrument ? `__lf_require_timed(${JSON.stringify(flat)}, ${JSON.stringify(target)})` : `require(${JSON.stringify(flat)})`;
      dependencies.push({ from: name, to: target, requested: match.requested });
      offset = match.end;
    }
    output += source.slice(offset);
    if (instrument && dependencies.some(item => item.from === name)) {
      // Exact duration originates in the Luau VM (os.clock), never in the UI.
      const prefix = `local __lf_original_require = require\nlocal function __lf_require_timed(spec: string, label: string): any\n    local start = os.clock()\n    local value = __lf_original_require(spec)\n    print(${JSON.stringify(REQUIRE_METRIC_MARKER)}, label, os.clock() - start)\n    return value\nend\n`;
      const directive = output.match(/^(--!\w+[^\n]*\n)/);
      output = directive ? directive[0] + prefix + output.slice(directive[0].length) : prefix + output;
    }
    transformed[name] = output;
  };
  visit(project.active);
  const modules = Object.create(null);
  for (const [name, code] of Object.entries(transformed)) {
    if (name !== project.active) modules[aliases.get(name)] = code;
  }
  return { code: transformed[project.active], modules, sources: Object.fromEntries(Object.keys(transformed).map(name => [aliases.get(name), transformed[name]])), aliases: Object.fromEntries(aliases), dependencies };
}

function stringValue(part) { return typeof part === 'object' && part !== null && 'value' in part ? String(part.value) : String(part); }
export function extractRequireTimings(result) {
  const timings = [];
  const prints = [];
  for (const args of result.prints || []) {
    if (Array.isArray(args) && stringValue(args[0]) === REQUIRE_METRIC_MARKER && args.length >= 3) {
      const seconds = Number(stringValue(args[2]));
      if (Number.isFinite(seconds) && seconds >= 0) timings.push({ module: stringValue(args[1]), milliseconds: seconds * 1000 });
    } else prints.push(args);
  }
  const output = (result.output || '').split('\n').filter(line => !line.startsWith(REQUIRE_METRIC_MARKER+'\t')).join('\n');
  return { ...result, prints, output, requireTimings: timings };
}

export function summarizeSamples(values) {
  const sorted = values.filter(v=>Number.isFinite(v) && v >= 0).sort((a,b)=>a-b);
  if (!sorted.length) return { samples: 0, medianMs: null, minMs: null, maxMs: null };
  const middle = Math.floor(sorted.length / 2);
  return { samples: sorted.length, medianMs: sorted.length % 2 ? sorted[middle] : (sorted[middle-1]+sorted[middle])/2, minMs: sorted[0], maxMs: sorted.at(-1) };
}
