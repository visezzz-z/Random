-- ASCRON | MM2 AutoFarm v9 (Noclip + SmoothFrameMove + GUI própria + Ações por papel)

local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local TeleportService     = game:GetService("TeleportService")
local HttpService         = game:GetService("HttpService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local Workspace           = game:GetService("Workspace")
local Debris              = game:GetService("Debris")
local VirtualUser         = game:GetService("VirtualUser")
local VirtualInputManager = game:GetService("VirtualInputManager")
local LocalPlayer         = Players.LocalPlayer

-- ===================== CONFIG =====================
getgenv().ASCRON = getgenv().ASCRON or {}
local C = getgenv().ASCRON

C.Currency             = C.Currency or "Coin"
C.FarmSpeed            = C.FarmSpeed or 22
C.FarmMode             = C.FarmMode or "Standard"      -- Standard / Lay / Safe
C.ServerHopPlayerCount = C.ServerHopPlayerCount or 6
C.HopOnFriendJoin      = C.HopOnFriendJoin or false
C.AntiAFK              = C.AntiAFK ~= false
C.AntiVoid             = C.AntiVoid ~= false
C.AntiFling            = C.AntiFling ~= false
C.Noclip               = C.Noclip ~= false
C.Disable3D            = C.Disable3D or false
C.AutoVoteMode         = C.AutoVoteMode or 0
C.AutoVoteMax          = C.AutoVoteMax or 0

-- Ações por papel (a user pediu separado)
C.AutoResetInnocent = C.AutoResetInnocent ~= false
C.AutoFlingMurderer = C.AutoFlingMurderer or false
C.AutoShootSheriff  = C.AutoShootSheriff  ~= false
C.AutoResetAnyRole  = C.AutoResetAnyRole  or false
C.AutoKillMurderer  = C.AutoKillMurderer  ~= false
C.AutoResetMurderer = C.AutoResetMurderer or false

C.Farming = false
C.FarmThread = nil
C.HopThread, C.FriendThread, C.VoteThread = nil, nil, nil
C.LastFullAction = 0
C.BlackGui = nil
C.Stats = { TotalCounted = 0, SessionStart = tick(), LastSeenValue = nil }

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
    if EVENT_CURRENCIES[C.Currency] then return 50 end
    return 40
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

-- ===================== MOVIMENTO (por frame, smoothstep) =====================
-- Sem tween, sem BodyVelocity. Cada RenderStepped seta o CFrame direto,
-- então não há janela para a física derrubar o personagem entre passos.
local LAY_ROTATION = CFrame.Angles(math.rad(90), 0, 0)
local function smoothMove(targetPos, rotate90, speed)
    local hrp = getHRP(); if not hrp then return false end
    local startPos = hrp.Position
    local distance = (targetPos - startPos).Magnitude
    if distance < 1.5 then
        hrp.AssemblyLinearVelocity = Vector3.zero
        return true
    end

    speed = math.clamp(speed or C.FarmSpeed, 5, 45)
    local duration = math.max(0.25, distance / speed)
    local startTime = tick()

    while C.Farming do
        local elapsed = tick() - startTime
        if elapsed >= duration then break end
        local alpha = elapsed / duration
        local eased = alpha * alpha * (3 - 2 * alpha)   -- smoothstep
        local currentPos = startPos:Lerp(targetPos, eased)

        local goalCFrame = CFrame.new(currentPos)
        if rotate90 then goalCFrame = goalCFrame * LAY_ROTATION end

        local h = getHRP(); if not h then return false end
        h.CFrame = goalCFrame
        h.AssemblyLinearVelocity = Vector3.zero
        h.AssemblyAngularVelocity = Vector3.zero
        RunService.RenderStepped:Wait()
    end

    local finalCFrame = CFrame.new(targetPos)
    if rotate90 then finalCFrame = finalCFrame * LAY_ROTATION end
    local h = getHRP(); if h then
        h.CFrame = finalCFrame
        h.AssemblyLinearVelocity = Vector3.zero
    end
    return true
end

-- ===================== FARM MODE STATE =====================
local function applyMode()
    local hum = getHum(); if not hum then return end
    if C.FarmMode == "Lay" or C.FarmMode == "Safe" then
        hum.PlatformStand = true
    else
        hum.PlatformStand = false
    end
end
local function resetMode()
    local hum = getHum()
    if hum then
        hum.PlatformStand = false
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end)
    end
