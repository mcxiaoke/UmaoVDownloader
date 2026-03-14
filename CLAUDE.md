# CLAUDE.md

本文件为 Claude Code (claude.ai/code) 在此代码库中工作时提供指导。

## 项目概述

Umao VDownloader 是一个多平台短视频下载工具，专注于抖音和小红书平台。项目包含三个主要部分：

- **Flutter 客户端**：支持 Android 和 Windows 的跨平台应用
- **CLI 工具**：独立的 Dart 命令行工具 (`umao_vd`)
- **Node.js 服务端**：前后端一体的 Web 平台，提供 REST API 和 Web 界面
- **架构设计**：解析逻辑、下载管理和用户界面清晰分离

## 常用命令

### Flutter 开发

```bash
# 获取依赖
flutter pub get

# 运行 Flutter 应用
flutter run

# 构建指定平台版本
flutter build windows --release
flutter build apk --release --split-per-abi

# 运行测试
flutter test
```

### CLI 工具开发

```bash
# 直接运行 CLI
dart run cli/umao_vd.dart --help
dart run cli/umao_vd.dart -j "https://v.douyin.com/example/"

# 编译为可执行文件
dart compile exe cli/umao_vd.dart -o build/umao_vd.exe
```

### 测试和调试

```bash
# 运行批量 URL 测试
dart run tool/run_tests.dart urls.txt
dart run tool/run_tests.dart xhs.txt --debug

# 运行 Flutter 组件测试
flutter test test/widget_test.dart

# 代码分析
flutter analyze
```

### 发布构建

```powershell
# 构建所有发布版本（Windows、Android、CLI）
.\build_release.ps1

# 构建指定目标
.\build_release.ps1 -Windows
.\build_release.ps1 -Android
.\build_release.ps1 -CLI
```

### Node.js 服务端

```bash
# 进入后端目录
cd backend

# 安装依赖
npm install --omit=dev

# 启动服务
node server.js

# 生产环境推荐使用 pm2
PORT=3333 BASE_PATH=/vd pm2 start server.js --name umao-vd
```

## 代码架构

### 核心服务

- **ParserFacade** (`lib/services/parser_facade.dart`)：视频解析的主要入口点
  - 支持多平台（抖音、小红书）
  - 实现解析策略模式（WebView 与 Dart 解析器）
  - 提供解析器对比模式用于测试准确性

- **平台解析器**：
  - `DouyinParser`：从抖音分享链接提取视频数据
  - `XiaohongshuParser`：处理小红书内容解析
  - `WebViewParser`：基于 JavaScript 的回退解析器

- **下载系统**：
  - `BaseDownloader`：包含通用下载逻辑的抽象基类
  - `DesktopDownloader`：Windows/Linux 特定实现
  - `MobileDownloader`：具有存储权限的 Android 特定实现

### 数据模型

- **VideoInfo**：包含以下内容的核心数据结构：
  - 视频元数据（ID、标题、尺寸、码率）
  - 具有直接 CDN 链接的质量变体
  - 图文作品支持（多图片、背景音乐）
  - 封面图片和分享信息

### 用户界面结构

- **HomePage** (`lib/ui/home_page.dart`)：主要应用界面
  - URL 输入和解析控制
  - 视频质量选择
  - 进度跟踪和下载管理
  - 多平台支持检测

### CLI 实现

- **umao_vd** (`cli/umao_vd.dart`)：独立命令行工具
  - 适用于脚本的 JSON 输出模式
  - 带进度条的下载功能
  - 跨平台编译支持

## 关键依赖项

### Flutter 依赖

- `http`：网络请求
- `webview_flutter` + `webview_windows`：JavaScript 解析回退
- `permission_handler`：Android 存储权限
- `path_provider`：平台特定文件路径
- `shared_preferences`：设置持久化

### 开发依赖

- `flutter_lints`：代码质量检查
- `flutter_launcher_icons`：应用图标生成

## 平台支持

### Node.js 服务端特性

- **轻量级实现**：无需第三方 NPM 依赖的原始纯函数解析器
- **跨域解决方案**：Express.js 代理接口解决浏览器 CORS 问题
- **安全机制**：白名单拦截功能防止 SSRF 攻击
- **前端优化**：
  - JSZip 前端分片组包功能
  - Canvas WebP 转 JPEG 离线转换（适配手机端相册）
