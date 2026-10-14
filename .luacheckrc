std = "lua51"
max_line_length = 120

-- Globals the addon writes: saved variables and slash command registration.
globals = {
    "SLASH_TANDEM1",
    "SlashCmdList",
    "TandemDB",
}

-- WoW API used by the addon; add new ones here as the addon grows.
read_globals = {
    "CreateFrame",
    "GetLocale",
    "issecretvalue",
}
