/**
 * xiaohongshu.js — 小红书平台解析器
 *
 * 功能概述：
 * 本解析器专门处理小红书平台（xiaohongshu.com）的内容解析。
 * 支持图文笔记、视频笔记、Live Photo等多种内容类型。
 * 能够提取高清无水印图片、多画质视频、背景音乐等。
 *
 * 数据源：
 * 主要通过解析页面中的window.__INITIAL_STATE__ JavaScript变量获取数据
 * 支持SSR数据作为备用数据源
 *
 * 主要特性：
 * - 支持小红书短链接（xhslink.com）解析
 * - 提取高清无水印图片（自动去除水印）
 * - 多画质视频解析（H.264/H.265/AV1编码）
 * - Live Photo动态图片支持
 * - CDN智能切换，提高下载成功率
 * - 详细的调试信息输出
 *
 * 支持的内容类型：
 * - 图文笔记：多图片+背景音乐
 * - 视频笔记：多画质视频流
 * - Live Photo：图片+短视频组合
 */

import {
  fetchWithRetry,
  extractUrl,
} from "./common.js";
import fs from "fs-extra";           // 文件系统操作
import { join } from "path";        // 路径处理

// 小红书专用User-Agent，模拟iOS移动端访问
const XHS_UA =
  "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) " +
  "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1";

// 小红书专用请求头
const XHS_HEADERS = {
  "User-Agent": XHS_UA,
  "Referer": "https://www.xiaohongshu.com/",
  "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
  "Accept-Language": "zh-CN,zh;q=0.9",
};

// 条件日志函数
let log = () => {};

// 当前解析的短ID，用于调试文件命名
let currentShortId = '';

/**
 * 判断是否支持解析该URL
 * 通过正则表达式检测URL是否属于小红书平台
 * @param {string} url - 待检测的URL
 * @returns {boolean} 是否支持解析
 */
export function canParse(url) {
  return /(xiaohongshu\.com|xhslink\.com)/.test(url);
}

/**
 * 从URL中提取短ID
 * 小红书短链接格式：xhslink.com/o/短ID
 * @param {string} url - 小红书链接
 * @returns {string} 提取的短ID，失败返回空字符串
 */
function extractShortId(url) {
  const match = url.match(/xhslink\.com\/o\/([A-Za-z0-9_-]+)/);
  if (match) return match[1];
  // 备用：从路径中提取
  const pathMatch = url.match(/\/item\/([A-Za-z0-9]+)/);
  if (pathMatch) return pathMatch[1];
  return '';
}

/**
 * 小红书链接解析主入口
 * 负责协调整个解析流程，包括URL重定向、数据提取、内容识别
 * @param {string} url - 小红书链接（支持短链接和完整链接）
 * @param {boolean} debug - 是否开启调试日志
 * @returns {Promise<VideoInfo>} 解析结果
 */
