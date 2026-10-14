local _, ns = ...

-- Counts the player's kills from the combat log, when the client allows it; stored after combat.
local Kills = {}
ns.Kills = Kills

local CLEU = "COMBAT_LOG_EVENT_UNFILTERED"
local BUFFER_MAX = 500

local Safe = ns.Store.Safe

local status = "unavailable"
local frame, playerGUID
local buffer = {}

local function isSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

-- Caches the player GUID once the client reports it; it may be missing at ADDON_LOADED.
local function player()
    playerGUID = playerGUID or (UnitGUID and Safe(UnitGUID("player")))
    return playerGUID
end

-- Registers the combat log under pcall (it may be forbidden) and the events that flush the buffer.
function Kills.Register(f)
    frame = f
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("PLAYER_LOGOUT")
    player()
    if not CombatLogGetCurrentEventInfo then
        status = "unavailable"
        return
    end
    local ok = pcall(f.RegisterEvent, f, CLEU)
    status = ok and "on" or "blocked"
end

function Kills.OnCombatLog()
    if status ~= "on" then
        return
    end
    local _, sub, _, src, _, _, _, dst = CombatLogGetCurrentEventInfo()
    if isSecret(sub) or isSecret(src) or isSecret(dst) then
        status = "secret"
        pcall(frame.UnregisterEvent, frame, CLEU)
        buffer = {}
        return
    end
    if sub ~= "PARTY_KILL" or not player() or src ~= playerGUID then
        return
    end
    local kind, id = ns.Store.ParseGUID(dst)
    if kind == "c" and #buffer < BUFFER_MAX then
        buffer[#buffer + 1] = id
    end
end

-- Stores the buffered kills unless in combat; force writes them anyway (logout or /reload).
function Kills.Flush(force)
    if not force and InCombatLockdown and InCombatLockdown() then
        return
    end
    for _, id in ipairs(buffer) do
        ns.Store.AddKill(id)
    end
    buffer = {}
end

-- Returns "on", "unavailable", "blocked" or "secret".
function Kills.Status()
    return status
end
