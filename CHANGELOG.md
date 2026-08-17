# Changelog

## 12.1.2 - 2026-08-16

- Improved and reorganized the UI with clearer naming, responsive history tables, two-column configuration sections, foreground modals, and load-on-demand options.
- Added a global account-wide Pugs raid team with local-only storage, optional automatic tracking, unrestricted Pugs editing, and raid-team reassignment.
- Added account-wide Midnight Season 2 dungeon logging for Mythic+, Mythic 0, trades, and specialization-aware bonus rolls while keeping dungeon data local.
- Added DPS-style raid and dungeon loot distribution with final-owner accounting, clickable difficulty segments, proportional bars, and persistent loot-level filters.
- Expanded Raid and Loot History with global season/content selection, raid tags, World/LFR support, dungeon filters, and detailed zone and boss information.
- Improved loot and trade management with exact roll icons, manual trade recording, detected-trade attribution, final-owner display, and safer item exclusions.
- Improved raid-team configuration and scheduling with per-team sync exclusion, portable time zones, visual raid-time sliders, grace periods, trusted ranks, and confirmed pruning.

## 12.1.1 - 2026-08-11

- Added Midnight Season 1 and Season 2 raid definitions, automatic Season 2 rollover, and a manual current-tier override.
- Limited scheduled tracking prompts to guild groups inside raids from the active tier.
- Added season filters to attendance, meter totals/details, loot, and trade history.
- Replaced the 1-12 month attendance range with 1-6 months, each Midnight season, and all seasons.
- Anchored late attendance to the scheduled server-time raid start plus the configured grace period instead of the time tracking begins.
- Limited 1-6 month attendance ranges to the current season so a new tier never inherits prior-season raids.
- Added a season-aware Tier history tab grouped by token type, with armor slot, recipient, difficulty, and loot method; Midnight Season 2 has its own catalog and undefined seasons show a clear empty state.

## 12.1.0 - 2026-08-01

- Refreshed the `/lv` window with the shared LootViewer addon theme, flat sections, sidebar branding, icons, tabs, and semantic controls.
- Added resizable, off-screen-capable window positioning with saved size and position.
- Reworked attendance detail into scrollable alphabetized status tables and replaced raid-row actions with edit and trash icons.
- Reworked the attendance meter into a scrollable section and split history into Recent, Trades, and Exclusions tabs.
- Added the session-only `/lv guild_set <guild>` stored-guild override.

## 0.1.0 - 2026-08-01

- Created the standalone LootViewer addon project.
- Added guild-scoped raid attendance, loot, trade, and manual override tracking.
- Added local verification, packaging, deployment, and tag-based CurseForge release tooling.
