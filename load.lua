-- ASCRON | MM2 AutoFarm v10
-- Fixes: toggle bug, GUI compacta, hop com retry, prefs por HWID

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
    local ok2, cid = pcall(function()
        return game:GetService("RbxAnalyticsService"):GetClientId()
    end)
    if ok2 and type(cid) == "string" and #cid > 0 then return cid end
    return tostring(LocalPlayer.UserId)
end
local HWID = getHWID()
local PREFS_FILE = "ASCRON_MM2_" .. (tostring(HWID):gsub("[^%w_%-]", "_")) .. ".json"

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

-- Defaults
if C.Currency == nil then C.Currency = "Coin" end
if C.FarmSpeed == nil then C.FarmSpeed = 22 end
if C.FarmMode == nil then C.FarmMode = "Standard" end
if C.ServerHopPlayerCount == nil then C.ServerHopPlayerCount = 6 end
if C.HopOnFriendJoin == nil then C.HopOnFriendJoin = false end
if C.AntiAFK == nil then C.AntiAFK = true end
if C.AntiVoid == nil then C.AntiVoid = true end
if C.AntiFling == nil then C.AntiFling = true end
if C.Noclip == nil then C.Noclip = true end
if C.Disable3D == nil then C.Disable3D = false end
if C.AutoVoteMode == nil then C.AutoVoteMode = 0 end
if C.AutoVoteMax == nil then C.AutoVoteMax = 0 end
if C.AutoResetInnocent == nil then C.AutoResetInnocent = true end
if C.AutoFlingMurderer == nil then C.AutoFlingMurderer = false end
if C.AutoShootSheriff == nil then C.AutoShootSheriff = true end
if C.AutoResetAnyRole == nil then C.AutoResetAnyRole = false end
if C.AutoKillMurderer == nil then C.AutoKillMurderer = true end
if C.AutoResetMurderer == nil then C.AutoResetMurderer = false end
if C.BagThresholdOverride == nil then C.BagThresholdOverride = 0 end

-- Load prefs
local saved = Prefs.load()
if saved then
    for k, v in pairs(saved) do
        if C[k] ~= nil then C[k] = v end
    end
end

-- Runtime-only (never loaded)
C.Farming = false
C.FarmThread = nil
C.HopThread, C.FriendThread, C.VoteThread = nil, nil, nil
C.LastFullAction = 0
C.Stats = { TotalCounted = 0, SessionStart = tick(), LastSeenValue = nil }

local function savePrefs()
    Prefs.save({
        Currency = C.Currency, FarmSpeed = C.FarmSpeed, FarmMode = C.FarmMode,
        ServerHopPlayerCount = C.ServerHopPlayerCount, HopOnFriendJoin = C.HopOnFriendJoin,
        AntiAFK = C.AntiAFK, AntiVoid = C.AntiVoid, AntiFling = C.AntiFling,
        Noclip = C.Noclip, Disable3D = C.Disable3D,
        AutoVoteMode = C.AutoVoteMode, AutoVoteMax = C.AutoVoteMax,
        AutoResetInnocent = C.AutoResetInnocent, AutoFlingMurderer = C.AutoFlingMurderer,
        AutoShootSheriff = C.AutoShootSheriff, AutoResetAnyRole = C.AutoResetAnyRole,
        AutoKillMurderer = C.AutoKillMurderer, AutoResetMurderer = C.AutoResetMurderer,
        BagThresholdOverride = C.BagThresholdOverride,
    })
end

-- ===================== UTIL =====================
local function getChar()
    local ch = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    ch:WaitForChild("HumanoidRootPart", 5)
    return ch
end
local function getHRP() local c = LocalPlayer.Character; return c and c:FindFirstChild("HumanoidRootPart") end
local function getHum() local c = LocalPlayer.Character; return c and c:FindFirstChildOfClass("Humanoid") end

-- ===================== BAG THRESHOLD =====================
local EVENT_CURRENCIES = {
    Candy = true, SnowToken = true, Token = true, Shell = true,
    Egg = true, Present = true, Gift = true, Gem = true,
}
local function getBagThreshold()
    if C.BagThresholdOverride and C.BagThresholdOverride > 0 then
        return C.BagThresholdOverride
    end
    if EVENT_CURRENCIES[C.Currency] then return 50 end
    return 40
