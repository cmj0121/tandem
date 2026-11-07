local _, ns = ...

-- A red border and a green up arrow on default bag and loot buttons whose item beats what the player wears (stage 10,
-- decisions 1-3; red and the arrow by user choice 2026-11-07). Each button gets one child frame with a glow texture
-- and the arrow over it; the button's own scripts, attributes and Blizzard's
-- UpgradeIcon are never touched. A non-secure child, so it is painted in combat too.
local ItemBorders = {}
ns.ItemBorders = ItemBorders

local Safe = ns.Store.Safe

local RED = { 1, 0.15, 0.15 }
local ARROW_ATLAS = "bags-greenarrow"
local ARROW_FILE = "Interface\\PetBattles\\BattleBar-AbilityBadge-Strong"
local ARROW_SIZE = 16
local BAG_FRAMES = 13
local BAG_SLOTS = 36
local LOOT_BUTTONS = 4

-- The glow texture is drawn 62 pixels wide around a 36-pixel button, as Blizzard's equipped-item border is.
local GLOW = 62 / 36

-- Calls obj:method(...) under pcall; returns its first result, or nil when the method is missing, raises or the value
-- is secret.
local function call(obj, method, ...)
    local fn = obj[method]
    if type(fn) ~= "function" then
        return nil
    end
    local ok, v = pcall(fn, obj, ...)
    return ok and Safe(v) or nil
end

local painted = setmetatable({}, { __mode = "k" })

-- Returns true when the client knows the atlas; never raises.
local function hasAtlas(name)
    if not (C_Texture and type(C_Texture.GetAtlasInfo) == "function") then
        return false
    end
    local ok, info = pcall(C_Texture.GetAtlasInfo, name)
    return ok and info ~= nil
end

-- The up arrow in the button's top-left corner, where Blizzard puts its own upgrade icon: the bag upgrade atlas when
-- the client has it, else the pet battle "strong" badge, a green up arrow too.
local function arrowOn(border, button)
    local arrow = border:CreateTexture(nil, "OVERLAY")
    if not (hasAtlas(ARROW_ATLAS) and pcall(arrow.SetAtlas, arrow, ARROW_ATLAS)) then
        arrow:SetTexture(ARROW_FILE)
    end
    arrow:SetSize(ARROW_SIZE, ARROW_SIZE)
    arrow:SetPoint("TOPLEFT", button, "TOPLEFT", -1, 1)
    return arrow
end

local function borderOf(button)
    local border = button.tandemUpgrade
    if not border then
        border = CreateFrame("Frame", nil, button)
        local size = (call(button, "GetWidth") or 36) * GLOW
        border:SetSize(size, size)
        border:SetPoint("CENTER", button, "CENTER")
        border:SetFrameLevel((call(button, "GetFrameLevel") or 0) + 2)
        local texture = border:CreateTexture(nil, "OVERLAY")
        texture:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        texture:SetBlendMode("ADD")
        texture:SetVertexColor(RED[1], RED[2], RED[3])
        texture:SetAllPoints(border)
        border.texture = texture
        border.arrow = arrowOn(border, button)
        button.tandemUpgrade = border
        painted[button] = true
    end
    return border
end

-- Shows the button's red border and arrow when on, else hides it (making no frame for a button that never had one).
function ItemBorders.Paint(button, on)
    if on then
        local ok, border = pcall(borderOf, button)
        if ok then
            border:Show()
        end
    elseif button.tandemUpgrade then
        button.tandemUpgrade:Hide()
    end
end

local function itemID(bag, slot)
    local fn = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
    if not (fn and type(bag) == "number" and type(slot) == "number") then
        return nil
    end
    local ok, id = pcall(fn, bag, slot)
    return ok and Safe(id) or nil
end

