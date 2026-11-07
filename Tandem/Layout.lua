local _, ns = ...

-- The Tandem Edit Mode layout (stage 12, D4, D12): an account layout named "Tandem" stacks the three bottom action
-- bars at the bottom centre with the player and target frames as wings beside them, moves the chat frame bottom-left,
-- the micro menu bottom-right and the minimap and buffs top-right (each only when the client's Edit Mode has its
-- system) and hides the other bars. Blizzard frames move only through Edit Mode, anchored to UIParent or to each
-- other; a frame Edit Mode cannot hide is faded with SetAlpha(0) and EnableMouse(false), both undone on off.
local Layout = {}
ns.Layout = Layout

local NAME = "Tandem"
-- Room under the bottom bar for the XP bar and between bars; the unit frame wings' gap beside and drop below the top
-- bar's top edge.
local XP_ROOM, BAR_GAP, UNIT_GAP, UNIT_DROP = 42, 2, 8, 12
-- Chat frame size in Edit Mode's hundreds / tens-and-ones settings, and the narrowest chat kept beside the band.
local CHAT_WIDTH, CHAT_HEIGHT, CHAT_MIN = 380, 120, 260
-- Corner inset and gap kept clear beside the wings; room above the bars for the class rail plus a gap.
local INSET, CLEAR, RAIL_ROOM = 16, 8, 48
local TOT_CVAR = "showTargetOfTarget"

local listeners = {}
-- concealed: frame names faded while on; faded[name] = { alpha, mouse } as they were before.
local concealed, faded = {}, {}
local pending, pendingSync, attached, busy

local REPLY = {
    [true] = "Tandem: layout on",
    [false] = "Tandem: layout off; your previous layout is back",
    missing = "Tandem: the layout needs Edit Mode, which this client lacks",
    readonly = "Tandem: the layout cannot be saved: saved data uses a newer schema",
    combat = "Tandem: the layout will change after combat",
    full = "Tandem: no free account layout slot; delete one in Edit Mode",
    error = "Tandem: the layout could not be changed",
}

-- Returns the localized reply to turning the layout on or off with Set's result.
function Layout.Reply(on, ok, reason)
    return ns.L[ok and REPLY[on] or REPLY[reason] or REPLY.error]
end

local function call(fn, ...)
    local ok, v = pcall(fn, ...)
    if ok then
        return ns.Store.Safe(v)
    end
end

local function enum(group, key)
    return call(function()
        return Enum[group][key]
    end)
end

local function inCombat()
    return call(InCombatLockdown) == true
end

local function ready()
    return ns.Check.Ready("Layout")
end

local function mainBarName()
    return type(_G.MainActionBar) == "table" and "MainActionBar" or "MainMenuBar"
end

-- Returns the frame Tandem's class area anchors above (the top bar) and the one the XP bar anchors under (the
-- bottom bar).
function Layout.BarAnchor()
    return _G.MultiBarBottomRight, _G[mainBarName()]
end

function Layout.IsOn()
    return ns.Store.Layout().on == true
end

