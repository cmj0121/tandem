local _, ns = ...

-- Opens the browse window without a command: the addon compartment entry from the .toc, or a minimap button on a
-- client without the compartment.
local Launcher = {}
ns.Launcher = Launcher

local L = ns.L

local ICON = "Interface\\AddOns\\Tandem\\Media\\icon"
local DEFAULT_ANGLE = 225
local BUTTON_SIZE = 31
local atan2 = math.atan2 or math.atan

local function showTooltip(owner)
    if not (GameTooltip and owner) then
        return
    end
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:SetText("Tandem")
    GameTooltip:AddLine(L["Click to browse known gear"], 1, 1, 1)
    if owner == Launcher.button then
        GameTooltip:AddLine(L["Drag to move this button"], 0.5, 0.5, 0.5)
    end
    GameTooltip:Show()
end

local function hideTooltip()
    if GameTooltip then
        GameTooltip:Hide()
    end
end

-- Toggles the browse window; in combat it prints the refusal, as /tandem browse does.
function Launcher.Click()
    if ns.View.InCombat() then
        return
    end
    ns.Browse.Toggle()
end

-- The .toc's AddonCompartmentFunc entries.
function Tandem_OnCompartmentClick()
    Launcher.Click()
end

function Tandem_OnCompartmentEnter(_, menuButton)
    showTooltip(menuButton)
end

function Tandem_OnCompartmentLeave()
    hideTooltip()
end

-- Returns the angle in degrees (0 <= a < 360) of point (x, y) around the centre (cx, cy). A tiny negative angle
-- rounds to 360 under % 360, so that wraps to 0.
function Launcher.Angle(x, y, cx, cy)
    local angle = math.deg(atan2(y - cy, x - cx)) % 360
    if angle >= 360 then
        return 0
    end
    return angle
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
    b:RegisterForClicks("AnyUp")
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
    b:SetScript("OnClick", Launcher.Click)
    b:SetScript("OnEnter", showTooltip)
    b:SetScript("OnLeave", hideTooltip)
    b:SetScript("OnDragStart", function(self)
        hideTooltip()
        self:SetScript("OnUpdate", follow)
    end)
    b:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        ns.Store.SetMinimapAngle(self.angle)
    end)
    b.angle = ns.Store.MinimapAngle() or DEFAULT_ANGLE
    place(b, b.angle)
    return b
end

-- PLAYER_LOGIN: the compartment entry needs nothing; without the compartment, a minimap button stands in.
function Launcher.OnLogin()
    if AddonCompartmentFrame or not Minimap or Launcher.button then
        return
    end
    Launcher.button = buildButton()
end
