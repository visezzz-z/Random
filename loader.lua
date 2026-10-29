-- ASCRON — MM2 TRADE DUPE v2
-- GUI + bounded freeze. Freeze no longer trips on trade open.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer

local FREEZE_INTERVAL = 0.1
local FREEZE_WINDOW   = 1.2
local CONFIRM_BURST   = 4
local CONFIRM_DEFER   = 2

-- ============================================================
-- GUI PARENT
-- ============================================================
local function guiParent()
    if type(gethui) == "function" then
        local ok, hui = pcall(gethui)
        if ok and hui then return hui end
    end
    return LocalPlayer:WaitForChild("PlayerGui")
end

local parent = guiParent()
local old = parent:FindFirstChild("ASCRON_Dupe")
if old then old:Destroy() end

-- ============================================================
-- REMOTE FINDERS
-- ============================================================
local function findTradeConfirmRemote()
    local candidates = {
        "ConfirmTrade", "TradeConfirm", "AcceptTrade", "TradeAccept",
        "TradeConfirmRemote", "ConfirmTradeRemote", "FinishTrade", "CompleteTrade"
    }
    for _, name in ipairs(candidates) do
        local r = ReplicatedStorage:FindFirstChild(name, true)
        if r and r:IsA("RemoteEvent") then return r end
    end
    for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d:IsA("RemoteEvent") then
            local n = d.Name:lower()
            if n:find("trade") and (n:find("confirm") or n:find("accept")) then
                return d
            end
        end
    end
    return nil
end

local function findReadyRemote()
    return ReplicatedStorage:FindFirstChild("TradeReady", true)
        or ReplicatedStorage:FindFirstChild("ReadyTrade", true)
        or ReplicatedStorage:FindFirstChild("SetReady", true)
end

-- ============================================================
-- STATE
-- ============================================================
local state = { armed = true, freezing = false, running = false }

-- ============================================================
-- GUI BUILD
-- ============================================================
local COLORS = {
    bg          = Color3.fromRGB(18, 18, 22),
    panel       = Color3.fromRGB(35, 35, 42),
    panelHover  = Color3.fromRGB(48, 48, 58),
    text        = Color3.fromRGB(230, 230, 235),
    dim         = Color3.fromRGB(140, 140, 150),
    accent      = Color3.fromRGB(0, 170, 255),
    ok          = Color3.fromRGB(60, 200, 120),
    warn        = Color3.fromRGB(220, 80, 80),
    amber       = Color3.fromRGB(240, 180, 60),
}

local screen = Instance.new("ScreenGui")
screen.Name = "ASCRON_Dupe"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 999
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = parent

local frame = Instance.new("Frame")
frame.Name = "Main"
frame.Size = UDim2.fromOffset(280, 178)
frame.Position = UDim2.new(0, 20, 0, 100)
frame.BackgroundColor3 = COLORS.bg
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = screen

local fcorner = Instance.new("UICorner")
fcorner.CornerRadius = UDim.new(0, 8)
fcorner.Parent = frame

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(45, 45, 55)
stroke.Thickness = 1
stroke.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -24, 0, 22)
title.Position = UDim2.new(0, 12, 0, 10)
title.BackgroundTransparency = 1
title.Text = "ASCRON — MM2 DUPE"
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextColor3 = COLORS.accent
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = frame

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -24, 0, 16)
status.Position = UDim2.new(0, 12, 0, 34)
status.BackgroundTransparency = 1
status.Text = "No active trade."
status.Font = Enum.Font.Gotham
status.TextSize = 11
status.TextColor3 = COLORS.dim
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextTruncate = Enum.TextTruncate.AtEnd
status.Parent = frame

local function setStatus(text, color)
    status.Text = text
    status.TextColor3 = color or COLORS.dim
end

local function makeButton(text, y, height)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -24, 0, height)
    btn.Position = UDim2.new(0, 12, 0, y)
    btn.BackgroundColor3 = COLORS.panel
    btn.BorderSizePixel = 0
    btn.Text = text
    btn.TextColor3 = COLORS.text
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 13
    btn.AutoButtonColor = false
    btn.Parent = frame
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 6)
    c.Parent = btn
    btn.MouseEnter:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = COLORS.panelHover }):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = COLORS.panel }):Play()
    end)
    return btn
