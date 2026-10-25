-- ASCRON | MM2 AutoFarm v14
-- Multi-container | Brief unanchor collect | Loader-based reexecution | Anti-fling distance gate | Lobby-aware farm

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local VirtualUser = game:GetService("VirtualUser")
local VirtualInputManager = game:GetService("VirtualInputManager")
local LocalPlayer = Players.LocalPlayer

-- ===================== HWID + PREFS =====================
local function getHWID()
    local ok, id = pcall(function() return gethwid() end)
    if ok and type(id) == "string" and #id > 0 then return id end
    local ok2, cid = pcall(function() return game:GetService("RbxAnalyticsService"):GetClientId() end)
    if ok2 and type(cid) == "string" and #cid > 0 then return cid end
    return tostring(LocalPlayer.UserId)
end
local HWID = getHWID()
local PREFS_FILE = "ASCRON_MM2_" .. (tostring(HWID):gsub("[^%w_%-]", "_")) .. ".json"
local SOURCE_FILE = "ASCRON_MM2_SOURCE.lua"

local Prefs = {}
local function getEnv() local e = {}; pcall(function() local g = getgenv(); if type(g) == "table" then e = g end end); return e end
function Prefs.load()
    local env = getEnv()
    local read = type(readfile) == "function" and readfile or env.readfile
    if not read then return nil end
    local ok, data = pcall(read, PREFS_FILE)
    if ok and data then
        local ok2, decoded = pcall(function() return HttpService:JSONDecode(data) end)
        if ok2 and decoded then return decoded end
    end
    return nil
end
function Prefs.save(tbl)
    local env = getEnv()
    local write = type(writefile) == "function" and writefile or env.writefile
    if not write then return end
    local ok, encoded = pcall(function() return HttpService:JSONEncode(tbl) end)
    if ok and encoded then pcall(write, PREFS_FILE, encoded) end
end

-- ===================== CONFIG =====================
getgenv().ASCRON = getgenv().ASCRON or {}
local C = getgenv().ASCRON

local defaults = {
    Currency = "Coin", FarmSpeed = 30, FarmMode = "Standard",
    ServerHopPlayerCount = 6, HopOnFriendJoin = false,
    AntiAFK = true, AntiVoid = true, AntiFling = true, Noclip = true,
    Disable3D = false, AutoVoteMode = 0, AutoVoteMax = 0,
    AutoResetInnocent = true, AutoFlingMurderer = false,
    AutoShootSheriff = true, AutoResetAnyRole = false,
    AutoKillMurderer = true, AutoResetMurderer = false,
    BagThresholdOverride = 0, ResetAfterAction = true,
}
for k, v in pairs(defaults) do if C[k] == nil then C[k] = v end end
local saved = Prefs.load()
if saved then for k, v in pairs(saved) do if C[k] ~= nil then C[k] = v end end end

C.Farming = false
C.FarmThread = nil
C.HopThread, C.FriendThread, C.VoteThread = nil, nil, nil
C.LastFullAction = 0
C.Stats = { TotalCounted = 0, SessionStart = tick(), LastSeenValue = nil }
C.HopStatus = ""
C.CollectFails = 0

local function savePrefs()
    local tbl = {}
    for k, _ in pairs(defaults) do tbl[k] = C[k] end
    Prefs.save(tbl)
end

-- ===================== UTIL =====================
local function getHRP() local c = LocalPlayer.Character; return c and c:FindFirstChild("HumanoidRootPart") end
local function getHum() local c = LocalPlayer.Character; return c and c:FindFirstChildOfClass("Humanoid") end

-- ===================== CACHE GetPlayerData =====================
local pdCache = { data = nil, timestamp = 0 }
local function getPlayerData()
    local now = tick()
    if pdCache.data and now - pdCache.timestamp < 0.5 then return pdCache.data end
    local remote = ReplicatedStorage:FindFirstChild("GetPlayerData", true)
    if not remote or not remote:IsA("RemoteFunction") then return nil end
    local ok, data = pcall(function() return remote:InvokeServer() end)
    if ok and data then pdCache.data = data; pdCache.timestamp = now; return data end
    return pdCache.data
end

-- ===================== BAG =====================
local EVENT_CURRENCIES = { Candy=true, SnowToken=true, Token=true, Shell=true, Egg=true, Present=true, Gift=true, Gem=true }
local function getBagThreshold()
    if C.BagThresholdOverride and C.BagThresholdOverride > 0 then return C.BagThresholdOverride end
    if EVENT_CURRENCIES[C.Currency] then return 50 end
    return 40
end
local CURRENCY_ALIASES = {
    Coin = {"Coins","Coin","coin","coins"},
    Candy = {"Candy","Candies","candy","candies"},
    SnowToken = {"SnowToken","SnowTokens","Snow Tokens"},
    Token = {"Token","Tokens"},
    Shell = {"Shell","Shells"},
}
local function getStatValue()
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    local aliases = CURRENCY_ALIASES[C.Currency] or {C.Currency}
    if ls then
        for _, name in ipairs(aliases) do
            local st = ls:FindFirstChild(name)
            if st and typeof(st.Value) == "number" then return st.Value end
        end
    end
    for _, name in ipairs(aliases) do
        local ok, v = pcall(function() return LocalPlayer:GetAttribute(name) end)
        if ok and type(v) == "number" then return v end
    end
    local data = getPlayerData()
    if data and data[LocalPlayer.Name] then
        local me = data[LocalPlayer.Name]
        for _, name in ipairs(aliases) do if type(me[name]) == "number" then return me[name] end end
        if type(me.Bag) == "number" then return me.Bag end
    end
    return nil
end

-- ===================== NOCLIP =====================
local noclipConn
local function startNoclip()
    if noclipConn then noclipConn:Disconnect() end
    noclipConn = RunService.Stepped:Connect(function()
        if not C.Noclip then return end
        local char = LocalPlayer.Character
        if not char then return end
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then part.CanCollide = false end
        end
    end)
