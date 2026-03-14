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
import { writeFileSync, mkdirSync, existsSync } from "fs";
import { join } from "path";

const XHS_UA =
  "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) " +
  "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1";

const XHS_HEADERS = {
  "User-Agent": XHS_UA,
  "Referer": "https://www.xiaohongshu.com/",
  "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
  "Accept-Language": "zh-CN,zh;q=0.9",
};

let log = () => {};
let currentShortId = ''; // 当前解析的短ID，用于调试文件名

/**
 * 判断是否支持该 URL
 */
export function canParse(url) {
  return /(xiaohongshu\.com|xhslink\.com)/.test(url);
}

/**
 * 从URL中提取短ID (如 xhslink.com/o/98zulilsiJI 中的 98zulilsiJI)
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
 * 解析入口
 * @param {string} url - 小红书链接
 * @param {boolean} debug - 是否开启调试日志
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
function saveDebugJson(data, prefix) {
  try {
    const tempDir = join(process.cwd(), 'temp');
    if (!existsSync(tempDir)) {
      mkdirSync(tempDir, { recursive: true });
    }
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const idPrefix = currentShortId ? `${currentShortId}_` : '';
    const filePath = join(tempDir, `${idPrefix}${prefix}_${timestamp}.json`);
    writeFileSync(filePath, JSON.stringify(data, null, 2));
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

  // 提取视频信息 (async)
  const videoInfo = await extractVideoInfo(note);

  // 判断类型：有视频优先视频，否则图片
  const type = videoInfo ? "video" : imageList.length > 0 ? "image" : "unknown";

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
    // 兼容旧格式：同时提供 imageUrls（大图URL数组）和 imageList（含thumb/full的对象数组）
    result.imageUrls = imageList.map(i => i.full);
    result.imageThumbs = imageList.map(i => i.thumb);
    result.imageList = imageList;
    result.imageCount = imageList.length;
    // 检测是否有 Live Photo
    result.isLivePhoto = imageList.some(i => i.isLivePhoto);
  } else if (type === "video" && videoInfo) {
    // 只返回最高画质视频
    result.videoUrl = videoInfo.videoUrl;
    result.quality = videoInfo.qualities[0] ?? null;
    result.videoSize = videoInfo.size ?? null;
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
