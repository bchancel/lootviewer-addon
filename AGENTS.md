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
- For each release, write 5-8 numbered changelog entries in simple, direct plain English. Combine related changes, focus on what users will notice, and omit low-level implementation details unless they are essential.
- Use an increasing prerelease suffix while testing a release locally. Start with `<version>-0`, then increase it for each newly tested revision, for example `12.1.6-0`, `12.1.6-1`, and `12.1.6-2`.
- Remove the prerelease suffix only when the branch is ready for its final push and deployment. For example, roll `12.1.6-2` into `12.1.6`.
- Run `./verify.ps1` before committing.
- Run `./build.ps1` and inspect the resulting `dist/LootViewer-<version>.zip` before publishing.
- The release archive must contain one top-level `LootViewer/` directory and only TOC/runtime files.
- Keep the personal `deploy.ps1` local and ignored; it must not be committed or packaged.
- When the user says "update and push," treat that as explicit release authorization and run `update_and_push.ps1` with `-Release` so the version commit, main branch, and release tag are all pushed.
- Do not create or push a release tag for other push requests unless the user explicitly requests a release. Tags matching `v*` publish through the GitHub Actions packager.

## Local testing

```powershell
powershell -ExecutionPolicy Bypass -File .\deploy.ps1
```

The default target is `C:\games\World of Warcraft\_retail_\Interface\AddOns\LootViewer`.

- Unless the user asks not to deploy, copy each newly tested revision to the local Retail addon folder after making and verifying changes.
- If the user explicitly asks to test on PTR, deploy to PTR instead and keep PTR as the default testing target for the rest of that session.
