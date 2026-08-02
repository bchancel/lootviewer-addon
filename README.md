# LootViewer

LootViewer is a World of Warcraft Retail addon for guild-scoped raid attendance, loot, and trade tracking. It records compact, merge-friendly SavedVariables that can be uploaded to the companion LootViewer web application.

Retail targets: WoW `12.1.0` and `12.0.7` / interfaces `120100, 120007`.

## Features

- Tracks raid sessions, encounter attendance snapshots, bench credit, and late flags.
- Captures loot and follow-up trades while preserving stable event identities.
- Supports separate raid teams and schedules within one guild.
- Stores compact, guild-scoped history across characters on the same account.
- Provides `/lv` configuration, attendance, and history views.
- Supports a session-only `/lv guild_set <guild>` override for viewing stored guild data from unguilded alts.
- Synchronizes records between participating guild members through addon messages.

## Repository layout

- `Core/`: storage, guild identity, communication, and data synchronization.
- `Events/`: raid, loot, and trade collection.
- `UI/`: the `/lv` interface and guild attendance overlay.
- `Docs/SAVED_VARIABLES.md`: compact data format documentation.
- `LootViewer.toc`: Retail addon manifest and release version.
- `verify.ps1`: static source, manifest, and packaging checks.
- `build.ps1`: creates a CurseForge-compatible zip in `dist/`.

## Verify and build

```powershell
.\verify.ps1
.\build.ps1
```

The build contains one top-level `LootViewer/` directory and only the files loaded by `LootViewer.toc`.

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

`LootViewerDB` is guild-scoped and uses compact dictionaries for character names, item strings, and repeated labels. Raid sessions, loot events, trades, roster overrides, and exclusions are stored separately so uploads from multiple players can be merged without changing raw event identity. See `Docs/SAVED_VARIABLES.md` for the schema.
