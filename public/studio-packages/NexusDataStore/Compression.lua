--!native
--!optimize 2

export type Options = {
	StringDictionary: boolean?,
	DictionaryMinLength: number?,
	DictionaryMinUses: number?,
	DictionaryMaxEntries: number?,
	DictionaryMaxCandidates: number?,
	MaxDepth: number?,
	MaxNodes: number?,
	DeterministicMaps: boolean?,
	PreallocateLimit: number?,
	AllowExpansion: boolean?,
}

export type Report = {
	RawBytes: number,
	RawBits: number,
	EncodedBytes: number,
	EncodedBits: number,
	PayloadBytes: number,
	PayloadBits: number,
	HeaderBytes: number,
	SavedBytes: number,
	SavedBits: number,
	Ratio: number,
	SavingsPercent: number,
	DictionaryEntries: number,
	DictionaryBytes: number,
	Codec: string,
	Engine: string,
	EngineVersion: string,
	Fields: {any},
	StorageBytes: number?,
	Transport: string?,
	PersistedCompressed: boolean?,
	RawStorageEstimate: number?,
}

local Compression = {}

Compression.CodecVersion = 230
Compression.Magic = 0x4E433233
Compression.EngineCode = 230

local TAG_NIL = 0
local TAG_FALSE = 1
local TAG_TRUE = 2
local TAG_INTEGER = 3
local TAG_NUMBER = 4
local TAG_STRING = 5
local TAG_STRING_REF = 6
local TAG_ARRAY = 7
local TAG_MAP = 8

local HEADER_BYTES = 11
local ADLER_MOD = 65521
local MAX_SAFE_INTEGER = 9007199254740991

local function finiteNumber(value: any): boolean
	return typeof(value) == "number" and math.isfinite(value)
end

local function integerOption(value: any, fallback: number, minimum: number, name: string): number
	if value == nil then
		return fallback
	end
	if not finiteNumber(value) or value % 1 ~= 0 or value < minimum then
		error("INVALID_OPTION:" .. name)
	end
	return value
end

local function varUIntBytes(value: number): number
	local count = 1
	while value >= 128 do
		value = math.floor(value / 128)
		count += 1
	end
	return count
end

local function isInteger(value: number): boolean
	return finiteNumber(value)
		and value >= -MAX_SAFE_INTEGER
		and value <= MAX_SAFE_INTEGER
		and value % 1 == 0
end

local function normalizeOptions(options: Options?): Options
	local source = options or {}
	if typeof(source) ~= "table" then
		error("OPTIONS_TABLE_REQUIRED")
	end
	if source.StringDictionary ~= nil and typeof(source.StringDictionary) ~= "boolean" then
		error("INVALID_OPTION:StringDictionary")
	end
	if source.AllowExpansion ~= nil and typeof(source.AllowExpansion) ~= "boolean" then
		error("INVALID_OPTION:AllowExpansion")
	end
	if source.DeterministicMaps ~= nil and typeof(source.DeterministicMaps) ~= "boolean" then
		error("INVALID_OPTION:DeterministicMaps")
	end
	return {
		StringDictionary = source.StringDictionary ~= false,
		DictionaryMinLength = integerOption(source.DictionaryMinLength, 4, 1, "DictionaryMinLength"),
		DictionaryMinUses = integerOption(source.DictionaryMinUses, 2, 2, "DictionaryMinUses"),
		DictionaryMaxEntries = integerOption(source.DictionaryMaxEntries, 16384, 1, "DictionaryMaxEntries"),
		DictionaryMaxCandidates = integerOption(source.DictionaryMaxCandidates, 100000, 100, "DictionaryMaxCandidates"),
		MaxDepth = integerOption(source.MaxDepth, 128, 8, "MaxDepth"),
		MaxNodes = integerOption(source.MaxNodes, 2000000, 100, "MaxNodes"),
		DeterministicMaps = source.DeterministicMaps == true,
		PreallocateLimit = integerOption(source.PreallocateLimit, 4194304, 256, "PreallocateLimit"),
		AllowExpansion = source.AllowExpansion == true,
	}
end

local Writer = {}
Writer.__index = Writer

type WriterObject = {
	Buffer: buffer,
	Position: number,
	Capacity: number,
	Ensure: (self: WriterObject, count: number) -> (),
	U8: (self: WriterObject, value: number) -> (),
	U16: (self: WriterObject, value: number) -> (),
	U32: (self: WriterObject, value: number) -> (),
	F64: (self: WriterObject, value: number) -> (),
	Bytes: (self: WriterObject, value: string) -> (),
	VarUInt: (self: WriterObject, value: number) -> (),
	VarInt: (self: WriterObject, value: number) -> (),
	String: (self: WriterObject, value: string) -> (),
	Finish: (self: WriterObject) -> buffer,
}

