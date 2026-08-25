# SavedVariables Draft

This draft is the contract for the future `LootViewer.lua` upload parser.

The top-level `g` table contains guild records. The compact `c.ui` table stores
the local `/lv` window state and global raid/dungeon view selection. The `a`
table contains account settings. The `m` table contains account-wide dungeon
history and is deliberately excluded from guild sync.

`Pugs` is a reserved virtual raid-team definition (`team = "pugs"`). It is
available account-wide but is not duplicated into any guild's `cfg.teams`.
It always uses `#C5C6C7`, has no schedule or editable configuration, and its
raid sessions, loot, and trades are omitted from both outgoing and incoming
guild sync. Existing guild team definitions using the reserved ID are removed
during normalization without deleting historical raids tagged with that ID.
Pugs sessions may be started regardless of guild authority. The account-wide
`a.autoPugRaids` preference optionally starts one after entering current-tier,
non-Raid-Finder raid content outside all configured team schedule windows.

```lua
{
  v = 2,
  a = { dungeonLogging = false, autoPugRaids = false },
  c = {
    ui = {
      context = "raid:midnight-2",
      window = {},
      lootFilters = { raidMinDifficulty = "lfr", dungeonMinTrack = "champion" },
    },
  },
  g = {},
  m = {},
}
```

## Guild Key

`region:realm:guild`, lower-cased and slugged.

Example:

```text
us:sargeras:sanctimonious
```

## Guild Record

```lua
{
  v = 2,
  cfg = {
    enabled = true,
    prompt = true,
    promptBefore = 60,
    endGrace = 0,
    promptTimeout = 30,
    lateGrace = 10,
    authority = "assist",
    rankMin = 0,
    rankMax = 3,
    tradeRaid = true,
    whisper = "standby",
    pruneMode = "days:30",
    selectedTeam = "main",
    teams = {
      {
        id = "main",
        name = "Main",
        tz = "central",
        clock24 = false,
        excludeSync = false,
        rt = 1780000000,
        ro = {
          [1] = { t = "raider", p = "tank", s = "melee" },
          [2] = { t = "trial", p = "healer" },
          [3] = { t = "helper", p = "ranged" },
        },
        schedules = {
          { w = 3, h = 20, m = 0, d = 180 },
          { w = 5, h = 20, m = 0, d = 180 },
        },
      },
      {
        id = "altraid",
        name = "AltRaid",
        tz = "eastern",
        clock24 = true,
        excludeSync = true,
        schedules = {
          { w = 7, h = 20, m = 0, d = 180 },
        },
      },
    },
    pruneDays = 0,
  },
  d = {
    n = { "Meemage-Sargeras" },
    i = { "item:19019::::::::90:::::" },
    s = { "Manaforge Omega", "Mythic", "Dimensius", "Main" },
  },
  gr = {},
  r = {},
  l = {},
  t = {},
  o = {},
  x = {},
}
```

Each configured team stores its roster in compact `ro` entries keyed by the
guild name-dictionary ID. `t` is the roster type (`raider`, `trial`, or
`helper`), `p` is the primary role, and `s` is the optional secondary role.
Valid roles are `tank`, `healer`, `melee`, and `ranged`. Missing Raiders and
Trials are marked no-show when that team's tracked raid ends; Helpers are never
marked automatically. Each team also stores its latest roster revision in `rt`
so newer authoritative addon snapshots replace older cached copies safely.

## Raid Session

```lua
{
  id = "r1",
  st = 1780000000,
  sst = 1780000400,
  set = 1780011200,
  en = 1780007200,
  z = 1,
  iid = 9999,
  diff = 2,
  did = 16,
  sea = "midnight-2",
  team = "main",
  tn = 4,
  by = 1,
  p = { [1] = 1780000000 },
  b = { [2] = 1780000000 },
  late = { [3] = 1780000900 },
  kills = {
    {
      ts = 1780001200,
      e = 3131,
      b = 3,
      d = 16,
      n = 20,
      p = { 1, 3, 4 },
      bench = { 2 },
      late = { 3 },
    },
  },
}
```

`st` records when tracking began. For a scheduled raid, `sst` and `set` record
the scheduled start and end instants. `sst` anchors `lateGrace`; inviting or
starting tracking early does not consume the grace period. Tracking stops at
`set` plus `endGrace`. Ad-hoc sessions do not have either scheduled timestamp.

The global season/content selector controls which tier is eligible for
scheduled prompts. New raid sessions store `sea` as a compact season ID.
Records created by older addon versions are classified on read from their
instance ID/name and, as a final fallback, their start date.

## Loot Event

```lua
{
  id = "l1",
  ts = 1780001210,
  sid = "r1",
  e = 3131,
  iid = 9999,
  inst = 1,
  boss = 3,
  did = 16,
  diff = 2,
  p = 1,
  item = 1,
  itemID = 19019,
  q = 1,
  r = "need",
  raw = "NeedMainSpec",
  src = "boss",
  boe = nil,
  wb = nil,
  tr = "t1",
}
```

## Trade Event

```lua
{
  id = "t1",
  ts = 1780001800,
  sid = "r1",
  f = 1,
  to = 2,
  item = 1,
  itemID = 19019,
  loot = "l1",
  src = "observed",
  by = 1,
}
```

`src = "manual"` identifies a trade entered from Loot History and `by` stores
the character that entered it. Trade-window captures use `src = "observed"`;
the Trades view labels those records as `Detected`.

## Dungeon Record

Dungeon history is account-wide and not guild-scoped. Names remain raw
character names; mains, alts, and pugs are not inferred. Its dictionaries use
the same compact `n` (name), `i` (item), and `s` (string) convention.

```lua
{
  v = 2,
  d = { n = {}, i = {}, s = {} },
  r = {
    {
      id = "m1", sea = "midnight-2", cm = 999, iid = 9999,
      z = 1, did = 8, lvl = 10, st = 1780000000, en = 1780001800,
      dur = 1740000, timed = 1, up = 1, p = { 1, 2, 3, 4, 5 },
    },
  },
  l = {
    {
      id = "ml1", run = "m1", sea = "midnight-2", ts = 1780001810,
      p = 1, o = 2, item = 1, itemID = 19019, q = 1,
      src = "end", track = "hero", tr = "mt1",
    },
  },
  b = {
    {
      id = "mb1", run = "m1", sea = "midnight-2", ts = 1780001820,
      p = 1, spec = 102, ok = 1, item = 2, itemID = 19020,
    },
  },
  t = {
    {
      id = "mt1", run = "m1", ts = 1780001900,
      f = 1, to = 2, item = 1, itemID = 19019, loot = "ml1",
    },
  },
}
```

`track` is `champion` for level 0-5 dungeon gear, `hero` for level 6-10,
and `myth` only for gear returned by `BONUS_ROLL_RESULT`. Bonus records retain
`spec`, the event's loot-specialization ID, so the per-dungeon/spec knockout
history can be reconstructed.
