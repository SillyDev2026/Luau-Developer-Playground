--!strict
-- Immutable-by-default table utilities for standalone Luau WASM and Studio.
local TableKit = {}

-- Create a shallow copy without mutating the input.
function TableKit.copy(source: {[any]: any}): {[any]: any}
    local result: {[any]: any} = {}
    for key, value in pairs(source) do
        result[key] = value
    end
    return result
end

-- Merge two maps, preferring keys from the right-hand map.
function TableKit.merge(left: {[any]: any}, right: {[any]: any}): {[any]: any}
    local result = TableKit.copy(left)
    for key, value in pairs(right) do
        result[key] = value
    end
    return result
end

-- Get keys as an array (iteration order is unspecified).
function TableKit.keys(source: {[any]: any}): {any}
    local result: {any} = {}
    for key in pairs(source) do
        table.insert(result, key)
    end
    return result
end

return TableKit
