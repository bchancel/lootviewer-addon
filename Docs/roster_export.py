"""Decode LootViewer's LVR1 roster export strings with the Python standard library.

Copy this file into your external site's codebase. Invalid exports raise ValueError.
"""

import base64
import binascii
import re
import zlib

MAX_BYTES = 250_000
TYPES = {"raider", "trial", "helper", "social"}
ROLES = {"", "tank", "healer", "melee", "ranged"}


def _clean(value: str, limit: int) -> bool:
    return (
        bool(value)
        and len(value.encode("utf-8")) <= limit
        and value == value.strip()
        and not any(ord(char) < 32 or ord(char) == 127 or char == "|" for char in value)
    )


def decode_roster_export(export_string: str) -> list[dict[str, str]]:
    """Return team, player, type, primary_role, secondary_role for every assignment.

    Player names include their realm; roles/types use the lowercase addon values.
    An unassigned role is an empty string. A valid empty roster returns [].
    The embedded guild key is checked for validity but omitted from returned rows.
    """
    if not isinstance(export_string, str) or len(export_string) > MAX_BYTES + 4096:
        raise ValueError("Roster string is too large or is not a string")
    value = re.sub(r"[ \t\n\r\f\v]", "", export_string)
    if len(value) > MAX_BYTES:
        raise ValueError("Roster string is too large")
    match = re.fullmatch(r"LVR1:([A-Za-z0-9+/=]+):([0-9a-fA-F]{8})", value)
    if not match:
        raise ValueError("Expected a LootViewer LVR1 roster string")
    encoded, expected = match.groups()
    try:
        raw = base64.b64decode(encoded, validate=True)
        if base64.b64encode(raw).decode("ascii") != encoded:
            raise ValueError("Noncanonical base64")
        if zlib.adler32(raw) != int(expected, 16):
            raise ValueError("Checksum mismatch")
        lines = raw.decode("utf-8").split("\n")
    except (binascii.Error, UnicodeDecodeError, ValueError) as exc:
        raise ValueError("Roster string is damaged or incomplete") from exc
    header = lines[0].split("\t")
    if len(header) != 5:
        raise ValueError("Invalid roster header")
    guild, team, count, revision, author = header
    slug = re.sub(r"[^a-z0-9-]", "", re.sub(r"\s+", "-", team.lower())).strip("-")
    if (
        not _clean(guild, 256)
        or not _clean(team, 96)
        or slug == "pugs"
        or not re.fullmatch(r"[0-9]{1,4}", count)
        or int(count) > 1000
        or int(count) != len(lines) - 1
        or not re.fullmatch(r"[0-9]{1,16}", revision)
        or int(revision) > 9007199254740991
        or not _clean(author, 128)
        or not re.fullmatch(r"[^\s-]+-[^\s]+", author)
    ):
        raise ValueError("Invalid roster header or player count")
    rows = []
    seen = set()
    for line in lines[1:]:
        fields = line.split("\t")
        if len(fields) != 4:
            raise ValueError("Invalid roster player row")
        player, roster_type, primary, secondary = fields
        if (
            not _clean(player, 128)
            or not re.fullmatch(r"[^\s-]+-[^\s]+", player)
            or player.lower() in seen
            or roster_type not in TYPES
            or primary not in ROLES
            or secondary not in ROLES
            or (secondary and primary == secondary)
        ):
            raise ValueError("Invalid or duplicate player in roster string")
        seen.add(player.lower())
        rows.append(
            {
                "team": team,
                "player": player,
                "type": roster_type,
                "primary_role": primary,
                "secondary_role": secondary,
            }
        )
    return rows
