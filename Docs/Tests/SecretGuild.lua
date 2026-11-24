-- Opaque strings and tables fail on access, as restricted WoW values do.
local secrets, secretTables = {}, {}
local function restricted()
    local value = newproxy(true)
    getmetatable(value).__tostring = function() error("Restricted text was converted") end
    getmetatable(value).__index = function() error("Restricted value was indexed") end
    secrets[value] = true
    return value
end
local secretText = restricted()
local secretTable = setmetatable({}, { __index = function() error("Restricted table was indexed") end })
secretTables[secretTable] = true
local env = setmetatable({}, { __index = _G })
env.issecretvalue = function(value) return secrets[value] == true end
env.issecrettable = function(value) return secretTables[value] == true end
env.type = function(value) return secrets[value] and "string" or type(value) end
local now, combat, reads, clubInfo = 1000, false, 0, nil
env.time = function() return now end
env.InCombatLockdown = function() return combat end
env.C_Club = {
    GetGuildClubId = function() return 1 end,
    GetClubInfo = function() reads = reads + 1; return clubInfo end,
}
env.wipe = function(t) for key in pairs(t) do t[key] = nil end end
local LV = { modules = {}, RegisterEvent = function() end, RosterSync = { publisherCache = {} } }
for _, path in ipairs({ "Core/Util.lua", "Core/Guild.lua" }) do
    setfenv(assert(loadfile(path)), env)("LootViewer", LV)
end
local info = { key = "guild", name = "Guild", realm = "Realm" }
function LV.Guild:ActualInfo() return info end
function LV.Guild:CurrentInfo() return info end
function LV.Guild:CurrentConfig() return { authority = "lead" } end
local function eq(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local directive, status = LV.Guild:ParseAuthorityDirective(secretText)
eq(directive, nil, "Restricted parser input has no directive")
eq(status, "unavailable", "Restricted input is unavailable rather than removed")
for _, text in ipairs({ "LootViewer Authority: Anyone", "\r\n LootViewer Authority: Lead/Assist \r\n" }) do
    directive, status = LV.Guild:ParseAuthorityDirective(text)
    eq(status, "valid", "Readable directive parses normally")
end
clubInfo = { description = "LootViewer Authority: Trusted 0-4" }
directive, status = LV.Guild:ScanAuthorityDirective()
eq(directive.mode, "trusted", "Initial readable guild setting")
local cache = LV.Guild.authorityDirectiveCache
for _, hidden in ipairs({ { description = secretText }, restricted(), secretTable, {} }) do
    clubInfo = hidden
    now = now + 31
    directive, status = LV.Guild:EffectiveAuthority()
    eq(directive.mode, "trusted", "Unreadable description preserves cached authority")
    eq(status, "valid", "Unreadable description preserves cached status")
    eq(LV.Guild.authorityDirectiveCache, cache, "No restricted value replaces the cache")
end
clubInfo = nil
LV.Guild:ScanAuthorityDirective()
eq(LV.Guild.authorityDirectiveCache, cache, "Missing club cache keeps authority")
local readText = LV.Guild.GuildInformationText
function LV.Guild:GuildInformationText() return secretText end
LV.Guild:ScanAuthorityDirective()
eq(LV.Guild.authorityDirectiveCache, cache, "Scan guards a restricted getter result")
function LV.Guild:GuildInformationText() error("Club data unavailable") end
LV.Guild:ScanAuthorityDirective()
eq(LV.Guild.authorityDirectiveCache, cache, "API failure keeps authority")
LV.Guild.GuildInformationText = readText
combat = true
local beforeReads = reads
LV.Guild:ScanAuthorityDirective()
eq(reads, beforeReads, "Combat uses cached authority without querying clubs")
combat = false
LV.Guild.authorityDirectiveCache = nil
clubInfo = { description = secretText }
directive = LV.Guild:EffectiveAuthority()
eq(directive.mode, "lead", "No cache uses the local authority setting")
eq(directive.source, "local", "Fallback is marked local")
clubInfo = { description = "LootViewer Authority: Anyone" }
LV.Guild:ScanAuthorityDirective()
clubInfo = { description = "" }
directive, status = LV.Guild:ScanAuthorityDirective()
eq(directive, nil, "Readable removal clears the directive")
eq(status, "missing", "Readable empty description means missing")
clubInfo = { description = "LootViewer Authority: invalid" }
directive, status = LV.Guild:ScanAuthorityDirective()
eq(status, "invalid", "Invalid readable directives are still validated")
env.issecretvalue, env.issecrettable = false, false
clubInfo = { description = "LootViewer Authority: Raid Lead" }
directive = LV.Guild:ScanAuthorityDirective()
eq(directive.mode, "lead", "Readable guild information without secret APIs")
print("PASS: restricted guild descriptions preserve cached authority and safe local fallbacks")
