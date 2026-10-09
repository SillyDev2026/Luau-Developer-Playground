import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { placeCompletionPopup } from '../src/completion-geometry.js';

const read = path => readFile(new URL(path, import.meta.url), 'utf8');

test('popup stays inside a narrow Android viewport and preserves width', () => {
  const pos = placeCompletionPopup({x:160,y:200,lineHeight:24},{width:290,height:450},{width:425,height:260});
  assert.ok(pos.left >= 0);
  assert.ok(pos.left+pos.width<=290);
  assert.ok(pos.top>=0 && pos.top+pos.height<=450);
  assert.ok(pos.height>100);
});

test('completion flips above cursor near bottom of screen', () => {
  const pos=placeCompletionPopup({x:80,y:360,lineHeight:23},{width:310,height:400},{width:420,height:250});
  assert.equal(pos.below,false);
  assert.ok(pos.top+pos.height<360);
});

test('completion below cursor when enough space exists', () => {
  const pos=placeCompletionPopup({x:30,y:42,lineHeight:22},{width:500,height:520},{width:380,height:260});
  assert.equal(pos.below,true);
  assert.ok(pos.top>42);
});

test('v1 autocomplete uses opaque existing palette instead of legacy undefined variables', async () => {
  const css=await read('../src/auto-require.css');
  const shell=await read('../src/v1.css');
  assert.doesNotMatch(css,/var\(--shell\)/);
  assert.doesNotMatch(css,/var\(--hover\)/);
  assert.match(css,/background:var\(--panel,#101826\)/);
  assert.match(css,/z-index:65/);
  assert.doesNotMatch(shell,/top:45px!important/);
});

test('offline service worker precaches the caret positioning helper',async()=>{
  const sw=await read('../public/sw.js');
  assert.match(sw,/completion-geometry\.js/);
  assert.match(sw,/luauforge-v1\.5\.0/);
});

test('phone autocomplete cannot stretch to fill editor due to a bottom anchor',async()=>{
  const css=await read('../src/auto-require.css');
  assert.doesNotMatch(css,/\.auto-require-menu\{[^}]*bottom:8px/);
  assert.match(css,/height:max-content/);
});
