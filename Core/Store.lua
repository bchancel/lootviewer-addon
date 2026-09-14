local _, LV = ...

LV.Store = {}
LV.modules.Store = LV.Store

local function ensureTable(parent, key)
    if type(parent[key]) ~= "table" then
        parent[key] = {}
    end
    return parent[key]
end

local DEFAULT_TEAM_COLOR = { r = 0.1725, g = 0.5569, b = 0.8275, a = 0.8 }
local TEAM_ROSTER_TYPES = { raider = true, trial = true, helper = true, social = true }
local TEAM_ROSTER_ROLES = { tank = true, healer = true, melee = true, ranged = true }
local PLAYER_ALIAS_MIGRATION_VERSION = 1
local GLOBAL_PUG_TEAM = {
    id = "pugs",
    name = "Pugs",
    tz = "realm",
    clock24 = false,
    excludeSync = true,
    global = true,
    locked = true,
    color = { r = 197 / 255, g = 198 / 255, b = 199 / 255, a = 1 },
    schedules = {},
}

local function clampColor(value, fallback)
    value = tonumber(value)
    if not value then
        return fallback
    elseif value < 0 then
        return 0
    elseif value > 1 then
        return 1
    end
    return value
end

local function snapScheduleMinute(value, maximum)
    value = math.floor(((tonumber(value) or 0) + 15) / 30) * 30
    return math.max(0, math.min(maximum or 1440, value))
end

function LV.Store:NormalizeHistoricalRaidTimes(record)
    if type(record) ~= "table" then
        return 0
    end

    local repaired = 0
    local graceSeconds = ((record.cfg and tonumber(record.cfg.endGrace)) or 0) * 60
    for _, raid in pairs(record.r or {}) do
        if type(raid) == "table" and raid.lastSource == "ui_edit" then
            local endedAt = tonumber(raid.en)
            local scheduledEndAt = tonumber(raid.set)
            if endedAt and scheduledEndAt then
                local maximumEndAt = scheduledEndAt + graceSeconds
                if endedAt > maximumEndAt then
                    raid.en = maximumEndAt
                    repaired = repaired + 1
                end
            end
        end
    end
    return repaired
end

local function storedPlayerName(record, nameID)
    nameID = tonumber(nameID)
    return nameID and LV.Util:Trim(record.d and record.d.n and record.d.n[nameID]) or ""
end

local function storedPlayerShortKey(record, nameID)
    local name = storedPlayerName(record, nameID)
    return name ~= "" and LV.Util:ShortName(name):lower() or nil
end

local function addPlayerCandidate(record, candidates, nameID)
    nameID = tonumber(nameID)
    local shortKey = nameID and storedPlayerShortKey(record, nameID)
    if not shortKey then
        return
    end
    candidates[shortKey] = candidates[shortKey] or {}
    candidates[shortKey][nameID] = true
end

local function uniquePlayerCandidate(candidates, shortKey)
    local found
    for nameID in pairs((shortKey and candidates[shortKey]) or {}) do
        if found and found ~= nameID then
            return nil
        end
        found = nameID
    end
    return found
end

local function removePlayerFromArray(list, nameID)
    local removed = 0
    if type(list) ~= "table" then
        return removed
    end
    for index = #list, 1, -1 do
        if tonumber(list[index]) == nameID then
            table.remove(list, index)
            removed = removed + 1
        end
    end
    return removed
end

