#!/usr/bin/env python3
"""Compile AgileStudio.lua into a Roblox Studio plugin .rbxmx.

Format matches the established AgileBot build:
- root <roblox version="4">
- bare <External>null</External> + <External>nil</External>
- direct <Item class="Script"> ... <ProtectedString name="Source"><![CDATA[...]]></ProtectedString>
- RunContext = 3 (Plugin), ScriptGuid present, SourceAssetId = -1
"""
import sys
from pathlib import Path

INPUT = Path(r"C:\Users\abdel\agilestudio\plugin\AgileStudio.lua")
OUTPUT = Path(r"C:\Users\abdel\agilestudio\plugin\AgileStudio.rbxmx")

LUA = INPUT.read_text(encoding="utf-8", newline="")

# guard against control chars outside nl/tab/cr (MSYS-safe)
bad = [c for c in LUA if ord(c) < 0x20 and c not in "\n\t\r"]
if bad:
    raise SystemExit("Source contains control chars: %r" % bad[:10])

SCRIPT_GUID = "RBXagilestudio0000000000000001"

xml = (
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<roblox version="4">\n'
    f'<Item class="Script" referent="RBXagilestudio">\n'
    '  <Properties>\n'
    '    <BinaryString name="AttributesSerialize"></BinaryString>\n'
    '    <Content name="LinkedSource"><null></null></Content>\n'
    '    <string name="Name">AgileStudio</string>\n'
    '    <bool name="Enabled">true</bool>\n'
    '    <Content name="Parent"><null></null></Content>\n'
    '    <ProtectedString name="Source"><![CDATA[' + LUA + ']]></ProtectedString>\n'
    '    <bool name="DefinesCapabilities">false</bool>\n'
    '    <int name="Capabilities">0</int>\n'
    '    <string name="ScriptGuid">' + SCRIPT_GUID + '</string>\n'
    '    <int name="SourceAssetId">-1</int>\n'
    '    <int name="RunContext">3</int>\n'
    '  </Properties>\n'
    '</Item>\n'
    '<External>nil</External>\n'
    '<External>null</External>\n'
    '</roblox>\n'
)

OUTPUT.write_text(xml, encoding="utf-8", newline="\n")
print(f"Successfully wrote {len(xml)} characters to {OUTPUT}")
