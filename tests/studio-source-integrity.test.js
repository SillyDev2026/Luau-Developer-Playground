import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {STUDIO_LIBRARIES,packageItems,fetchStudioPackage} from '../src/studio-libraries.js';
import {makeZip} from '../src/v1-zip.js';
import {readZip} from '../src/v15-zip.js';
const root=new URL('../',import.meta.url);
const sha=bytes=>createHash('sha1').update(`blob ${bytes.length}\0`).update(bytes).digest('hex');

test('imported Studio library originals match pinned Git blob hashes',async()=>{
  for(const lib of STUDIO_LIBRARIES){
    const bytes=await readFile(new URL(`public/studio-libraries/${lib.filename}`,root));
    assert.equal(sha(bytes),lib.blobSha,`Unexpected source change: ${lib.id}`);
  }
});
test('all Studio package files are present with original upstream hashes',async()=>{
  let n=0;
  for(const lib of STUDIO_LIBRARIES)for(const item of packageItems(lib)){
    const bytes=await readFile(new URL(`public/studio-packages/${lib.id}/${item.into}`,root));
    assert.equal(sha(bytes),item.sha,`Invalid Studio package: ${lib.id}/${item.into}`);n++;
  }
  assert.equal(n,18);
});
test('Studio package ZIPs preserve source structure and import safely',async()=>{
  for(const id of ['NexusDataStore','Signal','NetStream']){
    const lib=STUDIO_LIBRARIES.find(x=>x.id===id);
    const sources=await fetchStudioPackage(lib,async url=>{
      const filename=url.replace(/^\.\/(public\/)?/,'');
      try{
        const value=await readFile(new URL('public/'+filename,root),'utf8');
        return {ok:true,headers:{get:()=> 'text/plain'},text:async()=>value};
      }catch{return {ok:false,status:404};}
    });
    const zip=makeZip(sources);
    const roundTrip=await readZip(zip);
    assert.equal(Object.keys(roundTrip).length,Object.keys(sources).length);
    assert.ok(zip.length>300);
  }
});
