// Source-only Roblox Studio packages. Never load these into standalone Luau WASM.
// All sources are pinned to a specific Git commit to prevent silent upstream changes.
export const STUDIO_LIBRARIES = Object.freeze([
  { id: 'NexusDataStore', blobSha: 'f3dd469b5605c4ca8a04255c43fe0e02814ee3e1', label: 'NexusDataStore', repo: 'NexusDataStore', commit: 'ebe164ee4af64671f6d06222ea3d313364a937b6', file: 'DataStore.lua', filename: 'NexusDataStore.lua', environment: 'studio-server', dependencies: ['PlayersData ModuleScript child (create your own schema)', 'Compression module (optional sibling)'], purpose: 'Persistent player data, session locking, compression and recovery', methods: ['OpenAsync()', 'OpenPlayerAsync()', 'GetSession()', 'SaveAsync()', 'Validate()'], example: `-- Roblox Studio SERVER ONLY\n-- Place NexusDataStore in ServerScriptService with its required PlayersData child.\nlocal ServerScriptService = game:GetService("ServerScriptService")\nlocal NexusDataStore = require(ServerScriptService.NexusDataStore)\n-- Check the repository README for the current configuration and session API.\nprint("NexusDataStore loaded:", type(NexusDataStore))\n` },
  { id: 'ZonePlusV2', blobSha: 'b5543e5f47c250279400ae4bd91e8d5d6b2b7f7a', label: 'ZonePlusNext', repo: 'ZonePlusV2', commit: 'dd7f81ccef8ad264187a6ad7d8243fb697a466ca', file: 'ZonePlus.lua', filename: 'ZonePlusV2.lua', environment: 'studio', dependencies: ['Roblox Workspace, RunService, Players'], purpose: 'Spatial zones, overlap detection and spatial queries', methods: ['new(parts)', 'Version()', 'Destroy()'], example: `-- Roblox Studio ONLY\nlocal ReplicatedStorage = game:GetService("ReplicatedStorage")\nlocal ZonePlusNext = require(ReplicatedStorage.ZonePlusNext)\nprint("ZonePlus version:", ZonePlusNext.Version())\n-- Consult the current README for constructing and destroying zones.\n` },
  { id: 'BufferUtil', blobSha: '109bf5e88fe35d741f0b6b4dc1f87439860a13b3', label: 'BufferUtil', repo: 'BufferUtil', commit: 'a7472b5a1f95442ce589253f5198644ce1ce0d22', file: 'buffer.lua', filename: 'BufferUtil.lua', environment: 'studio', dependencies: ['Roblox buffer and vector types for some APIs'], purpose: 'Typed buffers, bit cursors and compact serialization', methods: ['VERSION', 'writeu8()', 'readu8()'], example: `-- Import into ReplicatedStorage in Roblox Studio\nlocal BufferUtil = require(game:GetService("ReplicatedStorage").BufferUtil)\nprint(BufferUtil.VERSION)\n` },
  { id: 'Compression', blobSha: 'ec6a1e11667e62273b1393ed880ff7514deefa37', label: 'Compression', repo: 'Compression', commit: '2742dc24e93ccf5305af56521d5b407c26e95d7a', file: 'Compress.lua', filename: 'Compression.lua', environment: 'studio', dependencies: ['Roblox datatypes for some codecs'], purpose: 'Data and buffer compression with schema support', methods: ['Version()', 'Compress()', 'Decompress()'], example: `local Compression = require(game:GetService("ReplicatedStorage").Compression)\nprint("Compression loaded:", type(Compression))\n-- See the upstream README for a supported encoding/decoding pair.\n` },
  { id: 'Signal', blobSha: '6456434563f7b1783bf0f8b0f09e40c784938b4f', label: 'Signal', repo: 'Signal', commit: 'a4437e9c0c8e912a80f778f23ada2b7d3be14ac6', file: 'Signal.lua', filename: 'Signal.lua', environment: 'studio', dependencies: ['EventBus ModuleScript sibling', 'Roblox task scheduler'], purpose: 'Typed signals and event dispatch', methods: ['new()', 'Connect()', 'Fire()', 'Disconnect()'], example: `-- Place EventBus beside Signal in ReplicatedStorage\nlocal Signal = require(game:GetService("ReplicatedStorage").Signal)\nlocal event = Signal.new()\nprint("Signal ready:", event ~= nil)\n` },
  { id: 'Promise', blobSha: 'f41d8e8f5b6c6e6d82e7c244130baeb41905c8b3', label: 'Promise', repo: 'Promise', commit: 'd9c691178d674ca1ff854be49cea82e0994266f7', file: 'Promise.lua', filename: 'Promise.lua', environment: 'studio', dependencies: ['HttpService', 'Roblox task scheduler'], purpose: 'Async promises with cancellation', methods: ['new(executor)', 'resolve(value)', 'reject(reason)'], example: `local Promise = require(game:GetService("ReplicatedStorage").Promise)\nprint("Promise loaded:", type(Promise))\n` },
  { id: 'NetStream', blobSha: '82e98f6b1860b6751eb14db812b4b6c65d7f2d01', label: 'NetStream', repo: 'NetStream', commit: '4c07f1e019130414edbefe4863df6fea43fba0fb', file: 'NetworkHandler/NetStream.lua', filename: 'NetStream.lua', environment: 'studio', dependencies: ['NetworkHandler/Modules/BitBuffer', 'BufferPool', 'BufferUtil', 'RunService', 'other NetworkHandler modules'], purpose: 'Roblox networking with packed events', methods: ['new()', ':event()', ':onCall()', ':start()'], example: `-- Import the entire NetworkHandler folder, not just this source file.\nlocal NetStream = require(game:GetService("ReplicatedStorage").NetworkHandler.NetStream)\nprint("NetStream:", type(NetStream))\n` },
]);
export const studioLibraryById = id => STUDIO_LIBRARIES.find(lib => lib.id === id) || null;
export function studioLibraryURL(lib) {
  if (!STUDIO_LIBRARIES.includes(lib)) throw new Error('Unknown Studio library');
  return `./studio-libraries/${encodeURIComponent(lib.filename)}`;
}
export async function fetchStudioLibrary(lib, fetchImpl = fetch) {
  const paths = [studioLibraryURL(lib), `./public/studio-libraries/${encodeURIComponent(lib.filename)}`];
  for (const path of paths) {
    try {
      const response = await fetchImpl(path);
      if (!response.ok || (response.headers?.get('content-type') || '').includes('text/html')) continue;
      const source = await response.text();
      if (source.length > 1000 && source.includes('return ')) return source;
    } catch { /* fallback: branch Pages source layout */ }
  }
  throw new Error(`${lib.label} source was not published. Check the library import build job.`);
}
export function sourceToStudioFile(lib, code) {
  return { filename: lib.filename, source: code, environment: lib.environment, dependencies: lib.dependencies };
}

