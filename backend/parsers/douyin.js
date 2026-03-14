/**
 * douyin.js — 抖音解析器
 */

import fs from "fs-extra";
import { join } from "path";
import {
  DEFAULT_HEADERS,
  extractUrl,
  extractWindowData,
  fetchWithRetry,
  MOBILE_UA,
} from "./common.js";

// aweme/v1/play/ 无水印播放接口
const PLAY_BASE = "https://aweme.snssdk.com/aweme/v1/play/";

// 各质量档 ratio 字符串
const QUALITY_RATIOS = ["2160p", "1080p", "720p", "480p", "360p"];

let log = () => {};
let currentShortId = ""; // 当前解析的短ID，用于调试文件名

/**
 * 判断是否支持该 URL
 */
export function canParse(url) {
  return /(v\.)?douyin\.com|iesdouyin\.com/.test(url);
}

/**
 * 解析入口
 * @param {string} url - 抖音链接
 * @param {boolean} debug - 是否开启调试日志
 */
export async function parse(url, debug = false) {
  log = debug ? (...args) => console.log("  [DY]", ...args) : () => {};
  currentShortId = extractShortId(url); // 设置当前短ID

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

  const isImagePost = Array.isArray(item.images) && item.images.length > 0;
  log(
    `  ✓ 内容类型: ${isImagePost ? "图文 " + item.images.length + " 张" : "视频"}`,
  );

  const info = {
    type: isImagePost ? "image" : "video",
    platform: "douyin",
    id: item.aweme_id ?? awemeId,
    shareId,
    title: item.desc ?? "",
    coverUrl: item.video?.cover?.url_list?.[0] ?? null,
    width: item.video?.width ?? null,
    height: item.video?.height ?? null,
  };

  log("→ 构建结果:");
  if (isImagePost) {
    info.imageUrls = extractImageUrls(item);
    info.imageCount = info.imageUrls.length;
    info.musicTitle = item.music?.title ?? null;
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
    info.width = bestQuality?.width ?? info.width;
    info.height = bestQuality?.height ?? info.height;
    log(
      `  type: video, quality: ${info.quality || "none"}, size: ${info.videoSize || "unknown"}`,
    );
    log(`  videoUrl: ${info.videoUrl || "none"}`);
  }

  return info;
}

// ── 内部函数 ─────────────────────────────────────────────────────────────────

async function resolveAndFetch(url) {
  const shareId = url.match(/v\.douyin\.com\/([A-Za-z0-9_-]+)/)?.[1] ?? null;
  const resp = await fetchWithRetry(url, {
    redirect: "follow",
    headers: DEFAULT_HEADERS,
  });

  const finalUrl = resp.url;
  const html = await resp.text();
  return { html, finalUrl, shareId };
}

async function fetchSharePage(fullUrl) {
  const resp = await fetchWithRetry(fullUrl, { headers: DEFAULT_HEADERS });
  return resp.text();
}

function extractVideoId(url) {
  const m = url.match(/\/(?:video|note|slides)\/(\d+)/);
  return m ? m[1] : null;
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
  const match = url.match(/v\.douyin\.com\/([A-Za-z0-9_-]+)/);
  if (match) return match[1];
  // 备用：从路径中提取
  const pathMatch = url.match(/\/(?:video|note|slides)\/(\d+)/);
  if (pathMatch) return pathMatch[1];
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
