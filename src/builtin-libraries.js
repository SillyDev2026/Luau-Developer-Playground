// Official user-owned releases bundled into LuauForge's virtual (not saved) workspace.
// No GitHub credentials and no runtime calls to raw.githubusercontent.com.
export const BUILTIN_PATH_PREFIX = '__luauforge_builtin__/';
export const BUILTIN_LIBRARIES = Object.freeze([
  Object.freeze({
    id: 'FastNum', label: 'FastNum / FastME', version: '2.9.5', file: 'FastNum.lua',
    repository: 'https://github.com/SillyDev2026/FastNum',
    description: 'Fast mantissa/exponent big-number math, compact formatting and storage codecs.',
    local: 'FastME', categories: [
      { name: 'Construct', methods: ['new(mantissa, exponent)', 'fromNumber(value)', 'fromString(text)', 'fromFormattedString(text)', 'fromStringInto(out, text)'] },
      { name: 'Arithmetic', methods: ['add(a, b)', 'sub(a, b)', 'mul(a, b)', 'div(a, b)', 'pow(a, b)', 'sqrt(a)', 'scale10(a, exponent)'] },
      { name: 'Formatting', methods: ['toString(value)', 'toSuffix(value)', 'format(value)'] },
      { name: 'Persistence', methods: ['serialize(value)', 'deserialize(text)', 'lbencode(value)', 'lbdecode(value)'] },
    ],
    example: `--!strict\n-- FastNum v2.9.5 (returns the FastME API table).\nlocal FastME = require("@FastNum")\nlocal balance = FastME.fromString("1e100")\nlocal reward = FastME.fromNumber(2500)\nlocal total = FastME.add(balance, reward)\nprint("FastNum version:", FastME.VERSION)\nprint("Balance:", FastME.toString(total))\nprint("Scientific:", FastME.toScientific(total))\n`,
  }),
  Object.freeze({
    id: 'NanoNum', label: 'NanoNum', version: '2.4.10', file: 'NanoNum.lua',
    repository: 'https://github.com/SillyDev2026/NanoNum',
    description: 'Buffer-based huge-number representation, math, serialization and formatting.',
    local: 'NanoNum', categories: [
      { name: 'Construct', methods: ['fromNumber(value)', 'fromString(text)', 'fromLog10(exponent)', 'fromLayer(layer, top)', 'compile(value)'] },
      { name: 'Arithmetic', methods: ['add(a, b)', 'sub(a, b)', 'mul(a, b)', 'div(a, b)', 'pow(a, b)', 'log10(a)'] },
      { name: 'Formatting', methods: ['format(value)', 'formatScientific(value)', 'toNumber(value)', 'inspect(value)'] },
      { name: 'Exact & storage', methods: ['fromStringExact(text)', 'addExact(a, b)', 'formatExact(value)', 'encode(value)', 'decode(value)'] },
    ],
    example: `--!strict\n-- NanoNum uses Luau buffers (available in the WASM VM).\nlocal NanoNum = require("@NanoNum")\nlocal base = NanoNum.fromString("1e1000")\nlocal gain = NanoNum.fromNumber(250)\nlocal total = NanoNum.add(base, gain)\nprint("NanoNum version:", NanoNum.engineInfo().Version)\nprint("Scientific:", NanoNum.formatScientific(total))\nprint("Bytes:", NanoNum.byteLength(total))\n`,
  }),
  Object.freeze({
    id: 'OmegaNum', label: 'OmegaNum', version: '2.4.0', file: 'OmegaNum.lua',
    repository: 'https://github.com/SillyDev2026/OmegaNumV2',
    description: 'Layered huge-number math and formatting with OmegaNum-compatible tables.',
    local: 'OmegaNum', categories: [
      { name: 'Construct', methods: ['fromNumber(value)', 'fromString(text)', 'toOmega(value)', 'correct(value)'] },
      { name: 'Arithmetic', methods: ['add(a, b)', 'sub(a, b)', 'mul(a, b)', 'div(a, b)', 'pow(a, b)', 'log10(a)'] },
      { name: 'Formatting', methods: ['toDisplay(value)', 'toString(value)', 'toNumber(value)'] },
      { name: 'Comparison', methods: ['cmp(a, b)', 'eq(a, b)', 'lt(a, b)', 'gte(a, b)'] },
    ],
    example: `--!strict\nlocal OmegaNum = require("@OmegaNum")\nlocal huge = OmegaNum.fromString("1e1000")\nlocal doubled = OmegaNum.mul(huge, 2)\nprint("OmegaNum version:", OmegaNum.VERSION)\nprint("Number:", OmegaNum.toDisplay(doubled))\nprint("Greater:", OmegaNum.gt(doubled, huge))\n`,
  }),
]);

