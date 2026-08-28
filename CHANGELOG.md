# Changelog

## 12.1.8 - 2026-08-28

1. Player searches now support clickable Name-Realm results and avoid accidental cross-realm duplicates.
2. Roster syncing now reliably selects the newest authoritative snapshot.
3. Roster editing is faster, with team, type, and role controls shown beside the selected player.
4. Roster and attendance lists now use consistent player cards with roster-status and alt icons.
5. Main-to-alt swaps retain the player's correct attendance status.
6. Attendance begins with a player's first guild raid, shows earlier raids in gray, and excludes Pugs from All Teams.
7. Loot can be assigned to Guild Bank, including historical BoEs with legacy data issues.
8. Raid details now show the night's loot, while loot Distribution excludes Pugs unless selected directly.

## 12.1.7 - 2026-08-25

1. Helpers now appear in their own roster category instead of under their primary combat role.

## 12.1.6 - 2026-08-25

1. Added a Roster page with raid-team tabs, role groups, cached player search, and authority-based editing.
2. Added Raider, Trial, and Helper roster types, multi-team assignments, guild roster syncing, and automatic no-shows for missing Raiders and Trials.
3. Redesigned Player Information with Main, Alt, and Pug tags, main-character search, roster controls, alt lists, attendance details, and a Class field only when needed.
4. Guild sync now compares raid lists, lets each player choose missing raids, retries lost transfers, and shows live progress.
5. Fixed restored or transferred raids losing linked attendance, loot, or trade records.
6. Fixed scheduled raid selection, empty raid records, and historical attendance duration, and added optional LFR tracking.
7. Trades now include only captured raid loot, and inactive guild-member attendance controls stay hidden.

## 12.1.5  August 19, 2026

1. Fixed duplicate loot and trade records.
2. Manual sync now shares raid nights, loot, trades, raid teams, and excluded items in both directions.
3. Added bonus loot tracking for raids and dungeons. Raid bonus loot has its own tab and does not count as regular raid loot.
4. Bonus loot is marked as personal, cannot be traded, and uses the correct reward difficulty.
5. Scheduled raids now start tracking inside the raid when most of the group belongs to your guild. You are asked to choose when more than one raid team is scheduled.
6. Dungeon Logging is on by default. The menu now separates raids and dungeons, and the season filter defaults to Current Season.
7. Warbound gear is ignored, and Curios are grouped by the winner's armor type.
8. The Roll column shows Need, Greed, or Transmog when known. Roll tooltips group each roll type, and raid history ignores zones outside the raid.

## 12.1.4 - 2026-08-17

- Fixed guild authority scanning to avoid the protected legacy Guild Information API by reading and caching the guild club description only from the out-of-combat Configuration panel.

## 12.1.3 - 2026-08-16

- Added guild-wide authority directives through Guild Information, with locked Authority and Trusted Rank controls, safe local fallbacks, validation warnings, and in-panel setup guidance.

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
