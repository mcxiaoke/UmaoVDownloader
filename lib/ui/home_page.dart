import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/douyin_parser.dart';
import '../services/downloader/base_downloader.dart';
import '../services/downloader/desktop_downloader.dart';
import '../services/downloader/mobile_downloader.dart';
import '../services/log_service.dart';
import '../services/parser_facade.dart';
import '../services/settings_service.dart';
import '../services/url_extractor.dart';

/// 主页
class HomePage extends StatefulWidget {
  final LogService log;
  final SettingsService settings;

  const HomePage({super.key, required this.log, required this.settings});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _inputCtrl = TextEditingController();
  final _logScrollCtrl = ScrollController();
  final _thumbScrollCtrl = ScrollController();
  final _parserFacade = ParserFacade();

  // 解析状态
  bool _parsing = false;
  VideoInfo? _videoInfo;

  // 文件大小预获取
  int? _fileSizeBytes; // null = 未知/加载中
  bool _fetchingSize = false;

  // 下载状态
  bool _downloading = false;
  double? _downloadProgress; // null = 不显示，0.0–1.0
  int? _lastVerboseProgressBucket;
  bool _downloadingMusic = false; // 单独下载音乐状态

  // 单个 Live Photo 下载状态 (index -> progress)
  final Map<int, double> _singleLivePhotoProgress = {};
  final Map<int, bool> _singleLivePhotoDownloading = {};

  LogService get _log => widget.log;
  SettingsService get _settings => widget.settings;

  bool get _verbose => _settings.verboseLog;

  void _vlog(String msg) {
    if (_verbose) _log.info(msg);
  }

  // ─── 解析 ────────────────────────────────────────────────────

