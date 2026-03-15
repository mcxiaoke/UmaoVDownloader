/**
 * douyin.js — 抖音平台解析器
 *
 * 功能概述：
 * 本解析器专门处理抖音平台（douyin.com）的视频和图文内容解析。
 * 支持短链接、视频详情页、图文笔记等多种链接格式。
 * 能够提取无水印视频、高清图片、背景音乐等信息。
 *
 * 主要特性：
 * - 支持抖音短链接（v.douyin.com）解析
 * - 提取多画质视频（2160p/1080p/720p）
 * - 图文内容解析，支持背景音乐提取
 * - 智能数据提取，支持多种页面结构
 * - 调试信息保存，便于问题排查
 *
 * 数据源：
 * 主要通过解析页面中的window._ROUTER_DATA JavaScript变量获取结构化数据
 */

import fs from "fs-extra"; // 文件系统操作
import { join } from "path"; // 路径处理
import { clearCookie, getCookie, isCookieLikelyInvalid } from "../cookies.js";
import {
  DEFAULT_HEADERS,
  extractUrl,
  extractWindowData,
  fetchWithRetry,
  MOBILE_UA,
} from "./common.js";

// 抖音无水印视频播放接口基础URL
const PLAY_BASE = "https://aweme.snssdk.com/aweme/v1/play/";

// 当前使用的请求头（包含动态 Cookie）
let DY_HEADERS = { ...DEFAULT_HEADERS };

// 支持的画质等级，按优先级排序（从高到低）
const QUALITY_RATIOS = ["2160p", "1080p", "720p"];

// 类型映射：aweme_type -> 媒体类型
const MEDIA_TYPES = {
  // 视频类型
  video: [0, 4, 51, 55, 58, 61, 109, 201],
  // 图文类型
  image: [2, 68, 150],
};

// 条件日志函数
let log = () => {};

// 当前解析的短ID，用于调试文件命名
let currentShortId = "";

/**
 * 初始化请求头（加载 Cookie）
 */
async function initHeaders() {
  const cookie = await getCookie("douyin");
  if (cookie) {
    DY_HEADERS = { ...DEFAULT_HEADERS, Cookie: cookie };
    log("  ✓ 已加载 Cookie");
  } else {
    DY_HEADERS = { ...DEFAULT_HEADERS };
  }
}

/**
 * 判断是否支持解析该URL
 * 通过正则表达式检测URL是否属于抖音平台
 * @param {string} url - 待检测的URL
 * @returns {boolean} 是否支持解析
 */
export function canParse(url) {
  return /(v\.)?douyin\.com|iesdouyin\.com/.test(url);
}

/**
 * 抖音链接解析主入口
 * 负责协调整个解析流程，包括URL处理、数据提取、结果构建
 * @param {string} url - 抖音链接（支持短链接和完整链接）
 * @param {boolean} debug - 是否开启调试日志
 * @returns {Promise<VideoInfo>} 解析结果
 */
