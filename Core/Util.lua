local _, LV = ...

LV.Util = {}
LV.Util.itemWarboundCache = {}

function LV.Util:Trim(value)
    value = tostring(value or "")
    value = value:gsub("^%s+", "")
    value = value:gsub("%s+$", "")
    return value
end

function LV.Util:IsBlank(value)
    return self:Trim(value) == ""
end

function LV.Util:CopyDefaults(target, defaults)
    if type(target) ~= "table" then
        target = {}
    end

    for key, value in pairs(defaults or {}) do
        if type(value) == "table" then
            target[key] = self:CopyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end

    return target
end

function LV.Util:NormalizeSlug(value)
    value = self:Trim(value):lower()
    value = value:gsub("%s+", "-")
    value = value:gsub("[^%w%-]", "")
    value = value:gsub("%-+", "-")
    value = value:gsub("^%-", ""):gsub("%-$", "")
    return value
end

function LV.Util:RegionSlug()
    local region = 0
    if type(GetCurrentRegion) == "function" then
        region = tonumber(GetCurrentRegion()) or 0
    end

    if region == 1 then
        return "us"
    elseif region == 2 then
        return "kr"
    elseif region == 3 then
        return "eu"
    elseif region == 4 then
        return "tw"
    elseif region == 5 then
        return "cn"
    end

    return "unknown"
end

function LV.Util:RealmName()
    local realm = nil
    if type(GetNormalizedRealmName) == "function" then
        realm = GetNormalizedRealmName()
    end
    if not realm or realm == "" then
        realm = GetRealmName()
    end
    return self:Trim(realm)
end

function LV.Util:UnitFullName(unit)
    local name, realm = UnitFullName(unit or "player")
    name = self:Trim(name)
    realm = self:Trim(realm)
    if name == "" then
        return ""
    end
    if realm == "" then
        realm = self:RealmName()
    end
    return name .. "-" .. realm
end

function LV.Util:PlayerFullName()
    return self:UnitFullName("player")
end

function LV.Util:ShortName(fullName)
    fullName = self:Trim(fullName)
    return (fullName:match("^([^%-]+)") or fullName)
end

function LV.Util:Now()
    return time()
end

function LV.Util:ServerNow()
    if type(GetServerTime) == "function" then
        local ok, value = pcall(GetServerTime)
        value = ok and tonumber(value) or nil
        if value and value > 0 then
            return value
        end
    end

    return self:Now()
end

local TIME_ZONES = {
    realm = { label = "Realm / Server" },
    eastern = { label = "Eastern (ET)", standardOffset = -5 * 60, dst = true },
    central = { label = "Central (CT)", standardOffset = -6 * 60, dst = true },
    mountain = { label = "Mountain (MT)", standardOffset = -7 * 60, dst = true },
    pacific = { label = "Pacific (PT)", standardOffset = -8 * 60, dst = true },
    utc = { label = "UTC", standardOffset = 0 },
}

local TIME_ZONE_VALUES = {
    { value = "realm", label = TIME_ZONES.realm.label },
    { value = "eastern", label = TIME_ZONES.eastern.label },
    { value = "central", label = TIME_ZONES.central.label },
    { value = "mountain", label = TIME_ZONES.mountain.label },
    { value = "pacific", label = TIME_ZONES.pacific.label },
    { value = "utc", label = TIME_ZONES.utc.label },
}

local TIME_ZONE_ALIASES = {
    ["local"] = "realm",
    ["server"] = "realm",
    ["realm / server"] = "realm",
    ["et"] = "eastern",
    ["est"] = "eastern",
    ["edt"] = "eastern",
    ["ct"] = "central",
    ["cst"] = "central",
    ["cdt"] = "central",
    ["mt"] = "mountain",
    ["mst"] = "mountain",
    ["mdt"] = "mountain",
    ["pt"] = "pacific",
    ["pst"] = "pacific",
    ["pdt"] = "pacific",
    ["gmt"] = "utc",
}

