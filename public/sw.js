/* LuauForge 1.0 offline app shell. Projects remain in localStorage and are
 * never uploaded. Cache is scoped to this GitHub Pages project, not the origin.
 */
const CACHE = 'luauforge-v1.6.0';
const APP = './';
const CORE = [
  './', './index.html', './favicon.svg', './manifest.webmanifest',
  './src/v1.js', './src/v1.css', './src/auto-require.css',
  './src/v1-editor.js', './src/v1-model.js', './src/v1-zip.js', './src/v1-graph.js',
  './src/store.js', './src/snapshots.js', './src/highlight.js', './src/editor-utils.js',
  './src/auto-require.js', './src/completion-geometry.js', './src/intellisense.js', './src/editor-intelligence.js',
  './src/roblox-api.js', './src/module-bundle.js', './src/wasm-client.js',
  './src/wasm-worker.js', './src/builtin-libraries.js',
  './src/v15-ui.js', './src/v15.css', './src/v15-analysis.js', './src/v15-modules.js',
  './src/v15-bench.js', './src/v15-zip.js', './src/v15-settings.js',
  './src/dashboard.js', './src/dashboard-model.js', './src/dashboard.css', './src/studio-libraries.js',
  './wasm/luau.wasm', './wasm/luau-module.js',
  './libraries/FastNum.lua', './libraries/NanoNum.lua', './libraries/OmegaNum.lua',
];
self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    await Promise.allSettled(CORE.map(async path => {
      const request = new Request(new URL(path, self.registration.scope), { cache: 'reload' });
      const response = await fetch(request);
      if (response.ok && response.type !== 'opaque') await cache.put(request, response);
    }));
    await self.skipWaiting();
  })());
});
self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const names = await caches.keys();
    await Promise.all(names.filter(name => name.startsWith('luauforge-') && name !== CACHE).map(name => caches.delete(name)));
    await self.clients.claim();
  })());
});
self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== location.origin || !url.href.startsWith(self.registration.scope)) return;
  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    const cached = await cache.match(request, { ignoreSearch: true });
    try {
      const response = await fetch(request);
      if (response.ok && response.type !== 'opaque') cache.put(request, response.clone()).catch(() => {});
      return response;
    } catch (error) {
      if (cached) return cached;
      if (request.mode === 'navigate') return cache.match(new URL(APP, self.registration.scope));
      throw error;
    }
  })());
});
