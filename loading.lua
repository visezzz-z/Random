-- ASCRON — MM2 TRADE OBSERVER
-- Passive recon. Hooks namecall for FireServer/InvokeServer/Connect on trade remotes.
-- Logs outbound payloads, inbound payloads, trade GUI lifecycle, new remotes.
-- No fires, no writes, no mutation. Copy the log back to the workshop.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- ============================================================
-- CONFIG
-- ============================================================
local KEYWORDS = {
    "trade","trading","confirm","accept","offer","deal",
    "session","inventory","item","send","give","swap","lock",
}
local MAX_ENTRIES = 400
local POLL_INTERVAL = 0.5

local REMOTE_CLASSES = {
    RemoteEvent = true,
    UnreliableRemoteEvent = true,
    RemoteFunction = true,
}

-- ============================================================
-- STATE
-- ============================================================
local watched = {}         -- [remote] = true
local signalOwner = {}     -- [OnClientEvent/OnClientInvoke signal] = remote
local wideMode = false
local logCount = 0
local startedAt = tick()

-- ============================================================
-- GUI
-- ============================================================
local COLORS = {
    bg       = Color3.fromRGB(16, 16, 20),
    panel    = Color3.fromRGB(28, 28, 34),
    text     = Color3.fromRGB(226, 226, 232),
    dim      = Color3.fromRGB(140, 140, 150),
    accent   = Color3.fromRGB(0, 170, 255),
    out      = Color3.fromRGB(90, 200, 255),
    inn      = Color3.fromRGB(120, 230, 140),
    gui      = Color3.fromRGB(230, 190, 80),
    warn     = Color3.fromRGB(235, 90, 90),
    ok       = Color3.fromRGB(70, 210, 130),
}

local function guiParent()
    if type(gethui) == "function" then
        local ok, hui = pcall(gethui)
        if ok and hui then return hui end
    end
    return PlayerGui
end

local parent = guiParent()
local old = parent:FindFirstChild("ASCRON_Observer")
if old then old:Destroy() end

local screen = Instance.new("ScreenGui")
screen.Name = "ASCRON_Observer"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 999
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = parent

local frame = Instance.new("Frame")
frame.Name = "Main"
frame.Size = UDim2.fromOffset(520, 380)
frame.Position = UDim2.new(0, 20, 0, 80)
frame.BackgroundColor3 = COLORS.bg
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = screen

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = frame

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(45, 45, 55)
stroke.Thickness = 1
stroke.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -24, 0, 22)
title.Position = UDim2.new(0, 12, 0, 8)
title.BackgroundTransparency = 1
title.Text = "ASCRON — TRADE OBSERVER"
title.Font = Enum.Font.GothamBold
title.TextSize = 13
title.TextColor3 = COLORS.accent
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = frame

local statLabel = Instance.new("TextLabel")
statLabel.Size = UDim2.new(1, -24, 0, 14)
statLabel.Position = UDim2.new(0, 12, 0, 30)
statLabel.BackgroundTransparency = 1
statLabel.Text = "watching 0 remotes  |  entries 0"
statLabel.Font = Enum.Font.Gotham
statLabel.TextSize = 10
statLabel.TextColor3 = COLORS.dim
statLabel.TextXAlignment = Enum.TextXAlignment.Left
statLabel.Parent = frame

-- buttons
local function makeButton(text, x, w, color)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(w, 22)
    b.Position = UDim2.fromOffset(x, 50)
    b.BackgroundColor3 = COLORS.panel
    b.BorderSizePixel = 0
    b.Text = text
    b.TextColor3 = color or COLORS.text
    b.Font = Enum.Font.GothamBold
    b.TextSize = 11
    b.AutoButtonColor = false
    b.Parent = frame
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 5)
    c.Parent = b
    return b
end

