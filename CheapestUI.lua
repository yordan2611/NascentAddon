local _, ns = ...

-- The cheapest-items list and the pop-up window that shows it when the bags
-- are full (docs/UI-SPEC.md section 8). The list is also used on the Cheapest
-- items page. The data and the actions come from Cheapest.lua.

local CheapestUI = {}
ns.CheapestUI = CheapestUI

local ROW_HEIGHT = 36
local ROW_ICON = 26
local ROW_INSET = 6
local ROW_TEXT_GAP = 8
local ROW_LINE_GAP = 2
local ROW_BUTTON_WIDTH = 58
local ROW_BUTTON_HEIGHT = 22
local TAG_GAP = 6
local COUNTDOWN_HEIGHT = 2
local EMPTY_PAD = 6
local EMPTY_LINK_GAP = 4

local LOOT_HEIGHT = 30
local LOOT_ICON = 20
local LOOT_GAP = 8

local POPUP_WIDTH = 480
local POPUP_PAD = 8
local BESIDE_LOOT_GAP = 12     -- between the loot window and the pop-up
local TITLE_TAG_GAP = 10
local FOOTER_LINK_GAP = 14

local QUALITY_FALLBACK = { r = 1, g = 1, b = 1 }

local function QualityColour(quality)
    local colour = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    return colour or QUALITY_FALLBACK
end

-- "rrggbb" for a { r, g, b } colour, for |c escape codes.
local function Hex(colour)
    return ("%02x%02x%02x"):format(math.floor(colour[1] * 255 + 0.5),
        math.floor(colour[2] * 255 + 0.5), math.floor(colour[3] * 255 + 0.5))
end

local function Muted(text)
    return "|cff" .. Hex(ns.Window.UI.C.textMuted) .. text .. "|r"
end

local function Money(copper)
    return ns.Cheapest:FormatMoney(copper)
end

local function Stacks(count)
    return count == 1 and "1 stack" or (count .. " stacks")
end

-- List ---------------------------------------------------------------------------------

-- Vendor value, the price of one item for a stack, and the auction value.
local function DetailText(entry)
    local text = "Vendor " .. Money(entry.vendorValue)
    if entry.count > 1 then
        text = text .. " (" .. Money(entry.unitVendor) .. " each)"
    end
    if entry.auctionValue then
        text = text .. "   Auction " .. Money(entry.auctionValue)
    end
    return text
end

local function ShowRowTooltip(row)
    local entry = row.entry
    if not entry then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetBagItem(entry.bag, entry.slot)
    local C = ns.Window.UI.C
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Shift-click to link in chat, right-click to ignore.",
        C.textMuted[1], C.textMuted[2], C.textMuted[3])
    GameTooltip:AddLine("Shift-click Delete to skip the confirmation.",
        C.textMuted[1], C.textMuted[2], C.textMuted[3])
    GameTooltip:Show()
end

-- The thin bar under an armed Delete that empties as the confirmation runs out.
local function UpdateCountdown(button)
    local Cheapest = ns.Cheapest
    local width = (button:GetWidth() - 2) * Cheapest:ArmedRemaining() / Cheapest.ARM_SECONDS
    if width > 0 then
        button.countdown:SetWidth(width)
        button.countdown:Show()
    else
        button.countdown:Hide()
    end
end

