"""测试 btch-downloader 后端 API: https://backend1.tioo.eu.org/douyin?url=..."""

import urllib.request
import urllib.parse
import json

API_BASE = "https://backend1.tioo.eu.org"
PROXY = "http://127.0.0.1:7890"
TEST_URLS = [
    "https://v.douyin.com/1umiZBSTt84/",  # 1080p 测试链接
    "https://v.douyin.com/jjA4YdaFphk/",  # 4K 测试链接
]


def make_opener(use_proxy: bool):
    if use_proxy:
        proxy = urllib.request.ProxyHandler({"http": PROXY, "https": PROXY})
        return urllib.request.build_opener(proxy)
    return urllib.request.build_opener()


def fetch_api(video_url: str, opener) -> dict:
    api_url = f"{API_BASE}/douyin?url={urllib.parse.quote(video_url)}"
    req = urllib.request.Request(
        api_url,
        headers={
            "User-Agent": "btch-downloader/3.0",
            "Accept": "application/json",
        },
    )
    resp = opener.open(req, timeout=20)
    return json.loads(resp.read())


def print_result(data: dict):
    def show(obj, indent=2):
        prefix = " " * indent
        if isinstance(obj, dict):
            for k, v in obj.items():
                if isinstance(v, (dict, list)):
                    print(f"{prefix}{k}:")
                    show(v, indent + 2)
                else:
                    sv = str(v)
                    if len(sv) > 110:
                        sv = sv[:110] + "..."
                    print(f"{prefix}{k}: {sv}")
        elif isinstance(obj, list):
            for i, item in enumerate(obj):
                print(f"{prefix}[{i}]:")
                show(item, indent + 2)
                if i >= 4:
                    print(f"{prefix}... (共 {len(obj)} 项)")
                    break
        else:
            sv = str(obj)
            if len(sv) > 110:
                sv = sv[:110] + "..."
            print(f"{prefix}{sv}")

    show(data)


for video_url in TEST_URLS:
    print(f'\n{"="*60}')
    print(f"视频: {video_url}")
    for use_proxy, label in [(False, "直连"), (True, "代理")]:
        try:
            data = fetch_api(video_url, make_opener(use_proxy))
            print(f"[{label}] 成功:")
            print_result(data)
            break
        except Exception as e:
            print(f"[{label}] 失败: {e}")
