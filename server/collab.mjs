import { createServer } from 'node:http';
import { randomBytes, randomUUID, createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';

const TYPES=new Set(['Script','ModuleScript','LocalScript']);
const TARGETS=new Set(['ReplicatedStorage','ServerScriptService','StarterGui','StarterPlayerScripts']);
const MAX_SCRIPTS=80,MAX_SOURCE=50000,MAX_BODY=80000;
const id=()=>randomUUID();
const secret=()=>randomBytes(32).toString('base64url');
const hash=value=>createHash('sha256').update(value).digest('hex');
const validName=value=>typeof value==='string'&&/^[A-Za-z0-9_][A-Za-z0-9_ -]{0,49}$/.test(value);
const validUser=value=>typeof value==='string'&&value.trim().length>=2&&value.trim().length<=36;
const isSource=value=>typeof value==='string'&&Buffer.byteLength(value,'utf8')<=MAX_SOURCE;
const safeRole=value=>value==='editor'||value==='viewer';
const json=(response,status,value,headers={})=>{
  response.writeHead(status,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff',...headers});
  response.end(JSON.stringify(value));
};
const failure=(status,message)=>Object.assign(new Error(message),{status});
const template=type=>type==='ModuleScript'?'--!strict\nlocal Module = {}\n\nreturn Module\n':type==='LocalScript'?'--!strict\n-- Client-side Luau\n':'--!strict\n-- Server-side Luau\n';

function readDatabase(path){
  if(!existsSync(path))return {version:1,workspaces:{}};
  const value=JSON.parse(readFileSync(path,'utf8'));
  if(value?.version!==1||!value.workspaces||typeof value.workspaces!=='object')throw Error('Unsupported collaboration database');
  return value;
}
function persist(path,value){
  mkdirSync(dirname(path),{recursive:true});
  const temp=path+'.'+process.pid+'.tmp';
  writeFileSync(temp,JSON.stringify(value),{mode:0o600});
  renameSync(temp,path);
}
async function parseBody(request){
  let size=0,chunks=[];
  for await(const chunk of request){
    size+=chunk.length;
    if(size>MAX_BODY)throw failure(413,'Request body exceeds limit');
    chunks.push(chunk);
  }
  try{
    const body=JSON.parse(Buffer.concat(chunks).toString('utf8'));
    if(!body||typeof body!=='object'||Array.isArray(body))throw Error();
    return body;
  }catch{throw failure(400,'Expected a JSON object');}
}
function requireSession(workspace,request){
  const auth=request.headers.authorization||'';
  const match=/^Bearer ([A-Za-z0-9_-]{30,120})$/.exec(auth);
  if(!match)throw failure(401,'Workspace token required');
  const digest=hash(match[1]);
  const member=Object.values(workspace.members).find(item=>item.tokenHash===digest);
  if(!member)throw failure(401,'Invalid workspace token');
  return member;
}
function requireStudio(workspace,request){
  const auth=request.headers.authorization||'';
  const match=/^Bearer ([A-Za-z0-9_-]{30,120})$/.exec(auth);
  if(!match||!workspace.studio?.tokenHash||hash(match[1])!==workspace.studio.tokenHash)throw failure(401,'Invalid Studio pairing token');
}
function editor(member){if(member.role==='viewer')throw failure(403,'This invitation is read-only');}
function owner(member){if(member.role!=='owner')throw failure(403,'Only the owner can manage invites and Studio pairing');}
function findWorkspace(db,workspaceId){
  const workspace=db.workspaces[workspaceId];
  if(!workspace)throw failure(404,'Workspace not found');
  return workspace;
}
function scriptSummary(script){
  const {id,name,type,target,version,updatedAt,updatedBy}=script;
  return {id,name,type,target,version,updatedAt,updatedBy};
}
function view(workspace,member){
  return {id:workspace.id,name:workspace.name,role:member.role,memberId:member.id,
    members:Object.values(workspace.members).map(({id,name,role})=>({id,name,role})),
    scripts:Object.values(workspace.scripts).map(scriptSummary),
    studio:{paired:Boolean(workspace.studio?.tokenHash),lastSeen:workspace.studio?.lastSeen||null}};
}
function uniqueScript(workspace,script,exclude){
  if(Object.values(workspace.scripts).some(x=>x.id!==exclude&&x.target===script.target&&x.name===script.name))throw failure(409,'A script with this name already exists in that Studio service');
}
function verifyScript(input){
  if(!validName(input.name))throw failure(400,'Script name must be 1–50 letters, digits, spaces, hyphens or underscores');
  if(!TYPES.has(input.type))throw failure(400,'Script type must be Script, LocalScript or ModuleScript');
  if(!TARGETS.has(input.target))throw failure(400,'Unsupported Studio destination');
  if(!isSource(input.source))throw failure(400,'Source must be UTF-8 text of 50 KB or less');
}
export function createCollabServer({dataFile,allowedOrigins=[],clock=()=>Date.now()}={}){
  if(!dataFile)throw Error('A persistent dataFile is required');
  const db=readDatabase(dataFile);
  const allowed=new Set(allowedOrigins.filter(Boolean));
  const attempt=new Map();
  const save=()=>persist(dataFile,db);
  const server=createServer(async(request,response)=>{
    response.setHeader('X-Content-Type-Options','nosniff');
    const origin=request.headers.origin;
    if(origin && !allowed.has(origin))return json(response,403,{error:'Origin not allowed'});
    if(origin){
      response.setHeader('Access-Control-Allow-Origin',origin);
      response.setHeader('Vary','Origin');
      response.setHeader('Access-Control-Allow-Headers','Authorization, Content-Type');
      response.setHeader('Access-Control-Allow-Methods','GET, POST, PATCH, OPTIONS');
    }
    if(request.method==='OPTIONS'){response.writeHead(204);response.end();return;}
    const pathname=new URL(request.url||'/', 'http://127.0.0.1').pathname;
    const route=pathname.split('/').filter(Boolean);
    const method=request.method;
    try{
      if(pathname==='/health'&&method==='GET')return json(response,200,{ok:true,service:'luauforge-collab'});
      if(route[0]!=='api')throw failure(404,'Unknown endpoint');
      if(!['GET','POST','PATCH'].includes(method))throw failure(405,'Method not allowed');
      // A small per-peer bound on account creation and invite redemption.
      if(method==='POST'&&(pathname==='/api/workspaces'||pathname==='/api/join')){
        const key=(request.socket.remoteAddress||'unknown')+':'+pathname,now=clock();
        const seen=(attempt.get(key)||[]).filter(time=>now-time<60000);
        if(seen.length>=30)throw failure(429,'Slow down and retry');
        seen.push(now);attempt.set(key,seen);
        if(attempt.size>2000)attempt.clear();
      }
      if(pathname==='/api/workspaces'&&method==='POST'){
        const body=await parseBody(request);
        if(!validUser(body.memberName)||typeof body.name!=='string'||body.name.trim().length<2||body.name.trim().length>80)throw failure(400,'Workspace and owner names required');
        const workspaceId=id(),memberId=id(),token=secret();
        const workspace={id:workspaceId,name:body.name.trim(),createdAt:clock(),
          members:{[memberId]:{id:memberId,name:body.memberName.trim(),role:'owner',tokenHash:hash(token)}},
          invites:{},scripts:{},studio:{tokenHash:null,lastSeen:null,applied:{}}};
        db.workspaces[workspaceId]=workspace;save();
        return json(response,201,{workspace:view(workspace,workspace.members[memberId]),token});
      }
      if(pathname==='/api/join'&&method==='POST'){
        const body=await parseBody(request);
        if(!validUser(body.memberName)||typeof body.code!=='string')throw failure(400,'Invite code and display name required');
        const digest=hash(body.code.trim()),now=clock();
        const workspace=Object.values(db.workspaces).find(w=>Object.values(w.invites).some(inv=>inv.hash===digest));
        if(!workspace)throw failure(404,'Invite code invalid or expired');
        const invite=Object.values(workspace.invites).find(x=>x.hash===digest);
        if(invite.expiresAt<=now){delete workspace.invites[invite.id];save();throw failure(410,'Invite expired');}
        if(Object.keys(workspace.members).length>=25)throw failure(409,'Workspace member limit reached');
        const memberId=id(),token=secret();
        workspace.members[memberId]={id:memberId,name:body.memberName.trim(),role:invite.role,tokenHash:hash(token)};
        delete workspace.invites[invite.id];save();
        return json(response,200,{workspace:view(workspace,workspace.members[memberId]),token});
      }
      if(route[1]==='workspaces'&&route[2]){
        const workspace=findWorkspace(db,route[2]),member=requireSession(workspace,request);
        if(route.length===3&&method==='GET')return json(response,200,{workspace:view(workspace,member)});
        if(route[3]==='invites'&&route.length===4&&method==='POST'){
          owner(member);
          const body=await parseBody(request);
          if(!safeRole(body.role))throw failure(400,'Invitation role must be editor or viewer');
          const now=clock();
          for(const [key,value] of Object.entries(workspace.invites))if(value.expiresAt<=now)delete workspace.invites[key];
          if(Object.keys(workspace.invites).length>=30)throw failure(429,'Too many pending invites');
          const code=secret(),invite={id:id(),hash:hash(code),role:body.role,expiresAt:now+24*3600000};
          workspace.invites[invite.id]=invite;save();
          return json(response,201,{code,role:invite.role,expiresAt:invite.expiresAt,uses:1});
        }
        if(route[3]==='studio-token'&&route.length===4&&method==='POST'){
          owner(member);
          const token=secret();
          workspace.studio={tokenHash:hash(token),lastSeen:null,applied:{}};
          save();
          return json(response,201,{token,workspaceId:workspace.id});
        }
        if(route[3]==='studio-status'&&route.length===4&&method==='GET'){
          return json(response,200,{studio:{paired:Boolean(workspace.studio?.tokenHash),lastSeen:workspace.studio.lastSeen,
            applied:Object.values(workspace.studio.applied).filter(x=>x.success).length,
            pending:Object.values(workspace.scripts).filter(script=>workspace.studio.applied[script.id]?.version!==script.version).length}});
        }
        if(route[3]==='scripts'){
          if(route.length===4&&method==='GET')return json(response,200,{scripts:Object.values(workspace.scripts).map(scriptSummary)});
          if(route.length===4&&method==='POST'){
            editor(member);
            const body=await parseBody(request);
            const script={id:id(),name:body.name,type:body.type,target:body.target,source:body.source??template(body.type),
              version:1,updatedBy:member.name,updatedAt:clock()};
            verifyScript(script);
            if(Object.keys(workspace.scripts).length>=MAX_SCRIPTS)throw failure(409,'Workspace script limit reached');
            uniqueScript(workspace,script);
            workspace.scripts[script.id]=script;save();
            return json(response,201,{script});
          }
          if(route.length===5){
            const script=workspace.scripts[route[4]];
            if(!script)throw failure(404,'Script not found');
            if(method==='GET')return json(response,200,{script});
            if(method==='PATCH'){
              editor(member);
              const body=await parseBody(request);
              if(!Number.isInteger(body.version)||body.version!==script.version)throw failure(409,'Another member saved a newer revision. Reload before editing.');
              const next={...script,name:body.name??script.name,type:body.type??script.type,
                target:body.target??script.target,source:body.source??script.source};
              verifyScript(next);uniqueScript(workspace,next,script.id);
              Object.assign(script,next,{version:script.version+1,updatedAt:clock(),updatedBy:member.name});
              save();return json(response,200,{script});
            }
          }
        }
      }
      if(route[1]==='studio'&&route[2]){
        const workspace=findWorkspace(db,route[2]);
        requireStudio(workspace,request);
        if(route[3]==='changes'&&route.length===4&&method==='GET'){
          workspace.studio.lastSeen=clock();save();
          const changes=Object.values(workspace.scripts).filter(script=>workspace.studio.applied[script.id]?.version!==script.version).slice(0,20);
          return json(response,200,{workspaceId:workspace.id,changes});
        }
        if(route[3]==='ack'&&route.length===4&&method==='POST'){
          const body=await parseBody(request),script=workspace.scripts[body.scriptId];
          if(!script)throw failure(404,'Script no longer exists');
          if(!Number.isInteger(body.version)||body.version!==script.version)throw failure(409,'Stale Studio acknowledgement');
          if(body.success!==true && body.success!==false)throw failure(400,'Acknowledgement must report success');
          const success=body.success===true;
          workspace.studio.applied[script.id]={version:success?script.version:0,success,
            message:success?'':String(body.error||'Failed to apply').slice(0,180),at:clock()};
          workspace.studio.lastSeen=clock();save();
          return json(response,200,{ok:true});
        }
      }
      throw failure(404,'Unknown endpoint');
    }catch(error){
      return json(response,error.status||500,{error:error.status?error.message:'Internal server error'});
    }
  });
  return {server,close:()=>new Promise(resolve=>server.close(resolve))};
}