local wideBtn = makeButton("WIDE: OFF", 12, 96, COLORS.dim)
local clearBtn = makeButton("CLEAR", 116, 72, COLORS.warn)
local copyBtn  = makeButton("COPY LOG", 196, 90, COLORS.ok)
local dumpBtn  = makeButton("DUMP REMOTES", 294, 116, COLORS.accent)
local exportBtn= makeButton("SAVE FILE", 418, 90, COLORS.accent)

-- log view
local logFrame = Instance.new("ScrollingFrame")
logFrame.Size = UDim2.new(1, -24, 1, -110)
logFrame.Position = UDim2.fromOffset(12, 80)
logFrame.BackgroundColor3 = COLORS.panel
logFrame.BorderSizePixel = 0
logFrame.ScrollBarThickness = 6
logFrame.ScrollBarImageColor3 = Color3.fromRGB(70, 70, 82)
logFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
logFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
logFrame.Parent = frame

local logCorner = Instance.new("UICorner")
logCorner.CornerRadius = UDim.new(0, 6)
logCorner.Parent = logFrame

local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 8)
padding.PaddingRight = UDim.new(0, 8)
padding.PaddingTop = UDim.new(0, 6)
padding.PaddingBottom = UDim.new(0, 6)
padding.Parent = logFrame

local list = Instance.new("UIListLayout")
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Padding = UDim.new(0, 2)
list.Parent = logFrame

local rawLog = {}

local function updateStat()
    local w = 0
    for _ in pairs(watched) do w += 1 end
    statLabel.Text = string.format("watching %d remotes  |  entries %d  |  %.0fs",
        w, logCount, tick() - startedAt)
end

local function timestamp()
    return string.format("%6.2f", tick() - startedAt)
end

local function pushLog(line, color)
    logCount += 1
    table.insert(rawLog, line)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 0, 0)
    lbl.AutomaticSize = Enum.AutomaticSize.Y
    lbl.BackgroundTransparency = 1
    lbl.Text = line
    lbl.Font = Enum.Font.Code
    lbl.TextSize = 11
    lbl.TextColor3 = color or COLORS.text
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextWrapped = true
    lbl.LayoutOrder = logCount
    lbl.Parent = logFrame

    -- cap entries
    if logCount > MAX_ENTRIES then
        local children = logFrame:GetChildren()
        for _, c in ipairs(children) do
            if c:IsA("TextLabel") and c.LayoutOrder <= logCount - MAX_ENTRIES then
                c:Destroy()
            end
        end
    end

    task.defer(function()
        logFrame.CanvasPosition = Vector2.new(0, logFrame.AbsoluteCanvasSize.Y)
    end)

    updateStat()
end

local function tag(t, color)
    return string.format("<font color='#%02X%02X%02X'>[%s]</font>",
        math.floor(color.R*255), math.floor(color.G*255), math.floor(color.B*255), t)
end

-- use RichText on labels for tag color
local function pushLogRich(prefix, prefixColor, body, bodyColor)
    logCount += 1
    table.insert(rawLog, prefix .. " " .. body)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 0, 0)
    lbl.AutomaticSize = Enum.AutomaticSize.Y
    lbl.BackgroundTransparency = 1
    lbl.RichText = true
    lbl.Text = tag(prefix, prefixColor) .. " " .. body
    lbl.Font = Enum.Font.Code
    lbl.TextSize = 11
    lbl.TextColor3 = bodyColor or COLORS.text
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextWrapped = true
    lbl.LayoutOrder = logCount
    lbl.Parent = logFrame

    if logCount > MAX_ENTRIES then
        for _, c in ipairs(logFrame:GetChildren()) do
            if c:IsA("TextLabel") and c.LayoutOrder <= logCount - MAX_ENTRIES then
                c:Destroy()
            end
        end
    end

    task.defer(function()
        logFrame.CanvasPosition = Vector2.new(0, logFrame.AbsoluteCanvasSize.Y)
    end)

    updateStat()
end

-- drag
local dragging, dragStart, startPos
frame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = frame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
frame.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
        local d = input.Position - dragStart
        frame.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + d.X,
            startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)