end

-- ===================== DETECÇÃO DE PAPEL =====================
local function getPlayerData()
    local remote = ReplicatedStorage:FindFirstChild("GetPlayerData", true)
    if not remote or not remote:IsA("RemoteFunction") then return nil end
    local ok, data = pcall(function() return remote:InvokeServer() end)
    return ok and data or nil
end
local function getMyRole()
    local data = getPlayerData()
    if data and data[LocalPlayer.Name] and data[LocalPlayer.Name].Role then
        return data[LocalPlayer.Name].Role
    end
    local ch = LocalPlayer.Character
    local bags = {ch, LocalPlayer:FindFirstChild("Backpack")}
    for _, bag in ipairs(bags) do
        if bag then
            for _, item in ipairs(bag:GetChildren()) do
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
local function killAll()
    local ch = LocalPlayer.Character
    local knife = ch and ch:FindFirstChild("Knife")
    if not knife then
        local bp = LocalPlayer:FindFirstChild("Backpack")
        knife = bp and bp:FindFirstChild("Knife")
        if knife then knife.Parent = ch end
    end
    if not knife then return end
    local events = knife:FindFirstChild("Events")
    local handleTouched = events and events:FindFirstChild("HandleTouched")
    if not handleTouched then return end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local upper = p.Character:FindFirstChild("UpperTorso") or p.Character:FindFirstChild("Torso")
            if upper then
                pcall(function() handleTouched:FireServer(upper) end)
            end
        end
    end
end

local function shootMurderer()
    local ch = LocalPlayer.Character
    local gun = ch and ch:FindFirstChild("Gun")
    if not gun then
        local bp = LocalPlayer:FindFirstChild("Backpack")
        gun = bp and bp:FindFirstChild("Gun")
        if gun then gun.Parent = ch end
    end
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

local function handleFullBag()
    local role = getMyRole()
    if not role then return end

    if role == "Innocent" then
        if C.AutoResetInnocent then
            local hum = getHum(); if hum then hum.Health = 0 end
            return
        end
        if C.AutoFlingMurderer then
            flingMurderer()
            task.wait(0.4)
        end
    elseif role == "Sheriff" then
        if C.AutoShootSheriff then
            shootMurderer()
            task.wait(0.4)
        end
    elseif role == "Murderer" then
        if C.AutoKillMurderer then
            killAll()
            task.wait(0.5)
        end
        if C.AutoResetMurderer then
            local hum = getHum(); if hum then hum.Health = 0 end
            return
        end
    end

    if C.AutoResetAnyRole then
        local hum = getHum(); if hum then hum.Health = 0 end
    end
end

-- ===================== STATS =====================
local function getStatValue()
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    if not ls then return nil end
    local st = ls:FindFirstChild(C.Currency)
            or ls:FindFirstChild("Coins")
            or ls:FindFirstChild("Candy")
    return st and st.Value or nil
end
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

-- ===================== LOOP DE FARM =====================
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
                task.wait(0.12)  -- deixa o toque assentar
            else
                task.wait(0.2)
            end

            -- Ação bolsa cheia
            local st = getStatValue()
            if st and st >= getBagThreshold() and tick() - C.LastFullAction > 2 then
                C.LastFullAction = tick()
                task.spawn(handleFullBag)
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

-- ===================== SERVER HOP (random 1–3) =====================
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

    -- Pega todos os servidores com 1–3 jogadores e escolhe UM aleatório.
    -- Assim não caímos sempre no "melhor" que todos os outros bots também buscam.
    local pool = {}
    for _, s in ipairs(res.data) do
        if s.id ~= game.JobId
           and s.playing >= 1
           and s.playing <= 3
           and s.playing < s.maxPlayers then
            table.insert(pool, s)
        end
    end
    if #pool == 0 then return end
    local target = pool[math.random(1, #pool)]

    local src = getgenv().ASCRON_SOURCE
    if src then
        pcall(function() syn.queue_on_teleport(src) end)
        pcall(function() queue_on_teleport(src) end)
    end
    local opts = Instance.new("TeleportOptions")
    opts.ServerInstanceId = target.id
    pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, target.id, LocalPlayer, opts)
    end)
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

