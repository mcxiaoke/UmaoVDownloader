# Umao VDownloader

多端合一的抖音无水印解析与下载工具，支持视频提取、多清晰度选择、图文打包下载以及背景音乐保存。项目分为两个部分：基于 Flutter 构建的客户端（支持 Android、Windows 和 CLI）以及基于 Node.js 构建的轻量级 Web 服务端。

##  核心特性

- **纯无痕解析**：直接提取网页内嵌的初始状态 JSON (`window._ROUTER_DATA`)，无需复杂的 Cookie 获取，无需调用需要签名鉴权的官方 API。
- **全格式支持**：
  - 常规视频：自动拉取所有可用清晰度（从 360p 到 4K），直接抽取无水印 CDN 直链。
  - 图文作品（Note/Slides）：提取最高画质图片（自动过滤水印版本）。
  - 背景音乐：支持直接提取并下载图文作品/视频的背景配乐。
- **智能文案提取**：直接复制抖音 APP 生成的分享文案，自动过滤中文描述提取包含的 URL。
- **多端跨平台支持**：
  - **Flutter 客户端**（Desktop / Android）：丰富的本地功能支持。
  - **Dart 独立 CLI 工具**（`umao_vd`）：管道友好，可单独用于脚本爬虫。
  - **Node.js Web 服务端**：提供标准 REST API（防接口 SSRF）并自带即用型 Web 界面。

---

##  模块一：Flutter 客户端 & CLI

客户端项目基于 Dart 3.11 和 Flutter 构建，提供本地化的直接下载体验和持久化配置管理。

### 目录结构 (App端)
- `cli/umao_vd.dart`: 纯 Dart 构建的独立命令行工具。
- `lib/services/douyin_parser.dart`: 核心爬虫解析端。内置 JSON 匹配结构、URL 降级重试等。
- `lib/services/downloader/`: 下载调度器（支持分平台特性）：
  - `mobile_downloader.dart`: 兼容 Android 10/11+ 存储规范机制，具备动态权限获取并在下载后触发系统广播刷新相册。
  - `desktop_downloader.dart`: 支持 Windows / Linux。
- `lib/ui/`: UI 构建，具有状态可维护的解析面板与多清晰度按钮及进度条展示。

### CLI 工具 (`umao_vd`)

支持直接脱离 Flutter 环境编译为极轻量的二进制程序（如 Windows EXE 或 Linux Elf）：

```bash
# 生成独立二进制文件
dart compile exe cli/umao_vd.dart -o build/umao_vd.exe

# 用法:
umao_vd.exe -d -o C:\Downloads "https://v.douyin.com/xxxxxx/"   # 解析并下载到指定目录
umao_vd.exe -j "https://v.douyin.com/xxxxxx/"                  # 以标准 JSON 输出解析信息
```

---

##  模块二：Node.js 服务端 & Web 前端

考虑到跨设备极速分享与下载能力（无需安装 App），项目内置了一套完全独立的 Node.js 爬虫实现及 Web 界面。

### 目录结构 (`backend/`)
- `parser.js`: 无需第三方 NPM 依赖的原始纯函数解析器。负责 302 跟随重定向、DOM 拆包与正则处理。
- `server.js`: Express.js 代理接口引擎。解决 Web 浏览器严格跨域 CORS 问题及实现白名单拦截功能。
- `public/`: 基于 HTML/CSS/JS 的纯静态零构建前端：
  - 支持 **JSZip 前端分片组包** 功能和流下载体验提升。
  - **Canvas WebP To JPEG 离线转化**：自动探明若客户端为 Mobile 端访问，会在内存级别拦截 WebP 并经 Canvas 输出 JPEG，支持各手机相册完美读写。

### 部署与使用

兼容反向代理以及子路径(`BASE_PATH`)环境映射处理：

```bash
# 启动
cd backend
npm install --omit=dev

# pm2 或 systemd 推荐
PORT=3333 BASE_PATH=/vd pm2 start server.js --name umao-vd
```

**Nginx 反代示例（子路径方案）：**
```nginx
location /vd/ {
    proxy_pass http://127.0.0.1:3333/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
}
location = /vd { return 301 /vd/; }
```

---

##  发版打包机制 (\`build_release.ps1\`)

项目内建一体化集成环境包自动输出脚本，执行后将触发下面流程：
1. 检测 `pubspec.yaml` 中现有 `version` 信息并完成自增迭代。
2. 调度执行各项系统底层 Flutter 打包指令(Split 拆包或统一发包)。
3. 将散落的产出对象汇聚至根部 `release` 存档夹中。
4. 提供高度归档压缩支持（在 Windows 环境内结合 `7z`）。

##  免责声明
本项目及其衍生的任何后端部署系统仅供个人技术研究、网络数据解析与协议学习交流使用，使用者务必遵守原平台相关版权、安全及商业规范声明。不得用于违反平台协定或任何非法获取及侵权之用途行为。
