--!strict
-- LuauForge: real Roblox SERVER module require timing (not browser WASM).
-- Place this Script in ServerScriptService.
-- Place a ModuleScript named "BenchmarkTarget" in ServerStorage.
-- Start a Studio server playtest and read the SERVER Output window.
local ServerStorage = game:GetService("ServerStorage")
local moduleTemplate = ServerStorage:WaitForChild("BenchmarkTarget")
assert(moduleTemplate:IsA("ModuleScript"), "BenchmarkTarget must be a ModuleScript")

local SAMPLES = 12
local coldSamples: {number} = {}
local cachedSamples: {number} = {}

local function describe(samples: {number}): (number, number, number)
    table.sort(samples)
    local n = #samples
    local middle = math.floor(n / 2)
    local median = n % 2 == 0 and (samples[middle] + samples[middle + 1]) / 2 or samples[middle + 1]
    return median, samples[1], samples[n]
end

for round = 1, SAMPLES do
    -- Clone allocation is excluded from the timing.
    local clonedModule = moduleTemplate:Clone()
    clonedModule.Parent = moduleTemplate.Parent

    local startCold = os.clock()
    local exported = require(clonedModule)
    local coldMs = (os.clock() - startCold) * 1000

    local startCached = os.clock()
    local cached = require(clonedModule)
    local cachedMs = (os.clock() - startCached) * 1000
    assert(rawequal(exported, cached), "Module exports changed on cached require")

    coldSamples[round] = coldMs
    cachedSamples[round] = cachedMs
    clonedModule:Destroy()
end

local coldMedian, coldMin, coldMax = describe(coldSamples)
local cachedMedian, cachedMin, cachedMax = describe(cachedSamples)
print(string.format("[LuauForge SERVER] %s | %d fresh module loads", moduleTemplate.Name, SAMPLES))
print(string.format("[SERVER CPU] Cold require: median %.5f ms | min %.5f | max %.5f", coldMedian, coldMin, coldMax))
print(string.format("[SERVER CPU] Cached require: median %.5f ms | min %.5f | max %.5f", cachedMedian, cachedMin, cachedMax))
-- External dependencies already cached by the server are not necessarily cold.
