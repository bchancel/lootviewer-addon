local _, LV = ...

LV.Raid = {}
LV.modules.Raid = LV.Raid

LV.Raid.prompted = {}
LV.Raid.latePrompted = {}
LV.Raid.adHocTimers = {}
LV.Raid.scheduledEndTimers = {}
LV.Raid.autoPugSignature = nil
LV.Raid.autoStartElections = {}
LV.Raid.remoteRaidLoggers = {}

local AUTO_START_ELECTION_SECONDS = 2
local REMOTE_LOGGER_FRESH_SECONDS = 10
local ROSTER_INVITE_DELAY = 0.50

local rosterInviteTypeRank = {
    raider = 1,
    trial = 2,
    helper = 3,
    social = 4,
}

local rosterInviteFilterRank = {
    raiders = 1,
    trials = 2,
    helpers = 3,
    all = 4,
}

local function listKeys(map)
    local out = {}
    for id, _ in pairs(map or {}) do
        out[#out + 1] = tonumber(id) or id
    end
    table.sort(out)
    return out
end

local function unitFullName(unit)
    if not UnitExists(unit) then
        return nil
    end
    return LV.Util:UnitFullName(unit)
end

local function isGuildRaidGroup()
    if not IsInRaid() then
        return false
    end
    if type(UnitIsInMyGuild) == "function" then
        local total = tonumber(GetNumGroupMembers()) or 0
        local guildMembers = 0
        for index = 1, total do
            local unit = "raid" .. tostring(index)
            if UnitExists(unit) and UnitIsInMyGuild(unit) then
                guildMembers = guildMembers + 1
            end
        end
        return total > 0 and guildMembers * 2 > total
    end
    if type(InGuildParty) == "function" then
        local ok, inGuildParty = pcall(InGuildParty)
        return ok and inGuildParty and true or false
    end
    return true
end

local function loggerSignature(guildKey, instanceID, difficultyID)
    return table.concat({ tostring(guildKey or ""), tostring(instanceID or 0), tostring(difficultyID or 0) }, ":")
end

local function isLFRWorldTier(instance)
    local difficultyID = tonumber(instance and instance.difficultyID) or 0
    local difficultyName = tostring(instance and instance.difficultyName or ""):lower()
    return difficultyID == 17 or difficultyID == 250
        or difficultyName == "world"
        or difficultyName:find("raid finder", 1, true) ~= nil
        or difficultyName:find("lfr", 1, true) ~= nil
end

local function teamWeekMinute(team)
    return LV.Util:TimezoneWeekMinute(team and team.tz or "realm", LV.Util:ServerNow())
end

local function inWeeklyWindow(nowMinute, startMinute, beforeMinutes, durationMinutes, afterMinutes)
    local weekMinutes = 7 * 24 * 60
    for offset = -weekMinutes, weekMinutes, weekMinutes do
        local start = startMinute + offset
        if nowMinute >= start - beforeMinutes and nowMinute <= start + durationMinutes + afterMinutes then
            return true, start
        end
    end
    return false, nil
end

local function scheduledServerTimestamp(startMinute, currentMinute)
    startMinute = tonumber(startMinute)
    currentMinute = tonumber(currentMinute)
    if not startMinute or not currentMinute then
        return nil
    end

    local serverNow = LV.Util:ServerNow()
    return serverNow - (serverNow % 60) + ((startMinute - currentMinute) * 60)
end

local function normalizeAdHocHours(hours)
    hours = tonumber(hours) or 3
    if hours < 0.25 then
        hours = 0.25
    elseif hours > 12 then
        hours = 12
    end
    return hours
end

local function refreshRosterUI()
    if LV.UI and LV.UI.frame and LV.UI.frame:IsShown() and LV.UI.currentTab == "roster" then
        LV.UI:Refresh()
    end
end

function LV.Raid:RaidInviteWindow(team)
    if type(team) ~= "table" then
        return nil
    end
    local currentMinute = teamWeekMinute(team)
    for slotIndex, slot in ipairs(team.schedules or {}) do
        local weekday = tonumber(slot.w)
        local hour = tonumber(slot.h) or 20
        local minute = tonumber(slot.m) or 0
        local duration = tonumber(slot.d) or 180
        if weekday then
            local startMinute = ((weekday - 1) * 24 * 60) + (hour * 60) + minute
            local active, matchedStart = inWeeklyWindow(currentMinute, startMinute, 30, duration, 0)
            if active then
                return {
                    slotIndex = slotIndex,
                    startMinute = matchedStart,
                    endMinute = matchedStart + duration,
                    currentMinute = currentMinute,
                    scheduledStartAt = scheduledServerTimestamp(matchedStart, currentMinute),
                    scheduledEndAt = scheduledServerTimestamp(matchedStart + duration, currentMinute),
                }
            end
        end
    end
    return nil
end

function LV.Raid:CanInviteRoster()
    if not IsInGroup() then
        return true
    end
    if C_PartyInfo and type(C_PartyInfo.CanInvite) == "function" then
        local ok, canInvite = pcall(C_PartyInfo.CanInvite)
        if ok then
            return canInvite == true
        end
    end
    return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

function LV.Raid:RosterInviteCandidates(guildKey, teamID, filter)
    local roster = LV.Store:TeamRoster(guildKey, teamID) or {}
    local maximumRank = rosterInviteFilterRank[filter or "raiders"] or 1
    local candidates = {}
    for nameID, assignment in pairs(roster) do
        local rosterType = type(assignment) == "table" and tostring(assignment.t or "raider"):lower() or "raider"
        if (rosterInviteTypeRank[rosterType] or 1) <= maximumRank then
            local fullName = LV.Store:DictionaryValue(guildKey, "n", nameID)
            if LV.Util:Trim(fullName) ~= "" then
                candidates[#candidates + 1] = fullName
            end
        end
    end
    table.sort(candidates, function(left, right)
        return left:lower() < right:lower()
    end)
    return candidates
end

function LV.Raid:GroupMemberNames()
    local names = {}
    local function include(unit)
        if UnitExists(unit) then
            local fullName = LV.Util:UnitFullName(unit)
            if fullName and fullName ~= "" then
                names[fullName:lower()] = true
                names[LV.Util:ShortName(fullName):lower()] = true
            end
        end
    end
    include("player")
    if IsInRaid() then
        for index = 1, (tonumber(GetNumGroupMembers()) or 0) do
            include("raid" .. tostring(index))
        end
    elseif IsInGroup() then
        for index = 1, (tonumber(GetNumSubgroupMembers()) or 0) do
            include("party" .. tostring(index))
        end
    end
    return names
end

function LV.Raid:IsRosterInviteActive(teamID)
    return type(self.inviteQueue) == "table"
        and (teamID == nil or tostring(self.inviteQueue.teamID) == tostring(teamID))
end

function LV.Raid:FinishRosterInvites(message)
    local queue = self.inviteQueue
    if not queue then
        return
    end
    queue.status = message or ("Sent " .. tostring(queue.sent or 0) .. " roster invite(s).")
    self.lastInviteStatus = {
        teamID = queue.teamID,
        text = queue.status,
        finishedAt = LV.Util:Now(),
    }
    self.inviteQueue = nil
    LV:Print(queue.status)
    refreshRosterUI()
end

function LV.Raid:ProcessRosterInviteQueue()
    local queue = self.inviteQueue
    if type(queue) ~= "table" then
        return
    end
    if not self:CanInviteRoster() then
        self:FinishRosterInvites("Roster invites stopped because you can no longer invite to the group.")
        return
    end

    if queue.requiresRaid and not IsInRaid() then
        if IsInGroup() then
            if not queue.conversionRequested then
                queue.conversionAttempts = (tonumber(queue.conversionAttempts) or 0) + 1
                if queue.conversionAttempts > 3 then
                    self:FinishRosterInvites("Roster invites paused because the party could not be converted to a raid. Convert it manually and try again.")
                    return
                end
                local convert = C_PartyInfo and C_PartyInfo.ConvertToRaid or ConvertToRaid
                if type(convert) ~= "function" then
                    self:FinishRosterInvites("Roster invites stopped because the party could not be converted to a raid.")
                    return
                end
                queue.conversionRequested = true
                queue.status = "Converting the party to a raid before continuing invites..."
                pcall(convert)
                refreshRosterUI()
                C_Timer.After(1, function()
                    if LV.Raid.inviteQueue == queue and not IsInRaid() then
                        queue.conversionRequested = nil
                        LV.Raid:ProcessRosterInviteQueue()
                    end
                end)
            end
            return
        elseif (tonumber(queue.sent) or 0) >= 4 then
            queue.status = "Four invites sent. Waiting for someone to join before converting to a raid..."
            refreshRosterUI()
            return
        end
    end

    local groupNames = self:GroupMemberNames()
    while #queue.names > 0 do
        local fullName = table.remove(queue.names, 1)
        local lowerName = fullName:lower()
        if groupNames[lowerName] or groupNames[LV.Util:ShortName(fullName):lower()] then
            queue.skipped = (tonumber(queue.skipped) or 0) + 1
        else
            local invite = C_PartyInfo and C_PartyInfo.InviteUnit or InviteUnit
            if type(invite) ~= "function" then
                self:FinishRosterInvites("Roster invites stopped because the Retail invite API is unavailable.")
                return
            end
            pcall(invite, fullName)
            queue.sent = (tonumber(queue.sent) or 0) + 1
            queue.status = "Sent " .. tostring(queue.sent) .. " of " .. tostring(queue.total)
                .. " roster invite(s)..."
            C_Timer.After(ROSTER_INVITE_DELAY, function()
                if LV.Raid.inviteQueue == queue then
                    LV.Raid:ProcessRosterInviteQueue()
                end
            end)
            return
        end
    end

    local message = "Sent " .. tostring(queue.sent or 0) .. " roster invite(s)"
    if (tonumber(queue.skipped) or 0) > 0 then
        message = message .. "; skipped " .. tostring(queue.skipped) .. " already grouped player(s)"
    end
    self:FinishRosterInvites(message .. ".")
end

function LV.Raid:StartRosterInvites(guildKey, teamID, filter)
    if self.inviteQueue then
        return false, "A roster invite batch is already running."
    end
    local record = LV.Store:GuildRecord(guildKey)
    local team = record and LV.Store:GetTeamByID(record, teamID)
    if not team or not self:RaidInviteWindow(team) then
        return false, "Team invites are available from 30 minutes before raid time until the raid ends."
    end
    if not self:CanInviteRoster() then
        return false, "You must be the group leader or an assistant to invite the roster."
    end
    local candidates = self:RosterInviteCandidates(guildKey, teamID, filter)
    if #candidates == 0 then
        return false, "No players match that roster filter."
    end
    local groupNames = self:GroupMemberNames()
    local names = {}
    local skipped = 0
    for _, fullName in ipairs(candidates) do
        if groupNames[fullName:lower()] or groupNames[LV.Util:ShortName(fullName):lower()] then
            skipped = skipped + 1
        else
            names[#names + 1] = fullName
        end
    end
    if #names == 0 then
        return false, "Everyone matching that roster filter is already in your group."
    end
    local currentGroupSize = IsInGroup() and (tonumber(GetNumGroupMembers()) or 1) or 1
    self.inviteQueue = {
        guildKey = guildKey,
        teamID = teamID,
        filter = filter,
        names = names,
        total = #names,
        sent = 0,
        skipped = skipped,
        requiresRaid = currentGroupSize + #names > 5,
        status = "Preparing " .. tostring(#names) .. " roster invite(s)...",
    }
    self:ProcessRosterInviteQueue()
    return true, #names
end

function LV.Raid:EnsureAttendanceMaps(session)
    if type(session) ~= "table" then
        return
    end

    session.p = session.p or {}
    session.b = session.b or {}
    session.late = session.late or {}
    session.out = session.out or {}
    session.noshow = session.noshow or {}
end

function LV.Raid:AttendanceIdentityID(guildKey, nameID)
    nameID = tonumber(nameID)
    if not nameID then
        return nil
    end
    local tag, mainID = LV.Guild:InferRosterTag(guildKey, nameID)
    if tag == "alt" and tonumber(mainID) then
        return tonumber(mainID)
    end
    return nameID
end

function LV.Raid:LinkedPlayerWasOnTime(guildKey, session, nameID)
    local identityID = self:AttendanceIdentityID(guildKey, nameID)
    if not identityID or type(session) ~= "table" then
        return false
    end
    self:EnsureAttendanceMaps(session)
    for actorID in pairs(session.p) do
        actorID = tonumber(actorID)
        if actorID and actorID ~= tonumber(nameID)
            and self:AttendanceIdentityID(guildKey, actorID) == identityID
            and not session.late[actorID]
            and not session.out[actorID]
            and not session.noshow[actorID] then
            return true
        end
    end
    return false
end

local function reconcileKillActors(guildKey, session, kill, field, allowed)
    local list = type(kill) == "table" and kill[field]
    if type(list) ~= "table" then
        return 0
    end

    local chosen = {}
    local killTime = tonumber(kill.ts) or math.huge
    for _, rawActorID in ipairs(list) do
        local actorID = tonumber(rawActorID)
        if actorID and (not allowed or allowed[actorID]) then
            local identityID = LV.Raid:AttendanceIdentityID(guildKey, actorID) or actorID
            local joinedAt = tonumber((session.p or {})[actorID]) or 0
            local current = chosen[identityID]
            if joinedAt <= killTime and (not current or joinedAt > current.joinedAt
                or (joinedAt == current.joinedAt and actorID == identityID)) then
                chosen[identityID] = { actorID = actorID, joinedAt = joinedAt }
            end
        end
    end

    local values = {}
    local emitted = {}
    for _, rawActorID in ipairs(list) do
        local actorID = tonumber(rawActorID)
        local identityID = actorID and (LV.Raid:AttendanceIdentityID(guildKey, actorID) or actorID)
        local choice = identityID and chosen[identityID]
        if choice and choice.actorID == actorID and not emitted[identityID] then
            values[#values + 1] = actorID
            emitted[identityID] = true
        end
    end

    local changed = #values ~= #list
    if not changed then
        for index, actorID in ipairs(values) do
            if tonumber(list[index]) ~= actorID then
                changed = true
                break
            end
        end
    end
    if changed then
        wipe(list)
        for _, actorID in ipairs(values) do
            list[#list + 1] = actorID
        end
        return 1
    end
    return 0
end

function LV.Raid:ReconcileLinkedAttendance(guildKey, session)
    if not guildKey or type(session) ~= "table" then
        return 0
    end
    self:EnsureAttendanceMaps(session)

    local onTimeIdentities = {}
    for actorID in pairs(session.p) do
        actorID = tonumber(actorID)
        if actorID and not session.late[actorID] and not session.out[actorID] and not session.noshow[actorID] then
            local identityID = self:AttendanceIdentityID(guildKey, actorID)
            if identityID then
                onTimeIdentities[identityID] = true
            end
        end
    end

    local changed = 0
    for rawActorID in pairs(session.late) do
        local actorID = tonumber(rawActorID)
        local identityID = actorID and self:AttendanceIdentityID(guildKey, actorID)
        if identityID and onTimeIdentities[identityID] then
            session.late[rawActorID] = nil
            changed = changed + 1
        end
    end

    for _, kill in ipairs(session.kills or {}) do
        changed = changed + reconcileKillActors(guildKey, session, kill, "p")
        changed = changed + reconcileKillActors(guildKey, session, kill, "late", session.late)
    end
    return changed
end

function LV.Raid:ReconcileGuildLinkedAttendance(guildKey)
    local record = guildKey and LV.Store:GuildRecord(guildKey)
    local changed = 0
    for _, session in pairs((record and record.r) or {}) do
        changed = changed + self:ReconcileLinkedAttendance(guildKey, session)
    end
    return changed
end

function LV.Raid:ReconcileAllLinkedAttendance()
    LV.Store:InitializeIfNeeded()
    local changed = 0
    for guildKey in pairs((LV.Store.db and LV.Store.db.g) or {}) do
        changed = changed + self:ReconcileGuildLinkedAttendance(guildKey)
    end
    return changed
end

function LV.Raid:FindActiveSchedule(cfg, now, teamID)
    if not cfg or type(cfg.teams) ~= "table" then
        return nil
    end

    local before = tonumber(cfg.promptBefore) or 60
    local after = tonumber(cfg.endGrace) or 0
    for teamIndex, team in ipairs(cfg.teams) do
        if not teamID or tostring(team.id) == tostring(teamID) then
            local currentMinute = teamWeekMinute(team)
            for slotIndex, slot in ipairs(team.schedules or {}) do
                local weekday = tonumber(slot.w)
                local hour = tonumber(slot.h) or 20
                local minute = tonumber(slot.m) or 0
                local duration = tonumber(slot.d) or 180

                if weekday then
                    local startMinute = ((weekday - 1) * 24 * 60) + (hour * 60) + minute
                    local matched, matchedStart = inWeeklyWindow(currentMinute, startMinute, before, duration, after)
                    if matched then
                        return team, teamIndex, slotIndex, slot, matchedStart, matchedStart + duration, currentMinute
                    end
                end
            end
        end
    end

    return nil
end

function LV.Raid:ActiveScheduleMatches(cfg)
    local matches = {}
    if not cfg or type(cfg.teams) ~= "table" then
        return matches
    end

    local before = tonumber(cfg.promptBefore) or 60
    local after = tonumber(cfg.endGrace) or 0
    local serverNow = LV.Util:ServerNow()
    for teamIndex, team in ipairs(cfg.teams) do
        local currentMinute = teamWeekMinute(team)
        for slotIndex, slot in ipairs(team.schedules or {}) do
            local weekday = tonumber(slot.w)
            local hour = tonumber(slot.h) or 20
            local minute = tonumber(slot.m) or 0
            local duration = tonumber(slot.d) or 180
            if weekday then
                local startMinute = ((weekday - 1) * 24 * 60) + (hour * 60) + minute
                local active, matchedStart = inWeeklyWindow(currentMinute, startMinute, before, duration, after)
                local scheduledStartAt = active and scheduledServerTimestamp(matchedStart, currentMinute) or nil
                local scheduledEndAt = active and scheduledServerTimestamp(matchedStart + duration, currentMinute) or nil
                if active and scheduledStartAt and scheduledEndAt
                    and serverNow < scheduledEndAt + (after * 60) then
                    matches[#matches + 1] = {
                        team = team,
                        teamIndex = teamIndex,
                        slotIndex = slotIndex,
                        startMinute = matchedStart,
                        endMinute = matchedStart + duration,
                        currentMinute = currentMinute,
                        scheduledStartAt = scheduledStartAt,
                        scheduledEndAt = scheduledEndAt,
                    }
                    break
                end
            end
        end
    end
    table.sort(matches, function(a, b)
        return tostring(a.team and a.team.name or a.team and a.team.id or ""):lower()
            < tostring(b.team and b.team.name or b.team and b.team.id or ""):lower()
    end)
    return matches
end

function LV.Raid:IsWithinRaidHours(cfg)
    if not cfg or type(cfg.teams) ~= "table" then
        return false
    end

    local after = tonumber(cfg.endGrace) or 0
    for _, team in ipairs(cfg.teams) do
        local currentMinute = teamWeekMinute(team)
        for _, slot in ipairs(team.schedules or {}) do
            local weekday = tonumber(slot.w)
            local hour = tonumber(slot.h) or 20
            local minute = tonumber(slot.m) or 0
            local duration = tonumber(slot.d) or 180
            if weekday then
                local startMinute = ((weekday - 1) * 24 * 60) + (hour * 60) + minute
                if inWeeklyWindow(currentMinute, startMinute, 0, duration, after) then
                    return true
                end
            end
        end
    end
    return false
end

function LV.Raid:ShouldPrompt()
    local guildInfo = LV.Guild:CurrentInfo()
    if not guildInfo or not IsInRaid() then
        return false
    end

    if not isGuildRaidGroup() then
        return false
    end

    local cfg = LV.Store:GetConfig(guildInfo.key)
    if not cfg or not cfg.enabled or not cfg.prompt then
        return false
    end

    if not LV.Guild:CanModifySession() then
        return false
    end

    if self:GetActiveSession() then
        return false
    end

    local instance = LV.Util:CurrentInstance()
    local instanceSeason = LV.Seasons:InstanceSeasonID(instance.instanceID, instance.name)
    local trackingSeason = LV.Seasons:TrackingSeasonID(cfg)
    if not instanceSeason or instanceSeason ~= trackingSeason then
        return false
    end

    local now = LV.Util:Now()
    local team, _, slotIndex, _, startTime = self:FindActiveSchedule(cfg, now)
    if not team then
        return false
    end

    local signature = guildInfo.key .. ":" .. tostring(team.id) .. ":" .. tostring(slotIndex) .. ":" .. tostring(startTime) .. ":" .. tostring(instance.instanceID)
    if self.prompted[signature] then
        return false
    end

    self.prompted[signature] = true
    return true, guildInfo.name, team
end

function LV.Raid:MaybePrompt()
    local shouldPrompt, guildName, team = self:ShouldPrompt()
    if shouldPrompt then
        local cfg = LV.Guild:CurrentConfig()
        StaticPopupDialogs[LV.Constants.TRACK_PROMPT].timeout = tonumber(cfg and cfg.promptTimeout) or 30
        StaticPopup_Show(LV.Constants.TRACK_PROMPT, team and team.name or "Raid", guildName, { teamID = team and team.id })
    end
end

function LV.Raid:ScheduledAutoStartContext()
    local guildInfo = LV.Guild:CurrentInfo()
    if not guildInfo or not IsInRaid() or not LV.Util:InRaidInstance() or not isGuildRaidGroup() then
        return nil
    end
    if self:GetActiveSession() then
        return nil
    end

    local cfg = LV.Store:GetConfig(guildInfo.key)
    if not cfg or cfg.enabled == false then
        return nil
    end
    local instance = LV.Util:CurrentInstance()
    local instanceSeason = LV.Seasons:InstanceSeasonID(instance.instanceID, instance.name)
    if not instanceSeason or instanceSeason ~= LV.Seasons:TrackingSeasonID(cfg) then
        return nil
    end
    local matches = self:ActiveScheduleMatches(cfg)
    if #matches == 0 then
        return nil
    end
    return {
        guildInfo = guildInfo,
        cfg = cfg,
        instance = instance,
        matches = matches,
        signature = loggerSignature(guildInfo.key, instance.instanceID, instance.difficultyID),
    }
end

function LV.Raid:AutoStartCandidatePriority()
    if UnitIsGroupLeader("player") then
        return 1
    elseif UnitIsGroupAssistant("player") then
        return 2
    elseif LV.Guild:CanModifySession() then
        return 3
    end
    return 4
end

function LV.Raid:StartElectedScheduledRaid(context)
    if not context or self:GetActiveSession() then
        return
    end
    local matches = self:ActiveScheduleMatches(context.cfg)
    if #matches == 0 then
        return
    end

    local function startTeam(teamID)
        if not LV.Raid:GetActiveSession() then
            LV.Raid:StartSession("auto_scheduled", teamID, { autoScheduled = true })
        end
    end

    if #matches == 1 then
        startTeam(matches[1].team.id)
    elseif LV.UI and LV.UI.PromptRaidTeamSelection then
        local teams = {}
        for _, match in ipairs(matches) do
            teams[#teams + 1] = match.team
        end
        LV.UI:PromptRaidTeamSelection(teams, startTeam)
    else
        LV:Print("Multiple raid teams are active. Open LootViewer and start the correct team.")
    end
end

function LV.Raid:ResolveAutoStartElection(signature)
    local state = self.autoStartElections[signature]
    self.autoStartElections[signature] = nil
    if not state then
        return
    end
    local context = self:ScheduledAutoStartContext()
    if not context or context.signature ~= signature then
        return
    end
    local remote = self.remoteRaidLoggers[signature]
    if remote and LV.Util:Now() - (tonumber(remote.ts) or 0) <= REMOTE_LOGGER_FRESH_SECONDS then
        return
    end

    local candidates = {}
    for _, candidate in pairs(state.candidates or {}) do
        candidates[#candidates + 1] = candidate
    end
    table.sort(candidates, function(a, b)
        if a.priority ~= b.priority then
            return a.priority < b.priority
        end
        return a.key < b.key
    end)
    local winner = candidates[1]
    if winner and winner.key == LV.Util:PlayerFullName():lower() then
        self:StartElectedScheduledRaid(context)
    end
end

function LV.Raid:JoinAutoStartElection(context, candidateName, priority)
    if not context then
        return
    end
    local signature = context.signature
    local state = self.autoStartElections[signature]
    if not state then
        state = { candidates = {}, sentAt = 0 }
        self.autoStartElections[signature] = state
    end
    candidateName = LV.Util:Trim(candidateName)
    if candidateName ~= "" then
        local key = candidateName:lower()
        state.candidates[key] = {
            key = key,
            name = candidateName,
            priority = math.max(1, math.min(4, tonumber(priority) or 4)),
        }
    end
    local selfName = LV.Util:PlayerFullName()
    state.candidates[selfName:lower()] = {
        key = selfName:lower(),
        name = selfName,
        priority = self:AutoStartCandidatePriority(),
    }

    local now = LV.Util:Now()
    if now - (tonumber(state.sentAt) or 0) >= 1 then
        state.sentAt = now
        LV.Comms:Send("P", {
            context.guildInfo.key,
            context.instance.instanceID,
            context.instance.difficultyID,
            self:AutoStartCandidatePriority(),
        })
    end
    if not state.timerStarted and C_Timer and C_Timer.After then
        state.timerStarted = true
        C_Timer.After(AUTO_START_ELECTION_SECONDS, function()
            LV.Raid:ResolveAutoStartElection(signature)
        end)
    end
end

function LV.Raid:MaybeAutoStartScheduled()
    local context = self:ScheduledAutoStartContext()
    if not context then
        return false
    end
    local remote = self.remoteRaidLoggers[context.signature]
    if remote and LV.Util:Now() - (tonumber(remote.ts) or 0) <= REMOTE_LOGGER_FRESH_SECONDS then
        return true
    end
    self:JoinAutoStartElection(context)
    return true
end

function LV.Raid:ObserveLoggerProbe(parts, sender)
    local guildInfo = LV.Guild:CurrentInfo()
    if not guildInfo or parts[2] ~= guildInfo.key then
        return
    end
    local instance = LV.Util:CurrentInstance()
    if tonumber(parts[3]) ~= tonumber(instance.instanceID)
        or tonumber(parts[4]) ~= tonumber(instance.difficultyID) then
        return
    end
    local session = self:GetActiveSession()
    if session then
        LV.Comms:Send("S", {
            guildInfo.key,
            session.id,
            session.st,
            session.iid,
            session.team,
            session.did,
        })
        return
    end
    local context = self:ScheduledAutoStartContext()
    if context then
        self:JoinAutoStartElection(context, sender, tonumber(parts[5]))
    end
end

function LV.Raid:MaybeAutoStartPug()
    local active = self:GetActiveSession()
    if active and active.autoPug then
        if not IsInRaid() or not LV.Util:InRaidInstance() then
            self.autoPugSignature = nil
            self:EndSession("left_pug_raid")
            return false
        end
        return true
    end

    if not IsInRaid() or not LV.Util:InRaidInstance() then
        self.autoPugSignature = nil
        return false
    end
    if active then
        return false
    end

    local account = LV.Store:AccountConfig()
    if not account or account.autoPugRaids ~= true then
        return false
    end

    local guildInfo = LV.Guild:CurrentInfo()
    if not guildInfo then
        return false
    end
    local cfg = LV.Store:GetConfig(guildInfo.key)
    if not cfg or cfg.enabled == false or self:IsWithinRaidHours(cfg)
        or (isGuildRaidGroup() and #self:ActiveScheduleMatches(cfg) > 0) then
        return false
    end

    local instance = LV.Util:CurrentInstance()
    if instance.instanceType ~= "raid"
        or (isLFRWorldTier(instance) and account.autoPugIncludeLFR ~= true) then
        return false
    end
    local instanceSeason = LV.Seasons:InstanceSeasonID(instance.instanceID, instance.name)
    if not instanceSeason or instanceSeason ~= LV.Seasons:TrackingSeasonID(cfg) then
        return false
    end

    local signature = table.concat({
        tostring(guildInfo.key),
        tostring(instance.instanceID),
        tostring(instance.difficultyID),
    }, ":")
    if self.autoPugSignature == signature then
        return false
    end
    self.autoPugSignature = signature
    return self:StartSession("auto_pug", LV.Constants.PUG_TEAM_ID, {
        adhoc = true,
        autoPug = true,
        noTimeout = true,
    }) ~= nil
end

function LV.Raid:StartSession(reason, teamID, options)
    local guildInfo = LV.Guild:CurrentInfo()
    if not guildInfo then
        LV:Print("You are not currently in a guild.")
        return nil
    end

    local isPugTeam = LV.Store:IsGlobalPugTeam(teamID)
    local isAutoScheduled = type(options) == "table" and options.autoScheduled == true
    if not isPugTeam and not isAutoScheduled and not LV.Guild:CanModifySession() then
        LV:Print("Your current LootViewer authority settings do not allow you to start a tracked raid.")
        return nil
    end

    if not IsInRaid() and reason ~= "slash" then
        LV:Print("Join a raid before starting a tracked raid.")
        return nil
    end

    local record = LV.Store:GuildRecord(guildInfo.key)
    local existing = self:GetActiveSession()
    if existing then
        LV:Print("Already tracking this raid.")
        return existing
    end

    local instance = LV.Util:CurrentInstance()
    local inRaidInstance = instance.instanceType == "raid"
    local team = LV.Store:GetTeamByID(record, teamID) or LV.Store:GetSelectedTeam(record)
    local scheduledStart = nil
    local scheduledEnd = nil
    if team and not (type(options) == "table" and options.adhoc) then
        local _, _, _, _, startMinute, endMinute, currentMinute = self:FindActiveSchedule(record.cfg, nil, team.id)
        scheduledStart = scheduledServerTimestamp(startMinute, currentMinute)
        scheduledEnd = scheduledServerTimestamp(endMinute, currentMinute)
    end
    if isAutoScheduled and scheduledEnd
        and LV.Util:ServerNow() >= scheduledEnd + ((tonumber(record.cfg.endGrace) or 0) * 60) then
        return nil
    end
    local startedAt = LV.Util:Now()
    local identityFields = {
        st = startedAt,
        sst = scheduledStart,
        team = team and team.id or "main",
    }
    local canonicalRaidID = not isPugTeam and LV.DataSync and LV.DataSync.RaidIdentity
        and LV.DataSync:RaidIdentity(guildInfo.key, identityFields) or nil
    local raidID = canonicalRaidID
    if not raidID or record.r[raidID] ~= nil then
        raidID = LV.Store:NewID(record, "raid", "r")
    end
    local playerID = LV.Store:NameID(guildInfo.key, LV.Util:PlayerFullName())
    local session = {
        id = raidID,
        cid = canonicalRaidID,
        st = startedAt,
        sst = scheduledStart,
        set = scheduledEnd,
        en = startedAt,
        z = inRaidInstance and LV.Store:StringID(guildInfo.key, instance.name) or nil,
        iid = inRaidInstance and instance.instanceID or 0,
        diff = inRaidInstance and LV.Store:StringID(guildInfo.key, instance.difficultyName) or nil,
        did = inRaidInstance and instance.difficultyID or 0,
        sea = (inRaidInstance and LV.Seasons:InstanceSeasonID(instance.instanceID, instance.name))
            or LV.Seasons:TrackingSeasonID(record.cfg),
        team = team and team.id or "main",
        tn = team and LV.Store:StringID(guildInfo.key, team.name) or nil,
        by = playerID,
        reason = reason or "",
        p = {},
        b = {},
        late = {},
        out = {},
        noshow = {},
        kills = {},
        rem = {},
    }

    if type(options) == "table" and options.adhoc then
        session.adhoc = 1
        if options.autoPug then
            session.autoPug = 1
        end
        if not options.noTimeout then
            local hours = normalizeAdHocHours(options.hours)
            session.adDur = math.floor(hours * 60)
            session.adEnd = session.st + math.floor(hours * 60 * 60)
        end
    end
    if isAutoScheduled then
        session.autoScheduled = 1
    end

    record.r[raidID] = session
    record.cur = raidID
    self:RecordRaidRoster("start")
    if session.set then
        self:ScheduleScheduledEnd(guildInfo.key, raidID, session.set + ((tonumber(record.cfg.endGrace) or 0) * 60))
    end
    if not LV.Store:IsTeamExcludedFromSync(guildInfo.key, session.team) then
        LV.Comms:Send("S", {
            guildInfo.key,
            raidID,
            session.st,
            session.iid,
            session.team,
            session.did,
        })
    end
    LV:Print("Tracking " .. (team and team.name or "Raid") .. " raid for " .. guildInfo.name .. ".")

    if LV.UI and LV.UI.Refresh then
        LV.UI:Refresh()
    end

    return session
end

function LV.Raid:StartAdHocSession(teamID, hours)
    local session = self:StartSession("adhoc", teamID, { adhoc = true, hours = hours })
    if session and session.adEnd then
        self:ScheduleAdHocEnd(session.id, session.adEnd)
    end
    return session
end

function LV.Raid:ScheduleAdHocEnd(raidID, endAt)
    if not C_Timer or not C_Timer.After then
        return
    end

    if self.adHocTimers[raidID] == endAt then
        return
    end
    self.adHocTimers[raidID] = endAt

    local delay = (tonumber(endAt) or 0) - LV.Util:Now()
    if delay <= 0 then
        self.adHocTimers[raidID] = nil
        return
    end

    C_Timer.After(delay, function()
        LV.Raid.adHocTimers[raidID] = nil
        local session = LV.Raid:GetActiveSession()
        if session and session.id == raidID and tonumber(session.adEnd) and LV.Util:Now() >= tonumber(session.adEnd) then
            LV.Raid:EndSession("adhoc_duration")
        end
    end)
end

function LV.Raid:ExpireScheduledSession(guildKey, raidID, endAt)
    local record = LV.Store:GuildRecord(guildKey)
    local session = record and record.r and record.r[raidID]
    if not record or record.cur ~= raidID or type(session) ~= "table" then
        return false
    end

    session.en = tonumber(endAt) or LV.Util:Now()
    session.endReason = "scheduled_end"
    self:ApplyTeamRosterNoShows(guildKey, record, session)
    record.cur = nil
    local signature = loggerSignature(guildKey, session.iid, session.did)
    self.scheduledEndTimers[tostring(guildKey) .. ":" .. tostring(raidID)] = nil
    self.autoStartElections[signature] = nil
    if LV.Guild:CurrentKey() == guildKey then
        local instance = LV.Util:CurrentInstance()
        if IsInRaid() and LV.Util:InRaidInstance()
            and tonumber(instance.instanceID) == tonumber(session.iid)
            and tonumber(instance.difficultyID) == tonumber(session.did) then
            self.autoPugSignature = signature
        end
    end
    if LV.Guild:CurrentKey() == guildKey and not LV.Store:IsRaidExcludedFromSync(guildKey, session) then
        LV.Comms:Send("E", { guildKey, session.id, session.en })
    end
    LV:Print("Scheduled raid tracking ended.")
    if LV.UI and LV.UI.Refresh then
        LV.UI:Refresh()
    end
    return true
end

function LV.Raid:ScheduleScheduledEnd(guildKey, raidID, endAt)
    if not C_Timer or not C_Timer.After or not guildKey or not raidID then
        return
    end

    endAt = tonumber(endAt)
    if not endAt then
        return
    end
    local key = tostring(guildKey) .. ":" .. tostring(raidID)
    if self.scheduledEndTimers[key] == endAt then
        return
    end
    self.scheduledEndTimers[key] = endAt
    local delay = endAt - LV.Util:ServerNow()
    if delay <= 0 then
        self:ExpireScheduledSession(guildKey, raidID, endAt)
        return
    end

    C_Timer.After(delay, function()
        if LV.Raid.scheduledEndTimers[key] ~= endAt then
            return
        end
        LV.Raid.scheduledEndTimers[key] = nil
        if LV.Util:ServerNow() >= endAt then
            LV.Raid:ExpireScheduledSession(guildKey, raidID, endAt)
        end
    end)
end

function LV.Raid:RosterPlayerAttended(guildKey, session, rosterNameID)
    rosterNameID = tonumber(rosterNameID)
    if not rosterNameID or type(session) ~= "table" then
        return false
    end
    local attendanceIDs = {}
    for _, map in ipairs({ session.p, session.b, session.late, session.out, session.noshow }) do
        for nameID in pairs(map or {}) do
            attendanceIDs[tonumber(nameID) or nameID] = true
        end
    end
    if attendanceIDs[rosterNameID] then
        return true
    end
    for actorNameID in pairs(attendanceIDs) do
        local tag, mainNameID = LV.Guild:InferRosterTag(guildKey, actorNameID)
        if tag == "alt" and tonumber(mainNameID) == rosterNameID then
            return true
        end
    end
    return false
end

function LV.Raid:ApplyTeamRosterNoShows(guildKey, record, session)
    if not guildKey or type(record) ~= "table" or type(session) ~= "table" then
        return 0
    end
    local roster = LV.Store:TeamRoster(guildKey, session.team or "main")
    if type(roster) ~= "table" then
        return 0
    end
    self:EnsureAttendanceMaps(session)
    local timestamp = tonumber(session.en) or LV.Util:Now()
    local changed = 0
    for rawNameID, assignment in pairs(roster) do
        local nameID = tonumber(rawNameID)
        local rosterType = type(assignment) == "table" and assignment.t or "raider"
        if nameID and rosterType ~= "helper" and rosterType ~= "social"
            and not self:RosterPlayerAttended(guildKey, session, nameID) then
            session.noshow[nameID] = timestamp
            changed = changed + 1
        end
    end
    return changed
end

function LV.Raid:EndSession(reason)
    local guildInfo = LV.Guild:CurrentInfo()
    local session, record = self:GetActiveSession()
    if not session or not record then
        LV:Print("No active LootViewer raid.")
        return
    end

    session.en = LV.Util:Now()
    session.endReason = reason or ""
    if guildInfo then
        self:ApplyTeamRosterNoShows(guildInfo.key, record, session)
    end
    record.cur = nil
    if guildInfo then
        self.scheduledEndTimers[tostring(guildInfo.key) .. ":" .. tostring(session.id)] = nil
    end
    LV:Print("Stopped tracking raid.")

    if guildInfo and not LV.Store:IsRaidExcludedFromSync(guildInfo.key, session) then
        LV.Comms:Send("E", { guildInfo.key, session.id, session.en })
    end

    if LV.UI and LV.UI.Refresh then
        LV.UI:Refresh()
    end
end

function LV.Raid:FindMostRecentSession(record)
    local bestSession = nil
    local bestID = nil
    local bestTime = 0

    if type(record) ~= "table" or type(record.r) ~= "table" then
        return nil
    end

    for raidID, session in pairs(record.r) do
        if type(session) == "table" then
            local timestamp = tonumber(session.en) or tonumber(session.st) or 0
            if timestamp > bestTime then
                bestTime = timestamp
                bestSession = session
                bestID = raidID
            end
        end
    end

    return bestSession, bestID
end

function LV.Raid:ExtendMostRecentSession(hours)
    local guildInfo = LV.Guild:CurrentInfo()
    if not guildInfo then
        LV:Print("You are not currently in a guild.")
        return nil
    end

    if not LV.Guild:CanModifySession() then
        LV:Print("Your current LootViewer authority settings do not allow you to extend a tracked raid.")
        return nil
    end

    local record = LV.Store:GuildRecord(guildInfo.key)
    if not record then
        LV:Print("No guild record found.")
        return nil
    end

    local raidID = record.cur
    local session = raidID and record.r[raidID]
    if type(session) ~= "table" then
        session, raidID = self:FindMostRecentSession(record)
    end

    if type(session) ~= "table" or not raidID then
        LV:Print("No LootViewer raid found to extend.")
        return nil
    end

    local extensionHours = normalizeAdHocHours(hours)
    local now = LV.Util:Now()
    local endAt = now + math.floor(extensionHours * 60 * 60)

    self:EnsureAttendanceMaps(session)
    session.en = now
    session.adEnd = endAt
    session.set = nil
    session.adDur = math.max(tonumber(session.adDur) or 0, math.floor((endAt - (tonumber(session.st) or now)) / 60))
    session.endReason = nil
    session.lastBy = LV.Store:NameID(guildInfo.key, LV.Util:PlayerFullName())
    session.lastSource = "extend"
    record.cur = raidID

    self.scheduledEndTimers[tostring(guildInfo.key) .. ":" .. tostring(raidID)] = nil

    self.adHocTimers[session.id] = nil
    self:ScheduleAdHocEnd(session.id, endAt)

    local instanceID = tonumber(session.iid) or 0
    if not LV.Store:IsTeamExcludedFromSync(guildInfo.key, session.team) then
        LV.Comms:Send("S", {
            guildInfo.key,
            session.id,
            tonumber(session.st) or now,
            instanceID,
            session.team,
            session.did,
        })
    end
    LV:Print("Extended raid tracking by " .. tostring(extensionHours) .. " hour(s), until " .. date("%H:%M", endAt) .. ".")

    if LV.UI and LV.UI.Refresh then
        LV.UI:Refresh()
    end

    return session
end

function LV.Raid:GetActiveSession()
    local guildKey = LV.Guild:CurrentKey()
    if not guildKey then
        return nil
    end

    local record = LV.Store:GuildRecord(guildKey)
    local raidID = record and record.cur
    local session = raidID and record.r[raidID]
    if type(session) ~= "table" then
        return nil
    end
    self:EnsureAttendanceMaps(session)

    local lastSeen = tonumber(session.en) or tonumber(session.st) or 0
    local scheduledEndAt = tonumber(session.set)
    if scheduledEndAt then
        local cfg = record.cfg or {}
        scheduledEndAt = scheduledEndAt + ((tonumber(cfg.endGrace) or 0) * 60)
        if LV.Util:ServerNow() >= scheduledEndAt then
            self:ExpireScheduledSession(guildKey, raidID, scheduledEndAt)
            return nil
        end
        self:ScheduleScheduledEnd(guildKey, raidID, scheduledEndAt)
    end
    local adHocEnd = tonumber(session.adEnd)
    if adHocEnd and LV.Util:Now() >= adHocEnd then
        session.en = adHocEnd
        session.endReason = session.endReason or "adhoc_duration"
        record.cur = nil
        return nil
    end

    if LV.Util:Now() - lastSeen > LV.Constants.SESSION_IDLE_SECONDS then
        record.cur = nil
        return nil
    end

    if adHocEnd then
        self:ScheduleAdHocEnd(session.id, adHocEnd)
    end

    return session, record, guildKey
end

function LV.Raid:ForEachRaidMember(callback)
    if IsInRaid() then
        for index = 1, GetNumGroupMembers() do
            local name = unitFullName("raid" .. index)
            if name then
                callback(name, "raid" .. index)
            end
        end
    elseif IsInGroup() then
        local playerName = LV.Util:PlayerFullName()
        callback(playerName, "player")
        for index = 1, GetNumSubgroupMembers() do
            local name = unitFullName("party" .. index)
            if name then
                callback(name, "party" .. index)
            end
        end
    end
end

function LV.Raid:UpdateSessionInstance(session, guildKey)
    if type(session) ~= "table" or not guildKey then
        return false
    end

    local instance = LV.Util:CurrentInstance()
    if instance.instanceType ~= "raid" or LV.Util:IsBlank(instance.name) then
        return false
    end

    local changed = false
    local zoneID = LV.Store:StringID(guildKey, instance.name)
    local difficultyID = LV.Store:StringID(guildKey, instance.difficultyName)
    if session.z ~= zoneID then
        session.z = zoneID
        changed = true
    end
    if tonumber(session.iid) ~= tonumber(instance.instanceID) then
        session.iid = instance.instanceID
        changed = true
    end
    if session.diff ~= difficultyID then
        session.diff = difficultyID
        changed = true
    end
    if tonumber(session.did) ~= tonumber(instance.difficultyID) then
        session.did = instance.difficultyID
        changed = true
    end

    local seasonID = LV.Seasons:InstanceSeasonID(instance.instanceID, instance.name)
    if seasonID and session.sea ~= seasonID then
        session.sea = seasonID
        changed = true
    end
    return changed
end

function LV.Raid:RecordRaidRoster(reason)
    local session, _, guildKey = self:GetActiveSession()
    if not session or not guildKey then
        return
    end

    self:UpdateSessionInstance(session, guildKey)
    local now = LV.Util:Now()
    session.en = now
    self:ForEachRaidMember(function(fullName, unit)
        local nameID = LV.Store:NameID(guildKey, fullName)
        if nameID then
            local _, classFileName = UnitClass(unit or "")
            if classFileName and classFileName ~= "" then
                LV.Store:SetPlayerClass(guildKey, nameID, classFileName)
            end
            if UnitIsInMyGuild and UnitIsInMyGuild(unit or "") then
                LV.Store:AddRosterMember(guildKey, fullName, {
                    c = classFileName,
                    ov = 1,
                    onl = 1,
                })
            end
        end
        if nameID and not session.b[nameID] and not session.out[nameID] and not session.noshow[nameID] then
            if not session.p[nameID] then
                session.p[nameID] = now
                self:MaybePromptLate(fullName, nameID)
            end
        end
    end)

    if LV.UI and LV.UI.Refresh then
        LV.UI:Refresh()
    end
end

function LV.Raid:MaybePromptLate(fullName, nameID)
    local session = self:GetActiveSession()
    if not session or session.b[nameID] or session.late[nameID] or session.out[nameID] or session.noshow[nameID] then
        return
    end
    local guildKey = LV.Guild:CurrentKey()
    if guildKey and self:LinkedPlayerWasOnTime(guildKey, session, nameID) then
        return
    end

    local cfg = LV.Guild:CurrentConfig()
    local grace = ((cfg and tonumber(cfg.lateGrace)) or 10) * 60
    local lateAnchor = tonumber(session.sst)
    if not lateAnchor and not session.adhoc and cfg then
        local _, _, _, _, startMinute, _, currentMinute = self:FindActiveSchedule(cfg, nil, session.team)
        lateAnchor = scheduledServerTimestamp(startMinute, currentMinute)
        session.sst = lateAnchor
    end
    lateAnchor = lateAnchor or tonumber(session.st) or 0
    if LV.Util:ServerNow() <= lateAnchor + grace then
        return
    end

    local key = tostring(session.id) .. ":" .. tostring(nameID)
    if self.latePrompted[key] then
        return
    end

    self.latePrompted[key] = true
    self:SetAttendance(fullName, "late", "late_auto")
end

function LV.Raid:SetAttendance(fullName, status, source)
    local session, _, guildKey = self:GetActiveSession()
    if not session or not guildKey then
        LV:Print("No active LootViewer raid.")
        return
    end

    local localPlayerID = guildKey and LV.Store:NameID(guildKey, LV.Util:PlayerFullName())
    local isAutoRecorder = session.autoScheduled and session.by == localPlayerID
    if source ~= "self" and source ~= "whisper" and not isAutoRecorder and not LV.Guild:CanModifySession() then
        LV:Print("Your current LootViewer authority settings do not allow attendance changes.")
        return
    end

    fullName = LV.Util:Trim(fullName)
    if fullName == "" then
        return
    end
    if not fullName:find("-", 1, true) then
        local info = LV.Guild:CurrentInfo()
        fullName = fullName .. "-" .. ((info and info.realm) or LV.Util:RealmName())
    end

    local nameID = LV.Store:NameID(guildKey, fullName)
    local now = LV.Util:Now()
    self:EnsureAttendanceMaps(session)
    if status == "bench" then
        session.b[nameID] = tonumber(session.st) or now
        session.p[nameID] = session.p[nameID] or tonumber(session.st) or now
        session.late[nameID] = nil
        session.out[nameID] = nil
        session.noshow[nameID] = nil
    elseif status == "late" then
        session.p[nameID] = session.p[nameID] or now
        session.late[nameID] = now
        session.b[nameID] = nil
        session.out[nameID] = nil
        session.noshow[nameID] = nil
    elseif status == "here" then
        session.p[nameID] = session.p[nameID] or now
        session.b[nameID] = nil
        session.late[nameID] = nil
        session.out[nameID] = nil
        session.noshow[nameID] = nil
    elseif status == "out" then
        session.out[nameID] = now
        session.p[nameID] = nil
        session.b[nameID] = nil
        session.late[nameID] = nil
        session.noshow[nameID] = nil
    elseif status == "noshow" then
        session.noshow[nameID] = now
        session.p[nameID] = nil
        session.b[nameID] = nil
        session.late[nameID] = nil
        session.out[nameID] = nil
    end

    session.en = now
    session.lastBy = LV.Store:NameID(guildKey, LV.Util:PlayerFullName())
    session.lastSource = source or ""

    if LV.UI and LV.UI.Refresh then
        LV.UI:Refresh()
    end
end

function LV.Raid:MarkPlayerBench(fullName, source)
    self:SetAttendance(fullName, "bench", source or "manual")
end

function LV.Raid:RecordBossKill(encounterID, encounterName, difficultyID, groupSize, success)
    if tonumber(success) ~= 1 then
        return
    end

    local session, _, guildKey = self:GetActiveSession()
    if not session or not guildKey then
        return
    end

    self:RecordRaidRoster("boss")
    local present = {}
    self:ForEachRaidMember(function(fullName, unit)
        if type(UnitIsConnected) ~= "function" or UnitIsConnected(unit or "") then
            local nameID = LV.Store:NameID(guildKey, fullName)
            if nameID and not session.b[nameID] and not session.out[nameID] and not session.noshow[nameID] then
                present[nameID] = true
            end
        end
    end)
    local late = {}
    for nameID in pairs(present) do
        if session.late[nameID] then
            late[nameID] = true
        end
    end
    local kill = {
        ts = LV.Util:Now(),
        e = tonumber(encounterID) or 0,
        b = LV.Store:StringID(guildKey, encounterName),
        d = tonumber(difficultyID) or 0,
        n = tonumber(groupSize) or 0,
        p = listKeys(present),
        bench = listKeys(session.b),
        late = listKeys(late),
        out = listKeys(session.out),
        noshow = listKeys(session.noshow),
    }

    table.insert(session.kills, kill)
    session.en = kill.ts

    if LV.Loot and LV.Loot.ScheduleLootHistoryScan then
        LV.Loot:ScheduleLootHistoryScan(encounterID)
    end
end

function LV.Raid:ObserveRemoteSession(parts, sender)
    local guildKey = LV.Guild:CurrentKey()
    if not guildKey or parts[2] ~= guildKey then
        return
    end

    sender = LV.Util:Trim(sender)
    if sender:lower() ~= LV.Util:PlayerFullName():lower() then
        local instance = LV.Util:CurrentInstance()
        local instanceID = tonumber(parts[5]) or tonumber(instance.instanceID) or 0
        local difficultyID = tonumber(parts[7]) or tonumber(instance.difficultyID) or 0
        local signature = loggerSignature(guildKey, instanceID, difficultyID)
        self.remoteRaidLoggers[signature] = {
            ts = LV.Util:Now(),
            sender = sender,
            raidID = parts[3],
            team = parts[6],
        }
        self.autoStartElections[signature] = nil
    end

    local session = self:GetActiveSession()
    if session then
        session.rem = session.rem or {}
        session.rem[sender or "unknown"] = LV.Util:Now()
    end
end

function LV.Raid:HandleWhisper(message, sender)
    local cfg = LV.Guild:CurrentConfig()
    local session = self:GetActiveSession()
    if not cfg or not session then
        return
    end

    local keyword = LV.Util:Trim(cfg.whisper):lower()
    if keyword == "" or LV.Util:Trim(message):lower() ~= keyword then
        return
    end

    self:MarkPlayerBench(sender, "whisper")
    SendChatMessage("LootViewer marked you as standby for tonight.", "WHISPER", nil, sender)
end

StaticPopupDialogs[LV.Constants.TRACK_PROMPT] = {
    text = "Track this as a LootViewer %s raid for %s?",
    button1 = YES,
    button2 = NO,
    timeout = 30,
    whileDead = true,
    hideOnEscape = true,
    OnAccept = function(_, data)
        LV.Raid:StartSession("prompt", data and data.teamID)
    end,
}

LV:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    C_Timer.After(2, function()
        LV.Raid:MaybeAutoStartScheduled()
        LV.Raid:MaybeAutoStartPug()
        LV.Raid:RecordRaidRoster("enter_world")
    end)
end)

LV:RegisterEvent("PLAYER_LOGIN", function()
    local repaired = LV.Raid:ReconcileAllLinkedAttendance()
    if repaired > 0 then
        LV:Print("Reconciled " .. tostring(repaired) .. " linked-character attendance entries.")
    end
end)

LV:RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
    C_Timer.After(1, function()
        LV.Raid:MaybeAutoStartScheduled()
        LV.Raid:MaybeAutoStartPug()
        LV.Raid:RecordRaidRoster("zone")
    end)
end)

LV:RegisterEvent("GROUP_ROSTER_UPDATE", function()
    C_Timer.After(1, function()
        LV.Raid:ProcessRosterInviteQueue()
        LV.Raid:MaybeAutoStartScheduled()
        LV.Raid:MaybeAutoStartPug()
        LV.Raid:RecordRaidRoster("roster")
    end)
end)

LV:RegisterEvent("ENCOUNTER_END", function(_, encounterID, encounterName, difficultyID, groupSize, success)
    LV.Raid:RecordBossKill(encounterID, encounterName, difficultyID, groupSize, success)
end)

LV:RegisterEvent("CHAT_MSG_WHISPER", function(_, message, sender)
    LV.Raid:HandleWhisper(message, sender)
end)

LV:RegisterEvent("PLAYER_LOGOUT", function()
    local session = LV.Raid:GetActiveSession()
    if session then
        session.en = LV.Util:Now()
    end
end)