-- Registers fn(on), called after the layout is turned on or off and at login while it is on.
function Layout.OnChange(fn)
    listeners[#listeners + 1] = fn
end

local function notify(on)
    for _, fn in ipairs(listeners) do
        pcall(fn, on)
    end
end

local function fade()
    for name in pairs(concealed) do
        local f = _G[name]
        if type(f) == "table" then
            if not faded[name] then
                faded[name] = { alpha = call(f.GetAlpha, f) or 1, mouse = call(f.IsMouseEnabled, f) }
            end
            pcall(f.SetAlpha, f, 0)
            pcall(f.EnableMouse, f, false)
        end
    end
end

local function unfade()
    for name, was in pairs(faded) do
        local f = _G[name]
        if type(f) == "table" then
            pcall(f.SetAlpha, f, was.alpha)
            if was.mouse ~= nil then
                pcall(f.EnableMouse, f, was.mouse)
            end
        end
        faded[name] = nil
    end
end

-- Fades the named Blizzard frame while the layout is on (for a frame without an Edit Mode visibility setting).
function Layout.Conceal(name)
    concealed[name] = true
    if attached and not inCombat() then
        fade()
    end
end

local function getCVar(name)
    return call((C_CVar and C_CVar.GetCVar) or GetCVar, name)
end

local function setCVar(name, value)
    pcall((C_CVar and C_CVar.SetCVar) or SetCVar, name, value)
end

local function presets()
    local list = call(function()
        return EditModePresetLayoutManager:GetCopyOfPresetLayouts()
    end)
    return type(list) == "table" and list or nil
end

local function activeInfo()
    local info = call(function()
        return EditModeManagerFrame:GetActiveLayoutInfo()
    end)
    return type(info) == "table" and info or nil
end

local function indexNamed(list, name, layoutType)
    for i, info in ipairs(type(list) == "table" and list or {}) do
        if type(info) == "table" and info.layoutName == name and info.layoutType == layoutType then
            return i
        end
    end
end

local function deepCopy(v)
    if type(v) ~= "table" then
        return v
    end
    local out = {}
    for k, x in pairs(v) do
        out[k] = deepCopy(x)
    end
    return out
end

local function anchor(point, relativeTo, relativePoint, x, y)
    return { point = point, relativeTo = relativeTo, relativePoint = relativePoint, offsetX = x, offsetY = y }
end

local function setSetting(system, setting, value)
    if setting == nil or value == nil then
        return
    end
    system.settings = type(system.settings) == "table" and system.settings or {}
    for _, row in ipairs(system.settings) do
        if row.setting == setting then
            row.value = value
            return
        end
    end
    system.settings[#system.settings + 1] = { setting = setting, value = value }
end

local function findSystem(info, system, index)
    for _, s in ipairs(info.systems) do
        if type(s) == "table" and s.system == system and (index == nil or s.systemIndex == nil
            or s.systemIndex == index) then
            return s
        end
    end
end

local function move(s, a)
    s.anchorInfo = a
    s.anchorInfo2 = nil
    s.isInDefaultPosition = false
end

-- Sets a chat size dimension through its hundreds and tens-and-ones settings, only when the client has both.
local function setSize(s, hundreds, tensAndOnes, value)
    local h, t = enum("EditModeChatFrameSetting", hundreds), enum("EditModeChatFrameSetting", tensAndOnes)
    if h ~= nil and t ~= nil then
        setSetting(s, h, math.floor(value / 100))
        setSetting(s, t, value % 100)
    end
end

-- Returns the named frame's width or height (method "GetWidth"/"GetHeight"), or fallback when unknown.
local function measure(name, method, fallback)
    local f = _G[name]
    local v = type(f) == "table" and call(f[method], f)
    return type(v) == "number" and v > 0 and v or fallback
end

-- Moves the chat frame, micro menu, minimap and buffs (D12) when the client's Edit Mode has their systems. The chat
-- and micro menu sit beside the wings when the screen leaves room, else above the band. The wings follow
-- MultiBarBottomRight's width as measured now (from the layout being replaced, never under one row of 12, as that
-- layout may have bar 3 vertical or in rows); no later check.
local function corners(info)
    local band = math.max(measure("MultiBarBottomRight", "GetWidth", 498), 498)
    local side = (measure("UIParent", "GetWidth", 1920) - band) / 2
    local block = 2 * BAR_GAP
    for _, name in ipairs({ mainBarName(), "MultiBarBottomLeft", "MultiBarBottomRight" }) do
        block = block + measure(name, "GetHeight", 40)
    end
    local above = XP_ROOM + block + RAIL_ROOM
    local chatSystem = enum("EditModeSystem", "ChatFrame")
    local chat = chatSystem ~= nil and findSystem(info, chatSystem, 1)
    if chat then
        local free = side - UNIT_GAP - measure("PlayerFrame", "GetWidth", 232) - INSET - CLEAR
        local width, y = CHAT_WIDTH, 8
        if free < CHAT_MIN then
            y = above
        elseif free < CHAT_WIDTH then
            width = math.floor(free)
        end
        move(chat, anchor("BOTTOMLEFT", "UIParent", "BOTTOMLEFT", INSET, y))
        setSize(chat, "WidthHundreds", "WidthTensAndOnes", width)
        setSize(chat, "HeightHundreds", "HeightTensAndOnes", CHAT_HEIGHT)
    end
    local microSystem = enum("EditModeSystem", "MicroMenu")
    local micro = microSystem ~= nil and findSystem(info, microSystem)
    if micro then
        local free = side - UNIT_GAP - measure("TargetFrame", "GetWidth", 232)
            - measure("TargetFrameToT", "GetWidth", 93) - 12 - CLEAR
        local fits = measure("MicroMenuContainer", "GetWidth", 260) <= free
        move(micro, anchor("BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -12, fits and 40 or above))
    end
    local minimapSystem = enum("EditModeSystem", "Minimap")
    local minimap = minimapSystem ~= nil and findSystem(info, minimapSystem)
    if not minimap then
        return
    end
    move(minimap, anchor("TOPRIGHT", "UIParent", "TOPRIGHT", -16, -16))
    local auraSystem = enum("EditModeSystem", "AuraFrame")
    local buffs = auraSystem ~= nil and type(_G.MinimapCluster) == "table"
        and findSystem(info, auraSystem, enum("EditModeAuraFrameSystemIndices", "BuffFrame") or 1)
    if buffs then
        move(buffs, anchor("TOPRIGHT", "MinimapCluster", "TOPLEFT", -8, 0))
    end
end

-- Rewrites info's systems to D12; returns the bar frame names Edit Mode cannot hide here (to fade instead).
local function override(info)
    local bar, unit = enum("EditModeSystem", "ActionBar"), enum("EditModeSystem", "UnitFrame")
    local visible = enum("EditModeActionBarSetting", "VisibleSetting")
    local hidden, always = enum("ActionBarVisibleSetting", "Hidden"), enum("ActionBarVisibleSetting", "Always")
    local main = mainBarName()
    local shown = {
        { "MainBar", anchor("BOTTOM", "UIParent", "BOTTOM", 0, XP_ROOM) },
        { "Bar2", anchor("BOTTOM", main, "TOP", 0, BAR_GAP), always },
        { "Bar3", anchor("BOTTOM", "MultiBarBottomLeft", "TOP", 0, BAR_GAP), always },
    }
    for _, row in ipairs(shown) do
        local s = bar and findSystem(info, bar, enum("EditModeActionBarSystemIndices", row[1]))
        if s then
            move(s, row[2])
            setSetting(s, enum("EditModeActionBarSetting", "Orientation"), 0)
            setSetting(s, enum("EditModeActionBarSetting", "NumRows"), 1)
            setSetting(s, enum("EditModeActionBarSetting", "NumIcons"), 12)
            setSetting(s, visible, row[3])
        end
    end
    local faders = {}
    for _, row in ipairs({ { "RightBar1", "MultiBarRight" }, { "RightBar2", "MultiBarLeft" },
        { "ExtraBar1", "MultiBar5" }, { "ExtraBar2", "MultiBar6" }, { "ExtraBar3", "MultiBar7" } }) do
        local s = bar and findSystem(info, bar, enum("EditModeActionBarSystemIndices", row[1]))
        if s and visible ~= nil and hidden ~= nil then
            setSetting(s, visible, hidden)
        else
            faders[#faders + 1] = row[2]
        end
    end
    local player = unit and findSystem(info, unit, enum("EditModeUnitFrameSystemIndices", "Player"))
    if player then
        move(player, anchor("TOPRIGHT", "MultiBarBottomRight", "TOPLEFT", -UNIT_GAP, -UNIT_DROP))
    end
    local target = unit and findSystem(info, unit, enum("EditModeUnitFrameSystemIndices", "Target"))
    if target then
        move(target, anchor("TOPLEFT", "MultiBarBottomRight", "TOPRIGHT", UNIT_GAP, -UNIT_DROP))
    end
    corners(info)
    return faders
end

local function maxPerType()
    local v = call(function()
        return Constants.EditModeConsts.EditModeMaxLayoutsPerType
    end)
    return type(v) == "number" and v or 5
end

local function setFaders(list)
    for _, name in ipairs({ "MultiBarRight", "MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7" }) do
        concealed[name] = nil
    end
    for _, name in ipairs(list) do
        concealed[name] = true
    end
end

local function apply()
    local layouts = call(C_EditMode.GetLayouts)
    local active = activeInfo()
    if type(layouts) ~= "table" or type(layouts.layouts) ~= "table" or not active then
        return false, "error"
    end
    local account = enum("EditModeLayoutType", "Account") or 1
    local presetType = enum("EditModeLayoutType", "Preset") or 0
    local isTandem = active.layoutName == NAME and active.layoutType == account
    local previous = ns.Store.Layout().previous
    if not isTandem then
        previous = { name = active.layoutName, type = active.layoutType }
    end
    local presetList = presets()
    if not presetList then
        return false, "error"
    end
    local source = active
    if isTandem and previous then
        local list = previous.type == presetType and presetList or layouts.layouts
        source = list[indexNamed(list, previous.name, previous.type) or 0] or active
    end
    local info = deepCopy(source)
    if type(info.systems) ~= "table" then
        return false, "error"
    end
    info.layoutName, info.layoutType = NAME, account
    local faders = override(info)

    local index = indexNamed(layouts.layouts, NAME, account)
    if index then
        layouts.layouts[index] = info
    else
        local count, last = 0, 0
        for i, l in ipairs(layouts.layouts) do
            if type(l) == "table" and l.layoutType == account then
                count, last = count + 1, i
            end
        end
        if count >= maxPerType() then
            return false, "full"
        end
        index = last + 1
        table.insert(layouts.layouts, index, info)
    end
    layouts.activeLayout = #presetList + index
    if not pcall(C_EditMode.SaveLayouts, layouts) then
        return false, "error"
    end
    local saved = call(C_EditMode.GetLayouts)
    index = type(saved) == "table" and indexNamed(saved.layouts, NAME, account)
    if not index or not pcall(C_EditMode.SetActiveLayout, #presetList + index) then
        return false, "error"
    end

    local store = ns.Store
    if previous then
        store.SetLayout("previous", previous)
    end
    if store.Layout().tot == nil then
        local tot = getCVar(TOT_CVAR)
        if type(tot) == "string" and tot ~= "1" then
            store.SetLayout("tot", tot)
        end
    end
    setCVar(TOT_CVAR, "1")
    store.SetLayout("on", true)
    setFaders(faders)
    fade()
    attached = true
    notify(true)
    return true
end

-- Undoes every side effect of the layout (ToT CVar, faded frames, saved state) and tells the listeners.
local function detach()
    local store = ns.Store
    local tot = store.Layout().tot
    if tot then
        setCVar(TOT_CVAR, tot)
    end
    store.SetLayout("tot", nil)
    store.SetLayout("previous", nil)
    store.SetLayout("on", false)
    unfade()
    attached = false
    notify(false)
end

local function restore()
    local store = ns.Store
    local layouts = call(C_EditMode.GetLayouts)
    local presetList = presets()
    if not presetList then
        return false, "error"
    end
    local previous = store.Layout().previous
    local index = 1
    if previous then
        if previous.type == (enum("EditModeLayoutType", "Preset") or 0) then
            index = indexNamed(presetList, previous.name, previous.type) or 1
        else
            local saved = type(layouts) == "table" and indexNamed(layouts.layouts, previous.name, previous.type)
            index = saved and #presetList + saved or 1
        end
    end
    local ok = pcall(C_EditMode.SetActiveLayout, index)
    detach()
    if not ok then
        return false, "error"
    end
    return true
end

local WORK = { [true] = apply, [false] = restore }

local function run(on)
    pending = nil
    busy = true
    local ok, done, reason = pcall(WORK[on])
    busy = nil
    if not ok then
        return false, "error"
    end
    return done, reason
end

-- Turns the layout on or off; returns true, or false and "missing" (no Edit Mode), "readonly" (newer saved data),
-- "combat" (deferred until combat ends), "full" (no free account layout slot) or "error".
function Layout.Set(on)
    if not ready() then
        return false, "missing"
    end
    if ns.Store.readOnly then
        return false, "readonly"
    end
    if not on and not Layout.IsOn() then
        pending = nil
        return true
    end
    if inCombat() then
        pending = on
        return false, "combat"
    end
    return run(on)
end

local function isTandem(info)
    return info.layoutName == NAME and info.layoutType == (enum("EditModeLayoutType", "Account") or 1)
end

-- Returns whether the account layout "Tandem" is the active Edit Mode layout.
function Layout.IsActive()
    local info = activeInfo()
    return info ~= nil and isTandem(info)
end

-- Matches Tandem's frames to the active layout while the layout is on, saving nothing: with "Tandem" active it
-- attaches them (once) and fades the frames again; with another layout active (switched or deleted in Edit Mode) the
-- layout turns off silently. Unknown active layout (Edit Mode not loaded yet) waits for the next call. Runs at login,
-- on EDIT_MODE_LAYOUTS_UPDATED and when Edit Mode closes.
function Layout.Sync()
    if busy or not Layout.IsOn() or not ready() then
        return
    end
    if inCombat() then
        pendingSync = true
        return
    end
    pendingSync = nil
    local info = activeInfo()
    if not info then
        return
    end
    if not isTandem(info) then
        detach()
        return
    end
    if not attached then
        info = deepCopy(info)
        if type(info.systems) == "table" then
            setFaders(override(info))
        end
        attached = true
        fade()
        notify(true)
    else
        fade()
    end
end

-- Runs the change combat deferred, printing its reply only when it fails; then any deferred sync.
function Layout.OnCombatEnd()
    if pending ~= nil then
        local on = pending
        pending = nil
        local ok, reason = Layout.Set(on)
        if not ok then
            print(Layout.Reply(on, ok, reason))
        end
    end
    if pendingSync then
        Layout.Sync()
    end
end

-- Edit Mode closing fires no game event; EventRegistry's callback is an event handler, not a hook.
if type(EventRegistry) == "table" then
    pcall(EventRegistry.RegisterCallback, EventRegistry, "EditMode.Exit", Layout.Sync, Layout)
end
