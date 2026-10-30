-- ASCRON — MM2 TRADE DIAGNOSTIC
-- PRINTS ONLY. No GUI. No namecall hook. No OnClientInvoke touch.
-- Run with the target player in the SAME server.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Trade = RS:WaitForChild("Trade")
local LP = Players.LocalPlayer
local TARGET = "kerli1f"

local function out(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring(select(i, ...))
    end
    print(table.concat(parts, " "))
end

out("============================================")
out("[DIAG] MM2 TRADE DIAGNOSTIC")
out("============================================")

local target = Players:FindFirstChild(TARGET)
if not target then
    out("[TARGET] '"..TARGET.."' NOT in this server.")
    out("[TARGET] Players actually in server:")
    for _, p in ipairs(Players:GetPlayers()) do
        out("  - "..p.Name)
    end
    out("[DIAG] STOP. Trade requires both players in the same server.")
    return
end

out("[TARGET] found:", target.Name, "UserId:", target.UserId)
out("[SELF]  ", LP.Name, "UserId:", LP.UserId, "AccountAge:", LP.AccountAge, "days")

-- 1. SendRequest
out("--- SendRequest ---")
do
    local sr = Trade:FindFirstChild("SendRequest")
    if not sr then
        out("SendRequest MISSING")
    else
        local ok, res = pcall(function() return sr:InvokeServer(target) end)
        out("InvokeServer(Player) ->", ok and "OK" or "ERR", tostring(res))
        task.wait(0.3)
        local ok2, res2 = pcall(function() return sr:InvokeServer(target.UserId) end)
        out("InvokeServer(UserId) ->", ok2 and "OK" or "ERR", tostring(res2))
    end
end

-- 2. Listen for StartTrade for 3s
out("--- Waiting 3s for StartTrade ---")
local opened = false
do
    local st = Trade:FindFirstChild("StartTrade")
    if st then
        local conn
        conn = st.OnClientEvent:Connect(function(...)
            opened = true
            out("[StartTrade] args:", ...)
            if conn then conn:Disconnect() end
        end)
    end
    task.wait(3)
    if not opened then
        out("[StartTrade] NOT fired — server did not open trade.")
    end
end

-- 3. GetTradeStatus variations
out("--- GetTradeStatus probes ---")
do
    local gts = Trade:FindFirstChild("GetTradeStatus")
    if gts then
        local tests = {
            {"Player", target},
            {"UserId", target.UserId},
            {"Self",   LP},
            {"SelfUID",LP.UserId},
        }
        for _, t in ipairs(tests) do
            local ok, res = pcall(function() return gts:InvokeServer(t[2]) end)
            out("GTS("..t[1]..") ->", ok and "OK" or "ERR", tostring(res))
            task.wait(0.2)
        end
    end
end

-- 4. Server settings
out("--- Server settings ---")
do
    local extras = RS:FindFirstChild("Remotes") and RS.Remotes:FindFirstChild("Extras")
    local ss = extras and extras:FindFirstChild("GetServerSettings")
    if ss and ss:IsA("RemoteFunction") then
        local ok, res = pcall(function() return ss:InvokeServer() end)
        out("GetServerSettings ->", ok and "OK" or "ERR", tostring(res))
        if ok and type(res) == "table" then
            for k, v in pairs(res) do
                out("  "..tostring(k).." = "..tostring(v))
            end
        end
    else
        out("GetServerSettings not found")
    end
end

-- 5. Version
out("--- Version ---")
do
    local extras = RS:FindFirstChild("Remotes") and RS.Remotes:FindFirstChild("Extras")
    local gv = extras and extras:FindFirstChild("GetVersion")
    if gv and gv:IsA("RemoteFunction") then
        local ok, res = pcall(function() return gv:InvokeServer() end)
        out("GetVersion ->", ok and "OK" or "ERR", tostring(res))
    end
end

out("============================================")
out("[DIAG] DONE — copy everything from [DIAG] to here")
out("============================================")
