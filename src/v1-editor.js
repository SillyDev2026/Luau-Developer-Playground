import { highlightLuau } from './highlight.js';
import { indentSelection, currentLineAndColumn, positionForLine } from './editor-utils.js';

const PAIRS = { '(': ')', '[': ']', '{': '}', '"': '"', "'": "'" };
export function newlineIndent(source, cursor) {
  const before = source.slice(source.lastIndexOf('\n', cursor - 1) + 1, cursor);
  const indentation = before.match(/^\s*/)?.[0] || '';
  const deeper = /(?:\b(?:then|do|else|repeat|function)\b|\{)\s*(?:--[^\n]*)?$/.test(before);
  return '\n' + indentation + (deeper ? '    ' : '');
}
export function matchBracket(source, cursor) {
  const pairs = { '(': ')', '[': ']', '{': '}' }, reverse = { ')': '(', ']': '[', '}': '{' };
  const at = /[()\[\]{}]/.test(source[cursor] || '') ? cursor : cursor - 1;
  if (at < 0) return null;
  const ch = source[at], forward = Object.hasOwn(pairs, ch), other = forward ? pairs[ch] : reverse[ch];
  if (!other) return null;
  let depth = 1;
  for (let i = at + (forward ? 1 : -1); i >= 0 && i < source.length; i += forward ? 1 : -1) {
    if (source[i] === ch) depth++;
    if (source[i] === other && --depth === 0) return [Math.min(at, i), Math.max(at, i)];
  }
  return null;
}
export class CodeEditor {
  constructor({ input, highlight, gutter, onChange, onCursor, onShortcut }) {
    Object.assign(this, { input, highlight, gutter, onChange, onCursor, onShortcut });
    this.source = null;
    this.raf = 0;
    input.addEventListener('input', () => { this.render(); this.onChange(input.value); this.onCursor(); });
    input.addEventListener('scroll', () => { highlight.parentElement.scrollTop = input.scrollTop; highlight.parentElement.scrollLeft = input.scrollLeft; gutter.scrollTop = input.scrollTop; });
    for (const type of ['click', 'keyup', 'select']) input.addEventListener(type, () => this.onCursor());
    input.addEventListener('keydown', event => this.keydown(event));
  }
  load(text, path) {
    this.source = path;
    this.input.dataset.path = path;
    this.input.value = text;
    this.input.selectionStart = this.input.selectionEnd = 0;
    this.input.scrollTop = this.input.scrollLeft = 0;
    this.render(); this.onCursor();
  }
  render() {
    cancelAnimationFrame(this.raf);
    this.raf = requestAnimationFrame(() => {
      const text = this.input.value;
      this.highlight.innerHTML = highlightLuau(text);
      const count = Math.min(text.split('\n').length, 10000);
      this.gutter.textContent = Array.from({ length: count }, (_, i) => i + 1).join('\n');
      this.highlight.parentElement.scrollTop = this.input.scrollTop;
      this.highlight.parentElement.scrollLeft = this.input.scrollLeft;
    });
  }
  replace(start, end, value, cursor = start + value.length) {
    this.input.focus();
    this.input.setRangeText(value, start, end, 'end');
    this.input.setSelectionRange(cursor, cursor);
    this.input.dispatchEvent(new Event('input', { bubbles: true }));
  }
  selectLine(line) {
    const pos = positionForLine(this.input.value, line);
    this.input.focus(); this.input.setSelectionRange(pos, pos);
    this.input.scrollTop = Math.max(0, (line - 5) * (parseFloat(getComputedStyle(this.input).lineHeight) || 21));
    this.onCursor();
  }
  keydown(event) {
    const input = this.input, ctrl = event.ctrlKey || event.metaKey;
    if (ctrl && (event.key === 'Enter' || event.key === 's' || event.key === 'S' || event.key === 'p' || event.key === 'P' || event.key === 'b' || event.key === 'B' || event.key === 'f' || event.key === 'F')) {
      event.preventDefault(); this.onShortcut(event.key.toLowerCase()); return;
    }
    if (event.key === 'Tab') {
      event.preventDefault();
      const { selectionStart: start, selectionEnd: end } = input;
      if (start === end && !event.shiftKey) this.replace(start, end, '    ');
      else { const result = indentSelection(input.value, start, end, event.shiftKey); this.replace(0, input.value.length, result.source, result.end); input.setSelectionRange(result.start, result.end); }
      return;
    }
    if (event.key === 'Enter' && !ctrl && !event.altKey && !event.isComposing) {
      event.preventDefault(); const a = input.selectionStart, b = input.selectionEnd;
      this.replace(a, b, newlineIndent(input.value, a)); return;
    }
    if (input.selectionStart === input.selectionEnd && !ctrl && !event.altKey && !event.isComposing) {
      const a = input.selectionStart;
      if (PAIRS[event.key]) {
        event.preventDefault(); this.replace(a, a, event.key + PAIRS[event.key], a + 1); return;
      }
      if ([')', ']', '}'].includes(event.key) && input.value[a] === event.key) {
        event.preventDefault(); input.setSelectionRange(a + 1, a + 1); this.onCursor();
      }
    }
  }
  get position() { return currentLineAndColumn(this.input.value, this.input.selectionStart); }
}
