--!native
--!optimize 2

local PlayersData = require(script.PlayersData)

export type Data = PlayersData.Data

export type PathKey = string | number
export type Path = PathKey | {PathKey}
export type SavePriority = "normal" | "high" | "critical"
export type CompressionTransport = "auto" | "buffer" | "base64"
export type OrderedWriteMode = "set" | "max" | "min"
export type SchemaType = "any" | "boolean" | "number" | "integer" | "string" | "table" | "array"

export type SchemaRule = {
	Type: SchemaType?,
	Required: boolean?,
	Optional: boolean?,
	Integer: boolean?,
	Min: number?,
	Max: number?,
	MinLength: number?,
	MaxLength: number?,
	Enum: {any}?,
	Children: {[string]: SchemaRule}?,
	ArrayOf: SchemaRule?,
	AllowUnknown: boolean?,
	Validate: ((value: any, path: string) -> (boolean | string))?,
}

export type MigrationContext = {
	StoreName: string,
	Key: string,
	FromVersion: number,
	ToVersion: number,
}

export type OpenContext = {
	Player: Player?,
	UserId: number?,
	Metadata: {[string]: any}?,
}

export type CompressionOptions = {
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

export type OrderedDataStoreConfig<T> = {
	Name: string?,
	Scope: string?,
	Path: Path?,
	Mode: OrderedWriteMode?,
	AutoSync: boolean?,
	ToNumber: ((value: any, session: any) -> number?)?,
	KeyFromSession: ((session: any) -> string | number)?,
	ClampMin: number?,
	ClampMax: number?,
	Integer: boolean?,
	Round: ("nearest" | "floor" | "ceil")?,
	RemoveWhenNil: boolean?,
}

export type StoreConfig<T> = {
	Name: string,
	Scope: string?,
	Template: T,
	Schema: {[string]: SchemaRule}?,
	SchemaVersion: number?,
	Migrations: {[number]: ((data: T, context: MigrationContext) -> T?)}?,
	Strict: boolean?,
	Reconcile: boolean?,
	EnforceTemplateTypes: boolean?,
	ValidateOnWrite: boolean?,
	DetectDirectChanges: boolean?,
	Compression: boolean?,
	CompressionModule: ModuleScript?,
	CompressionOptions: CompressionOptions?,
	CompressionReports: boolean?,
	CompressionTransport: CompressionTransport?,
	AutoSave: boolean?,
	AutoSaveInterval: number?,
	LockTimeout: number?,
	HeartbeatInterval: number?,
	RetryAttempts: number?,
	RetryBaseDelay: number?,
	RetryMaxDelay: number?,
	BudgetAware: boolean?,
	BudgetWaitTimeout: number?,
	MinimumSaveInterval: number?,
	LoadTimeout: number?,
	SaveTimeout: number?,
	MaxDataNodes: number?,
	MaxDataBytes: number?,
	MaxStoredBytes: number?,
	MaxDepth: number?,
	MaxSnapshots: number?,
	KeyPrefix: string?,
	PlayerKey: ((player: Player) -> string | number)?,
	AutoPlayerLifecycle: boolean?,
	EnableCrossServerEvents: boolean?,
	CrossServerTopic: string?,
	OrderedDataStores: {[string]: OrderedDataStoreConfig<T>}?,
	Debug: boolean?,
}

export type Change = {
	Path: {PathKey},
	Before: any,
	After: any,
}

export type Snapshot<T> = {
	Id: string,
	Label: string?,
	CreatedAt: number,
	Data: T,
	Revision: number,
}

export type Session<T> = {
	Store: any,
	Key: string,
	Player: Player?,
	UserId: number?,
	Context: OpenContext,
	Data: T,
	Revision: number,
	SchemaVersion: number,
	SessionId: string,
	Active: boolean,
	Dirty: boolean,
	MutationId: number,
	OpenedAt: number,
	LastSaveAt: number,
	IsActive: (self: Session<T>) -> boolean,
	IsDirty: (self: Session<T>) -> boolean,
	Get: (self: Session<T>, path: Path) -> any,
	GetOr: (self: Session<T>, path: Path, fallback: any) -> any,
	Has: (self: Session<T>, path: Path) -> boolean,
	Set: (self: Session<T>, path: Path, value: any) -> (boolean, string?),
	Delete: (self: Session<T>, path: Path) -> (boolean, string?),
	Increment: (self: Session<T>, path: Path, amount: number?) -> (boolean, any),
	IncrementClamped: (self: Session<T>, path: Path, amount: number?, minimum: number?, maximum: number?) -> (boolean, any),
	Toggle: (self: Session<T>, path: Path) -> (boolean, any),
	Append: (self: Session<T>, path: Path, value: any) -> (boolean, any),
	RemoveAt: (self: Session<T>, path: Path, index: number) -> (boolean, any),
	Award: (self: Session<T>, path: Path, amount: number) -> (boolean, any),
	Spend: (self: Session<T>, path: Path, amount: number) -> (boolean, any),
	UpdatePath: (self: Session<T>, path: Path, callback: (value: any, session: Session<T>) -> any) -> (boolean, any),
	Mutate: (self: Session<T>, callback: (draft: T, session: Session<T>) -> any) -> (boolean, any),
	Patch: (self: Session<T>, changes: {{Path: Path, Value: any}}) -> (boolean, string?),
	Watch: (self: Session<T>, path: Path?, callback: (newValue: any, oldValue: any, session: Session<T>, path: {PathKey}?) -> ()) -> any,
	Snapshot: (self: Session<T>, label: string?) -> Snapshot<T>,
	Restore: (self: Session<T>, snapshot: Snapshot<T>) -> (boolean, string?),
	DiffFromPersisted: (self: Session<T>) -> {Change},
	SaveAsync: (self: Session<T>, priority: SavePriority?) -> (boolean, string?),
	ReleaseAsync: (self: Session<T>) -> (boolean, string?),
	GetStatus: (self: Session<T>) -> {[string]: any},
	GetStats: (self: Session<T>) -> {[string]: any},
}

export type OrderedEntry = {
	Key: string,
	Value: number,
	Rank: number,
}

export type OrderedRank = {
	Rank: number,
	Key: string,
	Value: number,
}

export type OrderedStore<T> = {
	Alias: string,
	Name: string,
	Scope: string,
	Mode: OrderedWriteMode,
	AutoSync: boolean,
	Integer: boolean,
	GetAsync: (self: OrderedStore<T>, key: string | number) -> (boolean, number | string?),
	SetAsync: (self: OrderedStore<T>, key: string | number, value: any) -> (boolean, number | string?),
	UpdateAsync: (self: OrderedStore<T>, key: string | number, transform: (oldValue: number?) -> number?) -> (boolean, any, any?),
	MaxAsync: (self: OrderedStore<T>, key: string | number, value: any) -> (boolean, any),
	MinAsync: (self: OrderedStore<T>, key: string | number, value: any) -> (boolean, any),
	IncrementAsync: (self: OrderedStore<T>, key: string | number, delta: number?) -> (boolean, number | string?),
	RemoveAsync: (self: OrderedStore<T>, key: string | number) -> (boolean, any),
	WriteAsync: (self: OrderedStore<T>, key: string | number, value: any, mode: OrderedWriteMode?) -> (boolean, any),
	GetSortedAsync: (self: OrderedStore<T>, ascending: boolean?, pageSize: number?, minimum: number?, maximum: number?) -> (boolean, any),
	GetPageAsync: (self: OrderedStore<T>, ascending: boolean?, pageSize: number?, minimum: number?, maximum: number?) -> (boolean, {OrderedEntry} | string),
	GetTopAsync: (self: OrderedStore<T>, limit: number?, minimum: number?, maximum: number?) -> (boolean, {OrderedEntry} | string),
	GetBottomAsync: (self: OrderedStore<T>, limit: number?, minimum: number?, maximum: number?) -> (boolean, {OrderedEntry} | string),
	GetRankAsync: (self: OrderedStore<T>, key: string | number, ascending: boolean?, maxPages: number?) -> (boolean, OrderedRank | string),
	SyncSessionAsync: (self: OrderedStore<T>, session: Session<T>) -> (boolean, any),
}

export type Store<T> = {
	Config: StoreConfig<T>,
	OpenAsync: (self: Store<T>, key: string | number, context: OpenContext?) -> (Session<T>?, string?),
	OpenPlayerAsync: (self: Store<T>, player: Player) -> (Session<T>?, string?),
	PeekAsync: (self: Store<T>, key: string | number) -> (T?, {[string]: any} | string?),
	GetSession: (self: Store<T>, keyOrPlayer: string | number | Player) -> Session<T>?,
	WaitForSession: (self: Store<T>, keyOrPlayer: string | number | Player, timeout: number?) -> (Session<T>?, string?),
	SaveAsync: (self: Store<T>, session: Session<T>, priority: SavePriority?) -> (boolean, string?),
	ReleaseAsync: (self: Store<T>, session: Session<T>) -> (boolean, string?),
	FlushAsync: (self: Store<T>, timeout: number?) -> (boolean, string?),
	ReleaseAllAsync: (self: Store<T>) -> {[string]: {Success: boolean, Error: string?}},
	Validate: (self: Store<T>, data: T) -> (boolean, string?),
	GetTemplate: (self: Store<T>) -> T,
	GetSchema: (self: Store<T>) -> {[string]: SchemaRule}?,
	GetVersion: (self: Store<T>) -> string,
	EncodeCompressed: (self: Store<T>, data: any) -> (buffer?, any),
	DecodeCompressed: (self: Store<T>, raw: buffer) -> (any?, string?),
	GetCompressionReport: (self: Store<T>, dataOrSession: any) -> (any?, string?),
	GetOrderedStore: (self: Store<T>, alias: string) -> (OrderedStore<T>?, string?),
	SyncOrderedAsync: (self: Store<T>, session: Session<T>, alias: string?) -> (boolean, string?),
	SyncAllOrderedAsync: (self: Store<T>, alias: string?) -> (boolean, string?),
	GetMetrics: (self: Store<T>) -> {[string]: any},
	GetHealth: (self: Store<T>) -> {[string]: any},
	AttachPlayerLifecycle: (self: Store<T>) -> (),
	BindToClose: (self: Store<T>) -> (),
	CloseAsync: (self: Store<T>, timeout: number?) -> (boolean, string?),
	On: (self: Store<T>, eventName: string, callback: (...any) -> ()) -> any,
	Once: (self: Store<T>, eventName: string, callback: (...any) -> ()) -> any,
}


-- Concrete public aliases backed by PlayersData.Data.
-- Requiring NexusDataStore now gives callers one canonical player-data shape:
-- Store<Data> -> Session<Data> -> profile.Data.
export type Profile = Session<Data>
export type PlayerProfile = Session<Data>
export type PlayerStore = Store<Data>
export type PlayerStoreConfig = StoreConfig<Data>
export type PlayerSnapshot = Snapshot<Data>


export type NexusDataStoreModule = {
	new: (config: StoreConfig<Data>) -> Store<Data>,
	Version: string,
	RecordFormat: number,
	RequiredCompressionVersion: string,
	Errors: {[string]: string},
	OrderedDataStore: any,
	Compression: any,
}

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
local EncodingService = game:GetService("EncodingService")

local NexusDataStore: any = {}
NexusDataStore.__index = NexusDataStore
NexusDataStore.Version = "7.0.4"
NexusDataStore.RecordFormat = 700
NexusDataStore.RequiredCompressionVersion = "2.3.0"

local Session: any = {}
Session.__index = Session

local OrderedStore: any = {}
OrderedStore.__index = OrderedStore

local Signal: any = {}
Signal.__index = Signal

local RECORD_FORMAT = 700
local REQUIRED_COMPRESSION_VERSION = "2.3.0"
local MAX_SAFE_INTEGER = 9007199254740991

NexusDataStore.Errors = table.freeze({
	StoreClosed = "STORE_CLOSED",
	StoreClosing = "STORE_CLOSING",
	SessionNotFound = "SESSION_NOT_FOUND",
	SessionInactive = "SESSION_INACTIVE",
	SessionLocked = "SESSION_LOCKED",
	SessionLost = "SESSION_LOST",
	LoadTimeout = "LOAD_TIMEOUT",
	SaveTimeout = "SAVE_TIMEOUT",
	BudgetTimeout = "BUDGET_TIMEOUT",
	ValidationFailed = "VALIDATION_FAILED",
	UnsupportedRecord = "UNSUPPORTED_RECORD_FORMAT",
	CompressionUnavailable = "COMPRESSION_ENGINE_UNAVAILABLE",
})

local function now(): number
	return os.clock()
end

local function unix(): number
	return os.time()
end

local function finiteNumber(value: any): boolean
	return typeof(value) == "number" and math.isfinite(value)
end

local function safeInteger(value: any): boolean
	return finiteNumber(value)
		and value % 1 == 0
		and value >= -MAX_SAFE_INTEGER
		and value <= MAX_SAFE_INTEGER
end

local function configNumber(value: any, fallback: number, minimum: number, name: string, integer: boolean?, maximum: number?): number
	if value == nil then
		return fallback
	end
	assert(finiteNumber(value), name .. " must be a finite number")
	assert(value >= minimum, name .. " must be >= " .. tostring(minimum))
	if maximum ~= nil then
		assert(value <= maximum, name .. " must be <= " .. tostring(maximum))
	end
	if integer then
		assert(safeInteger(value), name .. " must be a safe integer")
	end
	return value
end

local function clone(value: any, seen: {[any]: any}?): any
	if typeof(value) ~= "table" then
		return value
	end
	seen = seen or {}
	if seen[value] then
		error("CIRCULAR_REFERENCE")
	end
	local output = {}
	seen[value] = output
	for key, child in pairs(value) do
		output[clone(key, seen)] = clone(child, seen)
	end
	seen[value] = nil
	return output
end

local function deepEqual(a: any, b: any, seen: {[any]: {[any]: boolean}}?): boolean
	if a == b then
		return true
	end
	if typeof(a) ~= typeof(b) then
		return false
	end
	if typeof(a) ~= "table" then
		return false
	end
	seen = seen or {}
	seen[a] = seen[a] or {}
	if seen[a][b] then
		return true
	end
	seen[a][b] = true
	for key, value in pairs(a) do
		if not deepEqual(value, b[key], seen) then
			return false
		end
	end
	for key in pairs(b) do
		if a[key] == nil then
			return false
		end
	end
	return true
end

local function normalizePath(path: Path): {PathKey}
	local function validateKey(key: any): PathKey
		if typeof(key) == "string" then
			assert(#key > 0, "Path string keys cannot be empty")
			return key
		end
		assert(safeInteger(key) and key >= 1, "Numeric path keys must be positive safe integers")
		return key
	end
	if typeof(path) == "string" or typeof(path) == "number" then
		return {validateKey(path)}
	end
	assert(typeof(path) == "table" and #path > 0, "Path must be a string, number, or non-empty array")
	local output = table.create(#path)
	for index, key in ipairs(path :: any) do
		output[index] = validateKey(key)
	end
	return output
end

local function pathKey(path: {PathKey}?): string
	if path == nil then
		return "*"
	end
	local pieces = table.create(#path)
	for index, key in ipairs(path) do
		if typeof(key) == "number" then
			pieces[index] = "n:" .. tostring(key)
		else
			pieces[index] = "s:" .. tostring(#key) .. ":" .. key
		end
	end
	return table.concat(pieces, "\31")
end

local function pathDisplay(path: {PathKey}): string
	local pieces = table.create(#path)
	for index, key in ipairs(path) do
		pieces[index] = tostring(key)
	end
	return table.concat(pieces, ".")
end

local function getAt(root: any, path: Path): any
	local keys = normalizePath(path)
	local cursor = root
	for _, key in ipairs(keys) do
		if typeof(cursor) ~= "table" then
			return nil
		end
		cursor = cursor[key]
		if cursor == nil then
			return nil
		end
	end
	return cursor
end

local function setAt(root: any, path: Path, value: any): (boolean, string?)
	local keys = normalizePath(path)
	local cursor = root
	for index = 1, #keys - 1 do
		local key = keys[index]
		if typeof(cursor) ~= "table" then
			return false, "PATH_PARENT_NOT_TABLE:" .. pathDisplay(keys)
		end
		local nextValue = cursor[key]
		if nextValue == nil then
			return false, "PATH_PARENT_MISSING:" .. pathDisplay(keys)
		end
		if typeof(nextValue) ~= "table" then
			return false, "PATH_PARENT_NOT_TABLE:" .. pathDisplay(keys)
		end
		cursor = nextValue
	end
	if typeof(cursor) ~= "table" then
		return false, "PATH_PARENT_NOT_TABLE:" .. pathDisplay(keys)
	end
	cursor[keys[#keys]] = value
	return true
end

local function deleteAt(root: any, path: Path): (boolean, string?)
	local keys = normalizePath(path)
	local cursor = root
	for index = 1, #keys - 1 do
		local nextValue = cursor[keys[index]]
		if typeof(nextValue) ~= "table" then
			return false, "PATH_PARENT_MISSING:" .. pathDisplay(keys)
		end
		cursor = nextValue
	end
	cursor[keys[#keys]] = nil
	return true
end

local function normalizeDataKey(key: string | number, prefix: string): string
	assert(typeof(key) == "string" or typeof(key) == "number", "DataStore key must be a string or number")
	if typeof(key) == "number" then
		assert(finiteNumber(key), "Numeric DataStore key must be finite")
	end
	local output = prefix .. tostring(key)
	assert(#output > 0 and #output <= 50, "DataStore key must be 1-50 bytes after KeyPrefix")
	return output
end

local function resolveRequestType(names: {string}): any
	for _, name in ipairs(names) do
		local ok, value = pcall(function()
			return (Enum.DataStoreRequestType :: any)[name]
		end)
		if ok and value ~= nil then
			return value
		end
	end
	return nil
end

local REQUEST_GET = resolveRequestType({"StandardRead", "GetAsync"})
local REQUEST_UPDATE = resolveRequestType({"StandardWrite", "UpdateAsync"})
local REQUEST_ORDERED_READ = resolveRequestType({"OrderedRead", "GetAsync"})
local REQUEST_ORDERED_WRITE = resolveRequestType({"OrderedWrite", "SetIncrementSortedAsync", "UpdateAsync"})
local REQUEST_ORDERED_LIST = resolveRequestType({"OrderedList", "GetSortedAsync"})
local REQUEST_ORDERED_REMOVE = resolveRequestType({"OrderedRemove"})
local REQUEST_STANDARD_UPDATE = {REQUEST_GET, REQUEST_UPDATE}
local REQUEST_ORDERED_UPDATE = {REQUEST_ORDERED_READ, REQUEST_ORDERED_WRITE}

function Signal.new()
	return setmetatable({
		NextId = 0,
		Listeners = {},
	}, Signal)
end

function Signal:Connect(callback)
	assert(typeof(callback) == "function", "Signal callback must be a function")
	self.NextId += 1
	local id = self.NextId
	self.Listeners[id] = callback
	local connection: any = {Connected = true}
	function connection:Disconnect()
		if not self.Connected then
			return
		end
		self.Connected = false
		if self._Signal then
			self._Signal.Listeners[self._Id] = nil
		end
	end
	connection._Signal = self
	connection._Id = id
	return connection
end

function Signal:Once(callback)
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		callback(...)
	end)
	return connection
end

function Signal:Fire(...)
	local callbacks = {}
	for _, callback in pairs(self.Listeners) do
		table.insert(callbacks, callback)
	end
	for _, callback in ipairs(callbacks) do
		task.spawn(callback, ...)
	end
end

local function inspectTable(value: any): (boolean, number, boolean)
	local count = 0
	local maxIndex = 0
	local hasNumeric = false
	local hasString = false
	for key in pairs(value) do
		count += 1
		if typeof(key) == "number" and key >= 1 and key % 1 == 0 then
			hasNumeric = true
			if key > maxIndex then
				maxIndex = key
			end
		elseif typeof(key) == "string" then
			hasString = true
		else
			return false, count, true
		end
	end
	if count == 0 then
		return true, 0, false
	end
	if hasNumeric and not hasString then
		return maxIndex == count, count, maxIndex ~= count
	end
	if hasString and not hasNumeric then
		return false, count, false
	end
	return false, count, true
end

local function schemaTypeMatches(value: any, expected: SchemaType): boolean
	if expected == "any" then
		return true
	elseif expected == "integer" then
		return safeInteger(value)
	elseif expected == "array" then
		if typeof(value) ~= "table" then
			return false
		end
		local isArray = inspectTable(value)
		return isArray
	elseif expected == "table" then
		return typeof(value) == "table"
	end
	return typeof(value) == expected
end

local function valueInEnum(value: any, values: {any}): boolean
	for _, allowed in ipairs(values) do
		if deepEqual(value, allowed) then
			return true
		end
	end
	return false
end

local function validateSchemaRuleDefinition(rule: any, path: string, seen: {[any]: boolean}?): (boolean, string?)
	if typeof(rule) ~= "table" then
		return false, "SCHEMA_RULE_MUST_BE_TABLE:" .. path
	end
	seen = seen or {}
	if seen[rule] then
		return false, "SCHEMA_RULE_CIRCULAR:" .. path
	end
	seen[rule] = true
	local validTypes = {any = true, boolean = true, number = true, integer = true, string = true, table = true, array = true}
	if rule.Type ~= nil and (typeof(rule.Type) ~= "string" or not validTypes[rule.Type]) then
		seen[rule] = nil
		return false, "SCHEMA_INVALID_TYPE:" .. path
	end
	for _, field in ipairs({"Required", "Optional", "Integer", "AllowUnknown"}) do
		if rule[field] ~= nil and typeof(rule[field]) ~= "boolean" then
			seen[rule] = nil
			return false, "SCHEMA_BOOLEAN_REQUIRED:" .. path .. "." .. field
		end
	end
	if rule.Required == true and rule.Optional == true then
		seen[rule] = nil
		return false, "SCHEMA_REQUIRED_OPTIONAL_CONFLICT:" .. path
	end
	for _, field in ipairs({"Min", "Max"}) do
		if rule[field] ~= nil and not finiteNumber(rule[field]) then
			seen[rule] = nil
			return false, "SCHEMA_FINITE_NUMBER_REQUIRED:" .. path .. "." .. field
		end
	end
	if rule.Min ~= nil and rule.Max ~= nil and rule.Max < rule.Min then
		seen[rule] = nil
		return false, "SCHEMA_INVALID_RANGE:" .. path
	end
	for _, field in ipairs({"MinLength", "MaxLength"}) do
		if rule[field] ~= nil and (not safeInteger(rule[field]) or rule[field] < 0) then
			seen[rule] = nil
			return false, "SCHEMA_NONNEGATIVE_INTEGER_REQUIRED:" .. path .. "." .. field
		end
	end
	if rule.MinLength ~= nil and rule.MaxLength ~= nil and rule.MaxLength < rule.MinLength then
		seen[rule] = nil
		return false, "SCHEMA_INVALID_LENGTH_RANGE:" .. path
	end
	if rule.Enum ~= nil and typeof(rule.Enum) ~= "table" then
		seen[rule] = nil
		return false, "SCHEMA_ENUM_MUST_BE_TABLE:" .. path
	end
	if rule.Validate ~= nil and typeof(rule.Validate) ~= "function" then
		seen[rule] = nil
		return false, "SCHEMA_VALIDATE_MUST_BE_FUNCTION:" .. path
	end
	if rule.ArrayOf ~= nil then
		local ok, err = validateSchemaRuleDefinition(rule.ArrayOf, path .. "[]", seen)
		if not ok then
			seen[rule] = nil
			return false, err
		end
	end
	if rule.Children ~= nil then
		if typeof(rule.Children) ~= "table" then
			seen[rule] = nil
			return false, "SCHEMA_CHILDREN_MUST_BE_TABLE:" .. path
		end
		for childName, childRule in pairs(rule.Children) do
			if typeof(childName) ~= "string" or #childName == 0 then
				seen[rule] = nil
				return false, "SCHEMA_CHILD_NAME_INVALID:" .. path
			end
			local ok, err = validateSchemaRuleDefinition(childRule, path .. "." .. childName, seen)
			if not ok then
				seen[rule] = nil
				return false, err
			end
		end
	end
	seen[rule] = nil
	return true
end

local function validateSchemaDefinition(schema: any): (boolean, string?)
	if schema == nil then
		return true
	end
	if typeof(schema) ~= "table" then
		return false, "SCHEMA_MUST_BE_TABLE"
	end
	for key, rule in pairs(schema) do
		if typeof(key) ~= "string" or #key == 0 then
			return false, "SCHEMA_ROOT_KEY_INVALID"
		end
		local ok, err = validateSchemaRuleDefinition(rule, "$.'" .. key .. "'")
		if not ok then
			return false, err
		end
	end
	return true
end

local function validateRule(value: any, rule: SchemaRule, displayPath: string): (boolean, string?)
	if value == nil then
		if rule.Required == true and rule.Optional ~= true then
			return false, "REQUIRED_VALUE_MISSING:" .. displayPath
		end
		return true
	end

	if rule.Type and not schemaTypeMatches(value, rule.Type) then
		return false, ("SCHEMA_TYPE_MISMATCH:%s expected %s got %s"):format(displayPath, rule.Type, typeof(value))
	end
	if rule.Integer == true and not safeInteger(value) then
		return false, "SCHEMA_INTEGER_REQUIRED:" .. displayPath
	end
	if typeof(value) == "number" then
		if rule.Min ~= nil and value < rule.Min then
			return false, "SCHEMA_MIN:" .. displayPath
		end
		if rule.Max ~= nil and value > rule.Max then
			return false, "SCHEMA_MAX:" .. displayPath
		end
	elseif typeof(value) == "string" then
		local length = utf8.len(value)
		if length == nil then
			return false, "INVALID_UTF8:" .. displayPath
		end
		if rule.MinLength ~= nil and length < rule.MinLength then
			return false, "SCHEMA_MIN_LENGTH:" .. displayPath
		end
		if rule.MaxLength ~= nil and length > rule.MaxLength then
			return false, "SCHEMA_MAX_LENGTH:" .. displayPath
		end
	end
	if rule.Enum and not valueInEnum(value, rule.Enum) then
		return false, "SCHEMA_ENUM:" .. displayPath
	end
	if rule.Validate then
		local ok, result = pcall(rule.Validate, value, displayPath)
		if not ok then
			return false, "SCHEMA_CUSTOM_ERROR:" .. tostring(result)
		end
		if result ~= true then
			return false, typeof(result) == "string" and result or ("SCHEMA_CUSTOM_FAILED:" .. displayPath)
		end
	end
	if typeof(value) == "table" then
		local isArray, count, mixed = inspectTable(value)
		if mixed then
			return false, "MIXED_OR_SPARSE_TABLE:" .. displayPath
		end
		if isArray and rule.ArrayOf then
			for index = 1, count do
				local ok, err = validateRule(value[index], rule.ArrayOf, displayPath .. "[" .. index .. "]")
				if not ok then
					return false, err
				end
			end
		elseif rule.Children then
			for childName, childRule in pairs(rule.Children) do
				local ok, err = validateRule(value[childName], childRule, displayPath .. "." .. childName)
				if not ok then
					return false, err
				end
			end
			if rule.AllowUnknown ~= true then
				for childName in pairs(value) do
					if typeof(childName) == "string" and rule.Children[childName] == nil then
						return false, "SCHEMA_UNKNOWN_KEY:" .. displayPath .. "." .. childName
					end
				end
			end
		end
	end
	return true
end

local function reconcileTemplate(data: any, template: any, enforceTypes: boolean, strict: boolean): (any, string?)
	if typeof(template) ~= "table" then
		if data == nil then
			return clone(template)
		end
		if enforceTypes and typeof(data) ~= typeof(template) then
			return nil, ("TEMPLATE_TYPE_MISMATCH expected %s got %s"):format(typeof(template), typeof(data))
		end
		return data
	end
	if data == nil then
		return clone(template)
	end
	if typeof(data) ~= "table" then
		return nil, "TEMPLATE_TABLE_REQUIRED"
	end

	local output = clone(data)
	local templateIsArray, templateCount = inspectTable(template)
	if templateIsArray and templateCount > 0 then
		if enforceTypes then
			local dataIsArray, dataCount, mixed = inspectTable(output)
			if not dataIsArray or mixed then
				return nil, "TEMPLATE_ARRAY_REQUIRED"
			end
			local exemplar = template[1]
			for index = 1, dataCount do
				if typeof(exemplar) == "table" then
					local reconciled, err = reconcileTemplate(output[index], exemplar, true, strict)
					if err then
						return nil, "TEMPLATE_ARRAY_ELEMENT_" .. index .. ":" .. err
					end
					output[index] = reconciled
				elseif typeof(output[index]) ~= typeof(exemplar) then
					return nil, "TEMPLATE_ARRAY_ELEMENT_TYPE_MISMATCH"
				end
			end
		end
		return output
	end

	for key, defaultValue in pairs(template) do
		if output[key] == nil then
			output[key] = clone(defaultValue)
		elseif enforceTypes then
			local reconciled, err = reconcileTemplate(output[key], defaultValue, true, strict)
			if err then
				return nil, tostring(key) .. ":" .. err
			end
			output[key] = reconciled
		end
	end
	if strict then
		for key in pairs(output) do
			if template[key] == nil then
				return nil, "UNKNOWN_TEMPLATE_KEY:" .. tostring(key)
			end
		end
	end
	return output
end

local function validateSerializable(value: any, state: any, path: string, maxDepth: number, maxNodes: number, depth: number): (boolean, string?)
	if depth > maxDepth then
		return false, "MAX_DEPTH_EXCEEDED:" .. path
	end
	state.Nodes += 1
	if state.Nodes > maxNodes then
		return false, "MAX_NODES_EXCEEDED"
	end
	local kind = typeof(value)
	if kind == "nil" or kind == "boolean" then
		return true
	elseif kind == "number" then
		if not finiteNumber(value) then
			return false, "NON_FINITE_NUMBER:" .. path
		end
		state.Bytes += 8
		return true
	elseif kind == "string" then
		if utf8.len(value) == nil then
			return false, "INVALID_UTF8:" .. path
		end
		state.Bytes += #value + 4
		return true
	elseif kind ~= "table" then
		return false, "UNSUPPORTED_TYPE:" .. path .. ":" .. kind
	end
	if state.Seen[value] then
		return false, "CIRCULAR_REFERENCE:" .. path
	end
	state.Seen[value] = true
	local isArray, count, mixed = inspectTable(value)
	if mixed then
		state.Seen[value] = nil
		return false, "MIXED_OR_SPARSE_TABLE:" .. path
	end
	state.Bytes += 4
	if isArray then
		for index = 1, count do
			local ok, err = validateSerializable(value[index], state, path .. "[" .. index .. "]", maxDepth, maxNodes, depth + 1)
			if not ok then
				state.Seen[value] = nil
				return false, err
			end
		end
	else
		for key, child in pairs(value) do
			if typeof(key) ~= "string" then
				state.Seen[value] = nil
				return false, "DICTIONARY_KEY_MUST_BE_STRING:" .. path
			end
			if utf8.len(key) == nil then
				state.Seen[value] = nil
				return false, "INVALID_UTF8_KEY:" .. path
			end
			state.Bytes += #key + 4
			local ok, err = validateSerializable(child, state, path .. "." .. key, maxDepth, maxNodes, depth + 1)
			if not ok then
				state.Seen[value] = nil
				return false, err
			end
		end
	end
	state.Seen[value] = nil
	return true
end

local function diffValues(before: any, after: any, path: {PathKey}, output: {Change}, seen: any)
	if deepEqual(before, after) then
		return
	end
	if typeof(before) ~= "table" or typeof(after) ~= "table" then
		table.insert(output, {Path = clone(path), Before = clone(before), After = clone(after)})
		return
	end
	seen[before] = seen[before] or {}
	if seen[before][after] then
		return
	end
	seen[before][after] = true
	local keys = {}
	for key in pairs(before) do
		keys[key] = true
	end
	for key in pairs(after) do
		keys[key] = true
	end
	local orderedKeys = {}
	for key in pairs(keys) do
		table.insert(orderedKeys, key)
	end
	table.sort(orderedKeys, function(a, b)
		local ak = typeof(a)
		local bk = typeof(b)
		if ak == bk then
			return tostring(a) < tostring(b)
		end
		return ak < bk
	end)
	for _, key in ipairs(orderedKeys) do
		table.insert(path, key)
		diffValues(before[key], after[key], path, output, seen)
		table.remove(path)
	end
end

local function compressionVersionCompatible(version: string): boolean
	local majorText, minorText = string.match(version, "^(%d+)%.(%d+)%.%d+$")
	if majorText == nil or minorText == nil then
		return false
	end
	return tonumber(majorText) == 2 and tonumber(minorText) == 3
end

local function compressionResolve(configured: ModuleScript?): (any?, string?)
	local candidate: Instance? = configured
	if candidate == nil then
		candidate = script:FindFirstChild("Compression")
	end
	if candidate == nil and script.Parent then
		candidate = script.Parent:FindFirstChild("Compression")
	end
	if candidate == nil then
		return nil, "Compression module not found beside NexusDataStore"
	end
	if not candidate:IsA("ModuleScript") then
		return nil, "CompressionModule must be a ModuleScript"
	end
	local ok, engine = pcall(require, candidate)
	if not ok then
		return nil, "Compression require failed:" .. tostring(engine)
	end
	if typeof(engine) ~= "table"
		or typeof(engine.Version) ~= "function"
		or typeof(engine.CompressTablePacket) ~= "function"
		or typeof(engine.DecompressTable) ~= "function" then
		return nil, "Compression module does not expose the v2.3.x codec API"
	end
	local versionOK, version = pcall(engine.Version)
	if not versionOK then
		return nil, "Compression Version() failed:" .. tostring(version)
	end
	version = tostring(version)
	if not compressionVersionCompatible(version) then
		return nil, ("Compression v2.3.x required, got v%s"):format(version)
	end
	if tonumber(engine.CodecVersion) ~= 230 then
		return nil, "Compression codec 230 required"
	end
	return engine
end

function NexusDataStore:_Debug(...)
	if self.Config.Debug then
		print("[NexusDataStore v7.0.2]", ...)
	end
end

function NexusDataStore:_GetSignal(name: string)
	local signal = self.Events[name]
	if not signal then
		signal = Signal.new()
		self.Events[name] = signal
	end
	return signal
end

function NexusDataStore:On(name: string, callback)
	assert(typeof(name) == "string" and #name > 0, "Event name must be a non-empty string")
	return self:_GetSignal(name):Connect(callback)
end

function NexusDataStore:Once(name: string, callback)
	assert(typeof(name) == "string" and #name > 0, "Event name must be a non-empty string")
	return self:_GetSignal(name):Once(callback)
end

function NexusDataStore:_Fire(name: string, ...)
	if typeof(name) ~= "string" or #name == 0 then
		return
	end
	local signal = self.Events[name]
	if signal then
		signal:Fire(...)
	end
end

function NexusDataStore:_WaitForBudget(requestType: any, absoluteDeadline: number?): boolean
	if not self.Config.BudgetAware or requestType == nil then
		return true
	end
	local deadline = now() + self.Config.BudgetWaitTimeout
	if absoluteDeadline ~= nil then
		deadline = math.min(deadline, absoluteDeadline)
	end
	repeat
		local ok, budget = pcall(DataStoreService.GetRequestBudgetForRequestType, DataStoreService, requestType)
		if ok and budget > 0 then
			return true
		end
		if now() >= deadline or self.Closed then
			break
		end
		task.wait(math.min(0.1, math.max(0, deadline - now())))
	until false
	return false
end

function NexusDataStore:_WaitForBudgets(requestTypes: any, absoluteDeadline: number?): boolean
	if requestTypes == nil then
		return true
	end
	if typeof(requestTypes) ~= "table" then
		return self:_WaitForBudget(requestTypes, absoluteDeadline)
	end
	local checked = {}
	for _, requestType in pairs(requestTypes) do
		if requestType ~= nil and not checked[requestType] then
			checked[requestType] = true
			if not self:_WaitForBudget(requestType, absoluteDeadline) then
				return false
			end
		end
	end
	return true
end

function NexusDataStore:_Retry(callback, requestTypes: any?, absoluteDeadline: number?, timeoutCode: string?): (boolean, any)
	local attempts = self.Config.RetryAttempts
	local delay = self.Config.RetryBaseDelay
	local lastError
	for attempt = 1, attempts do
		if self.Closed then
			return false, "STORE_CLOSED"
		end
		if absoluteDeadline ~= nil and now() >= absoluteDeadline then
			return false, timeoutCode or "OPERATION_TIMEOUT"
		end
		if requestTypes and not self:_WaitForBudgets(requestTypes, absoluteDeadline) then
			if absoluteDeadline ~= nil and now() >= absoluteDeadline then
				return false, timeoutCode or "OPERATION_TIMEOUT"
			end
			return false, "BUDGET_TIMEOUT"
		end
		local ok, result = pcall(callback)
		if ok then
			return true, result
		end
		lastError = result
		if attempt < attempts then
			self.Metrics.Retries += 1
			local jitter = 0.85 + math.random() * 0.3
			local waitTime = math.min(delay, self.Config.RetryMaxDelay) * jitter
			if absoluteDeadline ~= nil then
				local remaining = absoluteDeadline - now()
				if remaining <= 0 then
					return false, timeoutCode or "OPERATION_TIMEOUT"
				end
				waitTime = math.min(waitTime, remaining)
			end
			task.wait(waitTime)
			delay = math.min(delay * 2, self.Config.RetryMaxDelay)
		end
	end
	return false, tostring(lastError)
end

function NexusDataStore:_Attempt(callback, requestTypes: any?): (boolean, any)
	if self.Closed then
		return false, "STORE_CLOSED"
	end
	if requestTypes and not self:_WaitForBudgets(requestTypes) then
		return false, "BUDGET_TIMEOUT"
	end
	local ok, result = pcall(callback)
	if ok then
		return true, result
	end
	return false, tostring(result)
end

function NexusDataStore:_MeasureStoredValue(value: any): (number?, string?)
	local ok, encoded = pcall(HttpService.JSONEncode, HttpService, value)
	if not ok then
		return nil, "JSON_SIZE_MEASURE_FAILED:" .. tostring(encoded)
	end
	return #encoded
end

function NexusDataStore:_RecordEncoding(report: any?)
	if not report then
		return
	end
	if finiteNumber(report.StorageBytes) and report.StorageBytes >= 0 then
		self.Metrics.BytesEncoded += report.StorageBytes
	end
	if self.Config.CompressionReports and report.EngineVersion ~= nil then
		self:_Fire("CompressionReport", report)
	end
end

-- Encodes one v7 record without side effects so it is safe inside a retried UpdateAsync transform.
function NexusDataStore:_EncodeRecord(record: any): (any?, string?, any?)
	local rawBytes, rawMeasureErr = self:_MeasureStoredValue(record)
	if rawBytes == nil then
		return nil, rawMeasureErr
	end
	if not self.Config.Compression then
		if rawBytes > self.Config.MaxStoredBytes then
			return nil, ("STORED_BYTES_EXCEEDED:%d>%d"):format(rawBytes, self.Config.MaxStoredBytes)
		end
		return record, nil, {
			StorageBytes = rawBytes,
			Transport = "raw-table",
			PersistedCompressed = false,
		}
	end
	if not self.CompressionEngine then
		return nil, "COMPRESSION_ENGINE_UNAVAILABLE:" .. tostring(self.CompressionEngineError)
	end

	local ok, encoded, report = pcall(self.CompressionEngine.CompressTablePacket, record, self.Config.CompressionOptions)
	if not ok then
		return nil, "COMPRESSED_ENCODE_FAILED:" .. tostring(encoded)
	end
	if typeof(encoded) ~= "buffer" then
		return nil, "COMPRESSED_ENCODE_INVALID_BUFFER"
	end
	if typeof(report) ~= "table" then
		report = {
			EngineVersion = self.CompressionEngineVersion,
			EncodedBytes = buffer.len(encoded),
		}
	end

	local codec = tonumber(self.CompressionEngine.CodecVersion) or 230
	local transport = self.Config.CompressionTransport
	local bestEnvelope = nil
	local bestBytes = math.huge
	local bestTransport = nil

	-- A direct buffer lets Roblox's serializer choose its current buffer representation
	-- (including its own compression when profitable). JSONEncode is the documented way
	-- to measure the exact DataStore serialization size, so compare that actual size.
	if transport == "auto" or transport == "buffer" then
		local bufferEnvelope = {
			Format = RECORD_FORMAT,
			Codec = codec,
			Compressed = true,
			Encoding = "buffer",
			Payload = encoded,
		}
		local bufferBytes, bufferMeasureErr = self:_MeasureStoredValue(bufferEnvelope)
		if bufferBytes ~= nil then
			bestEnvelope = bufferEnvelope
			bestBytes = bufferBytes
			bestTransport = "buffer"
		elseif transport == "buffer" then
			return nil, "BUFFER_TRANSPORT_SIZE_MEASURE_FAILED:" .. tostring(bufferMeasureErr)
		end
	end

	-- Keep Base64 as a compatibility/fallback transport and compare it in auto mode.
	-- Its characters do not require JSON escaping, so cached envelope overhead + payload
	-- length is exact and avoids another whole JSONEncode for this candidate.
	if transport == "auto" or transport == "base64" then
		local base64OK, base64Buffer = pcall(EncodingService.Base64Encode, EncodingService, encoded)
		if not base64OK then
			if transport == "base64" or bestEnvelope == nil then
				return nil, "BASE64_ENCODE_FAILED:" .. tostring(base64Buffer)
			end
		else
			local payload = buffer.tostring(base64Buffer)
			local base64Envelope = {
				Format = RECORD_FORMAT,
				Codec = codec,
				Compressed = true,
				Encoding = "base64",
				Payload = payload,
			}
			local base64Bytes = self.CompressedEnvelopeBaseBytes + #payload
			if base64Bytes < bestBytes then
				bestEnvelope = base64Envelope
				bestBytes = base64Bytes
				bestTransport = "base64"
			end
		end
	end

	if bestEnvelope == nil then
		return nil, "NO_COMPRESSION_TRANSPORT_AVAILABLE"
	end

	report.RawStorageEstimate = rawBytes
	local allowExpansion = self.Config.CompressionOptions.AllowExpansion == true
	if not allowExpansion and rawBytes <= self.Config.MaxStoredBytes and bestBytes >= rawBytes then
		report.StorageBytes = rawBytes
		report.Transport = "raw-table"
		report.PersistedCompressed = false
		return record, nil, report
	end
	if bestBytes > self.Config.MaxStoredBytes then
		if rawBytes <= self.Config.MaxStoredBytes then
			report.StorageBytes = rawBytes
			report.Transport = "raw-table"
			report.PersistedCompressed = false
			return record, nil, report
		end
		return nil, ("STORED_BYTES_EXCEEDED:%d>%d"):format(bestBytes, self.Config.MaxStoredBytes)
	end

	report.StorageBytes = bestBytes
	report.Transport = bestTransport
	report.PersistedCompressed = true
	return bestEnvelope, nil, report
end

-- Decodes one v7 record and rejects malformed envelopes before they reach session acquisition.
function NexusDataStore:_DecodeRecord(raw: any): (any?, string?)
	if raw == nil then
		return nil
	end
	local record = raw
	if typeof(raw) ~= "table" then
		return nil, "UNSUPPORTED_RECORD_TYPE:" .. typeof(raw)
	end
	if raw.Compressed == true then
		if raw.Format ~= RECORD_FORMAT then
			return nil, "INVALID_COMPRESSED_ENVELOPE"
		end
		if not self.CompressionEngine then
			return nil, "COMPRESSION_ENGINE_UNAVAILABLE:" .. tostring(self.CompressionEngineError)
		end
		local codec = tonumber(self.CompressionEngine.CodecVersion)
		if raw.Codec ~= nil and tonumber(raw.Codec) ~= codec then
			return nil, "UNSUPPORTED_COMPRESSION_CODEC:" .. tostring(raw.Codec)
		end

		local decodedBuffer
		if raw.Encoding == "buffer" and typeof(raw.Payload) == "buffer" then
			decodedBuffer = raw.Payload
		elseif raw.Encoding == "base64" and typeof(raw.Payload) == "string" then
			local decodeOK, base64Decoded = pcall(EncodingService.Base64Decode, EncodingService, buffer.fromstring(raw.Payload))
			if not decodeOK then
				return nil, "BASE64_DECODE_FAILED:" .. tostring(base64Decoded)
			end
			decodedBuffer = base64Decoded
		else
			return nil, "INVALID_COMPRESSED_ENVELOPE"
		end

		local ok, decoded = pcall(self.CompressionEngine.DecompressTable, decodedBuffer, self.Config.CompressionOptions)
		if not ok then
			return nil, "COMPRESSED_DECODE_FAILED:" .. tostring(decoded)
		end
		record = decoded
	end
	if typeof(record) ~= "table" or record.Format ~= RECORD_FORMAT then
		return nil, "UNSUPPORTED_RECORD_FORMAT"
	end
	if typeof(record.Data) ~= "table" then
		return nil, "INVALID_RECORD_DATA"
	end
	if not safeInteger(record.SchemaVersion) or record.SchemaVersion < 1 then
		return nil, "INVALID_RECORD_SCHEMA_VERSION"
	end
	if not safeInteger(record.Revision) or record.Revision < 0 then
		return nil, "INVALID_RECORD_REVISION"
	end
	if not finiteNumber(record.CreatedAt) or record.CreatedAt < 0 then
		return nil, "INVALID_RECORD_CREATED_AT"
	end
	if not finiteNumber(record.UpdatedAt) or record.UpdatedAt < 0 then
		return nil, "INVALID_RECORD_UPDATED_AT"
	end
	if record.LastCommitId ~= nil and (typeof(record.LastCommitId) ~= "string" or #record.LastCommitId == 0 or #record.LastCommitId > 128) then
		return nil, "INVALID_RECORD_COMMIT_ID"
	end
	if record.Lock ~= nil then
		local lock = record.Lock
		if typeof(lock) ~= "table"
			or typeof(lock.JobId) ~= "string"
			or #lock.JobId == 0
			or typeof(lock.SessionId) ~= "string"
			or #lock.SessionId == 0
			or not finiteNumber(lock.HeartbeatAt)
			or lock.HeartbeatAt < 0
			or not finiteNumber(lock.ExpiresAt)
			or lock.ExpiresAt < lock.HeartbeatAt then
			return nil, "INVALID_RECORD_LOCK"
		end
	end
	return record
end

function NexusDataStore:Validate(data: Data): (boolean, string?)
	if typeof(data) ~= "table" then
		return false, "ROOT_DATA_MUST_BE_TABLE"
	end
	local state = {Nodes = 0, Bytes = 0, Seen = {}}
	local ok, err = validateSerializable(data, state, "$", self.Config.MaxDepth, self.Config.MaxDataNodes, 0)
	if not ok then
		self.Metrics.TypeErrors += 1
		return false, err
	end
	if state.Bytes > self.Config.MaxDataBytes then
		return false, ("MAX_DATA_BYTES_EXCEEDED:%d>%d"):format(state.Bytes, self.Config.MaxDataBytes)
	end
	if self.Schema then
		for key, rule in pairs(self.Schema) do
			local ruleOK, ruleErr = validateRule(data[key], rule, "$.'" .. key .. "'")
			if not ruleOK then
				self.Metrics.TypeErrors += 1
				return false, ruleErr
			end
		end
		if self.Config.Strict then
			for key in pairs(data) do
				if typeof(key) == "string" and self.Schema[key] == nil and self.Template[key] == nil then
					return false, "SCHEMA_UNKNOWN_ROOT_KEY:" .. key
				end
			end
		end
	end
	if self.Config.EnforceTemplateTypes then
		local _, templateErr = reconcileTemplate(data, self.Template, true, self.Config.Strict)
		if templateErr then
			self.Metrics.TypeErrors += 1
			return false, templateErr
		end
	end
	return true
end

function NexusDataStore:_Reconcile(data: Data): (Data?, string?)
	if not self.Config.Reconcile then
		return data
	end
	return reconcileTemplate(data, self.Template, self.Config.EnforceTemplateTypes, self.Config.Strict)
end

function NexusDataStore:_ApplyMigrations(data: Data, fromVersion: number, key: string): (Data?, string?)
	if fromVersion > self.SchemaVersion then
		return nil, ("SCHEMA_NEWER_THAN_SERVER:%d>%d"):format(fromVersion, self.SchemaVersion)
	end
	local working = clone(data)
	local version = fromVersion
	while version < self.SchemaVersion do
		local targetVersion = version + 1
		local migration = self.Config.Migrations[targetVersion]
		if not migration then
			return nil, "MIGRATION_MISSING:" .. targetVersion
		end
		local context: MigrationContext = {
			StoreName = self.Config.Name,
			Key = key,
			FromVersion = version,
			ToVersion = targetVersion,
		}
		local ok, migrated = pcall(migration, working, context)
		if not ok then
			return nil, "MIGRATION_FAILED:" .. targetVersion .. ":" .. tostring(migrated)
		end
		if migrated ~= nil then
			if typeof(migrated) ~= "table" then
				return nil, "MIGRATION_MUST_RETURN_TABLE_OR_NIL:" .. targetVersion
			end
			working = migrated
		end
		version = targetVersion
	end
	return working
end

function NexusDataStore:_BuildNewRecord(data: Data): any
	local stamp = unix()
	return {
		Format = RECORD_FORMAT,
		SchemaVersion = self.SchemaVersion,
		Revision = 0,
		CreatedAt = stamp,
		UpdatedAt = stamp,
		Data = data,
		Lock = nil,
	}
end

function NexusDataStore:_LockRecord(record: any, sessionId: string)
	local stamp = unix()
	record.Lock = {
		JobId = self.JobId,
		SessionId = sessionId,
		HeartbeatAt = stamp,
		ExpiresAt = stamp + self.Config.LockTimeout,
	}
end

function NexusDataStore:_OwnsRecord(record: any, session: any): boolean
	local lock = record and record.Lock
	return typeof(lock) == "table"
		and lock.JobId == self.JobId
		and lock.SessionId == session.SessionId
end

function NexusDataStore:_LockIsActive(lock: any): boolean
	return typeof(lock) == "table"
		and typeof(lock.ExpiresAt) == "number"
		and lock.ExpiresAt > unix()
end

function NexusDataStore:_Publish(eventName: string, payload: any)
	if not self.Config.EnableCrossServerEvents then
		return
	end
	task.spawn(function()
		local packet = {
			Version = NexusDataStore.Version,
			Event = eventName,
			Store = self.Config.Name,
			JobId = self.JobId,
			Payload = payload,
			At = unix(),
		}
		local ok, err = pcall(MessagingService.PublishAsync, MessagingService, self.Config.CrossServerTopic, packet)
		if not ok then
			self.Metrics.CrossServerPublishFailed += 1
			self:_Fire("CrossServerError", tostring(err))
		end
	end)
end

function NexusDataStore:_WithLocalMutex(map: any, key: string, timeout: number, callback)
	local deadline = now() + timeout
	while map[key] do
		if self.Closed then
			return nil, "STORE_CLOSED"
		end
		if now() >= deadline then
			return nil, "LOCAL_KEY_LOCK_TIMEOUT"
		end
		task.wait(0.02)
	end
	map[key] = true
	local ok, a, b, c = pcall(callback)
	map[key] = nil
	if not ok then
		return nil, "LOCAL_KEY_LOCK_CALLBACK_FAILED:" .. tostring(a)
	end
	return a, b, c
end

function NexusDataStore:_CreateSession(key: string, record: any, sessionId: string, context: OpenContext): Session<Data>
	local session: Session<Data> = setmetatable({
		Store = self,
		Key = key,
		Player = context.Player,
		UserId = context.UserId or (context.Player and context.Player.UserId or nil),
		Context = context,
		Data = clone(record.Data) :: Data,
		Revision = record.Revision or 0,
		SchemaVersion = record.SchemaVersion or self.SchemaVersion,
		SessionId = sessionId,
		Active = true,
		Dirty = false,
		MutationId = 0,
		OpenedAt = now(),
		LastSaveAt = now(),
		LastHeartbeatAt = now(),
		NextAutoSaveAt = now() + self.Config.AutoSaveInterval,
		LastPersistedSnapshot = clone(record.Data) :: Data,
		ObservedSnapshot = self.Config.DetectDirectChanges and clone(record.Data) or nil,
		Snapshots = {},
		Watchers = {},
		CommitBusy = false,
		Releasing = false,
		DirectChangeInvalid = false,
		SavePending = false,
		HeartbeatPending = false,
	}, Session) :: any
	self.Sessions[key] = session
	self.SessionById[sessionId] = session
	if session.Player then
		self.SessionByPlayer[session.Player] = session
	end
	return session
end

-- Opens and exclusively locks a v7 record, then migrates, reconciles, and validates it before creating a session.
function NexusDataStore:OpenAsync(key: string | number, context: OpenContext?): (Session<Data>?, string?)
	if self.Closed then
		return nil, "STORE_CLOSED"
	end
	if self.Closing then
		return nil, "STORE_CLOSING"
	end
	local keyOK, normalizedKey = pcall(normalizeDataKey, key, self.Config.KeyPrefix)
	if not keyOK then
		return nil, "INVALID_DATA_KEY:" .. tostring(normalizedKey)
	end
	if context ~= nil and typeof(context) ~= "table" then
		return nil, "INVALID_OPEN_CONTEXT"
	end
	local openContext: OpenContext = context or {}
	if openContext.Player ~= nil and (typeof(openContext.Player) ~= "Instance" or not openContext.Player:IsA("Player")) then
		return nil, "INVALID_CONTEXT_PLAYER"
	end
	if openContext.UserId ~= nil and (not safeInteger(openContext.UserId) or openContext.UserId < 0) then
		return nil, "INVALID_CONTEXT_USER_ID"
	end
	if openContext.Metadata ~= nil and typeof(openContext.Metadata) ~= "table" then
		return nil, "INVALID_CONTEXT_METADATA"
	end
	local openStartedAt = now()
	local openDeadline = openStartedAt + self.Config.LoadTimeout
	return self:_WithLocalMutex(self.OpenLocks, normalizedKey, self.Config.LoadTimeout, function()
		local existing = self.Sessions[normalizedKey]
		if existing and existing:IsActive() then
			return existing
		end
		local sessionId = HttpService:GenerateGUID(false)
		local acquireError
		local recordForSession
		local encodeReport
		local startTime = openStartedAt

		local success, result = self:_Retry(function()
			return self.DataStore:UpdateAsync(normalizedKey, function(raw)
				acquireError = nil
				recordForSession = nil
				encodeReport = nil
				local record, decodeErr = self:_DecodeRecord(raw)
				if raw ~= nil and not record then
					acquireError = decodeErr or "DECODE_FAILED"
					return nil
				end
				if record == nil then
					record = self:_BuildNewRecord(clone(self.Template))
				end
				if record.Lock and self:_LockIsActive(record.Lock) then
					local sameOwner = record.Lock.JobId == self.JobId and record.Lock.SessionId == sessionId
					if not sameOwner then
						acquireError = "SESSION_LOCKED"
						return nil
					end
				end

				local schemaVersion = tonumber(record.SchemaVersion) or 1
				local migrated, migrationErr = self:_ApplyMigrations(record.Data :: Data, schemaVersion, normalizedKey)
				if not migrated then
					acquireError = migrationErr
					return nil
				end
				local reconciled, reconcileErr = self:_Reconcile(migrated)
				if not reconciled then
					acquireError = "RECONCILE_FAILED:" .. tostring(reconcileErr)
					return nil
				end
				local valid, validationErr = self:Validate(reconciled)
				if not valid then
					acquireError = "LOAD_VALIDATION_FAILED:" .. tostring(validationErr)
					return nil
				end
				local changedOnLoad = schemaVersion ~= self.SchemaVersion or not deepEqual(record.Data, reconciled)
				record.Data = reconciled :: Data
				record.SchemaVersion = self.SchemaVersion
				if changedOnLoad then
					record.Revision = (tonumber(record.Revision) or 0) + 1
				end
				record.UpdatedAt = unix()
				self:_LockRecord(record, sessionId)
				recordForSession = clone(record)
				local encoded, encodeErr, currentReport = self:_EncodeRecord(record)
				if encoded == nil then
					acquireError = encodeErr
					return nil
				end
				encodeReport = currentReport
				return encoded
			end)
		end, REQUEST_STANDARD_UPDATE, openDeadline, "LOAD_TIMEOUT")

		if not success then
			self.Metrics.LoadsFailed += 1
			return nil, tostring(result)
		end
		if acquireError then
			self.Metrics.LoadsFailed += 1
			return nil, acquireError
		end
		self:_RecordEncoding(encodeReport)
		local finalRecord = recordForSession
		if finalRecord == nil then
			local decoded, decodeErr = self:_DecodeRecord(result)
			if not decoded then
				self.Metrics.LoadsFailed += 1
				return nil, decodeErr
			end
			finalRecord = decoded
		end
		if not self:_OwnsRecord(finalRecord, {SessionId = sessionId}) then
			self.Metrics.LoadsFailed += 1
			return nil, "SESSION_ACQUIRE_OWNERSHIP_FAILED"
		end
		local session = self:_CreateSession(normalizedKey, finalRecord, sessionId, openContext)
		self.Metrics.Opened += 1
		self.Metrics.LoadTime += now() - startTime
		self:_Fire("Opened", session)
		self:_Publish("Opened", {Key = normalizedKey, Revision = session.Revision})
		return session
	end)
end

-- Opens a player record while protecting custom PlayerKey handlers from propagating callback errors.
function NexusDataStore:OpenPlayerAsync(player: Player): (Session<Data>?, string?)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "OpenPlayerAsync expects a Player")
	local key
	if self.Config.PlayerKey then
		local ok, result = pcall(self.Config.PlayerKey, player)
		if not ok then
			return nil, "PLAYER_KEY_FAILED:" .. tostring(result)
		end
		key = result
	else
		key = player.UserId
	end
	if typeof(key) ~= "string" and typeof(key) ~= "number" then
		return nil, "PLAYER_KEY_INVALID"
	end
	return self:OpenAsync(key, {
		Player = player,
		UserId = player.UserId,
	})
end

function NexusDataStore:PeekAsync(key: string | number): (Data?, {[string]: any} | string?)
	if self.Closed then
		return nil, "STORE_CLOSED"
	end
	local keyOK, normalizedKey = pcall(normalizeDataKey, key, self.Config.KeyPrefix)
	if not keyOK then
		return nil, "INVALID_DATA_KEY:" .. tostring(normalizedKey)
	end
	local loadDeadline = now() + self.Config.LoadTimeout
	local success, raw = self:_Retry(function()
		return self.DataStore:GetAsync(normalizedKey)
	end, REQUEST_GET, loadDeadline, "LOAD_TIMEOUT")
	if not success then
		return nil, tostring(raw)
	end
	if raw == nil then
		return nil, "NOT_FOUND"
	end
	local record, err = self:_DecodeRecord(raw)
	if not record then
		return nil, err
	end
	return clone(record.Data) :: Data, {
		SchemaVersion = record.SchemaVersion,
		Revision = record.Revision,
		CreatedAt = record.CreatedAt,
		UpdatedAt = record.UpdatedAt,
		Locked = self:_LockIsActive(record.Lock),
		LockExpiresAt = record.Lock and record.Lock.ExpiresAt or nil,
	}
end

function NexusDataStore:_ResolveKey(keyOrPlayer: any): string?
	if typeof(keyOrPlayer) == "Instance" and keyOrPlayer:IsA("Player") then
		local session = self.SessionByPlayer[keyOrPlayer]
		if session then
			return session.Key
		end
		local rawKey = keyOrPlayer.UserId
		if self.Config.PlayerKey then
			local ok, result = pcall(self.Config.PlayerKey, keyOrPlayer)
			if not ok then
				self:_Fire("PlayerKeyFailed", keyOrPlayer, tostring(result))
				return nil
			end
			rawKey = result
		end
		local ok, normalized = pcall(normalizeDataKey, rawKey, self.Config.KeyPrefix)
		return ok and normalized or nil
	elseif typeof(keyOrPlayer) == "string" or typeof(keyOrPlayer) == "number" then
		local ok, normalized = pcall(normalizeDataKey, keyOrPlayer, self.Config.KeyPrefix)
		return ok and normalized or nil
	end
	return nil
end

function NexusDataStore:GetSession(keyOrPlayer: string | number | Player): Session<Data>?
	if typeof(keyOrPlayer) == "Instance" and keyOrPlayer:IsA("Player") then
		return self.SessionByPlayer[keyOrPlayer]
	end
	local key = self:_ResolveKey(keyOrPlayer)
	return key and self.Sessions[key] or nil
end

function NexusDataStore:WaitForSession(keyOrPlayer: string | number | Player, timeout: number?): (Session<Data>?, string?)
	local deadline = now() + (timeout or self.Config.LoadTimeout)
	repeat
		local session = self:GetSession(keyOrPlayer)
		if session and session:IsActive() then
			return session
		end
		task.wait(0.05)
	until now() >= deadline or self.Closed
	return nil, self.Closed and "STORE_CLOSED" or "SESSION_WAIT_TIMEOUT"
end

function NexusDataStore:_AcquireCommitLock(session: any, absoluteDeadline: number?): (boolean, string?)
	local deadline = absoluteDeadline or (now() + self.Config.SaveTimeout)
	while session.CommitBusy do
		if not session:IsActive() then
			return false, "SESSION_INACTIVE"
		end
		if now() >= deadline then
			return false, "COMMIT_LOCK_TIMEOUT"
		end
		task.wait(0.02)
	end
	session.CommitBusy = true
	return true
end

function NexusDataStore:_ReleaseCommitLock(session: any)
	session.CommitBusy = false
end

function NexusDataStore:_DetectDirectChanges(session: any)
	if not self.Config.DetectDirectChanges or not session:IsActive() then
		return
	end
	if not deepEqual(session.Data, session.ObservedSnapshot) then
		session.Dirty = true
		local cloned, observed = pcall(clone, session.Data)
		if not cloned then
			if not session.DirectChangeInvalid then
				session.MutationId += 1
				self.Metrics.DirectChanges += 1
				self:_Fire("DirectChangeInvalid", session, tostring(observed))
			end
			session.DirectChangeInvalid = true
			return
		end
		session.DirectChangeInvalid = false
		session.MutationId += 1
		session.ObservedSnapshot = observed
		self.Metrics.DirectChanges += 1
		session:_EmitChange(nil, nil, nil)
	end
end

function NexusDataStore:_Commit(session: any, release: boolean, reason: string): (boolean, string?)
	if not session or not session:IsActive() then
		return false, "SESSION_INACTIVE"
	end
	local commitStartedAt = now()
	local commitDeadline = commitStartedAt + self.Config.SaveTimeout
	local locked, lockErr = self:_AcquireCommitLock(session, commitDeadline)
	if not locked then
		return false, lockErr
	end
	local protectedOK, commitOK, commitErr = pcall(function()
		local persistData = reason ~= "heartbeat"
		local snapshot: any = nil
		-- Heartbeats only renew ownership; they must not pay for a full direct-change
		-- scan, validation pass, and deep clone of the live player state.
		if persistData then
			-- A clean session needs a direct-write scan before snapshotting. A dirty
			-- session is already going to persist the current live table.
			if not session.Dirty then
				self:_DetectDirectChanges(session)
			end
			local valid, validationErr = self:Validate(session.Data)
			if not valid then
				return false, "SAVE_VALIDATION_FAILED:" .. tostring(validationErr)
			end
			snapshot = clone(session.Data)
		end
		local hadDirty = session.Dirty
		local mutationIdAtStart = session.MutationId
		local saveError
		local nextRevision = session.Revision
		local startTime = commitStartedAt
		local commitId = HttpService:GenerateGUID(false)
		local encodeReport

		local success, result = self:_Retry(function()
			return self.DataStore:UpdateAsync(session.Key, function(raw)
				saveError = nil
				encodeReport = nil
				local record, decodeErr = self:_DecodeRecord(raw)
				if not record then
					saveError = decodeErr or "RECORD_MISSING"
					return nil
				end
				if record.LastCommitId == commitId then
					nextRevision = tonumber(record.Revision) or session.Revision
					local repeatedEncoded, repeatedEncodeErr, repeatedReport = self:_EncodeRecord(record)
					if repeatedEncoded == nil then
						saveError = repeatedEncodeErr
						return nil
					end
					encodeReport = repeatedReport
					return repeatedEncoded
				end
				if not self:_OwnsRecord(record, session) then
					saveError = "SESSION_LOST"
					return nil
				end
				local remoteRevision = tonumber(record.Revision)
				if remoteRevision == nil or remoteRevision ~= session.Revision then
					saveError = "REVISION_CONFLICT"
					return nil
				end
				-- UpdateAsync can invoke this transform more than once. Use the immutable
				-- commit-start dirty state, never live session.Dirty, so every retry writes
				-- the exact same snapshot and revision decision.
				if (hadDirty and persistData) or release then
					local dataChanged = hadDirty and persistData
					nextRevision = remoteRevision + (dataChanged and 1 or 0)
					if dataChanged or release then
						record.Data = snapshot
					end
					record.Revision = nextRevision
					record.SchemaVersion = self.SchemaVersion
					record.UpdatedAt = unix()
				end
				if release then
					record.Lock = nil
				else
					self:_LockRecord(record, session.SessionId)
				end
				record.LastCommitId = commitId
				local encoded, encodeErr, currentReport = self:_EncodeRecord(record)
				if encoded == nil then
					saveError = encodeErr
					return nil
				end
				encodeReport = currentReport
				return encoded
			end)
		end, REQUEST_STANDARD_UPDATE, commitDeadline, "SAVE_TIMEOUT")

		if not success then
			self.Metrics.SaveFailed += 1
			return false, tostring(result)
		end
		if saveError then
			self.Metrics.SaveFailed += 1
			if saveError == "SESSION_LOST" or saveError == "REVISION_CONFLICT" then
				self:_LoseSession(session, saveError)
			end
			return false, saveError
		end
		self:_RecordEncoding(encodeReport)
		session.Revision = nextRevision
		session.LastHeartbeatAt = now()
		local changedDuringCommit = false
		if persistData then
			session.LastSaveAt = now()
			session.NextAutoSaveAt = session.LastSaveAt + self.Config.AutoSaveInterval
			session.LastPersistedSnapshot = snapshot
			-- Controlled mutations increment MutationId, which is much cheaper to test
			-- than a deep comparison. Only fall back to deepEqual when direct table edits
			-- are enabled and no tracked mutation occurred during the request.
			changedDuringCommit = session.MutationId ~= mutationIdAtStart
			if not changedDuringCommit and self.Config.DetectDirectChanges then
				changedDuringCommit = not deepEqual(session.Data, snapshot)
			end
			if changedDuringCommit then
				session.Dirty = true
				session.ObservedSnapshot = self.Config.DetectDirectChanges and clone(session.Data) or nil
			else
				session.Dirty = false
				session.ObservedSnapshot = self.Config.DetectDirectChanges and clone(snapshot) or nil
			end
			self.Metrics.Saved += 1
			self.Metrics.SaveTime += now() - startTime
			self:_Fire("Saved", session, reason, release)
			self:_Publish("Saved", {Key = session.Key, Revision = session.Revision, Release = release})
		end

		if persistData and not changedDuringCommit and (hadDirty or release) then
			local orderedOK, orderedErr = self:_SyncAutoOrdered(session)
			if not orderedOK then
				self:_Fire("OrderedSyncFailed", session, orderedErr)
			end
		end
		if release and changedDuringCommit then
			self:_LoseSession(session, "CONCURRENT_MUTATION_DURING_RELEASE")
			return false, "CONCURRENT_MUTATION_DURING_RELEASE"
		end
		return true
	end)
	self:_ReleaseCommitLock(session)
	if not protectedOK then
		self.Metrics.SaveFailed += 1
		return false, tostring(commitOK)
	end
	return commitOK, commitErr
end

-- Saves a dirty active session while preserving changes that occur during an in-flight commit.
function NexusDataStore:SaveAsync(session: any, priority: SavePriority?): (boolean, string?)
	if not session or session.Store ~= self or not session:IsActive() then
		return false, "SESSION_INACTIVE"
	end
	priority = priority or "high"
	if priority ~= "normal" and priority ~= "high" and priority ~= "critical" then
		return false, "INVALID_SAVE_PRIORITY"
	end
	if not session.Dirty then
		self:_DetectDirectChanges(session)
		if not session.Dirty then
			return true
		end
	end
	if priority == "normal" and now() - session.LastSaveAt < self.Config.MinimumSaveInterval then
		return true, "DEFERRED"
	end
	return self:_Commit(session, false, priority)
end

function NexusDataStore:_UnregisterSession(session: any)
	if self.Sessions[session.Key] == session then
		self.Sessions[session.Key] = nil
	end
	if self.SessionById[session.SessionId] == session then
		self.SessionById[session.SessionId] = nil
	end
	if session.Player and self.SessionByPlayer[session.Player] == session then
		self.SessionByPlayer[session.Player] = nil
	end
end

function NexusDataStore:_LoseSession(session: any, reason: string)
	if not session.Active then
		return
	end
	session.Active = false
	session.Releasing = false
	self:_UnregisterSession(session)
	self.Metrics.SessionLost += 1
	self:_Fire("SessionLost", session, reason)
end

-- Releases ownership safely and rejects normal API mutations while the lock-clearing commit is in flight.
function NexusDataStore:ReleaseAsync(session: any): (boolean, string?)
	if not session or session.Store ~= self then
		return true
	end
	if not session:IsActive() then
		return true
	end
	if session.Releasing then
		local deadline = now() + self.Config.SaveTimeout
		while session.Releasing and session:IsActive() and now() < deadline do
			task.wait(0.02)
		end
		if not session:IsActive() then
			return true
		end
		if session.Releasing then
			return false, "SESSION_RELEASING_TIMEOUT"
		end
	end
	session.Releasing = true
	local ok, err = self:_Commit(session, true, "release")
	if not ok then
		if session.Active then
			session.Releasing = false
		end
		return false, err
	end
	session.Active = false
	session.Releasing = false
	self:_UnregisterSession(session)
	self.Metrics.Released += 1
	self:_Fire("Released", session)
	self:_Publish("Released", {Key = session.Key, Revision = session.Revision})
	return true
end

function NexusDataStore:_Heartbeat(session: any)
	if not session:IsActive() then
		return
	end
	if now() - session.LastHeartbeatAt < self.Config.HeartbeatInterval then
		return
	end
	local ok, err = self:_Commit(session, false, "heartbeat")
	if ok then
		self.Metrics.Heartbeats += 1
	else
		self:_Fire("HeartbeatFailed", session, err)
	end
end

function NexusDataStore:_BackgroundLoop()
	task.spawn(function()
		while not self.Closed do
			if not self.Closing then
				local sessions = {}
				for _, session in pairs(self.Sessions) do
					table.insert(sessions, session)
				end
				local currentTime = now()
				for _, session in ipairs(sessions) do
					if session:IsActive() then
						-- Controlled mutations already mark Dirty. Only scan a clean session for
						-- raw/direct table edits; this avoids an O(data) deepEqual every second
						-- while a record is already waiting to save.
						if not session.Dirty then
							self:_DetectDirectChanges(session)
						end
						if self.Config.AutoSave
							and session.Dirty
							and currentTime >= session.NextAutoSaveAt
							and not session.SavePending then
							session.SavePending = true
							session.NextAutoSaveAt = currentTime + self.Config.AutoSaveInterval
							task.spawn(function()
								local callOK, ok, err = pcall(self.SaveAsync, self, session, "normal")
								session.SavePending = false
								if not callOK then
									self:_Fire("AutoSaveFailed", session, tostring(ok))
								elseif not ok then
									self:_Fire("AutoSaveFailed", session, err)
								end
							end)
						elseif currentTime - session.LastHeartbeatAt >= self.Config.HeartbeatInterval
							and not session.HeartbeatPending
							and not session.SavePending
							and not session.CommitBusy then
							session.HeartbeatPending = true
							task.spawn(function()
								local callOK, err = pcall(self._Heartbeat, self, session)
								session.HeartbeatPending = false
								if not callOK then
									self:_Fire("HeartbeatFailed", session, tostring(err))
								end
							end)
						end
					end
				end
			end
			task.wait(1)
		end
	end)
end

function NexusDataStore:FlushAsync(timeout: number?): (boolean, string?)
	local deadline = now() + (timeout or self.Config.SaveTimeout)
	local sessions = {}
	for _, session in pairs(self.Sessions) do
		table.insert(sessions, session)
	end
	for _, session in ipairs(sessions) do
		if session:IsActive() then
			self:_DetectDirectChanges(session)
			if session.Dirty then
				local remaining = deadline - now()
				if remaining <= 0 then
					return false, "FLUSH_TIMEOUT"
				end
				local ok, err = self:SaveAsync(session, "critical")
				if not ok then
					return false, err
				end
			end
		end
	end
	return true
end

function NexusDataStore:ReleaseAllAsync(): {[string]: any}
	local sessions = {}
	for _, session in pairs(self.Sessions) do
		table.insert(sessions, session)
	end
	local results = {}
	for _, session in ipairs(sessions) do
		local ok, err = self:ReleaseAsync(session)
		results[session.Key] = {Success = ok, Error = err}
	end
	return results
end

function NexusDataStore:_HandleLifecycleJoin(player: Player)
	local session, err = self:OpenPlayerAsync(player)
	if not session then
		self:_Fire("PlayerLoadFailed", player, err)
		return
	end
	if player.Parent ~= Players then
		local released, releaseErr = self:ReleaseAsync(session)
		if not released then
			self:_Fire("PlayerReleaseFailed", player, releaseErr)
		end
	end
end

-- Attaches player join/leave handlers and closes the load-versus-leave race that can otherwise strand a session lock.
function NexusDataStore:AttachPlayerLifecycle()
	if self.LifecycleAttached then
		return
	end
	self.LifecycleAttached = true
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			self:_HandleLifecycleJoin(player)
		end)
	end
	self.PlayerAddedConnection = Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			self:_HandleLifecycleJoin(player)
		end)
	end)
	self.PlayerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
		local session = self.SessionByPlayer[player]
		if session then
			task.spawn(function()
				local ok, err = self:ReleaseAsync(session)
				if not ok then
					self:_Fire("PlayerReleaseFailed", player, err)
				end
			end)
		end
	end)
end

function NexusDataStore:BindToClose()
	if self.BoundToClose then
		return
	end
	self.BoundToClose = true
	game:BindToClose(function()
        local ok, err = self:CloseAsync(self.Config.SaveTimeout)
        if not ok then warn("[NexusDataStore] BindToClose could not release every session:", err) end
	end)
end

function NexusDataStore:CloseAsync(timeout: number?): (boolean, string?)
	if self.Closed then
		return true
	end
    if self.Closing then
        return false, "CLOSE_IN_PROGRESS"
    end
    if timeout ~= nil and (not finiteNumber(timeout) or timeout <= 0) then
        return false, "INVALID_CLOSE_TIMEOUT"
    end
	self.Closing = true
	local deadline = now() + (timeout or self.Config.SaveTimeout)
	local sessions = {}
	for _, session in pairs(self.Sessions) do
		table.insert(sessions, session)
	end
	local firstError
	for _, session in ipairs(sessions) do
		if now() >= deadline then
			firstError = firstError or "CLOSE_TIMEOUT"
			break
		end
        local released, ok, err = pcall(self.ReleaseAsync, self, session)
        if not released then
            firstError = firstError or "RELEASE_EXCEPTION:" .. tostring(ok)
        elseif not ok then
            firstError = firstError or err or "RELEASE_FAILED"
        end
	end
    -- Do not permanently stop heartbeats/saves while any active session
    -- remains unreleased. Leave the store open so callers can retry CloseAsync.
    for _, session in pairs(self.Sessions) do
        if session:IsActive() then
            firstError = firstError or "ACTIVE_SESSIONS_REMAIN"
            break
        end
    end
    if firstError ~= nil then
        self.Closing = false
        self:_Fire("CloseFailed", firstError)
        return false, firstError
    end
	if self.CrossServerSubscription then
		pcall(function()
			self.CrossServerSubscription:Disconnect()
		end)
	end
	if self.PlayerAddedConnection then
		self.PlayerAddedConnection:Disconnect()
	end
	if self.PlayerRemovingConnection then
		self.PlayerRemovingConnection:Disconnect()
	end
	self.Closed = true
	self.Closing = false
	self:_Fire("Closed", firstError)
	return firstError == nil, firstError
end

function NexusDataStore:GetMetrics()
	local output = clone(self.Metrics)
	local active = 0
	local dirty = 0
	for _, session in pairs(self.Sessions) do
		if session:IsActive() then
			active += 1
			if session.Dirty then
				dirty += 1
			end
		end
	end
	output.ActiveSessions = active
	output.DirtySessions = dirty
	output.AverageLoadTime = output.Opened > 0 and output.LoadTime / output.Opened or 0
	output.AverageSaveTime = output.Saved > 0 and output.SaveTime / output.Saved or 0
	return output
end

function NexusDataStore:GetHealth()
	local budgets = {}
	local requestMap = {
		StandardRead = REQUEST_GET,
		StandardWrite = REQUEST_UPDATE,
		OrderedRead = REQUEST_ORDERED_READ,
		OrderedWrite = REQUEST_ORDERED_WRITE,
		OrderedList = REQUEST_ORDERED_LIST,
		OrderedRemove = REQUEST_ORDERED_REMOVE,
	}
	for name, requestType in pairs(requestMap) do
		if requestType then
			local ok, value = pcall(DataStoreService.GetRequestBudgetForRequestType, DataStoreService, requestType)
			budgets[name] = ok and value or -1
		end
	end
	return {
		Version = NexusDataStore.Version,
		RecordFormat = RECORD_FORMAT,
		CompressionVersion = self.CompressionEngineVersion,
		Closed = self.Closed,
		Closing = self.Closing,
		JobId = self.JobId,
		Budgets = budgets,
		Metrics = self:GetMetrics(),
	}
end

function NexusDataStore:GetTemplate(): Data
	return clone(self.Template) :: Data
end

function NexusDataStore:GetSchema()
	return clone(self.Schema)
end

function NexusDataStore:GetVersion(): string
	return NexusDataStore.Version
end

function NexusDataStore:EncodeCompressed(data: any): (buffer?, any)
	if not self.CompressionEngine then
		return nil, "COMPRESSION_ENGINE_UNAVAILABLE:" .. tostring(self.CompressionEngineError)
	end
	local ok, encoded, report = pcall(self.CompressionEngine.CompressTablePacket, data, self.Config.CompressionOptions)
	if not ok then
		return nil, tostring(encoded)
	end
	return encoded, report
end

function NexusDataStore:DecodeCompressed(raw: buffer): (any?, string?)
	if not self.CompressionEngine then
		return nil, "COMPRESSION_ENGINE_UNAVAILABLE:" .. tostring(self.CompressionEngineError)
	end
	local ok, decoded = pcall(self.CompressionEngine.DecompressTable, raw, self.Config.CompressionOptions)
	if not ok then
		return nil, tostring(decoded)
	end
	return decoded
end

-- Reports packet and persistence transport sizes using the same JSON-size measurement Roblox documents for DataStore limits.
function NexusDataStore:GetCompressionReport(dataOrSession: any): (any?, string?)
	if not self.CompressionEngine then
		return nil, "COMPRESSION_ENGINE_UNAVAILABLE:" .. tostring(self.CompressionEngineError)
	end
	local data = dataOrSession
	if typeof(dataOrSession) == "table" and dataOrSession.Store == self then
		data = dataOrSession.Data
	end
	local valid, validationErr = self:Validate(data)
	if not valid then
		return nil, validationErr
	end

	-- Reuse the exact persistence selection path so reports cannot drift away from
	-- what SaveAsync will actually write.
	local record = self:_BuildNewRecord(clone(data))
	local encoded, encodeErr, report = self:_EncodeRecord(record)
	if encoded == nil then
		return nil, encodeErr
	end
	return report
end

local function normalizeOrderedKey(key: any): string
	assert(typeof(key) == "string" or typeof(key) == "number", "OrderedDataStore key must be a string or number")
	if typeof(key) == "number" then
		assert(finiteNumber(key), "Numeric OrderedDataStore key must be finite")
	end
	local output = tostring(key)
	assert(#output > 0 and #output <= 50, "OrderedDataStore key must be 1-50 bytes")
	return output
end

function OrderedStore.new(parent: any, alias: string, config: any)
	assert(typeof(alias) == "string" and #alias > 0, "OrderedDataStore alias must be a non-empty string")
	assert(typeof(config) == "table", "OrderedDataStore config must be a table")
	local name = config.Name or (parent.Config.Name .. "_" .. alias)
	local scope = config.Scope or parent.Config.Scope
	local mode = config.Mode or "max"
	assert(typeof(name) == "string" and #name > 0 and #name <= 50, "OrderedDataStore Name must be 1-50 bytes")
	assert(typeof(scope) == "string" and #scope > 0 and #scope <= 50, "OrderedDataStore Scope must be 1-50 bytes")
	assert(mode == "set" or mode == "max" or mode == "min", "OrderedDataStore Mode must be set, max, or min")
	if config.ToNumber ~= nil then
		assert(typeof(config.ToNumber) == "function", "OrderedDataStore ToNumber must be a function")
	end
	if config.KeyFromSession ~= nil then
		assert(typeof(config.KeyFromSession) == "function", "OrderedDataStore KeyFromSession must be a function")
	end
	if config.ClampMin ~= nil then
		assert(finiteNumber(config.ClampMin), "OrderedDataStore ClampMin must be finite")
	end
	if config.ClampMax ~= nil then
		assert(finiteNumber(config.ClampMax), "OrderedDataStore ClampMax must be finite")
	end
	if config.Round ~= nil then
		assert(config.Round == "nearest" or config.Round == "floor" or config.Round == "ceil", "OrderedDataStore Round must be nearest, floor, or ceil")
	end
	if config.Path ~= nil then
		local pathOK, pathErr = pcall(normalizePath, config.Path)
		assert(pathOK, "OrderedDataStore Path invalid: " .. tostring(pathErr))
	end
	if config.AutoSync == true then
		assert(config.Path ~= nil, "OrderedDataStore AutoSync requires Path")
	end
	if config.Integer == true then
		assert(config.ClampMin == nil or safeInteger(config.ClampMin), "OrderedDataStore integer ClampMin must be a safe integer")
		assert(config.ClampMax == nil or safeInteger(config.ClampMax), "OrderedDataStore integer ClampMax must be a safe integer")
	end
	if config.ClampMin ~= nil and config.ClampMax ~= nil then
		assert(config.ClampMax >= config.ClampMin, "OrderedDataStore ClampMax must be >= ClampMin")
	end
	return setmetatable({
		Parent = parent,
		Alias = alias,
		Name = name,
		Scope = scope,
		Path = config.Path,
		Mode = mode,
		AutoSync = config.AutoSync == true,
		ToNumber = config.ToNumber,
		KeyFromSession = config.KeyFromSession,
		ClampMin = config.ClampMin,
		ClampMax = config.ClampMax,
		Integer = config.Integer == true,
		Round = config.Round,
		RemoveWhenNil = config.RemoveWhenNil == true,
		DataStore = DataStoreService:GetOrderedDataStore(name, scope),
		KeyLocks = {},
	}, OrderedStore)
end

function OrderedStore:_WithKeyLock(key: string, callback)
	local deadline = now() + self.Parent.Config.SaveTimeout
	while self.KeyLocks[key] do
		if now() >= deadline then
			return false, "ORDERED_KEY_LOCK_TIMEOUT"
		end
		task.wait(0.02)
	end
	self.KeyLocks[key] = true
	local ok, a, b, c = pcall(callback)
	self.KeyLocks[key] = nil
	if not ok then
		return false, tostring(a)
	end
	return a, b, c
end

function OrderedStore:_NormalizeValue(value: any, session: any?): (number?, string?)
	if self.ToNumber then
		local ok, projected = pcall(self.ToNumber, value, session)
		if not ok then
			return nil, "ORDERED_TO_NUMBER_FAILED:" .. tostring(projected)
		end
		value = projected
	end
	if value == nil then
		return nil, "ORDERED_VALUE_NIL"
	end
	if not finiteNumber(value) then
		return nil, "ORDERED_VALUE_MUST_BE_FINITE_NUMBER"
	end
	if self.ClampMin ~= nil then
		value = math.max(value, self.ClampMin)
	end
	if self.ClampMax ~= nil then
		value = math.min(value, self.ClampMax)
	end
	if self.Round == "nearest" then
		value = value >= 0 and math.floor(value + 0.5) or math.ceil(value - 0.5)
	elseif self.Round == "floor" then
		value = math.floor(value)
	elseif self.Round == "ceil" then
		value = math.ceil(value)
	end
	if self.Integer and not safeInteger(value) then
		return nil, "ORDERED_VALUE_MUST_BE_SAFE_INTEGER"
	end
	return value
end

function OrderedStore:_SessionKey(session: any): (string?, string?)
	local rawKey
	if self.KeyFromSession then
		local ok, result = pcall(self.KeyFromSession, session)
		if not ok then
			return nil, "ORDERED_KEY_FROM_SESSION_FAILED:" .. tostring(result)
		end
		rawKey = result
	elseif session.UserId then
		rawKey = session.UserId
	else
		rawKey = session.Key
	end
	local ok, result = pcall(normalizeOrderedKey, rawKey)
	if not ok then
		return nil, tostring(result)
	end
	return result
end

-- Reads one numeric ordered value with backend and configured integer validation.
function OrderedStore:GetAsync(key: any): (boolean, any)
	key = normalizeOrderedKey(key)
	local success, result = self.Parent:_Retry(function()
		return self.DataStore:GetAsync(key)
	end, REQUEST_ORDERED_READ)
	if not success then
		self.Parent.Metrics.OrderedReadFailed += 1
		return false, tostring(result)
	end
	if result ~= nil and not finiteNumber(result) then
		return false, "ORDERED_BACKEND_RETURNED_INVALID_NUMBER"
	end
	if result ~= nil and self.Integer and not safeInteger(result) then
		return false, "ORDERED_BACKEND_RETURNED_NON_INTEGER"
	end
	self.Parent.Metrics.OrderedReads += 1
	return true, result
end

function OrderedStore:SetAsync(key: any, value: any): (boolean, any)
	key = normalizeOrderedKey(key)
	local normalized, err = self:_NormalizeValue(value)
	if normalized == nil then
		return false, err
	end
	return self:_WithKeyLock(key, function()
		local success, result = self.Parent:_Retry(function()
			return self.DataStore:SetAsync(key, normalized)
		end, REQUEST_ORDERED_WRITE)
		if not success then
			self.Parent.Metrics.OrderedWriteFailed += 1
			return false, tostring(result)
		end
		self.Parent.Metrics.OrderedWrites += 1
		return true, normalized
	end)
end

-- Atomically transforms one ordered value; the callback must remain non-yielding and retry-safe for Roblox UpdateAsync.
function OrderedStore:UpdateAsync(key: any, transform): (boolean, any, any?)
	key = normalizeOrderedKey(key)
	assert(typeof(transform) == "function", "OrderedDataStore UpdateAsync transform required")
	return self:_WithKeyLock(key, function()
		local callbackError
		local cancelled = false
		local nextValue
		local success, result = self.Parent:_Attempt(function()
			return self.DataStore:UpdateAsync(key, function(oldValue)
				callbackError = nil
				cancelled = false
				nextValue = nil
				if oldValue ~= nil and not finiteNumber(oldValue) then
					callbackError = "ORDERED_BACKEND_RETURNED_INVALID_NUMBER"
					error(callbackError)
				end
				if oldValue ~= nil and self.Integer and not safeInteger(oldValue) then
					callbackError = "ORDERED_BACKEND_RETURNED_NON_INTEGER"
					error(callbackError)
				end
				local ok, transformed = pcall(transform, oldValue)
				if not ok then
					callbackError = tostring(transformed)
					error(callbackError)
				end
				if transformed == nil then
					cancelled = true
					return nil
				end
				local normalized, normalizeErr = self:_NormalizeValue(transformed)
				if normalized == nil then
					callbackError = normalizeErr
					error(callbackError)
				end
				nextValue = normalized
				return normalized
			end)
		end, REQUEST_ORDERED_UPDATE)
		if not success then
			self.Parent.Metrics.OrderedWriteFailed += 1
			return false, callbackError or tostring(result)
		end
		self.Parent.Metrics.OrderedUpdates += 1
		if cancelled then
			self.Parent.Metrics.OrderedNoops += 1
			return true, result, "CANCELLED"
		end
		self.Parent.Metrics.OrderedWrites += 1
		return true, nextValue or result
	end)
end

function OrderedStore:MaxAsync(key: any, value: any)
	local normalized, err = self:_NormalizeValue(value)
	if normalized == nil then
		return false, err
	end
	return self:UpdateAsync(key, function(oldValue)
		if oldValue == nil or normalized > oldValue then
			return normalized
		end
		return nil
	end)
end

function OrderedStore:MinAsync(key: any, value: any)
	local normalized, err = self:_NormalizeValue(value)
	if normalized == nil then
		return false, err
	end
	return self:UpdateAsync(key, function(oldValue)
		if oldValue == nil or normalized < oldValue then
			return normalized
		end
		return nil
	end)
end

-- Increments ordered values without using IncrementAsync for floating-point stores, since Roblox IncrementAsync requires integer operands.
function OrderedStore:IncrementAsync(key: any, delta: number?): (boolean, any)
	key = normalizeOrderedKey(key)
	delta = delta or 1
	if not finiteNumber(delta) then
		return false, "ORDERED_DELTA_MUST_BE_FINITE_NUMBER"
	end
	if not self.Integer or self.ClampMin ~= nil or self.ClampMax ~= nil or self.Round ~= nil then
		return self:UpdateAsync(key, function(oldValue)
			return (oldValue or 0) + delta
		end)
	end
	if not safeInteger(delta) then
		return false, "ORDERED_DELTA_MUST_BE_SAFE_INTEGER"
	end
	return self:_WithKeyLock(key, function()
		local success, result = self.Parent:_Attempt(function()
			return self.DataStore:IncrementAsync(key, delta)
		end, REQUEST_ORDERED_WRITE)
		if not success then
			self.Parent.Metrics.OrderedWriteFailed += 1
			return false, tostring(result)
		end
		if not safeInteger(result) then
			return false, "ORDERED_BACKEND_RETURNED_INVALID_INTEGER"
		end
		self.Parent.Metrics.OrderedWrites += 1
		return true, result
	end)
end

function OrderedStore:RemoveAsync(key: any): (boolean, any)
	key = normalizeOrderedKey(key)
	return self:_WithKeyLock(key, function()
		local success, result = self.Parent:_Retry(function()
			return self.DataStore:RemoveAsync(key)
		end, REQUEST_ORDERED_REMOVE)
		if not success then
			self.Parent.Metrics.OrderedWriteFailed += 1
			return false, tostring(result)
		end
		self.Parent.Metrics.OrderedRemoves += 1
		return true, result
	end)
end

function OrderedStore:WriteAsync(key: any, value: any, mode: OrderedWriteMode?): (boolean, any)
	mode = mode or self.Mode
	if mode == "set" then
		return self:SetAsync(key, value)
	elseif mode == "max" then
		return self:MaxAsync(key, value)
	elseif mode == "min" then
		return self:MinAsync(key, value)
	end
	return false, "INVALID_ORDERED_MODE"
end

function OrderedStore:GetSortedAsync(ascending: boolean?, pageSize: number?, minimum: number?, maximum: number?): (boolean, any)
	pageSize = pageSize or 50
	assert(safeInteger(pageSize) and pageSize >= 1 and pageSize <= 100, "pageSize must be an integer from 1 to 100")
	if minimum ~= nil then
		assert(safeInteger(minimum), "minimum must be a safe integer")
	end
	if maximum ~= nil then
		assert(safeInteger(maximum), "maximum must be a safe integer")
	end
	if minimum ~= nil and maximum ~= nil then
		assert(maximum >= minimum, "maximum must be >= minimum")
	end
	local success, pages = self.Parent:_Retry(function()
		return self.DataStore:GetSortedAsync(ascending == true, pageSize, minimum, maximum)
	end, REQUEST_ORDERED_LIST)
	if not success then
		self.Parent.Metrics.OrderedReadFailed += 1
		return false, tostring(pages)
	end
	self.Parent.Metrics.OrderedReads += 1
	return true, pages
end

function OrderedStore:GetPageAsync(ascending: boolean?, pageSize: number?, minimum: number?, maximum: number?): (boolean, any)
	local ok, pages = self:GetSortedAsync(ascending, pageSize, minimum, maximum)
	if not ok then
		return false, pages
	end
	local entries = pages:GetCurrentPage()
	local output = table.create(#entries)
	for index, entry in ipairs(entries) do
		output[index] = {Key = entry.key, Value = entry.value, Rank = index}
	end
	return true, output
end

function OrderedStore:GetTopAsync(limit: number?, minimum: number?, maximum: number?)
	return self:GetPageAsync(false, limit or 10, minimum, maximum)
end

function OrderedStore:GetBottomAsync(limit: number?, minimum: number?, maximum: number?)
	return self:GetPageAsync(true, limit or 10, minimum, maximum)
end

function OrderedStore:GetRankAsync(key: any, ascending: boolean?, maxPages: number?): (boolean, any)
	key = normalizeOrderedKey(key)
	maxPages = maxPages or 10
	assert(safeInteger(maxPages) and maxPages >= 1, "maxPages must be a positive integer")
	local ok, pages = self:GetSortedAsync(ascending, 100)
	if not ok then
		return false, pages
	end
	local rank = 0
	for _ = 1, maxPages do
		local page = pages:GetCurrentPage()
		for _, entry in ipairs(page) do
			rank += 1
			if tostring(entry.key) == key then
				return true, {Rank = rank, Key = entry.key, Value = entry.value}
			end
		end
		if pages.IsFinished then
			return false, "ORDERED_KEY_NOT_FOUND"
		end
		local advanced, advanceErr = self.Parent:_Retry(function()
			return pages:AdvanceToNextPageAsync()
		end, REQUEST_ORDERED_LIST)
		if not advanced then
			return false, tostring(advanceErr)
		end
	end
	return false, "RANK_SCAN_LIMIT"
end

function OrderedStore:SyncSessionAsync(session: any): (boolean, any)
	if self.Path == nil then
		return false, "ORDERED_PATH_NOT_CONFIGURED"
	end
	if not session or not session:IsActive() then
		return false, "SESSION_INACTIVE"
	end
	local key, keyErr = self:_SessionKey(session)
	if not key then
		return false, keyErr
	end
	local rawValue = getAt(session.LastPersistedSnapshot or session.Data, self.Path)
	if rawValue == nil and self.RemoveWhenNil then
		return self:RemoveAsync(key)
	end
	local numberValue, valueErr = self:_NormalizeValue(rawValue, session)
	if numberValue == nil then
		return false, valueErr
	end
	return self:WriteAsync(key, numberValue, self.Mode)
end

function NexusDataStore:_SyncAutoOrdered(session: any): (boolean, string?)
	for alias, ordered in pairs(self.OrderedStores) do
		if ordered.AutoSync then
			local ok, value, state = ordered:SyncSessionAsync(session)
			if ok then
				self.Metrics.OrderedSyncs += 1
				self:_Fire("OrderedSyncCompleted", session, alias, value, state)
			else
				self.Metrics.OrderedSyncFailed += 1
				return false, tostring(alias) .. ":" .. tostring(value)
			end
		end
	end
	return true
end

function NexusDataStore:GetOrderedStore(alias: string): (any?, string?)
	local ordered = self.OrderedStores[alias]
	if not ordered then
		return nil, "ORDERED_STORE_NOT_FOUND:" .. tostring(alias)
	end
	return ordered
end

function NexusDataStore:SyncOrderedAsync(session: any, alias: string?): (boolean, string?)
	if not session or session.Store ~= self or not session:IsActive() then
		return false, "SESSION_INACTIVE"
	end
	if alias then
		local ordered, err = self:GetOrderedStore(alias)
		if not ordered then
			return false, err
		end
		local ok, value = ordered:SyncSessionAsync(session)
		if ok then
			return true
		end
		return false, tostring(value)
	end
	for name, ordered in pairs(self.OrderedStores) do
		local ok, value = ordered:SyncSessionAsync(session)
		if not ok then
			return false, tostring(name) .. ":" .. tostring(value)
		end
	end
	return true
end

function NexusDataStore:SyncAllOrderedAsync(alias: string?): (boolean, string?)
	for _, session in pairs(self.Sessions) do
		if session:IsActive() then
			local ok, err = self:SyncOrderedAsync(session, alias)
			if not ok then
				return false, session.Key .. ":" .. tostring(err)
			end
		end
	end
	return true
end


function Session:IsActive(): boolean
	return self.Active == true and self.Store.Closed ~= true
end

function Session:IsDirty(): boolean
	return self.Dirty == true
end

function Session:_CanMutate(): (boolean, string?)
	if not self:IsActive() then
		return false, "SESSION_INACTIVE"
	end
	if self.Releasing then
		return false, "SESSION_RELEASING"
	end
	return true
end

function Session:_EmitChange(path: {PathKey}?, newValue: any, oldValue: any)
	local exact = self.Watchers[pathKey(path)]
	local wildcard = self.Watchers["*"]
	if exact == nil and wildcard == nil and self.Store.Events.Changed == nil then
		return
	end
	local callbacks = {}
	if exact then
		for _, callback in pairs(exact) do
			table.insert(callbacks, callback)
		end
	end
	if wildcard and wildcard ~= exact then
		for _, callback in pairs(wildcard) do
			table.insert(callbacks, callback)
		end
	end
	for _, callback in ipairs(callbacks) do
		task.spawn(callback, clone(newValue), clone(oldValue), self, path and clone(path) or nil)
	end
	self.Store:_Fire("Changed", self, path and clone(path) or nil, clone(newValue), clone(oldValue))
end

function Session:_CommitDraft(draft: any, path: {PathKey}?, oldValue: any, newValue: any): (boolean, string?)
	local mutable, mutableErr = self:_CanMutate()
	if not mutable then
		return false, mutableErr
	end
	if self.Store.Config.ValidateOnWrite then
		local valid, err = self.Store:Validate(draft)
		if not valid then
			return false, "VALIDATION_FAILED:" .. tostring(err)
		end
	end
	self.Data = draft
	self.Dirty = true
	self.MutationId += 1
	self.ObservedSnapshot = self.Store.Config.DetectDirectChanges and clone(draft) or nil
	self.Store.Metrics.Mutations += 1
	self:_EmitChange(path, newValue, oldValue)
	return true
end

function Session:Get(path: Path): any
	return clone(getAt(self.Data, path))
end

function Session:GetOr(path: Path, fallback: any): any
	local value = getAt(self.Data, path)
	if value == nil then
		return clone(fallback)
	end
	return clone(value)
end

function Session:Has(path: Path): boolean
	return getAt(self.Data, path) ~= nil
end

-- Replaces one value through the validated copy-on-write mutation path.
function Session:Set(path: Path, value: any): (boolean, string?)
	if not self:IsActive() then
		return false, "SESSION_INACTIVE"
	end
	local keys = normalizePath(path)
	local draft = clone(self.Data)
	local oldValue = clone(getAt(draft, keys))
	local ok, err = setAt(draft, keys, clone(value))
	if not ok then
		return false, err
	end
	return self:_CommitDraft(draft, keys, oldValue, clone(value))
end

function Session:Delete(path: Path): (boolean, string?)
	if not self:IsActive() then
		return false, "SESSION_INACTIVE"
	end
	local keys = normalizePath(path)
	local draft = clone(self.Data)
	local oldValue = clone(getAt(draft, keys))
	local ok, err = deleteAt(draft, keys)
	if not ok then
		return false, err
	end
	return self:_CommitDraft(draft, keys, oldValue, nil)
end

function Session:Increment(path: Path, amount: number?): (boolean, any)
	amount = amount or 1
	if not finiteNumber(amount) then
		return false, "INVALID_INCREMENT"
	end
	local current = getAt(self.Data, path)
	if not finiteNumber(current) then
		return false, "NOT_NUMBER"
	end
	local nextValue = current + amount
	if not finiteNumber(nextValue) then
		return false, "NON_FINITE_RESULT"
	end
	local ok, err = self:Set(path, nextValue)
	return ok, ok and nextValue or err
end

function Session:IncrementClamped(path: Path, amount: number?, minimum: number?, maximum: number?): (boolean, any)
	amount = amount or 1
	local current = getAt(self.Data, path)
	if not finiteNumber(current) or not finiteNumber(amount) then
		return false, "NOT_NUMBER"
	end
	if minimum ~= nil and not finiteNumber(minimum) then
		return false, "INVALID_MINIMUM"
	end
	if maximum ~= nil and not finiteNumber(maximum) then
		return false, "INVALID_MAXIMUM"
	end
	if minimum ~= nil and maximum ~= nil and maximum < minimum then
		return false, "INVALID_RANGE"
	end
	local nextValue = current + amount
	if not finiteNumber(nextValue) then
		return false, "NON_FINITE_RESULT"
	end
	if minimum ~= nil then
		nextValue = math.max(nextValue, minimum)
	end
	if maximum ~= nil then
		nextValue = math.min(nextValue, maximum)
	end
	local ok, err = self:Set(path, nextValue)
	return ok, ok and nextValue or err
end

function Session:Toggle(path: Path): (boolean, any)
	local current = getAt(self.Data, path)
	if typeof(current) ~= "boolean" then
		return false, "NOT_BOOLEAN"
	end
	local nextValue = not current
	local ok, err = self:Set(path, nextValue)
	if not ok then
		return false, err
	end
	return true, nextValue
end

function Session:Append(path: Path, value: any): (boolean, any)
	local current = getAt(self.Data, path)
	if typeof(current) ~= "table" then
		return false, "NOT_ARRAY"
	end
	local isArray = inspectTable(current)
	if not isArray then
		return false, "NOT_ARRAY"
	end
	local draft = clone(self.Data)
	local target = getAt(draft, path)
	table.insert(target, clone(value))
	local keys = normalizePath(path)
	local ok, err = self:_CommitDraft(draft, keys, clone(current), clone(target))
	return ok, ok and #target or err
end

function Session:RemoveAt(path: Path, index: number): (boolean, any)
	if not safeInteger(index) or index < 1 then
		return false, "INVALID_INDEX"
	end
	local current = getAt(self.Data, path)
	if typeof(current) ~= "table" then
		return false, "NOT_ARRAY"
	end
	local isArray, count = inspectTable(current)
	if not isArray or index > count then
		return false, "INDEX_OUT_OF_RANGE"
	end
	local draft = clone(self.Data)
	local target = getAt(draft, path)
	local removed = table.remove(target, index)
	local keys = normalizePath(path)
	local ok, err = self:_CommitDraft(draft, keys, clone(current), clone(target))
	if not ok then
		return false, err
	end
	return true, clone(removed)
end

function Session:Award(path: Path, amount: number): (boolean, any)
	if not finiteNumber(amount) or amount < 0 then
		return false, "INVALID_AMOUNT"
	end
	return self:Increment(path, amount)
end

function Session:Spend(path: Path, amount: number): (boolean, any)
	if not finiteNumber(amount) or amount < 0 then
		return false, "INVALID_AMOUNT"
	end
	local current = getAt(self.Data, path)
	if not finiteNumber(current) then
		return false, "NOT_NUMBER"
	end
	if current < amount then
		return false, "INSUFFICIENT_VALUE"
	end
	return self:Increment(path, -amount)
end

-- Transforms one path and rejects stale results if the callback changes the live session while it runs.
function Session:UpdatePath(path: Path, callback): (boolean, any)
	assert(typeof(callback) == "function", "UpdatePath callback required")
	local mutable, mutableErr = self:_CanMutate()
	if not mutable then
		return false, mutableErr
	end
	local baseMutationId = self.MutationId
	local current = clone(getAt(self.Data, path))
	local ok, transformed = pcall(callback, current, self)
	if not ok then
		return false, tostring(transformed)
	end
	if self.MutationId ~= baseMutationId then
		return false, "CONCURRENT_MUTATION"
	end
	if transformed == nil then
		return true, current, "CANCELLED"
	end
	local changed, err = self:Set(path, transformed)
	if not changed then
		return false, err
	end
	return true, clone(transformed)
end

-- Runs an atomic in-memory draft mutation and rejects callbacks that mutate the live session concurrently.
function Session:Mutate(callback: (draft: Data, session: Session<Data>) -> any): (boolean, any)
	assert(typeof(callback) == "function", "Mutate callback required")
	local mutable, mutableErr = self:_CanMutate()
	if not mutable then
		return false, mutableErr
	end
	local draft = clone(self.Data) :: Data
	local baseMutationId = self.MutationId
	local ok, result = pcall(callback, draft, self :: Session<Data>)
	if not ok then
		return false, tostring(result)
	end
	if self.MutationId ~= baseMutationId then
		return false, "CONCURRENT_MUTATION"
	end
	if result == false then
		return true, nil, "CANCELLED"
	end
	local before = self.Data
	local committed, commitErr = self:_CommitDraft(draft, nil, before, draft)
	if not committed then
		return false, commitErr
	end
	self.Store.Metrics.Transactions += 1
	return true, result
end

-- Applies multiple path changes as one validated mutation.
function Session:Patch(changes: {{Path: Path, Value: any}}): (boolean, string?)
	local mutable, mutableErr = self:_CanMutate()
	if not mutable then
		return false, mutableErr
	end
	if typeof(changes) ~= "table" then
		return false, "PATCH_TABLE_REQUIRED"
	end
	local draft = clone(self.Data)
	for _, patch in ipairs(changes) do
		if typeof(patch) ~= "table" or patch.Path == nil then
			return false, "INVALID_PATCH"
		end
		local ok, err = setAt(draft, patch.Path, clone(patch.Value))
		if not ok then
			return false, err
		end
	end
	local before = self.Data
	return self:_CommitDraft(draft, nil, before, draft)
end

function Session:Watch(path: Path?, callback)
	assert(typeof(callback) == "function", "Watch callback required")
	local normalized = path and normalizePath(path) or nil
	local key = pathKey(normalized)
	self.Watchers[key] = self.Watchers[key] or {}
	local bucket = self.Watchers[key]
	local id = HttpService:GenerateGUID(false)
	bucket[id] = callback
	local connection: any = {Connected = true}
	function connection:Disconnect()
		if not self.Connected then
			return
		end
		self.Connected = false
		bucket[id] = nil
	end
	return connection
end

function Session:Snapshot(label: string?): Snapshot<Data>
	local snapshot = {
		Id = HttpService:GenerateGUID(false),
		Label = label,
		CreatedAt = unix(),
		Data = clone(self.Data) :: Data,
		Revision = self.Revision,
	}
	table.insert(self.Snapshots, snapshot)
	while #self.Snapshots > self.Store.Config.MaxSnapshots do
		table.remove(self.Snapshots, 1)
	end
	return clone(snapshot) :: Snapshot<Data>
end

-- Restores a snapshot through the same active-session validation path as other mutations.
function Session:Restore(snapshot: Snapshot<Data>): (boolean, string?)
	local mutable, mutableErr = self:_CanMutate()
	if not mutable then
		return false, mutableErr
	end
	if typeof(snapshot) ~= "table" or typeof(snapshot.Data) ~= "table" then
		return false, "INVALID_SNAPSHOT"
	end
	local draft = clone(snapshot.Data) :: Data
	local valid, err = self.Store:Validate(draft)
	if not valid then
		return false, "SNAPSHOT_VALIDATION_FAILED:" .. tostring(err)
	end
	local before = self.Data
	local committed, commitErr = self:_CommitDraft(draft, nil, before, draft)
	if not committed then
		return false, commitErr
	end
	self.Store.Metrics.Rollbacks += 1
	return true
end

function Session:DiffFromPersisted(): {Change}
	local output: {Change} = {}
	diffValues(self.LastPersistedSnapshot, self.Data, {}, output, {})
	return output
end

function Session:SaveAsync(priority: SavePriority?): (boolean, string?)
	return self.Store:SaveAsync(self, priority)
end

function Session:ReleaseAsync(): (boolean, string?)
	return self.Store:ReleaseAsync(self)
end

function Session:GetStatus()
	return {
		Key = self.Key,
		SessionId = self.SessionId,
		Active = self.Active,
		Dirty = self.Dirty,
		Revision = self.Revision,
		SchemaVersion = self.SchemaVersion,
		Age = now() - self.OpenedAt,
		LastSaveAge = now() - self.LastSaveAt,
		Mutations = self.MutationId,
	}
end

function Session:GetStats()
	local valid, err = self.Store:Validate(self.Data)
	local state = {Nodes = 0, Bytes = 0, Seen = {}}
	validateSerializable(self.Data, state, "$", self.Store.Config.MaxDepth, self.Store.Config.MaxDataNodes, 0)
	return {
		Valid = valid,
		Error = err,
		Nodes = state.Nodes,
		EstimatedBytes = state.Bytes,
		Revision = self.Revision,
		Dirty = self.Dirty,
		Mutations = self.MutationId,
	}
end


-- Creates a v7 store, validates configuration and codec compatibility, and starts lifecycle/background handlers.
function NexusDataStore.new(config: StoreConfig<Data>): Store<Data>
	assert(typeof(config) == "table", "Configuration table required")
	assert(typeof(config.Name) == "string" and #config.Name > 0 and #config.Name <= 50, "Name must be 1-50 bytes")
	assert(typeof(config.Template) == "table", "Template must be a table")
	assert(config.Scope == nil or (typeof(config.Scope) == "string" and #config.Scope > 0 and #config.Scope <= 50), "Scope must be 1-50 bytes")
	assert(config.Schema == nil or typeof(config.Schema) == "table", "Schema must be a table")
	local schemaOK, schemaErr = validateSchemaDefinition(config.Schema)
	assert(schemaOK, "Invalid Schema: " .. tostring(schemaErr))
	assert(config.Migrations == nil or typeof(config.Migrations) == "table", "Migrations must be a table")
	if config.Migrations ~= nil then
		for version, migration in pairs(config.Migrations) do
			assert(safeInteger(version) and version >= 2, "Migration versions must be safe integers >= 2")
			assert(typeof(migration) == "function", "Migration entries must be functions")
		end
	end
	assert(config.CompressionOptions == nil or typeof(config.CompressionOptions) == "table", "CompressionOptions must be a table")
	assert(config.CompressionTransport == nil or config.CompressionTransport == "auto" or config.CompressionTransport == "buffer" or config.CompressionTransport == "base64", "CompressionTransport must be auto, buffer, or base64")
	assert(config.OrderedDataStores == nil or typeof(config.OrderedDataStores) == "table", "OrderedDataStores must be a table")
	assert(config.PlayerKey == nil or typeof(config.PlayerKey) == "function", "PlayerKey must be a function")
	assert(config.KeyPrefix == nil or typeof(config.KeyPrefix) == "string", "KeyPrefix must be a string")
	assert(config.CompressionModule == nil or (typeof(config.CompressionModule) == "Instance" and config.CompressionModule:IsA("ModuleScript")), "CompressionModule must be a ModuleScript")
	assert(config.SchemaVersion == nil or (safeInteger(config.SchemaVersion) and config.SchemaVersion >= 1), "SchemaVersion must be a positive safe integer")
	local self: any = setmetatable({}, NexusDataStore)
	local lockTimeout = configNumber(config.LockTimeout, 120, 45, "LockTimeout")
	local requestedHeartbeat = configNumber(config.HeartbeatInterval, math.floor(lockTimeout / 3), 5, "HeartbeatInterval")
	local heartbeatInterval = math.min(requestedHeartbeat, math.max(5, math.floor(lockTimeout / 2)))
	local retryBaseDelay = configNumber(config.RetryBaseDelay, 0.5, 0.05, "RetryBaseDelay")
	local retryMaxDelay = configNumber(config.RetryMaxDelay, 10, 0.5, "RetryMaxDelay")
	retryMaxDelay = math.max(retryBaseDelay, retryMaxDelay)

	local crossServerTopic = config.CrossServerTopic or ("NexusDataStore:v7:" .. config.Name)
	assert(typeof(crossServerTopic) == "string" and #crossServerTopic >= 1 and #crossServerTopic <= 80, "CrossServerTopic must be 1-80 bytes")

	self.Config = {
		Name = config.Name,
		Scope = config.Scope or "Global",
		Template = clone(config.Template) :: Data,
		Schema = config.Schema,
		SchemaVersion = config.SchemaVersion or 1,
		Migrations = config.Migrations or {},
		Strict = config.Strict == true,
		Reconcile = config.Reconcile ~= false,
		EnforceTemplateTypes = config.EnforceTemplateTypes ~= false,
		ValidateOnWrite = config.ValidateOnWrite ~= false,
		DetectDirectChanges = config.DetectDirectChanges ~= false,
		Compression = config.Compression ~= false,
		CompressionModule = config.CompressionModule,
		CompressionOptions = clone(config.CompressionOptions or {}),
		CompressionReports = config.CompressionReports == true,
		CompressionTransport = config.CompressionTransport or "auto",
		AutoSave = config.AutoSave ~= false,
		AutoSaveInterval = configNumber(config.AutoSaveInterval, 30, 10, "AutoSaveInterval"),
		LockTimeout = lockTimeout,
		HeartbeatInterval = heartbeatInterval,
		RetryAttempts = configNumber(config.RetryAttempts, 6, 1, "RetryAttempts", true),
		RetryBaseDelay = retryBaseDelay,
		RetryMaxDelay = retryMaxDelay,
		BudgetAware = config.BudgetAware ~= false,
		BudgetWaitTimeout = configNumber(config.BudgetWaitTimeout, 10, 1, "BudgetWaitTimeout"),
		MinimumSaveInterval = configNumber(config.MinimumSaveInterval, 3, 0, "MinimumSaveInterval"),
		LoadTimeout = configNumber(config.LoadTimeout, 30, 5, "LoadTimeout"),
		SaveTimeout = configNumber(config.SaveTimeout, 30, 5, "SaveTimeout"),
		MaxDataNodes = configNumber(config.MaxDataNodes, 50000, 100, "MaxDataNodes", true),
		MaxDataBytes = configNumber(config.MaxDataBytes, 3900000, 1000, "MaxDataBytes", true),
		MaxStoredBytes = configNumber(config.MaxStoredBytes, 3900000, 1000, "MaxStoredBytes", true, 3900000),
		MaxDepth = configNumber(config.MaxDepth, 64, 8, "MaxDepth", true),
		MaxSnapshots = configNumber(config.MaxSnapshots, 10, 1, "MaxSnapshots", true),
		KeyPrefix = config.KeyPrefix or "",
		PlayerKey = config.PlayerKey,
		AutoPlayerLifecycle = config.AutoPlayerLifecycle == true,
		EnableCrossServerEvents = config.EnableCrossServerEvents == true,
		CrossServerTopic = crossServerTopic,
		OrderedDataStores = config.OrderedDataStores or {},
		Debug = config.Debug == true,
	}
	if self.Config.CompressionOptions.MaxDepth == nil then
		self.Config.CompressionOptions.MaxDepth = self.Config.MaxDepth + 8
	end
	if self.Config.CompressionOptions.MaxNodes == nil then
		-- Codec nodes include map keys as well as values.
		self.Config.CompressionOptions.MaxNodes = self.Config.MaxDataNodes * 2 + 4096
	end
	if not self.Config.Compression then
		self.Config.MaxDataBytes = math.min(self.Config.MaxDataBytes, self.Config.MaxStoredBytes)
	end
	self.Template = clone(config.Template) :: Data
	self.Schema = config.Schema and clone(config.Schema) or nil
	self.SchemaVersion = self.Config.SchemaVersion
	self.DataStore = DataStoreService:GetDataStore(self.Config.Name, self.Config.Scope)
	self.JobId = game.JobId ~= "" and game.JobId or HttpService:GenerateGUID(false)
	self.Sessions = {}
	self.SessionById = {}
	self.SessionByPlayer = {}
	self.OpenLocks = {}
	self.Events = {}
	self.OrderedStores = {}
	self.Closed = false
	self.Closing = false
	self.LifecycleAttached = false
	self.BoundToClose = false
	self.Metrics = {
		Opened = 0,
		Released = 0,
		LoadsFailed = 0,
		Saved = 0,
		SaveFailed = 0,
		Retries = 0,
		Mutations = 0,
		Transactions = 0,
		Rollbacks = 0,
		Heartbeats = 0,
		SessionLost = 0,
		TypeErrors = 0,
		DirectChanges = 0,
		BytesEncoded = 0,
		LoadTime = 0,
		SaveTime = 0,
		OrderedReads = 0,
		OrderedReadFailed = 0,
		OrderedWrites = 0,
		OrderedWriteFailed = 0,
		OrderedUpdates = 0,
		OrderedNoops = 0,
		OrderedRemoves = 0,
		OrderedSyncs = 0,
		OrderedSyncFailed = 0,
		CrossServerPublishFailed = 0,
	}

	local compressionEngine, compressionError = compressionResolve(config.CompressionModule)
	self.CompressionEngine = compressionEngine
	self.CompressionEngineError = compressionError
	local versionOK, compressionVersion = true, nil
	if compressionEngine then
		versionOK, compressionVersion = pcall(compressionEngine.Version)
	end
	self.CompressionEngineVersion = versionOK and compressionVersion ~= nil and tostring(compressionVersion) or nil
	if self.Config.Compression then
		assert(compressionEngine ~= nil, "NexusDataStore v7 compression is enabled but Compression v2.3.x (codec 230) could not be loaded: " .. tostring(compressionError))
	end

	-- Cache the JSON overhead for the compressed envelope once. Base64 payload
	-- characters are JSON-safe, so persisted size is base + #Payload exactly.
	local envelopeProbe = {
		Format = RECORD_FORMAT,
		Codec = compressionEngine and (tonumber(compressionEngine.CodecVersion) or 230) or 230,
		Compressed = true,
		Encoding = "base64",
		Payload = "",
	}
	local envelopeBaseBytes, envelopeBaseErr = self:_MeasureStoredValue(envelopeProbe)
	assert(envelopeBaseBytes ~= nil, "Failed to measure compression envelope: " .. tostring(envelopeBaseErr))
	self.CompressedEnvelopeBaseBytes = envelopeBaseBytes

	for alias, orderedConfig in pairs(self.Config.OrderedDataStores) do
		self.OrderedStores[alias] = OrderedStore.new(self, alias, orderedConfig)
	end

	local templateOK, templateErr = self:Validate(self.Template)
	assert(templateOK, "Invalid NexusDataStore v7 template: " .. tostring(templateErr))
	if self.Config.Compression then
		local codecOK, codecErr = pcall(self.CompressionEngine.CompressTablePacket, self:_BuildNewRecord(clone(self.Template)), self.Config.CompressionOptions)
		assert(codecOK, "Invalid Compression v2.3.x configuration or template: " .. tostring(codecErr))
	end

	if self.Config.EnableCrossServerEvents then
		local ok, subscription = pcall(MessagingService.SubscribeAsync, MessagingService, self.Config.CrossServerTopic, function(message)
			local packet = message.Data
			if typeof(packet) == "table"
				and packet.JobId ~= self.JobId
				and typeof(packet.Event) == "string"
				and #packet.Event > 0 then
				self:_Fire("CrossServerEvent", packet.Event, packet.Payload, packet)
			end
		end)
		if ok then
			self.CrossServerSubscription = subscription
		else
			self:_Fire("CrossServerError", tostring(subscription))
		end
	end

	self:_BackgroundLoop()
	if self.Config.AutoPlayerLifecycle then
		self:AttachPlayerLifecycle()
	end
	return self :: Store<Data>
end

NexusDataStore.OrderedDataStore = table.freeze({
	Class = OrderedStore,
	Modes = table.freeze({Set = "set", Max = "max", Min = "min"}),
})

NexusDataStore.Compression = table.freeze({
	RequiredVersion = REQUIRED_COMPRESSION_VERSION,
	CompatibleSeries = "2.3.x",
	CodecVersion = 230,
	RecordFormat = RECORD_FORMAT,
})

return NexusDataStore :: NexusDataStoreModule