export async function parse(url, debug = false) {
  log = debug ? (...args) => console.log("  [XHS]", ...args) : () => {};
  currentShortId = extractShortId(url); // 设置当前短ID

  log(`开始解析: ${url}`);

  const extracted = extractUrl(url);
  log(`提取URL: ${extracted}`);
  log(`短ID: ${currentShortId}`);

  // 跟随重定向获取真实 URL 和 HTML
  log("→ 请求页面...");
  const { html, finalUrl } = await resolveXhsUrl(extracted);
  log(`  最终URL: ${finalUrl}`);
  log(`  HTML长度: ${html.length} bytes`);

  // 尝试从 __INITIAL_STATE__ 提取数据
  log("→ 提取 __INITIAL_STATE__...");
  let data = extractInitialState(html);

  // 如果失败，尝试 SSR 数据
  if (!data) {
    log("  未找到 __INITIAL_STATE__, 尝试 SSR 数据...");
    data = extractSSRData(html);
  }

  if (!data) {
    throw new Error("未找到 __INITIAL_STATE__ 或 SSR 数据");
  }
  log("  ✓ 数据提取成功");

  // 提取笔记数据
  log("→ 提取笔记数据...");
  const note = extractNoteData(data);
  if (!note) {
    throw new Error("无法提取笔记数据");
  }
  log(`  ✓ noteId: ${note.noteId || note.id || "unknown"}`);
  log(`  ✓ title: ${(note.title || note.desc || "").substring(0, 50)}`);
  log(`  ✓ type: ${note.video ? "video" : note.imageList ? "image" : "unknown"}`);

  const result = await buildResult(note);

  log("→ 构建结果:");
  log(`  type: ${result.type}`);
  log(`  imageCount: ${result.imageCount || 0}`);
  if (result.qualities) {
    log(`  qualities: ${result.qualities.join(", ")}`);
    log(`  最佳视频: ${result.videoUrl}`);
    // 打印所有候选 URL
    if (result.allCandidates?.length > 0) {
      log("  所有候选流 (按大小排序):");
      const sorted = [...result.allCandidates].sort((a, b) => (b.size || 0) - (a.size || 0));
      for (let i = 0; i < Math.min(sorted.length, 6); i++) {
        const c = sorted[i];
        const sizeMB = c.size ? (c.size / 1024 / 1024).toFixed(2) + "MB" : "unknown";
        log(`    #${i + 1} ${c.codec}: ${sizeMB} ${c.width}x${c.height}`);
        log(`        ${c.url}`);
      }
    }
  }
  if (result.imageUrls?.length > 0) {
    log(`  imageUrls[0]: ${result.imageUrls[0]}`);
    // 打印域名供检查
    try {
      const urlObj = new URL(result.imageUrls[0]);
      log(`  图片域名: ${urlObj.hostname}`);
    } catch {}
  }

  return result;
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
 * 优先使用 JSON 解析（将 undefined 替换为 null），失败则回退到手动提取
 */
function extractInitialState(html) {
  // 方法1: 先尝试用 JSON 解析
  const jsonResult = extractInitialStateJson(html);
  if (jsonResult) {
    log("  使用 JSON 解析成功");
    return jsonResult;
  }

  // 方法2: 回退到手动提取 + new Function 解析
  log("  JSON 解析失败，回退到手动提取");
  return extractInitialStateLegacy(html);
}

/**
 * 使用 JSON 解析提取 __INITIAL_STATE__
 * 将 JavaScript undefined 替换为 null 使其成为合法 JSON
 */
function extractInitialStateJson(html) {
  // 匹配 window.__INITIAL_STATE__ = {...} 或 window.__INITIAL_STATE__={...}
  const match = html.match(/window\.__INITIAL_STATE__\s*=\s*(\{[\s\S]*?\})(?:;|\s*<\/script>)/);
  if (!match) return null;

  let jsonStr = match[1];

  // 将 JavaScript undefined 替换为 null
  // 匹配: : undefined, : undefined} : undefined] 等情况
  jsonStr = jsonStr.replace(/:\s*undefined\s*([,}\]])/g, ':null$1');

  try {
    const data = JSON.parse(jsonStr);
    // 保存原始 JSON 到 temp 目录供调试
    saveDebugJson(data, 'initial_state');
    return data;
  } catch (e) {
    // JSON 解析失败，返回 null 让调用方使用备用方案
    return null;
  }
}

/**
 * 保存调试 JSON 到 backend/temp 目录
 */
async function saveDebugJson(data, prefix) {
  try {
    const tempDir = join(process.cwd(), 'temp');
    await fs.ensureDir(tempDir);
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const idPrefix = currentShortId ? `${currentShortId}_` : '';
    const filePath = join(tempDir, `xhs_${idPrefix}${prefix}_${timestamp}.json`);
    await fs.writeFile(filePath, JSON.stringify(data, null, 2));
    log(`  调试 JSON 已保存: ${filePath}`);
  } catch (e) {
    // 保存失败不影响主流程
    log(`  保存调试 JSON 失败: ${e.message}`);
  }
}

/**
 * 备用方案：手动提取 + new Function 解析
 * 处理边界情况（如嵌套引号、特殊字符等）
 */
function extractInitialStateLegacy(html) {
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
  if (note) {
    saveDebugJson(note, 'note_data');
    return note;
  }

  // 备用路径
  if (data.note?.noteDetailMap) {
    const noteMap = data.note.noteDetailMap;
    const keys = Object.keys(noteMap);
    if (keys.length > 0) {
      const note = noteMap[keys[0]];
      saveDebugJson(note, 'note_data');
      return note;
    }
  }

  return null;
}