function LV.Store:RepairSyntheticPlayerAliases(record)
    if type(record) ~= "table" then
        return 0, 0
    end
    record.mig = type(record.mig) == "table" and record.mig or {}
    if (tonumber(record.mig.palias) or 0) >= PLAYER_ALIAS_MIGRATION_VERSION then
        return 0, 0
    end

    local evidence = {}
    local raidCandidates = {}
    local function rememberEvidence(nameID, candidates)
        nameID = tonumber(nameID)
        if nameID and storedPlayerName(record, nameID) ~= "" then
            evidence[nameID] = true
            if candidates then
                addPlayerCandidate(record, candidates, nameID)
            end
        end
    end

    for nameID in pairs(record.gr or {}) do
        rememberEvidence(nameID)
    end
    for _, team in ipairs((record.cfg and record.cfg.teams) or {}) do
        for nameID in pairs((type(team) == "table" and team.ro) or {}) do
            rememberEvidence(nameID)
        end
    end
    for raidID, raid in pairs(record.r or {}) do
        if type(raid) == "table" then
            local candidates = {}
            raidCandidates[tostring(raidID)] = candidates
            for _, map in ipairs({ raid.p, raid.b, raid.late, raid.out, raid.noshow }) do
                for nameID in pairs(map or {}) do
                    rememberEvidence(nameID, candidates)
                end
            end
            for _, kill in ipairs(raid.kills or {}) do
                if type(kill) == "table" then
                    for _, list in ipairs({ kill.p, kill.bench, kill.late, kill.out, kill.noshow }) do
                        for _, nameID in pairs(list or {}) do
                            rememberEvidence(nameID, candidates)
                        end
                    end
                end
            end
        end
    end

    local aliases = {}
    local conflicts = {}
    local repaired = 0
    local function recordAlias(fromID, toID)
        if aliases[fromID] and aliases[fromID] ~= toID then
            conflicts[fromID] = true
        else
            aliases[fromID] = toID
        end
    end
    local function repairLinkedField(row, field, candidates)
        local fromID = type(row) == "table" and tonumber(row[field]) or nil
        local shortKey = fromID and storedPlayerShortKey(record, fromID)
        local toID = shortKey and uniquePlayerCandidate(candidates or {}, shortKey) or nil
        if fromID and toID and fromID ~= toID then
            row[field] = toID
            recordAlias(fromID, toID)
            repaired = repaired + 1
        end
    end

    for _, row in ipairs(record.l or {}) do
        if type(row) == "table" then
            local candidates = raidCandidates[tostring(row.sid or "")]
            if candidates then
                repairLinkedField(row, "p", candidates)
                for _, roll in ipairs(row.rb or {}) do
                    repairLinkedField(roll, "p", candidates)
                end
            end
        end
    end
    for _, row in ipairs(record.t or {}) do
        if type(row) == "table" then
            local candidates = raidCandidates[tostring(row.sid or "")]
            if candidates then
                repairLinkedField(row, "f", candidates)
                repairLinkedField(row, "to", candidates)
            end
        end
    end

    for fromID in pairs(conflicts) do
        aliases[fromID] = nil
    end
    for fromID, toID in pairs(aliases) do
        if not evidence[fromID] then
            for _, team in ipairs((record.cfg and record.cfg.teams) or {}) do
                if type(team) == "table" and tonumber(team.rby) == fromID then
                    team.rby = toID
                end
            end
            for _, raid in pairs(record.r or {}) do
                if type(raid) == "table" and tonumber(raid.by) == fromID then
                    raid.by = toID
                end
            end
            for _, row in ipairs(record.l or {}) do
                if type(row) == "table" and tonumber(row.by) == fromID then
                    row.by = toID
                end
            end
            for _, row in ipairs(record.t or {}) do
                if type(row) == "table" and tonumber(row.by) == fromID then
                    row.by = toID
                end
            end
            for _, override in pairs(record.o or {}) do
                if type(override) == "table" then
                    if tonumber(override.main) == fromID then
                        override.main = toID
                    end
                    if tonumber(override.by) == fromID then
                        override.by = toID
                    end
                end
            end
            if record.pc and record.pc[fromID] then
                record.pc[toID] = record.pc[toID] or record.pc[fromID]
                record.pc[fromID] = nil
            end
            if record.o then
                record.o[fromID] = nil
            end
        end
    end

    local function stillReferenced(nameID)
        if (record.gr and record.gr[nameID]) or (record.o and record.o[nameID]) or (record.pc and record.pc[nameID]) then
            return true
        end
        for _, team in ipairs((record.cfg and record.cfg.teams) or {}) do
            if type(team) == "table" and ((team.ro and team.ro[nameID]) or tonumber(team.rby) == nameID) then
                return true
            end
        end
        for _, raid in pairs(record.r or {}) do
            if type(raid) == "table" then
                if tonumber(raid.by) == nameID then
                    return true
                end
                for _, map in ipairs({ raid.p, raid.b, raid.late, raid.out, raid.noshow }) do
                    if type(map) == "table" and map[nameID] then
                        return true
                    end
                end
                for _, kill in ipairs(raid.kills or {}) do
                    if type(kill) == "table" then
                        for _, list in ipairs({ kill.p, kill.bench, kill.late, kill.out, kill.noshow }) do
                            for _, candidateID in pairs(list or {}) do
                                if tonumber(candidateID) == nameID then
                                    return true
                                end
                            end
                        end
                    end
                end
            end
        end
        for _, row in ipairs(record.l or {}) do
            if type(row) == "table" then
                if tonumber(row.p) == nameID or tonumber(row.by) == nameID then
                    return true
                end
                for _, roll in ipairs(row.rb or {}) do
                    if type(roll) == "table" and tonumber(roll.p) == nameID then
                        return true
                    end
                end
            end
        end
        for _, row in ipairs(record.t or {}) do
            if type(row) == "table" and (tonumber(row.f) == nameID or tonumber(row.to) == nameID or tonumber(row.by) == nameID) then
                return true
            end
        end
        for _, override in pairs(record.o or {}) do
            if type(override) == "table" and (tonumber(override.main) == nameID or tonumber(override.by) == nameID) then
                return true
            end
        end
        return false
    end

    local removed = 0
    for fromID in pairs(aliases) do
        if not evidence[fromID] and not stillReferenced(fromID) and record.d and record.d.n then
            record.d.n[fromID] = ""
            removed = removed + 1
        end
    end
    record.mig.palias = PLAYER_ALIAS_MIGRATION_VERSION
    return repaired, removed
