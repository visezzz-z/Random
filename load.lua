-- Lambda Hub | v0.51 | MM2 Script by kerli
-- Removed: Server Hop. Fixed: Shoot Murderer (pure remote fire, no fling),
-- Silent Aim + Piercer (robust namecall redirect).

if getgenv().LAMBDA_RUNNING then
    pcall(function()
        if getgenv().LAMBDA_NOTIF_GUI then
            local holder = getgenv().LAMBDA_NOTIF_GUI:FindFirstChildOfClass("Frame")
            if holder then
                local n = Instance.new("Frame")
                n.Size = UDim2.new(1, 0, 0, 50)
                n.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
                n.Parent = holder
                local t = Instance.new("TextLabel")
                t.Size = UDim2.new(1,0,1,0)
                t.BackgroundTransparency = 1
                t.Text = "Lambda Hub: Already running! Close the GUI to re-execute."
                t.TextColor3 = Color3.fromRGB(255, 100, 100)
                t.Font = Enum.Font.GothamBold
                t.TextSize = 12
                t.Parent = n
                task.delay(3, function() pcall(function() n:Destroy() end) end)
            end
        end
    end)
    print("[Lambda] Already running.")
    return
end
getgenv().LAMBDA_RUNNING = true

print("[Lambda] v0.51 loading")

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local VirtualUser = game:GetService("VirtualUser")
local VirtualInputManager = game:GetService("VirtualInputManager")
local UIS = game:GetService("UserInputService")
local Stats = game:GetService("Stats")
local LocalPlayer = Players.LocalPlayer

-- ============ NOTIFICATIONS ============
local function setupNotifications()
    if getgenv().LAMBDA_NOTIF_GUI then pcall(function() getgenv().LAMBDA_NOTIF_GUI:Destroy() end) end
    local notifGui = Instance.new("ScreenGui")
    notifGui.Name = "LambdaNotifs"
    notifGui.ResetOnSpawn = false
    notifGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    notifGui.DisplayOrder = 999998
    pcall(function() notifGui.Parent = gethui and gethui() or game.CoreGui end)
    getgenv().LAMBDA_NOTIF_GUI = notifGui
    local notifContainer = Instance.new("Frame")
    notifContainer.Size = UDim2.new(0, 300, 1, 0)
    notifContainer.Position = UDim2.new(1, -320, 0, 0)
    notifContainer.BackgroundTransparency = 1
    notifContainer.Parent = notifGui
    local notifLayout = Instance.new("UIListLayout")
    notifLayout.Padding = UDim.new(0, 5)
    notifLayout.VerticalAlignment = Enum.VerticalAlignment.Top
    notifLayout.SortOrder = Enum.SortOrder.LayoutOrder
    notifLayout.Parent = notifContainer
end
local function notify(title, desc, dur)
    if not getgenv().LAMBDA_NOTIF_GUI then setupNotifications() end
    local notifGui = getgenv().LAMBDA_NOTIF_GUI
    if not notifGui then return end
    local notifContainer = notifGui:FindFirstChildOfClass("Frame")
    if not notifContainer then return end
    local n = Instance.new("Frame")
    n.Size = UDim2.new(1, 0, 0, 50)
    n.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
    n.BackgroundTransparency = 0.1
    n.BorderSizePixel = 0
    n.Parent = notifContainer
    local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 6); corner.Parent = n
    local stroke = Instance.new("UIStroke"); stroke.Color = Color3.fromRGB(255,200,0); stroke.Thickness=1; stroke.Transparency=0.5; stroke.Parent=n
    local ttl = Instance.new("TextLabel")
    ttl.Size = UDim2.new(1, -10, 0, 18); ttl.Position = UDim2.new(0, 5, 0, 4); ttl.BackgroundTransparency=1
    ttl.Text = title; ttl.TextColor3 = Color3.fromRGB(255,200,0); ttl.Font=Enum.Font.GothamBold; ttl.TextSize=12
    ttl.TextXAlignment=Enum.TextXAlignment.Left; ttl.Parent=n
    local dsc = Instance.new("TextLabel")
    dsc.Size = UDim2.new(1, -10, 0, 18); dsc.Position = UDim2.new(0, 5, 0, 24); dsc.BackgroundTransparency=1
    dsc.Text = desc; dsc.TextColor3 = Color3.fromRGB(220,220,220); dsc.Font=Enum.Font.Gotham; dsc.TextSize=11
    dsc.TextXAlignment=Enum.TextXAlignment.Left; dsc.Parent=n
    task.delay(dur or 3, function()
        TweenService:Create(n, TweenInfo.new(0.3), {BackgroundTransparency=1}):Play()
        TweenService:Create(stroke, TweenInfo.new(0.3), {Transparency=1}):Play()
        TweenService:Create(ttl, TweenInfo.new(0.3), {TextTransparency=1}):Play()
        TweenService:Create(dsc, TweenInfo.new(0.3), {TextTransparency=1}):Play()
        task.wait(0.3)
        pcall(function() n:Destroy() end)
    end)
end
setupNotifications()
notify("Lambda Hub", "Initializing Archives...", 2)

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
    Language="English",
    Currency="Coin", Speed=35, FarmMode="Stealth", Depth=3, AuraRadius=12, CoinAura=true,
    AutoLaunch=true, AutoGrabGun=true, GuiScale=1.0,
    Farming=false,
    AntiAFK=true, AntiVoid=true, AntiFling=true, Noclip=true, AntiMurderer=false,
    Disable3D=false, VoteMode=0, VoteMax=0,
    ResetInnocent=true, FlingMurderer=false, ShootSheriff=true, ResetAnyRole=false,
    KillMurderer=true, ResetMurderer=false, Threshold=50, ResetAfterAction=true,
    AutoShootAttempts=3,
    SilentAim=false, Piercer=false, PredMode="Auto",
    TouchFling=false, SecondLife=false,
    StatsTotal=0,
    PrimaryColor="#FFC800", SecondaryColor="#15151C",
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
C.GuiScale = math.clamp(tonumber(C.GuiScale) or 1.0, 0.4, 1.6)

C.FarmThread=nil
C.VoteThread=nil
C.LastFull=tick(); C.Cooldown=0
C.IntentionalReset=false
C.Stats={Total=tonumber(C.StatsTotal) or 0, Start=tick(), Last=0}
C.MissCount=0; C.WasInRound=false
C.CollectFails=0
C.LastGunGrab=0
C.FlingTarget=nil
C.FarmStatus="idle"
C.LastShot=0
C.ShotsFired=0

local function save() local t={} for k,_ in pairs(DEFAULTS) do t[k]=C[k] end prefsSave(t) end

local function isKineticBusy()
    local s = C.FarmStatus
    return s=="manual fling" or s=="flinging murderer" or s=="flinging" or s=="fling all" or s=="fling done"
end

