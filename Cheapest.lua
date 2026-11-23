local _, ns = ...

-- Cheapest items: finds the least valuable stacks in the general bags so the
-- player can delete, sell or ignore one when the bags are full. This file is
-- the logic and the events; CheapestUI.lua draws the list and the pop-up, and
-- CheapestPage.lua is the page in the main window.
--
-- Settings live in ns.db.profile.cheapest; the ignore list is per character in
-- ns.db.char.cheapestIgnored ({ [itemID] = true }).
--
-- A stack's value is its unit price times its count. The unit price is the
-- vendor price, or the Auctionator price when that option is on and
-- Auctionator knows the item.

local Cheapest = {}
ns.Cheapest = Cheapest

local GetContainerItemInfo = C_Container.GetContainerItemInfo
local GetContainerNumSlots = C_Container.GetContainerNumSlots
local GetContainerNumFreeSlots = C_Container.GetContainerNumFreeSlots
local GetItemInfo = C_Item.GetItemInfo
local GetItemInfoInstant = C_Item.GetItemInfoInstant

Cheapest.QUALITIES = {
    { quality = 0, label = "Poor" },
    { quality = 1, label = "Common" },
    { quality = 2, label = "Uncommon" },
    { quality = 3, label = "Rare" },
    { quality = 4, label = "Epic" },
}

-- Item classes that are never listed (Enum.ItemClass values).
local KEEP_CLASS = {
    [6] = true,   -- projectiles (arrows, bullets)
    [11] = true,  -- quivers and ammo pouches
    [12] = true,  -- quest items
    [13] = true,  -- keys
}
local CLASS_WEAPON = 2
local SUBCLASS_FISHING_POLE = 20

-- Profession tools that have a sell price but are needed to use the profession.
local TOOLS = {
    [2901] = true,  -- Mining Pick
    [5956] = true,  -- Blacksmith Hammer
    [7005] = true,  -- Skinning Knife
    [6219] = true,  -- Arclight Spanner
    [5060] = true,  -- Thieves' Tools
    [10498] = true, -- Gyromatic Micro-Adjustor
    [9149] = true,  -- Philosopher's Stone
    [6217] = true, [6218] = true,   -- Copper Rod, Runed Copper Rod
    [6338] = true, [6339] = true,   -- Silver Rod, Runed Silver Rod
    [11128] = true, [11130] = true, -- Golden Rod, Runed Golden Rod
    [11144] = true, [11145] = true, -- Truesilver Rod, Runed Truesilver Rod
    [16206] = true, [16207] = true, -- Arcanite Rod, Runed Arcanite Rod
}

-- The game's own delete confirmations (shown for better items).
local DELETE_DIALOGS = { "DELETE_ITEM", "DELETE_GOOD_ITEM", "DELETE_QUEST_ITEM", "DELETE_GOOD_QUEST_ITEM" }

local ARM_SECONDS = 4          -- how long a first Delete click waits for the second
local INFO_DELAY = 0.2         -- batches item-info arrivals into one rescan
local SELL_STEP = 0.15         -- seconds between sales in Sell all Poor
local QUALITY_POOR = 0

Cheapest.ARM_SECONDS = ARM_SECONDS

