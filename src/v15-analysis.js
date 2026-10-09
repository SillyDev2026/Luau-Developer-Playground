// Conservative, offline code intelligence helpers. These do not replace the
// Luau WASM type checker; unsafe cross-file renames are explicitly excluded.
export function maskLuau(source) {
  let out = '', state = 'code', close = '', i = 0;
  while (i < source.length) {
    const c = source[i], next = source[i + 1] || '';
    if (state === 'code') {
      if (c === '-' && next === '-') {
        const long = source.slice(i + 2).match(/^\[(=*)\[/);
        if (long) { close = ']' + long[1] + ']'; state = 'longcomment'; out += ' '.repeat(2 + long[0].length); i += 2 + long[0].length; continue; }
        state = 'comment'; out += '  '; i += 2; continue;
      }
      const long = source.slice(i).match(/^\[(=*)\[/);
      if (long) { close = ']' + long[1] + ']'; state = 'longstring'; out += ' '.repeat(long[0].length); i += long[0].length; continue; }
      if (c === '"' || c === "'" || c === '`') { state = c; out += ' '; i++; continue; }
      out += c; i++; continue;
    }
    if (state === 'comment') { if (c === '\n') { state = 'code'; out += '\n'; } else out += ' '; i++; continue; }
    if (state === 'longcomment' || state === 'longstring') {
      if (source.startsWith(close, i)) { out += ' '.repeat(close.length); i += close.length; state = 'code'; }
      else { out += c === '\n' ? '\n' : ' '; i++; }
      continue;
    }
    if (c === '\\') { out += ' '.repeat(Math.min(2, source.length - i)); i += 2; continue; }
    out += c === '\n' ? '\n' : ' ';
    if (c === state) state = 'code';
    i++;
  }
  return out;
}
export function referenceRanges(source, identifier, { skipProperties = true } = {}) {
  if (!/^[A-Za-z_][\w]*$/.test(identifier)) throw new Error('Select a valid identifier.');
  const masked = maskLuau(source), pattern = new RegExp(`\\b${identifier}\\b`, 'g'), found = [];
  for (const match of masked.matchAll(pattern)) {
    const i = match.index;
    if (skipProperties && /[.:]/.test(masked.slice(0, i).trimEnd().slice(-1))) continue;
    found.push({ start: i, end: i + identifier.length, line: source.slice(0, i).split('\n').length });
  }
  return found;
}
export function wordAt(source, offset) {
  let left = Math.max(0, Math.min(offset, source.length)), right = left;
  while (left > 0 && /[\w]/.test(source[left - 1])) left--;
  while (right < source.length && /[\w]/.test(source[right])) right++;
  const word = source.slice(left, right);
  return /^[A-Za-z_]\w*$/.test(word) ? word : '';
}
export function planRename(files, active, offset, replacement) {
  if (!/^[A-Za-z_]\w*$/.test(replacement)) throw new Error('New name must be a Luau identifier.');
  const source = files[active];
  if (typeof source !== 'string') throw new Error('Active file is missing.');
  const name = wordAt(source, offset);
  if (!name) throw new Error('Place your cursor on a variable or function name.');
  if (name === replacement) throw new Error('The name has not changed.');
  const declarations = maskLuau(source).match(new RegExp(`\\b(?:local\\s+(?:function\\s+)?|function\\s+)${name}\\b`));
  if (!declarations) throw new Error('Only variables/functions declared in this file can be renamed safely.');
  const ranges = referenceRanges(source, name);
  if (!ranges.length) throw new Error('No references found.');
  if (referenceRanges(source, replacement).length) throw new Error('Target name already exists in the file. Choose another name.');
  const ambiguous = /\b(function|do|then|repeat|else|elseif)\b/.test(maskLuau(source));
  return { name, replacement, active, ranges, cautious: ambiguous, preview: ranges.length, apply() {
    let result = source;
    for (const range of ranges.slice().reverse()) result = result.slice(0, range.start) + replacement + result.slice(range.end);
    return result;
  } };
}
export function findReferences(files, identifier) {
  const result = [];
  for (const [file, source] of Object.entries(files)) for (const range of referenceRanges(source, identifier)) result.push({ file, ...range });
  return result;
}
export function inferSimpleTypes(source) {
  const result = [];
  const visible = maskLuau(source);
  const re = /\blocal\s+([A-Za-z_]\w*)\s*(?::\s*([A-Za-z_]\w*(?:\??)))?\s*(?:=\s*)?/g;
  for (const match of visible.matchAll(re)) {
    const name = match[1], next = source.slice(match.index + match[0].length).trimStart();
    const value = match[2] || (/^[-+]?\d/.test(next) ? 'number' : /^["'`]/.test(next) ? 'string' : /^\{/.test(next) ? 'table' : /^(?:true|false)\b/.test(next) ? 'boolean' : /^function\b/.test(next) ? 'function' : 'unknown');
    result.push({ name, type: value, line: source.slice(0, match.index).split('\n').length });
  }
  return result;
}
export function generateModuleDocs(path, source) {
  const text = maskLuau(source), list = [];
  const re = /\bfunction\s+([\w.]+)(?::([\w]+))?\s*\(([^)]*)\)/g;
  for (const m of text.matchAll(re)) list.push({ name: m[1] + (m[2] ? ':' + m[2] : ''), args: source.slice(m.index).match(/\(([^)]*)\)/)?.[1] || '', line: source.slice(0, m.index).split('\n').length });
  const unique = [...new Map(list.map(x => [x.name, x])).values()];
  return `# ${path}\n\nAPI summary generated from static source patterns. Confirm inferred types with Luau diagnostics.\n\n` + (unique.length ? unique.map(x => `- \`${x.name}(${x.args})\` — line ${x.line}`).join('\n') : 'No exported function patterns detected.') + '\n';
}
export function quickFixSuggestions(source, diagnostics = []) {
  const suggestions = [];
  for (const d of diagnostics) {
    if (/Unknown global ['`"]?(warn)['`"]?/i.test(d.message || '')) suggestions.push({ label: 'Replace warn(...) with print(...) for standalone WASM', note: 'Review replacement before applying.' });
    if (/unknown require|module.*not found/i.test(d.message || '')) suggestions.push({ label: 'Open Modules → dependency inspector to resolve missing import paths', note: 'Does not modify source.' });
  }
  if (!source.startsWith('--!strict')) suggestions.push({ label: 'Add --!strict type-checking directive', insert: '--!strict\n' });
  return suggestions;
}
