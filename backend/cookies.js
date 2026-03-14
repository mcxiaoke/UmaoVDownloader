/**
 * cookies.js — Cookie 管理模块
 *
 * 功能概述：
 * 本模块负责管理用户的 Cookie 设置，支持抖音和小红书平台。
 * Cookie 用于获取高清图片和视频等需要登录态的内容。
 *
 * 主要特性：
 * - 持久化存储 Cookie 到本地 JSON 文件
 * - 支持为不同平台设置不同的 Cookie
 * - 提供 API 供解析器使用
 */

import { readFile, writeFile, access } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "url";
import { dirname } from "path";

const __dir = dirname(fileURLToPath(import.meta.url));
const COOKIE_FILE = join(__dir, "cookies.json");

// 默认空配置
const defaultCookies = {
  douyin: "",    // 抖音 Cookie
  xiaohongshu: "", // 小红书 Cookie
  updatedAt: null,
};

// 内存缓存
let cookieCache = null;

/**
 * 确保 Cookie 文件存在
 */
async function ensureCookieFile() {
  try {
    await access(COOKIE_FILE);
  } catch {
    // 文件不存在，创建默认配置
    await writeFile(COOKIE_FILE, JSON.stringify(defaultCookies, null, 2), "utf8");
  }
}

/**
 * 读取 Cookie 配置
 * @returns {Promise<{douyin: string, xiaohongshu: string, updatedAt: string|null}>}
 */
export async function loadCookies() {
  if (cookieCache) return cookieCache;

  await ensureCookieFile();

  try {
    const data = await readFile(COOKIE_FILE, "utf8");
    cookieCache = { ...defaultCookies, ...JSON.parse(data) };
    return cookieCache;
  } catch (e) {
    console.error("[Cookie] 读取失败:", e.message);
    return defaultCookies;
  }
}

/**
 * 保存 Cookie 配置
 * @param {Object} cookies - Cookie 配置对象
 * @param {string} [cookies.douyin] - 抖音 Cookie
 * @param {string} [cookies.xiaohongshu] - 小红书 Cookie
 */
export async function saveCookies(cookies) {
  const current = await loadCookies();
  const updated = {
    ...current,
    ...cookies,
    updatedAt: new Date().toISOString(),
  };

  await writeFile(COOKIE_FILE, JSON.stringify(updated, null, 2), "utf8");
  cookieCache = updated;
  console.log("[Cookie] 已保存到文件");
}

/**
 * 获取指定平台的 Cookie
 * @param {string} platform - 平台名称: 'douyin' | 'xiaohongshu'
 * @returns {Promise<string>} Cookie 字符串
 */
export async function getCookie(platform) {
  const cookies = await loadCookies();
  return cookies[platform] || "";
}

/**
 * 清除指定平台的 Cookie（当检测到 Cookie 无效/过期时调用）
 * @param {string} platform - 平台名称: 'douyin' | 'xiaohongshu'
 */
export async function clearCookie(platform) {
  const validPlatforms = ['douyin', 'xiaohongshu'];
  if (!validPlatforms.includes(platform)) {
    console.error(`[Cookie] 无效的平台: ${platform}`);
    return;
  }

  const current = await loadCookies();
  if (!current[platform]) {
    return; // 已经是空的，无需清除
  }

  const updated = {
    ...current,
    [platform]: "",
    updatedAt: new Date().toISOString(),
  };

  await writeFile(COOKIE_FILE, JSON.stringify(updated, null, 2), "utf8");
  cookieCache = updated;
  console.log(`[Cookie] ${platform} 的 Cookie 已清除（无效/过期）`);
}

/**
 * 检查 Cookie 是否可能无效（基于页面内容特征）
 * @param {string} platform - 平台名称
 * @param {string} html - 页面 HTML 内容
 * @param {Object} data - 解析的数据对象
 * @returns {boolean} 是否可能无效
 */
export function isCookieLikelyInvalid(platform, html = "", data = null) {
  // 小红书检测特征
  if (platform === 'xiaohongshu') {
    // 如果页面包含登录相关提示，可能是 Cookie 过期
    const loginIndicators = [
      '登录',
      '请先登录',
      '登录后查看',
      '未登录',
      '登录超时',
    ];
    const hasLoginPrompt = loginIndicators.some(text => html.includes(text));

    // 数据为空或缺少关键字段
    const hasEmptyData = !data || (!data.note && !data.noteData);

    return hasLoginPrompt || hasEmptyData;
  }

  // 抖音检测特征
  if (platform === 'douyin') {
    // 页面包含登录提示
    const loginIndicators = [
      '请登录',
      '登录后',
      '未登录',
    ];
    const hasLoginPrompt = loginIndicators.some(text => html.includes(text));

    // 数据为空或缺少关键字段
    const hasEmptyData = !data || (!data.item_list && !data.itemList);

    return hasLoginPrompt || hasEmptyData;
  }

  return false;
}

/**
 * 解析 Cookie 字符串为对象
 * 支持标准 Cookie 字符串和 Netscape HTTP Cookie File 格式
 * @param {string} cookieStr - Cookie 字符串
 * @returns {Object} Cookie 键值对
 */
export function parseCookieString(cookieStr) {
  if (!cookieStr || typeof cookieStr !== "string") return {};

  const cookies = {};
  const lines = cookieStr.split(/\r?\n/);

  // 检测是否为 Netscape 格式（以 # 开头或包含多个制表符）
  const isNetscapeFormat = lines.some(
    (line) =>
      line.startsWith("# Netscape HTTP Cookie File") ||
      (line.includes("\t") && line.split("\t").length >= 7)
  );

  if (isNetscapeFormat) {
    // 解析 Netscape 格式：domain	flag	path	secure	expiry	name	value
    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith("#")) continue;

      const parts = trimmed.split("\t");
      if (parts.length >= 7) {
        const name = parts[5].trim();
        const value = parts[6].trim();
        if (name) cookies[name] = value;
      } else if (parts.length >= 2 && line.includes("=")) {
        // 可能是普通格式 name=value
        const [key, ...valParts] = trimmed.split("=");
        if (key) cookies[key.trim()] = valParts.join("=").trim();
      }
    }
  } else {
    // 解析标准 Cookie 字符串：name=value; name2=value2
    cookieStr.split(";").forEach((pair) => {
      const [key, ...valueParts] = pair.trim().split("=");
      if (key && valueParts.length > 0) {
        cookies[key.trim()] = valueParts.join("=").trim();
      }
    });
  }

  return cookies;
}

/**
 * 转换 Cookie 为字符串（支持自动格式检测和转换）
 * @param {string} cookieStr - 原始 Cookie 字符串
 * @returns {string} 转换后的标准 Cookie 字符串
 */
export function normalizeCookieString(cookieStr) {
  if (!cookieStr || typeof cookieStr !== "string") return "";

  const cookies = parseCookieString(cookieStr);
  return formatCookieString(cookies);
}

/**
 * 格式化 Cookie 对象为字符串
 * @param {Object} cookieObj - Cookie 键值对
 * @returns {string} Cookie 字符串
 */
export function formatCookieString(cookieObj) {
  return Object.entries(cookieObj)
    .map(([key, value]) => `${key}=${value}`)
    .join("; ");
}
