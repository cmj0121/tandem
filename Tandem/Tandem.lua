local addonName, ns = ...

ns.name = addonName

local frame = CreateFrame("Frame")
for _, event in ipairs({
    "ADDON_LOADED", "GET_ITEM_INFO_RECEIVED", "LOOT_READY", "LOOT_OPENED", "QUEST_COMPLETE", "QUEST_FINISHED",
    "TRAINER_SHOW", "TRAINER_UPDATE", "PLAYER_LOGIN", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED",
    "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_ENTERING_WORLD",
    "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "SPELLS_CHANGED",
    "LEARNED_SPELL_IN_TAB", "LEARNED_SPELL_IN_SKILL_LINE", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED",
    "EDIT_MODE_LAYOUTS_UPDATED", "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION",
    "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA",
    "TIME_PLAYED_MSG", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "CVAR_UPDATE", "QUEST_TURNED_IN",
    "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED",
}) do
    ns.Store.RegisterEvent(frame, event)
end
-- The eat button's unit events, for the player only where the client allows it.
local PLAYER_EVENTS = { UNIT_POWER_UPDATE = true, UNIT_MAXPOWER = true }
for event in pairs(PLAYER_EVENTS) do
    ns.Store.RegisterUnitEvent(frame, event, "player")
end

-- The events the weapon enchant proc icon counts from, forwarded to Procs.OnEvent.
local PROC_EVENTS = { PLAYER_EQUIPMENT_CHANGED = true }
for _, event in ipairs(ns.Procs.EVENTS) do
    PROC_EVENTS[event] = true
end

-- The recall check (D3): once per frame however many cooldown events arrive, Flyout.Update only when the recall
-- state differs from the one it last applied (SPELL_UPDATE_COOLDOWN fires on every global cooldown); while Astral
-- Recall is on cooldown a timer checks again when it ends. One that runs in combat leaves the change to Flyout's
-- combat end, and PLAYER_REGEN_ENABLED checks again.
-- Right after the teleport's loading screen the client reads Astral Recall ready for a moment, then on cooldown again
-- (seen in game 2026-11-17). So a ready read well before the known end is trusted only when it still reads ready
-- RECALL_CONFIRM seconds later; a real reset (RECALL_EARLY seconds or more before the end) is applied then.
local RECALL_EARLY, RECALL_CONFIRM = 1, 0.5
local recallQueued, recallTimerAt, recallReadyAt, recallDoubtAt

local function timerAfter(delay, fn)
    return type(C_Timer) == "table" and type(C_Timer.After) == "function" and pcall(C_Timer.After, delay, fn)
end

local function checkRecall()
    recallQueued = false
    local state, readyAt = ns.ClassMacros.RecallState()
    local now = ns.Store.Call(GetTime)
    if type(now) ~= "number" then
        now = nil
    end
    if state == "spell" and recallReadyAt and now and now < recallReadyAt - RECALL_EARLY then
        recallDoubtAt = recallDoubtAt or now
        -- The timer fires about RECALL_CONFIRM later; a tenth's slack so its own check is not doubted again.
        if now < recallDoubtAt + RECALL_CONFIRM * 0.9 and timerAfter(RECALL_CONFIRM, checkRecall) then
            return
        end
    end
    recallDoubtAt = nil
    if state == "item" then
        recallReadyAt = readyAt
    elseif state == "spell" then
        recallReadyAt = nil
    end
    if state ~= ns.Flyout.RecallApplied() then
        ns.Flyout.Update()
    end
    if state == "item" and readyAt ~= recallTimerAt and now then
        recallTimerAt = readyAt
        if not timerAfter(math.max(0, readyAt - now), function()
            recallTimerAt = nil
            checkRecall()
        end) then
            recallTimerAt = nil
        end
    end
end

