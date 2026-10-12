// Compact source-only API index for explicitly reviewed public modules.
// Store signatures and documentation, NOT the downloaded/executable source.
import { maskLuau } from './intellisense.js?v=0.4.0';

export function validateModuleIndex(value){
  if(!Array.isArray(value))return [];
  return value.slice(0,60).filter(x=>x&&typeof x.name==='string'&&/^[A-Za-z_]\w*$/.test(x.name)&&
    typeof x.signature==='string'&&x.signature.length<=300&&x.signature.startsWith(x.name+'(')&&
    typeof x.documentation==='string'&&x.documentation.length<=180)
    .map(x=>({name:x.name,signature:x.signature,documentation:x.documentation}));
}
function closingParen(masked,open){
  let depth=0;
  for(let i=open;i<masked.length;i++){
    if(masked[i]==='(')depth++;
    else if(masked[i]===')'&&--depth===0)return i;
  }
  return -1;
}
function commentBefore(source,index){
  const lineStart=source.lastIndexOf('\n',Math.max(index-1,0))+1;
  if(source.slice(lineStart,index).trim())return '';
  const preceding=source.slice(0,lineStart).replace(/\r?\n$/,'');
  const notes=[];
  for(const line of preceding.split(/\r?\n/).reverse()){
    if(!/^\s*--(?!\[)/.test(line))break;
    const note=line.replace(/^\s*---?[ \t]?/,'').trim();
    if(note.startsWith('!'))break;
    notes.unshift(note);
  }
  return notes.join('\n').slice(0,180);
}
export function indexPublicModule(source){
  if(typeof source!=='string'||source.length>200000)return [];
  const masked=maskLuau(source),returned=masked.match(/\breturn\s+([A-Za-z_]\w*)\s*;?\s*$/)?.[1]||'';
  if(!returned)return [];
  const pattern=/\b(?:function\s+([A-Za-z_]\w*)[.:]([A-Za-z_]\w*)\s*\(|([A-Za-z_]\w*)[.]([A-Za-z_]\w*)\s*=\s*function\s*\()/g;
  const seen=new Set(),api=[];
  for(const match of masked.matchAll(pattern)){
    const table=match[1]||match[3],name=match[2]||match[4];
    if(table!==returned||seen.has(name))continue;
    const open=match.index+match[0].lastIndexOf('('),close=closingParen(masked,open);
    if(close<0)continue;
    const after=source.slice(close+1).split('\n')[0];
    const type=after.match(/^\s*:\s*([^\n;]+?)(?=\s*(?:--|$))/)?.[1]?.trim()||'';
    const signature=name+'('+source.slice(open+1,close)+')'+(type?': '+type:'');
    if(signature.length>300)continue;
    api.push({name,signature,documentation:commentBefore(source,match.index)});
    seen.add(name);
    if(api.length>=60)break;
  }
  return validateModuleIndex(api);
}
