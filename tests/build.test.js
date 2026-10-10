import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, stat } from 'node:fs/promises';
const root = new URL('../', import.meta.url);
const read = async path => readFile(new URL(path, root), 'utf8');

test('v1 entrypoint uses versioned local shell assets and preserves runtime files', async () => {
  const html = await read('index.html');
  assert.match(html, /href="\.\/src\/v1\.css\?v=1\.7\.0"/);
  assert.match(html, /src="\.\/src\/v1\.js\?v=1\.7\.0"/);
  assert.match(html, /href="\.\/manifest\.webmanifest"/);
  assert.doesNotMatch(html, /src="https:\/\//);
  for (const path of ['public/wasm/luau.wasm','dist/wasm/luau.wasm','dist/libraries/FastNum.lua','dist/sw.js']) assert.ok((await stat(new URL(path, root))).size > 100);
});
test('v1 shell has accessible editors and no duplicate ids', async () => {
  const html = await read('index.html');
  const ids = [...html.matchAll(/\bid="([^"]+)"/g)].map(x=>x[1]);
  assert.equal(new Set(ids).size,ids.length);
  for (const id of ['code-input','file-tree','sidebar','inspector','output-content','find-panel','modal-backdrop','dialog','tabs','mobile-dock','run-btn','stop-btn']) {
    assert.match(html,new RegExp(`id="${id}"`));
  }
});
test('deployment uploads verified build to GitHub Pages', async () => {
  const yaml = await read('.github/workflows/deploy.yml');
  assert.match(yaml,/actions\/deploy-pages@v4/);
  assert.match(yaml,/path: dist/);
  assert.match(yaml,/npm run check/);
  assert.doesNotMatch(yaml,/git push origin HEAD:main/);
});
