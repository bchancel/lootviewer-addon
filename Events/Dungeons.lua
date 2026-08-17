local _, LV = ...

LV.Dungeons = {}
LV.modules.Dungeons = LV.Dungeons

local COMPLETION_CAPTURE_SECONDS = 30 * 60
local TRADE_WINDOW_SECONDS = 2 * 60 * 60

local function normalizeName(name)
    if LV.Loot and LV.Loot.NormalizePlayerName then
        return LV.Loot:NormalizePlayerName(name)
    end
    name = LV.Util:Trim(name)
    if name == "" then
        return ""
    end
    if not name:find("-", 1, true) then
        name = name .. "-" .. LV.Util:RealmName()
    end
    return name
end

local function currentLootSpecID()
    local specID = type(GetLootSpecialization) == "function" and tonumber(GetLootSpecialization()) or 0
    if specID and specID > 0 then
        return specID
    end
    if type(GetSpecialization) == "function" and type(GetSpecializationInfo) == "function" then
        local index = GetSpecialization()
        if index then
            local ok, activeSpecID = pcall(GetSpecializationInfo, index)
            if ok then
                return tonumber(activeSpecID) or 0
            end
        end
    end
    return 0
end

local function itemInfoInstant(itemLink)
    local getter = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if type(getter) ~= "function" then
        return nil
    end
    local result = { pcall(getter, itemLink) }
    if not result[1] then
        return nil
    end
    return {
        itemID = tonumber(result[2]) or LV.Util:ItemID(itemLink) or 0,
        equipLoc = tostring(result[5] or ""),
        classID = tonumber(result[7]),
    }
end

local function isGear(itemLink)
    local info = itemInfoInstant(itemLink)
    if not info then
        return false
    end
    local weaponClass = Enum and Enum.ItemClass and Enum.ItemClass.Weapon or 2
    local armorClass = Enum and Enum.ItemClass and Enum.ItemClass.Armor or 4
    return info.equipLoc ~= ""
        and info.equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE"
        and (info.classID == weaponClass or info.classID == armorClass)
end

