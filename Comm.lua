local _, ns = ...

-- Version check over the hidden addon-message channel.
--
-- An addon cannot reach the internet, so the only way to learn that a newer
-- release exists is from other players. Every copy announces its version to
-- guild and group; a copy that hears an older version answers with its own.
-- The player is then told that their copy is up to date or out of date.
--
-- Wire format: an AceSerializer-encoded table sent with AceComm.
--   proto   (number) protocol version of the sender
--   version (string) the sender's addon version, "major.minor.patch"
--   kind    (string) message type; only "VERSION" exists in protocol 1
--   sid     (string) random per-session id, used to drop our own echoes
--   test    (true)   set on /nascent test messages; never sent to others
-- `proto` and `version` are the envelope and must keep their meaning in every
-- future protocol version, so an old copy can still learn it is out of date
-- from a message it otherwise cannot understand.

local Comm = {}
ns.Comm = Comm

LibStub("AceComm-3.0"):Embed(Comm)
LibStub("AceSerializer-3.0"):Embed(Comm)

local PREFIX = "Nascent"       -- addon-message prefix, at most 16 characters
local PROTOCOL = 1
local LOGIN_DELAY = 8          -- seconds; wait for the loading screen to clear
local VERDICT_DELAY = 6        -- seconds to wait for answers before reporting
local SEND_THROTTLE = 10       -- seconds between sends on the same channel
local TEST_TIMEOUT = 5         -- seconds to wait for a test message to return
local REMEMBER_FOR = 7 * 24 * 60 * 60 -- seconds a heard version stays remembered

local REPLY_CHANNELS = { GUILD = true, PARTY = true, RAID = true, INSTANCE_CHAT = true }

local sessionId = ("%04x%04x"):format(math.random(0, 65535), math.random(0, 65535))

local mine              -- parsed own version, set in Enable
local newestKnown       -- newest version string heard that is newer than ours
local announced         -- newest version already reported to the player
local verdictShown = false
local channelsAsked = 0 -- channels the last broadcast went out on
local lastSent = {}
local pendingReply = {}
local pendingTest = false
local lastGroupSize = 0

-- "1.4.3" -> { 1, 4, 3 }. Anything that is not a short dotted number is
-- rejected, so a malformed message can never trigger a notice.
local function ParseVersion(text)
    if type(text) ~= "string" or #text > 16 then return nil end
    local a, b, c = text:match("^(%d+)%.(%d+)%.(%d+)$")
    if not a then
        a, b = text:match("^(%d+)%.(%d+)$")
        c = "0"
    end
    if not a then return nil end
    return { tonumber(a), tonumber(b), tonumber(c) }
end

-- Returns 1 if a is newer than b, -1 if older, 0 if equal.
local function Compare(a, b)
    for i = 1, 3 do
        if a[i] ~= b[i] then
            return a[i] > b[i] and 1 or -1
        end
    end
    return 0
end

local function IsNewerThanMine(text)
    local parsed = ParseVersion(text)
    return parsed ~= nil and Compare(parsed, mine) > 0
end

-- Tells the player where they stand. `newest` is a version string or nil.
local function Report(newest, isTest)
    local tag = isTest and "[test] " or ""
    if newest and IsNewerThanMine(newest) then
        ns.Print(("%sYour version %s is out of date. Version %s is available."):format(tag, ns.VERSION, newest))
    elseif isTest or channelsAsked > 0 then
        ns.Print(("%sYour version %s is up to date."):format(tag, ns.VERSION))
    else
        ns.Print(("Your version %s is up to date (you are not in a guild or group, so no other players were asked).")
            :format(ns.VERSION))
    end
end

-- Reports a newer version heard after the verdict was already shown.
local function ReportIfNews()
    if not verdictShown or not newestKnown then return end
    if announced and Compare(ParseVersion(newestKnown), ParseVersion(announced)) <= 0 then return end
    announced = newestKnown
    Report(newestKnown)
end

local function Remember(text)
    if not newestKnown or Compare(ParseVersion(text), ParseVersion(newestKnown)) > 0 then
        newestKnown = text
    end
    local store = ns.db and ns.db.global
    if store then
        store.newestSeenVersion = newestKnown
        store.newestSeenAt = time()
    end
end

local function Send(distribution, target, testVersion)
    if not testVersion then
        local now = GetTime()
        if lastSent[distribution] and now - lastSent[distribution] < SEND_THROTTLE then return false end
        lastSent[distribution] = now
    end
    local payload = Comm:Serialize({
        proto = PROTOCOL,
        kind = "VERSION",
        version = testVersion or ns.VERSION,
        sid = sessionId,
        test = testVersion and true or nil,
    })
    Comm:SendCommMessage(PREFIX, payload, distribution, target)
    return true
end