- **部署灵活**：支持反向代理和子路径环境映射

### Android 特性

- Android 10/11+ 的动态权限处理
- 相册可见性的媒体存储集成
- 按架构拆分 APK 构建

### Windows 特性

- 用于 JavaScript 解析的 WebView2 集成
- 针对桌面优化的 UI 和文件处理
- MSIX 打包支持

### CLI 特性

- 适合管道的 JSON 输出
- 下载进度指示
- 可配置的输出目录

## 测试策略

### 测试文件

- `test/urls.txt`：抖音测试 URL 示例
- `test/xhs.txt`：小红书 URL 示例
- `tool/run_tests.dart`：带 HTML 缓存的自动批量测试

### 测试执行

- 批量测试将 HTML/JSON 保存到 `test/cache/` 以供分析
- 比较解析器性能和准确性
- 支持调试模式以输出详细信息

## 构建和发布流程

### 版本管理

- `pubspec.yaml` 中的自动版本递增
- 构建号跟踪用于发布管理

### 发布产物

- Windows：MSIX 包和 7z 压缩包
- Android：按架构拆分的 APK + 通用 APK
- CLI：平台特定的可执行文件

### 资源管理

- `assets/js/` 中的 JavaScript 提取器
- 平台特定的用户代理字符串
- 针对 CDN 兼容性进行优化

## 开发指南

### 解析器开发

- 始终使用 WebView 和 Dart 解析器进行测试
- 在开发期间缓存 HTML 响应
- 优雅地处理平台特定的错误情况

### 用户界面开发

- 遵循 Material Design 3 原则
- 支持移动和桌面屏幕尺寸
- 实现适当的加载状态和错误处理

### 下载实现

- 使用轮换用户代理避免被屏蔽
- 实现适当的进度回调
- 处理平台特定的存储要求

## 文件结构参考

```
lib/
├── main.dart                          # 应用入口点
├── services/
│   ├── parser_facade.dart            # 主要解析接口
│   ├── douyin_parser.dart            # 抖音特定解析
│   ├── xiaohongshu_parser.dart       # 小红书解析
│   ├── webview_parser.dart           # JavaScript 回退
│   ├── downloader/                   # 平台下载器
│   │   ├── base_downloader.dart
│   │   ├── desktop_downloader.dart
│   │   └── mobile_downloader.dart
│   ├── settings_service.dart         # 配置管理
│   └── log_service.dart              # 日志基础设施
└── ui/
    └── home_page.dart                # 主要应用 UI

cli/
└── umao_vd.dart                     # 独立 CLI 工具

backend/                             # Node.js 服务端
├── parser.js                       # 纯函数解析器
├── server.js                       # Express.js 服务
├── public/                         # 静态前端文件
│   ├── index.html                  # Web 界面
│   ├── js/                         # 前端 JavaScript
│   └── css/                        # 样式文件
└── package.json                    # 依赖配置

tool/
├── run_tests.dart                   # 批量测试工具
└── debug_parse.dart                 # 调试解析工具
test/
├── urls.txt                         # 测试 URL 集合
├── xhs.txt                          # 小红书 URL
└── cache/                           # 用于分析的缓存 HTML/JSON
```

## 常见开发任务

### 添加新平台支持

1. 在 `parser_facade.dart` 中扩展 `ParserPlatform` 枚举
2. 创建平台特定的解析器类
3. 更新 URL 检测逻辑
4. 添加到批量测试中

### Node.js 服务端开发

1. 修改 `backend/parser.js` 添加新的解析逻辑
2. 更新 `backend/server.js` 的路由处理
3. 在前端界面添加对应的 UI 元素
4. 测试跨域和安全性配置

### 提高解析器准确性

1. 使用 `tool/run_tests.dart --debug` 分析 HTML 结构
2. 检查 `test/cache/` 中的缓存文件
3. 更新正则表达式模式或 JSON 提取逻辑
4. 使用两种解析策略进行测试

### 添加新视频质量

1. 在解析器文件中扩展 `VideoQuality` 枚举
2. 更新质量检测逻辑
3. 使用各种源视频进行测试
4. 验证 CDN URL 可访问性

### 代码规则

1. 修改代码前仔细思考
2. 修改代码后仔细检查
3. 运行代码静态检查工具
4. 如果有测试就运行
