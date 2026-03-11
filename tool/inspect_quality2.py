"""
探查 playwm / playaddr 的 ratio 参数支持哪些清晰度。
并尝试通过抖音网页端 API（带 User-Agent 模拟）获取完整码率列表。

用法: python tool/inspect_quality2.py [videoId]
"""

import sys
import re
import json
import urllib.request
import urllib.parse
import http.client

UA_MOBILE = (
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) "
    "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
)

UA_PC = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/120.0.0.0 Safari/537.36"
)

VIDEO_ID = sys.argv[1] if len(sys.argv) > 1 else "7605478437712694528"
BASE_URL = (
    f"https://aweme.snssdk.com/aweme/v1/playwm/?"
    f"line=0&logo_name=aweme_diversion_search"
    f"&video_id=v0200fg10000d660fj7og65va5arbiu0"
)


def head_url(url, ua=UA_MOBILE):
    parsed = urllib.parse.urlparse(url)
    conn = (
        http.client.HTTPSConnection(parsed.netloc)
        if parsed.scheme == "https"
        else http.client.HTTPConnection(parsed.netloc)
    )
    path = parsed.path + ("?" + parsed.query if parsed.query else "")
    conn.request(
        "HEAD", path, headers={"User-Agent": ua, "Referer": "https://www.douyin.com/"}
    )
    resp = conn.getresponse()
    loc = resp.getheader("Location", "")
    conn.close()
    return resp.status, loc


def fetch_json(url, ua=UA_PC, extra_headers=None):
    headers = {"User-Agent": ua, "Referer": "https://www.douyin.com/"}
    if extra_headers:
        headers.update(extra_headers)
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            body = resp.read().decode("utf-8", errors="replace")
            return resp.status, body
    except urllib.error.HTTPError as e:
        return e.code, ""
    except Exception as e:
        return 0, str(e)


# ── 1. 测试 playwm 不同 ratio 参数 ─────────────────────────────
print("=" * 60)
print("测试 playwm 接口各清晰度 ratio 参数")
print("=" * 60)
base = (
    "https://aweme.snssdk.com/aweme/v1/playwm/"
    "?line=0&logo_name=aweme_diversion_search"
    "&video_id=v0200fg10000d660fj7og65va5arbiu0"
)

for ratio in ["360p", "480p", "540p", "720p", "1080p", "full_hd", "adapt"]:
    test_url = base + f"&ratio={ratio}"
    status, loc = head_url(test_url)
    print(f'  ratio={ratio:<10} -> [{status}] {loc[:100] if loc else "(no redirect)"}')

# ── 2. 测试 playaddr 改 ratio 参数 ─────────────────────────────
print()
base2 = (
    "https://aweme.snssdk.com/aweme/v1/play/"
    "?video_id=v0200fg10000d660fj7og65va5arbiu0"
    "&line=0"
)
print("=" * 60)
print("测试 play 接口(无水印)")
print("=" * 60)
for ratio in ["720p", "1080p", "full_hd"]:
    test_url = base2 + f"&ratio={ratio}"
    status, loc = head_url(test_url)
    print(f'  ratio={ratio:<10} -> [{status}] {loc[:100] if loc else "(no redirect)"}')

# ── 3. 调用抖音 Web API 获取完整视频信息 ────────────────────────
print()
print("=" * 60)
print("尝试 Web API (PC UA)")
print("=" * 60)
apis = [
    f"https://www.iesdouyin.com/web/api/v2/aweme/iteminfo/?item_ids={VIDEO_ID}",
    f"https://api.amemv.com/aweme/v1/web/aweme/detail/?aweme_id={VIDEO_ID}&aid=6383&version_name=23.5.0",
    f"https://www.douyin.com/aweme/v1/web/aweme/detail/?aweme_id={VIDEO_ID}&aid=6383",
]
for api in apis:
    status, body = fetch_json(api)
    print(f"\n  {api[:80]}")
    print(f"  状态: {status}, 响应长度: {len(body)}")
    if body.strip().startswith("{"):
        try:
            data = json.loads(body)
            # 找 bit_rate 或 video 字段
            if "aweme_detail" in data:
                v = data["aweme_detail"].get("video", {})
                br_list = v.get("bit_rate", [])
                print(f"  bit_rate 条目数: {len(br_list)}")
                for br in br_list:
                    gear = br.get("gear_name", br.get("quality_type", "?"))
                    w = br.get("play_addr", {}).get("width", "?")
                    h = br.get("play_addr", {}).get("height", "?")
                    urls = br.get("play_addr", {}).get("url_list", [])
                    print(
                        f'    gear={gear}, {w}x{h}, url={urls[0][:80] if urls else "N/A"}'
                    )
        except Exception as e:
            print(f"  JSON 解析失败: {e}")
            print(f"  前 200: {body[:200]}")
    else:
        print(f"  前 200: {body[:200]}")
