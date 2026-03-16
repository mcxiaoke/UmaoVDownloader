import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_logger.dart';
import '../services/log_service.dart';
import '../services/parser_common.dart';
import '../services/parser_facade.dart';
import '../services/settings_service.dart';
import 'mixins/downloader_mixin.dart';
import 'mixins/parser_mixin.dart';
import 'widgets/directory_row.dart';
import 'widgets/download_actions.dart';
import 'widgets/input_row.dart';
import 'widgets/log_panel.dart';
import 'widgets/thumbnail_grid.dart';
import 'widgets/video_cover.dart';

/// GitHub 项目地址
const String kGitHubUrl = 'https://github.com/mcxiaoke/UmaoVDownloader';

/// 主页
class HomePage extends StatefulWidget {
  final LogService log;
  final SettingsService settings;

  const HomePage({super.key, required this.log, required this.settings});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with ParserMixin, DownloaderMixin {
  final _inputCtrl = TextEditingController();
  final _thumbScrollCtrl = ScrollController();
  final _parserFacade = ParserFacade();
  bool _screenSizeLogged = false;
  String _appVersion = '';

  // ─── ParserMixin 所需状态 ─────────────────────────────────────

  @override
  TextEditingController get inputController => _inputCtrl;

  @override
  LogService get log => widget.log;

  @override
  SettingsService get settings => widget.settings;

  @override
  ParserFacade get parserFacade => _parserFacade;

  bool _parsing = false;
  @override
  bool get parsing => _parsing;
  @override
  set parsing(bool value) => _parsing = value;

  VideoInfo? _videoInfo;
  @override
  VideoInfo? get videoInfo => _videoInfo;
  @override
  set videoInfo(VideoInfo? value) => _videoInfo = value;

  int? _fileSizeBytes;
  @override
  int? get fileSizeBytes => _fileSizeBytes;
  @override
  set fileSizeBytes(int? value) => _fileSizeBytes = value;

  bool _fetchingSize = false;
  @override
  bool get fetchingSize => _fetchingSize;
  @override
  set fetchingSize(bool value) => _fetchingSize = value;

  // ─── DownloaderMixin 所需状态 ─────────────────────────────────

  bool _downloading = false;
  @override
  bool get downloading => _downloading;
  @override
  set downloading(bool value) => _downloading = value;

  double? _downloadProgress;
  @override
  double? get downloadProgress => _downloadProgress;
  @override
  set downloadProgress(double? value) => _downloadProgress = value;

  int? _lastVerboseProgressBucket;
  @override
  int? get lastVerboseProgressBucket => _lastVerboseProgressBucket;
  @override
  set lastVerboseProgressBucket(int? value) =>
      _lastVerboseProgressBucket = value;

  bool _downloadingMusic = false;
  @override
  bool get downloadingMusic => _downloadingMusic;
  @override
  set downloadingMusic(bool value) => _downloadingMusic = value;

  bool _downloadingLiveVideos = false;
  @override
  bool get downloadingLiveVideos => _downloadingLiveVideos;
  @override
  set downloadingLiveVideos(bool value) => _downloadingLiveVideos = value;

  double? _liveVideoProgress;
  @override
  double? get liveVideoProgress => _liveVideoProgress;
  @override
  set liveVideoProgress(double? value) => _liveVideoProgress = value;

  final Map<int, double> _singleProgress = {};
  @override
  Map<int, double> get singleProgress => _singleProgress;

  final Map<int, bool> _singleDownloading = {};
  @override
  Map<int, bool> get singleDownloading => _singleDownloading;

  final Map<int, bool> _singleDone = {};
  @override
  Map<int, bool> get singleDone => _singleDone;

  @override
  void initState() {
    super.initState();
    _initAppVersion();
    if (Platform.isAndroid) {
      _checkStoragePermission();
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

  // ─── 回调 ───────────────────────────────────────────────────

  @override
  void resetDownloadProgress() {
    _downloadProgress = null;
    _liveVideoProgress = null;
    _downloadingLiveVideos = false;
    _singleProgress.clear();
    _singleDownloading.clear();
    _singleDone.clear();
  }

  @override
  void onParseSuccess(VideoInfo info) {
    resetDownloadProgress();
    _downloadingMusic = false;
  }

  @override
  void onDownloadComplete(String path) {
    _inputCtrl.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已保存到 $path'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // ─── 构建界面 ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isAndroid = Platform.isAndroid;
    if (!_screenSizeLogged) {
      _screenSizeLogged = true;
      final mediaQuery = MediaQuery.of(context);
      final screenWidth = mediaQuery.size.width;
      final screenHeight = mediaQuery.size.height;
      final devicePixelRatio = mediaQuery.devicePixelRatio;
      widget.log.info(
        '屏幕: ${screenWidth.toStringAsFixed(0)} x ${screenHeight.toStringAsFixed(0)} '
        '逻辑像素, 设备像素比: ${devicePixelRatio.toStringAsFixed(2)}',
      );
    }
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
          child: _buildMainContent(),
        ),
      ),
    );
  }

