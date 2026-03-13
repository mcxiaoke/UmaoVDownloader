/**
 * parser.js — 抖音链接解析核心（Node.js 22+，ESM）
 *
 * 注意：此文件现在只是重新导出，实际实现已移至 parsers/ 目录
 * 保持此文件以维持向后兼容
 */

export { parse } from "./parsers/index.js";

/**
 * @typedef {Object} VideoInfo
 * @property {'video'|'image'} type
 * @property {string} platform - 平台标识，如 "douyin"
 * @property {string} id
 * @property {string|null} shareId
 * @property {string} title
 * @property {string|null} coverUrl
 * @property {number|null} width
 * @property {number|null} height
 * @property {string[]|undefined} qualities       - 视频专有
 * @property {Object|undefined}  qualityUrls      - 视频专有
 * @property {string|null|undefined} videoUrl     - 视频专有
 * @property {string[]|undefined}  imageUrls      - 图文专有
 * @property {number|undefined}    imageCount     - 图文专有
 * @property {string|null|undefined} musicTitle   - 图文专有
 * @property {string|null|undefined} musicUrl     - 图文专有
 */
