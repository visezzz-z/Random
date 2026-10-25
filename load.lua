-- ASCRON | MM2 AutoFarm v8 (Noclip + TweenService + Rayfield GUI)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local VirtualUser = game:GetService("VirtualUser")
local VirtualInputManager = game:GetService("VirtualInputManager")
local LocalPlayer = Players.LocalPlayer

-- ===================== CONFIG =====================
getgenv().ASCRON = getgenv().ASCRON or {}
local C = getgenv().ASCRON

C.Currency             = C.Currency or "Coin"
C.FarmSpeed            = C.FarmSpeed or 35
C.FarmMode             = C.FarmMode or "Standard"  -- Standard / Safe / Lay
C.SafeOffset           = C.SafeOffset or 60
C.AutoFullAction       = C.AutoFullAction or false
C.Disable3D            = C.Disable3D or false
C.ServerHopPlayerCount = C.ServerHopPlayerCount or 5
C.HopOnFriendJoin      = C.HopOnFriendJoin or false
C.BagFullThreshold     = C.BagFullThreshold or 40
C.AntiAFK              = C.AntiAFK ~= false
C.AntiVoid             = C.AntiVoid ~= false
C.AntiFling            = C.AntiFling ~= false
C.Noclip               = C.Noclip ~= false
C.AutoVoteMode         = C.AutoVoteMode or 0
C.AutoVoteMax          = C.AutoVoteMax or 0

C.Farming, C.FarmThread = false, nil
C.HopThread, C.FriendThread, C.VoteThread = nil, nil, nil
C.LastFullAction = 0
C.BodyVel, C.BlackGui = nil, nil

-- ===================== UTIL =====================
local function getChar()
    local ch = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    ch:WaitForChild("HumanoidRootPart", 5)
    return ch
end
local function getHRP() local c = getChar(); return c and c:FindFirstChild("HumanoidRootPart") end
local function getHum() local c = getChar(); return c and c:FindFirstChildOfClass("Humanoid") end

-- ===================== NOCLIP =====================
-- Desativa CanCollide em todas as partes do personagem, reaplicando a cada frame
-- para sobreviver a respawns e a partes que o jogo reative.
local noclipConn
local function startNoclip()
    if noclipConn then noclipConn:Disconnect() end
    noclipConn = RunService.Stepped:Connect(function()
        if not C.Noclip then return end
        local char = LocalPlayer.Character
        if not char then return end
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end)
end
local function stopNoclip()
    if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
    local char = LocalPlayer.Character
    if char then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = true
            end
        end
    end
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

-- ===================== MOVIMENTO (TweenService) =====================
-- Tween no HumanoidRootPart, sem BodyVelocity. Mais estável, sem glitch físico.
local function moveTo(position)
    local hrp = getHRP(); if not hrp then return false end
    local distance = (hrp.Position - position).Magnitude
    if distance < 3 then return true end

    local speed = math.clamp(C.FarmSpeed, 5, 80)
    local duration = math.max(0.08, distance / speed)
    local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
    local goal = { CFrame = CFrame.new(position) }
    local tween = TweenService:Create(hrp, tweenInfo, goal)
    tween:Play()
    tween.Completed:Wait()
    return true
end

-- ===================== COLETA (CoinContainer + TouchInterest) =====================
-- A assinatura real da moeda no MM2 é um MeshPart dentro de CoinContainer
-- com um TouchTransmitter (TouchInterest) filho.
local function getCoinContainer()
    for _, obj in ipairs(Workspace:GetChildren()) do
        local container = obj:FindFirstChild("CoinContainer")
        if container then return container end
    end
    return nil
end

local function findNearestCoin()
    local hrp = getHRP(); if not hrp then return nil end
    local container = getCoinContainer()
    if not container then return nil end

    local best, bestDist = nil, math.huge
    for _, descendant in ipairs(container:GetDescendants()) do
        if descendant:IsA("BasePart") and descendant:FindFirstChildWhichIsA("TouchTransmitter") then
            local dist = (hrp.Position - descendant.Position).Magnitude
            if dist < bestDist then
                bestDist = dist
                best = descendant
            end
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

