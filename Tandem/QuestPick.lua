local _, ns = ...

-- Marks the best quest reward choice on turn-in (decision 3): among the choices the player can use, the one that
-- strictly beats every other by item level, then quality, gets a small Tandem icon on its button. Advises only: the
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

-- Returns the item's record, a client-built one, false when it is not equippable (or unknown), or nil while the
-- client has not loaded it.
local function recordOf(id)
    local r = ns.Advisor.Item(id)
    if r then
        return r
    end
    local equipLoc, classID, subclassID = ns.Scanner.Equippable(id)
    if not equipLoc then
        return false
    end
    local name, _, quality, ilvl, reqLevel = C_Item.GetItemInfo(id)
    name, quality, ilvl, reqLevel = Safe(name), Safe(quality), Safe(ilvl), Safe(reqLevel)
    if type(name) ~= "string" or type(ilvl) ~= "number" then
        return nil
    end
    return { ilvl, type(reqLevel) == "number" and reqLevel or 1, type(quality) == "number" and quality or 1,
             equipLoc, classID, subclassID }
end

-- QuestPick.Pick(ids, class, level) -> index, pending
-- Returns the index of the usable choice that beats every other usable one by item level, then quality; nil on a
-- tie or when none is usable. pending lists the ids not loaded yet, and while any is, nothing is picked.
function QuestPick.Pick(ids, class, level)
    local best, bestIndex, tied, pending = nil, nil, false, {}
    for i, id in ipairs(ids) do
        local r = id and recordOf(id)
        if r == nil and id then
            pending[#pending + 1] = id
        elseif r and ns.Advisor.Usable(r, class, level) then
            if not best or r[1] > best[1] or (r[1] == best[1] and r[3] > best[3]) then
                best, bestIndex, tied = r, i, false
            elseif r[1] == best[1] and r[3] == best[3] then
                tied = true
            end
        end
    end
    if #pending > 0 or tied then
        return nil, pending
    end
    return bestIndex, pending
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