-- Returns the frame's item buttons: from EnumerateValidItems when it yields an iterator, else from the classic
-- ContainerFrame<f>Item<i> globals when f is given.
local function buttonsOf(frame, f)
    local list = {}
    local ok = pcall(function()
        local iter, state, init = frame:EnumerateValidItems()
        if type(iter) ~= "function" then
            error("no iterator")
        end
        for _, button in iter, state, init do
            list[#list + 1] = button
        end
    end)
    if ok or not f then
        return list
    end
    list = {}
    for i = 1, BAG_SLOTS do
        local button = _G["ContainerFrame" .. f .. "Item" .. i]
        if type(button) == "table" then
            list[#list + 1] = button
        end
    end
    return list
end

-- Paints the button's border from the item's verdict; a missing item or a Better that raises leaves it bare.
local function paintItem(button, id)
    local ok, better = false, nil
    if type(id) == "number" then
        ok, better = pcall(ns.Upgrade.Better, id)
    end
    ItemBorders.Paint(button, ok and better == true)
end

local function paintFrame(frame, f)
    if type(frame) ~= "table" or not call(frame, "IsShown") then
        return
    end
    for _, button in ipairs(buttonsOf(frame, f)) do
        if type(button) == "table" then
            local bag = call(button, "GetBagID")
            if type(bag) ~= "number" and f then
                bag = call(frame, "GetID")
            end
            paintItem(button, itemID(bag, call(button, "GetID")))
        end
    end
end

-- Returns true when the feature's client paths and the item API are there; otherwise hides every border it made.
local function ready()
    if ns.Check.Ready("Upgrade borders") and C_Item and C_Item.GetItemInfo then
        return true
    end
    for button in pairs(painted) do
        ItemBorders.Paint(button, false)
    end
    return false
end

-- Paints every shown default bag frame's buttons; while not ready it only hides the borders it made. A combined-bags
-- button without its own bag id is left bare.
function ItemBorders.Bags()
    if not ready() then
        return
    end
    for f = 1, BAG_FRAMES do
        paintFrame(_G["ContainerFrame" .. f], f)
    end
    paintFrame(ContainerFrameCombinedBags)
end

-- Returns the item id in a loot slot from its link, or nil for coin, an empty slot or a missing API.
local function lootID(slot)
    if type(slot) ~= "number" or not GetLootSlotLink then
        return nil
    end
    local ok, link = pcall(GetLootSlotLink, slot)
    link = ok and Safe(link)
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

local function paintLoot(button)
    if type(button) ~= "table" then
        return
    end
    local slot = call(button, "GetSlotIndex")
    if type(slot) ~= "number" then
        slot = Safe(button.slot)
    end
    paintItem(button, lootID(slot))
end

-- Returns LootFrame.ScrollBox, or nil when it is missing or looking it up raises.
local function scrollBox()
    local ok, box = pcall(function()
        return LootFrame.ScrollBox
    end)
    return ok and type(box) == "table" and box or nil
end

-- Paints the shown loot window's buttons: the ScrollBox's frames when it has ForEachFrame, else the shown
-- LootButton1..LOOTFRAME_NUMBUTTONS; while not ready it only hides the borders it made.
function ItemBorders.Loot()
    if not ready() or type(LootFrame) ~= "table" or not call(LootFrame, "IsShown") then
        return
    end
    local box = scrollBox()
    if box and type(box.ForEachFrame) == "function" then
        pcall(box.ForEachFrame, box, paintLoot)
        return
    end
    local n = type(LOOTFRAME_NUMBUTTONS) == "number" and LOOTFRAME_NUMBUTTONS or LOOT_BUTTONS
    for i = 1, n do
        local button = _G["LootButton" .. i]
        if type(button) == "table" and call(button, "IsShown") then
            paintLoot(button)
        end
    end
end

local function refresh()
    ItemBorders.Bags()
    ItemBorders.Loot()
end

local pending = false

-- Bag, loot, equipment and item info events and bag or loot frames shown: runs one refresh on the next frame however
-- many arrive before it, after Blizzard has filled the buttons; at once when C_Timer is missing.
function ItemBorders.Schedule()
    if not (C_Timer and C_Timer.After) then
        refresh()
        return
    end
    if pending then
        return
    end
    pending = true
    C_Timer.After(0, function()
        pending = false
        refresh()
    end)
end

local hooked = {}

local function hookShow(frame)
    if type(frame) == "table" and not hooked[frame] and type(frame.HookScript) == "function" then
        hooked[frame] = pcall(frame.HookScript, frame, "OnShow", ItemBorders.Schedule)
    end
end

-- A ScrollBox frame just given its loot slot: paints that frame.
local function onLootFrame(_, button)
    if ready() then
        paintLoot(button)
    end
end

-- Repaints loot buttons where the client lays them out, so paging and frame reuse never leave a stale border.
local function hookLoot()
    if not hooked.LootFrame_Update and type(LootFrame_Update) == "function" and hooksecurefunc then
        hooked.LootFrame_Update = pcall(hooksecurefunc, "LootFrame_Update", ItemBorders.Loot)
    end
    local box = scrollBox()
    if not box or hooked[box] then
        return
    end
    if ScrollUtil and type(ScrollUtil.AddInitializedFrameCallback) == "function" then
        hooked[box] = pcall(ScrollUtil.AddInitializedFrameCallback, box, onLootFrame, ItemBorders)
    elseif type(box.RegisterCallback) == "function" then
        hooked[box] = pcall(box.RegisterCallback, box, "OnDataRangeChanged", ItemBorders.Loot, ItemBorders)
    end
end

-- PLAYER_LOGIN: refreshes the borders whenever a default bag or loot frame is shown, and hooks the loot layout.
function ItemBorders.OnLogin()
    for f = 1, BAG_FRAMES do
        hookShow(_G["ContainerFrame" .. f])
    end
    hookShow(ContainerFrameCombinedBags)
    hookShow(LootFrame)
    hookLoot()
end
