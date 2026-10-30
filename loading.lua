-- ASCRON — MM2 TRADE OBSERVER v4 (TRULY PASSIVE)
-- Pass-through hook. Deferred logging. No probes. No OnClientInvoke touch.
-- Auto-saves to ASCRON/trade_YYYYMMDD_HHMMSS.log

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local Trade = RS:WaitForChild("Trade")

local SESSION_STAMP = os.date("%Y%m%d_%H%M%S")
local START_TIME = os.clock()

local CONFIG = {
    wideMode = false,
    autoSave = true,
    saveCooldown = 5,
    maxEntries = 400,
    autoSavePath = "ASCRON/trade_"..SESSION_STAMP..".log",
}

local C = {
    bg=Color3.fromRGB(16,16,20), panel=Color3.fromRGB(28,28,34),
    text=Color3.fromRGB(226,226,232), dim=Color3.fromRGB(140,140,150),
    accent=Color3.fromRGB(0,170,255), out=Color3.fromRGB(90,200,255),
    ret=Color3.fromRGB(70,210,130), inn=Color3.fromRGB(120,230,140),
    warn=Color3.fromRGB(235,90,90), ok=Color3.fromRGB(70,210,130),
    gui=Color3.fromRGB(230,190,80),
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

local frame = Instance.new("Frame", screen)
frame.Size = UDim2.fromOffset(540, 400)
frame.Position = UDim2.fromOffset(20, 80)
frame.BackgroundColor3 = C.bg
frame.BorderSizePixel = 0
frame.Active = true
Instance.new("UICorner", frame).CornerRadius = UDim.new(0,8)
local stroke = Instance.new("UIStroke", frame)
stroke.Color = Color3.fromRGB(45,45,55)
stroke.Thickness = 1

local title = Instance.new("TextLabel", frame)
title.Size = UDim2.new(1,-24,0,22)
title.Position = UDim2.fromOffset(12,8)
title.BackgroundTransparency = 1
title.Text = "ASCRON — TRADE OBSERVER v4 (PASSIVE)"
title.Font = Enum.Font.GothamBold
title.TextSize = 13
title.TextColor3 = C.accent
title.TextXAlignment = Enum.TextXAlignment.Left

local stat = Instance.new("TextLabel", frame)
stat.Size = UDim2.new(1,-24,0,14)
stat.Position = UDim2.fromOffset(12,30)
stat.BackgroundTransparency = 1
stat.Font = Enum.Font.Gotham
stat.TextSize = 10
stat.TextColor3 = C.dim
stat.TextXAlignment = Enum.TextXAlignment.Left

local function makeBtn(text, x, w, color)
    local b = Instance.new("TextButton", frame)
    b.Size = UDim2.fromOffset(w, 22)
    b.Position = UDim2.fromOffset(x, 50)
    b.BackgroundColor3 = C.panel
    b.BorderSizePixel = 0
    b.Text = text
    b.TextColor3 = color or C.text
    b.Font = Enum.Font.GothamBold
    b.TextSize = 11
    b.AutoButtonColor = false
    Instance.new("UICorner", b).CornerRadius = UDim.new(0,5)
    return b
end

local wideBtn  = makeBtn("WIDE: OFF", 12, 90, C.dim)
local clearBtn = makeBtn("CLEAR",    108, 70, C.warn)
local copyBtn  = makeBtn("COPY",     184, 70, C.ok)
local saveBtn  = makeBtn("SAVE",     260, 70, C.accent)

local logFrame = Instance.new("ScrollingFrame", frame)
logFrame.Size = UDim2.new(1,-24,1,-110)
logFrame.Position = UDim2.fromOffset(12,80)
logFrame.BackgroundColor3 = C.panel
logFrame.BorderSizePixel = 0
logFrame.ScrollBarThickness = 6
logFrame.ScrollBarImageColor3 = Color3.fromRGB(70,70,82)
logFrame.CanvasSize = UDim2.new(0,0,0,0)
logFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
Instance.new("UICorner", logFrame).CornerRadius = UDim.new(0,6)
local pad = Instance.new("UIPadding", logFrame)
pad.PaddingLeft = UDim.new(0,8); pad.PaddingRight = UDim.new(0,8)
pad.PaddingTop = UDim.new(0,6); pad.PaddingBottom = UDim.new(0,6)
local list = Instance.new("UIListLayout", logFrame)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Padding = UDim.new(0,2)

local rawLines = {}
local lineCount = 0
local lastSaveTime = 0

local function updateStat()
    stat.Text = string.format("entries %d  |  wide %s  |  saved %ds ago  |  %.0fs session",
        lineCount, CONFIG.wideMode and "on" or "off",
        math.floor(os.clock() - lastSaveTime),
        os.clock() - START_TIME)
end

local function addLine(tag, color, body)
    lineCount += 1
    local stamp = string.format("%.2f", os.clock() - START_TIME)
    table.insert(rawLines, string.format("[%s][%s] %s", stamp, tag, body))

    local lbl = Instance.new("TextLabel", logFrame)
    lbl.Size = UDim2.new(1,0,0,0)
    lbl.AutomaticSize = Enum.AutomaticSize.Y
    lbl.BackgroundTransparency = 1
    lbl.RichText = true
    lbl.Text = string.format("<font color='#%02X%02X%02X'>[%s]</font> %s",
        math.floor(color.R*255), math.floor(color.G*255), math.floor(color.B*255),
        tag, body)
    lbl.Font = Enum.Font.Code
    lbl.TextSize = 11
    lbl.TextColor3 = C.text
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextWrapped = true
    lbl.LayoutOrder = lineCount

    if lineCount > CONFIG.maxEntries then
        local cutoff = lineCount - CONFIG.maxEntries
        for _, c in ipairs(logFrame:GetChildren()) do
            if c:IsA("TextLabel") and c.LayoutOrder <= cutoff then c:Destroy() end
        end
    end

    task.defer(function()
        if logFrame.Parent then
            logFrame.CanvasPosition = Vector2.new(0, logFrame.AbsoluteCanvasSize.Y)
        end
    end)
end

local function fmt(v, depth)
    depth = depth or 0
    if depth > 2 then return "…" end
    local t = typeof(v)
    if t == "Instance" then return v:GetFullName() end
    if t == "table" then
        local parts, n = {}, 0
        for k, vv in pairs(v) do
            n += 1
            if n > 12 then table.insert(parts, "…"); break end
            if type(k) == "number" then
                table.insert(parts, fmt(vv, depth+1))
            else
                table.insert(parts, tostring(k).."="..fmt(vv, depth+1))
            end
        end
        return "{"..table.concat(parts,",").."}"
    end
    if t == "string" then return string.format("%q", v) end
    return tostring(v)
end

local function fmtArgs(pack)
    if not pack or pack.n == 0 then return "(none)" end
    local parts = {}
    for i = 1, pack.n do
        table.insert(parts, string.format("[%d]%s=%s", i, typeof(pack[i]), fmt(pack[i])))
    end
    return table.concat(parts, "  ")
end

local queue = {}
local scheduled = false

local function flush()
    scheduled = false
    if #queue == 0 then return end
    local batch = queue
    queue = {}
    for _, e in ipairs(batch) do
        addLine(e.tag, e.color, e.body)
    end
    updateStat()
    if CONFIG.autoSave and writefile then
        if os.clock() - lastSaveTime >= CONFIG.saveCooldown then
            lastSaveTime = os.clock()
            pcall(function()
                if isfolder and makefolder and not isfolder("ASCRON") then
                    makefolder("ASCRON")
                end
                writefile(CONFIG.autoSavePath, table.concat(rawLines, "\n"))
            end)
        end
    end
end

local function enqueue(tag, color, body)
    table.insert(queue, {tag=tag, color=color, body=body})
    if not scheduled then
        scheduled = true
        task.defer(flush)
    end
end

-- PASSIVE INBOUND (adds its own listener; game's listeners untouched)
local watched = {}
local function watchInbound(remote)
    if watched[remote] then return end
    watched[remote] = true
    if remote.ClassName == "RemoteEvent" or remote.ClassName == "UnreliableRemoteEvent" then
        remote.OnClientEvent:Connect(function(...)
            enqueue("IN", C.inn, string.format("%s <- %s", remote.Name, fmtArgs(table.pack(...))))
        end)
    end
end

-- PASS-THROUGH OUTBOUND HOOK
local hooked = false
do
    local mtOk, mt = pcall(getrawmetatable, game)
    if mtOk and mt and setreadonly and getnamecallmethod and newcclosure then
        local oldNamecall = mt.__namecall
        local unlocked = pcall(setreadonly, mt, false)
        if unlocked then
            mt.__namecall = newcclosure(function(self, ...)
                local method = getnamecallmethod()
                if method == "FireServer" or method == "InvokeServer" then
                    if typeof(self) == "Instance" then
                        local cn = self.ClassName
                        if cn == "RemoteEvent" or cn == "RemoteFunction" or cn == "UnreliableRemoteEvent" then
                            local remoteName = self.Name
                            local remotePath = self:GetFullName()
                            local args    = table.pack(...)
                            local results = table.pack(oldNamecall(self, ...))
                            task.defer(function()
                                if not CONFIG.wideMode and not remotePath:find("Trade", 1, true) then return end
                                enqueue("OUT", C.out, string.format("%s:%s  %s", remotePath, method, fmtArgs(args)))
                                if method == "InvokeServer" then
                                    local retStr
                                    if results.n == 0 then retStr = "nil"
                                    elseif results.n == 1 then retStr = fmt(results[1])
                                    else
                                        local parts = {}
                                        for i = 1, results.n do table.insert(parts, fmt(results[i])) end
                                        retStr = table.concat(parts, ", ")
                                    end
                                    enqueue("RET", C.ret, string.format("%s -> %s", remoteName, retStr))
                                end
                            end)
                            return table.unpack(results, 1, results.n)
                        end
                    end
                end
                return oldNamecall(self, ...)
            end)
            pcall(setreadonly, mt, true)
            hooked = true
        end
    end
end

-- WATCH TRADE REMOTES
for _, d in ipairs(Trade:GetDescendants()) do
    if d.ClassName == "RemoteEvent" or d.ClassName == "UnreliableRemoteEvent" then
        watchInbound(d)
    end
end
Trade.DescendantAdded:Connect(function(d)
    if d.ClassName == "RemoteEvent" or d.ClassName == "UnreliableRemoteEvent" then
        watchInbound(d)
    end
end)

-- TRADE GUI WATCHER
task.spawn(function()
    local seen = {}
    while screen.Parent do
        for _, g in ipairs(PlayerGui:GetChildren()) do
            if not seen[g] then
                seen[g] = true
                local n = g.Name:lower()
                if n:find("trade") or n:find("deal") then
                    enqueue("GUI", C.gui, "opened: "..g.Name)
                    for _, d in ipairs(g:GetDescendants()) do
                        if d.ClassName == "RemoteEvent" or d.ClassName == "UnreliableRemoteEvent" then
                            watchInbound(d)
                        end
                    end
                end
            end
        end
        for g in pairs(seen) do
            if not g.Parent then
                local n = g.Name:lower()
                if n:find("trade") or n:find("deal") then
                    enqueue("GUI", C.gui, "closed: "..g.Name)
                    lastSaveTime = 0  -- force save on next flush
                end
                seen[g] = nil
            end
        end
        task.wait(0.5)
    end
end)

-- DRAG
local drag, ds, sp
frame.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        drag = true; ds = i.Position; sp = frame.Position
        i.Changed:Connect(function()
            if i.UserInputState == Enum.UserInputState.End then drag = false end
        end)
    end
end)
frame.InputChanged:Connect(function(i)
    if drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - ds
        frame.Position = UDim2.new(sp.X.Scale, sp.X.Offset + d.X, sp.Y.Scale, sp.Y.Offset + d.Y)
    end
end)

-- BUTTONS
wideBtn.MouseButton1Click:Connect(function()
    CONFIG.wideMode = not CONFIG.wideMode
    wideBtn.Text = CONFIG.wideMode and "WIDE: ON" or "WIDE: OFF"
    wideBtn.TextColor3 = CONFIG.wideMode and C.ok or C.dim
    enqueue("MODE", C.dim, "wide="..tostring(CONFIG.wideMode))
end)

clearBtn.MouseButton1Click:Connect(function()
    for _, c in ipairs(logFrame:GetChildren()) do
        if c:IsA("TextLabel") then c:Destroy() end
    end
    rawLines = {}; lineCount = 0; updateStat()
end)

copyBtn.MouseButton1Click:Connect(function()
    if setclipboard then
        pcall(setclipboard, table.concat(rawLines, "\n"))
        enqueue("CPY", C.ok, string.format("%d lines to clipboard.", #rawLines))
    else
        enqueue("CPY", C.warn, "no setclipboard.")
    end
end)

saveBtn.MouseButton1Click:Connect(function()
    if not writefile then
        enqueue("SAV", C.warn, "no file API.")
        return
    end
    local ok, result = pcall(function()
        if isfolder and makefolder and not isfolder("ASCRON") then makefolder("ASCRON") end
        local path = "ASCRON/trade_"..os.date("%Y%m%d_%H%M%S")..".log"
        writefile(path, table.concat(rawLines, "\n"))
        return path
    end)
    if ok then
        lastSaveTime = os.clock()
        enqueue("SAV", C.ok, tostring(result))
    else
        enqueue("SAV", C.warn, "failed: "..tostring(result))
    end
end)

-- INIT
enqueue("BOOT", C.accent, "observer v4 online. hooked="..tostring(hooked))
enqueue("BOOT", C.dim, "passive: pass-through hook, deferred log, no probes, no OnClientInvoke.")
enqueue("BOOT", C.dim, "autosave path: "..CONFIG.autoSavePath)
updateStat()
print("[ASCRON] Observer v4 online (passive). Run trade, then COPY or SAVE.")
