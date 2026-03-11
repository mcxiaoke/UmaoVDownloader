"""
探查抖音分享页 HTML 中所有视频清晰度字段。
用法: python tool/inspect_quality.py <抖音短链接>
"""

import sys
import re
import json
import urllib.request
import urllib.parse

UA = (
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) "
    "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
)


def follow_redirects(url, max_hops=8):
    for _ in range(max_hops):
        req = urllib.request.Request(url, headers={"User-Agent": UA}, method="GET")
        opener = urllib.request.build_opener(urllib.request.HTTPRedirectHandler())
        opener.addhandler = lambda *a: None  # 不用这个
        try:
            # 手动跟随，不使用自动重定向
            import http.client

            parsed = urllib.parse.urlparse(url)
            conn = (
                http.client.HTTPSConnection(parsed.netloc)
                if parsed.scheme == "https"
                else http.client.HTTPConnection(parsed.netloc)
            )
            path = parsed.path + ("?" + parsed.query if parsed.query else "")
            conn.request(
                "GET",
                path,
                headers={"User-Agent": UA, "Referer": "https://www.douyin.com/"},
            )
            resp = conn.getresponse()
            conn.close()
            if resp.status in (301, 302, 303, 307, 308):
                location = resp.getheader("Location")
                if not location:
                    break
                url = urllib.parse.urljoin(url, location)
                print(f"  -> [{resp.status}] {url[:100]}")
            else:
                print(f"  OK [{resp.status}] {url[:100]}")
                break
        except Exception as e:
            print(f"  Error: {e}")
            break
    return url


def fetch_html(url):
    req = urllib.request.Request(
        url, headers={"User-Agent": UA, "Referer": "https://www.douyin.com/"}
    )
    with urllib.request.urlopen(req) as resp:
        return resp.read().decode("utf-8", errors="replace")


def decode_json_str(s):
    """解码 JSON 字符串转义"""
    try:
        return json.loads(f'"{s}"')
    except Exception:
        return s.replace("\\u002F", "/").replace("\\/", "/")


def main():
    url = sys.argv[1] if len(sys.argv) > 1 else "https://v.douyin.com/dSw-yoH9MhI/"
    print(f"短链接: {url}")

    # 1. 跟随重定向拿 videoId
    final_url = follow_redirects(url)
    m = re.search(r"/(?:video|note)/(\d+)", final_url)
    if not m:
        print("ERROR: 无法提取 videoId")
        return
    video_id = m.group(1)
    print(f"videoId: {video_id}\n")

    # 2. 抓取分享页 HTML
    share_url = f"https://www.iesdouyin.com/share/video/{video_id}/"
    print(f"抓取分享页: {share_url}")
    html = fetch_html(share_url)
    print(f"HTML 长度: {len(html)}\n")

    # 3. 找出所有 play_addr* 字段
    # 匹配: "play_addr_xxx": {"uri":"...", "url_list":["..."], ...}
    addr_pattern = re.compile(
        r'"(play_addr[^"]*?)"\s*:\s*(\{[^{}]{0,2000}?\})', re.DOTALL
    )

    print("=" * 60)
    print("所有 play_addr 相关字段:")
    print("=" * 60)
    found = {}
    for match in addr_pattern.finditer(html):
        field_name = match.group(1)
        obj_str = match.group(2)
        # 提取 url_list
        url_m = re.search(r'"url_list"\s*:\s*\[("(?:[^"\\]|\\.)*")', obj_str)
        # 提取 width / height
        w_m = re.search(r'"width"\s*:\s*(\d+)', obj_str)
        h_m = re.search(r'"height"\s*:\s*(\d+)', obj_str)
        width = w_m.group(1) if w_m else "?"
        height = h_m.group(1) if h_m else "?"

        if url_m:
            raw_url = url_m.group(1).strip('"')
            decoded_url = decode_json_str(raw_url)
            if field_name not in found:
                found[field_name] = (decoded_url, width, height)

    for name, (url, w, h) in found.items():
        print(f"\n[{name}]")
        print(f"  分辨率: {w} x {h}")
        print(f"  URL   : {url[:120]}")

    # 4. 找 bit_rate 数组（多码率信息）
    print("\n" + "=" * 60)
    print("bit_rate / quality 码率列表:")
    print("=" * 60)
    # 找 "bit_rate":[...] 数组
    br_m = re.search(r'"bit_rate"\s*:\s*(\[[\s\S]{0,10000}?\])\s*,\s*"', html)
    if br_m:
        try:
            br_list = json.loads(br_m.group(1))
            for item in br_list:
                gear = item.get("gear_name", item.get("quality_type", "?"))
                bitrate = item.get("bit_rate", "?")
                play = item.get("play_addr", {})
                urls = play.get("url_list", [])
                w = play.get("width", "?")
                h = play.get("height", "?")
                first_url = decode_json_str(urls[0]) if urls else "N/A"
                print(f"\n  gear: {gear}, bitrate: {bitrate}, {w}x{h}")
                print(f"  url : {first_url[:120]}")
        except Exception as e:
            print(f"  解析 bit_rate 失败: {e}")
            print(f"  原始内容前 500: {br_m.group(1)[:500]}")
    else:
        print("  未找到 bit_rate 数组")

    # 5. 找所有 ratio 字符串（720p/1080p 等标记）
    print("\n" + "=" * 60)
    print("ratio 字段（清晰度标记）:")
    print("=" * 60)
    ratios = re.findall(r'"ratio"\s*:\s*"([^"]+)"', html)
    print("  ", set(ratios))


if __name__ == "__main__":
    main()
