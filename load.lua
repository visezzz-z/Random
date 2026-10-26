-- Lambda Hub | v0.26 | By kerli
-- Stealth aura magnet | Fix fling | Shoot-until-dead loop

print("[Lambda] v0.26 loading")

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local VirtualUser = game:GetService("VirtualUser")
local VirtualInputManager = game:GetService("VirtualInputManager")
local UIS = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

local function hwid()
    local ok, id = pcall(function() return gethwid() end)
    if ok and type(id)=="string" and #id>0 then return id end
    local ok2, cid = pcall(function() return game:GetService("RbxAnalyticsService"):GetClientId() end)
    if ok2 and type(cid)=="string" and #cid>0 then return cid end
    return tostring(LocalPlayer.UserId)
end
local HWID = hwid()
local PREFS = "LAMBDA_HUB_"..(HWID:gsub("[^%w_%-]","_"))..".json"

local function env() local e={}; pcall(function() local g=getgenv(); if type(g)=="table" then e=g end end); return e end
local function prefsLoad()
    local e=env(); local rd=type(readfile)=="function" and readfile or e.readfile
    if not rd then return nil end
    local ok,d=pcall(rd,PREFS)
    if ok and d then local ok2,dec=pcall(function() return HttpService:JSONDecode(d) end); if ok2 then return dec end end
    return nil
end
local function prefsSave(t)
    local e=env(); local wr=type(writefile)=="function" and writefile or e.writefile
    if not wr then return end
    local ok,enc=pcall(function() return HttpService:JSONEncode(t) end)
    if ok then pcall(wr,PREFS,enc) end
end

getgenv().LAMBDA = getgenv().LAMBDA or {}
local C = getgenv().LAMBDA

local DEFAULTS = {
    Currency="Coin", Speed=35, FarmMode="Stealth", Depth=3, AuraRadius=15,
    HopAt=6, HopFriend=false, AutoLaunch=true, AutoRejoin=true,
    AntiAFK=true, AntiVoid=true, AntiFling=true, Noclip=true, AntiMurderer=false,
    Disable3D=false, VoteMode=0, VoteMax=0,
    ResetInnocent=true, FlingMurderer=false, ShootSheriff=true, ResetAnyRole=false,
    KillMurderer=true, ResetMurderer=false, Threshold=50, ResetAfterAction=true,
    PrimaryColor="#FFC800", SecondaryColor="#1E1E1E",
    Visuals_ESP_Murderer=false, Visuals_TR_Murderer=false, Visuals_CH_Murderer=false, Visuals_OL_Murderer=false, Visuals_HL_Murderer=false, Visuals_BX_Murderer=false,
    Visuals_ESP_Sheriff=false,  Visuals_TR_Sheriff=false,  Visuals_CH_Sheriff=false,  Visuals_OL_Sheriff=false,  Visuals_HL_Sheriff=false,  Visuals_BX_Sheriff=false,
    Visuals_ESP_Hero=false,     Visuals_TR_Hero=false,     Visuals_CH_Hero=false,     Visuals_OL_Hero=false,     Visuals_HL_Hero=false,     Visuals_BX_Hero=false,
    Visuals_ESP_Innocent=false, Visuals_TR_Innocent=false, Visuals_CH_Innocent=false, Visuals_OL_Innocent=false, Visuals_HL_Innocent=false, Visuals_BX_Innocent=false,
    Visuals_BX_Coin=false, Visuals_CH_Coin=false, Visuals_OL_Coin=false, Visuals_HL_Coin=false,
    Visuals_BX_Gun=false,  Visuals_CH_Gun=false,  Visuals_OL_Gun=false,  Visuals_HL_Gun=false,
}
for k,v in pairs(DEFAULTS) do if C[k]==nil then C[k]=v end end
local saved = prefsLoad()
if saved then for k,v in pairs(saved) do if C[k]~=nil then C[k]=v end end end

C.Farming=false; C.FarmStatus="idle"; C.FarmThread=nil
C.HopThread=nil; C.FriendThread=nil; C.VoteThread=nil; C.AntiMurdererThread=nil
C.LastFull=tick(); C.Cooldown=0; C.HopStatus=""; C.LastKickReason=""
C.IsHopping=false; C.IsTeleporting=false; C.IntentionalReset=false
C.Stats={Total=0, Start=tick(), Last=0}
C.MissCount=0; C.WasInRound=false
C.CollectFails=0
C.RejoinActive=false

local function save() local t={} for k,_ in pairs(DEFAULTS) do t[k]=C[k] end prefsSave(t) end

local function parseHex(s)
    s=tostring(s or ""):gsub("#","")
    if #s~=6 then return nil end
    local n=tonumber(s,16); if not n then return nil end
    return Color3.fromRGB(bit32.rshift(bit32.band(n,0xFF0000),16), bit32.rshift(bit32.band(n,0x00FF00),8), bit32.band(n,0x0000FF))
end
local function colorToHex(c)
    return string.format("#%02X%02X%02X", math.floor(c.R*255+.5), math.floor(c.G*255+.5), math.floor(c.B*255+.5))
end
local PRIMARY = parseHex(C.PrimaryColor) or Color3.fromRGB(255,200,0)
local SECONDARY = parseHex(C.SecondaryColor) or Color3.fromRGB(30,30,30)
local TEXT_DIM = Color3.fromRGB(150,150,150)
local TEXT_BRIGHT = Color3.fromRGB(220,220,220)

local function HRP() local c=LocalPlayer.Character; return c and c:FindFirstChild("HumanoidRootPart") end
local function HUM() local c=LocalPlayer.Character; return c and c:FindFirstChildOfClass("Humanoid") end

-- ============ Background GetPlayerData ============
local pdCache={data=nil,ts=0}
task.spawn(function()
    while true do
        task.wait(0.75)
        local ok,data=pcall(function()
            local r=ReplicatedStorage:FindFirstChild("GetPlayerData",true)
            if r and r:IsA("RemoteFunction") then return r:InvokeServer() end
        end)
        if ok and data then pdCache.data=data; pdCache.ts=tick() end
    end
end)
local function PD() return pdCache.data end

local function isDeadOrOutOfRound()
    local hum=HUM()
    if not hum then return true end
    if hum.Health<=0 then return true end
    if hum:GetState()==Enum.HumanoidStateType.Dead then return true end
    local d=PD()
    if d then
        local me=d[LocalPlayer.Name]
        if me then
            if me.Dead==true or me.Killed==true then return true end
            if me.Role=="None" then return true end
        end
    end
    return false
end

local function findMurderer()
    local d=PD(); if not d then return nil end
    for n,i in pairs(d) do
        if i.Role=="Murderer" and not i.Killed and not i.Dead then
            local p=Players:FindFirstChild(n)
            if p and p~=LocalPlayer then return p end
        end
    end
    return nil
end

local function murdererNearby(radius)
    radius=radius or 40
    local m=findMurderer()
    if not m or not m.Character then return false end
    local mh=m.Character:FindFirstChild("HumanoidRootPart")
    local myh=HRP()
    if not mh or not myh then return false end
    return (mh.Position-myh.Position).Magnitude<=radius
end

local function cleanup()
    local h=HRP(); if h then pcall(function() h.Anchored=false; h.AssemblyLinearVelocity=Vector3.zero; h.AssemblyAngularVelocity=Vector3.zero end) end
    local u=HUM(); if u then u.PlatformStand=false; u.AutoRotate=true end
end
local function hardReset()
    C.IntentionalReset=true
    local h=HRP(); if h then pcall(function() h.Anchored=false end) end
    local u=HUM(); if u then u.PlatformStand=false; u.AutoRotate=true; if u.Health>0 then u.Health=0 end end
    task.delay(1.5,function() C.IntentionalReset=false end)
end

-- ============ Rejoin ============
local RejoinState = { active=false }
local function getRejoinDelay(reason)
    reason=tostring(reason):lower()
    if reason:find("exploit") or reason:find("cheat") or reason:find("hack") then return 5 end
    if reason:find("position") or reason:find("bounds") then return 1 end
    return 0.5
end
local function safeRejoin(reason)
    if RejoinState.active then return end
    if not C.AutoRejoin and reason~="manual" then return end
    RejoinState.active=true; C.RejoinActive=true; C.LastKickReason=tostring(reason)
    print("[Lambda] Rejoin: "..tostring(reason))
    task.spawn(function()
        for attempt=1,2 do
            if C.IsHopping then break end
            C.HopStatus="rejoin "..attempt.."/2"
            local ok=pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId,game.JobId,LocalPlayer) end)
            if ok then task.wait(3); RejoinState.active=false; C.RejoinActive=false; return end
            task.wait(getRejoinDelay(reason))
        end
        for attempt=1,3 do
            if C.IsHopping then break end
            C.HopStatus="recover "..attempt.."/3"
            local ok=pcall(function() TeleportService:Teleport(game.PlaceId,LocalPlayer) end)
            if ok then task.wait(3); RejoinState.active=false; C.RejoinActive=false; return end
            task.wait(3)
        end
        C.HopStatus="recover FAILED"; RejoinState.active=false; C.RejoinActive=false
    end)
