local _, LV = ...

LV.RosterSync = {}
LV.modules.RosterSync = LV.RosterSync

local ROSTER_KINDS = {
    LRQ = true,
    LRS = true,
    LRP = true,
    LRE = true,
    LRU = true,
    LRM = true,
}

local SNAPSHOT_ELECTION_DELAY = 1.5
local ROSTER_TAGS = { guild = true, alt = true, pug = true }
local ROSTER_TYPES = { raider = true, trial = true, helper = true, social = true }

local function newerRevision(revision, author, currentRevision, currentAuthor)
    revision, currentRevision = tonumber(revision) or 0, tonumber(currentRevision) or 0
    if revision ~= currentRevision then
        return revision > currentRevision
    end
    -- Stable ties make simultaneous edits converge in either sync direction.
    return tostring(author or ""):lower() < tostring(currentAuthor or ""):lower()
end

function LV.RosterSync:BuildSyncSnapshot(guildKey, selection)
    local actual = LV.Guild:ActualInfo()
    local snapshot = { version = 1, teams = {}, overrides = {}, members = {} }
    snapshot.publisher = false
    if actual and actual.key == guildKey then
        snapshot.publisher, snapshot.reason = LV.Guild:CanPublishRoster()
    end
    if not snapshot.publisher then
        return snapshot
    end
    snapshot.memberID = LV.Guild:OwnClubMemberID()
    local record = LV.Store:GuildRecord(guildKey)
    local function name(id)
        return record.d.n[tonumber(id)] or ""
    end
    for _, team in ipairs(not selection and record.cfg.teams or {}) do
        if not team.excludeSync and not LV.Store:IsGlobalPugTeam(team) and (tonumber(team.rt) or 0) > 0 then
            local rows = {}
            for nameID, assignment in pairs(team.ro or {}) do
                local fullName = name(nameID)
                if fullName ~= "" then
                    local id = tonumber(nameID)
                    local className = record.d.s[record.pc[id]] or (record.gr[id] and record.gr[id].c)
                    rows[#rows + 1] = { n = fullName, t = assignment.t, p = assignment.p,
                        s = assignment.s, c = className }
                end
            end
            table.sort(rows, function(a, b) return a.n < b.n end)
            local author = name(team.rby)
            snapshot.teams[#snapshot.teams + 1] = { id = team.id, name = team.name,
                rt = team.rt, by = author ~= "" and author or LV.Util:PlayerFullName(), rows = rows }
        end
    end
    for nameID in pairs(selection and selection.overrides or record.o or {}) do
        local override = record.o[nameID]
        if override and ROSTER_TAGS[override.tag] and (tonumber(override.ts) or 0) > 0 and name(nameID) ~= "" then
            snapshot.overrides[#snapshot.overrides + 1] = { n = name(nameID), tag = override.tag,
                main = name(override.main), ts = override.ts, by = name(override.by) }
        end
    end
    for nameID in pairs(selection and selection.members or record.gr or {}) do
        local entry = record.gr[nameID]
        if entry and name(nameID) ~= "" then
            snapshot.members[#snapshot.members + 1] = { n = name(nameID), c = entry.c,
                r = entry.r, rn = entry.rn, rt = entry.rts or entry.ts or 0 }
        end
    end
    table.sort(snapshot.overrides, function(a, b) return a.n < b.n end)
    table.sort(snapshot.members, function(a, b) return a.n < b.n end)
    return snapshot
end

