import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { MOBILE_NAV_QUERY, usesMobileNavigation } from '../src/mobile-layout.js';

const read=name=>readFile(new URL('../'+name,import.meta.url),'utf8');

test('responsive phone-landscape media query is shared by mobile JavaScript and CSS',async()=>{
  assert.equal(MOBILE_NAV_QUERY,'(max-width:820px), (hover:none) and (pointer:coarse) and (max-height:700px)');
  assert.equal(usesMobileNavigation(query=>({matches:query===MOBILE_NAV_QUERY})),true);
  assert.equal(usesMobileNavigation(()=>({matches:false})),false);
  const css=await read('src/v1.css');
  const landscape='(hover:none) and (pointer:coarse) and (max-height:700px)';
  assert.ok(css.includes('@media (max-width:820px), '+landscape+' {'));
  assert.ok(css.split(landscape).length>=5,'drawer, dock and layout rules must cover landscape phones');
  assert.match(css,/\.sidebar\.is-mobile-open[^}]*transform:translateX\(0\)/);
  assert.match(css,/\.side-shade:not\(\.hidden\)[^{]*\{[^}]*display:block/);
  assert.match(css,/\.mobile-dock\{display:grid/);
  assert.match(css,/\.mobile-dock\{grid-template-columns:repeat\(9,minmax\(0,1fr\)\)!important/);
});

test('Explorer control stays available on desktop and phone landscape and opens Files',async()=>{
  const [html,js,css]=await Promise.all(['index.html','src/v1.js','src/v1.css'].map(read));
  assert.equal((html.match(/id="explorer-toggle"/g)||[]).length,1);
  assert.match(html,/id="explorer-toggle"[^>]*aria-controls="sidebar"/);
  assert.match(html,/id="explorer-toggle"[^>]*aria-expanded="false"/);
  assert.match(html,/id="mobile-files"/);
  assert.match(html,/id="hide-sidebar"/);
  assert.match(js,/\$\('explorer-toggle'\)\.addEventListener\('click', openExplorer\)/);
  assert.match(js,/\$\('mobile-files'\)\.addEventListener\('click', openExplorer\)/);
  assert.match(js,/function openExplorer\(\) \{/);
  assert.match(js,/setSide\('files'\)/);
  assert.match(js,/if \(usesMobileNavigation\(\)\) \{/);
  assert.match(js,/matchMedia\(MOBILE_NAV_QUERY\)\.addEventListener\?\.\('change',\(\)=>\{closeMobile\(\);setOutputExpanded\(false\);\}\)/);
  assert.match(css,/\.explorer-header-btn\s*\{display:inline-flex/);
  assert.match(css,/\.explorer-header-btn:focus-visible/);
  assert.match(js,/\$\('side-shade'\)\.addEventListener\('click', closeMobile\)/);
  assert.match(js,/\$\('hide-sidebar'\)\.addEventListener\('click', closeMobile\)/);
});

test('mobile bottom navigation fits nine destinations including Files and Output in portrait',async()=>{
  const [html,css]=await Promise.all(['index.html','src/v1.css'].map(read));
  const match=html.match(/<nav class="mobile-dock"[^>]*>([\s\S]*?)<\/nav>/);
  assert.ok(match);
  assert.equal((match[1].match(/<button\s/g)||[]).length,9);
  assert.ok(match[1].indexOf('id="mobile-files"')<match[1].indexOf('id="mobile-output"'));
  assert.ok(match[1].indexOf('id="mobile-output"')<match[1].indexOf('id="mobile-run"'));
  assert.match(css,/@media \(max-width:480px\) and \(pointer:coarse\)/);
  assert.match(css,/\.mobile-dock \{display:flex;overflow-x:auto/);
  assert.match(css,/\.mobile-dock button \{flex:0 0 54px/);
});

test('mobile changes do not remove editor actions or modify project persistence',async()=>{
  const [html,js]=await Promise.all(['index.html','src/v1.js'].map(read));
  for(const id of ['run-btn','stop-btn','new-file','import-file','file-filter','code-input','mobile-library','mobile-run','mobile-dashboard','mobile-settings'])assert.ok(html.includes('id="'+id+'"'),id);
  assert.match(js,/function openFile\(path\).*workspace\.open\(path\); closeMobile\(\); setOutputExpanded\(false\); if\(!usesMobileNavigation\(\)\)editor\.input\.focus\(\)/);
  assert.match(js,/workspace\.open\(path\)/);
  assert.match(js,/workspace\.project/);
});