end

-- ============ Position watchdog ============
local lastSafePos=nil
RunService.Heartbeat:Connect(function()
    local hrp=HRP(); if not hrp then return end
    local p=hrp.Position
    if p.Y>-100 and p.Y<5000 and math.abs(p.X)<5000 and math.abs(p.Z)<5000 then
        lastSafePos=p
    elseif lastSafePos and (p.Y<-500 or p.Y>50000 or math.abs(p.X)>100000 or math.abs(p.Z)>100000) then
        pcall(function()
            hrp.CFrame=CFrame.new(lastSafePos+Vector3.new(0,5,0))
            hrp.AssemblyLinearVelocity=Vector3.zero
            hrp.AssemblyAngularVelocity=Vector3.zero
        end)
    end
end)

-- ============ Metatable hooks ============
pcall(function()
    if not (getrawmetatable and setreadonly and newcclosure) then
        warn("[Lambda] getrawmetatable indisponível"); return
    end
    local mt=getrawmetatable(game)
    local oldNC=mt.__namecall
    local oldNI=mt.__newindex
    setreadonly(mt,false)
    mt.__namecall=newcclosure(function(self,...)
        local method=getnamecallmethod()
        if method=="Kick" and self==LocalPlayer then
            local args={...}; local reason=tostring(args[1] or "unknown")
            print("[Lambda] Kick intercepted: "..reason); safeRejoin(reason); return nil
        end
        if C.AntiMurderer and not C.IntentionalReset then
            local hum=HUM()
            if hum and self==hum then
                if method=="TakeDamage" then return 0 end
                if method=="ChangeState" then
                    local a={...}
                    if a[1]==Enum.HumanoidStateType.Dead then return nil end
                end
            end
        end
        return oldNC(self,...)
    end)
    mt.__newindex=newcclosure(function(self,key,value)
        if C.AntiMurderer and not C.IntentionalReset then
            local hum=HUM()
            if hum and self==hum and key=="Health" and value<=0 then
                if murdererNearby() then return end
            end
        end
        return oldNI(self,key,value)
    end)
    setreadonly(mt,true)
    print("[Lambda] Hooks installed")
end)

RunService.Heartbeat:Connect(function()
    if not C.AntiMurderer or C.IntentionalReset then return end
    local hum=HUM(); if not hum or hum.Health<=0 then return end
    if murdererNearby() then
        if hum.MaxHealth<1000 then pcall(function() hum.MaxHealth=1000 end) end
        if hum.Health<hum.MaxHealth then pcall(function() hum.Health=hum.MaxHealth end) end
    end
end)

-- ============ Bag ============
local EVENT_CURR={Candy=true,SnowToken=true,Token=true,Shell=true,Egg=true,Present=true,Gift=true,Gem=true}
local function threshold()
    if C.Threshold>0 then return C.Threshold end
    return EVENT_CURR[C.Currency] and 50 or 40
