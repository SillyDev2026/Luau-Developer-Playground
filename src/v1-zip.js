// Dependency-free, standards-compliant ZIP writer with STORE entries.
// Exports project source files without a CDN or external dependency.
const encoder = new TextEncoder();
const table = new Uint32Array(256);
for (let n = 0; n < 256; n++) {
  let c = n;
  for (let bit = 0; bit < 8; bit++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  table[n] = c >>> 0;
}
export function crc32(data) {
  let crc = 0xffffffff;
  for (const b of data) crc = table[(crc ^ b) & 255] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}
function writer() {
  const chunks = [];
  let length = 0;
  return {
    push(bytes) { chunks.push(bytes); length += bytes.length; },
    get length() { return length; },
    finish() { const out = new Uint8Array(length); let cursor = 0; for (const bytes of chunks) { out.set(bytes, cursor); cursor += bytes.length; } return out; }
  };
}
export function makeZip(files) {
  const entries = Object.entries(files).sort(([a], [b]) => a.localeCompare(b));
  if (entries.length > 150) throw new Error('Too many archive entries.');
  const local = writer(), central = writer();
  for (const [path, source] of entries) {
    if (!path || path.startsWith('/') || path.includes('..') || path.includes('\\')) throw new Error(`Invalid archive path: ${path}`);
    const filename = encoder.encode(path), data = encoder.encode(source);
    if (filename.length > 65535) throw new Error('Archive path is too long.');
    const hash = crc32(data), offset = local.length;
    const header = new Uint8Array(30 + filename.length), h = new DataView(header.buffer);
    h.setUint32(0, 0x04034b50, true); h.setUint16(4, 20, true); h.setUint16(6, 0x0800, true);
    h.setUint32(14, hash, true); h.setUint32(18, data.length, true); h.setUint32(22, data.length, true);
    h.setUint16(26, filename.length, true); header.set(filename, 30);
    local.push(header); local.push(data);
    const directory = new Uint8Array(46 + filename.length), d = new DataView(directory.buffer);
    d.setUint32(0, 0x02014b50, true); d.setUint16(4, 20, true); d.setUint16(6, 20, true); d.setUint16(8, 0x0800, true);
    d.setUint32(16, hash, true); d.setUint32(20, data.length, true); d.setUint32(24, data.length, true);
    d.setUint16(28, filename.length, true); d.setUint32(42, offset, true); directory.set(filename, 46);
    central.push(directory);
  }
  const end = new Uint8Array(22), e = new DataView(end.buffer);
  e.setUint32(0, 0x06054b50, true); e.setUint16(8, entries.length, true); e.setUint16(10, entries.length, true);
  e.setUint32(12, central.length, true); e.setUint32(16, local.length, true);
  const archive = writer(); archive.push(local.finish()); archive.push(central.finish()); archive.push(end);
  return archive.finish();
}