export async function parse(url, debug = false) {
  log = debug ? (...args) => console.log("  [DY]", ...args) : () => {};
  currentShortId = extractShortId(url); // 设置当前短ID

  // 初始化请求头（加载 Cookie）
  await initHeaders();

  log(`开始解析: ${url}`);
  log(`短ID: ${currentShortId}`);

  const extracted = extractUrl(url);
  log(`提取URL: ${extracted}`);

  // 跟随重定向获取 HTML
  log("→ 请求页面...");
  const { html: rawHtml, finalUrl, shareId } = await resolveAndFetch(extracted);
  log(`  最终URL: ${finalUrl}`);
  log(`  HTML长度: ${rawHtml.length} bytes`);

  const awemeId = extractVideoId(finalUrl);
  if (!awemeId) {
    throw new Error(`无法从链接提取视频 ID，最终 URL: ${finalUrl}`);
  }
  log(`  awemeId: ${awemeId}`);

  const isNote = finalUrl.includes("/note/");
  log(`  类型: ${isNote ? "图文(note)" : "视频(video)"}`);

  // 若页面不含数据，重新请求 share 页
  let html = rawHtml;
  if (!html.includes("window._ROUTER_DATA")) {
    log("  未找到 _ROUTER_DATA, 请求 share 页面...");
    const shareBase = `https://www.iesdouyin.com/share/${isNote ? "note" : "video"}/${awemeId}/`;
    const origParams = new URL(finalUrl).search;
    html = await fetchSharePage(shareBase + origParams);
  }

  log("→ 提取 _ROUTER_DATA...");
  let routerData = extractRouterDataJson(html);

  // JSON解析失败，回退到手动提取
  if (!routerData) {
    log("  JSON解析失败，回退到手动提取...");
    //routerData = extractWindowData(html, "_ROUTER_DATA");
  }

  // 检测 Cookie 是否可能无效/过期，如果是则清除后重试
  if (!routerData && isCookieLikelyInvalid("douyin", html, null)) {
    log("  ⚠️ Cookie 可能无效或已过期，正在清除并重新尝试...");
    await clearCookie("douyin");
    // 重置请求头（去掉 Cookie）
    DY_HEADERS = { ...DEFAULT_HEADERS };
    // 重新获取页面
    html = await fetchSharePage(finalUrl);
    // 重新提取数据
    routerData = extractRouterDataJson(html);
  }

  if (!routerData) {
    throw new Error("未找到 _ROUTER_DATA");
  }
  log("  ✓ 提取成功");

  log("→ 提取视频/图文数据...");
  const item = extractItem(routerData);
  if (!item) {
    throw new Error("videoInfoRes.item_list 为空");
  }
  log(`  ✓ title: ${(item.desc || "").substring(0, 50)}`);

  // 保存提取的item数据供调试
  saveDebugJson(item, "item_data");

  // 使用统一的类型检测函数
  const mediaType = detectMediaType(item);
  log(`  ✓ 内容类型: ${mediaType}`);

  // 提取用户信息
  // 抖音author对象字段：short_id, unique_id(抖音号), sec_uid, nickname, avatar_thumb
  const author = item.author ?? {};
  const userInfo = {
    userId: author.unique_id ?? author.short_id ?? null,
    nickname: author.nickname ?? null,
    avatar: author.avatar_thumb?.url_list?.[0] ?? null,
  };

  // 构建基础信息
  const itemId = item.aweme_id ?? awemeId;
  const info = {
    type: mediaType,
    platform: "douyin",
    id: itemId,
    itemId, // 统一字段：平台内容ID
    shareId, // 短链接ID（如 v.douyin.com/xxxxx 中的 xxxxx）
    title: item.desc ?? "",
    coverUrl: item.video?.cover?.url_list?.[0] ?? null,
    width: item.video?.width ?? null,
    height: item.video?.height ?? null,
    ...userInfo,
  };

  log("→ 构建结果:");

  // 根据类型填充详细内容
  if (mediaType === "image") {
    // 统一图片结构：返回完整的 imageList（含 thumb 和 full）
    info.imageList = extractImageList(item);
    info.imageUrls = info.imageList.map((i) => i.full);
    info.imageThumbs = info.imageList.map((i) => i.thumb);
    info.imageCount = info.imageList.length;
    info.musicTitle = item.music?.title ?? null;
    info.musicAuthor = item.music?.author ?? null;
    info.musicUrl = extractMusicUrl(item);
    log(`  type: image, imageCount: ${info.imageCount}`);
    if (info.imageUrls.length > 0) {
      log(`  imageUrls[0]: ${info.imageUrls[0]}`);
    }
    if (info.musicUrl) {
      log(`  musicUrl: ${info.musicUrl}`);
    }
  } else {
    // 只返回最高画质视频
    const qualities = extractQualities(item);
    const bestQuality = qualities[0];
    info.videoUrl = bestQuality
      ? buildPlayUrl(bestQuality.videoFileId, bestQuality.ratio)
      : null;
    info.quality = bestQuality?.ratio ?? null;
    info.videoSize = bestQuality?.size ?? null;
    info.videoBitrate = bestQuality?.bitrate ?? null; // 视频码率 (bps)
    info.width = bestQuality?.width ?? info.width;
    info.height = bestQuality?.height ?? info.height;
    // duration 单位是毫秒，转换为秒
    info.duration = item.video?.duration
      ? Math.round(item.video.duration / 1000)
      : null;
    log(
      `  type: video, quality: ${info.quality || "none"}, size: ${info.videoSize || "unknown"}, duration: ${info.duration || "unknown"}s`,
    );
    log(`  videoUrl: ${info.videoUrl || "none"}`);
  }

  return info;
}

// ── 类型检测 ─────────────────────────────────────────────────────────────────

/**
 * 智能检测作品类型
 * 优先使用 aweme_type，未知时综合以下特征：
 * - images 字段是否存在且非空
 * - video.play_addr.uri 格式（URL 开头 vs 视频 ID）
 * - video.duration（图文为 0 或很小，视频有实际时长）
 * @param {object} item - 作品数据
 * @returns {"image"|"video"} 媒体类型
 */
