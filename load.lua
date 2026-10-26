-- Lambda Hub | v0.32 | By kerli
-- Polished GUI | Fixed Autofarm | Fixed Server Hop | Auto-Start

print("[Lambda] v0.32 loading")

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local VirtualUser = game:GetService("VirtualUser")
local VirtualInputManager = game:GetService("VirtualInputManager")
local UIS = game:GetService("UserInputService")
local Stats = game:GetService("Stats")
local LocalPlayer = Players.LocalPlayer

-- ============ HWID + PREFS ============
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
    Currency="Coin", Speed=35, FarmMode="Stealth", Depth=3, AuraRadius=12, CoinAura=true,
    HopAt=6, HopFriend=false, AutoLaunch=true, AutoGrabGun=true,
    Farming=false,
    AntiAFK=true, AntiVoid=true, AntiFling=true, Noclip=true, AntiMurderer=false,
    Disable3D=false, VoteMode=0, VoteMax=0,
    ResetInnocent=true, FlingMurderer=false, ShootSheriff=true, ResetAnyRole=false,
    KillMurderer=true, ResetMurderer=false, Threshold=50, ResetAfterAction=true,
    PredMultiplier=1.0,
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
if C.Depth and C.Depth > 8 then C.Depth = 3 end
if C.AuraRadius and C.AuraRadius < 5 then C.AuraRadius = 12 end

C.FarmThread=nil
C.HopThread=nil; C.FriendThread=nil; C.VoteThread=nil
C.LastFull=tick(); C.Cooldown=0; C.HopStatus=""; C.LastKickReason=""
C.IsHopping=false; C.IsTeleporting=false; C.IntentionalReset=false
C.Stats={Total=0, Start=tick(), Last=0}
C.MissCount=0; C.WasInRound=false
C.CollectFails=0
C.LastGunGrab=0
C.FlingTarget=nil
C.FarmStatus="idle"

local function save() local t={} for k,_ in pairs(DEFAULTS) do t[k]=C[k] end prefsSave(t) end

-- ============ COLORS ============
local function parseHex(s)
    s=tostring(s or ""):gsub("#","")
    if #s~=6 then return nil end
    local n=tonumber(s,16); if not n then return nil end
    return Color3.fromRGB(bit32.rshift(bit32.band(n,0xFF0000),16), bit32.rshift(bit32.band(n,0x00FF00),8), bit32.band(n,0x0000FF))
end
local function colorToHex(c) return string.format("#%02X%02X%02X", math.floor(c.R*255+.5), math.floor(c.G*255+.5), math.floor(c.B*255+.5)) end
local PRIMARY = parseHex(C.PrimaryColor) or Color3.fromRGB(255,200,0)
local SECONDARY = parseHex(C.SecondaryColor) or Color3.fromRGB(30,30,30)
local TEXT_DIM = Color3.fromRGB(150,150,150); local TEXT_BRIGHT = Color3.fromRGB(220,220,220)
local function HRP() local c=LocalPlayer.Character; return c and c:FindFirstChild("HumanoidRootPart") end
local function HUM() local c=LocalPlayer.Character; return c and c:FindFirstChildOfClass("Humanoid") end

-- ============ GetPlayerData ============
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
    if d then local me=d[LocalPlayer.Name]
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
local function findRole(roleName)
    local d=PD(); if not d then return nil end
    for n,i in pairs(d) do
        if i.Role==roleName and not i.Killed and not i.Dead then
            local p=Players:FindFirstChild(n)
            if p and p~=LocalPlayer then return p end
        end
    end
    return nil
end
local function murdererNearby(r)
    r=r or 40
    local m=findMurderer(); if not m or not m.Character then return false end
    local mh=m.Character:FindFirstChild("HumanoidRootPart"); local myh=HRP()
    if not mh or not myh then return false end
    return (mh.Position-myh.Position).Magnitude<=r
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

-- Anti-AFK
local afkConn
local function startAFK()
    if afkConn then afkConn:Disconnect() end
    afkConn=LocalPlayer.Idled:Connect(function()
        pcall(function() VirtualUser:CaptureController(); VirtualUser:ClickButton2(Vector2.new(0,0)) end)
    end)
end

-- Anti-Void
local voidConn; local origDH=Workspace.FallenPartsDestroyHeight
local function setupVoid()
    if not C.AntiVoid then Workspace.FallenPartsDestroyHeight=origDH; if voidConn then voidConn:Disconnect(); voidConn=nil end; return end
    Workspace.FallenPartsDestroyHeight=0/0
    if voidConn then voidConn:Disconnect() end
    voidConn=LocalPlayer.CharacterAdded:Connect(function() task.wait(0.1); Workspace.FallenPartsDestroyHeight=0/0 end)
end

-- Anti-Fling
local function startAntiFling()
    local lastP,lastT=nil,tick(); local lastC=nil
    RunService.Heartbeat:Connect(function()
        if not C.AntiFling then return end
        local ch=LocalPlayer.Character
        if not ch then lastC=nil; lastP=nil; return end
        if ch~=lastC then lastC=ch; lastP=nil; lastT=tick(); return end
        local h=ch:FindFirstChild("HumanoidRootPart"); local u=ch:FindFirstChildOfClass("Humanoid")
        if not h or not u or u.Health<=0 or h.Anchored then lastP=nil; return end
        local now=tick()
        if lastP and now-lastT>0.1 then
            local d=(h.Position-lastP).Magnitude; local s=d/(now-lastT)
            if s>150 and d<30 then
                h.AssemblyLinearVelocity=Vector3.zero; h.AssemblyAngularVelocity=Vector3.zero
                h.CFrame=CFrame.new(lastP)*h.CFrame.Rotation
            end
        end
        lastP=h.Position; lastT=now
    end)
end

-- Noclip
local noclipConn
local function startNoclip()
    if noclipConn then noclipConn:Disconnect() end
    noclipConn=RunService.Stepped:Connect(function()
        if not C.Noclip then return end
        local ch=LocalPlayer.Character; if not ch then return end
        for _,p in ipairs(ch:GetDescendants()) do if p:IsA("BasePart") and p.CanCollide then p.CanCollide=false end end
    end)
end
local function stopNoclip() if noclipConn then noclipConn:Disconnect(); noclipConn=nil end end

-- ============ BAG ============
local EVENT_CURR={Candy=true,SnowToken=true,Token=true,Shell=true,Egg=true,Present=true,Gift=true,Gem=true}
local function threshold() if C.Threshold>0 then return C.Threshold end return EVENT_CURR[C.Currency] and 50 or 40 end
local CURRENCY_FIELDS = {
    Coin={"Coins","Coin","coins","coin"}, Candy={"Candy","Candies","candy","candies"},
    SnowToken={"SnowToken","SnowTokens","Snow Tokens"}, Token={"Token","Tokens"}, Shell={"Shell","Shells"},
}
local PATTERNS={"coin","cand","token","shell","egg","present","gift","gem","snow"}

local function getVal(ch)
    if not ch then return nil end
    local ok,v=pcall(function() return ch.Value end)
    if not ok then return nil end
    if type(v)=="number" then return v end
    if type(v)=="string" then local n=tonumber(v); if n then return n end end
    return nil
end

local function statValue()
    local ls=LocalPlayer:FindFirstChild("leaderstats") or LocalPlayer:FindFirstChild("Stats")
    if ls then
        local fields=CURRENCY_FIELDS[C.Currency] or {C.Currency}
        for _,fn in ipairs(fields) do local v=getVal(ls:FindFirstChild(fn)); if v then return v end end
        local cn=C.Currency:lower(); local sh=cn:sub(1,4)
        for _,ch in ipairs(ls:GetChildren()) do
            local n=ch.Name:lower()
            if n:find(cn,1,true) or (sh~="" and n:find(sh,1,true)) then local v=getVal(ch); if v then return v end end
        end
        for _,ch in ipairs(ls:GetChildren()) do
            local n=ch.Name:lower()
            for _,p in ipairs(PATTERNS) do if n:find(p,1,true) then local v=getVal(ch); if v then return v end end end
        end
    end
    local attrs=LocalPlayer:GetAttributes(); local cn=C.Currency:lower()
    for k,v in pairs(attrs) do
        if type(v)=="number" then local n=tostring(k):lower(); if n:find(cn,1,true) or n:find(cn:sub(1,4),1,true) then return v end end
    end
    local d=PD()
    if d and d[LocalPlayer.Name] then
        local me=d[LocalPlayer.Name]; local fields=CURRENCY_FIELDS[C.Currency] or {C.Currency}
        for _,fn in ipairs(fields) do if type(me[fn])=="number" then return me[fn] end end
        for k,v in pairs(me) do if type(v)=="number" and v>=0 and v<=500 then
            local n=tostring(k):lower()
            for _,p in ipairs(PATTERNS) do if n:find(p,1,true) then return v end end
        end end
    end
    return nil
end

-- ============ COINS ============
local coinCache={parts={},ts=0}
local coinBlacklist={}
local function isBlacklisted(c) local t=coinBlacklist[c]; if not t then return false end; if tick()-t>5 then coinBlacklist[c]=nil; return false end; return true end
local function blacklist(c) if c then coinBlacklist[c]=tick() end; for k,v in pairs(coinBlacklist) do if tick()-v>5 then coinBlacklist[k]=nil end end end
local function removeCoinFromCache(coin)
    for i, p in ipairs(coinCache.parts) do
        if p == coin then
            table.remove(coinCache.parts, i)
            break
        end
    end
    blacklist(coin)
end

