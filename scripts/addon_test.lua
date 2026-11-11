-- Loads the addon's .toc files in order under a stubbed WoW API and checks its locale handling.
local addonDir = arg[0]:gsub("[^/]*$", "") .. "../Tandem/"

local function tocFiles()
    local files = {}
    for raw in io.lines(addonDir .. "Tandem.toc") do
        local line = raw:match("^%s*(.-)%s*$")
        if line ~= "" and line:sub(1, 1) ~= "#" then
            files[#files + 1] = line:gsub("\\", "/")
        end
    end
    return files
end

local function exists(path)
    local f = io.open(path)
    if f then
        f:close()
    end
    return f ~= nil
end

-- Loads the addon as a client with the given locale would; returns its namespace,
-- the printed lines, a function that fires ADDON_LOADED, the global environment, a function that fires any event
-- and the event frame. opts.env sets globals before any file runs. opts.rejectEvents, a set of names, makes
-- registering any of them raise as a client that does not know the event would.
-- opts.toc replaces the toc's file list; its missing files are skipped, as WoW does. A missing file the real toc
-- lists fails the load. opts.widgets, a function(kind, name, parent, template), makes every other CreateFrame call
-- than the event frame's.
local function loadAddon(locale, opts)
    opts = opts or {}
    local printed = {}
    local handler
    local frame = { registered = {}, unregistered = {} }
    function frame.RegisterEvent(self, ev)
        if opts.rejectEvents and opts.rejectEvents[ev] then
            error(('Attempt to register unknown event "%s"'):format(ev))
        end
        self.registered[ev] = true
    end
    function frame.UnregisterEvent(self, ev)
        self.registered[ev] = nil
        self.unregistered[ev] = true
    end
    function frame.SetScript(_, _, fn)
        handler = fn
    end
    local env = setmetatable({
        CreateFrame = function(kind, name, parent, template)
            if opts.widgets and (kind ~= "Frame" or name or parent or template) then
                return opts.widgets(kind, name, parent, template)
            end
            return frame
        end,
        GetLocale = function()
            return locale
        end,
        print = function(msg)
            printed[#printed + 1] = msg
        end,
        SlashCmdList = {},
    }, { __index = _G })
    env._G = env
    for k, v in pairs(opts.env or {}) do
        env[k] = v
    end

    local ns = {}
    for _, file in ipairs(opts.toc or tocFiles()) do
        if not opts.toc or exists(addonDir .. file) then
            local chunk = assert(loadfile(addonDir .. file, "t", env))
            if setfenv then
                setfenv(chunk, env)
            end
            chunk("Tandem", ns)
        end
    end

    local function fire(event, ...)
        handler(frame, event, ...)
    end
    local function fireLoaded()
        fire("ADDON_LOADED", "Tandem")
    end
    return ns, printed, fireLoaded, env, fire, frame
end

local failures = 0
local function check(name, got, want)
    if got == want then
        print("ok   " .. name)
    else
        failures = failures + 1
        print(("FAIL %s: got %q, want %q"):format(name, tostring(got), tostring(want)))
    end
end

for _, case in ipairs({
    { locale = "enUS", line = "Tandem loaded" },
    { locale = "zhTW", line = "Tandem 已載入" },
    { locale = "deDE", line = "Tandem loaded" },
}) do
    local _, printed, fireLoaded = loadAddon(case.locale)
    fireLoaded()
    check(case.locale .. " load line", printed[1], case.line)
end

local ns = loadAddon("zhTW")
check("zhTW falls back to English for a missing key", ns.L["Not translated yet"], "Not translated yet")

do
    local toc = tocFiles()
    table.insert(toc, 1, "Data/Missing.lua")
    local _, printed, fireLoaded = loadAddon("enUS", { toc = toc })
    fireLoaded()
    check("a missing toc file does not break the load", printed[1], "Tandem loaded")
end

-- Store: TandemDB validation and migration.

-- Loads the addon with TandemDB set to db, fires ADDON_LOADED; returns ns, printed lines, env, fire, frame.
local function loadWithDB(db, locale, opts)
    local addon, printed, fireLoaded, env, fire, frame = loadAddon(locale or "enUS", opts)
    env.TandemDB = db
    fireLoaded()
    return addon, printed, env, fire, frame
end

-- Returns v as text with table keys sorted, to compare saved data before and after.
local function dump(v)
    if type(v) ~= "table" then
        return type(v) == "string" and ("%q"):format(v) or tostring(v)
    end
    local keys = {}
    for k in pairs(v) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    local out = {}
    for _, k in ipairs(keys) do
        out[#out + 1] = dump(k) .. "=" .. dump(v[k])
    end
    return "{" .. table.concat(out, ",") .. "}"
end

-- Returns true for a fresh schema-7 db: no keys but schemaVersion and empty weights, trainers and layout.
local function isCurrent(db)
    if type(db) ~= "table" or db.schemaVersion ~= 7 or type(db.weights) ~= "table" or next(db.weights) ~= nil
        or type(db.trainers) ~= "table" or next(db.trainers) ~= nil or type(db.layout) ~= "table"
        or next(db.layout) ~= nil then
        return false
    end
    local keys = 0
    for _ in pairs(db) do
        keys = keys + 1
    end
    return keys == 4
end

do
    local addon, printed, env = loadWithDB(nil)
    check("nil db becomes a fresh v7 table", isCurrent(env.TandemDB), true)
    check("nil db prints only the load line", #printed, 1)
    check("Store.db is TandemDB", addon.Store.db, env.TandemDB)
    check("Store.SCHEMA is 7", addon.Store.SCHEMA, 7)
end

do
    local _, printed, env = loadWithDB("garbage")
    check("garbage db becomes a fresh v7 table", isCurrent(env.TandemDB), true)
    check("garbage db prints a reset line", printed[2], "Tandem: saved data was unreadable and has been reset")
end

do
    local _, printed = loadWithDB("garbage", "zhTW")
    check("zhTW reset line", printed[2], "Tandem：存檔資料無法讀取，已重設")
end

-- Schema 6 (stage 11, D4), now 7: a v5 db keeps its weights and trainers; every other key is dropped and counted.
do
    local weights = { ["Thrall-Realm"] = { spec = 2, overrides = { [2] = { str = 2.5 } } } }
    local trainers = { MAGE = { [116] = { level = 4, rank = 1 }, [1459] = { level = 1 } } }
    local item = { 10, 5, 2, "INVTYPE_HEAD", 4, 1 }
    local addon, printed, env = loadWithDB({
        schemaVersion = 5,
        items = { [25] = item },
        stats = { [25] = { str = 5 } },
        statsVersion = 2,
        scan = { cursor = 500, nonEquippable = 7, blocks = { [0] = 3 }, lastRun = { hits = 3 } },
        npcs = { [100] = "Hogger" },
        quests = { [176] = "Wanted: Hogger" },
        loot = { ["25:c:100:1429"] = { item = 25, kind = "c", id = 100, map = 1429, count = 4, coords = {} } },
        kills = { [100] = 9 },
        corpses = { [100] = 5 },
        ui = { window = { point = "TOP", relativePoint = "TOP", x = 1, y = 2 }, minimap = 45, minimapHidden = true },
        weights = weights,
        trainers = trainers,
    })
    local db = env.TandemDB
    check("v5 db migrates to v7", db.schemaVersion, 7)
    check("v5 db keeps its weights", dump(db.weights), dump(weights))
    check("v5 db keeps its trainers", dump(db.trainers), dump(trainers))
    check("v5 db keeps nothing else", dump(db), dump({ schemaVersion = 7, weights = weights, trainers = trainers,
        layout = {} }))
    check("v5 db trainers are read back", addon.Store.TrainerSpells("MAGE")[116].level, 4)
    check("v5 db is writable", addon.Store.readOnly, false)
    check("v5 db prints the upgrade line", printed[2], "Tandem: saved data upgraded from schema 5 to 7")
    -- items, stats, statsVersion, scan, npcs, quests, loot, kills, corpses, ui
    check("v5 db counts each dropped key", printed[3], "Tandem: dropped 10 invalid or unused saved entries")
    check("v5 db prints nothing else", #printed, 3)
end

do
    local _, printed = loadWithDB({ schemaVersion = 5, items = {}, weights = {} }, "zhTW")
    check("zhTW upgrade line", printed[2], "Tandem：存檔資料已從結構版本 5 升級到 7")
    check("zhTW dropped line", printed[3], "Tandem：已捨棄 1 筆無效或不再使用的存檔資料")
end

do
    local _, printed, env = loadWithDB({ unknownTop = true, weights = { ["Tom-Realm"] = { spec = 1 } } })
    check("old db without a version is migrated to v7", env.TandemDB.schemaVersion, 7)
    check("old db without a version keeps its weights", env.TandemDB.weights["Tom-Realm"].spec, 1)
    check("old db drops unknown top-level keys", env.TandemDB.unknownTop, nil)
    check("old db without a version prints no upgrade line", printed[2],
        "Tandem: dropped 1 invalid or unused saved entries")
end

for _, bad in ipairs({ 1.5, 0 / 0, -1, -math.huge }) do
    local _, printed, env = loadWithDB({ schemaVersion = bad })
    check("damaged version " .. tostring(bad) .. " is migrated", env.TandemDB.schemaVersion, 7)
    check("damaged version " .. tostring(bad) .. " prints no upgrade line", #printed, 1)
end

do
    local _, printed, env = loadWithDB({ schemaVersion = 7, weights = { ["Tom-Realm"] = { spec = 3 } },
                                         trainers = { WARRIOR = { [100] = { level = 4 } } } })
    check("v7 db keeps weights", env.TandemDB.weights["Tom-Realm"].spec, 3)
    check("v7 db keeps trainers", env.TandemDB.trainers.WARRIOR[100].level, 4)
    check("valid v7 db prints only the load line", #printed, 1)
end

-- Store: weights (stage 7, decisions 6-8).
do
    local _, printed, env = loadWithDB({
        schemaVersion = 7,
        weights = {
            ["Thrall-Realm"] = { spec = 2, overrides = { [2] = { str = 2.5, sta = 0 }, [1] = { int = 1 } } },
            ["Jaina-Realm"] = { spec = 4, overrides = { [1] = { int = 1, fire = 2, sp = "x" }, [5] = { str = 1 },
                                                        [2] = "bad" } },
            ["Arthas-Realm"] = { overrides = "bad" },
            ["Uther-Realm"] = "bad",
            [""] = { spec = 1 },
            [7] = { spec = 1 },
        },
    })
    local db = env.TandemDB
    local w = db.weights["Thrall-Realm"]
    check("weights: a valid entry keeps its spec", w and w.spec, 2)
    check("weights: a valid entry keeps its overrides", w and w.overrides[2].str .. " " .. w.overrides[2].sta
        .. " " .. w.overrides[1].int, "2.5 0 1")
    local j = db.weights["Jaina-Realm"]
    check("weights: spec 4 is dropped, the entry kept", j and tostring(j.spec), "nil")
    check("weights: a valid override key survives", j and j.overrides[1].int, 1)
    check("weights: bad override keys are dropped", j and tostring(j.overrides[1].fire) .. tostring(j.overrides[1].sp),
        "nilnil")
    check("weights: an override for spec 5 is dropped", j and j.overrides[5], nil)
    check("weights: a non-table override is dropped", j and j.overrides[2], nil)
    local a = db.weights["Arthas-Realm"]
    check("weights: bad overrides become empty", a and type(a.overrides) == "table" and next(a.overrides) == nil,
        true)
    check("weights: a non-table entry is dropped", db.weights["Uther-Realm"], nil)
    check("weights: an empty name is dropped", db.weights[""], nil)
    check("weights: a number name is dropped", db.weights[7], nil)
    -- Jaina spec, fire, sp, [5], [2]; Arthas overrides; Uther, "", 7
    check("weights: invalid entries are counted", printed[2], "Tandem: dropped 9 invalid or unused saved entries")
end

do
    local addon, printed, env = loadWithDB({ schemaVersion = 7, weights = "bad" })
    check("weights: a non-table weights becomes empty", type(env.TandemDB.weights), "table")
    check("weights: a bad weights counts as dropped", printed[2], "Tandem: dropped 1 invalid or unused saved entries")
    check("STAT_KEYS lists 21 keys", #addon.Store.STAT_KEYS, 21)
end

-- Store: class trainer spells (stage 8, decision 4).
do
    local addon, printed, env = loadWithDB({
        schemaVersion = 7,
        trainers = {
            MAGE = { [116] = { level = 4, rank = 1 }, [205] = { level = 8, rank = 2, extra = true },
                     [1459] = { level = 1 }, [0] = { level = 1 }, [10] = { level = 0 }, [11] = { level = 2.5 },
                     [12] = { level = 2, rank = 0 }, [13] = { level = 2, rank = "1" }, [14] = "bad",
                     ["15"] = { level = 2 } },
            WARRIOR = {},
            mage = { [116] = { level = 4 } },
            [""] = { [116] = { level = 4 } },
            [7] = { [116] = { level = 4 } },
            PRIEST = "bad",
        },
    })
    local db, Store = env.TandemDB, addon.Store
    local mage = db.trainers.MAGE
    check("trainers: a valid entry is kept", mage[116].level .. " " .. mage[116].rank, "4 1")
    check("trainers: extra entry fields are stripped", mage[205].level .. " " .. mage[205].rank .. " "
        .. tostring(mage[205].extra), "8 2 nil")
    check("trainers: a rankless entry is kept", mage[1459].level .. " " .. tostring(mage[1459].rank), "1 nil")
    check("trainers: bad spellIDs and entries are dropped alone",
        tostring(mage[0]) .. tostring(mage[10]) .. tostring(mage[11]) .. tostring(mage[12]) .. tostring(mage[13])
        .. tostring(mage[14]) .. tostring(mage["15"]), "nilnilnilnilnilnilnil")
    check("trainers: an empty class is kept", type(db.trainers.WARRIOR) == "table", true)
    check("trainers: bad class keys are dropped", tostring(db.trainers.mage) .. tostring(db.trainers[""])
        .. tostring(db.trainers[7]) .. tostring(db.trainers.PRIEST), "nilnilnilnil")
    -- MAGE 0, 10, 11, 12, 13, 14, "15"; mage, "", 7, PRIEST
    check("trainers: invalid entries are counted", printed[2], "Tandem: dropped 11 invalid or unused saved entries")

    check("TrainerSpells reads a class", Store.TrainerSpells("MAGE")[116].level, 4)
    check("TrainerSpells is nil for an unseen class", Store.TrainerSpells("ROGUE"), nil)
    check("SetTrainerSpell records a spell", Store.SetTrainerSpell("ROGUE", 1752, 1, 1), true)
    check("SetTrainerSpell writes TandemDB", db.trainers.ROGUE[1752].level .. " " .. db.trainers.ROGUE[1752].rank,
        "1 1")
    check("SetTrainerSpell skips an unchanged spell", Store.SetTrainerSpell("ROGUE", 1752, 1, 1), false)
    check("SetTrainerSpell records a rankless spell", Store.SetTrainerSpell("ROGUE", 2983, 8), true)
    check("SetTrainerSpell rankless has no rank", db.trainers.ROGUE[2983].rank, nil)
    check("SetTrainerSpell keeps the lower level on a higher one", Store.SetTrainerSpell("MAGE", 116, 6, 1), false)
    check("SetTrainerSpell lower level unchanged", mage[116].level, 4)
    check("SetTrainerSpell takes a lower level", Store.SetTrainerSpell("MAGE", 116, 3, 1), true)
    check("SetTrainerSpell lower level written", mage[116].level, 3)
    check("SetTrainerSpell keeps the rank when given none", Store.SetTrainerSpell("MAGE", 116, 3), false)
    check("SetTrainerSpell adds a rank to a rankless spell", Store.SetTrainerSpell("MAGE", 1459, 1, 1), true)
    check("SetTrainerSpell rank added", mage[1459].rank, 1)
    for name, args in pairs({
        ["a lowercase class"] = { "mage", 1, 1 }, ["an empty class"] = { "", 1, 1 }, ["a number class"] = { 7, 1, 1 },
        ["spell 0"] = { "MAGE", 0, 1 }, ["a fractional spell"] = { "MAGE", 1.5, 1 },
        ["a string spell"] = { "MAGE", "1", 1 }, ["level 0"] = { "MAGE", 1, 0 }, ["nil level"] = { "MAGE", 1 },
        ["a NaN level"] = { "MAGE", 1, 0 / 0 }, ["rank 0"] = { "MAGE", 1, 1, 0 },
        ["a fractional rank"] = { "MAGE", 1, 1, 1.5 }, ["a string rank"] = { "MAGE", 1, 1, "1" },
    }) do
        check("SetTrainerSpell rejects " .. name, Store.SetTrainerSpell(args[1], args[2], args[3], args[4]), false)
    end
    check("SetTrainerSpell rejections write nothing", mage[1], nil)

    local newer = loadWithDB({ schemaVersion = 8, trainers = { MAGE = { [116] = { level = 4 } } } }).Store
    check("newer db blocks SetTrainerSpell", newer.SetTrainerSpell("MAGE", 1, 1, 1), false)
    check("newer db reads no trainer spells", newer.TrainerSpells("MAGE"), nil)
end

do
    local newer = { schemaVersion = 8, items = "new format", weights = "new format" }
    local addon, printed, env = loadWithDB(newer)
    check("newer db is left untouched", env.TandemDB, newer)
    check("newer db keeps its fields", env.TandemDB.items .. " " .. env.TandemDB.weights, "new format new format")
    check("newer db prints a warning", printed[2],
        "Tandem: saved data uses newer schema 8; recording is off until the addon is updated")
    check("newer db prints nothing else", #printed, 2)
    check("newer db is read-only", addon.Store.readOnly, true)
end

do
    local addon, _, env = loadWithDB(nil)
    check("Safe passes values without issecretvalue", addon.Store.Safe(5), 5)
    env.issecretvalue = function(v)
        return v == "secret"
    end
    check("Safe hides a secret value", addon.Store.Safe("secret"), nil)
    check("Safe passes a plain value", addon.Store.Safe("plain"), "plain")
end

-- Commands: /tandem parsing and output.

-- Returns the lines printed after the first from.
local function linesSince(printed, from)
    local out = {}
    for i = from + 1, #printed do
        out[#out + 1] = printed[i]
    end
    return out
end

-- Runs msg through /tandem; returns the lines it printed.
local function run(addon, printed, msg)
    local from = #printed
    addon.Commands.Run(msg)
    return linesSince(printed, from)
end

do
    local addon, printed, env = loadWithDB(nil)
    check("SLASH_TANDEM1 is /tandem", env.SLASH_TANDEM1, "/tandem")
    check("SlashCmdList.TANDEM is Run", env.SlashCmdList.TANDEM, addon.Commands.Run)

    local help = run(addon, printed, "")
    check("empty input prints usage", help[1], "Tandem commands:")
    check("help prints usage", run(addon, printed, "help")[1], "Tandem commands:")
    check("unknown subcommand prints usage", run(addon, printed, "dance")[1], "Tandem commands:")
    check("usage lists check", help[2], "  /tandem check - list the client APIs each feature needs")
    check("usage lists weights", help[3], "  /tandem weights - show the stat weights of your talent tree")
    check("usage lists weights spec", help[4],
        "  /tandem weights spec <1|2|3|auto> - pick the talent tree, or follow your talents")
    check("usage lists weights set", help[5],
        "  /tandem weights set <stat> <number> - set your own weight for a stat (0 ignores it)")
    check("usage lists weights reset", help[6], "  /tandem weights reset - drop your own weights for the active tree")
    check("usage lists layout", help[7],
        "  /tandem layout [on|off] - arrange bars, unit frames and chat for Tandem, or restore your layout")
    check("usage lists minimap", help[8], "  /tandem minimap [on|off] - show or hide the minimap button")
    check("usage lists debug", help[9],
        "  /tandem debug [on|off|snap] - record layout traces for the developer; /reload saves them")
    check("usage line count", #help, 9)
    for _, sub in ipairs({ "scan", "count", "gear", "rank", "browse", "export", "map clear", "forget 1 2" }) do
        check(("removed %q prints usage"):format(sub), run(addon, printed, sub)[1], "Tandem commands:")
    end
end

do
    local _, printed, _, fire = loadWithDB(nil)
    local before = #printed
    fire("ADDON_LOADED", "OtherAddon")
    check("another addon's ADDON_LOADED is ignored", #printed, before)
end

-- StatSearch.ReadStats (stage 7, unit 2): tooltip lines parsed into stat keys.

-- Returns { addon, env } for a fresh load in locale.
local function loadStats(locale)
    local addon, _, env = loadWithDB(nil, locale)
    return { addon = addon, env = env }
end

-- Gives a loadStats ctx the tooltip API over tips ({[id] = {left texts}}; an id without lines is not loaded).
local function withTips(ctx, tips)
    ctx.env.C_TooltipInfo = { GetItemByID = function(id)
        if not tips[id] then
            return nil
        end
        local lines = {}
        for i, text in ipairs(tips[id]) do
            lines[i] = { leftText = text }
        end
        return { lines = lines }
    end }
    return ctx
end

-- Returns stats as "key=n,..." sorted by key, or "nil".
local function statsText(stats)
    if not stats then
        return "nil"
    end
    local parts = {}
    for key, n in pairs(stats) do
        parts[#parts + 1] = key .. "=" .. n
    end
    table.sort(parts)
    return table.concat(parts, ",")
end

do
    local ctx = withTips(loadStats(), {
        [1] = { "Robe of Tests", "Binds when equipped", "Chest", "Cloth", "|cffffffff65 Armor|r", "+10 Stamina",
            "+12 Intellect", "+8 Spirit", "+3 Fire Resistance",
            "Equip: Increases damage and healing done by magical spells and effects by up to 23.",
            "Equip: Increases healing done by spells and effects by up to 44.",
            "Equip: Improves your chance to hit with spells by 1%.",
            "Equip: Improves your chance to get a critical strike with spells by 2%.",
            "Equip: Restores 6 mana per 5 sec.", "Equip: Increases damage done by Fire spells and effects by up to 9.",
            "(2) Set: Restores 4 mana per 5 sec." },
        [2] = { "Blade of Tests", "Main Hand", "Sword", "41 - 77 Damage", "Speed 2.50", "(23.6 damage per second)",
            "+5 Strength", "+7 Agility", "Equip: +20 Attack Power.", "Equip: +12 ranged Attack Power.",
            "Equip: Improves your chance to hit by 1%.", "Equip: Improves your chance to get a critical strike by 1%.",
            "Equip: +10 Attack Power when fighting Undead." },
        [3] = { "Shield of Tests", "Off Hand", "Shield", "1500 Armor", "26 Block", "Equip: Increased Defense +7.",
            "Equip: Increases your chance to dodge an attack by 1%.",
            "Equip: Increases your chance to parry an attack by 2%.",
            "Equip: Increases your chance to block attacks with a shield by 3%.",
            "Equip: Increases the block value of your shield by 14." },
        [4] = { "Plain Ring", "Finger" },
    })
    local Read = ctx.addon.StatSearch.ReadStats
    check("stats enUS: caster lines", statsText(Read(1)),
        "armor=65,heal=44,int=12,mp5=6,sp=23,spellcrit=2,spellhit=1,spi=8,sta=10")
    check("stats enUS: weapon lines", statsText(Read(2)), "agi=7,ap=20,crit=1,dps=23.6,hit=1,rap=12,str=5")
    check("stats enUS: tank lines", statsText(Read(3)), "armor=1500,block=3,blockvalue=40,def=7,dodge=1,parry=2")
    check("stats enUS: no stat lines is an empty table", statsText(Read(4)), "")
    check("stats enUS: an unloaded tooltip is nil", Read(5), nil)
end

do
    local ctx = withTips(loadStats("zhTW"), {
        [1] = { "測試長袍", "胸部", "布甲", "65點護甲", "+10 耐力", "+12 智力", "+8 精神",
            "裝備：使所有法術和魔法效果所造成的傷害和治療效果提高最多23點。",
            "裝備：使法術和魔法效果的治療效果提高最多44點。",
            "裝備：使你的法術擊中敵人的機率提高1%。",
            "裝備：使你的法術造成致命一擊的機率提高1%。",
            "裝備：每5秒恢復6點法力值。" },
        [2] = { "測試之刃", "主手", "劍", "(每秒傷害23.6)", "+5 力量", "+7 敏捷", "裝備：+20 攻擊強度。",
            "裝備：+12遠程攻擊強度。", "裝備：使你擊中目標的機率提高1%。", "裝備：使你造成致命一擊的機率提高2%。" },
        [3] = { "測試之盾", "副手", "盾牌", "1500點護甲", "26點格擋", "裝備：防禦技能提高7點。",
            "裝備：使你躲閃攻擊的機率提高1%。", "裝備：使你招架攻擊的機率提高2%。",
            "裝備：使你用盾牌格擋攻擊的機率提高3%。", "裝備：使你的盾牌格擋值提高14點。" },
    })
    local Read = ctx.addon.StatSearch.ReadStats
    check("stats zhTW: caster lines", statsText(Read(1)),
        "armor=65,heal=44,int=12,mp5=6,sp=23,spellcrit=1,spellhit=1,spi=8,sta=10")
    check("stats zhTW: weapon lines", statsText(Read(2)), "agi=7,ap=20,crit=2,dps=23.6,hit=1,rap=12,str=5")
    check("stats zhTW: tank lines", statsText(Read(3)), "armor=1500,block=3,blockvalue=40,def=7,dodge=1,parry=2")
end

do
    local ctx = withTips(loadStats("enGB"), { [1] = { "Helm", "+4 Stamina" } })
    check("enGB: English patterns", statsText(ctx.addon.StatSearch.ReadStats(1)), "sta=4")
end

-- Trainer: class trainer services recorded with stubbed trainer and tooltip APIs (stage 8, unit 2).

-- Loads the addon with a trainer window of ctx.services ({ name, rank, kind, level, id }); the player is a mage out of
-- combat at a class trainer. ctx.tradeskill makes it a tradeskill trainer.
local function loadTrainer()
    local addon, printed, env, fire, frame = loadWithDB({ schemaVersion = 6 })
    local ctx = { addon = addon, printed = printed, env = env, fire = fire, frame = frame, combat = false,
                  tradeskill = false, services = {
                      { "Frost", nil, "header" },
                      { "Frostbolt", "Rank 2", "available", 8, 205 },
                      { "Ice Armor", "", "unavailable", 30, 7302 },
                  } }
    env.InCombatLockdown = function()
        return ctx.combat
    end
    env.UnitClass = function(unit)
        if unit == "player" then
            return "Mage", "MAGE", 8
        end
    end
    env.IsTradeskillTrainer = function()
        return ctx.tradeskill
    end
    env.GetNumTrainerServices = function()
        return #ctx.services
    end
    env.GetTrainerServiceInfo = function(i)
        local s = ctx.services[i]
        return s[1], s[2], s[3]
    end
    env.GetTrainerServiceLevelReq = function(i)
        return ctx.services[i][4]
    end
    env.C_TooltipInfo = {
        GetTrainerService = function(i)
            local s = ctx.services[i]
            if s[3] ~= "header" then
                return { id = s[5], lines = {} }
            end
        end,
    }
    function ctx.spells()
        local out = {}
        for id, e in pairs(env.TandemDB.trainers.MAGE or {}) do
            out[#out + 1] = ("%s=%d/%s"):format(tostring(id), e.level, tostring(e.rank))
        end
        table.sort(out)
        return table.concat(out, " ")
    end
    return ctx
end

do
    local ctx = loadTrainer()
    for _, ev in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE" }) do
        check("trainer: registers " .. ev, ctx.frame.registered[ev], true)
    end
    ctx.fire("TRAINER_SHOW")
    check("trainer: records ranked and rankless services, skips the header", ctx.spells(), "205=8/2 7302=30/nil")
    ctx.fire("TRAINER_UPDATE")
    check("trainer: TRAINER_UPDATE records nothing twice", ctx.spells(), "205=8/2 7302=30/nil")
    ctx.services[4] = { "Fire Ward", "Rank 1", "used", 20, "543" }
    ctx.services[5] = { "Frostbolt", "Rank 3", "unavailable", 14, 837 }
    ctx.services[6] = { "Blink", nil, "available", 20 }
    ctx.fire("TRAINER_UPDATE")
    check("trainer: TRAINER_UPDATE records a new service, skips missing and non-numeric ids", ctx.spells(),
        "205=8/2 7302=30/nil 837=14/3")
end

for name, setup in pairs({
    ["in combat"] = function(ctx)
        ctx.combat = true
    end,
    ["while read-only"] = function(ctx)
        ctx.addon.Store.readOnly = true
    end,
    ["at a tradeskill trainer"] = function(ctx)
        ctx.tradeskill = true
    end,
    ["without GetNumTrainerServices"] = function(ctx)
        ctx.env.GetNumTrainerServices = nil
    end,
    ["without GetTrainerServiceInfo"] = function(ctx)
        ctx.env.GetTrainerServiceInfo = nil
    end,
    ["without GetTrainerServiceLevelReq"] = function(ctx)
        ctx.env.GetTrainerServiceLevelReq = nil
    end,
    ["without C_TooltipInfo.GetTrainerService"] = function(ctx)
        ctx.env.C_TooltipInfo = {}
    end,
    ["without UnitClass"] = function(ctx)
        ctx.env.UnitClass = nil
    end,
}) do
    local ctx = loadTrainer()
    setup(ctx)
    ctx.fire("TRAINER_SHOW")
    ctx.fire("TRAINER_UPDATE")
    check("trainer: nothing recorded " .. name, ctx.env.TandemDB.trainers.MAGE, nil)
end

do
    local ctx = loadTrainer()
    ctx.env.IsTradeskillTrainer = nil
    ctx.env.issecretvalue = function(v)
        return v == 205
    end
    ctx.fire("TRAINER_SHOW")
    check("trainer: a secret spell id is skipped", ctx.spells(), "7302=30/nil")
end

-- Items: where an item goes and whether a class can use it (stage 11, D1).

-- { ilvl, reqLevel, quality, equipLoc, classID, subclassID }
local GEAR = {
    [1] = { 45, 40, 3, "INVTYPE_CHEST", 4, 4 },        -- plate chest
    [2] = { 30, 25, 2, "INVTYPE_ROBE", 4, 3 },         -- mail robe
    [3] = { 30, 25, 3, "INVTYPE_CHEST", 4, 2 },        -- leather chest
    [4] = { 30, 25, 3, "INVTYPE_ROBE", 4, 1 },         -- cloth robe
    [5] = { 20, 15, 2, "INVTYPE_SHIELD", 4, 6 },
    [6] = { 20, 15, 2, "INVTYPE_RELIC", 4, 7 },        -- libram
    [7] = { 25, 20, 2, "INVTYPE_WEAPON", 2, 7 },       -- one-hand sword
    [8] = { 22, 18, 2, "INVTYPE_RANGEDRIGHT", 2, 19 }, -- wand
    [9] = { 1, 1, 1, "INVTYPE_BODY", 4, 0 },           -- shirt
    [10] = { 5, 1, 1, "INVTYPE_2HWEAPON", 2, 20 },     -- fishing pole
    [11] = { 99, 1, 5, "INVTYPE_CHEST", 4, 1 },        -- GM robe, no source
    [12] = { 20, 10, 2, "INVTYPE_CHEST", 4, 3 },       -- mail chest
    [13] = { 50, 38, 3, "INVTYPE_LEGS", 4, 4 },        -- plate legs, low reqLevel
    [14] = { 24, 15, 2, "INVTYPE_WEAPONOFFHAND", 2, 7 }, -- off-hand sword
    [15] = { 30, 20, 2, "INVTYPE_2HWEAPON", 2, 1 },    -- two-hand axe, no source
}

do
    local Items = loadWithDB(nil).Items
    local function place(equipLoc, class, level)
        local p = Items.Place({ 10, 1, 1, equipLoc, 4, 1 }, class, level)
        return tostring(p.slot) .. " " .. tostring(p.offhand)
    end
    check("items: ROBE goes in chest", place("INVTYPE_ROBE", "MAGE", 1), "chest nil")
    check("items: CLOAK goes in back", place("INVTYPE_CLOAK", "MAGE", 1), "back nil")
    check("items: rogue dual-wields one-hand weapons at 10", place("INVTYPE_WEAPON", "ROGUE", 10), "mainhand true")
    check("items: rogue below 10 does not dual-wield", place("INVTYPE_WEAPON", "ROGUE", 9), "mainhand nil")
    check("items: warrior dual-wields at 20", place("INVTYPE_WEAPON", "WARRIOR", 20), "mainhand true")
    check("items: warrior below 20 does not dual-wield", place("INVTYPE_WEAPON", "WARRIOR", 19), "mainhand nil")
    check("items: mage never dual-wields", place("INVTYPE_WEAPON", "MAGE", 60), "mainhand nil")
    check("items: main-hand weapon", place("INVTYPE_WEAPONMAINHAND", "ROGUE", 60), "mainhand nil")
    check("items: shield is off hand", place("INVTYPE_SHIELD", "WARRIOR", 60), "offhand nil")
    check("items: holdable is off hand", place("INVTYPE_HOLDABLE", "MAGE", 60), "offhand nil")
    check("items: two-hander", place("INVTYPE_2HWEAPON", "WARRIOR", 60), "twohand nil")
    check("items: relic is ranged", place("INVTYPE_RELIC", "PALADIN", 60), "ranged nil")
    check("items: thrown is ranged", place("INVTYPE_THROWN", "ROGUE", 60), "ranged nil")
    check("items: shirt has no slot", place("INVTYPE_BODY", "MAGE", 60), "nil nil")
    check("items: tabard has no slot", place("INVTYPE_TABARD", "MAGE", 60), "nil nil")
    check("items: unknown equipLoc has no slot", place("INVTYPE_WHATEVER", "MAGE", 60), "nil nil")
    local p = Items.Place(GEAR[1], "WARRIOR", 30)
    check("items: Place of an item", p.slot .. " " .. tostring(p.usable) .. " " .. p.reason .. " " .. p.needLevel,
        "chest false level 40")
    check("items: Place without an id has no score", p.score, nil)

    local function usable(id, class, level)
        local ok, reason, need = Items.Usable(GEAR[id], class, level)
        return tostring(ok) .. " " .. tostring(reason) .. " " .. tostring(need)
    end
    check("items: warrior wears plate at 40", usable(1, "WARRIOR", 40), "true nil nil")
    check("items: warrior needs 40 for plate", usable(1, "WARRIOR", 39), "false level 40")
    check("items: plate needLevel is the proficiency level", usable(13, "WARRIOR", 30), "false level 40")
    check("items: paladin wears plate at 40", usable(1, "PALADIN", 40), "true nil nil")
    check("items: hunter needs 40 for mail", usable(12, "HUNTER", 39), "false level 40")
    check("items: hunter wears mail at 40", usable(12, "HUNTER", 40), "true nil nil")
    check("items: shaman needs 40 for mail", usable(12, "SHAMAN", 39), "false level 40")
    check("items: shaman wears mail at 40", usable(12, "SHAMAN", 40), "true nil nil")
    check("items: warrior wears mail before 40", usable(12, "WARRIOR", 10), "true nil nil")
    check("items: mage cannot wear plate", usable(1, "MAGE", 60), "false proficiency nil")
    check("items: rogue cannot wear mail", usable(12, "ROGUE", 60), "false proficiency nil")
    check("items: reqLevel blocks a usable type", usable(3, "ROGUE", 24), "false level 25")
    check("items: paladin uses a shield", usable(5, "PALADIN", 20), "true nil nil")
    check("items: mage cannot use a shield", usable(5, "MAGE", 60), "false proficiency nil")
    check("items: mage cannot use an off-hand weapon", usable(14, "MAGE", 60), "false proficiency nil")
    check("items: off-hand weapon needs dual wield", usable(14, "WARRIOR", 19), "false level 20")
    check("items: warrior uses an off-hand weapon at 20", usable(14, "WARRIOR", 20), "true nil nil")
    check("items: shaman cannot use a two-hand axe", usable(15, "SHAMAN", 60), "false proficiency nil")
    check("items: shaman cannot use a two-hand mace",
        select(2, Items.Usable({ 30, 20, 2, "INVTYPE_2HWEAPON", 2, 5 }, "SHAMAN", 60)), "proficiency")
    check("items: warrior uses a two-hand axe", usable(15, "WARRIOR", 60), "true nil nil")
    check("items: paladin uses a libram", usable(6, "PALADIN", 20), "true nil nil")
    check("items: druid cannot use a libram", usable(6, "DRUID", 60), "false proficiency nil")
    check("items: priest uses a wand", usable(8, "PRIEST", 20), "true nil nil")
    check("items: warrior cannot use a wand", usable(8, "WARRIOR", 60), "false proficiency nil")
    check("items: fishing pole is never usable", usable(10, "WARRIOR", 60), "false proficiency nil")
    check("items: shirt has no slot to use", usable(9, "WARRIOR", 60), "false slot nil")
    check("items: unknown class wears cloth", usable(4, "MONK", 60), "true nil nil")
    check("items: unknown class cannot wear leather", usable(3, "MONK", 60), "false proficiency nil")
end

-- Commands: combat refusal and an unknown player.

-- A secret value as the client hands it out: comparing, concatenating or indexing it raises. Lua never calls __eq
-- against nil, so `secret == nil` cannot be trapped here; code must ask issecretvalue first.
local SECRET_MT = {}
for _, event in ipairs({ "__eq", "__lt", "__le", "__concat", "__index", "__len", "__call" }) do
    SECRET_MT[event] = function()
        error("secret value used")
    end
end
local function secret()
    return setmetatable({}, SECRET_MT)
end

-- Builds the link Commands makes for an uncached item.
local function built(id, hex, name)
    return ("|cff%s|Hitem:%d::::::::::::::|h[%s]|h|r"):format(hex, id, name or ("item #" .. id))
end

-- Loads the addon with a fresh TandemDB and a stubbed player: ctx.class/className/level for
-- UnitClass/UnitLevel, ctx.equipped[invSlot] = link, ctx.cache[id] = { name, link, quality, ilvl, reqLevel } for
-- C_Item.GetItemInfo, ctx.combat, ctx.secret values hidden by issecretvalue. C_Item.IsItemDataCachedByID is true for
-- ids in ctx.cache. opts.env adds globals, opts.widgets goes to loadAddon. Returns ctx with addon, printed, env, fire,
-- frame, run(msg).
local function loadGear(locale, opts)
    local ctx = { class = "WARRIOR", className = "Warrior", level = 40, equipped = {}, cache = {}, combat = false,
                  requested = {} }
    local env = {
        UnitClass = function(unit)
            assert(unit == "player")
            return ctx.className, ctx.class
        end,
        UnitLevel = function()
            return ctx.level
        end,
        InCombatLockdown = function()
            return ctx.combat
        end,
        GetInventoryItemLink = function(unit, slot)
            assert(unit == "player")
            return ctx.equipped[slot]
        end,
        C_Item = {
            IsItemDataCachedByID = function(id)
                return ctx.cache[id] ~= nil
            end,
            GetItemInfo = function(id)
                local c = ctx.cache[id]
                if c then
                    return c[1], c[2], c[3], c[4], c[5]
                end
            end,
            RequestLoadItemDataByID = function(id)
                ctx.requested[id] = true
            end,
            GetItemInfoInstant = function(id)
                return id
            end,
        },
        issecretvalue = function(v)
            return getmetatable(v) == SECRET_MT
        end,
    }
    for k, v in pairs(opts and opts.env or {}) do
        env[k] = v
    end
    local loadOpts = { env = env, widgets = opts and opts.widgets }
    ctx.addon, ctx.printed, ctx.env, ctx.fire, ctx.frame = loadWithDB(nil, locale or "enUS", loadOpts)
    function ctx.run(msg)
        return run(ctx.addon, ctx.printed, msg)
    end
    function ctx.since(from)
        return linesSince(ctx.printed, from)
    end
    return ctx
end

local BLUE, GREEN = "0070dd", "1eff00"

do
    local ctx = loadGear()
    ctx.combat = true
    for _, msg in ipairs({ "check", "weights", "WEIGHTS reset" }) do
        local out = ctx.run(msg)
        check(("%q refuses in combat"):format(msg), out[1], "Tandem: not available in combat")
        check(("%q prints only the refusal"):format(msg), #out, 1)
    end
    check("help still works in combat", ctx.run("help")[1], "Tandem commands:")
end

for name, setup in pairs({
    ["missing UnitClass"] = function(ctx)
        ctx.env.UnitClass = nil
    end,
    ["missing UnitLevel"] = function(ctx)
        ctx.env.UnitLevel = nil
    end,
    ["nil class"] = function(ctx)
        ctx.class = nil
    end,
    ["nil level"] = function(ctx)
        ctx.level = nil
    end,
    ["secret class"] = function(ctx)
        ctx.class = secret()
    end,
    ["secret level"] = function(ctx)
        ctx.level = secret()
    end,
}) do
    local ctx = loadGear()
    setup(ctx)
    local out = ctx.run("weights")
    check(("%s: weights explains"):format(name), out[1],
        "Tandem: your class or level is not known yet; try again in a moment")
    check(("%s: weights prints one line"):format(name), #out, 1)
end

do
    local ctx = loadGear("zhTW")
    check("zhTW usage lists check", ctx.run("help")[2], "  /tandem check - 列出各功能需要的用戶端 API")
    ctx.class = nil
    check("zhTW unknown class", ctx.run("weights")[1], "Tandem：尚未取得你的職業或等級，請稍後再試")
    ctx.combat = true
    check("zhTW combat refusal", ctx.run("check")[1], "Tandem：戰鬥中無法使用")
end

-- Fake widgets for the frame tests.

-- A fake region or frame. Methods (capitalised keys) that are not stubbed are no-ops; lower-case fields stay nil,
-- so the addon's own fields on a widget behave as on a real frame.
local function noop() end
local WIDGET = {}
WIDGET.__index = function(_, key)
    if WIDGET[key] then
        return WIDGET[key]
    end
    if type(key) == "string" and key:match("^%u") then
        return noop
    end
end
-- Show and Hide run OnShow / OnHide when the state changes, as a real frame does.
function WIDGET.Show(w)
    local was = w.shown
    w.shown = true
    if not was and w.scripts.OnShow then
        w.scripts.OnShow(w)
    end
end
function WIDGET.Hide(w)
    local was = w.shown
    w.shown = false
    if was and w.scripts.OnHide then
        w.scripts.OnHide(w)
    end
end
function WIDGET.SetFocus(w) w.focused = true end
function WIDGET.ClearFocus(w) w.focused = false end
function WIDGET.IsShown(w) return w.shown end
function WIDGET.SetShown(w, shown)
    if shown then
        w:Show()
    else
        w:Hide()
    end
end
function WIDGET.SetScript(w, name, fn) w.scripts[name] = fn end
function WIDGET.GetScript(w, name) return w.scripts[name] end
function WIDGET.SetText(w, text) w.text = text end
function WIDGET.GetText(w) return w.text end
function WIDGET.SetTexture(w, texture) w.texture = texture end
function WIDGET.SetChecked(w, checked) w.checked = checked end
function WIDGET.GetChecked(w) return w.checked end
function WIDGET.SetAlpha(w, alpha) w.alpha = alpha end
function WIDGET.SetTitle(w, title) w.title = title end
function WIDGET.ClearAllPoints(w) w.points = {} end
function WIDGET.SetPoint(w, ...) w.points[#w.points + 1] = { ... } end
function WIDGET.GetPoint(w)
    local p = w.points[1] or {}
    return p[1], p[2], p[3], p[4], p[5]
end
function WIDGET.SetupMenu(w, generator) w.generator = generator end
function WIDGET.SetDontSavePosition(w, v) w.dontSave = v end
function WIDGET.SetUserPlaced(w, v) w.userPlaced = v end
function WIDGET.StopMovingOrSizing(w) w.userPlaced, w.sizing = true, nil end
function WIDGET.SetSize(w, width, height) w.width, w.height = width, height end
function WIDGET.GetSize(w) return w.width, w.height end
function WIDGET.SetResizable(w, v) w.resizable = v end
function WIDGET.SetResizeBounds(w, ...) w.bounds = { ... } end
function WIDGET.SetMinResize(w, ...) w.minResize = { ... } end
function WIDGET.SetMaxResize(w, ...) w.maxResize = { ... } end
function WIDGET.StartSizing(w, corner) w.sizing = corner end
function WIDGET.SetNormalTexture(w, t) w.normal = t end
function WIDGET.SetPushedTexture(w, t) w.pushed = t end
function WIDGET.SetHighlightTexture(w, t) w.highlight = t end
function WIDGET.SetEnabled(w, enabled) w.enabled = enabled end
function WIDGET.IsEnabled(w) return w.enabled end
function WIDGET.SetMaxLetters(w, n) w.maxLetters = n end
function WIDGET.SetParent(w, parent) w.parent = parent end
function WIDGET.SetFrameLevel(w, level) w.level = level end
function WIDGET.GetFrameLevel(w) return w.level or 1 end
function WIDGET.SetFrameStrata(w, strata) w.strata = strata end
function WIDGET.GetFrameStrata(w) return w.strata end
function WIDGET.SetHitRectInsets(w, ...) w.hitInsets = { ... } end
function WIDGET.SetMinMaxValues(w, lo, hi) w.min, w.max = lo, hi end
function WIDGET.SetValue(w, v) w.value = v end
function WIDGET.EnableMouse(w, v) w.mouse = v end
function WIDGET.SetTextColor(w, r, g, b) w.textColor = { r, g, b } end
function WIDGET.SetStatusBarColor(w, r, g, b) w.barColor = { r, g, b } end
function WIDGET.SetHeight(w, h) w.height = h end
function WIDGET.SetWidth(w, v) w.width = v end
function WIDGET.RegisterForClicks(w, ...) w.clicks = { ... } end
function WIDGET.SetAttribute(w, key, value)
    w.attrs = w.attrs or {}
    w.attrs[key] = value
end
-- Six pixels a character stands in for the font's measure.
function WIDGET.GetStringWidth(w) return 6 * #(w.text or "") end

local function newWidget(ui, kind, name, parent, template)
    local w = setmetatable({ ui = ui, kind = kind, name = name, parent = parent, template = template, shown = true,
                             scripts = {}, points = {}, buttons = {} }, WIDGET)
    ui.widgets[#ui.widgets + 1] = w
    return w
end

function WIDGET.CreateFontString(w) return newWidget(w.ui, "FontString", nil, w) end
function WIDGET.CreateTexture(w) return newWidget(w.ui, "Texture", nil, w) end
function WIDGET.SetDataProvider(w, provider)
    w.provider = provider
    for i, row in ipairs(provider.rows) do
        local b = w.buttons[i] or newWidget(w.ui, "Button", nil, w)
        w.buttons[i] = b
        w.view.initializer(b, row)
    end
end
function WIDGET.ForEachFrame(w, fn)
    for i, row in ipairs(w.provider.rows) do
        fn(w.buttons[i], row)
    end
end

-- Weights.Score with a passed weights table (stage 7, decision 3).

do
    local W = loadWithDB(nil, "enUS", { env = {
        UnitName = function() return "Tank" end, GetRealmName = function() return "Realm" end,
    } }).Weights
    W.SetOverride("str", 2, "WARRIOR", 40)
    local stats = { str = 10, int = 3, sta = 4 }
    check("score: a passed weights table scores as Score builds it",
        W.Score(stats, "WARRIOR", 1, W.Effective("WARRIOR", 1)), W.Score(stats, "WARRIOR", 1))
    check("score: the passed weights table is used", W.Score(stats, "WARRIOR", 1, { int = 1 }), 3)
end

-- Fake tooltips for the tooltip tests.

-- A fake tooltip: AddLine records { text, r, g, b, wrap }; forbidden makes IsForbidden true.
local function fakeTooltip()
    local t = { lines = {}, forbidden = false }
    function t.AddLine(self, text, r, g, b, wrap)
        self.lines[#self.lines + 1] = { text = text, r = r, g = g, b = b, wrap = wrap }
    end
    function t.IsForbidden(self)
        return self.forbidden
    end
    return t
end

local function texts(tooltip)
    local out = {}
    for _, l in ipairs(tooltip.lines) do
        out[#out + 1] = l.text
    end
    return table.concat(out, " / ")
end

local function colour(line)
    return line and (line.r .. "," .. line.g .. "," .. line.b) or "nil"
end

-- Check: /tandem check lists each feature's client APIs (stage 6, unit 1).

-- Every API Check looks for, first alternative only for the either-or ones.
local function checkAPIs()
    local fn = function() end
    return {
        TooltipDataProcessor = { AddTooltipPostCall = fn },
        Enum = { TooltipDataType = { Item = 0 } },
        GetQuestItemLink = fn, GetNumQuestChoices = fn,
        QuestInfoRewardsFrame = { RewardButtons = {} },
        C_Container = { GetContainerNumSlots = fn, GetContainerItemID = fn, GetContainerNumFreeSlots = fn },
        GetInventoryItemLink = fn,
        C_Item = { GetItemStats = fn },
        C_TooltipInfo = { GetItemByID = fn, GetTrainerService = fn },
        C_SpecializationInfo = { GetSpecialization = fn },
        GetNumTrainerServices = fn, GetTrainerServiceInfo = fn, GetTrainerServiceLevelReq = fn,
        GetActionInfo = fn, C_Spell = { GetSpellInfo = fn }, IsSpellKnown = fn, ActionButton1 = {},
        ContainerFrame1Item1 = {},
        C_EditMode = { GetLayouts = fn, SaveLayouts = fn, SetActiveLayout = fn }, EditModeManagerFrame = {},
        EditModePresetLayoutManager = { GetCopyOfPresetLayouts = fn },
        MainActionBar = {}, UnitXP = fn, UnitXPMax = fn, ToggleAllBags = fn,
        GetTotemInfo = fn, GetWeaponEnchantInfo = fn, UnitPower = fn,
        GetInventoryItemID = fn, InCombatLockdown = fn, SecureActionButtonMixin = {},
        SecureCmdList = { EQUIP_TO_SLOT = fn }, EquipItemByName = fn,
        C_Map = { GetBestMapForUnit = fn, GetPlayerMapPosition = fn }, RequestTimePlayed = fn,
    }
end

-- Returns the check output as { [feature] = line } after the header, plus the raw lines.
local function runCheck(addon, printed)
    local out = run(addon, printed, "check")
    local byName = {}
    for i = 2, #out do
        byName[out[i]:match("^(.-):")] = out[i]
    end
    return byName, out
end

-- Returns the check output line of the named feature, matched by its (localized) name before an enUS or zhTW colon;
-- "" when none matches.
local function lineFor(out, name)
    for _, line in ipairs(out) do
        if line:sub(1, #name + 1) == name .. ":" or line:sub(1, #name + 3) == name .. "：" then
            return line
        end
    end
    return ""
end

do
    local addon, printed = loadWithDB(nil)
    local byName, out = runCheck(addon, printed)
    check("check: header", out[1], "Tandem API check:")
    check("check: one line per feature and probe", #out, 1 + #addon.Check.FEATURES + #addon.Check.PROBES)
    check("check: fifteen features", #addon.Check.FEATURES, 15)
    check("check: eighteen probes", #addon.Check.PROBES, 18)
    check("check: tooltip missing without the API", byName["Item tooltip"],
        "Item tooltip: missing (TooltipDataProcessor.AddTooltipPostCall missing, Enum.TooltipDataType.Item missing)")
    check("check: quest reward pick lists each button lookup", byName["Quest reward pick"],
        "Quest reward pick: missing (GetNumQuestChoices missing, GetQuestItemLink missing, "
            .. "QuestInfoRewardsFrame.RewardButtons missing, QuestInfoRewardsFrameQuestInfoItem1 missing, "
            .. "QuestRewardItem1 missing)")
    for _, name in ipairs({ "Item tooltip", "Quest reward pick", "Upgrade alert", "Item stats", "Stat search",
        "Talent spec", "Trainer record", "Action bar borders", "Upgrade borders", "Layout", "XP bar", "Bag button",
        "Fishing rod", "Map info", "Shaman area" }) do
        check(("check: %s line present"):format(name), byName[name] ~= nil, true)
        check(("check: %s missing under bare stubs"):format(name),
            byName[name] and byName[name]:match("^[^:]*: (%a+)"), "missing")
    end
    check("check: extra words print usage", run(addon, printed, "check now")[1], "Tandem commands:")
end

do
    local addon, printed = loadWithDB(nil, "enUS", { env = checkAPIs() })
    local byName, out = runCheck(addon, printed)
    for i = 2, 1 + #addon.Check.FEATURES do
        check(("check: %s ok with every API"):format(out[i]:match("^(.-):")), out[i]:match("^[^:]*: (%a+)"), "ok")
    end
    check("check: an ok line lists the APIs", byName["Item tooltip"],
        "Item tooltip: ok (TooltipDataProcessor.AddTooltipPostCall ok, Enum.TooltipDataType.Item ok)")
    check("check: the other alternative shows missing", byName["Item stats"],
        "Item stats: ok (C_Item.GetItemStats ok, GetItemStats missing)")
end

do
    local env = checkAPIs()
    env.QuestRewardItem1 = {}
    env.C_Container = nil
    env.GetContainerNumSlots = function() end
    env.QuestInfoRewardsFrame = 5
    env.Enum = { TooltipDataType = {} }
    local addon, printed = loadWithDB(nil, "enUS", { env = env })
    local byName = runCheck(addon, printed)
    check("check: a named reward button is enough", byName["Quest reward pick"],
        "Quest reward pick: ok (GetNumQuestChoices ok, GetQuestItemLink ok, "
            .. "QuestInfoRewardsFrame.RewardButtons missing, QuestInfoRewardsFrameQuestInfoItem1 missing, "
            .. "QuestRewardItem1 ok)")
    check("check: one need with no alternative fails the feature", byName["Upgrade alert"],
        "Upgrade alert: missing (C_Container.GetContainerNumSlots missing, GetContainerNumSlots ok, "
            .. "C_Container.GetContainerItemID missing, GetContainerItemID missing, GetInventoryItemLink ok)")
    check("check: a non-table step is missing, not an error",
        byName["Quest reward pick"]:match("QuestInfoRewardsFrame.RewardButtons (%a+)"), "missing")
    check("check: a missing field is missing", byName["Item tooltip"]:match("TooltipDataType.Item (%a+)"), "missing")
    check("check: Has on a nil step", addon.Check.Has("NoSuchTable.Field"), false)
    check("check: Has on a present value", addon.Check.Has("GetQuestItemLink"), true)
end

-- Every feature name kept code gates on is a known feature, ready when every path is present: an unknown name is
-- never ready, so a typo would keep a feature dark.
do
    local names = {}
    for _, file in ipairs(tocFiles()) do
        local f = io.open(addonDir .. file, "r")
        if f then
            for name in f:read("*a"):gmatch('Check%.Ready%("([^"]+)"%)') do
                names[name] = true
            end
            f:close()
        end
    end
    local addon = loadWithDB(nil, "enUS", { env = checkAPIs() })
    local count = 0
    for name in pairs(names) do
        count = count + 1
        check(("check: Ready(%q) with every API"):format(name), addon.Check.Ready(name), true)
    end
    check("check: kept code gates on thirteen features", count, 13)
    check("check: an unknown feature is never ready", addon.Check.Ready("Map pins"), false)
end

do
    local addon, printed, env = loadWithDB(nil)
    env.InCombatLockdown = function()
        return true
    end
    local out = run(addon, printed, "check")
    check("check: refused in combat", out[1], "Tandem: not available in combat")
    check("check: prints only the refusal in combat", #out, 1)
end

do
    local addon, printed = loadWithDB(nil, "zhTW", { env = checkAPIs() })
    local out = run(addon, printed, "check")
    check("zhTW check: header", out[1], "Tandem API 檢查：")
    check("zhTW check: feature line", lineFor(out, "物品屬性"),
        "物品屬性：可用（C_Item.GetItemStats 可用, GetItemStats 缺少）")
    check("zhTW check: map info line", lineFor(out, "地圖資訊"):sub(1, #"地圖資訊：可用"), "地圖資訊：可用")
end

-- Live item data (stage 11, D1): the client as the judges read it, with an empty TandemDB.

local RED, WHITE = { r = 1, g = 0.125, b = 0.125 }, { r = 1, g = 1, b = 1 }
local STRENGTH = { enUS = "+%d Strength", zhTW = "+%d 力量" }

-- Loads loadGear with a fresh TandemDB; the client knows GEAR live. ctx.items[id] = { equipLoc,
-- classID, subclassID } is C_Item.GetItemInfoInstant; ctx.cache[id] = { name, link, quality, ilvl, reqLevel } is
-- C_Item.GetItemInfo; ctx.tips[id], a list of left texts or { left, right, leftColor, rightColor } (colours
-- { r, g, b }), is C_TooltipInfo.GetItemByID, left out by opts.noTips. Every GEAR item's tooltip reads its item level
-- as Strength (ctx.strength(n) makes that line), so it scores its item level for a level 40 warrior. Item 900 is a
-- plate chest of item level 60 (Strength 60) the client has not loaded until ctx.cache[900] is set. opts.env adds
-- globals, opts.widgets goes to loadAddon.
local function loadLive(locale, opts)
    opts = opts or {}
    locale = locale or "enUS"
    local tips = {}
    local env = {}
    if not opts.noTips then
        env.C_TooltipInfo = { GetItemByID = function(id)
            if not tips[id] then
                return nil
            end
            local lines = {}
            for i, l in ipairs(tips[id]) do
                lines[i] = type(l) == "table"
                    and { leftText = l[1], rightText = l[2], leftColor = l[3], rightColor = l[4] }
                    or { leftText = l, leftColor = WHITE }
            end
            return { lines = lines }
        end }
    end
    for k, v in pairs(opts.env or {}) do
        env[k] = v
    end
    local ctx = loadGear(locale, { env = env, widgets = opts.widgets })
    function ctx.strength(n)
        return STRENGTH[locale]:format(n)
    end
    ctx.tips, ctx.items = tips, {}
    for id, r in pairs(GEAR) do
        ctx.items[id] = { r[4], r[5], r[6] }
        ctx.cache[id] = { "Item " .. id, nil, r[3], r[1], r[2] }
        tips[id] = { "Item " .. id, ctx.strength(r[1]) }
    end
    ctx.items[900] = { "INVTYPE_CHEST", 4, 4 }
    tips[900] = { "Late Plate", ctx.strength(60) }
    local instant = ctx.env.C_Item.GetItemInfoInstant
    ctx.env.C_Item.GetItemInfoInstant = function(id)
        local it = ctx.items[id]
        if it then
            return id, nil, nil, it[1], nil, it[2], it[3]
        end
        return instant(id)
    end
    return ctx
end

-- Quest reward pick (stage 6, unit 4): an icon on the best choice's button at turn-in.

-- Loads loadLive() with a reward window offering choices (item ids) through the API the client has: opts.style is
-- "list" (QuestInfoRewardsFrame.RewardButtons, choices typed and numbered), "named"
-- (QuestInfoRewardsFrameQuestInfoItem<i>), "old" (QuestRewardItem<i>) or "none". Every quest selection API is a
-- stub that counts its calls in ctx.selected. ctx.quest.choices can change before firing again. opts.noTips goes to
-- loadLive.
local function loadQuest(choices, opts)
    opts = opts or {}
    local q = { choices = choices, buttons = {} }
    local ui = { widgets = {} }
    local style = opts.style or "list"
    local env = {
        GetNumQuestChoices = function()
            return #q.choices
        end,
        GetQuestItemLink = function(list, i)
            local id = list == "choice" and q.choices[i]
            return id and built(id, "ffffff")
        end,
    }
    local list = {}
    for i = 1, 6 do
        local b = newWidget(ui, "Button", style == "named" and ("QuestInfoRewardsFrameQuestInfoItem" .. i)
            or ("QuestRewardItem" .. i))
        q.buttons[i] = b
        if style == "list" then
            b.type = "choice"
            function b.GetID()
                return i
            end
            list[#list + 1] = b
        elseif style == "named" then
            env["QuestInfoRewardsFrameQuestInfoItem" .. i] = b
        elseif style == "old" then
            env["QuestRewardItem" .. i] = b
        end
    end
    if style == "list" then
        local reward = newWidget(ui, "Button")
        reward.type = "reward"
        function reward.GetID()
            return 1
        end
        table.insert(list, 1, reward)
        q.reward = reward
        env.QuestInfoRewardsFrame = { RewardButtons = list }
    end
    local selected = {}
    for _, name in ipairs({ "GetQuestReward", "SelectQuestReward", "QuestInfoItem_OnClick", "CompleteQuest" }) do
        env[name] = function()
            selected[#selected + 1] = name
        end
    end
    local ctx = loadLive("enUS", { env = env, noTips = opts.noTips })
    ctx.quest, ctx.selected = q, selected
    -- Returns the indexes of the buttons with a shown Tandem mark, as "1,3".
    function ctx.marked()
        local out = {}
        for i, b in ipairs(q.buttons) do
            for _, w in ipairs(ui.widgets) do
                if w.parent == b and w.kind == "Texture" and w:IsShown() then
                    out[#out + 1] = tostring(i)
                end
            end
        end
        return table.concat(out, ",")
    end
    -- Returns the mark texture on button i, shown or not.
    function ctx.mark(i)
        for _, w in ipairs(ui.widgets) do
            if w.parent == q.buttons[i] and w.kind == "Texture" then
                return w
            end
        end
    end
    function ctx.complete()
        ctx.fire("QUEST_COMPLETE")
    end
    return ctx
end

do
    local ctx = loadQuest({ 3, 1, 12 })
    local from = #ctx.printed
    ctx.complete()
    check("quest pick: marks the highest item level", ctx.marked(), "2")
    check("quest pick: nothing on the fixed reward", ctx.quest.reward.texture, nil)
    check("quest pick: the mark is the Tandem icon", ctx.mark(2).texture, "Interface\\AddOns\\Tandem\\Media\\icon")
    check("quest pick: the mark sits on the button's top right", ctx.mark(2).points[1][1], "TOPRIGHT")
    check("quest pick: never selects", #ctx.selected, 0)
    check("quest pick: prints nothing", #ctx.since(from), 0)
    ctx.fire("QUEST_FINISHED")
    check("quest pick: QUEST_FINISHED hides the mark", ctx.marked(), "")
    ctx.quest.choices = { 2, 3 }
    ctx.complete()
    check("quest pick: an equal score marks none, whatever the quality", ctx.marked(), "")
    ctx.quest.choices = { 1, 2 }
    ctx.complete()
    check("quest pick: a new window moves the mark", ctx.marked(), "1")
    check("quest pick: still never selects", #ctx.selected, 0)
end

do
    local ctx = loadQuest({ 3, 4 })
    ctx.complete()
    check("quest pick: a tie on item level and quality marks none", ctx.marked(), "")
    ctx.quest.choices = { 3, 4, 1 }
    ctx.complete()
    check("quest pick: a tie below the best still marks the best", ctx.marked(), "3")
    ctx.quest.choices = { 1 }
    ctx.complete()
    check("quest pick: one choice marks none", ctx.marked(), "")
    ctx.quest.choices = { 8, 12 }
    ctx.complete()
    check("quest pick: an unusable choice never wins", ctx.marked(), "2")
end

do
    local ctx = loadQuest({ 1, 3, 12 })
    ctx.tips[1], ctx.tips[3] = { "A", ctx.strength(2) }, { "B", ctx.strength(1) }
    ctx.tips[12] = { "C", ctx.strength(9) }
    ctx.complete()
    check("quest pick score: every choice scored picks the highest score", ctx.marked(), "3")
    ctx.quest.choices = { 12, 8 }
    ctx.tips[8] = nil
    ctx.complete()
    check("quest pick score: an unusable stat-less choice does not stop the score pick", ctx.marked(), "1")
end

do
    local ctx = loadQuest({ 1, 3, 12 })
    ctx.tips[1], ctx.tips[3] = { "A", ctx.strength(2) }, { "B", ctx.strength(9) }
    ctx.tips[12] = { "C", ctx.strength(9) }
    ctx.complete()
    check("quest pick score: a tie on score marks none, whatever the item level", ctx.marked(), "")
    ctx.quest.choices = { 2, 4 }
    ctx.tips[2], ctx.tips[4] = { "D", ctx.strength(5) }, { "E", ctx.strength(5) }
    ctx.complete()
    check("quest pick score: a tie on score and armor marks none", ctx.marked(), "")
    ctx.quest.choices = { 3, 2 }
    ctx.tips[2] = nil
    ctx.complete()
    check("quest pick score: a choice whose tooltip is loading waits", ctx.marked(), "")
end

do
    local ctx = loadQuest({ 1, 3, 12 })
    ctx.tips[1], ctx.tips[3] = { "A", ctx.strength(2) }, { "B", ctx.strength(9) }
    ctx.tips[12] = { "C", ctx.strength(9), "20 Armor" }
    ctx.complete()
    check("quest pick score: a tie on score goes to more armor", ctx.marked(), "3")
end

do
    local ctx = loadQuest({ 12, 1, 3 }, { noTips = true })
    ctx.complete()
    check("quest pick score: without tooltip stats, nothing is marked", ctx.marked(), "")
end

do
    local ctx = loadQuest({ 1, 3 })
    ctx.tips[1] = { "A", ctx.strength(45), { "Requires Level 50", nil, RED } }
    ctx.complete()
    check("quest pick: a red tooltip line is not usable", ctx.marked(), "2")
end

do
    local ctx = loadQuest({ 1, 13 })
    ctx.level = 10
    ctx.complete()
    check("quest pick: no usable choice marks none", ctx.marked(), "")
    ctx.quest.choices = { 9, 99 }
    ctx.level = 40
    ctx.complete()
    check("quest pick: non-equippable choices mark none", ctx.marked(), "")
    check("quest pick: non-equippable choices are not asked for", next(ctx.requested), nil)
end

do
    local ctx = loadQuest({ 3, 1 })
    ctx.combat = true
    local from = #ctx.printed
    ctx.complete()
    check("quest pick: nothing in combat", ctx.marked(), "")
    check("quest pick: nothing printed in combat", #ctx.since(from), 0)
end

for _, style in ipairs({ "named", "old" }) do
    local ctx = loadQuest({ 3, 1 }, { style = style })
    ctx.complete()
    check("quest pick: the " .. style .. " buttons", ctx.marked(), "2")
end

do
    local ctx = loadQuest({ 3, 1 }, { style = "none" })
    local ok = pcall(ctx.complete)
    check("quest pick: no button found is no error", ok, true)
    check("quest pick: no button found marks none", ctx.marked(), "")
end

do
    local ctx = loadQuest({ 3, 1 })
    ctx.env.GetNumQuestChoices = nil
    local ok = pcall(ctx.complete)
    check("quest pick: a missing quest API is no error", ok, true)
    check("quest pick: a missing quest API marks none", ctx.marked(), "")
end

do
    -- Item 900 is a plate chest of item level 60 the client has not loaded yet.
    local ctx = loadQuest({ 1, 900 })
    ctx.complete()
    check("quest pick: an uncached choice is asked for", ctx.requested[900], true)
    check("quest pick: nothing marked while a choice is loading", ctx.marked(), "")
    ctx.cache[900] = { "Late Plate", nil, 3, 60 }
    ctx.fire("GET_ITEM_INFO_RECEIVED", 77, true)
    check("quest pick: another item's info changes nothing", ctx.marked(), "")
    ctx.fire("GET_ITEM_INFO_RECEIVED", 900, true)
    check("quest pick: judged again once it arrives", ctx.marked(), "2")
    ctx.fire("QUEST_FINISHED")
    ctx.cache[900] = nil
    ctx.complete()
    ctx.fire("QUEST_FINISHED")
    ctx.cache[900] = { "Late Plate", nil, 3, 60 }
    ctx.fire("GET_ITEM_INFO_RECEIVED", 900, true)
    check("quest pick: a closed window is not judged again", ctx.marked(), "")
end

-- Upgrade alert (stage 6, unit 5): a chat line when a new bag item beats what is worn.

-- Loads loadLive() with bags read through opts.api: "container" (C_Container, default), "global" (the old global bag
-- functions) or "none". ctx.bags[bag] lists the item ids in a bag (0..5); ctx.bagUpdate() changes nothing but fires
-- BAG_UPDATE_DELAYED. ctx.slotCalls[bag] counts the slot lookups per bag. The player wears item 3 (score 30) on the
-- chest. opts.env adds globals; opts.widgets goes to loadAddon.
local function loadUpgrade(opts)
    opts = opts or {}
    local bags, slotCalls = { [0] = {} }, {}
    local function numSlots(bag)
        return bags[bag] and #bags[bag] or 0
    end
    local function itemID(bag, slot)
        slotCalls[bag] = (slotCalls[bag] or 0) + 1
        return bags[bag] and bags[bag][slot]
    end
    local env = {}
    if (opts.api or "container") == "container" then
        env.C_Container = { GetContainerNumSlots = numSlots, GetContainerItemID = itemID }
    elseif opts.api == "global" then
        env.GetContainerNumSlots, env.GetContainerItemID = numSlots, itemID
    end
    for k, v in pairs(opts.env or {}) do
        env[k] = v
    end
    local ctx = loadLive(opts.locale, { env = env, widgets = opts.widgets })
    ctx.bags, ctx.slotCalls = bags, slotCalls
    function ctx.bagUpdate()
        ctx.fire("BAG_UPDATE_DELAYED")
    end
    -- Puts ids in the bags and fires BAG_UPDATE_DELAYED; returns the lines printed.
    function ctx.loot(...)
        for _, id in ipairs({ ... }) do
            table.insert(bags[0], id)
        end
        local from = #ctx.printed
        ctx.bagUpdate()
        return ctx.since(from)
    end
    ctx.equipped[5] = "|cff0070dd|Hitem:3::::::::::::::|h[Leather Vest]|h|r"
    return ctx
end

local function upgradeLine(slot, id, hex, score, over)
    return ("Tandem: upgrade for %s: %s (score %.1f over %.1f)"):format(slot, built(id, hex), score, over)
end

do
    local ctx = loadUpgrade()
    check("upgrade: BAG_UPDATE_DELAYED registered", ctx.frame.registered.BAG_UPDATE_DELAYED, true)
    check("upgrade: PLAYER_REGEN_ENABLED registered", ctx.frame.registered.PLAYER_REGEN_ENABLED, true)
    ctx.bags[0] = { 1, 13 }
    local from = #ctx.printed
    ctx.bagUpdate()
    check("upgrade: the login snapshot prints nothing", #ctx.since(from), 0)
    check("upgrade: the login snapshot's items are not judged later", #ctx.loot(), 0)
    ctx.bags[0] = {}
    ctx.bagUpdate()
    local out = ctx.loot(1)
    check("upgrade: one line for a new upgrade", #out, 1)
    check("upgrade: the line names the slot, link and scores", out[1], upgradeLine("Chest", 1, BLUE, 45, 30))
    ctx.bags[0] = {}
    ctx.bagUpdate()
    check("upgrade: the same item again prints nothing", #ctx.loot(1), 0)
    check("upgrade: an item no better than the worn one prints nothing", #ctx.loot(4), 0)
    check("upgrade: an item the class cannot use prints nothing", #ctx.loot(8), 0)
    check("upgrade: an item with no ranked slot prints nothing", #ctx.loot(9), 0)
    check("upgrade: the worn item itself prints nothing", #ctx.loot(3), 0)
    out = ctx.loot(13, 2)
    check("upgrade: an empty slot counts as score 0", out[1], upgradeLine("Legs", 13, BLUE, 50, 0))
    check("upgrade: only the upgrades of a batch print", #out, 1)
    check("upgrade: an unchanged bag prints nothing", #ctx.loot(), 0)
    check("upgrade: reads bags 0 to 4 only", ctx.slotCalls[5], nil)
end

do
    local ctx = loadUpgrade()
    ctx.equipped[11] = "|cff1eff00|Hitem:16::::::::::::::|h[Ring]|h|r"
    ctx.cache[16] = { "Ring", nil, 2, 20 }
    ctx.cache[17] = { "Band", nil, 2, 10 }
    local loop = "|cff1eff00|Hitem:18::::|h[Loop]|h|r"
    ctx.cache[18] = { "Loop", loop, 2, 15 }
    ctx.equipped[12] = "|cff1eff00|Hitem:17::::::::::::::|h[Band]|h|r"
    for id, n in pairs({ [16] = 20, [17] = 10, [18] = 15 }) do
        ctx.items[id] = { "INVTYPE_FINGER", 4, 0 }
        ctx.tips[id] = { "Ring", ctx.strength(n) }
    end
    ctx.bagUpdate()
    local out = ctx.loot(18)
    check("upgrade: a ring is judged against the weaker worn ring", out[1],
        ("Tandem: upgrade for Finger: %s (score 15.0 over 10.0)"):format(loop))
end

do
    local ctx = loadUpgrade()
    ctx.equipped[16] = "|cff1eff00|Hitem:15::::::::::::::|h[Axe]|h|r"
    ctx.bagUpdate()
    check("upgrade: no off-hand line while wielding a two-hander", #ctx.loot(5, 14), 0)
end

-- Two-hander against both hands (D3): a bag two-hander (item 50) beats the main hand and the off hand together.
do
    local ctx = loadUpgrade()
    local Upgrade, Items = ctx.addon.Upgrade, ctx.addon.Items
    local function twoHander(id, str)
        ctx.items[id] = { "INVTYPE_2HWEAPON", 2, 1 }
        ctx.cache[id] = { "Axe " .. id, nil, 2, 30, 20 }
        ctx.tips[id] = { "Axe " .. id, ctx.strength(str) }
    end
    twoHander(50, 30)
    ctx.tips[7] = { "Sword", ctx.strength(20) }
    ctx.tips[5] = { "Shield", ctx.strength(15) }
    ctx.equipped[16] = "|cff1eff00|Hitem:7::::::::::::::|h[Sword]|h|r"
    ctx.equipped[17] = "|cff1eff00|Hitem:5::::::::::::::|h[Shield]|h|r"
    check("two-hand: 30 does not beat main 20 + shield 15", Upgrade.Better(50), false)
    local worn = Items.Equipped("twohand")
    check("two-hand: both hands make one entry", #worn.list, 1)
    check("two-hand: the entry sums both hands", worn.score, 35)
    check("two-hand: the entry is at the lower item level", worn.ilvl, 20)
    check("two-hand: both hands are worn ids", worn.ids[7] and worn.ids[5], true)
    ctx.equipped[17] = nil
    ctx.fire("PLAYER_EQUIPMENT_CHANGED")
    check("two-hand: 30 beats main 20 with an empty off hand", Upgrade.Better(50), true)
    check("two-hand: an empty off hand adds 0", Items.Equipped("twohand").score, 20)

    ctx.tips[14] = { "Off Sword", "(10.0 damage per second)" }
    ctx.equipped[17] = "|cff1eff00|Hitem:14::::::::::::::|h[Off Sword]|h|r"
    local full = Items.Score(14, "WARRIOR", 40)
    check("two-hand: the off-hand weapon has a dps score", full > 0, true)
    check("two-hand: an off-hand weapon's dps counts half", Items.Equipped("twohand").score, 20 + full / 2)

    ctx.equipped[17] = secret()
    check("two-hand: an unknown off hand answers nil", Items.Beats(99, 99, Items.Equipped("twohand")), nil)
    ctx.equipped[17] = nil
    ctx.equipped[16] = secret()
    check("two-hand: an unknown main hand answers nil", Items.Beats(99, 99, Items.Equipped("twohand")), nil)
end

do
    local ctx = loadUpgrade()
    local Upgrade, Items = ctx.addon.Upgrade, ctx.addon.Items
    for id, str in pairs({ [50] = 35, [51] = 25 }) do
        ctx.items[id] = { "INVTYPE_2HWEAPON", 2, 1 }
        ctx.cache[id] = { "Axe " .. id, nil, 2, 30, 20 }
        ctx.tips[id] = { "Axe " .. id, ctx.strength(str) }
    end
    ctx.equipped[16] = "|cff1eff00|Hitem:15::::::::::::::|h[Axe]|h|r"
    local worn = Items.Equipped("twohand")
    check("two-hand: a worn two-hander alone is its own entry", worn.list[1].id, 15)
    check("two-hand: a worn two-hander scores alone", worn.score, 30)
    check("two-hand: a better two-hander beats a worn one", Upgrade.Better(50), true)
    check("two-hand: a worse two-hander does not", Upgrade.Better(51), false)
end

do
    local ctx = loadUpgrade()
    ctx.bagUpdate()
    local out = ctx.loot(900)
    check("upgrade: an uncached item prints nothing yet", #out, 0)
    check("upgrade: an uncached item is asked for", ctx.requested[900], true)
    ctx.cache[900] = { "Late Plate", "|cffa335ee|Hitem:900::::|h[Late Plate]|h|r", 4, 60 }
    local from = #ctx.printed
    ctx.fire("GET_ITEM_INFO_RECEIVED", 77, true)
    check("upgrade: another item's info prints nothing", #ctx.since(from), 0)
    ctx.fire("GET_ITEM_INFO_RECEIVED", 900, true)
    out = ctx.since(from)
    check("upgrade: a late item prints once it arrives", out[1],
        "Tandem: upgrade for Chest: |cffa335ee|Hitem:900::::|h[Late Plate]|h|r (score 60.0 over 30.0)")
    check("upgrade: a late item prints one line", #out, 1)
    ctx.fire("GET_ITEM_INFO_RECEIVED", 900, true)
    check("upgrade: its info again prints nothing", #ctx.since(from), 1)
end

do
    local ctx = loadUpgrade()
    ctx.bagUpdate()
    ctx.loot(900)
    ctx.bags[0] = {}
    ctx.bagUpdate()
    ctx.cache[900] = { "Late Plate", nil, 4, 60 }
    local from = #ctx.printed
    ctx.fire("GET_ITEM_INFO_RECEIVED", 900, true)
    check("upgrade: a late item gone from the bags prints nothing", #ctx.since(from), 0)
end

do
    local ctx = loadUpgrade()
    ctx.bagUpdate()
    ctx.combat = true
    check("upgrade: nothing printed in combat", #ctx.loot(1, 900), 0)
    ctx.cache[900] = { "Late Plate", nil, 4, 60 }
    local from = #ctx.printed
    ctx.fire("GET_ITEM_INFO_RECEIVED", 900, true)
    check("upgrade: a late item in combat prints nothing", #ctx.since(from), 0)
    ctx.combat = false
    ctx.fire("PLAYER_REGEN_ENABLED")
    local out = ctx.since(from)
    check("upgrade: combat lines print after combat", #out, 2)
    check("upgrade: combat lines keep their order", out[1], upgradeLine("Chest", 1, BLUE, 45, 30))
    ctx.fire("PLAYER_REGEN_ENABLED")
    check("upgrade: queued lines print once", #ctx.since(from), 2)
end

for _, api in ipairs({ "global", "none" }) do
    local ctx = loadUpgrade({ api = api })
    local ok = pcall(ctx.bagUpdate)
    ctx.loot(1)
    local out = ctx.loot(13)
    check("upgrade: the " .. api .. " bag API is no error", ok, true)
    check("upgrade: the " .. api .. " bag API", #out, api == "global" and 1 or 0)
end

do
    local ctx = loadUpgrade()
    for id, n in pairs({ [3] = 10, [1] = 5, [12] = 12, [13] = 1 }) do
        ctx.tips[id] = { "Item", ctx.strength(n) }
    end
    ctx.bagUpdate()
    check("upgrade score: a lower score is no upgrade at a higher item level", #ctx.loot(1), 0)
    check("upgrade score: a higher score is an upgrade at a lower item level", ctx.loot(12)[1],
        ("Tandem: upgrade for Chest: %s (score 12.0 over 10.0)"):format(built(12, GREEN)))
    check("upgrade score: an empty slot counts as score 0", ctx.loot(13)[1],
        upgradeLine("Legs", 13, BLUE, 1, 0))
    ctx.tips[11] = nil
    ctx.equipped[5] = "|Hitem:11:|h"
    ctx.addon.Upgrade.Invalidate()
    check("upgrade score: a stat-less worn item gives no line", ctx.loot(4, 2)[1], nil)
end

do
    local ctx = loadUpgrade({ locale = "zhTW" })
    ctx.tips[3], ctx.tips[12] = { "Item", ctx.strength(1) }, { "Item", ctx.strength(2) }
    ctx.bagUpdate()
    check("zhTW upgrade alert score line", ctx.loot(12)[1],
        ("Tandem：胸部的升級：%s（分數 2.0，高於 1.0）"):format(built(12, GREEN, "物品 #12")))
end

do
    local ctx = loadUpgrade({ locale = "zhTW" })
    ctx.bagUpdate()
    check("zhTW upgrade alert line", ctx.loot(1)[1],
        ("Tandem：胸部的升級：%s（分數 45.0，高於 30.0）"):format(built(1, BLUE, "物品 #1")))
end

do
    local ctx = loadUpgrade()
    local Upgrade = ctx.addon.Upgrade
    local from = #ctx.printed
    check("upgrade better: an upgrade is true", Upgrade.Better(1), true)
    check("upgrade better: no better than worn is false", Upgrade.Better(4), false)
    check("upgrade better: not usable is false", Upgrade.Better(8), false)
    check("upgrade better: no ranked slot is false", Upgrade.Better(9), false)
    check("upgrade better: the worn item is false", Upgrade.Better(3), false)
    check("upgrade better: a loading item is nil", Upgrade.Better(900), nil)
    check("upgrade better: a loading item is asked for", ctx.requested[900], true)
    check("upgrade better: Better prints nothing", #ctx.since(from), 0)
    check("upgrade better: another item's info is not judged", Upgrade.OnItemInfo(77), false)
    ctx.cache[900] = { "Late Plate", nil, 4, 60 }
    check("upgrade better: a waiting item's info is judged", Upgrade.OnItemInfo(900), true)
    check("upgrade better: its info again is not judged", Upgrade.OnItemInfo(900), false)
    check("upgrade better: the loaded item is true", Upgrade.Better(900), true)
    check("upgrade better: an item Better asked for prints nothing", #ctx.since(from), 0)
end

do
    local ctx = loadUpgrade()
    local Upgrade = ctx.addon.Upgrade
    ctx.equipped[5] = "|Hitem:900:|h"
    ctx.tips[900] = { "Late Plate", ctx.strength(20) }
    check("upgrade better: a loading worn item gives nil", Upgrade.Better(1), nil)
    ctx.cache[900] = { "Late Plate", nil, 4, 20 }
    check("upgrade better: an answer on incomplete worn data is not kept", Upgrade.Better(1), true)
end

do
    local ctx = loadUpgrade()
    local Upgrade = ctx.addon.Upgrade
    check("upgrade better: first answer", Upgrade.Better(1), true)
    ctx.cache[900] = { "Late Plate", nil, 4, 60 }
    ctx.equipped[5] = "|Hitem:900:|h"
    check("upgrade better: a kept answer is reused", Upgrade.Better(1), true)
    Upgrade.Invalidate()
    check("upgrade better: Invalidate recomputes", Upgrade.Better(1), false)
    ctx.equipped[5] = "|Hitem:3:|h"
    check("upgrade better: kept false until the key changes", Upgrade.Better(1), false)
    ctx.level = 41
    check("upgrade better: a level change recomputes", Upgrade.Better(1), true)
    ctx.equipped[5] = "|Hitem:900:|h"
    check("upgrade better: kept true at the new level", Upgrade.Better(1), true)
    ctx.addon.Weights.revision = ctx.addon.Weights.revision + 1
    check("upgrade better: a Weights revision change recomputes", Upgrade.Better(1), false)
    ctx.equipped[5] = "|Hitem:3:|h"
    ctx.fire("PLAYER_EQUIPMENT_CHANGED")
    check("upgrade better: an equipment change recomputes", Upgrade.Better(1), true)
end

do
    local ctx = loadUpgrade()
    ctx.bags[0] = { 900 }
    ctx.bagUpdate()
    local from = #ctx.printed
    check("upgrade better: a snapshot item Better asks for is nil", ctx.addon.Upgrade.Better(900), nil)
    ctx.cache[900] = { "Late Plate", nil, 4, 60 }
    check("upgrade better: the snapshot item's info is judged", ctx.addon.Upgrade.OnItemInfo(900), true)
    check("upgrade better: a snapshot item Better asked for prints nothing", #ctx.since(from), 0)
    check("upgrade better: the snapshot item is then true", ctx.addon.Upgrade.Better(900), true)
end

-- Score-only hints (stage 10, unit 5): loadUpgrade, whose ctx.tips are the tooltips.
local loadTipUpgrade = loadUpgrade

do
    local ctx = loadUpgrade()
    ctx.tips[1] = { "Plate Chest", ctx.strength(10) }
    ctx.bagUpdate()
    check("upgrade d6: a higher ilvl with a lower score is no upgrade", ctx.addon.Upgrade.Better(1), false)
    check("upgrade d6: a higher ilvl with a lower score prints nothing", #ctx.loot(1), 0)
end

do
    local ctx = loadTipUpgrade()
    local before = dump(ctx.env.TandemDB)
    ctx.tips[1] = { "Plate Chest", "+40 Strength" }
    check("upgrade d6: an unscanned item is judged by its tooltip's stats", ctx.addon.Upgrade.Better(1), true)
    check("upgrade d6: the read stats are not saved", dump(ctx.env.TandemDB), before)
end

do
    local ctx = loadTipUpgrade()
    local before = dump(ctx.env.TandemDB)
    ctx.tips[3] = { "Leather Vest", "+50 Strength" }
    ctx.tips[4] = { "Robe", "+5 Strength" }
    ctx.tips[1] = { "Plate Chest", "+45 Strength" }
    check("upgrade d6: the worn item's stats are read before judging", ctx.addon.Upgrade.Better(1), false)
    check("upgrade d6: the worn item's read stats are not saved", dump(ctx.env.TandemDB), before)
end

do
    local ctx = loadTipUpgrade()
    local before = dump(ctx.env.TandemDB)
    ctx.tips[1] = nil
    ctx.bagUpdate()
    check("upgrade d6: unreadable stats are nil", ctx.addon.Upgrade.Better(1), nil)
    check("upgrade d6: unreadable stats print nothing", #ctx.loot(1), 0)
    check("upgrade d6: unreadable stats are not saved", dump(ctx.env.TandemDB), before)
    ctx.tips[1] = { "Plate Chest", "+40 Strength" }
    local from = #ctx.printed
    check("upgrade d6: the item's info is judged", ctx.addon.Upgrade.OnItemInfo(1), true)
    check("upgrade d6: readable stats then give the line", ctx.since(from)[1], upgradeLine("Chest", 1, BLUE, 40, 30))
    check("upgrade d6: readable stats then give true", ctx.addon.Upgrade.Better(1), true)
end

do
    local ctx = loadTipUpgrade()
    ctx.tips[1] = { "Plate Chest", "+45 Strength", { "Classes: Rogue", nil, RED } }
    ctx.bagUpdate()
    check("upgrade d7: a red requirement line is no upgrade", ctx.addon.Upgrade.Better(1), false)
    check("upgrade d7: a red requirement line prints nothing", #ctx.loot(1), 0)
    ctx.tips[4] = { "Robe", "+90 Strength", { "Chest", "Cloth", WHITE, WHITE } }
    check("upgrade d7: white lines are no block", ctx.addon.Upgrade.Better(4), true)
end

do
    local ctx = loadTipUpgrade()
    ctx.tips[1] = { "Plate Chest", "+45 Strength", { "Chest", "Plate", WHITE, RED } }
    check("upgrade d7: a red right text (untrained armor) is no upgrade", ctx.addon.Upgrade.Better(1), false)
    ctx.tips[1] = { "Plate Chest", "+45 Strength", { "Chest", "Plate", WHITE, WHITE } }
    check("upgrade d7: the answer is kept until skills change", ctx.addon.Upgrade.Better(1), false)
    ctx.fire("SKILL_LINES_CHANGED")
    check("upgrade d7: SKILL_LINES_CHANGED judges again once the line is white", ctx.addon.Upgrade.Better(1), true)
    ctx.tips[1] = { "Plate Chest", { "Requires Level 50", nil, RED } }
    ctx.fire("PLAYER_LEVEL_UP", 41)
    check("upgrade d7: PLAYER_LEVEL_UP judges again", ctx.addon.Upgrade.Better(1), false)
    check("upgrade d7: SKILL_LINES_CHANGED registered", ctx.frame.registered.SKILL_LINES_CHANGED, true)
end

do
    local ctx = loadTipUpgrade()
    ctx.cache[1] = nil
    ctx.tips[1] = { "Plate Chest" }
    check("upgrade d7: an unloaded tooltip is nil", ctx.addon.StatSearch.Blocked(1), nil)
    check("upgrade d7: an unloaded tooltip is asked for", ctx.requested[1], true)
    ctx.env.C_TooltipInfo = nil
    check("upgrade d7: no tooltip API blocks nothing", ctx.addon.StatSearch.Blocked(1), false)
end

do
    local ctx = loadTipUpgrade()
    local before = dump(ctx.env.TandemDB)
    ctx.cache[950], ctx.items[950] = { "Potion", nil, 1, 5 }, { "", 0, 1 }
    ctx.tips[8], ctx.tips[9], ctx.tips[950] = { "Cloth", "+9 Strength" }, { "Thing", "+9 Strength" }, { "Potion" }
    check("upgrade d6: a potion is no upgrade", ctx.addon.Upgrade.Better(950), false)
    check("upgrade d6: an unusable item is no upgrade", ctx.addon.Upgrade.Better(8), false)
    check("upgrade d6: an item without a slot is no upgrade", ctx.addon.Upgrade.Better(9), false)
    check("upgrade d6: TandemDB is unchanged", dump(ctx.env.TandemDB), before)
end

do
    local ctx = loadTipUpgrade()
    ctx.cache[3] = nil
    ctx.bagUpdate()
    check("upgrade d6: a worn item still loading prints nothing", #ctx.loot(1), 0)
    check("upgrade d6: the loading worn item is asked for", ctx.requested[3], true)
    check("upgrade d6: an unrelated item's info is not judged", ctx.addon.Upgrade.OnItemInfo(77), false)
    ctx.cache[3] = { "Leather Vest", nil, 3, 30 }
    local from = #ctx.printed
    check("upgrade d6: the worn item's info is judged", ctx.addon.Upgrade.OnItemInfo(3), true)
    check("upgrade d6: the waiting bag item then gets its line", ctx.since(from)[1],
        upgradeLine("Chest", 1, BLUE, 45, 30))
    check("upgrade d6: one line", #ctx.since(from), 1)
end

do
    local skills = { { "Swords", 50 }, { "Defense", 100 } }
    local ctx = loadTipUpgrade()
    ctx.env.GetNumSkillLines = function()
        return #skills
    end
    ctx.env.GetSkillLineInfo = function(i)
        return skills[i][1], false, nil, skills[i][2]
    end
    local Upgrade = ctx.addon.Upgrade
    ctx.tips[1] = { "Plate Chest", "+45 Strength", { "Chest", "Plate", WHITE, RED } }
    check("upgrade d7: blocked before the skill change", Upgrade.Better(1), false)
    ctx.fire("SKILL_LINES_CHANGED")
    check("upgrade d7: still blocked after the first skill read", Upgrade.Better(1), false)
    ctx.tips[1] = { "Plate Chest", "+45 Strength", { "Chest", "Plate", WHITE, WHITE } }
    skills[1][2] = 51
    check("upgrade d7: a skill point only does not judge again", Upgrade.OnSkillLines(), false)
    check("upgrade d7: so the kept answer stays", Upgrade.Better(1), false)
    table.insert(skills, { "Plate Mail", 1 })
    check("upgrade d7: a newly learned skill judges again", Upgrade.OnSkillLines(), true)
    check("upgrade d7: so the item is now an upgrade", Upgrade.Better(1), true)
    ctx.env.GetNumSkillLines = nil
    check("upgrade d7: without the skill API every change judges again", Upgrade.OnSkillLines(), true)
end

-- Weights (stage 7, unit 4): built-in weights per class and tree, spec detection, per-character overrides, Score.

-- Loads the addon for "Tom-Realm" (ctx.name renames) with opts.talents as the talent API: "old" (name, icon,
-- points), "new" (id, name, description, icon, points) over ctx.points, "spec" (C_SpecializationInfo over ctx.spec)
-- or nil for none. opts.db is TandemDB. Returns addon, ctx, env.
local function weightsData(opts)
    opts = opts or {}
    local ctx = { points = { 0, 0, 0 } }
    local env = {
        UnitName = function()
            return ctx.name or "Tom"
        end,
        GetRealmName = function()
            return "Realm"
        end,
        UnitLevel = function()
            return 60
        end,
    }
    if opts.talents == "old" or opts.talents == "new" then
        env.GetNumTalentTabs = function()
            return 3
        end
        env.GetTalentTabInfo = function(i)
            if opts.talents == "old" then
                return "Tree" .. i, "icon", ctx.points[i], "bg"
            end
            return 100 + i, "Tree" .. i, "desc", "icon", ctx.points[i], "bg", 0, true
        end
    elseif opts.talents == "spec" then
        env.C_SpecializationInfo = { GetSpecialization = function()
            return ctx.spec
        end }
    end
    local addon, _, e = loadWithDB(opts.db, "enUS", { env = env })
    return addon, ctx, e
end

do
    local W = weightsData().Weights
    local classes, trees, badKeys, badDefault = 0, 0, 0, 0
    local isKey = {}
    for _, key in ipairs(W.KEYS) do
        isKey[key] = true
    end
    for class, specs in pairs(W.DEFAULTS) do
        classes = classes + 1
        trees = trees + #specs
        for _, weights in ipairs(specs) do
            for key, w in pairs(weights) do
                if not isKey[key] or type(w) ~= "number" then
                    badKeys = badKeys + 1
                end
            end
        end
        local d = W.DEFAULT_SPEC[class]
        if not (d and specs[d] and #W.SPECS[class] == 3) then
            badDefault = badDefault + 1
        end
    end
    check("weights: nine classes", classes, 9)
    check("weights: three trees each", trees, 27)
    check("weights: built-ins use only the stored stat keys", badKeys, 0)
    check("weights: each class has a default tree", badDefault, 0)
    check("weights: twenty-one stat keys", #W.KEYS, 21)
end

do
    local W = weightsData().Weights
    check("weights: Score of nil stats is nil", W.Score(nil, "WARRIOR", 1), nil)
    check("weights: Score is the weighted sum", W.Score({ str = 10, sta = 5 }, "WARRIOR", 1), 12.5)
    check("weights: Score ignores unweighted stats", W.Score({ str = 10, sp = 30 }, "WARRIOR", 1), 10)
    check("weights: Score of no stats is 0", W.Score({}, "WARRIOR", 1), 0)
    check("weights: Score for an unknown class is 0", W.Score({ str = 10 }, "MONK", 1), 0)
    check("weights: Score without a spec uses the active one", W.Score({ str = 10, sta = 5 }, "WARRIOR"), 12.5)
    check("weights: a caster item scores below a strength item for a warrior",
        W.Score({ sp = 20, int = 10 }, "WARRIOR", 1) < W.Score({ str = 10 }, "WARRIOR", 1), true)
    check("weights: a caster item scores above a strength item for a mage",
        W.Score({ sp = 20, int = 10 }, "MAGE", 3) > W.Score({ str = 10 }, "MAGE", 3), true)
    check("weights: healing counts for a holy priest", W.Score({ heal = 10 }, "PRIEST", 2), 10)
    check("weights: healing does not count for a shadow priest", W.Score({ heal = 10 }, "PRIEST", 3), 0)
    local e = W.Effective("WARRIOR", 1)
    e.str = 99
    check("weights: Effective returns a copy", W.DEFAULTS.WARRIOR[1].str, 1)
    check("weights: Effective of an unknown spec is empty", next(W.Effective("WARRIOR", 4)), nil)
end

do
    local addon = weightsData()
    local W = addon.Weights
    check("weights: no talent API is not ready", addon.Check.Ready("Talent spec"), false)
    check("weights: no talent API detects nothing", W.DetectSpec(60), nil)
    local spec, auto = W.Active("PRIEST", 60)
    check("weights: no talent API falls back to the class default", spec, 3)
    check("weights: the fallback is auto", auto, true)
    check("weights: a class without built-ins has no active spec", (W.Active("MONK", 60)), nil)
end

for _, style in ipairs({ "old", "new" }) do
    local addon, ctx = weightsData({ talents = style })
    local W = addon.Weights
    check(("weights %s: talent tabs are ready"):format(style), addon.Check.Ready("Talent spec"), true)
    check(("weights %s: nothing spent detects nothing"):format(style), W.DetectSpec(60), nil)
    check(("weights %s: nothing spent falls back to the default"):format(style), (W.Active("WARRIOR", 60)), 1)
    ctx.points = { 5, 0, 31 }
    check(("weights %s: the tree with most points"):format(style), W.DetectSpec(60), 3)
    check(("weights %s: Active follows the talents"):format(style), (W.Active("WARRIOR", 60)), 3)
    check(("weights %s: below level 10 uses the default"):format(style), (W.Active("WARRIOR", 9)), 1)
    ctx.points = { 10, 10, 0 }
    check(("weights %s: a tie picks the first tree"):format(style), W.DetectSpec(60), 1)
end

do
    local addon, ctx = weightsData({ talents = "spec" })
    local W = addon.Weights
    check("weights spec: the specialization API is ready", addon.Check.Ready("Talent spec"), true)
    ctx.spec = 2
    check("weights spec: reads the specialization", W.DetectSpec(60), 2)
    ctx.spec = 5
    check("weights spec: an out-of-range spec falls back", (W.Active("DRUID", 60)), 2)
    ctx.spec = nil
    check("weights spec: no specialization falls back", (W.Active("MAGE", 60)), 3)
end

do
    local addon, _, env = weightsData({ talents = "old" })
    local W = addon.Weights
    check("weights: a db without weights reads the built-ins", W.Effective("WARRIOR", 1).str, 1)
    check("weights: set an override", W.SetOverride("str", 2, "WARRIOR", 60), true)
    check("weights: the weights table is created lazily", type(env.TandemDB.weights), "table")
    check("weights: the override is saved per character and spec",
        env.TandemDB.weights["Tom-Realm"].overrides[1].str, 2)
    check("weights: Effective applies the override", W.Effective("WARRIOR", 1).str, 2)
    check("weights: Score uses the override", W.Score({ str = 10 }, "WARRIOR", 1), 20)
    check("weights: an override does not touch the built-ins", W.DEFAULTS.WARRIOR[1].str, 1)
    check("weights: 0 is a valid override", W.SetOverride("sta", 0, "WARRIOR", 60), true)
    check("weights: a 0 override ignores the stat", W.Score({ sta = 10 }, "WARRIOR", 1), 0)
    check("weights: an override may add a stat",
        W.SetOverride("sp", 0.5, "WARRIOR", 60) and W.Score({ sp = 10 }, "WARRIOR", 1), 5)
    check("weights: an unknown stat is refused", W.SetOverride("fire", 1, "WARRIOR", 60), false)
    check("weights: a non-number is refused", W.SetOverride("str", "2", "WARRIOR", 60), false)
    check("weights: NaN is refused", W.SetOverride("str", 0 / 0, "WARRIOR", 60), false)
    check("weights: a class without built-ins is refused", W.SetOverride("str", 1, "MONK", 60), false)

    check("weights: set spec 2", W.SetSpec(2), true)
    local spec, auto = W.Active("WARRIOR", 60)
    check("weights: a chosen spec is active", spec, 2)
    check("weights: a chosen spec is not auto", auto, false)
    check("weights: the other spec's overrides do not apply", W.Effective("WARRIOR", 2).str, 1)
    check("weights: set an override on spec 2", W.SetOverride("agi", 3, "WARRIOR", 60), true)
    check("weights: reset drops the active spec's overrides", W.Reset("WARRIOR", 60), true)
    check("weights: reset spec 2 restores its built-ins", W.Effective("WARRIOR", 2).agi, 0.7)
    check("weights: reset keeps the other spec's overrides", W.Effective("WARRIOR", 1).str, 2)
    check("weights: spec 4 is refused", W.SetSpec(4), false)
    check("weights: spec 1.5 is refused", W.SetSpec(1.5), false)
    check("weights: a refused spec keeps the choice", (W.Active("WARRIOR", 60)), 2)
    check("weights: set spec auto", W.SetSpec("auto"), true)
    spec, auto = W.Active("WARRIOR", 60)
    check("weights: auto returns to the detected or default spec", spec, 1)
    check("weights: auto is auto", auto, true)
    check("weights: auto clears the saved spec", env.TandemDB.weights["Tom-Realm"].spec, nil)
end

do
    local addon, ctx, env = weightsData()
    local W = addon.Weights
    env.TandemDB.weights = { ["Tom-Realm"] = "bad", ["Ann-Realm"] = { spec = 7, overrides = {
        [1] = { str = "x", fire = 3, agi = 2 }, [3] = "bad" } } }
    check("weights: a garbled entry reads as none", W.Effective("WARRIOR", 1).str, 1)
    check("weights: a garbled entry is replaced on write",
        W.SetSpec(3) and env.TandemDB.weights["Tom-Realm"].spec, 3)
    ctx.name = "Ann"
    check("weights: an invalid saved spec is auto", select(2, W.Active("WARRIOR", 60)), true)
    local e = W.Effective("WARRIOR", 1)
    check("weights: a non-number override is skipped", e.str, 1)
    check("weights: an unknown key override is skipped", e.fire, nil)
    check("weights: a valid override beside bad ones applies", e.agi, 2)
    check("weights: a non-table spec override is skipped", W.Effective("WARRIOR", 3).sta, 1)
    check("weights: an override replaces a non-table spec entry",
        W.SetSpec(3) and W.SetOverride("sta", 2, "WARRIOR", 60) and W.Effective("WARRIOR", 3).sta, 2)
    ctx.name = ""
    check("weights: an unknown character cannot save", W.SetSpec(1), false)
    check("weights: an unknown character reads the built-ins", W.Effective("WARRIOR", 3).sta, 1)
end

do
    local addon, _, env = weightsData({ db = { schemaVersion = 99, items = {} } })
    local W = addon.Weights
    check("weights: a newer db is read-only", addon.Store.readOnly, true)
    check("weights: read-only refuses a spec", W.SetSpec(2), false)
    check("weights: read-only refuses an override", W.SetOverride("str", 2, "WARRIOR", 60), false)
    check("weights: read-only refuses a reset", W.Reset("WARRIOR", 60), false)
    check("weights: read-only leaves the db alone", env.TandemDB.weights, nil)
end

do
    local addon, printed = loadWithDB(nil, "enUS", { env = checkAPIs() })
    local byName = runCheck(addon, printed)
    check("check: talent spec lists its alternatives", byName["Talent spec"],
        "Talent spec: ok (GetTalentTabInfo missing, C_SpecializationInfo.GetSpecialization ok, "
            .. "GetSpecialization missing)")
    local zh, zhPrinted = loadWithDB(nil, "zhTW")
    local out = run(zh, zhPrinted, "check")
    check("zhTW check: talent spec line", lineFor(out, "天賦專精"):match("^天賦專精："), "天賦專精：")
    check("zhTW check: trainer record line", lineFor(out, "訓練師紀錄"), "訓練師紀錄：缺少（GetNumTrainerServices 缺少, "
        .. "GetTrainerServiceInfo 缺少, GetTrainerServiceLevelReq 缺少, C_TooltipInfo.GetTrainerService 缺少）")
    check("zhTW check: action bar borders line", lineFor(out, "快捷列邊框"), "快捷列邊框：缺少（GetActionInfo 缺少, GetSpellInfo 缺少, "
        .. "C_Spell.GetSpellInfo 缺少, IsSpellKnown 缺少, IsPlayerSpell 缺少, ActionButton1 缺少）")
end

-- Upgrade borders and the loot/bag probes in /tandem check (stage 10, unit 4).

local PROBES = {
    "LootButton1", "LootFrame.ScrollBox", "LootFrame_Update", "ContainerFrame1Item1.IconBorder",
    "ContainerFrame1Item1.NewItemTexture", "ContainerFrame1Item1.UpgradeIcon", "Enum.EditModeSystem.ChatFrame",
    "MainStatusTrackingBarContainer", "BagsBar", "Enum.EditModeSystem.MicroMenu", "Enum.EditModeSystem.Minimap",
    "Enum.EditModeSystem.AuraFrame", "Enum.EditModeActionBarSetting.HideBarArt", "MainActionBar.EndCaps",
    "MainMenuBar.EndCaps", "MainMenuBarArtFrame.LeftEndCap", "MainMenuBarLeftEndCap",
    "Enum.EditModeSystem.ObjectiveTracker",
}

do
    local addon = loadWithDB(nil, "enUS", { env = checkAPIs() })
    check("upgrade borders: ready with the classic bag button", addon.Check.Ready("Upgrade borders"), true)
    local env = checkAPIs()
    env.ContainerFrame1Item1 = nil
    env.ContainerFrameCombinedBags = {}
    addon = loadWithDB(nil, "enUS", { env = env })
    check("upgrade borders: ready with only the combined bags", addon.Check.Ready("Upgrade borders"), true)
    env = checkAPIs()
    env.ContainerFrame1Item1 = nil
    addon = loadWithDB(nil, "enUS", { env = env })
    check("upgrade borders: not ready without a bag button", addon.Check.Ready("Upgrade borders"), false)
    check("upgrade borders: the alert alone stays ready", addon.Check.Ready("Upgrade alert"), true)
end

do
    local addon, printed = loadWithDB(nil)
    local out = run(addon, printed, "check")
    local n = 1 + #addon.Check.FEATURES
    check("check: upgrade borders line", lineFor(out, "Upgrade borders"),
        "Upgrade borders: missing (C_Container.GetContainerNumSlots missing, "
        .. "GetContainerNumSlots missing, C_Container.GetContainerItemID missing, GetContainerItemID missing, "
        .. "GetInventoryItemLink missing, ContainerFrame1Item1 missing, ContainerFrameCombinedBags missing)")
    for i, path in ipairs(PROBES) do
        check(("probe: %s missing"):format(path), out[n + i], ("Probe: %s missing"):format(path))
    end
    check("probe: nothing after the probes", out[n + #PROBES + 1], nil)

    local fn = function() end
    local explode = setmetatable({}, { __index = function() error("no such key") end })
    addon, printed = loadWithDB(nil, "enUS", { env = {
        LootButton1 = {}, LootFrame = { ScrollBox = {} }, LootFrame_Update = fn,
        ContainerFrame1Item1 = { IconBorder = {}, NewItemTexture = {}, UpgradeIcon = {} },
        Enum = { EditModeSystem = { ChatFrame = 2, MicroMenu = 10, Minimap = 11, AuraFrame = 12,
            ObjectiveTracker = 13 },
            EditModeActionBarSetting = { HideBarArt = 6 } },
        MainStatusTrackingBarContainer = {}, BagsBar = {},
        MainActionBar = { EndCaps = {} }, MainMenuBar = { EndCaps = {} },
        MainMenuBarArtFrame = { LeftEndCap = {} }, MainMenuBarLeftEndCap = {},
    } })
    out = run(addon, printed, "check")
    for i, path in ipairs(PROBES) do
        check(("probe: %s present"):format(path), out[n + i], ("Probe: %s present"):format(path))
    end
    check("probe: a present button does not ready the feature", addon.Check.Ready("Upgrade borders"), false)

    addon, printed = loadWithDB(nil, "enUS", { env = { ContainerFrame1Item1 = explode } })
    out = run(addon, printed, "check")
    check("probe: a raising lookup is missing", out[n + 4], "Probe: ContainerFrame1Item1.IconBorder missing")
    check("check: Has never raises", addon.Check.Has("ContainerFrame1Item1.UpgradeIcon"), false)

    local zh, zhPrinted = loadWithDB(nil, "zhTW")
    out = run(zh, zhPrinted, "check")
    check("zhTW check: upgrade borders line", lineFor(out, "升級邊框"):match("^(升級邊框)："), "升級邊框")
    check("zhTW check: probe line", out[n + 1], "探測：LootButton1 缺少")
    zh, zhPrinted = loadWithDB(nil, "zhTW", { env = { LootButton1 = {} } })
    check("zhTW check: present probe", run(zh, zhPrinted, "check")[n + 1], "探測：LootButton1 存在")
end

-- Layout, XP bar, bag button and Shaman area gates in /tandem check (stage 12, unit 1).

do
    local addon, printed = loadWithDB(nil, "enUS", { env = checkAPIs() })
    local byName = runCheck(addon, printed)
    check("check: layout line", byName["Layout"], "Layout: ok (C_EditMode.GetLayouts ok, C_EditMode.SaveLayouts ok, "
        .. "C_EditMode.SetActiveLayout ok, EditModeManagerFrame ok, "
        .. "EditModePresetLayoutManager.GetCopyOfPresetLayouts ok, "
        .. "MainActionBar ok, MainMenuBar missing)")
    check("check: xp bar line", byName["XP bar"], "XP bar: ok (UnitXP ok, UnitXPMax ok)")
    check("check: bag button line", byName["Bag button"],
        "Bag button: ok (C_Container.GetContainerNumFreeSlots ok, GetContainerNumFreeSlots missing, ToggleAllBags ok)")
    check("check: shaman area line", byName["Shaman area"],
        "Shaman area: ok (GetTotemInfo ok, UnitPower ok)")

    local fn = function() end
    local env = checkAPIs()
    env.MainActionBar, env.MainMenuBar = nil, {}
    env.C_Container = { GetContainerNumSlots = fn, GetContainerItemID = fn }
    env.GetContainerNumFreeSlots = fn
    addon = loadWithDB(nil, "enUS", { env = env })
    check("layout: ready with the classic MainMenuBar", addon.Check.Ready("Layout"), true)
    check("bag button: ready with the global free-slot API", addon.Check.Ready("Bag button"), true)

    for _, case in ipairs({
        { "Layout", "C_EditMode" }, { "Layout", "EditModeManagerFrame" }, { "Layout", "MainActionBar" },
        { "Layout", "EditModePresetLayoutManager" },
        { "XP bar", "UnitXPMax" }, { "Bag button", "ToggleAllBags" }, { "Shaman area", "GetTotemInfo" },
        { "Shaman area", "UnitPower" },
    }) do
        env = checkAPIs()
        env[case[2]] = nil
        addon = loadWithDB(nil, "enUS", { env = env })
        check(("%s: not ready without %s"):format(case[1], case[2]), addon.Check.Ready(case[1]), false)
    end

    local zh, zhPrinted = loadWithDB(nil, "zhTW", { env = checkAPIs() })
    local out = run(zh, zhPrinted, "check")
    check("zhTW check: layout line", lineFor(out, "介面配置"):match("^(.-)：可用"), "介面配置")
    check("zhTW check: xp bar line", lineFor(out, "經驗條"), "經驗條：可用（UnitXP 可用, UnitXPMax 可用）")
    check("zhTW check: bag button line", lineFor(out, "背包按鈕"):match("^(.-)：可用"), "背包按鈕")
    check("zhTW check: shaman area line", lineFor(out, "薩滿區"),
        "薩滿區：可用（GetTotemInfo 可用, UnitPower 可用）")
end

-- /tandem weights (stage 7, unit 6): show, spec, set and reset.

-- Loads the addon as a level 60 Tom-Realm warrior with no talent API; ctx.class, ctx.className, ctx.level,
-- ctx.combat and ctx.name change the player. Returns ctx with ctx.run(msg) -> printed lines.
local function loadWeights(locale, db)
    local ctx = { class = "WARRIOR", className = "Warrior", level = 60, name = "Tom" }
    local addon, printed, env = loadWithDB(db, locale or "enUS", { env = {
        UnitClass = function()
            return ctx.className, ctx.class
        end,
        UnitLevel = function()
            return ctx.level
        end,
        UnitName = function()
            return ctx.name
        end,
        GetRealmName = function()
            return "Realm"
        end,
        InCombatLockdown = function()
            return ctx.combat == true
        end,
    } })
    ctx.addon, ctx.env = addon, env
    function ctx.run(msg)
        return run(addon, printed, msg)
    end
    return ctx
end

local ARMS = "str 1, agi 0.6, sta 0.5, armor 0.01, dps 3, ap 0.5, hit 10, crit 10"

do
    local ctx = loadWeights()
    local out = ctx.run("weights")
    check("weights: shows the active tree", out[1], "Tandem: Arms Warrior weights, tree 1 (auto)")
    check("weights: lists the weights in stat key order", out[2], ARMS)
    check("weights: no own weight, no legend", #out, 2)
    check("weights: the command writes nothing", ctx.env.TandemDB.weights["Tom-Realm"], nil)

    out = ctx.run("weights spec 2")
    check("weights spec 2: confirms", out[1], "Tandem: weights use tree 2")
    check("weights spec 2: shows the chosen tree", out[2], "Tandem: Fury Warrior weights, tree 2 (manual)")
    check("weights spec 2: saves the spec", ctx.env.TandemDB.weights["Tom-Realm"].spec, 2)

    out = ctx.run("weights set hit 20")
    check("weights set: confirms", out[1], "Tandem: hit weight set to 20")
    check("weights set: marks the own weight", out[3],
        "str 1, agi 0.7, sta 0.5, armor 0.01, dps 3, ap 0.5, hit 20*, crit 11")
    check("weights set: prints the legend", out[4], "  * your own weight; /tandem weights reset drops them")
    check("weights set: saves on the active tree", ctx.env.TandemDB.weights["Tom-Realm"].overrides[2].hit, 20)
    out = ctx.run("weights set sta 0")
    check("weights set 0: shows the ignored stat", out[3]:match("sta [^,]*"), "sta 0*")
    out = ctx.run("weights set sp 0.25")
    check("weights set: a stat without a built-in is added", out[3]:match("sp [^,]*"), "sp 0.25*")
    check("weights set: a negative number", ctx.run("weights set spi -1")[1], "Tandem: spi weight set to -1")
    check("weights set: a leading point", ctx.run("weights set int .5")[1], "Tandem: int weight set to 0.5")

    out = ctx.run("weights reset")
    check("weights reset: confirms", out[1], "Tandem: own weights for tree 2 dropped")
    check("weights reset: shows the built-ins", out[3],
        "str 1, agi 0.7, sta 0.5, armor 0.01, dps 3, ap 0.5, hit 12, crit 11")
    check("weights reset: no legend", #out, 3)

    out = ctx.run("weights spec auto")
    check("weights spec auto: confirms", out[1], "Tandem: weights follow your talents")
    check("weights spec auto: back to the default tree", out[2], "Tandem: Arms Warrior weights, tree 1 (auto)")
    check("weights spec auto: clears the saved spec", ctx.env.TandemDB.weights["Tom-Realm"].spec, nil)
    check("weights: SPECS names the trees", ctx.addon.Weights.SPECS.WARRIOR[1], "Arms")

    local before = ctx.run("weights")
    for _, msg in ipairs({ "weights spec", "weights spec 0", "weights spec 4", "weights spec x", "weights spec 1 2",
                           "weights set", "weights set str", "weights set str x", "weights set str 1 2",
                           "weights set str 1e3", "weights set str 0x10", "weights reset now", "weights dance" }) do
        out = ctx.run(msg)
        check(("%q prints the weights usage"):format(msg), out[1] .. "|" .. #out,
            "Tandem: usage /tandem weights [spec <1|2|3|auto> | set <stat> <number> | reset]|1")
    end
    out = ctx.run("weights set fire 2")
    check("weights set: an unknown stat is named", out[1], "Tandem: unknown stat fire; use one of: "
        .. table.concat(ctx.addon.Store.STAT_KEYS, " "))
    check("weights set: an unknown stat prints one line", #out, 1)
    check("weights: refusals change nothing", table.concat(ctx.run("weights"), "|"), table.concat(before, "|"))

    ctx.combat = true
    for _, msg in ipairs({ "weights", "weights spec 2", "weights set str 2", "weights reset", "weights x" }) do
        out = ctx.run(msg)
        check(("%q refuses in combat"):format(msg), out[1] .. "|" .. #out, "Tandem: not available in combat|1")
    end
    check("weights in combat: nothing saved", ctx.env.TandemDB.weights["Tom-Realm"].spec, nil)
    ctx.combat = false

    ctx.class, ctx.className = "MONK", "Monk"
    check("weights: a class without built-ins", ctx.run("weights")[1], "Tandem: no built-in weights for Monk")
    ctx.class = nil
    check("weights: an unknown class", ctx.run("weights spec 2")[1],
        "Tandem: your class or level is not known yet; try again in a moment")
    ctx.class, ctx.className, ctx.name = "MAGE", "Mage", ""
    out = ctx.run("weights spec 1")
    check("weights: an unknown character cannot save", out[1] .. "|" .. #out,
        "Tandem: weights cannot be saved: recording is off or your character is not known yet|1")
    check("weights: an unknown character still sees the built-ins", ctx.run("weights")[1],
        "Tandem: Frost Mage weights, tree 3 (auto)")
end

do
    local ctx = loadWeights("enUS", { schemaVersion = 99 })
    check("weights on a newer db: set is refused", ctx.run("weights set str 2")[1],
        "Tandem: weights cannot be saved: recording is off or your character is not known yet")
    check("weights on a newer db: the db is untouched", ctx.env.TandemDB.weights, nil)
end

do
    local ctx = loadWeights("zhTW")
    local out = ctx.run("weights set str 2")
    check("zhTW weights set line", out[1], "Tandem：str 的權重設為 2")
    check("zhTW weights header", out[2], "Tandem：武器Warrior的屬性權重，第 1 系（自動）")
    check("zhTW weights legend", out[4], "  * 你自訂的權重；/tandem weights reset 可刪除")
    check("zhTW weights usage", ctx.run("weights x")[1],
        "Tandem：用法 /tandem weights [spec <1|2|3|auto> | set <屬性> <數字> | reset]")
end

-- SpellRanks: red/yellow state per action slot from spellbook ranks and trainer data.

local RANKED = {
    [116] = { "Frostbolt", 1 }, [205] = { "Frostbolt", 2 }, [837] = { "Frostbolt", 3 },
    [133] = { "Fireball", 1 }, [143] = { "Fireball", 2 },
    [1459] = { "Arcane Intellect" }, [2139] = { "Counterspell" },
}

-- Loads the addon as a mage with ctx.known[spellID] learned (all in the spellbook), ctx.bar[slot] = { kind, id }
-- for GetActionInfo and ctx.level. opts.book: "modern" (C_SpellBook, default), "legacy" (GetNumSpellTabs) or "none";
-- opts.legacySpell uses GetSpellInfo/GetSpellSubtext instead of C_Spell; opts.widgets goes to loadAddon,
-- opts.env adds globals. ctx.env and ctx.fire are loadAddon's.
local function loadSpellRanks(opts)
    opts = opts or {}
    local ctx = { known = {}, bar = {}, level = 60 }
    local function book()
        local ranked = {}
        for id in pairs(RANKED) do
            ranked[#ranked + 1] = id
        end
        table.sort(ranked)
        local learned = {}
        for _, id in ipairs(ranked) do
            if ctx.known[id] then
                learned[#learned + 1] = id
            end
        end
        return learned
    end
    local function subtext(id)
        local s = RANKED[id]
        return s and (s[2] and ("Rank " .. s[2]) or "") or nil
    end
    local env = {
        UnitClass = function()
            return "Mage", "MAGE"
        end,
        UnitLevel = function()
            return ctx.level
        end,
        GetActionInfo = function(slot)
            local a = ctx.bar[slot]
            if a then
                return a[1], a[2]
            end
        end,
        IsSpellKnown = function(id)
            return ctx.known[id] == true
        end,
    }
    if opts.legacySpell then
        env.GetSpellInfo = function(id)
            return RANKED[id] and RANKED[id][1]
        end
        env.GetSpellSubtext = subtext
    else
        env.C_Spell = {
            GetSpellInfo = function(id)
                return RANKED[id] and { name = RANKED[id][1] }
            end,
            GetSpellSubtext = subtext,
        }
    end
    if (opts.book or "modern") == "modern" then
        env.Enum = { SpellBookSpellBank = { Player = 0 }, SpellBookItemType = { Spell = 1, FutureSpell = 2 } }
        env.C_SpellBook = {
            GetNumSpellBookSkillLines = function()
                return 2
            end,
            GetSpellBookSkillLineInfo = function(line)
                return line == 1 and { itemIndexOffset = 0, numSpellBookItems = 0 }
                    or { itemIndexOffset = 0, numSpellBookItems = #book() + 1 }
            end,
            GetSpellBookItemInfo = function(index)
                local id = book()[index]
                if id then
                    return { itemType = 1, spellID = id }
                end
                return { itemType = 2, spellID = 837 }
            end,
        }
    elseif opts.book == "legacy" then
        env.BOOKTYPE_SPELL = "spell"
        env.GetNumSpellTabs = function()
            return 1
        end
        env.GetSpellTabInfo = function()
            return "General", "icon", 0, #book() + 1
        end
        env.GetSpellBookItemInfo = function(index, bank)
            local id = book()[index]
            if bank ~= "spell" then
                return nil
            end
            if id then
                return "SPELL", id
            end
            return "FUTURESPELL", 837
        end
    end
    for k, v in pairs(opts.env or {}) do
        env[k] = v
    end
    local addon, _, fullEnv, fire = loadWithDB(nil, "enUS",
        { env = env, widgets = opts.widgets })
    ctx.addon, ctx.Store, ctx.env, ctx.fire = addon, addon.Store, fullEnv, fire
    function ctx.state(slot)
        addon.SpellRanks.Invalidate()
        return tostring(addon.SpellRanks.State(slot))
    end
    return ctx
end

do
    local ctx = loadSpellRanks()
    ctx.known[116], ctx.known[205] = true, true
    ctx.bar[1], ctx.bar[2] = { "spell", 116 }, { "spell", 205 }
    check("spell ranks: a lower rank with a higher one known is red", ctx.state(1), "red")
    check("spell ranks: the highest known rank without trainer data is none", ctx.state(2), "nil")
    ctx.Store.SetTrainerSpell("MAGE", 837, 14, 3)
    ctx.level = 14
    check("spell ranks: the next rank trainable at the player's level is yellow", ctx.state(2), "yellow")
    ctx.level = 13
    check("spell ranks: the next rank above the player's level is none", ctx.state(2), "nil")
    ctx.level = 14
    check("spell ranks: red wins over yellow", ctx.state(1), "red")
    ctx.known[837] = true
    check("spell ranks: a learned next rank is not yellow", ctx.state(2), "red")
    ctx.bar[3] = { "spell", 837 }
    check("spell ranks: the highest rank learned is none", ctx.state(3), "nil")
    ctx.bar[4], ctx.bar[5], ctx.bar[6] = { "macro", 1 }, { "item", 2589 }, nil
    check("spell ranks: a macro is none", ctx.state(4), "nil")
    check("spell ranks: an item is none", ctx.state(5), "nil")
    check("spell ranks: an empty slot is none", ctx.state(6), "nil")
    ctx.bar[7] = { "spell", "21CB4" }
    check("spell ranks: a non-numeric id is none", ctx.state(7), "nil")
    ctx.bar[8] = { "spell", secret() }
    check("spell ranks: a secret id is none", ctx.state(8), "nil")
    ctx.known[1459] = true
    ctx.bar[9] = { "spell", 1459 }
    check("spell ranks: a rankless spell without a trainer next rank is none", ctx.state(9), "nil")
    ctx.known[133] = true
    ctx.Store.SetTrainerSpell("MAGE", 143, 6)
    ctx.bar[10] = { "spell", 133 }
    check("spell ranks: a trainer spell without a recorded rank uses its subtext", ctx.state(10), "yellow")
end

do
    local ctx = loadSpellRanks()
    ctx.known[116] = true
    ctx.bar[1] = { "spell", 116 }
    ctx.addon.SpellRanks.Invalidate()
    check("spell ranks: state is cached until invalidated", tostring(ctx.addon.SpellRanks.State(1)), "nil")
    ctx.known[205] = true
    check("spell ranks: the cache keeps the old ranks", tostring(ctx.addon.SpellRanks.State(1)), "nil")
    ctx.addon.SpellRanks.Invalidate()
    check("spell ranks: invalidating reads the new ranks", tostring(ctx.addon.SpellRanks.State(1)), "red")
end

do
    local ctx = loadSpellRanks()
    ctx.Store.SetTrainerSpell("WARRIOR", 205, 8, 2)
    ctx.known[116] = true
    ctx.bar[1] = { "spell", 116 }
    check("spell ranks: another class's trainer data is none", ctx.state(1), "nil")
end

do
    local ctx = loadSpellRanks({ book = "legacy", legacySpell = true })
    ctx.known[116], ctx.known[205] = true, true
    ctx.bar[1] = { "spell", 116 }
    check("spell ranks: the legacy spellbook and spell API make red", ctx.state(1), "red")
    ctx.Store.SetTrainerSpell("MAGE", 837, 14, 3)
    ctx.bar[2] = { "spell", 205 }
    check("spell ranks: the legacy spellbook makes yellow", ctx.state(2), "yellow")
end

do
    local ctx = loadSpellRanks({ book = "none" })
    ctx.known[116], ctx.known[205] = true, true
    ctx.Store.SetTrainerSpell("MAGE", 837, 14, 3)
    ctx.bar[1], ctx.bar[2] = { "spell", 116 }, { "spell", 205 }
    local ok, got = pcall(ctx.state, 1)
    check("spell ranks: no spellbook API is none without errors", tostring(ok) .. " " .. got, "true nil")
    ok, got = pcall(ctx.state, 2)
    check("spell ranks: no spellbook API is never yellow", tostring(ok) .. " " .. got, "true nil")
end

do
    local ctx = loadSpellRanks({ env = { UnitClass = function()
            return "Mage", secret()
        end, issecretvalue = function(v)
            return getmetatable(v) == SECRET_MT
        end } })
    ctx.Store.SetTrainerSpell("MAGE", 205, 8, 2)
    ctx.known[116] = true
    ctx.bar[1] = { "spell", 116 }
    local ok, got = pcall(ctx.state, 1)
    check("spell ranks: a secret class token is none without errors", tostring(ok) .. " " .. tostring(got), "true nil")
end

-- ActionBorders: red/yellow borders on fake default action buttons from SpellRanks state (stage 8, unit 5).

function WIDGET.SetVertexColor(w, r, g, b) w.color = { r, g, b } end
function WIDGET.SetBlendMode(w, mode) w.blend = mode end

-- Loads loadSpellRanks with fake buttons: ActionButton1-12 (button.action = i), MultiBarBottomLeftButton1-12 (slot
-- from ActionButton_GetPagedID, 60 + i) and MultiBarRightButton1-12 (slot from button:GetPagedID(), 24 + i).
-- opts.multi5 adds MultiBar5Button1-12 (slot 72 + i); opts.noAPI drops GetActionInfo; opts.timer adds a C_Timer
-- whose After calls wait in ctx.timers until ctx.nextFrame() runs them; ctx.combat drives InCombatLockdown.
-- ctx.border(name) returns "red", "yellow", "hidden" or "none" for a button; ctx.refreshes counts Refresh runs.
local function loadBorders(opts)
    opts = opts or {}
    local ui = { widgets = {} }
    local ctx
    local buttons = {}
    local env = {
        InCombatLockdown = function()
            return ctx.combat
        end,
        ActionButton_GetPagedID = function(button)
            return button.paged
        end,
    }
    local function add(name, fill)
        for i = 1, 12 do
            local b = newWidget(ui, "CheckButton", name .. i)
            fill(b, i)
            buttons[name .. i] = b
            env[name .. i] = b
        end
    end
    add("ActionButton", function(b, i) b.action = i end)
    add("MultiBarBottomLeftButton", function(b, i) b.paged = 60 + i end)
    add("MultiBarRightButton", function(b, i)
        b.GetPagedID = function()
            return 24 + i
        end
    end)
    if opts.multi5 then
        add("MultiBar5Button", function(b, i) b.action = 72 + i end)
    end
    local timers = {}
    if opts.timer then
        env.C_Timer = { After = function(_, fn)
            timers[#timers + 1] = fn
        end }
    end
    local spellOpts = { env = env, widgets = function(kind, name, parent, template)
        return newWidget(ui, kind, name, parent, template)
    end }
    ctx = loadSpellRanks(spellOpts)
    if opts.noAPI then
        ctx.env.GetActionInfo = nil
    end
    ctx.buttons, ctx.ui, ctx.timers, ctx.refreshes = buttons, ui, timers, 0
    local refresh = ctx.addon.ActionBorders.Refresh
    ctx.addon.ActionBorders.Refresh = function()
        ctx.refreshes = ctx.refreshes + 1
        refresh()
    end
    function ctx.nextFrame()
        local due = {}
        for i = #timers, 1, -1 do
            due[i], timers[i] = timers[i], nil
        end
        for _, fn in ipairs(due) do
            fn()
        end
    end
    function ctx.border(name)
        local border = buttons[name].tandemBorder
        if not border then
            return "none"
        elseif not border.shown then
            return "hidden"
        end
        local c = border.texture.color
        return (c[1] == 1 and c[2] == 0.15 and c[3] == 0.15 and "red")
            or (c[1] == 1 and c[2] == 0.82 and c[3] == 0 and "yellow") or "other"
    end
    return ctx
end

do
    local ctx = loadBorders()
    ctx.known[116], ctx.known[205] = true, true
    ctx.Store.SetTrainerSpell("MAGE", 837, 14, 3)
    ctx.level = 14
    ctx.bar[1], ctx.bar[2], ctx.bar[3] = { "spell", 116 }, { "spell", 205 }, { "macro", 1 }
    ctx.bar[61], ctx.bar[25] = { "spell", 116 }, { "spell", 205 }
    ctx.fire("PLAYER_LOGIN")
    check("borders: a red slot gets a red border", ctx.border("ActionButton1"), "red")
    check("borders: a yellow slot gets a yellow border", ctx.border("ActionButton2"), "yellow")
    check("borders: a macro slot gets no border frame", ctx.border("ActionButton3"), "none")
    check("borders: ActionButton_GetPagedID gives the slot", ctx.border("MultiBarBottomLeftButton1"), "red")
    check("borders: button:GetPagedID gives the slot", ctx.border("MultiBarRightButton1"), "yellow")
    local border = ctx.buttons.ActionButton1.tandemBorder
    check("borders: the border is a child of the button", border.parent, ctx.buttons.ActionButton1)
    check("borders: the border uses the action button glow", border.texture.texture,
        "Interface\\Buttons\\UI-ActionButton-Border")
    check("borders: the glow is additive", border.texture.blend, "ADD")
    check("borders: the button's action is unchanged", ctx.buttons.ActionButton1.action, 1)

    ctx.bar[1] = { "spell", 837 }
    ctx.known[837] = true
    ctx.fire("ACTIONBAR_SLOT_CHANGED", 1)
    check("borders: a slot change to the top rank hides the border", ctx.border("ActionButton1"), "hidden")
    check("borders: a slot change refreshes the others", ctx.border("ActionButton2"), "red")
    local frames = #ctx.ui.widgets
    ctx.fire("SPELLS_CHANGED")
    check("borders: a refresh reuses the border frames", #ctx.ui.widgets, frames)

    ctx.combat = true
    ctx.bar[3] = { "spell", 116 }
    ctx.fire("ACTIONBAR_SLOT_CHANGED", 3)
    check("borders: in combat a new red slot stays bare", ctx.border("ActionButton3"), "none")
    check("borders: in combat a border stays as it is", ctx.border("ActionButton2"), "red")
    ctx.combat = false
    ctx.fire("PLAYER_REGEN_ENABLED")
    check("borders: combat end refreshes the borders", ctx.border("ActionButton3"), "red")

    ctx.known[837] = nil
    ctx.level = 20
    ctx.fire("PLAYER_LEVEL_UP", 20)
    check("borders: a level up refreshes the borders", ctx.border("ActionButton2"), "yellow")
end

do
    local ctx = loadBorders({ noAPI = true })
    ctx.known[116], ctx.known[205] = true, true
    ctx.bar[1] = { "spell", 116 }
    local ok = pcall(ctx.fire, "PLAYER_LOGIN")
    check("borders: missing API raises nothing", ok, true)
    check("borders: missing API leaves buttons untouched", ctx.border("ActionButton1"), "none")
    check("borders: missing API makes no frames", #ctx.ui.widgets, 36)
end

do
    local ctx = loadBorders()
    ctx.env.ActionButton1 = nil
    ctx.known[116], ctx.known[205] = true, true
    ctx.bar[2] = { "spell", 116 }
    ctx.fire("PLAYER_ENTERING_WORLD")
    check("borders: no ActionButton1 leaves the bars untouched", ctx.border("ActionButton2"), "none")
end

do
    local ctx = loadBorders({ multi5 = true })
    ctx.known[116], ctx.known[205] = true, true
    ctx.bar[73] = { "spell", 116 }
    ctx.fire("ACTIONBAR_PAGE_CHANGED")
    check("borders: MultiBar5 buttons get borders when present", ctx.border("MultiBar5Button1"), "red")
    local bare = loadBorders()
    bare.known[116], bare.known[205] = true, true
    bare.bar[1] = { "spell", 116 }
    local ok = pcall(bare.fire, "UPDATE_BONUS_ACTIONBAR")
    check("borders: absent MultiBar5-7 raise nothing", ok, true)
    check("borders: absent MultiBar5-7 still draw the others", bare.border("ActionButton1"), "red")
end

do
    local ctx = loadBorders()
    ctx.known[116] = true
    ctx.bar[1] = { "spell", 116 }
    ctx.fire("PLAYER_LOGIN")
    check("borders: no next rank known, no border", ctx.border("ActionButton1"), "none")
    ctx.Store.SetTrainerSpell("MAGE", 205, 4, 2)
    ctx.fire("TRAINER_UPDATE")
    check("borders: trainer data refreshes to yellow", ctx.border("ActionButton1"), "yellow")
    ctx.known[205] = true
    ctx.fire("LEARNED_SPELL_IN_TAB")
    check("borders: learning the rank turns it red", ctx.border("ActionButton1"), "red")
    ctx.buttons.ActionButton4.action = nil
    ctx.fire("SPELLS_CHANGED")
    check("borders: a button without a slot is skipped", ctx.border("ActionButton4"), "none")
end

do
    local ctx = loadBorders({ timer = true })
    ctx.known[116], ctx.known[205] = true, true
    ctx.bar[1] = { "spell", 116 }
    for slot = 1, 20 do
        ctx.fire("ACTIONBAR_SLOT_CHANGED", slot)
    end
    check("borders: slot changes wait for the next frame", ctx.refreshes, 0)
    check("borders: twenty slot changes queue one timer", #ctx.timers, 1)
    check("borders: nothing is drawn before the next frame", ctx.border("ActionButton1"), "none")
    ctx.nextFrame()
    check("borders: twenty slot changes in one frame refresh once", ctx.refreshes, 1)
    check("borders: the deferred refresh draws", ctx.border("ActionButton1"), "red")

    ctx.fire("ACTIONBAR_PAGE_CHANGED")
    for i = 1, 12 do
        ctx.buttons["ActionButton" .. i].action = 12 + i
    end
    ctx.bar[13], ctx.bar[1] = nil, nil
    ctx.bar[14] = { "spell", 116 }
    ctx.nextFrame()
    check("borders: a page change paints the new page's slots", ctx.border("ActionButton2"), "red")
    check("borders: a page change clears the old page's border", ctx.border("ActionButton1"), "hidden")

    ctx.fire("SPELLS_CHANGED")
    ctx.combat = true
    ctx.bar[15] = { "spell", 116 }
    ctx.nextFrame()
    check("borders: a refresh that lands in combat leaves borders untouched", ctx.border("ActionButton3"), "none")
    ctx.combat = false
    ctx.fire("PLAYER_REGEN_ENABLED")
    ctx.nextFrame()
    check("borders: combat end picks up the missed refresh", ctx.border("ActionButton3"), "red")
    ctx.fire("ACTIONBAR_SLOT_CHANGED", 1)
    check("borders: a new event after the run schedules again", #ctx.timers, 1)
end

do
    local ctx = loadBorders()
    ctx.known[116], ctx.known[205] = true, true
    ctx.bar[1] = { "spell", 116 }
    ctx.fire("ACTIONBAR_SLOT_CHANGED", 1)
    check("borders: no C_Timer refreshes at once", ctx.refreshes, 1)
    check("borders: no C_Timer draws at once", ctx.border("ActionButton1"), "red")
end


-- Event registration: a client that rejects an unknown event name must not stop the load.
local EVENTS = {
    "ADDON_LOADED", "GET_ITEM_INFO_RECEIVED", "LOOT_READY", "LOOT_OPENED", "QUEST_COMPLETE", "QUEST_FINISHED",
    "TRAINER_SHOW", "TRAINER_UPDATE", "PLAYER_LOGIN", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED",
    "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED",
    "UPDATE_BONUS_ACTIONBAR", "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED",
}

-- Events only the removed loot, source, kill and browse recorders listened to.
local GONE_EVENTS = {
    "LOOT_CLOSED", "QUEST_DETAIL", "MERCHANT_SHOW", "MERCHANT_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_LOGOUT",
    "COMBAT_LOG_EVENT_UNFILTERED",
}

do
    local ok, addon, _, fireLoaded, env, _, frame = pcall(loadAddon, "enUS",
        { rejectEvents = { LEARNED_SPELL_IN_TAB = true } })
    check("events: an unknown event does not abort the load", ok, true)
    if ok then
        check("events: the rejected event is not registered", frame.registered.LEARNED_SPELL_IN_TAB, nil)
        fireLoaded()
        for _, ev in ipairs(EVENTS) do
            local want = true
            if ev == "ADDON_LOADED" then
                want = nil
            end
            check("events: still registers " .. ev, frame.registered[ev], want)
        end
        for _, ev in ipairs(GONE_EVENTS) do
            check("events: no longer registers " .. ev, frame.registered[ev], nil)
        end
        check("events: ADDON_LOADED was registered before it fired", frame.unregistered.ADDON_LOADED, true)
        check("events: ADDON_LOADED initialises TandemDB", isCurrent(env.TandemDB), true)
        check("events: Store.db set", addon.Store.db, env.TandemDB)
    end
end

do
    local _, _, _, _, _, frame = loadAddon("enUS", { rejectEvents = { LEARNED_SPELL_IN_SKILL_LINE = true } })
    check("events: an older client registers LEARNED_SPELL_IN_TAB", frame.registered.LEARNED_SPELL_IN_TAB, true)
end

do
    local ctx = loadBorders({ rejectEvents = { LEARNED_SPELL_IN_TAB = true } })
    ctx.known[116] = true
    ctx.bar[1] = { "spell", 116 }
    ctx.Store.SetTrainerSpell("MAGE", 205, 4, 2)
    ctx.fire("PLAYER_LOGIN")
    check("events: before learning the rank the border is yellow", ctx.border("ActionButton1"), "yellow")
    ctx.known[205] = true
    ctx.fire("LEARNED_SPELL_IN_SKILL_LINE")
    check("events: LEARNED_SPELL_IN_SKILL_LINE refreshes like LEARNED_SPELL_IN_TAB", ctx.border("ActionButton1"), "red")
end


-- ItemBorders: red border on default bag buttons whose item beats what is worn (stage 10, unit 2).

-- HookScript chains after the frame's script, as on a real frame; w.hooks counts the hooks per script.
function WIDGET.HookScript(w, name, fn)
    local prev = w.scripts[name]
    w.hooks = w.hooks or {}
    w.hooks[name] = (w.hooks[name] or 0) + 1
    w.scripts[name] = function(...)
        if prev then
            prev(...)
        end
        fn(...)
    end
end

-- Loads loadUpgrade with fake widgets. ctx.classic(f, bag, items, n) builds ContainerFrame<f> with the classic
-- ContainerFrame<f>Item<i> globals for slots 1..n (default #items; a nil id is an empty slot), reading bag;
-- ctx.modern(name, list) builds a frame whose EnumerateValidItems yields one button per { bag, id } with GetBagID.
-- Both are shown and fill ctx.bags.
-- opts.env adds globals; opts.timer adds a C_Timer whose After calls wait in ctx.timers until ctx.nextFrame();
-- ctx.refreshes counts ItemBorders.Bags runs. ctx.border(button) returns "red", "hidden", "none" or "other".
local function loadItemBorders(opts)
    opts = opts or {}
    local ui = { widgets = {} }
    local timers = {}
    local env = {}
    for k, v in pairs(opts.env or {}) do
        env[k] = v
    end
    if opts.timer then
        env.C_Timer = { After = function(_, fn)
            timers[#timers + 1] = fn
        end }
    end
    local ctx = loadUpgrade({ env = env, widgets = function(kind, name, parent, template)
        return newWidget(ui, kind, name, parent, template)
    end })
    ctx.ui, ctx.timers, ctx.refreshes = ui, timers, 0
    local bags = ctx.addon.ItemBorders.Bags
    ctx.addon.ItemBorders.Bags = function()
        ctx.refreshes = ctx.refreshes + 1
        bags()
    end
    local function button(slot, bag)
        local b = newWidget(ui, "Button")
        b.level = 5
        b.GetID = function()
            return slot
        end
        if bag then
            b.GetBagID = function()
                return bag
            end
        end
        return b
    end
    function ctx.classic(f, bag, items, n)
        local frame = newWidget(ui, "Frame", "ContainerFrame" .. f)
        frame.GetID = function()
            return bag
        end
        ctx.env["ContainerFrame" .. f] = frame
        ctx.bags[bag] = {}
        local buttons = {}
        for i = 1, n or #items do
            ctx.bags[bag][i] = items[i]
            buttons[i] = button(i)
            ctx.env["ContainerFrame" .. f .. "Item" .. i] = buttons[i]
        end
        return frame, buttons
    end
    function ctx.modern(name, list)
        local frame = newWidget(ui, "Frame", name)
        local buttons = {}
        for i, e in ipairs(list) do
            ctx.bags[e[1]] = ctx.bags[e[1]] or {}
            local slot = #ctx.bags[e[1]] + 1
            ctx.bags[e[1]][slot] = e[2]
            buttons[i] = button(slot, e[1])
        end
        frame.EnumerateValidItems = function()
            return ipairs(buttons)
        end
        ctx.env[name] = frame
        return frame, buttons
    end
    function ctx.nextFrame()
        local due = {}
        for i = #timers, 1, -1 do
            due[i], timers[i] = timers[i], nil
        end
        for _, fn in ipairs(due) do
            fn()
        end
    end
    function ctx.border(b)
        local border = b.tandemUpgrade
        if not border then
            return "none"
        elseif not border.shown then
            return "hidden"
        end
        local c = border.texture.color
        return (c[1] == 1 and c[2] == 0.15 and c[3] == 0.15) and "red" or "other"
    end
    return ctx
end

do
    local ctx = loadItemBorders()
    ctx.tips[1] = { "Plate Chest", ctx.strength(10) }
    local _, b = ctx.classic(1, 0, { 1 }, 1)
    ctx.bagUpdate()
    check("item borders: a higher ilvl with a lower score gets none", ctx.border(b[1]), "none")
end

do
    local ctx = loadItemBorders()
    local _, b = ctx.classic(1, 0, { 1, 4, nil, 900 }, 4)
    ctx.bagUpdate()
    check("item borders: an upgrade in a shown bag gets a red border", ctx.border(b[1]), "red")
    check("item borders: a non-upgrade gets none", ctx.border(b[2]), "none")
    check("item borders: an empty slot gets none", ctx.border(b[3]), "none")
    check("item borders: a loading item gets none", ctx.border(b[4]), "none")
    local border = b[1].tandemUpgrade
    check("item borders: the border is a child of the button", border.parent, b[1])
    check("item borders: the border sits two levels over the button", border.level, 7)
    check("item borders: the border uses the action button glow", border.texture.texture,
        "Interface\\Buttons\\UI-ActionButton-Border")
    check("item borders: the glow is additive", border.texture.blend, "ADD")
    check("item borders: the button's scripts are untouched", next(b[1].scripts), nil)
    check("item borders: the arrow falls back to the pet battle badge", border.arrow.texture,
        "Interface\\PetBattles\\BattleBar-AbilityBadge-Strong")
    check("item borders: the arrow sits in the button's top-left corner", border.arrow.points[1][1], "TOPLEFT")
    check("item borders: the arrow is anchored to the button", border.arrow.points[1][2], b[1])

    ctx.cache[900] = { "Late Plate", nil, 4, 60 }
    ctx.fire("GET_ITEM_INFO_RECEIVED", 77, true)
    check("item borders: another item's info leaves it bare", ctx.border(b[4]), "none")
    ctx.fire("GET_ITEM_INFO_RECEIVED", 900, true)
    check("item borders: info arriving later shows the border", ctx.border(b[4]), "red")

    local frames = #ctx.ui.widgets
    ctx.bagUpdate()
    check("item borders: a refresh reuses the border frames", #ctx.ui.widgets, frames)

    ctx.equipped[5] = "|Hitem:900:|h"
    ctx.fire("PLAYER_EQUIPMENT_CHANGED")
    check("item borders: an equip change that beats the item clears it", ctx.border(b[1]), "hidden")

    ctx.bags[0][4] = nil
    ctx.bagUpdate()
    check("item borders: an emptied slot hides its border", ctx.border(b[4]), "hidden")
end

do
    local ctx = loadItemBorders()
    local frame, b = ctx.classic(1, 0, { 1 })
    local _, m = ctx.modern("ContainerFrame2", { { 3, 1 }, { 3, 4 } })
    local _, hidden = ctx.classic(3, 2, { 1 })
    ctx.env.ContainerFrame3:Hide()
    local _, c = ctx.modern("ContainerFrameCombinedBags", { { 4, 1 }, { 4, 9 } })
    ctx.bagUpdate()
    check("item borders: EnumerateValidItems and GetBagID give the upgrade", ctx.border(m[1]), "red")
    check("item borders: EnumerateValidItems non-upgrade gets none", ctx.border(m[2]), "none")
    check("item borders: a hidden bag frame is skipped", ctx.border(hidden[1]), "none")
    check("item borders: the combined bags get the border", ctx.border(c[1]), "red")
    check("item borders: the combined bags non-upgrade gets none", ctx.border(c[2]), "none")
    check("item borders: the classic frame still painted", ctx.border(b[1]), "red")
    frame:Hide()
    ctx.equipped[5] = "|Hitem:900:|h"
    ctx.cache[900] = { "Late Plate", nil, 4, 60 }
    ctx.fire("PLAYER_EQUIPMENT_CHANGED")
    check("item borders: a hidden frame keeps its border until shown", ctx.border(b[1]), "red")
end

do
    local ctx = loadItemBorders()
    local _, m = ctx.modern("ContainerFrame1", { { 0, 1 } })
    ctx.bagUpdate()
    check("item borders: no bag button path is not ready", ctx.addon.Check.Ready("Upgrade borders"), false)
    check("item borders: not ready paints nothing", ctx.border(m[1]), "none")
    ctx.env.ContainerFrameCombinedBags = newWidget(ctx.ui, "Frame")
    ctx.env.ContainerFrameCombinedBags:Hide()
    ctx.bagUpdate()
    check("item borders: ready again paints", ctx.border(m[1]), "red")
    ctx.env.ContainerFrameCombinedBags = nil
    ctx.bagUpdate()
    check("item borders: not ready hides the borders it made", ctx.border(m[1]), "hidden")
end

do
    local ctx = loadItemBorders({ timer = true })
    local frame, b = ctx.classic(1, 0, { 1 })
    ctx.bagUpdate()
    ctx.fire("PLAYER_EQUIPMENT_CHANGED")
    ctx.bagUpdate()
    check("item borders: nothing painted before the next frame", ctx.border(b[1]), "none")
    check("item borders: Schedule coalesces into one timer", #ctx.timers, 1)
    ctx.nextFrame()
    check("item borders: one refresh on the next frame", ctx.refreshes, 1)
    check("item borders: the next frame paints", ctx.border(b[1]), "red")
    ctx.bagUpdate()
    check("item borders: a later event schedules again", #ctx.timers, 1)
    ctx.nextFrame()

    local combined = ctx.modern("ContainerFrameCombinedBags", {})
    ctx.fire("PLAYER_LOGIN")
    ctx.nextFrame()
    ctx.fire("PLAYER_LOGIN")
    ctx.nextFrame()
    check("item borders: OnShow hooked once per bag frame", (frame.hooks or {}).OnShow, 1)
    check("item borders: OnShow hooked once on the combined bags", (combined.hooks or {}).OnShow, 1)
    local before = ctx.refreshes
    frame:Hide()
    frame:Show()
    check("item borders: showing a bag frame schedules a refresh", #ctx.timers, 1)
    ctx.nextFrame()
    check("item borders: the shown frame is refreshed once", ctx.refreshes, before + 1)
end


do
    local ctx = loadItemBorders()
    local _, b = ctx.classic(1, 0, { 1 })
    ctx.bagUpdate()
    check("item borders: painted with C_Item", ctx.border(b[1]), "red")
    ctx.env.C_Item = nil
    ctx.addon.Upgrade.Invalidate()
    local ok = pcall(ctx.addon.ItemBorders.Bags)
    check("item borders: no C_Item raises nothing", ok, true)
    check("item borders: no C_Item hides the border", ctx.border(b[1]), "hidden")
    local _, m = ctx.modern("ContainerFrame2", { { 3, 1 } })
    ok = pcall(ctx.addon.ItemBorders.Bags)
    check("item borders: no C_Item paints nothing new", tostring(ok) .. " " .. ctx.border(m[1]), "true none")
end

do
    local ctx = loadItemBorders()
    ctx.classic(1, 0, {}, 1)
    local raising = function()
        error("boom")
    end
    local _, m = ctx.modern("ContainerFrame2", { { 3, 1 } })
    ctx.addon.Upgrade.Better = raising
    local ok = pcall(ctx.addon.ItemBorders.Bags)
    check("item borders: a raising Better raises nothing", ok, true)
    check("item borders: a raising Better counts as not better", ctx.border(m[1]), "none")
end

do
    local ctx = loadItemBorders()
    ctx.classic(1, 0, {}, 1)
    local combined, c = ctx.modern("ContainerFrameCombinedBags", { { 0, 1 } })
    combined.GetID = function()
        return 0
    end
    c[1].GetBagID = nil
    ctx.bagUpdate()
    check("item borders: a combined-bags button without GetBagID is skipped", ctx.border(c[1]), "none")
end


-- SetAtlas records the atlas name, as SetTexture records its file.
function WIDGET.SetAtlas(w, atlas) w.atlas = atlas end

do
    local ctx = loadItemBorders({ env = { C_Texture = { GetAtlasInfo = function(name)
        return name == "bags-greenarrow" and {} or nil
    end } } })
    local _, b = ctx.classic(1, 0, { 1 }, 1)
    ctx.bagUpdate()
    check("item borders: the arrow uses the bag upgrade atlas when the client has it", b[1].tandemUpgrade.arrow.atlas,
        "bags-greenarrow")
end

do
    local ctx = loadItemBorders()
    ctx.env.GameTooltip = fakeTooltip()
    local tip = ctx.env.GameTooltip
    ctx.addon.Tooltip.OnItem(tip, { id = 1 })
    local line
    for _, l in ipairs(tip.lines) do
        if l.text:find("upgrade over what you wear", 1, true) then
            line = l
        end
    end
    check("item tooltip: an upgrade gets the score line", line and line.text:match("%(score .+%)") ~= nil, true)
    check("item tooltip: the upgrade line is green", colour(line), "0.1,1,0.1")
    tip.lines = {}
    ctx.addon.Tooltip.OnItem(tip, { id = 4 })
    check("item tooltip: a non-upgrade gets no upgrade line", texts(tip):find("upgrade over", 1, true), nil)
end

-- Tooltip (stage 11, D3): only the upgrade line, on GameTooltip and ItemRefTooltip, never in combat.

-- Loads loadUpgrade with the tooltip API; ctx.text(data [, tooltip]) runs the captured post-call on a cleared
-- tooltip and returns its lines.
local function loadTooltip(locale, opts)
    opts = opts or {}
    local hooks = {}
    local env = { GameTooltip = fakeTooltip(), ItemRefTooltip = fakeTooltip(),
                  Enum = { TooltipDataType = { Item = 0 } } }
    if not opts.noAPI then
        env.TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn)
            hooks[#hooks + 1] = { kind = kind, fn = fn }
        end }
    end
    local ctx = loadUpgrade({ locale = locale, env = env })
    ctx.hooks = hooks
    function ctx.text(data, tooltip)
        tooltip = tooltip or ctx.env.GameTooltip
        tooltip.lines = {}
        hooks[1].fn(tooltip, data)
        return texts(tooltip)
    end
    return ctx
end

do
    local ctx = loadTooltip()
    check("tooltip: one post-call registered", #ctx.hooks, 1)
    check("tooltip: registered for item tooltips", ctx.hooks[1].kind, 0)
    check("tooltip: the post-call is Tooltip.OnItem", ctx.hooks[1].fn, ctx.addon.Tooltip.OnItem)
    local before = #ctx.printed
    check("tooltip: an upgrade gets only the upgrade line", ctx.text({ id = 1 }),
        "Tandem: upgrade over what you wear (score 45.0 over 30.0)")
    check("tooltip: ItemRefTooltip gets it too", ctx.text({ id = 1 }, ctx.env.ItemRefTooltip),
        "Tandem: upgrade over what you wear (score 45.0 over 30.0)")
    check("tooltip: the line does not wrap", ctx.env.ItemRefTooltip.lines[1].wrap, false)
    check("tooltip: an item the class cannot use gets nothing", ctx.text({ id = 8 }), "")
    check("tooltip: a non-upgrade gets nothing", ctx.text({ id = 4 }), "")
    check("tooltip: an item not loaded yet gets nothing", ctx.text({ id = 900 }), "")
    ctx.combat = true
    check("tooltip: nothing in combat", ctx.text({ id = 1 }), "")
    ctx.combat = false
    ctx.env.GameTooltip.forbidden = true
    check("tooltip: nothing on a forbidden tooltip", ctx.text({ id = 1 }), "")
    ctx.env.GameTooltip.forbidden = false
    check("tooltip: nothing on a shopping tooltip", ctx.text({ id = 1 }, fakeTooltip()), "")
    check("tooltip: nothing for a secret id", ctx.text({ id = secret() }), "")
    check("tooltip: nothing for secret data", ctx.text(secret()), "")
    check("tooltip: nothing without data", ctx.text(nil), "")
    for _, bad in ipairs({ 0, -1, 1.5, "1" }) do
        check("tooltip: nothing for id " .. tostring(bad), ctx.text({ id = bad }), "")
    end
    ctx.class = nil
    check("tooltip: nothing while the class is unknown", ctx.text({ id = 1 }), "")
    check("tooltip: hovering never prints", #ctx.printed, before)
end

do
    local ctx = loadTooltip("zhTW")
    check("zhTW tooltip upgrade line", ctx.text({ id = 1 }), "Tandem：比身上裝備更好（分數 45.0，高於 30.0）")
    ctx = loadTooltip(nil, { noAPI = true })
    check("tooltip: no post-call without the API", #ctx.hooks, 0)
    check("tooltip: the module still loads", type(ctx.addon.Tooltip.OnItem), "function")
    local addon = loadWithDB(nil, "enUS", { env = { Enum = {}, TooltipDataProcessor = {} } })
    check("tooltip: an API without AddTooltipPostCall is ignored", type(addon.Tooltip), "table")
end

-- Live judge (stage 11, U1): items judged from live client data only, with an empty TandemDB.

do
    local ctx = loadUpgrade()
    local db = ctx.env.TandemDB
    check("live: TandemDB has no items", db.items, nil)
    check("live: TandemDB has no stats", db.stats, nil)
    local before = dump(db)
    ctx.bagUpdate()
    check("live: an unscanned bag item is judged by live info and tooltip stats", ctx.loot(1)[1],
        upgradeLine("Chest", 1, BLUE, 45, 30))
    check("live: Better reads live data", ctx.addon.Upgrade.Better(13), true)
    check("live: QuestPick reads live data", ctx.addon.QuestPick.Pick({ 3, 1 }, "WARRIOR", 40), 2)
    check("live: TandemDB is unchanged after judging", dump(db), before)
end

do
    local ctx = loadUpgrade()
    local Items = ctx.addon.Items
    ctx.env.TandemDB.items = { [99] = { 50, 1, 4, "INVTYPE_CHEST", 4, 1 } }
    check("items: Info from the client", dump(Items.Info(1)), dump({ 45, 40, 3, "INVTYPE_CHEST", 4, 4 }))
    check("items: Info of an item not loaded is nil", Items.Info(900), nil)
    check("items: Info asks for an item not loaded", ctx.requested[900], true)
    ctx.cache[900] = { "Late Plate", nil, nil, 60 }
    check("items: Info of a loaded item without level or quality", dump(Items.Info(900)),
        dump({ 60, 1, 1, "INVTYPE_CHEST", 4, 4 }))
    check("items: Info never reads TandemDB", Items.Info(99), false)
    ctx.cache[950], ctx.items[950] = { "Potion", nil, 1, 5 }, { "INVTYPE_NON_EQUIP_IGNORE", 0, 1 }
    check("items: Info of a non-equippable item is false", Items.Info(950), false)
    check("items: Stats from the tooltip", Items.Stats(1).str, 45)
    ctx.tips[1] = { "Plate Chest", ctx.strength(5) }
    check("items: Stats are kept for the session", Items.Stats(1).str, 45)
    ctx.tips[13] = nil
    check("items: unreadable Stats are nil", Items.Stats(13), nil)
    ctx.tips[13] = { "Legs", ctx.strength(7) }
    check("items: unreadable Stats are read again", Items.Stats(13).str, 7)
    check("items: Score weighs the stats", Items.Score(13, "WARRIOR", 40), 7)
    check("items: nothing is saved", ctx.env.TandemDB.stats, nil)
end

do
    local Items = loadUpgrade().addon.Items
    local worn = { ids = { [3] = true }, ilvl = 30, list = { { id = 3, ilvl = 30, score = 30, armor = 20 } } }
    local better, over = Items.Beats(31, 0, worn)
    check("beats: a higher score wins with less armor", tostring(better) .. " " .. tostring(over), "true 30")
    check("beats: an equal score wins with more armor", Items.Beats(30, 21, worn), true)
    check("beats: an equal score and armor loses", Items.Beats(30, 20, worn), false)
    check("beats: an equal score with less armor loses", Items.Beats(30, 5, worn), false)
    check("beats: a lower score loses with more armor", Items.Beats(29, 99, worn), false)
    check("beats: an unscored item is unknown", Items.Beats(nil, 30, worn), nil)
    check("beats: an unknown worn item is unknown", Items.Beats(99, 99, { list = { { unknown = true } } }), nil)
    check("beats: an unscored worn item is unknown", Items.Beats(99, 99, { ilvl = 1, list = { { id = 3, ilvl = 1 } } }),
        nil)
    check("beats: an off hand behind a two-hander has nothing to beat",
        Items.Beats(99, 99, { list = { { ilvl = 0, score = 0 } } }), false)
    local pair = { ilvl = 10, list = { { id = 1, ilvl = 10, score = 10, armor = 30 },
                                       { id = 2, ilvl = 20, score = 10, armor = 15 } } }
    check("beats: the weakest of equal scores has less armor", Items.Beats(10, 20, pair), true)
    check("beats: ... and must still be beaten", Items.Beats(10, 15, pair), false)
    check("beats: item level never decides", Items.Beats(10, 15, { ilvl = 1, list = { { id = 1, ilvl = 1,
        score = 10, armor = 15 } } }), false)
    check("beats: an empty slot scores 0 with 0 armor", Items.Beats(0, 1, { ilvl = 0, list = { { ilvl = 0,
        score = 0, armor = 0 } } }), true)
    check("beats: nothing does not beat an empty slot", Items.Beats(0, 0, { ilvl = 0, list = { { ilvl = 0,
        score = 0, armor = 0 } } }), false)
end

do
    local ctx = loadItemBorders()
    local function add(id, cache, tip)
        ctx.items[id], ctx.cache[id], ctx.tips[id] = { "INVTYPE_CHEST", 4, 2 }, cache, tip
    end
    add(20, { "Vest", nil, 3, 35, 30 }, { "Vest", ctx.strength(30), "50 Armor" })
    add(21, { "Vest", nil, 3, 45, 20 }, { "Vest", ctx.strength(30) })
    add(22, { "Vest", nil, 3, 60, 45 }, { "Vest", ctx.strength(60) })
    add(23, { "Vest", nil, 3, 50, 1 }, { "Vest", ctx.strength(60), { "Requires Level 50", nil, RED } })
    local before = dump(ctx.env.TandemDB)
    local _, b = ctx.classic(1, 0, { 20, 4, 21, 22, 23 })
    ctx.bagUpdate()
    check("live borders: an equal score with more armor gets the border", ctx.border(b[1]), "red")
    check("live borders: an equal score and armor gets none", ctx.border(b[2]), "none")
    check("live borders: an equal score at a higher item level gets none", ctx.border(b[3]), "none")
    check("live borders: a required level not met gets none", ctx.border(b[4]), "none")
    check("live borders: a red tooltip line gets none", ctx.border(b[5]), "none")
    check("live borders: TandemDB is unchanged after painting", dump(ctx.env.TandemDB), before)
end

do
    local ctx = loadUpgrade()
    ctx.items[22], ctx.cache[22] = { "INVTYPE_CHEST", 4, 2 }, { "Vest", nil, 3, 60, 45 }
    ctx.tips[22] = { "Vest", ctx.strength(60) }
    ctx.bagUpdate()
    check("live: a required level not met prints nothing", #ctx.loot(22), 0)
    ctx.level = 45
    ctx.fire("PLAYER_LEVEL_UP", 45)
    check("live: reaching the level makes it an upgrade", ctx.addon.Upgrade.Better(22), true)
end

do
    local ctx = loadQuest({ 12, 3, 4 })
    local before = dump(ctx.env.TandemDB)
    ctx.tips[12], ctx.tips[3] = { "A", ctx.strength(9) }, { "B", ctx.strength(9) }
    ctx.tips[4] = { "C", ctx.strength(1) }
    ctx.complete()
    check("live quest pick: a tie on score marks none, whatever the item level", ctx.marked(), "")
    check("live quest pick: TandemDB is unchanged", dump(ctx.env.TandemDB), before)
end

-- ItemBorders.Loot: red border on loot window buttons (stage 10, unit 3).

local function itemLink(id)
    return "|cffffffff|Hitem:" .. id .. "::::::::60:::::|h[Item " .. id .. "]|h|r"
end

-- Loads loadItemBorders with a classic bag frame (for the gate), a shown LootFrame and GetLootSlotLink over
-- ctx.links[slot]. opts.buttons adds LootButton1-4 (button.slot = i) and a LootFrame_Update that sets each button's
-- slot to ctx.page * 4 + i; opts.box adds LootFrame.ScrollBox over ctx.frames (ctx.lootFrame(index) adds one whose
-- GetSlotIndex returns frame.index) with ScrollUtil.AddInitializedFrameCallback, or with box:RegisterCallback when
-- opts.box is "callback". ctx.hooks counts
-- hooksecurefunc / AddInitializedFrameCallback / RegisterCallback calls; ctx.init and ctx.rangeChanged hold the hooks.
local function loadLootBorders(opts)
    opts = opts or {}
    local ctx = loadItemBorders()
    ctx.classic(1, 0, {}, 1)
    ctx.links, ctx.hooks, ctx.page, ctx.frames = {}, { secure = 0, init = 0, callback = 0 }, 0, {}
    local env = ctx.env
    env.GetLootSlotLink = function(slot)
        return ctx.links[slot]
    end
    env.hooksecurefunc = function(name, fn)
        ctx.hooks.secure = ctx.hooks.secure + 1
        local orig = env[name]
        env[name] = function(...)
            orig(...)
            fn(...)
        end
    end
    env.LootFrame = newWidget(ctx.ui, "Frame", "LootFrame")
    ctx.buttons = {}
    if opts.buttons then
        for i = 1, 4 do
            local b = newWidget(ctx.ui, "Button", "LootButton" .. i)
            b.slot = i
            ctx.buttons[i] = b
            env["LootButton" .. i] = b
        end
        env.LootFrame_Update = function()
            for i, b in ipairs(ctx.buttons) do
                b.slot = ctx.page * 4 + i
            end
        end
    end
    if opts.box then
        local box = { ForEachFrame = function(_, fn)
            for _, f in ipairs(ctx.frames) do
                fn(f)
            end
        end }
        if opts.box == "callback" then
            box.RegisterCallback = function(_, event, fn, owner)
                ctx.hooks.callback = ctx.hooks.callback + 1
                ctx.rangeChanged = event == "OnDataRangeChanged" and function()
                    fn(owner)
                end
            end
        else
            env.ScrollUtil = { AddInitializedFrameCallback = function(_, fn, owner)
                ctx.hooks.init = ctx.hooks.init + 1
                ctx.init = function(frame)
                    fn(owner, frame, {})
                end
            end }
        end
        env.LootFrame.ScrollBox = box
    end
    function ctx.lootFrame(index)
        local f = newWidget(ctx.ui, "Button")
        f.index = index
        f.GetSlotIndex = function(w)
            return w.index
        end
        ctx.frames[#ctx.frames + 1] = f
        return f
    end
    return ctx
end

do
    local ctx = loadLootBorders({ buttons = true })
    local b = ctx.buttons
    ctx.links[1], ctx.links[3], ctx.links[4] = itemLink(1), itemLink(4), itemLink(1)
    ctx.links[2] = nil
    b[4]:Hide()
    ctx.fire("PLAYER_LOGIN")
    ctx.fire("LOOT_OPENED")
    check("loot borders: LOOT_OPENED registered", ctx.frame.registered.LOOT_OPENED, true)
    check("loot borders: an upgrade's loot button gets a red border", ctx.border(b[1]), "red")
    check("loot borders: a coin slot gets none", ctx.border(b[2]), "none")
    check("loot borders: a non-upgrade gets none", ctx.border(b[3]), "none")
    check("loot borders: a hidden button is skipped", ctx.border(b[4]), "none")
    check("loot borders: the border sits two levels over the button", b[1].tandemUpgrade.level, 3)
    ctx.links[5], ctx.links[7] = itemLink(4), itemLink(1)
    ctx.page = 1
    ctx.env.LootFrame_Update()
    check("loot borders: paging hides the border of the button's new non-upgrade", ctx.border(b[1]), "hidden")
    check("loot borders: paging shows the border on the button's new upgrade", ctx.border(b[3]), "red")
    ctx.fire("PLAYER_LOGIN")
    check("loot borders: LootFrame_Update hooked once", ctx.hooks.secure, 1)
    check("loot borders: LootFrame OnShow hooked once", (ctx.env.LootFrame.hooks or {}).OnShow, 1)
    ctx.page = 0
    ctx.env.LootFrame:Hide()
    ctx.env.LootFrame_Update()
    check("loot borders: a hidden loot window is not painted", ctx.border(b[1]), "hidden")
    ctx.env.LootFrame:Show()
    check("loot borders: showing the loot window repaints", ctx.border(b[1]), "red")
    ctx.links[1] = itemLink(900)
    ctx.fire("LOOT_READY")
    check("loot borders: LOOT_READY repaints; a loading item gets none", ctx.border(b[1]), "hidden")
    ctx.cache[900] = { "Late Plate", nil, 4, 60 }
    ctx.fire("GET_ITEM_INFO_RECEIVED", 900, true)
    check("loot borders: info arriving later shows it", ctx.border(b[1]), "red")
end

do
    local ctx = loadLootBorders({ box = true, buttons = true })
    local f1, f2 = ctx.lootFrame(1), ctx.lootFrame(2)
    ctx.links[1], ctx.links[2], ctx.links[3] = itemLink(1), itemLink(4), itemLink(1)
    ctx.fire("PLAYER_LOGIN")
    ctx.fire("LOOT_OPENED")
    check("loot borders: a ScrollBox upgrade frame gets a border", ctx.border(f1), "red")
    check("loot borders: a ScrollBox non-upgrade frame gets none", ctx.border(f2), "none")
    check("loot borders: the ScrollBox wins over LootButtons", ctx.border(ctx.buttons[1]), "none")
    f1.index = 2
    ctx.init(f1)
    check("loot borders: a reused frame drops the old item's border", ctx.border(f1), "hidden")
    f2.index = 3
    ctx.init(f2)
    check("loot borders: a reused frame shows the new item's border", ctx.border(f2), "red")
    f2.GetSlotIndex, f2.slot = nil, 2
    ctx.init(f2)
    check("loot borders: .slot stands in for GetSlotIndex", ctx.border(f2), "hidden")
    ctx.fire("PLAYER_LOGIN")
    check("loot borders: the element init hooked once", ctx.hooks.init, 1)
end

do
    local ctx = loadLootBorders({ box = "callback" })
    local f1 = ctx.lootFrame(1)
    ctx.links[1], ctx.links[2] = itemLink(1), itemLink(4)
    ctx.fire("PLAYER_LOGIN")
    ctx.fire("PLAYER_LOGIN")
    check("loot borders: OnDataRangeChanged hooked once", ctx.hooks.callback, 1)
    ctx.rangeChanged()
    check("loot borders: a data range change paints", ctx.border(f1), "red")
    f1.index = 2
    ctx.rangeChanged()
    check("loot borders: a data range change follows the item", ctx.border(f1), "hidden")
end

do
    local ctx = loadLootBorders({ buttons = true, box = true })
    local f1 = ctx.lootFrame(1)
    ctx.links[1] = itemLink(1)
    ctx.fire("PLAYER_LOGIN")
    ctx.env.LootFrame_Update()
    check("loot borders: painted while ready", ctx.border(ctx.buttons[1]), "none")
    check("loot borders: frame painted while ready", ctx.border(f1), "red")
    ctx.env.C_Item = nil
    local ok = pcall(ctx.env.LootFrame_Update)
    check("loot borders: no C_Item raises nothing", ok, true)
    check("loot borders: no C_Item hides the border", ctx.border(f1), "hidden")
    local f2 = ctx.lootFrame(1)
    ok = pcall(ctx.init, f2)
    check("loot borders: no C_Item paints no reused frame", tostring(ok) .. " " .. ctx.border(f2), "true none")
end

do
    local ctx = loadLootBorders({ buttons = true })
    ctx.env.ContainerFrame1Item1 = nil
    ctx.links[1] = itemLink(1)
    ctx.fire("PLAYER_LOGIN")
    local ok = pcall(ctx.env.LootFrame_Update)
    check("loot borders: gate false raises nothing", ok, true)
    check("loot borders: gate false paints nothing", ctx.border(ctx.buttons[1]), "none")
end

-- Source-aware stats (D2): worn, bag and linked items score from their own tooltip, not the bare item id's.

-- Adds the source tooltip APIs to a loadUpgrade ctx: C_TooltipInfo.GetInventoryItem over ctx.invTips[inv],
-- GetBagItem over ctx.bagTips["bag:slot"] and GetHyperlink over ctx.linkTips[link] (lists of left texts; a missing
-- entry gives no lines), and C_Container.GetContainerItemLink over ctx.bagLinks["bag:slot"]. ctx.calls counts the
-- reads per API ("inv", "bag", "link").
local function withSources(ctx)
    ctx.invTips, ctx.bagTips, ctx.linkTips, ctx.bagLinks, ctx.calls = {}, {}, {}, {}, {}
    local function data(api, list)
        ctx.calls[api] = (ctx.calls[api] or 0) + 1
        local lines = {}
        for i, text in ipairs(list or {}) do
            lines[i] = { leftText = text, leftColor = WHITE }
        end
        return { lines = lines }
    end
    local tips = ctx.env.C_TooltipInfo
    tips.GetInventoryItem = function(unit, inv)
        assert(unit == "player")
        return data("inv", ctx.invTips[inv])
    end
    tips.GetBagItem = function(bag, slot)
        return data("bag", ctx.bagTips[bag .. ":" .. slot])
    end
    tips.GetHyperlink = function(link)
        return data("link", ctx.linkTips[link])
    end
    ctx.env.C_Container.GetContainerItemLink = function(bag, slot)
        return ctx.bagLinks[bag .. ":" .. slot]
    end
    return ctx
end

local MONKEY = "|cff0070dd|Hitem:3::::::::40:::::|h[Leather Vest of the Monkey]|h|r"
local BEAR = "|cff0070dd|Hitem:3::::::::40:::::|h[Leather Vest of the Bear]|h|r"

do
    local ctx = withSources(loadUpgrade())
    local Upgrade = ctx.addon.Upgrade
    ctx.equipped[5] = MONKEY
    ctx.tips[3] = { "Leather Vest" }
    ctx.invTips[5] = { "Leather Vest of the Monkey", ctx.strength(50) }
    check("sources: a worn suffix item scores from its inventory tooltip", Upgrade.Better(1), false)
    ctx.bagLinks["0:1"] = "|cff0070dd|Hitem:1::::::::40:::::|h[Plate Chest of Strength]|h|r"
    ctx.bagTips["0:1"] = { "Plate Chest of Strength", ctx.strength(60) }
    check("sources: a bag item scores from its bag tooltip", Upgrade.Better(1, { bag = 0, slot = 1, id = 1 }), true)
    check("sources: the bare id keeps its own answer", Upgrade.Better(1), false)
end

do
    local ctx = withSources(loadUpgrade())
    ctx.equipped[5] = MONKEY
    check("sources: an inventory tooltip without lines falls back to the id's", ctx.addon.Upgrade.Better(1), true)
    check("sources: the inventory tooltip was asked first", ctx.calls.inv ~= nil, true)
end

do
    local ctx = withSources(loadUpgrade())
    local Items = ctx.addon.Items
    ctx.equipped[5] = MONKEY
    ctx.cache[3] = nil
    ctx.invTips[5] = { "Leather Vest" }
    check("sources: a worn item not loaded has no stats", Items.Stats({ inv = 5, id = 3 }), nil)
    check("sources: its slot tooltip is not read before it loads", ctx.calls.inv, nil)
    ctx.cache[3] = { "Leather Vest", nil, 3, 30 }
    ctx.invTips[5] = { "Leather Vest of the Monkey", ctx.strength(50) }
    check("sources: the loaded worn item reads its slot tooltip", statsText(Items.Stats({ inv = 5, id = 3 })), "str=50")
    ctx.equipped[5] = BEAR
    ctx.invTips[5] = { "Leather Vest of the Bear", ctx.strength(5) }
    check("sources: another item in the slot is read anew", statsText(Items.Stats({ inv = 5, id = 3 })), "str=5")
end

-- Returns the scores in upgrade lines, sorted, as "50.0,60.0".
local function lineScores(lines)
    local scores = {}
    for _, line in ipairs(lines) do
        scores[#scores + 1] = line:match("%(score ([%d.]+) over")
    end
    table.sort(scores)
    return table.concat(scores, ",")
end

do
    local ctx = withSources(loadUpgrade())
    ctx.bagUpdate()
    ctx.bagLinks["0:1"] = "|Hitem:1::::::::40:::1::|h"
    ctx.bagLinks["0:2"] = "|Hitem:1::::::::40:::2::|h"
    ctx.bagTips["0:1"] = { "Plate Chest of the Monkey", ctx.strength(20) }
    ctx.bagTips["0:2"] = { "Plate Chest of the Bear", ctx.strength(40) }
    local out = ctx.loot(1, 1)
    check("sources: two suffix variants of one id are judged apart", lineScores(out), "40.0")
    check("sources: the line names the bag item's own link", out[1],
        "Tandem: upgrade for Chest: |Hitem:1::::::::40:::2::|h (score 40.0 over 30.0)")
end

do
    local ctx = withSources(loadUpgrade())
    ctx.bagUpdate()
    ctx.equipped[5] = secret()
    check("sources: a bag item behind an unknown worn item prints nothing yet", #ctx.loot(1), 0)
    check("sources: another item is waited on", ctx.addon.Upgrade.Better(900), nil)
    ctx.equipped[5] = "|cff0070dd|Hitem:3::::::::::::::|h[Leather Vest]|h|r"
    ctx.cache[900] = { "Late Plate", nil, 4, 60 }
    local from = #ctx.printed
    ctx.fire("GET_ITEM_INFO_RECEIVED", 900, true)
    check("sources: any waiting item's info judges an untied pending item again", ctx.since(from)[1],
        upgradeLine("Chest", 1, BLUE, 45, 30))
    ctx.fire("GET_ITEM_INFO_RECEIVED", 900, true)
    check("sources: the untied item is judged once", #ctx.since(from), 1)
end

do
    local ctx = withSources(loadUpgrade())
    ctx.bagUpdate()
    ctx.bagLinks["0:1"] = "|Hitem:900::::::::40:::1::|h"
    ctx.bagLinks["0:2"] = "|Hitem:900::::::::40:::2::|h"
    ctx.bagTips["0:1"] = { "Late Plate of the Bear", ctx.strength(60) }
    ctx.bagTips["0:2"] = { "Late Plate of the Monkey", ctx.strength(50) }
    check("sources: two loading variants print nothing yet", #ctx.loot(900, 900), 0)
    ctx.cache[900] = { "Late Plate", nil, 4, 60 }
    local from = #ctx.printed
    ctx.fire("GET_ITEM_INFO_RECEIVED", 900, true)
    check("sources: one item info judges both waiting variants once", lineScores(ctx.since(from)), "50.0,60.0")
    ctx.fire("GET_ITEM_INFO_RECEIVED", 900, true)
    check("sources: the item info again prints nothing", #ctx.since(from), 2)
end

do
    local ctx = withSources(loadTooltip())
    local link = itemLink(1)
    ctx.linkTips[link] = { "Plate Chest of the Monkey", ctx.strength(20) }
    check("sources: the tooltip judges its hyperlink", ctx.text({ id = 1, hyperlink = link }), "")
    check("sources: the tooltip without a hyperlink judges the id", ctx.text({ id = 1 }),
        "Tandem: upgrade over what you wear (score 45.0 over 30.0)")
end

do
    local ctx = withSources(loadItemBorders())
    ctx.bagLinks["0:1"] = itemLink(1)
    ctx.bagTips["0:1"] = { "Plate Chest of the Monkey", ctx.strength(10) }
    local _, b = ctx.classic(1, 0, { 1, 1 }, 2)
    ctx.bagUpdate()
    check("sources: a bag border judges the slot's item", ctx.border(b[1]), "none")
    check("sources: a slot without a link falls back to the id", ctx.border(b[2]), "red")
end

do
    local ctx = withSources(loadLootBorders({ buttons = true }))
    ctx.links[1], ctx.links[2] = itemLink(1), "|cffffffff|Hitem:1::::::::60:::2::|h[Item 1]|h|r"
    ctx.linkTips[itemLink(1)] = { "Plate Chest of the Monkey", ctx.strength(10) }
    ctx.fire("PLAYER_LOGIN")
    ctx.fire("LOOT_OPENED")
    check("sources: a loot border judges the slot's link", ctx.border(ctx.buttons[1]), "none")
    check("sources: a link without lines falls back to the id", ctx.border(ctx.buttons[2]), "red")
end

-- Layout: the Tandem Edit Mode layout and /tandem layout (stage 12, U2, D2, D4).
local LAYOUT_ENUM = {
    EditModeSystem = { ActionBar = 0, UnitFrame = 3, ChatFrame = 9, StatusTrackingBar = 14 },
    EditModeStatusTrackingBarSystemIndices = { StatusTrackingBar1 = 1, StatusTrackingBar2 = 2 },
    EditModeActionBarSystemIndices = { MainBar = 1, Bar2 = 2, Bar3 = 3, RightBar1 = 4, RightBar2 = 5, ExtraBar1 = 6,
        ExtraBar2 = 7, ExtraBar3 = 8 },
    EditModeActionBarSetting = { Orientation = 0, NumRows = 1, NumIcons = 2, IconSize = 3, VisibleSetting = 5,
        HideBarArt = 6 },
    ActionBarVisibleSetting = { Always = 0, Hidden = 3 },
    EditModeUnitFrameSystemIndices = { Player = 1, Target = 2, Focus = 3 },
    EditModeLayoutType = { Preset = 0, Account = 1, Character = 2 },
    EditModeChatFrameSetting = { WidthHundreds = 0, WidthTensAndOnes = 1, HeightHundreds = 2, HeightTensAndOnes = 3 },
}

local function copyTable(v)
    if type(v) ~= "table" then
        return v
    end
    local out = {}
    for k, x in pairs(v) do
        out[k] = copyTable(x)
    end
    return out
end

-- LAYOUT_ENUM plus the micro menu, minimap and aura frame systems some clients add (D12).
local function cornerEnum()
    local e = copyTable(LAYOUT_ENUM)
    e.EditModeSystem.MicroMenu, e.EditModeSystem.Minimap, e.EditModeSystem.AuraFrame = 10, 11, 12
    e.EditModeSystem.ObjectiveTracker = 13
    e.EditModeSystem.DamageMeter = 15
    e.EditModeAuraFrameSystemIndices = { BuffFrame = 1, DebuffFrame = 2 }
    return e
end

-- A saved layout with eight action bars, three unit frames and the chat frame, all moved by the player.
local function editLayout(name, layoutType)
    local systems = {}
    local function at(x)
        return { point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", offsetX = x, offsetY = 0 }
    end
    for i = 1, 8 do
        systems[#systems + 1] = { system = 0, systemIndex = i, isInDefaultPosition = false, anchorInfo = at(i),
            anchorInfo2 = at(0), settings = { { setting = 1, value = 2 }, { setting = 3, value = 5 } } }
    end
    for i = 1, 3 do
        systems[#systems + 1] = { system = 3, systemIndex = i, isInDefaultPosition = true, anchorInfo = at(10 * i),
            settings = {} }
    end
    systems[#systems + 1] = { system = 9, systemIndex = 1, anchorInfo = at(99), settings = {} }
    for _, s in ipairs({ { 10, 1 }, { 11, 1 }, { 12, 1 }, { 12, 2 }, { 13, 1 }, { 14, 1 }, { 14, 2 }, { 15, 1 } }) do
        systems[#systems + 1] = { system = s[1], systemIndex = s[2], anchorInfo = at(99), settings = {} }
    end
    return { layoutName = name or "view", layoutType = layoutType or 1, systems = systems }
end

-- Loads the addon with a stubbed Edit Mode: state.layouts is what GetLayouts returns (copied), state.active the active
-- index (the two presets first). Frames record alpha, mouse, and every Hide/Show/SetPoint call in state.touched.
-- opts.db is TandemDB, opts.env adds globals, opts.locale the locale, opts.frames more fake Blizzard frame names,
-- opts.widgets goes to loadAddon, opts.sizes = { name = { width, height } } gives frames a size, opts.coords the
-- minimapShowPlayerCoords CVar (state.coords; absent when nil). Returns ctx with
-- addon, printed, fire, state, env, run(msg).
local function loadLayout(opts)
    opts = opts or {}
    local state = { layouts = opts.layouts or { editLayout() }, active = opts.active or 3, saved = 0, activated = {},
        combat = false, touched = {}, cvar = opts.tot or "0", coords = opts.coords, frames = {} }
    local presetList = { editLayout("Modern", 0), editLayout("Classic", 0) }
    for i = 3, opts.presets or 2 do
        presetList[i] = editLayout("Preset" .. i, 0)
    end
    local function frame(name)
        local f = { alpha = 1, mouse = true }
        function f.GetAlpha(self) return self.alpha end
        function f.SetAlpha(self, a) self.alpha = a end
        function f.IsMouseEnabled(self) return self.mouse end
        function f.EnableMouse(self, m) self.mouse = m end
        for _, method in ipairs({ "Hide", "Show", "SetPoint", "ClearAllPoints", "SetParent" }) do
            f[method] = function() state.touched[#state.touched + 1] = name .. ":" .. method end
        end
        state.frames[name] = f
        return f
    end
    local env = {
        Enum = copyTable(LAYOUT_ENUM),
        InCombatLockdown = function() return state.combat end,
        hooksecurefunc = function() state.hooked = true end,
        GetCVar = function(name)
            if name == "showTargetOfTarget" then
                return state.cvar
            end
            return name == "minimapShowPlayerCoords" and state.coords or nil
        end,
        SetCVar = function(name, v)
            if name == "showTargetOfTarget" then
                state.cvar = v
            elseif name == "minimapShowPlayerCoords" then
                state.coords = v
            end
        end,
        C_EditMode = {
            GetLayouts = function()
                return { activeLayout = state.active, layouts = copyTable(state.layouts) }
            end,
            SaveLayouts = function(info)
                state.saved = state.saved + 1
                state.savedActive = info.activeLayout
                state.layouts = copyTable(info.layouts)
            end,
            SetActiveLayout = function(i)
                state.activated[#state.activated + 1] = i
                state.active = i
            end,
        },
        EditModeManagerFrame = {
            GetActiveLayoutInfo = function()
                if state.unknown then
                    return nil
                end
                if state.active <= #presetList then
                    return copyTable(presetList[state.active])
                end
                return copyTable(state.layouts[state.active - #presetList])
            end,
        },
        EditModePresetLayoutManager = { GetCopyOfPresetLayouts = function() return copyTable(presetList) end },
    }
    for _, name in ipairs({ "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight",
        "MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7", "PlayerFrame", "TargetFrame", "ChatFrame1" }) do
        env[name] = frame(name)
    end
    for _, name in ipairs(opts.frames or {}) do
        env[name] = frame(name)
    end
    for name, size in pairs(opts.sizes or {}) do
        env[name] = env[name] or frame(name)
        env[name].GetWidth = function() return size[1] end
        env[name].GetHeight = function() return size[2] end
    end
    for k, v in pairs(opts.env or {}) do
        env[k] = v
    end
    local addon, printed, realEnv, fire, frameObj = loadWithDB(opts.db, opts.locale or "enUS",
        { env = env, rejectEvents = opts.rejectEvents, widgets = opts.widgets })
    local ctx = { addon = addon, printed = printed, fire = fire, state = state, env = realEnv, frame = frameObj }
    function ctx.run(msg)
        return table.concat(run(addon, printed, msg), "|")
    end
    return ctx
end

local function systemOf(info, system, index)
    for _, s in ipairs(info.systems) do
        if s.system == system and s.systemIndex == index then
            return s
        end
    end
end

local function anchorText(s)
    local a = s.anchorInfo
    return ("%s %s %s %s %s"):format(a.point, a.relativeTo, a.relativePoint, a.offsetX, a.offsetY)
end

local function settingOf(s, id)
    for _, row in ipairs(s.settings) do
        if row.setting == id then
            return row.value
        end
    end
end

local function savedTandem(state)
    for _, l in ipairs(state.layouts) do
        if l.layoutName == "Tandem" and l.layoutType == 1 then
            return l
        end
    end
end

-- Schema 7 (D4): a v6 db gains the layout key silently, keeping its weights and trainers.
do
    local weights = { ["Thrall-Realm"] = { spec = 2, overrides = { [2] = { str = 2.5 } } } }
    local trainers = { MAGE = { [116] = { level = 4, rank = 1 } } }
    local _, printed, env = loadWithDB({ schemaVersion = 6, weights = copyTable(weights),
        trainers = copyTable(trainers) })
    check("schema 7: v6 db migrates", env.TandemDB.schemaVersion, 7)
    check("schema 7: v6 db keeps weights, trainers, gains layout", dump(env.TandemDB),
        dump({ schemaVersion = 7, weights = weights, trainers = trainers, layout = {} }))
    check("schema 7: v6 migration prints only the load line", table.concat(printed, "|"), "Tandem loaded")
end

do
    local layout = { on = true, previous = { name = "view", type = 1 }, tot = "0" }
    local addon, printed, env = loadWithDB({ schemaVersion = 7, layout = copyTable(layout) })
    check("schema 7: a valid layout is kept", dump(env.TandemDB.layout), dump(layout))
    check("schema 7: a valid layout prints only the load line", #printed, 1)
    check("schema 7: Store.Layout reads it", addon.Store.Layout().previous.name, "view")

    printed, env = select(2, loadWithDB({ schemaVersion = 7, layout = { on = "yes", previous = { name = "", type = 1 },
        tot = 1, extra = true } }))
    check("schema 7: bad layout fields are dropped", dump(env.TandemDB.layout), "{}")
    check("schema 7: bad layout fields are counted", printed[2], "Tandem: dropped 4 invalid or unused saved entries")
    addon, printed, env = loadWithDB({ schemaVersion = 7, layout = "bad" })
    check("schema 7: a non-table layout becomes empty", dump(env.TandemDB.layout), "{}")
    check("schema 7: a non-table layout is counted", printed[2], "Tandem: dropped 1 invalid or unused saved entries")

    local Store = addon.Store
    check("SetLayout: on", Store.SetLayout("on", true) and Store.Layout().on, true)
    check("SetLayout: rejects a non-boolean on", Store.SetLayout("on", 1), false)
    check("SetLayout: rejects an unknown field", Store.SetLayout("rows", 3), false)
    check("SetLayout: rejects a 65-character name", Store.SetLayout("previous", { name = ("x"):rep(65), type = 1 }),
        false)
    check("SetLayout: rejects a fractional type", Store.SetLayout("previous", { name = "a", type = 1.5 }), false)
    local prev = { name = "a", type = 2, extra = 1 }
    Store.SetLayout("previous", prev)
    check("SetLayout: previous is copied clean", dump(Store.Layout().previous), dump({ name = "a", type = 2 }))
    check("SetLayout: nil clears", Store.SetLayout("previous", nil) and Store.Layout().previous, nil)

    local newer = loadWithDB({ schemaVersion = 8, layout = { on = true } }).Store
    check("SetLayout: a newer db is not written", newer.SetLayout("on", false), false)
    check("SetLayout: a newer db reads as off", newer.Layout().on, nil)
end

-- On and off: the Tandem layout per D2, previous by name and type, ToT CVar.
do
    local ctx = loadLayout({ layouts = { editLayout("view"), editLayout("view", 2) }, active = 4,
        frames = { "MainMenuBarLeftEndCap" } })
    local changes = {}
    ctx.addon.Layout.OnChange(function(on) changes[#changes + 1] = tostring(on) end)
    local before = #ctx.printed
    check("layout state: off at first", ctx.run("layout"), "Tandem: layout off")
    check("layout on: reply", ctx.run("layout on"), "Tandem: layout on")
    check("layout on: prints only the replies", #ctx.printed - before, 2)
    local state, Store = ctx.state, ctx.addon.Store
    check("layout on: saved once, activates presets + index", state.saved .. " " .. table.concat(state.activated, ","),
        "1 4")
    check("layout on: inserted after the account layout, before the character one",
        state.layouts[2].layoutName .. " " .. state.layouts[3].layoutType, "Tandem 2")
    check("layout on: previous by name and type", dump(Store.Layout().previous), dump({ name = "view", type = 2 }))
    check("layout on: stored on", Store.Layout().on, true)
    check("layout on: IsOn and IsActive", tostring(ctx.addon.Layout.IsOn()) .. " "
        .. tostring(ctx.addon.Layout.IsActive()), "true true")
    check("layout on: ToT CVar set", state.cvar, "1")
    check("layout on: old ToT CVar saved", Store.Layout().tot, "0")
    check("layout on: listeners told", table.concat(changes, ","), "true")
    local t = savedTandem(state)
    local main = systemOf(t, 0, 1)
    check("layout on: main bar on top of the stack", anchorText(main), "BOTTOM MultiBarBottomLeft TOP 0 2")
    check("layout on: main bar not default, one anchor", tostring(main.isInDefaultPosition) .. " "
        .. tostring(main.anchorInfo2), "false nil")
    check("layout on: main bar one row of 12", settingOf(main, 0) .. " " .. settingOf(main, 1) .. " "
        .. settingOf(main, 2), "0 1 12")
    check("layout on: other bar settings kept", settingOf(main, 3), 5)
    check("layout on: main bar art (gryphons) hidden by Edit Mode", settingOf(main, 6), 1)
    check("layout on: classic end caps faded too", ctx.state.frames.MainMenuBarLeftEndCap.alpha, 0)
    check("layout on: bar 2 on bar 3", anchorText(systemOf(t, 0, 2)), "BOTTOM MultiBarBottomRight TOP 0 2")
    check("layout on: bar 2 always shown", settingOf(systemOf(t, 0, 2), 5), 0)
    check("layout on: bar 3 at the bottom centre with XP room", anchorText(systemOf(t, 0, 3)),
        "BOTTOM UIParent BOTTOM 0 8")
    check("layout on: Blizzard's XP and reputation bars along the bottom edge", anchorText(systemOf(t, 14, 1))
        .. " | " .. anchorText(systemOf(t, 14, 2)), "BOTTOM UIParent BOTTOM 0 0 | BOTTOM UIParent BOTTOM 0 17")
    for i = 4, 8 do
        check("layout on: bar index " .. i .. " hidden by Edit Mode", settingOf(systemOf(t, 0, i), 5), 3)
    end
    check("layout on: player frame in the unit row, left of centre", anchorText(systemOf(t, 3, 1)),
        "BOTTOMRIGHT UIParent BOTTOM -120 192")
    check("layout on: target frame in the unit row, right of centre", anchorText(systemOf(t, 3, 2)),
        "BOTTOMLEFT UIParent BOTTOM 120 192")
    check("layout on: focus untouched", systemOf(t, 3, 3).isInDefaultPosition, true)
    check("layout on: chat bottom-left", anchorText(systemOf(t, 9, 1)), "BOTTOMLEFT UIParent BOTTOMLEFT 16 8")
    check("layout on: chat 380x120 by its size settings", settingOf(systemOf(t, 9, 1), 0) .. " "
        .. settingOf(systemOf(t, 9, 1), 1) .. " " .. settingOf(systemOf(t, 9, 1), 2) .. " "
        .. settingOf(systemOf(t, 9, 1), 3), "3 80 1 20")
    for _, sys in ipairs({ 10, 11, 12 }) do
        check("layout on: corner system " .. sys .. " untouched", systemOf(t, sys, 1).anchorInfo.offsetX, 99)
    end
    check("layout on: copied from the character view", state.layouts[1].systems[1].anchorInfo.offsetX, 1)
    check("layout: UnitRow is the XP room, three 40px bars, two gaps and the lift; spread 120",
        table.concat({ ctx.addon.Layout.UnitRow() }, " "), "192 120")
    check("layout state: on", ctx.run("layout"), "Tandem: layout on")

    check("layout reapply: ok", ctx.run("layout on"), "Tandem: layout on")
    check("layout reapply: replaces, keeps previous", #state.layouts .. " " .. Store.Layout().previous.type, "3 2")
    check("layout reapply: keeps the first ToT value", Store.Layout().tot, "0")

    check("layout off: reply", ctx.run("layout off"), "Tandem: layout off; your previous layout is back")
    check("layout off: the character view by name and type", state.active, 5)
    check("layout off: ToT CVar restored", state.cvar, "0")
    check("layout off: state cleared", dump(Store.Layout()), "{}")
    check("layout off: listeners told", table.concat(changes, ","), "true,true,false")
    check("layout off: Tandem kept saved", savedTandem(state) ~= nil, true)
    local n = #state.activated
    check("layout off again: nothing to restore", ctx.run("layout off") .. " " .. #state.activated - n,
        "Tandem: layout off; your previous layout is back 0")
    check("layout: no frame hidden, shown, moved or hooked", #state.touched .. " " .. tostring(state.hooked), "0 nil")
    for _, msg in ipairs({ "layout maybe", "layout on off" }) do
        check("layout: usage for " .. msg, run(ctx.addon, ctx.printed, msg)[1], "Tandem commands:")
    end
end

-- Corners (D12): micro menu, minimap and buffs move only when the client's Edit Mode has their systems; chat keeps its
-- size without the size settings.
do
    local ctx = loadLayout({ env = { Enum = cornerEnum() }, frames = { "MinimapCluster" } })
    ctx.run("layout on")
    local t = savedTandem(ctx.state)
    check("layout corners: micro menu bottom-right", anchorText(systemOf(t, 10, 1)),
        "BOTTOMRIGHT UIParent BOTTOMRIGHT -12 4")
    check("layout corners: quest tracker left where the player has it", systemOf(t, 13, 1).anchorInfo.offsetX, 99)
    check("layout corners: damage meter left where the player has it", systemOf(t, 15, 1).anchorInfo.offsetX, 99)
    check("layout: MicroRoom is the micro menu's 40px, its 4px gap and 8px clear", ctx.addon.Layout.MicroRoom(), 52)
    check("layout corners: minimap top-right", anchorText(systemOf(t, 11, 1)), "TOPRIGHT UIParent TOPRIGHT -16 -16")
    check("layout corners: buffs left of the minimap", anchorText(systemOf(t, 12, 1)),
        "TOPRIGHT MinimapCluster TOPLEFT -8 0")
    check("layout corners: debuffs untouched", systemOf(t, 12, 2).anchorInfo.offsetX, 99)
    check("layout corners: no frame moved directly", #ctx.state.touched, 0)

    ctx = loadLayout({ env = { Enum = cornerEnum() } })
    ctx.run("layout on")
    t = savedTandem(ctx.state)
    check("layout corners: buffs untouched without the minimap frame", systemOf(t, 12, 1).anchorInfo.offsetX, 99)
    check("layout corners: minimap still moved", anchorText(systemOf(t, 11, 1)), "TOPRIGHT UIParent TOPRIGHT -16 -16")

    local noMinimap = cornerEnum()
    noMinimap.EditModeSystem.Minimap = nil
    ctx = loadLayout({ env = { Enum = noMinimap }, frames = { "MinimapCluster" } })
    ctx.run("layout on")
    t = savedTandem(ctx.state)
    check("layout corners: no minimap system leaves the minimap and buffs",
        systemOf(t, 11, 1).anchorInfo.offsetX .. " " .. systemOf(t, 12, 1).anchorInfo.offsetX, "99 99")
    check("layout corners: micro menu still moved", anchorText(systemOf(t, 10, 1)),
        "BOTTOMRIGHT UIParent BOTTOMRIGHT -12 4")

    local noMicro = cornerEnum()
    noMicro.EditModeSystem.MicroMenu = nil
    ctx = loadLayout({ env = { Enum = noMicro }, sizes = { MicroMenuContainer = { 250, 30 } } })
    ctx.run("layout on")
    t = savedTandem(ctx.state)
    check("layout: no micro menu system keeps no room under the bag row", ctx.addon.Layout.MicroRoom(), 0)
    check("layout corners: no micro menu system leaves the micro menu, quest tracker and damage meter",
        systemOf(t, 10, 1).anchorInfo.offsetX .. " " .. systemOf(t, 13, 1).anchorInfo.offsetX .. " "
        .. systemOf(t, 15, 1).anchorInfo.offsetX, "99 99 99")

    local noSize = copyTable(LAYOUT_ENUM)
    noSize.EditModeChatFrameSetting = nil
    noSize.EditModeSystem.ChatFrame = nil
    ctx = loadLayout({ env = { Enum = noSize } })
    check("layout corners: no chat system still turns on", ctx.run("layout on"), "Tandem: layout on")
    check("layout corners: chat left alone", systemOf(savedTandem(ctx.state), 9, 1).anchorInfo.offsetX, 99)

    noSize = copyTable(LAYOUT_ENUM)
    noSize.EditModeChatFrameSetting = nil
    ctx = loadLayout({ env = { Enum = noSize } })
    ctx.run("layout on")
    local chat = systemOf(savedTandem(ctx.state), 9, 1)
    check("layout corners: chat moved without size settings", anchorText(chat) .. " " .. #chat.settings,
        "BOTTOMLEFT UIParent BOTTOMLEFT 16 8 0")
end

-- Narrow screens (D12, D13 fit): the chat stays beside the bars, narrows to the room left, else goes above the band
-- and the unit frames over it; the micro menu is bottom-right whatever the width.
do
    local function corners(uiWidth, measured, barWidth)
        local sizes = { UIParent = { uiWidth, 768 }, MultiBarBottomRight = barWidth and { barWidth, 40 } or nil }
        if measured then
            sizes.MultiBarBottomRight, sizes.MultiBarBottomLeft = { 500, 45 }, { 500, 45 }
            sizes.MainActionBar, sizes.PlayerFrame, sizes.TargetFrame = { 500, 45 }, { 230, 90 }, { 230, 90 }
            sizes.TargetFrameToT, sizes.MicroMenuContainer = { 90, 40 }, { 250, 40 }
        end
        local ctx = loadLayout({ env = { Enum = cornerEnum() }, sizes = sizes })
        ctx.run("layout on")
        local t = savedTandem(ctx.state)
        local chat = systemOf(t, 9, 1)
        return anchorText(chat) .. " " .. (settingOf(chat, 0) * 100 + settingOf(chat, 1)),
            anchorText(systemOf(t, 10, 1))
    end
    local chat, micro = corners(1920)
    check("layout fit 1920: chat bottom-left at full width", chat, "BOTTOMLEFT UIParent BOTTOMLEFT 16 8 380")
    check("layout fit 1920: micro menu bottom-right", micro, "BOTTOMRIGHT UIParent BOTTOMRIGHT -12 4")
    chat = corners(1366)
    check("layout fit 1366: chat keeps its full width beside the bars", chat,
        "BOTTOMLEFT UIParent BOTTOMLEFT 16 8 380")
    chat = corners(1200)
    check("layout fit 1200: chat narrowed to the room left", chat, "BOTTOMLEFT UIParent BOTTOMLEFT 16 8 327")
    chat, micro = corners(1024)
    check("layout fit 1024: chat above the band and the unit frames", chat,
        "BOTTOMLEFT UIParent BOTTOMLEFT 16 300 380")
    check("layout fit 1024: micro menu still bottom-right", micro, "BOTTOMRIGHT UIParent BOTTOMRIGHT -12 4")
    chat = corners(1366, true)
    check("layout fit measured 1366: chat beside the measured bars", chat, "BOTTOMLEFT UIParent BOTTOMLEFT 16 8 380")
    chat = corners(1200, false, 45)
    check("layout fit 1200: a narrow measured bar 3 counts as one row of 12", chat,
        "BOTTOMLEFT UIParent BOTTOMLEFT 16 8 327")
    chat = corners(1024, true)
    check("layout fit measured 1024: chat above the measured band and unit frames", chat,
        "BOTTOMLEFT UIParent BOTTOMLEFT 16 305 380")
end

do
    local ctx = loadLayout({ active = 2, tot = "1" })
    ctx.run("layout on")
    check("layout preset: previous is the preset", dump(ctx.addon.Store.Layout().previous),
        dump({ name = "Classic", type = 0 }))
    check("layout preset: ToT already on saves nothing", ctx.addon.Store.Layout().tot, nil)
    ctx.run("layout off")
    check("layout preset: off picks the preset index", ctx.state.active, 2)
    check("layout preset: ToT left on", ctx.state.cvar, "1")
end

-- Off after the player deleted or renamed a layout in Edit Mode.
do
    local ctx = loadLayout()
    ctx.run("layout on")
    ctx.state.layouts[1].layoutName = "renamed"
    ctx.run("layout off")
    check("layout fallback: a renamed previous picks the first preset", ctx.state.active, 1)
    check("layout fallback: renamed previous still restores ToT", ctx.state.cvar, "0")

    ctx = loadLayout()
    ctx.run("layout on")
    table.remove(ctx.state.layouts, 2)
    ctx.state.active = 1
    check("layout fallback: Tandem deleted, off still replies", ctx.run("layout off"),
        "Tandem: layout off; your previous layout is back")
    check("layout fallback: Tandem deleted restores the previous", ctx.state.active, 3)
    check("layout fallback: Tandem deleted restores ToT", ctx.state.cvar, "0")

    ctx = loadLayout()
    ctx.run("layout on")
    table.remove(ctx.state.layouts, 2)
    table.remove(ctx.state.layouts, 1)
    ctx.run("layout off")
    check("layout fallback: both gone pick the first preset", ctx.state.active, 1)
end

-- The per-type layout limit.
do
    local layouts = {}
    for i = 1, 5 do
        layouts[i] = editLayout("L" .. i)
    end
    local ctx = loadLayout({ layouts = layouts })
    check("layout full: reply", ctx.run("layout on"), "Tandem: no free account layout slot; delete one in Edit Mode")
    check("layout full: nothing saved, activated or stored", ctx.state.saved .. " " .. #ctx.state.activated .. " "
        .. tostring(ctx.addon.Store.Layout().on) .. " " .. ctx.state.cvar, "0 0 nil 0")
    layouts[5] = editLayout("Tandem")
    ctx = loadLayout({ layouts = copyTable(layouts) })
    check("layout full: an existing Tandem is reused", ctx.run("layout on"), "Tandem: layout on")
    check("layout full: activates the reused index", table.concat(ctx.state.activated, ",") .. " "
        .. #ctx.state.layouts, "7 5")
    ctx = loadLayout({ layouts = copyTable(layouts), env = { Constants = { EditModeConsts = {
        EditModeMaxLayoutsPerType = 4 } } } })
    check("layout full: the client's maximum is used", ctx.run("layout on"), "Tandem: layout on")
end

-- Combat: on and off wait for PLAYER_REGEN_ENABLED, with one line.
do
    local ctx = loadLayout()
    ctx.state.combat = true
    local before = #ctx.printed
    check("layout combat: on deferred", ctx.run("layout on"), "Tandem: the layout will change after combat")
    check("layout combat: nothing changed", ctx.state.saved .. " " .. #ctx.state.activated .. " "
        .. tostring(ctx.addon.Store.Layout().on), "0 0 nil")
    ctx.state.combat = false
    ctx.fire("PLAYER_REGEN_ENABLED")
    check("layout combat: applies after combat", table.concat(ctx.state.activated, ",") .. " "
        .. tostring(ctx.addon.Store.Layout().on), "4 true")
    check("layout combat: one line in all", #ctx.printed - before, 1)
    ctx.fire("PLAYER_REGEN_ENABLED")
    check("layout combat: runs once", #ctx.state.activated, 1)
    ctx.state.combat = true
    check("layout combat: off deferred", ctx.run("layout off"), "Tandem: the layout will change after combat")
    check("layout combat: still Tandem", ctx.state.active, 4)
    ctx.state.combat = false
    ctx.fire("PLAYER_REGEN_ENABLED")
    check("layout combat: restores after combat", ctx.state.active .. " " .. ctx.state.cvar, "3 0")
    ctx.state.combat = true
    ctx.run("layout on")
    ctx.run("layout off")
    ctx.state.combat = false
    ctx.fire("PLAYER_REGEN_ENABLED")
    check("layout combat: off cancels a deferred on", #ctx.state.activated, 2)
end

-- Without Edit Mode's hide-art setting, the main bar's gryphon end caps still fade and come back on off.
do
    local enumNoArt = copyTable(LAYOUT_ENUM)
    enumNoArt.EditModeActionBarSetting.HideBarArt = nil
    local ctx = loadLayout({ env = { Enum = enumNoArt } })
    local caps = { alpha = 1, mouse = true }
    function caps.GetAlpha(self) return self.alpha end
    function caps.SetAlpha(self, a) self.alpha = a end
    function caps.IsMouseEnabled(self) return self.mouse end
    function caps.EnableMouse(self, m) self.mouse = m end
    ctx.state.frames.MainActionBar.EndCaps = caps
    ctx.run("layout on")
    check("layout art: end caps faded without HideBarArt", caps.alpha, 0)
    ctx.run("layout off")
    check("layout art: end caps back on off", caps.alpha, 1)
end

-- The totem bar room (D13): a Shaman's top bar keeps Edit Mode's totem bar spot free; the rail and unit frames go above
-- it; other classes keep no room.
do
    local totem = { GetHeight = function() return 38 end }
    local ctx = loadLayout({ env = { MultiCastActionBarFrame = totem, UnitClass = function()
        return "Shaman", "SHAMAN"
    end }, sizes = { MainActionBar = { 498, 40 } } })
    check("totem room: Shaman keeps the totem bar spot above the main bar", ctx.addon.Layout.TotemRoom(), 68)
    ctx.run("layout on")
    local t = savedTandem(ctx.state)
    check("totem room: unit row above the totem bar", anchorText(systemOf(t, 3, 1)) .. " | "
        .. anchorText(systemOf(t, 3, 2)), "BOTTOMRIGHT UIParent BOTTOM -120 260 | BOTTOMLEFT UIParent BOTTOM 120 260")
    ctx = loadLayout({ env = { MultiCastActionBarFrame = totem, UnitClass = function()
        return "Mage", "MAGE"
    end } })
    check("totem room: other classes keep none", ctx.addon.Layout.TotemRoom(), 0)
    ctx = loadLayout({ env = { UnitClass = function() return "Shaman", "SHAMAN" end } })
    check("totem room: none without the totem bar", ctx.addon.Layout.TotemRoom(), 0)
end

-- The debug recorder (D13): off by default; on logs what modules pass to Debug.Log into TandemDebug; off stops
-- recording and keeps the log.
do
    local ctx = loadLayout({ env = { UIParent = {}, GetTime = function() return 12.5 end } })
    local env = ctx.env
    local Debug = ctx.addon.Debug
    check("debug: off by default", Debug.IsOn(), false)
    Debug.Log("ignored")
    check("debug: nothing logged while off", env.TandemDebug, nil)
    check("debug: on replies", ctx.run("debug on"), "Tandem: debug recording on; /reload saves it to disk")
    check("debug: on is saved", env.TandemDebug.on, true)
    Debug.Log("bags: opened")
    local log = env.TandemDebug.log
    check("debug: a line is time, combat and what", log[#log], "12.50 combat=false bags: opened")
    for _ = 1, 400 do
        Debug.Log("x")
    end
    check("debug: the log keeps the last 300 lines", #env.TandemDebug.log, 300)
    check("debug: off replies with the lines kept", ctx.run("debug off"),
        "Tandem: debug recording off (300 lines kept)")
    Debug.Log("x")
    check("debug: nothing logged after off", #env.TandemDebug.log, 300)
    check("debug: on again starts a fresh log", (ctx.run("debug on") and #env.TandemDebug.log), 1)
    check("debug: bad argument prints usage", ctx.run("debug maybe"):match("^Tandem commands:") ~= nil, true)
    ctx.env.MainStatusTrackingBarContainer = { IsShown = function() return true end,
        IsVisible = function() return true end, GetAlpha = function() return 1 end }
    local xp = { GetName = function() return "MainMenuExpBar" end, GetBottom = function() return 30 end,
        IsVisible = function() return true end }
    local high = { GetName = function() return "Minimap" end, GetBottom = function() return 700 end,
        IsVisible = function() return true end }
    ctx.env.UIParent.GetChildren = function() return xp, high end
    ctx.run("debug snap")
    local text = table.concat(env.TandemDebug.log, "\n")
    check("debug snap: watched status bar logged",
        text:match("watch MainStatusTrackingBarContainer: shown true") ~= nil, true)
    check("debug snap: a missing watched frame says so", text:match("watch ReputationWatchBar: missing") ~= nil, true)
    check("debug snap: a visible frame in the bottom band is listed", text:match("frame MainMenuExpBar: ") ~= nil, true)
    check("debug snap: a frame high on screen is not", text:match("frame Minimap") == nil, true)
    ctx.run("layout on")
    check("debug snap: a layout change takes one",
        table.concat(env.TandemDebug.log, "\n"):match("snapshot layout on.*frame MainMenuExpBar") ~= nil, true)
end

-- The snapshot's minimap probe (D11): MinimapCluster and Minimap walked breadth first to depth 6, named nodes and
-- FontStrings with text logged as mmtree lines, minimap and coordinate CVars as mmcvar lines.
local unpack = rawget(table, "unpack") or rawget(_G, "unpack")
local function probeNode(spec)
    spec.children, spec.regions = spec.children or {}, spec.regions or {}
    local n = { spec = spec }
    function n.GetName() return spec.name end
    function n.GetObjectType() return spec.kind or "Frame" end
    function n.IsShown() return spec.shown ~= false end
    function n.GetText() return spec.text end
    if spec.raises then
        n.GetChildren = function() error("forbidden") end
    else
        n.GetChildren = function() return unpack(spec.children) end
    end
    n.GetRegions = function() return unpack(spec.regions) end
    return n
end

local function probeLog(env, snap)
    env.TandemDebug = { on = true, log = {} }
    snap("debug snap")
    local out = {}
    for _, l in ipairs(env.TandemDebug.log) do
        local m = l:match("^[%d.]+ combat=%a+   (mm%a+ .*)$")
        if m then
            out[#out + 1] = m
        end
    end
    return out
end

do
    local ctx = loadLayout({ env = { UIParent = {}, GetTime = function() return 1 end } })
    local env = ctx.env
    local coords = probeNode({ kind = "FontString", text = "37.0, 43.8" })
    local deep = probeNode({ regions = { coords } })
    local minimap = probeNode({ name = "Minimap", children = { probeNode({ children = { deep } }) } })
    local container = probeNode({ name = "MinimapContainer", children = { minimap } })
    local zone = probeNode({ kind = "FontString", text = "Elwynn |cffffffffForest|r" })
    local empty = probeNode({ kind = "FontString", text = "" })
    local odd = probeNode({ name = "OddFrame", raises = true, shown = false })
    env.MinimapCluster = probeNode({ name = "MinimapCluster", children = { container, odd },
        regions = { zone, empty } })
    env.Minimap = minimap
    local log = probeLog(env, ctx.run)
    check("mm probe: the named roots, children and regions",
        table.concat(log, "\n"), table.concat({
            "mmtree MinimapCluster Frame shown true text ",
            "mmtree Minimap Frame shown true text ",
            "mmtree MinimapCluster.MinimapContainer Frame shown true text ",
            "mmtree MinimapCluster.OddFrame Frame shown false text ",
            "mmtree MinimapCluster.r1 FontString shown true text Elwynn ||cffffffffForest||r",
            "mmtree Minimap.c1.c1.r1 FontString shown true text 37.0, 43.8",
        }, "\n"))

    -- Seven levels down is past the depth cap.
    local tip = probeNode({ kind = "FontString", text = "too deep" })
    local chain = tip
    for _ = 1, 6 do
        chain = probeNode({ children = { chain } })
    end
    env.MinimapCluster, env.Minimap = probeNode({ name = "MinimapCluster", children = { chain } }), nil
    log = probeLog(env, ctx.run)
    check("mm probe: nothing past depth 6", table.concat(log, "\n"), "mmtree MinimapCluster Frame shown true text ")

    local many = {}
    for i = 1, 100 do
        many[i] = probeNode({ name = "Named" .. i })
    end
    env.MinimapCluster = probeNode({ name = "MinimapCluster", children = many })
    log = probeLog(env, ctx.run)
    check("mm probe: at most 60 lines", #log .. " " .. log[60],
        "60 mmtree MinimapCluster.Named59 Frame shown true text ")

    local wide = {}
    for i = 1, 700 do
        wide[i] = probeNode({})
    end
    wide[700] = probeNode({ kind = "FontString", text = "past the cap" })
    env.MinimapCluster = probeNode({ children = wide })
    log = probeLog(env, ctx.run)
    check("mm probe: at most 600 nodes read", #log, 0)

    env.MinimapCluster = nil
    local cvars = { minimapShowCoords = "1", rotateMinimap = "0", showCoordinates = "1", nameplateShowAll = "1" }
    env.C_CVar = { GetCVar = function(n) return cvars[n] end }
    env.C_Console = { GetAllCommands = function()
        return { { command = "minimapShowCoords" }, { command = "nameplateShowAll" }, { command = "rotateMinimap" },
            { command = "showCoordinates" } }
    end }
    log = probeLog(env, ctx.run)
    check("mm probe: C_Console CVars with coord or minimap", table.concat(log, " "),
        "mmcvar minimapShowCoords=1 mmcvar rotateMinimap=0 mmcvar showCoordinates=1")
    env.C_Console, env.C_CVar = nil, nil
    env.ConsoleGetAllCommands = function() return { "MINIMAPZoom", "fooBar" } end
    env.GetCVar = function(n) return n == "MINIMAPZoom" and "2" or nil end
    log = probeLog(env, ctx.run)
    check("mm probe: ConsoleGetAllCommands and GetCVar", table.concat(log, " "), "mmcvar MINIMAPZoom=2")
    local lots = {}
    for i = 1, 40 do
        lots[i] = { command = "coord" .. i }
    end
    env.ConsoleGetAllCommands = function() return lots end
    log = probeLog(env, ctx.run)
    check("mm probe: at most 30 CVars", #log .. " " .. log[30], "30 mmcvar coord30=nil")

    env.ConsoleGetAllCommands, env.GetCVar = nil, nil
    env.C_Console = {}
    log = probeLog(env, ctx.run)
    local tail = env.TandemDebug.log[#env.TandemDebug.log]
    check("mm probe: no minimap, no console API: no lines, the snapshot still runs",
        #log .. " " .. tostring(tail:match("watch ") ~= nil), "0 true")
end

-- Bars Edit Mode cannot hide fade instead, again after Edit Mode re-applies, and come back on off.
do
    local enumNoVisible = copyTable(LAYOUT_ENUM)
    enumNoVisible.ActionBarVisibleSetting = nil
    local ctx = loadLayout({ env = { Enum = enumNoVisible } })
    check("layout fade: EDIT_MODE_LAYOUTS_UPDATED registered", ctx.frame.registered.EDIT_MODE_LAYOUTS_UPDATED, true)
    local bar = ctx.state.frames.MultiBarRight
    ctx.fire("EDIT_MODE_LAYOUTS_UPDATED")
    check("layout fade: nothing while off", bar.alpha, 1)
    ctx.run("layout on")
    check("layout fade: faded and mouse off", bar.alpha .. " " .. tostring(bar.mouse), "0 false")
    check("layout fade: every other bar faded", ctx.state.frames.MultiBar7.alpha, 0)
    check("layout fade: the shown bars stay", ctx.state.frames.MultiBarBottomRight.alpha, 1)
    bar.alpha, bar.mouse = 1, true
    ctx.fire("EDIT_MODE_LAYOUTS_UPDATED")
    check("layout fade: re-faded on EDIT_MODE_LAYOUTS_UPDATED", bar.alpha .. " " .. tostring(bar.mouse), "0 false")
    bar.alpha = 1
    ctx.state.combat = true
    ctx.fire("EDIT_MODE_LAYOUTS_UPDATED")
    check("layout fade: not in combat", bar.alpha, 1)
    ctx.state.combat = false
    ctx.fire("PLAYER_REGEN_ENABLED")
    check("layout fade: after combat", bar.alpha, 0)
    ctx.state.frames.MultiBarLeft.alpha = 0.5
    ctx.run("layout off")
    check("layout fade: off restores alpha and mouse", bar.alpha .. " " .. tostring(bar.mouse), "1 true")
    check("layout fade: no frame hidden or hooked", #ctx.state.touched .. " " .. tostring(ctx.state.hooked), "0 nil")

    local exit
    ctx = loadLayout({ env = { Enum = copyTable(enumNoVisible), EventRegistry = {
        RegisterCallback = function(_, name, fn, owner) exit = name == "EditMode.Exit" and function() fn(owner) end end,
    } } })
    ctx.run("layout on")
    bar = ctx.state.frames.MultiBarRight
    bar.alpha = 1
    exit()
    check("layout fade: re-faded when Edit Mode closes", bar.alpha, 0)
    ctx.addon.Layout.Conceal("BagsBar")
    check("layout conceal: an unknown frame is skipped", bar.alpha, 0)

    ctx = loadLayout({ rejectEvents = { EDIT_MODE_LAYOUTS_UPDATED = true } })
    check("layout fade: an unknown event leaves the load working", ctx.run("layout on"), "Tandem: layout on")
end

-- D12: the client's minimap coordinates are hidden while the layout is on and restored when it goes off.
do
    local ctx = loadLayout({ coords = "1" })
    ctx.run("layout on")
    check("layout coords: on hides the client's coordinates", ctx.state.coords, "0")
    check("layout coords: on saves the old value", ctx.addon.Store.Layout().coords, "1")
    ctx.state.coords = "2"
    ctx.run("layout on")
    check("layout coords: reapply keeps the first value", ctx.addon.Store.Layout().coords, "1")
    ctx.run("layout off")
    check("layout coords: off restores the old value", ctx.state.coords, "1")
    check("layout coords: off clears the field", ctx.addon.Store.Layout().coords, nil)

    ctx = loadLayout({ coords = "0", layouts = { editLayout(), editLayout("Tandem") }, active = 4,
        db = { schemaVersion = 7, layout = { on = true, previous = { name = "view", type = 1 }, coords = "1" } } })
    ctx.fire("PLAYER_LOGIN")
    ctx.state.coords = "2"
    ctx.run("layout on")
    check("layout coords: a saved value survives a reload", ctx.addon.Store.Layout().coords, "1")
    ctx.run("layout off")
    check("layout coords: off after a reload restores the saved value", ctx.state.coords, "1")

    ctx = loadLayout({ coords = "1", layouts = { editLayout(), editLayout("Tandem") }, active = 4,
        db = { schemaVersion = 7, layout = { on = true, previous = { name = "view", type = 1 } } } })
    ctx.fire("PLAYER_LOGIN")
    check("layout coords: on at login hides the client's coordinates", ctx.state.coords, "0")
    check("layout coords: on at login saves the old value", ctx.addon.Store.Layout().coords, "1")
    ctx.run("layout off")
    check("layout coords: off after an on login restores the old value", ctx.state.coords, "1")

    ctx = loadLayout({ coords = "0" })
    ctx.run("layout on")
    check("layout coords: already off saves nothing", ctx.addon.Store.Layout().coords, nil)
    ctx.run("layout off")
    check("layout coords: already off stays off", ctx.state.coords, "0")

    ctx = loadLayout()
    local set = {}
    local setCVar = ctx.env.SetCVar
    ctx.env.SetCVar = function(name, v)
        set[#set + 1] = name
        setCVar(name, v)
    end
    ctx.run("layout on")
    ctx.run("layout off")
    check("layout coords: a client without the CVar is never touched", table.concat(set, ","),
        "showTargetOfTarget,showTargetOfTarget")
    check("layout coords: nothing saved without the CVar", ctx.state.coords, nil)
end

-- Relogin with the layout on re-attaches without saving again.
do
    local enumNoVisible = copyTable(LAYOUT_ENUM)
    enumNoVisible.ActionBarVisibleSetting = nil
    local ctx = loadLayout({ env = { Enum = enumNoVisible }, layouts = { editLayout(), editLayout("Tandem") },
        active = 4, db = { schemaVersion = 7, layout = { on = true, previous = { name = "view", type = 1 },
        tot = "0" } } })
    local changes = {}
    ctx.addon.Layout.OnChange(function(on) changes[#changes + 1] = tostring(on) end)
    ctx.fire("PLAYER_LOGIN")
    check("layout relogin: nothing saved or activated", ctx.state.saved .. " " .. #ctx.state.activated, "0 0")
    check("layout relogin: listeners told", table.concat(changes, ","), "true")
    check("layout relogin: bars faded again", ctx.state.frames.MultiBarRight.alpha, 0)
    check("layout relogin: previous kept", ctx.addon.Store.Layout().previous.name, "view")
    ctx.run("layout off")
    check("layout relogin: off restores the saved previous", ctx.state.active .. " " .. ctx.state.cvar, "3 0")

    ctx = loadLayout()
    local told = 0
    ctx.addon.Layout.OnChange(function() told = told + 1 end)
    ctx.fire("PLAYER_LOGIN")
    check("layout relogin: off tells nobody", told, 0)
end

-- Gate: without Edit Mode the layout stays dark.
do
    local ctx = loadLayout({ env = { MainActionBar = false, C_EditMode = false },
        db = { schemaVersion = 7, layout = { on = true } } })
    local changes = 0
    ctx.addon.Layout.OnChange(function() changes = changes + 1 end)
    ctx.fire("PLAYER_LOGIN")
    ctx.fire("EDIT_MODE_LAYOUTS_UPDATED")
    check("layout gate: login stays dark", changes, 0)
    check("layout gate: on refused", ctx.run("layout on"),
        "Tandem: the layout needs Edit Mode, which this client lacks")
    check("layout gate: nothing changed", ctx.state.cvar .. " " .. #ctx.state.activated, "0 0")
    local newer = loadLayout({ db = { schemaVersion = 8 } })
    check("layout: a newer db refuses", newer.run("layout on"),
        "Tandem: the layout cannot be saved: saved data uses a newer schema")
    local broken = loadLayout()
    broken.env.C_EditMode.SaveLayouts = function() error("bad layout") end
    check("layout error: a failing save", broken.run("layout on"), "Tandem: the layout could not be changed")
    check("layout error: nothing activated", #broken.state.activated, 0)
end

do
    local ctx = loadLayout({ locale = "zhTW" })
    check("zhTW layout on", ctx.run("layout on"), "Tandem：介面配置已開啟")
    check("zhTW layout off", ctx.run("layout off"), "Tandem：介面配置已關閉；已還原你先前的版面")
    ctx.state.combat = true
    check("zhTW layout combat", ctx.run("layout on"), "Tandem：介面配置將在戰鬥結束後變更")
end

-- Review fixes: the layout follows Edit Mode, real preset count, deferred failures, saved active index.
do
    local enumNoVisible = copyTable(LAYOUT_ENUM)
    enumNoVisible.ActionBarVisibleSetting = nil
    local ctx = loadLayout({ env = { Enum = enumNoVisible } })
    local changes = {}
    ctx.addon.Layout.OnChange(function(on) changes[#changes + 1] = tostring(on) end)
    ctx.run("layout on")
    local bar = ctx.state.frames.MultiBarRight
    local before = #ctx.printed
    ctx.state.active = 3
    ctx.fire("EDIT_MODE_LAYOUTS_UPDATED")
    check("layout sync: another active layout turns it off", tostring(ctx.addon.Layout.IsOn()), "false")
    check("layout sync: ToT and faded frames restored", ctx.state.cvar .. " " .. bar.alpha .. " "
        .. tostring(bar.mouse), "0 1 true")
    check("layout sync: listeners told off", table.concat(changes, ","), "true,false")
    check("layout sync: prints nothing, activates nothing", (#ctx.printed - before) .. " " .. #ctx.state.activated,
        "0 1")

    local exit
    ctx = loadLayout({ env = { Enum = copyTable(enumNoVisible), EventRegistry = {
        RegisterCallback = function(_, name, fn, owner) exit = name == "EditMode.Exit" and function() fn(owner) end end,
    } } })
    ctx.run("layout on")
    table.remove(ctx.state.layouts, 2)
    ctx.state.active = 1
    exit()
    check("layout sync: Tandem deleted in Edit Mode turns it off", tostring(ctx.addon.Layout.IsOn()) .. " "
        .. ctx.state.cvar .. " " .. ctx.state.frames.MultiBar5.alpha, "false 0 1")

    ctx = loadLayout({ layouts = { editLayout(), editLayout("Tandem") }, active = 3,
        db = { schemaVersion = 7, layout = { on = true, previous = { name = "view", type = 1 }, tot = "0" } } })
    ctx.state.cvar = "1"
    changes = {}
    ctx.addon.Layout.OnChange(function(on) changes[#changes + 1] = tostring(on) end)
    before = #ctx.printed
    ctx.fire("PLAYER_LOGIN")
    check("layout relogin: another layout active turns it off", tostring(ctx.addon.Layout.IsOn()) .. " "
        .. ctx.state.cvar .. " " .. table.concat(changes, ","), "false 0 false")
    check("layout relogin: off silently, nothing activated", (#ctx.printed - before) .. " " .. #ctx.state.activated,
        "0 0")

    ctx = loadLayout({ layouts = { editLayout(), editLayout("Tandem") }, active = 4,
        db = { schemaVersion = 7, layout = { on = true } } })
    changes = {}
    ctx.addon.Layout.OnChange(function(on) changes[#changes + 1] = tostring(on) end)
    ctx.state.unknown = true
    ctx.fire("PLAYER_LOGIN")
    check("layout relogin: an unknown active layout waits", tostring(ctx.addon.Layout.IsOn()) .. " "
        .. #changes, "true 0")
    ctx.state.unknown = nil
    ctx.fire("EDIT_MODE_LAYOUTS_UPDATED")
    ctx.fire("EDIT_MODE_LAYOUTS_UPDATED")
    check("layout relogin: attaches once Edit Mode knows", table.concat(changes, ","), "true")
end

do
    local tandemChar = editLayout("Tandem", 2)
    local ctx = loadLayout({ layouts = { editLayout(), tandemChar }, active = 4 })
    check("layout IsActive: a character layout named Tandem is not it", ctx.addon.Layout.IsActive(), false)
    ctx.run("layout on")
    check("layout IsActive: the account Tandem is", ctx.addon.Layout.IsActive(), true)
    check("layout insert: saved with the new Tandem active", ctx.state.savedActive .. " "
        .. table.concat(ctx.state.activated, ","), "4 4")
    ctx.run("layout on")
    check("layout replace: saved with Tandem active", ctx.state.savedActive, 4)

    ctx = loadLayout({ presets = 3, active = 4 })
    ctx.run("layout on")
    check("layout presets: three presets put the first saved layout at 4, Tandem at 5",
        table.concat(ctx.state.activated, ",") .. " " .. ctx.state.savedActive, "5 5")
    ctx.run("layout off")
    check("layout presets: off counts three presets", ctx.state.active, 4)

    ctx = loadLayout({ env = { EditModePresetLayoutManager = { GetCopyOfPresetLayouts = function() end } } })
    check("layout presets: an unknown preset list is an error", ctx.run("layout on"),
        "Tandem: the layout could not be changed")
    check("layout presets: nothing saved or activated", ctx.state.saved .. " " .. #ctx.state.activated, "0 0")
end

do
    local layouts = {}
    for i = 1, 5 do
        layouts[i] = editLayout("L" .. i)
    end
    local ctx = loadLayout({ layouts = layouts })
    ctx.state.combat = true
    ctx.run("layout on")
    ctx.state.combat = false
    local before = #ctx.printed
    ctx.fire("PLAYER_REGEN_ENABLED")
    check("layout combat: a deferred on that fails says why", table.concat(linesSince(ctx.printed, before), "|"),
        "Tandem: no free account layout slot; delete one in Edit Mode")

    ctx = loadLayout()
    ctx.state.combat = true
    ctx.run("layout on")
    ctx.state.combat = false
    ctx.env.C_EditMode = nil
    before = #ctx.printed
    ctx.fire("PLAYER_REGEN_ENABLED")
    check("layout combat: a deferred on without Edit Mode says so", table.concat(linesSince(ctx.printed, before), "|"),
        "Tandem: the layout needs Edit Mode, which this client lacks")

    ctx = loadLayout()
    ctx.run("layout on")
    ctx.state.combat = true
    ctx.run("layout off")
    ctx.state.combat = false
    before = #ctx.printed
    ctx.fire("PLAYER_REGEN_ENABLED")
    check("layout combat: a deferred off that works prints nothing", #ctx.printed - before, 0)
end

do
    local enumNoVisible = copyTable(LAYOUT_ENUM)
    enumNoVisible.ActionBarVisibleSetting = nil
    local ctx = loadLayout({ env = { Enum = enumNoVisible } })
    ctx.run("layout on")
    ctx.env.MultiBarRight = nil
    local ok = pcall(ctx.run, "layout off")
    check("layout unfade: a missing frame is skipped", tostring(ok) .. " " .. ctx.state.frames.MultiBar7.alpha .. " "
        .. ctx.state.cvar, "true 1 0")
end

do
    local _, printed = loadWithDB({ schemaVersion = 6, weights = "bad" })
    check("schema 7: a v6 db with drops still reports the upgrade", printed[2],
        "Tandem: saved data upgraded from schema 6 to 7")
end

-- Shared helpers for the frame tests below (stage 12).

-- A fake GameTooltip for the frame tests: SetText records title, AddLine records lines, Show/Hide set shown.
local function barTooltip()
    local tip = fakeTooltip()
    function tip.SetOwner(self, owner, anchor) self.owner, self.anchor, self.lines = owner, anchor, {} end
    function tip.SetText(self, text) self.title = text end
    function tip.Show(self) self.shown = true end
    function tip.Hide(self) self.shown = false end
    return tip
end

-- Returns "r,g,b" of a widget colour field rounded to two places, or "nil".
local function rgb(c)
    if not c then
        return "nil"
    end
    return ("%.2f,%.2f,%.2f"):format(c[1], c[2], c[3])
end

local function loadXP(opts)
    opts = opts or {}
    local ui = { widgets = {} }
    local xp = { xp = 1200, max = 4000, rested = 0, level = 20, cap = 60 }
    local env = {
        UnitXP = function() return xp.xp end,
        UnitXPMax = function() return xp.max end,
        GetXPExhaustion = function() return xp.rested end,
        UnitLevel = function() return xp.level end,
        GetMaxPlayerLevel = function() return xp.cap end,
        GameTooltip = barTooltip(),
        UIParent = { name = "UIParent", GetWidth = function() return 1600 end },
    }
    for k, v in pairs(opts.env or {}) do
        env[k] = v
    end
    local ctx = loadLayout({ env = env, locale = opts.locale, db = opts.db, layouts = opts.layouts,
        active = opts.active, sizes = opts.sizes,
        frames = opts.frames or { "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" },
        widgets = function(kind, name, parent, template)
            return newWidget(ui, kind, name, parent, template)
        end })
    ctx.ui, ctx.xp, ctx.tip = ui, xp, env.GameTooltip
    function ctx.bar()
        for _, w in ipairs(ui.widgets) do
            if w.kind == "StatusBar" then
                return w
            end
        end
    end
    function ctx.text()
        local b = ctx.bar()
        return b and b.text and b.text.text
    end
    return ctx
end

do
    local ctx = loadXP()
    check("xp bar: nothing made while the layout is off", (ctx.bar()), nil)
    ctx.fire("PLAYER_XP_UPDATE")
    check("xp bar: events while off are harmless", (ctx.bar()), nil)
    ctx.run("layout on")
    local bar = ctx.bar()
    check("xp bar: shown at the top centre", tostring(bar.shown) .. " " .. tostring(bar.parent == ctx.env.UIParent)
        .. " " .. #bar.points .. " " .. tostring(bar.points[1][2] == ctx.env.UIParent) .. " "
        .. bar.points[1][1] .. " " .. bar.points[1][3] .. " " .. bar.points[1][4] .. " " .. bar.points[1][5],
        "true true 1 true TOP TOP 0 -4")
    check("xp bar: 12px, 30% of the 1600 wide screen", bar.height .. " " .. bar.width, "12 480")
    local cuts = {}
    for _, w in ipairs(ctx.ui.widgets) do
        if w.kind == "Texture" and w.parent == bar and w.width == 1 then
            cuts[#cuts + 1] = w.points[1][4] .. "/" .. w.points[2][1]
        end
    end
    check("xp bar: nine 1px dividers make ten cells", table.concat(cuts, " "),
        "48/BOTTOMLEFT 96/BOTTOMLEFT 144/BOTTOMLEFT 192/BOTTOMLEFT 240/BOTTOMLEFT 288/BOTTOMLEFT 336/BOTTOMLEFT "
        .. "384/BOTTOMLEFT 432/BOTTOMLEFT")
    check("xp bar: value and max", bar.value .. " " .. bar.min .. " " .. bar.max, "1200 0 4000")
    check("xp bar: only the percent on the bar", ctx.text(), "30%")
    check("xp bar: purple without rested", rgb(bar.barColor), "0.58,0.00,0.55")
    check("xp bar: takes the mouse for its tooltip", bar.mouse, true)
    bar.scripts.OnEnter(bar)
    check("xp bar: tooltip without rested",
        ctx.tip.title .. " / " .. texts(ctx.tip) .. " / " .. tostring(ctx.tip.shown),
        "1200 / 4000 (30%) /  / true")
    bar.scripts.OnLeave(bar)
    check("xp bar: tooltip hidden on leave", ctx.tip.shown, false)
    ctx.xp.xp, ctx.xp.rested = 2480, 1000
    ctx.fire("PLAYER_XP_UPDATE")
    check("xp bar: PLAYER_XP_UPDATE updates", ctx.text(), "62%")
    check("xp bar: blue while rested", rgb(bar.barColor), "0.00,0.39,0.88")
    bar.scripts.OnEnter(bar)
    check("xp bar: tooltip with rested", ctx.tip.title .. " / " .. texts(ctx.tip), "2480 / 4000 (62%) / Rested +25%")
    ctx.xp.rested = 2000
    ctx.fire("UPDATE_EXHAUSTION")
    bar.scripts.OnEnter(bar)
    check("xp bar: UPDATE_EXHAUSTION updates the tooltip", texts(ctx.tip), "Rested +50%")
    ctx.xp.xp, ctx.xp.max, ctx.xp.rested, ctx.xp.level = 10, 5000, nil, 21
    ctx.fire("PLAYER_LEVEL_UP")
    check("xp bar: PLAYER_LEVEL_UP updates", ctx.text() .. "|" .. bar.value .. "|" .. rgb(bar.barColor),
        "0%|10|0.58,0.00,0.55")
    check("xp bar: default status bar faded", ctx.state.frames.MainStatusTrackingBarContainer.alpha .. " "
        .. tostring(ctx.state.frames.MainStatusTrackingBarContainer.mouse), "0 false")
    check("xp bar: the second (reputation) status bar faded too",
        ctx.state.frames.SecondaryStatusTrackingBarContainer.alpha, 0)
    ctx.state.frames.MainStatusTrackingBarContainer.alpha = 1
    ctx.fire("PLAYER_ENTERING_WORLD")
    check("xp bar: a status bar Blizzard shows again is faded on entering the world",
        ctx.state.frames.MainStatusTrackingBarContainer.alpha, 0)
    ctx.state.frames.MainStatusTrackingBarContainer.alpha = 1
    ctx.fire("PLAYER_XP_UPDATE")
    check("xp bar: and on an XP update", ctx.state.frames.MainStatusTrackingBarContainer.alpha, 0)
    ctx.xp.level = 59
    ctx.fire("PLAYER_LEVEL_UP", 60)
    check("xp bar: PLAYER_LEVEL_UP's level wins over a stale UnitLevel", bar.shown, false)
    ctx.xp.level = 60
    ctx.fire("PLAYER_XP_UPDATE")
    check("xp bar: hidden at the maximum level", bar.shown, false)
    ctx.xp.level = 59
    ctx.fire("PLAYER_XP_UPDATE")
    check("xp bar: back below the maximum", bar.shown, true)
    ctx.xp.max = 0
    ctx.fire("PLAYER_XP_UPDATE")
    check("xp bar: hidden when max XP is 0", bar.shown, false)
    ctx.xp.max = 5000
    ctx.run("layout off")
    check("xp bar: hidden when the layout is off", bar.shown, false)
    check("xp bar: default status bar restored", ctx.state.frames.MainStatusTrackingBarContainer.alpha .. " "
        .. tostring(ctx.state.frames.MainStatusTrackingBarContainer.mouse), "1 true")
    ctx.fire("PLAYER_XP_UPDATE")
    check("xp bar: events while off keep it hidden", bar.shown, false)
    check("xp bar: no Blizzard frame hidden or hooked", #ctx.state.touched .. " " .. tostring(ctx.state.hooked),
        "0 nil")
    ctx.run("layout on")
    check("xp bar: shown again, one bar", tostring(bar.shown) .. " " .. tostring(ctx.bar() == bar), "true true")
end

do
    local ctx = loadXP({ env = { GetMaxPlayerLevel = false, MAX_PLAYER_LEVEL = 20 } })
    ctx.run("layout on")
    check("xp bar: MAX_PLAYER_LEVEL when GetMaxPlayerLevel is missing", ctx.bar().shown, false)

    ctx = loadXP({ env = { GetMaxPlayerLevel = false } })
    ctx.run("layout on")
    check("xp bar: no level cap known still shows", ctx.bar().shown, true)

    ctx = loadXP()
    ctx.env.UnitXPMax = nil
    ctx.run("layout on")
    check("xp bar: not ready stays dark", tostring((ctx.bar())) .. " "
        .. ctx.state.frames.MainStatusTrackingBarContainer.alpha, "nil 1")

    ctx = loadXP({ frames = { "MainMenuExpBar" } })
    ctx.run("layout on")
    check("xp bar: classic MainMenuExpBar faded", ctx.state.frames.MainMenuExpBar.alpha, 0)
    ctx.run("layout off")
    check("xp bar: classic MainMenuExpBar restored", ctx.state.frames.MainMenuExpBar.alpha, 1)

    ctx = loadXP({ locale = "zhTW" })
    ctx.xp.rested = 400
    ctx.run("layout on")
    ctx.bar().scripts.OnEnter(ctx.bar())
    check("zhTW xp bar text and tooltip", ctx.text() .. " / " .. ctx.tip.title .. " / " .. texts(ctx.tip),
        "30% / 1200 / 4000 (30%) / 休息 +10%")

    ctx = loadXP({ env = { GameTooltip = false } })
    ctx.run("layout on")
    ctx.bar().scripts.OnEnter(ctx.bar())
    ctx.bar().scripts.OnLeave(ctx.bar())
    check("xp bar: no GameTooltip is harmless", ctx.bar().shown, true)

    ctx = loadXP({ layouts = { editLayout(), editLayout("Tandem") }, active = 4,
        db = { schemaVersion = 7, layout = { on = true, previous = { name = "view", type = 1 } } } })
    ctx.fire("PLAYER_LOGIN")
    check("xp bar: relogin with the layout on shows it", tostring(ctx.bar().shown) .. " " .. ctx.text(),
        "true 30%")
end

-- Map info inside the XP bar while the layout is on (stage 13, U1, U4, D3, D9).

-- Loads the layout with a fake C_Map: ctx.pos = { x, y } is the player's position on map ctx.map (nil for none);
-- ctx.tickers lists C_Timer.NewTicker calls; ctx.t is GetTime, ctx.requests counts RequestTimePlayed calls,
-- ctx.zone and ctx.subzone are the zone texts and ctx.tip is GameTooltip. ctx.xp is the XP API's state, as in
-- loadXP; ctx.bar() is the XP bar. opts.frames are the named frames the client has.
local function loadMapInfo(opts)
    opts = opts or {}
    local ui = { widgets = {} }
    local ctx
    local env = {
        UIParent = { name = "UIParent", GetWidth = function() return 1600 end },
        UnitXP = function() return ctx.xp.xp end,
        UnitXPMax = function() return ctx.xp.max end,
        GetXPExhaustion = function() return 0 end,
        UnitLevel = function() return ctx.xp.level end,
        GetMaxPlayerLevel = function() return 60 end,
        RequestTimePlayed = function() ctx.requests = ctx.requests + 1 end,
        GetTime = function() return ctx.t end,
        GetZoneText = function() return ctx.zone end,
        GetSubZoneText = function() return ctx.subzone end,
        GameTooltip = barTooltip(),
        C_Map = {
            GetBestMapForUnit = function(unit) return unit == "player" and ctx.map or nil end,
            GetPlayerMapPosition = function(map, unit)
                if map ~= ctx.map or unit ~= "player" or not ctx.pos then
                    return nil
                end
                return { GetXY = function() return ctx.pos[1], ctx.pos[2] end }
            end,
        },
        C_Timer = { NewTicker = function(interval, fn)
            local t = { interval = interval, fn = fn }
            function t.Cancel(self) self.cancelled = true end
            ctx.tickers[#ctx.tickers + 1] = t
            return t
        end },
    }
    for k, v in pairs(opts.env or {}) do
        env[k] = v
    end
    ctx = loadLayout({ env = env, locale = opts.locale, frames = opts.frames or { "MinimapCluster", "Minimap" },
        widgets = function(kind, name, parent, template)
            return newWidget(ui, kind, name, parent, template)
        end })
    ctx.ui, ctx.map, ctx.pos, ctx.tickers = ui, 1429, { 0.4231, 0.678 }, {}
    ctx.xp = { xp = 1200, max = 4000, level = 20 }
    ctx.requests, ctx.t, ctx.zone, ctx.subzone, ctx.tip = 0, 1000, "Elwynn Forest", "Goldshire", ctx.env.GameTooltip
    function ctx.line()
        for _, w in ipairs(ui.widgets) do
            if w.kind == "Frame" and w.text then
                return w
            end
        end
    end
    function ctx.text()
        local l = ctx.line()
        return l and l.text.text
    end
    function ctx.bar()
        for _, w in ipairs(ui.widgets) do
            if w.kind == "StatusBar" then
                return w
            end
        end
    end
    -- The line's parent and first point as "parent point relative relativePoint x y".
    function ctx.where()
        local l = ctx.line()
        local p = l.points[1]
        local function name(f)
            return f == ctx.bar() and "bar" or f == ctx.env.UIParent and "UIParent" or tostring(f)
        end
        return name(l.parent) .. " " .. #l.points .. " " .. p[1] .. " " .. name(p[2]) .. " " .. p[3] .. " " .. p[4]
            .. " " .. p[5]
    end
    return ctx
end

do
    local ctx = loadMapInfo()
    check("map info: nothing made while the layout is off", (ctx.line()), nil)
    ctx.fire("ZONE_CHANGED")
    check("map info: zone events while off are harmless", (ctx.line()), nil)
    ctx.run("layout on")
    local line = ctx.line()
    check("map info: shown centred just below the XP bar", tostring(line.shown) .. " " .. ctx.where(),
        "true UIParent 1 TOP bar BOTTOM 0 -2")
    check("map info: coordinates in percent, two decimals", ctx.text(), "(42.31, 67.80)")
    check("map info: one 0.5 s ticker while shown", #ctx.tickers .. " " .. ctx.tickers[1].interval, "1 0.5")
    ctx.pos = { 0.5, 0.25 }
    ctx.tickers[1].fn()
    check("map info: the ticker refreshes", ctx.text(), "(50.00, 25.00)")
    ctx.pos = nil
    ctx.fire("ZONE_CHANGED_NEW_AREA")
    check("map info: no position shows dashes", ctx.text(), "(--, --)")
    ctx.pos = { 0.1, 0.2 }
    ctx.fire("ZONE_CHANGED_INDOORS")
    check("map info: ZONE_CHANGED_INDOORS refreshes", ctx.text(), "(10.00, 20.00)")
    ctx.pos = { 0, 0 }
    ctx.fire("ZONE_CHANGED")
    check("map info: a 0,0 position shows dashes", ctx.text(), "(--, --)")
    ctx.pos, ctx.map = { 0.3, 0.3 }, nil
    ctx.fire("ZONE_CHANGED")
    check("map info: no map shows dashes", ctx.text(), "(--, --)")
    ctx.map = 1429
    ctx.run("layout off")
    check("map info: hidden when the layout is off", line.shown, false)
    check("map info: ticker stopped while hidden", tostring(ctx.tickers[1].cancelled) .. " " .. #ctx.tickers,
        "true 1")
    ctx.tickers[1].fn()
    ctx.fire("ZONE_CHANGED")
    check("map info: updates while off keep it hidden", line.shown, false)
    check("map info: no Blizzard frame touched or hooked", #ctx.state.touched .. " " .. tostring(ctx.state.hooked),
        "0 nil")
    ctx.run("layout on")
    check("map info: shown again, one line, a new ticker", tostring(line.shown) .. " "
        .. tostring(ctx.line() == line) .. " " .. #ctx.tickers .. " " .. tostring(ctx.tickers[2].cancelled),
        "true true 2 nil")
end

do
    local ctx = loadMapInfo()
    ctx.run("layout on")
    local line, bar = ctx.line(), ctx.bar()
    check("map info: above the XP bar's frame level", line.level .. " " .. bar:GetFrameLevel(), "2 1")
    check("map info: a UIParent child, not the bar's", tostring(line.parent == ctx.env.UIParent), "true")
    check("map info: the XP percent stays centred", bar.text.text .. " " .. bar.text.points[1][1] .. " "
        .. bar.text.points[1][3], "30% CENTER CENTER")
    check("map info: its own mouse area, sized to the text", tostring(line.mouse) .. " " .. line.width .. " "
        .. line.height, "true 84 12")
    ctx.fire("TIME_PLAYED_MSG", 1054800, 4800)
    check("map info: the line with /played below the bar", ctx.text() .. " | " .. ctx.where(),
        "(42.31, 67.80) · 1H20m | UIParent 1 TOP bar BOTTOM 0 -2")
    line.scripts.OnEnter(line)
    check("map info: hover on the line shows the map tooltip", tostring(ctx.tip.owner == line) .. " "
        .. ctx.tip.title, "true Elwynn Forest")
    line.scripts.OnLeave(line)
    bar.scripts.OnEnter(bar)
    check("map info: the XP tooltip still works on the bar", tostring(ctx.tip.owner == bar) .. " " .. ctx.tip.title
        .. " " .. tostring(ctx.tip.shown), "true 1200 / 4000 (30%) true")
    bar.scripts.OnLeave(bar)
    local points = 0
    local clear = line.ClearAllPoints
    line.ClearAllPoints = function(w)
        points = points + 1
        clear(w)
    end
    ctx.tickers[1].fn()
    ctx.fire("ZONE_CHANGED")
    check("map info: not re-placed while the bar's state holds", points, 0)
    ctx.xp.level = 60
    ctx.fire("PLAYER_LEVEL_UP", 60)
    check("map info: at the maximum level, at the screen's top", tostring(bar.shown) .. " " .. ctx.where()
        .. " " .. tostring(line.shown) .. " " .. points, "false UIParent 1 TOP UIParent TOP 0 -4 true 1")
    ctx.xp.level = 59
    ctx.fire("PLAYER_XP_UPDATE")
    ctx.tickers[1].fn()
    check("map info: back below the bar once it shows again", ctx.where() .. " " .. points,
        "UIParent 1 TOP bar BOTTOM 0 -2 2")
    ctx.xp.max = 0
    ctx.fire("PLAYER_XP_UPDATE")
    check("map info: an XP update that hides the bar moves the line to the screen's top", tostring(bar.shown) .. " "
        .. ctx.where() .. " " .. points, "false UIParent 1 TOP UIParent TOP 0 -4 3")
    ctx.xp.max = 4000
    ctx.fire("UPDATE_EXHAUSTION")
    check("map info: an XP update that shows the bar moves the line back", ctx.where() .. " " .. points,
        "UIParent 1 TOP bar BOTTOM 0 -2 4")
    bar:Hide()
    check("map info: the bar hiding alone leaves the line shown", tostring(line.shown), "true")
    ctx.fire("PLAYER_XP_UPDATE")
    ctx.run("layout off")
    check("map info: hidden with the layout off, the bar too", tostring(line.shown) .. " " .. tostring(bar.shown),
        "false false")
    ctx.run("layout on")
    check("map info: placed again on layout on", tostring(line.shown) .. " " .. ctx.where() .. " " .. points,
        "true UIParent 1 TOP bar BOTTOM 0 -2 5")

    ctx = loadMapInfo()
    ctx.run("layout on")
    ctx.bar().strata = "MEDIUM"
    ctx.bar().level = 5
    ctx.xp.level = 60
    ctx.fire("PLAYER_LEVEL_UP", 60)
    ctx.xp.level = 20
    ctx.fire("PLAYER_XP_UPDATE")
    check("map info: the bar's strata, a level above it", ctx.line().strata .. " " .. ctx.line().level, "MEDIUM 6")

    ctx = loadMapInfo()
    ctx.xp.level = 60
    ctx.run("layout on")
    check("map info: at the screen's top at the maximum level", ctx.where(), "UIParent 1 TOP UIParent TOP 0 -4")

    ctx = loadMapInfo()
    ctx.env.UnitXP = nil
    ctx.run("layout on")
    check("map info: at the screen's top without the XP API", tostring((ctx.bar())) .. " " .. ctx.where() .. " "
        .. ctx.text(), "nil UIParent 1 TOP UIParent TOP 0 -4 (42.31, 67.80)")

    for _, missing in ipairs({ "GetPlayerMapPosition", "RequestTimePlayed" }) do
        ctx = loadMapInfo()
        if missing == "RequestTimePlayed" then
            ctx.env.RequestTimePlayed = nil
        else
            ctx.env.C_Map[missing] = nil
        end
        ctx.run("layout on")
        check("map info: dark without " .. missing, tostring((ctx.line())) .. " " .. #ctx.tickers, "nil 0")
    end

    ctx = loadMapInfo({ env = { C_Timer = false } })
    ctx.run("layout on")
    check("map info: no C_Timer still shows", tostring(ctx.line().shown) .. " " .. ctx.text(),
        "true (42.31, 67.80)")

    ctx = loadMapInfo()
    ctx.pos = { "x", 0.5 }
    ctx.run("layout on")
    check("map info: a non-number position shows dashes", ctx.text(), "(--, --)")
end

do
    local ctx = loadMapInfo()
    ctx.env.C_Map.GetPlayerMapPosition = function() error("no map") end
    ctx.run("layout on")
    check("map info: a raising map API shows dashes", ctx.text(), "(--, --)")
    local events = {}
    for _, ev in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }) do
        events[#events + 1] = tostring(ctx.frame.registered[ev])
    end
    check("map info: zone events registered", table.concat(events, " "), "true true true")
end

do
    local ctx = loadLayout({ rejectEvents = { ZONE_CHANGED_INDOORS = true } })
    check("map info: an unknown zone event is skipped", tostring(ctx.frame.registered.ZONE_CHANGED_INDOORS) .. " "
        .. tostring(ctx.frame.registered.ZONE_CHANGED_NEW_AREA), "nil true")
end

-- /played in the map info line and its tooltip (stage 13, U2, D1, D4, D5).
do
    local S = loadMapInfo().addon.MapInfo
    local short, long = {}, {}
    for _, s in ipairs({ 0, 59, 1200, 3600, 4800, 86399, 86400, 104400, 1054800, -5 }) do
        short[#short + 1] = S.Short(s)
        long[#long + 1] = S.Played(s)
    end
    check("played: short text", table.concat(short, " "), "0m 0m 20m 1H0m 1H20m 23H59m 1d0H 1d5H 12d5H 0m")
    check("played: tooltip text", table.concat(long, ", "),
        "0m, 0m, 20m, 1h 0m, 1h 20m, 23h 59m, 1d 0h, 1d 5h, 12d 5h, 0m")
    local Z = loadMapInfo({ locale = "zhTW" }).addon.MapInfo
    check("zhTW played: tooltip text", Z.Played(1054800) .. ", " .. Z.Played(4800) .. ", " .. Z.Played(1200),
        "12天 5時, 1時 20分, 20分")
end

do
    local ctx = loadMapInfo()
    ctx.run("layout on")
    ctx.fire("PLAYER_LOGIN")
    check("played: RequestTimePlayed once at login", ctx.requests, 1)
    check("played: only coordinates before /played arrives", ctx.text(), "(42.31, 67.80)")
    local line = ctx.line()
    line.scripts.OnEnter(line)
    check("played: tooltip before /played lists zone and session", ctx.tip.anchor .. " / " .. ctx.tip.title
        .. " / " .. texts(ctx.tip), "ANCHOR_BOTTOM / Elwynn Forest / Goldshire / This session: 0m")
    ctx.t = 1600
    ctx.fire("TIME_PLAYED_MSG", 1054800, 4800)
    check("played: the line ends with this level", ctx.text(), "(42.31, 67.80) · 1H20m")
    ctx.t = 1600 + 3600
    ctx.tickers[1].fn()
    check("played: this level counts up with GetTime", ctx.text(), "(42.31, 67.80) · 2H20m")
    line.scripts.OnEnter(line)
    check("played: tooltip lists zone, played, this level and session", ctx.tip.title .. " / " .. texts(ctx.tip)
        .. " / " .. tostring(ctx.tip.shown),
        "Elwynn Forest / Goldshire / Played: 12d 6h / This level: 2h 20m / This session: 1h 10m / true")
    line.scripts.OnLeave(line)
    check("played: tooltip hidden on leave", ctx.tip.shown, false)
    ctx.fire("PLAYER_LEVEL_UP", 21)
    check("played: a level up resets this level", ctx.text(), "(42.31, 67.80) · 0m")
    ctx.t = ctx.t + 1200
    ctx.subzone = ""
    line.scripts.OnEnter(line)
    check("played: after a level up the total keeps counting, no empty subzone", texts(ctx.tip),
        "Played: 12d 6h / This level: 20m / This session: 1h 30m")
    check("played: no new RequestTimePlayed on level up", ctx.requests, 1)
    ctx.fire("PLAYER_LOGIN")
    check("played: RequestTimePlayed only once", ctx.requests, 1)
    ctx.fire("TIME_PLAYED_MSG", nil, "x")
    ctx.tickers[1].fn()
    check("played: a malformed message is ignored", ctx.text(), "(42.31, 67.80) · 20m")
    check("played: TIME_PLAYED_MSG registered, nothing hooked", tostring(ctx.frame.registered.TIME_PLAYED_MSG)
        .. " " .. tostring(ctx.state.hooked), "true nil")
end

do
    local ctx = loadMapInfo()
    ctx.env.C_Map.GetPlayerMapPosition = nil
    ctx.fire("PLAYER_LOGIN")
    check("played: no RequestTimePlayed while the gate is dark", ctx.requests, 0)

    ctx = loadMapInfo()
    ctx.env.RequestTimePlayed = function() error("throttled") end
    check("played: a raising RequestTimePlayed is harmless", (pcall(ctx.fire, "PLAYER_LOGIN")), true)

    ctx = loadMapInfo({ locale = "zhTW" })
    ctx.run("layout on")
    ctx.fire("PLAYER_LOGIN")
    ctx.fire("TIME_PLAYED_MSG", 1054800, 4800)
    local line = ctx.line()
    line.scripts.OnEnter(line)
    check("zhTW played: tooltip", texts(ctx.tip), "Goldshire / 遊玩時間：12天 5時 / 本等級：1時 20分 / 本次上線：0分")
    check("zhTW played: the line is not localized", ctx.text(), "(42.31, 67.80) · 1H20m")

    ctx = loadMapInfo({ env = { GameTooltip = false } })
    ctx.run("layout on")
    line = ctx.line()
    line.scripts.OnEnter(line)
    line.scripts.OnLeave(line)
    check("played: no GameTooltip is harmless", line.shown, true)
end

do
    local ctx = loadLayout({ rejectEvents = { TIME_PLAYED_MSG = true } })
    check("played: an unknown TIME_PLAYED_MSG is skipped", tostring(ctx.frame.registered.TIME_PLAYED_MSG) .. " "
        .. tostring(ctx.frame.registered.ZONE_CHANGED), "nil true")
end

-- Combined bags at login (B opens one window with every bag).
do
    local cvars = { combinedBags = "0" }
    local env = {
        GetCVar = function(name) return cvars[name] end,
        SetCVar = function(name, v) cvars[name] = v end,
    }
    local ctx = loadLayout({ env = env })
    ctx.fire("PLAYER_LOGIN")
    check("combined bags: turned on at login", cvars.combinedBags, "1")
    cvars.combinedBags = nil
    ctx.fire("PLAYER_LOGIN")
    check("combined bags: a client without the CVar gets none", cvars.combinedBags, nil)
    local c = { combinedBags = "0" }
    ctx = loadLayout({ env = { C_CVar = { GetCVar = function(n) return c[n] end,
        SetCVar = function(n, v) c[n] = v end } } })
    ctx.fire("PLAYER_LOGIN")
    check("combined bags: C_CVar preferred", c.combinedBags, "1")
end

-- Bag row at the bottom right while the layout is on (stage 12, U4, D5, D12).

-- Loads the layout with fake bags: ctx.bags[bag] = { total, free, family }; bag b sits in inventory slot 30 + b whose
-- texture is "icon<slot>" and is named "Bag<b>". ctx.toggled counts ToggleAllBags calls, ctx.tip is GameTooltip.
local function loadBags(opts)
    opts = opts or {}
    local ui = { widgets = {} }
    local bags = {
        [0] = { 16, 5, 0 }, [1] = { 10, 2, 0 }, [2] = { 12, 12, 0 },
    }
    local ctx
    local env = {
        C_Container = {
            GetContainerNumSlots = function(bag) return bags[bag] and bags[bag][1] or 0 end,
            GetContainerNumFreeSlots = function(bag)
                if bags[bag] then
                    return bags[bag][2], bags[bag][3]
                end
                return 0, 0
            end,
            ContainerIDToInventoryID = function(bag) return 30 + bag end,
            GetBagName = function(bag) return "Bag" .. bag end,
        },
        GetInventoryItemTexture = function(unit, slot)
            return unit == "player" and ("icon" .. slot) or nil
        end,
        ToggleAllBags = function() ctx.toggled = ctx.toggled + 1 end,
        GameTooltip = barTooltip(),
        UIParent = { name = "UIParent" },
    }
    for k, v in pairs(opts.env or {}) do
        env[k] = v
    end
    ctx = loadLayout({ env = env, locale = opts.locale, db = opts.db, layouts = opts.layouts, active = opts.active,
        frames = opts.frames or { "BagsBar" },
        widgets = function(kind, name, parent, template)
            return newWidget(ui, kind, name, parent, template)
        end })
    ctx.ui, ctx.bags, ctx.toggled, ctx.tip = ui, bags, 0, env.GameTooltip
    -- Every icon button made so far, in creation order.
    function ctx.icons()
        local out = {}
        for _, w in ipairs(ui.widgets) do
            if w.kind == "Button" and w.count then
                out[#out + 1] = w
            end
        end
        return out
    end
    function ctx.row()
        local first = ctx.icons()[1]
        return first and first.parent
    end
    -- The shown icons as "texture free/total", right to left, joined by " | ".
    function ctx.text()
        local out = {}
        for _, w in ipairs(ctx.icons()) do
            if w.shown then
                out[#out + 1] = tostring(w.icon.texture) .. " " .. tostring(w.count.text)
            end
        end
        return table.concat(out, " | ")
    end
    return ctx
end

local GENERAL_ICON = "Interface\\Icons\\INV_Misc_Bag_08"

do
    local ctx = loadBags()
    check("bag row: nothing made while the layout is off", #ctx.icons(), 0)
    ctx.fire("BAG_UPDATE_DELAYED")
    check("bag row: events while off are harmless", #ctx.icons(), 0)
    ctx.run("layout on")
    local row = ctx.row()
    check("bag row: shown at the bottom right", tostring(row.shown) .. " " .. tostring(row.parent == ctx.env.UIParent)
        .. " " .. #row.points .. " " .. table.concat({ row.points[1][1], tostring(row.points[1][2] == ctx.env.UIParent),
        row.points[1][3], row.points[1][4], row.points[1][5] }, " "), "true true 1 BOTTOMRIGHT true BOTTOMRIGHT -12 8")
    local micro = loadBags({ env = { Enum = cornerEnum() } })
    micro.run("layout on")
    check("bag row: above the micro menu in the bottom-right corner", micro.row().points[1][5], 60)
    micro.run("layout off")
    micro.run("layout on")
    check("bag row: placed again, one anchor", #micro.row().points, 1)
    check("bag row: general bags first, backpack icon, free/total across bags", ctx.text(), GENERAL_ICON .. " 19/38")
    local general = ctx.icons()[1]
    check("bag row: 28px icon, rightmost", general.width .. "x" .. general.height .. " " .. general.points[1][1] .. " "
        .. general.points[1][4], "28x28 BOTTOMRIGHT 0")
    check("bag row: count on the icon's lower edge", general.count.points[1][1] .. " " .. general.count.points[1][3],
        "BOTTOM BOTTOM")
    check("bag row: white with 10 or more free", rgb(general.count.textColor), "1.00,1.00,1.00")
    ctx.bags[3] = { 20, 7, 8 }
    ctx.bags[1][2] = 0
    ctx.fire("BAG_UPDATE_DELAYED")
    check("bag row: BAG_UPDATE_DELAYED updates; a profession bag gets its own icon", ctx.text(),
        GENERAL_ICON .. " 17/38 | icon33 7/20")
    local icons = ctx.icons()
    check("bag row: the next icon grows leftwards", icons[2].points[1][1] .. " " .. icons[2].points[1][4],
        "BOTTOMRIGHT -32")
    check("bag row: yellow under 10 free", rgb(icons[2].count.textColor), "1.00,0.82,0.00")
    ctx.bags[4] = { 14, 4, 8 }
    ctx.bags[2] = { 18, 1, 1024 }
    ctx.fire("BAG_UPDATE_DELAYED")
    check("bag row: one icon per family, in family order; same family summed", ctx.text(),
        GENERAL_ICON .. " 5/26 | icon33 11/34 | icon32 1/18")
    check("bag row: row sized to its icons", ctx.row().width .. "x" .. ctx.row().height, "92x28")
    ctx.bags[0][2] = 0
    ctx.fire("BAG_UPDATE_DELAYED")
    check("bag row: red at 0 free", rgb(ctx.icons()[1].count.textColor), "1.00,0.10,0.10")
    ctx.bags[0][2] = 5
    ctx.bags[2], ctx.bags[4] = nil, { 0, 0, 0 }
    ctx.fire("BAG_UPDATE_DELAYED")
    check("bag row: empty and missing bags skipped; spare icon hidden, icons reused", ctx.text() .. " / "
        .. #ctx.icons() .. " " .. tostring(ctx.icons()[3].shown), GENERAL_ICON .. " 5/26 | icon33 7/20 / 3 false")
    local b = ctx.icons()[2]
    b.scripts.OnClick(b, "LeftButton")
    ctx.icons()[1].scripts.OnClick(ctx.icons()[1], "LeftButton")
    check("bag row: any icon click opens all bags", ctx.toggled, 2)
    b.scripts.OnEnter(b)
    check("bag row: profession tooltip names its bags", ctx.tip.title .. " / " .. texts(ctx.tip) .. " / "
        .. tostring(ctx.tip.shown), "Profession bag / Bag3 / 7/20 free / Click to open your bags / true")
    b.scripts.OnLeave(b)
    check("bag row: tooltip hidden on leave", ctx.tip.shown, false)
    ctx.icons()[1].scripts.OnEnter(ctx.icons()[1])
    check("bag row: general tooltip names its bags", ctx.tip.title .. " / " .. texts(ctx.tip),
        "General bags / Bag0, Bag1 / 5/26 free / Click to open your bags")
    check("bag row: BagsBar faded", ctx.state.frames.BagsBar.alpha .. " "
        .. tostring(ctx.state.frames.BagsBar.mouse), "0 false")
    ctx.run("layout off")
    check("bag row: hidden when the layout is off", ctx.row().shown, false)
    check("bag row: BagsBar restored", ctx.state.frames.BagsBar.alpha .. " "
        .. tostring(ctx.state.frames.BagsBar.mouse), "1 true")
    ctx.fire("BAG_UPDATE_DELAYED")
    check("bag row: events while off keep it hidden", ctx.row().shown, false)
    check("bag row: no Blizzard frame hidden or hooked", #ctx.state.touched .. " " .. tostring(ctx.state.hooked),
        "0 nil")
    ctx.bags[0][2] = 1
    local rowBefore = ctx.row()
    ctx.run("layout on")
    check("bag row: shown again and updated, same frames", tostring(ctx.row().shown) .. " "
        .. tostring(ctx.row() == rowBefore) .. " " .. #ctx.icons() .. " " .. ctx.text(),
        "true true 3 " .. GENERAL_ICON .. " 1/26 | icon33 7/20")
end

do
    local ctx = loadBags()
    ctx.env.ToggleAllBags = nil
    ctx.run("layout on")
    check("bag row: not ready stays dark, BagsBar kept", #ctx.icons() .. " " .. ctx.state.frames.BagsBar.alpha, "0 1")

    ctx = loadBags({ frames = {} })
    ctx.run("layout on")
    check("bag row: no BagsBar still shows", ctx.row().shown, true)

    ctx = loadBags({ env = { GetInventoryItemTexture = false } })
    ctx.bags[1] = { 20, 3, 8 }
    ctx.run("layout on")
    check("bag row: no icon API falls back to a question mark", ctx.text(),
        GENERAL_ICON .. " 17/28 | Interface\\Icons\\INV_Misc_QuestionMark 3/20")
    local b = ctx.icons()[1]
    ctx.env.GameTooltip = nil
    b.scripts.OnEnter(b)
    b.scripts.OnLeave(b)
    check("bag row: no GameTooltip is harmless", b.shown, true)

    ctx = loadBags({ locale = "zhTW" })
    ctx.bags[1] = { 20, 3, 8 }
    ctx.env.C_Container.GetBagName = nil
    ctx.run("layout on")
    local zb = ctx.icons()[2]
    zb.scripts.OnEnter(zb)
    check("zhTW bag row tooltip, no bag names", ctx.tip.title .. " / " .. texts(ctx.tip), "專業背包 / 剩餘 3/20 / 點擊開啟背包")
    ctx.icons()[1].scripts.OnEnter(ctx.icons()[1])
    check("zhTW bag row general tooltip", ctx.tip.title .. " / " .. texts(ctx.tip), "一般背包 / 剩餘 17/28 / 點擊開啟背包")

    ctx = loadBags({ layouts = { editLayout(), editLayout("Tandem") }, active = 4,
        db = { schemaVersion = 7, layout = { on = true, previous = { name = "view", type = 1 } } } })
    ctx.fire("PLAYER_LOGIN")
    check("bag row: relogin with the layout on shows it", tostring(ctx.row().shown) .. " " .. ctx.text(),
        "true " .. GENERAL_ICON .. " 19/38")
end

-- The reagent bag: its own bag row icon, opened and closed with the other bags, and B pointed at the same opener.
do
    local open, binds, cleared = {}, {}, 0
    local enum = copyTable(LAYOUT_ENUM)
    enum.BagIndex = { ReagentBag = 5 }
    local ctx
    ctx = loadBags({ env = {
        Enum = enum,
        IsBagOpen = function(bag) return open[bag] end,
        OpenBag = function(bag) open[bag] = true end,
        CloseBag = function(bag) open[bag] = nil end,
        ToggleAllBags = function()
            ctx.toggled = ctx.toggled + 1
            open[0] = not open[0] or nil
        end,
        GetBindingKey = function(action)
            if action == "OPENALLBAGS" then
                return "SHIFT-B"
            elseif action == "TOGGLEBACKPACK" then
                return "B"
            end
        end,
        SetOverrideBindingClick = function(owner, priority, key, button)
            binds[#binds + 1] = key .. ">" .. button .. ">" .. tostring(owner.name) .. ">" .. tostring(priority)
        end,
        ClearOverrideBindings = function() cleared = cleared + 1 end,
    } })
    ctx.bags[5] = { 20, 7, 0 }
    ctx.run("layout on")
    check("reagent bag: its own icon after the profession bags", ctx.text(),
        GENERAL_ICON .. " 19/38 | icon35 7/20")
    local r = ctx.icons()[2]
    r.scripts.OnEnter(r)
    check("reagent bag: tooltip", ctx.tip.title .. " / " .. texts(ctx.tip),
        "Reagent bag / Bag5 / 7/20 free / Click to open your bags")
    r.scripts.OnClick(r, "LeftButton")
    check("reagent bag: opens with all bags", tostring(open[0]) .. " " .. tostring(open[5]), "true true")
    r.scripts.OnClick(r, "LeftButton")
    check("reagent bag: closes with all bags", tostring(open[0]) .. " " .. tostring(open[5]), "nil nil")
    ctx.fire("PLAYER_LOGIN")
    check("reagent bag: every open-all-bags and open-backpack key clicks Tandem's opener",
        table.concat(binds, " ") .. " " .. cleared,
        "SHIFT-B>TandemOpenAllBags>TandemOpenAllBags>false B>TandemOpenAllBags>TandemOpenAllBags>false 1")
    ctx.bags[5] = nil
    open = {}
    r.scripts.OnClick(r, "LeftButton")
    check("reagent bag: none equipped opens only the others", tostring(open[0]) .. " " .. tostring(open[5]),
        "true nil")

    binds = {}
    ctx.state.combat = true
    ctx.fire("PLAYER_LOGIN")
    check("reagent bag: no binding change in combat", #binds, 0)
    ctx.state.combat = false
    ctx.fire("PLAYER_REGEN_ENABLED")
    check("reagent bag: bound when combat ends", #binds, 2)

    -- A client whose bag window state reads the same before and after the toggle: the reagent bag simply toggles.
    local shut = {}
    ctx = loadBags({ env = {
        Enum = enum,
        IsBagOpen = function(bag) return bag == 5 and shut[5] or nil end,
        OpenBag = function(bag) shut[bag] = true end,
        CloseBag = function(bag) shut[bag] = nil end,
    } })
    ctx.bags[5] = { 20, 7, 0 }
    ctx.run("layout on")
    local icon = ctx.icons()[1]
    icon.scripts.OnClick(icon, "LeftButton")
    check("reagent bag: unseen main window still opens it", tostring(shut[5]) .. " " .. ctx.toggled, "true 1")
    icon.scripts.OnClick(icon, "LeftButton")
    check("reagent bag: and closes it on the next press", tostring(shut[5]) .. " " .. ctx.toggled, "nil 2")
end

-- Class rail above the top action bar, Shaman first (stage 12, U5, D5, D12, PLAN decision 6).

-- Loads the layout as a Shaman: ctx.t is GetTime; ctx.totems[slot] = { have, name, start, duration, icon };
-- ctx.weapon is GetWeaponEnchantInfo's returns (n of them); ctx.auras[name] = aura data for
-- C_UnitAuras.GetAuraDataBySpellName and ctx.buffs the UnitBuff list { name, icon, count, expiration }, so a buff
-- the rail must not show can be up; ctx.mana = { cur, max }; ctx.tickers lists C_Timer.NewTicker calls; ctx.calls
-- counts totem, weapon, weapon icon, aura and power API calls; ctx.tip is GameTooltip. opts.class is the class file.
local function loadShaman(opts)
    opts = opts or {}
    local ui = { widgets = {} }
    local ctx
    local spells = { [324] = "Lightning Shield", [24398] = "Water Shield" }
    local env = {
        UIParent = { name = "UIParent" },
        GameTooltip = barTooltip(),
        UnitClass = function() return "Class", opts.class or "SHAMAN" end,
        GetTime = function() return ctx.t end,
        GetTotemInfo = function(slot)
            ctx.calls = ctx.calls + 1
            local t = ctx.totems[slot]
            if not t then
                return false, "", 0, 0, ""
            end
            return t[1], t[2], t[3], t[4], t[5]
        end,
        GetWeaponEnchantInfo = function()
            ctx.calls = ctx.calls + 1
            local w = ctx.weapon
            if w.n == 6 then
                return w[1], w[2], w[3], w[4], w[5], w[6]
            end
            return w[1], w[2], w[3], w[4], w[5], w[6], w[7], w[8]
        end,
        GetInventoryItemTexture = function(unit, slot)
            ctx.calls = ctx.calls + 1
            return unit == "player" and ({ [16] = "mhIcon", [17] = "ohIcon" })[slot] or nil
        end,
        C_Spell = { GetSpellName = function(id) return spells[id] end },
        UnitPower = function(unit, kind)
            ctx.calls = ctx.calls + 1
            return unit == "player" and kind == 0 and ctx.mana[1] or nil end,
        UnitPowerMax = function(unit, kind) return unit == "player" and kind == 0 and ctx.mana[2] or nil end,
        C_Timer = { NewTicker = function(interval, fn)
            local t = { interval = interval, fn = fn }
            function t.Cancel(self) self.cancelled = true end
            ctx.tickers[#ctx.tickers + 1] = t
            return t
        end },
    }
    env.UnitBuff = function(unit, i)
        ctx.calls = ctx.calls + 1
        local b = unit == "player" and ctx.buffs[i]
        if b then
            return b[1], b[2], b[3], nil, nil, b[4]
        end
    end
    env.C_UnitAuras = { GetAuraDataBySpellName = function(unit, name, filter)
        ctx.calls = ctx.calls + 1
        return unit == "player" and filter == "HELPFUL" and ctx.auras[name] or nil
    end }
    for k, v in pairs(opts.env or {}) do
        env[k] = v
    end
    ctx = loadLayout({ env = env, locale = opts.locale, db = opts.db, layouts = opts.layouts, active = opts.active,
        widgets = function(kind, name, parent, template)
            return newWidget(ui, kind, name, parent, template)
        end })
    ctx.ui, ctx.t, ctx.totems, ctx.weapon, ctx.auras, ctx.buffs = ui, 100, {}, { n = 8 }, {}, {}
    ctx.mana, ctx.tickers, ctx.calls, ctx.tip = { 800, 1000 }, {}, 0, env.GameTooltip
    function ctx.area()
        for _, w in ipairs(ui.widgets) do
            if w.kind == "Frame" and w.parent == ctx.env.UIParent then
                return w
            end
        end
    end
    -- The rail's shown slots in order, as "icon time" plus " x<count>" when a count shows.
    function ctx.shownSlots()
        local out = {}
        for _, w in ipairs(ui.widgets) do
            if w.kind == "Frame" and w.parent == ctx.area() and w.shown then
                out[#out + 1] = w
            end
        end
        return out
    end
    function ctx.slots()
        local out = {}
        for i, s in ipairs(ctx.shownSlots()) do
            out[i] = tostring(s.icon.texture) .. " " .. s.time.text .. (s.count.text ~= "" and (" x" .. s.count.text)
                or "")
        end
        return table.concat(out, " | ")
    end
    -- The tooltip of shown slot i as "title / line / ...".
    function ctx.tooltip(i)
        local s = ctx.shownSlots()[i]
        s.scripts.OnEnter(s)
        local out = { ctx.tip.title }
        for _, l in ipairs(ctx.tip.lines) do
            out[#out + 1] = l.text
        end
        s.scripts.OnLeave(s)
        return table.concat(out, " / ")
    end
    function ctx.live()
        local n = 0
        for _, t in ipairs(ctx.tickers) do
            n = n + (t.cancelled and 0 or 1)
        end
        return n
    end
    return ctx
end

do
    local ctx = loadShaman()
    check("class rail: nothing made while the layout is off", (ctx.area()), nil)
    ctx.fire("PLAYER_TOTEM_UPDATE")
    ctx.fire("UNIT_AURA", "player")
    check("class rail: events while off are harmless", (ctx.area()), nil)
    ctx.run("layout on")
    local a = ctx.area()
    check("class rail: 36x232 between the unit frames, 30 above the unit row; mana and no slot keep it hidden",
        tostring(a.shown) .. " " .. a.height .. "x" .. tostring(a.width) .. " "
        .. tostring(a.template) .. " " .. #a.points .. " " .. a.points[1][1] .. " "
        .. tostring(a.points[1][2] == ctx.env.UIParent) .. " " .. table.concat(a.points[1], " ", 3),
        "false 36x232 nil 1 BOTTOM true BOTTOM 0 222")
    check("class rail: no totem or enchant shows no slot", ctx.slots(), "")
    check("class rail: mana line along the bottom", a.line.kind .. " " .. a.line.height .. " " .. a.line.points[1][1]
        .. " " .. a.line.points[2][1] .. " " .. a.line.value .. " " .. a.line.min .. " " .. a.line.max .. " "
        .. tostring(a.line.shown) .. " " .. rgb(a.line.barColor), "StatusBar 4 BOTTOMLEFT BOTTOMRIGHT 800 0 1000 true "
        .. "0.00,0.44,0.87")

    ctx.totems[1] = { true, "Searing Totem", 90, 55, "fireIcon" }
    ctx.totems[2] = { true, "Stoneskin Totem", 100, 120, "earthIcon" }
    ctx.totems[4] = { true, "Windfury Totem", 40, 120, "airIcon" }
    ctx.fire("PLAYER_TOTEM_UPDATE")
    check("class rail: active totems only, in Earth, Fire, Water, Air order; m:ss above a minute, else seconds",
        ctx.slots(), "earthIcon 2:00 | fireIcon 45 | airIcon 60")
    check("class rail: a slot shows the rail with its mana line", tostring(a.shown) .. " " .. tostring(a.line.shown)
        .. " " .. ctx.live(), "true true 1")
    local s = ctx.shownSlots()
    check("class rail: 32px slots centred above the line", s[1].width .. "x" .. s[1].height .. " "
        .. ("%s %d %d / %d / %d "):format(s[1].points[1][3], s[1].points[1][4], s[1].points[1][5], s[2].points[1][4],
        s[3].points[1][4]) .. tostring(s[1].points[1][2] == a), "32x32 BOTTOM -36 4 / 0 / 36 true")
    check("class rail: a totem's tooltip is its name", ctx.tooltip(1) .. " " .. tostring(ctx.tip.shown),
        "Stoneskin Totem / 2:00 false")
    check("class rail: one ticker at 4 Hz while shown", #ctx.tickers .. " " .. ctx.tickers[1].interval .. " "
        .. ctx.live(), "1 0.25 1")
    ctx.t = 150
    ctx.calls = 0
    ctx.tickers[1].fn()
    check("class rail: the ticker counts down; an expired totem's slot goes", ctx.slots(),
        "earthIcon 1:10 | airIcon 10")
    check("class rail: a tick calls no totem, weapon, aura or power API", ctx.calls, 0)
    check("class rail: the remaining slots re-centre", ("%d %d"):format(ctx.shownSlots()[1].points[1][4],
        ctx.shownSlots()[2].points[1][4]), "-18 18")
    ctx.t = 100
    ctx.totems = {}
    ctx.fire("PLAYER_TOTEM_UPDATE")

    ctx.weapon = { true, 1234567, 0, 563, true, 61000, 0, 2, n = 8 }
    ctx.fire("UNIT_INVENTORY_CHANGED", "player")
    check("class rail: weapon enchants never show", ctx.slots(), "")
    ctx.weapon = { n = 8 }

    ctx.auras["Lightning Shield"] = { applications = 3, expirationTime = 640, icon = "lsIcon" }
    ctx.buffs = { { "Lightning Shield", "lsIcon", 3, 640 } }
    ctx.fire("UNIT_AURA", "player")
    check("class rail: Lightning Shield up shows no slot", ctx.slots(), "")
    ctx.auras["Water Shield"] = { applications = 3, expirationTime = 640, icon = "wsIcon" }
    ctx.totems[3] = { true, "Healing Stream Totem", 100, 60, "waterIcon" }
    ctx.fire("PLAYER_TOTEM_UPDATE")
    check("class rail: a shield up beside a totem shows only the totem", ctx.slots() .. " / " .. ctx.tooltip(1),
        "waterIcon 60 / Healing Stream Totem / 1:00")

    ctx.mana = { 450, 1200 }
    ctx.fire("UNIT_POWER_UPDATE", "player", "MANA")
    check("class rail: UNIT_POWER_UPDATE", a.line.value .. " " .. a.line.max, "450 1200")
    ctx.mana = { 450, 1500 }
    ctx.fire("UNIT_MAXPOWER", "player", "MANA")
    check("class rail: UNIT_MAXPOWER", a.line.value .. " " .. a.line.max, "450 1500")

    local clickable, mouse = {}, 0
    for _, w in ipairs(ctx.ui.widgets) do
        if w.template or w.scripts.OnClick or w.scripts.OnMouseDown or w.scripts.OnMouseUp or w.kind == "Button" then
            clickable[#clickable + 1] = w.kind
        end
        if w.mouse and not (w.parent == a and w.scripts.OnEnter) then
            mouse = mouse + 1
        end
    end
    check("class rail: nothing clickable, no templates; only slots take the mouse, for their tooltip",
        #clickable .. " " .. mouse, "0 0")

    ctx.run("layout off")
    check("class rail: hidden with the layout off; ticker stopped", tostring(a.shown) .. " " .. ctx.live(),
        "false 0")
    ctx.fire("PLAYER_TOTEM_UPDATE")
    check("class rail: events while off keep it hidden", a.shown, false)
    ctx.run("layout on")
    check("class rail: shown again, one rail, one live ticker", tostring(a.shown) .. " "
        .. tostring(ctx.area() == a) .. " " .. ctx.live(), "true true 1")
end

do
    local ctx = loadShaman({ env = { UnitPowerMax = function() return 0 end } })
    ctx.run("layout on")
    check("class rail: no mana and no slot hides the rail and the line", tostring(ctx.area().shown) .. " "
        .. tostring(ctx.area().line.shown) .. " " .. ctx.live(), "false false 0")
    ctx.totems[2] = { true, "Stoneskin Totem", 100, 120, "earthIcon" }
    ctx.fire("PLAYER_TOTEM_UPDATE")
    check("class rail: a slot shows the rail again", tostring(ctx.area().shown) .. " " .. ctx.slots() .. " "
        .. ctx.live(), "true earthIcon 2:00 1")
    ctx.t = 220
    ctx.tickers[1].fn()
    check("class rail: the last slot running out hides the rail", tostring(ctx.area().shown) .. " " .. ctx.live(),
        "false 0")

    ctx = loadShaman({ class = "WARRIOR" })
    ctx.run("layout on")
    check("class rail: another class gets no rail", (ctx.area()), nil)

    ctx = loadShaman()
    ctx.env.GetTotemInfo = nil
    ctx.run("layout on")
    check("class rail: not ready stays dark", (ctx.area()), nil)

    ctx = loadShaman({ env = { C_Timer = false } })
    ctx.totems[2] = { true, "Stoneskin Totem", 100, 120, "earthIcon" }
    ctx.run("layout on")
    check("class rail: no C_Timer still shows", ctx.area().shown, true)

    ctx = loadShaman({ env = { GameTooltip = false } })
    ctx.totems[2] = { true, "Stoneskin Totem", 100, 120, "earthIcon" }
    ctx.run("layout on")
    local s = ctx.shownSlots()[1]
    s.scripts.OnEnter(s)
    s.scripts.OnLeave(s)
    check("class rail: no GameTooltip is harmless", ctx.slots(), "earthIcon 2:00")

    ctx = loadShaman()
    for i = 1, 4 do
        ctx.totems[i] = { true, "Totem " .. i, 100, 120, "t" .. i }
    end
    ctx.weapon = { true, 60000, 0, 1, true, 60000, 0, 2, n = 8 }
    ctx.auras["Lightning Shield"] = { applications = 3, expirationTime = 160, icon = "lsIcon" }
    ctx.run("layout on")
    check("class rail: four slots at most for a Shaman, centred", ("%d %d %d"):format(#ctx.shownSlots(),
        ctx.shownSlots()[1].points[1][4], ctx.shownSlots()[4].points[1][4]), "4 -54 54")

    local many = {}
    for i = 1, 14 do
        many[i] = { icon = "i" .. i, label = "L" .. i }
    end
    ctx.addon.ClassArea.Set(many)
    check("class rail: twelve slots at most", ("%d %d %d"):format(#ctx.shownSlots(), ctx.shownSlots()[1].points[1][4],
        ctx.shownSlots()[12].points[1][4]), "12 -198 198")

    ctx = loadShaman({ layouts = { editLayout(), editLayout("Tandem") }, active = 4,
        db = { schemaVersion = 7, layout = { on = true, previous = { name = "view", type = 1 } } } })
    ctx.totems[2] = { true, "Stoneskin Totem", 100, 120, "earthIcon" }
    ctx.fire("PLAYER_LOGIN")
    check("class rail: relogin with the layout on shows it", ctx.area().shown, true)
    local reg = ctx.frame.registered
    check("class rail: unit events registered (falling back to every unit); no UNIT_AURA",
        tostring(reg.UNIT_AURA) .. " " .. tostring(reg.UNIT_POWER_UPDATE) .. " " .. tostring(reg.UNIT_MAXPOWER) .. " "
        .. tostring(reg.PLAYER_TOTEM_UPDATE) .. " " .. tostring(reg.UNIT_INVENTORY_CHANGED), "nil true true true nil")
end

-- Store.RegisterUnitEvent: the player only where the client has RegisterUnitEvent, else every unit (U5 review).
do
    local Store = loadWithDB(nil).Store
    local got = {}
    local f = { RegisterUnitEvent = function(_, ev, unit) got[#got + 1] = ev .. ":" .. unit end,
        RegisterEvent = function(_, ev) got[#got + 1] = ev end }
    check("unit event: RegisterUnitEvent used for the unit", tostring(Store.RegisterUnitEvent(f, "UNIT_AURA", "player"))
        .. " " .. table.concat(got, ","), "true UNIT_AURA:player")
    got = {}
    f.RegisterUnitEvent = function() error("unknown event") end
    check("unit event: a raising RegisterUnitEvent falls back", tostring(Store.RegisterUnitEvent(f, "UNIT_AURA",
        "player")) .. " " .. table.concat(got, ","), "true UNIT_AURA")
    f.RegisterUnitEvent = nil
    f.RegisterEvent = function() error("unknown event") end
    check("unit event: an unknown event registers nothing", Store.RegisterUnitEvent(f, "UNIT_NOPE", "player"), false)
end

-- Minimap button and addon compartment: a click turns the layout on or off (stage 12, U6).

local function fakeMinimap(ui)
    local m = newWidget(ui, "Minimap", "Minimap")
    m.GetWidth = function() return 140 end
    m.GetCenter = function() return 500, 400 end
    m.GetEffectiveScale = function() return 2 end
    return m
end

local function near(a, b)
    return math.abs(a - b) < 1e-6
end

-- Loads the layout with a fake minimap and GameTooltip; ctx.cursor is GetCursorPosition, ctx.button() the minimap
-- button after PLAYER_LOGIN, ctx.tip the tooltip. opts.noMinimap leaves Minimap out.
local function loadMinimap(opts)
    opts = opts or {}
    local ui = { widgets = {} }
    local tip = fakeTooltip()
    function tip.SetOwner(self, owner) self.owner, self.lines = owner, {} end
    function tip.SetText(self, text) self.title = text end
    function tip.Show(self) self.shown = true end
    function tip.Hide(self) self.shown = false end
    local ctx
    local env = { GameTooltip = tip, GetCursorPosition = function() return ctx.cursor[1], ctx.cursor[2] end }
    if not opts.noMinimap then
        env.Minimap = fakeMinimap(ui)
    end
    ctx = loadLayout({ env = env, locale = opts.locale, db = opts.db, layouts = opts.layouts, active = opts.active,
        widgets = function(kind, name, parent, template)
            return newWidget(ui, kind, name, parent, template)
        end })
    ctx.ui, ctx.tip, ctx.cursor = ui, tip, { 1000, 1000 }
    function ctx.button()
        for _, w in ipairs(ui.widgets) do
            if w.name == "TandemMinimapButton" then
                return w
            end
        end
    end
    function ctx.click(b)
        local from = #ctx.printed
        b.scripts.OnClick(b, "LeftButton")
        return table.concat(linesSince(ctx.printed, from), "|")
    end
    return ctx
end

do
    local want = {
        AddonCompartmentFunc = "Tandem_OnCompartmentClick",
        AddonCompartmentFuncOnEnter = "Tandem_OnCompartmentEnter",
        AddonCompartmentFuncOnLeave = "Tandem_OnCompartmentLeave",
    }
    local got = {}
    for raw in io.lines(addonDir .. "Tandem.toc") do
        local key, value = raw:match("^## (%S+): (%S+)$")
        if key and want[key] then
            got[key] = value
        end
    end
    local ctx = loadMinimap()
    for key, fn in pairs(want) do
        check("toc " .. key, got[key], fn)
        check("launcher: global " .. fn, type(ctx.env[fn]), "function")
    end

    ctx.fire("PLAYER_LOGIN")
    local b = ctx.button()
    check("minimap button: shown by default on the minimap", tostring(b.shown) .. " " .. tostring(b.parent
        == ctx.env.Minimap) .. " " .. b.icon.texture, "true true Interface\\AddOns\\Tandem\\Media\\icon")
    local p = b.points[1]
    check("minimap button: default angle 225", p[1] .. " " .. p[3] .. " " .. tostring(near(p[4], -80 * math.sqrt(0.5))
        and near(p[5], -80 * math.sqrt(0.5))), "CENTER CENTER true")
    check("minimap button: no state saved by default", ctx.env.TandemDB.layout.minimap, nil)
    ctx.fire("PLAYER_LOGIN")
    local n = 0
    for _, w in ipairs(ctx.ui.widgets) do
        n = n + (w.name == "TandemMinimapButton" and 1 or 0)
    end
    check("minimap button: built once", n, 1)

    local from = #ctx.printed
    b.scripts.OnClick(b, "RightButton")
    check("minimap button: a right click does nothing", #ctx.printed .. " " .. tostring(ctx.addon.Layout.IsOn()),
        from .. " false")
    check("minimap button: click turns the layout on", ctx.click(b) .. " " .. tostring(ctx.addon.Layout.IsOn()),
        "Tandem: layout on true")
    b.scripts.OnEnter(b)
    check("minimap button: tooltip with the state and hints", ctx.tip.title .. " / " .. texts(ctx.tip) .. " / "
        .. tostring(ctx.tip.owner == b) .. " " .. tostring(ctx.tip.shown),
        "Tandem / Layout: on / Click to turn the layout on/off / Drag to move this button / true true")
    b.scripts.OnLeave(b)
    check("minimap button: tooltip hidden", ctx.tip.shown, false)
    check("minimap button: click turns the layout off", ctx.click(b) .. " " .. tostring(ctx.addon.Layout.IsOn()),
        "Tandem: layout off; your previous layout is back false")
    b.scripts.OnEnter(b)
    check("minimap button: tooltip shows off", ctx.tip.lines[1].text, "Layout: off")

    from = #ctx.printed
    ctx.env.Tandem_OnCompartmentClick("Tandem", "LeftButton")
    check("compartment click turns the layout on", table.concat(linesSince(ctx.printed, from), "|") .. " "
        .. tostring(ctx.addon.Layout.IsOn()), "Tandem: layout on true")
    from = #ctx.printed
    ctx.env.Tandem_OnCompartmentClick("Tandem", "LeftButton")
    check("compartment click turns the layout off", table.concat(linesSince(ctx.printed, from), "|") .. " "
        .. tostring(ctx.addon.Layout.IsOn()), "Tandem: layout off; your previous layout is back false")
    local menuButton = {}
    ctx.env.Tandem_OnCompartmentEnter("Tandem", menuButton)
    check("compartment tooltip: no drag hint", tostring(ctx.tip.owner == menuButton) .. " " .. texts(ctx.tip),
        "true Layout: off / Click to turn the layout on/off")
    ctx.env.Tandem_OnCompartmentLeave("Tandem", menuButton)
    check("compartment tooltip hidden", ctx.tip.shown, false)

    ctx.state.combat = true
    check("minimap button: click in combat waits", ctx.click(b), "Tandem: the layout will change after combat")
    ctx.state.combat = false
    ctx.fire("PLAYER_REGEN_ENABLED")
    check("minimap button: the deferred click turns it on after combat", ctx.addon.Layout.IsOn(), true)

    b.scripts.OnDragStart(b)
    check("minimap button: follows the cursor while dragged", type(b.scripts.OnUpdate), "function")
    ctx.cursor = { 1200, 800 }
    b.scripts.OnUpdate(b)
    check("minimap button: drag moves it east", near(b.points[1][4], 80) and near(b.points[1][5], 0), true)
    ctx.cursor = { 1200, 1000 }
    b.scripts.OnUpdate(b)
    b.scripts.OnDragStop(b)
    check("minimap button: stops following", b.scripts.OnUpdate, nil)
    check("minimap button: drag saves the angle", near(ctx.env.TandemDB.layout.minimap.angle, 45), true)

    check("minimap command: no argument hides", ctx.run("minimap") .. " " .. tostring(b.shown),
        "Tandem: minimap button hidden false")
    check("minimap command: hidden is saved with the angle", tostring(ctx.env.TandemDB.layout.minimap.hidden) .. " "
        .. tostring(near(ctx.env.TandemDB.layout.minimap.angle, 45)), "true true")
    check("minimap command: no argument shows again", ctx.run("minimap") .. " " .. tostring(b.shown),
        "Tandem: minimap button shown true")
    check("minimap command: shown drops the hidden flag", ctx.env.TandemDB.layout.minimap.hidden, nil)
    check("minimap command: off", ctx.run("minimap off") .. " " .. tostring(b.shown),
        "Tandem: minimap button hidden false")
    check("minimap command: off again stays hidden", ctx.run("minimap off") .. " " .. tostring(b.shown),
        "Tandem: minimap button hidden false")
    ctx.state.combat = true
    check("minimap command: works in combat", ctx.run("minimap on") .. " " .. tostring(b.shown),
        "Tandem: minimap button shown true")
    ctx.state.combat = false
    for _, msg in ipairs({ "minimap yes", "minimap on off" }) do
        check("minimap command: usage for " .. msg, ctx.run(msg):match("^[^|]*"), "Tandem commands:")
    end
    ctx.run("minimap off")

    local again = loadMinimap({ db = ctx.env.TandemDB })
    again.fire("PLAYER_LOGIN")
    local q = again.button()
    check("minimap button: hidden state restored at login", q.shown, false)
    check("minimap button: angle restored at login", near(q.points[1][4], 80 * math.sqrt(0.5))
        and near(q.points[1][5], 80 * math.sqrt(0.5)), true)
end

do
    local ctx = loadMinimap({ noMinimap = true })
    ctx.fire("PLAYER_LOGIN")
    check("minimap button: no minimap builds nothing", ctx.button(), nil)
    ctx.run("minimap on")
    check("minimap command: nothing saved when shown without an angle", ctx.env.TandemDB.layout.minimap, nil)
    check("minimap command: still saved without a minimap", ctx.run("minimap off") .. " "
        .. tostring(ctx.env.TandemDB.layout.minimap.hidden), "Tandem: minimap button hidden true")
    ctx.env.Tandem_OnCompartmentEnter("Tandem", nil)
    check("compartment tooltip without a frame is skipped", ctx.tip.title, nil)
end

do
    local ctx = loadMinimap({ locale = "zhTW" })
    ctx.fire("PLAYER_LOGIN")
    local b = ctx.button()
    b.scripts.OnEnter(b)
    check("zhTW minimap tooltip", texts(ctx.tip), "介面配置：關閉 / 點擊以開啟或關閉介面配置 / 拖曳以移動此按鈕")
    check("zhTW minimap command", ctx.run("minimap"), "Tandem：已隱藏小地圖按鈕")
    local help = run(ctx.addon, ctx.printed, "help")
    check("zhTW usage lists minimap", help[#help - 1], "  /tandem minimap [on|off] - 顯示或隱藏小地圖按鈕")
    check("zhTW usage lists debug", help[#help], "  /tandem debug [on|off|snap] - 為開發者記錄版面追蹤資料；/reload 後寫入存檔")
end

do
    local Launcher = loadWithDB(nil).Launcher
    check("angle: north is 90", near(Launcher.Angle(0, 10, 0, 0), 90), true)
    check("angle: a tiny negative angle wraps to 0", Launcher.Angle(1, -1e-300, 0, 0), 0)
end

-- Store: the optional minimap state in TandemDB.layout (U6), schema 7 unchanged.
do
    local addon, printed, env = loadWithDB({ schemaVersion = 7, layout = { on = true,
        minimap = { angle = 90.5, hidden = true } } })
    check("minimap store: a valid state is kept", dump(env.TandemDB.layout.minimap), dump({ angle = 90.5,
        hidden = true }))
    check("minimap store: a valid state prints only the load line", #printed, 1)
    local Store = addon.Store
    check("minimap store: SetLayout copies clean", Store.SetLayout("minimap", { angle = 0, extra = 1 })
        and dump(Store.Layout().minimap), dump({ angle = 0 }))
    for name, v in pairs({ ["360"] = { angle = 360 }, ["a string angle"] = { angle = "90" },
        ["NaN"] = { angle = 0 / 0 }, ["a non-boolean hidden"] = { hidden = 1 }, ["a number"] = 5 }) do
        check("minimap store: SetLayout rejects " .. name, Store.SetLayout("minimap", v), false)
        local _, out, e = loadWithDB({ schemaVersion = 7, layout = { on = true, minimap = v } })
        check("minimap store: load drops " .. name, tostring(e.TandemDB.layout.minimap) .. " "
            .. tostring(e.TandemDB.layout.on) .. " " .. tostring(out[2]),
            "nil true Tandem: dropped 1 invalid or unused saved entries")
    end
    check("minimap store: a newer db is not written",
        loadWithDB({ schemaVersion = 8 }).Store.SetLayout("minimap", { angle = 1 }), false)
end


-- Fishing rod swap (U1, D2, D3): Rod.lua's pure logic over a fake client.

-- Loads loadLive() as a level 40 warrior with ctx.worn[inv] = id for GetInventoryItemID, ctx.bags[bag] listing item
-- ids (bags 0..4), ctx.bound["bag:slot"] for C_Item.IsBound over ItemLocation:CreateFromBagAndSlot, item 70 a second
-- fishing pole, items 901 (a fishing pole) and 902 (a sword) the client has no cached item info for, and
-- C_Timer.After queueing its callbacks in ctx.timers (ctx.expire() runs them). Every item's icon is "icon<id>".
local function loadRod()
    local ctx
    local bags = { [0] = {} }
    local env = {
        GetInventoryItemID = function(unit, inv)
            assert(unit == "player")
            return ctx.worn[inv]
        end,
        C_Container = {
            GetContainerNumSlots = function(bag)
                return bags[bag] and #bags[bag] or 0
            end,
            GetContainerItemID = function(bag, slot)
                return bags[bag] and bags[bag][slot]
            end,
        },
        ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot)
            return { key = bag .. ":" .. slot }
        end },
        C_Timer = { After = function(_, fn)
            ctx.timers[#ctx.timers + 1] = fn
        end },
    }
    ctx = loadLive("enUS", { env = env })
    ctx.worn, ctx.bags, ctx.bound, ctx.timers = {}, bags, {}, {}
    function ctx.expire()
        local due = ctx.timers
        ctx.timers = {}
        for _, fn in ipairs(due) do
            fn()
        end
    end
    ctx.env.C_Item.IsBound = function(loc)
        return ctx.bound[loc.key] == true
    end
    ctx.items[70] = { "INVTYPE_2HWEAPON", 2, 20 }
    ctx.cache[70] = { "Strong Pole", nil, 2, 30, 1 }
    ctx.tips[70] = { "Strong Pole", ctx.strength(99) }
    ctx.items[901] = { "INVTYPE_2HWEAPON", 2, 20 }
    ctx.items[902] = { "INVTYPE_WEAPON", 2, 7 }
    local instant = ctx.env.C_Item.GetItemInfoInstant
    ctx.env.C_Item.GetItemInfoInstant = function(id)
        local got, a, b, equipLoc, _, classID, subclassID = instant(id)
        return got, a, b, equipLoc, "icon" .. tostring(id), classID, subclassID
    end
    ctx.Rod = ctx.addon.Rod
    return ctx
end

-- Returns Rod.Macro()'s text and icon as one string.
local function rodMacro(Rod)
    local text, icon = Rod.Macro()
    return tostring(text) .. " | " .. tostring(icon)
end

do
    local ctx = loadRod()
    local Rod = ctx.Rod
    check("rod: a fishing pole is a rod", Rod.IsRod(10), true)
    check("rod: a sword is not a rod", Rod.IsRod(7), false)
    check("rod: a fishing pole not loaded yet is a rod", Rod.IsRod(901), true)
    check("rod: an item not loaded yet is not a rod", Rod.IsRod(900), false)
    check("rod: an unknown item is not a rod", Rod.IsRod(999), false)
    check("rod: no rod finds nothing", tostring(Rod.Find()), "nil")
    check("rod: no rod has no macro", rodMacro(Rod), "nil | nil")
    check("rod: no rod is not fishing", Rod.Fishing(), false)
end

do
    local ctx = loadRod()
    local Rod = ctx.Rod
    ctx.worn[16], ctx.worn[17] = 7, 14
    ctx.bags[0] = { 9, 10 }
    Rod.Remember()
    local id, worn = Rod.Find()
    check("rod: a bag rod is found, not worn", tostring(id) .. " " .. tostring(worn), "10 false")
    check("rod: a bag rod with a sword worn equips the rod", rodMacro(Rod), "/equipslot 16 item:10 | icon10")
    check("rod: nothing to put back while not fishing", tostring(Rod.Back()), "nil")
    ctx.worn[16], ctx.worn[17] = 10, nil
    ctx.bags[0] = { 9, 7, 14 }
    Rod.Remember()
    id, worn = Rod.Find()
    check("rod: a worn rod is found worn", tostring(id) .. " " .. tostring(worn), "10 true")
    check("rod: the worn rod is fishing", Rod.Fishing(), true)
    check("rod: a worn rod puts the sword and off hand back", rodMacro(Rod),
        "/equipslot 16 item:7\n/equipslot 17 item:14 | icon7")
    ctx.worn[16] = nil
    ctx.bags[0] = { 9, 7, 14, 10 }
    Rod.Remember()
    ctx.worn[16] = 10
    check("rod: an empty main hand never overwrites", rodMacro(Rod),
        "/equipslot 16 item:7\n/equipslot 17 item:14 | icon7")
end

do
    local ctx = loadRod()
    local Rod = ctx.Rod
    ctx.worn[16], ctx.worn[17] = 7, 14
    Rod.Remember()
    ctx.worn[16], ctx.worn[17] = 10, nil
    ctx.bags[0] = { 7, 14 }
    Rod.Restoring()
    ctx.worn[16] = 7
    ctx.bags[0] = { 14, 10 }
    Rod.Remember()
    ctx.worn[16] = 10
    ctx.bags[0] = { 7, 14 }
    check("rod: an empty off hand seen mid-restore keeps the off hand", rodMacro(Rod),
        "/equipslot 16 item:7\n/equipslot 17 item:14 | icon7")
end

do
    local ctx = loadRod()
    local Rod = ctx.Rod
    ctx.worn[16], ctx.worn[17] = 7, 14
    Rod.Remember()
    ctx.worn[17] = nil
    ctx.bags[0] = { 14, 10 }
    Rod.Remember()
    ctx.worn[16] = 10
    ctx.bags[0] = { 14, 7 }
    check("rod: an off hand taken off is not put back", rodMacro(Rod), "/equipslot 16 item:7 | icon7")
end

do
    local ctx = loadRod()
    local Rod = ctx.Rod
    ctx.worn[16], ctx.worn[17] = 7, 14
    Rod.Remember()
    Rod.Restoring()
    ctx.expire()
    ctx.worn[17] = nil
    Rod.Remember()
    ctx.worn[16] = 10
    ctx.bags[0] = { 14, 7 }
    check("rod: an off hand taken off after the restore window is forgotten", rodMacro(Rod),
        "/equipslot 16 item:7 | icon7")
end

do
    local ctx = loadRod()
    local Rod = ctx.Rod
    ctx.worn[16], ctx.worn[17] = 7, 14
    Rod.Remember()
    Rod.Restoring()
    ctx.worn[16], ctx.worn[17] = 15, nil
    Rod.Remember()
    ctx.worn[16] = 10
    ctx.bags[0] = { 14, 7, 15 }
    check("rod: a two-hander forgets the off hand even mid-restore", rodMacro(Rod), "/equipslot 16 item:15 | icon15")
end

do
    local ctx = loadRod()
    local Rod = ctx.Rod
    ctx.worn[16] = 10
    ctx.bags[0] = { 7, 15, 70 }
    check("rod: no soulbound weapon, nothing to put back", rodMacro(Rod), "nil | nil")
    ctx.bound["0:1"], ctx.bound["0:3"] = true, true
    check("rod: the fallback is a soulbound usable weapon, never a fishing pole", rodMacro(Rod),
        "/equipslot 16 item:7 | icon7")
    ctx.bound["0:2"] = true
    check("rod: the fallback is the highest-scored weapon", rodMacro(Rod), "/equipslot 16 item:15 | icon15")
    ctx.items[71] = { "INVTYPE_WEAPON", 2, 7 }
    ctx.cache[71] = { "Plated Sword", nil, 2, 20, 1 }
    ctx.tips[71] = { "Plated Sword", ctx.strength(29), "100 Armor" }
    ctx.bags[0] = { 15, 71 }
    ctx.bound["0:1"], ctx.bound["0:2"] = true, true
    check("rod: a score tie goes to more armor", rodMacro(Rod), "/equipslot 16 item:71 | icon71")
    ctx.bags[0] = { 71, 15 }
    check("rod: the armor tie-break does not depend on bag order", rodMacro(Rod), "/equipslot 16 item:71 | icon71")
    ctx.env.C_Item.IsBound = nil
    check("rod: no C_Item.IsBound, no fallback", rodMacro(Rod), "nil | nil")
end

do
    local ctx = loadRod()
    local Rod = ctx.Rod
    ctx.worn[16] = 10
    ctx.bags[0] = { 7 }
    ctx.bound["0:1"] = true
    ctx.env.ItemLocation = nil
    check("rod: no ItemLocation, no fallback", rodMacro(Rod), "nil | nil")
end

do
    local ctx = loadRod()
    local Rod = ctx.Rod
    ctx.worn[16] = 10
    ctx.bags[0] = { 7 }
    ctx.bound["0:1"] = true
    ctx.tips[7] = nil
    check("rod: a weapon with no score yet is no fallback", rodMacro(Rod), "nil | nil")
end

do
    local ctx = loadRod()
    local Rod = ctx.Rod
    ctx.worn[16], ctx.worn[17] = 7, 14
    Rod.Remember()
    ctx.worn[16], ctx.worn[17] = 10, nil
    ctx.bags[0] = { 15, 14 }
    ctx.bound["0:1"] = true
    check("rod: a remembered sword no longer in the bags falls back", rodMacro(Rod), "/equipslot 16 item:15 | icon15")
end

do
    local ctx = loadRod()
    local Rod = ctx.Rod
    ctx.worn[16] = 902
    Rod.Remember()
    ctx.worn[16] = 901
    ctx.bags[0] = { 902 }
    check("rod: an uncached worn sword is remembered", rodMacro(Rod), "/equipslot 16 item:902 | icon902")
    local C_Item = ctx.env.C_Item
    ctx.env.C_Item = nil
    check("rod: no C_Item, no rod", Rod.IsRod(10), false)
    ctx.env.C_Item = C_Item
end

-- Fishing rod button (U2, D1, D3, D4): one secure button left of the bag row while the layout is on and a rod is owned.

-- Loads loadBags() with the Fishing rod APIs: ctx.worn[inv] = id for GetInventoryItemID, ctx.content[bag] listing
-- item ids, item 10 a fishing pole, 7 a sword, 14 an off-hand sword (icons "icon<id>", names "Item <id>").
-- ctx.button() is TandemRodButton; ctx.calls logs its SetAttribute/SetPoint/Show/Hide calls once ctx.watch() ran.
local ROD_ITEMS = {
    [7] = { "INVTYPE_WEAPON", 2, 7 }, [10] = { "INVTYPE_2HWEAPON", 2, 20 }, [14] = { "INVTYPE_WEAPONOFFHAND", 2, 7 },
}
local function loadRodButton(opts)
    opts = opts or {}
    local fn = function() end
    local ctx
    local env = {
        GetInventoryItemID = function(_, inv) return ctx.worn[inv] end,
        SecureActionButtonMixin = {}, SecureCmdList = { EQUIP_TO_SLOT = fn }, EquipItemByName = fn,
        C_Item = {
            GetItemInfoInstant = function(id)
                local it = ROD_ITEMS[id]
                if it then
                    return id, nil, nil, it[1], "icon" .. id, it[2], it[3]
                end
            end,
            GetItemInfo = function(id)
                if ROD_ITEMS[id] then
                    return "Item " .. id, nil, 2, 10, 1
                end
            end,
        },
    }
    for k, v in pairs(opts.env or {}) do
        env[k] = v
    end
    ctx = loadBags({ env = env, locale = opts.locale })
    ctx.worn, ctx.content, ctx.calls = {}, { [0] = {} }, {}
    ctx.env.C_Container.GetContainerItemID = function(bag, slot)
        return ctx.content[bag] and ctx.content[bag][slot]
    end
    local slots = ctx.env.C_Container.GetContainerNumSlots
    ctx.env.C_Container.GetContainerNumSlots = function(bag)
        return math.max(slots(bag), ctx.content[bag] and #ctx.content[bag] or 0)
    end
    function ctx.button()
        for _, w in ipairs(ctx.ui.widgets) do
            if w.name == "TandemRodButton" then
                return w
            end
        end
    end
    function ctx.watch()
        local b = ctx.button()
        for _, method in ipairs({ "SetAttribute", "SetPoint", "Show", "Hide" }) do
            local orig = WIDGET[method]
            b[method] = function(self, ...)
                ctx.calls[#ctx.calls + 1] = method
                return orig(self, ...)
            end
        end
    end
    return ctx
end

local function rodState(b)
    return table.concat({ tostring(b.shown), tostring(b.attrs and b.attrs.type),
        tostring(b.attrs and b.attrs.macrotext), tostring(b.icon.texture) }, " | ")
end

do
    local ctx = loadRodButton()
    ctx.worn[16], ctx.worn[17] = 7, 14
    ctx.content[0] = { 10 }
    ctx.fire("PLAYER_LOGIN")
    local b = ctx.button()
    check("rod button: made at login as a secure button on UIParent", tostring(b ~= nil) .. " " .. b.kind .. " "
        .. tostring(b.template) .. " " .. tostring(b.parent == ctx.env.UIParent) .. " " .. b.width .. "x" .. b.height,
        "true Button SecureActionButtonTemplate true 28x28")
    check("rod button: clicks registered on up and down", table.concat(b.clicks, " "), "AnyUp AnyDown")
    check("rod button: hidden while the layout is off", b.shown, false)
    ctx.run("layout on")
    check("rod button: shown with the equip macro", rodState(b),
        "true | macro | /equipslot 16 item:10 | icon10")
    local p = b.points[1]
    check("rod button: anchored to UIParent left of the bag row", #b.points .. " " .. table.concat({ p[1],
        tostring(p[2] == ctx.env.UIParent), p[3], p[4], p[5] }, " "), "1 BOTTOMRIGHT true BOTTOMRIGHT -44 8")
    check("rod button: never parented or anchored to the bag row",
        tostring(b.parent == ctx.row()) .. " " .. tostring(p[2] == ctx.row()), "false false")
    ctx.bags[3] = { 20, 7, 8 }
    ctx.fire("BAG_UPDATE_DELAYED")
    check("rod button: moves left as the bag row grows", b.points[1][4], -76)

    b.scripts.OnEnter(b)
    check("rod button: tooltip to equip the rod", ctx.tip.title .. " / " .. texts(ctx.tip),
        "Fishing rod / Equip Item 10 / Click to equip your fishing rod")
    ctx.bags[0][2], ctx.bags[1][2], ctx.bags[2][2] = 0, 0, 0
    b.scripts.OnEnter(b)
    check("rod button: bags full with an off hand worn", texts(ctx.tip),
        "Equip Item 10 / Bags full: no room for your off hand / Click to equip your fishing rod")
    check("rod button: the bags-full line is red", colour(ctx.tip.lines[2]), "1,0.1,0.1")
    ctx.worn[17] = nil
    b.scripts.OnEnter(b)
    check("rod button: no off hand, no bags-full line", texts(ctx.tip),
        "Equip Item 10 / Click to equip your fishing rod")
    ctx.worn[17] = 14
    ctx.bags[2][2] = 3
    b.scripts.OnEnter(b)
    check("rod button: a free general slot, no bags-full line", texts(ctx.tip),
        "Equip Item 10 / Click to equip your fishing rod")
    ctx.bags[2][2] = 0
    b.scripts.OnEnter(b)
    check("rod button: a profession bag's free slots do not count", texts(ctx.tip):match("Bags full") ~= nil, true)

    ctx.worn[16], ctx.worn[17] = 10, nil
    ctx.content[0] = { 7, 14 }
    ctx.fire("PLAYER_EQUIPMENT_CHANGED")
    check("rod button: rod worn puts the weapons back", rodState(b),
        "true | macro | /equipslot 16 item:7\n/equipslot 17 item:14 | icon7")
    b.scripts.OnEnter(b)
    check("rod button: tooltip to put the weapons back", texts(ctx.tip),
        "Put back Item 7 + Item 14 / Click to put your weapons back")

    ctx.watch()
    ctx.state.combat = true
    ctx.worn[16], ctx.worn[17] = 7, 14
    ctx.content[0] = { 10 }
    ctx.fire("PLAYER_EQUIPMENT_CHANGED")
    ctx.fire("BAG_UPDATE_DELAYED")
    ctx.content[0] = {}
    ctx.fire("BAG_UPDATE_DELAYED")
    check("rod button: nothing changed in combat", #ctx.calls .. " " .. rodState(b),
        "0 true | macro | /equipslot 16 item:7\n/equipslot 17 item:14 | icon7")
    b.scripts.OnEnter(b)
    check("rod button: in-combat tooltip note", ctx.tip.lines[#ctx.tip.lines].text,
        "In combat the button runs the swap it showed before combat")
    ctx.state.combat = false
    ctx.fire("PLAYER_REGEN_ENABLED")
    check("rod button: the rod gone hides it when combat ends", b.shown, false)
    ctx.calls = {}
    ctx.fire("PLAYER_REGEN_ENABLED")
    check("rod button: nothing pending, nothing applied", #ctx.calls, 0)

    ctx.content[0] = { 10 }
    ctx.fire("BAG_UPDATE_DELAYED")
    check("rod button: shown again with a rod back in the bags", b.shown, true)
    ctx.run("layout off")
    check("rod button: hidden when the layout is off", b.shown, false)
    ctx.state.combat = true
    ctx.calls = {}
    ctx.run("layout on")
    ctx.state.combat = false
    ctx.fire("PLAYER_REGEN_ENABLED")
    check("rod button: the layout turned on in combat shows it after", b.shown, true)
end

do
    local ctx = loadRodButton()
    ctx.worn[16] = 10
    ctx.content[0] = {}
    ctx.fire("PLAYER_LOGIN")
    ctx.run("layout on")
    local b = ctx.button()
    check("rod button: worn rod with nothing to put back still shows", rodState(b), "true | macro | nil | icon10")
    b.scripts.OnEnter(b)
    check("rod button: asks to equip a weapon", texts(ctx.tip), "Equip your weapon")
end

do
    local ctx = loadRodButton()
    local full = ctx.env.C_Item.GetItemInfo
    ctx.env.C_Item.GetItemInfo = function(id)
        if id ~= 10 then
            return full(id)
        end
    end
    ctx.worn[16] = 7
    ctx.content[0] = { 10 }
    ctx.run("layout on")
    ctx.fire("PLAYER_LOGIN")
    local b = ctx.button()
    check("rod button: an uncached bag rod shows at login", rodState(b),
        "true | macro | /equipslot 16 item:10 | icon10")
    ctx.watch()
    ctx.env.C_Item.GetItemInfo = full
    ctx.fire("GET_ITEM_INFO_RECEIVED", 10, true)
    check("rod button: item info arriving refreshes it", table.concat(ctx.calls, " "):match("Show") ~= nil, true)
end

do
    local timers = {}
    local ctx = loadRodButton({ env = { C_Timer = { After = function(_, fn)
        timers[#timers + 1] = fn
    end } } })
    ctx.content[0] = { 10 }
    ctx.run("layout on")
    ctx.fire("PLAYER_LOGIN")
    ctx.watch()
    local updates = 0
    local b = ctx.button()
    local show = b.Show
    b.Show = function(self, ...)
        updates = updates + 1
        return show(self, ...)
    end
    for i = 1, 50 do
        ctx.fire("GET_ITEM_INFO_RECEIVED", i, true)
    end
    check("rod button: item info events wait for the next frame", updates, 0)
    local due = timers
    timers = {}
    for _, fn in ipairs(due) do
        fn()
    end
    check("rod button: many item info events run one update", updates, 1)
    ctx.fire("GET_ITEM_INFO_RECEIVED", 10, true)
    check("rod button: a later item info event schedules again", #timers, 1)
end

do
    local ctx = loadRodButton()
    local restoring = 0
    ctx.worn[16] = 10
    ctx.content[0] = { 7 }
    ctx.fire("PLAYER_LOGIN")
    ctx.addon.Rod.Restoring = function() restoring = restoring + 1 end
    local b = ctx.button()
    b.scripts.PreClick(b, "LeftButton", true)
    ctx.worn[16] = 7
    b.scripts.PreClick(b, "LeftButton", true)
    check("rod button: PreClick marks only a restore click", restoring, 1)
end

do
    local ctx = loadRodButton()
    ctx.env.EquipItemByName = nil
    ctx.content[0] = { 10 }
    ctx.fire("PLAYER_LOGIN")
    ctx.run("layout on")
    check("rod button: not ready makes no button", ctx.button(), nil)
    for _, need in ipairs({ "GetInventoryItemID", "InCombatLockdown", "SecureActionButtonMixin", "SecureCmdList" }) do
        local env = checkAPIs()
        env[need] = nil
        check(("fishing rod: not ready without %s"):format(need),
            loadWithDB(nil, "enUS", { env = env }).Check.Ready("Fishing rod"), false)
    end
    local env = checkAPIs()
    env.SecureCmdList, env.SLASH_EQUIP_TO_SLOT1 = nil, "/equipslot"
    env.SecureActionButtonMixin, env.SecureActionButton_OnClick = nil, function() end
    check("fishing rod: ready with the other alternatives",
        loadWithDB(nil, "enUS", { env = env }).Check.Ready("Fishing rod"), true)
    env = checkAPIs()
    env.EquipItemByName, env.C_Item.EquipItemByName = nil, function() end
    check("fishing rod: ready with only C_Item.EquipItemByName",
        loadWithDB(nil, "enUS", { env = env }).Check.Ready("Fishing rod"), true)
    env = checkAPIs()
    check("fishing rod: ready with only the global EquipItemByName",
        env.C_Item.EquipItemByName == nil and loadWithDB(nil, "enUS", { env = env }).Check.Ready("Fishing rod"), true)
    env = checkAPIs()
    env.EquipItemByName = nil
    check("fishing rod: not ready without either EquipItemByName",
        loadWithDB(nil, "enUS", { env = env }).Check.Ready("Fishing rod"), false)
    local addon, printed = loadWithDB(nil, "enUS", { env = checkAPIs() })
    check("check: fishing rod line", runCheck(addon, printed)["Fishing rod"],
        "Fishing rod: ok (GetInventoryItemID ok, C_Container.GetContainerItemID ok, GetContainerItemID missing, "
            .. "C_Container.GetContainerNumFreeSlots ok, GetContainerNumFreeSlots missing, InCombatLockdown ok, "
            .. "SecureActionButton_OnClick missing, SecureActionButtonMixin ok, SecureCmdList.EQUIP_TO_SLOT ok, "
            .. "SlashCmdList.EQUIP_TO_SLOT missing, SLASH_EQUIP_TO_SLOT1 missing, C_Item.EquipItemByName missing, "
            .. "EquipItemByName ok)")
end

do
    local ctx = loadRodButton({ locale = "zhTW" })
    ctx.worn[16], ctx.worn[17] = 7, 14
    ctx.content[0] = { 10 }
    ctx.bags[0][2], ctx.bags[1][2], ctx.bags[2][2] = 0, 0, 0
    ctx.fire("PLAYER_LOGIN")
    ctx.run("layout on")
    local b = ctx.button()
    b.scripts.OnEnter(b)
    check("zhTW rod button tooltip", ctx.tip.title .. " / " .. texts(ctx.tip),
        "魚竿 / 裝備 Item 10 / 背包已滿：沒有空間放副手 / 點擊裝備魚竿")
end

-- The rod button's debug lines: the check lines at login and on /tandem check, then rod login, layout and update
-- lines while recording, an update logged only when it changed; nothing while off.
local function debugText(env)
    return table.concat(env.TandemDebug and env.TandemDebug.log or {}, "\n")
end

do
    local ctx = loadRodButton()
    ctx.env.TandemDebug = { on = true, log = {} }
    ctx.worn[16], ctx.worn[17] = 7, 14
    ctx.content[0] = { 10 }
    ctx.fire("PLAYER_LOGIN")
    local text = debugText(ctx.env)
    check("rod debug: the fishing rod check line at login",
        text:match("check Fishing rod: ok %(GetInventoryItemID ok, ") ~= nil, true)
    check("rod debug: a probe line at login", text:match("probe LootButton1: missing") ~= nil, true)
    check("rod debug: the login line", text:match("rod login: ready=true button=made CreateFrame=function") ~= nil,
        true)
    ctx.run("layout on")
    local log = ctx.env.TandemDebug.log
    check("rod debug: the layout line", debugText(ctx.env):match("rod layout: on=true") ~= nil, true)
    check("rod debug: the update line", log[#log]:match("combat=false (.*)$"),
        "rod update: combat=false on=true rod=10 worn=false macro=/equipslot 16 item:10 shown=true point=-44,8")
    local n = #log
    ctx.fire("BAG_UPDATE_DELAYED")
    check("rod debug: an unchanged update is not logged again", #log, n)
    ctx.worn[16], ctx.worn[17] = 10, nil
    ctx.content[0] = { 7, 14 }
    ctx.fire("PLAYER_EQUIPMENT_CHANGED")
    check("rod debug: the macro's line breaks show as |", log[#log]:match("macro=(.-) shown"),
        "/equipslot 16 item:7|/equipslot 17 item:14")
    n = #log
    ctx.run("check")
    check("rod debug: /tandem check logs the check lines",
        table.concat(log, "\n", n + 1):match("check Fishing rod: ok") ~= nil, true)
end

do
    local ctx = loadRodButton()
    ctx.env.TandemDebug = { on = true, log = {} }
    local create = ctx.env.CreateFrame
    ctx.env.CreateFrame = function(kind, name, parent, template)
        if template == "SecureActionButtonTemplate" then
            error("blocked")
        end
        return create(kind, name, parent, template)
    end
    ctx.fire("PLAYER_LOGIN")
    local text = debugText(ctx.env)
    check("rod debug: a failing CreateFrame logs its error",
        text:match("rod login: CreateFrame failed: .*blocked") ~= nil, true)
    check("rod debug: and no button", text:match("rod login: ready=true button=none") ~= nil, true)
end

do
    local ctx = loadRodButton()
    ctx.content[0] = { 10 }
    ctx.fire("PLAYER_LOGIN")
    ctx.run("layout on")
    ctx.run("check")
    check("rod debug: nothing logged while off", ctx.env.TandemDebug == nil or #ctx.env.TandemDebug.log == 0, true)
end

-- Upgrade judge while fishing (U3): with the rod in the main hand no weapon-slot item is an upgrade, and those items
-- are judged again once the weapons are worn again. GetInventoryItemID reads the id from ctx.equipped's link.
do
    local ctx
    ctx = loadItemBorders({ env = { GetInventoryItemID = function(_, inv)
        local link = ctx.equipped[inv]
        return link and tonumber(link:match("item:(%d+)"))
    end } })
    local function wear(main, off)
        ctx.equipped[16] = main and ("|Hitem:" .. main .. ":|h") or nil
        ctx.equipped[17] = off and ("|Hitem:" .. off .. ":|h") or nil
        ctx.fire("PLAYER_EQUIPMENT_CHANGED")
    end
    local function show(items)
        local from = #ctx.printed
        local _, b = ctx.classic(1, 0, items)
        ctx.bagUpdate()
        return ctx.since(from), b
    end
    ctx.items[60] = { "INVTYPE_WEAPON", 2, 7 }
    ctx.cache[60] = { "Big Sword", nil, 3, 40, 30 }
    ctx.tips[60] = { "Big Sword", ctx.strength(40) }
    ctx.items[61] = { "INVTYPE_HEAD", 4, 4 }
    ctx.cache[61] = { "Helm", nil, 3, 40, 30 }
    ctx.tips[61] = { "Helm", ctx.strength(10) }
    wear(7, 5)
    show({ 9 })
    wear(10, nil)
    check("fishing: the rod worn is fishing", ctx.addon.Rod.Fishing(), true)
    local out = show({ 9, 7, 5 })
    check("fishing: the weapons taken off print nothing", #out, 0)
    local b
    out, b = show({ 9, 7, 5, 60, 61 })
    check("fishing: only the helm prints while fishing", #out, 1)
    check("fishing: the helm line", out[1], upgradeLine("Head", 61, BLUE, 10, 0))
    check("fishing: a better weapon gets no border", ctx.border(b[4]), "none")
    check("fishing: the sword gets no border", ctx.border(b[2]), "none")
    check("fishing: the off hand gets no border", ctx.border(b[3]), "none")
    check("fishing: the helm still gets a border", ctx.border(b[5]), "red")
    check("fishing: a better weapon is not an upgrade", ctx.addon.Upgrade.Better(60), false)
    wear(7, 5)
    out, b = show({ 9, 10, 60, 61 })
    check("fishing: after the swap back the better weapon prints once", #out, 1)
    check("fishing: the weapon line", out[1], upgradeLine("Main hand", 60, BLUE, 40, 20))
    check("fishing: after the swap back the better weapon gets a border", ctx.border(b[3]), "red")
    check("fishing: the next bag update prints nothing", #show({ 9, 10, 60, 61 }), 0)
    wear(10, nil)
    ctx.addon.Rod = nil
    check("fishing: no Rod module judges weapons as before", ctx.addon.Upgrade.Better(60), true)
end

-- U3: an item still loading when looted while fishing is deferred when its info arrives, and alerts after the swap.
do
    local ctx
    ctx = loadUpgrade({ env = { GetInventoryItemID = function(_, inv)
        local link = ctx.equipped[inv]
        return link and tonumber(link:match("item:(%d+)"))
    end } })
    local function wear(main, off)
        ctx.equipped[16] = main and ("|Hitem:" .. main .. ":|h") or nil
        ctx.equipped[17] = off and ("|Hitem:" .. off .. ":|h") or nil
        ctx.fire("PLAYER_EQUIPMENT_CHANGED")
    end
    ctx.items[62] = { "INVTYPE_WEAPON", 2, 7 }
    ctx.tips[62] = { "Late Sword", ctx.strength(40) }
    wear(7, 5)
    ctx.bagUpdate()
    wear(10, nil)
    ctx.bags[0] = { 7, 5 }
    ctx.bagUpdate()
    check("fishing info: a loading weapon prints nothing", #ctx.loot(62), 0)
    ctx.cache[62] = { "Late Sword", nil, 3, 40, 30 }
    local from = #ctx.printed
    ctx.fire("GET_ITEM_INFO_RECEIVED", 62, true)
    check("fishing info: its info arriving while fishing prints nothing", #ctx.since(from), 0)
    wear(7, 5)
    ctx.bags[0] = { 10, 62 }
    from = #ctx.printed
    ctx.bagUpdate()
    local out = ctx.since(from)
    check("fishing info: after the swap back it prints once", #out, 1)
    check("fishing info: the weapon line", out[1], upgradeLine("Main hand", 62, BLUE, 40, 20))
end

if failures > 0 then
    os.exit(1)
end
