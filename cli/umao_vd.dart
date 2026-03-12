/// umao_vd — 抖音链接解析 & 下载 CLI 工具
///
/// 用法：
///   dart run cli/umao_vd.dart <URL>                    # 只解析，打印信息
///   dart run cli/umao_vd.dart -d <URL>                 # 解析 + 下载（最高清晰度）
///   dart run cli/umao_vd.dart -d -o <目录> <URL>       # 下载到指定目录
///   dart run cli/umao_vd.dart -j <URL>                 # 只输出 JSON 解析结果
///
/// 选项：
///   -d, --download          解析后立即下载
///   -o, --output <目录>     下载目录（默认：当前目录）
///   -j, --json              以 JSON 格式输出解析结果（与 -d 互斥）
///   -h, --help              显示本帮助
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:umao_vdownloader/services/douyin_parser.dart';
import 'package:umao_vdownloader/services/downloader/base_downloader.dart';
import 'package:umao_vdownloader/services/url_extractor.dart';

// ── 内联下载器（以当前目录为默认，UA 与桌面端一致）─────────────────────────
class _CliDownloader extends BaseDownloader {
  _CliDownloader(this._outputDir);

  final String _outputDir;

  @override
  List<String> get downloadUserAgents => const [
    kUaIosDouyin,
    kUaEdge,
    kUaIosWechat,
  ];

  @override
  Future<String> getDefaultDirectory() async => _outputDir;
}

// ── 帮助文本 ──────────────────────────────────────────────────────────────────
void _printHelp() {
  stdout.writeln('''
用法: dart run cli/umao_vd.dart [选项] <抖音链接或分享文本>

选项:
  -d, --download          解析后自动下载（最高可用清晰度）
  -o, --output <目录>     下载保存目录（默认：当前目录，仅与 -d 配合使用）
  -j, --json              仅输出 JSON 解析结果，不下载
  -h, --help              显示此帮助

示例:
  dart run cli/umao_vd.dart https://v.douyin.com/jjA4YdaFphk/
  dart run cli/umao_vd.dart -d https://v.douyin.com/jjA4YdaFphk/
  dart run cli/umao_vd.dart -d -o D:/Downloads https://v.douyin.com/jjA4YdaFphk/
  dart run cli/umao_vd.dart -j https://v.douyin.com/hA9hAH4gYdc/
''');
}

// ── JSON 序列化 ───────────────────────────────────────────────────────────────
Map<String, dynamic> _toJson(VideoInfo info) {
  return {
    'type': info.isImagePost ? 'image' : 'video',
    'id': info.videoId,
    'shareId': info.shareId,
    'title': info.title,
    if (!info.isImagePost) ...{
      'qualities': info.availableQualities.map((q) => q.ratio).toList(),
      'coverUrl': info.coverUrl,
      if (info.width != null) 'width': info.width,
      if (info.height != null) 'height': info.height,
      if (info.bitrateKbps != null) 'bitrateKbps': info.bitrateKbps,
    },
    if (info.isImagePost) ...{
      'imageCount': info.imageUrls.length,
      'imageUrls': info.imageUrls,
      if (info.musicUrl != null) 'musicUrl': info.musicUrl,
      if (info.musicTitle != null) 'musicTitle': info.musicTitle,
    },
  };
}

// ── 纯文本解析结果打印 ────────────────────────────────────────────────────────
void _printInfo(VideoInfo info) {
  stdout.writeln('');
  stdout.writeln('标题    : ${info.title}');
  stdout.writeln('ID      : ${info.videoId}');
  if (info.shareId != null) stdout.writeln('短链 ID : ${info.shareId}');

  if (info.isImagePost) {
    stdout.writeln('类型    : 图文作品');
    stdout.writeln('图片数  : ${info.imageUrls.length} 张');
    for (var i = 0; i < info.imageUrls.length; i++) {
      final url = info.imageUrls[i];
      final preview = url.length > 80 ? '${url.substring(0, 80)}…' : url;
      stdout.writeln('  图片${(i + 1).toString().padLeft(2, '0')}: $preview');
    }
    if (info.musicTitle != null) stdout.writeln('背景音乐: ${info.musicTitle}');
  } else {
    stdout.writeln('类型    : 视频作品');
    stdout.writeln(
      '清晰度  : ${info.availableQualities.map((q) => q.ratio).join(' / ')}',
    );
    if (info.resolutionLabel != null)
      stdout.writeln('分辨率  : ${info.resolutionLabel}');
    if (info.bitrateKbps != null)
      stdout.writeln('码率    : ${info.bitrateKbps} kbps');
  }
  stdout.writeln('');
}

