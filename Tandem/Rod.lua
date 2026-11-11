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
local lastRod

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

-- equipLoc, classID, subclassID from the client's instant item data, which needs no cached item info; nils when it
-- does not tell.
local function instant(id)
    local _, _, _, equipLoc, _, classID, subclassID = call(C_Item and C_Item.GetItemInfoInstant, id)
    return equipLoc, classID, subclassID
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
-- True when the client's instant item data says the item is a fishing pole, cached item info or not.
function Rod.IsRod(id)
    local _, classID, subclassID = instant(id)
    return classID == WEAPON and subclassID == FISHING_POLE
end

-- Rod.Find() -> rodID|nil, worn
-- The worn main hand when it is a rod (worn true), else the first rod in bags 0..4. A rod found is kept as the last rod
-- seen this session, for the fishing macro.
function Rod.Find()
    local main = worn(MAIN)
    local rod, isWorn = main, true
    if not (main and Rod.IsRod(main)) then
        rod, isWorn = eachBagItem(function(id)
            return Rod.IsRod(id) and id or nil
        end), false
    end
    lastRod = rod or lastRod
    return rod, isWorn
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
    local equipLoc, classID
    if main then
        equipLoc, classID = instant(main)
    end
    if classID ~= WEAPON or Rod.IsRod(main) then
        return
    end
    remembered.main = main
    local off = worn(OFF)
    if off then
        remembered.off = off
    elseif equipLoc == TWO_HAND or not restoring then
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
    local off = remembered.off
    if not inBags(off) or instant(main) == TWO_HAND then
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

-- The rod button (D1, D4): one secure button left of the bag row while the layout is on and a rod is owned; its
-- click runs Rod.Macro(). It is parented and anchored to UIParent only, never to the bag row, and its attributes,
-- anchor and visibility change only out of combat; a change asked for in combat waits for Rod.OnCombatEnd().

local SIZE, GAP = 28, 4
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local button, on, pending, lastUpdate
-- Whether the button was told to fire on mouse-up whatever ActionButtonUseKeyDown says; set on its first update out of
-- combat (a button made in combat waits for Rod.OnCombatEnd).
local keyUp

-- The fishing macro (D5): one character macro the player drags from the button onto an action bar. It equips the rod
-- when it is not worn and casts Fishing when it is. Written only out of combat, and only when its body changed.
local MACRO_NAME = "Tandem Fishing"
local MACRO_ICON = "INV_Misc_QuestionMark"
local FISHING_SPELL = 7620
-- Fishing Pole: the client greys an item the player does not own, so the macro's icon is grey with no rod.
local DEFAULT_ROD = 6256
local macroPending, macroFull, lastMacro

local function debugOn()
    return ns.Debug ~= nil and ns.Debug.IsOn()
end

local function log(text)
    if debugOn() then
        ns.Debug.Log(text)
    end
end

-- The client's localized name for fishing poles, or nil.
local function poleName()
    local name = call(C_Item and C_Item.GetItemSubClassInfo or GetItemSubClassInfo, WEAPON, FISHING_POLE)
    return type(name) == "string" and name ~= "" and name or nil
end

-- The client's localized name of the Fishing spell (any rank: /cast takes the name alone), or nil.
local function fishingName()
    local name = call(C_Spell and C_Spell.GetSpellInfo, FISHING_SPELL)
    if type(name) == "table" then
        name = name.name
    end
    if type(name) ~= "string" then
        name = call(GetSpellInfo, FISHING_SPELL)
    end
    return type(name) == "string" and name ~= "" and name or nil
end

-- Rod.MacroBody() -> text|nil
-- The fishing macro's body: equip the rod while it is not worn, cast Fishing while it is. The rod is the one found now,
-- else the last one seen this session, else the Fishing Pole. Nil when the client does not give both localized names.
function Rod.MacroBody()
    local pole, fishing = poleName(), fishingName()
    if not (pole and fishing) then
        return nil
    end
    local rod = Rod.Find() or lastRod or DEFAULT_ROD
    return ("#showtooltip [equipped:%s] %s; item:%d\n/equip [noequipped:%s] item:%d\n/cast [equipped:%s] %s"):format(
        pole, fishing, rod, pole, rod, pole, fishing)
end

local function macroLog(line)
    if line ~= lastMacro then
        lastMacro = line
        log("rod macro: " .. line)
    end
