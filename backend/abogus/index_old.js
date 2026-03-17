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
 * @param {Object} config - 可选配置 { pageId, appId, version, fingerprint }
 * @returns {string} a_bogus 签名
 */
export function generateABogus(queryString, userAgent = DEFAULT_UA, config = {}) {
  const { pageId, appId, version, fingerprint: customFingerprint } = { ...DEFAULT_CONFIG, ...config };
  const fp = customFingerprint || fingerprint;
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