end
local function stopNoclip() if noclipConn then noclipConn:Disconnect(); noclipConn = nil end end

-- ===================== ANTI-AFK =====================
local antiAFKConn
local function startAntiAFK()
    if antiAFKConn then antiAFKConn:Disconnect() end
    antiAFKConn = LocalPlayer.Idled:Connect(function()
        pcall(function() VirtualUser:CaptureController(); VirtualUser:ClickButton2(Vector2.new(0, 0)) end)
    end)
end

-- ===================== ANTI-VOID =====================
local antiVoidConn
local origDestroyHeight = Workspace.FallenPartsDestroyHeight
local function setupAntiVoid()
    if not C.AntiVoid then
        Workspace.FallenPartsDestroyHeight = origDestroyHeight
        if antiVoidConn then antiVoidConn:Disconnect(); antiVoidConn = nil end
        return
    end
    Workspace.FallenPartsDestroyHeight = 0/0
    if antiVoidConn then antiVoidConn:Disconnect() end
    antiVoidConn = LocalPlayer.CharacterAdded:Connect(function()
        task.wait(0.1)
        Workspace.FallenPartsDestroyHeight = 0/0
    end)
end

-- ===================== ANTI-FLING (distance gate) =====================
local function startAntiFling()
    local lastPos, lastCheck = nil, tick()
    local lastChar = nil
    RunService.Heartbeat:Connect(function()
        if not C.AntiFling then return end
        local char = LocalPlayer.Character
        if not char then lastChar = nil; lastPos = nil; return end
        if char ~= lastChar then lastChar = char; lastPos = nil; lastCheck = tick(); return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or hum.Health <= 0 or hrp.Anchored then lastPos = nil; return end
        local now = tick()
        if lastPos and now - lastCheck > 0.1 then
            local delta = (hrp.Position - lastPos).Magnitude
            local speed = delta / (now - lastCheck)
            -- Só snap-back se for distância curta com velocidade absurda (fling real)
            -- Teleporte grande (delta > 30) é servidor movendo, não fling
            if speed > 150 and delta < 30 then
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
                hrp.CFrame = CFrame.new(lastPos) * hrp.CFrame.Rotation
            end
        end
        lastPos = hrp.Position
        lastCheck = now
    end)
end

-- ===================== COLETA (multi-container + brief unanchor) =====================
local function getCurrencyContainers()
    local containers = {}
    local seen = {}
    local function addIfExists(c)
        if c and not seen[c] then seen[c] = true; table.insert(containers, c) end
    end
    for _, obj in ipairs(Workspace:GetChildren()) do
        addIfExists(obj:FindFirstChild("CoinContainer"))
        addIfExists(obj:FindFirstChild("CandyContainer"))
        addIfExists(obj:FindFirstChild("TokenContainer"))
        addIfExists(obj:FindFirstChild("Collectables"))
        local mapF = obj:FindFirstChild("Map")
        if mapF then
            addIfExists(mapF:FindFirstChild("CoinContainer"))
            addIfExists(mapF:FindFirstChild("CandyContainer"))
            addIfExists(mapF:FindFirstChild("TokenContainer"))
            addIfExists(mapF:FindFirstChild("Collectables"))
        end
    end
    return containers
end

local function findNearestCoin()
    local hrp = getHRP(); if not hrp then return nil end
    local containers = getCurrencyContainers()
    if #containers == 0 then return nil end
    local best, bestDist = nil, math.huge
    for _, container in ipairs(containers) do
        for _, d in ipairs(container:GetDescendants()) do
            if d:IsA("BasePart") and d:FindFirstChildWhichIsA("TouchTransmitter") then
                local dist = (hrp.Position - d.Position).Magnitude
                if dist < bestDist then bestDist = dist; best = d end
            end
        end
    end
    return best
end

local function collect(coin)
    local hrp = getHRP()
    local char = LocalPlayer.Character
    if not hrp or not coin or not char then return false end
    local wasAnchored = hrp.Anchored
    if wasAnchored then
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        hrp.Anchored = false
    end
    task.wait()
    pcall(function()
        if typeof(firetouchinterest) == "function" then
            local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
            if torso then
                firetouchinterest(torso, coin, 0)
                task.wait(0.02)
                firetouchinterest(torso, coin, 1)
            end
            firetouchinterest(hrp, coin, 0)
            task.wait(0.02)
            firetouchinterest(hrp, coin, 1)
        end
    end)
    task.wait(0.03)
    if wasAnchored and hrp.Parent then
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        hrp.Anchored = true
    end
    return true
end

-- ===================== MOVIMENTO (mantido da v13) =====================
local LAY_ROTATION = CFrame.Angles(math.rad(90), 0, 0)

local function travelTo(targetPos, rotate90, speed, coinRef)
    local hrp = getHRP(); if not hrp then return false end
    if not hrp.Anchored then hrp.Anchored = true end
    local hum = getHum()
    if hum and not hum.PlatformStand then hum.PlatformStand = true; hum.AutoRotate = false end
    speed = math.clamp(speed or C.FarmSpeed, 8, 60)
    local rotation = rotate90 and LAY_ROTATION or hrp.CFrame.Rotation
    local lastTime = tick()
    while C.Farming do
        local h = getHRP()
        if not h or not h.Anchored then return false end
        if coinRef and not coinRef.Parent then return false end
        local curHum = getHum()
        if not curHum or curHum.Health <= 0 then return false end
        local delta = targetPos - h.Position
        local dist = delta.Magnitude
        if dist < 2.5 then
            h.CFrame = CFrame.new(targetPos) * rotation
            return true
        end
        local now = tick()
        local dt = math.min(now - lastTime, 0.05)
        lastTime = now
        local step = math.min(speed * dt, dist)
        h.CFrame = CFrame.new(h.Position + delta.Unit * step) * rotation
        task.wait()
    end
    return false