end

function LV.Store:Initialize()
    if type(LootViewerDB) ~= "table" then
        LootViewerDB = {}
    end

    LootViewerDB.v = LV.Constants.DB_VERSION
    ensureTable(LootViewerDB, "g")
    ensureTable(LootViewerDB, "c")
    ensureTable(LootViewerDB, "a")
    LV.Util:CopyDefaults(LootViewerDB.a, LV.Constants.DEFAULTS.account)

    local dungeon = ensureTable(LootViewerDB, "m")
    dungeon.v = LV.Constants.DB_VERSION
    ensureTable(dungeon, "d")
    ensureTable(dungeon.d, "n")
    ensureTable(dungeon.d, "i")
    ensureTable(dungeon.d, "s")
    ensureTable(dungeon, "r")
    ensureTable(dungeon, "l")
    ensureTable(dungeon, "b")
    ensureTable(dungeon, "t")
    ensureTable(dungeon, "next")
    dungeon.next.run = tonumber(dungeon.next.run) or 1
    dungeon.next.loot = tonumber(dungeon.next.loot) or 1
    dungeon.next.bonus = tonumber(dungeon.next.bonus) or 1
    dungeon.next.trade = tonumber(dungeon.next.trade) or 1

    self.db = LootViewerDB
    self.runtime = { rev = {}, dungeonRev = { n = {}, i = {}, s = {} } }
    self:EnsureDungeonReverseMaps(dungeon)
end

function LV.Store:AccountConfig()
    self:InitializeIfNeeded()
    return self.db.a
end

function LV.Store:DungeonRecord()
    self:InitializeIfNeeded()
    return self.db.m
end

function LV.Store:EnsureDungeonReverseMaps(record)
    if not self.runtime or not self.runtime.dungeonRev then
        return
    end
    for _, kind in ipairs({ "n", "i", "s" }) do
        wipe(self.runtime.dungeonRev[kind])
        for index, value in ipairs((record.d and record.d[kind]) or {}) do
            if value and value ~= "" then
                self.runtime.dungeonRev[kind][value] = index
            end
        end
    end
end

function LV.Store:DungeonDictionaryID(kind, value)
    value = LV.Util:Trim(value)
    if value == "" then
        return nil
    end
    local record = self:DungeonRecord()
    local dictionary = record.d[kind]
    local reverse = self.runtime.dungeonRev[kind]
    local existing = reverse[value]
    if existing then
        return existing
    end
    local id = #dictionary + 1
    dictionary[id] = value
    reverse[value] = id
    return id
end

function LV.Store:DungeonDictionaryValue(kind, id)
    local record = self:DungeonRecord()
    id = tonumber(id)
    return id and record.d[kind][id] or ""
end

function LV.Store:DungeonNameID(name)
    return self:DungeonDictionaryID("n", name)
end

function LV.Store:DungeonItemID(itemLink)
    return self:DungeonDictionaryID("i", LV.Util:ItemKey(itemLink))
end

function LV.Store:DungeonStringID(value)
    return self:DungeonDictionaryID("s", value)
end

function LV.Store:GuildRecord(guildKey)
    if not guildKey or guildKey == "" then
        return nil
    end

    self:InitializeIfNeeded()

    local guilds = self.db.g
    local record = guilds[guildKey]
    if type(record) ~= "table" then
        record = {
            v = LV.Constants.DB_VERSION,
            cfg = {},
            d = { n = {}, i = {}, s = {} },
            gr = {},
            r = {},
            l = {},
            t = {},
            o = {},
            x = {},
            pc = {},
            next = { raid = 1, loot = 1, trade = 1 },
        }
        guilds[guildKey] = record
    end

    record.v = LV.Constants.DB_VERSION
    LV.Util:CopyDefaults(record, { cfg = LV.Constants.DEFAULTS.cfg })
    if record.cfg.authority == "rank" then
        record.cfg.authority = "trusted"
    end
    if LV.Util:Trim(record.cfg.whisper):lower() == "bench" then
        record.cfg.whisper = "standby"
    end
    ensureTable(record, "d")
    ensureTable(record.d, "n")
    ensureTable(record.d, "i")
    ensureTable(record.d, "s")
    ensureTable(record, "gr")
    ensureTable(record, "r")
    ensureTable(record, "l")
    ensureTable(record, "t")
    ensureTable(record, "o")
    ensureTable(record, "x")
    ensureTable(record, "pc")
    ensureTable(record, "next")
    record.next.raid = tonumber(record.next.raid) or 1
    record.next.loot = tonumber(record.next.loot) or 1
    record.next.trade = tonumber(record.next.trade) or 1
    self:NormalizeTeams(record)
    local repairedAliases, removedAliases = self:RepairSyntheticPlayerAliases(record)
    self:NormalizeHistoricalRaidTimes(record)

    self:EnsureReverseMaps(guildKey, record)
    if repairedAliases > 0 or removedAliases > 0 then
        LV:Print("Repaired " .. tostring(repairedAliases) .. " player reference(s) and removed "
            .. tostring(removedAliases) .. " synthetic player alias(es).")
    end
    return record
