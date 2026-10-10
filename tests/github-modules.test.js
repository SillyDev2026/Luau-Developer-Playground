import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { parseGithubInput,parseGithubSpecifier,previewGithubModule,saveGithubPin,readGithubPins,removeGithubPin,loadGithubForProject,githubModuleTargets,GITHUB_PINS_KEY,githubVirtualFile } from '../src/github-modules.js';
import { bundleProject } from '../src/module-bundle.js';
const storage=()=>{const map=new Map();return {getItem:k=>map.get(k)??null,setItem:(k,v)=>map.set(k,v)}};
const fakeSha='a'.repeat(40);
const sample='local Math = {}\nfunction Math.add(a,b) return a + b end\nreturn Math\n';
function response(code,status=200){return {ok:status===200,status,headers:{get:()=> 'text/plain'},text:async()=>code,json:async()=>({sha:fakeSha})};}
test('GitHub path parser accepts exact public repository paths, rejects traversal and bad hosts',()=>{
  assert.equal(parseGithubSpecifier('@Alice/My-Repo/src/Math.luau').path,'src/Math.luau');
  assert.equal(parseGithubSpecifier('@FastNum'),null);
  assert.equal(parseGithubInput('https://github.com/Alice/My-Repo/blob/main/src/Math.luau').ref,'main');
  assert.equal(parseGithubInput('https://raw.githubusercontent.com/Alice/My-Repo/main/src/Math.luau').owner,'Alice');
  for(const url of ['@Alice/Repo/../secret.luau','@Alice/Repo/./src.luau','@Alice/Repo/lib/%2e%2e/hack.luau','https://evil.com/Alice/Repo/test.luau','@A/Repo/foo\\secret.luau'])assert.throws(()=>parseGithubInput(url));
});
test('public preview pins the resolved immutable commit and retains source without saving it',async()=>{
  const seen=[];
  const preview=await previewGithubModule('@Alice/My-Repo/src/Math.luau',{fetchImpl:async url=>{seen.push(url);return url.includes('/commits/')?response(''):response(sample);}});
  assert.equal(preview.sha,fakeSha);
  assert.equal(preview.specifier,'@Alice/My-Repo/src/Math.luau');
  assert.equal(preview.size,new TextEncoder().encode(sample).byteLength);
  assert.match(seen[1],new RegExp(fakeSha));
  const db=storage();saveGithubPin(preview,db);
  assert.equal(readGithubPins(db).length,1);
  assert.equal(db.getItem(GITHUB_PINS_KEY).includes(sample),false,'store metadata only, never downloaded source');
  removeGithubPin(preview.specifier,db);
  assert.equal(readGithubPins(db).length,0);
});
test('Studio-dependent scripts are flagged before saving a WASM pin',async()=>{
  const source='local MyModule = game:GetService("DataStoreService")\nreturn MyModule';
  const preview=await previewGithubModule('@Alice/MyRepo/src/Data.luau',{fetchImpl:async url=>url.includes('/commits/')?response(''):response(source)});
  assert.equal(preview.studioOnly,true);
  assert.throws(()=>saveGithubPin(preview,storage()),/Studio/);
});
test('public built-in TestTools loads through a site-local URL and resolves with normal Luau require semantics',async()=>{
  const project={active:'tests/example.test.luau',files:{'tests/example.test.luau':'local T = require("@SillyDev2026/Luau-Developer-Playground/community/TestTools.luau")\nT.equal(20+22,42)'}};
  const loaded=await loadGithubForProject(project,{storage:storage(),moduleUrl:'https://site.example/Luau-Developer-Playground/src/github-modules.js',fetchImpl:async url=>{assert.match(url,/\/community\/TestTools\.luau/);return response(await readFile(new URL('../public/community/TestTools.luau',import.meta.url),'utf8'));}});
  assert.equal(Object.keys(project.files).length,1);
  assert.equal(Object.keys(loaded.files).length,2);
  const bundle=bundleProject(loaded);
  assert.equal(bundle.dependencies[0].requested,'@SillyDev2026/Luau-Developer-Playground/community/TestTools.luau');
  assert.equal(Object.keys(bundle.modules).length,1);
});
test('unapproved external modules cannot execute even when a source URL is known',async()=>{
  const project={active:'main.luau',files:{'main.luau':'local M = require("@Alice/My-Repo/src/Math.luau")'}};
  await assert.rejects(loadGithubForProject(project,{storage:storage(),fetchImpl:async()=>{throw Error('should not fetch');}}),/Untrusted/);
});
test('approved external modules fetch only pinned SHA and resolve relative dependencies safely',async()=>{
  const db=storage();saveGithubPin({specifier:'@Alice/My-Repo/src/Math.luau',sha:fakeSha,size:80},db);
  const seen=[];
  const project={active:'main.luau',files:{'main.luau':'local M = require("@Alice/My-Repo/src/Math.luau")\nprint(M.value)'}};
  const ready=await loadGithubForProject(project,{storage:db,fetchImpl:async url=>{seen.push(url);return response(url.endsWith('src/Math.luau')?'local Data = require("./Data.luau")\nreturn {value=Data.value}':'return {value=42}');}});
  assert.equal(Object.keys(ready.files).length,3);
  assert.equal(bundleProject(ready).dependencies.length,2);
  assert.ok(seen.every(url=>url.includes(fakeSha)));
  assert.equal(githubModuleTargets(db).length,4);
});
test('dependency traversal cannot escape a public repository root',async()=>{
  const db=storage();saveGithubPin({specifier:'@Alice/Repo/Math.luau',sha:fakeSha},db);
  const project={active:'main.luau',files:{'main.luau':'local M = require("@Alice/Repo/Math.luau")'}};
  await assert.rejects(loadGithubForProject(project,{storage:db,fetchImpl:async()=>response('local X = require("../Hidden.luau")\nreturn X')}),/escapes repository/);
});
test('malformed saved pins are discarded instead of executed',()=>{
  const db=storage();db.setItem(GITHUB_PINS_KEY,JSON.stringify([{specifier:'@Alice/Repo/../bad.lua',sha:fakeSha},{specifier:'@Alice/Repo/module.luau',sha:'no'}]));
  assert.deepEqual(readGithubPins(db),[]);
});
test('site documentation wires up public module controls and HTML has no duplicate ids',async()=>{
  const html=await readFile(new URL('../index.html',import.meta.url),'utf8');
  const ui=await readFile(new URL('../src/v1.js',import.meta.url),'utf8');
  for(const id of ['github-module-add','github-module-publish'])assert.match(html,new RegExp(`id="${id}"`));
  assert.match(ui,/previewGithubModule/);
  assert.match(ui,/checkbox\.checked/);
  assert.match(html,/v=1\.7\.0/);
});
