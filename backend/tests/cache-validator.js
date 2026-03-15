/**
 * cache-validator.js — 缓存数据验证器
 *
 * 功能：验证解析器输出是否与缓存数据一致
 * 支持两种模式：
 *   1. 在线测试 (--online)：使用真实 URL 请求网络，验证完整流程
 *   2. 本地测试 (--local)：使用缓存 JSON 数据，验证解析逻辑
 *
 * 使用方式:
 *   node cache-validator.js --online           # 在线测试所有用例
 *   node cache-validator.js --local            # 本地测试所有用例
 *   node cache-validator.js --local --verbose  # 本地测试 + 详细输出
 *   node cache-validator.js --online --douyin  # 只测试抖音
 *   node cache-validator.js --local --xhs      # 只测试小红书
 *
 * 退出码:
 *   0 - 全部通过
 *   1 - 有测试失败
 */

import fs from "fs-extra";
import { dirname, join } from "path";
import { fileURLToPath } from "url";
import { parse } from "../parser.js";
import {
  ALL_TEST_CASES,
  DOUYIN_TEST_CASES,
  XIAOHONGSHU_TEST_CASES,
} from "./cache-test-cases.js";

const __dir = dirname(fileURLToPath(import.meta.url));
const CACHE_DIR = join(__dir, "cache");

// 解析命令行参数
const args = process.argv.slice(2);
const VERBOSE = args.includes("--verbose") || args.includes("-v");
const ONLINE_MODE = args.includes("--online");
const LOCAL_MODE = args.includes("--local");
const TEST_DOUYIN = args.includes("--douyin");
const TEST_XHS = args.includes("--xhs") || args.includes("--xiaohongshu");

// 默认模式：本地测试
const MODE = ONLINE_MODE ? "online" : "local";

// 颜色输出
const c = {
  reset: "\x1b[0m",
  green: "\x1b[32m",
  red: "\x1b[31m",
  yellow: "\x1b[33m",
  cyan: "\x1b[36m",
  dim: "\x1b[2m",
  bold: "\x1b[1m",
};

// ============================================================================
// 本地测试：直接解析缓存 JSON
// ============================================================================

/**
 * 抖音本地测试：解析 item_data JSON
 */
async function testDouyinLocal(tc) {
  const cachePath = join(CACHE_DIR, tc.cacheFile);
  const exists = await fs.pathExists(cachePath);

  if (!exists) {
    return {
      pass: false,
      errors: [`缓存文件不存在: ${tc.cacheFile}`],
    };
  }

  const item = await fs.readJson(cachePath);
  const errors = [];

  // 验证类型
  const awemeType = item.aweme_type;
  const expectedType = tc.expectedType;

  // 根据 aweme_type 判断实际类型
  const VIDEO_TYPES = [0, 4, 51, 55, 58, 61, 109, 201];
  const IMAGE_TYPES = [2, 68, 150];
  let actualType = "unknown";
  if (VIDEO_TYPES.includes(awemeType)) actualType = "video";
  else if (IMAGE_TYPES.includes(awemeType)) actualType = "image";

  if (actualType !== expectedType) {
    errors.push(`类型不匹配: 期望 "${expectedType}", 实际 aweme_type=${awemeType}`);
  }

  // 验证标题（模糊匹配前20字符）
  if (tc.expectedTitle) {
    const expectedSub = tc.expectedTitle.substring(0, 20);
    if (!item.desc?.includes(expectedSub)) {
      errors.push(`标题不匹配: 期望包含 "${expectedSub}", 实际 "${item.desc?.substring(0, 40)}"`);
    }
  }

  // 验证作者
  if (tc.expectedAuthor && item.author?.nickname !== tc.expectedAuthor) {
    errors.push(`作者不匹配: 期望 "${tc.expectedAuthor}", 实际 "${item.author?.nickname}"`);
  }

  // 验证时长
  if (tc.expectedDuration && item.video?.duration) {
    const actualDuration = Math.round(item.video.duration / 1000);
    if (Math.abs(actualDuration - tc.expectedDuration) > 2) {
      errors.push(`时长不匹配: 期望 ~${tc.expectedDuration}s, 实际 ${actualDuration}s`);
    }
  }

  // 验证必要字段
  if (!item.aweme_id) errors.push("缺少 aweme_id");
  if (!item.video?.play_addr) errors.push("缺少 video.play_addr");
  if (!item.author?.nickname) errors.push("缺少 author.nickname");

  return {
    pass: errors.length === 0,
    errors,
    details: VERBOSE ? {
      aweme_id: item.aweme_id,
      type: actualType,
      title: item.desc?.substring(0, 50),
      author: item.author?.nickname,
      duration: item.video?.duration ? Math.round(item.video.duration / 1000) : null,
    } : null,
  };
}

