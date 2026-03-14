/**
 * test.js — 批量测试 URL
 *
 * 用法:
 *   node test.js                    # 默认测试 ../test/urls.txt
 *   node test.js ../test/xhs.txt    # 测试指定文件
 *   node test.js ./my-links.txt     # 测试任意路径的txt文件
 */

import { readFileSync } from "fs";
import { dirname, resolve, basename, extname } from "path";
import { fileURLToPath } from "url";
import { parse } from "./parser.js";

const __dir = dirname(fileURLToPath(import.meta.url));

// 获取命令行参数，解析为绝对路径
const arg = process.argv[2];
let urlsFile;
let groupName;

if (!arg) {
  // 默认使用 ../test/urls.txt
  urlsFile = resolve(__dir, "../test/urls.txt");
  groupName = "urls";
} else if (arg.includes("/") || arg.includes("\\")) {
  // 传入的是路径，直接使用
  urlsFile = resolve(arg);
  groupName = basename(arg, extname(arg));
} else {
  // 传入的是简称，映射到 ../test/ 目录
  const fileMap = {
    urls: "urls.txt",
    dy: "dy.txt",
    xhs: "xhs.txt",
  };
  const filename = fileMap[arg] || `${arg}.txt`;
  urlsFile = resolve(__dir, "../test", filename);
  groupName = arg;
}

// 解析测试文件（跳过空行和纯注释行，提取 url 和 label）
const entries = readFileSync(urlsFile, "utf8")
  .split("\n")
  .map((line) => line.trim())
  .filter((line) => line && !line.startsWith("#"))
  .map((line) => {
    const [urlPart, ...rest] = line.split("#");
    return {
      url: urlPart.trim(),
      label: rest.join("#").trim() || urlPart.trim(),
    };
  });

console.log(`测试组: ${groupName}`);
console.log(`文件: ${urlsFile}`);
console.log(`共 ${entries.length} 条 URL，开始测试…\n`);

const results = [];
const DELAY_MS = 2000;

for (let idx = 0; idx < entries.length; idx++) {
  const { url, label } = entries[idx];
  if (idx > 0) await new Promise((r) => setTimeout(r, DELAY_MS));

  // 提取短ID
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
    shortId = "?";
  }

  process.stdout.write(`  测试 ${label.padEnd(20)} ${url} … `);
  const t0 = Date.now();

  try {
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

// ── 汇总表 ────────────────────────────────────────────────────────────────────
console.log("\n" + "─".repeat(80));
console.log("汇总结果");
console.log("─".repeat(80));

for (let i = 0; i < results.length; i++) {
  const r = results[i];
  const status = r.ok ? "✓ OK" : "✗ FAIL";
  const title = r.title ? `  ${r.title.substring(0, 35)}` : "";

  console.log(
    `${r.shortId.padEnd(14)}${r.label.padEnd(20)}${r.type.padEnd(8)}${status.padEnd(8)}${r.detail}${title}`,
  );

  // 项目之间用 --- 分隔
  if (i < results.length - 1) {
    console.log("─".repeat(80));
  }
}

console.log("─".repeat(80));

const passed = results.filter((r) => r.ok).length;
const color = passed === results.length ? "\x1b[32m" : "\x1b[31m";
console.log(`\n${color}结果：${passed} / ${results.length} 通过\x1b[0m`);

if (passed < results.length) process.exit(1);
