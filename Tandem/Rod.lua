local _, ns = ...

-- The fishing rod swap (D2, D3): finds the rod, remembers the weapons it replaces and builds the macro text that
-- swaps one for the other. Advises only: nothing here equips an item; the swap runs on the player's own click.
-- The remembered weapons live for the session only, never in TandemDB.
local Rod = {}
ns.Rod = Rod

local call = ns.Store.Call

local BAGS = 4
local MAIN, OFF = 16, 17
local WEAPON, FISHING_POLE = 2, 20
local RESTORE_SECONDS = 2
local TWO_HAND = "INVTYPE_2HWEAPON"
-- The equip locations a fallback main hand may have.
local MAIN_HAND = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true, [TWO_HAND] = true }

local remembered = {}
local restoring = false

local function worn(inv)
    local id = call(_G.GetInventoryItemID, "player", inv)
    return type(id) == "number" and id or nil
end

-- Calls fn(id, bag, slot) for each item in bags 0..4 until it returns a value, and returns that value.
local function eachBagItem(fn)
    local c = type(C_Container) == "table" and C_Container or {}
    local numSlots = c.GetContainerNumSlots or _G.GetContainerNumSlots
    local itemID = c.GetContainerItemID or _G.GetContainerItemID
    for bag = 0, BAGS do
        local n = call(numSlots, bag)
        for slot = 1, type(n) == "number" and n or 0 do
            local id = call(itemID, bag, slot)
            if type(id) == "number" then
                local found = fn(id, bag, slot)
                if found then
                    return found
                end
            end
        end
    end
end

local function inBags(id)
    return id ~= nil and eachBagItem(function(other)
        return other == id
    end) or false
end

local function icon(id)
    return (select(5, call(C_Item and C_Item.GetItemInfoInstant, id)))
end

-- Whether the client says the bag slot's item is soulbound; false when it does not tell.
local function bound(bag, slot)
    local location = type(ItemLocation) == "table" and ItemLocation
    local loc = location and call(location.CreateFromBagAndSlot, location, bag, slot)
    return loc ~= nil and call(C_Item and C_Item.IsBound, loc) == true
end

-- Rod.IsRod(id) -> bool
-- True when the client knows the item as a fishing pole; an item not equippable or not loaded yet is not a rod.
function Rod.IsRod(id)
    local info = ns.Items.Info(id)
    return info and info[5] == WEAPON and info[6] == FISHING_POLE or false
end

-- Rod.Find() -> rodID|nil, worn
-- The worn main hand when it is a rod (worn true), else the first rod in bags 0..4.
function Rod.Find()
    local main = worn(MAIN)
    if main and Rod.IsRod(main) then
        return main, true
    end
    return eachBagItem(function(id)
        return Rod.IsRod(id) and id or nil
    end), false
end

-- Rod.Fishing() -> bool: the rod is in the main hand.
function Rod.Fishing()
    local main = worn(MAIN)
    return main ~= nil and Rod.IsRod(main)
end

-- Marks a restore click as in flight for 2 s (the button's PreClick), so the off hand's empty slot seen before its
-- macro line lands does not forget it.
function Rod.Restoring()
    if not (type(C_Timer) == "table" and type(C_Timer.After) == "function") then
        return
    end
    restoring = true
    if not pcall(C_Timer.After, RESTORE_SECONDS, function()
        restoring = false
    end) then
        restoring = false
    end
end

-- PLAYER_EQUIPMENT_CHANGED, PLAYER_LOGIN: remembers the worn weapons (D2). An empty or rod main hand changes nothing;
-- an empty off hand is forgotten under a two-hander, or under a one-hander unless a restore click is in flight (the
-- player took it off).
function Rod.Remember()
    local main = worn(MAIN)
    local info = main and ns.Items.Info(main)
    if not (info and info[5] == WEAPON) or Rod.IsRod(main) then
        return
    end
    remembered.main = main
    local off = worn(OFF)
    if off then
        remembered.off = off
    elseif info[4] == TWO_HAND or not restoring then
        remembered.off = nil
    end
end

-- The best soulbound bag weapon the player can wield in the main hand now, by score with armor breaking a tie, or nil.
local function fallback()
    local _, class, level = ns.View.Player(true)
    if not class then
        return nil
    end
    local Items = ns.Items
    local best, bestScore, bestArmor
    eachBagItem(function(id, bag, slot)
        local info = Items.Info(id)
        if not (info and MAIN_HAND[info[4]]) or Rod.IsRod(id) or not Items.Usable(info, class, level)
            or not bound(bag, slot) then
            return
        end
        local src = { id = id, bag = bag, slot = slot }
        local score = Items.Score(src, class, level)
        if score == nil then
            return
        end
        local armor = Items.Armor(src)
        if not best or score > bestScore or (score == bestScore and armor > bestArmor) then
            best, bestScore, bestArmor = id, score, armor
        end
    end)
    return best
end

-- Rod.Back() -> mainID|nil, offID|nil
-- While the rod is worn, the weapons to put back: the remembered main hand when it is in the bags, else the fallback,
-- and the remembered off hand when it is in the bags and the main hand is not a two-hander. Nil while not fishing.
function Rod.Back()
    if not Rod.Fishing() then
        return nil
    end
    local main = inBags(remembered.main) and remembered.main or fallback()
    if not main then
        return nil
    end
    local info = ns.Items.Info(main)
    local off = remembered.off
    if not inBags(off) or (info and info[4] == TWO_HAND) then
        off = nil
    end
    return main, off
end

-- Rod.Macro() -> text|nil, iconTexture|nil
-- The swap the button runs: equip the rod from the bags, or put the weapons back while it is worn; nil when there is
-- no rod, or nothing to put back.
function Rod.Macro()
    local rod, isWorn = Rod.Find()
    if not rod then
        return nil
    end
    if not isWorn then
        return "/equipslot 16 item:" .. rod, icon(rod)
    end
    local main, off = Rod.Back()
    if not main then
        return nil
    end
    local text = "/equipslot 16 item:" .. main
    if off then
        text = text .. "\n/equipslot 17 item:" .. off
    end
    return text, icon(main)
end
