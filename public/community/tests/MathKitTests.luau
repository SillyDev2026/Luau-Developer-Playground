--!strict
-- A public test-suite module that itself imports two public sibling modules.
local T = require('../TestTools.luau')
local Math = require('../MathKit.luau')
local Suite = {}
function Suite.run()
    T.run('MathKit.add', function()
        T.equal(Math.add(20, 22), 42)
    end)
    T.run('MathKit.multiply', function()
        T.equal(Math.multiply(6, 7), 42)
    end)
    return true
end
return Suite
