local _, ns = ...

-- Display helpers shared by the slash command and the browse window: slot labels, item links, what the player
-- wears, upgrade marks and source lines.
local View = {}
ns.View = View

local L = ns.L
local Safe = ns.Store.Safe

View.SLOT_LABELS = {
    head = "Head", neck = "Neck", shoulder = "Shoulder", back = "Back", chest = "Chest", wrist = "Wrist",
    hands = "Hands", waist = "Waist", legs = "Legs", feet = "Feet", finger = "Finger", trinket = "Trinket",
    mainhand = "Main hand", offhand = "Off hand", twohand = "Two-hand", ranged = "Ranged",
}

-- Inventory slots worn for each slot token; a pair is compared by its lower item level.
local INVENTORY = {
    head = { 1 }, neck = { 2 }, shoulder = { 3 }, back = { 15 }, chest = { 5 }, wrist = { 9 }, hands = { 10 },
    waist = { 6 }, legs = { 7 }, feet = { 8 }, finger = { 11, 12 }, trinket = { 13, 14 }, mainhand = { 16 },
    offhand = { 17 }, twohand = { 16 }, ranged = { 18 },
}

View.QUALITY_HEX = {
    [0] = "9d9d9d", "ffffff", "1eff00", "0070dd", "a335ee", "ff8000", "e6cc80", "00ccff",
}
local QUALITY_HEX = View.QUALITY_HEX

-- Prints the refusal and returns true while in combat (decision 9).
function View.InCombat()
    if InCombatLockdown and InCombatLockdown() then
        print(L["Tandem: not available in combat"])
        return true
    end
    return false
end

-- Returns the player's localised class name, class file and level, or nil when the client hides any of them.
function View.Player()
    local name, classFile, level
    if UnitClass then
        name, classFile = UnitClass("player")
        name, classFile = Safe(name), Safe(classFile)
    end
    if UnitLevel then
        level = Safe(UnitLevel("player"))
    end
    if type(classFile) ~= "string" or type(level) ~= "number" or level < 1 then
        print(L["Tandem: your class or level is not known yet; try again in a moment"])
        return nil
    end
    return type(name) == "string" and name or classFile, classFile, level
end

-- Returns the client's link for an item when cached; else builds one from the id in its quality colour and asks
-- the client to load the item for next time.
function View.ItemLink(id, quality)
    if C_Item and C_Item.GetItemInfo then
        local name, link = C_Item.GetItemInfo(id)
        link = Safe(link)
        if type(link) == "string" then
            return link
        end
        if Safe(name) == nil and C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(id)
        end
    end
    return View.BuiltLink(id, quality)
end

-- Returns a link built from the id in its quality colour, for an item the client has not loaded.
function View.BuiltLink(id, quality)
    return ("|cff%s|Hitem:%d::::::::::::::|h[%s]|h|r"):format(QUALITY_HEX[quality] or QUALITY_HEX[1], id,
        L["item #%d"]:format(id))
end

function View.LinkOf(id)
    local r = ns.Advisor.Item(id)
    return View.ItemLink(id, r and r[3])
end

function View.SlotLabel(slot)
    return L[View.SLOT_LABELS[slot]]
end

-- Returns the item level of an item id from the cache, else from the client, or nil.
local function ilvlOf(id)
    local r = ns.Advisor.Item(id)
    if r then
        return r[1]
    end
    if C_Item and C_Item.GetItemInfo then
        local ilvl = Safe(select(4, C_Item.GetItemInfo(id)))
        return type(ilvl) == "number" and ilvl or nil
    end
end

-- Returns the item id worn in an inventory slot, false when it is empty, or nil when the client does not tell.
-- A secret link is never compared: it is checked before anything else touches it.
local function wornID(inv)
    if not GetInventoryItemLink then
        return nil
    end
    local raw = GetInventoryItemLink("player", inv)
    if issecretvalue and issecretvalue(raw) then
        return nil
    end
    if raw == nil then
        return false
    end
    return type(raw) == "string" and tonumber(raw:match("item:(%d+)")) or nil
end

-- Returns an item's equipLoc from the cache, else from the client, or nil.
local function equipLocOf(id)
    local r = ns.Advisor.Item(id)
    if r then
        return r[4]
    end
    if C_Item and C_Item.GetItemInfoInstant then
        return Safe((select(4, C_Item.GetItemInfoInstant(id))))
    end
end

-- Returns what the player wears in a slot token: { ids = {[id] = true}, list = { {id, ilvl} | {ilvl = 0} | {unknown} },
-- ilvl } where ilvl is the one to beat (the lower of a pair, 0 when a slot is empty) or nil when unknown. An off hand
-- behind a two-hander, or behind a main hand the client does not reveal, has nothing to beat.
function View.Equipped(slot)
    local out = { ids = {}, list = {}, ilvl = math.huge }
    for _, inv in ipairs(INVENTORY[slot]) do
        local id = wornID(inv)
        local e = {}
        if id then
            e.id, e.ilvl = id, ilvlOf(id)
            out.ids[id] = true
        elseif id == false then
            e.ilvl = 0
        else
            e.unknown = true
        end
        out.list[#out.list + 1] = e
        if out.ilvl and e.ilvl then
            out.ilvl = math.min(out.ilvl, e.ilvl)
        else
            out.ilvl = nil
        end
    end
    if slot == "offhand" then
        local main = wornID(16)
        if main == nil or (main and equipLocOf(main) == "INVTYPE_2HWEAPON") then
            out.ilvl = nil
        end
    end
    return out
end

function View.Marks(id, ilvl, sourced, worn)
    local s = ""
    if worn.ids[id] then
        s = s .. L[" (equipped)"]
    elseif worn.ilvl and ilvl > worn.ilvl then
        s = s .. L[" (upgrade)"]
    end
    if not sourced then
        s = s .. L[" (no known source)"]
    end
    return s
end

-- Returns text with its escape character doubled so a stored name cannot inject colour codes or links.
function View.Escape(text)
    return (text:gsub("|", "||"))
end
local escape = View.Escape

-- Returns the lines describing where an item drops: up to max sources, then how many more there are.
function View.SourceLines(id, max)
    local rows = ns.Advisor.Sources(id)
    if #rows == 0 then
        return { L["  no known source"] }
    end
    local lines = {}
    for i = 1, math.min(#rows, max) do
        local s = rows[i]
        local name = s.name and escape(s.name)
        if not name then
            name = s.kind == "c" and L["npc #%d"]:format(s.id) or s.kind == "o" and L["object #%d"]:format(s.id)
                or L["unknown source"]
        end
        local map = s.mapName and escape(s.mapName) or L["unknown map"]
        if s.rateBasis == "kill" then
            lines[#lines + 1] = L["  %s, %s - drops: %d, %.1f%% per kill"]:format(name, map, s.count, s.rate * 100)
        elseif s.rateBasis == "corpse" then
            lines[#lines + 1] = L["  %s, %s - drops: %d, %.1f%% per looted corpse (upper bound)"]:format(name, map,
                s.count, s.rate * 100)
        else
            lines[#lines + 1] = L["  %s, %s - drops: %d"]:format(name, map, s.count)
        end
    end
    if #rows > max then
        lines[#lines + 1] = L["  and %d more sources"]:format(#rows - max)
    end
    return lines
end
