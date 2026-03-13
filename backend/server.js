/**
 * server.js — HTTP API 服务
 *
 * 启动: node server.js
 * 开发: node --watch server.js
 *
 * 端点:
 *   GET /parse?url=<抖音链接>          解析，返回 VideoInfo JSON
 *   GET /download?url=<直链>&name=<文件名>  代理转发，触发浏览器下载
 */

import archiver from "archiver";
import express from "express";
import { Readable } from "node:stream";
import { dirname, join } from "path";
import { fileURLToPath } from "url";
import { parse } from "./parser.js";

const __dir = dirname(fileURLToPath(import.meta.url));
const app = express();
const PORT = process.env.PORT ?? 3333;
const BASE = (process.env.BASE_PATH ?? "").replace(/\/+$/, ""); // e.g. "/vd"

// 动态注入 <base href> 到 index.html
app.get([BASE + "/", BASE + "/index.html", BASE || "/"], async (req, res) => {
  const { readFile } = await import("node:fs/promises");
  let html = await readFile(join(__dir, "public", "index.html"), "utf8");
  const base = BASE ? `<base href="${BASE}/" />` : "";
  html = html.replace("</head>", `${base}</head>`);
  res.type("html").send(html);
});

// 静态前端文件
app.use(express.static(join(__dir, "public")));
app.use(express.json());

// CDN 域名白名单（防止 SSRF）
const ALLOWED_DOMAINS = [
  // 抖音
  "aweme.snssdk.com",
  "v3-cold.douyinvod.com",
  "v3-dy.douyinvod.com",
  "v19-dy.douyinvod.com",
  "v9-dy.douyinvod.com",
  "douyinpic.com",
  "douyinstatic.com",
  // 小红书
  "xhscdn.com",
  "xiaohongshu.com",
];

const UA_PROXY =
  "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) " +
  "AppleWebKit/605.1.15 (KHTML, like Gecko) " +
  "Mobile/15E148 aweme_36.7.0 Region/CN AppTheme/light " +
  "NetType/WIFI JsSdk/2.0 Channel/App ByteLocale/zh " +
  "ByteFullLocale/zh-Hans-CN WKWebView/1 aweme/36.7.0";

// ── GET /parse ────────────────────────────────────────────────────────────────
app.get("/parse", async (req, res) => {
  const { url } = req.query;
  if (!url) return res.status(400).json({ error: "缺少 url 参数" });

  try {
    const info = await parse(url);
    res.json(info);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ── GET /download ─────────────────────────────────────────────────────────────
// 代理转发视频/图片流，绕过浏览器 CORS，同时触发下载
app.get("/download", async (req, res) => {
  const { url, name } = req.query;
  if (!url) return res.status(400).json({ error: "缺少 url 参数" });

  // 白名单校验，防止 SSRF
  let parsedUrl;
  try {
    parsedUrl = new URL(url);
  } catch {
    return res.status(400).json({ error: "无效的 URL" });
  }
  if (!ALLOWED_DOMAINS.some((d) => parsedUrl.hostname.endsWith(d))) {
    return res.status(403).json({ error: "不允许代理该域名" });
  }

  try {
    const upstream = await fetch(url, {
      headers: { "User-Agent": UA_PROXY },
      redirect: "follow",
    });
    if (!upstream.ok) {
      return res
        .status(upstream.status)
        .json({ error: `上游返回 ${upstream.status}` });
    }

    const filename = name ? encodeURIComponent(name) : "download";
    res.setHeader(
      "Content-Disposition",
      `attachment; filename*=UTF-8''${filename}`,
    );
    res.setHeader(
      "Content-Type",
      upstream.headers.get("content-type") ?? "application/octet-stream",
    );
    const cl = upstream.headers.get("content-length");
    if (cl) res.setHeader("Content-Length", cl);

    // 流式转发，不缓存到内存
    for await (const chunk of upstream.body) {
      res.write(chunk);
    }
    res.end();
  } catch (e) {
    if (!res.headersSent) res.status(500).json({ error: e.message });
  }
});

// ── POST /zip ────────────────────────────────────────────────────────────────
// 将多张图片打包为 ZIP 返回
// body: { urls: string[], names: string[], filename?: string }
app.post("/zip", async (req, res) => {
  const { urls, names, filename = "images.zip" } = req.body ?? {};
  if (!Array.isArray(urls) || urls.length === 0)
    return res.status(400).json({ error: "缺少 urls 参数" });
  if (urls.length > 100)
    return res.status(400).json({ error: "最多支持 100 张" });

  // 白名单校验全部 URL
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

  const safeFilename = (filename || "images.zip").replace(
    /[\\/:\"*?<>|]/g,
    "_",
  );
  res.setHeader("Content-Type", "application/zip");
  res.setHeader(
    "Content-Disposition",
    `attachment; filename*=UTF-8''${encodeURIComponent(safeFilename)}`,
  );

  // 图片本身已压缩，level:0 直接存储即可
  const archive = archiver("zip", { zlib: { level: 0 } });
  archive.pipe(res);

  for (let i = 0; i < urls.length; i++) {
    const name = names?.[i] ?? `image_${String(i + 1).padStart(2, "0")}.webp`;
    try {
      const upstream = await fetch(urls[i], {
        headers: { "User-Agent": UA_PROXY },
        redirect: "follow",
      });
      if (upstream.ok) {
        archive.append(Readable.fromWeb(upstream.body), { name });
      }
    } catch {
      // 跳过失败的图片，不中断整体打包
    }
  }

  await archive.finalize();
});

// ── 启动 ──────────────────────────────────────────────────────────────────────
app.listen(PORT, "0.0.0.0", () => {
  console.log(`umao-vd backend listening on http://0.0.0.0:${PORT}`);
  console.log("  GET  /parse?url=<抖音链接>");
  console.log("  GET  /download?url=<直链>&name=<文件名>");
  console.log("  POST /zip  { urls, names, filename }");
});
