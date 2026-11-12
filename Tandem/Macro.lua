local _, ns = ...

-- Character macros Tandem keeps for its buttons (the fishing macro, the class macros): found by name among the
-- character macros only, edited only when their body changed, made only when asked and a character slot is free.
-- Callers check combat and the macro API first.
local Macro = {}
ns.Macro = Macro

local call = ns.Store.Call

-- The client's account and character macro slots when it does not say (MAX_ACCOUNT_MACROS and MAX_CHARACTER_MACROS
-- live in the load-on-demand macro UI). Character macros have the indexes after the account ones.
local ACCOUNT_MACROS, CHARACTER_MACROS = 120, 18

-- Macro.Index(name) -> index|nil: the character macro named name; an account macro of that name is not it.
function Macro.Index(name)
    local accounts = type(MAX_ACCOUNT_MACROS) == "number" and MAX_ACCOUNT_MACROS or ACCOUNT_MACROS
    local index = call(GetMacroIndexByName, name)
    if type(index) ~= "number" or index <= 0 then
        return nil
    end
    if index > accounts then
        return index
    end
    local _, characterMacros = call(GetNumMacros)
    for i = accounts + 1, accounts + (type(characterMacros) == "number" and characterMacros or 0) do
        if call(GetMacroInfo, i) == name then
            return i
        end
    end
end

-- Macro.Ensure(name, icon, body, create) -> index|nil, what[, used, max]
-- Makes the character macro name hold body. what is "kept" (already so), "edited", "created", "absent" (missing and
-- create false) or "full" (missing and no character slot free; used and max follow).
function Macro.Ensure(name, icon, body, create)
    local index = Macro.Index(name)
    if index then
        if select(3, call(GetMacroInfo, index)) ~= body then
            call(EditMacro, index, name, icon, body)
            return index, "edited"
        end
        return index, "kept"
    end
    if not create then
        return nil, "absent"
    end
    local _, used = call(GetNumMacros)
    local max = type(MAX_CHARACTER_MACROS) == "number" and MAX_CHARACTER_MACROS or CHARACTER_MACROS
    if type(used) == "number" and used >= max then
        return nil, "full", used, max
    end
    index = call(CreateMacro, name, icon, body, true)
    return type(index) == "number" and index > 0 and index or nil, "created"
end