  Future<void> _parse() async {
    // 让输入框失去焦点，隐藏键盘
    FocusScope.of(context).unfocus();

    final input = _inputCtrl.text.trim();
    if (input.isEmpty) return;

    _vlog('原始输入长度=${input.length}');

    final url = UrlExtractor.extractFirst(input);
    if (url == null) {
      _log.warn('无效输入，未找到链接');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('未找到有效的链接，请粘贴抖音/小红书分享文本或链接'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    // 校验是否为支持的平台
    final platform = ParserPlatform.fromUrl(url);
    if (platform == ParserPlatform.unknown) {
      _log.warn('不支持的链接: $url');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('仅支持抖音/小红书链接，检测到: ${Uri.parse(url).host}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    setState(() {
      _parsing = true;
      _videoInfo = null;
      _downloadProgress = null;
    });
    _log.info('开始解析：$url');
    _vlog('当前平台: ${Platform.operatingSystem}');
    _vlog('策略=${_settings.parserStrategy.value}');
    final enableCompare =
        _settings.compareParsers &&
        _settings.parserStrategy == ParserStrategy.auto;
    _vlog('并行对比=${enableCompare ? "开启" : "关闭"}');
    final sw = Stopwatch()..start();

    try {
      final info = await _parserFacade.parse(
        url,
        strategy: _settings.parserStrategy,
        compareParsers: enableCompare,
        log: (m) => _vlog(m),
      );

      setState(() {
        _videoInfo = info;
        _fileSizeBytes = null;
        _downloadingMusic = false;
      });
      // 视频作品：获取文件大小
      if (info.mediaType == MediaType.video && info.videoUrl.isNotEmpty) {
        _fetchFileSize(info);
      }
      _log.info('解析成功：${info.title}');
      _vlog('解析耗时: ${sw.elapsedMilliseconds} ms');
      _log.info('itemId=${info.itemId}');
      switch (info.mediaType) {
        case MediaType.image:
          _log.info('图文作品，共 ${info.imageUrls.length} 张图片');
          _vlog('musicUrl=${info.musicUrl ?? "<none>"}');
        case MediaType.livePhoto:
          _log.info('实况图作品，共 ${info.livePhotoUrls.length} 个视频');
          _vlog('封面=${info.coverUrl ?? "<none>"}');
        case MediaType.video:
          _log.info('fileId=${info.videoFileId}');
          _vlog('封面=${info.coverUrl ?? "<none>"}');
          _vlog('分辨率=${info.resolutionLabel ?? "<unknown>"}');
          _vlog('videoUrl=${info.videoUrl}');
      }
    } catch (e, st) {
      _log.error('解析失败：$e');
      _vlog('解析异常堆栈: $st');
    } finally {
      sw.stop();
      setState(() => _parsing = false);
    }
  }

  // ─── 文件大小预获取 ────────────────────────────────────────────

  /// 获取视频文件大小
  Future<void> _fetchFileSize(VideoInfo info) async {
    if (_fetchingSize) return;
    setState(() {
      _fileSizeBytes = null;
      _fetchingSize = true;
    });

    try {
      _vlog('开始获取视频文件大小');

      final ioClient = HttpClient();
      String resolvedUrl = info.videoUrl;
      try {
        final req = await ioClient.getUrl(Uri.parse(info.videoUrl));
        req.headers.set(HttpHeaders.userAgentHeader, kUaEdge);
        req.followRedirects = false;
        final resp = await req.close();
        await resp.drain<void>();
        if (resp.statusCode >= 300 && resp.statusCode < 400) {
          resolvedUrl =
              resp.headers.value(HttpHeaders.locationHeader) ?? info.videoUrl;
        }
      } finally {
        ioClient.close();
      }
      final headResp = await http.head(
        Uri.parse(resolvedUrl),
        headers: {HttpHeaders.userAgentHeader: kUaEdge},
      );
      final cl = headResp.headers['content-length'];
      final size = cl != null ? int.tryParse(cl) : null;

      if (mounted) {
        setState(() {
          _fileSizeBytes = size;
          _fetchingSize = false;
        });
      }

      _vlog('视频文件大小: ${_formatFileSize(size)}');
    } catch (e) {
      _vlog('获取文件大小失败: $e');
      if (mounted) {
        setState(() {
          _fetchingSize = false;
        });
      }
    }
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null) return 'unknown';
    final mb = bytes / (1024 * 1024);
    if (mb >= 1) return '${mb.toStringAsFixed(2)} MB';
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }

  // ─── 下载 ────────────────────────────────────────────────────

  /// 下载单个 Live Photo 视频
  Future<void> _downloadSingleLivePhoto(int index) async {
    final info = _videoInfo;
    if (info == null || info.livePhotoUrls.isEmpty) return;
    if (_singleLivePhotoDownloading[index] == true) return;

    final url = info.livePhotoUrls[index];
    final prefix = info.shareId ?? info.itemId;
    final cleanTitle = _sanitizeFilename(info.title);
    final filename = '${prefix}_${cleanTitle}_${index + 1}';

    setState(() {
      _singleLivePhotoDownloading[index] = true;
      _singleLivePhotoProgress[index] = 0;
    });
    _log.info('开始下载实况视频 ${index + 1}/${info.livePhotoUrls.length}');

    try {
      final downloader = (Platform.isAndroid || Platform.isIOS)
          ? MobileDownloader()
          : DesktopDownloader();
      final path = await downloader.downloadSingleLivePhoto(
        url,
        directory: _settings.downloadDir,
        filename: filename,
        onProgress: (received, total) {
          if (!mounted) return;
          if (total != null && total > 0) {
            setState(() => _singleLivePhotoProgress[index] = received / total);
          }
        },
        onLog: (msg) => _log.info('[DL] $msg'),
      );
      _log.info('实况视频 ${index + 1} 下载完成：$path');
      if (mounted) {
        setState(() => _singleLivePhotoProgress[index] = 1.0);
        // 2秒后清除进度状态
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            setState(() {
              _singleLivePhotoProgress.remove(index);
              _singleLivePhotoDownloading.remove(index);
            });
          }
        });
      }
    } on StoragePermissionDeniedException {
      _log.error('存储权限被永久拒绝，请到系统设置中手动开启');
      setState(() {
        _singleLivePhotoProgress.remove(index);
        _singleLivePhotoDownloading.remove(index);
      });
      if (mounted) _showPermissionDialog();
    } catch (e) {
      _log.error('实况视频 ${index + 1} 下载失败：$e');
      setState(() {
        _singleLivePhotoProgress.remove(index);
        _singleLivePhotoDownloading.remove(index);
      });
    }
  }

  /// 下载单个图片
  Future<void> _downloadSingleImage(int index) async {
    final info = _videoInfo;
    if (info == null || info.imageUrls.isEmpty) return;
    if (_singleLivePhotoDownloading[index] == true) return;

    final url = info.imageUrls[index];
    final prefix = info.shareId ?? info.itemId;
    final cleanTitle = _sanitizeFilename(info.title);
    final filename = '${prefix}_${cleanTitle}_${index + 1}';

    setState(() {
      _singleLivePhotoDownloading[index] = true;
      _singleLivePhotoProgress[index] = 0;
    });
    _log.info('开始下载图片 ${index + 1}/${info.imageUrls.length}');

    try {
      final downloader = (Platform.isAndroid || Platform.isIOS)
          ? MobileDownloader()
          : DesktopDownloader();
      final path = await downloader.downloadSingleImage(
        url,
        directory: _settings.downloadDir,
        filename: filename,
        onProgress: (received, total) {
          if (!mounted) return;
          if (total != null && total > 0) {
            setState(() => _singleLivePhotoProgress[index] = received / total);
          }
        },
        onLog: (msg) => _log.info('[DL] $msg'),
      );
      _log.info('图片 ${index + 1} 下载完成：$path');
      if (mounted) {
        setState(() => _singleLivePhotoProgress[index] = 1.0);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            setState(() {
              _singleLivePhotoProgress.remove(index);
              _singleLivePhotoDownloading.remove(index);
            });
          }
        });
      }
    } on StoragePermissionDeniedException {
      _log.error('存储权限被永久拒绝，请到系统设置中手动开启');
      setState(() {
        _singleLivePhotoProgress.remove(index);
        _singleLivePhotoDownloading.remove(index);
      });
      if (mounted) _showPermissionDialog();
    } catch (e) {
      _log.error('图片 ${index + 1} 下载失败：$e');
      setState(() {
        _singleLivePhotoProgress.remove(index);
        _singleLivePhotoDownloading.remove(index);
      });
    }
  }

  Future<void> _download() async {
    final info = _videoInfo;
    if (info == null || _downloading) return;

    setState(() {
      _downloading = true;
      _downloadProgress = 0;
      _lastVerboseProgressBucket = null;
    });
    final downloadLabel = switch (info.mediaType) {
      MediaType.image => '图文（${info.imageUrls.length} 张）',
      MediaType.livePhoto => '实况图（${info.livePhotoUrls.length} 个视频）',
      MediaType.video => '视频',
    };
    _log.info('开始下载 $downloadLabel：${info.title}');

    try {
      final downloader = (Platform.isAndroid || Platform.isIOS)
          ? MobileDownloader()
          : DesktopDownloader();
      _vlog(
        '下载器=${downloader.runtimeType}, 目录=${_settings.downloadDir}',
      );
      final path = await downloader.downloadVideo(
        info,
        directory: _settings.downloadDir,
        onProgress: (received, total) {
          if (!mounted) return;
          if (info.mediaType == MediaType.image || info.mediaType == MediaType.livePhoto) {
            // 图文或实况图：received = 当前张数/个数， total = 总数
            if (total != null && total > 0) {
              final p = received / total;
              setState(() => _downloadProgress = p);
              final bucket = (p * 10).floor();
              if (_verbose && _lastVerboseProgressBucket != bucket) {
                _lastVerboseProgressBucket = bucket;
                final type = info.mediaType == MediaType.image ? '图文' : '实况图';
                _vlog(
                  '$type下载进度 ${(p * 100).toStringAsFixed(0)}% ($received/$total)',
                );
              }
            }
          } else {
            final t = total ?? _fileSizeBytes;
            if (t != null && t > 0) {
              final p = received / t;
              setState(() => _downloadProgress = p);
              final bucket = (p * 10).floor();
              if (_verbose && _lastVerboseProgressBucket != bucket) {
                _lastVerboseProgressBucket = bucket;
                _vlog('视频下载进度 ${(p * 100).toStringAsFixed(0)}% ($received/$t)');
              }
            }
          }
        },
        onLog: (msg) => _log.info('[DL] $msg'),
      );
      _log.info('下载完成：$path');
      setState(() => _downloadProgress = 1.0);
      _inputCtrl.clear();
    } on StoragePermissionDeniedException {
      _log.error('存储权限被永久拒绝，请到系统设置中手动开启');
      setState(() => _downloadProgress = null);
      if (mounted) _showPermissionDialog();
    } catch (e) {
      _log.error('下载失败：$e');
      setState(() => _downloadProgress = null);
    } finally {
      setState(() => _downloading = false);
    }
  }

  /// 单独下载背景音乐
  Future<void> _downloadMusicOnly() async {
    final info = _videoInfo;
    if (info == null || info.musicUrl == null || _downloadingMusic) return;

    setState(() => _downloadingMusic = true);

    try {
      final downloader = (Platform.isAndroid || Platform.isIOS)
          ? MobileDownloader()
          : DesktopDownloader();

      final prefix = info.shareId ?? info.itemId;
      final cleanTitle = _sanitizeFilename(info.title);
      String filename;
      if (info.musicAuthor != null && info.musicTitle != null) {
        final cleanAuthor = _sanitizeFilename(info.musicAuthor!, maxLen: 50);
        final cleanMusicTitle = _sanitizeFilename(info.musicTitle!, maxLen: 50);
        filename = '${prefix}_${cleanAuthor} - ${cleanMusicTitle}';
      } else {
        filename = '${prefix}_${cleanTitle}_bgm';
      }

      final path = await downloader.downloadMusicFile(
        info.musicUrl!,
        filename: filename,
        onLog: (msg) => _log.info('[DL] $msg'),
      );

      if (path == null) {
        _log.warn('背景音乐下载失败');
      }
    } on StoragePermissionDeniedException {
      _log.error('存储权限被永久拒绝，请到系统设置中手动开启');
      if (mounted) _showPermissionDialog();
    } catch (e) {
      _log.error('背景音乐下载失败：$e');
    } finally {
      setState(() => _downloadingMusic = false);
    }
  }

  // ─── 选择目录 ────────────────────────────────────────────────

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

  Future<void> _openLogSettingsPanel() async {
    var verbose = _settings.verboseLog;
    var compare = _settings.compareParsers;
    var parserStrategy = _settings.parserStrategy;

    String parserLabel(ParserStrategy s) {
      return switch (s) {
        ParserStrategy.auto => '自动',
        ParserStrategy.dartOnly => 'Dart解析器',
        ParserStrategy.jsOnly => 'JS解析器',
      };
    }

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
                        await _settings.setVerboseLog(v);
                        _log.info(v ? '已开启详细日志输出' : '已关闭详细日志输出');
                      },
                      title: const Text('详细日志'),
                    ),
                    SwitchListTile.adaptive(
                      value: compare,
                      onChanged: parserStrategy == ParserStrategy.auto
                          ? (v) async {
                              setSheetState(() => compare = v);
                              await _settings.setCompareParsers(v);
                              _log.info(v ? '已开启双解析器并行对比' : '已关闭双解析器并行对比');
                            }
                          : null,
                      subtitle: parserStrategy == ParserStrategy.auto
                          ? null
                          : const Text('仅自动模式生效'),
                      title: const Text('解析器并行对比'),
                    ),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      leading: const Icon(Icons.memory),
                      title: const Text('解析器选择'),
                      subtitle: Text(parserLabel(parserStrategy)),
                      trailing: DropdownButton<ParserStrategy>(
                        value: parserStrategy,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(
                            value: ParserStrategy.auto,
                            child: Text('自动'),
                          ),
                          DropdownMenuItem(
                            value: ParserStrategy.dartOnly,
                            child: Text('Dart解析器'),
                          ),
                          DropdownMenuItem(
                            value: ParserStrategy.jsOnly,
                            child: Text('JS解析器'),
                          ),
                        ],
                        onChanged: (v) async {
                          if (v == null) return;
                          setSheetState(() => parserStrategy = v);
                          await _settings.setParserStrategy(v);
                          _log.info('解析器已切换为：${parserLabel(v)}');
                        },
                      ),
                    ),
                    if (_log.logFilePath != null)
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                        ),
                        leading: const Icon(Icons.copy_all),
                        title: const Text('复制日志路径'),
                        onTap: () {
                          Clipboard.setData(
                            ClipboardData(text: _log.logFilePath!),
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

  // 权限被永久拒绝时弹对话框引导用户去设置页
  void _showPermissionDialog() {
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

  // ─── 构建 ────────────────────────────────────────────────────

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
  /// - 上面区域（输入、结果、目录）自然排列，可滚动
  /// - 日志区域占满剩余空间
  Widget _buildUnifiedLayout() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 上面区域自适应，日志占满剩余空间，但日志最小100px
        final maxContentHeight = constraints.maxHeight - 100 - 8; // 减去日志最小高度和间距

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
                    _buildInputRow(),
                    const SizedBox(height: 10),
                    _buildResultCard(),
                    const SizedBox(height: 10),
                    _buildDirectoryRow(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // 日志区域：占满剩余空间
            Expanded(child: _buildLogPanel()),
          ],
        );
      },
    );
  }

  // ── 输入区 ───────────────────────────────────────────────────

  Widget _buildInputRow() {
    final parseButton = FilledButton.icon(
      onPressed: _parsing ? null : _parse,
      icon: _parsing
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.search, size: 18),
      label: const Text('解析'),
    );

    final inputField = TextField(
      controller: _inputCtrl,
      decoration: const InputDecoration(
        hintText: '粘贴抖音/小红书分享文本或链接…',
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      maxLines: 1,
      onSubmitted: (_) => _parse(),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 520;
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              inputField,
              const SizedBox(height: 8),
              SizedBox(height: 40, child: parseButton),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: inputField),
            const SizedBox(width: 8),
            parseButton,
          ],
        );
      },
    );
  }

  // ── 解析结果卡片 ──────────────────────────────────────────────

  Widget _buildResultCard() {
    if (_videoInfo == null && !_parsing) {
      return Container(
        height: 280, // 默认高度扩大一倍
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
        height: 280, // 加载状态高度也扩大
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
                // 标题（可复制）
                SelectableText(
                  info.title.replaceAll(RegExp(r'\s+'), ' '),
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
                // 封面图/缩略图：图文作品或实况图显示缩略图，普通视频显示封面
                if (info.mediaType != MediaType.video && info.imageUrls.isNotEmpty)
                  _buildThumbnailGrid(info),
                // 普通视频显示封面
                if (info.mediaType == MediaType.video && info.coverUrl != null)
                  _buildVideoCover(info.coverUrl!),
                const SizedBox(height: 12),
                // 操作区
                if (narrow)
                  _buildActionsNarrow(info)
                else
                  _buildActionsWide(info),
                // 进度条
                if (_downloading ||
                    (_downloadProgress != null && _downloadProgress! < 1.0))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: switch (info.mediaType) {
                      MediaType.image => LinearProgressIndicator(
                          value: _downloadProgress,
                          semanticsLabel:
                              '已下载 ${((_downloadProgress ?? 0) * info.imageUrls.length).round()} / ${info.imageUrls.length} 张',
                        ),
                      MediaType.livePhoto => LinearProgressIndicator(
                          value: _downloadProgress,
                          semanticsLabel:
                              '已下载 ${((_downloadProgress ?? 0) * info.livePhotoUrls.length).round()} / ${info.livePhotoUrls.length} 个',
                        ),
                      MediaType.video => LinearProgressIndicator(value: _downloadProgress),
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── 缩略图横向滚动列表（图文作品 / 实况图）─────────────────────────────────────

  Widget _buildThumbnailGrid(VideoInfo info) {
    final imageUrls = info.imageUrls;
    final imageThumbUrls = info.imageThumbUrls.isNotEmpty
        ? info.imageThumbUrls
        : info.imageUrls;
    if (imageUrls.isEmpty) return const SizedBox.shrink();

    final isLivePhoto = info.mediaType == MediaType.livePhoto;
    final itemCount = imageUrls.length;

    // 固定缩略图尺寸（统一卡片高度为120）
    const itemWidth = 80.0;
    const itemHeight = 116.0; // 约3:4比例，统一高度

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        height: itemHeight + 4, // 120总高度
        child: Listener(
          // 桌面端：鼠标滚轮转为横向滚动
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              // 将垂直滚轮事件转为横向滚动
              final newOffset = _thumbScrollCtrl.offset + event.scrollDelta.dy;
              if (newOffset >= 0 &&
                  newOffset <= _thumbScrollCtrl.position.maxScrollExtent) {
                _thumbScrollCtrl.jumpTo(newOffset);
              }
            }
          },
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
              },
            ),
            child: ListView.separated(
              controller: _thumbScrollCtrl,
              scrollDirection: Axis.horizontal,
              physics: const AlwaysScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: itemCount,
              separatorBuilder: (context, index) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final thumbUrl = imageThumbUrls[index];
                final isDownloading =
                    _singleLivePhotoDownloading[index] == true;
                final progress = _singleLivePhotoProgress[index];
                final isDone = (progress ?? 0) >= 0.99;

                return Stack(
                  children: [
                    // 缩略图
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: itemWidth,
                        height: itemHeight,
                        child: Image.network(
                          thumbUrl,
                          fit: BoxFit.cover,
                          headers: thumbUrl.contains('xhscdn.com')
                              ? const {'Referer': 'https://www.xiaohongshu.com/'}
                              : null,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              color: Colors.grey.shade200,
                              child: const Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Colors.grey.shade300,
                              child: const Icon(
                                Icons.broken_image,
                                color: Colors.grey,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    // Live Photo 标识（右上角）
                    if (isLivePhoto)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(179),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.videocam,
                                size: 10,
                                color: Colors.white,
                              ),
                              SizedBox(width: 2),
                              Text(
                                'LIVE',
                                style: TextStyle(
                                  fontSize: 8,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    // 下载按钮（底部中央）
                    Positioned(
                      bottom: 4,
                      left: 4,
                      right: 4,
                      child: SizedBox(
                        height: 24,
                        child: ElevatedButton(
                          onPressed: isDownloading || isDone
                              ? null
                              : () => isLivePhoto
                                    ? _downloadSingleLivePhoto(index)
                                    : _downloadSingleImage(index),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDone
                                ? Colors.green
                                : Colors.black.withAlpha(179),
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          child: isDownloading
                              ? SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    value:
                                        progress != null &&
                                            progress > 0 &&
                                            progress < 1
                                        ? progress
                                        : null,
                                    color: Colors.white,
                                  ),
                                )
                              : isDone
                              ? const Icon(Icons.check, size: 14)
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isLivePhoto
                                          ? Icons.download
                                          : Icons.download,
                                      size: 12,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      isLivePhoto ? 'MP4' : '图片',
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // ── 视频封面（普通视频）────────────────────────────────────────

  Widget _buildVideoCover(String coverUrl) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxHeight: 120, // 统一卡片高度
          ),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  coverUrl,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      color: Colors.grey.shade200,
                      child: const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.grey.shade300,
                      child: const Icon(
                        Icons.broken_image,
                        color: Colors.grey,
                        size: 48,
                      ),
                    );
                  },
                ),
                // 视频标识（右上角）
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(179),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.videocam, size: 10, color: Colors.white),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionsWide(VideoInfo info) {
    // 根据媒体类型确定按钮文字
    final downloadLabel = switch (info.mediaType) {
      MediaType.image => '下载图片',
      MediaType.livePhoto => '下载动图',
      MediaType.video => '下载视频',
    };

    // 下载按钮公用部分
    final downloadBtn = FilledButton.icon(
      onPressed: _downloading ? null : _download,
      icon: _downloading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.download, size: 18),
      label: Text(_downloading ? '下载中…' : downloadLabel),
    );
    final doneLabel = _downloadProgress == 1.0
        ? const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 18),
              SizedBox(width: 4),
              Text('下载完成', style: TextStyle(color: Colors.green, fontSize: 13)),
            ],
          )
        : const SizedBox.shrink();

    return switch (info.mediaType) {
      MediaType.image => Row(
          children: [
            Text(
              '图文作品  ${info.imageUrls.length} 张图片',
              style: const TextStyle(fontSize: 13),
            ),
            const Spacer(),
            if (info.musicUrl != null) ...[
              OutlinedButton.icon(
                onPressed: _downloadingMusic ? null : _downloadMusicOnly,
                icon: _downloadingMusic
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.deepPurple,
                        ),
                      )
                    : const Icon(Icons.music_note, size: 16),
                label: Text(_downloadingMusic ? '下载中…' : '下载音乐'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.deepPurple,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 8),
            ],
            doneLabel,
            if (doneLabel is! SizedBox) const SizedBox(width: 8),
            downloadBtn,
          ],
        ),
      MediaType.livePhoto => Row(
          children: [
            Text(
              '实况图  ${info.livePhotoUrls.length} 个',
              style: const TextStyle(fontSize: 13),
            ),
            const Spacer(),
            doneLabel,
            const SizedBox(width: 8),
            downloadBtn,
          ],
        ),
      MediaType.video => Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.videocam, size: 12, color: Colors.blue.shade700),
                  const SizedBox(width: 4),
                  Text(
                    '视频',
                    style: TextStyle(fontSize: 11, color: Colors.blue.shade700),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _buildResolutionInfoLabel(info),
            const Spacer(),
            doneLabel,
            const SizedBox(width: 8),
            downloadBtn,
          ],
        ),
    };
  }

  /// 构建视频信息标签：分辨率 | 尺寸 | 文件大小
  Widget _buildResolutionInfoLabel(VideoInfo info) {
    final parts = <String>[];

    // 分辨率
    if (info.resolutionLabel != null) {
      parts.add(info.resolutionLabel!);
    }

    // 尺寸（文件大小）
    if (_fileSizeBytes != null) {
      final mb = _fileSizeBytes! / (1024 * 1024);
      final sizeLabel = mb >= 1
          ? '${mb.toStringAsFixed(1)} MB'
          : '${(_fileSizeBytes! / 1024).toStringAsFixed(0)} KB';
      parts.add(sizeLabel);
    } else if (_fetchingSize) {
      parts.add('...');
    }

    final text = parts.join(' | ');
    if (text.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline, size: 12, color: Colors.grey.shade600),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsNarrow(VideoInfo info) {
    // 根据媒体类型确定按钮文字
    final downloadLabel = switch (info.mediaType) {
      MediaType.image => '下载图片',
      MediaType.livePhoto => '下载动图',
      MediaType.video => '下载视频',
    };

    final downloadBtn = FilledButton.icon(
      onPressed: _downloading ? null : _download,
      icon: _downloading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.download, size: 18),
      label: Text(_downloading ? '下载中…' : downloadLabel),
    );

    return switch (info.mediaType) {
      MediaType.image => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  '图文作品  ${info.imageUrls.length} 张图片',
                  style: const TextStyle(fontSize: 13),
                ),
                if (_downloadProgress == 1.0) ...const [
                  Spacer(),
                  Icon(Icons.check_circle, color: Colors.green, size: 18),
                  SizedBox(width: 4),
                  Text(
                    '下载完成',
                    style: TextStyle(color: Colors.green, fontSize: 13),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _downloading ? null : _download,
                    icon: _downloading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.download, size: 18),
                    label: Text(_downloading ? '下载中…' : '下载图片'),
                  ),
                ),
                if (info.musicUrl != null) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _downloadingMusic ? null : _downloadMusicOnly,
                    icon: _downloadingMusic
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.deepPurple,
                            ),
                          )
                        : const Icon(Icons.music_note, size: 16),
                    label: Text(_downloadingMusic ? '…' : '音乐'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.deepPurple,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      MediaType.livePhoto => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  '实况图  ${info.livePhotoUrls.length} 个',
                  style: const TextStyle(fontSize: 13),
                ),
                if (_downloadProgress == 1.0) ...const [
                  Spacer(),
                  Icon(Icons.check_circle, color: Colors.green, size: 18),
                  SizedBox(width: 4),
                  Text(
                    '下载完成',
                    style: TextStyle(color: Colors.green, fontSize: 13),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            downloadBtn,
          ],
        ),
      MediaType.video => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.videocam, size: 12, color: Colors.blue.shade700),
                      const SizedBox(width: 4),
                      Text(
                        '视频',
                        style: TextStyle(fontSize: 11, color: Colors.blue.shade700),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _buildResolutionInfoLabel(info),
                if (_downloadProgress == 1.0) ...const [
                  Spacer(),
                  Icon(Icons.check_circle, color: Colors.green, size: 18),
                  SizedBox(width: 4),
                  Text('下载完成', style: TextStyle(color: Colors.green, fontSize: 13)),
                ],
              ],
            ),
            const SizedBox(height: 8),
            downloadBtn,
          ],
        ),
    };
  }

  // ── 下载目录行 ───────────────────────────────────────────────

  Widget _buildDirectoryRow() {
    final isAndroid = Platform.isAndroid;
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isAndroid
                    ? Icons.folder_special_outlined
                    : Icons.folder_outlined,
                size: 22,
                color: Colors.grey,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _settings.downloadDir.isEmpty
                      ? '（未设置下载目录）'
                      : _settings.downloadDir,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!isAndroid) ...[
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: _pickDirectory,
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('更改', style: TextStyle(fontSize: 14)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                  ),
                ),
                if (_settings.downloadDir.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  OutlinedButton.icon(
                    onPressed: () {
                      if (Platform.isWindows) {
                        Process.run('explorer', [_settings.downloadDir]);
                      }
                    },
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('打开', style: TextStyle(fontSize: 14)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
          // Android：快捷目录选择按钮（Movies / Downloads / App私有）
          if (isAndroid)
            FutureBuilder<List<AndroidQuickDir>>(
              future: SettingsService.androidQuickDirs(),
              builder: (context, snap) {
                if (!snap.hasData) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 6,
                    children: snap.data!.map((d) {
                      final selected = _settings.downloadDir == d.path;
                      return ChoiceChip(
                        label: Text(
                          d.label,
                          style: const TextStyle(fontSize: 12),
                        ),
                        selected: selected,
                        onSelected: (_) async {
                          await _settings.setDownloadDir(d.path);
                          _log.info('下载目录切换为：${d.path}');
                        },
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ── 日志面板 ──────────────────────────────────────────────────

  Widget _buildLogPanel() {
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 430;

          final actionStyle = TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            minimumSize: const Size(56, 34),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          );

          final actions = [
            TextButton.icon(
              onPressed: _openLogSettingsPanel,
              icon: const Icon(Icons.tune, size: 17),
              label: Text(
                '设置',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
              ),
              style: actionStyle,
            ),
            TextButton.icon(
              onPressed: _copyLogContent,
              icon: const Icon(Icons.content_copy, size: 17),
              label: Text(
                '复制日志',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
              ),
              style: actionStyle,
            ),
            TextButton.icon(
              onPressed: () => setState(() => _log.entries.clear()),
              icon: const Icon(Icons.delete_outline, size: 17),
              label: Text(
                '清空',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
              ),
              style: actionStyle,
            ),
          ];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 标题栏
              if (narrow)
                Wrap(
                  runSpacing: 4,
                  spacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.terminal, size: 15, color: Colors.grey),
                        SizedBox(width: 4),
                        Text(
                          '日志',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                    ...actions,
                  ],
                )
              else
                Row(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.terminal, size: 15, color: Colors.grey),
                        SizedBox(width: 4),
                        Text(
                          '日志',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                    const Spacer(),
                    ...actions,
                  ],
                ),
              const Divider(height: 4),
              // 日志列表占满剩余空间
              Expanded(child: _buildLogListView()),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLogListView() {
    return ListenableBuilder(
      listenable: _log,
      builder: (context, _) {
        // 自动滚动到底部
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_logScrollCtrl.hasClients) {
            _logScrollCtrl.animateTo(
              _logScrollCtrl.position.maxScrollExtent,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
            );
          }
        });

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.all(8),
          child: SelectionArea(
            child: ListView.builder(
              controller: _logScrollCtrl,
              itemCount: _log.entries.length,
              itemBuilder: (_, i) {
                final e = _log.entries[i];
                return Text(
                  e.toString(),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: Platform.isAndroid ? 10 : 11,
                    height: 1.4,
                    color: switch (e.level) {
                      LogLevel.error => const Color(0xFFFF6B6B),
                      LogLevel.warn => const Color(0xFFFFD93D),
                      LogLevel.info => const Color(0xFFB0BEC5),
                    },
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _logScrollCtrl.dispose();
    _thumbScrollCtrl.dispose();
    super.dispose();
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

  /// 清理文件名（简化版）
  String _sanitizeFilename(String name, {int maxLen = 20}) {
    var result = name.replaceAll(
      RegExp(
        r'[^\u4e00-\u9fff'
        r'\u3400-\u4dbf'
        r'\u3000-\u303f'
        r'\uff01-\uffe6'
        r'a-zA-Z0-9'
        r' .,_\-!?()'
        r']',
      ),
      '',
    );
    result = result.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (result.length > maxLen) result = result.substring(0, maxLen).trim();
    return result.isEmpty ? 'file' : result;
  }
}

// ─── 辅助组件 ───────────────────────────────────────────────
