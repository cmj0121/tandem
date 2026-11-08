local _, ns = ...

-- Blizzard's totem bar (stage 12, D13): while the Tandem layout is on, MultiCastActionBarFrame (secure totem buttons)
-- sits right of the three-bar block. It has no Edit Mode system, so it moves by SetPoint, only out of combat (a move
-- in combat waits for PLAYER_REGEN_ENABLED), again whenever Blizzard may have re-anchored it (on events, and a twice a
-- second check while on, since Blizzard also moves it after spell casts), and goes back to its saved points on off.
local TotemBar = {}
ns.TotemBar = TotemBar

local GAP, WATCH = 8, 0.5

-- saved = { manager = ignoreFramePositionManager as it was, points = { {point, relativeTo, ...}, ... } }
local saved, on, pending, watcher

local function call(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, v = pcall(fn, ...)
    if ok then
        return ns.Store.Safe(v)
    end
end

local function totemBar()
    local f = _G.MultiCastActionBarFrame
    return type(f) == "table" and f or nil
end

local function save(f)
    if saved then
        return
    end
    saved = { manager = f.ignoreFramePositionManager, points = {} }
    local n = call(f.GetNumPoints, f)
    for i = 1, type(n) == "number" and n or 0 do
        local p = { pcall(f.GetPoint, f, i) }
        if p[1] and p[2] ~= nil then
            table.remove(p, 1)
            saved.points[#saved.points + 1] = p
        end
    end
end

-- Puts the totem bar where the layout state says: beside the bars while on, back where it was after off.
function TotemBar.Place()
    local f = totemBar()
    if not f or (not on and not saved) then
        return
    end
    if call(InCombatLockdown) == true then
        pending = true
        return
    end
    pending = nil
    if on then
        local beside = _G.MultiBarBottomLeft
        if type(beside) ~= "table" then
            return
        end
        save(f)
        f.ignoreFramePositionManager = true
        pcall(f.ClearAllPoints, f)
        pcall(f.SetPoint, f, "LEFT", beside, "RIGHT", GAP, 0)
    else
        f.ignoreFramePositionManager = saved.manager
        pcall(f.ClearAllPoints, f)
        for _, p in ipairs(saved.points) do
            pcall(f.SetPoint, f, (unpack or rawget(table, "unpack"))(p))
        end
        saved = nil
    end
end

-- True when the totem bar is anchored anywhere but right of the bars.
local function drifted(f)
    local beside = _G.MultiBarBottomLeft
    if call(f.GetNumPoints, f) ~= 1 then
        return true
    end
    local ok, point, relativeTo, relativePoint, x, y = pcall(f.GetPoint, f, 1)
    return not ok or point ~= "LEFT" or relativeTo ~= beside or relativePoint ~= "RIGHT"
        or math.abs((tonumber(x) or 0) - GAP) > 0.5 or math.abs(tonumber(y) or 0) > 0.5
end

-- The watcher's tick: puts a moved totem bar back, or after combat when it moved in combat.
function TotemBar.Watch()
    local f = totemBar()
    if not on or not f or not drifted(f) then
        return
    end
    TotemBar.Place()
end

local function startWatch()
    if not watcher and type(C_Timer) == "table" and type(C_Timer.NewTicker) == "function" then
        watcher = C_Timer.NewTicker(WATCH, TotemBar.Watch)
    end
end

local function stopWatch()
    if watcher then
        pcall(watcher.Cancel, watcher)
        watcher = nil
    end
end

local function nameOf(v)
    if type(v) ~= "table" then
        return tostring(v)
    end
    return tostring(call(v.GetName, v) or "?")
end

local function flag(v)
    return tostring(v == true or v == 1)
end

-- One diagnostic line for /tandem check (where the totem bar is and what holds it), or nil without the bar.
function TotemBar.Describe()
    local f = totemBar()
    if not f then
        return nil
    end
    local points = {}
    for i = 1, tonumber(call(f.GetNumPoints, f)) or 0 do
        local ok, p, r, rp, x, y = pcall(f.GetPoint, f, i)
        if ok then
            points[#points + 1] = ("%s %s %s %d %d"):format(tostring(p), nameOf(r), tostring(rp), tonumber(x) or 0,
                tonumber(y) or 0)
        end
    end
    local parent = call(f.GetParent, f)
    return ("Totem bar: shown %s, visible %s, alpha %s, parent %s (visible %s), left %d, bottom %d, points [%s], "
        .. "layout %s, watch %s, NewTicker %s"):format(flag(call(f.IsShown, f)), flag(call(f.IsVisible, f)),
        tostring(call(f.GetAlpha, f)), nameOf(parent), flag(type(parent) == "table" and call(parent.IsVisible, parent)),
        tonumber(call(f.GetLeft, f)) or -1, tonumber(call(f.GetBottom, f)) or -1, table.concat(points, "; "),
        flag(on), flag(watcher ~= nil), flag(type(C_Timer) == "table" and type(C_Timer.NewTicker) == "function"))
end

function TotemBar.OnCombatEnd()
    if pending then
        TotemBar.Place()
    end
end

ns.Layout.OnChange(function(layoutOn)
    on = layoutOn == true and totemBar() ~= nil
    TotemBar.Place()
    if on then
        startWatch()
    else
        stopWatch()
    end
end)