function detectMediaType(item) {
  // 1. 优先使用 aweme_type 判断
  const awemeType = item.aweme_type;
  if (awemeType != null) {
    const typeNum = Number(awemeType);
    if (MEDIA_TYPES.image.includes(typeNum)) {
      log(`  aweme_type=${typeNum} 判定为图文`);
      return "image";
    }
    if (MEDIA_TYPES.video.includes(typeNum)) {
      log(`  aweme_type=${typeNum} 判定为视频`);
      return "video";
    }
    log(`  未知 aweme_type=${typeNum}，进入兜底判断`);
  } else {
    log(`  无 aweme_type，进入兜底判断`);
  }

  // 2. 兜底：综合特征判断
  const images = item.images;
  const video = item.video;

  // 特征 1：images 字段存在且非空 → 图文
  if (Array.isArray(images) && images.length > 0) {
    log(`  images 字段存在且非空，判定为图文`);
    return "image";
  }

  // 特征 2：video.play_addr.uri 以 http 开头 → 图文（实况图/音频）
  const playUri = video?.play_addr?.uri;
  if (typeof playUri === "string" && playUri.startsWith("http")) {
    log(`  video.play_addr.uri 为 URL 格式，判定为图文`);
    return "image";
  }

  // 特征 3：video.duration 为 0 或不存在，且 images 为空 → 可能是图文
  const duration = video?.duration;
  if ((duration == null || duration === 0) && !Array.isArray(images)) {
    const bitRate = video?.bit_rate;
    if (!Array.isArray(bitRate) || bitRate.length === 0) {
      log(`  duration=0 且无码率信息，判定为图文`);
      return "image";
    }
  }

  // 默认判定为视频
  log(`  无图文特征，默认判定为视频`);
  return "video";
}

// ── 内部函数 ─────────────────────────────────────────────────────────────────

async function resolveAndFetch(url) {
  // 提取 shareId（短链接 ID）
  let shareId = null;
  try {
    const urlObj = new URL(url);
    const pathParts = urlObj.pathname.split("/").filter(Boolean);
    if (urlObj.hostname === "v.douyin.com" && pathParts[0]) {
      shareId = pathParts[0];
    }
  } catch {
    // 回退到正则
    shareId = url.match(/v\.douyin\.com\/([A-Za-z0-9_-]+)/)?.[1] ?? null;
  }

  const resp = await fetchWithRetry(url, {
    redirect: "follow",
    headers: DY_HEADERS,
  });

  const finalUrl = resp.url;
  const html = await resp.text();
  return { html, finalUrl, shareId };
}

async function fetchSharePage(fullUrl) {
  const resp = await fetchWithRetry(fullUrl, { headers: DY_HEADERS });
  return resp.text();
}

function extractVideoId(url) {
  try {
    const urlObj = new URL(url);
    const pathParts = urlObj.pathname.split("/").filter(Boolean);

    // /video/xxxxx 或 /note/xxxxx 或 /slides/xxxxx
    const idIndex = pathParts.findIndex((p) =>
      ["video", "note", "slides"].includes(p),
    );
    if (idIndex !== -1 && pathParts[idIndex + 1]) {
      return pathParts[idIndex + 1];
    }
  } catch {
    // 如果 URL 解析失败，回退到正则
    const m = url.match(/\/(?:video|note|slides)\/(\d+)/);
    if (m) return m[1];
  }
  return null;
}

function extractItem(routerData) {
  const loaderData = routerData.loaderData;
  if (!loaderData) return null;

  const pageKey = Object.keys(loaderData).find((k) => k.includes("/page"));
  if (!pageKey) return null;

  return loaderData[pageKey]?.videoInfoRes?.item_list?.[0] ?? null;
}

function buildPlayUrl(videoFileId, ratio = "1080p", line = 0) {
  return `${PLAY_BASE}?video_id=${videoFileId}&ratio=${ratio}&line=${line}`;
}

function extractQualities(item) {
  const video = item.video;
  const bitRates = video?.bit_rate;

  if (Array.isArray(bitRates) && bitRates.length > 0) {
    return bitRates
      .map((b) => ({
        ratio: b.gear_name?.replace("gear_", "") ?? b.quality_type ?? "",
        videoFileId: b.play_addr?.uri,
        size: b.data_size ?? 0,
        bitrate: b.bit_rate ?? 0, // 视频码率 (bps)
        width: b.play_addr?.width ?? video?.width ?? 0,
        height: b.play_addr?.height ?? video?.height ?? 0,
      }))
      .filter((q) => QUALITY_RATIOS.includes(q.ratio) && q.videoFileId)
      .sort(
        (a, b) =>
          QUALITY_RATIOS.indexOf(a.ratio) - QUALITY_RATIOS.indexOf(b.ratio),
      );
  }

  const uri = video?.play_addr?.uri;
  if (!uri) return [];

  const h = video?.height ?? 0;
  const w = video?.width ?? 0;
  const ratio =
    h >= 2160 ? "2160p" : h >= 1080 ? "1080p" : h >= 720 ? "720p" : "480p";
  return [{ ratio, videoFileId: uri, size: 0, width: w, height: h }];
}

