#!/usr/bin/env python3
"""
用 App Store Connect API 填写钢琴节拍器的上架元数据。

为什么不用网页填：截图上传要点十几次、年龄分级有三十多个开关，
手工点既慢又容易漏。这里一次性把能通过 API 写的字段全部写完，
只剩「提交审核」这一下留给人工确认。

用法：
    TOKEN=$(swift store/scripts/asc-token.swift <key> <keyId> <issuer> 900)
    ASC_TOKEN=$TOKEN python3 store/scripts/fill-metadata.py
"""

import json
import os
import sys
import urllib.error
import urllib.request

TOKEN = os.environ.get("ASC_TOKEN")
if not TOKEN:
    sys.exit("缺少 ASC_TOKEN 环境变量")

BASE = "https://api.appstoreconnect.apple.com/v1"

# 这个 App 的各项 id，均通过 API 查得，改 App 时需要重新取。
APP_ID = "6830036110"
VERSION_ID = "de1f88c4-1deb-4f5a-92a6-2c9b1536116d"
APP_INFO_ID = "8d124754-ae78-4258-9070-9bf48028b0c3"
APP_INFO_LOC_ID = "fba704cf-b75d-4000-8dbe-ba69c1820cd1"
VERSION_LOC_ID = "b6d9645b-f77c-43f1-b535-9dd35b626f38"

PRIVACY_URL = "https://xhuaustc.github.io/metronome-site/"
SUPPORT_URL = "https://xhuaustc.github.io/metronome-site/support.html"


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method)
    req.add_header("Authorization", "Bearer " + TOKEN)
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode()
        print(f"  ✗ {method} {path} -> HTTP {e.code}")
        try:
            for err in json.loads(detail)["errors"]:
                print(f"    {err.get('code')}: {err.get('title')} — {err.get('detail')}")
        except Exception:
            print("   ", detail[:500])
        return None


def patch(path, attributes, rtype):
    body = {"data": {"type": rtype, "id": path.rsplit("/", 1)[-1], "attributes": attributes}}
    return call("PATCH", path, body)


DESCRIPTION = """打开即用，节拍稳到不必信任它——只需要跟着它弹。

钢琴练习对节拍器的要求和排练室不一样：它得安静地待在谱架上，你抬眼就能看清现在是第几拍，伸手就能按下开始，中间不要有任何需要思考的地方。

【为稳定而生】
节拍由音频采样帧直接驱动，不是靠界面计时器。界面再怎么动画、系统再怎么忙，声音都不会被拖慢。每个拍点按固定帧数一次性算好，误差不会随练习时间累积。

【抬眼就能看清】
当前拍放大高亮，第一拍始终带圈标记。下方的大号数字直接告诉你第几拍、第几小节，不用自己数。6/8 拍会额外标出 3+3 的分组重音，一眼看出重音落在哪儿。

【听得清，不刺耳】
木质、电子、木鱼三种音色。强拍和普通拍用音高区分，而不是单纯加大音量，长时间练习耳朵不容易累。细分音量刻意压低，只做辅助，永远不抢主拍。

【该有的都有】
· 速度 30–240，可加减、可滑动、也可直接输入
· 拍号：2/4、3/4、4/4、3/8、6/8，6/8 按 3+3 分组
· 细分：无、二等、三等、四等
· 预备拍：可以给一小节预备，也可以关掉
· 重音：可以单独关闭，只要均匀的哒哒哒
· 屏幕常亮：练习期间自动保持亮屏，不用中途去点亮
· 播放中改速度立刻生效，声响不会重复也不会突然补一下
· 拍号和细分改动会等到下一小节才切换，不会打断你正在弹的这句
· 设置自动保存，重新打开是安静待命，不会自己响

【干净】
没有账号，不联网，不收集任何数据。所有设置只保存在你的手机上。

【关于中断】
来电、闹钟或其它应用抢占音频时，节拍器会立即停止并复位到第一拍，不会在你挂断电话的瞬间自己响起来。"""

PROMO = "节拍由音频采样帧直接驱动，不靠计时器。界面怎么动都不会拖慢声音，连续练习半小时也不会偏。打开就能用，抬眼就能看清第几拍。"

KEYWORDS = "节拍器,钢琴,节奏,练习,BPM,拍号,重音,细分,预备拍,稳定,metronome,piano"

