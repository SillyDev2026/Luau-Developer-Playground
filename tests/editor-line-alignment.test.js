import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const read=path=>readFile(new URL('../'+path,import.meta.url),'utf8');
const rule=(css,selector)=>{const at=css.indexOf(selector);assert.ok(at>=0,'CSS selector missing: '+selector);const from=css.indexOf('{',at);return css.slice(from+1,css.indexOf('}',from));};

test('gutter, textarea and syntax overlay use exactly the same top and bottom offsets',async()=>{
 const css=await read('src/v1.css');
 const gutter=rule(css,'.line-gutter{flex:0 0 48px;');
 const code=rule(css,'.highlight-scroll pre,#code-input{margin:0;');
 for(const key of ['--editor-pad-top','--editor-pad-bottom','--editor-line-height']){
   assert.match(css,new RegExp(key.replaceAll('-','\\-')+':'),'Editor CSS variable missing '+key);
   assert.ok(gutter.includes('var('+key+')'),'Gutter not using '+key);
   assert.ok(code.includes('var('+key+')'),'Code/highlighting not using '+key);
 }
 assert.match(gutter,/padding:var\(--editor-pad-top\) 9px var\(--editor-pad-bottom\) 0/);
 assert.match(code,/padding:var\(--editor-pad-top\) var\(--editor-pad-right\) var\(--editor-pad-bottom\) var\(--editor-pad-left\)/);
 assert.match(gutter,/font:var\(--editor-font\)\/var\(--editor-line-height\)/);
 assert.match(code,/font:var\(--editor-font\)\/var\(--editor-line-height\)/);
 assert.doesNotMatch(code,/120px|45px/);
 assert.match(gutter,/box-sizing:border-box/);
 assert.match(code,/box-sizing:border-box/);
});

test('Android portrait and landscape use one shared vertical layout, 16px minimum and scroll padding',async()=>{
 const [css,js]=await Promise.all(['src/v1.css','src/v1.js'].map(read));
 const breakpoint='@media (max-width:820px), (hover:none) and (pointer:coarse) and (max-height:700px)';
 assert.ok(css.includes(breakpoint));
 assert.match(css,/:root\{--editor-pad-top:11px;--editor-pad-bottom:18px;--editor-pad-left:10px;--editor-pad-right:12px;\}/);
 assert.match(css,/#code-input\{scroll-padding-top:var\(--editor-pad-top\);scroll-padding-bottom:72px;\}/);
 assert.match(css,/#code-input,\.highlight-scroll pre,\.line-gutter\{font-size:max\(16px,var\(--editor-font\)\);\}/);
 assert.match(js,/usesMobileNavigation\(\) \? Math\.max\(16,p\.fontSize\) : p\.fontSize/);
});

test('scrolling and file opening keep input, line numbers and syntax highlighting synchronized',async()=>{
 const [js,editor]=await Promise.all(['src/v1.js','src/v1-editor.js'].map(read));
 assert.match(editor,/highlight\.parentElement\.scrollTop = input\.scrollTop/);
 assert.match(editor,/highlight\.parentElement\.scrollLeft = input\.scrollLeft/);
 assert.match(editor,/gutter\.scrollTop = input\.scrollTop/);
 assert.match(editor,/this\.highlight\.parentElement\.scrollTop = this\.input\.scrollTop/);
 assert.match(editor,/this\.gutter\.textContent\s*=\s*Array\.from/);
 assert.match(js,/function openFile\(path\).*workspace\.open\(path\)/);
});
