local addonName, ns = ...

-- The main Nascent window, opened with /nas.
-- Layout, colours, sizes and fonts come from docs/UI-SPEC.md. Change the spec
-- first, then this file.
--
--   +--------------------------------------------------+
--   | title bar: logo, name                    close X |
--   +------------+-------------------------------------+
--   | search     | cards of the selected page          |
--   | categories |  (scrolls)                          |
--   |   items    |                                     |
--   | (scrolls)  |                                     |
--   +------------+-------------------------------------+
--   | footer: version                             grip |
--   +--------------------------------------------------+

local Window = {}
ns.Window = Window

-- Media ----------------------------------------------------------------------

-- addonName is the folder the game loaded us from; it is only used for paths.
local MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Media\\"
local FONT = MEDIA .. "Fonts\\Expressway.ttf"
local FALLBACK_FONT = "Fonts\\ARIALN.TTF"
local LOGO = MEDIA .. "logo_n.tga"
local ICON_CLOSE = MEDIA .. "icon_close.tga"
local ICON_GRIP = MEDIA .. "icon_grip.tga"
local ICON_CHEVRON_DOWN = MEDIA .. "icon_chevron_down.tga"
local ICON_CHEVRON_RIGHT = MEDIA .. "icon_chevron_right.tga"

-- Colours (UI-SPEC section 1) --------------------------------------------------

local C = {
    bgWindow      = { 0.020, 0.020, 0.020 },
    bgSidebar     = { 0, 0, 0 },
    borderOuter   = { 0, 0, 0 },
    borderInner   = { 0.118, 0.137, 0.314 },
    divider       = { 0.071, 0.082, 0.180 },
    textPrimary   = { 1, 1, 1 },
    textSecondary = { 0.663, 0.675, 0.796 },
    textMuted     = { 0.553, 0.565, 0.722 },
    hoverBg       = { 0.039, 0.047, 0.110 },
    closeHover    = { 1.000, 0.420, 0.420 },
    closeHoverBg  = { 0.078, 0.039, 0.047 },
    grip          = { 0.227, 0.255, 0.502 },
}

-- The accent is ns.COLOR; read it at use so the setting can change it.
local function Accent()
    return ns.COLOR.r, ns.COLOR.g, ns.COLOR.b
end

-- Layout (UI-SPEC section 3) ---------------------------------------------------

local WIDTH, HEIGHT = 795, 806
local MIN_WIDTH, MIN_HEIGHT = 640, 460
local MAX_WIDTH, MAX_HEIGHT = 1400, 1000
local BORDER = 2                -- 1px outer + 1px inner

local TITLE_HEIGHT = 30
local TITLE_INSET = 10
local TITLE_LOGO_SIZE = 18
local TITLE_NAME_GAP = 6
local CLOSE_SIZE = 22
local CLOSE_INSET = 4
local CLOSE_ICON_SIZE = 10

local FOOTER_HEIGHT = 22
local FOOTER_INSET = 10
local GRIP_SIZE = 12
local GRIP_INSET = 5
local GRIP_LEVEL = 10           -- above the content frames

local SIDEBAR_WIDTH = 180
local SEARCH_INSET = 6
local SEARCH_HEIGHT = 24
local SEARCH_TEXT_INSET = 8
local SEARCH_MAX_LETTERS = 40

local GROUP_HEIGHT = 26
local GROUP_INSET = 10
local GROUP_BULLET = 4
local GROUP_LABEL_GAP = 8
local CHEVRON_SIZE = 10
local CHEVRON_INSET = 10
local ITEM_HEIGHT = 24
local ITEM_INDENT = 24
local ITEM_PAD_RIGHT = 8
local ITEM_BAR_WIDTH = 2

local SCROLL_BAR_WIDTH = 3
local SCROLL_BAR_GAP = 3
local SCROLL_STEP = 40
local THUMB_MIN = 20

local CONTENT_PAD = 8
local CARD_GAP = 8
local CARD_HEADER_HEIGHT = 30
local CARD_PAD = 10
local CARD_ITEM_GAP = 8
local CARD_LABEL_GAP = 4
local BUTTON_HEIGHT = 26
local BUTTON_GAP = 6

local TOOLTIP_PAD_X, TOOLTIP_PAD_Y = 12, 8
local TOOLTIP_MAX_WIDTH = 240
local TOOLTIP_TEXT_MAX = TOOLTIP_MAX_WIDTH - 2 * TOOLTIP_PAD_X
local TOOLTIP_LINE_GAP = 4
local TOOLTIP_OFFSET = 8

local SCALE_MIN, SCALE_MAX = 0.7, 1.5

-- Font sizes (UI-SPEC section 2).
local FONT_TITLE = 15
local FONT_GROUP = 14
local FONT_ITEM = 13
local FONT_SEARCH = 13
local FONT_CARD_TITLE = 14
local FONT_BODY = 13
local FONT_FOOTER = 12
local FONT_TOOLTIP_TITLE = 14
local FONT_TOOLTIP_DESC = 13
local FONT_MIN = 12

-- Navigation -----------------------------------------------------------------