-- ===================== MODOS (Standard/Safe/Lay) =====================
local function resetMode()
    local hum = getHum()
    if hum then
        hum.PlatformStand = false
        hum:ChangeState(Enum.HumanoidStateType.Running)
    end
end

-- ===================== BOLSA CHEIA =====================
local function getStatValue()
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    if not ls then return nil end
    local st = ls:FindFirstChild(C.Currency) or ls:FindFirstChild("Coins") or ls:FindFirstChild("Candy")
    return st and st.Value or nil
end

local function clickTool(tool)
    if not tool then return end
    pcall(function() tool.Parent = getChar() end)
    task.wait(0.05)
    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
    task.wait(0.05)
    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
end

local function fullAction()
    local ch = getChar(); local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local knife = ch:FindFirstChild("Knife") or (LocalPlayer.Backpack and LocalPlayer.Backpack:FindFirstChild("Knife"))
    local gun = ch:FindFirstChild("Gun") or (LocalPlayer.Backpack and LocalPlayer.Backpack:FindFirstChild("Gun"))

    if knife then
        local ev = knife:FindFirstChild("Events")
        local ht = ev and ev:FindFirstChild("HandleTouched")
        if ht then
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and p.Character then
                    local upper = p.Character:FindFirstChild("UpperTorso")
                    if upper then pcall(function() ht:FireServer(upper) end) end
                end
            end
        end
    elseif gun then
        local remote = ReplicatedStorage:FindFirstChild("GetPlayerData", true)
        if remote and remote:IsA("RemoteFunction") then
            local ok, data = pcall(function() return remote:InvokeServer() end)
            if ok and data then
                for name, info in pairs(data) do
                    if info.Role == "Murderer" and not info.Killed and not info.Dead then
                        local p = Players:FindFirstChild(name)
                        if p and p ~= LocalPlayer and p.Character then
                            local tHrp = p.Character:FindFirstChild("HumanoidRootPart")
                            if tHrp then
                                hrp.CFrame = CFrame.new(hrp.Position, tHrp.Position)
                                task.wait(0.1)
                                clickTool(gun)
                            end
                        end
                        break
                    end
                end
            end
        end
    else
        local hum = getHum(); if hum then hum.Health = 0 end
    end
end

-- ===================== LOOP DE FARM =====================
local function startFarm()
    if C.Farming then return end
    C.Farming = true
    C.FarmThread = task.spawn(function()
        while C.Farming do
            local hrp = getHRP()
            if not hrp then task.wait(1); continue end

            local coin = findNearestCoin()
            if coin then
                local target = coin.Position
                if C.FarmMode == "Safe" then
                    target = target - Vector3.new(0, C.SafeOffset, 0)
                end
                moveTo(target)
                if coin.Parent then collect(coin) end
            end

            if C.AutoFullAction then
                local st = getStatValue()
                if st and st >= C.BagFullThreshold and tick() - C.LastFullAction > 2 then
                    C.LastFullAction = tick()
                    fullAction()
                end
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

-- ===================== SERVER HOP =====================
local function captureSource()
    if getgenv().ASCRON_SOURCE then return end
    local ok, info = pcall(function() return debug.getinfo(1, "S") end)
    if ok and info and info.source then getgenv().ASCRON_SOURCE = info.source; return end
    local ok2, bc = pcall(function() if getscriptbytecode then return getscriptbytecode() end end)
    if ok2 and bc then getgenv().ASCRON_SOURCE = bc end
end
captureSource()

local function hop()
    local url = string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100", game.PlaceId)
    local ok, res = pcall(function() return HttpService:JSONDecode(game:HttpGet(url)) end)
    if not ok or not res or not res.data then return end
    local cands = {}
    for _, s in ipairs(res.data) do
        if s.id ~= game.JobId and s.playing < s.maxPlayers then table.insert(cands, s) end
    end
    if #cands == 0 then return end
    table.sort(cands, function(a, b) return a.playing < b.playing end)
    local src = getgenv().ASCRON_SOURCE
    if src then
        pcall(function() syn.queue_on_teleport(src) end)
        pcall(function() queue_on_teleport(src) end)
    end
    local opts = Instance.new("TeleportOptions")
    opts.ServerInstanceId = cands[1].id
    pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, cands[1].id, LocalPlayer, opts) end)
