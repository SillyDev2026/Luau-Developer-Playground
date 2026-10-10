--!native
--!optimize 2

local Compression = {}

export type Mode = "Binary" | "BinaryWithHash"
export type StringStrategy = "Auto" | "Raw" | "LZ" | "ASCII7" | "Identifier6" | "Numeric4"
export type TableStrategy = "Auto" | "Compact" | "Dynamic"
export type BufferStrategy = "Auto" | "Raw" | "LZ" | "Sparse" | "Nibble"
export type EntropyStrategy = "Auto" | "Huffman" | "None"

export type Options = {
	Mode: Mode?,
	CompressStrings: boolean?,
	StringMinLength: number?,
	StringStrategy: StringStrategy?,
	StringSearchDepth: number?,
	StringWindowSize: number?,
	StringMaxMatch: number?,
	VerifyHash: boolean?,
	SchemaVersion: number?,
	UseStringDictionary: boolean?,
	DictionaryMinUses: number?,
	MaxDictionaryEntries: number?,
	TableCompression: boolean?,
	HomogeneousArrays: boolean?,
	DeltaArrays: boolean?,
	RunLengthArrays: boolean?,
	CompactMapKeys: boolean?,
	TableKeyMapping: boolean?,
	MappedKeyMinUses: number?,
	MaxMappedKeys: number?,
	TableStrategy: TableStrategy?,
	CompressBuffers: boolean?,
	BufferStrategy: BufferStrategy?,
	BufferMinLength: number?,
	BufferSearchDepth: number?,
	BufferWindowSize: number?,
	BufferMaxMatch: number?,
	EntropyCoding: boolean?,
	EntropyStrategy: EntropyStrategy?,
	HuffmanMinBytes: number?,
	HuffmanMinSavings: number?,
	HuffmanMaxCodeBits: number?,
	AllowExpansion: boolean?,
}

export type Descriptor = {
	Kind: string,
	Optional: boolean?,
	Options: {[string]: any}?,
	Item: Descriptor?,
	Fields: {[string]: Descriptor}?,
}

export type Packet = {
	Data: buffer,
	Hash: number?,
	Bytes: number,
	Bits: number,
	SchemaVersion: number?,
	RawBytes: number?,
	SavedBytes: number?,
	ExpandedBytes: number?,
	ByteDelta: number?,
	SavingsPercent: number?,
	ExpansionPercent: number?,
	Ratio: number?,
	IsSmaller: boolean?,
	ValueType: string?,
	Codec: string?,
	Passthrough: boolean?,
	UsefulBits: number?,
	PhysicalBits: number?,
	SavedBits: number?,
	ExpandedBits: number?,
	BitSavingsPercent: number?,
	PaddingBits: number?,
	IsPhysicallySmaller: boolean?,
	IsBitSmaller: boolean?,
	Entropy: string?,
	EntropyBytesBefore: number?,
	EntropyBytesAfter: number?,
	EntropySavedBytes: number?,
}

export type BitLayoutField = {
	Name: string,
	Type: string,
	Present: boolean,
	UsefulBits: number,
	PaddingBits: number,
	PhysicalBits: number,
	RawBits: number,
	SavedBits: number,
	ExpandedBits: number,
	SavingsPercent: number,
}

export type BitLayout = {
	HeaderBits: number,
	UsefulBits: number,
	PaddingBits: number,
	PhysicalBits: number,
	PhysicalBytes: number,
	RawBits: number,
	SavedBits: number,
	ExpandedBits: number,
	SavingsPercent: number,
	Fields: {BitLayoutField},
}

type Writer = {
	Buffer: buffer,
	Position: number,
	BitBuffer: number,
	BitCount: number,
	UsedBits: number,
	PaddingBits: number,
	KeyMapEncode: {[string]: number}?,
	KeyMapCount: number?,
}

type Reader = {
	Buffer: buffer,
	Position: number,
	Length: number,
	BitBuffer: number,
	BitCount: number,
	LegacyVarUInt: boolean,
	KeyMapDecode: {string}?,
}

type Field = {
	Name: string,
	Descriptor: Descriptor,
}

type DictionaryState = {
	Encode: {[string]: number},
	Decode: {string},
}

type SchemaObject = {
	Fields: {Field},
	Version: number,
	Encode: (self: SchemaObject, value: {[string]: any}, options: Options?) -> Packet,
	Decode: (self: SchemaObject, packet: Packet | buffer, options: Options?) -> {[string]: any},
	EncodeDelta: (self: SchemaObject, previous: {[string]: any}, current: {[string]: any}, options: Options?) -> Packet,
	DecodeDelta: (self: SchemaObject, previous: {[string]: any}, packet: Packet | buffer, options: Options?) -> {[string]: any},
	AnalyzeBits: (self: SchemaObject, value: {[string]: any}) -> BitLayout,
	PrintBitLayout: (self: SchemaObject, value: {[string]: any}) -> BitLayout,
}

local FMT = {
	MAGIC_A = 0x43,
	MAGIC_B = 0x50,
	VERSION = 25,
	HUFFMAN_MAGIC_A = 0x48,
	HUFFMAN_MAGIC_B = 0x55,
	HUFFMAN_MAGIC_C = 0x46,
	HUFFMAN_MAGIC_D = 0x31,
	COMPACT_NUMBER_MAGIC = 0xD7,
	COMPACT_BUFFER_ZERO_RUN_MAGIC = 0xD6,
	COMPACT_TABLE_MAGIC = 0xD5,
	COMPACT_MAPPED_TABLE_MAGIC = 0xD2,
	COMPACT_BUFFER_MAGIC = 0xD4,
	COMPACT_BUFFER_RAW_MAGIC = 0xD3,
}

-- Returns true when the buffer begins with a Compression-owned buffer frame marker.
local function hasCompressionBufferMagic(data: buffer): boolean
	if buffer.len(data) == 0 then return false end
	local first = buffer.readu8(data, 0)
	return first == FMT.COMPACT_BUFFER_MAGIC
		or first == FMT.COMPACT_BUFFER_RAW_MAGIC
		or first == FMT.COMPACT_BUFFER_ZERO_RUN_MAGIC
end

local MODE = {
	DYNAMIC = 1,
	SCHEMA = 2,
	DELTA = 3,
}

local TAG = {
	NIL = 0,
	FALSE = 1,
	TRUE = 2,
	UINT = 3,
	INT = 4,
	FLOAT = 5,
	STRING = 6,
	STRING_REF = 7,
	ARRAY = 8,
	MAP = 9,
	VECTOR2 = 10,
	VECTOR3 = 11,
	COLOR3 = 12,
	CFRAME = 13,
	ZERO = 14,
	ONE = 15,
	NEG_ONE = 16,
	ARRAY_BOOL = 17,
	ARRAY_UINT = 18,
	ARRAY_INT = 19,
	ARRAY_FLOAT = 20,
	ARRAY_STRING = 21,
	ARRAY_RLE = 22,
	MAP_STRING = 23,
	ARRAY_UINT_DELTA = 24,
	ARRAY_INT_DELTA = 25,
	POWER10 = 26,
	BUFFER = 27,
	COLOR3_F32 = 28,
	COLOR3_F64 = 29,
	FLOAT32 = 30,
	DECIMAL = 31,
	VECTOR2_F32 = 32,
	VECTOR3_F32 = 33,
	CFRAME_F32 = 34,
	ARRAY_FLOAT32 = 35,
	UDIM = 36,
	UDIM2 = 37,
	RECT = 38,
	NUMBER_RANGE = 39,
	BRICK_COLOR = 40,
	DATETIME = 41,
	ARRAY_VECTOR2_F32 = 42,
	ARRAY_VECTOR2_F64 = 43,
	ARRAY_VECTOR3_F32 = 44,
	ARRAY_VECTOR3_F64 = 45,
	ARRAY_COLOR3_RGB8 = 46,
	ARRAY_COLOR3_F32 = 47,
	ARRAY_COLOR3_F64 = 48,
	ARRAY_UDIM = 49,
	ARRAY_UDIM2 = 50,
	ARRAY_NUMBER_RANGE = 51,
	ARRAY_BRICK_COLOR = 52,
	ARRAY_RECT = 53,
	ARRAY_DATETIME = 54,
	INLINE_NEG_BASE = 112,
	INLINE_UINT_BASE = 128,
}

local ATOM = {
	NIL = 0xE0,
	FALSE = 0xE1,
	TRUE = 0xE2,
	ZERO = 0xE3,
	ONE = 0xE4,
	NEG_ONE = 0xE5,
	UINT = 0xE6,
	INT = 0xE7,
	FLOAT = 0xE8,
	POWER10 = 0xE9,
	STRING = 0xEA,
	VECTOR2 = 0xEB,
	VECTOR3 = 0xEC,
	COLOR3 = 0xED,
	CFRAME = 0xEE,
	FLOAT32 = 0xEF,
	DECIMAL = 0xF0,
	VECTOR2_F32 = 0xF1,
	VECTOR3_F32 = 0xF2,
	CFRAME_F32 = 0xF3,
	COLOR3_F32 = 0xF4,
	COLOR3_F64 = 0xF5,
	UDIM = 0xF6,
	UDIM2 = 0xF7,
	RECT = 0xF8,
	NUMBER_RANGE = 0xF9,
	BRICK_COLOR = 0xFA,
	DATETIME = 0xFB,
}

local DEFAULT_CAPACITY = 256
local MAX_SAFE_INTEGER = 9007199254740991
local MAX_SAFE_ZIGZAG_INTEGER = 4503599627370495
local MAX_DECODE_STRING_BYTES = 4_194_304
local MAX_DECODE_CONTAINER_ITEMS = 4_194_304
local MAX_HUFFMAN_DECODE_BYTES = 16_777_216
local MAX_DECODE_BUFFER_BYTES = 16_777_216

-- Handles fail.
local function fail(message: string, level: number?)
	error("Compression: " .. message, (level or 1) + 1)
end

-- Handles new writer.
local function newWriter(capacity: number?): Writer
	return {
		Buffer = buffer.create(capacity or DEFAULT_CAPACITY),
		Position = 0,
		BitBuffer = 0,
		BitCount = 0,
		UsedBits = 0,
		PaddingBits = 0,
		KeyMapEncode = nil,
		KeyMapCount = nil,
	}
end

-- Handles new reader.
local function newReader(data: buffer): Reader
	return {
		Buffer = data,
		Position = 0,
		Length = buffer.len(data),
		BitBuffer = 0,
		BitCount = 0,
		LegacyVarUInt = false,
		KeyMapDecode = nil,
	}
end

-- Handles ensure capacity.
local function ensureCapacity(w: Writer, additional: number)
	local needed = w.Position + additional
	if needed <= buffer.len(w.Buffer) then return end
	local old = w.Buffer
	local newLength = math.max(needed, math.max(16, buffer.len(old) * 2))
	local nextBuffer = buffer.create(newLength)
	buffer.copy(nextBuffer, 0, old, 0, w.Position)
	w.Buffer = nextBuffer
end

-- Handles write byte raw.
local function writeByteRaw(w: Writer, value: number)
	ensureCapacity(w, 1)
	buffer.writeu8(w.Buffer, w.Position, value % 256)
	w.Position += 1
end

-- Handles write byte.
local function writeByte(w: Writer, value: number)
	writeByteRaw(w, value)
	w.UsedBits += 8
end

-- Handles read byte.
local function readByte(r: Reader): number
	if r.Position >= r.Length then fail("unexpected end of payload", 2) end
	local value = buffer.readu8(r.Buffer, r.Position)
	r.Position += 1
	return value
end

-- Handles flush bits.
local function flushBits(w: Writer)
	if w.BitCount > 0 then
		w.PaddingBits += 8 - w.BitCount
		writeByteRaw(w, w.BitBuffer)
		w.BitBuffer = 0
		w.BitCount = 0
	end
end

-- Handles align reader.
local function alignReader(r: Reader)
	r.BitBuffer = 0
	r.BitCount = 0
end

-- Handles write bits.
local function writeBits(w: Writer, value: number, count: number)
	w.UsedBits += count
	local remaining = count
	local current = value
	while remaining > 0 do
		local free = 8 - w.BitCount
		local take = math.min(free, remaining)
		local base = 2 ^ take
		local chunk = current % base
		w.BitBuffer += chunk * 2 ^ w.BitCount
		w.BitCount += take
		current = math.floor(current / base)
		remaining -= take
		if w.BitCount == 8 then
			writeByteRaw(w, w.BitBuffer)
			w.BitBuffer = 0
			w.BitCount = 0
		end
	end
end

-- Handles read bits.
local function readBits(r: Reader, count: number): number
	local result = 0
	local multiplier = 1
	local remaining = count
	while remaining > 0 do
		if r.BitCount == 0 then
			r.BitBuffer = readByte(r)
			r.BitCount = 8
		end
		local take = math.min(r.BitCount, remaining)
		local base = 2 ^ take
		local chunk = r.BitBuffer % base
		result += chunk * multiplier
		r.BitBuffer = math.floor(r.BitBuffer / base)
		r.BitCount -= take
		remaining -= take
		multiplier *= base
	end
	return result
end

-- Handles write var uint.
local function writeVarUInt(w: Writer, value: number)
	if value < 0 or value % 1 ~= 0 or value > MAX_SAFE_INTEGER then fail("expected safe unsigned integer", 2) end
	flushBits(w)
	repeat
		local byte = value % 128
		value = math.floor(value / 128)
		if value > 0 then byte += 128 end
		writeByte(w, byte)
	until value == 0
end

-- Handles read var uint.
local function readVarUInt(r: Reader): number
	alignReader(r)
	local result = 0
	local multiplier = 1
	if r.LegacyVarUInt then
		for _ = 1, 256 do
			local byte = readByte(r)
			result += (byte % 128) * multiplier
			if byte < 128 then return result end
			multiplier *= 128
			if multiplier == math.huge then fail("legacy VarUInt overflow", 2) end
		end
		fail("invalid legacy VarUInt", 2)
		return 0
	end
	for _ = 1, 8 do
		local byte = readByte(r)
		result += (byte % 128) * multiplier
		if result > MAX_SAFE_INTEGER then fail("VarUInt exceeds safe integer range", 2) end
		if byte < 128 then return result end
		multiplier *= 128
	end
	fail("invalid VarUInt", 2)
	return 0
end

-- Handles zigzag encode.
local function zigzagEncode(value: number): number
	if value >= 0 then return value * 2 end
	return -value * 2 - 1
end

-- Handles zigzag decode.
local function zigzagDecode(value: number): number
	if value % 2 == 0 then return value / 2 end
	return -(value + 1) / 2
end

-- Handles write var int.
local function writeVarInt(w: Writer, value: number)
	writeVarUInt(w, zigzagEncode(value))
end

-- Handles read var int.
local function readVarInt(r: Reader): number
	return zigzagDecode(readVarUInt(r))
end

-- Handles write f64.
local function writeF64(w: Writer, value: number)
	flushBits(w)
	ensureCapacity(w, 8)
	buffer.writef64(w.Buffer, w.Position, value)
	w.Position += 8
	w.UsedBits += 64
end

-- Handles read f64.
local function readF64(r: Reader): number
	alignReader(r)
	if r.Position + 8 > r.Length then fail("truncated float", 2) end
	local value = buffer.readf64(r.Buffer, r.Position)
	r.Position += 8
	return value
end

-- Handles write f32.
local function writeF32(w: Writer, value: number)
	flushBits(w)
	ensureCapacity(w, 4)
	buffer.writef32(w.Buffer, w.Position, value)
	w.Position += 4
	w.UsedBits += 32
end

-- Handles read f32.
local function readF32(r: Reader): number
	alignReader(r)
	if r.Position + 4 > r.Length then fail("truncated float32", 2) end
	local value = buffer.readf32(r.Buffer, r.Position)
	r.Position += 4
	return value
end

local FLOAT32_EXACT_SCRATCH = buffer.create(4)
-- Tests exact Float32 round trips with a reusable non-yielding scratch buffer.
local function exactFloat32(value: number): boolean
	if value ~= value or value == math.huge or value == -math.huge then return false end
	buffer.writef32(FLOAT32_EXACT_SCRATCH, 0, value)
	return buffer.readf32(FLOAT32_EXACT_SCRATCH, 0) == value
end

-- Handles color3 bytes.
local function color3Bytes(value: Color3): (number, number, number)
	return
		math.clamp(math.floor(value.R * 255 + 0.5), 0, 255),
		math.clamp(math.floor(value.G * 255 + 0.5), 0, 255),
		math.clamp(math.floor(value.B * 255 + 0.5), 0, 255)
end

-- Handles exact color3 bytes.
local function exactColor3Bytes(value: Color3): (boolean, number, number, number)
	local r, g, b = color3Bytes(value)
	local restored = Color3.fromRGB(r, g, b)
	return
		restored.R == value.R
		and restored.G == value.G
		and restored.B == value.B,
		r,
		g,
		b
end

-- Handles exact color3 f32.
local function exactColor3F32(value: Color3): boolean
	return
		exactFloat32(value.R)
		and exactFloat32(value.G)
		and exactFloat32(value.B)
end

