"""Python/Lua format compatibility and malformed export regression tests."""

import base64
from pathlib import Path
import sys
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[2]
sys.dont_write_bytecode = True
sys.path.insert(0, str(ROOT / "Docs"))
sys.path.insert(0, str(ROOT / ".build" / "test-deps"))
from roster_export import decode_roster_export
from lupa.lua51 import LuaRuntime


def wrap(raw: str) -> str:
    lines = raw.split("\n")
    lines[0] += "\t1\tOfficer-Sargeras"
    raw = "\n".join(lines)
    payload = raw.encode("utf-8")
    return f"LVR1:{base64.b64encode(payload).decode()}:{zlib.adler32(payload):08x}"


class RosterExportTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lua = LuaRuntime(unpack_returned_tuples=True)
        cls.lua.execute((ROOT / "Docs" / "Tests" / "RosterTransfer.lua").read_text(encoding="utf-8"))

    def test_real_lua_export(self):
        rows = decode_roster_export(self.lua.globals().ROSTER_TRANSFER_FIXTURE)
        self.assertEqual(len(rows), 4)
        mage = next(row for row in rows if row["player"].startswith("Méémage"))
        self.assertEqual(mage, {"team": "Main", "player": "Méémage-Sargeras", "type": "raider",
                               "primary_role": "ranged", "secondary_role": "healer"})
        self.assertEqual(decode_roster_export(self.lua.globals().ROSTER_TRANSFER_EMPTY_FIXTURE), [])

    def test_wrapped_copy_paste(self):
        value = self.lua.globals().ROSTER_TRANSFER_FIXTURE
        self.assertEqual(decode_roster_export(" \r\n" + value[:30] + "\n" + value[30:]), decode_roster_export(value))

    def test_rejects_malformed_exports(self):
        malformed = [
            "", "LVR2:AAAA:00000000", wrap("g\tMain\t1"),
            wrap("g\tMain\t1\nP-Realm\traider\ttank\ttank"),
            wrap("g\tMain\t1\nP-Realm\tinvalid\tranged\t"),
            wrap("g\tMain\t1\nP-Realm\traider\tinvalid\t"),
            wrap("g\tMain\t2\nP-Realm\traider\ttank\t\np-realm\ttrial\tmelee\t"),
            wrap("g\tpugs\t0"), wrap("g\tMain\t1\nNoRealm\traider\ttank\t"),
            wrap("g\tMain\t1001"), "x" * 260000,
            self.lua.globals().ROSTER_TRANSFER_FIXTURE[:-1] + "z",
        ]
        for value in malformed:
            with self.subTest(value=value[:60]), self.assertRaises(ValueError):
                decode_roster_export(value)


if __name__ == "__main__":
    unittest.main()
