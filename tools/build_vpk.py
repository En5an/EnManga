#!/usr/bin/env python3
"""Package the app/ folder into an installable VPK.

    python3 tools/build_vpk.py            -> dist/EnManga-Beta-v1.0.vpk
    python3 tools/build_vpk.py 1.1        -> dist/EnManga-Beta-v1.1.vpk

A VPK is a plain ZIP of the app folder (eboot.bin, sce_sys/, Lua files, assets).
The version shown inside the app is APP_VERSION in app/index.lua and APP_VER in
app/sce_sys/param.sfo; change those yourself before a release.
"""
import os, sys, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "app")
version = sys.argv[1] if len(sys.argv) > 1 else "1.0"
out_dir = os.path.join(ROOT, "dist")
os.makedirs(out_dir, exist_ok=True)
out = os.path.join(out_dir, f"EnManga-Beta-v{version}.vpk")

skip = {".DS_Store", "Thumbs.db", "desktop.ini"}
count = 0
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for folder, dirs, files in os.walk(APP):
        dirs.sort()
        for name in sorted(files):
            if name in skip or name.startswith("._"):
                continue
            path = os.path.join(folder, name)
            z.write(path, os.path.relpath(path, APP).replace(os.sep, "/"))
            count += 1
    z.write(os.path.join(ROOT, "LICENSE"), "LICENSE")
    count += 1
print(f"{out}  ({count} files, {os.path.getsize(out) / 1048576:.1f} MB)")
