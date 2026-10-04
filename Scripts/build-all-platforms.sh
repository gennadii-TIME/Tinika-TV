#!/usr/bin/env bash
# Build Tinika TV (Lume scheme) for every first-release Apple platform.
# Requires macOS + Xcode 26.4+ and the matching simulator runtimes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SPM="${TINIKA_SPM_DIR:-$HOME/Library/Developer/Lume-SharedSPM}"
DD="${TINIKA_DERIVED_DATA:-/tmp/tinika-dd-all}"
LOG_DIR="${TINIKA_BUILD_LOG_DIR:-$ROOT/docs/build-logs}"
mkdir -p "$LOG_DIR" "$SPM"

# Optional local signing overrides (needed on Mac hosts without upstream team CHG45F8MCL).
# Example: TINIKA_DEVELOPMENT_TEAM=7Q4F885549 ./Scripts/build-all-platforms.sh
EXTRA_BUILD_FLAGS=()
if [[ -n "${TINIKA_DEVELOPMENT_TEAM:-}" ]]; then
  EXTRA_BUILD_FLAGS+=(
    -allowProvisioningUpdates
    "DEVELOPMENT_TEAM=${TINIKA_DEVELOPMENT_TEAM}"
    CODE_SIGN_STYLE=Automatic
  )
fi

# CloudKit is disabled in Lume.entitlements / LumeApp.isCloudKitSyncConfigured until
# a Tinika TV iCloud container is registered. No temporary entitlements override needed.
xcodebuild -version | tee "$LOG_DIR/xcode-version.txt"

# Prefer device names present on current Xcode; override via TINIKA_*_DEST.
destinations=(
  "${TINIKA_TVOS_DEST:-platform=tvOS Simulator,name=Apple TV 4K (3rd generation)}"
  "${TINIKA_IPHONE_DEST:-platform=iOS Simulator,name=iPhone 17 Pro}"
  "${TINIKA_IPAD_DEST:-platform=iOS Simulator,name=iPad Pro 13-inch (M5)}"
  "${TINIKA_MACOS_DEST:-platform=macOS}"
)

names=(tvOS iPhone iPad macOS)
failed=0

for i in "${!destinations[@]}"; do
  name="${names[$i]}"
  dest="${destinations[$i]}"
  log="$LOG_DIR/build-${name}.log"
  echo "=== Building $name ($dest) ===" | tee "$log"
  if xcodebuild build \
      -project Lume.xcodeproj \
      -scheme Lume \
      -destination "$dest" \
      -clonedSourcePackagesDirPath "$SPM" \
      -derivedDataPath "$DD" \
      ${EXTRA_BUILD_FLAGS[@]+"${EXTRA_BUILD_FLAGS[@]}"} \
      >>"$log" 2>&1; then
    echo "OK $name" | tee -a "$log"
  else
    echo "FAIL $name (see $log)" | tee -a "$log"
    failed=$((failed + 1))
  fi
done

echo "=== Summary ==="
echo "Failed platforms: $failed"
echo "Logs: $LOG_DIR"
exit "$failed"
