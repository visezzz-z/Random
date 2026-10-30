-- ASCRON — MM2 TRADE OBSERVER v3 (SAFE / NON-INTRUSIVE)
-- Hooks outbound only. Polls state. Does NOT touch OnClientInvoke.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Trade = RS:WaitForChild("Trade")
local LP = Players.LocalPlayer
local TARGET = "kerli1f"

local function out(tag, msg)
    print(string.format("[OBS][%-4s] %s", tag, msg))
end

-- ============================================================
-- STATE
-- ============================================================
local tradeState = "IDLE"
local lastProbe = 0
local probeInterval = 2.0

-- ============================================================
-- OUTBOUND HOOK (NO INBOUND TOUCH)
-- ============================================================
local hookOk, mt = pcall(getrawmetatable, game)
if hookOk and mt and hookmetamethod and getnamecallmethod and setreadonly then
    local oldNamecall = mt.__namecall
    setreadonly(mt, false)
    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()

        if method == "FireServer" or method == "InvokeServer" then
            local isRemote = typeof(self) == "Instance" and (
                self:IsA("RemoteEvent") or
                self:IsA("UnreliableRemoteEvent") or
                self:IsA("RemoteFunction")
            )

            if isRemote then
                local args = { ... }
                local argStr = {}
                for i, v in ipairs(args) do
                    if typeof(v) == "Instance" then
                        table.insert(argStr, string.format("[%d]Instance:%s", i, v:GetFullName()))
                    elseif type(v) == "table" then
                        local inner = {}
                        for k, vv in pairs(v) do
                            if type(k) == "number" then table.insert(inner, tostring(vv)) end
                        end
                        table.insert(argStr, string.format("[%d]table{%s}", i, table.concat(inner, ",")))
                    else
                        table.insert(argStr, string.format("[%d]%s:%s", i, typeof(v), tostring(v)))
                    end
                end

                out("OUT", string.format("%s:%s  %s", self:GetFullName(), method, table.concat(argStr, "  ")))

                -- Track state transitions for trade remotes
                if self:IsDescendantOf(Trade) then
                    if self.Name == "SendRequest" then
                        tradeState = "REQUEST_SENT"
                    elseif self.Name == "AcceptRequest" then
                        tradeState = "REQUEST_ACCEPTED"
                    elseif self.Name == "OfferItem" then
                        tradeState = "ITEMS_OFFERED"
                    elseif self.Name == "AcceptTrade" then
                        tradeState = "TRADE_ACCEPTED"
                    elseif self.Name == "CompleteTrade" then
                        tradeState = "COMPLETING"
                    end
                end

                local ok, result = pcall(oldNamecall, self, table.unpack(args))
                if not ok then
                    out("ERR", string.format("%s:%s -> %s", self.Name, method, tostring(result)))
                    error(result, 0)
                end
                if method == "InvokeServer" then
                    out("RET", string.format("%s -> %s", self.Name, tostring(result)))
                end
                return result
            end
        end

        return oldNamecall(self, ...)
    end)
    setreadonly(mt, true)
    out("HOOK", "namecall armed (outbound only).")
else
    out("HOOK", "FAILED — no metatable access.")
end

-- ============================================================
-- SAFE STATE PROBE (SYNCHRONOUS, NO SIDE EFFECTS)
-- ============================================================
local function probeState()
    if os.clock() - lastProbe < probeInterval then return end
    lastProbe = os.clock()

    local gts = Trade:FindFirstChild("GetTradeStatus")
    if not gts or not gts:IsA("RemoteFunction") then return end

    local ok, res = pcall(function()
        return gts:InvokeServer()
    end)

    if ok then
        out("STATE", string.format("GetTradeStatus -> %s", tostring(res)))
        if type(res) == "table" then
            for k, v in pairs(res) do
                out("STATE", string.format("  %s = %s", tostring(k), tostring(v)))
            end
        end
    else
        out("STATE", string.format("GetTradeStatus ERR -> %s", tostring(res)))
    end
end

-- ============================================================
-- LOOP
-- ============================================================
out("BOOT", "observer v3 online. target=" .. TARGET)
out("BOOT", "tradeState=" .. tradeState)

task.spawn(function()
    while true do
        probeState()
        task.wait(0.5)
    end
end)
