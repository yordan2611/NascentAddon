local addonName, ns = ...

-- The player-facing name. Never show addonName (the folder name) in game.
ns.NAME = "Nascent"
ns.VERSION = C_AddOns.GetAddOnMetadata(addonName, "Version") or "0.0.0"

-- The Nascent blue: the `accent` token in docs/UI-SPEC.md, used for the chat
-- tag and the window's logo, underline and selected nav row.
-- The player can change it in Settings; change it only through ns.SetAccent.
local DEFAULT_ACCENT = { r = 0x90 / 255, g = 0x99 / 255, b = 0xf9 / 255 }
ns.COLOR = { r = DEFAULT_ACCENT.r, g = DEFAULT_ACCENT.g, b = DEFAULT_ACCENT.b, hex = "9099f9" }

function ns.Print(text)
    print("|cff" .. ns.COLOR.hex .. ns.NAME .. "|r: " .. tostring(text))
end

local function SetColor(r, g, b)
    local c = ns.COLOR
    c.r, c.g, c.b = r, g, b
    c.hex = ("%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- Changes the accent colour everywhere it is shown and saves it.
function ns.SetAccent(r, g, b)
    SetColor(r, g, b)
    ns.db.profile.accent = { r = r, g = g, b = b }
    ns.Window:ApplyAccent()
    ns.MinimapButton:ApplyAccent()
end

function ns.ResetAccent()
    ns.SetAccent(DEFAULT_ACCENT.r, DEFAULT_ACCENT.g, DEFAULT_ACCENT.b)
    ns.db.profile.accent = nil
end

local function IsColorPart(value)
    return type(value) == "number" and value >= 0 and value <= 1
end

local dbDefaults = {
    global = {
        -- newestSeenVersion (string) and newestSeenAt (unix time) are written
        -- by Comm.lua when another player reports a newer version.
    },
    profile = {
        -- Window.lua also writes point, relativePoint, x, y, width, height and
        -- section (the last selected nav row) here.
        window = {},
        -- Handed to LibDBIcon, which adds minimapPos.
        minimap = { hide = false },
        hideInCombat = false,
        scale = 1,       -- window scale, 0.7 to 1.5
        opacity = 1,     -- window background alpha, 0.6 to 1
        fontOffset = 0,  -- added to every font size, -2 to +4
        -- accent = { r, g, b } is written by ns.SetAccent; absent means the default.
    },
}

-- Opens or closes the window. Global because the keybinding (Bindings.xml) and
-- the addon compartment entry (## AddonCompartmentFunc) call it by name.
function Nascent_Toggle()
    ns.Window:Toggle()
end

BINDING_NAME_NASCENT_TOGGLE = "Toggle " .. ns.NAME

local function PrintHelp()
    ns.Print("version " .. ns.VERSION)
    ns.Print("/nas - open or close the window")
    ns.Print("/nas minimap - show or hide the minimap button")
    ns.Print("/nas combat - turn hiding the window in combat on or off")
    ns.Print("/nas version - ask other players whether a newer version exists")
    ns.Print("/nas test <version> - send yourself a test message, e.g. /nas test 9.9.9")
end

SLASH_NASCENT1 = "/nas"
SLASH_NASCENT2 = "/nascent"
SlashCmdList.NASCENT = function(input)
    local command, argument = strtrim(input or ""):match("^(%S*)%s*(.-)$")
    command = command:lower()
    if command == "" then
        ns.Window:Toggle()
    elseif command == "minimap" then
        local hidden = not ns.db.profile.minimap.hide
        ns.MinimapButton:SetHidden(hidden)
        ns.Settings:Refresh()
        ns.Print(hidden and "Minimap button hidden." or "Minimap button shown.")
    elseif command == "combat" then
        local enabled = not ns.db.profile.hideInCombat
        ns.db.profile.hideInCombat = enabled
        ns.Settings:Refresh()
        ns.Print(enabled and "The window now hides in combat." or "The window now stays open in combat.")
    elseif command == "version" then
        ns.Comm:Check()
    elseif command == "test" then
        ns.Comm:SendTest(argument)
    else
        PrintHelp()
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then return end
        self:UnregisterEvent("ADDON_LOADED")
        ns.db = LibStub("AceDB-3.0"):New("NascentDB", dbDefaults, true)
        local accent = ns.db.profile.accent
        if type(accent) == "table" and IsColorPart(accent.r) and IsColorPart(accent.g) and IsColorPart(accent.b) then
            SetColor(accent.r, accent.g, accent.b)
        end
    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        print("Nascent loaded")
        ns.Comm:Enable()
        ns.Window:RegisterMedia()
        ns.MinimapButton:Enable()
        self:RegisterEvent("PLAYER_REGEN_DISABLED")
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
    elseif event == "PLAYER_REGEN_DISABLED" then
        ns.Window:OnCombat(true)
    elseif event == "PLAYER_REGEN_ENABLED" then
        ns.Window:OnCombat(false)
    end
end)
