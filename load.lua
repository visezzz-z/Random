-- Lambda Hub | v0.21 | By ASCRON
-- Stealth farm | Rewritten ESP | URL reexec | Debounced round detection

print("[Lambda] v0.21 loading")

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

local function hwid()
    local ok, id = pcall(function() return gethwid() end)
    if ok and type(id) == "string" and #id > 0 then return id end
    local ok2, cid = pcall(function() return game:GetService("RbxAnalyticsService"):GetClientId() end)
    if ok2 and type(cid) == "string" and #cid > 0 then return cid end
    return tostring(LocalPlayer.UserId)
end
local HWID = hwid()
local PREFS = "LAMBDA_HUB_" .. (HWID:gsub("[^%w_%-]", "_")) .. ".json"
local SRC = "LAMBDA_SOURCE.lua"

local function env() local e = {}; pcall(function() local g = getgenv(); if type(g)=="table" then e=g end end); return e end
local function prefsLoad()
    local e = env()
    local rd = type(readfile) == "function" and readfile or e.readfile
    if not rd then return nil end
    local ok, d = pcall(rd, PREFS)
    if ok and d then local ok2, dec = pcall(function() return HttpService:JSONDecode(d) end); if ok2 then return dec end end
    return nil
end
local function prefsSave(t)
    local e = env()
    local wr = type(writefile) == "function" and writefile or e.writefile
    if not wr then return end
    local ok, enc = pcall(function() return HttpService:JSONEncode(t) end)
    if ok then pcall(wr, PREFS, enc) end
end

getgenv().LAMBDA = getgenv().LAMBDA or {}
local C = getgenv().LAMBDA

local DEFAULTS = {
    Currency="Coin", Speed=35, FarmMode="Stealth", Depth=18, CoinRise=4,
    HopAt=6, HopFriend=false,
    AntiAFK=true, AntiVoid=true, AntiFling=true, Noclip=true, AntiMurderer=false,
    Disable3D=false, VoteMode=0, VoteMax=0,
    ResetInnocent=true, FlingMurderer=false, ShootSheriff=true, ResetAnyRole=false,
    KillMurderer=true, ResetMurderer=false, Threshold=0, ResetAfterAction=true,
    ReexecURL="",
    ESPOn=false, TracersOn=false, ChamsOn=false, OutlinesOn=false,
    ShowMurderer=true, ShowSheriff=true, ShowHero=true, ShowInnocent=true,
    CoinESP=false, GunESP=false,
    PrimaryColor="#FFC800", SecondaryColor="#1E1E1E",
}
for k,v in pairs(DEFAULTS) do if C[k]==nil then C[k]=v end end
local saved = prefsLoad()
if saved then for k,v in pairs(saved) do if C[k]~=nil then C[k]=v end end end

C.Farming=false; C.FarmStatus="idle"; C.FarmThread=nil
C.HopThread=nil; C.FriendThread=nil; C.VoteThread=nil; C.AntiMurdererThread=nil
C.LastFull=tick(); C.Cooldown=0; C.HopStatus=""
C.IsHopping=false; C.IsTeleporting=false
C.Stats={Total=0, Start=tick(), Last=0}
C.MissCount=0; C.WasInRound=false
C.CollectFails=0

local function save() local t={} for k,_ in pairs(DEFAULTS) do t[k]=C[k] end prefsSave(t) end

local function parseHex(s)
    s = tostring(s or ""):gsub("#","")
    if #s ~= 6 then return nil end
    local n = tonumber(s, 16); if not n then return nil end
    local r = bit32.rshift(bit32.band(n, 0xFF0000), 16)
    local g = bit32.rshift(bit32.band(n, 0x00FF00), 8)
    local b = bit32.band(n, 0x0000FF)
    return Color3.fromRGB(r, g, b)
end
local PRIMARY = parseHex(C.PrimaryColor) or Color3.fromRGB(255, 200, 0)
local SECONDARY = parseHex(C.SecondaryColor) or Color3.fromRGB(30, 30, 30)
local TEXT_DIM = Color3.fromRGB(150,150,150)
local TEXT_BRIGHT = Color3.fromRGB(220,220,220)

local function HRP() local c=LocalPlayer.Character; return c and c:FindFirstChild("HumanoidRootPart") end
local function HUM() local c=LocalPlayer.Character; return c and c:FindFirstChildOfClass("Humanoid") end

-- ============ Background GetPlayerData (single thread, all reads from cache) ============
local pdCache = { data=nil, ts=0 }
task.spawn(function()
    while true do
        task.wait(0.75)
        local ok, data = pcall(function()
            local r = ReplicatedStorage:FindFirstChild("GetPlayerData", true)
            if r and r:IsA("RemoteFunction") then return r:InvokeServer() end
        end)
        if ok and data then pdCache.data=data; pdCache.ts=tick() end
    end
end)
local function PD() return pdCache.data end

local function inRound()
    local d = PD()
    if not d then return true end
    local me = d[LocalPlayer.Name]
    if not me then return true end
    if me.Dead==true or me.Killed==true then return false end
    if me.Role=="None" then return false end
    return true
end

local function findMurderer()
    local d = PD(); if not d then return nil end
    for n, i in pairs(d) do
        if i.Role=="Murderer" and not i.Killed and not i.Dead then
            local p = Players:FindFirstChild(n)
            if p and p~=LocalPlayer then return p end
        end
    end
    return nil
end

local function cleanup()
    local h=HRP(); if h then pcall(function() h.Anchored=false; h.AssemblyLinearVelocity=Vector3.zero; h.AssemblyAngularVelocity=Vector3.zero end) end
    local u=HUM(); if u then u.PlatformStand=false; u.AutoRotate=true end
end
local function hardReset()
    local h=HRP(); if h then pcall(function() h.Anchored=false end) end
    local u=HUM(); if u then u.PlatformStand=false; u.AutoRotate=true; if u.Health>0 then u.Health=0 end end
end

-- ============ Bag from leaderstats (no yield) ============
local EVENT_CURR = { Candy=true, SnowToken=true, Token=true, Shell=true, Egg=true, Present=true, Gift=true, Gem=true }
local function threshold()
    if C.Threshold>0 then return C.Threshold end
    return EVENT_CURR[C.Currency] and 50 or 40
end
local PATTERNS = {"coin","cand","token","shell","egg","present","gift","gem","snow"}
local function statValue()
    local best
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    if ls then
        for _,ch in ipairs(ls:GetChildren()) do
            if ch:IsA("IntValue") or ch:IsA("NumberValue") then
                local n=ch.Name:lower()
                for _,p in ipairs(PATTERNS) do
                    if n:find(p) then
                        if not best or ch.Value>best then best=ch.Value end
                        break
                    end
                end
            end
        end
    end
    if best then return best end
    local d=PD()
    if d and d[LocalPlayer.Name] then
        for k,v in pairs(d[LocalPlayer.Name]) do
            if type(v)=="number" and v>=0 and v<=500 then
                local n=tostring(k):lower()
                for _,p in ipairs(PATTERNS) do
                    if n:find(p) then if not best or v>best then best=v end; break end
                end
            end
        end
    end
    return best
end

-- ============ Noclip / Anti-AFK / Anti-Void / Anti-Fling ============
local noclipConn
local function startNoclip()
    if noclipConn then noclipConn:Disconnect() end
    noclipConn = RunService.Stepped:Connect(function()
        if not C.Noclip then return end
        local ch=LocalPlayer.Character; if not ch then return end
        for _,p in ipairs(ch:GetDescendants()) do
            if p:IsA("BasePart") and p.CanCollide then p.CanCollide=false end
        end
    end)
end
local function stopNoclip() if noclipConn then noclipConn:Disconnect(); noclipConn=nil end end

local afkConn
local function startAFK()
    if afkConn then afkConn:Disconnect() end
    afkConn = LocalPlayer.Idled:Connect(function()
        pcall(function() VirtualUser:CaptureController(); VirtualUser:ClickButton2(Vector2.new(0,0)) end)
    end)