end

function LV.Store:UniqueTeamID(cfg, rawName)
    local base = LV.Util:NormalizeSlug(rawName)
    if base == "" then
        base = "team"
    end

    local used = {}
    used[LV.Constants.PUG_TEAM_ID] = true
    for _, team in ipairs(cfg.teams or {}) do
        if type(team) == "table" and team.id then
            used[team.id] = true
        end
    end

    if not used[base] then
        return base
    end

    local suffix = 2
    while used[base .. "-" .. suffix] do
        suffix = suffix + 1
    end

    return base .. "-" .. suffix
end

function LV.Store:DefaultTeamColor()
    return {
        r = DEFAULT_TEAM_COLOR.r,
        g = DEFAULT_TEAM_COLOR.g,
        b = DEFAULT_TEAM_COLOR.b,
        a = DEFAULT_TEAM_COLOR.a,
    }
end

function LV.Store:NormalizeTeamColor(color)
    if type(color) ~= "table" then
        return self:DefaultTeamColor()
    end

    return {
        r = clampColor(color.r or color[1], DEFAULT_TEAM_COLOR.r),
        g = clampColor(color.g or color[2], DEFAULT_TEAM_COLOR.g),
        b = clampColor(color.b or color[3], DEFAULT_TEAM_COLOR.b),
        a = clampColor(color.a or color[4], DEFAULT_TEAM_COLOR.a),
    }
end

function LV.Store:NormalizeTeams(record)
    local cfg = record.cfg
    if type(cfg.teams) ~= "table" then
        cfg.teams = {}
    end
    for index = #cfg.teams, 1, -1 do
        local team = cfg.teams[index]
        local teamID = type(team) == "table" and LV.Util:NormalizeSlug(team.id or team.name) or ""
        if teamID == LV.Constants.PUG_TEAM_ID then
            table.remove(cfg.teams, index)
        end
    end
    if type(cfg.teams) ~= "table" or #cfg.teams == 0 then
        cfg.teams = {
            {
                id = "main",
                name = "Main",
                tz = "realm",
                clock24 = false,
                schedules = {},
            },
        }
    end

    local seen = {}
    for index, team in ipairs(cfg.teams) do
        if type(team) ~= "table" then
            team = {}
            cfg.teams[index] = team
        end

        team.name = LV.Util:Trim(team.name)
        if team.name == "" then
            team.name = index == 1 and "Main" or ("Team " .. index)
        end

        team.id = LV.Util:NormalizeSlug(team.id or team.name)
        if team.id == "" or seen[team.id] then
            team.id = self:UniqueTeamID(cfg, team.name)
        end
        seen[team.id] = true

        team.tz = LV.Util:NormalizeTimezone(team.tz)
        team.clock24 = team.clock24 == true or tonumber(team.clock24) == 1

        if type(team.schedules) ~= "table" then
            team.schedules = {}
        end
        for _, slot in ipairs(team.schedules) do
            if type(slot) == "table" then
                local startMinute = snapScheduleMinute(((tonumber(slot.h) or 20) * 60) + (tonumber(slot.m) or 0), 1410)
                slot.h = math.floor(startMinute / 60)
                slot.m = startMinute % 60
                slot.d = math.max(30, snapScheduleMinute(slot.d or 180, 1440))
            end
        end
        team.excludeSync = team.excludeSync == true or tonumber(team.excludeSync) == 1
        team.color = self:NormalizeTeamColor(team.color)
        local roster = type(team.ro) == "table" and team.ro or {}
        local normalizedRoster = {}
        for rawNameID, assignment in pairs(roster) do
            local nameID = tonumber(rawNameID)
            if nameID and type(record.d) == "table" and type(record.d.n) == "table"
                and LV.Util:Trim(record.d.n[nameID]) ~= "" then
                assignment = type(assignment) == "table" and assignment or {}
                local primary = tostring(assignment.p or ""):lower()
                local secondary = tostring(assignment.s or ""):lower()
                local rosterType = tostring(assignment.t or ""):lower()
                if primary == "helper" then
                    rosterType = "helper"
                    primary = TEAM_ROSTER_ROLES[secondary] and secondary or ""
                    secondary = ""
                end
                assignment.t = TEAM_ROSTER_TYPES[rosterType] and rosterType or "raider"
                assignment.p = TEAM_ROSTER_ROLES[primary] and primary or nil
                assignment.s = TEAM_ROSTER_ROLES[secondary] and secondary ~= assignment.p and secondary or nil
                normalizedRoster[nameID] = assignment
            end
        end
        wipe(roster)
        for nameID, assignment in pairs(normalizedRoster) do
            roster[nameID] = assignment
        end
        team.ro = roster
    end

    if type(cfg.schedules) == "table" and #cfg.schedules > 0 and not cfg._teamsMigrated then
        local main = cfg.teams[1]
        for _, slot in ipairs(cfg.schedules) do
            table.insert(main.schedules, slot)
        end
        cfg._teamsMigrated = 1
    end

    if not self:GetTeamByID(record, cfg.selectedTeam) then
        cfg.selectedTeam = cfg.teams[1].id
    end
