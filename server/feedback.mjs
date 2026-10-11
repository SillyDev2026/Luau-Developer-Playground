import { randomBytes, randomUUID, createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync, renameSync } from 'node:fs';
import { dirname } from 'node:path';

const CHANNELS=Object.freeze({suggestion:'1558939401394851850',bug:'1558939354234093638'});
const MAX_BODY=10000;
const token=()=>randomBytes(32).toString('base64url');
const digest=value=>createHash('sha256').update(value).digest('hex');
const fail=(status,message)=>Object.assign(new Error(message),{status});
const validText=(value,min,max)=>typeof value==='string'&&value.trim().length>=min&&value.trim().length<=max;
const respond=(res,status,body)=>{
  res.writeHead(status,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});
  res.end(JSON.stringify(body));
};
const validSnowflake=value=>typeof value==='string'&&/^\d{17,20}$/.test(value);
function database(file){
  if(!existsSync(file))return {version:1,users:{},posts:{}};
  const value=JSON.parse(readFileSync(file,'utf8'));
  if(value?.version!==1||!value.users||!value.posts)throw Error('Invalid feedback database');
  return value;
}
function persist(path,data){
  mkdirSync(dirname(path),{recursive:true});
  const temp=path+'.'+process.pid+'.tmp';
  writeFileSync(temp,JSON.stringify(data),{mode:0o600});
  renameSync(temp,path);
}
async function readBody(req){
  let size=0,parts=[];
  for await(const part of req){
    size+=part.length;
    if(size>MAX_BODY)throw fail(413,'Request too large');
    parts.push(part);
  }
  try{
    const value=JSON.parse(Buffer.concat(parts).toString('utf8'));
    if(!value||typeof value!=='object'||Array.isArray(value))throw Error();
    return value;
  }catch{throw fail(400,'Expected a valid JSON object');}
}
function auth(data,request){
  const bearer=/^Bearer ([A-Za-z0-9_-]{30,120})$/.exec(request.headers.authorization||'');
  if(!bearer)throw fail(401,'Connect a feedback profile first');
  const user=data.users[digest(bearer[1])];
  if(!user)throw fail(401,'Feedback session expired or invalid');
  return user;
}
function tally(post){
  const values=Object.values(post.votes);
  return {upvotes:values.filter(x=>x===1).length,downvotes:values.filter(x=>x===-1).length};
}
function publicPost(post,memberId){
  const {upvotes,downvotes}=tally(post);
  return {id:post.id,type:post.type,title:post.title,body:post.body,author:post.author,createdAt:post.createdAt,
    threadUrl:post.threadUrl,upvotes,downvotes,score:upvotes-downvotes,myVote:post.votes[memberId]||0,
    discordSynced:post.discordSynced!==false};
}
function forumMessage(post){
  const {upvotes,downvotes}=tally(post);
  const label=post.type==='bug'?'Bug report':'Suggestion';
  return '**'+label+' · LuauForge feedback**\n**Submitted by:** '+post.author+
    '\n\n'+post.body+'\n\n**Website votes:** 👍 '+upvotes+'  |  👎 '+downvotes+
    '\n*Discord reactions are separate from website votes.*';
}
export async function discordApi(method,path,body,botToken,request=fetch){
  if(!botToken)throw fail(503,'Discord bot token is not configured on the Node backend');
  const response=await request('https://discord.com/api/v10'+path,{
    method,headers:{Authorization:'Bot '+botToken,'Content-Type':'application/json'},
    ...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(12000)
  });
  if(!response.ok){
    const detail=await response.json().catch(()=>({}));
    // Do not leak bot authorization details, server credentials or Discord request bodies.
    throw fail(response.status===429?503:502,'Discord rejected the request (HTTP '+response.status+
      (typeof detail.code==='number'?', code '+detail.code:'')+'). Check bot permissions and forum configuration.');
  }
  return response.status===204?null:response.json();
}

