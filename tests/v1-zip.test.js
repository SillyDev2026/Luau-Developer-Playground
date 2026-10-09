import test from 'node:test';
import assert from 'node:assert/strict';
import {makeZip,crc32} from '../src/v1-zip.js';
import { writeFile, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import {join} from 'node:path';
import {execFileSync} from 'node:child_process';
test('CRC32 matches standard zip checksum',()=>assert.equal(crc32(new TextEncoder().encode('123456789')),0xcbf43926));
test('project source ZIP round-trips with actual unzip',async()=>{
 const files={'main.luau':'print("Hello")\n','modules/Café.luau':'return {result=42}\n'};
 const archive=makeZip(files);assert.equal(new DataView(archive.buffer).getUint32(0,true),0x04034b50);
 const dir=await mkdtemp(join(tmpdir(),'luauforge-zip-'));
 try{
   const path=join(dir,'release.zip');await writeFile(path,archive);
   for(const [name,content] of Object.entries(files)) assert.equal(execFileSync('python3',['-c',`import zipfile,sys; sys.stdout.buffer.write(zipfile.ZipFile(sys.argv[1]).read(sys.argv[2]))`,path,name],{encoding:'utf8'}),content);
 } finally{await rm(dir,{recursive:true,force:true});}
});
test('archive rejects traversal',()=>assert.throws(()=>makeZip({'../secret':'x'}),/Invalid archive path/));
