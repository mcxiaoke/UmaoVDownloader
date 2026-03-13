(() => {
  const PLAY_BASE = "https://aweme.snssdk.com/aweme/v1/play/";

  function jsonFail(reason) {
    return JSON.stringify({ ok: false, reason });
  }

  function decodeJsonEscapedString(value) {
    if (typeof value !== "string") return value;
    try {
      return JSON.parse(
        '"' + value.replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"',
      );
    } catch (_) {
      return value;
    }
  }

  function extractShareId(url) {
    const shareMatch = url.match(/v\.douyin\.com\/([A-Za-z0-9_-]+)/);
    return shareMatch ? shareMatch[1] : null;
  }

  function getLoaderData() {
    return window._ROUTER_DATA && window._ROUTER_DATA.loaderData;
  }

  function findAwemeItem(loaderData) {
    for (const key in loaderData) {
      if (!Object.prototype.hasOwnProperty.call(loaderData, key)) continue;
      if (!String(key).includes("/page")) continue;

      const candidate =
        loaderData[key] &&
        loaderData[key].videoInfoRes &&
        loaderData[key].videoInfoRes.item_list &&
        loaderData[key].videoInfoRes.item_list[0];
      if (candidate) return candidate;
    }
    return null;
  }

  function pickImageUrl(image) {
    const urls = image && Array.isArray(image.url_list) ? image.url_list : [];

    const lq = urls.find(
      (u) =>
        typeof u === "string" &&
        u.includes("tplv-dy-lqen-new") &&
        !u.includes("-water"),
    );
    if (lq) return decodeJsonEscapedString(lq);

    const aweme = urls.find(
      (u) => typeof u === "string" && u.includes("tplv-dy-aweme-images"),
    );
    if (aweme) return decodeJsonEscapedString(aweme);

    return urls[0] ? decodeJsonEscapedString(urls[0]) : null;
  }

  function extractImageUrls(item) {
    const images = Array.isArray(item.images) ? item.images : [];
    return images.map(pickImageUrl).filter(Boolean);
  }

  function buildBaseResult(item, shareId, imageUrls) {
    return {
      ok: true,
      id: String(item.aweme_id || ""),
      title: String(item.desc || ""),
      coverUrl:
        item.video &&
        item.video.cover &&
        Array.isArray(item.video.cover.url_list)
          ? decodeJsonEscapedString(item.video.cover.url_list[0])
          : null,
      width: item.video && item.video.width != null ? item.video.width : null,
      height:
        item.video && item.video.height != null ? item.video.height : null,
      shareId,
      type: imageUrls.length > 0 ? "image" : "video",
      imageUrls,
      musicTitle:
        item.music && item.music.title ? String(item.music.title) : null,
      musicUrl: null,
      qualityUrls: {},
    };
  }

  function fillImageMusic(item, out) {
    const musicList =
      item.music &&
      item.music.play_url &&
      Array.isArray(item.music.play_url.url_list)
        ? item.music.play_url.url_list
        : [];

    if (musicList.length > 0) {
      out.musicUrl = decodeJsonEscapedString(musicList[0]);
      return;
    }

    const playUri =
      item.video && item.video.play_addr && item.video.play_addr.uri;
    if (typeof playUri === "string" && playUri.includes(".mp3")) {
      out.musicUrl = decodeJsonEscapedString(playUri);
    }
  }

  function fillVideoQualities(item, out) {
    const bitRates =
      item.video && Array.isArray(item.video.bit_rate)
        ? item.video.bit_rate
        : [];

    for (const br of bitRates) {
      const ratio =
        br && br.gear_name ? String(br.gear_name).replace("gear_", "") : "";
      const uri = br && br.play_addr ? br.play_addr.uri : null;
      if (!ratio || !uri) continue;
      out.qualityUrls[ratio] =
        `${PLAY_BASE}?video_id=${uri}&ratio=${ratio}&line=0`;
    }

    if (Object.keys(out.qualityUrls).length > 0) return;

    const uri =
      item.video && item.video.play_addr ? item.video.play_addr.uri : null;
    const h = item.video && item.video.height ? Number(item.video.height) : 0;
    if (!uri) return;

    const ratio = h >= 1080 ? "1080p" : "720p";
    out.qualityUrls[ratio] =
      `${PLAY_BASE}?video_id=${uri}&ratio=${ratio}&line=0`;
  }

  function extractFromHtml() {
    const html = document.documentElement.innerHTML;
    const marker = "window._ROUTER_DATA = ";
    const start = html.indexOf(marker);
    if (start < 0) return null;

    const jsonStart = start + marker.length;
    let depth = 0;
    let inString = false;
    let escaped = false;
    let end = -1;

    for (let i = jsonStart; i < html.length; i++) {
      const ch = html[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch === "\\") {
        escaped = true;
        continue;
      }
      if (ch === '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;
      if (ch === "{") {
        depth++;
      } else if (ch === "}") {
        depth--;
        if (depth === 0) {
          end = i;
          break;
        }
      }
    }

    if (end <= jsonStart) return null;

    try {
      const raw = html.substring(jsonStart, end + 1);
      return JSON.parse(raw);
    } catch (e) {
      return null;
    }
  }

  function runExtract() {
    const inputUrl = location.href;
    const shareId = extractShareId(inputUrl);

    // 尝试从 window._ROUTER_DATA 获取
    let loaderData = getLoaderData();

    // 如果失败，尝试从 HTML 中解析
    if (!loaderData) {
      const fromHtml = extractFromHtml();
      if (fromHtml && fromHtml.loaderData) {
        loaderData = fromHtml.loaderData;
      }
    }

    if (!loaderData) return jsonFail("no_router_data");

    const item = findAwemeItem(loaderData);
    if (!item) return jsonFail("no_item");

    const imageUrls = extractImageUrls(item);
    const out = buildBaseResult(item, shareId, imageUrls);

    if (out.type === "image") {
      fillImageMusic(item, out);
      return JSON.stringify(out);
    }

    fillVideoQualities(item, out);
    return JSON.stringify(out);
  }

  try {
    return runExtract();
  } catch (e) {
    return jsonFail(String(e));
  }
})();
