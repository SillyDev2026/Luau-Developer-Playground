import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const read=path=>readFile(new URL('../'+path,import.meta.url),'utf8');

test('Output can always be opened from the topbar or mobile bottom bar',async()=>{
  const [html,js]=await Promise.all(['index.html','src/v1.js'].map(read));
  for(const id of ['workspace-main','explorer-toggle','mobile-files','output-toggle','mobile-output','output-panel','output-back','output-content']){
    assert.equal((html.match(new RegExp('id="'+id+'"','g'))||[]).length,1,'Missing or duplicate '+id);
  }
  assert.match(html,/id="output-toggle"[^>]*aria-controls="output-panel"[^>]*aria-expanded="false"/);
  assert.match(html,/id="mobile-output"[^>]*aria-controls="output-panel"[^>]*aria-expanded="false"/);
  assert.match(js,/\$\('output-toggle'\)\.addEventListener\('click', toggleOutput\)/);
  assert.match(js,/\$\('mobile-output'\)\.addEventListener\('click', toggleOutput\)/);
  assert.match(js,/\$\('output-back'\)\.addEventListener\('click',\(\)=>setOutputExpanded\(false\)\)/);
  assert.match(js,/function openOutput\(\) \{/);
  assert.match(js,/closeMobile\(\);\s*if \(document\.activeElement === editor\.input\) editor\.input\.blur\(\);\s*setOutputExpanded\(true\)/);
});

test('Expanding Output reclaims landscape height without making logs disappear',async()=>{
  const [css,js]=await Promise.all(['src/v1.css','src/v1.js'].map(read));
  for(const rule of [
    '.workspace-main.output-expanded .editor-panel',
    '.workspace-main.output-expanded .editor-and-output',
    '.workspace-main.output-expanded .output-panel',
    '.workspace-main.output-expanded .output-content',
    '.workspace-main.output-expanded .output-tabs',
    '.workspace-main.output-expanded .output-focus-heading'
  ])assert.ok(css.includes(rule),rule);
  assert.match(css,/\.workspace-main\.output-expanded \.output-panel\{[^}]*max-height:none!important/);
  assert.match(css,/\.workspace-main\.output-expanded \.editor-panel[^}]*display:none!important/);
  assert.match(js,/function setOutputExpanded\(expanded\)/);
  assert.match(js,/\.classList\.toggle\('output-expanded',expanded\)/);
  assert.match(js,/for\(const id of \['output-toggle','mobile-output'\]\)/);
  assert.match(js,/function switchOutput\(view, focusOnMobile=false\)/);
  assert.match(js,/switchOutput\('console',true\)/);
  assert.match(js,/switchOutput\('problems',true\)/);
  assert.match(js,/switchOutput\('bytecode',true\)/);
  assert.match(js,/switchOutput\('benchmarks',true\)/);
  assert.match(js,/switchOutput\('tests',true\)/);
});

test('Explorer and file selection close mobile overlays and do not summon Android keyboard',async()=>{
  const js=await read('src/v1.js');
  assert.match(js,/function openExplorer\(\) \{\s*setOutputExpanded\(false\);/);
  assert.match(js,/function openFile\(path\).*workspace\.open\(path\); closeMobile\(\); setOutputExpanded\(false\); if\(!usesMobileNavigation\(\)\)editor\.input\.focus\(\)/);
  assert.match(js,/matchMedia\(MOBILE_NAV_QUERY\)\.addEventListener\?\.\('change',\(\)=>\{closeMobile\(\);setOutputExpanded\(false\);\}\)/);
  assert.match(js,/\$\('side-shade'\)\.addEventListener\('click', closeMobile\)/);
});

test('output controls preserve nine dock destinations and accessible content',async()=>{
  const [html,css]=await Promise.all(['index.html','src/v1.css'].map(read));
  const nav=html.match(/<nav class="mobile-dock"[^>]*>([\s\S]*?)<\/nav>/);
  assert.ok(nav);
  assert.equal((nav[1].match(/<button\s/g)||[]).length,9);
  assert.match(css,/\.mobile-dock\{grid-template-columns:repeat\(9,minmax\(0,1fr\)\)!important/);
  assert.match(html,/id="output-content" aria-live="polite"/);
  for(const key of ['console','problems','bytecode','benchmarks','tests'])assert.ok(html.includes('data-output="'+key+'"'));
  assert.match(html,/id="output-back"[^>]*aria-label="Return to code editor"/);
});
