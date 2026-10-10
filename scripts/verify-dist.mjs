// Fail CI if the uploaded Pages artifact would be missing its WASM runtime.
import assert from 'node:assert/strict';
import { readFile, stat } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const out = join(root, 'dist');
const html = await readFile(join(out, 'index.html'), 'utf8');
const worker = await readFile(join(out, 'src/wasm-worker.js'), 'utf8');
const bundle = await readFile(join(out, 'src/module-bundle.js'), 'utf8');
assert.match(bundle, /bundleProject/);
const glue = await readFile(join(out, 'wasm/luau-module.js'), 'utf8');
const binary = await readFile(join(out, 'wasm/luau.wasm'));
assert.match(html, /href="\.\/favicon\.svg"/);
assert.match(html, /src="\.\/src\/v1\.js\?v=1\.7\.0"/);
assert.match(worker, /new URL\('\.\.\/wasm\/', import\.meta\.url\)/);
assert.match(worker, /new URL\('\.\.\/public\/wasm\/', import\.meta\.url\)/);

assert.match(glue, /export default createLuauModule/);
assert.equal(binary.subarray(0, 4).toString('hex'), '0061736d');
assert.ok(binary.length > 1_000_000);
for(const [name,minSize] of [['FastNum.lua',90000],['NanoNum.lua',300000],['OmegaNum.lua',70000]]) {
  const code = await readFile(join(out,'libraries',name),'utf8');
  assert.ok(code.length > minSize,`Missing or truncated bundled library: ${name}`);
}
await stat(join(out, 'favicon.svg'));
for (const path of ['src/dashboard.js','src/dashboard-model.js','src/dashboard.css','src/studio-libraries.js','src/v15-ui.js','src/v15.css','src/v15-analysis.js','src/v15-modules.js','src/v15-bench.js','src/v15-zip.js','src/v15-settings.js','src/v1.js','src/v1.css','src/v1-model.js','src/v1-editor.js','src/v1-zip.js','src/v1-graph.js','src/auto-require.css','src/completion-geometry.js','manifest.webmanifest','sw.js']) await stat(join(out, path));
assert.equal((await readFile(join(root, 'public/wasm/luau.wasm'))).length, binary.length);
console.log(`GitHub Pages distribution verified: ${binary.length} WASM bytes; valid loader and relative URLs`);

// Source-only Roblox Studio imports are pinned and checked during deployment.
for(const name of ['NexusDataStore','ZonePlusV2','BufferUtil','Compression','Signal','Promise','NetStream']) {
  const studio = await readFile(join(out,'studio-libraries',name+'.lua'));
  assert.ok(studio.length > 4000,`Missing pinned Studio package: ${name}`);
}

for (const module of ['TestTools.luau','MathKit.luau','registry.json']) await stat(join(out,'community',module));
await stat(join(out,'src/github-modules.js'));

await stat(join(out,'community/tests/MathKitTests.luau'));
