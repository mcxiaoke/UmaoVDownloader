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

let log = () => {};

/**
 * 判断是否支持该 URL
 */
export function canParse(url) {
  return /(xiaohongshu\.com|xhslink\.com)/.test(url);
}

/**
 * 解析入口
 * @param {string} url - 小红书链接
 * @param {boolean} debug - 是否开启调试日志
 */
export async function parse(url, debug = false) {
  log = debug ? (...args) => console.log("  [XHS]", ...args) : () => {};

  log(`开始解析: ${url}`);

  const extracted = extractUrl(url);
  log(`提取URL: ${extracted}`);

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
    log(`  最佳视频: ${result.videoUrl?.substring(0, 80)}...`);
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
async function buildResult(note) {
  const id = note.noteId || note.id || "";
  const title = note.title || "";
  const desc = note.desc || "";

  // 封面图
  const coverUrl = extractCoverUrl(note);

  // 提取图片列表
  const imageUrls = extractImageUrls(note);

  // 提取视频信息 (async)
  const videoInfo = await extractVideoInfo(note);

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
    result.formatInfo = videoInfo.formatInfo;
    result.allCandidates = videoInfo.allCandidates;
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
      // 从 infoList 中提取原始 fileId 构建高清 URL
      // 避免使用带 !style_xxx 后缀的压缩 URL
      if (img.infoList?.length > 0) {
        const best = img.infoList[img.infoList.length - 1];
        if (best.url) {
          // 从 URL 中提取 fileId 和路径前缀（去掉时间戳和压缩参数）
          // URL 格式: http://xxx/时间戳/签名/[notes_uhdr/]fileId!style_xxx
          const result = extractFileIdFromUrl(best.url);
          if (result) {
            // 使用 sns-img-hw 域名构建高清无水印 URL，保留前缀
            return `https://sns-img-hw.xhscdn.com/${result.prefix}${result.fileId}?imageView2/2/w/0/format/jpg`;
          }
          return best.url;
        }
      }

      // 其次尝试 traceId 构建（备用）
      const traceId = img.traceId || img.infoList?.[0]?.imageScene?.traceId;
      if (traceId) {
        return `https://sns-img-hw.xhscdn.com/${traceId}?imageView2/2/w/0/format/jpg`;
      }

      // 最后备用：urlDefault 或 url
      return img.urlDefault || img.url || null;
    })
    .filter(Boolean);
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
      // 检查是否有 notes_uhdr 前缀
      const prefix = pathParts.includes("notes_uhdr") ? "notes_uhdr/" : "";
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
        log && log(`    找到可用CDN: ${variant.url.substring(0, 60)}... (${(size / 1024 / 1024).toFixed(2)}MB)`);
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
      log(`      ${c.url.substring(0, 80)}...`);
    }
  }

  return {
    qualities,
    qualityUrls,
    videoUrl: bestUrl,
    formatInfo,
    allCandidates: candidateUrls,
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