export function builtinId(specifier) {
  return typeof specifier === 'string' && specifier[0] === '@' && BUILTIN_LIBRARIES.some(lib => lib.id === specifier.slice(1)) ? specifier.slice(1) : null;
}
export function builtinPath(id) { return `${BUILTIN_PATH_PREFIX}${id}.luau`; }
export function builtinById(id) { return BUILTIN_LIBRARIES.find(x => x.id === id) || null; }

// This compatibility adapter is applied to the *virtual* source only, never to
// the original module stored in public/libraries/ or the creator's repository.
// OmegaNum's current source uses HttpService only for JSONEncode(number-array).
export function adaptBuiltinSource(id, source) {
  if (id !== 'OmegaNum') return source;
  const original = 'local HttpService = game:GetService("HttpService")';
  if (!source.includes(original)) throw new Error('OmegaNum Roblox compatibility adapter needs updating; module source changed.');
  return source.replace(original, `local HttpService = { JSONEncode = function(_, values)
    local out = table.create(#values)
    for i = 1, #values do
        local value = values[i]
        if type(value) == "number" and value == value and math.abs(value) ~= math.huge then
            out[i] = tostring(value)
        elseif type(value) == "string" then
            out[i] = string.format("%q", value)
        else
            out[i] = "null"
        end
    end
    return "[" .. table.concat(out, ",") .. "]"
end }`);
}

// In the GitHub Actions deploy, public/libraries/* becomes /libraries/*.
// GitHub's optional branch Pages output preserves /public/libraries/*.
export async function fetchBuiltinSource(id, { fetchImpl = fetch, moduleUrl = import.meta.url } = {}) {
  const lib = builtinById(id);
  if (!lib) throw new Error(`Unknown built-in library: ${id}`);
  const roots = [new URL('../libraries/', moduleUrl), new URL('../public/libraries/', moduleUrl)];
  const problems = [];
  for (const root of roots) {
    const url = new URL(`${lib.file}?v=${encodeURIComponent(lib.version)}`, root);
    try {
      const response = await fetchImpl(url, { cache: 'force-cache' });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      if ((response.headers.get('content-type') || '').includes('text/html')) throw new Error('HTML instead of Luau source');
      const source = await response.text();
      if (source.length < 5000 || !source.includes('return ')) throw new Error('Incomplete or invalid Luau source');
      return adaptBuiltinSource(id, source);
    } catch (error) { problems.push(`${url.pathname}: ${error.message}`); }
  }
  throw new Error(`${lib.label} could not load. Check that public/libraries/${lib.file} is deployed. ${problems.join(' | ')}`);
}

// A preloaded cached source is shared between analysis, run and benchmark; it is
// NOT copied to the user's saved workspace (NanoNum alone exceeds its file cap).
const cachedSources = new Map();
export async function loadBuiltinsForProject(project, { fetchSource = fetchBuiltinSource } = {}) {
  const sourceText = Object.values(project.files).join('\n');
  const needed = BUILTIN_LIBRARIES.filter(lib => sourceText.includes(`"@${lib.id}"`) || sourceText.includes(`'@${lib.id}'`));
  if (!needed.length) return project;
  const sources = await Promise.all(needed.map(async lib => {
    if (!cachedSources.has(lib.id)) {
      const pending = Promise.resolve().then(() => fetchSource(lib.id));
      cachedSources.set(lib.id, pending);
      pending.catch(() => { if (cachedSources.get(lib.id) === pending) cachedSources.delete(lib.id); });
    }
    return [builtinPath(lib.id), await cachedSources.get(lib.id)];
  }));
  return { ...project, files: { ...project.files, ...Object.fromEntries(sources) } };
}

export function clearBuiltinCache() { cachedSources.clear(); }
