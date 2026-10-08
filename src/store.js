export const VERSION = 2;
export const STORAGE_KEY = 'luau-dev-playground:v2';
export const LEGACY_STORAGE_KEY = 'luau-dev-playground:v1';
export const FILE_LIMIT = 60;
export const FILE_SIZE_LIMIT = 200_000;
export const TOTAL_SIZE_LIMIT = 900_000;
export const DEFAULT_FILES = Object.freeze({
  'main.luau': `--!strict\n-- Welcome to LuauForge v0.3\n\nlocal function greet(name: string): string\n    return \`Hello, {name}!\`\nend\n\nprint(greet("Developer"))\n\nlocal sum = 0\nfor i = 1, 10 do\n    sum += i\nend\nprint("Sum:", sum)\n`,
  'examples/types.luau': `--!strict\ntype Point = { x: number, y: number }\n\nlocal function distance(point: Point): number\n    return math.sqrt(point.x ^ 2 + point.y ^ 2)\nend\n\nprint(distance({ x = 3, y = 4 }))\n`,
  'examples/benchmark.luau': `--!strict\n-- Browser execution timings differ from Roblox Studio.\nlocal iterations = 100000\nlocal startTime = os.clock()\nlocal total = 0\nfor i = 1, iterations do\n    total += i\nend\nprint("Total:", total)\nprint("Elapsed seconds:", os.clock() - startTime)\n`,
});

export function createDefaultProject() {
  return { version: VERSION, name: 'My Workspace', files: { ...DEFAULT_FILES }, active: 'main.luau', mode: 'strict', optimization: 1, theme: 'dark', wordWrap: false, sidebarOpen: true, inspectorOpen: true, fontSize: 13, sidebarWidth: 258, outputHeight: 202, updatedAt: Date.now() };
}

export function normalizePath(input) {
  const name = String(input ?? '').trim().replaceAll('\\', '/');
  if (!name || name.length > 140 || name.startsWith('/') || name.endsWith('/') || name.includes('//') || /[<>:"|?*\x00-\x1f]/.test(name)) throw new Error('Use a relative filename without invalid characters.');
  const segments = name.split('/');
  if (segments.some(part => !part || part === '.' || part === '..')) throw new Error('Paths cannot contain . or .. segments.');
  return /\.lua(u)?$/i.test(name) ? name : `${name}.luau`;
}

function boundedNumber(value, fallback, min, max) {
  return Number.isFinite(value) ? Math.max(min, Math.min(max, Math.round(value))) : fallback;
}

export function validateProject(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Invalid project data.');
  if (!value.files || typeof value.files !== 'object' || Array.isArray(value.files)) throw new Error('Missing project files.');
  const entries = Object.entries(value.files);
  if (!entries.length || entries.length > FILE_LIMIT) throw new Error(`Projects require 1–${FILE_LIMIT} files.`);
  const files = Object.create(null);
  let total = 0;
  for (const [rawName, source] of entries) {
    const name = normalizePath(rawName);
    if (name !== rawName || typeof source !== 'string') throw new Error(`Invalid source file: ${rawName}`);
    const bytes = new TextEncoder().encode(source).byteLength;
    if (bytes > FILE_SIZE_LIMIT) throw new Error(`${name} exceeds the ${formatBytes(FILE_SIZE_LIMIT)} limit.`);
    total += bytes;
    if (total > TOTAL_SIZE_LIMIT) throw new Error('Project exceeds the total size limit.');
    files[name] = source;
  }
  const active = Object.hasOwn(files, value.active) ? value.active : Object.keys(files)[0];
  return {
    version: VERSION,
    name: typeof value.name === 'string' ? value.name.trim().slice(0, 72) || 'My Workspace' : 'My Workspace',
    files,
    active,
    mode: ['strict', 'nonstrict', 'nocheck'].includes(value.mode) ? value.mode : 'strict',
    optimization: [0, 1, 2].includes(value.optimization) ? value.optimization : 1,
    theme: ['dark', 'light'].includes(value.theme) ? value.theme : 'dark',
    wordWrap: Boolean(value.wordWrap),
    sidebarOpen: value.sidebarOpen !== false,
    inspectorOpen: value.inspectorOpen !== false,
    fontSize: boundedNumber(value.fontSize, 13, 11, 22),
    sidebarWidth: boundedNumber(value.sidebarWidth, 258, 205, 430),
    outputHeight: boundedNumber(value.outputHeight, 202, 105, 520),
    updatedAt: Number.isFinite(value.updatedAt) ? value.updatedAt : Date.now(),
  };
}

export function addFile(project, requested, contents = '') {
  const name = normalizePath(requested);
  if (Object.hasOwn(project.files, name)) throw new Error('A file with that name already exists.');
  if (Object.keys(project.files).length >= FILE_LIMIT) throw new Error('Maximum file count reached.');
  return validateProject({ ...project, files: { ...project.files, [name]: contents }, active: name });
}

export function renameFile(project, oldName, requested) {
  const name = normalizePath(requested);
  if (!Object.hasOwn(project.files, oldName)) throw new Error('Selected file was not found.');
  if (name !== oldName && Object.hasOwn(project.files, name)) throw new Error('The new filename already exists.');
  const files = Object.create(null);
  for (const [path, content] of Object.entries(project.files)) files[path === oldName ? name : path] = content;
  return validateProject({ ...project, files, active: project.active === oldName ? name : project.active });
}

export function deleteFile(project, name) {
  if (!Object.hasOwn(project.files, name)) throw new Error('Selected file was not found.');
  if (Object.keys(project.files).length === 1) throw new Error('At least one file must remain.');
  const files = { ...project.files };
  delete files[name];
  return validateProject({ ...project, files, active: project.active === name ? Object.keys(files)[0] : project.active });
}

export function countLines(source) { return source.split('\n').length; }
export function formatBytes(bytes) { return bytes < 1024 ? `${bytes} B` : bytes < 1048576 ? `${(bytes / 1024).toFixed(1)} KB` : `${(bytes / 1048576).toFixed(2)} MB`; }
export function projectSize(project) { return Object.values(project.files).reduce((sum, code) => sum + new TextEncoder().encode(code).byteLength, 0); }
export function projectToJSON(project) { return JSON.stringify({ format: 'luau-developer-playground', ...validateProject(project) }, null, 2); }

export function loadProject(storage = globalThis.localStorage) {
  for (const key of [STORAGE_KEY, LEGACY_STORAGE_KEY]) {
    try {
      const raw = storage.getItem(key);
      if (raw) return validateProject(JSON.parse(raw));
    } catch { /* Corrupt or inaccessible storage; try the other key. */ }
  }
  return createDefaultProject();
}

export function saveProject(project, storage = globalThis.localStorage) {
  const valid = validateProject({ ...project, updatedAt: Date.now() });
  storage.setItem(STORAGE_KEY, JSON.stringify(valid));
  return valid;
}