/**
 * 小红书本本地测试：解析 note_data JSON
 */
async function testXiaohongshuLocal(tc) {
  const cachePath = join(CACHE_DIR, tc.cacheFile);
  const exists = await fs.pathExists(cachePath);

  if (!exists) {
    return {
      pass: false,
      errors: [`缓存文件不存在: ${tc.cacheFile}`],
    };
  }

  const note = await fs.readJson(cachePath);
  const errors = [];

  // 验证类型
  const noteType = note.type;
  const expectedType = tc.expectedType;

  // 判断实际类型
  let actualType = "unknown";
  if (noteType === "video") {
    actualType = "video";
  } else if (noteType === "normal") {
    // 检查是否有实况图
    const hasLivePhoto = note.imageList?.some(img => img.livePhoto === true);
    actualType = hasLivePhoto ? "livephoto" : "image";
  }

  if (actualType !== expectedType) {
    errors.push(`类型不匹配: 期望 "${expectedType}", 实际 type="${noteType}" -> "${actualType}"`);
  }

  // 验证标题
  if (tc.expectedTitle && !note.title?.includes(tc.expectedTitle.substring(0, 15))) {
    errors.push(`标题不匹配: 期望包含 "${tc.expectedTitle.substring(0, 15)}...", 实际 "${note.title?.substring(0, 30)}"`);
  }

  // 验证作者
  if (tc.expectedAuthor && note.user?.nickName !== tc.expectedAuthor) {
    errors.push(`作者不匹配: 期望 "${tc.expectedAuthor}", 实际 "${note.user?.nickName}"`);
  }

  // 验证图片数量
  if (tc.expectedImageCount && note.imageList?.length !== tc.expectedImageCount) {
    errors.push(`图片数量不匹配: 期望 ${tc.expectedImageCount}, 实际 ${note.imageList?.length}`);
  }

  // 验证实况图数量
  if (tc.expectedLivePhotoCount) {
    const livePhotoCount = note.imageList?.filter(img => img.livePhoto === true).length || 0;
    if (livePhotoCount !== tc.expectedLivePhotoCount) {
      errors.push(`实况图数量不匹配: 期望 ${tc.expectedLivePhotoCount}, 实际 ${livePhotoCount}`);
    }
  }

  // 验证视频时长
  if (tc.expectedDuration && note.video?.media?.video?.duration) {
    const actualDuration = note.video.media.video.duration;
    if (Math.abs(actualDuration - tc.expectedDuration) > 2) {
      errors.push(`时长不匹配: 期望 ~${tc.expectedDuration}s, 实际 ${actualDuration}s`);
    }
  }

  // 验证必要字段
  if (!note.noteId) errors.push("缺少 noteId");
  if (actualType === "video" && !note.video?.media?.stream) {
    errors.push("缺少 video.media.stream");
  }
  if (actualType !== "video" && !note.imageList?.length) {
    errors.push("缺少 imageList");
  }

  return {
    pass: errors.length === 0,
    errors,
    details: VERBOSE ? {
      noteId: note.noteId,
      type: actualType,
      title: note.title?.substring(0, 50),
      author: note.user?.nickName,
      imageCount: note.imageList?.length,
      livePhotoCount: note.imageList?.filter(img => img.livePhoto).length,
      duration: note.video?.media?.video?.duration,
    } : null,
  };
}

// ============================================================================
// 在线测试：使用真实 URL 请求
// ============================================================================

/**
 * 在线测试：调用解析器解析真实 URL
 */