end

local function beginFarmMovement()
    local hrp = getHRP(); local hum = getHum()
    if hum then hum.PlatformStand = true; hum.AutoRotate = false end
    if hrp then
        hrp.Anchored = true
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end
end

local function endFarmMovement()
    local hrp = getHRP(); local hum = getHum()
    if hrp then pcall(function() hrp.Anchored = false end) end
    if hum then
        hum.PlatformStand = false
        hum.AutoRotate = true
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end)
    end
end

-- ===================== PAPEL =====================
local function getMyRole()
    local data = getPlayerData()
    if data and data[LocalPlayer.Name] then
        local r = data[LocalPlayer.Name].Role
        if r and r ~= "None" then return r end
    end
    for _, container in ipairs({LocalPlayer.Character, LocalPlayer:FindFirstChild("Backpack")}) do
        if container then
            for _, item in ipairs(container:GetChildren()) do
                if item:IsA("Tool") then
                    local n = item.Name:lower()
                    if n:find("knife") then return "Murderer" end
                    if n:find("gun") then return "Sheriff" end
                end
            end
        end
    end
    return "Innocent"
end
local function findMurderer()
    local data = getPlayerData()
    if not data then return nil end
    for name, info in pairs(data) do
        if info.Role == "Murderer" and not info.Killed and not info.Dead then
            local p = Players:FindFirstChild(name)
            if p and p ~= LocalPlayer then return p end
        end
    end
    return nil
end

-- ===================== AÇÕES =====================
local function equipTool(name)
    local ch = LocalPlayer.Character; if not ch then return nil end
    local tool = ch:FindFirstChild(name)
    if not tool then
        local bp = LocalPlayer:FindFirstChild("Backpack")
        tool = bp and bp:FindFirstChild(name)
        if tool then tool.Parent = ch; task.wait(0.2) end
    end
    return tool
end
local function killAll()
    local knife = equipTool("Knife"); if not knife then return end
    local events = knife:FindFirstChild("Events")
    local ht = events and events:FindFirstChild("HandleTouched")
    if not ht then return end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local upper = p.Character:FindFirstChild("UpperTorso") or p.Character:FindFirstChild("Torso")
            if upper then pcall(function() ht:FireServer(upper) end); task.wait(0.05) end
        end
    end
end
local function shootMurderer()
    local gun = equipTool("Gun"); if not gun then return end
    local murderer = findMurderer()
    if not murderer or not murderer.Character then return end
    local mHrp = murderer.Character:FindFirstChild("HumanoidRootPart")
    local hrp = getHRP()
    if not mHrp or not hrp then return end
    hrp.CFrame = CFrame.new(hrp.Position, mHrp.Position)
    task.wait(0.1)
    pcall(function() gun:Activate() end)
    task.wait(0.05)
    pcall(function()
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
        task.wait(0.05)
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
    end)
    local events = gun:FindFirstChild("Events")
    if events then
        for _, ev in ipairs(events:GetChildren()) do
            if ev:IsA("RemoteEvent") then pcall(function() ev:FireServer(mHrp) end) end
        end
    end
end
local function flingMurderer()
    local murderer = findMurderer()
    if not murderer or not murderer.Character then return end
    local mHrp = murderer.Character:FindFirstChild("HumanoidRootPart")
    if not mHrp then return end
    pcall(function() mHrp:SetNetworkOwner(LocalPlayer) end)
    local bv = Instance.new("BodyVelocity")
    bv.Velocity = Vector3.new(0, 800, 0)
    bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bv.P = 100000; bv.Parent = mHrp
    local bg = Instance.new("BodyGyro")
    bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    bg.P = 100000
    bg.CFrame = CFrame.new(0, math.huge, 0); bg.Parent = mHrp
    Debris:AddItem(bv, 0.6); Debris:AddItem(bg, 0.6)
end
local function resetCharacter()
    local hrp = getHRP()
    if hrp then pcall(function() hrp.Anchored = false end) end
    local hum = getHum()
    if hum then hum.PlatformStand = false; hum.Health = 0 end
end

local function handleFullBag()
    local role = getMyRole()
    local didAction = false
    if role == "Innocent" then
        if C.AutoFlingMurderer then flingMurderer(); didAction = true end
        if C.AutoResetInnocent and not didAction then resetCharacter(); return end
    elseif role == "Sheriff" then
        if C.AutoShootSheriff then shootMurderer(); didAction = true end
    elseif role == "Murderer" then
        if C.AutoKillMurderer then killAll(); didAction = true end
        if C.AutoResetMurderer and not didAction then resetCharacter(); return end
    end
    if didAction and C.ResetAfterAction then task.wait(1.2); resetCharacter(); return end
    if C.AutoResetAnyRole then resetCharacter() end
end

-- ===================== STATS =====================
local function startStatsTracker()
    task.spawn(function()
        LocalPlayer:WaitForChild("leaderstats", 10)
        task.wait(1)
        C.Stats.LastSeenValue = getStatValue() or 0
        while true do
            task.wait(0.5)
            local v = getStatValue()
            if v then
                if C.Stats.LastSeenValue and v > C.Stats.LastSeenValue then
                    C.Stats.TotalCounted += (v - C.Stats.LastSeenValue)
                end
                C.Stats.LastSeenValue = v
            end
        end
    end)
end
local function getRatePerHour()
    local elapsed = math.max(1, tick() - C.Stats.SessionStart)
    return math.floor((C.Stats.TotalCounted / elapsed) * 3600)
end

-- ===================== FARM LOOP =====================
local function isInLobby()
    local lobby = Workspace:FindFirstChild("Lobby")
    if not lobby then return false end
    local vp = lobby:FindFirstChild("VotePads")
    return vp ~= nil
end

