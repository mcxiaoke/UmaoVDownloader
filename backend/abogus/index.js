/**
 * 抖音 a_bogus 签名模块
 * 
 * 用于生成抖音 API 请求所需的 a_bogus 签名参数
 * 基于反编译的 bdms 1.0.1.19-fix.01 版本
 * 
 * 使用方法:
 *   import { generateABogus, BDMS } from '../abogus/index.js';
 *   const aBogus = generateABogus(queryString, userAgent);
 */

import { BDMS } from './abogus.js';

// 默认指纹配置 (Android Chrome 真机参数)
let fingerprint = {
  innerWidth: 980,
  innerHeight: 1762,
  outerWidth: 400,
  outerHeight: 890,
  availWidth: 400,
  availHeight: 890,
  sizeWidth: 400,
  sizeHeight: 890,
  platform: "Linux armv81"
};

// 常见屏幕分辨率（用于生成合理的指纹参数）
const SCREEN_PRESETS = {
  // 移动端分辨率
  mobile: [
    { width: 360, height: 640 },   // 常见 Android
    { width: 375, height: 667 },   // iPhone 6/7/8
    { width: 390, height: 844 },   // iPhone 12/13/14
    { width: 393, height: 851 },   // Pixel 7
    { width: 412, height: 915 },   // Samsung Galaxy
    { width: 414, height: 896 },   // iPhone 11/XR
    { width: 428, height: 926 },   // iPhone 12/13/14 Pro Max
  ],
  // PC 端分辨率
  desktop: [
    { width: 1366, height: 768 },  // 最常见笔记本
    { width: 1440, height: 900 },  // MacBook Air
    { width: 1536, height: 864 },  // 常见缩放
    { width: 1600, height: 900 },  // 常见显示器
    { width: 1920, height: 1080 }, // 全高清
    { width: 2560, height: 1440 }, // 2K 显示器
  ]
};

/**
 * 生成随机浏览器指纹
 * @param {string} platformType - 平台类型: "mobile" 或 "desktop"，默认自动检测
 * @param {string} userAgent - User-Agent 字符串，用于自动检测平台类型
 * @returns {Object} 指纹对象
 */
export function generateFingerprint(platformType = null, userAgent = null) {
  // 自动检测平台类型
  let type = platformType;
  if (!type && userAgent) {
    type = /mobile|android|iphone|ipad/i.test(userAgent) ? 'mobile' : 'desktop';
  }
  if (!type) {
    type = 'mobile'; // 默认移动端
  }

  const presets = SCREEN_PRESETS[type];
  const screen = presets[Math.floor(Math.random() * presets.length)];

  // 生成合理的浏览器窗口参数
  if (type === 'mobile') {
    // 移动端：窗口通常等于或略小于屏幕
    const innerWidth = screen.width;
    const innerHeight = Math.floor(screen.height * (0.85 + Math.random() * 0.1)); // 85%-95% 高度
    const outerWidth = innerWidth;
    const outerHeight = screen.height;
    const availWidth = screen.width;
    const availHeight = screen.height - Math.floor(Math.random() * 80); // 减去状态栏/导航栏

    return {
      innerWidth,
      innerHeight,
      outerWidth,
      outerHeight,
      availWidth,
      availHeight,
      sizeWidth: screen.width,
      sizeHeight: screen.height,
      platform: "Linux armv81"
    };
  } else {
    // 桌面端：窗口通常小于屏幕，有一定随机性
    const innerWidth = Math.floor(screen.width * (0.6 + Math.random() * 0.35)); // 60%-95% 宽度
    const innerHeight = Math.floor(screen.height * (0.7 + Math.random() * 0.25)); // 70%-95% 高度
    const outerWidth = innerWidth + Math.floor(Math.random() * 20); // 边框
    const outerHeight = innerHeight + Math.floor(70 + Math.random() * 30); // 标题栏等
    const availWidth = screen.width;
    const availHeight = screen.height - Math.floor(30 + Math.random() * 50); // 任务栏

    return {
      innerWidth,
      innerHeight,
      outerWidth,
      outerHeight,
      availWidth,
      availHeight,
      sizeWidth: screen.width,
      sizeHeight: screen.height,
      platform: "Win32"
    };
  }
}

// 默认 UA (Android Edge Mobile)
const DEFAULT_UA = "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Mobile Safari/537.36 EdgA/145.0.0.0";

// 默认配置
const DEFAULT_CONFIG = {
  // pageId: 页面ID
  //   - 9999: 移动端 H5 页面（slidesinfo 等接口）
  //   - 6241: PC 端页面
  pageId: 9999,
  
  // appId: 应用ID
  //   - 1128: 抖音移动端
  //   - 6383: 抖音 PC 端（aweme/detail 等接口）
  // 注意：不同接口可能需要不同的 appId
  appId: 1128,
  
  // bdms 版本号 (不同平台使用不同版本)
  //   - douyin (抖音): 1.0.1.19-fix
  //   - tuan (团长): 1.0.1.15
  //   - ju (巨量百应): 1.0.1.20
  //   - doudian (抖店): 1.0.1.1
  //   - qc (巨量千川): 1.0
  version: "1.0.1.19-fix.01"
};

/**
 * 设置浏览器指纹
 * @param {Object} fp - 指纹对象
 */
export function setFingerprint(fp) {
  fingerprint = { ...fingerprint, ...fp };
  console.log('[ABOGUS] 指纹已更新:', fingerprint);
}

/**
 * 生成 a_bogus 签名
 * @param {string} queryString - URL 查询参数字符串 (不含 a_bogus)
 * @param {string} userAgent - User-Agent 字符串
 * @param {Object} config - 可选配置
 * @param {number} config.pageId - 页面ID (9999=移动端, 6241=PC端)
 * @param {number} config.appId - 应用ID (1128=移动端, 6383=PC端)
 * @param {string} config.version - bdms 版本号
 * @param {Object} config.fingerprint - 自定义指纹对象
 * @param {boolean} config.useRandomFingerprint - 是否使用随机指纹（优先级高于 fingerprint）
 * @param {string} config.platformType - 随机指纹平台类型: "mobile" 或 "desktop"
 * @returns {string} a_bogus 签名
 */
export function generateABogus(queryString, userAgent = DEFAULT_UA, config = {}) {
  const { 
    pageId, 
    appId, 
    version, 
    fingerprint: customFingerprint,
    useRandomFingerprint = false,
    platformType = null
  } = { ...DEFAULT_CONFIG, ...config };
  
  // 确定使用的指纹：随机指纹 > 自定义指纹 > 默认指纹
  let fp;
  if (useRandomFingerprint) {
    fp = generateFingerprint(platformType, userAgent);
  } else {
    fp = customFingerprint || fingerprint;
  }
  
  const bdms = new BDMS(userAgent, fp);
  
  const aBogus = bdms.calculateABogus(
    1, 0, 8,
    queryString,
    "",
    userAgent,
    pageId,
    appId,
    version
  );
  
  return aBogus;
}

/**
 * 获取当前指纹配置
 */
export function getFingerprint() {
  return { ...fingerprint };
}

export { BDMS };
