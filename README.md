# LootViewer

LootViewer is a World of Warcraft Retail addon for guild-scoped raid attendance, loot, and trade tracking plus account-wide local dungeon loot history. It records compact, merge-friendly raid SavedVariables that can be uploaded to the companion LootViewer web application; dungeon records are never synced.

Retail targets: WoW `12.1.0` and `12.0.7` / interfaces `120100, 120007`.

## Features

- Tracks raid sessions, encounter attendance snapshots, standby credit, and late flags.
- Captures loot and follow-up trades while preserving stable event identities.
- Supports separate raid teams and visual 30-minute start/end schedules within one guild, with per-team portable time zones, optional 24-hour labels, and local-only sync exclusion.
- Includes a reserved account-wide Pugs team in every raid-team selector; it has a fixed `#C5C6C7` color, no schedule or configuration, and never syncs.
- Allows any player to start Pugs tracking regardless of guild authority, with an optional account-wide auto-start for current-tier pug raids outside configured raid hours.
- Allows guild officers to publish a `LootViewer Authority:` directive in Guild Information that locks the effective Lead/Assist, Raid Lead, Anyone, or Trusted rank policy without replacing members' local fallback settings.
- Filters Raid History and raid-linked Loot History data by raid tag.
- Provides a Loot History minimum-difficulty slider from LFR through Mythic, with gray LFR and stacked Normal, Heroic, and Mythic distribution segments.
- Anchors scheduled-raid lateness to the configured team-time-zone start plus the grace period, even when tracking starts early.
- Ends scheduled tracking at the configured raid end plus an optional 0-20 minute grace period for extra pulls.
- Tracks Midnight raid tiers separately, with season filters across attendance, meter totals, loot, and trades.
- Keeps 1-6 month attendance ranges inside the current season instead of carrying prior-season raids across a tier boundary.
- Limits scheduled prompts to qualifying guild groups inside raids from the tier selected by the global context selector.
- Stores compact, guild-scoped history across characters on the same account.
- Provides `/lv` configuration, attendance, and history views.
- Adds season-owned tier-token catalogs and a Tier history grouped by token type, slot, and raid difficulty; seasons without a catalog report that no tier tokens are defined.
- Supports a session-only `/lv guild_set <guild>` override for viewing stored guild data from unguilded alts.
- Synchronizes records between participating guild members through addon messages.
- Optionally records Midnight Season 2 Mythic+ end-of-run gear, Mythic 0 boss gear, and bonus-roll loot with the active loot specialization.
- Shows raid and dungeon loot distribution as clickable Normal/Heroic/Mythic or Champion/Hero/Myth stacked meters using the final owner after trades.
- Filters dungeon distribution by minimum Champion/Heroic/Bonus Roll track and by any individual dungeon in the selected season.
- Shows recorded zones and defeated bosses in each Raid History attendance detail.
- Keeps Recent Loot History readable with aligned responsive columns, full raid-hour date tooltips, and compact method icons.
- Offers per-item Recent loot options for recording a manual trade to another raid participant or excluding the item.
- Resolves Recent loot to its final owner after trades while retaining the original looter in the owner tooltip and search index.
- Identifies who initiated a manual trade record in Trades and labels automatic trade-window captures as Detected.
- Lets any player correct Pugs attendance history and move a recorded raid between raid teams without breaking its linked attendance, boss kills, loot, or trades.
- Scales loot Distribution bars proportionally against the highest recipient total, matching a DPS-meter presentation.
- Remembers the last selected raid and dungeon minimum loot-level thresholds across window closes and UI reloads.
- Loads the configuration UI only when requested through the companion `LootViewer_Options` addon.

## Guild authority directive

Guild officers can place exactly one of these standalone lines anywhere in the Guild Information text box:

```text
LootViewer Authority: Lead / Assist
LootViewer Authority: Raid Lead
LootViewer Authority: Anyone
LootViewer Authority: Trusted 0-3
```

Matching is case-insensitive and permits extra whitespace. A valid directive locks the effective Authority setting for members of that guild; the Trusted form also locks the guild-rank range. LootViewer retains each member's saved local values and restores them when the directive is removed. Missing, malformed, or duplicate directives leave local settings active, with malformed and duplicate entries identified in Configuration.

## Repository layout

- `Core/`: storage, guild identity, communication, and data synchronization.
- `Events/`: raid, loot, and trade collection.
- `UI/`: the `/lv` interface and guild attendance overlay.
- `Options/`: source for the `LootViewer_Options` load-on-demand companion addon.
- `Docs/SAVED_VARIABLES.md`: compact data format documentation.
- `LootViewer.toc`: Retail addon manifest and release version.
- `verify.ps1`: static source, manifest, and packaging checks.
- `build.ps1`: creates a CurseForge-compatible zip in `dist/`.

## Verify and build

```powershell
.\verify.ps1
.\build.ps1
```

The build contains sibling `LootViewer/` and `LootViewer_Options/` directories. The options addon depends on the main addon and is loaded only when Configuration is opened.

## Local deployment

`deploy.ps1` is a local, ignored helper modeled after PopAuras. Its default target is:

```text
C:\games\World of Warcraft\_retail_\Interface\AddOns\LootViewer
```

Run it with:

```powershell
powershell -ExecutionPolicy Bypass -File .\deploy.ps1
```

Override the target with `-TargetRoot` or `LOOTVIEWER_ADDON_DEPLOY_TARGET`.

## CurseForge release setup

1. Create the LootViewer project on CurseForge and copy its numeric project ID.
2. Add `## X-Curse-Project-ID: <id>` to `LootViewer.toc`.
3. Add a repository Actions secret named `CF_API_KEY` containing a CurseForge API token.
4. Update `CHANGELOG.md`, then run `./update_and_push.ps1 -NewVersion <major.minor.patch> -Release`.

Tags matching `v*` run the BigWigs packager, create a GitHub release, and upload the Retail package to CurseForge once the project ID and API key are configured.

## SavedVariables

`LootViewerDB.g` is guild-scoped and uses compact dictionaries for character names, item strings, and repeated labels. `LootViewerDB.m` contains account-wide local dungeon runs, loot, bonus rolls, and observed trades, while `LootViewerDB.a` contains account settings. See `Docs/SAVED_VARIABLES.md` for the schema.
