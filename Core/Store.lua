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

function LV.Store:Initialize()
    if type(LootViewerDB) ~= "table" then
        LootViewerDB = {}
    end

    LootViewerDB.v = LV.Constants.DB_VERSION
    ensureTable(LootViewerDB, "g")
    ensureTable(LootViewerDB, "c")

    self.db = LootViewerDB
    self.runtime = { rev = {} }
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

    self:EnsureReverseMaps(guildKey, record)
    return record
end

function LV.Store:UniqueTeamID(cfg, rawName)
    local base = LV.Util:NormalizeSlug(rawName)
    if base == "" then
        base = "team"
    end

    local used = {}
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
    if type(cfg.teams) ~= "table" or #cfg.teams == 0 then
        cfg.teams = {
            {
                id = "main",
                name = "Main",
                tz = "local",
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

        team.tz = LV.Util:Trim(team.tz)
        if team.tz == "" then
            team.tz = "local"
        end

        if type(team.schedules) ~= "table" then
            team.schedules = {}
        end
        team.color = self:NormalizeTeamColor(team.color)
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

function LV.Store:GetTeamByID(recordOrCfg, teamID)
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

function LV.Store:GetSelectedTeam(recordOrCfg)
    local cfg = recordOrCfg and recordOrCfg.cfg or recordOrCfg
    if type(cfg) ~= "table" then
        return nil
    end

    return self:GetTeamByID(cfg, cfg.selectedTeam) or cfg.teams[1]
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

    local team = {
        id = self:UniqueTeamID(record.cfg, teamName),
        name = teamName,
        tz = "local",
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
            removed = removed + 1
        end
    end

    return removed
end

LV:RegisterEvent("ADDON_LOADED", function(_, loadedAddonName)
    if loadedAddonName == LV.name then
        LV.Store:Initialize()
    end
end)