-- ============================================================
-- UTIL
-- ============================================================
local function fullPath(inst)
    local parts, cur = {}, inst
    while cur and cur ~= game do
        table.insert(parts, 1, cur.Name)
        cur = cur.Parent
    end
    return table.concat(parts, ".")
end

local function matches(name)
    local n = name:lower()
    for _, k in ipairs(KEYWORDS) do
        if n:find(k) then return true end
    end
    return false
end

local function fmtArgs(args)
    local out = {}
    for i, v in ipairs(args) do
        local t = typeof(v)
        local s
        if t == "Instance" then
            s = fullPath(v)
        elseif t == "table" then
            s = "{" .. #v .. "}"
            -- shallow dump
            local inner = {}
            for k, vv in pairs(v) do
                if type(k) == "number" then
                    table.insert(inner, tostring(vv))
                else
                    table.insert(inner, tostring(k) .. "=" .. tostring(vv))
                end
            end
            s = "{" .. table.concat(inner, ", ") .. "}"
        else
            s = tostring(v)
        end
        table.insert(out, string.format("[%d]%s=%s", i, t, s))
    end
    return table.concat(out, "  ")
end

-- ============================================================
-- TRACK REGISTRATION
-- ============================================================
local function register(remote, reason)
    if watched[remote] then return end
    watched[remote] = true
    signalOwner[remote.OnClientEvent]   = remote
    signalOwner[remote.OnClientInvoke]  = remote
    pushLogRich("TRACK", COLORS.gui,
        string.format("%s  %s", fullPath(remote), reason or ""), COLORS.dim)
    updateStat()
end

local function scanAndRegister(tag)
    for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
        if REMOTE_CLASSES[d.ClassName] and matches(d.Name) then
            register(d, tag)
        end
    end
end

-- ============================================================
-- NAMECALL HOOK
-- ============================================================
local hookArmed = false
do
    local ok, mt = pcall(getrawmetatable, game)
    if ok and mt and hookmetamethod and getnamecallmethod and setreadonly then
        local old
        old = mt.__namecall
        setreadonly(mt, false)
        mt.__namecall = newcclosure(function(self, ...)
            local method = getnamecallmethod()

            -- OUTBOUND
            if REMOTE_CLASSES[typeof(self)] == nil and typeof(self) then
                -- not a remote, fallthrough
            end

            if method == "FireServer" or method == "InvokeServer" then
                if REMOTE_CLASSES[typeof(self)] or
                   (typeof(self) == "Instance" and (self:IsA("RemoteEvent") or self:IsA("UnreliableRemoteEvent") or self:IsA("RemoteFunction"))) then
                    if wideMode or watched[self] or matches(self.Name) then
                        if not watched[self] then register(self, "auto") end
                        pushLogRich("OUT", COLORS.out,
                            string.format("%s.%s  %s", fullPath(self), method, fmtArgs({...})), COLORS.out)
                    end
                end
                local result = old(self, ...)
                if method == "InvokeServer" and (wideMode or watched[self]) then
                    pushLogRich("RET", COLORS.ok,
                        string.format("%s -> %s", fullPath(self), tostring(result)), COLORS.ok)
                end
                return result
            end

            -- INBOUND WRAP (Connect / Once on OnClientEvent / OnClientInvoke)
            if method == "Connect" or method == "Once" or method == "ConnectParallel" then
                local owner = signalOwner[self]
                if owner then
                    local args = { ... }
                    local cb = args[1]
                    if type(cb) == "function" then
                        args[1] = function(...)
                            pushLogRich("IN", COLORS.inn,
                                string.format("%s <- %s", fullPath(owner), fmtArgs({...})), COLORS.inn)
                            return cb(...)
                        end
                    end
                    return old(self, table.unpack(args))
                end
            end

            return old(self, ...)
        end)
        setreadonly(mt, true)
        hookArmed = true
        pushLogRich("HOOK", COLORS.ok, "namecall armed.", COLORS.dim)
    else
        pushLogRich("HOOK", COLORS.warn, "executor lacks namecall hook — dump only.", COLORS.dim)
    end
