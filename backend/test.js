/**
 * test.js — 短视频解析器批量测试工具
 *
 * 功能概述：
 * 本工具用于批量测试抖音、小红书等平台链接的解析功能。
 * 支持自动识别URL类型、统计解析成功率、输出详细测试报告。
 *
 * 使用方式:
 *   node test.js                    # 默认测试 ../test/urls.txt
 *   node test.js ../test/xhs.txt    # 测试小红书链接文件
 *   node test.js ./my-links.txt     # 测试自定义链接文件
 *   node test.js urls               # 测试预定义的urls.txt
 *
 * 链接文件格式：
 *   - 每行一个URL
 *   - 支持 # 注释，# 后面的内容作为标签
 *   - 空行自动跳过
 *   示例：
 *   https://v.douyin.com/abc123/    # 抖音测试视频
 *   https://xhslink.com/o/xyz789/   # 小红书测试图文
 */

import fs from "fs-extra";                              // 文件系统增强工具
import { dirname, resolve, basename, extname, join } from "path"; // 路径处理
import { fileURLToPath } from "url";                       // URL转文件路径
import { parse } from "./parser.js";                      // 解析器核心

// 获取当前文件所在目录
const __dir = dirname(fileURLToPath(import.meta.url));

// 日志目录
const LOGS_DIR = join(__dir, "logs");
await fs.ensureDir(LOGS_DIR);

/**
 * 对 CDN URL 进行 HEAD 请求测试
 * @param {string} url - 要测试的 URL
 * @returns {Promise<{url: string, status: number, ok: boolean, contentType: string|null, contentLength: number|null, error: string|null}>}
 */
async function testCdnUrl(url) {
  const result = {
    url,
    status: null,
    ok: false,
    contentType: null,
    contentLength: null,
    error: null,
  };

  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 10000); // 10秒超时

    const resp = await fetch(url, {
      method: "HEAD",
      redirect: "follow",
      signal: controller.signal,
    });

    clearTimeout(timeout);

    result.status = resp.status;
    result.ok = resp.ok && resp.status < 400; // 200-399 视为成功
    result.contentType = resp.headers.get("content-type");
    result.contentLength = parseInt(resp.headers.get("content-length") || "0") || null;

    if (!result.ok) {
      result.error = `HTTP ${resp.status}`;
    }
  } catch (e) {
    result.error = e.name === "AbortError" ? "Timeout" : e.message;
  }

  return result;
}

/**
 * 测试解析结果中的所有 CDN 地址
 * @param {object} info - 解析结果
 * @returns {Promise<Array>} CDN 测试结果列表
 */
async function testAllCdnUrls(info) {
  const urlsToTest = [];

  // 收集视频 URL
  if (info.videoUrl) {
    urlsToTest.push({ type: "video", url: info.videoUrl, idx: 0 });
  }

  // 收集图片 URL
  if (info.imageUrls && Array.isArray(info.imageUrls)) {
    info.imageUrls.forEach((url, idx) => {
      if (url) urlsToTest.push({ type: "image", url, idx });
    });
  }

  // 收集实况图视频 URL
  if (info.livePhotoUrls && Array.isArray(info.livePhotoUrls)) {
    info.livePhotoUrls.forEach((url, idx) => {
      if (url) urlsToTest.push({ type: "livephoto", url, idx });
    });
  }

  // 逐个测试
  const results = [];
  for (const item of urlsToTest) {
    const testResult = await testCdnUrl(item.url);
    results.push({ ...item, ...testResult });
  }

  return results;
}

/**
 * 格式化文件大小
 * @param {number|null} bytes
 * @returns {string}
 */
function formatSize(bytes) {
  if (!bytes || bytes === 0) return "-";
  if (bytes < 1024) return `${bytes}B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)}KB`;
  return `${(bytes / 1024 / 1024).toFixed(2)}MB`;
}

/**
 * 生成测试报告并保存到日志目录
 * @param {string} groupName - 测试组名
 * @param {Array} results - 测试结果列表
 * @param {Date} startTime - 测试开始时间
 */
