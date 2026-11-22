local addonName, ns = ...

-- The minimap button (LibDataBroker launcher shown by LibDBIcon). It can be
-- hidden with /nas minimap; the choice and the button's position are kept in
-- ns.db.profile.minimap.

local MinimapButton = {}
ns.MinimapButton = MinimapButton

-- addonName is the folder the game loaded us from; it is only used for paths.
local LOGO = "Interface\\AddOns\\" .. addonName .. "\\Media\\logo_n.tga"

local icon = LibStub("LibDBIcon-1.0")
local launcher

-- Retints the button after the accent colour changed. LibDBIcon repaints when
-- these fields are assigned.
function MinimapButton:ApplyAccent()
    if not launcher then return end
    launcher.iconR = ns.COLOR.r
    launcher.iconG = ns.COLOR.g
    launcher.iconB = ns.COLOR.b
end

function MinimapButton:Enable()
    launcher = LibStub("LibDataBroker-1.1"):NewDataObject(ns.NAME, {
        type = "launcher",
        text = ns.NAME,
        icon = LOGO,
        -- The logo is white; tint it with the Nascent blue.
        iconR = ns.COLOR.r,
        iconG = ns.COLOR.g,
        iconB = ns.COLOR.b,
        OnClick = function()
            ns.Window:Toggle()
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine(ns.NAME)
            tooltip:AddLine("Click to open or close the window.", 1, 1, 1)
        end,
    })
    icon:Register(ns.NAME, launcher, ns.db.profile.minimap)
end

function MinimapButton:SetHidden(hidden)
    ns.db.profile.minimap.hide = hidden
    if hidden then
        icon:Hide(ns.NAME)
    else
        icon:Show(ns.NAME)
    end
end