end

local voidConn
local origDH = Workspace.FallenPartsDestroyHeight
local function setupVoid()
    if not C.AntiVoid then Workspace.FallenPartsDestroyHeight=origDH; if voidConn then voidConn:Disconnect(); voidConn=nil end; return end
    Workspace.FallenPartsDestroyHeight=0/0
    if voidConn then voidConn:Disconnect() end
    voidConn = LocalPlayer.CharacterAdded:Connect(function() task.wait(0.1); Workspace.FallenPartsDestroyHeight=0/0 end)
end

local function startFling()
    local lastP, lastT = nil, tick()
    local lastC = nil
    RunService.Heartbeat:Connect(function()
        if not C.AntiFling then return end
        local ch=LocalPlayer.Character
        if not ch then lastC=nil; lastP=nil; return end
        if ch~=lastC then lastC=ch; lastP=nil; lastT=tick(); return end
        local h=ch:FindFirstChild("HumanoidRootPart")
        local u=ch:FindFirstChildOfClass("Humanoid")
        if not h or not u or u.Health<=0 or h.Anchored then lastP=nil; return end
        local now=tick()
        if lastP and now-lastT>0.1 then
            local d=(h.Position-lastP).Magnitude
            local s=d/(now-lastT)
            if s>150 and d<30 then
                h.AssemblyLinearVelocity=Vector3.zero
                h.AssemblyAngularVelocity=Vector3.zero
                h.CFrame=CFrame.new(lastP)*h.CFrame.Rotation
            end
        end
        lastP=h.Position; lastT=now
    end)
end

-- ============ Anti-Murderer (safer: down instead of horizontal) ============
local function startAntiMurderer()
    if C.AntiMurdererThread then task.cancel(C.AntiMurdererThread) end
    C.AntiMurdererThread = task.spawn(function()
        while true do
            task.wait(0.5)
            if C.AntiMurderer then
                local h=HRP()
                if h then
                    local m=findMurderer()
                    if m and m.Character then
                        local mh=m.Character:FindFirstChild("HumanoidRootPart")
                        if mh and (h.Position-mh.Position).Magnitude<25 then
                            local was=h.Anchored
                            if was then h.Anchored=false end
                            -- Desce 30 studs em vez de 200 horizontal (não sai do mapa)
                            h.CFrame=CFrame.new(h.Position-Vector3.new(0,30,0))*h.CFrame.Rotation
                            if was then h.Anchored=true end
                        end
                    end
                end
            end
        end
    end)
end

-- ============ Coin cache ============
local coinCache = { parts={}, ts=0 }
local function getContainers()
    local list = {}
    for _,o in ipairs(Workspace:GetChildren()) do
        for _,n in ipairs({"CoinContainer","CandyContainer","TokenContainer","Collectables"}) do
            local c=o:FindFirstChild(n); if c then table.insert(list,c) end
        end
        local m=o:FindFirstChild("Map")
        if m then
            for _,n in ipairs({"CoinContainer","CandyContainer","TokenContainer","Collectables"}) do
                local c=m:FindFirstChild(n); if c then table.insert(list,c) end
            end
        end
    end
    return list
end
local function getCoins()
    if tick()-coinCache.ts < 0.4 then
        local alive={}
        for _,p in ipairs(coinCache.parts) do if p.Parent then table.insert(alive,p) end end
        coinCache.parts=alive
        return alive
    end
    local parts={}
    for _,c in ipairs(getContainers()) do
        for _,d in ipairs(c:GetDescendants()) do
            if d:IsA("BasePart") and d:FindFirstChildWhichIsA("TouchTransmitter") then
                table.insert(parts,d)
            end
        end
    end
    coinCache.parts=parts; coinCache.ts=tick()
    return parts
end
local function nearestCoin()
    local h=HRP(); if not h then return nil end
    local best, bd = nil, math.huge
    for _,p in ipairs(getCoins()) do
        local d=(h.Position-p.Position).Magnitude
        if d<bd then bd=d; best=p end
    end
    return best
end

local function touch(coin)
    local h=HRP(); local ch=LocalPlayer.Character
    if not h or not coin or not ch then return false end
    local was=h.Anchored
    if was then h.Anchored=false; h.AssemblyLinearVelocity=Vector3.zero end
    task.wait(0.02)
    pcall(function()
        if typeof(firetouchinterest)~="function" then return end
        local torso=ch:FindFirstChild("UpperTorso") or ch:FindFirstChild("Torso")
        if torso then firetouchinterest(torso,coin,0); task.wait(0.015); firetouchinterest(torso,coin,1) end
        firetouchinterest(h,coin,0); task.wait(0.015); firetouchinterest(h,coin,1)
    end)
    task.wait(0.02)
    if was and h.Parent then h.Anchored=true; h.AssemblyLinearVelocity=Vector3.zero end
    return true
end

-- ============ Movement ============
local LAY = CFrame.Angles(math.rad(90),0,0)
local function travel(targetPos, rot90, spd, coinRef)
    local h=HRP(); if not h then return false end
    if not h.Anchored then h.Anchored=true end
    local u=HUM()
    if u and not u.PlatformStand then u.PlatformStand=true; u.AutoRotate=false end
    spd = math.clamp(spd or C.Speed, 10, 70)
    local rot = rot90 and LAY or h.CFrame.Rotation
    local lastT = tick()
    local startT = tick()
    local lastDist = math.huge
    local lastProgress = tick()

    while C.Farming do
        if tick()-startT>15 then return false end
        if not inRound() then return false end
        local cur=HRP()
        if not cur or not cur.Anchored then return false end
        if coinRef and not coinRef.Parent then return false end
        local cu=HUM()
        if not cu or cu.Health<=0 then return false end
        if cur.Position.Y<-150 or cur.Position.Y>10000 then return false end

        local delta = targetPos - cur.Position
        local dist = delta.Magnitude
        if dist<2.5 then cur.CFrame=CFrame.new(targetPos)*rot; return true end

        if dist < lastDist-1 then lastProgress=tick(); lastDist=dist
        elseif tick()-lastProgress>3 then return false end

        local now=tick()
        local dt=math.min(now-lastT,0.05)
        lastT=now
        local step=math.min(spd*dt, dist)
        cur.CFrame=CFrame.new(cur.Position+delta.Unit*step)*rot
        task.wait()
    end
    return false
end

local function beginMove()
    local h=HRP(); local u=HUM()
    if u then u.PlatformStand=true; u.AutoRotate=false end
    if h then h.Anchored=true; h.AssemblyLinearVelocity=Vector3.zero; h.AssemblyAngularVelocity=Vector3.zero end
end

-- ============ Role ============
local function role()
    local d=PD()
    if d and d[LocalPlayer.Name] then
        local r=d[LocalPlayer.Name].Role
        if r and r~="None" then return r end
    end
    for _,cont in ipairs({LocalPlayer.Character, LocalPlayer:FindFirstChild("Backpack")}) do
        if cont then
            for _,it in ipairs(cont:GetChildren()) do
                if it:IsA("Tool") then
                    local n=it.Name:lower()
                    if n:find("knife") then return "Murderer" end
                    if n:find("gun") then return "Sheriff" end
                end
            end
        end
    end
    return "Innocent"
end

local function equip(n)
    local ch=LocalPlayer.Character; if not ch then return nil end
    local t=ch:FindFirstChild(n)
    if not t then
        local bp=LocalPlayer:FindFirstChild("Backpack")
        t=bp and bp:FindFirstChild(n)
        if t then t.Parent=ch; task.wait(0.2) end
    end
    return t
end
local function killAll()
    local k=equip("Knife"); if not k then return end
    local ev=k:FindFirstChild("Events")
    local ht=ev and ev:FindFirstChild("HandleTouched")
    if not ht then return end
    for _,p in ipairs(Players:GetPlayers()) do
        if p~=LocalPlayer and p.Character then
            local up=p.Character:FindFirstChild("UpperTorso") or p.Character:FindFirstChild("Torso")
            if up then pcall(function() ht:FireServer(up) end); task.wait(0.05) end
        end
    end
