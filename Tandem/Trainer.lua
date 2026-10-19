local _, ns = ...

-- Records the spells a class trainer teaches, keyed by spell ID, with their required level and rank (decision 4).
local Trainer = {}
ns.Trainer = Trainer

local Safe = ns.Store.Safe

local function blocked()
    return ns.Store.readOnly or (InCombatLockdown and InCombatLockdown())
end

-- Returns the service's numeric spell ID from its tooltip data, or nil.
local function spellID(i)
    local data = Safe(C_TooltipInfo.GetTrainerService(i))
    local id = type(data) == "table" and Safe(data.id) or nil
    return type(id) == "number" and id or nil
end

-- Returns the first integer in the rank text ("Rank 3" -> 3), or nil.
local function rankOf(text)
    text = Safe(text)
    return type(text) == "string" and tonumber(text:match("%d+")) or nil
end

-- TRAINER_SHOW, TRAINER_UPDATE: records every class service under the player's class; tradeskill trainers are skipped.
function Trainer.OnTrainer()
    if blocked() or not ns.Check.Ready("Trainer record") or not UnitClass then
        return
    end
    if IsTradeskillTrainer and Safe(IsTradeskillTrainer()) then
        return
    end
    local _, classFile = UnitClass("player")
    classFile = Safe(classFile)
    local n = Safe(GetNumTrainerServices())
    for i = 1, type(n) == "number" and n or 0 do
        local _, rank, kind = GetTrainerServiceInfo(i)
        local id = Safe(kind) ~= "header" and spellID(i)
        if id then
            ns.Store.SetTrainerSpell(classFile, id, Safe(GetTrainerServiceLevelReq(i)), rankOf(rank))
        end
    end
end