function Writer.new(initialCapacity: number?): WriterObject
	local capacity = math.max(64, initialCapacity or 4096)
	return setmetatable({
		Buffer = buffer.create(capacity),
		Position = 0,
		Capacity = capacity,
	}, Writer) :: any
end

function Writer:Ensure(count: number)
	local required = self.Position + count
	if required <= self.Capacity then
		return
	end

	local capacity = self.Capacity
	while capacity < required do
		capacity *= 2
	end

	local nextBuffer = buffer.create(capacity)
	buffer.copy(nextBuffer, 0, self.Buffer, 0, self.Position)
	self.Buffer = nextBuffer
	self.Capacity = capacity
end

function Writer:U8(value: number)
	local position = self.Position
	if position + 1 > self.Capacity then
		self:Ensure(1)
	end
	buffer.writeu8(self.Buffer, position, value)
	self.Position = position + 1
end

function Writer:U16(value: number)
	local position = self.Position
	if position + 2 > self.Capacity then
		self:Ensure(2)
	end
	buffer.writeu16(self.Buffer, position, value)
	self.Position = position + 2
end

function Writer:U32(value: number)
	local position = self.Position
	if position + 4 > self.Capacity then
		self:Ensure(4)
	end
	buffer.writeu32(self.Buffer, position, value)
	self.Position = position + 4
end

function Writer:F64(value: number)
	local position = self.Position
	if position + 8 > self.Capacity then
		self:Ensure(8)
	end
	buffer.writef64(self.Buffer, position, value)
	self.Position = position + 8
end

function Writer:Bytes(value: string)
	local length = #value
	local position = self.Position
	if position + length > self.Capacity then
		self:Ensure(length)
	end
	buffer.writestring(self.Buffer, position, value, length)
	self.Position = position + length
end

function Writer:VarUInt(value: number)
	assert(value >= 0 and value <= MAX_SAFE_INTEGER and value % 1 == 0, "VarUInt requires a non-negative safe integer")
	local position = self.Position
	if position + 8 > self.Capacity then
		self:Ensure(8)
	end
	local target = self.Buffer
	repeat
		local byte = value % 128
		value = math.floor(value / 128)
		if value > 0 then
			byte += 128
		end
		buffer.writeu8(target, position, byte)
		position += 1
	until value == 0
	self.Position = position
end

function Writer:VarInt(value: number)
	assert(isInteger(value), "VarInt requires a safe integer")
	local encoded
	if value >= 0 then
		encoded = value * 2
	else
		encoded = (-value * 2) - 1
	end
	self:VarUInt(encoded)
end

