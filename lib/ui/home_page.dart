import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  final _logScrollCtrl = ScrollController();
  final _thumbScrollCtrl = ScrollController();
  final _parserFacade = ParserFacade();

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
  set lastVerboseProgressBucket(int? value) => _lastVerboseProgressBucket = value;

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

  // ─── 回调 ───────────────────────────────────────────────────

  @override
  void resetDownloadProgress() {
    _downloadProgress = null;
    _liveVideoProgress = null;
    _downloadingLiveVideos = false;
    _singleProgress.clear();
    _singleDownloading.clear();
  }

  @override
  void onParseSuccess(VideoInfo info) {
    resetDownloadProgress();
    _downloadingMusic = false;
  }

  @override
  void onDownloadComplete() {
    _inputCtrl.clear();
  }

  // ─── 构建界面 ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isAndroid = Platform.isAndroid;
    return Scaffold(
      appBar: AppBar(title: const Text('Umao VDownloader - 短视频下载')),
      // Android 允许输入法覆盖日志区域
      resizeToAvoidBottomInset: isAndroid,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          child: _buildUnifiedLayout(),
        ),
      ),
    );
  }

  /// 统一布局：自适应多平台
  Widget _buildUnifiedLayout() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 上面区域自适应，日志占满剩余空间，但日志最小100px
        final maxContentHeight = constraints.maxHeight - 100 - 8;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 上面区域：限制最大高度，超出可滚动
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxContentHeight),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InputRow(
                      controller: _inputCtrl,
                      parsing: _parsing,
                      onParse: parse,
                    ),
                    const SizedBox(height: 10),
                    _buildResultCard(),
                    const SizedBox(height: 10),
                    DirectoryRow(
                      settings: widget.settings,
                      onPickDirectory: _pickDirectory,
                      onOpenDirectory: _openDirectory,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // 日志区域：占满剩余空间
            Expanded(
              child: LogPanel(
                log: widget.log,
                settings: widget.settings,
                scrollController: _logScrollCtrl,
                onSettingsTap: _openLogSettingsPanel,
                onCopyTap: _copyLogContent,
                onClearTap: () => setState(() => widget.log.entries.clear()),
              ),
            ),
          ],
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
                // 标题（可复制，截断到40字符）
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

  /// 截断标题到指定长度（默认40字符）
  String _truncateTitle(String title, [int maxLen = 40]) {
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
                      title: Text('日志设置'),
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
                    if (widget.log.logFilePath != null)
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                        ),
                        leading: const Icon(Icons.copy_all),
                        title: const Text('复制日志路径'),
                        onTap: () {
                          Clipboard.setData(
                            ClipboardData(text: widget.log.logFilePath!),
                          );
                          Navigator.of(ctx).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('日志路径已复制'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
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
    _logScrollCtrl.dispose();
    _thumbScrollCtrl.dispose();
    super.dispose();
  }
}
