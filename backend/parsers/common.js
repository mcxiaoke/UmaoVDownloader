/**
 * common.js — 通用工具和常量
 */

// 移动端 User-Agent
export const MOBILE_UA =
  "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) " +
  "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1";

// 默认请求头
export const DEFAULT_HEADERS = {
  "User-Agent": MOBILE_UA,
  "Referer": "https://www.douyin.com/",
};

/**
 * 带重试的 fetch
 */
export async function fetchWithRetry(url, options = {}, retries = 2) {
  for (let i = 0; i < retries; i++) {
    try {
      const resp = await fetch(url, options);
      if (resp.ok) return resp;
      if (i === retries - 1) throw new Error(`HTTP ${resp.status}`);
    } catch (e) {
      if (i === retries - 1) throw e;
      await delay(500 * (i + 1));
    }
  }
  throw new Error("请求失败");
}

/**
 * 延迟函数
 */
export function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * 从 HTML 中提取 window.XXX 数据
 * @param {string} html - HTML 内容
 * @param {string} varName - 变量名，如 "_ROUTER_DATA"
 * @returns {object|null}
 */
export function extractWindowData(html, varName) {
  const marker = `window.${varName} = `;
  const start = html.indexOf(marker);
  if (start === -1) return null;

  let depth = 0;
  let inString = false;
  let escaped = false;
  let i = start + marker.length;

  for (; i < html.length; i++) {
    const ch = html[i];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (ch === "\\") {
      escaped = true;
      continue;
    }
    if (ch === '"') {
      inString = !inString;
      continue;
    }
    if (inString) continue;

    if (ch === "{") depth++;
    else if (ch === "}") {
      depth--;
      if (depth === 0) break;
    }
  }

  try {
    return JSON.parse(html.substring(start + marker.length, i + 1));
  } catch {
    return null;
  }
}

/**
 * 从 URL 中提取第一个 http 链接
 */
export function extractUrl(text) {
  return text.match(/https?:\/\/[^\s，,。]+/)?.[0] ?? text;
}
