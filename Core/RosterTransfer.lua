local _, LV = ...

LV.RosterTransfer = {}
LV.modules.RosterTransfer = LV.RosterTransfer

local KINDS = { LVO = true, LVH = true, LVA = true, LVC = true, LVK = true, LVD = true }
local TYPES = { raider = true, trial = true, helper = true, social = true }
local ROLES = { [""] = true, tank = true, healer = true, melee = true, ranged = true }
local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local VALUES = {}
for index = 1, #ALPHABET do VALUES[ALPHABET:sub(index, index)] = index - 1 end
local CHUNK_SIZE, MAX_PLAYERS, MAX_BYTES = 180, 1000, 250000
local PROMPT = "LOOTVIEWER_ROSTER_TRANSFER"

local function split(value, separator)
    local fields, cursor = {}, 1
    while true do
        local found = value:find(separator, cursor, true)
        fields[#fields + 1] = value:sub(cursor, found and found - 1 or #value)
        if not found then return fields end
        cursor = found + #separator
    end
end

local function encode(value)
    local result = {}
    for index = 1, #value, 3 do
        local a, b, c = value:byte(index, index + 2)
        local number = a * 65536 + (b or 0) * 256 + (c or 0)
        result[#result + 1] = ALPHABET:sub(math.floor(number / 262144) + 1, math.floor(number / 262144) + 1)
            .. ALPHABET:sub(math.floor(number / 4096) % 64 + 1, math.floor(number / 4096) % 64 + 1)
            .. (b and ALPHABET:sub(math.floor(number / 64) % 64 + 1, math.floor(number / 64) % 64 + 1) or "=")
            .. (c and ALPHABET:sub(number % 64 + 1, number % 64 + 1) or "=")
    end
    return table.concat(result)
end

local function decode(value)
    if #value % 4 ~= 0 or value:find("[^%w+/=]") then return nil end
    local result = {}
    for index = 1, #value, 4 do
        local a, b, c, d = value:sub(index, index), value:sub(index + 1, index + 1),
            value:sub(index + 2, index + 2), value:sub(index + 3, index + 3)
        if not VALUES[a] or not VALUES[b] or (c ~= "=" and not VALUES[c])
            or (d ~= "=" and not VALUES[d]) or (c == "=" and d ~= "=")
            or ((c == "=" or d == "=") and index + 3 ~= #value) then return nil end
        local number = VALUES[a] * 262144 + VALUES[b] * 4096 + (VALUES[c] or 0) * 64 + (VALUES[d] or 0)
        result[#result + 1] = string.char(math.floor(number / 65536))
            .. (c ~= "=" and string.char(math.floor(number / 256) % 256) or "")
            .. (d ~= "=" and string.char(number % 256) or "")
    end
    local raw = table.concat(result)
    return encode(raw) == value and raw or nil
end

local function checksum(value)
    local a, b = 1, 0
    for index = 1, #value do
        a = (a + value:byte(index)) % 65521
        b = (b + a) % 65521
    end
    return string.format("%08x", b * 65536 + a)
end

local function clean(value, limit, allowEmpty)
    return type(value) == "string" and #value <= limit and (allowEmpty or value ~= "")
        and value == LV.Util:Trim(value) and not value:find("[%z\001-\031\127|]")
end

local function validPlayer(name)
    return clean(name, 128) and name:match("^[^%s%-]+%-[^%s]+$") ~= nil
end

local function peerKey(name)
    return LV.Guild:NormalizeMemberName(name):lower()
end

function LV.RosterTransfer:IsTransferKind(kind)
    return KINDS[kind] == true
end

function LV.RosterTransfer:CanManage(guildKey)
    local actual = LV.Guild:ActualInfo()
    if not actual or actual.key ~= guildKey then return false, "Select your current guild to transfer a roster." end
    if not LV.Guild:CanModifySession() then return false, "Your roster permissions do not allow roster transfers." end
    return true
end

function LV.RosterTransfer:Export(guildKey, teamID)
    local allowed, reason = self:CanManage(guildKey)
    if not allowed then return nil, reason end
    local roster, team = LV.Store:TeamRoster(guildKey, teamID)
    if not roster or not clean(team.name, 96) or not clean(guildKey, 256) then
        return nil, "This team cannot be exported (team names must be 96 bytes or fewer)."
    end
    local rows = {}
    for nameID, assignment in pairs(roster) do
        rows[#rows + 1] = { player = LV.Store:DictionaryValue(guildKey, "n", nameID),
            type = assignment.t or "raider", primary = assignment.p or "", secondary = assignment.s or "" }
    end
    table.sort(rows, function(a, b) return a.player < b.player end)
    local author = LV.Store:DictionaryValue(guildKey, "n", team.rby)
    if author == "" then author = LV.Util:PlayerFullName() end
    local lines = { table.concat({ guildKey, team.name, tostring(#rows), tostring(tonumber(team.rt) or 0), author }, "\t") }
    for _, row in ipairs(rows) do
        lines[#lines + 1] = table.concat({ row.player, row.type, row.primary, row.secondary }, "\t")
    end
    local raw = table.concat(lines, "\n")
    local value = "LVR1:" .. encode(raw) .. ":" .. checksum(raw)
    local parsed, errorText = self:Decode(value)
    if not parsed then return nil, errorText end
    return value, parsed
end

function LV.RosterTransfer:Decode(value)
    if type(value) ~= "string" or #value > MAX_BYTES + 4096 then return nil, "Roster string is too large." end
    value = value:gsub("%s", "")
    if #value > MAX_BYTES then return nil, "Roster string is too large." end
    local encoded, expected = value:match("^LVR1:([A-Za-z0-9+/=]+):(%x%x%x%x%x%x%x%x)$")
    if not encoded then return nil, "Expected a LootViewer LVR1 roster string." end
    local raw = decode(encoded)
    if not raw or checksum(raw) ~= expected:lower() then return nil, "Roster string is damaged or incomplete." end
    local lines = split(raw, "\n")
    local header = split(lines[1], "\t")
    local count, revision = tonumber(header[3]), tonumber(header[4])
    if #header ~= 5 or not clean(header[1], 256) or not clean(header[2], 96)
        or LV.Util:NormalizeSlug(header[2]) == LV.Constants.PUG_TEAM_ID
        or not count or not header[3]:match("^%d+$") or count > MAX_PLAYERS or count ~= #lines - 1
        or not revision or not header[4]:match("^%d+$") or revision > 9007199254740991 or not validPlayer(header[5]) then
        return nil, "Invalid roster header or player count."
    end
    local result, seen = { guildKey = header[1], team = header[2], revision = revision, author = header[5], rows = {} }, {}
    for index = 2, #lines do
        local fields = split(lines[index], "\t")
        local name = fields[1]
        if #fields ~= 4 or not validPlayer(name) or seen[name:lower()]
            or not TYPES[fields[2]] or not ROLES[fields[3]] or not ROLES[fields[4]]
            or (fields[4] ~= "" and fields[3] == fields[4]) then
            return nil, "Invalid or duplicate player in roster string."
        end
        seen[name:lower()] = true
        result.rows[#result.rows + 1] = { player = name, type = fields[2], primary = fields[3], secondary = fields[4] }
    end
    return result
end

function LV.RosterTransfer:MatchingTeam(guildKey, teamName)
    local record = LV.Store:GuildRecord(guildKey)
    local match
    for _, team in ipairs(record.cfg.teams or {}) do
        if team.name:lower() == teamName:lower() then
            if match then return nil, "More than one team has this name. Rename one before importing." end
            match = team
        end
    end
    return match
end

function LV.RosterTransfer:CanReceive(guildKey, sender, memberID)
    local actual = LV.Guild:ActualInfo()
    if not actual or actual.key ~= guildKey then return false, "This roster belongs to a different guild." end
    return LV.Guild:CanAcceptRosterPublisher(guildKey, sender, memberID)
end

-- Called only after a confirmation; decoding and all permission checks precede writes.
function LV.RosterTransfer:Import(guildKey, value, sender, memberID)
    local allowed, reason
    if sender then allowed, reason = self:CanReceive(guildKey, sender, memberID)
    else allowed, reason = self:CanManage(guildKey) end
    if not allowed then return nil, reason end
    local data, errorText = self:Decode(value)
    if not data then return nil, errorText end
    if data.guildKey ~= guildKey then return nil, "This roster belongs to a different guild." end
    local team
    team, errorText = self:MatchingTeam(guildKey, data.team)
    if errorText then return nil, errorText end
    team = team or LV.Store:AddRaidTeam(guildKey, data.team)
    if not team then return nil, "Unable to create the roster team." end
    local roster = LV.Store:TeamRoster(guildKey, team.id)
    wipe(roster)
    for _, row in ipairs(data.rows) do
        local nameID = LV.Store:NameID(guildKey, row.player)
        LV.Store:SetTeamRosterPlayer(guildKey, team.id, nameID, row.type, row.primary, row.secondary)
    end
    if sender then
        team.rt, team.rby = data.revision, LV.Store:NameID(guildKey, data.author)
    else
        LV.RosterSync:BumpTeamRevision(team)
        team.rby = LV.Store:NameID(guildKey, LV.Util:PlayerFullName())
    end
    if LV.UI and LV.UI.Refresh then LV.UI:Refresh() end
    return team, #data.rows
end

function LV.RosterTransfer:Send(guildKey, teamID, target)
    local value, data = self:Export(guildKey, teamID)
    if not value then return false, data end
    local publisher, publisherReason = LV.Guild:CanPublishRoster()
    if not publisher then return false, publisherReason end
    if not C_Timer or not C_Timer.NewTicker or not C_Timer.After then return false, "Roster transfer timers are unavailable." end
    if self.outbound then return false, "A roster offer is still active. Wait for it to finish or expire." end
    target = LV.Util:Trim(target)
    local channel, destination = "WHISPER", target
    local category = LE_PARTY_CATEGORY_HOME
    if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then category = LE_PARTY_CATEGORY_INSTANCE end
    if target:lower() == "group" or target:lower() == "raid" then
        if not IsInGroup(category) or (target:lower() == "raid" and not IsInRaid(category)) then
            return false, "You are not in the requested group or raid."
        end
        channel = category == LE_PARTY_CATEGORY_INSTANCE and "INSTANCE_CHAT" or (IsInRaid(category) and "RAID" or "PARTY")
        destination = nil
    else
        destination = LV.Guild:NormalizeMemberName(target)
        if not validPlayer(destination) or peerKey(destination) == peerKey(LV.Util:PlayerFullName()) then
            return false, "Enter another character name, Name-Realm, group, or raid."
        end
    end
    self.serial = (self.serial or 0) + 1
    local offer = { token = tostring(LV.Util:ServerNow()) .. "-" .. tostring(self.serial),
        value = value, guildKey = guildKey, teamID = teamID, peers = {}, target = destination,
        accepted = 0, responses = {}, verifying = {} }
    self.outbound = offer
    local sent = LV.Comms:SendMessage("LVO", { offer.token, checksum(guildKey), encode(data.team), #data.rows, #value,
        LV.Guild:OwnClubMemberID() or "" }, channel, destination)
    if not sent then self.outbound = nil; return false, "Unable to send addon messages." end
    C_Timer.After(60, function()
        if self.outbound ~= offer then return end
        offer.closed = true
        self:FinishOffer(offer)
        if offer.accepted == 0 and not next(offer.verifying) then
            LV:Print(next(offer.responses) and "Roster offer expired without acceptance."
                or "No roster offer receipt. Check the target name and that the recipient has the roster-transfer version of LootViewer loaded.")
        end
    end)
    return true, "Offered " .. data.team .. " to " .. target .. ". Recipients have 60 seconds to accept."
end

function LV.RosterTransfer:FinishOffer(offer)
    if self.outbound ~= offer then return end
    if next(offer.verifying) then return end
    for _, peer in pairs(offer.peers) do if not peer.done then return end end
    if offer.target or offer.closed then self.outbound = nil end
end

function LV.RosterTransfer:StartAcceptedOffer(offer)
    if self.inbound ~= offer or offer.accepted then return end
    if offer.rankTicker then offer.rankTicker:Cancel(); offer.rankTicker = nil end
    offer.accepted = true
    C_Timer.After(600, function()
        if self.inbound == offer then
            self.inbound = nil
            if not offer.complete then LV:Print("Roster transfer expired. Your roster was unchanged.") end
        end
    end)
    LV.Comms:SendWhisper("LVA", offer.sender, { offer.token })
end

function LV.RosterTransfer:AcceptOffer(offer)
    if self.inbound ~= offer or offer.confirmed or offer.expires <= LV.Util:ServerNow() then return end
    offer.confirmed = true
    local allowed, reason, reasonCode = self:CanReceive(offer.guildKey, offer.sender, offer.memberID)
    if allowed then self:StartAcceptedOffer(offer); return end
    if reasonCode ~= "rankUnavailable" or not C_Timer.NewTicker then
        self:DeclineOffer(offer, reason); LV:Print("Roster transfer rejected: " .. tostring(reason)); return
    end
    -- An explicit acceptance authorizes looking up this one sender. A missing
    -- Blizzard cache must not hide the offer or grant permission to import it.
    LV:Print("Accepted roster offer. Waiting for Blizzard to load " .. offer.sender .. "'s guild rank...")
    LV.Comms:SendWhisper("LVH", offer.sender, { offer.token, "checking" })
    local search, expires = {}, GetTime() + 20
    LV.Guild:RequestSyncPartnerRank(offer.guildKey)
    offer.rankTicker = C_Timer.NewTicker(1, function()
        if self.inbound ~= offer then offer.rankTicker:Cancel(); return end
        local rank, status = LV.Guild:ClubMemberRank(offer.guildKey, offer.sender, offer.memberID)
        if rank == nil and status ~= "club rank not loaded" and GetTime() < expires then
            LV.Guild:FindSyncClubMember(offer.guildKey, offer.sender, search)
        end
        local verified, detail, code = self:CanReceive(offer.guildKey, offer.sender, offer.memberID)
        if verified then self:StartAcceptedOffer(offer)
        elseif code ~= "rankUnavailable" or GetTime() >= expires then
            local errorText = code == "rankUnavailable" and "Blizzard could not verify the sender's guild rank. Retry after the Guild window has loaded."
                or detail
            self:DeclineOffer(offer, errorText)
            LV:Print("Roster transfer rejected: " .. tostring(errorText))
        end
    end)
end

function LV.RosterTransfer:DeclineOffer(offer, reason)
    if self.inbound ~= offer then return end
    if offer.rankTicker then offer.rankTicker:Cancel(); offer.rankTicker = nil end
    self.inbound = nil
    LV.Comms:SendWhisper("LVD", offer.sender, { offer.token, reason or "" })
end

function LV.RosterTransfer:HandleMessage(parts, sender, channel)
    local kind, token = parts[1], parts[2]
    if peerKey(sender) == peerKey(LV.Util:PlayerFullName()) then return end
    if kind == "LVC" and channel == "WHISPER" then
        local receipt = self.receipts and self.receipts[peerKey(sender)]
        if receipt and receipt.token == token and tonumber(parts[3]) == receipt.sequence
            and tonumber(parts[4]) == receipt.sequence and parts[5] == receipt.chunk then
            LV.Comms:SendWhisper("LVK", sender, { token, receipt.sequence })
            return
        end
    end
    if kind == "LVO" then
        if channel ~= "WHISPER" and channel ~= "PARTY" and channel ~= "RAID" and channel ~= "INSTANCE_CHAT" then return end
        local actual = LV.Guild:ActualInfo()
        local teamName, count, size = decode(parts[4] or ""), tonumber(parts[5]), tonumber(parts[6])
        if not token or not token:match("^%d+%-%d+$") or #token > 24
            or not clean(teamName, 96) or not count or count < 0 or count > MAX_PLAYERS or count ~= math.floor(count)
            or not size or size < 16 or size > MAX_BYTES or size ~= math.floor(size) then return end
        if not C_Timer or not C_Timer.After then return end
        local function rejectOffer(reason)
            LV.Comms:SendWhisper("LVH", sender, { token, "rejected", reason })
        end
        if not actual or parts[3] ~= checksum(actual.key) then rejectOffer("This roster is for a different guild."); return end
        if self.inbound and not self.inbound.complete then
            if self.inbound.token == token and peerKey(self.inbound.sender) == peerKey(sender) then
                LV.Comms:SendWhisper("LVH", sender, { token, "shown" })
            else rejectOffer("Another roster offer is already open.") end
            return
        end
        local team, errorText = self:MatchingTeam(actual.key, teamName)
        if errorText then rejectOffer(errorText); return end
        local offer = { sender = sender, token = token, guildKey = actual.key, team = teamName,
            count = count, size = size, total = math.ceil(size / CHUNK_SIZE), chunks = {}, received = 0,
            expires = LV.Util:ServerNow() + 60, memberID = tonumber(parts[7]) }
        self.inbound = offer
        local summary = teamName .. " (" .. count .. " players).\n"
            .. (team and "Replace this team's current roster?" or "Create this team and import its roster?")
        local popup = StaticPopup_Show(PROMPT, sender, summary, offer)
        if not popup then
            self.inbound = nil
            rejectOffer("No confirmation slot is available. Close another dialog and retry.")
            LV:Print("Roster confirmation could not open. Close another dialog and ask " .. sender .. " to retry.")
            return
        end
        -- /lv uses FULLSCREEN_DIALOG, above Blizzard's usual popup strata.
        -- Restore the shared popup frame before it is reused by another dialog.
        popup._lvRosterStrata, popup._lvRosterLevel = popup:GetFrameStrata(), popup:GetFrameLevel()
        if not popup._lvRosterHideHook then
            popup._lvRosterHideHook = true
            popup:HookScript("OnHide", function(frame)
                if frame._lvRosterStrata then
                    frame:SetFrameStrata(frame._lvRosterStrata)
                    frame:SetFrameLevel(frame._lvRosterLevel)
                    frame._lvRosterStrata, frame._lvRosterLevel = nil, nil
                end
            end)
        end
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        if LV.UI and LV.UI.frame then popup:SetFrameLevel(LV.UI.frame:GetFrameLevel() + 650) end
        popup:Raise()
        LV.Comms:SendWhisper("LVH", sender, { token, "shown" })
        C_Timer.After(60, function()
            if self.inbound == offer and not offer.confirmed then
                self.inbound = nil
            end
        end)
        return
    end
    if channel ~= "WHISPER" then return end
    local outbound, inbound = self.outbound, self.inbound
    if kind == "LVH" and outbound and outbound.token == token
        and (not outbound.target or peerKey(outbound.target) == peerKey(sender)) then
        local key, status = peerKey(sender), parts[3]
        if status ~= "shown" and status ~= "checking" and status ~= "rejected" then return end
        if outbound.responses[key] == status then return end
        outbound.responses[key] = status
        if status == "checking" then
            outbound.verifying[key] = true
            C_Timer.After(25, function()
                if self.outbound == outbound and outbound.verifying[key] then
                    outbound.verifying[key] = nil
                    LV:Print(sender .. " could not finish verifying roster permissions.")
                    self:FinishOffer(outbound)
                end
            end)
            LV:Print(sender .. " accepted the offer and is verifying roster permissions...")
        elseif status == "shown" then
            LV:Print("Roster confirmation shown to " .. sender .. ".")
        else
            outbound.verifying[key] = nil
            LV:Print("Roster offer rejected by " .. sender .. ": " .. tostring(parts[4] or "unavailable"))
            if outbound.target then self.outbound = nil end
            self:FinishOffer(outbound)
        end
    elseif kind == "LVA" and outbound and (not outbound.closed or outbound.verifying[peerKey(sender)]) and outbound.token == token
        and (not outbound.target or peerKey(outbound.target) == peerKey(sender)) then
        if not self:CanManage(outbound.guildKey) then return end
        local key = peerKey(sender)
        outbound.verifying[key] = nil
        if outbound.peers[key] or outbound.accepted >= 40 then return end
        outbound.accepted = outbound.accepted + 1
        local peer = { sender = sender, sequence = 1, total = math.ceil(#outbound.value / CHUNK_SIZE), attempts = 0, nextAt = 0 }
        outbound.peers[key] = peer
        C_Timer.After(600, function()
            if self.outbound == outbound and not peer.done then
                peer.done = true
                peer.ticker:Cancel()
                LV:Print("Roster transfer to " .. sender .. " expired.")
                self:FinishOffer(outbound)
            end
        end)
        peer.ticker = C_Timer.NewTicker(0.25, function()
            if self.outbound ~= outbound then peer.ticker:Cancel(); return end
            if GetTime() < peer.nextAt or GetTime() < (self.nextChunkAt or 0) then return end
            if peer.attempts >= 5 or not self:CanManage(outbound.guildKey) then
                peer.done = true
                peer.ticker:Cancel()
                LV:Print("Roster transfer to " .. sender .. " stopped (timeout or roster permission changed).")
                self:FinishOffer(outbound)
                return
            end
            peer.attempts, peer.nextAt = peer.attempts + 1, GetTime() + 1.5
            self.nextChunkAt = GetTime() + 0.25
            local offset = (peer.sequence - 1) * CHUNK_SIZE + 1
            LV.Comms:SendWhisper("LVC", sender, { token, peer.sequence, peer.total, outbound.value:sub(offset, offset + CHUNK_SIZE - 1) })
        end)
    elseif kind == "LVK" and outbound and outbound.token == token then
        local peer = outbound.peers[peerKey(sender)]
        if not peer or peer.done or tonumber(parts[3]) ~= peer.sequence then return end
        peer.sequence, peer.attempts, peer.nextAt = peer.sequence + 1, 0, 0
        if peer.sequence > peer.total then
            peer.done = true
            peer.ticker:Cancel()
            LV:Print(sender .. " received and imported the roster.")
            self:FinishOffer(outbound)
        end
    elseif kind == "LVD" and outbound and outbound.token == token then
        local key = peerKey(sender)
        local peer = outbound.peers[key]
        if not peer and not outbound.responses[key] and (not outbound.target or peerKey(outbound.target) ~= key) then return end
        outbound.verifying[key] = nil
        if peer then peer.done = true; peer.ticker:Cancel() end
        LV:Print(sender .. " declined or could not import the roster.")
        if parts[3] and parts[3] ~= "" then LV:Print("Roster transfer: " .. parts[3]) end
        if outbound.target and peerKey(outbound.target) == peerKey(sender) then self.outbound = nil end
        self:FinishOffer(outbound)
    elseif kind == "LVC" and inbound and inbound.token == token and inbound.accepted
        and peerKey(inbound.sender) == peerKey(sender) then
        local sequence, total, chunk = tonumber(parts[3]), tonumber(parts[4]), parts[5]
        if not sequence or sequence ~= math.floor(sequence) or sequence < 1 or sequence > inbound.total
            or total ~= inbound.total or type(chunk) ~= "string" or #chunk > CHUNK_SIZE then return end
        local length = sequence == total and inbound.size - (total - 1) * CHUNK_SIZE or CHUNK_SIZE
        if #chunk ~= length then return end
        if sequence == inbound.received + 1 then
            inbound.chunks[sequence], inbound.received = chunk, sequence
            if sequence == total then
                local value = table.concat(inbound.chunks)
                local data = self:Decode(value)
                local team, errorText
                if data and data.team == inbound.team and #data.rows == inbound.count then
                    team, errorText = self:Import(inbound.guildKey, value, sender, inbound.memberID)
                end
                if not team then
                    LV:Print(errorText or "Roster transfer was invalid. Your roster was unchanged.")
                    self:DeclineOffer(inbound, errorText or "The roster string was invalid.")
                    return
                end
                inbound.complete = true
                local receipt = { token = token, sequence = total, chunk = chunk }
                self.receipts = self.receipts or {}
                local key = peerKey(sender)
                self.receipts[key] = receipt
                C_Timer.After(600, function() if self.receipts[key] == receipt then self.receipts[key] = nil end end)
                C_Timer.After(10, function() if self.inbound == inbound then self.inbound = nil end end)
                LV:Print("Imported " .. inbound.count .. " players into " .. team.name .. " from " .. sender .. ".")
                -- Retain the completed transfer briefly so a lost final ACK is retried safely.
            end
        end
        if sequence <= inbound.received and inbound.chunks[sequence] == chunk then
            LV.Comms:SendWhisper("LVK", sender, { token, sequence })
        end
    end
end

StaticPopupDialogs[PROMPT] = {
    text = "%s wants to send a LootViewer roster:\n%s",
    button1 = ACCEPT,
    button2 = "Decline",
    timeout = 60,
    whileDead = true,
    hideOnEscape = true,
    OnAccept = function(_, data) LV.RosterTransfer:AcceptOffer(data) end,
    OnCancel = function(_, data) LV.RosterTransfer:DeclineOffer(data) end,
}