local function getContainers()
    local list={}
    for _,o in ipairs(Workspace:GetChildren()) do
        for _,n in ipairs({"CoinContainer","CandyContainer","TokenContainer","Collectables"}) do local c=o:FindFirstChild(n); if c then table.insert(list,c) end end
        local m=o:FindFirstChild("Map")
        if m then for _,n in ipairs({"CoinContainer","CandyContainer","TokenContainer","Collectables"}) do local c=m:FindFirstChild(n); if c then table.insert(list,c) end end end
    end
    return list
end
local function getCoins()
    if tick()-coinCache.ts<0.4 then
        local alive={}; for _,p in ipairs(coinCache.parts) do if p.Parent then table.insert(alive,p) end end; coinCache.parts=alive; return alive
    end
    local parts={}
    for _,c in ipairs(getContainers()) do for _,d in ipairs(c:GetDescendants()) do if d:IsA("BasePart") and d:FindFirstChildWhichIsA("TouchTransmitter") then table.insert(parts,d) end end end
    coinCache.parts=parts; coinCache.ts=tick(); return parts
end
local function nearestCoin()
    local h=HRP(); if not h then return nil end
    local best,bd=nil,math.huge
    for _,p in ipairs(getCoins()) do if not isBlacklisted(p) then local d=(h.Position-p.Position).Magnitude; if d<bd then bd=d; best=p end end end
    return best
end

-- ============ MOVEMENT ============
local LAY=CFrame.Angles(math.rad(90),0,0); local UPRIGHT=CFrame.new()
local function travel(targetPos, rot90, spd, coinRef)
    local h=HRP(); if not h then return false end
    if not h.Anchored then h.Anchored=true end
    local u=HUM(); if u and not u.PlatformStand then u.PlatformStand=true; u.AutoRotate=false end
    spd=math.clamp(spd or C.Speed,10,70)
    local rot = rot90 and LAY or UPRIGHT
    local lastT=tick(); local startT=tick(); local lastDist=math.huge; local lastProgress=tick()
    while C.Farming do
        if tick()-startT>15 then return false end
        if isDeadOrOutOfRound() then return false end
        local cur=HRP(); if not cur or not cur.Anchored then return false end
        if coinRef and not coinRef.Parent then return false end
        if cur.Position.Y<-150 or cur.Position.Y>10000 then return false end
        local delta=targetPos-cur.Position; local dist=delta.Magnitude
        if dist<2.5 then cur.CFrame=CFrame.new(targetPos)*rot; return true end
        if dist<lastDist-1 then lastProgress=tick(); lastDist=dist elseif tick()-lastProgress>3 then return false end
        local now=tick(); local dt=math.min(now-lastT,0.05); lastT=now
        local step=math.min(spd*dt,dist); cur.CFrame=CFrame.new(cur.Position+delta.Unit*step)*rot
        task.wait()
    end
    return false
end

local function unanchorForTouch(ragdoll)
    local h=HRP(); local u=HUM(); if not h or not u then return nil,nil,nil,nil end
    local wasA=h.Anchored; if wasA then h.Anchored=false end
    u.PlatformStand = ragdoll and true or false
    local bv=Instance.new("BodyVelocity"); bv.MaxForce=Vector3.new(math.huge,math.huge,math.huge); bv.Velocity=Vector3.zero; bv.P=1000000; bv.Parent=h
    local bg=nil
    if ragdoll then bg=Instance.new("BodyGyro"); bg.MaxTorque=Vector3.new(math.huge,math.huge,math.huge); bg.P=1000000; bg.CFrame=h.CFrame; bg.Parent=h end
    return bv,bg,wasA,u
end
local function reanchorAfterTouch(bv,bg,wasA,u)
    if bv and bv.Parent then pcall(function() bv:Destroy() end) end
    if bg and bg.Parent then pcall(function() bg:Destroy() end) end
    local h=HRP(); if h and h.Parent then h.AssemblyLinearVelocity=Vector3.zero; h.AssemblyAngularVelocity=Vector3.zero; if wasA then h.Anchored=true end end
    if u and u.Parent then u.PlatformStand=true end
end

local function collectNormal(coin, rot90)
    local h=HRP(); local u=HUM(); if not h or not u or not coin or not coin.Parent then return false end
    if (h.Position-coin.Position).Magnitude>2.5 then if not travel(coin.Position,rot90,C.Speed,coin) then return false end end
    if not coin.Parent then return true end
    local bv,bg,wasA,curU=unanchorForTouch(rot90); if not bv then return false end
    local got=false; local start=tick(); local statBefore=statValue()
    while tick()-start<1.5 and C.Farming do
        if not coin.Parent then got=true; break end
        pcall(function() firetouchinterest(h,coin,0); firetouchinterest(h,coin,1) end)
        local sv=statValue(); if statBefore and sv and sv>statBefore then got=true; break end
        task.wait(0.05)
    end
    reanchorAfterTouch(bv,bg,wasA,curU); 
    if got then removeCoinFromCache(coin) end
    return got
end

local function collectStealth(coin)
    local h=HRP(); local u=HUM(); if not h or not u or not coin or not coin.Parent then return false end
    local target=Vector3.new(coin.Position.X, coin.Position.Y-C.Depth, coin.Position.Z)
    if (h.Position-target).Magnitude>2.5 then if not travel(target,true,C.Speed,coin) then return false end end
    local bv,bg,wasA,curU=unanchorForTouch(true); if not bv then return false end
    local got=false; local start=tick(); local statBefore=statValue()
    while tick()-start<1.5 and C.Farming do
        if not coin.Parent then got=true; break end
        if C.CoinAura then
            for _,c in ipairs(getCoins()) do if c.Parent and not isBlacklisted(c) then local d=(h.Position-c.Position).Magnitude; if d<=C.AuraRadius then pcall(function() firetouchinterest(h,c,0); firetouchinterest(h,c,1) end) end end end
        else
            pcall(function() firetouchinterest(h,coin,0); firetouchinterest(h,coin,1) end)
        end
        local sv=statValue(); if statBefore and sv and sv>statBefore then got=true; break end
        task.wait(0.05)
    end
    if not got and coin.Parent and C.Farming then
        reanchorAfterTouch(bv,bg,wasA,curU); travel(coin.Position,true,C.Speed*1.5,coin)
        local bv2,bg2,wasA2,curU2=unanchorForTouch(true)
        if bv2 then local s2=tick(); while tick()-s2<0.5 and C.Farming do if not coin.Parent then got=true; break end; pcall(function() firetouchinterest(h,coin,0); firetouchinterest(h,coin,1) end); task.wait(0.05) end; reanchorAfterTouch(bv2,bg2,wasA2,curU2) end
    else reanchorAfterTouch(bv,bg,wasA,curU) end
    if got then removeCoinFromCache(coin) end
    return got
end

-- ============ AUTO GRAB GUN ============
local function findGunDropPart()
    local gd=Workspace:FindFirstChild("GunDrop", true)
    if gd and gd:IsA("BasePart") then return gd end
    for _,o in ipairs(Workspace:GetChildren()) do
        if (o:IsA("Tool") or o:IsA("Model")) and (o.Name=="Gun" or o.Name=="Revolver") and not Players:GetPlayerFromCharacter(o.Parent) then
            local h=o:FindFirstChild("Handle") or o.PrimaryPart or o:FindFirstChildWhichIsA("BasePart")
            if h then return h end
        end
    end
    return nil
end

local function grabGun()
    if not C.AutoGrabGun then return false end
    if tick()-C.LastGunGrab<5 then return false end
    local ch=LocalPlayer.Character; if not ch then return false end
    if ch:FindFirstChild("Gun") then return false end
    local bp=LocalPlayer:FindFirstChild("Backpack"); if bp and bp:FindFirstChild("Gun") then return false end
    local handle=findGunDropPart(); if not handle then return false end
    C.LastGunGrab=tick(); C.FarmStatus="grab gun"
    local h=HRP(); if not h then return false end
    if (h.Position-handle.Position).Magnitude>5 then travel(handle.Position,false,C.Speed*1.5,nil) end
    local bv,bg,wasA,curU=unanchorForTouch(false); if not bv then return false end
    task.wait(0.03)
    pcall(function() firetouchinterest(h,handle,0); task.wait(0.05); firetouchinterest(h,handle,1) end)
    task.wait(0.1); reanchorAfterTouch(bv,bg,wasA,curU); return true
end

-- ============ ROLE ============
local function role()
    local d=PD()
    if d and d[LocalPlayer.Name] then local r=d[LocalPlayer.Name].Role; if r and r~="None" then return r end end
    for _,cont in ipairs({LocalPlayer.Character,LocalPlayer:FindFirstChild("Backpack")}) do
        if cont then for _,it in ipairs(cont:GetChildren()) do if it:IsA("Tool") then local n=it.Name:lower(); if n:find("knife") then return "Murderer" end; if n:find("gun") then return "Sheriff" end end end end
    end
    return "Innocent"
end
local function equip(n)
    local ch=LocalPlayer.Character; if not ch then return nil end
    local t=ch:FindFirstChild(n)
    if not t then local bp=LocalPlayer:FindFirstChild("Backpack"); t=bp and bp:FindFirstChild(n); if t then t.Parent=ch; task.wait(0.2) end end
    return t
end
local function killAll()
    local k=equip("Knife"); if not k then return end
    local ev=k:FindFirstChild("Events"); local ht=ev and ev:FindFirstChild("HandleTouched"); if not ht then return end
    for _,p in ipairs(Players:GetPlayers()) do
        if p~=LocalPlayer and p.Character then
            local up=p.Character:FindFirstChild("UpperTorso") or p.Character:FindFirstChild("Torso")
            if up then pcall(function() ht:FireServer(up) end); task.wait(0.05) end
        end
    end
