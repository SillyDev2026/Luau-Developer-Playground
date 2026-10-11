// Community feedback UI. The Node backend owns all Discord credentials.
// Display names are unverified; sessions are pseudonymous and kept per tab.
const SESSION_KEY='luauforge:feedback:session:v1';
const ORIGIN_KEY='luauforge:feedback:api:v1';
const element=(tag,cls,text)=>{
  const node=document.createElement(tag);
  if(cls)node.className=cls;
  if(text!==undefined)node.textContent=String(text);
  return node;
};
export function normalizeFeedbackApi(value){
  const url=new URL(value.trim());
  const local=['localhost','127.0.0.1'].includes(url.hostname);
  if(url.protocol!=='https:'&&!(local&&url.protocol==='http:'))throw Error('Use an HTTPS Node server (localhost is allowed for testing).');
  if(url.username||url.password||url.pathname!=='/'||url.search||url.hash)throw Error('Enter the server origin only, without a path.');
  return url.origin;
}
export async function feedbackRequest(api,path,{token='',method='GET',body}={}){
  const response=await fetch(api+path,{method,cache:'no-store',signal:AbortSignal.timeout(15000),
    headers:{...(body?{'Content-Type':'application/json'}:{}),...(token?{Authorization:'Bearer '+token}:{})},
    ...(body?{body:JSON.stringify(body)}:{})});
  const data=await response.json().catch(()=>({}));
  if(!response.ok)throw Object.assign(Error(data.error||'Request failed (HTTP '+response.status+')'),{status:response.status});
  return data;
}
export function mountFeedback({notify=()=>{},onOpenPage=()=>{}}={}){
  const $=id=>document.getElementById(id),page=$('feedback-view');
  if(!page)return null;
  const list=$('feedback-post-list'),status=$('feedback-status'),apiInput=$('feedback-api'),
    nameInput=$('feedback-name'),titleInput=$('feedback-title'),descInput=$('feedback-description');
  let session=null,posts=[],configured=false,visible=false,busy=false;
  try{
    const value=JSON.parse(sessionStorage.getItem(SESSION_KEY)||'null');
    if(value?.api&&value?.token&&value?.name)session={api:normalizeFeedbackApi(value.api),token:value.token,name:value.name};
  }catch{/* unavailable */}
  try{
    const collab=JSON.parse(sessionStorage.getItem('luauforge:collab:session:v1')||'null');
    apiInput.value=session?.api||localStorage.getItem(ORIGIN_KEY)||collab?.api||'';
  }catch{apiInput.value=session?.api||'';}
  if(session)nameInput.value=session.name;
  function message(text,error=false){
    status.textContent=text;status.dataset.error=String(error);
  }
  function currentApi(){
    return normalizeFeedbackApi(apiInput.value);
  }
  function activeSession(){
    try{return session?.api===currentApi()?session:null;}catch{return null;}
  }
  function setProfile(){
    const active=activeSession();
    $('feedback-profile-status').textContent=active?'Connected as '+active.name+' · session in this tab':
      session?'Server address changed. Connect a profile for this server.':'Not connected. Choose a display name.';
    $('feedback-submit').disabled=!active||!configured||busy;
  }
  const typeInputs=[...page.querySelectorAll('input[name="feedback-type"]')];
  function activeType(){return typeInputs.find(input=>input.checked)?.value||'suggestion';}
  function showType(){
    $('feedback-destination').textContent=activeType()==='bug'?
      'Bug report → Discord bug-report forum':'Suggestion → Discord suggestion forum';
  }
  async function load(){
    const api=currentApi();
    const [settings,response]=await Promise.all([
      feedbackRequest(api,'/api/feedback/status'),
      feedbackRequest(api,'/api/feedback/posts',{token:session?.api===api?session.token:''})
    ]);
    configured=settings.configured===true;
    posts=response.posts||[];
    try{localStorage.setItem(ORIGIN_KEY,api);}catch{/* optional */}
    setProfile();render();
    if(!configured)message('Backend reached, but the Discord forum integration is not configured. Ask the site owner to enable it.',true);
    else message('Connected to the feedback board. Suggestions and bugs open separate Discord forum threads.');
    return response;
  }
  function filtered(){
    const q=$('feedback-search').value.trim().toLowerCase();
    const category=$('feedback-category').value,sort=$('feedback-sort').value;
    const entries=posts.filter(post=>
      (category==='all'||post.type===category)&&
      (!q||[post.title,post.body,post.author].some(x=>x.toLowerCase().includes(q))));
    if(sort==='top')entries.sort((a,b)=>b.upvotes-a.upvotes||b.createdAt-a.createdAt);
    else if(sort==='discussed')entries.sort((a,b)=>b.score-a.score||b.createdAt-a.createdAt);
    else entries.sort((a,b)=>b.createdAt-a.createdAt);
    return entries;
  }
  function render(){
    list.replaceChildren();
    $('feedback-post-count').textContent=String(posts.length);
    const entries=filtered();
    if(!entries.length){
      list.append(element('p','feedback-empty',posts.length?
        'No posts match the current search. Try another category or keyword.':
        'No feedback yet. Share the first suggestion or bug report after connecting.'));
      return;
    }
    for(const post of entries){
      const card=element('article','feedback-post');
      const heading=element('div','feedback-post-heading'),headerText=element('div');
      const kind=element('span','feedback-kind '+post.type,post.type==='bug'?'⚑ BUG REPORT':'✦ SUGGESTION');
      const headingText=element('h3','',post.title);
      headerText.append(kind,headingText);heading.append(headerText);
      const body=element('p','feedback-post-desc',post.body);
      const created=Number.isFinite(post.createdAt)?new Date(post.createdAt).toLocaleDateString():'';
      const meta=element('div','feedback-post-meta','By '+post.author+' · '+created);
      const row=element('div','feedback-post-actions');
      const voteButton=(voteValue,icon,textCount)=>{
        const button=element('button','feedback-vote'+(post.myVote===voteValue?' active':''),icon+' '+textCount);
        button.type='button';
        button.disabled=!activeSession()||busy;
        button.title=activeSession()?'Vote '+(voteValue===1?'up':'down')+' (click again to undo)':'Connect a feedback profile to vote';
        button.setAttribute('aria-pressed',String(post.myVote===voteValue));
        button.addEventListener('click',()=>run(async()=>{
          const result=await feedbackRequest(currentApi(),'/api/feedback/posts/'+post.id+'/vote',{
            method:'POST',token:activeSession().token,body:{vote:voteValue}
          });
          posts=posts.map(item=>item.id===post.id?result.post:item);
          render();
          message(result.post.discordSynced?'Vote recorded and Discord summary updated.':
            'Vote saved; Discord summary update will be retried later.');
        }));
        return button;
      };
      row.append(voteButton(1,'👍',post.upvotes),voteButton(-1,'👎',post.downvotes),element('span','feedback-score','Score '+(post.score>0?'+':'')+post.score));
      if(post.discordSynced===false)row.append(element('span','feedback-sync-note','Discord summary pending'));
      if(/^https:\/\/discord\.com\/channels\/\d{17,20}\/\d{17,20}$/.test(post.threadUrl||'')){
        const link=element('a','feedback-discord-link','Discuss on Discord ↗');
        link.href=post.threadUrl;link.target='_blank';link.rel='noopener noreferrer';
        row.append(link);
      }
      card.append(heading,body,meta,row);list.append(card);
    }
  }
  async function run(task){
    if(busy)return;
    busy=true;setProfile();
    try{await task();}
    catch(error){
      message(error.message,true);
      if(error.status===401){session=null;try{sessionStorage.removeItem(SESSION_KEY);}catch{}}
      notify(error.message,true);
    }finally{busy=false;setProfile();render();}
  }
  async function connect(){
    const api=currentApi();
    if(nameInput.value.trim().length<2)throw Error('Please enter a display name (at least 2 characters).');
    const status=await feedbackRequest(api,'/api/feedback/status');
    if(!status.configured)throw Error('Discord feedback bot is not configured on the Node backend yet.');
    const reply=await feedbackRequest(api,'/api/feedback/session',{method:'POST',body:{name:nameInput.value.trim()}});
    session={api,token:reply.token,name:reply.name};configured=true;
    try{sessionStorage.setItem(SESSION_KEY,JSON.stringify(session));}catch{}
    await load();
    message('Feedback profile connected as '+session.name+'. You can now submit and vote.');
  }
  async function submit(){
    if(!activeSession())throw Error('Connect your feedback profile for this backend before submitting.');
    const type=activeType();
    const result=await feedbackRequest(session.api,'/api/feedback/posts',{
      token:activeSession().token,method:'POST',
      body:{type,title:titleInput.value.trim(),body:descInput.value.trim()}
    });
    titleInput.value='';descInput.value='';
    posts.unshift(result.post);render();
    message('Successfully created a '+(type==='bug'?'bug report':'suggestion')+' Discord forum thread! Open it using Discuss on Discord.');
  }
  function open(){
    onOpenPage();
    visible=true;page.classList.remove('hidden');
    $('main-surface').classList.add('feedback-page-active');
    if(apiInput.value.trim())run(load);
    else message('Enter your Node backend URL to read, submit and vote on feedback.');
    $('feedback-back-editor').focus();
  }
  function close(){
    visible=false;page.classList.add('hidden');
    $('main-surface').classList.remove('feedback-page-active');
  }
  for(const id of ['feedback-page-btn','mobile-feedback'])$(id).addEventListener('click',open);
  $('feedback-back-editor').addEventListener('click',close);
  $('feedback-connect-btn').addEventListener('click',()=>run(connect));
  apiInput.addEventListener('input',()=>{configured=false;setProfile();});
  $('feedback-reload').addEventListener('click',()=>run(load));
  $('feedback-form').addEventListener('submit',event=>{event.preventDefault();run(submit);});
  for(const id of ['feedback-search','feedback-category','feedback-sort']){
    $(id).addEventListener(id==='feedback-search'?'input':'change',render);
  }
  for(const input of typeInputs)input.addEventListener('change',showType);
  for(const id of ['dashboard-btn','mobile-dashboard','brand-home'])$(id).addEventListener('click',close,{capture:true});
  for(const id of ['collab-page-btn','mobile-collab'])$(id).addEventListener('click',close,{capture:true});
  showType();setProfile();render();
  return {open,close,refresh:()=>run(load),get visible(){return visible;}};
}
