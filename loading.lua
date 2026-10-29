-- ASCRON — MM2 TRADE OBSERVER v2
-- Fix: inbound capture via passive :Connect / OnClientInvoke wrapper.
-- Adds: SendRequest return-value logging, auto-accept for alt, state probe.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Trade = ReplicatedStorage:WaitForChild("Trade")

-- ============================================================
-- CONFIG
-- ============================================================
local KEYWORDS = {
    "trade","trading","confirm","accept","offer","deal",
    "session","inventory","item","send","give","swap","lock",
}
local MAX_ENTRIES = 400
local POLL_INTERVAL = 0.5
local AUTO_ACCEPT = true   -- alt accounts: auto-accept incoming trade requests

local REMOTE_CLASSES = {
    RemoteEvent = true,
    UnreliableRemoteEvent = true,
    RemoteFunction = true,
}

-- ============================================================
-- STATE
-- ============================================================
local watched = {}
local logCount = 0
local startedAt = tick()
local wideMode = false
local tradeActive = false

-- ============================================================
-- GUI
-- ============================================================
local COLORS = {
    bg=Color3.fromRGB(16,16,20), panel=Color3.fromRGB(28,28,34),
    text=Color3.fromRGB(226,226,232), dim=Color3.fromRGB(140,140,150),
    accent=Color3.fromRGB(0,170,255), out=Color3.fromRGB(90,200,255),
    inn=Color3.fromRGB(120,230,140), gui=Color3.fromRGB(230,190,80),
    warn=Color3.fromRGB(235,90,90), ok=Color3.fromRGB(70,210,130),
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
screen.Parent = parent

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(540, 400)
frame.Position = UDim2.fromOffset(20, 80)
frame.BackgroundColor3 = COLORS.bg
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = screen
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)
local stroke = Instance.new("UIStroke", frame)
stroke.Color = Color3.fromRGB(45,45,55); stroke.Thickness = 1

local title = Instance.new("TextLabel", frame)
title.Size = UDim2.new(1,-24,0,22); title.Position = UDim2.fromOffset(12,8)
title.BackgroundTransparency = 1; title.Text = "ASCRON — TRADE OBSERVER v2"
title.Font = Enum.Font.GothamBold; title.TextSize = 13
title.TextColor3 = COLORS.accent; title.TextXAlignment = Enum.TextXAlignment.Left

local statLabel = Instance.new("TextLabel", frame)
statLabel.Size = UDim2.new(1,-24,0,14); statLabel.Position = UDim2.fromOffset(12,30)
statLabel.BackgroundTransparency = 1; statLabel.Text = "booting..."
statLabel.Font = Enum.Font.Gotham; statLabel.TextSize = 10
statLabel.TextColor3 = COLORS.dim; statLabel.TextXAlignment = Enum.TextXAlignment.Left

local function makeBtn(text, x, w, color)
    local b = Instance.new("TextButton", frame)
    b.Size = UDim2.fromOffset(w, 22); b.Position = UDim2.fromOffset(x, 50)
    b.BackgroundColor3 = COLORS.panel; b.BorderSizePixel = 0
    b.Text = text; b.TextColor3 = color or COLORS.text
    b.Font = Enum.Font.GothamBold; b.TextSize = 11; b.AutoButtonColor = false
    Instance.new("UICorner", b).CornerRadius = UDim.new(0,5)
    return b
end
local wideBtn  = makeBtn("WIDE: OFF", 12, 96, COLORS.dim)
local clearBtn = makeBtn("CLEAR", 116, 72, COLORS.warn)
local copyBtn  = makeBtn("COPY LOG", 196, 90, COLORS.ok)
local probeBtn = makeBtn("PROBE STATE", 294, 104, COLORS.accent)
local autoBtn  = makeBtn(AUTO_ACCEPT and "AUTO-ACC: ON" or "AUTO-ACC: OFF", 406, 122, AUTO_ACCEPT and COLORS.ok or COLORS.dim)

local logFrame = Instance.new("ScrollingFrame", frame)
logFrame.Size = UDim2.new(1,-24,1,-110); logFrame.Position = UDim2.fromOffset(12,80)
logFrame.BackgroundColor3 = COLORS.panel; logFrame.BorderSizePixel = 0
logFrame.ScrollBarThickness = 6; logFrame.ScrollBarImageColor3 = Color3.fromRGB(70,70,82)
logFrame.CanvasSize = UDim2.new(0,0,0,0); logFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
Instance.new("UICorner", logFrame).CornerRadius = UDim.new(0,6)
local pad = Instance.new("UIPadding", logFrame)
pad.PaddingLeft=UDim.new(0,8); pad.PaddingRight=UDim.new(0,8)
pad.PaddingTop=UDim.new(0,6); pad.PaddingBottom=UDim.new(0,6)
local list = Instance.new("UIListLayout", logFrame)
list.SortOrder = Enum.SortOrder.LayoutOrder; list.Padding = UDim.new(0,2)

