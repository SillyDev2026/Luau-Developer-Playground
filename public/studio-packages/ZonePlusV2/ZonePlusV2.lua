--!native
--!optimize 2

--[[
    ZonePlusNext v1.2.2
    A dependency-free zone system for Roblox.

    Goals:
      * One shared scheduler for every zone.
      * Shared player spatial hash broad phase.
      * Spatial / temporal / semantic / predictive query engine.
      * Bounded transition history + optional position rewind history.
      * Cached zone world bounds with dirty invalidation.
      * Deterministic cleanup.
      * Dynamic zone containers.
      * Strong public configuration.
      * Stable enter/exit handling near borders.
      * Players + arbitrary tracked items.
      * Priority, tags, stats, and compound query builder.
      * No dependency on Touched events.
      * No dependency on Workspace spatial queries for center detection.

    Notes:
      * Block, Ball, and Cylinder Parts receive shape-aware point checks.
      * WedgePart, CornerWedgePart, MeshPart, UnionOperation, etc. use their
        oriented bounding box for point checks in v0.6.0.
      * "Bounds" uses exact OBB intersection for box-like zone parts, with
        shape-aware sampling fallback for Ball and Cylinder Parts.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local VERSION = "1.2.2"
local DEFAULT_INTERVAL = 0.10
local MIN_INTERVAL = 1 / 240
local EPSILON = 1e-6
local DEFAULT_SPATIAL_CELL_SIZE = 64
local DEFAULT_MAX_QUERY_CELLS = 2048
local DEFAULT_MAX_PLAYER_CELLS = 128
local DEFAULT_BRUTE_FORCE_THRESHOLD = 24

local DEFAULT_ZONE_INDEX_CELL_SIZE = 128
local DEFAULT_ZONE_INDEX_MAX_QUERY_CELLS = 4096
local DEFAULT_ZONE_INDEX_MAX_ZONE_CELLS = 256
local DEFAULT_ZONE_INDEX_BRUTE_FORCE_THRESHOLD = 64

export type DetectionMode = "Center" | "Bounds" | "AnyPart" | "WholeCharacter"

export type SpatialConfig = {
	Enabled: boolean?,
	CellSize: number?,
	MaxQueryCells: number?,
	MaxPlayerCells: number?,
	BruteForceThreshold: number?,
}

export type ZoneIndexConfig = {
	Enabled: boolean?,
	CellSize: number?,
	MaxQueryCells: number?,
	MaxZoneCells: number?,
	BruteForceThreshold: number?,
}

export type IndexMode = "Auto" | "Static" | "Dynamic"

export type SchedulerConfig = {
	ActiveOnly: boolean?,
	FrameBudgetMs: number?,
	MaxStepsPerFrame: number?,
}

export type SchedulerStats = {
	Ticks: number,
	FrameBudgetMs: number,
	MaxStepsPerFrame: number,
	Steps: number,
	CandidateZones: number,
	SkippedZones: number,
	DeferredZones: number,
	BudgetHits: number,
	StepLimitHits: number,
	BudgetOverruns: number,
	LastFrameSeconds: number,
	PeakFrameSeconds: number,
	LastCandidateSeconds: number,
	PeakCandidateSeconds: number,
	LastWorkSeconds: number,
	PeakWorkSeconds: number,
}


export type QueryPrecision = "Broad" | "Bounds" | "Exact"

export type HistoryConfig = {
	Position: boolean?,
	Duration: number?,
	SampleRate: number?,
	TransitionLimit: number?,
}

export type TransitionRecord = {
	Time: number,
	Inside: boolean,
	Position: Vector3?,
	Velocity: Vector3?,
	Direction: Vector3?,
	Speed: number,
	Side: string?,
}

export type PositionSample = {
	Time: number,
	Position: Vector3,
	Velocity: Vector3,
}

export type ZoneQueryOptions = {
	RequireTags: {string}?,
	ExcludeTags: {string}?,
	MinPriority: number?,
	MaxPriority: number?,
	MinOccupancy: number?,
	MaxOccupancy: number?,
	Full: boolean?,
	Enabled: boolean?,
	Limit: number?,
	Precision: QueryPrecision?,
}

export type VisibilityOptions = {
	IgnoreInstances: {Instance}?,
	MaxDistance: number?,
}

export type PredictionResult = {
	WillEnter: boolean,
	Time: number?,
	Position: Vector3?,
	Velocity: Vector3,
}

export type QueryStats = {
	Executions: number,
	Candidates: number,
	Results: number,
	VisibilityRays: number,
	ExactOverlapQueries: number,
	PredictionSamples: number,
	PositionSamples: number,
	ZoneIndexQueries: number,
	ZoneIndexFallbacks: number,
	ZoneCellsVisited: number,
}

export type ZoneOptions = {
	Name: string?,
	UpdateInterval: number?,
	Detection: DetectionMode?,
	Padding: number | Vector3?,
	EnterDelay: number?,
	ExitDelay: number?,
	Priority: number?,
	Capacity: number?,
	TrackPlayers: boolean?,
	AutoDestroyWithContainer: boolean?,
	PlayerFilter: ((Player) -> boolean)?,
	Tags: {string}?,
	BroadPhase: boolean?,
	HistoryLimit: number?,
	IndexMode: IndexMode?,
}

export type ZoneInfo = {
	Name: string,
	Enabled: boolean,
	Priority: number,
	Occupancy: number,
	Capacity: number?,
	Full: boolean,
	Tags: {string},
	PartCount: number,
}

export type PlayerZoneState = {
	Inside: boolean,
	Pending: boolean,
	PendingInside: boolean?,
	PendingSeconds: number,
	EntryTime: number?,
	ExitTime: number?,
	TimeInside: number,
}

export type ItemZoneState = {
	Tracked: boolean,
	Inside: boolean,
	Pending: boolean,
	PendingInside: boolean?,
	PendingSeconds: number,
}

export type ZoneStats = {
	Checks: number,
	Hits: number,
	Misses: number,
	Enters: number,
	Exits: number,
	Errors: number,
	BroadPhaseQueries: number,
	BroadPhaseFallbacks: number,
	CandidatePlayers: number,
	PrecisePlayerChecks: number,
	CellsVisited: number,
	LastCheckSeconds: number,
	TotalCheckSeconds: number,
}

export type GlobalStats = {
	Version: string,
	Zones: number,
	EnabledZones: number,
	ActivePlayerMemberships: number,
	TrackedItems: number,
	SchedulerTicks: number,
	Checks: number,
	Errors: number,
	BroadPhaseQueries: number,
	BroadPhaseFallbacks: number,
	CandidatePlayers: number,
	PrecisePlayerChecks: number,
	CellsVisited: number,
	SpatialRebuilds: number,
	SpatialBuckets: number,
	IndexedPlayers: number,
	ZoneIndexRebuilds: number,
	ZoneIndexBuckets: number,
	IndexedZones: number,
	OversizedZones: number,
	StaticIndexNodes: number,
	StaticIndexedZones: number,
	DynamicIndexedZones: number,
	AutoPromotions: number,
	SchedulerCandidateZones: number,
	SchedulerSkippedZones: number,
	SchedulerSteps: number,
	SchedulerDeferredZones: number,
	SchedulerBudgetHits: number,
	SchedulerStepLimitHits: number,
	SchedulerBudgetOverruns: number,
	SchedulerLastFrameSeconds: number,
	SchedulerPeakFrameSeconds: number,
	TotalCheckSeconds: number,
}

type SignalConnection = {
	Connected: boolean,
	Disconnect: (self: SignalConnection) -> (),
}

type SignalObject = {
	Connect: (self: SignalObject, callback: (...any) -> ()) -> SignalConnection,
	Once: (self: SignalObject, callback: (...any) -> ()) -> SignalConnection,
	Wait: (self: SignalObject) -> ...any,
	Fire: (self: SignalObject, ...any) -> (),
	Destroy: (self: SignalObject) -> (),
}


type SignalHandler = {
	callback: (...any) -> (),
	connected: boolean,
	once: boolean,
	connection: SignalConnection?,
}

type SignalDispatchEntry = {
	callback: (...any) -> (),
	args: any,
}

type CandidateState = {
	inside: boolean,
	pendingInside: boolean?,
	pendingSince: number?,
	lastSeen: number,
}

type TrackedItem = {
	instance: Instance,
	state: CandidateState,
}

type AnyZone = any

local function newSignal(): SignalObject
	local handlers: {[number]: SignalHandler} = {}
	local nextId = 0
	local destroyed = false

	local signal = {} :: any

	local function connect(callback: (...any) -> (), once: boolean): SignalConnection
		assert(type(callback) == "function", "Signal callback must be a function")
		assert(not destroyed, "Cannot connect to a destroyed signal")

		nextId += 1
		local id = nextId
		local handler: SignalHandler = {
			callback = callback,
			connected = true,
			once = once,
			connection = nil,
		}
		handlers[id] = handler

		local connection = {
			Connected = true,
		} :: any

		function connection:Disconnect()
			if not connection.Connected then
				return
			end

			connection.Connected = false
			handler.connected = false
			handlers[id] = nil
		end

		handler.connection = connection
		return connection
	end

	function signal:Connect(callback: (...any) -> ()): SignalConnection
		return connect(callback, false)
	end

	function signal:Once(callback: (...any) -> ()): SignalConnection
		return connect(callback, true)
	end

	function signal:Wait(): ...any
		assert(not destroyed, "Cannot wait on a destroyed signal")

		local thread = coroutine.running()
		self:Once(function(...)
			task.spawn(thread, ...)
		end)

		return coroutine.yield()
	end

	function signal:Fire(...)
		if destroyed then
			return
		end

		local arguments = table.pack(...)
		local dispatch: {SignalDispatchEntry} = {}

		for id, handler in pairs(handlers) do
			if not handler.connected then
				handlers[id] = nil
				continue
			end

			if handler.once then
				handler.connected = false
				handlers[id] = nil
				if handler.connection then
					handler.connection.Connected = false
				end
			end

			table.insert(dispatch, {
				callback = handler.callback,
				args = arguments,
			})
		end

		for _, entry in ipairs(dispatch) do
			task.spawn(function()
				entry.callback(table.unpack(entry.args, 1, entry.args.n))
			end)
		end
	end

	function signal:Destroy()
		if destroyed then
			return
		end

		destroyed = true
		for _, handler in pairs(handlers) do
			handler.connected = false
			if handler.connection then
				handler.connection.Connected = false
			end
		end
		table.clear(handlers)
	end

	return signal
end

local function shallowCopy<T>(source: {T}): {T}
	local result = table.create(#source)
	for index, value in ipairs(source) do
		result[index] = value
	end
	return result
end

local function isFiniteNumber(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

local function requireFiniteNumber(value: number, name: string): number
	assert(type(value) == "number" and isFiniteNumber(value), name .. " must be a finite number")
	return value
end

local function requireNonNegativeFinite(value: number, name: string): number
	requireFiniteNumber(value, name)
	assert(value >= 0, name .. " must be greater than or equal to zero")
	return value
end

local function clampInterval(value: number?): number
	if value == nil then
		return DEFAULT_INTERVAL
	end

	requireFiniteNumber(value, "UpdateInterval")
	return math.max(MIN_INTERVAL, value)
end

local function paddingToVector(value: number | Vector3?): Vector3
	if value == nil then
		return Vector3.zero
	end

	if type(value) == "number" then
		requireFiniteNumber(value, "Padding")
		return Vector3.new(value, value, value)
	end

	assert(typeof(value) == "Vector3", "Padding must be a number or Vector3")
	return value
end

local function isFiniteVector3(value: Vector3): boolean
	return
		value.X == value.X and value.Y == value.Y and value.Z == value.Z
		and math.abs(value.X) < math.huge
		and math.abs(value.Y) < math.huge
		and math.abs(value.Z) < math.huge
end

local function isBasePart(instance: Instance?): boolean
	return instance ~= nil and instance:IsA("BasePart")
end

local function isSupportedContainer(container: any): boolean
	if typeof(container) == "Instance" then
		return true
	end

	if type(container) == "table" then
		return true
	end

	return false
end

local function pointInsideBlock(part: BasePart, worldPoint: Vector3, padding: Vector3): boolean
	local localPoint = part.CFrame:PointToObjectSpace(worldPoint)
	local half = part.Size * 0.5 + padding

	return
		math.abs(localPoint.X) <= half.X + EPSILON
		and math.abs(localPoint.Y) <= half.Y + EPSILON
		and math.abs(localPoint.Z) <= half.Z + EPSILON
end

local function pointInsideBall(part: BasePart, worldPoint: Vector3, padding: Vector3): boolean
	local localPoint = part.CFrame:PointToObjectSpace(worldPoint)
	local radius = part.Size * 0.5 + padding

	if radius.X <= 0 or radius.Y <= 0 or radius.Z <= 0 then
		return false
	end

	local nx = localPoint.X / radius.X
	local ny = localPoint.Y / radius.Y
	local nz = localPoint.Z / radius.Z

	return nx * nx + ny * ny + nz * nz <= 1 + EPSILON
end

local function pointInsideCylinder(part: BasePart, worldPoint: Vector3, padding: Vector3): boolean
	local localPoint = part.CFrame:PointToObjectSpace(worldPoint)
	local half = part.Size * 0.5 + padding

	if half.X <= 0 or half.Y <= 0 or half.Z <= 0 then
		return false
	end

	if math.abs(localPoint.X) > half.X + EPSILON then
		return false
	end

	local ny = localPoint.Y / half.Y
	local nz = localPoint.Z / half.Z
	return ny * ny + nz * nz <= 1 + EPSILON
end

local function pointInsidePart(part: BasePart, worldPoint: Vector3, padding: Vector3): boolean
	if part:IsA("Part") then
		if part.Shape == Enum.PartType.Ball then
			return pointInsideBall(part, worldPoint, padding)
		elseif part.Shape == Enum.PartType.Cylinder then
			return pointInsideCylinder(part, worldPoint, padding)
		end
	end

	return pointInsideBlock(part, worldPoint, padding)
end

local function getModelPosition(model: Model): Vector3
	return model:GetPivot().Position
end

local function getItemPosition(instance: Instance): Vector3?
	if instance:IsA("BasePart") then
		return instance.Position
	end

	if instance:IsA("Attachment") then
		return instance.WorldPosition
	end

	if instance:IsA("Model") then
		return getModelPosition(instance)
	end

	return nil
end

local function getCharacterRoot(character: Model?): BasePart?
	if character == nil then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end

	local primary = character.PrimaryPart
	if primary then
		return primary
	end

	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if torso and torso:IsA("BasePart") then
		return torso
	end

	return nil
end

local function getBoxSamples(cframe: CFrame, size: Vector3): {Vector3}
	local half = size * 0.5
	local samples = table.create(9)

	samples[1] = cframe.Position

	local index = 2
	for x = -1, 1, 2 do
		for y = -1, 1, 2 do
			for z = -1, 1, 2 do
				local offset = Vector3.new(half.X * x, half.Y * y, half.Z * z)
				samples[index] = cframe:PointToWorldSpace(offset)
				index += 1
			end
		end
	end

	return samples
end

local function pointInsideOrientedBox(cframe: CFrame, size: Vector3, worldPoint: Vector3): boolean
	local p = cframe:PointToObjectSpace(worldPoint)
	local half = size * 0.5
	return
		math.abs(p.X) <= half.X + EPSILON
		and math.abs(p.Y) <= half.Y + EPSILON
		and math.abs(p.Z) <= half.Z + EPSILON
end

local function orientedBoxWorldAABB(cframe: CFrame, size: Vector3): (Vector3, Vector3)
	local half = size * 0.5
	local right = cframe.RightVector
	local up = cframe.UpVector
	local look = cframe.LookVector

	local extent = Vector3.new(
		math.abs(right.X) * half.X + math.abs(up.X) * half.Y + math.abs(look.X) * half.Z,
		math.abs(right.Y) * half.X + math.abs(up.Y) * half.Y + math.abs(look.Y) * half.Z,
		math.abs(right.Z) * half.X + math.abs(up.Z) * half.Y + math.abs(look.Z) * half.Z
	)

	return cframe.Position - extent, cframe.Position + extent
end

local function cellCoordinate(value: number, cellSize: number): number
	return math.floor(value / cellSize)
end

local function cellKey(x: number, y: number, z: number): string
	return tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
end

local function getCellRange(minimum: Vector3, maximum: Vector3, cellSize: number): (number, number, number, number, number, number)
	return
		cellCoordinate(minimum.X, cellSize),
		cellCoordinate(maximum.X, cellSize),
		cellCoordinate(minimum.Y, cellSize),
		cellCoordinate(maximum.Y, cellSize),
		cellCoordinate(minimum.Z, cellSize),
		cellCoordinate(maximum.Z, cellSize)
end

local function getCellCount(x0: number, x1: number, y0: number, y1: number, z0: number, z1: number): number
	return (x1 - x0 + 1) * (y1 - y0 + 1) * (z1 - z0 + 1)
end

local function isBoxLikeZonePart(part: BasePart): boolean
	if part:IsA("Part") then
		return part.Shape == Enum.PartType.Block
	end

	-- Complex BaseParts use their OBB as the documented v0.3 fallback.
	return not part:IsA("Part")
end

local function obbIntersects(aCF: CFrame, aSize: Vector3, bCF: CFrame, bSize: Vector3): boolean
	-- Separating Axis Theorem for two oriented boxes (15 candidate axes).
	local a = {aCF.RightVector, aCF.UpVector, -aCF.LookVector}
	local b = {bCF.RightVector, bCF.UpVector, -bCF.LookVector}
	local ah = aSize * 0.5
	local bh = bSize * 0.5
	local ae = {ah.X, ah.Y, ah.Z}
	local be = {bh.X, bh.Y, bh.Z}

	local r = table.create(3)
	local ar = table.create(3)
	for i = 1, 3 do
		r[i] = table.create(3)
		ar[i] = table.create(3)
		for j = 1, 3 do
			local dot = a[i]:Dot(b[j])
			r[i][j] = dot
			ar[i][j] = math.abs(dot) + 1e-7
		end
	end

	local translation = bCF.Position - aCF.Position
	local t = {
		translation:Dot(a[1]),
		translation:Dot(a[2]),
		translation:Dot(a[3]),
	}

	for i = 1, 3 do
		local ra = ae[i]
		local rb = be[1] * ar[i][1] + be[2] * ar[i][2] + be[3] * ar[i][3]
		if math.abs(t[i]) > ra + rb then
			return false
		end
	end

	for j = 1, 3 do
		local ra = ae[1] * ar[1][j] + ae[2] * ar[2][j] + ae[3] * ar[3][j]
		local rb = be[j]
		local projected = math.abs(t[1] * r[1][j] + t[2] * r[2][j] + t[3] * r[3][j])
		if projected > ra + rb then
			return false
		end
	end

	for i = 1, 3 do
		local i1 = (i % 3) + 1
		local i2 = ((i + 1) % 3) + 1

		for j = 1, 3 do
			local j1 = (j % 3) + 1
			local j2 = ((j + 1) % 3) + 1

			local ra = ae[i1] * ar[i2][j] + ae[i2] * ar[i1][j]
			local rb = be[j1] * ar[i][j2] + be[j2] * ar[i][j1]
			local projected = math.abs(t[i2] * r[i1][j] - t[i1] * r[i2][j])

			if projected > ra + rb then
				return false
			end
		end
	end

	return true
end

local function isCharacterBodyPart(part: BasePart, character: Model): boolean
	local ancestor = part.Parent

	while ancestor and ancestor ~= character do
		if ancestor:IsA("Accessory") or ancestor:IsA("Tool") then
			return false
		end
		ancestor = ancestor.Parent
	end

	return ancestor == character
end

local ZonePlusNext = {}
ZonePlusNext.__index = ZonePlusNext

local zones: {[AnyZone]: boolean} = {}
local zoneList: {AnyZone} = {}
local zoneNameIndex: {[string]: {AnyZone}} = {}
local zoneTagIndex: {[string]: {AnyZone}} = {}
local playerMemberships: {[Player]: {[AnyZone]: boolean}} = {}

local zoneIndexEnabled = true
local zoneIndexCellSize = DEFAULT_ZONE_INDEX_CELL_SIZE
local zoneIndexMaxQueryCells = DEFAULT_ZONE_INDEX_MAX_QUERY_CELLS
local zoneIndexMaxZoneCells = DEFAULT_ZONE_INDEX_MAX_ZONE_CELLS
local zoneIndexBruteForceThreshold = DEFAULT_ZONE_INDEX_BRUTE_FORCE_THRESHOLD

-- v1 custom hybrid index:
--   * static/auto-still zones -> Morton-ordered packed AABB tree
--   * dynamic/auto-promoted zones -> incrementally updated loose grid
local staticTreeDirty = true
local staticTreeRoot = 0
local staticNodeMin: {Vector3} = {}
local staticNodeMax: {Vector3} = {}
local staticNodeLeft: {number} = {}
local staticNodeRight: {number} = {}
local staticNodeZone: {AnyZone?} = {}
local staticNodeCount = 0
local staticIndexedZones = 0

local dynamicBuckets: {[string]: {[AnyZone]: boolean}} = {}
local dynamicZoneKeys: {[AnyZone]: {string}} = {}
local dynamicOversizedZones: {[AnyZone]: boolean} = {}
local dynamicIndexedSet: {[AnyZone]: boolean} = {}
local dynamicDirtyZones: {[AnyZone]: boolean} = {}
local dynamicBucketCount = 0
local dynamicIndexedZones = 0

local zoneIndexRebuilds = 0
local zoneIndexAutoPromotions = 0

local schedulerConnection: RBXScriptConnection? = nil
local schedulerActiveOnly = true
local schedulerFrameBudgetSeconds = 0.001
local schedulerMaxStepsPerFrame = 0
local schedulerRoundRobinCursor = 0
local schedulerAlwaysZones: {[AnyZone]: boolean} = {}
local schedulerCandidateZones = 0
local schedulerSkippedZones = 0
local schedulerSteps = 0
local schedulerDeferredZones = 0
local schedulerBudgetHits = 0
local schedulerStepLimitHits = 0
local schedulerBudgetOverruns = 0
local schedulerLastFrameSeconds = 0
local schedulerPeakFrameSeconds = 0
local schedulerLastCandidateSeconds = 0
local schedulerPeakCandidateSeconds = 0
local schedulerLastWorkSeconds = 0
local schedulerPeakWorkSeconds = 0

local registryBatchDepth = 0
local registryDirty = false
local schedulerTicks = 0
local globalChecks = 0
local globalCheckSeconds = 0
local globalErrors = 0
local globalBroadPhaseQueries = 0
local globalBroadPhaseFallbacks = 0
local globalCandidatePlayers = 0
local globalPrecisePlayerChecks = 0
local globalCellsVisited = 0
local spatialRebuilds = 0

local spatialEnabled = true
local spatialCellSize = DEFAULT_SPATIAL_CELL_SIZE
local spatialMaxQueryCells = DEFAULT_MAX_QUERY_CELLS
local spatialMaxPlayerCells = DEFAULT_MAX_PLAYER_CELLS
local spatialBruteForceThreshold = DEFAULT_BRUTE_FORCE_THRESHOLD
local playerBuckets: {[string]: {Player}} = {}
local oversizedPlayers: {Player} = {}
local playerBoundsMin: {[Player]: Vector3} = {}
local playerBoundsMax: {[Player]: Vector3} = {}
local spatialIndexedPlayers = 0
local spatialBucketCount = 0
local spatialIndexValid = false
local spatialConfigRevision = 0


local DEFAULT_TRANSITION_HISTORY_LIMIT = 64
local DEFAULT_POSITION_HISTORY_DURATION = 3
local DEFAULT_POSITION_HISTORY_SAMPLE_RATE = 20

local positionHistoryEnabled = false
local positionHistoryDuration = DEFAULT_POSITION_HISTORY_DURATION
local positionHistorySampleRate = DEFAULT_POSITION_HISTORY_SAMPLE_RATE
local globalTransitionHistoryLimit = DEFAULT_TRANSITION_HISTORY_LIMIT
local positionHistory: {[Player]: {PositionSample}} = {}
local positionHistoryConnection: RBXScriptConnection? = nil
local positionHistoryAccumulator = 0

local queryExecutions = 0
local queryCandidates = 0
local queryResults = 0
local queryVisibilityRays = 0
local queryExactOverlapQueries = 0
local queryPredictionSamples = 0
local queryPositionSamples = 0
local queryZoneIndexQueries = 0
local queryZoneIndexFallbacks = 0
local queryZoneCellsVisited = 0

local function getRootSnapshot(player: Player): (Vector3?, Vector3?)
	local root = getCharacterRoot(player.Character)
	if root == nil then
		return nil, nil
	end
	return root.Position, root.AssemblyLinearVelocity
end

local function trimPositionSamples(samples: {PositionSample}, now: number)
	local cutoff = now - positionHistoryDuration
	local removeCount = 0
	for index, sample in ipairs(samples) do
		if sample.Time < cutoff then
			removeCount = index
		else
			break
		end
	end
	if removeCount > 0 then
		for _ = 1, removeCount do
			table.remove(samples, 1)
		end
	end
end

local function samplePlayerPositions()
	if not positionHistoryEnabled then
		return
	end

	local now = os.clock()
	local seen: {[Player]: boolean} = {}

	for _, player in ipairs(Players:GetPlayers()) do
		local position, velocity = getRootSnapshot(player)
		if position == nil or velocity == nil then
			continue
		end

		seen[player] = true
		local samples = positionHistory[player]
		if samples == nil then
			samples = {}
			positionHistory[player] = samples
		end

		table.insert(samples, {
			Time = now,
			Position = position,
			Velocity = velocity,
		})
		queryPositionSamples += 1
		trimPositionSamples(samples, now)
	end

	for player in pairs(positionHistory) do
		if not seen[player] and player.Parent ~= Players then
			positionHistory[player] = nil
		end
	end
end

local function updatePositionSamplerConnection()
	if positionHistoryEnabled then
		if positionHistoryConnection ~= nil then
			return
		end

		positionHistoryAccumulator = 0
		positionHistoryConnection = RunService.Heartbeat:Connect(function(dt)
			positionHistoryAccumulator += dt
			local interval = 1 / positionHistorySampleRate
			if positionHistoryAccumulator + EPSILON < interval then
				return
			end
			positionHistoryAccumulator = positionHistoryAccumulator % interval
			samplePlayerPositions()
		end)
	else
		if positionHistoryConnection then
			positionHistoryConnection:Disconnect()
			positionHistoryConnection = nil
		end
		positionHistoryAccumulator = 0
		table.clear(positionHistory)
	end
end

local function latestPositionSample(player: Player): PositionSample?
	local samples = positionHistory[player]
	if samples == nil or #samples == 0 then
		return nil
	end
	return samples[#samples]
end

local function sideFromPoint(boundsCF: CFrame?, boundsSize: Vector3?, position: Vector3): string?
	if boundsCF == nil or boundsSize == nil then
		return nil
	end

	local localPoint = boundsCF:PointToObjectSpace(position)
	local half = boundsSize * 0.5
	local nx = if half.X > EPSILON then localPoint.X / half.X else 0
	local ny = if half.Y > EPSILON then localPoint.Y / half.Y else 0
	local nz = if half.Z > EPSILON then localPoint.Z / half.Z else 0

	local ax, ay, az = math.abs(nx), math.abs(ny), math.abs(nz)
	if ax >= ay and ax >= az then
		return if nx >= 0 then "East" else "West"
	elseif ay >= ax and ay >= az then
		return if ny >= 0 then "Top" else "Bottom"
	else
		return if nz >= 0 then "South" else "North"
	end
end

local function pointAABBDistanceSquared(point: Vector3, minimum: Vector3, maximum: Vector3): number
	local dx = math.max(minimum.X - point.X, 0, point.X - maximum.X)
	local dy = math.max(minimum.Y - point.Y, 0, point.Y - maximum.Y)
	local dz = math.max(minimum.Z - point.Z, 0, point.Z - maximum.Z)
	return dx * dx + dy * dy + dz * dz
end

local function aabbIntersects(aMin: Vector3, aMax: Vector3, bMin: Vector3, bMax: Vector3): boolean
	return
		aMin.X <= bMax.X and aMax.X >= bMin.X
		and aMin.Y <= bMax.Y and aMax.Y >= bMin.Y
		and aMin.Z <= bMax.Z and aMax.Z >= bMin.Z
end

local function rayAABB(origin: Vector3, direction: Vector3, minimum: Vector3, maximum: Vector3): number?
	local tmin = 0
	local tmax = 1

	local function axis(o: number, d: number, mn: number, mx: number): boolean
		if math.abs(d) <= EPSILON then
			return o >= mn and o <= mx
		end

		local inv = 1 / d
		local t1 = (mn - o) * inv
		local t2 = (mx - o) * inv
		if t1 > t2 then
			t1, t2 = t2, t1
		end
		tmin = math.max(tmin, t1)
		tmax = math.min(tmax, t2)
		return tmin <= tmax
	end

	if not axis(origin.X, direction.X, minimum.X, maximum.X) then return nil end
	if not axis(origin.Y, direction.Y, minimum.Y, maximum.Y) then return nil end
	if not axis(origin.Z, direction.Z, minimum.Z, maximum.Z) then return nil end

	return tmin
end

-- Segment intersection against a part's oriented bounds, expressed in local space.
-- Unlike a world AABB, this avoids false positives near rotated thin zones.
local function rayOrientedBox(origin: Vector3, direction: Vector3, cframe: CFrame, size: Vector3): number?
    local localOrigin = cframe:PointToObjectSpace(origin)
    local localDirection = cframe:VectorToObjectSpace(direction)
    local half = size * 0.5
    return rayAABB(localOrigin, localDirection, -half, half)
end

local function appendBounded<T>(array: {T}, value: T, limit: number)
	table.insert(array, value)
	local overflow = #array - limit
	if overflow > 0 then
		for _ = 1, overflow do
			table.remove(array, 1)
		end
	end
end

local function invalidateSpatialIndex()
	spatialIndexValid = false
end

local function clearSpatialIndex()
	table.clear(playerBuckets)
	table.clear(oversizedPlayers)
	table.clear(playerBoundsMin)
	table.clear(playerBoundsMax)
	spatialIndexedPlayers = 0
	spatialBucketCount = 0
end

local function addPlayerToBucket(key: string, player: Player)
	local bucket = playerBuckets[key]
	if bucket == nil then
		bucket = {}
		playerBuckets[key] = bucket
		spatialBucketCount += 1
	end
	table.insert(bucket, player)
end

local function rebuildPlayerSpatialIndex()
	clearSpatialIndex()

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character == nil then
			continue
		end

		local success, boxCF, boxSize = pcall(function()
			local cframe, size = character:GetBoundingBox()
			return cframe, size
		end)

		if not success or typeof(boxCF) ~= "CFrame" or typeof(boxSize) ~= "Vector3" then
			local root = getCharacterRoot(character)
			if root == nil then
				continue
			end
			boxCF = root.CFrame
			boxSize = root.Size
		end

		local minimum, maximum = orientedBoxWorldAABB(boxCF :: CFrame, boxSize :: Vector3)
		playerBoundsMin[player] = minimum
		playerBoundsMax[player] = maximum
		spatialIndexedPlayers += 1

		if not spatialEnabled then
			continue
		end

		local x0, x1, y0, y1, z0, z1 = getCellRange(minimum, maximum, spatialCellSize)
		local cells = getCellCount(x0, x1, y0, y1, z0, z1)

		if cells > spatialMaxPlayerCells then
			table.insert(oversizedPlayers, player)
			continue
		end

		for x = x0, x1 do
			for y = y0, y1 do
				for z = z0, z1 do
					addPlayerToBucket(cellKey(x, y, z), player)
				end
			end
		end
	end

	spatialRebuilds += 1
	spatialIndexValid = true
end

local function ensurePlayerSpatialIndex()
	if not spatialIndexValid then
		rebuildPlayerSpatialIndex()
	end
end

local function validateIndexMode(mode: string): IndexMode
	if mode == "Auto" or mode == "Static" or mode == "Dynamic" then
		return mode :: IndexMode
	end
	error(("Unknown IndexMode %q"):format(mode), 3)
end

local function clearStaticTree()
	table.clear(staticNodeMin)
	table.clear(staticNodeMax)
	table.clear(staticNodeLeft)
	table.clear(staticNodeRight)
	table.clear(staticNodeZone)
	staticTreeRoot = 0
	staticNodeCount = 0
	staticIndexedZones = 0
end

local function clearDynamicIndex()
	table.clear(dynamicBuckets)
	table.clear(dynamicZoneKeys)
	table.clear(dynamicOversizedZones)
	table.clear(dynamicIndexedSet)
	table.clear(dynamicDirtyZones)
	dynamicBucketCount = 0
	dynamicIndexedZones = 0
end

local function removeDynamicZone(zone: AnyZone)
	local keys = dynamicZoneKeys[zone]
	if keys then
		for _, key in ipairs(keys) do
			local bucket = dynamicBuckets[key]
			if bucket then
				bucket[zone] = nil
				if next(bucket) == nil then
					dynamicBuckets[key] = nil
					dynamicBucketCount = math.max(0, dynamicBucketCount - 1)
				end
			end
		end
		dynamicZoneKeys[zone] = nil
	end

	if dynamicOversizedZones[zone] then
		dynamicOversizedZones[zone] = nil
	end

	if dynamicIndexedSet[zone] then
		dynamicIndexedSet[zone] = nil
		dynamicIndexedZones = math.max(0, dynamicIndexedZones - 1)
	end
end

local function insertDynamicZone(zone: AnyZone)
	removeDynamicZone(zone)

	if zone._destroyed or zone._destroying or not zone._indexDynamic then
		return
	end

	zone:_recomputeBounds()
	if not zone._boundsValid then
		return
	end

	dynamicIndexedSet[zone] = true
	dynamicIndexedZones += 1

	local x0, x1, y0, y1, z0, z1 =
		getCellRange(zone._boundsMin, zone._boundsMax, zoneIndexCellSize)
	local cells = getCellCount(x0, x1, y0, y1, z0, z1)

	if cells > zoneIndexMaxZoneCells then
		dynamicOversizedZones[zone] = true
		return
	end

	local keys = table.create(cells)
	for x = x0, x1 do
		for y = y0, y1 do
			for z = z0, z1 do
				local key = cellKey(x, y, z)
				local bucket = dynamicBuckets[key]
				if bucket == nil then
					bucket = {}
					dynamicBuckets[key] = bucket
					dynamicBucketCount += 1
				end
				bucket[zone] = true
				table.insert(keys, key)
			end
		end
	end

	dynamicZoneKeys[zone] = keys
end

local function processDynamicDirtyZones()
	if next(dynamicDirtyZones) == nil then
		return
	end

	for zone in pairs(dynamicDirtyZones) do
		dynamicDirtyZones[zone] = nil
		insertDynamicZone(zone)
	end
end

local function mortonCode10(x: number, y: number, z: number): number
	local code = 0
	for bitIndex = 0, 9 do
		local divisor = 2 ^ bitIndex
		local xb = math.floor(x / divisor) % 2
		local yb = math.floor(y / divisor) % 2
		local zb = math.floor(z / divisor) % 2
		local shift = 2 ^ (bitIndex * 3)
		code += xb * shift + yb * shift * 2 + zb * shift * 4
	end
	return code
end

local function quantizeMorton(value: number, minimum: number, maximum: number): number
	local span = maximum - minimum
	if span <= EPSILON then
		return 0
	end
	return math.clamp(math.floor(((value - minimum) / span) * 1023 + 0.5), 0, 1023)
end

local function addStaticNode(
	minimum: Vector3,
	maximum: Vector3,
	left: number,
	right: number,
	zone: AnyZone?
): number
	staticNodeCount += 1
	local index = staticNodeCount
	staticNodeMin[index] = minimum
	staticNodeMax[index] = maximum
	staticNodeLeft[index] = left
	staticNodeRight[index] = right
	staticNodeZone[index] = zone
	return index
end

local function buildStaticNode(entries: {any}, first: number, last: number): number
	if first == last then
		local entry = entries[first]
		return addStaticNode(entry.Min, entry.Max, 0, 0, entry.Zone)
	end

	local middle = math.floor((first + last) * 0.5)
	local left = buildStaticNode(entries, first, middle)
	local right = buildStaticNode(entries, middle + 1, last)

	local leftMin = staticNodeMin[left]
	local leftMax = staticNodeMax[left]
	local rightMin = staticNodeMin[right]
	local rightMax = staticNodeMax[right]

	local minimum = Vector3.new(
		math.min(leftMin.X, rightMin.X),
		math.min(leftMin.Y, rightMin.Y),
		math.min(leftMin.Z, rightMin.Z)
	)
	local maximum = Vector3.new(
		math.max(leftMax.X, rightMax.X),
		math.max(leftMax.Y, rightMax.Y),
		math.max(leftMax.Z, rightMax.Z)
	)

	return addStaticNode(minimum, maximum, left, right, nil)
end

local function rebuildStaticTree()
	clearStaticTree()

	if not zoneIndexEnabled then
		staticTreeDirty = false
		return
	end

	local entries = {}
	local centroidMin: Vector3? = nil
	local centroidMax: Vector3? = nil

	for _, zone in ipairs(zoneList) do
		if zone._destroyed or zone._destroying or zone._indexDynamic then
			continue
		end

		zone:_recomputeBounds()
		if not zone._boundsValid then
			continue
		end

		local center = (zone._boundsMin + zone._boundsMax) * 0.5
		local entry = {
			Zone = zone,
			Min = zone._boundsMin,
			Max = zone._boundsMax,
			Center = center,
			Code = 0,
		}
		table.insert(entries, entry)

		if centroidMin == nil then
			centroidMin = center
			centroidMax = center
		else
			local currentMin = centroidMin :: Vector3
			local currentMax = centroidMax :: Vector3
			centroidMin = Vector3.new(
				math.min(currentMin.X, center.X),
				math.min(currentMin.Y, center.Y),
				math.min(currentMin.Z, center.Z)
			)
			centroidMax = Vector3.new(
				math.max(currentMax.X, center.X),
				math.max(currentMax.Y, center.Y),
				math.max(currentMax.Z, center.Z)
			)
		end
	end

	staticIndexedZones = #entries

	if #entries == 0 then
		staticTreeDirty = false
		zoneIndexRebuilds += 1
		return
	end

	local cmin = centroidMin :: Vector3
	local cmax = centroidMax :: Vector3

	for _, entry in ipairs(entries) do
		local center = entry.Center
		entry.Code = mortonCode10(
			quantizeMorton(center.X, cmin.X, cmax.X),
			quantizeMorton(center.Y, cmin.Y, cmax.Y),
			quantizeMorton(center.Z, cmin.Z, cmax.Z)
		)
	end

	table.sort(entries, function(a, b)
		if a.Code == b.Code then
			return a.Zone._creationIndex < b.Zone._creationIndex
		end
		return a.Code < b.Code
	end)

	staticTreeRoot = buildStaticNode(entries, 1, #entries)
	staticTreeDirty = false
	zoneIndexRebuilds += 1
end

local function rebuildDynamicIndex()
	clearDynamicIndex()

	if not zoneIndexEnabled then
		return
	end

	for _, zone in ipairs(zoneList) do
		if not zone._destroyed and not zone._destroying and zone._indexDynamic then
			insertDynamicZone(zone)
		end
	end
end

local function invalidateZoneIndex()
	staticTreeDirty = true

	for _, zone in ipairs(zoneList) do
		if zone._indexDynamic and not zone._destroyed and not zone._destroying then
			dynamicDirtyZones[zone] = true
		end
	end
end

local function rebuildZoneSpatialIndex()
	rebuildStaticTree()
	rebuildDynamicIndex()
end

local function ensureZoneSpatialIndex()
	if not zoneIndexEnabled then
		return
	end

	if staticTreeDirty then
		rebuildStaticTree()
	end

	processDynamicDirtyZones()
end

local function markZoneIndexGeometryDirty(zone: AnyZone)
	if not zones[zone] then
		return
	end

	if zone.IndexMode == "Auto" and not zone._indexDynamic then
		zone._indexDynamic = true
		zoneIndexAutoPromotions += 1
		staticTreeDirty = true
		dynamicDirtyZones[zone] = true
	elseif zone._indexDynamic then
		dynamicDirtyZones[zone] = true
	else
		staticTreeDirty = true
	end
end

local function sortZonesByRegistryOrder(list: {AnyZone})
	table.sort(list, function(a, b)
		if a.Priority == b.Priority then
			return a._creationIndex < b._creationIndex
		end
		return a.Priority > b.Priority
	end)
end

local staticQueryStack: {number} = {}

local function collectStaticTreeAABB(minimum: Vector3, maximum: Vector3, result: {AnyZone}, seen: {[AnyZone]: boolean})
	if staticTreeRoot == 0 then
		return
	end

	table.clear(staticQueryStack)
	table.insert(staticQueryStack, staticTreeRoot)

	while #staticQueryStack > 0 do
		local nodeIndex = staticQueryStack[#staticQueryStack]
		staticQueryStack[#staticQueryStack] = nil

		if not aabbIntersects(
			minimum,
			maximum,
			staticNodeMin[nodeIndex],
			staticNodeMax[nodeIndex]
			) then
			continue
		end

		local zone = staticNodeZone[nodeIndex]
		if zone then
			if not zone._destroyed and not zone._destroying and not zone._indexDynamic and not seen[zone] then
				seen[zone] = true
				table.insert(result, zone)
			end
		else
			local left = staticNodeLeft[nodeIndex]
			local right = staticNodeRight[nodeIndex]
			if left ~= 0 then
				table.insert(staticQueryStack, left)
			end
			if right ~= 0 then
				table.insert(staticQueryStack, right)
			end
		end
	end
end

local function collectDynamicGridAABB(minimum: Vector3, maximum: Vector3, result: {AnyZone}, seen: {[AnyZone]: boolean}): number?
	local x0, x1, y0, y1, z0, z1 =
		getCellRange(minimum, maximum, zoneIndexCellSize)
	local cells = getCellCount(x0, x1, y0, y1, z0, z1)

	if cells > zoneIndexMaxQueryCells then
		return nil
	end

	for x = x0, x1 do
		for y = y0, y1 do
			for z = z0, z1 do
				local bucket = dynamicBuckets[cellKey(x, y, z)]
				if bucket then
					for zone in pairs(bucket) do
						if not seen[zone] and not zone._destroyed and not zone._destroying then
							seen[zone] = true
							table.insert(result, zone)
						end
					end
				end
			end
		end
	end

	for zone in pairs(dynamicOversizedZones) do
		if not seen[zone] and not zone._destroyed and not zone._destroying then
			seen[zone] = true
			table.insert(result, zone)
		end
	end

	return cells
end

local function collectZoneIndexAABB(
	minimum: Vector3,
	maximum: Vector3,
	trackStats: boolean?,
	sortResult: boolean?
): {AnyZone}?
	if not zoneIndexEnabled or #zoneList <= zoneIndexBruteForceThreshold then
		if trackStats ~= false then
			queryZoneIndexFallbacks += 1
		end
		return nil
	end

	ensureZoneSpatialIndex()

	local result = {}
	local seen: {[AnyZone]: boolean} = {}

	collectStaticTreeAABB(minimum, maximum, result, seen)
	local cells = collectDynamicGridAABB(minimum, maximum, result, seen)

	if cells == nil then
		if trackStats ~= false then
			queryZoneIndexFallbacks += 1
		end
		return nil
	end

	if trackStats ~= false then
		queryZoneIndexQueries += 1
		queryZoneCellsVisited += cells
	end

	if sortResult ~= false then
		sortZonesByRegistryOrder(result)
	end

	return result
end

local function rebuildZoneList()
	table.clear(zoneList)
	for zone in pairs(zones) do
		table.insert(zoneList, zone)
	end

	table.sort(zoneList, function(a, b)
		if a.Priority == b.Priority then
			return a._creationIndex < b._creationIndex
		end
		return a.Priority > b.Priority
	end)

	table.clear(zoneNameIndex)
	table.clear(zoneTagIndex)

	for rank, zone in ipairs(zoneList) do
		zone._registryRank = rank
		if not zone._destroyed and not zone._destroying then
			local nameBucket = zoneNameIndex[zone.Name]
			if nameBucket == nil then
				nameBucket = {}
				zoneNameIndex[zone.Name] = nameBucket
			end
			table.insert(nameBucket, zone)

			for tag in pairs(zone._tags) do
				local tagBucket = zoneTagIndex[tag]
				if tagBucket == nil then
					tagBucket = {}
					zoneTagIndex[tag] = tagBucket
				end
				table.insert(tagBucket, zone)
			end
		end
	end
end

local function requestZoneListRebuild()
	if registryBatchDepth > 0 then
		registryDirty = true
		return
	end

	rebuildZoneList()
end


local function addPlayerMembership(player: Player, zone: AnyZone)
	local membership = playerMemberships[player]

	if membership == nil then
		membership = {}
		playerMemberships[player] = membership
	end

	membership[zone] = true
end

local function removePlayerMembership(player: Player, zone: AnyZone)
	local membership = playerMemberships[player]

	if membership == nil then
		return
	end

	membership[zone] = nil

	if next(membership) == nil then
		playerMemberships[player] = nil
	end
end

local function clearZoneMemberships(zone: AnyZone)
	for player, membership in pairs(playerMemberships) do
		if membership[zone] then
			membership[zone] = nil

			if next(membership) == nil then
				playerMemberships[player] = nil
			end
		end
	end
end

local function getPlayerMembership(player: Player): {[AnyZone]: boolean}?
	return playerMemberships[player]
end

local function getActivePlayerMembershipCount(): number
	local count = 0

	for _, membership in pairs(playerMemberships) do
		for zone in pairs(membership) do
			if not zone._destroyed and not zone._destroying then
				count += 1
			end
		end
	end

	return count
end

local function getTrackedItemCount(): number
	local count = 0
	for zone in pairs(zones) do
		for _ in pairs(zone._trackedItems) do
			count += 1
		end
	end
	return count
end

local function stopSchedulerIfUnused()
	if next(zones) ~= nil then
		return
	end

	if schedulerConnection then
		schedulerConnection:Disconnect()
		schedulerConnection = nil
	end

	clearSpatialIndex()
	spatialIndexValid = false
	clearStaticTree()
	clearDynamicIndex()
	staticTreeDirty = true
	schedulerRoundRobinCursor = 0
end

local creationCounter = 0

local function collectZoneParts(container: any): {BasePart}
	local result: {BasePart} = {}
	local seen: {[BasePart]: boolean} = {}

	local function add(part: BasePart)
		if seen[part] then
			return
		end
		seen[part] = true
		table.insert(result, part)
	end

	if typeof(container) == "Instance" then
		local instance = container :: Instance

		if instance:IsA("BasePart") then
			add(instance)
		else
			for _, descendant in ipairs(instance:GetDescendants()) do
				if descendant:IsA("BasePart") then
					add(descendant)
				end
			end
		end
	else
		for _, candidate in ipairs(container) do
			assert(typeof(candidate) == "Instance" and candidate:IsA("BasePart"), "Zone part arrays may only contain BaseParts")
			add(candidate)
		end
	end

	return result
end

local function validateDetection(mode: string): DetectionMode
	if mode == "Center" or mode == "Bounds" or mode == "AnyPart" or mode == "WholeCharacter" then
		return mode :: DetectionMode
	end

	error(("Unknown Detection mode %q"):format(mode), 3)
end

local function updateZoneSchedulerResidency(zone: AnyZone)
	if zone._destroyed or zone._destroying or not zone.Enabled then
		schedulerAlwaysZones[zone] = nil
		return
	end

	local hasTrackedItems = next(zone._trackedItems) ~= nil
	local hasPlayerState = next(zone._playerStates) ~= nil
	local requiresFullPlayerScan = zone.TrackPlayers and not zone.BroadPhase

	if hasTrackedItems or hasPlayerState or requiresFullPlayerScan then
		schedulerAlwaysZones[zone] = true
	else
		schedulerAlwaysZones[zone] = nil
	end
end

local function collectScheduledZones(): {AnyZone}
	if not schedulerActiveOnly or not zoneIndexEnabled or #zoneList <= zoneIndexBruteForceThreshold then
		return shallowCopy(zoneList)
	end

	ensurePlayerSpatialIndex()
	ensureZoneSpatialIndex()

	local result = {}
	local seen: {[AnyZone]: boolean} = {}

	for player, minimum in pairs(playerBoundsMin) do
		local maximum = playerBoundsMax[player]
		if maximum == nil then
			continue
		end

		local candidates = collectZoneIndexAABB(minimum, maximum, false, false)
		if candidates == nil then
			return shallowCopy(zoneList)
		end

		for _, zone in ipairs(candidates) do
			if zone.TrackPlayers and not seen[zone] then
				seen[zone] = true
				table.insert(result, zone)
			end
		end
	end

	for zone in pairs(schedulerAlwaysZones) do
		if not seen[zone] then
			seen[zone] = true
			table.insert(result, zone)
		end
	end

	return result
end

local function shouldStepScheduledZone(zone: AnyZone, now: number): boolean
	if zone._destroyed or zone._destroying or not zone.Enabled then
		return false
	end

	if not zone.TrackPlayers and next(zone._trackedItems) == nil then
		return false
	end

	if now + EPSILON < zone._nextStepAt then
		return false
	end

	return true
end

local function ensureScheduler()
	if schedulerConnection then
		return
	end

	schedulerConnection = RunService.Heartbeat:Connect(function()
		local frameStarted = os.clock()

		schedulerTicks += 1
		invalidateSpatialIndex()

		local candidateStarted = os.clock()
		local snapshot = collectScheduledZones()
		local candidateElapsed = os.clock() - candidateStarted

		schedulerLastCandidateSeconds = candidateElapsed
		schedulerPeakCandidateSeconds = math.max(
			schedulerPeakCandidateSeconds,
			candidateElapsed
		)

		local count = #snapshot

		schedulerCandidateZones += count
		schedulerSkippedZones += math.max(
			0,
			#zoneList - count
		)

		if count == 0 then
			local frameElapsed =
				os.clock() - frameStarted

			schedulerLastWorkSeconds = 0
			schedulerLastFrameSeconds = frameElapsed
			schedulerPeakFrameSeconds = math.max(
				schedulerPeakFrameSeconds,
				frameElapsed
			)

			return
		end

		local workStarted = os.clock()

		local startIndex =
			(schedulerRoundRobinCursor % count) + 1

		local visited = 0
		local stepped = 0

		local stoppedForBudget = false
		local stoppedForStepLimit = false
		local frameOverrunCounted = false

		for offset = 0, count - 1 do
			if visited > 0 then
				if schedulerFrameBudgetSeconds > 0
					and os.clock() - workStarted
					>= schedulerFrameBudgetSeconds
				then
					stoppedForBudget = true
					break
				end

				if schedulerMaxStepsPerFrame > 0
					and stepped
					>= schedulerMaxStepsPerFrame
				then
					stoppedForStepLimit = true
					break
				end
			end

			local index =
				((startIndex + offset - 2) % count) + 1

			local zone = snapshot[index]
			visited += 1

			local now = os.clock()

			if not shouldStepScheduledZone(
				zone,
				now
				) then
				continue
			end

			zone._nextStepAt =
				now + zone.UpdateInterval

			local stepStarted = os.clock()

			local success, err =
				xpcall(function()
					zone:_step()
				end, debug.traceback)

			local stepElapsed =
				os.clock() - stepStarted

			schedulerSteps += 1
			stepped += 1

			if schedulerFrameBudgetSeconds > 0
				and stepElapsed
				> schedulerFrameBudgetSeconds
			then
				schedulerBudgetOverruns += 1
				frameOverrunCounted = true
			end

			if not success then
				zone._stats.Errors += 1
				globalErrors += 1

				warn(
					(
						"[ZonePlusNext v%s] "
							.. "zone %q step failed:\n%s"
					):format(
						VERSION,
						zone.Name,
						tostring(err)
					)
				)
			end
		end

		schedulerRoundRobinCursor =
			(startIndex - 1 + visited) % count

		local deferred =
			math.max(0, count - visited)

		if deferred > 0 then
			schedulerDeferredZones += deferred
		end

		if stoppedForBudget then
			schedulerBudgetHits += 1
		end

		if stoppedForStepLimit then
			schedulerStepLimitHits += 1
		end

		local workElapsed =
			os.clock() - workStarted

		if schedulerFrameBudgetSeconds > 0
			and workElapsed
			> schedulerFrameBudgetSeconds
			and stepped > 0
			and not frameOverrunCounted
		then
			schedulerBudgetOverruns += 1
		end

		local frameElapsed =
			os.clock() - frameStarted

		schedulerLastWorkSeconds = workElapsed
		schedulerPeakWorkSeconds = math.max(
			schedulerPeakWorkSeconds,
			workElapsed
		)

		schedulerLastFrameSeconds = frameElapsed
		schedulerPeakFrameSeconds = math.max(
			schedulerPeakFrameSeconds,
			frameElapsed
		)
	end)
end

local function makeCandidateState(): CandidateState
	return {
		inside = false,
		pendingInside = nil,
		pendingSince = nil,
		lastSeen = os.clock(),
	}
end

function ZonePlusNext.Version(): string
	return VERSION
end

function ZonePlusNext.ConfigureScheduler(config: SchedulerConfig)
	assert(type(config) == "table", "ConfigureScheduler expects a table")

	if config.ActiveOnly ~= nil then
		schedulerActiveOnly =
			not not config.ActiveOnly
	end

	if config.FrameBudgetMs ~= nil then
		local milliseconds =
			requireNonNegativeFinite(
				config.FrameBudgetMs,
				"FrameBudgetMs"
			)

		schedulerFrameBudgetSeconds =
			milliseconds / 1000
	end

	if config.MaxStepsPerFrame ~= nil then
		local steps =
			requireNonNegativeFinite(
				config.MaxStepsPerFrame,
				"MaxStepsPerFrame"
			)

		schedulerMaxStepsPerFrame =
			math.floor(steps)
	end
end

function ZonePlusNext.GetSchedulerConfig(): SchedulerConfig
	return {
		ActiveOnly = schedulerActiveOnly,
		FrameBudgetMs =
			schedulerFrameBudgetSeconds * 1000,
		MaxStepsPerFrame =
			schedulerMaxStepsPerFrame,
	}
end

function ZonePlusNext.SetSchedulerBudget(
	milliseconds: number
)
	ZonePlusNext.ConfigureScheduler({
		FrameBudgetMs = milliseconds,
	})
end

function ZonePlusNext.GetSchedulerStats(): SchedulerStats
	return {
		Ticks = schedulerTicks,
		FrameBudgetMs =
			schedulerFrameBudgetSeconds * 1000,
		MaxStepsPerFrame =
			schedulerMaxStepsPerFrame,
		Steps = schedulerSteps,
		CandidateZones = schedulerCandidateZones,
		SkippedZones = schedulerSkippedZones,
		DeferredZones = schedulerDeferredZones,
		BudgetHits = schedulerBudgetHits,
		StepLimitHits = schedulerStepLimitHits,
		BudgetOverruns = schedulerBudgetOverruns,
		LastFrameSeconds =
			schedulerLastFrameSeconds,
		PeakFrameSeconds =
			schedulerPeakFrameSeconds,
		LastCandidateSeconds =
			schedulerLastCandidateSeconds,
		PeakCandidateSeconds =
			schedulerPeakCandidateSeconds,
		LastWorkSeconds =
			schedulerLastWorkSeconds,
		PeakWorkSeconds =
			schedulerPeakWorkSeconds,
	}
end

function ZonePlusNext.ResetSchedulerStats()
	schedulerTicks = 0
	schedulerSteps = 0
	schedulerCandidateZones = 0
	schedulerSkippedZones = 0
	schedulerDeferredZones = 0
	schedulerBudgetHits = 0
	schedulerStepLimitHits = 0
	schedulerBudgetOverruns = 0
	schedulerLastFrameSeconds = 0
	schedulerPeakFrameSeconds = 0
	schedulerLastCandidateSeconds = 0
	schedulerPeakCandidateSeconds = 0
	schedulerLastWorkSeconds = 0
	schedulerPeakWorkSeconds = 0
end

function ZonePlusNext.ConfigureSpatialHash(config: SpatialConfig)
	assert(type(config) == "table", "ConfigureSpatialHash expects a table")

	if config.Enabled ~= nil then
		spatialEnabled = not not config.Enabled
	end

	if config.CellSize ~= nil then
		local value = requireFiniteNumber(config.CellSize, "CellSize")
		assert(value > 0, "CellSize must be greater than zero")
		spatialCellSize = value
	end

	if config.MaxQueryCells ~= nil then
		local value = requireFiniteNumber(config.MaxQueryCells, "MaxQueryCells")
		assert(value >= 1, "MaxQueryCells must be at least 1")
		spatialMaxQueryCells = math.floor(value)
	end

	if config.MaxPlayerCells ~= nil then
		local value = requireFiniteNumber(config.MaxPlayerCells, "MaxPlayerCells")
		assert(value >= 1, "MaxPlayerCells must be at least 1")
		spatialMaxPlayerCells = math.floor(value)
	end

	if config.BruteForceThreshold ~= nil then
		local value = requireFiniteNumber(config.BruteForceThreshold, "BruteForceThreshold")
		assert(value >= 0, "BruteForceThreshold must be greater than or equal to zero")
		spatialBruteForceThreshold = math.floor(value)
	end

	spatialConfigRevision += 1
	invalidateSpatialIndex()
	if not spatialEnabled then
		clearSpatialIndex()
	end
end

function ZonePlusNext.GetSpatialConfig(): SpatialConfig
	return {
		Enabled = spatialEnabled,
		CellSize = spatialCellSize,
		MaxQueryCells = spatialMaxQueryCells,
		MaxPlayerCells = spatialMaxPlayerCells,
		BruteForceThreshold = spatialBruteForceThreshold,
	}
end

function ZonePlusNext.RebuildSpatialIndex()
	invalidateSpatialIndex()
	rebuildPlayerSpatialIndex()
end

function ZonePlusNext.ConfigureZoneIndex(config: ZoneIndexConfig)
	assert(type(config) == "table", "ConfigureZoneIndex expects a table")

	if config.Enabled ~= nil then
		zoneIndexEnabled = not not config.Enabled
	end

	if config.CellSize ~= nil then
		local value = requireFiniteNumber(config.CellSize, "CellSize")
		assert(value > 0, "CellSize must be greater than zero")
		zoneIndexCellSize = value
	end

	if config.MaxQueryCells ~= nil then
		local value = requireFiniteNumber(config.MaxQueryCells, "MaxQueryCells")
		assert(value >= 1, "MaxQueryCells must be at least 1")
		zoneIndexMaxQueryCells = math.floor(value)
	end

	if config.MaxZoneCells ~= nil then
		local value = requireFiniteNumber(config.MaxZoneCells, "MaxZoneCells")
		assert(value >= 1, "MaxZoneCells must be at least 1")
		zoneIndexMaxZoneCells = math.floor(value)
	end

	if config.BruteForceThreshold ~= nil then
		local value = requireFiniteNumber(config.BruteForceThreshold, "BruteForceThreshold")
		assert(value >= 0, "BruteForceThreshold must be greater than or equal to zero")
		zoneIndexBruteForceThreshold = math.floor(value)
	end

	staticTreeDirty = true
	clearDynamicIndex()

	if zoneIndexEnabled then
		for _, zone in ipairs(zoneList) do
			if zone._indexDynamic and not zone._destroyed and not zone._destroying then
				dynamicDirtyZones[zone] = true
			end
		end
	else
		clearStaticTree()
	end
end

function ZonePlusNext.GetZoneIndexConfig(): ZoneIndexConfig
	return {
		Enabled = zoneIndexEnabled,
		CellSize = zoneIndexCellSize,
		MaxQueryCells = zoneIndexMaxQueryCells,
		MaxZoneCells = zoneIndexMaxZoneCells,
		BruteForceThreshold = zoneIndexBruteForceThreshold,
	}
end

function ZonePlusNext.RebuildZoneIndex()
	rebuildZoneSpatialIndex()
end

function ZonePlusNext.WarmIndexes()
	ZonePlusNext.RebuildSpatialIndex()
	ZonePlusNext.RebuildZoneIndex()
end

function ZonePlusNext.GetIndexStats()
	ensureZoneSpatialIndex()

	local oversized = 0
	for _ in pairs(dynamicOversizedZones) do
		oversized += 1
	end

	return {
		Player = {
			Enabled = spatialEnabled,
			Rebuilds = spatialRebuilds,
			Buckets = spatialBucketCount,
			IndexedPlayers = spatialIndexedPlayers,
			OversizedPlayers = #oversizedPlayers,
		},
		Zone = {
			Enabled = zoneIndexEnabled,
			Rebuilds = zoneIndexRebuilds,
			Buckets = dynamicBucketCount,
			IndexedZones = staticIndexedZones + dynamicIndexedZones,
			OversizedZones = oversized,
			StaticZones = staticIndexedZones,
			DynamicZones = dynamicIndexedZones,
			StaticNodes = staticNodeCount,
			AutoPromotions = zoneIndexAutoPromotions,
		},
	}
end

function ZonePlusNext.BeginBatch()
	registryBatchDepth += 1
end

function ZonePlusNext.EndBatch()
	assert(registryBatchDepth > 0, "EndBatch called without BeginBatch")
	registryBatchDepth -= 1

	if registryBatchDepth == 0 and registryDirty then
		registryDirty = false
		rebuildZoneList()
	end
end

function ZonePlusNext.Batch(callback: () -> ...any): ...any
	assert(type(callback) == "function", "Batch expects a function")

	ZonePlusNext.BeginBatch()
	local packed = table.pack(xpcall(callback, debug.traceback))
	local success = packed[1]

	local endSuccess, endError = pcall(ZonePlusNext.EndBatch)
	if not endSuccess then
		error(endError, 2)
	end

	if not success then
		error(packed[2], 2)
	end

	return table.unpack(packed, 2, packed.n)
end

function ZonePlusNext.CreateMany(containers: {any}, options: ZoneOptions?): {AnyZone}
	assert(type(containers) == "table", "CreateMany expects an array")
	local result = table.create(#containers)

	ZonePlusNext.Batch(function()
		for index, container in ipairs(containers) do
			result[index] = ZonePlusNext.new(container, options)
		end
	end)

	return result
end

function ZonePlusNext.new(container: Instance | {BasePart}, options: ZoneOptions?): AnyZone
	assert(isSupportedContainer(container), "ZonePlusNext.new expects an Instance or an array of BaseParts")

	options = options or {}

	creationCounter += 1

	local self = setmetatable({}, ZonePlusNext) :: any

	self._creationIndex = creationCounter
	self._destroyed = false
	self._destroying = false
	self._ownedContainer = false
	self._containerConnections = {} :: {RBXScriptConnection}
	self._partConnections = {} :: {[BasePart]: {RBXScriptConnection}}
	self._itemConnections = {} :: {[Instance]: RBXScriptConnection}
	self._invalidParts = {} :: {[BasePart]: boolean}
	self._playerStates = {} :: {[Player]: CandidateState}
	self._playerHistory = {} :: {[Player]: {TransitionRecord}}
	self._trackedItems = {} :: {[Instance]: TrackedItem}
	self._occupancy = 0
	self._accumulator = 0
	self._nextStepAt = 0
	self._indexDynamic = false
	self._parts = {} :: {BasePart}
	self._filterErrorActive = false
	self._geometryDirty = true
	self._boundsValid = false
	self._boundsMin = Vector3.zero
	self._boundsMax = Vector3.zero
	self._queryCellKeys = {} :: {string}
	self._queryCellCount = 0
	self._queryCellFallback = false
	self._cellCacheRevision = -1

	self.Container = container
	self.Name = options.Name or if typeof(container) == "Instance" then (container :: Instance).Name else ("Zone_%d"):format(creationCounter)
	self.UpdateInterval = clampInterval(options.UpdateInterval)
	self.Detection = validateDetection(options.Detection or "Center")
	self.Padding = paddingToVector(options.Padding)
	assert(isFiniteVector3(self.Padding), "Padding must be finite")

	self.EnterDelay = requireNonNegativeFinite(options.EnterDelay or 0, "EnterDelay")
	self.ExitDelay = requireNonNegativeFinite(options.ExitDelay or 0.05, "ExitDelay")
	self.Priority = requireFiniteNumber(options.Priority or 0, "Priority")
	self.Capacity = nil
	if options.Capacity ~= nil then
		self.Capacity = math.floor(requireNonNegativeFinite(options.Capacity, "Capacity"))
	end
	self.TrackPlayers = if options.TrackPlayers == nil then true else options.TrackPlayers
	self.AutoDestroyWithContainer = if options.AutoDestroyWithContainer == nil then true else options.AutoDestroyWithContainer
	self.PlayerFilter = options.PlayerFilter
	self.BroadPhase = if options.BroadPhase == nil then true else not not options.BroadPhase
	self.IndexMode = validateIndexMode(options.IndexMode or "Auto")
	self._indexDynamic = self.IndexMode == "Dynamic"
	self.HistoryLimit = math.max(4, math.floor(requireNonNegativeFinite(options.HistoryLimit or globalTransitionHistoryLimit, "HistoryLimit")))
	self.Enabled = true

	self._tags = {} :: {[string]: boolean}
	if options.Tags then
		for _, tag in ipairs(options.Tags) do
			assert(type(tag) == "string" and tag ~= "", "Tags may only contain non-empty strings")
			self._tags[tag] = true
		end
	end

	self.playerEntered = newSignal()
	self.playerExited = newSignal()
	self.itemEntered = newSignal()
	self.itemExited = newSignal()
	self.partsChanged = newSignal()
	self.enabledChanged = newSignal()
	self.occupancyChanged = newSignal()
	self.destroying = newSignal()

	self._stats = {
		Checks = 0,
		Hits = 0,
		Misses = 0,
		Enters = 0,
		Exits = 0,
		Errors = 0,
		BroadPhaseQueries = 0,
		BroadPhaseFallbacks = 0,
		CandidatePlayers = 0,
		PrecisePlayerChecks = 0,
		CellsVisited = 0,
		LastCheckSeconds = 0,
		TotalCheckSeconds = 0,
	} :: ZoneStats

	self:_refreshParts()
	self:_bindContainer()

	zones[self] = true
	if self._indexDynamic then
		dynamicDirtyZones[self] = true
	else
		staticTreeDirty = true
	end
	requestZoneListRebuild()
	updateZoneSchedulerResidency(self)
	ensureScheduler()

	return self
end

function ZonePlusNext.fromRegion(cframe: CFrame, size: Vector3, options: ZoneOptions?): AnyZone
	assert(size.X > 0 and size.Y > 0 and size.Z > 0, "fromRegion size components must be greater than zero")

	local part = Instance.new("Part")
	part.Name = "ZonePlusNextRegion"
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Transparency = 1
	part.CFrame = cframe
	part.Size = size
	part.Parent = nil

	local merged = table.clone(options or {})
	if merged.Name == nil then
		merged.Name = "RegionZone"
	end
	merged.AutoDestroyWithContainer = false

	local zone = ZonePlusNext.new(part, merged)
	zone._ownedContainer = true
	return zone
end

function ZonePlusNext.GetZones(): {AnyZone}
	local result = {}
	for _, zone in ipairs(zoneList) do
		if not zone._destroyed and not zone._destroying then
			table.insert(result, zone)
		end
	end
	return result
end

function ZonePlusNext.GetByName(name: string): AnyZone?
	assert(type(name) == "string" and name ~= "", "GetByName name must be a non-empty string")
	local bucket = zoneNameIndex[name]
	if bucket then
		for _, zone in ipairs(bucket) do
			if not zone._destroyed and not zone._destroying then
				return zone
			end
		end
	end
	return nil
end

function ZonePlusNext.GetAllByName(name: string): {AnyZone}
	assert(type(name) == "string" and name ~= "", "GetAllByName name must be a non-empty string")
	local result = {}
	local bucket = zoneNameIndex[name]
	if bucket then
		for _, zone in ipairs(bucket) do
			if not zone._destroyed and not zone._destroying then
				table.insert(result, zone)
			end
		end
	end
	return result
end

function ZonePlusNext.GetZoneCount(enabledOnly: boolean?): number
	if enabledOnly ~= nil then
		assert(type(enabledOnly) == "boolean", "GetZoneCount enabledOnly must be a boolean")
	end

	local count = 0
	for _, zone in ipairs(zoneList) do
		if not zone._destroyed and not zone._destroying then
			if enabledOnly ~= true or zone.Enabled then
				count += 1
			end
		end
	end
	return count
end

function ZonePlusNext.GetZonesForPlayer(player: Player): {AnyZone}
	assert(typeof(player) == "Instance" and player:IsA("Player"), "GetZonesForPlayer expects a Player")

	local membership = getPlayerMembership(player)
	if membership == nil then
		return {}
	end

	local result = {}

	for zone in pairs(membership) do
		if not zone._destroyed and not zone._destroying then
			table.insert(result, zone)
		end
	end

	table.sort(result, function(a, b)
		return a._registryRank < b._registryRank
	end)

	return result
end

function ZonePlusNext.GetHighestPriorityZone(player: Player): AnyZone?
	assert(typeof(player) == "Instance" and player:IsA("Player"), "GetHighestPriorityZone expects a Player")

	local membership = getPlayerMembership(player)
	if membership == nil then
		return nil
	end

	local best: AnyZone? = nil
	local bestRank = math.huge

	for zone in pairs(membership) do
		if not zone._destroyed and not zone._destroying then
			local rank = zone._registryRank or math.huge

			if rank < bestRank then
				best = zone
				bestRank = rank
			end
		end
	end

	return best
end

function ZonePlusNext.IsPlayerInAnyZone(player: Player): boolean
	local membership = getPlayerMembership(player)
	return membership ~= nil and next(membership) ~= nil
end

function ZonePlusNext.GetPlayerZoneByTag(player: Player, tag: string): AnyZone?
	assert(type(tag) == "string" and tag ~= "", "tag must be a non-empty string")

	local membership = getPlayerMembership(player)
	if membership == nil then
		return nil
	end

	local best: AnyZone? = nil
	local bestRank = math.huge

	for zone in pairs(membership) do
		if not zone._destroyed
			and not zone._destroying
			and zone._tags[tag]
		then
			local rank = zone._registryRank or math.huge

			if rank < bestRank then
				best = zone
				bestRank = rank
			end
		end
	end

	return best
end

function ZonePlusNext.IsPlayerInTag(player: Player, tag: string): boolean
	return ZonePlusNext.GetPlayerZoneByTag(player, tag) ~= nil
end

function ZonePlusNext.IsPlayerInAnyTag(player: Player, tags: {string}): boolean
	assert(type(tags) == "table", "tags must be an array")

	for _, tag in ipairs(tags) do
		assert(type(tag) == "string" and tag ~= "", "tags must contain non-empty strings")

		if ZonePlusNext.IsPlayerInTag(player, tag) then
			return true
		end
	end

	return false
end

function ZonePlusNext.IsPlayerInAllTags(player: Player, tags: {string}): boolean
	assert(type(tags) == "table", "tags must be an array")

	for _, tag in ipairs(tags) do
		assert(type(tag) == "string" and tag ~= "", "tags must contain non-empty strings")

		if not ZonePlusNext.IsPlayerInTag(player, tag) then
			return false
		end
	end

	return true
end

function ZonePlusNext.GetPlayerTags(player: Player): {string}
	local membership = getPlayerMembership(player)
	if membership == nil then
		return {}
	end

	local seen: {[string]: boolean} = {}
	local result = {}

	for zone in pairs(membership) do
		if not zone._destroyed and not zone._destroying then
			for tag in pairs(zone._tags) do
				if not seen[tag] then
					seen[tag] = true
					table.insert(result, tag)
				end
			end
		end
	end

	table.sort(result)
	return result
end

function ZonePlusNext.GetPlayersByTag(tag: string): {Player}
	assert(type(tag) == "string" and tag ~= "", "tag must be a non-empty string")

	local result = {}
	local bucket = zoneTagIndex[tag]

	if bucket == nil then
		return result
	end

	local seen: {[Player]: boolean} = {}

	for _, zone in ipairs(bucket) do
		if not zone._destroyed and not zone._destroying then
			for player, state in pairs(zone._playerStates) do
				if state.inside and not seen[player] then
					seen[player] = true
					table.insert(result, player)
				end
			end
		end
	end

	table.sort(result, function(a, b)
		return a.UserId < b.UserId
	end)

	return result
end

function ZonePlusNext.CountPlayersByTag(tag: string): number
	return #ZonePlusNext.GetPlayersByTag(tag)
end

function ZonePlusNext.GetGlobalStats(): GlobalStats
	local enabled = 0
	for zone in pairs(zones) do
		if not zone._destroyed and not zone._destroying and zone.Enabled then
			enabled += 1
		end
	end

	return {
		Version = VERSION,
		Zones = ZonePlusNext.GetZoneCount(),
		EnabledZones = enabled,
		ActivePlayerMemberships = getActivePlayerMembershipCount(),
		TrackedItems = getTrackedItemCount(),
		SchedulerTicks = schedulerTicks,
		Checks = globalChecks,
		Errors = globalErrors,
		BroadPhaseQueries = globalBroadPhaseQueries,
		BroadPhaseFallbacks = globalBroadPhaseFallbacks,
		CandidatePlayers = globalCandidatePlayers,
		PrecisePlayerChecks = globalPrecisePlayerChecks,
		CellsVisited = globalCellsVisited,
		SpatialRebuilds = spatialRebuilds,
		SpatialBuckets = spatialBucketCount,
		IndexedPlayers = spatialIndexedPlayers,
		ZoneIndexRebuilds = zoneIndexRebuilds,
		ZoneIndexBuckets = dynamicBucketCount,
		IndexedZones = staticIndexedZones + dynamicIndexedZones,
		OversizedZones = (function()
			local count = 0
			for _ in pairs(dynamicOversizedZones) do count += 1 end
			return count
		end)(),
		StaticIndexNodes = staticNodeCount,
		StaticIndexedZones = staticIndexedZones,
		DynamicIndexedZones = dynamicIndexedZones,
		AutoPromotions = zoneIndexAutoPromotions,
		SchedulerCandidateZones = schedulerCandidateZones,
		SchedulerSkippedZones = schedulerSkippedZones,
		SchedulerSteps = schedulerSteps,
		SchedulerDeferredZones = schedulerDeferredZones,
		SchedulerBudgetHits = schedulerBudgetHits,
		SchedulerStepLimitHits = schedulerStepLimitHits,
		SchedulerBudgetOverruns = schedulerBudgetOverruns,
		SchedulerLastFrameSeconds = schedulerLastFrameSeconds,
		SchedulerPeakFrameSeconds = schedulerPeakFrameSeconds,
		TotalCheckSeconds = globalCheckSeconds,
	}
end

function ZonePlusNext:_markGeometryDirty()
	self._geometryDirty = true
	self._cellCacheRevision = -1
	markZoneIndexGeometryDirty(self)
end

function ZonePlusNext:_recomputeBounds()
	if not self._geometryDirty then
		return
	end

	self._geometryDirty = false
	self._boundsValid = false

	local aggregateMin: Vector3? = nil
	local aggregateMax: Vector3? = nil

	for _, part in ipairs(self._parts) do
		if not self:_isPartActive(part) then
			continue
		end

		local paddedSize = part.Size + self.Padding * 2
		if paddedSize.X <= 0 or paddedSize.Y <= 0 or paddedSize.Z <= 0 then
			continue
		end

		local minimum, maximum = orientedBoxWorldAABB(part.CFrame, paddedSize)

		if aggregateMin == nil then
			aggregateMin = minimum
			aggregateMax = maximum
		else
			local currentMin = aggregateMin :: Vector3
			local currentMax = aggregateMax :: Vector3
			aggregateMin = Vector3.new(
				math.min(currentMin.X, minimum.X),
				math.min(currentMin.Y, minimum.Y),
				math.min(currentMin.Z, minimum.Z)
			)
			aggregateMax = Vector3.new(
				math.max(currentMax.X, maximum.X),
				math.max(currentMax.Y, maximum.Y),
				math.max(currentMax.Z, maximum.Z)
			)
		end
	end

	if aggregateMin ~= nil and aggregateMax ~= nil then
		self._boundsMin = aggregateMin
		self._boundsMax = aggregateMax
		self._boundsValid = true
	end
end

function ZonePlusNext:GetBounds(): (CFrame?, Vector3?)
	assert(not self._destroyed, "Cannot get bounds from a destroyed zone")
	self:_recomputeBounds()

	if not self._boundsValid then
		return nil, nil
	end

	local center = (self._boundsMin + self._boundsMax) * 0.5
	local size = self._boundsMax - self._boundsMin
	return CFrame.new(center), size
end

function ZonePlusNext:_getQueryCellKeys(): ({string}, number, boolean)
	self:_recomputeBounds()

	if not self._boundsValid then
		return {}, 0, false
	end

	if self._cellCacheRevision == spatialConfigRevision then
		return self._queryCellKeys, self._queryCellCount, self._queryCellFallback
	end

	local x0, x1, y0, y1, z0, z1 = getCellRange(self._boundsMin, self._boundsMax, spatialCellSize)
	local cells = getCellCount(x0, x1, y0, y1, z0, z1)

	self._queryCellCount = cells
	self._queryCellFallback = cells > spatialMaxQueryCells
	table.clear(self._queryCellKeys)

	if not self._queryCellFallback then
		for x = x0, x1 do
			for y = y0, y1 do
				for z = z0, z1 do
					table.insert(self._queryCellKeys, cellKey(x, y, z))
				end
			end
		end
	end

	self._cellCacheRevision = spatialConfigRevision
	return self._queryCellKeys, self._queryCellCount, self._queryCellFallback
end

function ZonePlusNext:_queryCandidatePlayers(): {Player}
	if not spatialEnabled or not self.BroadPhase then
		return Players:GetPlayers()
	end

	self._stats.BroadPhaseQueries += 1
	globalBroadPhaseQueries += 1

	local allPlayers = Players:GetPlayers()
	if #zoneList * #allPlayers <= spatialBruteForceThreshold then
		self._stats.BroadPhaseFallbacks += 1
		globalBroadPhaseFallbacks += 1
		self._stats.CandidatePlayers += #allPlayers
		globalCandidatePlayers += #allPlayers
		return allPlayers
	end

	local queryKeys, cells, fallback = self:_getQueryCellKeys()
	if not self._boundsValid then
		return {}
	end

	if fallback then
		self._stats.BroadPhaseFallbacks += 1
		globalBroadPhaseFallbacks += 1
		self._stats.CandidatePlayers += #allPlayers
		globalCandidatePlayers += #allPlayers
		return allPlayers
	end

	ensurePlayerSpatialIndex()

	self._stats.CellsVisited += cells
	globalCellsVisited += cells

	local result = {}
	local seen: {[Player]: boolean} = {}

	for _, key in ipairs(queryKeys) do
		local bucket = playerBuckets[key]
		if bucket then
			for _, player in ipairs(bucket) do
				if not seen[player] then
					seen[player] = true
					table.insert(result, player)
				end
			end
		end
	end

	for _, player in ipairs(oversizedPlayers) do
		if not seen[player] then
			seen[player] = true
			table.insert(result, player)
		end
	end

	self._stats.CandidatePlayers += #result
	globalCandidatePlayers += #result
	return result
end

function ZonePlusNext:_removePart(part: BasePart)
	self._invalidParts[part] = true
	self:_markGeometryDirty()

	local connections = self._partConnections[part]
	if connections then
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		self._partConnections[part] = nil
	end

	local nextParts = {}
	for _, current in ipairs(self._parts) do
		if current ~= part then
			table.insert(nextParts, current)
		end
	end
	self._parts = nextParts

	if not self._destroyed then
		self.partsChanged:Fire(shallowCopy(self._parts))
	end
end

function ZonePlusNext:_rebindPartConnections()
	local active: {[BasePart]: boolean} = {}

	for _, part in ipairs(self._parts) do
		active[part] = true
		if self._partConnections[part] == nil then
			local connections = {}

			table.insert(connections, part.Destroying:Connect(function()
				if self._destroyed then
					return
				end

				if typeof(self.Container) == "Instance" and self.Container == part and self.AutoDestroyWithContainer then
					self:Destroy()
					return
				end

				self:_removePart(part)
			end))

			table.insert(connections, part:GetPropertyChangedSignal("CFrame"):Connect(function()
				if not self._destroyed then
					self:_markGeometryDirty()
				end
			end))

			table.insert(connections, part:GetPropertyChangedSignal("Size"):Connect(function()
				if not self._destroyed then
					self:_markGeometryDirty()
				end
			end))

			self._partConnections[part] = connections
		end
	end

	for part, connections in pairs(self._partConnections) do
		if not active[part] then
			for _, connection in ipairs(connections) do
				connection:Disconnect()
			end
			self._partConnections[part] = nil
		end
	end
end

function ZonePlusNext:_bindContainer()
	if typeof(self.Container) ~= "Instance" then
		return
	end

	local container = self.Container :: Instance

	if container:IsA("BasePart") then
		return
	end

	table.insert(self._containerConnections, container.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			self:_refreshParts()
		end
	end))

	table.insert(self._containerConnections, container.DescendantRemoving:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			task.defer(function()
				if not self._destroyed then
					self:_refreshParts()
				end
			end)
		end
	end))

	table.insert(self._containerConnections, container.Destroying:Connect(function()
		if self.AutoDestroyWithContainer and not self._destroyed then
			self:Destroy()
		end
	end))
end

function ZonePlusNext:_refreshParts()
	if self._destroyed then
		return
	end

	local collected = collectZoneParts(self.Container)
	local refreshed = {}

	for _, part in ipairs(collected) do
		-- A removed part may be reparented into the container. The old
		-- invalidation mark must not permanently exclude a live part.
		self._invalidParts[part] = nil
		table.insert(refreshed, part)
	end

	self._parts = refreshed
	self:_markGeometryDirty()
	self:_rebindPartConnections()
	self.partsChanged:Fire(shallowCopy(self._parts))
end

function ZonePlusNext:Refresh()
	assert(not self._destroyed and not self._destroying, "Cannot refresh a destroyed zone")
	self:_refreshParts()
end

function ZonePlusNext:GetParts(): {BasePart}
	return shallowCopy(self._parts)
end

function ZonePlusNext:_isPartActive(part: BasePart): boolean
	if self._invalidParts[part] then
		return false
	end

	if typeof(self.Container) == "Instance" then
		local container = self.Container :: Instance
		if container:IsA("BasePart") then
			return part == container
		end
		return part:IsDescendantOf(container)
	end

	return true
end

function ZonePlusNext:_containsPointGeometry(point: Vector3): boolean
	if self._destroyed then
		return false
	end

	for _, part in ipairs(self._parts) do
		if self:_isPartActive(part) and pointInsidePart(part, point, self.Padding) then
			return true
		end
	end

	return false
end

function ZonePlusNext:ContainsPoint(point: Vector3): boolean
	if self._destroyed or not self.Enabled then
		return false
	end

	return self:_containsPointGeometry(point)
end

function ZonePlusNext:_containsRootBounds(root: BasePart): boolean
	for _, zonePart in ipairs(self._parts) do
		if not self:_isPartActive(zonePart) then
			continue
		end

		if isBoxLikeZonePart(zonePart) then
			local paddedSize = zonePart.Size + self.Padding * 2
			if paddedSize.X > 0 and paddedSize.Y > 0 and paddedSize.Z > 0 then
				if obbIntersects(root.CFrame, root.Size, zonePart.CFrame, paddedSize) then
					return true
				end
			end
		end
	end

	-- Shape-aware fallback for Ball/Cylinder Parts.
	for _, sample in ipairs(getBoxSamples(root.CFrame, root.Size)) do
		if self:_containsPointGeometry(sample) then
			return true
		end
	end

	for _, zonePart in ipairs(self._parts) do
		if self:_isPartActive(zonePart) and pointInsideOrientedBox(root.CFrame, root.Size, zonePart.Position) then
			return true
		end
	end

	return false
end

function ZonePlusNext:_containsAnyCharacterPart(character: Model): boolean
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") and isCharacterBodyPart(descendant, character) and self:ContainsPoint(descendant.Position) then
			return true
		end
	end

	return false
end

function ZonePlusNext:_containsWholeCharacter(character: Model): boolean
	local foundPart = false

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") and isCharacterBodyPart(descendant, character) then
			foundPart = true
			if not self:ContainsPoint(descendant.Position) then
				return false
			end
		end
	end

	return foundPart
end

function ZonePlusNext:FindPlayer(player: Player): boolean
	if self._destroyed or not self.Enabled then
		return false
	end

	if self.PlayerFilter then
		local success, allowed = pcall(self.PlayerFilter, player)
		if not success then
			self._stats.Errors += 1
			globalErrors += 1
			if not self._filterErrorActive then
				self._filterErrorActive = true
				warn(("[ZonePlusNext v%s] PlayerFilter failed for zone %q: %s"):format(VERSION, self.Name, tostring(allowed)))
			end
			return false
		end

		self._filterErrorActive = false
		if not allowed then
			return false
		end
	end

	local character = player.Character
	local root = getCharacterRoot(character)

	if self.Detection == "AnyPart" then
		return character ~= nil and self:_containsAnyCharacterPart(character)
	elseif self.Detection == "WholeCharacter" then
		return character ~= nil and self:_containsWholeCharacter(character)
	end

	if root == nil then
		return false
	end

	if self.Detection == "Bounds" then
		return self:_containsRootBounds(root)
	end

	return self:ContainsPoint(root.Position)
end

function ZonePlusNext:FindItem(instance: Instance): boolean
	if self._destroyed or not self.Enabled then
		return false
	end

	local position = getItemPosition(instance)
	if position == nil then
		return false
	end

	return self:ContainsPoint(position)
end

function ZonePlusNext:_recordPlayerTransition(player: Player, inside: boolean): TransitionRecord
	local now = os.clock()
	local position, velocity = getRootSnapshot(player)
	local speed = if velocity then velocity.Magnitude else 0
	local direction: Vector3? = nil

	local latest = latestPositionSample(player)
	if position and latest then
		local delta = position - latest.Position
		if delta.Magnitude > EPSILON then
			direction = delta.Unit
		end
	end
	if direction == nil and velocity and velocity.Magnitude > EPSILON then
		direction = velocity.Unit
	end

	local boundsCF, boundsSize = self:GetBounds()
	local transition: TransitionRecord = {
		Time = now,
		Inside = inside,
		Position = position,
		Velocity = velocity,
		Direction = direction,
		Speed = speed,
		Side = if position then sideFromPoint(boundsCF, boundsSize, position) else nil,
	}

	local history = self._playerHistory[player]
	if history == nil then
		history = {}
		self._playerHistory[player] = history
	end

	appendBounded(history, transition, self.HistoryLimit)
	return transition
end

function ZonePlusNext:_commitPlayerState(player: Player, state: CandidateState, inside: boolean)
	if state.inside == inside then
		return
	end

	state.inside = inside
	state.pendingInside = nil
	state.pendingSince = nil

	if inside then
		self._occupancy += 1
		addPlayerMembership(player, self)
	else
		self._occupancy = math.max(0, self._occupancy - 1)
		removePlayerMembership(player, self)
	end

	local transition = self:_recordPlayerTransition(player, inside)

	if inside then
		self._stats.Enters += 1
		self.playerEntered:Fire(player, self, transition)
	else
		self._stats.Exits += 1
		self.playerExited:Fire(player, self, transition)
	end

	self.occupancyChanged:Fire(self._occupancy, self.Capacity, self)
end

function ZonePlusNext:_commitItemState(instance: Instance, state: CandidateState, inside: boolean)
	if state.inside == inside then
		return
	end

	state.inside = inside
	state.pendingInside = nil
	state.pendingSince = nil

	if inside then
		self._stats.Enters += 1
		self.itemEntered:Fire(instance, self)
	else
		self._stats.Exits += 1
		self.itemExited:Fire(instance, self)
	end
end

function ZonePlusNext:_resolveCandidate(
	state: CandidateState,
	observedInside: boolean,
	enterDelay: number,
	exitDelay: number,
	commit: (boolean) -> ()
)
	state.lastSeen = os.clock()

	if observedInside == state.inside then
		state.pendingInside = nil
		state.pendingSince = nil
		return
	end

	local requiredDelay = if observedInside then enterDelay else exitDelay

	if requiredDelay <= 0 then
		commit(observedInside)
		return
	end

	if state.pendingInside ~= observedInside then
		state.pendingInside = observedInside
		state.pendingSince = os.clock()
		return
	end

	local pendingSince = state.pendingSince
	if pendingSince and os.clock() - pendingSince >= requiredDelay then
		commit(observedInside)
	end
end

function ZonePlusNext:_scanPlayers()
	if not self.TrackPlayers then
		return
	end

	local candidates = self:_queryCandidatePlayers()
	local candidateSet: {[Player]: boolean} = {}

	for _, player in ipairs(candidates) do
		candidateSet[player] = true
	end

	-- Keep active/pending states in the narrow phase even after the player has
	-- moved out of the broad-phase cells. This guarantees exits and delayed
	-- transitions are resolved correctly.
	for player, state in pairs(self._playerStates) do
		if player.Parent == Players and (state.inside or state.pendingInside ~= nil) and not candidateSet[player] then
			candidateSet[player] = true
			table.insert(candidates, player)
		end
	end

	for _, player in ipairs(candidates) do
		if player.Parent ~= Players then
			continue
		end

		local state = self._playerStates[player]
		if state == nil then
			state = makeCandidateState()
			self._playerStates[player] = state
		end

		self._stats.PrecisePlayerChecks += 1
		globalPrecisePlayerChecks += 1

		local inside = self:FindPlayer(player)
		if inside then
			self._stats.Hits += 1
		else
			self._stats.Misses += 1
		end

		self:_resolveCandidate(state, inside, self.EnterDelay, self.ExitDelay, function(nextInside)
			self:_commitPlayerState(player, state :: CandidateState, nextInside)
		end)

		if not state.inside and state.pendingInside == nil then
			self._playerStates[player] = nil
		end
	end

	for player, state in pairs(self._playerStates) do
		if player.Parent ~= Players then
			if state.inside then
				self:_commitPlayerState(player, state, false)
			end
			self._playerStates[player] = nil
		end
	end

	updateZoneSchedulerResidency(self)
end

function ZonePlusNext:_scanTrackedItems()
	for instance in pairs(self._trackedItems) do
		local inside =
			self:_refreshTrackedItem(
				instance,
				false
			)

		if inside then
			self._stats.Hits += 1
		else
			self._stats.Misses += 1
		end
	end
end

function ZonePlusNext:_step()
	if self._destroyed or not self.Enabled then
		return
	end

	local started = os.clock()

	self:_scanPlayers()
	self:_scanTrackedItems()

	local elapsed = os.clock() - started

	self._stats.Checks += 1
	self._stats.LastCheckSeconds = elapsed
	self._stats.TotalCheckSeconds += elapsed

	globalChecks += 1
	globalCheckSeconds += elapsed
end

function ZonePlusNext:StepNow()
	assert(not self._destroyed and not self._destroying, "Cannot step a destroyed zone")
	self:_step()
end

function ZonePlusNext:_refreshTrackedItem(
	instance: Instance,
	immediate: boolean
): boolean
	local record = self._trackedItems[instance]

	if record == nil then
		return false
	end

	local success, inside = pcall(function()
		return self:FindItem(instance)
	end)

	if not success then
		self._stats.Errors += 1
		globalErrors += 1
		inside = false
	end

	if immediate then
		self:_commitItemState(
			instance,
			record.state,
			inside
		)
	else
		self:_resolveCandidate(
			record.state,
			inside,
			self.EnterDelay,
			self.ExitDelay,
			function(nextInside)
				self:_commitItemState(
					instance,
					record.state,
					nextInside
				)
			end
		)
	end

	return inside
end

function ZonePlusNext:TrackItem(
	instance: Instance,
	immediate: boolean?
)
	assert(
		not self._destroyed
			and not self._destroying,
		"Cannot track an item on a destroyed zone"
	)

	assert(
		typeof(instance) == "Instance",
		"TrackItem expects an Instance"
	)

	assert(
		instance:IsA("BasePart")
			or instance:IsA("Model")
			or instance:IsA("Attachment"),
		"TrackItem supports BasePart, Model, and Attachment"
	)

	local existing =
		self._trackedItems[instance]

	if existing then
		if immediate == true then
			self:_refreshTrackedItem(
				instance,
				true
			)
		end

		return self
	end

	self._trackedItems[instance] = {
		instance = instance,
		state = makeCandidateState(),
	}

	self._itemConnections[instance] =
		instance.Destroying:Connect(function()
			if not self._destroyed then
				self:UntrackItem(
					instance,
					true
				)
			end
		end)

	updateZoneSchedulerResidency(self)

	if immediate == true then
		self:_refreshTrackedItem(
			instance,
			true
		)
	end

	return self
end

function ZonePlusNext:UntrackItem(
	instance: Instance,
	fireExit: boolean?
)
	local record =
		self._trackedItems[instance]

	if record == nil then
		return self
	end

	local connection =
		self._itemConnections[instance]

	if connection then
		connection:Disconnect()
		self._itemConnections[instance] = nil
	end

	if fireExit ~= false
		and record.state.inside
	then
		self:_commitItemState(
			instance,
			record.state,
			false
		)
	end

	self._trackedItems[instance] = nil

	updateZoneSchedulerResidency(self)
	return self
end

function ZonePlusNext:Contains(subject: any): boolean
	if typeof(subject) == "Vector3" then
		return self:ContainsPoint(subject)
	end

	if typeof(subject) == "Instance" then
		if subject:IsA("Player") then
			return self:FindPlayer(
				subject :: Player
			)
		end

		return self:FindItem(
			subject :: Instance
		)
	end

	error(
		"Contains expects a Player, Instance, or Vector3",
		2
	)
end

function ZonePlusNext:TrackItems(
	instances: {Instance},
	immediate: boolean?
)
	assert(
		type(instances) == "table",
		"TrackItems expects an array"
	)

	for index, instance in ipairs(instances) do
		assert(
			typeof(instance) == "Instance",
			(
				"TrackItems item #%d must be an Instance"
			):format(index)
		)

		self:TrackItem(
			instance,
			immediate
		)
	end

	return self
end

function ZonePlusNext:UntrackItems(
	instances: {Instance},
	fireExit: boolean?
)
	assert(
		type(instances) == "table",
		"UntrackItems expects an array"
	)

	for index, instance in ipairs(instances) do
		assert(
			typeof(instance) == "Instance",
			(
				"UntrackItems item #%d must be an Instance"
			):format(index)
		)

		self:UntrackItem(
			instance,
			fireExit
		)
	end

	return self
end

function ZonePlusNext:IsItemTracked(
	instance: Instance
): boolean
	return self._trackedItems[instance] ~= nil
end

function ZonePlusNext:GetItemState(
	instance: Instance
): ItemZoneState
	local record =
		self._trackedItems[instance]

	if record == nil then
		return {
			Tracked = false,
			Inside = false,
			Pending = false,
			PendingInside = nil,
			PendingSeconds = 0,
		}
	end

	local state = record.state
	local pendingSeconds = 0

	if state.pendingSince then
		pendingSeconds = math.max(
			0,
			os.clock()
			- state.pendingSince
		)
	end

	return {
		Tracked = true,
		Inside = state.inside,
		Pending =
			state.pendingInside ~= nil,
		PendingInside =
			state.pendingInside,
		PendingSeconds =
			pendingSeconds,
	}
end

function ZonePlusNext:GetPlayerState(player: Player): PlayerZoneState
	local state = self._playerStates[player]
	local now = os.clock()

	local pendingSeconds = 0
	if state and state.pendingSince then
		pendingSeconds = math.max(0, now - state.pendingSince)
	end

	return {
		Inside = state ~= nil and state.inside,
		Pending = state ~= nil and state.pendingInside ~= nil,
		PendingInside = if state then state.pendingInside else nil,
		PendingSeconds = pendingSeconds,
		EntryTime = self:GetEntryTime(player),
		ExitTime = self:GetExitTime(player),
		TimeInside = self:GetTimeInside(player),
	}
end

function ZonePlusNext:IsPlayerInside(player: Player): boolean
	local state = self._playerStates[player]
	return state ~= nil and state.inside
end

function ZonePlusNext:IsItemInside(instance: Instance): boolean
	local record = self._trackedItems[instance]
	return record ~= nil and record.state.inside
end

function ZonePlusNext:GetPlayers(): {Player}
	local result = {}

	for player, state in pairs(self._playerStates) do
		if state.inside then
			table.insert(result, player)
		end
	end

	return result
end

function ZonePlusNext:GetItems(): {Instance}
	local result = {}

	for instance, record in pairs(self._trackedItems) do
		if record.state.inside then
			table.insert(result, instance)
		end
	end

	return result
end

function ZonePlusNext:GetOccupancy(): number
	return self._occupancy
end

function ZonePlusNext:IsEmpty(): boolean
	return self._occupancy == 0
end

function ZonePlusNext:IsOccupied(): boolean
	return self._occupancy > 0
end

function ZonePlusNext:GetCapacity(): number?
	return self.Capacity
end

function ZonePlusNext:IsFull(): boolean
	return self.Capacity ~= nil and self._occupancy >= self.Capacity
end

function ZonePlusNext:GetRemainingCapacity(): number?
	if self.Capacity == nil then
		return nil
	end
	return math.max(0, self.Capacity - self._occupancy)
end

function ZonePlusNext:CanAcceptPlayer(player: Player?): boolean
	if player ~= nil and self:IsPlayerInside(player) then
		return true
	end
	return not self:IsFull()
end

function ZonePlusNext:GetInfo(): ZoneInfo
	return {
		Name = self.Name,
		Enabled = self.Enabled,
		Priority = self.Priority,
		Occupancy = self._occupancy,
		Capacity = self.Capacity,
		Full = self:IsFull(),
		Tags = self:GetTags(),
		PartCount = #self._parts,
	}
end

function ZonePlusNext:SetName(name: string)
	assert(not self._destroyed and not self._destroying, "Cannot rename a destroyed zone")
	assert(type(name) == "string" and name ~= "", "Zone name must be a non-empty string")
	if self.Name == name then
		return
	end
	self.Name = name
	requestZoneListRebuild()
end

function ZonePlusNext:SetCapacity(capacity: number?)
	assert(not self._destroyed and not self._destroying, "Cannot change a destroyed zone")
	if capacity == nil then
		self.Capacity = nil
	else
		self.Capacity = math.floor(requireNonNegativeFinite(capacity, "Capacity"))
	end
	self.occupancyChanged:Fire(self._occupancy, self.Capacity, self)
end

function ZonePlusNext:SetEnabled(enabled: boolean)
	assert(not self._destroyed and not self._destroying, "Cannot change a destroyed zone")

	enabled = not not enabled
	if self.Enabled == enabled then
		return
	end

	self.Enabled = enabled
	self._accumulator = 0
	self._nextStepAt = 0

	if not enabled then
		for player, state in pairs(self._playerStates) do
			state.pendingInside = nil
			state.pendingSince = nil
			if state.inside then
				self:_commitPlayerState(player, state, false)
			end
		end

		table.clear(self._playerStates)

		for instance, record in pairs(self._trackedItems) do
			record.state.pendingInside = nil
			record.state.pendingSince = nil
			if record.state.inside then
				self:_commitItemState(instance, record.state, false)
			end
		end
	end

	updateZoneSchedulerResidency(self)
	self.enabledChanged:Fire(enabled)
end

function ZonePlusNext:Enable()
	self:SetEnabled(true)
	return self
end

function ZonePlusNext:Disable()
	self:SetEnabled(false)
	return self
end

function ZonePlusNext:ToggleEnabled(): boolean
	self:SetEnabled(not self.Enabled)
	return self.Enabled
end

function ZonePlusNext:SetTrackPlayers(enabled: boolean, fireExits: boolean?)
	assert(not self._destroyed and not self._destroying, "Cannot change a destroyed zone")

	enabled = not not enabled
	if self.TrackPlayers == enabled then
		return
	end

	self.TrackPlayers = enabled

	if not enabled then
		local oldOccupancy = self._occupancy

		for player, state in pairs(self._playerStates) do
			if fireExits ~= false and state.inside then
				self:_commitPlayerState(player, state, false)
			end
		end

		table.clear(self._playerStates)
		clearZoneMemberships(self)

		if fireExits == false and oldOccupancy > 0 then
			self._occupancy = 0
			self.occupancyChanged:Fire(0, self.Capacity, self)
		end
	end

	updateZoneSchedulerResidency(self)
end

function ZonePlusNext:GetIndexMode(): (IndexMode, IndexMode)
	local effective: IndexMode = if self._indexDynamic then "Dynamic" else "Static"
	return self.IndexMode, effective
end

function ZonePlusNext:SetIndexMode(mode: IndexMode)
	assert(not self._destroyed and not self._destroying, "Cannot change a destroyed zone")

	local nextMode = validateIndexMode(mode)
	if self.IndexMode == nextMode then
		return
	end

	removeDynamicZone(self)
	self.IndexMode = nextMode
	self._indexDynamic = nextMode == "Dynamic"

	staticTreeDirty = true

	if self._indexDynamic then
		dynamicDirtyZones[self] = true
	end
end

function ZonePlusNext:SetBroadPhase(enabled: boolean)
	assert(not self._destroyed and not self._destroying, "Cannot change a destroyed zone")
	self.BroadPhase = not not enabled
	updateZoneSchedulerResidency(self)
end

function ZonePlusNext:SetUpdateInterval(seconds: number)
	assert(not self._destroyed and not self._destroying, "Cannot change a destroyed zone")
	self.UpdateInterval = clampInterval(seconds)
	self._nextStepAt = 0
end

function ZonePlusNext:SetDetection(mode: DetectionMode)
	assert(not self._destroyed and not self._destroying, "Cannot change a destroyed zone")
	self.Detection = validateDetection(mode)
end

function ZonePlusNext:SetPadding(padding: number | Vector3)
	assert(not self._destroyed and not self._destroying, "Cannot change a destroyed zone")
	local value = paddingToVector(padding)
	assert(isFiniteVector3(value), "Padding must be finite")
	self.Padding = value
	self:_markGeometryDirty()
end

function ZonePlusNext:SetDelays(enterDelay: number, exitDelay: number?)
	assert(not self._destroyed and not self._destroying, "Cannot change a destroyed zone")

	self.EnterDelay = requireNonNegativeFinite(enterDelay, "EnterDelay")
	self.ExitDelay = requireNonNegativeFinite(
		if exitDelay == nil then enterDelay else exitDelay,
		"ExitDelay"
	)

	return self
end

function ZonePlusNext:SetPlayerFilter(filter: ((Player) -> boolean)?)
	assert(not self._destroyed and not self._destroying, "Cannot change a destroyed zone")
	assert(filter == nil or type(filter) == "function", "PlayerFilter must be a function or nil")

	self.PlayerFilter = filter
	self._filterErrorActive = false
	return self
end

function ZonePlusNext:SetPriority(priority: number)
	assert(not self._destroyed and not self._destroying, "Cannot change a destroyed zone")
	self.Priority = requireFiniteNumber(priority, "Priority")
	requestZoneListRebuild()
end

function ZonePlusNext:AddTag(tag: string)
	assert(not self._destroyed and not self._destroying, "Cannot change a destroyed zone")
	assert(type(tag) == "string" and tag ~= "", "Tag must be a non-empty string")
	if self._tags[tag] then
		return
	end
	self._tags[tag] = true
	requestZoneListRebuild()
end

function ZonePlusNext:RemoveTag(tag: string)
	assert(not self._destroyed and not self._destroying, "Cannot change a destroyed zone")
	if not self._tags[tag] then
		return
	end
	self._tags[tag] = nil
	requestZoneListRebuild()
end

function ZonePlusNext:AddTags(tags: {string})
	assert(not self._destroyed and not self._destroying, "Cannot change a destroyed zone")
	assert(type(tags) == "table", "AddTags expects an array")

	local changed = false

	for _, tag in ipairs(tags) do
		assert(type(tag) == "string" and tag ~= "", "Tags must be non-empty strings")

		if not self._tags[tag] then
			self._tags[tag] = true
			changed = true
		end
	end

	if changed then
		requestZoneListRebuild()
	end

	return self
end

function ZonePlusNext:RemoveTags(tags: {string})
	assert(not self._destroyed and not self._destroying, "Cannot change a destroyed zone")
	assert(type(tags) == "table", "RemoveTags expects an array")

	local changed = false

	for _, tag in ipairs(tags) do
		assert(type(tag) == "string" and tag ~= "", "Tags must be non-empty strings")

		if self._tags[tag] then
			self._tags[tag] = nil
			changed = true
		end
	end

	if changed then
		requestZoneListRebuild()
	end

	return self
end

function ZonePlusNext:SetTags(tags: {string})
	assert(not self._destroyed and not self._destroying, "Cannot change a destroyed zone")
	assert(type(tags) == "table", "SetTags expects an array")

	local nextTags: {[string]: boolean} = {}

	for _, tag in ipairs(tags) do
		assert(type(tag) == "string" and tag ~= "", "Tags must be non-empty strings")
		nextTags[tag] = true
	end

	self._tags = nextTags
	requestZoneListRebuild()
	return self
end

function ZonePlusNext:HasTag(tag: string): boolean
	return self._tags[tag] == true
end

function ZonePlusNext:GetTags(): {string}
	local result = {}
	for tag in pairs(self._tags) do
		table.insert(result, tag)
	end
	table.sort(result)
	return result
end

function ZonePlusNext:HasAnyTag(tags: {string}): boolean
	assert(type(tags) == "table", "HasAnyTag expects an array")
	for _, tag in ipairs(tags) do
		assert(type(tag) == "string" and tag ~= "", "Tags must be non-empty strings")
		if self._tags[tag] then
			return true
		end
	end
	return false
end

function ZonePlusNext:HasAllTags(tags: {string}): boolean
	assert(type(tags) == "table", "HasAllTags expects an array")
	for _, tag in ipairs(tags) do
		assert(type(tag) == "string" and tag ~= "", "Tags must be non-empty strings")
		if not self._tags[tag] then
			return false
		end
	end
	return true
end

function ZonePlusNext:Apply(options: ZoneOptions)
	assert(not self._destroyed and not self._destroying, "Cannot change a destroyed zone")
	assert(type(options) == "table", "Apply expects a ZoneOptions table")

	if options.Name ~= nil then
		self:SetName(options.Name)
	end

	if options.UpdateInterval ~= nil then
		self:SetUpdateInterval(options.UpdateInterval)
	end

	if options.Detection ~= nil then
		self:SetDetection(options.Detection)
	end

	if options.Padding ~= nil then
		self:SetPadding(options.Padding)
	end

	if options.Priority ~= nil then
		self:SetPriority(options.Priority)
	end

	if options.Capacity ~= nil then
		self:SetCapacity(options.Capacity)
	end

	if options.TrackPlayers ~= nil then
		self:SetTrackPlayers(options.TrackPlayers)
	end

	if options.BroadPhase ~= nil then
		self:SetBroadPhase(options.BroadPhase)
	end

	if options.IndexMode ~= nil then
		self:SetIndexMode(options.IndexMode)
	end

	if options.EnterDelay ~= nil or options.ExitDelay ~= nil then
		self:SetDelays(
			options.EnterDelay or self.EnterDelay,
			options.ExitDelay or self.ExitDelay
		)
	end

	if options.PlayerFilter ~= nil then
		self:SetPlayerFilter(options.PlayerFilter)
	end

	if options.Tags ~= nil then
		self:SetTags(options.Tags)
	end

	if options.AutoDestroyWithContainer ~= nil then
		self.AutoDestroyWithContainer = not not options.AutoDestroyWithContainer
	end

	return self
end

function ZonePlusNext:GetStats(): ZoneStats
	return table.clone(self._stats)
end

function ZonePlusNext:ResetStats()
	self._stats.Checks = 0
	self._stats.Hits = 0
	self._stats.Misses = 0
	self._stats.Enters = 0
	self._stats.Exits = 0
	self._stats.Errors = 0
	self._stats.BroadPhaseQueries = 0
	self._stats.BroadPhaseFallbacks = 0
	self._stats.CandidatePlayers = 0
	self._stats.PrecisePlayerChecks = 0
	self._stats.CellsVisited = 0
	self._stats.LastCheckSeconds = 0
	self._stats.TotalCheckSeconds = 0
end

function ZonePlusNext.ResetGlobalStats()
	schedulerTicks = 0
	globalChecks = 0
	globalErrors = 0
	globalBroadPhaseQueries = 0
	globalBroadPhaseFallbacks = 0
	globalCandidatePlayers = 0
	globalPrecisePlayerChecks = 0
	globalCellsVisited = 0
	spatialRebuilds = 0
	zoneIndexRebuilds = 0
	zoneIndexAutoPromotions = 0
	schedulerCandidateZones = 0
	schedulerSkippedZones = 0
	schedulerSteps = 0
	schedulerDeferredZones = 0
	schedulerBudgetHits = 0
	schedulerStepLimitHits = 0
	schedulerBudgetOverruns = 0
	schedulerLastFrameSeconds = 0
	schedulerPeakFrameSeconds = 0
	schedulerLastCandidateSeconds = 0
	schedulerPeakCandidateSeconds = 0
	schedulerLastWorkSeconds = 0
	schedulerPeakWorkSeconds = 0
	globalCheckSeconds = 0
end

function ZonePlusNext:Destroy()
	if self._destroyed or self._destroying then
		return
	end

	self._destroying = true
	self.destroying:Fire(self)

	-- Commit final exits while geometry/history APIs are still valid.
	for player, state in pairs(self._playerStates) do
		if state.inside then
			self:_commitPlayerState(player, state, false)
		end
	end

	for instance, record in pairs(self._trackedItems) do
		if record.state.inside then
			self:_commitItemState(instance, record.state, false)
		end
	end

	for _, connection in ipairs(self._containerConnections) do
		connection:Disconnect()
	end
	table.clear(self._containerConnections)

	for part, connections in pairs(self._partConnections) do
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		self._partConnections[part] = nil
	end

	for instance, connection in pairs(self._itemConnections) do
		connection:Disconnect()
		self._itemConnections[instance] = nil
	end

	clearZoneMemberships(self)
	table.clear(self._playerStates)
	table.clear(self._playerHistory)
	table.clear(self._trackedItems)
	table.clear(self._parts)
	table.clear(self._invalidParts)
	table.clear(self._tags)

	self._destroyed = true
	self._destroying = false

	schedulerAlwaysZones[self] = nil
	removeDynamicZone(self)
	zones[self] = nil
	staticTreeDirty = true
	requestZoneListRebuild()

	self.playerEntered:Destroy()
	self.playerExited:Destroy()
	self.itemEntered:Destroy()
	self.itemExited:Destroy()
	self.partsChanged:Destroy()
	self.enabledChanged:Destroy()
	self.occupancyChanged:Destroy()
	self.destroying:Destroy()

	if self._ownedContainer and typeof(self.Container) == "Instance" then
		pcall(function()
			(self.Container :: Instance):Destroy()
		end)
	end

	stopSchedulerIfUnused()
end



-- ============================================================
-- v1 Query Engine
-- ============================================================

local function zoneMatchesCriteria(zone: AnyZone, options: ZoneQueryOptions?): boolean
	if zone._destroyed or zone._destroying then
		return false
	end

	if options == nil then
		return true
	end

	if options.Enabled ~= nil and zone.Enabled ~= options.Enabled then
		return false
	end
	if options.MinPriority ~= nil and zone.Priority < options.MinPriority then
		return false
	end
	if options.MaxPriority ~= nil and zone.Priority > options.MaxPriority then
		return false
	end
	if options.MinOccupancy ~= nil then
		local minimum = math.floor(requireNonNegativeFinite(options.MinOccupancy, "MinOccupancy"))
		if zone._occupancy < minimum then
			return false
		end
	end
	if options.MaxOccupancy ~= nil then
		local maximum = math.floor(requireNonNegativeFinite(options.MaxOccupancy, "MaxOccupancy"))
		if zone._occupancy > maximum then
			return false
		end
	end
	if options.Full ~= nil then
		assert(type(options.Full) == "boolean", "Full must be a boolean")
		if zone:IsFull() ~= options.Full then
			return false
		end
	end

	if options.RequireTags then
		for _, tag in ipairs(options.RequireTags) do
			assert(type(tag) == "string" and tag ~= "", "RequireTags must contain non-empty strings")
			if not zone:HasTag(tag) then
				return false
			end
		end
	end

	if options.ExcludeTags then
		for _, tag in ipairs(options.ExcludeTags) do
			assert(type(tag) == "string" and tag ~= "", "ExcludeTags must contain non-empty strings")
			if zone:HasTag(tag) then
				return false
			end
		end
	end

	return true
end

local function getZoneCandidates(options: ZoneQueryOptions?): {AnyZone}
	if options and options.RequireTags and #options.RequireTags > 0 then
		local best: {AnyZone}? = nil
		for _, tag in ipairs(options.RequireTags) do
			assert(type(tag) == "string" and tag ~= "", "RequireTags must contain non-empty strings")
			local bucket = zoneTagIndex[tag]
			if bucket == nil then
				return {}
			end
			if best == nil or #bucket < #best then
				best = bucket
			end
		end
		return best or {}
	end

	return zoneList
end

local function intersectZoneCandidates(spatial: {AnyZone}, semantic: {AnyZone}): {AnyZone}
	if semantic == zoneList then
		return spatial
	end

	if #spatial == 0 or #semantic == 0 then
		return {}
	end

	local smaller = spatial
	local larger = semantic

	if #semantic < #spatial then
		smaller = semantic
		larger = spatial
	end

	local allowed: {[AnyZone]: boolean} = {}
	for _, zone in ipairs(larger) do
		allowed[zone] = true
	end

	local result = {}
	for _, zone in ipairs(smaller) do
		if allowed[zone] then
			table.insert(result, zone)
		end
	end

	sortZonesByRegistryOrder(result)
	return result
end

local function getSpatialZoneCandidates(
	minimum: Vector3,
	maximum: Vector3,
	options: ZoneQueryOptions?
): {AnyZone}
	local semantic = getZoneCandidates(options)
	local spatial = collectZoneIndexAABB(minimum, maximum)

	if spatial == nil then
		return semantic
	end

	return intersectZoneCandidates(spatial, semantic)
end

local function limitZones(list: {AnyZone}, options: ZoneQueryOptions?): {AnyZone}
	if options and options.Limit ~= nil then
		local limit = math.max(0, math.floor(requireNonNegativeFinite(options.Limit, "Limit")))
		while #list > limit do
			table.remove(list)
		end
	end
	return list
end

local function getZoneBounds(zone: AnyZone): (Vector3?, Vector3?)
	local cf, size = zone:GetBounds()
	if cf == nil or size == nil then
		return nil, nil
	end
	local half = size * 0.5
	return cf.Position - half, cf.Position + half
end

local function playerCandidatesForAABB(minimum: Vector3, maximum: Vector3): {Player}
	-- Query APIs can be used even when no zones exist. In that case there is no
	-- zone scheduler heartbeat to invalidate movement, so force a fresh snapshot.
	if schedulerConnection == nil then
		invalidateSpatialIndex()
	end
	ensurePlayerSpatialIndex()

	local x0, x1, y0, y1, z0, z1 = getCellRange(minimum, maximum, spatialCellSize)
	local cells = getCellCount(x0, x1, y0, y1, z0, z1)

	if not spatialEnabled or cells > spatialMaxQueryCells then
		return Players:GetPlayers()
	end

	local result: {Player} = {}
	local seen: {[Player]: boolean} = {}

	for x = x0, x1 do
		for y = y0, y1 do
			for z = z0, z1 do
				local bucket = playerBuckets[cellKey(x, y, z)]
				if bucket then
					for _, player in ipairs(bucket) do
						if not seen[player] then
							seen[player] = true
							table.insert(result, player)
						end
					end
				end
			end
		end
	end

	for _, player in ipairs(oversizedPlayers) do
		if not seen[player] then
			seen[player] = true
			table.insert(result, player)
		end
	end

	return result
end

function ZonePlusNext.EnableHistory(config: HistoryConfig?)
	config = config or {}

	if config.Duration ~= nil then
		local value = requireFiniteNumber(config.Duration, "History Duration")
		assert(value > 0, "History Duration must be greater than zero")
		positionHistoryDuration = value
	end

	if config.SampleRate ~= nil then
		local value = requireFiniteNumber(config.SampleRate, "History SampleRate")
		assert(value > 0 and value <= 240, "History SampleRate must be > 0 and <= 240")
		positionHistorySampleRate = value
	end

	if config.TransitionLimit ~= nil then
		local value = math.floor(requireFiniteNumber(config.TransitionLimit, "TransitionLimit"))
		assert(value >= 4, "TransitionLimit must be at least 4")
		globalTransitionHistoryLimit = value
	end

	if config.Position ~= nil then
		positionHistoryEnabled = not not config.Position
	end

	updatePositionSamplerConnection()
end

function ZonePlusNext.GetHistoryConfig(): HistoryConfig
	return {
		Position = positionHistoryEnabled,
		Duration = positionHistoryDuration,
		SampleRate = positionHistorySampleRate,
		TransitionLimit = globalTransitionHistoryLimit,
	}
end

function ZonePlusNext.ClearHistory(player: Player?)
	if player then
		positionHistory[player] = nil
		for zone in pairs(zones) do
			zone._playerHistory[player] = nil
		end
	else
		table.clear(positionHistory)
		for zone in pairs(zones) do
			table.clear(zone._playerHistory)
		end
	end
end

function ZonePlusNext.GetPositionHistory(player: Player): {PositionSample}
	local samples = positionHistory[player]
	if samples == nil then
		return {}
	end
	return table.clone(samples)
end

function ZonePlusNext.GetPositionAt(player: Player, secondsAgo: number): (Vector3?, Vector3?)
	local amount = requireNonNegativeFinite(secondsAgo, "secondsAgo")
	local samples = positionHistory[player]
	if samples == nil or #samples == 0 then
		return nil, nil
	end

	local target = os.clock() - amount
	local previous: PositionSample? = nil

	for _, sample in ipairs(samples) do
		if sample.Time >= target then
			if previous == nil then
				return sample.Position, sample.Velocity
			end

			local span = sample.Time - previous.Time
			if span <= EPSILON then
				return sample.Position, sample.Velocity
			end

			local alpha = math.clamp((target - previous.Time) / span, 0, 1)
			return previous.Position:Lerp(sample.Position, alpha), previous.Velocity:Lerp(sample.Velocity, alpha)
		end
		previous = sample
	end

	local last = samples[#samples]
	return last.Position, last.Velocity
end

function ZonePlusNext:GetPlayerHistory(player: Player, withinSeconds: number?): {TransitionRecord}
	local history = self._playerHistory[player]
	if history == nil then
		return {}
	end

	if withinSeconds == nil then
		return table.clone(history)
	end

	local window = requireNonNegativeFinite(withinSeconds, "withinSeconds")
	local cutoff = os.clock() - window
	local result: {TransitionRecord} = {}
	for _, record in ipairs(history) do
		if record.Time >= cutoff then
			table.insert(result, record)
		end
	end
	return result
end

function ZonePlusNext:GetEntryTime(player: Player): number?
	local history = self._playerHistory[player]
	if history == nil then return nil end
	for index = #history, 1, -1 do
		if history[index].Inside then
			return history[index].Time
		end
	end
	return nil
end

function ZonePlusNext:GetExitTime(player: Player): number?
	local history = self._playerHistory[player]
	if history == nil then return nil end
	for index = #history, 1, -1 do
		if not history[index].Inside then
			return history[index].Time
		end
	end
	return nil
end

function ZonePlusNext:GetTimeInside(player: Player): number
	if not self:IsPlayerInside(player) then
		return 0
	end
	local entered = self:GetEntryTime(player)
	if entered == nil then
		return 0
	end
	return math.max(0, os.clock() - entered)
end

function ZonePlusNext:InsideFor(player: Player, seconds: number): boolean
	local duration = requireNonNegativeFinite(seconds, "seconds")
	return self:IsPlayerInside(player) and self:GetTimeInside(player) >= duration
end

function ZonePlusNext:WasPlayerInside(player: Player, secondsAgo: number): boolean
	local target = os.clock() - requireNonNegativeFinite(secondsAgo, "secondsAgo")
	local history = self._playerHistory[player]

	if history == nil or #history == 0 then
		return self:IsPlayerInside(player) and secondsAgo == 0
	end

	local state = false
	for _, record in ipairs(history) do
		if record.Time > target then
			break
		end
		state = record.Inside
	end
	return state
end

function ZonePlusNext:EnteredWithin(player: Player, seconds: number): boolean
	local cutoff = os.clock() - requireNonNegativeFinite(seconds, "seconds")
	local history = self._playerHistory[player]
	if history == nil then return false end
	for index = #history, 1, -1 do
		local record = history[index]
		if record.Time < cutoff then break end
		if record.Inside then return true end
	end
	return false
end

function ZonePlusNext:ExitedWithin(player: Player, seconds: number): boolean
	local cutoff = os.clock() - requireNonNegativeFinite(seconds, "seconds")
	local history = self._playerHistory[player]
	if history == nil then return false end
	for index = #history, 1, -1 do
		local record = history[index]
		if record.Time < cutoff then break end
		if not record.Inside then return true end
	end
	return false
end

function ZonePlusNext:CrossedBy(player: Player, seconds: number?): boolean
	local window = seconds or math.huge
	local history = self:GetPlayerHistory(player, if window == math.huge then nil else window)
	local entered = false
	local exited = false
	for _, record in ipairs(history) do
		if record.Inside then entered = true else exited = true end
	end
	return entered and exited
end

function ZonePlusNext:GetPlayersDuring(seconds: number): {Player}
	local result = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if self:IsPlayerInside(player) or self:EnteredWithin(player, seconds) or self:ExitedWithin(player, seconds) then
			table.insert(result, player)
		end
	end
	return result
end

function ZonePlusNext:GetEntryDirection(player: Player): TransitionRecord?
	local history = self._playerHistory[player]
	if history == nil then return nil end
	for index = #history, 1, -1 do
		local record = history[index]
		if record.Inside then
			return table.clone(record)
		end
	end
	return nil
end

function ZonePlusNext:GetPlayersEnteringFrom(side: string, withinSeconds: number?): {Player}
	local result = {}
	local cutoff = if withinSeconds then os.clock() - requireNonNegativeFinite(withinSeconds, "withinSeconds") else -math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		local history = self._playerHistory[player]
		if history then
			for index = #history, 1, -1 do
				local record = history[index]
				if record.Time < cutoff then break end
				if record.Inside and record.Side == side then
					table.insert(result, player)
					break
				end
			end
		end
	end
	return result
end

function ZonePlusNext.QueryZones(options: ZoneQueryOptions?): {AnyZone}
	queryExecutions += 1
	local result = {}
	local candidates = getZoneCandidates(options)
	local limit = if options and options.Limit ~= nil
		then math.floor(requireNonNegativeFinite(options.Limit, "Limit"))
		else nil

	if limit == 0 then
		return result
	end

	queryCandidates += #candidates
	for _, zone in ipairs(candidates) do
		if zoneMatchesCriteria(zone, options) then
			table.insert(result, zone)
			if limit ~= nil and #result >= limit then
				break
			end
		end
	end

	queryResults += #result
	return result
end

function ZonePlusNext.GetZonesByTag(tag: string): {AnyZone}
	assert(type(tag) == "string" and tag ~= "", "GetZonesByTag tag must be a non-empty string")
	local result = {}
	local bucket = zoneTagIndex[tag]
	if bucket then
		for _, zone in ipairs(bucket) do
			if not zone._destroyed and not zone._destroying then
				table.insert(result, zone)
			end
		end
	end
	return result
end

function ZonePlusNext.GetZonesByTags(tags: {string}, matchAll: boolean?): {AnyZone}
	assert(type(tags) == "table", "GetZonesByTags expects an array of tags")
	if matchAll == nil or matchAll == true then
		return ZonePlusNext.QueryZones({
			RequireTags = tags,
		})
	end

	assert(type(matchAll) == "boolean", "matchAll must be a boolean")
	local result = {}
	local seen: {[AnyZone]: boolean} = {}

	for _, tag in ipairs(tags) do
		assert(type(tag) == "string" and tag ~= "", "Tags must be non-empty strings")
		local bucket = zoneTagIndex[tag]
		if bucket then
			for _, zone in ipairs(bucket) do
				if not zone._destroyed and not zone._destroying and not seen[zone] then
					seen[zone] = true
					table.insert(result, zone)
				end
			end
		end
	end

	table.sort(result, function(a, b)
		if a.Priority == b.Priority then
			return a._creationIndex < b._creationIndex
		end
		return a.Priority > b.Priority
	end)

	return result
end

local function getManagementLimit(options: ZoneQueryOptions?): number?
	if options == nil or options.Limit == nil then
		return nil
	end
	return math.floor(requireNonNegativeFinite(options.Limit, "Limit"))
end

function ZonePlusNext.SetZonesEnabled(enabled: boolean, options: ZoneQueryOptions?): number
	local changed = 0
	local matched = 0
	local limit = getManagementLimit(options)
	local snapshot = shallowCopy(getZoneCandidates(options))
	local target = not not enabled

	for _, zone in ipairs(snapshot) do
		if limit ~= nil and matched >= limit then
			break
		end
		if zoneMatchesCriteria(zone, options) then
			matched += 1
			if zone.Enabled ~= target then
				zone:SetEnabled(target)
				changed += 1
			end
		end
	end

	return changed
end

function ZonePlusNext.DestroyZones(options: ZoneQueryOptions?): number
	local destroyed = 0
	local matched = 0
	local limit = getManagementLimit(options)
	local snapshot = shallowCopy(getZoneCandidates(options))

	for _, zone in ipairs(snapshot) do
		if limit ~= nil and matched >= limit then
			break
		end
		if zoneMatchesCriteria(zone, options) then
			matched += 1
			zone:Destroy()
			destroyed += 1
		end
	end

	return destroyed
end

function ZonePlusNext.QueryPoint(point: Vector3, options: ZoneQueryOptions?): {AnyZone}
	assert(isFiniteVector3(point), "QueryPoint point must be finite")
	queryExecutions += 1
	local result = {}
	local candidates = getSpatialZoneCandidates(point, point, options)
	local limit = getManagementLimit(options)

	if limit == 0 then
		return result
	end

	queryCandidates += #candidates
	for _, zone in ipairs(candidates) do
		if not zoneMatchesCriteria(zone, options) then continue end
		local minimum, maximum = getZoneBounds(zone)
		if minimum == nil or maximum == nil then continue end
		if point.X < minimum.X or point.X > maximum.X or point.Y < minimum.Y or point.Y > maximum.Y or point.Z < minimum.Z or point.Z > maximum.Z then
			continue
		end
		if zone:_containsPointGeometry(point) then
			table.insert(result, zone)
			if limit ~= nil and #result >= limit then
				break
			end
		end
	end

	queryResults += #result
	return result
end

function ZonePlusNext.QueryRadius(position: Vector3, radius: number, options: ZoneQueryOptions?): {AnyZone}
	assert(isFiniteVector3(position), "QueryRadius position must be finite")
	radius = requireNonNegativeFinite(radius, "radius")
	queryExecutions += 1

	local radiusSq = radius * radius
	local extent = Vector3.new(radius, radius, radius)
	local candidates = getSpatialZoneCandidates(position - extent, position + extent, options)
	local limit = getManagementLimit(options)
	local ranked = {}

	if limit == 0 then
		return {}
	end

	queryCandidates += #candidates

	for _, zone in ipairs(candidates) do
		if not zoneMatchesCriteria(zone, options) then continue end
		local minimum, maximum = getZoneBounds(zone)
		if minimum == nil or maximum == nil then continue end
		local distanceSquared = pointAABBDistanceSquared(position, minimum, maximum)
		if distanceSquared <= radiusSq then
			table.insert(ranked, {
				Zone = zone,
				DistanceSquared = distanceSquared,
			})
		end
	end

	table.sort(ranked, function(a, b)
		if a.DistanceSquared == b.DistanceSquared then
			return a.Zone.Priority > b.Zone.Priority
		end
		return a.DistanceSquared < b.DistanceSquared
	end)

	local result = {}
	local take = if limit == nil then #ranked else math.min(limit, #ranked)
	for index = 1, take do
		table.insert(result, ranked[index].Zone)
	end

	queryResults += #result
	return result
end

ZonePlusNext.QuerySphere = ZonePlusNext.QueryRadius

function ZonePlusNext.QueryBox(cframe: CFrame, size: Vector3, options: ZoneQueryOptions?): {AnyZone}
	assert(isFiniteVector3(size), "QueryBox size must be finite")
	assert(size.X >= 0 and size.Y >= 0 and size.Z >= 0, "QueryBox size must be non-negative")
	queryExecutions += 1
	local result = {}
	local queryMin, queryMax = orientedBoxWorldAABB(cframe, size)
	local candidates = getSpatialZoneCandidates(queryMin, queryMax, options)
	local limit = getManagementLimit(options)

	if limit == 0 then
		return result
	end

	queryCandidates += #candidates
	for _, zone in ipairs(candidates) do
		if not zoneMatchesCriteria(zone, options) then continue end
		local boundsCF, boundsSize = zone:GetBounds()
		if boundsCF == nil or boundsSize == nil then continue end
		if obbIntersects(cframe, size, boundsCF, boundsSize) then
			table.insert(result, zone)
			if limit ~= nil and #result >= limit then
				break
			end
		end
	end

	queryResults += #result
	return result
end

function ZonePlusNext:OverlapsPart(part: BasePart, precision: QueryPrecision?): boolean
	precision = precision or "Bounds"
	assert(precision == "Broad" or precision == "Bounds" or precision == "Exact", "invalid overlap precision")

	if self._destroyed then
		return false
	end

	if precision == "Broad" then
		local boundsCF, boundsSize = self:GetBounds()
		if boundsCF == nil or boundsSize == nil then
			return false
		end
		local zoneMin = boundsCF.Position - boundsSize * 0.5
		local zoneMax = boundsCF.Position + boundsSize * 0.5
		local partMin, partMax = orientedBoxWorldAABB(part.CFrame, part.Size)
		return aabbIntersects(zoneMin, zoneMax, partMin, partMax)
	end

	if precision == "Exact" and part:IsDescendantOf(Workspace) and part.CanQuery then
		local eligible = {}
		for _, zonePart in ipairs(self:GetParts()) do
			if self:_isPartActive(zonePart) and zonePart:IsDescendantOf(Workspace) and zonePart.CanQuery then
				table.insert(eligible, zonePart)
			end
		end

		if #eligible > 0 then
			queryExactOverlapQueries += 1
			local params = OverlapParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = eligible
			local success, results = pcall(function()
				return Workspace:GetPartsInPart(part, params)
			end)
			if success then
				return #results > 0
			end
		end
	end

	return self:_containsRootBounds(part)
end

function ZonePlusNext.QueryPart(part: BasePart, options: ZoneQueryOptions?): {AnyZone}
	queryExecutions += 1
	local result = {}
	local precision: QueryPrecision = if options and options.Precision then options.Precision else "Bounds"
	local partMin, partMax = orientedBoxWorldAABB(part.CFrame, part.Size)
	local candidates = getSpatialZoneCandidates(partMin, partMax, options)
	local limit = getManagementLimit(options)

	if limit == 0 then
		return result
	end

	queryCandidates += #candidates
	for _, zone in ipairs(candidates) do
		if not zoneMatchesCriteria(zone, options) then continue end
		if zone:OverlapsPart(part, precision) then
			table.insert(result, zone)
			if limit ~= nil and #result >= limit then
				break
			end
		end
	end

	queryResults += #result
	return result
end

function ZonePlusNext.QueryRay(origin: Vector3, direction: Vector3, options: ZoneQueryOptions?): {AnyZone}
	assert(isFiniteVector3(origin), "QueryRay origin must be finite")
	assert(isFiniteVector3(direction), "QueryRay direction must be finite")
	queryExecutions += 1
	local hits = {}
	local endpoint = origin + direction
	local queryMin = Vector3.new(
		math.min(origin.X, endpoint.X),
		math.min(origin.Y, endpoint.Y),
		math.min(origin.Z, endpoint.Z)
	)
	local queryMax = Vector3.new(
		math.max(origin.X, endpoint.X),
		math.max(origin.Y, endpoint.Y),
		math.max(origin.Z, endpoint.Z)
	)
	local candidates = getSpatialZoneCandidates(queryMin, queryMax, options)
	queryCandidates += #candidates

	for _, zone in ipairs(candidates) do
		if not zoneMatchesCriteria(zone, options) then continue end
		local minimum, maximum = getZoneBounds(zone)
		if minimum == nil or maximum == nil then continue end
		-- The index uses broad world bounds. Narrow-phase testing must
		-- use each part's orientation (including per-zone padding).
		local nearestT: number? = nil
		for _, part in ipairs(zone._parts) do
			if not zone:_isPartActive(part) then continue end
			local size = part.Size + zone.Padding * 2
			if size.X <= 0 or size.Y <= 0 or size.Z <= 0 then continue end
			local t = rayOrientedBox(origin, direction, part.CFrame, size)
			if t ~= nil and (nearestT == nil or t < nearestT) then
				nearestT = t
			end
		end
		if nearestT ~= nil then
			table.insert(hits, {Zone = zone, T = nearestT})
		end
	end
	table.sort(hits, function(a, b) return a.T < b.T end)
	local result = {}
	for _, hit in ipairs(hits) do
		table.insert(result, hit.Zone)
	end
	limitZones(result, options)
	queryResults += #result
	return result
end

function ZonePlusNext.QueryPath(startPosition: Vector3, endPosition: Vector3, options: ZoneQueryOptions?): {AnyZone}
	return ZonePlusNext.QueryRay(startPosition, endPosition - startPosition, options)
end

function ZonePlusNext.GetOverlappingZones(zone: AnyZone, options: ZoneQueryOptions?): {AnyZone}
	assert(type(zone) == "table" and getmetatable(zone) == ZonePlusNext, "GetOverlappingZones expects a zone")

	if zone._destroyed or zone._destroying then
		return {}
	end

	zone:_recomputeBounds()
	if not zone._boundsValid then
		return {}
	end

	local candidates = getSpatialZoneCandidates(zone._boundsMin, zone._boundsMax, options)
	local result = {}
	local limit = getManagementLimit(options)

	for _, other in ipairs(candidates) do
		if other ~= zone and zoneMatchesCriteria(other, options) then
			other:_recomputeBounds()

			if other._boundsValid and aabbIntersects(
				zone._boundsMin,
				zone._boundsMax,
				other._boundsMin,
				other._boundsMax
				) then
				table.insert(result, other)

				if limit ~= nil and #result >= limit then
					break
				end
			end
		end
	end

	return result
end

function ZonePlusNext:GetNearbyZones(radius: number, options: ZoneQueryOptions?): {AnyZone}
	radius = requireNonNegativeFinite(radius, "radius")

	local boundsCF = self:GetBounds()
	if boundsCF == nil then
		return {}
	end

	local result = ZonePlusNext.QueryRadius(boundsCF.Position, radius, options)

	for index = #result, 1, -1 do
		if result[index] == self then
			table.remove(result, index)
		end
	end

	return result
end

function ZonePlusNext.QueryDuring(zone: AnyZone, seconds: number): {Player}
	queryExecutions += 1
	local result = zone:GetPlayersDuring(seconds)
	queryCandidates += #Players:GetPlayers()
	queryResults += #result
	return result
end

function ZonePlusNext.GetNearestZones(position: Vector3, count: number?, options: ZoneQueryOptions?): {AnyZone}
	assert(isFiniteVector3(position), "GetNearestZones position must be finite")

	local desired = if count == nil then 1 else math.floor(requireNonNegativeFinite(count, "count"))

	if options and options.Limit ~= nil then
		desired = math.min(desired, math.floor(requireNonNegativeFinite(options.Limit, "Limit")))
	end

	if desired <= 0 then
		queryExecutions += 1
		return {}
	end

	queryExecutions += 1

	local candidates: {AnyZone}? = nil

	if zoneIndexEnabled and #zoneList > zoneIndexBruteForceThreshold then
		local radius = zoneIndexCellSize

		for _ = 1, 8 do
			local extent = Vector3.new(radius, radius, radius)
			local spatial = collectZoneIndexAABB(position - extent, position + extent)

			if spatial == nil then
				break
			end

			local combined = intersectZoneCandidates(spatial, getZoneCandidates(options))
			local probe = {}

			for _, zone in ipairs(combined) do
				if zoneMatchesCriteria(zone, options) then
					local minimum, maximum = getZoneBounds(zone)

					if minimum and maximum then
						table.insert(probe, {
							Zone = zone,
							DistanceSquared = pointAABBDistanceSquared(position, minimum, maximum),
						})
					end
				end
			end

			table.sort(probe, function(a, b)
				return a.DistanceSquared < b.DistanceSquared
			end)

			if #probe >= desired then
				local kth = probe[desired]

				if kth.DistanceSquared <= radius * radius then
					candidates = combined
					break
				end
			end

			radius *= 2
		end
	end

	if candidates == nil then
		candidates = getZoneCandidates(options)
		queryZoneIndexFallbacks += 1
	end

	queryCandidates += #candidates

	local ranked = {}

	for _, zone in ipairs(candidates) do
		if not zoneMatchesCriteria(zone, options) then
			continue
		end

		local minimum, maximum = getZoneBounds(zone)

		if minimum == nil or maximum == nil then
			continue
		end

		table.insert(ranked, {
			Zone = zone,
			DistanceSquared = pointAABBDistanceSquared(position, minimum, maximum),
		})
	end

	table.sort(ranked, function(a, b)
		if a.DistanceSquared == b.DistanceSquared then
			return a.Zone.Priority > b.Zone.Priority
		end
		return a.DistanceSquared < b.DistanceSquared
	end)

	local result = {}

	for index = 1, math.min(desired, #ranked) do
		table.insert(result, ranked[index].Zone)
	end

	queryResults += #result
	return result
end

function ZonePlusNext.GetNearestZone(subject: Vector3 | Player, options: ZoneQueryOptions?): (AnyZone?, number?)
	local position: Vector3?
	if typeof(subject) == "Vector3" then
		position = subject :: Vector3
		assert(isFiniteVector3(position), "GetNearestZone position must be finite")
	elseif typeof(subject) == "Instance" and (subject :: Instance):IsA("Player") then
		local root = getCharacterRoot((subject :: Player).Character)
		position = if root then root.Position else nil
	else
		error("GetNearestZone expects a Vector3 or Player", 2)
	end
	if position == nil then return nil, nil end
	local list = ZonePlusNext.GetNearestZones(position, 1, options)
	local zone = list[1]
	if zone == nil then return nil, nil end
	local minimum, maximum = getZoneBounds(zone)
	if minimum == nil or maximum == nil then return zone, nil end
	return zone, math.sqrt(pointAABBDistanceSquared(position, minimum, maximum))
end

function ZonePlusNext.QueryPlayersInRadius(position: Vector3, radius: number): {Player}
	assert(isFiniteVector3(position), "QueryPlayersInRadius position must be finite")
	radius = requireNonNegativeFinite(radius, "radius")
	queryExecutions += 1
	local extent = Vector3.new(radius, radius, radius)
	local candidates = playerCandidatesForAABB(position - extent, position + extent)
	queryCandidates += #candidates
	local result = {}
	local radiusSq = radius * radius
	for _, player in ipairs(candidates) do
		local root = getCharacterRoot(player.Character)
		if root then
			local delta = root.Position - position
			if delta:Dot(delta) <= radiusSq then
				table.insert(result, player)
			end
		end
	end
	queryResults += #result
	return result
end

function ZonePlusNext.QueryPlayersInBox(cframe: CFrame, size: Vector3): {Player}
	assert(isFiniteVector3(size), "QueryPlayersInBox size must be finite")
	assert(size.X >= 0 and size.Y >= 0 and size.Z >= 0, "QueryPlayersInBox size must be non-negative")
	local minimum, maximum = orientedBoxWorldAABB(cframe, size)
	queryExecutions += 1
	local candidates = playerCandidatesForAABB(minimum, maximum)
	queryCandidates += #candidates
	local result = {}
	for _, player in ipairs(candidates) do
		local root = getCharacterRoot(player.Character)
		if root and pointInsideOrientedBox(cframe, size, root.Position) then
			table.insert(result, player)
		end
	end
	queryResults += #result
	return result
end

function ZonePlusNext.GetNearestPlayers(subject: Vector3 | AnyZone, count: number?): {Player}
	local position: Vector3

	if typeof(subject) == "Vector3" then
		position = subject :: Vector3
		assert(isFiniteVector3(position), "GetNearestPlayers position must be finite")
	elseif type(subject) == "table" and getmetatable(subject) == ZonePlusNext then
		local zone = subject :: AnyZone
		if zone._destroyed or zone._destroying then
			return {}
		end
		local cf = zone:GetBounds()
		if cf == nil then
			return {}
		end
		position = cf.Position
	else
		error("GetNearestPlayers expects a Vector3 or ZonePlusNext zone", 2)
	end

	queryExecutions += 1
	local desired = if count == nil then 1 else math.floor(requireNonNegativeFinite(count, "count"))
	if desired <= 0 then
		return {}
	end

	local players = Players:GetPlayers()
	queryCandidates += #players
	local ranked = {}

	for _, player in ipairs(players) do
		local root = getCharacterRoot(player.Character)
		if root then
			local delta = root.Position - position
			table.insert(ranked, {
				Player = player,
				DistanceSquared = delta:Dot(delta),
			})
		end
	end

	table.sort(ranked, function(a, b)
		return a.DistanceSquared < b.DistanceSquared
	end)

	local result = {}
	for index = 1, math.min(desired, #ranked) do
		table.insert(result, ranked[index].Player)
	end

	queryResults += #result
	return result
end

local function isPlayerVisible(origin: Vector3, player: Player, options: VisibilityOptions?): boolean
	local root = getCharacterRoot(player.Character)
	if root == nil then return false end

	local direction = root.Position - origin
	local distance = direction.Magnitude
	if options and options.MaxDistance ~= nil then
		local maxDistance = requireNonNegativeFinite(options.MaxDistance, "MaxDistance")
		if distance > maxDistance then
			return false
		end
	end
	if distance <= EPSILON then return true end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if options and options.IgnoreInstances then options.IgnoreInstances else {}
	params.IgnoreWater = true

	queryVisibilityRays += 1
	local result = Workspace:Raycast(origin, direction, params)
	return result == nil or (player.Character ~= nil and result.Instance:IsDescendantOf(player.Character))
end

function ZonePlusNext.QueryVisible(origin: Vector3, players: {Player}?, options: VisibilityOptions?): {Player}
	queryExecutions += 1
	local candidates = players or Players:GetPlayers()
	queryCandidates += #candidates
	local result = {}
	for _, player in ipairs(candidates) do
		if isPlayerVisible(origin, player, options) then
			table.insert(result, player)
		end
	end
	queryResults += #result
	return result
end

function ZonePlusNext:CanSeePlayer(player: Player, origin: Vector3?, options: VisibilityOptions?): boolean
	if origin == nil then
		local cf = self:GetBounds()
		if cf == nil then return false end
		origin = cf.Position
	end
	return isPlayerVisible(origin, player, options)
end

function ZonePlusNext.PredictPosition(player: Player, seconds: number): Vector3?
	seconds = requireNonNegativeFinite(seconds, "seconds")
	local root = getCharacterRoot(player.Character)
	if root == nil then return nil end
	return root.Position + root.AssemblyLinearVelocity * seconds
end

function ZonePlusNext:PredictPlayerEntry(player: Player, horizon: number, step: number?): PredictionResult
	horizon = requireNonNegativeFinite(horizon, "horizon")
	local sampleStep = step or math.min(0.1, math.max(0.02, self.UpdateInterval))
	sampleStep = requireFiniteNumber(sampleStep, "step")
	assert(sampleStep > 0, "step must be greater than zero")

	local root = getCharacterRoot(player.Character)
	local velocity = if root then root.AssemblyLinearVelocity else Vector3.zero
	if root == nil then
		return {WillEnter = false, Time = nil, Position = nil, Velocity = velocity}
	end

	if self:FindPlayer(player) then
		return {WillEnter = true, Time = 0, Position = root.Position, Velocity = velocity}
	end

	local t = sampleStep
	while t <= horizon + EPSILON do
		local predicted = root.Position + velocity * t
		queryPredictionSamples += 1
		if self:ContainsPoint(predicted) then
			return {WillEnter = true, Time = t, Position = predicted, Velocity = velocity}
		end
		t += sampleStep
	end

	return {WillEnter = false, Time = nil, Position = nil, Velocity = velocity}
end

function ZonePlusNext:PredictIntersection(instance: Instance, velocity: Vector3, horizon: number, step: number?): PredictionResult
	horizon = requireNonNegativeFinite(horizon, "horizon")
	assert(isFiniteVector3(velocity), "velocity must be finite")
	local position = getItemPosition(instance)
	if position == nil then
		return {WillEnter = false, Time = nil, Position = nil, Velocity = velocity}
	end

	local sampleStep = requireFiniteNumber(step or 0.05, "step")
	assert(sampleStep > 0, "step must be greater than zero")
	local t = 0
	while t <= horizon + EPSILON do
		local predicted = position + velocity * t
		queryPredictionSamples += 1
		if self:ContainsPoint(predicted) then
			return {WillEnter = true, Time = t, Position = predicted, Velocity = velocity}
		end
		t += sampleStep
	end
	return {WillEnter = false, Time = nil, Position = nil, Velocity = velocity}
end

function ZonePlusNext.GetQueryStats(): QueryStats
	return {
		Executions = queryExecutions,
		Candidates = queryCandidates,
		Results = queryResults,
		VisibilityRays = queryVisibilityRays,
		ExactOverlapQueries = queryExactOverlapQueries,
		PredictionSamples = queryPredictionSamples,
		PositionSamples = queryPositionSamples,
		ZoneIndexQueries = queryZoneIndexQueries,
		ZoneIndexFallbacks = queryZoneIndexFallbacks,
		ZoneCellsVisited = queryZoneCellsVisited,
	}
end

function ZonePlusNext.ResetQueryStats()
	queryExecutions = 0
	queryCandidates = 0
	queryResults = 0
	queryVisibilityRays = 0
	queryExactOverlapQueries = 0
	queryPredictionSamples = 0
	queryPositionSamples = 0
	queryZoneIndexQueries = 0
	queryZoneIndexFallbacks = 0
	queryZoneCellsVisited = 0
end

function ZonePlusNext.GetCompactStats(): string
	local global = ZonePlusNext.GetGlobalStats()
	local query = ZonePlusNext.GetQueryStats()

	return string.format(
		"[ZonePlusNext v%s] zones=%d/%d members=%d checks=%d errors=%d queries=%d results=%d idx=%dS/%dD sched=%.2fms/%d",
		VERSION,
		global.EnabledZones,
		global.Zones,
		global.ActivePlayerMemberships,
		global.Checks,
		global.Errors,
		query.Executions,
		query.Results,
		global.StaticIndexedZones,
		global.DynamicIndexedZones,
		schedulerLastWorkSeconds * 1000,
		schedulerDeferredZones
	)
end

function ZonePlusNext.PrintStats()
	print(ZonePlusNext.GetCompactStats())
end

local QueryBuilder = {}
QueryBuilder.__index = QueryBuilder

local function newQueryBuilder(): any
	return setmetatable({
		_filters = {},
		_orFilters = {},
		_candidateProvider = nil,
		_sortPoint = nil,
		_limit = nil,
		_rootCache = {},
	}, QueryBuilder)
end

function QueryBuilder:_getRoot(player: Player): BasePart?
	local cached = self._rootCache[player]
	if cached == false then
		return nil
	end
	if cached ~= nil then
		return cached
	end

	local root = getCharacterRoot(player.Character)
	self._rootCache[player] = root or false
	return root
end

function QueryBuilder:_addFilter(predicate: (Player) -> boolean)
	table.insert(self._filters, predicate)
	return self
end

function QueryBuilder:Inside(zone: AnyZone)
	return self:_addFilter(function(player) return zone:FindPlayer(player) end)
end

function QueryBuilder:Outside(zone: AnyZone)
	return self:_addFilter(function(player) return not zone:FindPlayer(player) end)
end

function QueryBuilder:InsideFor(zone: AnyZone, seconds: number)
	return self:_addFilter(function(player) return zone:InsideFor(player, seconds) end)
end

function QueryBuilder:WasInside(zone: AnyZone, secondsAgo: number)
	return self:_addFilter(function(player) return zone:WasPlayerInside(player, secondsAgo) end)
end

function QueryBuilder:EnteredWithin(zone: AnyZone, seconds: number)
	return self:_addFilter(function(player) return zone:EnteredWithin(player, seconds) end)
end

function QueryBuilder:ExitedWithin(zone: AnyZone, seconds: number)
	return self:_addFilter(function(player) return zone:ExitedWithin(player, seconds) end)
end

function QueryBuilder:WithinRadius(position: Vector3, radius: number)
	assert(isFiniteVector3(position), "position must be finite")
	radius = requireNonNegativeFinite(radius, "radius")
	local radiusSq = radius * radius
	if self._candidateProvider == nil then
		self._candidateProvider = function()
			local extent = Vector3.new(radius, radius, radius)
			local candidates = playerCandidatesForAABB(position - extent, position + extent)
			local result = {}
			for _, player in ipairs(candidates) do
				local root = self:_getRoot(player)
				if root then
					local delta = root.Position - position
					if delta:Dot(delta) <= radiusSq then
						table.insert(result, player)
					end
				end
			end
			return result
		end
	end
	return self:_addFilter(function(player)
		local root = self:_getRoot(player)
		if root == nil then
			return false
		end
		local delta = root.Position - position
		return delta:Dot(delta) <= radiusSq
	end)
end

function QueryBuilder:WithinBox(cframe: CFrame, size: Vector3)
	assert(isFiniteVector3(size), "size must be finite")
	assert(size.X >= 0 and size.Y >= 0 and size.Z >= 0, "size must be non-negative")
	local minimum, maximum = orientedBoxWorldAABB(cframe, size)
	if self._candidateProvider == nil then
		self._candidateProvider = function()
			return playerCandidatesForAABB(minimum, maximum)
		end
	end
	return self:_addFilter(function(player)
		local root = self:_getRoot(player)
		return root ~= nil and pointInsideOrientedBox(cframe, size, root.Position)
	end)
end

function QueryBuilder:SpeedAbove(speed: number)
	speed = requireNonNegativeFinite(speed, "speed")
	local speedSq = speed * speed
	return self:_addFilter(function(player)
		local root = self:_getRoot(player)
		if root == nil then
			return false
		end
		local velocity = root.AssemblyLinearVelocity
		return velocity:Dot(velocity) >= speedSq
	end)
end

function QueryBuilder:SpeedBelow(speed: number)
	speed = requireNonNegativeFinite(speed, "speed")
	local speedSq = speed * speed
	return self:_addFilter(function(player)
		local root = self:_getRoot(player)
		if root == nil then
			return false
		end
		local velocity = root.AssemblyLinearVelocity
		return velocity:Dot(velocity) <= speedSq
	end)
end

function QueryBuilder:InZoneTag(tag: string)
	assert(type(tag) == "string" and tag ~= "", "tag must be a non-empty string")
	return self:_addFilter(function(player)
		return ZonePlusNext.IsPlayerInTag(player, tag)
	end)
end

function QueryBuilder:NotInZoneTag(tag: string)
	assert(type(tag) == "string" and tag ~= "", "tag must be a non-empty string")
	return self:_addFilter(function(player)
		return not ZonePlusNext.IsPlayerInTag(player, tag)
	end)
end

function QueryBuilder:InAnyZoneTag(tags: {string})
	assert(type(tags) == "table", "tags must be an array")
	return self:_addFilter(function(player)
		return ZonePlusNext.IsPlayerInAnyTag(player, tags)
	end)
end

function QueryBuilder:InAllZoneTags(tags: {string})
	assert(type(tags) == "table", "tags must be an array")
	return self:_addFilter(function(player)
		return ZonePlusNext.IsPlayerInAllTags(player, tags)
	end)
end

function QueryBuilder:VisibleFrom(origin: Vector3, options: VisibilityOptions?)
	assert(isFiniteVector3(origin), "origin must be finite")
	return self:_addFilter(function(player) return isPlayerVisible(origin, player, options) end)
end

function QueryBuilder:And(predicate: (Player) -> boolean)
	assert(type(predicate) == "function", "And predicate must be a function")
	return self:_addFilter(predicate)
end

function QueryBuilder:Not(predicate: (Player) -> boolean)
	assert(type(predicate) == "function", "Not predicate must be a function")
	return self:_addFilter(function(player) return not predicate(player) end)
end

function QueryBuilder:Or(predicate: (Player) -> boolean)
	assert(type(predicate) == "function", "Or predicate must be a function")
	table.insert(self._orFilters, predicate)
	return self
end

function QueryBuilder:SortByDistance(position: Vector3)
	assert(isFiniteVector3(position), "position must be finite")
	self._sortPoint = position
	return self
end

function QueryBuilder:Limit(count: number)
	count = requireNonNegativeFinite(count, "count")
	self._limit = math.max(0, math.floor(count))
	return self
end

function QueryBuilder:Execute(): {Player}
	queryExecutions += 1
	table.clear(self._rootCache)

	if self._limit == 0 then
		return {}
	end

	local candidates = if self._candidateProvider then self._candidateProvider() else Players:GetPlayers()
	queryCandidates += #candidates
	local result = {}

	for _, player in ipairs(candidates) do
		local passed = true
		for _, predicate in ipairs(self._filters) do
			local success, value = pcall(predicate, player)
			if not success or not value then
				passed = false
				break
			end
		end

		if passed and #self._orFilters > 0 then
			local any = false
			for _, predicate in ipairs(self._orFilters) do
				local success, value = pcall(predicate, player)
				if success and value then
					any = true
					break
				end
			end
			passed = any
		end

		if passed then
			table.insert(result, player)
			if self._limit ~= nil and self._sortPoint == nil and #result >= self._limit then
				break
			end
		end
	end

	if self._sortPoint then
		local point = self._sortPoint
		table.sort(result, function(a, b)
			local ar = self:_getRoot(a)
			local br = self:_getRoot(b)
			if ar == nil then return false end
			if br == nil then return true end
			local ad = ar.Position - point
			local bd = br.Position - point
			return ad:Dot(ad) < bd:Dot(bd)
		end)
	end

	if self._limit then
		while #result > self._limit do
			table.remove(result)
		end
	end

	queryResults += #result
	return result
end

function ZonePlusNext.QueryPlayers(): any
	return newQueryBuilder()
end

function ZonePlusNext.Query(spec: any): any
	assert(type(spec) == "table", "Query expects a table")

	local queryType = spec.Type
	assert(
		queryType == nil
			or queryType == "Player"
			or queryType == "Players"
			or queryType == "Zone"
			or queryType == "Zones",
		"Query Type must be Player, Players, Zone, or Zones"
	)

	if queryType == "Zone" or queryType == "Zones" then
		return ZonePlusNext.QueryZones(spec)
	end

	local builder = ZonePlusNext.QueryPlayers()

	if spec.Spatial then
		local spatial = spec.Spatial
		if spatial.Zone then builder:Inside(spatial.Zone) end
		if spatial.Position and spatial.Radius then builder:WithinRadius(spatial.Position, spatial.Radius) end
		if spatial.CFrame and spatial.Size then builder:WithinBox(spatial.CFrame, spatial.Size) end
	end

	if spec.Temporal then
		local temporal = spec.Temporal
		local zone = temporal.Zone or (spec.Spatial and spec.Spatial.Zone)
		if zone then
			if temporal.InsideFor then builder:InsideFor(zone, temporal.InsideFor) end
			if temporal.WasInside then builder:WasInside(zone, temporal.WasInside) end
			if temporal.EnteredWithin then builder:EnteredWithin(zone, temporal.EnteredWithin) end
			if temporal.ExitedWithin then builder:ExitedWithin(zone, temporal.ExitedWithin) end
		end
	end

	if spec.Velocity then
		if spec.Velocity.Min then builder:SpeedAbove(spec.Velocity.Min) end
		if spec.Velocity.Max then builder:SpeedBelow(spec.Velocity.Max) end
	end

	if spec.ZoneTag then builder:InZoneTag(spec.ZoneTag) end
	if spec.ExcludeZoneTag then builder:NotInZoneTag(spec.ExcludeZoneTag) end
	if spec.ZoneTagsAny then builder:InAnyZoneTag(spec.ZoneTagsAny) end
	if spec.ZoneTagsAll then builder:InAllZoneTags(spec.ZoneTagsAll) end
	if spec.VisibleFrom then builder:VisibleFrom(spec.VisibleFrom, spec.Visibility) end
	if spec.SortByDistance then builder:SortByDistance(spec.SortByDistance) end
	if spec.Limit then builder:Limit(spec.Limit) end

	return builder:Execute()
end

Players.PlayerRemoving:Connect(function(player)
	clearSpatialIndex()
	spatialIndexValid = false
	for zone in pairs(zones) do
		local state = zone._playerStates[player]
		if state then
			if state.inside and not zone._destroyed and not zone._destroying then
				zone:_commitPlayerState(player, state, false)
			end
			zone._playerStates[player] = nil
		end
		zone._playerHistory[player] = nil
		updateZoneSchedulerResidency(zone)
	end

	playerMemberships[player] = nil
	positionHistory[player] = nil
end)

-- Compatibility-style aliases for a smoother migration.
ZonePlusNext.findPlayer = ZonePlusNext.FindPlayer
ZonePlusNext.findItem = ZonePlusNext.FindItem
ZonePlusNext.contains = ZonePlusNext.Contains
ZonePlusNext.enable = ZonePlusNext.Enable
ZonePlusNext.disable = ZonePlusNext.Disable
ZonePlusNext.toggleEnabled = ZonePlusNext.ToggleEnabled
ZonePlusNext.apply = ZonePlusNext.Apply
ZonePlusNext.addTags = ZonePlusNext.AddTags
ZonePlusNext.removeTags = ZonePlusNext.RemoveTags
ZonePlusNext.setTags = ZonePlusNext.SetTags
ZonePlusNext.setDelays = ZonePlusNext.SetDelays
ZonePlusNext.setPlayerFilter = ZonePlusNext.SetPlayerFilter
ZonePlusNext.trackItems = ZonePlusNext.TrackItems
ZonePlusNext.untrackItems = ZonePlusNext.UntrackItems
ZonePlusNext.isItemTracked = ZonePlusNext.IsItemTracked
ZonePlusNext.getItemState = ZonePlusNext.GetItemState
ZonePlusNext.getPlayerState = ZonePlusNext.GetPlayerState
ZonePlusNext.findPoint = ZonePlusNext.ContainsPoint
ZonePlusNext.trackItem = ZonePlusNext.TrackItem
ZonePlusNext.untrackItem = ZonePlusNext.UntrackItem
ZonePlusNext.setDetection = ZonePlusNext.SetDetection
ZonePlusNext.setEnabled = ZonePlusNext.SetEnabled
ZonePlusNext.setTrackPlayers = ZonePlusNext.SetTrackPlayers
ZonePlusNext.setBroadPhase = ZonePlusNext.SetBroadPhase
ZonePlusNext.getBounds = ZonePlusNext.GetBounds
ZonePlusNext.queryPoint = ZonePlusNext.QueryPoint
ZonePlusNext.queryRadius = ZonePlusNext.QueryRadius
ZonePlusNext.queryBox = ZonePlusNext.QueryBox
ZonePlusNext.queryPart = ZonePlusNext.QueryPart
ZonePlusNext.queryRay = ZonePlusNext.QueryRay
ZonePlusNext.queryPath = ZonePlusNext.QueryPath
ZonePlusNext.queryPlayers = ZonePlusNext.QueryPlayers
ZonePlusNext.getNearestZone = ZonePlusNext.GetNearestZone
ZonePlusNext.getNearestPlayers = ZonePlusNext.GetNearestPlayers
ZonePlusNext.getZonesByTag = ZonePlusNext.GetZonesByTag
ZonePlusNext.getZonesByTags = ZonePlusNext.GetZonesByTags
ZonePlusNext.getZonesForPlayer = ZonePlusNext.GetZonesForPlayer
ZonePlusNext.getHighestPriorityZone = ZonePlusNext.GetHighestPriorityZone
ZonePlusNext.isPlayerInAnyZone = ZonePlusNext.IsPlayerInAnyZone
ZonePlusNext.getPlayerZoneByTag = ZonePlusNext.GetPlayerZoneByTag
ZonePlusNext.isPlayerInTag = ZonePlusNext.IsPlayerInTag
ZonePlusNext.isPlayerInAnyTag = ZonePlusNext.IsPlayerInAnyTag
ZonePlusNext.isPlayerInAllTags = ZonePlusNext.IsPlayerInAllTags
ZonePlusNext.getPlayerTags = ZonePlusNext.GetPlayerTags
ZonePlusNext.getPlayersByTag = ZonePlusNext.GetPlayersByTag
ZonePlusNext.countPlayersByTag = ZonePlusNext.CountPlayersByTag
ZonePlusNext.getOverlappingZones = ZonePlusNext.GetOverlappingZones
ZonePlusNext.getZoneIndexConfig = ZonePlusNext.GetZoneIndexConfig
ZonePlusNext.rebuildZoneIndex = ZonePlusNext.RebuildZoneIndex
ZonePlusNext.warmIndexes = ZonePlusNext.WarmIndexes
ZonePlusNext.configureScheduler = ZonePlusNext.ConfigureScheduler
ZonePlusNext.getSchedulerConfig = ZonePlusNext.GetSchedulerConfig
ZonePlusNext.setSchedulerBudget = ZonePlusNext.SetSchedulerBudget
ZonePlusNext.getSchedulerStats = ZonePlusNext.GetSchedulerStats
ZonePlusNext.resetSchedulerStats = ZonePlusNext.ResetSchedulerStats
ZonePlusNext.getIndexMode = ZonePlusNext.GetIndexMode
ZonePlusNext.setIndexMode = ZonePlusNext.SetIndexMode
ZonePlusNext.beginBatch = ZonePlusNext.BeginBatch
ZonePlusNext.endBatch = ZonePlusNext.EndBatch
ZonePlusNext.batch = ZonePlusNext.Batch
ZonePlusNext.createMany = ZonePlusNext.CreateMany
ZonePlusNext.getCompactStats = ZonePlusNext.GetCompactStats
ZonePlusNext.printStats = ZonePlusNext.PrintStats
ZonePlusNext.setZonesEnabled = ZonePlusNext.SetZonesEnabled
ZonePlusNext.destroyZones = ZonePlusNext.DestroyZones
ZonePlusNext.destroy = ZonePlusNext.Destroy

return ZonePlusNext