// ── 进度条 ────────────────────────────────────────────────────────────────────
void _onProgress(int received, int? total) {
  if (total == null || total == 0) return;
  final pct = (received / total * 100).clamp(0, 100).toStringAsFixed(1);
  final recMb = (received / 1024 / 1024).toStringAsFixed(2);
  final totMb = (total / 1024 / 1024).toStringAsFixed(2);
  stdout.write('\r  下载中: $recMb / $totMb MB ($pct%)   ');
}

// ── 入口 ──────────────────────────────────────────────────────────────────────
Future<void> main(List<String> args) async {
  bool download = false;
  bool jsonMode = false;
  String outputDir = Directory.current.path;
  final positional = <String>[];

  // 简单手写参数解析（避免引入外部 args 包）
  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '-h' || '--help':
        _printHelp();
        exit(0);
      case '-d' || '--download':
        download = true;
      case '-j' || '--json':
        jsonMode = true;
      case '-o' || '--output':
        if (i + 1 >= args.length) {
          stderr.writeln('错误: -o/--output 需要指定目录路径');
          exit(1);
        }
        outputDir = args[++i];
      default:
        if (args[i].startsWith('-')) {
          stderr.writeln('未知选项: ${args[i]}（使用 -h 查看帮助）');
          exit(1);
        }
        positional.add(args[i]);
    }
  }

  if (jsonMode && download) {
    stderr.writeln('错误: -j/--json 与 -d/--download 不能同时使用');
    exit(1);
  }

  // 获取输入（命令行参数或 stdin）
  final String input;
  if (positional.isNotEmpty) {
    input = positional.join(' ');
  } else {
    stdout.write('请输入抖音分享内容或链接: ');
    input = stdin.readLineSync() ?? '';
  }

  if (input.trim().isEmpty) {
    stderr.writeln('错误: 未提供输入');
    exit(1);
  }

  final url = UrlExtractor.extractFirst(input);
  if (url == null) {
    stderr.writeln('错误: 未找到有效的 HTTP/HTTPS 链接');
    exit(1);
  }

  if (!jsonMode) stdout.writeln('链接: $url');

  // 解析
  if (!jsonMode) stdout.write('正在解析…');
  final VideoInfo info;
  try {
    info = await DouyinParser().parse(url);
    if (!jsonMode) stdout.writeln(' 完成');
  } on DouyinParseException catch (e) {
    stderr.writeln('解析失败: ${e.message}');
    exit(1);
  } catch (e) {
    stderr.writeln('解析失败: $e');
    exit(1);
  }

  // JSON 模式：只输出 JSON，退出
  if (jsonMode) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(_toJson(info)));
    exit(0);
  }

  // 普通解析模式：打印信息
  _printInfo(info);

  if (!download) exit(0);

  // 下载模式
  final dir = Directory(outputDir);
  if (!dir.existsSync()) {
    stdout.writeln('创建目录: $outputDir');
    dir.createSync(recursive: true);
  }

  final downloader = _CliDownloader(outputDir);

  try {
    if (info.isImagePost) {
      stdout.writeln('开始下载图文（${info.imageUrls.length} 张）…');
    } else {
      final best = info.availableQualities.first;
      stdout.writeln('开始下载视频（${best.ratio}）… → $outputDir');
    }

    final savedPath = await downloader.downloadVideo(
      info,
      onProgress: _onProgress,
      onLog: (msg) => stdout.writeln('\n  $msg'),
    );

    stdout.writeln('');
    stdout.writeln('已保存: $savedPath');
  } on http.ClientException catch (e) {
    stderr.writeln('\n下载失败（网络错误）: $e');
    exit(1);
  } catch (e) {
    stderr.writeln('\n下载失败: $e');
    exit(1);
  }
  exit(0);
}