local entries = {}             -- the sorted list, rebuilt by Scan
local skipped = { quality = 0, ignored = 0, soulbound = 0 } -- why stacks were left out, from Scan
local dirty = true
local armedAt                  -- GetTime() of the first Delete click
local selling = false          -- Sell all Poor is running
local waiting = {}             -- itemID -> true while its item info is loading
local watched = {}             -- the same for items shown elsewhere (the ignore list)
local rescanScheduled = false
local listeners = {}
local looting = false          -- a loot window is open (events and the loot frame's OnShow/OnHide)
local merchantOpen = false
local autoOpened = false       -- the pop-up opened by itself, so it closes with the loot window
local continueLoot = false     -- after a delete: keep looting what fits on every bag update
local waitForRoom = false      -- the delete has not freed its slot yet (the game's dialog may be open)
local triedLoot = {}           -- loot slots already taken in this run, so a failed one is not retried
local armed                    -- key of the entry whose Delete was clicked once
local armGeneration = 0

local function Settings()
    return ns.db.profile.cheapest
end

local function LastBag()
    return NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS
end

-- Bags with a family (herb, soul, ammo, ...) only hold their own kind of item,
-- so their free slots do not help and their contents are not listed.
local function IsGeneralBag(bag)
    local _, family = GetContainerNumFreeSlots(bag)
    return family == nil or family == 0
end

function Cheapest:FreeSlots()
    local free = 0
    for bag = BACKPACK_CONTAINER, LastBag() do
        if IsGeneralBag(bag) then
            free = free + (GetContainerNumFreeSlots(bag) or 0)
        end
    end
    return free
end

function Cheapest:IsMerchantOpen()
    return merchantOpen
end

-- Ignore list --------------------------------------------------------------------

local function IgnoreList()
    local list = ns.db.char.cheapestIgnored
    if type(list) ~= "table" then
        list = {}
        ns.db.char.cheapestIgnored = list
    end
    return list
end

function Cheapest:IsIgnored(itemID)
    return IgnoreList()[itemID] == true
end

-- The ignored item IDs, sorted.
function Cheapest:GetIgnored()
    local ids = {}
    for itemID, value in pairs(IgnoreList()) do
        if type(itemID) == "number" and value == true then
            ids[#ids + 1] = itemID
        end
    end
    table.sort(ids)
    return ids
end

-- Asks the game for an item's info and notifies the listeners when it arrives.
function Cheapest:WatchItem(itemID)
    if watched[itemID] then return end
    watched[itemID] = true
    if C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemID)
    end
end

-- Change notification ----------------------------------------------------------------

-- `listener()` runs whenever the list may have changed. Listeners that are not
-- visible should do nothing; GetEntries rescans when it is next called.
function Cheapest:Subscribe(listener)
    listeners[#listeners + 1] = listener
end

function Cheapest:Invalidate()
    dirty = true
    for _, listener in ipairs(listeners) do
        listener()
    end
end

local function ScheduleRescan()
    if rescanScheduled then return end
    rescanScheduled = true
    C_Timer.After(INFO_DELAY, function()
        rescanScheduled = false
        Cheapest:Invalidate()
    end)
end

-- Scanning -----------------------------------------------------------------------------

local function AuctionPrice(itemID)
    if not Settings().auctionPrices then return nil end
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not (api and api.GetAuctionPriceByItemID) then return nil end
    local ok, price = pcall(api.GetAuctionPriceByItemID, ns.NAME, itemID)
    if ok and type(price) == "number" and price > 0 then
        return price
    end
    return nil
end

function Cheapest:HasAuctionSource()
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    return api ~= nil and api.GetAuctionPriceByItemID ~= nil
end

local function ReadSlot(bag, slot)
    local info = GetContainerItemInfo(bag, slot)
    if type(info) ~= "table" or type(info.itemID) ~= "number" or info.isLocked then
        return nil
    end
    local itemID = info.itemID
    if TOOLS[itemID] then return nil end

    local name, _, itemQuality, _, _, _, _, _, _, _, sellPrice = GetItemInfo(info.hyperlink or itemID)
    if not name then
        -- Not cached yet; GET_ITEM_INFO_RECEIVED brings it.
        waiting[itemID] = true
        if C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(itemID)
        end
        return nil
    end

    -- Never listed, and not counted as left out: items that cannot be sold
    -- (hearthstone, quest items, ...), and the kept classes.
    if info.hasNoValue or type(sellPrice) ~= "number" or sellPrice <= 0 then return nil end
    local _, _, _, _, _, classID, subclassID = GetItemInfoInstant(itemID)
    if KEEP_CLASS[classID] then return nil end
    if classID == CLASS_WEAPON and subclassID == SUBCLASS_FISHING_POLE then return nil end

    -- Left out by the player's choices; counted for the empty-list message.
    if Cheapest:IsIgnored(itemID) then
        skipped.ignored = skipped.ignored + 1
        return nil
    end
    if Settings().skipSoulbound and info.isBound then
        skipped.soulbound = skipped.soulbound + 1
        return nil
    end
    local quality = type(info.quality) == "number" and info.quality or itemQuality
    if type(quality) ~= "number" or not Settings().qualities[quality] then
        skipped.quality = skipped.quality + 1
        return nil
    end

    local count = type(info.stackCount) == "number" and info.stackCount or 1
    local auction = AuctionPrice(itemID)
    return {
        bag = bag,
        slot = slot,
        itemID = itemID,
        link = info.hyperlink,
        name = name,
        icon = info.iconFileID,
        quality = quality,
        count = count,
        unitVendor = sellPrice,
        vendorValue = sellPrice * count,
        auctionValue = auction and auction * count or nil,
        value = (auction or sellPrice) * count,
    }
end

local function Cheaper(a, b)
    if a.value ~= b.value then return a.value < b.value end
    if a.itemID ~= b.itemID then return a.itemID < b.itemID end
    if a.bag ~= b.bag then return a.bag < b.bag end
    return a.slot < b.slot
end

local function Scan()
    wipe(entries)
    wipe(waiting)
    skipped.quality, skipped.ignored, skipped.soulbound = 0, 0, 0
    for bag = BACKPACK_CONTAINER, LastBag() do
        if IsGeneralBag(bag) then
            for slot = 1, GetContainerNumSlots(bag) or 0 do
                local entry = ReadSlot(bag, slot)
                if entry then
                    entries[#entries + 1] = entry
                end
            end
        end
    end
    table.sort(entries, Cheaper)
    dirty = false
end

-- How many sellable stacks the last scan left out, by reason:
-- { quality = n, ignored = n, soulbound = n }. Do not change the returned table.
function Cheapest:GetSkipped()
    if dirty then
        Scan()
    end
    return skipped
end

-- The listed stacks, cheapest first. Do not change the returned table.
function Cheapest:GetEntries()
    if dirty then
        Scan()
    end
    return entries
end

-- Loot ----------------------------------------------------------------------------------

-- Loot slot type of an item. Plumber and DeleteCheapestItem compare with the
-- number; LOOT_SLOT_ITEM may be nil in clients that moved it to an Enum.
local SLOT_TYPE_ITEM = 1

local function Trace(text)
    if ns.debug then
        ns.Print("|cff888888[cheap]|r " .. text)
    end
end

-- On Forever, loot can be shown without LOOT_OPENED firing (noted by
-- NaowhForever), and replacement loot windows keep the Blizzard frame hidden,
-- so any of the three signs counts.
local function LootOpen()
    return looting or (LootFrame ~= nil and LootFrame:IsShown()) or (GetNumLootItems() or 0) > 0
end

local function StopLoot()
    continueLoot = false
    waitForRoom = false
    wipe(triedLoot)
end

function Cheapest:IsLooting()
    return LootOpen()
end

-- The visible loot window to place the pop-up beside: Plumber's replacement
-- (PlumberLootWindow) or the Blizzard frame. Nil when neither is shown.
function Cheapest:LootWindowFrame()
    local plumber = _G.PlumberLootWindow
    if type(plumber) == "table" and plumber.IsShown and plumber:IsShown() then
        return plumber
    end
    if LootFrame and LootFrame:IsShown() then
        return LootFrame
    end
    return nil
end

-- The items still in the loot window, most wanted first (quest items, then
-- value). Each is { slot, link, name, icon, quality, quantity, value, quest };
-- value is nil while the item's price is not cached.
function Cheapest:GetPendingLoot()
    local items = {}
    if not LootOpen() then return items end
    for slot = 1, GetNumLootItems() or 0 do
        if LootSlotHasItem(slot) and GetLootSlotType(slot) == SLOT_TYPE_ITEM then
            local texture, name, quantity, _, quality, _, isQuest, questID = GetLootSlotInfo(slot)
            local link = GetLootSlotLink(slot)
            if texture then
                quantity = type(quantity) == "number" and quantity or 1
                local itemID = link and GetItemInfoInstant(link)
                local sellPrice = link and select(11, GetItemInfo(link))
                local unit = type(itemID) == "number" and AuctionPrice(itemID) or nil
                if not unit and type(sellPrice) == "number" then
                    unit = sellPrice
                end
                items[#items + 1] = {
                    slot = slot,
                    link = link,
                    name = name,
                    icon = texture,
                    quality = quality,
                    quantity = quantity,
                    value = unit and unit * quantity or nil,
                    quest = (isQuest or questID) and true or false,
                }
            end
        end
    end
    table.sort(items, function(a, b)
        if a.quest ~= b.quest then return a.quest end
        if (a.value or -1) ~= (b.value or -1) then return (a.value or -1) > (b.value or -1) end
        return a.slot < b.slot
    end)
    return items
end

-- Room left in this item's unfilled stacks in the general bags.
local function StackRoom(itemID, maxStack)
    if type(maxStack) ~= "number" or maxStack <= 1 then return 0 end
    local room = 0
    for bag = BACKPACK_CONTAINER, LastBag() do
        if IsGeneralBag(bag) then
            for slot = 1, GetContainerNumSlots(bag) or 0 do
                local info = GetContainerItemInfo(bag, slot)
                if type(info) == "table" and info.itemID == itemID then
                    local count = type(info.stackCount) == "number" and info.stackCount or 1
                    if count < maxStack then
                        room = room + maxStack - count
                    end
                end
            end
        end
    end
    return room
end

-- The next loot slot to take: of the items that fit (a free slot, or room on an
-- existing stack), a quest item first, otherwise the highest vendor value.
-- Also returns whether taking it uses up a free slot.
local function NextLootSlot(free)
    local best, bestValue, bestUsesSlot
    for slot = 1, GetNumLootItems() or 0 do
        if not triedLoot[slot] and LootSlotHasItem(slot) and GetLootSlotType(slot) == SLOT_TYPE_ITEM then
            local texture, _, quantity, _, _, locked, isQuest, questID = GetLootSlotInfo(slot)
            local link = GetLootSlotLink(slot)
            if texture and link and not locked then
                quantity = type(quantity) == "number" and quantity or 1
                local itemID = GetItemInfoInstant(link)
                local _, _, _, _, _, _, _, maxStack, _, _, sellPrice = GetItemInfo(link)
                local stacks = type(itemID) == "number" and StackRoom(itemID, maxStack) >= quantity
                if stacks or free > 0 then
                    local value
                    if isQuest or questID then
                        value = math.huge
                    else
                        value = (type(sellPrice) == "number" and sellPrice or 0) * quantity
                    end
                    if not bestValue or value > bestValue then
                        best, bestValue, bestUsesSlot = slot, value, not stacks
                    end
                end
            end
        end
    end
    return best, bestUsesSlot
end

-- Loots everything that fits in `free` slots plus room on existing stacks.
-- The server handles requests in order, so right after a delete the freed
-- slot can be counted before the bags show it. Returns how many were looted.
local function LootWhatFits(free)
    local taken = 0
    while true do
        local slot, usesSlot = NextLootSlot(free)
        if not slot then break end
        triedLoot[slot] = true
        Trace("loot slot " .. slot .. (usesSlot and " (free slot)" or " (onto a stack)"))
        LootSlot(slot)
        taken = taken + 1
        if usesSlot then
            free = free - 1
        end
    end
    return taken
end

-- After a delete that waits on the game's own dialog: runs on every bag update
-- until the slot is free, then loots once. Stops when the loot window closes.
local function ContinueLoot()
    if not LootOpen() then
        Trace("loot window closed; stop")
        StopLoot()
        return
    end
    local free = Cheapest:FreeSlots()
    if waitForRoom and free < 1 then
        Trace("waiting for the delete to free a slot")
        return
    end
    Trace("bags have " .. free .. " free; looting")
    LootWhatFits(free)
    StopLoot()
end

-- Actions -------------------------------------------------------------------------------

local function EntryKey(entry)
    return entry.bag .. ":" .. entry.slot .. ":" .. entry.itemID .. ":" .. entry.count
end

-- True when the slot still holds the stack the list showed.
local function StillThere(entry)
    local info = GetContainerItemInfo(entry.bag, entry.slot)
    return type(info) == "table" and info.itemID == entry.itemID and not info.isLocked
        and (info.stackCount or 1) == entry.count
end

local function DeleteDialogShown()
    for _, name in ipairs(DELETE_DIALOGS) do
        if StaticPopup_FindVisible(name) then
            return true
        end
    end
    return false
end

local function Describe(entry)
    local text = entry.link or entry.name
    if entry.count > 1 then
        text = text .. " x" .. entry.count
    end
    return text
end

function Cheapest:FormatMoney(copper)
    return C_CurrencyInfo.GetCoinTextureString(math.floor(copper))
end

-- Checks shared by Delete and Sell. Prints why the action cannot run.
local function CanAct(entry)
    if InCombatLockdown() then
        ns.Print("Leave combat first.")
        return false
    end
    if GetCursorInfo() then
        ns.Print("Put down what you are holding first.")
        return false
    end
    if not StillThere(entry) then
        ns.Print("That item moved in your bags. The list has been refreshed.")
        Cheapest:Invalidate()
        return false
    end
    return true
end

function Cheapest:IsArmed(entry)
    return armed ~= nil and armed == EntryKey(entry)
end

-- Seconds left before an armed Delete goes back to normal; 0 when none is armed.
function Cheapest:ArmedRemaining()
    if not (armed and armedAt) then return 0 end
    return math.max(0, ARM_SECONDS - (GetTime() - armedAt))
end

local function Disarm()
    if armed then
        armed = nil
        Cheapest:Invalidate()
    end
end

-- Deletes the stack. With "Confirm before deleting" on, the first click only
-- arms the button and a second click within a few seconds deletes;
-- `skipConfirm` (Shift-click) deletes at once.
function Cheapest:Delete(entry, skipConfirm)
    if not CanAct(entry) then
        Disarm()
        return
    end
    if Settings().confirmDelete and not skipConfirm and not self:IsArmed(entry) then
        armed = EntryKey(entry)
        armedAt = GetTime()
        armGeneration = armGeneration + 1
        local generation = armGeneration
        C_Timer.After(ARM_SECONDS, function()
            if generation == armGeneration then Disarm() end
        end)
        self:Invalidate()
        return
    end
    armed = nil

    C_Container.PickupContainerItem(entry.bag, entry.slot)
    local kind, cursorItemID = GetCursorInfo()
    if kind ~= "item" or cursorItemID ~= entry.itemID then
        ClearCursor()
        ns.Print("That item could not be picked up. The list has been refreshed.")
        self:Invalidate()
        return
    end

    DeleteCursorItem()
    StopLoot()
    local loot = Settings().lootAfterDelete and LootOpen()
    Trace("deleted; loot window " .. (LootOpen() and "open" or "closed")
        .. ", " .. (GetNumLootItems() or 0) .. " loot slots, keep looting " .. tostring(Settings().lootAfterDelete))
    if DeleteDialogShown() then
        -- Better items need the game's own confirmation. Cancelling it puts the
        -- item back; confirming frees the slot, and the bag update loots.
        ns.Print("Confirm the delete in the game's dialog.")
        if loot then
            continueLoot = true
            waitForRoom = true
        end
    elseif GetCursorInfo() then
        ClearCursor()
        ns.Print("The game did not delete that item; it is back in your bags.")
    else
        ns.Print("Deleted " .. Describe(entry) .. " (" .. self:FormatMoney(entry.vendorValue) .. ").")
        if loot then
            -- The server handles the delete before these loot requests, so the
            -- freed slot counts already.
            LootWhatFits(math.max(1, self:FreeSlots()))
        end
    end
    self:Invalidate()
end

function Cheapest:Sell(entry)
    if not merchantOpen then
        ns.Print("Open a vendor to sell.")
        return
    end
    if not CanAct(entry) then return end
    C_Container.UseContainerItem(entry.bag, entry.slot)
    ns.Print("Sold " .. Describe(entry) .. " (" .. self:FormatMoney(entry.vendorValue) .. ").")
    Disarm()
end

-- Poor-quality stacks that Sell all Poor would sell: sellable, not locked and
-- not ignored. Each is { bag, slot, itemID, count, value }.
local function PoorStacks()
    local stacks = {}
    for bag = BACKPACK_CONTAINER, LastBag() do
        for slot = 1, GetContainerNumSlots(bag) or 0 do
            local info = GetContainerItemInfo(bag, slot)
            if type(info) == "table" and type(info.itemID) == "number" and not info.isLocked
                and not info.hasNoValue and not Cheapest:IsIgnored(info.itemID) then
                local _, _, itemQuality, _, _, _, _, _, _, _, sellPrice = GetItemInfo(info.hyperlink or info.itemID)
                local quality = type(info.quality) == "number" and info.quality or itemQuality
                if quality == QUALITY_POOR and type(sellPrice) == "number" and sellPrice > 0 then
                    local count = type(info.stackCount) == "number" and info.stackCount or 1
                    stacks[#stacks + 1] = {
                        bag = bag, slot = slot, itemID = info.itemID, count = count, value = sellPrice * count,
                    }
                end
            end
        end
    end
    return stacks
end

-- How many Poor stacks Sell all Poor would sell, and what they are worth.
function Cheapest:PoorSummary()
    local stacks = PoorStacks()
    local total = 0
    for _, stack in ipairs(stacks) do
        total = total + stack.value
    end
    return #stacks, total
end

function Cheapest:IsSelling()
    return selling
end

-- Sells every Poor stack that is not ignored, one every SELL_STEP seconds so
-- the vendor keeps up. Stops if the vendor closes or combat starts.
function Cheapest:SellAllPoor()
    if not merchantOpen then
        ns.Print("Open a vendor to sell.")
        return
    end
    if selling then return end
    local stacks = PoorStacks()
    if #stacks == 0 then
        ns.Print("You have no Poor items to sell.")
        return
    end
    selling = true
    self:Invalidate()
    local sold, total, index = 0, 0, 0
    local function Finish(reason)
        selling = false
        if sold > 0 then
            ns.Print("Sold " .. sold .. (sold == 1 and " Poor stack" or " Poor stacks")
                .. " for " .. self:FormatMoney(total) .. "." .. (reason or ""))
        elseif reason then
            ns.Print(reason)
        end
        self:Invalidate()
    end
    local function Step()
        if not merchantOpen then return Finish(" The vendor closed before the rest were sold.") end
        if InCombatLockdown() then return Finish(" Stopped for combat.") end
        index = index + 1
        local stack = stacks[index]
        if not stack then return Finish() end
        local info = GetContainerItemInfo(stack.bag, stack.slot)
        if type(info) == "table" and info.itemID == stack.itemID and not info.isLocked then
            C_Container.UseContainerItem(stack.bag, stack.slot)
            sold = sold + 1
            total = total + stack.value
        end
        C_Timer.After(SELL_STEP, Step)
    end
    Step()
end

-- The "Delete cheapest item" keybinding: Delete on the first listed stack,
-- with the same confirmation as the button.
function Cheapest:DeleteCheapest()
    local first = self:GetEntries()[1]
    if not first then
        ns.Print("Nothing to delete: no listed item in your bags.")
        return
    end
    local wasArmed = self:IsArmed(first)
    self:Delete(first)
    if not wasArmed and self:IsArmed(first) then
        ns.Print("Press again within " .. ARM_SECONDS .. " seconds to delete " .. Describe(first) .. ".")
    end
end

function Cheapest:Ignore(entry)
    IgnoreList()[entry.itemID] = true
    ns.Print((entry.link or entry.name) .. " will not be listed again. Undo it on the Cheapest items page.")
    armed = nil
    self:Invalidate()
end

function Cheapest:Unignore(itemID)
    IgnoreList()[itemID] = nil
    self:Invalidate()
end

function Cheapest:ClearIgnored()
    wipe(IgnoreList())
    self:Invalidate()
end

-- Events --------------------------------------------------------------------------------

local function IsBagsFullMessage(message)
    return message ~= nil and (message == ERR_INV_FULL or message == ERR_BAG_FULL)
end

-- Opens the pop-up by itself. It then closes with the loot window, also when
-- the full-bag error came before the loot window showed.
local function OpenAutomatically()
    if ns.CheapestWindow:IsShown() then return end
    ns.CheapestWindow:Show(true)
    autoOpened = true
end

local function LootShown(source)
    if looting then return end
    Trace("loot window open (" .. tostring(source) .. "), " .. (GetNumLootItems() or 0) .. " loot slots")
    looting = true
    StopLoot()
    local threshold = Settings().openAtFree
    if type(threshold) == "number" and threshold > 0 and Cheapest:FreeSlots() <= threshold then
        OpenAutomatically()
    elseif autoOpened and ns.CheapestWindow:IsShown() then
        -- The full-bag error came first; move beside the loot window now.
        ns.CheapestWindow:PlaceNearLoot()
    end
    Cheapest:Invalidate()
end

local function LootHidden(source)
    Trace("loot window closed (" .. tostring(source) .. ")")
    looting = false
    StopLoot()
    if autoOpened then
        autoOpened = false
        ns.CheapestWindow:Hide()
    end
    Cheapest:Invalidate()
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "BAG_UPDATE_DELAYED" then
        if continueLoot then
            ContinueLoot()
        end
        Cheapest:Invalidate()
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if waiting[arg1] or watched[arg1] then
            watched[arg1] = nil
            ScheduleRescan()
        end
    elseif event == "UI_ERROR_MESSAGE" then
        -- arg1 is the message type and arg2 the text; check both, as the
        -- argument order has differed between clients.
        if Settings().openWhenFull and (IsBagsFullMessage(arg2) or IsBagsFullMessage(arg1)) then
            OpenAutomatically()
        end
    elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
        LootShown(event)
    elseif event == "LOOT_CLOSED" then
        LootHidden(event)
    elseif event == "LOOT_SLOT_CLEARED" then
        -- The waiting-loot line and the "worth more than the loot" tags change.
        Cheapest:Invalidate()
    elseif event == "MERCHANT_SHOW" then
        merchantOpen = true
        Cheapest:Invalidate()
    elseif event == "MERCHANT_CLOSED" then
        merchantOpen = false
        Cheapest:Invalidate()
    end
end)

-- The pop-up was closed, so the next loot window no longer closes it.
function Cheapest:ReleaseFromLoot()
    autoOpened = false
end

-- Called by Core.lua at PLAYER_LOGIN.
function Cheapest:Enable()
    -- The loot frame covers a loot window that fired no event; the events cover
    -- loot windows replaced by other addons. Both hooks are unguarded in
    -- NaowhForever (DestroyCheapestPopup.lua). A replacement may hide the
    -- frame while loot is still open, so OnHide counts only with no loot left.
    if LootFrame and LootFrame.HookScript then
        LootFrame:HookScript("OnShow", function() LootShown("LootFrame") end)
        LootFrame:HookScript("OnHide", function()
            if (GetNumLootItems() or 0) == 0 then
                LootHidden("LootFrame")
            end
        end)
    end
    events:RegisterEvent("BAG_UPDATE_DELAYED")
    events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    events:RegisterEvent("UI_ERROR_MESSAGE")
    events:RegisterEvent("LOOT_READY")
    events:RegisterEvent("LOOT_OPENED")
    events:RegisterEvent("LOOT_CLOSED")
    events:RegisterEvent("LOOT_SLOT_CLEARED") -- unguarded in NaowhForever (DestroyCheapestPopup.lua)
    events:RegisterEvent("MERCHANT_SHOW")
    events:RegisterEvent("MERCHANT_CLOSED")
end