end

local CURRENCY_FIELDS = {
    Coin = {"Coins", "Coin"},
    Candy = {"Candy"},
    SnowToken = {"SnowToken", "Snow Tokens", "SnowTokens"},
    Token = {"Token", "Tokens"},
    Shell = {"Shell", "Shells"},
    Egg = {"Egg", "Eggs"},
    Present = {"Present", "Presents"},
    Gift = {"Gift", "Gifts"},
    Gem = {"Gem", "Gems"},
    Cash = {"Cash"},
    Money = {"Money"},
}
local function getStatValue()
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    if not ls then return nil end
    local fields = CURRENCY_FIELDS[C.Currency] or {C.Currency}
    for _, field in ipairs(fields) do
        local st = ls:FindFirstChild(field)
        if st then return st.Value end
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
            if part:IsA("BasePart") and part.CanCollide then
                part.CanCollide = false
            end
        end
    end)
end
local function stopNoclip()
    if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
end

-- ===================== ANTI-AFK =====================
local antiAFKConn
local function startAntiAFK()
    if antiAFKConn then antiAFKConn:Disconnect() end
    antiAFKConn = LocalPlayer.Idled:Connect(function()
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new(0, 0))
        end)
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

-- ===================== ANTI-FLING =====================
local function startAntiFling()
    local lastPos, lastCheck = nil, tick()
    RunService.Heartbeat:Connect(function()
        if not C.AntiFling then return end
        local hrp = getHRP(); if not hrp then return end
        local hum = getHum(); if not hum or hum.Health <= 0 then return end
        local now = tick()
        if lastPos and now - lastCheck > 0.1 then
            local speed = (hrp.Position - lastPos).Magnitude / (now - lastCheck)
            if speed > 150 then
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
                if lastPos then hrp.CFrame = CFrame.new(lastPos) end
            end
        end
        lastPos = hrp.Position
        lastCheck = now
    end)
end

-- ===================== COLETA =====================
local function getCoinContainer()
    for _, obj in ipairs(Workspace:GetChildren()) do
        local c = obj:FindFirstChild("CoinContainer")
        if c then return c end
    end
    return nil
end
local function findNearestCoin()
    local hrp = getHRP(); if not hrp then return nil end
    local container = getCoinContainer()
    if not container then return nil end
    local best, bestDist = nil, math.huge
    for _, d in ipairs(container:GetDescendants()) do
        if d:IsA("BasePart") and d:FindFirstChildWhichIsA("TouchTransmitter") then
            local dist = (hrp.Position - d.Position).Magnitude
            if dist < bestDist then bestDist = dist; best = d end
        end
    end
    return best
end
local function collect(coin)
    local hrp = getHRP(); if not hrp or not coin then return end
    pcall(function()
        firetouchinterest(hrp, coin, 0)
        task.wait(0.03)
        firetouchinterest(hrp, coin, 1)
    end)
end

-- ===================== MOVIMENTO (smoothstep por frame) =====================
local LAY_ROTATION = CFrame.Angles(math.rad(90), 0, 0)
local function smoothMove(targetPos, rotate90, speed)
    local hrp = getHRP(); if not hrp then return false end
    local startPos = hrp.Position
    local distance = (targetPos - startPos).Magnitude
    if distance < 1.5 then
        hrp.AssemblyLinearVelocity = Vector3.zero
        return true
    end
    speed = math.clamp(speed or C.FarmSpeed, 8, 45)
    local duration = math.max(0.25, distance / speed)
    local startTime = tick()
    local completed = false
    while C.Farming do
        local elapsed = tick() - startTime
        if elapsed >= duration then completed = true; break end
        local alpha = elapsed / duration
        local eased = alpha * alpha * (3 - 2 * alpha)
        local currentPos = startPos:Lerp(targetPos, eased)
        local goalCFrame = CFrame.new(currentPos)
        if rotate90 then goalCFrame = goalCFrame * LAY_ROTATION end
        local h = getHRP(); if not h then return false end
        h.CFrame = goalCFrame
        h.AssemblyLinearVelocity = Vector3.zero
        h.AssemblyAngularVelocity = Vector3.zero
        RunService.RenderStepped:Wait()
    end
    if not completed then return false end
    local finalCFrame = CFrame.new(targetPos)
    if rotate90 then finalCFrame = finalCFrame * LAY_ROTATION end
    local h = getHRP(); if h then
        h.CFrame = finalCFrame
        h.AssemblyLinearVelocity = Vector3.zero
    end
    return true
