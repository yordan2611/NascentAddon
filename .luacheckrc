-- Luacheck configuration for Nascent (WoW runs Lua 5.1).
std = "lua51"
max_line_length = false
codes = true

exclude_files = {
    "Libs/",
    ".release/",
}

ignore = {
    "211/addonName", -- unused `local addonName, ns = ...` header
    "211/ns",
    "212/self",      -- unused self in methods and script handlers
    "212/event",     -- unused event argument in OnEvent handlers
    "212/%.%.%.",    -- unused varargs
}

-- Globals this addon defines (SavedVariables, slash commands, named frames).
globals = {
    "NascentDB",
    "SLASH_NASCENT1",
    "SlashCmdList",
}

-- WoW API the addon may read. Only add a name here after confirming it exists
-- in the client (see CLAUDE.md): an entry here silences the undefined-global
-- warning that would otherwise catch a made-up API.
read_globals = {
    -- Frames and core UI
    "CreateFrame",
    "UIParent",
    "GameTooltip",
    "DEFAULT_CHAT_FRAME",
    "BackdropTemplateMixin",
    "STANDARD_TEXT_FONT",
    "GameFontNormal",
    "GameFontNormalSmall",
    "GameFontHighlight",
    "GameFontHighlightSmall",

    -- Embedded libraries
    "LibStub",

    -- Addons, guild and group (seen unguarded in 16001-only addons)
    "C_AddOns",
    "IsInGuild",
    "IsInGroup",
    "IsInRaid",
    "GetNumGroupMembers",
    "LE_PARTY_CATEGORY_INSTANCE",
    "LE_PARTY_CATEGORY_HOME", -- unverified; Comm.lua tolerates nil

    -- State and info
    "InCombatLockdown",
    "GetBuildInfo",
    "GetTime",
    "GetRealmName",
    "UnitName",
    "UnitFullName", -- returns first name, surname on Forever
    "UnitClass",
    "UnitExists",
    "UnitGUID",
    "IsLoggedIn",

    -- Utilities
    "hooksecurefunc",
    "geterrorhandler",
    "debugstack",
    "ReloadUI",
    "C_Timer",

    -- WoW's Lua extensions
    "strsplit",
    "strjoin",
    "strtrim",
    "strmatch",
    "tinsert",
    "tremove",
    "wipe",
    "format",
    "date",
    "time",
}
