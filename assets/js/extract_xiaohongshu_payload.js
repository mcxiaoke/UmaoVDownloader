/**
 * 小红书分享页数据提取器（WebView 注入脚本）
 * 从 window.__INITIAL_STATE__ 中提取视频/图文信息
 */

(() => {
  // ── 常量定义 ────────────────────────────────────────────────────────────────
  const CONSTANTS = {
    CDN_DOMAINS: [
      "sns-img-hw.xhscdn.com",
      "sns-video-hw.xhscdn.com",
      "sns-video-hs.xhscdn.com",
      "sns-video-al.xhscdn.com",
    ],
  };

  // ── 错误类型 ────────────────────────────────────────────────────────────────
  const ErrorCode = {
    NO_INITIAL_STATE: "no_initial_state",
    NO_NOTE_DATA: "no_note_data",
    EXTRACTION_FAILED: "extraction_failed",
  };

  // ── 工具函数 ────────────────────────────────────────────────────────────────

  /**
   * 安全获取嵌套对象属性
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
   * 返回失败的 JSON 响应
   */
  function jsonFail(reason) {
    return JSON.stringify({ ok: false, reason });
  }

  /**
   * 返回成功的 JSON 响应
   */
  function jsonSuccess(data) {
    return JSON.stringify({ ok: true, ...data });
  }

  // ── 数据提取 ────────────────────────────────────────────────────────────────

  /**
   * 从 window 对象获取 __INITIAL_STATE__
   */
  function getInitialStateFromWindow() {
    return get(window, "__INITIAL_STATE__");
  }

  /**
   * 从 HTML 源码解析 __INITIAL_STATE__
   * 小红书数据包含 undefined，需要用 new Function 解析
   */
  function parseInitialStateFromHtml() {
    const html = document.documentElement.innerHTML;
    const marker = /window\.__INITIAL_STATE__\s*=\s*/;
    const match = html.match(marker);
    if (!match) return null;

    const start = match.index + match[0].length;
    let depth = 0;
    let inString = false;
    let escaped = false;

    for (let i = start; i < html.length; i++) {
      const ch = html[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch === "\\") {
        escaped = true;
        continue;
      }
      if (ch === '"' && html[i - 1] !== "\\") {
        inString = !inString;
        continue;
      }
      if (inString) continue;

      if (ch === "{" || ch === "[") depth++;
      else if (ch === "}" || ch === "]") {
        depth--;
        if (depth === 0) {
          const jsonStr = html.substring(start, i + 1);
          try {
            // 小红书数据包含 undefined，标准 JSON.parse 不支持
            return new Function("return " + jsonStr)();
          } catch {
            return null;
          }
        }
      }
    }
    return null;
  }

  /**
   * 获取初始状态数据
   */
  function getInitialState() {
    const fromWindow = getInitialStateFromWindow();
    if (fromWindow) return fromWindow;
    return parseInitialStateFromHtml();
  }

  /**
   * 从 __INITIAL_STATE__ 中提取笔记数据
   */
  function extractNoteData(data) {
    // 新结构：noteData.data.noteData
    const note = get(data, "noteData.data.noteData");
    if (note) return note;

    // 备用路径
    const noteMap = get(data, "note.noteDetailMap");
    if (noteMap) {
      const keys = Object.keys(noteMap);
      if (keys.length > 0) return noteMap[keys[0]];
    }

    return null;
  }

  // ── 结果构建 ────────────────────────────────────────────────────────────────

  /**
   * 从 URL 中提取 fileId 和路径前缀
   */
  function extractFileIdFromUrl(url) {
    if (!url) return null;
    try {
      const urlObj = new URL(url);
      const pathParts = urlObj.pathname.split("/").filter(Boolean);
      const lastPart = pathParts[pathParts.length - 1];
      const fileId = lastPart.split("!")[0];
      if (fileId && /^[a-z0-9]+$/i.test(fileId)) {
        const prefix = pathParts.includes("notes_uhdr") ? "notes_uhdr/" : "";
        return { fileId, prefix };
      }
    } catch {
      // 解析失败
    }
    return null;
  }

  /**
   * 提取封面图 URL
   */
  function extractCoverUrl(note) {
    const candidates = [
      get(note, "cover.urlDefault"),
      get(note, "cover.url"),
      get(note, "cover.infoList.0.url"),
      get(note, "imageList.0.urlDefault"),
      get(note, "imageList.0.url"),
      get(note, "imageList.0.infoList.0.url"),
      get(note, "video.media.videoFirstFrame.url"),
    ];

    for (const url of candidates) {
      if (url) return url;
    }
    return null;
  }

  /**
   * 提取图片 URL 列表（无水印高清图）
   */
  function extractImageUrls(note) {
    const imageList = get(note, "imageList", []);
    if (!Array.isArray(imageList)) return [];

    return imageList
      .map((img) => {
        // 优先使用 infoList 中的 URL 提取 fileId
        const infoList = get(img, "infoList", []);
        if (infoList.length > 0) {
          const best = infoList[infoList.length - 1];
          if (best.url) {
            const result = extractFileIdFromUrl(best.url);
            if (result) {
              return `https://sns-img-hw.xhscdn.com/${result.prefix}${result.fileId}?imageView2/2/w/0/format/jpg`;
            }
            return best.url;
          }
        }

        // 备用：traceId
        const traceId = img.traceId || get(img, "infoList.0.imageScene.traceId");
        if (traceId) {
          return `https://sns-img-hw.xhscdn.com/${traceId}?imageView2/2/w/0/format/jpg`;
        }

        // 最后备用
        return img.urlDefault || img.url || null;
      })
      .filter(Boolean);
  }

  /**
   * 提取视频信息
   */
  function extractVideoInfo(note) {
    const video = get(note, "video");
    if (!video) return null;

    const stream = get(video, "media.stream");
    if (!stream) return null;

    const qualities = [];
    const qualityUrls = {};

    const formats = [
      { key: "origin", name: "原画" },
      { key: "h264", name: "HD" },
      { key: "h265", name: "HD (H.265)" },
      { key: "av1", name: "HD (AV1)" },
    ];

    for (const { key, name } of formats) {
      const streams = stream[key];
      if (Array.isArray(streams) && streams.length > 0) {
        // 找码率最高的流
        let bestStream = streams[0];
        let bestBitrate = bestStream.videoBitrate || 0;

        for (const s of streams) {
          const bitrate = s.videoBitrate || 0;
          if (bitrate > bestBitrate) {
            bestBitrate = bitrate;
            bestStream = s;
          }
        }

        const url = bestStream.masterUrl || bestStream.url;
        if (url) {
          qualities.push(name);
          qualityUrls[name] = url;
        }
      }
    }

    if (qualities.length === 0) return null;

    return {
      qualities,
      qualityUrls,
      videoUrl: qualityUrls[qualities[0]],
      width: video.width,
      height: video.height,
    };
  }

  /**
   * 构建基础结果对象
   */
  function buildResult(note) {
    const id = get(note, "noteId") || get(note, "id") || "";
    const title = get(note, "title") || "";
    const desc = get(note, "desc") || "";
    const coverUrl = extractCoverUrl(note);

    // 判断类型
    const videoInfo = extractVideoInfo(note);
    const imageUrls = extractImageUrls(note);
    const type = videoInfo ? "video" : imageUrls.length > 0 ? "image" : "unknown";

    const result = {
      id: String(id),
      title: title || desc.substring(0, 50),
      coverUrl,
      type,
      platform: "xiaohongshu",
      width: note.width || null,
      height: note.height || null,
    };

    if (type === "video" && videoInfo) {
      result.qualities = videoInfo.qualities;
      result.qualityUrls = videoInfo.qualityUrls;
      result.videoUrl = videoInfo.videoUrl;
      result.width = videoInfo.width;
      result.height = videoInfo.height;
    } else if (type === "image") {
      result.imageUrls = imageUrls;
      result.imageCount = imageUrls.length;
    }

    return result;
  }

  // ── 主流程 ──────────────────────────────────────────────────────────────────

  function runExtract() {
    // 获取初始状态
    const data = getInitialState();
    if (!data) return jsonFail(ErrorCode.NO_INITIAL_STATE);

    // 提取笔记数据
    const note = extractNoteData(data);
    if (!note) return jsonFail(ErrorCode.NO_NOTE_DATA);

    // 构建结果
    const result = buildResult(note);
    return jsonSuccess(result);
  }

  // 执行并返回结果
  try {
    return runExtract();
  } catch (e) {
    return jsonFail(`${ErrorCode.EXTRACTION_FAILED}: ${e.message}`);
  }
})();