end

-- ===================== MODO =====================
local function applyMode()
    local hum = getHum(); if not hum then return end
    hum.PlatformStand = (C.FarmMode == "Lay" or C.FarmMode == "Safe")
end
local function resetMode()
    local hum = getHum()
    if hum then
        hum.PlatformStand = false
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end)
    end
end

-- ===================== PAPEL (detecção) =====================
local function getPlayerData()
    local remote = ReplicatedStorage:FindFirstChild("GetPlayerData", true)
    if not remote or not remote:IsA("RemoteFunction") then return nil end
    local ok, data = pcall(function() return remote:InvokeServer() end)
    return ok and data or nil
end
local function getMyRole()
    local data = getPlayerData()
    if data and data[LocalPlayer.Name] then
        local r = data[LocalPlayer.Name].Role
        if r and r ~= "None" then return r end
    end
    -- Fallback: detectar por tools (mochila + character)
    local containers = {LocalPlayer.Character, LocalPlayer:FindFirstChild("Backpack")}
    for _, container in ipairs(containers) do
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

-- ===================== AÇÕES POR PAPEL =====================
local function equipTool(name)
    local ch = LocalPlayer.Character; if not ch then return nil end
    local tool = ch:FindFirstChild(name)
    if not tool then
        local bp = LocalPlayer:FindFirstChild("Backpack")
        tool = bp and bp:FindFirstChild(name)
        if tool then
            tool.Parent = ch
            task.wait(0.25)
        end
    end
    return tool
end

local function killAll()
    local knife = equipTool("Knife")
    if not knife then return end
    local events = knife:FindFirstChild("Events")
    local handleTouched = events and events:FindFirstChild("HandleTouched")
    if not handleTouched then return end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local upper = p.Character:FindFirstChild("UpperTorso") or p.Character:FindFirstChild("Torso")
            if upper then
                pcall(function() handleTouched:FireServer(upper) end)
                task.wait(0.05)
            end
        end
    end
end

local function shootMurderer()
    local gun = equipTool("Gun")
    if not gun then return end
    local murderer = findMurderer()
    if not murderer or not murderer.Character then return end
    local mHrp = murderer.Character:FindFirstChild("HumanoidRootPart")
    local hrp = getHRP()
    if not mHrp or not hrp then return end
    hrp.CFrame = CFrame.new(hrp.Position, mHrp.Position)
    task.wait(0.1)
    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
    task.wait(0.1)
    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
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
    bv.P = 100000
    bv.Parent = mHrp
    local bg = Instance.new("BodyGyro")
    bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    bg.P = 100000
    bg.CFrame = CFrame.new(0, math.huge, 0)
    bg.Parent = mHrp
    Debris:AddItem(bv, 0.6)
    Debris:AddItem(bg, 0.6)
end

local function resetCharacter()
    local hum = getHum()
    if hum then hum.Health = 0 end
end

local function handleFullBag()
    local role = getMyRole()
    if role == "Innocent" then
        if C.AutoResetInnocent then resetCharacter(); return end
        if C.AutoFlingMurderer then flingMurderer(); task.wait(0.4) end
    elseif role == "Sheriff" then
        if C.AutoShootSheriff then shootMurderer(); task.wait(0.4) end
    elseif role == "Murderer" then
        if C.AutoKillMurderer then killAll(); task.wait(0.5) end
        if C.AutoResetMurderer then resetCharacter(); return end
    end
    if C.AutoResetAnyRole then resetCharacter() end
end

