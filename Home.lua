local _, ns = ...

-- The Home page (docs/UI-SPEC.md section 3, Pages). Window.lua calls
-- Home:Build with the page the first time the window is created.

local Home = {}
ns.Home = Home

-- "First Surname"; UnitName would give the first name only.
local function PlayerName()
    local first, surname = UnitFullName("player")
    if type(first) ~= "string" or first == "" then
        return nil
    end
    if type(surname) == "string" and surname ~= "" then
        return first .. " " .. surname
    end
    return first
end

function Home:Build(page)
    local UI = ns.Window.UI

    local welcome = page:AddCard("Welcome to " .. ns.NAME)
    local name = PlayerName()
    if name then
        local hello = welcome:AddText("", UI.C.textPrimary)
        -- The name is drawn in the accent, so repaint it when the accent changes.
        UI.OnAccent(function()
            hello:SetText("Hello, |cff" .. ns.COLOR.hex .. name .. "|r!")
        end)
    end
    welcome:AddText("Version: " .. ns.VERSION)

    local actions = page:AddCard("Quick actions")
    actions:AddButtons({
        { label = "Check for updates", onClick = function() ns.Comm:Check() end },
        { label = "Reload UI", onClick = ReloadUI },
    })
    actions:AddText("Type /nas to open or close this window, and /nas version to check for updates.")

    local start = page:AddCard("Getting started")
    start:AddText("Use the sidebar to move between sections. Click a category name to fold it.")
    start:AddText("Type in the search box to find a section by name. Enter opens the first match.")
    start:AddText("Changes in Settings apply at once and are saved.")
end
