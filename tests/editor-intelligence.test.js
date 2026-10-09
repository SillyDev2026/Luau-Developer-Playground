import test from 'node:test';
import assert from 'node:assert/strict';
import { argumentContext, signatureFor, formatSignature, outlineSymbols, definitionAt } from '../src/editor-intelligence.js';
import { CORE_API } from '../src/roblox-api.js';

test('nested calls count only top-level arguments', () => {
  const source = 'print(math.max(1, 2), {x=5, y=6}, "a,b", value)';
  const at=source.indexOf('value')+2;
  const context=argumentContext(source,at);
  assert.equal(context.name,'print');
  assert.equal(context.activeParameter,3);
  assert.equal(argumentContext(source,source.indexOf('2')+1).name,'math.max');
});

test('comments and quoted commas or parentheses do not change active parameters', () => {
  const source='math.max(1, "a,(b,c)", 3';
  assert.equal(argumentContext(source,source.length).activeParameter,2);
  assert.equal(argumentContext('local x = "math.max(1"',25),null);
  assert.equal(argumentContext('local function foo(a, b',23),null);
});

test('signature hint for native calls, Roblox APIs and inferred services', () => {
  const first=signatureFor('local n = math.sqrt(',20,CORE_API);
  assert.ok(first?.signature?.includes('sqrt(x: number)'));
  const service='local players = game:GetService("Players")\nplayers:GetPlayers(';
  assert.match(signatureFor(service,service.length,CORE_API).signature,/GetPlayers\(/);
  const nested='local part = Instance.new("Part")\npart:IsA(';
  assert.match(signatureFor(nested,nested.length,CORE_API).signature,/IsA\(/);
});

test('local function signatures and active argument highlight', () => {
  const code='local function calc(a: number, b: string): boolean\n  return true\nend\ncalc(1, ';
  const hint=signatureFor(code,code.length,CORE_API);
  assert.match(hint.signature,/calc\(a: number, b: string\)/);
  assert.equal(hint.activeParameter,1);
  const format=formatSignature(hint.signature,hint.activeParameter);
  assert.equal(format.active,'b: string');
  assert.match(format.before,/a: number,/);
});

test('file outline lists actual declarations, not comments or strings', () => {
  const src='-- local fake = 1\nlocal test = 3\nlocal function run(x)\nend\ntype Shape = {size: number}\n';
  assert.deepEqual(outlineSymbols(src).map(x=>x.name),['test','run','Shape']);
});

test('F12 local definition navigates before cursor and skips future declarations', () => {
  const code='local test = 42\nprint(test)\nlocal later = 1';
  const pos=code.indexOf('test',code.indexOf('print'))+2;
  assert.equal(definitionAt(code,pos).line,1);
  assert.equal(definitionAt(code,code.indexOf('later',code.indexOf('print'))),null);
});

test('formatSignature does not split table/generic type parameters',()=>{
  const s='create(map: {[string]: number}, cb: (number, string) -> boolean, enabled: boolean): ()';
  assert.equal(formatSignature(s,1).active,'cb: (number, string) -> boolean');
});