end

-- ============ FLING ============
local function touch(a,b) pcall(function() firetouchinterest(a,b,0); firetouchinterest(a,b,1) end) end

local function flingTarget(targetPlayer)
    if not targetPlayer or not targetPlayer.Character then return false end
    local myChar=LocalPlayer.Character; if not myChar then return false end
    local myHum=myChar:FindFirstChildOfClass("Humanoid"); local myRoot=myChar:FindFirstChild("HumanoidRootPart")
    if not myHum or not myRoot then return false end
    local tChar=targetPlayer.Character; local tRoot=tChar and tChar:FindFirstChild("HumanoidRootPart")
    if not tRoot then return false end

    myHum:ChangeState(Enum.HumanoidStateType.Physics)
    myRoot.Anchored=false
    
    local startTime=tick(); local success=false
    while tick()-startTime<2.0 and C.Farming do
        if not tRoot.Parent or not myRoot.Parent then break end
        local offset=tRoot.CFrame*CFrame.new(0,0,2)
        myRoot.CFrame=offset
        local dir=(tRoot.Position-myRoot.Position).Unit
        myRoot.AssemblyLinearVelocity=dir*150+Vector3.new(0,50,0)
        myRoot.AssemblyAngularVelocity=Vector3.new(0,100,0)
        pcall(function() firetouchinterest(myRoot,tRoot,0); firetouchinterest(myRoot,tRoot,1) end)
        local tHum=tChar:FindFirstChildOfClass("Humanoid")
        if tHum and tHum.Health<=0 then success=true; break end
        task.wait(0.05)
    end
    myHum:ChangeState(Enum.HumanoidStateType.GettingUp)
    myRoot.AssemblyLinearVelocity=Vector3.zero; myRoot.AssemblyAngularVelocity=Vector3.zero
    return success
end

local function flingLoop(targetPlayer)
    local deadline=tick()+12
    while tick()<deadline and C.Farming do
        local tChar=targetPlayer.Character; if not tChar then break end
        local tHum=tChar:FindFirstChildOfClass("Humanoid"); if not tHum or tHum.Health<=0 then break end
        flingTarget(targetPlayer)
        task.wait(0.5)
    end
end

-- ============ SHOOT ============
local function getPing()
    local ok, ping = pcall(function()
        return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
    end)
    return ok and ping or 100
end

local function shootAtMurderer()
    local gun=equip("Gun"); if not gun then return false end
    local m=findMurderer(); if not m or not m.Character then return false end
    local mHrp=m.Character:FindFirstChild("HumanoidRootPart")
    local mHead=m.Character:FindFirstChild("Head")
    local hrp=HRP(); if not mHrp or not hrp then return false end
    local cam=workspace.CurrentCamera; if not cam then return false end

    local ping=getPing()
    local velocity=mHrp.AssemblyLinearVelocity
    local predTime = (ping/1000) * C.PredMultiplier
    local aimPos = mHrp.Position + velocity * predTime
    if mHead then aimPos = mHead.Position + velocity * predTime end

    pcall(function() hrp.CFrame=CFrame.new(hrp.Position, aimPos) end)
    task.wait(0.03)

    local screenPos, onScreen = cam:WorldToViewportPoint(aimPos)
    pcall(function() gun:Activate() end)
    task.wait(0.05)

    if onScreen then
        local isMobile=UIS.TouchEnabled and not UIS.MouseEnabled
        if isMobile then
            pcall(function() VirtualUser:Button1Down(Vector2.new(screenPos.X,screenPos.Y),cam.CFrame) end)
            task.wait(0.08)
            pcall(function() VirtualUser:Button1Up(Vector2.new(screenPos.X,screenPos.Y),cam.CFrame) end)
        else
            pcall(function()
                VirtualInputManager:SendMouseMoveEvent(screenPos.X,screenPos.Y,game)
                task.wait(0.02)
                VirtualInputManager:SendMouseButtonEvent(screenPos.X,screenPos.Y,0,true,game,0)
                task.wait(0.08)
                VirtualInputManager:SendMouseButtonEvent(screenPos.X,screenPos.Y,0,false,game,0)
            end)
        end
    end

    local ev=gun:FindFirstChild("Events")
    if ev then
        for _,r in ipairs(ev:GetChildren()) do
            if r:IsA("RemoteEvent") then
                local fireArgs = {mHrp}
                if mHead then fireArgs = {mHead} end
                pcall(function() r:FireServer(unpack(fireArgs)) end)
            end
        end
    end
    return true
end

local function shootLoop()
    local waited=0
    while waited<3 and C.Farming do if findMurderer() then break end; task.wait(0.2); waited=waited+0.2 end
    local deadline=tick()+15; local shots=0
    while tick()<deadline and C.Farming do
        local m=findMurderer(); if not m or not m.Character then break end
        local mh=m.Character:FindFirstChildOfClass("Humanoid"); if not mh or mh.Health<=0 then break end
        if not shootAtMurderer() then break end
        shots=shots+1; task.wait(0.25)
    end
    return shots>0
end

-- ============ FULL BAG ============
local function fullBag()
    local r=role(); local did=false
    local h=HRP(); if h then h.Anchored=false end
    local u=HUM(); if u then u.PlatformStand=false; u.AutoRotate=true end

    if r=="Innocent" then
        if C.FlingMurderer then
            local m=findMurderer()
            if m then
                C.FarmStatus="flinging murderer"
                flingLoop(m)
                did=true
            end
        end
        if C.ResetInnocent then hardReset(); return end
        if did then return end
    elseif r=="Sheriff" then
        if C.ShootSheriff then
            C.FarmStatus="shooting"
            shootLoop()
            did=true
        end
    elseif r=="Murderer" then
        if C.KillMurderer then killAll(); did=true end
        if C.ResetMurderer and not did then hardReset(); return end
    end

    if did and C.ResetAfterAction then task.wait(1.5); hardReset(); return end
    if C.ResetAnyRole then hardReset() end
end

-- ============ STATS / ROUND WATCHER ============
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
local function rate() local e=math.max(1,tick()-C.Stats.Start); return math.floor((C.Stats.Total/e)*3600) end

task.spawn(function()
    local lastC=nil
    while true do
        task.wait(0.15)
        local ch=LocalPlayer.Character
        if ch~=lastC then lastC=ch; C.MissCount=0; C.WasInRound=false end
        local h=ch and ch:FindFirstChild("HumanoidRootPart"); local u=ch and ch:FindFirstChildOfClass("Humanoid")
        if C.Farming and h and u then
            if h.Position.Y<-150 then C.FarmStatus="fell"; hardReset(); C.Cooldown=tick()+3; C.MissCount=0; C.WasInRound=false; continue end
            local outside=isDeadOrOutOfRound()
            if not outside then C.WasInRound=true; C.MissCount=0
            elseif C.WasInRound then C.MissCount=C.MissCount+1
                if C.MissCount>=3 then C.FarmStatus="round end"; if u.Health>0 then hardReset() end; C.Cooldown=tick()+3; C.MissCount=0; C.WasInRound=false end
            end
        else C.MissCount=0; C.WasInRound=false end
    end
end)

-- ============ FARM ============
local function farmLoopFn()
    while C.Farming do
        if tick()<C.Cooldown then C.FarmStatus="cooldown"; cleanup(); task.wait(0.2); continue end
        local u=HUM(); local h=HRP()
        if not u or u.Health<=0 or not h then C.FarmStatus="no char"; task.wait(0.3); continue end
        if u:GetState()==Enum.HumanoidStateType.Dead then C.FarmStatus="dead state"; cleanup(); task.wait(0.3); continue end
        if isDeadOrOutOfRound() then C.FarmStatus="dead/lobby"; cleanup(); task.wait(0.3); continue end

        if C.AutoGrabGun and role()=="Sheriff" then
            local ch=LocalPlayer.Character; local bp=LocalPlayer:FindFirstChild("Backpack")
            local hasGun=(ch and ch:FindFirstChild("Gun")) or (bp and bp:FindFirstChild("Gun"))
            if not hasGun and findGunDropPart() then grabGun(); task.wait(0.3) end
        end

        local coin=nearestCoin()
        if coin then
            local got=false
            if C.FarmMode=="Stealth" then
                C.FarmStatus=C.CoinAura and "stealth+aura" or "stealth"
                if not h.Anchored then h.Anchored=true; u.PlatformStand=true; u.AutoRotate=false end
                got=collectStealth(coin)
            elseif C.FarmMode=="Lay" then
                C.FarmStatus="lay"
                if not h.Anchored then h.Anchored=true; u.PlatformStand=true; u.AutoRotate=false end
                got=collectNormal(coin,true)
            else
                C.FarmStatus="standard"
                if not h.Anchored then h.Anchored=true; u.PlatformStand=true; u.AutoRotate=false end
                got=collectNormal(coin,false)
            end
            if got then 
                C.CollectFails=0
                removeCoinFromCache(coin)
            elseif coin.Parent then 
                blacklist(coin); C.CollectFails=C.CollectFails+1
            else 
                C.CollectFails=0
            end
            coinCache.ts = 0
            task.wait(0.02)
        else C.FarmStatus="no coins"; cleanup(); task.wait(0.3) end

        local st=statValue()
        if st and st>=threshold() and tick()-C.LastFull>3 then C.LastFull=tick(); C.FarmStatus="full bag"; fullBag() end
    end
    C.FarmStatus="idle"
    C.Farming=false
    C.FarmThread=nil
end

