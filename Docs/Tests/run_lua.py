"""Run Lua 5.1 regression tests: python Docs/Tests/run_lua.py.

Requires lupa (python -m pip install --target .build/test-deps lupa).
Test dependencies stay outside the addon and release packages.
"""
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / ".build" / "test-deps"))
from lupa.lua51 import LuaRuntime

os.chdir(ROOT)
lua = LuaRuntime(unpack_returned_tuples=True)
compile_lua = lua.eval("function(path) assert(loadfile(path)) end")
sources = [ROOT / "LootViewer.lua"]
for folder in ("Core", "Events", "UI", "Options"):
    sources.extend((ROOT / folder).glob("*.lua"))
for path in sources:
    compile_lua(str(path))
print(f"Lua 5.1 syntax passed for {len(sources)} runtime files.", flush=True)
lua.execute((ROOT / "Docs" / "Tests" / "RosterSync.lua").read_text(encoding="utf-8"))
