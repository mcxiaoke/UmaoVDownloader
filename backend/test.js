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
import { dirname, resolve, basename, extname } from "path"; // 路径处理
import { fileURLToPath } from "url";                       // URL转文件路径
import { parse } from "./parser.js";                      // 解析器核心

// 获取当前文件所在目录
const __dir = dirname(fileURLToPath(import.meta.url));

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
      } else if (info.type === "image") {
        if (info.isLivePhoto) {
          typeDesc = "动态图";
          detailDesc = `动态图(${info.imageCount}张)`;
        } else {
          typeDesc = "静态图";
          detailDesc = `静态图(${info.imageCount}张)`;
        }
      } else {
        typeDesc = info.type || "未知";
        detailDesc = info.type || "-";
      }

      console.log(`OK  (${ms}ms)`);
      results.push({
        label,
        shortId,
        ok: true,
        type: typeDesc,
        detail: detailDesc,
        title: info.title,
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
  const color = passed === results.length ? "\x1b[32m" : "\x1b[31m"; // 绿色/红色
  console.log(`\n${color}结果：${passed} / ${results.length} 通过\x1b[0m`);

  // 如果有失败的测试，以错误状态退出
  if (passed < results.length) process.exit(1);
})();
