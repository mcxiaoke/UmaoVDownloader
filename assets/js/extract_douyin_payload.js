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
    // 类型映射：aweme_type -> 媒体类型
    MEDIA_TYPES: {
      // 视频类型
      video: [0, 4, 51, 55, 58, 61, 109, 201],
      // 图文类型
      image: [2, 68, 150],
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

  // ── 类型检测 ────────────────────────────────────────────────────────────────

  /**
   * 智能检测作品类型
   * 优先使用 aweme_type，未知时综合以下特征：
   * - images 字段是否存在且非空
   * - video.play_addr.uri 格式（URL 开头 vs 视频 ID）
   * - video.duration（图文为 0 或很小，视频有实际时长）
   */
  function detectMediaType(item) {
    // 1. 优先使用 aweme_type 判断
    const awemeType = get(item, "aweme_type");
    if (awemeType != null) {
      const typeNum = Number(awemeType);
      if (CONSTANTS.MEDIA_TYPES.image.includes(typeNum)) {
        return "image";
      }
      if (CONSTANTS.MEDIA_TYPES.video.includes(typeNum)) {
        return "video";
      }
    }

    // 2. 兜底：综合特征判断
    const images = get(item, "images");
    const video = get(item, "video");

    // 特征 1：images 字段存在且非空 → 图文
    if (Array.isArray(images) && images.length > 0) {
      return "image";
    }

    // 特征 2：video.play_addr.uri 以 http 开头 → 图文（实况图/音频）
    const playUri = get(video, "play_addr.uri");
    if (typeof playUri === "string" && playUri.startsWith("http")) {
      return "image";
    }

    // 特征 3：video.duration 为 0 或不存在，且 images 为空 → 可能是图文
    const duration = get(video, "duration");
    if ((duration == null || duration === 0) && !Array.isArray(images)) {
      const bitRate = get(video, "bit_rate");
      if (!Array.isArray(bitRate) || bitRate.length === 0) {
        return "image";
      }
    }

    // 默认判定为视频
    return "video";
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
   * 提取视频 URL（最高质量）
   */
  function extractVideoUrl(item) {
    const bitRates = get(item, "video.bit_rate", []);

    // 从 bit_rate 数组提取最高质量（第一个通常是最高质量）
    if (bitRates.length > 0) {
      const br = bitRates[0];
      const uri = get(br, "play_addr.uri");
      const ratio = get(br, "gear_name", "").replace("gear_", "") || "1080p";
      if (uri) {
        return `${CONSTANTS.PLAY_BASE}?video_id=${uri}&ratio=${ratio}&line=0`;
      }
    }

    // 降级：从 play_addr 构建 URL
    const uri = get(item, "video.play_addr.uri");
    const height = get(item, "video.height", 0);
    if (!uri) return null;

    const ratio = height >= 1080 ? "1080p" : "720p";
    return `${CONSTANTS.PLAY_BASE}?video_id=${uri}&ratio=${ratio}&line=0`;
  }

  /**
   * 提取背景音乐 URL
   * 
   * 注意：抖音图文作品有两种存储音乐的方式：
   * 1. music.play_url.url_list - 正常的 MP3 直链
   * 2. video.play_addr.uri - 图文作品的音频实际存储在这里，是一个完整的 HTTP URL（没有 .mp3 后缀）
   * 
   * 不能用 .includes(".mp3") 来判断，因为第二种情况的 URL 没有 .mp3 后缀，
   * 但实际 Content-Type 是 audio/mp4。用 startsWith("http") 可以覆盖这两种情况。
   * 
   * 普通视频的 video.play_addr.uri 是 ID 字符串（如 v0200fg10000c...），会被过滤掉。
   */
  function extractMusicUrl(item) {
    // 优先从 music.play_url 获取
    const musicUrl = getArrayItem(item, "music.play_url.url_list");
    if (musicUrl) return decodeJsonEscapedString(musicUrl);

    // 降级：检查 video.play_addr.uri 是否为合法 URL（图文作品的音频）
    const playUri = get(item, "video.play_addr.uri");
    if (typeof playUri === "string" && playUri.startsWith("http")) {
      return decodeJsonEscapedString(playUri);
    }

    return null;
  }

  /**
   * 提取图文作品的图片列表（含 thumb 和 full）
   */
  function extractImageList(item) {
    const images = get(item, "images", []);
    return images.map((image, idx) => {
      const urls = get(image, "url_list", []);
      if (!Array.isArray(urls) || urls.length === 0) return null;

      // 找大图（无水印优先）：tplv-dy-lqen-new 且无 water
      const full =
        urls.find(
          (u) => u.includes("tplv-dy-lqen-new") && !u.includes("-water"),
        ) ??
        urls.find((u) => u.includes("tplv-dy-aweme-images")) ??
        urls[0] ??
        null;

      // 找缩略图：带 200x200 或类似的尺寸标记
      const thumb =
        urls.find((u) => u.includes("200x200") || u.includes("thumb")) ??
        urls.find((u) => u.includes("tplv-dy-aweme-images")) ??
        full;

      if (!full) {
        console.log(`[DY WebView] 图片 ${idx + 1}: 无可用 URL`);
        return null;
      }

      return { thumb: thumb || full, full: decodeJsonEscapedString(full) };
    }).filter(Boolean);
  }

  /**
   * 提取视频质量信息
   */
  function extractVideoQuality(item) {
    const bitRates = get(item, "video.bit_rate", []);
    if (bitRates.length === 0) return null;

    const best = bitRates[0];
    return {
      ratio: get(best, "gear_name", "").replace("gear_", "") || "1080p",
      size: get(best, "data_size"),
      bitrate: get(best, "bit_rate"),
      width: get(best, "play_addr.width"),
      height: get(best, "play_addr.height"),
    };
  }

  /**
   * 构建基础结果对象 - 对齐 backend 字段
   */
  function buildBaseResult(item, shareId) {
    const mediaType = detectMediaType(item);
    const imageList = mediaType === "image" ? extractImageList(item) : [];
    const imageUrls = imageList.map(i => i.full);
    const imageThumbs = imageList.map(i => i.thumb);
    const coverUrl = getArrayItem(item, "video.cover.url_list");
    const awemeId = String(get(item, "aweme_id", ""));

    // 提取视频质量信息
    const qualityInfo = mediaType === "video" ? extractVideoQuality(item) : null;
    const duration = get(item, "video.duration");

    return {
      ok: true,
      platform: "douyin",
      id: awemeId,
      itemId: awemeId,
      title: String(get(item, "desc", "")),
      coverUrl: coverUrl ? decodeJsonEscapedString(coverUrl) : null,
      width: get(item, "video.width"),
      height: get(item, "video.height"),
      shareId,
      type: mediaType,
      imageList,
      imageUrls,
      imageThumbs,
      imageCount: imageUrls.length,
      musicTitle: get(item, "music.title"),
      musicUrl: null,
      videoUrl: null,
      quality: qualityInfo?.ratio || null,
      videoSize: qualityInfo?.size || null,
      videoBitrate: qualityInfo?.bitrate || null,
      duration: duration ? Math.round(duration / 1000) : null,
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
      result.videoUrl = extractVideoUrl(item);
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
