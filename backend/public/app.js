const isMobile = /Android|iPhone|iPad|iPod|Mobile/i.test(navigator.userAgent);

const input = document.getElementById("urlInput");
const btn = document.getElementById("parseBtn");
const status = document.getElementById("status");
const result = document.getElementById("result");
const abogusToggle = document.getElementById("abogusToggle");

// 恢复开关状态
abogusToggle.checked = localStorage.getItem("options.abogusEnabled") === "true";
abogusToggle.addEventListener("change", () => {
  localStorage.setItem("options.abogusEnabled", abogusToggle.checked);
});

function setStatus(msg, isError = false) {
  status.textContent = msg;
  status.className = isError ? "error" : "";
}

// 友好错误提示转换
function getFriendlyError(error) {
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
  if (
    msg.includes("network") ||
    msg.includes("timeout") ||
    msg.includes("网络")
  ) {
    return "网络连接失败，请检查网络后重试";
  }
  if (
    msg.includes("无法提取") ||
    msg.includes("未找到") ||
    msg.includes("解析")
  ) {
    return "解析失败，页面结构可能已变更";
  }
  return error || "解析失败，请稍后重试";
}

function dlUrl(url, name) {
  return `api/download?url=${encodeURIComponent(url)}&name=${encodeURIComponent(name)}`;
}