-- Categories and their items. An item with a `build` function fills its own
-- page; the others get a placeholder card. Settings.lua and Home.lua load
-- after this file, so they are looked up when the page is built.
local PLACEHOLDER_BODY = "Placeholder content for this section."
local GROUPS = {
    { key = "general", label = "General", items = {
        { key = "home", label = "Home", desc = "Welcome and quick actions.",
          build = function(page) ns.Home:Build(page) end },
        { key = "settings", label = "Settings", desc = "Options for this addon.",
          build = function(page) ns.Settings:Build(page) end },
    } },
    { key = "inventory", label = "Inventory", items = {
        { key = "cheapest", label = "Cheapest items", desc = "Make room when your bags are full.",
          build = function(page) ns.CheapestPage:Build(page) end },
    } },
    { key = "categoryTwo", label = "Category Two", items = {
        { key = "one", label = "Section One", desc = "Placeholder description." },
        { key = "two", label = "Section Two", desc = "Placeholder description." },
    } },
    { key = "categoryThree", label = "Category Three", items = {
        { key = "three", label = "Section Three", desc = "Placeholder description." },
        { key = "four", label = "Section Four", desc = "Placeholder description." },
    } },
}
local DEFAULT_KEY = "home"

-- State ----------------------------------------------------------------------

local frame
local tooltip
local search
local noMatches
local navScroll, contentScroll
local groupWidgets = {}     -- { group, header, rows }
local rows = {}             -- every item row, in sidebar order
local pages = {}            -- item key -> page
local fontStrings = {}      -- { text = FontString or EditBox, size = base size }, for the font size offset
local backgrounds = {}      -- { texture = Texture, colour = {r, g, b} }, for the window opacity
local accentListeners = {}  -- functions that repaint something in the accent colour
local layoutListeners = {}  -- functions that re-lay out other windows after a font or scale change
local selectedKey = DEFAULT_KEY
local filter = ""           -- lower-case search text
-- True while the window should come back when combat ends (hide in combat).
local reopenAfterCombat = false

-- Helpers ----------------------------------------------------------------------

local function Clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

local function Solid(parent, layer, colour, alpha)
    local texture = parent:CreateTexture(nil, layer)
    texture:SetColorTexture(colour[1], colour[2], colour[3], alpha or 1)
    return texture
end