end

local execBtn = makeButton("EXECUTE DUPE", 60, 38)
execBtn.TextColor3 = COLORS.accent

local freezeBtn = makeButton("FREEZE: ARMED", 106, 28)
freezeBtn.TextColor3 = COLORS.ok

local note = Instance.new("TextLabel")
note.Size = UDim2.new(1, -24, 0, 14)
note.Position = UDim2.new(0, 12, 0, 140)
note.BackgroundTransparency = 1
note.Text = "Freeze runs only inside the execute window."
note.Font = Enum.Font.Gotham
note.TextSize = 10
note.TextColor3 = COLORS.dim
note.TextXAlignment = Enum.TextXAlignment.Left
note.Parent = frame

-- drag
local dragging, dragStart, startPos
frame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = frame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)
frame.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
        local d = input.Position - dragStart
        frame.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + d.X,
            startPos.Y.Scale, startPos.Y.Offset + d.Y
        )
    end
end)

-- ============================================================
-- FREEZE (BOUNDED)
-- ============================================================
local function startFreeze()
    if state.freezing then return true end
    local readyRemote = findReadyRemote()
    if not (readyRemote and readyRemote:IsA("RemoteEvent")) then
        return false
    end
    state.freezing = true
    local deadline = os.clock() + FREEZE_WINDOW
    task.spawn(function()
        while state.freezing and os.clock() < deadline do
            pcall(function()
                readyRemote:FireServer(true)
            end)
            task.wait(FREEZE_INTERVAL)
        end
        state.freezing = false
    end)
    return true
end

local function stopFreeze()
    state.freezing = false
end

-- ============================================================
-- EXECUTE
-- ============================================================
local function executeDupe()
    if state.running then return end

    local confirmRemote = findTradeConfirmRemote()
    if not confirmRemote then
        setStatus("Confirm remote not found — open trade first.", COLORS.warn)
        return
    end

    state.running = true
    execBtn.Text = "RUNNING..."
    execBtn.TextColor3 = COLORS.amber

    local froze = false
    if state.armed then
        froze = startFreeze()
        if froze then
            setStatus("Freezing trade window...", COLORS.accent)
            task.wait(0.1)
        else
            setStatus("No ready remote — running without freeze.", COLORS.amber)
        end
    end

    for i = 1, CONFIRM_BURST do
        pcall(function() confirmRemote:FireServer() end)
    end

    task.defer(function()
        for i = 1, CONFIRM_DEFER do
            pcall(function() confirmRemote:FireServer() end)
        end
    end)

    setStatus(froze and "Burst fired. Freeze window 1.2s." or "Burst fired.", COLORS.accent)

    task.delay(FREEZE_WINDOW + 0.2, function()
        stopFreeze()
        state.running = false
        execBtn.Text = "EXECUTE DUPE"
        execBtn.TextColor3 = COLORS.accent
        setStatus("Done. Check both inventories.", COLORS.ok)
    end)
end

-- ============================================================
-- WIRING
-- ============================================================
freezeBtn.MouseButton1Click:Connect(function()
    state.armed = not state.armed
    freezeBtn.Text = state.armed and "FREEZE: ARMED" or "FREEZE: OFF"
    freezeBtn.TextColor3 = state.armed and COLORS.ok or COLORS.dim
end)

execBtn.MouseButton1Click:Connect(executeDupe)

-- trade watcher (never freezes, only reports)
task.spawn(function()
    local found = false
    while screen.Parent do
        if not state.running then
            local r = findTradeConfirmRemote()
            if r and not found then
                found = true
                setStatus("Trade detected — execute ready.", COLORS.ok)
            elseif not r and found then
                found = false
                setStatus("No active trade.", COLORS.dim)
            end
        else
            found = findTradeConfirmRemote() ~= nil
        end
        task.wait(0.5)
    end
end)
