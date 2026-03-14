/**
 * index.js — 解析器统一入口和调度中心
 *
 * 功能概述：
 * 本文件作为所有平台解析器的统一入口，负责：
 * 1. 根据URL自动识别所属平台
 * 2. 将解析请求路由到对应的平台解析器
 * 3. 提供统一的错误处理和接口规范
 *
 * 设计原则：
 * - 按优先级排序解析器，确保正确匹配
 * - 支持灵活扩展新平台解析器
 * - 统一的接口规范便于维护
 */

// 导入各平台解析器模块
import * as douyin from "./douyin.js";              // 抖音解析器
import * as xiaohongshu from "./xiaohongshu.js";    // 小红书解析器

// 注册所有解析器（按优先级排序）
// 注意：顺序很重要，更具体的规则应该放在前面
const parsers = [douyin, xiaohongshu];

/**
 * 自动识别平台并解析短视频链接
 * @param {string} url - 待解析的视频/图文链接
 * @param {boolean} debug - 是否开启调试日志输出
 * @returns {Promise<VideoInfo>} 解析后的视频/图文信息
 * @throws {Error} 当链接不被任何解析器支持时抛出错误
 */
export async function parse(url, debug = false) {
  // 遍历所有解析器，找到能够处理该URL的解析器
  const parser = parsers.find((p) => p.canParse(url));

  if (!parser) {
    throw new Error(`不支持的链接: ${url}`);
  }

  // 调用对应解析器的parse方法进行解析
  return await parser.parse(url, debug);
}

// 导出各平台解析器，便于单独使用或测试
export { douyin, xiaohongshu };
