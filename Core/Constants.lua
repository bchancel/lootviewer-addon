local _, LV = ...

LV.Constants = {
    DB_VERSION = 1,
    PREFIX = "LootViewer",
    TRACK_PROMPT = "LOOTVIEWER_TRACK_RAID",
    MAIN_PROMPT = "LOOTVIEWER_MAIN_PLAYER",
    TEAM_PROMPT = "LOOTVIEWER_RAID_TEAM",
    DELETE_RAID_PROMPT = "LOOTVIEWER_DELETE_RAID",
    SYNC_INVITE_PROMPT = "LOOTVIEWER_SYNC_INVITE",
    TRADE_WINDOW_SECONDS = 2 * 60 * 60,
    SESSION_IDLE_SECONDS = 8 * 60 * 60,
    DEFAULTS = {
        cfg = {
            enabled = true,
            prompt = true,
            promptBefore = 60,
            promptAfter = 60,
            promptTimeout = 30,
            lateGrace = 10,
            authority = "assist",
            rankMin = 0,
            rankMax = 3,
            tradeRaid = true,
            whisper = "bench",
            schedules = {},
            selectedTeam = "main",
            teams = {
                {
                    id = "main",
                    name = "Main",
                    tz = "local",
                    color = { r = 0.1725, g = 0.5569, b = 0.8275, a = 0.8 },
                    schedules = {},
                },
            },
            pruneDays = 0,
        },
    },
}

LV.RollStateLabels = {
    [0] = "need",
    [1] = "offspec",
    [2] = "transmog",
    [3] = "greed",
    [4] = "noroll",
    [5] = "pass",
}
