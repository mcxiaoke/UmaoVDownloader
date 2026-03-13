/**
 * douyin.js — 抖音解析器
 */

import {
  MOBILE_UA,
  DEFAULT_HEADERS,
  fetchWithRetry,
  extractWindowData,
  extractUrl,
} from "./common.js";

// aweme/v1/play/ 无水印播放接口
const PLAY_BASE = "https://aweme.snssdk.com/aweme/v1/play/";

// 各质量档 ratio 字符串
const QUALITY_RATIOS = ["2160p", "1080p", "720p", "480p", "360p"];

/**
 * 判断是否支持该 URL
 */
export function canParse(url) {
  return /(v\.)?douyin\.com|iesdouyin\.com/.test(url);
}

/**
 * 解析入口
 */
export async function parse(url) {
  const extracted = extractUrl(url);

  // 跟随重定向获取 HTML
  const { html: rawHtml, finalUrl, shareId } = await resolveAndFetch(extracted);
  const awemeId = extractVideoId(finalUrl);
  if (!awemeId) {
    throw new Error(`无法从链接提取视频 ID，最终 URL: ${finalUrl}`);
  }

  const isNote = finalUrl.includes("/note/");

  // 若页面不含数据，重新请求 share 页
  let html = rawHtml;
  if (!html.includes("window._ROUTER_DATA")) {
    const shareBase = `https://www.iesdouyin.com/share/${isNote ? "note" : "video"}/${awemeId}/`;
    const origParams = new URL(finalUrl).search;
    html = await fetchSharePage(shareBase + origParams);
  }

  const routerData = extractWindowData(html, "_ROUTER_DATA");
  if (!routerData) {
    throw new Error("未找到 _ROUTER_DATA");
  }

  const item = extractItem(routerData);
  if (!item) {
    throw new Error("videoInfoRes.item_list 为空");
  }

  const isImagePost = Array.isArray(item.images) && item.images.length > 0;

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

  if (isImagePost) {
    info.imageUrls = extractImageUrls(item);
    info.imageCount = info.imageUrls.length;
    info.musicTitle = item.music?.title ?? null;
    info.musicUrl = extractMusicUrl(item);
  } else {
    const qualities = extractQualities(item);
    info.qualities = qualities.map((q) => q.ratio);
    info.qualityUrls = Object.fromEntries(
      qualities.map((q) => [q.ratio, buildPlayUrl(q.videoFileId, q.ratio)]),
    );
    info.videoUrl = info.qualityUrls[qualities[0]?.ratio] ?? null;
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
  const bitRates = item.video?.bit_rate;
  if (Array.isArray(bitRates) && bitRates.length > 0) {
    return bitRates
      .map((b) => ({
        ratio: b.gear_name?.replace("gear_", "") ?? b.quality_type ?? "",
        videoFileId: b.play_addr?.uri,
      }))
      .filter((q) => QUALITY_RATIOS.includes(q.ratio) && q.videoFileId)
      .sort(
        (a, b) =>
          QUALITY_RATIOS.indexOf(a.ratio) - QUALITY_RATIOS.indexOf(b.ratio),
      );
  }

  const uri = item.video?.play_addr?.uri;
  if (!uri) return [];

  const h = item.video?.height ?? 0;
  const ratio =
    h >= 2160 ? "2160p" : h >= 1080 ? "1080p" : h >= 720 ? "720p" : "480p";
  return [{ ratio, videoFileId: uri }];
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

function extractMusicUrl(item) {
  const mUrl = item.music?.play_url?.url_list?.[0];
  if (mUrl) return mUrl;

  const playUri = item.video?.play_addr?.uri;
  if (typeof playUri === "string" && playUri.includes(".mp3")) {
    return playUri;
  }
  return null;
}
