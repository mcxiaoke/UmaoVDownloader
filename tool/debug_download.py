"""测试 btch-downloader 后端 API 对抖音链接的解析结果"""

import urllib.request
import urllib.error
import re, json

video_id = "7593728529112616207"
share_url = f"https://www.iesdouyin.com/share/video/{video_id}/"
mobile_ua = (
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) "
    "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
)

req = urllib.request.Request(
    share_url, headers={"User-Agent": mobile_ua, "Referer": "https://www.douyin.com/"}
)
resp = urllib.request.urlopen(req, timeout=15)
html = resp.read().decode("utf-8", errors="replace")
print(f"页面大小: {len(html)} bytes")

# 找 play_addr 周边 JSON
idx = html.find("play_addr")
if idx >= 0:
    snippet = html[max(0, idx - 5) : idx + 300]
    print(f"\nplay_addr 周边:\n{snippet}\n")

# 找 bit_rate_video_stream 或 width x height
for keyword in ["bit_rate", "width", "height", "2160", "4k", "4K", "ratio"]:
    pos = html.find(keyword)
    if pos >= 0:
        print(f'  "{keyword}" at {pos}: ...{html[max(0,pos-10):pos+80]}...')

# 测试该视频 2160p 是否能请求
pc_ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36 Edg/145.0.0.0"
file_id = "v0d00fg10000d5h5eufog65iqen0dfb0"

print("\n=== 测试 2160p/4k ===")


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, hdrs, newurl):
        return None


opener = urllib.request.build_opener(NoRedirect())

for ratio in ["2160p", "4k", "1080p", "720p"]:
    url = f"https://aweme.snssdk.com/aweme/v1/play/?video_id={file_id}&ratio={ratio}&line=0"
    req2 = urllib.request.Request(url, headers={"User-Agent": pc_ua})
    cdn_url = None
    try:
        r = opener.open(req2, timeout=8)
        print(f"  [{ratio}] 直接200")
        r.close()
        continue
    except urllib.error.HTTPError as e:
        cdn_url = e.headers.get("Location")
        if not cdn_url:
            print(f"  [{ratio}] {e.code} 无Location")
            continue

    req3 = urllib.request.Request(cdn_url, headers={"User-Agent": pc_ua})
    try:
        r2 = opener.open(req3, timeout=8)
        print(f'  [{ratio}] -> CDN 200, CL={r2.headers.get("Content-Length")}')
        r2.close()
    except urllib.error.HTTPError as e2:
        print(f"  [{ratio}] -> CDN {e2.code}  url_end=...{cdn_url[-40:]}")
    except Exception as ex:
        print(f"  [{ratio}] error: {ex}")