-- ===================== GUI PRÓPRIA =====================
local function getGuiParent()
    do local ok, r = pcall(function() return gethui() end); if ok and r then return r end end
    do local ok, r = pcall(function() return game:GetService("CoreGui") end); if ok and r then return r end end
    do local ok, r = pcall(function() return LocalPlayer:WaitForChild("PlayerGui", 5) end); if ok and r then return r end end
    return nil
end

local function buildGui()
    local parent = getGuiParent()
    if not parent then
        warn("[ASCRON] Nenhum parent de GUI disponível.")
        return
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "ASCRON_MM2_v9"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 999999
    pcall(function()
        if syn and syn.protect_gui then syn.protect_gui(gui) end
    end)
    gui.Parent = parent

    local main = Instance.new("Frame")
    main.Size = UDim2.new(0, 420, 0, 520)
    main.Position = UDim2.new(0, 40, 0, 40)
    main.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
    main.BorderSizePixel = 0
    main.Active = true
    main.Draggable = true
    main.Parent = gui

    -- Title bar
    local titleBar = Instance.new("Frame")
    titleBar.Size = UDim2.new(1, 0, 0, 32)
    titleBar.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
    titleBar.BorderSizePixel = 0
    titleBar.Parent = main

    local titleLbl = Instance.new("TextLabel")
    titleLbl.Size = UDim2.new(1, -80, 1, 0)
    titleLbl.Position = UDim2.new(0, 10, 0, 0)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text = "ASCRON | MM2 AutoFarm v9"
    titleLbl.TextColor3 = Color3.fromRGB(255, 200, 0)
    titleLbl.Font = Enum.Font.GothamBold
    titleLbl.TextSize = 14
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.Parent = titleBar

    local minBtn = Instance.new("TextButton")
    minBtn.Size = UDim2.new(0, 28, 0, 22)
    minBtn.Position = UDim2.new(1, -64, 0, 5)
    minBtn.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
    minBtn.Text = "—"
    minBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    minBtn.Font = Enum.Font.GothamBold
    minBtn.TextSize = 14
    minBtn.Parent = titleBar

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 28, 0, 22)
    closeBtn.Position = UDim2.new(1, -32, 0, 5)
    closeBtn.BackgroundColor3 = Color3.fromRGB(120, 30, 30)
    closeBtn.Text = "X"
    closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 14
    closeBtn.Parent = titleBar

    local collapsed = false
    minBtn.MouseButton1Click:Connect(function()
        collapsed = not collapsed
        main.Size = collapsed and UDim2.new(0, 420, 0, 32) or UDim2.new(0, 420, 0, 520)
        minBtn.Text = collapsed and "+" or "—"
    end)
    closeBtn.MouseButton1Click:Connect(function() gui:Destroy() end)

    -- Tab bar
    local tabBar = Instance.new("Frame")
    tabBar.Size = UDim2.new(1, 0, 0, 30)
    tabBar.Position = UDim2.new(0, 0, 0, 32)
    tabBar.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
    tabBar.BorderSizePixel = 0
    tabBar.Parent = main

    local tabLayout = Instance.new("UIListLayout")
    tabLayout.FillDirection = Enum.FillDirection.Horizontal
    tabLayout.Padding = UDim.new(0, 0)
    tabLayout.Parent = tabBar

    -- Content
    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, 0, 1, -62)
    content.Position = UDim2.new(0, 0, 0, 62)
    content.BackgroundTransparency = 1
    content.Parent = main

    local tabs = {}
    local activeTab = nil
    local function makeTab(name)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 100, 1, 0)
        btn.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
        btn.Text = name
        btn.TextColor3 = Color3.fromRGB(180, 180, 180)
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 12
        btn.Parent = tabBar

        local frame = Instance.new("ScrollingFrame")
        frame.Size = UDim2.new(1, 0, 1, 0)
        frame.BackgroundTransparency = 1
        frame.ScrollBarThickness = 4
        frame.CanvasSize = UDim2.new(0, 0, 0, 0)
        frame.Visible = false
        frame.Parent = content

        local list = Instance.new("UIListLayout")
        list.Padding = UDim.new(0, 6)
        list.SortOrder = Enum.SortOrder.LayoutOrder
        list.Parent = frame

        local pad = Instance.new("UIPadding")
        pad.PaddingTop = UDim.new(0, 10)
        pad.PaddingLeft = UDim.new(0, 10)
        pad.PaddingRight = UDim.new(0, 10)
        pad.Parent = frame

        tabs[name] = { btn = btn, frame = frame, list = list }

        local function updateCanvas()
            frame.CanvasSize = UDim2.new(0, 0, 0, list.AbsoluteContentSize.Y + 20)
        end
        list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvas)

        btn.MouseButton1Click:Connect(function()
            for _, t in pairs(tabs) do
                t.frame.Visible = false
                t.btn.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
                t.btn.TextColor3 = Color3.fromRGB(180, 180, 180)
            end
            frame.Visible = true
            btn.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
            btn.TextColor3 = Color3.fromRGB(255, 200, 0)
            activeTab = name
        end)

        return frame
    end

    local mainTab = makeTab("Main")
    local actionsTab = makeTab("Actions")
    local protectTab = makeTab("Protection")
    local serverTab = makeTab("Server")
    local voteTab = makeTab("Vote")

    -- ===== WIDGETS =====
    local function makeLabel(parent, text, order)
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1, 0, 0, 18)
        l.BackgroundTransparency = 1
        l.Text = text
        l.TextColor3 = Color3.fromRGB(160, 160, 160)
        l.Font = Enum.Font.Gotham
        l.TextSize = 11
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.LayoutOrder = order
        l.Parent = parent
        return l
    end

    local function makeToggle(parent, text, initial, order, cb)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 30)
        row.BackgroundTransparency = 1
        row.LayoutOrder = order
        row.Parent = parent

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -60, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = text
        lbl.TextColor3 = Color3.fromRGB(220, 220, 220)
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 13
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = row

        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 50, 0, 22)
        btn.Position = UDim2.new(1, -55, 0.5, -11)
        btn.BackgroundColor3 = initial and Color3.fromRGB(0, 130, 0) or Color3.fromRGB(55, 55, 55)
        btn.Text = initial and "ON" or "OFF"
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 11
        btn.Parent = row

        local state = initial
        btn.MouseButton1Click:Connect(function()
            state = not state
            btn.BackgroundColor3 = state and Color3.fromRGB(0, 130, 0) or Color3.fromRGB(55, 55, 55)
            btn.Text = state and "ON" or "OFF"
            cb(state)
        end)
        return row
    end

    local function makeInput(parent, labelText, value, order, cb)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 26)
        row.BackgroundTransparency = 1
        row.LayoutOrder = order
        row.Parent = parent

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -90, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = labelText
        lbl.TextColor3 = Color3.fromRGB(220, 220, 220)
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 12
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = row

        local box = Instance.new("TextBox")
        box.Size = UDim2.new(0, 80, 0, 22)
        box.Position = UDim2.new(1, -85, 0.5, -11)
        box.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
        box.TextColor3 = Color3.fromRGB(255, 255, 255)
        box.Text = tostring(value)
        box.Font = Enum.Font.Gotham
        box.TextSize = 12
        box.Parent = row
        box.FocusLost:Connect(function() cb(box.Text) end)
        return row
    end

    local function makeCycle(parent, labelText, options, currentIndex, order, cb)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 30)
        row.BackgroundTransparency = 1
        row.LayoutOrder = order
        row.Parent = parent

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -140, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = labelText
        lbl.TextColor3 = Color3.fromRGB(220, 220, 220)
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 12
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = row

        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 130, 0, 22)
        btn.Position = UDim2.new(1, -135, 0.5, -11)
        btn.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
        btn.Text = options[currentIndex]
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.Font = Enum.Font.Gotham
        btn.TextSize = 12
        btn.Parent = row

        local idx = currentIndex
        btn.MouseButton1Click:Connect(function()
            idx = idx % #options + 1
            btn.Text = options[idx]
            cb(options[idx], idx)
        end)
        return row
    end

    -- ===== MAIN TAB =====
    local order = 0
    local function nextOrder() order += 1; return order end

    makeToggle(mainTab, "AUTO FARM", C.Farming, nextOrder(), function(s)
        C.Farming = s
        if s then startFarm() else stopFarm() end
    end)

    makeLabel(mainTab, "— Currency —", nextOrder())
    makeCycle(mainTab, "Target", {"Coin","Candy","SnowToken","Token","Shell"}, 1, nextOrder(), function(option)
        C.Currency = option
    end)

    makeLabel(mainTab, "— Movement —", nextOrder())
    makeInput(mainTab, "Speed (studs/sec)", C.FarmSpeed, nextOrder(), function(v)
        local n = tonumber(v); if n then C.FarmSpeed = math.clamp(n, 8, 45) end
    end)
    makeCycle(mainTab, "Mode", {"Standard","Lay","Safe"}, 1, nextOrder(), function(option)
        C.FarmMode = option
    end)

    makeLabel(mainTab, "— Session Stats —", nextOrder())
    local statsLbl = Instance.new("TextLabel")
    statsLbl.Size = UDim2.new(1, 0, 0, 50)
    statsLbl.BackgroundColor3 = Color3.fromRGB(30, 28, 0)
    statsLbl.BorderSizePixel = 0
    statsLbl.TextColor3 = Color3.fromRGB(255, 220, 100)
    statsLbl.Font = Enum.Font.Code
    statsLbl.TextSize = 13
    statsLbl.Text = "Collected: 0\nPer hour: 0\nBag threshold: 40"
    statsLbl.LayoutOrder = nextOrder()
    statsLbl.Parent = mainTab

    task.spawn(function()
        while statsLbl.Parent do
            task.wait(1)
            statsLbl.Text = string.format(
                "Collected: %d\nPer hour: %d\nBag threshold: %d",
                C.Stats.TotalCounted, getRatePerHour(), getBagThreshold()
            )
        end
    end)

    -- ===== ACTIONS TAB =====
    order = 0
    makeLabel(actionsTab, "— Innocent —", nextOrder())
    makeToggle(actionsTab, "Reset when bag full", C.AutoResetInnocent, nextOrder(), function(s) C.AutoResetInnocent = s end)
    makeToggle(actionsTab, "Fling murderer when bag full", C.AutoFlingMurderer, nextOrder(), function(s) C.AutoFlingMurderer = s end)

    makeLabel(actionsTab, "— Sheriff —", nextOrder())
    makeToggle(actionsTab, "Shoot murderer when bag full", C.AutoShootSheriff, nextOrder(), function(s) C.AutoShootSheriff = s end)

    makeLabel(actionsTab, "— Murderer —", nextOrder())
    makeToggle(actionsTab, "Kill all when bag full", C.AutoKillMurderer, nextOrder(), function(s) C.AutoKillMurderer = s end)
    makeToggle(actionsTab, "Reset when bag full", C.AutoResetMurderer, nextOrder(), function(s) C.AutoResetMurderer = s end)

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
        C.Noclip = s
        if s then startNoclip() else stopNoclip() end
    end)
    makeToggle(protectTab, "Disable 3D Rendering", C.Disable3D, nextOrder(), function(s)
        C.Disable3D = s
        pcall(function() RunService:Set3dRenderingEnabled(not s) end)
    end)

    -- ===== SERVER TAB =====
    order = 0
    makeInput(serverTab, "Hop if players >", C.ServerHopPlayerCount, nextOrder(), function(v)
        local n = tonumber(v); if n then C.ServerHopPlayerCount = n end
    end)
    makeToggle(serverTab, "Hop when friend joins", C.HopOnFriendJoin, nextOrder(), function(s)
        C.HopOnFriendJoin = s
        if s then startFriendMonitor() end
    end)

    -- ===== VOTE TAB =====
    order = 0
    makeCycle(voteTab, "Vote mode", {"OFF","Smallest Map","Largest Map","Random"}, 1, nextOrder(), function(option)
        local map = {OFF = 0, ["Smallest Map"] = 1, ["Largest Map"] = 2, Random = 3}
        C.AutoVoteMode = map[option] or 0
        if C.AutoVoteMode ~= 0 then startAutoVote() else stopAutoVote() end
    end)
    makeInput(voteTab, "Max votes (0 = infinite)", C.AutoVoteMax, nextOrder(), function(v)
        local n = tonumber(v); if n then C.AutoVoteMax = math.max(0, n) end
    end)

    -- Ativa primeira aba
    tabs["Main"].btn.MouseButton1Click:Fire()

    print("[ASCRON] GUI construída em: " .. tostring(parent))
end

-- ===================== INICIALIZAÇÃO =====================
startStatsTracker()
if C.AntiAFK then startAntiAFK() end
if C.AntiVoid then setupAntiVoid() end
if C.AntiFling then startAntiFling() end
if C.Noclip then startNoclip() end
if C.ServerHopPlayerCount > 0 then startHopMonitor() end
if C.HopOnFriendJoin then startFriendMonitor() end

buildGui()
print("[ASCRON] v9 pronta.")
