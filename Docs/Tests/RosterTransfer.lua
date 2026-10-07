-- Real storage, guild permissions, export/import, comms dispatch and paced transfers.
local now, packets, timers, clients, prompts = 50000, {}, {}, {}, {}
local inGroup, inRaid, instance = true, false, false
function GetTime() return now end
function GetServerTime() return math.floor(now) end
function time() return math.floor(now) end
function GetRealmName() return "Sargeras" end
function wipe(t) for key in pairs(t) do t[key] = nil end return t end
LE_PARTY_CATEGORY_HOME, LE_PARTY_CATEGORY_INSTANCE = 1, 2
function IsInGroup(category) return category == 2 and instance or (category ~= 2 and inGroup) end
function IsInRaid() return inRaid end
function GetNumGuildMembers() error("Transfers must not scan the guild roster") end
function GuildRoster() error("Transfers must not refresh the guild roster") end
StaticPopupDialogs, ACCEPT = {}, "Accept"
local popupAvailable = true
function StaticPopup_Show(_, sender, summary, data)
    if not popupAvailable then return nil end
    local popup = { sender = sender, summary = summary, data = data, strata = "DIALOG", level = 100 }
    function popup:GetFrameStrata() return self.strata end
    function popup:SetFrameStrata(strata) self.strata = strata end
    function popup:GetFrameLevel() return self.level end
    function popup:SetFrameLevel(level) self.level = level end
    function popup:Raise() self.raised = true end
    function popup:HookScript(_, callback) self.onHide = callback end
    prompts[#prompts + 1] = popup
    return popup
end
C_Timer = {
    After = function(delay, callback) timers[#timers + 1] = { at = now + delay, callback = callback } end,
    NewTicker = function(interval, callback)
        local timer = { at = now + interval, interval = interval, callback = callback,
            Cancel = function(self) self.cancelled = true end }
        timers[#timers + 1] = timer
        return timer
    end,
}
local function eq(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function newClient(name, rank, key)
    local LV = { modules = {}, prints = {}, name = "LootViewer" }
    function LV:Print(message) self.prints[#self.prints + 1] = message end
    function LV:RegisterEvent() end
    for _, file in ipairs({ "Constants", "Util", "Store", "Guild", "Comms", "RosterSync", "RosterTransfer" }) do
        assert(loadfile("Core/" .. file .. ".lua"))("LootViewer", LV)
    end
    LootViewerDB = {}
    LV.Store:Initialize()
    function LV.Util:PlayerFullName() return name end
    local info = { key = key or "test-guild", name = "Test Guild", realm = "Sargeras", rankIndex = rank }
    LV.info = info
    function LV.Guild:ActualInfo() return info end
    LV.Guild.CurrentInfo = LV.Guild.ActualInfo
    function LV.Guild:LoadedGuildRosterMember(fullName)
        local client = clients[self:NormalizeMemberName(fullName)]
        return client and { rankIndex = client.info.rankIndex } or nil
    end
    local record = LV.Store:GuildRecord(info.key)
    record.cfg.authority = "trusted"
    LV.UI = { Refresh = function() end }
    function LV.Comms:SendMessage(kind, payload, channel, target)
        local parts = { kind }
        for _, value in ipairs(payload) do parts[#parts + 1] = tostring(value) end
        local message = table.concat(parts, "\031")
        assert(#message <= 255, "Addon message exceeds 255 bytes")
        packets[#packets + 1] = { sender = name, target = target, channel = channel, message = message, parts = parts }
        return true
    end
    clients[name] = LV
    return LV, record, info
end
local function advance(seconds, filter)
    local deadline = now + seconds
    while now < deadline do
        now = now + 0.05
        for index = #timers, 1, -1 do
            local timer = timers[index]
            if timer.cancelled then table.remove(timers, index)
            elseif timer.at <= now then
                if timer.interval then timer.at = now + timer.interval else table.remove(timers, index) end
                timer.callback()
            end
        end
        local pending = packets
        packets = {}
        for _, packet in ipairs(pending) do
            if not filter or filter(packet) then
                for name, client in pairs(clients) do
                    if not packet.target or name:lower() == packet.target:lower() then
                        client.Comms:HandleMessage("LootViewer", packet.message, packet.channel, packet.sender)
                    end
                end
            end
        end
    end
end
local function set(client, player, kind, primary, secondary)
    local id = client.Store:NameID("test-guild", player)
    return client.Store:SetTeamRosterPlayer("test-guild", "main", id, kind, primary, secondary)
end
local sender, sr = newClient("Officer-Sargeras", 1)
local receiver, rr, receiverInfo = newClient("Meemage-Sargeras", 2)
local other, otherRecord = newClient("Other-Sargeras", 2)
local member, mr = newClient("Member-Sargeras", 8)
local foreign = newClient("Foreign-Sargeras", 2, "other-guild")
set(sender, "M\195\169\195\169mage-Sargeras", "raider", "ranged", "healer")
set(sender, "Tank-Sargeras", "trial", "tank", "melee")
set(sender, "Social-Sargeras", "social", nil, nil)
set(sender, "Helper-Sargeras", "helper", "healer", nil)
set(receiver, "Removed-Sargeras", "raider", "melee", nil)
local exported, parsed = sender.RosterTransfer:Export("test-guild", "main")
assert(exported, "Export succeeds")
eq(#parsed.rows, 4, "Full roster exported")
assert(receiver.RosterTransfer:Decode("\n " .. exported:sub(1, 24) .. "\n" .. exported:sub(25) .. " "), "Wrapped copy/paste supported")
assert(not receiver.RosterTransfer:Decode(exported:sub(1, -3)), "Truncated string rejected")
assert(not receiver.RosterTransfer:Decode(exported:gsub("LVR1", "LVR2")), "Future format rejected")
assert(not member.RosterTransfer:Export("test-guild", "main"), "Read-only export denied")
assert(not member.RosterTransfer:Import("test-guild", exported), "Read-only import denied")
assert(not foreign.RosterTransfer:Import("other-guild", exported), "Wrong guild import denied")
local corrupt = exported:sub(1, -2) .. (exported:sub(-1) == "0" and "1" or "0")
assert(not receiver.RosterTransfer:Import("test-guild", corrupt), "Bad checksum rejected")
assert(next(rr.cfg.teams[1].ro), "Invalid import preserves old roster")
local imported, count = receiver.RosterTransfer:Import("test-guild", exported)
eq(count, 4, "Four assignments imported")
eq(rr.cfg.teams[1].ro[receiver.Store:NameID("test-guild", "Removed-Sargeras")], nil, "Import removes stale player")
eq(rr.cfg.teams[1].ro[receiver.Store:NameID("test-guild", "Tank-Sargeras")].s, "melee", "Secondary role imported")
print("PASS: roster export/import handles Unicode, empty roles, permissions, guild boundaries and corruption")

sr.cfg.teams[1].name = "New Team"
local newExport = sender.RosterTransfer:Export("test-guild", "main")
local mainRoster = rr.cfg.teams[1].ro
imported = receiver.RosterTransfer:Import("test-guild", newExport)
eq(imported.name, "New Team", "Unknown team created")
eq(rr.cfg.teams[1].ro, mainRoster, "Other team untouched")
imported.schedules = { { w = 3, h = 20, m = 0, d = 180 } }
local schedules = imported.schedules
assert(receiver.RosterTransfer:Import("test-guild", newExport))
eq(imported.schedules, schedules, "Existing schedules preserved")
sr.cfg.teams[1].name = "Main"
local ok = sender.RosterTransfer:Send("test-guild", "main", "meemage")
assert(ok, "Unqualified target accepted")
eq(packets[1].target, "meemage-Sargeras", "Target gets local realm")
local loadedMember = receiver.Guild.LoadedGuildRosterMember
function receiver.Guild:LoadedGuildRosterMember() return nil end
local clubRank = receiver.Guild.ClubMemberRank
function receiver.Guild:ClubMemberRank() return nil, "member ID unavailable" end
receiver.UI.frame = { GetFrameLevel = function() return 100 end }
advance(0.2)
eq(#prompts, 1, "Whisper offer shows confirmation even when sender rank is not cached")
eq(prompts[1].strata, "FULLSCREEN_DIALOG", "Confirmation appears above the addon window")
assert(prompts[1].level > receiver.UI.frame:GetFrameLevel() and prompts[1].raised, "Confirmation raised above addon dialogs")
prompts[1].onHide(prompts[1])
eq(prompts[1].strata, "DIALOG", "Shared popup strata restored on hide")
eq(prompts[1].level, 100, "Shared popup level restored on hide")
receiver.Guild.LoadedGuildRosterMember, receiver.Guild.ClubMemberRank = loadedMember, clubRank
eq(receiver.RosterTransfer.inbound.accepted, nil, "Offer does not accept itself")
receiver.RosterTransfer:DeclineOffer(receiver.RosterTransfer.inbound)
advance(0.2)
eq(sender.RosterTransfer.outbound, nil, "Decline frees sender")
assert(sender.RosterTransfer:Send("test-guild", "main", "meemage-sargeras"), "Full target accepted")
advance(0.2)
receiver.RosterTransfer:AcceptOffer(receiver.RosterTransfer.inbound)
local droppedChunk, droppedFinalAck = false, false
advance(12, function(packet)
    if packet.parts[1] == "LVC" and packet.parts[3] == "2" and not droppedChunk then
        droppedChunk = true; return false
    end
    if packet.parts[1] == "LVK" and receiver.RosterTransfer.inbound and receiver.RosterTransfer.inbound.complete and not droppedFinalAck then
        droppedFinalAck = true; return false
    end
    return true
end)
assert(droppedChunk and droppedFinalAck, "Both chunk and final ACK drops exercised")
eq(sender.RosterTransfer.outbound, nil, "Reliable whisper transfer completes")
assert(rr.cfg.teams[1].ro[receiver.Store:NameID("test-guild", "Helper-Sargeras")], "Received complete roster")
print("PASS: explicit decline, short/full names, dropped chunks and lost final acknowledgments")

advance(11)
popupAvailable = false
assert(sender.RosterTransfer:Send("test-guild", "main", "Meemage-Sargeras"))
advance(0.2)
eq(receiver.RosterTransfer.inbound, nil, "Missing popup slot does not leave a phantom offer")
eq(sender.RosterTransfer.outbound, nil, "Missing popup slot reports rejection to sender")
assert(sender.prints[#sender.prints]:find("confirmation slot", 1, true), "Sender sees why the popup could not open")
popupAvailable = true
print("PASS: popup stays above /lv and unavailable dialog slots report a rejection")

assert(sender.RosterTransfer:Send("test-guild", "main", "group"))
eq(packets[1].channel, "PARTY", "Group selects party channel")
advance(0.2)
assert(receiver.RosterTransfer.inbound and other.RosterTransfer.inbound, "Each permitted group recipient gets an offer")
assert(member.RosterTransfer.inbound, "Read-only guild member receives authorized transfer confirmation")
eq(foreign.RosterTransfer.inbound, nil, "Foreign guild recipient ignored")
receiver.RosterTransfer:AcceptOffer(receiver.RosterTransfer.inbound)
other.RosterTransfer:AcceptOffer(other.RosterTransfer.inbound)
member.RosterTransfer:AcceptOffer(member.RosterTransfer.inbound)
advance(5)
assert(receiver.RosterTransfer.inbound.complete and other.RosterTransfer.inbound.complete, "Group recipients transfer independently")
assert(member.RosterTransfer.inbound.complete and next(mr.cfg.teams[1].ro), "Read-only member accepts authorized publisher")
eq(mr.cfg.teams[1].rt, sr.cfg.teams[1].rt or 0, "Incoming revision preserved")
assert(next(otherRecord.cfg.teams[1].ro), "Second group recipient imported")
advance(56)
eq(sender.RosterTransfer.outbound, nil, "Broadcast offer expires after completed peers")
inRaid = true
assert(sender.RosterTransfer:Send("test-guild", "main", "raid"))
eq(packets[1].channel, "RAID", "Raid channel selected")
advance(61)
inRaid, instance = false, true
assert(sender.RosterTransfer:Send("test-guild", "main", "group"))
eq(packets[1].channel, "INSTANCE_CHAT", "Instance group channel selected")
advance(61)
instance, inGroup = false, false
assert(not sender.RosterTransfer:Send("test-guild", "main", "group"), "No group rejected")
assert(not sender.RosterTransfer:Send("test-guild", "main", "raid"), "No raid rejected")
assert(not sender.RosterTransfer:Send("test-guild", "main", ""), "Blank target rejected")
print("PASS: party, raid and instance broadcasts, per-recipient confirmation, exclusions and expiry")

inGroup = true
set(receiver, "Keep-Sargeras", "raider", "melee")
assert(sender.RosterTransfer:Send("test-guild", "main", "Meemage-Sargeras"))
advance(0.2)
receiver.RosterTransfer:AcceptOffer(receiver.RosterTransfer.inbound)
advance(5, function(packet)
    if packet.parts[1] == "LVC" and packet.parts[3] == packet.parts[4] then sender.info.rankIndex = 8 end
    return true
end)
assert(rr.cfg.teams[1].ro[receiver.Store:NameID("test-guild", "Keep-Sargeras")], "Permission change during receipt prevents replacement")
eq(sender.RosterTransfer.outbound, nil, "Rejected import does not report success")
sender.info.rankIndex = 1
advance(11)
assert(sender.RosterTransfer:Send("test-guild", "main", "Meemage-Sargeras"))
advance(0.2)
receiver.RosterTransfer:AcceptOffer(receiver.RosterTransfer.inbound)
advance(12, function(packet) return packet.parts[1] ~= "LVC" end)
eq(sender.RosterTransfer.outbound, nil, "Lost transfer stops after bounded retries")
assert(rr.cfg.teams[1].ro[receiver.Store:NameID("test-guild", "Keep-Sargeras")], "Incomplete receipt never mutates roster")
advance(600)
eq(receiver.RosterTransfer.inbound, nil, "Incomplete receive expires")
print("PASS: permission rechecks, bounded retries and atomic incomplete-transfer rejection")

-- Missing Blizzard rank data must not hide an offer. A late acceptance may
-- verify after the original 60-second offer window, without losing the sender.
local oldClub, oldGuildInfo = C_Club, C_GuildInfo
local rankRequests, rankReady = 0, false
C_Club = nil
C_GuildInfo = { GuildRoster = function()
    rankRequests = rankRequests + 1
    C_Timer.After(2, function() rankReady = true end)
end }
local cold, coldRecord = newClient("ColdMember-Sargeras", 8)
function cold.Guild:LoadedGuildRosterMember(fullName)
    if rankReady and self:NormalizeMemberName(fullName) == "Officer-Sargeras" then return { rankIndex = 1 } end
end
function cold.Guild:RefreshRoster() error("A selected transfer must not rebuild the full roster") end
local popupCount = #prompts
assert(sender.RosterTransfer:Send("test-guild", "main", "ColdMember-Sargeras"))
advance(0.2)
eq(#prompts, popupCount + 1, "Cold recipient sees a confirmation")
eq(rankRequests, 0, "Offers do not request a guild roster before acceptance")
eq(sender.RosterTransfer.outbound.responses["coldmember-sargeras"], "shown", "Sender receives popup acknowledgment")
advance(58.8)
cold.RosterTransfer:AcceptOffer(cold.RosterTransfer.inbound)
assert(cold.RosterTransfer.inbound.rankTicker, "Accepted offer waits for missing rank")
eq(cold.RosterTransfer.inbound.accepted, nil, "Unverified offer cannot start data transfer")
eq(rankRequests, 1, "Only the accepted manual transfer loads Blizzard's rank cache")
advance(1.2)
assert(sender.RosterTransfer.outbound and sender.RosterTransfer.outbound.closed,
    "Original offer expiry keeps the accepted permission check alive")
eq(next(coldRecord.cfg.teams[1].ro), nil, "Missing rank does not grant import permission")
advance(5)
assert(cold.RosterTransfer.inbound.complete and next(coldRecord.cfg.teams[1].ro), "Loaded rank resumes and completes the transfer")
eq(sender.RosterTransfer.outbound, nil, "Late verification releases completed sender")
print("PASS: cold guild rank caches show confirmation and late acceptance resumes after verification")

-- The advertised member ID is a hint resolved by Blizzard, never a claimed rank.
local modern, modernRecord = newClient("ModernMember-Sargeras", 8)
function modern.Guild:LoadedGuildRosterMember() return nil end
local memberReads, memberSearches = 0, 0
C_Club = {
    GetGuildClubId = function() return 501 end,
    GetMemberInfoForSelf = function() return { memberId = 37 } end,
    GetMemberInfo = function(_, id)
        memberReads = memberReads + 1
        if id == 37 then return { name = "Officer-Sargeras", guildRankOrder = 2 } end
    end,
    GetClubMembers = function() memberSearches = memberSearches + 1; return {} end,
}
sender.Guild.ownClubID, sender.Guild.ownClubMemberID = nil, nil
assert(sender.RosterTransfer:Send("test-guild", "main", "ModernMember-Sargeras"))
eq(packets[1].parts[7], "37", "Offer includes the sender's Blizzard member ID")
advance(0.2)
modern.RosterTransfer:AcceptOffer(modern.RosterTransfer.inbound)
advance(5)
assert(modern.RosterTransfer.inbound.complete and next(modernRecord.cfg.teams[1].ro), "Modern member data verifies a cold recipient")
eq(memberSearches, 0, "Valid member hints avoid searching other members")
assert(memberReads > 0, "Identity and rank were read from Blizzard")
print("PASS: modern member hints authorize transfers without a loaded guild roster")

-- An ID that names another local player falls back to a bounded selected lookup.
local mismatched, mismatchedRecord = newClient("MismatchedMember-Sargeras", 8)
function mismatched.Guild:LoadedGuildRosterMember() return nil end
local ids = {}
for index = 1, 205 do ids[index] = index end
function C_Club.GetClubMembers() memberSearches = memberSearches + 1; return ids end
function C_Club.GetMemberInfo(_, id)
    if id == 201 then return { name = "Officer-Sargeras", guildRankOrder = 2 } end
    return { name = "DifferentPlayer-Sargeras", guildRankOrder = 1 }
end
assert(sender.RosterTransfer:Send("test-guild", "main", "MismatchedMember-Sargeras"))
advance(0.2)
mismatched.RosterTransfer:AcceptOffer(mismatched.RosterTransfer.inbound)
assert(mismatched.RosterTransfer.inbound.rankTicker, "Incorrect member ID does not authorize transfer")
advance(1.2)
eq(next(mismatchedRecord.cfg.teams[1].ro), nil, "First bounded lookup cannot import the roster")
advance(6)
assert(mismatched.RosterTransfer.inbound.complete and next(mismatchedRecord.cfg.teams[1].ro), "Selected lookup finds the correct local member ID")
eq(mismatched.Guild.clubMemberIDs["test-guild|officer-sargeras"], 201, "Only the matched identity is cached")
print("PASS: mismatched remote member IDs use a bounded selected lookup")

local unavailable, unavailableRecord = newClient("UnavailableMember-Sargeras", 8)
function unavailable.Guild:LoadedGuildRosterMember() return nil end
C_Club = nil
function C_GuildInfo.GuildRoster() rankRequests = rankRequests + 1 end
assert(sender.RosterTransfer:Send("test-guild", "main", "UnavailableMember-Sargeras"))
advance(0.2)
unavailable.RosterTransfer:AcceptOffer(unavailable.RosterTransfer.inbound)
advance(22)
eq(sender.RosterTransfer.outbound, nil, "Rank timeout gives sender a rejection")
eq(unavailable.RosterTransfer.inbound, nil, "Rank timeout releases recipient")
eq(next(unavailableRecord.cfg.teams[1].ro), nil, "Unavailable rank cannot change a roster")
assert(sender.prints[#sender.prints]:find("could not verify", 1, true), "Sender sees why verification failed")
C_Club, C_GuildInfo = oldClub, oldGuildInfo
print("PASS: permission lookup timeout rejects without mutations and reports the reason")

wipe(sr.cfg.teams[1].ro)
local emptyExport = sender.RosterTransfer:Export("test-guild", "main")
imported, count = receiver.RosterTransfer:Import("test-guild", emptyExport)
eq(count, 0, "Empty roster supported")
eq(next(imported.ro), nil, "Empty import clears roster")
print("PASS: confirmed empty exports can clear a roster")

-- Exercise the real UI confirmation path without constructing Blizzard frames.
assert(loadfile("UI/MainFrame.lua"))("LootViewer", receiver)
function receiver.UI:Refresh() end
local confirmation
function receiver.UI:ShowConfirmationDialog(options) confirmation = options end
receiver.UI:ConfirmRosterImport("test-guild", exported)
assert(confirmation and confirmation.message:find("Main", 1, true), "UI shows target team confirmation")
eq(next(rr.cfg.teams[1].ro), nil, "UI confirmation precedes roster changes")
confirmation.onAccept()
assert(next(rr.cfg.teams[1].ro), "Confirm applies roster import")
confirmation = nil
receiverInfo.rankIndex = 8
receiver.UI:ConfirmRosterImport("test-guild", exported)
eq(confirmation, nil, "Read-only UI cannot open an import confirmation")
receiverInfo.rankIndex = 2
print("PASS: manual UI imports wait for confirmation and respect current permissions")

-- Expose real Lua-produced exports to the Python compatibility regression.
ROSTER_TRANSFER_FIXTURE = exported
ROSTER_TRANSFER_EMPTY_FIXTURE = emptyExport