end
local function shoot()
    local g=equip("Gun"); if not g then return end
    local m=findMurderer()
    if not m or not m.Character then return end
    local mh=m.Character:FindFirstChild("HumanoidRootPart")
    local h=HRP()
    if not mh or not h then return end
    h.CFrame=CFrame.new(h.Position, mh.Position)
    task.wait(0.1)
    pcall(function() g:Activate() end)
    task.wait(0.05)
    pcall(function()
        VirtualInputManager:SendMouseButtonEvent(0,0,0,true,game,0)
        task.wait(0.05)
        VirtualInputManager:SendMouseButtonEvent(0,0,0,false,game,0)
    end)
    local ev=g:FindFirstChild("Events")
    if ev then for _,r in ipairs(ev:GetChildren()) do if r:IsA("RemoteEvent") then pcall(function() r:FireServer(mh) end) end end end
end
local function fling()
    local m=findMurderer()
    if not m or not m.Character then return end
    local mh=m.Character:FindFirstChild("HumanoidRootPart"); if not mh then return end
    pcall(function() mh:SetNetworkOwner(LocalPlayer) end)
    local bv=Instance.new("BodyVelocity")
    bv.Velocity=Vector3.new(0,800,0); bv.MaxForce=Vector3.new(math.huge,math.huge,math.huge); bv.P=100000; bv.Parent=mh
    local bg=Instance.new("BodyGyro")
    bg.MaxTorque=Vector3.new(math.huge,math.huge,math.huge); bg.P=100000; bg.CFrame=CFrame.new(0,math.huge,0); bg.Parent=mh
    Debris:AddItem(bv,0.6); Debris:AddItem(bg,0.6)
end

local function fullBag()
    local r=role()
    local did=false
    if r=="Innocent" then
        if C.FlingMurderer then fling(); did=true end
        if C.ResetInnocent and not did then hardReset(); return end
    elseif r=="Sheriff" then
        if C.ShootSheriff then shoot(); did=true end
    elseif r=="Murderer" then
        if C.KillMurderer then killAll(); did=true end
        if C.ResetMurderer and not did then hardReset(); return end
    end
    if did and C.ResetAfterAction then task.wait(1.2); hardReset(); return end
    if C.ResetAnyRole then hardReset() end
end

local function statsTick()
    task.spawn(function()
        LocalPlayer:WaitForChild("leaderstats", 10)
        task.wait(1)
        C.Stats.Last = statValue() or 0
        while true do
            task.wait(0.5)
            local v=statValue()
            if v and C.Stats.Last and v>C.Stats.Last then C.Stats.Total = C.Stats.Total + (v-C.Stats.Last) end
            if v then C.Stats.Last = v end
        end
    end)
end
local function rate()
    local e=math.max(1,tick()-C.Stats.Start)
    return math.floor((C.Stats.Total/e)*3600)
end

-- ============ Round watcher (debounced) ============
task.spawn(function()
    local lastC=nil
    while true do
        task.wait(0.15)
        local ch=LocalPlayer.Character
        if ch~=lastC then lastC=ch; C.MissCount=0; C.WasInRound=false end
        local h=ch and ch:FindFirstChild("HumanoidRootPart")
        if C.Farming and h then
            if h.Position.Y<-150 then
                C.FarmStatus="fell"
                hardReset(); C.Cooldown=tick()+3; C.MissCount=0; C.WasInRound=false
                continue
            end
            local ir=inRound()
            if ir then C.WasInRound=true; C.MissCount=0
            elseif C.WasInRound then
                C.MissCount=C.MissCount+1
                if C.MissCount>=3 then
                    C.FarmStatus="round end"
                    hardReset(); C.Cooldown=tick()+3; C.MissCount=0; C.WasInRound=false
                end
            end
        else C.MissCount=0; C.WasInRound=false end
    end
end)

-- ============ Farm loop with stealth depth ============
local function farm()
    if C.Farming then return end
    C.Farming=true; C.FarmStatus="starting"
    C.FarmThread=task.spawn(function()
        while C.Farming do
            if tick()<C.Cooldown then C.FarmStatus="cooldown"; cleanup(); task.wait(0.2); continue end
            local u=HUM(); local h=HRP()
            if not u or u.Health<=0 or not h then C.FarmStatus="no char"; task.wait(0.3); continue end
            if not inRound() then C.FarmStatus="lobby"; cleanup(); task.wait(0.3); continue end

            local coin=nearestCoin()
            if coin then
                -- Stealth: abaixo da superfície, sobe para moeda, coleta, desce
                local depth = C.FarmMode=="Stealth" and C.Depth or 0
                local rot90 = C.FarmMode=="Lay"

                if depth>0 then
                    -- Fase 1: viaja para baixo da moeda
                    local below = coin.Position - Vector3.new(0, depth, 0)
                    if not h.Anchored then beginMove(); task.wait(0.03) end
                    C.FarmStatus="travel-below"
                    if travel(below, rot90, C.Speed, coin) then
                        -- Fase 2: sobe para pegar
                        C.FarmStatus="rise"
                        local above = coin.Position + Vector3.new(0, C.CoinRise, 0)
                        travel(above, rot90, C.Speed*1.6, coin)
                        if coin.Parent then
                            C.FarmStatus="collect"
                            touch(coin)
                            local t=tick()
                            while coin.Parent and tick()-t<0.25 do task.wait(0.02) end
                            if coin.Parent then C.CollectFails=C.CollectFails+1 else C.CollectFails=0 end
                        end
                        -- Fase 3: desce de volta
                        C.FarmStatus="descend"
                        travel(coin.Position - Vector3.new(0, depth, 0), rot90, C.Speed*1.6, nil)
                    end
                else
                    if not h.Anchored then beginMove(); task.wait(0.03) end
                    C.FarmStatus="travel"
                    if travel(coin.Position, rot90, C.Speed, coin) and coin.Parent then
                        C.FarmStatus="collect"
                        touch(coin)
                        local t=tick()
                        while coin.Parent and tick()-t<0.25 do task.wait(0.02) end
                        if coin.Parent then C.CollectFails=C.CollectFails+1 else C.CollectFails=0 end
                    end
                end
                task.wait(0.03)
            else
                C.FarmStatus="no coins"
                cleanup()
                task.wait(0.3)
            end

            local st=statValue()
            if st and st>=threshold() and tick()-C.LastFull>3 then
                C.LastFull=tick(); C.FarmStatus="full bag"; fullBag()
            end
        end
        C.FarmStatus="idle"
    end)
end
local function stopFarm()
    C.Farming=false; C.FarmStatus="idle"
    if C.FarmThread then task.cancel(C.FarmThread); C.FarmThread=nil end
    cleanup()
end

-- ============ Source + URL reexec ============
local function captureSrc()
    if getgenv().LAMBDA_SOURCE then return end
    local e=env()
    local rd=type(readfile)=="function" and readfile or e.readfile
    local wr=type(writefile)=="function" and writefile or e.writefile
    if rd then
        local ok,d=pcall(rd,SRC)
        if ok and d and #d>1000 then getgenv().LAMBDA_SOURCE=d; return end
    end
    local ok,info=pcall(function() return debug.getinfo(1,"S") end)
    if ok and info and info.source then
        local s=info.source
        if s:sub(1,1)=="@" and rd then
            local o,c=pcall(rd,s:sub(2)); if o and c then getgenv().LAMBDA_SOURCE=c; if wr then pcall(wr,SRC,c) end; return end
        elseif s:sub(1,1)=="=" then
            local m=s:match('^=%[string "(.*)"%]$')
            if m and #m>100 then
                m=m:gsub('\\n','\n'):gsub('\\t','\t'):gsub('\\"','"'):gsub("\\'","'"):gsub('\\\\','\\')
                getgenv().LAMBDA_SOURCE=m; if wr then pcall(wr,SRC,m) end
                return
            end
        end
    end
