local _, ns = ...

-- Display helpers shared by the slash command and the judges: the player, slot labels, item links and scores.
local View = {}
ns.View = View

local L = ns.L
local Safe = ns.Store.Safe

View.SLOT_LABELS = {
    head = "Head", neck = "Neck", shoulder = "Shoulder", back = "Back", chest = "Chest", wrist = "Wrist",
    hands = "Hands", waist = "Waist", legs = "Legs", feet = "Feet", finger = "Finger", trinket = "Trinket",
    mainhand = "Main hand", offhand = "Off hand", twohand = "Two-hand", ranged = "Ranged",
}

local QUALITY_HEX = {
    [0] = "9d9d9d", "ffffff", "1eff00", "0070dd", "a335ee", "ff8000", "e6cc80", "00ccff",
}

local requested = {}

-- Prints the refusal and returns true while in combat (decision 9).
function View.InCombat()
    if InCombatLockdown and InCombatLockdown() then
        print(L["Tandem: not available in combat"])
        return true
    end
    return false
end

-- Returns the player's localised class name, class file and level, or nil when the client hides any of them; says
-- so unless quiet.
function View.Player(quiet)
    local name, classFile, level
    if UnitClass then
        name, classFile = UnitClass("player")
        name, classFile = Safe(name), Safe(classFile)
    end
    if UnitLevel then
        level = Safe(UnitLevel("player"))
    end
    if type(classFile) ~= "string" or type(level) ~= "number" or level < 1 then
        if not quiet then
            print(L["Tandem: your class or level is not known yet; try again in a moment"])
        end
        return nil
    end
    return type(name) == "string" and name or classFile, classFile, level
end

-- Asks the client to load an item, once per session.
function View.RequestItem(id)
    if not requested[id] and C_Item and C_Item.RequestLoadItemDataByID then
        requested[id] = true
        C_Item.RequestLoadItemDataByID(id)
    end
end

-- Returns the client's link for an item when cached; else builds one from the id in its quality colour and asks
-- the client to load the item for next time.
function View.ItemLink(id, quality)
    if C_Item and C_Item.GetItemInfo then
        local name, link = C_Item.GetItemInfo(id)
        link = Safe(link)
        if type(link) == "string" then
            return link
        end
        if Safe(name) == nil then
            View.RequestItem(id)
        end
    end
    return ("|cff%s|Hitem:%d::::::::::::::|h[%s]|h|r"):format(QUALITY_HEX[quality] or QUALITY_HEX[1], id,
        L["item #%d"]:format(id))
end

function View.SlotLabel(slot)
    return L[View.SLOT_LABELS[slot]]
end

-- Returns a stat score as shown beside an item, one decimal; "" for an item without stats (nil).
function View.ScoreText(score)
    return score and ("%.1f"):format(score) or ""
end
