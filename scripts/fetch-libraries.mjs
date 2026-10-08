// Explicit maintenance command: refresh the THREE pinned library sources.
// This is not called on website load. Updating versions requires reviewing API
// compatibility, smoke tests and scripts/library-versions.json.
import {readFile, mkdir, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
const versions = JSON.parse(await readFile(new URL('./library-versions.json',import.meta.url),'utf8'));
const destination = new URL('../public/libraries/',import.meta.url);
await mkdir(destination,{recursive:true});
for(const [id,metadata] of Object.entries(versions)) {
  const url = `https://raw.githubusercontent.com/${metadata.repository}/${metadata.commit}/${metadata.path}`;
  const response = await fetch(url,{signal:AbortSignal.timeout(90000)});
  if(!response.ok) throw Error(`${id} fetch failed (${response.status})`);
  const source = await response.text();
  if(source.length<5000||!source.includes('return ')) throw Error(`${id} source appears truncated`);
  const output = new URL(`${metadata.path}`,destination);
  await writeFile(output,source);
  console.log(`${id} v${metadata.version}: fetched ${source.length} chars`);
}
