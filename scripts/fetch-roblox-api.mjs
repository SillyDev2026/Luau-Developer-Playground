// Produce a compact, self-hosted autocomplete index from the Studio API dump.
// The full dump is reference metadata only; it does NOT add Roblox services
// to the browser-based Luau virtual machine.
import { writeFile } from 'node:fs/promises';
import { join } from 'node:path';

const URL = 'https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/API-Dump.json';
function typeName(type) { if(!type)return 'any';return type.Name || type.name || 'any'; }
function accessible(member){
  if(member.Tags?.includes('Hidden')||member.Tags?.includes('NotBrowsable')||member.Tags?.includes('Deprecated'))return false;
  const security=member.Security;
  if(typeof security==='string')return security==='None';
  if(security&&typeof security==='object')return security.Read==='None'||security.Write==='None';
  return true;
}
export function compactRobloxAPI(dump) {
  const classes={},enums={},types=[];
  for(const cls of dump.Classes||[]){
    if(!cls.Name)continue;
    types.push(cls.Name);
    const members=[];
    for(const m of cls.Members||[]){
      if(!accessible(m))continue;
      let kind='',detail='',result='';
      if(m.MemberType==='Function'||m.MemberType==='Callback'){
        kind='function';result=typeName(m.ReturnType);
        const params=(m.Parameters||[]).map(p=>`${p.Name||'arg'}: ${typeName(p.Type)}`).join(', ');
        detail=`${m.Name}(${params}): ${result}`;
      }else if(m.MemberType==='Property'){
        kind='property';result=typeName(m.ValueType);detail=`${m.Name}: ${result}`;
      }else if(m.MemberType==='Event'){
        kind='event';result='RBXScriptSignal';detail=`${m.Name}(${(m.Parameters||[]).map(p=>`${p.Name}: ${typeName(p.Type)}`).join(', ')})`;
      }
      if(kind&&m.Name)members.push([m.Name,kind,detail,result]);
    }
    classes[cls.Name]={parent:cls.Superclass,members};
  }
  for(const en of dump.Enums||[]){if(en.Name)enums[en.Name]=(en.Items||[]).map(item=>item.Name);}
  return {source:URL,version:dump.Version,classes,enums,types};
}
if(process.argv[1]?.endsWith('fetch-roblox-api.mjs')){
  const response=await fetch(URL,{signal:AbortSignal.timeout(120000)});
  if(!response.ok)throw new Error(`Failed to fetch Studio API dump: HTTP ${response.status}`);
  const metadata=compactRobloxAPI(await response.json());
  if(metadata.types.length<300||Object.keys(metadata.enums).length<100)throw new Error('Incomplete Roblox API dump; refused to publish incomplete autocomplete metadata');
  const output=join(import.meta.dirname,'../public/roblox-api.json');
  await writeFile(output,JSON.stringify(metadata));
  console.log(`Roblox API: ${metadata.types.length} engine classes, ${Object.keys(metadata.enums).length} enums; written ${output}`);
}
