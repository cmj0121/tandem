local _, ns = ...

-- Marks the best quest reward choice on turn-in (decision 3, rule D2 of stage 11): among the choices the player can
-- use, the one that strictly beats every other by stat score when every one has stats, ties and stat-less choices by
-- item level, then quality, gets a small Tandem icon on its button. Advises only: the
-- icon is a child texture of the reward button, nothing is selected, and nothing happens in combat or when the
-- client lacks the quest API or the reward buttons.
local QuestPick = {}
ns.QuestPick = QuestPick

local Safe = ns.Store.Safe

local ICON = "Interface\\AddOns\\Tandem\\Media\\icon"
local MARK_SIZE = 16

local open = false
local waiting = {}
local marks = {}
local shown

local function choiceID(i)
    local link = Safe(GetQuestItemLink("choice", i))
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

-- Returns the index of the strict winner among choices { index, ilvl, quality, score }, or nil on a tie: by score
-- when every choice has one, then item level, then quality.
local function winner(choices)
    local scored = true
    for _, c in ipairs(choices) do
        scored = scored and c.score ~= nil
    end
    local function cmp(a, b)
        if scored and a.score ~= b.score then
            return a.score - b.score
        end
        return a.ilvl ~= b.ilvl and a.ilvl - b.ilvl or a.quality - b.quality
    end
    local best, tied
    for _, c in ipairs(choices) do
        local d = best and cmp(c, best)
        if not best or d > 0 then
            best, tied = c, false
        elseif d == 0 then
            tied = true
        end
    end
    return best and not tied and best.index or nil
end

-- QuestPick.Pick(ids, class, level) -> index, pending
-- Returns the index of the usable choice that strictly beats every other usable one, from live item data: by stat
-- score when every usable choice has one, ties by item level, then quality; else by item level, then quality; nil on
-- a remaining tie or when none is usable. A choice with a red tooltip line is not usable. pending lists the ids not
-- loaded yet, and while any is, nothing is picked.
function QuestPick.Pick(ids, class, level)
    local Items = ns.Items
    local choices, pending = {}, {}
    for i, id in ipairs(ids) do
        local info = id and Items.Info(id)
        if info == nil and id then
            pending[#pending + 1] = id
        elseif info and Items.Usable(info, class, level) then
            local blocked = ns.StatSearch.Blocked(id)
            if blocked == nil then
                pending[#pending + 1] = id
            elseif not blocked then
                choices[#choices + 1] = { index = i, ilvl = info[1], quality = info[3],
                                          score = Items.Score(id, class, level) }
            end
        end
    end
    if #pending > 0 then
        return nil, pending
    end
    return winner(choices), pending
end

-- Returns the reward button of choice i: a choice button in QuestInfoRewardsFrame.RewardButtons, else the named
-- button; nil when none is found.
local function buttonFor(i)
    local list = type(QuestInfoRewardsFrame) == "table" and QuestInfoRewardsFrame.RewardButtons
    if type(list) == "table" then
        for _, b in ipairs(list) do
            if type(b) == "table" and b.type == "choice" and b.GetID and b:GetID() == i then
                return b
            end
        end
        local b = list[i]
        if type(b) == "table" and b.type == nil then
            return b
        end
    end
    return _G["QuestInfoRewardsFrameQuestInfoItem" .. i] or _G["QuestRewardItem" .. i]
end

local function markOn(button)
    local mark = marks[button]
    if not mark then
        mark = button:CreateTexture(nil, "OVERLAY")
        mark:SetSize(MARK_SIZE, MARK_SIZE)
        mark:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
        mark:SetTexture(ICON)
        marks[button] = mark
    end
    mark:Show()
    shown = mark
end

local function hideMark()
    if shown then
        shown:Hide()
        shown = nil
    end
end

local function evaluate()
    hideMark()
    waiting = {}
    if InCombatLockdown and InCombatLockdown() then
        return
    end
    local _, class, level = ns.View.Player(true)
    local n = Safe(GetNumQuestChoices())
    if not class or type(n) ~= "number" or n < 2 then
        return
    end
    local ids = {}
    for i = 1, n do
        ids[i] = choiceID(i) or false
    end
    local index, pending = QuestPick.Pick(ids, class, level)
    for _, id in ipairs(pending) do
        waiting[id] = true
        if C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(id)
        end
    end
    local button = index and buttonFor(index)
    if button and button.CreateTexture then
        markOn(button)
    end
end

-- QUEST_COMPLETE: marks the best choice of the reward window.
function QuestPick.OnQuestComplete()
    if not (ns.Check.Ready("Quest reward pick") and C_Item and C_Item.GetItemInfo) then
        return
    end
    open = true
    evaluate()
end

-- GET_ITEM_INFO_RECEIVED: judges the choices again once a choice it waits for arrives.
function QuestPick.OnItemInfo(id)
    id = Safe(id)
    if open and id and waiting[id] then
        evaluate()
    end
end

-- QUEST_FINISHED: the reward window closed; drops the mark.
function QuestPick.OnQuestFinished()
    open = false
    waiting = {}
    hideMark()
end
