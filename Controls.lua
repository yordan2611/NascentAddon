local _, ns = ...

-- Controls shared by the pages (docs/UI-SPEC.md section 5, "As built"). They
-- are added to ns.Window.UI, so load this file after Window.lua and before the
-- page files. Each control has a Refresh method that re-reads its value.

local UI = ns.Window.UI

local SLIDER_WIDTH, SLIDER_HEIGHT = 200, 16
local TRACK_HEIGHT = 4
local THUMB_WIDTH = 8
local VALUE_GAP = 12

local CHECK_SIZE = 16
local CHECK_MARK_INSET = 3

-- A horizontal slider. `spec`: min, max, step, format(value), get(),
-- live(value) (optional, while dragging), commit(value) (on release).
function UI.Slider(parent, spec)
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

    slider.Refresh()
    return slider
end

-- A checkbox. `spec`: get(), set(checked).
function UI.Checkbox(parent, spec)
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
        mark:SetShown(spec.get() and true or false)
    end

    box:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        spec.set(not spec.get())
        box.Refresh()
    end)

    box.Refresh()
    return box
end

-- A text link: muted text that turns white on hover, as the accent's Reset.
function UI.TextButton(parent, label, onClick)
    local button = CreateFrame("Button", nil, parent)
    local text = UI.Text(button, UI.FONT_BODY, UI.C.textMuted)
    text:SetPoint("LEFT")
    text:SetText(label)
    button:SetSize(math.max(1, text:GetStringWidth()), CHECK_SIZE)
    local function Paint(colour)
        text:SetTextColor(colour[1], colour[2], colour[3])
    end
    button:SetScript("OnEnter", function() Paint(UI.C.textPrimary) end)
    button:SetScript("OnLeave", function() Paint(UI.C.textMuted) end)
    button:SetScript("OnHide", function() Paint(UI.C.textMuted) end)
    button:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        onClick()
    end)
    button.text = text
    return button
end
