local _, ns = ...

-- The Cheapest items page (docs/UI-SPEC.md section 8). Window.lua calls
-- CheapestPage:Build with the page the first time the window is created.
-- Settings live in ns.db.profile.cheapest; the logic is in Cheapest.lua.

local CheapestPage = {}
ns.CheapestPage = CheapestPage

local PAGE_ROWS = 10

local GRID_COLUMNS = 3
local GRID_CELL_WIDTH = 110
local GRID_ROW_HEIGHT = 16
local GRID_ROW_GAP = 8
local GRID_LABEL_GAP = 8

local IGNORED_ROW_HEIGHT = 28
local IGNORED_ICON = 18
local IGNORED_INSET = 6
local IGNORED_GAP = 8
local IGNORED_BUTTON_WIDTH = 70
local IGNORED_BUTTON_HEIGHT = 22
local EMPTY_PAD = 6

local POPUP_ROWS_MIN, POPUP_ROWS_MAX = 3, 10
local FREE_SLOTS_MAX = 10

local controls = {}

local function Track(control)
    controls[#controls + 1] = control
    return control
end

local function Changed()
    ns.Cheapest:Invalidate()
end

-- Quality checkboxes in a grid, each followed by the quality's name in its colour.
local function CreateQualityGrid(parent)
    local UI = ns.Window.UI
    local settings = ns.db.profile.cheapest
    local qualities = ns.Cheapest.QUALITIES
    local rowsNeeded = math.ceil(#qualities / GRID_COLUMNS)
    local grid = CreateFrame("Frame", nil, parent)
    grid:SetSize(GRID_COLUMNS * GRID_CELL_WIDTH,
        rowsNeeded * GRID_ROW_HEIGHT + (rowsNeeded - 1) * GRID_ROW_GAP)

    for index, entry in ipairs(qualities) do
        local column = (index - 1) % GRID_COLUMNS
        local line = math.floor((index - 1) / GRID_COLUMNS)
        local box = Track(UI.Checkbox(grid, {
            get = function() return settings.qualities[entry.quality] end,
            set = function(checked)
                settings.qualities[entry.quality] = checked
                Changed()
            end,
        }))
        box:SetPoint("TOPLEFT", column * GRID_CELL_WIDTH, -line * (GRID_ROW_HEIGHT + GRID_ROW_GAP))
        -- The label is part of the click area.
        box:SetHitRectInsets(-4, -(GRID_CELL_WIDTH - GRID_ROW_HEIGHT - GRID_LABEL_GAP), -4, -4)

        local label = UI.Text(grid, UI.FONT_BODY, UI.C.textPrimary)
        label:SetPoint("LEFT", box, "RIGHT", GRID_LABEL_GAP, 0)
        label:SetText(entry.label)
        local colour = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[entry.quality]
        if colour then
            label:SetTextColor(colour.r, colour.g, colour.b)
        end
    end
    return grid
end

-- Ignored items --------------------------------------------------------------------

local function CreateIgnoredRow(list)
    local UI = ns.Window.UI
    local row = CreateFrame("Frame", nil, list)
    row:SetHeight(IGNORED_ROW_HEIGHT)
    row.line = UI.AddLine(row, "BOTTOM", UI.C.divider)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(IGNORED_ICON, IGNORED_ICON)
    row.icon:SetPoint("LEFT", IGNORED_INSET, 0)

    row.remove = UI.Button(row, "Remove", function()
        if row.itemID then ns.Cheapest:Unignore(row.itemID) end
    end)
    row.remove:SetSize(IGNORED_BUTTON_WIDTH, IGNORED_BUTTON_HEIGHT)
    row.remove:SetPoint("RIGHT", -IGNORED_INSET, 0)

    row.name = UI.Text(row, UI.FONT_BODY, UI.C.textPrimary)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", IGNORED_GAP, 0)
    row.name:SetPoint("RIGHT", row.remove, "LEFT", -IGNORED_GAP, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.name:SetMaxLines(1)
    return row
end

local function PaintIgnoredRow(row, itemID)
    local UI = ns.Window.UI
    row.itemID = itemID
    local _, _, _, _, icon = C_Item.GetItemInfoInstant(itemID)
    row.icon:SetTexture(icon)
    local name, _, quality = C_Item.GetItemInfo(itemID)
    if name then
        row.name:SetText(name)
        local colour = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
        if colour then
            row.name:SetTextColor(colour.r, colour.g, colour.b)
        else
            row.name:SetTextColor(UI.C.textPrimary[1], UI.C.textPrimary[2], UI.C.textPrimary[3])
        end
    else
        -- Not cached yet: show the ID until the name loads.
        row.name:SetText("Item " .. itemID)
        row.name:SetTextColor(UI.C.textMuted[1], UI.C.textMuted[2], UI.C.textMuted[3])
        ns.Cheapest:WatchItem(itemID)
    end
end

local function CreateIgnoredList(parent)
    local UI = ns.Window.UI
    local list = CreateFrame("Frame", nil, parent)
    list:SetSize(1, 1)
    local rows = {}

    local empty = UI.Text(list, UI.FONT_BODY, UI.C.textSecondary)
    empty:SetPoint("TOPLEFT", 0, -EMPTY_PAD)
    empty:SetJustifyH("LEFT")
    empty:SetWordWrap(true)
    empty:SetText("Nothing ignored. Click Ignore on a listed item to keep it off the list.")

    function list.Layout(width)
        local ids = ns.Cheapest:GetIgnored()
        for index, itemID in ipairs(ids) do
            local row = rows[index]
            if not row then
                row = CreateIgnoredRow(list)
                rows[index] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -(index - 1) * IGNORED_ROW_HEIGHT)
            row:SetPoint("TOPRIGHT", 0, -(index - 1) * IGNORED_ROW_HEIGHT)
            row.line:SetShown(index < #ids)
            PaintIgnoredRow(row, itemID)
            row:Show()
        end
        for index = #ids + 1, #rows do
            rows[index].itemID = nil
            rows[index]:Hide()
        end
        empty:SetShown(#ids == 0)
        if #ids == 0 then
            empty:SetWidth(width)
            return empty:GetStringHeight() + 2 * EMPTY_PAD
        end
        return #ids * IGNORED_ROW_HEIGHT
    end

    return list
end

-- Page -------------------------------------------------------------------------------

function CheapestPage:Build(page)
    local UI = ns.Window.UI
    local Cheapest = ns.Cheapest
    local settings = ns.db.profile.cheapest

    local bags = page:AddCard("In your bags")
    bags:AddText("The cheapest stacks in your general bags, cheapest first. Hover a row for the item's tooltip.")
    bags:AddCustom(ns.CheapestUI.CreateList(bags.frame, function() return PAGE_ROWS end))
    bags:AddButtons({
        { label = "Open pop-up", onClick = function() ns.CheapestWindow:Show() end },
        { label = "Refresh", onClick = Changed },
        { label = "Sell all Poor", onClick = function() Cheapest:SellAllPoor() end },
    })
    bags:AddText("Shift-click a row to link the item in chat, right-click it to ignore it, and Shift-click "
        .. "Delete to skip the confirmation. Sell all Poor needs an open vendor and skips ignored items. "
        .. "The \"Delete cheapest item\" key binding (Key Bindings, Nascent) deletes the first row.",
        UI.C.textMuted)

    local listed = page:AddCard("What is listed")
    local panel = listed.frame
    listed:AddControl("Qualities", CreateQualityGrid(panel))
    listed:AddControl("Skip soulbound items", Track(UI.Checkbox(panel, {
        get = function() return settings.skipSoulbound end,
        set = function(checked)
            settings.skipSoulbound = checked
            Changed()
        end,
    })))
    listed:AddText("Quest items, keys, ammunition, profession tools and items that cannot be sold are never listed.",
        UI.C.textMuted)

    local popup = page:AddCard("Pop-up")
    panel = popup.frame
    popup:AddControl("Open when your bags are full", Track(UI.Checkbox(panel, {
        get = function() return settings.openWhenFull end,
        set = function(checked) settings.openWhenFull = checked end,
    })))
    popup:AddText("Opens when the game says your inventory is full, for example when loot does not fit.",
        UI.C.textMuted)
    popup:AddControl("Open when looting with this many free slots or fewer", Track(UI.Slider(panel, {
        min = 0, max = FREE_SLOTS_MAX, step = 1,
        format = function(value) return value == 0 and "Off" or tostring(value) end,
        get = function() return settings.openAtFree end,
        commit = function(value) settings.openAtFree = value end,
    })))
    popup:AddText("A pop-up that opened by itself closes when the loot window closes.", UI.C.textMuted)
    popup:AddControl("Place it beside the loot window", Track(UI.Checkbox(panel, {
        get = function() return settings.followLoot end,
        set = function(checked) settings.followLoot = checked end,
    })))
    popup:AddText("When it opens while looting. Dragging the pop-up turns this off and keeps it where you put it.",
        UI.C.textMuted)
    popup:AddControl("Rows in the pop-up", Track(UI.Slider(panel, {
        min = POPUP_ROWS_MIN, max = POPUP_ROWS_MAX, step = 1,
        format = tostring,
        get = function() return settings.rows end,
        commit = function(value)
            settings.rows = value
            Changed()
        end,
    })))
    popup:AddText("Type /nas cheap to open or close the pop-up yourself.", UI.C.textMuted)

    local deleting = page:AddCard("Deleting")
    panel = deleting.frame
    deleting:AddControl("Confirm before deleting", Track(UI.Checkbox(panel, {
        get = function() return settings.confirmDelete end,
        set = function(checked)
            settings.confirmDelete = checked
            Changed()
        end,
    })))
    deleting:AddText("The first click turns Delete into Confirm. Click again within a few seconds to delete.",
        UI.C.textMuted)
    deleting:AddControl("Keep looting after deleting", Track(UI.Checkbox(panel, {
        get = function() return settings.lootAfterDelete end,
        set = function(checked) settings.lootAfterDelete = checked end,
    })))
    deleting:AddText("While a loot window is open, goes on looting whatever now fits: quest items first, "
        .. "then the most valuable.", UI.C.textMuted)
    deleting:AddControl("Use auction prices", Track(UI.Checkbox(panel, {
        get = function() return settings.auctionPrices end,
        set = function(checked)
            settings.auctionPrices = checked
            Changed()
        end,
    })))
    local auctionHint = deleting:AddText("", UI.C.textMuted)

    local ignored = page:AddCard("Ignored items")
    ignored:AddText("Items you ignored are never listed on this character.")
    ignored:AddCustom(CreateIgnoredList(ignored.frame))
    ignored:AddButtons({
        { label = "Clear all", onClick = function() Cheapest:ClearIgnored() end },
    })

    local function Refresh()
        for _, control in ipairs(controls) do
            control.Refresh()
        end
        auctionHint:SetText(Cheapest:HasAuctionSource()
            and "Ranks stacks by Auctionator's price when it knows one, and by vendor price otherwise."
            or "Needs Auctionator, which is not loaded. Vendor prices are used.")
    end

    page.frame:SetScript("OnShow", Refresh)
    Refresh()

    Cheapest:Subscribe(function()
        if page.frame:IsVisible() then
            ns.Window:Relayout()
        end
    end)
end