local function rosterSnapshot(members)
    local names = {}
    local seen = {}
    local function add(name)
        name = normalizeName(name)
        local key = name:lower()
        if name ~= "" and not seen[key] then
            seen[key] = true
            names[#names + 1] = name
        end
    end

    for _, member in ipairs(members or {}) do
        if type(member) == "table" then
            add(member.name)
        else
            add(member)
        end
    end
    add(LV.Util:PlayerFullName())
    for index = 1, 4 do
        add(LV.Util:UnitFullName("party" .. tostring(index)))
    end
    table.sort(names)
    return names
end

local function parseChatLoot(message)
    message = tostring(message or "")
    local itemLink = message:match("(|c%x+|Hitem:.-|h%[.-%]|h|r)")
    if not itemLink then
        return nil, nil
    end

    local player = message:match("^(.+) receives loot:")
        or message:match("^(.+) receives item:")
    if not player and message:find("You receive", 1, true) then
        player = LV.Util:PlayerFullName()
    end
    return player and normalizeName(player) or nil, itemLink
end

function LV.Dungeons:IsEnabled()
    local cfg = LV.Store:AccountConfig()
    return cfg and cfg.dungeonLogging == true
end

function LV.Dungeons:RunByID(runID)
    if not runID then
        return nil
    end
    for _, run in ipairs(self:Record().r or {}) do
        if type(run) == "table" and run.id == runID then
            return run
        end
    end
    return nil
end

function LV.Dungeons:Record()
    return LV.Store:DungeonRecord()
end

function LV.Dungeons:ContextSeasonID(context)
    if context and LV.Seasons:IsSeasonID(context.seasonID) then
        return context.seasonID
    end
    local instance = LV.Util:CurrentInstance()
    return LV.Seasons:DungeonSeasonID(instance.name, LV.Util:Now())
end

function LV.Dungeons:MapName(mapID)
    if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo and tonumber(mapID) then
        local result = { pcall(C_ChallengeMode.GetMapUIInfo, tonumber(mapID)) }
        if result[1] and LV.Util:Trim(result[2]) ~= "" then
            return LV.Util:Trim(result[2])
        end
    end
    return LV.Util:CurrentInstance().name
end

function LV.Dungeons:CreateRuntime(kind, fields)
    fields = fields or {}
    local instance = LV.Util:CurrentInstance()
    local name = LV.Util:Trim(fields.name or instance.name)
    return {
        kind = kind,
        mapID = tonumber(fields.mapID) or 0,
        instanceID = tonumber(fields.instanceID) or instance.instanceID,
        difficultyID = tonumber(fields.difficultyID) or instance.difficultyID,
        name = name,
        level = tonumber(fields.level) or 0,
        seasonID = fields.seasonID or LV.Seasons:DungeonSeasonID(name, LV.Util:Now()),
        startedAt = tonumber(fields.startedAt) or LV.Util:Now(),
        members = rosterSnapshot(fields.members),
    }
end

function LV.Dungeons:StartKeystone(mapID)
    if not self:IsEnabled() then
        return
    end
    local level = 0
    if C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo then
        local result = { pcall(C_ChallengeMode.GetActiveKeystoneInfo) }
        if result[1] then
            level = tonumber(result[2]) or 0
        end
    end
    local name = self:MapName(mapID)
    if not LV.Seasons:IsKnownDungeon(name) then
        self.current = nil
        return
    end
    self.current = self:CreateRuntime("keystone", {
        mapID = mapID,
        name = name,
        level = level,
    })
end

function LV.Dungeons:MaybeStartMythicZero()
    if not self:IsEnabled() then
        self.current = nil
        return
    end
    local instance = LV.Util:CurrentInstance()
    if self.current and self.current.kind == "keystone" then
        if instance.instanceType == "party" and self.current.instanceID == instance.instanceID then
            return
        end
        self:FinishCurrent()
    end

    if instance.instanceType == "party"
        and instance.difficultyID == 23
        and LV.Seasons:IsKnownDungeon(instance.name) then
        if not self.current
            or self.current.kind ~= "mythic0"
            or self.current.instanceID ~= instance.instanceID then
            self.current = self:CreateRuntime("mythic0", {
                name = instance.name,
                instanceID = instance.instanceID,
                difficultyID = instance.difficultyID,
                level = 0,
            })
        end
    elseif self.current and self.current.kind == "mythic0" then
        self:FinishCurrent()
    end
end

function LV.Dungeons:EnsureRun(context, completionInfo)
    context = context or self.current
    if not context then
        return nil
    end
    if context.runID then
        return self:RunByID(context.runID)
    end

    completionInfo = type(completionInfo) == "table" and completionInfo or {}
    local record = self:Record()
    local members = rosterSnapshot(completionInfo.members or context.members)
    local memberIDs = {}
    for _, name in ipairs(members) do
        memberIDs[#memberIDs + 1] = LV.Store:DungeonNameID(name)
    end

    local run = {
        id = LV.Store:NewID(record, "run", "m"),
        sea = self:ContextSeasonID(context),
        cm = tonumber(completionInfo.mapChallengeModeID) or context.mapID or 0,
        iid = context.instanceID or 0,
        z = LV.Store:DungeonStringID(context.name or self:MapName(context.mapID)),
        did = context.difficultyID or 0,
        lvl = tonumber(completionInfo.level) or context.level or 0,
        st = context.startedAt or LV.Util:Now(),
        en = context.completedAt,
        dur = tonumber(completionInfo.time) or nil,
        timed = completionInfo.onTime and 1 or nil,
        up = tonumber(completionInfo.keystoneUpgradeLevels) or nil,
        practice = completionInfo.practiceRun and 1 or nil,
        m0 = context.kind == "mythic0" and 1 or nil,
        p = memberIDs,
    }
    record.r[#record.r + 1] = run
    context.runID = run.id
    return run
end

function LV.Dungeons:CompletionInfo()
    if C_ChallengeMode and C_ChallengeMode.GetChallengeCompletionInfo then
        local result = { pcall(C_ChallengeMode.GetChallengeCompletionInfo) }
        if result[1] and type(result[2]) == "table" then
            return result[2]
        end
    end
    return {}
end

function LV.Dungeons:CompleteKeystone()
    if not self:IsEnabled() then
        return
    end
    local info = self:CompletionInfo()
    if not self.current or self.current.kind ~= "keystone" then
        local mapID = tonumber(info.mapChallengeModeID) or 0
        local name = self:MapName(mapID)
        if not LV.Seasons:IsKnownDungeon(name) then
            return
        end
        self.current = self:CreateRuntime("keystone", {
            mapID = mapID,
            name = name,
            level = tonumber(info.level) or 0,
            members = info.members,
        })
    end

    local context = self.current
    context.completedAt = LV.Util:Now()
    context.captureUntil = context.completedAt + COMPLETION_CAPTURE_SECONDS
    context.level = tonumber(info.level) or context.level or 0
    context.members = rosterSnapshot(info.members or context.members)
    self:EnsureRun(context, info)

    if C_Timer and C_Timer.After then
        local runID = context.runID
        C_Timer.After(COMPLETION_CAPTURE_SECONDS, function()
            if LV.Dungeons.current and LV.Dungeons.current.runID == runID then
                LV.Dungeons:FinishCurrent()
            end
        end)
    end

    if LV.UI and LV.UI.Refresh then
        LV.UI:Refresh()
    end
end

function LV.Dungeons:FinishCurrent()
    local context = self.current
    if not context then
        return
    end
    local run = context.runID and self:RunByID(context.runID)
    if run and not run.en then
        run.en = LV.Util:Now()
    end
    self.current = nil
    self.pendingBonus = nil
end

function LV.Dungeons:LootTrack(context, source)
    if source == "bonus" then
        return "myth"
    end
    local level = tonumber(context and context.level) or 0
    return level <= 5 and "champion" or "hero"
end

function LV.Dungeons:FindDuplicate(runID, playerID, itemID, itemKey, timestamp)
    local rows = self:Record().l
    for index = #rows, 1, -1 do
        local row = rows[index]
        local delta = math.abs((tonumber(timestamp) or 0) - (tonumber(row.ts) or 0))
        if delta > 20 and (tonumber(timestamp) or 0) >= (tonumber(row.ts) or 0) then
            break
        end
        if row.run == runID and row.p == playerID
            and ((itemID > 0 and tonumber(row.itemID) == itemID) or row.item == itemKey) then
            return row
        end
    end
    return nil
end

function LV.Dungeons:AddLoot(fields)
    if not self:IsEnabled() or type(fields) ~= "table" or not isGear(fields.itemLink) then
        return nil
    end
    local context = fields.context or self.current
    if not context then
        return nil
    end
    if context.kind == "keystone" and not context.completedAt then
        return nil
    end

    local run = self:EnsureRun(context)
    if not run then
        return nil
    end
    local player = normalizeName(fields.player)
    if player == "" then
        return nil
    end

    local record = self:Record()
    local playerID = LV.Store:DungeonNameID(player)
    local itemKeyID = LV.Store:DungeonItemID(fields.itemLink)
    local itemID = tonumber(fields.itemID) or LV.Util:ItemID(fields.itemLink) or 0
    local timestamp = tonumber(fields.ts) or LV.Util:Now()
    local duplicate = self:FindDuplicate(run.id, playerID, itemID, itemKeyID, timestamp)
    if duplicate then
        if fields.source == "bonus" then
            duplicate.src = "bonus"
            duplicate.track = "myth"
            duplicate.spec = tonumber(fields.specID) or duplicate.spec
            duplicate.bonus = fields.bonusID or duplicate.bonus
        end
        if fields.boss and fields.boss ~= "" and not duplicate.boss then
            duplicate.boss = LV.Store:DungeonStringID(fields.boss)
        end
        return duplicate
    end

    local row = {
        id = LV.Store:NewID(record, "loot", "ml"),
        run = run.id,
        sea = run.sea,
        ts = timestamp,
        p = playerID,
        item = itemKeyID,
        itemID = itemID,
        q = tonumber(fields.quantity) or 1,
        src = fields.source or (context.kind == "mythic0" and "boss" or "end"),
        track = self:LootTrack(context, fields.source),
        boss = fields.boss and fields.boss ~= "" and LV.Store:DungeonStringID(fields.boss) or nil,
        spec = tonumber(fields.specID) or nil,
        bonus = fields.bonusID,
    }
    record.l[#record.l + 1] = row
    if LV.UI and LV.UI.Refresh then
        LV.UI:Refresh()
    end
    return row
end

function LV.Dungeons:RecordEncounterLoot(encounterID, itemID, itemLink, quantity, recipientName, className)
    if not self:IsEnabled() then
        return
    end
    self:MaybeStartMythicZero()
    local context = self.current
    if not context then
        return
    end
    if context.kind ~= "mythic0" and not context.completedAt then
        return
    end
    self:AddLoot({
        ts = LV.Util:Now(),
        player = recipientName,
        itemID = itemID,
        itemLink = itemLink,
        quantity = quantity,
        boss = context.lastEncounterName or "",
        source = context.kind == "mythic0" and "boss" or "end",
        context = context,
    })
end

function LV.Dungeons:RecordChatLoot(message)
    if not self:IsEnabled() then
        return
    end
    self:MaybeStartMythicZero()
    local context = self.current
    if not context then
        return
    end
    local player, itemLink = parseChatLoot(message)
    if not player or not itemLink or not isGear(itemLink) then
        return
    end
    local fields = {
        ts = LV.Util:Now(),
        player = player,
        itemLink = itemLink,
        boss = context.lastEncounterName or "",
        source = context.kind == "mythic0" and "boss" or "end",
        context = context,
    }
    if context.kind ~= "keystone" or context.completedAt then
        self:AddLoot(fields)
    end
end

function LV.Dungeons:BeginBonusRoll()
    local context = self.current
    if not self:IsEnabled() or not context or context.kind ~= "keystone" or not context.completedAt then
        return
    end
    self.pendingBonus = {
        ts = LV.Util:Now(),
        specID = currentLootSpecID(),
        runID = context.runID,
    }
end

function LV.Dungeons:AddBonusRecord(fields)
    local context = self.current
    if not self:IsEnabled() or not context or not context.runID then
        return nil
    end
    local record = self:Record()
    local playerID = LV.Store:DungeonNameID(LV.Util:PlayerFullName())
    local row = {
        id = LV.Store:NewID(record, "bonus", "mb"),
        run = context.runID,
        sea = self:ContextSeasonID(context),
        ts = tonumber(fields.ts) or LV.Util:Now(),
        p = playerID,
        spec = tonumber(fields.specID) or currentLootSpecID(),
        ok = fields.success and 1 or nil,
        item = fields.itemLink and LV.Store:DungeonItemID(fields.itemLink) or nil,
        itemID = fields.itemLink and (LV.Util:ItemID(fields.itemLink) or 0) or 0,
        q = tonumber(fields.quantity) or nil,
        type = fields.typeIdentifier,
        currency = tonumber(fields.currencyID) or nil,
        secondary = fields.isSecondaryResult and 1 or nil,
    }
    record.b[#record.b + 1] = row
    return row
end

function LV.Dungeons:RecordBonusResult(typeIdentifier, itemLink, quantity, specID, sex, personalLootToast, currencyID, isSecondaryResult)
    local context = self.current
    if not context or not context.completedAt then
        return
    end
    local bonus = self:AddBonusRecord({
        ts = LV.Util:Now(),
        success = itemLink ~= nil and itemLink ~= "",
        typeIdentifier = typeIdentifier,
        itemLink = itemLink,
        quantity = quantity,
        specID = specID or (self.pendingBonus and self.pendingBonus.specID),
        currencyID = currencyID,
        isSecondaryResult = isSecondaryResult,
    })
    if bonus and itemLink and isGear(itemLink) then
        self:AddLoot({
            ts = bonus.ts,
            player = LV.Util:PlayerFullName(),
            itemLink = itemLink,
            quantity = quantity,
            source = "bonus",
            specID = bonus.spec,
            bonusID = bonus.id,
            context = context,
        })
    end
    self.pendingBonus = nil
end

function LV.Dungeons:RecordBonusFailure()
    if self.pendingBonus and self.current and self.current.completedAt then
        self:AddBonusRecord({
            ts = LV.Util:Now(),
            success = false,
            specID = self.pendingBonus.specID,
            typeIdentifier = "failed",
        })
    end
    self.pendingBonus = nil
end

function LV.Dungeons:FindTradeSource(fromName, itemLink, timestamp)
    local record = self:Record()
    local fromID = LV.Store:DungeonNameID(normalizeName(fromName))
    local itemID = LV.Util:ItemID(itemLink) or 0
    local itemKey = LV.Store:DungeonItemID(itemLink)
    timestamp = tonumber(timestamp) or LV.Util:Now()

    for index = #record.l, 1, -1 do
        local row = record.l[index]
        if timestamp - (tonumber(row.ts) or 0) > TRADE_WINDOW_SECONDS then
            break
        end
        local ownerID = row.o or row.p
        if ownerID == fromID and ((itemID > 0 and tonumber(row.itemID) == itemID) or row.item == itemKey) then
            return row
        end
    end
    return nil
end

function LV.Dungeons:RecordTrade(fromName, toName, itemLink, source)
    if not self:IsEnabled() then
        return nil
    end
    local timestamp = LV.Util:Now()
    local loot = self:FindTradeSource(fromName, itemLink, timestamp)
    if not loot then
        return nil
    end

    local record = self:Record()
    local fromID = LV.Store:DungeonNameID(normalizeName(fromName))
    local toID = LV.Store:DungeonNameID(normalizeName(toName))
    local trade = {
        id = LV.Store:NewID(record, "trade", "mt"),
        ts = timestamp,
        run = loot.run,
        f = fromID,
        to = toID,
        item = loot.item,
        itemID = loot.itemID,
        loot = loot.id,
        src = source or "observed",
    }
    record.t[#record.t + 1] = trade
    loot.o = toID
    loot.tr = trade.id
    if LV.UI and LV.UI.Refresh then
        LV.UI:Refresh()
    end
    return trade
end

LV:RegisterOptionalEvent("CHALLENGE_MODE_START", function(_, mapID)
    LV.Dungeons:StartKeystone(mapID)
end)

LV:RegisterOptionalEvent("CHALLENGE_MODE_COMPLETED", function()
    LV.Dungeons:CompleteKeystone()
end)

LV:RegisterOptionalEvent("CHALLENGE_MODE_COMPLETED_REWARDS", function()
    if not (LV.Dungeons.current and LV.Dungeons.current.completedAt) then
        LV.Dungeons:CompleteKeystone()
    end
end)

LV:RegisterOptionalEvent("CHALLENGE_MODE_RESET", function()
    LV.Dungeons:FinishCurrent()
end)

LV:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    LV.Dungeons:MaybeStartMythicZero()
end)

LV:RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
    LV.Dungeons:MaybeStartMythicZero()
end)

LV:RegisterEvent("ENCOUNTER_LOOT_RECEIVED", function(_, encounterID, itemID, itemLink, quantity, recipientName, className)
    LV.Dungeons:RecordEncounterLoot(encounterID, itemID, itemLink, quantity, recipientName, className)
end)

LV:RegisterEvent("CHAT_MSG_LOOT", function(_, message)
    LV.Dungeons:RecordChatLoot(message)
end)

LV:RegisterEvent("ENCOUNTER_END", function(_, encounterID, encounterName, difficultyID, groupSize, success)
    if tonumber(success) == 1 and LV.Dungeons.current and LV.Dungeons.current.kind == "mythic0" then
        LV.Dungeons.current.lastEncounterName = LV.Util:Trim(encounterName)
    end
end)

LV:RegisterOptionalEvent("BONUS_ROLL_STARTED", function()
    LV.Dungeons:BeginBonusRoll()
end)

LV:RegisterOptionalEvent("BONUS_ROLL_RESULT", function(_, ...)
    LV.Dungeons:RecordBonusResult(...)
end)

LV:RegisterOptionalEvent("BONUS_ROLL_FAILED", function()
    LV.Dungeons:RecordBonusFailure()
end)

LV:RegisterOptionalEvent("BONUS_ROLL_DEACTIVATE", function()
    LV.Dungeons.pendingBonus = nil
end)
