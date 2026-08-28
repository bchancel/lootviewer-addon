local _, LV = ...

LV.Guild = {}
LV.modules.Guild = LV.Guild

local AUTHORITY_LABELS = {
    assist = "Lead / Assist",
    lead = "Raid Lead",
    trusted = "Trusted Rank",
    all = "Anyone",
}

function LV.Guild:RankMaximum()
    if type(GuildControlGetNumRanks) == "function" then
        local ok, count = pcall(GuildControlGetNumRanks)
        count = ok and tonumber(count) or nil
        if count and count > 1 then
            return count - 1
        end
    end
    return 9
end

function LV.Guild:ParseAuthorityDirective(text)
    text = tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    local matches = {}
    local directiveLines = 0
    local maximumRank = self:RankMaximum()

    for line in (text .. "\n"):gmatch("(.-)\n") do
        line = LV.Util:Trim(line)
        local lowered = line:lower()
        if lowered:match("^lootviewer%s+authority") then
            directiveLines = directiveLines + 1
            local value = lowered:match("^lootviewer%s+authority%s*:%s*(.-)%s*$")
            if value then
                value = LV.Util:Trim(value):gsub("%s+", " "):gsub("%s*/%s*", "/")
                local mode
                local rankMin
                local rankMax
                if value == "lead/assist" then
                    mode = "assist"
                elseif value == "raid lead" then
                    mode = "lead"
                elseif value == "anyone" then
                    mode = "all"
                else
                    local low, high = value:match("^trusted%s+(%d+)%s*%-%s*(%d+)$")
                    low = tonumber(low)
                    high = tonumber(high)
                    if low and high and low <= high and low >= 0 and high <= maximumRank then
                        mode = "trusted"
                        rankMin = low
                        rankMax = high
                    end
                end

                if mode then
                    matches[#matches + 1] = {
                        mode = mode,
                        label = AUTHORITY_LABELS[mode],
                        rankMin = rankMin,
                        rankMax = rankMax,
                        line = line,
                        source = "guildInfo",
                    }
                end
            end
        end
    end

    if directiveLines == 0 then
        return nil, "missing"
    end
    if directiveLines > 1 then
        return nil, "multiple"
    end
    if #matches ~= 1 then
        return nil, "invalid"
    end
    return matches[1], "valid"
end

function LV.Guild:GuildInformationText()
    if not (C_Club and C_Club.GetGuildClubId and C_Club.GetClubInfo) then
        return ""
    end
    local clubID = C_Club.GetGuildClubId()
    if not clubID then
        return ""
    end
    local clubInfo = C_Club.GetClubInfo(clubID)
    return clubInfo and tostring(clubInfo.description or "") or ""
end

function LV.Guild:GuildAuthorityDirective()
    local actual = self:ActualInfo()
    local current = self:CurrentInfo()
    if not actual or not current or actual.key ~= current.key or current.override then
        return nil, "missing"
    end
    local cached = self.authorityDirectiveCache
    if not cached or cached.guildKey ~= actual.key then
        return nil, "missing"
    end
    return cached.directive, cached.status
end

function LV.Guild:ScanAuthorityDirective()
    if InCombatLockdown and InCombatLockdown() then
        return self:GuildAuthorityDirective()
    end

    local actual = self:ActualInfo()
    local current = self:CurrentInfo()
    if not actual or not current or actual.key ~= current.key or current.override then
        return nil, "missing"
    end

    local text = self:GuildInformationText()
    local directive, status = self:ParseAuthorityDirective(text)
    self.authorityDirectiveCache = {
        guildKey = actual.key,
        directive = directive,
        status = status,
        text = text,
    }
    return directive, status
end

function LV.Guild:EffectiveAuthority()
    local cfg = self:CurrentConfig()
    if not cfg then
        return nil, "missing"
    end

    local directive, status = self:GuildAuthorityDirective()
    if directive then
        return directive, status
    end

    local mode = cfg.authority or "assist"
    return {
        mode = mode,
        label = AUTHORITY_LABELS[mode] or AUTHORITY_LABELS.assist,
        rankMin = tonumber(cfg.rankMin) or 0,
        rankMax = tonumber(cfg.rankMax) or 3,
        source = "local",
    }, status
end

function LV.Guild:ActualInfo()
    local guildName, rankName, rankIndex, guildRealm = GetGuildInfo("player")
    guildName = LV.Util:Trim(guildName)
    if guildName == "" then
        return nil
    end

    guildRealm = LV.Util:Trim(guildRealm)
    if guildRealm == "" then
        guildRealm = LV.Util:RealmName()
    end

    return {
        name = guildName,
        realm = guildRealm,
        rankName = LV.Util:Trim(rankName),
        rankIndex = tonumber(rankIndex) or 99,
        key = self:BuildKey(guildName, guildRealm),
    }
