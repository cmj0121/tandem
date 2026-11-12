local _, ns = ...

-- The class macros: per class, the macros one flyout button offers (first the Shaman's cures and Stormstrike), each
-- shown while the player knows its spells, and the entry each character last picked.
local ClassMacros = {}
ns.ClassMacros = ClassMacros

local Cure = ns.Cure
local call = ns.Store.Call

local STORMSTRIKE = "#showtooltip %s\n/targetenemy [noharm][dead]\n/startattack [harm]\n/cast %s"

-- Per class, its entries in display order, bottom-up: the id, the spells it needs known (the first gives the icon),
-- its character macro's name, the debuff types it cures, its description (an enUS locale key) and its macro body
-- for the spells' localized names; logKnown debug-logs whether its spell is known, once per login.
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
            id = "stormstrike", spells = { 17364 }, macro = "Tandem Stormstrike", kinds = {}, logKnown = true,
            description = "Switches to the nearest enemy when your target is missing, dead or friendly (it may be one "
                .. "not yet fighting), starts attacking and casts Stormstrike",
            body = function(names)
                return STORMSTRIKE:format(names[1], names[1])
            end,
        },
    },
}

local loggedKnown

local function log(text)
    if ns.Debug ~= nil and ns.Debug.IsOn() then
        ns.Debug.Log(text)
    end
end

-- The localized names of the entry's spells and its first spell's icon, or nil when one is unknown or unnamed.
local function resolve(e)
    local names, icon = {}, nil
    for i, id in ipairs(e.spells) do
        local known = Cure.Known(id)
        if e.logKnown and not loggedKnown then
            loggedKnown = true
            log(("class macros: stormstrike known=%s"):format(tostring(known)))
        end
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

-- ClassMacros.List(classFile) -> { entry... }: the class's shown entries in display order, each { id, title (the
-- localized spell names), icon, body (the macro's), cast (the body without its #showtooltip line), macro,
-- description (localized), kinds }; empty for a class without entries.
function ClassMacros.List(classFile)
    local shown = {}
    for _, e in ipairs(ClassMacros.ENTRIES[classFile] or {}) do
        local names, icon = resolve(e)
        if names then
            local body = e.body(names)
            shown[#shown + 1] = {
                id = e.id,
                title = table.concat(names, " / "),
                icon = icon,
                body = body,
                cast = (body:gsub("^#showtooltip[^\n]*\n", "")),
                macro = e.macro,
                description = ns.L[e.description],
                kinds = copy(e.kinds),
            }
        end
    end
    return shown
end

local function playerClass()
    local _, classFile = call(UnitClass, "player")
    return classFile
end

-- ClassMacros.Pick() -> entry|nil: the player's picked shown entry, else the first shown one; nil when none is shown.
function ClassMacros.Pick()
    local list = ClassMacros.List(playerClass())
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
-- when it is no such entry, the character is unknown or the db is read-only.
function ClassMacros.SetPick(id)
    local key = ns.Weights.CharacterKey()
    for _, e in ipairs(ClassMacros.ENTRIES[playerClass()] or {}) do
        if e.id == id then
            return key ~= nil and ns.Store.SetPick(key, id)
        end
    end
    return false
end
