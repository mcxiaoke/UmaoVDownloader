import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/providers.dart';
import '../services/app_logger.dart';
import '../services/log_service.dart';
import '../services/parser_common.dart';
import '../services/settings_service.dart';
import 'widgets/directory_row.dart';
import 'widgets/download_actions.dart';
import 'widgets/input_row.dart';
import 'widgets/log_panel.dart';
import 'widgets/thumbnail_grid.dart';
import 'widgets/video_cover.dart';

/// GitHub 项目地址
const String kGitHubUrl = 'https://github.com/mcxiaoke/UmaoVDownloader';

/// 主页
///
/// 使用 ConsumerStatefulWidget 以支持 Riverpod 的响应式状态管理。
/// 状态通过 Provider 管理，UI 监听状态变化并响应。
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _inputCtrl = TextEditingController();
  final _thumbScrollCtrl = ScrollController();
  bool _screenSizeLogged = false;
  String _appVersion = '';

  // 服务 getter - 直接从 Provider 获取
  LogService get _log => ref.read(logServiceProvider);
  SettingsService get _settings => ref.read(settingsServiceProvider);

  @override
  void initState() {
    super.initState();
    _initAppVersion();
    if (Platform.isAndroid) {
      _checkStoragePermission();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_screenSizeLogged) {
      _screenSizeLogged = true;
      final mediaQuery = MediaQuery.of(context);
      final screenWidth = mediaQuery.size.width;
      final screenHeight = mediaQuery.size.height;
      final devicePixelRatio = mediaQuery.devicePixelRatio;
      _log.info(
        '屏幕: ${screenWidth.toStringAsFixed(0)} x ${screenHeight.toStringAsFixed(0)} '
        '逻辑像素, 设备像素比: ${devicePixelRatio.toStringAsFixed(2)}',
      );
    }
  }

  Future<void> _initAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = info.version;
      });
    }
  }

  /// 检查存储权限，未授权则弹窗引导用户授权
  Future<void> _checkStoragePermission() async {
    // 延迟一帧执行，确保 context 可用
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    final sdkInt = await _androidSdkVersion();
    final permission = sdkInt >= 30
        ? Permission.manageExternalStorage
        : Permission.storage;

    final status = await permission.status;
    if (status.isGranted || status.isLimited) return;

    // 未授权：弹窗引导用户授权
    _showPermissionRequiredDialog(permission);
  }

  /// 读取 Android SDK 版本
  Future<int> _androidSdkVersion() async {
    try {
      final result = await Process.run('getprop', ['ro.build.version.sdk']);
      return int.tryParse((result.stdout as String).trim()) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// 显示必须授权的对话框
  void _showPermissionRequiredDialog(Permission permission) {
    showDialog<void>(
      context: context,
      barrierDismissible: false, // 点击外部不关闭
      builder: (ctx) => AlertDialog(
        title: const Text('需要存储权限'),
        content: const Text('此应用需要存储权限才能保存下载的文件。\n\n请授权后使用。'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              SystemNavigator.pop(); // 退出应用
            },
            child: const Text('退出'),
          ),
          FilledButton(
            onPressed: () async {
              final result = await permission.request();
              final recheck = await permission.status;
              if (result.isGranted || recheck.isGranted || recheck.isLimited) {
                if (ctx.mounted) Navigator.pop(ctx);
              } else if (result.isPermanentlyDenied || recheck.isPermanentlyDenied) {
                // 永久拒绝，引导去设置
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  openAppSettings();
                  // 返回后再次检查
                  Future.delayed(const Duration(milliseconds: 500), () {
                    if (mounted) _checkStoragePermission();
                  });
                }
              }
            },
            child: const Text('授权'),
          ),
        ],
      ),
    );
  }

  // ─── 解析逻辑 ─────────────────────────────────────────────────────

  /// 解析输入
  Future<void> _parse() async {
    // 让输入框失去焦点，隐藏键盘
    FocusScope.of(context).unfocus();

    final input = _inputCtrl.text.trim();
    if (input.isEmpty) return;

    final result =
        await ref.read(videoNotifierProvider.notifier).parse(input);

    // 处理需要 UI 反馈的结果
    if (result.shouldShowErrorSnack && mounted) {
      final message = switch (result.type) {
        ParseResultType.invalidUrl => '未找到有效的链接，请粘贴抖音/小红书分享文本或链接',
        ParseResultType.unsupportedPlatform => '目前仅支持抖音/小红书链接',
        ParseResultType.error => result.errorMessage ?? '解析失败，请稍后重试',
        _ => '解析失败',
      };

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    // 解析成功：重置下载状态
    if (result.isSuccess) {
      ref.read(downloadNotifierProvider.notifier).reset();
    }
  }

  // ─── 下载逻辑 ─────────────────────────────────────────────────────

  /// 下载主内容
  Future<void> _download() async {
    final result = await ref.read(downloadNotifierProvider.notifier).download();
    _handleDownloadResult(result);
  }

  /// 下载单个图片
  Future<void> _downloadSingleImage(int index) async {
    final result =
        await ref.read(downloadNotifierProvider.notifier).downloadSingleImage(index);
    _handleDownloadResult(result, index: index, type: '图片');
  }

  /// 下载单个实况视频
  Future<void> _downloadSingleLivePhoto(int index) async {
    final result =
        await ref.read(downloadNotifierProvider.notifier).downloadSingleLivePhoto(index);
    _handleDownloadResult(result, index: index, type: '实况视频');
  }

  /// 下载背景音乐
  Future<void> _downloadMusic() async {
    final result = await ref.read(downloadNotifierProvider.notifier).downloadMusic();
    _handleDownloadResult(result, type: '背景音乐');
  }

  /// 下载动图视频
  Future<void> _downloadLiveVideos() async {
    final result = await ref.read(downloadNotifierProvider.notifier).downloadLiveVideos();
    _handleDownloadResult(result, type: '动图视频');
  }

  /// 处理下载结果
  void _handleDownloadResult(DownloadResult result, {int? index, String? type}) {
    if (!mounted) return;

    // 权限被拒绝
    if (result.shouldShowPermissionDialog) {
      _showPermissionDeniedDialog();
      return;
    }

    // 成功
    if (result.isSuccess) {
      // 清空输入
      _inputCtrl.clear();

      // 显示成功提示
      final message = _buildSuccessMessage(result, index: index, type: type);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
        ),
      );

      // 单个下载：延迟清除进度
      if (index != null) {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            ref.read(downloadNotifierProvider.notifier).clearSingleProgress(index);
          }
        });
      }
    }

    // 失败
    if (result.type == DownloadResultType.error && result.errorMessage != null) {
      final label = type != null && index != null ? '$type ${index + 1}' : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$label 下载失败'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// 构建成功消息
  String _buildSuccessMessage(DownloadResult result, {int? index, String? type}) {
    if (type != null && index != null) {
      return '$type ${index + 1} 已保存';
    }
    if (result.count != null) {
      return '动图视频已保存（${result.count} 个）';
    }
    if (result.isBatch) {
      return '已保存到 ${result.path}';
    }
    return '已保存到 ${result.path}';
  }

  /// 显示权限被永久拒绝的对话框
  void _showPermissionDeniedDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('需要存储权限'),
        content: const Text('存储权限已被永久拒绝，请在系统设置中手动开启后重试。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }

  // ─── 构建界面 ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // 监听状态
    final videoState = ref.watch(videoNotifierProvider);
    final downloadState = ref.watch(downloadNotifierProvider);

    final isAndroid = Platform.isAndroid;

    return Scaffold(
      appBar: AppBar(
        title: LayoutBuilder(
          builder: (context, constraints) {
            // 小屏用短标题
            return Text(
              MediaQuery.of(context).size.width <= 420
                  ? 'Umao 视频下载'
                  : 'Umao VDownloader - 短视频下载',
            );
          },
        ),
        actions: [
          // 设置按钮
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: '设置',
            onPressed: _openLogSettingsPanel,
          ),
          // 日志按钮
          IconButton(
            icon: const Icon(Icons.article_outlined),
            tooltip: '查看日志',
            onPressed: _openLogPanel,
          ),
          const SizedBox(width: 8),
        ],
      ),
      // Android 允许输入法覆盖
      resizeToAvoidBottomInset: isAndroid,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          child: _buildMainContent(videoState, downloadState),
        ),
      ),
    );
  }

  /// 主内容区
  Widget _buildMainContent(VideoState videoState, DownloadState downloadState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 顶部输入行（固定）
        InputRow(
          controller: _inputCtrl,
          parsing: videoState.parsing,
          onParse: _parse,
        ),
        const SizedBox(height: 10),
        // 中间结果区域（可滚动）
        Expanded(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: _buildResultCard(videoState, downloadState),
          ),
        ),
        const SizedBox(height: 10),
        // 底部目录行（固定）
        DirectoryRow(
          settings: _settings,
          onPickDirectory: _pickDirectory,
          onOpenDirectory: _openDirectory,
        ),
      ],
    );
  }

  /// 打开日志面板
  Future<void> _openLogPanel() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          decoration: BoxDecoration(
            color: Theme.of(ctx).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 拖拽指示条
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // 日志面板
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: LogPanel(
                    log: _log,
                    settings: _settings,
                    scrollController: ScrollController(),
                    onCopyTap: _copyLogContent,
                    onClearTap: () => setState(() => _log.entries.clear()),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── 解析结果卡片 ──────────────────────────────────────────────

  Widget _buildResultCard(VideoState videoState, DownloadState downloadState) {
    if (videoState.videoInfo == null && !videoState.parsing) {
      return Container(
        height: 280,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Text('解析结果将显示在这里', style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    if (videoState.parsing) {
      return const SizedBox(
        height: 280,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final info = videoState.videoInfo!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 400;
        return Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 标题（可复制，截断到80字符）
                SelectableText(
                  _truncateTitle(info.title),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _buildMetaInfo(info),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                // 封面图/缩略图
                if (info.mediaType != MediaType.video &&
                    info.imageUrls.isNotEmpty)
                  ThumbnailGrid(
                    videoInfo: info,
                    scrollController: _thumbScrollCtrl,
                    singleProgress: downloadState.singleProgressMap,
                    singleDownloading: downloadState.singleDownloadingMap,
                    singleDone: downloadState.singleDoneMap,
                    onDownloadImage: _downloadSingleImage,
                    onDownloadLivePhoto: _downloadSingleLivePhoto,
                  ),
                // 普通视频显示封面
                if (info.mediaType == MediaType.video && info.coverUrl != null)
                  VideoCover(coverUrl: info.coverUrl!),
                const SizedBox(height: 12),
                // 操作区
                if (narrow)
                  DownloadActionsNarrow(
                    videoInfo: info,
                    downloading: downloadState.downloading,
                    downloadProgress: downloadState.downloadProgress,
                    downloadingMusic: downloadState.downloadingMusic,
                    downloadingLiveVideos: downloadState.downloadingLiveVideos,
                    liveVideoProgress: downloadState.liveVideoProgress,
                    fileSizeBytes: videoState.fileSizeBytes,
                    fetchingSize: videoState.fetchingSize,
                    onDownload: _download,
                    onDownloadMusic: _downloadMusic,
                    onDownloadLiveVideos: _downloadLiveVideos,
                  )
                else
                  DownloadActionsWide(
                    videoInfo: info,
                    downloading: downloadState.downloading,
                    downloadProgress: downloadState.downloadProgress,
                    downloadingMusic: downloadState.downloadingMusic,
                    downloadingLiveVideos: downloadState.downloadingLiveVideos,
                    liveVideoProgress: downloadState.liveVideoProgress,
                    fileSizeBytes: videoState.fileSizeBytes,
                    fetchingSize: videoState.fetchingSize,
                    onDownload: _download,
                    onDownloadMusic: _downloadMusic,
                    onDownloadLiveVideos: _downloadLiveVideos,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 截断标题到指定长度（默认80字符）
  String _truncateTitle(String title, [int maxLen = 80]) {
    final text = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length <= maxLen) return text;
    return '${text.substring(0, maxLen)}...';
  }

  /// 构建元信息文本：ID · 类型 · 数量
  String _buildMetaInfo(VideoInfo info) {
    final id = info.shareId ?? info.itemId;
    final (type, count) = switch (info.mediaType) {
      MediaType.image => ('图文', '${info.imageUrls.length}'),
      MediaType.livePhoto => ('实况图', '${info.livePhotoUrls.length}'),
      MediaType.video => ('视频', '1'),
    };
    return 'ID: $id · 类型: $type · 数量: $count';
  }

  // ─── 日志设置面板 ────────────────────────────────────────────

  Future<void> _openLogSettingsPanel() async {
    var verbose = _settings.verboseLog;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.tune),
                      title: Text('设置'),
                    ),
                    SwitchListTile.adaptive(
                      value: verbose,
                      onChanged: (v) async {
                        setSheetState(() => verbose = v);
                        await _settings.setVerboseLog(v);
                        AppLogger.setVerbose(v);
                        _log.info(v ? '已开启详细日志输出' : '已关闭详细日志输出');
                      },
                      title: const Text('详细日志'),
                    ),
                    // 分隔线
                    const Divider(height: 24),
                    // 关于信息
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      leading: const Icon(Icons.info_outline),
                      title: const Text('About'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text('Umao VDownloader v${_appVersion.isNotEmpty ? _appVersion : "..."}'),
                          const Text('mcxiaoke'),
                          const SizedBox(height: 4),
                          GestureDetector(
                            onTap: () => _openUrl(kGitHubUrl),
                            child: Text(
                              kGitHubUrl,
                              style: TextStyle(
                                color: Theme.of(ctx).primaryColor,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ─── 目录操作 ────────────────────────────────────────────────

  Future<void> _pickDirectory() async {
    final savedDir = _settings.downloadDir;
    final initialDir = savedDir.isNotEmpty && await Directory(savedDir).exists()
        ? savedDir
        : null;
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择下载目录',
      initialDirectory: initialDir,
    );
    if (result != null) {
      await _settings.setDownloadDir(result);
      _log.info('下载目录已更改为：$result');
    }
  }

  void _openDirectory(String path) {
    if (Platform.isWindows) {
      Process.run('explorer', [path]);
    } else if (Platform.isMacOS) {
      Process.run('open', [path]);
    }
  }

  /// 打开 URL（桌面用系统浏览器，移动端用 url_launcher）
  Future<void> _openUrl(String url) async {
    if (Platform.isWindows) {
      Process.run('start', [url], runInShell: true);
    } else if (Platform.isMacOS) {
      Process.run('open', [url]);
    } else if (Platform.isLinux) {
      Process.run('xdg-open', [url]);
    } else {
      // 移动端使用 url_launcher
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  void _copyLogContent() {
    if (_log.entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('当前没有日志可复制'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final content = _log.entries.map((e) => e.toString()).join('\n');
    Clipboard.setData(ClipboardData(text: content));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制日志内容（${_log.entries.length} 条）'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ─── 生命周期 ────────────────────────────────────────────────

  @override
  void dispose() {
    _inputCtrl.dispose();
    _thumbScrollCtrl.dispose();
    super.dispose();
  }
}
