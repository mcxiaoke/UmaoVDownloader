/**
 * parser.js — 抖音链接解析核心（Node.js 22+，ESM）
 *
 * 数据来源：iesdouyin.com 分享页 HTML 内嵌的 window._ROUTER_DATA JSON
 * 不依赖任何 Cookie / Token，匿名可用。
 */

const MOBILE_UA =
  "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) " +
  "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1";

const REFERER = "https://www.douyin.com/";

// aweme/v1/play/ 无水印播放接口
const PLAY_BASE = "https://aweme.snssdk.com/aweme/v1/play/";

// 各质量档 ratio 字符串（与 Dart 端保持一致）
const QUALITY_RATIOS = ["2160p", "1080p", "720p", "480p", "360p"];

// ── 工具函数 ─────────────────────────────────────────────────────────────────

/** 从短链跟随重定向，同时获取落地页 HTML，返回 { html, finalUrl, shareId } */
async function resolveAndFetch(url) {
  const shareId = url.match(/v\.douyin\.com\/([A-Za-z0-9_-]+)/)?.[1] ?? null;
  const resp = await fetch(url, {
    redirect: "follow",
    headers: { "User-Agent": MOBILE_UA, Referer: REFERER },
  });
  if (!resp.ok) throw new Error(`HTTP ${resp.status} 跟随重定向失败`);
  // finalUrl 为 iesdouyin.com/share/video(note)/{id}/?... 带完整 query 参数
  const finalUrl = resp.url;
  // 若落地页已含数据（iesdouyin share 页），直接用；否则再请求一次带 query 的 URL
  const html = await resp.text();
  return { html, finalUrl, shareId };
}

/** 不够时的降级：用完整 URL 重新 fetch share 页（finalUrl 已含 query 参数） */
async function fetchSharePageByUrl(fullUrl) {
  const resp = await fetch(fullUrl, {
    headers: { "User-Agent": MOBILE_UA, Referer: REFERER },
  });
  if (!resp.ok) throw new Error(`HTTP ${resp.status} fetching share page`);
  return resp.text();
}

/** 从最终 URL 提取 aweme_id */
function extractVideoId(url) {
  const m = url.match(/\/(?:video|note|slides)\/(\d+)/);
  return m ? m[1] : null;
}

/** 判断是否为图文 note 类型 */
function isNoteUrl(url) {
  return url.includes("/note/");
}

/** 从 HTML 中提取 window._ROUTER_DATA 对象 */
function extractRouterData(html) {
  const marker = "window._ROUTER_DATA = ";
  const start = html.indexOf(marker);
  if (start === -1) throw new Error("未找到 _ROUTER_DATA，页面结构可能已变化");

  // 用括号配对法提取完整 JSON（避免截断嵌套结构）
  let depth = 0,
    i = start + marker.length,
    end = -1;
  for (; i < html.length; i++) {
    if (html[i] === "{") depth++;
    else if (html[i] === "}") {
      depth--;
      if (depth === 0) {
        end = i;
        break;
      }
    }
  }
  if (end === -1) throw new Error("_ROUTER_DATA JSON 截断，解析失败");
  return JSON.parse(html.substring(start + marker.length, end + 1));
}

/**
 * 从 _ROUTER_DATA 中提取 item（aweme 对象）
 * page key 形如 "video_(id)/page" 或 "note_(id)/page"
 */
function extractItem(routerData) {
  const loaderData = routerData.loaderData;
  const pageKey = Object.keys(loaderData).find((k) => k.includes("/page"));
  if (!pageKey) throw new Error("未找到 loaderData page key");

  const item = loaderData[pageKey]?.videoInfoRes?.item_list?.[0];
  if (!item)
    throw new Error("videoInfoRes.item_list 为空，内容可能已下架或需登录");
  return item;
}

/**
 * 构造无水印视频播放 URL
 * play_addr.url_list[0] 为 playwm（带水印），替换为 play 即无水印
 */
function buildPlayUrl(videoFileId, ratio = "1080p", line = 0) {
  return `${PLAY_BASE}?video_id=${videoFileId}&ratio=${ratio}&line=${line}`;
}