end

local function getPayload()
    if C.ReexecURL and C.ReexecURL~="" then
        return 'pcall(function() loadstring(game:HttpGet("'..C.ReexecURL..'"))() end)', "url"
    end
    captureSrc()
    local src=getgenv().LAMBDA_SOURCE
    if not src then return nil, "none" end
    local e=env()
    local wr=type(writefile)=="function" and writefile or e.writefile
    if wr then pcall(wr,SRC,src) end
    return "pcall(function() local s=readfile('"..SRC.."'); if s and #s>100 then loadstring(s)() end end)", "file"
end
local function queueReexec()
    local p,k=getPayload()
    if not p then warn("[Lambda] Reexec: sem URL e sem source"); return false end
    if syn and type(syn.queue_on_teleport)=="function" then
        if pcall(syn.queue_on_teleport,p) then print("[Lambda] Reexec: syn ("..k..")"); return true end
    end
    if type(queue_on_teleport)=="function" then
        if pcall(queue_on_teleport,p) then print("[Lambda] Reexec: queue_on_teleport ("..k..")"); return true end
    end
    local g=getgenv()
    if g and type(g.queue_on_teleport)=="function" then
        if pcall(g.queue_on_teleport,p) then print("[Lambda] Reexec: getgenv ("..k..")"); return true end
    end
    if type(queueonteleport)=="function" then
        if pcall(queueonteleport,p) then print("[Lambda] Reexec: queueonteleport ("..k..")"); return true end
    end
    warn("[Lambda] Reexec: nenhum método disponível")
    return false
end

-- ============ Kick hook with teleport guard ============
pcall(function()
    if not (getrawmetatable and setreadonly and newcclosure) then return end
    local mt=getrawmetatable(game)
    local old=mt.__namecall
    setreadonly(mt,false)
    mt.__namecall=newcclosure(function(self,...)
        local method=getnamecallmethod()
        if method=="Kick" and self==LocalPlayer and not C.IsTeleporting then
            print("[Lambda] Kick interceptado")
            C.IsTeleporting=true
            queueReexec()
            task.spawn(function()
                task.wait(0.1)
                pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
            end)
            return nil
        end
        return old(self,...)
    end)
    setreadonly(mt,true)
    print("[Lambda] Kick hook on")
end)

-- ============ Server hop (single connection, guarded) ============
local function httpGet(u)
    local m={
        function() return game:HttpGet(u) end,
        function() if syn and syn.request then return syn.request({Url=u,Method="GET"}).Body end end,
        function() if request then return request({Url=u,Method="GET"}).Body end end,
        function() if http_request then return http_request({Url=u,Method="GET"}).Body end end,
    }
    for _,f in ipairs(m) do local ok,r=pcall(f); if ok and type(r)=="string" and #r>0 then return r end end
    return nil
end
local function pool()
    local raw=httpGet(string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100", game.PlaceId))
    if not raw then return {} end
    local ok,res=pcall(function() return HttpService:JSONDecode(raw) end)
    if not ok or not res or not res.data then return {} end
    local t={}
    for _,s in ipairs(res.data) do
        if s.id~=game.JobId and s.playing>=1 and s.playing<=3 and s.playing<s.maxPlayers then table.insert(t,s) end
    end
    for i=#t,2,-1 do local j=math.random(1,i); t[i],t[j]=t[j],t[i] end
    return t
end

local hopInitFailedConn
local function hop()
    if C.IsHopping then return false end
    C.IsHopping=true
    C.HopStatus="queue"
    queueReexec()

    C.HopStatus="fetch"
    local list=pool()
    if #list==0 then C.HopStatus="no servers"; C.IsHopping=false; return false end

    if not hopInitFailedConn then
        hopInitFailedConn = TeleportService.TeleportInitFailed:Connect(function() end)
    end

    C.IsTeleporting=true
    for i,s in ipairs(list) do
        C.HopStatus="try "..i.."/"..#list
        local ok,res=pcall(function()
            local o=Instance.new("TeleportOptions")
            o.ServerInstanceId=s.id
            return TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id, LocalPlayer, o)
        end)
        if ok and not (typeof(res)=="EnumItem" and res==Enum.TeleportState.Failed) then
            C.HopStatus="OK"
            task.wait(5)
            C.IsTeleporting=false; C.IsHopping=false
            return true
        end
        task.wait(0.4)
    end
    C.HopStatus="fallback"
    local ok=pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
    task.wait(4)
    C.IsTeleporting=false; C.IsHopping=false
    C.HopStatus = ok and "fallback OK" or "FAILED"
    return ok
end

local function hopMonitor()
    if C.HopThread then return end
    C.HopThread=task.spawn(function()
        while C.HopAt>0 do
            task.wait(5)
            if not C.IsHopping and #Players:GetPlayers()>C.HopAt then hop(); break end
        end
    end)
end

local function friendMonitor()
    if C.FriendThread then return end
    C.FriendThread=task.spawn(function()
        local ids={}
        pcall(function()
            local raw=httpGet("https://friends.roblox.com/v1/users/"..LocalPlayer.UserId.."/friends")
            if raw then local r=HttpService:JSONDecode(raw); if r and r.data then for _,f in ipairs(r.data) do ids[f.id]=true end end end
        end)
        while C.HopFriend do
            task.wait(10)
            for _,p in ipairs(Players:GetPlayers()) do if p~=LocalPlayer and ids[p.UserId] then hop(); break end end
        end
    end)
end

-- ============ Auto-Vote ============
local VOTE_PADS={"VotePad1","VotePad2","VotePad3"}
local MAPS={"Manor","House 2","Office 3","Hospital 3","Bank 2","Vampire's Castle","Mansion 2","WorkPlace","Hotel 2","Farm House","Police Station","Factory","Bio Lab","Research Facility","Mil Base"}
local function norm(s) s=string.lower(s):gsub("-"," "):gsub("%s+"," "); return s:match("^%s*(.-)%s*$") end
local rankCache={}
local function rank(r)
    if rankCache[r] then return rankCache[r] end
    local l=norm(r); local v=#MAPS+1
    for i,n in ipairs(MAPS) do if l==norm(n) then v=i; break end end
    rankCache[r]=v; return v
end
local function pads()
    local o={}
    local l=Workspace:FindFirstChild("Lobby")
    local f=l and l:FindFirstChild("VotePads")
    if not f then return o end
    for _,n in ipairs(VOTE_PADS) do
        local p=f:FindFirstChild(n)
        local t=p and p:FindFirstChild("Pad")
        local g=p and p:FindFirstChild("VoteInfoGui")
        local c=g and g:FindFirstChild("Container")
        local l2=c and c:FindFirstChild("MapName")
        if t and l2 and g.Enabled then table.insert(o,{trigger=t, map=l2.Text}) end
    end
    return o
