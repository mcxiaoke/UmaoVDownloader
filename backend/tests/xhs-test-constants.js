/**
 * xhs-test-constants.js — 小红书解析器验证测试常量定义
 *
 * 使用方式:
 *   import { XHS_TEST_CASES, XHS_TEST_CASES_MAP } from "./xhs-test-constants.js";
 *
 * 测试用例格式:
 *   {
 *     url: string,           // 小红书分享链接
 *     expectedType: string,  // 期望类型: "video" | "livephoto" | "image"
 *     expectedCount: number, // 期望数量 (视频=1, 图片=张数, 实况图=实况视频数量)
 *     description: string,   // 测试描述
 *   }
 */

/**
 * 小红书标准验证测试用例
 * 用于自动化验证解析器输出是否符合预期
 */
export const XHS_TEST_CASES = [
  {
    url: "http://xhslink.com/o/67vVM3Fpvej",
    expectedType: "livephoto",
    expectedCount: 3,
    description: "实况图：3张实况图",
  },
  {
    url: "http://xhslink.com/o/1gizvB0cIID",
    expectedType: "image",
    expectedCount: 4,
    description: "静态图：4张纯图片",
  },
  {
    url: "http://xhslink.com/o/1Qltcsjriy6",
    expectedType: "video",
    expectedCount: 1,
    description: "视频：1个普通视频",
  },
];

/**
 * 测试用例 Map（以 URL 为 key，方便快速查找）
 */
export const XHS_TEST_CASES_MAP = new Map(
  XHS_TEST_CASES.map((tc) => [tc.url, tc]),
);

/**
 * 类型定义（与 parser 返回的类型保持一致）
 */
export const MediaType = {
  VIDEO: "video", // 普通视频
  LIVEPHOTO: "livephoto", // 实况图（带视频流的图片）
  IMAGE: "image", // 纯静态图片
};

/**
 * 验证结果类型定义
 */
export const ValidationResult = {
  PASS: "PASS", // 通过
  FAIL: "FAIL", // 失败
  SKIP: "SKIP", // 跳过（非测试用例）
};

/**
 * 获取实际数量（根据类型从解析结果中提取）
 * @param {object} info - parser 返回的解析结果
 * @returns {number}
 */
export function getActualCount(info) {
  if (!info || !info.type) return 0;

  switch (info.type) {
    case MediaType.VIDEO:
      return 1; // 视频固定为 1
    case MediaType.LIVEPHOTO:
      return info.livePhotoCount || info.imageCount || 0;
    case MediaType.IMAGE:
      return info.imageCount || 0;
    default:
      return 0;
  }
}

/**
 * 验证单个测试结果
 * @param {object} info - parser 返回的解析结果
 * @param {object} expected - 期望的测试用例
 * @returns {{result: string, errors: string[]}}
 */
export function validateResult(info, expected) {
  const errors = [];

  // 验证类型
  if (info.type !== expected.expectedType) {
    errors.push(
      `类型不匹配: 期望 "${expected.expectedType}", 实际 "${info.type}"`,
    );
  }

  // 验证数量
  const actualCount = getActualCount(info);
  if (actualCount !== expected.expectedCount) {
    errors.push(
      `数量不匹配: 期望 ${expected.expectedCount}, 实际 ${actualCount}`,
    );
  }

  return {
    result: errors.length === 0 ? ValidationResult.PASS : ValidationResult.FAIL,
    errors,
  };
}
