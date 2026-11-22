local _, ns = ...

-- The Settings page (docs/UI-SPEC.md section 5). Window.lua calls
-- Settings:Build with the page the first time the window is created.
-- Every value lives in ns.db.profile; the accent colour is ns.COLOR.

local Settings = {}
ns.Settings = Settings

local SLIDER_WIDTH, SLIDER_HEIGHT = 200, 16
local TRACK_HEIGHT = 4
local THUMB_WIDTH = 8
local VALUE_GAP = 12

local CHECK_SIZE = 16
local CHECK_MARK_INSET = 3

local SWATCH_WIDTH, SWATCH_HEIGHT = 32, 16
local RESET_GAP = 12

local OPACITY_MIN, OPACITY_MAX = 0.6, 1.0
local FONT_OFFSET_MIN, FONT_OFFSET_MAX = -2, 4

local controls = {}     -- everything with a Refresh method

local function Percent(value)
    return ("%d%%"):format(math.floor(value * 100 + 0.5))
end

-- Controls ---------------------------------------------------------------------

-- A horizontal slider. `spec`: min, max, step, format(value), get(),
-- live(value) (optional, while dragging), commit(value) (on release).
local function CreateSlider(parent, spec)
    local UI = ns.Window.UI
    local slider = CreateFrame("Frame", nil, parent)
    slider:SetSize(SLIDER_WIDTH, SLIDER_HEIGHT)
    slider:EnableMouse(true)

    local track = UI.Solid(slider, "BACKGROUND", UI.C.borderInner)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(TRACK_HEIGHT)

    local fill = slider:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT")
    fill:SetHeight(TRACK_HEIGHT)
    UI.OnAccent(function(r, g, b)
        fill:SetColorTexture(r, g, b, 1)
    end)

    local thumb = UI.Solid(slider, "OVERLAY", UI.C.textPrimary)
    thumb:SetSize(THUMB_WIDTH, SLIDER_HEIGHT)

    local label = UI.Text(parent, UI.FONT_BODY, UI.C.textPrimary)
    label:SetPoint("LEFT", slider, "RIGHT", VALUE_GAP, 0)

    local value = spec.min
    local dragging = false

    local function Paint()
        local fraction = (value - spec.min) / (spec.max - spec.min)
        fill:SetShown(fraction > 0)
        fill:SetWidth(math.max(1, fraction * SLIDER_WIDTH))
        thumb:ClearAllPoints()
        thumb:SetPoint("CENTER", slider, "LEFT", fraction * SLIDER_WIDTH, 0)
        label:SetText(spec.format(value))
    end

    local function ValueAtCursor()
        local x = GetCursorPosition() / slider:GetEffectiveScale()
        local fraction = UI.Clamp((x - slider:GetLeft()) / slider:GetWidth(), 0, 1)
        local steps = math.floor(fraction * (spec.max - spec.min) / spec.step + 0.5)
        return UI.Clamp(spec.min + steps * spec.step, spec.min, spec.max)
    end

    local function Track()
        local new = ValueAtCursor()
        if new ~= value then
            value = new
            Paint()
            if spec.live then spec.live(value) end
        end
    end

    local function Release()
        if not dragging then return end
        dragging = false
        slider:SetScript("OnUpdate", nil)
        spec.commit(value)
    end

    slider:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        dragging = true
        Track()
        slider:SetScript("OnUpdate", Track)
    end)
    slider:SetScript("OnMouseUp", Release)
    -- Hiding mid-drag never delivers the mouse-up.
    slider:SetScript("OnHide", Release)

    function slider.Refresh()
        value = UI.Clamp(spec.get(), spec.min, spec.max)
        Paint()
    end

    controls[#controls + 1] = slider
    return slider
end

-- A checkbox. `spec`: get(), set(checked).
local function CreateCheckbox(parent, spec)
    local UI = ns.Window.UI
    local box = CreateFrame("Button", nil, parent)
    box:SetSize(CHECK_SIZE, CHECK_SIZE)
    box:SetHitRectInsets(-4, -4, -4, -4)

    local background = UI.Solid(box, "BACKGROUND", UI.C.bgWindow)
    background:SetAllPoints()
    UI.AddEdge(box, 0, UI.C.borderInner)

    local mark = box:CreateTexture(nil, "ARTWORK")
    mark:SetPoint("TOPLEFT", CHECK_MARK_INSET, -CHECK_MARK_INSET)
    mark:SetPoint("BOTTOMRIGHT", -CHECK_MARK_INSET, CHECK_MARK_INSET)
    UI.OnAccent(function(r, g, b)
        mark:SetColorTexture(r, g, b, 1)
    end)

    function box.Refresh()
        mark:SetShown(spec.get())
    end

    box:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        spec.set(not spec.get())
        box.Refresh()
    end)

    controls[#controls + 1] = box
    return box
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

    local reset = CreateFrame("Button", nil, parent)
    local label = UI.Text(reset, UI.FONT_BODY, UI.C.textMuted)
    label:SetPoint("LEFT")
    label:SetText("Reset")
    reset:SetSize(60, SWATCH_HEIGHT)
    reset:SetPoint("LEFT", swatch, "RIGHT", RESET_GAP, 0)
    reset:SetScript("OnEnter", function()
        label:SetTextColor(UI.C.textPrimary[1], UI.C.textPrimary[2], UI.C.textPrimary[3])
    end)
    reset:SetScript("OnLeave", function()
        label:SetTextColor(UI.C.textMuted[1], UI.C.textMuted[2], UI.C.textMuted[3])
    end)
    reset:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        ns.ResetAccent()
    end)

    return swatch
end

-- Page -------------------------------------------------------------------------

function Settings:Build(page)
    local UI = ns.Window.UI
    local profile = ns.db.profile

    local appearance = page:AddCard("Appearance")
    local panel = appearance.frame

    appearance:AddControl("UI scale", CreateSlider(panel, {
        min = UI.SCALE_MIN, max = UI.SCALE_MAX, step = 0.05,
        format = Percent,
        get = function() return profile.scale end,
        -- Applied on release only: scaling the window while the cursor is on
        -- its slider would move the slider under the cursor.
        commit = function(value)
            profile.scale = value
            ns.Window:ApplyScale()
        end,
    }))

    local function SetOpacity(value)
        profile.opacity = value
        ns.Window:ApplyOpacity()
    end
    appearance:AddControl("Window opacity", CreateSlider(panel, {
        min = OPACITY_MIN, max = OPACITY_MAX, step = 0.05,
        format = Percent,
        get = function() return profile.opacity end,
        live = SetOpacity,
        commit = SetOpacity,
    }))

    appearance:AddControl("Font size", CreateSlider(panel, {
        min = FONT_OFFSET_MIN, max = FONT_OFFSET_MAX, step = 1,
        format = function(value)
            return value == 0 and "0" or ("%+d"):format(value)
        end,
        get = function() return profile.fontOffset end,
        commit = function(value)
            profile.fontOffset = value
            ns.Window:ApplyFonts()
        end,
    }))
    appearance:AddText("Added to the size of every text in this window.", UI.C.textMuted)

    appearance:AddControl("Accent color", CreateAccentPicker(panel))

    local behavior = page:AddCard("Behavior")
    panel = behavior.frame

    behavior:AddControl("Show minimap button", CreateCheckbox(panel, {
        get = function() return not profile.minimap.hide end,
        set = function(checked) ns.MinimapButton:SetHidden(not checked) end,
    }))

    behavior:AddControl("Hide in combat", CreateCheckbox(panel, {
        get = function() return profile.hideInCombat end,
        set = function(checked) profile.hideInCombat = checked end,
    }))
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
