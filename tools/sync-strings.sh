#!/bin/zsh
# Extracts localizable strings with the Swift compiler and syncs them into the string catalog.
# Afterwards, fill in English for any keys listed as untranslated.
set -euo pipefail
cd "$(dirname "$0")/.."

CATALOG=Resources/Localization/Localizable.xcstrings
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

touch Sources/Efirometr/*.swift
swift build -c release -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$OUT" >/dev/null
xcrun xcstringstool sync "$CATALOG" --stringsdata "$OUT"/*.stringsdata

python3 -I - "$CATALOG" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
missing = [k for k, v in d["strings"].items()
           if v.get("extractionState") != "stale" and "en" not in v.get("localizations", {}) and k.strip()]
print(f"{len(d['strings'])} keys, {len(missing)} without English")
for k in missing:
    print("  " + json.dumps(k, ensure_ascii=False))
PY
