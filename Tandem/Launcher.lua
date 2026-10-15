local _, ns = ...

-- Opens the browse window without a command: the addon compartment entry from the .toc, and a minimap button that
-- is shown unless the player hides it.
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

-- Toggles the browse window; in combat Browse.Show prints the refusal, as /tandem browse does.
local function click()
    ns.Browse.Toggle()
end

-- The .toc's AddonCompartmentFunc entries.
Tandem_OnCompartmentClick = click

function Tandem_OnCompartmentEnter(_, menuButton)
    showTooltip(menuButton)
end

Tandem_OnCompartmentLeave = ns.View.HideTooltip

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
    b:SetScript("OnClick", click)
    b:SetScript("OnEnter", showTooltip)
    b:SetScript("OnLeave", ns.View.HideTooltip)
    b:SetScript("OnDragStart", function(self)
        ns.View.HideTooltip()
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

-- Whether the minimap button is hidden this session: read from TandemDB once, then kept here so a read-only db
-- still hides and shows it until logout.
local hidden

-- Returns true unless the minimap button was hidden with /tandem minimap off or the browse window's checkbox.
function Launcher.IsButtonShown()
    if hidden == nil then
        hidden = ns.Store.MinimapHidden()
    end
    return not hidden
end

-- Shows or hides the minimap button, saves the choice and ticks the browse window's checkbox to match.
function Launcher.SetButtonShown(shown)
    hidden = not shown
    ns.Store.SetMinimapHidden(hidden)
    if Launcher.button then
        Launcher.button:SetShown(shown)
    end
    ns.Browse.OnMinimapButtonChanged()
end

-- PLAYER_LOGIN: the compartment entry needs nothing; the minimap button is built next to it, shown unless hidden.
function Launcher.OnLogin()
    if not Minimap or Launcher.button then
        return
    end
    Launcher.button = buildButton()
    Launcher.button:SetShown(Launcher.IsButtonShown())
end
