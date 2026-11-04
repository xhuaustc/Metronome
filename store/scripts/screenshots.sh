#!/bin/bash
# 从真实 Debug App 生成 7 张截图；使用专用模拟器避免改变日常测试数据。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
: "${SIM_UDID:?请指定截图专用模拟器 SIM_UDID}"
OUT="${SCREENSHOT_OUTPUT:-build/store-2026-11-04/screenshots}"
DD="${SCREENSHOT_DD:-build/review-dd}"
BUNDLE_ID="com.mpan.pianometronome"
mkdir -p "$OUT"
xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
xcrun simctl bootstatus "$SIM_UDID" -b >/dev/null
if [ "${SCREENSHOT_SKIP_BUILD:-0}" != "1" ]; then
  xcodebuild -project PianoMetronome.xcodeproj -scheme PianoMetronome \
    -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
    -configuration Debug -derivedDataPath "$DD" build CODE_SIGNING_ALLOWED=NO > "$OUT/build.log" 2>&1
fi
xcrun simctl status_bar "$SIM_UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
xcrun simctl install "$SIM_UDID" "$DD/Build/Products/Debug-iphonesimulator/PianoMetronome.app"
shoot() {
  local name="$1"; shift
  xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID" -screenshotMode "$@" >/dev/null
  sleep "${SCREENSHOT_SETTLE_SECONDS:-10}"
  xcrun simctl io "$SIM_UDID" screenshot --type=png "$OUT/$name"
}
shoot 01-home.png
shoot 02-practice.png -screenshotPractice
shoot 03-practice-settings.png -screenshotPracticeSettings
shoot 04-meters.png -screenshotMeter
shoot 05-appearance.png -screenshotSettings
shoot 06-sounds.png -screenshotSettings -screenshotSounds
shoot 07-favorites.png -screenshotFavorites
xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" >/dev/null

# App Store 不接受带 alpha 通道的截图。
swift store/scripts/export-screenshots.swift "$OUT"
