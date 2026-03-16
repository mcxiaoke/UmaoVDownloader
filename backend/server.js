/**
 * server.js — Umao VDownloader HTTP API 服务主入口
 *
 * 功能概述：
 * 本文件实现了一个轻量级的 Express.js Web 服务，提供短视频解析和下载代理功能。
 * 主要特性：
 * - 支持抖音、小红书平台的视频/图文解析
 * - 提供安全的CDN代理下载服务
 * - 支持多图片打包为ZIP下载
 * - 内置域名白名单防护SSRF攻击
 * - 支持反向代理和子路径部署
 *
 * 启动方式:
 *   node server.js                    # 正常启动 (端口 3333)
 *   node server.js --debug            # 开启详细调试日志
 *   DEBUG=1 node server.js            # 环境变量方式开启调试
 *   PORT=8080 node server.js          # 自定义端口
 *   BASE_PATH=/vd node server.js      # 子路径部署
 * 开发模式: nodemon server.js -- --debug
 *
 * API端点:
 *   GET /parse?url=<平台链接>         解析视频/图文，返回 VideoInfo JSON
 *   GET /download?url=<直链>&name=<文件名>  代理转发下载，绕过浏览器CORS限制
 *   POST /zip {urls, names, filename}  将多张图片打包为ZIP文件下载
 */

import archiver from "archiver"; // ZIP压缩打包库
import express from "express"; // Web服务器框架
import { Readable } from "node:stream"; // Node.js流处理
import { dirname, join } from "path"; // 路径处理工具
import { fileURLToPath } from "url"; // URL转文件路径
import { loadCookies, normalizeCookieString, saveCookies } from "./cookies.js"; // Cookie 管理模块
import { parse } from "./parser.js"; // 视频解析核心模块

// 获取当前文件所在目录的绝对路径
const __dir = dirname(fileURLToPath(import.meta.url));

// 创建Express应用实例
const app = express();

// 服务配置
const PORT = process.env.PORT ?? 3333; // 服务端口，默认3333
// 支持子路径部署（用于反向代理场景），移除末尾斜杠
const BASE = (process.env.BASE_PATH ?? "").replace(/\/+$/, ""); // e.g. "/vd"

// 调试模式开关：支持环境变量DEBUG=1或命令行参数--debug
const DEBUG = process.env.DEBUG || process.argv.includes("--debug");

// 条件日志函数：仅在DEBUG模式下输出
const log = DEBUG ? (...args) => console.log("[DEBUG]", ...args) : () => {};
const logTime = (label) => (DEBUG ? console.time(label) : () => {});
const logTimeEnd = (label) => (DEBUG ? console.timeEnd(label) : () => {});

// 服务端错误信息转换（不暴露内部细节）
function getServerErrorMsg(error) {
  const msg = (error || "").toLowerCase();
  if (msg.includes("不存在") || msg.includes("已删除") || msg.includes("404")) {
    return "作品不存在或已被删除";
  }
  if (msg.includes("403") || msg.includes("被拒绝") || msg.includes("私密")) {
    return "访问被拒绝，作品可能已设为私密";
  }
  if (msg.includes("401") || msg.includes("未授权") || msg.includes("登录")) {
    return "需要登录才能访问此内容";
  }
  if (msg.includes("风控") || msg.includes("挑战") || msg.includes("waf")) {
    return "触发风控，请稍后重试或更换网络";
  }
  if (msg.includes("网络") || msg.includes("timeout") || msg.includes("socket")) {
    return "网络连接失败，请稍后重试";
  }
  if (msg.includes("无法提取") || msg.includes("未找到")) {
    return "解析失败，页面结构可能已变更";
  }
  return "解析失败，请稍后重试";
}

// 动态注入 <base href> 到 index.html，支持子路径部署
app.get([BASE + "/", BASE + "/index.html", BASE || "/"], async (req, res) => {
  const { readFile } = await import("node:fs/promises");
  let html = await readFile(join(__dir, "public", "index.html"), "utf8");

  // 如果配置了BASE_PATH，注入base标签确保前端资源正确加载
  const base = BASE ? `<base href="${BASE}/" />` : "";
  html = html.replace("</head>", `${base}</head>`);

  res.type("html").send(html);
});

// 静态文件服务：提供前端页面、JS、CSS等资源
app.use(express.static(join(__dir, "public")));

// 解析JSON请求体，用于POST /zip接口
app.use(express.json());

// CDN 域名白名单（防止 SSRF 服务器端请求伪造攻击）
const ALLOWED_DOMAINS = [
  // 抖音CDN域名
  "aweme.snssdk.com", // 抖音主API域名
  "douyinvod.com", // 抖音视频CDN
  "douyinpic.com", // 抖音图片CDN
  "douyinstatic.com", // 抖音静态资源CDN
  // 小红书CDN域名
  "xhscdn.com", // 小红书CDN主域名
  "xiaohongshu.com", // 小红书主域名
];

