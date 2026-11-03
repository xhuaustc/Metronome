#!/bin/bash
#
# 一键打包并上传到 App Store Connect。
#
# 需要一个 App Store Connect API 密钥（.p8）。获取方式见
# store/上架清单.md 第 2 步。密钥只需要配置一次。
#
# 用法：
#   export ASC_KEY_ID=XXXXXXXXXX
#   export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#   export ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8
#   ./store/scripts/release.sh
#
# 只打包不上传：
#   ./store/scripts/release.sh --no-upload
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

PROJECT="PianoMetronome.xcodeproj"
SCHEME="PianoMetronome"
TEAM_ID="3BVFM34328"
ARCHIVE="build/PianoMetronome.xcarchive"
EXPORT_DIR="build/export"
EXPORT_OPTIONS="Support/ExportOptions.plist"

UPLOAD=1
case "${1:-}" in
  --no-upload) UPLOAD=0 ;;
  --help|-h) sed -n '2,20p' "$0"; exit 0 ;;
esac

# ── 前置检查 ───────────────────────────────────────────────────────────
if [ "$UPLOAD" = "1" ]; then
  : "${ASC_KEY_ID:?未设置 ASC_KEY_ID}"
  : "${ASC_ISSUER_ID:?未设置 ASC_ISSUER_ID}"
  : "${ASC_KEY_PATH:?未设置 ASC_KEY_PATH}"
  ASC_KEY_PATH="${ASC_KEY_PATH/#\~/$HOME}"
  [ -f "$ASC_KEY_PATH" ] || { echo "找不到密钥文件：$ASC_KEY_PATH"; exit 1; }
  AUTH_ARGS=(-authenticationKeyPath "$ASC_KEY_PATH"
             -authenticationKeyID "$ASC_KEY_ID"
             -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi

# 这台机器上编译器给宏插件套 sandbox-exec 会被拒，必须关掉前端沙箱。
SWIFT_FLAGS='$(inherited) -Xfrontend -disable-sandbox'

# macOS 自带 bash 3.2，空数组展开需要下面这种写法才不会报 unbound variable。
EXTRA_ARGS=()
if [ "$UPLOAD" = "1" ]; then
  EXTRA_ARGS=(-allowProvisioningUpdates "${AUTH_ARGS[@]}")
fi

echo "==> 清理上次产物"
rm -rf "$ARCHIVE" "$EXPORT_DIR"
mkdir -p build

echo "==> 归档（Release）"
ARCHIVE_CMD=(xcodebuild archive
  -project "$PROJECT"
  -scheme "$SCHEME"
  -configuration Release
  -destination 'generic/platform=iOS'
  -archivePath "$ARCHIVE"
  DEVELOPMENT_TEAM="$TEAM_ID"
  CODE_SIGN_STYLE=Automatic
  OTHER_SWIFT_FLAGS="$SWIFT_FLAGS")
if [ ${#EXTRA_ARGS[@]} -gt 0 ]; then ARCHIVE_CMD+=("${EXTRA_ARGS[@]}"); fi

"${ARCHIVE_CMD[@]}" 2>&1 | grep -E "error:|ARCHIVE (SUCCEEDED|FAILED)" || true

[ -d "$ARCHIVE" ] || { echo "归档失败"; exit 1; }

echo "==> 导出 App Store 包"
if [ "$UPLOAD" = "1" ]; then
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    "${AUTH_ARGS[@]}"
else
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    DEVELOPMENT_TEAM="$TEAM_ID" || {
      echo
      echo "导出失败。若提示 No Accounts，说明命令行读不到 Xcode 里登录的账号。"
      echo "两种办法："
      echo "  1) 提供 ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH 后重跑本脚本；"
      echo "  2) 用 Xcode 图形界面：open \"$ARCHIVE\""
      exit 1
    }
fi

IPA=$(find "$EXPORT_DIR" -name "*.ipa" | head -1)
[ -n "$IPA" ] || { echo "没有找到 .ipa"; exit 1; }
echo "    $(du -h "$IPA" | cut -f1)  $IPA"

if [ "$UPLOAD" = "1" ]; then
  echo "==> 校验"
  xcrun altool --validate-app -f "$IPA" -t ios \
    --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

  echo "==> 上传"
  xcrun altool --upload-app -f "$IPA" -t ios \
    --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

  echo
  echo "上传完成。接下来去 App Store Connect 绑定构建版本并提交审核："
  echo "  https://appstoreconnect.apple.com/apps"
else
  echo
  echo "已完成打包（未上传）。产物：$IPA"
fi
