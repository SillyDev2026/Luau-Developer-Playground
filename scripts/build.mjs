// Production build. Use the same public-directory semantics as Vite: /public/* -> /*.
// Never publish a site with an editor that points at missing runtime files.
import { cp, mkdir, rm, writeFile, readFile, stat, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const out = join(root, 'dist');
const wasm = join(root, 'public/wasm/luau.wasm');
const glue = join(root, 'public/wasm/luau-module.js');
const bytes = await readFile(wasm).catch(() => null);
const script = await readFile(glue, 'utf8').catch(() => '');
if (!bytes || bytes.length < 1_000_000 || bytes.subarray(0, 4).toString('hex') !== '0061736d') {
  throw new Error('Missing or invalid Luau WASM asset. Run npm run fetch:wasm before npm run build.');
}
if (!script.includes('createLuauModule') || !script.includes('export default')) {
  throw new Error('Missing or invalid Luau WASM JavaScript loader. Run npm run fetch:wasm before npm run build.');
}
await rm(out, { recursive: true, force: true });
await mkdir(out, { recursive: true });
await cp(join(root, 'index.html'), join(out, 'index.html'));
await cp(join(root, 'src'), join(out, 'src'), { recursive: true });
for (const entry of await readdir(join(root, 'public'), { withFileTypes: true })) {
  await cp(join(root, 'public', entry.name), join(out, entry.name), { recursive: entry.isDirectory() });
}
await writeFile(join(out, '.nojekyll'), '');
if ((await stat(join(out, 'wasm/luau-module.js'))).size < 10000 || (await stat(join(out, 'wasm/luau.wasm'))).size < 1_000_000) {
  throw new Error('WASM assets were lost during site packaging');
}
console.log('Built complete GitHub Pages site in dist/ (WASM and loader verified).');