end

-- ============================================================
-- GUI LIFECYCLE POLLER
-- ============================================================
task.spawn(function()
    local seen = {}
    while screen.Parent do
        -- new remotes in RS
        scanAndRegister("scan")

        -- trade GUIs
        for _, g in ipairs(PlayerGui:GetChildren()) do
            if not seen[g] then
                seen[g] = true
                local n = g.Name:lower()
                if n:find("trade") or n:find("trading") or n:find("deal") then
                    pushLogRich("GUI+", COLORS.gui, g.Name, COLORS.gui)
                    -- walk it
                    for _, d in ipairs(g:GetDescendants()) do
                        if REMOTE_CLASSES[d.ClassName] then
                            register(d, "in gui " .. g.Name)
                        end
                    end
                end
            end
        end
        -- removed GUIs
        for g in pairs(seen) do
            if not g.Parent then
                seen[g] = nil
                pushLogRich("GUI-", COLORS.gui, g.Name, COLORS.dim)
            end
        end

        -- if trade GUI is open, dump its visible children once
        task.wait(POLL_INTERVAL)
    end
end)

-- ============================================================
-- BUTTON WIRING
-- ============================================================
wideBtn.MouseButton1Click:Connect(function()
    wideMode = not wideMode
    wideBtn.Text = wideMode and "WIDE: ON" or "WIDE: OFF"
    wideBtn.TextColor3 = wideMode and COLORS.ok or COLORS.dim
    if wideMode then
        for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
            if REMOTE_CLASSES[d.ClassName] then register(d, "wide") end
        end
    end
end)

clearBtn.MouseButton1Click:Connect(function()
    for _, c in ipairs(logFrame:GetChildren()) do
        if c:IsA("TextLabel") then c:Destroy() end
    end
    rawLog = {}
    logCount = 0
    updateStat()
end)

copyBtn.MouseButton1Click:Connect(function()
    local s = table.concat(rawLog, "\n")
    if setclipboard then
        pcall(setclipboard, s)
        pushLogRich("COPY", COLORS.ok, string.format("%d entries to clipboard.", #rawLog), COLORS.ok)
    else
        pushLogRich("COPY", COLORS.warn, "setclipboard unavailable.", COLORS.warn)
    end
end)

dumpBtn.MouseButton1Click:Connect(function()
    pushLogRich("DUMP", COLORS.accent, "all remotes in RS:", COLORS.dim)
    local n = 0
    for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
        if REMOTE_CLASSES[d.ClassName] then
            n += 1
            local w = watched[d] and "*" or " "
            pushLogRich("  "..w, COLORS.dim,
                string.format("%-16s %s", d.ClassName, fullPath(d)), COLORS.text)
        end
    end
    pushLogRich("DUMP", COLORS.accent, n .. " remotes total.", COLORS.dim)
end)

exportBtn.MouseButton1Click:Connect(function()
    if not (writefile and isfolder and makefolder) then
        pushLogRich("SAVE", COLORS.warn, "no file API.", COLORS.warn)
        return
    end
    if not isfolder("ASCRON") then makefolder("ASCRON") end
    local path = "ASCRON/observer_" .. os.date("%Y%m%d_%H%M%S") .. ".log"
    local ok, err = pcall(writefile, path, table.concat(rawLog, "\n"))
    if ok then
        pushLogRich("SAVE", COLORS.ok, path, COLORS.ok)
    else
        pushLogRich("SAVE", COLORS.warn, tostring(err), COLORS.warn)
    end
end)

-- ============================================================
-- INITIAL SWEEP
-- ============================================================
pushLogRich("BOOT", COLORS.accent, "observer online.", COLORS.dim)
scanAndRegister("boot")
updateStat()

print("[ASCRON] Observer online. Open a trade, place items, confirm. Copy the log.")