function LV.RosterSync:ApplySyncSnapshot(guildKey, sender, snapshot)
    local counts = { teams = 0, links = 0, members = 0 }
    if not snapshot or snapshot.version ~= 1 then
        return nil, "Partner must update LootViewer to sync roster changes."
    end
    -- Recheck authority once per complete transfer, before importing ranks.
    if not snapshot.publisher then
        return nil, "Not sent: " .. (snapshot.reason or "partner's publishing check declined")
    end
    local allowed, reason, reasonCode = LV.Guild:CanAcceptRosterPublisher(guildKey, sender, snapshot.memberID)
    if not allowed then
        return nil, "Not accepted: " .. (reason or "publisher could not be verified"), reasonCode
    end
    local record = LV.Store:GuildRecord(guildKey)
    for _, incoming in ipairs(snapshot.teams or {}) do
        local team = LV.Store:GetTeamByID(record, incoming.id)
        local revision = tonumber(incoming.rt) or 0
        local author = LV.Util:Trim(incoming.by)
        local oldAuthor = team and LV.Store:DictionaryValue(guildKey, "n", team.rby) or ""
        if oldAuthor == "" then oldAuthor = LV.Util:PlayerFullName() end
        local seen, valid = {}, revision > 0 and incoming.id and incoming.id ~= ""
            and not LV.Store:IsGlobalPugTeam(incoming.id)
            and type(incoming.rows) == "table" and #incoming.rows == tonumber(incoming.count)
        for _, row in ipairs(incoming.rows or {}) do
            local key = LV.Util:Trim(row.n):lower()
            if key == "" or seen[key] or not ROSTER_TYPES[row.t] then valid = false end
            seen[key] = true
        end
        if valid and (not team or not team.excludeSync)
            and (not team or newerRevision(revision, author, team.rt, oldAuthor)) then
            if not team then
                team = { id = incoming.id, name = incoming.name, ro = {}, schedules = {} }
                record.cfg.teams[#record.cfg.teams + 1] = team
            end
            -- Replace the complete team, including removals and an empty roster.
            local roster = LV.Store:TeamRoster(guildKey, team.id)
            wipe(roster)
            for _, row in ipairs(incoming.rows) do
                local nameID = LV.Store:NameID(guildKey, row.n)
                LV.Store:SetTeamRosterPlayer(guildKey, team.id, nameID, row.t, row.p, row.s)
                if row.c and row.c ~= "" then LV.Store:SetPlayerClass(guildKey, nameID, row.c) end
            end
            team.rt, team.rby = revision, LV.Store:NameID(guildKey, author ~= "" and author or sender)
            counts.teams = counts.teams + 1
        end
    end
    for _, row in ipairs(snapshot.overrides or {}) do
        local fullName, mainName = LV.Util:Trim(row.n), LV.Util:Trim(row.main)
        if fullName ~= "" and ROSTER_TAGS[row.tag] and (tonumber(row.ts) or 0) > 0
            and (row.tag ~= "alt" or (mainName ~= "" and mainName:lower() ~= fullName:lower())) then
            local nameID = LV.Store:NameID(guildKey, fullName)
            local current = record.o[nameID]
            local oldAuthor = current and LV.Store:DictionaryValue(guildKey, "n", current.by) or ""
            if not current or newerRevision(row.ts, row.by, current.ts, oldAuthor) then
                record.o[nameID] = { tag = row.tag,
                    main = row.tag == "alt" and LV.Store:NameID(guildKey, mainName) or nil,
                    ts = tonumber(row.ts), by = LV.Store:NameID(guildKey, row.by) }
                counts.links = counts.links + 1
            end
        end
    end
    for _, row in ipairs(snapshot.members or {}) do
        local fullName = LV.Util:Trim(row.n)
        if fullName ~= "" then
            local nameID = LV.Store:NameID(guildKey, fullName)
            local entry = record.gr[nameID]
            local changed = not entry
            if not entry then
                entry = {}
                record.gr[nameID] = entry
            end
            local rank, revision = tonumber(row.r), tonumber(row.rt) or 0
            local oldRevision = tonumber(entry.rts or entry.ts) or 0
            if rank and rank >= 0 and rank == math.floor(rank) and revision > 0
                and (entry.r == nil or newerRevision(revision, tostring(rank) .. (row.rn or ""),
                    oldRevision, tostring(entry.r) .. (entry.rn or ""))) then
                changed = changed or entry.r ~= rank or entry.rn ~= row.rn
                entry.r, entry.rn, entry.rts = rank, row.rn, revision
            end
            if (not entry.c or entry.c == "") and row.c and row.c ~= "" then
                entry.c = row.c
                LV.Store:SetPlayerClass(guildKey, nameID, row.c)
                changed = true
            end
            if changed then counts.members = counts.members + 1 end
        end
    end
    if counts.links > 0 and LV.Raid and LV.Raid.ReconcileGuildLinkedAttendance then
        LV.Raid:ReconcileGuildLinkedAttendance(guildKey)
    end
    return counts, string.format("Roster synced: %d teams, %d main/alt tags, %d members updated.",
        counts.teams, counts.links, counts.members)
end

local function normalizedSender(sender)
    return LV.Guild:NormalizeMemberName(sender)
end

function LV.RosterSync:IsRosterKind(kind)
    return ROSTER_KINDS[kind] and true or false
end

function LV.RosterSync:BumpTeamRevision(team)
    local now = LV.Util:ServerNow()
    team.rt = math.max(now, (tonumber(team.rt) or 0) + 1)
    return team.rt
end

function LV.RosterSync:RequestLatest(force, metadataAttempt)
    local actual = LV.Guild:ActualInfo()
    if not actual or type(IsInGuild) ~= "function" or not IsInGuild() then
        return false
    end
    local now = LV.Util:Now()
    if not force and now - (tonumber(self.lastRequestAt) or 0) < 15 then
        return false
    end
    self.lastRequestAt = now
    self.requestSerial = (tonumber(self.requestSerial) or 0) + 1
    local nonce = tostring(LV.Util:ServerNow()) .. "-" .. tostring(self.requestSerial)
    self.metadataRequests = self.metadataRequests or {}
    for token, request in pairs(self.metadataRequests) do
        if request.expires <= now then self.metadataRequests[token] = nil end
    end
    self.metadataRequests[nonce] = { guildKey = actual.key, expires = now + 600, attempt = metadataAttempt or 0 }
    return LV.Comms:SendMessage("LRQ", { actual.key, nonce, 1 }, "GUILD")
end

function LV.RosterSync:QueueMetadataUpdate(guildKey, nameID, kind)
    self.metadataPending = self.metadataPending or {}
    local pending = self.metadataPending[guildKey]
    if not pending then
        pending = { overrides = {}, members = {} }
        self.metadataPending[guildKey] = pending
    end
    pending[kind][nameID] = true
    if self.metadataFlushScheduled or not C_Timer or not C_Timer.After then return end
    self.metadataFlushScheduled = true
    C_Timer.After(0.5, function()
        self.metadataFlushScheduled = false
        local batches = self.metadataPending
        self.metadataPending = {}
        for key, selection in pairs(batches) do
            local snapshot = self:BuildSyncSnapshot(key, selection)
            if snapshot.publisher then
                self.metadataSerial = (self.metadataSerial or 0) + 1
                local token = "u" .. tostring(LV.Util:ServerNow()) .. "-" .. tostring(self.metadataSerial)
                self:SendMetadata(key, token, snapshot)
            end
        end
    end)
end

function LV.RosterSync:SendMetadata(guildKey, token, snapshot, target, delay)
    if not snapshot.publisher or not C_Timer or not C_Timer.After then return false end
    local payload = LV.DataSync:EncodeRosterSnapshot(guildKey, snapshot)
    -- Account for the complete addon-message envelope, including long guild
    -- names. Chunk bytes rather than truncating names or UTF-8 rank labels.
    local hint = snapshot.memberID and ("pm:" .. tostring(snapshot.memberID)) or ""
    local header = table.concat({ "LRM", guildKey, token, "2048", "2048", "", hint }, "\031")
    local chunkSize = math.min(180, 255 - #header)
    if chunkSize < 1 then return false end
    local total = math.ceil(#payload / chunkSize)
    if total > 2048 then return false end
    local channel = target and "WHISPER" or "GUILD"
    for sequence = 1, total do
        local chunk = payload:sub((sequence - 1) * chunkSize + 1, sequence * chunkSize)
        local packet = { guildKey, token, sequence, total, chunk, hint }
        C_Timer.After((delay or 0) + (sequence - 1) * 0.10, function()
            local actual = LV.Guild:ActualInfo()
            if actual and actual.key == guildKey then
                LV.Comms:SendMessage("LRM", packet, channel, target)
            end
        end)
    end
    return true
end

function LV.RosterSync:ReceiveMetadata(parts, sender, channel)
    local guildKey, token = parts[2], parts[3]
    local sequence, total = tonumber(parts[4]), tonumber(parts[5])
    if not token or token == "" or not sequence or not total or total < 1 or total > 2048
        or sequence < 1 or sequence > total or sequence ~= math.floor(sequence) or total ~= math.floor(total)
        or type(parts[6]) ~= "string" or #parts[6] > 180 then return end
    local now = LV.Util:Now()
    local request = self.metadataRequests and self.metadataRequests[token]
    if channel == "WHISPER" then
        if not request or request.guildKey ~= guildKey or request.expires <= now then return end
    elseif channel ~= "GUILD" or token:sub(1, 1) ~= "u" then
        return
    end
    local key = guildKey .. "|" .. normalizedSender(sender):lower() .. "|" .. token
    self.metadataIncoming = self.metadataIncoming or {}
    self.metadataCompleted = self.metadataCompleted or {}
    for completedKey, expires in pairs(self.metadataCompleted) do
        if expires <= now then self.metadataCompleted[completedKey] = nil end
    end
    if self.metadataCompleted[key] then return end
    local stage = self.metadataIncoming[key]
    if not stage then
        stage = { total = total, chunks = {}, received = 0 }
        self.metadataIncoming[key] = stage
        if C_Timer and C_Timer.After then
            C_Timer.After(math.max(20, total * 0.10 + 15), function()
                if self.metadataIncoming[key] ~= stage then return end
                self.metadataIncoming[key] = nil
                local actual = LV.Guild:ActualInfo()
                local attempt = request and request.attempt or 0
                if actual and actual.key == guildKey and attempt < 2 and not self.metadataRetryScheduled then
                    self.metadataRetryScheduled = true
                    C_Timer.After(5, function()
                        self.metadataRetryScheduled = false
                        if LV.Guild:ActualInfo() and LV.Guild:ActualInfo().key == guildKey then
                            self:RequestLatest(true, attempt + 1)
                        end
                    end)
                end
            end)
        end
    end
    if stage.total ~= total then return end
    if not stage.chunks[sequence] then
        stage.chunks[sequence] = parts[6]
        stage.received = stage.received + 1
    end
    if stage.received ~= total then return end
    self.metadataIncoming[key] = nil
    self.metadataCompleted[key] = now + 600
    local manifest = LV.DataSync:ParseManifest(table.concat(stage.chunks))
    if manifest.guildKey ~= guildKey then return end
    -- The existing automatic protocol owns team snapshots; these packets
    -- only merge player metadata and never import raid history or settings.
    manifest.roster.teams = {}
    local counts = self:ApplySyncSnapshot(guildKey, sender, manifest.roster)
    if counts and (counts.links > 0 or counts.members > 0) and LV.UI and LV.UI.Refresh then
        LV.UI:Refresh()
    end
end

function LV.RosterSync:QueueWhisper(kind, target, payload, delay)
    local memberID = LV.Guild:OwnClubMemberID()
    payload[#payload + 1] = memberID and ("pm:" .. tostring(memberID)) or ""
    local send = function()
        LV.Comms:SendWhisper(kind, target, payload)
    end
    if C_Timer and C_Timer.After and (tonumber(delay) or 0) > 0 then
        C_Timer.After(delay, send)
    else
        send()
    end
end

function LV.RosterSync:ScheduleRetry()
    if self.retryScheduled then
        return
    end
    self.retryScheduled = true
    local retry = function()
        self.retryScheduled = false
        self:RequestLatest(true)
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(5, retry)
    else
        retry()
    end
end

function LV.RosterSync:SendSnapshot(target, guildKey, nonce, includeMetadata)
    local record = LV.Store:GuildRecord(guildKey)
    if not record then
        return false
    end
    local snapshots = {}
    for _, team in ipairs((record.cfg and record.cfg.teams) or {}) do
        local roster = type(team.ro) == "table" and team.ro or {}
        local rows = {}
        for rawNameID, assignment in pairs(roster) do
            local nameID = tonumber(rawNameID)
            local fullName = nameID and LV.Store:DictionaryValue(guildKey, "n", nameID) or ""
            if fullName ~= "" and type(assignment) == "table" then
                rows[#rows + 1] = {
                    fullName = fullName,
                    rosterType = assignment.t or "raider",
                    primaryRole = assignment.p or "",
                    secondaryRole = assignment.s or "",
                    className = LV.Store:PlayerClass(guildKey, nameID),
                }
            end
        end
        table.sort(rows, function(a, b) return a.fullName:lower() < b.fullName:lower() end)
        local revision = tonumber(team.rt)
        -- A fresh or migrated client has no authoritative roster revision.
        -- It must not claim a current timestamp merely because someone asked
        -- for a snapshot; the first real roster edit establishes its revision.
        if revision and revision > 0 then
            snapshots[#snapshots + 1] = {
                teamID = team.id,
                revision = revision,
                rows = rows,
            }
        end
    end

    -- Advertise every team first so requesters can elect a winner before the
    -- larger player payloads make different publishers finish out of order.
    local delay = 0
    for _, snapshot in ipairs(snapshots) do
        self:QueueWhisper("LRS", target,
            { guildKey, nonce, snapshot.teamID, snapshot.revision, #snapshot.rows }, delay)
        delay = delay + 0.10
    end
    for _, snapshot in ipairs(snapshots) do
        for _, row in ipairs(snapshot.rows) do
            self:QueueWhisper("LRP", target, {
                guildKey, nonce, snapshot.teamID, snapshot.revision, row.fullName, row.rosterType,
                row.primaryRole, row.secondaryRole, row.className,
            }, delay)
            delay = delay + 0.10
        end
        self:QueueWhisper("LRE", target,
            { guildKey, nonce, snapshot.teamID, snapshot.revision }, delay)
        delay = delay + 0.10
    end
    if includeMetadata then
        local selection = { overrides = record.o, members = record.gr }
        self:SendMetadata(guildKey, nonce, self:BuildSyncSnapshot(guildKey, selection), target, delay)
    end
    return true
end

function LV.RosterSync:PublishPlayer(guildKey, teamID, nameID, assignment, removed)
    local actual = LV.Guild:ActualInfo()
    if not actual or actual.key ~= guildKey or not LV.Guild:CanPublishRoster() then
        return false
    end
    local record = LV.Store:GuildRecord(guildKey)
    local team = record and LV.Store:GetTeamByID(record, teamID)
    local fullName = LV.Store:DictionaryValue(guildKey, "n", nameID)
    if not team or fullName == "" then
        return false
    end
    local revision = self:BumpTeamRevision(team)
    team.rby = LV.Store:NameID(guildKey, LV.Util:PlayerFullName())
    assignment = type(assignment) == "table" and assignment or {}
    local memberID = LV.Guild:OwnClubMemberID()
    return LV.Comms:SendMessage("LRU", {
        guildKey,
        teamID,
        revision,
        fullName,
        removed and 1 or 0,
        assignment.t or "",
        assignment.p or "",
        assignment.s or "",
        LV.Store:PlayerClass(guildKey, nameID),
        memberID and ("pm:" .. tostring(memberID)) or "",
    }, "GUILD")
end

function LV.RosterSync:CanAccept(sender, guildKey, memberID)
    sender = normalizedSender(sender)
    if sender == "" then
        return false
    end
    self.publisherCache = self.publisherCache or {}
    local key = guildKey .. "|" .. sender:lower()
    local cached = self.publisherCache[key]
    local now = LV.Util:Now()
    if not memberID and cached and now < cached.expires then
        return cached.allowed
    end
    local allowed = LV.Guild:CanAcceptRosterPublisher(guildKey, sender, memberID)
    self.publisherCache[key] = { allowed = allowed, expires = now + 60 }
    return allowed
end

local function betterSnapshotCandidate(left, right)
    if not right then
        return true
    elseif left.revision ~= right.revision then
        return left.revision > right.revision
    elseif left.rankIndex ~= right.rankIndex then
        return left.rankIndex < right.rankIndex
    end
    return left.senderKey < right.senderKey
end

function LV.RosterSync:FinishSnapshotElection(electionKey)
    local election = self.snapshotElections and self.snapshotElections[electionKey]
    if not election or not election.winnerStageKey then
        return false
    end
    local stage = self.inbound and self.inbound[election.winnerStageKey]
    if not stage or not stage.complete then
        return false
    end

    for _, candidate in pairs(election.candidates) do
        self.inbound[candidate.stageKey] = nil
    end
    self.snapshotElections[electionKey] = nil
    return self:ApplySnapshot(stage.sender, stage)
end

function LV.RosterSync:ResolveSnapshotElection(electionKey)
    local election = self.snapshotElections and self.snapshotElections[electionKey]
    if not election or election.resolved then
        return false
    end

    local winner
    for _, candidate in pairs(election.candidates) do
        if betterSnapshotCandidate(candidate, winner) then
            winner = candidate
        end
    end
    election.resolved = true
    election.winnerStageKey = winner and winner.stageKey or nil
    if not winner then
        self.snapshotElections[electionKey] = nil
        return false
    end

    for _, candidate in pairs(election.candidates) do
        if candidate.stageKey ~= winner.stageKey then
            self.inbound[candidate.stageKey] = nil
        end
    end
    return self:FinishSnapshotElection(electionKey)
end

function LV.RosterSync:ConsiderSnapshotCandidate(sender, nonce, teamID, stageKey, stage)
    self.snapshotElections = self.snapshotElections or {}
    local electionKey = tostring(nonce) .. "|" .. tostring(teamID)
    local election = self.snapshotElections[electionKey]
    if not election then
        election = { candidates = {} }
        self.snapshotElections[electionKey] = election
    elseif election.resolved then
        return electionKey, false
    end

    local fullName = normalizedSender(sender)
    local senderKey = fullName:lower()
    election.candidates[senderKey] = {
        senderKey = senderKey,
        stageKey = stageKey,
        revision = stage.revision,
        rankIndex = tonumber(LV.Guild:RosterMemberRank(stage.guildKey, fullName)) or 999,
    }
    if not election.scheduled then
        election.scheduled = true
        if C_Timer and C_Timer.After then
            C_Timer.After(SNAPSHOT_ELECTION_DELAY, function()
                LV.RosterSync:ResolveSnapshotElection(electionKey)
            end)
        else
            self:ResolveSnapshotElection(electionKey)
        end
    end
    return electionKey, true
end

function LV.RosterSync:ApplySnapshot(sender, stage)
    local record = LV.Store:GuildRecord(stage.guildKey)
    local roster, team = LV.Store:TeamRoster(stage.guildKey, stage.teamID)
    if not record or not roster or not team or stage.revision < (tonumber(team.rt) or 0)
        or #stage.rows ~= stage.expected then
        return false
    end
    wipe(roster)
    for _, row in ipairs(stage.rows) do
        local nameID = LV.Store:NameID(stage.guildKey, row.fullName)
        if nameID then
            if row.className ~= "" then
                LV.Store:SetPlayerClass(stage.guildKey, nameID, row.className)
            end
            LV.Store:SetTeamRosterPlayer(stage.guildKey, stage.teamID, nameID,
                row.rosterType, row.primaryRole, row.secondaryRole)
        end
    end
    team.rt = stage.revision
    team.rby = LV.Store:NameID(stage.guildKey, normalizedSender(sender))
    self.lastRosterReceivedAt = LV.Util:Now()
    if LV.UI and LV.UI.Refresh then
        LV.UI:Refresh()
    end
    return true
end

function LV.RosterSync:HandleMessage(parts, sender, channel)
    local kind = parts[1]
    local guildKey = parts[2]
    local actual = LV.Guild:ActualInfo()
    if not actual or guildKey ~= actual.key then
        return
    end
    if normalizedSender(sender):lower() == LV.Util:PlayerFullName():lower() then return end

    if kind == "LRQ" then
        local nonce = parts[3]
        if channel == "GUILD" and nonce and nonce ~= "" and LV.Guild:CanPublishRoster() then
            self:SendSnapshot(sender, guildKey, nonce, tonumber(parts[4]) == 1)
        end
        return
    end

    local hint = tostring(parts[#parts] or ""):match("^pm:(.+)$")
    if not self:CanAccept(sender, guildKey, tonumber(hint)) then
        return
    end

    if kind == "LRM" then
        self:ReceiveMetadata(parts, sender, channel)
    elseif kind == "LRS" then
        local nonce, teamID = parts[3], parts[4]
        local revision, expected = tonumber(parts[5]), tonumber(parts[6])
        local record = LV.Store:GuildRecord(guildKey)
        if nonce and teamID and revision and expected and expected >= 0 and expected <= 500
            and LV.Store:GetTeamByID(record, teamID) then
            self.inbound = self.inbound or {}
            local key = normalizedSender(sender):lower() .. "|" .. nonce .. "|" .. teamID
            self.inbound[key] = {
                guildKey = guildKey,
                teamID = teamID,
                revision = revision,
                expected = expected,
                rows = {},
                sender = normalizedSender(sender),
            }
            local stage = self.inbound[key]
            local accepted
            stage.electionKey, accepted = self:ConsiderSnapshotCandidate(sender, nonce, teamID, key, stage)
            if not accepted then
                self.inbound[key] = nil
            elseif C_Timer and C_Timer.After then
                local timeout = math.max(20, (expected * 0.10) + 10)
                C_Timer.After(timeout, function()
                    if self.inbound and self.inbound[key] == stage then
                        self.inbound[key] = nil
                        local election = self.snapshotElections and self.snapshotElections[stage.electionKey]
                        if election and election.winnerStageKey == key then
                            self.snapshotElections[stage.electionKey] = nil
                        end
                        self:ScheduleRetry()
                    end
                end)
            end
        end
    elseif kind == "LRP" then
        local nonce, teamID = parts[3], parts[4]
        local key = normalizedSender(sender):lower() .. "|" .. tostring(nonce or "") .. "|" .. tostring(teamID or "")
        local stage = self.inbound and self.inbound[key]
        if stage and tonumber(parts[5]) == stage.revision and #stage.rows < stage.expected then
            stage.rows[#stage.rows + 1] = {
                fullName = LV.Util:Trim(parts[6]),
                rosterType = LV.Util:Trim(parts[7]),
                primaryRole = LV.Util:Trim(parts[8]),
                secondaryRole = LV.Util:Trim(parts[9]),
                className = LV.Util:Trim(parts[10]),
            }
        end
    elseif kind == "LRE" then
        local nonce, teamID = parts[3], parts[4]
        local key = normalizedSender(sender):lower() .. "|" .. tostring(nonce or "") .. "|" .. tostring(teamID or "")
        local stage = self.inbound and self.inbound[key]
        if stage and tonumber(parts[5]) == stage.revision then
            stage.complete = #stage.rows == stage.expected
            local election = self.snapshotElections and self.snapshotElections[stage.electionKey]
            if stage.complete and election and election.resolved and election.winnerStageKey == key then
                self:FinishSnapshotElection(stage.electionKey)
            elseif not stage.complete then
                self:ScheduleRetry()
            end
        end
    elseif kind == "LRU" then
        local teamID, revision = parts[3], tonumber(parts[4])
        local fullName, removed = LV.Util:Trim(parts[5]), tonumber(parts[6]) == 1
        local record = LV.Store:GuildRecord(guildKey)
        local roster, team = LV.Store:TeamRoster(guildKey, teamID)
        if roster and team and revision and revision >= (tonumber(team.rt) or 0) and fullName ~= "" then
            local nameID = LV.Store:NameID(guildKey, fullName)
            if removed then
                roster[nameID] = nil
            else
                local className = LV.Util:Trim(parts[10])
                if className ~= "" then
                    LV.Store:SetPlayerClass(guildKey, nameID, className)
                end
                LV.Store:SetTeamRosterPlayer(guildKey, teamID, nameID,
                    parts[7], parts[8], parts[9])
            end
            team.rt = revision
            team.rby = LV.Store:NameID(guildKey, normalizedSender(sender))
            self.lastRosterReceivedAt = LV.Util:Now()
            if LV.UI and LV.UI.Refresh then
                LV.UI:Refresh()
            end
        end
    end
end

local function requestRosterSoon()
    if LV.RosterSync.requestScheduled then
        return
    end
    LV.RosterSync.requestScheduled = true
    if C_Timer and C_Timer.After then
        C_Timer.After(5, function()
            LV.RosterSync.requestScheduled = false
            LV.RosterSync:RequestLatest(false)
        end)
    else
        LV.RosterSync.requestScheduled = false
        LV.RosterSync:RequestLatest(false)
    end
end

LV:RegisterEvent("PLAYER_ENTERING_WORLD", requestRosterSoon)
LV:RegisterEvent("PLAYER_GUILD_UPDATE", requestRosterSoon)
LV:RegisterEvent("GROUP_ROSTER_UPDATE", function()
    local inRaid = type(IsInRaid) == "function" and IsInRaid() or false
    if inRaid and not LV.RosterSync.wasInRaid then requestRosterSoon() end
    LV.RosterSync.wasInRaid = inRaid
end)
LV:RegisterEvent("GUILD_ROSTER_UPDATE", function()
    if LV.RosterSync.publisherCache then
        wipe(LV.RosterSync.publisherCache)
    end
    if not LV.RosterSync.lastRosterReceivedAt then
        requestRosterSoon()
    end
end)