// Layouts mirror Roblox ModuleScript hierarchies. A ZIP is source-only;
// creating Instance/ModuleScript objects happens in Roblox Studio, not browser WASM.
export const STUDIO_PACKAGE_EXTRAS = Object.freeze({
  NexusDataStore: [
    { path:'Data.lua', into:'NexusDataStore/PlayersData.lua', sha:'712c47143a3249931fa665de5b497361734d6327' },
    { path:'Compression.lua', into:'Compression.lua', sha:'44ade1b82affd3b3cef186bd09cfc173e0ef2f7b' },
  ],
  Signal: [
    { path:'EventBus.lua', into:'EventBus.lua', sha:'1feeaa37a44d19f6f426c86920d118b1249c9384' },
    { path:'Promise.lua', into:'Promise.lua', sha:'15a73b149f6fc0ecb2c9dfda8b636db016365b0d' },
  ],
  NetStream: [
    { path:'NetworkHandler/EventBus.lua', into:'NetworkHandler/EventBus.lua', sha:'bacc3d9b4e1bd3c34e6c51ff130d64938eb942e4' },
    { path:'NetworkHandler/Modules/BitBuffer.lua', into:'NetworkHandler/Modules/BitBuffer.lua', sha:'9bc4d13034c243252b09f728d8bd921cf9cd7d93' },
    { path:'NetworkHandler/Modules/BufferPool.lua', into:'NetworkHandler/Modules/BufferPool.lua', sha:'a07191da16ac24389f061aaab74de1f569fdf151' },
    { path:'NetworkHandler/Modules/BufferUtil.lua', into:'NetworkHandler/Modules/BufferUtil.lua', sha:'980ac500be902db39e2215ce2d39b4eeba805462' },
    { path:'NetworkHandler/Modules/Promise.lua', into:'NetworkHandler/Modules/Promise.lua', sha:'d786fa3343954b362bede9623e8f23cb0f15a49b' },
    { path:'NetworkHandler/Modules/RoleSystem.lua', into:'NetworkHandler/Modules/RoleSystem.lua', sha:'476d790e846e23d755977d17ef5cf4ad010fbe63' },
    { path:'NetworkHandler/Modules/Signal.lua', into:'NetworkHandler/Modules/Signal.lua', sha:'fd3f091cfab1222100dcae03e700e88637fa55e1' },
  ],
});
export function packageItems(lib) {
  const mainInto = lib.id === 'NexusDataStore' ? 'NexusDataStore/NexusDataStore.lua' : lib.id === 'NetStream' ? 'NetworkHandler/NetStream.lua' : lib.filename;
  return [{ path:lib.file,into:mainInto,sha:lib.blobSha },...(STUDIO_PACKAGE_EXTRAS[lib.id]||[])];
}
export async function fetchStudioPackage(lib, fetchImpl = fetch) {
  const sources = {};
  for(const item of packageItems(lib)) {
    const encoded = item.into.split('/').map(encodeURIComponent).join('/');
    const urls = [`./studio-packages/${lib.id}/${encoded}`, `./public/studio-packages/${lib.id}/${encoded}`];
    let result=null;
    for(const url of urls) {
      try {const response=await fetchImpl(url);if(!response.ok||(response.headers?.get('content-type')||'').includes('text/html'))continue;result=await response.text();if(result.length>10)break;}
      catch { /* try other Pages layout */ }
    }
    if (!result || result.length<10) throw new Error(`Missing package file: ${lib.label}/${item.into}`);
    sources[item.into] = result;
  }
  return sources;
}
