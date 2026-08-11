local _, LV = ...

LV.Seasons = {}
LV.modules.Seasons = LV.Seasons

local definitions = {
    {
        id = "midnight-1",
        label = "Midnight Season 1",
        shortLabel = "Midnight S1",
        startDate = 20260317,
        raids = {
            { name = "Sporefall", instanceID = 1592 },
            { name = "The Voidspire", instanceID = 2912 },
            { name = "March on Quel'Danas", instanceID = 2913 },
            { name = "The Dreamrift", instanceID = 2939 },
        },
    },
    {
        id = "midnight-2",
        label = "Midnight Season 2",
        shortLabel = "Midnight S2",
        startDate = 20260817,
        raids = {
            { name = "The Tidebound Grotto", instanceID = 2987 },
            { name = "The Venomous Abyss", instanceID = 3004 },
        },
    },
}

local definitionsByID = {}
local seasonsByInstanceID = {}
local seasonsByInstanceName = {}

local function normalizeInstanceName(value)
    value = LV.Util:Trim(value):lower()
    value = value:gsub("\226\128\152", "'")
    value = value:gsub("\226\128\153", "'")
    value = value:gsub("[^%w]", "")
    return value
end

for _, definition in ipairs(definitions) do
    definitionsByID[definition.id] = definition
    for _, raid in ipairs(definition.raids or {}) do
        seasonsByInstanceID[tonumber(raid.instanceID) or 0] = definition.id
        seasonsByInstanceName[normalizeInstanceName(raid.name)] = definition.id
    end
end

local function dateKey(value)
    if type(value) ~= "table" then
        return nil
    end

    local year = tonumber(value.year)
    local month = tonumber(value.month)
    local day = tonumber(value.monthDay or value.day)
    if not year or not month or not day then
        return nil
    end
    return (year * 10000) + (month * 100) + day
end

local function currentDateKey()
    if C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime then
        local ok, current = pcall(C_DateAndTime.GetCurrentCalendarTime)
        local key = ok and dateKey(current) or nil
        if key then
            return key
        end
    end

    return dateKey(date("*t", LV.Util:Now())) or 0
end

local function timestampDateKey(timestamp)
    timestamp = tonumber(timestamp)
    if not timestamp or timestamp <= 0 then
        return nil
    end
    return dateKey(date("*t", timestamp))
end

function LV.Seasons:Definitions()
    return definitions
end

function LV.Seasons:Definition(seasonID)
    return definitionsByID[seasonID]
end

function LV.Seasons:IsSeasonID(seasonID)
    return definitionsByID[seasonID] ~= nil
end

function LV.Seasons:Label(seasonID)
    local definition = self:Definition(seasonID)
    return definition and definition.label or "Unknown Season"
end

function LV.Seasons:SeasonIDForDateKey(key)
    key = tonumber(key) or 0
    local seasonID = nil
    for _, definition in ipairs(definitions) do
        if key >= definition.startDate then
            seasonID = definition.id
        else
            break
        end
    end
    return seasonID
end

function LV.Seasons:CurrentSeasonID()
    return self:SeasonIDForDateKey(currentDateKey()) or definitions[1].id
end

function LV.Seasons:SeasonIDForTimestamp(timestamp)
    local key = timestampDateKey(timestamp)
    return key and self:SeasonIDForDateKey(key) or nil
end

function LV.Seasons:TrackingSeasonID(cfg)
    local configured = cfg and cfg.seasonMode
    if self:IsSeasonID(configured) then
        return configured
    end
    return self:CurrentSeasonID()
end

function LV.Seasons:InstanceSeasonID(instanceID, instanceName)
    local byID = seasonsByInstanceID[tonumber(instanceID) or 0]
    if byID then
        return byID
    end
    return seasonsByInstanceName[normalizeInstanceName(instanceName)]
end

function LV.Seasons:RaidSeasonID(guildKey, raid)
    if type(raid) ~= "table" then
        return nil
    end

    if self:IsSeasonID(raid.sea) then
        return raid.sea
    end

    local instanceName = ""
    if guildKey and raid.z and LV.Store and LV.Store.DictionaryValue then
        instanceName = LV.Store:DictionaryValue(guildKey, "s", raid.z)
    end
    return self:InstanceSeasonID(raid.iid, instanceName)
        or self:SeasonIDForTimestamp(raid.st)
end

function LV.Seasons:EventSeasonID(guildKey, record, row)
    if type(row) ~= "table" then
        return nil
    end

    local raid = row.sid and record and record.r and record.r[row.sid]
    local linkedSeason = self:RaidSeasonID(guildKey, raid)
    if linkedSeason then
        return linkedSeason
    end

    local instanceName = ""
    if guildKey and row.inst and LV.Store and LV.Store.DictionaryValue then
        instanceName = LV.Store:DictionaryValue(guildKey, "s", row.inst)
    end
    return self:InstanceSeasonID(row.iid, instanceName)
        or self:SeasonIDForTimestamp(row.ts)
end

function LV.Seasons:ResolveFilter(filter)
    if filter == "current" then
        return self:CurrentSeasonID()
    end
    return filter
end

function LV.Seasons:RaidMatchesFilter(guildKey, raid, filter)
    filter = self:ResolveFilter(filter or "current")
    if filter == "all" then
        return true
    end
    return self:RaidSeasonID(guildKey, raid) == filter
end

function LV.Seasons:EventMatchesFilter(guildKey, record, row, filter)
    filter = self:ResolveFilter(filter or "current")
    if filter == "all" then
        return true
    end
    return self:EventSeasonID(guildKey, record, row) == filter
end

function LV.Seasons:RaidMatchesRange(guildKey, raid, range)
    if type(range) == "number" then
        return self:RaidSeasonID(guildKey, raid) == self:CurrentSeasonID()
            and (tonumber(raid and raid.st) or 0) >= LV.Util:Now() - (range * 30 * 86400)
    end

    range = range or "months:3"
    local months = tonumber(tostring(range):match("^months:(%d+)$"))
    if months then
        return self:RaidSeasonID(guildKey, raid) == self:CurrentSeasonID()
            and (tonumber(raid and raid.st) or 0) >= LV.Util:Now() - (months * 30 * 86400)
    end

    local seasonID = tostring(range):match("^season:(.+)$")
    if seasonID then
        return self:RaidSeasonID(guildKey, raid) == seasonID
    end

    return range == "all"
end

function LV.Seasons:FilterValues(includeCurrent)
    local values = {}
    if includeCurrent then
        values[#values + 1] = {
            value = "current",
            label = "Current: " .. self:Label(self:CurrentSeasonID()),
        }
    end
    for _, definition in ipairs(definitions) do
        values[#values + 1] = { value = definition.id, label = definition.label }
    end
    values[#values + 1] = { value = "all", label = "All Seasons" }
    return values
end

function LV.Seasons:MeterRangeValues()
    local values = {}
    for month = 1, 6 do
        values[#values + 1] = {
            value = "months:" .. tostring(month),
            label = month == 1 and "Last 1 Month" or ("Last " .. tostring(month) .. " Months"),
        }
    end
    for _, definition in ipairs(definitions) do
        values[#values + 1] = {
            value = "season:" .. definition.id,
            label = definition.label,
        }
    end
    values[#values + 1] = { value = "all", label = "All Seasons" }
    return values
end

function LV.Seasons:TrackingModeValues()
    local current = self:CurrentSeasonID()
    local values = {
        { value = "auto", label = "Automatic: " .. self:Label(current) },
    }
    for _, definition in ipairs(definitions) do
        values[#values + 1] = { value = definition.id, label = definition.label }
    end
    return values
end
