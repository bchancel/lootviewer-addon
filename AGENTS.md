# LootViewer Addon Maintainer Notes

## Project scope

- This repository contains only the standalone World of Warcraft Retail addon.
- Runtime source lives at the repository root and is loaded by `LootViewer.toc`.
- Do not add the LootViewer Flask web app, syncer, server data, uploaded logs, Docker files, or deployment files from the combined application repository.
- SavedVariables are compact and guild-scoped. `Core/Store.lua` owns dictionary IDs and per-guild records.
- Raid state is in `Events/Raid.lua`; loot and trade capture are in `Events/Loot.lua` and `Events/Trade.lua`.
- The `/lv` UI lives in `UI/MainFrame.lua`; guild drilldown attendance controls live in `UI/GuildOverlay.lua`.
- Do not rescan full guild rosters automatically. Use online, selected, or manual data to avoid client freezes.

## Release checks

- Keep `LootViewer.toc` interface and version metadata aligned with the supported Retail client.
- Run `./verify.ps1` before committing.
- Run `./build.ps1` and inspect the resulting `dist/LootViewer-<version>.zip` before publishing.
- The release archive must contain one top-level `LootViewer/` directory and only TOC/runtime files.
- Keep the personal `deploy.ps1` local and ignored; it must not be committed or packaged.
- Do not create or push a release tag unless the user explicitly requests a release. Tags matching `v*` publish through the GitHub Actions packager.

## Local testing

```powershell
powershell -ExecutionPolicy Bypass -File .\deploy.ps1
```

The default target is `C:\games\World of Warcraft\_retail_\Interface\AddOns\LootViewer`.
