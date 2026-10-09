import { analyzeDependencies } from './v1-graph.js';
import { maskLuau } from './v15-analysis.js';

export function moduleReport(files) {
  const graph = analyzeDependencies(files);
  const incoming = new Map(graph.nodes.map(n => [n, []]));
  for (const [from, targets] of graph.edges) for (const to of targets) incoming.get(to)?.push(from);
  const unused = [], roots = [];
  for (const name of graph.nodes) {
    const requestedBy = incoming.get(name) || [];
    if (!requestedBy.length) {
      if (/^(?:modules|lib|packages)\//i.test(name)) unused.push(name);
      else roots.push(name);
    }
  }
  // This is reachability guidance, not proof of dead code (dynamic imports exist).
  return { ...graph, incoming, unused, roots, count: graph.nodes.length };
}
export function missingRequireCandidates(source, names) {
  const masked = maskLuau(source);
  const candidates = [];
  for (const name of names) {
    const simple = name.split('/').at(-1).replace(/\.lua(u)?$/i, '');
    if (!/^[A-Za-z_]\w*$/.test(simple)) continue;
    if (!new RegExp(`\\b${simple}\\s*[.:]`).test(masked)) continue;
    if (new RegExp(`\\blocal\\s+${simple}\\s*=`).test(masked)) continue;
    candidates.push({ name: simple, path: name });
  }
  return candidates;
}
export function modulePinManifest(catalog, files) {
  const body = Object.values(files).join('\n');
  return catalog.map(lib => ({ id: lib.id, version: lib.version, pinned: true, referenced: body.includes(`@${lib.id}`), repository: lib.repository }));
}
