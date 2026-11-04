#!/usr/bin/env python3
"""
上传两套尺寸的 7 张截图；保留旧图直至所有新图处理完成并校验成功。

App Store Connect 的截图上传是三步协议，不能一次 PUT 完事：
  1. 建截图集（按显示类型分，这里只用 6.9 英寸）
  2. 建截图占位，拿到 uploadOperations（一组切片上传指令，含 offset/length/url/headers）
  3. 按切片 PUT 二进制，最后把 uploaded 置 true 让服务端校验

用法：
    export ASC_TOKEN=$(swift store/scripts/asc-token.swift ...)
    python3 store/scripts/upload-screenshots.py
"""

import hashlib
import time
from pathlib import Path
import json
import mimetypes
import os
import sys
import urllib.error
import urllib.request

TOKEN = os.environ.get("ASC_TOKEN")
if not TOKEN:
    sys.exit("缺少 ASC_TOKEN 环境变量")

BASE = "https://api.appstoreconnect.apple.com/v1"
VERSION_LOC_ID = "b6d9645b-f77c-43f1-b535-9dd35b626f38"
# 注意：API 的枚举里还没有 APP_IPHONE_69，最新一档只在网页端提供。
# 6.7 英寸这个槽位接受 1320×2868，正是 6.9 英寸的像素尺寸。
# 可以同时传一套 6.5 英寸（1284×2778）作为兜底，老设备商品页也就能出图。
DISPLAY_TYPE = os.environ.get("SCREENSHOT_DISPLAY_TYPE", "APP_IPHONE_67")
SHOT_DIR = os.environ.get("SCREENSHOT_DIR", "")

SHOTS = [(name, "") for name in [
    "01-home.png", "02-practice.png", "03-practice-settings.png",
    "04-meters.png", "05-appearance.png", "06-sounds.png", "07-favorites.png",
]]


def call(method, path, body=None, raw=None, url=None, headers=None):
    if url:
        # 分片上传走的是 S3 预签名 URL，鉴权已经在 query string 里了。
        # 再补一个 Authorization 头会让签名对不上，S3 直接回 400。
        req = urllib.request.Request(url, data=raw, method=method)
    else:
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(BASE + path, data=data, method=method)
        if data:
            req.add_header("Content-Type", "application/json")
        req.add_header("Authorization", "Bearer " + TOKEN)
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw_out = resp.read()
            return json.loads(raw_out) if raw_out and not url else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode()
        print(f"  ✗ {method} {path or '<upload>'} -> HTTP {e.code}")
        try:
            for err in json.loads(detail)["errors"]:
                print(f"    {err.get('code')}: {err.get('detail')}")
        except Exception:
            print("    上传服务返回非 JSON 错误，原截图保留")
        return None


