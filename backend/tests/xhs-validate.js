/**
 * xhs-validate.js — 小红书解析器自动化验证测试
 *
 * 功能：自动对比解析结果与预期标准，生成验证报告
 *
 * 使用方式:
 *   node xhs-validate.js                    # 测试所有标准用例
 *   node xhs-validate.js --verbose          # 显示详细输出
 *   node xhs-validate.js --save             # 保存报告到 logs 目录
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
  MediaType,
  ValidationResult,
  XHS_TEST_CASES,
  getActualCount,
  validateResult,
} from "./xhs-test-constants.js";

const __dir = dirname(fileURLToPath(import.meta.url));
const LOGS_DIR = join(__dir, "..", "logs");

// 解析命令行参数
const args = process.argv.slice(2);
const VERBOSE = args.includes("--verbose") || args.includes("-v");
const SAVE_REPORT = args.includes("--save") || args.includes("-s");
const SKIP_CDN = args.includes("--skip-cdn"); // 跳过 CDN 验证

// CDN 验证配置
const CDN_TEST_DELAY_MS = 2000; // CDN 测试间隔 2 秒
const CDN_TIMEOUT_MS = 10000;   // CDN 请求超时 10 秒
const MIN_CONTENT_LENGTH = 1000; // 最小 Content-Length (bytes)

/**
 * 对 CDN URL 进行 HEAD 验证
 * 验证规则:
 *   - HTTP status < 400
 *   - Content-Type 存在
 *   - Content-Length > 1000
 * @param {string} url - CDN 地址
 * @returns {Promise<{ok: boolean, status: number, contentType: string|null, contentLength: number, error: string|null}>}
 */
async function validateCdnUrl(url) {
  const result = {
    url,
    ok: false,
    status: null,
    contentType: null,
    contentLength: 0,
    error: null,
  };

  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), CDN_TIMEOUT_MS);

    const resp = await fetch(url, {
      method: "HEAD",
      redirect: "follow",
      signal: controller.signal,
    });

    clearTimeout(timeoutId);

    result.status = resp.status;
    result.contentType = resp.headers.get("content-type");
    result.contentLength = parseInt(resp.headers.get("content-length") || "0") || 0;

    // 验证规则
    if (resp.status >= 400) {
      result.error = `HTTP ${resp.status} >= 400`;
    } else if (!result.contentType) {
      result.error = "缺少 Content-Type";
    } else if (result.contentLength < MIN_CONTENT_LENGTH) {
      result.error = `Content-Length ${result.contentLength} < ${MIN_CONTENT_LENGTH}`;
    } else {
      result.ok = true;
    }
  } catch (e) {
    result.error = e.name === "AbortError" ? "Timeout > 10s" : e.message;
  }

  return result;
}

/**
 * 验证解析结果中的所有 CDN 地址
 * 规则：
 *   - video: 只验证 videoUrl
 *   - livephoto: 只验证 videoUrl 和 livePhotoUrls（mp4），不验证图片
 *   - image: 只验证 imageUrls
 * @param {object} info - parser 返回的解析结果
 * @returns {Promise<Array>} CDN 验证结果列表
 */
async function validateAllCdns(info) {
  const urlsToTest = [];

  if (info.type === "video") {
    // 普通视频：只验证 videoUrl
    if (info.videoUrl) {
      urlsToTest.push({ type: "video", url: info.videoUrl, idx: 0 });
    }
  } else if (info.type === "livephoto") {
    // 实况图：只验证视频（videoUrl + livePhotoUrls），不验证图片
    if (info.videoUrl) {
      urlsToTest.push({ type: "video", url: info.videoUrl, idx: 0 });
    }
    if (info.livePhotoUrls && Array.isArray(info.livePhotoUrls)) {
      info.livePhotoUrls.forEach((url, idx) => {
        if (url) urlsToTest.push({ type: "livephoto", url, idx });
      });
    }
  } else if (info.type === "image") {
    // 纯图片：验证所有图片
    if (info.imageUrls && Array.isArray(info.imageUrls)) {
      info.imageUrls.forEach((url, idx) => {
        if (url) urlsToTest.push({ type: "image", url, idx });
      });
    }
  }

  // 逐个测试，间隔 2 秒
  const results = [];
  for (let i = 0; i < urlsToTest.length; i++) {
    const item = urlsToTest[i];

    if (i > 0) {
      await new Promise(r => setTimeout(r, CDN_TEST_DELAY_MS));
    }

    const testResult = await validateCdnUrl(item.url);
    results.push({ ...item, ...testResult });
  }

  return results;
}



