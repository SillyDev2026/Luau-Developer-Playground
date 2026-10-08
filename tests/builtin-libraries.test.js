import test from 'node:test';
import assert from 'node:assert/strict';
import { BUILTIN_LIBRARIES, builtinId, builtinPath, adaptBuiltinSource, loadBuiltinsForProject, clearBuiltinCache, fetchBuiltinSource } from '../src/builtin-libraries.js';
import { bundleProject } from '../src/module-bundle.js';

test('catalog includes exactly three pinned user-owned modules and real API methods', () => {
  assert.deepEqual(BUILTIN_LIBRARIES.map(lib => lib.id), ['FastNum','NanoNum','OmegaNum']);
  assert.deepEqual(BUILTIN_LIBRARIES.map(lib => lib.version), ['2.9.5','2.4.10','2.4.0']);
  assert.ok(BUILTIN_LIBRARIES.every(lib => lib.example.includes(`require("@${lib.id}")`) && lib.categories.length >= 3));
  assert.equal(builtinId('@FastNum'), 'FastNum');
  assert.equal(builtinId('@Untrusted'), null);
});

test('bundler resolves @FastNum transitively without copying library into saved workspace', async () => {
  clearBuiltinCache();
  const project = { active:'main.luau', files: { 'main.luau': 'local a = require("./test/Bridge.luau")\nprint(a.sum(1,2))', 'test/Bridge.luau': 'local lib = require("@FastNum")\nreturn {sum = function(a,b) return lib.toNumber(lib.add(lib.fromNumber(a),lib.fromNumber(b))) end}' } };
  const hydrated = await loadBuiltinsForProject(project, {fetchSource: async id => `local FastME = {}\nfunction FastME.fromNumber(x) return x end\nfunction FastME.add(a,b) return a+b end\nfunction FastME.toNumber(x) return x end\nreturn FastME`});
  assert.equal(Object.keys(project.files).length, 2);
  assert.ok(hydrated.files[builtinPath('FastNum')]);
  const bundled = bundleProject(hydrated);
  assert.ok(Object.values(bundled.modules).some(v=>v.includes('function FastME.fromNumber')));
  assert.ok(bundled.dependencies.some(dep=>dep.requested==='@FastNum'));
  assert.ok(!bundled.code.includes('@FastNum'));
});

test('missing and malicious aliases are rejected explicitly', () => {
  assert.throws(() => bundleProject({active:'main.luau',files:{'main.luau':'local x = require("@FastNum")'}}), /Missing built-in/);
  assert.throws(() => bundleProject({active:'main.luau',files:{'main.luau':'local x = require("@NoSuchLibrary")'}}), /Unsupported require/);
});

test('browser adapter preserves all OmegaNum source except HttpService JSON encoding', () => {
  const original = '--!native\nlocal HttpService = game:GetService("HttpService")\nlocal OmegaNum = {}\nreturn OmegaNum';
  const adapted = adaptBuiltinSource('OmegaNum', original);
  assert.doesNotMatch(adapted,/game:GetService/);
  assert.match(adapted, /JSONEncode/);
  assert.match(adapted, /return OmegaNum/);
  assert.equal(adaptBuiltinSource('FastNum',original), original);
  assert.throws(()=>adaptBuiltinSource('OmegaNum', 'return {}'),/adapter needs updating/);
});

test('loader tries both Pages layouts and rejects HTML in place of a library', async () => {
  const visited = [];
  const sample = 'local Lib = {}\n'+'-- Source line\n'.repeat(500)+'return Lib';
  const source = await fetchBuiltinSource('FastNum', {moduleUrl:'https://host.example/Playground/src/builtin-libraries.js',fetchImpl:async url => {
    visited.push(url.pathname);
    if(visited.length===1) return {ok:true,headers:{get:()=> 'text/html'},text:async()=>'<html />'};
    return {ok:true,headers:{get:()=> 'text/plain'},text:async()=>sample};
  }});
  assert.equal(source,sample);
  assert.deepEqual(visited,['/Playground/libraries/FastNum.lua','/Playground/public/libraries/FastNum.lua']);
});

test('fetch failures can retry and do not poison the library cache', async () => {
  clearBuiltinCache();
  const project={active:'main.luau',files:{'main.luau':'local FastME = require("@FastNum")'}};
  let attempts = 0;
  const get = () => loadBuiltinsForProject(project,{fetchSource:async()=>{attempts++;if(attempts===1)throw Error('Offline');return 'return {}';}});
  await assert.rejects(get(),/Offline/);
  await Promise.resolve();
  const success=await get();
  assert.ok(success.files[builtinPath('FastNum')]);
  assert.equal(attempts,2);
});
