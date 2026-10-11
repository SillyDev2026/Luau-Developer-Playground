import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { createCollabServer } from '../server/collab.mjs';
import { sharedScriptPath } from '../src/collab.js';

test('failed Studio updates back off and new script revisions are immediately eligible',async t=>{
  let now=1_700_000_000_000;
  const dir=mkdtempSync(join(tmpdir(),'luauforge-retry-')),dataFile=join(dir,'db.json');
  t.after(()=>rmSync(dir,{recursive:true,force:true}));
  const app=createCollabServer({dataFile,clock:()=>now,allowedOrigins:['http://localhost:4173']});
  await new Promise(resolve=>app.server.listen(0,'127.0.0.1',resolve));
  t.after(()=>app.close());
  const url='http://127.0.0.1:'+app.server.address().port;
  async function call(path,method='GET',body,token){
    const result=await fetch(url+path,{method,headers:{...(token?{Authorization:'Bearer '+token}:{}),...(body?{'Content-Type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{})});
    return {status:result.status,data:await result.json()};
  }
  const created=await call('/api/workspaces','POST',{name:'Safety Test',memberName:'Owner'});
  const id=created.data.workspace.id,owner=created.data.token,base='/api/workspaces/'+id;
  const script=(await call(base+'/scripts','POST',{name:'Run',type:'Script',target:'ServerScriptService',source:'print(1)'},owner)).data.script;
  const pairing=(await call(base+'/studio-token','POST',{},owner)).data.token,studio='/api/studio/'+id;
  assert.equal((await call(studio+'/changes','GET',undefined,pairing)).data.changes.length,1);
  assert.equal((await call(studio+'/ack','POST',{scriptId:script.id,version:1,success:false,error:'Studio source changed'},pairing)).status,200);
  assert.equal((await call(studio+'/changes','GET',undefined,pairing)).data.changes.length,0);
  let status=(await call(base+'/studio-status','GET',undefined,owner)).data.studio;
  assert.equal(status.pending,1);
  assert.equal(status.applied,0);
  assert.equal(status.failures.length,1);
  assert.equal(status.failures[0].error,'Studio source changed');
  now+=14999;
  assert.equal((await call(studio+'/changes','GET',undefined,pairing)).data.changes.length,0);
  now+=1;
  assert.equal((await call(studio+'/changes','GET',undefined,pairing)).data.changes.length,1);
  await call(studio+'/ack','POST',{scriptId:script.id,version:1,success:false,error:'still changed'},pairing);
  now+=15000;
  assert.equal((await call(studio+'/changes','GET',undefined,pairing)).data.changes.length,0);
  now+=15000;
  assert.equal((await call(studio+'/changes','GET',undefined,pairing)).data.changes.length,1);
  assert.equal((await call(base+'/scripts/'+script.id,'PATCH',{version:1,source:'print(2)'},owner)).status,200);
  assert.equal((await call(studio+'/changes','GET',undefined,pairing)).data.changes[0].version,2);
  assert.equal((await call(studio+'/ack','POST',{scriptId:script.id,version:2,success:true},pairing)).status,200);
  status=(await call(base+'/studio-status','GET',undefined,owner)).data.studio;
  assert.equal(status.pending,0);
  assert.equal(status.applied,1);
  assert.deepEqual(status.failures,[]);
});

test('workspace owner can revoke editor/viewer sessions and members can leave',async t=>{
  const dir=mkdtempSync(join(tmpdir(),'luauforge-members-'));
  t.after(()=>rmSync(dir,{recursive:true,force:true}));
  const app=createCollabServer({dataFile:join(dir,'db.json')});
  await new Promise(resolve=>app.server.listen(0,'127.0.0.1',resolve));
  t.after(()=>app.close());
  const url='http://127.0.0.1:'+app.server.address().port;
  async function call(path,method='GET',body,token){
    const response=await fetch(url+path,{method,headers:{...(token?{Authorization:'Bearer '+token}:{}),...(body?{'Content-Type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{})});
    return {status:response.status,data:await response.json()};
  }
  const ownerCreate=await call('/api/workspaces','POST',{name:'Team',memberName:'Owner'});
  const workspaceId=ownerCreate.data.workspace.id,owner=ownerCreate.data.token,api='/api/workspaces/'+workspaceId;
  assert.equal((await call(api+'/leave','POST',{},owner)).status,403);
  const invite=(await call(api+'/invites','POST',{role:'editor'},owner)).data;
  const member=await call('/api/join','POST',{code:invite.code,memberName:'Dev'});
  const memberId=member.data.workspace.memberId,editor=member.data.token;
  assert.equal((await call(api+'/members/'+memberId,'DELETE',undefined,editor)).status,403);
  assert.equal((await call(api+'/members/'+ownerCreate.data.workspace.memberId,'DELETE',undefined,owner)).status,403);
  assert.equal((await call(api+'/members/'+memberId,'DELETE',undefined,owner)).status,200);
  assert.equal((await call(api,'GET',undefined,editor)).status,401);
  assert.equal((await call(api+'/members/'+memberId,'DELETE',undefined,owner)).status,404);
  const viewerCode=(await call(api+'/invites','POST',{role:'viewer'},owner)).data.code;
  const viewer=(await call('/api/join','POST',{code:viewerCode,memberName:'Observer'})).data.token;
  assert.equal((await call(api+'/leave','POST',{},viewer)).status,200);
  assert.equal((await call(api,'GET',undefined,viewer)).status,401);
  const memberList=(await call(api,'GET',undefined,owner)).data.workspace.members;
  assert.deepEqual(memberList.map(x=>x.role),['owner']);
});

test('script editor file mappings use stable IDs and preserve legacy local copies',()=>{
  const id='11111111-2222-3333-4444-555555555555';
  const script={id,name:'Server Handler'};
  const stable=sharedScriptPath('workspace-id',script);
  assert.equal(stable,'collab/workspace-id/'+id+'.luau');
  const renamed=sharedScriptPath('workspace-id',{...script,name:'Changed'});
  assert.equal(renamed,stable);
  const legacy='collab/workspace-id/Server Handler-'+id.slice(0,8)+'.luau';
  assert.equal(sharedScriptPath('workspace-id',script,{[legacy]:'local copy'}),legacy);
  assert.equal(sharedScriptPath('other-workspace',script), 'collab/other-workspace/'+id+'.luau');
});

test('full script page has accessible navigation, search/filter and non-destructive revision UX',async()=>{
  const {readFile}=await import('node:fs/promises');
  const html=await readFile(new URL('../index.html',import.meta.url),'utf8');
  const css=await readFile(new URL('../src/collab.css',import.meta.url),'utf8');
  const js=await readFile(new URL('../src/collab.js',import.meta.url),'utf8');
  const plugin=await readFile(new URL('../studio/LuauForgeBridge.plugin.lua',import.meta.url),'utf8');
  for(const id of ['collab-view','collab-page-btn','collab-back-editor','mobile-collab','collab-search',
    'collab-filter-type','collab-filter-target','collab-script-details','collab-edit-name','collab-edit-type',
    'collab-edit-target','collab-update-script','collab-preview','collab-list-summary','collab-stats','collab-leave']){
    assert.ok(html.includes('id="'+id+'"'),id);
  }
  assert.match(css,/\.main-surface\.collab-page-active/);
  assert.match(css,/#collab-settings \.collab-files/);
  assert.match(js,/loadedSource/);
  assert.match(js,/Another member saved a newer revision|error\.status===409/);
  assert.match(js,/sharedScriptPath\(/);
  assert.match(js,/workspace\.project\.files\[path\]!==script\.source/);
  assert.match(plugin,/sourceHash\(existing\.Source\)/);
  assert.match(plugin,/sourceHash\(oldSource\)/);
  assert.match(plugin,/if created then existing:Destroy\(\) end/);
  assert.doesNotMatch(plugin,/loadstring\s*\(/);
});
