# SavedVariables Draft

This draft is the contract for the future `LootViewer.lua` upload parser.

The top-level `g` table contains guild records. The compact `c.ui.window` table
stores only the local `/lv` window size and position and is not guild data.

## Guild Key

`region:realm:guild`, lower-cased and slugged.

Example:

```text
us:sargeras:sanctimonious
```

## Guild Record

```lua
{
  v = 1,
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
    seasonMode = "auto",
    selectedTeam = "main",
    teams = {
      {
        id = "main",
        name = "Main",
        tz = "EST",
        schedules = {
          { w = 3, h = 20, m = 0, d = 180 },
          { w = 5, h = 20, m = 0, d = 180 },
        },
      },
      {
        id = "altraid",
        name = "AltRaid",
        tz = "EST",
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

## Raid Session

```lua
{
  id = "r1",
  st = 1780000000,
  sst = 1780000400,
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

`st` records when tracking began. For a scheduled raid, `sst` records the
scheduled start in server time and is the anchor for `lateGrace`; inviting or
starting tracking early does not consume the grace period. Ad-hoc sessions do
not have `sst` and use their tracking start instead.

`seasonMode` is `"auto"` by default and can be set to a known season ID to
override the tier used for scheduled prompts. New raid sessions store `sea` as
a compact season ID. Records created by older addon versions are classified on
read from their instance ID/name and, as a final fallback, their start date.

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
