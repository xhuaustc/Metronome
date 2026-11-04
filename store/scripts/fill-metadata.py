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


DESCRIPTION = '知拍节拍器，陪你从慢练开始，稳稳跟上每一拍。\n\n为钢琴练习打造，也适合吉他、小提琴等乐器的日常节奏训练。打开应用，调好速度，一键开始。清晰的拍点、随节拍摆动的机械摆针，让练习更直观。\n\n【从慢练到目标速度】\n设置起始速度和目标速度，按指定小节数自动提速。遇到难点时保持当前速度，或退回一档，准备好再继续。到达目标后保持播放，让你专注手上的练习。\n\n【你需要的节奏，随手可调】\n· 20–400 BPM，支持直接输入、加减按钮和拖动配重调速\n· 14 种拍号，覆盖常用拍子、复拍子及 5 拍、7 拍\n· 复拍子可按大拍或小拍计速，不规则拍子可选重音分组\n· 二、三、四等分细分提示，配合重音练习节奏\n· 可选一小节预备拍，给双手留好准备时间\n\n【常练的节奏，一键找回】\n最多收藏 5 组常用设置，保存速度、拍号、计拍方式、重音分组和细分。练不同曲目时快速切换，也可长按覆盖更新。\n\n【看得清，也听得清】\n大字号速度、清晰拍点与机械摆针，方便放在谱架上查看。四种外观与四种机械敲击音色独立选择，音色支持试听，找到适合自己的练习搭配。\n\n【让练习少一点打断】\n支持屏幕常亮、锁屏与后台播放。来电或系统音频中断时停止，之后由你手动重新开始。设置自动保存在本机，再次打开即可接着使用。\n\n【简单，安心】\n无广告、无内购、无需注册。完全离线运行，不收集个人数据，不申请麦克风权限。\n\n从今天的一次慢练开始，把节拍练稳。'

PROMO = '打开就练，稳稳跟上每一拍。按小节渐进提速，吃力时保持或退回一档。支持 20–400 BPM、14 种拍号与常用节奏收藏，外观和音色自由搭配。离线使用，无广告、无内购。'

KEYWORDS = '节拍器,钢琴,节奏,练习,BPM,拍号,重音,细分,预备拍,稳定,metronome,piano'

REVIEW_NOTES = '本应用是一个节拍器。开启播放后，即使锁屏或切到其它应用，节拍声也会继续，\n这是钢琴练习的实际需要（练习时需要看谱，屏幕会锁）。因此启用了 UIBackgroundModes = audio。\n\n复现方式：\n1. 打开应用，点击首页「开始」按钮开始播放，会听到稳定的节拍声。\n2. 按侧边电源键锁屏，节拍声继续，间隔不变。\n3. 重新解锁回到应用，查看界面拍点和小节。\n\n应用完全离线运行，无账号、无网络请求、无内购、无广告。\n拍号选择器支持 14 种拍号；复拍子可选择大拍或小拍计速。\n\n本次构建新增渐进提速练习：在首页进入「渐进提速」，启用并配置起始速度、目标速度、增量和每档小节数，返回首页后开始。播放中可保持、继续或退回一档；到达目标后保持。训练在音频时钟上推进，锁屏后仍可继续。\n\n设置中的外观和声音分别保存，左右滑动首页机身仅切换外观。声音可逐项试听，无需开始播放。'


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
        {'name': '知拍节拍器 - 钢琴练习与节奏训练', 'subtitle': '从慢练到熟练，按小节自动提速', "privacyPolicyUrl": PRIVACY_URL},
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
