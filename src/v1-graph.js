import { bundleProject } from './module-bundle.js';

// Build a dependency graph using the same resolver as the execution worker;
// never claim a module was imported if the WASM runner would reject that path.
export function analyzeDependencies(files) {
  const nodes = Object.keys(files).sort();
  const edges = new Map(), problems = [];
  for (const name of nodes) {
    try {
      const result = bundleProject({ active: name, files });
      edges.set(name, result.dependencies.filter(x => x.from === name).map(x => x.to));
    } catch (error) {
      edges.set(name, []);
      problems.push({ file: name, message: error.message });
    }
  }
  const cycles = [], seen = new Set(), active = new Set(), stack = [];
  function visit(name) {
    if (active.has(name)) {
      const pos = stack.indexOf(name);
      if (pos >= 0) cycles.push([...stack.slice(pos), name]);
      return;
    }
    if (seen.has(name)) return;
    seen.add(name); active.add(name); stack.push(name);
    for (const target of edges.get(name) || []) visit(target);
    stack.pop(); active.delete(name);
  }
  nodes.forEach(visit);
  return { nodes, edges, cycles, problems };
}