-- Handles write string raw.
local function writeStringRaw(w: Writer, value: string)
	flushBits(w)
	writeVarUInt(w, #value)
	ensureCapacity(w, #value)
	buffer.writestring(w.Buffer, w.Position, value)
	w.Position += #value
	w.UsedBits += #value * 8
end

-- Handles read string raw.
local function readStringRaw(r: Reader): string
	alignReader(r)
	local length = readVarUInt(r)
	if r.Position + length > r.Length then fail("truncated string", 2) end
	local value = buffer.readstring(r.Buffer, r.Position, length)
	r.Position += length
	return value
end

-- Finalizes a writer and avoids a copy when its backing buffer is already exactly sized.
local function finish(w: Writer): buffer
	flushBits(w)
	if w.Position == buffer.len(w.Buffer) then return w.Buffer end
	local result = buffer.create(w.Position)
	if w.Position > 0 then buffer.copy(result, 0, w.Buffer, 0, w.Position) end
	return result
end

-- Hashes a buffer with FNV-1a while caching the source length for the hot loop.
local function hashBuffer(data: buffer): number
	local hash = 2166136261
	local length = buffer.len(data)
	for i = 0, length - 1 do
		hash = bit32.bxor(hash, buffer.readu8(data, i))
		hash = (hash * 16777619) % 4294967296
	end
	return hash
end

type HuffmanNode = {
	Frequency: number,
	MinSymbol: number,
	Symbol: number?,
	Left: HuffmanNode?,
	Right: HuffmanNode?,
}

type HuffmanCode = {
	Code: number,
	PackedCode: number,
	Length: number,
}

-- Handles is huffman frame.
local function isHuffmanFrame(data: buffer): boolean
	return buffer.len(data) >= 4
		and buffer.readu8(data, 0) == FMT.HUFFMAN_MAGIC_A
		and buffer.readu8(data, 1) == FMT.HUFFMAN_MAGIC_B
		and buffer.readu8(data, 2) == FMT.HUFFMAN_MAGIC_C
		and buffer.readu8(data, 3) == FMT.HUFFMAN_MAGIC_D
end

-- Handles huffman frame original length.
FMT.HuffmanFrameOriginalLength = function(data: buffer): number?
	if not isHuffmanFrame(data) then return nil end
	local r = newReader(data)
	r.Position = 4
	return readVarUInt(r)
end

-- Handles string starts huffman magic.
FMT.StringStartsHuffmanMagic = function(value: string): boolean
	return #value >= 4
		and string.byte(value, 1) == FMT.HUFFMAN_MAGIC_A
		and string.byte(value, 2) == FMT.HUFFMAN_MAGIC_B
		and string.byte(value, 3) == FMT.HUFFMAN_MAGIC_C
		and string.byte(value, 4) == FMT.HUFFMAN_MAGIC_D
end

-- Handles huffman node less.
local function huffmanNodeLess(a: HuffmanNode, b: HuffmanNode): boolean
	if a.Frequency == b.Frequency then
		return a.MinSymbol < b.MinSymbol
	end
	return a.Frequency < b.Frequency
end

-- Pushes a Huffman node into the deterministic min-heap without creating per-encode closures.
local function huffmanHeapPush(heap: {HuffmanNode}, node: HuffmanNode)
	local index = #heap + 1
	heap[index] = node
	while index > 1 do
		local parent = math.floor(index / 2)
		if not huffmanNodeLess(heap[index], heap[parent]) then break end
		heap[index], heap[parent] = heap[parent], heap[index]
		index = parent
	end
end

-- Pops the smallest Huffman node from the deterministic min-heap.
local function huffmanHeapPop(heap: {HuffmanNode}): HuffmanNode
	local root = heap[1]
	local last = heap[#heap]
	heap[#heap] = nil
	if #heap > 0 then
		heap[1] = last
		local index = 1
		while true do
			local left = index * 2
			if left > #heap then break end
			local right = left + 1
			local smallest = left
			if right <= #heap and huffmanNodeLess(heap[right], heap[left]) then smallest = right end
			if not huffmanNodeLess(heap[smallest], heap[index]) then break end
			heap[index], heap[smallest] = heap[smallest], heap[index]
			index = smallest
		end
	end
	return root
end

-- Builds deterministic Huffman code lengths from a dense byte-frequency table.
local function buildHuffmanLengths(data: buffer, maxCodeBits: number): ({[number]: number}?, number, {number})
	local frequencies: {number} = table.create(256, 0)
	local length = buffer.len(data)
	for i = 0, length - 1 do
		local symbol = buffer.readu8(data, i)
		local index = symbol + 1
		frequencies[index] += 1
	end

	local heap: {HuffmanNode} = {}
	local symbolCount = 0


	for symbol = 0, 255 do
		local frequency = frequencies[symbol + 1]
		if frequency > 0 then
			symbolCount += 1
			huffmanHeapPush(heap, {
				Frequency = frequency,
				MinSymbol = symbol,
				Symbol = symbol,
				Left = nil,
				Right = nil,
			})
		end
	end

	if symbolCount == 0 then return {}, 0, frequencies end
	if symbolCount == 1 then
		local only = heap[1].Symbol :: number
		return {[only] = 1}, 1, frequencies
	end

	while #heap > 1 do
		local left = huffmanHeapPop(heap)
		local right = huffmanHeapPop(heap)
		huffmanHeapPush(heap, {
			Frequency = left.Frequency + right.Frequency,
			MinSymbol = math.min(left.MinSymbol, right.MinSymbol),
			Symbol = nil,
			Left = left,
			Right = right,
		})
	end

	local lengths: {[number]: number} = {}
	local stackNodes: {HuffmanNode} = {heap[1]}
	local stackDepths: {number} = {0}
	local stackCount = 1
	while stackCount > 0 do
		local node = stackNodes[stackCount]
		local depth = stackDepths[stackCount]
		stackCount -= 1
		if node.Symbol ~= nil then
			local codeLength = math.max(1, depth)
			if codeLength > maxCodeBits then return nil, symbolCount, frequencies end
			lengths[node.Symbol] = codeLength
		else
			if node.Right ~= nil then
				stackCount += 1
				stackNodes[stackCount] = node.Right
				stackDepths[stackCount] = depth + 1
			end
			if node.Left ~= nil then
				stackCount += 1
				stackNodes[stackCount] = node.Left
				stackDepths[stackCount] = depth + 1
			end
		end
	end

	return lengths, symbolCount, frequencies
end

-- Handles reverse huffman bits.
local function reverseHuffmanBits(code: number, length: number): number
	local reversed = 0
	local current = code
	for _ = 1, length do
		reversed = reversed * 2 + current % 2
		current = math.floor(current / 2)
	end
	return reversed
end

-- Handles canonical huffman codes.
local function canonicalHuffmanCodes(lengths: {[number]: number}): ({[number]: HuffmanCode}, {any}, number)
	local entries = {}
	local maxLength = 0
	for symbol = 0, 255 do
		local length = lengths[symbol]
		if length ~= nil then
			entries[#entries + 1] = {Symbol = symbol, Length = length}
			maxLength = math.max(maxLength, length)
		end
	end

	table.sort(entries, function(a, b)
		if a.Length == b.Length then return a.Symbol < b.Symbol end
		return a.Length < b.Length
	end)

	local codes: {[number]: HuffmanCode} = {}
	local code = 0
	local previousLength = 0
	for i, entry in ipairs(entries) do
		local length = entry.Length
		if i == 1 then
			code = 0
		else
			code = (code + 1) * 2 ^ (length - previousLength)
		end
		if code >= 2 ^ length then fail("invalid Huffman code lengths", 3) end
		codes[entry.Symbol] = {
			Code = code,
			PackedCode = reverseHuffmanBits(code, length),
			Length = length,
		}
		previousLength = length
	end

	return codes, entries, maxLength
end

-- Handles write huffman code.
local function writeHuffmanCode(w: Writer, packedCode: number, length: number)
	writeBits(w, packedCode, length)
end

-- Handles huffman encode frame.
local function huffmanEncodeFrame(data: buffer, maxCodeBits: number?): buffer?
	if typeof(data) ~= "buffer" then fail("HuffmanEncode expects buffer", 2) end
	local originalLength = buffer.len(data)
	if originalLength > MAX_HUFFMAN_DECODE_BYTES then return nil end
	if originalLength == 0 then
		local empty = newWriter(8)
		writeByte(empty, FMT.HUFFMAN_MAGIC_A)
		writeByte(empty, FMT.HUFFMAN_MAGIC_B)
		writeByte(empty, FMT.HUFFMAN_MAGIC_C)
		writeByte(empty, FMT.HUFFMAN_MAGIC_D)
		writeVarUInt(empty, 0)
		writeVarUInt(empty, 0)
		return finish(empty)
	end

	local maximumBits = math.clamp(math.floor(maxCodeBits or 32), 4, 32)
	local lengths, symbolCount, frequencies = buildHuffmanLengths(data, maximumBits)
	if lengths == nil or symbolCount == 0 then return nil end

	local w = newWriter(math.max(16, originalLength))
	writeByte(w, FMT.HUFFMAN_MAGIC_A)
	writeByte(w, FMT.HUFFMAN_MAGIC_B)
	writeByte(w, FMT.HUFFMAN_MAGIC_C)
	writeByte(w, FMT.HUFFMAN_MAGIC_D)
	writeVarUInt(w, originalLength)
	writeVarUInt(w, symbolCount)

	if symbolCount == 1 then
		for symbol = 0, 255 do
			if lengths[symbol] ~= nil then
				writeByte(w, symbol)
				break
			end
		end
		return finish(w)
	end

	local codes, entries = canonicalHuffmanCodes(lengths)
	local packedCodes: {number} = table.create(256, 0)
	local codeLengths: {number} = table.create(256, 0)
	local bitLength = 0
	for _, entry in ipairs(entries) do
		local code = codes[entry.Symbol]
		local denseIndex = entry.Symbol + 1
		packedCodes[denseIndex] = code.PackedCode
		codeLengths[denseIndex] = code.Length
		writeByte(w, entry.Symbol)
		writeByte(w, code.Length)
		bitLength += frequencies[denseIndex] * code.Length
	end

	writeVarUInt(w, bitLength)
	for i = 0, originalLength - 1 do
		local denseIndex = buffer.readu8(data, i) + 1
		local codeLength = codeLengths[denseIndex]
		if codeLength == 0 then fail("missing Huffman code", 2) end
		writeHuffmanCode(w, packedCodes[denseIndex], codeLength)
	end

	return finish(w)
end

-- Handles huffman decode frame.
local function huffmanDecodeFrame(data: buffer): buffer
	if typeof(data) ~= "buffer" then fail("HuffmanDecode expects buffer", 2) end
	if not isHuffmanFrame(data) then fail("invalid Huffman frame", 2) end
	local r = newReader(data)
	if readByte(r) ~= FMT.HUFFMAN_MAGIC_A
		or readByte(r) ~= FMT.HUFFMAN_MAGIC_B
		or readByte(r) ~= FMT.HUFFMAN_MAGIC_C
		or readByte(r) ~= FMT.HUFFMAN_MAGIC_D then
		fail("invalid Huffman frame", 2)
	end

	local originalLength = readVarUInt(r)
	if originalLength > MAX_HUFFMAN_DECODE_BYTES then fail("Huffman output exceeds decode limit", 2) end
	local symbolCount = readVarUInt(r)
	if symbolCount == 0 then
		if originalLength ~= 0 or r.Position ~= r.Length then fail("invalid empty Huffman frame", 2) end
		return buffer.create(0)
	end
	if symbolCount > 256 then fail("invalid Huffman symbol count", 2) end
    if originalLength < symbolCount then fail("Huffman symbol count exceeds output length", 2) end

	if symbolCount == 1 then
		if r.Position + 1 ~= r.Length then fail("invalid single-symbol Huffman frame", 2) end
		local symbol = readByte(r)
		local result = buffer.create(originalLength)
		if originalLength > 0 then buffer.fill(result, 0, symbol, originalLength) end
		return result
	end

	local lengths: {[number]: number} = {}
	for _ = 1, symbolCount do
		local symbol = readByte(r)
		local length = readByte(r)
		if length < 1 or length > 32 then fail("invalid Huffman code length", 2) end
		if lengths[symbol] ~= nil then fail("duplicate Huffman symbol", 2) end
		lengths[symbol] = length
	end

	local codes, entries, maxLength = canonicalHuffmanCodes(lengths)
	if #entries ~= symbolCount then fail("invalid Huffman codebook", 2) end
	local decodeLookup: {[number]: number} = {}
	for _, entry in ipairs(entries) do
		local code = codes[entry.Symbol]
		local lookupKey = code.Code * 33 + code.Length
		if decodeLookup[lookupKey] ~= nil then fail("duplicate Huffman code", 2) end
		decodeLookup[lookupKey] = entry.Symbol
	end

	local bitLength = readVarUInt(r)
    if bitLength < originalLength or bitLength > originalLength * maxLength then
        fail("invalid Huffman bit length", 2)
    end
	local payloadBytes = math.ceil(bitLength / 8)
	if r.Position + payloadBytes ~= r.Length then fail("invalid Huffman payload length", 2) end
	local body: Reader = {
		Buffer = data,
		Position = r.Position,
		Length = r.Length,
		BitBuffer = 0,
		BitCount = 0,
		LegacyVarUInt = false,
		KeyMapDecode = nil,
	}
	local result = buffer.create(originalLength)
	local consumedBits = 0

	for outputIndex = 0, originalLength - 1 do
		local code = 0
		local found: number? = nil
		for length = 1, maxLength do
			if consumedBits >= bitLength then fail("truncated Huffman bitstream", 2) end
			code = code * 2 + readBits(body, 1)
			consumedBits += 1
			local symbol = decodeLookup[code * 33 + length]
			if symbol ~= nil then
				found = symbol
				break
			end
		end
		if found == nil then fail("invalid Huffman bitstream", 2) end
		buffer.writeu8(result, outputIndex, found)
	end

	if consumedBits ~= bitLength then fail("Huffman bit length mismatch", 2) end
    if body.BitBuffer ~= 0 then fail("nonzero Huffman padding bits", 2) end
	return result
end

-- Handles entropy strategy.
local function entropyStrategy(options: Options?): EntropyStrategy
	if options and options.EntropyCoding == false then return "None" end
	local strategy: EntropyStrategy = options and options.EntropyStrategy or "Auto"
	if strategy ~= "Auto" and strategy ~= "Huffman" and strategy ~= "None" then
		fail("invalid EntropyStrategy " .. tostring(strategy), 3)
	end
	return strategy
end

-- Handles maybe huffman.
local function maybeHuffman(data: buffer, options: Options?): (buffer, boolean)
	if isHuffmanFrame(data) then return data, true end
	local strategy = entropyStrategy(options)
	if strategy == "None" then return data, false end
	local minimum = math.max(1, math.floor(options and options.HuffmanMinBytes or 16))
	if strategy == "Auto" and buffer.len(data) < minimum then return data, false end
	local maxCodeBits = math.clamp(math.floor(options and options.HuffmanMaxCodeBits or 32), 4, 32)
	local candidate = huffmanEncodeFrame(data, maxCodeBits)
	if candidate == nil then return data, false end
	if strategy == "Huffman" then
		if options and options.AllowExpansion == true then return candidate, true end
		if buffer.len(candidate) < buffer.len(data) then return candidate, true end
		return data, false
	end
	local minimumSavings = math.max(0, math.floor(options and options.HuffmanMinSavings or 1))
	if buffer.len(candidate) + minimumSavings <= buffer.len(data) then
		return candidate, true
	end
	return data, false
end

-- Handles entropy decode if needed.
local function entropyDecodeIfNeeded(data: buffer): (buffer, boolean)
	if isHuffmanFrame(data) then return huffmanDecodeFrame(data), true end
	return data, false
end

-- Checks whether huffman.
function Compression.IsHuffman(data: buffer): boolean
	return typeof(data) == "buffer" and isHuffmanFrame(data)
end

-- Handles huffman encode.
function Compression.HuffmanEncode(data: buffer, options: Options?): buffer
	if typeof(data) ~= "buffer" then fail("HuffmanEncode expects buffer", 2) end
	local maxCodeBits = math.clamp(math.floor(options and options.HuffmanMaxCodeBits or 32), 4, 32)
	local encoded = huffmanEncodeFrame(data, maxCodeBits)
	if encoded == nil and maxCodeBits < 32 then encoded = huffmanEncodeFrame(data, 32) end
	if encoded == nil then fail("Huffman code length exceeds supported 32-bit limit", 2) end
	return encoded
end

-- Handles huffman decode.
function Compression.HuffmanDecode(data: buffer): buffer
	return huffmanDecodeFrame(data)
end

-- Safely attempts to huffman without throwing.
function Compression.TryHuffman(data: buffer, options: Options?): (buffer, boolean)
	if typeof(data) ~= "buffer" then fail("TryHuffman expects buffer", 2) end
	return maybeHuffman(data, options)
end

-- Handles huffman stats.
function Compression.HuffmanStats(data: buffer, options: Options?): {[string]: any}
	if typeof(data) ~= "buffer" then fail("HuffmanStats expects buffer", 2) end
	local encoded, selected = maybeHuffman(data, options)
	local rawBytes = buffer.len(data)
	local bytes = buffer.len(encoded)
	return {
		Selected = selected,
		RawBytes = rawBytes,
		Bytes = bytes,
		SavedBytes = math.max(0, rawBytes - bytes),
		ExpandedBytes = math.max(0, bytes - rawBytes),
		SavingsPercent = rawBytes > 0 and math.max(0, (rawBytes - bytes) / rawBytes * 100) or 0,
		Ratio = rawBytes > 0 and bytes / rawBytes or 1,
	}
end

-- Handles is integer.
local function isInteger(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge and value % 1 == 0
end

-- Handles is safe uint.
local function isSafeUInt(value: number): boolean
	return isInteger(value) and value >= 0 and value <= MAX_SAFE_INTEGER
end

-- Handles is safe int.
local function isSafeInt(value: number): boolean
	return isInteger(value) and math.abs(value) <= MAX_SAFE_ZIGZAG_INTEGER
end

-- Handles var uint byte length.
local function varUIntByteLength(value: number): number
	local bytes = 1
	while value >= 128 do
		value = math.floor(value / 128)
		bytes += 1
	end
	return bytes
end

-- Handles var int byte length.
local function varIntByteLength(value: number): number
	return varUIntByteLength(zigzagEncode(value))
end

-- Handles is array.
local function isArray(value: {[any]: any}): boolean
	local n = #value
	for key in pairs(value) do
		if typeof(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > n then return false end
	end
	return true
end

-- Handles deep equal.
FMT.DeepEqual = function(a: any, b: any): boolean
	if a == b then return true end
	local kind = typeof(a)
	if kind ~= typeof(b) then return false end
	if kind == "buffer" then
		local length = buffer.len(a)
		if length ~= buffer.len(b) then return false end
		for i = 0, length - 1 do
			if buffer.readu8(a, i) ~= buffer.readu8(b, i) then return false end
		end
		return true
	end
	if kind ~= "table" then return false end
	for key, value in pairs(a) do if not FMT.DeepEqual(value, b[key]) then return false end end
	for key, value in pairs(b) do if not FMT.DeepEqual(value, a[key]) then return false end end
	return true
end

-- Handles dictionary score.
local function dictionaryScore(value: string, count: number): number
	local rawEntryCost = #value + varUIntByteLength(#value)
	local approximateReferenceCost = count
	local approximateInlineCost = count * (#value + 2)
	return approximateInlineCost - (rawEntryCost + approximateReferenceCost)
end

-- Handles collect strings safe.
local function collectStringsSafe(value: any, counts: {[string]: number}, seen: {[any]: boolean})
	local kind = typeof(value)
	if kind == "string" then
		counts[value] = (counts[value] or 0) + 1
	elseif kind == "table" then
		if seen[value] then return end
		seen[value] = true
		for key, child in pairs(value) do
			collectStringsSafe(key, counts, seen)
			collectStringsSafe(child, counts, seen)
		end
	end
end

-- Handles make dictionary.
local function makeDictionary(value: any, options: Options?): DictionaryState
	local state: DictionaryState = {Encode = {}, Decode = {}}
	if options and options.UseStringDictionary == false then return state end
	local counts = {}
	collectStringsSafe(value, counts, {})
	local minUses = math.max(2, options and options.DictionaryMinUses or 2)
	local candidates = {}
	for stringValue, count in pairs(counts) do
		local score = dictionaryScore(stringValue, count)
		if count >= minUses and #stringValue >= 2 and score > 0 then
			candidates[#candidates + 1] = {Value = stringValue, Count = count, Score = score}
		end
	end
	table.sort(candidates, function(a, b)
		if a.Score == b.Score then
			if a.Count == b.Count then return a.Value < b.Value end
			return a.Count > b.Count
		end
		return a.Score > b.Score
	end)
	local maximum = math.clamp(options and options.MaxDictionaryEntries or 255, 0, 4095)
	for i = 1, math.min(maximum, #candidates) do
		local valueString = candidates[i].Value
		state.Encode[valueString] = i
		state.Decode[i] = valueString
	end
	return state
end

local STR = {
	RAW = 0,
	LZ_V1 = 1,
	NUMERIC4 = 2,
	IDENTIFIER6 = 3,
	ASCII7 = 4,
	LZ_V2 = 5,
	RAW_V3 = 6,
}

local IDENTIFIER_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"
local IDENTIFIER_ENCODE: {[number]: number} = {}
for i = 1, #IDENTIFIER_ALPHABET do IDENTIFIER_ENCODE[string.byte(IDENTIFIER_ALPHABET, i)] = i - 1 end

local NUMERIC4_ENCODE: {[number]: number} = {}
for i = 0, 9 do NUMERIC4_ENCODE[string.byte(tostring(i))] = i end
NUMERIC4_ENCODE[string.byte("-")] = 10
NUMERIC4_ENCODE[string.byte("+")] = 11
NUMERIC4_ENCODE[string.byte(".")] = 12
NUMERIC4_ENCODE[string.byte("e")] = 13
NUMERIC4_ENCODE[string.byte("E")] = 14
local NUMERIC4_DECODE = {"0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "-", "+", ".", "e", "E"}

-- Handles raw string packet.
local function rawStringPacket(value: string): buffer
	if #value == 0 then return buffer.create(0) end
	local first = string.byte(value, 1)
	if first > STR.RAW_V3 and not FMT.StringStartsHuffmanMagic(value) then
		local raw = buffer.create(#value)
		buffer.writestring(raw, 0, value)
		return raw
	end
	local w = newWriter(math.max(1, #value + 1))
	writeByte(w, STR.RAW_V3)
	flushBits(w)
	ensureCapacity(w, #value)
	buffer.writestring(w.Buffer, w.Position, value)
	w.Position += #value
	w.UsedBits += #value * 8
	return finish(w)
end

-- Returns the exact raw-string fallback size without allocating it.
local function rawStringPacketByteLength(value: string): number
	local length = #value
	if length == 0 then return 0 end
	local first = string.byte(value, 1)
	if first > STR.RAW_V3 and not FMT.StringStartsHuffmanMagic(value) then return length end
	return length + 1
end

type StringAnalysis = {
	Length: number,
	Numeric4: boolean,
	Identifier6: boolean,
	ASCII7: boolean,
}

-- Scans string codec eligibility once so Auto does not rescan for Numeric4, Identifier6, and ASCII7.
local function analyzeString(value: string): StringAnalysis
	local length = #value
	local numeric = length > 0
	local identifier = length > 0
	local ascii = length > 0
	for i = 1, length do
		local byte = string.byte(value, i)
		if numeric and NUMERIC4_ENCODE[byte] == nil then numeric = false end
		if identifier and IDENTIFIER_ENCODE[byte] == nil then identifier = false end
		if ascii and byte > 127 then ascii = false end
		if not numeric and not identifier and not ascii then break end
	end
	return {Length = length, Numeric4 = numeric, Identifier6 = identifier, ASCII7 = ascii}
end

-- Returns the exact Numeric4 encoded size for an eligible non-empty string.
local function estimatedNumeric4Bytes(length: number): number
	return math.floor(length / 2) + 2
end

-- Returns the exact Identifier6 encoded size for an eligible string.
local function estimatedIdentifier6Bytes(length: number): number
	return 1 + varUIntByteLength(length) + math.ceil(length * 6 / 8)
end

-- Returns the exact ASCII7 encoded size for an eligible string.
local function estimatedASCII7Bytes(length: number): number
	return 1 + varUIntByteLength(length) + math.ceil(length * 7 / 8)
end

-- Handles numeric4 packet.
local function numeric4Packet(value: string): buffer?
	if #value == 0 then return nil end
	for i = 1, #value do if NUMERIC4_ENCODE[string.byte(value, i)] == nil then return nil end end
	local w = newWriter(math.max(4, math.ceil(#value / 2) + 2))
	writeByte(w, STR.NUMERIC4)
	local pending: number? = nil
	for i = 1, #value do
		local code = NUMERIC4_ENCODE[string.byte(value, i)] :: number
		if pending == nil then pending = code else writeByte(w, (pending :: number) + code * 16); pending = nil end
	end
	if pending == nil then
		writeByte(w, 15 + 15 * 16)
	else
		writeByte(w, (pending :: number) + 15 * 16)
	end
	return finish(w)
end

-- Handles identifier6 packet.
local function identifier6Packet(value: string): buffer?
	if #value == 0 then return nil end
	for i = 1, #value do if IDENTIFIER_ENCODE[string.byte(value, i)] == nil then return nil end end
	local w = newWriter(math.max(8, math.ceil(#value * 0.75) + 4))
	writeByte(w, STR.IDENTIFIER6)
	writeVarUInt(w, #value)
	for i = 1, #value do writeBits(w, IDENTIFIER_ENCODE[string.byte(value, i)] :: number, 6) end
	return finish(w)
end

-- Handles ascii7 packet.
local function ascii7Packet(value: string): buffer?
	if #value == 0 then return nil end
	for i = 1, #value do if string.byte(value, i) > 127 then return nil end end
	local w = newWriter(math.max(8, math.ceil(#value * 0.875) + 4))
	writeByte(w, STR.ASCII7)
	writeVarUInt(w, #value)
	for i = 1, #value do writeBits(w, string.byte(value, i), 7) end
	return finish(w)
end

-- Builds a numeric 3-byte LZ key without allocating a temporary substring.
local function stringIndexKey(value: string, position: number, length: number): number?
	if position + 2 > length then return nil end
	local a, b, c = string.byte(value, position, position + 2)
	return (a :: number) + (b :: number) * 256 + (c :: number) * 65536
end

-- Adds a string position to the LZ index using allocation-free numeric keys.
local function addStringIndex(index: {[number]: {number}}, value: string, position: number, length: number)
	local key = stringIndexKey(value, position, length)
	if key == nil then return end
	local list = index[key]
	if list == nil then list = {}; index[key] = list end
	list[#list + 1] = position
end

-- Finds the best string LZ match using the same candidate order as previous versions.
local function indexedStringMatch(value: string, position: number, lengthTotal: number, index: {[number]: {number}}, window: number, maxMatch: number, depth: number): (number, number)
	local key = stringIndexKey(value, position, lengthTotal)
	if key == nil then return 0, 0 end
	local list = index[key]
	if list == nil then return 0, 0 end
	local bestDistance = 0
	local bestLength = 0
	local checked = 0
	local maximum = math.min(maxMatch, lengthTotal - position + 1)
	for i = #list, 1, -1 do
		local candidate = list[i]
		local distance = position - candidate
		if distance > window then break end
		checked += 1
		if checked > depth then break end
		local length = 0
		while length < maximum do
			local source = candidate + (length % distance)
			if string.byte(value, source) ~= string.byte(value, position + length) then break end
			length += 1
		end
		if length > bestLength then
			bestLength = length
			bestDistance = distance
			if length == maximum then break end
		end
	end
	if bestLength < 3 or bestLength <= 1 + varUIntByteLength(bestDistance) then return 0, 0 end
	return bestDistance, bestLength
end

-- Counts a repeated-byte run while reusing the caller's cached string length.
local function repeatedByteRun(value: string, position: number, maximum: number, lengthTotal: number): number
	local byte = string.byte(value, position)
	local length = 1
	local limit = math.min(lengthTotal, position + maximum - 1)
	for i = position + 1, limit do
		if string.byte(value, i) ~= byte then break end
		length += 1
	end
	return length
end

-- Handles lz v2 packet.
local function lzV2Packet(value: string, options: Options?): buffer
	local searchDepth = math.clamp(options and options.StringSearchDepth or 24, 1, 128)
	local window = math.clamp(options and options.StringWindowSize or 16383, 32, 65535)
	local maxMatch = math.clamp(options and options.StringMaxMatch or 66, 3, 66)
	local lengthTotal = #value
	local body = newWriter(math.max(16, lengthTotal))
	local index: {[number]: {number}} = {}
	local position = 1
	local literalStart = 1
	local literalLength = 0

	-- Handles flush literal.
	local function flushLiteral()
		if literalLength == 0 then return end
		writeByte(body, literalLength - 1)
		ensureCapacity(body, literalLength)
		buffer.writestring(body.Buffer, body.Position, string.sub(value, literalStart, literalStart + literalLength - 1))
		body.Position += literalLength
		body.UsedBits += literalLength * 8
		literalLength = 0
	end

	while position <= lengthTotal do
		local runLength = repeatedByteRun(value, position, maxMatch, lengthTotal)
		local distance, matchLength = indexedStringMatch(value, position, lengthTotal, index, window, maxMatch, searchDepth)
		local useRun = runLength >= 3 and runLength >= matchLength
		local consume = useRun and runLength or matchLength
		if consume >= 3 then
			flushLiteral()
			if useRun then
				writeByte(body, 128 + runLength - 3)
				writeByte(body, string.byte(value, position))
			else
				writeByte(body, 192 + matchLength - 3)
				writeVarUInt(body, distance)
			end
			for p = position, position + consume - 1 do addStringIndex(index, value, p, lengthTotal) end
			position += consume
			literalStart = position
		else
			if literalLength == 0 then literalStart = position end
			literalLength += 1
			addStringIndex(index, value, position, lengthTotal)
			position += 1
			if literalLength == 128 then flushLiteral(); literalStart = position end
		end
	end
	flushLiteral()
	local packedBody = finish(body)
	local w = newWriter(buffer.len(packedBody) + 8)
	writeByte(w, STR.LZ_V2)
	writeVarUInt(w, lengthTotal)
	ensureCapacity(w, buffer.len(packedBody))
	buffer.copy(w.Buffer, w.Position, packedBody, 0, buffer.len(packedBody))
	w.Position += buffer.len(packedBody)
	w.UsedBits += buffer.len(packedBody) * 8
	return finish(w)
end

-- Handles choose smaller.
local function chooseSmaller(current: buffer, candidate: buffer?): buffer
	if candidate ~= nil and buffer.len(candidate) < buffer.len(current) then return candidate end
	return current
end

-- Compresses a string with lazy raw allocation while preserving the previous codec ordering and byte format.
function Compression.CompressString(value: string, options: Options?): buffer
	if typeof(value) ~= "string" then fail("CompressString expects string", 2) end
	if options and options.CompressStrings == false then return rawStringPacket(value) end

	local strategy: StringStrategy = options and options.StringStrategy or "Auto"
	local best: buffer
	if strategy == "Raw" then
		best = rawStringPacket(value)
	elseif strategy == "Numeric4" then
		local candidate = numeric4Packet(value)
		if candidate == nil then fail("Numeric4 strategy only supports 0-9 + - . e E", 2) end
		best = candidate
	elseif strategy == "Identifier6" then
		local candidate = identifier6Packet(value)
		if candidate == nil then fail("Identifier6 strategy only supports A-Z a-z 0-9 _ -", 2) end
		best = candidate
	elseif strategy == "ASCII7" then
		local candidate = ascii7Packet(value)
		if candidate == nil then fail("ASCII7 strategy only supports ASCII bytes 0-127", 2) end
		best = candidate
	elseif strategy == "LZ" then
		best = lzV2Packet(value, options)
	elseif strategy == "Auto" then
		local analysis = analyzeString(value)
		local bestCandidate: buffer? = nil
		local bestBytes = rawStringPacketByteLength(value)

		if analysis.Numeric4 then
			local bytes = estimatedNumeric4Bytes(analysis.Length)
			if bytes < bestBytes then
				bestCandidate = numeric4Packet(value)
				bestBytes = bestCandidate and buffer.len(bestCandidate) or bestBytes
			end
		end

		if analysis.Identifier6 then
			local bytes = estimatedIdentifier6Bytes(analysis.Length)
			if bytes < bestBytes then
				bestCandidate = identifier6Packet(value)
				bestBytes = bestCandidate and buffer.len(bestCandidate) or bestBytes
			end
		end

		if analysis.ASCII7 then
			local bytes = estimatedASCII7Bytes(analysis.Length)
			if bytes < bestBytes then
				bestCandidate = ascii7Packet(value)
				bestBytes = bestCandidate and buffer.len(bestCandidate) or bestBytes
			end
		end

		local minLength = math.max(3, options and options.StringMinLength or 16)
		if analysis.Length >= minLength then
			local lz = lzV2Packet(value, options)
			if buffer.len(lz) < bestBytes then
				bestCandidate = lz
				bestBytes = buffer.len(lz)
			end
		end

		best = bestCandidate or rawStringPacket(value)
	else
		fail("invalid StringStrategy " .. tostring(strategy), 2)
		best = rawStringPacket(value)
	end

	if strategy ~= "Raw"
		and (not options or options.AllowExpansion ~= true)
		and buffer.len(best) > rawStringPacketByteLength(value) then
		best = rawStringPacket(value)
	end

	local entropyData = maybeHuffman(best, options)
	return entropyData
end

-- Handles decompress string legacy v1.
local function decompressStringLegacyV1(r: Reader): string
	local originalLength = readVarUInt(r)
	if originalLength > MAX_DECODE_STRING_BYTES then
		fail("legacy string exceeds decode limit", 2)
	end
	local compressedLength = readVarUInt(r)
	local compressedEnd = r.Position + compressedLength
	if compressedEnd > r.Length then fail("truncated compressed string", 2) end
	local output = table.create(originalLength)
	while r.Position < compressedEnd and #output < originalLength do
		local token = readByte(r)
		if token == 0 then
			local count = readByte(r)
			if count < 1 or r.Position + count > compressedEnd or #output + count > originalLength then fail("invalid legacy literal run", 2) end
			for _ = 1, count do output[#output + 1] = string.char(readByte(r)) end
		elseif token == 1 then
			if r.Position + 2 > compressedEnd then fail("truncated legacy back-reference", 2) end
			local packed = readByte(r) * 256 + readByte(r)
			local distance = math.floor(packed / 16) + 1
			local length = packed % 16 + 3
			if distance > #output or #output + length > originalLength then fail("invalid legacy back-reference", 2) end
			for _ = 1, length do
				local index = #output - distance + 1
				output[#output + 1] = output[index]
			end
		else
			fail("invalid legacy compressed string token", 2)
		end
	end
	if r.Position ~= compressedEnd or #output ~= originalLength then fail("legacy decompressed string length mismatch", 2) end
	return table.concat(output)
end

-- Decompresses string.
function Compression.DecompressString(data: buffer): string
	if typeof(data) ~= "buffer" then fail("DecompressString expects buffer", 2) end
	data = entropyDecodeIfNeeded(data)
	if buffer.len(data) == 0 then return "" end
	local first = buffer.readu8(data, 0)
	if first > STR.RAW_V3 then
		return buffer.readstring(data, 0, buffer.len(data))
	end
	local r = newReader(data)
	local mode = readByte(r)
	if mode == STR.RAW_V3 then
		local length = r.Length - r.Position
		local value = length > 0 and buffer.readstring(r.Buffer, r.Position, length) or ""
		r.Position = r.Length
		return value
	elseif mode == STR.RAW then
		local value = readStringRaw(r)
		if r.Position ~= r.Length then fail("trailing bytes in raw string payload", 2) end
		return value
	elseif mode == STR.LZ_V1 then
		local value = decompressStringLegacyV1(r)
		if r.Position ~= r.Length then fail("trailing bytes in legacy string payload", 2) end
		return value
	elseif mode == STR.NUMERIC4 then
		local output = {}
		local terminated = false
		while r.Position < r.Length do
			local packed = readByte(r)
			local low = packed % 16
			local high = math.floor(packed / 16)
			if low == 15 then terminated = true; if high ~= 15 then fail("invalid Numeric4 terminator", 2) end; break end
			output[#output + 1] = NUMERIC4_DECODE[low + 1]
			if high == 15 then terminated = true; break end
			output[#output + 1] = NUMERIC4_DECODE[high + 1]
		end
		if not terminated or r.Position ~= r.Length then fail("invalid Numeric4 payload", 2) end
		return table.concat(output)
	elseif mode == STR.IDENTIFIER6 then
		local length = readVarUInt(r)
		if length > MAX_DECODE_STRING_BYTES then
			fail("Identifier6 string exceeds decode limit", 2)
		end
		local availableBits = (r.Length - r.Position) * 8 + r.BitCount
		if length * 6 > availableBits then
			fail("truncated Identifier6 payload", 2)
		end
		local output = table.create(length)
		for i = 1, length do
			local index = readBits(r, 6) + 1
			output[i] = string.sub(IDENTIFIER_ALPHABET, index, index)
		end
		if r.Position ~= r.Length or r.BitBuffer ~= 0 then fail("invalid Identifier6 padding or trailing bytes", 2) end
		return table.concat(output)
	elseif mode == STR.ASCII7 then
		local length = readVarUInt(r)
		if length > MAX_DECODE_STRING_BYTES then
			fail("ASCII7 string exceeds decode limit", 2)
		end
		local availableBits = (r.Length - r.Position) * 8 + r.BitCount
		if length * 7 > availableBits then
			fail("truncated ASCII7 payload", 2)
		end
		local output = table.create(length)
		for i = 1, length do output[i] = string.char(readBits(r, 7)) end
		if r.Position ~= r.Length or r.BitBuffer ~= 0 then fail("invalid ASCII7 padding or trailing bytes", 2) end
		return table.concat(output)
	elseif mode == STR.LZ_V2 then
		local originalLength = readVarUInt(r)
		if originalLength > MAX_DECODE_STRING_BYTES then
			fail("LZ string exceeds decode limit", 2)
		end
		local output = table.create(originalLength)
		while #output < originalLength do
			if r.Position >= r.Length then fail("truncated LZ string payload", 2) end
			local token = readByte(r)
			if token < 128 then
				local count = token + 1
				if r.Position + count > r.Length or #output + count > originalLength then fail("invalid LZ literal run", 2) end
				for _ = 1, count do output[#output + 1] = string.char(readByte(r)) end
			elseif token < 192 then
				local count = token - 128 + 3
				if #output + count > originalLength then fail("invalid LZ byte run", 2) end
				local byte = readByte(r)
				for _ = 1, count do output[#output + 1] = string.char(byte) end
			else
				local length = token - 192 + 3
				local distance = readVarUInt(r)
				if distance < 1 or distance > #output or #output + length > originalLength then fail("invalid LZ back-reference", 2) end
				for _ = 1, length do
					local index = #output - distance + 1
					output[#output + 1] = output[index]
				end
			end
		end
		if r.Position ~= r.Length then fail("trailing bytes in LZ string payload", 2) end
		return table.concat(output)
	end
	fail("invalid compressed string mode", 2)
	return ""
end


local BUF = {
	RAW = 0,
	ZERO = 1,
	FILL = 2,
	LZ = 3,
	SPARSE_ZERO = 4,
	SPARSE_POWER2 = 5,
	NIBBLE_LOW = 6,
	NIBBLE_HIGH = 7,
	V2_FLAG = 0x80,
	V2_LENGTH_EXT = 15,
}

local POWER2_EXPONENT: {[number]: number} = {
	[1] = 0,
	[2] = 1,
	[4] = 2,
	[8] = 3,
	[16] = 4,
	[32] = 5,
	[64] = 6,
	[128] = 7,
}

-- Stores reusable facts discovered during one linear scan of a source buffer.
type BufferAnalysis = {
	Length: number,
	FirstByte: number?,
	AllSame: boolean,
	NonZeroCount: number,
	AllPower2OrZero: boolean,
	LowNibbleCompatible: boolean,
	HighNibbleCompatible: boolean,
	BestZeroStart: number,
	BestZeroLength: number,
}

-- Rejects malformed frames before they can allocate an unreasonable decoded buffer.
BUF.ValidateDecodedBufferLength = function(length: number, label: string?)
	if length < 0 or length % 1 ~= 0 or length > MAX_DECODE_BUFFER_BYTES then
		fail((label or "buffer") .. " output exceeds decode limit", 3)
	end
end

-- Returns the encoded byte cost of a compact v2 buffer header for a given source length.
local function bufferV2HeaderByteLength(length: number): number
	return 2 + (length >= BUF.V2_LENGTH_EXT and varUIntByteLength(length) or 0)
end

-- Normalizes an integer buffer option and rejects NaN, infinity, and non-number values.
local function bufferIntegerOption(value: any, defaultValue: number, minimum: number, maximum: number, name: string): number
	if value == nil then return defaultValue end
	if typeof(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		fail(name .. " must be a finite number", 3)
	end
	return math.clamp(math.floor(value), minimum, maximum)
end

-- Scans a buffer once and caches the facts shared by Fill, ZeroRun, Sparse, and Nibble codecs.
local function analyzeBuffer(value: buffer): BufferAnalysis
	local length = buffer.len(value)
	local firstByte = length > 0 and buffer.readu8(value, 0) or nil
	local allSame = length > 0
	local nonZeroCount = 0
	local allPower2OrZero = true
	local lowNibbleCompatible = true
	local highNibbleCompatible = true
	local bestZeroStart = -1
	local bestZeroLength = 0
	local currentZeroStart = -1
	local currentZeroLength = 0

	for i = 0, length - 1 do
		local byte = buffer.readu8(value, i)
		if allSame and byte ~= firstByte then allSame = false end

		if byte == 0 then
			if currentZeroLength == 0 then currentZeroStart = i end
			currentZeroLength += 1
		else
			if currentZeroLength > bestZeroLength then
				bestZeroStart = currentZeroStart
				bestZeroLength = currentZeroLength
			end
			currentZeroStart = -1
			currentZeroLength = 0

			nonZeroCount += 1
			if allPower2OrZero and POWER2_EXPONENT[byte] == nil then allPower2OrZero = false end
		end

		if lowNibbleCompatible and byte > 15 then lowNibbleCompatible = false end
		if highNibbleCompatible and byte % 16 ~= 0 then highNibbleCompatible = false end
	end

	if currentZeroLength > bestZeroLength then
		bestZeroStart = currentZeroStart
		bestZeroLength = currentZeroLength
	end

	return {
		Length = length,
		FirstByte = firstByte,
		AllSame = allSame,
		NonZeroCount = nonZeroCount,
		AllPower2OrZero = allPower2OrZero,
		LowNibbleCompatible = lowNibbleCompatible,
		HighNibbleCompatible = highNibbleCompatible,
		BestZeroStart = bestZeroStart,
		BestZeroLength = bestZeroLength,
	}
end

-- Returns the exact encoded size of a Fill/Zero candidate, or nil when the codec cannot apply.
local function estimatedFillBytes(analysis: BufferAnalysis): number?
	if analysis.Length == 0 or not analysis.AllSame then return nil end
	return bufferV2HeaderByteLength(analysis.Length) + ((analysis.FirstByte or 0) == 0 and 0 or 1)
end

-- Returns the exact ZeroRun candidate size without constructing the candidate.
local function estimatedZeroRunBytes(analysis: BufferAnalysis): number?
	local bestStart = analysis.BestZeroStart
	local bestLength = analysis.BestZeroLength
	if analysis.Length < 3 or bestStart < 0 or bestLength < 3 then return nil end
	local compactControl = bestStart <= 15 and bestLength <= 16
		and not (bestStart == 15 and bestLength == 16)
	local metadataBytes = compactControl and 2
		or (2 + varUIntByteLength(bestStart) + varUIntByteLength(bestLength))
	local bytes = analysis.Length - bestLength + metadataBytes
	return bytes < analysis.Length and bytes or nil
end

-- Returns the exact SparseZero candidate size without writing its bitmap or values.
local function estimatedSparseZeroBytes(analysis: BufferAnalysis): number?
	if analysis.Length == 0 or analysis.NonZeroCount == 0 or analysis.NonZeroCount == analysis.Length then return nil end
	return bufferV2HeaderByteLength(analysis.Length) + math.ceil(analysis.Length / 8) + analysis.NonZeroCount
end

-- Returns the exact SparsePower2 candidate size when every non-zero byte is a power of two.
local function estimatedSparsePower2Bytes(analysis: BufferAnalysis): number?
	if analysis.Length == 0 or analysis.NonZeroCount == 0 or not analysis.AllPower2OrZero then return nil end
	local headerBytes = bufferV2HeaderByteLength(analysis.Length)
	if analysis.Length <= 14 and analysis.NonZeroCount <= 7 then
		return headerBytes + math.ceil(analysis.NonZeroCount * 7 / 8)
	end
	return headerBytes + math.ceil(analysis.Length / 8) + math.ceil(analysis.NonZeroCount * 3 / 8)
end

-- Returns the exact Nibble4 candidate size when the selected nibble representation is valid.
local function estimatedNibbleBytes(analysis: BufferAnalysis, high: boolean): number?
	if analysis.Length == 0 then return nil end
	local compatible = high and analysis.HighNibbleCompatible or analysis.LowNibbleCompatible
	if not compatible then return nil end
	return bufferV2HeaderByteLength(analysis.Length) + math.ceil(analysis.Length / 2)
end

-- Writes the compact v2 buffer mode/length header.
local function writeBufferV2Header(w: Writer, mode: number, length: number)
	if mode < 0 or mode > 7 then fail("invalid v2 buffer mode", 2) end
	if length < 0 or length % 1 ~= 0 then fail("invalid buffer length", 2) end
	writeByte(w, FMT.COMPACT_BUFFER_MAGIC)
	local lengthCode = length < BUF.V2_LENGTH_EXT and length or BUF.V2_LENGTH_EXT
	writeByte(w, BUF.V2_FLAG + mode * 16 + lengthCode)
	if lengthCode == BUF.V2_LENGTH_EXT then writeVarUInt(w, length) end
end

-- Reads a compact or legacy buffer header and returns mode, length, and format generation.
local function readBufferHeader(r: Reader): (number, number, boolean)
	if readByte(r) ~= FMT.COMPACT_BUFFER_MAGIC then fail("invalid compressed buffer header", 2) end
	local control = readByte(r)
	if control < BUF.V2_FLAG then
		if control < BUF.RAW or control > BUF.LZ then fail("invalid legacy compressed buffer mode", 2) end
		local length = readVarUInt(r)
		BUF.ValidateDecodedBufferLength(length, "legacy buffer")
		return control, length, false
	end
	local packed = control - BUF.V2_FLAG
	local mode = math.floor(packed / 16)
	local lengthCode = packed % 16
	if mode < BUF.RAW or mode > BUF.NIBBLE_HIGH then fail("invalid v2 compressed buffer mode", 2) end
	local length = lengthCode
	if lengthCode == BUF.V2_LENGTH_EXT then length = readVarUInt(r) end
	BUF.ValidateDecodedBufferLength(length, "buffer")
	return mode, length, true
end

-- Wraps raw bytes so Compression-owned magic bytes cannot be mistaken for compressed frames.
local function bufferRawPacket(value: buffer): buffer
	local length = buffer.len(value)
	local result = buffer.create(length + 1)
	buffer.writeu8(result, 0, FMT.COMPACT_BUFFER_RAW_MAGIC)
	if length > 0 then buffer.copy(result, 1, value, 0, length) end
	return result
end

-- Returns the exact raw fallback byte count without allocating the fallback buffer.
local function bufferRawCandidateByteLength(value: buffer): number
	local length = buffer.len(value)
	if length == 0 then return 0 end
	if hasCompressionBufferMagic(value) or isHuffmanFrame(value) then return length + 1 end
	return length
end

-- Returns raw passthrough bytes when safe, otherwise returns an escaped raw buffer frame.
local function bufferRawCandidate(value: buffer): buffer
	local length = buffer.len(value)
	if length == 0 then return buffer.create(0) end
	if not hasCompressionBufferMagic(value) and not isHuffmanFrame(value) then
		local raw = buffer.create(length)
		buffer.copy(raw, 0, value, 0, length)
		return raw
	end
	return bufferRawPacket(value)
end

-- Packs all-zero or single-byte-fill buffers into a tiny fill frame.
local function bufferFillPacket(value: buffer, analysis: BufferAnalysis?): buffer?
	local info = analysis or analyzeBuffer(value)
	local length = info.Length
	if length == 0 or not info.AllSame then return nil end
	local first = info.FirstByte :: number
	local w = newWriter(6)
	writeBufferV2Header(w, first == 0 and BUF.ZERO or BUF.FILL, length)
	if first ~= 0 then writeByte(w, first) end
	return finish(w)
end

-- Checks whether a sparse bitmap marks a byte position as present.
local function bitmapHas(bitmap: buffer, position: number): boolean
	local byteIndex = math.floor(position / 8)
	local bitIndex = position % 8
	return bit32.band(buffer.readu8(bitmap, byteIndex), bit32.lshift(1, bitIndex)) ~= 0
end

-- Appends raw buffer bytes to the current writer without changing their contents.
local function appendRawBuffer(w: Writer, data: buffer)
	local length = buffer.len(data)
	flushBits(w)
	ensureCapacity(w, length)
	if length > 0 then buffer.copy(w.Buffer, w.Position, data, 0, length) end
	w.Position += length
	w.UsedBits += length * 8
end

-- Packs mostly-zero buffers by reserving the bitmap directly inside the output frame.
local function bufferSparseZeroPacket(value: buffer, analysis: BufferAnalysis?): buffer?
	local info = analysis or analyzeBuffer(value)
	local length = info.Length
	local nonZeroCount = info.NonZeroCount
	if length == 0 or nonZeroCount == 0 or nonZeroCount == length then return nil end

	local bitmapBytes = math.ceil(length / 8)
	local w = newWriter(bufferV2HeaderByteLength(length) + bitmapBytes + nonZeroCount)
	writeBufferV2Header(w, BUF.SPARSE_ZERO, length)
	flushBits(w)
	local bitmapStart = w.Position
	ensureCapacity(w, bitmapBytes)
	if bitmapBytes > 0 then buffer.fill(w.Buffer, bitmapStart, 0, bitmapBytes) end
	w.Position += bitmapBytes
	w.UsedBits += bitmapBytes * 8

	for i = 0, length - 1 do
		local byte = buffer.readu8(value, i)
		if byte ~= 0 then
			local byteIndex = math.floor(i / 8)
			local bitIndex = i % 8
			local bitmapByte = buffer.readu8(w.Buffer, bitmapStart + byteIndex)
			buffer.writeu8(w.Buffer, bitmapStart + byteIndex, bit32.bor(bitmapByte, bit32.lshift(1, bitIndex)))
			writeByte(w, byte)
		end
	end
	return finish(w)
end

-- Removes the largest profitable contiguous zero run and stores compact reconstruction metadata.
local function bufferZeroRunPacket(value: buffer, analysis: BufferAnalysis?): buffer?
	local info = analysis or analyzeBuffer(value)
	local length = info.Length
	if length < 3 then return nil end

	local bestStart = info.BestZeroStart
	local bestLength = info.BestZeroLength
	if bestLength < 3 or bestStart < 0 then return nil end

	local compactControl = bestStart <= 15 and bestLength <= 16
		and not (bestStart == 15 and bestLength == 16)
	local metadataBytes = compactControl and 2
		or (2 + varUIntByteLength(bestStart) + varUIntByteLength(bestLength))
	if length - bestLength + metadataBytes >= length then return nil end

	local w = newWriter(length - bestLength + metadataBytes)
	writeByte(w, FMT.COMPACT_BUFFER_ZERO_RUN_MAGIC)
	if compactControl then
		writeByte(w, bestStart + (bestLength - 1) * 16)
	else
		writeByte(w, 0xFF)
		writeVarUInt(w, bestStart)
		writeVarUInt(w, bestLength)
	end

	if bestStart > 0 then
		flushBits(w)
		ensureCapacity(w, bestStart)
		buffer.copy(w.Buffer, w.Position, value, 0, bestStart)
		w.Position += bestStart
		w.UsedBits += bestStart * 8
	end

	local tailStart = bestStart + bestLength
	local tailLength = length - tailStart
	if tailLength > 0 then
		flushBits(w)
		ensureCapacity(w, tailLength)
		buffer.copy(w.Buffer, w.Position, value, tailStart, tailLength)
		w.Position += tailLength
		w.UsedBits += tailLength * 8
	end

	return finish(w)
end

-- Packs sparse power-of-two bytes while writing bitmap metadata directly into the result frame.
local function bufferSparsePower2Packet(value: buffer, analysis: BufferAnalysis?): buffer?
	local info = analysis or analyzeBuffer(value)
	local length = info.Length
	local nonZeroCount = info.NonZeroCount
	if length == 0 or nonZeroCount == 0 or not info.AllPower2OrZero then return nil end

	if length <= 14 and nonZeroCount <= 7 then
		local w = newWriter(bufferV2HeaderByteLength(length) + math.ceil(nonZeroCount * 7 / 8))
		writeBufferV2Header(w, BUF.SPARSE_POWER2, length)
		for i = 0, length - 1 do
			local byte = buffer.readu8(value, i)
			if byte ~= 0 then
				writeBits(w, i, 4)
				writeBits(w, POWER2_EXPONENT[byte] :: number, 3)
			end
		end
		return finish(w)
	end

	local bitmapBytes = math.ceil(length / 8)
	local exponentBytes = math.ceil(nonZeroCount * 3 / 8)
	local w = newWriter(bufferV2HeaderByteLength(length) + bitmapBytes + exponentBytes)
	writeBufferV2Header(w, BUF.SPARSE_POWER2, length)
	flushBits(w)
	local bitmapStart = w.Position
	ensureCapacity(w, bitmapBytes)
	if bitmapBytes > 0 then buffer.fill(w.Buffer, bitmapStart, 0, bitmapBytes) end
	w.Position += bitmapBytes
	w.UsedBits += bitmapBytes * 8

	for i = 0, length - 1 do
		local byte = buffer.readu8(value, i)
		if byte ~= 0 then
			local byteIndex = math.floor(i / 8)
			local bitIndex = i % 8
			local bitmapByte = buffer.readu8(w.Buffer, bitmapStart + byteIndex)
			buffer.writeu8(w.Buffer, bitmapStart + byteIndex, bit32.bor(bitmapByte, bit32.lshift(1, bitIndex)))
			writeBits(w, POWER2_EXPONENT[byte] :: number, 3)
		end
	end
	return finish(w)
end

-- Packs buffers whose bytes fit in low or high 4-bit nibbles.
local function bufferNibblePacket(value: buffer, high: boolean, analysis: BufferAnalysis?): buffer?
	local info = analysis or analyzeBuffer(value)
	local length = info.Length
	if length == 0 then return nil end
	if high then
		if not info.HighNibbleCompatible then return nil end
	elseif not info.LowNibbleCompatible then
		return nil
	end

	local mode = high and BUF.NIBBLE_HIGH or BUF.NIBBLE_LOW
	local w = newWriter(4 + math.ceil(length / 2))
	writeBufferV2Header(w, mode, length)

	local position = 0
	while position < length do
		local a = buffer.readu8(value, position)
		if high then a = math.floor(a / 16) end
		local b = 0
		if position + 1 < length then
			b = buffer.readu8(value, position + 1)
			if high then b = math.floor(b / 16) end
		end
		writeByte(w, a + b * 16)
		position += 2
	end

	return finish(w)
end

-- Builds the 3-byte lookup key used by the buffer LZ match index.
local function bufferIndexKey(value: buffer, position: number, lengthTotal: number): number?
	if position + 2 >= lengthTotal then return nil end
	return buffer.readu8(value, position)
		+ buffer.readu8(value, position + 1) * 256
		+ buffer.readu8(value, position + 2) * 65536
end

-- Adds a buffer position to the LZ match index.
local function addBufferIndex(index: {[number]: {number}}, value: buffer, position: number, lengthTotal: number)
	local key = bufferIndexKey(value, position, lengthTotal)
	if key == nil then return end
	local list = index[key]
	if list == nil then list = {}; index[key] = list end
	list[#list + 1] = position
end

-- Finds the best recent LZ back-reference for the current buffer position.
local function indexedBufferMatch(value: buffer, position: number, lengthTotal: number, index: {[number]: {number}}, window: number, maxMatch: number, depth: number): (number, number)
	local key = bufferIndexKey(value, position, lengthTotal)
	if key == nil then return 0, 0 end
	local list = index[key]
	if list == nil then return 0, 0 end
	local bestDistance = 0
	local bestLength = 0
	local checked = 0
	local maximum = math.min(maxMatch, lengthTotal - position)
	for i = #list, 1, -1 do
		local candidate = list[i]
		local distance = position - candidate
		if distance > window then break end
		checked += 1
		if checked > depth then break end
		local length = 0
		while length < maximum do
			local source = candidate + (length % distance)
			if buffer.readu8(value, source) ~= buffer.readu8(value, position + length) then break end
			length += 1
		end
		if length > bestLength then
			bestLength = length
			bestDistance = distance
			if length == maximum then break end
		end
	end
	if bestLength < 3 or bestLength <= 1 + varUIntByteLength(bestDistance) then return 0, 0 end
	return bestDistance, bestLength
end

-- Counts a repeated-byte run for the buffer LZ encoder.
local function repeatedBufferByteRun(value: buffer, position: number, maximum: number, lengthTotal: number): number
	if position >= lengthTotal then return 0 end
	local byte = buffer.readu8(value, position)
	local length = 1
	local limit = math.min(lengthTotal, position + maximum)
	for i = position + 1, limit - 1 do
		if buffer.readu8(value, i) ~= byte then break end
		length += 1
	end
	return length
end

-- Compresses repeated buffer runs/back-references with the configurable LZ matcher.
local function bufferLZPacket(value: buffer, options: Options?): buffer
	local searchDepth = bufferIntegerOption(options and options.BufferSearchDepth, 32, 1, 192, "BufferSearchDepth")
	local window = bufferIntegerOption(options and options.BufferWindowSize, 32767, 32, 65535, "BufferWindowSize")
	local maxMatch = bufferIntegerOption(options and options.BufferMaxMatch, 66, 3, 66, "BufferMaxMatch")
	local lengthTotal = buffer.len(value)
	local body = newWriter(math.max(16, lengthTotal))
	local index: {[number]: {number}} = {}
	local position = 0
	local literalStart = 0
	local literalLength = 0

	-- Handles flush literal.
	local function flushLiteral()
		if literalLength == 0 then return end
		writeByte(body, literalLength - 1)
		ensureCapacity(body, literalLength)
		buffer.copy(body.Buffer, body.Position, value, literalStart, literalLength)
		body.Position += literalLength
		body.UsedBits += literalLength * 8
		literalLength = 0
	end

	while position < lengthTotal do
		local runLength = repeatedBufferByteRun(value, position, maxMatch, lengthTotal)
		local distance, matchLength = indexedBufferMatch(value, position, lengthTotal, index, window, maxMatch, searchDepth)
		local useRun = runLength >= 3 and runLength >= matchLength
		local consume = useRun and runLength or matchLength
		if consume >= 3 then
			flushLiteral()
			if useRun then
				writeByte(body, 128 + runLength - 3)
				writeByte(body, buffer.readu8(value, position))
			else
				writeByte(body, 192 + matchLength - 3)
				writeVarUInt(body, distance)
			end
			for p = position, position + consume - 1 do addBufferIndex(index, value, p, lengthTotal) end
			position += consume
			literalStart = position
		else
			if literalLength == 0 then literalStart = position end
			literalLength += 1
			addBufferIndex(index, value, position, lengthTotal)
			position += 1
			if literalLength == 128 then flushLiteral(); literalStart = position end
		end
	end

	flushLiteral()
	local packedBody = finish(body)
	local w = newWriter(buffer.len(packedBody) + 4)
	writeBufferV2Header(w, BUF.LZ, lengthTotal)
	appendRawBuffer(w, packedBody)
	return finish(w)
end

-- Chooses the smallest sparse-family representation while reusing one source-buffer analysis pass.
local function bestSparseBuffer(value: buffer, raw: buffer, analysis: BufferAnalysis?): buffer
	local info = analysis or analyzeBuffer(value)
	local best = raw

	local zeroRunBytes = estimatedZeroRunBytes(info)
	if zeroRunBytes ~= nil and zeroRunBytes < buffer.len(best) then
		best = chooseSmaller(best, bufferZeroRunPacket(value, info))
	end

	local power2Bytes = estimatedSparsePower2Bytes(info)
	if power2Bytes ~= nil and power2Bytes < buffer.len(best) then
		best = chooseSmaller(best, bufferSparsePower2Packet(value, info))
	end

	local sparseBytes = estimatedSparseZeroBytes(info)
	if sparseBytes ~= nil and sparseBytes < buffer.len(best) then
		best = chooseSmaller(best, bufferSparseZeroPacket(value, info))
	end

	return best
end

-- Chooses the smaller low/high nibble representation without rescanning codec eligibility.
local function bestNibbleBuffer(value: buffer, raw: buffer, analysis: BufferAnalysis?): buffer
	local info = analysis or analyzeBuffer(value)
	local best = raw

	local lowBytes = estimatedNibbleBytes(info, false)
	if lowBytes ~= nil and lowBytes < buffer.len(best) then
		best = chooseSmaller(best, bufferNibblePacket(value, false, info))
	end

	local highBytes = estimatedNibbleBytes(info, true)
	if highBytes ~= nil and highBytes < buffer.len(best) then
		best = chooseSmaller(best, bufferNibblePacket(value, true, info))
	end

	return best
end

-- Runs buffer codec selection with lazy raw fallback allocation and one shared analysis pass.
local function compressBufferBase(value: buffer, options: Options?): buffer
	if options and options.CompressBuffers == false then return bufferRawCandidate(value) end

	local length = buffer.len(value)
	-- Framed codecs are bounded on decode; oversized inputs stay lossless via raw passthrough/escape.
	if length > MAX_DECODE_BUFFER_BYTES then return bufferRawCandidate(value) end

	local strategy: BufferStrategy = options and options.BufferStrategy or "Auto"
	if strategy == "Raw" then
		return bufferRawCandidate(value)
	elseif strategy == "LZ" then
		local candidate = bufferLZPacket(value, options)
		if options and options.AllowExpansion == true then return candidate end
		local rawBytes = bufferRawCandidateByteLength(value)
		return buffer.len(candidate) <= rawBytes and candidate or bufferRawCandidate(value)
	elseif strategy == "Sparse" then
		local analysis = analyzeBuffer(value)
		local rawBytes = bufferRawCandidateByteLength(value)
		local best: buffer? = nil
		local bestBytes = rawBytes

		local zeroRunBytes = estimatedZeroRunBytes(analysis)
		if zeroRunBytes ~= nil and zeroRunBytes < bestBytes then
			best = bufferZeroRunPacket(value, analysis)
			bestBytes = best and buffer.len(best) or bestBytes
		end
		local power2Bytes = estimatedSparsePower2Bytes(analysis)
		if power2Bytes ~= nil and power2Bytes < bestBytes then
			best = bufferSparsePower2Packet(value, analysis)
			bestBytes = best and buffer.len(best) or bestBytes
		end
		local sparseBytes = estimatedSparseZeroBytes(analysis)
		if sparseBytes ~= nil and sparseBytes < bestBytes then
			best = bufferSparseZeroPacket(value, analysis)
			bestBytes = best and buffer.len(best) or bestBytes
		end
		return best or bufferRawCandidate(value)
	elseif strategy == "Nibble" then
		local analysis = analyzeBuffer(value)
		local rawBytes = bufferRawCandidateByteLength(value)
		local best: buffer? = nil
		local bestBytes = rawBytes

		local lowBytes = estimatedNibbleBytes(analysis, false)
		if lowBytes ~= nil and lowBytes < bestBytes then
			best = bufferNibblePacket(value, false, analysis)
			bestBytes = best and buffer.len(best) or bestBytes
		end
		local highBytes = estimatedNibbleBytes(analysis, true)
		if highBytes ~= nil and highBytes < bestBytes then
			best = bufferNibblePacket(value, true, analysis)
		end
		return best or bufferRawCandidate(value)
	elseif strategy == "Auto" then
		local analysis = analyzeBuffer(value)
		local rawBytes = bufferRawCandidateByteLength(value)
		local best: buffer? = nil
		local bestBytes = rawBytes

		local fillBytes = estimatedFillBytes(analysis)
		if fillBytes ~= nil and fillBytes < bestBytes then
			best = bufferFillPacket(value, analysis)
			bestBytes = best and buffer.len(best) or bestBytes
		end

		local zeroRunBytes = estimatedZeroRunBytes(analysis)
		if zeroRunBytes ~= nil and zeroRunBytes < bestBytes then
			best = bufferZeroRunPacket(value, analysis)
			bestBytes = best and buffer.len(best) or bestBytes
		end

		local power2Bytes = estimatedSparsePower2Bytes(analysis)
		if power2Bytes ~= nil and power2Bytes < bestBytes then
			best = bufferSparsePower2Packet(value, analysis)
			bestBytes = best and buffer.len(best) or bestBytes
		end

		local sparseBytes = estimatedSparseZeroBytes(analysis)
		if sparseBytes ~= nil and sparseBytes < bestBytes then
			best = bufferSparseZeroPacket(value, analysis)
			bestBytes = best and buffer.len(best) or bestBytes
		end

		local lowNibbleBytes = estimatedNibbleBytes(analysis, false)
		if lowNibbleBytes ~= nil and lowNibbleBytes < bestBytes then
			best = bufferNibblePacket(value, false, analysis)
			bestBytes = best and buffer.len(best) or bestBytes
		end

		local highNibbleBytes = estimatedNibbleBytes(analysis, true)
		if highNibbleBytes ~= nil and highNibbleBytes < bestBytes then
			best = bufferNibblePacket(value, true, analysis)
			bestBytes = best and buffer.len(best) or bestBytes
		end

		local minimum = bufferIntegerOption(options and options.BufferMinLength, 6, 3, MAX_DECODE_BUFFER_BYTES, "BufferMinLength")
		if analysis.Length >= minimum then
			local lz = bufferLZPacket(value, options)
			local lzBytes = buffer.len(lz)
			if lzBytes < bestBytes then
				best = lz
				bestBytes = lzBytes
			end
		end

		return best or bufferRawCandidate(value)
	end

	fail("invalid BufferStrategy " .. tostring(strategy), 2)
	return bufferRawCandidate(value)
end

-- Compresses a buffer using the selected buffer codec, then applies Huffman only when profitable.
function Compression.CompressBuffer(value: buffer, options: Options?): buffer
	if typeof(value) ~= "buffer" then fail("CompressBuffer expects buffer", 2) end
	local best = compressBufferBase(value, options)
	local entropyData = maybeHuffman(best, options)
	return entropyData
end
-- Reconstructs an LZ buffer body after its decoded length has been validated.
local function decompressLZBufferBody(r: Reader, originalLength: number): buffer
	local result = buffer.create(originalLength)
	local outputPosition = 0

	while outputPosition < originalLength do
		if r.Position >= r.Length then fail("truncated LZ buffer payload", 2) end
		local token = readByte(r)
		if token < 128 then
			local count = token + 1
			if r.Position + count > r.Length or outputPosition + count > originalLength then fail("invalid LZ buffer literal", 2) end
			buffer.copy(result, outputPosition, r.Buffer, r.Position, count)
			r.Position += count
			outputPosition += count
		elseif token < 192 then
			local count = token - 128 + 3
			if r.Position >= r.Length or outputPosition + count > originalLength then fail("invalid LZ buffer run", 2) end
			local byte = readByte(r)
			buffer.fill(result, outputPosition, byte, count)
			outputPosition += count
		else
			local length = token - 192 + 3
			local distance = readVarUInt(r)
			if distance < 1 or distance > outputPosition or outputPosition + length > originalLength then fail("invalid LZ buffer back-reference", 2) end
			for _ = 1, length do
				local byte = buffer.readu8(result, outputPosition - distance)
				buffer.writeu8(result, outputPosition, byte)
				outputPosition += 1
			end
		end
	end

	if r.Position ~= r.Length then fail("trailing bytes in LZ buffer payload", 2) end
	return result
end

-- Verifies that unused bits in the final sparse bitmap byte are zero.
local function validateBitmapPadding(bitmap: buffer, originalLength: number, label: string)
	local bitmapBytes = buffer.len(bitmap)
	if bitmapBytes == 0 or originalLength % 8 == 0 then return end
	local usedBits = originalLength % 8
	local last = buffer.readu8(bitmap, bitmapBytes - 1)
	local validMask = 2 ^ usedBits - 1
	if bit32.band(last, 255 - validMask) ~= 0 then
		fail("invalid " .. label .. " bitmap padding", 3)
	end
end

-- Counts present entries in a sparse bitmap up to the declared decoded length.
local function countBitmapBits(bitmap: buffer, originalLength: number): number
	local count = 0
	for i = 0, originalLength - 1 do
		if bitmapHas(bitmap, i) then count += 1 end
	end
	return count
end

-- Restores a SparseZero frame from its bitmap and non-zero payload.
local function decompressSparseZero(r: Reader, originalLength: number): buffer
	local bitmapBytes = math.ceil(originalLength / 8)
	if r.Position + bitmapBytes > r.Length then fail("truncated sparse-zero bitmap", 2) end

	local bitmap = buffer.create(bitmapBytes)
	if bitmapBytes > 0 then buffer.copy(bitmap, 0, r.Buffer, r.Position, bitmapBytes) end
	r.Position += bitmapBytes
	validateBitmapPadding(bitmap, originalLength, "sparse-zero")

	local result = buffer.create(originalLength)
	for i = 0, originalLength - 1 do
		if bitmapHas(bitmap, i) then
			if r.Position >= r.Length then fail("truncated sparse-zero values", 2) end
			buffer.writeu8(result, i, readByte(r))
		end
	end

	if r.Position ~= r.Length then fail("trailing bytes in sparse-zero buffer payload", 2) end
	return result
end

-- Decodes the bitmap form of SparsePower2 after validating bitmap and exponent sizes.
local function decodeSparsePower2Bitmap(r: Reader, originalLength: number): buffer
	local bitmapBytes = math.ceil(originalLength / 8)
	if r.Position + bitmapBytes > r.Length then fail("truncated sparse-power2 bitmap", 2) end

	local bitmap = buffer.create(bitmapBytes)
	if bitmapBytes > 0 then buffer.copy(bitmap, 0, r.Buffer, r.Position, bitmapBytes) end
	r.Position += bitmapBytes
	validateBitmapPadding(bitmap, originalLength, "sparse-power2")

	local nonZeroCount = countBitmapBits(bitmap, originalLength)
	local requiredExponentBytes = math.ceil(nonZeroCount * 3 / 8)
	if r.Position + requiredExponentBytes ~= r.Length then
		fail("sparse-power2 exponent payload length mismatch", 2)
	end

	local result = buffer.create(originalLength)
	for i = 0, originalLength - 1 do
		if bitmapHas(bitmap, i) then
			local exponent = readBits(r, 3)
			buffer.writeu8(result, i, 2 ^ exponent)
		end
	end

	if r.Position ~= r.Length or r.BitBuffer ~= 0 then
		fail("invalid sparse-power2 padding or trailing bytes", 2)
	end
	return result
end

-- Detects the ambiguous short SparsePower2 bitmap form emitted by older compatible versions.
local function shortSparsePower2LooksLegacyBitmap(r: Reader, originalLength: number): boolean
	local bitmapBytes = math.ceil(originalLength / 8)
	local remaining = r.Length - r.Position
	if remaining < bitmapBytes then return false end

	local bitmap = buffer.create(bitmapBytes)
	if bitmapBytes > 0 then buffer.copy(bitmap, 0, r.Buffer, r.Position, bitmapBytes) end

	if bitmapBytes > 0 and originalLength % 8 ~= 0 then
		local usedBits = originalLength % 8
		local last = buffer.readu8(bitmap, bitmapBytes - 1)
		local validMask = 2 ^ usedBits - 1
		if bit32.band(last, 255 - validMask) ~= 0 then return false end
	end

	local nonZeroCount = countBitmapBits(bitmap, originalLength)
	if nonZeroCount <= 7 then return false end
	local expected = bitmapBytes + math.ceil(nonZeroCount * 3 / 8)
	return remaining == expected
end

-- Restores compact or bitmap SparsePower2 frames, including legacy recovery.
local function decompressSparsePower2(r: Reader, originalLength: number): buffer
	-- v2.3.1 could emit the bitmap form for short buffers when there were
	-- more than seven non-zero power-of-two entries. The old short decoder
	-- could confuse that payload with the compact 7-bit-entry form.
	if originalLength <= 14 and shortSparsePower2LooksLegacyBitmap(r, originalLength) then
		return decodeSparsePower2Bitmap(r, originalLength)
	end

	local result = buffer.create(originalLength)
	if originalLength <= 14 then
		local payloadBytes = r.Length - r.Position
		if payloadBytes < 1 or payloadBytes > 7 then fail("invalid compact sparse-power2 payload", 2) end
		local count = payloadBytes
		local previousPosition = -1
		for _ = 1, count do
			local position = readBits(r, 4)
			local exponent = readBits(r, 3)
			if position >= originalLength or position <= previousPosition then fail("invalid sparse-power2 position", 2) end
			buffer.writeu8(result, position, 2 ^ exponent)
			previousPosition = position
		end
		if r.Position ~= r.Length or r.BitBuffer ~= 0 then fail("invalid sparse-power2 padding or trailing bytes", 2) end
		return result
	end

	return decodeSparsePower2Bitmap(r, originalLength)
end

-- Restores low-nibble or high-nibble packed buffer bytes.
local function decompressNibbleBuffer(r: Reader, originalLength: number, high: boolean): buffer
	local packedBytes = math.ceil(originalLength / 2)
	if r.Position + packedBytes ~= r.Length then fail("nibble buffer length mismatch", 2) end
	local result = buffer.create(originalLength)
	local outputPosition = 0

	while outputPosition < originalLength do
		local packed = readByte(r)
		local a = packed % 16
		local b = math.floor(packed / 16)
		if high then
			a *= 16
			b *= 16
		end
		buffer.writeu8(result, outputPosition, a)
		outputPosition += 1
		if outputPosition < originalLength then
			buffer.writeu8(result, outputPosition, b)
			outputPosition += 1
		elseif b ~= 0 then
			fail("invalid nibble buffer padding", 2)
		end
	end

	return result
end

-- Reconstructs the omitted contiguous zero run in a ZeroRun frame.
local function decompressZeroRunBuffer(data: buffer): buffer
	if buffer.len(data) < 2 or buffer.readu8(data, 0) ~= FMT.COMPACT_BUFFER_ZERO_RUN_MAGIC then
		fail("invalid zero-run buffer frame", 2)
	end

	local r = newReader(data)
	readByte(r)
	local control = readByte(r)
	local runStart: number
	local runLength: number
	if control == 0xFF then
		runStart = readVarUInt(r)
		runLength = readVarUInt(r)
	else
		runStart = control % 16
		runLength = math.floor(control / 16) + 1
	end

	if runLength < 1 then fail("invalid zero-run length", 2) end
	if runLength > MAX_DECODE_BUFFER_BYTES then fail("zero-run output exceeds decode limit", 2) end
	local payloadStart = r.Position
	local payloadLength = r.Length - payloadStart
	if runStart > payloadLength then fail("invalid zero-run start", 2) end

	local originalLength = payloadLength + runLength
	BUF.ValidateDecodedBufferLength(originalLength, "zero-run buffer")
	local result = buffer.create(originalLength)
	if runStart > 0 then
		buffer.copy(result, 0, data, payloadStart, runStart)
	end
	local suffixLength = payloadLength - runStart
	if suffixLength > 0 then
		buffer.copy(result, runStart + runLength, data, payloadStart + runStart, suffixLength)
	end
	return result
end

-- Decompresses raw, ZeroRun, sparse, nibble, LZ, fill, and Huffman-wrapped buffer frames.
function Compression.DecompressBuffer(data: buffer): buffer
	if typeof(data) ~= "buffer" then fail("DecompressBuffer expects buffer", 2) end
	data = entropyDecodeIfNeeded(data)
	if buffer.len(data) == 0 then return buffer.create(0) end
	local first = buffer.readu8(data, 0)
	if first == FMT.COMPACT_BUFFER_ZERO_RUN_MAGIC then
		return decompressZeroRunBuffer(data)
	end
	if not hasCompressionBufferMagic(data) then
		local raw = buffer.create(buffer.len(data))
		buffer.copy(raw, 0, data, 0, buffer.len(data))
		return raw
	end
	if first == FMT.COMPACT_BUFFER_RAW_MAGIC then
		local length = buffer.len(data) - 1
		local result = buffer.create(length)
		if length > 0 then buffer.copy(result, 0, data, 1, length) end
		return result
	end
	if buffer.len(data) < 2 then fail("truncated compressed buffer", 2) end

	local r = newReader(data)
	local mode, originalLength, isV2 = readBufferHeader(r)

	if mode == BUF.RAW then
		if r.Position + originalLength ~= r.Length then fail("raw buffer length mismatch", 2) end
		local result = buffer.create(originalLength)
		if originalLength > 0 then buffer.copy(result, 0, r.Buffer, r.Position, originalLength) end
		return result
	elseif mode == BUF.ZERO then
		if r.Position ~= r.Length then fail("trailing bytes in zero buffer payload", 2) end
		return buffer.create(originalLength)
	elseif mode == BUF.FILL then
		if r.Position + 1 ~= r.Length then fail("invalid fill buffer payload", 2) end
		local result = buffer.create(originalLength)
		local byte = readByte(r)
		if originalLength > 0 then buffer.fill(result, 0, byte, originalLength) end
		return result
	elseif mode == BUF.LZ then
		return decompressLZBufferBody(r, originalLength)
	end

	if not isV2 then fail("legacy buffer cannot use v2 mode", 2) end

	if mode == BUF.SPARSE_ZERO then
		return decompressSparseZero(r, originalLength)
	elseif mode == BUF.SPARSE_POWER2 then
		return decompressSparsePower2(r, originalLength)
	elseif mode == BUF.NIBBLE_LOW then
		return decompressNibbleBuffer(r, originalLength, false)
	elseif mode == BUF.NIBBLE_HIGH then
		return decompressNibbleBuffer(r, originalLength, true)
	end

	fail("invalid compressed buffer mode", 2)
	return buffer.create(0)
end

-- Reports a non-Huffman buffer frame codec without allocating or decoding entropy data.
BUF.ModeBase = function(data: buffer): string
	if buffer.len(data) == 0 then return "RawPassthrough" end
	local first = buffer.readu8(data, 0)
	if first == FMT.COMPACT_BUFFER_ZERO_RUN_MAGIC then return "ZeroRun" end
	if not hasCompressionBufferMagic(data) then return "RawPassthrough" end
	if first == FMT.COMPACT_BUFFER_RAW_MAGIC then return "Raw" end
	if buffer.len(data) < 2 then return "Invalid" end
	local control = buffer.readu8(data, 1)
	local mode = control
	if control >= BUF.V2_FLAG then
		mode = math.floor((control - BUF.V2_FLAG) / 16)
	end
	if mode == BUF.RAW then return "Raw" end
	if mode == BUF.ZERO then return "Zero" end
	if mode == BUF.FILL then return "Fill" end
	if mode == BUF.LZ then return "LZ" end
	if mode == BUF.SPARSE_ZERO then return "SparseZero" end
	if mode == BUF.SPARSE_POWER2 then return "SparsePower2" end
	if mode == BUF.NIBBLE_LOW then return "Nibble4" end
	if mode == BUF.NIBBLE_HIGH then return "NibbleHigh4" end
	return "Unknown"
end

-- Reports the buffer codec stored in a compressed buffer frame.
function Compression.BufferMode(data: buffer): string
	if typeof(data) ~= "buffer" then return "Invalid" end
	if isHuffmanFrame(data) then
		local ok, decoded = pcall(huffmanDecodeFrame, data)
		if not ok then return "Invalid" end
		return "Huffman/" .. BUF.ModeBase(decoded)
	end
	return BUF.ModeBase(data)
end

-- Reports the buffer frame generation used by a packed buffer.
function Compression.BufferFrameVersion(data: buffer): number?
	if typeof(data) ~= "buffer" then return nil end
	if isHuffmanFrame(data) then return 4 end
	if buffer.len(data) == 0 then return 0 end
	local first = buffer.readu8(data, 0)
	if first == FMT.COMPACT_BUFFER_ZERO_RUN_MAGIC then return 5 end
	if not hasCompressionBufferMagic(data) then return 0 end
	if first == FMT.COMPACT_BUFFER_RAW_MAGIC then return 3 end
	if buffer.len(data) < 2 then return nil end
	return buffer.readu8(data, 1) >= BUF.V2_FLAG and 2 or 1
end

-- Compresses an original buffer once and returns size, mode, savings, and frame statistics.
function Compression.BufferStats(value: buffer, options: Options?): {[string]: any}
	if typeof(value) ~= "buffer" then fail("BufferStats expects buffer", 2) end
	local data = Compression.CompressBuffer(value, options)
	local rawBytes = buffer.len(value)
	local bytes = buffer.len(data)
	local delta = rawBytes - bytes
	local saved = math.max(0, delta)
	local expanded = math.max(0, -delta)
	return {
		Mode = Compression.BufferMode(data),
		FrameVersion = Compression.BufferFrameVersion(data),
		Bytes = bytes,
		Bits = bytes * 8,
		UsefulBits = bytes * 8,
		PhysicalBits = bytes * 8,
		SavedBits = saved * 8,
		ExpandedBits = expanded * 8,
		BitSavingsPercent = rawBytes > 0 and math.max(0, delta / rawBytes * 100) or 0,
		RawBytes = rawBytes,
		SavedBytes = saved,
		ExpandedBytes = expanded,
		ByteDelta = delta,
		SavingsPercent = rawBytes > 0 and math.max(0, delta / rawBytes * 100) or 0,
		ExpansionPercent = rawBytes > 0 and math.max(0, -delta / rawBytes * 100) or 0,
		Ratio = rawBytes > 0 and bytes / rawBytes or 1,
		IsSmaller = bytes < rawBytes,
		Data = data,
	}
end

-- Prints a formatted BufferStats report for an original uncompressed buffer.
function Compression.PrintBufferStats(value: buffer, options: Options?): {[string]: any}
	local stats = Compression.BufferStats(value, options)
	print("========== Compression v2.6.4 Buffer Stats ==========")
	print("Mode:", stats.Mode, "| Frame:", "v" .. tostring(stats.FrameVersion or "?"))
	print("Raw:", Compression.FormatBytes(stats.RawBytes))
	print("Encoded:", Compression.FormatBytes(stats.Bytes))
	if stats.ExpandedBytes > 0 then
		print("Expanded:", Compression.FormatBytes(stats.ExpandedBytes))
		print(string.format("Expansion: %.2f%%", stats.ExpansionPercent))
	else
		print("Saved:", Compression.FormatBytes(stats.SavedBytes))
		print(string.format("Savings: %.2f%%", stats.SavingsPercent))
	end
	print(string.format("Ratio: %.4fx", stats.Ratio))
	print("======================================================")
	return stats
end

-- Attempts to decompress a buffer and returns success, result, and error text instead of throwing.
function Compression.TryDecompressBuffer(data: buffer): (boolean, buffer?, string?)
	local ok, result = pcall(
		Compression.DecompressBuffer,
		data
	)

	if ok then
		return true, result, nil
	end

	return false,
		nil,
		tostring(result)
end

-- Returns compressed bytes only when smaller, otherwise returns an exact raw copy plus false.
function Compression.CompressBufferSmart(value: buffer, options: Options?): (buffer, boolean)
	if typeof(value) ~= "buffer" then fail("CompressBufferSmart expects buffer", 2) end
	local packed = Compression.CompressBuffer(value, options)
	if buffer.len(packed) < buffer.len(value) then return packed, true end
	local raw = buffer.create(buffer.len(value))
	if buffer.len(value) > 0 then buffer.copy(raw, 0, value, 0, buffer.len(value)) end
	return raw, false
end

-- Restores CompressBufferSmart output using the caller-provided compressed flag.
function Compression.DecompressBufferSmart(data: buffer, compressed: boolean): buffer
	if typeof(data) ~= "buffer" then fail("DecompressBufferSmart expects buffer", 2) end
	if compressed then return Compression.DecompressBuffer(data) end
	local raw = buffer.create(buffer.len(data))
	if buffer.len(data) > 0 then buffer.copy(raw, 0, data, 0, buffer.len(data)) end
	return raw
end

-- Handles quantize.
local function quantize(value: number, minimum: number, maximum: number, bits: number): number
	local levels = 2 ^ bits - 1
	local alpha = math.clamp((value - minimum) / (maximum - minimum), 0, 1)
	return math.floor(alpha * levels + 0.5)
end

-- Handles dequantize.
local function dequantize(value: number, minimum: number, maximum: number, bits: number): number
	return minimum + (value / (2 ^ bits - 1)) * (maximum - minimum)
end

local writeNumberPayload: (Writer, number) -> ()
local readNumberPayload: (Reader) -> number
local writeDateTimePayload: (Writer, any) -> ()
local readDateTimePayload: (Reader) -> any

-- Handles validate.
local function validate(descriptor: Descriptor, value: any, path: string)
	if value == nil then
		if descriptor.Optional then return end
		fail(path .. " is required", 3)
	end
	local kind = descriptor.Kind
	local actual = typeof(value)
	if kind == "Bool" and actual ~= "boolean" then fail(path .. " expected boolean", 3)
	elseif kind == "UInt" and (actual ~= "number" or not isSafeUInt(value)) then fail(path .. " expected safe unsigned integer", 3)
	elseif kind == "Int" and (actual ~= "number" or not isSafeInt(value)) then fail(path .. " expected safe signed integer", 3)
	elseif (kind == "Float" or kind == "Quantized") and actual ~= "number" then fail(path .. " expected number", 3)
	elseif (kind == "String" or kind == "CompressedString") and actual ~= "string" then fail(path .. " expected string", 3)
	elseif kind == "Buffer" and actual ~= "buffer" then fail(path .. " expected buffer", 3)
	elseif kind == "Vector2" and actual ~= "Vector2" then fail(path .. " expected Vector2", 3)
	elseif (kind == "Vector3" or kind == "QuantizedVector3") and actual ~= "Vector3" then fail(path .. " expected Vector3", 3)
	elseif kind == "Color3" and actual ~= "Color3" then fail(path .. " expected Color3", 3)
	elseif kind == "CFrame" and actual ~= "CFrame" then fail(path .. " expected CFrame", 3)
	elseif kind == "UDim" and actual ~= "UDim" then fail(path .. " expected UDim", 3)
	elseif kind == "UDim2" and actual ~= "UDim2" then fail(path .. " expected UDim2", 3)
	elseif kind == "Rect" and actual ~= "Rect" then fail(path .. " expected Rect", 3)
	elseif kind == "NumberRange" and actual ~= "NumberRange" then fail(path .. " expected NumberRange", 3)
	elseif kind == "BrickColor" and actual ~= "BrickColor" then fail(path .. " expected BrickColor", 3)
	elseif kind == "DateTime" and actual ~= "DateTime" then fail(path .. " expected DateTime", 3)
	elseif kind == "Array" then
		if actual ~= "table" or not isArray(value) then fail(path .. " expected array", 3) end
		for i, item in ipairs(value) do validate(descriptor.Item :: Descriptor, item, path .. "[" .. tostring(i) .. "]") end
	elseif kind == "Object" then
		if actual ~= "table" then fail(path .. " expected table", 3) end
		for name, child in pairs(descriptor.Fields :: {[string]: Descriptor}) do validate(child, value[name], path .. "." .. name) end
	end
end

-- Handles descriptor uses bit stream.
local function descriptorUsesBitStream(kind: string): boolean
	-- Objects can continue an existing bit stream because their children
	-- perform their own alignment when necessary. This preserves bit packing
	-- for nested Bool/optional fields instead of forcing a padding byte.
	return kind == "Bool"
		or kind == "Quantized"
		or kind == "QuantizedVector3"
		or kind == "Object"
end

-- Handles write descriptor.
local function writeDescriptor(w: Writer, descriptor: Descriptor, value: any)
	local kind = descriptor.Kind
	local o = descriptor.Options
	if not descriptorUsesBitStream(kind) then flushBits(w) end
	if kind == "Bool" then writeBits(w, value and 1 or 0, 1)
	elseif kind == "UInt" then writeVarUInt(w, value)
	elseif kind == "Int" then writeVarInt(w, value)
	elseif kind == "Float" then writeF64(w, value)
	elseif kind == "String" then writeStringRaw(w, value)
	elseif kind == "CompressedString" then
		local compressed = Compression.CompressString(value, o)
		writeVarUInt(w, buffer.len(compressed))
		flushBits(w)
		ensureCapacity(w, buffer.len(compressed))
		buffer.copy(w.Buffer, w.Position, compressed, 0, buffer.len(compressed))
		w.Position += buffer.len(compressed)
		w.UsedBits += buffer.len(compressed) * 8
	elseif kind == "Buffer" then
		local compressed = Compression.CompressBuffer(value, o)
		writeVarUInt(w, buffer.len(compressed))
		flushBits(w)
		ensureCapacity(w, buffer.len(compressed))
		buffer.copy(w.Buffer, w.Position, compressed, 0, buffer.len(compressed))
		w.Position += buffer.len(compressed)
		w.UsedBits += buffer.len(compressed) * 8
	elseif kind == "Vector2" then writeF64(w, value.X); writeF64(w, value.Y)
	elseif kind == "Vector3" then writeF64(w, value.X); writeF64(w, value.Y); writeF64(w, value.Z)
	elseif kind == "Color3" then
		local byteExact, red, green, blue = exactColor3Bytes(value)
		if byteExact then
			writeByte(w, 0)
			writeByte(w, red)
			writeByte(w, green)
			writeByte(w, blue)
		elseif exactColor3F32(value) then
			writeByte(w, 1)
			writeF32(w, value.R)
			writeF32(w, value.G)
			writeF32(w, value.B)
		else
			writeByte(w, 2)
			writeF64(w, value.R)
			writeF64(w, value.G)
			writeF64(w, value.B)
		end
	elseif kind == "CFrame" then
		local components = {value:GetComponents()}
		for i = 1, 12 do writeF64(w, components[i]) end
	elseif kind == "UDim" then
		writeNumberPayload(w, value.Scale)
		writeVarInt(w, value.Offset)
	elseif kind == "UDim2" then
		writeNumberPayload(w, value.X.Scale)
		writeVarInt(w, value.X.Offset)
		writeNumberPayload(w, value.Y.Scale)
		writeVarInt(w, value.Y.Offset)
	elseif kind == "Rect" then
		writeNumberPayload(w, value.Min.X)
		writeNumberPayload(w, value.Min.Y)
		writeNumberPayload(w, value.Max.X)
		writeNumberPayload(w, value.Max.Y)
	elseif kind == "NumberRange" then
		writeNumberPayload(w, value.Min)
		writeNumberPayload(w, value.Max)
	elseif kind == "BrickColor" then
		writeVarUInt(w, value.Number)
	elseif kind == "DateTime" then
		writeDateTimePayload(w, value)
	elseif kind == "Quantized" then writeBits(w, quantize(value, o.Minimum, o.Maximum, o.Bits), o.Bits)
	elseif kind == "QuantizedVector3" then
		writeBits(w, quantize(value.X, o.Minimum.X, o.Maximum.X, o.Bits), o.Bits)
		writeBits(w, quantize(value.Y, o.Minimum.Y, o.Maximum.Y, o.Bits), o.Bits)
		writeBits(w, quantize(value.Z, o.Minimum.Z, o.Maximum.Z, o.Bits), o.Bits)
	elseif kind == "Array" then
		writeVarUInt(w, #value)
		for _, item in ipairs(value) do writeDescriptor(w, descriptor.Item :: Descriptor, item) end
	elseif kind == "Object" then
		local names = {}
		for name in pairs(descriptor.Fields :: {[string]: Descriptor}) do names[#names + 1] = name end
		table.sort(names)
		for _, name in ipairs(names) do
			local child = (descriptor.Fields :: {[string]: Descriptor})[name]
			local present = value[name] ~= nil
			if child.Optional then writeBits(w, present and 1 or 0, 1) end
			if present then writeDescriptor(w, child, value[name]) end
		end
	end
end

-- Handles read descriptor.
local function readDescriptor(r: Reader, descriptor: Descriptor, binaryVersion: number?): any
	local kind = descriptor.Kind
	local o = descriptor.Options
	if not descriptorUsesBitStream(kind) then alignReader(r) end
	if kind == "Bool" then return readBits(r, 1) == 1
	elseif kind == "UInt" then return readVarUInt(r)
	elseif kind == "Int" then return readVarInt(r)
	elseif kind == "Float" then return readF64(r)
	elseif kind == "String" then return readStringRaw(r)
	elseif kind == "CompressedString" then
		local length = readVarUInt(r)
		alignReader(r)
		if r.Position + length > r.Length then fail("truncated compressed string", 2) end
		local slice = buffer.create(length)
		buffer.copy(slice, 0, r.Buffer, r.Position, length)
		r.Position += length
		return Compression.DecompressString(slice)
	elseif kind == "Buffer" then
		local length = readVarUInt(r)
		alignReader(r)
		if r.Position + length > r.Length then fail("truncated compressed buffer", 2) end
		local slice = buffer.create(length)
		buffer.copy(slice, 0, r.Buffer, r.Position, length)
		r.Position += length
		return Compression.DecompressBuffer(slice)
	elseif kind == "Vector2" then return Vector2.new(readF64(r), readF64(r))
	elseif kind == "Vector3" then return Vector3.new(readF64(r), readF64(r), readF64(r))
	elseif kind == "Color3" then
		alignReader(r)
		if binaryVersion ~= nil and binaryVersion <= 21 then
			return Color3.fromRGB(
				readByte(r),
				readByte(r),
				readByte(r)
			)
		end

		local mode = readByte(r)
		if mode == 0 then
			return Color3.fromRGB(
				readByte(r),
				readByte(r),
				readByte(r)
			)
		elseif mode == 1 then
			return Color3.new(
				readF32(r),
				readF32(r),
				readF32(r)
			)
		elseif mode == 2 then
			return Color3.new(
				readF64(r),
				readF64(r),
				readF64(r)
			)
		end
		fail("invalid schema Color3 mode", 2)
	elseif kind == "CFrame" then
		local components = table.create(12)
		for i = 1, 12 do components[i] = readF64(r) end
		return CFrame.new(table.unpack(components))
	elseif kind == "UDim" then
		return UDim.new(
			readNumberPayload(r),
			readVarInt(r)
		)
	elseif kind == "UDim2" then
		return UDim2.new(
			readNumberPayload(r),
			readVarInt(r),
			readNumberPayload(r),
			readVarInt(r)
		)
	elseif kind == "Rect" then
		return Rect.new(
			readNumberPayload(r),
			readNumberPayload(r),
			readNumberPayload(r),
			readNumberPayload(r)
		)
	elseif kind == "NumberRange" then
		return NumberRange.new(
			readNumberPayload(r),
			readNumberPayload(r)
		)
	elseif kind == "BrickColor" then
		return BrickColor.new(
			readVarUInt(r)
		)
	elseif kind == "DateTime" then
		return readDateTimePayload(r)
	elseif kind == "Quantized" then return dequantize(readBits(r, o.Bits), o.Minimum, o.Maximum, o.Bits)
	elseif kind == "QuantizedVector3" then
		return Vector3.new(
			dequantize(readBits(r, o.Bits), o.Minimum.X, o.Maximum.X, o.Bits),
			dequantize(readBits(r, o.Bits), o.Minimum.Y, o.Maximum.Y, o.Bits),
			dequantize(readBits(r, o.Bits), o.Minimum.Z, o.Maximum.Z, o.Bits)
		)
	elseif kind == "Array" then
		local count = readVarUInt(r)
		if count < 0 or count % 1 ~= 0 then
			fail("invalid schema array count", 2)
		end
		local remaining = r.Length - r.Position
		local hardLimit = math.max(
			16,
			remaining * 8 + 16
		)
		if count > MAX_DECODE_CONTAINER_ITEMS then
			fail(
				"schema array count exceeds decode limit",
				2
			)
		end
		if count > hardLimit then
			fail(
				"schema array count exceeds payload bounds",
				2
			)
		end
		local result = table.create(count)
		for i = 1, count do
			result[i] = readDescriptor(
				r,
				descriptor.Item :: Descriptor,
				binaryVersion
			)
		end
		return result
	elseif kind == "Object" then
		local result = {}
		local names = {}
		for name in pairs(descriptor.Fields :: {[string]: Descriptor}) do names[#names + 1] = name end
		table.sort(names)
		for _, name in ipairs(names) do
			local child = (descriptor.Fields :: {[string]: Descriptor})[name]
			local present = true
			if child.Optional then present = readBits(r, 1) == 1 end
			if present then result[name] = readDescriptor(r, child, binaryVersion) end
		end
		return result
	end
	fail("unsupported descriptor " .. kind, 2)
	return nil
end

-- Handles write header.
local function writeHeader(w: Writer, mode: number, schemaVersion: number?)
	writeByte(w, FMT.MAGIC_A)
	writeByte(w, FMT.MAGIC_B)
	writeByte(w, FMT.VERSION)
	writeByte(w, mode)
	writeVarUInt(w, schemaVersion or 1)
end

-- Handles read header.
local function readHeader(r: Reader, expectedMode: number): (number, number)
	if readByte(r) ~= FMT.MAGIC_A or readByte(r) ~= FMT.MAGIC_B then fail("invalid binary header", 2) end
	local binaryVersion = readByte(r)
	if binaryVersion ~= FMT.VERSION and binaryVersion ~= 24 and binaryVersion ~= 23 and binaryVersion ~= 22 and binaryVersion ~= 21 and binaryVersion ~= 20 and binaryVersion ~= 19 and binaryVersion ~= 18 and binaryVersion ~= 17 and binaryVersion ~= 16 and binaryVersion ~= 15 and binaryVersion ~= 14 and binaryVersion ~= 13 and binaryVersion ~= 12 and binaryVersion ~= 11 and binaryVersion ~= 10 and binaryVersion ~= 9 and binaryVersion ~= 8 and binaryVersion ~= 7 and binaryVersion ~= 6 then fail("unsupported binary version", 2) end
	r.LegacyVarUInt = binaryVersion == 6
	if readByte(r) ~= expectedMode then fail("unexpected binary mode", 2) end
	return readVarUInt(r), binaryVersion
end

-- Handles packet from buffer.
local function packetFromBuffer(
	data: buffer,
	options: Options?,
	schemaVersion: number?,
	rawBits: number?,
	usefulBits: number?,
	paddingBits: number?
): Packet
	local mode = options and options.Mode or "Binary"

	if mode ~= "Binary"
		and mode ~= "BinaryWithHash" then
		fail(
			"invalid Mode " .. tostring(mode),
			2
		)
	end

	local hash = nil

	if mode == "BinaryWithHash" then
		hash = hashBuffer(data)
	end

	local bytes = buffer.len(data)
	local physicalBits = bytes * 8
	local logicalBits = usefulBits
		or physicalBits
	local padding = paddingBits
		or math.max(
			0,
			physicalBits - logicalBits
		)

	local rawBytes = rawBits
		and math.ceil(rawBits / 8)
		or nil

	local byteDelta = rawBytes
		and (rawBytes - bytes)
		or nil

	local savedBytes = byteDelta
		and math.max(0, byteDelta)
		or nil

	local expandedBytes = byteDelta
		and math.max(0, -byteDelta)
		or nil

	local savingsPercent =
		rawBytes
		and rawBytes > 0
		and math.max(
			0,
			(byteDelta :: number)
			/ rawBytes
			* 100
		)
		or 0

	local expansionPercent =
		rawBytes
		and rawBytes > 0
		and math.max(
			0,
			-(byteDelta :: number)
			/ rawBytes
			* 100
		)
		or 0

	local ratio =
		rawBytes
		and rawBytes > 0
		and bytes / rawBytes
		or nil

	local savedBits =
		rawBits ~= nil
		and math.max(
			0,
			(rawBits :: number)
			- logicalBits
		)
		or nil

	local expandedBits =
		rawBits ~= nil
		and math.max(
			0,
			logicalBits
			- (rawBits :: number)
		)
		or nil

	local bitSavingsPercent =
		rawBits ~= nil
		and rawBits > 0
		and math.max(
			0,
			((rawBits :: number)
				- logicalBits)
			/ (rawBits :: number)
			* 100
		)
		or 0

	return {
		Data = data,
		Hash = hash,
		Bytes = bytes,
		Bits = logicalBits,
		UsefulBits = logicalBits,
		PhysicalBits = physicalBits,
		PaddingBits = padding,
		SchemaVersion = schemaVersion,
		RawBytes = rawBytes,
		SavedBytes = savedBytes,
		ExpandedBytes = expandedBytes,
		ByteDelta = byteDelta,
		SavingsPercent = savingsPercent,
		ExpansionPercent = expansionPercent,
		Ratio = ratio,
		IsSmaller = if rawBytes ~= nil
			then bytes < (rawBytes :: number)
			else nil,
		IsPhysicallySmaller = if rawBytes ~= nil
			then bytes < (rawBytes :: number)
			else nil,
		IsBitSmaller = if rawBits ~= nil
			then logicalBits < (rawBits :: number)
			else nil,
		SavedBits = savedBits,
		ExpandedBits = expandedBits,
		BitSavingsPercent = bitSavingsPercent,
	}
end

-- Handles packet from entropy.
local function packetFromEntropy(
	data: buffer,
	options: Options?,
	schemaVersion: number?,
	rawBits: number?,
	usefulBits: number?,
	paddingBits: number?
): Packet
	local alreadyHuffman = isHuffmanFrame(data)
	local entropySourceBytes = buffer.len(data)
	if alreadyHuffman then
		entropySourceBytes = FMT.HuffmanFrameOriginalLength(data) or buffer.len(data)
	end
	local encoded, usedHuffman = maybeHuffman(data, options)
	local packet
	if usedHuffman then
		packet = packetFromBuffer(encoded, options, schemaVersion, rawBits, buffer.len(encoded) * 8, 0)
		packet.Entropy = "Huffman"
		packet.EntropyBytesBefore = entropySourceBytes
		packet.EntropyBytesAfter = buffer.len(encoded)
		packet.EntropySavedBytes = math.max(0, entropySourceBytes - buffer.len(encoded))
	else
		packet = packetFromBuffer(data, options, schemaVersion, rawBits, usefulBits, paddingBits)
		packet.Entropy = "None"
		packet.EntropyBytesBefore = buffer.len(data)
		packet.EntropyBytesAfter = buffer.len(data)
		packet.EntropySavedBytes = 0
	end
	return packet
end

-- Handles mark boolean packet.
local function markBooleanPacket(packet: Packet): Packet
	local rawBits = 8
	local usefulBits = 1
	local physicalBits = packet.Bytes * 8
	packet.Bits = usefulBits
	packet.UsefulBits = usefulBits
	packet.PhysicalBits = physicalBits
	packet.SavedBits = rawBits - usefulBits
	packet.ExpandedBits = 0
	packet.BitSavingsPercent = (rawBits - usefulBits) / rawBits * 100
	packet.SavingsPercent = packet.BitSavingsPercent
	packet.ExpansionPercent = 0
	packet.Ratio = usefulBits / rawBits
	packet.IsSmaller = usefulBits < rawBits
	packet.IsPhysicallySmaller = packet.Bytes < 1
	packet.IsBitSmaller = usefulBits < rawBits
	packet.PaddingBits = math.max(
		0,
		physicalBits - usefulBits
	)
	return packet
end

-- Handles unwrap packet.
local function unwrapPacket(packet: Packet | buffer, options: Options?): (buffer, number?)
	if typeof(packet) == "buffer" then
		local decoded = entropyDecodeIfNeeded(packet)
		return decoded, nil
	end
	if typeof(packet) ~= "table" or typeof((packet :: any).Data) ~= "buffer" then fail("expected Packet or buffer", 2) end
	local object = packet :: Packet
	if object.Hash ~= nil and (not options or options.VerifyHash ~= false) then
		if hashBuffer(object.Data) ~= object.Hash then fail("hash verification failed", 2) end
	end
	local decoded = entropyDecodeIfNeeded(object.Data)
	return decoded, object.SchemaVersion
end

-- Handles raw value bits.
local function rawValueBits(value: any): number
	local kind = typeof(value)
	if kind == "boolean" then return 8
	elseif kind == "number" then return 64
	elseif kind == "string" then return #value * 8
	elseif kind == "Vector2" then return 128
	elseif kind == "Vector3" then return 192
	elseif kind == "Color3" then return 96
	elseif kind == "CFrame" then return 768
	elseif kind == "UDim" then return 96
	elseif kind == "UDim2" then return 192
	elseif kind == "Rect" then return 256
	elseif kind == "NumberRange" then return 128
	elseif kind == "BrickColor" then return 16
	elseif kind == "DateTime" then return 64
	elseif kind == "buffer" then return buffer.len(value) * 8
	elseif kind == "table" then
		local bits = 0
		for key, child in pairs(value) do bits += rawValueBits(key); bits += rawValueBits(child) end
		return bits
	end
	return 0
end

-- Handles clone buffer.
FMT.CloneBuffer = function(value: buffer): buffer
	local length = buffer.len(value)
	local result = buffer.create(length)
	if length > 0 then buffer.copy(result, 0, value, 0, length) end
	return result
end

-- Handles raw auto byte count and codec.
local function rawAutoByteCountAndCodec(value: any): (number?, string?)
	local kind = typeof(value)
	if kind == "nil" then return 0, "PassthroughNil" end
	if kind == "number" then return 8, "PassthroughNumber" end
	if kind == "string" then return #value, "PassthroughString" end
	if kind == "buffer" then return buffer.len(value), "PassthroughBuffer" end
	if kind == "Vector2" then return 16, "PassthroughVector2" end
	if kind == "Vector3" then return 24, "PassthroughVector3" end
	if kind == "Color3" then
		local useF32 = exactColor3F32(value)
		return useF32 and 12 or 24, useF32 and "PassthroughColor3F32" or "PassthroughColor3F64"
	end
	if kind == "CFrame" then return 96, "PassthroughCFrame" end
	if kind == "UDim" then return 12, "PassthroughUDim" end
	if kind == "UDim2" then return 24, "PassthroughUDim2" end
	if kind == "Rect" then return 32, "PassthroughRect" end
	if kind == "NumberRange" then return 16, "PassthroughNumberRange" end
	if kind == "BrickColor" then return 2, "PassthroughBrickColor" end
	if kind == "DateTime" then return 8, "PassthroughDateTime" end
	return nil, nil
end

-- Handles raw auto data.
local function rawAutoData(value: any): (buffer?, string?)
	local kind = typeof(value)

	if kind == "nil" then
		return buffer.create(0), "PassthroughNil"
	elseif kind == "number" then
		local data = buffer.create(8)
		buffer.writef64(data, 0, value)
		return data, "PassthroughNumber"
	elseif kind == "string" then
		local data = buffer.create(#value)
		if #value > 0 then buffer.writestring(data, 0, value) end
		return data, "PassthroughString"
	elseif kind == "buffer" then
		return FMT.CloneBuffer(value), "PassthroughBuffer"
	elseif kind == "Vector2" then
		local data = buffer.create(16)
		buffer.writef64(data, 0, value.X)
		buffer.writef64(data, 8, value.Y)
		return data, "PassthroughVector2"
	elseif kind == "Vector3" then
		local data = buffer.create(24)
		buffer.writef64(data, 0, value.X)
		buffer.writef64(data, 8, value.Y)
		buffer.writef64(data, 16, value.Z)
		return data, "PassthroughVector3"
	elseif kind == "Color3" then
		if exactColor3F32(value) then
			local data = buffer.create(12)
			buffer.writef32(data, 0, value.R)
			buffer.writef32(data, 4, value.G)
			buffer.writef32(data, 8, value.B)
			return data, "PassthroughColor3F32"
		end

		local data = buffer.create(24)
		buffer.writef64(data, 0, value.R)
		buffer.writef64(data, 8, value.G)
		buffer.writef64(data, 16, value.B)
		return data, "PassthroughColor3F64"
	elseif kind == "CFrame" then
		local data = buffer.create(96)
		local components = {value:GetComponents()}
		for i = 1, 12 do buffer.writef64(data, (i - 1) * 8, components[i]) end
		return data, "PassthroughCFrame"
	elseif kind == "UDim" then
		local data = buffer.create(12)
		buffer.writef64(data, 0, value.Scale)
		buffer.writei32(data, 8, value.Offset)
		return data, "PassthroughUDim"
	elseif kind == "UDim2" then
		local data = buffer.create(24)
		buffer.writef64(data, 0, value.X.Scale)
		buffer.writei32(data, 8, value.X.Offset)
		buffer.writef64(data, 12, value.Y.Scale)
		buffer.writei32(data, 20, value.Y.Offset)
		return data, "PassthroughUDim2"
	elseif kind == "Rect" then
		local data = buffer.create(32)
		buffer.writef64(data, 0, value.Min.X)
		buffer.writef64(data, 8, value.Min.Y)
		buffer.writef64(data, 16, value.Max.X)
		buffer.writef64(data, 24, value.Max.Y)
		return data, "PassthroughRect"
	elseif kind == "NumberRange" then
		local data = buffer.create(16)
		buffer.writef64(data, 0, value.Min)
		buffer.writef64(data, 8, value.Max)
		return data, "PassthroughNumberRange"
	elseif kind == "BrickColor" then
		local data = buffer.create(2)
		buffer.writeu16(data, 0, value.Number)
		return data, "PassthroughBrickColor"
	elseif kind == "DateTime" then
		local data = buffer.create(8)
		buffer.writef64(data, 0, value.UnixTimestampMillis)
		return data, "PassthroughDateTime"
	end

	return nil, nil
end

-- Handles decode passthrough packet.
local function decodePassthroughPacket(packet: Packet): (boolean, any)
	if packet.Passthrough ~= true then return false, nil end
	local codec = packet.Codec
	local data = packet.Data
	local length = buffer.len(data)

	if codec == "PassthroughNil" then
		if length ~= 0 then fail("invalid nil passthrough length", 2) end
		return true, nil
	elseif codec == "PassthroughNumber" then
		if length ~= 8 then fail("invalid number passthrough length", 2) end
		return true, buffer.readf64(data, 0)
	elseif codec == "PassthroughString" then
		return true, length > 0 and buffer.readstring(data, 0, length) or ""
	elseif codec == "PassthroughBuffer" then
		return true, FMT.CloneBuffer(data)
	elseif codec == "PassthroughVector2" then
		if length ~= 16 then fail("invalid Vector2 passthrough length", 2) end
		return true, Vector2.new(buffer.readf64(data, 0), buffer.readf64(data, 8))
	elseif codec == "PassthroughVector3" then
		if length ~= 24 then fail("invalid Vector3 passthrough length", 2) end
		return true, Vector3.new(buffer.readf64(data, 0), buffer.readf64(data, 8), buffer.readf64(data, 16))
	elseif codec == "PassthroughColor3F32" then
		if length ~= 12 then fail("invalid Color3 float32 passthrough length", 2) end
		return true, Color3.new(buffer.readf32(data, 0), buffer.readf32(data, 4), buffer.readf32(data, 8))
	elseif codec == "PassthroughColor3F64" then
		if length ~= 24 then fail("invalid Color3 float64 passthrough length", 2) end
		return true, Color3.new(buffer.readf64(data, 0), buffer.readf64(data, 8), buffer.readf64(data, 16))
	elseif codec == "PassthroughCFrame" then
		if length ~= 96 then fail("invalid CFrame passthrough length", 2) end
		local components = table.create(12)
		for i = 1, 12 do components[i] = buffer.readf64(data, (i - 1) * 8) end
		return true, CFrame.new(table.unpack(components))
	elseif codec == "PassthroughUDim" then
		if length ~= 12 then fail("invalid UDim passthrough length", 2) end
		return true, UDim.new(buffer.readf64(data, 0), buffer.readi32(data, 8))
	elseif codec == "PassthroughUDim2" then
		if length ~= 24 then fail("invalid UDim2 passthrough length", 2) end
		return true, UDim2.new(
			buffer.readf64(data, 0),
			buffer.readi32(data, 8),
			buffer.readf64(data, 12),
			buffer.readi32(data, 20)
		)
	elseif codec == "PassthroughRect" then
		if length ~= 32 then fail("invalid Rect passthrough length", 2) end
		return true, Rect.new(
			buffer.readf64(data, 0),
			buffer.readf64(data, 8),
			buffer.readf64(data, 16),
			buffer.readf64(data, 24)
		)
	elseif codec == "PassthroughNumberRange" then
		if length ~= 16 then fail("invalid NumberRange passthrough length", 2) end
		return true, NumberRange.new(buffer.readf64(data, 0), buffer.readf64(data, 8))
	elseif codec == "PassthroughBrickColor" then
		if length ~= 2 then fail("invalid BrickColor passthrough length", 2) end
		return true, BrickColor.new(buffer.readu16(data, 0))
	elseif codec == "PassthroughDateTime" then
		if length ~= 8 then fail("invalid DateTime passthrough length", 2) end
		return true, DateTime.fromUnixTimestampMillis(buffer.readf64(data, 0))
	end

	fail("unknown passthrough codec " .. tostring(codec), 2)
	return false, nil
end

local Schema = {}
Schema.__index = Schema

-- Handles schema.
function Compression.Schema(definition: {[string]: Descriptor}, version: number?): SchemaObject
	if typeof(definition) ~= "table" then fail("Schema expects descriptor table", 2) end
	local schemaVersion = version or 1
	if not isSafeUInt(schemaVersion) or schemaVersion < 1 then
		fail("Schema version must be a positive safe integer", 2)
	end
	local fields = {}
	for name, descriptor in pairs(definition) do
		if typeof(name) ~= "string" then fail("schema field names must be strings", 2) end
		if typeof(descriptor) ~= "table" or typeof(descriptor.Kind) ~= "string" then fail("invalid descriptor for field " .. name, 2) end
		fields[#fields + 1] = {Name = name, Descriptor = descriptor}
	end
	table.sort(fields, function(a, b) return a.Name < b.Name end)
	return setmetatable({Fields = fields, Version = schemaVersion}, Schema) :: any
end

-- Handles schema.
function Schema:Encode(value: {[string]: any}, options: Options?): Packet
	if typeof(value) ~= "table" then
		fail(
			"Schema:Encode expects table",
			2
		)
	end

	local w = newWriter()
	writeHeader(w, MODE.SCHEMA, self.Version)
	for _, field in ipairs(self.Fields) do
		local descriptor = field.Descriptor
		local fieldValue = value[field.Name]
		local present = fieldValue ~= nil
		if descriptor.Optional then writeBits(w, present and 1 or 0, 1)
		elseif not present then fail("missing required field " .. field.Name, 2) end
		if present then validate(descriptor, fieldValue, field.Name); writeDescriptor(w, descriptor, fieldValue) end
	end
	local data = finish(w)
	return packetFromEntropy(
		data,
		options,
		self.Version,
		rawValueBits(value),
		w.UsedBits,
		w.PaddingBits
	)
end

-- Handles schema.
function Schema:Decode(packet: Packet | buffer, options: Options?): {[string]: any}
	local data, packetVersion = unwrapPacket(packet, options)
	local r = newReader(data)
	local encodedVersion, binaryVersion = readHeader(r, MODE.SCHEMA)
	if packetVersion ~= nil and packetVersion ~= encodedVersion then fail("packet/schema version mismatch", 2) end
	if encodedVersion ~= self.Version then fail("schema version mismatch", 2) end
	local result = {}
	for _, field in ipairs(self.Fields) do
		local descriptor = field.Descriptor
		local present = true
		if descriptor.Optional then present = readBits(r, 1) == 1 end
		if present then result[field.Name] = readDescriptor(r, descriptor, binaryVersion) end
	end
	alignReader(r)
	if r.Position ~= r.Length then fail("trailing bytes in schema payload", 2) end
	return result
end

-- Handles schema.
function Schema:EncodeDelta(previous: {[string]: any}, current: {[string]: any}, options: Options?): Packet
	if typeof(previous) ~= "table"
		or typeof(current) ~= "table" then
		fail(
			"Schema:EncodeDelta expects previous and current tables",
			2
		)
	end

	for _, field in ipairs(self.Fields) do
		local descriptor =
			field.Descriptor
		local value =
			current[field.Name]

		if value == nil then
			if not descriptor.Optional then
				fail(
					"missing required field "
						.. field.Name,
					2
				)
			end
		else
			validate(
				descriptor,
				value,
				field.Name
			)
		end
	end

	local w = newWriter()
	writeHeader(
		w,
		MODE.DELTA,
		self.Version
	)

	for _, field in ipairs(self.Fields) do
		writeBits(
			w,
			FMT.DeepEqual(
				previous[field.Name],
				current[field.Name]
			)
				and 0
				or 1,
			1
		)
	end

	for _, field in ipairs(self.Fields) do
		if not FMT.DeepEqual(
			previous[field.Name],
			current[field.Name]
			) then
			local value =
				current[field.Name]

			writeBits(
				w,
				value ~= nil
					and 1
					or 0,
				1
			)

			if value ~= nil then
				writeDescriptor(
					w,
					field.Descriptor,
					value
				)
			end
		end
	end

	local data =
		finish(w)

	return packetFromEntropy(
		data,
		options,
		self.Version,
		rawValueBits(current),
		w.UsedBits,
		w.PaddingBits
	)
end

-- Handles schema.
function Schema:DecodeDelta(previous: {[string]: any}, packet: Packet | buffer, options: Options?): {[string]: any}
	if typeof(previous) ~= "table" then
		fail(
			"Schema:DecodeDelta expects previous table",
			2
		)
	end

	local data, packetVersion =
		unwrapPacket(
			packet,
			options
		)
	local r = newReader(data)
	local version, binaryVersion =
		readHeader(
			r,
			MODE.DELTA
		)

	if packetVersion ~= nil
		and packetVersion ~= version then
		fail(
			"packet/schema version mismatch",
			2
		)
	end

	if version ~= self.Version then
		fail(
			"schema version mismatch",
			2
		)
	end

	local changed =
		table.create(
			#self.Fields
		)

	for i = 1, #self.Fields do
		changed[i] =
			readBits(r, 1) == 1
	end

	local result =
		table.clone(previous)

	for i, field in ipairs(self.Fields) do
		if changed[i] then
			local present =
				readBits(r, 1) == 1

			if present then
				result[field.Name] =
					readDescriptor(
						r,
						field.Descriptor,
						binaryVersion
					)
			else
				if not field.Descriptor.Optional then
					fail(
						"delta removed required field "
							.. field.Name,
						2
					)
				end

				result[field.Name] = nil
			end
		end
	end

	alignReader(r)

	if r.Position ~= r.Length then
		fail(
			"trailing bytes in delta payload",
			2
		)
	end

	for _, field in ipairs(self.Fields) do
		local value =
			result[field.Name]

		if value == nil then
			if not field.Descriptor.Optional then
				fail(
					"missing required field "
						.. field.Name,
					2
				)
			end
		else
			validate(
				field.Descriptor,
				value,
				field.Name
			)
		end
	end

	return result
end

-- Handles schema.
function Schema:AnalyzeBits(value: {[string]: any}): BitLayout
	if typeof(value) ~= "table" then
		fail(
			"Schema:AnalyzeBits expects table",
			2
		)
	end

	local w = newWriter()
	local fields = {}
	local rawBits = 0
	writeHeader(w, MODE.SCHEMA, self.Version)
	local headerBits = w.UsedBits
	for _, field in ipairs(self.Fields) do
		local descriptor = field.Descriptor
		local fieldValue = value[field.Name]
		local present = fieldValue ~= nil
		local usedBefore = w.UsedBits
		local paddingBefore = w.PaddingBits
		if descriptor.Optional then writeBits(w, present and 1 or 0, 1)
		elseif not present then fail("missing required field " .. field.Name, 2) end
		if present then validate(descriptor, fieldValue, field.Name); writeDescriptor(w, descriptor, fieldValue) end
		local useful = w.UsedBits - usedBefore
		local padding = w.PaddingBits - paddingBefore
		local raw = present and rawValueBits(fieldValue) or 0
		local physical = useful + padding
		local delta = raw - physical
		local saved = math.max(0, delta)
		local expanded = math.max(0, -delta)
		rawBits += raw
		fields[#fields + 1] = {
			Name = field.Name, Type = descriptor.Kind, Present = present,
			UsefulBits = useful, PaddingBits = padding, PhysicalBits = physical,
			RawBits = raw, SavedBits = saved, ExpandedBits = expanded,
			SavingsPercent = raw > 0 and math.max(0, (delta / raw) * 100) or 0,
		}
	end
	local data = finish(w)
	local physicalBits = buffer.len(data) * 8
	local deltaBits = rawBits - physicalBits
	local savedBits = math.max(0, deltaBits)
	local expandedBits = math.max(0, -deltaBits)
	return {
		HeaderBits = headerBits, UsefulBits = w.UsedBits, PaddingBits = w.PaddingBits,
		PhysicalBits = physicalBits, PhysicalBytes = buffer.len(data), RawBits = rawBits,
		SavedBits = savedBits, ExpandedBits = expandedBits,
		SavingsPercent = rawBits > 0 and math.max(0, (deltaBits / rawBits) * 100) or 0,
		Fields = fields,
	}
end

-- Handles schema.
function Schema:PrintBitLayout(value: {[string]: any}): BitLayout
	local layout = self:AnalyzeBits(value)
	print("========== Compression v2.6.0 Bit Layout ==========")
	print("Header bits:", layout.HeaderBits)
	for _, field in ipairs(layout.Fields) do
		print(string.format(
			"%s [%s] | useful=%d bits | padding=%d | physical=%d | raw=%d | saved=%.2f%%",
			field.Name, field.Type, field.UsefulBits, field.PaddingBits, field.PhysicalBits, field.RawBits, field.SavingsPercent
			))
	end
	print("---------------------------------------------------")
	print("Useful bits:", layout.UsefulBits)
	print("Padding bits:", layout.PaddingBits)
	print("Physical:", layout.PhysicalBits, "bits /", layout.PhysicalBytes, "bytes")
	print("Raw:", layout.RawBits, "bits")
	print("Saved:", layout.SavedBits, "bits")
	print("Expanded:", layout.ExpandedBits, "bits")
	print(string.format("Savings: %.2f%%", layout.SavingsPercent))
	print("===================================================")
	return layout
end

-- Handles write compact string.
local function writeCompactString(w: Writer, value: string, options: Options?, dictionary: DictionaryState)
	local id = dictionary.Encode[value]
	if id then
		writeVarUInt(w, id * 2 + 1)
		return
	end
	local packed = Compression.CompressString(value, options)
	writeVarUInt(w, buffer.len(packed) * 2)
	flushBits(w)
	ensureCapacity(w, buffer.len(packed))
	buffer.copy(w.Buffer, w.Position, packed, 0, buffer.len(packed))
	w.Position += buffer.len(packed)
	w.UsedBits += buffer.len(packed) * 8
end

-- Handles read compact string.
local function readCompactString(r: Reader, dictionary: DictionaryState): string
	local token = readVarUInt(r)
	if token % 2 == 1 then
		local id = (token - 1) / 2
		local value = dictionary.Decode[id]
		if value == nil then fail("invalid string dictionary reference", 2) end
		return value
	end
	local length = token / 2
	if r.Position + length > r.Length then fail("truncated compact string", 2) end
	local data = buffer.create(length)
	buffer.copy(data, 0, r.Buffer, r.Position, length)
	r.Position += length
	return Compression.DecompressString(data)
end

-- Handles sorted map keys.
local function sortedMapKeys(value: {[any]: any}): {any}
	local keys = {}
	for key in pairs(value) do
		local keyType = typeof(key)
		if keyType ~= "string" and keyType ~= "number" then fail("map keys must be strings or numbers", 2) end
		keys[#keys + 1] = key
	end
	table.sort(keys, function(a, b)
		local ta = typeof(a)
		local tb = typeof(b)
		if ta ~= tb then return ta < tb end
		if ta == "number" then return a < b end
		return a < b
	end)
	return keys
end

-- Handles classify array.
local function classifyArray(value: {any}): string
	local count = #value
	if count == 0 then return "Mixed" end
	local firstType = typeof(value[1])
	if firstType == "boolean" then
		for i = 2, count do if typeof(value[i]) ~= "boolean" then return "Mixed" end end
		return "Bool"
	elseif firstType == "string" then
		for i = 2, count do if typeof(value[i]) ~= "string" then return "Mixed" end end
		return "String"
	elseif firstType == "number" then
		local allUInt = true
		local allInt = true
		for i = 1, count do
			local item = value[i]
			if typeof(item) ~= "number" then return "Mixed" end
			if not isSafeUInt(item) then allUInt = false end
			if not isSafeInt(item) then allInt = false end
		end
		if allUInt then return "UInt" end
		if allInt then return "Int" end
		return "Float"
	elseif firstType == "Vector2"
		or firstType == "Vector3"
		or firstType == "Color3"
		or firstType == "UDim"
		or firstType == "UDim2"
		or firstType == "NumberRange"
		or firstType == "BrickColor"
		or firstType == "Rect"
		or firstType == "DateTime" then
		for i = 2, count do
			if typeof(value[i]) ~= firstType then
				return "Mixed"
			end
		end
		return firstType
	end
	return "Mixed"
end

-- Handles count scalar runs.
local function countScalarRuns(value: {any}): number
	if #value == 0 then return 0 end
	local firstType = typeof(value[1])
	if firstType ~= "boolean" and firstType ~= "number" and firstType ~= "string" then return #value end
	local runs = 1
	local previous = value[1]
	for i = 2, #value do
		if value[i] ~= previous then
			runs += 1
			previous = value[i]
		end
	end
	return runs
end

-- Handles can use uint delta.
local function canUseUIntDelta(value: {any}): boolean
	if #value < 3 then return false end
	local normalBytes = varUIntByteLength(value[1])
	local deltaBytes = normalBytes
	for i = 2, #value do
		normalBytes += varUIntByteLength(value[i])
		local delta = value[i] - value[i - 1]
		if not isSafeInt(delta) then return false end
		deltaBytes += varIntByteLength(delta)
	end
	return deltaBytes < normalBytes
end

-- Handles can use int delta.
local function canUseIntDelta(value: {any}): boolean
	if #value < 3 then return false end
	local normalBytes = varIntByteLength(value[1])
	local deltaBytes = normalBytes
	for i = 2, #value do
		normalBytes += varIntByteLength(value[i])
		local delta = value[i] - value[i - 1]
		if not isSafeInt(delta) then return false end
		deltaBytes += varIntByteLength(delta)
	end
	return deltaBytes < normalBytes
end

-- Handles power10 exponent.
local function power10Exponent(value: number): number?
	if value == 0 or value ~= value or value == math.huge or value == -math.huge then return nil end
	local absolute = math.abs(value)
	local exponent = math.floor(math.log10(absolute) + 0.5)
	if exponent < -308 or exponent > 308 then return nil end
	if 10 ^ exponent == absolute then return exponent end
	return nil
end

-- Handles decimal candidate.
local function decimalCandidate(value: number): (number?, number?)
	if value ~= value or value == math.huge or value == -math.huge then return nil, nil end
	local bestInteger: number? = nil
	local bestScale: number? = nil
	local bestBytes = math.huge

	for scale = 1, 12 do
		local factor = 10 ^ scale
		local scaled = value * factor
		if scaled == scaled and scaled ~= math.huge and scaled ~= -math.huge and math.abs(scaled) <= MAX_SAFE_ZIGZAG_INTEGER then
			local integer = math.round(scaled)
			if integer / factor == value then
				local bytes = 2 + varIntByteLength(integer)
				if bytes < bestBytes then
					bestBytes = bytes
					bestInteger = integer
					bestScale = scale
				end
			end
		end
	end

	return bestInteger, bestScale
end

writeNumberPayload = function(w: Writer, value: number)
	if value == 0 then
		writeByte(w, TAG.ZERO)
	elseif value == 1 then
		writeByte(w, TAG.ONE)
	elseif value == -1 then
		writeByte(w, TAG.NEG_ONE)
	else
		local exponent = power10Exponent(value)
		if exponent ~= nil then
			writeByte(w, TAG.POWER10)
			local sign = value < 0 and 1 or 0
			writeVarUInt(w, zigzagEncode(exponent) * 2 + sign)
		elseif isSafeUInt(value) then
			writeByte(w, TAG.UINT)
			writeVarUInt(w, value)
		elseif isSafeInt(value) then
			writeByte(w, TAG.INT)
			writeVarInt(w, value)
		else
			local decimalInteger, decimalScale = decimalCandidate(value)
			local decimalBytes = if decimalInteger ~= nil and decimalScale ~= nil then 2 + varIntByteLength(decimalInteger) else math.huge
			local float32Bytes = exactFloat32(value) and 5 or math.huge

			if decimalBytes < float32Bytes and decimalBytes < 9 then
				writeByte(w, TAG.DECIMAL)
				writeByte(w, decimalScale :: number)
				writeVarInt(w, decimalInteger :: number)
			elseif float32Bytes < 9 then
				writeByte(w, TAG.FLOAT32)
				writeF32(w, value)
			elseif decimalBytes < 9 then
				writeByte(w, TAG.DECIMAL)
				writeByte(w, decimalScale :: number)
				writeVarInt(w, decimalInteger :: number)
			else
				writeByte(w, TAG.FLOAT)
				writeF64(w, value)
			end
		end
	end
end

readNumberPayload = function(r: Reader): number
	alignReader(r)
	local tag = readByte(r)
	if tag == TAG.ZERO then return 0 end
	if tag == TAG.ONE then return 1 end
	if tag == TAG.NEG_ONE then return -1 end
	if tag == TAG.UINT then return readVarUInt(r) end
	if tag == TAG.INT then return readVarInt(r) end
	if tag == TAG.FLOAT then return readF64(r) end
	if tag == TAG.FLOAT32 then return readF32(r) end
	if tag == TAG.DECIMAL then
		local scale = readByte(r)
		if scale < 1 or scale > 12 then fail("invalid decimal payload scale", 2) end
		return readVarInt(r) / 10 ^ scale
	end
	if tag == TAG.POWER10 then
		local code = readVarUInt(r)
		local sign = code % 2
		local exponent = zigzagDecode(math.floor(code / 2))
		local value = 10 ^ exponent
		return sign == 1 and -value or value
	end
	fail("invalid number payload", 2)
	return 0
end

writeDateTimePayload = function(w: Writer, value: any)
	local millis = value.UnixTimestampMillis
	local seconds = math.floor(millis / 1000)
	local remainder = millis - seconds * 1000
	writeVarInt(w, seconds)
	writeVarUInt(w, remainder)
end

readDateTimePayload = function(r: Reader): any
	local seconds = readVarInt(r)
	local remainder = readVarUInt(r)
	if remainder > 999 then
		fail("invalid DateTime millisecond remainder", 2)
	end
	return DateTime.fromUnixTimestampMillis(
		seconds * 1000 + remainder
	)
end

-- Handles write atom number.
local function writeAtomNumber(w: Writer, value: number)
	if value == 0 then
		writeByte(w, ATOM.ZERO)
	elseif value == 1 then
		writeByte(w, ATOM.ONE)
	elseif value == -1 then
		writeByte(w, ATOM.NEG_ONE)
	else
		local exponent = power10Exponent(value)
		if exponent ~= nil then
			writeByte(w, ATOM.POWER10)
			local sign = value < 0 and 1 or 0
			writeVarUInt(w, zigzagEncode(exponent) * 2 + sign)
		elseif isSafeUInt(value) then
			writeByte(w, ATOM.UINT)
			writeVarUInt(w, value)
		elseif isSafeInt(value) then
			writeByte(w, ATOM.INT)
			writeVarInt(w, value)
		else
			local decimalInteger, decimalScale = decimalCandidate(value)
			local decimalBytes = if decimalInteger ~= nil and decimalScale ~= nil then 2 + varIntByteLength(decimalInteger) else math.huge
			local float32Bytes = exactFloat32(value) and 5 or math.huge

			if decimalBytes < float32Bytes and decimalBytes < 9 then
				writeByte(w, ATOM.DECIMAL)
				writeByte(w, decimalScale :: number)
				writeVarInt(w, decimalInteger :: number)
			elseif float32Bytes < 9 then
				writeByte(w, ATOM.FLOAT32)
				writeF32(w, value)
			elseif decimalBytes < 9 then
				writeByte(w, ATOM.DECIMAL)
				writeByte(w, decimalScale :: number)
				writeVarInt(w, decimalInteger :: number)
			else
				writeByte(w, ATOM.FLOAT)
				writeF64(w, value)
			end
		end
	end
end

-- Handles encode compact atom.
local function encodeCompactAtom(value: any, options: Options?): buffer?
	local kind = typeof(value)
	local w = newWriter(32)

	if kind == "nil" then
		writeByte(w, ATOM.NIL)
	elseif kind == "boolean" then
		writeByte(w, value and ATOM.TRUE or ATOM.FALSE)
	elseif kind == "number" then
		writeAtomNumber(w, value)
	elseif kind == "string" then
		writeByte(w, ATOM.STRING)
		local packed = Compression.CompressString(value, options)
		ensureCapacity(w, buffer.len(packed))
		if buffer.len(packed) > 0 then buffer.copy(w.Buffer, w.Position, packed, 0, buffer.len(packed)) end
		w.Position += buffer.len(packed)
		w.UsedBits += buffer.len(packed) * 8
	elseif kind == "Vector2" then
		writeByte(w, ATOM.VECTOR2)
		writeNumberPayload(w, value.X)
		writeNumberPayload(w, value.Y)
		local normal = finish(w)

		if exactFloat32(value.X)
			and exactFloat32(value.Y) then
			local f = newWriter(9)
			writeByte(f, ATOM.VECTOR2_F32)
			writeF32(f, value.X)
			writeF32(f, value.Y)
			return chooseSmaller(normal, finish(f))
		end

		return normal
	elseif kind == "Vector3" then
		writeByte(w, ATOM.VECTOR3)
		writeNumberPayload(w, value.X)
		writeNumberPayload(w, value.Y)
		writeNumberPayload(w, value.Z)
		local normal = finish(w)

		if exactFloat32(value.X)
			and exactFloat32(value.Y)
			and exactFloat32(value.Z) then
			local f = newWriter(13)
			writeByte(f, ATOM.VECTOR3_F32)
			writeF32(f, value.X)
			writeF32(f, value.Y)
			writeF32(f, value.Z)
			return chooseSmaller(normal, finish(f))
		end

		return normal
	elseif kind == "Color3" then
		local byteExact, r, g, b = exactColor3Bytes(value)

		if byteExact then
			writeByte(w, ATOM.COLOR3)
			writeByte(w, r)
			writeByte(w, g)
			writeByte(w, b)
		elseif exactColor3F32(value) then
			writeByte(w, ATOM.COLOR3_F32)
			writeF32(w, value.R)
			writeF32(w, value.G)
			writeF32(w, value.B)
		else
			writeByte(w, ATOM.COLOR3_F64)
			writeF64(w, value.R)
			writeF64(w, value.G)
			writeF64(w, value.B)
		end
	elseif kind == "CFrame" then
		local components = {value:GetComponents()}

		writeByte(w, ATOM.CFRAME)
		for i = 1, 12 do writeNumberPayload(w, components[i]) end
		local normal = finish(w)

		local useF32 = true

		for i = 1, 12 do
			if not exactFloat32(components[i]) then
				useF32 = false
				break
			end
		end

		if useF32 then
			local f = newWriter(49)
			writeByte(f, ATOM.CFRAME_F32)
			for i = 1, 12 do writeF32(f, components[i]) end
			return chooseSmaller(normal, finish(f))
		end

		return normal
	elseif kind == "UDim" then
		writeByte(w, ATOM.UDIM)
		writeNumberPayload(w, value.Scale)
		writeVarInt(w, value.Offset)
	elseif kind == "UDim2" then
		writeByte(w, ATOM.UDIM2)
		writeNumberPayload(w, value.X.Scale)
		writeVarInt(w, value.X.Offset)
		writeNumberPayload(w, value.Y.Scale)
		writeVarInt(w, value.Y.Offset)
	elseif kind == "Rect" then
		writeByte(w, ATOM.RECT)
		writeNumberPayload(w, value.Min.X)
		writeNumberPayload(w, value.Min.Y)
		writeNumberPayload(w, value.Max.X)
		writeNumberPayload(w, value.Max.Y)
	elseif kind == "NumberRange" then
		writeByte(w, ATOM.NUMBER_RANGE)
		writeNumberPayload(w, value.Min)
		writeNumberPayload(w, value.Max)
	elseif kind == "BrickColor" then
		writeByte(w, ATOM.BRICK_COLOR)
		writeVarUInt(w, value.Number)
	elseif kind == "DateTime" then
		writeByte(w, ATOM.DATETIME)
		writeDateTimePayload(w, value)
	else
		return nil
	end

	return finish(w)
end

-- Handles is compact atom tag.
local function isCompactAtomTag(tag: number): boolean
	return tag >= ATOM.NIL and tag <= ATOM.DATETIME
end

-- Handles decode compact atom.
local function decodeCompactAtom(data: buffer): (boolean, any)
	if buffer.len(data) < 1 then return false, nil end
	local first = buffer.readu8(data, 0)
	if not isCompactAtomTag(first) then return false, nil end

	local r = newReader(data)
	local tag = readByte(r)
	local value: any

	if tag == ATOM.NIL then
		value = nil
	elseif tag == ATOM.FALSE then
		value = false
	elseif tag == ATOM.TRUE then
		value = true
	elseif tag == ATOM.ZERO then
		value = 0
	elseif tag == ATOM.ONE then
		value = 1
	elseif tag == ATOM.NEG_ONE then
		value = -1
	elseif tag == ATOM.UINT then
		value = readVarUInt(r)
	elseif tag == ATOM.INT then
		value = readVarInt(r)
	elseif tag == ATOM.FLOAT then
		value = readF64(r)
	elseif tag == ATOM.FLOAT32 then
		value = readF32(r)
	elseif tag == ATOM.DECIMAL then
		local scale = readByte(r)
		if scale < 1 or scale > 12 then fail("invalid decimal atom scale", 2) end
		value = readVarInt(r) / 10 ^ scale
	elseif tag == ATOM.POWER10 then
		local code = readVarUInt(r)
		local sign = code % 2
		local exponent = zigzagDecode(math.floor(code / 2))
		local result = 10 ^ exponent
		value = sign == 1 and -result or result
	elseif tag == ATOM.STRING then
		local length = r.Length - r.Position
		if length == 0 then
			value = ""
		else
			local packed = buffer.create(length)
			buffer.copy(
				packed,
				0,
				r.Buffer,
				r.Position,
				length
			)
			r.Position = r.Length
			value = Compression.DecompressString(
				packed
			)
		end
	elseif tag == ATOM.VECTOR2 then
		value = Vector2.new(readNumberPayload(r), readNumberPayload(r))
	elseif tag == ATOM.VECTOR2_F32 then
		value = Vector2.new(readF32(r), readF32(r))
	elseif tag == ATOM.VECTOR3 then
		value = Vector3.new(readNumberPayload(r), readNumberPayload(r), readNumberPayload(r))
	elseif tag == ATOM.VECTOR3_F32 then
		value = Vector3.new(readF32(r), readF32(r), readF32(r))
	elseif tag == ATOM.COLOR3 then
		value = Color3.fromRGB(readByte(r), readByte(r), readByte(r))
	elseif tag == ATOM.COLOR3_F32 then
		value = Color3.new(readF32(r), readF32(r), readF32(r))
	elseif tag == ATOM.COLOR3_F64 then
		value = Color3.new(readF64(r), readF64(r), readF64(r))
	elseif tag == ATOM.CFRAME then
		local components = table.create(12)
		for i = 1, 12 do components[i] = readNumberPayload(r) end
		value = CFrame.new(table.unpack(components))
	elseif tag == ATOM.CFRAME_F32 then
		local components = table.create(12)
		for i = 1, 12 do components[i] = readF32(r) end
		value = CFrame.new(table.unpack(components))
	elseif tag == ATOM.UDIM then
		value = UDim.new(
			readNumberPayload(r),
			readVarInt(r)
		)
	elseif tag == ATOM.UDIM2 then
		value = UDim2.new(
			readNumberPayload(r),
			readVarInt(r),
			readNumberPayload(r),
			readVarInt(r)
		)
	elseif tag == ATOM.RECT then
		value = Rect.new(
			readNumberPayload(r),
			readNumberPayload(r),
			readNumberPayload(r),
			readNumberPayload(r)
		)
	elseif tag == ATOM.NUMBER_RANGE then
		value = NumberRange.new(
			readNumberPayload(r),
			readNumberPayload(r)
		)
	elseif tag == ATOM.BRICK_COLOR then
		value = BrickColor.new(
			readVarUInt(r)
		)
	elseif tag == ATOM.DATETIME then
		value = readDateTimePayload(r)
	else
		return false, nil
	end

	alignReader(r)
	if r.Position ~= r.Length then fail("trailing bytes in compact atom", 2) end
	return true, value
end

local CT = {
	VALUE_NIL = 0x00,
	VALUE_FALSE = 0x01,
	VALUE_TRUE = 0x02,
	VALUE_STRING = 0x03,
	VALUE_FLOAT = 0x04,
	VALUE_UINT = 0x05,
	VALUE_INT = 0x06,
	VALUE_POWER10 = 0x07,
	VALUE_VECTOR2 = 0x08,
	VALUE_VECTOR3 = 0x09,
	VALUE_COLOR3 = 0x0A,
	VALUE_CFRAME = 0x0B,
	VALUE_BUFFER = 0x0C,
	VALUE_COLOR3_F32 = 0x0D,
	VALUE_COLOR3_F64 = 0x0E,
	VALUE_FLOAT32 = 0x0F,

	SMALL_ARRAY = 0x10,
	SMALL_STRING_MAP = 0x20,
	SMALL_MAP = 0x30,
	SMALL_BOOL_ARRAY = 0x40,
	SMALL_UINT_ARRAY = 0x50,
	SMALL_STRING_ARRAY = 0x60,

	ARRAY_EXT = 0x70,
	STRING_MAP_EXT = 0x71,
	MAP_EXT = 0x72,
	BOOL_ARRAY_EXT = 0x73,
	UINT_ARRAY_EXT = 0x74,
	INT_ARRAY_EXT = 0x75,
	FLOAT_ARRAY_EXT = 0x76,
	STRING_ARRAY_EXT = 0x77,
	UINT_DELTA_EXT = 0x78,
	INT_DELTA_EXT = 0x79,
	RLE_ARRAY_EXT = 0x7A,
	VALUE_DECIMAL = 0x7B,
	VALUE_VECTOR2_F32 = 0x7C,
	VALUE_VECTOR3_F32 = 0x7D,
	VALUE_CFRAME_F32 = 0x7E,
	FLOAT32_ARRAY_EXT = 0x7F,
	INLINE_UINT_BASE = 0x80,
}

local TINY = {
	RAW_EXT = 0x80,
	IDENTIFIER_EXT = 0x81,
	ASCII_EXT = 0x82,
	NUMERIC_EXT = 0x83,
}

-- Handles append buffer.
local function appendBuffer(w: Writer, data: buffer)
	flushBits(w)
	local length = buffer.len(data)
	ensureCapacity(w, length)
	buffer.copy(w.Buffer, w.Position, data, 0, length)
	w.Position += length
	w.UsedBits += length * 8
end

-- Handles tiny string mode.
local function tinyStringMode(value: string): (number, number)
	local length = #value
	local headerBytes = length <= 31 and 1 or 1 + varUIntByteLength(length)
	local bestMode = 0
	local bestBytes = headerBytes + length

	local identifier = true
	local ascii = true
	local numeric = length > 0
	for i = 1, length do
		local byte = string.byte(value, i)
		if IDENTIFIER_ENCODE[byte] == nil then identifier = false end
		if byte > 127 then ascii = false end
		if NUMERIC4_ENCODE[byte] == nil then numeric = false end
	end

	if identifier then
		local bytes = headerBytes + math.ceil(length * 6 / 8)
		if bytes < bestBytes then bestMode = 1; bestBytes = bytes end
	end
	if ascii then
		local bytes = headerBytes + math.ceil(length * 7 / 8)
		if bytes < bestBytes then bestMode = 2; bestBytes = bytes end
	end
	if numeric then
		local bytes = headerBytes + math.ceil(length * 4 / 8)
		if bytes < bestBytes then bestMode = 3; bestBytes = bytes end
	end
	return bestMode, bestBytes
end

-- Handles write tiny string.
local function writeTinyString(w: Writer, value: string)
	flushBits(w)
	local length = #value
	local mode = tinyStringMode(value)
	if length <= 31 then
		if mode == 0 then writeByte(w, length)
		elseif mode == 1 then writeByte(w, 0x20 + length)
		elseif mode == 2 then writeByte(w, 0x40 + length)
		else writeByte(w, 0x60 + length) end
	else
		if mode == 0 then writeByte(w, TINY.RAW_EXT)
		elseif mode == 1 then writeByte(w, TINY.IDENTIFIER_EXT)
		elseif mode == 2 then writeByte(w, TINY.ASCII_EXT)
		else writeByte(w, TINY.NUMERIC_EXT) end
		writeVarUInt(w, length)
	end

	if mode == 0 then
		ensureCapacity(w, length)
		if length > 0 then buffer.writestring(w.Buffer, w.Position, value) end
		w.Position += length
		w.UsedBits += length * 8
	elseif mode == 1 then
		for i = 1, length do writeBits(w, IDENTIFIER_ENCODE[string.byte(value, i)] :: number, 6) end
		flushBits(w)
	elseif mode == 2 then
		for i = 1, length do writeBits(w, string.byte(value, i), 7) end
		flushBits(w)
	else
		for i = 1, length do writeBits(w, NUMERIC4_ENCODE[string.byte(value, i)] :: number, 4) end
		flushBits(w)
	end
end

-- Handles read tiny string.
local function readTinyString(r: Reader): string
	alignReader(r)
	local header = readByte(r)
	local mode: number
	local length: number
	if header <= 0x1F then mode = 0; length = header
	elseif header <= 0x3F then mode = 1; length = header - 0x20
	elseif header <= 0x5F then mode = 2; length = header - 0x40
	elseif header <= 0x7F then mode = 3; length = header - 0x60
	elseif header == TINY.RAW_EXT then mode = 0; length = readVarUInt(r)
	elseif header == TINY.IDENTIFIER_EXT then mode = 1; length = readVarUInt(r)
	elseif header == TINY.ASCII_EXT then mode = 2; length = readVarUInt(r)
	elseif header == TINY.NUMERIC_EXT then mode = 3; length = readVarUInt(r)
	else fail("invalid compact table string header", 2) end

	if mode == 0 then
		if r.Position + length > r.Length then fail("truncated compact table string", 2) end
		local value = buffer.readstring(r.Buffer, r.Position, length)
		r.Position += length
		return value
	end

	if length > 4_194_304 then
		fail(
			"compact table string exceeds decode limit",
			2
		)
	end

	local bitsPerCharacter =
		mode == 1
		and 6
		or (
			mode == 2
			and 7
			or 4
		)

	local requiredBits =
		length * bitsPerCharacter

	local availableBits =
		(r.Length - r.Position) * 8

	if requiredBits > availableBits then
		fail(
			"truncated compact table string bits",
			2
		)
	end

	local output = table.create(length)
	if mode == 1 then
		for i = 1, length do
			local index = readBits(r, 6) + 1
			if index < 1 or index > #IDENTIFIER_ALPHABET then fail("invalid compact identifier code", 2) end
			output[i] = string.sub(IDENTIFIER_ALPHABET, index, index)
		end
	elseif mode == 2 then
		for i = 1, length do output[i] = string.char(readBits(r, 7)) end
	else
		for i = 1, length do
			local code = readBits(r, 4)
			if code > 14 then fail("invalid compact numeric string code", 2) end
			output[i] = NUMERIC4_DECODE[code + 1]
		end
	end
	if r.BitBuffer ~= 0 then fail("invalid compact table string padding", 2) end
	alignReader(r)
	return table.concat(output)
end

-- Handles compact integer option.
local function compactIntegerOption(
	value: any,
	defaultValue: number,
	minimum: number,
	maximum: number,
	name: string
): number
	if value == nil then
		return defaultValue
	end

	if typeof(value) ~= "number"
		or value ~= value
		or value == math.huge
		or value == -math.huge then
		fail(
			name .. " must be a finite number",
			3
		)
	end

	return math.clamp(
		math.floor(value),
		minimum,
		maximum
	)
end

-- Handles build compact key map.
local function buildCompactKeyMap(value: {[any]: any}, options: Options?): DictionaryState
	local state: DictionaryState = {Encode = {}, Decode = {}}

	if options and options.TableKeyMapping == false then
		return state
	end

	if options and options.CompactMapKeys == false then
		return state
	end

	local counts: {[string]: number} = {}
	local active: {[any]: boolean} = {}

	-- Handles visit.
	local function visit(current: any)
		if typeof(current) ~= "table" then
			return
		end

		if active[current] then
			fail(
				"cyclic tables cannot use compact key mapping",
				3
			)
		end

		active[current] = true

		if isArray(current) then
			for _, child in ipairs(current) do
				visit(child)
			end
		else
			for key, child in pairs(current) do
				if typeof(key) == "string" then
					counts[key] =
						(counts[key] or 0) + 1
				end

				visit(child)
			end
		end

		active[current] = nil
	end

	visit(value)

	local minimumUses = compactIntegerOption(
		options and options.MappedKeyMinUses,
		2,
		2,
		1_000_000,
		"MappedKeyMinUses"
	)

	local maximum = compactIntegerOption(
		options and options.MaxMappedKeys,
		255,
		0,
		4095,
		"MaxMappedKeys"
	)

	if maximum == 0 then
		return state
	end

	local candidates = {}

	for key, count in pairs(counts) do
		if count >= minimumUses then
			local _, keyBytes = tinyStringMode(key)
			local potential =
				count * keyBytes
			- keyBytes
			- count

			if potential > 0 then
				candidates[#candidates + 1] = {
					Value = key,
					Count = count,
					KeyBytes = keyBytes,
					Potential = potential,
				}
			end
		end
	end

	table.sort(candidates, function(a, b)
		if a.Potential == b.Potential then
			if a.Count == b.Count then
				return a.Value < b.Value
			end

			return a.Count > b.Count
		end

		return a.Potential > b.Potential
	end)

	for _, candidate in ipairs(candidates) do
		if #state.Decode >= maximum then
			break
		end

		local id = #state.Decode + 1
		local idBytes = varUIntByteLength(id)

		local dictionaryCountPenalty =
			id == 128
			and 1
			or 0

		local exactSavings =
			candidate.Count * candidate.KeyBytes
		- candidate.KeyBytes
		- candidate.Count * idBytes
		- dictionaryCountPenalty

		if exactSavings > 0 then
			state.Encode[candidate.Value] = id
			state.Decode[id] = candidate.Value
		end
	end

	return state
end

-- Handles compact array normal uint bytes.
local function compactArrayNormalUIntBytes(value: {any}): number
	local count = #value
	local bytes = count <= 15 and 1 or 1 + varUIntByteLength(count)
	for i = 1, count do bytes += varUIntByteLength(value[i]) end
	return bytes
end

-- Handles compact array delta uint bytes.
local function compactArrayDeltaUIntBytes(value: {any}): number
	local count = #value
	local bytes = 1 + varUIntByteLength(count)
	if count == 0 then return bytes end
	bytes += varUIntByteLength(value[1])
	for i = 2, count do bytes += varIntByteLength(value[i] - value[i - 1]) end
	return bytes
end

-- Handles compact array normal int bytes.
local function compactArrayNormalIntBytes(value: {any}): number
	local count = #value
	local bytes = 1 + varUIntByteLength(count)
	for i = 1, count do bytes += varIntByteLength(value[i]) end
	return bytes
end

-- Handles compact array delta int bytes.
local function compactArrayDeltaIntBytes(value: {any}): number
	local count = #value
	local bytes = 1 + varUIntByteLength(count)
	if count == 0 then return bytes end
	bytes += varIntByteLength(value[1])
	for i = 2, count do bytes += varIntByteLength(value[i] - value[i - 1]) end
	return bytes
end

local compactWriteValue: (Writer, any, Options?) -> ()
local compactReadValue: (Reader) -> any

-- Handles validate container count.
local function validateContainerCount(r: Reader, count: number, label: string)
	if count < 0
		or count % 1 ~= 0 then
		fail(
			"invalid " .. label .. " count",
			3
		)
	end

	if count > MAX_DECODE_CONTAINER_ITEMS then
		fail(
			label .. " count exceeds decode limit",
			3
		)
	end

	local remaining =
		r.Length - r.Position
	local hardLimit =
		math.max(
			16,
			remaining * 8 + 16
		)

	if count > hardLimit then
		fail(
			label .. " count exceeds payload bounds",
			3
		)
	end
end

-- Handles write compact count tag.
local function writeCompactCountTag(w: Writer, smallBase: number, extendedTag: number, count: number)
	if count <= 15 then
		writeByte(w, smallBase + count)
	else
		writeByte(w, extendedTag)
		writeVarUInt(w, count)
	end
end

-- Handles compact write array.
local function compactWriteArray(w: Writer, value: {any}, options: Options?)
	local count = #value
	local arrayKind = (not options or options.HomogeneousArrays ~= false) and classifyArray(value) or "Mixed"
	local runCount = (not options or options.RunLengthArrays ~= false) and countScalarRuns(value) or count
	local useRLE = count >= 4 and arrayKind ~= "Bool" and runCount > 0 and runCount <= math.floor(count / 3)

	if useRLE then
		writeByte(w, CT.RLE_ARRAY_EXT)
		writeVarUInt(w, count)
		writeVarUInt(w, runCount)
		local i = 1
		while i <= count do
			local item = value[i]
			local length = 1
			while i + length <= count and value[i + length] == item do length += 1 end
			writeVarUInt(w, length)
			compactWriteValue(w, item, options)
			i += length
		end
		return
	end

	if arrayKind == "Bool" then
		writeCompactCountTag(w, CT.SMALL_BOOL_ARRAY, CT.BOOL_ARRAY_EXT, count)
		for i = 1, count do writeBits(w, value[i] and 1 or 0, 1) end
		flushBits(w)
	elseif arrayKind == "UInt" then
		local useDelta = count >= 3 and (not options or options.DeltaArrays ~= false)
		if useDelta then useDelta = compactArrayDeltaUIntBytes(value) < compactArrayNormalUIntBytes(value) end
		if useDelta then
			writeByte(w, CT.UINT_DELTA_EXT)
			writeVarUInt(w, count)
			writeVarUInt(w, value[1])
			for i = 2, count do writeVarInt(w, value[i] - value[i - 1]) end
		else
			writeCompactCountTag(w, CT.SMALL_UINT_ARRAY, CT.UINT_ARRAY_EXT, count)
			for i = 1, count do writeVarUInt(w, value[i]) end
		end
	elseif arrayKind == "Int" then
		local useDelta = count >= 3 and (not options or options.DeltaArrays ~= false)
		if useDelta then useDelta = compactArrayDeltaIntBytes(value) < compactArrayNormalIntBytes(value) end
		writeByte(w, useDelta and CT.INT_DELTA_EXT or CT.INT_ARRAY_EXT)
		writeVarUInt(w, count)
		if count > 0 then
			writeVarInt(w, value[1])
			for i = 2, count do
				if useDelta then writeVarInt(w, value[i] - value[i - 1]) else writeVarInt(w, value[i]) end
			end
		end
	elseif arrayKind == "Float" then
		local useF32 = count > 0
		for i = 1, count do
			if not exactFloat32(value[i]) then
				useF32 = false
				break
			end
		end
		writeByte(w, useF32 and CT.FLOAT32_ARRAY_EXT or CT.FLOAT_ARRAY_EXT)
		writeVarUInt(w, count)
		for i = 1, count do
			if useF32 then writeF32(w, value[i]) else writeF64(w, value[i]) end
		end
	elseif arrayKind == "String" then
		writeCompactCountTag(w, CT.SMALL_STRING_ARRAY, CT.STRING_ARRAY_EXT, count)
		for i = 1, count do writeTinyString(w, value[i]) end
	else
		writeCompactCountTag(w, CT.SMALL_ARRAY, CT.ARRAY_EXT, count)
		for i = 1, count do compactWriteValue(w, value[i], options) end
	end
end

-- Handles compact write map.
local function compactWriteMap(w: Writer, value: {[any]: any}, options: Options?)
	local keys = sortedMapKeys(value)
	local allStringKeys = not options or options.CompactMapKeys ~= false

	if allStringKeys then
		for _, key in ipairs(keys) do
			if typeof(key) ~= "string" then
				allStringKeys = false
				break
			end
		end
	end

	if allStringKeys then
		writeCompactCountTag(
			w,
			CT.SMALL_STRING_MAP,
			CT.STRING_MAP_EXT,
			#keys
		)

		local keyMap = w.KeyMapEncode

		for _, key in ipairs(keys) do
			if keyMap then
				local id = keyMap[key]

				if id then
					writeVarUInt(w, id)
				else
					writeVarUInt(w, 0)
					writeTinyString(w, key)
				end
			else
				writeTinyString(w, key)
			end

			compactWriteValue(w, value[key], options)
		end
	else
		writeCompactCountTag(
			w,
			CT.SMALL_MAP,
			CT.MAP_EXT,
			#keys
		)

		for _, key in ipairs(keys) do
			compactWriteValue(w, key, options)
			compactWriteValue(w, value[key], options)
		end
	end
end

compactWriteValue = function(w: Writer, value: any, options: Options?)
	flushBits(w)
	local kind = typeof(value)
	if kind == "nil" then writeByte(w, CT.VALUE_NIL)
	elseif kind == "boolean" then writeByte(w, value and CT.VALUE_TRUE or CT.VALUE_FALSE)
	elseif kind == "number" then
		if isSafeUInt(value) and value <= 127 then
			writeByte(w, CT.INLINE_UINT_BASE + value)
		else
			local exponent = power10Exponent(value)
			if exponent ~= nil then
				writeByte(w, CT.VALUE_POWER10)
				writeVarUInt(w, zigzagEncode(exponent) * 2 + (value < 0 and 1 or 0))
			elseif isSafeUInt(value) then
				writeByte(w, CT.VALUE_UINT)
				writeVarUInt(w, value)
			elseif isSafeInt(value) then
				writeByte(w, CT.VALUE_INT)
				writeVarInt(w, value)
			else
				local decimalInteger, decimalScale = decimalCandidate(value)
				local decimalBytes = if decimalInteger ~= nil and decimalScale ~= nil then 2 + varIntByteLength(decimalInteger) else math.huge
				local float32Bytes = exactFloat32(value) and 5 or math.huge

				if decimalBytes < float32Bytes and decimalBytes < 9 then
					writeByte(w, CT.VALUE_DECIMAL)
					writeByte(w, decimalScale :: number)
					writeVarInt(w, decimalInteger :: number)
				elseif float32Bytes < 9 then
					writeByte(w, CT.VALUE_FLOAT32)
					writeF32(w, value)
				elseif decimalBytes < 9 then
					writeByte(w, CT.VALUE_DECIMAL)
					writeByte(w, decimalScale :: number)
					writeVarInt(w, decimalInteger :: number)
				else
					writeByte(w, CT.VALUE_FLOAT)
					writeF64(w, value)
				end
			end
		end
	elseif kind == "string" then
		writeByte(w, CT.VALUE_STRING)
		writeTinyString(w, value)
	elseif kind == "Vector2" then
		if exactFloat32(value.X)
			and exactFloat32(value.Y) then
			writeByte(w, CT.VALUE_VECTOR2_F32)
			writeF32(w, value.X)
			writeF32(w, value.Y)
		else
			writeByte(w, CT.VALUE_VECTOR2)
			writeF64(w, value.X)
			writeF64(w, value.Y)
		end
	elseif kind == "Vector3" then
		if exactFloat32(value.X)
			and exactFloat32(value.Y)
			and exactFloat32(value.Z) then
			writeByte(w, CT.VALUE_VECTOR3_F32)
			writeF32(w, value.X)
			writeF32(w, value.Y)
			writeF32(w, value.Z)
		else
			writeByte(w, CT.VALUE_VECTOR3)
			writeF64(w, value.X)
			writeF64(w, value.Y)
			writeF64(w, value.Z)
		end
	elseif kind == "Color3" then
		local byteExact, r, g, b = exactColor3Bytes(value)

		if byteExact then
			writeByte(w, CT.VALUE_COLOR3)
			writeByte(w, r)
			writeByte(w, g)
			writeByte(w, b)
		elseif exactColor3F32(value) then
			writeByte(w, CT.VALUE_COLOR3_F32)
			writeF32(w, value.R)
			writeF32(w, value.G)
			writeF32(w, value.B)
		else
			writeByte(w, CT.VALUE_COLOR3_F64)
			writeF64(w, value.R)
			writeF64(w, value.G)
			writeF64(w, value.B)
		end
	elseif kind == "CFrame" then
		local components = {value:GetComponents()}
		local useF32 = true
		for i = 1, 12 do
			if not exactFloat32(components[i]) then
				useF32 = false
				break
			end
		end
		writeByte(w, useF32 and CT.VALUE_CFRAME_F32 or CT.VALUE_CFRAME)
		for i = 1, 12 do
			if useF32 then writeF32(w, components[i]) else writeF64(w, components[i]) end
		end
	elseif kind == "buffer" then
		writeByte(w, CT.VALUE_BUFFER)
		local packed = Compression.CompressBuffer(value, options)
		writeVarUInt(w, buffer.len(packed))
		appendBuffer(w, packed)
	elseif kind == "table" then
		if isArray(value) then compactWriteArray(w, value, options) else compactWriteMap(w, value, options) end
	else
		fail("unsupported compact table type " .. kind, 2)
	end
end

-- Handles read compact array.
local function readCompactArray(r: Reader, count: number): {any}
	validateContainerCount(r, count, "compact array")
	local result = table.create(count)
	for i = 1, count do result[i] = compactReadValue(r) end
	return result
end

-- Handles read compact string map.
local function readCompactStringMap(r: Reader, count: number): {[any]: any}
	validateContainerCount(r, count, "compact string map")

	local result = {}
	local seenKeys: {[string]: boolean} = {}
	local keyMap = r.KeyMapDecode

	for _ = 1, count do
		local key: string

		if keyMap then
			local id = readVarUInt(r)

			if id == 0 then
				key = readTinyString(r)
			else
				key = keyMap[id]

				if key == nil then
					fail("invalid compact mapped key reference", 2)
				end
			end
		else
			key = readTinyString(r)
		end

		if seenKeys[key] then
			fail("duplicate compact string map key", 2)
		end

		seenKeys[key] = true
		result[key] = compactReadValue(r)
	end

	return result
end

-- Handles read compact map.
local function readCompactMap(r: Reader, count: number): {[any]: any}
	validateContainerCount(r, count, "compact map")

	local result = {}
	local seenKeys: {[any]: boolean} = {}

	for _ = 1, count do
		local key = compactReadValue(r)
		local keyType = typeof(key)

		if keyType ~= "string"
			and keyType ~= "number" then
			fail("invalid compact table map key", 2)
		end

		if seenKeys[key] then
			fail("duplicate compact map key", 2)
		end

		seenKeys[key] = true
		result[key] = compactReadValue(r)
	end

	return result
end

compactReadValue = function(r: Reader): any
	alignReader(r)
	local tag = readByte(r)
	if tag >= CT.INLINE_UINT_BASE then return tag - CT.INLINE_UINT_BASE end
	if tag >= CT.SMALL_STRING_ARRAY and tag <= CT.SMALL_STRING_ARRAY + 15 then
		local count = tag - CT.SMALL_STRING_ARRAY
		local result = table.create(count)
		for i = 1, count do result[i] = readTinyString(r) end
		return result
	end
	if tag >= CT.SMALL_UINT_ARRAY and tag <= CT.SMALL_UINT_ARRAY + 15 then
		local count = tag - CT.SMALL_UINT_ARRAY
		local result = table.create(count)
		for i = 1, count do result[i] = readVarUInt(r) end
		return result
	end
	if tag >= CT.SMALL_BOOL_ARRAY and tag <= CT.SMALL_BOOL_ARRAY + 15 then
		local count = tag - CT.SMALL_BOOL_ARRAY
		local result = table.create(count)
		for i = 1, count do result[i] = readBits(r, 1) == 1 end
		if r.BitBuffer ~= 0 then fail("invalid compact bool array padding", 2) end
		alignReader(r)
		return result
	end
	if tag >= CT.SMALL_MAP and tag <= CT.SMALL_MAP + 15 then return readCompactMap(r, tag - CT.SMALL_MAP) end
	if tag >= CT.SMALL_STRING_MAP and tag <= CT.SMALL_STRING_MAP + 15 then return readCompactStringMap(r, tag - CT.SMALL_STRING_MAP) end
	if tag >= CT.SMALL_ARRAY and tag <= CT.SMALL_ARRAY + 15 then return readCompactArray(r, tag - CT.SMALL_ARRAY) end

	if tag == CT.VALUE_NIL then return nil
	elseif tag == CT.VALUE_FALSE then return false
	elseif tag == CT.VALUE_TRUE then return true
	elseif tag == CT.VALUE_STRING then return readTinyString(r)
	elseif tag == CT.VALUE_FLOAT then return readF64(r)
	elseif tag == CT.VALUE_FLOAT32 then return readF32(r)
	elseif tag == CT.VALUE_DECIMAL then
		local scale = readByte(r)
		if scale < 1 or scale > 12 then fail("invalid compact decimal scale", 2) end
		return readVarInt(r) / 10 ^ scale
	elseif tag == CT.VALUE_UINT then return readVarUInt(r)
	elseif tag == CT.VALUE_INT then return readVarInt(r)
	elseif tag == CT.VALUE_POWER10 then
		local code = readVarUInt(r)
		local value = 10 ^ zigzagDecode(math.floor(code / 2))
		return code % 2 == 1 and -value or value
	elseif tag == CT.VALUE_VECTOR2 then return Vector2.new(readF64(r), readF64(r))
	elseif tag == CT.VALUE_VECTOR2_F32 then return Vector2.new(readF32(r), readF32(r))
	elseif tag == CT.VALUE_VECTOR3 then return Vector3.new(readF64(r), readF64(r), readF64(r))
	elseif tag == CT.VALUE_VECTOR3_F32 then return Vector3.new(readF32(r), readF32(r), readF32(r))
	elseif tag == CT.VALUE_COLOR3 then return Color3.fromRGB(readByte(r), readByte(r), readByte(r))
	elseif tag == CT.VALUE_COLOR3_F32 then return Color3.new(readF32(r), readF32(r), readF32(r))
	elseif tag == CT.VALUE_COLOR3_F64 then return Color3.new(readF64(r), readF64(r), readF64(r))
	elseif tag == CT.VALUE_CFRAME then
		local components = table.create(12)
		for i = 1, 12 do components[i] = readF64(r) end
		return CFrame.new(table.unpack(components))
	elseif tag == CT.VALUE_CFRAME_F32 then
		local components = table.create(12)
		for i = 1, 12 do components[i] = readF32(r) end
		return CFrame.new(table.unpack(components))
	elseif tag == CT.VALUE_BUFFER then
		local length = readVarUInt(r)
		if r.Position + length > r.Length then fail("truncated compact buffer value", 2) end
		local packed = buffer.create(length)
		buffer.copy(packed, 0, r.Buffer, r.Position, length)
		r.Position += length
		return Compression.DecompressBuffer(packed)
	elseif tag == CT.ARRAY_EXT then return readCompactArray(r, readVarUInt(r))
	elseif tag == CT.STRING_MAP_EXT then return readCompactStringMap(r, readVarUInt(r))
	elseif tag == CT.MAP_EXT then return readCompactMap(r, readVarUInt(r))
	elseif tag == CT.BOOL_ARRAY_EXT then
		local count = readVarUInt(r)
		validateContainerCount(r, count, "compact bool array")
		local result = table.create(count)
		for i = 1, count do result[i] = readBits(r, 1) == 1 end
		if r.BitBuffer ~= 0 then fail("invalid compact bool array padding", 2) end
		alignReader(r)
		return result
	elseif tag == CT.UINT_ARRAY_EXT then
		local count = readVarUInt(r)
		validateContainerCount(r, count, "compact uint array")
		local result = table.create(count)
		for i = 1, count do result[i] = readVarUInt(r) end
		return result
	elseif tag == CT.INT_ARRAY_EXT then
		local count = readVarUInt(r)
		validateContainerCount(r, count, "compact int array")
		local result = table.create(count)
		for i = 1, count do result[i] = readVarInt(r) end
		return result
	elseif tag == CT.FLOAT_ARRAY_EXT then
		local count = readVarUInt(r)
		validateContainerCount(r, count, "compact float array")
		local result = table.create(count)
		for i = 1, count do result[i] = readF64(r) end
		return result
	elseif tag == CT.FLOAT32_ARRAY_EXT then
		local count = readVarUInt(r)
		validateContainerCount(r, count, "compact float32 array")
		local result = table.create(count)
		for i = 1, count do result[i] = readF32(r) end
		return result
	elseif tag == CT.STRING_ARRAY_EXT then
		local count = readVarUInt(r)
		validateContainerCount(r, count, "compact string array")
		local result = table.create(count)
		for i = 1, count do result[i] = readTinyString(r) end
		return result
	elseif tag == CT.UINT_DELTA_EXT then
		local count = readVarUInt(r)
		validateContainerCount(r, count, "compact uint delta array")
		local result = table.create(count)
		if count > 0 then
			result[1] = readVarUInt(r)
			for i = 2, count do result[i] = result[i - 1] + readVarInt(r) end
		end
		return result
	elseif tag == CT.INT_DELTA_EXT then
		local count = readVarUInt(r)
		validateContainerCount(r, count, "compact int delta array")
		local result = table.create(count)
		if count > 0 then
			result[1] = readVarInt(r)
			for i = 2, count do result[i] = result[i - 1] + readVarInt(r) end
		end
		return result
	elseif tag == CT.RLE_ARRAY_EXT then
		local count = readVarUInt(r)
		if count > 4_194_304 then fail("compact RLE array count exceeds decode limit", 2) end
		local runCount = readVarUInt(r)
		validateContainerCount(r, runCount, "compact RLE run")
		if runCount > count and count > 0 then fail("compact RLE run count exceeds item count", 2) end
		local result = table.create(count)
		local position = 1
		for _ = 1, runCount do
			local length = readVarUInt(r)
			if length < 1 or position + length - 1 > count then fail("invalid compact RLE array", 2) end
			local item = compactReadValue(r)
			for _ = 1, length do result[position] = item; position += 1 end
		end
		if position ~= count + 1 then fail("compact RLE array length mismatch", 2) end
		return result
	end
	fail("invalid compact table value tag", 2)
	return nil
end

-- Handles encode compact table buffer.
local function encodeCompactTableBuffer(
	value: {[any]: any},
	options: Options?
): (buffer, number, number, boolean)
	local plain = newWriter(64)
	writeByte(
		plain,
		FMT.COMPACT_TABLE_MAGIC
	)
	compactWriteValue(
		plain,
		value,
		options
	)

	local plainData = finish(plain)
	local plainUsefulBits = plain.UsedBits
	local plainPaddingBits = plain.PaddingBits

	local keyMap = buildCompactKeyMap(
		value,
		options
	)

	if #keyMap.Decode == 0 then
		return plainData,
			plainUsefulBits,
			plainPaddingBits,
			false
	end

	local mapped = newWriter(64)
	mapped.KeyMapEncode = keyMap.Encode
	mapped.KeyMapCount = #keyMap.Decode

	writeByte(
		mapped,
		FMT.COMPACT_MAPPED_TABLE_MAGIC
	)

	writeVarUInt(
		mapped,
		#keyMap.Decode
	)

	for i = 1, #keyMap.Decode do
		writeTinyString(
			mapped,
			keyMap.Decode[i]
		)
	end

	compactWriteValue(
		mapped,
		value,
		options
	)

	local mappedData = finish(mapped)

	if buffer.len(mappedData)
		< buffer.len(plainData) then
		return mappedData,
			mapped.UsedBits,
			mapped.PaddingBits,
			true
	end

	return plainData,
		plainUsefulBits,
		plainPaddingBits,
		false
end

-- Handles decode compact table buffer.
local function decodeCompactTableBuffer(data: buffer): {[any]: any}
	local r = newReader(data)
	local magic = readByte(r)

	if magic == FMT.COMPACT_MAPPED_TABLE_MAGIC then
		local keyCount = readVarUInt(r)

		validateContainerCount(
			r,
			keyCount,
			"compact mapped key dictionary"
		)

		local decode = table.create(keyCount)
		local seen: {[string]: boolean} = {}

		for i = 1, keyCount do
			local key = readTinyString(r)

			if seen[key] then
				fail(
					"duplicate compact mapped key dictionary entry",
					2
				)
			end

			seen[key] = true
			decode[i] = key
		end

		r.KeyMapDecode = decode
	elseif magic ~= FMT.COMPACT_TABLE_MAGIC then
		fail("invalid compact table header", 2)
	end

	local value = compactReadValue(r)

	if typeof(value) ~= "table" then
		fail(
			"compact table payload did not decode to table",
			2
		)
	end

	alignReader(r)

	if r.Position ~= r.Length then
		fail(
			"trailing bytes in compact table payload",
			2
		)
	end

	return value
end

-- Handles compact mode from tag.
CT.ModeFromTag = function(
	tag: number,
	mapped: boolean
): string
	local prefix = mapped
		and "CompactMapped"
		or "Compact"

	if tag >= CT.SMALL_STRING_ARRAY
		and tag <= CT.SMALL_STRING_ARRAY + 15 then
		return prefix .. "StringArray"
	end

	if tag >= CT.SMALL_UINT_ARRAY
		and tag <= CT.SMALL_UINT_ARRAY + 15 then
		return prefix .. "UIntArray"
	end

	if tag >= CT.SMALL_BOOL_ARRAY
		and tag <= CT.SMALL_BOOL_ARRAY + 15 then
		return prefix .. "BoolArray"
	end

	if tag >= CT.SMALL_MAP
		and tag <= CT.SMALL_MAP + 15 then
		return prefix .. "Map"
	end

	if tag >= CT.SMALL_STRING_MAP
		and tag <= CT.SMALL_STRING_MAP + 15 then
		return prefix .. "StringMap"
	end

	if tag >= CT.SMALL_ARRAY
		and tag <= CT.SMALL_ARRAY + 15 then
		return prefix .. "MixedArray"
	end

	if tag == CT.ARRAY_EXT then
		return prefix .. "MixedArray"
	end

	if tag == CT.STRING_MAP_EXT then
		return prefix .. "StringMap"
	end

	if tag == CT.MAP_EXT then
		return prefix .. "Map"
	end

	if tag == CT.BOOL_ARRAY_EXT then
		return prefix .. "BoolArray"
	end

	if tag == CT.UINT_ARRAY_EXT then
		return prefix .. "UIntArray"
	end

	if tag == CT.INT_ARRAY_EXT then
		return prefix .. "IntArray"
	end

	if tag == CT.FLOAT_ARRAY_EXT then
		return prefix .. "FloatArray"
	end

	if tag == CT.FLOAT32_ARRAY_EXT then
		return prefix .. "Float32Array"
	end

	if tag == CT.STRING_ARRAY_EXT then
		return prefix .. "StringArray"
	end

	if tag == CT.UINT_DELTA_EXT then
		return prefix .. "UIntDeltaArray"
	end

	if tag == CT.INT_DELTA_EXT then
		return prefix .. "IntDeltaArray"
	end

	if tag == CT.RLE_ARRAY_EXT then
		return prefix .. "RLEArray"
	end

	return prefix .. "Unknown"
end

-- Handles compact table mode from data.
CT.TableModeFromData = function(data: buffer): string?
	if buffer.len(data) < 2 then
		return nil
	end

	local magic = buffer.readu8(
		data,
		0
	)

	if magic == FMT.COMPACT_TABLE_MAGIC then
		return CT.ModeFromTag(
			buffer.readu8(data, 1),
			false
		)
	end

	if magic ~= FMT.COMPACT_MAPPED_TABLE_MAGIC then
		return nil
	end

	local r = newReader(data)
	readByte(r)

	local ok, tag = pcall(function()
		local keyCount = readVarUInt(r)

		validateContainerCount(
			r,
			keyCount,
			"compact mapped key dictionary"
		)

		for _ = 1, keyCount do
			readTinyString(r)
		end

		alignReader(r)
		return readByte(r)
	end)

	if not ok then
		return "CompactMappedInvalid"
	end

	return CT.ModeFromTag(
		tag,
		true
	)
end

-- Handles dynamic write.
local function dynamicWrite(w: Writer, value: any, options: Options?, dictionary: DictionaryState)
	local kind = typeof(value)
	if kind == "nil" then
		flushBits(w)
		writeByte(w, TAG.NIL)
	elseif kind == "boolean" then
		flushBits(w)
		writeByte(w, value and TAG.TRUE or TAG.FALSE)
	elseif kind == "number" then
		flushBits(w)
		if isSafeUInt(value)
			and value <= 127 then
			writeByte(
				w,
				TAG.INLINE_UINT_BASE + value
			)
		elseif isSafeInt(value)
			and value >= -17
			and value <= -2 then
			writeByte(
				w,
				110 - value
			)
		else
			writeNumberPayload(w, value)
		end
	elseif kind == "string" then
		local id = dictionary.Encode[value]
		flushBits(w)
		if id then
			writeByte(w, TAG.STRING_REF)
			writeVarUInt(w, id)
		else
			writeByte(w, TAG.STRING)
			local packed = Compression.CompressString(value, options)
			writeVarUInt(w, buffer.len(packed))
			ensureCapacity(w, buffer.len(packed))
			buffer.copy(w.Buffer, w.Position, packed, 0, buffer.len(packed))
			w.Position += buffer.len(packed)
			w.UsedBits += buffer.len(packed) * 8
		end
	elseif kind == "Vector2" then
		flushBits(w)
		if exactFloat32(value.X)
			and exactFloat32(value.Y) then
			writeByte(w, TAG.VECTOR2_F32)
			writeF32(w, value.X)
			writeF32(w, value.Y)
		else
			writeByte(w, TAG.VECTOR2)
			writeF64(w, value.X)
			writeF64(w, value.Y)
		end
	elseif kind == "Vector3" then
		flushBits(w)
		if exactFloat32(value.X)
			and exactFloat32(value.Y)
			and exactFloat32(value.Z) then
			writeByte(w, TAG.VECTOR3_F32)
			writeF32(w, value.X)
			writeF32(w, value.Y)
			writeF32(w, value.Z)
		else
			writeByte(w, TAG.VECTOR3)
			writeF64(w, value.X)
			writeF64(w, value.Y)
			writeF64(w, value.Z)
		end
	elseif kind == "Color3" then
		flushBits(w)
		local byteExact, r, g, b = exactColor3Bytes(value)

		if byteExact then
			writeByte(w, TAG.COLOR3)
			writeByte(w, r)
			writeByte(w, g)
			writeByte(w, b)
		elseif exactColor3F32(value) then
			writeByte(w, TAG.COLOR3_F32)
			writeF32(w, value.R)
			writeF32(w, value.G)
			writeF32(w, value.B)
		else
			writeByte(w, TAG.COLOR3_F64)
			writeF64(w, value.R)
			writeF64(w, value.G)
			writeF64(w, value.B)
		end
	elseif kind == "CFrame" then
		flushBits(w)
		local components = {value:GetComponents()}
		local useF32 = true
		for i = 1, 12 do
			if not exactFloat32(components[i]) then
				useF32 = false
				break
			end
		end
		writeByte(w, useF32 and TAG.CFRAME_F32 or TAG.CFRAME)
		for i = 1, 12 do
			if useF32 then writeF32(w, components[i]) else writeF64(w, components[i]) end
		end
	elseif kind == "UDim" then
		flushBits(w)
		writeByte(w, TAG.UDIM)
		writeNumberPayload(w, value.Scale)
		writeVarInt(w, value.Offset)
	elseif kind == "UDim2" then
		flushBits(w)
		writeByte(w, TAG.UDIM2)
		writeNumberPayload(w, value.X.Scale)
		writeVarInt(w, value.X.Offset)
		writeNumberPayload(w, value.Y.Scale)
		writeVarInt(w, value.Y.Offset)
	elseif kind == "Rect" then
		flushBits(w)
		writeByte(w, TAG.RECT)
		writeNumberPayload(w, value.Min.X)
		writeNumberPayload(w, value.Min.Y)
		writeNumberPayload(w, value.Max.X)
		writeNumberPayload(w, value.Max.Y)
	elseif kind == "NumberRange" then
		flushBits(w)
		writeByte(w, TAG.NUMBER_RANGE)
		writeNumberPayload(w, value.Min)
		writeNumberPayload(w, value.Max)
	elseif kind == "BrickColor" then
		flushBits(w)
		writeByte(w, TAG.BRICK_COLOR)
		writeVarUInt(w, value.Number)
	elseif kind == "DateTime" then
		flushBits(w)
		writeByte(w, TAG.DATETIME)
		writeDateTimePayload(w, value)
	elseif kind == "buffer" then
		flushBits(w)
		writeByte(w, TAG.BUFFER)
		local packed = Compression.CompressBuffer(value, options)
		writeVarUInt(w, buffer.len(packed))
		ensureCapacity(w, buffer.len(packed))
		buffer.copy(w.Buffer, w.Position, packed, 0, buffer.len(packed))
		w.Position += buffer.len(packed)
		w.UsedBits += buffer.len(packed) * 8
	elseif kind == "table" then
		flushBits(w)
		if isArray(value) then
			local count = #value
			local tableCompression = not options or options.TableCompression ~= false
			local homogeneous = tableCompression and (not options or options.HomogeneousArrays ~= false)
			local arrayKind = homogeneous and classifyArray(value) or "Mixed"
			local runCount = tableCompression and (not options or options.RunLengthArrays ~= false) and countScalarRuns(value) or count
			if count >= 4 and runCount <= math.floor(count / 3) and arrayKind ~= "Bool" then
				writeByte(w, TAG.ARRAY_RLE)
				writeVarUInt(w, count)
				writeVarUInt(w, runCount)
				local i = 1
				while i <= count do
					local item = value[i]
					local length = 1
					while i + length <= count and value[i + length] == item do length += 1 end
					writeVarUInt(w, length)
					dynamicWrite(w, item, options, dictionary)
					i += length
				end
			elseif arrayKind == "Bool" then
				writeByte(w, TAG.ARRAY_BOOL)
				writeVarUInt(w, count)
				for i = 1, count do writeBits(w, value[i] and 1 or 0, 1) end
			elseif arrayKind == "UInt" then
				local useDelta = (not options or options.DeltaArrays ~= false) and canUseUIntDelta(value)
				writeByte(w, useDelta and TAG.ARRAY_UINT_DELTA or TAG.ARRAY_UINT)
				writeVarUInt(w, count)
				if count > 0 then
					writeVarUInt(w, value[1])
					for i = 2, count do
						if useDelta then writeVarInt(w, value[i] - value[i - 1]) else writeVarUInt(w, value[i]) end
					end
				end
			elseif arrayKind == "Int" then
				local useDelta = (not options or options.DeltaArrays ~= false) and canUseIntDelta(value)
				writeByte(w, useDelta and TAG.ARRAY_INT_DELTA or TAG.ARRAY_INT)
				writeVarUInt(w, count)
				if count > 0 then
					writeVarInt(w, value[1])
					for i = 2, count do
						if useDelta then writeVarInt(w, value[i] - value[i - 1]) else writeVarInt(w, value[i]) end
					end
				end
			elseif arrayKind == "Float" then
				local useF32 = count > 0

				for i = 1, count do
					if not exactFloat32(value[i]) then
						useF32 = false
						break
					end
				end

				writeByte(
					w,
					useF32
						and TAG.ARRAY_FLOAT32
						or TAG.ARRAY_FLOAT
				)
				writeVarUInt(w, count)

				for i = 1, count do
					if useF32 then
						writeF32(w, value[i])
					else
						writeF64(w, value[i])
					end
				end
			elseif arrayKind == "String" then
				writeByte(w, TAG.ARRAY_STRING)
				writeVarUInt(w, count)
				for i = 1, count do writeCompactString(w, value[i], options, dictionary) end
			elseif arrayKind == "Vector2" then
				local useF32 = true
				for i = 1, count do
					local item = value[i]
					if not exactFloat32(item.X)
						or not exactFloat32(item.Y) then
						useF32 = false
						break
					end
				end
				writeByte(w, useF32 and TAG.ARRAY_VECTOR2_F32 or TAG.ARRAY_VECTOR2_F64)
				writeVarUInt(w, count)
				for i = 1, count do
					local item = value[i]
					if useF32 then
						writeF32(w, item.X)
						writeF32(w, item.Y)
					else
						writeF64(w, item.X)
						writeF64(w, item.Y)
					end
				end
			elseif arrayKind == "Vector3" then
				local useF32 = true
				for i = 1, count do
					local item = value[i]
					if not exactFloat32(item.X)
						or not exactFloat32(item.Y)
						or not exactFloat32(item.Z) then
						useF32 = false
						break
					end
				end
				writeByte(w, useF32 and TAG.ARRAY_VECTOR3_F32 or TAG.ARRAY_VECTOR3_F64)
				writeVarUInt(w, count)
				for i = 1, count do
					local item = value[i]
					if useF32 then
						writeF32(w, item.X)
						writeF32(w, item.Y)
						writeF32(w, item.Z)
					else
						writeF64(w, item.X)
						writeF64(w, item.Y)
						writeF64(w, item.Z)
					end
				end
			elseif arrayKind == "Color3" then
				local useRGB8 = true
				local useF32 = true
				for i = 1, count do
					local item = value[i]
					local byteExact = exactColor3Bytes(item)
					if not byteExact then useRGB8 = false end
					if not exactColor3F32(item) then useF32 = false end
				end
				writeByte(
					w,
					useRGB8
						and TAG.ARRAY_COLOR3_RGB8
						or (useF32 and TAG.ARRAY_COLOR3_F32 or TAG.ARRAY_COLOR3_F64)
				)
				writeVarUInt(w, count)
				for i = 1, count do
					local item = value[i]
					if useRGB8 then
						local _, r, g, b = exactColor3Bytes(item)
						writeByte(w, r)
						writeByte(w, g)
						writeByte(w, b)
					elseif useF32 then
						writeF32(w, item.R)
						writeF32(w, item.G)
						writeF32(w, item.B)
					else
						writeF64(w, item.R)
						writeF64(w, item.G)
						writeF64(w, item.B)
					end
				end
			elseif arrayKind == "UDim" then
				writeByte(w, TAG.ARRAY_UDIM)
				writeVarUInt(w, count)
				for i = 1, count do
					writeNumberPayload(w, value[i].Scale)
					writeVarInt(w, value[i].Offset)
				end
			elseif arrayKind == "UDim2" then
				writeByte(w, TAG.ARRAY_UDIM2)
				writeVarUInt(w, count)
				for i = 1, count do
					local item = value[i]
					writeNumberPayload(w, item.X.Scale)
					writeVarInt(w, item.X.Offset)
					writeNumberPayload(w, item.Y.Scale)
					writeVarInt(w, item.Y.Offset)
				end
			elseif arrayKind == "NumberRange" then
				writeByte(w, TAG.ARRAY_NUMBER_RANGE)
				writeVarUInt(w, count)
				for i = 1, count do
					writeNumberPayload(w, value[i].Min)
					writeNumberPayload(w, value[i].Max)
				end
			elseif arrayKind == "BrickColor" then
				writeByte(w, TAG.ARRAY_BRICK_COLOR)
				writeVarUInt(w, count)
				for i = 1, count do writeVarUInt(w, value[i].Number) end
			elseif arrayKind == "Rect" then
				writeByte(w, TAG.ARRAY_RECT)
				writeVarUInt(w, count)
				for i = 1, count do
					local item = value[i]
					writeNumberPayload(w, item.Min.X)
					writeNumberPayload(w, item.Min.Y)
					writeNumberPayload(w, item.Max.X)
					writeNumberPayload(w, item.Max.Y)
				end
			elseif arrayKind == "DateTime" then
				writeByte(w, TAG.ARRAY_DATETIME)
				writeVarUInt(w, count)
				for i = 1, count do writeDateTimePayload(w, value[i]) end
			else
				writeByte(w, TAG.ARRAY)
				writeVarUInt(w, count)
				for _, item in ipairs(value) do dynamicWrite(w, item, options, dictionary) end
			end
		else
			local keys = sortedMapKeys(value)
			local allStringKeys = not options or options.CompactMapKeys ~= false
			if allStringKeys then
				for _, key in ipairs(keys) do
					if typeof(key) ~= "string" then allStringKeys = false; break end
				end
			end
			if allStringKeys and (not options or options.TableCompression ~= false) then
				writeByte(w, TAG.MAP_STRING)
				writeVarUInt(w, #keys)
				for _, key in ipairs(keys) do
					writeCompactString(w, key, options, dictionary)
					dynamicWrite(w, value[key], options, dictionary)
				end
			else
				writeByte(w, TAG.MAP)
				writeVarUInt(w, #keys)
				for _, key in ipairs(keys) do
					dynamicWrite(w, key, options, dictionary)
					dynamicWrite(w, value[key], options, dictionary)
				end
			end
		end
	else
		fail("unsupported dynamic type " .. kind, 2)
	end
end

-- Handles dynamic read.
local function dynamicRead(r: Reader, dictionary: DictionaryState): any
	alignReader(r)
	local tag = readByte(r)
	if tag >= TAG.INLINE_UINT_BASE then
		return tag - TAG.INLINE_UINT_BASE
	end
	if tag >= TAG.INLINE_NEG_BASE
		and tag < TAG.INLINE_UINT_BASE then
		return -(tag - 110)
	end
	if tag == TAG.NIL then return nil
	elseif tag == TAG.FALSE then return false
	elseif tag == TAG.TRUE then return true
	elseif tag == TAG.ZERO then return 0
	elseif tag == TAG.ONE then return 1
	elseif tag == TAG.NEG_ONE then return -1
	elseif tag == TAG.UINT then return readVarUInt(r)
	elseif tag == TAG.INT then return readVarInt(r)
	elseif tag == TAG.FLOAT then return readF64(r)
	elseif tag == TAG.FLOAT32 then return readF32(r)
	elseif tag == TAG.DECIMAL then
		local scale = readByte(r)
		if scale < 1 or scale > 12 then fail("invalid dynamic decimal scale", 2) end
		return readVarInt(r) / 10 ^ scale
	elseif tag == TAG.POWER10 then
		local code = readVarUInt(r)
		local sign = code % 2
		local exponent = zigzagDecode(math.floor(code / 2))
		local value = 10 ^ exponent
		return sign == 1 and -value or value
	elseif tag == TAG.STRING_REF then
		local id = readVarUInt(r)
		local value = dictionary.Decode[id]
		if value == nil then fail("invalid string dictionary reference", 2) end
		return value
	elseif tag == TAG.STRING then
		local length = readVarUInt(r)
		if r.Position + length > r.Length then fail("truncated dynamic string", 2) end
		local data = buffer.create(length)
		buffer.copy(data, 0, r.Buffer, r.Position, length)
		r.Position += length
		return Compression.DecompressString(data)
	elseif tag == TAG.VECTOR2 then return Vector2.new(readF64(r), readF64(r))
	elseif tag == TAG.VECTOR2_F32 then return Vector2.new(readF32(r), readF32(r))
	elseif tag == TAG.VECTOR3 then return Vector3.new(readF64(r), readF64(r), readF64(r))
	elseif tag == TAG.VECTOR3_F32 then return Vector3.new(readF32(r), readF32(r), readF32(r))
	elseif tag == TAG.COLOR3 then return Color3.fromRGB(readByte(r), readByte(r), readByte(r))
	elseif tag == TAG.COLOR3_F32 then return Color3.new(readF32(r), readF32(r), readF32(r))
	elseif tag == TAG.COLOR3_F64 then return Color3.new(readF64(r), readF64(r), readF64(r))
	elseif tag == TAG.CFRAME then
		local components = table.create(12)
		for i = 1, 12 do components[i] = readF64(r) end
		return CFrame.new(table.unpack(components))
	elseif tag == TAG.CFRAME_F32 then
		local components = table.create(12)
		for i = 1, 12 do components[i] = readF32(r) end
		return CFrame.new(table.unpack(components))
	elseif tag == TAG.UDIM then
		return UDim.new(readNumberPayload(r), readVarInt(r))
	elseif tag == TAG.UDIM2 then
		return UDim2.new(
			readNumberPayload(r),
			readVarInt(r),
			readNumberPayload(r),
			readVarInt(r)
		)
	elseif tag == TAG.RECT then
		return Rect.new(
			readNumberPayload(r),
			readNumberPayload(r),
			readNumberPayload(r),
			readNumberPayload(r)
		)
	elseif tag == TAG.NUMBER_RANGE then
		return NumberRange.new(readNumberPayload(r), readNumberPayload(r))
	elseif tag == TAG.BRICK_COLOR then
		return BrickColor.new(readVarUInt(r))
	elseif tag == TAG.DATETIME then
		return readDateTimePayload(r)
	elseif tag == TAG.BUFFER then
		local length = readVarUInt(r)
		if r.Position + length > r.Length then fail("truncated dynamic buffer", 2) end
		local packed = buffer.create(length)
		buffer.copy(packed, 0, r.Buffer, r.Position, length)
		r.Position += length
		return Compression.DecompressBuffer(packed)
	elseif tag == TAG.ARRAY then
		local count = readVarUInt(r)
		validateContainerCount(r, count, "dynamic array")
		local result = table.create(count)
		for i = 1, count do result[i] = dynamicRead(r, dictionary) end
		return result
	elseif tag == TAG.ARRAY_BOOL then
		local count = readVarUInt(r)
		validateContainerCount(r, count, "dynamic bool array")
		local result = table.create(count)
		for i = 1, count do result[i] = readBits(r, 1) == 1 end
		return result
	elseif tag == TAG.ARRAY_UINT then
		local count = readVarUInt(r)
		validateContainerCount(r, count, "dynamic uint array")
		local result = table.create(count)
		for i = 1, count do result[i] = readVarUInt(r) end
		return result
	elseif tag == TAG.ARRAY_INT then
		local count = readVarUInt(r)
		validateContainerCount(r, count, "dynamic int array")
		local result = table.create(count)
		for i = 1, count do result[i] = readVarInt(r) end
		return result
	elseif tag == TAG.ARRAY_FLOAT then
		local count = readVarUInt(r)
		validateContainerCount(r, count, "dynamic float array")
		local result = table.create(count)
		for i = 1, count do result[i] = readF64(r) end
		return result
	elseif tag == TAG.ARRAY_FLOAT32 then
		local count = readVarUInt(r)
		validateContainerCount(r, count, "dynamic float32 array")
		local result = table.create(count)
		for i = 1, count do result[i] = readF32(r) end
		return result
	elseif tag == TAG.ARRAY_STRING then
		local count = readVarUInt(r)
		validateContainerCount(r, count, "dynamic string array")
		local result = table.create(count)
		for i = 1, count do result[i] = readCompactString(r, dictionary) end
		return result
	elseif tag == TAG.ARRAY_VECTOR2_F32
		or tag == TAG.ARRAY_VECTOR2_F64 then
		local count = readVarUInt(r)
		validateContainerCount(r, count, "dynamic Vector2 array")
		local result = table.create(count)
		local useF32 = tag == TAG.ARRAY_VECTOR2_F32
		for i = 1, count do
			result[i] = Vector2.new(
				useF32 and readF32(r) or readF64(r),
				useF32 and readF32(r) or readF64(r)
			)
		end
		return result
	elseif tag == TAG.ARRAY_VECTOR3_F32
		or tag == TAG.ARRAY_VECTOR3_F64 then
		local count = readVarUInt(r)
		validateContainerCount(r, count, "dynamic Vector3 array")
		local result = table.create(count)
		local useF32 = tag == TAG.ARRAY_VECTOR3_F32
		for i = 1, count do
			result[i] = Vector3.new(
				useF32 and readF32(r) or readF64(r),
				useF32 and readF32(r) or readF64(r),
				useF32 and readF32(r) or readF64(r)
			)
		end
		return result
	elseif tag == TAG.ARRAY_COLOR3_RGB8
		or tag == TAG.ARRAY_COLOR3_F32
		or tag == TAG.ARRAY_COLOR3_F64 then
		local count = readVarUInt(r)
		validateContainerCount(r, count, "dynamic Color3 array")
		local result = table.create(count)
		for i = 1, count do
			if tag == TAG.ARRAY_COLOR3_RGB8 then
				result[i] = Color3.fromRGB(readByte(r), readByte(r), readByte(r))
			elseif tag == TAG.ARRAY_COLOR3_F32 then
				result[i] = Color3.new(readF32(r), readF32(r), readF32(r))
			else
				result[i] = Color3.new(readF64(r), readF64(r), readF64(r))
			end
		end
		return result
	elseif tag == TAG.ARRAY_UDIM then
		local count = readVarUInt(r)
		validateContainerCount(r, count, "dynamic UDim array")
		local result = table.create(count)
		for i = 1, count do result[i] = UDim.new(readNumberPayload(r), readVarInt(r)) end
		return result
	elseif tag == TAG.ARRAY_UDIM2 then
		local count = readVarUInt(r)
		validateContainerCount(r, count, "dynamic UDim2 array")
		local result = table.create(count)
		for i = 1, count do
			result[i] = UDim2.new(
				readNumberPayload(r),
				readVarInt(r),
				readNumberPayload(r),
				readVarInt(r)
			)
		end
		return result
	elseif tag == TAG.ARRAY_NUMBER_RANGE then
		local count = readVarUInt(r)
		validateContainerCount(r, count, "dynamic NumberRange array")
		local result = table.create(count)
		for i = 1, count do result[i] = NumberRange.new(readNumberPayload(r), readNumberPayload(r)) end
		return result
	elseif tag == TAG.ARRAY_BRICK_COLOR then
		local count = readVarUInt(r)
		validateContainerCount(r, count, "dynamic BrickColor array")
		local result = table.create(count)
		for i = 1, count do result[i] = BrickColor.new(readVarUInt(r)) end
		return result
	elseif tag == TAG.ARRAY_RECT then
		local count = readVarUInt(r)
		validateContainerCount(r, count, "dynamic Rect array")
		local result = table.create(count)
		for i = 1, count do
			result[i] = Rect.new(
				readNumberPayload(r),
				readNumberPayload(r),
				readNumberPayload(r),
				readNumberPayload(r)
			)
		end
		return result
	elseif tag == TAG.ARRAY_DATETIME then
		local count = readVarUInt(r)
		validateContainerCount(r, count, "dynamic DateTime array")
		local result = table.create(count)
		for i = 1, count do result[i] = readDateTimePayload(r) end
		return result
	elseif tag == TAG.ARRAY_RLE then
		local count = readVarUInt(r)
		if count > 4_194_304 then fail("dynamic RLE array count exceeds decode limit", 2) end
		local runCount = readVarUInt(r)
		validateContainerCount(r, runCount, "dynamic RLE run")
		if runCount > count and count > 0 then fail("dynamic RLE run count exceeds item count", 2) end
		local result = table.create(count)
		local position = 1
		for _ = 1, runCount do
			local length = readVarUInt(r)
			if length < 1 or position + length - 1 > count then fail("invalid RLE array", 2) end
			local item = dynamicRead(r, dictionary)
			for _ = 1, length do result[position] = item; position += 1 end
		end
		if position ~= count + 1 then fail("RLE array length mismatch", 2) end
		return result
	elseif tag == TAG.ARRAY_UINT_DELTA then
		local count = readVarUInt(r)
		validateContainerCount(r, count, "dynamic uint delta array")
		local result = table.create(count)
		if count > 0 then
			result[1] = readVarUInt(r)
			for i = 2, count do result[i] = result[i - 1] + readVarInt(r) end
		end
		return result
	elseif tag == TAG.ARRAY_INT_DELTA then
		local count = readVarUInt(r)
		validateContainerCount(r, count, "dynamic int delta array")
		local result = table.create(count)
		if count > 0 then
			result[1] = readVarInt(r)
			for i = 2, count do result[i] = result[i - 1] + readVarInt(r) end
		end
		return result
	elseif tag == TAG.MAP then
		local count = readVarUInt(r)
		validateContainerCount(r, count, "dynamic map")

		local result = {}
		local seenKeys: {[any]: boolean} = {}

		for _ = 1, count do
			local key = dynamicRead(r, dictionary)
			local keyType = typeof(key)

			if keyType ~= "string"
				and keyType ~= "number" then
				fail("invalid dynamic map key", 2)
			end

			if seenKeys[key] then
				fail("duplicate dynamic map key", 2)
			end

			seenKeys[key] = true
			result[key] = dynamicRead(r, dictionary)
		end

		return result
	elseif tag == TAG.MAP_STRING then
		local count = readVarUInt(r)
		validateContainerCount(r, count, "dynamic string map")

		local result = {}
		local seenKeys: {[string]: boolean} = {}

		for _ = 1, count do
			local key = readCompactString(
				r,
				dictionary
			)

			if seenKeys[key] then
				fail(
					"duplicate dynamic string map key",
					2
				)
			end

			seenKeys[key] = true
			result[key] = dynamicRead(
				r,
				dictionary
			)
		end

		return result
	end
	fail("invalid dynamic tag", 2)
	return nil
end

-- Handles write compressed string blob.
local function writeCompressedStringBlob(w: Writer, value: string, options: Options?)
	local packed = Compression.CompressString(value, options)
	writeVarUInt(w, buffer.len(packed))
	flushBits(w)
	ensureCapacity(w, buffer.len(packed))
	buffer.copy(w.Buffer, w.Position, packed, 0, buffer.len(packed))
	w.Position += buffer.len(packed)
	w.UsedBits += buffer.len(packed) * 8
end

-- Handles read compressed string blob.
local function readCompressedStringBlob(r: Reader): string
	local length = readVarUInt(r)
	if r.Position + length > r.Length then fail("truncated dictionary string", 2) end
	local data = buffer.create(length)
	buffer.copy(data, 0, r.Buffer, r.Position, length)
	r.Position += length
	return Compression.DecompressString(data)
end

-- Handles assert no cycles.
local function assertNoCycles(value: any, active: {[any]: boolean}, visited: {[any]: boolean})
	if typeof(value) ~= "table" then return end
	if active[value] then fail("cyclic tables cannot be encoded", 3) end
	if visited[value] then return end
	active[value] = true
	for key, child in pairs(value) do
		assertNoCycles(key, active, visited)
		assertNoCycles(child, active, visited)
	end
	active[value] = nil
	visited[value] = true
end

-- Handles encode dynamic value packet.
local function encodeDynamicValuePacket(
	value: any,
	options: Options?,
	schemaVersion: number,
	rawBits: number?,
	cyclesAlreadyChecked: boolean?
): Packet
	if not cyclesAlreadyChecked then
		assertNoCycles(value, {}, {})
	end

	local w = newWriter()
	local dictionary = makeDictionary(value, options)
	writeHeader(w, MODE.DYNAMIC, schemaVersion)
	writeVarUInt(w, #dictionary.Decode)
	for i = 1, #dictionary.Decode do
		writeCompressedStringBlob(w, dictionary.Decode[i], options)
	end
	dynamicWrite(w, value, options, dictionary)

	local data = finish(w)
	return packetFromEntropy(
		data,
		options,
		schemaVersion,
		rawBits or rawValueBits(value),
		w.UsedBits,
		w.PaddingBits
	)
end

-- Handles encode.
function Compression.Encode(value: any, options: Options?): Packet
	local schemaVersion = options and options.SchemaVersion or 1
	local kind = typeof(value)

	if kind == "buffer" then
		local compactBuffer = compressBufferBase(value, options)
		if not hasCompressionBufferMagic(compactBuffer) then
			compactBuffer = bufferRawPacket(value)
		end
		local baseMode = BUF.ModeBase(compactBuffer)
		local packet = packetFromEntropy(compactBuffer, options, schemaVersion, buffer.len(value) * 8)
		packet.Codec = "Buffer/"
			.. (packet.Entropy == "Huffman" and "Huffman/" or "")
			.. baseMode
		return packet
	end

	if kind == "table"
		and options
		and options.TableCompression ~= false
		and options.TableStrategy == "Compact" then
		assertNoCycles(value, {}, {})
		local compactTable,
			usefulBits,
			paddingBits =
			encodeCompactTableBuffer(
				value,
				options
			)

		return packetFromEntropy(
			compactTable,
			options,
			schemaVersion,
			rawValueBits(value),
			usefulBits,
			paddingBits
		)
	end

	local atom = encodeCompactAtom(value, options)
	if atom ~= nil then
		if kind == "boolean" then
			return markBooleanPacket(packetFromBuffer(atom, options, schemaVersion, rawValueBits(value)))
		end
		local packet = packetFromEntropy(atom, options, schemaVersion, rawValueBits(value))
		if kind == "string" then
			packet.Codec = packet.Entropy == "Huffman" and "CompactString+Huffman" or "CompactString"
		end
		return packet
	end

	return encodeDynamicValuePacket(
		value,
		options,
		schemaVersion,
		nil,
		false
	)
end

-- Handles decode.
function Compression.Decode(packet: Packet | buffer, options: Options?): any
	if typeof(packet) == "table" and (packet :: any).Passthrough == true then
		local passthroughPacket = packet :: Packet
		if passthroughPacket.Hash ~= nil and (not options or options.VerifyHash ~= false) then
			if hashBuffer(passthroughPacket.Data) ~= passthroughPacket.Hash then fail("hash verification failed", 2) end
		end
		local handled, passthroughValue = decodePassthroughPacket(passthroughPacket)
		if handled then return passthroughValue end
	end

	local data = unwrapPacket(packet, options)
	if hasCompressionBufferMagic(data) then
		return Compression.DecompressBuffer(data)
	end
	if buffer.len(data) >= 1 then
		local first = buffer.readu8(data, 0)
		if first == FMT.COMPACT_TABLE_MAGIC
			or first == FMT.COMPACT_MAPPED_TABLE_MAGIC then
			return decodeCompactTableBuffer(data)
		end
	end

	local atomHandled, atomValue = decodeCompactAtom(data)
	if atomHandled then return atomValue end

	local r = newReader(data)
	if r.Length >= 2 and buffer.readu8(data, 0) == FMT.COMPACT_NUMBER_MAGIC then
		readByte(r)
		local compactVersion = readByte(r)
		if compactVersion ~= FMT.VERSION and compactVersion ~= 24 and compactVersion ~= 23 and compactVersion ~= 22 and compactVersion ~= 21 and compactVersion ~= 20 and compactVersion ~= 19 and compactVersion ~= 18 and compactVersion ~= 17 and compactVersion ~= 16 and compactVersion ~= 15 and compactVersion ~= 14 and compactVersion ~= 13 and compactVersion ~= 12 and compactVersion ~= 11 and compactVersion ~= 10 and compactVersion ~= 9 and compactVersion ~= 8 and compactVersion ~= 7 then fail("unsupported compact number version", 2) end
		local value = readNumberPayload(r)
		if r.Position ~= r.Length then fail("trailing bytes in compact number payload", 2) end
		return value
	end
	local _, binaryVersion = readHeader(r, MODE.DYNAMIC)
	local dictionary: DictionaryState = {Encode = {}, Decode = {}}
	local count = readVarUInt(r)
	validateContainerCount(r, count, "string dictionary")
	for i = 1, count do
		local value =
			binaryVersion >= 8
			and readCompressedStringBlob(r)
			or readStringRaw(r)

		if dictionary.Encode[value] ~= nil then
			fail(
				"duplicate string dictionary entry",
				2
			)
		end

		dictionary.Decode[i] = value
		dictionary.Encode[value] = i
	end
	local value = dynamicRead(r, dictionary)
	alignReader(r)
	if r.Position ~= r.Length then fail("trailing bytes in dynamic payload", 2) end
	return value
end

-- Handles hash.
function Compression.Hash(data: buffer): number
	if typeof(data) ~= "buffer" then fail("Hash expects buffer", 2) end
	return hashBuffer(data)
end

-- Handles verify.
function Compression.Verify(data: buffer, hash: number): boolean
	if typeof(data) ~= "buffer" then fail("Verify expects buffer", 2) end
	if typeof(hash) ~= "number" then fail("Verify expects numeric hash", 2) end
	return hashBuffer(data) == hash
end

-- Handles optional.
function Compression.Optional(descriptor: Descriptor): Descriptor
	if typeof(descriptor) ~= "table" or typeof(descriptor.Kind) ~= "string" then fail("Optional expects Descriptor", 2) end
	local copy = table.clone(descriptor)
	copy.Optional = true
	return copy
end

-- Handles bool.
function Compression.Bool(): Descriptor return {Kind = "Bool"} end
-- Handles uint.
function Compression.UInt(): Descriptor return {Kind = "UInt"} end
-- Handles int.
function Compression.Int(): Descriptor return {Kind = "Int"} end
-- Handles float.
function Compression.Float(): Descriptor return {Kind = "Float"} end
-- Handles string.
function Compression.String(): Descriptor return {Kind = "String"} end
-- Compresses ed string.
function Compression.CompressedString(options: Options?): Descriptor return {Kind = "CompressedString", Options = options} end
-- Handles buffer.
function Compression.Buffer(options: Options?): Descriptor return {Kind = "Buffer", Options = options} end
-- Handles vector2.
function Compression.Vector2(): Descriptor return {Kind = "Vector2"} end
-- Handles vector3.
function Compression.Vector3(): Descriptor return {Kind = "Vector3"} end
-- Handles color3.
function Compression.Color3(): Descriptor return {Kind = "Color3"} end
-- Handles cframe.
function Compression.CFrame(): Descriptor return {Kind = "CFrame"} end
-- Handles udim.
function Compression.UDim(): Descriptor return {Kind = "UDim"} end
-- Handles udim2.
function Compression.UDim2(): Descriptor return {Kind = "UDim2"} end
-- Handles rect.
function Compression.Rect(): Descriptor return {Kind = "Rect"} end
-- Handles number range.
function Compression.NumberRange(): Descriptor return {Kind = "NumberRange"} end
-- Handles brick color.
function Compression.BrickColor(): Descriptor return {Kind = "BrickColor"} end
-- Handles date time.
function Compression.DateTime(): Descriptor return {Kind = "DateTime"} end
-- Handles array.
function Compression.Array(item: Descriptor): Descriptor
	if typeof(item) ~= "table"
		or typeof(item.Kind) ~= "string" then
		fail("Array expects Descriptor", 2)
	end

	return {
		Kind = "Array",
		Item = item,
	}
end

-- Handles object.
function Compression.Object(fields: {[string]: Descriptor}): Descriptor
	if typeof(fields) ~= "table" then
		fail("Object expects descriptor table", 2)
	end

	for name, descriptor in pairs(fields) do
		if typeof(name) ~= "string" then
			fail("Object field names must be strings", 2)
		end

		if typeof(descriptor) ~= "table"
			or typeof(descriptor.Kind) ~= "string" then
			fail(
				"Object field "
					.. name
					.. " must be a Descriptor",
				2
			)
		end
	end

	return {
		Kind = "Object",
		Fields = fields,
	}
end

-- Handles quantized.
function Compression.Quantized(minimum: number, maximum: number, bits: number): Descriptor
	if typeof(minimum) ~= "number"
		or typeof(maximum) ~= "number"
		or minimum ~= minimum
		or maximum ~= maximum
		or minimum == math.huge
		or minimum == -math.huge
		or maximum == math.huge
		or maximum == -math.huge then
		fail("Quantized bounds must be finite numbers", 2)
	end

	if maximum <= minimum then
		fail("Quantized maximum must be greater than minimum", 2)
	end

	if typeof(bits) ~= "number"
		or bits % 1 ~= 0
		or bits < 1
		or bits > 24 then
		fail("Quantized bits must be an integer from 1 to 24", 2)
	end

	return {
		Kind = "Quantized",
		Options = {
			Minimum = minimum,
			Maximum = maximum,
			Bits = bits,
		},
	}
end

-- Handles quantized vector3.
function Compression.QuantizedVector3(minimum: Vector3, maximum: Vector3, bits: number): Descriptor
	if typeof(minimum) ~= "Vector3"
		or typeof(maximum) ~= "Vector3" then
		fail("QuantizedVector3 expects Vector3 bounds", 2)
	end

	if maximum.X <= minimum.X
		or maximum.Y <= minimum.Y
		or maximum.Z <= minimum.Z then
		fail(
			"QuantizedVector3 maximum must exceed minimum on every axis",
			2
		)
	end

	if typeof(bits) ~= "number"
		or bits % 1 ~= 0
		or bits < 1
		or bits > 24 then
		fail(
			"QuantizedVector3 bits must be an integer from 1 to 24",
			2
		)
	end

	return {
		Kind = "QuantizedVector3",
		Options = {
			Minimum = minimum,
			Maximum = maximum,
			Bits = bits,
		},
	}
end

-- Handles descriptors equivalent.
FMT.DescriptorsEquivalent = function(a: Descriptor, b: Descriptor): boolean
	if a.Kind ~= b.Kind then
		return false
	end

	if a.Optional ~= b.Optional then
		return false
	end

	if a.Kind == "Array" then
		return a.Item ~= nil
			and b.Item ~= nil
			and FMT.DescriptorsEquivalent(
				a.Item :: Descriptor,
				b.Item :: Descriptor
			)
	end

	if a.Kind == "Object" then
		local fieldsA =
			a.Fields
		local fieldsB =
			b.Fields

		if fieldsA == nil
			or fieldsB == nil then
			return fieldsA == fieldsB
		end

		for name, childA in pairs(fieldsA) do
			local childB =
				fieldsB[name]

			if childB == nil
				or not FMT.DescriptorsEquivalent(
					childA,
					childB
				) then
				return false
			end
		end

		for name in pairs(fieldsB) do
			if fieldsA[name] == nil then
				return false
			end
		end
	end

	return true
end

-- Infers descriptor.
function Compression.InferDescriptor(value: any): Descriptor
	local kind = typeof(value)
	if kind == "boolean" then return Compression.Bool()
	elseif kind == "number" then
		if isSafeUInt(value) then return Compression.UInt() end
		if isSafeInt(value) then return Compression.Int() end
		return Compression.Float()
	elseif kind == "string" then
		if #value >= 24 then return Compression.CompressedString() end
		return Compression.String()
	elseif kind == "buffer" then return Compression.Buffer()
	elseif kind == "Vector2" then return Compression.Vector2()
	elseif kind == "Vector3" then return Compression.Vector3()
	elseif kind == "Color3" then return Compression.Color3()
	elseif kind == "CFrame" then return Compression.CFrame()
	elseif kind == "UDim" then return Compression.UDim()
	elseif kind == "UDim2" then return Compression.UDim2()
	elseif kind == "Rect" then return Compression.Rect()
	elseif kind == "NumberRange" then return Compression.NumberRange()
	elseif kind == "BrickColor" then return Compression.BrickColor()
	elseif kind == "DateTime" then return Compression.DateTime()
	elseif kind == "table" then
		if isArray(value) then
			if #value == 0 then fail("InferDescriptor cannot infer the item type of an empty array", 2) end
			local item = Compression.InferDescriptor(value[1])
			for i = 2, #value do
				local nextDescriptor = Compression.InferDescriptor(value[i])
				if not FMT.DescriptorsEquivalent(item, nextDescriptor) then
					fail("InferDescriptor requires homogeneous arrays; mismatch at index " .. tostring(i), 2)
				end
			end
			return Compression.Array(item)
		end
		local fields: {[string]: Descriptor} = {}
		for key, child in pairs(value) do
			if typeof(key) ~= "string" then fail("InferDescriptor object keys must be strings", 2) end
			fields[key] = Compression.InferDescriptor(child)
		end
		return Compression.Object(fields)
	end
	fail("InferDescriptor could not infer descriptor for " .. kind, 2)
	return Compression.String()
end

-- Handles auto descriptor.
function Compression.AutoDescriptor(value: any): Descriptor
	return Compression.InferDescriptor(value)
end

-- Handles string mode.
function Compression.StringMode(data: buffer): string
	if typeof(data) ~= "buffer" then return "Invalid" end
	if isHuffmanFrame(data) then
		local ok, decoded = pcall(huffmanDecodeFrame, data)
		if not ok then return "Invalid" end
		return "Huffman/" .. Compression.StringMode(decoded)
	end
	if buffer.len(data) == 0 then return "RawPassthrough" end
	local mode = buffer.readu8(data, 0)
	if mode > STR.RAW_V3 then return "RawPassthrough" end
	if mode == STR.RAW then return "Raw" end
	if mode == STR.LZ_V1 then return "LZ-v1" end
	if mode == STR.NUMERIC4 then return "Numeric4" end
	if mode == STR.IDENTIFIER6 then return "Identifier6" end
	if mode == STR.ASCII7 then return "ASCII7" end
	if mode == STR.LZ_V2 then return "LZ-v2" end
	if mode == STR.RAW_V3 then return "Raw" end
	return "Unknown"
end

-- Handles string stats.
function Compression.StringStats(value: string, options: Options?): {[string]: any}
	if typeof(value) ~= "string" then fail("StringStats expects string", 2) end
	local data = Compression.CompressString(value, options)
	local rawBytes = #value
	local bytes = buffer.len(data)
	local delta = rawBytes - bytes
	local saved = math.max(0, delta)
	local expanded = math.max(0, -delta)
	return {
		Mode = Compression.StringMode(data),
		Bytes = bytes,
		Bits = bytes * 8,
		UsefulBits = bytes * 8,
		PhysicalBits = bytes * 8,
		SavedBits = saved * 8,
		ExpandedBits = expanded * 8,
		BitSavingsPercent = rawBytes > 0 and math.max(0, delta / rawBytes * 100) or 0,
		RawBytes = rawBytes,
		SavedBytes = saved,
		ExpandedBytes = expanded,
		ByteDelta = delta,
		SavingsPercent = rawBytes > 0 and math.max(0, delta / rawBytes * 100) or 0,
		ExpansionPercent = rawBytes > 0 and math.max(0, -delta / rawBytes * 100) or 0,
		Ratio = rawBytes > 0 and bytes / rawBytes or 1,
		IsSmaller = bytes < rawBytes,
		EncodedBytesText = Compression.FormatBytes(bytes),
		RawBytesText = Compression.FormatBytes(rawBytes),
		SavedBytesText = Compression.FormatBytes(saved),
		ExpandedBytesText = Compression.FormatBytes(expanded),
	}
end

-- Prints string stats.
function Compression.PrintStringStats(value: string, options: Options?): {[string]: any}
	local stats = Compression.StringStats(value, options)
	print("========== Compression v2.6.4 String Stats ==========")
	print("Mode:", stats.Mode)
	print("Raw:", stats.RawBytesText)
	print("Encoded:", stats.EncodedBytesText)
	if stats.ExpandedBytes > 0 then
		print("Expanded:", stats.ExpandedBytesText)
		print(string.format("Expansion: %.2f%%", stats.ExpansionPercent))
	else
		print("Saved:", stats.SavedBytesText)
		print(string.format("Savings: %.2f%%", stats.SavingsPercent))
	end
	print(string.format("Ratio: %.4fx", stats.Ratio))
	print("======================================================")
	return stats
end

-- Safely attempts to decompress string without throwing.
function Compression.TryDecompressString(data: buffer): (boolean, string?, string?)
	local ok, result = pcall(
		Compression.DecompressString,
		data
	)

	if ok then
		return true, result, nil
	end

	return false,
		nil,
		tostring(result)
end

-- Compresses string smart.
function Compression.CompressStringSmart(value: string, options: Options?): (buffer, boolean)
	if typeof(value) ~= "string" then fail("CompressStringSmart expects string", 2) end
	local packed = Compression.CompressString(value, options)
	if buffer.len(packed) < #value then return packed, true end
	local raw = buffer.create(#value)
	if #value > 0 then buffer.writestring(raw, 0, value) end
	return raw, false
end

-- Decompresses string smart.
function Compression.DecompressStringSmart(data: buffer, compressed: boolean): string
	if typeof(data) ~= "buffer" then fail("DecompressStringSmart expects buffer", 2) end
	if compressed then return Compression.DecompressString(data) end
	local length = buffer.len(data)
	return length > 0 and buffer.readstring(data, 0, length) or ""
end

-- Handles auto codec for.
local function autoCodecFor(value: any, packet: Packet, options: Options?): string
	if packet.Codec ~= nil then return packet.Codec end
	local kind = typeof(value)
	local inspectData = packet.Data
	local suffix = ""
	if isHuffmanFrame(inspectData) then
		local ok, decoded = pcall(huffmanDecodeFrame, inspectData)
		if ok then
			inspectData = decoded
			suffix = "+Huffman"
		end
	end

	local base: string
	if kind == "buffer" then
		base = "Buffer/" .. Compression.BufferMode(packet.Data)
		return base
	elseif kind == "number" then
		local tag = buffer.len(inspectData) > 0 and buffer.readu8(inspectData, 0) or -1
		if tag == ATOM.DECIMAL then base = "CompactDecimal"
		elseif tag == ATOM.FLOAT32 then base = "CompactFloat32"
		else base = "CompactNumber" end
	elseif kind == "UDim" then base = "CompactUDim"
	elseif kind == "UDim2" then base = "CompactUDim2"
	elseif kind == "Rect" then base = "CompactRect"
	elseif kind == "NumberRange" then base = "CompactNumberRange"
	elseif kind == "BrickColor" then base = "CompactBrickColor"
	elseif kind == "DateTime" then base = "CompactDateTime"
	elseif kind == "table" then
		if buffer.len(inspectData) > 0 then
			local first = buffer.readu8(inspectData, 0)
			if first == FMT.COMPACT_TABLE_MAGIC or first == FMT.COMPACT_MAPPED_TABLE_MAGIC then
				base = "Table/" .. Compression.TableMode(packet.Data, options)
				return base
			end
		end
		base = "DynamicTable"
	elseif kind == "string" then base = "CompactString"
	elseif kind == "boolean" then return "CompactBoolean1Bit"
	elseif kind == "nil" then base = "CompactNil"
	elseif kind == "Vector2" then
		base = buffer.len(inspectData) > 0 and buffer.readu8(inspectData, 0) == ATOM.VECTOR2_F32 and "CompactVector2F32" or "CompactVector2"
	elseif kind == "Vector3" then
		base = buffer.len(inspectData) > 0 and buffer.readu8(inspectData, 0) == ATOM.VECTOR3_F32 and "CompactVector3F32" or "CompactVector3"
	elseif kind == "Color3" then
		local tag = buffer.len(inspectData) > 0 and buffer.readu8(inspectData, 0) or -1
		if tag == ATOM.COLOR3_F32 then base = "CompactColor3F32"
		elseif tag == ATOM.COLOR3_F64 then base = "CompactColor3F64"
		else base = "CompactColor3" end
	elseif kind == "CFrame" then
		base = buffer.len(inspectData) > 0 and buffer.readu8(inspectData, 0) == ATOM.CFRAME_F32 and "CompactCFrameF32" or "CompactCFrame"
	else
		base = "Dynamic" .. kind
	end
	return base .. suffix
end
-- Handles dynamic table packet.
local function dynamicTablePacket(
	value: {[any]: any},
	options: Options?,
	rawBits: number,
	cyclesAlreadyChecked: boolean
): Packet
	local packet = encodeDynamicValuePacket(
		value,
		options,
		options and options.SchemaVersion or 1,
		rawBits,
		cyclesAlreadyChecked
	)
	packet.Codec = packet.Entropy == "Huffman" and "DynamicTable+Huffman" or "DynamicTable"
	return packet
end

-- Handles adaptive table packet.
local function adaptiveTablePacket(value: {[any]: any}, options: Options?): Packet
	assertNoCycles(value, {}, {})
	local rawBits = rawValueBits(value)

	if options and options.TableStrategy == "Dynamic" then
		return dynamicTablePacket(value, options, rawBits, true)
	end

	if options and options.TableStrategy == "Compact" then
		local compactOK,
			compactData,
			compactUsefulBits,
			compactPaddingBits =
			pcall(
				encodeCompactTableBuffer,
				value,
				options
			)

		if compactOK then
			local packet = packetFromEntropy(
				compactData,
				options,
				options and options.SchemaVersion or 1,
				rawBits,
				compactUsefulBits,
				compactPaddingBits
			)
			packet.Codec = "Table/" .. (CT.TableModeFromData(compactData) or "Invalid")
			return packet
		end

		return dynamicTablePacket(
			value,
			options,
			rawBits,
			true
		)
	end

	local compactOK,
		compactData,
		compactUsefulBits,
		compactPaddingBits =
		pcall(
			encodeCompactTableBuffer,
			value,
			options
		)

	local dynamicPacket =
		dynamicTablePacket(
			value,
			options,
			rawBits,
			true
		)

	if not compactOK then
		return dynamicPacket
	end

	local compactPacket = packetFromEntropy(
		compactData,
		options,
		options and options.SchemaVersion or 1,
		rawBits,
		compactUsefulBits,
		compactPaddingBits
	)
	compactPacket.Codec = "Table/" .. (CT.TableModeFromData(compactData) or "Invalid")

	if dynamicPacket.Bytes < compactPacket.Bytes then
		return dynamicPacket
	end

	return compactPacket
end

-- Handles compress.
function Compression.Compress(value: any, options: Options?): Packet
	if typeof(value) == "table"
		and (not options or options.TableCompression ~= false) then
		return adaptiveTablePacket(value, options)
	end

	return Compression.Encode(value, options)
end

-- Handles decompress.
function Compression.Decompress(packet: Packet | buffer, options: Options?): any
	return Compression.Decode(packet, options)
end

-- Handles auto.
function Compression.Auto(value: any, options: Options?): Packet
	local packet = Compression.Compress(value, options)
	local kind = typeof(value)
	packet.ValueType = kind
	packet.Codec = autoCodecFor(value, packet, options)
	if kind == "boolean" then
		markBooleanPacket(packet)
	end

	if not options or options.AllowExpansion ~= true then
		local rawBytes, rawCodec = rawAutoByteCountAndCodec(value)
		if rawBytes ~= nil and rawCodec ~= nil and rawBytes < packet.Bytes then
			local rawData = rawAutoData(value)
			if rawData ~= nil then
				local rawPacket = packetFromBuffer(rawData, options, options and options.SchemaVersion or 1, rawValueBits(value))
				rawPacket.ValueType = kind
				rawPacket.Codec = rawCodec
				rawPacket.Passthrough = true
				return rawPacket
			end
		end
	end

	return packet
end

-- Handles auto decompress.
function Compression.AutoDecompress(packet: Packet | buffer, options: Options?): any
	return Compression.Decompress(packet, options)
end

-- Safely attempts to auto without throwing.
function Compression.TryAuto(value: any, options: Options?): (boolean, Packet?, string?)
	local ok, result = pcall(Compression.Auto, value, options)
	if ok then return true, result, nil end
	return false, nil, tostring(result)
end

-- Checks whether it can auto.
function Compression.CanAuto(value: any, options: Options?): boolean
	local ok = pcall(Compression.Auto, value, options)
	return ok
end

-- Safely attempts to auto decompress without throwing.
function Compression.TryAutoDecompress(packet: Packet | buffer, options: Options?): (boolean, any, string?)
	local ok, result = pcall(Compression.AutoDecompress, packet, options)
	if ok then return true, result, nil end
	return false, nil, tostring(result)
end

-- Handles auto stats.
function Compression.AutoStats(value: any, options: Options?): {[string]: any}
	local packet = Compression.Auto(value, options)
	local stats = Compression.Stats(packet)
	stats.ValueType = packet.ValueType
	stats.Codec = packet.Codec
	stats.EncodedBytesText = Compression.FormatBytes(stats.Bytes)
	stats.RawBytesText = stats.RawBytes and Compression.FormatBytes(stats.RawBytes) or nil
	stats.SavedBytesText = Compression.FormatBytes(stats.SavedBytes or 0)
	stats.ExpandedBytesText = Compression.FormatBytes(stats.ExpandedBytes or 0)
	return stats
end

-- Prints auto stats.
function Compression.PrintAutoStats(value: any, options: Options?): {[string]: any}
	local stats = Compression.AutoStats(value, options)
	print("========== Compression v2.6.4 Auto Stats ==========")
	print("Type:", stats.ValueType)
	print("Codec:", stats.Codec)
	if stats.Entropy ~= nil then
		print("Entropy:", stats.Entropy)
		if stats.Entropy == "Huffman" then
			print("Huffman bytes:", stats.EntropyBytesBefore, "->", stats.EntropyBytesAfter)
		end
	end
	print("Raw:", stats.RawBytesText or "Unknown")
	print("Encoded:", stats.EncodedBytesText)
	if stats.UsefulBits ~= nil
		and stats.PhysicalBits ~= nil
		and stats.UsefulBits ~= stats.PhysicalBits then
		print("Useful bits:", stats.UsefulBits)
		print("Physical bits:", stats.PhysicalBits)
		print(
			"Padding bits:",
			stats.PaddingBits or 0
		)
	end
	if (stats.ExpandedBytes or 0) > 0 then
		print("Expanded:", stats.ExpandedBytesText)
	else
		print("Saved:", stats.SavedBytesText)
	end
	if (stats.ExpandedBytes or 0) > 0 then
		if stats.ExpansionPercent ~= nil then
			print(string.format("Expansion: %.2f%%", stats.ExpansionPercent))
		end
	elseif stats.SavingsPercent ~= nil then
		print(string.format("Savings: %.2f%%", stats.SavingsPercent))
	end
	if stats.Ratio ~= nil then print(string.format("Ratio: %.4fx", stats.Ratio)) end
	print("====================================================")
	return stats
end

-- Compresses number.
function Compression.CompressNumber(value: number, options: Options?): buffer
	if typeof(value) ~= "number" then fail("CompressNumber expects number", 2) end
	local w = newWriter(16)
	writeNumberPayload(w, value)
	local data = finish(w)
	local encoded = maybeHuffman(data, options)
	return encoded
end

-- Decompresses number.
function Compression.DecompressNumber(data: buffer): number
	if typeof(data) ~= "buffer" then fail("DecompressNumber expects buffer", 2) end
	data = entropyDecodeIfNeeded(data)
	local r = newReader(data)
	local value = readNumberPayload(r)
	if r.Position ~= r.Length then fail("trailing bytes in number payload", 2) end
	return value
end

-- Handles number stats.
function Compression.NumberStats(value: number): {[string]: any}
	local data = Compression.CompressNumber(value)
	local bytes = buffer.len(data)
	local bits = bytes * 8
	local rawBytes = 8
	local rawBits = 64
	local saved = math.max(0, rawBytes - bytes)
	local expanded = math.max(0, bytes - rawBytes)
	local savedBits = math.max(0, rawBits - bits)
	local expandedBits = math.max(0, bits - rawBits)

	return {
		Bytes = bytes,
		Bits = bits,
		UsefulBits = bits,
		PhysicalBits = bits,
		RawBytes = rawBytes,
		RawBits = rawBits,
		SavedBytes = saved,
		ExpandedBytes = expanded,
		SavedBits = savedBits,
		ExpandedBits = expandedBits,
		SavingsPercent = rawBytes > 0
			and saved / rawBytes * 100
			or 0,
		ExpansionPercent = rawBytes > 0
			and expanded / rawBytes * 100
			or 0,
		Ratio = bytes / rawBytes,
		IsSmaller = bytes < rawBytes,
		BytesText = Compression.FormatBytes
			and Compression.FormatBytes(bytes)
			or tostring(bytes) .. " B",
	}
end

TAG.TABLE_MODE_NAMES = {
	[TAG.ARRAY] = "MixedArray",
	[TAG.MAP] = "Map",
	[TAG.ARRAY_BOOL] = "BoolArray",
	[TAG.ARRAY_UINT] = "UIntArray",
	[TAG.ARRAY_INT] = "IntArray",
	[TAG.ARRAY_FLOAT] = "FloatArray",
	[TAG.ARRAY_FLOAT32] = "Float32Array",
	[TAG.ARRAY_STRING] = "StringArray",
	[TAG.ARRAY_RLE] = "RLEArray",
	[TAG.MAP_STRING] = "StringMap",
	[TAG.ARRAY_UINT_DELTA] = "UIntDeltaArray",
	[TAG.ARRAY_INT_DELTA] = "IntDeltaArray",
	[TAG.ARRAY_VECTOR2_F32] = "Vector2F32Array",
	[TAG.ARRAY_VECTOR2_F64] = "Vector2F64Array",
	[TAG.ARRAY_VECTOR3_F32] = "Vector3F32Array",
	[TAG.ARRAY_VECTOR3_F64] = "Vector3F64Array",
	[TAG.ARRAY_COLOR3_RGB8] = "Color3RGB8Array",
	[TAG.ARRAY_COLOR3_F32] = "Color3F32Array",
	[TAG.ARRAY_COLOR3_F64] = "Color3F64Array",
	[TAG.ARRAY_UDIM] = "UDimArray",
	[TAG.ARRAY_UDIM2] = "UDim2Array",
	[TAG.ARRAY_NUMBER_RANGE] = "NumberRangeArray",
	[TAG.ARRAY_BRICK_COLOR] = "BrickColorArray",
	[TAG.ARRAY_RECT] = "RectArray",
	[TAG.ARRAY_DATETIME] = "DateTimeArray",
}

-- Handles table entry count.
MODE.TableEntryCount = function(value: {[any]: any}): number
	local count = 0
	for _ in pairs(value) do count += 1 end
	return count
end

-- Handles analyze table structure.
MODE.AnalyzeTableStructure = function(value: {[any]: any}): {[string]: any}
	local result = {
		Kind = isArray(value) and "Array" or "Map",
		Entries = MODE.TableEntryCount(value),
		TotalEntries = 0,
		Tables = 0,
		Arrays = 0,
		Maps = 0,
		MaxDepth = 0,
		Booleans = 0,
		Numbers = 0,
		Strings = 0,
		Vector2s = 0,
		Vector3s = 0,
		Color3s = 0,
		CFrames = 0,
		UDims = 0,
		UDim2s = 0,
		Rects = 0,
		NumberRanges = 0,
		BrickColors = 0,
		DateTimes = 0,
		Buffers = 0,
		OtherValues = 0,
		StringKeys = 0,
		NumberKeys = 0,
		RepeatedStringKeys = 0,
		MappedKeyCandidates = 0,
	}

	local active: {[any]: boolean} = {}
	local stringKeyCounts: {[string]: number} = {}

	-- Handles visit scalar.
	local function visitScalar(item: any)
		local kind = typeof(item)
		if kind == "boolean" then result.Booleans += 1
		elseif kind == "number" then result.Numbers += 1
		elseif kind == "string" then result.Strings += 1
		elseif kind == "Vector2" then result.Vector2s += 1
		elseif kind == "Vector3" then result.Vector3s += 1
		elseif kind == "Color3" then result.Color3s += 1
		elseif kind == "CFrame" then result.CFrames += 1
		elseif kind == "UDim" then result.UDims += 1
		elseif kind == "UDim2" then result.UDim2s += 1
		elseif kind == "Rect" then result.Rects += 1
		elseif kind == "NumberRange" then result.NumberRanges += 1
		elseif kind == "BrickColor" then result.BrickColors += 1
		elseif kind == "DateTime" then result.DateTimes += 1
		elseif kind == "buffer" then result.Buffers += 1
		elseif kind ~= "nil" and kind ~= "table" then result.OtherValues += 1 end
	end

	-- Handles visit table.
	local function visitTable(current: {[any]: any}, depth: number)
		if active[current] then fail("cyclic tables cannot be analyzed", 3) end
		active[current] = true
		result.Tables += 1
		result.MaxDepth = math.max(result.MaxDepth, depth)
		local array = isArray(current)
		if array then result.Arrays += 1 else result.Maps += 1 end

		for key, child in pairs(current) do
			result.TotalEntries += 1
			if not array then
				local keyKind = typeof(key)
				if keyKind == "string" then
					result.StringKeys += 1
					stringKeyCounts[key] =
						(stringKeyCounts[key] or 0) + 1
				elseif keyKind == "number" then
					result.NumberKeys += 1
				end
			end
			visitScalar(key)
			if typeof(child) == "table" then visitTable(child, depth + 1) else visitScalar(child) end
		end
		active[current] = nil
	end

	visitTable(value, 1)

	for key, count in pairs(stringKeyCounts) do
		if count >= 2 then
			result.RepeatedStringKeys += 1

			local _, keyBytes =
				tinyStringMode(key)

			if keyBytes * count
				- keyBytes
				- count > 0 then
				result.MappedKeyCandidates += 1
			end
		end
	end

	return result
end

-- Handles top level dynamic tag.
MODE.TopLevelDynamicTag = function(packet: Packet | buffer, options: Options?): number?
	local data = unwrapPacket(packet, options)
	if buffer.len(data) < 1 then return nil end
	local first = buffer.readu8(data, 0)
	if first == FMT.COMPACT_NUMBER_MAGIC
		or hasCompressionBufferMagic(data)
		or first == FMT.COMPACT_TABLE_MAGIC
		or first == FMT.COMPACT_MAPPED_TABLE_MAGIC then
		return nil
	end
	local r = newReader(data)
	local ok, tag = pcall(function()
		local _, binaryVersion = readHeader(r, MODE.DYNAMIC)
		local count = readVarUInt(r)
		for _ = 1, count do
			if binaryVersion >= 8 then readCompressedStringBlob(r) else readStringRaw(r) end
		end
		alignReader(r)
		return readByte(r)
	end)
	if not ok then return nil end
	return tag
end

-- Compresses table.
function Compression.CompressTable(value: {[any]: any}, options: Options?): buffer
	if typeof(value) ~= "table" then fail("CompressTable expects table", 2) end

	if options and options.TableCompression == false then
		return Compression.Encode(value, options).Data
	end

	return adaptiveTablePacket(value, options).Data
end

-- Compresses table packet.
function Compression.CompressTablePacket(value: {[any]: any}, options: Options?): Packet
	if typeof(value) ~= "table" then fail("CompressTablePacket expects table", 2) end

	if options and options.TableCompression == false then
		return Compression.Encode(value, options)
	end

	return adaptiveTablePacket(value, options)
end

-- Decompresses table.
function Compression.DecompressTable(packet: Packet | buffer, options: Options?): {[any]: any}
	local data = unwrapPacket(packet, options)
	local value
	if buffer.len(data) >= 1
		and (
			buffer.readu8(data, 0) == FMT.COMPACT_TABLE_MAGIC
				or buffer.readu8(data, 0) == FMT.COMPACT_MAPPED_TABLE_MAGIC
		) then
		value = decodeCompactTableBuffer(data)
	else
		value = Compression.Decode(
			data,
			options
		)
	end
	if typeof(value) ~= "table" then fail("decoded value is not a table", 2) end
	return value
end

-- Safely attempts to decompress table without throwing.
function Compression.TryDecompressTable(
	packet: Packet | buffer,
	options: Options?
): (boolean, {[any]: any}?, string?)
	local ok, result = pcall(
		Compression.DecompressTable,
		packet,
		options
	)

	if ok then
		return true, result, nil
	end

	return false,
		nil,
		tostring(result)
end

-- Checks whether compact table.
function Compression.IsCompactTable(packet: Packet | buffer, options: Options?): boolean
	local data = unwrapPacket(packet, options)
	if buffer.len(data) < 1 then return false end
	local first = buffer.readu8(data, 0)
	return first == FMT.COMPACT_TABLE_MAGIC
		or first == FMT.COMPACT_MAPPED_TABLE_MAGIC
end

-- Handles table mode.
function Compression.TableMode(packet: Packet | buffer, options: Options?): string
	local data = unwrapPacket(packet, options)
	local compactMode = CT.TableModeFromData(data)
	if compactMode ~= nil then return compactMode end
	local tag = MODE.TopLevelDynamicTag(
		data,
		nil
	)
	if tag == nil then return "Invalid" end
	return TAG.TABLE_MODE_NAMES[tag] or "NotTable"
end

-- Handles table bytes.
function Compression.TableBytes(packet: Packet | buffer, options: Options?): number
	local data = unwrapPacket(packet, options)
	return buffer.len(data)
end

-- Handles table entries.
function Compression.TableEntries(value: {[any]: any}): number
	if typeof(value) ~= "table" then fail("TableEntries expects table", 2) end
	return MODE.TableEntryCount(value)
end

-- Handles table structure.
function Compression.TableStructure(value: {[any]: any}): {[string]: any}
	if typeof(value) ~= "table" then fail("TableStructure expects table", 2) end
	return MODE.AnalyzeTableStructure(value)
end

-- Handles table stats.
function Compression.TableStats(value: {[any]: any}, options: Options?): {[string]: any}
	if typeof(value) ~= "table" then
		fail(
			"TableStats expects table",
			2
		)
	end

	local packet =
		Compression.CompressTablePacket(
			value,
			options
		)

	local bytes = packet.Bytes
	local physicalBits =
		packet.PhysicalBits
		or bytes * 8
	local usefulBits =
		packet.UsefulBits
		or packet.Bits
		or physicalBits
	local paddingBits =
		packet.PaddingBits
		or math.max(
			0,
			physicalBits - usefulBits
		)

	local rawBits =
		rawValueBits(value)
	local rawBytes =
		math.ceil(rawBits / 8)

	local byteDelta =
		rawBytes - bytes
	local savedBytes =
		math.max(
			0,
			byteDelta
		)
	local expandedBytes =
		math.max(
			0,
			-byteDelta
		)

	local bitDelta =
		rawBits - usefulBits
	local savedBits =
		math.max(
			0,
			bitDelta
		)
	local expandedBits =
		math.max(
			0,
			-bitDelta
		)

	local structure =
		MODE.AnalyzeTableStructure(value)

	local keyMap =
		buildCompactKeyMap(
			value,
			options
		)

	local mode =
		Compression.TableMode(
			packet,
			options
		)

	local mapped =
		string.find(
			mode,
			"CompactMapped",
			1,
			true
		) == 1

	local mappingOptions =
		options
		and table.clone(options)
		or {}

	mappingOptions.TableStrategy =
		"Compact"
	mappingOptions.TableKeyMapping =
		true

	local mappedOK,
		mappedCompact =
		pcall(
			Compression.CompressTablePacket,
			value,
			mappingOptions
		)

	local unmappedOptions =
		options
		and table.clone(options)
		or {}

	unmappedOptions.TableStrategy =
		"Compact"
	unmappedOptions.TableKeyMapping =
		false

	local unmappedOK,
		unmappedCompact =
		pcall(
			Compression.CompressTablePacket,
			value,
			unmappedOptions
		)

	local mappedCompactBytes =
		mappedOK
		and mappedCompact.Bytes
		or nil

	local unmappedCompactBytes =
		unmappedOK
		and unmappedCompact.Bytes
		or nil

	local mappingSavedBytes =
		mappedCompactBytes
		and unmappedCompactBytes
		and math.max(
			0,
			unmappedCompactBytes
			- mappedCompactBytes
		)
		or 0

	local mappingSavingsPercent =
		unmappedCompactBytes
		and unmappedCompactBytes > 0
		and mappingSavedBytes
		/ unmappedCompactBytes
		* 100
		or 0

	return {
		Mode = mode,
		Format = mapped
			and "CompactMappedBuffer"
			or (
				Compression.IsCompactTable(
					packet,
					options
				)
				and "CompactBuffer"
				or "DynamicBuffer"
			),

		Mapped = mapped,
		MappingAvailable =
			#keyMap.Decode > 0,
		MappedKeys =
			mapped
			and #keyMap.Decode
			or 0,
		AvailableMappedKeys =
			#keyMap.Decode,
		MappedCompactBytes =
			mappedCompactBytes,
		UnmappedCompactBytes =
			unmappedCompactBytes,
		MappingSavedBytes =
			mappingSavedBytes,
		MappingSavingsPercent =
			mappingSavingsPercent,

		Bytes = bytes,
		Bits = usefulBits,
		UsefulBits = usefulBits,
		PhysicalBits = physicalBits,
		PaddingBits = paddingBits,

		RawBytes = rawBytes,
		RawBits = rawBits,

		SavedBytes = savedBytes,
		ExpandedBytes = expandedBytes,
		ByteDelta = byteDelta,

		SavedBits = savedBits,
		ExpandedBits = expandedBits,
		BitDelta = bitDelta,

		SavingsPercent =
			rawBytes > 0
			and math.max(
				0,
				byteDelta
				/ rawBytes
				* 100
			)
			or 0,

		ExpansionPercent =
			rawBytes > 0
			and math.max(
				0,
				-byteDelta
				/ rawBytes
				* 100
			)
			or 0,

		BitSavingsPercent =
			rawBits > 0
			and math.max(
				0,
				bitDelta
				/ rawBits
				* 100
			)
			or 0,

		BitExpansionPercent =
			rawBits > 0
			and math.max(
				0,
				-bitDelta
				/ rawBits
				* 100
			)
			or 0,

		Ratio =
			rawBytes > 0
			and bytes / rawBytes
			or 1,

		IsSmaller =
			bytes < rawBytes,
		IsPhysicallySmaller =
			bytes < rawBytes,
		IsBitSmaller =
			usefulBits < rawBits,

		Kind = structure.Kind,
		Entries = structure.Entries,
		TotalEntries = structure.TotalEntries,
		Tables = structure.Tables,
		Arrays = structure.Arrays,
		Maps = structure.Maps,
		MaxDepth = structure.MaxDepth,
		Booleans = structure.Booleans,
		Numbers = structure.Numbers,
		Strings = structure.Strings,
		Vector2s = structure.Vector2s,
		Vector3s = structure.Vector3s,
		Color3s = structure.Color3s,
		CFrames = structure.CFrames,
		UDims = structure.UDims,
		UDim2s = structure.UDim2s,
		Rects = structure.Rects,
		NumberRanges = structure.NumberRanges,
		BrickColors = structure.BrickColors,
		DateTimes = structure.DateTimes,
		Buffers = structure.Buffers,
		StringKeys = structure.StringKeys,
		NumberKeys = structure.NumberKeys,
		RepeatedStringKeys =
			structure.RepeatedStringKeys,
		MappedKeyCandidates =
			#keyMap.Decode,

		EncodedBytesText =
			Compression.FormatBytes(bytes),
		RawBytesText =
			Compression.FormatBytes(rawBytes),
		SavedBytesText =
			Compression.FormatBytes(savedBytes),
		ExpandedBytesText =
			Compression.FormatBytes(expandedBytes),
		MappingSavedBytesText =
			Compression.FormatBytes(
				mappingSavedBytes
			),
	}
end

-- Prints table stats.
function Compression.PrintTableStats(value: {[any]: any}, options: Options?): {[string]: any}
	local stats = Compression.TableStats(value, options)
	print("========== Compression v2.6.4 Table Stats ==========")
	print("Mode:", stats.Mode)
	print("Format:", stats.Format)
	print("Kind:", stats.Kind)
	print("Entries:", stats.Entries, "| Total nested entries:", stats.TotalEntries)
	print("Tables:", stats.Tables, "| Arrays:", stats.Arrays, "| Maps:", stats.Maps, "| Depth:", stats.MaxDepth)
	print(
		"Map keys:",
		stats.StringKeys,
		"| Repeated:",
		stats.RepeatedStringKeys,
		"| Available mapped:",
		stats.AvailableMappedKeys,
		"| Used:",
		stats.MappedKeys
	)

	if stats.MappingSavedBytes > 0 then
		print(
			"Mapping saved:",
			stats.MappingSavedBytesText,
			string.format(
				"(%.2f%% vs unmapped Compact)",
				stats.MappingSavingsPercent
			)
		)
	end

	print("Estimated raw:", stats.RawBytesText)
	print("Compressed:", stats.EncodedBytesText)

	if stats.PaddingBits > 0 then
		print(
			"Useful bits:",
			stats.UsefulBits,
			"| Physical bits:",
			stats.PhysicalBits,
			"| Padding:",
			stats.PaddingBits
		)
	end
	if stats.ExpandedBytes > 0 then
		print("Expanded:", stats.ExpandedBytesText)
		print(string.format("Expansion: %.2f%%", stats.ExpansionPercent))
	else
		print("Saved:", stats.SavedBytesText)
		print(string.format("Savings: %.2f%%", stats.SavingsPercent))
	end
	print(string.format("Ratio: %.4fx", stats.Ratio))
	print("=====================================================")
	return stats
end

-- Estimates raw bytes.
function Compression.EstimateRawBytes(value: any): number
	return math.ceil(rawValueBits(value) / 8)
end

-- Formats bytes.
function Compression.FormatBytes(bytes: number): string
	if bytes ~= bytes then return "NaN B" end
	if bytes == math.huge then return "inf B" end
	if bytes == -math.huge then return "-inf B" end
	local sign = bytes < 0 and "-" or ""
	local value = math.abs(bytes)
	local units = {"B", "KB", "MB", "GB", "TB"}
	local unit = 1
	while value >= 1024 and unit < #units do
		value /= 1024
		unit += 1
	end
	if unit == 1 then return sign .. tostring(math.floor(value + 0.5)) .. " B" end
	return string.format("%s%.2f %s", sign, value, units[unit])
end

-- Handles stats.
function Compression.Stats(packet: Packet | buffer): {[string]: any}
	if typeof(packet) == "buffer" then
		local bytes = buffer.len(packet)
		return {
			Bytes = bytes,
			Bits = bytes * 8,
			UsefulBits = bytes * 8,
			PhysicalBits = bytes * 8,
			SavedBits = nil,
			ExpandedBits = nil,
			BitSavingsPercent = nil,
			PaddingBits = 0,
			IsPhysicallySmaller = nil,
			IsBitSmaller = nil,
			Hash = nil,
			RawBytes = nil,
			SavedBytes = nil,
			ExpandedBytes = nil,
			ByteDelta = nil,
			SavingsPercent = nil,
			ExpansionPercent = nil,
			Ratio = nil,
			IsSmaller = nil,
		}
	end
	return {
		Bytes = packet.Bytes,
		Bits = packet.Bits,
		UsefulBits = packet.UsefulBits or packet.Bits,
		PhysicalBits = packet.PhysicalBits or packet.Bits,
		SavedBits = packet.SavedBits or 0,
		ExpandedBits = packet.ExpandedBits or 0,
		BitSavingsPercent = packet.BitSavingsPercent,
		PaddingBits = packet.PaddingBits
			or math.max(
				0,
				(packet.PhysicalBits or packet.Bits)
				- (packet.UsefulBits or packet.Bits)
			),
		Hash = packet.Hash,
		RawBytes = packet.RawBytes,
		SavedBytes = packet.SavedBytes or 0,
		ExpandedBytes = packet.ExpandedBytes or 0,
		ByteDelta = packet.ByteDelta,
		SavingsPercent = packet.SavingsPercent or 0,
		ExpansionPercent = packet.ExpansionPercent or 0,
		Ratio = packet.Ratio,
		IsSmaller = if packet.IsSmaller ~= nil
			then packet.IsSmaller
			elseif packet.RawBytes ~= nil
			then packet.Bytes < (packet.RawBytes :: number)
			else nil,

		IsPhysicallySmaller =
			if packet.IsPhysicallySmaller ~= nil
			then packet.IsPhysicallySmaller
			elseif packet.RawBytes ~= nil
			then packet.Bytes < (packet.RawBytes :: number)
			else nil,

		IsBitSmaller =
			if packet.IsBitSmaller ~= nil
			then packet.IsBitSmaller
			elseif packet.RawBytes ~= nil
			then (packet.UsefulBits or packet.Bits)
			< (packet.RawBytes :: number) * 8
			else nil,

		ValueType = packet.ValueType,
		Codec = packet.Codec,
		Passthrough = packet.Passthrough == true,
		Entropy = packet.Entropy,
		EntropyBytesBefore = packet.EntropyBytesBefore,
		EntropyBytesAfter = packet.EntropyBytesAfter,
		EntropySavedBytes = packet.EntropySavedBytes or 0,
	}
end

-- Handles analyze.
function Compression.Analyze(value: any, options: Options?): {[string]: any}
	local packet = Compression.Auto(value, options)
	local stats = Compression.Stats(packet)
	stats.EncodedBytesText = Compression.FormatBytes(stats.Bytes)
	stats.RawBytesText = stats.RawBytes and Compression.FormatBytes(stats.RawBytes) or nil
	stats.SavedBytesText = Compression.FormatBytes(stats.SavedBytes or 0)
	stats.ExpandedBytesText = Compression.FormatBytes(stats.ExpandedBytes or 0)
	return stats
end

-- Handles pack.
function Compression.Pack(value: any, options: Options?): Packet
	return Compression.Auto(
		value,
		options
	)
end

-- Handles unpack.
function Compression.Unpack(packet: Packet | buffer, options: Options?): any
	return Compression.AutoDecompress(
		packet,
		options
	)
end

-- Safely attempts to pack without throwing.
function Compression.TryPack(value: any, options: Options?): (boolean, Packet?, string?)
	return Compression.TryAuto(
		value,
		options
	)
end

-- Safely attempts to unpack without throwing.
function Compression.TryUnpack(packet: Packet | buffer, options: Options?): (boolean, any, string?)
	return Compression.TryAutoDecompress(
		packet,
		options
	)
end

-- Handles size.
function Compression.Size(value: any, options: Options?): (number, number)
	local packet = Compression.Auto(
		value,
		options
	)

	return packet.Bytes,
		packet.Bits
end

-- Handles codec.
function Compression.Codec(value: any, options: Options?): string
	local packet = Compression.Auto(
		value,
		options
	)

	return packet.Codec
		or "Unknown"
end

-- Handles version.
function Compression.Version(): string
	return "2.6.5"
end

return Compression
