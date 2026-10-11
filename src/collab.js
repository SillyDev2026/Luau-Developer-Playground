// Shared workspaces are opt-in and separate from the existing local-only editor.
// Tokens are kept in sessionStorage, not in exported projects or permanent settings.
const KEY='luauforge:collab:session:v1';
const TYPES=['Script','LocalScript','ModuleScript'];
const TARGETS=['ReplicatedStorage','ServerScriptService','StarterGui','StarterPlayerScripts'];
const el=(name,properties={})=>Object.assign(document.createElement(name),properties);
const nonempty=value=>typeof value==='string'&&value.trim().length>0;
const cleanApi=value=>{
  const url=new URL(value);
  const local=url.hostname==='127.0.0.1'||url.hostname==='localhost';
  if(url.protocol!=='https:' && !(local&&url.protocol==='http:'))throw Error('Use an HTTPS Node server URL.');
  if(url.username||url.password||url.search||url.hash||url.pathname!=='/')throw Error('Use just the server origin, without a path.');
  return url.origin;
};
async function apiCall(api,token,path,method='GET',data){
  const response=await fetch(api+path,{method,cache:'no-store',signal:AbortSignal.timeout(15000),
    headers:{...(data?{'Content-Type':'application/json'}:{}),...(token?{Authorization:'Bearer '+token}:{})},
    ...(data?{body:JSON.stringify(data)}:{})});
  const payload=await response.json().catch(()=>({}));
  if(!response.ok)throw Object.assign(Error(payload.error||'Server returned '+response.status),{status:response.status});
  return payload;
}
export function mountCollabWorkspace({workspace,editor,notify}){
  const $=id=>document.getElementById(id);
  const section=$('collab-settings');
  if(!section)return null;
  const apiInput=$('collab-api'),nameInput=$('collab-name'),titleInput=$('collab-title'),codeInput=$('collab-code');
  const kind=$('collab-type'),target=$('collab-target'),scriptName=$('collab-script-name');
  const info=$('collab-info'),status=$('collab-status'),members=$('collab-members'),files=$('collab-files');
  const output=$('collab-secret'),outputLabel=$('collab-secret-label');
  const bindings=new Map();
  let connection=null,infoModel=null,timer=null,refreshing=false;
  const setStatus=(message,warning=false)=>{status.textContent=message;status.dataset.warning=String(warning);};
  const hideSecret=()=>{output.value='';output.parentElement.classList.add('hidden');};
  const revealSecret=(label,value)=>{
    outputLabel.textContent=label;
    output.value=value;
    output.parentElement.classList.remove('hidden');
    output.select();
  };
  for(const type of TYPES)kind.append(el('option',{value:type,textContent:type}));
  for(const service of TARGETS)target.append(el('option',{value:service,textContent:service}));
  const restore=()=>{
    try{
      const value=JSON.parse(sessionStorage.getItem(KEY)||'null');
      if(value?.api&&value.workspaceId&&value.token){
        connection={api:cleanApi(value.api),workspaceId:value.workspaceId,token:value.token};
        apiInput.value=connection.api;
      }
    }catch{/* session not stored */}
  };
  const persist=()=>{
    try{
      if(connection)sessionStorage.setItem(KEY,JSON.stringify(connection));
      else sessionStorage.removeItem(KEY);
    }catch{/* browser may disable storage */}
  };
  const call=(path,method='GET',body)=> {
    if(!connection)throw Error('Create or join a shared workspace first.');
    return apiCall(connection.api,connection.token,'/api/workspaces/'+connection.workspaceId+path,method,body);
  };
  async function copySecret(){
    try{await navigator.clipboard.writeText(output.value);setStatus('Copied. Share invitation codes only with teammates; keep Studio tokens private.');}
    catch{output.focus();output.select();setStatus('Select and copy the code manually.');}
  }
  function currentBinding(){return bindings.get(workspace.project.active);}
  function setControls(){
    const active=Boolean(connection),write=active&&infoModel?.role!=='viewer',admin=active&&infoModel?.role==='owner';
    $('collab-create-script').disabled=!write;
    $('collab-save-script').disabled=!write;
    $('collab-invite').disabled=!admin;
    $('collab-studio-token').disabled=!admin;
    $('collab-refresh').disabled=!active;
    $('collab-disconnect').disabled=!active;
  }
  function render(){
    files.replaceChildren();members.replaceChildren();
    if(!infoModel){info.textContent='Not connected to a shared workspace.';setControls();return;}
    info.textContent=infoModel.name+' · '+infoModel.role+' · '+infoModel.scripts.length+' scripts · Studio workspace ID: '+infoModel.id;
    for(const member of infoModel.members){
      members.append(el('span',{className:'collab-chip',textContent:member.name+' ('+member.role+')'}));
    }
    for(const script of infoModel.scripts){
      const row=el('div',{className:'collab-script'});
      const label=el('div',{className:'collab-script-detail'});
      label.append(el('strong',{textContent:script.name}),el('small',{textContent:script.type+' → '+script.target+' · r'+script.version}));
      const button=el('button',{type:'button',textContent:'Edit'});
      button.addEventListener('click',()=>openRemote(script.id).catch(error=>setStatus(error.message,true)));
      row.append(label,button);files.append(row);
    }
    setControls();
  }
  async function refresh(){
    if(!connection||refreshing)return;
    refreshing=true;
    try{
      const response=await call('');
      infoModel=response.workspace;
      render();
      const studio=await call('/studio-status');
      const value=studio.studio;
      $('collab-studio-status').textContent=value.paired?
        'Studio '+(value.lastSeen?'last connected '+new Date(value.lastSeen).toLocaleTimeString():'token created, awaiting plugin')+
        ' · '+value.pending+' pending scripts':'Studio plugin not paired yet.';
    }catch(error){
      setStatus('Cannot refresh shared workspace: '+error.message,true);
      if(error.status===401){connection=null;persist();infoModel=null;render();}
    }finally{refreshing=false;}
  }
  function start(){
    if(timer)clearInterval(timer);
    if(connection){refresh();timer=setInterval(()=>{if(!document.hidden)refresh();},5000);}
    else {infoModel=null;render();}
    setControls();
  }
  async function startWorkspace(){
    const api=cleanApi(apiInput.value);
    const result=await apiCall(api,'','/api/workspaces','POST',{name:titleInput.value,memberName:nameInput.value});
    connection={api,workspaceId:result.workspace.id,token:result.token};
    persist();hideSecret();setStatus('Created shared workspace. Invite a teammate or create a script.');
    start();
  }
  async function joinWorkspace(){
    const api=cleanApi(apiInput.value);
    const result=await apiCall(api,'','/api/join','POST',{code:codeInput.value.trim(),memberName:nameInput.value});
    connection={api,workspaceId:result.workspace.id,token:result.token};
    persist();hideSecret();codeInput.value='';setStatus('Joined shared workspace with '+result.workspace.role+' access.');
    start();
  }
  function localPath(script){
    // Script IDs guarantee no collisions with a different shared script name.
    return 'collab/'+connection.workspaceId+'/'+script.name+'-'+script.id.slice(0,8)+'.luau';
  }
  async function openRemote(scriptId){
    const result=await call('/scripts/'+encodeURIComponent(scriptId));
    const script=result.script,path=localPath(script);
    const previous=bindings.get(path);
    if(previous&&workspace.project.files[path]!==previous.loadedSource){
      throw Error('Local edits are not published yet. Save the current script to the server before reloading.');
    }
    if(!previous&&Object.hasOwn(workspace.project.files,path)&&workspace.project.files[path]!==script.source){
      throw Error('Existing local copy differs from the server. Rename or export the local file before reloading to avoid losing work.');
    }
    if(Object.hasOwn(workspace.project.files,path)){
      workspace.update(project=>({...project,files:{...project.files,[path]:script.source},active:path}));
    }else{
      workspace.create(path,script.source);
    }
    bindings.set(path,{id:script.id,version:script.version,loadedSource:script.source});
    editor.input.focus();
    setStatus('Opened '+script.name+' · revision '+script.version+'. Save to publish changes to collaborators and Studio.');
  }
  async function createScript(){
    const result=await call('/scripts','POST',{name:scriptName.value.trim(),type:kind.value,target:target.value});
    await refresh();
    await openRemote(result.script.id);
    setStatus(result.script.type+' '+result.script.name+' created for '+result.script.target+'.');
  }
  async function publishScript(){
    const entry=currentBinding();
    if(!entry)throw Error('Open a shared script from this panel before publishing.');
    const value=workspace.project.files[workspace.project.active];
    const result=await call('/scripts/'+entry.id,'PATCH',{version:entry.version,source:value});
    entry.version=result.script.version;entry.loadedSource=value;
    await refresh();
    setStatus('Published revision '+entry.version+' of '+result.script.name+'. Studio will receive it while connected.');
  }
  async function invite(){
    const result=await call('/invites','POST',{role:$('collab-invite-role').value});
    revealSecret('One-use '+result.role+' invite code (expires in 24 hours)',result.code);
    setStatus('Invitation created. Share this code privately.');
  }
  async function linkStudio(){
    const result=await call('/studio-token','POST',{});
    revealSecret('Studio pairing token · paste into the Roblox Studio plugin',result.token);
    setStatus('Studio token created. Generating a new token disconnects any old plugin session.');
    await refresh();
  }
  async function safeAction(fn){
    try{await fn();}catch(error){setStatus(error.message,true);notify(error.message,true);}
  }
  $('collab-create').addEventListener('click',()=>safeAction(startWorkspace));
  $('collab-join').addEventListener('click',()=>safeAction(joinWorkspace));
  $('collab-refresh').addEventListener('click',()=>safeAction(refresh));
  $('collab-create-script').addEventListener('click',()=>safeAction(createScript));
  $('collab-save-script').addEventListener('click',()=>safeAction(publishScript));
  $('collab-invite').addEventListener('click',()=>safeAction(invite));
  $('collab-studio-token').addEventListener('click',()=>safeAction(linkStudio));
  $('collab-copy-secret').addEventListener('click',()=>safeAction(copySecret));
  $('collab-disconnect').addEventListener('click',()=>{
    connection=null;infoModel=null;persist();hideSecret();
    if(timer)clearInterval(timer);timer=null;
    setStatus('Disconnected. Your local editor files remain on this device.');
    start();
  });
  restore();start();
  return {refresh,get connection(){return connection?{workspaceId:connection.workspaceId,api:connection.api}:null;}};
}
