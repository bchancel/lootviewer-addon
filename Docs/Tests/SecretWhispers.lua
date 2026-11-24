-- Lua 5.1 cannot create WoW secrets. These opaque stand-ins reject string access
-- and report as strings so type checks alone cannot hide a missing secret guard.
local secrets = {}
local function secretString()
    local value = newproxy(true)
    getmetatable(value).__tostring = function() error("Secret value was converted to text") end
    getmetatable(value).__index = function() error("Secret value was indexed") end
    secrets[value] = true
    return value
end
local secretMessage, secretSender = secretString(), secretString()
local env = setmetatable({ StaticPopupDialogs = {}, YES = "Yes", NO = "No" }, { __index = _G })
env.issecretvalue = function(value) return secrets[value] == true end
env.type = function(value) return secrets[value] and "string" or type(value) end

local LV = { modules = {}, events = {}, Constants = { TRACK_PROMPT = "test-track" } }
function LV:RegisterEvent(event, handler) self.events[event] = handler end
for _, path in ipairs({ "Core/Util.lua", "Events/Raid.lua" }) do
    local chunk = assert(loadfile(path))
    setfenv(chunk, env)("LootViewer", LV)
end

local function eq(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
eq(LV.Util:Trim(secretMessage), "", "Secret message trims to empty text")
eq(LV.Util:Trim(secretSender), "", "Secret name trims to empty text")
eq(LV.Util:IsBlank(secretMessage), true, "Secret text is treated as blank")
eq(LV.Util:NormalizeSlug(secretMessage), "", "String helpers receive safe empty text")
eq(LV.Util:Trim(" \tordinary text\r\n"), "ordinary text", "Ordinary whitespace trimming")
eq(LV.Util:Trim(nil), "", "Missing text")
eq(LV.Util:Trim(false), "", "False keeps its existing empty-text behavior")
eq(LV.Util:Trim(123), "123", "Numeric text")

local cfg, session = { whisper = " \tStaNdBy " }, { team = "pugs" }
LV.Guild = { CurrentConfig = function() return cfg end }
function LV.Raid:GetActiveSession() return session end
local marked, replies = {}, {}
function LV.Raid:MarkPlayerBench(sender, source)
    assert(not secrets[sender], "Secret sender must never change attendance")
    marked[#marked + 1] = { sender = sender, source = source }
end
env.SendChatMessage = function(message, channel, language, target)
    assert(not secrets[target], "Secret sender must never be used as a whisper target")
    replies[#replies + 1] = { message = message, channel = channel, language = language, target = target }
end
local function whisper(message, sender)
    LV.events.CHAT_MSG_WHISPER("CHAT_MSG_WHISPER", message, sender)
end
local function ignored(message, sender, label)
    local beforeMarked, beforeReplies = #marked, #replies
    whisper(message, sender)
    eq(#marked, beforeMarked, label .. " leaves attendance alone")
    eq(#replies, beforeReplies, label .. " sends no reply")
end

ignored(secretMessage, "Player-Realm", "Secret message")
ignored("standby", secretSender, "Secret sender with a matching keyword")
ignored(secretMessage, secretSender, "Both fields secret")
ignored("hello", "Player-Realm", "Unrelated whisper")
ignored(nil, "Player-Realm", "Missing message")
ignored("standby", nil, "Missing sender")
ignored("standby", "", "Empty sender")
ignored(123, "Player-Realm", "Non-string message")
ignored("standby", 123, "Non-string sender")
whisper(" \tSTANDBY\r\n", "Player-OtherRealm")
eq(#marked, 1, "Readable keyword still marks standby")
eq(marked[1].sender, "Player-OtherRealm", "Full sender name is preserved")
eq(marked[1].source, "whisper", "Standby source")
eq(#replies, 1, "Matching whisper receives one reply")
eq(replies[1].target, "Player-OtherRealm", "Reply target")
eq(replies[1].channel, "WHISPER", "Reply channel")
eq(replies[1].message, "LootViewer marked you as standby for tonight.", "Confirmation text")

cfg.whisper = ""
ignored("", "Player-Realm", "Disabled keyword")
cfg.whisper = "standby"
session = nil
ignored("standby", "Player-Realm", "No active raid")
session, cfg = { team = "pugs" }, nil
ignored("standby", "Player-Realm", "No guild config")

-- Preserve ordinary string handling when the secret API is unavailable.
env.issecretvalue = false
cfg = { whisper = "standby" }
eq(LV.Util:Trim(" safe "), "safe", "Trim without the secret API")
whisper("standby", "Legacy-Realm")
eq(#marked, 2, "Readable whisper without the secret API")
eq(#replies, 2, "Reply without the secret API")
print("Secret whisper regression tests passed.")