end

function LV.Store:TeamRoster(guildKey, teamID)
    local record = self:GuildRecord(guildKey)
    local team = record and self:GetTeamByID(record, teamID)
    if not team or self:IsGlobalPugTeam(team) then
        return nil
    end
    team.ro = type(team.ro) == "table" and team.ro or {}
    return team.ro, team
end

function LV.Store:SetTeamRosterPlayer(guildKey, teamID, nameID, rosterType, primaryRole, secondaryRole)
    local roster = self:TeamRoster(guildKey, teamID)
    nameID = tonumber(nameID)
    if not roster or not nameID or self:DictionaryValue(guildKey, "n", nameID) == "" then
        return nil
    end
    rosterType = tostring(rosterType or "raider"):lower()
    primaryRole = tostring(primaryRole or ""):lower()
    secondaryRole = tostring(secondaryRole or ""):lower()
    if not TEAM_ROSTER_TYPES[rosterType] then
        rosterType = "raider"
    end
    if not TEAM_ROSTER_ROLES[primaryRole] then
        primaryRole = nil
    end
    if not TEAM_ROSTER_ROLES[secondaryRole] or secondaryRole == primaryRole then
        secondaryRole = nil
    end
    local assignment = roster[nameID]
    if type(assignment) ~= "table" then
        assignment = {}
        roster[nameID] = assignment
    end
    assignment.t = rosterType
    assignment.p = primaryRole
    assignment.s = secondaryRole
    return assignment
end

function LV.Store:RemoveTeamRosterPlayer(guildKey, teamID, nameID)
    local roster = self:TeamRoster(guildKey, teamID)
    nameID = tonumber(nameID)
    if not roster or not nameID or roster[nameID] == nil then
        return false
    end
    roster[nameID] = nil
    return true
end

function LV.Store:GetTeamByID(recordOrCfg, teamID)
    if tostring(teamID or "") == LV.Constants.PUG_TEAM_ID then
        return GLOBAL_PUG_TEAM, 0
    end
    local cfg = recordOrCfg and recordOrCfg.cfg or recordOrCfg
    if type(cfg) ~= "table" then
        return nil
    end

    for index, team in ipairs(cfg.teams or {}) do
        if type(team) == "table" and team.id == teamID then
            return team, index
        end
    end

    return nil
end

function LV.Store:GlobalPugTeam()
    return GLOBAL_PUG_TEAM
end

function LV.Store:IsGlobalPugTeam(teamOrID)
    local teamID = type(teamOrID) == "table" and teamOrID.id or teamOrID
    return tostring(teamID or "") == LV.Constants.PUG_TEAM_ID
end

function LV.Store:GetSelectedTeam(recordOrCfg)
    local cfg = recordOrCfg and recordOrCfg.cfg or recordOrCfg
    if type(cfg) ~= "table" then
        return nil
    end

    return self:GetTeamByID(cfg, cfg.selectedTeam) or cfg.teams[1]
end

function LV.Store:IsTeamExcludedFromSync(guildKey, teamID)
    if self:IsGlobalPugTeam(teamID) then
        return true
    end
    local record = self:GuildRecord(guildKey)
    local team = record and self:GetTeamByID(record, teamID or "main")
    return team and team.excludeSync == true or false
