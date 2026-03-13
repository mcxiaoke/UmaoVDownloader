/**
 * test.js — 批量测试 URL
 *
 * 用法:
 *   node test.js              # 默认测试 ../test/urls.txt
 *   node test.js urls         # 测试 ../test/urls.txt
 *   node test.js dy           # 测试 ../test/dy.txt
 *   node test.js xhs          # 测试 ../test/xhs.txt
 */

import { readFileSync } from "fs";
import { dirname, resolve } from "path";
import { fileURLToPath } from "url";
import { parse } from "./parser.js";

const __dir = dirname(fileURLToPath(import.meta.url));

// 获取命令行参数，默认为 urls
const arg = process.argv[2] || "urls";
const fileMap = {
  urls: "urls.txt",
  dy: "dy.txt",
  xhs: "xhs.txt",
};
const filename = fileMap[arg] || `${arg}.txt`;
const urlsFile = resolve(__dir, "../test", filename);

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

console.log(`测试文件: ${filename}`);
console.log(`共 ${entries.length} 条 URL，开始测试…\n`);

const results = [];

const DELAY_MS = 2000;

for (let idx = 0; idx < entries.length; idx++) {
  const { url, label } = entries[idx];
  if (idx > 0) await new Promise((r) => setTimeout(r, DELAY_MS));
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
    const detail =
      info.type === "image"
        ? `图文 ${info.imageCount} 张`
        : `视频 [${info.qualities?.join("/")}]`;
    console.log(`OK  (${ms}ms)`);
    results.push({ label, shortId, ok: true, detail, title: info.title });
  } catch (e) {
    const ms = Date.now() - t0;
    console.log(`FAIL  (${ms}ms)`);
    console.log(`    ↳ ${e.message}`);
    results.push({ label, shortId, ok: false, detail: e.message });
  }
}

// ── 汇总表 ────────────────────────────────────────────────────────────────────
const sep = "─".repeat(80);
console.log(`\n${sep}`);
console.log("ID".padEnd(14) + "类型".padEnd(22) + "结果".padEnd(8) + "详情");
console.log(sep);
for (const r of results) {
  const status = r.ok ? "✓ OK" : "✗ FAIL";
  const title = r.title ? `  ${r.title.substring(0, 30)}…` : "";
  console.log(
    r.shortId.padEnd(14) +
      r.label.padEnd(22) +
      status.padEnd(8) +
      r.detail +
      title,
  );
}
console.log(sep);

const passed = results.filter((r) => r.ok).length;
const color = passed === results.length ? "\x1b[32m" : "\x1b[31m";
console.log(`\n${color}结果：${passed} / ${results.length} 通过\x1b[0m`);

if (passed < results.length) process.exit(1);
