local addonName, ns = ...

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        print("Nascent loaded")
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)
