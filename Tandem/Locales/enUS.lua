local _, ns = ...

-- English text is the key: a string with no translation shows its English key.
ns.L = setmetatable({}, {
    __index = function(_, key)
        return key
    end,
})

-- Tooltip stat lines (decision 7) as { Lua pattern capturing the number, stat key }, tried in order on each line as
-- shown; the first match wins. Only English clients get these; zhTW sets its own, and any other locale has none, so
-- its items stay unparsed instead of being saved as stat-less.
local english = GetLocale() == "enUS" or GetLocale() == "enGB"
ns.StatPatterns = english and {
    { "^%+(%d+) Strength$", "str" },
    { "^%+(%d+) Agility$", "agi" },
    { "^%+(%d+) Stamina$", "sta" },
    { "^%+(%d+) Intellect$", "int" },
    { "^%+(%d+) Spirit$", "spi" },
    { "^(%d+) Armor$", "armor" },
    { "^(%d+) Block$", "blockvalue" },
    { "^%((%d+%.?%d*) damage per second%)$", "dps" },
    { "^Equip: %+(%d+) Attack Power%.?$", "ap" },
    { "^Equip: %+(%d+) ranged Attack Power%.?$", "rap" },
    { "^Equip: Increases damage and healing done by magical spells and effects by up to (%d+)%.?$", "sp" },
    { "^Equip: Increases healing done by spells and effects by up to (%d+)%.?$", "heal" },
    { "^Equip: Improves your chance to hit by (%d+%.?%d*)%%%.?$", "hit" },
    { "^Equip: Improves your chance to get a critical strike by (%d+%.?%d*)%%%.?$", "crit" },
    { "^Equip: Improves your chance to hit with spells by (%d+%.?%d*)%%%.?$", "spellhit" },
    { "^Equip: Improves your chance to get a critical strike with spells by (%d+%.?%d*)%%%.?$", "spellcrit" },
    { "^Equip: Restores (%d+) mana per 5 sec%.?$", "mp5" },
    { "^Equip: Increased Defense %+(%d+)%.?$", "def" },
    { "^Equip: Increases your chance to dodge an attack by (%d+%.?%d*)%%%.?$", "dodge" },
    { "^Equip: Increases your chance to parry an attack by (%d+%.?%d*)%%%.?$", "parry" },
    { "^Equip: Increases your chance to block attacks with a shield by (%d+%.?%d*)%%%.?$", "block" },
    { "^Equip: Increases the block value of your shield by (%d+)%.?$", "blockvalue" },
} or nil