-- ============ LANGUAGE ============
local TR = {
English = {
    tab_main="Main", tab_combat="Combat", tab_visuals="Visuals", tab_misc="Misc", tab_theme="Theme",
    auto_farm="AUTO FARM", auto_farm_desc="Collects currency, starts on execute", auto_launch="Auto-launch on execute",
    telemetry="Telemetry", harvest="Harvest", currency="Currency", travel_speed="Travel speed", farm_mode="Farm mode",
    stealth_depth="Stealth depth", coin_aura="Coin Aura", aura_radius="Aura radius", bag_threshold="Bag threshold",
    st_collected="Collected", st_shots="Shots", st_bag="Bag", st_fails="Fails", st_status="Status",
    snap_engine="Shoot Engine", auto_snap="Auto shoot murderer on full bag",
    max_attempts="Max attempts", snap_now="SHOOT MURDERER NOW", silent_piercer="Silent Aim & Piercer",
    silent_aim="Silent Aim", silent_aim_desc="Shots redirect to the murderer", piercer="Piercer Bullet",
    piercer_desc="Shots ignore walls", prediction="Prediction",
    fling="Fling", fling_murderer="Fling murderer on full bag", fling_target="Manual fling target",
    fling_selected="FLING SELECTED TARGET", fling_all="FLING ALL IN SERVER", ward="Touch Fling & Second Life",
    touch_fling="Touch Fling", touch_fling_desc="Anyone who touches you gets flung", second_life="Second Life",
    second_life_desc="Rejoin the server when you die", roles="Roles", elim_all="Murderer: eliminate all",
    auto_grab="Auto grab dropped gun", reset_full="Reset when full", reset_after="Reset after action", no_target="No target",
    v_murderer="Murderer", v_sheriff="Sheriff", v_hero="Hero", v_innocents="Innocents", v_coins="Coins & Pickups",
    v_guns="Dropped Guns", f_box="Box + Name", f_tracer="Tracer", f_chams="Chams", f_outline="Outline", f_glow="Glow", f_3dbox="3D Box",
    protections="Protections", anti_afk="Anti-AFK", anti_void="Anti-Void", anti_fling="Anti-Fling",
    anti_murderer="Anti-Murderer", noclip="Noclip", disable3d="Disable 3D rendering", map_vote="Map Vote",
    vote_mode="Vote mode", max_votes="Max votes (0 = inf)", language="Language",
    v_off="OFF", v_smallest="Smallest Map", v_largest="Largest Map", v_random="Random",
    gui_scale="GUI Scale", scale="Scale (0.4 - 1.6)", themes="Themes", primary="Primary Color",
    secondary="Secondary Color", rebuild="APPLY & REBUILD",
},
Russian = {
    tab_main="Главная", tab_combat="Бой", tab_visuals="Визуал", tab_misc="Прочее", tab_theme="Тема",
    auto_farm="АВТО ФАРМ", auto_farm_desc="Собирает валюту, стартует сразу", auto_launch="Автозапуск при выполнении",
    telemetry="Статистика", harvest="Сбор", currency="Валюта", travel_speed="Скорость движения", farm_mode="Режим фарма",
    stealth_depth="Глубина (стелс)", coin_aura="Аура монет", aura_radius="Радиус ауры", bag_threshold="Порог сумки",
    st_collected="Собрано", st_shots="Выстрелы", st_bag="Сумка", st_fails="Провалы", st_status="Статус",
    snap_engine="Стрельба", auto_snap="Авто-выстрел в убийцу при полной сумке",
    max_attempts="Попытки", snap_now="ВЫСТРЕЛ В УБИЙЦУ", silent_piercer="Скрытый прицел и пробитие",
    silent_aim="Скрытый прицел", silent_aim_desc="Пули летят в убийцу", piercer="Пробитие стен",
    piercer_desc="Выстрелы проходят сквозь стены", prediction="Предсказание",
    fling="Флинг", fling_murderer="Флинг убийцы при полной сумке", fling_target="Цель флинга",
    fling_selected="ФЛИНГ ЦЕЛИ", fling_all="ФЛИНГ ВСЕХ", ward="Тач-флинг и вторая жизнь",
    touch_fling="Тач-флинг", touch_fling_desc="Кто коснётся тебя — улетит", second_life="Вторая жизнь",
    second_life_desc="Перезайти на сервер после смерти", roles="Роли", elim_all="Убийца: убить всех",
    auto_grab="Авто-подбор пистолета", reset_full="Сброс при полной сумке", reset_after="Сброс после действия", no_target="Нет цели",
    v_murderer="Убийца", v_sheriff="Шериф", v_hero="Герой", v_innocents="Невиновные", v_coins="Монеты и предметы",
    v_guns="Пистолеты на земле", f_box="Бокс + имя", f_tracer="Трейсер", f_chams="Чамсы", f_outline="Обводка", f_glow="Свечение", f_3dbox="3D бокс",
    protections="Защита", anti_afk="Анти-АФК", anti_void="Анти-войд", anti_fling="Анти-флинг",
    anti_murderer="Анти-убийца", noclip="Noclip", disable3d="Отключить 3D", map_vote="Голосование за карту",
    vote_mode="Режим", max_votes="Макс. голосов (0 = ∞)", language="Язык",
    v_off="ВЫКЛ", v_smallest="Маленькая карта", v_largest="Большая карта", v_random="Случайно",
    gui_scale="Масштаб GUI", scale="Масштаб (0.4 - 1.6)", themes="Темы", primary="Основной цвет",
    secondary="Цвет фона", rebuild="ПРИМЕНИТЬ",
},
Finnish = {
    tab_main="Pää", tab_combat="Taistelu", tab_visuals="Näkymät", tab_misc="Muut", tab_theme="Teema",
    auto_farm="AUTOFARM", auto_farm_desc="Kerää valuuttaa, käynnistyy heti", auto_launch="Automaattikäynnistys",
    telemetry="Tilastot", harvest="Keräys", currency="Valuutta", travel_speed="Liikenopeus", farm_mode="Farm-tila",
    stealth_depth="Stealth-syvyys", coin_aura="Kolikkoaura", aura_radius="Auran säde", bag_threshold="Laukun raja",
    st_collected="Kerätty", st_shots="Laukaukset", st_bag="Laukku", st_fails="Virheet", st_status="Tila",
    snap_engine="Ampuminen", auto_snap="Ammu murhaaja automaattisesti täydestä laukusta",
    max_attempts="Yritykset", snap_now="AMMU MURHAAJA NYT", silent_piercer="Silent Aim & Piercer",
    silent_aim="Silent Aim", silent_aim_desc="Laukaukset ohjautuvat murhaajaan", piercer="Piercer",
    piercer_desc="Laukaukset menevät seinien läpi", prediction="Ennuste",
    fling="Fling", fling_murderer="Flingaa murhaaja täydestä laukusta", fling_target="Fling-kohde",
    fling_selected="FLINGAA VALITTU", fling_all="FLINGAA KAIKKI", ward="Touch Fling & Toinen elämä",
    touch_fling="Touch Fling", touch_fling_desc="Sinuun koskeva pelaaja lentää", second_life="Toinen elämä",
    second_life_desc="Liity palvelimeen uudelleen kuoltuasi", roles="Roolit", elim_all="Murhaaja: tapa kaikki",
    auto_grab="Poimi pudonnut ase automaattisesti", reset_full="Reset kun laukku täynnä", reset_after="Reset toiminnon jälkeen", no_target="Ei kohdetta",
    v_murderer="Murhaaja", v_sheriff="Seriffi", v_hero="Sankari", v_innocents="Viattomat", v_coins="Kolikot ja tavarat",
    v_guns="Pudotetut aseet", f_box="Boksi + nimi", f_tracer="Viiva", f_chams="Chamsit", f_outline="Ääriviivat", f_glow="Hehku", f_3dbox="3D-boksi",
    protections="Suojaus", anti_afk="Anti-AFK", anti_void="Anti-Void", anti_fling="Anti-Fling",
    anti_murderer="Anti-Murderer", noclip="Noclip", disable3d="Poista 3D-renderöinti", map_vote="Karttaäänestys",
    vote_mode="Äänestystila", max_votes="Maksimiäänet (0 = rajaton)", language="Kieli",
    v_off="POIS", v_smallest="Pienin kartta", v_largest="Suurin kartta", v_random="Satunnainen",
    gui_scale="GUI-koko", scale="Koko (0.4 - 1.6)", themes="Teemat", primary="Pääväri",
    secondary="Taustaväri", rebuild="TALLETA & UUDELLEENRAKENNA",
},
German = {
    tab_main="Haupt", tab_combat="Kampf", tab_visuals="Sicht", tab_misc="Sonstiges", tab_theme="Design",
    auto_farm="AUTO-FARM", auto_farm_desc="Sammelt Währung, startet sofort", auto_launch="Autostart bei Ausführung",
    telemetry="Statistik", harvest="Sammeln", currency="Währung", travel_speed="Geschwindigkeit", farm_mode="Farm-Modus",
    stealth_depth="Stealth-Tiefe", coin_aura="Münz-Aura", aura_radius="Aura-Radius", bag_threshold="Taschen-Limit",
    st_collected="Gesammelt", st_shots="Schüsse", st_bag="Tasche", st_fails="Fehler", st_status="Status",
    snap_engine="Schuss-Engine", auto_snap="Auto-Schuss auf Mörder bei voller Tasche",
    max_attempts="Versuche", snap_now="MÖRDER JETZT SCHIESSEN", silent_piercer="Silent Aim & Piercer",
    silent_aim="Silent Aim", silent_aim_desc="Schüsse treffen den Mörder", piercer="Piercer",
    piercer_desc="Schüsse durchdringen Wände", prediction="Vorhersage",
    fling="Fling", fling_murderer="Mörder bei voller Tasche flingen", fling_target="Fling-Ziel",
    fling_selected="ZIEL FLINGEN", fling_all="ALLE FLINGEN", ward="Touch Fling & Zweites Leben",
    touch_fling="Touch Fling", touch_fling_desc="Wer dich berührt, wird weggeschleudert", second_life="Zweites Leben",
    second_life_desc="Nach dem Tod neu beitreten", roles="Rollen", elim_all="Mörder: alle eliminieren",
    auto_grab="Waffe automatisch aufheben", reset_full="Reset bei voller Tasche", reset_after="Reset nach Aktion", no_target="Kein Ziel",
    v_murderer="Mörder", v_sheriff="Sheriff", v_hero="Held", v_innocents="Unschuldige", v_coins="Münzen & Items",
    v_guns="Waffen am Boden", f_box="Box + Name", f_tracer="Linie", f_chams="Chams", f_outline="Kontur", f_glow="Glow", f_3dbox="3D-Box",
    protections="Schutzfunktionen", anti_afk="Anti-AFK", anti_void="Anti-Void", anti_fling="Anti-Fling",
    anti_murderer="Anti-Mörder", noclip="Noclip", disable3d="3D-Rendering aus", map_vote="Kartenwahl",
    vote_mode="Wahlmodus", max_votes="Max. Stimmen (0 = unendlich)", language="Sprache",
    v_off="AUS", v_smallest="Kleinste Karte", v_largest="Größte Karte", v_random="Zufällig",
    gui_scale="GUI-Größe", scale="Größe (0.4 - 1.6)", themes="Designs", primary="Hauptfarbe",
    secondary="Hintergrundfarbe", rebuild="ANWENDEN & NEU AUFBAUEN",
},
}
local function L(key)
    local t = TR[C.Language] or TR["English"]
    return t[key] or TR["English"][key] or key
end

-- ============ COLORS ============
local function parseHex(s)
    s=tostring(s or ""):gsub("#","")
    if #s~=6 then return nil end
    local n=tonumber(s,16); if not n then return nil end
    return Color3.fromRGB(bit32.rshift(bit32.band(n,0xFF0000),16), bit32.rshift(bit32.band(n,0x00FF00),8), bit32.band(n,0x0000FF))
end
local function colorToHex(c) return string.format("#%02X%02X%02X", math.floor(c.R*255+.5), math.floor(c.G*255+.5), math.floor(c.B*255+.5)) end
local PRIMARY = parseHex(C.PrimaryColor) or Color3.fromRGB(255,200,0)
local SECONDARY = parseHex(C.SecondaryColor) or Color3.fromRGB(21,21,28)
local INSET = Color3.fromRGB(18,18,24)
local CELL = Color3.fromRGB(26,26,34)
local TEXT_DIM = Color3.fromRGB(140,140,150)
local TEXT_BRIGHT = Color3.fromRGB(228,228,235)
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

