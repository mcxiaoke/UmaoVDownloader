/**
 * index.js — 解析器统一入口
 */

import * as douyin from "./douyin.js";
import * as xiaohongshu from "./xiaohongshu.js";

// 注册所有解析器（按优先级排序）
const parsers = [douyin, xiaohongshu];

/**
 * 自动识别平台并解析
 * @param {string} url - 视频链接
 * @param {boolean} debug - 是否开启调试日志
 * @returns {Promise<VideoInfo>}
 */
export async function parse(url, debug = false) {
  const parser = parsers.find((p) => p.canParse(url));
  if (!parser) {
    throw new Error(`不支持的链接: ${url}`);
  }
  return await parser.parse(url, debug);
}

// 导出各平台解析器供单独使用
export { douyin, xiaohongshu };