/** 从 item 中提取可用清晰度列表（从高到低） */
function extractQualities(item) {
  // bit_rate 数组优先（包含多清晰度）；没有时只有 play_addr 一档
  const bitRates = item.video?.bit_rate;
  if (Array.isArray(bitRates) && bitRates.length > 0) {
    // gear_name 形如 "gear_1080p"，提取数字部分
    return bitRates
      .map((b) => {
        const ratio = b.gear_name?.replace("gear_", "") ?? b.quality_type ?? "";
        return { ratio, videoFileId: b.play_addr?.uri };
      })
      .filter((q) => QUALITY_RATIOS.includes(q.ratio) && q.videoFileId)
      .sort(
        (a, b) =>
          QUALITY_RATIOS.indexOf(a.ratio) - QUALITY_RATIOS.indexOf(b.ratio),
      );
  }

  // 只有 play_addr 一档，猜测清晰度
  const uri = item.video?.play_addr?.uri;
  if (!uri) return [];
  const h = item.video?.height ?? 0;
  const ratio =
    h >= 2160 ? "2160p" : h >= 1080 ? "1080p" : h >= 720 ? "720p" : "480p";
  return [{ ratio, videoFileId: uri }];
}

/** 从图文 item.images 中提取最佳质量图片 URL 列表 */
function extractImageUrls(item) {
  const images = item.images;
  if (!Array.isArray(images) || images.length === 0) return [];

  return images
    .map((img) => {
      const urls = img.url_list ?? [];
      // 优先取 lqen-new（高清无水印），fallback 第一个
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

// ── 主入口 ───────────────────────────────────────────────────────────────────

/**
 * 解析抖音链接，返回结构化 VideoInfo 对象
 *
 * @param {string} url 任意抖音分享链接（短链 / 长链 / 带文字的分享文本）
 * @returns {Promise<VideoInfo>}
 */
export async function parse(url) {
  // 从文本中提取第一个 HTTP URL
  const extracted = url.match(/https?:\/\/[^\s，,。]+/)?.[0] ?? url;

  // 一次 fetch 跟随重定向并获取 HTML（finalUrl 带完整 query 参数）
  const { html: rawHtml, finalUrl, shareId } = await resolveAndFetch(extracted);
  const awemeId = extractVideoId(finalUrl);
  if (!awemeId) throw new Error(`无法从链接提取视频 ID，最终 URL: ${finalUrl}`);

  const isNote = isNoteUrl(finalUrl);

  // 若重定向落地页就是 iesdouyin share 页且含数据则直接用
  // 否则（如落地到 www.douyin.com SPA 壳）重新请求带 query 参数的 iesdouyin URL
  let html = rawHtml;
  if (!html.includes("window._ROUTER_DATA")) {
    // 用 finalUrl 中的 awemeId 构造 iesdouyin share URL，保留原始 query 参数
    const shareBase = `https://www.iesdouyin.com/share/${isNote ? "note" : "video"}/${awemeId}/`;
    const origParams = new URL(finalUrl).search;
    html = await fetchSharePageByUrl(shareBase + origParams);
  }
  const routerData = extractRouterData(html);
  const item = extractItem(routerData);

  const isImagePost = Array.isArray(item.images) && item.images.length > 0;

  /** @type {VideoInfo} */
  const info = {
    type: isImagePost ? "image" : "video",
    id: item.aweme_id ?? awemeId,
    shareId,
    title: item.desc ?? "",
    coverUrl: item.video?.cover?.url_list?.[0] ?? null,
    width: item.video?.width ?? null,
    height: item.video?.height ?? null,
  };

  if (isImagePost) {
    info.imageUrls = extractImageUrls(item);
    info.imageCount = info.imageUrls.length;
    info.musicTitle = item.music?.title ?? null;
    info.musicUrl = item.music?.play_url?.url_list?.[0] ?? null;
  } else {
    const qualities = extractQualities(item);
    // qualityUrls: { "1080p": "https://aweme...", ... }
    info.qualities = qualities.map((q) => q.ratio);
    info.qualityUrls = Object.fromEntries(
      qualities.map((q) => [q.ratio, buildPlayUrl(q.videoFileId, q.ratio)]),
    );
    // 最佳画质 URL（供直接使用）
    info.videoUrl = info.qualityUrls[qualities[0]?.ratio] ?? null;
  }

  return info;
}

/**
 * @typedef {Object} VideoInfo
 * @property {'video'|'image'} type
 * @property {string} id
 * @property {string|null} shareId
 * @property {string} title
 * @property {string|null} coverUrl
 * @property {number|null} width
 * @property {number|null} height
 * @property {string[]|undefined} qualities       - 视频专有，从高到低
 * @property {Object|undefined}  qualityUrls      - 视频专有，{ "1080p": url, ... }
 * @property {string|null|undefined} videoUrl     - 视频专有，最佳质量 URL
 * @property {string[]|undefined}  imageUrls      - 图文专有
 * @property {number|undefined}    imageCount     - 图文专有
 * @property {string|null|undefined} musicTitle   - 图文专有
 * @property {string|null|undefined} musicUrl     - 图文专有
 */
