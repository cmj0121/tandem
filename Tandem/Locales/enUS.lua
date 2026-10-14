local _, ns = ...

-- English text is the key: a string with no translation shows its English key.
ns.L = setmetatable({}, {
    __index = function(_, key)
        return key
    end,
})
