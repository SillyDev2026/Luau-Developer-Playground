// Opt-in shared workspaces. Local-only projects stay in the browser.
// Shared session tokens remain in sessionStorage and never enter exported projects.
const KEY='luauforge:collab:session:v1';
const TYPES=['Script','LocalScript','ModuleScript'];
const TARGETS=['ReplicatedStorage','ServerScriptService','StarterGui','StarterPlayerScripts'];
const el=(name,properties={})=>Object.assign(document.createElement(name),properties);
const cleanApi=value=>{
  const url=new URL(value.trim());
  const local=url.hostname==='127.0.0.1'||url.hostname==='localhost';
  if(url.protocol!=='https:'&&!(local&&url.protocol==='http:'))throw Error('Use a trusted HTTPS Node server (HTTP localhost only).');
  if(url.username||url.password||url.search||url.hash||url.pathname!=='/')throw Error('Enter only the API origin, without a path or credentials.');
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
export function sharedScriptPath(workspaceId,script,files={}){
  const prefix='collab/'+workspaceId+'/';
  const legacy=prefix+script.name+'-'+script.id.slice(0,8)+'.luau';
  return Object.hasOwn(files,legacy)?legacy:prefix+script.id+'.luau';
}

export function mountCollabWorkspace({workspace,editor,notify,onOpenPage=()=>{}}){
  const $=id=>document.getElementById(id),section=$('collab-settings');
  if(!section)return null;
  const host=$('collab-page-body'),page=$('collab-view'),surface=$('main-surface');
  const teaser=el('div',{className:'setting-group collab-shortcut'});
  const openButton=el('button',{type:'button',className:'wide-btn',textContent:'◇ Open Shared Scripts'});
  teaser.append(el('div',{className:'setting-title',textContent:'TEAM SCRIPTS'}),openButton,
    el('p',{className:'inspector-note',textContent:'Manage collaborators, publish scripts and pair Studio on the full-width Scripts page.'}));
  section.parentElement.insertBefore(teaser,section);
  host.append(section);
  const apiInput=$('collab-api'),nameInput=$('collab-name'),titleInput=$('collab-title'),codeInput=$('collab-code');
  const kind=$('collab-type'),target=$('collab-target'),scriptName=$('collab-script-name');
  const info=$('collab-info'),status=$('collab-status'),members=$('collab-members'),files=$('collab-files');
  const output=$('collab-secret'),outputLabel=$('collab-secret-label'),details=$('collab-script-details');
  const search=$('collab-search'),filterType=$('collab-filter-type'),filterTarget=$('collab-filter-target');
  const bindings=new Map();
  let connection=null,infoModel=null,timer=null,pendingRefresh=null,selectedId=null,selectedRemote=null,visible=false;
  const setStatus=(message,warning=false)=>{status.textContent=message;status.dataset.warning=String(warning);};
  const hideSecret=()=>{output.value='';output.parentElement.classList.add('hidden');};
  const revealSecret=(label,value)=>{outputLabel.textContent=label;output.value=value;output.parentElement.classList.remove('hidden');};
  for(const type of TYPES)kind.append(el('option',{value:type,textContent:type}));
  for(const service of TARGETS)target.append(el('option',{value:service,textContent:service}));
  function openPage(){
    onOpenPage();
    visible=true;page.classList.remove('hidden');surface.classList.add('collab-page-active');
    render();
    $('collab-back-editor').focus();
  }
  function closePage(){
    visible=false;page.classList.add('hidden');surface.classList.remove('collab-page-active');
  }
  function restored(){
    try{
      const value=JSON.parse(sessionStorage.getItem(KEY)||'null');
      if(value?.api&&value.workspaceId&&value.token){
        connection={api:cleanApi(value.api),workspaceId:value.workspaceId,token:value.token};
        apiInput.value=connection.api;
      }
    }catch{/* Browser session unavailable. */}
  }
  function persist(){
    try{
      if(connection)sessionStorage.setItem(KEY,JSON.stringify(connection));
      else sessionStorage.removeItem(KEY);
    }catch{/* Browser may deny session storage. */}
  }
  function call(path,method='GET',body,session=connection){
    if(!session)throw Error('Create or join a shared workspace first.');
    return apiCall(session.api,session.token,'/api/workspaces/'+session.workspaceId+path,method,body);
  }
  async function copySecret(){
    try{await navigator.clipboard.writeText(output.value);setStatus('Copied. Keep Studio pairing tokens private.');}
    catch{output.focus();output.select();setStatus('Select the code and copy it manually.');}
  }
  function localPath(script,session=connection){
    return sharedScriptPath(session.workspaceId,script,workspace.project.files);
  }
  function currentBinding(){
    const entry=bindings.get(workspace.project.active);
    return entry?.workspaceId===connection?.workspaceId?entry:null;
  }
  function isDirty(path){
    const entry=bindings.get(path);
    return Boolean(entry&&entry.workspaceId===connection?.workspaceId&&workspace.project.files[path]!==entry.loadedSource);
  }
  function setControls(){
    const active=Boolean(connection),write=active&&Boolean(infoModel)&&infoModel.role!=='viewer',admin=active&&infoModel?.role==='owner';
    $('collab-create-script').disabled=!write;
    $('collab-save-script').disabled=!write||!currentBinding()||!isDirty(workspace.project.active);
    $('collab-update-script').disabled=!write||!selectedRemote;
    $('collab-open-editor').disabled=!selectedRemote;
    $('collab-invite').disabled=!admin;
    $('collab-studio-token').disabled=!admin;
    $('collab-refresh').disabled=!active;
    $('collab-disconnect').disabled=!active;
    $('collab-leave').disabled=!active||!infoModel||infoModel.role==='owner';
  }
  function renderDetail(){
    if(!selectedRemote||!infoModel?.scripts.some(script=>script.id===selectedRemote.id)){
      details.classList.add('hidden');setControls();return;
    }
    details.classList.remove('hidden');
    $('collab-selected-title').textContent=selectedRemote.name+' · revision '+selectedRemote.version+' · '+selectedRemote.updatedBy;
    $('collab-edit-name').value=selectedRemote.name;
    $('collab-edit-type').value=selectedRemote.type;
    $('collab-edit-target').value=selectedRemote.target;
    $('collab-preview').textContent=selectedRemote.source;
    setControls();
  }
  function render(){
    files.replaceChildren();members.replaceChildren();
    if(!infoModel){
      info.textContent='Not connected. Enter your server origin and create or join a workspace.';
      $('collab-stats').replaceChildren(el('span',{textContent:'0 scripts'}),el('span',{textContent:'0 members'}),el('span',{textContent:'Studio offline'}));
      $('collab-list-summary').textContent='No shared scripts loaded';
      renderDetail();return;
    }
    info.textContent=infoModel.name+' · '+infoModel.role+' · Studio workspace ID: '+infoModel.id;
    for(const member of infoModel.members){
      const chip=el('span',{className:'collab-chip'});
      chip.append(el('span',{textContent:member.name+' · '+member.role}));
      if(infoModel.role==='owner'&&member.role!=='owner'){
        const remove=el('button',{type:'button',textContent:'×',title:'Remove '+member.name,ariaLabel:'Remove '+member.name});
        remove.addEventListener('click',()=>safeAction(async()=>{
          if(!window.confirm('Remove '+member.name+' from this workspace? Their token will stop working.'))return;
          await call('/members/'+member.id,'DELETE');await refresh();setStatus('Member removed.');
        }));
        chip.append(remove);
      }
      members.append(chip);
    }
    const studio=infoModel.studio;
    $('collab-stats').replaceChildren(
      el('span',{textContent:infoModel.scripts.length+' scripts'}),
      el('span',{textContent:infoModel.members.length+' members'}),
      el('span',{textContent:studio.paired?'Studio paired':'Studio unpaired'}));
    const q=search.value.trim().toLowerCase();
    const listed=infoModel.scripts.filter(item=>
      (!q||[item.name,item.updatedBy,item.type,item.target].some(x=>x.toLowerCase().includes(q)))&&
      (!filterType.value||item.type===filterType.value)&&(!filterTarget.value||item.target===filterTarget.value))
      .sort((a,b)=>b.updatedAt-a.updatedAt||a.name.localeCompare(b.name));
    $('collab-list-summary').textContent=listed.length+' of '+infoModel.scripts.length+' scripts · Select Open to edit using Luau IntelliSense';
    if(!listed.length)files.append(el('p',{className:'inspector-note',textContent:'No scripts match these filters. Create one above or change the search.'}));
    for(const script of listed){
      const row=el('article',{className:'collab-script'});
      if(script.id===selectedId)row.classList.add('selected');
      const label=el('div',{className:'collab-script-detail'});
      const opened=[...bindings.entries()].find(([,entry])=>entry.workspaceId===connection?.workspaceId&&entry.id===script.id);
      const dirty=opened&&isDirty(opened[0]);
      const badge=el('span',{className:'collab-script-badge',textContent:dirty?'Unsaved':opened?'In editor':'Shared'});
      if(dirty)badge.classList.add('collab-unsaved');
      label.append(el('strong',{textContent:script.name}),el('small',{textContent:script.type+' · '+script.target}),el('small',{textContent:'Revision '+script.version+' · '+script.updatedBy}),badge);
      const buttons=el('div',{className:'collab-script-actions'});
      const inspect=el('button',{type:'button',textContent:'Details'});
      inspect.addEventListener('click',()=>safeAction(()=>selectScript(script.id)));
      const open=el('button',{type:'button',textContent:'Open code'});
      open.addEventListener('click',()=>safeAction(()=>openRemote(script.id)));
      buttons.append(inspect,open);row.append(label,buttons);files.append(row);
    }
    setControls();
  }
  async function refresh(){
    const session=connection;
    if(!session||pendingRefresh===session)return;
    pendingRefresh=session;
    try{
      const response=await call('', 'GET', undefined,session);
      if(connection!==session)return;
      infoModel=response.workspace;render();
      const studio=await call('/studio-status','GET',undefined,session);
      if(connection!==session)return;
      const value=studio.studio,failures=value.failures||[];
      const summary=value.paired?'Studio '+(value.lastSeen?'last connected '+new Date(value.lastSeen).toLocaleTimeString():'paired, awaiting plugin')+
        ' · '+value.pending+' pending'+(failures.length?' · '+failures.length+' failed':''):'Studio plugin not paired yet.';
      $('collab-studio-status').textContent=summary+(failures.length?' · '+failures.slice(0,2).map(x=>x.name+': '+x.error).join('; '):'');
    }catch(error){
      if(connection!==session)return;
      setStatus('Cannot refresh: '+error.message,true);
      if(error.status===401){connection=null;persist();infoModel=null;hideSecret();render();}
    }finally{if(pendingRefresh===session)pendingRefresh=null;}
  }
  function start(){
    if(timer)clearInterval(timer);
    timer=null;
    if(connection){refresh();timer=setInterval(()=>{if(!document.hidden)refresh();},5000);}
    else{infoModel=null;selectedId=null;selectedRemote=null;render();}
    setControls();
  }
  async function createWorkspace(){
    const api=cleanApi(apiInput.value);
    const result=await apiCall(api,'','/api/workspaces','POST',{name:titleInput.value,memberName:nameInput.value});
    connection={api,workspaceId:result.workspace.id,token:result.token};
    infoModel=result.workspace;selectedRemote=null;selectedId=null;persist();hideSecret();
    setStatus('Workspace created. Invite a teammate or create your first script.');
    start();
  }
  async function joinWorkspace(){
    const api=cleanApi(apiInput.value);
    const result=await apiCall(api,'','/api/join','POST',{code:codeInput.value.trim(),memberName:nameInput.value});
    connection={api,workspaceId:result.workspace.id,token:result.token};
    infoModel=result.workspace;selectedRemote=null;selectedId=null;persist();hideSecret();codeInput.value='';
    setStatus('Joined as '+result.workspace.role+'.');start();
  }
  async function selectScript(scriptId){
    const session=connection;
    const result=await call('/scripts/'+encodeURIComponent(scriptId),'GET',undefined,session);
    if(connection!==session)throw Error('Workspace changed while loading script.');
    selectedId=scriptId;selectedRemote=result.script;render();renderDetail();
  }
  async function openRemote(scriptId){
    const session=connection;
    const response=await call('/scripts/'+encodeURIComponent(scriptId),'GET',undefined,session);
    if(connection!==session)throw Error('Workspace changed while loading script.');
    const script=response.script,path=localPath(script,session),previous=bindings.get(path);
    if(previous&&workspace.project.files[path]!==previous.loadedSource){
      throw Error('You have unpublished local changes. Publish them before reloading this script.');
    }
    if(!previous&&Object.hasOwn(workspace.project.files,path)&&workspace.project.files[path]!==script.source){
      throw Error('The saved local copy differs from the server. Export or rename your local file before replacing it.');
    }
    if(Object.hasOwn(workspace.project.files,path)){
      workspace.update(project=>({...project,files:{...project.files,[path]:script.source},active:path}));
    }else{
      workspace.create(path,script.source);
    }
    bindings.set(path,{id:script.id,workspaceId:session.workspaceId,version:script.version,loadedSource:script.source});
    selectedId=script.id;selectedRemote=script;renderDetail();render();closePage();editor.input.focus();
    setStatus('Opened '+script.name+' r'+script.version+' in the Luau editor. Use Publish to share changes.');
  }
  async function createScript(){
    const session=connection;
    const response=await call('/scripts','POST',{name:scriptName.value.trim(),type:kind.value,target:target.value},session);
    if(connection!==session)throw Error('Workspace changed after the script was created.');
    if(infoModel)infoModel.scripts.push(response.script);
    await refresh();
    await openRemote(response.script.id);
    setStatus(response.script.type+' '+response.script.name+' created in '+response.script.target+'.');
  }
  async function publishScript(){
    const entry=currentBinding();
    if(!entry)throw Error('Open a script from the shared script list first.');
    const path=workspace.project.active,source=workspace.project.files[path];
    if(typeof source!=='string')throw Error('Active script is missing.');
    if(source===entry.loadedSource)throw Error('No unpublished changes.');
    const session=connection;
    const response=await call('/scripts/'+entry.id,'PATCH',{version:entry.version,source},session);
    if(connection!==session)throw Error('Workspace changed after publishing.');
    entry.version=response.script.version;entry.loadedSource=source;
    if(selectedId===entry.id)selectedRemote=response.script;
    await refresh();renderDetail();
    setStatus('Published '+response.script.name+' revision '+entry.version+'. Studio will receive it when connected.');
  }
  async function saveProperties(){
    if(!selectedRemote)throw Error('Select a script first.');
    const session=connection,id=selectedRemote.id;
    const result=await call('/scripts/'+id,'PATCH',{
      version:selectedRemote.version,name:$('collab-edit-name').value.trim(),
      type:$('collab-edit-type').value,target:$('collab-edit-target').value
    },session);
    if(connection!==session)throw Error('Workspace changed while saving.');
    selectedRemote=result.script;
    for(const entry of bindings.values())if(entry.id===id&&entry.workspaceId===session.workspaceId)entry.version=result.script.version;
    await refresh();renderDetail();
    setStatus('Properties saved. Studio will apply the new name/location when connected.');
  }
  async function invite(){
    const result=await call('/invites','POST',{role:$('collab-invite-role').value});
    revealSecret('One-use '+result.role+' invitation (24 hours)',result.code);
    setStatus('Invite created. Send the code privately.');
  }
  async function pairStudio(){
    const result=await call('/studio-token','POST',{});
    revealSecret('Studio pairing token · paste into local Studio plugin',result.token);
    setStatus('New Studio token created. The previous plugin token is invalid.');
    await refresh();
  }
  async function leaveWorkspace(){
    if(!connection||infoModel?.role==='owner')return;
    if(!window.confirm('Leave this shared workspace? Your access token will be revoked.'))return;
    await call('/leave','POST',{});
    disconnect('You left the workspace. Existing local files were kept.');
  }
  function disconnect(message='Disconnected from this tab. Existing server access is NOT revoked.'){
    connection=null;infoModel=null;selectedRemote=null;selectedId=null;
    persist();hideSecret();setStatus(message);start();
  }
  async function safeAction(action){
    try{await action();}catch(error){
      if(error.status===409)await refresh();
      setStatus(error.message,true);notify(error.message,true);
    }
  }
  for(const [name,action] of [
    ['collab-create',createWorkspace],['collab-join',joinWorkspace],['collab-refresh',refresh],
    ['collab-create-script',createScript],['collab-save-script',publishScript],
    ['collab-invite',invite],['collab-studio-token',pairStudio],['collab-copy-secret',copySecret],
    ['collab-update-script',saveProperties],['collab-open-editor',()=>openRemote(selectedId)],['collab-leave',leaveWorkspace]
  ])$(name).addEventListener('click',()=>safeAction(action));
  $('collab-disconnect').addEventListener('click',()=>disconnect());
  for(const field of [search,filterType,filterTarget])field.addEventListener(field===search?'input':'change',render);
  for(const name of ['collab-page-btn','mobile-collab'])$(name).addEventListener('click',openPage);
  openButton.addEventListener('click',openPage);
  $('collab-back-editor').addEventListener('click',()=>{closePage();editor.input.focus();});
  for(const name of ['dashboard-btn','brand-home','mobile-dashboard'])$(name).addEventListener('click',closePage,{capture:true});
  editor.input.addEventListener('input',()=>{if(connection){setControls();if(visible)render();}});
  editor.input.addEventListener('luauforge:filechange',()=>{setControls();if(visible)render();});
  window.addEventListener('pagehide',()=>{if(timer)clearInterval(timer);});
  restored();start();
  return {open:openPage,close:closePage,refresh,get connection(){
    return connection?{workspaceId:connection.workspaceId,api:connection.api}:null;
  }};
}