// 代理请求使用的User-Agent，模拟 iPhone Safari
const UA_PROXY =
  "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) " +
  "AppleWebKit/605.1.15 (KHTML, like Gecko) " +
  "Version/16.6 Mobile/15E148 Safari/604.1";

// ── GET /parse API 端点 ────────────────────────────────────────────────────────────────
// 功能：解析抖音、小红书等平台链接，返回结构化视频/图文信息
app.get("/parse", async (req, res) => {
  const { url } = req.query;
  log(`→ /parse 请求: ${url}`);

  // 参数验证
  if (!url) {
    log("  ✗ 缺少 url 参数");
    return res.status(400).json({ error: "缺少 url 参数" });
  }

  // 记录解析耗时
  logTime("  parse耗时");

  try {
    // 调用解析器，传入DEBUG标志以控制日志输出
    const info = await parse(url, DEBUG);
    logTimeEnd("  parse耗时");

    // 记录解析结果详情
    log(`  ✓ 解析成功: type=${info.type}, platform=${info.platform}`);

    if (info.type === "video") {
      // 视频类型：输出画质信息和视频URL
      log(`    qualities: ${info.qualities?.join(", ") || "none"}`);
      log(`    videoUrl: ${info.videoUrl}`);
    } else {
      // 图文类型：输出图片数量和首张图片URL
      log(`    imageCount: ${info.imageCount}`);
      log(`    imageUrls[0]: ${info.imageUrls?.[0]}`);
    }

    // 返回解析结果
    res.json(info);
  } catch (e) {
    logTimeEnd("  parse耗时");
    log(`  ✗ 解析失败: ${e.message}`);
    // 区分客户端错误(400)和服务端错误(500)
    const isClientError =
      e.message?.includes("不存在") ||
      e.message?.includes("已删除") ||
      e.message?.includes("404") ||
      e.message?.includes("403") ||
      e.message?.includes("401") ||
      e.message?.includes("私密") ||
      e.message?.includes("拒绝") ||
      e.message?.includes("登录");
    const statusCode = isClientError ? 400 : 500;
    // 返回友好错误（不暴露内部细节）
    const friendlyMsg = getServerErrorMsg(e.message);
    res.status(statusCode).json({ error: friendlyMsg });
  }
});

// ── GET /download API 端点 ─────────────────────────────────────────────────────────────
// 功能：代理转发视频/图片流，解决浏览器CORS跨域问题，同时触发下载
app.get("/download", async (req, res) => {
  const { url, name } = req.query;
  log(`→ /download 请求: ${name || "unnamed"}`);
  log(`  url: ${url}`);

  // 参数验证
  if (!url) {
    log("  ✗ 缺少 url 参数");
    return res.status(400).json({ error: "缺少 url 参数" });
  }

  // URL格式验证和白名单校验，防止SSRF攻击
  let parsedUrl;
  try {
    parsedUrl = new URL(url);
  } catch {
    log("  ✗ 无效的 URL");
    return res.status(400).json({ error: "无效的 URL" });
  }

  // 域名白名单检查：只允许代理已知安全的CDN域名
  if (!ALLOWED_DOMAINS.some((d) => parsedUrl.hostname.endsWith(d))) {
    log(`  ✗ 域名不在白名单: ${parsedUrl.hostname}`);
    return res.status(403).json({ error: "不允许代理该域名" });
  }

  try {
    log(`  开始代理: ${parsedUrl.hostname}`);

    // 向源站发起请求，使用移动端User-Agent避免被屏蔽
    const upstream = await fetch(url, {
      headers: { "User-Agent": UA_PROXY },
      redirect: "follow", // 跟随重定向
    });

    // 检查上游响应状态
    if (!upstream.ok) {
      log(`  ✗ 上游返回 ${upstream.status}`);
      return res
        .status(upstream.status)
        .json({ error: `上游返回 ${upstream.status}` });
    }

    // 设置响应头，触发浏览器下载
    const filename = name ? encodeURIComponent(name) : "download";
    res.setHeader(
      "Content-Disposition",
      `attachment; filename*=UTF-8''${filename}`,
    );
    res.setHeader(
      "Content-Type",
      upstream.headers.get("content-type") ?? "application/octet-stream",
    );

    // 传递Content-Length头，便于浏览器显示下载进度
    const cl = upstream.headers.get("content-length");
    if (cl) res.setHeader("Content-Length", cl);

    log(
      `  ✓ 开始流式转发, Content-Type: ${upstream.headers.get("content-type")}`,
    );

    // 流式转发：直接将上游响应体流式传输到客户端，避免内存缓存
    for await (const chunk of upstream.body) {
      res.write(chunk);
    }
    res.end();
    log(`  ✓ 转发完成`);
  } catch (e) {
    log(`  ✗ 代理失败: ${e.message}`);
    if (!res.headersSent) {
      res.status(500).json({ error: "下载代理失败，请稍后重试" });
    }
  }
});

