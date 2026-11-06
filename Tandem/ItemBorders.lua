local _, ns = ...

-- A green border on default bag buttons whose item beats what the player wears (stage 10, decisions 1-3). Each button
-- gets one child frame with a glow texture over it; the button's own scripts, attributes and Blizzard's UpgradeIcon are
-- never touched. A non-secure child, so it is painted in combat too.
local ItemBorders = {}
ns.ItemBorders = ItemBorders

local Safe = ns.Store.Safe

local GREEN = { 0.1, 1, 0.1 }
local BAG_FRAMES = 13
local BAG_SLOTS = 36

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
        texture:SetVertexColor(GREEN[1], GREEN[2], GREEN[3])
        texture:SetAllPoints(border)
        border.texture = texture
        button.tandemUpgrade = border
        painted[button] = true
    end
    return border
end

-- Shows the button's green border when on, else hides it (making no frame for a button that never had one).
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
            local id = itemID(bag, call(button, "GetID"))
            local ok, better = false, nil
            if type(id) == "number" then
                ok, better = pcall(ns.Upgrade.Better, id)
            end
            ItemBorders.Paint(button, ok and better == true)
        end
    end
end

-- Paints every shown default bag frame's buttons; while the feature's client paths or the item API are missing it
-- only hides the borders it made. A combined-bags button without its own bag id is left bare.
function ItemBorders.Bags()
    if not (ns.Check.Ready("Upgrade borders") and C_Item and C_Item.GetItemInfo) then
        for button in pairs(painted) do
            ItemBorders.Paint(button, false)
        end
        return
    end
    for f = 1, BAG_FRAMES do
        paintFrame(_G["ContainerFrame" .. f], f)
    end
    paintFrame(ContainerFrameCombinedBags)
end

local function refresh()
    ItemBorders.Bags()
end

local pending = false

-- Bag, equipment and item info events and bag frames shown: runs one refresh on the next frame however many arrive
-- before it, after Blizzard has filled the buttons; at once when C_Timer is missing.
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

-- PLAYER_LOGIN: refreshes the borders whenever a default bag frame is shown.
function ItemBorders.OnLogin()
    for f = 1, BAG_FRAMES do
        hookShow(_G["ContainerFrame" .. f])
    end
    hookShow(ContainerFrameCombinedBags)
end
