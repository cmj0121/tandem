local _, ns = ...

-- Records equippable quest rewards (kind "q", id = questID) and merchant items (kind "v", id = merchant npcID) as
-- gear sources, and caches their item records, now or once GET_ITEM_INFO_RECEIVED brings them.
local Sources = {}
ns.Sources = Sources

local QUEST_LISTS = { "choice", "reward" }

local Safe = ns.Store.Safe

-- Items waiting for their info: [id] = { equipLoc, classID, subclassID }.
local pending = {}

local function blocked()
    return ns.Store.readOnly or (InCombatLockdown and InCombatLockdown())
end

-- Returns the player's Store.FACTIONS bit, or nil (neutral, unknown or no API).
local function playerFaction()
    if not UnitFactionGroup then
        return nil
    end
    local faction = Safe(UnitFactionGroup("player"))
    return faction and ns.Store.FACTIONS[faction]
end

local function count(fn)
    local n = fn and Safe(fn())
    return type(n) == "number" and n or 0
end

local function linkID(link)
    link = Safe(link)
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

-- Records the linked item under kind/id when it is equippable and caches its record; true when equippable.
local function record(link, kind, id, faction, map, x, y)
    local item = linkID(link)
    if not item then
        return false
    end
    local equipLoc, classID, subclassID = ns.Scanner.Equippable(item)
    if not equipLoc then
        return false
    end
    ns.Store.AddSource(item, kind, id, map, x, y, faction)
    if not (ns.Store.db.items[item] or pending[item])
        and ns.Scanner.CacheItem(item, equipLoc, classID, subclassID) == nil then
        pending[item] = { equipLoc, classID, subclassID }
        if C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(item)
        end
    end
    return true
end

-- QUEST_DETAIL, QUEST_COMPLETE: records the shown quest's equippable choice and reward items, and its name.
function Sources.OnQuest()
    if blocked() or not (GetQuestID and GetQuestItemLink) then
        return
    end
    local faction, quest = playerFaction(), Safe(GetQuestID())
    if not faction or type(quest) ~= "number" or quest < 1 then
        return
    end
    local map, x, y = ns.Loot.PlayerPosition()
    local any = false
    for _, list in ipairs(QUEST_LISTS) do
        for i = 1, count(list == "choice" and GetNumQuestChoices or GetNumQuestRewards) do
            any = record(GetQuestItemLink(list, i), "q", quest, faction, map, x, y) or any
        end
    end
    if any and GetTitleText then
        ns.Store.SetQuestName(quest, Safe(GetTitleText()))
    end
end

-- MERCHANT_SHOW, MERCHANT_UPDATE: records the merchant's equippable items under its npc, and its name. Links can
-- arrive late, so each update records what the first pass missed.
function Sources.OnMerchant()
    if blocked() or not (UnitGUID and GetMerchantNumItems and GetMerchantItemLink) then
        return
    end
    local faction = playerFaction()
    local kind, npc = ns.Store.ParseGUID(Safe(UnitGUID("npc")))
    if not faction or kind ~= "c" then
        return
    end
    local map, x, y = ns.Loot.PlayerPosition()
    local any = false
    for i = 1, count(GetMerchantNumItems) do
        any = record(GetMerchantItemLink(i), "v", npc, faction, map, x, y) or any
    end
    if any and UnitName then
        ns.Store.SetNpcName(npc, Safe(UnitName("npc")))
    end
end

-- GET_ITEM_INFO_RECEIVED: caches a pending item; other queries are ignored.
function Sources.OnItemInfo(id, success)
    id = Safe(id)
    local entry = id and pending[id]
    if not entry then
        return
    end
    pending[id] = nil
    if Safe(success) ~= false then
        ns.Scanner.CacheItem(id, entry[1], entry[2], entry[3])
    end
end
