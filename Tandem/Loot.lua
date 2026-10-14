local _, ns = ...

-- Logs each looted item once per source and counts each looted creature once per session.
local Loot = { SEEN_MAX = 200 }
ns.Loot = Loot

local NAME_UNITS = { "target", "mouseover" }

local Safe = ns.Store.Safe
local parseGUID = ns.Store.ParseGUID

-- LOOT_READY may fire more than once for one loot window; LOOT_CLOSED ends the window.
local recorded = false

-- Sources already recorded this session, so a re-opened corpse or node adds nothing; a ring of SEEN_MAX GUIDs.
local seen, order, nextSeen = {}, {}, 1

local function remember(guid)
    local old = order[nextSeen]
    if old then
        seen[old] = nil
    end
    order[nextSeen] = guid
    seen[guid] = true
    nextSeen = nextSeen % Loot.SEEN_MAX + 1
end

local function playerPosition()
    if not (C_Map and C_Map.GetBestMapForUnit) then
        return nil
    end
    local map = Safe(C_Map.GetBestMapForUnit("player"))
    if not map or not C_Map.GetPlayerMapPosition then
        return map
    end
    local pos = Safe(C_Map.GetPlayerMapPosition(map, "player"))
    if not (pos and pos.GetXY) then
        return map
    end
    local x, y = pos:GetXY()
    return map, Safe(x), Safe(y)
end

local function recordName(npcID, guid)
    if not (UnitGUID and UnitName) then
        return
    end
    for _, unit in ipairs(NAME_UNITS) do
        if Safe(UnitGUID(unit)) == guid then
            ns.Store.SetNpcName(npcID, Safe(UnitName(unit)))
            return
        end
    end
end

-- Returns the Creature/Vehicle/GameObject GUIDs among GetLootSourceInfo's (guid, quantity) pairs, or nil when
-- the slot reports no source at all; secret and other GUIDs are left out.
local function sourceGUIDs(...)
    local n = select("#", ...)
    if n == 0 or select(1, ...) == nil then
        return nil
    end
    local guids = {}
    for i = 1, n, 2 do
        local guid = Safe((select(i, ...)))
        if parseGUID(guid) then
            guids[#guids + 1] = guid
        end
    end
    return guids
end

local function itemID(slot)
    local link = Safe(GetLootSlotLink(slot))
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

function Loot.OnLootReady()
    if recorded or ns.Store.readOnly or (InCombatLockdown and InCombatLockdown()) then
        return
    end
    if not (GetNumLootItems and GetLootSlotLink) then
        return
    end
    local slots = Safe(GetNumLootItems())
    if type(slots) ~= "number" then
        return
    end
    recorded = true
    local map, x, y = playerPosition()

    -- Every slot, money too, so a gold-only corpse still counts.
    local slotSources, isFresh, fresh = {}, {}, {}
    for slot = 1, slots do
        local guids = GetLootSourceInfo and sourceGUIDs(GetLootSourceInfo(slot))
        slotSources[slot] = guids or false
        for _, guid in ipairs(guids or {}) do
            if not seen[guid] and not isFresh[guid] then
                isFresh[guid] = true
                fresh[#fresh + 1] = guid
            end
        end
    end

    for _, guid in ipairs(fresh) do
        local kind, id = parseGUID(guid)
        if kind == "c" then
            ns.Store.AddCorpse(id)
            recordName(id, guid)
        end
    end

    for slot = 1, slots do
        local item = itemID(slot)
        local guids = slotSources[slot]
        if item and not guids then
            ns.Store.AddLoot(item, "?", 0, map, x, y)
        elseif item then
            for _, guid in ipairs(guids) do
                if isFresh[guid] then
                    local kind, id = parseGUID(guid)
                    ns.Store.AddLoot(item, kind, id, map, x, y)
                end
            end
        end
    end

    for _, guid in ipairs(fresh) do
        remember(guid)
    end
end

function Loot.OnLootClosed()
    recorded = false
end
