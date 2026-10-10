--!strict
-- Public LuauForge test helpers; standalone Luau, no Roblox engine globals.
local TestTools = {}
function TestTools.equal(actual: any, expected: any, message: string?)
    assert(actual == expected, message or (`expected {tostring(expected)}, got {tostring(actual)}`))
    return true
end
function TestTools.truthy(value: any, message: string?)
    assert(value, message or 'expected a truthy value')
    return true
end
function TestTools.run(name: string, test: () -> ())
    test()
    print('PASS', name)
    return true
end
return TestTools