async function generateReport(groupName, results, startTime) {
  const timestamp = startTime.toISOString().replace(/[:.]/g, "-").slice(0, 19);
  const filename = `test-${groupName}-${timestamp}.txt`;
  const filepath = join(LOGS_DIR, filename);

  const lines = [];
  lines.push(`# Umao VDownloader 测试报告`);
  lines.push(`# 测试组: ${groupName}`);
  lines.push(`# 时间: ${startTime.toLocaleString()}`);
  lines.push(`# 总数: ${results.length}`);
  lines.push(`#`);
  lines.push(`# 格式: [状态] 平台 | 类型 | 短ID | CDN测试结果 | 标题`);
  lines.push(`# CDN测试: 类型(序号):状态码/大小 [内容类型]`);
  lines.push(`#`);
  lines.push("");

  for (const r of results) {
    const platform = r.platform || "-";
    const status = r.ok ? "[OK]" : "[FAIL]";
    const title = r.title ? r.title.substring(0, 40) : "";

    // 构建 CDN 测试结果字符串
    let cdnInfo = "";
    if (r.cdnTests && r.cdnTests.length > 0) {
      const testSummaries = r.cdnTests.map(t => {
        const typeAbbr = t.type === "video" ? "V" : t.type === "livephoto" ? "L" : "I";
        const statusAbbr = t.ok ? `${t.status}` : `!${t.status || "ERR"}`;
        const size = formatSize(t.contentLength);
        return `${typeAbbr}${t.idx + 1}:${statusAbbr}/${size}`;
      });
      cdnInfo = testSummaries.join(" ");
    } else {
      cdnInfo = r.ok ? "-" : "解析失败";
    }

    lines.push(`${status} ${platform.padEnd(10)} | ${r.type.padEnd(6)} | ${r.shortId.padEnd(12)} | ${cdnInfo.padEnd(40)} | ${title}`);

    // 如果有失败的 CDN，详细列出
    if (r.cdnTests && r.cdnTests.some(t => !t.ok)) {
      for (const t of r.cdnTests.filter(t => !t.ok)) {
        lines.push(`    ! CDN失败: ${t.type}[${t.idx + 1}] ${t.url.substring(0, 80)}`);
        lines.push(`      -> ${t.error || `HTTP ${t.status}`}`);
      }
    }
  }

  lines.push("");
  lines.push("# 汇总:");
  const passed = results.filter(r => r.ok).length;
  const cdnFailed = results.filter(r => r.cdnTests && r.cdnTests.some(t => !t.ok)).length;
  lines.push(`#   解析成功: ${passed}/${results.length}`);
  lines.push(`#   CDN失败: ${cdnFailed}/${results.length}`);

  await fs.writeFile(filepath, lines.join("\n"), "utf8");
  console.log(`\n报告已保存: ${filepath}`);

  return filepath;
}

// 解析命令行参数，确定测试文件路径
const arg = process.argv[2];
let urlsFile;
let groupName;

if (!arg) {
  // 默认测试文件：上级目录的test/urls.txt
  urlsFile = resolve(__dir, "../test/urls.txt");
  groupName = "urls";
} else if (arg.includes("/") || arg.includes("\\")) {
  // 传入的是完整路径，直接使用
  urlsFile = resolve(arg);
  groupName = basename(arg, extname(arg));
} else {
  // 传入的是简称，映射到预定义的测试文件
  const fileMap = {
    urls: "urls.txt",    // 通用测试链接
    dy: "dy.txt",        // 抖音测试链接
    xhs: "xhs.txt",      // 小红书测试链接
  };
  const filename = fileMap[arg] || `${arg}.txt`;
  urlsFile = resolve(__dir, "../test", filename);
  groupName = arg;
}