local function weekday(year, month, day)
    local monthOffsets = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 }
    if month < 3 then
        year = year - 1
    end
    local zeroBased = (year + math.floor(year / 4) - math.floor(year / 100) + math.floor(year / 400) + monthOffsets[month] + day) % 7
    return zeroBased + 1
end

local function firstSunday(year, month)
    return 1 + ((1 - weekday(year, month, 1)) % 7)
end

local function usesUSDST(utc, standardOffset)
    local secondSundayMarch = firstSunday(utc.year, 3) + 7
    local firstSundayNovember = firstSunday(utc.year, 11)
    local startUTCHour = 2 - math.floor(standardOffset / 60)
    local endUTCHour = 1 - math.floor(standardOffset / 60)

    if utc.month < 3 or utc.month > 11 then
        return false
    elseif utc.month > 3 and utc.month < 11 then
        return true
    elseif utc.month == 3 then
        return utc.day > secondSundayMarch or (utc.day == secondSundayMarch and utc.hour >= startUTCHour)
    end

    return utc.day < firstSundayNovember or (utc.day == firstSundayNovember and utc.hour < endUTCHour)
end

function LV.Util:NormalizeTimezone(value)
    value = self:Trim(value):lower()
    value = TIME_ZONE_ALIASES[value] or value
    return TIME_ZONES[value] and value or "realm"
end

function LV.Util:TimezoneValues()
    return TIME_ZONE_VALUES
end

function LV.Util:TimezoneLabel(value)
    local timezone = TIME_ZONES[self:NormalizeTimezone(value)]
    return timezone and timezone.label or TIME_ZONES.realm.label
end

function LV.Util:TimezoneCalendar(value, timestamp)
    local timezoneID = self:NormalizeTimezone(value)
    if timezoneID == "realm" then
        if C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime then
            local ok, current = pcall(C_DateAndTime.GetCurrentCalendarTime)
            if ok and type(current) == "table" and current.weekday then
                return {
                    wday = tonumber(current.weekday) or 1,
                    hour = tonumber(current.hour) or 0,
                    min = tonumber(current.minute) or 0,
                }
            end
        end
        return date("*t", tonumber(timestamp) or self:Now())
    end

    timestamp = tonumber(timestamp) or self:ServerNow()
    local timezone = TIME_ZONES[timezoneID]
    local utc = date("!*t", timestamp)
    local offset = tonumber(timezone.standardOffset) or 0
    if timezone.dst and usesUSDST(utc, offset) then
        offset = offset + 60
    end
    return date("!*t", timestamp + (offset * 60))
end

function LV.Util:TimezoneWeekMinute(value, timestamp)
    local current = self:TimezoneCalendar(value, timestamp)
    return (((tonumber(current.wday) or 1) - 1) * 24 * 60)
        + ((tonumber(current.hour) or 0) * 60)
        + (tonumber(current.min) or 0)
end

function LV.Util:ItemID(itemLink)
    if not itemLink then
        return nil
    end
    local id = tostring(itemLink):match("item:(%d+)")
    return tonumber(id)
end

function LV.Util:ItemKey(itemLink)
    if not itemLink then
        return ""
    end
    local itemString = tostring(itemLink):match("(item:[^|]+)")
    return itemString or tostring(itemLink)
end

function LV.Util:GetItemBindType(itemLink)
    if not itemLink or type(GetItemInfo) ~= "function" then
        return nil
    end

    local result = { pcall(GetItemInfo, itemLink) }
    if result[1] then
        return result[15]
    end

    return nil
end

function LV.Util:IsItemBoE(itemLink)
    local bindType = self:GetItemBindType(itemLink)
    return bindType ~= nil and bindType == LE_ITEM_BIND_ON_EQUIP
end

