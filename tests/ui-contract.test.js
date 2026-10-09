import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const html = await readFile(new URL('../index.html', import.meta.url),'utf8');
const js = await readFile(new URL('../src/v1.js', import.meta.url),'utf8');
const css = await readFile(new URL('../src/v1.css', import.meta.url),'utf8');
test('v1 app handlers only reference existing ids', () => {
 const used=[...js.matchAll(/\$\('([a-z][\w-]*)'\)/g)].map(x=>x[1]);
 const missing=[...new Set(used)].filter(id=>!html.includes(`id="${id}"`));
 assert.deepEqual(missing,[]);
 assert.ok(new Set(used).size>50);
});
test('v1 has phone dock, responsive panels, accessible output', () => {
 for(const id of ['mobile-dock','mobile-files','mobile-settings','side-shade','code-input','output-content','find-input','file-filter']) assert.match(html,new RegExp(`id="${id}"`));
 assert.match(css,/@media \(max-width:820px\)/);
 assert.match(css,/80vw,320px/);
 assert.match(css,/100dvh/);
 assert.match(css,/safe-area-inset-bottom/);
 assert.match(css,/repeat\(3,minmax\(0,1fr\)\)/);
});
