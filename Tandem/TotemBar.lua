local _, ns = ...

-- Blizzard's totem bar (stage 12, D13): while the Tandem layout is on, MultiCastActionBarFrame (secure totem buttons)
-- sits right of the three-bar block. It has no Edit Mode system, so it moves by SetPoint, only out of combat (a move
-- in combat waits for PLAYER_REGEN_ENABLED), again whenever Blizzard may have re-anchored it, and goes back to its
-- saved points on off.
local TotemBar = {}
ns.TotemBar = TotemBar

local GAP = 8

-- saved = { manager = ignoreFramePositionManager as it was, points = { {point, relativeTo, ...}, ... } }
local saved, on, pending

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

function TotemBar.OnCombatEnd()
    if pending then
        TotemBar.Place()
    end
end

ns.Layout.OnChange(function(layoutOn)
    on = layoutOn == true
    TotemBar.Place()
end)
