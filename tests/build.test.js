import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const root = new URL('../', import.meta.url);
const read = async name => readFile(new URL(name, root), 'utf8');

test('entrypoint references local assets with relative paths', async () => {
  const html = await read('index.html');
  assert.match(html, /src="\.\/src\/main\.js\?v=0\.4\.1"/);
  assert.match(html, /href="\.\/src\/styles\.css\?v=0\.4\.1"/);
  assert.match(html, /src="https:\/\/cdnjs\.cloudflare\.com/);
  assert.doesNotMatch(html, /src="\/src\//);
});

test('critical element ids are not repeated', async () => {
  const html = await read('index.html');
  const ids = [...html.matchAll(/\bid="([^"]+)"/g)].map(x => x[1]);
  assert.equal(ids.length, new Set(ids).size);
  for (const id of ['code-input', 'runner-modal', 'file-tree', 'runner-frame-container', 'save-status']) assert.ok(ids.includes(id));
});

test('deployment publishes dist folder', async () => {
  const yaml = await read('.github/workflows/deploy.yml');
  assert.match(yaml, /actions\/deploy-pages@v4/);
  assert.match(yaml, /path: dist/);
  assert.match(yaml, /npm test/);
});


test('build uses public root paths, not nested /public assets', async () => {
  const build = await read('scripts/build.mjs');
  const worker = await read('src/wasm-worker.js');
  assert.match(build, /for \(const entry of await readdir/);
  assert.match(worker, /new URL\('\.\.\/wasm\/', import\.meta\.url\)/);
  assert.match(worker, /new URL\('\.\.\/public\/wasm\/', import\.meta\.url\)/);
  assert.match(worker, /luau-module\.js/);
  assert.match(await read('index.html'), /href="\.\/favicon\.svg"/);
  assert.doesNotMatch(worker, /import\(['"]\.\.\/public/);
});


test('publishing workflow checks runtime binary into main for Jekyll compatibility', async () => {
  const yaml = await read('.github/workflows/deploy.yml');
  const ignore = await read('.gitignore');
  assert.match(yaml, /contents: write/);
  assert.match(yaml, /git add public\/wasm\/luau-module\.js public\/wasm\/luau\.wasm/);
  assert.match(yaml, /git push origin HEAD:main/);
  assert.doesNotMatch(ignore, /^public\/wasm\/luau\.wasm$/m);
});

test('both source and Actions publishing layouts contain a compatible runtime', async () => {
  const { stat } = await import('node:fs/promises');
  const { fileURLToPath } = await import('node:url');
  for (const prefix of ['public/wasm', 'dist/wasm']) {
    const wasm = fileURLToPath(new URL(prefix + '/luau.wasm', root));
    const loader = fileURLToPath(new URL(prefix + '/luau-module.js', root));
    assert.ok((await stat(wasm)).size > 1_000_000);
    assert.ok((await stat(loader)).size > 10000);
  }
});
