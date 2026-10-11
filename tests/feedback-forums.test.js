import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { createCollabServer } from '../server/collab.mjs';
import { normalizeFeedbackApi } from '../src/feedback.js';

const ORIGIN='https://sillydev2026.github.io';
const suggestionForum='1558939401394851850',bugForum='1558939354234093638';
const guild='123456789123456789',threadOne='223456789123456789',threadTwo='323456789123456789';
const response=(code,body={})=>new Response(code===204?null:JSON.stringify(body),{status:code,headers:{'Content-Type':'application/json'}});
function testServer(t,{configured=true,discordFailure=false}={}){
  const folder=mkdtempSync(join(tmpdir(),'feedback-test-'));
  const requests=[];
  const mock=async(url,options)=>{
    const path=new URL(url).pathname;requests.push({path,method:options.method,body:options.body?JSON.parse(options.body):null,auth:options.headers.Authorization});
    if(discordFailure)return response(403,{code:50013,message:'Missing permissions'});
    if(options.method==='POST'&&/\/threads$/.test(path)){
      const isBug=path.includes(bugForum);
      const id=isBug?threadTwo:threadOne;
      return response(201,{id,guild_id:guild,message:{id}});
    }
    if(options.method==='PATCH')return response(200,{id:path.split('/').at(-1)});
    if(options.method==='PUT')return response(204);
    return response(404);
  };
  const app=createCollabServer({dataFile:join(folder,'workspace.json'),
    feedbackDataFile:join(folder,'feedback.json'),allowedOrigins:[ORIGIN],
    discordBotToken:configured?'test-discord-token':'',discordRequest:mock});
  t.after(async()=>{if(app.server.listening)await app.close();rmSync(folder,{recursive:true,force:true});});
  return {app,folder,requests};
}
async function listen(app){
  await new Promise(resolve=>app.server.listen(0,'127.0.0.1',resolve));
  return 'http://127.0.0.1:'+app.server.address().port;
}
async function call(url,path,{method='GET',body,token,origin=ORIGIN}={}){
  const res=await fetch(url+path,{method,headers:{...(origin?{Origin:origin}:{}),...(token?{Authorization:'Bearer '+token}:{}),...(body?{'Content-Type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{})});
  return {status:res.status,data:await res.json(),headers:res.headers};
}
const profile=(url,name='Developer')=>call(url,'/api/feedback/session',{method:'POST',body:{name}});
const makePost=(url,token,type,title)=>call(url,'/api/feedback/posts',{
  method:'POST',token,body:{type,title,body:'The editor should handle this scenario with useful diagnostics and no crashes.'}
});
test('each submission creates a genuine Discord forum thread in the intended channel',async t=>{
  const {app,folder,requests}=testServer(t),url=await listen(app);
  const info=await call(url,'/api/feedback/status');
  assert.equal(info.status,200);assert.equal(info.data.configured,true);
  assert.equal((await call(url,'/api/feedback/posts')).data.posts.length,0);
  const person=await profile(url),token=person.data.token;
  assert.equal(person.status,201);
  const suggestion=await makePost(url,token,'suggestion','Better Luau autocomplete');
  assert.equal(suggestion.status,201);
  assert.equal(suggestion.data.post.type,'suggestion');
  assert.equal(suggestion.data.post.threadUrl,'https://discord.com/channels/'+guild+'/'+threadOne);
  const bug=await makePost(url,token,'bug','Autocomplete fails on nested modules');
  assert.equal(bug.status,201);
  assert.equal(bug.data.post.threadUrl,'https://discord.com/channels/'+guild+'/'+threadTwo);
  const creations=requests.filter(x=>x.method==='POST');
  assert.equal(creations.length,2);
  assert.equal(creations[0].path,'/api/v10/channels/'+suggestionForum+'/threads');
  assert.equal(creations[1].path,'/api/v10/channels/'+bugForum+'/threads');
  assert.equal(creations[0].body.message.allowed_mentions.parse.length,0);
  assert.match(creations[0].body.message.content,/Website votes.*👍 0/);
  assert.equal(creations[0].auth,'Bot test-discord-token');
  assert.equal(requests.filter(x=>x.method==='PUT').length,4);
  const list=await call(url,'/api/feedback/posts',{token});
  assert.equal(list.data.posts.length,2);
  assert.equal(list.data.posts[0].author,'Developer');
  assert.equal(list.data.posts[0].myVote,0);
  const saved=readFileSync(join(folder,'feedback.json'),'utf8');
  assert.ok(!saved.includes(token));
  assert.ok(!saved.includes('test-discord-token'));
});

test('thumbs up/down track each visitor, change votes, and update the Discord forum starter message',async t=>{
  const {app,requests}=testServer(t),url=await listen(app);
  const writer=(await profile(url,'Author')).data.token;
  const visitor=(await profile(url,'Voter')).data.token;
  const post=(await makePost(url,writer,'bug','Broken auto indent in scripts')).data.post;
  const path='/api/feedback/posts/'+post.id+'/vote';
  const cast=async(voter,value)=>call(url,path,{method:'POST',token:voter,body:{vote:value}});
  assert.equal((await cast(visitor,1)).data.post.upvotes,1);
  let current=await call(url,'/api/feedback/posts',{token:visitor});
  assert.equal(current.data.posts[0].myVote,1);
  assert.equal((await cast(visitor,-1)).data.post.upvotes,0);
  assert.equal((await call(url,path,{method:'POST',token:writer,body:{vote:1}})).data.post.upvotes,1);
  assert.equal((await cast(visitor,-1)).data.post.downvotes,0);
  assert.equal((await cast(visitor,1)).data.post.score,2);
  assert.equal((await cast(visitor,1)).data.post.myVote,0);
  assert.equal((await cast(visitor,4)).status,400);
  assert.equal((await call(url,path,{method:'POST',body:{vote:1}})).status,401);
  current=await call(url,'/api/feedback/posts');
  assert.equal(current.data.posts[0].myVote,0);
  assert.equal(current.data.posts[0].upvotes,1);
  const patches=requests.filter(x=>x.method==='PATCH');
  assert.ok(patches.length>=5);
  assert.match(patches.at(-1).body.content,/👍 1  \|  👎 0/);
  assert.deepEqual(patches.at(-1).body.allowed_mentions,{parse:[]});
});

test('missing bot, bad forum permissions and validation errors never claim success',async t=>{
  const {app}=testServer(t,{configured:false}),url=await listen(app);
  assert.equal((await call(url,'/api/feedback/status')).data.configured,false);
  const person=(await profile(url)).data.token;
  assert.equal((await makePost(url,person,'suggestion','A valid feature title')).status,503);
  assert.equal((await call(url,'/api/feedback/posts')).data.posts.length,0);
});
test('Discord permission failures are surfaced without saving a nonexistent post',async t=>{
  const {app}=testServer(t,{discordFailure:true}),url=await listen(app);
  const member=(await profile(url)).data.token;
  const output=await makePost(url,member,'bug','Fail to render Lua Editor');
  assert.equal(output.status,502);
  assert.match(output.data.error,/Discord rejected/);
  assert.equal((await call(url,'/api/feedback/posts')).data.posts.length,0);
});
test('validation, visitor sessions, origin control and posting limits',async t=>{
  const {app}=testServer(t),url=await listen(app);
  assert.equal((await profile(url,'A')).status,400);
  assert.equal((await profile(url,'@everyone')).status,400);
  const key=(await profile(url)).data.token;
  assert.equal((await call(url,'/api/feedback/posts',{method:'POST',token:key,
    body:{type:'other',title:'A valid title',body:'This description is long enough to send to Discord.'}})).status,400);
  assert.equal((await call(url,'/api/feedback/posts',{method:'POST',token:key,
    body:{type:'bug',title:'Short',body:'This description is long enough to send to Discord.'}})).status,400);
  assert.equal((await call(url,'/api/feedback/posts',{origin:'https://evil.example'})).status,403);
  assert.equal((await makePost(url,key,'suggestion','First clear feature suggestion')).status,201);
  assert.equal((await makePost(url,key,'suggestion','Second clear feature request')).status,201);
  assert.equal((await makePost(url,key,'bug','Third issue report example')).status,201);
  assert.equal((await makePost(url,key,'bug','Fourth issue report example')).status,429);
});
test('feedback website exposes correct UI controls without placing bot token in browser',async()=>{
  const {readFile}=await import('node:fs/promises');
  const [html,js,css,server,entry]=await Promise.all(['index.html','src/feedback.js','src/feedback.css','server/feedback.mjs','server/index.mjs'].map(file=>readFile(new URL('../'+file,import.meta.url),'utf8')));
  for(const id of ['feedback-view','feedback-page-btn','mobile-feedback','feedback-form','feedback-title','feedback-description','feedback-post-list','feedback-sort','feedback-search','feedback-submit','feedback-api']){
    assert.match(html,new RegExp('id="'+id+'"'));
  }
  assert.match(css,/\.main-surface\.feedback-page-active/);
  assert.match(js,/textContent/);
  assert.match(js,/aria-pressed/);
  assert.match(js,/sessionStorage/);
  assert.doesNotMatch(html,/DISCORD_BOT_TOKEN/);
  assert.doesNotMatch(js,/DISCORD_BOT_TOKEN/);
  assert.match(entry,/process\.env\.DISCORD_BOT_TOKEN/);
  assert.match(server,/allowed_mentions:\{parse:\[\]\}/);
  assert.equal(normalizeFeedbackApi('https://example.com/'),'https://example.com');
  assert.equal(normalizeFeedbackApi('http://localhost:8787/'),'http://localhost:8787');
  assert.throws(()=>normalizeFeedbackApi('http://evil.example'),/HTTPS/);
  assert.throws(()=>normalizeFeedbackApi('https://someone@evil.example'),/origin only/);
});
