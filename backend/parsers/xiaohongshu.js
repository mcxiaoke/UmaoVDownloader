/**
 * xiaohongshu.js — 小红书解析器
 *
 * 数据结构：window.__INITIAL_STATE__
 * 支持：图文笔记、视频笔记
 */

import {
  fetchWithRetry,
  extractUrl,
} from "./common.js";

const XHS_UA =
  "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) " +
  "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1";

const XHS_HEADERS = {
  "User-Agent": XHS_UA,
  "Referer": "https://www.xiaohongshu.com/",
  "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
  "Accept-Language": "zh-CN,zh;q=0.9",
};

/**
 * 判断是否支持该 URL
 */
export function canParse(url) {
  return /(xiaohongshu\.com|xhslink\.com)/.test(url);
}

/**
 * 解析入口
 */
export async function parse(url) {
  const extracted = extractUrl(url);

  // 跟随重定向获取真实 URL 和 HTML
  const { html, finalUrl } = await resolveXhsUrl(extracted);

  // 尝试从 __INITIAL_STATE__ 提取数据
  let data = extractInitialState(html);

  // 如果失败，尝试 SSR 数据
  if (!data) {
    data = extractSSRData(html);
  }

  if (!data) {
    throw new Error("未找到 __INITIAL_STATE__ 或 SSR 数据");
  }

  // 提取笔记数据
  const note = extractNoteData(data);
  if (!note) {
    throw new Error("无法提取笔记数据");
  }

  return buildResult(note);
}

// ── 内部函数 ─────────────────────────────────────────────────────────────────

async function resolveXhsUrl(url) {
  // 跟随重定向
  const resp = await fetchWithRetry(url, {
    redirect: "follow",
    headers: XHS_HEADERS,
  }, 3);

  const finalUrl = resp.url;
  const html = await resp.text();

  return { html, finalUrl };
}

/**
 * 尝试从 SSR 渲染的 HTML 中提取数据（备用方案）
 */
function extractSSRData(html) {
  // 有些页面数据在 <script id="ssr-data" type="application/json"> 中
  const ssrMatch = html.match(
    /<script[^>]*id=["']ssr-data["'][^>]*>([\s\S]*?)<\/script>/
  );
  if (ssrMatch) {
    try {
      return JSON.parse(ssrMatch[1]);
    } catch {
      return null;
    }
  }

  // 或者在 window.__INITIAL_STATE__ 中（已经由 extractWindowData 处理）
  return null;
}

/**
 * 从 HTML 中提取 __INITIAL_STATE__
 * 注意：小红书的数据包含 undefined，需要用 new Function 解析
 */
function extractInitialState(html) {
  // 兼容多种格式：window.__INITIAL_STATE__= 或 window.__INITIAL_STATE__ =
  const marker = html.match(/window\.__INITIAL_STATE__\s*=\s*/);
  if (!marker) return null;

  const start = marker.index + marker[0].length;
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
 * 从 __INITIAL_STATE__ 中提取笔记数据
 * 数据结构：noteData.data.noteData
 */
function extractNoteData(data) {
  // 新结构：noteData.data.noteData
  const note = data.noteData?.data?.noteData;
  if (note) return note;

  // 备用路径
  if (data.note?.noteDetailMap) {
    const noteMap = data.note.noteDetailMap;
    const keys = Object.keys(noteMap);
    if (keys.length > 0) return noteMap[keys[0]];
  }

  return null;
}

/**
 * 构建统一的结果对象
 */
function buildResult(note) {
  const id = note.noteId || note.id || "";
  const title = note.title || "";
  const desc = note.desc || "";

  // 封面图
  const coverUrl = extractCoverUrl(note);

  // 提取图片列表
  const imageUrls = extractImageUrls(note);

  // 提取视频信息
  const videoInfo = extractVideoInfo(note);

  // 判断类型：有视频优先视频，否则图片
  const type = videoInfo ? "video" : imageUrls.length > 0 ? "image" : "unknown";

  const result = {
    type,
    platform: "xiaohongshu",
    id: String(id),
    shareId: null, // 小红书没有类似抖音的短链 ID
    title: title || desc.substring(0, 50),
    coverUrl,
    width: note.width || null,
    height: note.height || null,
  };

  if (type === "image") {
    result.imageUrls = imageUrls;
    result.imageCount = imageUrls.length;
  } else if (type === "video" && videoInfo) {
    result.qualities = videoInfo.qualities;
    result.qualityUrls = videoInfo.qualityUrls;
    result.videoUrl = videoInfo.videoUrl;
  }

  return result;
}

function extractCoverUrl(note) {
  // 尝试多种封面图路径
  const candidates = [
    note.cover?.urlDefault,
    note.cover?.url,
    note.cover?.infoList?.[0]?.url,
    note.imageList?.[0]?.urlDefault,
    note.imageList?.[0]?.url,
    note.imageList?.[0]?.infoList?.[0]?.url,
  ];

  for (const url of candidates) {
    if (url) return url;
  }

  // 备用：从视频首帧提取
  if (note.video?.media?.videoFirstFrame?.url) {
    return note.video.media.videoFirstFrame.url;
  }

  return null;
}

function extractImageUrls(note) {
  const imageList = note.imageList || note.images || [];
  if (!Array.isArray(imageList)) return [];

  return imageList
    .map((img) => {
      // 小红书图片格式
      // 优先 urlDefault，其次 url
      return img.urlDefault || img.url || null;
    })
    .filter(Boolean);
}

function extractVideoInfo(note) {
  const video = note.video;
  if (!video) return null;

  // 从小红书媒体流中提取视频 URL
  // 优先级：origin > h264 > h265 > av1
  const stream = video.media?.stream;
  if (!stream) return null;

  const qualities = [];
  const qualityUrls = {};

  // 尝试各种编码格式（使用不同名称避免重复标签）
  const formats = [
    { key: "origin", name: "原画" },
    { key: "h264", name: "HD" },
    { key: "h265", name: "HD (H.265)" },
    { key: "av1", name: "HD (AV1)" },
  ];

  for (const { key, name } of formats) {
    const streams = stream[key];
    if (Array.isArray(streams) && streams.length > 0) {
      // 取第一个流（通常是最佳质量）
      const s = streams[0];
      // 小红书视频 URL 在 masterUrl 字段
      const url = s.masterUrl || s.url;
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
  };
}
