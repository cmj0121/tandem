local _, ns = ...

-- Turns the Tandem layout on or off without a command (stage 12, U6): the addon compartment entry from the .toc, and
-- a minimap button that is shown unless the player hides it with /tandem minimap off.
local Launcher = {}
ns.Launcher = Launcher

local ICON = "Interface\\AddOns\\Tandem\\Media\\icon"
local DEFAULT_ANGLE = 225
local BUTTON_SIZE = 31
local atan2 = math.atan2 or math.atan

local function showTooltip(owner)
    if type(GameTooltip) ~= "table" or not owner then
        return
    end
    local L = ns.L
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:SetText("Tandem")
    GameTooltip:AddLine(ns.Layout.IsOn() and L["Layout: on"] or L["Layout: off"], 1, 1, 1)
    GameTooltip:AddLine(L["Click to turn the layout on/off"], 0.5, 0.5, 0.5)
    if owner == Launcher.button then
        GameTooltip:AddLine(L["Drag to move this button"], 0.5, 0.5, 0.5)
    end
    GameTooltip:Show()
end

local hideTooltip = ns.View.HideTooltip

-- Turns the layout on or off and prints the reply /tandem layout prints; in combat Layout defers itself.
local function click()
    local on = not ns.Layout.IsOn()
    local ok, reason = ns.Layout.Set(on)
    print(ns.Layout.Reply(on, ok, reason))
end

-- The .toc's AddonCompartmentFunc entries.
Tandem_OnCompartmentClick = click

function Tandem_OnCompartmentEnter(_, menuButton)
    showTooltip(menuButton)
end

Tandem_OnCompartmentLeave = hideTooltip

-- Returns the angle in degrees (0 <= a < 360) of point (x, y) around the centre (cx, cy). A tiny negative angle
-- rounds to 360 under % 360, so that wraps to 0.
function Launcher.Angle(x, y, cx, cy)
    local angle = math.deg(atan2(y - cy, x - cx)) % 360
    if angle >= 360 then
        return 0
    end
    return angle
end

-- The saved minimap button state { angle, hidden }; empty when nothing is saved.
local function saved()
    return ns.Store.Layout().minimap or {}
end

-- Whether the button is hidden this session: read from TandemDB once, then kept here so a read-only db still hides
-- and shows it until logout.
local hidden

-- Saves the angle and hidden flag; nothing is kept when neither is set.
local function save(angle)
    if angle == nil and not hidden then
        ns.Store.SetLayout("minimap", nil)
    else
        ns.Store.SetLayout("minimap", { angle = angle, hidden = hidden or nil })
    end
end

-- Places the button on the minimap's edge at angle degrees.
local function place(button, angle)
    local radius = (Minimap.GetWidth and Minimap:GetWidth() or 140) / 2 + 10
    local rad = math.rad(angle)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * radius, math.sin(rad) * radius)
end

-- While dragging: follows the cursor around the minimap.
local function follow(self)
    if not (GetCursorPosition and Minimap.GetCenter) then
        return
    end
    local x, y = GetCursorPosition()
    local scale = Minimap.GetEffectiveScale and Minimap:GetEffectiveScale() or 1
    local cx, cy = Minimap:GetCenter()
    if not (x and cx) then
        return
    end
    self.angle = Launcher.Angle(x / scale, y / scale, cx, cy)
    place(self, self.angle)
end

local function buildButton()
    local b = CreateFrame("Button", "TandemMinimapButton", Minimap)
    b:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", b, "CENTER", 0, 0)
    icon:SetTexture(ICON)
    b.icon = icon
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b:SetScript("OnClick", function(_, mouse)
        if mouse == "LeftButton" then
            click()
        end
    end)
    b:SetScript("OnEnter", showTooltip)
    b:SetScript("OnLeave", hideTooltip)
    b:SetScript("OnDragStart", function(self)
        hideTooltip()
        self:SetScript("OnUpdate", follow)
    end)
    b:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        save(self.angle)
    end)
    b.angle = saved().angle or DEFAULT_ANGLE
    place(b, b.angle)
    return b
end

-- Returns true unless the minimap button was hidden with /tandem minimap off.
function Launcher.IsButtonShown()
    if hidden == nil then
        hidden = saved().hidden == true
    end
    return not hidden
end

-- Shows or hides the minimap button and saves the choice with its angle.
function Launcher.SetButtonShown(shown)
    hidden = not shown
    save(Launcher.button and Launcher.button.angle or saved().angle)
    if Launcher.button then
        Launcher.button:SetShown(shown)
    end
end

-- PLAYER_LOGIN: the compartment entry needs nothing; the minimap button is built once, shown unless hidden.
function Launcher.OnLogin()
    if type(Minimap) ~= "table" or Launcher.button then
        return
    end
    Launcher.button = buildButton()
    Launcher.button:SetShown(Launcher.IsButtonShown())
end
