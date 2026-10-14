-- Loads the addon's .toc files in order under a stubbed WoW API and checks its locale handling.
local addonDir = arg[0]:gsub("[^/]*$", "") .. "../Tandem/"

local function tocFiles()
    local files = {}
    for raw in io.lines(addonDir .. "Tandem.toc") do
        local line = raw:match("^%s*(.-)%s*$")
        if line ~= "" and line:sub(1, 1) ~= "#" then
            files[#files + 1] = line:gsub("\\", "/")
        end
    end
    return files
end

-- Loads the addon as a client with the given locale would; returns its namespace,
-- the printed lines, and a function that fires ADDON_LOADED.
local function loadAddon(locale)
    local printed = {}
    local handler
    local frame = {
        RegisterEvent = function() end,
        UnregisterEvent = function() end,
        SetScript = function(_, _, fn)
            handler = fn
        end,
    }
    local env = setmetatable({
        CreateFrame = function()
            return frame
        end,
        GetLocale = function()
            return locale
        end,
        print = function(msg)
            printed[#printed + 1] = msg
        end,
    }, { __index = _G })

    local ns = {}
    for _, file in ipairs(tocFiles()) do
        local chunk = assert(loadfile(addonDir .. file, "t", env))
        if setfenv then
            setfenv(chunk, env)
        end
        chunk("Tandem", ns)
    end

    local function fireLoaded()
        handler(frame, "ADDON_LOADED", "Tandem")
    end
    return ns, printed, fireLoaded
end

local failures = 0
local function check(name, got, want)
    if got == want then
        print("ok   " .. name)
    else
        failures = failures + 1
        print(("FAIL %s: got %q, want %q"):format(name, tostring(got), tostring(want)))
    end
end

for _, case in ipairs({
    { locale = "enUS", line = "Tandem loaded" },
    { locale = "zhTW", line = "Tandem 已載入" },
    { locale = "deDE", line = "Tandem loaded" },
}) do
    local _, printed, fireLoaded = loadAddon(case.locale)
    fireLoaded()
    check(case.locale .. " load line", printed[1], case.line)
end

local ns = loadAddon("zhTW")
check("zhTW falls back to English for a missing key", ns.L["Not translated yet"], "Not translated yet")

if failures > 0 then
    os.exit(1)
end
