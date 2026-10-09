import test from 'node:test';
import assert from 'node:assert/strict';
import { Workspace,findProjectTests,classifyScript } from '../src/v1-model.js';
const makeStorage=()=>{const map=new Map();return {getItem:k=>map.get(k)||null,setItem:(k,v)=>map.set(k,v),removeItem:k=>map.delete(k)};};
test('v1 workspace migrates saved v2 project without erasing files',()=>{
 const storage=makeStorage();
 storage.setItem('luau-dev-playground:v2',JSON.stringify({files:{'main.luau':'print(43)','lib/Math.luau':'return {x=1}'},active:'main.luau',name:'Older'}));
 const w=new Workspace({storage});assert.equal(w.project.name,'Older');assert.equal(w.project.files['main.luau'],'print(43)');
 w.open('lib/Math.luau');w.source('return {x=2}');assert.equal(w.flush(),true);
 const restored=new Workspace({storage});assert.equal(restored.project.files['lib/Math.luau'],'return {x=2}');
 w.dispose();restored.dispose();
});
test('v1 file creation deletion and recovery snapshots',()=>{
 const storage=makeStorage();const w=new Workspace({storage});
 w.create('lib/A.luau','return {}');w.snapshot();w.rename('lib/A.luau','lib/B.luau');
 assert.equal(Object.hasOwn(w.project.files,'lib/B.luau'),true);
 const snap=w.snapshots()[0];w.restore(snap.id);assert.equal(Object.hasOwn(w.project.files,'lib/A.luau'),true);
 w.dispose();
});
test('v1 test file detection includes conventional spec names',()=>{
 const p={files:{'main.luau':'','tests/foo.luau':'','examples/Bench.test.luau':'','lib/Util.spec.lua':'','lib/Other.luau':''}};
 assert.deepEqual(findProjectTests(p),['examples/Bench.test.luau','lib/Util.spec.lua','tests/foo.luau']);
 assert.equal(classifyScript('modules/Test.luau'),'module');
});