local function farm()
    if C.FarmThread then return end
    C.Farming=true; C.FarmStatus="starting"
    C.FarmThread=task.spawn(farmLoopFn)
end
local function stopFarm()
    C.Farming=false; C.FarmStatus="idle"
    if C.FarmThread then task.cancel(C.FarmThread); C.FarmThread=nil end
    cleanup()
end

-- ============ HOP ============
local function hop()
    if C.IsHopping then return false end
    C.IsHopping=true; C.IsTeleporting=true; C.HopStatus="fetching"
    
    local servers = {}
    local url = string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100", game.PlaceId)
    local success, result = pcall(function() return game:HttpGet(url) end)
    
    if success and result then
        local ok, res = pcall(function() return HttpService:JSONDecode(result) end)
        if ok and res and res.data then
            for _, s in ipairs(res.data) do
                if s.id ~= game.JobId and s.playing < s.maxPlayers then
                    table.insert(servers, s.id)
                end
            end
        end
    end
    
    if #servers == 0 then
        C.HopStatus="fallback"
        pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
        task.wait(5)
        C.IsHopping=false; C.IsTeleporting=false
        return
    end
    
    local targetServer = servers[math.random(1, #servers)]
    C.HopStatus="hopping"
    
    local options = Instance.new("TeleportOptions")
    options.ServerInstanceId = targetServer
    
    pcall(function() TeleportService:TeleportAsync(game.PlaceId, {LocalPlayer}, options) end)
    task.wait(5)
    C.IsHopping=false; C.IsTeleporting=false
end

local function hopNow() if C.IsHopping then return end task.spawn(hop) end
local function hopMonitor()
    if C.HopThread then return end
    C.HopThread=task.spawn(function()
        while C.HopAt>0 do task.wait(5); if not C.IsHopping and #Players:GetPlayers()>C.HopAt then hop(); break end end
    end)
end

-- ============ AUTO-VOTE ============
local VOTE_PADS={"VotePad1","VotePad2","VotePad3"}
local MAPS={"Manor","House 2","Office 3","Hospital 3","Bank 2","Vampire's Castle","Mansion 2","WorkPlace","Hotel 2","Farm House","Police Station","Factory","Bio Lab","Research Facility","Mil Base"}
local function norm(s) s=string.lower(s):gsub("-"," "):gsub("%s+"," "); return s:match("^%s*(.-)%s*$") end
local rankCache={}
local function rank(r) if rankCache[r] then return rankCache[r] end local l=norm(r); local v=#MAPS+1; for i,n in ipairs(MAPS) do if l==norm(n) then v=i; break end end; rankCache[r]=v; return v end
local function pads()
    local o={}; local l=Workspace:FindFirstChild("Lobby"); local f=l and l:FindFirstChild("VotePads"); if not f then return o end
    for _,n in ipairs(VOTE_PADS) do local p=f:FindFirstChild(n); local t=p and p:FindFirstChild("Pad"); local g=p and p:FindFirstChild("VoteInfoGui"); local c=g and g:FindFirstChild("Container"); local l2=c and c:FindFirstChild("MapName"); if t and l2 and g.Enabled then table.insert(o,{trigger=t,map=l2.Text}) end end
    return o
end
local function pickPad(o)
    if #o==0 then return nil end; if C.VoteMode==3 then return o[math.random(1,#o)] end
    local b,bs; for _,p in ipairs(o) do local r=rank(p.map); local s=(C.VoteMode==1) and -r or r; if not bs or s>bs then b,bs=p,s end end; return b
end
local function inside(t,pos) local lp=t.CFrame:PointToObjectSpace(pos); local h=t.Size*0.5; return math.abs(lp.X)<=h.X and math.abs(lp.Y)<=h.Y and math.abs(lp.Z)<=h.Z end
local function vote(p)
    local h=HRP(); local u=HUM(); if not h or not u or u.Health<=0 then return false end
    h.Anchored=false; h.AssemblyLinearVelocity=Vector3.zero; h.AssemblyAngularVelocity=Vector3.zero
    u.PlatformStand=false; u.AutoRotate=true
    local pp=p.trigger.Position; h.CFrame=CFrame.new(pp+Vector3.new(0,4,0))
    local st=tick(); local landed=false
    while tick()-st<2 do task.wait(0.05); local ch=HRP(); if not ch then return false end; if inside(p.trigger,ch.Position) then landed=true; break end; if tick()-st>1 then ch.CFrame=CFrame.new(pp+Vector3.new(0,1,0)) end end
    if not landed then return false end
    if typeof(firetouchinterest)=="function" then pcall(function() firetouchinterest(h,p.trigger,0); task.wait(0.05); firetouchinterest(h,p.trigger,1) end) end
    task.wait(0.3)
    if typeof(firetouchinterest)=="function" then pcall(function() firetouchinterest(h,p.trigger,0); task.wait(0.05); firetouchinterest(h,p.trigger,1) end) end
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
            if #o==0 then task.wait(0.4) elseif C.VoteMax>0 and v>=C.VoteMax then task.wait(0.5) else local p=pickPad(o); if p and vote(p) then v=v+1 end; task.wait(0.5) end
        end
    end)
end
local function stopVote() C.VoteMode=0; if C.VoteThread then task.cancel(C.VoteThread); C.VoteThread=nil end end

-- ============ VISUALS ============
local ROLE_COLORS={Murderer=Color3.fromRGB(255,40,40),Sheriff=Color3.fromRGB(40,140,255),Hero=Color3.fromRGB(255,200,50),Innocent=Color3.fromRGB(60,255,80),Unknown=Color3.fromRGB(200,200,200)}
local COIN_COL=Color3.fromRGB(255,215,0); local GUN_COL=Color3.fromRGB(255,100,255)
local hasDrawing=(function() local ok,d=pcall(function() return Drawing.new("Square") end); if ok and d then pcall(function() d:Remove() end); return true end; return false end)()
local ESP={draws={},smooth={},highlights={},sboxes={},coinHL={},gunHL={},coinBX={},gunBX={}}
local function visOn(cat,feat) return C["Visuals_"..feat.."_"..cat]==true end
local function roleToCat(r) if r=="Murderer" then return "Murderer" end if r=="Sheriff" then return "Sheriff" end if r=="Hero" then return "Hero" end return "Innocent" end
local function roleFor(p) local d=PD(); if d and d[p.Name] and d[p.Name].Role and d[p.Name].Role~="None" then return d[p.Name].Role end return "Innocent" end
local function getDraw(p)
    if ESP.draws[p] then return ESP.draws[p] end; if not hasDrawing then return nil end
    local t={}; pcall(function() t.box=Drawing.new("Square"); t.box.Thickness=1; t.box.Filled=false; t.box.Visible=false end)
    pcall(function() t.name=Drawing.new("Text"); t.name.Center=true; t.name.Outline=true; t.name.Size=13; t.name.Font=2; t.name.Visible=false end)
    pcall(function() t.tracer=Drawing.new("Line"); t.tracer.Thickness=1; t.tracer.Visible=false end)
    ESP.draws[p]=t; return t
end
local function hideAll(t) for _,d in pairs(t) do pcall(function() d.Visible=false end) end end
local function getCoinVisualParts() local parts={}; for _,c in ipairs(getContainers()) do for _,d in ipairs(c:GetDescendants()) do if d:IsA("BasePart") then table.insert(parts,d) end end end; return parts end
local function getGroundGunParts()
    local parts={}; for _,obj in ipairs(Workspace:GetChildren()) do if (obj:IsA("Tool") or obj:IsA("Model")) and (obj.Name=="Gun" or obj.Name=="Revolver") and not Players:GetPlayerFromCharacter(obj.Parent) then for _,p in ipairs(obj:GetDescendants()) do if p:IsA("BasePart") then table.insert(parts,p) end end end end; return parts
end
local anyPlayerDrawing=false; local anyHighlight=false; local anyCoin=false; local anyGun=false
local function rebuildVisualCache()
    anyPlayerDrawing=false; anyHighlight=false
    for _,cat in ipairs({"Murderer","Sheriff","Hero","Innocent"}) do
        if visOn(cat,"ESP") or visOn(cat,"TR") then anyPlayerDrawing=true end
        if visOn(cat,"CH") or visOn(cat,"OL") or visOn(cat,"HL") or visOn(cat,"BX") then anyHighlight=true end
    end
    anyCoin=visOn("Coin","CH") or visOn("Coin","OL") or visOn("Coin","HL") or visOn("Coin","BX")
    anyGun=visOn("Gun","CH") or visOn("Gun","OL") or visOn("Gun","HL") or visOn("Gun","BX")
end
rebuildVisualCache()

RunService.RenderStepped:Connect(function()
    if not hasDrawing then return end
    if not anyPlayerDrawing then for _,t in pairs(ESP.draws) do hideAll(t) end return end
    local cam=workspace.CurrentCamera; if not cam then return end
    local lh=HRP(); local lu=HUM(); local origin
    if lh and lu and lu.Health>0 then local sp,on=cam:WorldToViewportPoint(lh.Position); if on then origin=Vector2.new(sp.X,sp.Y) end end
    if not origin then local vs=cam.ViewportSize; origin=Vector2.new(vs.X/2,vs.Y) end
    for _,p in ipairs(Players:GetPlayers()) do
        if p==LocalPlayer then continue end
        local role=roleFor(p); local cat=roleToCat(role); local wantESP=visOn(cat,"ESP"); local wantTR=visOn(cat,"TR")
        if not (wantESP or wantTR) then if ESP.draws[p] then hideAll(ESP.draws[p]) end continue end
        local t=ESP.draws[p] or getDraw(p); if not t then continue end
        local ch=p.Character; local hp=ch and ch:FindFirstChild("HumanoidRootPart"); local hu=ch and ch:FindFirstChildOfClass("Humanoid")
        if not hp or not hu or hu.Health<=0 then hideAll(t) continue end
        local col=ROLE_COLORS[role] or ROLE_COLORS.Unknown
        local top,on1=cam:WorldToViewportPoint(hp.Position+Vector3.new(0,2.6,0)); local bot,on2=cam:WorldToViewportPoint(hp.Position-Vector3.new(0,2.8,0))
        if not (on1 and on2) then hideAll(t) continue end; if math.abs(top.Y-bot.Y)<2 then hideAll(t) continue end
        local h=math.abs(top.Y-bot.Y); local w=h/1.8
        local targetPos=Vector2.new(top.X-w/2,top.Y); local targetSize=Vector2.new(w,h); local targetTracerTo=Vector2.new(top.X,top.Y)
        local s=ESP.smooth[p]; if not s then s={pos=targetPos,size=targetSize,tracerTo=targetTracerTo}; ESP.smooth[p]=s end
        s.pos=s.pos:Lerp(targetPos,0.4); s.size=s.size:Lerp(targetSize,0.4); s.tracerTo=s.tracerTo:Lerp(targetTracerTo,0.5)
        if wantESP then if t.box then t.box.Position=s.pos; t.box.Size=s.size; t.box.Color=col; t.box.Visible=true end; if t.name then t.name.Text=p.Name.." ["..role.."]"; t.name.Position=Vector2.new(top.X,s.pos.Y-18); t.name.Color=col; t.name.Visible=true end
        else if t.box then t.box.Visible=false end; if t.name then t.name.Visible=false end end
        if wantTR and t.tracer then t.tracer.From=origin; t.tracer.To=s.tracerTo; t.tracer.Color=col; t.tracer.Visible=true elseif t.tracer then t.tracer.Visible=false end
    end
end)

local hlAccum=0
RunService.Heartbeat:Connect(function(dt)
    if not (anyHighlight or anyCoin or anyGun) then return end
    hlAccum=hlAccum+dt; if hlAccum<0.2 then return end; hlAccum=0
    for _,p in ipairs(Players:GetPlayers()) do
        if p==LocalPlayer then continue end
        local role=roleFor(p); local cat=roleToCat(role)
        local wantCH=visOn(cat,"CH"); local wantOL=visOn(cat,"OL"); local wantHL=visOn(cat,"HL"); local wantBX=visOn(cat,"BX")
        local ch=p.Character; local hl=ESP.highlights[p]; local sb=ESP.sboxes[p]
        local wantFill=wantCH or wantHL; local wantEdge=wantOL or wantHL
        if (not ch) or (not (wantFill or wantEdge)) then if hl then pcall(function() hl:Destroy() end); ESP.highlights[p]=nil end
        else
            if not hl or hl.Parent~=ch then if hl then pcall(function() hl:Destroy() end) end; hl=Instance.new("Highlight"); hl.Name="LAMBDA_HL"; hl.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop; hl.Parent=ch; ESP.highlights[p]=hl end
            local col=ROLE_COLORS[role] or ROLE_COLORS.Unknown; hl.FillColor=col; hl.OutlineColor=col; hl.FillTransparency=wantFill and 0.5 or 1; hl.OutlineTransparency=wantEdge and 0 or 1
        end
        if (not ch) or (not wantBX) then if sb then pcall(function() sb:Destroy() end); ESP.sboxes[p]=nil end
        else if not sb or sb.Adornee~=ch then if sb then pcall(function() sb:Destroy() end) end; sb=Instance.new("SelectionBox"); sb.Adornee=ch; sb.LineThickness=0.05; sb.SurfaceTransparency=1; sb.Parent=ch; ESP.sboxes[p]=sb end; sb.Color3=ROLE_COLORS[role] or ROLE_COLORS.Unknown end
    end
    if anyCoin then
        local wantCH=visOn("Coin","CH"); local wantOL=visOn("Coin","OL"); local wantHL=visOn("Coin","HL"); local wantBX=visOn("Coin","BX")
        local wantFill=wantCH or wantHL; local wantEdge=wantOL or wantHL; local seen={}
        for _,part in ipairs(getCoinVisualParts()) do seen[part]=true; local hl=ESP.coinHL[part]; local bx=ESP.coinBX[part]
            if wantFill or wantEdge then if not hl or hl.Parent~=part then if hl then pcall(function() hl:Destroy() end) end; hl=Instance.new("Highlight"); hl.Name="LAMBDA_CoinHL"; hl.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop; hl.Parent=part; ESP.coinHL[part]=hl end; hl.FillColor=COIN_COL; hl.OutlineColor=COIN_COL; hl.FillTransparency=wantFill and 0.5 or 1; hl.OutlineTransparency=wantEdge and 0 or 1 elseif hl then pcall(function() hl:Destroy() end); ESP.coinHL[part]=nil end
            if wantBX then if not bx or bx.Adornee~=part then if bx then pcall(function() bx:Destroy() end) end; bx=Instance.new("SelectionBox"); bx.Adornee=part; bx.Color3=COIN_COL; bx.LineThickness=0.06; bx.SurfaceTransparency=1; bx.Parent=part; ESP.coinBX[part]=bx end elseif bx then pcall(function() bx:Destroy() end); ESP.coinBX[part]=nil end
        end
        for p,hl in pairs(ESP.coinHL) do if not seen[p] or not p.Parent then pcall(function() hl:Destroy() end); ESP.coinHL[p]=nil end end
        for p,bx in pairs(ESP.coinBX) do if not seen[p] or not p.Parent then pcall(function() bx:Destroy() end); ESP.coinBX[p]=nil end end
    else for _,hl in pairs(ESP.coinHL) do pcall(function() hl:Destroy() end) end; for _,bx in pairs(ESP.coinBX) do pcall(function() bx:Destroy() end) end; ESP.coinHL={}; ESP.coinBX={} end
    if anyGun then
        local wantCH=visOn("Gun","CH"); local wantOL=visOn("Gun","OL"); local wantHL=visOn("Gun","HL"); local wantBX=visOn("Gun","BX")
        local wantFill=wantCH or wantHL; local wantEdge=wantOL or wantHL; local seen={}
        for _,part in ipairs(getGroundGunParts()) do seen[part]=true; local hl=ESP.gunHL[part]; local bx=ESP.gunBX[part]
            if wantFill or wantEdge then if not hl or hl.Parent~=part then if hl then pcall(function() hl:Destroy() end) end; hl=Instance.new("Highlight"); hl.Name="LAMBDA_GunHL"; hl.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop; hl.Parent=part; ESP.gunHL[part]=hl end; hl.FillColor=GUN_COL; hl.OutlineColor=GUN_COL; hl.FillTransparency=wantFill and 0.5 or 1; hl.OutlineTransparency=wantEdge and 0 or 1 elseif hl then pcall(function() hl:Destroy() end); ESP.gunHL[part]=nil end
            if wantBX then if not bx or bx.Adornee~=part then if bx then pcall(function() bx:Destroy() end) end; bx=Instance.new("SelectionBox"); bx.Adornee=part; bx.Color3=GUN_COL; bx.LineThickness=0.08; bx.SurfaceTransparency=1; bx.Parent=part; ESP.gunBX[part]=bx end elseif bx then pcall(function() bx:Destroy() end); ESP.gunBX[part]=nil end
        end
        for p,hl in pairs(ESP.gunHL) do if not seen[p] or not p.Parent then pcall(function() hl:Destroy() end); ESP.gunHL[p]=nil end end
        for p,bx in pairs(ESP.gunBX) do if not seen[p] or not p.Parent then pcall(function() bx:Destroy() end); ESP.gunBX[p]=nil end end
    else for _,hl in pairs(ESP.gunHL) do pcall(function() hl:Destroy() end) end; for _,bx in pairs(ESP.gunBX) do pcall(function() bx:Destroy() end) end; ESP.gunHL={}; ESP.gunBX={} end
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
local MAIN_GUI; local REBUILD_TOKEN=0
local function scheduleRebuild() REBUILD_TOKEN=REBUILD_TOKEN+1; local mt=REBUILD_TOKEN; task.delay(0.3,function() if REBUILD_TOKEN==mt then buildGui() end end) end
local PRESETS={Color3.fromRGB(255,0,0),Color3.fromRGB(255,100,0),Color3.fromRGB(255,200,0),Color3.fromRGB(180,255,0),Color3.fromRGB(0,255,0),Color3.fromRGB(0,255,180),Color3.fromRGB(0,255,255),Color3.fromRGB(0,180,255),Color3.fromRGB(0,100,255),Color3.fromRGB(0,0,255),Color3.fromRGB(100,0,255),Color3.fromRGB(180,0,255),Color3.fromRGB(255,0,255),Color3.fromRGB(255,0,180),Color3.fromRGB(255,0,100),Color3.fromRGB(255,255,255),Color3.fromRGB(200,200,200),Color3.fromRGB(128,128,128),Color3.fromRGB(64,64,64),Color3.fromRGB(30,30,30),Color3.fromRGB(0,0,0),Color3.fromRGB(150,75,0),Color3.fromRGB(255,180,150),Color3.fromRGB(80,40,20)}
local THEMES={{name="Gold",p=Color3.fromRGB(255,200,0),s=Color3.fromRGB(30,30,30)},{name="Ocean",p=Color3.fromRGB(0,180,255),s=Color3.fromRGB(20,30,45)},{name="Forest",p=Color3.fromRGB(80,200,80),s=Color3.fromRGB(20,30,20)},{name="Rose",p=Color3.fromRGB(255,100,150),s=Color3.fromRGB(40,20,30)},{name="Cyber",p=Color3.fromRGB(255,0,180),s=Color3.fromRGB(15,15,40)},{name="Mono",p=Color3.fromRGB(220,220,220),s=Color3.fromRGB(25,25,25)}}

function buildGui()
    if MAIN_GUI then pcall(function() MAIN_GUI:Destroy() end) end
    local parent=guiParent(); if not parent then return end
    local gui=Instance.new("ScreenGui"); gui.Name="LambdaHub"; gui.ResetOnSpawn=false; gui.IgnoreGuiInset=true; gui.DisplayOrder=999999
    pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end); gui.Parent=parent; MAIN_GUI=gui

    local main=Instance.new("Frame"); main.Size=UDim2.new(0,390,0,520); main.Position=UDim2.new(0,30,0,30); main.BackgroundColor3=SECONDARY; main.BorderSizePixel=0; main.Active=true; main.Draggable=true; main.Parent=gui
    local titleBar=Instance.new("Frame"); titleBar.Size=UDim2.new(1,0,0,28); titleBar.BackgroundColor3=SECONDARY; titleBar.BorderSizePixel=0; titleBar.Parent=main
    local title=Instance.new("TextLabel"); title.Size=UDim2.new(1,-80,1,0); title.Position=UDim2.new(0,10,0,0); title.BackgroundTransparency=1; title.Text="Lambda Hub | v0.32"; title.TextColor3=PRIMARY; title.Font=Enum.Font.GothamBold; title.TextSize=13; title.TextXAlignment=Enum.TextXAlignment.Left; title.Parent=titleBar
    local min=Instance.new("TextButton"); min.Size=UDim2.new(0,24,0,20); min.Position=UDim2.new(1,-56,0,4); min.BackgroundColor3=Color3.fromRGB(70,70,70); min.Text="—"; min.TextColor3=Color3.fromRGB(255,255,255); min.Font=Enum.Font.GothamBold; min.TextSize=13; min.Parent=titleBar
    local close=Instance.new("TextButton"); close.Size=UDim2.new(0,24,0,20); close.Position=UDim2.new(1,-28,0,4); close.BackgroundColor3=Color3.fromRGB(120,30,30); close.Text="X"; close.TextColor3=Color3.fromRGB(255,255,255); close.Font=Enum.Font.GothamBold; close.TextSize=13; close.Parent=titleBar
    
    local statusBar=Instance.new("Frame"); 
    statusBar.Size=UDim2.new(1,0,0,52); 
    statusBar.Position=UDim2.new(0,0,0,28); 
    statusBar.BackgroundColor3=Color3.fromRGB(20,20,20); 
    statusBar.BorderSizePixel=0; 
    statusBar.Visible=false; 
    statusBar.Parent=main
    
    local stats=Instance.new("TextLabel"); 
    stats.Size=UDim2.new(1,-10,1,0); 
    stats.Position=UDim2.new(0,5,0,0); 
    stats.BackgroundTransparency=1; 
    stats.TextColor3=PRIMARY; 
    stats.Font=Enum.Font.Code; 
    stats.TextSize=11; 
    stats.TextXAlignment=Enum.TextXAlignment.Left; 
    stats.TextYAlignment=Enum.TextYAlignment.Center; 
    stats.Text="Collected: 0 | Per hour: 0 | Bag: ?/50 | Fails: 0 | Status: idle"; 
    stats.Parent=statusBar

    local collapsed=false
    min.MouseButton1Click:Connect(function() 
        collapsed=not collapsed
        if collapsed then
            main.Size=UDim2.new(0,390,0,80); 
            content.Visible=false; 
            tabBar.Visible=false; 
            statusBar.Visible=true; 
            min.Text="+"
        else
            main.Size=UDim2.new(0,390,0,520); 
            content.Visible=true; 
            tabBar.Visible=true; 
            statusBar.Visible=false; 
            min.Text="—"
        end
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
    local tabBar=Instance.new("Frame"); tabBar.Size=UDim2.new(1,0,0,26); tabBar.Position=UDim2.new(0,0,0,28); tabBar.BackgroundColor3=SECONDARY; tabBar.BorderSizePixel=0; tabBar.Parent=main
    local tabLay=Instance.new("UIListLayout"); tabLay.FillDirection=Enum.FillDirection.Horizontal; tabLay.Padding=UDim.new(0,0); tabLay.Parent=tabBar
    local content=Instance.new("Frame"); content.Size=UDim2.new(1,0,1,-54); content.Position=UDim2.new(0,0,0,54); content.BackgroundTransparency=1; content.Parent=main
    local tabs={}
    local function newTab(name,wPct)
        local b=Instance.new("TextButton"); b.Size=UDim2.new(wPct,0,1,0); b.BackgroundColor3=SECONDARY; b.Text=name; b.TextColor3=TEXT_DIM; b.Font=Enum.Font.GothamBold; b.TextSize=10; b.Parent=tabBar
        local f=Instance.new("ScrollingFrame"); f.Size=UDim2.new(1,0,1,0); f.BackgroundTransparency=1; f.ScrollBarThickness=4; f.CanvasSize=UDim2.new(0,0,0,0); f.Visible=false; f.Parent=content
        local l=Instance.new("UIListLayout"); l.Padding=UDim.new(0,4); l.SortOrder=Enum.SortOrder.LayoutOrder; l.Parent=f
        local p=Instance.new("UIPadding"); p.PaddingTop=UDim.new(0,8); p.PaddingLeft=UDim.new(0,8); p.PaddingRight=UDim.new(0,8); p.Parent=f
        tabs[name]={btn=b,frame=f,list=l}
        l:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function() f.CanvasSize=UDim2.new(0,0,0,l.AbsoluteContentSize.Y+16) end)
        b.MouseButton1Click:Connect(function() for _,t in pairs(tabs) do t.frame.Visible=false; t.btn.BackgroundColor3=SECONDARY; t.btn.TextColor3=TEXT_DIM end; f.Visible=true; b.BackgroundColor3=PRIMARY; b.TextColor3=Color3.fromRGB(0,0,0) end)
        return f
    end
    local mainTab=newTab("Main",1/8); local combatTab=newTab("Combat",1/8); local actionsTab=newTab("Actions",1/8); local protectTab=newTab("Protect",1/8); local visualsTab=newTab("Visuals",1/8); local serverTab=newTab("Server",1/8); local voteTab=newTab("Vote",1/8); local themeTab=newTab("Theme",1/8)

    local function lbl(par,txt,ord) local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,0,16); l.BackgroundTransparency=1; l.Text=txt; l.TextColor3=TEXT_DIM; l.Font=Enum.Font.Gotham; l.TextSize=10; l.TextXAlignment=Enum.TextXAlignment.Left; l.LayoutOrder=ord; l.Parent=par; return l end
    local function tog(par,txt,init,ord,cb)
        local row=Instance.new("Frame"); row.Size=UDim2.new(1,0,0,26); row.BackgroundTransparency=1; row.LayoutOrder=ord; row.Parent=par
        local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,-60,1,0); l.BackgroundTransparency=1; l.Text=txt; l.TextColor3=TEXT_BRIGHT; l.Font=Enum.Font.Gotham; l.TextSize=12; l.TextXAlignment=Enum.TextXAlignment.Left; l.Parent=row
        local b=Instance.new("TextButton"); b.Size=UDim2.new(0,48,0,20); b.Position=UDim2.new(1,-52,0.5,-10); b.BackgroundColor3=init and PRIMARY or Color3.fromRGB(55,55,55); b.Text=init and "ON" or "OFF"; b.TextColor3=init and Color3.fromRGB(0,0,0) or Color3.fromRGB(255,255,255); b.Font=Enum.Font.GothamBold; b.TextSize=10; b.Parent=row
        local st=init; b.MouseButton1Click:Connect(function() st=not st; b.BackgroundColor3=st and PRIMARY or Color3.fromRGB(55,55,55); b.Text=st and "ON" or "OFF"; b.TextColor3=st and Color3.fromRGB(0,0,0) or Color3.fromRGB(255,255,255); pcall(function() cb(st) end); save() end)
        return b
    end
    local function inp(par,label,val,ord,cb)
        local row=Instance.new("Frame"); row.Size=UDim2.new(1,0,0,24); row.BackgroundTransparency=1; row.LayoutOrder=ord; row.Parent=par
        local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,-80,1,0); l.BackgroundTransparency=1; l.Text=label; l.TextColor3=TEXT_BRIGHT; l.Font=Enum.Font.Gotham; l.TextSize=11; l.TextXAlignment=Enum.TextXAlignment.Left; l.Parent=row
        local b=Instance.new("TextBox"); b.Size=UDim2.new(0,72,0,20); b.Position=UDim2.new(1,-76,0.5,-10); b.BackgroundColor3=Color3.fromRGB(45,45,45); b.TextColor3=Color3.fromRGB(255,255,255); b.Text=tostring(val); b.Font=Enum.Font.Gotham; b.TextSize=11; b.Parent=row
        b.FocusLost:Connect(function() pcall(function() cb(b.Text) end); save() end)
    end
    local function cyc(par,label,opts,init,ord,cb)
        local row=Instance.new("Frame"); row.Size=UDim2.new(1,0,0,26); row.BackgroundTransparency=1; row.LayoutOrder=ord; row.Parent=par
        local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,-130,1,0); l.BackgroundTransparency=1; l.Text=label; l.TextColor3=TEXT_BRIGHT; l.Font=Enum.Font.Gotham; l.TextSize=11; l.TextXAlignment=Enum.TextXAlignment.Left; l.Parent=row
        local b=Instance.new("TextButton"); b.Size=UDim2.new(0,120,0,20); b.Position=UDim2.new(1,-124,0.5,-10); b.BackgroundColor3=Color3.fromRGB(55,55,55); b.TextColor3=Color3.fromRGB(255,255,255); b.Font=Enum.Font.Gotham; b.TextSize=11; b.Parent=row
        local i=findIdx(opts,init); b.Text=opts[i]; b.MouseButton1Click:Connect(function() i=i%#opts+1; b.Text=opts[i]; pcall(function() cb(opts[i]) end); save() end)
    end
    local function btn(par,label,bgColor,textColor,ord,cb) local b=Instance.new("TextButton"); b.Size=UDim2.new(1,0,0,28); b.BackgroundColor3=bgColor; b.Text=label; b.TextColor3=textColor; b.Font=Enum.Font.GothamBold; b.TextSize=11; b.LayoutOrder=ord; b.Parent=par; b.MouseButton1Click:Connect(cb); return b end
    local function playerDrop(par,label,ord,cb)
        local row=Instance.new("Frame"); row.Size=UDim2.new(1,0,0,26); row.BackgroundTransparency=1; row.LayoutOrder=ord; row.Parent=par
        local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,-100,1,0); l.BackgroundTransparency=1; l.Text=label; l.TextColor3=TEXT_BRIGHT; l.Font=Enum.Font.Gotham; l.TextSize=11; l.TextXAlignment=Enum.TextXAlignment.Left; l.Parent=row
        local b=Instance.new("TextButton"); b.Size=UDim2.new(0,90,0,20); b.Position=UDim2.new(1,-94,0.5,-10); b.BackgroundColor3=Color3.fromRGB(55,55,55); b.TextColor3=Color3.fromRGB(255,255,255); b.Font=Enum.Font.Gotham; b.TextSize=10; b.Text="Select"; b.Parent=row
        local players={}; for _,p in ipairs(Players:GetPlayers()) do if p~=LocalPlayer then table.insert(players,p) end end
        local idx=0
        b.MouseButton1Click:Connect(function()
            idx=idx%#players+1
            if idx==0 then b.Text="Select"; cb(nil)
            else b.Text=players[idx].Name; cb(players[idx]) end
        end)
    end
    local function visualRow(par,dispName,cat,features,ord)
        local row=Instance.new("Frame"); row.Size=UDim2.new(1,0,0,26); row.BackgroundTransparency=1; row.LayoutOrder=ord; row.Parent=par
        local l=Instance.new("TextLabel"); l.Size=UDim2.new(0,55,1,0); l.BackgroundTransparency=1; l.Text=dispName; l.TextColor3=TEXT_BRIGHT; l.Font=Enum.Font.Gotham; l.TextSize=11; l.TextXAlignment=Enum.TextXAlignment.Left; l.Parent=row
        local xPos=60
        for _,feat in ipairs(features) do local key="Visuals_"..feat.."_"..cat; if C[key]==nil then C[key]=false end; local state=C[key]
            local b=Instance.new("TextButton"); b.Size=UDim2.new(0,40,0,20); b.Position=UDim2.new(0,xPos,0.5,-10); b.BackgroundColor3=state and PRIMARY or Color3.fromRGB(55,55,55); b.Text=feat; b.TextColor3=state and Color3.fromRGB(0,0,0) or Color3.fromRGB(255,255,255); b.Font=Enum.Font.GothamBold; b.TextSize=9; b.Parent=row
            b.MouseButton1Click:Connect(function() C[key]=not C[key]; b.BackgroundColor3=C[key] and PRIMARY or Color3.fromRGB(55,55,55); b.TextColor3=C[key] and Color3.fromRGB(0,0,0) or Color3.fromRGB(255,255,255); rebuildVisualCache(); save() end)
            xPos=xPos+42
        end
    end

    local o=0; local function no() o=o+1; return o end

    -- MAIN
    local farmBtn = tog(mainTab,"AUTO FARM",C.Farming,no(),function(s) if s then farm() else stopFarm() end end)
    tog(mainTab,"Auto-launch on exec",C.AutoLaunch,no(),function(s) C.AutoLaunch=s end)
    lbl(mainTab,"— Currency —",no()); cyc(mainTab,"Target",{"Coin","Candy","SnowToken","Token","Shell"},C.Currency,no(),function(v) C.Currency=v end)
    lbl(mainTab,"— Movement —",no()); inp(mainTab,"Speed (studs/s)",C.Speed,no(),function(v) local n=tonumber(v); if n then C.Speed=math.clamp(n,10,70) end end)
    cyc(mainTab,"Farm mode",{"Stealth","Standard","Lay"},C.FarmMode,no(),function(v) C.FarmMode=v end)
    inp(mainTab,"Stealth depth (1-8)",C.Depth,no(),function(v) local n=tonumber(v); if n then C.Depth=math.clamp(n,1,8) end end)
    tog(mainTab,"Coin Aura",C.CoinAura,no(),function(s) C.CoinAura=s end)
    inp(mainTab,"Aura radius",C.AuraRadius,no(),function(v) local n=tonumber(v); if n then C.AuraRadius=math.clamp(n,5,25) end end)
    lbl(mainTab,"— Bag —",no()); inp(mainTab,"Threshold (50=default)",C.Threshold,no(),function(v) local n=tonumber(v); if n then C.Threshold=math.max(0,n) end end)
    
    task.spawn(function() 
        while stats and stats.Parent do 
            task.wait(0.5)
            local b=statValue()
            local rateVal = rate()
            local thresh = threshold()
            stats.Text=string.format("Collected: %d | Per hour: %d | Bag: %s/%d | Fails: %d | Status: %s",
                C.Stats.Total, rateVal, b and tostring(b) or "?", thresh, C.CollectFails, C.FarmStatus or "idle") 
        end 
    end)

    -- COMBAT
    o=0
    lbl(combatTab,"— Sheriff —",no())
    tog(combatTab,"Shoot murderer when full",C.ShootSheriff,no(),function(s) C.ShootSheriff=s end)
    inp(combatTab,"Prediction (0-3)",C.PredMultiplier,no(),function(v) local n=tonumber(v); if n then C.PredMultiplier=math.clamp(n,0,3) end end)
    lbl(combatTab,"— Innocent —",no())
    tog(combatTab,"Fling murderer when full",C.FlingMurderer,no(),function(s) C.FlingMurderer=s end)
    lbl(combatTab,"— Manual fling —",no())
    playerDrop(combatTab,"Fling target",no(),function(p) C.FlingTarget=p end)
    btn(combatTab,"FLING SELECTED TARGET",PRIMARY,Color3.fromRGB(0,0,0),no(),function()
        local t=C.FlingTarget
        if not t or not t.Character then
            local m=findMurderer()
            if m then t=m else return end
        end
        if t and t.Character then
            C.FarmStatus="manual fling"
            flingLoop(t)
        end
    end)
    btn(combatTab,"FLING MURDERER",Color3.fromRGB(255,100,100),Color3.fromRGB(255,255,255),no(),function()
        local m=findMurderer()
        if m then C.FarmStatus="manual fling"; flingLoop(m) end
    end)
    btn(combatTab,"FLING SHERIFF",Color3.fromRGB(100,140,255),Color3.fromRGB(255,255,255),no(),function()
        local s=findRole("Sheriff")
        if s then C.FarmStatus="manual fling"; flingLoop(s) end
    end)
    btn(combatTab,"FLING RANDOM INNOCENT",Color3.fromRGB(100,255,100),Color3.fromRGB(0,0,0),no(),function()
        local r=findRole("Innocent") or findRole("Hero")
        if r then C.FarmStatus="manual fling"; flingLoop(r) end
    end)

    -- ACTIONS
    o=0
    tog(actionsTab,"Reset when full",C.ResetInnocent,no(),function(s) C.ResetInnocent=s end)
    tog(actionsTab,"Kill all when full",C.KillMurderer,no(),function(s) C.KillMurderer=s end)
    tog(actionsTab,"Reset murderer when full",C.ResetMurderer,no(),function(s) C.ResetMurderer=s end)
    tog(actionsTab,"Reset after action",C.ResetAfterAction,no(),function(s) C.ResetAfterAction=s end)
    tog(actionsTab,"Reset regardless of role",C.ResetAnyRole,no(),function(s) C.ResetAnyRole=s end)
    tog(actionsTab,"Auto grab gun",C.AutoGrabGun,no(),function(s) C.AutoGrabGun=s end)

    -- PROTECT
    o=0
    tog(protectTab,"Anti-AFK",C.AntiAFK,no(),function(s) C.AntiAFK=s; if s then startAFK() end end)
    tog(protectTab,"Anti-Void",C.AntiVoid,no(),function(s) C.AntiVoid=s; setupVoid() end)
    tog(protectTab,"Anti-Fling",C.AntiFling,no(),function(s) C.AntiFling=s end)
    tog(protectTab,"Anti-Murderer (passive)",C.AntiMurderer,no(),function(s) C.AntiMurderer=s end)
    tog(protectTab,"Noclip",C.Noclip,no(),function(s) C.Noclip=s; if s then startNoclip() else stopNoclip() end end)
    tog(protectTab,"Disable 3D",C.Disable3D,no(),function(s) C.Disable3D=s; pcall(function() RunService:Set3dRenderingEnabled(not s) end) end)

    -- VISUALS
    o=0
    lbl(visualsTab,"— Players —",no()); lbl(visualsTab,"Category      ESP  TR   CH   OL   HL   BX",no())
    visualRow(visualsTab,"Murd","Murderer",{"ESP","TR","CH","OL","HL","BX"},no())
    visualRow(visualsTab,"Sher","Sheriff",{"ESP","TR","CH","OL","HL","BX"},no())
    visualRow(visualsTab,"Hero","Hero",{"ESP","TR","CH","OL","HL","BX"},no())
    visualRow(visualsTab,"Inno","Innocent",{"ESP","TR","CH","OL","HL","BX"},no())
    lbl(visualsTab,"— Objects —",no()); lbl(visualsTab,"Category      ESP  TR   CH   OL   HL   BX",no())
    visualRow(visualsTab,"Coin","Coin",{"BX","CH","OL","HL"},no())
    visualRow(visualsTab,"Gun","Gun",{"BX","CH","OL","HL"},no())

    -- SERVER
    o=0
    inp(serverTab,"Hop if players >",C.HopAt,no(),function(v) local n=tonumber(v); if n then C.HopAt=n end end)
    btn(serverTab,"HOP NOW",PRIMARY,Color3.fromRGB(0,0,0),no(),function() hopNow() end)
    local hopLbl=Instance.new("TextLabel"); hopLbl.Size=UDim2.new(1,0,0,36); hopLbl.BackgroundColor3=Color3.fromRGB(28,28,28); hopLbl.BorderSizePixel=0; hopLbl.TextColor3=PRIMARY; hopLbl.Font=Enum.Font.Code; hopLbl.TextSize=10; hopLbl.Text="Status: idle"; hopLbl.LayoutOrder=no(); hopLbl.Parent=serverTab
    task.spawn(function() while hopLbl.Parent do task.wait(0.5); local s="Status: "..(C.HopStatus~="" and C.HopStatus or "idle"); hopLbl.Text=s end end)

    -- VOTE
    o=0
    local voteOpts={"OFF","Smallest Map","Largest Map","Random"}; local voteMap={OFF=0,["Smallest Map"]=1,["Largest Map"]=2,Random=3}; local voteRev={[0]="OFF",[1]="Smallest Map",[2]="Largest Map",[3]="Random"}
    cyc(voteTab,"Vote mode",voteOpts,voteRev[C.VoteMode] or "OFF",no(),function(v) C.VoteMode=voteMap[v] or 0; if C.VoteMode~=0 then startVote() else stopVote() end end)
    inp(voteTab,"Max votes (0=inf)",C.VoteMax,no(),function(v) local n=tonumber(v); if n then C.VoteMax=math.max(0,n) end end)

    -- THEME
    o=0
    lbl(themeTab,"— Themes —",no())
    local themeRow=Instance.new("Frame"); themeRow.Size=UDim2.new(1,0,0,28); themeRow.BackgroundTransparency=1; themeRow.LayoutOrder=no(); themeRow.Parent=themeTab
    local themeLay=Instance.new("UIListLayout"); themeLay.FillDirection=Enum.FillDirection.Horizontal; themeLay.Padding=UDim.new(0,4); themeLay.Parent=themeRow
    for _,theme in ipairs(THEMES) do local tb=Instance.new("TextButton"); tb.Size=UDim2.new(0,54,1,0); tb.BackgroundColor3=theme.p; tb.Text=theme.name; tb.TextColor3=Color3.fromRGB(0,0,0); tb.Font=Enum.Font.GothamBold; tb.TextSize=9; tb.Parent=themeRow; tb.MouseButton1Click:Connect(function() C.PrimaryColor=colorToHex(theme.p); C.SecondaryColor=colorToHex(theme.s); PRIMARY=theme.p; SECONDARY=theme.s; save(); buildGui() end) end
    lbl(themeTab,"— Primary Color —",no()); local pPrev=Instance.new("Frame"); pPrev.Size=UDim2.new(1,0,0,24); pPrev.BackgroundColor3=PRIMARY; pPrev.BorderSizePixel=0; pPrev.LayoutOrder=no(); pPrev.Parent=themeTab
    local pHue=Instance.new("Frame"); pHue.Size=UDim2.new(1,0,0,18); pHue.BackgroundColor3=Color3.new(1,1,1); pHue.BorderSizePixel=0; pHue.LayoutOrder=no(); pHue.Parent=themeTab
    local pHueGrad=Instance.new("UIGradient"); pHueGrad.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(255,0,0)),ColorSequenceKeypoint.new(1/6,Color3.fromRGB(255,255,0)),ColorSequenceKeypoint.new(2/6,Color3.fromRGB(0,255,0)),ColorSequenceKeypoint.new(3/6,Color3.fromRGB(0,255,255)),ColorSequenceKeypoint.new(4/6,Color3.fromRGB(0,0,255)),ColorSequenceKeypoint.new(5/6,Color3.fromRGB(255,0,255)),ColorSequenceKeypoint.new(1,Color3.fromRGB(255,0,0))}); pHueGrad.Parent=pHue
    pHue.InputBegan:Connect(function(input) if input.UserInputType~=Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.Touch then return end; local rel=(input.Position.X-pHue.AbsolutePosition.X)/pHue.AbsoluteSize.X; rel=math.clamp(rel,0,1); local c=Color3.fromHSV(rel,0.85,1); C.PrimaryColor=colorToHex(c); PRIMARY=c; pPrev.BackgroundColor3=c; save(); scheduleRebuild() end)
    local pGrid=Instance.new("Frame"); pGrid.Size=UDim2.new(1,0,0,84); pGrid.BackgroundTransparency=1; pGrid.LayoutOrder=no(); pGrid.Parent=themeTab
    local pGridLay=Instance.new("UIGridLayout"); pGridLay.CellSize=UDim2.new(0,20,0,20); pGridLay.CellPadding=UDim2.new(0,2,0,2); pGridLay.Parent=pGrid
    for _,c in ipairs(PRESETS) do local sw=Instance.new("TextButton"); sw.BackgroundColor3=c; sw.Text=""; sw.BorderSizePixel=0; sw.Parent=pGrid; sw.MouseButton1Click:Connect(function() C.PrimaryColor=colorToHex(c); PRIMARY=c; pPrev.BackgroundColor3=c; save(); scheduleRebuild() end) end
    lbl(themeTab,"— Secondary Color —",no()); local sPrev=Instance.new("Frame"); sPrev.Size=UDim2.new(1,0,0,24); sPrev.BackgroundColor3=SECONDARY; sPrev.BorderSizePixel=0; sPrev.LayoutOrder=no(); sPrev.Parent=themeTab
    local sHue=Instance.new("Frame"); sHue.Size=UDim2.new(1,0,0,18); sHue.BackgroundColor3=Color3.new(1,1,1); sHue.BorderSizePixel=0; sHue.LayoutOrder=no(); sHue.Parent=themeTab; local sHueGrad=pHueGrad:Clone(); sHueGrad.Parent=sHue
    sHue.InputBegan:Connect(function(input) if input.UserInputType~=Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.Touch then return end; local rel=(input.Position.X-sHue.AbsolutePosition.X)/sHue.AbsoluteSize.X; rel=math.clamp(rel,0,1); local c=Color3.fromHSV(rel,0.6,0.25); C.SecondaryColor=colorToHex(c); SECONDARY=c; sPrev.BackgroundColor3=c; save(); scheduleRebuild() end)
    local sGrid=Instance.new("Frame"); sGrid.Size=UDim2.new(1,0,0,84); sGrid.BackgroundTransparency=1; sGrid.LayoutOrder=no(); sGrid.Parent=themeTab
    local sGridLay=Instance.new("UIGridLayout"); sGridLay.CellSize=UDim2.new(0,20,0,20); sGridLay.CellPadding=UDim2.new(0,2,0,2); sGridLay.Parent=sGrid
    for _,c in ipairs(PRESETS) do local sw=Instance.new("TextButton"); sw.BackgroundColor3=c; sw.Text=""; sw.BorderSizePixel=0; sw.Parent=sGrid; sw.MouseButton1Click:Connect(function() C.SecondaryColor=colorToHex(c); SECONDARY=c; sPrev.BackgroundColor3=c; save(); scheduleRebuild() end) end
    btn(themeTab,"APPLY / REBUILD GUI",PRIMARY,Color3.fromRGB(0,0,0),no(),function() buildGui() end)

    tabs["Main"].btn.MouseButton1Click:Fire()
    
    return farmBtn
end

-- ============ INIT ============
LocalPlayer.CharacterAdded:Connect(function(ch)
    pdCache.data=nil; task.wait(0.5)
    local u=ch:FindFirstChildOfClass("Humanoid")
    if u then u.Died:Connect(function() local h=ch:FindFirstChild("HumanoidRootPart"); if h then pcall(function() h.Anchored=false end) end end) end
end)

statsTick()
if C.AntiAFK then startAFK() end
if C.AntiVoid then setupVoid() end
if C.AntiFling then startAntiFling() end
if C.Noclip then startNoclip() end
if C.HopAt>0 then hopMonitor() end

local farmBtnRef = buildGui()

-- Auto-launch: automatically start farming upon execution
task.spawn(function()
    task.wait(5)
    if not LocalPlayer.Character then LocalPlayer.CharacterAdded:Wait() end
    task.wait(2)
    
    if C.AutoLaunch then
        C.Farming = true
        farm()
        if farmBtnRef then
            farmBtnRef.BackgroundColor3 = PRIMARY
            farmBtnRef.Text = "ON"
            farmBtnRef.TextColor3 = Color3.fromRGB(0,0,0)
        end
    end
end)

print("[Lambda] v0.32 ready | HWID: "..HWID)