-- A background that follows the "window opacity" setting.
local function Background(parent, colour)
    local texture = Solid(parent, "BACKGROUND", colour, ns.db.profile.opacity)
    texture:SetAllPoints()
    backgrounds[#backgrounds + 1] = { texture = texture, colour = colour }
    return texture
end

-- The fallback goes first so the region still has a font if the Expressway
-- file cannot be loaded. The spec's minimum size holds whatever the offset is.
local function SetTextFont(region, size)
    size = math.max(FONT_MIN, size + ns.db.profile.fontOffset)
    region:SetFont(FALLBACK_FONT, size, "")
    region:SetFont(FONT, size, "")
end

-- Sets the font and keeps it following the font size offset. Works for
-- FontStrings and EditBoxes.
local function RegisterFont(region, size)
    SetTextFont(region, size)
    fontStrings[#fontStrings + 1] = { text = region, size = size }
end

-- `size` is the role's size from the spec; the font size offset is added to it.
local function Text(parent, size, colour)
    local text = parent:CreateFontString(nil, "OVERLAY")
    -- The font must be set before SetText.
    RegisterFont(text, size)
    text:SetTextColor(colour[1], colour[2], colour[3])
    return text
end

-- Runs `paint` now and again whenever the accent colour changes.
local function OnAccent(paint)
    accentListeners[#accentListeners + 1] = paint
    paint(Accent())
end

-- A 1px rectangle outline, `inset` pixels in from the edge of `parent`.
local function AddEdge(parent, inset, colour)
    local top = Solid(parent, "BORDER", colour)
    top:SetPoint("TOPLEFT", inset, -inset)
    top:SetPoint("TOPRIGHT", -inset, -inset)
    top:SetHeight(1)

    local bottom = Solid(parent, "BORDER", colour)
    bottom:SetPoint("BOTTOMLEFT", inset, inset)
    bottom:SetPoint("BOTTOMRIGHT", -inset, inset)
    bottom:SetHeight(1)

    -- The sides sit between the top and bottom strips so corners do not overlap.
    local left = Solid(parent, "BORDER", colour)
    left:SetPoint("TOPLEFT", inset, -inset - 1)
    left:SetPoint("BOTTOMLEFT", inset, inset + 1)
    left:SetWidth(1)

    local right = Solid(parent, "BORDER", colour)
    right:SetPoint("TOPRIGHT", -inset, -inset - 1)
    right:SetPoint("BOTTOMRIGHT", -inset, inset + 1)
    right:SetWidth(1)
end

-- A 1px horizontal line along the top or bottom edge of `parent`.
local function AddLine(parent, edge, colour)
    local line = Solid(parent, "BORDER", colour)
    line:SetPoint(edge .. "LEFT")
    line:SetPoint(edge .. "RIGHT")
    line:SetHeight(1)
    return line
end

local function CreateButton(parent, label, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetHeight(BUTTON_HEIGHT)

    local background = Solid(button, "BACKGROUND", C.bgWindow)
    background:SetAllPoints()
    local hover = Solid(button, "ARTWORK", C.hoverBg)
    hover:SetAllPoints()
    hover:Hide()
    AddEdge(button, 0, C.borderInner)

    local text = Text(button, FONT_BODY, C.textPrimary)
    text:SetPoint("CENTER")
    text:SetText(label)
    button.label = text

    button:SetScript("OnEnter", function() hover:Show() end)
    button:SetScript("OnLeave", function() hover:Hide() end)
    -- OnLeave does not fire when the button is hidden under the cursor.
    button:SetScript("OnHide", function() hover:Hide() end)
    button:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        onClick()
    end)
    return button
end

-- Saved state ------------------------------------------------------------------

local function SaveGeometry(window)
    local saved = ns.db.profile.window
    local point, _, relativePoint, x, y = window:GetPoint(1)
    saved.point, saved.relativePoint, saved.x, saved.y = point, relativePoint, x, y
    saved.width, saved.height = window:GetSize()
end

local function RestoreGeometry(window)
    local saved = ns.db.profile.window
    if type(saved.width) == "number" and type(saved.height) == "number" then
        window:SetSize(Clamp(saved.width, MIN_WIDTH, MAX_WIDTH), Clamp(saved.height, MIN_HEIGHT, MAX_HEIGHT))
    end
    if type(saved.point) == "string" and type(saved.relativePoint) == "string"
        and type(saved.x) == "number" and type(saved.y) == "number" then
        window:ClearAllPoints()
        window:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    end
end

-- The categories the player folded, as { [category key] = true }.
local function Folded()
    local saved = ns.db.profile.window
    if type(saved.folded) ~= "table" then
        saved.folded = {}
    end
    return saved.folded
end

-- Scrolling --------------------------------------------------------------------

-- A plain ScrollFrame with a child frame (`scroll.child`) and a thin bar to its
-- right. After changing the child's height, call `scroll.Sync()`.
local function CreateScroll(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    scroll.child = child

    local bar = CreateFrame("Frame", nil, parent)
    bar:SetWidth(SCROLL_BAR_WIDTH)
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", SCROLL_BAR_GAP, 0)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", SCROLL_BAR_GAP, 0)
    bar:EnableMouse(true)
    bar:Hide()

    local track = Solid(bar, "BACKGROUND", C.divider)
    track:SetAllPoints()

    local thumb = bar:CreateTexture(nil, "ARTWORK")
    OnAccent(function(r, g, b)
        thumb:SetColorTexture(r, g, b, 1)
    end)
    local thumbHeight = THUMB_MIN

    function scroll.Sync()
        scroll:UpdateScrollChildRect()
        local range = scroll:GetVerticalScrollRange()
        if range <= 0 then
            scroll:SetVerticalScroll(0)
            bar:Hide()
            return
        end
        local at = Clamp(scroll:GetVerticalScroll(), 0, range)
        scroll:SetVerticalScroll(at)
        bar:Show()
        local height = bar:GetHeight()
        local view = scroll:GetHeight()
        thumbHeight = math.min(height, math.max(THUMB_MIN, height * view / (view + range)))
        local offset = (height - thumbHeight) * at / range
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPLEFT", 0, -offset)
        thumb:SetPoint("TOPRIGHT", 0, -offset)
        thumb:SetHeight(thumbHeight)
    end

    function scroll.ScrollTo(value)
        scroll:SetVerticalScroll(Clamp(value, 0, math.max(0, scroll:GetVerticalScrollRange())))
        scroll.Sync()
    end

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        self.ScrollTo(self:GetVerticalScroll() - delta * SCROLL_STEP)
    end)

    -- Clicking the bar moves the thumb's middle to the cursor; holding drags it.
    local function Follow()
        local range = scroll:GetVerticalScrollRange()
        local travel = bar:GetHeight() - thumbHeight
        if range <= 0 or travel <= 0 then return end
        local _, y = GetCursorPosition()
        y = y / bar:GetEffectiveScale()
        local fromTop = bar:GetTop() - y - thumbHeight / 2
        scroll.ScrollTo(range * Clamp(fromTop / travel, 0, 1))
    end
    local function StopFollowing()
        bar:SetScript("OnUpdate", nil)
    end
    bar:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        Follow()
        bar:SetScript("OnUpdate", Follow)
    end)
    bar:SetScript("OnMouseUp", StopFollowing)
    bar:SetScript("OnHide", StopFollowing)

    return scroll
end

-- Tooltip ----------------------------------------------------------------------

local function CreateTooltip(window)
    local tip = CreateFrame("Frame", nil, window)
    tip:SetFrameStrata("TOOLTIP")
    tip:Hide()

    local background = Solid(tip, "BACKGROUND", C.bgSidebar)
    background:SetAllPoints()
    AddEdge(tip, 0, C.borderInner)

    tip.title = Text(tip, FONT_TOOLTIP_TITLE, C.textPrimary)
    tip.title:SetPoint("TOPLEFT", TOOLTIP_PAD_X, -TOOLTIP_PAD_Y)
    tip.title:SetJustifyH("LEFT")
    tip.title:SetWordWrap(false)

    tip.desc = Text(tip, FONT_TOOLTIP_DESC, C.textSecondary)
    tip.desc:SetPoint("TOPLEFT", tip.title, "BOTTOMLEFT", 0, -TOOLTIP_LINE_GAP)
    tip.desc:SetJustifyH("LEFT")
    tip.desc:SetWordWrap(false)

    return tip
end

-- Sets the text and returns its width, capped so the tooltip stays within its
-- maximum width (a longer line is cut off).
local function FitTooltipText(text, value)
    text:SetWidth(0)
    text:SetText(value)
    local width = text:GetStringWidth()
    if width > TOOLTIP_TEXT_MAX then
        width = TOOLTIP_TEXT_MAX
        text:SetWidth(width)
    end
    return width
end

local function ShowTooltip(row)
    local width = math.max(
        FitTooltipText(tooltip.title, row.item.label),
        FitTooltipText(tooltip.desc, row.item.desc))
    local height = tooltip.title:GetStringHeight() + TOOLTIP_LINE_GAP + tooltip.desc:GetStringHeight()
    tooltip:SetSize(width + 2 * TOOLTIP_PAD_X, height + 2 * TOOLTIP_PAD_Y)
    tooltip:ClearAllPoints()
    tooltip:SetPoint("LEFT", row, "RIGHT", TOOLTIP_OFFSET, 0)
    tooltip:Show()
end

-- Pages and cards ----------------------------------------------------------------

-- A card: a titled box whose items are stacked by Card:Layout. Pages add
-- cards with page:AddCard(title) and fill them with the Add methods.
local Card = {}
Card.__index = Card

-- Wrapped text. `colour` defaults to the body colour; pass C.textMuted for a
-- hint under a control.
function Card:AddText(text, colour)
    local region = Text(self.frame, FONT_BODY, colour or C.textSecondary)
    region:SetJustifyH("LEFT")
    region:SetWordWrap(true)
    region:SetText(text)
    self.items[#self.items + 1] = { kind = "text", region = region }
    return region
end

-- A label with a control under it. The control must already have its size.
function Card:AddControl(label, control)
    local text = Text(self.frame, FONT_BODY, C.textPrimary)
    text:SetJustifyH("LEFT")
    text:SetText(label)
    self.items[#self.items + 1] = { kind = "control", label = text, region = control }
    return control
end

-- A row of buttons sharing the card's width: { { label = ..., onClick = ... }, ... }.
function Card:AddButtons(list)
    local holder = CreateFrame("Frame", nil, self.frame)
    holder:SetHeight(BUTTON_HEIGHT)
    holder.buttons = {}
    for index, entry in ipairs(list) do
        holder.buttons[index] = CreateButton(holder, entry.label, entry.onClick)
    end
    self.items[#self.items + 1] = { kind = "buttons", region = holder }
    return holder
end

-- A region that sizes itself: `region.Layout(width)` places its contents for
-- the card's inner width and returns its height. Call Window:Relayout() after
-- its contents change.
function Card:AddCustom(region)
    self.items[#self.items + 1] = { kind = "custom", region = region }
    return region
end

-- Places the items for a card `width` wide and returns the card's height.
function Card:Layout(width)
    local inner = width - 2 * CARD_PAD
    local y = CARD_HEADER_HEIGHT + 1 + CARD_PAD
    for index, item in ipairs(self.items) do
        if index > 1 then
            y = y + CARD_ITEM_GAP
        end
        local region = item.region
        if item.kind == "text" then
            region:SetWidth(inner)
            region:ClearAllPoints()
            region:SetPoint("TOPLEFT", CARD_PAD, -y)
            y = y + region:GetStringHeight()
        elseif item.kind == "control" then
            item.label:ClearAllPoints()
            item.label:SetPoint("TOPLEFT", CARD_PAD, -y)
            y = y + item.label:GetStringHeight() + CARD_LABEL_GAP
            region:ClearAllPoints()
            region:SetPoint("TOPLEFT", CARD_PAD, -y)
            y = y + region:GetHeight()
        elseif item.kind == "buttons" then
            region:ClearAllPoints()
            region:SetPoint("TOPLEFT", CARD_PAD, -y)
            region:SetWidth(inner)
            local count = #region.buttons
            local buttonWidth = (inner - (count - 1) * BUTTON_GAP) / count
            for i, button in ipairs(region.buttons) do
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", (i - 1) * (buttonWidth + BUTTON_GAP), 0)
                button:SetWidth(buttonWidth)
            end
            y = y + BUTTON_HEIGHT
        elseif item.kind == "custom" then
            region:ClearAllPoints()
            region:SetPoint("TOPLEFT", CARD_PAD, -y)
            region:SetWidth(inner)
            local height = region.Layout(inner)
            region:SetHeight(math.max(1, height))
            y = y + height
        end
    end
    y = y + CARD_PAD
    self.frame:SetHeight(y)
    return y
end

local Page = {}
Page.__index = Page

function Page:AddCard(title)
    local card = setmetatable({ items = {} }, Card)
    local box = CreateFrame("Frame", nil, self.frame)
    Background(box, C.bgSidebar)
    AddEdge(box, 0, C.borderInner)

    local heading = Text(box, FONT_CARD_TITLE, C.textPrimary)
    heading:SetPoint("LEFT", box, "TOPLEFT", CARD_PAD, -CARD_HEADER_HEIGHT / 2)
    heading:SetText(title)
    OnAccent(function(r, g, b)
        heading:SetTextColor(r, g, b)
    end)

    local line = Solid(box, "BORDER", C.divider)
    line:SetPoint("TOPLEFT", 1, -CARD_HEADER_HEIGHT)
    line:SetPoint("TOPRIGHT", -1, -CARD_HEADER_HEIGHT)
    line:SetHeight(1)

    card.frame = box
    self.cards[#self.cards + 1] = card
    return card
end

-- Stacks the cards for a page `width` wide and returns the page's height.
function Page:Layout(width)
    local y = 0
    for index, card in ipairs(self.cards) do
        if index > 1 then
            y = y + CARD_GAP
        end
        card.frame:ClearAllPoints()
        card.frame:SetPoint("TOPLEFT", 0, -y)
        card.frame:SetWidth(width)
        y = y + card:Layout(width)
    end
    self.frame:SetHeight(math.max(1, y))
    return y
end

local function CreatePage(parent, item)
    local page = setmetatable({ cards = {} }, Page)
    page.frame = CreateFrame("Frame", nil, parent)
    page.frame:SetPoint("TOPLEFT")
    page.frame:SetPoint("TOPRIGHT")
    page.frame:Hide()
    if item.build then
        item.build(page)
    else
        page:AddCard(item.label):AddText(PLACEHOLDER_BODY)
    end
    return page
end

local function LayoutPage()
    if not contentScroll then return end
    local page = pages[selectedKey]
    local child = contentScroll.child
    local width = child:GetWidth()
    if not page or width <= 1 then return end
    child:SetHeight(math.max(1, page:Layout(width)))
    contentScroll.Sync()
end

-- Sidebar ----------------------------------------------------------------------

local function UpdateRow(row)
    local r, g, b
    if row.item.key == selectedKey then
        r, g, b = Accent()
        row.selectedBg:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0.16), CreateColor(r, g, b, 0.02))
        row.bar:SetColorTexture(r, g, b, 1)
        row.selectedBg:Show()
        row.bar:Show()
        row.hoverBg:Hide()
    else
        local colour = row.hovered and C.textPrimary or C.textSecondary
        r, g, b = colour[1], colour[2], colour[3]
        row.selectedBg:Hide()
        row.bar:Hide()
        row.hoverBg:SetShown(row.hovered)
    end
    row.label:SetTextColor(r, g, b)
end

local function UpdateHeader(header)
    header.chevron:SetTexture(header.open and ICON_CHEVRON_DOWN or ICON_CHEVRON_RIGHT)
    local colour = header.hovered and C.textPrimary or C.textMuted
    header.chevron:SetVertexColor(colour[1], colour[2], colour[3])
end

local function Matches(item)
    return filter == "" or item.label:lower():find(filter, 1, true) ~= nil
end

-- Places the category headers and the item rows that the search and the
-- folded categories leave visible.
local function LayoutNav()
    if not navScroll then return end
    local y = 0
    local anyShown = false
    for _, widget in ipairs(groupWidgets) do
        local matched = 0
        for _, row in ipairs(widget.rows) do
            row.matches = Matches(row.item)
            if row.matches then
                matched = matched + 1
            end
        end

        local header = widget.header
        local showGroup = matched > 0
        header:SetShown(showGroup)
        header.open = filter ~= "" or not Folded()[widget.group.key]
        UpdateHeader(header)
        if showGroup then
            anyShown = true
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", 0, -y)
            header:SetPoint("TOPRIGHT", 0, -y)
            y = y + GROUP_HEIGHT
        end

        for _, row in ipairs(widget.rows) do
            if showGroup and header.open and row.matches then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -y)
                row:SetPoint("TOPRIGHT", 0, -y)
                row:Show()
                y = y + ITEM_HEIGHT
            else
                row:Hide()
                -- OnLeave does not fire for a row hidden under the cursor.
                if row.hovered then
                    row.hovered = false
                    UpdateRow(row)
                    tooltip:Hide()
                end
            end
        end
    end
    noMatches:SetShown(not anyShown)
    navScroll.child:SetHeight(math.max(1, y))
    navScroll.Sync()
end

local function Select(key)
    selectedKey = key
    ns.db.profile.window.section = key
    for _, row in ipairs(rows) do
        UpdateRow(row)
    end
    for pageKey, page in pairs(pages) do
        page.frame:SetShown(pageKey == key)
    end
    if contentScroll then
        contentScroll:SetVerticalScroll(0)
    end
    LayoutPage()
end

local function CreateRow(parent, item)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ITEM_HEIGHT)
    row.item = item
    row.hovered = false

    row.hoverBg = Solid(row, "BACKGROUND", C.hoverBg)
    row.hoverBg:SetAllPoints()

    -- A white texture; UpdateRow tints it with the accent gradient.
    row.selectedBg = Solid(row, "BACKGROUND", C.textPrimary)
    row.selectedBg:SetAllPoints()

    row.bar = Solid(row, "ARTWORK", C.textPrimary)
    row.bar:SetPoint("TOPLEFT")
    row.bar:SetPoint("BOTTOMLEFT")
    row.bar:SetWidth(ITEM_BAR_WIDTH)

    row.label = Text(row, FONT_ITEM, C.textSecondary)
    row.label:SetPoint("LEFT", ITEM_INDENT, 0)
    row.label:SetPoint("RIGHT", -ITEM_PAD_RIGHT, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.label:SetMaxLines(1)
    row.label:SetText(item.label)

    row:SetScript("OnEnter", function(self)
        self.hovered = true
        UpdateRow(self)
        ShowTooltip(self)
    end)
    row:SetScript("OnLeave", function(self)
        self.hovered = false
        UpdateRow(self)
        tooltip:Hide()
    end)
    row:SetScript("OnClick", function(self)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        Select(self.item.key)
    end)

    rows[#rows + 1] = row
    return row
end

local function CreateHeader(parent, group)
    local header = CreateFrame("Button", nil, parent)
    header:SetHeight(GROUP_HEIGHT)
    header.hovered = false
    header.open = true

    local bullet = header:CreateTexture(nil, "ARTWORK")
    bullet:SetSize(GROUP_BULLET, GROUP_BULLET)
    bullet:SetPoint("LEFT", GROUP_INSET, 0)

    local label = Text(header, FONT_GROUP, C.textPrimary)
    label:SetPoint("LEFT", bullet, "RIGHT", GROUP_LABEL_GAP, 0)
    label:SetText(group.label)

    OnAccent(function(r, g, b)
        bullet:SetColorTexture(r, g, b, 1)
        label:SetTextColor(r, g, b)
    end)

    header.chevron = header:CreateTexture(nil, "ARTWORK")
    header.chevron:SetSize(CHEVRON_SIZE, CHEVRON_SIZE)
    header.chevron:SetPoint("RIGHT", -CHEVRON_INSET, 0)
    UpdateHeader(header)

    header:SetScript("OnEnter", function(self)
        self.hovered = true
        UpdateHeader(self)
    end)
    header:SetScript("OnLeave", function(self)
        self.hovered = false
        UpdateHeader(self)
    end)
    header:SetScript("OnHide", function(self)
        self.hovered = false
        UpdateHeader(self)
    end)
    header:SetScript("OnClick", function()
        -- Every category with a match is open while searching.
        if filter ~= "" then return end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        local folded = Folded()
        folded[group.key] = not folded[group.key] or nil
        LayoutNav()
    end)

    return header
end

local function CreateSearch(sidebar)
    local box = CreateFrame("EditBox", nil, sidebar)
    box:SetPoint("TOPLEFT", SEARCH_INSET, -SEARCH_INSET)
    box:SetPoint("TOPRIGHT", -(1 + SEARCH_INSET), -SEARCH_INSET)
    box:SetHeight(SEARCH_HEIGHT)
    box:SetAutoFocus(false)
    box:SetMaxLetters(SEARCH_MAX_LETTERS)
    box:SetTextInsets(SEARCH_TEXT_INSET, SEARCH_TEXT_INSET, 0, 0)
    RegisterFont(box, FONT_SEARCH)
    box:SetTextColor(C.textPrimary[1], C.textPrimary[2], C.textPrimary[3])

    local background = Solid(box, "BACKGROUND", C.bgWindow)
    background:SetAllPoints()
    AddEdge(box, 0, C.borderInner)

    local placeholder = Text(box, FONT_SEARCH, C.textMuted)
    placeholder:SetPoint("LEFT", SEARCH_TEXT_INSET, 0)
    placeholder:SetText("Search...")

    box:SetScript("OnTextChanged", function(self)
        local text = strtrim(self:GetText() or "")
        placeholder:SetShown(self:GetText() == "")
        filter = text:lower()
        LayoutNav()
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    -- Enter opens the first item that is still listed.
    box:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        for _, row in ipairs(rows) do
            if row:IsShown() then
                PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
                Select(row.item.key)
                return
            end
        end
    end)

    return box
end

local function CreateSidebar(window)
    local sidebar = CreateFrame("Frame", nil, window)
    sidebar:SetPoint("TOPLEFT", BORDER, -(BORDER + TITLE_HEIGHT))
    sidebar:SetPoint("BOTTOMLEFT", BORDER, BORDER + FOOTER_HEIGHT)
    sidebar:SetWidth(SIDEBAR_WIDTH)
    Background(sidebar, C.bgSidebar)

    local edge = Solid(sidebar, "BORDER", C.borderInner)
    edge:SetPoint("TOPRIGHT")
    edge:SetPoint("BOTTOMRIGHT")
    edge:SetWidth(1)

    search = CreateSearch(sidebar)

    local scroll = CreateScroll(sidebar)
    scroll:SetPoint("TOPLEFT", 0, -(2 * SEARCH_INSET + SEARCH_HEIGHT))
    scroll:SetPoint("BOTTOMRIGHT", -(1 + 2 * SCROLL_BAR_GAP + SCROLL_BAR_WIDTH), SEARCH_INSET)

    for _, group in ipairs(GROUPS) do
        local widget = { group = group, rows = {} }
        widget.header = CreateHeader(scroll.child, group)
        for index, item in ipairs(group.items) do
            widget.rows[index] = CreateRow(scroll.child, item)
        end
        groupWidgets[#groupWidgets + 1] = widget
    end

    noMatches = Text(scroll.child, FONT_ITEM, C.textMuted)
    noMatches:SetPoint("TOPLEFT", GROUP_INSET, -(GROUP_HEIGHT - FONT_ITEM) / 2)
    noMatches:SetText("No matches")
    noMatches:Hide()

    scroll:SetScript("OnSizeChanged", function(self, width)
        self.child:SetWidth(width)
        LayoutNav()
    end)
    navScroll = scroll
end

-- Title bar, content, footer ------------------------------------------------------

local function CreateCloseButton(parent, window)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(CLOSE_SIZE, CLOSE_SIZE)
    button:SetPoint("RIGHT", -CLOSE_INSET, 0)
    button:SetHitRectInsets(-4, -4, -4, -4)

    local background = Solid(button, "BACKGROUND", C.closeHoverBg)
    background:SetAllPoints()
    background:Hide()

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON_CLOSE)
    icon:SetSize(CLOSE_ICON_SIZE, CLOSE_ICON_SIZE)
    icon:SetPoint("CENTER")

    local function SetHovered(hovered)
        local colour = hovered and C.closeHover or C.textMuted
        icon:SetVertexColor(colour[1], colour[2], colour[3])
        background:SetShown(hovered)
    end
    SetHovered(false)

    button:SetScript("OnEnter", function() SetHovered(true) end)
    button:SetScript("OnLeave", function() SetHovered(false) end)
    -- OnLeave does not fire when the button is hidden under the cursor.
    button:SetScript("OnHide", function() SetHovered(false) end)
    button:SetScript("OnClick", function() window:Hide() end)
    return button
end

local function CreateTitleBar(window)
    local bar = CreateFrame("Frame", nil, window)
    bar:SetPoint("TOPLEFT", BORDER, -BORDER)
    bar:SetPoint("TOPRIGHT", -BORDER, -BORDER)
    bar:SetHeight(TITLE_HEIGHT)
    Background(bar, C.bgSidebar)
    AddLine(bar, "BOTTOM", C.borderInner)

    -- The title bar is the drag handle.
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function()
        if InCombatLockdown() then
            ns.Print("The window cannot be moved in combat.")
            return
        end
        window:StartMoving()
    end)
    bar:SetScript("OnDragStop", function()
        window:StopMovingOrSizing()
        SaveGeometry(window)
    end)

    local logo = bar:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(LOGO)
    logo:SetSize(TITLE_LOGO_SIZE, TITLE_LOGO_SIZE)
    logo:SetPoint("LEFT", TITLE_INSET, 0)
    OnAccent(function(r, g, b)
        logo:SetVertexColor(r, g, b)
    end)

    local name = Text(bar, FONT_TITLE, C.textPrimary)
    name:SetPoint("LEFT", logo, "RIGHT", TITLE_NAME_GAP, 0)
    name:SetText(ns.NAME)

    CreateCloseButton(bar, window)
end

local function CreateContent(window)
    local content = CreateFrame("Frame", nil, window)
    content:SetPoint("TOPLEFT", BORDER + SIDEBAR_WIDTH, -(BORDER + TITLE_HEIGHT))
    content:SetPoint("BOTTOMRIGHT", -BORDER, BORDER + FOOTER_HEIGHT)
    Background(content, C.bgWindow)

    local scroll = CreateScroll(content)
    scroll:SetPoint("TOPLEFT", CONTENT_PAD, -CONTENT_PAD)
    scroll:SetPoint("BOTTOMRIGHT", -(CONTENT_PAD + SCROLL_BAR_GAP + SCROLL_BAR_WIDTH), CONTENT_PAD)

    for _, row in ipairs(rows) do
        pages[row.item.key] = CreatePage(scroll.child, row.item)
    end

    scroll:SetScript("OnSizeChanged", function(self, width)
        self.child:SetWidth(width)
        LayoutPage()
    end)
    contentScroll = scroll
end

local function CreateFooter(window)
    local bar = CreateFrame("Frame", nil, window)
    bar:SetPoint("BOTTOMLEFT", BORDER, BORDER)
    bar:SetPoint("BOTTOMRIGHT", -BORDER, BORDER)
    bar:SetHeight(FOOTER_HEIGHT)
    Background(bar, C.bgSidebar)
    AddLine(bar, "TOP", C.borderInner)

    local version = Text(bar, FONT_FOOTER, C.textMuted)
    version:SetPoint("LEFT", FOOTER_INSET, 0)
    version:SetText("v" .. ns.VERSION)
end

local function CreateGrip(window)
    local grip = CreateFrame("Button", nil, window)
    grip:SetSize(GRIP_SIZE, GRIP_SIZE)
    grip:SetPoint("BOTTOMRIGHT", -(BORDER + GRIP_INSET), BORDER + GRIP_INSET)
    grip:SetFrameLevel(window:GetFrameLevel() + GRIP_LEVEL)

    local icon = grip:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON_GRIP)
    icon:SetAllPoints()
    icon:SetVertexColor(C.grip[1], C.grip[2], C.grip[3])

    local sizing = false
    grip:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        if InCombatLockdown() then
            ns.Print("The window cannot be resized in combat.")
            return
        end
        sizing = true
        window:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        if not sizing then return end
        sizing = false
        window:StopMovingOrSizing()
        SaveGeometry(window)
    end)
end

-- Window -----------------------------------------------------------------------

-- Also run on show: OnSizeChanged may not have reached the scroll children yet.
local function Relayout()
    navScroll.child:SetWidth(navScroll:GetWidth())
    contentScroll.child:SetWidth(contentScroll:GetWidth())
    LayoutNav()
    LayoutPage()
end

local function Create()
    -- Named so that the Escape key can close it through UISpecialFrames.
    local window = CreateFrame("Frame", "NascentMainFrame", UIParent)
    window:SetSize(WIDTH, HEIGHT)
    window:SetPoint("CENTER")
    window:SetFrameStrata("MEDIUM")
    window:SetToplevel(true)
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:SetMovable(true)
    window:SetResizable(true)
    window:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
    window:Hide()
    -- Scale first: the saved offsets are in the window's own scaled units.
    window:SetScale(Clamp(ns.db.profile.scale, SCALE_MIN, SCALE_MAX))
    RestoreGeometry(window)

    AddEdge(window, 0, C.borderOuter)
    AddEdge(window, 1, C.borderInner)

    tooltip = CreateTooltip(window)
    CreateTitleBar(window)
    CreateSidebar(window)
    CreateContent(window)
    CreateFooter(window)
    CreateGrip(window)

    window:SetScript("OnShow", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
        Relayout()
    end)
    window:SetScript("OnHide", function(self)
        PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
        -- Hiding mid-drag (Escape, combat) never delivers the mouse-up.
        self:StopMovingOrSizing()
        SaveGeometry(self)
        search:ClearFocus()
        -- OnLeave does not fire for a row hidden under the cursor.
        tooltip:Hide()
        for _, row in ipairs(rows) do
            row.hovered = false
            UpdateRow(row)
        end
    end)

    if UISpecialFrames then
        tinsert(UISpecialFrames, "NascentMainFrame")
    end

    return window
end

-- Offer the font to other addons when LibSharedMedia is installed. Called at
-- login, when every addon that might carry the library has loaded.
function Window:RegisterMedia()
    local LSM = LibStub("LibSharedMedia-3.0", true)
    if LSM then
        LSM:Register("font", "Expressway", FONT)
    end
end

-- Building blocks for the page files (Home.lua, Settings.lua), so their
-- controls match the window and follow the font size offset and the accent.
-- A page's build function receives a page; page:AddCard(title) returns a card
-- with AddText, AddControl and AddButtons.
Window.UI = {
    C = C,
    Solid = Solid,
    Background = Background,
    Text = Text,
    AddEdge = AddEdge,
    AddLine = AddLine,
    Button = CreateButton,
    CloseButton = CreateCloseButton,
    Clamp = Clamp,
    Accent = Accent,
    OnAccent = OnAccent,
    -- Runs `relayout` after the font size offset or the UI scale changes.
    OnRelayout = function(relayout)
        layoutListeners[#layoutListeners + 1] = relayout
    end,
    LOGO = LOGO,
    BORDER = BORDER,
    TITLE_HEIGHT = TITLE_HEIGHT,
    TITLE_INSET = TITLE_INSET,
    TITLE_LOGO_SIZE = TITLE_LOGO_SIZE,
    TITLE_NAME_GAP = TITLE_NAME_GAP,
    FOOTER_HEIGHT = FOOTER_HEIGHT,
    FOOTER_INSET = FOOTER_INSET,
    BUTTON_GAP = BUTTON_GAP,
    FONT_TITLE = FONT_TITLE,
    FONT_BODY = FONT_BODY,
    FONT_FOOTER = FONT_FOOTER,
    SCALE_MIN = SCALE_MIN,
    SCALE_MAX = SCALE_MAX,
}

local function NotifyRelayout()
    for _, relayout in ipairs(layoutListeners) do
        relayout()
    end
end

-- The Apply functions push a changed setting from ns.db.profile (or ns.COLOR)
-- into the window. They do nothing before the window has been built.

function Window:ApplyScale()
    if frame then
        frame:SetScale(Clamp(ns.db.profile.scale, SCALE_MIN, SCALE_MAX))
    end
    NotifyRelayout()
end

function Window:ApplyOpacity()
    for _, entry in ipairs(backgrounds) do
        local colour = entry.colour
        entry.texture:SetColorTexture(colour[1], colour[2], colour[3], ns.db.profile.opacity)
    end
end

function Window:ApplyFonts()
    for _, entry in ipairs(fontStrings) do
        SetTextFont(entry.text, entry.size)
    end
    if frame then
        Relayout()
    end
    NotifyRelayout()
end

-- Re-lays out the selected page, for pages whose content changed size.
function Window:Relayout()
    if frame and frame:IsShown() then
        LayoutPage()
    end
end

function Window:ApplyAccent()
    local r, g, b = Accent()
    for _, paint in ipairs(accentListeners) do
        paint(r, g, b)
    end
    for _, row in ipairs(rows) do
        UpdateRow(row)
    end
end

local function EnsureFrame()
    if frame then return end
    frame = Create()
    -- Reopen on the section that was selected last time, if it still exists.
    local key = DEFAULT_KEY
    for _, row in ipairs(rows) do
        if row.item.key == ns.db.profile.window.section then
            key = row.item.key
        end
    end
    Select(key)
end

function Window:Toggle()
    EnsureFrame()
    if frame:IsShown() then
        frame:Hide()
    elseif ns.db.profile.hideInCombat and InCombatLockdown() then
        -- Asking twice in the same fight cancels the pending open.
        reopenAfterCombat = not reopenAfterCombat
        if reopenAfterCombat then
            ns.Print("The window is hidden in combat. It will open when combat ends.")
        else
            ns.Print("The window will stay closed when combat ends.")
        end
    else
        frame:Show()
    end
end

-- Opens the window on the section with item key `key`.
function Window:ShowSection(key)
    EnsureFrame()
    if pages[key] then
        Select(key)
    end
    if not frame:IsShown() then
        Window:Toggle()
    end
end

-- Called by Core.lua on PLAYER_REGEN_DISABLED (true) and PLAYER_REGEN_ENABLED
-- (false).
function Window:OnCombat(inCombat)
    if inCombat then
        if ns.db.profile.hideInCombat and frame and frame:IsShown() then
            reopenAfterCombat = true
            frame:Hide()
        end
    elseif reopenAfterCombat then
        reopenAfterCombat = false
        EnsureFrame()
        frame:Show()
    end
end