/**
 * 格式化类型显示
 */
function formatType(type) {
  const icons = {
    [MediaType.VIDEO]: "🎬",
    [MediaType.LIVEPHOTO]: "🎥",
    [MediaType.IMAGE]: "🖼️",
  };
  return `${icons[type] || "❓"} ${type.padEnd(10)}`;
}

/**
 * 格式化数量显示
 */
function formatCount(type, count) {
  const labels = {
    [MediaType.VIDEO]: "个视频",
    [MediaType.LIVEPHOTO]: "张实况",
    [MediaType.IMAGE]: "张图片",
  };
  return `${count}${labels[type] || ""}`;
}

/**
 * 生成验证报告
 */
async function generateValidationReport(results, startTime) {
  const timestamp = startTime.toISOString().replace(/[:.]/g, "-").slice(0, 19);
  const filename = `validate-xhs-${timestamp}.txt`;
  const filepath = join(LOGS_DIR, filename);

  await fs.ensureDir(LOGS_DIR);

  const lines = [];
  lines.push(`# 小红书解析器验证测试报告`);
  lines.push(`# 时间: ${startTime.toLocaleString()}`);
  lines.push(`# 测试用例数: ${results.length}`);
  lines.push(`#`);
  lines.push(`# 格式: [结果] URL | 期望类型/数量 | 实际类型/数量 | 描述`);
  lines.push(`#`);
  lines.push("");

  let passCount = 0;
  let failCount = 0;

  for (const r of results) {
    const status = r.result === ValidationResult.PASS ? "[PASS]" : "[FAIL]";
    const expected = `${r.expectedType}/${r.expectedCount}`;
    const actual =
      r.actualType && r.actualCount !== null
        ? `${r.actualType}/${r.actualCount}`
        : "解析失败";

    lines.push(`${status} ${r.url}`);
    lines.push(`      期望: ${expected.padEnd(15)} 实际: ${actual}`);
    lines.push(`      描述: ${r.description}`);

    // CDN 验证结果
    if (r.cdnResults && r.cdnResults.length > 0) {
      lines.push(`      CDN验证:`);
      for (const cdn of r.cdnResults) {
        const cdnStatus = cdn.ok ? "✓" : "✗";
        const sizeMB = (cdn.contentLength / 1024 / 1024).toFixed(2);
        lines.push(`        ${cdnStatus} ${cdn.type}[${cdn.idx + 1}] HTTP ${cdn.status || "ERR"} | ${sizeMB}MB | ${cdn.contentType?.split(";")[0] || "-"}`);
        if (!cdn.ok && cdn.error) {
          lines.push(`          → ${cdn.error}`);
        }
      }
    }

    if (r.errors && r.errors.length > 0) {
      for (const err of r.errors) {
        lines.push(`      ! ${err}`);
      }
    }
    lines.push("");

    if (r.result === ValidationResult.PASS) passCount++;
    else failCount++;
  }

  lines.push(
    `# 汇总: 通过 ${passCount}/${results.length}, 失败 ${failCount}/${results.length}`,
  );

  await fs.writeFile(filepath, lines.join("\n"), "utf8");
  return filepath;
}

/**
 * 主测试逻辑
 */