local rawLog = {}

local function updateStat()
    local w = 0; for _ in pairs(watched) do w += 1 end
    statLabel.Text = string.format(
        "watching %d  |  entries %d  |  trade %s  |  %.0fs",
        w, logCount, tradeActive and "ACTIVE" or "idle", tick() - startedAt)
end

local function push(prefix, prefixColor, body, bodyColor)
    logCount += 1
    table.insert(rawLog, prefix .. " " .. body)
    local lbl = Instance.new("TextLabel", logFrame)
    lbl.Size = UDim2.new(1,0,0,0); lbl.AutomaticSize = Enum.AutomaticSize.Y
    lbl.BackgroundTransparency = 1; lbl.RichText = true
    lbl.Text = string.format("<font color='#%02X%02X%02X'>[%s]</font> %s",
        math.floor(prefixColor.R*255), math.floor(prefixColor.G*255),
        math.floor(prefixColor.B*255), prefix, body)
    lbl.Font = Enum.Font.Code; lbl.TextSize = 11
    lbl.TextColor3 = bodyColor or COLORS.text
    lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.TextWrapped = true
    lbl.LayoutOrder = logCount
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

local dragging, dragStart, startPos
frame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true; dragStart = input.Position; startPos = frame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
frame.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
        local d = input.Position - dragStart
        frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset+d.X,
                                   startPos.Y.Scale, startPos.Y.Offset+d.Y)
    end
end)

-- ============================================================
-- UTIL
-- ============================================================
local function fullPath(inst)
    local parts, cur = {}, inst
    while cur and cur ~= game do
        table.insert(parts, 1, cur.Name); cur = cur.Parent
    end
    return table.concat(parts, ".")
end

local function matches(name)
    local n = name:lower()
    for _, k in ipairs(KEYWORDS) do if n:find(k) then return true end end
    return false
end

local function fmtVal(v, depth)
    depth = depth or 0
    local t = typeof(v)
    if t == "Instance" then return fullPath(v) end
    if t == "table" then
        if depth >= 2 then return "{...}" end
        local inner = {}
        local count = 0
        for k, vv in pairs(v) do
            count += 1
            if count > 20 then table.insert(inner, "..."); break end
            if type(k) == "number" then
                table.insert(inner, fmtVal(vv, depth+1))
            else
                table.insert(inner, tostring(k).."="..fmtVal(vv, depth+1))
            end
        end
        return "{"..table.concat(inner, ", ").."}"
    end
    if t == "string" then return string.format("%q", v) end
    return tostring(v)
end

local function fmtArgs(args)
    local out = {}
    for i, v in ipairs(args) do
        table.insert(out, string.format("[%d]%s=%s", i, typeof(v), fmtVal(v)))
    end
    return #out > 0 and table.concat(out, "  ") or "(no args)"
end

-- ============================================================
-- REGISTER + INBOUND OBSERVE
-- ============================================================
local function observeInbound(remote)
    if remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent") then
        remote.OnClientEvent:Connect(function(...)
            push("IN ", COLORS.inn,
                string.format("%s <- %s", remote.Name, fmtArgs({...})), COLORS.inn)
        end)
    elseif remote:IsA("RemoteFunction") then
        local prev = remote.OnClientInvoke
        remote.OnClientInvoke = function(...)
            push("INV", COLORS.inn,
                string.format("%s <- %s", remote.Name, fmtArgs({...})), COLORS.inn)
            if type(prev) == "function" then return prev(...) end
        end
    end
end

local function register(remote, reason)
    if watched[remote] then return end
    watched[remote] = true
    observeInbound(remote)
    push("TRK", COLORS.gui, string.format("%s  %s", fullPath(remote), reason or ""), COLORS.dim)
end

local function scanAndRegister(tag)
    for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
        if REMOTE_CLASSES[d.ClassName] and matches(d.Name) then
            register(d, tag)
        end
    end
end

