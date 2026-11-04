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
RELEASE_DIR="${RELEASE_DIR:-build/releases/$(date +%Y%m%d-%H%M%S)}"
ARCHIVE="$RELEASE_DIR/PianoMetronome.xcarchive"
EXPORT_DIR="$RELEASE_DIR/export"
EXPORT_OPTIONS="Support/ExportOptions.plist"
SIGN_IDENTITY="iPhone Distribution: Xiaohua Pan (3BVFM34328)"
PROFILE_NAME="PianoMetronome AppStore"

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
  export API_PRIVATE_KEYS_DIR="$(dirname "$ASC_KEY_PATH")"
  AUTH_ARGS=(-authenticationKeyPath "$ASC_KEY_PATH"
             -authenticationKeyID "$ASC_KEY_ID"
             -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi

# 这台机器上编译器给宏插件套 sandbox-exec 会被拒，必须关掉前端沙箱。
SWIFT_FLAGS='$(inherited) -Xfrontend -disable-sandbox'

# 手动签名不需要 -allowProvisioningUpdates；带上它反而会去碰云签名，
# 在这个 Individual 团队上直接报权限错误。

# 每次发布写入独立目录，不覆盖或删除已有归档。
[ ! -e "$ARCHIVE" ] && [ ! -e "$EXPORT_DIR" ] || { echo "产物目录已存在，请使用新的 RELEASE_DIR"; exit 1; }
mkdir -p "$RELEASE_DIR"

echo "==> 归档（Release）"
# Individual 团队拿不到 cloud-managed distribution certificate，自动签名
# 在 exportArchive 阶段必定失败。统一走手动签名：描述文件由 make-profile.sh
# 生成并安装，这里只引用它的名字。
ARCHIVE_CMD=(xcodebuild archive
  -project "$PROJECT"
  -scheme "$SCHEME"
  -configuration Release
  -destination 'generic/platform=iOS'
  -archivePath "$ARCHIVE"
  DEVELOPMENT_TEAM="$TEAM_ID"
  CODE_SIGN_STYLE=Manual
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY"
  PROVISIONING_PROFILE_SPECIFIER="$PROFILE_NAME"
  OTHER_SWIFT_FLAGS="$SWIFT_FLAGS")

"${ARCHIVE_CMD[@]}" > "$RELEASE_DIR/archive.log" 2>&1 || {
  tail -60 "$RELEASE_DIR/archive.log"
  exit 1
}

[ -d "$ARCHIVE" ] || { echo "归档失败"; exit 1; }

echo "==> 导出 App Store 包"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  DEVELOPMENT_TEAM="$TEAM_ID" || {
    echo
    echo "导出失败。手动签名下最常见的原因是描述文件没装或名字对不上："
    echo "  描述文件：$PROFILE_NAME"
    echo "  重装：./store/scripts/make-profile.sh"
    exit 1
  }

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