/**
 * 智能检测小红书作品类型
 * 根据数据结构特征判断：video / livephoto / image
 * 
 * 判断逻辑：
 * 1. 有根级别 video.media.stream 且包含有效视频流 → video（普通视频）
 * 2. 无根级别 video，但 imageList 中有 livePhoto=true 且带视频流 → livephoto（实况图）
 * 3. 否则 → image（纯图文）
 * 
 * @param {object} note - 笔记数据
 * @returns {"video"|"livephoto"|"image"} 媒体类型
 */
function detectMediaType(note) {
  // 1. 检查是否为普通视频（根级别有 video 字段且包含有效视频流）
  const rootStream = note.video?.media?.stream;
  if (rootStream && typeof rootStream === "object") {
    const hasValidStream = ["h264", "h265", "av1", "origin"].some(
      codec => Array.isArray(rootStream[codec]) && rootStream[codec].length > 0
    );
    if (hasValidStream) {
      return "video";
    }
  }

  // 2. 检查是否为实况图（imageList 中有 livePhoto=true 且带视频流）
  const imageList = note.imageList || note.images || [];
  if (Array.isArray(imageList) && imageList.length > 0) {
    const hasLivePhoto = imageList.some(img => {
      if (img.livePhoto !== true) return false;
      const stream = img.stream;
      if (!stream || typeof stream !== "object") return false;
      return ["h264", "h265", "av1"].some(
        codec => Array.isArray(stream[codec]) && stream[codec].length > 0
      );
    });
    
    if (hasLivePhoto) {
      return "livephoto";
    }
  }

  // 3. 默认为纯图文
  return "image";
}

/**
 * 构建统一的结果对象
 */
