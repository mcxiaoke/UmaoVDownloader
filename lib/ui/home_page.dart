import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/douyin_parser.dart';
import '../services/downloader/base_downloader.dart';
import '../services/downloader/desktop_downloader.dart';
import '../services/downloader/mobile_downloader.dart';
import '../services/log_service.dart';
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

  // 解析状态
  bool _parsing = false;
  VideoInfo? _videoInfo;
  VideoQuality _selectedQuality = VideoQuality.p1080;

  // 文件大小预获取
  int? _fileSizeBytes; // null = 未知/加载中
  bool _fetchingSize = false;

  // 下载状态
  bool _downloading = false;
  double? _downloadProgress; // null = 不显示，0.0–1.0

  LogService get _log => widget.log;
  SettingsService get _settings => widget.settings;

  // ─── 解析 ────────────────────────────────────────────────────

  Future<void> _parse() async {
    final input = _inputCtrl.text.trim();
    if (input.isEmpty) return;

    final url = UrlExtractor.extractFirst(input);
    if (url == null) {
      _log.warn('无效输入，未找到抖音链接');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('未找到有效的抖音链接，请粘贴分享文本或链接'),
            duration: Duration(seconds: 3),
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

    try {
      final parser = DouyinParser();
      final info = await parser.parse(url);
      parser.dispose();

      setState(() {
        _videoInfo = info;
        // 默认选最高清晰度
        _selectedQuality = info.availableQualities.first;
        _fileSizeBytes = null;
      });
      _fetchFileSize(info, info.availableQualities.first);
      _log.info('解析成功：${info.title}');
      _log.info('videoId=${info.videoId}  fileId=${info.videoFileId}');
      _log.info(
        '可用清晰度：${info.availableQualities.map((q) => q.ratio).join(' / ')}',
      );
      // resolution/bitrate from play_addr reflects mobile stream size, skip for now
      // 输出各清晰度的实际下载地址
      for (final q in info.availableQualities) {
        _log.info('  ${q.ratio}: ${info.qualityUrls[q]}');
      }
    } catch (e) {
      _log.error('解析失败：$e');
    } finally {
      setState(() => _parsing = false);
    }
  }

  // ─── 文件大小预获取 ────────────────────────────────────────────

  Future<void> _fetchFileSize(VideoInfo info, VideoQuality quality) async {
    if (_fetchingSize) return;
    setState(() {
      _fileSizeBytes = null;
      _fetchingSize = true;
    });
    try {
      final downloadUrl = info.urlFor(quality);
      // 跟随一次 302 重定向后发 HEAD 请求
      final ioClient = HttpClient();
      String resolvedUrl = downloadUrl;
      try {
        final req = await ioClient.getUrl(Uri.parse(downloadUrl));
        req.headers.set(HttpHeaders.userAgentHeader, kUaEdge);
        req.followRedirects = false;
        final resp = await req.close();
        await resp.drain<void>();
        if (resp.statusCode >= 300 && resp.statusCode < 400) {
          resolvedUrl =
              resp.headers.value(HttpHeaders.locationHeader) ?? downloadUrl;
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
      if (mounted) setState(() => _fileSizeBytes = size);
    } catch (_) {
      // 获取失败不影响使用，保持 null
    } finally {
      if (mounted) setState(() => _fetchingSize = false);
    }
  }

  // ─── 下载 ────────────────────────────────────────────────────

  Future<void> _download() async {
    final info = _videoInfo;
    if (info == null || _downloading) return;

    setState(() {
      _downloading = true;
      _downloadProgress = 0;
    });
    _log.info('开始下载 [${_selectedQuality.ratio}]：${info.title}');

    try {
      final downloader = (Platform.isAndroid || Platform.isIOS)
          ? MobileDownloader()
          : DesktopDownloader();
      final path = await downloader.downloadVideo(
        info,
        quality: _selectedQuality,
        directory: _settings.downloadDir,
        onProgress: (received, total) {
          if (!mounted) return;
          final t = total ?? _fileSizeBytes;
          if (t != null && t > 0) {
            setState(() => _downloadProgress = received / t);
          }
        },
        onLog: (msg) => _log.info('[DL] $msg'),
      );
      _log.info('下载完成：$path');
      setState(() {
        _downloadProgress = 1.0;
        _videoInfo = null;
      });
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
    return Scaffold(
      appBar: AppBar(title: const Text('DViewer - 抖音视频下载')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildInputRow(),
            const SizedBox(height: 12),
            _buildResultCard(),
            const SizedBox(height: 12),
            _buildDirectoryRow(),
            const SizedBox(height: 8),
            Expanded(child: _buildLogPanel()),
          ],
        ),
      ),
    );
  }

  // ── 输入区 ───────────────────────────────────────────────────

  Widget _buildInputRow() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _inputCtrl,
            decoration: const InputDecoration(
              hintText: '粘贴抖音分享文本或链接…',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
            ),
            maxLines: 1,
            onSubmitted: (_) => _parse(),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
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
        ),
      ],
    );
  }

  // ── 解析结果卡片 ──────────────────────────────────────────────

  Widget _buildResultCard() {
    if (_videoInfo == null && !_parsing) {
      return Container(
        height: 80,
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
        height: 80,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final info = _videoInfo!;
    final qualities = info.availableQualities;

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 400;
        return Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题（可复制）
                SelectableText(
                  info.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'ID: ${info.videoId}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 12),
                // 质量选择 + 下载按钮：屏幕宽则并排，流则堆叠
                if (narrow)
                  _buildActionsNarrow(info, qualities)
                else
                  _buildActionsWide(info, qualities),
                // 进度条
                if (_downloading ||
                    (_downloadProgress != null && _downloadProgress! < 1.0))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(value: _downloadProgress),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionsWide(VideoInfo info, List<VideoQuality> qualities) {
    return Row(
      children: [
        const Text('清晰度：', style: TextStyle(fontSize: 13)),
        const SizedBox(width: 6),
        _QualityDropdown(
          qualities: qualities,
          value: _selectedQuality,
          onChanged: (q) {
            setState(() {
              _selectedQuality = q;
              _fileSizeBytes = null;
            });
            _fetchFileSize(info, q);
          },
        ),
        const SizedBox(width: 8),
        _FileSizeLabel(bytes: _fileSizeBytes, loading: _fetchingSize),
        const Spacer(),
        if (_downloadProgress == 1.0)
          const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 18),
              SizedBox(width: 4),
              Text('下载完成', style: TextStyle(color: Colors.green, fontSize: 13)),
            ],
          ),
        const SizedBox(width: 8),
        FilledButton.icon(
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
          label: Text(_downloading ? '下载中…' : '下载'),
        ),
      ],
    );
  }

  Widget _buildActionsNarrow(VideoInfo info, List<VideoQuality> qualities) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text('清晰度：', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 6),
            _QualityDropdown(
              qualities: qualities,
              value: _selectedQuality,
              onChanged: (q) {
                setState(() {
                  _selectedQuality = q;
                  _fileSizeBytes = null;
                });
                _fetchFileSize(info, q);
              },
            ),
            const SizedBox(width: 6),
            _FileSizeLabel(bytes: _fileSizeBytes, loading: _fetchingSize),
            if (_downloadProgress == 1.0) ...const [
              Spacer(),
              Icon(Icons.check_circle, color: Colors.green, size: 18),
              SizedBox(width: 4),
              Text('下载完成', style: TextStyle(color: Colors.green, fontSize: 13)),
            ],
          ],
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
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
          label: Text(_downloading ? '下载中…' : '下载'),
        ),
      ],
    );
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 标题栏
        Row(
          children: [
            const Icon(Icons.terminal, size: 15, color: Colors.grey),
            const SizedBox(width: 4),
            const Text(
              '日志',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const Spacer(),
            if (_log.logFilePath != null)
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _log.logFilePath!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('日志路径已复制'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Icons.copy, size: 15),
                label: Text(
                  '复制日志路径',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            TextButton.icon(
              onPressed: () => setState(() => _log.entries.clear()),
              icon: const Icon(Icons.delete_outline, size: 15),
              label: Text(
                '清空',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        const Divider(height: 4),
        Expanded(
          child: ListenableBuilder(
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
                          fontSize: 11,
                          height: 1.5,
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
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _logScrollCtrl.dispose();
    super.dispose();
  }
}

// ─── 清晰度下拉组件 ───────────────────────────────────────────────

/// 文件大小标签：加载中显示小转圈，加载完显示 xx.xx MB，失败不显示
class _FileSizeLabel extends StatelessWidget {
  final int? bytes;
  final bool loading;

  const _FileSizeLabel({required this.bytes, required this.loading});

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(strokeWidth: 1.5),
      );
    }
    if (bytes == null) return const SizedBox.shrink();
    final mb = bytes! / (1024 * 1024);
    final label = mb >= 1
        ? '${mb.toStringAsFixed(2)} MB'
        : '${(bytes! / 1024).toStringAsFixed(1)} KB';
    return Text(
      label,
      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
    );
  }
}

class _QualityDropdown extends StatelessWidget {
  final List<VideoQuality> qualities;
  final VideoQuality value;
  final ValueChanged<VideoQuality> onChanged;

  const _QualityDropdown({
    required this.qualities,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButton<VideoQuality>(
      value: qualities.contains(value) ? value : qualities.first,
      isDense: true,
      underline: const SizedBox(),
      items: qualities
          .map((q) => DropdownMenuItem(value: q, child: Text(q.ratio)))
          .toList(),
      onChanged: (q) {
        if (q != null) onChanged(q);
      },
    );
  }
}
