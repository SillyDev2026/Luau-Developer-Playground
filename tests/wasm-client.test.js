import test from 'node:test';
import assert from 'node:assert/strict';
import { LuauRuntime, normalizeDiagnostics, renderOutput } from '../src/wasm-client.js';

class FakeWorker {
  terminated = false;
  postMessage(message) {
    this.messages.push(message);
    if (message.type === 'init') queueMicrotask(() => this.onmessage({ data: { id: message.id, type: 'init', result: { ready: true } } }));
    else if (message.type === 'execute') queueMicrotask(() => this.onmessage({ data: { id: message.id, type: 'execute', result: { success: true, output: 'ok' }, elapsed: 12 } }));
    else if (message.type === 'diagnostics') queueMicrotask(() => this.onmessage({ data: { id: message.id, type: 'diagnostics', result: { diagnostics: [] }, elapsed: 2 } }));
  }
  constructor() { this.messages = []; }
  terminate() { this.terminated = true; }
}
const project = { active: 'main.luau', files: { 'main.luau': 'print("ok")' }, mode: 'strict', optimization: 1 };
test('run invokes wasm worker and captures output', async () => {
  const runtime = new LuauRuntime({ workerFactory: () => new FakeWorker() });
  const { result } = await runtime.run(project);
  assert.equal(result.output, 'ok');
  assert.equal(runtime.executing, false);
  runtime.dispose();
});
test('analysis worker survives execution stop', async () => {
  const runtime = new LuauRuntime({ workerFactory: () => new FakeWorker() });
  await runtime.diagnostics(project);
  const original = runtime.analysis;
  await runtime.run(project);
  runtime.stop();
  assert.equal(runtime.execution, null);
  assert.equal(runtime.analysis, original);
  runtime.dispose();
});
test('stop rejects a hung execution and future runs remain possible', async () => {
  class HungWorker extends FakeWorker { postMessage(message) { if (message.type === 'execute') this.messages.push(message); else super.postMessage(message); } }
  const runtime = new LuauRuntime({ workerFactory: () => new HungWorker() });
  const promise = runtime.run(project);
  await new Promise(resolve => setTimeout(resolve, 5));
  runtime.stop();
  await assert.rejects(promise, /stopped/);
  assert.equal(runtime.executing, false);
  runtime.dispose();
});
test('diagnostics are normalized to 1-indexed lines', () => {
  assert.deepEqual(normalizeDiagnostics([{ severity:'error', message:'bad', startLine:2, startCol:4, moduleName:'main' }])[0], { message:'bad', severity:'error', line:3, column:5, module:'main' });
});
test('output renders native Luau text and fallback structured values', () => {
  assert.equal(renderOutput({ output: 'hello\n' }), 'hello\n');
  assert.equal(renderOutput({ prints: [[5, 'ok']] }), '5\tok');
});
test('runtime worker targets local same-origin asset URLs', async () => {
  const { readFile } = await import('node:fs/promises');
  const source = await readFile(new URL('../src/wasm-worker.js', import.meta.url), 'utf8');
  assert.match(source, /new URL\('\.\.\/wasm\/'/);
  assert.match(source, /new URL\('\.\.\/public\/wasm\/'/);
  assert.doesNotMatch(source, /play\.luau\.org/);
});


test('missing published asset yields an actionable GitHub Pages error', async () => {
  const { readFile } = await import('node:fs/promises');
  const source = await readFile(new URL('../src/wasm-worker.js', import.meta.url), 'utf8');
  assert.match(source, /GitHub Pages deployment/);
  assert.match(source, /res\.ok/);
  assert.match(source, /fetchAsset\(loaderUrl/);
});

test('worker initialization errors can be retried with a fresh worker', async () => {
  let created = 0;
  class RecoveringWorker extends FakeWorker {
    constructor() { super(); created++; }
    postMessage(message) {
      if (created === 1 && message.type === 'init') queueMicrotask(() => this.onmessage({ data: { id: message.id, type: 'error', error: 'Luau loader missing' } }));
      else super.postMessage(message);
    }
  }
  const runtime = new LuauRuntime({ workerFactory: () => new RecoveringWorker() });
  await assert.rejects(runtime.run(project), /Luau loader missing/);
  // The user can retry after resetting the failing worker.
  runtime.stop();
  const { result } = await runtime.run(project);
  assert.equal(result.output, 'ok');
  runtime.dispose();
});

test('a stopped run cannot clear the running flag of the next run', async () => {
  const runtime = new LuauRuntime({ workerFactory: () => new FakeWorker() });
  const stopped = runtime.run(project);
  runtime.stop();
  await assert.rejects(stopped, /stopped/);
  const { result } = await runtime.run(project);
  assert.equal(result.output, 'ok');
  runtime.dispose();
});
