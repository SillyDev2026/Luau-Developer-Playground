export const V15_KEY = 'luauforge:v15:toolbox';
export function readV15(storage) {
  let data = {};
  try { data = JSON.parse(storage.getItem(V15_KEY) || '{}') || {}; } catch { /* recovery */ }
  if (!data || typeof data !== 'object' || Array.isArray(data)) data = {};
  const snippets = Object.fromEntries(Object.entries(data.snippets || {}).filter(([k,v]) => /^[A-Za-z]\w{0,39}$/.test(k) && typeof v === 'string' && v.length <= 8000).slice(0,40));
  const library = Object.fromEntries(Object.entries(data.library || {}).filter(([k,v]) => /^[A-Za-z_]\w{0,39}$/.test(k) && typeof v === 'string' && v.length <= 100000).slice(0,15));
  const history = Array.isArray(data.history) ? data.history.filter(x => x && Number.isFinite(x.medianNs) && typeof x.label === 'string').slice(-50) : [];
  return { snippets, library, history, focus: Boolean(data.focus) };
}
export function saveV15(storage, data) {
  try { storage.setItem(V15_KEY, JSON.stringify(data)); return true; } catch { return false; }
}
export function registerSnippet(state, trigger, code) {
  if (!/^[A-Za-z]\w{0,39}$/.test(trigger) || typeof code !== 'string' || !code.trim() || code.length > 8000) throw new Error('Use a valid shortcut and 1–8,000 characters of source.');
  if (Object.keys(state.snippets).length >= 40 && !Object.hasOwn(state.snippets, trigger)) throw new Error('Snippet limit reached (40).');
  state.snippets[trigger] = code;
}
export function registerShelfModule(state, name, code) {
  if (!/^[A-Za-z_]\w{0,39}$/.test(name) || typeof code !== 'string' || code.length > 100000 || !/\breturn\b/.test(code)) throw new Error('Choose a module name and valid Luau source returning a value (max 100 KB).');
  if (Object.keys(state.library).length >= 15 && !Object.hasOwn(state.library, name)) throw new Error('Custom shelf limit reached (15).');
  state.library[name] = code;
}
