export const OFFICIAL_PLAYGROUND = 'https://play.luau.org/';
export const LZ_URL = 'https://cdnjs.cloudflare.com/ajax/libs/lz-string/1.4.4/lz-string.min.js';

export function buildShareState(project) {
  const state = { v: 2, f: project.files };
  if (Object.keys(project.files).length > 1) state.a = project.active;
  state.s = { mode: project.mode, optimizationLevel: project.optimization };
  return state;
}

export function buildPlaygroundURL(project, { embed = true, compressor = globalThis.LZString } = {}) {
  if (!compressor || typeof compressor.compressToEncodedURIComponent !== 'function') throw new Error('The share codec is unavailable. Check your internet connection.');
  const address = new URL(OFFICIAL_PLAYGROUND);
  if (embed) address.searchParams.set('embed', 'true');
  address.searchParams.set('theme', project.theme);
  address.hash = compressor.compressToEncodedURIComponent(JSON.stringify(buildShareState(project)));
  return address.toString();
}