def main():
    if os.environ.get("ASC_REPLACE_SCREENSHOTS") != "1":
        sys.exit("请在版本可编辑且获得替换授权后设置 ASC_REPLACE_SCREENSHOTS=1")
    base = os.path.join(os.path.dirname(__file__), "..", "screenshots")
    os.chdir(os.path.abspath(SHOT_DIR) if SHOT_DIR else base)
    backup = Path(os.environ["SCREENSHOT_BACKUP_DIR"]).resolve()
    if not backup.is_dir():
        sys.exit("缺少旧截图备份目录")

    # 截图集可能已存在（重跑脚本），先查再建，避免重复。
    existing = call(
        "GET",
        f"/appStoreVersionLocalizations/{VERSION_LOC_ID}/appScreenshotSets",
    )
    if existing is None or existing.get("links", {}).get("next"):
        sys.exit("读取截图集失败或结果不完整，停止操作")
    set_id = None
    if existing:
        for s in existing["data"]:
            if s["attributes"]["screenshotDisplayType"] == DISPLAY_TYPE:
                set_id = s["id"]
                print(f"复用已有截图集 {set_id}")

    if not set_id:
        r = call(
            "POST",
            "/appScreenshotSets",
            {
                "data": {
                    "type": "appScreenshotSets",
                    "attributes": {"screenshotDisplayType": DISPLAY_TYPE},
                    "relationships": {
                        "appStoreVersionLocalization": {
                            "data": {
                                "type": "appStoreVersionLocalizations",
                                "id": VERSION_LOC_ID,
                            }
                        }
                    },
                }
            },
        )
        if not r:
            sys.exit("建截图集失败")
        set_id = r["data"]["id"]
        print(f"新建截图集 {set_id}")

    # 在删除已有截图前验证所有新文件，确保失败时仍可用备份恢复。
    for name, _ in SHOTS:
        if not os.path.isfile(name) or os.path.getsize(name) == 0:
            sys.exit(f"截图缺失或为空：{name}")
    leftovers = call("GET", f"/appScreenshotSets/{set_id}/appScreenshots")
    if leftovers is None:
        sys.exit("读取现有截图失败，未删除任何截图")
    if leftovers.get("links", {}).get("next"):
        sys.exit("截图列表未完整读取，停止操作")
    old_shots = leftovers["data"]
    if len(old_shots) + len(SHOTS) > 10:
        sys.exit("空间不足以保留旧图并验证新图，请人工处理；未删除任何截图")
    for shot in old_shots:
        saved = backup / (shot['id'] + '.png')
        checksum = shot['attributes'].get('sourceFileChecksum')
        if not saved.is_file():
            sys.exit("旧截图备份缺失，停止替换")
        digest = hashlib.md5(saved.read_bytes()).hexdigest()
        if digest != checksum:
            # Apple CDN 会重新编码 PNG，原始上传 MD5 与下载文件可能不同。
            # 仅接受已与当前原生尺寸 CDN 图逐字节复核过的备份清单。
            manifest = backup / "verified-backups.json"
            verified = json.loads(manifest.read_text()).get(shot['id'], {}) if manifest.is_file() else {}
            asset = shot['attributes'].get('imageAsset', {})
            if (verified.get('sourceFileChecksum') != checksum
                    or verified.get('backupMD5') != digest
                    or verified.get('width') != asset.get('width')
                    or verified.get('height') != asset.get('height')):
                sys.exit("旧截图备份校验不符，停止替换")
    new_ids = []

    ok = 0
    for name, caption in SHOTS:
        size = os.path.getsize(name)
        print(f"→ {name}  {size/1024:.0f} KB")
        r = call(
            "POST",
            "/appScreenshots",
            {
                "data": {
                    "type": "appScreenshots",
                    "attributes": {"fileSize": size, "fileName": name},
                    "relationships": {
                        "appScreenshotSet": {
                            "data": {"type": "appScreenshotSets", "id": set_id}
                        }
                    },
                }
            },
        )
        if not r:
            sys.exit(f"创建截图失败：{name}")
        shot_id = r["data"]["id"]
        new_ids.append(shot_id)
        (backup / ("new-" + DISPLAY_TYPE + ".json")).write_text(json.dumps(new_ids))
        ops = r["data"]["attributes"].get("uploadOperations") or []
        if not ops:
            sys.exit(f"截图未返回上传指令：{name}")

        with open(name, "rb") as f:
            blob = f.read()
        for op in ops:
            start = op["offset"]
            chunk = blob[start:start + op["length"]]
            hdrs = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
            res = call(op["method"], None, raw=chunk, url=op["url"], headers=hdrs)
            if res is None:
                sys.exit(f"截图分片上传失败：{name}")

        r = call(
            "PATCH",
            f"/appScreenshots/{shot_id}",
            {
                "data": {
                    "type": "appScreenshots",
                    "id": shot_id,
                    "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(blob).hexdigest()},
                }
            },
        )
        if not r:
            sys.exit(f"截图提交失败：{name}")
        state = r["data"]["attributes"].get("assetDeliveryState", {}).get("state")
        if state in ("FAILED", "REJECTED"):
            sys.exit(f"截图处理失败：{name}，状态 {state}")
        print(f"  ✓ 已上传，状态 {state}")
        ok += 1

    # 所有新截图完成服务端处理后，才调整顺序并移除有备份的旧图。
    for shot_id in new_ids:
        for attempt in range(180):
            result = call("GET", f"/appScreenshots/{shot_id}")
            if result is None:
                sys.exit("新图校验请求失败，旧图保留")
            state = result['data']['attributes'].get('assetDeliveryState', {}).get('state')
            if state == "COMPLETE":
                break
            if state in ("FAILED", "REJECTED"):
                sys.exit("新图处理失败，旧图保留")
            time.sleep(2)
        else:
            sys.exit("新图处理尚未完成，旧图保留")
    order = new_ids + [shot['id'] for shot in old_shots]
    if call("PATCH", f"/appScreenshotSets/{set_id}/relationships/appScreenshots",
            {"data": [{"type": "appScreenshots", "id": value} for value in order]}) is None:
        sys.exit("排序失败，旧图保留")
    for shot in old_shots:
        if call("DELETE", f"/appScreenshots/{shot['id']}") is None:
            sys.exit("清理旧截图失败，新旧图均已备份")
    final = call("GET", f"/appScreenshotSets/{set_id}/appScreenshots")
    if final is None or [shot['id'] for shot in final['data']] != new_ids:
        sys.exit("最终截图顺序校验失败，请人工检查")
    print(f"完成 {ok}/{len(SHOTS)} 张，服务端处理及顺序校验通过")


if __name__ == "__main__":
    main()
