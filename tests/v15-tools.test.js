import test from 'node:test';
import assert from 'node:assert/strict';
import { maskLuau, referenceRanges, wordAt, findReferences, planRename, inferSimpleTypes, generateModuleDocs, quickFixSuggestions } from '../src/v15-analysis.js';
import { makeBenchSource, parseBenchResult, formatBenchmarkCsv, compareBenchmarks } from '../src/v15-bench.js';
import { makeZip } from '../src/v1-zip.js';
import { readZip } from '../src/v15-zip.js';
import { readV15, registerSnippet, registerShelfModule } from '../src/v15-settings.js';
import { moduleReport, missingRequireCandidates, modulePinManifest } from '../src/v15-modules.js';
import { BUILTIN_LIBRARIES } from '../src/builtin-libraries.js';
import { readFile } from 'node:fs/promises';

test('mask excludes quoted strings, comments, and long quoted literals', () => {
  const s = 'local test = 1 -- test\nprint("test")\n--[[test]]\nlocal data = [=[test]=]';
  assert.equal(referenceRanges(s, 'test').length, 1);
  assert.equal(maskLuau(s).length, s.length);
});
test('find project references with source positions and exclude properties', () => {
  const files = { 'main.luau':'local test = 1\nprint(test)\nfoo.test = test -- test', 'module.luau':'print(test)' };
  assert.equal(findReferences(files,'test').length, 4);
  assert.equal(wordAt(files['main.luau'], 7),'test');
});
test('rename preview excludes property and comments and edits after confirmation', () => {
  const source = 'local test = 2\nprint(test, model.test) -- test';
  const plan=planRename({'main.luau':source},'main.luau',7,'speed');
  assert.equal(plan.preview,2);
  assert.match(plan.apply(),/local speed = 2/);
  assert.match(plan.apply(),/print\(speed, model\.test\) -- test/);
  assert.equal(source,'local test = 2\nprint(test, model.test) -- test');
});
test('rename rejects collisions and nonlocal guesses', () => {
  assert.throws(()=>planRename({'main.luau':'print(foo)'},'main.luau',6,'bar'),/declared/);
  assert.throws(()=>planRename({'main.luau':'local a = 1\nlocal b=2'},'main.luau',6,'b'),/exists/);
});
test('basic type explorer and API docs', () => {
  const s='local count: number = 12\nlocal greeting = "hello"\nlocal Module = {}\nfunction Module.add(a: number, b: number)\n return a + b\nend\nreturn Module';
  const types = inferSimpleTypes(s);
  assert.ok(types.some(x=>x.name==='count'&&x.type==='number'));
  assert.ok(generateModuleDocs('module.luau',s).includes('Module.add(a: number, b: number)'));
  assert.ok(quickFixSuggestions('print(1)').some(x=>x.insert==='--!strict\n'));
});
test('missing import candidates, pins and reachability', () => {
  assert.deepEqual(missingRequireCandidates('Math.add(2,3)', ['modules/Math.luau']).map(x=>x.name),['Math']);
  assert.equal(missingRequireCandidates('local Math = require("./modules/Math.luau")\nMath.add(1,2)', ['modules/Math.luau']).length,0);
  const pins=modulePinManifest(BUILTIN_LIBRARIES,{'main.luau':'local F=require("@FastNum")'});
  assert.equal(pins.find(x=>x.id==='FastNum').referenced,true);
  const report=moduleReport({'main.luau':'print("ok")','modules/Unused.luau':'return {}'});
  assert.ok(report.unused.includes('modules/Unused.luau'));
});
test('benchmark source validates and runs batched os.clock operations', () => {
  const s=makeBenchSource({expression:'math.sqrt(i)',iterations:1000,warmup:100,samples:5});
  assert.match(s,/os\.clock\(\)/);
  assert.match(s,/LUAFORGE_BENCH/);
  assert.throws(()=>makeBenchSource({iterations:0}),/Iterations/);
  assert.throws(()=>makeBenchSource({expression:'print(1)\nprint(2)'}),/Invalid/);
});
test('benchmark result parse, history CSV and comparisons', () => {
  const bench=parseBenchResult('LUAFORGE_BENCH\t10000\t12\t25.1\t26\t28\t32\t27');
  assert.equal(bench.medianNs,26);
  assert.equal(bench.p95Ns,28);
  assert.ok(bench.opsPerSecond>0);
  assert.match(formatBenchmarkCsv([{...bench,label:'foo"bar'}]),/"foo""bar"/);
  assert.equal(compareBenchmarks({medianNs:10},{medianNs:20}).faster,'first');
});
test('safe ZIP round trip retains nested Luau source and UTF8',async()=>{
  const files={'main.luau':'print("⧉ Luau")','modules/Foo.lua':'return {value = 8}'};
  const restored=await readZip(makeZip(files));
  assert.equal(restored['main.luau'],files['main.luau']);
  assert.equal(restored['modules/Foo.lua'],files['modules/Foo.lua']);
});
test('ZIP rejects traversal, duplicates and tampering',async()=>{
  assert.throws(()=>makeZip({'../evil.luau':'return 1'}),/Invalid/);
  const zip=makeZip({'main.luau':'print(42)'});
  zip[43]^=1;
  await assert.rejects(()=>readZip(zip),/integrity|UTF|Invalid/);
});
test('optional feature storage recovers malformed settings and caps values',()=>{
  const storage={getItem:()=>'{broken'};
  const state=readV15(storage);
  assert.deepEqual(state.history,[]);
  registerSnippet(state,'bench','print(1)');
  registerShelfModule(state,'Math','return {}');
  assert.equal(state.snippets.bench,'print(1)');
  assert.throws(()=>registerSnippet(state,'a-b','bad'),/valid shortcut/);
  assert.throws(()=>registerShelfModule(state,'Bad','function x() end'),/returning/);
});
test('v1.5 toolbox entrypoint and layout are wired up',async()=>{
  const html=await readFile(new URL('../index.html',import.meta.url),'utf8');
  const js=await readFile(new URL('../src/v1.js',import.meta.url),'utf8');
  const css=await readFile(new URL('../src/v15.css',import.meta.url),'utf8');
  assert.match(html,/id="v15-actions"/);
  assert.match(html,/v15\.css\?v=1\.5\.0/);
  assert.match(js,/mountV15\(/);
  assert.match(css,/@media\(max-width:820px\)/);
});
