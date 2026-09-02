local _, LV = ...

LV.DataSync = {}
LV.modules.DataSync = LV.DataSync

local CHUNK_SIZE = 180
local SEND_DELAY = 0.25
local RETRY_DELAY = 1.5
local SYNC_WINDOW_SECONDS = 60 * 86400
local RELIABLE_PROTOCOL_VERSION = 3
local SYNC_PROTOCOL_VERSION = 6
local RAID_ID_MIGRATION_VERSION = 1
local EXCLUDED_REMOTE_RAID = {}

local syncKinds = {
    Q = true,
    A = true,
    D = true,
    C = true,
    N = true,
    M = true,
    R = true,
    G = true,
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
    endGrace = true,
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
    seasonMode = true,
    pruneMode = true,
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

local function transferTime()
    if GetTime then
        return GetTime()
    end
    return LV.Util:Now()
end

local function samePlayer(left, right)
    return LV.Util:Trim(left):lower() == LV.Util:Trim(right):lower()
end

local function raidKillSignature(raid)
    local kills = {}
    for _, kill in ipairs((raid and raid.kills) or {}) do
        local encounterID = tonumber(kill and kill.e) or 0
        if encounterID > 0 then
            kills[#kills + 1] = tostring(encounterID)
        end
    end
    table.sort(kills)
    return table.concat(kills, ",")
end

local function countMap(map)
    local count = 0
    for _ in pairs(map or {}) do
        count = count + 1
    end
    return count
end

local function raidAttendanceCount(raid)
    local ids = {}
    for _, map in ipairs({ raid and raid.p, raid and raid.b, raid and raid.late,
        raid and raid.out, raid and raid.noshow }) do
        for id in pairs(map or {}) do
            ids[id] = true
        end
    end
    return countMap(ids)
end

local function stableHash(value)
    local hash = 5381
    value = tostring(value or "")
    for index = 1, #value do
        hash = ((hash * 33) + string.byte(value, index)) % 2147483647
    end
    return string.format("%x", hash)
end

local function normalizedRaidDay(timestamp)
    -- Noon UTC keeps normal evening starts together even when clients begin a
    -- few minutes apart on opposite sides of midnight UTC.
    return math.floor(((tonumber(timestamp) or LV.Util:Now()) - (12 * 60 * 60)) / 86400)
end

local function calculatedRaidIdentity(guildKey, raid)
    local teamID = tostring((raid and raid.team) or "main"):lower()
    local anchor = tonumber(raid and raid.sst) or tonumber(raid and raid.st) or LV.Util:Now()
    return "rs" .. tostring(normalizedRaidDay(anchor)) .. "-"
        .. stableHash(tostring(guildKey or "") .. "|" .. teamID)
end

function LV.DataSync:RaidIdentity(guildKey, raid)
    if type(raid) ~= "table" then
        return nil
    end
    local existing = tostring(raid.cid or "")
    if existing:match("^rs%-?%d+%-%x+$") then
        return existing
    end
    raid.cid = calculatedRaidIdentity(guildKey, raid)
    return raid.cid
end

local function selectedRaid(selectedRaidIDs, raidID)
    if type(selectedRaidIDs) ~= "table" then
        return true
    end
    return selectedRaidIDs[raidID] == true or selectedRaidIDs[tostring(raidID or "")] == true
end

local function raidSelected(selectedRaidIDs, raidID, raid)
    if selectedRaid(selectedRaidIDs, raidID) or selectedRaid(selectedRaidIDs, raid and raid.id)
        or selectedRaid(selectedRaidIDs, raid and raid.cid) then
        return true
    end
    if type(selectedRaidIDs) == "table" then
        for _, remoteRaidID in pairs((raid and raid.sy) or {}) do
            if selectedRaid(selectedRaidIDs, remoteRaidID) then
                return true
            end
        end
    end
    return false
end

local function setRaidExportLink(links, raidID, exportRaidID)
    if raidID == nil or tostring(raidID) == "" then
        return
    end
    links[raidID] = exportRaidID
    links[tostring(raidID)] = exportRaidID
end

local function raidExportLink(links, raidID)
    if raidID == nil then
        return nil
    end
    return links[raidID] or links[tostring(raidID)]
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

local function mergeNameIDs(target, incoming)
    target = type(target) == "table" and target or {}
    local seen = {}
    for _, nameID in ipairs(target) do
        seen[nameID] = true
    end
    for _, nameID in ipairs(incoming or {}) do
        if not seen[nameID] then
            target[#target + 1] = nameID
            seen[nameID] = true
        end
    end
    return target
end

local function earlierPositive(left, right)
    left = tonumber(left) or 0
    right = tonumber(right) or 0
    if left <= 0 then return right > 0 and right or nil end
    if right <= 0 then return left end
    return math.min(left, right)
end

local function laterPositive(left, right)
    left = tonumber(left) or 0
    right = tonumber(right) or 0
    local value = math.max(left, right)
    return value > 0 and value or nil
end

local function mergeRaidKill(targetRaid, sourceKill)
    targetRaid.kills = targetRaid.kills or {}
    local encounterID = tonumber(sourceKill and sourceKill.e) or 0
    local sourceDifficulty = tonumber(sourceKill and sourceKill.d) or 0
    for _, targetKill in ipairs(targetRaid.kills) do
        local targetDifficulty = tonumber(targetKill and targetKill.d) or 0
        if (tonumber(targetKill and targetKill.e) or 0) == encounterID
            and (targetDifficulty == sourceDifficulty or targetDifficulty == 0 or sourceDifficulty == 0) then
            targetKill.ts = earlierPositive(targetKill.ts, sourceKill.ts)
            targetKill.b = targetKill.b or sourceKill.b
            if targetDifficulty == 0 then targetKill.d = sourceDifficulty end
            targetKill.n = math.max(tonumber(targetKill.n) or 0, tonumber(sourceKill.n) or 0)
            for _, key in ipairs({ "p", "bench", "late", "out", "noshow" }) do
                targetKill[key] = mergeNameIDs(targetKill[key], sourceKill[key])
            end
            return false
        end
    end

    targetRaid.kills[#targetRaid.kills + 1] = sourceKill
    return true
end

local function mergeRaidRecord(target, source)
    ensureRaidMaps(target)
    ensureRaidMaps(source)
    target.st = earlierPositive(target.st, source.st)
    target.sst = earlierPositive(target.sst, source.sst)
    target.en = math.max(tonumber(target.en) or 0, tonumber(source.en) or 0)
    target.set = laterPositive(target.set, source.set)
    target.adEnd = laterPositive(target.adEnd, source.adEnd)
    target.adDur = laterPositive(target.adDur, source.adDur)

    for _, key in ipairs({ "z", "iid", "diff", "did", "sea", "tn", "by", "reason", "adhoc",
        "autoPug", "lastSource" }) do
        if target[key] == nil or target[key] == "" or target[key] == 0 then
            target[key] = source[key]
        end
    end

    local attendanceIDs = {}
    for _, map in ipairs({ source.p, source.b, source.late, source.out, source.noshow }) do
        for nameID in pairs(map or {}) do
            attendanceIDs[nameID] = true
        end
    end
    for nameID in pairs(attendanceIDs) do
        local status, timestamp = mapStatus(source, nameID)
        if status then
            setRaidStatus(target, nameID, status, timestamp)
        end
    end

    for _, sourceKill in ipairs(source.kills or {}) do
        if type(sourceKill) == "table" then
            mergeRaidKill(target, sourceKill)
        end
    end
    for _, key in ipairs({ "sy", "rem" }) do
        target[key] = type(target[key]) == "table" and target[key] or {}
        for mapKey, value in pairs(type(source[key]) == "table" and source[key] or {}) do
            if target[key][mapKey] == nil then
                target[key][mapKey] = value
            end
        end
    end
end

function LV.DataSync:NormalizeLegacyRaidIDs()
    LV.Store:InitializeIfNeeded()
    local totals = { raids = 0, merged = 0, links = 0, guilds = 0 }

    for guildKey, rawRecord in pairs((LV.Store.db and LV.Store.db.g) or {}) do
        if type(rawRecord) == "table" then
            local record = LV.Store:GuildRecord(guildKey)
            record.mig = type(record.mig) == "table" and record.mig or {}
            if (tonumber(record.mig.rid) or 0) < RAID_ID_MIGRATION_VERSION then
                local rows = {}
                for oldRaidID, raid in pairs(record.r or {}) do
                    rows[#rows + 1] = { id = oldRaidID, raid = raid }
                end
                table.sort(rows, function(left, right)
                    local leftStart = tonumber(type(left.raid) == "table" and left.raid.st) or 0
                    local rightStart = tonumber(type(right.raid) == "table" and right.raid.st) or 0
                    if leftStart ~= rightStart then return leftStart < rightStart end
                    return tostring(left.id) < tostring(right.id)
                end)

                local normalized = {}
                local links = {}
                for _, item in ipairs(rows) do
                    local oldRaidID, raid = item.id, item.raid
                    if type(raid) == "table" and not LV.Store:IsGlobalPugTeam(raid.team) then
                        local oldRecordID = raid.id
                        local oldCanonicalID = raid.cid
                        local canonicalID = calculatedRaidIdentity(guildKey, raid)
                        links[tostring(oldRaidID)] = canonicalID
                        if oldRecordID ~= nil then links[tostring(oldRecordID)] = canonicalID end
                        if oldCanonicalID ~= nil then links[tostring(oldCanonicalID)] = canonicalID end
                        links[canonicalID] = canonicalID

                        if tostring(oldRaidID) ~= canonicalID or tostring(oldRecordID or "") ~= canonicalID
                            or tostring(oldCanonicalID or "") ~= canonicalID then
                            totals.raids = totals.raids + 1
                        end
                        raid.id = canonicalID
                        raid.cid = canonicalID
                        if normalized[canonicalID] then
                            mergeRaidRecord(normalized[canonicalID], raid)
                            totals.merged = totals.merged + 1
                        else
                            normalized[canonicalID] = raid
                        end
                    else
                        normalized[oldRaidID] = raid
                    end
                end
                record.r = normalized

                for _, collection in ipairs({ record.l, record.t }) do
                    for _, row in ipairs(collection or {}) do
                        if type(row) == "table" and row.sid ~= nil then
                            local canonicalID = links[tostring(row.sid)]
                            if canonicalID and tostring(row.sid) ~= canonicalID then
                                row.sid = canonicalID
                                totals.links = totals.links + 1
                            end
                        end
                    end
                end
                if record.cur ~= nil and links[tostring(record.cur)] then
                    record.cur = links[tostring(record.cur)]
                end
                record.mig.rid = RAID_ID_MIGRATION_VERSION
                totals.guilds = totals.guilds + 1
            end
        end
    end

    return totals
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

local function sortedResolvedNames(guildKey, values)
    local names = {}
    for id in pairs(values or {}) do
        local name = nameForID(guildKey, id):lower()
        if name ~= "" then names[#names + 1] = name end
    end
    table.sort(names)
    return table.concat(names, ",")
end

local function sortedListNames(guildKey, values)
    local names = {}
    for _, id in ipairs(values or {}) do
        local name = nameForID(guildKey, id):lower()
        if name ~= "" then names[#names + 1] = name end
    end
    table.sort(names)
    return table.concat(names, ",")
end

local function raidContentSignature(guildKey, record, raidID, raid)
    local tokens = {}
    for _, status in ipairs(statusOrder) do
        local key = statusMaps[status]
        tokens[#tokens + 1] = "a|" .. status .. "|" .. sortedResolvedNames(guildKey, raid and raid[key])
    end
    for _, kill in ipairs((raid and raid.kills) or {}) do
        tokens[#tokens + 1] = table.concat({
            "k", tostring(tonumber(kill and kill.e) or 0), tostring(tonumber(kill and kill.d) or 0),
            sortedListNames(guildKey, kill and kill.p), sortedListNames(guildKey, kill and kill.bench),
            sortedListNames(guildKey, kill and kill.late), sortedListNames(guildKey, kill and kill.out),
            sortedListNames(guildKey, kill and kill.noshow),
        }, "|")
    end
    for _, row in ipairs((record and record.l) or {}) do
        if type(row) == "table" and tostring(row.sid or "") == tostring(raidID or "")
            and not (LV.Loot and LV.Loot.IsWarboundRow and LV.Loot:IsWarboundRow(guildKey, row)) then
            tokens[#tokens + 1] = table.concat({
                "l", nameForID(guildKey, row.p):lower(), tostring(tonumber(row.itemID) or 0),
                itemForID(guildKey, row.item):lower(), tostring(tonumber(row.e) or 0), tostring(row.src or ""),
            }, "|")
        end
    end
    for _, row in ipairs((record and record.t) or {}) do
        if type(row) == "table" and tostring(row.sid or "") == tostring(raidID or "") then
            tokens[#tokens + 1] = table.concat({
                "t", nameForID(guildKey, row.f):lower(), nameForID(guildKey, row.to):lower(),
                tostring(tonumber(row.itemID) or 0), itemForID(guildKey, row.item):lower(),
            }, "|")
        end
    end
    table.sort(tokens)
    return stableHash(table.concat(tokens, "\031"))
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
    local text = prefix
        .. tostring(counts.exclusions or 0) .. " exclusion(s), "
        .. tostring(counts.raids or 0) .. " raid(s), "
        .. tostring(counts.loot or 0) .. " loot, "
        .. tostring(counts.trades or 0) .. " trade(s)"
    local restored = (tonumber(counts.relinkedLoot) or 0) + (tonumber(counts.relinkedTrades) or 0)
    if restored > 0 then
        text = text .. ", " .. tostring(restored) .. " existing event link(s) restored"
    end
    return text
end

function LV.DataSync:TransferSummary(guildName, counts)
    counts = counts or {}
    local parts = {}
    if counts.config then
        parts[#parts + 1] = "Updated Guild Config"
    end
    parts[#parts + 1] = tostring(counts.exclusions or 0) .. " excluded item rule(s)"
    parts[#parts + 1] = tostring(counts.raids or 0) .. " raid(s)"
    parts[#parts + 1] = tostring(counts.loot or 0) .. " loot(s)"
    parts[#parts + 1] = tostring(counts.trades or 0) .. " trade(s)"
    local restored = (tonumber(counts.relinkedLoot) or 0) + (tonumber(counts.relinkedTrades) or 0)
    if restored > 0 then
        parts[#parts + 1] = tostring(restored) .. " existing event link(s) restored"
    end
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
        if LV.UI.RefreshSyncComparisonProgress then
            LV.UI:RefreshSyncComparisonProgress()
        end
    end
end

function LV.DataSync:BuildManifest(guildKey)
    if self.RepairOrphanedRaidEvents then
        self:RepairOrphanedRaidEvents(guildKey, true)
    end
    local record = LV.Store:GuildRecord(guildKey)
    local cutoff = LV.Util:Now() - SYNC_WINDOW_SECONDS
    local rows = {}
    for raidID, raid in pairs((record and record.r) or {}) do
        if type(raid) == "table" and (tonumber(raid.st) or 0) >= cutoff
            and not LV.Store:IsRaidExcludedFromSync(guildKey, raid) then
            rows[#rows + 1] = {
                id = raidID,
                syncID = self:RaidIdentity(guildKey, raid) or raidID,
                raid = raid,
            }
        end
    end
    table.sort(rows, function(a, b)
        local ast = tonumber(a.raid.st) or 0
        local bst = tonumber(b.raid.st) or 0
        if ast ~= bst then
            return ast > bst
        end
        return tostring(a.id) < tostring(b.id)
    end)

    local raidLinks = {}
    for _, item in ipairs(rows) do
        setRaidExportLink(raidLinks, item.id, item.syncID)
        setRaidExportLink(raidLinks, item.raid.id, item.syncID)
        setRaidExportLink(raidLinks, item.raid.cid, item.syncID)
        for _, remoteRaidID in pairs(item.raid.sy or {}) do
            setRaidExportLink(raidLinks, remoteRaidID, item.syncID)
        end
    end
    local lootCounts = {}
    local excludedLootIDs = {}
    for _, loot in ipairs((record and record.l) or {}) do
        local raidID = raidExportLink(raidLinks, type(loot) == "table" and loot.sid or nil)
        local warbound = type(loot) == "table" and LV.Loot and LV.Loot.IsWarboundRow
            and LV.Loot:IsWarboundRow(guildKey, loot)
        if type(loot) == "table" and raidID and not warbound
            and (tonumber(loot.ts) or 0) >= cutoff then
            lootCounts[raidID] = (lootCounts[raidID] or 0) + 1
        elseif type(loot) == "table" and loot.id and warbound then
            excludedLootIDs[loot.id] = true
        end
    end
    local tradeCounts = {}
    for _, trade in ipairs((record and record.t) or {}) do
        local raidID = raidExportLink(raidLinks, type(trade) == "table" and trade.sid or nil)
        if type(trade) == "table" and raidID and not excludedLootIDs[trade.loot]
            and (tonumber(trade.ts) or 0) >= cutoff then
            tradeCounts[raidID] = (tradeCounts[raidID] or 0) + 1
        end
    end

    local lines = {
        line("MV", {
            { "v", SYNC_PROTOCOL_VERSION },
            { "g", guildKey },
            { "cutoff", cutoff },
        }),
    }
    for _, item in ipairs(rows) do
        local raid = item.raid
        lines[#lines + 1] = line("MR", {
            { "id", item.syncID },
            { "st", raid.st },
            { "sst", raid.sst },
            { "iid", raid.iid },
            { "team", raid.team or "main" },
            { "tn", stringForID(guildKey, raid.tn) },
            { "kills", #(raid.kills or {}) },
            { "ks", raidKillSignature(raid) },
            { "people", raidAttendanceCount(raid) },
            { "loot", lootCounts[item.syncID] or 0 },
            { "trades", tradeCounts[item.syncID] or 0 },
            { "sig", raidContentSignature(guildKey, record, item.id, raid) },
        })
    end
    return table.concat(lines, "\n"), #rows
end

function LV.DataSync:ParseManifest(payload)
    local manifest = { raids = {}, byID = {} }
    for raw in tostring(payload or ""):gmatch("[^\n]+") do
        local kind, fields = parseLine(raw)
        if kind == "MV" then
            manifest.version = tonumber(fields.v) or 0
            manifest.guildKey = fields.g
            manifest.cutoff = tonumber(fields.cutoff) or 0
        elseif kind == "MR" and fields.id and fields.id ~= "" then
            local entry = {
                id = fields.id,
                st = tonumber(fields.st) or 0,
                sst = tonumber(fields.sst),
                iid = tonumber(fields.iid) or 0,
                team = fields.team ~= "" and fields.team or "main",
                teamName = fields.tn ~= "" and fields.tn or (fields.team ~= "" and fields.team or "main"),
                kills = tonumber(fields.kills) or 0,
                killSignature = fields.ks or "",
                people = tonumber(fields.people) or 0,
                loot = tonumber(fields.loot) or 0,
                trades = tonumber(fields.trades) or 0,
                signature = fields.sig or "",
            }
            manifest.raids[#manifest.raids + 1] = entry
            manifest.byID[entry.id] = entry
        end
    end
    return manifest
end

function LV.DataSync:BuildExport(guildKey, selectedRaidIDs, options)
    options = options or {}
    local record = LV.Store:GuildRecord(guildKey)
    local cutoff = LV.Util:Now() - SYNC_WINDOW_SECONDS
    local counts = { config = false, exclusions = 0, raids = 0, loot = 0, trades = 0 }
    local excludedTeamIDs = { [LV.Constants.PUG_TEAM_ID] = true }
    local includedTeams = {}
    for _, team in ipairs((record.cfg and record.cfg.teams) or {}) do
        if type(team) == "table" then
            if team.excludeSync == true then
                excludedTeamIDs[team.id] = true
            else
                includedTeams[#includedTeams + 1] = team
            end
        end
    end
    local excludedRaidIDs = {}
    local raidExportLinks = {}
    for raidID, raid in pairs((record and record.r) or {}) do
        if type(raid) == "table" and (excludedTeamIDs[raid.team or "main"]
            or not raidSelected(selectedRaidIDs, raidID, raid)) then
            excludedRaidIDs[raidID] = true
            if raid.id then excludedRaidIDs[raid.id] = true end
        elseif type(raid) == "table" then
            local exportRaidID = self:RaidIdentity(guildKey, raid) or raid.id or raidID
            setRaidExportLink(raidExportLinks, raidID, exportRaidID)
            setRaidExportLink(raidExportLinks, raid.id, exportRaidID)
            setRaidExportLink(raidExportLinks, raid.cid, exportRaidID)
            for _, remoteRaidID in pairs(raid.sy or {}) do
                setRaidExportLink(raidExportLinks, remoteRaidID, exportRaidID)
            end
        end
    end
    local excludedLootIDs = {}
    for _, row in ipairs((record and record.l) or {}) do
        if type(row) == "table" and row.id and (excludedRaidIDs[row.sid]
            or (LV.Loot and LV.Loot.IsWarboundRow and LV.Loot:IsWarboundRow(guildKey, row))) then
            excludedLootIDs[row.id] = true
        end
    end
    local lines = {
        line("H", {
            { "v", 1 },
            { "g", guildKey },
            { "from", LV.Util:PlayerFullName() },
            { "cutoff", cutoff },
            { "created", LV.Util:Now() },
        }),
    }

    if not options.raidDataOnly and type(record.cfg) == "table" then
        local cfg = record.cfg
        local selectedTeam = cfg.selectedTeam
        if excludedTeamIDs[selectedTeam] then
            selectedTeam = includedTeams[1] and includedTeams[1].id or "main"
        end
        counts.config = true
        lines[#lines + 1] = line("CFG", {
            { "enabled", boolString(cfg.enabled) },
            { "prompt", boolString(cfg.prompt) },
            { "promptBefore", cfg.promptBefore },
            { "promptAfter", cfg.promptAfter },
            { "endGrace", cfg.endGrace },
            { "promptTimeout", cfg.promptTimeout },
            { "lateGrace", cfg.lateGrace },
            { "authority", cfg.authority },
            { "rankMin", cfg.rankMin },
            { "rankMax", cfg.rankMax },
            { "tradeRaid", boolString(cfg.tradeRaid) },
            { "whisper", cfg.whisper },
            { "selectedTeam", selectedTeam },
            { "seasonMode", cfg.seasonMode },
            { "pruneMode", cfg.pruneMode },
            { "pruneDays", cfg.pruneDays },
        })

        for _, team in ipairs(includedTeams) do
            if type(team) == "table" then
                local color = LV.Store:NormalizeTeamColor(team.color)
                lines[#lines + 1] = line("TEAM", {
                    { "id", team.id },
                    { "name", team.name },
                    { "tz", team.tz },
                    { "clock24", boolString(team.clock24) },
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

    if not options.raidDataOnly then
        local itemExclusions = LV.Loot and LV.Loot.LootItemExclusions
            and LV.Loot:LootItemExclusions(record) or {}
        local exclusionKeys = {}
        for key in pairs(itemExclusions or {}) do
            exclusionKeys[#exclusionKeys + 1] = key
        end
        table.sort(exclusionKeys)
        for _, key in ipairs(exclusionKeys) do
            local entry = itemExclusions[key]
            local enabled = not LV.Loot or not LV.Loot.IsLootItemExclusionEnabled
                or LV.Loot:IsLootItemExclusionEnabled(entry)
            if enabled then
                counts.exclusions = counts.exclusions + 1
            end
            lines[#lines + 1] = line("XI", {
                { "key", key },
                { "name", type(entry) == "table" and entry.name or tostring(entry or key) },
                { "itemID", type(entry) == "table" and entry.itemID or nil },
                { "enabled", enabled and 1 or 0 },
                { "default", type(entry) == "table" and entry.default or nil },
                { "ts", type(entry) == "table" and entry.ts or 0 },
            })
        end
    end

    local raids = {}
    for raidID, raid in pairs((record and record.r) or {}) do
        if type(raid) == "table" and not excludedRaidIDs[raidID] and (tonumber(raid.st) or 0) >= cutoff then
            raids[#raids + 1] = {
                raid = raid,
                id = self:RaidIdentity(guildKey, raid) or raid.id or raidID,
            }
        end
    end
    table.sort(raids, function(a, b)
        local ast = tonumber(a.raid.st) or 0
        local bst = tonumber(b.raid.st) or 0
        if ast ~= bst then
            return ast < bst
        end
        return tostring(a.id or "") < tostring(b.id or "")
    end)

    for _, raidItem in ipairs(raids) do
        local raid = raidItem.raid
        local exportRaidID = raidItem.id
        counts.raids = counts.raids + 1
        lines[#lines + 1] = line("R", {
            { "id", exportRaidID },
            { "st", raid.st },
            { "sst", raid.sst },
            { "set", raid.set },
            { "en", raid.en },
            { "z", stringForID(guildKey, raid.z) },
            { "iid", raid.iid },
            { "diff", stringForID(guildKey, raid.diff) },
            { "did", raid.did },
            { "sea", raid.sea or LV.Seasons:RaidSeasonID(guildKey, raid) },
            { "team", raid.team },
            { "tn", stringForID(guildKey, raid.tn) },
            { "by", nameForID(guildKey, raid.by) },
            { "reason", raid.reason },
            { "adhoc", raid.adhoc },
            { "adDur", raid.adDur },
            { "adEnd", raid.adEnd },
            { "ks", raidKillSignature(raid) },
            { "p", encodeStatusList(guildKey, raid.p) },
            { "b", encodeStatusList(guildKey, raid.b) },
            { "late", encodeStatusList(guildKey, raid.late) },
            { "out", encodeStatusList(guildKey, raid.out) },
            { "ns", encodeStatusList(guildKey, raid.noshow) },
        })

        for _, kill in ipairs(raid.kills or {}) do
            lines[#lines + 1] = line("K", {
                { "rid", exportRaidID },
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
    local lootRaidIDs = {}
    for _, row in ipairs((record and record.l) or {}) do
        local exportRaidID = raidExportLink(raidExportLinks, type(row) == "table" and row.sid or nil)
        local selectedLink = type(selectedRaidIDs) ~= "table" or exportRaidID ~= nil
        if type(row) == "table" and not excludedRaidIDs[row.sid] and selectedLink
            and not (LV.Loot and LV.Loot.IsWarboundRow and LV.Loot:IsWarboundRow(guildKey, row))
            and (tonumber(row.ts) or 0) >= cutoff then
            lootRows[#lootRows + 1] = row
            lootRaidIDs[row] = exportRaidID or row.sid
        end
    end
    sortedPairsByTimestamp(lootRows, "ts")

    for _, row in ipairs(lootRows) do
        counts.loot = counts.loot + 1
        lines[#lines + 1] = line("L", {
            { "id", row.id },
            { "ts", row.ts },
            { "sid", lootRaidIDs[row] },
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
            { "spec", row.spec },
            { "bdid", row.bdid },
            { "br", row.br },
            { "tr", row.tr },
            { "by", nameForID(guildKey, row.by) },
        })
    end

    local tradeRows = {}
    local tradeRaidIDs = {}
    for _, row in ipairs((record and record.t) or {}) do
        local exportRaidID = raidExportLink(raidExportLinks, type(row) == "table" and row.sid or nil)
        local selectedLink = type(selectedRaidIDs) ~= "table" or exportRaidID ~= nil
        if type(row) == "table" and not excludedRaidIDs[row.sid] and not excludedLootIDs[row.loot]
            and selectedLink
            and (tonumber(row.ts) or 0) >= cutoff then
            tradeRows[#tradeRows + 1] = row
            tradeRaidIDs[row] = exportRaidID or row.sid
        end
    end
    sortedPairsByTimestamp(tradeRows, "ts")

    for _, row in ipairs(tradeRows) do
        counts.trades = counts.trades + 1
        lines[#lines + 1] = line("T", {
            { "id", row.id },
            { "ts", row.ts },
            { "sid", tradeRaidIDs[row] },
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

    local payload, manifestCount = self:BuildManifest(guildInfo.key)
    local cutoff = LV.Util:Now() - SYNC_WINDOW_SECONDS
    local token = tostring(LV.Util:Now()) .. "-" .. tostring(math.random(100000, 999999))
    self.outbound = {
        token = token,
        target = target,
        guildKey = guildInfo.key,
        guildName = guildInfo.name,
        payload = payload,
        manifestCount = manifestCount,
        cutoff = cutoff,
        state = "waiting",
        sent = 0,
        total = 0,
        status = "Waiting for " .. target .. " to accept...",
        protocolVersion = SYNC_PROTOCOL_VERSION,
        twoWay = false,
        selective = true,
    }

    LV.Comms:SendWhisper("Q", target, {
        token,
        guildInfo.key,
        guildInfo.name,
        cutoff,
        tostring(manifestCount) .. " raid summaries",
        SYNC_PROTOCOL_VERSION,
        "selective",
    })
    self:RefreshUI()
end

function LV.DataSync:HandleInvite(parts, sender)
    local token = parts[2]
    local guildKey = parts[3]
    local guildName = parts[4]
    local cutoff = tonumber(parts[5]) or 0
    local counts = parts[6] or ""
    local protocolVersion = tonumber(parts[7]) or 1
    local selective = parts[8] == "selective" and protocolVersion >= SYNC_PROTOCOL_VERSION
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
        protocolVersion = protocolVersion,
        twoWay = not selective and protocolVersion >= 2,
        selective = selective,
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
        protocolVersion = data.protocolVersion or 1,
        twoWay = data.twoWay and true or false,
        reliable = (data.protocolVersion or 1) >= RELIABLE_PROTOCOL_VERSION,
        selective = data.selective and true or false,
    }
    LV.Comms:SendWhisper("A", data.sender, { data.token, data.guildKey, SYNC_PROTOCOL_VERSION })
    if self.inbound.selective then
        local manifest = self:BuildManifest(data.guildKey)
        self:QueueGenericTransfer(self.inbound, "V", manifest, "Sending raid comparison...")
    end
    self:RefreshUI()
end

function LV.DataSync:CancelTicker(transfer)
    if transfer and transfer.ticker then
        transfer.ticker:Cancel()
        transfer.ticker = nil
    end
end

function LV.DataSync:SendCompletion(target, transfer, counts)
    counts = counts or {}
    LV.Comms:SendWhisper("C", target, {
        transfer.token,
        transfer.guildKey,
        counts.raids,
        counts.loot,
        counts.trades,
        counts.skipped,
        counts.config and 1 or 0,
        transfer.guildName or "",
        counts.exclusions or 0,
    })
end

function LV.DataSync:GenericTarget(session)
    return session and (session.target or session.sender) or ""
end

function LV.DataSync:SessionForMessage(token, sender)
    local outbound = self.outbound
    if outbound and outbound.token == token and samePlayer(outbound.target, sender) then
        return outbound
    end
    local inbound = self.inbound
    if inbound and inbound.token == token and samePlayer(inbound.sender, sender) then
        return inbound
    end
    return nil
end

function LV.DataSync:StartNextGenericTransfer(session)
    if not session or session.genericCurrent or not session.genericQueue or #session.genericQueue == 0 then
        return
    end
    local transfer = table.remove(session.genericQueue, 1)
    session.genericCurrent = transfer
    session.state = "transferring"
    session.status = transfer.label or "Transferring selected sync data..."

    local target = self:GenericTarget(session)
    local function pump()
        if not session.genericCurrent or session.genericCurrent.id ~= transfer.id then
            if transfer.ticker then
                transfer.ticker:Cancel()
                transfer.ticker = nil
            end
            return
        end
        local sequence = transfer.acked + 1
        if sequence > transfer.total then
            return
        end
        local now = transferTime()
        if transfer.pendingSequence ~= sequence or not transfer.lastSendAt
            or now - transfer.lastSendAt >= RETRY_DELAY then
            transfer.pendingSequence = sequence
            transfer.lastSendAt = now
            LV.Comms:SendWhisper("G", target, {
                session.token,
                transfer.id,
                transfer.kind,
                sequence,
                transfer.total,
                transfer.chunks[sequence],
            })
        end
    end

    if C_Timer and C_Timer.NewTicker then
        transfer.ticker = C_Timer.NewTicker(SEND_DELAY, pump)
        pump()
    else
        LV:Print("Selective sync requires the Retail timer API.")
        session.state = "error"
        session.status = "Unable to start selective sync."
    end
    self:RefreshUI()
end

function LV.DataSync:QueueGenericTransfer(session, kind, payload, label)
    if not session then
        return false
    end
    local chunks = {}
    local cursor = 1
    payload = tostring(payload or "")
    while cursor <= #payload do
        chunks[#chunks + 1] = string.sub(payload, cursor, cursor + CHUNK_SIZE - 1)
        cursor = cursor + CHUNK_SIZE
    end
    if #chunks == 0 then
        chunks[1] = ""
    end
    session.genericQueue = session.genericQueue or {}
    session.genericSerial = (tonumber(session.genericSerial) or 0) + 1
    local transferID = tostring(LV.Util:Now()) .. tostring(session.genericSerial)
        .. tostring(math.random(1000, 9999))
    session.genericQueue[#session.genericQueue + 1] = {
        id = transferID,
        kind = kind,
        label = label,
        chunks = chunks,
        total = #chunks,
        acked = 0,
    }
    self:StartNextGenericTransfer(session)
    return true
end

function LV.DataSync:BuildComparison(session)
    if not session or type(session.remoteManifest) ~= "table" then
        return nil
    end
    local record = LV.Store:GuildRecord(session.guildKey)
    local localManifest = self:ParseManifest(self:BuildManifest(session.guildKey))
    local comparison = { missingLocal = {}, missingRemote = {} }
    local sender = self:GenericTarget(session)
    local function countsEqual(left, right)
        return (tonumber(left and left.kills) or 0) == (tonumber(right and right.kills) or 0)
            and (tonumber(left and left.people) or 0) == (tonumber(right and right.people) or 0)
            and (tonumber(left and left.loot) or 0) == (tonumber(right and right.loot) or 0)
            and (tonumber(left and left.trades) or 0) == (tonumber(right and right.trades) or 0)
    end

    for _, remote in ipairs(session.remoteManifest.raids or {}) do
        local _, raid = self:FindRaid(session.guildKey, record, sender, {
            id = remote.id,
            st = remote.st,
            sst = remote.sst,
            iid = remote.iid,
            team = remote.team,
            ks = remote.killSignature,
            people = remote.people,
        })
        local localEntry = raid and localManifest.byID[raid.id]
        if raid and not localEntry then
            for _, candidate in ipairs(localManifest.raids or {}) do
                if self:ManifestRaidsMatch(candidate, remote) then
                    localEntry = candidate
                    break
                end
            end
        end
        local remoteHasMore = localEntry and (
            (tonumber(remote.kills) or 0) > (tonumber(localEntry.kills) or 0)
            or (tonumber(remote.people) or 0) > (tonumber(localEntry.people) or 0)
            or (tonumber(remote.loot) or 0) > (tonumber(localEntry.loot) or 0)
            or (tonumber(remote.trades) or 0) > (tonumber(localEntry.trades) or 0)
            or (countsEqual(remote, localEntry)
                and remote.signature ~= "" and localEntry.signature ~= ""
                and remote.signature ~= localEntry.signature))
        if not raid or remoteHasMore then
            remote.update = raid and true or nil
            comparison.missingLocal[#comparison.missingLocal + 1] = remote
        end
    end

    for _, localEntry in ipairs(localManifest.raids or {}) do
        local found = false
        local remoteEntry
        for _, remote in ipairs(session.remoteManifest.raids or {}) do
            if self:ManifestRaidsMatch(localEntry, remote) then
                found = true
                remoteEntry = remote
                break
            end
        end
        local localHasMore = remoteEntry and (
            (tonumber(localEntry.kills) or 0) > (tonumber(remoteEntry.kills) or 0)
            or (tonumber(localEntry.people) or 0) > (tonumber(remoteEntry.people) or 0)
            or (tonumber(localEntry.loot) or 0) > (tonumber(remoteEntry.loot) or 0)
            or (tonumber(localEntry.trades) or 0) > (tonumber(remoteEntry.trades) or 0)
            or (countsEqual(localEntry, remoteEntry)
                and localEntry.signature ~= "" and remoteEntry.signature ~= ""
                and localEntry.signature ~= remoteEntry.signature))
        if not found or localHasMore then
            localEntry.update = found and true or nil
            comparison.missingRemote[#comparison.missingRemote + 1] = localEntry
        end
    end
    session.localManifest = localManifest
    session.comparison = comparison
    return comparison
end

function LV.DataSync:ShowComparison(session)
    self:BuildComparison(session)
    if LV.UI and LV.UI.ShowSyncComparison then
        LV.UI:ShowSyncComparison(session)
    end
end

function LV.DataSync:RequestSelected(session, selected)
    if not session or type(session.remoteManifest) ~= "table" then
        return false, "The raid comparison is no longer available."
    end
    if session.requestPending then
        return false, "Waiting for the current raid selection to finish."
    end
    local lines = {}
    local count = 0
    for _, raid in ipairs(session.remoteManifest.raids or {}) do
        if selected and selected[raid.id] == true then
            lines[#lines + 1] = line("RQ", { { "id", raid.id } })
            count = count + 1
        end
    end
    if count == 0 then
        return false, "Select at least one raid."
    end
    session.status = "Requesting " .. tostring(count) .. " selected raid(s)..."
    session.requestPending = true
    self:QueueGenericTransfer(session, "X", table.concat(lines, "\n"), session.status)
    return true, count
end

function LV.DataSync:HandleGenericPayload(session, transferKind, payload, sender)
    if transferKind == "V" then
        local manifest = self:ParseManifest(payload)
        if manifest.version ~= SYNC_PROTOCOL_VERSION or manifest.guildKey ~= session.guildKey then
            session.state = "error"
            session.status = "The raid comparison uses an incompatible sync version."
            self:RefreshUI()
            return
        end
        session.remoteManifest = manifest
        session.state = "ready"
        session.status = "Raid comparison ready. Select only the raids you want to import."
        self:ShowComparison(session)
        self:RefreshUI()
        return
    end

    if transferKind == "X" then
        local selected = {}
        for raw in tostring(payload or ""):gmatch("[^\n]+") do
            local kind, fields = parseLine(raw)
            if kind == "RQ" and fields.id and fields.id ~= "" then
                selected[fields.id] = true
            end
        end
        local export, counts = self:BuildExport(session.guildKey, selected, { raidDataOnly = true })
        session.counts = counts
        self:QueueGenericTransfer(session, "P", export,
            "Sending " .. self:FormatCounts(counts) .. "...")
        return
    end

    if transferKind == "P" then
        local imported = self:ImportPayload(sender, payload, { preserveConfig = true })
        session.requestPending = nil
        session.imported = imported
        session.state = "ready"
        session.status = "Imported " .. self:FormatCounts(imported) .. "."
        LV:Print(self:TransferSummary(session.guildName, imported))
        local completion = line("GC", {
            { "raids", imported.raids },
            { "loot", imported.loot },
            { "trades", imported.trades },
            { "skipped", imported.skipped },
            { "relinkedLoot", imported.relinkedLoot },
            { "relinkedTrades", imported.relinkedTrades },
        })
        self:QueueGenericTransfer(session, "C", completion, "Confirming selected raid import...")
        local manifest = self:BuildManifest(session.guildKey)
        self:QueueGenericTransfer(session, "V", manifest, "Refreshing raid comparison...")
        self:ShowComparison(session)
        return
    end

    if transferKind == "C" then
        local kind, fields = parseLine(payload)
        if kind == "GC" then
            session.sentImported = {
                raids = tonumber(fields.raids) or 0,
                loot = tonumber(fields.loot) or 0,
                trades = tonumber(fields.trades) or 0,
                skipped = tonumber(fields.skipped) or 0,
                relinkedLoot = tonumber(fields.relinkedLoot) or 0,
                relinkedTrades = tonumber(fields.relinkedTrades) or 0,
            }
            session.state = "ready"
            session.status = tostring(sender or self:GenericTarget(session)) .. " imported "
                .. self:FormatCounts(session.sentImported) .. "."
            self:RefreshUI()
        end
    end
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

    if outbound.reliable and C_Timer and C_Timer.NewTicker then
        local function pump()
            if not self.outbound or self.outbound.token ~= outbound.token then
                self:CancelTicker(outbound)
                return
            end

            if outbound.state == "sent" and not outbound.twoWay then
                local now = transferTime()
                if not outbound.lastCompletionRequest or now - outbound.lastCompletionRequest >= RETRY_DELAY then
                    outbound.lastCompletionRequest = now
                    LV.Comms:SendWhisper("R", outbound.target, { outbound.token, "C", 0 })
                end
                return
            end

            if outbound.state ~= "sending" then
                self:CancelTicker(outbound)
                return
            end

            local sequence = outbound.sent + 1
            local now = transferTime()
            if outbound.pendingSequence ~= sequence or not outbound.lastSendAt
                or now - outbound.lastSendAt >= RETRY_DELAY then
                outbound.pendingSequence = sequence
                outbound.lastSendAt = now
                LV.Comms:SendWhisper("D", outbound.target, {
                    outbound.token,
                    sequence,
                    outbound.total,
                    outbound.chunks[sequence],
                })
            end
        end

        outbound.ticker = C_Timer.NewTicker(SEND_DELAY, pump)
        pump()
        self:RefreshUI()
        return
    end

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

function LV.DataSync:BeginReturnChunkSend()
    local inbound = self.inbound
    if not inbound or not inbound.twoWay or inbound.state ~= "receiving" then
        return
    end

    local payload = inbound.returnPayload
    local counts = inbound.returnCounts
    if not payload then
        payload, counts = self:BuildExport(inbound.guildKey)
    end
    local chunks = {}
    local cursor = 1
    while cursor <= #payload do
        chunks[#chunks + 1] = string.sub(payload, cursor, cursor + CHUNK_SIZE - 1)
        cursor = cursor + CHUNK_SIZE
    end
    if #chunks == 0 then
        chunks[1] = ""
    end

    inbound.returnCounts = counts
    inbound.returnChunks = chunks
    inbound.forwardReceived = inbound.received
    inbound.received = nil
    inbound.sent = 0
    inbound.total = #chunks
    inbound.state = "returning"
    inbound.status = "Returning merged data to " .. tostring(inbound.sender or "sync partner") .. "..."

    if inbound.reliable and C_Timer and C_Timer.NewTicker then
        local function pump()
            if not self.inbound or self.inbound.token ~= inbound.token then
                self:CancelTicker(inbound)
                return
            end

            if inbound.state == "return_sent" then
                local now = transferTime()
                if not inbound.lastCompletionRequest or now - inbound.lastCompletionRequest >= RETRY_DELAY then
                    inbound.lastCompletionRequest = now
                    LV.Comms:SendWhisper("R", inbound.sender, { inbound.token, "C", 0 })
                end
                return
            end

            if inbound.state ~= "returning" then
                self:CancelTicker(inbound)
                return
            end

            local sequence = inbound.sent + 1
            local now = transferTime()
            if inbound.pendingSequence ~= sequence or not inbound.lastSendAt
                or now - inbound.lastSendAt >= RETRY_DELAY then
                inbound.pendingSequence = sequence
                inbound.lastSendAt = now
                LV.Comms:SendWhisper("M", inbound.sender, {
                    inbound.token,
                    sequence,
                    inbound.total,
                    inbound.returnChunks[sequence],
                })
            end
        end

        inbound.ticker = C_Timer.NewTicker(SEND_DELAY, pump)
        pump()
        self:RefreshUI()
        return
    end

    local function sendNext()
        if not self.inbound or self.inbound.token ~= inbound.token then
            if inbound.ticker then
                inbound.ticker:Cancel()
            end
            return
        end

        inbound.sent = inbound.sent + 1
        LV.Comms:SendWhisper("M", inbound.sender, {
            inbound.token,
            inbound.sent,
            inbound.total,
            inbound.returnChunks[inbound.sent],
        })

        if inbound.sent >= inbound.total then
            if inbound.ticker then
                inbound.ticker:Cancel()
                inbound.ticker = nil
            end
            inbound.state = "return_sent"
            inbound.status = "Merged data sent. Waiting for " .. tostring(inbound.sender or "sync partner") .. " to import..."
        end
        self:RefreshUI()
    end

    if C_Timer and C_Timer.NewTicker then
        inbound.ticker = C_Timer.NewTicker(SEND_DELAY, sendNext)
    else
        while inbound.sent < inbound.total do
            sendNext()
        end
    end

    self:RefreshUI()
end

function LV.DataSync:ManifestRaidsMatch(left, right)
    if type(left) ~= "table" or type(right) ~= "table" then
        return false
    end
    local leftTeam = tostring(left.team or "main")
    local rightTeam = tostring(right.team or "main")
    local leftIID = tonumber(left.iid) or 0
    local rightIID = tonumber(right.iid) or 0
    if not LV.Util:IsBlank(left.id) and tostring(left.id) == tostring(right.id or "") then
        return true
    end
    local delta = math.abs((tonumber(left.st) or 0) - (tonumber(right.st) or 0))
    if leftTeam ~= rightTeam or delta > 10 * 60
        or (leftIID > 0 and rightIID > 0 and leftIID ~= rightIID) then
        return false
    end
    if delta <= 5 then
        return true
    end
    local leftKills = tostring(left.killSignature or left.ks or "")
    local rightKills = tostring(right.killSignature or right.ks or "")
    if leftKills ~= "" and leftKills == rightKills then
        return true
    end
    local leftScheduled = tonumber(left.sst) or 0
    local rightScheduled = tonumber(right.sst) or 0
    if leftScheduled > 0 and rightScheduled > 0 and math.abs(leftScheduled - rightScheduled) <= 5 * 60 then
        return true
    end
    local leftPeople = tonumber(left.people) or 0
    local rightPeople = tonumber(right.people) or 0
    return delta <= 5 * 60 and leftPeople >= 3 and leftPeople == rightPeople
end

local function incomingRaidNames(fields)
    local names = {}
    for _, key in ipairs({ "p", "b", "late", "out", "ns" }) do
        for _, item in ipairs(split(fields and fields[key] or "", ",")) do
            local name = normalizedName(split(item, "|")[1]):lower()
            if name ~= "" then
                names[name] = true
            end
        end
    end
    return names
end

local function localRaidNames(guildKey, raid)
    local names = {}
    for _, map in ipairs({ raid and raid.p, raid and raid.b, raid and raid.late,
        raid and raid.out, raid and raid.noshow }) do
        for id in pairs(map or {}) do
            local name = nameForID(guildKey, id):lower()
            if name ~= "" then
                names[name] = true
            end
        end
    end
    return names
end

local function similarRaidRoster(guildKey, raid, fields)
    local incoming = incomingRaidNames(fields)
    local localNames = localRaidNames(guildKey, raid)
    local incomingCount = countMap(incoming)
    local localCount = countMap(localNames)
    if incomingCount == 0 or localCount == 0 then
        return false
    end
    local common = 0
    for name in pairs(incoming) do
        if localNames[name] then
            common = common + 1
        end
    end
    local smaller = math.min(incomingCount, localCount)
    return common >= math.min(3, smaller) and common / smaller >= 0.60
end

function LV.DataSync:FindRaid(guildKey, record, sender, fields)
    fields = fields or {}
    local remoteID = fields.id
    for raidID, raid in pairs((record and record.r) or {}) do
        if type(raid) == "table" and remoteID ~= nil
            and tostring(self:RaidIdentity(guildKey, raid) or "") == tostring(remoteID) then
            return raidID, raid, false
        end
    end
    for raidID, raid in pairs((record and record.r) or {}) do
        if type(raid) == "table" and type(raid.sy) == "table" then
            for remoteSender, knownID in pairs(raid.sy) do
                if samePlayer(remoteSender, sender) and knownID == remoteID then
                    return raidID, raid, true
                end
            end
        end
    end

    local st = tonumber(fields.st) or 0
    local iid = tonumber(fields.iid) or 0
    local team = fields.team
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

    for raidID, raid in pairs((record and record.r) or {}) do
        if type(raid) == "table" then
            local summaryMatches = self:ManifestRaidsMatch({
                st = raid.st,
                sst = raid.sst,
                iid = raid.iid,
                team = raid.team,
                killSignature = raidKillSignature(raid),
                people = raidAttendanceCount(raid),
            }, {
                st = st,
                sst = fields.sst,
                iid = iid,
                team = team,
                killSignature = fields.ks,
                people = fields.people,
            })
            if summaryMatches or (math.abs((tonumber(raid.st) or 0) - st) <= 10 * 60
                and (LV.Util:IsBlank(team) or raid.team == team)
                and (iid == 0 or (tonumber(raid.iid) or 0) == 0 or iid == (tonumber(raid.iid) or 0))
                and similarRaidRoster(guildKey, raid, fields)) then
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
    local incomingTeamID = fields.team ~= "" and fields.team or "main"
    if LV.Store:IsGlobalPugTeam(incomingTeamID) then
        remoteRaidMap[fields.id] = EXCLUDED_REMOTE_RAID
        return false, true
    end
    local localTeam = LV.Store:GetTeamByID(record, incomingTeamID)
    if localTeam and localTeam.excludeSync == true then
        remoteRaidMap[fields.id] = EXCLUDED_REMOTE_RAID
        return false, true
    end

    local raidID, raid, knownRemote = self:FindRaid(guildKey, record, sender, fields)
    local created = false

    if not raid then
        local preferredID = tostring(fields.id or "")
        if preferredID:match("^rs[%w%-]+$") and record.r[preferredID] == nil then
            raidID = preferredID
        else
            raidID = LV.Store:NewID(record, "raid", "r")
        end
        raid = {
            id = raidID,
            cid = preferredID:match("^rs[%w%-]+$") and preferredID or nil,
            st = tonumber(fields.st) or LV.Util:Now(),
            sst = tonumber(fields.sst),
            set = tonumber(fields.set),
            en = tonumber(fields.en) or tonumber(fields.st) or LV.Util:Now(),
            z = LV.Store:StringID(guildKey, fields.z or ""),
            iid = tonumber(fields.iid) or 0,
            diff = LV.Store:StringID(guildKey, fields.diff or ""),
            did = tonumber(fields.did) or 0,
            sea = LV.Seasons:IsSeasonID(fields.sea) and fields.sea or nil,
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
        raid.sst = raid.sst or tonumber(fields.sst)
        raid.set = raid.set or tonumber(fields.set)
        raid.z = raid.z or LV.Store:StringID(guildKey, fields.z or "")
        if (tonumber(raid.iid) or 0) == 0 then raid.iid = tonumber(fields.iid) or 0 end
        raid.diff = raid.diff or LV.Store:StringID(guildKey, fields.diff or "")
        if (tonumber(raid.did) or 0) == 0 then raid.did = tonumber(fields.did) or 0 end
        raid.sea = raid.sea or (LV.Seasons:IsSeasonID(fields.sea) and fields.sea or nil)
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
    local incomingDifficulty = tonumber(fields.d) or 0
    local function mergeNames(target, incoming)
        local seen = {}
        for _, nameID in ipairs(target or {}) do
            seen[nameID] = true
        end
        for _, nameID in ipairs(incoming or {}) do
            if not seen[nameID] then
                target[#target + 1] = nameID
                seen[nameID] = true
            end
        end
    end
    for _, kill in ipairs(raid.kills) do
        local existingDifficulty = tonumber(kill.d) or 0
        if (tonumber(kill.e) or 0) == encounterID
            and (existingDifficulty == incomingDifficulty or existingDifficulty == 0 or incomingDifficulty == 0) then
            kill.b = kill.b or LV.Store:StringID(guildKey, fields.boss or "")
            if existingDifficulty == 0 then kill.d = incomingDifficulty end
            kill.n = math.max(tonumber(kill.n) or 0, tonumber(fields.n) or 0)
            kill.p = kill.p or {}
            kill.bench = kill.bench or {}
            kill.late = kill.late or {}
            kill.out = kill.out or {}
            kill.noshow = kill.noshow or {}
            mergeNames(kill.p, decodeNameList(guildKey, fields.p))
            mergeNames(kill.bench, decodeNameList(guildKey, fields.bench))
            mergeNames(kill.late, decodeNameList(guildKey, fields.late))
            mergeNames(kill.out, decodeNameList(guildKey, fields.out))
            mergeNames(kill.noshow, decodeNameList(guildKey, fields.ns))
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

function LV.DataSync:FindLoot(record, sender, remoteID, playerID, itemKeyID, itemID, timestamp, encounterID, source, bonusEventID)
    for _, row in ipairs((record and record.l) or {}) do
        if type(row) == "table" and type(row.sy) == "table" and row.sy[sender] == remoteID then
            return row, true
        end
    end

    if source == "bonus" and not LV.Util:IsBlank(bonusEventID) then
        for _, row in ipairs((record and record.l) or {}) do
            if type(row) == "table" and row.br == bonusEventID then
                return row, false
            end
        end
    end

    if source == "bonus" then
        return nil, false
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
    if remoteRaidMap[fields.sid] == EXCLUDED_REMOTE_RAID then
        return false, true
    end

    local fullName = normalizedName(fields.p)
    local itemKey = LV.Util:ItemKey(fields.item or "")
    if fullName == "" or itemKey == "" then
        return false, true
    end
    if LV.Util:IsItemWarbound(itemKey) then
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

    local row, knownRemote = self:FindLoot(record, sender, fields.id, playerID, itemKeyID, itemID,
        fields.ts, fields.e, fields.src, fields.br)
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
        row.spec = row.spec or tonumber(fields.spec) or nil
        row.bdid = row.bdid or tonumber(fields.bdid) or nil
        row.br = row.br or (fields.br ~= "" and fields.br or nil)
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
        spec = tonumber(fields.spec) or nil,
        bdid = tonumber(fields.bdid) or nil,
        br = fields.br ~= "" and fields.br or nil,
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
    if remoteRaidMap[fields.sid] == EXCLUDED_REMOTE_RAID then
        return false, true
    end

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

function LV.DataSync:RelinkOrphanedRaidEvents(guildKey, record, raidID)
    local raid = record and record.r and record.r[raidID]
    if type(raid) ~= "table" then
        return 0, 0
    end

    local raidStart = tonumber(raid.st) or 0
    if raidStart <= 0 then
        return 0, 0
    end
    local raidEnd = math.max(raidStart, tonumber(raid.en) or 0, tonumber(raid.set) or 0,
        tonumber(raid.adEnd) or 0)
    if raidEnd <= raidStart then
        raidEnd = raidStart + (8 * 60 * 60)
    end
    local windowStart = raidStart - (10 * 60)
    local windowEnd = raidEnd + (30 * 60)
    local raidTeam = tostring(raid.team or "main")
    local raidInstanceID = tonumber(raid.iid) or 0
    local raidZone = stringForID(guildKey, raid.z):lower()
    local encounterIDs = {}
    for _, kill in ipairs(raid.kills or {}) do
        local encounterID = tonumber(kill and kill.e) or 0
        if encounterID > 0 then
            encounterIDs[encounterID] = true
        end
    end

    local function inRaidWindow(row)
        local timestamp = tonumber(row and row.ts) or 0
        return timestamp >= windowStart and timestamp <= windowEnd
    end

    local function savedRaidMatches(row)
        local savedStart = tonumber(row and row.rst) or 0
        if savedStart <= 0 or math.abs(savedStart - raidStart) > 10 * 60
            or tostring(row.rt or "main") ~= raidTeam then
            return false
        end
        local savedInstanceID = tonumber(row.rii) or 0
        return savedInstanceID == 0 or raidInstanceID == 0 or savedInstanceID == raidInstanceID
    end

    local function lootMatches(row)
        if savedRaidMatches(row) then
            return true
        end
        local encounterID = tonumber(row.e) or 0
        if encounterID > 0 and encounterIDs[encounterID] then
            return true
        end
        local rowInstanceID = tonumber(row.iid) or 0
        if raidInstanceID > 0 and rowInstanceID > 0 and raidInstanceID == rowInstanceID then
            return true
        end
        local rowInstance = stringForID(guildKey, row.inst):lower()
        return raidZone ~= "" and rowInstance ~= "" and raidZone == rowInstance
    end

    local orphanRaidIDs = {}
    local relinkedLootIDs = {}
    local relinkedLoot = 0
    for _, row in ipairs(record.l or {}) do
        local oldRaidID = type(row) == "table" and row.sid or nil
        if oldRaidID and not record.r[oldRaidID] and inRaidWindow(row) and lootMatches(row) then
            orphanRaidIDs[oldRaidID] = true
            if row.id then
                relinkedLootIDs[row.id] = true
            end
            row.sid = raidID
            row.rt = nil
            row.rst = nil
            row.rii = nil
            relinkedLoot = relinkedLoot + 1
        end
    end

    local relinkedTrades = 0
    for _, row in ipairs(record.t or {}) do
        local oldRaidID = type(row) == "table" and row.sid or nil
        local sourceLoot = type(row) == "table" and self:LootByID(record, row.loot) or nil
        local followsRestoredLoot = sourceLoot and sourceLoot.sid == raidID
            and (relinkedLootIDs[sourceLoot.id] or orphanRaidIDs[oldRaidID])
        local followsOrphanGroup = oldRaidID and orphanRaidIDs[oldRaidID]
        local followsSavedRaid = oldRaidID and not record.r[oldRaidID]
            and inRaidWindow(row) and savedRaidMatches(row)
        if followsRestoredLoot or followsOrphanGroup or followsSavedRaid then
            row.sid = raidID
            row.rt = nil
            row.rst = nil
            row.rii = nil
            relinkedTrades = relinkedTrades + 1
        end
    end

    return relinkedLoot, relinkedTrades
end

function LV.DataSync:RepairOrphanedRaidEvents(guildKey, silent)
    if not guildKey or guildKey == "" then
        return 0, 0
    end
    self.repairedGuilds = self.repairedGuilds or {}
    if self.repairedGuilds[guildKey] then
        return 0, 0
    end

    local record = LV.Store:GuildRecord(guildKey)
    local raids = {}
    for raidID, raid in pairs((record and record.r) or {}) do
        if type(raid) == "table" then
            raids[#raids + 1] = { id = raidID, st = tonumber(raid.st) or 0 }
        end
    end
    table.sort(raids, function(a, b)
        if a.st ~= b.st then
            return a.st > b.st
        end
        return tostring(a.id) < tostring(b.id)
    end)

    local relinkedLoot = 0
    local relinkedTrades = 0
    for _, item in ipairs(raids) do
        local lootCount, tradeCount = self:RelinkOrphanedRaidEvents(guildKey, record, item.id)
        relinkedLoot = relinkedLoot + lootCount
        relinkedTrades = relinkedTrades + tradeCount
    end
    self.repairedGuilds[guildKey] = true

    local restored = relinkedLoot + relinkedTrades
    if restored > 0 and not silent then
        LV:Print("Restored " .. tostring(restored) .. " orphaned loot/trade link(s) to their raid tags.")
    end
    return relinkedLoot, relinkedTrades
end

function LV.DataSync:ImportLootItemExclusion(record, fields)
    if type(record) ~= "table" or not LV.Loot or not LV.Loot.LootItemExclusions then
        return false
    end

    local key = LV.Util:Trim(fields.key or "")
    if key == "" or (not key:match("^id:%d+$") and not key:match("^name:.+$")) then
        return false
    end

    local exclusions = LV.Loot:LootItemExclusions(record)
    local existing = exclusions[key]
    local incomingTS = tonumber(fields.ts) or 0
    local existingTS = type(existing) == "table" and (tonumber(existing.ts) or 0) or 0
    local enabled = fields.enabled == nil or parseBool(fields.enabled)
    local existingEnabled = LV.Loot:IsLootItemExclusionEnabled(existing)
    if existing and existingTS > incomingTS then
        return false
    end
    if existing and existingTS == incomingTS and not existingEnabled and enabled then
        return false
    end

    local name = LV.Util:Trim(fields.name or "")
    exclusions[key] = {
        name = name ~= "" and name or key,
        itemID = tonumber(fields.itemID) or nil,
        enabled = enabled and 1 or 0,
        default = parseBool(fields.default) and 1 or nil,
        ts = incomingTS,
    }
    record.x.itemSeed[key] = 1
    return not existing
        or existingTS ~= incomingTS
        or existingEnabled ~= enabled
        or (type(existing) == "table" and tostring(existing.name or "") ~= tostring(exclusions[key].name or ""))
end

function LV.DataSync:ImportConfig(record, fields, configState)
    if type(record) ~= "table" then
        return false
    end

    record.cfg = record.cfg or {}
    local cfg = record.cfg
    local originalSelectedTeam = cfg.selectedTeam
    if not configState.preserveConfig then
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
    end

    local existingTeams = {}
    local preservedTeamIDs = {}
    for _, team in ipairs(cfg.teams or {}) do
        if type(team) == "table" and team.id then
            existingTeams[team.id] = team
            if team.excludeSync == true then
                preservedTeamIDs[team.id] = true
            end
        end
    end
    if preservedTeamIDs[originalSelectedTeam] then
        cfg.selectedTeam = originalSelectedTeam
    end
    cfg.schedules = nil
    cfg._teamsMigrated = 1
    configState.seen = true
    configState.teamsByID = {}
    configState.existingTeams = existingTeams
    configState.skippedTeamIDs = {}
    configState.preservedTeamIDs = preservedTeamIDs
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
    if LV.Store:IsGlobalPugTeam(teamID) then
        return false
    end
    if configState.preservedTeamIDs and configState.preservedTeamIDs[teamID] then
        configState.skippedTeamIDs[teamID] = true
        return false
    end

    local team = configState.existingTeams and configState.existingTeams[teamID]
    if team and configState.preserveConfig then
        configState.skippedTeamIDs[teamID] = true
        return false
    end
    local created = not team
    if not team then
        team = { id = teamID }
    end
    team.name = LV.Util:Trim(fields.name) ~= "" and LV.Util:Trim(fields.name) or teamID
    team.tz = LV.Util:NormalizeTimezone(fields.tz)
    team.clock24 = parseBool(fields.clock24)
    team.excludeSync = false
    team.color = LV.Store:NormalizeTeamColor({
        r = fields.cr,
        g = fields.cg,
        b = fields.cb,
        a = fields.ca,
    })
    team.schedules = {}

    cfg.teams = cfg.teams or {}
    if created then
        cfg.teams[#cfg.teams + 1] = team
        configState.existingTeams[teamID] = team
    end
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

function LV.DataSync:ImportPayload(sender, payload, options)
    sender = sender or "unknown"
    local guildKey = LV.Guild:CurrentKey()
    if not guildKey then
        return { config = false, exclusions = 0, raids = 0, loot = 0, trades = 0, skipped = 0,
            kills = 0, relinkedLoot = 0, relinkedTrades = 0 }
    end

    local record = LV.Store:GuildRecord(guildKey)
    local remoteRaidMap = {}
    local remoteLootMap = {}
    local configState = {
        seen = false,
        teamsByID = {},
        preserveConfig = type(options) == "table" and options.preserveConfig == true,
    }
    local imported = { config = false, exclusions = 0, raids = 0, loot = 0, trades = 0, skipped = 0,
        kills = 0, relinkedLoot = 0, relinkedTrades = 0 }

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
            elseif kind == "XI" then
                if self:ImportLootItemExclusion(record, fields) then
                    imported.exclusions = imported.exclusions + 1
                end
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

    local importedRaidIDs = {}
    for _, localRaidID in pairs(remoteRaidMap) do
        if (type(localRaidID) == "string" or type(localRaidID) == "number") and record.r[localRaidID] then
            importedRaidIDs[localRaidID] = true
        end
    end
    for localRaidID in pairs(importedRaidIDs) do
        local relinkedLoot, relinkedTrades = self:RelinkOrphanedRaidEvents(guildKey, record, localRaidID)
        imported.relinkedLoot = imported.relinkedLoot + relinkedLoot
        imported.relinkedTrades = imported.relinkedTrades + relinkedTrades
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
        if outbound and outbound.token == parts[2] and outbound.guildKey == parts[3]
            and samePlayer(outbound.target, sender) then
            outbound.remoteProtocolVersion = tonumber(parts[4]) or 1
            outbound.twoWay = outbound.remoteProtocolVersion >= 2
            outbound.reliable = outbound.remoteProtocolVersion >= RELIABLE_PROTOCOL_VERSION
            if outbound.selective then
                if outbound.remoteProtocolVersion < SYNC_PROTOCOL_VERSION then
                    outbound.state = "incompatible"
                    outbound.status = tostring(sender or outbound.target)
                        .. " must update LootViewer before selective sync can start."
                    LV:Print(outbound.status)
                    self:SendCompletion(sender, outbound, {})
                    self:RefreshUI()
                    return
                end
                outbound.twoWay = false
                outbound.status = tostring(sender or outbound.target)
                    .. " accepted. Exchanging raid summaries..."
                self:QueueGenericTransfer(outbound, "V", outbound.payload, "Sending raid comparison...")
                return
            end
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

    if kind == "G" then
        local session = self:SessionForMessage(parts[2], sender)
        local transferID = parts[3]
        local transferKind = parts[4]
        local sequence = tonumber(parts[5]) or 0
        local total = tonumber(parts[6]) or 0
        if not session or not session.selective or not transferID or transferID == ""
            or sequence <= 0 or total <= 0 or sequence > total then
            return
        end

        session.genericIncoming = session.genericIncoming or {}
        local incoming = session.genericIncoming[transferID]
        if not incoming then
            incoming = {
                kind = transferKind,
                total = total,
                received = 0,
                chunks = {},
            }
            session.genericIncoming[transferID] = incoming
        end
        if incoming.kind ~= transferKind or incoming.total ~= total then
            return
        end
        if not incoming.chunks[sequence] then
            incoming.chunks[sequence] = parts[7] or ""
            incoming.received = incoming.received + 1
        end
        LV.Comms:SendWhisper("R", sender, { session.token, "G", transferID, sequence })
        session.genericReceiving = incoming
        session.status = "Receiving selective sync data from " .. tostring(sender) .. "..."

        if incoming.received >= incoming.total and not incoming.processed then
            incoming.processed = true
            local chunks = {}
            for index = 1, incoming.total do
                chunks[#chunks + 1] = incoming.chunks[index] or ""
            end
            session.genericReceiving = nil
            self:HandleGenericPayload(session, incoming.kind, table.concat(chunks, ""), sender)
        end
        self:RefreshUI()
        return
    end

    if kind == "D" then
        local inbound = self.inbound
        if not inbound or inbound.token ~= parts[2] or not samePlayer(inbound.sender, sender) then
            return
        end

        local sequence = tonumber(parts[3]) or 0
        local total = tonumber(parts[4]) or 0
        if sequence <= 0 or total <= 0 then
            return
        end

        if inbound.forwardComplete then
            if inbound.reliable then
                LV.Comms:SendWhisper("R", sender, { inbound.token, "D", sequence })
            end
            return
        end

        inbound.total = total
        if not inbound.chunks[sequence] then
            inbound.chunks[sequence] = parts[5] or ""
            inbound.received = inbound.received + 1
        end
        if inbound.reliable then
            LV.Comms:SendWhisper("R", sender, { inbound.token, "D", sequence })
        end
        inbound.status = "Receiving data from " .. tostring(sender or "sync partner") .. "..."

        if inbound.received >= inbound.total and not inbound.forwardComplete then
            inbound.forwardComplete = true
            local chunks = {}
            for index = 1, inbound.total do
                chunks[#chunks + 1] = inbound.chunks[index] or ""
            end
            if inbound.twoWay and not inbound.returnPayload then
                inbound.returnPayload, inbound.returnCounts = self:BuildExport(inbound.guildKey)
            end
            local imported = self:ImportPayload(sender, table.concat(chunks, ""))
            inbound.imported = imported
            if inbound.twoWay then
                inbound.status = "Imported " .. self:FormatCounts(imported) .. ". Preparing merged return..."
                self:BeginReturnChunkSend()
            else
                inbound.state = "complete"
                inbound.status = "Imported " .. self:FormatCounts(imported) .. "."
                LV:Print(self:TransferSummary(inbound.guildName, imported))
                self:SendCompletion(sender, inbound, imported)
            end
        end
        self:RefreshUI()
        return
    end

    if kind == "M" then
        local outbound = self.outbound
        if not outbound or not outbound.twoWay or outbound.token ~= parts[2]
            or not samePlayer(outbound.target, sender) then
            return
        end

        local sequence = tonumber(parts[3]) or 0
        local total = tonumber(parts[4]) or 0
        if sequence <= 0 or total <= 0 then
            return
        end

        if outbound.returnComplete then
            if outbound.reliable then
                LV.Comms:SendWhisper("R", sender, { outbound.token, "M", sequence })
            end
            return
        end

        outbound.returnChunks = outbound.returnChunks or {}
        outbound.received = outbound.received or 0
        outbound.total = total
        outbound.state = "receiving_return"
        if not outbound.returnChunks[sequence] then
            outbound.returnChunks[sequence] = parts[5] or ""
            outbound.received = outbound.received + 1
        end
        if outbound.reliable then
            LV.Comms:SendWhisper("R", sender, { outbound.token, "M", sequence })
        end
        outbound.status = "Receiving merged data from " .. tostring(sender or outbound.target) .. "..."

        if outbound.received >= outbound.total and not outbound.returnComplete then
            outbound.returnComplete = true
            local chunks = {}
            for index = 1, outbound.total do
                chunks[#chunks + 1] = outbound.returnChunks[index] or ""
            end
            local imported = self:ImportPayload(sender, table.concat(chunks, ""), { preserveConfig = true })
            outbound.returnImported = imported
            outbound.state = "complete"
            outbound.status = "Two-way sync complete with " .. tostring(sender or outbound.target) .. "."
            LV:Print("Two-way " .. self:TransferSummary(outbound.guildName, imported))
            self:SendCompletion(sender, outbound, imported)
        end
        self:RefreshUI()
        return
    end

    if kind == "R" then
        local token = parts[2]
        local direction = parts[3]

        if direction == "G" then
            local session = self:SessionForMessage(token, sender)
            local transferID = parts[4]
            local sequence = tonumber(parts[5]) or 0
            local transfer = session and session.genericCurrent
            if transfer and transfer.id == transferID and sequence == transfer.acked + 1
                and sequence == transfer.pendingSequence then
                transfer.acked = sequence
                transfer.pendingSequence = nil
                transfer.lastSendAt = nil
                if transfer.acked >= transfer.total then
                    if transfer.ticker then
                        transfer.ticker:Cancel()
                        transfer.ticker = nil
                    end
                    session.genericCurrent = nil
                    session.state = session.remoteManifest and "ready" or "waiting_manifest"
                    if not session.genericQueue or #session.genericQueue == 0 then
                        if transfer.kind == "V" and not session.remoteManifest then
                            session.status = "Raid summaries sent. Waiting for comparison data..."
                        elseif transfer.kind == "X" then
                            session.status = "Selection delivered. Waiting for raid data..."
                        elseif transfer.kind == "P" then
                            session.status = "Selected raid data delivered. Waiting for import confirmation..."
                        end
                    end
                    self:StartNextGenericTransfer(session)
                end
                self:RefreshUI()
            end
            return
        end

        local sequence = tonumber(parts[4]) or 0

        if direction == "D" then
            local outbound = self.outbound
            if outbound and outbound.reliable and outbound.state == "sending" and outbound.token == token
                and samePlayer(outbound.target, sender) and sequence == outbound.sent + 1
                and sequence == outbound.pendingSequence then
                outbound.sent = sequence
                outbound.pendingSequence = nil
                outbound.lastSendAt = nil
                if outbound.sent >= outbound.total then
                    outbound.state = "sent"
                    outbound.status = "Delivered. Waiting for " .. outbound.target .. " to import..."
                    if outbound.twoWay then
                        self:CancelTicker(outbound)
                    end
                end
                self:RefreshUI()
            end
            return
        end

        if direction == "M" then
            local inbound = self.inbound
            if inbound and inbound.reliable and inbound.state == "returning" and inbound.token == token
                and samePlayer(inbound.sender, sender) and sequence == inbound.sent + 1
                and sequence == inbound.pendingSequence then
                inbound.sent = sequence
                inbound.pendingSequence = nil
                inbound.lastSendAt = nil
                if inbound.sent >= inbound.total then
                    inbound.state = "return_sent"
                    inbound.status = "Merged data delivered. Waiting for "
                        .. tostring(inbound.sender or "sync partner") .. " to import..."
                end
                self:RefreshUI()
            end
            return
        end

        if direction == "C" then
            local inbound = self.inbound
            if inbound and not inbound.twoWay and inbound.token == token and inbound.imported
                and samePlayer(inbound.sender, sender) then
                self:SendCompletion(sender, inbound, inbound.imported)
                return
            end

            local outbound = self.outbound
            if outbound and outbound.twoWay and outbound.token == token and outbound.returnImported
                and samePlayer(outbound.target, sender) then
                self:SendCompletion(sender, outbound, outbound.returnImported)
            end
            return
        end
    end

    if kind == "C" then
        local inbound = self.inbound
        if inbound and inbound.token == parts[2] and samePlayer(inbound.sender, sender) and inbound.twoWay then
            local ackCounts = {
                raids = tonumber(parts[4]) or 0,
                loot = tonumber(parts[5]) or 0,
                trades = tonumber(parts[6]) or 0,
                config = parseBool(parts[8]),
                exclusions = tonumber(parts[10]) or 0,
            }
            inbound.returnImported = ackCounts
            inbound.state = "complete"
            self:CancelTicker(inbound)
            inbound.status = "Two-way sync complete with " .. tostring(sender or inbound.sender) .. "."
            LV:Print("Two-way sync complete for " .. tostring(inbound.guildName or "Guild") .. ".")
            self:RefreshUI()
            return
        end

        local outbound = self.outbound
        if outbound and outbound.token == parts[2] and samePlayer(outbound.target, sender) then
            outbound.state = "complete"
            self:CancelTicker(outbound)
            local ackCounts = {
                raids = tonumber(parts[4]) or 0,
                loot = tonumber(parts[5]) or 0,
                trades = tonumber(parts[6]) or 0,
                config = parseBool(parts[8]),
                exclusions = tonumber(parts[10]) or 0,
            }
            local ackGuildName = parts[9] ~= "" and parts[9] or outbound.guildName
            outbound.status = tostring(sender or outbound.target) .. " imported " .. self:FormatCounts(ackCounts) .. "."
            LV:Print(self:TransferSummary(ackGuildName, ackCounts))
            self:RefreshUI()
        end
    end
end

function LV.DataSync:ProgressForSession(session)
    if not session then
        return 0, 1, "Ready to sync."
    end

    if session.genericCurrent then
        return session.genericCurrent.acked or 0, session.genericCurrent.total or 1,
            session.status or "Sending selective sync data..."
    end
    if session.genericReceiving then
        return session.genericReceiving.received or 0, session.genericReceiving.total or 1,
            session.status or "Receiving selective sync data..."
    end

    if session.state == "waiting" then
        return 0, 1, session.status or "Waiting..."
    end

    local current = session.received or session.sent or 0
    local total = session.total or 1
    if total <= 0 then
        total = 1
    end
    if session.state == "complete" then
        current = total
    end
    return current, total, session.status or ""
end

function LV.DataSync:Progress()
    local inbound = self.inbound
    local outbound = self.outbound
    local active = (inbound and inbound.state ~= "complete" and inbound)
        or (outbound and outbound.state ~= "complete" and outbound)
        or outbound
        or inbound
    return self:ProgressForSession(active)
end

local function repairCurrentGuildOrphans()
    local guildKey = LV.Guild and LV.Guild:CurrentKey()
    if guildKey then
        LV.DataSync:RepairOrphanedRaidEvents(guildKey, false)
    end
end

LV:RegisterEvent("PLAYER_LOGIN", function()
    local normalized = LV.DataSync:NormalizeLegacyRaidIDs()
    if normalized.raids > 0 or normalized.merged > 0 or normalized.links > 0 then
        LV:Print("Normalized " .. tostring(normalized.raids) .. " legacy raid ID(s), merged "
            .. tostring(normalized.merged) .. " duplicate raid record(s), and relinked "
            .. tostring(normalized.links) .. " loot/trade event(s).")
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(1, repairCurrentGuildOrphans)
    else
        repairCurrentGuildOrphans()
    end
end)

LV:RegisterEvent("PLAYER_GUILD_UPDATE", repairCurrentGuildOrphans)

StaticPopupDialogs[LV.Constants.SYNC_INVITE_PROMPT] = {
    text = "%s wants to compare LootViewer raid data for %s.\nExchange a small raid list, then choose which missing raids to import? Raid details are sent only after selection.",
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
