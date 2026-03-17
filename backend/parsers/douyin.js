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
import { generateABogus } from "../abogus/index.js"; // a_bogus 签名模块

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

  // 检测是否开启 abogus (URL 参数 abogus=1)
  let useAbogus = false;
  try {
    const urlObj = new URL(url);
    useAbogus = urlObj.searchParams.get("abogus") === "1";
  } catch {
    // URL 解析失败，忽略
  }
  if (useAbogus) {
    log(">>> ABOGUS 模式已开启 <<<");
  }

  // 初始化请求头（加载 Cookie）
  await initHeaders();

  log(`开始解析: ${url}`);

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
  const isNote = finalUrl.includes("/note/");

  // 构建 share 页面 URL 作为 referer
  const shareRefererUrl = `https://www.iesdouyin.com/share/${isNote ? "note" : "video"}/${awemeId}/`;

  // 若页面不含数据，重新请求 share 页
  let html = rawHtml;
  if (!html.includes("window._ROUTER_DATA")) {
    log("  未找到 _ROUTER_DATA, 请求 share 页面...");
    const origParams = new URL(finalUrl).search;
    html = await fetchSharePage(shareRefererUrl + origParams);
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
  log("  ✓ 数据提取成功");

  // 提取 webId（用于 a_bogus 签名）
  let extractedWebId = null;
  try {
    // 从 commonContext 或 loaderData 中提取 webId
    const loaderData = routerData.loaderData || {};
    extractedWebId = routerData.commonContext?.webId || 
      Object.values(loaderData).find(v => v?.webId)?.webId || null;
    if (extractedWebId) {
      log(`  ✓ 提取到 webId: ${extractedWebId}`);
    }
  } catch (e) {
    log(`  ⚠️ 提取 webId 失败: ${e.message}`);
  }

  const item = extractItem(routerData);
  if (!item || Object.keys(item).length === 0) {
    throw new Error("作品不存在或已被删除");
  }

  const itemId = item.aweme_id;
  if (!itemId) {
    throw new Error("作品数据无效，可能是链接已失效");
  }

  // 保存提取的item数据供调试
  saveDebugJson(item, "item_data");

  // 使用统一的类型检测函数
  const mediaType = detectMediaType(item);
  const title = (item.desc || "").trim();
  log(`  ✓ awemeId: ${itemId}, title: ${title.substring(0, 30) || "<无标题>"}, type: ${mediaType}`);

  // 提取作者信息
  const author = item.author ?? {};
  const authorId = author.unique_id ?? author.short_id ?? null;
  const authorName = author.nickname ?? null;
  const authorAvatar = author.avatar_thumb?.url_list?.[0] ?? null;

  // 提取统计信息
  const statistics = item.statistics ?? {};
  const createTime = item.create_time ?? null;

  // 构建基础信息
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
    // 作者信息
    authorId,
    authorName,
    authorAvatar,
    // 统计信息
    createTime,
    likeCount: statistics.digg_count ?? null,
    collectCount: statistics.collect_count ?? null,
    commentCount: statistics.comment_count ?? null,
    shareCount: statistics.share_count ?? null,
  };

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

    log(`→ 构建结果: type=image, imageCount=${info.imageCount}`);

    if (info.imageUrls.length > 0) {
      log(`  imageUrls[0]: ${info.imageUrls[0]}`);
      for (let i = 0; i < info.imageUrls.length; i++) {
        log(`thumb${i + 1}=${info.imageThumbs[i]}`);
        log(`full${i + 1}=${info.imageUrls[i]}`);
      }
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

    log(`→ 构建结果: type=video, quality=${info.quality || "none"}, duration=${info.duration || "unknown"}s`);
    log(`  videoUrl: ${info.videoUrl || "none"}`);
  }

  // 验证结果有效性
  if (!info.videoUrl && (!info.imageUrls || info.imageUrls.length === 0)) {
    throw new Error("无法获取有效的媒体内容，可能是链接无效或已被删除");
  }

  // ========== ABOGUS 模式：获取动图视频 ==========
  if (useAbogus && mediaType === "image" && itemId) {
    log(">>> 尝试获取动图视频 (slidesinfo API)...");
    try {
      const slidesInfo = await fetchSlidesInfo(itemId, shareRefererUrl, extractedWebId);
      if (slidesInfo && slidesInfo.images) {
        log(`  ✓ 获取到 ${slidesInfo.images.length} 张图片数据`);
        
        // 将动图视频信息合并到 imageList，对齐小红书 livephoto 格式
        let livePhotoCount = 0;
        const livePhotoUrls = [];
        
        info.imageList = info.imageList.map((img, idx) => {
          const slideImg = slidesInfo.images[idx];
          if (!slideImg?.video?.play_addr?.url_list?.[0]) {
            // 没有视频，保持原样
            return img;
          }
          
          // 提取视频信息
          const playAddr = slideImg.video.play_addr;
          const playAddrH264 = slideImg.video.play_addr_h264;
          const videoUrl = playAddr.url_list[0];
          const videoUrlH264 = playAddrH264?.url_list?.[0] || videoUrl;
          
          livePhotoCount++;
          livePhotoUrls.push(videoUrl);
          
          log(`  Image ${idx + 1}: 动态视频 ${slideImg.video.duration}ms, ${playAddr.width}x${playAddr.height}, ${(playAddr.data_size / 1024).toFixed(1)}KB`);
          
          // 对齐小红书 livephoto 格式
          return {
            ...img,
            // 视频信息（对齐小红书格式）
            videoUrl: videoUrl,
            videoUrlH264: videoUrlH264,
            isLivePhoto: true,
            // 视频尺寸
            videoWidth: playAddr.width || null,
            videoHeight: playAddr.height || null,
            videoSize: playAddr.data_size || null,
            duration: slideImg.video.duration || null, // 毫秒
          };
        });
        
        // 更新结果（对齐小红书 livephoto 格式）
        if (livePhotoCount > 0) {
          info.type = "livephoto"; // 更新类型
          info.livePhotoCount = livePhotoCount;
          info.livePhotoUrls = livePhotoUrls;
          log(`  ✓ 检测到 ${livePhotoCount} 个实况图，类型更新为 livephoto`);
        }
        
        // 保存 slidesInfo 供调试
        saveDebugJson(slidesInfo, "slidesinfo");
      }
    } catch (e) {
      log(`  ⚠️ 获取动图视频失败: ${e.message}`);
    }
  }

  // 添加 referer 和 cookie（用于 CDN 请求）
  info.refererUrl = shareRefererUrl;
  // 从当前请求头中提取 Cookie（如果有）
  info.cookie = DY_HEADERS.Cookie || null;

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
      return "image";
    }
    if (MEDIA_TYPES.video.includes(typeNum)) {
      return "video";
    }
  }

  // 2. 兜底：综合特征判断
  const images = item.images;
  const video = item.video;

  // 特征 1：images 字段存在且非空 → 图文
  if (Array.isArray(images) && images.length > 0) {
    return "image";
  }

  // 特征 2：video.play_addr.uri 以 http 开头 → 图文（实况图/音频）
  const playUri = video?.play_addr?.uri;
  if (typeof playUri === "string" && playUri.startsWith("http")) {
    return "image";
  }

  // 特征 3：video.duration 为 0 或不存在，且 images 为空 → 可能是图文
  const duration = video?.duration;
  if ((duration == null || duration === 0) && !Array.isArray(images)) {
    const bitRate = video?.bit_rate;
    if (!Array.isArray(bitRate) || bitRate.length === 0) {
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

  let resp;
  try {
    resp = await fetchWithRetry(url, {
      redirect: "follow",
      headers: DY_HEADERS,
    });
  } catch (e) {
    // 检测 404 错误，给出明确提示
    if (e.message && e.message.includes("404")) {
      throw new Error("作品不存在或已被删除（链接返回404）");
    }
    throw e;
  }

  const finalUrl = resp.url;
  const html = await resp.text();

  // 检测页面内容中的错误提示
  if (html.includes("作品已删除") || html.includes("视频已删除") || html.includes("内容不存在")) {
    throw new Error("作品已被删除或不存在");
  }

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
  const imgBitrate = item.img_bitrate;
  if (!Array.isArray(images) || images.length === 0) return [];

  // 构建 uri -> 缩略图映射 (从 img_bitrate)
  const thumbMap = {};
  if (Array.isArray(imgBitrate)) {
    // 优先找 480p 的缩略图
    let targetGear = imgBitrate.find(
      (gear) => gear.name === "gear_480p",
    )?.images;
    // 如果没有 480p，取第一个 gear
    targetGear = targetGear ?? imgBitrate[0]?.images;

    if (Array.isArray(targetGear)) {
      for (const img of targetGear) {
        const uri = img.uri;
        const urlList = img.url_list;
        if (!uri || !Array.isArray(urlList) || urlList.length === 0) continue;
        // 找 shrink 缩略图
        const shrinkUrl = urlList.find((u) => u.includes("tplv-dy-shrink"));
        if (shrinkUrl) {
          thumbMap[uri] = shrinkUrl;
        }
      }
    }
  }

  return images
    .map((img, idx) => {
      const uri = img.uri;
      const urlList = img.url_list ?? [];
      const downloadUrlList = img.download_url_list ?? [];

      let full = null;
      let thumb = null;

      // 1. 大图优先级：lqen-new（无水印）> download_url_list（带水印高清）> aweme-images > fallback
      full =
        urlList.find(
          (u) => u.includes("tplv-dy-lqen-new") && !u.includes("-water"),
        ) ??
        (downloadUrlList.length > 0 ? downloadUrlList[0] : null) ??
        urlList.find((u) => u.includes("tplv-dy-aweme-images")) ??
        urlList[0] ??
        null;

      // 2. 缩略图：从 thumbMap 获取
      if (uri && thumbMap[uri]) {
        thumb = thumbMap[uri];
      }
      thumb = thumb || full;

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
    log(`  保存调试 JSON 失败: ${e}`);
  }
}

// ── ABOGUS 相关函数 ─────────────────────────────────────────────────────────

/**
 * 使用 slidesinfo API 获取动图视频信息
 * @param {string} awemeId - 作品 ID
 * @param {string} referer - Referer URL
 * @returns {Promise<Object|null>} slides 信息
 */
async function fetchSlidesInfo(awemeId, referer, pageWebId = null) {
  // 生成随机 19 位数字 ID (device_id 和 web_id 通常相同)
  const randomId = () => {
    let id = '';
    for (let i = 0; i < 19; i++) {
      id += Math.floor(Math.random() * 10);
    }
    return id;
  };
  
  // 优先使用页面提取的 webId，否则随机生成
  const webId = pageWebId || randomId();
  const deviceId = webId; // device_id 通常与 web_id 相同
  
  if (pageWebId) {
    log(`  [ABOGUS] 使用页面提取的 device_id/web_id: ${deviceId}`);
  } else {
    log(`  [ABOGUS] 随机生成 device_id/web_id: ${deviceId}`);
  }

  // 构建 API URL 参数
  const params = {
    reflow_source: 'reflow_page',
    web_id: webId,
    device_id: deviceId,
    aweme_ids: `[${awemeId}]`,
    request_source: '200'
  };

  // 构建 query string
  const queryString = Object.entries(params)
    .map(([k, v]) => `${k}=${encodeURIComponent(v)}`)
    .join('&');

  log(`  [ABOGUS] queryString: ${queryString.substring(0, 100)}...`);

  // 生成 a_bogus
  const userAgent = DY_HEADERS["User-Agent"] || MOBILE_UA;
  log(`  [ABOGUS] UA: ${userAgent.substring(0, 50)}...`);
  
  const aBogus = generateABogus(queryString, userAgent);
  log(`  [ABOGUS] a_bogus: ${aBogus}`);
  log(`  [ABOGUS] a_bogus length: ${aBogus.length}`);

  // 构建完整 URL
  const apiUrl = `https://www.iesdouyin.com/web/api/v2/aweme/slidesinfo/?${queryString}&a_bogus=${encodeURIComponent(aBogus)}`;
  log(`  [ABOGUS] API URL: ${apiUrl.substring(0, 100)}...`);

  // 发送请求
  const resp = await fetchWithRetry(apiUrl, {
    method: 'GET',
    headers: {
      'accept': 'application/json, text/plain, */*',
      'accept-language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'agw-js-conv': 'str',
      'cookie': DY_HEADERS.Cookie || '',
      'Referer': referer,
      'User-Agent': userAgent
    }
  });

  const text = await resp.text();
  log(`  [ABOGUS] Response status: ${resp.status}`);
  log(`  [ABOGUS] Response length: ${text.length}`);

  try {
    const json = JSON.parse(text);
    
    // 检查错误
    if (json.status_code !== 0) {
      log(`  [ABOGUS] API 错误: status_code=${json.status_code}, msg=${json.status_msg}`);
      return null;
    }

    // 提取 slides 信息
    const item = json.aweme_details?.[0];
    if (!item) {
      log(`  [ABOGUS] 未找到 aweme_details`);
      return null;
    }

    log(`  [ABOGUS] 成功获取 slides 信息: aweme_id=${item.aweme_id}, images=${item.images?.length}`);

    return {
      aweme_id: item.aweme_id,
      images: item.images
    };
  } catch (e) {
    log(`  [ABOGUS] JSON 解析失败: ${e.message}`);
    log(`  [ABOGUS] Response preview: ${text.substring(0, 200)}`);
    return null;
  }
}
