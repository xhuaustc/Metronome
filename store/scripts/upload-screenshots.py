#!/usr/bin/env python3
"""
把 store/screenshots 下的 6.9 英寸截图上传到 App Store Connect。

App Store Connect 的截图上传是三步协议，不能一次 PUT 完事：
  1. 建截图集（按显示类型分，这里只用 6.9 英寸）
  2. 建截图占位，拿到 uploadOperations（一组切片上传指令，含 offset/length/url/headers）
  3. 按切片 PUT 二进制，最后把 uploaded 置 true 让服务端校验

用法：
    export ASC_TOKEN=$(swift store/scripts/asc-token.swift ...)
    python3 store/scripts/upload-screenshots.py
"""

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
# 6.7 英寸这个槽位同时接受 1290×2796 和 1320×2868，我们的截图是后者。
DISPLAY_TYPE = "APP_IPHONE_67"

SHOTS = [
    ("01-idle.png", "打开即可开始：大号拍点与当前速度一目了然"),
    ("02-playing.png", "播放中：当前拍放大高亮，第一拍带圈标记"),
    ("03-settings.png", "三种音色、细分与预备拍，都在一页里"),
]


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
        with urllib.request.urlopen(req) as resp:
            raw_out = resp.read()
            return json.loads(raw_out) if raw_out and not url else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode()
        print(f"  ✗ {method} {path or url} -> HTTP {e.code}")
        try:
            for err in json.loads(detail)["errors"]:
                print(f"    {err.get('code')}: {err.get('detail')}")
        except Exception:
            print("   ", detail[:400])
        return None


def main():
    os.chdir(os.path.join(os.path.dirname(__file__), "..", "screenshots"))

    # 截图集可能已存在（重跑脚本），先查再建，避免重复。
    existing = call(
        "GET",
        f"/appStoreVersionLocalizations/{VERSION_LOC_ID}/appScreenshotSets",
    )
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

    # 上一次失败会留下「已建占位但没传完」的截图，同一个位置塞两张会冲突。
    leftovers = call("GET", f"/appScreenshotSets/{set_id}/appScreenshots")
    if leftovers:
        for s in leftovers["data"]:
            call("DELETE", f"/appScreenshots/{s['id']}")
            print(f"  清掉残留占位 {s['id']}")

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
            continue
        shot_id = r["data"]["id"]
        ops = r["data"]["attributes"].get("uploadOperations") or []

        with open(name, "rb") as f:
            blob = f.read()
        for op in ops:
            start = op["offset"]
            chunk = blob[start:start + op["length"]]
            hdrs = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
            res = call(op["method"], None, raw=chunk, url=op["url"], headers=hdrs)
            if res is None:
                break

        r = call(
            "PATCH",
            f"/appScreenshots/{shot_id}",
            {
                "data": {
                    "type": "appScreenshots",
                    "id": shot_id,
                    "attributes": {"uploaded": True},
                }
            },
        )
        if r:
            state = r["data"]["attributes"].get("assetDeliveryState", {}).get("state")
            print(f"  ✓ 已上传，状态 {state}")
            ok += 1

    print(f"\n完成 {ok}/{len(SHOTS)} 张")


if __name__ == "__main__":
    main()
