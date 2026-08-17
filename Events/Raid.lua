local _, LV = ...

LV.Raid = {}
LV.modules.Raid = LV.Raid

LV.Raid.prompted = {}
LV.Raid.latePrompted = {}
LV.Raid.adHocTimers = {}
LV.Raid.scheduledEndTimers = {}
LV.Raid.autoPugSignature = nil

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
    if type(InGuildParty) ~= "function" then
        return true
    end

    local ok, inGuildParty = pcall(InGuildParty)
    return ok and inGuildParty and true or false
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
    if not cfg or cfg.enabled == false or self:IsWithinRaidHours(cfg) then
        return false
    end

    local instance = LV.Util:CurrentInstance()
    if instance.instanceType ~= "raid" or tonumber(instance.difficultyID) == 17 then
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
    if not isPugTeam and not LV.Guild:CanModifySession() then
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
    local team = LV.Store:GetTeamByID(record, teamID) or LV.Store:GetSelectedTeam(record)
    local scheduledStart = nil
    local scheduledEnd = nil
    if team and not (type(options) == "table" and options.adhoc) then
        local _, _, _, _, startMinute, endMinute, currentMinute = self:FindActiveSchedule(record.cfg, nil, team.id)
        scheduledStart = scheduledServerTimestamp(startMinute, currentMinute)
        scheduledEnd = scheduledServerTimestamp(endMinute, currentMinute)
    end
    local raidID = LV.Store:NewID(record, "raid", "r")
    local playerID = LV.Store:NameID(guildInfo.key, LV.Util:PlayerFullName())
    local session = {
        id = raidID,
        st = LV.Util:Now(),
        sst = scheduledStart,
        set = scheduledEnd,
        en = LV.Util:Now(),
        z = LV.Store:StringID(guildInfo.key, instance.name),
        iid = instance.instanceID,
        diff = LV.Store:StringID(guildInfo.key, instance.difficultyName),
        did = instance.difficultyID,
        sea = LV.Seasons:InstanceSeasonID(instance.instanceID, instance.name) or LV.Seasons:TrackingSeasonID(record.cfg),
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

    record.r[raidID] = session
    record.cur = raidID
    self:RecordRaidRoster("start")
    if session.set then
        self:ScheduleScheduledEnd(guildInfo.key, raidID, session.set + ((tonumber(record.cfg.endGrace) or 0) * 60))
    end
    if not LV.Store:IsTeamExcludedFromSync(guildInfo.key, session.team) then
        LV.Comms:Send("S", { guildInfo.key, raidID, session.st, instance.instanceID, session.team })
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
    record.cur = nil
    self.scheduledEndTimers[tostring(guildKey) .. ":" .. tostring(raidID)] = nil
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

function LV.Raid:EndSession(reason)
    local guildInfo = LV.Guild:CurrentInfo()
    local session, record = self:GetActiveSession()
    if not session or not record then
        LV:Print("No active LootViewer raid.")
        return
    end

    session.en = LV.Util:Now()
    session.endReason = reason or ""
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
        LV.Comms:Send("S", { guildInfo.key, session.id, tonumber(session.st) or now, instanceID, session.team })
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

function LV.Raid:RecordRaidRoster(reason)
    local session, _, guildKey = self:GetActiveSession()
    if not session or not guildKey then
        return
    end

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

    if source ~= "self" and source ~= "whisper" and not LV.Guild:CanModifySession() then
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
    local kill = {
        ts = LV.Util:Now(),
        e = tonumber(encounterID) or 0,
        b = LV.Store:StringID(guildKey, encounterName),
        d = tonumber(difficultyID) or 0,
        n = tonumber(groupSize) or 0,
        p = listKeys(session.p),
        bench = listKeys(session.b),
        late = listKeys(session.late),
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
        LV.Raid:MaybeAutoStartPug()
        LV.Raid:MaybePrompt()
        LV.Raid:RecordRaidRoster("enter_world")
    end)
end)

LV:RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
    C_Timer.After(1, function()
        LV.Raid:MaybeAutoStartPug()
        LV.Raid:MaybePrompt()
    end)
end)

LV:RegisterEvent("GROUP_ROSTER_UPDATE", function()
    C_Timer.After(1, function()
        LV.Raid:MaybeAutoStartPug()
        LV.Raid:MaybePrompt()
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
