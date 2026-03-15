/**
 * parser.js — 短视频平台链接解析核心模块（Node.js 22+，ESM）
 *
 * 功能说明：
 * 本文件作为解析器的统一入口点，负责将解析请求路由到对应平台的解析器。
 * 支持抖音、小红书等多个平台的视频和图文内容解析。
 *
 * 注意：此文件现在只是重新导出，实际实现已移至 parsers/ 目录
 * 保持此文件以维持向后兼容
 */

// 从 parsers 目录导入统一的解析函数
export { parse } from "./parsers/index.js";

/**
 * 视频/图文信息数据结构定义
 * @typedef {Object} VideoInfo
 * @property {'video'|'image'} type - 内容类型：video(视频) 或 image(图文)
 * @property {string} platform - 平台标识，如 "douyin"(抖音)、"xiaohongshu"(小红书)
 * @property {string} id - 内容唯一标识符
 * @property {string|null} shareId - 分享链接中的短ID（抖音特有）
 * @property {string} title - 内容标题或描述
 * @property {string|null} coverUrl - 封面图片URL
 * @property {number|null} width - 内容宽度（像素）
 * @property {number|null} height - 内容高度（像素）
 * @property {string[]|undefined} qualities - 视频专有：可用画质列表，如 ["1080p", "720p"]
 * @property {Object|undefined} qualityUrls - 视频专有：各画质对应的URL映射
 * @property {string|null|undefined} videoUrl - 视频专有：最高画质视频直链
 * @property {string[]|undefined} imageUrls - 图文专有：图片URL数组
 * @property {number|undefined} imageCount - 图文专有：图片数量
 * @property {string|null|undefined} musicTitle - 图文专有：背景音乐标题
 * @property {string|null|undefined} musicAuthor - 图文专有：背景音乐作者
 * @property {string|null|undefined} musicUrl - 图文专有：背景音乐URL
 */
