/**
 * common.js — 通用工具函数和常量定义
 *
 * 功能概述：
 * 本文件包含所有解析器共享的工具函数和常量，提供：
 * - 统一的HTTP请求处理
 * - HTML数据提取工具
 * - 移动端User-Agent模拟
 * - 重试和延迟机制
 *
 * 设计原则：
 * - 避免代码重复，提高维护性
 * - 统一的错误处理和重试策略
 * - 安全的HTML解析方法
 */

// 移动端 User-Agent，用于模拟真实用户访问
export const MOBILE_UA =
  "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) " +
  "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1";

// 默认HTTP请求头，主要用于抖音等平台
export const DEFAULT_HEADERS = {
  "User-Agent": MOBILE_UA,
  "Referer": "https://www.douyin.com/", // 来源页面
};

/**
 * 带重试机制的HTTP请求函数
 * 在网络不稳定的情况下自动重试，提高成功率
 * @param {string} url - 请求URL
 * @param {Object} options - fetch选项
 * @param {number} retries - 重试次数，默认2次
 * @returns {Promise<Response>} fetch响应对象
 * @throws {Error} 当所有重试都失败时抛出错误
 */
export async function fetchWithRetry(url, options = {}, retries = 2) {
  for (let i = 0; i < retries; i++) {
    try {
      const resp = await fetch(url, options);
      if (resp.ok) return resp;
      if (i === retries - 1) throw new Error(`HTTP ${resp.status}`);
    } catch (e) {
      if (i === retries - 1) throw e;
      // 指数退避：延迟时间随重试次数增加
      await delay(500 * (i + 1));
    }
  }
  throw new Error("请求失败");
}

/**
 * 延迟函数，用于控制请求频率
 * @param {number} ms - 延迟毫秒数
 * @returns {Promise} 延迟后的Promise
 */
export function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * 从HTML中提取window.XXX变量数据
 * 通过手动解析JavaScript代码提取页面中的结构化数据
 * @param {string} html - HTML内容
 * @param {string} varName - 变量名，如"_ROUTER_DATA"
 * @returns {object|null} 解析后的数据对象，失败返回null
 */
export function extractWindowData(html, varName) {
  const marker = `window.${varName} = `;
  const start = html.indexOf(marker);
  if (start === -1) return null;

  let depth = 0;        // 大括号嵌套深度
  let inString = false; // 是否在字符串内
  let escaped = false;  // 是否被转义
  let i = start + marker.length;

  // 手动解析JavaScript对象，处理嵌套和字符串
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
    // 提取并解析JSON数据
    return JSON.parse(html.substring(start + marker.length, i + 1));
  } catch {
    return null;
  }
}

/**
 * 从文本中提取第一个HTTP/HTTPS链接
 * 用于处理包含URL的文本，提取纯净的URL
 * @param {string} text - 包含URL的文本
 * @returns {string} 提取到的URL，如果没有则返回原文本
 */
export function extractUrl(text) {
  return text.match(/https?:\/\/[^\s，,。]+/)?.[0] ?? text;
}