local function startFarm()
    if C.Farming then return end
    C.Farming = true
    C.FarmThread = task.spawn(function()
        while C.Farming do
            local hum = getHum()
            if not hum or hum.Health <= 0 then task.wait(0.5); continue end
            if isInLobby() then
                -- Em lobby: desancora, deixa auto-vote agir
                local hrp = getHRP()
                if hrp and hrp.Anchored then endFarmMovement() end
                task.wait(0.5)
                continue
            end
            local hrp = getHRP()
            if not hrp then task.wait(0.3); continue end
            if not hrp.Anchored then beginFarmMovement(); task.wait(0.1) end
            local coin = findNearestCoin()
            if coin then
                local targetPos = coin.Position
                local rotate90 = (C.FarmMode == "Lay")
                local arrived = travelTo(targetPos, rotate90, C.FarmSpeed, coin)
                if arrived and coin.Parent then
                    collect(coin)
                    local t = tick()
                    while coin.Parent and tick() - t < 0.5 do task.wait(0.02) end
                    if coin.Parent then
                        C.CollectFails += 1
                    else
                        C.CollectFails = 0
                    end
                end
                task.wait(0.05)
            else
                task.wait(0.15)
            end
            local st = getStatValue()
            if st and st >= getBagThreshold() and tick() - C.LastFullAction > 3 then
                C.LastFullAction = tick()
                handleFullBag()
            end
        end
    end)
end
local function stopFarm()
    C.Farming = false
    if C.FarmThread then task.cancel(C.FarmThread); C.FarmThread = nil end
    endFarmMovement()
end

