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

// 默认指纹配置 (可在运行时覆盖)
let fingerprint = {
  innerWidth: 420,
  innerHeight: 960,
  outerWidth: 420,
  outerHeight: 960,
  availWidth: 420,
  availHeight: 960,
  sizeWidth: 420,
  sizeHeight: 960,
  platform: "Win32"
};

// 默认 UA
const DEFAULT_UA = "Mozilla/5.0 (Linux; Android 6.0; Nexus 5 Build/MRA58N) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Mobile Safari/537.36";

// 默认配置
const DEFAULT_CONFIG = {
  pageId: 9999,
  appId: 1128,
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
 * @param {Object} config - 可选配置 { pageId, appId, version }
 * @returns {string} a_bogus 签名
 */
export function generateABogus(queryString, userAgent = DEFAULT_UA, config = {}) {
  const { pageId, appId, version } = { ...DEFAULT_CONFIG, ...config };
  const bdms = new BDMS(userAgent);
  
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