end

-- Makes or refreshes the fishing macro and returns its index, or nil when there is none to use. Out of combat only (in
-- combat it marks the change as pending); made only once a rod was seen and a character macro slot is free; edited
-- only when its body changed.
local function ensureMacro()
    if not ns.Check.Ready("Fishing macro") then
        return nil
    end
    if call(InCombatLockdown) then
        macroPending = true
        return nil
    end
    macroPending = nil
    local body = Rod.MacroBody()
    if not body then
        macroLog(("skipped: no localized names (pole=%s fishing=%s)"):format(tostring(poleName()),
            tostring(fishingName())))
        return nil
    end
    local index, what, used, max = ns.Macro.Ensure(MACRO_NAME, MACRO_ICON, body, lastRod ~= nil)
    macroFull = what == "full" or nil
    if what == "edited" or what == "created" then
        lastMacro = nil
        macroLog(("%s index=%s body=%s"):format(what, tostring(index), (body:gsub("\n", "|"))))
    elseif what == "absent" then
        macroLog("skipped: no rod seen")
    elseif what == "full" then
        macroLog(("skipped: character macros full (%d/%d)"):format(used, max))
    end
    return index
end

-- OnDragStart: picks the fishing macro up for an action bar, making it first when it is missing; nothing in combat.
local function dragStart()
    if call(InCombatLockdown) then
        return
    end
    local index = ensureMacro()
    if index then
        call(PickupMacro, index)
    end
end

local function itemName(id)
    local name = call(C_Item and C_Item.GetItemInfo, id)
    return type(name) == "string" and name or ("item:" .. id)
end

-- Whether the general bags (family 0) have no free slot, so the off hand an equipped rod displaces has nowhere to go.
local function bagsFull()
    local general = ns.BagButton.Count()
    return general.total > 0 and general.free == 0
end

local function showTooltip(self)
    local tip = GameTooltip
    if type(tip) ~= "table" then
        return
    end
    local L = ns.L
    tip:SetOwner(self, "ANCHOR_TOPLEFT")
    tip:SetText(L["Fishing rod"])
    local rod, isWorn = Rod.Find()
    if rod and not isWorn then
        tip:AddLine(L["Equip %s"]:format(itemName(rod)), 1, 1, 1)
        if worn(OFF) and bagsFull() then
            tip:AddLine(L["Bags full: no room for your off hand"], 1, 0.1, 0.1)
        end
        tip:AddLine(L["Click to equip your fishing rod"], 0.5, 0.5, 0.5)
    elseif rod then
        local main, off = Rod.Back()
        if main then
            local names = itemName(main) .. (off and (" + " .. itemName(off)) or "")
            tip:AddLine(L["Put back %s"]:format(names), 1, 1, 1)
            tip:AddLine(L["Click to put your weapons back"], 0.5, 0.5, 0.5)
        else
            tip:AddLine(L["Equip your weapon"], 1, 1, 1)
        end
    end
    if macroFull then
        tip:AddLine(L["Character macros full: no room for the fishing macro"], 1, 0.1, 0.1)
    elseif ns.Check.Ready("Fishing macro") and not call(InCombatLockdown) then
        tip:AddLine(L["Drag to place the fishing macro on your action bar"], 0.5, 0.5, 0.5)
    end
    if call(InCombatLockdown) then
        tip:AddLine(L["In combat the button runs the swap it showed before combat"], 0.5, 0.5, 0.5)
    end
    tip:Show()
end

local function preClick()
    if Rod.Fishing() then
        Rod.Restoring()
    end
end

local function update()
    if call(InCombatLockdown) then
        pending = true
        return
    end
    pending = nil
    if not keyUp then
        button:SetAttribute("useOnKeyDown", false)
        keyUp = true
    end
    local rod = Rod.Find()
    if not (on and rod) then
        button:Hide()
        return
    end
    local text, texture = Rod.Macro()
    button:SetAttribute("type", "macro")
    button:SetAttribute("macrotext", text)
    button.icon:SetTexture(texture or icon(rod) or UNKNOWN_ICON)
    button:ClearAllPoints()
    button:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", ns.BagButton.OFFSET_X - ns.BagButton.Width() - GAP,
        ns.BagButton.OFFSET_Y + ns.Layout.MicroRoom())
    button:Show()
