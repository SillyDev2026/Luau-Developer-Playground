// Fetch pinned prebuilt official Luau Playground WASM and matching Emscripten JS.
// No unpinned main-branch downloads, no secrets, no runtime CDN dependency.
import { mkdir, writeFile, stat } from 'node:fs/promises';
import { join } from 'node:path';
const commit = 'e232f443148728fe5b8e714f1796aaa676287df7';
const base = `https://raw.githubusercontent.com/luau-lang/playground/${commit}/`;
const assets = [
  ['public/wasm/luau.wasm', 'luau.wasm'],
  ['src/lib/luau/luau-module.js', 'luau-module.js'],
];
const dir = join(import.meta.dirname, '../public/wasm');
await mkdir(dir, { recursive: true });
for (const [from, to] of assets) {
  const res = await fetch(base + from, { signal: AbortSignal.timeout(120000) });
  if (!res.ok) throw new Error(`Upstream ${to} fetch failed (${res.status})`);
  const data = new Uint8Array(await res.arrayBuffer());
  if (to.endsWith('.wasm') && (data.length < 1_000_000 || data[0] !== 0 || data[1] !== 97 || data[2] !== 115 || data[3] !== 109)) throw new Error('Invalid Luau WASM file');
  if (to.endsWith('.js') && !new TextDecoder().decode(data).includes('createLuauModule')) throw new Error('Invalid Luau JS glue file');
  await writeFile(join(dir, to), data);
  console.log(`Fetched pinned ${to}: ${(await stat(join(dir, to))).size} bytes`);
}
