# Umao VDownloader

多端合一的短视频无水印解析与下载工具，支持 **抖音** 和 **小红书** 两大平台。项目分为两个部分：基于 Flutter 构建的客户端（支持 Android、Windows 和 CLI）以及基于 Node.js 构建的轻量级 Web 服务端。

## 核心特性

- **纯无痕解析**：直接提取网页内嵌的初始状态 JSON（抖音 `window._ROUTER_DATA`、小红书 `window.__INITIAL_STATE__`），无需复杂的 Cookie 获取，无需调用需要签名鉴权的官方 API。
- **多平台支持**：
  - **抖音**：常规视频、图文作品、长视频
  - **小红书**：视频笔记、图文笔记、实况图（Live Photo）
- **全格式支持**：
  - 常规视频：自动拉取所有可用清晰度（从 360p 到 4K），直接抽取无水印 CDN 直链。
  - 图文作品：提取最高画质图片（自动过滤水印版本）。
  - 实况图：支持小红书 Live Photo 动态图片解析。
  - 背景音乐：支持直接提取并下载图文作品/视频的背景配乐。
- **智能文案提取**：直接复制 APP 生成的分享文案，自动过滤中文描述提取包含的 URL。
- **多端跨平台支持**：
  - **Flutter 客户端**（Desktop / Android）：丰富的本地功能支持。
  - **Dart 独立 CLI 工具**（`umao_vd`）：管道友好，可单独用于脚本爬虫。
  - **Node.js Web 服务端**：提供标准 REST API 并自带即用型 Web 界面。

---

## 模块一：Flutter 客户端 & CLI

客户端项目基于 Dart 3.11 和 Flutter 构建，提供本地化的直接下载体验和持久化配置管理。

### 目录结构 (App端)

```
lib/services/
├── parser_facade.dart          # 解析器门面，统一入口
├── parser_common.dart          # 公共数据模型（VideoInfo、MediaType 等）
├── douyin_parser.dart          # 抖音解析器
├── xiaohongshu_parser.dart     # 小红书解析器
├── url_extractor.dart          # URL 智能提取
├── settings_service.dart       # 配置持久化
└── downloader/                 # 下载调度器
    ├── base_downloader.dart    # 基础下载逻辑
    ├── mobile_downloader.dart  # Android 特定实现
    └── desktop_downloader.dart # Windows/Linux 实现
```

### CLI 工具 (`umao_vd`)

支持直接脱离 Flutter 环境编译为极轻量的二进制程序：

```bash
# 生成独立二进制文件
dart compile exe cli/umao_vd.dart -o build/umao_vd.exe

# 用法:
umao_vd.exe -d -o C:\Downloads "https://v.douyin.com/xxxxxx/"   # 解析并下载
umao_vd.exe -j "https://v.douyin.com/xxxxxx/"                  # JSON 输出
umao_vd.exe -j "http://xhslink.com/o/xxxxxx"                   # 支持小红书
```

---

## 模块二：Node.js 服务端 & Web 前端

跨设备极速分享与下载能力（无需安装 App），内置完整的解析器实现及 Web 界面。

### 目录结构 (`backend/`)

```
backend/
├── parser.js                   # 解析器入口
├── server.js                   # Express.js 服务
├── parsers/
│   ├── index.js                # 解析器路由
│   ├── common.js               # 公共工具函数
│   ├── douyin.js               # 抖音解析器
│   └── xiaohongshu.js          # 小红书解析器
├── public/                     # Web 前端
│   ├── index.html
│   ├── app.js
│   └── style.css
└── tests/                      # 测试系统
    ├── cache-validator.js      # 验证器（本地/在线模式）
    ├── cache-test-cases.js     # 测试用例
    └── cache/                  # 测试数据缓存
```

### 测试系统

支持本地和在线两种测试模式，用于验证解析器正确性：

```bash
cd backend

# 本地测试（快速，无网络请求）
node tests/cache-validator.js --local
node tests/cache-validator.js --local --douyin    # 只测抖音
node tests/cache-validator.js --local --xhs       # 只测小红书

# 在线测试（真实网络请求）
node tests/cache-validator.js --online
```

测试覆盖：
- 抖音：短视频、长视频、图文
- 小红书：视频、静态图、实况图

### 部署与使用

```bash
cd backend
npm install --omit=dev

# 开发模式
node server.js

# 生产环境（pm2 推荐）
PORT=3333 BASE_PATH=/vd pm2 start server.js --name umao-vd
```

**Nginx 反代示例：**
```nginx
location /vd/ {
    proxy_pass http://127.0.0.1:3333/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
}
```

---

## 模块三：Dart 端测试

Flutter 项目也提供了对应的单元测试，复用同一份测试缓存数据：

```bash
# 运行解析器测试
flutter test test/parser_test.dart
```

### 媒体 URL 可用性验证

验证解析出的媒体 URL 是否真实可用：

```bash
dart run tool/run_tests.dart                    # 验证缓存数据
dart run tool/run_tests.dart --verbose          # 详细输出
```

检测结果：
- **可用**：返回 200 等成功状态
- **未知 (405)**：CDN 不支持 HEAD 请求，URL 可能仍可用
- **不可用**：返回 401/403/404 等

---

## 发版打包机制 (`build_release.ps1`)

项目内建一体化集成环境包自动输出脚本：

```powershell
.\build_release.ps1           # 构建所有平台
.\build_release.ps1 -Windows  # 仅 Windows
.\build_release.ps1 -Android  # 仅 Android
.\build_release.ps1 -CLI      # 仅 CLI
```

---

## 免责声明

本项目及其衍生的任何后端部署系统仅供个人技术研究、网络数据解析与协议学习交流使用，使用者务必遵守原平台相关版权、安全及商业规范声明。不得用于违反平台协定或任何非法获取及侵权之用途行为。
