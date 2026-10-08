import test from 'node:test';
import assert from 'node:assert/strict';
import { findMatches, replaceAllLiteral, positionForLine, currentLineAndColumn, indentSelection } from '../src/editor-utils.js';

test('literal search and case sensitivity', () => {
  assert.deepEqual(findMatches('Ab ab ABC', 'ab'), [0, 3, 6]);
  assert.deepEqual(findMatches('Ab ab ABC', 'ab', true), [3]);
  assert.deepEqual(findMatches('abc', ''), []);
  assert.deepEqual(findMatches('test.*test', '.*'), [4]);
});
test('replacement treats query literally', () => {
  assert.deepEqual(replaceAllLiteral('a.b a*b', '.', '-'), { source: 'a-b a*b', count: 1 });
  assert.deepEqual(replaceAllLiteral('Hi hi', 'hi', 'bye'), { source: 'bye bye', count: 2 });
  assert.deepEqual(replaceAllLiteral('abc', '', 'x'), { source: 'abc', count: 0 });
});
test('line and column calculations handle last line', () => {
  assert.equal(positionForLine('a\nb\nlast', 3), 4);
  assert.equal(positionForLine('a\nb', 200), 3);
  assert.equal(positionForLine('a\nb', 0), 0);
  assert.deepEqual(currentLineAndColumn('abc\ndef', 5), { line: 2, column: 2 });
});
test('multiline indent/outdent preserves text and selection bounds', () => {
  const input = 'alpha\nbeta\ngamma';
  const result = indentSelection(input, 0, 10);
  assert.equal(result.source, '    alpha\n    beta\ngamma');
  assert.equal(indentSelection(result.source, 0, result.end, true).source, input);
});