-- ============ PROTECTIONS ============
local afkConn
local function startAFK()
    if afkConn then afkConn:Disconnect() end
    afkConn=LocalPlayer.Idled:Connect(function()
        pcall(function() VirtualUser:CaptureController(); VirtualUser:ClickButton2(Vector2.new(0,0)) end)
    end)
end
local voidConn; local origDH=Workspace.FallenPartsDestroyHeight
local function setupVoid()
    if not C.AntiVoid then Workspace.FallenPartsDestroyHeight=origDH; if voidConn then voidConn:Disconnect(); voidConn=nil end; return end
    Workspace.FallenPartsDestroyHeight=0/0
    if voidConn then voidConn:Disconnect() end
    voidConn=LocalPlayer.CharacterAdded:Connect(function() task.wait(0.1); Workspace.FallenPartsDestroyHeight=0/0 end)
end
local function startAntiFling()
    local lastP,lastT=nil,tick(); local lastC=nil
    RunService.Heartbeat:Connect(function()
        if not C.AntiFling then return end
        if isKineticBusy() then lastP=nil; return end
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
local noclipConn
local function startNoclip()
    if noclipConn then noclipConn:Disconnect() end
    noclipConn=RunService.Stepped:Connect(function()
        if not C.Noclip then return end
        if isKineticBusy() then return end
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
    if not coin then return end
    for i, p in ipairs(coinCache.parts) do if p == coin then table.remove(coinCache.parts, i); break end end
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
    reanchorAfterTouch(bv,bg,wasA,curU)
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
    return got
end

-- ============ AUTO GRAB GUN ============
local function rawGunTool()
    local ch=LocalPlayer.Character
    local t=ch and ch:FindFirstChild("Gun")
    if t and t:IsA("Tool") then return t end
    local bp=LocalPlayer:FindFirstChild("Backpack")
    t=bp and bp:FindFirstChild("Gun")
    if t and t:IsA("Tool") then return t end
    return nil
end
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
local function equipGun()
    local gun=rawGunTool()
    if not gun then return nil end
    local ch=LocalPlayer.Character
    if gun.Parent~=ch and ch then
        local u=HUM()
        if u then pcall(function() u:EquipTool(gun) end) task.wait(0.15) end
    end
    return gun
end
local function grabGun()
    if not C.AutoGrabGun then return false end
    if tick()-C.LastGunGrab<5 then return false end
    local ch=LocalPlayer.Character; if not ch then return false end
    if rawGunTool() then return false end
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
local function flingTarget(targetPlayer, returnHome)
    if returnHome == nil then returnHome = true end
    local myChar = LocalPlayer.Character
    local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local myHum = myChar and myChar:FindFirstChildOfClass("Humanoid")
    local tChar = targetPlayer and targetPlayer.Character
    local tHRP = tChar and tChar:FindFirstChild("HumanoidRootPart")
    if not (myHRP and tHRP and tHRP.Parent) then return false end
    local backCF = myHRP.CFrame
    if myHum then pcall(function() myHum:ChangeState(Enum.HumanoidStateType.Physics) end) end
    local bav = Instance.new("BodyAngularVelocity")
    bav.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    bav.AngularVelocity = Vector3.new(0, 99999, 0)
    bav.Parent = myHRP
    local start = tick()
    while tick() - start < 2.5 do
        tChar = targetPlayer.Character
        tHRP = tChar and tChar:FindFirstChild("HumanoidRootPart")
        if not myHRP.Parent then break end
        if not (tHRP and tHRP.Parent) then break end
        local tHum = tChar:FindFirstChildOfClass("Humanoid")
        if tHum and tHum.Health <= 0 then break end
        pcall(function()
            myHRP.CFrame = tHRP.CFrame
            myHRP.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        end)
        RunService.Heartbeat:Wait()
    end
    pcall(function() bav:Destroy() end)
    if myHRP.Parent then
        myHRP.AssemblyLinearVelocity = Vector3.zero
        myHRP.AssemblyAngularVelocity = Vector3.zero
        if returnHome then myHRP.CFrame = backCF + Vector3.new(0, 3, 0) end
    end
    if returnHome and myHum and myHum.Parent then
        pcall(function() myHum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
    end
    return true
end
local function restoreToOrigin(originCF)
    local h = HRP()
    if h and h.Parent and originCF then
        h.AssemblyLinearVelocity = Vector3.zero
        h.AssemblyAngularVelocity = Vector3.zero
        h.CFrame = originCF + Vector3.new(0, 3, 0)
    end
    local hum = HUM()
    if hum and hum.Parent then pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end) end
end
local function flingLoop(targetPlayer)
    C.FarmStatus = "flinging"
    local originCF = HRP() and HRP().CFrame
    local deadline = tick() + 8
    while tick() < deadline do
        local tChar = targetPlayer.Character
        if not tChar then break end
        local tHum = tChar:FindFirstChildOfClass("Humanoid")
        if not tHum or tHum.Health <= 0 then break end
        flingTarget(targetPlayer, false)
        task.wait(0.3)
    end
    restoreToOrigin(originCF)
    C.FarmStatus = "fling done"
end
local function flingAll()
    task.spawn(function()
        C.FarmStatus = "fling all"
        local originCF = HRP() and HRP().CFrame
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character then
                local hum = p.Character:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    flingTarget(p, false)
                    task.wait(0.3)
                end
            end
        end
        restoreToOrigin(originCF)
        C.FarmStatus = "fling done"
    end)
end

-- ============ SHOOT ENGINE (pure remote fire, no fling) ============
local SERVER_SHOT_CD = 3.25
local function getPing()
    local ok, ping = pcall(function() return Stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
    return (ok and ping) or 100
end
local function pickHitPart(char)
    if not char then return nil end
    return char:FindFirstChild("Head") or char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or char:FindFirstChild("HumanoidRootPart")
end
local function predictPos(part)
    if not part then return nil end
    local base = part.Position
    local mode = C.PredMode or "Auto"
    if mode == "Off" then return base end
    local vel = part.AssemblyLinearVelocity or Vector3.zero
    local t = 0
    if mode == "Auto" then
        local h = HRP()
        local dist = h and (h.Position - base).Magnitude or 30
        t = (getPing()/1000)*0.5 + dist/1100
    else
        local mult = tonumber(tostring(mode):gsub("x","")) or 1
        t = mult * (getPing()/1000)
    end
    t = math.clamp(t, 0, 0.5)
    return base + vel*t
end
local function collectGunRemotes()
    local found = {}
    local gun = rawGunTool()
    if not gun then return found end
    local function scan(inst, depth)
        if depth > 4 then return end
        local ok, children = pcall(function() return inst:GetChildren() end)
        if not ok then return end
        for _, d in ipairs(children) do
            if d:IsA("RemoteEvent") then table.insert(found, d) end
            if depth < 4 then scan(d, depth+1) end
        end
    end
    pcall(function() scan(gun, 0) end)
    return found
end
local function shootMurderer()
    local murderer = findMurderer()
    if not murderer or not murderer.Character then return false end
    local mHum = murderer.Character:FindFirstChildOfClass("Humanoid")
    if not mHum or mHum.Health <= 0 then return true end
    local target = pickHitPart(murderer.Character)
    if not target then return false end
    local gun = equipGun()
    if not gun then return false end

    C.FarmStatus = "shooting"

    local cam = workspace.CurrentCamera
    if cam then
        pcall(function() cam.CFrame = CFrame.new(cam.CFrame.Position, target.Position) end)
    end
    task.wait(0.05)

    pcall(function() gun:Activate() end)

    local remotes = collectGunRemotes()
    for _, rem in ipairs(remotes) do
        pcall(function() rem:FireServer(target, target.Position) end)
        pcall(function() rem:FireServer(target.Position, target) end)
        pcall(function() rem:FireServer(target.Position) end)
        pcall(function() rem:FireServer(target) end)
    end

    C.LastShot = tick()
    C.ShotsFired = C.ShotsFired + 1
    return true
end
local function shootMurdererAuto()
    local attempts = math.clamp(tonumber(C.AutoShootAttempts) or 3, 1, 6)
    for i = 1, attempts do
        local m = findMurderer()
        if not m then return true end
        local mh = m.Character and m.Character:FindFirstChildOfClass("Humanoid")
        if not mh or mh.Health <= 0 then return true end
        local myu = HUM()
        if not myu or myu.Health <= 0 then return false end
        shootMurderer()
        task.wait(SERVER_SHOT_CD)
        mh = m.Character and m.Character:FindFirstChildOfClass("Humanoid")
        if not mh or mh.Health <= 0 then return true end
        if not findMurderer() then return true end
    end
    return not findMurderer()
end

-- ============ SILENT AIM / PIERCER / ANTI-MURDERER HOOK ============
pcall(function()
    if not (getrawmetatable and setreadonly and newcclosure) then return end
    local mt = getrawmetatable(game)
    local oldNC = mt.__namecall
    local oldNI = mt.__newindex
    setreadonly(mt, false)
    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        if method == "FireServer" and (C.SilentAim or C.Piercer) and not C.IntentionalReset then
            local isGun = false
            pcall(function()
                if typeof(self) == "Instance" and self:IsA("RemoteEvent") then
                    local gun = rawGunTool()
                    if gun and self:IsDescendantOf(gun) then isGun = true end
                    local n = self.Name:lower()
                    if n:find("shoot") or n:find("fire") or n:find("gun") or n:find("shot") then isGun = true end
                end
            end)
            if isGun then
                local murderer = findMurderer()
                if murderer and murderer.Character then
                    local part = pickHitPart(murderer.Character)
                    if part then
                        local pos = predictPos(part) or part.Position
                        local args = {...}
                        local n = select("#", ...)
                        for i = 1, n do
                            local v = args[i]
                            if typeof(v) == "Instance" and v:IsA("BasePart") then
                                args[i] = part
                            elseif typeof(v) == "Vector3" then
                                args[i] = pos
                            elseif typeof(v) == "CFrame" then
                                args[i] = CFrame.new(pos)
                            end
                        end
                        return oldNC(self, table.unpack(args, 1, n))
                    end
                end
            end
        end
        if C.AntiMurderer and not C.IntentionalReset then
            local hum = HUM()
            if hum and self == hum then
                if method == "TakeDamage" then return 0 end
                if method == "ChangeState" then local a = {...}; if a[1] == Enum.HumanoidStateType.Dead then return nil end end
            end
        end
        return oldNC(self, ...)
    end)
    mt.__newindex = newcclosure(function(self, key, value)
        if C.AntiMurderer and not C.IntentionalReset then
            local hum = HUM()
            if hum and self == hum and key == "Health" and value <= 0 then if murdererNearby() then return end end
        end
        return oldNI(self, key, value)
    end)
    setreadonly(mt, true)
end)

-- ============ FULL BAG ============
local function fullBag()
    local r=role(); local did=false
    local h=HRP(); if h then h.Anchored=false end
    local u=HUM(); if u then u.PlatformStand=false; u.AutoRotate=true end
    if r=="Innocent" then
        if C.FlingMurderer then
            local m=findMurderer()
            if m then C.FarmStatus="flinging murderer"; flingLoop(m); did=true end
        end
        if C.ResetInnocent then hardReset(); return end
        if did then return end
    elseif r=="Sheriff" or r=="Hero" then
        if C.ShootSheriff then C.FarmStatus="shooting"; shootMurdererAuto(); did=true end
    elseif r=="Murderer" then
        if C.KillMurderer then killAll(); did=true end
        if C.ResetMurderer and not did then hardReset(); return end
    end
    if did and C.ResetAfterAction then task.wait(1.5); hardReset(); return end
    if C.ResetAnyRole then hardReset() end
end

-- ============ STATS ============
local function statsTick()
    task.spawn(function()
        LocalPlayer:WaitForChild("leaderstats",10); task.wait(1)
        C.Stats.Last=statValue() or 0
        local saveCounter=0
        while true do
            task.wait(0.5)
            local v=statValue()
            if v and C.Stats.Last and v>C.Stats.Last then C.Stats.Total=C.Stats.Total+(v-C.Stats.Last) end
            if v then C.Stats.Last=v end
            saveCounter=saveCounter+1
            if saveCounter>=8 then saveCounter=0; C.StatsTotal=C.Stats.Total; save() end
        end
    end)
end
local function rate() local e=math.max(1,tick()-C.Stats.Start); return math.floor((C.Stats.Total/e)*3600) end

-- ============ ROUND WATCHER ============
task.spawn(function()
    local lastC=nil
    while true do
        task.wait(0.15)
        local ch=LocalPlayer.Character
        if ch~=lastC then lastC=ch; C.MissCount=0; C.WasInRound=false end
        local h=ch and ch:FindFirstChild("HumanoidRootPart"); local u=ch and ch:FindFirstChildOfClass("Humanoid")
        if C.Farming and h and u then
            local busy = isKineticBusy()
            if h.Position.Y<-150 and not busy then C.FarmStatus="fell"; hardReset(); C.Cooldown=tick()+3; C.MissCount=0; C.WasInRound=false; continue end
            local outside=isDeadOrOutOfRound()
            if not outside then C.WasInRound=true; C.MissCount=0
            elseif C.WasInRound and not busy then C.MissCount=C.MissCount+1
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
            if not rawGunTool() and findGunDropPart() then grabGun(); task.wait(0.3) end
        end
        local coin=nearestCoin()
        if coin then
            task.spawn(function()
                local conn
                conn = coin.AncestryChanged:Connect(function()
                    if not coin.Parent then removeCoinFromCache(coin); if conn.Connected then conn:Disconnect() end end
                end)
                task.delay(4, function() if conn and conn.Connected then conn:Disconnect() end end)
            end)
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
            if got then C.CollectFails=0; removeCoinFromCache(coin)
            elseif coin.Parent then blacklist(coin); C.CollectFails=C.CollectFails+1
            else C.CollectFails=0 end
            coinCache.ts = 0
            task.wait(0.01)
        else C.FarmStatus="no coins"; cleanup(); task.wait(0.3) end
        local st=statValue()
        if st and st>=threshold() and tick()-C.LastFull>3 then C.LastFull=tick(); C.FarmStatus="full bag"; fullBag() end
    end
    C.FarmStatus="idle"
    C.Farming=false
    C.FarmThread=nil
end
local function farm()
    if C.FarmThread and coroutine.status(C.FarmThread) ~= "dead" then return end
    C.Farming=true; C.FarmStatus="starting"
    C.FarmThread=task.spawn(farmLoopFn)
end
local function stopFarm()
    C.Farming=false; C.FarmStatus="idle"
    if C.FarmThread then pcall(function() task.cancel(C.FarmThread) end); C.FarmThread=nil end
    cleanup()
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

-- ============ VISUALS ENGINE ============
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
local MAIN_GUI
local PRESETS={Color3.fromRGB(255,0,0),Color3.fromRGB(255,100,0),Color3.fromRGB(255,200,0),Color3.fromRGB(180,255,0),Color3.fromRGB(0,255,0),Color3.fromRGB(0,255,180),Color3.fromRGB(0,255,255),Color3.fromRGB(0,180,255),Color3.fromRGB(0,100,255),Color3.fromRGB(0,0,255),Color3.fromRGB(100,0,255),Color3.fromRGB(180,0,255),Color3.fromRGB(255,0,255),Color3.fromRGB(255,0,180),Color3.fromRGB(255,0,100),Color3.fromRGB(255,255,255),Color3.fromRGB(200,200,200),Color3.fromRGB(128,128,128),Color3.fromRGB(64,64,64),Color3.fromRGB(30,30,30),Color3.fromRGB(0,0,0),Color3.fromRGB(150,75,0),Color3.fromRGB(255,180,150),Color3.fromRGB(80,40,20)}
local THEMES={
    {name="Gold",p=Color3.fromRGB(255,200,0),s=Color3.fromRGB(21,21,28)},
    {name="Ocean",p=Color3.fromRGB(0,180,255),s=Color3.fromRGB(16,24,36)},
    {name="Forest",p=Color3.fromRGB(80,200,80),s=Color3.fromRGB(16,26,18)},
    {name="Rose",p=Color3.fromRGB(255,100,150),s=Color3.fromRGB(30,18,24)},
    {name="Cyber",p=Color3.fromRGB(255,0,180),s=Color3.fromRGB(14,14,32)},
    {name="Mono",p=Color3.fromRGB(220,220,220),s=Color3.fromRGB(20,20,20)},
}
local function corner(o,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r or 6); c.Parent=o; return c end
local function strokeOf(o,col,th,tr)
    local s=Instance.new("UIStroke"); s.Color=col or Color3.fromRGB(255,255,255); s.Thickness=th or 1; s.Transparency=tr or 0.75
    s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; s.Parent=o; return s
end
local FAST_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local guiRefs = nil

local function buildGui()
    if MAIN_GUI then pcall(function() MAIN_GUI:Destroy() end) end
    local parent=guiParent(); if not parent then return nil end
    local gui=Instance.new("ScreenGui"); gui.Name="LambdaHub"; gui.ResetOnSpawn=false; gui.IgnoreGuiInset=true; gui.DisplayOrder=999999
    pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)
    gui.Parent=parent; MAIN_GUI=gui

    local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
    local isMobile = UIS.TouchEnabled and not UIS.MouseEnabled
    local ROOT_W, ROOT_H
    if isMobile then
        ROOT_W = math.clamp(math.floor(vp.X * 0.94), 300, 430)
        ROOT_H = math.clamp(math.floor(vp.Y * 0.80), 340, 560)
    else
        ROOT_W = 410
        ROOT_H = math.clamp(math.floor(vp.Y * 0.76), 430, 580)
    end
    local TITLE_H, SIDE_W, MIN_STATS_H = 30, 64, 50

    local root=Instance.new("Frame")
    root.Size=UDim2.fromOffset(ROOT_W,ROOT_H)
    root.AnchorPoint=Vector2.new(0.5,0.5)
    root.Position=UDim2.fromScale(0.5,0.5)
    root.BackgroundColor3=SECONDARY
    root.BackgroundTransparency=0.02
    root.BorderSizePixel=0
    root.Active=true; root.Draggable=true
    root.Parent=gui
    corner(root,10)
    strokeOf(root,PRIMARY,1.5,0.6)

    local uiScale = Instance.new("UIScale")
    uiScale.Parent = root
    uiScale.Scale = C.GuiScale

    local titleBar=Instance.new("Frame"); titleBar.Size=UDim2.new(1,0,0,TITLE_H); titleBar.BackgroundTransparency=1; titleBar.Parent=root
    local dot=Instance.new("Frame"); dot.Size=UDim2.fromOffset(9,9); dot.Position=UDim2.new(0,10,0.5,-4); dot.BackgroundColor3=PRIMARY; dot.BorderSizePixel=0; dot.Parent=titleBar; corner(dot,5)
    local title=Instance.new("TextLabel"); title.Size=UDim2.new(0,70,1,0); title.Position=UDim2.new(0,24,0,0); title.BackgroundTransparency=1; title.Text="LAMBDA"; title.TextColor3=TEXT_BRIGHT; title.Font=Enum.Font.GothamBold; title.TextSize=13; title.TextXAlignment=Enum.TextXAlignment.Left; title.Parent=titleBar
    local ver=Instance.new("TextLabel"); ver.Size=UDim2.new(0,40,1,0); ver.Position=UDim2.new(0,84,0,1); ver.BackgroundTransparency=1; ver.Text="v0.51"; ver.TextColor3=PRIMARY; ver.Font=Enum.Font.GothamBold; ver.TextSize=9; ver.TextXAlignment=Enum.TextXAlignment.Left; ver.Parent=titleBar

    local function winBtn(xOff, txt, bg, cb)
        local b=Instance.new("TextButton"); b.Size=UDim2.fromOffset(22,18); b.Position=UDim2.new(1,xOff,0.5,-9); b.BackgroundColor3=bg; b.BackgroundTransparency=0.35; b.Text=txt; b.TextColor3=Color3.fromRGB(255,255,255); b.Font=Enum.Font.GothamBold; b.TextSize=11; b.BorderSizePixel=0; b.AutoButtonColor=false; b.Parent=titleBar; corner(b,4)
        b.MouseButton1Click:Connect(cb)
        return b
    end

    local minBar=Instance.new("Frame"); minBar.Size=UDim2.new(1,-10,0,MIN_STATS_H); minBar.Position=UDim2.new(0,5,0,TITLE_H); minBar.BackgroundColor3=INSET; minBar.BackgroundTransparency=0.1; minBar.BorderSizePixel=0; minBar.Visible=false; minBar.Parent=root; corner(minBar,7)
    strokeOf(minBar, PRIMARY, 1, 0.8)
    local minStats=Instance.new("TextLabel"); minStats.Size=UDim2.new(1,-10,1,-4); minStats.Position=UDim2.new(0,5,0,2); minStats.BackgroundTransparency=1; minStats.TextColor3=PRIMARY; minStats.Font=Enum.Font.Code; minStats.TextSize=10; minStats.TextXAlignment=Enum.TextXAlignment.Left; minStats.TextYAlignment=Enum.TextYAlignment.Top; minStats.TextWrapped=true; minStats.Text=""; minStats.Parent=minBar

    local sidebar=Instance.new("Frame"); sidebar.Size=UDim2.new(0,SIDE_W,1,-TITLE_H-5); sidebar.Position=UDim2.new(0,0,0,TITLE_H+2); sidebar.BackgroundTransparency=1; sidebar.Parent=root
    local sideLay=Instance.new("UIListLayout"); sideLay.Padding=UDim.new(0,2); sideLay.SortOrder=Enum.SortOrder.LayoutOrder; sideLay.Parent=sidebar
    local sidePad=Instance.new("UIPadding"); sidePad.PaddingLeft=UDim.new(0,4); sidePad.PaddingTop=UDim.new(0,2); sidePad.Parent=sidebar

    local content=Instance.new("Frame"); content.Size=UDim2.new(1,-SIDE_W-7,1,-TITLE_H-7); content.Position=UDim2.new(0,SIDE_W+3,0,TITLE_H+3); content.BackgroundTransparency=1; content.Parent=root

    local tabs={}
    local function selectTab(name)
        for n,t in pairs(tabs) do
            t.frame.Visible = false
            TweenService:Create(t.btn,FAST_TWEEN,{BackgroundTransparency=1}):Play()
            t.btn.TextColor3=TEXT_DIM
        end
        local t = tabs[name]
        if t then
            t.frame.Visible = true
            TweenService:Create(t.btn,FAST_TWEEN,{BackgroundTransparency=0.85}):Play()
            t.btn.TextColor3=PRIMARY
        end
    end
    local function newTab(name, ord)
        local b=Instance.new("TextButton"); b.Size=UDim2.new(1,-4,0,25); b.BackgroundColor3=PRIMARY; b.BackgroundTransparency=1; b.Text=name; b.TextColor3=TEXT_DIM; b.Font=Enum.Font.GothamMedium; b.TextSize=9; b.BorderSizePixel=0; b.AutoButtonColor=false; b.LayoutOrder=ord; b.Parent=sidebar; corner(b,6)
        local f=Instance.new("ScrollingFrame"); f.Size=UDim2.new(1,0,1,0); f.BackgroundTransparency=1; f.BorderSizePixel=0; f.ScrollBarThickness=2; f.ScrollBarImageColor3=PRIMARY; f.ScrollBarImageTransparency=0.5; f.ScrollingEnabled=true
        f.CanvasSize=UDim2.new(0,0,0,0); f.AutomaticCanvasSize=Enum.AutomaticSize.Y; f.Visible=false; f.Parent=content
        local l=Instance.new("UIListLayout"); l.Padding=UDim.new(0,2); l.SortOrder=Enum.SortOrder.LayoutOrder; l.Parent=f
        local p=Instance.new("UIPadding"); p.PaddingTop=UDim.new(0,2); p.PaddingLeft=UDim.new(0,2); p.PaddingRight=UDim.new(0,4); p.PaddingBottom=UDim.new(0,8); p.Parent=f
        tabs[name]={btn=b,frame=f,list=l}
        b.MouseButton1Click:Connect(function() selectTab(name) end)
        return f
    end

    local mainTab    = newTab(L("tab_main"),1)
    local combatTab  = newTab(L("tab_combat"),2)
    local visualsTab = newTab(L("tab_visuals"),3)
    local miscTab    = newTab(L("tab_misc"),4)
    local themeTab   = newTab(L("tab_theme"),5)

    local function section(par,txt,ord)
        local f=Instance.new("Frame"); f.Size=UDim2.new(1,0,0,13); f.BackgroundTransparency=1; f.LayoutOrder=ord; f.Parent=par
        local l=Instance.new("TextLabel"); l.Size=UDim2.new(0,#txt*6+10,1,0); l.BackgroundTransparency=1; l.Text=string.upper(txt); l.TextColor3=PRIMARY; l.TextTransparency=0.1; l.Font=Enum.Font.GothamBold; l.TextSize=9; l.TextXAlignment=Enum.TextXAlignment.Left; l.Parent=f
        local line=Instance.new("Frame"); line.Size=UDim2.new(1,-(#txt*6+16),0,1); line.Position=UDim2.new(0,#txt*6+14,0.5,0); line.BackgroundColor3=Color3.fromRGB(255,255,255); line.BackgroundTransparency=0.88; line.BorderSizePixel=0; line.Parent=f
        return f
    end
    local function toggleSwitch(par,txt,desc,init,ord,cb)
        local hgt = desc and 30 or 21
        local row=Instance.new("Frame"); row.Size=UDim2.new(1,0,0,hgt); row.BackgroundTransparency=1; row.LayoutOrder=ord; row.Parent=par
        local l=Instance.new("TextLabel"); l.BackgroundTransparency=1; l.Text=txt; l.TextColor3=TEXT_BRIGHT; l.Font=Enum.Font.GothamMedium; l.TextSize=10; l.TextXAlignment=Enum.TextXAlignment.Left; l.TextTruncate=Enum.TextTruncate.AtEnd
        if desc then
            l.Size=UDim2.new(1,-44,0,12); l.Position=UDim2.new(0,2,0,1)
            local d=Instance.new("TextLabel"); d.Size=UDim2.new(1,-44,0,12); d.Position=UDim2.new(0,2,0,15); d.BackgroundTransparency=1; d.Text=desc; d.TextColor3=TEXT_DIM; d.Font=Enum.Font.Gotham; d.TextSize=8; d.TextXAlignment=Enum.TextXAlignment.Left; d.TextTruncate=Enum.TextTruncate.AtEnd; d.Parent=row
        else
            l.Size=UDim2.new(1,-44,1,0); l.Position=UDim2.new(0,2,0,0)
        end
        l.Parent=row
        local track=Instance.new("TextButton"); track.Size=UDim2.fromOffset(32,17); track.Position=UDim2.new(1,-36,0.5,-8); track.BackgroundColor3=init and PRIMARY or Color3.fromRGB(48,48,56); track.BorderSizePixel=0; track.Text=""; track.AutoButtonColor=false; track.Parent=row; corner(track,9)
        local knob=Instance.new("Frame"); knob.Size=UDim2.fromOffset(11,11); knob.BackgroundColor3=init and Color3.fromRGB(18,18,22) or Color3.fromRGB(235,235,240); knob.BorderSizePixel=0; knob.Position=init and UDim2.new(1,-14,0.5,-5) or UDim2.new(0,3,0.5,-5); knob.Parent=track; corner(knob,6)
        local st=init
        local function apply(s,instant)
            st=s
            local ti=instant and TweenInfo.new(0) or FAST_TWEEN
            TweenService:Create(track,ti,{BackgroundColor3=s and PRIMARY or Color3.fromRGB(48,48,56)}):Play()
            TweenService:Create(knob,ti,{Position=s and UDim2.new(1,-14,0.5,-5) or UDim2.new(0,3,0.5,-5), BackgroundColor3=s and Color3.fromRGB(18,18,22) or Color3.fromRGB(235,235,240)}):Play()
        end
        track.MouseButton1Click:Connect(function() apply(not st); pcall(function() cb(st) end); save() end)
        return {set=function(s) apply(s,true) end, row=row}
    end
    local function miniToggle(txt, init, cb)
        local row=Instance.new("Frame"); row.BackgroundColor3=CELL; row.BackgroundTransparency=0.35; row.BorderSizePixel=0; corner(row,5)
        local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,-32,1,0); l.Position=UDim2.new(0,5,0,0); l.BackgroundTransparency=1; l.Text=txt; l.TextColor3=TEXT_BRIGHT; l.Font=Enum.Font.Gotham; l.TextSize=9; l.TextXAlignment=Enum.TextXAlignment.Left; l.TextTruncate=Enum.TextTruncate.AtEnd; l.Parent=row
        local track=Instance.new("TextButton"); track.Size=UDim2.fromOffset(24,13); track.Position=UDim2.new(1,-28,0.5,-6); track.BackgroundColor3=init and PRIMARY or Color3.fromRGB(48,48,56); track.BorderSizePixel=0; track.Text=""; track.AutoButtonColor=false; track.Parent=row; corner(track,7)
        local knob=Instance.new("Frame"); knob.Size=UDim2.fromOffset(9,9); knob.BackgroundColor3=init and Color3.fromRGB(18,18,22) or Color3.fromRGB(235,235,240); knob.BorderSizePixel=0; knob.Position=init and UDim2.new(1,-11,0.5,-4) or UDim2.new(0,2,0.5,-4); knob.Parent=track; corner(knob,5)
        local st=init
        track.MouseButton1Click:Connect(function()
            st=not st
            TweenService:Create(track,FAST_TWEEN,{BackgroundColor3=st and PRIMARY or Color3.fromRGB(48,48,56)}):Play()
            TweenService:Create(knob,FAST_TWEEN,{Position=st and UDim2.new(1,-11,0.5,-4) or UDim2.new(0,2,0.5,-4)}):Play()
            pcall(function() cb(st) end); save()
        end)
        return row
    end
    local function visualGrid(par,catName,features,ord)
        local rows = math.ceil(#features/2)
        local grid=Instance.new("Frame"); grid.Size=UDim2.new(1,0,0,rows*19+(rows-1)*3+2); grid.BackgroundTransparency=1; grid.LayoutOrder=ord; grid.Parent=par
        local lay=Instance.new("UIGridLayout"); lay.CellSize=UDim2.new(0.5,-2,0,19); lay.CellPadding=UDim2.new(0,4,0,3); lay.Parent=grid
        for _,feat in ipairs(features) do
            local key="Visuals_"..feat[2].."_"..catName
            if C[key]==nil then C[key]=false end
            local cell=miniToggle(feat[1], C[key], function(s) C[key]=s; rebuildVisualCache() end)
            cell.Parent=grid
        end
        return grid
    end
    local function numInput(par,label,val,minV,maxV,ord,cb)
        local row=Instance.new("Frame"); row.Size=UDim2.new(1,0,0,21); row.BackgroundTransparency=1; row.LayoutOrder=ord; row.Parent=par
        local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,-62,1,0); l.Position=UDim2.new(0,2,0,0); l.BackgroundTransparency=1; l.Text=label; l.TextColor3=TEXT_BRIGHT; l.Font=Enum.Font.Gotham; l.TextSize=10; l.TextXAlignment=Enum.TextXAlignment.Left; l.TextTruncate=Enum.TextTruncate.AtEnd; l.Parent=row
        local box=Instance.new("TextBox"); box.Size=UDim2.fromOffset(56,17); box.Position=UDim2.new(1,-60,0.5,-8); box.BackgroundColor3=INSET; box.BorderSizePixel=0; box.Text=tostring(val); box.PlaceholderText="val"; box.TextColor3=PRIMARY; box.PlaceholderColor3=TEXT_DIM; box.Font=Enum.Font.GothamMedium; box.TextSize=10; box.ClearTextOnFocus=false; box.Parent=row; corner(box,5); strokeOf(box,Color3.fromRGB(255,255,255),1,0.9)
        box.FocusLost:Connect(function()
            local n=tonumber(box.Text)
            if n then if minV then n=math.clamp(n,minV,maxV) end; pcall(function() cb(n) end); box.Text=tostring(n) else box.Text=tostring(val) end
            save()
        end)
        return row
    end
    local function cycleBtn(par,label,opts,init,ord,cb)
        local row=Instance.new("Frame"); row.Size=UDim2.new(1,0,0,21); row.BackgroundTransparency=1; row.LayoutOrder=ord; row.Parent=par
        local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,-98,1,0); l.Position=UDim2.new(0,2,0,0); l.BackgroundTransparency=1; l.Text=label; l.TextColor3=TEXT_BRIGHT; l.Font=Enum.Font.Gotham; l.TextSize=10; l.TextXAlignment=Enum.TextXAlignment.Left; l.TextTruncate=Enum.TextTruncate.AtEnd; l.Parent=row
        local b=Instance.new("TextButton"); b.Size=UDim2.fromOffset(92,17); b.Position=UDim2.new(1,-96,0.5,-8); b.BackgroundColor3=INSET; b.BorderSizePixel=0; b.TextColor3=PRIMARY; b.Font=Enum.Font.GothamMedium; b.TextSize=9; b.AutoButtonColor=false; b.Parent=row; corner(b,5); strokeOf(b,Color3.fromRGB(255,255,255),1,0.9)
        local i=findIdx(opts,init); b.Text=tostring(opts[i])
        b.MouseButton1Click:Connect(function() i=i%#opts+1; b.Text=tostring(opts[i]); pcall(function() cb(opts[i]) end); save() end)
        return {set=function(v) i=findIdx(opts,v); b.Text=tostring(opts[i]) end}
    end
    local function actionBtn(par,label,bg,fg,ord,cb)
        local b=Instance.new("TextButton"); b.Size=UDim2.new(1,0,0,23); b.BackgroundColor3=bg; b.BackgroundTransparency=0.08; b.BorderSizePixel=0; b.Text=label; b.TextColor3=fg; b.Font=Enum.Font.GothamBold; b.TextSize=10; b.LayoutOrder=ord; b.AutoButtonColor=false; b.Parent=par; corner(b,6)
        b.MouseButton1Click:Connect(cb)
        return b
    end
    local function hint(par,txt,ord,ht)
        local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,0,ht or 16); l.BackgroundTransparency=1; l.Text=txt; l.TextColor3=TEXT_DIM; l.Font=Enum.Font.Gotham; l.TextSize=8; l.TextXAlignment=Enum.TextXAlignment.Left; l.TextYAlignment=Enum.TextYAlignment.Top; l.TextWrapped=true; l.LayoutOrder=ord; l.Parent=par
        return l
    end
    local function playerDrop(par,label,ord,cb)
        local row=Instance.new("Frame"); row.Size=UDim2.new(1,0,0,21); row.BackgroundTransparency=1; row.LayoutOrder=ord; row.Parent=par
        local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,-80,1,0); l.Position=UDim2.new(0,2,0,0); l.BackgroundTransparency=1; l.Text=label; l.TextColor3=TEXT_BRIGHT; l.Font=Enum.Font.Gotham; l.TextSize=10; l.TextXAlignment=Enum.TextXAlignment.Left; l.TextTruncate=Enum.TextTruncate.AtEnd; l.Parent=row
        local b=Instance.new("TextButton"); b.Size=UDim2.fromOffset(74,17); b.Position=UDim2.new(1,-78,0.5,-8); b.BackgroundColor3=INSET; b.BorderSizePixel=0; b.TextColor3=PRIMARY; b.Font=Enum.Font.GothamMedium; b.TextSize=9; b.Text=L("no_target"); b.AutoButtonColor=false; b.Parent=row; corner(b,5); strokeOf(b,Color3.fromRGB(255,255,255),1,0.9)
        local players={}; local idx=0
        b.MouseButton1Click:Connect(function()
            players={}; for _,p in ipairs(Players:GetPlayers()) do if p~=LocalPlayer then table.insert(players,p) end end
            if #players==0 then b.Text=L("no_target"); return end
            idx=idx%#players+1
            if idx==0 then b.Text=L("no_target"); cb(nil) else b.Text=players[idx].Name; cb(players[idx]) end
            save()
        end)
        return row
    end

    local o=0; local function no() o=o+1; return o end

    -- ===== MAIN =====
    local farmSwitch = toggleSwitch(mainTab,L("auto_farm"),L("auto_farm_desc"),C.Farming,no(),function(s) if s then C.FarmThread=nil; farm() else stopFarm() end end)
    toggleSwitch(mainTab,L("auto_launch"),nil,C.AutoLaunch,no(),function(s) C.AutoLaunch=s end)

    section(mainTab,L("telemetry"),no())
    local statsPanel=Instance.new("Frame"); statsPanel.Size=UDim2.new(1,0,0,40); statsPanel.BackgroundColor3=INSET; statsPanel.BackgroundTransparency=0.1; statsPanel.BorderSizePixel=0; statsPanel.LayoutOrder=no(); statsPanel.Parent=mainTab; corner(statsPanel,6); strokeOf(statsPanel,PRIMARY,1,0.8)
    local statsLabel=Instance.new("TextLabel"); statsLabel.Size=UDim2.new(1,-8,1,-4); statsLabel.Position=UDim2.new(0,4,0,2); statsLabel.BackgroundTransparency=1; statsLabel.TextColor3=PRIMARY; statsLabel.Font=Enum.Font.Code; statsLabel.TextSize=10; statsLabel.TextXAlignment=Enum.TextXAlignment.Left; statsLabel.TextYAlignment=Enum.TextYAlignment.Top; statsLabel.TextWrapped=true; statsLabel.Text=""; statsLabel.Parent=statsPanel
    task.spawn(function()
        while statsLabel and statsLabel.Parent do
            task.wait(0.5)
            local b=statValue()
            local txt=string.format("%s: %d | %d/h | %s: %d\n%s: %s/%d | %s: %d\n%s: %s",
                L("st_collected"), C.Stats.Total, rate(), L("st_shots"), C.ShotsFired,
                L("st_bag"), b and tostring(b) or "?", threshold(), L("st_fails"), C.CollectFails,
                L("st_status"), tostring(C.FarmStatus or "idle"))
            statsLabel.Text=txt
            if minStats and minStats.Parent then minStats.Text=txt end
        end
    end)

    section(mainTab,L("harvest"),no())
    cycleBtn(mainTab,L("currency"),{"Coin","Candy","SnowToken","Token","Shell"},C.Currency,no(),function(v) C.Currency=v end)
    numInput(mainTab,L("travel_speed"),C.Speed,10,70,no(),function(v) C.Speed=v end)
    cycleBtn(mainTab,L("farm_mode"),{"Stealth","Standard","Lay"},C.FarmMode,no(),function(v) C.FarmMode=v end)
    numInput(mainTab,L("stealth_depth"),C.Depth,1,8,no(),function(v) C.Depth=v end)
    toggleSwitch(mainTab,L("coin_aura"),nil,C.CoinAura,no(),function(s) C.CoinAura=s end)
    numInput(mainTab,L("aura_radius"),C.AuraRadius,5,25,no(),function(v) C.AuraRadius=v end)
    numInput(mainTab,L("bag_threshold"),C.Threshold,0,999,no(),function(v) C.Threshold=v end)

    -- ===== COMBAT =====
    o=0
    section(combatTab,L("snap_engine"),no())
    toggleSwitch(combatTab,L("auto_snap"),nil,C.ShootSheriff,no(),function(s) C.ShootSheriff=s end)
    numInput(combatTab,L("max_attempts"),C.AutoShootAttempts,1,6,no(),function(v) C.AutoShootAttempts=v end)
    actionBtn(combatTab,L("snap_now"),PRIMARY,Color3.fromRGB(0,0,0),no(),function()
        local m=findMurderer(); if not m then C.FarmStatus="no murderer"; return end
        task.spawn(function() shootMurderer() end)
    end)

    section(combatTab,L("silent_piercer"),no())
    toggleSwitch(combatTab,L("silent_aim"),L("silent_aim_desc"),C.SilentAim,no(),function(s) C.SilentAim=s end)
    toggleSwitch(combatTab,L("piercer"),L("piercer_desc"),C.Piercer,no(),function(s) C.Piercer=s end)
    cycleBtn(combatTab,L("prediction"),{"Off","Auto","0.5x","1x","1.5x","2x"},C.PredMode,no(),function(v) C.PredMode=v end)

    section(combatTab,L("fling"),no())
    toggleSwitch(combatTab,L("fling_murderer"),nil,C.FlingMurderer,no(),function(s) C.FlingMurderer=s end)
    playerDrop(combatTab,L("fling_target"),no(),function(p) C.FlingTarget=p end)
    actionBtn(combatTab,L("fling_selected"),PRIMARY,Color3.fromRGB(0,0,0),no(),function()
        local t=C.FlingTarget; if not t or not t.Character then local m=findMurderer(); if m then t=m else return end end
        if t and t.Character then C.FarmStatus="manual fling"; task.spawn(function() flingLoop(t) end) end
    end)
    actionBtn(combatTab,L("fling_all"),Color3.fromRGB(200,60,60),Color3.fromRGB(255,255,255),no(),function() flingAll() end)

    section(combatTab,L("ward"),no())
    toggleSwitch(combatTab,L("touch_fling"),L("touch_fling_desc"),C.TouchFling,no(),function(s) C.TouchFling=s end)
    toggleSwitch(combatTab,L("second_life"),L("second_life_desc"),C.SecondLife,no(),function(s) C.SecondLife=s end)

    section(combatTab,L("roles"),no())
    toggleSwitch(combatTab,L("elim_all"),nil,C.KillMurderer,no(),function(s) C.KillMurderer=s end)
    toggleSwitch(combatTab,L("auto_grab"),nil,C.AutoGrabGun,no(),function(s) C.AutoGrabGun=s end)
    toggleSwitch(combatTab,L("reset_full"),nil,C.ResetInnocent,no(),function(s) C.ResetInnocent=s end)
    toggleSwitch(combatTab,L("reset_after"),nil,C.ResetAfterAction,no(),function(s) C.ResetAfterAction=s end)

    -- ===== VISUALS =====
    o=0
    local PLAYER_FEATS={{L("f_box"),"ESP"},{L("f_tracer"),"TR"},{L("f_chams"),"CH"},{L("f_outline"),"OL"},{L("f_glow"),"HL"},{L("f_3dbox"),"BX"}}
    local OBJ_FEATS={{L("f_3dbox"),"BX"},{L("f_chams"),"CH"},{L("f_outline"),"OL"},{L("f_glow"),"HL"}}
    section(visualsTab,L("v_murderer"),no())
    visualGrid(visualsTab,"Murderer",PLAYER_FEATS,no())
    section(visualsTab,L("v_sheriff"),no())
    visualGrid(visualsTab,"Sheriff",PLAYER_FEATS,no())
    section(visualsTab,L("v_hero"),no())
    visualGrid(visualsTab,"Hero",PLAYER_FEATS,no())
    section(visualsTab,L("v_innocents"),no())
    visualGrid(visualsTab,"Innocent",PLAYER_FEATS,no())
    section(visualsTab,L("v_coins"),no())
    visualGrid(visualsTab,"Coin",OBJ_FEATS,no())
    section(visualsTab,L("v_guns"),no())
    visualGrid(visualsTab,"Gun",OBJ_FEATS,no())

    -- ===== MISC =====
    o=0
    local langDisplay = {English="English", Russian="Русский", Finnish="Suomi", German="Deutsch"}
    local displayToInternal = {["English"]="English", ["Русский"]="Russian", ["Suomi"]="Finnish", ["Deutsch"]="German"}
    cycleBtn(miscTab,L("language"),{"English","Русский","Suomi","Deutsch"}, langDisplay[C.Language] or "English",no(),function(v)
        C.Language = displayToInternal[v] or "English"
        save()
        guiRefs = buildGui()
        if C.Farming and guiRefs and guiRefs.farmSwitch then guiRefs.farmSwitch.set(true) end
    end)
    section(miscTab,L("protections"),no())
    toggleSwitch(miscTab,L("anti_afk"),nil,C.AntiAFK,no(),function(s) C.AntiAFK=s; if s then startAFK() end end)
    toggleSwitch(miscTab,L("anti_void"),nil,C.AntiVoid,no(),function(s) C.AntiVoid=s; setupVoid() end)
    toggleSwitch(miscTab,L("anti_fling"),nil,C.AntiFling,no(),function(s) C.AntiFling=s end)
    toggleSwitch(miscTab,L("anti_murderer"),nil,C.AntiMurderer,no(),function(s) C.AntiMurderer=s end)
    toggleSwitch(miscTab,L("noclip"),nil,C.Noclip,no(),function(s) C.Noclip=s; if s then startNoclip() else stopNoclip() end end)
    toggleSwitch(miscTab,L("disable3d"),nil,C.Disable3D,no(),function(s) C.Disable3D=s; pcall(function() RunService:Set3dRenderingEnabled(not s) end) end)
    section(miscTab,L("map_vote"),no())
    local voteOptsDisp={L("v_off"),L("v_smallest"),L("v_largest"),L("v_random")}
    local voteDispToMode={[L("v_off")]=0,[L("v_smallest")]=1,[L("v_largest")]=2,[L("v_random")]=3}
    local voteModeToDisp={[0]=L("v_off"),[1]=L("v_smallest"),[2]=L("v_largest"),[3]=L("v_random")}
    cycleBtn(miscTab,L("vote_mode"),voteOptsDisp,voteModeToDisp[C.VoteMode] or voteOptsDisp[1],no(),function(v)
        C.VoteMode=voteDispToMode[v] or 0
        if C.VoteMode~=0 then startVote() else stopVote() end
    end)
    numInput(miscTab,L("max_votes"),C.VoteMax,0,99,no(),function(v) C.VoteMax=v end)

    -- ===== THEME =====
    o=0
    section(themeTab,L("gui_scale"),no())
    numInput(themeTab,L("scale"),C.GuiScale,0.4,1.6,no(),function(v) C.GuiScale=v; if uiScale then uiScale.Scale=v end end)
    section(themeTab,L("themes"),no())
    local themeRow=Instance.new("Frame"); themeRow.Size=UDim2.new(1,0,0,22); themeRow.BackgroundTransparency=1; themeRow.LayoutOrder=no(); themeRow.Parent=themeTab
    local themeLay=Instance.new("UIListLayout"); themeLay.FillDirection=Enum.FillDirection.Horizontal; themeLay.Padding=UDim.new(0,3); themeLay.Parent=themeRow
    for _,theme in ipairs(THEMES) do
        local tb=Instance.new("TextButton"); tb.Size=UDim2.new(0,44,1,0); tb.BackgroundColor3=theme.p; tb.BackgroundTransparency=0.1; tb.Text=theme.name; tb.TextColor3=Color3.fromRGB(0,0,0); tb.Font=Enum.Font.GothamBold; tb.TextSize=8; tb.BorderSizePixel=0; tb.AutoButtonColor=false; tb.Parent=themeRow; corner(tb,5)
        tb.MouseButton1Click:Connect(function() C.PrimaryColor=colorToHex(theme.p); C.SecondaryColor=colorToHex(theme.s); PRIMARY=theme.p; SECONDARY=theme.s; save(); guiRefs=buildGui(); if C.Farming and guiRefs and guiRefs.farmSwitch then guiRefs.farmSwitch.set(true) end end)
    end
    section(themeTab,L("primary"),no())
    local pPrev=Instance.new("Frame"); pPrev.Size=UDim2.new(1,0,0,14); pPrev.BackgroundColor3=PRIMARY; pPrev.BorderSizePixel=0; pPrev.LayoutOrder=no(); pPrev.Parent=themeTab; corner(pPrev,4)
    local pHue=Instance.new("TextButton"); pHue.Size=UDim2.new(1,0,0,12); pHue.BackgroundColor3=Color3.new(1,1,1); pHue.BorderSizePixel=0; pHue.Text=""; pHue.AutoButtonColor=false; pHue.LayoutOrder=no(); pHue.Parent=themeTab; corner(pHue,4)
    local pHueGrad=Instance.new("UIGradient"); pHueGrad.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(255,0,0)),ColorSequenceKeypoint.new(1/6,Color3.fromRGB(255,255,0)),ColorSequenceKeypoint.new(2/6,Color3.fromRGB(0,255,0)),ColorSequenceKeypoint.new(3/6,Color3.fromRGB(0,255,255)),ColorSequenceKeypoint.new(4/6,Color3.fromRGB(0,0,255)),ColorSequenceKeypoint.new(5/6,Color3.fromRGB(255,0,255)),ColorSequenceKeypoint.new(1,Color3.fromRGB(255,0,0))}); pHueGrad.Parent=pHue
    pHue.InputBegan:Connect(function(input)
        if input.UserInputType~=Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.Touch then return end
        local rel=(input.Position.X-pHue.AbsolutePosition.X)/math.max(1,pHue.AbsoluteSize.X); rel=math.clamp(rel,0,1)
        local c=Color3.fromHSV(rel,0.85,1); C.PrimaryColor=colorToHex(c); PRIMARY=c; pPrev.BackgroundColor3=c; save()
    end)
    local pGrid=Instance.new("Frame"); pGrid.Size=UDim2.new(1,0,0,34); pGrid.BackgroundTransparency=1; pGrid.LayoutOrder=no(); pGrid.Parent=themeTab
    local pGridLay=Instance.new("UIGridLayout"); pGridLay.CellSize=UDim2.new(0,14,0,14); pGridLay.CellPadding=UDim2.new(0,2,0,2); pGridLay.Parent=pGrid
    for _,c in ipairs(PRESETS) do
        local sw=Instance.new("TextButton"); sw.BackgroundColor3=c; sw.Text=""; sw.BorderSizePixel=0; sw.AutoButtonColor=false; sw.Parent=pGrid; corner(sw,3)
        sw.MouseButton1Click:Connect(function() C.PrimaryColor=colorToHex(c); PRIMARY=c; pPrev.BackgroundColor3=c; save(); guiRefs=buildGui(); if C.Farming and guiRefs and guiRefs.farmSwitch then guiRefs.farmSwitch.set(true) end end)
    end
    section(themeTab,L("secondary"),no())
    local sPrev=Instance.new("Frame"); sPrev.Size=UDim2.new(1,0,0,14); sPrev.BackgroundColor3=SECONDARY; sPrev.BorderSizePixel=0; sPrev.LayoutOrder=no(); sPrev.Parent=themeTab; corner(sPrev,4); strokeOf(sPrev,Color3.fromRGB(255,255,255),1,0.85)
    local sHue=Instance.new("TextButton"); sHue.Size=UDim2.new(1,0,0,12); sHue.BackgroundColor3=Color3.new(1,1,1); sHue.BorderSizePixel=0; sHue.Text=""; sHue.AutoButtonColor=false; sHue.LayoutOrder=no(); sHue.Parent=themeTab; corner(sHue,4)
    local sHueGrad=pHueGrad:Clone(); sHueGrad.Parent=sHue
    sHue.InputBegan:Connect(function(input)
        if input.UserInputType~=Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.Touch then return end
        local rel=(input.Position.X-sHue.AbsolutePosition.X)/math.max(1,sHue.AbsoluteSize.X); rel=math.clamp(rel,0,1)
        local c=Color3.fromHSV(rel,0.5,0.22); C.SecondaryColor=colorToHex(c); SECONDARY=c; sPrev.BackgroundColor3=c; save()
    end)
    local sGrid=Instance.new("Frame"); sGrid.Size=UDim2.new(1,0,0,34); sGrid.BackgroundTransparency=1; sGrid.LayoutOrder=no(); sGrid.Parent=themeTab
    local sGridLay=Instance.new("UIGridLayout"); sGridLay.CellSize=UDim2.new(0,14,0,14); sGridLay.CellPadding=UDim2.new(0,2,0,2); sGridLay.Parent=sGrid
    for _,c in ipairs(PRESETS) do
        local sw=Instance.new("TextButton"); sw.BackgroundColor3=c; sw.Text=""; sw.BorderSizePixel=0; sw.AutoButtonColor=false; sw.Parent=sGrid; corner(sw,3)
        sw.MouseButton1Click:Connect(function() C.SecondaryColor=colorToHex(c); SECONDARY=c; sPrev.BackgroundColor3=c; save(); guiRefs=buildGui(); if C.Farming and guiRefs and guiRefs.farmSwitch then guiRefs.farmSwitch.set(true) end end)
    end
    actionBtn(themeTab,L("rebuild"),PRIMARY,Color3.fromRGB(0,0,0),no(),function() guiRefs=buildGui(); if C.Farming and guiRefs and guiRefs.farmSwitch then guiRefs.farmSwitch.set(true) end end)

    local collapsed=false
    winBtn(-50,"—",Color3.fromRGB(70,70,80),function()
        collapsed=not collapsed
        if collapsed then
            root.Size=UDim2.fromOffset(ROOT_W,TITLE_H+MIN_STATS_H+6)
            sidebar.Visible=false; content.Visible=false; minBar.Visible=true
        else
            root.Size=UDim2.fromOffset(ROOT_W,ROOT_H)
            sidebar.Visible=true; content.Visible=true; minBar.Visible=false
        end
    end)
    winBtn(-26,"✕",Color3.fromRGB(150,40,40),function()
        for _,d in pairs(ESP.highlights) do pcall(function() d:Destroy() end) end
        for _,d in pairs(ESP.sboxes) do pcall(function() d:Destroy() end) end
        for _,d in pairs(ESP.coinHL) do pcall(function() d:Destroy() end) end
        for _,d in pairs(ESP.coinBX) do pcall(function() d:Destroy() end) end
        for _,d in pairs(ESP.gunHL) do pcall(function() d:Destroy() end) end
        for _,d in pairs(ESP.gunBX) do pcall(function() d:Destroy() end) end
        for _,t in pairs(ESP.draws) do for _,d in pairs(t) do pcall(function() d:Remove() end) end end
        save(); gui:Destroy(); MAIN_GUI=nil
        getgenv().LAMBDA_RUNNING = false
        notify("Lambda Hub", "GUI Closed. Safe to re-execute.", 2)
    end)

    selectTab(L("tab_main"))
    return {farmSwitch=farmSwitch}