async function runValidation() {
  const startTime = new Date();
  const results = [];

  console.log("=".repeat(70));
  console.log("小红书解析器验证测试");
  console.log("=".repeat(70));
  console.log(`测试用例: ${XHS_TEST_CASES.length} 个`);
  console.log("");

  for (let i = 0; i < XHS_TEST_CASES.length; i++) {
    const tc = XHS_TEST_CASES[i];
    console.log(`[${i + 1}/${XHS_TEST_CASES.length}] ${tc.description}`);
    console.log(`  URL: ${tc.url}`);
    console.log(
      `  期望: ${formatType(tc.expectedType)} × ${formatCount(tc.expectedType, tc.expectedCount)}`,
    );

    const t0 = Date.now();
    const result = {
      url: tc.url,
      description: tc.description,
      expectedType: tc.expectedType,
      expectedCount: tc.expectedCount,
      actualType: null,
      actualCount: null,
      result: ValidationResult.FAIL,
      errors: [],
    };

    try {
      const info = await parse(tc.url, VERBOSE);
      result.actualType = info.type;
      result.actualCount = getActualCount(info);

      const validation = validateResult(info, tc);
      result.result = validation.result;
      result.errors = validation.errors;

      const ms = Date.now() - t0;

      if (result.result === ValidationResult.PASS) {
        console.log(`  ✓ 解析通过 (${ms}ms)`);
        if (VERBOSE) {
          console.log(
            `      实际: ${formatType(info.type)} × ${formatCount(info.type, result.actualCount)}`,
          );
          console.log(`      标题: ${info.title?.substring(0, 40) || "-"}`);
        }

        // CDN 验证
        if (!SKIP_CDN) {
          console.log(`  → CDN 验证中...`);
          const cdnResults = await validateAllCdns(info);
          result.cdnResults = cdnResults;

          const okCount = cdnResults.filter(r => r.ok).length;
          const failCount = cdnResults.length - okCount;

          if (failCount === 0) {
            console.log(`    ✓ CDN 全部通过 ${okCount}/${cdnResults.length}`);
          } else {
            console.log(`    ✗ CDN 失败 ${failCount}/${cdnResults.length}`);
            result.result = ValidationResult.FAIL;
          }

          // 显示每个 CDN 结果
          for (const r of cdnResults) {
            const icon = r.ok ? "✓" : "✗";
            const typeIcon = r.type === "video" ? "🎬" : r.type === "livephoto" ? "🎥" : "🖼️";
            const sizeMB = (r.contentLength / 1024 / 1024).toFixed(2);
            console.log(`      ${icon} ${typeIcon}[${r.idx + 1}] HTTP ${r.status || "ERR"} | ${sizeMB}MB | ${r.contentType?.split(";")[0] || "-"}`);
            if (!r.ok && r.error) {
              console.log(`         → ${r.error}`);
              result.errors.push(`CDN[${r.type}${r.idx + 1}]: ${r.error}`);
            }
          }
        }
      } else {
        console.log(`  ✗ 解析失败 (${ms}ms)`);
        for (const err of result.errors) {
          console.log(`      ! ${err}`);
        }
      }
    } catch (e) {
      result.errors.push(`解析异常: ${e.message}`);
      console.log(`  ✗ 异常: ${e.message}`);
    }

    results.push(result);
    console.log("");

    // 请求间隔，避免被屏蔽
    if (i < XHS_TEST_CASES.length - 1) {
      await new Promise((r) => setTimeout(r, 3000));
    }
  }

  // 汇总结果
  console.log("=".repeat(70));
  console.log("验证汇总");
  console.log("=".repeat(70));

  const passCount = results.filter(
    (r) => r.result === ValidationResult.PASS,
  ).length;
  const failCount = results.filter(
    (r) => r.result === ValidationResult.FAIL,
  ).length;

  for (const r of results) {
    const icon = r.result === ValidationResult.PASS ? "✓" : "✗";
    const status = r.result === ValidationResult.PASS ? "PASS" : "FAIL";
    console.log(`${icon} [${status}] ${r.description}`);
    if (r.result === ValidationResult.FAIL && r.errors.length > 0) {
      for (const err of r.errors) {
        console.log(`   ! ${err}`);
      }
    }
  }

  console.log("");
  const color = failCount === 0 ? "\x1b[32m" : "\x1b[31m";
  console.log(
    `${color}结果: ${passCount}/${results.length} 通过, ${failCount}/${results.length} 失败\x1b[0m`,
  );

  // 保存报告
  if (SAVE_REPORT) {
    const reportPath = await generateValidationReport(results, startTime);
    console.log(`\n报告已保存: ${reportPath}`);
  }

  // 返回退出码
  process.exit(failCount > 0 ? 1 : 0);
}

// 运行测试
runValidation().catch((e) => {
  console.error("测试运行失败:", e);
  process.exit(1);
});