local function scheduleRecall()
    if recallQueued then
        return
    end
    recallQueued = true
    if not timerAfter(0, checkRecall) then
        checkRecall()
    end
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
    -- The proc probe's candidates, some also handled below (PLAYER_LEAVE_COMBAT is not, nor are the chat lines).
    ns.ProcProbe.OnEvent(event, ...)
    ns.KillerProbe.OnEvent(event, ...)
    ns.RangeProbe.OnEvent(event, ...)
    ns.MaelstromProbe.OnEvent(event, ...)
    ns.Maelstrom.OnEvent(event, ...)
    ns.RangeText.OnEvent(event, ...)
    ns.Killers.OnEvent(event, ...)
    if PROC_EVENTS[event] then
        ns.Procs.OnEvent(event, ...)
    end
    if PLAYER_EVENTS[event] then
        if (...) == "player" then
            ns.Eat.Schedule()
        end
    elseif event == "ADDON_LOADED" then
        onLoaded(self, event, ...)
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        ns.QuestPick.OnItemInfo(...)
        if ns.Upgrade.OnItemInfo(...) then
            ns.ItemBorders.Schedule()
        end
        ns.Rod.Schedule()
        ns.Eat.Invalidate()
        ns.Eat.Schedule()
    elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
        ns.ItemBorders.Schedule()
    elseif event == "QUEST_COMPLETE" then
        ns.QuestPick.OnQuestComplete()
    elseif event == "QUEST_FINISHED" then
        ns.QuestPick.OnQuestFinished()
    elseif event == "QUEST_TURNED_IN" then
        -- A library book turned in (library books D5) dims its pins and leaves the alert.
        if ns.Books.OnQuestTurnedIn((...)) then
            ns.BookPins.Refresh()
            ns.BookAlert.Update()
        end
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
        ns.Eat.Rescan()
    elseif event == "PLAYER_LOGIN" then
        ns.ActionBorders.Schedule()
        ns.ItemBorders.OnLogin()
        ns.Layout.Sync()
        ns.Launcher.OnLogin()
        ns.Debug.OnLogin()
        ns.ProcProbe.OnLogin(self)
        ns.KillerProbe.OnLogin(self)
        ns.RangeProbe.OnLogin(self)
        ns.MaelstromProbe.OnLogin(self)
        ns.ManaProbe.OnLogin()
        ns.Maelstrom.OnLogin(self)
        ns.RangeText.OnLogin(self)
        ns.Killers.OnLogin(self)
        ns.Procs.OnLogin(self)
        ns.FiveSecond.OnLogin()
        ns.BagButton.OnLogin()
        -- Before the rod button, whose first update places the class macro button. Aura events only once it exists.
        if ns.Flyout.OnLogin() then
            ns.Store.RegisterEvent(self, "UNIT_AURA")
            ns.Store.RegisterEvent(self, "GROUP_ROSTER_UPDATE")
            ns.Store.RegisterEvent(self, "SPELL_UPDATE_COOLDOWN")
            scheduleRecall()
        end
        -- Before the rod button too, whose update places it left of the class macro button.
        ns.Mute.OnLogin()
        -- After the mute button, whose place it follows; before the rod button, whose update places both again.
        ns.Role.OnLogin()
        -- After the layout mode button, whose place it follows; its aura event only once it exists.
        if ns.Eat.OnLogin() then
            ns.Store.RegisterEvent(self, "UNIT_AURA")
        end
        ns.Rod.OnLogin()
        ns.MapInfo.OnLogin()
        ns.BookPins.OnLogin()
        ns.BookAlert.OnLogin()
        -- A fresh login shows Blizzard's status bars after the layout attached; fade them again once it settles.
        if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
            C_Timer.After(3, ns.Layout.Refade)
        end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ACTIONBAR_SLOT_CHANGED" or event == "ACTIONBAR_PAGE_CHANGED"
        or event == "UPDATE_BONUS_ACTIONBAR" or event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB"
        or event == "LEARNED_SPELL_IN_SKILL_LINE" or event == "PLAYER_LEVEL_UP" then
        if event ~= "ACTIONBAR_SLOT_CHANGED" and event ~= "ACTIONBAR_PAGE_CHANGED"
            and event ~= "UPDATE_BONUS_ACTIONBAR" then
            -- A spell learned shows its class macro, which may show the button and move the mute button.
            ns.Flyout.Update()
            ns.Mute.Update()
            ns.Role.Update()
            if event == "SPELLS_CHANGED" and ns.Flyout.Made() then
                scheduleRecall()
            end
        end
        if event == "PLAYER_ENTERING_WORLD" then
            ns.Layout.Refade()
            ns.BookAlert.Update()
        end
        if event == "PLAYER_LEVEL_UP" then
            ns.XPBar.Update(...)
            ns.MapInfo.OnLevelUp()
            ns.BookPins.Refresh(...)
            ns.BookAlert.Update(...)
            ns.Eat.Rescan()
            ns.Weights.OnTalents()
            ns.Upgrade.Invalidate()
            ns.ItemBorders.Schedule()
        end
        ns.ActionBorders.Schedule()
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- A talent walk that failed in combat may try again (D4).
        ns.Weights.OnTalents()
        ns.Upgrade.OnCombatEnd()
        ns.ActionBorders.Schedule()
        ns.Layout.OnCombatEnd()
        ns.BagButton.OnCombatEnd()
        ns.Rod.OnCombatEnd()
        ns.Flyout.OnCombatEnd()
        if ns.Flyout.Made() then
            scheduleRecall()
        end
        ns.Mute.OnCombatEnd()
        ns.Debug.OnCombatEnd()
        ns.Role.OnCombatEnd()
        ns.Eat.OnCombatEnd()
        ns.BookAlert.OnCombatEnd()
    elseif event == "TRAIT_CONFIG_UPDATED" or event == "PLAYER_TALENT_UPDATE"
        or event == "CHARACTER_POINTS_CHANGED" then
        -- Talents changed: the C_Traits tab is walked again and the upgrade verdicts judged again (D4). Which event
        -- Forever fires is logged to confirm in game.
        if ns.Debug.IsOn() then
            ns.Debug.Log("spec event " .. event)
        end
        ns.Weights.OnTalents()
        ns.Upgrade.Invalidate()
        ns.ItemBorders.Schedule()
    elseif event == "PLAYER_REGEN_DISABLED" then
        ns.Flyout.OnCombatStart()
        ns.BookAlert.OnCombatStart()
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        scheduleRecall()
    elseif event == "EDIT_MODE_LAYOUTS_UPDATED" then
        ns.Layout.Sync()
    elseif event == "PLAYER_XP_UPDATE" or event == "UPDATE_EXHAUSTION" then
        ns.XPBar.Update()
        ns.MapInfo.Update()
    elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" or event == "ZONE_CHANGED_NEW_AREA" then
        ns.MapInfo.Update()
        ns.BookAlert.Update()
    elseif event == "TIME_PLAYED_MSG" then
        ns.MapInfo.OnTimePlayed(...)
    elseif event == "UNIT_AURA" or event == "GROUP_ROSTER_UPDATE" then
        ns.Cure.Scan(event == "UNIT_AURA" and (...) or nil)
        if event == "UNIT_AURA" and (...) == "player" then
            ns.Eat.Schedule()
        end
    elseif event == "CVAR_UPDATE" then
        ns.Mute.Refresh()
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        ns.Debug.OnBlocked(event, ...)
    end
end)
