local _, LV = ...

LV.DataSync = {}
LV.modules.DataSync = LV.DataSync

local CHUNK_SIZE = 180
local SEND_DELAY = 0.08
local SYNC_WINDOW_SECONDS = 60 * 86400

local syncKinds = {
    Q = true,
    A = true,
    D = true,
    C = true,
    N = true,
}

local statusMaps = {
    here = "p",
    bench = "b",
    late = "late",
    out = "out",
    noshow = "noshow",
}

local statusOrder = { "out", "noshow", "bench", "late", "here" }

local configBooleans = {
    enabled = true,
    prompt = true,
    tradeRaid = true,
}

local configNumbers = {
    promptBefore = true,
    promptAfter = true,
    promptTimeout = true,
    lateGrace = true,
    rankMin = true,
    rankMax = true,
    pruneDays = true,
}

local configStrings = {
    authority = true,
    whisper = true,
    selectedTeam = true,
}

local function split(text, separator)
    local out = {}
    local cursor = 1
    text = tostring(text or "")

    while true do
        local found = string.find(text, separator, cursor, true)
        if not found then
            out[#out + 1] = string.sub(text, cursor)
            break
        end

        out[#out + 1] = string.sub(text, cursor, found - 1)
        cursor = found + string.len(separator)
    end

    return out
end

local function encode(value)
    value = tostring(value or "")
    value = value:gsub("%%", "%%25")
    value = value:gsub("\031", "%%1F")
    value = value:gsub("\t", "%%09")
    value = value:gsub("\n", "%%0A")
    value = value:gsub("\r", "%%0D")
    value = value:gsub("|", "%%7C")
    value = value:gsub(",", "%%2C")
    value = value:gsub("=", "%%3D")
    return value
end

local function decode(value)
    return tostring(value or ""):gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16) or 0)
    end)
end

