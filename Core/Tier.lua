local _, LV = ...

LV.Tier = {}

local seasonID = "midnight-2"

local tokenTypes = {
    { id = "curio", label = "Curio", family = "All Armor" },
    { id = "cloth", label = "Cloth", family = "Venomwoven" },
    { id = "leather", label = "Leather", family = "Venomcured" },
    { id = "mail", label = "Mail", family = "Venomcast" },
    { id = "plate", label = "Plate", family = "Venomforged" },
}

-- The Venomous Abyss uses one base item ID per token across raid difficulties.
-- The loot row's difficulty ID identifies Raid Finder, Normal, Heroic, or Mythic.
local tokens = {
    { itemID = 270909, name = "Slumbering Coil Curio", type = "curio", slot = "Any" },

    { itemID = 270914, name = "Venomwoven Effigy", type = "cloth", slot = "Head" },
    { itemID = 270926, name = "Venomwoven Icon", type = "cloth", slot = "Chest" },
    { itemID = 270910, name = "Venomwoven Idol", type = "cloth", slot = "Hands" },
    { itemID = 270918, name = "Venomwoven Relic", type = "cloth", slot = "Legs" },
    { itemID = 270922, name = "Venomwoven Remnant", type = "cloth", slot = "Shoulders" },

    { itemID = 270915, name = "Venomcured Effigy", type = "leather", slot = "Head" },
    { itemID = 270927, name = "Venomcured Icon", type = "leather", slot = "Chest" },
    { itemID = 270911, name = "Venomcured Idol", type = "leather", slot = "Hands" },
    { itemID = 270919, name = "Venomcured Relic", type = "leather", slot = "Legs" },
    { itemID = 270923, name = "Venomcured Remnant", type = "leather", slot = "Shoulders" },

    { itemID = 270916, name = "Venomcast Effigy", type = "mail", slot = "Head" },
    { itemID = 270928, name = "Venomcast Icon", type = "mail", slot = "Chest" },
    { itemID = 270912, name = "Venomcast Idol", type = "mail", slot = "Hands" },
    { itemID = 270920, name = "Venomcast Relic", type = "mail", slot = "Legs" },
    { itemID = 270924, name = "Venomcast Remnant", type = "mail", slot = "Shoulders" },

    { itemID = 270917, name = "Venomforged Effigy", type = "plate", slot = "Head" },
    { itemID = 270929, name = "Venomforged Icon", type = "plate", slot = "Chest" },
    { itemID = 270913, name = "Venomforged Idol", type = "plate", slot = "Hands" },
    { itemID = 270921, name = "Venomforged Relic", type = "plate", slot = "Legs" },
    { itemID = 270925, name = "Venomforged Remnant", type = "plate", slot = "Shoulders" },
}

local seasonCatalogs = {
    [seasonID] = {
        types = tokenTypes,
        tokens = tokens,
    },
}

local typesBySeasonID = {}
local tokensByItemID = {}

for catalogSeasonID, catalog in pairs(seasonCatalogs) do
    typesBySeasonID[catalogSeasonID] = {}
    for _, definition in ipairs(catalog.types or {}) do
        typesBySeasonID[catalogSeasonID][definition.id] = definition
    end
    for _, token in ipairs(catalog.tokens or {}) do
        token.seasonID = catalogSeasonID
        tokensByItemID[token.itemID] = token
    end
end

function LV.Tier:HasDefinitions(selectedSeasonID)
    return seasonCatalogs[selectedSeasonID] ~= nil
end

function LV.Tier:Types(selectedSeasonID)
    local catalog = seasonCatalogs[selectedSeasonID]
    return catalog and catalog.types or {}
end

function LV.Tier:Type(selectedSeasonID, typeID)
    return typesBySeasonID[selectedSeasonID] and typesBySeasonID[selectedSeasonID][typeID]
end

function LV.Tier:TypeValues(selectedSeasonID)
    if not self:HasDefinitions(selectedSeasonID) then
        return {}
    end

    local values = {
        { value = "all", label = "All Tier Types" },
    }
    for _, definition in ipairs(self:Types(selectedSeasonID)) do
        values[#values + 1] = {
            value = definition.id,
            label = definition.label .. " - " .. definition.family,
        }
    end
    return values
end

function LV.Tier:Token(itemID)
    return tokensByItemID[tonumber(itemID) or 0]
end

function LV.Tier:TokenForRow(guildKey, row)
    if type(row) ~= "table" then
        return nil
    end

    local itemID = tonumber(row.itemID)
    if not itemID and guildKey and row.item and LV.Store and LV.Store.DictionaryValue then
        local itemKey = LV.Store:DictionaryValue(guildKey, "i", row.item)
        itemID = LV.Util:ItemID(itemKey)
    end
    return self:Token(itemID)
end
