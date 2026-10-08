import test from 'node:test';
import assert from 'node:assert/strict';
import { bundleProject, resolveModule, extractRequireTimings, summarizeSamples, REQUIRE_METRIC_MARKER } from '../src/module-bundle.js';
const project = (files, active='main.luau') => ({ files, active });
test('relative requires resolve nested folders and explicit extensions', () => {
  const files = { 'main.luau':'', 'src/modules/Math.lua':'return {}', 'src/lib/init.luau':'return {}' };
  assert.equal(resolveModule('src/main.luau', './modules/Math', files), 'src/modules/Math.lua');
  assert.equal(resolveModule('src/main.luau', './lib', files), 'src/lib/init.luau');
  assert.equal(resolveModule('src/tests/unit.luau','../modules/Math.lua',files),'src/modules/Math.lua');
});
test('missing or escaping workspace imports fail before runtime', () => {
  assert.throws(() => resolveModule('main.luau','../secret',{}),/escapes the workspace/);
  assert.throws(() => resolveModule('main.luau','@private',{}),/Unsupported/);
  assert.throws(() => resolveModule('main.luau','./missing',{}),/Module not found/);
  assert.throws(() => resolveModule('main.luau','./same',{'same.luau':'','same.lua':''}),/Ambiguous/);
});
test('flat VM keys preserve nested chains and cache identity', () => {
  const files = {
    'src/main.luau':'local a = require("./modules/A"); local b = require("./modules/A"); print(a == b)',
    'src/modules/A.luau':'local b = require("../common/B.luau"); return b',
    'src/common/B.luau':'return {value=42}',
  };
  const bundle=bundleProject(project(files,'src/main.luau'),{instrument:true});
  assert.equal(Object.keys(bundle.modules).length,2);
  assert.equal(bundle.dependencies.length,3);
  assert.match(bundle.code,/__lf_require_timed/);
  assert.ok(!bundle.code.includes('require("./modules/A")'));
  assert.ok(Object.keys(bundle.modules).every(key=>/^__lf_m\d+\.luau$/.test(key)));
});
test('comment and string contents do not produce module requirements', () => {
  const input='-- require("./missing")\nlocal s = "require(\\"./missing\\")"\n--[[ require("./missing") ]]\nprint(s)';
  assert.equal(bundleProject(project({'main.luau':input})).dependencies.length,0);
});
test('unrelated broken modules do not block main script execution', () => {
  const bundle=bundleProject(project({'main.luau':'print("good")','unused.luau':'return require("./missing")'}));
  assert.deepEqual(Object.keys(bundle.modules),[]);
});
test('instrumented module timings are extracted without leaking internal console output', () => {
  const result=extractRequireTimings({success:true,output:`${REQUIRE_METRIC_MARKER}\tlib/Math.luau\t0.0005\n42`,prints:[[{value:REQUIRE_METRIC_MARKER},{value:'lib/Math.luau'},{value:0.0005}],[{value:42}]]});
  assert.deepEqual(result.requireTimings,[{module:'lib/Math.luau',milliseconds:0.5}]);
  assert.equal(result.output,'42');
  assert.equal(result.prints.length,1);
});
test('median is computed from actual numerical samples', () => {
  assert.deepEqual(summarizeSamples([4,1,3,2]), {samples:4,medianMs:2.5,minMs:1,maxMs:4});
  assert.equal(summarizeSamples([]).medianMs,null);
});
test('module panel and benchmark action are connected', async () => {
  const { readFile } = await import('node:fs/promises');
  const html=await readFile(new URL('../index.html',import.meta.url),'utf8');
  const js=await readFile(new URL('../src/main.js',import.meta.url),'utf8');
  assert.match(html,/id="benchmark-module-btn"/);
  assert.match(html,/id="benchmark-module"/);
  assert.match(js,/benchmarkModule\(/);
  assert.match(js,/renderBenchmarkModules\(/);
});
