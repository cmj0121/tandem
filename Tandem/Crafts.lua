local _, ns = ...

-- The craftable list (craft flyout D1, D3): the item-making spells the player knows, the highest known rank of each
-- seed family plus any spell whose item was learned from a cast, and the learned tradeskill recipes cached while a
-- profession window was open; only items that can be used are kept, and an item the client has not loaded yet is
-- kept and checked again when its info arrives. A pair is learned when exactly one bag item's count rises within
-- WATCH seconds of a player cast out of combat with no loot, mail, trade, merchant, quest or bank window open (nor a
-- quest turned in); at most MAX_PAIRS are kept, the least recently made dropped first. A recipe read back unlearned,
-- or missing from its open profession's list, or whose profession spell the player no longer knows, leaves the cache.
-- Pairs, recipes, made times and the pick are saved per character through Store (in memory only while the character
-- is unknown).
-- Reads only: it never opens a profession window; TryCraft crafts only in a window the player opened. Its debug lines,
-- and the craft flyout's, go to their own channel TandemDebug.crafts (the last LOG_LIMIT), which login does not flush,
-- up to LOG_LIMIT a session.
local Crafts = {}
ns.Crafts = Crafts

local WATCH = 3
local BAGS = 4
local LOG_LIMIT = 300
Crafts.MAX_PAIRS = 40
-- Gathering and opening spells, never learned as pairs: their loot reaches the bags after auto-loot has closed the
-- loot window, often unseen. Fishing is not on the list.
Crafts.SKIP_SPELLS = {}
for _, spell in ipairs({ 3365, 6247, 6477, 6478, 21248, 22810, 1804, 8613, 8617, 8618, 10768, 2575, 2576, 3564,
    10248, 2366, 2368, 3570, 11993, 13262 }) do
    Crafts.SKIP_SPELLS[spell] = true
end