export function createFeedbackApi({dataFile,botToken='',channels=CHANNELS,clock=()=>Date.now(),request=fetch}={}){
  if(!dataFile)throw Error('Persistent feedback dataFile required');
  const data=database(dataFile),attempts=new Map();
  const save=()=>persist(dataFile,data);
  const discord=(method,path,body)=>discordApi(method,path,body,botToken,request);
  function limit(key,max,windowMs){
    const now=clock(),recent=(attempts.get(key)||[]).filter(x=>now-x<windowMs);
    if(recent.length>=max)throw fail(429,'Rate limit reached. Try again later.');
    recent.push(now);attempts.set(key,recent);
    if(attempts.size>5000)attempts.clear();
  }
  async function handle(req,res,pathname){
    if(!pathname.startsWith('/api/feedback'))return false;
    const route=pathname.split('/').filter(Boolean),method=req.method;
    try{
      if(route.length===3&&route[2]==='status'&&method==='GET'){
        return respond(res,200,{configured:Boolean(botToken&&validSnowflake(channels.suggestion)&&validSnowflake(channels.bug)),
          categories:['suggestion','bug'],voteMode:'website-with-discord-summary'});
      }
      if(route.length===3&&route[2]==='session'&&method==='POST'){
        limit('profile:'+req.socket.remoteAddress,12,3600000);
        const body=await readBody(req);
        if(!validText(body.name,2,32)||/[\r\n<>@]/.test(body.name))throw fail(400,'Display name must be 2–32 characters without @ or markup');
        const key=token(),user={id:randomUUID(),name:body.name.trim(),createdAt:clock()};
        data.users[digest(key)]=user;save();
        return respond(res,201,{token:key,name:user.name});
      }
      if(route.length===3&&route[2]==='posts'&&method==='GET'){
        // Repair a failed Discord summary after a cooldown when people refresh.
        const retry=Object.values(data.posts).find(post=>post.discordSynced===false&&
          clock()-(post.lastSyncAttemptAt||0)>=30000);
        if(retry&&botToken){
          retry.lastSyncAttemptAt=clock();save();
          try{
            await discord('PATCH','/channels/'+retry.threadId+'/messages/'+retry.messageId,
              {content:forumMessage(retry),allowed_mentions:{parse:[]}});
            retry.discordSynced=true;save();
          }catch{/* Retain unsynced state and retry on a later refresh. */}
        }
        // Public list; an optional session token personalizes vote state.
        let memberId='';
        try{memberId=auth(data,req).id;}catch{}
        const list=Object.values(data.posts).sort((a,b)=>b.createdAt-a.createdAt).slice(0,100).map(p=>publicPost(p,memberId));
        return respond(res,200,{posts:list});
      }
      if(route.length===3&&route[2]==='posts'&&method==='POST'){
        const user=auth(data,req);
        if(!botToken)throw fail(503,'Discord bot has not been configured on this backend');
        limit('post-user:'+user.id,3,3600000);
        limit('post-address:'+req.socket.remoteAddress,10,3600000);
        const body=await readBody(req);
        if(!['suggestion','bug'].includes(body.type))throw fail(400,'Choose Suggestion or Bug report');
        if(!validText(body.title,8,100)||/[\r\n]/.test(body.title))throw fail(400,'Title must be 8–100 characters on one line');
        if(!validText(body.body,20,1400))throw fail(400,'Description must be 20–1400 characters');
        const channel=channels[body.type];
        if(!validSnowflake(channel))throw fail(503,'Discord forum channel is not configured');
        if(Object.keys(data.posts).length>=500)throw fail(503,'Feedback storage capacity reached');
        const post={id:randomUUID(),type:body.type,title:body.title.trim(),body:body.body.trim(),
          author:user.name,createdAt:clock(),votes:{},discordSynced:true};
        let thread;
        try{
          thread=await discord('POST','/channels/'+channel+'/threads',{
            name:post.title,message:{content:forumMessage(post),allowed_mentions:{parse:[]}},
            auto_archive_duration:1440
          });
        }catch(error){if(error.status)throw error;throw fail(502,'Could not create a Discord forum thread. Try again later.');}
        if(!validSnowflake(thread?.id)||!validSnowflake(thread?.guild_id))throw fail(502,'Discord did not return a valid forum thread');
        post.threadId=thread.id;
        post.messageId=validSnowflake(thread.message?.id)?thread.message.id:thread.id;
        post.threadUrl='https://discord.com/channels/'+thread.guild_id+'/'+thread.id;
        data.posts[post.id]=post;save();
        // Optional native Discord reactions for Discord members. Web votes use
        // server-maintained tallies, since one bot cannot react as every visitor.
        for(const emoji of ['👍','👎']){
          try{await discord('PUT','/channels/'+thread.id+'/messages/'+post.messageId+'/reactions/'+encodeURIComponent(emoji)+'/@me');}
          catch{/* This doesn't alter successful creation of the forum post. */}
        }
        return respond(res,201,{post:publicPost(post,user.id)});
      }
      if(route.length===5&&route[2]==='posts'&&route[4]==='vote'&&method==='POST'){
        const user=auth(data,req),post=data.posts[route[3]];
        if(!post)throw fail(404,'Feedback post does not exist');
        limit('vote:'+user.id,40,3600000);
        const body=await readBody(req);
        if(body.vote!==-1&&body.vote!==0&&body.vote!==1)throw fail(400,'Vote must be -1, 0, or 1');
        const prior=post.votes[user.id]||0,desired=body.vote===prior?0:body.vote;
        if(desired===0)delete post.votes[user.id];else post.votes[user.id]=desired;
        post.discordSynced=false;post.lastSyncAttemptAt=clock();save();
        try{
          await discord('PATCH','/channels/'+post.threadId+'/messages/'+post.messageId,
            {content:forumMessage(post),allowed_mentions:{parse:[]}});
          post.discordSynced=true;save();
        }catch{/* Votes persist even if Discord is temporarily unavailable. */}
        return respond(res,200,{post:publicPost(post,user.id)});
      }
      throw fail(404,'Feedback endpoint not found');
    }catch(error){
      return respond(res,error.status||500,{error:error.status?error.message:'Unexpected feedback service error'});
    }
  }
  return {handle};
}
