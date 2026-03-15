/**
 * cache-test-cases.js — 从缓存文件提取的测试用例
 *
 * 数据来源：backend/temp/ 目录下的缓存 JSON 文件
 * 提取时间：2026-03-15
 *
 * 用途：
 *   1. 在线测试：用真实 URL 请求网络，验证完整解析流程
 *   2. 本地测试：用缓存 JSON 数据，验证解析器内部逻辑
 *
 * 使用方式:
 *   // 在线测试
 *   node cache-validator.js --online
 *
 *   // 本地测试（快速，无网络请求）
 *   node cache-validator.js --local
 */

// ============================================================================
// 抖音测试用例
// ============================================================================

export const DOUYIN_TEST_CASES = [
  // ---- 视频类型 ----
  {
    id: "7617064037122445669",
    shortId: "KbpvKx0EIEY",
    url: "https://v.douyin.com/KbpvKx0EIEY/",
    expectedType: "video",
    expectedTitle: "等三秒",
    expectedAuthor: "么凹猫 ੭",
    expectedDuration: 10,
    description: "抖音短视频：等三秒",
    cacheFile: "dy_KbpvKx0EIEY.json",
  },
  {
    id: "7617153727447028401",
    shortId: "rO1fV5ERDH8",
    url: "https://v.douyin.com/rO1fV5ERDH8/",
    expectedType: "video",
    expectedTitle: "晓看天色暮看云",
    expectedAuthor: "倦枝",
    expectedDuration: 9,
    description: "抖音视频：古风汉服",
    cacheFile: "dy_rO1fV5ERDH8.json",
  },
  {
    id: "7606645780610436367",
    shortId: "maVLO1IQhXI",
    url: "https://v.douyin.com/maVLO1IQhXI/",
    expectedType: "video",
    expectedTitle: "深入撒哈拉地底",
    expectedAuthor: "老马哄睡宇宙",
    expectedDuration: 1490,
    description: "抖音长视频：撒哈拉沙漠科普",
    cacheFile: "dy_maVLO1IQhXI.json",
  },
  {
    id: "7607435539599396148",
    shortId: "9mKjtjII7AI",
    url: "https://v.douyin.com/9mKjtjII7AI/",
    expectedType: "video",
    expectedTitle: "【超时空辉夜姬】",
    expectedAuthor: "鸿昭",
    expectedDuration: 127,
    description: "抖音MAD视频：超时空辉夜姬",
    cacheFile: "dy_9mKjtjII7AI.json",
  },
  // ---- 图文类型 ----
  {
    id: "7617154153260980474",
    shortId: "4YVImZUFrHQ",
    url: "https://v.douyin.com/4YVImZUFrHQ/",
    expectedType: "image",
    expectedTitle: "杳杳春时来",
    expectedAuthor: "初识.",
    expectedImageCount: 6,
    description: "抖音图文：春日JK甜妹（6张图）",
    cacheFile: "dy_4YVImZUFrHQ.json",
  },
  {
    id: "7616386190702389370",
    shortId: "Emsjx8zX81k",
    url: "https://v.douyin.com/Emsjx8zX81k/",
    expectedType: "image",
    expectedTitle: "一个人的夜",
    expectedAuthor: "我不是土豆",
    expectedImageCount: 4,
    description: "抖音图文：穿搭分享（4张图）",
    cacheFile: "dy_Emsjx8zX81k.json",
  },
  {
    // 注意：抖音的实况图在数据层面也是 aweme_type=2，可能只是标签不同
    id: "7552501921916849418",
    shortId: "He1-6IwxJNs",
    url: "https://v.douyin.com/He1-6IwxJNs/",
    expectedType: "image", // 抖音实况图在数据上是 image 类型
    expectedTitle: "是不是我太笨",
    expectedAuthor: "快快越越",
    expectedImageCount: 3,
    description: "抖音图文/实况图：美女氛围感（3张图）",
    cacheFile: "dy_He1-6IwxJNs.json",
  },
];

// ============================================================================
// 小红书测试用例
// ============================================================================

export const XIAOHONGSHU_TEST_CASES = [
  // ---- 视频类型 ----
  {
    noteId: "69b52bea000000001b022211",
    shortId: "5NUDXVKC8Pm",
    url: "http://xhslink.com/o/5NUDXVKC8Pm",
    expectedType: "video",
    expectedTitle: "白菜对我笑",
    expectedAuthor: "是月辉大人🌙",
    expectedDuration: 10,
    description: "小红书视频：cos流萤",
    cacheFile: "xhs_5NUDXVKC8Pm.json",
  },
  {
    noteId: "69a806320000000022031c3e",
    shortId: "5PFClcBVSjg",
    url: "http://xhslink.com/o/5PFClcBVSjg",
    expectedType: "video",
    expectedTitle: "爻老板〖Cry For Me〗",
    expectedAuthor: "可燃乌龙茶",
    expectedDuration: 15,
    description: "小红书视频：MMD爻光",
    cacheFile: "xhs_5PFClcBVSjg.json",
  },
  // ---- 实况图类型 ----
  {
    noteId: "693edd11000000001e034560",
    shortId: "1YCJtCHOnmf",
    url: "http://xhslink.com/o/1YCJtCHOnmf",
    expectedType: "livephoto",
    expectedTitle: "用live实况打开我的秋冬幸福小记",
    expectedAuthor: "跑跑酸奶",
    expectedImageCount: 7,
    expectedLivePhotoCount: 1,
    description: "小红书实况图：秋冬幸福小记（7张图，1张实况）",
    cacheFile: "xhs_1YCJtCHOnmf.json",
  },
  // ---- 静态图片类型 ----
  {
    noteId: "69b696010000000021005adc",
    shortId: "5VgHFbkL9Ou",
    url: "http://xhslink.com/o/5VgHFbkL9Ou",
    expectedType: "image",
    expectedImageCount: 3,
    description: "小红书静态图：明日方舟终末地（3张图）",
    cacheFile: "xhs_5VgHFbkL9Ou.json",
  },
  {
    noteId: "5be439a8f4fc960001fa7476",
    shortId: "1gizvB0cIID",
    url: "http://xhslink.com/o/1gizvB0cIID",
    expectedType: "image",
    expectedImageCount: 4,
    description: "小红书静态图：4张纯图片",
    cacheFile: "xhs_1gizvB0cIID.json",
  },
];

// ============================================================================
// 所有测试用例合并
// ============================================================================

export const ALL_TEST_CASES = [
  ...DOUYIN_TEST_CASES.map((tc) => ({ ...tc, platform: "douyin" })),
  ...XIAOHONGSHU_TEST_CASES.map((tc) => ({ ...tc, platform: "xiaohongshu" })),
];