-- ============================================================
-- NAMECALL HOOK (outbound + RemoteFunction return)
-- ============================================================
local hookArmed = false
do
    local ok, mt = pcall(getrawmetatable, game)
    if ok and mt and hookmetamethod and getnamecallmethod and setreadonly then
        local old = mt.__namecall
        setreadonly(mt, false)
        mt.__namecall = newcclosure(function(self, ...)
            local method = getnamecallmethod()
            if method == "FireServer" or method == "InvokeServer" then
                local isRemote = typeof(self) == "Instance" and
                    (self:IsA("RemoteEvent") or self:IsA("UnreliableRemoteEvent")
                     or self:IsA("RemoteFunction"))
                if isRemote and (wideMode or watched[self] or matches(self.Name)) then
                    if not watched[self] then register(self, "auto") end
                    push("OUT", COLORS.out,
                        string.format("%s:%s  %s", self.Name, method, fmtArgs({...})), COLORS.out)
                end
                local result = old(self, ...)
                if isRemote and method == "InvokeServer" and (wideMode or watched[self]) then
                    push("RET", COLORS.ok,
                        string.format("%s -> %s", self.Name, fmtVal(result)), COLORS.ok)
                end
                return result
            end
            return old(self, ...)
        end)
        setreadonly(mt, true)
        hookArmed = true
        push("HOK", COLORS.ok, "namecall armed.", COLORS.dim)
    else
        push("HOK", COLORS.warn, "no namecall hook.", COLORS.dim)
    end
end

-- ============================================================
-- AUTO-ACCEPT (alt accounts)
-- ============================================================
if AUTO_ACCEPT then
    task.spawn(function()
        local remotes = {
            Trade:FindFirstChild("GetRequest"),
            ReplicatedStorage:FindFirstChild("RequestSent"),
            ReplicatedStorage:FindFirstChild("TradeRequest"),
        }
        for _, r in ipairs(remotes) do
            if r and r:IsA("RemoteEvent") then
                r.OnClientEvent:Connect(function(requester, ...)
                    push("AAC", COLORS.ok,
                        string.format("incoming request from %s — accepting.", tostring(requester)), COLORS.ok)
                    task.wait(0.4)
                    local acc = Trade:FindFirstChild("AcceptRequest")
                    if acc then
                        pcall(function() acc:FireServer(requester) end)
                        task.wait(0.1)
                        pcall(function() acc:FireServer() end)
                    end
                end)
            end
        end
    end)
end

-- ============================================================
-- TRADE GUI POLLER
-- ============================================================
task.spawn(function()
    local seen = {}
    while screen.Parent do
        scanAndRegister("scan")
        for _, g in ipairs(PlayerGui:GetChildren()) do
            if not seen[g] then
                seen[g] = true
                local n = g.Name:lower()
                if n:find("trade") or n:find("deal") then
                    tradeActive = true
                    push("GUI+", COLORS.gui, g.Name, COLORS.gui)
                    for _, d in ipairs(g:GetDescendants()) do
                        if REMOTE_CLASSES[d.ClassName] then register(d, "gui") end
                    end
                end
            end
        end
        for g in pairs(seen) do
            if not g.Parent then
                seen[g] = nil
                if g.Name:lower():find("trade") or g.Name:lower():find("deal") then
                    tradeActive = false
                    push("GUI-", COLORS.gui, g.Name, COLORS.dim)
                end
            end
        end
        task.wait(POLL_INTERVAL)
    end
end)

-- ============================================================
-- BUTTONS
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
    rawLog = {}; logCount = 0; updateStat()
end)

copyBtn.MouseButton1Click:Connect(function()
    if setclipboard then
        pcall(setclipboard, table.concat(rawLog, "\n"))
        push("CPY", COLORS.ok, string.format("%d entries copied.", #rawLog), COLORS.ok)
    end
end)

probeBtn.MouseButton1Click:Connect(function()
    push("PRB", COLORS.accent, "state probe:", COLORS.dim)
    push("PRB", COLORS.dim, "  tradeActive(gui): "..tostring(tradeActive), COLORS.text)
    local status = Trade:FindFirstChild("GetTradeStatus")
    if status and status:IsA("RemoteFunction") then
        local ok, res = pcall(function() return status:InvokeServer() end)
        push("PRB", COLORS.dim,
            "  GetTradeStatus -> "..(ok and fmtVal(res) or ("ERR "..tostring(res))), COLORS.text)
    end
    for _, name in ipairs({"StartTrade","EndTrade","OfferItem","AcceptTrade","CompleteTrade"}) do
        local r = Trade:FindFirstChild(name)
        push("PRB", COLORS.dim, "  "..name..": "..(r and r.ClassName or "MISSING"), COLORS.text)
    end
end)

autoBtn.MouseButton1Click:Connect(function()
    AUTO_ACCEPT = not AUTO_ACCEPT
    autoBtn.Text = AUTO_ACCEPT and "AUTO-ACC: ON" or "AUTO-ACC: OFF"
    autoBtn.TextColor3 = AUTO_ACCEPT and COLORS.ok or COLORS.dim
    push("AAC", COLORS.dim, "toggle now "..tostring(AUTO_ACCEPT).." (takes effect next request)", COLORS.dim)
end)

-- ============================================================
-- INIT
-- ============================================================
push("BOOT", COLORS.accent, "observer v2 online.", COLORS.dim)
scanAndRegister("boot")
updateStat()
print("[ASCRON] Observer v2 online. Inbound now captured.")
