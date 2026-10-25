-- Omicron | Overdrive Hub Server Hop Addon
-- Server hopping on high player count or friend join.

local shared = odh_shared_plugins

local my_own_tab = shared.CreateTab("Omicron Hop", "/axioriasolver/testplugin/refs/heads/main/icon")
local my_own_section = my_own_tab:AddSection("Server Hop", "AUTO-HOP ON FULL / FRIEND JOIN")

-- ===================== SERVICES =====================
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

-- ===================== STATE =====================
local hopState = {
    enabled = false,
    threshold = 6,
    friendJoin = false,
    hopThread = nil,
    friendThread = nil,
}

-- ===================== UTIL =====================
local function httpGet(url)
    local methods = {
        function() return game:HttpGet(url) end,
        function() if syn and syn.request then return syn.request({Url=url, Method="GET"}).Body end end,
        function() if request then return request({Url=url, Method="GET"}).Body end end,
        function() if http_request then return http_request({Url=url, Method="GET"}).Body end end,
        function() if http and http.request then return http.request({Url=url, Method="GET"}).Body end end,
    }
    for _, fn in ipairs(methods) do
        local ok, res = pcall(fn)
        if ok and type(res) == "string" and #res > 0 then
            return res
        end
    end
    return nil
end

-- ===================== SERVER HOP =====================
local function getServerPool()
    local url = string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100", game.PlaceId)
    local raw = httpGet(url)
    if not raw then
        return {}
    end
    local ok, res = pcall(function() return HttpService:JSONDecode(raw) end)
    if not ok or not res or not res.data then
        return {}
    end
    local pool = {}
    for _, s in ipairs(res.data) do
        if s.id ~= game.JobId and s.playing >= 1 and s.playing <= 3 and s.playing < s.maxPlayers then
            table.insert(pool, s)
        end
    end
    for i = #pool, 2, -1 do
        local j = math.random(1, i)
        pool[i], pool[j] = pool[j], pool[i]
    end
    return pool
end

local function tryTeleport(serverId)
    local failed = false
    local failReason = nil
    local conn = TeleportService.TeleportInitFailed:Connect(function(plr, _, reason)
        if plr == LocalPlayer then
            failed = true
            failReason = reason
        end
    end)
    local ok, result = pcall(function()
        local opts = Instance.new("TeleportOptions")
        opts.ServerInstanceId = serverId
        return TeleportService:TeleportToPlaceInstance(game.PlaceId, serverId, LocalPlayer, opts)
    end)
    if not ok then
        conn:Disconnect()
        return false, "erro: " .. tostring(result)
    end
    if typeof(result) == "EnumItem" and result == Enum.TeleportState.Failed then
        conn:Disconnect()
        return false, "TeleportState = Failed"
    end
    local start = tick()
    while tick() - start < 3 do
        if failed then
            conn:Disconnect()
            return false, "TeleportInitFailed: " .. tostring(failReason)
        end
        task.wait(0.1)
    end
    conn:Disconnect()
    return true
end

local function hop()
    local pool = getServerPool()
    if #pool > 0 then
        for _, srv in ipairs(pool) do
            local ok = tryTeleport(srv.id)
            if ok then
                return true
            end
            task.wait(0.3)
        end
    end
    -- Fallback: Teleport to a random server
    local failed = false
    local conn = TeleportService.TeleportInitFailed:Connect(function(plr)
        if plr == LocalPlayer then
            failed = true
        end
    end)
    local ok = pcall(function()
        TeleportService:Teleport(game.PlaceId, LocalPlayer)
    end)
    task.wait(3)
    conn:Disconnect()
    return ok and not failed
end

-- ===================== MONITORS =====================
local function startHopMonitor()
    if hopState.hopThread then
        return
    end
    hopState.hopThread = task.spawn(function()
        while hopState.enabled do
            task.wait(5)
            if #Players:GetPlayers() > hopState.threshold then
                if hop() then
                    break
                end
            end
        end
    end)
end

local function startFriendMonitor()
    if hopState.friendThread then
        return
    end
    hopState.friendThread = task.spawn(function()
        local friendIds = {}
        pcall(function()
            local raw = httpGet("https://friends.roblox.com/v1/users/" .. LocalPlayer.UserId .. "/friends")
            if raw then
                local r = HttpService:JSONDecode(raw)
                if r and r.data then
                    for _, f in ipairs(r.data) do
                        friendIds[f.id] = true
                    end
                end
            end
        end)
        while hopState.friendJoin do
            task.wait(10)
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and friendIds[p.UserId] then
                    hop()
                    break
                end
            end
        end
    end)
end

-- ===================== UI =====================
local toggle = my_own_section:AddToggle("Enable Auto-Hop", function(state)
    hopState.enabled = state
    if state then
        startHopMonitor()
        shared.Notify("Auto-Hop enabled", 2)
    else
        if hopState.hopThread then
            task.cancel(hopState.hopThread)
            hopState.hopThread = nil
        end
        shared.Notify("Auto-Hop disabled", 2)
    end
end)

local slider = my_own_section:AddSlider("Player Threshold", 1, 30, 6, function(value)
    hopState.threshold = value
    shared.Notify("Threshold set to " .. value, 2)
end)

local friendToggle = my_own_section:AddToggle("Hop on Friend Join", function(state)
    hopState.friendJoin = state
    if state then
        startFriendMonitor()
        shared.Notify("Friend-join hop enabled", 2)
    else
        if hopState.friendThread then
            task.cancel(hopState.friendThread)
            hopState.friendThread = nil
        end
        shared.Notify("Friend-join hop disabled", 2)
    end
end)

my_own_section:AddButton("Hop Now", function()
    shared.Notify("Hopping...", 2)
    hop()
end)

my_own_section:AddLabel("Credits: kerli")
