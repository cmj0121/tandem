local addonName, ns = ...

ns.name = addonName

local frame = CreateFrame("Frame")
for _, event in ipairs({
    "ADDON_LOADED", "GET_ITEM_INFO_RECEIVED", "LOOT_READY", "LOOT_CLOSED", "QUEST_DETAIL", "QUEST_COMPLETE",
    "QUEST_FINISHED", "MERCHANT_SHOW", "MERCHANT_UPDATE", "TRAINER_SHOW", "TRAINER_UPDATE", "PLAYER_REGEN_DISABLED",
    "PLAYER_LOGIN", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD",
    "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "SPELLS_CHANGED",
    "LEARNED_SPELL_IN_TAB", "LEARNED_SPELL_IN_SKILL_LINE", "PLAYER_LEVEL_UP",
}) do
    ns.Store.RegisterEvent(frame, event)
end

local function onLoaded(self, event, loadedName)
    if loadedName ~= addonName then
        return
    end

    self:UnregisterEvent(event)
    local L = ns.L
    local db, report = ns.Store.Load(TandemDB)
    TandemDB = db
    ns.Kills.Register(self)
    print(L["%s loaded"]:format(addonName))

    if report.status == "newer" then
        print(L["%s: saved data uses newer schema %d; recording is off until the addon is updated"]:format(
            addonName, report.version))
    elseif report.status == "migrated" and type(report.version) == "number" and report.version >= 0
        and report.version < math.huge and report.version == math.floor(report.version) then
        print(L["%s: saved data upgraded from schema %d to %d"]:format(addonName, report.version, ns.Store.SCHEMA))
    elseif report.status == "reset" then
        print(L["%s: saved data was unreadable and has been reset"]:format(addonName))
    end
    if report.dropped > 0 then
        print(L["%s: dropped %d invalid saved entries"]:format(addonName, report.dropped))
    end
end

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        onLoaded(self, event, ...)
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        ns.Scanner.OnItemInfo(...)
        ns.Browse.OnItemInfo(...)
        ns.Sources.OnItemInfo(...)
        ns.QuestPick.OnItemInfo(...)
        if ns.Upgrade.OnItemInfo(...) then
            ns.ItemBorders.Schedule()
        end
    elseif event == "LOOT_READY" then
        ns.Loot.OnLootReady()
    elseif event == "LOOT_CLOSED" then
        ns.Loot.OnLootClosed()
    elseif event == "QUEST_DETAIL" then
        ns.Sources.OnQuest()
    elseif event == "QUEST_COMPLETE" then
        ns.Sources.OnQuest()
        ns.QuestPick.OnQuestComplete()
    elseif event == "QUEST_FINISHED" then
        ns.QuestPick.OnQuestFinished()
    elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
        ns.Sources.OnMerchant()
    elseif event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then
        ns.Trainer.OnTrainer()
        ns.ActionBorders.Schedule()
    elseif event == "PLAYER_REGEN_DISABLED" then
        ns.Browse.OnCombat()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        ns.Upgrade.Invalidate()
        ns.ItemBorders.Schedule()
        ns.Browse.OnEquipmentChanged()
    elseif event == "BAG_UPDATE_DELAYED" then
        ns.Upgrade.OnBagUpdate()
        ns.ItemBorders.Schedule()
    elseif event == "PLAYER_LOGIN" then
        ns.Launcher.OnLogin()
        ns.ActionBorders.Schedule()
        ns.ItemBorders.OnLogin()
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ACTIONBAR_SLOT_CHANGED" or event == "ACTIONBAR_PAGE_CHANGED"
        or event == "UPDATE_BONUS_ACTIONBAR" or event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB"
        or event == "LEARNED_SPELL_IN_SKILL_LINE" or event == "PLAYER_LEVEL_UP" then
        ns.ActionBorders.Schedule()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        ns.Kills.OnCombatLog()
    elseif event == "PLAYER_REGEN_ENABLED" then
        ns.Kills.Flush(false)
        ns.Upgrade.OnCombatEnd()
        ns.ActionBorders.Schedule()
    elseif event == "PLAYER_LOGOUT" then
        ns.Kills.Flush(true)
    end
end)