end
local function pickPad(o)
    if #o==0 then return nil end
    if C.VoteMode==3 then return o[math.random(1,#o)] end
    local b,bs
    for _,p in ipairs(o) do
        local r=rank(p.map); local s=(C.VoteMode==1) and -r or r
        if not bs or s>bs then b,bs=p,s end
    end
    return b
end
local function inside(t,pos)
    local lp=t.CFrame:PointToObjectSpace(pos)
    local h=t.Size*0.5
    return math.abs(lp.X)<=h.X and math.abs(lp.Y)<=h.Y and math.abs(lp.Z)<=h.Z
end
local function vote(p)
    local h=HRP(); local u=HUM()
    if not h or not u or u.Health<=0 then return false end
    h.Anchored=false; h.AssemblyLinearVelocity=Vector3.zero; h.AssemblyAngularVelocity=Vector3.zero
    u.PlatformStand=false; u.AutoRotate=true
    local pp=p.trigger.Position
    h.CFrame=CFrame.new(pp+Vector3.new(0,4,0))
    local st=tick(); local landed=false
    while tick()-st<2 do
        task.wait(0.05)
        local ch=HRP(); if not ch then return false end
        if inside(p.trigger, ch.Position) then landed=true; break end
        if tick()-st>1 then ch.CFrame=CFrame.new(pp+Vector3.new(0,1,0)) end
    end
    if not landed then return false end
    if typeof(firetouchinterest)=="function" then
        pcall(function() firetouchinterest(h,p.trigger,0); task.wait(0.05); firetouchinterest(h,p.trigger,1) end)
    end
    task.wait(0.3)
    if typeof(firetouchinterest)=="function" then
        pcall(function() firetouchinterest(h,p.trigger,0); task.wait(0.05); firetouchinterest(h,p.trigger,1) end)
    end
    task.wait(0.2)
    if u.Health>0 then u:ChangeState(Enum.HumanoidStateType.Dead); u.Health=0 end
    return true
end
local function startVote()
    if C.VoteThread then task.cancel(C.VoteThread) end
    C.VoteThread=task.spawn(function()
        local v=0
        while C.VoteMode~=0 do
            local o=pads()
            if #o==0 then task.wait(0.4)
            elseif C.VoteMax>0 and v>=C.VoteMax then task.wait(0.5)
            else
                local p=pickPad(o)
                if p and vote(p) then v=v+1 end
                task.wait(0.5)
            end
        end
    end)
end
local function stopVote() C.VoteMode=0; if C.VoteThread then task.cancel(C.VoteThread); C.VoteThread=nil end end

-- ============ ESP (full rewrite) ============
local ROLE_COLORS = {
    Murderer=Color3.fromRGB(255,40,40),
    Sheriff=Color3.fromRGB(40,140,255),
    Hero=Color3.fromRGB(255,200,50),
    Innocent=Color3.fromRGB(60,255,80),
    Unknown=Color3.fromRGB(200,200,200),
}
local COIN_COL=Color3.fromRGB(255,215,0)
local GUN_COL=Color3.fromRGB(255,100,255)
local hasDrawing = (function()
    local ok,d=pcall(function() return Drawing.new("Square") end)
    if ok and d then pcall(function() d:Remove() end); return true end
    return false
end)

local ESP = { draws={}, smooth={}, highlights={}, coinSels={}, gunSels={} }
local roleCache = { data=nil, ts=0 }
local function roleFor(p)
    local d=PD()
    if d and d[p.Name] and d[p.Name].Role and d[p.Name].Role~="None" then return d[p.Name].Role end
    return "Innocent"
end
local function roleShown(r)
    if r=="Murderer" then return C.ShowMurderer end
    if r=="Sheriff" then return C.ShowSheriff end
    if r=="Hero" then return C.ShowHero end
    if r=="Innocent" then return C.ShowInnocent end
    return false
end
local function getDraw(p)
    if ESP.draws[p] then return ESP.draws[p] end
    if not hasDrawing then return nil end
    local t={}
    pcall(function() t.box=Drawing.new("Square"); t.box.Thickness=1; t.box.Filled=false; t.box.Visible=false end)
    pcall(function() t.name=Drawing.new("Text"); t.name.Center=true; t.name.Outline=true; t.name.Size=13; t.name.Font=2; t.name.Visible=false end)
    pcall(function() t.tracer=Drawing.new("Line"); t.tracer.Thickness=1; t.tracer.Visible=false end)
    ESP.draws[p]=t
    return t
end
local function hideAll(t) for _,d in pairs(t) do pcall(function() d.Visible=false end) end end

local function updateESP()
    if not hasDrawing then return end
    if not (C.ESPOn or C.TracersOn) then
        for _,t in pairs(ESP.draws) do hideAll(t) end
        return
    end
    local cam=workspace.CurrentCamera; if not cam then return end

    -- Tracer origin: local character HRP
    local lh=HRP()
    local lu=HUM()
    local origin
    if lh and lu and lu.Health>0 then
        local sp,on=cam:WorldToViewportPoint(lh.Position)
        if on then origin=Vector2.new(sp.X, sp.Y) end
    end
    if not origin then
        local vs=cam.ViewportSize
        origin=Vector2.new(vs.X/2, vs.Y)
    end

    for _,p in ipairs(Players:GetPlayers()) do
        if p==LocalPlayer then continue end
        local t=ESP.draws[p] or getDraw(p)
        if not t then continue end
        local ch=p.Character
        local hp=ch and ch:FindFirstChild("HumanoidRootPart")
        local hu=ch and ch:FindFirstChildOfClass("Humanoid")
        if not hp or not hu or hu.Health<=0 then hideAll(t) continue end
        local r=roleFor(p)
        if not roleShown(r) then hideAll(t) continue end
        local col=ROLE_COLORS[r] or ROLE_COLORS.Unknown

        -- Use HRP only — stable, no head bobbing
        local top,on1 = cam:WorldToViewportPoint(hp.Position + Vector3.new(0, 2.6, 0))
        local bot,on2 = cam:WorldToViewportPoint(hp.Position - Vector3.new(0, 2.8, 0))
        if not (on1 and on2) then hideAll(t) continue end
        if math.abs(top.Y-bot.Y)<2 then hideAll(t) continue end

        -- Target for lerp
        local h = math.abs(top.Y-bot.Y)
        local w = h/1.8
        local targetPos = Vector2.new(top.X - w/2, top.Y)
        local targetSize = Vector2.new(w, h)
        local targetTracerTo = Vector2.new(top.X, top.Y)
        local s = ESP.smooth[p]
        if not s then
            s={pos=targetPos, size=targetSize, tracerTo=targetTracerTo}
            ESP.smooth[p]=s
        end
        s.pos = s.pos:Lerp(targetPos, 0.4)
        s.size = s.size:Lerp(targetSize, 0.4)
        s.tracerTo = s.tracerTo:Lerp(targetTracerTo, 0.5)

        if C.ESPOn then
            if t.box then
                t.box.Position=s.pos
                t.box.Size=s.size
                t.box.Color=col
                t.box.Visible=true
            end
            if t.name then
                t.name.Text=p.Name.." ["..r.."]"
                t.name.Position=Vector2.new(top.X, s.pos.Y-18)
                t.name.Color=col
                t.name.Visible=true
            end
        else
            if t.box then t.box.Visible=false end
            if t.name then t.name.Visible=false end
        end
        if C.TracersOn and t.tracer then
            t.tracer.From=origin
            t.tracer.To=s.tracerTo
            t.tracer.Color=col
            t.tracer.Visible=true
        elseif t.tracer then
            t.tracer.Visible=false
        end
    end
end

RunService.RenderStepped:Connect(function()
    if not (C.ESPOn or C.TracersOn) then return end
    pcall(updateESP)
end)

-- Highlights + coin/gun SelectionBoxes (heartbeat 5 Hz)
local hlConn
local hlAccum=0
hlConn = RunService.Heartbeat:Connect(function(dt)
    if not (C.ChamsOn or C.OutlinesOn or C.CoinESP or C.GunESP) then return end
    hlAccum += dt
    if hlAccum<0.2 then return end
    hlAccum=0

    -- Player highlights
    if C.ChamsOn or C.OutlinesOn then
        for _,p in ipairs(Players:GetPlayers()) do
            if p==LocalPlayer then continue end
            local ch=p.Character
            local hl=ESP.highlights[p]
            if not ch then
                if hl then pcall(function() hl:Destroy() end); ESP.highlights[p]=nil end
                continue
            end
            local r=roleFor(p)
            if not roleShown(r) then
                if hl then pcall(function() hl:Destroy() end); ESP.highlights[p]=nil end
                continue
            end
            if not hl or hl.Parent~=ch then
                if hl then pcall(function() hl:Destroy() end) end
                hl=Instance.new("Highlight")
                hl.Name="LAMBDA_HL"
                hl.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop
                hl.Parent=ch
                ESP.highlights[p]=hl
            end
            local col=ROLE_COLORS[r] or ROLE_COLORS.Unknown
            hl.FillColor=col; hl.OutlineColor=col
            hl.FillTransparency=C.ChamsOn and 0.5 or 1
            hl.OutlineTransparency=C.OutlinesOn and 0 or 1
        end
    else
        for _,hl in pairs(ESP.highlights) do pcall(function() hl:Destroy() end) end
        ESP.highlights={}
    end

    -- Coin ESP via SelectionBox
    if C.CoinESP then
        local seen={}
        for _,coin in ipairs(getCoins()) do
            seen[coin]=true
            local sb=ESP.coinSels[coin]
            if not sb or sb.Parent~=coin then
                if sb then pcall(function() sb:Destroy() end) end
                local s=Instance.new("SelectionBox")
                s.Adornee=coin
                s.Color3=COIN_COL
                s.LineThickness=0.06
                s.SurfaceTransparency=1
                s.Parent=coin
                ESP.coinSels[coin]=s
            end
        end
        for part,sb in pairs(ESP.coinSels) do
            if not seen[part] or not part.Parent then pcall(function() sb:Destroy() end); ESP.coinSels[part]=nil end
        end
    else
        for _,sb in pairs(ESP.coinSels) do pcall(function() sb:Destroy() end) end
        ESP.coinSels={}
    end

    -- Gun ESP via SelectionBox on Handle
    if C.GunESP then
        local seen={}
        for _,o in ipairs(Workspace:GetChildren()) do
            local isGun = o:IsA("Tool") and (o.Name=="Gun" or o.Name=="Revolver")
            if not isGun and o:IsA("Model") and (o.Name=="Gun" or o.Name=="Revolver") then isGun=true end
            if isGun and not Players:GetPlayerFromCharacter(o.Parent) then
                local handle = o:FindFirstChild("Handle") or (o:IsA("Model") and o.PrimaryPart) or o:FindFirstChildWhichIsA("BasePart")
                if handle then
                    seen[handle]=true
                    local sb=ESP.gunSels[handle]
                    if not sb or sb.Parent~=handle then
                        if sb then pcall(function() sb:Destroy() end) end
                        local s=Instance.new("SelectionBox")
                        s.Adornee=handle
                        s.Color3=GUN_COL
                        s.LineThickness=0.08
                        s.SurfaceTransparency=1
                        s.Parent=handle
                        ESP.gunSels[handle]=s
                    end
                end
            end
        end
        for part,sb in pairs(ESP.gunSels) do
            if not seen[part] or not part.Parent then pcall(function() sb:Destroy() end); ESP.gunSels[part]=nil end
        end
    else
        for _,sb in pairs(ESP.gunSels) do pcall(function() sb:Destroy() end) end
        ESP.gunSels={}
    end
end)

Players.PlayerRemoving:Connect(function(p)
    if ESP.draws[p] then for _,d in pairs(ESP.draws[p]) do pcall(function() d:Remove() end) end; ESP.draws[p]=nil end
    if ESP.smooth[p] then ESP.smooth[p]=nil end
    if ESP.highlights[p] then pcall(function() ESP.highlights[p]:Destroy() end); ESP.highlights[p]=nil end
end)

-- ============ GUI ============
local function guiParent()
    do local ok,r=pcall(function() return gethui() end); if ok and r then return r end end
    do local ok,r=pcall(function() return game:GetService("CoreGui") end); if ok and r then return r end end
    do local ok,r=pcall(function() return LocalPlayer:WaitForChild("PlayerGui",5) end); if ok and r then return r end end
    return nil
end
local function findIdx(t,v) for i,x in ipairs(t) do if x==v then return i end end; return 1 end

local MAIN_GUI

local function buildGui()
    if MAIN_GUI then pcall(function() MAIN_GUI:Destroy() end) end
    local parent=guiParent()
    if not parent then warn("[Lambda] Sem parent GUI"); return end
    local gui=Instance.new("ScreenGui")
    gui.Name="LambdaHub"; gui.ResetOnSpawn=false; gui.IgnoreGuiInset=true; gui.DisplayOrder=999999
    pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)
    gui.Parent=parent
    MAIN_GUI=gui

    local main=Instance.new("Frame")
    main.Size=UDim2.new(0,380,0,510); main.Position=UDim2.new(0,30,0,30)
    main.BackgroundColor3=SECONDARY; main.BorderSizePixel=0; main.Active=true; main.Draggable=true
    main.Parent=gui

    local titleBar=Instance.new("Frame")
    titleBar.Size=UDim2.new(1,0,0,28); titleBar.BackgroundColor3=SECONDARY
    titleBar.BorderSizePixel=0; titleBar.Parent=main

    local title=Instance.new("TextLabel")
    title.Size=UDim2.new(1,-80,1,0); title.Position=UDim2.new(0,10,0,0)
    title.BackgroundTransparency=1; title.Text="Lambda Hub | v0.21"
    title.TextColor3=PRIMARY; title.Font=Enum.Font.GothamBold; title.TextSize=13
    title.TextXAlignment=Enum.TextXAlignment.Left; title.Parent=titleBar

    local min=Instance.new("TextButton")
    min.Size=UDim2.new(0,24,0,20); min.Position=UDim2.new(1,-56,0,4)
    min.BackgroundColor3=Color3.fromRGB(70,70,70); min.Text="—"
    min.TextColor3=Color3.fromRGB(255,255,255); min.Font=Enum.Font.GothamBold; min.TextSize=13
    min.Parent=titleBar
    local close=Instance.new("TextButton")
    close.Size=UDim2.new(0,24,0,20); close.Position=UDim2.new(1,-28,0,4)
    close.BackgroundColor3=Color3.fromRGB(120,30,30); close.Text="X"
    close.TextColor3=Color3.fromRGB(255,255,255); close.Font=Enum.Font.GothamBold; close.TextSize=13
    close.Parent=titleBar

    local collapsed=false
    min.MouseButton1Click:Connect(function()
        collapsed=not collapsed
        main.Size=collapsed and UDim2.new(0,380,0,28) or UDim2.new(0,380,0,510)
        min.Text=collapsed and "+" or "—"
    end)
    close.MouseButton1Click:Connect(function()
        for _,hl in pairs(ESP.highlights) do pcall(function() hl:Destroy() end) end
        for _,sb in pairs(ESP.coinSels) do pcall(function() sb:Destroy() end) end
        for _,sb in pairs(ESP.gunSels) do pcall(function() sb:Destroy() end) end
        for _,t in pairs(ESP.draws) do for _,d in pairs(t) do pcall(function() d:Remove() end) end end
        save(); gui:Destroy(); MAIN_GUI=nil
    end)

    local tabBar=Instance.new("Frame")
    tabBar.Size=UDim2.new(1,0,0,26); tabBar.Position=UDim2.new(0,0,0,28)
    tabBar.BackgroundColor3=SECONDARY; tabBar.BorderSizePixel=0; tabBar.Parent=main
    local tabLay=Instance.new("UIListLayout")
    tabLay.FillDirection=Enum.FillDirection.Horizontal; tabLay.Padding=UDim.new(0,0); tabLay.Parent=tabBar

    local content=Instance.new("Frame")
    content.Size=UDim2.new(1,0,1,-54); content.Position=UDim2.new(0,0,0,54)
    content.BackgroundTransparency=1; content.Parent=main

    local tabs={}
    local function newTab(name, wPct)
        local b=Instance.new("TextButton")
        b.Size=UDim2.new(wPct,0,1,0); b.BackgroundColor3=SECONDARY
        b.Text=name; b.TextColor3=TEXT_DIM; b.Font=Enum.Font.GothamBold; b.TextSize=11
        b.Parent=tabBar
        local f=Instance.new("ScrollingFrame")
        f.Size=UDim2.new(1,0,1,0); f.BackgroundTransparency=1
        f.ScrollBarThickness=4; f.CanvasSize=UDim2.new(0,0,0,0); f.Visible=false; f.Parent=content
        local l=Instance.new("UIListLayout")
        l.Padding=UDim.new(0,4); l.SortOrder=Enum.SortOrder.LayoutOrder; l.Parent=f
        local p=Instance.new("UIPadding")
        p.PaddingTop=UDim.new(0,8); p.PaddingLeft=UDim.new(0,8); p.PaddingRight=UDim.new(0,8); p.Parent=f
        tabs[name]={btn=b, frame=f, list=l}
        l:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            f.CanvasSize=UDim2.new(0,0,0,l.AbsoluteContentSize.Y+16)
        end)
        b.MouseButton1Click:Connect(function()
            for _,t in pairs(tabs) do
                t.frame.Visible=false; t.btn.BackgroundColor3=SECONDARY; t.btn.TextColor3=TEXT_DIM
            end
            f.Visible=true; b.BackgroundColor3=PRIMARY; b.TextColor3=Color3.fromRGB(0,0,0)
        end)
        return f
    end

    local mainTab=newTab("Main",1/7)
    local actionsTab=newTab("Actions",1/7)
    local protectTab=newTab("Protect",1/7)
    local espTab=newTab("ESP",1/7)
    local serverTab=newTab("Server",1/7)
    local voteTab=newTab("Vote",1/7)
    local themeTab=newTab("Theme",1/7)

    local function lbl(par,txt,ord)
        local l=Instance.new("TextLabel")
        l.Size=UDim2.new(1,0,0,16); l.BackgroundTransparency=1
        l.Text=txt; l.TextColor3=TEXT_DIM; l.Font=Enum.Font.Gotham; l.TextSize=10
        l.TextXAlignment=Enum.TextXAlignment.Left; l.LayoutOrder=ord; l.Parent=par
        return l
    end
    local function tog(par,txt,init,ord,cb)
        local row=Instance.new("Frame")
        row.Size=UDim2.new(1,0,0,26); row.BackgroundTransparency=1; row.LayoutOrder=ord; row.Parent=par
        local l=Instance.new("TextLabel")
        l.Size=UDim2.new(1,-60,1,0); l.BackgroundTransparency=1
        l.Text=txt; l.TextColor3=TEXT_BRIGHT; l.Font=Enum.Font.Gotham; l.TextSize=12
        l.TextXAlignment=Enum.TextXAlignment.Left; l.Parent=row
        local b=Instance.new("TextButton")
        b.Size=UDim2.new(0,48,0,20); b.Position=UDim2.new(1,-52,0.5,-10)
        b.BackgroundColor3=init and PRIMARY or Color3.fromRGB(55,55,55)
        b.Text=init and "ON" or "OFF"
        b.TextColor3=init and Color3.fromRGB(0,0,0) or Color3.fromRGB(255,255,255)
        b.Font=Enum.Font.GothamBold; b.TextSize=10; b.Parent=row
        local st=init
        b.MouseButton1Click:Connect(function()
            st=not st
            b.BackgroundColor3=st and PRIMARY or Color3.fromRGB(55,55,55)
            b.Text=st and "ON" or "OFF"
            b.TextColor3=st and Color3.fromRGB(0,0,0) or Color3.fromRGB(255,255,255)
            pcall(function() cb(st) end); save()
        end)
    end
    local function inp(par,label,val,ord,cb)
        local row=Instance.new("Frame")
        row.Size=UDim2.new(1,0,0,24); row.BackgroundTransparency=1; row.LayoutOrder=ord; row.Parent=par
        local l=Instance.new("TextLabel")
        l.Size=UDim2.new(1,-80,1,0); l.BackgroundTransparency=1
        l.Text=label; l.TextColor3=TEXT_BRIGHT; l.Font=Enum.Font.Gotham; l.TextSize=11
        l.TextXAlignment=Enum.TextXAlignment.Left; l.Parent=row
        local b=Instance.new("TextBox")
        b.Size=UDim2.new(0,72,0,20); b.Position=UDim2.new(1,-76,0.5,-10)
        b.BackgroundColor3=Color3.fromRGB(45,45,45)
        b.TextColor3=Color3.fromRGB(255,255,255); b.Text=tostring(val)
        b.Font=Enum.Font.Gotham; b.TextSize=11; b.Parent=row
        b.FocusLost:Connect(function() pcall(function() cb(b.Text) end); save() end)
    end
    local function wide(par,label,val,ord,cb)
        local col=Instance.new("Frame")
        col.Size=UDim2.new(1,0,0,44); col.BackgroundTransparency=1; col.LayoutOrder=ord; col.Parent=par
        local l=Instance.new("TextLabel")
        l.Size=UDim2.new(1,0,0,14); l.BackgroundTransparency=1
        l.Text=label; l.TextColor3=TEXT_BRIGHT; l.Font=Enum.Font.Gotham; l.TextSize=11
        l.TextXAlignment=Enum.TextXAlignment.Left; l.Parent=col
        local b=Instance.new("TextBox")
        b.Size=UDim2.new(1,0,0,24); b.Position=UDim2.new(0,0,0,16)
        b.BackgroundColor3=Color3.fromRGB(45,45,45)
        b.TextColor3=Color3.fromRGB(255,255,255); b.Text=tostring(val)
        b.Font=Enum.Font.Gotham; b.TextSize=10; b.Parent=col
        b.FocusLost:Connect(function() pcall(function() cb(b.Text) end); save() end)
    end
    local function cyc(par,label,opts,init,ord,cb)
        local row=Instance.new("Frame")
        row.Size=UDim2.new(1,0,0,26); row.BackgroundTransparency=1; row.LayoutOrder=ord; row.Parent=par
        local l=Instance.new("TextLabel")
        l.Size=UDim2.new(1,-130,1,0); l.BackgroundTransparency=1
        l.Text=label; l.TextColor3=TEXT_BRIGHT; l.Font=Enum.Font.Gotham; l.TextSize=11
        l.TextXAlignment=Enum.TextXAlignment.Left; l.Parent=row
        local b=Instance.new("TextButton")
        b.Size=UDim2.new(0,120,0,20); b.Position=UDim2.new(1,-124,0.5,-10)
        b.BackgroundColor3=Color3.fromRGB(55,55,55)
        b.TextColor3=Color3.fromRGB(255,255,255); b.Font=Enum.Font.Gotham; b.TextSize=11; b.Parent=row
        local i=findIdx(opts,init); b.Text=opts[i]
        b.MouseButton1Click:Connect(function()
            i=i%#opts+1; b.Text=opts[i]; pcall(function() cb(opts[i]) end); save()
        end)
    end

    local o=0
    local function no() o=o+1; return o end

    tog(mainTab,"AUTO FARM",C.Farming,no(),function(s) if s then farm() else stopFarm() end end)
    lbl(mainTab,"— Currency —",no())
    cyc(mainTab,"Target",{"Coin","Candy","SnowToken","Token","Shell"},C.Currency,no(),function(v) C.Currency=v end)
    lbl(mainTab,"— Movement —",no())
    inp(mainTab,"Speed (studs/s)",C.Speed,no(),function(v) local n=tonumber(v); if n then C.Speed=math.clamp(n,10,70) end end)
    cyc(mainTab,"Farm mode",{"Stealth","Standard","Lay"},C.FarmMode,no(),function(v) C.FarmMode=v end)
    inp(mainTab,"Stealth depth",C.Depth,no(),function(v) local n=tonumber(v); if n then C.Depth=math.clamp(n,5,50) end end)
    inp(mainTab,"Coin rise height",C.CoinRise,no(),function(v) local n=tonumber(v); if n then C.CoinRise=math.clamp(n,1,20) end end)
    lbl(mainTab,"— Bag —",no())
    inp(mainTab,"Threshold (0=auto)",C.Threshold,no(),function(v) local n=tonumber(v); if n then C.Threshold=math.max(0,n) end end)
    local stats=Instance.new("TextLabel")
    stats.Size=UDim2.new(1,0,0,72); stats.BackgroundColor3=Color3.fromRGB(30,28,0)
    stats.BorderSizePixel=0; stats.TextColor3=PRIMARY; stats.Font=Enum.Font.Code; stats.TextSize=10
    stats.Text="Collected: 0\nPer hour: 0\nBag: ?/40\nFails: 0\nStatus: idle"
    stats.LayoutOrder=no(); stats.Parent=mainTab
    task.spawn(function()
        while stats.Parent do
            task.wait(0.5)
            local b=statValue()
            stats.Text=string.format("Collected: %d\nPer hour: %d\nBag: %s/%d\nFails: %d\nStatus: %s",
                C.Stats.Total, rate(),
                b and tostring(b) or "?", threshold(),
                C.CollectFails, C.FarmStatus or "idle")
        end
    end)

    o=0
    lbl(actionsTab,"— Innocent —",no())
    tog(actionsTab,"Reset when full",C.ResetInnocent,no(),function(s) C.ResetInnocent=s end)
    tog(actionsTab,"Fling murderer when full",C.FlingMurderer,no(),function(s) C.FlingMurderer=s end)
    lbl(actionsTab,"— Sheriff —",no())
    tog(actionsTab,"Shoot murderer when full",C.ShootSheriff,no(),function(s) C.ShootSheriff=s end)
    lbl(actionsTab,"— Murderer —",no())
    tog(actionsTab,"Kill all when full",C.KillMurderer,no(),function(s) C.KillMurderer=s end)
    tog(actionsTab,"Reset when full",C.ResetMurderer,no(),function(s) C.ResetMurderer=s end)
    lbl(actionsTab,"— Flow —",no())
    tog(actionsTab,"Reset after action",C.ResetAfterAction,no(),function(s) C.ResetAfterAction=s end)
    tog(actionsTab,"Reset regardless of role",C.ResetAnyRole,no(),function(s) C.ResetAnyRole=s end)

    o=0
    tog(protectTab,"Anti-AFK",C.AntiAFK,no(),function(s) C.AntiAFK=s; if s then startAFK() end end)
    tog(protectTab,"Anti-Void",C.AntiVoid,no(),function(s) C.AntiVoid=s; setupVoid() end)
    tog(protectTab,"Anti-Fling",C.AntiFling,no(),function(s) C.AntiFling=s end)
    tog(protectTab,"Anti-Murderer (drops down)",C.AntiMurderer,no(),function(s) C.AntiMurderer=s end)
    tog(protectTab,"Noclip",C.Noclip,no(),function(s) C.Noclip=s; if s then startNoclip() else stopNoclip() end end)
    tog(protectTab,"Disable 3D",C.Disable3D,no(),function(s) C.Disable3D=s; pcall(function() RunService:Set3dRenderingEnabled(not s) end) end)

    o=0
    lbl(espTab,"— Player ESP —",no())
    tog(espTab,"Boxes + Names",C.ESPOn,no(),function(s) C.ESPOn=s end)
    tog(espTab,"Tracers",C.TracersOn,no(),function(s) C.TracersOn=s end)
    tog(espTab,"Chams (fill)",C.ChamsOn,no(),function(s) C.ChamsOn=s end)
    tog(espTab,"Outlines",C.OutlinesOn,no(),function(s) C.OutlinesOn=s end)
    lbl(espTab,"— Roles shown —",no())
    tog(espTab,"Murderer (red)",C.ShowMurderer,no(),function(s) C.ShowMurderer=s end)
    tog(espTab,"Sheriff (blue)",C.ShowSheriff,no(),function(s) C.ShowSheriff=s end)
    tog(espTab,"Hero (yellow)",C.ShowHero,no(),function(s) C.ShowHero=s end)
    tog(espTab,"Innocent (green)",C.ShowInnocent,no(),function(s) C.ShowInnocent=s end)
    lbl(espTab,"— Objects —",no())
    tog(espTab,"Coin ESP",C.CoinESP,no(),function(s) C.CoinESP=s end)
    tog(espTab,"Dropped Gun ESP",C.GunESP,no(),function(s) C.GunESP=s end)

    o=0
    wide(serverTab,"Reexec URL (raw GitHub)",C.ReexecURL,no(),function(v) C.ReexecURL=v end)
    inp(serverTab,"Hop if players >",C.HopAt,no(),function(v) local n=tonumber(v); if n then C.HopAt=n end end)
    tog(serverTab,"Hop when friend joins",C.HopFriend,no(),function(s) C.HopFriend=s; if s then friendMonitor() end end)
    local hopLbl=Instance.new("TextLabel")
    hopLbl.Size=UDim2.new(1,0,0,24); hopLbl.BackgroundColor3=Color3.fromRGB(28,28,28)
    hopLbl.BorderSizePixel=0; hopLbl.TextColor3=PRIMARY; hopLbl.Font=Enum.Font.Code; hopLbl.TextSize=10
    hopLbl.Text="Hop: idle"; hopLbl.LayoutOrder=no(); hopLbl.Parent=serverTab
    task.spawn(function()
        while hopLbl.Parent do
            task.wait(0.5)
            hopLbl.Text="Hop: "..(C.HopStatus~="" and C.HopStatus or "idle")
        end
    end)

    o=0
    local voteOpts={"OFF","Smallest Map","Largest Map","Random"}
    local voteMap={OFF=0,["Smallest Map"]=1,["Largest Map"]=2,Random=3}
    local voteRev={[0]="OFF",[1]="Smallest Map",[2]="Largest Map",[3]="Random"}
    cyc(voteTab,"Vote mode",voteOpts,voteRev[C.VoteMode] or "OFF",no(),function(v)
        C.VoteMode=voteMap[v] or 0
        if C.VoteMode~=0 then startVote() else stopVote() end
    end)
    inp(voteTab,"Max votes (0=inf)",C.VoteMax,no(),function(v) local n=tonumber(v); if n then C.VoteMax=math.max(0,n) end end)

    o=0
    wide(themeTab,"Primary color (hex)",C.PrimaryColor,no(),function(v)
        C.PrimaryColor=v
        local c=parseHex(v); if c then PRIMARY=c; buildGui() end
    end)
    wide(themeTab,"Secondary color (hex)",C.SecondaryColor,no(),function(v)
        C.SecondaryColor=v
        local c=parseHex(v); if c then SECONDARY=c; buildGui() end
    end)
    local pvBtn=Instance.new("TextButton")
    pvBtn.Size=UDim2.new(1,0,0,30); pvBtn.BackgroundColor3=PRIMARY
    pvBtn.Text="Rebuild GUI with new colors"; pvBtn.TextColor3=Color3.fromRGB(0,0,0)
    pvBtn.Font=Enum.Font.GothamBold; pvBtn.TextSize=11; pvBtn.LayoutOrder=no(); pvBtn.Parent=themeTab
    pvBtn.MouseButton1Click:Connect(function() buildGui() end)

    tabs["Main"].btn.MouseButton1Click:Fire()
end

-- ============ INIT ============
captureSrc()

LocalPlayer.CharacterAdded:Connect(function(ch)
    pdCache.data=nil
    task.wait(0.5)
    local u=ch:FindFirstChildOfClass("Humanoid")
    if u then
        u.Died:Connect(function()
            local h=ch:FindFirstChild("HumanoidRootPart")
            if h then pcall(function() h.Anchored=false end) end
        end)
    end
end)

statsTick()
if C.AntiAFK then startAFK() end
if C.AntiVoid then setupVoid() end
if C.AntiFling then startFling() end
if C.AntiMurderer then startAntiMurderer() end
if C.Noclip then startNoclip() end
if C.HopAt>0 then hopMonitor() end
if C.HopFriend then friendMonitor() end
if C.Disable3D then pcall(function() RunService:Set3dRenderingEnabled(false) end) end

buildGui()

print("[Lambda] v0.21 ready | HWID: "..HWID)
if C.ReexecURL~="" then print("[Lambda] Reexec URL: "..C.ReexecURL)
else warn("[Lambda] Reexec URL vazio — preencha na aba Server para reexecutar após hop") end
