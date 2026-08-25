local _, LV = ...

LV.RosterSync = {}
LV.modules.RosterSync = LV.RosterSync

local ROSTER_KINDS = {
    LRQ = true,
    LRS = true,
    LRP = true,
    LRE = true,
    LRU = true,
}

local function normalizedSender(sender)
    sender = LV.Util:Trim(sender)
    if sender ~= "" and not sender:find("-", 1, true) then
        local actual = LV.Guild:ActualInfo()
        sender = sender .. "-" .. ((actual and actual.realm) or LV.Util:RealmName())
    end
    return sender
end

function LV.RosterSync:IsRosterKind(kind)
    return ROSTER_KINDS[kind] and true or false
end

function LV.RosterSync:BumpTeamRevision(team)
    local now = LV.Util:ServerNow()
    team.rt = math.max(now, (tonumber(team.rt) or 0) + 1)
    return team.rt
end

function LV.RosterSync:RequestLatest(force)
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
    return LV.Comms:SendMessage("LRQ", { actual.key, nonce }, "GUILD")
end

function LV.RosterSync:QueueWhisper(kind, target, payload, delay)
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

function LV.RosterSync:SendSnapshot(target, guildKey, nonce)
    local record = LV.Store:GuildRecord(guildKey)
    if not record then
        return false
    end
    local delay = 0
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
        if not revision or revision <= 0 then
            revision = LV.Util:ServerNow()
            team.rt = revision
        end
        self:QueueWhisper("LRS", target,
            { guildKey, nonce, team.id, revision, #rows }, delay)
        delay = delay + 0.10
        for _, row in ipairs(rows) do
            self:QueueWhisper("LRP", target, {
                guildKey, nonce, team.id, revision, row.fullName, row.rosterType,
                row.primaryRole, row.secondaryRole, row.className,
            }, delay)
            delay = delay + 0.10
        end
        self:QueueWhisper("LRE", target, { guildKey, nonce, team.id, revision }, delay)
        delay = delay + 0.10
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
    assignment = type(assignment) == "table" and assignment or {}
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
    }, "GUILD")
end

function LV.RosterSync:CanAccept(sender, guildKey)
    sender = normalizedSender(sender)
    if sender == "" then
        return false
    end
    self.publisherCache = self.publisherCache or {}
    local key = guildKey .. "|" .. sender:lower()
    local cached = self.publisherCache[key]
    local now = LV.Util:Now()
    if cached and now < cached.expires then
        return cached.allowed
    end
    local allowed = LV.Guild:CanAcceptRosterPublisher(guildKey, sender)
    self.publisherCache[key] = { allowed = allowed, expires = now + 60 }
    return allowed
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

    if kind == "LRQ" then
        local nonce = parts[3]
        if channel == "GUILD" and nonce and nonce ~= "" and LV.Guild:CanPublishRoster() then
            self:SendSnapshot(sender, guildKey, nonce)
        end
        return
    end

    if not self:CanAccept(sender, guildKey) then
        return
    end

    if kind == "LRS" then
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
            }
            local stage = self.inbound[key]
            if C_Timer and C_Timer.After then
                C_Timer.After(20, function()
                    if self.inbound and self.inbound[key] == stage then
                        self.inbound[key] = nil
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
            self.inbound[key] = nil
            if not self:ApplySnapshot(sender, stage) and #stage.rows ~= stage.expected then
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
LV:RegisterEvent("GUILD_ROSTER_UPDATE", function()
    if LV.RosterSync.publisherCache then
        wipe(LV.RosterSync.publisherCache)
    end
    if not LV.RosterSync.lastRosterReceivedAt then
        requestRosterSoon()
    end
end)