-- Seed families, each its ranks lowest first as { spell = <spellID>, item = <itemID> } (classic IDs).
local function ranks(list)
    local out = {}
    for i = 1, #list, 2 do
        out[#out + 1] = { spell = list[i], item = list[i + 1] }
    end
    return out
end
Crafts.SPELLS = {
    water = ranks({ 5504, 5350, 5505, 2288, 5506, 2136, 6127, 3772, 10138, 8077, 10139, 8078, 10140, 8079 }),
    food = ranks({ 587, 5349, 597, 1113, 990, 1114, 6129, 1487, 10144, 8075, 10145, 8076, 28612, 22895 }),
    manaGem = ranks({ 759, 5514, 3552, 5513, 10053, 8007, 10054, 8008 }),
    healthstone = ranks({ 6201, 5512, 6202, 5511, 5699, 5509, 11729, 5510, 11730, 9421 }),
    soulstone = ranks({ 693, 5232, 20752, 16892, 20755, 16893, 20756, 16895, 20757, 16896 }),
    spellstone = ranks({ 2362, 5522, 17727, 13602, 17728, 13603 }),
    firestone = ranks({ 6366, 1254, 17951, 13699, 17952, 13700, 17953, 13701 }),
}
local SEED = {}
for _, family in pairs(Crafts.SPELLS) do
    for _, r in ipairs(family) do
        SEED[r.spell] = true
    end
end

-- The events on this module's own frame; any may be rejected by the client.
local EVENTS = { "LOOT_OPENED", "LOOT_CLOSED", "MAIL_SHOW", "MAIL_CLOSED", "TRADE_SHOW", "TRADE_CLOSED",
    "MERCHANT_SHOW", "MERCHANT_CLOSED", "QUEST_COMPLETE", "QUEST_FINISHED", "QUEST_TURNED_IN", "BANKFRAME_OPENED",
    "BANKFRAME_CLOSED", "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED", "LOOT_READY", "TRADE_SKILL_SHOW",
    "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED" }
local WINDOWS = {
    LOOT_OPENED = { "loot", true }, LOOT_CLOSED = { "loot", false }, MAIL_SHOW = { "mail", true },
    MAIL_CLOSED = { "mail", false }, TRADE_SHOW = { "trade", true }, TRADE_CLOSED = { "trade", false },
    MERCHANT_SHOW = { "merchant", true }, MERCHANT_CLOSED = { "merchant", false },
    QUEST_COMPLETE = { "quest", true }, QUEST_FINISHED = { "quest", false },
    BANKFRAME_OPENED = { "bank", true }, BANKFRAME_CLOSED = { "bank", false },
    GUILDBANKFRAME_OPENED = { "guildbank", true }, GUILDBANKFRAME_CLOSED = { "guildbank", false },
}
-- Events that spoil the watched cast without a window staying open.
local SPOILS = { QUEST_TURNED_IN = true, LOOT_READY = true }

local call, Safe = ns.Store.Call, ns.Store.Safe

local events
local open = {}
-- The window flags kept: only those whose open and close events both registered.
local tracked = {}
-- This session's crafts { pairs, recipes, made, pick }, merged with the saved ones once the character is known.
local mem = { pairs = {}, recipes = {}, made = {} }
local loadedKey
-- The items read before their info loaded, re-checked on GET_ITEM_INFO_RECEIVED.
local pending = {}
-- The cast whose bag gain is watched: spell, when, bag counts by item ID then, and whether a window spoiled it.
local watch
local listeners = {}
local lastSig
local logged = 0

-- Crafts.Log(what): while debugging, appends one line (time, combat, what) to TandemDebug.crafts, keeping the last
-- LOG_LIMIT and at most LOG_LIMIT a session.
function Crafts.Log(what)
    if logged >= LOG_LIMIT or not ns.Debug.IsOn() then
        return
    end
    logged = logged + 1
    if type(TandemDebug.crafts) ~= "table" then
        TandemDebug.crafts = {}
    end
    local out = TandemDebug.crafts
    out[#out + 1] = ("%.2f combat=%s %s"):format(tonumber((call(_G.GetTime))) or 0,
        tostring(call(_G.InCombatLockdown) == true), what)
    while #out > LOG_LIMIT do
        table.remove(out, 1)
    end
end

local function log(what)
    Crafts.Log("crafts: " .. what)
end

local function isText(v)
    return type(v) == "string" and v ~= ""
end

local function isID(v)
    return type(v) == "number" and v >= 1 and v % 1 == 0
end

local function anyOpen()
    for _, on in pairs(open) do
        if on then
            return true
        end
    end
    return false
end

local function now()
    return tonumber((call(_G.GetTime))) or 0
end

-- Returns the crafts state, loading the saved data once the character is known; what this session learned before
-- then is kept and saved too.
local function state()
    local key = ns.Weights.CharacterKey()
    if key and key ~= loadedKey and ns.Store.db then
        loadedKey = key
        local saved = ns.Store.Crafts(key)
        for spell, item in pairs(mem.pairs) do
            saved.pairs[spell] = item
            ns.Store.SetCraftPair(key, spell, item)
        end
        for id, r in pairs(mem.recipes) do
            saved.recipes[id] = r
            ns.Store.SetCraftRecipe(key, id, r)
        end
        for id, when in pairs(mem.made) do
            saved.made[id] = when
            ns.Store.SetCraftMade(key, id, when)
        end
        if mem.pick then
            saved.pick = mem.pick
            ns.Store.SetCraftPick(key, mem.pick)
        end
        mem = saved
    end
    return mem, loadedKey
end

local function isKnown(spell)
    return call(_G.IsPlayerSpell, spell) == true or call(_G.IsSpellKnown, spell) == true
end

local function spellInfo(spell)
    local c = type(_G.C_Spell) == "table" and _G.C_Spell or {}
    local info = call(c.GetSpellInfo, spell)
    if type(info) == "table" then
        return Safe(info.name), Safe(info.iconID)
    end
    local name = call(c.GetSpellName, spell)
    if name then
        return name, (call(c.GetSpellTexture, spell))
    end
    local legacyName, _, icon = call(_G.GetSpellInfo, spell)
    return legacyName, icon
end

-- The item classes of an item enhancement (an armor kit, an oil), used on other gear rather than made to be used:
-- class 8, or the older Consumable class 0 with its Item Enhancement subclass 6.
local ENHANCEMENT_CLASS, CONSUMABLE_CLASS, ENHANCEMENT_SUBCLASS = 8, 0, 6
-- dropped[item] = true once its "enhancement dropped" line is logged.
local dropped = {}

-- Whether item can be used (D1): it has a use spell or is a consumable, and is not an item enhancement. True for an
-- unknown item, and for one whose info is not loaded yet, which is then asked for and re-checked when it arrives.
local function usable(item)
    if not item then
        return true
    end
    local c = type(_G.C_Item) == "table" and _G.C_Item or {}
    if not call(c.GetItemInfo or _G.GetItemInfo, item) then
        pending[item] = true
        call(c.RequestLoadItemDataByID, item)
        return true
    end
    local classID, subclassID = select(6, call(c.GetItemInfoInstant or _G.GetItemInfoInstant, item))
    if classID == ENHANCEMENT_CLASS or classID == CONSUMABLE_CLASS and subclassID == ENHANCEMENT_SUBCLASS then
        if not dropped[item] then
            dropped[item] = true
            log(("enhancement dropped item=%s class=%s/%s"):format(tostring(item), tostring(classID),
                tostring(subclassID)))
        end
        return false
    end
    if call(c.GetItemSpell or _G.GetItemSpell, item) then
        return true
    end
    return classID == CONSUMABLE_CLASS
end

-- The camp recipes the flyout lists (by recipe ID, or by the item a recipe makes); any other recipe is left out, so a
-- profession shows its camp gear only: Leatherworking's 營地帳篷 (Camp Tent) and Cooking's Basic Campfire, which
-- makes no item.
Crafts.CAMP_RECIPES = { [818] = true, [1229432] = true }
Crafts.CAMP_ITEMS = { [279978] = true }

local function camp(recipe, item)
    return Crafts.CAMP_RECIPES[recipe] == true or item ~= nil and Crafts.CAMP_ITEMS[item] == true
end

local function spellEntry(s, spell, seedItem)
    local name, icon = spellInfo(spell)
    local id = "spell:" .. spell
    return { id = id, kind = "spell", name = name or id, icon = icon, spell = spell, item = s.pairs[spell] or seedItem,
        made = s.made[id] }
end

-- Crafts.List() -> entries { id, kind, name, icon, spell | recipe, profession (recipe), item|nil, made|nil }: one per
-- seed family at its highest known rank, per learned non-seed spell still known and per cached camp recipe, whose item
-- can be used; the pick first, then the latest made, then by name.
function Crafts.List()
    local s = state()
    local all = {}
    for _, family in pairs(Crafts.SPELLS) do
        for i = #family, 1, -1 do
            if isKnown(family[i].spell) then
                all[#all + 1] = spellEntry(s, family[i].spell, family[i].item)
                break
            end
        end
    end
    for spell in pairs(s.pairs) do
        if not SEED[spell] and not s.recipes[spell] and isKnown(spell) then
            all[#all + 1] = spellEntry(s, spell)
        end
    end
    for recipe, r in pairs(s.recipes) do
        local id, item = "recipe:" .. recipe, s.pairs[recipe] or r.item
        if camp(recipe, item) then
            all[#all + 1] = { id = id, kind = "recipe", name = r.name, icon = r.icon, recipe = recipe,
                profession = r.profession, item = item, made = s.made[id] }
        end
    end
    local out = {}
    for _, e in ipairs(all) do
        if usable(e.item) then
            out[#out + 1] = e
        end
    end
    table.sort(out, function(a, b)
        if (a.id == s.pick) ~= (b.id == s.pick) then
            return a.id == s.pick
        end
        if (a.made or -1) ~= (b.made or -1) then
            return (a.made or -1) > (b.made or -1)
        end
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.id < b.id
    end)
    return out
end

-- Calls each OnChange listener once the list differs from the one they last saw.
local function notify()
    local parts = {}
    for _, e in ipairs(Crafts.List()) do
        parts[#parts + 1] = ("%s:%s:%s:%s"):format(e.id, tostring(e.item), e.name, tostring(e.icon))
    end
    local sig = table.concat(parts, "|")
    if sig == lastSig then
        return
    end
    lastSig = sig
    log("list " .. (#parts > 0 and sig or "empty"))
    for _, fn in ipairs(listeners) do
        fn()
    end
end

-- Crafts.OnChange(fn): fn() is called whenever the list changes.
function Crafts.OnChange(fn)
    listeners[#listeners + 1] = fn
end

-- Crafts.Pick() -> the entry the button shows: the saved pick, else the first of the list; nil when empty.
function Crafts.Pick()
    return Crafts.List()[1]
end

-- Crafts.SetPick(id) -> saved: makes the listed entry id the pick; false when it is not listed.
function Crafts.SetPick(id)
    local s, key = state()
    for _, e in ipairs(Crafts.List()) do
        if e.id == id then
            s.pick = id
            if key then
                ns.Store.SetCraftPick(key, id)
            end
            log("pick " .. id)
            notify()
            return true
        end
    end
    return false
end

-- Crafts.MarkMade(id) -> saved: records now as when the entry id was last made; false for a malformed id or no clock.
function Crafts.MarkMade(id)
    local when = call(_G.time)
    if type(id) ~= "string" or not (id:match("^spell:%d+$") or id:match("^recipe:%d+$")) or not isID(when) then
        return false
    end
    local s, key = state()
    s.made[id] = when
    if key then
        ns.Store.SetCraftMade(key, id, when)
    end
    log("made " .. id)
    notify()
    return true
end

-- Returns the bag counts by item ID, bags 0..BAGS, through C_Container or the old globals.
local function counts()
    local c = type(_G.C_Container) == "table" and _G.C_Container or {}
    local numSlots = c.GetContainerNumSlots or _G.GetContainerNumSlots
    local itemID = c.GetContainerItemID or _G.GetContainerItemID
    local itemInfo = c.GetContainerItemInfo or _G.GetContainerItemInfo
    local out = {}
    for bag = 0, BAGS do
        local n = call(numSlots, bag)
        for slot = 1, type(n) == "number" and n or 0 do
            local id = call(itemID, bag, slot)
            if type(id) == "number" then
                local info, count = call(itemInfo, bag, slot)
                if type(info) == "table" then
                    count = info.stackCount
                end
                out[id] = (out[id] or 0) + (tonumber(count) or 1)
            end
        end
    end
    return out
end

local function setPair(s, key, spell, item)
    s.pairs[spell] = item
    if key then
        ns.Store.SetCraftPair(key, spell, item)
    end
end

-- Returns when spell's entry was last made (as a spell or a recipe), 0 when never.
local function madeAt(s, spell)
    return math.max(s.made["spell:" .. spell] or 0, s.made["recipe:" .. spell] or 0)
end

local function learn(spell, item)
    local s, key = state()
    if s.pairs[spell] ~= item then
        local n, oldest = 0, nil
        for other in pairs(s.pairs) do
            n = n + 1
            if other ~= spell and (not oldest or madeAt(s, other) < madeAt(s, oldest)
                or (madeAt(s, other) == madeAt(s, oldest) and other < oldest)) then
                oldest = other
            end
        end
        if not s.pairs[spell] and n >= Crafts.MAX_PAIRS and oldest then
            setPair(s, key, oldest, nil)
            log("pair dropped " .. oldest)
        end
        setPair(s, key, spell, item)
    end
    log(("pair %d -> %d"):format(spell, item))
    Crafts.MarkMade((s.recipes[spell] and "recipe:" or "spell:") .. spell)
end

-- Crafts.OnBagUpdate(): BAG_UPDATE_DELAYED. Within WATCH seconds of a watched cast, the first rise in bag counts ends
-- the watch: exactly one item risen with no window open in the meantime becomes the cast's pair, unless the spell is
-- in SKIP_SPELLS.
function Crafts.OnBagUpdate()
    if not watch then
        return
    end
    if now() - watch.at > WATCH then
        watch = nil
        return
    end
    local after = counts()
    local rose = {}
    for id, n in pairs(after) do
        if n > (watch.bags[id] or 0) then
            rose[#rose + 1] = id
        end
    end
    if #rose == 0 then
        return
    end
    local w = watch
    watch = nil
    local reason = Crafts.SKIP_SPELLS[w.spell] and "skip" or #rose ~= 1 and ("rose=" .. #rose)
        or (w.spoiled or anyOpen()) and "window" or nil
    if reason then
        log(("pair skipped spell=%d reason=%s"):format(w.spell, reason))
        return
    end
    learn(w.spell, rose[1])
end

local function onCast(unit, spell)
    if Safe(unit) ~= "player" or not isID(Safe(spell)) or call(_G.InCombatLockdown) == true then
        return
    end
    watch = { spell = spell, at = now(), bags = counts(), spoiled = anyOpen() }
end

-- Returns the item a recipe makes, from its schematic or else its output data; nil when neither tells.
local function outputItem(ui, recipe)
    local schematic = call(ui.GetRecipeSchematic, recipe, false)
    local item = type(schematic) == "table" and Safe(schematic.outputItemID)
    if isID(item) then
        return item
    end
    local data = call(ui.GetRecipeOutputItemData, recipe)
    item = type(data) == "table" and Safe(data.itemID)
    return isID(item) and item or nil
end

local function sameRecipe(a, b)
    return a and a.name == b.name and a.icon == b.icon and a.item == b.item and a.profession == b.profession
end

local function setRecipe(s, key, recipe, r)
    s.recipes[recipe] = r
    if key then
        ns.Store.SetCraftRecipe(key, recipe, r)
    end
end

-- A recipe newly cached takes the made time its cast recorded as a spell before it was known as a recipe.
local function moveMade(s, key, recipe)
    local from, to = "spell:" .. recipe, "recipe:" .. recipe
    local when = s.made[from]
    if not when then
        return
    end
    s.made[from] = nil
    if (s.made[to] or -1) < when then
        s.made[to] = when
    end
    if key then
        ns.Store.SetCraftMade(key, from, nil)
        ns.Store.SetCraftMade(key, to, s.made[to])
    end
end

-- Crafts.ReadRecipes(): caches every learned recipe of the open profession window through C_TradeSkillUI.
function Crafts.ReadRecipes()
    local ui = _G.C_TradeSkillUI
    if type(ui) ~= "table" then
        return
    end
    local ids = call(ui.GetAllRecipeIDs)
    if type(ids) ~= "table" then
        log("recipes: no list")
        return
    end
    local base = call(ui.GetBaseProfessionInfo)
    local prof = type(base) == "table" and Safe(base.professionName) or nil
    local s, key = state()
    local learned, changed, seen, lineMatch = 0, 0, {}, false
    for _, recipe in ipairs(ids) do
        local info = isID(recipe) and call(ui.GetRecipeInfo, recipe)
        local flag = type(info) == "table" and Safe(info.learned)
        local name = flag == true and Safe(info.name)
        if isText(name) then
            learned = learned + 1
            seen[recipe] = true
            local icon = Safe(info.icon)
            local line = Safe((select(2, call(ui.GetTradeSkillLineForRecipe, recipe))))
            lineMatch = lineMatch or (prof ~= nil and line == prof)
            -- The recipe's own line first: while a window switches, the base info may still name the old profession.
            local profession = isText(line) and line or prof
            local r = { name = name, icon = (isID(icon) or isText(icon)) and icon or nil,
                item = outputItem(ui, recipe), profession = isText(profession) and profession or nil }
            if not sameRecipe(s.recipes[recipe], r) then
                changed = changed + 1
                if not s.recipes[recipe] then
                    moveMade(s, key, recipe)
                end
                setRecipe(s, key, recipe, r)
            end
        elseif flag == false and s.recipes[recipe] then
            changed = changed + 1
            setRecipe(s, key, recipe, nil)
        end
    end
    -- A cached recipe of the open profession no longer in its learned list, once the list reads at all and is the
    -- open profession's (a listed learned recipe's line names it).
    if prof and learned > 0 and not lineMatch then
        log("recipes: sweep skipped, no line matches " .. prof)
    elseif prof and learned > 0 then
        for recipe, r in pairs(s.recipes) do
            if r.profession == prof and not seen[recipe] then
                changed = changed + 1
                setRecipe(s, key, recipe, nil)
            end
        end
    end
    log(("recipes %s: %d ids, %d learned, %d changed"):format(tostring(prof), #ids, learned, changed))
    if changed > 0 then
        notify()
    end
end

-- Crafts.TryCraft(entry) -> crafted: for a recipe entry out of combat, with its profession's window open and ready,
-- crafts one; false otherwise (the click then casts the profession to open its window).
function Crafts.TryCraft(entry)
    if type(entry) ~= "table" or entry.kind ~= "recipe" then
        return false
    end
    if call(_G.InCombatLockdown) == true then
        log("craft " .. entry.id .. ": in combat")
        return false
    end
    local ui = _G.C_TradeSkillUI
    if type(ui) ~= "table" or call(ui.IsTradeSkillReady) ~= true then
        log("craft " .. entry.id .. ": window not ready")
        return false
    end
    local base = call(ui.GetBaseProfessionInfo)
    local prof = type(base) == "table" and Safe(base.professionName) or nil
    if not isText(prof) or prof ~= entry.profession then
        log(("craft %s: open profession %s, wants %s"):format(entry.id, tostring(prof), tostring(entry.profession)))
        return false
    end
    local craftable = Safe((call(ui.GetCraftableCount, entry.recipe)))
    local ok, err = false, "nil-fn"
    if type(ui.CraftRecipe) == "function" then
        ok, err = pcall(ui.CraftRecipe, entry.recipe, 1)
    end
    log(("craft %s: CraftRecipe craftable=%s ok=%s err=%s"):format(entry.id, tostring(craftable), tostring(ok),
        ok and "-" or tostring(err)))
    return true
end

-- Whether the player knows the profession spell named name (the make action casts it by name).
local function knowsByName(name)
    local c = type(_G.C_Spell) == "table" and _G.C_Spell or {}
    if type(c.GetSpellInfo) == "function" then
        return type((call(c.GetSpellInfo, name))) == "table"
    end
    return call(_G.GetSpellInfo, name) ~= nil
end

-- Returns the name of the first spell in the player's spellbook, a spell the player surely knows; nil when unread.
local function firstBookSpell()
    local book = type(_G.C_SpellBook) == "table" and _G.C_SpellBook or {}
    local bank = type(_G.Enum) == "table" and type(_G.Enum.SpellBookSpellBank) == "table"
        and _G.Enum.SpellBookSpellBank.Player or 0
    local info = call(book.GetSpellBookItemInfo, 1, bank)
    local name = type(info) == "table" and Safe(info.name)
    if isText(name) then
        return name
    end
    name = call(_G.GetSpellBookItemName, 1, _G.BOOKTYPE_SPELL or "spell")
    return isText(name) and name or nil
end

-- Drops the cached recipes whose profession spell the player no longer knows, only once a lookup by name of a spell
-- the player surely knows succeeds (else a lookup that fails on this client would empty the cache).
local function pruneProfessions()
    local control = firstBookSpell()
    if not control or not knowsByName(control) then
        log("profession prune skipped")
        return
    end
    local s, key = state()
    local known = {}
    for recipe, r in pairs(s.recipes) do
        local prof = r.profession
        if prof and known[prof] == nil then
            known[prof] = knowsByName(prof)
        end
        if prof and not known[prof] then
            setRecipe(s, key, recipe, nil)
            log(("recipe %d dropped: %s unknown"):format(recipe, prof))
        end
    end
end

-- Crafts.OnSpellsChanged(): SPELLS_CHANGED, LEARNED_SPELL_IN_TAB and the like; a rank or profession learned or
-- unlearned may change the list.
function Crafts.OnSpellsChanged()
    pruneProfessions()
    notify()
end

-- Crafts.OnItemInfo(item): GET_ITEM_INFO_RECEIVED; an item read before it loaded is checked again.
function Crafts.OnItemInfo(item)
    item = Safe(item)
    if item and pending[item] then
        pending[item] = nil
        notify()
    end
end

-- An event on this module's own frame: the window flags (a window opening spoils the watched cast), the player's
-- casts and the profession window's recipe list.
function Crafts.OnEvent(event, ...)
    local window = WINDOWS[event]
    if window then
        if tracked[window[1]] then
            open[window[1]] = window[2]
        end
        if window[2] and watch then
            watch.spoiled = true
        end
    elseif SPOILS[event] then
        if watch then
            watch.spoiled = true
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spell = ...
        onCast(unit, spell)
    elseif event:find("^TRADE_SKILL_") then
        Crafts.ReadRecipes()
    end
end

-- PLAYER_LOGIN: registers this module's events on its own frame, once, skipping any the client rejects, and builds
-- the first list.
function Crafts.OnLogin()
    if events then
        return
    end
    events = CreateFrame("Frame", "TandemCraftsEvents")
    local rejected = {}
    if not ns.Store.RegisterUnitEvent(events, "UNIT_SPELLCAST_SUCCEEDED", "player") then
        rejected[#rejected + 1] = "UNIT_SPELLCAST_SUCCEEDED"
    end
    local ok = {}
    for _, event in ipairs(EVENTS) do
        ok[event] = ns.Store.RegisterEvent(events, event)
        if not ok[event] then
            rejected[#rejected + 1] = event
        end
    end
    for event, window in pairs(WINDOWS) do
        tracked[window[1]] = tracked[window[1]] ~= false and ok[event]
    end
    events:SetScript("OnEvent", function(_, event, ...)
        Crafts.OnEvent(event, ...)
    end)
    log("login rejected=" .. (#rejected > 0 and table.concat(rejected, ",") or "none"))
    pruneProfessions()
    notify()
end
