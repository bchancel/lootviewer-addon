# Roster transfers and external imports

The Roster page has a Roster Transfer cell beside Invite Team. It remains available
when the invite window is closed. Pasted imports and exports require the same
permission as editing the current guild's roster. Send To also requires roster
publishing authority. Guild members with read-only roster access can accept an
incoming roster. The confirmation appears even when Blizzard has not loaded the
sender's rank. After acceptance, the addon verifies the publisher using Blizzard
member data, waiting up to 20 seconds for it to load, then checks again before
importing. Incoming transfers retain the publisher's roster revision.

Export copies the selected team's entire roster, regardless of the invite filter.
Import replaces the team with the exported name (case-insensitive), creating it if
missing. A confirmation shows the team and player count before any changes. Empty
rosters clear that team's assignments. Other teams and existing schedules are kept.
Exports belong to one guild and cannot be imported into another guild.

Send To accepts a character on your realm (`meemage`), a full name
(`meemage-sargeras`), `group`, or `raid`. `group` uses your current party or raid;
instance groups use the instance addon channel. Each eligible LootViewer recipient
gets an Accept/Decline popup. No roster changes occur before acceptance and receipt
of the complete, valid transfer. Recipients need this version of LootViewer.
Offers expire after 60 seconds; accepted transfers have up to 10 minutes to finish.
The sender sees when the recipient displays the confirmation or is verifying
permissions. Rejected offers and missing receipt acknowledgments include a status
message, so an old addon version or missing guild data does not fail silently.
The confirmation appears above the LootViewer window. If Blizzard cannot open
another popup, the sender receives an explicit rejection asking for a retry.

## Python decoder

Copy `Docs/roster_export.py` into the external site. It uses only the standard library.

```python
from roster_export import decode_roster_export

rows = decode_roster_export(export_string)
# [{"team": "Main", "player": "Meemage-Sargeras", "type": "raider",
#   "primary_role": "ranged", "secondary_role": ""}, ...]

# If the site expects five-element lists:
values = [[r["team"], r["player"], r["type"], r["primary_role"], r["secondary_role"]]
          for r in rows]
```

Types are `raider`, `trial`, `helper`, or `social`. Roles are `tank`, `healer`,
`melee`, `ranged`, or an empty string. Player names include the realm. Invalid,
truncated, unsupported, and duplicate-player exports raise `ValueError`.

## LVR1 wire format

`LVR1:<standard base64>:<eight hexadecimal Adler-32 digits>`

The base64 contains UTF-8 text. Its first line is
`guild_key<TAB>team_name<TAB>player_count<TAB>roster_revision<TAB>revision_author`.
The last two fields preserve automatic sync ordering and are omitted from Python's
returned rows. Subsequent lines contain
`player<TAB>type<TAB>primary_role<TAB>secondary_role`. Lines are separated by LF,
without a trailing LF. Missing roles are empty fields. Rows are sorted by the
UTF-8 player name bytes when exported. The checksum covers the decoded bytes;
it detects corruption and is not an authentication signature. ASCII whitespace
around or inside the export string is ignored for copy/paste convenience.
