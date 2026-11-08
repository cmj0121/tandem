local _, ns = ...

-- The XP bar (stage 12, D5, D12, D14): a StatusBar centred at the top of the screen, half its width, while the
-- Tandem layout is on, purple (blue while rested) with the percent on it; value/max and rested percent show on hover.
-- Blizzard's status (XP / reputation) bars are faded through Layout.Conceal, never hidden.
local XPBar = {}
ns.XPBar = XPBar

-- Height, gap under the screen's top edge, and share of the screen's width.
local HEIGHT, GAP, SHARE = 12, 4, 0.5
-- The bar is split into this many cells by thin dark lines, like Blizzard's classic XP bar.
local CELLS = 10
local REST_COLOR, XP_COLOR = { 0, 0.39, 0.88 }, { 0.58, 0, 0.55 }

local bar, on

local function call(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, v = pcall(fn, ...)
    if ok then
        return ns.Store.Safe(v)
    end
end

local function number(v)
    return type(v) == "number" and v or nil
end

local function maxLevel()
    return number(call(_G.GetMaxPlayerLevel)) or number(_G.MAX_PLAYER_LEVEL)
end

local function percent(n, max)
    return math.floor(n / max * 100)
end

local function showTooltip(owner)
    local tip = GameTooltip
    if type(tip) ~= "table" or not owner.max then
        return
    end
    local L = ns.L
    tip:SetOwner(owner, "ANCHOR_BOTTOM")
    tip:SetText(("%d / %d (%d%%)"):format(owner.xp, owner.max, percent(owner.xp, owner.max)))
    if owner.rested > 0 then
        tip:AddLine(L["Rested +%d%%"]:format(percent(owner.rested, owner.max)), REST_COLOR[1], REST_COLOR[2],
            REST_COLOR[3])
    end
    tip:Show()
end

local function hideTooltip()
    if type(GameTooltip) == "table" then
        GameTooltip:Hide()
    end
end

local function create()
    bar = CreateFrame("StatusBar", nil, UIParent)
    bar:SetHeight(HEIGHT)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    bg:SetColorTexture(0, 0, 0, 0.5)
    -- Cell dividers over the fill (ARTWORK sublevel 7), under the percent text (OVERLAY).
    bar.dividers = {}
    for i = 1, CELLS - 1 do
        local d = bar:CreateTexture(nil, "ARTWORK", nil, 7)
        d:SetColorTexture(0, 0, 0, 0.8)
        d:SetWidth(1)
        bar.dividers[i] = d
    end
    bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.text:SetPoint("CENTER", bar, "CENTER", 0, 0)
    bar:EnableMouse(true)
    bar:SetScript("OnEnter", showTooltip)
    bar:SetScript("OnLeave", hideTooltip)
    bar:Hide()
end

local function place()
    local parent = UIParent
    local width = type(parent) == "table" and call(parent.GetWidth, parent)
    bar:ClearAllPoints()
    bar:SetPoint("TOP", UIParent, "TOP", 0, -GAP)
    width = math.floor((type(width) == "number" and width > 0 and width or 1024) * SHARE)
    bar:SetWidth(width)
    for i, d in ipairs(bar.dividers) do
        d:ClearAllPoints()
        d:SetPoint("TOPLEFT", bar, "TOPLEFT", math.floor(width * i / CELLS), 0)
        d:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", math.floor(width * i / CELLS), 0)
    end
end

-- Refreshes the bar's value and text; hides it while the layout is off, the client lacks the XP API or the player
-- is at the maximum level. newLevel is PLAYER_LEVEL_UP's level, which UnitLevel may not report yet.
function XPBar.Update(newLevel)
    if not bar then
        return
    end
    local xp, max = number(call(UnitXP, "player")), number(call(UnitXPMax, "player"))
    local level, cap = number(newLevel) or number(call(UnitLevel, "player")), maxLevel()
    if not on or not xp or not max or max <= 0 or (level and cap and level >= cap) then
        bar:Hide()
        return
    end
    local rested = number(call(GetXPExhaustion)) or 0
    bar.xp, bar.max, bar.rested = xp, max, rested
    bar:SetMinMaxValues(0, max)
    bar:SetValue(xp)
    local color = rested > 0 and REST_COLOR or XP_COLOR
    bar:SetStatusBarColor(color[1], color[2], color[3])
    bar.text:SetText(("%d%%"):format(percent(xp, max)))
    bar:Show()
end

local function onChange(layoutOn)
    on = layoutOn and ns.Check.Ready("XP bar")
    if on then
        for _, name in ipairs({ "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer",
            "MainMenuExpBar" }) do
            if type(_G[name]) == "table" then
                ns.Layout.Conceal(name)
            end
        end
        if not bar then
            create()
        end
        place()
    end
    XPBar.Update()
end

ns.Layout.OnChange(onChange)