function extractImageUrls(item) {
  const images = item.images;
  if (!Array.isArray(images) || images.length === 0) return [];

  return images
    .map((img) => {
      const urls = img.url_list ?? [];
      return (
        urls.find(
          (u) => u.includes("tplv-dy-lqen-new") && !u.includes("-water"),
        ) ??
        urls.find((u) => u.includes("tplv-dy-aweme-images")) ??
        urls[0] ??
        null
      );
    })
    .filter(Boolean);
}

/**
 * 提取图片列表（统一结构：含 thumb 和 full）
 * 返回 [{thumb, full}, ...] 格式，与小红书保持一致
 */
function extractImageList(item) {
  const images = item.images;
  if (!Array.isArray(images) || images.length === 0) return [];

  return images
    .map((img, idx) => {
      const urls = img.url_list ?? [];

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
        log(`  图片 ${idx + 1}: 无可用 URL`);
        return null;
      }

      return { thumb: thumb || full, full };
    })
    .filter(Boolean);
}

/**
 * 判断字符串是否为合法的 URL
 * @param {string} str - 待验证的字符串
 * @returns {boolean} 是否为合法 URL
 */
function isValidURL(str) {
  // 先做空值/非字符串过滤
  if (typeof str !== "string" || str.trim() === "") {
    return false;
  }
  try {
    new URL(str);
    return true;
  } catch (err) {
    // 捕获构造失败的异常，返回 false
    return false;
  }
}

function extractMusicUrl(item) {
  // 优先使用 music.play_url（如有）
  const mUrl = item.music?.play_url?.url_list?.[0];
  if (isValidURL(mUrl)) return mUrl;

  // 其次使用 video.play_addr.uri（不管是否mp3后缀）
  const playUri = item.video?.play_addr?.uri;
  if (isValidURL(playUri)) {
    return playUri;
  }

  return null;
}

// ── 辅助函数 ─────────────────────────────────────────────────────────────────

/**
 * 从URL中提取短ID (如 v.douyin.com/xxxxx 中的 xxxxx)
 */
function extractShortId(url) {
  try {
    const urlObj = new URL(url);
    const pathParts = urlObj.pathname.split("/").filter(Boolean);

    // v.douyin.com/xxxxx
    if (urlObj.hostname === "v.douyin.com" && pathParts[0]) {
      return pathParts[0];
    }

    // /video/xxxxx 或 /note/xxxxx 或 /slides/xxxxx
    const idIndex = pathParts.findIndex((p) =>
      ["video", "note", "slides"].includes(p),
    );
    if (idIndex !== -1 && pathParts[idIndex + 1]) {
      return pathParts[idIndex + 1];
    }
  } catch {
    // 如果 URL 解析失败，回退到正则
    const match = url.match(/v\.douyin\.com\/([A-Za-z0-9_-]+)/);
    if (match) return match[1];
    const pathMatch = url.match(/\/(?:video|note|slides)\/(\d+)/);
    if (pathMatch) return pathMatch[1];
  }
  return "";
}

/**
 * 使用 JSON 解析提取 _ROUTER_DATA
 * 优先方法，失败返回 null 让调用方使用备用方案
 */
function extractRouterDataJson(html) {
  // 匹配 window._ROUTER_DATA = {...} 或 window._ROUTER_DATA={...}
  const match = html.match(
    /window\._ROUTER_DATA\s*=\s*(\{[\s\S]*?\})(?:;|\s*<\/script>)/,
  );
  if (!match) return null;

  let jsonStr = match[1];

  // 将 JavaScript undefined 替换为 null
  jsonStr = jsonStr.replace(/:\s*undefined\s*([,}\]])/g, ":null$1");

  try {
    const data = JSON.parse(jsonStr);
    // 保存原始 JSON 到 temp 目录供调试
    log("  JSON 解析成功，保存调试数据...");
    saveDebugJson(data, "router_data");
    return data;
  } catch (e) {
    // JSON 解析失败，返回 null 让调用方使用备用方案
    log(`  JSON 解析失败: ${e.message}`);
    return null;
  }
}

/**
 * 保存调试 JSON 到 backend/temp 目录
 */
async function saveDebugJson(data, prefix) {
  try {
    const tempDir = join(process.cwd(), "temp");
    await fs.ensureDir(tempDir);
    const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
    const idPrefix = currentShortId ? `${currentShortId}_` : "";
    const filePath = join(tempDir, `dy_${idPrefix}${prefix}_${timestamp}.json`);
    await fs.writeFile(filePath, JSON.stringify(data, null, 2));
    log(`  调试 JSON 已保存: ${filePath}`);
  } catch (e) {
    // 保存失败不影响主流程
    log(`  保存调试 JSON 失败: ${e.message}`);
  }
}
