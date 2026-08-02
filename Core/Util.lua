local _, LV = ...

LV.Util = {}

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