  /// 主内容区
  Widget _buildMainContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 顶部输入行（固定）
        InputRow(controller: _inputCtrl, parsing: _parsing, onParse: parse),
        const SizedBox(height: 10),
        // 中间结果区域（可滚动）
        Expanded(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: _buildResultCard(),
          ),
        ),
        const SizedBox(height: 10),
        // 底部目录行（固定）
        DirectoryRow(
          settings: widget.settings,
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
                    log: widget.log,
                    settings: widget.settings,
                    scrollController: ScrollController(),
                    onCopyTap: _copyLogContent,
                    onClearTap: () =>
                        setState(() => widget.log.entries.clear()),
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

  Widget _buildResultCard() {
    if (_videoInfo == null && !_parsing) {
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

    if (_parsing) {
      return const SizedBox(
        height: 280,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final info = _videoInfo!;

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
                    singleProgress: _singleProgress,
                    singleDownloading: _singleDownloading,
                    singleDone: _singleDone,
                    onDownloadImage: downloadSingleImage,
                    onDownloadLivePhoto: downloadSingleLivePhoto,
                  ),
                // 普通视频显示封面
                if (info.mediaType == MediaType.video && info.coverUrl != null)
                  VideoCover(coverUrl: info.coverUrl!),
                const SizedBox(height: 12),
                // 操作区
                if (narrow)
                  DownloadActionsNarrow(
                    videoInfo: info,
                    downloading: _downloading,
                    downloadProgress: _downloadProgress,
                    downloadingMusic: _downloadingMusic,
                    downloadingLiveVideos: _downloadingLiveVideos,
                    liveVideoProgress: _liveVideoProgress,
                    fileSizeBytes: _fileSizeBytes,
                    fetchingSize: _fetchingSize,
                    onDownload: download,
                    onDownloadMusic: downloadMusicOnly,
                    onDownloadLiveVideos: downloadLiveVideos,
                  )
                else
                  DownloadActionsWide(
                    videoInfo: info,
                    downloading: _downloading,
                    downloadProgress: _downloadProgress,
                    downloadingMusic: _downloadingMusic,
                    downloadingLiveVideos: _downloadingLiveVideos,
                    liveVideoProgress: _liveVideoProgress,
                    fileSizeBytes: _fileSizeBytes,
                    fetchingSize: _fetchingSize,
                    onDownload: download,
                    onDownloadMusic: downloadMusicOnly,
                    onDownloadLiveVideos: downloadLiveVideos,
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
    var verbose = widget.settings.verboseLog;

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
                        await widget.settings.setVerboseLog(v);
                        AppLogger.setVerbose(v);
                        widget.log.info(v ? '已开启详细日志输出' : '已关闭详细日志输出');
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
    final savedDir = widget.settings.downloadDir;
    final initialDir = savedDir.isNotEmpty && await Directory(savedDir).exists()
        ? savedDir
        : null;
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择下载目录',
      initialDirectory: initialDir,
    );
    if (result != null) {
      await widget.settings.setDownloadDir(result);
      widget.log.info('下载目录已更改为：$result');
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
    if (widget.log.entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('当前没有日志可复制'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final content = widget.log.entries.map((e) => e.toString()).join('\n');
    Clipboard.setData(ClipboardData(text: content));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制日志内容（${widget.log.entries.length} 条）'),
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
