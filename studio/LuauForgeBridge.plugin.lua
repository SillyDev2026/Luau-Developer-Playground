--!strict
-- Install as a Roblox Studio Plugin Script, never as an in-experience Script.
-- The plugin ONLY changes scripts tagged as managed by this workspace.
-- Credentials stay in memory for this Studio session.
local HttpService = game:GetService("HttpService")
local ScriptEditorService = game:GetService("ScriptEditorService")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

local roots = {
    ReplicatedStorage = game:GetService("ReplicatedStorage"),
    ServerScriptService = game:GetService("ServerScriptService"),
    StarterGui = game:GetService("StarterGui"),
    StarterPlayerScripts = StarterPlayer:WaitForChild("StarterPlayerScripts")
}
local classes = { Script = true, LocalScript = true, ModuleScript = true }
local toolbar = plugin:CreateToolbar("LuauForge")
local button = toolbar:CreateButton("Workspace Bridge", "Connect LuauForge shared scripts", "")
local widgetInfo = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 330, 340, 270, 250)
local widget = plugin:CreateDockWidgetPluginGui("LuauForgeStudioBridge_v1", widgetInfo)
widget.Title = "LuauForge • Studio Bridge"

local function element(className, properties, parent)
    local object = Instance.new(className)
    for name, value in pairs(properties) do
        (object :: any)[name] = value
    end
    object.Parent = parent
    return object
end

