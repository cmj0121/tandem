local _, ns = ...

-- The class macros: per class, the macros one flyout button offers (first the Shaman's cures and Stormstrike), each
-- shown while the player knows its spells, and the entry each character last picked.
local ClassMacros = {}
ns.ClassMacros = ClassMacros

local Cure = ns.Cure
local call = ns.Store.Call

local STORMSTRIKE = "#showtooltip %s\n/targetenemy [noharm][dead]\n/startattack [harm]\n/cast %s"
local TOTEMS = "#showtooltip\n/cast [btn:2] %s; %s"

local ASTRAL_RECALL, HEARTHSTONE = 556, 6948
-- A cooldown this short or shorter is the global cooldown, so the spell counts as ready.
local GCD = 1.5
-- The recall bodies per RecallState: Astral Recall ready, on cooldown, or unreadable (the cast line fails while it
-- is on cooldown and the use line runs), and none for no Hearthstone in the bags. Right click always uses the
-- Hearthstone; in combat, where the macro cannot change, both clicks show and use it, casting Astral Recall only
-- when the Hearthstone cannot be used.
local RECALL = {
    spell = "#showtooltip [combat] item:6948; %s\n/use [combat][btn:2] item:6948\n/cast [combat] %s\n"
        .. "/cast [nocombat,nobtn:2] %s",
    item = "#showtooltip item:6948\n/use item:6948",
    unknown = "#showtooltip [combat] item:6948; %s\n/use [combat][btn:2] item:6948\n/cast [nobtn:2] %s\n"
        .. "/use [nocombat,nobtn:2] item:6948",
    none = "#showtooltip %s\n/use [btn:2] item:6948; %s",
}
local function hearthCount()
    local n = call(C_Item and C_Item.GetItemCount, HEARTHSTONE)
    if n == nil then
        n = call(GetItemCount, HEARTHSTONE)
    end
    return n
end

local function hearthIcon()
    return call(C_Item and C_Item.GetItemIconByID, HEARTHSTONE) or call(_G.GetItemIcon, HEARTHSTONE)
end

-- The hyperlink of the item the recall macro shows in combat, for the flyout row's combat tooltip.
ClassMacros.COMBAT_LINK = "item:" .. HEARTHSTONE

-- Per class, its entries in display order, bottom-up: the id, the spells it needs known (the first gives the icon),
-- its character macro's name, the debuff types it cures, its description (an enUS locale key) and its macro body
-- for the spells' localized names and the recall state (RecallState); logKnown debug-logs whether each of its spells
-- is known, once per login; noPick keeps its row from becoming the pick; note returns an enUS locale key the tooltip
-- adds, or nil; combat returns whether its body has a combat clause, and combatIcon the icon the row then shows, or
-- nil.
ClassMacros.ENTRIES = {
    SHAMAN = {
        {
            id = "poison", spells = { 526 }, macro = "Tandem Poison", kinds = { "Poison" },
            description = "Cures poison on your mouseover friend, your target or yourself",
            body = function(names)
                return Cure.MacroBody(names[1])
            end,
        },
        {
            id = "disease", spells = { 2870 }, macro = "Tandem Disease", kinds = { "Disease" },
            description = "Cures disease on your mouseover friend, your target or yourself",
            body = function(names)
                return Cure.MacroBody(names[1])
            end,
        },
        {
            id = "cure", spells = { 526, 2870 }, macro = "Tandem Cure", kinds = { "Poison", "Disease" },
            description = "Left-click cures poison, right-click cures disease",
            body = function(names)
                return Cure.CombinedBody(names[1], names[2])
            end,
        },
        {
            id = "totems", spells = { 66842, 66843 }, macro = "Tandem Totems", kinds = {}, logKnown = true,
            description = "Left-click casts Call of the Elements, right-click casts Call of the "
                .. "Ancestors",
            body = function(names)
                return TOTEMS:format(names[2], names[1])
            end,
        },
        {
            id = "stormstrike", spells = { 17364 }, macro = "Tandem Stormstrike", kinds = {}, logKnown = true,
            description = "Switches to the nearest enemy when your target is missing, dead or friendly (it may be one "
                .. "not yet fighting), starts attacking and casts Stormstrike",
            body = function(names)
                return STORMSTRIKE:format(names[1], names[1])
            end,
        },
        {
            id = "recall", spells = { ASTRAL_RECALL }, macro = "Tandem Recall", kinds = {}, noPick = true,
            description = "Left-click casts Astral Recall, or uses your Hearthstone while it is on cooldown; "
                .. "right-click uses your Hearthstone; in combat both use your Hearthstone",
            body = function(names, state)
                if hearthCount() == 0 then
                    state = "none"
                end
                return RECALL[state]:format(names[1], names[1], names[1])
            end,
            note = function()
                return hearthCount() == 0 and "No Hearthstone in your bags" or nil
            end,
            combat = function()
                return hearthCount() ~= 0
            end,
            combatIcon = hearthIcon,
        },
    },
}

local loggedKnown, loggedRecall = {}, nil

local function log(text)
    if ns.Debug ~= nil and ns.Debug.IsOn() then
        ns.Debug.Log(text)
    end
end

-- Debug-logs, once per login, whether each of the logKnown entry's spells is known.
local function logKnown(e)
    if not e.logKnown or loggedKnown[e.id] then
        return
    end
    loggedKnown[e.id] = true
    for _, id in ipairs(e.spells) do
        local known = tostring(Cure.Known(id))
        if #e.spells == 1 then
            log(("class macros: %s known=%s"):format(e.id, known))
        else
            log(("class macros: %s %d known=%s"):format(e.id, id, known))
        end
    end
end

-- The localized names of the entry's spells and its first spell's icon, or nil when one is unknown or unnamed.
local function resolve(e)
    logKnown(e)
    local names, icon = {}, nil
    for i, id in ipairs(e.spells) do
        local known = Cure.Known(id)
        local name, spellIcon = Cure.SpellInfo(id)
        if not (known and name) then
            return nil
        end
        names[i] = name
        icon = icon or spellIcon
    end
    return names, icon
end

local function copy(list)
    local out = {}
    for i, v in ipairs(list) do
        out[i] = v
    end
    return out
end

-- The value's type for the debug line, "secret" for a secret one.
local function kind(v)
    if issecretvalue and issecretvalue(v) then
        return "secret"
    end
    return type(v)
end

local function plain(v)
    return not (issecretvalue and issecretvalue(v)) and type(v) == "number"
end

-- ClassMacros.RecallState() -> "spell"|"item"|"unknown", readyAt|nil: whether Astral Recall's cooldown reads 0 (or
-- only the global cooldown), reads more (readyAt is the GetTime it ends at) or cannot be read (a part missing or
-- secret). Debug-logs the raw start and duration types once per state change.
function ClassMacros.RecallState()
    local start, duration
    local cd = call(C_Spell and C_Spell.GetSpellCooldown, ASTRAL_RECALL)
    if type(cd) == "table" then
        start, duration = cd.startTime, cd.duration
    elseif type(GetSpellCooldown) == "function" then
        -- Raw, not through call (which turns a secret into nil), so the debug line tells a secret from a nil.
        local ok, s, d = pcall(GetSpellCooldown, ASTRAL_RECALL)
        if ok then
            start, duration = s, d
        end
    end
    local state, readyAt = "unknown", nil
    if plain(start) and plain(duration) then
        if start == 0 or duration <= GCD then
            state = "spell"
        else
            state, readyAt = "item", start + duration
        end
    end
    if state ~= loggedRecall then
        loggedRecall = state
        log(("class macros: recall state=%s start=%s duration=%s"):format(state, kind(start), kind(duration)))
    end
    return state, readyAt
