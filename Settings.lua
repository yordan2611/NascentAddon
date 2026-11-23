local _, ns = ...

-- The Settings page (docs/UI-SPEC.md section 5). Window.lua calls
-- Settings:Build with the page the first time the window is created.
-- Every value lives in ns.db.profile; the accent colour is ns.COLOR.
-- The slider and checkbox come from Controls.lua.

local Settings = {}
ns.Settings = Settings

local SWATCH_WIDTH, SWATCH_HEIGHT = 32, 16
local RESET_GAP = 12

local OPACITY_MIN, OPACITY_MAX = 0.6, 1.0
local FONT_OFFSET_MIN, FONT_OFFSET_MAX = -2, 4

local controls = {}     -- everything with a Refresh method

local function Percent(value)
    return ("%d%%"):format(math.floor(value * 100 + 0.5))
end

local function Track(control)
    controls[#controls + 1] = control
    return control
end

-- The accent colour swatch (opens the colour picker) and its Reset button.
local function CreateAccentPicker(parent)
    local UI = ns.Window.UI
    local swatch = CreateFrame("Button", nil, parent)
    swatch:SetSize(SWATCH_WIDTH, SWATCH_HEIGHT)
    swatch:SetHitRectInsets(-4, -4, -4, -4)

    local fill = swatch:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    UI.OnAccent(function(r, g, b)
        fill:SetColorTexture(r, g, b, 1)
    end)
    UI.AddEdge(swatch, 0, UI.C.borderInner)

    swatch:SetScript("OnClick", function()
        local r, g, b = ns.COLOR.r, ns.COLOR.g, ns.COLOR.b
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b,
            hasOpacity = false,
            swatchFunc = function()
                ns.SetAccent(ColorPickerFrame:GetColorRGB())
            end,
            cancelFunc = function()
                ns.SetAccent(r, g, b)
            end,
        })
    end)

    local reset = UI.TextButton(parent, "Reset", ns.ResetAccent)
    reset:SetPoint("LEFT", swatch, "RIGHT", RESET_GAP, 0)

    return swatch
end

-- Page -------------------------------------------------------------------------

function Settings:Build(page)
    local UI = ns.Window.UI
    local profile = ns.db.profile

    local appearance = page:AddCard("Appearance")
    local panel = appearance.frame

    appearance:AddControl("UI scale", Track(UI.Slider(panel, {
        min = UI.SCALE_MIN, max = UI.SCALE_MAX, step = 0.05,
        format = Percent,
        get = function() return profile.scale end,
        -- Applied on release only: scaling the window while the cursor is on
        -- its slider would move the slider under the cursor.
        commit = function(value)
            profile.scale = value
            ns.Window:ApplyScale()
        end,
    })))

    local function SetOpacity(value)
        profile.opacity = value
        ns.Window:ApplyOpacity()
    end
    appearance:AddControl("Window opacity", Track(UI.Slider(panel, {
        min = OPACITY_MIN, max = OPACITY_MAX, step = 0.05,
        format = Percent,
        get = function() return profile.opacity end,
        live = SetOpacity,
        commit = SetOpacity,
    })))

    appearance:AddControl("Font size", Track(UI.Slider(panel, {
        min = FONT_OFFSET_MIN, max = FONT_OFFSET_MAX, step = 1,
        format = function(value)
            return value == 0 and "0" or ("%+d"):format(value)
        end,
        get = function() return profile.fontOffset end,
        commit = function(value)
            profile.fontOffset = value
            ns.Window:ApplyFonts()
        end,
    })))
    appearance:AddText("Added to the size of every text in this window.", UI.C.textMuted)

    appearance:AddControl("Accent color", CreateAccentPicker(panel))

    local behavior = page:AddCard("Behavior")
    panel = behavior.frame

    behavior:AddControl("Show minimap button", Track(UI.Checkbox(panel, {
        get = function() return not profile.minimap.hide end,
        set = function(checked) ns.MinimapButton:SetHidden(not checked) end,
    })))

    behavior:AddControl("Hide in combat", Track(UI.Checkbox(panel, {
        get = function() return profile.hideInCombat end,
        set = function(checked) profile.hideInCombat = checked end,
    })))
    behavior:AddText("The window closes when combat starts and opens again when it ends.", UI.C.textMuted)

    page.frame:SetScript("OnShow", function() Settings:Refresh() end)
    Settings:Refresh()
end

-- Re-reads every control from the saved values. Also called by the slash
-- commands that change a setting; harmless before the page has been built.
function Settings:Refresh()
    for _, control in ipairs(controls) do
        control.Refresh()
    end
end
