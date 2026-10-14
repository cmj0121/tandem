local _, ns = ...

-- Logs each looted item once per source of the open loot window.
local Loot = {}
ns.Loot = Loot

local KINDS = { Creature = "c", Vehicle = "c", GameObject = "o" }
local NAME_UNITS = { "target", "mouseover" }

local Safe = ns.Store.Safe

-- LOOT_READY may fire more than once for one loot window; LOOT_CLOSED ends the window.
local recorded = false

-- Returns kind, id for a Creature/Vehicle/GameObject GUID ("Type-0-server-instance-zone-id-spawn"), or nil.
local function parseGUID(guid)
    if type(guid) ~= "string" then
        return nil
    end
    local fields = {}
    for field in guid:gmatch("[^-]+") do
        fields[#fields + 1] = field
    end
    local kind, id = KINDS[fields[1]], tonumber(fields[6])
    if kind and id then
        return kind, id
    end
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

local function recordSources(item, map, x, y, ...)
    local n = select("#", ...)
    if n == 0 or select(1, ...) == nil then
        ns.Store.AddLoot(item, "?", 0, map, x, y)
        return
    end
    for i = 1, n, 2 do
        local guid = Safe((select(i, ...)))
        local kind, id = parseGUID(guid)
        if kind then
            ns.Store.AddLoot(item, kind, id, map, x, y)
            if kind == "c" then
                recordName(id, guid)
            end
        end
    end
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
    for slot = 1, slots do
        local item = itemID(slot)
        if item then
            if GetLootSourceInfo then
                recordSources(item, map, x, y, GetLootSourceInfo(slot))
            else
                recordSources(item, map, x, y)
            end
        end
    end
end

function Loot.OnLootClosed()
    recorded = false
end
