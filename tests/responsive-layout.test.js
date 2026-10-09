import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const css = await readFile(new URL('../src/v1.css',import.meta.url),'utf8');
test('mobile drawers are bounded to viewport and content scrolls internally', () => {
 assert.match(css,/width:min\(80vw,320px\)/);
 assert.match(css,/max-width:calc\(100vw - 44px\)/);
 assert.match(css,/\.side-content\s*\{/);
 assert.match(css,/overflow:auto/);
});
test('editor and output use available space instead of absolute pixels', () => {
 assert.match(css,/\.workspace-main\{[^}]*min-width:0/);
 assert.match(css,/\.editor-and-output\{[^}]*flex:1 1 auto/);
 assert.match(css,/\.output-panel\{[^}]*var\(--output-height\)/);
});