-- ===================== SOURCE + REEXECUTION =====================
local function captureSource()
    if getgenv().ASCRON_SOURCE then return true end
    local env = getgenv()
    local read = type(readfile) == "function" and readfile or env.readfile
    local write = type(writefile) == "function" and writefile or env.writefile
    if read then
        local ok, existing = pcall(read, SOURCE_FILE)
        if ok and existing and #existing > 1000 then
            getgenv().ASCRON_SOURCE = existing
            print("[ASCRON] Source: arquivo salvo (" .. #existing .. " bytes)")
            return true
        end
    end
    local function saveSrc(src)
        if not src or #src < 100 then return false end
        getgenv().ASCRON_SOURCE = src
        if write then pcall(write, SOURCE_FILE, src) end
        print("[ASCRON] Source: capturada (" .. #src .. " bytes)")
        return true
    end
    local ok1, info1 = pcall(function()
        if debug and debug.info then return debug.info(1, "s") end
    end)
    if ok1 and type(info1) == "string" and #info1 > 100 then
        if info1:sub(1, 1) == "@" then
            if read then
                local ok, content = pcall(read, info1:sub(2))
                if ok and content then return saveSrc(content) end
            end
        elseif info1:sub(1, 1) ~= "=" then
            return saveSrc(info1)
        end
    end
    local ok2, info2 = pcall(function() return debug.getinfo(1, "S") end)
    if ok2 and info2 and info2.source then
        local s = info2.source
        if s:sub(1, 1) == "@" then
            if read then
                local ok, content = pcall(read, s:sub(2))
                if ok and content then return saveSrc(content) end
            end
        elseif s:sub(1, 1) == "=" then
            local m = s:match('^=%[string "(.*)"%]$')
            if m and #m > 100 then
                m = m:gsub('\\n', '\n'):gsub('\\t', '\t'):gsub('\\"', '"'):gsub("\\'", "'"):gsub('\\\\', '\\')
                return saveSrc(m)
            end
        end
    end
    if type(getscriptsource) == "function" then
        local ok3, s = pcall(getscriptsource)
        if ok3 and type(s) == "string" then return saveSrc(s) end
    end
    return false
end

local function queueForReexecution()
    if not getgenv().ASCRON_SOURCE then captureSource() end
    if not getgenv().ASCRON_SOURCE then
        warn("[ASCRON] Reexec: source NÃO capturada. Ative Auto-Execute no executor.")
        return false
    end
    local write = type(writefile) == "function" and writefile or getgenv().writefile
    if write then pcall(write, SOURCE_FILE, getgenv().ASCRON_SOURCE) end
    -- Loader pequeno: lê o arquivo e executa. Cabe no limite do queue.
    local loader = "pcall(function() local s = readfile('" .. SOURCE_FILE .. "'); if s and #s > 100 then loadstring(s)() end end)"

    local function try(method, fn)
        local ok, result = pcall(fn)
        if ok and result ~= false then
            print("[ASCRON] Reexec: queue OK via " .. method)
            return true
        end
        return false
    end

    if syn and syn.queue_on_teleport then
        if try("syn.queue_on_teleport(loader)", function() syn.queue_on_teleport(loader) end) then return true end
        if try("syn.queue_on_teleport(full)", function() syn.queue_on_teleport(getgenv().ASCRON_SOURCE) end) then return true end
    end
    if type(queue_on_teleport) == "function" then
        if try("queue_on_teleport(loader)", function() queue_on_teleport(loader) end) then return true end
        if try("queue_on_teleport(full)", function() queue_on_teleport(getgenv().ASCRON_SOURCE) end) then return true end
    end
    local g = getgenv()
    if g and type(g.queue_on_teleport) == "function" then
        if try("getgenv().queue_on_teleport", function() g.queue_on_teleport(loader) end) then return true end
    end
    warn("[ASCRON] Reexec: NENHUM método funcionou. Habilite Auto-Execute no executor e aponte para " .. SOURCE_FILE)
    return false
end

-- ===================== HTTP MULTI =====================
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
        if ok and type(res) == "string" and #res > 0 then return res end
    end
    return nil
end

-- ===================== HOP =====================
local function getServerPool()
    local url = string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100", game.PlaceId)
    local raw = httpGet(url)
    if not raw then print("[ASCRON] Hop: HTTP falhou"); return {} end
    local ok, res = pcall(function() return HttpService:JSONDecode(raw) end)
    if not ok or not res or not res.data then print("[ASCRON] Hop: JSON inválido"); return {} end
    local pool = {}
    for _, s in ipairs(res.data) do
        if s.id ~= game.JobId and s.playing >= 1 and s.playing <= 3 and s.playing < s.maxPlayers then
            table.insert(pool, s)
        end
    end
    for i = #pool, 2, -1 do
        local j = math.random(1, i); pool[i], pool[j] = pool[j], pool[i]
    end
    return pool
end

local function tryTeleport(serverId)
    local failed, failReason = false, nil
    local conn = TeleportService.TeleportInitFailed:Connect(function(plr, _, reason)
        if plr == LocalPlayer then failed = true; failReason = reason end
    end)
    local ok, result = pcall(function()
        local opts = Instance.new("TeleportOptions")
        opts.ServerInstanceId = serverId
        return TeleportService:TeleportToPlaceInstance(game.PlaceId, serverId, LocalPlayer, opts)
    end)
    if not ok then conn:Disconnect(); return false, "erro: " .. tostring(result) end
    if typeof(result) == "EnumItem" and result == Enum.TeleportState.Failed then
        conn:Disconnect(); return false, "State=Failed"
    end
    local start = tick()
    while tick() - start < 3 do
        if failed then conn:Disconnect(); return false, "InitFailed: " .. tostring(failReason) end
        task.wait(0.1)
    end
    conn:Disconnect()
    return true
end

local function hop()
    print("[ASCRON] === Hop iniciado ===")
    C.HopStatus = "buscando..."
    local pool = getServerPool()
    print("[ASCRON] Pool: " .. #pool)
    for i, srv in ipairs(pool) do
        C.HopStatus = "tentativa " .. i .. "/" .. #pool
        print("[ASCRON] #" .. i .. ": " .. srv.id .. " (" .. srv.playing .. " plrs)")
        local ok, reason = tryTeleport(srv.id)
        if ok then
            print("[ASCRON] Teleporte OK!")
            C.HopStatus = "OK"
            queueForReexecution()
            return true
        end
        print("[ASCRON] Falhou: " .. tostring(reason))
        task.wait(0.3)
    end
    print("[ASCRON] Fallback Teleport(PlaceId)")
    C.HopStatus = "fallback"
    local failed = false
    local conn = TeleportService.TeleportInitFailed:Connect(function(plr) if plr == LocalPlayer then failed = true end end)
    pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
    task.wait(3)
    conn:Disconnect()
    if not failed then
        print("[ASCRON] Fallback OK")
        C.HopStatus = "fallback OK"
        queueForReexecution()
        return true
    end
    C.HopStatus = "FALHOU"
    return false
end

local function startHopMonitor()
    if C.HopThread then return end
    C.HopThread = task.spawn(function()
        while C.ServerHopPlayerCount > 0 do
            task.wait(5)
            if #Players:GetPlayers() > C.ServerHopPlayerCount then
                if hop() then break end
            end
        end
    end)
end

local function startFriendMonitor()
    if C.FriendThread then return end
    C.FriendThread = task.spawn(function()
        local ids = {}
        pcall(function()
            local raw = httpGet("https://friends.roblox.com/v1/users/" .. LocalPlayer.UserId .. "/friends")
            if raw then
                local r = HttpService:JSONDecode(raw)
                if r and r.data then for _, f in ipairs(r.data) do ids[f.id] = true end end
            end
        end)
        while C.HopOnFriendJoin do
            task.wait(10)
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and ids[p.UserId] then hop(); break end
            end
        end
    end)
end

-- ===================== AUTO-VOTE =====================
local VOTE_PADS = {"VotePad1", "VotePad2", "VotePad3"}
local MAP_ORDER = {"Manor","House 2","Office 3","Hospital 3","Bank 2","Vampire's Castle","Mansion 2","WorkPlace","Hotel 2","Farm House","Police Station","Factory","Bio Lab","Research Facility","Mil Base"}
local function normalizeMapName(s) s = string.lower(s):gsub("-", " "):gsub("%s+", " "); return s:match("^%s*(.-)%s*$") end
local mapRankCache = {}
local function getMapRank(raw)
    if mapRankCache[raw] then return mapRankCache[raw] end
    local low = normalizeMapName(raw); local rank = #MAP_ORDER + 1
    for i, name in ipairs(MAP_ORDER) do
        if low == normalizeMapName(name) then rank = i; break end
    end
    mapRankCache[raw] = rank; return rank
end
local function getOpenVotePads()
    local open = {}
    local lobby = Workspace:FindFirstChild("Lobby")
    local folder = lobby and lobby:FindFirstChild("VotePads")
    if not folder then return open end
    for _, name in ipairs(VOTE_PADS) do
        local pad = folder:FindFirstChild(name)
        local trigger = pad and pad:FindFirstChild("Pad")
        local gui = pad and pad:FindFirstChild("VoteInfoGui")
        local container = gui and gui:FindFirstChild("Container")
        local label = container and container:FindFirstChild("MapName")
        if trigger and label and gui.Enabled then
            table.insert(open, { trigger = trigger, map = label.Text })
        end
    end
    return open
end
local function pickVotePad(open)
    if #open == 0 then return nil end
    if C.AutoVoteMode == 3 then return open[math.random(1, #open)] end
    local best, bestScore
    for _, pad in ipairs(open) do
        local rank = getMapRank(pad.map)
        local score = (C.AutoVoteMode == 1) and -rank or rank
        if not bestScore or score > bestScore then best, bestScore = pad, score end
    end
    return best
end
local function insidePad(trigger, pos)
    local lp = trigger.CFrame:PointToObjectSpace(pos)
    local h = trigger.Size * 0.5
    return math.abs(lp.X) <= h.X and math.abs(lp.Y) <= h.Y and math.abs(lp.Z) <= h.Z
end
local function startAutoVote()
    if C.VoteThread then task.cancel(C.VoteThread) end
    C.VoteThread = task.spawn(function()
        local votes = 0
        while C.AutoVoteMode ~= 0 do
            local open = getOpenVotePads()
            if #open == 0 then task.wait(0.3); continue end
            if C.AutoVoteMax > 0 and votes >= C.AutoVoteMax then task.wait(0.5); continue end
            local target = pickVotePad(open)
            if not target then task.wait(0.1); continue end
            local hrp = getHRP(); local hum = getHum()
            if not hum or not hrp or hum.Health <= 0 then task.wait(0.3); continue end
            if not insidePad(target.trigger, hrp.Position) then
                hrp.CFrame = CFrame.new(target.trigger.Position + Vector3.new(0, 1, 0)) * hrp.CFrame.Rotation
            end
            if typeof(firetouchinterest) == "function" then
                firetouchinterest(hrp, target.trigger, 0)
                firetouchinterest(hrp, target.trigger, 1)
            end
            task.wait(0.12)
            if hum.Health > 0 then
                if typeof(firetouchinterest) == "function" then
                    firetouchinterest(hrp, target.trigger, 0)
                    firetouchinterest(hrp, target.trigger, 1)
                end
                votes += 1
                hum:ChangeState(Enum.HumanoidStateType.Dead)
                hum.Health = 0
            end
            task.wait(0.05)
        end
    end)
end
local function stopAutoVote()
    C.AutoVoteMode = 0
    if C.VoteThread then task.cancel(C.VoteThread); C.VoteThread = nil end
end

-- ===================== GUI =====================
local function getGuiParent()
    do local ok, r = pcall(function() return gethui() end); if ok and r then return r end end
    do local ok, r = pcall(function() return game:GetService("CoreGui") end); if ok and r then return r end end
    do local ok, r = pcall(function() return LocalPlayer:WaitForChild("PlayerGui", 5) end); if ok and r then return r end end
    return nil
end
local function findIndex(tbl, value) for i, v in ipairs(tbl) do if v == value then return i end end; return 1 end

local function buildGui()
    local parent = getGuiParent()
    if not parent then warn("[ASCRON] Sem parent GUI."); return end
    local gui = Instance.new("ScreenGui")
    gui.Name = "ASCRON_MM2_v14"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 999999
    pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)
    gui.Parent = parent

    local main = Instance.new("Frame")
    main.Size = UDim2.new(0, 360, 0, 460)
    main.Position = UDim2.new(0, 30, 0, 30)
    main.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
    main.BorderSizePixel = 0; main.Active = true; main.Draggable = true
    main.Parent = gui

    local titleBar = Instance.new("Frame")
    titleBar.Size = UDim2.new(1, 0, 0, 28)
    titleBar.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
    titleBar.BorderSizePixel = 0; titleBar.Parent = main

    local titleLbl = Instance.new("TextLabel")
    titleLbl.Size = UDim2.new(1, -80, 1, 0)
    titleLbl.Position = UDim2.new(0, 10, 0, 0)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text = "ASCRON | MM2 v14"
    titleLbl.TextColor3 = Color3.fromRGB(255, 200, 0)
    titleLbl.Font = Enum.Font.GothamBold; titleLbl.TextSize = 13
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.Parent = titleBar

    local minBtn = Instance.new("TextButton")
    minBtn.Size = UDim2.new(0, 24, 0, 20)
    minBtn.Position = UDim2.new(1, -56, 0, 4)
    minBtn.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
    minBtn.Text = "—"; minBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    minBtn.Font = Enum.Font.GothamBold; minBtn.TextSize = 13
    minBtn.Parent = titleBar

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 24, 0, 20)
    closeBtn.Position = UDim2.new(1, -28, 0, 4)
    closeBtn.BackgroundColor3 = Color3.fromRGB(120, 30, 30)
    closeBtn.Text = "X"; closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 13
    closeBtn.Parent = titleBar

    local collapsed = false
    minBtn.MouseButton1Click:Connect(function()
        collapsed = not collapsed
        main.Size = collapsed and UDim2.new(0, 360, 0, 28) or UDim2.new(0, 360, 0, 460)
        minBtn.Text = collapsed and "+" or "—"
    end)
    closeBtn.MouseButton1Click:Connect(function() savePrefs(); gui:Destroy() end)

    local tabBar = Instance.new("Frame")
    tabBar.Size = UDim2.new(1, 0, 0, 26)
    tabBar.Position = UDim2.new(0, 0, 0, 28)
    tabBar.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
    tabBar.BorderSizePixel = 0; tabBar.Parent = main
    local tabLayout = Instance.new("UIListLayout")
    tabLayout.FillDirection = Enum.FillDirection.Horizontal
    tabLayout.Padding = UDim.new(0, 0)
    tabLayout.Parent = tabBar

    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, 0, 1, -54)
    content.Position = UDim2.new(0, 0, 0, 54)
    content.BackgroundTransparency = 1; content.Parent = main

    local tabs = {}
    local function makeTab(name)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0.2, 0, 1, 0)
        btn.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
        btn.Text = name; btn.TextColor3 = Color3.fromRGB(180, 180, 180)
        btn.Font = Enum.Font.GothamBold; btn.TextSize = 11
        btn.Parent = tabBar
        local frame = Instance.new("ScrollingFrame")
        frame.Size = UDim2.new(1, 0, 1, 0)
        frame.BackgroundTransparency = 1
        frame.ScrollBarThickness = 4
        frame.CanvasSize = UDim2.new(0, 0, 0, 0)
        frame.Visible = false; frame.Parent = content
        local list = Instance.new("UIListLayout")
        list.Padding = UDim.new(0, 4); list.SortOrder = Enum.SortOrder.LayoutOrder
        list.Parent = frame
        local pad = Instance.new("UIPadding")
        pad.PaddingTop = UDim.new(0, 8); pad.PaddingLeft = UDim.new(0, 8)
        pad.PaddingRight = UDim.new(0, 8); pad.Parent = frame
        tabs[name] = { btn = btn, frame = frame, list = list }
        list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            frame.CanvasSize = UDim2.new(0, 0, 0, list.AbsoluteContentSize.Y + 16)
        end)
        btn.MouseButton1Click:Connect(function()
            for _, t in pairs(tabs) do
                t.frame.Visible = false
                t.btn.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
                t.btn.TextColor3 = Color3.fromRGB(180, 180, 180)
            end
            frame.Visible = true
            btn.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
            btn.TextColor3 = Color3.fromRGB(255, 200, 0)
        end)
        return frame
    end

    local mainTab = makeTab("Main")
    local actionsTab = makeTab("Actions")
    local protectTab = makeTab("Protect")
    local serverTab = makeTab("Server")
    local voteTab = makeTab("Vote")

    local function makeLabel(parent, text, order)
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1, 0, 0, 16)
        l.BackgroundTransparency = 1
        l.Text = text; l.TextColor3 = Color3.fromRGB(150, 150, 150)
        l.Font = Enum.Font.Gotham; l.TextSize = 10
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.LayoutOrder = order; l.Parent = parent
        return l
    end
    local function makeToggle(parent, text, initial, order, cb)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 26)
        row.BackgroundTransparency = 1; row.LayoutOrder = order; row.Parent = parent
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -60, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = text; lbl.TextColor3 = Color3.fromRGB(220, 220, 220)
        lbl.Font = Enum.Font.Gotham; lbl.TextSize = 12
        lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Parent = row
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 48, 0, 20)
        btn.Position = UDim2.new(1, -52, 0.5, -10)
        btn.BackgroundColor3 = initial and Color3.fromRGB(0, 130, 0) or Color3.fromRGB(55, 55, 55)
        btn.Text = initial and "ON" or "OFF"
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.Font = Enum.Font.GothamBold; btn.TextSize = 10
        btn.Parent = row
        local state = initial
        btn.MouseButton1Click:Connect(function()
            state = not state
            btn.BackgroundColor3 = state and Color3.fromRGB(0, 130, 0) or Color3.fromRGB(55, 55, 55)
            btn.Text = state and "ON" or "OFF"
            cb(state); savePrefs()
        end)
    end
    local function makeInput(parent, labelText, value, order, cb)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 24)
        row.BackgroundTransparency = 1; row.LayoutOrder = order; row.Parent = parent
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -80, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = labelText; lbl.TextColor3 = Color3.fromRGB(220, 220, 220)
        lbl.Font = Enum.Font.Gotham; lbl.TextSize = 11
        lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Parent = row
        local box = Instance.new("TextBox")
        box.Size = UDim2.new(0, 72, 0, 20)
        box.Position = UDim2.new(1, -76, 0.5, -10)
        box.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
        box.TextColor3 = Color3.fromRGB(255, 255, 255)
        box.Text = tostring(value)
        box.Font = Enum.Font.Gotham; box.TextSize = 11
        box.Parent = row
        box.FocusLost:Connect(function() cb(box.Text); savePrefs() end)
    end
    local function makeCycle(parent, labelText, options, initialValue, order, cb)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 26)
        row.BackgroundTransparency = 1; row.LayoutOrder = order; row.Parent = parent
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -130, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = labelText; lbl.TextColor3 = Color3.fromRGB(220, 220, 220)
        lbl.Font = Enum.Font.Gotham; lbl.TextSize = 11
        lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Parent = row
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 120, 0, 20)
        btn.Position = UDim2.new(1, -124, 0.5, -10)
        btn.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.Font = Enum.Font.Gotham; btn.TextSize = 11
        btn.Parent = row
        local idx = findIndex(options, initialValue)
        btn.Text = options[idx]
        btn.MouseButton1Click:Connect(function()
            idx = idx % #options + 1
            btn.Text = options[idx]
            cb(options[idx]); savePrefs()
        end)
    end

    local order = 0
    local function nextOrder() order += 1; return order end

    makeToggle(mainTab, "AUTO FARM", C.Farming, nextOrder(), function(s)
        if s then startFarm() else stopFarm() end
    end)
    makeLabel(mainTab, "— Currency —", nextOrder())
    makeCycle(mainTab, "Target", {"Coin","Candy","SnowToken","Token","Shell"}, C.Currency, nextOrder(), function(o) C.Currency = o end)
    makeLabel(mainTab, "— Movement —", nextOrder())
    makeInput(mainTab, "Speed (studs/s, 8-60)", C.FarmSpeed, nextOrder(), function(v)
        local n = tonumber(v); if n then C.FarmSpeed = math.clamp(n, 8, 60) end
    end)
    makeCycle(mainTab, "Mode", {"Standard","Lay"}, C.FarmMode, nextOrder(), function(o) C.FarmMode = o end)
    makeLabel(mainTab, "— Bag —", nextOrder())
    makeInput(mainTab, "Threshold override (0=auto)", C.BagThresholdOverride, nextOrder(), function(v)
        local n = tonumber(v); if n then C.BagThresholdOverride = math.max(0, n) end
    end)

    local statsLbl = Instance.new("TextLabel")
    statsLbl.Size = UDim2.new(1, 0, 0, 60)
    statsLbl.BackgroundColor3 = Color3.fromRGB(30, 28, 0)
    statsLbl.BorderSizePixel = 0
    statsLbl.TextColor3 = Color3.fromRGB(255, 220, 100)
    statsLbl.Font = Enum.Font.Code; statsLbl.TextSize = 10
    statsLbl.Text = "Collected: 0\nPer hour: 0\nBag: 0/40\nFails: 0"
    statsLbl.LayoutOrder = nextOrder(); statsLbl.Parent = mainTab
    task.spawn(function()
        while statsLbl.Parent do
            task.wait(1)
            local bag = getStatValue()
            statsLbl.Text = string.format(
                "Collected: %d\nPer hour: %d\nBag: %s/%d\nFails: %d",
                C.Stats.TotalCounted, getRatePerHour(),
                bag ~= nil and tostring(bag) or "?",
                getBagThreshold(), C.CollectFails
            )
        end
    end)

    order = 0
    makeLabel(actionsTab, "— Innocent —", nextOrder())
    makeToggle(actionsTab, "Reset when bag full", C.AutoResetInnocent, nextOrder(), function(s) C.AutoResetInnocent = s end)
    makeToggle(actionsTab, "Fling murderer when full", C.AutoFlingMurderer, nextOrder(), function(s) C.AutoFlingMurderer = s end)
    makeLabel(actionsTab, "— Sheriff —", nextOrder())
    makeToggle(actionsTab, "Shoot murderer when full", C.AutoShootSheriff, nextOrder(), function(s) C.AutoShootSheriff = s end)
    makeLabel(actionsTab, "— Murderer —", nextOrder())
    makeToggle(actionsTab, "Kill all when full", C.AutoKillMurderer, nextOrder(), function(s) C.AutoKillMurderer = s end)
    makeToggle(actionsTab, "Reset when full", C.AutoResetMurderer, nextOrder(), function(s) C.AutoResetMurderer = s end)
    makeLabel(actionsTab, "— Flow —", nextOrder())
    makeToggle(actionsTab, "Reset after action", C.ResetAfterAction, nextOrder(), function(s) C.ResetAfterAction = s end)
    makeToggle(actionsTab, "Reset regardless of role", C.AutoResetAnyRole, nextOrder(), function(s) C.AutoResetAnyRole = s end)

    order = 0
    makeToggle(protectTab, "Anti-AFK", C.AntiAFK, nextOrder(), function(s) C.AntiAFK = s; if s then startAntiAFK() end end)
    makeToggle(protectTab, "Anti-Void", C.AntiVoid, nextOrder(), function(s) C.AntiVoid = s; setupAntiVoid() end)
    makeToggle(protectTab, "Anti-Fling", C.AntiFling, nextOrder(), function(s) C.AntiFling = s end)
    makeToggle(protectTab, "Noclip", C.Noclip, nextOrder(), function(s) C.Noclip = s; if s then startNoclip() else stopNoclip() end end)
    makeToggle(protectTab, "Disable 3D", C.Disable3D, nextOrder(), function(s)
        C.Disable3D = s; pcall(function() RunService:Set3dRenderingEnabled(not s) end)
    end)

    order = 0
    makeInput(serverTab, "Hop if players >", C.ServerHopPlayerCount, nextOrder(), function(v)
        local n = tonumber(v); if n then C.ServerHopPlayerCount = n end
    end)
    makeToggle(serverTab, "Hop when friend joins", C.HopOnFriendJoin, nextOrder(), function(s) C.HopOnFriendJoin = s; if s then startFriendMonitor() end end)
    local hopStatusLbl = Instance.new("TextLabel")
    hopStatusLbl.Size = UDim2.new(1, 0, 0, 24)
    hopStatusLbl.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
    hopStatusLbl.BorderSizePixel = 0
    hopStatusLbl.TextColor3 = Color3.fromRGB(255, 220, 100)
    hopStatusLbl.Font = Enum.Font.Code; hopStatusLbl.TextSize = 10
    hopStatusLbl.Text = "Hop: idle"
    hopStatusLbl.LayoutOrder = nextOrder(); hopStatusLbl.Parent = serverTab
    task.spawn(function()
        while hopStatusLbl.Parent do
            task.wait(0.5)
            hopStatusLbl.Text = "Hop: " .. (C.HopStatus ~= "" and C.HopStatus or "idle")
        end
    end)

    order = 0
    local voteOptions = {"OFF","Smallest Map","Largest Map","Random"}
    local voteMap = {OFF = 0, ["Smallest Map"] = 1, ["Largest Map"] = 2, Random = 3}
    local voteRev = {[0] = "OFF", [1] = "Smallest Map", [2] = "Largest Map", [3] = "Random"}
    makeCycle(voteTab, "Vote mode", voteOptions, voteRev[C.AutoVoteMode] or "OFF", nextOrder(), function(o)
        C.AutoVoteMode = voteMap[o] or 0
        if C.AutoVoteMode ~= 0 then startAutoVote() else stopAutoVote() end
    end)
    makeInput(voteTab, "Max votes (0=infinite)", C.AutoVoteMax, nextOrder(), function(v)
        local n = tonumber(v); if n then C.AutoVoteMax = math.max(0, n) end
    end)

    tabs["Main"].btn.MouseButton1Click:Fire()
end

-- ===================== INIT =====================
captureSource()

LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(2)
    if C.Farming then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > 0 and not isInLobby() then
            beginFarmMovement()
        end
    end
end)

startStatsTracker()
if C.AntiAFK then startAntiAFK() end
if C.AntiVoid then setupAntiVoid() end
if C.AntiFling then startAntiFling() end
if C.Noclip then startNoclip() end
if C.ServerHopPlayerCount > 0 then startHopMonitor() end
if C.HopOnFriendJoin then startFriendMonitor() end
if C.Disable3D then pcall(function() RunService:Set3dRenderingEnabled(false) end) end

buildGui()

print("[ASCRON] v14 pronta.")
print("[ASCRON] HWID: " .. HWID)
if getgenv().ASCRON_SOURCE then
    print("[ASCRON] Source: " .. #getgenv().ASCRON_SOURCE .. " bytes → " .. SOURCE_FILE)
else
    warn("[ASCRON] Source NÃO capturada. Reexecução via queue pode falhar — ative Auto-Execute no executor.")
end