REVIEW_NOTES = """本应用是一个节拍器。开启播放后，即使锁屏或切到其它应用，节拍声也会继续，
这是钢琴练习的实际需要（练习时需要看谱，屏幕会锁）。因此启用了 UIBackgroundModes = audio。

复现方式：
1. 打开应用，点击底部圆形按钮开始播放，会听到稳定的节拍声。
2. 按侧边电源键锁屏，节拍声继续，间隔不变。
3. 在锁屏状态下重新解锁回到应用，界面显示的拍点与声音始终一致。

应用完全离线运行，无账号、无网络请求、无内购、无广告。
若需要验证 6/8 拍的分组重音：在首页第二行选择 6/8，重音会落在第 1 拍和第 4 拍。"""


def main():
    print("1/6 版本本地化（描述 / 关键词 / 宣传文本 / 链接）")
    r = patch(
        f"/appStoreVersionLocalizations/{VERSION_LOC_ID}",
        {
            "description": DESCRIPTION,
            "keywords": KEYWORDS,
            "promotionalText": PROMO,
            "marketingUrl": PRIVACY_URL,
            "supportUrl": SUPPORT_URL,
        },
        "appStoreVersionLocalizations",
    )
    if r:
        print("  ✓ 已写入")

    print("2/6 App 信息本地化（副标题 / 隐私政策 URL）")
    r = patch(
        f"/appInfoLocalizations/{APP_INFO_LOC_ID}",
        {"subtitle": "专为钢琴练习设计的节拍器", "privacyPolicyUrl": PRIVACY_URL},
        "appInfoLocalizations",
    )
    if r:
        print("  ✓ 已写入")

    print("3/6 版权")
    r = patch(
        f"/appStoreVersions/{VERSION_ID}",
        {"copyright": "2026 Xiaohua Pan"},
        "appStoreVersions",
    )
    if r:
        print("  ✓ 已写入")

    print("4/6 年龄分级（全部无）")
    # 这两类字段类型不一样：一类是三档枚举 NONE/INFREQUENT_OR_MILD/
    # FREQUENT_OR_INTENSE，另一类就是布尔。混着传会 409。
    enum_fields = [
        "alcoholTobaccoOrDrugUseOrReferences", "contests", "gamblingSimulated",
        "gunsOrOtherWeapons", "medicalOrTreatmentInformation", "profanityOrCrudeHumor",
        "sexualContentGraphicAndNudity", "sexualContentOrNudity", "horrorOrFearThemes",
        "matureOrSuggestiveThemes", "violenceCartoonOrFantasy",
        "violenceRealisticProlongedGraphicOrSadistic", "violenceRealistic",
    ]
    bool_fields = [
        "advertising", "gambling", "healthOrWellnessTopics", "lootBox",
        "messagingAndChat", "parentalControls", "socialMedia", "socialMediaAgeRestricted",
        "unrestrictedWebAccess", "userGeneratedContent", "ageAssurance",
    ]
    body = {f: "NONE" for f in enum_fields}
    body.update({f: False for f in bool_fields})
    r = patch(
        f"/ageRatingDeclarations/{APP_INFO_ID}",
        body,
        "ageRatingDeclarations",
    )
    if r:
        print("  ✓ 已写入（系统算出 4+）")

    print("5/6 主分类 Music")
    cats = call("GET", "/appCategories?limit=200")
    music = None
    if cats:
        for c in cats["data"]:
            if c["id"] == "MUSIC":
                music = c["id"]
    if music:
        r = call(
            "PATCH",
            f"/appInfos/{APP_INFO_ID}",
            {
                "data": {
                    "type": "appInfos",
                    "id": APP_INFO_ID,
                    "relationships": {
                        "primaryCategory": {"data": {"type": "appCategories", "id": music}}
                    },
                }
            },
        )
        if r:
            print("  ✓ 已设为 音乐")
    else:
        print("  ✗ 没查到 MUSIC 分类 id")

    print("6/6 审核备注")
    r = call(
        "POST",
        "/appStoreReviewDetails",
        {
            "data": {
                "type": "appStoreReviewDetails",
                "attributes": {
                    "contactFirstName": "Xiaohua",
                    "contactLastName": "Pan",
                    "contactEmail": "mpan.dev@gmail.com",
                    "contactPhone": "+86 13800000000",
                    "demoAccountRequired": False,
                    "notes": REVIEW_NOTES,
                },
                "relationships": {
                    "appStoreVersion": {
                        "data": {"type": "appStoreVersions", "id": VERSION_ID}
                    }
                },
            }
        },
    )
    if r:
        print("  ✓ 已写入（电话号码需人工改成真实号码）")


if __name__ == "__main__":
    main()
