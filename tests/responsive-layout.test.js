import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const css = await readFile(new URL('../src/responsive-layout.css', import.meta.url), 'utf8');
const html = await readFile(new URL('../index.html', import.meta.url), 'utf8');

test('mobile viewport scales drawers proportionally and honors safe area', () => {
  assert.match(css, /width:min\(80vw,320px\)/);
  assert.match(css, /top:var\(--mobile-header\)/);
  assert.match(css, /bottom:var\(--mobile-dock\)/);
  assert.match(css, /env\(safe-area-inset-bottom/);
  assert.match(css, /height:100dvh/);
});

test('library action buttons have text sizing independent of icon-only button class', () => {
  assert.match(css, /\.builtin-catalog-actions\s*\{\s*display:grid/);
  assert.match(css, /grid-template-columns:repeat\(3,minmax\(0,1fr\)\)/);
  assert.match(css, /\.builtin-catalog-actions button\s*\{[^}]*font:600 12px\/1\.2/s);
  assert.match(css, /\.builtin-catalog-actions button\s*\{[^}]*min-width:0/s);
});

test('new stylesheet version invalidates older mobile layout cache', () => {
  assert.match(html, /responsive-layout\.css\?v=0\.4\.1/);
  assert.match(html, /main\.js\?v=0\.4\.1/);
});