end

-- ClassMacros.List(classFile, state) -> { entry... }: the class's shown entries in display order, each { id, title
-- (the localized spell names), icon, body (the macro's), cast (the body without its #showtooltip line), macro,
-- description (localized), kinds, noPick, note (localized or nil), combat (true or nil), combatIcon (or nil) }, the
-- bodies for the recall state (read now when nil); empty for a class without entries.
function ClassMacros.List(classFile, state)
    local shown = {}
    for _, e in ipairs(ClassMacros.ENTRIES[classFile] or {}) do
        local names, icon = resolve(e)
        if names then
            state = state or ClassMacros.RecallState()
            local note = e.note and e.note()
            local body = e.body(names, state)
            local combat = e.combat and e.combat() or nil
            shown[#shown + 1] = {
                id = e.id,
                title = table.concat(names, " / "),
                icon = icon,
                body = body,
                cast = (body:gsub("^#showtooltip[^\n]*\n", "")),
                macro = e.macro,
                description = ns.L[e.description],
                kinds = copy(e.kinds),
                noPick = e.noPick,
                note = note and ns.L[note] or nil,
                combat = combat,
                combatIcon = combat and e.combatIcon() or nil,
            }
        end
    end
    return shown
end

local function playerClass()
    local _, classFile = call(UnitClass, "player")
    return classFile
end

-- ClassMacros.Pick(state) -> entry|nil: the player's picked shown entry, else the first shown one, never a noPick
-- one; nil when none is shown. state goes to List.
function ClassMacros.Pick(state)
    local list = {}
    for _, e in ipairs(ClassMacros.List(playerClass(), state)) do
        if not e.noPick then
            list[#list + 1] = e
        end
    end
    local key = ns.Weights.CharacterKey()
    local saved = key and ns.Store.Pick(key)
    for _, e in ipairs(list) do
        if e.id == saved then
            return e
        end
    end
    return list[1]
end

-- ClassMacros.SetPick(id) -> saved: saves id, one of the player's class entries, as the character's pick; false
-- when it is no such entry, a noPick one, the character is unknown or the db is read-only.
function ClassMacros.SetPick(id)
    local key = ns.Weights.CharacterKey()
    for _, e in ipairs(ClassMacros.ENTRIES[playerClass()] or {}) do
        if e.id == id and not e.noPick then
            return key ~= nil and ns.Store.SetPick(key, id)
        end
    end
    return false
end
