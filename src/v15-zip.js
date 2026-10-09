// Import ZIP archives using the central directory, not untrusted local-entry
// filenames. Guard against zip-slip, bombs, duplicate names and CRC failures.
import { crc32 } from './v1-zip.js';
const decoder = new TextDecoder('utf-8', { fatal: true });
const MAX_ZIP = 5_000_000, MAX_TOTAL = 1_200_000;
function safePath(name) {
  if (!name || name.includes('\\') || name.startsWith('/') || /^(?:[A-Za-z]:|\/)/.test(name) || name.split('/').some(p => p === '..' || p === '.' || !p) || /[\x00-\x1f]/.test(name)) throw new Error(`Unsafe ZIP path: ${name}`);
  if (!/\.lua(u)?$/i.test(name)) throw new Error(`Only Luau source is importable: ${name}`);
  return name;
}
async function expand(data, method) {
  if (method === 0) return data;
  if (method !== 8) throw new Error(`ZIP compression method ${method} is unsupported.`);
  if (typeof DecompressionStream === 'undefined') throw new Error('Compressed ZIP import requires a browser with DecompressionStream.');
  const bytes = await new Response(new Blob([data]).stream().pipeThrough(new DecompressionStream('deflate-raw'))).arrayBuffer();
  return new Uint8Array(bytes);
}
export async function readZip(input) {
  const bytes = input instanceof Uint8Array ? input : new Uint8Array(input);
  if (bytes.length > MAX_ZIP || bytes.length < 22) throw new Error('ZIP must be between 22 bytes and 5 MB.');
  const dv = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let eocd = -1;
  for (let n = bytes.length - 22; n >= Math.max(0, bytes.length - 65557); n--) if (dv.getUint32(n, true) === 0x06054b50) { eocd = n; break; }
  if (eocd < 0) throw new Error('ZIP end-of-directory header not found.');
  if (dv.getUint16(eocd + 4, true) || dv.getUint16(eocd + 6, true)) throw new Error('Multi-disk ZIP is unsupported.');
  const count = dv.getUint16(eocd + 10, true), size = dv.getUint32(eocd + 12, true), start = dv.getUint32(eocd + 16, true);
  if (count > 150 || start + size > eocd) throw new Error('Invalid ZIP directory or too many entries.');
  let pos = start, total = 0;
  const files = Object.create(null);
  for (let n = 0; n < count; n++) {
    if (pos + 46 > bytes.length || dv.getUint32(pos, true) !== 0x02014b50) throw new Error('Invalid ZIP directory entry.');
    const flags = dv.getUint16(pos + 8, true), method = dv.getUint16(pos + 10, true), crc = dv.getUint32(pos + 16, true), compressed = dv.getUint32(pos + 20, true), expanded = dv.getUint32(pos + 24, true);
    const nameLen = dv.getUint16(pos + 28, true), extra = dv.getUint16(pos + 30, true), comment = dv.getUint16(pos + 32, true), offset = dv.getUint32(pos + 42, true);
    if (pos + 46 + nameLen + extra + comment > bytes.length) throw new Error('Truncated ZIP directory.');
    const name = decoder.decode(bytes.slice(pos + 46, pos + 46 + nameLen));
    pos += 46 + nameLen + extra + comment;
    if (name.endsWith('/')) continue;
    // Standard project ZIPs contain README, assets and directories. Ignore
    // non-Luau entries without importing or interpreting their contents.
    if (!/\.lua(u)?$/i.test(name)) continue;
    const path = safePath(name);
    if (Object.hasOwn(files, path)) throw new Error('Duplicate ZIP entry: ' + path);
    if (flags & 1) throw new Error('Password-encrypted ZIP entries are not supported.');
    if (expanded > 200_000 || (total += expanded) > MAX_TOTAL) throw new Error('ZIP would exceed workspace size limits.');
    if (offset + 30 > bytes.length || dv.getUint32(offset, true) !== 0x04034b50) throw new Error('Invalid ZIP file header.');
    const localName = dv.getUint16(offset + 26, true), localExtra = dv.getUint16(offset + 28, true);
    const dataOffset = offset + 30 + localName + localExtra;
    if (dataOffset + compressed > bytes.length) throw new Error('Truncated ZIP entry data.');
    const content = await expand(bytes.slice(dataOffset, dataOffset + compressed), method);
    if (content.length !== expanded || crc32(content) !== crc) throw new Error('ZIP file failed integrity verification: ' + path);
    files[path] = decoder.decode(content);
  }
  if (!Object.keys(files).length) throw new Error('ZIP contains no .luau or .lua files.');
  // GitHub repository archives wrap project files in Repo-main/. Strip that
  // single shared top-level folder without altering real project subfolders.
  const paths = Object.keys(files);
  const commonRoot = paths.every(p => p.startsWith(paths[0].split('/')[0] + '/')) ? paths[0].split('/')[0] : null;
  if (commonRoot && !/^(?:modules|lib|src|tests|scripts|examples)$/i.test(commonRoot)) {
    const stripped = Object.create(null);
    for (const [path, content] of Object.entries(files)) stripped[path.slice(commonRoot.length + 1)] = content;
    return stripped;
  }
  return files;
}
