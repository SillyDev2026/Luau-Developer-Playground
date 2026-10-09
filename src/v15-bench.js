// A batched os.clock benchmark executes inside the actual Luau WASM VM.
// JavaScript measures neither per-op time nor layout/console rendering.
export function makeBenchSource({ setup = '', expression = 'math.sqrt(i)', iterations = 100000, warmup = 10000, samples = 10 } = {}) {
  if (!Number.isInteger(iterations) || iterations < 100 || iterations > 2_000_000) throw new Error('Iterations must be 100–2,000,000.');
  if (!Number.isInteger(warmup) || warmup < 0 || warmup > 100000) throw new Error('Warmups must be 0–100,000.');
  if (!Number.isInteger(samples) || samples < 2 || samples > 25) throw new Error('Samples must be 2–25.');
  if (typeof setup !== 'string' || setup.length > 25000 || typeof expression !== 'string' || expression.length > 3000 || /\n|\r/.test(expression)) throw new Error('Invalid benchmark source.');
  return `--!nonstrict\n${setup}\nlocal I = ${iterations}\nlocal W = ${warmup}\nlocal N = ${samples}\nlocal sink = nil\nfor i = 1, W do sink = (${expression}) end\nlocal measured = table.create(N)\nfor trial = 1, N do\n    local before = os.clock()\n    for i = 1, I do sink = (${expression}) end\n    measured[trial] = (os.clock() - before) * 1e9 / I\nend\ntable.sort(measured)\nlocal sum = 0\nfor _, n in measured do sum += n end\nlocal median = measured[math.ceil(N / 2)]\nlocal p95 = measured[math.ceil(N * 0.95)]\nprint('LUAFORGE_BENCH', I, N, measured[1], median, p95, measured[N], sum / N)\n`;
}
export function parseBenchResult(output) {
  const line = String(output).split('\n').find(x => x.includes('LUAFORGE_BENCH'));
  if (!line) throw new Error('No benchmark data returned; check the Luau output.');
  const tail = line.slice(line.indexOf('LUAFORGE_BENCH') + 15).trim();
  const numbers = tail.split(/\s+/).map(Number);
  if (numbers.length < 7 || numbers.some(x => !Number.isFinite(x))) throw new Error('Invalid benchmark numeric result.');
  const [iterations, samples, minNs, medianNs, p95Ns, maxNs, meanNs] = numbers;
  return { iterations, samples, minNs, medianNs, p95Ns, maxNs, meanNs, opsPerSecond: medianNs > 0 ? 1e9 / medianNs : null, runtime: 'Luau WASM os.clock; batched timing' };
}
export function formatBenchmarkCsv(rows) {
  const keys = ['timestamp', 'label', 'iterations', 'samples', 'minNs', 'medianNs', 'p95Ns', 'maxNs', 'meanNs', 'opsPerSecond'];
  const escape = value => `"${String(value ?? '').replaceAll('"', '""')}"`;
  return [keys.join(','), ...rows.map(row => keys.map(key => escape(row[key])).join(','))].join('\r\n') + '\r\n';
}
export function compareBenchmarks(a, b) {
  if (!(a.medianNs > 0 && b.medianNs > 0)) return null;
  return { ratio: a.medianNs / b.medianNs, faster: a.medianNs < b.medianNs ? 'first' : a.medianNs > b.medianNs ? 'second' : 'tie' };
}