// ── POST /zip API 端点 ────────────────────────────────────────────────────────────────
// 功能：将多张图片打包为ZIP文件返回，适用于小红书等多图内容
// 请求体: { urls: string[], names: string[], filename?: string }
app.post("/zip", async (req, res) => {
  const { urls, names, filename = "images.zip" } = req.body ?? {};

  // 参数验证
  if (!Array.isArray(urls) || urls.length === 0)
    return res.status(400).json({ error: "缺少 urls 参数" });
  if (urls.length > 100)
    return res.status(400).json({ error: "最多支持 100 张" });

  // 对所有URL进行白名单校验，防止SSRF攻击
  for (const u of urls) {
    let p;
    try {
      p = new URL(u);
    } catch {
      return res.status(400).json({ error: `无效 URL: ${u}` });
    }
    if (!ALLOWED_DOMAINS.some((d) => p.hostname.endsWith(d)))
      return res.status(403).json({ error: `不允许代理域名: ${p.hostname}` });
  }

  // 安全处理文件名，替换非法字符
  const safeFilename = (filename || "images.zip").replace(
    /[\\/:\"*?<>|]/g,
    "_",
  );

  // 设置响应头，指定ZIP文件类型和下载文件名
  res.setHeader("Content-Type", "application/zip");
  res.setHeader(
    "Content-Disposition",
    `attachment; filename*=UTF-8''${encodeURIComponent(safeFilename)}`,
  );

  // 创建ZIP归档，使用level:0避免重复压缩（图片本身已压缩）
  const archive = archiver("zip", { zlib: { level: 0 } });
  archive.pipe(res);

  // 逐个下载图片并添加到ZIP中
  for (let i = 0; i < urls.length; i++) {
    const name = names?.[i] ?? `image_${String(i + 1).padStart(2, "0")}.webp`;
    try {
      const upstream = await fetch(urls[i], {
        headers: { "User-Agent": UA_PROXY },
        redirect: "follow",
      });
      if (upstream.ok) {
        // 将图片流直接添加到ZIP，避免内存缓存
        archive.append(Readable.fromWeb(upstream.body), { name });
      }
    } catch {
      // 单个图片下载失败时跳过，不中断整体打包过程
      // 这样可以确保其他图片正常打包
    }
  }

  // 完成ZIP打包
  await archive.finalize();
});

// ── Cookie 管理 API ──────────────────────────────────────────────────────────────────
// 功能：获取和设置 Cookie，用于下载需要登录态的高清内容

// GET /api/cookies - 获取当前 Cookie 配置（敏感字段脱敏）
app.get("/api/cookies", async (req, res) => {
  try {
    const cookies = await loadCookies();
    // 脱敏处理：只返回是否存在 Cookie，不返回完整值
    res.json({
      douyin: cookies.douyin ? "***已设置***" : "",
      xiaohongshu: cookies.xiaohongshu ? "***已设置***" : "",
      updatedAt: cookies.updatedAt,
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// POST /api/cookies - 设置 Cookie
// 请求体: { douyin?: string, xiaohongshu?: string }
// 支持标准 Cookie 字符串或 Netscape HTTP Cookie File 格式
app.post("/api/cookies", async (req, res) => {
  const { douyin, xiaohongshu } = req.body ?? {};

  try {
    const toSave = {};
    // 自动检测并转换 Cookie 格式（支持 Netscape 格式）
    if (typeof douyin === "string") {
      toSave.douyin = normalizeCookieString(douyin.trim());
    }
    if (typeof xiaohongshu === "string") {
      toSave.xiaohongshu = normalizeCookieString(xiaohongshu.trim());
    }

    await saveCookies(toSave);
    log("[Cookie] 已更新");

    res.json({ success: true, message: "Cookie 已保存" });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// DELETE /api/cookies - 清除 Cookie
app.delete("/api/cookies", async (req, res) => {
  try {
    await saveCookies({ douyin: "", xiaohongshu: "" });
    log("[Cookie] 已清除");
    res.json({ success: true, message: "Cookie 已清除" });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ── 服务启动 ──────────────────────────────────────────────────────────────────────
app.listen(PORT, "0.0.0.0", () => {
  console.log(`umao-vd backend listening on http://0.0.0.0:${PORT}`);
  console.log("API端点:");
  console.log("  GET  /parse?url=<链接>                    # 解析视频/图文");
  console.log("  GET  /download?url=<直链>&name=<文件名>   # 代理下载");
  console.log("  POST /zip  { urls, names, filename }     # 打包下载");
  console.log("  GET  /api/cookies                        # 获取 Cookie 状态");
  console.log("  POST /api/cookies                        # 设置 Cookie");
  console.log("  DELETE /api/cookies                      # 清除 Cookie");

  if (DEBUG) {
    console.log("\n[DEBUG 模式已开启] 详细日志已启用");
    console.log("  使用 DEBUG=1 或 --debug 开启调试日志\n");
  }
});