-- ===================== STATS =====================
local function startStatsTracker()
    task.spawn(function()
        local ls = LocalPlayer:FindFirstChild("leaderstats")
                or LocalPlayer:WaitForChild("leaderstats", 10)
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

-- ===================== FARM LOOP (TOGGLE FIX) =====================
local function startFarm()
    if C.Farming then return end
    C.Farming = true
    C.FarmThread = task.spawn(function()
        while C.Farming do
            local hrp = getHRP()
            if not hrp then task.wait(0.5); continue end
            applyMode()
            local coin = findNearestCoin()
            if coin then
                local targetPos = coin.Position
                local rotate90 = (C.FarmMode == "Lay" or C.FarmMode == "Safe")
                if C.FarmMode == "Safe" then
                    targetPos = targetPos - Vector3.new(0, 20, 0)
                end
                smoothMove(targetPos, rotate90, C.FarmSpeed)
                if coin.Parent then collect(coin) end
                task.wait(0.12)
            else
                task.wait(0.2)
            end
            local st = getStatValue()
            if st and st >= getBagThreshold() and tick() - C.LastFullAction > 2 then
                C.LastFullAction = tick()
                handleFullBag()
            end
            task.wait(0.05)
        end
    end)
end
local function stopFarm()
    C.Farming = false
    if C.FarmThread then task.cancel(C.FarmThread); C.FarmThread = nil end
    resetMode()
end

-- ===================== SERVER HOP (retry) =====================
local function captureSource()
    if getgenv().ASCRON_SOURCE then return end
    local ok, info = pcall(function() return debug.getinfo(1, "S") end)
    if ok and info and info.source then getgenv().ASCRON_SOURCE = info.source; return end
    local ok2, bc = pcall(function() if getscriptbytecode then return getscriptbytecode() end end)
    if ok2 and bc then getgenv().ASCRON_SOURCE = bc end
end
captureSource()

local function getServerPool()
    local url = string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100", game.PlaceId)
    local ok, res = pcall(function() return HttpService:JSONDecode(game:HttpGet(url)) end)
    if not ok or not res or not res.data then return {} end
    local pool = {}
    for _, s in ipairs(res.data) do
        if s.id ~= game.JobId and s.playing >= 1 and s.playing <= 3 and s.playing < s.maxPlayers then
            table.insert(pool, s)
        end
    end
    -- Fisher-Yates shuffle
    for i = #pool, 2, -1 do
        local j = math.random(1, i)
        pool[i], pool[j] = pool[j], pool[i]
    end
    return pool
end

local function tryTeleportOnce()
    local pool = getServerPool()
    if #pool == 0 then return false end
    local failed = false
    local failConn = TeleportService.TeleportInitFailed:Connect(function() failed = true end)
    local src = getgenv().ASCRON_SOURCE
    if src then
        pcall(function() syn.queue_on_teleport(src) end)
        pcall(function() queue_on_teleport(src) end)
    end
    for _, srv in ipairs(pool) do
        local opts = Instance.new("TeleportOptions")
        opts.ServerInstanceId = srv.id
        failed = false
        pcall(function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, srv.id, LocalPlayer, opts)
        end)
        local waitStart = tick()
        while tick() - waitStart < 2 do
            if failed then break end
            task.wait(0.1)
        end
        if not failed then
            failConn:Disconnect()
            return true
        end
    end
    failConn:Disconnect()
    return false
end

local function hop()
    for attempt = 1, 5 do
        if tryTeleportOnce() then return true end
        task.wait(2)
    end
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
            local url = "https://friends.roblox.com/v1/users/" .. LocalPlayer.UserId .. "/friends"
            local r = HttpService:JSONDecode(game:HttpGet(url))
            if r and r.data then for _, f in ipairs(r.data) do ids[f.id] = true end end
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
local function normalizeMapName(s)
    s = string.lower(s):gsub("-", " "):gsub("%s+", " ")
    return s:match("^%s*(.-)%s*$")
end
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
            if #open == 0 then task.wait(0.2); continue end
            if C.AutoVoteMax > 0 and votes >= C.AutoVoteMax then task.wait(0.5); continue end
            local target = pickVotePad(open)
            if not target then task.wait(0.1); continue end
            local char = getChar()
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if not hum or not hrp or hum.Health <= 0 then task.wait(0.2); continue end
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