async function testOnline(tc) {
  const errors = [];

  try {
    const result = await parse(tc.url, VERBOSE);

    // 验证类型
    if (result.type !== tc.expectedType) {
      errors.push(`类型不匹配: 期望 "${tc.expectedType}", 实际 "${result.type}"`);
    }

    // 验证标题（模糊匹配）
    if (tc.expectedTitle) {
      const expectedSub = tc.expectedTitle.substring(0, 15);
      if (!result.title?.includes(expectedSub)) {
        errors.push(`标题不匹配: 期望包含 "${expectedSub}...", 实际 "${result.title?.substring(0, 30)}"`);
      }
    }

    // 验证作者
    if (tc.expectedAuthor && result.authorName !== tc.expectedAuthor) {
      errors.push(`作者不匹配: 期望 "${tc.expectedAuthor}", 实际 "${result.authorName}"`);
    }

    // 验证时长（视频）
    if (tc.expectedDuration && result.duration) {
      if (Math.abs(result.duration - tc.expectedDuration) > 2) {
        errors.push(`时长不匹配: 期望 ~${tc.expectedDuration}s, 实际 ${result.duration}s`);
      }
    }

    // 验证图片数量
    if (tc.expectedImageCount && result.imageCount !== tc.expectedImageCount) {
      errors.push(`图片数量不匹配: 期望 ${tc.expectedImageCount}, 实际 ${result.imageCount}`);
    }

    return {
      pass: errors.length === 0,
      errors,
      details: VERBOSE ? {
        type: result.type,
        title: result.title?.substring(0, 50),
        author: result.authorName,
        duration: result.duration,
        imageCount: result.imageCount,
        videoUrl: result.videoUrl ? "✓" : "✗",
        imageUrls: result.imageUrls?.length || 0,
      } : null,
    };

  } catch (e) {
    return {
      pass: false,
      errors: [`解析异常: ${e.message}`],
    };
  }
}

// ============================================================================
// 主测试流程
// ============================================================================

async function runTests() {
  console.log("=".repeat(70));
  console.log(`缓存数据验证测试 [${MODE === "online" ? "在线" : "本地"}模式]`);
  console.log("=".repeat(70));

  // 选择测试用例
  let testCases = [];
  if (TEST_DOUYIN) {
    testCases = DOUYIN_TEST_CASES.map(tc => ({ ...tc, platform: "douyin" }));
  } else if (TEST_XHS) {
    testCases = XIAOHONGSHU_TEST_CASES.map(tc => ({ ...tc, platform: "xiaohongshu" }));
  } else {
    testCases = ALL_TEST_CASES;
  }

  console.log(`测试用例: ${testCases.length} 个\n`);

  const results = [];
  let passCount = 0;
  let failCount = 0;

  for (let i = 0; i < testCases.length; i++) {
    const tc = testCases[i];
    const platformIcon = tc.platform === "douyin" ? "🎵" : "📕";
    const typeIcon = tc.expectedType === "video" ? "🎬" :
                     tc.expectedType === "livephoto" ? "🎥" : "🖼️";

    console.log(`[${i + 1}/${testCases.length}] ${platformIcon} ${typeIcon} ${tc.description}`);
    console.log(`  ${c.dim}${tc.url}${c.reset}`);

    const startTime = Date.now();
    let result;

    if (MODE === "online") {
      result = await testOnline(tc);
    } else {
      // 本地测试
      if (tc.platform === "douyin") {
        result = await testDouyinLocal(tc);
      } else {
        result = await testXiaohongshuLocal(tc);
      }
    }

    const duration = Date.now() - startTime;

    if (result.pass) {
      passCount++;
      console.log(`  ${c.green}✓ PASS${c.reset} (${duration}ms)`);
    } else {
      failCount++;
      console.log(`  ${c.red}✗ FAIL${c.reset} (${duration}ms)`);
      for (const err of result.errors) {
        console.log(`    ${c.red}! ${err}${c.reset}`);
      }
    }

    // 详细输出
    if (VERBOSE && result.details) {
      console.log(`  ${c.cyan}Details:${c.reset}`);
      for (const [key, val] of Object.entries(result.details)) {
        if (val != null) {
          console.log(`    ${key}: ${val}`);
        }
      }
    }

    results.push({ tc, result, duration });
    console.log("");

    // 在线测试时增加间隔，避免请求过快
    if (MODE === "online" && i < testCases.length - 1) {
      await new Promise(r => setTimeout(r, 2000));
    }
  }

  // 汇总
  console.log("=".repeat(70));
  console.log("测试汇总");
  console.log("=".repeat(70));

  for (const { tc, result } of results) {
    const icon = result.pass ? `${c.green}✓${c.reset}` : `${c.red}✗${c.reset}`;
    const status = result.pass ? "PASS" : "FAIL";
    console.log(`${icon} [${status}] ${tc.description}`);
  }

  console.log("");
  const color = failCount === 0 ? c.green : c.red;
  console.log(
    `${color}结果: ${passCount}/${results.length} 通过, ${failCount}/${results.length} 失败${c.reset}`
  );

  process.exit(failCount > 0 ? 1 : 0);
}

// 运行
runTests().catch(e => {
  console.error("测试运行失败:", e);
  process.exit(1);
});
