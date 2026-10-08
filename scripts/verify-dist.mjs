// Fail CI if the uploaded Pages artifact would be missing its WASM runtime.
import assert from 'node:assert/strict';
import { readFile, stat } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
const out = join(dirname(fileURLToPath(import.meta.url)), '..', 'dist');
const html = await readFile(join(out, 'index.html'), 'utf8');
const worker = await readFile(join(out, 'src/wasm-worker.js'), 'utf8');
const glue = await readFile(join(out, 'wasm/luau-module.js'), 'utf8');
const binary = await readFile(join(out, 'wasm/luau.wasm'));
assert.match(html, /href="\.\/favicon\.svg"/);
assert.match(worker, /new URL\('\.\.\/wasm\/'/);
assert.match(worker, /new URL\('\.\.\/public\/wasm\/'/);

assert.match(glue, /export default createLuauModule/);
assert.equal(binary.subarray(0, 4).toString('hex'), '0061736d');
assert.ok(binary.length > 1_000_000);
await stat(join(out, 'favicon.svg'));
console.log(`GitHub Pages distribution verified: ${binary.length} WASM bytes; valid loader and relative URLs`);
