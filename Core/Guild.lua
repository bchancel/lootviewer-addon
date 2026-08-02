local _, LV = ...

LV.Guild = {}
LV.modules.Guild = LV.Guild

function LV.Guild:CurrentInfo()
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
    local cfg = self:CurrentConfig()
    rankIndex = tonumber(rankIndex)
    if not cfg or not rankIndex then
        return false
    end

    local minRank = tonumber(cfg.rankMin) or 0
    local maxRank = tonumber(cfg.rankMax) or 3
    return rankIndex >= minRank and rankIndex <= maxRank
end

function LV.Guild:CanModifySession()
    local cfg = self:CurrentConfig()
    if not cfg then
        return false
    end

    local mode = cfg.authority or "assist"
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
