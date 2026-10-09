import test from 'node:test';
import assert from 'node:assert/strict';
import { analyzeDependencies } from '../src/v1-graph.js';
test('graph shows imported files and detects unresolved require',()=>{
 const files={'main.luau':'local A = require("./modules/A.luau")','modules/A.luau':'return {ok = true}'};
 const r=analyzeDependencies(files);assert.deepEqual(r.edges.get('main.luau'),['modules/A.luau']);
 assert.equal(r.problems.length,0);
 files['modules/A.luau']='return require("./missing.luau")';
 assert.ok(analyzeDependencies(files).problems.length>0);
});
test('graph detects dependency cycles',()=>{
 const files={'main.luau':'return require("./lib/a.luau")','lib/a.luau':'return require("./b.luau")','lib/b.luau':'return require("./a.luau")'};
 assert.ok(analyzeDependencies(files).cycles.some(c=>c.length>=3));
});