async function buildResult(note) {
  const id = note.noteId || note.id || "";
  const title = note.title || "";
  const desc = note.desc || "";

  // 封面图
  const coverUrl = extractCoverUrl(note);

  // 提取图片列表（返回 {thumb, full} 对象数组）
  const imageList = extractImageUrls(note);

  // 使用统一的类型检测
  const mediaType = detectMediaType(note);
  log(`  类型检测: ${mediaType}`);

  const result = {
    type: mediaType,
    platform: "xiaohongshu",
    id: String(id),
    shareId: null,
    title: title || desc.substring(0, 50),
    coverUrl,
    width: note.width || null,
    height: note.height || null,
  };

  // 根据类型填充详细内容
  if (mediaType === "video") {
    // 普通视频：提取视频流
    const videoInfo = await extractVideoInfo(note);
    if (videoInfo) {
      result.videoUrl = videoInfo.videoUrl;
      result.quality = videoInfo.qualities[0] ?? null;
      result.videoSize = videoInfo.size ?? null;
      result.width = videoInfo.width ?? result.width;
      result.height = videoInfo.height ?? result.height;
    }
  } else if (mediaType === "livephoto") {
    // 实况图：图片列表 + 实况视频URL列表
    result.imageUrls = imageList.map(i => i.full);
    result.imageThumbs = imageList.map(i => i.thumb);
    result.imageList = imageList;
    result.imageCount = imageList.length;
    
    // 提取实况视频URL列表
    const livePhotoUrls = imageList
      .filter(img => img.isLivePhoto && img.videoUrl)
      .map(img => img.videoUrl);
    result.livePhotoUrls = livePhotoUrls;
    result.livePhotoCount = livePhotoUrls.length;
    
    // 用第一个实况视频作为默认视频
    if (livePhotoUrls.length > 0) {
      result.videoUrl = livePhotoUrls[0];
    }
  } else {
    // 纯图文
    result.imageUrls = imageList.map(i => i.full);
    result.imageThumbs = imageList.map(i => i.thumb);
    result.imageList = imageList;
    result.imageCount = imageList.length;
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
    .map((img, idx) => {
      // fullOrig: 带水印原图, fullNoWater: 无水印图(CDN替换)
      const result = { 
        thumb: null, 
        full: null, 
        fullOrig: null, 
        fullNoWater: null,
        videoUrl: null, 
        isLivePhoto: false 
      };

      // 提取 Live Photo 视频 URL
      if (img.livePhoto === true && img.stream) {
        const videoStream = img.stream.h264?.[0] || img.stream.h265?.[0] || img.stream.av1?.[0];
        if (videoStream?.masterUrl) {
          result.videoUrl = videoStream.masterUrl;
          result.isLivePhoto = true;
          log(`  图片 ${idx + 1}: 检测到 Live Photo, 视频 URL: ${videoStream.masterUrl}`);
        }
      }

      // 调试：打印 infoList 结构
      if (img.infoList?.length > 0) {
        log(`  图片 ${idx + 1}: infoList 有 ${img.infoList.length} 项`);
        img.infoList.forEach((item, i) => {
          log(`    [${i}] imageScene: ${item.imageScene}, url: ${item.url}`);
        });
        
        // 找大图：WB_DFT > H5_DTL > 其他含 DFT 的
        const dftScenes = ["WB_DFT", "H5_DTL"];
        for (const scene of dftScenes) {
          const match = img.infoList.find(i => i.imageScene === scene && i.url);
          if (match?.url) {
            result.fullOrig = match.url;
            log(`  图片 ${idx + 1}: 大图(原图)使用 ${scene}`);
            break;
          }
        }
        if (!result.fullOrig) {
          const dftMatch = img.infoList.find(i => i.imageScene?.includes("DFT") && i.url);
          if (dftMatch?.url) {
            result.fullOrig = dftMatch.url;
            log(`  图片 ${idx + 1}: 大图(原图)使用 ${dftMatch.imageScene}`);
          }
        }

        // 找预览图：WB_PRV > H5_PRV > urlPre
        const prvScenes = ["WB_PRV", "H5_PRV"];
        for (const scene of prvScenes) {
          const match = img.infoList.find(i => i.imageScene === scene && i.url);
          if (match?.url) {
            result.thumb = match.url;
            log(`  图片 ${idx + 1}: 预览图使用 ${scene}`);
            break;
          }
        }
      } else {
        log(`  图片 ${idx + 1}: 无 infoList`);
      }

      // 外层字段作为备选
      if (!result.fullOrig) {
        if (img.urlDefault) {
          result.fullOrig = img.urlDefault;
          log(`  图片 ${idx + 1}: 大图(原图)使用 urlDefault`);
        } else if (img.url) {
          result.fullOrig = img.url;
          log(`  图片 ${idx + 1}: 大图(原图)使用 url`);
        }
      }

      if (!result.thumb) {
        if (img.urlPre) {
          result.thumb = img.urlPre;
          log(`  图片 ${idx + 1}: 预览图使用 urlPre`);
        } else if (img.urlDefault) {
          result.thumb = img.urlDefault;
          log(`  图片 ${idx + 1}: 预览图使用 urlDefault`);
        }
      }

      // 生成无水印 URL
      // 正确格式: https://sns-img-hw.xhscdn.com/notes_pre_post/{fileId}?imageView2/2/w/0/format/jpg
      if (result.fullOrig) {
        result.fullNoWater = buildNoWatermarkUrl(result.fullOrig);
        log(`  图片 ${idx + 1}: 无水印 URL: ${result.fullNoWater}`);
      }

      // 决定使用哪个作为 full: 优先使用无水印图
      if (result.fullNoWater) {
        result.full = result.fullNoWater;
        log(`  图片 ${idx + 1}: 使用无水印图`);
      } else {
        result.full = result.fullOrig;
        log(`  图片 ${idx + 1}: 无水印图不可用，使用原图`);
      }

      // 如果没有大图，用预览图代替
      if (!result.full && result.thumb) {
        result.full = result.thumb;
        log(`  图片 ${idx + 1}: 无大图，用预览图代替`);
      }
      // 如果没有预览图，用大图代替
      if (!result.thumb && result.full) {
        result.thumb = result.full;
        log(`  图片 ${idx + 1}: 无预览图，用大图代替`);
      }

      if (!result.full && !result.thumb) {
        log(`  图片 ${idx + 1}: 无可用 URL`);
        return null;
      }

      return result;
    })
    .filter(Boolean);
}

/**
 * 构建无水印图片 URL
 * 原URL: http://sns-webpic-qc.xhscdn.com/202603132203/xxx/notes_pre_post/1040g...!h5_1080jpg
 * 目标:   https://sns-img-hw.xhscdn.com/notes_pre_post/1040g...?imageView2/2/w/0/format/jpg
 */
function buildNoWatermarkUrl(originalUrl) {
  if (!originalUrl) return null;

  try {
    const urlObj = new URL(originalUrl);
    const pathParts = urlObj.pathname.split("/").filter(Boolean);

    // 提取 fileId（最后一部分，去掉 ! 后缀）
    const lastPart = pathParts[pathParts.length - 1];
    const fileId = lastPart.split("!")[0];

    if (!fileId || !/^[a-z0-9]+$/i.test(fileId)) {
      return null;
    }

    // 确定路径前缀（注意：有单数 note 和复数 notes 两种形式）
    let prefix = "";
    if (pathParts.includes("notes_pre_post")) {
      prefix = "notes_pre_post/";
    } else if (pathParts.includes("note_pre_post_uhdr")) {
      prefix = "note_pre_post_uhdr/";
    } else if (pathParts.includes("notes_uhdr")) {
      prefix = "notes_uhdr/";
    }

    // 构建无水印 URL
    return `https://sns-img-hw.xhscdn.com/${prefix}${fileId}?imageView2/2/w/0/format/jpg`;
  } catch {
    return null;
  }
}

/**
 * 从小红书 URL 中提取 fileId 和路径前缀
 * 输入: http://sns-webpic-qc.xhscdn.com/20260313/xxx/1040g00831tjqb2q67o705nra153g8dr7i3l0j38!style_d4c824bab532bfe9
 * 输出: { fileId: "1040g00831tjqb2q67o705nra153g8dr7i3l0j38", prefix: "" }
 *
 * 输入: http://sns-webpic-qc.xhscdn.com/20260313/xxx/notes_uhdr/1040g3qo31tjts3bemi705nra153g8dr74gm9keg!style_xxx
 * 输出: { fileId: "1040g3qo31tjts3bemi705nra153g8dr74gm9keg", prefix: "notes_uhdr/" }
 */
function extractFileIdFromUrl(url) {
  if (!url) return null;
  try {
    const urlObj = new URL(url);
    const pathParts = urlObj.pathname.split("/").filter(Boolean);
    // 取最后一部分，去掉 !style_xxx 后缀
    const lastPart = pathParts[pathParts.length - 1];
    // 去掉 ! 后面的内容
    const fileId = lastPart.split("!")[0];
    // 验证 fileId 格式（通常是 1040g 开头）
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
    // 解析失败返回 null
  }
  return null;
}

async function extractVideoInfo(note) {
  const video = note.video;
  if (!video) return null;

  // 从小红书媒体流中提取视频 URL
  const stream = video.media?.stream;
  if (!stream) return null;

  const qualities = [];
  const qualityUrls = {};
  const formatInfo = {}; // 存储码率信息用于调试
  const candidateUrls = []; // 存储所有候选URL

  // 尝试各种编码格式
  const formats = [
    { key: "origin", name: "原画" },
    { key: "h264", name: "HD" },
    { key: "h265", name: "HD (H.265)" },
    { key: "av1", name: "HD (AV1)" },
  ];

  for (const { key, name } of formats) {
    const streams = stream[key];
    if (Array.isArray(streams) && streams.length > 0) {
      // 遍历所有流，找码率最高的
      let bestStream = streams[0];
      let bestBitrate = bestStream.videoBitrate || 0;

      for (const s of streams) {
        const bitrate = s.videoBitrate || 0;
        if (bitrate > bestBitrate) {
          bestBitrate = bitrate;
          bestStream = s;
        }
        // 收集所有候选URL
        const url = s.masterUrl || s.url;
        if (url) {
          candidateUrls.push({
            url,
            bitrate: s.videoBitrate || 0,
            size: s.size || 0,
            width: s.width,
            height: s.height,
            codec: key,
          });
        }
      }

      const url = bestStream.masterUrl || bestStream.url;
      if (url) {
        qualities.push(name);
        qualityUrls[name] = url;
        formatInfo[name] = {
          bitrate: bestBitrate,
          width: bestStream.width,
          height: bestStream.height,
          size: bestStream.size,
          url: url,
        };
      }
    }
  }

  if (qualities.length === 0) return null;

  // 默认使用第一个质量的URL，如果失败再尝试切换CDN
  let bestUrl = qualityUrls[qualities[0]];
  let bestSize = formatInfo[qualities[0]]?.size || 0;

  // 验证默认URL是否可用，如果不可用则尝试切换CDN
  log && log("  验证视频URL可用性...");
  const isAvailable = await verifyUrlAvailable(bestUrl);
  if (!isAvailable) {
    log && log(`    默认URL不可用，尝试切换CDN...`);
    const cdnVariants = generateCdnVariants([{ url: bestUrl, codec: "h264" }]);
    for (const variant of cdnVariants) {
      const size = await verifyUrlAndGetSize(variant.url);
      if (size > 0) {
        log && log(`    找到可用CDN: ${variant.url} (${(size / 1024 / 1024).toFixed(2)}MB)`);
        bestUrl = variant.url;
        bestSize = size;
        break;
      }
    }
  } else {
    log && log(`    默认URL可用`);
  }

  // 打印调试信息
  if (log) {
    log("  视频流信息:");
    // 按大小排序打印
    const sorted = [...candidateUrls].sort((a, b) => (b.size || 0) - (a.size || 0));
    for (const c of sorted.slice(0, 5)) {
      const sizeMB = c.size ? (c.size / 1024 / 1024).toFixed(2) + "MB" : "unknown";
      log(`    ${c.codec}: ${c.width}x${c.height}, ${c.bitrate}bps, ${sizeMB}`);
      log(`      ${c.url}`);
    }
  }

  return {
    qualities,
    qualityUrls,
    videoUrl: bestUrl,
    size: bestSize,
  };
}

/**
 * 生成不同CDN域名的变体URL
 * 例如: sns-video-hs.xhscdn.com -> sns-video-hw.xhscdn.com
 */
function generateCdnVariants(candidates) {
  const variants = [];
  // CDN 域名映射表
  const cdnDomains = [
    "sns-video-hw.xhscdn.com",   // 华为云
    "sns-video-hs.xhscdn.com",   // 火山引擎
    "sns-video-al.xhscdn.com",   // 阿里云
    "sns-video-qn.xhscdn.com",   // 七牛
    "sns-video-bd.xhscdn.com",   // 百度云
  ];

  for (const c of candidates) {
    // 提取当前域名
    const match = c.url.match(/https:\/\/([^/]+)(\/.*)/);
    if (!match) continue;

    const [, currentDomain, path] = match;

    // 为每个CDN生成变体
    for (const domain of cdnDomains) {
      if (domain !== currentDomain) {
        const newUrl = `https://${domain}${path}`;
        variants.push({
          url: newUrl,
          codec: c.codec,
          bitrate: c.bitrate,
          width: c.width,
          height: c.height,
          source: c.url,
        });
      }
    }
  }

  return variants;
}

/**
 * 验证 URL 是否可用（HTTP 200-399 视为可用）
 */
async function verifyUrlAvailable(url) {
  const XHS_HEADERS = {
    "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X)",
    "Referer": "https://www.xiaohongshu.com/",
  };

  try {
    const resp = await fetch(url, {
      method: "HEAD",
      headers: XHS_HEADERS,
      redirect: "follow",
    });
    return resp.ok; // 200-399
  } catch {
    return false;
  }
}

/**
 * 验证 URL 并返回文件大小
 */
async function verifyUrlAndGetSize(url) {
  const XHS_HEADERS = {
    "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X)",
    "Referer": "https://www.xiaohongshu.com/",
  };

  try {
    const resp = await fetch(url, {
      method: "HEAD",
      headers: XHS_HEADERS,
      redirect: "follow",
    });
    if (resp.ok) {
      return parseInt(resp.headers.get("content-length") || "0");
    }
  } catch {
    // 忽略失败
  }
  return 0;
}