end

local function startHopMonitor()
    if C.HopThread then return end
    C.HopThread = task.spawn(function()
        while C.ServerHopPlayerCount > 0 do
            task.wait(5)
            if #Players:GetPlayers() > C.ServerHopPlayerCount then hop(); break end
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
local MAP_ORDER = {"Manor", "House 2", "Office 3", "Hospital 3", "Bank 2", "Vampire's Castle", "Mansion 2", "WorkPlace", "Hotel 2", "Farm House", "Police Station", "Factory", "Bio Lab", "Research Facility", "Mil Base"}
local function normalizeMapName(s)
    s = string.lower(s):gsub("-", " "):gsub("%s+", " ")
    return s:match("^%s*(.-)%s*$")
end
local mapRankCache = {}
local function getMapRank(raw)
    if mapRankCache[raw] then return mapRankCache[raw] end
    local low = normalizeMapName(raw)
    local rank = #MAP_ORDER + 1
    for i, name in ipairs(MAP_ORDER) do
        if low == normalizeMapName(name) then rank = i; break end
    end
    mapRankCache[raw] = rank
    return rank
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
            table.insert(open, { trigger = trigger, gui = gui, map = label.Text })
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
local function touchPad(hrp, trigger)
    if typeof(firetouchinterest) == "function" then
        firetouchinterest(hrp, trigger, 0)
        firetouchinterest(hrp, trigger, 1)
    end
end
local function startAutoVote()
    if C.VoteThread then task.cancel(C.VoteThread) end
    C.VoteThread = task.spawn(function()
        local votes = 0
        while C.AutoVoteMode ~= 0 do
            local open = getOpenVotePads()
            if #open == 0 then task.wait(0.1); continue end
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
            touchPad(hrp, target.trigger)
            task.wait(0.12)
            if hum.Health > 0 and insidePad(target.trigger, hrp.Position) then
                touchPad(hrp, target.trigger)
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

-- ===================== GUI (Rayfield) =====================
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
    Name = "ASCRON | MM2 AutoFarm",
    LoadingTitle = "Loading ASCRON...",
    LoadingSubtitle = "by the Craftsman",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "ASCRON",
        FileName = "MM2_Config"
    },
    KeySystem = false
})

-- ===== Farm Tab =====
local FarmTab = Window:CreateTab("Farm", 4483362458)

FarmTab:CreateDropdown({
    Name = "Currency",
    Options = {"Coin", "Candy", "SnowToken", "Token", "Shell"},
    CurrentOption = {C.Currency},
    Flag = "Currency",
    Callback = function(option) C.Currency = option end
})

FarmTab:CreateSlider({
    Name = "Farm Speed (studs/sec)",
    Range = {10, 80},
    Increment = 5,
    Suffix = "studs/s",
    CurrentValue = C.FarmSpeed,
    Flag = "FarmSpeed",
    Callback = function(value) C.FarmSpeed = value end
})

FarmTab:CreateDropdown({
    Name = "Farm Mode",
    Options = {"Standard", "Safe (Underground)", "Lay"},
    CurrentOption = {C.FarmMode},
    Flag = "FarmMode",
    Callback = function(option) C.FarmMode = option end
})

FarmTab:CreateSlider({
    Name = "Safe Mode Offset",
    Range = {30, 120},
    Increment = 5,
    Suffix = "studs",
    CurrentValue = C.SafeOffset,
    Flag = "SafeOffset",
    Callback = function(value) C.SafeOffset = value end
})

FarmTab:CreateToggle({
    Name = "Auto Action on Full Bag",
    CurrentValue = C.AutoFullAction,
    Flag = "AutoFullAction",
    Callback = function(state) C.AutoFullAction = state end
})

