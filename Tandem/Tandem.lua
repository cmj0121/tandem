local addonName, ns = ...

ns.name = addonName

local frame = CreateFrame("Frame")
for _, event in ipairs({
    "ADDON_LOADED", "GET_ITEM_INFO_RECEIVED", "LOOT_READY", "LOOT_OPENED", "QUEST_COMPLETE", "QUEST_FINISHED",
    "TRAINER_SHOW", "TRAINER_UPDATE", "PLAYER_LOGIN", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED",
    "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD",
    "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "SPELLS_CHANGED",
    "LEARNED_SPELL_IN_TAB", "LEARNED_SPELL_IN_SKILL_LINE", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED",
    "EDIT_MODE_LAYOUTS_UPDATED", "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION",
    "PLAYER_TOTEM_UPDATE", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA",
    "TIME_PLAYED_MSG", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN",
}) do
    ns.Store.RegisterEvent(frame, event)
end
-- The class area's unit events, for the player only where the client allows it.
local PLAYER_EVENTS = { UNIT_POWER_UPDATE = true, UNIT_MAXPOWER = true }
for event in pairs(PLAYER_EVENTS) do
    ns.Store.RegisterUnitEvent(frame, event, "player")
end

local function onLoaded(self, event, loadedName)
    if loadedName ~= addonName then
        return
    end

    self:UnregisterEvent(event)
    local L = ns.L
    local db, report = ns.Store.Load(TandemDB)
    TandemDB = db
    print(L["%s loaded"]:format(addonName))

    if report.status == "newer" then
        print(L["%s: saved data uses newer schema %d; recording is off until the addon is updated"]:format(
            addonName, report.version))
    elseif report.status == "migrated" and type(report.version) == "number" and report.version >= 0
        and report.version < math.huge and report.version == math.floor(report.version)
        and (report.version < 6 or report.dropped > 0) then
        print(L["%s: saved data upgraded from schema %d to %d"]:format(addonName, report.version, ns.Store.SCHEMA))
    elseif report.status == "reset" then
        print(L["%s: saved data was unreadable and has been reset"]:format(addonName))
    end
    if report.dropped > 0 then
        print(L["%s: dropped %d invalid or unused saved entries"]:format(addonName, report.dropped))
    end
end

frame:SetScript("OnEvent", function(self, event, ...)
    if PLAYER_EVENTS[event] or event == "PLAYER_TOTEM_UPDATE" then
        ns.ClassArea.OnEvent(event, ...)
    elseif event == "ADDON_LOADED" then
        onLoaded(self, event, ...)
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        ns.QuestPick.OnItemInfo(...)
        if ns.Upgrade.OnItemInfo(...) then
            ns.ItemBorders.Schedule()
        end
        ns.Rod.Schedule()
    elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
        ns.ItemBorders.Schedule()
    elseif event == "QUEST_COMPLETE" then
        ns.QuestPick.OnQuestComplete()
    elseif event == "QUEST_FINISHED" then
        ns.QuestPick.OnQuestFinished()
    elseif event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then
        ns.Trainer.OnTrainer()
        ns.ActionBorders.Schedule()
    elseif event == "SKILL_LINES_CHANGED" then
        if ns.Upgrade.OnSkillLines() then
            ns.ItemBorders.Schedule()
        end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        ns.Upgrade.Invalidate()
        ns.ItemBorders.Schedule()
        ns.Rod.Remember()
        ns.Rod.Update()
    elseif event == "BAG_UPDATE_DELAYED" then
        ns.Upgrade.OnBagUpdate()
        ns.ItemBorders.Schedule()
        -- After the bag row, whose new width places the rod button.
        ns.BagButton.Update()
        ns.Rod.Update()
    elseif event == "PLAYER_LOGIN" then
        ns.ActionBorders.Schedule()
        ns.ItemBorders.OnLogin()
        ns.Layout.Sync()
        ns.Launcher.OnLogin()
        ns.Debug.OnLogin()
        ns.BagButton.OnLogin()
        ns.Rod.OnLogin()
        ns.MapInfo.OnLogin()
        -- A fresh login shows Blizzard's status bars after the layout attached; fade them again once it settles.
        if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
            C_Timer.After(3, ns.Layout.Refade)
        end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ACTIONBAR_SLOT_CHANGED" or event == "ACTIONBAR_PAGE_CHANGED"
        or event == "UPDATE_BONUS_ACTIONBAR" or event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB"
        or event == "LEARNED_SPELL_IN_SKILL_LINE" or event == "PLAYER_LEVEL_UP" then
        if event == "PLAYER_ENTERING_WORLD" then
            ns.Layout.Refade()
        end
        if event == "PLAYER_LEVEL_UP" then
            ns.XPBar.Update(...)
            ns.MapInfo.OnLevelUp()
            ns.Upgrade.Invalidate()
            ns.ItemBorders.Schedule()
        end
        ns.ActionBorders.Schedule()
    elseif event == "PLAYER_REGEN_ENABLED" then
        ns.Upgrade.OnCombatEnd()
        ns.ActionBorders.Schedule()
        ns.Layout.OnCombatEnd()
        ns.BagButton.OnCombatEnd()
        ns.Rod.OnCombatEnd()
    elseif event == "EDIT_MODE_LAYOUTS_UPDATED" then
        ns.Layout.Sync()
    elseif event == "PLAYER_XP_UPDATE" or event == "UPDATE_EXHAUSTION" then
        ns.XPBar.Update()
        ns.MapInfo.Update()
    elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" or event == "ZONE_CHANGED_NEW_AREA" then
        ns.MapInfo.Update()
    elseif event == "TIME_PLAYED_MSG" then
        ns.MapInfo.OnTimePlayed(...)
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        ns.Debug.OnBlocked(event, ...)
    end
end)
