import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/douyin_parser.dart';
import '../services/downloader/desktop_downloader.dart';
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
      _log.warn('未找到链接：$input');
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
      });
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
      final downloader = DesktopDownloader();
      final path = await downloader.downloadVideo(
        info,
        quality: _selectedQuality,
        directory: _settings.downloadDir,
      );
      _log.info('下载完成：$path');
      setState(() => _downloadProgress = 1.0);
    } catch (e) {
      _log.error('下载失败：$e');
      setState(() => _downloadProgress = null);
    } finally {
      setState(() => _downloading = false);
    }
  }

  // ─── 选择目录 ────────────────────────────────────────────────

  Future<void> _pickDirectory() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择下载目录',
      initialDirectory: _settings.downloadDir,
    );
    if (result != null) {
      await _settings.setDownloadDir(result);
      _log.info('下载目录已更改为：$result');
    }
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
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'ID: ${info.videoId}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            // 质量选择 + 下载按钮
            Row(
              children: [
                const Text('清晰度：', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 6),
                _QualityDropdown(
                  qualities: qualities,
                  value: _selectedQuality,
                  onChanged: (q) => setState(() => _selectedQuality = q),
                ),
                const Spacer(),
                if (_downloadProgress == 1.0)
                  const Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 18),
                      SizedBox(width: 4),
                      Text(
                        '下载完成',
                        style: TextStyle(color: Colors.green, fontSize: 13),
                      ),
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
            ),
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
  }

  // ── 下载目录行 ───────────────────────────────────────────────

  Widget _buildDirectoryRow() {
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) => Row(
        children: [
          const Icon(Icons.folder_outlined, size: 22, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _settings.downloadDir.isEmpty
                  ? '（未设置下载目录）'
                  : _settings.downloadDir,
              style: const TextStyle(fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: _pickDirectory,
            icon: const Icon(Icons.folder_open, size: 18),
            label: const Text('更改', style: TextStyle(fontSize: 14)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