end

-- Rod.NextX() -> x: the BOTTOMRIGHT x offset from UIParent's bottom-right corner for the right edge of a button left
-- of the rod button, or of the bag row while the rod button is hidden; the y offset is the rod button's.
function Rod.NextX()
    local x = ns.BagButton.OFFSET_X - ns.BagButton.Width() - GAP
    if button and call(button.IsShown, button) == true then
        x = x - SIZE - GAP
    end
    return x
end

local function updateLine()
    local rod, isWorn = Rod.Find()
    local text = rod and Rod.Macro()
    local _, _, _, x, y = call(button.GetPoint, button)
    return ("rod update: combat=%s on=%s rod=%s worn=%s macro=%s shown=%s point=%s,%s"):format(
        tostring(call(InCombatLockdown) == true), tostring(on == true), tostring(rod), tostring(isWorn == true),
        (tostring(text):gsub("\n", "|")), tostring(call(button.IsShown, button) == true), tostring(x), tostring(y))
end

-- Refreshes the button's macro, icon, place and visibility; in combat only marks the change as pending. Runs after
-- BagButton.Update (BAG_UPDATE_DELAYED) and after the bag row's layout listener, whose row width places it. While
-- debugging, logs the button's state when it differs from the last one logged. Then makes or refreshes the fishing
-- macro.
function Rod.Update()
    if not button then
        return
    end
    update()
    ensureMacro()
    -- The cure buttons sit left of this one, so they follow its place and visibility.
    if ns.Cure then
        ns.Cure.Update()
    end
    -- The mute button sits left of the cure buttons, so it follows their places and visibility.
    if ns.Mute then
        ns.Mute.Update()
    end
    if debugOn() then
        local ok, line = pcall(updateLine)
        if ok and line ~= lastUpdate then
            lastUpdate = line
            log(line)
        end
    end
end

local scheduled = false

-- GET_ITEM_INFO_RECEIVED: runs one Rod.Update on the next frame however many arrive before it; at once when C_Timer
-- is missing.
function Rod.Schedule()
    if not (type(C_Timer) == "table" and type(C_Timer.After) == "function") then
        Rod.Update()
        return
    end
    if scheduled then
        return
    end
    scheduled = true
    if not pcall(C_Timer.After, 0, function()
        scheduled = false
        Rod.Update()
    end) then
        scheduled = false
        Rod.Update()
    end
end

-- PLAYER_REGEN_ENABLED: applies the change combat held back, the button's or the macro's.
function Rod.OnCombatEnd()
    if pending or macroPending then
        Rod.Update()
    end
end

-- PLAYER_LOGIN: makes the button (never later, so it is never first made in combat by a layout change), remembers
-- the worn weapons and shows the button when it should.
function Rod.OnLogin()
    local ready = ns.Check.Ready("Fishing rod")
    if not button and type(CreateFrame) == "function" and ready then
        local ok, made = pcall(CreateFrame, "Button", "TandemRodButton", UIParent, "SecureActionButtonTemplate")
        if ok then
            button = made
            button:SetSize(SIZE, SIZE)
            button:SetFrameStrata("MEDIUM")
            -- Mouse-up only (useOnKeyDown false, set by update): the mouse-down that starts a drag must not swap.
            button:RegisterForClicks("AnyUp")
            button.icon = button:CreateTexture(nil, "ARTWORK")
            button.icon:SetAllPoints(button)
            button:SetScript("PreClick", preClick)
            button:SetScript("OnEnter", showTooltip)
            button:SetScript("OnLeave", ns.View.HideTooltip)
            if ns.Check.Ready("Fishing macro") then
                button:RegisterForDrag("LeftButton")
                button:SetScript("OnDragStart", dragStart)
            end
        else
            log("rod login: CreateFrame failed: " .. tostring(made))
        end
    end
    log(("rod login: ready=%s button=%s CreateFrame=%s"):format(tostring(ready),
        button and "made" or "none", type(CreateFrame)))
    Rod.Remember()
    Rod.Update()
end

-- Listens after the bag row (Rod.lua follows BagButton.lua in the toc), so BagButton.Width() is already current.
ns.Layout.OnChange(function(layoutOn)
    on = layoutOn and ns.Check.Ready("Fishing rod")
    log("rod layout: on=" .. tostring(on))
    Rod.Update()
end)