local frame = element("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(21, 26, 39) }, widget)
local layout = element("UIListLayout", { Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder }, frame)
local padding = element("UIPadding", { PaddingTop = UDim.new(0, 12), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, frame)
local function label(text, order)
    return element("TextLabel", {
        LayoutOrder = order, Size = UDim2.new(1, 0, 0, 33),
        BackgroundTransparency = 1, TextColor3 = Color3.fromRGB(227, 233, 248),
        Font = Enum.Font.Gotham, TextSize = 12, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
        Text = text
    }, frame)
end
local function input(placeholder, order, secret)
    return element("TextBox", {
        LayoutOrder = order, Size = UDim2.new(1, 0, 0, 35), BackgroundColor3 = Color3.fromRGB(38, 45, 64),
        TextColor3 = Color3.fromRGB(248, 248, 250), Font = Enum.Font.Code, TextSize = 12,
        PlaceholderText = placeholder, Text = "", ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left
    }, frame)
end
label("Paste the HTTPS API address and the Studio workspace token from LuauForge.", 1)
local urlBox = input("https://your-node-server.example", 2, false)
local workspaceBox = input("Workspace ID", 3, false)
local tokenBox = input("Studio pairing token (session only)", 4, true)
local connectButton = element("TextButton", {
    LayoutOrder = 5, Size = UDim2.new(1, 0, 0, 38),
    BackgroundColor3 = Color3.fromRGB(73, 112, 244), TextColor3 = Color3.new(1, 1, 1),
    Text = "Connect", Font = Enum.Font.GothamBold, TextSize = 14
}, frame)
local status = label("Disconnected. Only managed scripts will be updated.", 6)
local note = label("Edit mode only • polls every 5 seconds • never deletes other scripts.", 7)

local apiUrl = ""
local workspaceId = ""
local studioToken = ""
local connected = false
local generation = 0

local function request(method, endpoint, payload)
    local options = {
        Url = apiUrl .. endpoint,
        Method = method,
        Headers = { Authorization = "Bearer " .. studioToken, ["Content-Type"] = "application/json" }
    }
    if payload ~= nil then
        options.Body = HttpService:JSONEncode(payload)
    end
    local result = HttpService:RequestAsync(options)
    local decoded, body = pcall(HttpService.JSONDecode, HttpService, result.Body)
    if not result.Success then
        error("HTTP " .. tostring(result.StatusCode) .. ": " .. tostring(decoded and body.error or "Server unavailable"))
    end
    if not decoded then error("Expected JSON response from collaboration server") end
    return body
end

local function managedScript(scriptId)
    for _, parent in pairs(roots) do
        for _, child in ipairs(parent:GetChildren()) do
            if classes[child.ClassName] and child:GetAttribute("LuauForgeWorkspace") == workspaceId and child:GetAttribute("LuauForgeScriptId") == scriptId then
                return child
            end
        end
    end
    return nil
end

local function sourceHash(source)
    -- Stable per-script checksum to detect local Studio changes since last sync.
    local a = 1
    local b = 0
    for i = 1, #source do
        a = (a + string.byte(source, i)) % 65521
        b = (b + a) % 65521
    end
    return b * 65536 + a
end

local function applyScript(item)
    local target = roots[item.target]
    if target == nil or not classes[item.type] then
        error("Rejected unapproved destination or LuaSourceContainer class")
    end
    if typeof(item.source) ~= "string" or #item.source > 50000 then
        error("Invalid script source")
    end
    if typeof(item.name) ~= "string" or not string.match(item.name, "^[%w_][%w_ %-]*$") or #item.name > 50 then
        error("Invalid managed script name")
    end
    local existing = managedScript(item.id)
    if existing and existing.ClassName ~= item.type then
        error("Changing the class of an existing managed script requires manual review")
    end
    if existing then
        local expected = existing:GetAttribute("LuauForgeSourceHash")
        if expected ~= nil and expected ~= sourceHash(existing.Source) then
            error("Studio source was modified locally. Publish or back up changes before syncing this file.")
        end
    end
    for _, child in ipairs(target:GetChildren()) do
        if child.Name == item.name and child ~= existing then
            error("Target already contains " .. item.name .. "; refusing to overwrite it")
        end
    end
    local created = existing == nil
    if created then
        existing = Instance.new(item.type)
        existing.Name = item.name
        existing:SetAttribute("LuauForgeWorkspace", workspaceId)
        existing:SetAttribute("LuauForgeScriptId", item.id)
        existing.Parent = target
    end
    -- UpdateSourceAsync also refreshes source open in the Studio script editor.
    -- On failure do not leave behind an empty tagged object.
    local ok, err = pcall(function()
        ScriptEditorService:UpdateSourceAsync(existing, function(oldSource)
            local lastSynced = existing:GetAttribute("LuauForgeSourceHash")
            if not created and lastSynced ~= nil and sourceHash(oldSource) ~= lastSynced then
                error("Unsaved Studio editor changes detected. Resolve before syncing.")
            end
            return item.source
        end)
    end)
    if not ok then
        if created then existing:Destroy() end
        error(err)
    end
    existing.Name = item.name
    existing.Parent = target
    existing:SetAttribute("LuauForgeRevision", item.version)
    existing:SetAttribute("LuauForgeSourceHash", sourceHash(item.source))
end

local function poll(current)
    if not connected or current ~= generation then return end
    if RunService:IsRunning() then
        status.Text = "Paused during Play/Test mode."
        return
    end
    local body = request("GET", "/api/studio/" .. workspaceId .. "/changes", nil)
    local changes = body.changes or {}
    for _, item in ipairs(changes) do
        if not connected or current ~= generation then return end
        local ok, err = pcall(applyScript, item)
        if ok then
            request("POST", "/api/studio/" .. workspaceId .. "/ack", {
                scriptId = item.id, version = item.version, success = true
            })
        else
            warn("[LuauForge] Skipped " .. tostring(item.name) .. ": " .. tostring(err))
            request("POST", "/api/studio/" .. workspaceId .. "/ack", {
                scriptId = item.id, version = item.version, success = false, error = tostring(err)
            })
        end
    end
    status.Text = "Connected • " .. tostring(#changes) .. " pending scripts checked"
end

local function validEndpoint(url)
    -- Reject URL path, query, userinfo and misleading domain prefixes.
    if string.match(url, "^https://[%w%.%-]+$") then return true end
    if string.match(url, "^https://[%w%.%-]+:%d+$") then return true end
    return string.match(url, "^http://127%.0%.0%.1:%d+$") ~= nil
end

connectButton.MouseButton1Click:Connect(function()
    if connected then
        connected = false
        generation += 1
        studioToken = ""
        tokenBox.Text = ""
        connectButton.Text = "Connect"
        status.Text = "Disconnected"
        return
    end
    local url = urlBox.Text:gsub("/+$", "")
    if not validEndpoint(url) then
        status.Text = "Use a trusted HTTPS server (localhost allowed for testing)."
        return
    end
    if not string.match(workspaceBox.Text, "^[%w%-]+$") or #tokenBox.Text < 30 then
        status.Text = "Enter the workspace ID and pairing token."
        return
    end
    apiUrl = url
    workspaceId = workspaceBox.Text
    studioToken = tokenBox.Text
    tokenBox.Text = ""
    connected = true
    generation += 1
    local current = generation
    connectButton.Text = "Disconnect"
    status.Text = "Connecting…"
    task.spawn(function()
        while connected and current == generation do
            local ok, err = pcall(poll, current)
            if not ok then status.Text = "Sync failed: " .. string.sub(tostring(err), 1, 130) end
            task.wait(5)
        end
    end)
end)

button.Click:Connect(function()
    widget.Enabled = not widget.Enabled
end)
plugin.Unloading:Connect(function()
    connected = false
    generation += 1
    studioToken = ""
end)
