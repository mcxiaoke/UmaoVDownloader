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
   * 使用 JSON 解析提取 __INITIAL_STATE__
   * 将 JavaScript undefined 替换为 null 使其成为合法 JSON
   */
  function parseInitialStateFromHtmlJson() {
    const html = document.documentElement.innerHTML;
    const match = html.match(/window\.__INITIAL_STATE__\s*=\s*(\{[\s\S]*?\})(?:;|\s*<\/script>)/);
    if (!match) return null;

    let jsonStr = match[1];

    // 将 JavaScript undefined 替换为 null
    // 匹配: : undefined, : undefined} : undefined] 等情况
    jsonStr = jsonStr.replace(/:\s*undefined\s*([,}\]])/g, ':null$1');

    try {
      return JSON.parse(jsonStr);
    } catch {
      // JSON 解析失败，返回 null 让调用方使用备用方案
      return null;
    }
  }

  /**
   * 备用方案：手动提取 + new Function 解析
   * 处理边界情况（如嵌套引号、特殊字符等）
   */
  function parseInitialStateFromHtmlLegacy() {
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
            // 使用 new Function 作为安全的替代方案
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
   * 优先使用 JSON 解析，失败则回退到手动提取
   */
  function getInitialState() {
    // 1. 优先从 window 对象获取（如果页面已加载完成）
    const fromWindow = getInitialStateFromWindow();
    if (fromWindow) return fromWindow;

    // 2. 尝试 JSON 解析
    const fromJson = parseInitialStateFromHtmlJson();
    if (fromJson) {
      console.log('[XHS WebView] 使用 JSON 解析成功');
      return fromJson;
    }

    // 3. 回退到手动提取
    console.log('[XHS WebView] JSON 解析失败，回退到手动提取');
    return parseInitialStateFromHtmlLegacy();
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
   * 支持 notes_pre_post 和 notes_uhdr 路径
   */
  function extractFileIdFromUrl(url) {
    if (!url) return null;
    try {
      const urlObj = new URL(url);
      const pathParts = urlObj.pathname.split("/").filter(Boolean);
      const lastPart = pathParts[pathParts.length - 1];
      const fileId = lastPart.split("!")[0];
      if (fileId && /^[a-z0-9]+$/i.test(fileId)) {
        // 检查路径前缀（注意：有单数 note 和复数 notes 两种形式）
        let prefix = "";
        if (pathParts.includes("notes_pre_post")) {
          prefix = "notes_pre_post/";
        } else if (pathParts.includes("note_pre_post_uhdr")) {
          prefix = "note_pre_post_uhdr/";
        } else if (pathParts.includes("notes_uhdr")) {
          prefix = "notes_uhdr/";
        }
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
   * 提取图片列表（含 thumb 和 full）
   */
  function extractImageList(note) {
    const imageList = get(note, "imageList", []);
    if (!Array.isArray(imageList)) return [];

    return imageList
      .map((img) => {
        // 优先使用 infoList 中的 URL 提取 fileId
        const infoList = get(img, "infoList", []);
        let fullUrl = null;
        let thumbUrl = null;

        if (infoList.length > 0) {
          const best = infoList[infoList.length - 1];
          const thumb = infoList[0];
          if (best.url) {
            const result = extractFileIdFromUrl(best.url);
            if (result) {
              fullUrl = `https://sns-img-hw.xhscdn.com/${result.prefix}${result.fileId}?imageView2/2/w/0/format/jpg`;
            } else {
              fullUrl = best.url;
            }
          }
          if (thumb.url) {
            const result = extractFileIdFromUrl(thumb.url);
            if (result) {
              thumbUrl = `https://sns-img-hw.xhscdn.com/${result.prefix}${result.fileId}?imageView2/2/w/200/format/jpg`;
            } else {
              thumbUrl = thumb.url;
            }
          }
        }

        // 备用：traceId
        if (!fullUrl) {
          const traceId = img.traceId || get(img, "infoList.0.imageScene.traceId");
          if (traceId) {
            fullUrl = `https://sns-img-hw.xhscdn.com/${traceId}?imageView2/2/w/0/format/jpg`;
            thumbUrl = `https://sns-img-hw.xhscdn.com/${traceId}?imageView2/2/w/200/format/jpg`;
          }
        }

        // 最后备用
        if (!fullUrl) {
          fullUrl = img.urlDefault || img.url || null;
          thumbUrl = img.urlDefault || img.url || null;
        }

        if (!fullUrl) return null;

        return {
          full: fullUrl,
          thumb: thumbUrl || fullUrl,
          isLivePhoto: img.livePhoto === true,
          videoUrl: null, // 实况图视频URL在extractLivePhotoUrls中单独处理
        };
      })
      .filter(Boolean);
  }

  /**
   * 提取图片 URL 列表（无水印高清图）- 兼容旧字段
   */
  function extractImageUrls(note) {
    const list = extractImageList(note);
    return list.map(i => i.full);
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
   * 提取实况图视频 URL 列表
   * 实况图 (livePhoto) 每张图都带有一个短视频（带声音）
   */
  function extractLivePhotoUrls(note) {
    const imageList = get(note, "imageList", []);
    if (!Array.isArray(imageList)) return [];

    const urls = [];
    for (const img of imageList) {
      // 检查是否为实况图
      if (img.livePhoto !== true) continue;

      // 提取视频流
      const stream = img.stream;
      if (!stream || typeof stream !== "object") continue;

      // 优先 h264，其次 h265/av1
      const formats = ["h264", "h265", "hevc", "av1"];
      let videoUrl = null;
      for (const fmt of formats) {
        const streams = stream[fmt];
        if (Array.isArray(streams) && streams.length > 0) {
          const first = streams[0];
          if (first) {
            videoUrl = first.masterUrl || first.url;
            if (videoUrl) break;
          }
        }
      }
      if (videoUrl) {
        urls.push(videoUrl);
      }
    }
    return urls;
  }

  /**
   * 从URL中提取分享ID (xhslink.com/o/xxxxx)
   */
  function extractShareId(url) {
    try {
      const urlObj = new URL(url);
      const pathParts = urlObj.pathname.split("/").filter(Boolean);
      if (urlObj.hostname === "xhslink.com" && pathParts[0] === "o") {
        return pathParts[1] || null;
      }
    } catch {
      const match = url.match(/xhslink\.com\/o\/([A-Za-z0-9_-]+)/);
      if (match) return match[1];
    }
    return null;
  }

  /**
   * 构建基础结果对象 - 对齐 backend 字段
   */
  function buildResult(note, shareId) {
    const id = get(note, "noteId") || get(note, "id") || "";
    const title = get(note, "title") || "";
    const desc = get(note, "desc") || "";
    const coverUrl = extractCoverUrl(note);

    // 判断类型
    const videoInfo = extractVideoInfo(note);
    const imageList = extractImageList(note);
    const imageUrls = imageList.map(i => i.full);
    const imageThumbs = imageList.map(i => i.thumb);
    const livePhotoUrls = extractLivePhotoUrls(note);

    // 优先级：普通视频 > 实况图 > 纯图片
    let type = "unknown";
    if (videoInfo) {
      type = "video";
    } else if (livePhotoUrls.length > 0) {
      type = "livephoto";
    } else if (imageUrls.length > 0) {
      type = "image";
    }

    // 提取用户信息
    const user = note.user || note.author || {};
    const userInfo = {
      userId: user.userId || user.id || null,
      nickname: user.nickName || user.nickname || null,
      avatar: user.avatar || null,
    };

    // 提取背景音乐
    const musicInfo = extractMusicInfo(note);

    const result = {
      ok: true,
      platform: "xiaohongshu",
      id: String(id),
      itemId: String(id),
      shareId,
      title: title || desc.substring(0, 50),
      coverUrl,
      type,
      width: note.width || null,
      height: note.height || null,
      ...userInfo,
    };

    if (type === "video" && videoInfo) {
      result.qualities = videoInfo.qualities;
      result.qualityUrls = videoInfo.qualityUrls;
      result.videoUrl = videoInfo.videoUrl;
      result.width = videoInfo.width;
      result.height = videoInfo.height;
    } else if (type === "livephoto") {
      // 实况图：返回视频 URL 列表和图片 URL 列表（用于缩略图）
      result.livePhotoUrls = livePhotoUrls;
      result.livePhotoCount = livePhotoUrls.length;
      result.imageUrls = imageUrls;
      result.imageThumbs = imageThumbs;
      result.imageList = imageList;
      result.imageCount = imageUrls.length;
      // 用第一个视频 URL 作为默认视频地址
      result.videoUrl = livePhotoUrls[0];
      result.qualityUrls = { "720p": livePhotoUrls[0] };
    } else if (type === "image") {
      result.imageUrls = imageUrls;
      result.imageThumbs = imageThumbs;
      result.imageList = imageList;
      result.imageCount = imageUrls.length;
    }

    // 添加音乐信息
    if (musicInfo.url) {
      result.musicUrl = musicInfo.url;
      result.musicTitle = musicInfo.title;
      result.musicAuthor = musicInfo.author;
    }

    return result;
  }

  /**
   * 提取背景音乐信息
   */
  function extractMusicInfo(note) {
    // 1. 直接在 note.music
    const music = note.music;
    if (music) {
      const url = music.url || music.playUrl || music.path;
      const title = music.title || music.name;
      const author = music.author || music.artist || music.singer;
      if (url) {
        return { url, title, author };
      }
    }

    // 2. 在 note.bgm
    const bgm = note.bgm;
    if (bgm) {
      const url = bgm.url || bgm.playUrl || bgm.path;
      const title = bgm.title || bgm.name;
      const author = bgm.author || bgm.artist || bgm.singer;
      if (url) {
        return { url, title, author };
      }
    }

    // 3. 在 note.audio
    const audio = note.audio;
    if (audio) {
      const url = audio.url || audio.playUrl || audio.path;
      const title = audio.title || audio.name;
      const author = audio.author || audio.artist || audio.singer;
      if (url) {
        return { url, title, author };
      }
    }

    return { url: null, title: null, author: null };
  }

  // ── 主流程 ──────────────────────────────────────────────────────────────────

  function runExtract() {
    // 获取初始状态
    const data = getInitialState();
    if (!data) return jsonFail(ErrorCode.NO_INITIAL_STATE);

    // 提取笔记数据
    const note = extractNoteData(data);
    if (!note) return jsonFail(ErrorCode.NO_NOTE_DATA);

    // 提取分享ID（优先使用外部传入的 shareId，否则从当前 URL 提取）
    const shareId = (typeof window !== 'undefined' && window.__SHARE_ID__) || extractShareId(location.href);

    // 构建结果
    const result = buildResult(note, shareId);
    return jsonSuccess(result);
  }

  // 执行并返回结果
  try {
    return runExtract();
  } catch (e) {
    return jsonFail(`${ErrorCode.EXTRACTION_FAILED}: ${e.message}`);
  }
})();
