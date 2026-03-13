/**
 * 抖音分享页数据提取器（WebView 注入脚本）
 * 从 window._ROUTER_DATA 或 HTML 源码中提取视频/图文信息
 */

(() => {
  // ── 常量定义 ────────────────────────────────────────────────────────────────
  const CONSTANTS = {
    PLAY_BASE: "https://aweme.snssdk.com/aweme/v1/play/",
    URL_PATTERNS: {
      SHARE_ID: /v\.douyin\.com\/([A-Za-z0-9_-]+)/,
      LQEN_NEW: /tplv-dy-lqen-new/,
      WATERMARK: /-water/,
      AWEME_IMAGES: /tplv-dy-aweme-images/,
    },
    PRIORITY: {
      IMAGE_URLS: [
        {
          test: (u) => u.includes("tplv-dy-lqen-new") && !u.includes("-water"),
          name: "lqen-new",
        },
        {
          test: (u) => u.includes("tplv-dy-aweme-images"),
          name: "aweme-images",
        },
      ],
    },
  };

  // ── 错误类型 ────────────────────────────────────────────────────────────────
  const ErrorCode = {
    NO_ROUTER_DATA: "no_router_data",
    NO_ITEM: "no_item",
    EXTRACTION_FAILED: "extraction_failed",
  };

  // ── 工具函数 ────────────────────────────────────────────────────────────────

  /**
   * 安全获取嵌套对象属性
   * @param {any} obj - 源对象
   * @param {string} path - 点分隔路径，如 "a.b.c"
   * @param {any} defaultValue - 默认值
   */
  function get(obj, path, defaultValue = null) {
    const keys = path.split(".");
    let result = obj;
    for (const key of keys) {
      if (result == null || typeof result !== "object") return defaultValue;
      result = result[key];
    }
    return result ?? defaultValue;
  }

  /**
   * 安全获取数组元素
   * @param {any} obj
   * @param {string} path
   * @param {number} index
   */
  function getArrayItem(obj, path, index = 0) {
    const arr = get(obj, path);
    return Array.isArray(arr) ? arr[index] : null;
  }

  /**
   * 返回失败的 JSON 响应
   */
  function jsonFail(reason) {
    return JSON.stringify({ ok: false, reason });
  }

  /**
   * 解码 JSON 转义字符串（如 \u002F → /）
   */
  function decodeJsonEscapedString(value) {
    if (typeof value !== "string") return value;
    try {
      return JSON.parse(
        '"' + value.replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"',
      );
    } catch {
      return value;
    }
  }

  /**
   * 从 URL 中提取分享 ID
   * @param {string} url
   */
  function extractShareId(url) {
    const match = url.match(CONSTANTS.URL_PATTERNS.SHARE_ID);
    return match ? match[1] : null;
  }

  // ── 数据提取 ────────────────────────────────────────────────────────────────

  /**
   * 从 window 对象获取 _ROUTER_DATA
   */
  function getRouterDataFromWindow() {
    return get(window, "_ROUTER_DATA");
  }

  /**
   * 从 HTML 源码解析 _ROUTER_DATA
   */
  function parseRouterDataFromHtml() {
    const html = document.documentElement.innerHTML;
    const marker = "window._ROUTER_DATA = ";
    const start = html.indexOf(marker);
    if (start < 0) return null;

    const jsonStart = start + marker.length;
    let depth = 0;
    let inString = false;
    let escaped = false;

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

      if (ch === "{") depth++;
      else if (ch === "}") {
        depth--;
        if (depth === 0) {
          try {
            return JSON.parse(html.substring(jsonStart, i + 1));
          } catch {
            return null;
          }
        }
      }
    }
    return null;
  }

  /**
   * 获取 loaderData（优先从 window，其次从 HTML）
   */
  function getLoaderData() {
    const fromWindow = getRouterDataFromWindow();
    if (fromWindow?.loaderData) return fromWindow.loaderData;

    const fromHtml = parseRouterDataFromHtml();
    return fromHtml?.loaderData ?? null;
  }

  /**
   * 从 loaderData 中查找 aweme item
   */
  function findAwemeItem(loaderData) {
    const pageKey = Object.keys(loaderData).find((k) => k.includes("/page"));
    if (!pageKey) return null;

    return getArrayItem(loaderData[pageKey], "videoInfoRes.item_list");
  }

  // ── 结果构建 ────────────────────────────────────────────────────────────────

  /**
   * 从图片对象中选择最佳 URL
   * @param {object} image
   */
  function pickBestImageUrl(image) {
    const urls = get(image, "url_list", []);
    if (!Array.isArray(urls) || urls.length === 0) return null;

    // 按优先级匹配
    for (const { test } of CONSTANTS.PRIORITY.IMAGE_URLS) {
      const found = urls.find((u) => typeof u === "string" && test(u));
      if (found) return decodeJsonEscapedString(found);
    }

    return decodeJsonEscapedString(urls[0]);
  }

  /**
   * 提取图文作品的图片 URL 列表
   */
  function extractImageUrls(item) {
    const images = get(item, "images", []);
    return images.map(pickBestImageUrl).filter(Boolean);
  }

  /**
   * 提取视频清晰度列表
   */
  function extractVideoQualities(item) {
    const bitRates = get(item, "video.bit_rate", []);
    const qualities = {};

    // 从 bit_rate 数组提取多清晰度
    for (const br of bitRates) {
      const ratio = get(br, "gear_name", "").replace("gear_", "");
      const uri = get(br, "play_addr.uri");
      if (ratio && uri) {
        qualities[ratio] =
          `${CONSTANTS.PLAY_BASE}?video_id=${uri}&ratio=${ratio}&line=0`;
      }
    }

    if (Object.keys(qualities).length > 0) return qualities;

    // 降级：从 play_addr 猜测清晰度
    const uri = get(item, "video.play_addr.uri");
    const height = get(item, "video.height", 0);
    if (!uri) return qualities;

    const ratio = height >= 1080 ? "1080p" : "720p";
    qualities[ratio] =
      `${CONSTANTS.PLAY_BASE}?video_id=${uri}&ratio=${ratio}&line=0`;

    return qualities;
  }

  /**
   * 提取背景音乐 URL
   */
  function extractMusicUrl(item) {
    // 优先从 music.play_url 获取
    const musicUrl = getArrayItem(item, "music.play_url.url_list");
    if (musicUrl) return decodeJsonEscapedString(musicUrl);

    // 降级：检查 video.play_addr.uri 是否为 mp3
    const playUri = get(item, "video.play_addr.uri");
    if (typeof playUri === "string" && playUri.includes(".mp3")) {
      return decodeJsonEscapedString(playUri);
    }

    return null;
  }

  /**
   * 构建基础结果对象
   */
  function buildBaseResult(item, shareId) {
    const imageUrls = extractImageUrls(item);
    const coverUrl = getArrayItem(item, "video.cover.url_list");

    return {
      ok: true,
      id: String(get(item, "aweme_id", "")),
      title: String(get(item, "desc", "")),
      coverUrl: coverUrl ? decodeJsonEscapedString(coverUrl) : null,
      width: get(item, "video.width"),
      height: get(item, "video.height"),
      shareId,
      type: imageUrls.length > 0 ? "image" : "video",
      imageUrls,
      musicTitle: get(item, "music.title"),
      musicUrl: null,
      qualityUrls: {},
    };
  }

  // ── 主流程 ──────────────────────────────────────────────────────────────────

  function runExtract() {
    const inputUrl = location.href;
    const shareId = extractShareId(inputUrl);

    // 获取 loaderData
    const loaderData = getLoaderData();
    if (!loaderData) return jsonFail(ErrorCode.NO_ROUTER_DATA);

    // 查找 aweme item
    const item = findAwemeItem(loaderData);
    if (!item) return jsonFail(ErrorCode.NO_ITEM);

    // 构建结果
    const result = buildBaseResult(item, shareId);

    // 根据类型填充额外数据
    if (result.type === "image") {
      result.musicUrl = extractMusicUrl(item);
    } else {
      result.qualityUrls = extractVideoQualities(item);
    }

    return JSON.stringify(result);
  }

  // 执行并返回结果
  try {
    return runExtract();
  } catch (e) {
    return jsonFail(`${ErrorCode.EXTRACTION_FAILED}: ${e.message}`);
  }
})();
