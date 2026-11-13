local addonName, ns = ...

-- The player-facing name. Never show addonName (the folder name) in game.
ns.NAME = "Nascent"
ns.VERSION = C_AddOns.GetAddOnMetadata(addonName, "Version") or "0.0.0"

local CHAT_TAG = "|cff7fd4ff" .. ns.NAME .. "|r: "

function ns.Print(text)
    print(CHAT_TAG .. tostring(text))
end

local dbDefaults = {
    global = {
        -- newestSeenVersion (string) and newestSeenAt (unix time) are written
        -- by Comm.lua when another player reports a newer version.
    },
}

local function PrintHelp()
    ns.Print("version " .. ns.VERSION)
    ns.Print("/nascent version - ask other players whether a newer version exists")
    ns.Print("/nascent test <version> - send yourself a test message, e.g. /nascent test 9.9.9")
end

SLASH_NASCENT1 = "/nascent"
SlashCmdList.NASCENT = function(input)
    local command, argument = strtrim(input or ""):match("^(%S*)%s*(.-)$")
    command = command:lower()
    if command == "version" then
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
    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        print("Nascent loaded")
        ns.Comm:Enable()
    end
end)
