#!/bin/bash
#
# 重新生成 App Store 截图（6.9 英寸，1320 × 2868）。
#
# 依赖 DEBUG 构建里的 -screenshotMode 启动参数，该代码在 Release 中不参与编译。
# 换了界面就重跑一次，避免手搓截图。
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

UDID="${SIM_UDID:-E7CA1814-2A2C-4EDB-84B2-C839FED16B81}"   # iPhone 17 Pro Max
BUNDLE_ID="com.mpan.pianometronome"
DD="build/dd"
OUT="store/screenshots"

mkdir -p "$OUT"

echo "==> 构建模拟器版本"
xcodebuild -project PianoMetronome.xcodeproj \
  -scheme PianoMetronome \
  -destination "platform=iOS Simulator,id=$UDID" \
  -configuration Debug \
  -derivedDataPath "$DD" \
  build CODE_SIGNING_ALLOWED=NO \
  OTHER_SWIFT_FLAGS='$(inherited) -Xfrontend -disable-sandbox' \
  >/dev/null

echo "==> 启动模拟器"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null

# 状态栏统一成 9:41 + 满电满格，这是 App Store 截图的惯例。
xcrun simctl status_bar "$UDID" override \
  --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3

xcrun simctl install "$UDID" "$DD/Build/Products/Debug-iphonesimulator/PianoMetronome.app"

shoot() {          # shoot <文件名> <启动参数…>
  local name="$1"; shift
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE_ID" -screenshotMode "$@" >/dev/null
  sleep 4
  xcrun simctl io "$UDID" screenshot --type=png "$OUT/$name"
}

echo "==> 截图"
shoot 01-idle.png
shoot 02-playing.png -screenshotPlaying
shoot 03-settings.png -screenshotSettings

for f in "$OUT"/*.png; do
  printf '  %-22s %s\n' "$(basename "$f")" "$(sips -g pixelWidth -g pixelHeight "$f" | awk '/pixel/{printf "%s ", $2}')"
done
