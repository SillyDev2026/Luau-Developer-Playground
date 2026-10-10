// Reproducible Studio-only library import. All upstream revisions and Git blob
// hashes are pinned; CI fails rather than silently packaging different code.
import { STUDIO_LIBRARIES, packageItems } from '../src/studio-libraries.js';
import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
const expected = {
  NexusDataStore: 'f3dd469b5605c4ca8a04255c43fe0e02814ee3e1',
  ZonePlusV2: 'b5543e5f47c250279400ae4bd91e8d5d6b2b7f7a',
  BufferUtil: '109bf5e88fe35d741f0b6b4dc1f87439860a13b3',
  Compression: 'ec6a1e11667e62273b1393ed880ff7514deefa37',
  Signal: '6456434563f7b1783bf0f8b0f09e40c784938b4f',
  Promise: 'f41d8e8f5b6c6e6d82e7c244130baeb41905c8b3',
  NetStream: '82e98f6b1860b6751eb14db812b4b6c65d7f2d01',
};
const dir = new URL('../public/studio-libraries/', import.meta.url);
await mkdir(dir, { recursive: true });
for(const lib of STUDIO_LIBRARIES) {
  const path = new URL(lib.filename, dir);
  let bytes = await readFile(path).catch(() => null);
  const sha = data => createHash('sha1').update(`blob ${data.length}\0`).update(data).digest('hex');
  if (!bytes || sha(bytes) !== expected[lib.id]) {
    const url = `https://raw.githubusercontent.com/SillyDev2026/${lib.repo}/${lib.commit}/${lib.file}`;
    const response = await fetch(url, { signal: AbortSignal.timeout(120000) });
    if (!response.ok) throw new Error(`${lib.id} source fetch failed: HTTP ${response.status}`);
    bytes = Buffer.from(await response.arrayBuffer());
    if (sha(bytes) !== expected[lib.id]) throw new Error(`${lib.id}: unexpected upstream source hash; refusing unreviewed code`);
    await writeFile(path, bytes);
  }
  console.log(`${lib.label}: ${bytes.length} bytes (SHA-1 ${expected[lib.id]}) · Roblox Studio only`);
  for (const item of packageItems(lib)) {
    const destination = new URL(`../public/studio-packages/${lib.id}/${item.into}`, import.meta.url);
    await mkdir(new URL('.',destination), {recursive:true});
    let payload = await readFile(destination).catch(()=>null);
    if (!payload || sha(payload) !== item.sha) {
      const fileUrl = `https://raw.githubusercontent.com/SillyDev2026/${lib.repo}/${lib.commit}/${item.path}`;
      const response = await fetch(fileUrl,{signal:AbortSignal.timeout(120000)});
      if(!response.ok) throw new Error(`Missing ${lib.id} package dependency ${item.path}: HTTP ${response.status}`);
      payload = Buffer.from(await response.arrayBuffer());
      if(sha(payload)!==item.sha)throw new Error(`${lib.id} dependency SHA mismatch: ${item.path}`);
      await writeFile(destination,payload);
    }
  }
}