function Writer:String(value: string)
	self:VarUInt(#value)
	self:Bytes(value)
end

function Writer:Finish(): buffer
	if self.Position == self.Capacity then
		return self.Buffer
	end
	local output = buffer.create(self.Position)
	buffer.copy(output, 0, self.Buffer, 0, self.Position)
	return output
end

local Reader = {}
Reader.__index = Reader

type ReaderObject = {
	Buffer: buffer,
	Position: number,
	Length: number,
	Need: (self: ReaderObject, count: number) -> (),
	U8: (self: ReaderObject) -> number,
	U16: (self: ReaderObject) -> number,
	U32: (self: ReaderObject) -> number,
	F64: (self: ReaderObject) -> number,
	VarUInt: (self: ReaderObject) -> number,
	VarInt: (self: ReaderObject) -> number,
	String: (self: ReaderObject) -> string,
	Remaining: (self: ReaderObject) -> number,
}

function Reader.new(source: buffer, offset: number?, length: number?): ReaderObject
	local start = offset or 0
	local count = length or (buffer.len(source) - start)
	return setmetatable({
		Buffer = source,
		Position = start,
		Length = start + count,
	}, Reader) :: any
end

function Reader:Need(count: number)
	if self.Position + count > self.Length then
		error("COMPRESSION_TRUNCATED")
	end
end

function Reader:U8(): number
	local position = self.Position
	if position >= self.Length then
		error("COMPRESSION_TRUNCATED")
	end
	local value = buffer.readu8(self.Buffer, position)
	self.Position = position + 1
	return value
end

function Reader:U16(): number
	local position = self.Position
	if position + 2 > self.Length then
		error("COMPRESSION_TRUNCATED")
	end
	local value = buffer.readu16(self.Buffer, position)
	self.Position = position + 2
	return value
end

function Reader:U32(): number
	local position = self.Position
	if position + 4 > self.Length then
		error("COMPRESSION_TRUNCATED")
	end
	local value = buffer.readu32(self.Buffer, position)
	self.Position = position + 4
	return value
end

function Reader:F64(): number
	local position = self.Position
	if position + 8 > self.Length then
		error("COMPRESSION_TRUNCATED")
	end
	local value = buffer.readf64(self.Buffer, position)
	self.Position = position + 8
	return value
end

function Reader:VarUInt(): number
	local source = self.Buffer
	local position = self.Position
	local limit = self.Length
	local value = 0
	local multiplier = 1
	local count = 0
	while true do
		if position >= limit then
			error("COMPRESSION_TRUNCATED")
		end
		count += 1
		if count > 8 then
			error("VARUINT_TOO_LARGE")
		end
		local byte = buffer.readu8(source, position)
		position += 1
		value += (byte % 128) * multiplier
		if byte < 128 then
			if count > 1 and byte == 0 then
				error("NON_CANONICAL_VARUINT")
			end
			break
		end
		multiplier *= 128
	end
	if value > MAX_SAFE_INTEGER then
		error("VARUINT_UNSAFE_INTEGER")
	end
	self.Position = position
	return value
end

function Reader:VarInt(): number
	local encoded = self:VarUInt()
	if encoded % 2 == 0 then
		return encoded / 2
	end
	return -((encoded + 1) / 2)
end

function Reader:String(): string
	local length = self:VarUInt()
	local position = self.Position
	if position + length > self.Length then
		error("COMPRESSION_TRUNCATED")
	end
	local value = buffer.readstring(self.Buffer, position, length)
	self.Position = position + length
	return value
end

function Reader:Remaining(): number
	return self.Length - self.Position
end

local function adler32(source: buffer, offset: number?, length: number?): number
	local start = offset or 0
	local count = length or (buffer.len(source) - start)
	local finish = start + count
	local a = 1
	local b = 0
	local index = start
	while index < finish do
		local blockEnd = math.min(index + 5552, finish)
		while index + 8 <= blockEnd do
			a += buffer.readu8(source, index)
			b += a
			a += buffer.readu8(source, index + 1)
			b += a
			a += buffer.readu8(source, index + 2)
			b += a
			a += buffer.readu8(source, index + 3)
			b += a
			a += buffer.readu8(source, index + 4)
			b += a
			a += buffer.readu8(source, index + 5)
			b += a
			a += buffer.readu8(source, index + 6)
			b += a
			a += buffer.readu8(source, index + 7)
			b += a
			index += 8
		end
		while index < blockEnd do
			a += buffer.readu8(source, index)
			b += a
			index += 1
		end
		a %= ADLER_MOD
		b %= ADLER_MOD
	end
	return b * 65536 + a
end

local function inspectTableShape(value: {[any]: any}): (boolean, number)
	local count = 0
	local maxIndex = 0
	local denseArrayCandidate = true
	for key in pairs(value) do
		count += 1
		if typeof(key) == "number" and key >= 1 and key % 1 == 0 then
			if key > maxIndex then
				maxIndex = key
			end
		else
			denseArrayCandidate = false
		end
	end
	if count == 0 then
		return true, 0
	end
	if denseArrayCandidate and maxIndex == count then
		return true, count
	end
	return false, count
end

local function collectStrings(
	value: any,
	counts: {[string]: number},
	seen: {[any]: boolean},
	state: {Nodes: number, Candidates: number},
	options: Options,
	depth: number
)
	if depth > (options.MaxDepth :: number) then
		error("MAX_DEPTH_EXCEEDED")
	end

	state.Nodes += 1
	if state.Nodes > (options.MaxNodes :: number) then
		error("MAX_NODES_EXCEEDED")
	end

	local kind = typeof(value)
	if kind == "string" then
		if #value >= (options.DictionaryMinLength :: number) then
			local uses = counts[value]
			if uses ~= nil then
				counts[value] = uses + 1
			elseif state.Candidates < (options.DictionaryMaxCandidates :: number) then
				counts[value] = 1
				state.Candidates += 1
			end
		end
		return
	end
	if kind ~= "table" then
		return
	end
	if seen[value] then
		error("CIRCULAR_REFERENCE")
	end
	seen[value] = true

	for key, child in pairs(value) do
		if typeof(key) == "string" and #key >= (options.DictionaryMinLength :: number) then
			local uses = counts[key]
			if uses ~= nil then
				counts[key] = uses + 1
			elseif state.Candidates < (options.DictionaryMaxCandidates :: number) then
				counts[key] = 1
				state.Candidates += 1
			end
		end
		collectStrings(child, counts, seen, state, options, depth + 1)
	end
	seen[value] = nil
end

local function buildDictionary(value: any, options: Options): ({string}, {[string]: number}, number, number)
	if options.StringDictionary == false then
		return {}, {}, 0, 0
	end

	local counts: {[string]: number} = {}
	local scanState = {Nodes = 0, Candidates = 0}
	collectStrings(value, counts, {}, scanState, options, 0)

	local entries = {}
	for text, uses in pairs(counts) do
		if uses >= (options.DictionaryMinUses :: number) then
			local rawCost = 1 + varUIntBytes(#text) + #text
			local dictionaryCost = varUIntBytes(#text) + #text
			local score = uses * (rawCost - 2) - dictionaryCost
			if score > 0 then
				table.insert(entries, {Text = text, Uses = uses, Score = score})
			end
		end
	end
	table.sort(entries, function(a, b)
		if a.Score ~= b.Score then
			return a.Score > b.Score
		end
		local aLength = #a.Text
		local bLength = #b.Text
		if aLength ~= bLength then
			return aLength > bLength
		end
		return a.Text < b.Text
	end)

	local maxEntries = options.DictionaryMaxEntries :: number
	local list: {string} = table.create(math.min(#entries, maxEntries))
	local lookup: {[string]: number} = {}
	local bytes = 0
	for _, entry in ipairs(entries) do
		if #list >= maxEntries then
			break
		end
		local index = #list + 1
		local rawCost = 1 + varUIntBytes(#entry.Text) + #entry.Text
		local referenceCost = 1 + varUIntBytes(index)
		local dictionaryCost = varUIntBytes(#entry.Text) + #entry.Text
		if entry.Uses * (rawCost - referenceCost) > dictionaryCost then
			list[index] = entry.Text
			lookup[entry.Text] = index
			bytes += varUIntBytes(#entry.Text) + #entry.Text
		end
	end
	return list, lookup, bytes, scanState.Nodes
end

local function writeValue(
	writer: WriterObject,
	value: any,
	dictionary: {[string]: number},
	seen: {[any]: boolean},
	state: {Nodes: number, RawBytes: number},
	options: Options,
	depth: number
)
	if depth > (options.MaxDepth :: number) then
		error("MAX_DEPTH_EXCEEDED")
	end
	state.Nodes += 1
	if state.Nodes > (options.MaxNodes :: number) then
		error("MAX_NODES_EXCEEDED")
	end

	local kind = typeof(value)
	if kind == "nil" then
		state.RawBytes += 1
		writer:U8(TAG_NIL)
		return
	elseif kind == "boolean" then
		state.RawBytes += 1
		writer:U8(value and TAG_TRUE or TAG_FALSE)
		return
	elseif kind == "number" then
		state.RawBytes += 8
		if not finiteNumber(value) then
			error("NON_FINITE_NUMBER")
		end
		if isInteger(value) and math.abs(value) <= math.floor(MAX_SAFE_INTEGER / 2) then
			writer:U8(TAG_INTEGER)
			writer:VarInt(value)
		else
			writer:U8(TAG_NUMBER)
			writer:F64(value)
		end
		return
	elseif kind == "string" then
		state.RawBytes += #value + 4
		local dictionaryIndex = dictionary[value]
		if dictionaryIndex then
			writer:U8(TAG_STRING_REF)
			writer:VarUInt(dictionaryIndex)
		else
			writer:U8(TAG_STRING)
			writer:String(value)
		end
		return
	elseif kind ~= "table" then
		error("UNSUPPORTED_TYPE:" .. kind)
	end

	state.RawBytes += 4
	if seen[value] then
		error("CIRCULAR_REFERENCE")
	end
	seen[value] = true

	local isArray, count = inspectTableShape(value)
	if isArray then
		writer:U8(TAG_ARRAY)
		writer:VarUInt(count)
		for index = 1, count do
			writeValue(writer, value[index], dictionary, seen, state, options, depth + 1)
		end
	else
		writer:U8(TAG_MAP)
		writer:VarUInt(count)
		if options.DeterministicMaps == true then
			local keys = table.create(count)
			local keyCount = 0
			for key in pairs(value) do
				local keyType = typeof(key)
				if keyType ~= "string" and keyType ~= "number" and keyType ~= "boolean" then
					error("NON_DETERMINISTIC_MAP_KEY:" .. keyType)
				end
				keyCount += 1
				keys[keyCount] = key
			end
			table.sort(keys, function(a, b)
				local ak = typeof(a)
				local bk = typeof(b)
				if ak ~= bk then
					return ak < bk
				end
				if ak == "number" or ak == "string" then
					return a < b
				end
				return a == false and b == true
			end)
			for index = 1, keyCount do
				local key = keys[index]
				writeValue(writer, key, dictionary, seen, state, options, depth + 1)
				writeValue(writer, value[key], dictionary, seen, state, options, depth + 1)
			end
		else
			for key, child in pairs(value) do
				writeValue(writer, key, dictionary, seen, state, options, depth + 1)
				writeValue(writer, child, dictionary, seen, state, options, depth + 1)
			end
		end
	end
	seen[value] = nil
end

local function readValue(
	reader: ReaderObject,
	dictionary: {string},
	state: {Nodes: number},
	options: Options,
	depth: number
): any
	if depth > (options.MaxDepth :: number) then
		error("MAX_DEPTH_EXCEEDED")
	end
	state.Nodes += 1
	if state.Nodes > (options.MaxNodes :: number) then
		error("MAX_NODES_EXCEEDED")
	end

	local tag = reader:U8()
	if tag == TAG_NIL then
		return nil
	elseif tag == TAG_FALSE then
		return false
	elseif tag == TAG_TRUE then
		return true
	elseif tag == TAG_INTEGER then
		return reader:VarInt()
	elseif tag == TAG_NUMBER then
		local value = reader:F64()
		if not finiteNumber(value) then
			error("NON_FINITE_NUMBER")
		end
		return value
	elseif tag == TAG_STRING then
		return reader:String()
	elseif tag == TAG_STRING_REF then
		local index = reader:VarUInt()
		local value = dictionary[index]
		if value == nil then
			error("INVALID_STRING_REFERENCE")
		end
		return value
	elseif tag == TAG_ARRAY then
		local count = reader:VarUInt()
		local remainingNodes = (options.MaxNodes :: number) - state.Nodes
		if count > remainingNodes then
			error("MAX_NODES_EXCEEDED")
		end
		if count > reader:Remaining() then
			error("INVALID_ARRAY_COUNT")
		end
		local output = table.create(count)
		for index = 1, count do
			local child = readValue(reader, dictionary, state, options, depth + 1)
			if child == nil then
				error("NIL_ARRAY_VALUE")
			end
			output[index] = child
		end
		return output
	elseif tag == TAG_MAP then
		local count = reader:VarUInt()
		local remainingNodes = (options.MaxNodes :: number) - state.Nodes
		if count > math.floor(remainingNodes / 2) then
			error("MAX_NODES_EXCEEDED")
		end
		if count > math.floor(reader:Remaining() / 2) then
			error("INVALID_MAP_COUNT")
		end
		local output = {}
		local seenKeys = {}
		for _ = 1, count do
			local key = readValue(reader, dictionary, state, options, depth + 1)
			if key == nil then
				error("NIL_MAP_KEY")
			end
			if seenKeys[key] then
				error("DUPLICATE_MAP_KEY")
			end
			seenKeys[key] = true
			local child = readValue(reader, dictionary, state, options, depth + 1)
			if child == nil then
				error("NIL_MAP_VALUE")
			end
			output[key] = child
		end
		return output
	end
	error("UNKNOWN_TAG:" .. tostring(tag))
end

-- Returns the codec version exposed to dependent modules.
function Compression.Version(): string
	return "2.3.3"
end

-- Returns the stable table codec mode identifier.
function Compression.TableMode(_value: any, _options: Options?): string
	return "buffer-v230"
end

-- Encodes using the v2.3 packet format with the v2.3.3 hardened engine.
function Compression.CompressTablePacket(value: any, options: Options?): (buffer, Report)
	local normalized = normalizeOptions(options)
	local dictionary, lookup, dictionaryBytes, scannedNodes = buildDictionary(value, normalized)

	local estimatedCapacity = math.max(256, HEADER_BYTES + dictionaryBytes + scannedNodes * 6)
	estimatedCapacity = math.min(estimatedCapacity, normalized.PreallocateLimit :: number)
	local packetWriter = Writer.new(estimatedCapacity)
	packetWriter.Position = HEADER_BYTES
	packetWriter:VarUInt(#dictionary)
	for _, text in ipairs(dictionary) do
		packetWriter:String(text)
	end

	local writeState = {Nodes = 0, RawBytes = 0}
	writeValue(packetWriter, value, lookup, {}, writeState, normalized, 0)
	local payloadBytes = packetWriter.Position - HEADER_BYTES
	local checksum = adler32(packetWriter.Buffer, HEADER_BYTES, payloadBytes)

	buffer.writeu32(packetWriter.Buffer, 0, Compression.Magic)
	buffer.writeu16(packetWriter.Buffer, 4, Compression.CodecVersion)
	buffer.writeu8(packetWriter.Buffer, 6, #dictionary > 0 and 1 or 0)
	buffer.writeu32(packetWriter.Buffer, 7, checksum)
	local output = packetWriter:Finish()

	local rawBytes = writeState.RawBytes
	local encodedBytes = buffer.len(output)
	local savedBytes = rawBytes - encodedBytes
	local ratio = 0
	local savings = 0
	if rawBytes ~= 0 then
		ratio = encodedBytes / rawBytes
		savings = (1 - ratio) * 100
	end

	local report: Report = {
		RawBytes = rawBytes,
		RawBits = rawBytes * 8,
		EncodedBytes = encodedBytes,
		EncodedBits = encodedBytes * 8,
		PayloadBytes = payloadBytes,
		PayloadBits = payloadBytes * 8,
		HeaderBytes = HEADER_BYTES,
		SavedBytes = savedBytes,
		SavedBits = savedBytes * 8,
		Ratio = ratio,
		SavingsPercent = savings,
		DictionaryEntries = #dictionary,
		DictionaryBytes = dictionaryBytes,
		Codec = "NexusBinary230",
		Engine = "Compression",
		EngineVersion = Compression.Version(),
		Fields = {},
	}
	return output, report
end

-- Decodes and validates a v2.3 packet with allocation and corruption guards.
function Compression.DecompressTable(source: buffer, options: Options?): any
	assert(typeof(source) == "buffer", "DecompressTable expects a buffer")
	if buffer.len(source) < HEADER_BYTES then
		error("COMPRESSION_TRUNCATED")
	end
	if buffer.readu32(source, 0) ~= Compression.Magic then
		error("COMPRESSION_MAGIC_MISMATCH")
	end
	local version = buffer.readu16(source, 4)
	if version ~= Compression.CodecVersion then
		error("UNSUPPORTED_COMPRESSION_VERSION:" .. tostring(version))
	end
	local flags = buffer.readu8(source, 6)
	if flags ~= 0 and flags ~= 1 then
		error("INVALID_COMPRESSION_FLAGS")
	end

	local expectedChecksum = buffer.readu32(source, 7)
	local payloadLength = buffer.len(source) - HEADER_BYTES
	local actualChecksum = adler32(source, HEADER_BYTES, payloadLength)
	if actualChecksum ~= expectedChecksum then
		error("COMPRESSION_CHECKSUM_MISMATCH")
	end

	local normalized = normalizeOptions(options)
	local reader = Reader.new(source, HEADER_BYTES, payloadLength)
	local dictionaryCount = reader:VarUInt()
	if dictionaryCount > (normalized.MaxNodes :: number) then
		error("MAX_NODES_EXCEEDED")
	end
	if dictionaryCount > reader:Remaining() then
		error("INVALID_DICTIONARY_COUNT")
	end
	if flags == 0 and dictionaryCount ~= 0 then
		error("UNEXPECTED_STRING_DICTIONARY")
	end
	local dictionary = table.create(dictionaryCount)
	local dictionaryLookup = {}
	for index = 1, dictionaryCount do
		local text = reader:String()
		if dictionaryLookup[text] then
			error("DUPLICATE_DICTIONARY_ENTRY")
		end
		dictionaryLookup[text] = true
		dictionary[index] = text
	end
	local value = readValue(reader, dictionary, {Nodes = 0}, normalized, 0)
	if reader:Remaining() ~= 0 then
		error("COMPRESSION_TRAILING_BYTES")
	end
	return value
end

-- Measures a value using the same encoder path without changing the packet format.
function Compression.Measure(value: any, options: Options?): Report
	local _, report = Compression.CompressTablePacket(value, options)
	return report
end

return table.freeze(Compression)
