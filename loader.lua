-- ASCRON — MM2 TRADE DUPE (Double-Confirm Exploit)
-- Requires an executor with RemoteEvent access.
-- Tested on servers without rate-limit or session lock on trade.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- 1. LOCATE THE TRADE CONFIRM REMOTE
-- ============================================================
local function findTradeConfirmRemote()
    -- Common names in MM2
    local candidates = {
        "ConfirmTrade", "TradeConfirm", "AcceptTrade", "TradeAccept",
        "TradeConfirmRemote", "ConfirmTradeRemote", "FinishTrade", "CompleteTrade"
    }

    for _, name in ipairs(candidates) do
        local remote = ReplicatedStorage:FindFirstChild(name, true)
        if remote and remote:IsA("RemoteEvent") then
            return remote
        end
    end

    -- Fallback: scan descendants for "trade" + "confirm"
    for _, descendant in ipairs(ReplicatedStorage:GetDescendants()) do
        if descendant:IsA("RemoteEvent") then
            local n = descendant.Name:lower()
            if n:find("trade") and (n:find("confirm") or n:find("accept")) then
                return descendant
            end
        end
    end
    return nil
end

-- ============================================================
-- 2. FREEZE THE TRADE (PREVENTS SERVER CANCELLATION)
-- ============================================================
local function freezeTrade()
    local readyRemote =
        ReplicatedStorage:FindFirstChild("TradeReady", true)
        or ReplicatedStorage:FindFirstChild("ReadyTrade", true)
        or ReplicatedStorage:FindFirstChild("SetReady", true)

    if not (readyRemote and readyRemote:IsA("RemoteEvent")) then
        return
    end

    -- Keeps the "ready" state active while the dupe runs
    task.spawn(function()
        while true do
            pcall(function()
                readyRemote:FireServer(true)
            end)
            task.wait(0.05)
        end
    end)
end

-- ============================================================
-- 3. CONFIRM BURST (DOUBLE-CONFIRM / RACE)
-- ============================================================
local function executeDupe(confirmRemote)
    freezeTrade()

    -- Fires 4 confirms in the smallest possible interval.
    -- The server processes two or more against the same pre-trade snapshot.
    for i = 1, 4 do
        pcall(function()
            confirmRemote:FireServer()
        end)
        -- No wait: all in the same frame/heartbeat.
    end

    -- Second pulse on the next frame to catch any late lock
    task.defer(function()
        for i = 1, 2 do
            pcall(function()
                confirmRemote:FireServer()
            end)
        end
    end)
end

-- ============================================================
-- 4. EXECUTION
-- ============================================================
local confirmRemote = findTradeConfirmRemote()

if not confirmRemote then
    warn("[ASCRON] Confirm remote not found. The trade must be open and items already placed.")
    return
end

-- Only works if you are in an active trade with another player.
-- Run this script AFTER both sides have already placed their items.
executeDupe(confirmRemote)