-- Announces our version on every channel we are in. Returns how many channels
-- we are in, whether or not the throttle let this particular send through.
local function Broadcast()
    local channels = 0
    if IsInGuild() then
        Send("GUILD")
        channels = channels + 1
    end
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        Send("INSTANCE_CHAT")
        channels = channels + 1
    end
    -- LE_PARTY_CATEGORY_HOME may be nil on this client; a nil category means
    -- "any group", which is still correct here.
    if IsInRaid(LE_PARTY_CATEGORY_HOME) then
        Send("RAID")
        channels = channels + 1
    elseif IsInGroup(LE_PARTY_CATEGORY_HOME) then
        Send("PARTY")
        channels = channels + 1
    end
    channelsAsked = channels
    return channels
end

-- Someone on this channel runs an older copy: answer after a short random
-- delay so they learn about our version. The answer is dropped if another
-- player with the same or a newer version speaks first.
local function ScheduleReply(distribution)
    if pendingReply[distribution] then return end
    pendingReply[distribution] = true
    C_Timer.After(1 + math.random() * 4, function()
        if pendingReply[distribution] then
            pendingReply[distribution] = nil
            Send(distribution)
        end
    end)
end

function Comm:OnCommReceived(prefix, text, distribution)
    if prefix ~= PREFIX or not mine then return end

    local ok, message = self:Deserialize(text)
    if not ok or type(message) ~= "table" or type(message.proto) ~= "number" then return end

    local theirs = ParseVersion(message.version)
    if not theirs then return end

    local own = message.sid == sessionId
    if message.test then
        -- Test messages only count when they are our own, sent to ourselves.
        if own and distribution == "WHISPER" then
            pendingTest = false
            Report(message.version, true)
        end
        return
    end
    if own then return end -- our own broadcast echoed back

    -- A newer protocol may carry kinds we do not know; its version still counts.
    if message.proto <= PROTOCOL and message.kind ~= "VERSION" then return end

    local order = Compare(theirs, mine)
    if order < 0 then
        if REPLY_CHANNELS[distribution] then
            ScheduleReply(distribution)
        end
        return
    end

    -- Same or newer version heard on this channel: no answer needed from us.
    pendingReply[distribution] = nil

    if order > 0 then
        Remember(message.version)
        ReportIfNews()
    end
end

local function ShowVerdict()
    verdictShown = true
    announced = newestKnown
    Report(newestKnown)
end

-- Asks other players and reports the result. Used by /nascent version.
function Comm:Check()
    if not mine then
        ns.Print("Version check is unavailable: the version in the TOC file is not in major.minor.patch form.")
        return
    end
    Broadcast()
    C_Timer.After(VERDICT_DELAY, ShowVerdict)
end

-- Forever characters have a first name and a surname, and a whisper must be
-- addressed to both ("First Surname"). UnitName returns the first name only.
local function PlayerFullName()
    local first, surname = UnitFullName("player")
    if surname and surname ~= "" then
        return first .. " " .. surname
    end
    return first
end

-- Sends a test message to ourselves through the real send and receive path,
-- pretending to be `version`. Used by /nascent test.
function Comm:SendTest(version)
    if not mine then return end
    if not ParseVersion(version) then
        ns.Print("Usage: /nascent test <version>, for example /nascent test 9.9.9")
        return
    end
    local target = PlayerFullName()
    if not target then
        ns.Print("[test] Could not read your character's name; try again in a moment.")
        return
    end
    pendingTest = true
    Send("WHISPER", target, version)
    C_Timer.After(TEST_TIMEOUT, function()
        if pendingTest then
            pendingTest = false
            ns.Print(("[test] The test message to %s did not come back."):format(target))
        end
    end)
end

local function LoginCheck()
    -- Recall a newer version heard in an earlier session, while it is recent.
    local store = ns.db and ns.db.global
    if store then
        local heardAt = tonumber(store.newestSeenAt)
        local recent = heardAt and time() - heardAt < REMEMBER_FOR
        if recent and IsNewerThanMine(store.newestSeenVersion) then
            newestKnown = store.newestSeenVersion
        else
            store.newestSeenVersion = nil
            store.newestSeenAt = nil
        end
    end
    Comm:Check()
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function()
    -- GROUP_ROSTER_UPDATE: announce again when someone new joins the group.
    local size = GetNumGroupMembers()
    if size > lastGroupSize and mine then
        Broadcast()
    end
    lastGroupSize = size
end)

function Comm:Enable()
    mine = ParseVersion(ns.VERSION)
    self:RegisterComm(PREFIX)
    lastGroupSize = GetNumGroupMembers()
    events:RegisterEvent("GROUP_ROSTER_UPDATE")
    C_Timer.After(LOGIN_DELAY, LoginCheck)
end