// 主测试逻辑（异步立即执行函数）
(async () => {
  const startTime = new Date();

  // 解析测试文件：跳过空行和注释行，提取URL和标签
  const entries = (await fs.readFile(urlsFile, "utf8"))
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line && !line.startsWith("#")) // 过滤空行和注释
    .map((line) => {
      const [urlPart, ...rest] = line.split("#");
      return {
        url: urlPart.trim(),
        label: rest.join("#").trim() || urlPart.trim(), // 使用注释作为标签
      };
    });

  console.log(`测试组: ${groupName}`);
  console.log(`文件: ${urlsFile}`);
  console.log(`共 ${entries.length} 条 URL，开始测试…\n`);

  const results = [];
  const DELAY_MS = 2000; // 请求间隔，避免被屏蔽

  // 逐个测试URL
  for (let idx = 0; idx < entries.length; idx++) {
    const { url, label } = entries[idx];

    // 添加延迟，避免请求过于频繁
    if (idx > 0) await new Promise((r) => setTimeout(r, DELAY_MS));

    // 提取短ID用于结果展示
    let shortId = url.match(/v\.douyin\.com\/([A-Za-z0-9_-]+)/)?.[1];
    if (!shortId) {
      shortId = url.match(/\/(?:video|note|slides)\/(\d+)/)?.[1];
    }
    if (!shortId) {
      shortId = url.match(/xhslink\.com\/o\/([A-Za-z0-9_-]+)/)?.[1];
    }
    if (!shortId) {
      shortId = url.match(/xiaohongshu\.com\/explore\/([a-z0-9]+)/)?.[1];
    }
    if (!shortId) {
      shortId = "?"; // 无法提取ID时显示?
    }

    // 显示测试进度
    process.stdout.write(`  测试 ${label.padEnd(20)} ${url} … `);
    const t0 = Date.now();

    try {
      // 调用解析器解析URL
      const info = await parse(url);
      const ms = Date.now() - t0;

      // 构建类型和详情描述
      let typeDesc = "";
      let detailDesc = "";

      if (info.type === "video") {
        typeDesc = "视频";
        const qualities = info.qualities?.join("/") || "default";
        detailDesc = `视频[${qualities}]`;
      } else if (info.type === "livephoto") {
        typeDesc = "实况图";
        detailDesc = `实况图(${info.livePhotoCount || info.imageCount}张)`;
      } else if (info.type === "image") {
        typeDesc = "静态图";
        detailDesc = `静态图(${info.imageCount}张)`;
      } else {
        typeDesc = info.type || "未知";
        detailDesc = info.type || "-";
      }

      // 测试 CDN 地址可用性
      console.log(`解析OK (${ms}ms)，测试CDN…`);
      const cdnTests = await testAllCdnUrls(info);

      // 显示 CDN 测试结果
      const cdnOkCount = cdnTests.filter(t => t.ok).length;
      const cdnFailCount = cdnTests.length - cdnOkCount;
      if (cdnTests.length > 0) {
        const cdnStatus = cdnFailCount === 0 ? "✓" : `!(${cdnFailCount})`;
        console.log(`    CDN: ${cdnOkCount}/${cdnTests.length} ${cdnStatus}`);

        // 显示每个 CDN 的详细信息
        for (const t of cdnTests) {
          const typeIcon = t.type === "video" ? "🎬" : t.type === "livephoto" ? "🎥" : "🖼️";
          const statusIcon = t.ok ? "✓" : "✗";
          const sizeStr = formatSize(t.contentLength);
          console.log(`      ${typeIcon} [${t.idx + 1}] ${statusIcon} HTTP ${t.status || "ERR"} | ${sizeStr.padStart(8)} | ${t.contentType?.split(";")[0] || "-"}`);
          if (!t.ok && t.error) {
            console.log(`         → ${t.error}`);
          }
        }
      }

      results.push({
        label,
        shortId,
        ok: true,
        type: typeDesc,
        detail: detailDesc,
        title: info.title,
        platform: info.platform,
        cdnTests,
      });
    } catch (e) {
      const ms = Date.now() - t0;
      console.log(`FAIL  (${ms}ms)`);
      console.log(`    ↳ ${e.message}`);
      results.push({
        label,
        shortId,
        ok: false,
        type: "ERROR",
        detail: e.message,
        platform: null,
        cdnTests: [],
      });
    }
  }

  // ── 测试结果汇总 ────────────────────────────────────────────────────────────────────
  console.log("\n" + "─".repeat(80));
  console.log("汇总结果");
  console.log("─".repeat(80));

  // 输出每个测试用例的结果
  for (let i = 0; i < results.length; i++) {
    const r = results[i];
    const status = r.ok ? "✓ OK" : "✗ FAIL";
    const title = r.title ? `  ${r.title.substring(0, 35)}` : "";

    console.log(
      `${r.shortId.padEnd(14)}${r.label.padEnd(20)}${r.type.padEnd(8)}${status.padEnd(8)}${r.detail}${title}`,
    );

    // 项目之间用分隔线隔开
    if (i < results.length - 1) {
      console.log("─".repeat(80));
    }
  }

  console.log("─".repeat(80));

  // 统计并显示最终结果
  const passed = results.filter((r) => r.ok).length;
  const cdnFailedCount = results.filter((r) => r.ok && r.cdnTests?.some(t => !t.ok)).length;
  const color = passed === results.length && cdnFailedCount === 0 ? "\x1b[32m" : "\x1b[31m"; // 绿色/红色
  console.log(`\n${color}结果：${passed} / ${results.length} 解析成功，CDN失败: ${cdnFailedCount}\x1b[0m`);

  // 生成测试报告
  await generateReport(groupName, results, startTime);

  // 如果有失败的测试，以错误状态退出
  if (passed < results.length) process.exit(1);
})();
