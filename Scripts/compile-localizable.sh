#!/bin/sh
# compile-localizable.sh
#
# Xcode's incremental String Catalog compile can leave some languages' 
# Localizable.strings incomplete (Tinika menu keys present in en/ru only).
# Recompile Localizable.xcstrings into the app bundle so every supported
# language gets the full catalog — required for in-app language switching
# via Bundle.main.localizedString / AppleLanguages.
#
# Runs after the Resources phase. Safe to re-run (overwrites .strings).

set -euo pipefail

SRC="${SRCROOT}/Lume/Localizable.xcstrings"
DEST="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"

if [ ! -f "$SRC" ]; then
  echo "error: missing String Catalog at $SRC" >&2
  exit 1
fi

if [ -z "${TARGET_BUILD_DIR:-}" ] || [ -z "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]; then
  echo "error: TARGET_BUILD_DIR / UNLOCALIZED_RESOURCES_FOLDER_PATH unset" >&2
  exit 1
fi

mkdir -p "$DEST"
XCSTRINGSTOOL=$(xcrun --find xcstringstool)
"$XCSTRINGSTOOL" compile "$SRC" --output-directory "$DEST" --serialization-format binary

echo "Compiled Localizable.xcstrings → $DEST (all catalog languages)"