-- ===================== GUI (compacta) =====================
local function getGuiParent()
    do local ok, r = pcall(function() return gethui() end); if ok and r then return r end end
    do local ok, r = pcall(function() return game:GetService("CoreGui") end); if ok and r then return r end end
    do local ok, r = pcall(function() return LocalPlayer:WaitForChild("PlayerGui", 5) end); if ok and r then return r end end
    return nil
end

local function findIndex(tbl, value)
    for i, v in ipairs(tbl) do if v == value then return i end end
    return 1
end

local function buildGui()
    local parent = getGuiParent()
    if not parent then
        warn("[ASCRON] Nenhum parent de GUI disponível.")
        return
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "ASCRON_MM2_v10"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 999999
    pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)
    gui.Parent = parent

    local main = Instance.new("Frame")
    main.Size = UDim2.new(0, 360, 0, 440)
    main.Position = UDim2.new(0, 30, 0, 30)
    main.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
    main.BorderSizePixel = 0
    main.Active = true
    main.Draggable = true
    main.Parent = gui

    local titleBar = Instance.new("Frame")
    titleBar.Size = UDim2.new(1, 0, 0, 28)
    titleBar.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
    titleBar.BorderSizePixel = 0
    titleBar.Parent = main

    local titleLbl = Instance.new("TextLabel")
    titleLbl.Size = UDim2.new(1, -80, 1, 0)
    titleLbl.Position = UDim2.new(0, 10, 0, 0)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text = "ASCRON | MM2 v10"
    titleLbl.TextColor3 = Color3.fromRGB(255, 200, 0)
    titleLbl.Font = Enum.Font.GothamBold
    titleLbl.TextSize = 13
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.Parent = titleBar

    local minBtn = Instance.new("TextButton")
    minBtn.Size = UDim2.new(0, 24, 0, 20)
    minBtn.Position = UDim2.new(1, -56, 0, 4)
    minBtn.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
    minBtn.Text = "—"
    minBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    minBtn.Font = Enum.Font.GothamBold
    minBtn.TextSize = 13
    minBtn.Parent = titleBar

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 24, 0, 20)
    closeBtn.Position = UDim2.new(1, -28, 0, 4)
    closeBtn.BackgroundColor3 = Color3.fromRGB(120, 30, 30)
    closeBtn.Text = "X"
    closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 13
    closeBtn.Parent = titleBar

    local collapsed = false
    minBtn.MouseButton1Click:Connect(function()
        collapsed = not collapsed
        main.Size = collapsed and UDim2.new(0, 360, 0, 28) or UDim2.new(0, 360, 0, 440)
        minBtn.Text = collapsed and "+" or "—"
    end)
    closeBtn.MouseButton1Click:Connect(function()
        savePrefs()
        gui:Destroy()
    end)

    local tabBar = Instance.new("Frame")
    tabBar.Size = UDim2.new(1, 0, 0, 26)
    tabBar.Position = UDim2.new(0, 0, 0, 28)
    tabBar.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
    tabBar.BorderSizePixel = 0
    tabBar.Parent = main

    local tabLayout = Instance.new("UIListLayout")
    tabLayout.FillDirection = Enum.FillDirection.Horizontal
    tabLayout.Padding = UDim.new(0, 0)
    tabLayout.Parent = tabBar

    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, 0, 1, -54)
    content.Position = UDim2.new(0, 0, 0, 54)
    content.BackgroundTransparency = 1
    content.Parent = main

    local tabs = {}
    local function makeTab(name)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0.2, 0, 1, 0)
        btn.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
        btn.Text = name
        btn.TextColor3 = Color3.fromRGB(180, 180, 180)
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 11
        btn.Parent = tabBar

        local frame = Instance.new("ScrollingFrame")
        frame.Size = UDim2.new(1, 0, 1, 0)
        frame.BackgroundTransparency = 1
        frame.ScrollBarThickness = 4
        frame.CanvasSize = UDim2.new(0, 0, 0, 0)
        frame.Visible = false
        frame.Parent = content

        local list = Instance.new("UIListLayout")
        list.Padding = UDim.new(0, 4)
        list.SortOrder = Enum.SortOrder.LayoutOrder
        list.Parent = frame

        local pad = Instance.new("UIPadding")
        pad.PaddingTop = UDim.new(0, 8)
        pad.PaddingLeft = UDim.new(0, 8)
        pad.PaddingRight = UDim.new(0, 8)
        pad.Parent = frame

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
        l.Text = text
        l.TextColor3 = Color3.fromRGB(150, 150, 150)
        l.Font = Enum.Font.Gotham
        l.TextSize = 10
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.LayoutOrder = order
        l.Parent = parent
        return l
    end

    local function makeToggle(parent, text, initial, order, cb)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 26)
        row.BackgroundTransparency = 1
        row.LayoutOrder = order
        row.Parent = parent

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -60, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = text
        lbl.TextColor3 = Color3.fromRGB(220, 220, 220)
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 12
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = row

        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 48, 0, 20)
        btn.Position = UDim2.new(1, -52, 0.5, -10)
        btn.BackgroundColor3 = initial and Color3.fromRGB(0, 130, 0) or Color3.fromRGB(55, 55, 55)
        btn.Text = initial and "ON" or "OFF"
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 10
        btn.Parent = row

        local state = initial
        btn.MouseButton1Click:Connect(function()
            state = not state
            btn.BackgroundColor3 = state and Color3.fromRGB(0, 130, 0) or Color3.fromRGB(55, 55, 55)
            btn.Text = state and "ON" or "OFF"
            cb(state)
            savePrefs()
        end)
        return row
    end

    local function makeInput(parent, labelText, value, order, cb)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 24)
        row.BackgroundTransparency = 1
        row.LayoutOrder = order
        row.Parent = parent

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -80, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = labelText
        lbl.TextColor3 = Color3.fromRGB(220, 220, 220)
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 11
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = row

        local box = Instance.new("TextBox")
        box.Size = UDim2.new(0, 72, 0, 20)
        box.Position = UDim2.new(1, -76, 0.5, -10)
        box.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
        box.TextColor3 = Color3.fromRGB(255, 255, 255)
        box.Text = tostring(value)
        box.Font = Enum.Font.Gotham
        box.TextSize = 11
        box.Parent = row
        box.FocusLost:Connect(function() cb(box.Text); savePrefs() end)
        return row
    end

    local function makeCycle(parent, labelText, options, initialValue, order, cb)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 26)
        row.BackgroundTransparency = 1
        row.LayoutOrder = order
        row.Parent = parent

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -130, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = labelText
        lbl.TextColor3 = Color3.fromRGB(220, 220, 220)
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 11
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = row

        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 120, 0, 20)
        btn.Position = UDim2.new(1, -124, 0.5, -10)
        btn.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.Font = Enum.Font.Gotham
        btn.TextSize = 11
        btn.Parent = row

        local idx = findIndex(options, initialValue)
        btn.Text = options[idx]
        btn.MouseButton1Click:Connect(function()
            idx = idx % #options + 1
            btn.Text = options[idx]
            cb(options[idx])
            savePrefs()
        end)
        return row
    end

    -- ===== MAIN TAB =====
    local order = 0
    local function nextOrder() order += 1; return order end

    makeToggle(mainTab, "AUTO FARM", C.Farming, nextOrder(), function(s)
        if s then startFarm() else stopFarm() end
    end)
    makeLabel(mainTab, "— Currency —", nextOrder())
    makeCycle(mainTab, "Target", {"Coin","Candy","SnowToken","Token","Shell"}, C.Currency, nextOrder(), function(o) C.Currency = o end)
    makeLabel(mainTab, "— Movement —", nextOrder())
    makeInput(mainTab, "Speed (studs/s, 8-45)", C.FarmSpeed, nextOrder(), function(v)
        local n = tonumber(v); if n then C.FarmSpeed = math.clamp(n, 8, 45) end
    end)
    makeCycle(mainTab, "Mode", {"Standard","Lay","Safe"}, C.FarmMode, nextOrder(), function(o) C.FarmMode = o end)
    makeLabel(mainTab, "— Bag —", nextOrder())
    makeInput(mainTab, "Threshold override (0=auto)", C.BagThresholdOverride, nextOrder(), function(v)
        local n = tonumber(v); if n then C.BagThresholdOverride = math.max(0, n) end
    end)

    local statsLbl = Instance.new("TextLabel")
    statsLbl.Size = UDim2.new(1, 0, 0, 48)
    statsLbl.BackgroundColor3 = Color3.fromRGB(30, 28, 0)
    statsLbl.BorderSizePixel = 0
    statsLbl.TextColor3 = Color3.fromRGB(255, 220, 100)
    statsLbl.Font = Enum.Font.Code
    statsLbl.TextSize = 11
    statsLbl.Text = "Collected: 0\nPer hour: 0\nBag: 0/40"
    statsLbl.LayoutOrder = nextOrder()
    statsLbl.Parent = mainTab
    task.spawn(function()
        while statsLbl.Parent do
            task.wait(1)
            statsLbl.Text = string.format(
                "Collected: %d\nPer hour: %d\nBag: %s/%d",
                C.Stats.TotalCounted, getRatePerHour(),
                tostring(getStatValue() or 0), getBagThreshold()
            )
        end
    end)

    -- ===== ACTIONS TAB =====
    order = 0
    makeLabel(actionsTab, "— Innocent —", nextOrder())
    makeToggle(actionsTab, "Reset when bag full", C.AutoResetInnocent, nextOrder(), function(s) C.AutoResetInnocent = s end)
    makeToggle(actionsTab, "Fling murderer when full", C.AutoFlingMurderer, nextOrder(), function(s) C.AutoFlingMurderer = s end)
    makeLabel(actionsTab, "— Sheriff —", nextOrder())
    makeToggle(actionsTab, "Shoot murderer when full", C.AutoShootSheriff, nextOrder(), function(s) C.AutoShootSheriff = s end)
    makeLabel(actionsTab, "— Murderer —", nextOrder())
    makeToggle(actionsTab, "Kill all when full", C.AutoKillMurderer, nextOrder(), function(s) C.AutoKillMurderer = s end)
    makeToggle(actionsTab, "Reset when full", C.AutoResetMurderer, nextOrder(), function(s) C.AutoResetMurderer = s end)
    makeLabel(actionsTab, "— Universal —", nextOrder())
    makeToggle(actionsTab, "Reset regardless of role", C.AutoResetAnyRole, nextOrder(), function(s) C.AutoResetAnyRole = s end)

    -- ===== PROTECTION TAB =====
    order = 0
    makeToggle(protectTab, "Anti-AFK", C.AntiAFK, nextOrder(), function(s)
        C.AntiAFK = s; if s then startAntiAFK() end
    end)
    makeToggle(protectTab, "Anti-Void", C.AntiVoid, nextOrder(), function(s)
        C.AntiVoid = s; setupAntiVoid()
    end)
    makeToggle(protectTab, "Anti-Fling", C.AntiFling, nextOrder(), function(s) C.AntiFling = s end)
    makeToggle(protectTab, "Noclip", C.Noclip, nextOrder(), function(s)
        C.Noclip = s; if s then startNoclip() else stopNoclip() end
    end)
    makeToggle(protectTab, "Disable 3D rendering", C.Disable3D, nextOrder(), function(s)
        C.Disable3D = s
        pcall(function() RunService:Set3dRenderingEnabled(not s) end)
    end)

    -- ===== SERVER TAB =====
    order = 0
    makeInput(serverTab, "Hop if players >", C.ServerHopPlayerCount, nextOrder(), function(v)
        local n = tonumber(v); if n then C.ServerHopPlayerCount = n end
    end)
    makeToggle(serverTab, "Hop when friend joins", C.HopOnFriendJoin, nextOrder(), function(s)
        C.HopOnFriendJoin = s; if s then startFriendMonitor() end
    end)

    -- ===== VOTE TAB =====
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
    print("[ASCRON] GUI em: " .. tostring(parent))
end

-- ===================== INIT =====================
startStatsTracker()
if C.AntiAFK then startAntiAFK() end
if C.AntiVoid then setupAntiVoid() end
if C.AntiFling then startAntiFling() end
if C.Noclip then startNoclip() end
if C.ServerHopPlayerCount > 0 then startHopMonitor() end
if C.HopOnFriendJoin then startFriendMonitor() end
if C.Disable3D then pcall(function() RunService:Set3dRenderingEnabled(false) end) end

buildGui()
print("[ASCRON] v10 pronta. Prefs: " .. PREFS_FILE)
