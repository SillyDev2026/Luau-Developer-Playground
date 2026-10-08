import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const html = await readFile(new URL('../index.html', import.meta.url), 'utf8');
const main = await readFile(new URL('../src/main.js', import.meta.url), 'utf8');
const css = await readFile(new URL('../src/styles.css', import.meta.url), 'utf8');
test('every referenced DOM id exists in the page', () => {
  const refs = [...main.matchAll(/\$\('([a-z][\w-]*)'\)/g)].map(m => m[1]);
  const unique = [...new Set(refs)];
  const missing = unique.filter(id => !html.includes(`id="${id}"`));
  assert.deepEqual(missing, []);
  assert.ok(unique.length > 40);
});
test('responsive width and resize controls exist', () => {
  assert.match(css, /max-width:820px/);
  assert.match(css, /max-width:430px/);
  assert.match(html, /id="output-resizer"[^>]*role="separator"/);
  assert.match(html, /id="sidebar-resizer"[^>]*role="separator"/);
  assert.match(css, /--editor-font/);
});
test('v0.2 includes accessible modal and search controls', () => {
  for (const id of ['runner-modal', 'command-modal', 'snapshot-modal']) assert.match(html, new RegExp(`id="${id}"[^>]*role="dialog"`));
  for (const id of ['find-input', 'replace-input', 'file-filter', 'code-input']) assert.match(html, new RegExp(`id="${id}"`));
});