FarmTab:CreateSlider({
    Name = "Full Bag Threshold",
    Range = {10, 500},
    Increment = 10,
    Suffix = "coins",
    CurrentValue = C.BagFullThreshold,
    Flag = "BagFullThreshold",
    Callback = function(value) C.BagFullThreshold = value end
})

-- ===== Protection Tab =====
local ProtectTab = Window:CreateTab("Protection", 4483362458)

ProtectTab:CreateToggle({
    Name = "Anti-AFK",
    CurrentValue = C.AntiAFK,
    Flag = "AntiAFK",
    Callback = function(state) C.AntiAFK = state; if state then startAntiAFK() end end
})

ProtectTab:CreateToggle({
    Name = "Anti-Void",
    CurrentValue = C.AntiVoid,
    Flag = "AntiVoid",
    Callback = function(state) C.AntiVoid = state; setupAntiVoid() end
})

ProtectTab:CreateToggle({
    Name = "Anti-Fling",
    CurrentValue = C.AntiFling,
    Flag = "AntiFling",
    Callback = function(state) C.AntiFling = state end
})

ProtectTab:CreateToggle({
    Name = "Noclip",
    CurrentValue = C.Noclip,
    Flag = "Noclip",
    Callback = function(state) C.Noclip = state; if state then startNoclip() else stopNoclip() end end
})

ProtectTab:CreateToggle({
    Name = "Disable 3D Rendering",
    CurrentValue = C.Disable3D,
    Flag = "Disable3D",
    Callback = function(state)
        C.Disable3D = state
        pcall(function() RunService:Set3dRenderingEnabled(not state) end)
    end
})

-- ===== Server Tab =====
local ServerTab = Window:CreateTab("Server", 4483362458)

ServerTab:CreateSlider({
    Name = "Hop if players >",
    Range = {1, 12},
    Increment = 1,
    Suffix = "players",
    CurrentValue = C.ServerHopPlayerCount,
    Flag = "HopCount",
    Callback = function(value) C.ServerHopPlayerCount = value end
})

ServerTab:CreateToggle({
    Name = "Hop when friend joins",
    CurrentValue = C.HopOnFriendJoin,
    Flag = "HopFriend",
    Callback = function(state) C.HopOnFriendJoin = state; if state then startFriendMonitor() end end
})

-- ===== Auto-Vote Tab =====
local VoteTab = Window:CreateTab("Auto-Vote", 4483362458)

VoteTab:CreateDropdown({
    Name = "Vote Mode",
    Options = {"OFF", "Smallest Map", "Largest Map", "Random"},
    CurrentOption = {"OFF"},
    Flag = "VoteMode",
    Callback = function(option)
        local map = {OFF = 0, ["Smallest Map"] = 1, ["Largest Map"] = 2, Random = 3}
        C.AutoVoteMode = map[option] or 0
        if C.AutoVoteMode ~= 0 then startAutoVote() else stopAutoVote() end
    end
})

VoteTab:CreateSlider({
    Name = "Max Votes (0 = infinite)",
    Range = {0, 50},
    Increment = 1,
    CurrentValue = C.AutoVoteMax,
    Flag = "VoteMax",
    Callback = function(value) C.AutoVoteMax = value end
})

-- ===== Actions =====
local ActionsTab = Window:CreateTab("Actions", 4483362458)

ActionsTab:CreateButton({
    Name = "START FARM",
    Callback = function() startFarm() end
})

ActionsTab:CreateButton({
    Name = "STOP FARM",
    Callback = function() stopFarm() end
})

-- ===================== INICIALIZAÇÃO =====================
if C.AntiAFK then startAntiAFK() end
if C.AntiVoid then setupAntiVoid() end
if C.AntiFling then startAntiFling() end
if C.Noclip then startNoclip() end
if C.ServerHopPlayerCount > 0 then startHopMonitor() end
if C.HopOnFriendJoin then startFriendMonitor() end

print("[ASCRON] v8 loaded. Noclip + TweenService + Rayfield GUI.")
