-- Uses the real store, guild authority, roster sync, and reliable transfer code.
local now = 1000
function time() return math.floor(now) end
GetServerTime, GetTime = time, function() return now end
function GetRealmName() return "Realm" end
function wipe(t) for key in pairs(t) do t[key] = nil end return t end
function IsInGuild() return true end
function GuildRoster() error("Sync must not request a guild roster scan") end
function GetNumGuildMembers() error("Sync must use cached roster data") end
function StaticPopup_Show() end
StaticPopupDialogs, ACCEPT = {}, "Accept"
local timers, messages, clients, ranks = {}, {}, {}, {}
C_Timer = {
    NewTicker = function(_, callback)
        local timer = { callback = callback, Cancel = function(self) self.cancelled = true end }
        timers[#timers + 1] = timer
        return timer
    end,
    After = function() end,
}
local guildKey = "test-guild"
local function eq(actual, expected, label)
    assert(actual == expected, (label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function newClient(name, rank)
    local LV = { modules = {}, events = {}, Print = function() end }
    function LV:RegisterEvent(event, handler)
        self.events[event] = self.events[event] or {}
        table.insert(self.events[event], handler)
    end
    for _, file in ipairs({ "Constants", "Util", "Store", "Guild", "RosterSync", "DataSync" }) do
        assert(loadfile("Core/" .. file .. ".lua"))("LootViewer", LV)
    end
    LootViewerDB = {}
    LV.Store:Initialize()
    function LV.Util:PlayerFullName() return name end
    local info = { key = guildKey, name = "Test Guild", realm = "Realm", rankIndex = rank }
    function LV.Guild:ActualInfo() return info end
    LV.Guild.CurrentInfo = LV.Guild.ActualInfo
    function LV.Guild:CurrentKey() return guildKey end
    LV.Guild.originalLoadedGuildRosterMember = LV.Guild.LoadedGuildRosterMember
    function LV.Guild:LoadedGuildRosterMember(fullName)
        return ranks[fullName] and { rankIndex = ranks[fullName] } or nil
    end
    ranks[name], clients[name] = rank, LV
    LV.Comms = {
        SendMessage = function() return true end,
        SendWhisper = function(_, kind, target, payload)
            local parts = { kind }
            for _, value in ipairs(payload) do parts[#parts + 1] = tostring(value) end
            messages[#messages + 1] = { parts = parts, sender = name, target = target }
            return true
        end,
    }
    local record = LV.Store:GuildRecord(guildKey)
    record.cfg.authority = "trusted"
    LV.Raid = { ReconcileGuildLinkedAttendance = function() LV.reconciled = (LV.reconciled or 0) + 1 end }
    return LV, record
end
local function id(client, name) return client.Store:NameID(guildKey, name .. "-Realm") end
local function override(client, name, tag, main)
    client.Guild:SetRosterOverride(guildKey, name .. "-Realm", tag, main and main .. "-Realm")
end
local function assign(client, name, kind, role)
    local assignment = client.Store:SetTeamRosterPlayer(guildKey, "main", id(client, name), kind, role, "")
    client.RosterSync:PublishPlayer(guildKey, "main", id(client, name), assignment, false)
end
local function import(client, sender, payload)
    local session = { guildKey = guildKey, target = sender }
    client.DataSync:HandleGenericPayload(session, "V", payload, sender)
    return session
end

local a, ar = newClient("Officer-Realm", 1)
local b, br = newClient("Partner-Realm", 2)
id(b, "DifferentDictionaryOrder")
for _, client in ipairs({ a, b }) do
    override(client, "Billcosbyed", "guild")
    override(client, "Trashhealur", "alt", "Billcosbyed")
    assign(client, "Billcosbyed", "raider", "healer")
    assign(client, "Promoted", "trial", "ranged")
    assign(client, "Removed", "helper", "melee")
    client.Store:AddRosterMember(guildKey, "Promoted-Realm", { r = 6, rn = "Trial", c = "MAGE" })
    client.Store:AddRosterMember(guildKey, "Demoted-Realm", { r = 2, rn = "Officer", c = "WARRIOR" })
    local record = client.Store:GuildRecord(guildKey)
    record.r.same = { id = "same", st = 950, team = "main", kills = {}, p = {}, b = {},
        late = {}, out = {}, noshow = {} }
end
local stale = b.DataSync:BuildManifest(guildKey)
now = 2000
override(a, "Trashhealur", "guild")
override(a, "Billcosbyed", "alt", "Trashhealur")
assign(a, "Promoted", "raider", "ranged")
assign(a, "Billcosbyed", "helper", "healer")
a.Store:RemoveTeamRosterPlayer(guildKey, "main", id(a, "Removed"))
a.RosterSync:PublishPlayer(guildKey, "main", id(a, "Removed"), {}, true)
a.Store:AddRosterMember(guildKey, "Promoted-Realm", { r = 3, rn = "Raider", c = "MAGE", on = "PRIVATE NOTE" })
a.Store:AddRosterMember(guildKey, "Demoted-Realm", { r = 7, rn = "Social", c = "WARRIOR" })
ar.cfg.teams[#ar.cfg.teams + 1] = { id = "newteam", name = "New Team", rt = 2000,
    ro = { [id(a, "Trashhealur")] = { t = "raider", p = "healer" } } }
ar.cfg.teams[#ar.cfg.teams + 1] = { id = "private", name = "Private", rt = 2000, excludeSync = true,
    ro = { [id(a, "PrivatePlayer")] = { t = "raider" } } }
local fresh = a.DataSync:BuildManifest(guildKey)
assert(not fresh:find("PRIVATE NOTE", 1, true), "Officer notes must not be transferred")
assert(not fresh:find("PrivatePlayer", 1, true), "Excluded rosters must not be transferred")
b.reconciled = 0
local session = import(b, "Officer-Realm", fresh)
eq(#session.comparison.missingLocal, 0, "Matching raids require no selection")
eq(#session.comparison.missingRemote, 0, "Matching raids remain up to date")
eq(br.o[id(b, "Trashhealur")].tag, "guild", "New main")
eq(br.o[id(b, "Trashhealur")].main, nil, "Old alt link cleared")
eq(br.o[id(b, "Billcosbyed")].main, id(b, "Trashhealur"), "Alt links use recipient IDs")
eq(br.cfg.teams[1].ro[id(b, "Promoted")].t, "raider", "Team promotion")
eq(br.cfg.teams[1].ro[id(b, "Billcosbyed")].t, "helper", "Team demotion")
eq(br.cfg.teams[1].ro[id(b, "Removed")], nil, "Removed assignment")
eq(br.gr[id(b, "Promoted")].r, 3, "Guild promotion")
eq(br.gr[id(b, "Demoted")].r, 7, "Guild demotion")
assert(b.Store:GetTeamByID(br, "newteam").ro[id(b, "Trashhealur")], "Missing team created")
eq(b.Store:GetTeamByID(br, "private"), nil, "Excluded team stays local")
eq(b.reconciled, 1, "Reconcile only after complete main swap")
eq(session.rosterImported.links, 2, "Visible link count")
eq(br.cfg.authority, "trusted", "Sync preserves local authority settings")
print("PASS: up-to-date raids still sync mains, alts, ranks, teams, roles, and removals")

session = import(a, "Partner-Realm", stale)
eq(ar.o[id(a, "Billcosbyed")].main, id(a, "Trashhealur"), "Stale main swap rejected")
eq(ar.cfg.teams[1].ro[id(a, "Promoted")].t, "raider", "Stale team rejected")
eq(ar.gr[id(a, "Demoted")].r, 7, "Stale guild rank rejected")
session = import(b, "Officer-Realm", fresh)
eq(session.rosterImported.links, 0, "Repeated import is idempotent")
eq(session.rosterImported.teams, 0, "Repeated team import is idempotent")
eq(session.rosterImported.members, 0, "Repeated rank import is idempotent")
print("PASS: reverse sync preserves newer edits and repeat imports make no changes")

local rankTime = br.gr[id(b, "Promoted")].rts
now = 3000
b.Store:AddRosterMember(guildKey, "Promoted-Realm", { c = "MAGE" })
eq(br.gr[id(b, "Promoted")].rts, rankTime, "Class observation cannot freshen a rank")
b.Store:AddRosterMember(guildKey, "Promoted-Realm", { r = 8, rn = "Social" })
b.Store:AddRosterMember(guildKey, "Promoted-Realm", { r = 2, rn = "Officer" })
assert(br.gr[id(b, "Promoted")].rts > now, "Same-second rank edits need increasing revisions")
override(b, "Billcosbyed", "guild")
override(b, "Billcosbyed", "alt", "Trashhealur")
assert(br.o[id(b, "Billcosbyed")].ts > now, "Same-second tag edits need increasing revisions")
print("PASS: rank freshness is independent of raid observations; rapid edits stay ordered")

local c, cr = newClient("Recipient-Realm", 2)
ranks["Officer-Realm"] = 8
session = import(c, "Officer-Realm", fresh)
eq(next(cr.o), nil, "Unauthorized main changes rejected")
eq(next(cr.gr), nil, "Unauthorized ranks rejected before authority can change")
eq(session.rosterImported, nil, "Unauthorized import reported")
ranks["Officer-Realm"] = 1
session = import(c, "Officer-Realm", fresh:gsub("g=test%-guild", "g=another-guild"))
eq(session.state, "error", "Wrong guild rejected")
eq(next(cr.o), nil, "Wrong guild made no changes")
local oldManifest = "MV\tv=6\tg=test-guild\tcutoff=0"
session = import(c, "Officer-Realm", oldManifest)
eq(session.state, "ready", "Older peer raid comparison still works")
assert(session.rosterStatus:find("update LootViewer", 1, true), "Older peer gets update guidance")
local untrusted = newClient("Untrusted-Realm", 8)
local untrustedManifest = untrusted.DataSync:ParseManifest(untrusted.DataSync:BuildManifest(guildKey))
eq(untrustedManifest.roster.publisher, false, "Untrusted clients do not publish")
print("PASS: authority, guild boundaries, and older clients are handled")

local malformed = c.DataSync:ParseManifest(fresh).roster
malformed.teams[1].count = 999
c.RosterSync:ApplySyncSnapshot(guildKey, "Officer-Realm", malformed)
eq(next(cr.cfg.teams[1].ro), nil, "Incomplete team cannot replace the roster")
cr.cfg.teams[1].excludeSync = true
import(c, "Officer-Realm", fresh)
eq(next(cr.cfg.teams[1].ro), nil, "Receiver's excluded team stays untouched")
cr.cfg.teams[1].excludeSync = false
now = 4000
wipe(ar.cfg.teams[1].ro)
a.RosterSync:BumpTeamRevision(ar.cfg.teams[1])
import(b, "Officer-Realm", a.DataSync:BuildManifest(guildKey))
eq(next(br.cfg.teams[1].ro), nil, "Empty snapshot removes final assignment")
print("PASS: incomplete snapshots, local exclusions, and empty rosters")

-- Equal edit times resolve identically, regardless of which player starts sync.
now = 4500
override(a, "TiePlayer", "guild")
override(b, "TiePlayer", "pug")
local tieA, tieB = a.DataSync:BuildManifest(guildKey), b.DataSync:BuildManifest(guildKey)
import(b, "Officer-Realm", tieA)
import(a, "Partner-Realm", tieB)
eq(ar.o[id(a, "TiePlayer")].tag, br.o[id(b, "TiePlayer")].tag, "Concurrent edits converge")
print("PASS: equal-time edits converge in both directions")

-- Exercise the actual invite, both manifests, chunk acknowledgments and retry.
messages, timers = {}, {}
local dropped = false
a.DataSync:StartSync("Recipient-Realm")
override(a, "EditedWhileWaiting", "guild")
for _ = 1, 2000 do
    local pending = messages
    messages = {}
    for _, message in ipairs(pending) do
        local peer = clients[message.target]
        if message.parts[1] == "G" and message.parts[5] == "2" and not dropped then
            dropped = true
        else
            peer.DataSync:HandleMessage(message.parts, message.sender)
            if message.parts[1] == "Q" then peer.DataSync:AcceptInvite() end
        end
    end
    now = now + 0.25
    local active = false
    for _, timer in ipairs(timers) do
        if not timer.cancelled then timer.callback(); active = true end
    end
    if not active and #messages == 0 then break end
end
assert(dropped, "Transfer must exercise a dropped chunk")
eq(a.DataSync.outbound.state, "ready", "Initiator finishes reliable handshake")
eq(c.DataSync.inbound.state, "ready", "Receiver finishes reliable handshake")
assert(a.DataSync.outbound.rosterImported, "Initiator automatically imports roster")
assert(c.DataSync.inbound.rosterImported, "Receiver automatically imports roster")
eq(cr.o[id(c, "Billcosbyed")].main, id(c, "Trashhealur"), "Main swap arrives over the real transfer")
eq(cr.o[id(c, "EditedWhileWaiting")].tag, "guild", "Edits while awaiting acceptance are included")
print("PASS: two-way invite handshake automatically imports roster after a dropped chunk")

-- Automatic sync uses the real event handlers, paced packets and timeout
-- recovery. Nobody accepts an invite and no raid details are requested.
messages, timers = {}, {}
local delayed, sent = {}, {}
for _, client in pairs(clients) do client.online = false end
local publisher, pr = newClient("LiveOfficer-Realm", 1)
local recipient, rr = newClient("LiveMember-Realm", 8)
local offline, off = newClient("OfflineMember-Realm", 8)
offline.online = false
local function enableNetwork(client, name)
    function client.Comms:SendMessage(kind, payload, channel, target)
        local parts = { kind }
        for _, value in ipairs(payload) do parts[#parts + 1] = tostring(value) end
        local packet = { parts = parts, sender = name, target = target, channel = channel }
        if kind == "LRM" then assert(#table.concat(parts, "\031") <= 255, "Oversized addon message") end
        messages[#messages + 1], sent[#sent + 1] = packet, packet
        return true
    end
    function client.Comms:SendWhisper(kind, target, payload)
        return self:SendMessage(kind, payload, "WHISPER", target)
    end
end
for name, client in pairs(clients) do enableNetwork(client, name) end
function C_Timer.After(delay, callback)
    delayed[#delayed + 1] = { at = now + delay, callback = callback }
end
local function advance(seconds, filter)
    local untilTime = now + seconds
    while now < untilTime do
        now = now + 0.05
        for index = #delayed, 1, -1 do
            local timer = delayed[index]
            if timer.at <= now then table.remove(delayed, index); timer.callback() end
        end
        local pending = messages
        messages = {}
        for _, packet in ipairs(pending) do
            if not filter or filter(packet) then
                for name, client in pairs(clients) do
                    if client.online ~= false and (packet.channel == "GUILD" or packet.target == name) then
                        assert(client.RosterSync:IsRosterKind(packet.parts[1]), "Unexpected manual sync message")
                        client.RosterSync:HandleMessage(packet.parts, packet.sender, packet.channel)
                    end
                end
            end
        end
    end
end
local function fire(client, event)
    for _, handler in ipairs(client.events[event] or {}) do handler(nil) end
end
local function metadata(client)
    local record = client.Store:GuildRecord(guildKey)
    return client.RosterSync:BuildSyncSnapshot(guildKey, { overrides = record.o, members = record.gr })
end
local function countSent(sender, kind)
    local count = 0
    for _, packet in ipairs(sent) do
        if packet.sender == sender and packet.parts[1] == kind then count = count + 1 end
    end
    return count
end

now = 10000
override(publisher, "Trashhealur", "guild")
override(publisher, "Billcosbyed", "alt", "Trashhealur")
publisher.Store:AddRosterMember(guildKey, "Promoted-Realm", { r = 2, rn = "Officer", c = "MAGE" })
publisher.Store:AddRosterMember(guildKey, "Demoted-Realm", { r = 8, rn = "Social", c = "WARRIOR", on = "SECRET" })
advance(5)
eq(rr.o[id(recipient, "Billcosbyed")].main, id(recipient, "Trashhealur"), "Live main swap")
eq(rr.gr[id(recipient, "Promoted")].r, 2, "Live promotion")
eq(rr.gr[id(recipient, "Demoted")].r, 8, "Live demotion")
eq(recipient.reconciled, 1, "Live main swap applies as a complete batch")
eq(countSent("LiveMember-Realm", "LRM"), 0, "Imports do not echo to guild")
eq(next(off.o), nil, "Offline peer missed the live edit")
eq(recipient.DataSync.pendingInvite, nil, "Automatic updates need no manual invite")
eq(recipient.DataSync.inbound, nil, "Automatic updates do not use manual sessions")
for _, packet in ipairs(sent) do
    assert(not table.concat(packet.parts):find("SECRET", 1, true), "Automatic sync must omit officer notes")
end
local packetsBefore = countSent("LiveOfficer-Realm", "LRM")
publisher.Store:AddRosterMember(guildKey, "Promoted-Realm", { r = 2, rn = "Officer", c = "MAGE" })
publisher.Store:AddRosterMember(guildKey, "Demoted-Realm", { c = "WARRIOR" })
advance(2)
eq(countSent("LiveOfficer-Realm", "LRM"), packetsBefore, "Unchanged ranks and class observations stay quiet")
print("PASS: live mains and ranks sync atomically without invites, echoes, scans or private notes")

offline.online = true
fire(offline, "PLAYER_ENTERING_WORLD")
advance(15)
eq(off.o[id(offline, "Billcosbyed")].main, id(offline, "Trashhealur"), "Login catch-up")
eq(off.gr[id(offline, "Demoted")].r, 8, "Login catches up cached guild ranks")
offline.online = false
override(publisher, "Billcosbyed", "guild")
advance(3)
offline.online = true
local inRaid = true
function IsInRaid() return inRaid end
fire(offline, "GROUP_ROSTER_UPDATE")
advance(15)
eq(off.o[id(offline, "Billcosbyed")].tag, "guild", "Joining raid catches cleared alt link")
eq(off.o[id(offline, "Billcosbyed")].main, nil, "Cleared main link stays cleared")
local requests = countSent("OfflineMember-Realm", "LRQ")
for _ = 1, 25 do fire(offline, "GROUP_ROSTER_UPDATE") end
advance(6)
eq(countSent("OfflineMember-Realm", "LRQ"), requests, "Group changes do not repeatedly request snapshots")
print("PASS: login and raid-join catch-up work without requests on every group change")

local oldAuto = metadata(publisher)
override(publisher, "Billcosbyed", "alt", "Trashhealur")
advance(3)
publisher.RosterSync:SendMetadata(guildKey, "u-stale", oldAuto)
advance(3)
eq(rr.o[id(recipient, "Billcosbyed")].tag, "alt", "Stale automatic snapshot cannot undo new edit")
-- Long labels, delimiters and UTF-8 must survive byte chunking and escaping.
local longRank = string.rep("Officér%\t\n", 40)
publisher.Store:AddRosterMember(guildKey, "LongLabel-Realm", { r = 3, rn = longRank, c = "MAGE" })
local captured = {}
advance(4, function(packet)
    if packet.parts[1] == "LRM" then captured[#captured + 1] = packet; return false end
    return true
end)
assert(#captured > 2, "Test must split the long label")
for index = #captured, 2, -1 do
    local packet = captured[index]
    recipient.RosterSync:HandleMessage(packet.parts, packet.sender, packet.channel)
    recipient.RosterSync:HandleMessage(packet.parts, packet.sender, packet.channel)
end
eq(rr.gr[id(recipient, "LongLabel")], nil, "Partial metadata never applies")
local first = captured[1]
recipient.RosterSync:HandleMessage(first.parts, first.sender, first.channel)
eq(rr.gr[id(recipient, "LongLabel")].rn, longRank, "Out-of-order duplicate chunks retain UTF-8 and delimiters")
recipient.RosterSync:HandleMessage(first.parts, first.sender, first.channel)
eq(countSent("LiveMember-Realm", "LRM"), 0, "Duplicate complete packets do not echo")
print("PASS: stale, duplicate and out-of-order packets preserve current data and long labels")

-- Drop one live packet, then allow the timeout's automatic snapshot request.
override(publisher, "RecoveredAlt", "alt", "Trashhealur")
publisher.Store:AddRosterMember(guildKey, "RecoveredAlt-Realm", { r = 4, rn = longRank })
local lost = false
advance(45, function(packet)
    if packet.parts[1] == "LRM" and packet.channel == "GUILD" and packet.parts[4] == "2" and not lost then
        lost = true; return false
    end
    return true
end)
assert(lost, "Test must drop a metadata chunk")
eq(rr.o[id(recipient, "RecoveredAlt")].main, id(recipient, "Trashhealur"), "Timeout automatically recovers missing edit")
eq(rr.gr[id(recipient, "RecoveredAlt")].rn, longRank, "Timeout recovers complete rank record")
assert(countSent("LiveMember-Realm", "LRQ") > 0, "Recovery requested a snapshot")
print("PASS: incomplete live updates automatically recover through a catch-up snapshot")

-- Authority is checked again at commit even if the cached packet check passed.
publisher.Store:AddRosterMember(guildKey, "UntrustedUpdate-Realm", { r = 1, rn = longRank })
captured = {}
advance(4, function(packet)
    if packet.parts[1] == "LRM" then captured[#captured + 1] = packet; return false end
    return true
end)
for index = 1, #captured - 1 do
    local packet = captured[index]
    recipient.RosterSync:HandleMessage(packet.parts, packet.sender, packet.channel)
end
ranks["LiveOfficer-Realm"] = 8
local last = captured[#captured]
recipient.RosterSync:HandleMessage(last.parts, last.sender, last.channel)
eq(rr.gr[id(recipient, "UntrustedUpdate")], nil, "Demoted publisher cannot finish import")
ranks["LiveOfficer-Realm"] = 1
local broadcasts = countSent("LiveMember-Realm", "LRM")
override(recipient, "LocalOnly", "guild")
advance(2)
eq(countSent("LiveMember-Realm", "LRM"), broadcasts, "Unauthorized editor does not broadcast")
local oldPeerPackets = countSent("LiveOfficer-Realm", "LRM")
publisher.RosterSync:HandleMessage({ "LRQ", guildKey, "old-peer" }, "LiveMember-Realm", "GUILD")
advance(3)
eq(countSent("LiveOfficer-Realm", "LRM"), oldPeerPackets, "Legacy peer is not sent metadata")
print("PASS: automatic sync enforces authority at send and commit and keeps old peers compatible")

-- A persistently lossy connection gets two catch-up attempts, not an endless
-- broadcast loop. Requests from other clients are disabled for this case.
offline.online = false
local requestsBeforeLoss = countSent("LiveMember-Realm", "LRQ")
publisher.Store:AddRosterMember(guildKey, "AlwaysLost-Realm", { r = 3, rn = longRank })
advance(120, function(packet)
    return not (packet.parts[1] == "LRM" and packet.parts[4] == "2")
end)
eq(countSent("LiveMember-Realm", "LRQ") - requestsBeforeLoss, 2, "Incomplete metadata retries are bounded")
eq(rr.gr[id(recipient, "AlwaysLost")], nil, "Repeatedly incomplete snapshots never partially import")
eq(next(recipient.RosterSync.metadataIncoming), nil, "Expired receive buffers are released")
print("PASS: persistent packet loss has bounded retries and releases partial snapshots")

-- Reproduce the rank-1/rank-3 sync with the actual cached-roster lookup,
-- short whisper names and a cold guild-directive cache on both clients.
messages, timers = {}, {}
local one, oneRecord = newClient("RankOne-Realm", 1)
local three, threeRecord = newClient("RankThree-Realm", 3)
one.Guild.LoadedGuildRosterMember = one.Guild.originalLoadedGuildRosterMember
three.Guild.LoadedGuildRosterMember = three.Guild.originalLoadedGuildRosterMember
oneRecord.cfg.authority, threeRecord.cfg.authority = "assist", "assist"
local loadedRoster = {
    { name = "RankOne-Realm", rank = 1 }, { name = "RankThree-Realm", rank = 3 },
    { name = "Boundary-Realm", rank = 4 }, { name = "Outside-Realm", rank = 5 },
    { name = "Space-Area 52", rank = 1 },
}
function GetNumGuildMembers() return #loadedRoster end
function GetGuildRosterInfo(index)
    local member = loadedRoster[index]
    return member.name, "Guild Rank", member.rank, nil, "Mage", nil, nil, nil, true, nil, "MAGE"
end
function IsInRaid() return false end
function IsInGroup() return false end
function UnitExists() return false end
function UnitIsGroupLeader() return false end
function UnitIsGroupAssistant() return false end
local description, clubReads = "LootViewer Authority: Trusted 0-4", 0
C_Club = {
    GetGuildClubId = function() return 1 end,
    GetClubInfo = function()
        clubReads = clubReads + 1
        return description and { description = description } or nil
    end,
}
eq(one.Guild:CanPublishRoster(), true, "Rank 1 can publish without opening Configuration")
eq(three.Guild:CanPublishRoster(), true, "Rank 3 can publish without opening Configuration")
eq(three.Guild:CanAcceptRosterPublisher(guildKey, "RankOne"), true, "Rank 1 short sender resolves")
eq(one.Guild:CanAcceptRosterPublisher(guildKey, "RankThree"), true, "Rank 3 short sender resolves")
eq(one.Guild:CanAcceptRosterPublisher(guildKey, "Boundary"), true, "Guild directive allows rank 4")
eq(one.Guild:CanAcceptRosterPublisher(guildKey, "Space-Area52"), true, "Realm formatting is normalized")
eq(one.Guild:CanAcceptRosterPublisher(guildKey, "RankThree-OtherRealm"), false, "Different realm is not mistaken for trusted player")
local allowed, reason = one.Guild:CanAcceptRosterPublisher(guildKey, "Outside")
eq(allowed, false, "Rank 5 remains rejected")
assert(reason:find("rank 5", 1, true) and reason:find("0-4", 1, true), "Rank rejection explains the actual range")
eq(clubReads, 2, "Directive reads are throttled per client")

override(one, "Trashhealur", "guild")
override(one, "Billcosbyed", "alt", "Trashhealur")
override(three, "OtherMain", "guild")
one.DataSync:StartSync("RankThree")
for _ = 1, 2000 do
    local pending = messages
    messages = {}
    for _, message in ipairs(pending) do
        local peer = clients[message.target] or clients[message.target .. "-Realm"]
        local shortSender = peer.Util:ShortName(message.sender)
        peer.DataSync:HandleMessage(message.parts, shortSender)
        if message.parts[1] == "Q" then peer.DataSync:AcceptInvite() end
    end
    now = now + 0.25
    local active = false
    for _, timer in ipairs(timers) do
        if not timer.cancelled then timer.callback(); active = true end
    end
    if not active and #messages == 0 then break end
end
eq(threeRecord.o[id(three, "Billcosbyed")].main, id(three, "Trashhealur"), "Rank 3 receives rank 1's main swap")
eq(oneRecord.o[id(one, "OtherMain")].tag, "guild", "Rank 1 receives rank 3's data")
eq(one.DataSync.outbound.rosterSentAccepted, true, "Rank 1 receives actual delivery confirmation")
eq(three.DataSync.inbound.rosterSentAccepted, true, "Rank 3 receives actual delivery confirmation")
local display = one.DataSync:RosterStatusText(one.DataSync.outbound)
assert(display:find("From RankThree:", 1, true) and display:find("To RankThree:", 1, true), "Display identifies both directions")
print("PASS: rank 1 and rank 3 sync both ways with cold settings, short names and delivery receipts")

-- Read only the matched group unit when Blizzard's guild roster is not loaded.
loadedRoster = {}
function IsInGroup() return true end
function GetNumSubgroupMembers() return 1 end
function UnitExists(unit) return unit == "party1" end
function UnitFullName(unit) return "RankThree", "Realm" end
local liveRank, guildUnitReads = 3, 0
function GetGuildInfo(unit)
    eq(unit, "party1", "Only matched publisher guild information is read")
    guildUnitReads = guildUnitReads + 1
    return "Test Guild", "Officer", liveRank, "Realm"
end
oneRecord.gr[id(one, "RankThree")] = { r = 8 }
eq(one.Guild:CanAcceptRosterPublisher(guildKey, "RankThree"), true, "Current group rank overrides stale saved rank")
eq(guildUnitReads, 1, "No full roster scan for the group publisher")
liveRank = 8
eq(one.Guild:CanAcceptRosterPublisher(guildKey, "RankThree"), false, "Live demotion is respected")
allowed, reason = one.Guild:CanAcceptRosterPublisher(guildKey, "NotLoaded")
eq(allowed, false, "Unknown ranks are not implicitly trusted")
assert(reason:find("rank unavailable", 1, true), "Unknown rank has an actionable message")
eq(oneRecord.gr[id(one, "NotLoaded")], nil, "Validation does not import claimed ranks")
print("PASS: live group ranks beat stale caches and unavailable ranks get a specific explanation")

-- Transient API unavailability and combat do not erase a loaded directive.
description = nil
one.Guild:ScanAuthorityDirective()
eq(one.Guild:EffectiveAuthority().mode, "trusted", "Unavailable club cache retains verified policy")
function InCombatLockdown() return true end
local readsBeforeCombat = clubReads
now = now + 60
eq(one.Guild:EffectiveAuthority().rankMax, 4, "Combat uses the cached directive")
eq(clubReads, readsBeforeCombat, "Combat does not query club descriptions")
function InCombatLockdown() return false end
description = "Guild info without a directive"
one.Guild:ScanAuthorityDirective()
eq(one.Guild:EffectiveAuthority().mode, "assist", "Actual directive removal restores local policy")
print("PASS: directive caching preserves combat safety, transient failures and local fallback settings")

-- Actual failure: two ungrouped officers with empty Blizzard and saved guild
-- rosters. Neither opens the Guild window. Blizzard answers asynchronously.
messages, timers, loadedRoster = {}, {}, {}
description = "LootViewer Authority: Trusted 0-4"
function IsInGroup() return false end
local coldOne, coldOneRecord = newClient("ColdOne-Realm", 1)
local coldThree, coldThreeRecord = newClient("ColdThree-Realm", 3)
for _, client in ipairs({ coldOne, coldThree }) do
    client.Guild.LoadedGuildRosterMember = client.Guild.originalLoadedGuildRosterMember
    function client.Guild:RefreshRoster() error("Sync must not rebuild the full guild roster") end
    client.Guild:CurrentConfig().authority = "assist"
end
local rankRequests, rosterReads = 0, 0
C_GuildInfo = { GuildRoster = function() rankRequests = rankRequests + 1 end }
local readRoster = GetGuildRosterInfo
function GetGuildRosterInfo(index)
    rosterReads = rosterReads + 1
    return readRoster(index)
end
local function guildRosterUpdated(client)
    for _, handler in ipairs(client.events.GUILD_ROSTER_UPDATE) do handler() end
end
local function manualStep()
    local pending = messages
    messages = {}
    for _, message in ipairs(pending) do
        local peer = clients[message.target] or clients[message.target .. "-Realm"]
        peer.DataSync:HandleMessage(message.parts, peer.Util:ShortName(message.sender))
        if message.parts[1] == "Q" then peer.DataSync:AcceptInvite() end
    end
    now = now + 0.25
    local active = false
    for _, timer in ipairs(timers) do
        if not timer.cancelled then timer.callback(); active = true end
    end
    return active or #messages > 0
end
local function finishManual()
    for _ = 1, 2000 do if not manualStep() then return end end
    error("Manual sync did not settle")
end
override(coldOne, "Trashhealur", "guild")
override(coldOne, "Billcosbyed", "alt", "Trashhealur")
override(coldThree, "OtherMain", "guild")
coldOne.DataSync:StartSync("ColdThree")
for _ = 1, 70 do
    manualStep()
    if coldOne.DataSync.outbound.rosterPending and coldThree.DataSync.inbound.rosterPending then break end
end
assert(coldOne.DataSync.outbound.rosterPending and coldThree.DataSync.inbound.rosterPending,
    "Both accounts wait for Blizzard instead of rejecting unknown ranks")
eq(rankRequests, 2, "Each manual sync requests its missing Blizzard rank data once")
eq(coldThreeRecord.o[id(coldThree, "Billcosbyed")], nil, "Unverified roster is held without importing")
assert(coldOne.DataSync.outbound.comparison, "Raid comparison remains usable during the rank lookup")
guildRosterUpdated(coldOne)
guildRosterUpdated(coldThree)
manualStep()
assert(coldOne.DataSync.outbound.rosterPending, "An early empty update does not reject the partner")
loadedRoster = {
    { name = "Unrelated-Realm", rank = 7 },
    { name = "ColdOne-Realm", rank = 1 }, { name = "ColdThree-Realm", rank = 3 },
}
for _ = 1, 100 do guildRosterUpdated(coldOne); guildRosterUpdated(coldThree) end
eq(rosterReads, 0, "Repeated roster load events never scan synchronously")
finishManual()
eq(coldThreeRecord.o[id(coldThree, "Billcosbyed")].main, id(coldThree, "Trashhealur"), "Cold rank 3 receives main swap")
eq(coldOneRecord.o[id(coldOne, "OtherMain")].tag, "guild", "Cold rank 1 receives peer data")
eq(coldOne.DataSync.outbound.rosterSentAccepted, true, "Deferred import sends success receipt to rank 1")
eq(coldThree.DataSync.inbound.rosterSentAccepted, true, "Deferred import sends success receipt to rank 3")
eq(coldOne.DataSync.outbound.rosterPending, nil, "Completed rank wait releases snapshot and timer")
eq(coldOneRecord.gr[id(coldOne, "Unrelated")], nil, "Rank lookup does not import unrelated guild members")
eq(rankRequests, 2, "Roster events do not start extra Blizzard requests")
print("PASS: empty guild caches load asynchronously and rank 1/rank 3 sync both ways without the Guild window")

-- Loading a rank is not permission by itself. A demoted sender remains denied.
loadedRoster, messages, timers = {}, {}, {}
now = now + 10
override(coldOne, "AfterDemotion", "guild")
coldOne.DataSync:StartSync("ColdThree")
for _ = 1, 70 do
    manualStep()
    if coldOne.DataSync.outbound.rosterPending and coldThree.DataSync.inbound.rosterPending then break end
end
loadedRoster = { { name = "ColdOne-Realm", rank = 8 }, { name = "ColdThree-Realm", rank = 3 } }
guildRosterUpdated(coldOne)
guildRosterUpdated(coldThree)
finishManual()
eq(coldThreeRecord.o[id(coldThree, "AfterDemotion")], nil, "Newly loaded demotion blocks held data")
eq(coldOne.DataSync.outbound.rosterSentAccepted, false, "Sender sees receiver's rank rejection")
assert(coldOne.DataSync.outbound.rosterSentStatus:find("rank 8", 1, true), "Receipt explains loaded rank rejection")
print("PASS: deferred verification still rejects an officer demoted outside trusted ranks")

-- Missing responses expire; abandoned sessions never apply held snapshots.
loadedRoster, messages, timers = {}, {}, {}
now = now + 10
coldOne.DataSync:StartSync("ColdThree")
finishManual()
eq(coldOne.DataSync.outbound.rosterPending, nil, "Missing Blizzard data has a bounded wait")
eq(coldThree.DataSync.inbound.rosterPending, nil, "Both timeout timers stop")
eq(coldOne.DataSync.outbound.rosterSentAccepted, false, "Timeout sends a rejection receipt")
assert(coldOne.DataSync.outbound.rosterSentStatus:find("rank unavailable", 1, true), "Timeout remains explicit")
local abandoned = { guildKey = guildKey, target = "ColdOne" }
coldThree.DataSync.inbound = abandoned
coldThree.DataSync:HandleGenericPayload(abandoned, "V", coldOne.DataSync:BuildManifest(guildKey), "ColdOne")
assert(abandoned.rosterPending, "Unknown peer waits in the accepted session")
local abandonedTimer = abandoned.rosterPending.ticker
coldThree.DataSync.inbound = nil
loadedRoster = { { name = "ColdOne-Realm", rank = 1 } }
abandonedTimer.callback()
eq(abandoned.rosterPending, nil, "Replacing the session discards held data")
eq(abandonedTimer.cancelled, true, "Abandoned timer is cancelled")
eq(coldThreeRecord.o[id(coldThree, "AfterDemotion")], nil, "Abandoned snapshot cannot import later")
print("PASS: missing rank data times out cleanly and replaced sessions cannot apply stale snapshots")

-- Retail may expose ranks in C_Club while the legacy roster stays empty.
-- Advertised member IDs locate data; they never supply or prove the rank.
messages, timers, loadedRoster = {}, {}, {}
local modernOne, modernOneRecord = newClient("ModernOne-Realm", 1)
local modernThree, modernThreeRecord = newClient("ModernThree-Realm", 3)
local clubMembers = {
    [101] = { name = "ModernOne", guildRankOrder = 2, memberId = 101 },
    [103] = { name = "ModernThree-Realm", guildRankOrder = 4, memberId = 103 },
    [104] = { name = "Boundary-Realm", guildRankOrder = 5, memberId = 104 },
    [105] = { name = "Outside-Realm", guildRankOrder = 6, memberId = 105 },
    [100] = { name = "GuildMaster-Realm", guildRankOrder = 1, memberId = 100 },
}
local selfMemberID, memberReads, focusRequests = 101, 0, 0
C_Club.GetMemberInfoForSelf = function(clubID) eq(clubID, 1); return clubMembers[selfMemberID] end
C_Club.GetMemberInfo = function(clubID, memberID)
    eq(clubID, 1, "Member IDs are always looked up in the local guild")
    memberReads = memberReads + 1
    return clubMembers[memberID]
end
C_Club.GetClubMembers = function() error("Advertised ID must not enumerate guild members") end
C_Club.FocusMembers = function(clubID) eq(clubID, 1); focusRequests = focusRequests + 1 end
for _, client in ipairs({ modernOne, modernThree }) do
    client.Guild.LoadedGuildRosterMember = client.Guild.originalLoadedGuildRosterMember
    client.Guild:ActualInfo().realm = "GuildHomeRealm"
    function client.Guild:RefreshRoster() error("No full roster rebuild") end
    local ownID = client == modernOne and 101 or 103
    local ownMember = client.Guild.OwnClubMemberID
    function client.Guild:OwnClubMemberID() selfMemberID = ownID; return ownMember(self) end
end
override(modernOne, "Billcosbyed", "alt", "Trashhealur")
override(modernThree, "OtherMain", "guild")
modernOne.DataSync:StartSync("ModernThree")
finishManual()
eq(modernThreeRecord.o[id(modernThree, "Billcosbyed")].main, id(modernThree, "Trashhealur"), "Modern club rank authorizes main swap")
eq(modernOneRecord.o[id(modernOne, "OtherMain")].tag, "guild", "Modern-only sync works in reverse")
eq(modernOne.DataSync.outbound.rosterSentAccepted, true, "Modern rank 1 receives acceptance")
eq(modernThree.DataSync.inbound.rosterSentAccepted, true, "Modern rank 3 receives acceptance")
eq(focusRequests, 0, "Loaded selected member needs no guild refresh")
eq(modernThree.Guild:RosterMemberRank(guildKey, "GuildMaster", 100), 0, "Guild master order 1 means rank 0")
eq(modernThree.Guild:CanAcceptRosterPublisher(guildKey, "Boundary", 104), true, "Club order 5 means trusted rank 4")
eq(modernThree.Guild:CanAcceptRosterPublisher(guildKey, "Outside", 105), false, "Club order 6 is outside 0-4")
eq(modernThree.Guild:CanAcceptRosterPublisher(guildKey, "Impostor", 101), false, "Someone else's officer ID cannot authorize a sender")
eq(modernThree.Guild:CanAcceptRosterPublisher(guildKey, "ModernOne-OtherRealm", 101), false, "Same short name on another realm cannot borrow an ID")
eq(modernThree.Guild:CanAcceptRosterPublisher("other-guild", "ModernOne", 101), false, "Club IDs cannot authorize cross-guild sync")
print("PASS: modern guild ranks authorize both directions, normalize cross-realm guild names and validate member IDs")

-- A fresh automatic recipient must also use the hint before its initial
-- authority gate, without enumerating the roster or waiting for manual sync.
messages, delayed, timers = {}, {}, {}
for _, client in pairs(clients) do client.online = false end
modernOne.online = true
modernOne.RosterSync.metadataFlushScheduled = nil -- the manual harness did not run After callbacks
local modernAuto, modernAutoRecord = newClient("ModernAuto-Realm", 8)
modernAuto.Guild.LoadedGuildRosterMember = modernAuto.Guild.originalLoadedGuildRosterMember
modernAuto.online = true
enableNetwork(modernOne, "ModernOne-Realm")
enableNetwork(modernAuto, "ModernAuto-Realm")
modernAuto.RosterSync.publisherCache = { [guildKey .. "|modernone-realm"] = { allowed = false, expires = now + 60 } }
override(modernOne, "LiveModernAlt", "alt", "LiveModernMain")
assign(modernOne, "LiveModernMain", "raider", "healer")
advance(3)
eq(modernAutoRecord.o[id(modernAuto, "LiveModernAlt")].main, id(modernAuto, "LiveModernMain"), "Automatic metadata uses modern rank before accepting chunks")
eq(modernAutoRecord.cfg.teams[1].ro[id(modernAuto, "LiveModernMain")].t, "raider", "Live team updates carry a validated member hint")
clubMembers[101].guildRankOrder = 9
override(modernOne, "DemotedModern", "guild")
advance(3)
eq(modernAutoRecord.o[id(modernAuto, "DemotedModern")], nil, "Current club demotion overrides previously accepted authority")
clubMembers[101].guildRankOrder = 2
modernAutoRecord.cfg.teams[1].ro = {}
modernAutoRecord.cfg.teams[1].rt = 0
modernAuto.RosterSync:RequestLatest(true)
advance(6)
eq(modernAutoRecord.cfg.teams[1].ro[id(modernAuto, "LiveModernMain")].t, "raider", "Automatic catch-up team snapshots verify modern member hints")
print("PASS: automatic main/alt, team updates and catch-up verify modern ranks without full roster scans")

-- Older versions have no ID hint. Resolve only the selected manual partner,
-- in batches, even when only CLUB_MEMBERS_UPDATED arrives and legacy stays empty.
messages, timers = {}, {}
C_Club.GetMemberInfoForSelf = function() return nil end
local searchOne, searchOneRecord = newClient("SearchOne-Realm", 1)
local searchThree, searchThreeRecord = newClient("SearchThree-Realm", 3)
local clubReady, enumerationCount = false, 0
local memberIDs = {}
for index = 1, 250 do
    memberIDs[index] = 1000 + index
    clubMembers[1000 + index] = { name = "Unrelated" .. index .. "-Realm", guildRankOrder = 9 }
end
clubMembers[1249] = { name = "SearchOne-Realm", guildRankOrder = 2 }
clubMembers[1250] = { name = "SearchThree-Realm", guildRankOrder = 4 }
C_Club.GetClubMembers = function()
    enumerationCount = enumerationCount + 1
    return clubReady and memberIDs or {}
end
for _, client in ipairs({ searchOne, searchThree }) do
    client.Guild.LoadedGuildRosterMember = client.Guild.originalLoadedGuildRosterMember
end
override(searchOne, "LegacyPeerAlt", "alt", "LegacyPeerMain")
override(searchThree, "LegacyOtherMain", "guild")
local focusedBefore = focusRequests
searchOne.DataSync:StartSync("SearchThree")
for _ = 1, 70 do
    manualStep()
    if searchOne.DataSync.outbound.rosterPending and searchThree.DataSync.inbound.rosterPending then break end
end
assert(searchOne.DataSync.outbound.rosterPending and searchThree.DataSync.inbound.rosterPending, "Unloaded modern membership is held")
eq(focusRequests - focusedBefore, 2, "Both manual participants request modern club membership")
clubReady = true
fire(searchOne, "CLUB_MEMBERS_UPDATED")
fire(searchThree, "CLUB_MEMBERS_UPDATED")
memberReads = 0
manualStep()
assert(memberReads <= 200, "Each pending partner search reads at most 100 members per tick")
eq(searchThreeRecord.o[id(searchThree, "LegacyPeerAlt")], nil, "Partial selected-member search cannot authorize data")
finishManual()
eq(searchThreeRecord.o[id(searchThree, "LegacyPeerAlt")].main, id(searchThree, "LegacyPeerMain"), "ID-less manual peer is found in modern cache")
eq(searchOne.DataSync.outbound.rosterSentAccepted, true, "Modern-only fallback returns a successful receipt")
eq(searchOneRecord.gr[id(searchOne, "Unrelated1")], nil, "Selected-member search never imports unrelated members")
local debugLines = {}
function searchOne:Print(message) debugLines[#debugLines + 1] = message end
searchOne.DataSync:PrintSyncDebug()
assert(table.concat(debugLines, " "):find("rank=3", 1, true), "Diagnostics report the actual resolved partner rank")
print("PASS: older peers resolve through bounded modern member searches and club events without legacy data")

-- A selected member can exist before its rank loads. Never turn missing rank
-- data into rank 0, and do not enumerate when the selected ID is already known.
messages, timers = {}, {}
C_Club.GetClubMembers = function() error("Known member must be queried directly") end
clubMembers[101].guildRankOrder = nil
local pendingModern = { guildKey = guildKey, target = "ModernOne" }
modernThree.DataSync.inbound = pendingModern
modernThree.DataSync:HandleGenericPayload(pendingModern, "V", modernOne.DataSync:BuildManifest(guildKey), "ModernOne")
assert(pendingModern.rosterPending, "A matched club member without rank data waits")
pendingModern.rosterPending.ticker.callback()
assert(pendingModern.rosterPending, "Missing club rank is never implicitly trusted")
clubMembers[101].guildRankOrder = 2
clubMembers[101].guid = "Player-1-ABC"
function GetPlayerInfoByGUID() error("GUID cache unavailable") end
fire(modernThree, "CLUB_MEMBER_UPDATED")
pendingModern.rosterPending.ticker.callback()
assert(pendingModern.rosterImported, "Club member update resumes pending sync using the known name and ID")
eq(pendingModern.rosterPending, nil, "Modern rank update stops the wait timer")
eq(modernThree.Guild:RosterMemberRank(guildKey, "ModernOne", 101), 1, "A valid member name does not depend on a GUID lookup")
print("PASS: partially loaded modern ranks resume on member events without scanning or trusting missing values")

-- A peer's opaque member ID may name another member in this client's view.
-- Its presence must not suppress the selected-player name search.
messages, timers, loadedRoster = {}, {}, {}
local localMapClient, localMapRecord = newClient("LocalMap-Realm", 3)
GetGuildRosterInfo = nil -- a member count alone does not prove the old row API exists
function GetNumGuildMembers() return 946 end
localMapClient.Guild.LoadedGuildRosterMember = localMapClient.Guild.originalLoadedGuildRosterMember
clubMembers[2] = { name = "LocalMap-Realm", guildRankOrder = 4 }
clubMembers[777] = { name = "ModernOne-Realm", guildRankOrder = 2 }
local localMemberIDs = { 2 }
for index = 2, 945 do localMemberIDs[index] = 2000 + index end
localMemberIDs[946] = 777
C_Club.GetClubMembers = function() return localMemberIDs end
local mismatchedPayload = modernOne.DataSync:BuildManifest(guildKey):gsub("publisherMemberID=101", "publisherMemberID=2")
local localMapSession = { guildKey = guildKey, target = "ModernOne" }
localMapClient.DataSync.inbound = localMapSession
localMapClient.DataSync:HandleGenericPayload(localMapSession, "V", mismatchedPayload, "ModernOne")
assert(localMapSession.rosterPending, "Mismatched advertised ID waits for local resolution")
for _ = 1, 10 do
    if not localMapSession.rosterPending then break end
    local readsBefore = memberReads
    localMapSession.rosterPending.ticker.callback()
    assert(memberReads - readsBefore <= 102, "A 946-member guild is searched in bounded batches")
end
assert(localMapSession.rosterImported, "A mismatched advertised ID cannot prevent local name resolution")
eq(localMapClient.Guild.clubMemberIDs[guildKey .. "|modernone-realm"], 777, "Only locally verified member ID is remembered")
eq(localMapClient.Guild:RosterMemberRank(guildKey, "ModernOne", 2), 1, "Repeated packets prefer the verified local ID over the peer hint")
clubMembers[777].guildRankOrder = 9
eq(localMapClient.Guild:CanAcceptRosterPublisher(guildKey, "ModernOne", 2), false, "Demotion is checked on the resolved local member")
print("PASS: differing member IDs on two clients fall back to local identity without granting false authority")