end

local function dismissMobilePicker()
    if not UIS.TouchEnabled then return end
    if MAIN_GUI then MAIN_GUI.Enabled = false end
    local cam=workspace.CurrentCamera; local vp=cam and cam.ViewportSize or Vector2.new(800,600)
    for _=1,2 do
        pcall(function() VirtualInputManager:SendMouseButtonEvent(vp.X/2,vp.Y/2,0,true,game,0); task.wait(0.08); VirtualInputManager:SendMouseButtonEvent(vp.X/2,vp.Y/2,0,false,game,0) end)
        task.wait(0.4)
    end
    pcall(function() VirtualInputManager:SendKeyEvent(true,Enum.KeyCode.Return,false,game); task.wait(0.1); VirtualInputManager:SendKeyEvent(false,Enum.KeyCode.Return,false,game) end)
    if MAIN_GUI then MAIN_GUI.Enabled = true end
end

-- ============ CHARACTER HOOKS (Touch Fling + Second Life) ============
local touchDebounce = {}
local function setupCharacterHooks(char)
    local hum = char:FindFirstChildOfClass("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hum then
        hum.Died:Connect(function()
            if C.SecondLife and not C.IntentionalReset then
                task.wait(2)
                pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
            end
        end)
    end
    if hrp then
        hrp.Touched:Connect(function(hit)
            if not C.TouchFling then return end
            local otherChar = hit and hit.Parent
            if not otherChar then return end
            local otherHum = otherChar:FindFirstChildOfClass("Humanoid")
            local otherPlr = Players:GetPlayerFromCharacter(otherChar)
            if otherHum and otherPlr and otherPlr ~= LocalPlayer and otherHum.Health > 0 then
                local now = tick()
                if touchDebounce[otherPlr] and now - touchDebounce[otherPlr] < 2 then return end
                touchDebounce[otherPlr] = now
                task.spawn(function() flingTarget(otherPlr, true) end)
            end
        end)
    end
end

-- ============ INIT ============
LocalPlayer.CharacterAdded:Connect(function(ch)
    pdCache.data=nil; task.wait(0.5)
    setupCharacterHooks(ch)
    local u=ch:FindFirstChildOfClass("Humanoid")
    if u then u.Died:Connect(function() local h=ch:FindFirstChild("HumanoidRootPart"); if h then pcall(function() h.Anchored=false end) end end) end
end)
if LocalPlayer.Character then setupCharacterHooks(LocalPlayer.Character) end

statsTick()
if C.AntiAFK then startAFK() end
if C.AntiVoid then setupVoid() end
if C.AntiFling then startAntiFling() end
if C.Noclip then startNoclip() end
if C.Disable3D then pcall(function() RunService:Set3dRenderingEnabled(false) end) end

notify("Lambda Hub", "Constructing GUI...", 2)
guiRefs = buildGui()

local function tryAutoLaunch()
    if not C.AutoLaunch then return end
    if C.FarmThread and coroutine.status(C.FarmThread) ~= "dead" then return end
    C.FarmThread = nil
    farm()
    if guiRefs and guiRefs.farmSwitch then pcall(function() guiRefs.farmSwitch.set(true) end) end
end

task.spawn(function()
    task.wait(3)
    if not LocalPlayer.Character then LocalPlayer.CharacterAdded:Wait() end
    task.wait(1)
    dismissMobilePicker()
    tryAutoLaunch()
    task.wait(4)
    tryAutoLaunch()
    task.wait(6)
    tryAutoLaunch()
end)

notify("Lambda Hub", "Lambda Hub v0.51 Ready!", 4)
print("[Lambda] v0.51 ready | HWID: "..HWID)