function LV.Util:IsItemWarbound(itemLink)
    itemLink = tostring(itemLink or "")
    if itemLink == "" then
        return false
    end

    local cacheKey = self:ItemKey(itemLink)
    if self.itemWarboundCache[cacheKey] then
        return true
    end
    if not C_TooltipInfo or type(C_TooltipInfo.GetHyperlink) ~= "function" then
        return false
    end

    local ok, tooltip = pcall(C_TooltipInfo.GetHyperlink, itemLink)
    if not ok or type(tooltip) ~= "table" or type(tooltip.lines) ~= "table" then
        return false
    end

    local function isReadable(value, expectedType)
        if type(value) ~= expectedType then
            return false
        end
        if type(issecretvalue) == "function" and issecretvalue(value) then
            return false
        end
        return true
    end

    local bindingEnum = Enum and Enum.TooltipDataItemBinding
    local accountUntilEquipped = bindingEnum and bindingEnum.AccountUntilEquipped or 9
    local bindToAccountUntilEquipped = bindingEnum and bindingEnum.BindToAccountUntilEquipped or 10
    local bindingText = {}
    local function addBindingText(value)
        if type(value) == "string" and value ~= "" then
            bindingText[value] = true
        end
    end
    addBindingText(ITEM_ACCOUNTBOUND_UNTIL_EQUIP)
    addBindingText(ITEM_BIND_TO_ACCOUNT_UNTIL_EQUIP)

    for _, line in ipairs(tooltip.lines) do
        if type(line) == "table" then
            local bonding = line.bonding
            if (isReadable(bonding, "number")
                    and (bonding == accountUntilEquipped or bonding == bindToAccountUntilEquipped))
                or (isReadable(line.leftText, "string") and bindingText[line.leftText])
                or (isReadable(line.rightText, "string") and bindingText[line.rightText]) then
                self.itemWarboundCache[cacheKey] = true
                return true
            end
        end
    end
    return false
end

local function escapeLuaPattern(value)
    return tostring(value or ""):gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
end

local function lootFormatPattern(formatText, captureFirstString)
    formatText = tostring(formatText or "")
    if formatText == "" then
        return nil
    end

    local pieces = { "^" }
    local cursor = 1
    local stringIndex = 0
    while cursor <= #formatText do
        local startAt, endAt, kind = formatText:find("%%[%d%$]*([sd])", cursor)
        if not startAt then
            pieces[#pieces + 1] = escapeLuaPattern(formatText:sub(cursor))
            break
        end
        pieces[#pieces + 1] = escapeLuaPattern(formatText:sub(cursor, startAt - 1))
        if kind == "s" then
            stringIndex = stringIndex + 1
            pieces[#pieces + 1] = captureFirstString and stringIndex == 1 and "(.+)" or ".-"
        else
            pieces[#pieces + 1] = "%d+"
        end
        cursor = endAt + 1
    end
    pieces[#pieces + 1] = "$"
    return table.concat(pieces)
end

function LV.Util:ExtractBonusLoot(message)
    message = tostring(message or "")
    if message == "" then
        return nil, nil
    end

    local itemLink = message:match("(|c%x+|Hitem:.-|h.-|h|r)")
        or message:match("(|Hitem:.-|h.-|h)")
    if not itemLink then
        return nil, nil
    end

    local selfPattern = lootFormatPattern(LOOT_ITEM_BONUS_ROLL_SELF, false)
    if (selfPattern and message:match(selfPattern)) or message:find("^You receive bonus loot:") then
        return self:PlayerFullName(), itemLink
    end

    local otherPattern = lootFormatPattern(LOOT_ITEM_BONUS_ROLL, true)
    local player = otherPattern and message:match(otherPattern)
        or message:match("^(.+) receives bonus loot:")
    if not player or player == "" then
        return nil, nil
    end
    return player, itemLink
end

function LV.Util:InRaidInstance()
    local inInstance, instanceType = IsInInstance()
    return inInstance and instanceType == "raid"
end

function LV.Util:CurrentInstance()
    local name, instanceType, difficultyID, difficultyName, _, _, _, instanceID = GetInstanceInfo()
    return {
        name = self:Trim(name),
        instanceType = instanceType,
        difficultyID = tonumber(difficultyID) or 0,
        difficultyName = self:Trim(difficultyName),
        instanceID = tonumber(instanceID) or 0,
    }
end

function LV.Util:PackedList(list)
    local out = {}
    for _, value in ipairs(list or {}) do
        if value ~= nil then
            out[#out + 1] = value
        end
    end
    return out
end