end

function LV.Store:IsRaidExcludedFromSync(guildKey, raidOrID)
    local record = self:GuildRecord(guildKey)
    local raid = type(raidOrID) == "table" and raidOrID or (record and record.r and record.r[raidOrID])
    return type(raid) == "table" and self:IsTeamExcludedFromSync(guildKey, raid.team or "main") or false
end

function LV.Store:AddRaidTeam(guildKey, teamName)
    local record = self:GuildRecord(guildKey)
    if not record then
        return nil
    end

    teamName = LV.Util:Trim(teamName)
    if teamName == "" then
        teamName = "Team " .. tostring(#record.cfg.teams + 1)
    end
    if LV.Util:NormalizeSlug(teamName) == LV.Constants.PUG_TEAM_ID then
        LV:Print("Pugs is a reserved account-wide raid team.")
        return nil
    end

    local team = {
        id = self:UniqueTeamID(record.cfg, teamName),
        name = teamName,
        tz = "realm",
        clock24 = false,
        color = self:DefaultTeamColor(),
        schedules = {},
    }
    table.insert(record.cfg.teams, team)
    record.cfg.selectedTeam = team.id
    return team
end

function LV.Store:InitializeIfNeeded()
    if not self.db then
        self:Initialize()
    end
end

function LV.Store:EnsureReverseMaps(guildKey, record)
    self.runtime.rev[guildKey] = self.runtime.rev[guildKey] or { n = {}, i = {}, s = {} }
    local rev = self.runtime.rev[guildKey]

    for _, kind in ipairs({ "n", "i", "s" }) do
        wipe(rev[kind])
        for index, value in ipairs(record.d[kind] or {}) do
            if value and value ~= "" then
                rev[kind][value] = index
            end
        end
    end
end

function LV.Store:DictionaryID(guildKey, kind, value)
    value = LV.Util:Trim(value)
    if value == "" then
        return nil
    end

    local record = self:GuildRecord(guildKey)
    if not record then
        return nil
    end

    local dict = record.d[kind]
    local rev = self.runtime.rev[guildKey] and self.runtime.rev[guildKey][kind]
    if not dict or not rev then
        return nil
    end

    local existing = rev[value]
    if existing then
        return existing
    end

    local id = #dict + 1
    dict[id] = value
    rev[value] = id
    return id
end

function LV.Store:DictionaryValue(guildKey, kind, id)
    local record = self:GuildRecord(guildKey)
    id = tonumber(id)
    if not record or not id then
        return ""
    end
    return record.d[kind][id] or ""
end

function LV.Store:NameID(guildKey, name)
    return self:DictionaryID(guildKey, "n", name)
end

function LV.Store:GuildBankNameID(guildKey)
    local record = self:GuildRecord(guildKey)
    if not record or type(record.d) ~= "table" or type(record.d.n) ~= "table" then
        return nil
    end

    for nameID, fullName in ipairs(record.d.n) do
        if LV.Util:Trim(fullName):lower() == "guild bank" then
            return nameID
        end
    end

    return self:NameID(guildKey, "Guild Bank")
end

function LV.Store:ItemID(guildKey, itemLink)
    return self:DictionaryID(guildKey, "i", LV.Util:ItemKey(itemLink))
end

function LV.Store:StringID(guildKey, value)
    return self:DictionaryID(guildKey, "s", value)
end

function LV.Store:NewID(record, kind, prefix)
    local nextTable = ensureTable(record, "next")
    local nextID = tonumber(nextTable[kind]) or 1
    nextTable[kind] = nextID + 1
    return (prefix or kind) .. tostring(nextID)
end

function LV.Store:AddRosterMember(guildKey, name, fields)
    local record = self:GuildRecord(guildKey)
    local nameID = self:NameID(guildKey, name)
    if not record or not nameID then
        return nil
    end

    local entry = record.gr[nameID]
    if type(entry) ~= "table" then
        entry = {}
        record.gr[nameID] = entry
    end

    for key, value in pairs(fields or {}) do
        entry[key] = value
    end
    entry.ts = LV.Util:Now()

    if entry.c and entry.c ~= "" then
        self:SetPlayerClass(guildKey, nameID, entry.c)
    end

    return entry
end

function LV.Store:PlayerRows(guildKey)
    local record = self:GuildRecord(guildKey)
    local rowsByID = {}
    local function include(nameID, source)
        nameID = tonumber(nameID)
        local fullName = nameID and storedPlayerName(record, nameID) or ""
        if fullName == "" then
            return
        end
        local row = rowsByID[nameID]
        if not row then
            row = {
                id = nameID,
                fullName = fullName,
                name = LV.Util:ShortName(fullName),
            }
            rowsByID[nameID] = row
        end
        row[source] = true
    end

    for nameID in pairs((record and record.gr) or {}) do
        include(nameID, "guild")
    end
    for _, team in ipairs((record and record.cfg and record.cfg.teams) or {}) do
        if type(team) == "table" then
            for nameID in pairs(team.ro or {}) do
                include(nameID, "roster")
            end
            include(team.rby, "history")
        end
    end
    for _, raid in pairs((record and record.r) or {}) do
        if type(raid) == "table" then
            include(raid.by, "history")
            for _, map in ipairs({ raid.p, raid.b, raid.late, raid.out, raid.noshow }) do
                for nameID in pairs(map or {}) do
                    include(nameID, "attendance")
                end
            end
            for _, kill in ipairs(raid.kills or {}) do
                if type(kill) == "table" then
                    for _, list in ipairs({ kill.p, kill.bench, kill.late, kill.out, kill.noshow }) do
                        for _, nameID in pairs(list or {}) do
                            include(nameID, "attendance")
                        end
                    end
                end
            end
        end
    end
    for _, row in ipairs((record and record.l) or {}) do
        if type(row) == "table" then
            include(row.p, "loot")
            include(row.by, "history")
            for _, roll in ipairs(row.rb or {}) do
                if type(roll) == "table" then
                    include(roll.p, "loot")
                end
            end
        end
    end
    for _, row in ipairs((record and record.t) or {}) do
        if type(row) == "table" then
            include(row.f, "trade")
            include(row.to, "trade")
            include(row.by, "history")
        end
    end
    for nameID, override in pairs((record and record.o) or {}) do
        include(nameID, "override")
        if type(override) == "table" then
            include(override.main, "override")
            include(override.by, "history")
        end
    end

    local rows = {}
    for _, row in pairs(rowsByID) do
        rows[#rows + 1] = row
    end
    table.sort(rows, function(a, b)
        return a.fullName:lower() < b.fullName:lower()
    end)
    return rows
end

function LV.Store:DeletePlayer(guildKey, nameID)
    local record = self:GuildRecord(guildKey)
    nameID = tonumber(nameID)
    local fullName = record and nameID and storedPlayerName(record, nameID) or ""
    if fullName == "" then
        return false, "Player not found."
    end

    local removed = { raids = 0, loot = 0, trades = 0, links = 0 }
    record.gr[nameID] = nil
    record.pc[nameID] = nil
    record.o[nameID] = nil

    for _, team in ipairs((record.cfg and record.cfg.teams) or {}) do
        if type(team) == "table" then
            if type(team.ro) == "table" and team.ro[nameID] then
                team.ro[nameID] = nil
                removed.links = removed.links + 1
            end
            if tonumber(team.rby) == nameID then
                team.rby = nil
            end
        end
    end
    for _, raid in pairs(record.r or {}) do
        if type(raid) == "table" then
            local removedFromRaid = false
            for _, map in ipairs({ raid.p, raid.b, raid.late, raid.out, raid.noshow }) do
                if type(map) == "table" and map[nameID] ~= nil then
                    map[nameID] = nil
                    removedFromRaid = true
                end
            end
            for _, kill in ipairs(raid.kills or {}) do
                if type(kill) == "table" then
                    for _, list in ipairs({ kill.p, kill.bench, kill.late, kill.out, kill.noshow }) do
                        if removePlayerFromArray(list, nameID) > 0 then
                            removedFromRaid = true
                        end
                    end
                end
            end
            if tonumber(raid.by) == nameID then
                raid.by = nil
            end
            if removedFromRaid then
                removed.raids = removed.raids + 1
            end
        end
    end

    local removedLootIDs = {}
    for index = #(record.l or {}), 1, -1 do
        local row = record.l[index]
        if type(row) == "table" and tonumber(row.p) == nameID then
            if row.id then
                removedLootIDs[tostring(row.id)] = true
            end
            table.remove(record.l, index)
            removed.loot = removed.loot + 1
        elseif type(row) == "table" then
            if tonumber(row.by) == nameID then
                row.by = nil
            end
            for rollIndex = #(row.rb or {}), 1, -1 do
                if type(row.rb[rollIndex]) == "table" and tonumber(row.rb[rollIndex].p) == nameID then
                    table.remove(row.rb, rollIndex)
                    removed.links = removed.links + 1
                end
            end
        end
    end
    for index = #(record.t or {}), 1, -1 do
        local row = record.t[index]
        if type(row) == "table" and (
            tonumber(row.f) == nameID
            or tonumber(row.to) == nameID
            or removedLootIDs[tostring(row.loot or "")]
        ) then
            table.remove(record.t, index)
            removed.trades = removed.trades + 1
        elseif type(row) == "table" and tonumber(row.by) == nameID then
            row.by = nil
        end
    end
    for _, override in pairs(record.o or {}) do
        if type(override) == "table" then
            if tonumber(override.main) == nameID then
                override.main = nil
                override.tag = "guild"
                removed.links = removed.links + 1
            end
            if tonumber(override.by) == nameID then
                override.by = nil
            end
        end
    end

    record.d.n[nameID] = ""
    self:EnsureReverseMaps(guildKey, record)
    return true, fullName, removed
end

function LV.Store:SetPlayerClass(guildKey, nameOrID, className)
    className = LV.Util:Trim(className)
    if className == "" then
        return
    end

    local record = self:GuildRecord(guildKey)
    if not record then
        return
    end

    local nameID = tonumber(nameOrID)
    if not nameID then
        nameID = self:NameID(guildKey, nameOrID)
    end
    if not nameID then
        return
    end

    record.pc[nameID] = self:StringID(guildKey, className)
end

function LV.Store:PlayerClass(guildKey, nameID)
    local record = self:GuildRecord(guildKey)
    nameID = tonumber(nameID)
    if not record or not nameID then
        return ""
    end

    local classID = record.pc and record.pc[nameID]
    if classID then
        return self:DictionaryValue(guildKey, "s", classID)
    end

    local rosterEntry = record.gr and record.gr[nameID]
    if type(rosterEntry) == "table" then
        return LV.Util:Trim(rosterEntry.c)
    end

    return ""
end

function LV.Store:GetConfig(guildKey)
    local record = self:GuildRecord(guildKey)
    return record and record.cfg or nil
end

function LV.Store:Prune(guildKey, olderThanSeconds)
    local record = self:GuildRecord(guildKey)
    olderThanSeconds = tonumber(olderThanSeconds)
    if not record or not olderThanSeconds or olderThanSeconds <= 0 then
        return 0
    end

    local cutoff = LV.Util:Now() - olderThanSeconds
    local removed = 0

    local function pruneArray(list, timestampKey)
        for index = #list, 1, -1 do
            local row = list[index]
            if type(row) == "table" and tonumber(row[timestampKey]) and tonumber(row[timestampKey]) < cutoff then
                table.remove(list, index)
                removed = removed + 1
            end
        end
    end

    pruneArray(record.l, "ts")
    pruneArray(record.t, "ts")

    for raidID, raid in pairs(record.r) do
        if type(raid) == "table" and tonumber(raid.st) and tonumber(raid.st) < cutoff then
            record.r[raidID] = nil
            if record.cur == raidID then
                record.cur = nil
            end
            removed = removed + 1
        end
    end

    return removed
end

function LV.Store:PruneAllHistory(guildKey)
    local record = self:GuildRecord(guildKey)
    if not record then
        return 0
    end

    local removed = 0
    for _, list in ipairs({ record.l, record.t }) do
        removed = removed + #(list or {})
        wipe(list)
    end
    for raidID, _ in pairs(record.r or {}) do
        record.r[raidID] = nil
        removed = removed + 1
    end
    record.cur = nil
    return removed
end

function LV.Store:PruneSeason(guildKey, seasonID)
    local record = self:GuildRecord(guildKey)
    if not record or not LV.Seasons:IsSeasonID(seasonID) then
        return 0
    end

    local removed = 0
    local removedRaidIDs = {}
    local removedLootIDs = {}
    for raidID, raid in pairs(record.r or {}) do
        if type(raid) == "table" and LV.Seasons:RaidSeasonID(guildKey, raid) == seasonID then
            removedRaidIDs[raidID] = true
            if raid.id then removedRaidIDs[raid.id] = true end
            record.r[raidID] = nil
            removed = removed + 1
        end
    end
    for index = #(record.l or {}), 1, -1 do
        local row = record.l[index]
        if type(row) == "table" and (removedRaidIDs[row.sid] or LV.Seasons:EventSeasonID(guildKey, record, row) == seasonID) then
            if row.id then removedLootIDs[row.id] = true end
            table.remove(record.l, index)
            removed = removed + 1
        end
    end
    for index = #(record.t or {}), 1, -1 do
        local row = record.t[index]
        if type(row) == "table" and (removedRaidIDs[row.sid] or removedLootIDs[row.loot]) then
            table.remove(record.t, index)
            removed = removed + 1
        end
    end
    if removedRaidIDs[record.cur] then
        record.cur = nil
    end
    return removed
end

LV:RegisterEvent("ADDON_LOADED", function(_, loadedAddonName)
    if loadedAddonName == LV.name then
        LV.Store:Initialize()
    end
end)