local function line(kind, fields)
    local parts = { kind }
    for _, item in ipairs(fields or {}) do
        parts[#parts + 1] = tostring(item[1]) .. "=" .. encode(item[2])
    end
    return table.concat(parts, "\t")
end

local function parseLine(raw)
    local parts = split(raw, "\t")
    local kind = parts[1]
    local fields = {}

    for index = 2, #parts do
        local part = parts[index]
        local equals = string.find(part, "=", 1, true)
        if equals then
            local key = string.sub(part, 1, equals - 1)
            fields[key] = decode(string.sub(part, equals + 1))
        end
    end

    return kind, fields
end

local function boolString(value)
    return value and "1" or "0"
end

local function numString(value)
    return string.format("%.4f", tonumber(value) or 0)
end

local function rollBreakdownMethodCount(list)
    local count = 0
    for _, entry in ipairs(list or {}) do
        if type(entry) == "table" then
            local roll = entry.r or entry.roll or entry.method
            if roll ~= nil then
                roll = tostring(roll)
                if roll ~= "" and not roll:match("^%d+$") then
                    count = count + 1
                end
            end
        end
    end
    return count
end

local function parseBool(value)
    value = tostring(value or ""):lower()
    return value == "1" or value == "true" or value == "yes"
end

local function sortedPairsByTimestamp(items, timestampKey)
    table.sort(items, function(a, b)
        local at = tonumber(a[timestampKey]) or 0
        local bt = tonumber(b[timestampKey]) or 0
        if at ~= bt then
            return at < bt
        end
        return tostring(a.id or "") < tostring(b.id or "")
    end)
end

local function mapStatus(raid, nameID)
    for _, status in ipairs(statusOrder) do
        local map = raid and raid[statusMaps[status]]
        if map and map[nameID] then
            return status, tonumber(map[nameID]) or 0
        end
    end
    return nil, 0
end

local function ensureRaidMaps(raid)
    raid.p = raid.p or {}
    raid.b = raid.b or {}
    raid.late = raid.late or {}
    raid.out = raid.out or {}
    raid.noshow = raid.noshow or {}
    raid.kills = raid.kills or {}
end

local function setRaidStatus(raid, nameID, status, timestamp)
    if not raid or not nameID or not statusMaps[status] then
        return false
    end

    ensureRaidMaps(raid)
    timestamp = tonumber(timestamp) or LV.Util:Now()

    local _, existingTS = mapStatus(raid, nameID)
    if existingTS > 0 and timestamp > 0 and existingTS > timestamp then
        return false
    end

    raid.p[nameID] = nil
    raid.b[nameID] = nil
    raid.late[nameID] = nil
    raid.out[nameID] = nil
    raid.noshow[nameID] = nil

    if status == "here" then
        raid.p[nameID] = timestamp
    elseif status == "bench" then
        raid.p[nameID] = timestamp
        raid.b[nameID] = timestamp
    elseif status == "late" then
        raid.p[nameID] = timestamp
        raid.late[nameID] = timestamp
    elseif status == "out" then
        raid.out[nameID] = timestamp
    elseif status == "noshow" then
        raid.noshow[nameID] = timestamp
    end

    return true
end

local function normalizedName(name)
    name = LV.Util:Trim(name)
    if name ~= "" and not name:find("-", 1, true) then
        local info = LV.Guild:CurrentInfo()
        name = name .. "-" .. ((info and info.realm) or LV.Util:RealmName())
    end
    return name
end

local function nameForID(guildKey, nameID)
    return LV.Store:DictionaryValue(guildKey, "n", nameID)
end

local function stringForID(guildKey, stringID)
    return LV.Store:DictionaryValue(guildKey, "s", stringID)
end

local function itemForID(guildKey, itemID)
    return LV.Store:DictionaryValue(guildKey, "i", itemID)
end

local function encodeStatusList(guildKey, map)
    local rows = {}
    for id, timestamp in pairs(map or {}) do
        local fullName = nameForID(guildKey, id)
        if fullName ~= "" then
            local rosterTag = LV.Guild:InferRosterTag(guildKey, id)
            rows[#rows + 1] = {
                fullName = fullName,
                text = fullName .. "|" .. tostring(timestamp or "") .. "|" .. LV.Store:PlayerClass(guildKey, id) .. "|" .. rosterTag,
            }
        end
    end
    table.sort(rows, function(a, b)
        return a.fullName:lower() < b.fullName:lower()
    end)

    local out = {}
    for _, row in ipairs(rows) do
        out[#out + 1] = row.text
    end
    return table.concat(out, ",")
end

local function encodeNameList(guildKey, list)
    local rows = {}
    for _, id in ipairs(list or {}) do
        local fullName = nameForID(guildKey, id)
        if fullName ~= "" then
            rows[#rows + 1] = fullName
        end
    end
    table.sort(rows, function(a, b)
        return a:lower() < b:lower()
    end)
    return table.concat(rows, ",")
end

local function decodeNameList(guildKey, value)
    local ids = {}
    if LV.Util:IsBlank(value) then
        return ids
    end

    for _, name in ipairs(split(value, ",")) do
        name = normalizedName(name)
        if name ~= "" then
            local nameID = LV.Store:NameID(guildKey, name)
            if nameID then
                ids[#ids + 1] = nameID
            end
        end
    end
    table.sort(ids)
    return ids
end

local function encodeRollBreakdown(guildKey, entries)
    local rows = {}
    for _, entry in ipairs(entries or {}) do
        if type(entry) == "table" and entry.p then
            local fullName = nameForID(guildKey, entry.p)
            if fullName ~= "" then
                local className = stringForID(guildKey, entry.cls)
                if className == "" then
                    className = LV.Store:PlayerClass(guildKey, entry.p)
                end
                rows[#rows + 1] = table.concat({
                    fullName,
                    className or "",
                    entry.r or "",
                    entry.raw or "",
                    entry.w and "1" or "",
                }, "|")
            end
        end
    end
    return table.concat(rows, ",")
end

local function decodeRollBreakdown(guildKey, value)
    local rows = {}
    if LV.Util:IsBlank(value) then
        return nil
    end

    for _, item in ipairs(split(value, ",")) do
        local parts = split(item, "|")
        local fullName = normalizedName(parts[1])
        if fullName ~= "" then
            local nameID = LV.Store:NameID(guildKey, fullName)
            local className = LV.Util:Trim(parts[2] or "")
            if className ~= "" then
                LV.Store:SetPlayerClass(guildKey, nameID, className)
            end
            rows[#rows + 1] = {
                p = nameID,
                cls = className ~= "" and LV.Store:StringID(guildKey, className) or nil,
                r = parts[3] or "",
                raw = parts[4] ~= "" and parts[4] or nil,
                w = tonumber(parts[5]) and 1 or nil,
            }
        end
    end

    return #rows > 0 and rows or nil
end

function LV.DataSync:IsSyncKind(kind)
    return syncKinds[kind] and true or false
end

function LV.DataSync:FormatCounts(counts)
    counts = counts or {}
    local prefix = counts.config and "config, " or ""
    return prefix
        .. tostring(counts.raids or 0) .. " raid(s), "
        .. tostring(counts.loot or 0) .. " loot, "
        .. tostring(counts.trades or 0) .. " trade(s)"
end

function LV.DataSync:TransferSummary(guildName, counts)
    counts = counts or {}
    local parts = {}
    if counts.config then
        parts[#parts + 1] = "Updated Guild Config"
    end
    parts[#parts + 1] = tostring(counts.raids or 0) .. " raid(s)"
    parts[#parts + 1] = tostring(counts.loot or 0) .. " loot(s)"
    parts[#parts + 1] = tostring(counts.trades or 0) .. " trade(s)"
    return tostring(guildName or "Guild") .. " Transfer Complete. " .. table.concat(parts, ", ")
end

function LV.DataSync:NormalizeTarget(target)
    target = LV.Util:Trim(target)
    if target ~= "" and not target:find("-", 1, true) then
        target = target .. "-" .. LV.Util:RealmName()
    end
    return target
end

function LV.DataSync:RefreshUI()
    if LV.UI and LV.UI.frame and LV.UI.frame:IsShown() and LV.UI.currentTab == "sync" then
        LV.UI:Refresh()
    end
end

function LV.DataSync:BuildExport(guildKey)
    local record = LV.Store:GuildRecord(guildKey)
    local cutoff = LV.Util:Now() - SYNC_WINDOW_SECONDS
    local counts = { config = false, raids = 0, loot = 0, trades = 0 }
    local lines = {
        line("H", {
            { "v", 1 },
            { "g", guildKey },
            { "from", LV.Util:PlayerFullName() },
            { "cutoff", cutoff },
            { "created", LV.Util:Now() },
        }),
    }

    if type(record.cfg) == "table" then
        local cfg = record.cfg
        counts.config = true
        lines[#lines + 1] = line("CFG", {
            { "enabled", boolString(cfg.enabled) },
            { "prompt", boolString(cfg.prompt) },
            { "promptBefore", cfg.promptBefore },
            { "promptAfter", cfg.promptAfter },
            { "promptTimeout", cfg.promptTimeout },
            { "lateGrace", cfg.lateGrace },
            { "authority", cfg.authority },
            { "rankMin", cfg.rankMin },
            { "rankMax", cfg.rankMax },
            { "tradeRaid", boolString(cfg.tradeRaid) },
            { "whisper", cfg.whisper },
            { "selectedTeam", cfg.selectedTeam },
            { "pruneDays", cfg.pruneDays },
        })

        for _, team in ipairs(cfg.teams or {}) do
            if type(team) == "table" then
                local color = LV.Store:NormalizeTeamColor(team.color)
                lines[#lines + 1] = line("TEAM", {
                    { "id", team.id },
                    { "name", team.name },
                    { "tz", team.tz },
                    { "cr", numString(color.r) },
                    { "cg", numString(color.g) },
                    { "cb", numString(color.b) },
                    { "ca", numString(color.a) },
                })

                for _, slot in ipairs(team.schedules or {}) do
                    if type(slot) == "table" then
                        lines[#lines + 1] = line("SCH", {
                            { "team", team.id },
                            { "w", slot.w },
                            { "h", slot.h },
                            { "m", slot.m },
                            { "d", slot.d },
                        })
                    end
                end
            end
        end
    end

    local raids = {}
    for raidID, raid in pairs((record and record.r) or {}) do
        if type(raid) == "table" and (tonumber(raid.st) or 0) >= cutoff then
            raids[#raids + 1] = raid
            raid.id = raid.id or raidID
        end
    end
    sortedPairsByTimestamp(raids, "st")

    for _, raid in ipairs(raids) do
        counts.raids = counts.raids + 1
        lines[#lines + 1] = line("R", {
            { "id", raid.id },
            { "st", raid.st },
            { "en", raid.en },
            { "z", stringForID(guildKey, raid.z) },
            { "iid", raid.iid },
            { "diff", stringForID(guildKey, raid.diff) },
            { "did", raid.did },
            { "team", raid.team },
            { "tn", stringForID(guildKey, raid.tn) },
            { "by", nameForID(guildKey, raid.by) },
            { "reason", raid.reason },
            { "adhoc", raid.adhoc },
            { "adDur", raid.adDur },
            { "adEnd", raid.adEnd },
            { "p", encodeStatusList(guildKey, raid.p) },
            { "b", encodeStatusList(guildKey, raid.b) },
            { "late", encodeStatusList(guildKey, raid.late) },
            { "out", encodeStatusList(guildKey, raid.out) },
            { "ns", encodeStatusList(guildKey, raid.noshow) },
        })

        for _, kill in ipairs(raid.kills or {}) do
            lines[#lines + 1] = line("K", {
                { "rid", raid.id },
                { "ts", kill.ts },
                { "e", kill.e },
                { "boss", stringForID(guildKey, kill.b) },
                { "d", kill.d },
                { "n", kill.n },
                { "p", encodeNameList(guildKey, kill.p) },
                { "bench", encodeNameList(guildKey, kill.bench) },
                { "late", encodeNameList(guildKey, kill.late) },
                { "out", encodeNameList(guildKey, kill.out) },
                { "ns", encodeNameList(guildKey, kill.noshow) },
            })
        end
    end

    local lootRows = {}
    for _, row in ipairs((record and record.l) or {}) do
        if type(row) == "table" and (tonumber(row.ts) or 0) >= cutoff then
            lootRows[#lootRows + 1] = row
        end
    end
    sortedPairsByTimestamp(lootRows, "ts")

    for _, row in ipairs(lootRows) do
        counts.loot = counts.loot + 1
        lines[#lines + 1] = line("L", {
            { "id", row.id },
            { "ts", row.ts },
            { "sid", row.sid },
            { "e", row.e },
            { "iid", row.iid },
            { "inst", stringForID(guildKey, row.inst) },
            { "boss", stringForID(guildKey, row.boss) },
            { "did", row.did },
            { "diff", stringForID(guildKey, row.diff) },
            { "p", nameForID(guildKey, row.p) },
            { "cls", stringForID(guildKey, row.cls) ~= "" and stringForID(guildKey, row.cls) or LV.Store:PlayerClass(guildKey, row.p) },
            { "item", itemForID(guildKey, row.item) },
            { "itemID", row.itemID },
            { "q", row.q },
            { "r", row.r },
            { "raw", row.raw },
            { "rb", encodeRollBreakdown(guildKey, row.rb) },
            { "src", row.src },
            { "boe", row.boe },
            { "wb", row.wb },
            { "tr", row.tr },
            { "by", nameForID(guildKey, row.by) },
        })
    end

    local tradeRows = {}
    for _, row in ipairs((record and record.t) or {}) do
        if type(row) == "table" and (tonumber(row.ts) or 0) >= cutoff then
            tradeRows[#tradeRows + 1] = row
        end
    end
    sortedPairsByTimestamp(tradeRows, "ts")

    for _, row in ipairs(tradeRows) do
        counts.trades = counts.trades + 1
        lines[#lines + 1] = line("T", {
            { "id", row.id },
            { "ts", row.ts },
            { "sid", row.sid },
            { "f", nameForID(guildKey, row.f) },
            { "to", nameForID(guildKey, row.to) },
            { "item", itemForID(guildKey, row.item) },
            { "itemID", row.itemID },
            { "loot", row.loot },
            { "src", row.src },
            { "by", nameForID(guildKey, row.by) },
        })
    end

    return table.concat(lines, "\n"), counts, cutoff
end

function LV.DataSync:StartSync(target)
    local guildInfo = LV.Guild:CurrentInfo()
    if not guildInfo then
        LV:Print("Log into a guilded character before syncing LootViewer data.")
        return
    end

    target = self:NormalizeTarget(target)
    if target == "" then
        LV:Print("Enter a player name to sync with.")
        return
    end

    local payload, counts, cutoff = self:BuildExport(guildInfo.key)
    local token = tostring(LV.Util:Now()) .. "-" .. tostring(math.random(100000, 999999))
    self.outbound = {
        token = token,
        target = target,
        guildKey = guildInfo.key,
        guildName = guildInfo.name,
        payload = payload,
        counts = counts,
        cutoff = cutoff,
        state = "waiting",
        sent = 0,
        total = 0,
        status = "Waiting for " .. target .. " to accept...",
    }

    LV.Comms:SendWhisper("Q", target, {
        token,
        guildInfo.key,
        guildInfo.name,
        cutoff,
        self:FormatCounts(counts),
    })
    self:RefreshUI()
end

function LV.DataSync:HandleInvite(parts, sender)
    local token = parts[2]
    local guildKey = parts[3]
    local guildName = parts[4]
    local cutoff = tonumber(parts[5]) or 0
    local counts = parts[6] or ""
    local currentKey = LV.Guild:CurrentKey()

    if not token or token == "" or not guildKey or guildKey == "" then
        return
    end

    if currentKey ~= guildKey then
        LV:Print("LootViewer sync invite from " .. tostring(sender or "unknown") .. " is for another guild.")
        return
    end

    self.pendingInvite = {
        token = token,
        sender = sender,
        guildKey = guildKey,
        guildName = guildName,
        cutoff = cutoff,
        counts = counts,
    }

    StaticPopup_Show(LV.Constants.SYNC_INVITE_PROMPT, sender or "Unknown", guildName or "this guild", self.pendingInvite)
end

function LV.DataSync:AcceptInvite(data)
    data = data or self.pendingInvite
    if not data or not data.sender or not data.token then
        return
    end

    self.inbound = {
        token = data.token,
        sender = data.sender,
        guildKey = data.guildKey,
        guildName = data.guildName,
        chunks = {},
        received = 0,
        total = 0,
        state = "receiving",
        status = "Waiting for data from " .. data.sender .. "...",
    }
    LV.Comms:SendWhisper("A", data.sender, { data.token, data.guildKey })
    self:RefreshUI()
end

function LV.DataSync:DeclineInvite(data)
    data = data or self.pendingInvite
    if data and data.sender and data.token then
        LV.Comms:SendWhisper("N", data.sender, { data.token, data.guildKey })
    end
end

function LV.DataSync:BeginChunkSend()
    local outbound = self.outbound
    if not outbound or outbound.state ~= "waiting" then
        return
    end

    local payload = outbound.payload or ""
    local chunks = {}
    local cursor = 1
    while cursor <= #payload do
        chunks[#chunks + 1] = string.sub(payload, cursor, cursor + CHUNK_SIZE - 1)
        cursor = cursor + CHUNK_SIZE
    end
    if #chunks == 0 then
        chunks[1] = ""
    end

    outbound.chunks = chunks
    outbound.total = #chunks
    outbound.sent = 0
    outbound.state = "sending"
    outbound.status = "Sending " .. self:FormatCounts(outbound.counts) .. "..."

    local function sendNext()
        if not self.outbound or self.outbound.token ~= outbound.token then
            if outbound.ticker then
                outbound.ticker:Cancel()
            end
            return
        end

        outbound.sent = outbound.sent + 1
        LV.Comms:SendWhisper("D", outbound.target, {
            outbound.token,
            outbound.sent,
            outbound.total,
            outbound.chunks[outbound.sent],
        })

        if outbound.sent >= outbound.total then
            if outbound.ticker then
                outbound.ticker:Cancel()
                outbound.ticker = nil
            end
            outbound.state = "sent"
            outbound.status = "Sent. Waiting for " .. outbound.target .. " to import..."
        end
        self:RefreshUI()
    end

    if C_Timer and C_Timer.NewTicker then
        outbound.ticker = C_Timer.NewTicker(SEND_DELAY, sendNext)
    else
        while outbound.sent < outbound.total do
            sendNext()
        end
    end

    self:RefreshUI()
end

function LV.DataSync:FindRaid(record, sender, remoteID, st, team, iid)
    for raidID, raid in pairs((record and record.r) or {}) do
        if type(raid) == "table" and type(raid.sy) == "table" and raid.sy[sender] == remoteID then
            return raidID, raid, true
        end
    end

    st = tonumber(st) or 0
    iid = tonumber(iid) or 0
    for raidID, raid in pairs((record and record.r) or {}) do
        if type(raid) == "table" then
            local raidST = tonumber(raid.st) or 0
            local raidIID = tonumber(raid.iid) or 0
            if math.abs(raidST - st) <= 5
                and (LV.Util:IsBlank(team) or raid.team == team)
                and (iid == 0 or raidIID == 0 or iid == raidIID) then
                return raidID, raid, false
            end
        end
    end

    return nil, nil, false
end

function LV.DataSync:ImportStatusList(guildKey, raid, status, value)
    if LV.Util:IsBlank(value) then
        return 0
    end

    local changed = 0
    for _, item in ipairs(split(value, ",")) do
        local parts = split(item, "|")
        local fullName = normalizedName(parts[1])
        if fullName ~= "" then
            local nameID = LV.Store:NameID(guildKey, fullName)
            if parts[3] and parts[3] ~= "" then
                LV.Store:SetPlayerClass(guildKey, nameID, parts[3])
            end
            if parts[4] and parts[4] ~= "" and parts[4] ~= "pug" then
                LV.Store:AddRosterMember(guildKey, fullName, {
                    c = parts[3],
                    ov = 1,
                })
            end
            if setRaidStatus(raid, nameID, status, tonumber(parts[2]) or LV.Util:Now()) then
                changed = changed + 1
            end
        end
    end
    return changed
end

function LV.DataSync:ImportRaid(guildKey, record, sender, fields, remoteRaidMap)
    local raidID, raid, knownRemote = self:FindRaid(record, sender, fields.id, fields.st, fields.team, fields.iid)
    local created = false

    if not raid then
        raidID = LV.Store:NewID(record, "raid", "r")
        raid = {
            id = raidID,
            st = tonumber(fields.st) or LV.Util:Now(),
            en = tonumber(fields.en) or tonumber(fields.st) or LV.Util:Now(),
            z = LV.Store:StringID(guildKey, fields.z or ""),
            iid = tonumber(fields.iid) or 0,
            diff = LV.Store:StringID(guildKey, fields.diff or ""),
            did = tonumber(fields.did) or 0,
            team = fields.team ~= "" and fields.team or "main",
            tn = fields.tn ~= "" and LV.Store:StringID(guildKey, fields.tn) or nil,
            by = fields.by ~= "" and LV.Store:NameID(guildKey, normalizedName(fields.by)) or nil,
            reason = fields.reason or "",
            p = {},
            b = {},
            late = {},
            out = {},
            noshow = {},
            kills = {},
            rem = {},
        }
        if tonumber(fields.adhoc) then
            raid.adhoc = tonumber(fields.adhoc)
            raid.adDur = tonumber(fields.adDur)
            raid.adEnd = tonumber(fields.adEnd)
        end
        record.r[raidID] = raid
        created = true
    else
        ensureRaidMaps(raid)
        raid.en = math.max(tonumber(raid.en) or 0, tonumber(fields.en) or 0)
        raid.z = raid.z or LV.Store:StringID(guildKey, fields.z or "")
        raid.diff = raid.diff or LV.Store:StringID(guildKey, fields.diff or "")
        raid.tn = raid.tn or (fields.tn ~= "" and LV.Store:StringID(guildKey, fields.tn) or nil)
    end

    raid.sy = raid.sy or {}
    raid.sy[sender] = fields.id
    remoteRaidMap[fields.id] = raidID

    self:ImportStatusList(guildKey, raid, "here", fields.p)
    self:ImportStatusList(guildKey, raid, "bench", fields.b)
    self:ImportStatusList(guildKey, raid, "late", fields.late)
    self:ImportStatusList(guildKey, raid, "out", fields.out)
    self:ImportStatusList(guildKey, raid, "noshow", fields.ns)

    return created, knownRemote
end

function LV.DataSync:ImportKill(guildKey, record, fields, remoteRaidMap)
    local raidID = remoteRaidMap[fields.rid]
    local raid = raidID and record.r[raidID]
    if type(raid) ~= "table" then
        return false
    end

    raid.kills = raid.kills or {}
    local ts = tonumber(fields.ts) or 0
    local encounterID = tonumber(fields.e) or 0
    for _, kill in ipairs(raid.kills) do
        if math.abs((tonumber(kill.ts) or 0) - ts) <= 5 and (tonumber(kill.e) or 0) == encounterID then
            return false
        end
    end

    raid.kills[#raid.kills + 1] = {
        ts = ts,
        e = encounterID,
        b = LV.Store:StringID(guildKey, fields.boss or ""),
        d = tonumber(fields.d) or 0,
        n = tonumber(fields.n) or 0,
        p = decodeNameList(guildKey, fields.p),
        bench = decodeNameList(guildKey, fields.bench),
        late = decodeNameList(guildKey, fields.late),
        out = decodeNameList(guildKey, fields.out),
        noshow = decodeNameList(guildKey, fields.ns),
    }
    return true
end

function LV.DataSync:FindLoot(record, sender, remoteID, playerID, itemKeyID, itemID, timestamp, encounterID, source)
    for _, row in ipairs((record and record.l) or {}) do
        if type(row) == "table" and type(row.sy) == "table" and row.sy[sender] == remoteID then
            return row, true
        end
    end

    timestamp = tonumber(timestamp) or 0
    for _, row in ipairs((record and record.l) or {}) do
        local rowItemID = tonumber(row and row.itemID) or 0
        local sameItemID = rowItemID > 0 and (tonumber(itemID) or 0) > 0 and rowItemID == (tonumber(itemID) or 0)
        local sameItemKey = type(row) == "table" and row.item == itemKeyID
        local rowEncounter = tonumber(row and row.e) or 0
        local incomingEncounter = tonumber(encounterID) or 0
        if type(row) == "table"
            and math.abs((tonumber(row.ts) or 0) - timestamp) <= 8
            and row.p == playerID
            and (sameItemID or sameItemKey)
            and (rowEncounter == incomingEncounter or rowEncounter == 0 or incomingEncounter == 0) then
            return row, false
        end
    end

    return nil, false
end

function LV.DataSync:ImportLoot(guildKey, record, sender, fields, remoteRaidMap, remoteLootMap)
    local fullName = normalizedName(fields.p)
    local itemKey = LV.Util:ItemKey(fields.item or "")
    if fullName == "" or itemKey == "" then
        return false, true
    end

    local playerID = LV.Store:NameID(guildKey, fullName)
    local itemKeyID = LV.Store:ItemID(guildKey, itemKey)
    local itemID = tonumber(fields.itemID) or LV.Util:ItemID(itemKey) or 0
    if LV.Loot and LV.Loot.IsLootExcluded and LV.Loot:IsLootExcluded(guildKey, {
        e = tonumber(fields.e) or 0,
        item = itemKeyID,
        itemID = itemID,
        p = playerID,
    }) then
        return false, true
    end

    local row, knownRemote = self:FindLoot(record, sender, fields.id, playerID, itemKeyID, itemID, fields.ts, fields.e, fields.src)
    local rollBreakdown = decodeRollBreakdown(guildKey, fields.rb)
    local incomingRoll = fields.r or ""
    local incomingRaw = fields.raw
    local incomingRollFromBreakdown = false
    if LV.Loot and LV.Loot.WinnerRollFromBreakdown then
        local winnerRoll, winnerRawRoll, winnerRollFound = LV.Loot:WinnerRollFromBreakdown({ p = playerID }, rollBreakdown)
        if winnerRoll and winnerRoll ~= "" then
            incomingRoll = winnerRoll
            incomingRollFromBreakdown = true
        end
        if winnerRollFound and winnerRawRoll ~= nil then
            incomingRaw = winnerRawRoll
            incomingRollFromBreakdown = true
        end
    end
    local incomingRawText = incomingRaw ~= nil and tostring(incomingRaw) or ""

    if fields.cls and fields.cls ~= "" then
        LV.Store:SetPlayerClass(guildKey, playerID, fields.cls)
    end

    if row then
        row.sy = row.sy or {}
        row.sy[sender] = fields.id
        if incomingRoll ~= "" and (incomingRollFromBreakdown or not row.r or row.r == "" or tostring(row.r):match("^%d+$")) then
            row.r = incomingRoll
        end
        if incomingRollFromBreakdown and incomingRawText ~= "" then
            row.raw = incomingRawText
        else
            row.raw = row.raw or (incomingRawText ~= "" and incomingRawText or nil)
        end
        if rollBreakdown and (
            not row.rb
            or #row.rb < #rollBreakdown
            or rollBreakdownMethodCount(row.rb) < rollBreakdownMethodCount(rollBreakdown)
        ) then
            row.rb = rollBreakdown
        end
        remoteLootMap[fields.id] = row.id
        return false, knownRemote
    end

    row = {
        id = LV.Store:NewID(record, "loot", "l"),
        ts = tonumber(fields.ts) or LV.Util:Now(),
        sid = remoteRaidMap[fields.sid],
        e = tonumber(fields.e) or 0,
        iid = tonumber(fields.iid) or 0,
        inst = LV.Store:StringID(guildKey, fields.inst or ""),
        boss = LV.Store:StringID(guildKey, fields.boss or ""),
        did = tonumber(fields.did) or 0,
        diff = LV.Store:StringID(guildKey, fields.diff or ""),
        p = playerID,
        cls = fields.cls ~= "" and LV.Store:StringID(guildKey, fields.cls) or nil,
        item = itemKeyID,
        itemID = itemID,
        q = tonumber(fields.q) or 1,
        r = incomingRoll,
        raw = incomingRawText ~= "" and incomingRawText or nil,
        rb = rollBreakdown,
        src = fields.src or "sync",
        boe = tonumber(fields.boe) or nil,
        wb = tonumber(fields.wb) or nil,
        by = fields.by ~= "" and LV.Store:NameID(guildKey, normalizedName(fields.by)) or nil,
        sy = { [sender] = fields.id },
    }
    table.insert(record.l, row)
    remoteLootMap[fields.id] = row.id
    return true, false
end

function LV.DataSync:FindTrade(record, sender, remoteID, fromID, toID, itemKeyID, itemID, timestamp)
    for _, row in ipairs((record and record.t) or {}) do
        if type(row) == "table" and type(row.sy) == "table" and row.sy[sender] == remoteID then
            return row, true
        end
    end

    timestamp = tonumber(timestamp) or 0
    for _, row in ipairs((record and record.t) or {}) do
        if type(row) == "table"
            and math.abs((tonumber(row.ts) or 0) - timestamp) <= 8
            and row.f == fromID
            and row.to == toID
            and row.item == itemKeyID
            and (tonumber(row.itemID) or 0) == (tonumber(itemID) or 0) then
            return row, false
        end
    end

    return nil, false
end

function LV.DataSync:LootByID(record, lootID)
    if not lootID then
        return nil
    end

    for _, row in ipairs((record and record.l) or {}) do
        if type(row) == "table" and row.id == lootID then
            return row
        end
    end
    return nil
end

function LV.DataSync:ImportTrade(guildKey, record, sender, fields, remoteRaidMap, remoteLootMap)
    local fromName = normalizedName(fields.f)
    local toName = normalizedName(fields.to)
    local itemKey = LV.Util:ItemKey(fields.item or "")
    if fromName == "" or toName == "" or itemKey == "" then
        return false, true
    end

    local fromID = LV.Store:NameID(guildKey, fromName)
    local toID = LV.Store:NameID(guildKey, toName)
    local itemKeyID = LV.Store:ItemID(guildKey, itemKey)
    local itemID = tonumber(fields.itemID) or LV.Util:ItemID(itemKey) or 0
    local row, knownRemote = self:FindTrade(record, sender, fields.id, fromID, toID, itemKeyID, itemID, fields.ts)

    if row then
        row.sy = row.sy or {}
        row.sy[sender] = fields.id
        return false, knownRemote
    end

    row = {
        id = LV.Store:NewID(record, "trade", "t"),
        ts = tonumber(fields.ts) or LV.Util:Now(),
        sid = remoteRaidMap[fields.sid],
        f = fromID,
        to = toID,
        item = itemKeyID,
        itemID = itemID,
        loot = remoteLootMap[fields.loot],
        src = fields.src or "sync",
        by = fields.by ~= "" and LV.Store:NameID(guildKey, normalizedName(fields.by)) or nil,
        sy = { [sender] = fields.id },
    }
    table.insert(record.t, row)

    local sourceLoot = self:LootByID(record, row.loot)
    if sourceLoot then
        sourceLoot.tr = row.id
    end

    return true, false
end

function LV.DataSync:ImportConfig(record, fields, configState)
    if type(record) ~= "table" then
        return false
    end

    record.cfg = record.cfg or {}
    local cfg = record.cfg
    for key, _ in pairs(configBooleans) do
        if fields[key] ~= nil then
            cfg[key] = parseBool(fields[key])
        end
    end
    for key, _ in pairs(configNumbers) do
        if fields[key] ~= nil and fields[key] ~= "" then
            cfg[key] = tonumber(fields[key]) or cfg[key]
        end
    end
    for key, _ in pairs(configStrings) do
        if fields[key] ~= nil then
            cfg[key] = LV.Util:Trim(fields[key])
        end
    end

    cfg.teams = {}
    cfg.schedules = nil
    cfg._teamsMigrated = 1
    configState.seen = true
    configState.teamsByID = {}
    configState.selectedTeam = cfg.selectedTeam
    return true
end

function LV.DataSync:ImportConfigTeam(record, fields, configState)
    if not configState.seen or type(record) ~= "table" then
        return false
    end

    local cfg = record.cfg or {}
    local teamID = LV.Util:NormalizeSlug(fields.id or fields.name or "")
    if teamID == "" then
        teamID = "team-" .. tostring(#(cfg.teams or {}) + 1)
    end

    local team = {
        id = teamID,
        name = LV.Util:Trim(fields.name) ~= "" and LV.Util:Trim(fields.name) or teamID,
        tz = LV.Util:Trim(fields.tz) ~= "" and LV.Util:Trim(fields.tz) or "local",
        color = LV.Store:NormalizeTeamColor({
            r = fields.cr,
            g = fields.cg,
            b = fields.cb,
            a = fields.ca,
        }),
        schedules = {},
    }
    cfg.teams = cfg.teams or {}
    cfg.teams[#cfg.teams + 1] = team
    configState.teamsByID[teamID] = team
    return true
end

function LV.DataSync:ImportConfigSchedule(record, fields, configState)
    if not configState.seen or type(record) ~= "table" then
        return false
    end

    local teamID = LV.Util:NormalizeSlug(fields.team or "")
    local team = configState.teamsByID[teamID]
    if not team then
        return false
    end

    team.schedules = team.schedules or {}
    team.schedules[#team.schedules + 1] = {
        w = tonumber(fields.w) or 1,
        h = tonumber(fields.h) or 20,
        m = tonumber(fields.m) or 0,
        d = tonumber(fields.d) or 180,
    }
    return true
end

function LV.DataSync:ImportPayload(sender, payload)
    sender = sender or "unknown"
    local guildKey = LV.Guild:CurrentKey()
    if not guildKey then
        return { config = false, raids = 0, loot = 0, trades = 0, skipped = 0, kills = 0 }
    end

    local record = LV.Store:GuildRecord(guildKey)
    local remoteRaidMap = {}
    local remoteLootMap = {}
    local configState = { seen = false, teamsByID = {} }
    local imported = { config = false, raids = 0, loot = 0, trades = 0, skipped = 0, kills = 0 }

    for _, rawLine in ipairs(split(payload or "", "\n")) do
        if rawLine ~= "" then
            local kind, fields = parseLine(rawLine)
            if kind == "H" then
                if fields.g and fields.g ~= "" and fields.g ~= guildKey then
                    return imported
                end
            elseif kind == "CFG" then
                if self:ImportConfig(record, fields, configState) then
                    imported.config = true
                end
            elseif kind == "TEAM" then
                self:ImportConfigTeam(record, fields, configState)
            elseif kind == "SCH" then
                self:ImportConfigSchedule(record, fields, configState)
            elseif kind == "R" then
                local created = self:ImportRaid(guildKey, record, sender, fields, remoteRaidMap)
                if created then
                    imported.raids = imported.raids + 1
                else
                    imported.skipped = imported.skipped + 1
                end
            elseif kind == "K" then
                if self:ImportKill(guildKey, record, fields, remoteRaidMap) then
                    imported.kills = imported.kills + 1
                end
            elseif kind == "L" then
                local added, skipped = self:ImportLoot(guildKey, record, sender, fields, remoteRaidMap, remoteLootMap)
                if added then
                    imported.loot = imported.loot + 1
                elseif skipped then
                    imported.skipped = imported.skipped + 1
                end
            elseif kind == "T" then
                local added, skipped = self:ImportTrade(guildKey, record, sender, fields, remoteRaidMap, remoteLootMap)
                if added then
                    imported.trades = imported.trades + 1
                elseif skipped then
                    imported.skipped = imported.skipped + 1
                end
            end
        end
    end

    if configState.seen then
        LV.Store:NormalizeTeams(record)
    end

    table.sort(record.l, function(a, b)
        return (tonumber(a.ts) or 0) < (tonumber(b.ts) or 0)
    end)
    table.sort(record.t, function(a, b)
        return (tonumber(a.ts) or 0) < (tonumber(b.ts) or 0)
    end)

    if LV.UI and LV.UI.Refresh then
        LV.UI:Refresh()
    end
    return imported
end

function LV.DataSync:HandleMessage(parts, sender)
    local kind = parts[1]
    if kind == "Q" then
        self:HandleInvite(parts, sender)
        return
    end

    if kind == "A" then
        local outbound = self.outbound
        if outbound and outbound.token == parts[2] and outbound.guildKey == parts[3] then
            outbound.status = tostring(sender or outbound.target) .. " accepted. Preparing transfer..."
            self:BeginChunkSend()
        end
        return
    end

    if kind == "N" then
        local outbound = self.outbound
        if outbound and outbound.token == parts[2] then
            outbound.state = "declined"
            outbound.status = tostring(sender or outbound.target) .. " declined the sync invite."
            self:RefreshUI()
        end
        return
    end

    if kind == "D" then
        local inbound = self.inbound
        if not inbound or inbound.token ~= parts[2] or inbound.sender ~= sender then
            return
        end

        local sequence = tonumber(parts[3]) or 0
        local total = tonumber(parts[4]) or 0
        if sequence <= 0 or total <= 0 then
            return
        end

        inbound.total = total
        if not inbound.chunks[sequence] then
            inbound.chunks[sequence] = parts[5] or ""
            inbound.received = inbound.received + 1
        end
        inbound.status = "Receiving data from " .. tostring(sender or "sync partner") .. "..."

        if inbound.received >= inbound.total then
            local chunks = {}
            for index = 1, inbound.total do
                chunks[#chunks + 1] = inbound.chunks[index] or ""
            end
            local imported = self:ImportPayload(sender, table.concat(chunks, ""))
            inbound.state = "complete"
            inbound.imported = imported
            inbound.status = "Imported " .. self:FormatCounts(imported) .. "."
            LV:Print(self:TransferSummary(inbound.guildName, imported))
            LV.Comms:SendWhisper("C", sender, {
                inbound.token,
                inbound.guildKey,
                imported.raids,
                imported.loot,
                imported.trades,
                imported.skipped,
                imported.config and 1 or 0,
                inbound.guildName or "",
            })
        end
        self:RefreshUI()
        return
    end

    if kind == "C" then
        local outbound = self.outbound
        if outbound and outbound.token == parts[2] then
            outbound.state = "complete"
            local ackCounts = {
                raids = tonumber(parts[4]) or 0,
                loot = tonumber(parts[5]) or 0,
                trades = tonumber(parts[6]) or 0,
                config = parseBool(parts[7]),
            }
            local ackGuildName = parts[8] ~= "" and parts[8] or outbound.guildName
            local configText = ackCounts.config and "config, " or ""
            outbound.status = tostring(sender or outbound.target) .. " imported "
                .. configText
                .. tostring(ackCounts.raids) .. " raid(s), "
                .. tostring(ackCounts.loot) .. " loot, "
                .. tostring(ackCounts.trades) .. " trade(s)."
            LV:Print(self:TransferSummary(ackGuildName, ackCounts))
            self:RefreshUI()
        end
    end
end

function LV.DataSync:Progress()
    local active = self.inbound or self.outbound
    if not active then
        return 0, 1, "Ready to sync."
    end

    if active.state == "waiting" then
        return 0, 1, active.status or "Waiting..."
    end

    local current = active.received or active.sent or 0
    local total = active.total or 1
    if total <= 0 then
        total = 1
    end
    if active.state == "complete" then
        current = total
    end
    return current, total, active.status or ""
end

StaticPopupDialogs[LV.Constants.SYNC_INVITE_PROMPT] = {
    text = "%s wants to send LootViewer data for %s.\nAccept guild config plus attendance and loot from the last 2 months?",
    button1 = ACCEPT,
    button2 = "Decline",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    OnAccept = function(_, data)
        LV.DataSync:AcceptInvite(data)
    end,
    OnCancel = function(_, data)
        LV.DataSync:DeclineInvite(data)
    end,
}