function renderVideo(info) {
  const ext = ".mp4";
  const idPart = info.shareId || info.itemId || info.id || "";
  const titlePart = info.title.replace(/[\\/:"*?<>|]/g, "_").substring(0, 40);
  const safeName = idPart ? `${idPart}_${titlePart}` : titlePart;

  // 构建下载按钮文字：下载视频 + 文件大小 + 时长 + 码率 + 分辨率
  const width = info.width ?? "?";
  const height = info.height ?? "?";
  const sizeMB = info.videoSize
    ? (info.videoSize / 1024 / 1024).toFixed(1)
    : null;
  const bitrate = info.videoBitrate
    ? Math.round(info.videoBitrate / 1000)
    : null; // kb/s
  const duration = info.duration ? `${info.duration}s` : null; // 时长(秒)

  let btnText = "↓ 下载视频";
  if (sizeMB) btnText += ` ${sizeMB}MB`;
  if (duration) btnText += ` ${duration}`;
  if (bitrate) btnText += ` ${bitrate}kb/s`;
  if (width !== "?" && height !== "?") btnText += ` ${width}×${height}`;

  const qualityBtn = `<a class="btn-dl primary full-width" href="${dlUrl(info.videoUrl, `${safeName}${ext}`)}" download>${btnText}</a>`;

  const directLinkBtn = `<a class="btn-dl secondary full-width" href="${info.videoUrl}" target="_blank" rel="noreferrer" title="提示：右键另存为的文件名无法控制，如需自定义文件名请使用上面的下载按钮">新标签页打开视频（右键另存为） ↗</a>`;

  const coverProxyUrl = info.coverUrl
    ? `api/download?url=${encodeURIComponent(info.coverUrl)}&name=cover.jpg`
    : null;

  // 信息行：ID + 类型 + 数量
  const metaInfo = `ID: ${info.itemId || info.id || "-"} · 类型: 视频 · 数量: 1`;

  result.innerHTML = `
        <div class="info-title">${escHtml(info.title || info.shareId || "")}</div>
        <div class="info-meta">${escHtml(metaInfo)}</div>
        ${coverProxyUrl ? `<img class="video-cover" src="${coverProxyUrl}" loading="lazy" style="margin-top:0.6rem;" />` : ""}
        <div class="action-btns">
          ${qualityBtn}
          ${directLinkBtn}
        </div>
      `;
}

function renderImages(info) {
  const idPart = info.shareId || info.itemId || info.id || "";
  const titlePart = info.title.replace(/[\\/:"*?<>|]/g, "_").substring(0, 40);
  const safeName = idPart ? `${idPart}_${titlePart}` : titlePart;

  // 使用后端返回的缩略图和大图
  const imageList = info.imageList || []; // 完整图片对象数组 {thumb, full, videoUrl, isLivePhoto}
  const imageUrls = info.imageUrls || []; // 大图（下载用）
  const imageThumbs = info.imageThumbs || []; // 小图（列表显示用）

  const items = imageUrls
    .map((url, i) => {
      const imgData = imageList[i] || {};
      const videoBtn =
        imgData.isLivePhoto && imgData.videoUrl
          ? `<button class="img-video-btn" data-video="${imgData.videoUrl}" data-idx="${i}" title="下载 Live Photo 视频">🎬 MP4</button>`
          : "";
      return `
        <div class="image-item">
          <img src="${`api/download?url=${encodeURIComponent(imageThumbs[i] || url)}&name=thumb_${i}.webp`}" loading="lazy" data-full="${url}" />
          <button class="img-dl-btn" data-url="${url}" data-idx="${i}">${isMobile ? "↓ JPG" : "↓ WebP"}</button>
          ${videoBtn}
        </div>
      `;
    })
    .join("");

  // 构建音乐文件名：{shareId}_{musicAuthor} - {musicTitle}.mp3
  const musicFileName =
    info.musicAuthor && info.musicTitle
      ? `${idPart}_${escHtml(info.musicAuthor).replace(/[\\/:"*?<>|]/g, "_")} - ${escHtml(info.musicTitle).replace(/[\\/:"*?<>|]/g, "_")}.mp3`
      : `${safeName}_music.mp3`;

  const musicBtn = info.musicUrl
    ? `<a class="btn-dl secondary full-width" href="${dlUrl(info.musicUrl, musicFileName)}" download>
              ♪ 下载背景音乐${info.musicTitle ? " · " + escHtml(info.musicTitle.substring(0, 20)) : ""}
           </a>`
    : "";

  // 信息行：ID + 类型 + 数量
  const typeText = info.type === "livephoto" ? "实况" : "图片";
  const metaInfo = `ID: ${info.itemId || info.id || "-"} · 类型: ${typeText} · 数量: ${info.imageCount || 0}`;

  result.innerHTML = `
        <div class="info-title">${escHtml(info.title)}</div>
        <div class="info-meta">${escHtml(metaInfo)}</div>
        <div class="image-grid">${items}</div>
        <div class="action-btns">
          <button class="btn-dl primary full-width" id="zipBtn">📦 打包下载全部 WebP（${info.imageCount} 张）</button>
          ${musicBtn}
        </div>
      `;

  result.querySelectorAll(".img-dl-btn").forEach((dlBtn) => {
    dlBtn.addEventListener("click", async () => {
      dlBtn.disabled = true;
      const idx = parseInt(dlBtn.dataset.idx);
      if (isMobile) {
        dlBtn.textContent = "转换中…";
        try {
          const name = `${safeName}_${String(idx + 1).padStart(2, "0")}.jpg`;
          await downloadAsJpeg(dlBtn.dataset.url, name);
        } catch (e) {
          setStatus("下载失败：" + e.message, true);
        } finally {
          dlBtn.disabled = false;
          dlBtn.textContent = "↓ JPG";
        }
      } else {
        try {
          const name = `${safeName}_${String(idx + 1).padStart(2, "0")}.webp`;
          const a = document.createElement("a");
          a.href = dlUrl(dlBtn.dataset.url, name);
          a.download = name;
          document.body.appendChild(a);
          a.click();
          a.remove();
        } finally {
          dlBtn.disabled = false;
          dlBtn.textContent = "↓ WebP";
        }
      }
    });
  });

  // Live Photo 视频下载按钮
  result.querySelectorAll(".img-video-btn").forEach((videoBtn) => {
    videoBtn.addEventListener("click", async () => {
      videoBtn.disabled = true;
      const idx = parseInt(videoBtn.dataset.idx);
      try {
        const name = `${safeName}_${String(idx + 1).padStart(2, "0")}_live.mp4`;
        const a = document.createElement("a");
        a.href = dlUrl(videoBtn.dataset.video, name);
        a.download = name;
        document.body.appendChild(a);
        a.click();
        a.remove();
      } catch (e) {
        setStatus("视频下载失败：" + e.message, true);
      } finally {
        videoBtn.disabled = false;
      }
    });
  });

  document.getElementById("zipBtn").addEventListener("click", () =>
    downloadAllAsZip(
      info.imageUrls,
      info.imageUrls.map(
        (_, i) => `${safeName}_${String(i + 1).padStart(2, "0")}.webp`,
      ),
      `${safeName}.zip`,
    ),
  );
}

function escHtml(s) {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

// 从任意文本中提取第一个支持的链接（支持分享文案夹带 URL）
function extractUrl(text) {
  // 抖音链接：支持 v.douyin.com/xxxxx、www.douyin.com/video/xxxxx、iesdouyin.com/share/xxxxx 等
  const douyinMatch =
    text.match(
      /https?:\/\/(?:v\.|www\.)?douyin\.com\/[A-Za-z0-9_-]+(?:\/[^\s，,。]*)?/,
    ) || text.match(/https?:\/\/[^\s]*iesdouyin\.com\/[^\s，,。]+/);
  if (douyinMatch) return douyinMatch[0].replace(/[，。、\s]+$/, "");

  // 小红书链接：支持多种格式
  // - xhslink.com/o/xxxxx (短链接)
  // - www.xiaohongshu.com/explore/xxxxx
  // - www.xiaohongshu.com/discovery/item/xxxxx
  // - www.xiaohongshu.com/user/profile/作者ID/笔记ID
  const xhsMatch =
    text.match(/https?:\/\/(?:www\.)?xhslink\.com\/[^\s，,。]+/) ||
    text.match(
      /https?:\/\/[^\s]*xiaohongshu\.com\/(?:explore|discovery|user)\/[^\s，,。]+/,
    );
  if (xhsMatch) return xhsMatch[0].replace(/[，。、\s]+$/, "");

  return null;
}

async function doParse() {
  const raw = input.value.trim();
  if (!raw) {
    setStatus("请输入链接", true);
    return;
  }
  const url = extractUrl(raw);
  if (!url) {
    setStatus(
      "未识别到支持的链接，支持抖音(v.douyin.com)和小红书(xiaohongshu.com)",
      true,
    );
    return;
  }
  // 回填清理后的链接，方便用户确认
  input.value = url;

  btn.disabled = true;
  result.innerHTML = "";
  setStatus("正在解析…");

  try {
    // 检查是否启用 abogus
    const useAbogus = abogusToggle.checked;
    const abogusParam = useAbogus ? "&abogus=1" : "";
    const resp = await fetch(
      `api/parse?url=${encodeURIComponent(url)}${abogusParam}`,
    );
    const info = await resp.json();
    if (!resp.ok) {
      // 友好错误提示
      const friendlyMsg = getFriendlyError(info.error || "解析失败");
      setStatus(friendlyMsg, true);
      return;
    }

    // 清除状态
    setStatus("");

    // 渲染：livephoto 和 image 都用 renderImages，video 用 renderVideo
    if (info.type === "image" || info.type === "livephoto") {
      renderImages(info);
    } else {
      renderVideo(info);
    }
  } catch (e) {
    const friendlyMsg = getFriendlyError(e.message || "网络请求失败");
    setStatus(friendlyMsg, true);
    console.error("[parse] 错误详情:", e);
  } finally {
    btn.disabled = false;
  }
}

// 通过代理拉取图片，canvas 转 JPEG，返回 Blob
async function fetchAndConvertToJpeg(cdnUrl) {
  const proxyUrl = `api/download?url=${encodeURIComponent(cdnUrl)}&name=img`;
  const resp = await fetch(proxyUrl);
  if (!resp.ok) throw new Error(`代理请求失败 ${resp.status}`);
  const blob = await resp.blob();
  const objUrl = URL.createObjectURL(blob);
  try {
    const img = new Image();
    img.src = objUrl;
    await new Promise((res, rej) => {
      img.onload = res;
      img.onerror = () => rej(new Error("图片加载失败"));
    });
    const canvas = document.createElement("canvas");
    canvas.width = img.naturalWidth;
    canvas.height = img.naturalHeight;
    canvas.getContext("2d").drawImage(img, 0, 0);
    return await new Promise((res) => canvas.toBlob(res, "image/jpeg", 0.8));
  } finally {
    URL.revokeObjectURL(objUrl);
  }
}

// 单张：转 JPEG 后触发浏览器下载
async function downloadAsJpeg(cdnUrl, filename) {
  const jpegBlob = await fetchAndConvertToJpeg(cdnUrl);
  const a = document.createElement("a");
  a.href = URL.createObjectURL(jpegBlob);
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(a.href);
}

// 全部打包 ZIP：始终下载原始 WebP（服务端打包）
async function downloadAllAsZip(urls, names, zipFilename) {
  const zipBtn = document.getElementById("zipBtn");
  if (zipBtn) {
    zipBtn.disabled = true;
    zipBtn.textContent = "打包中…";
  }
  try {
    const resp = await fetch("api/zip", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ urls, names, filename: zipFilename }),
    });
    if (!resp.ok) {
      const err = await resp.json().catch(() => ({}));
      setStatus("打包失败：" + (err.error ?? resp.status), true);
      return;
    }
    const blob = await resp.blob();
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = zipFilename;
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(a.href);
    setStatus(`已打包 ${urls.length} 张 WebP，下载完成`);
  } catch (e) {
    setStatus("打包失败：" + e.message, true);
  } finally {
    if (zipBtn) {
      zipBtn.disabled = false;
      zipBtn.textContent = `📦 打包下载全部 WebP（${urls.length} 张）`;
    }
  }
}

btn.addEventListener("click", doParse);

// 请求防抖：避免快速按 Enter 重复请求
let isParsing = false;
const debouncedParse = () => {
  if (isParsing) return;
  isParsing = true;
  doParse().finally(() => {
    setTimeout(() => (isParsing = false), 500);
  });
};

input.addEventListener("keydown", (e) => {
  if (e.key === "Enter") debouncedParse();
});

// ── Cookie 设置功能 ───────────────────────────────────────────────────────────
const kookieBtn = document.getElementById("kookieBtn");
const kookieModal = document.getElementById("kookieModal");
const closeKookieModal = document.getElementById("closeKookieModal");
const saveKookiesBtn = document.getElementById("saveKookies");
const clearKookiesBtn = document.getElementById("clearKookies");
const kookieTabs = document.querySelectorAll(".kookie-tab");
const kookieHelpLink = document.getElementById("kookieHelpLink");
const kookieHelp = document.getElementById("kookieHelp");
const xhsKookieInput = document.getElementById("xhsKookieInput");
const douyinKookieInput = document.getElementById("douyinKookieInput");
const xhsKookieStatus = document.getElementById("xhsKookieStatus");
const douyinKookieStatus = document.getElementById("douyinKookieStatus");

// 打开弹窗
kookieBtn.addEventListener("click", () => {
  kookieModal.classList.add("show");
  loadKookieStatus();
});

// 关闭弹窗
closeKookieModal.addEventListener("click", () => {
  kookieModal.classList.remove("show");
});

// 点击遮罩关闭
kookieModal.addEventListener("click", (e) => {
  if (e.target === kookieModal) {
    kookieModal.classList.remove("show");
  }
});

// Tab 切换
kookieTabs.forEach((tab) => {
  tab.addEventListener("click", () => {
    kookieTabs.forEach((t) => t.classList.remove("active"));
    tab.classList.add("active");

    document.querySelectorAll(".kookie-tab-content").forEach((content) => {
      content.classList.remove("active");
    });
    document.getElementById(`tab-${tab.dataset.tab}`).classList.add("active");
  });
});

// 显示/隐藏帮助
kookieHelpLink.addEventListener("click", (e) => {
  e.preventDefault();
  kookieHelp.style.display =
    kookieHelp.style.display === "none" ? "block" : "none";
});

// 加载 Cookie 状态
async function loadKookieStatus() {
  try {
    const resp = await fetch("api/cookies");
    const data = await resp.json();

    xhsKookieInput.value = data.xiaohongshu || "";
    xhsKookieInput.placeholder = data.xiaohongshu
      ? "*** Cookie 已设置 ***"
      : "请粘贴小红书的 Cookie 字符串...";

    douyinKookieInput.value = data.douyin || "";
    douyinKookieInput.placeholder = data.douyin
      ? "*** Cookie 已设置 ***"
      : "请粘贴抖音的 Cookie 字符串...";

    if (data.xiaohongshu) {
      xhsKookieStatus.textContent = "✓ 已设置 Cookie";
      xhsKookieStatus.className = "kookie-status success";
    }
    if (data.douyin) {
      douyinKookieStatus.textContent = "✓ 已设置 Cookie";
      douyinKookieStatus.className = "kookie-status success";
    }
  } catch (e) {
    console.error("加载 Cookie 状态失败:", e);
  }
}

// 保存 Cookie
saveKookiesBtn.addEventListener("click", async () => {
  const xhsKookie = xhsKookieInput.value.trim();
  const douyinKookie = douyinKookieInput.value.trim();

  try {
    saveKookiesBtn.disabled = true;
    saveKookiesBtn.textContent = "保存中...";

    const resp = await fetch("api/cookies", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        xiaohongshu: xhsKookie,
        douyin: douyinKookie,
      }),
    });

    const data = await resp.json();

    if (resp.ok) {
      xhsKookieStatus.textContent = xhsKookie ? "✓ 小红书 Cookie 已保存" : "";
      xhsKookieStatus.className = xhsKookie
        ? "kookie-status success"
        : "kookie-status";
      douyinKookieStatus.textContent = douyinKookie
        ? "✓ 抖音 Cookie 已保存"
        : "";
      douyinKookieStatus.className = douyinKookie
        ? "kookie-status success"
        : "kookie-status";

      // 清空输入框（因为服务器返回的是脱敏值）
      xhsKookieInput.value = "";
      douyinKookieInput.value = "";

      setTimeout(() => {
        kookieModal.classList.remove("show");
      }, 500);
    } else {
      throw new Error(data.error || "保存失败");
    }
  } catch (e) {
    xhsKookieStatus.textContent = "✗ 保存失败: " + e.message;
    xhsKookieStatus.className = "kookie-status error";
  } finally {
    saveKookiesBtn.disabled = false;
    saveKookiesBtn.textContent = "保存设置";
  }
});

// 清除 Cookie
clearKookiesBtn.addEventListener("click", async () => {
  if (!confirm("确定要清除所有 Cookie 吗？")) return;

  try {
    clearKookiesBtn.disabled = true;
    const resp = await fetch("api/cookies", { method: "DELETE" });

    if (resp.ok) {
      xhsKookieInput.value = "";
      xhsKookieInput.placeholder = "请粘贴小红书的 Cookie 字符串...";
      xhsKookieStatus.textContent = "✓ 已清除";
      xhsKookieStatus.className = "kookie-status";

      douyinKookieInput.value = "";
      douyinKookieInput.placeholder = "请粘贴抖音的 Cookie 字符串...";
      douyinKookieStatus.textContent = "✓ 已清除";
      douyinKookieStatus.className = "kookie-status";

      setTimeout(() => {
        kookieModal.classList.remove("show");
      }, 500);
    }
  } catch (e) {
    console.error("清除失败:", e);
  } finally {
    clearKookiesBtn.disabled = false;
  }
});