local function CreateRow(list)
    local UI = ns.Window.UI
    local Cheapest = ns.Cheapest
    local row = CreateFrame("Frame", nil, list)
    row:SetHeight(ROW_HEIGHT)
    row:EnableMouse(true)

    row.hover = UI.Solid(row, "BACKGROUND", UI.C.hoverBg)
    row.hover:SetAllPoints()
    row.hover:Hide()

    row.line = UI.AddLine(row, "BOTTOM", UI.C.divider)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_ICON, ROW_ICON)
    row.icon:SetPoint("LEFT", ROW_INSET, 0)

    row.ignore = UI.Button(row, "Ignore", function() Cheapest:Ignore(row.entry) end)
    row.sell = UI.Button(row, "Sell", function() Cheapest:Sell(row.entry) end)
    row.delete = UI.Button(row, "Delete", function() Cheapest:Delete(row.entry, IsShiftKeyDown()) end)
    for _, button in ipairs({ row.ignore, row.sell, row.delete }) do
        button:SetSize(ROW_BUTTON_WIDTH, ROW_BUTTON_HEIGHT)
    end
    row.ignore:SetPoint("RIGHT", -ROW_INSET, 0)

    local countdown = UI.Solid(row.delete, "OVERLAY", UI.C.closeHover)
    countdown:SetPoint("BOTTOMLEFT", 1, 1)
    countdown:SetHeight(COUNTDOWN_HEIGHT)
    countdown:Hide()
    row.delete.countdown = countdown

    row.name = UI.Text(row, UI.FONT_BODY, UI.C.textPrimary)
    row.name:SetPoint("BOTTOMLEFT", row.icon, "RIGHT", ROW_TEXT_GAP, ROW_LINE_GAP / 2)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.name:SetMaxLines(1)

    row.tag = UI.Text(row, UI.FONT_FOOTER, UI.C.closeHover)
    row.tag:SetText("Worth more than the loot")
    row.tag:Hide()

    row.detail = UI.Text(row, UI.FONT_FOOTER, UI.C.textMuted)
    row.detail:SetPoint("TOPLEFT", row.icon, "RIGHT", ROW_TEXT_GAP, -ROW_LINE_GAP / 2)
    row.detail:SetJustifyH("LEFT")
    row.detail:SetWordWrap(false)
    row.detail:SetMaxLines(1)

    -- The item tooltip, from the bag slot so it shows the real stack.
    local function HideTooltip()
        row.hover:Hide()
        if GameTooltip:GetOwner() == row then
            GameTooltip:Hide()
        end
    end
    row:SetScript("OnEnter", function()
        row.hover:Show()
        ShowRowTooltip(row)
    end)
    row:SetScript("OnLeave", HideTooltip)
    -- OnLeave does not fire for a row hidden under the cursor.
    row:SetScript("OnHide", HideTooltip)

    -- Shift-click (the game's chat-link modifier) or Ctrl-click links the item;
    -- right-click ignores it.
    row:SetScript("OnMouseUp", function(_, button)
        local entry = row.entry
        if not entry then return end
        if button == "RightButton" then
            Cheapest:Ignore(entry)
        elseif button == "LeftButton" and entry.link and (IsModifiedClick("CHATLINK") or IsControlKeyDown()) then
            ChatFrameUtil.InsertLink(entry.link)
        end
    end)

    return row
end

-- `loot` is the most wanted item still in the loot window, or nil; rows worth
-- more than it get a tag, as deleting them for it would lose money.
local function PaintRow(row, entry, loot)
    local UI = ns.Window.UI
    local Cheapest = ns.Cheapest
    row.entry = entry
    row.icon:SetTexture(entry.icon)

    local colour = QualityColour(entry.quality)
    local name = entry.name
    if entry.count > 1 then
        name = name .. " " .. Muted("x" .. entry.count)
    end
    row.name:SetText(name)
    row.name:SetTextColor(colour.r, colour.g, colour.b)
    row.detail:SetText(DetailText(entry))

    -- From the right: Ignore, Delete, and Sell while a vendor is open. Sell is
    -- the main action at a vendor, so it goes first and takes the accent.
    local merchant = Cheapest:IsMerchantOpen()
    row.delete:ClearAllPoints()
    row.delete:SetPoint("RIGHT", row.ignore, "LEFT", -UI.BUTTON_GAP, 0)
    row.sell:ClearAllPoints()
    row.sell:SetPoint("RIGHT", row.delete, "LEFT", -UI.BUTTON_GAP, 0)
    row.sell:SetShown(merchant)
    row.sell.label:SetTextColor(UI.Accent())
    local leftmost = merchant and row.sell or row.delete

    local armed = Cheapest:IsArmed(entry)
    row.delete.label:SetText(armed and "Confirm" or "Delete")
    local labelColour = armed and UI.C.closeHover or UI.C.textPrimary
    row.delete.label:SetTextColor(labelColour[1], labelColour[2], labelColour[3])
    if armed then
        row.delete:SetScript("OnUpdate", UpdateCountdown)
        UpdateCountdown(row.delete)
    else
        row.delete:SetScript("OnUpdate", nil)
        row.delete.countdown:Hide()
    end

    local worthMore = loot ~= nil and entry.value > loot.value
    row.tag:SetShown(worthMore)
    row.tag:ClearAllPoints()
    row.tag:SetPoint("BOTTOMRIGHT", leftmost, "LEFT", -ROW_TEXT_GAP, ROW_LINE_GAP / 2)
    if worthMore then
        row.name:SetPoint("BOTTOMRIGHT", row.tag, "BOTTOMLEFT", -TAG_GAP, 0)
    else
        row.name:SetPoint("BOTTOMRIGHT", leftmost, "LEFT", -ROW_TEXT_GAP, ROW_LINE_GAP / 2)
    end
    row.detail:SetPoint("TOPRIGHT", leftmost, "LEFT", -ROW_TEXT_GAP, -ROW_LINE_GAP / 2)

    -- Repaint the tooltip if the row changed under the cursor.
    if GameTooltip:GetOwner() == row then
        ShowRowTooltip(row)
    end
end

-- Why nothing is listed, from what the last scan left out.
local function EmptyText()
    local skipped = ns.Cheapest:GetSkipped()
    local parts = {}
    if skipped.quality > 0 then
        parts[#parts + 1] = Stacks(skipped.quality) .. " of a quality you left unticked"
    end
    if skipped.ignored > 0 then
        parts[#parts + 1] = Stacks(skipped.ignored) .. " ignored"
    end
    if skipped.soulbound > 0 then
        parts[#parts + 1] = Stacks(skipped.soulbound) .. " soulbound"
    end
    if #parts == 0 then
        return "Nothing to list: nothing in your bags can be sold."
    end
    return "Nothing to list. Left out: " .. table.concat(parts, ", ") .. "."
end

-- The loot to compare the rows with: the most wanted item still in the loot
-- window, unless it is a quest item (always worth the room) or has no price yet.
local function LootToCompare()
    local loot = ns.Cheapest:GetPendingLoot()[1]
    if loot and not loot.quest and loot.value then
        return loot
    end
    return nil
end

-- A list of the cheapest stacks. `maxRows()` returns how many to show.
-- `list.Layout(width)` repaints it from Cheapest:GetEntries() and returns its
-- height; the caller sizes its own frame from that. With `filterLink`, an
-- empty list offers a link to the page's filters.
function CheapestUI.CreateList(parent, maxRows, filterLink)
    local UI = ns.Window.UI
    local list = CreateFrame("Frame", nil, parent)
    list:SetSize(1, 1)
    local rows = {}

    local empty = UI.Text(list, UI.FONT_BODY, UI.C.textSecondary)
    empty:SetPoint("TOPLEFT", 0, -EMPTY_PAD)
    empty:SetJustifyH("LEFT")
    empty:SetWordWrap(true)

    local link
    if filterLink then
        link = UI.TextButton(list, "Change what is listed", function()
            ns.Window:ShowSection("cheapest")
        end)
        link:SetPoint("TOPLEFT", empty, "BOTTOMLEFT", 0, -EMPTY_LINK_GAP)
    end

    function list.Layout(width)
        local entries = ns.Cheapest:GetEntries()
        local count = math.min(#entries, maxRows())
        local loot = count > 0 and LootToCompare() or nil
        for index = 1, count do
            local row = rows[index]
            if not row then
                row = CreateRow(list)
                rows[index] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
            row:SetPoint("TOPRIGHT", 0, -(index - 1) * ROW_HEIGHT)
            row.line:SetShown(index < count)
            PaintRow(row, entries[index], loot)
            row:Show()
        end
        for index = count + 1, #rows do
            rows[index].entry = nil
            rows[index]:Hide()
        end
        empty:SetShown(count == 0)
        if link then
            link:SetShown(count == 0)
        end
        if count == 0 then
            empty:SetWidth(width)
            empty:SetText(EmptyText())
            local height = empty:GetStringHeight() + 2 * EMPTY_PAD
            if link then
                height = height + link:GetHeight() + EMPTY_LINK_GAP
            end
            return height
        end
        return count * ROW_HEIGHT
    end

    return list
end

-- Pop-up ---------------------------------------------------------------------------------

local Popup = {}
ns.CheapestWindow = Popup

local frame, list, lootLine, freeTag, summaryText, sellPoor, optionsButton
local besideLoot = false       -- placed beside the loot window rather than at the saved spot

-- Saved as the top-left corner, so the spot is the same whether the pop-up was
-- placed by hand or beside the loot window when it was dragged.
local function SavePosition(window)
    local saved = ns.db.profile.cheapest.window
    local left, top = window:GetLeft(), window:GetTop()
    if not (left and top) then return end
    saved.point, saved.relativePoint, saved.x, saved.y = "TOPLEFT", "BOTTOMLEFT", left, top
    window:ClearAllPoints()
    window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

local function RestorePosition(window)
    local saved = ns.db.profile.cheapest.window
    window:ClearAllPoints()
    if type(saved.point) == "string" and type(saved.relativePoint) == "string"
        and type(saved.x) == "number" and type(saved.y) == "number" then
        window:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    else
        window:SetPoint("CENTER", 0, 150)
    end
end

-- Beside the loot window, on its right unless the pop-up would run off the
-- screen there. Returns false when no loot window is shown.
local function PlaceBesideLoot(window)
    local loot = ns.Cheapest:LootWindowFrame()
    if not loot then return false end
    local lootRight = (loot:GetRight() or 0) * loot:GetEffectiveScale()
    local screenRight = (UIParent:GetRight() or 0) * UIParent:GetEffectiveScale()
    local width = (POPUP_WIDTH + BESIDE_LOOT_GAP) * window:GetEffectiveScale()
    window:ClearAllPoints()
    if lootRight + width <= screenRight then
        window:SetPoint("TOPLEFT", loot, "TOPRIGHT", BESIDE_LOOT_GAP, 0)
    else
        window:SetPoint("TOPRIGHT", loot, "TOPLEFT", -BESIDE_LOOT_GAP, 0)
    end
    return true
end

-- The line above the list naming the loot that did not fit.
local function PaintLootLine()
    local items = ns.Cheapest:GetPendingLoot()
    local first = items[1]
    lootLine.slot = first and first.slot
    if not first then
        lootLine:Hide()
        return 0
    end
    lootLine.icon:SetTexture(first.icon)
    local colour = QualityColour(first.quality)
    local text = "|cff" .. Hex({ colour.r, colour.g, colour.b }) .. (first.name or "?") .. "|r"
    if first.quantity > 1 then
        text = text .. " " .. Muted("x" .. first.quantity)
    end
    if first.quest then
        text = text .. "  " .. Muted("quest item")
    elseif first.value then
        text = text .. "  " .. Money(first.value)
    end
    lootLine.name:SetText(text)
    lootLine.more:SetText(#items > 1 and ("+" .. (#items - 1) .. " more") or "")
    lootLine:Show()
    if GameTooltip:GetOwner() == lootLine and GameTooltip.SetLootItem then
        GameTooltip:SetLootItem(first.slot)
    end
    return LOOT_HEIGHT
end

local function PaintFooter()
    local UI = ns.Window.UI
    local Cheapest = ns.Cheapest

    local free = Cheapest:FreeSlots()
    freeTag:SetText(free .. " free")
    local colour = free == 0 and UI.C.closeHover or UI.C.textMuted
    freeTag:SetTextColor(colour[1], colour[2], colour[3])

    local entries = Cheapest:GetEntries()
    if #entries == 0 then
        summaryText:SetText("Nothing listed")
    else
        local total = 0
        for _, entry in ipairs(entries) do
            total = total + entry.value
        end
        summaryText:SetText(Stacks(#entries) .. " listed, worth " .. Money(total))
    end

    local count = 0
    if Cheapest:IsMerchantOpen() and not Cheapest:IsSelling() then
        count = Cheapest:PoorSummary()
    end
    if count > 0 then
        sellPoor.text:SetText("Sell all Poor (" .. count .. ")")
        sellPoor:SetWidth(math.max(1, sellPoor.text:GetStringWidth()))
    end
    sellPoor:SetShown(count > 0)
end

local function Layout()
    if not (frame and frame:IsShown()) then return end
    local UI = ns.Window.UI
    local inner = POPUP_WIDTH - 2 * UI.BORDER - 2 * POPUP_PAD
    local lootHeight = PaintLootLine()
    local offset = lootHeight > 0 and (lootHeight + LOOT_GAP) or 0
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", POPUP_PAD, -(POPUP_PAD + offset))
    list:SetWidth(inner)
    local height = list.Layout(inner)
    list:SetHeight(math.max(1, height))
    frame:SetHeight(2 * UI.BORDER + UI.TITLE_HEIGHT + 2 * POPUP_PAD + offset + height + UI.FOOTER_HEIGHT)
    PaintFooter()
end

local function ApplyScale()
    if frame then
        local UI = ns.Window.UI
        frame:SetScale(UI.Clamp(ns.db.profile.scale, UI.SCALE_MIN, UI.SCALE_MAX))
        Layout()
    end
end

local function CreateTitleBar(window)
    local UI = ns.Window.UI
    local bar = CreateFrame("Frame", nil, window)
    bar:SetPoint("TOPLEFT", UI.BORDER, -UI.BORDER)
    bar:SetPoint("TOPRIGHT", -UI.BORDER, -UI.BORDER)
    bar:SetHeight(UI.TITLE_HEIGHT)
    UI.Background(bar, UI.C.bgSidebar)
    UI.AddLine(bar, "BOTTOM", UI.C.borderInner)

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
        SavePosition(window)
        -- Dragged away from the loot window: keep it where the player put it.
        local settings = ns.db.profile.cheapest
        if besideLoot and settings.followLoot then
            settings.followLoot = false
            ns.Print("The pop-up now opens where you put it. To place it beside the loot "
                .. "window again, turn that back on under Options.")
        end
        besideLoot = false
    end)

    local logo = bar:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(UI.LOGO)
    logo:SetSize(UI.TITLE_LOGO_SIZE, UI.TITLE_LOGO_SIZE)
    logo:SetPoint("LEFT", UI.TITLE_INSET, 0)
    UI.OnAccent(function(r, g, b)
        logo:SetVertexColor(r, g, b)
    end)

    local name = UI.Text(bar, UI.FONT_TITLE, UI.C.textPrimary)
    name:SetPoint("LEFT", logo, "RIGHT", UI.TITLE_NAME_GAP, 0)
    name:SetText("Cheapest items")

    local close = UI.CloseButton(bar, window)
    freeTag = UI.Text(bar, UI.FONT_FOOTER, UI.C.textMuted)
    freeTag:SetPoint("RIGHT", close, "LEFT", -TITLE_TAG_GAP, 0)
end

local function CreateLootLine(body)
    local UI = ns.Window.UI
    local line = CreateFrame("Frame", nil, body)
    line:SetPoint("TOPLEFT", POPUP_PAD, -POPUP_PAD)
    line:SetPoint("TOPRIGHT", -POPUP_PAD, -POPUP_PAD)
    line:SetHeight(LOOT_HEIGHT)
    line:EnableMouse(true)
    UI.Background(line, UI.C.bgSidebar)
    UI.AddEdge(line, 0, UI.C.divider)

    local label = UI.Text(line, UI.FONT_FOOTER, UI.C.textMuted)
    label:SetPoint("LEFT", ROW_INSET + 2, 0)
    label:SetText("Waiting to loot")

    line.icon = line:CreateTexture(nil, "ARTWORK")
    line.icon:SetSize(LOOT_ICON, LOOT_ICON)
    line.icon:SetPoint("LEFT", label, "RIGHT", ROW_TEXT_GAP, 0)

    line.more = UI.Text(line, UI.FONT_FOOTER, UI.C.textMuted)
    line.more:SetPoint("RIGHT", -(ROW_INSET + 2), 0)

    line.name = UI.Text(line, UI.FONT_BODY, UI.C.textPrimary)
    line.name:SetPoint("LEFT", line.icon, "RIGHT", ROW_TEXT_GAP, 0)
    line.name:SetPoint("RIGHT", line.more, "LEFT", -ROW_TEXT_GAP, 0)
    line.name:SetJustifyH("LEFT")
    line.name:SetWordWrap(false)
    line.name:SetMaxLines(1)

    line:SetScript("OnEnter", function()
        if line.slot and GameTooltip.SetLootItem then
            GameTooltip:SetOwner(line, "ANCHOR_RIGHT")
            GameTooltip:SetLootItem(line.slot)
            GameTooltip:Show()
        end
    end)
    line:SetScript("OnLeave", function()
        if GameTooltip:GetOwner() == line then
            GameTooltip:Hide()
        end
    end)
    line:Hide()
    return line
end

local function CreateFooter(window)
    local UI = ns.Window.UI
    local bar = CreateFrame("Frame", nil, window)
    bar:SetPoint("BOTTOMLEFT", UI.BORDER, UI.BORDER)
    bar:SetPoint("BOTTOMRIGHT", -UI.BORDER, UI.BORDER)
    bar:SetHeight(UI.FOOTER_HEIGHT)
    UI.Background(bar, UI.C.bgSidebar)
    UI.AddLine(bar, "TOP", UI.C.borderInner)

    summaryText = UI.Text(bar, UI.FONT_FOOTER, UI.C.textMuted)
    summaryText:SetPoint("LEFT", UI.FOOTER_INSET, 0)

    optionsButton = UI.TextButton(bar, "Options", function()
        ns.Window:ShowSection("cheapest")
    end)
    optionsButton:SetPoint("RIGHT", -UI.FOOTER_INSET, 0)

    sellPoor = UI.TextButton(bar, "Sell all Poor", function()
        ns.Cheapest:SellAllPoor()
    end)
    sellPoor:SetPoint("RIGHT", optionsButton, "LEFT", -FOOTER_LINK_GAP, 0)
    sellPoor:Hide()
end

local function Create()
    local UI = ns.Window.UI
    -- Named so that the Escape key can close it through UISpecialFrames.
    local window = CreateFrame("Frame", "NascentCheapestFrame", UIParent)
    window:SetSize(POPUP_WIDTH, 200)
    window:SetFrameStrata("HIGH")
    window:SetToplevel(true)
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:SetMovable(true)
    window:Hide()
    window:SetScale(UI.Clamp(ns.db.profile.scale, UI.SCALE_MIN, UI.SCALE_MAX))
    RestorePosition(window)

    UI.AddEdge(window, 0, UI.C.borderOuter)
    UI.AddEdge(window, 1, UI.C.borderInner)

    CreateTitleBar(window)

    local body = CreateFrame("Frame", nil, window)
    body:SetPoint("TOPLEFT", UI.BORDER, -(UI.BORDER + UI.TITLE_HEIGHT))
    body:SetPoint("BOTTOMRIGHT", -UI.BORDER, UI.BORDER + UI.FOOTER_HEIGHT)
    UI.Background(body, UI.C.bgWindow)

    lootLine = CreateLootLine(body)
    list = CheapestUI.CreateList(body, function() return ns.db.profile.cheapest.rows end, true)

    CreateFooter(window)

    window:SetScript("OnShow", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
        Layout()
    end)
    window:SetScript("OnHide", function(self)
        PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
        self:StopMovingOrSizing()
        ns.Cheapest:ReleaseFromLoot()
    end)

    if UISpecialFrames then
        tinsert(UISpecialFrames, "NascentCheapestFrame")
    end

    ns.Cheapest:Subscribe(Layout)
    UI.OnRelayout(ApplyScale)
    return window
end

function Popup:IsShown()
    return frame ~= nil and frame:IsShown()
end

-- Moves the open pop-up beside the loot window, if that option is on. Runs a
-- frame later, so a loot window that opens with the same event is shown first.
function Popup:PlaceNearLoot()
    if not frame or not ns.db.profile.cheapest.followLoot then return end
    C_Timer.After(0, function()
        if frame:IsShown() and ns.db.profile.cheapest.followLoot and PlaceBesideLoot(frame) then
            besideLoot = true
        end
    end)
end

-- `nearLoot`: opened by looting, so place it beside the loot window.
function Popup:Show(nearLoot)
    if not frame then
        frame = Create()
    elseif besideLoot and not frame:IsShown() then
        -- Last time it sat beside a loot window that has gone; use the saved spot.
        RestorePosition(frame)
        besideLoot = false
    end
    frame:Show()
    if nearLoot then
        self:PlaceNearLoot()
    end
end

function Popup:Hide()
    if frame then
        frame:Hide()
    end
end

function Popup:Toggle()
    if self:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

-- Re-lays out the pop-up after a setting that changes its rows.
function Popup:Refresh()
    Layout()
end
