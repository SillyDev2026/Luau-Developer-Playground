import test from 'node:test';
import assert from 'node:assert/strict';
import { newlineIndent,matchBracket } from '../src/v1-editor.js';
test('auto indent retains indentation and increases in a do block',()=>{
 const str='    if ready then';assert.equal(newlineIndent(str,str.length),'\n        ');
 assert.equal(newlineIndent('  print(1)',10),'\n  ');
});
test('bracket match finds pairs without searching out of bounds',()=>{
 assert.deepEqual(matchBracket('return (1 + (2 * 3))',7),[7,19]);
 assert.equal(matchBracket('plain',2),null);
});
