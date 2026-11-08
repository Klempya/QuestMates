#!/bin/sh
# Build the distributable addon zip: dist/QuestMates-v<version>.zip
# The version is read from QuestMates/QuestMates.toc (## Version: X.Y.Z),
# so the package name always matches the addon's reported version.
# Usage: sh tools/make_dist.sh     (run from anywhere)
set -e
cd "$(dirname "$0")/.."

VER=$(sed -n 's/^## Version:[[:space:]]*//p' QuestMates/QuestMates.toc | tr -d '[:space:]')
if [ -z "$VER" ]; then
  echo "could not read ## Version: from QuestMates/QuestMates.toc" >&2
  exit 1
fi
OUT="dist/QuestMates-v${VER}.zip"
mkdir -p dist
rm -f "$OUT"

# zip only the addon folder, with a fixed order for reproducibility
python3 - "$VER" "$OUT" <<'EOF'
import sys, zipfile, os
ver, out = sys.argv[1], sys.argv[2]
files = sorted(
    os.path.join(r, f)
    for r, d, fs in os.walk("QuestMates") for f in fs
)
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for p in files:
        z.write(p, p)  # archive path = QuestMates/...
print("built " + out + " (v" + ver + ")")
for p in files:
    print("  " + p)
EOF
