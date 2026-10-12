// Build a real standalone Windows .exe using Node 26's native SEA builder.
// This runs on windows-latest; no ZIP and no Node installation on user devices.
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, writeFileSync, statSync, readFileSync } from 'node:fs';
import { resolve, join } from 'node:path';
const root=resolve(import.meta.dirname,'..');
const out=join(root,'build','server-windows');
mkdirSync(out,{recursive:true});
const exeName='LuauForge-Server-Windows-x64.exe';
const executable=join(out,exeName);
function run(command,args){
  const result=spawnSync(command,args,{cwd:root,stdio:'inherit',shell:false});
  if(result.error)throw result.error;
  if(result.status!==0)throw Error(command+' failed with exit code '+result.status);
}
if(process.platform!=='win32'||process.arch!=='x64')throw Error('Build the Windows x64 server on a Windows x64 runner');
if(Number(process.versions.node.split('.')[0])<26)throw Error('Node.js 26+ is required for --build-sea');
run(process.execPath,[join(root,'node_modules','esbuild','bin','esbuild'),
  'server/windows-entry.mjs','--bundle','--platform=node','--format=cjs','--target=node26',
  '--outfile='+join(out,'server.cjs')]);
const conf=join(out,'sea-config.json');
writeFileSync(conf,JSON.stringify({main:join(out,'server.cjs'),output:executable,disableExperimentalSEAWarning:true},null,2));
run(process.execPath,['--build-sea',conf]);
if(!existsSync(executable)||statSync(executable).size<1_000_000||
   readFileSync(executable).subarray(0,2).toString()!=='MZ')throw Error('Invalid standalone Windows PE executable');
console.log('Built standalone server: '+executable+' ('+statSync(executable).size+' bytes)');
