# WebView 后备解析最小实现计划

## 目标与约束

- 目标：在不依赖后端 Web 服务的前提下，提高解析稳定性。
- 约束：尽量不增加包体，保持现有下载链路与 UI 主流程不变。
- 平台优先级：Android、Windows。

## 选型结论（体积优先）

- Android：优先 `webview_flutter`（系统 WebView）。
- Windows：优先 `webview_windows`（依赖系统 WebView2 Runtime）。
- 暂不采用：`flutter_js` 作为第一阶段方案（维护复杂度更高，且不是浏览器上下文）。

## 最小实现清单

1. 定义后备策略开关与入口

- 新增策略枚举：`dartOnly | dartThenWebView`。
- 默认 `dartOnly`，后续可在设置中切换为 `dartThenWebView`。

2. 统一解析结果映射

- 保证 WebView 后备结果映射到现有 `VideoInfo`，UI 和下载层无感。
- 统一字段：`videoId/title/type/imageUrls/musicUrl/musicTitle/qualityUrls/...`。

3. Android 接入最小 WebView 后备容器

- 仅用于解析，不新增浏览器页面交互。
- 流程：加载目标 URL -> 页面完成 -> 注入 JS -> 回传 JSON。

4. Windows 接入最小 WebView 后备容器

- 启动前检测 WebView2 Runtime。
- 缺失时给出明确错误提示与引导。
- 与 Android 共用同一份提取脚本。

5. 抽取单一 JS 提取脚本

- 新增：`assets/js/extract_douyin_payload.js`。
- Android/Windows 均注入该脚本，避免双份维护。

6. 后备触发条件（最小版）

- 仅当 Dart 解析失败时触发后备。
- 错误白名单：`未找到视频地址`、`_ROUTER_DATA`、风控相关提示。

7. 详细日志打点（复用现有日志面板）

- 记录策略路径：`Dart -> WebViewFallback`。
- 记录时序：加载开始/结束、注入开始/结束、映射结果。
- 记录失败点：导航失败、脚本执行失败、字段映射失败。

8. 超时与资源回收

- 单次后备超时建议：12~15 秒。
- 任务完成后立即销毁 WebView 解析实例。
- 同时仅允许一个后备任务运行。

9. 最小 UI 变更

- 设置项增加：`启用 WebView 后备解析`（默认关闭）。
- 日志面板仅新增策略切换日志，不新增复杂控件。

10. 验收标准

- 当前 `test/urls.txt` 全部通过。
- 至少 2 条“主路径失败但后备成功”的案例可复现。
- 图文音乐字段稳定返回（`musicUrl` 不丢失）。

## 建议实施顺序

1. 先做策略与统一映射（不引入 WebView）。
2. 再接 Android WebView 后备并打通日志。
3. 最后接 Windows WebView 后备与 Runtime 检查。
4. 完成回归后再默认开启后备策略。
