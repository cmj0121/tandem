local _, ns = ...

-- Spell rank state per action slot (decision 5). Red: the slot holds a lower rank of a spell already known at a
-- higher rank. Yellow, only when not red: the player's own trainer records (decision 4) teach a higher rank
-- than the highest known one at or below the player's level, not yet known. Read-only: drawing and events belong to
-- ActionBorders. Known ranks and trainable ranks per spell name are cached until SpellRanks.Invalidate().
local SpellRanks = {}
ns.SpellRanks = SpellRanks

local Safe = ns.Store.Safe

local cache

local function spellName(id)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = Safe(C_Spell.GetSpellInfo(id))
        return type(info) == "table" and Safe(info.name) or nil
    elseif GetSpellInfo then
        return Safe((GetSpellInfo(id)))
    end
end

local function subtextRank(id)
    local get = (C_Spell and C_Spell.GetSpellSubtext) or GetSpellSubtext
    local text = get and Safe(get(id))
    local digits = type(text) == "string" and text:match("%d+")
    return digits and tonumber(digits)
end

local function isKnown(id)
    if IsSpellKnown and Safe(IsSpellKnown(id)) then
        return true
    end
    return IsPlayerSpell ~= nil and Safe(IsPlayerSpell(id)) == true
end

-- Calls fn(spellID) for every learned spell in the player's spellbook; false when no spellbook API exists.
local function eachBookSpell(fn)
    local book = C_SpellBook
    if book and book.GetNumSpellBookSkillLines and book.GetSpellBookSkillLineInfo and book.GetSpellBookItemInfo then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        local spellType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
        for line = 1, Safe(book.GetNumSpellBookSkillLines()) or 0 do
            local info = Safe(book.GetSpellBookSkillLineInfo(line))
            local offset = type(info) == "table" and Safe(info.itemIndexOffset)
            local count = type(info) == "table" and Safe(info.numSpellBookItems)
            if type(offset) == "number" and type(count) == "number" then
                for index = offset + 1, offset + count do
                    local item = Safe(book.GetSpellBookItemInfo(index, bank))
                    local id = type(item) == "table" and Safe(item.spellID)
                    if type(id) == "number" and (spellType == nil or Safe(item.itemType) == spellType) then
                        fn(id)
                    end
                end
            end
        end
        return true
    end
    if GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemInfo then
        local bank = BOOKTYPE_SPELL or "spell"
        for tab = 1, Safe(GetNumSpellTabs()) or 0 do
            local _, _, offset, count = GetSpellTabInfo(tab)
            offset, count = Safe(offset), Safe(count)
            if type(offset) == "number" and type(count) == "number" then
                for index = offset + 1, offset + count do
                    local kind, id = GetSpellBookItemInfo(index, bank)
                    kind, id = Safe(kind), Safe(id)
                    if kind == "SPELL" and type(id) == "number" then
                        fn(id)
                    end
                end
            end
        end
        return true
    end
    return false
end

local function build()
    local known, trainable, ranks = {}, {}, {}
    local readable = eachBookSpell(function(id)
        local name, rank = spellName(id), subtextRank(id)
        if name and rank and rank > (known[name] or 0) then
            known[name] = rank
        end
    end)
    local _, classFile = UnitClass("player")
    classFile = Safe(classFile)
    local level = Safe(UnitLevel("player"))
    local own = type(classFile) == "string" and ns.Store.db and ns.Store.TrainerSpells(classFile)
    if type(own) == "table" and type(level) == "number" then
        for id, entry in pairs(own) do
            if type(id) == "number" and type(entry) == "table" and type(entry.level) == "number" then
                local rank = type(entry.rank) == "number" and entry.rank or subtextRank(id)
                ranks[id] = rank
                local name = spellName(id)
                if name and rank and entry.level <= level and rank > (trainable[name] or 0) and not isKnown(id) then
                    trainable[name] = rank
                end
            end
        end
    end
    return { readable = readable, known = known, trainable = trainable, ranks = ranks }
end

-- Drops the cached ranks; the next State call rebuilds them. Call when spells, level, trainer data or bars change.
function SpellRanks.Invalidate()
    cache = nil
end

-- Returns "red", "yellow" or nil for an action slot; nil for macros, items, empty or unreadable slots, and when the
-- spellbook cannot be read.
function SpellRanks.State(slot)
    if not GetActionInfo then
        return nil
    end
    local kind, id = GetActionInfo(slot)
    kind, id = Safe(kind), Safe(id)
    if kind ~= "spell" or type(id) ~= "number" then
        return nil
    end
    cache = cache or build()
    local name = spellName(id)
    if not cache.readable or not name then
        return nil
    end
    local rank = subtextRank(id) or cache.ranks[id]
    local best = cache.known[name]
    if rank and best and best > rank then
        return "red"
    end
    local nextRank = cache.trainable[name]
    if nextRank and nextRank > math.max(best or 0, rank or 0) then
        return "yellow"
    end
    return nil
end
