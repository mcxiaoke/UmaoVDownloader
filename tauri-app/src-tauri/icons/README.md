# 图标文件说明

此目录需要放置应用图标文件。可使用以下方式生成：

## 方法 1：使用 Tauri CLI 生成

```bash
cd tauri-app
npm run tauri icon /path/to/your/icon.png
```

准备一张 1024x1024 或更大的 PNG 图片，Tauri 会自动生成所有需要的尺寸。

## 方法 2：手动放置

需要以下文件：
- 32x32.png
- 128x128.png
- 128x128@2x.png (256x256)
- icon.icns (macOS)
- icon.ico (Windows)

## 临时方案

如果不需要自定义图标，可以先删除 `tauri.conf.json` 中的 `bundle.icon` 配置，使用系统默认图标。