end
local PATTERNS={"coin","cand","token","shell","egg","present","gift","gem","snow"}
local function statValue()
    local best
    local ls=LocalPlayer:FindFirstChild("leaderstats")
    if ls then
        for _,ch in ipairs(ls:GetChildren()) do
            if ch:IsA("IntValue") or ch:IsA("NumberValue") then
                local n=ch.Name:lower()
                for _,p in ipairs(PATTERNS) do
                    if n:find(p) then if not best or ch.Value>best then best=ch.Value end; break end
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
    noclipConn=RunService.Stepped:Connect(function()
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
    afkConn=LocalPlayer.Idled:Connect(function()
        pcall(function() VirtualUser:CaptureController(); VirtualUser:ClickButton2(Vector2.new(0,0)) end)
    end)
end

local voidConn
local origDH=Workspace.FallenPartsDestroyHeight
local function setupVoid()
    if not C.AntiVoid then Workspace.FallenPartsDestroyHeight=origDH; if voidConn then voidConn:Disconnect(); voidConn=nil end; return end
    Workspace.FallenPartsDestroyHeight=0/0
    if voidConn then voidConn:Disconnect() end
    voidConn=LocalPlayer.CharacterAdded:Connect(function() task.wait(0.1); Workspace.FallenPartsDestroyHeight=0/0 end)
end

local function startFling()
    local lastP,lastT=nil,tick(); local lastC=nil
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

-- ============ Coin cache + blacklist ============
local coinCache={parts={},ts=0}
local coinBlacklist={}
local function isBlacklisted(c)
    local t=coinBlacklist[c]
    if not t then return false end
    if tick()-t>1.5 then coinBlacklist[c]=nil; return false end
    return true
end
local function blacklist(c)
    coinBlacklist[c]=tick()
    for k,v in pairs(coinBlacklist) do
        if tick()-v>3 then coinBlacklist[k]=nil end
    end
end

local function getContainers()
    local list={}
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
    if tick()-coinCache.ts<0.4 then
        local alive={}
        for _,p in ipairs(coinCache.parts) do if p.Parent then table.insert(alive,p) end end
        coinCache.parts=alive
        return alive
    end
    local parts={}
    for _,c in ipairs(getContainers()) do
        for _,d in ipairs(c:GetDescendants()) do
            if d:IsA("BasePart") and d:FindFirstChildWhichIsA("TouchTransmitter") then table.insert(parts,d) end
        end
    end
    coinCache.parts=parts; coinCache.ts=tick()
    return parts
end
local function nearestCoin()
    local h=HRP(); if not h then return nil end
    local best,bd=nil,math.huge
    for _,p in ipairs(getCoins()) do
        if not isBlacklisted(p) then
            local d=(h.Position-p.Position).Magnitude
            if d<bd then bd=d; best=p end
        end
    end
    return best
end

-- ============ Movement ============
local LAY=CFrame.Angles(math.rad(90),0,0)
local function travel(targetPos,rot90,spd,coinRef)
    local h=HRP(); if not h then return false end
    if not h.Anchored then h.Anchored=true end
    local u=HUM()
    if u and not u.PlatformStand then u.PlatformStand=true; u.AutoRotate=false end
    spd=math.clamp(spd or C.Speed,10,70)
    local rot=rot90 and LAY or h.CFrame.Rotation
    local lastT=tick(); local startT=tick()
    local lastDist=math.huge; local lastProgress=tick()
    while C.Farming do
        if tick()-startT>15 then return false end
        if isDeadOrOutOfRound() then return false end
        local cur=HRP()
        if not cur or not cur.Anchored then return false end
        if coinRef and not coinRef.Parent then return false end
        if cur.Position.Y<-150 or cur.Position.Y>10000 then return false end
        local delta=targetPos-cur.Position
        local dist=delta.Magnitude
        if dist<2.5 then cur.CFrame=CFrame.new(targetPos)*rot; return true end
        if dist<lastDist-1 then lastProgress=tick(); lastDist=dist
        elseif tick()-lastProgress>3 then return false end
        local now=tick(); local dt=math.min(now-lastT,0.05); lastT=now
        local step=math.min(spd*dt,dist)
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

-- ============ Aura ============
local function fireTouchBurst(coin)
    local hrp=HRP(); local ch=LocalPlayer.Character
    if not hrp or not ch or not coin or not coin.Parent then return end
    local torso=ch:FindFirstChild("UpperTorso") or ch:FindFirstChild("Torso")
    pcall(function()
        if torso then firetouchinterest(torso,coin,0) end
        firetouchinterest(hrp,coin,0)
        if torso then firetouchinterest(torso,coin,1) end
        firetouchinterest(hrp,coin,1)
    end)
end

local function auraBurst(targetCoin, deadline)
    local collectedTarget = false
    local statBefore = statValue() or 0
    while C.Farming and tick() < deadline do
        local hrp = HRP()
        if not hrp then return false end
        local anyNear = false
        for _, c in ipairs(getCoins()) do
            if not isBlacklisted(c) then
                local d = (hrp.Position - c.Position).Magnitude
                if d <= C.AuraRadius then
                    anyNear = true
                    fireTouchBurst(c)
                    if not c.Parent then
                        if c == targetCoin then collectedTarget = true end
                    end
                end
            end
        end
        local statAfter = statValue() or 0
        if statAfter > statBefore then
            -- Confirmed collection via leaderstats
            if targetCoin and not targetCoin.Parent then collectedTarget = true end
            if collectedTarget then return true end
        end
        if collectedTarget then return true end
        if not anyNear then break end
        task.wait(0.015)
    end
    return collectedTarget
end

-- ============ Role / actions ============
local function role()
    local d=PD()
    if d and d[LocalPlayer.Name] then
        local r=d[LocalPlayer.Name].Role
        if r and r~="None" then return r end
    end
    for _,cont in ipairs({LocalPlayer.Character,LocalPlayer:FindFirstChild("Backpack")}) do
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
    local ev=k:FindFirstChild("Events"); local ht=ev and ev:FindFirstChild("HandleTouched")
    if not ht then return end
    for _,p in ipairs(Players:GetPlayers()) do
        if p~=LocalPlayer and p.Character then
            local up=p.Character:FindFirstChild("UpperTorso") or p.Character:FindFirstChild("Torso")
            if up then pcall(function() ht:FireServer(up) end); task.wait(0.05) end
        end
    end
end

-- ============ Fling (AFP-style) ============
local function flingMurderer()
    local murderer = findMurderer()
    if not murderer or not murderer.Character then return false end
    local myChar = LocalPlayer.Character
    if not myChar then return false end
    local myHum = myChar:FindFirstChildOfClass("Humanoid")
    local myRoot = myChar:FindFirstChild("HumanoidRootPart")
    if not myHum or not myRoot then return false end

    if myRoot.Anchored then myRoot.Anchored = false end
    myHum.PlatformStand = true
    for _, track in ipairs(myHum:GetPlayingAnimationTracks()) do
        pcall(function() track:Stop() end)
    end

    local origHeight = Workspace.FallenPartsDestroyHeight
    local savedCF = myRoot.CFrame

    for attempt = 1, 3 do
        local tChar = murderer.Character
        if not tChar then break end
        local tHum = tChar:FindFirstChildOfClass("Humanoid")
        if not tHum or tHum.Health <= 0 then break end
        local tRoot = tChar:FindFirstChild("HumanoidRootPart")
        local tHead = tChar:FindFirstChild("Head")
        if not tRoot then break end

        local bv = Instance.new("BodyVelocity")
        bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
        bv.Velocity = Vector3.new(0, -50000, 0)
        bv.Parent = myRoot

        local bg = Instance.new("BodyGyro")
        bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
        bg.P = 1000000
        bg.Parent = myRoot

        Workspace.FallenPartsDestroyHeight = 0/0

        local start = tick()
        while tick() - start < 1.0 and C.Farming do
            if not tChar or not tRoot.Parent then break end
            if not myRoot or not myRoot.Parent then break end
            local headPos = tHead and tHead.Position or (tRoot.Position + Vector3.new(0, 2.5, 0))
            pcall(function()
                myRoot.CFrame = CFrame.new(headPos) * CFrame.Angles(math.pi/2, 0, 0)
            end)
            myRoot.AssemblyLinearVelocity = Vector3.new(0, -50000, 0)
            myRoot.AssemblyAngularVelocity = Vector3.new(7500, 7500, 7500)
            for _ = 1, 5 do
                pcall(function() firetouchinterest(myRoot, tRoot, 0) end)
                pcall(function() firetouchinterest(myRoot, tRoot, 1) end)
                if tHead then
                    pcall(function() firetouchinterest(myRoot, tHead, 0) end)
                    pcall(function() firetouchinterest(myRoot, tHead, 1) end)
                end
            end
            RunService.Heartbeat:Wait()
        end

        pcall(function() bv:Destroy() end)
        pcall(function() bg:Destroy() end)
        Workspace.FallenPartsDestroyHeight = origHeight

        if not murderer.Character then break end
        local tHum2 = murderer.Character:FindFirstChildOfClass("Humanoid")
        if not tHum2 or tHum2.Health <= 0 then break end
        task.wait(0.2)
    end

    Workspace.FallenPartsDestroyHeight = origHeight
    if myRoot and myRoot.Parent then
        pcall(function()
            myRoot.CFrame = savedCF
            myRoot.AssemblyLinearVelocity = Vector3.zero
            myRoot.AssemblyAngularVelocity = Vector3.zero
        end)
    end
    if myHum and myHum.Parent then
        myHum.PlatformStand = false
        pcall(function() myHum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
    end
    return true
end

-- ============ Shoot loop ============
local function shootAtMurderer()
    local gun = equip("Gun")
    if not gun then return false end
    local m = findMurderer()
    if not m or not m.Character then return false end
    local mHrp = m.Character:FindFirstChild("HumanoidRootPart")
    local hrp = HRP()
    if not mHrp or not hrp then return false end

    -- Aim: rotate root + camera to face murderer
    pcall(function()
        hrp.CFrame = CFrame.new(hrp.Position, mHrp.Position)
    end)
    local cam = workspace.CurrentCamera
    if cam then
        pcall(function()
            cam.CFrame = CFrame.new(cam.CFrame.Position, mHrp.Position)
        end)
    end
    task.wait(0.05)

    -- Method 1: Activate
    pcall(function() gun:Activate() end)

    -- Method 2: Click center (mobile/PC)
    local vp = cam and cam.ViewportSize or Vector2.new(800, 600)
    local center = Vector2.new(vp.X / 2, vp.Y / 2)
    local isMobile = UIS.TouchEnabled and not UIS.MouseEnabled
    if isMobile then
        pcall(function() VirtualUser:Button1Down(center, cam.CFrame) end)
        task.wait(0.06)
        pcall(function() VirtualUser:Button1Up(center, cam.CFrame) end)
    else
        pcall(function()
            VirtualInputManager:SendMouseButtonEvent(center.X, center.Y, 0, true, game, 0)
            task.wait(0.06)
            VirtualInputManager:SendMouseButtonEvent(center.X, center.Y, 0, false, game, 0)
        end)
    end

    -- Method 3: Fire remote events
    local ev = gun:FindFirstChild("Events")
    if ev then
        for _, r in ipairs(ev:GetChildren()) do
            if r:IsA("RemoteEvent") then
                local rn = r.Name:lower()
                if rn:find("fire") or rn:find("shoot") or rn:find("click") or rn:find("hit") then
                    pcall(function() r:FireServer(mHrp) end)
                end
            end
        end
    end
    return true
end

local function shootLoop()
    local deadline = tick() + 10
    while tick() < deadline and C.Farming do
        local m = findMurderer()
        if not m or not m.Character then break end
        local mh = m.Character:FindFirstChildOfClass("Humanoid")
        if not mh or mh.Health <= 0 then break end
        if not shootAtMurderer() then break end
        task.wait(0.35)
    end
end

-- ============ Full bag ============
local function fullBag()
    local r = role()
    local did = false

    -- Unanchor so fling / physical actions work
    local h = HRP()
    if h then h.Anchored = false end
    local u = HUM()
    if u then u.PlatformStand = false; u.AutoRotate = true end

    if r == "Innocent" then
        if C.FlingMurderer then
            C.FarmStatus = "flinging"
            flingMurderer()
            did = true
        end
        if C.ResetInnocent and not did then hardReset(); return end
    elseif r == "Sheriff" then
        if C.ShootSheriff then
            C.FarmStatus = "shooting"
            shootLoop()
            did = true
        end
    elseif r == "Murderer" then
        if C.KillMurderer then killAll(); did = true end
        if C.ResetMurderer and not did then hardReset(); return end
    end

    if did and C.ResetAfterAction then
        task.wait(1.5)
        hardReset()
        return
    end
    if C.ResetAnyRole then hardReset() end
end

local function statsTick()
    task.spawn(function()
        LocalPlayer:WaitForChild("leaderstats",10); task.wait(1)
        C.Stats.Last=statValue() or 0
        while true do
            task.wait(0.5)
            local v=statValue()
            if v and C.Stats.Last and v>C.Stats.Last then C.Stats.Total=C.Stats.Total+(v-C.Stats.Last) end
            if v then C.Stats.Last=v end
        end
    end)
end
local function rate()
    local e=math.max(1,tick()-C.Stats.Start)
    return math.floor((C.Stats.Total/e)*3600)
end

-- ============ Round watcher ============
task.spawn(function()
    local lastC=nil
    while true do
        task.wait(0.15)
        local ch=LocalPlayer.Character
        if ch~=lastC then lastC=ch; C.MissCount=0; C.WasInRound=false end
        local h=ch and ch:FindFirstChild("HumanoidRootPart")
        local u=ch and ch:FindFirstChildOfClass("Humanoid")
        if C.Farming and h and u then
            if h.Position.Y<-150 then
                C.FarmStatus="fell"
                hardReset(); C.Cooldown=tick()+3; C.MissCount=0; C.WasInRound=false
                continue
            end
            local outside=isDeadOrOutOfRound()
            if not outside then C.WasInRound=true; C.MissCount=0
            elseif C.WasInRound then
                C.MissCount=C.MissCount+1
                if C.MissCount>=3 then
                    C.FarmStatus="round end"
                    if u.Health>0 then hardReset() end
                    C.Cooldown=tick()+3; C.MissCount=0; C.WasInRound=false
                end
            end
        else C.MissCount=0; C.WasInRound=false end
    end
end)

-- ============ Farm loop ============
local function farm()
    if C.Farming then return end
    C.Farming=true; C.FarmStatus="starting"
    C.FarmThread=task.spawn(function()
        while C.Farming do
            if tick()<C.Cooldown then C.FarmStatus="cooldown"; cleanup(); task.wait(0.2); continue end
            local u=HUM(); local h=HRP()
            if not u or u.Health<=0 or not h then C.FarmStatus="no char"; task.wait(0.3); continue end
            if u:GetState()==Enum.HumanoidStateType.Dead then C.FarmStatus="dead state"; cleanup(); task.wait(0.3); continue end
            if isDeadOrOutOfRound() then C.FarmStatus="dead/lobby"; cleanup(); task.wait(0.3); continue end

            local coin=nearestCoin()
            if coin then
                if C.FarmMode=="Stealth" then
                    C.FarmStatus="aura"
                    if not h.Anchored then beginMove(); task.wait(0.05) end
                    -- Travel to 3 studs below coin (no coinRef, so coin disappearing mid-travel won't abort)
                    local target = Vector3.new(coin.Position.X, coin.Position.Y - C.Depth, coin.Position.Z)
                    if (h.Position - target).Magnitude > 3 then
                        travel(target, false, C.Speed, nil)
                    end
                    -- Fire touch on all coins within AuraRadius for up to 0.6s
                    local got = auraBurst(coin, tick() + 0.6)
                    if got then
                        C.CollectFails = 0
                        coinCache.ts = 0
                    elseif coin.Parent then
                        blacklist(coin)
                        C.CollectFails = C.CollectFails + 1
                    else
                        C.CollectFails = 0
                        coinCache.ts = 0
                    end
                    task.wait(0.01)
                else
                    C.FarmStatus="travel"
                    if not h.Anchored then beginMove(); task.wait(0.03) end
                    local ok = false
                    if (h.Position - coin.Position).Magnitude > 2.5 then
                        ok = travel(coin.Position, C.FarmMode=="Lay", C.Speed, coin)
                    else
                        ok = true
                    end
                    if ok and coin.Parent then
                        C.FarmStatus="collect"
                        local statBefore = statValue() or 0
                        local t0 = tick()
                        while coin.Parent and C.Farming and tick()-t0 < 0.5 do
                            fireTouchBurst(coin)
                            local sv = statValue() or 0
                            if sv > statBefore then break end
                            task.wait(0.015)
                        end
                        if coin.Parent then
                            blacklist(coin); C.CollectFails = C.CollectFails + 1
                        else
                            C.CollectFails = 0; coinCache.ts = 0
                        end
                    end
                    task.wait(0.01)
                end
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

-- ============ HTTP / hop ============
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
    local raw=httpGet(string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100",game.PlaceId))
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

local function hop()
    if C.IsHopping then return false end
    C.IsHopping=true; C.IsTeleporting=true; C.HopStatus="fetch"
    local list=pool()
    if #list==0 then C.HopStatus="no servers"; C.IsHopping=false; C.IsTeleporting=false; return false end
    for i,s in ipairs(list) do
        C.HopStatus=string.format("try %d/%d",i,#list)
        local ok,res=pcall(function()
            local o=Instance.new("TeleportOptions"); o.ServerInstanceId=s.id
            return TeleportService:TeleportToPlaceInstance(game.PlaceId,s.id,LocalPlayer,o)
        end)
        if ok and not (typeof(res)=="EnumItem" and res==Enum.TeleportState.Failed) then
            C.HopStatus="OK"; task.wait(4); C.IsHopping=false; C.IsTeleporting=false; return true
        end
        task.wait(0.5)
    end
    C.HopStatus="fallback"
    local ok=pcall(function() TeleportService:Teleport(game.PlaceId,LocalPlayer) end)
    task.wait(3); C.IsHopping=false; C.IsTeleporting=false
    C.HopStatus=ok and "fallback OK" or "FAILED"
    return ok
end

local function hopNow()
    if C.IsHopping or RejoinState.active then return end
    task.spawn(hop)
end

local function hopMonitor()
    if C.HopThread then return end
    C.HopThread=task.spawn(function()
        while C.HopAt>0 do
            task.wait(5)
            if not C.IsHopping and not RejoinState.active and #Players:GetPlayers()>C.HopAt then hop(); break end
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
    local l=Workspace:FindFirstChild("Lobby"); local f=l and l:FindFirstChild("VotePads")
    if not f then return o end
    for _,n in ipairs(VOTE_PADS) do
        local p=f:FindFirstChild(n)
        local t=p and p:FindFirstChild("Pad")
        local g=p and p:FindFirstChild("VoteInfoGui")
        local c=g and g:FindFirstChild("Container")
        local l2=c and c:FindFirstChild("MapName")
        if t and l2 and g.Enabled then table.insert(o,{trigger=t,map=l2.Text}) end
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
    local lp=t.CFrame:PointToObjectSpace(pos); local h=t.Size*0.5
    return math.abs(lp.X)<=h.X and math.abs(lp.Y)<=h.Y and math.abs(lp.Z)<=h.Z
end
local function vote(p)
    local h=HRP(); local u=HUM()
    if not h or not u or u.Health<=0 then return false end
    h.Anchored=false; h.AssemblyLinearVelocity=Vector3.zero; h.AssemblyAngularVelocity=Vector3.zero
    u.PlatformStand=false; u.AutoRotate=true
    local pp=p.trigger.Position; h.CFrame=CFrame.new(pp+Vector3.new(0,4,0))
    local st=tick(); local landed=false
    while tick()-st<2 do
        task.wait(0.05)
        local ch=HRP(); if not ch then return false end
        if inside(p.trigger,ch.Position) then landed=true; break end
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
    if u.Health>0 then C.IntentionalReset=true; u:ChangeState(Enum.HumanoidStateType.Dead); u.Health=0; task.delay(1.5,function() C.IntentionalReset=false end) end
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

-- ============ Visuals ============
local ROLE_COLORS={
    Murderer=Color3.fromRGB(255,40,40),
    Sheriff=Color3.fromRGB(40,140,255),
    Hero=Color3.fromRGB(255,200,50),
    Innocent=Color3.fromRGB(60,255,80),
    Unknown=Color3.fromRGB(200,200,200),
}
local COIN_COL=Color3.fromRGB(255,215,0)
local GUN_COL=Color3.fromRGB(255,100,255)
local hasDrawing=(function() local ok,d=pcall(function() return Drawing.new("Square") end); if ok and d then pcall(function() d:Remove() end); return true end; return false end)()

local ESP={draws={},smooth={},highlights={},sboxes={},coinHL={},gunHL={},coinBX={},gunBX={}}

local function visOn(cat, feat) return C["Visuals_"..feat.."_"..cat] == true end
local function roleToCat(r)
    if r=="Murderer" then return "Murderer" end
    if r=="Sheriff" then return "Sheriff" end
    if r=="Hero" then return "Hero" end
    return "Innocent"
end
local function roleFor(p)
    local d=PD()
    if d and d[p.Name] and d[p.Name].Role and d[p.Name].Role~="None" then return d[p.Name].Role end
    return "Innocent"
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

local anyPlayerDrawing=false
local anyHighlight=false
local anyCoin=false
local anyGun=false
local function rebuildVisualCache()
    anyPlayerDrawing=false
    anyHighlight=false
    for _,cat in ipairs({"Murderer","Sheriff","Hero","Innocent"}) do
        if visOn(cat,"ESP") or visOn(cat,"TR") then anyPlayerDrawing=true end
        if visOn(cat,"CH") or visOn(cat,"OL") or visOn(cat,"HL") or visOn(cat,"BX") then anyHighlight=true end
    end
    anyCoin = visOn("Coin","CH") or visOn("Coin","OL") or visOn("Coin","HL") or visOn("Coin","BX")
    anyGun  = visOn("Gun","CH")  or visOn("Gun","OL")  or visOn("Gun","HL")  or visOn("Gun","BX")
end
rebuildVisualCache()

RunService.RenderStepped:Connect(function()
    if not hasDrawing then return end
    if not anyPlayerDrawing then
        for _,t in pairs(ESP.draws) do hideAll(t) end
        return
    end
    local cam=workspace.CurrentCamera; if not cam then return end
    local lh=HRP(); local lu=HUM()
    local origin
    if lh and lu and lu.Health>0 then
        local sp,on=cam:WorldToViewportPoint(lh.Position)
        if on then origin=Vector2.new(sp.X,sp.Y) end
    end
    if not origin then local vs=cam.ViewportSize; origin=Vector2.new(vs.X/2,vs.Y) end
    for _,p in ipairs(Players:GetPlayers()) do
        if p==LocalPlayer then continue end
        local role=roleFor(p)
        local cat=roleToCat(role)
        local wantESP=visOn(cat,"ESP")
        local wantTR=visOn(cat,"TR")
        if not (wantESP or wantTR) then
            if ESP.draws[p] then hideAll(ESP.draws[p]) end
            continue
        end
        local t=ESP.draws[p] or getDraw(p)
        if not t then continue end
        local ch=p.Character
        local hp=ch and ch:FindFirstChild("HumanoidRootPart")
        local hu=ch and ch:FindFirstChildOfClass("Humanoid")
        if not hp or not hu or hu.Health<=0 then hideAll(t) continue end
        local col=ROLE_COLORS[role] or ROLE_COLORS.Unknown
        local top,on1=cam:WorldToViewportPoint(hp.Position+Vector3.new(0,2.6,0))
        local bot,on2=cam:WorldToViewportPoint(hp.Position-Vector3.new(0,2.8,0))
        if not (on1 and on2) then hideAll(t) continue end
        if math.abs(top.Y-bot.Y)<2 then hideAll(t) continue end
        local h=math.abs(top.Y-bot.Y); local w=h/1.8
        local targetPos=Vector2.new(top.X-w/2,top.Y)
        local targetSize=Vector2.new(w,h)
        local targetTracerTo=Vector2.new(top.X,top.Y)
        local s=ESP.smooth[p]
        if not s then s={pos=targetPos,size=targetSize,tracerTo=targetTracerTo}; ESP.smooth[p]=s end
        s.pos=s.pos:Lerp(targetPos,0.4)
        s.size=s.size:Lerp(targetSize,0.4)
        s.tracerTo=s.tracerTo:Lerp(targetTracerTo,0.5)
        if wantESP then
            if t.box then t.box.Position=s.pos; t.box.Size=s.size; t.box.Color=col; t.box.Visible=true end
            if t.name then t.name.Text=p.Name.." ["..role.."]"; t.name.Position=Vector2.new(top.X,s.pos.Y-18); t.name.Color=col; t.name.Visible=true end
        else
            if t.box then t.box.Visible=false end
            if t.name then t.name.Visible=false end
        end
        if wantTR and t.tracer then
            t.tracer.From=origin; t.tracer.To=s.tracerTo; t.tracer.Color=col; t.tracer.Visible=true
        elseif t.tracer then t.tracer.Visible=false end
    end
end)

local hlAccum=0
RunService.Heartbeat:Connect(function(dt)
    if not (anyHighlight or anyCoin or anyGun) then return end
    hlAccum=hlAccum+dt
    if hlAccum<0.2 then return end
    hlAccum=0

    for _,p in ipairs(Players:GetPlayers()) do
        if p==LocalPlayer then continue end
        local role=roleFor(p); local cat=roleToCat(role)
        local wantCH=visOn(cat,"CH"); local wantOL=visOn(cat,"OL"); local wantHL=visOn(cat,"HL"); local wantBX=visOn(cat,"BX")
        local ch=p.Character
        local hl=ESP.highlights[p]
        local sb=ESP.sboxes[p]
        local wantFill=wantCH or wantHL
        local wantEdge=wantOL or wantHL
        if (not ch) or (not (wantFill or wantEdge)) then
            if hl then pcall(function() hl:Destroy() end); ESP.highlights[p]=nil end
        else
            if not hl or hl.Parent~=ch then
                if hl then pcall(function() hl:Destroy() end) end
                hl=Instance.new("Highlight"); hl.Name="LAMBDA_HL"; hl.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop; hl.Parent=ch
                ESP.highlights[p]=hl
            end
            local col=ROLE_COLORS[role] or ROLE_COLORS.Unknown
            hl.FillColor=col; hl.OutlineColor=col
            hl.FillTransparency=wantFill and 0.5 or 1
            hl.OutlineTransparency=wantEdge and 0 or 1
        end
        if (not ch) or (not wantBX) then
            if sb then pcall(function() sb:Destroy() end); ESP.sboxes[p]=nil end
        else
            if not sb or sb.Adornee~=ch then
                if sb then pcall(function() sb:Destroy() end) end
                sb=Instance.new("SelectionBox"); sb.Adornee=ch
                sb.Color3=ROLE_COLORS[role] or ROLE_COLORS.Unknown
                sb.LineThickness=0.05; sb.SurfaceTransparency=1; sb.Parent=ch
                ESP.sboxes[p]=sb
            else
                sb.Color3=ROLE_COLORS[role] or ROLE_COLORS.Unknown
            end
        end
    end

    if anyCoin then
        local wantCH=visOn("Coin","CH"); local wantOL=visOn("Coin","OL"); local wantHL=visOn("Coin","HL"); local wantBX=visOn("Coin","BX")
        local wantFill=wantCH or wantHL; local wantEdge=wantOL or wantHL
        local seen={}
        for _,coin in ipairs(getCoins()) do
            seen[coin]=true
            local hl=ESP.coinHL[coin]; local bx=ESP.coinBX[coin]
            if wantFill or wantEdge then
                if not hl or hl.Parent~=coin then
                    if hl then pcall(function() hl:Destroy() end) end
                    hl=Instance.new("Highlight"); hl.Name="LAMBDA_CoinHL"; hl.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop; hl.Parent=coin
                    ESP.coinHL[coin]=hl
                end
                hl.FillColor=COIN_COL; hl.OutlineColor=COIN_COL
                hl.FillTransparency=wantFill and 0.5 or 1
                hl.OutlineTransparency=wantEdge and 0 or 1
            elseif hl then
                pcall(function() hl:Destroy() end); ESP.coinHL[coin]=nil
            end
            if wantBX then
                if not bx or bx.Adornee~=coin then
                    if bx then pcall(function() bx:Destroy() end) end
                    bx=Instance.new("SelectionBox"); bx.Adornee=coin; bx.Color3=COIN_COL
                    bx.LineThickness=0.06; bx.SurfaceTransparency=1; bx.Parent=coin
                    ESP.coinBX[coin]=bx
                end
            elseif bx then
                pcall(function() bx:Destroy() end); ESP.coinBX[coin]=nil
            end
        end
        for part,hl in pairs(ESP.coinHL) do if not seen[part] or not part.Parent then pcall(function() hl:Destroy() end); ESP.coinHL[part]=nil end end
        for part,bx in pairs(ESP.coinBX) do if not seen[part] or not part.Parent then pcall(function() bx:Destroy() end); ESP.coinBX[part]=nil end end
    else
        for _,hl in pairs(ESP.coinHL) do pcall(function() hl:Destroy() end) end
        for _,bx in pairs(ESP.coinBX) do pcall(function() bx:Destroy() end) end
        ESP.coinHL={}; ESP.coinBX={}
    end

    if anyGun then
        local wantCH=visOn("Gun","CH"); local wantOL=visOn("Gun","OL"); local wantHL=visOn("Gun","HL"); local wantBX=visOn("Gun","BX")
        local wantFill=wantCH or wantHL; local wantEdge=wantOL or wantHL
        local seen={}
        for _,o in ipairs(Workspace:GetChildren()) do
            local isGun=(o:IsA("Tool") or o:IsA("Model")) and (o.Name=="Gun" or o.Name=="Revolver")
            if isGun and not Players:GetPlayerFromCharacter(o.Parent) then
                local handle=o:FindFirstChild("Handle") or (o:IsA("Model") and o.PrimaryPart) or o:FindFirstChildWhichIsA("BasePart")
                if handle then
                    seen[handle]=true
                    local hl=ESP.gunHL[handle]; local bx=ESP.gunBX[handle]
                    if wantFill or wantEdge then
                        if not hl or hl.Parent~=handle then
                            if hl then pcall(function() hl:Destroy() end) end
                            hl=Instance.new("Highlight"); hl.Name="LAMBDA_GunHL"; hl.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop; hl.Parent=handle
                            ESP.gunHL[handle]=hl
                        end
                        hl.FillColor=GUN_COL; hl.OutlineColor=GUN_COL
                        hl.FillTransparency=wantFill and 0.5 or 1
                        hl.OutlineTransparency=wantEdge and 0 or 1
                    elseif hl then
                        pcall(function() hl:Destroy() end); ESP.gunHL[handle]=nil
                    end
                    if wantBX then
                        if not bx or bx.Adornee~=handle then
                            if bx then pcall(function() bx:Destroy() end) end
                            bx=Instance.new("SelectionBox"); bx.Adornee=handle; bx.Color3=GUN_COL
                            bx.LineThickness=0.08; bx.SurfaceTransparency=1; bx.Parent=handle
                            ESP.gunBX[handle]=bx
                        end
                    elseif bx then
                        pcall(function() bx:Destroy() end); ESP.gunBX[handle]=nil
                    end
                end
            end
        end
        for part,hl in pairs(ESP.gunHL) do if not seen[part] or not part.Parent then pcall(function() hl:Destroy() end); ESP.gunHL[part]=nil end end
        for part,bx in pairs(ESP.gunBX) do if not seen[part] or not part.Parent then pcall(function() bx:Destroy() end); ESP.gunBX[part]=nil end end
    else
        for _,hl in pairs(ESP.gunHL) do pcall(function() hl:Destroy() end) end
        for _,bx in pairs(ESP.gunBX) do pcall(function() bx:Destroy() end) end
        ESP.gunHL={}; ESP.gunBX={}
    end
end)

Players.PlayerRemoving:Connect(function(p)
    if ESP.draws[p] then for _,d in pairs(ESP.draws[p]) do pcall(function() d:Remove() end) end; ESP.draws[p]=nil end
    if ESP.smooth[p] then ESP.smooth[p]=nil end
    if ESP.highlights[p] then pcall(function() ESP.highlights[p]:Destroy() end); ESP.highlights[p]=nil end
    if ESP.sboxes[p] then pcall(function() ESP.sboxes[p]:Destroy() end); ESP.sboxes[p]=nil end
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
local REBUILD_TOKEN=0
local function scheduleRebuild()
    REBUILD_TOKEN=REBUILD_TOKEN+1
    local myToken=REBUILD_TOKEN
    task.delay(0.3,function()
        if REBUILD_TOKEN==myToken then buildGui() end
    end)
end

local PRESETS={
    Color3.fromRGB(255,0,0),Color3.fromRGB(255,100,0),Color3.fromRGB(255,200,0),Color3.fromRGB(180,255,0),
    Color3.fromRGB(0,255,0),Color3.fromRGB(0,255,180),Color3.fromRGB(0,255,255),Color3.fromRGB(0,180,255),
    Color3.fromRGB(0,100,255),Color3.fromRGB(0,0,255),Color3.fromRGB(100,0,255),Color3.fromRGB(180,0,255),
    Color3.fromRGB(255,0,255),Color3.fromRGB(255,0,180),Color3.fromRGB(255,0,100),
    Color3.fromRGB(255,255,255),Color3.fromRGB(200,200,200),Color3.fromRGB(128,128,128),
    Color3.fromRGB(64,64,64),Color3.fromRGB(30,30,30),Color3.fromRGB(0,0,0),
    Color3.fromRGB(150,75,0),Color3.fromRGB(255,180,150),Color3.fromRGB(80,40,20),
}
local THEMES={
    {name="Gold", p=Color3.fromRGB(255,200,0), s=Color3.fromRGB(30,30,30)},
    {name="Ocean", p=Color3.fromRGB(0,180,255), s=Color3.fromRGB(20,30,45)},
    {name="Forest", p=Color3.fromRGB(80,200,80), s=Color3.fromRGB(20,30,20)},
    {name="Rose", p=Color3.fromRGB(255,100,150), s=Color3.fromRGB(40,20,30)},
    {name="Cyber", p=Color3.fromRGB(255,0,180), s=Color3.fromRGB(15,15,40)},
    {name="Mono", p=Color3.fromRGB(220,220,220), s=Color3.fromRGB(25,25,25)},
}

function buildGui()
    if MAIN_GUI then pcall(function() MAIN_GUI:Destroy() end) end
    local parent=guiParent(); if not parent then return end
    local gui=Instance.new("ScreenGui")
    gui.Name="LambdaHub"; gui.ResetOnSpawn=false; gui.IgnoreGuiInset=true; gui.DisplayOrder=999999
    pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)
    gui.Parent=parent; MAIN_GUI=gui

    local main=Instance.new("Frame")
    main.Size=UDim2.new(0,380,0,510); main.Position=UDim2.new(0,30,0,30)
    main.BackgroundColor3=SECONDARY; main.BorderSizePixel=0; main.Active=true; main.Draggable=true; main.Parent=gui

    local titleBar=Instance.new("Frame")
    titleBar.Size=UDim2.new(1,0,0,28); titleBar.BackgroundColor3=SECONDARY; titleBar.BorderSizePixel=0; titleBar.Parent=main

    local title=Instance.new("TextLabel")
    title.Size=UDim2.new(1,-80,1,0); title.Position=UDim2.new(0,10,0,0)
    title.BackgroundTransparency=1; title.Text="Lambda Hub | v0.26"
    title.TextColor3=PRIMARY; title.Font=Enum.Font.GothamBold; title.TextSize=13
    title.TextXAlignment=Enum.TextXAlignment.Left; title.Parent=titleBar

    local min=Instance.new("TextButton")
    min.Size=UDim2.new(0,24,0,20); min.Position=UDim2.new(1,-56,0,4)
    min.BackgroundColor3=Color3.fromRGB(70,70,70); min.Text="—"; min.TextColor3=Color3.fromRGB(255,255,255)
    min.Font=Enum.Font.GothamBold; min.TextSize=13; min.Parent=titleBar
    local close=Instance.new("TextButton")
    close.Size=UDim2.new(0,24,0,20); close.Position=UDim2.new(1,-28,0,4)
    close.BackgroundColor3=Color3.fromRGB(120,30,30); close.Text="X"; close.TextColor3=Color3.fromRGB(255,255,255)
    close.Font=Enum.Font.GothamBold; close.TextSize=13; close.Parent=titleBar

    local collapsed=false
    min.MouseButton1Click:Connect(function()
        collapsed=not collapsed
        main.Size=collapsed and UDim2.new(0,380,0,28) or UDim2.new(0,380,0,510)
        min.Text=collapsed and "+" or "—"
    end)
    close.MouseButton1Click:Connect(function()
        for _,d in pairs(ESP.highlights) do pcall(function() d:Destroy() end) end
        for _,d in pairs(ESP.sboxes) do pcall(function() d:Destroy() end) end
        for _,d in pairs(ESP.coinHL) do pcall(function() d:Destroy() end) end
        for _,d in pairs(ESP.coinBX) do pcall(function() d:Destroy() end) end
        for _,d in pairs(ESP.gunHL) do pcall(function() d:Destroy() end) end
        for _,d in pairs(ESP.gunBX) do pcall(function() d:Destroy() end) end
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
    local function newTab(name,wPct)
        local b=Instance.new("TextButton")
        b.Size=UDim2.new(wPct,0,1,0); b.BackgroundColor3=SECONDARY
        b.Text=name; b.TextColor3=TEXT_DIM; b.Font=Enum.Font.GothamBold; b.TextSize=11; b.Parent=tabBar
        local f=Instance.new("ScrollingFrame")
        f.Size=UDim2.new(1,0,1,0); f.BackgroundTransparency=1; f.ScrollBarThickness=4
        f.CanvasSize=UDim2.new(0,0,0,0); f.Visible=false; f.Parent=content
        local l=Instance.new("UIListLayout"); l.Padding=UDim.new(0,4); l.SortOrder=Enum.SortOrder.LayoutOrder; l.Parent=f
        local p=Instance.new("UIPadding"); p.PaddingTop=UDim.new(0,8); p.PaddingLeft=UDim.new(0,8); p.PaddingRight=UDim.new(0,8); p.Parent=f
        tabs[name]={btn=b,frame=f,list=l}
        l:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            f.CanvasSize=UDim2.new(0,0,0,l.AbsoluteContentSize.Y+16)
        end)
        b.MouseButton1Click:Connect(function()
            for _,t in pairs(tabs) do t.frame.Visible=false; t.btn.BackgroundColor3=SECONDARY; t.btn.TextColor3=TEXT_DIM end
            f.Visible=true; b.BackgroundColor3=PRIMARY; b.TextColor3=Color3.fromRGB(0,0,0)
        end)
        return f
    end

    local mainTab=newTab("Main",1/7)
    local actionsTab=newTab("Actions",1/7)
    local protectTab=newTab("Protect",1/7)
    local visualsTab=newTab("Visuals",1/7)
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
        local row=Instance.new("Frame"); row.Size=UDim2.new(1,0,0,26); row.BackgroundTransparency=1; row.LayoutOrder=ord; row.Parent=par
        local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,-60,1,0); l.BackgroundTransparency=1
        l.Text=txt; l.TextColor3=TEXT_BRIGHT; l.Font=Enum.Font.Gotham; l.TextSize=12; l.TextXAlignment=Enum.TextXAlignment.Left; l.Parent=row
        local b=Instance.new("TextButton"); b.Size=UDim2.new(0,48,0,20); b.Position=UDim2.new(1,-52,0.5,-10)
        b.BackgroundColor3=init and PRIMARY or Color3.fromRGB(55,55,55); b.Text=init and "ON" or "OFF"
        b.TextColor3=init and Color3.fromRGB(0,0,0) or Color3.fromRGB(255,255,255)
        b.Font=Enum.Font.GothamBold; b.TextSize=10; b.Parent=row
        local st=init
        b.MouseButton1Click:Connect(function()
            st=not st; b.BackgroundColor3=st and PRIMARY or Color3.fromRGB(55,55,55)
            b.Text=st and "ON" or "OFF"; b.TextColor3=st and Color3.fromRGB(0,0,0) or Color3.fromRGB(255,255,255)
            pcall(function() cb(st) end); save()
        end)
    end
    local function inp(par,label,val,ord,cb)
        local row=Instance.new("Frame"); row.Size=UDim2.new(1,0,0,24); row.BackgroundTransparency=1; row.LayoutOrder=ord; row.Parent=par
        local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,-80,1,0); l.BackgroundTransparency=1
        l.Text=label; l.TextColor3=TEXT_BRIGHT; l.Font=Enum.Font.Gotham; l.TextSize=11; l.TextXAlignment=Enum.TextXAlignment.Left; l.Parent=row
        local b=Instance.new("TextBox"); b.Size=UDim2.new(0,72,0,20); b.Position=UDim2.new(1,-76,0.5,-10)
        b.BackgroundColor3=Color3.fromRGB(45,45,45); b.TextColor3=Color3.fromRGB(255,255,255); b.Text=tostring(val)
        b.Font=Enum.Font.Gotham; b.TextSize=11; b.Parent=row
        b.FocusLost:Connect(function() pcall(function() cb(b.Text) end); save() end)
    end
    local function cyc(par,label,opts,init,ord,cb)
        local row=Instance.new("Frame"); row.Size=UDim2.new(1,0,0,26); row.BackgroundTransparency=1; row.LayoutOrder=ord; row.Parent=par
        local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,-130,1,0); l.BackgroundTransparency=1
        l.Text=label; l.TextColor3=TEXT_BRIGHT; l.Font=Enum.Font.Gotham; l.TextSize=11; l.TextXAlignment=Enum.TextXAlignment.Left; l.Parent=row
        local b=Instance.new("TextButton"); b.Size=UDim2.new(0,120,0,20); b.Position=UDim2.new(1,-124,0.5,-10)
        b.BackgroundColor3=Color3.fromRGB(55,55,55); b.TextColor3=Color3.fromRGB(255,255,255); b.Font=Enum.Font.Gotham; b.TextSize=11; b.Parent=row
        local i=findIdx(opts,init); b.Text=opts[i]
        b.MouseButton1Click:Connect(function() i=i%#opts+1; b.Text=opts[i]; pcall(function() cb(opts[i]) end); save() end)
    end
    local function btn(par,label,bgColor,textColor,ord,cb)
        local b=Instance.new("TextButton")
        b.Size=UDim2.new(1,0,0,28); b.BackgroundColor3=bgColor; b.Text=label
        b.TextColor3=textColor; b.Font=Enum.Font.GothamBold; b.TextSize=11
        b.LayoutOrder=ord; b.Parent=par
        b.MouseButton1Click:Connect(cb)
        return b
    end
    local function visualRow(par,dispName,cat,features,ord)
        local row=Instance.new("Frame")
        row.Size=UDim2.new(1,0,0,26); row.BackgroundTransparency=1; row.LayoutOrder=ord; row.Parent=par
        local l=Instance.new("TextLabel")
        l.Size=UDim2.new(0,55,1,0); l.BackgroundTransparency=1
        l.Text=dispName; l.TextColor3=TEXT_BRIGHT; l.Font=Enum.Font.Gotham; l.TextSize=11
        l.TextXAlignment=Enum.TextXAlignment.Left; l.Parent=row
        local xPos=60
        for _,feat in ipairs(features) do
            local key="Visuals_"..feat.."_"..cat
            if C[key]==nil then C[key]=false end
            local state=C[key]
            local b=Instance.new("TextButton")
            b.Size=UDim2.new(0,40,0,20); b.Position=UDim2.new(0,xPos,0.5,-10)
            b.BackgroundColor3=state and PRIMARY or Color3.fromRGB(55,55,55)
            b.Text=feat; b.TextColor3=state and Color3.fromRGB(0,0,0) or Color3.fromRGB(255,255,255)
            b.Font=Enum.Font.GothamBold; b.TextSize=9; b.Parent=row
            b.MouseButton1Click:Connect(function()
                C[key]=not C[key]
                b.BackgroundColor3=C[key] and PRIMARY or Color3.fromRGB(55,55,55)
                b.TextColor3=C[key] and Color3.fromRGB(0,0,0) or Color3.fromRGB(255,255,255)
                rebuildVisualCache(); save()
            end)
            xPos=xPos+42
        end
    end

    local o=0
    local function no() o=o+1; return o end

    tog(mainTab,"AUTO FARM",C.Farming,no(),function(s) if s then farm() else stopFarm() end end)
    tog(mainTab,"Auto-launch on exec",C.AutoLaunch,no(),function(s) C.AutoLaunch=s end)
    lbl(mainTab,"— Currency —",no())
    cyc(mainTab,"Target",{"Coin","Candy","SnowToken","Token","Shell"},C.Currency,no(),function(v) C.Currency=v end)
    lbl(mainTab,"— Movement —",no())
    inp(mainTab,"Speed (studs/s)",C.Speed,no(),function(v) local n=tonumber(v); if n then C.Speed=math.clamp(n,10,70) end end)
    cyc(mainTab,"Farm mode",{"Stealth","Standard","Lay"},C.FarmMode,no(),function(v) C.FarmMode=v end)
    inp(mainTab,"Stealth depth (3=default)",C.Depth,no(),function(v) local n=tonumber(v); if n then C.Depth=math.clamp(n,1,30) end end)
    inp(mainTab,"Aura radius",C.AuraRadius,no(),function(v) local n=tonumber(v); if n then C.AuraRadius=math.clamp(n,5,40) end end)
    lbl(mainTab,"— Bag —",no())
    inp(mainTab,"Threshold (50=default)",C.Threshold,no(),function(v) local n=tonumber(v); if n then C.Threshold=math.max(0,n) end end)
    local stats=Instance.new("TextLabel")
    stats.Size=UDim2.new(1,0,0,72); stats.BackgroundColor3=Color3.fromRGB(30,28,0); stats.BorderSizePixel=0
    stats.TextColor3=PRIMARY; stats.Font=Enum.Font.Code; stats.TextSize=10
    stats.Text="Collected: 0\nPer hour: 0\nBag: ?/50\nFails: 0\nStatus: idle"
    stats.LayoutOrder=no(); stats.Parent=mainTab
    task.spawn(function()
        while stats.Parent do
            task.wait(0.5)
            local b=statValue()
            stats.Text=string.format("Collected: %d\nPer hour: %d\nBag: %s/%d\nFails: %d\nStatus: %s",
                C.Stats.Total,rate(),b and tostring(b) or "?",threshold(),C.CollectFails,C.FarmStatus or "idle")
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
    tog(protectTab,"Anti-Murderer (passive)",C.AntiMurderer,no(),function(s) C.AntiMurderer=s end)
    tog(protectTab,"Noclip",C.Noclip,no(),function(s) C.Noclip=s; if s then startNoclip() else stopNoclip() end end)
    tog(protectTab,"Disable 3D",C.Disable3D,no(),function(s) C.Disable3D=s; pcall(function() RunService:Set3dRenderingEnabled(not s) end) end)

    o=0
    lbl(visualsTab,"— Players —",no())
    lbl(visualsTab,"Category      ESP  TR   CH   OL   HL   BX",no())
    visualRow(visualsTab,"Murd","Murderer",{"ESP","TR","CH","OL","HL","BX"},no())
    visualRow(visualsTab,"Sher","Sheriff",{"ESP","TR","CH","OL","HL","BX"},no())
    visualRow(visualsTab,"Hero","Hero",{"ESP","TR","CH","OL","HL","BX"},no())
    visualRow(visualsTab,"Inno","Innocent",{"ESP","TR","CH","OL","HL","BX"},no())
    lbl(visualsTab,"— Objects —",no())
    lbl(visualsTab,"Category      ESP  TR   CH   OL   HL   BX",no())
    visualRow(visualsTab,"Coin","Coin",{"BX","CH","OL","HL"},no())
    visualRow(visualsTab,"Gun","Gun",{"BX","CH","OL","HL"},no())

    o=0
    tog(serverTab,"Auto-rejoin on kick",C.AutoRejoin,no(),function(s) C.AutoRejoin=s end)
    inp(serverTab,"Hop if players >",C.HopAt,no(),function(v) local n=tonumber(v); if n then C.HopAt=n end end)
    tog(serverTab,"Hop when friend joins",C.HopFriend,no(),function(s) C.HopFriend=s; if s then friendMonitor() end end)
    btn(serverTab,"HOP NOW (change server)",PRIMARY,Color3.fromRGB(0,0,0),no(),function() hopNow() end)
    btn(serverTab,"REJOIN NOW (recover manually)",Color3.fromRGB(80,80,80),Color3.fromRGB(255,255,255),no(),function() safeRejoin("manual") end)
    local hopLbl=Instance.new("TextLabel")
    hopLbl.Size=UDim2.new(1,0,0,36); hopLbl.BackgroundColor3=Color3.fromRGB(28,28,28); hopLbl.BorderSizePixel=0
    hopLbl.TextColor3=PRIMARY; hopLbl.Font=Enum.Font.Code; hopLbl.TextSize=10
    hopLbl.Text="Status: idle"; hopLbl.LayoutOrder=no(); hopLbl.Parent=serverTab
    task.spawn(function()
        while hopLbl.Parent do
            task.wait(0.5)
            local s="Status: "..(C.HopStatus~="" and C.HopStatus or "idle")
            if C.LastKickReason~="" then s=s.."\nLast kick: "..C.LastKickReason end
            hopLbl.Text=s
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
    lbl(themeTab,"— Themes —",no())
    local themeRow=Instance.new("Frame")
    themeRow.Size=UDim2.new(1,0,0,28); themeRow.BackgroundTransparency=1; themeRow.LayoutOrder=no(); themeRow.Parent=themeTab
    local themeLay=Instance.new("UIListLayout")
    themeLay.FillDirection=Enum.FillDirection.Horizontal; themeLay.Padding=UDim.new(0,4); themeLay.Parent=themeRow
    for _,theme in ipairs(THEMES) do
        local tb=Instance.new("TextButton")
        tb.Size=UDim2.new(0,54,1,0); tb.BackgroundColor3=theme.p
        tb.Text=theme.name; tb.TextColor3=Color3.fromRGB(0,0,0)
        tb.Font=Enum.Font.GothamBold; tb.TextSize=9; tb.Parent=themeRow
        tb.MouseButton1Click:Connect(function()
            C.PrimaryColor=colorToHex(theme.p); C.SecondaryColor=colorToHex(theme.s)
            PRIMARY=theme.p; SECONDARY=theme.s
            save(); buildGui()
        end)
    end
    lbl(themeTab,"— Primary Color —",no())
    local pPrev=Instance.new("Frame")
    pPrev.Size=UDim2.new(1,0,0,24); pPrev.BackgroundColor3=PRIMARY; pPrev.BorderSizePixel=0
    pPrev.LayoutOrder=no(); pPrev.Parent=themeTab
    local pHue=Instance.new("Frame")
    pHue.Size=UDim2.new(1,0,0,18); pHue.BackgroundColor3=Color3.new(1,1,1); pHue.BorderSizePixel=0
    pHue.LayoutOrder=no(); pHue.Parent=themeTab
    local pHueGrad=Instance.new("UIGradient")
    pHueGrad.Color=ColorSequence.new({
        ColorSequenceKeypoint.new(0,Color3.fromRGB(255,0,0)),
        ColorSequenceKeypoint.new(1/6,Color3.fromRGB(255,255,0)),
        ColorSequenceKeypoint.new(2/6,Color3.fromRGB(0,255,0)),
        ColorSequenceKeypoint.new(3/6,Color3.fromRGB(0,255,255)),
        ColorSequenceKeypoint.new(4/6,Color3.fromRGB(0,0,255)),
        ColorSequenceKeypoint.new(5/6,Color3.fromRGB(255,0,255)),
        ColorSequenceKeypoint.new(1,Color3.fromRGB(255,0,0)),
    })
    pHueGrad.Parent=pHue
    pHue.InputBegan:Connect(function(input)
        if input.UserInputType~=Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.Touch then return end
        local rel=(input.Position.X-pHue.AbsolutePosition.X)/pHue.AbsoluteSize.X
        rel=math.clamp(rel,0,1)
        local c=Color3.fromHSV(rel,0.85,1)
        C.PrimaryColor=colorToHex(c); PRIMARY=c
        pPrev.BackgroundColor3=c
        save(); scheduleRebuild()
    end)
    local pGrid=Instance.new("Frame")
    pGrid.Size=UDim2.new(1,0,0,84); pGrid.BackgroundTransparency=1
    pGrid.LayoutOrder=no(); pGrid.Parent=themeTab
    local pGridLay=Instance.new("UIGridLayout")
    pGridLay.CellSize=UDim2.new(0,20,0,20); pGridLay.CellPadding=UDim2.new(0,2,0,2); pGridLay.Parent=pGrid
    for _,c in ipairs(PRESETS) do
        local sw=Instance.new("TextButton")
        sw.BackgroundColor3=c; sw.Text=""; sw.BorderSizePixel=0; sw.Parent=pGrid
        sw.MouseButton1Click:Connect(function()
            C.PrimaryColor=colorToHex(c); PRIMARY=c
            pPrev.BackgroundColor3=c
            save(); scheduleRebuild()
        end)
    end
    lbl(themeTab,"— Secondary Color —",no())
    local sPrev=Instance.new("Frame")
    sPrev.Size=UDim2.new(1,0,0,24); sPrev.BackgroundColor3=SECONDARY; sPrev.BorderSizePixel=0
    sPrev.LayoutOrder=no(); sPrev.Parent=themeTab
    local sHue=Instance.new("Frame")
    sHue.Size=UDim2.new(1,0,0,18); sHue.BackgroundColor3=Color3.new(1,1,1); sHue.BorderSizePixel=0
    sHue.LayoutOrder=no(); sHue.Parent=themeTab
    local sHueGrad=pHueGrad:Clone(); sHueGrad.Parent=sHue
    sHue.InputBegan:Connect(function(input)
        if input.UserInputType~=Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.Touch then return end
        local rel=(input.Position.X-sHue.AbsolutePosition.X)/sHue.AbsoluteSize.X
        rel=math.clamp(rel,0,1)
        local c=Color3.fromHSV(rel,0.6,0.25)
        C.SecondaryColor=colorToHex(c); SECONDARY=c
        sPrev.BackgroundColor3=c
        save(); scheduleRebuild()
    end)
    local sGrid=Instance.new("Frame")
    sGrid.Size=UDim2.new(1,0,0,84); sGrid.BackgroundTransparency=1
    sGrid.LayoutOrder=no(); sGrid.Parent=themeTab
    local sGridLay=Instance.new("UIGridLayout")
    sGridLay.CellSize=UDim2.new(0,20,0,20); sGridLay.CellPadding=UDim2.new(0,2,0,2); sGridLay.Parent=sGrid
    for _,c in ipairs(PRESETS) do
        local sw=Instance.new("TextButton")
        sw.BackgroundColor3=c; sw.Text=""; sw.BorderSizePixel=0; sw.Parent=sGrid
        sw.MouseButton1Click:Connect(function()
            C.SecondaryColor=colorToHex(c); SECONDARY=c
            sPrev.BackgroundColor3=c
            save(); scheduleRebuild()
        end)
    end
    btn(themeTab,"APPLY / REBUILD GUI",PRIMARY,Color3.fromRGB(0,0,0),no(),function() buildGui() end)

    tabs["Main"].btn.MouseButton1Click:Fire()
end

-- ============ Mobile picker dismiss ============
local function dismissMobilePicker()
    if not UIS.TouchEnabled then return end
    local cam=workspace.CurrentCamera
    local vp=cam and cam.ViewportSize or Vector2.new(800,600)
    for _=1,3 do
        pcall(function()
            VirtualInputManager:SendMouseButtonEvent(vp.X/2,vp.Y/2,0,true,game,0)
            task.wait(0.08)
            VirtualInputManager:SendMouseButtonEvent(vp.X/2,vp.Y/2,0,false,game,0)
        end)
        task.wait(0.5)
    end
    pcall(function()
        VirtualInputManager:SendKeyEvent(true,Enum.KeyCode.Return,false,game)
        task.wait(0.1)
        VirtualInputManager:SendKeyEvent(false,Enum.KeyCode.Return,false,game)
    end)
end

-- ============ INIT ============
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
if C.Noclip then startNoclip() end
if C.HopAt>0 then hopMonitor() end
if C.HopFriend then friendMonitor() end
if C.Disable3D then pcall(function() RunService:Set3dRenderingEnabled(false) end) end

buildGui()

task.spawn(function()
    if not C.AutoLaunch then return end
    task.wait(2); dismissMobilePicker(); task.wait(2)
    if not HUM() then pcall(function() LocalPlayer.CharacterAdded:Wait() end); task.wait(2) end
    local tries=0
    while tries<30 do
        if isDeadOrOutOfRound() then task.wait(1); tries=tries+1 else break end
    end
    if C.AutoLaunch and not C.Farming then farm() end
end)

print("[Lambda] v0.26 ready | HWID: "..HWID)
if C.Depth > 5 then
    print("[Lambda] Note: depth="..C.Depth.." (saved). Para aura ótima, mude o slider para 3.")
end