end

function LV.Guild:CurrentInfo()
    return self.sessionOverride or self:ActualInfo()
end

function LV.Guild:ClearSessionOverride(silent)
    local previous = self.sessionOverride
    self.sessionOverride = nil
    if not silent then
        if previous then
            LV:Print("Cleared the guild session override.")
        else
            LV:Print("No guild session override is active.")
        end
    end
    if LV.UI and LV.UI.Refresh then
        LV.UI:Refresh()
    end
    return previous ~= nil
end

function LV.Guild:SetSessionOverride(selector)
    selector = LV.Util:Trim(selector)
    local lowered = selector:lower()
    if selector == "" or lowered == "clear" or lowered == "off" or lowered == "none" then
        return self:ClearSessionOverride(false)
    end

    LV.Store:InitializeIfNeeded()
    local guilds = LV.Store.db and LV.Store.db.g or {}
    local normalized = LV.Util:NormalizeSlug(selector)
    local matches = {}

    for key, record in pairs(guilds or {}) do
        if type(record) == "table" then
            local regionSlug, realmSlug, guildSlug = tostring(key):match("^([^:]+):([^:]+):(.+)$")
            local exactKey = tostring(key):lower() == lowered
            local guildMatch = guildSlug and guildSlug == normalized
            local realmGuildMatch = realmSlug and guildSlug
                and (realmSlug .. ":" .. guildSlug) == lowered
            if exactKey or guildMatch or realmGuildMatch then
                matches[#matches + 1] = {
                    key = key,
                    region = regionSlug,
                    realm = realmSlug,
                    guild = guildSlug,
                    exact = exactKey,
                }
            end
        end
    end

    if #matches == 0 then
        LV:Print("No stored guild matches '" .. selector .. "'. Sync or visit that guild before using the override.")
        return false
    elseif #matches > 1 then
        local keys = {}
        for _, match in ipairs(matches) do
            keys[#keys + 1] = match.key
        end
        table.sort(keys)
        LV:Print("That guild name is ambiguous. Use its full key: " .. table.concat(keys, ", "))
        return false
    end

    local match = matches[1]
    local displayName = match.exact and tostring(match.guild or selector):gsub("%-", " ") or selector
    self.sessionOverride = {
        name = displayName,
        realm = tostring(match.realm or LV.Util:RealmName()),
        rankName = "Session Override",
        rankIndex = 99,
        key = match.key,
        override = true,
        selector = selector,
    }
    LV.Store:GuildRecord(match.key)
    LV:Print("Guild session override set to " .. displayName .. " (" .. match.key .. ").")
    if LV.UI and LV.UI.Refresh then
        LV.UI:Refresh()
    end
    return true
end

function LV.Guild:BuildKey(guildName, realmName)
    return table.concat({
        LV.Util:RegionSlug(),
        LV.Util:NormalizeSlug(realmName or LV.Util:RealmName()),
        LV.Util:NormalizeSlug(guildName),
    }, ":")
end

function LV.Guild:CurrentKey()
    local info = self:CurrentInfo()
    return info and info.key or nil
end

function LV.Guild:CurrentRecord()
    local key = self:CurrentKey()
    if not key then
        return nil
    end
    return LV.Store:GuildRecord(key)
end

function LV.Guild:CurrentConfig()
    local key = self:CurrentKey()
    return key and LV.Store:GetConfig(key) or nil
end

function LV.Guild:RefreshRoster()
    local info = self:CurrentInfo()
    if not info then
        return 0
    end

    if type(GuildRoster) == "function" then
        GuildRoster()
    end

    local count = 0
    local now = LV.Util:Now()
    local record = LV.Store:GuildRecord(info.key)
    if record then
        record.rosterScan = now
    end
    local total = GetNumGuildMembers and GetNumGuildMembers() or 0
    for index = 1, total do
        local name, rankName, rankIndex, level, classDisplayName, zone, note, officerNote, online, status, classFileName, achievementPoints, achievementRank, isMobile, canSoR, repStanding, guid = GetGuildRosterInfo(index)
        name = LV.Util:Trim(name)
        if name ~= "" then
            if not name:find("-", 1, true) then
                name = name .. "-" .. info.realm
            end

            local offlineDays = 0
            if not online and type(GetGuildRosterLastOnline) == "function" then
                local years, months, days, hours = GetGuildRosterLastOnline(index)
                if years or months or days or hours then
                    offlineDays = (tonumber(years) or 0) * 365 + (tonumber(months) or 0) * 30 + (tonumber(days) or 0)
                    if offlineDays == 0 and (tonumber(hours) or 0) > 0 then
                        offlineDays = 1
                    end
                end
            end

            LV.Store:AddRosterMember(info.key, name, {
                r = tonumber(rankIndex) or 99,
                rn = LV.Util:Trim(rankName),
                c = LV.Util:Trim(classFileName or classDisplayName),
                z = LV.Util:Trim(zone),
                n = LV.Util:Trim(note),
                on = LV.Util:Trim(officerNote),
                onl = online and 1 or 0,
                lo = offlineDays,
                guid = LV.Util:Trim(guid),
                ap = tonumber(achievementPoints) or nil,
            })
            count = count + 1
        end
    end

    return count
end

function LV.Guild:RememberMember(fullName, fields)
    local info = self:CurrentInfo()
    if not info then
        return nil
    end

    fullName = LV.Util:Trim(fullName)
    if fullName == "" then
        return nil
    end

    if not fullName:find("-", 1, true) then
        fullName = fullName .. "-" .. info.realm
    end

    fields = fields or {}
    fields.ov = fields.ov or 1
    return LV.Store:AddRosterMember(info.key, fullName, fields)
end

function LV.Guild:IsGuildMember(fullName)
    local info = self:CurrentInfo()
    if not info then
        return false
    end

    local record = LV.Store:GuildRecord(info.key)
    local nameID = LV.Store:NameID(info.key, fullName)
    return record and nameID and record.gr[nameID] ~= nil
end

function LV.Guild:RankAllowed(rankIndex)
    local authority = self:EffectiveAuthority()
    rankIndex = tonumber(rankIndex)
    if not authority or not rankIndex then
        return false
    end

    local minRank = tonumber(authority.rankMin) or 0
    local maxRank = tonumber(authority.rankMax) or 3
    return rankIndex >= minRank and rankIndex <= maxRank
end

function LV.Guild:CanModifySession()
    local authority = self:EffectiveAuthority()
    if not authority then
        return false
    end

    local mode = authority.mode or "assist"
    if mode == "all" then
        return true
    end

    if mode == "lead" then
        return UnitIsGroupLeader("player")
    end

    if mode == "assist" then
        return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
    end

    if mode == "rank" or mode == "trusted" then
        local info = self:CurrentInfo()
        return info and self:RankAllowed(info.rankIndex) or false
    end

    return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

function LV.Guild:LoadedGuildRosterMember(fullName)
    local actual = self:ActualInfo()
    if not actual or type(GetNumGuildMembers) ~= "function" or type(GetGuildRosterInfo) ~= "function" then
        return nil
    end
    fullName = LV.Util:Trim(fullName):lower()
    for index = 1, (tonumber(GetNumGuildMembers()) or 0) do
        local name, rankName, rankIndex, _, classDisplayName, _, _, _, online, _, classFileName =
            GetGuildRosterInfo(index)
        name = LV.Util:Trim(name)
        if name ~= "" and not name:find("-", 1, true) then
            name = name .. "-" .. actual.realm
        end
        if name:lower() == fullName then
            return {
                index = index,
                fullName = name,
                rankName = LV.Util:Trim(rankName),
                rankIndex = tonumber(rankIndex) or 99,
                className = LV.Util:Trim(classFileName or classDisplayName),
                online = online and 1 or 0,
            }
        end
    end
    return nil
end

function LV.Guild:RosterMemberRank(guildKey, fullName)
    local actual = self:ActualInfo()
    if actual and actual.key == guildKey
        and LV.Util:Trim(fullName):lower() == LV.Util:PlayerFullName():lower() then
        return actual.rankIndex
    end
    local member = self:LoadedGuildRosterMember(fullName)
    if member then
        return member.rankIndex
    end
    local record = LV.Store:GuildRecord(guildKey)
    local wanted = LV.Util:Trim(fullName):lower()
    for nameID, entry in pairs((record and record.gr) or {}) do
        local name = LV.Store:DictionaryValue(guildKey, "n", nameID)
        if name:lower() == wanted and type(entry) == "table" then
            return tonumber(entry.r)
        end
    end
    return nil
end

function LV.Guild:CanAcceptRosterPublisher(guildKey, fullName)
    local actual = self:ActualInfo()
    if not actual or actual.key ~= guildKey then
        return false
    end
    local rankIndex = self:RosterMemberRank(guildKey, fullName)
    if rankIndex == nil then
        return false
    end
    local authority = self:EffectiveAuthority()
    local mode = authority and authority.mode or "assist"
    if mode == "all" then
        return true
    elseif mode == "trusted" or mode == "rank" then
        return self:RankAllowed(rankIndex)
    end

    local wanted = LV.Util:Trim(fullName):lower()
    local function unitAllowed(unit)
        if type(UnitExists) ~= "function" or not UnitExists(unit)
            or LV.Util:UnitFullName(unit):lower() ~= wanted then
            return nil
        end
        if mode == "lead" then
            return UnitIsGroupLeader(unit) and true or false
        end
        return (UnitIsGroupLeader(unit) or UnitIsGroupAssistant(unit)) and true or false
    end
    local allowed = unitAllowed("player")
    if allowed ~= nil then
        return allowed
    end
    if type(IsInRaid) == "function" and IsInRaid() then
        for index = 1, (tonumber(GetNumGroupMembers()) or 0) do
            allowed = unitAllowed("raid" .. index)
            if allowed ~= nil then
                return allowed
            end
        end
    elseif type(IsInGroup) == "function" and IsInGroup() then
        for index = 1, (tonumber(GetNumSubgroupMembers()) or 0) do
            allowed = unitAllowed("party" .. index)
            if allowed ~= nil then
                return allowed
            end
        end
    end

    -- Guild recipients outside the publisher's group cannot inspect group
    -- leadership, so use the configured trusted rank range as the fallback.
    return self:RankAllowed(rankIndex)
end

function LV.Guild:CanPublishRoster()
    local info = self:ActualInfo()
    return info and self:CanModifySession() and self:CanAcceptRosterPublisher(info.key, LV.Util:PlayerFullName()) or false
end

function LV.Guild:InferRosterTag(guildKey, nameID)
    local record = LV.Store:GuildRecord(guildKey)
    if not record then
        return "pug", nil
    end

    local override = record.o[nameID]
    if type(override) == "table" and override.tag then
        return override.tag, override.main
    end

    local rosterEntry = record.gr[nameID]
    if type(rosterEntry) ~= "table" then
        return "pug", nil
    end

    local note = LV.Util:Trim(rosterEntry.n)
    local officerNote = LV.Util:Trim(rosterEntry.on)
    local inferredMain = self:InferMainFromNote(guildKey, officerNote ~= "" and officerNote or note)
    if inferredMain then
        return "alt", inferredMain
    end

    return "guild", nil
end

function LV.Guild:InferMainFromNote(guildKey, note)
    note = LV.Util:Trim(note)
    if note == "" or note:find("%s") then
        return nil
    end

    local record = LV.Store:GuildRecord(guildKey)
    if not record then
        return nil
    end

    local wanted = note:lower()
    for id, _ in pairs(record.gr) do
        local name = LV.Store:DictionaryValue(guildKey, "n", id)
        if LV.Util:ShortName(name):lower() == wanted then
            return tonumber(id)
        end
    end

    return nil
end

function LV.Guild:SetRosterOverride(guildKey, fullName, tag, mainName)
    local record = LV.Store:GuildRecord(guildKey)
    if not record then
        return
    end

    local nameID = LV.Store:NameID(guildKey, fullName)
    if not nameID then
        return
    end

    local mainID = nil
    if tag == "alt" and mainName and mainName ~= "" then
        if not mainName:find("-", 1, true) then
            local info = self:CurrentInfo()
            mainName = mainName .. "-" .. ((info and info.realm) or LV.Util:RealmName())
        end
        mainID = LV.Store:NameID(guildKey, mainName)
    end

    record.o[nameID] = {
        tag = tag or "guild",
        main = mainID,
        ts = LV.Util:Now(),
        by = LV.Store:NameID(guildKey, LV.Util:PlayerFullName()),
    }
    if LV.Raid and LV.Raid.ReconcileGuildLinkedAttendance then
        LV.Raid:ReconcileGuildLinkedAttendance(guildKey)
    end
end

LV:RegisterEvent("PLAYER_LOGIN", function()
    -- Guild roster loading is left to Blizzard's guild UI. LootViewer only
    -- records raid members, whispers, and explicit overlay/manual actions.
end)

LV:RegisterEvent("GUILD_ROSTER_UPDATE", function()
    -- Roster scans are intentionally user-triggered from the UI. The client can
    -- fire this event repeatedly while loading guild data, and rebuilding rows
    -- here makes the config frame feel sluggish.
end)

LV:RegisterEvent("PLAYER_GUILD_UPDATE", function()
    LV.Guild.authorityDirectiveCache = nil
end)
