import test from 'node:test';
import assert from 'node:assert/strict';
import { maskLuau, localsInScope, completionContext, staticCompletions, applyCompletion, mergeCompletions } from '../src/intellisense.js';
import { CORE_API } from '../src/roblox-api.js';
import { compactRobloxAPI } from '../scripts/fetch-roblox-api.mjs';
const suggest=(text,api=CORE_API)=>staticCompletions(text,text.length,api)?.items||[];
const has=(items,name)=>items.some(x=>x.label===name);

test('typing t suggests in-scope local test and testSpeed',()=>{
 const items=suggest('local test = x\nlocal testSpeed = 25\nt');
 assert.ok(has(items,'test'));assert.ok(has(items,'testSpeed'));
 assert.equal(items[0].label,'test');
});
test('local variable declared after the cursor is not visible',()=>{
 const s='t\nlocal test = 123';
 assert.equal(has(staticCompletions(s,1,CORE_API)?.items||[],'test'),false);
});
test('function params and block locals do not leak past end',()=>{
 const code='local function calculate(number: number)\n  local scoped = 5\n  return number + scoped\nend\ns';
 assert.ok(!has(suggest(code),'scoped'));
 assert.ok(!has(suggest(code),'number'));
 const inside='local function calculate(number: number)\n  local scoped = 5\n  s';
 assert.ok(has(suggest(inside),'scoped'));
 assert.ok(localsInScope(inside,inside.length).some(x=>x.name==='number'));
});
test('shadowing resolves the innermost type',()=>{
 const src='local v: string = "hi"\ndo\n  local v: Part = Instance.new("Part")\n  v.P';
 const items=suggest(src);
 assert.ok(has(items,'Position'));
 assert.equal(localsInScope(src,src.length).filter(x=>x.name==='v')[0].type,'Part');
});
test('comments and strings do not generate phantom symbols',()=>{
 assert.ok(!has(suggest('-- local secret = 4\ns'),'secret'));
 assert.ok(!has(suggest('local msg = "local fake = 1"\nf'),'fake'));
 assert.equal(completionContext('print("abc")',11),null);
 assert.equal(maskLuau('local test = "a" -- comment').length,'local test = "a" -- comment'.length);
});
test('type annotation completion suggests engine type names',()=>{
 const items=suggest('local target: Pa');
 assert.ok(has(items,'Part'));
});
test('Instance.new and GetService infer Roblox class types',()=>{
 assert.ok(has(suggest('local block = Instance.new("Part")\nblock.P'),'Position'));
 assert.ok(has(suggest('local players = game:GetService("Players")\nplayers.Get'),'GetPlayers'));
});
test('typed locals see inherited members from the API dump',()=>{
 const mock={classes:{Part:{parent:'BasePart',members:[['Position','property','Position: Vector3','Vector3']]},BasePart:{parent:'Instance',members:[]},Instance:{parent:'<<<ROOT>>>',members:[['Destroy','function','Destroy(): ()','nil']]}},types:['Part'],enums:{}};
 assert.ok(has(suggest('local part: Part\npart.D',mock),'Destroy'));
});
test('table literal fields are suggested without inventing new fields',()=>{
 const items=suggest('local settings = { speed = 2, multiplier = 3 }\nsettings.sp');
 assert.ok(has(items,'speed'));assert.ok(!has(items,'random'));
});
test('enums suggest their types and items',()=>{
 assert.ok(has(suggest('Enum.Mat'),'Material'));
 assert.ok(has(suggest('Enum.Material.N'),'Neon'));
});
test('standard math APIs include call snippets and parameters',()=>{
 const completion=staticCompletions('math.sq',7,CORE_API);
 assert.ok(has(completion.items,'sqrt'));
 const result=applyCompletion('math.sq',completion,completion.items.find(x=>x.label==='sqrt'));
 assert.equal(result.source,'math.sqrt()');
 assert.equal(result.cursor,'math.sqrt('.length);
});
test('native WASM completions merge without losing local suggestions',()=>{
 const local=staticCompletions('local test = 3\nte',17,CORE_API);
 const merged=mergeCompletions(local,[{label:'test',detail:'number',kind:'variable'},{label:'template',detail:'type alias',kind:'type'}]);
 assert.ok(has(merged.items,'test'));assert.ok(has(merged.items,'template'));
 assert.equal(merged.items.filter(x=>x.label==='test').length,1);
});
test('Roblox API dump compaction preserves signatures, types, security and enums',()=>{
 const compiled=compactRobloxAPI({Version:1,Classes:[{Name:'Test',Superclass:'Instance',Members:[{Name:'Move',MemberType:'Function',Parameters:[{Name:'where',Type:{Name:'Vector3'}}],ReturnType:{Name:'boolean'},Security:'None'}, {Name:'Private',MemberType:'Property',ValueType:{Name:'string'},Security:{Read:'RobloxSecurity',Write:'RobloxSecurity'}}]}],Enums:[{Name:'Mode',Items:[{Name:'A'}]}]});
 assert.equal(compiled.classes.Test.members[0][2],'Move(where: Vector3): boolean');
 assert.equal(compiled.classes.Test.members.length,1);
 assert.deepEqual(compiled.enums.Mode,['A']);
});


test('long strings and long comments never leak fake local symbols or slash imports',()=>{
 const code='local visible = 1\nlocal source = [=[\nlocal phantom = 10\n-- fake comment\n]=]\n--[==[\nlocal hidden = 2\n]==]\nvi';
 const clean=maskLuau(code);
 assert.equal(clean.length,code.length);
 assert.equal(clean.split('\n').length,code.split('\n').length);
 assert.ok(has(suggest(code),'visible'));
 assert.ok(!has(suggest(code),'phantom'));
 assert.ok(!has(suggest(code),'hidden'));
 assert.equal(completionContext('local s = [=[\n/Math\n]=]',17),null);
});


test('Luau function parameter and return annotations offer types, never tonumber',()=>{
  for(const code of [
    'function Math.add(a: nu',
    'function Math.add(a: number, b: nu',
    'function Math.add(a: number, b: number): nu',
    'local function calc(a: number): nu',
    'type Callback = (value: nu',
    'local result: nu',
    'local result = value :: nu'
  ]){
    const context=completionContext(code,code.length);
    assert.equal(context?.mode,'type',code);
    const items=suggest(code);
    assert.ok(has(items,'number'),code);
    assert.ok(!has(items,'tonumber'),code);
    const merged=mergeCompletions({ ...context,items },[{label:'tonumber',kind:'function',detail:'WASM value global'}]);
    assert.ok(!has(merged.items,'tonumber'),code);
  }
  assert.equal(completionContext('local count = tonumber', 'local count = tonumber'.length)?.mode,'identifier');
  assert.equal(staticCompletions('function Math.add(a: number','function Math.add(a: number'.length,CORE_API),null);
});
