const KEYWORDS = new Set('and break continue do else elseif end export false for function if in local nil not or repeat return then true type until while'.split(' '));
const BUILTINS = new Set('assert error getmetatable ipairs next pairs pcall print require select setmetatable tonumber tostring type typeof unpack xpcall math string table task coroutine os bit32 buffer vector utf8'.split(' '));
const TYPES = new Set('any boolean number string thread unknown never nil vector buffer'.split(' '));
const escapeHtml = value => value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&#39;');

// A lightweight editor presentation lexer, not a parser or type checker.
export function highlightLuau(source) {
  let output = '';
  let i = 0;
  while (i < source.length) {
    const rest = source.slice(i);
    let match;
    if ((match = /^(--\[(=*)\[[\s\S]*?\]\2\]|--[^\n]*)/.exec(rest))) {
      output += `<span class="token comment">${escapeHtml(match[0])}</span>`;
    } else if ((match = /^(\[(=*)\[[\s\S]*?\]\2\]|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`)/.exec(rest))) {
      output += `<span class="token string">${escapeHtml(match[0])}</span>`;
    } else if ((match = /^(?:0[xX][0-9a-fA-F_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d[\d_]*)?)/.exec(rest))) {
      output += `<span class="token number">${escapeHtml(match[0])}</span>`;
    } else if ((match = /^[A-Za-z_][A-Za-z_0-9]*/.exec(rest))) {
      const word = match[0];
      const cls = KEYWORDS.has(word) ? 'keyword' : TYPES.has(word) ? 'type' : BUILTINS.has(word) ? 'builtin' : '';
      output += cls ? `<span class="token ${cls}">${word}</span>` : word;
    } else {
      output += escapeHtml(source[i]);
      i++;
      continue;
    }
    i += match[0].length;
  }
  return output + '\n';
}
