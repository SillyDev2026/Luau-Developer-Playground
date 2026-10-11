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


test('bracket matching ignores quoted strings and comments',()=>{
 const source='print("( ignored )", (2 + 3)) -- ((\n';
 assert.deepEqual(matchBracket(source,5),[5,source.indexOf(') --')]);
 assert.equal(matchBracket(source,source.indexOf('( ignored')),null);
 assert.equal(matchBracket('-- (comment)',3),null);
 const inner=source.indexOf('(2 + 3)');
 assert.deepEqual(matchBracket(source,inner),[inner,inner+6]);
});
