--!strict
-- Small standalone Luau signal; intentionally uses no Roblox services.
local SignalLite = {}

-- Create a new signal with Connect, Fire and Destroy methods.
function SignalLite.new()
    local listeners: {{callback: (...any) -> (), active: boolean}} = {}
    local destroyed = false
    local signal = {}

    -- Subscribe a callback. Disconnect is safe to call more than once.
    function signal:Connect(callback: (...any) -> ())
        assert(not destroyed, "SignalLite: signal destroyed")
        assert(type(callback) == "function", "SignalLite: callback must be a function")
        local entry = {callback = callback, active = true}
        table.insert(listeners, entry)
        local connection = {}
        function connection:Disconnect()
            entry.active = false
        end
        return connection
    end

    -- Call active listeners in their registration order.
    function signal:Fire(...: any)
        assert(not destroyed, "SignalLite: signal destroyed")
        local args = table.pack(...)
        local count = #listeners
        for i = 1, count do
            local entry = listeners[i]
            if entry and entry.active then
                entry.callback(table.unpack(args, 1, args.n))
            end
        end
    end

    -- Invalidate all subscriptions permanently.
    function signal:Destroy()
        destroyed = true
        table.clear(listeners)
    end

    return signal
end

return SignalLite
