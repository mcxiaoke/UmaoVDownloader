/// CLI 测试入口
///
/// 模式 1 - 默认：解析 + 下载
///   dart run tool/cli_test.dart <抖音分享文本或链接>
///   dart run tool/cli_test.dart          # 交互式输入
///
/// 模式 2 - UA 清晰度对比（--ua-test）：
///   dart run tool/cli_test.dart --ua-test <抖音分享文本或链接>
///   对同一视频用 4 种 UA 各发一次 HEAD 请求，对比 Content-Length（文件大小）
library;

import 'dart:io';

import 'package:umao_vdownloader/services/douyin_parser.dart';
import 'package:umao_vdownloader/services/downloader/base_downloader.dart';
import 'package:umao_vdownloader/services/downloader/desktop_downloader.dart';
import 'package:umao_vdownloader/services/url_extractor.dart';
import 'package:http/http.dart' as http;

// ── UA 列表（用于对比测试）────────────────────────────────────
const _testUAs = [
  (label: '桌面 Edge 145', ua: kUaEdge),
  (label: 'iOS 微信 8.0.69', ua: kUaIosWechat),
  (label: '抖音 App 36.7', ua: kUaIosDouyin),
];

Future<void> main(List<String> args) async {
  // ── 解析 --ua-test 开关 ───────────────────────────────────────
  final uaTestMode = args.contains('--ua-test');
  final restArgs = args.where((a) => a != '--ua-test').toList();

  // ── 1. 获取输入 ───────────────────────────────────────────────
  String input;
  if (restArgs.isNotEmpty) {
    input = restArgs.join(' ');
  } else {
    stdout.write('请输入抖音分享内容或链接: ');
    input = stdin.readLineSync() ?? '';
  }

  if (input.trim().isEmpty) {
    stderr.writeln('错误: 输入不能为空');
    exit(1);
  }

  // ── 2. 提取链接 ───────────────────────────────────────────────
  final url = UrlExtractor.extractFirst(input);
  if (url == null) {
    stderr.writeln('错误: 未找到有效的 HTTP/HTTPS 链接');
    exit(1);
  }
  print('提取链接: $url');

  // ── 3. 解析视频信息 ───────────────────────────────────────────
  final parser = DouyinParser();
  VideoInfo? info;
  try {
    print('正在解析视频信息...');
    info = await parser.parse(url);
  } on DouyinParseException catch (e) {
    stderr.writeln('解析失败: $e');
    exit(1);
  } catch (e) {
    stderr.writeln('未知错误: $e');
    exit(1);
  } finally {
    parser.dispose();
  }

  _printSeparator();
  print('视频ID   : ${info.videoId}');
  print('标题     : ${info.title}');
  print('fileId   : ${info.videoFileId}');
  print('封面地址 : ${info.coverUrl ?? "无"}');
  print('可用清晰度: ${info.availableQualities.map((q) => q.ratio).join(", ")}');
  if (info.imageUrls.isNotEmpty) {
    print('图片数量 : ${info.imageUrls.length} 张');
    for (var i = 0; i < info.imageUrls.length; i++) {
      print('  图片${i + 1}: ${info.imageUrls[i].substring(0, 80)}...');
    }
  }
  _printSeparator();

  // ── 模式 2：UA 清晰度对比 ──────────────────────────────────────
  if (uaTestMode) {
    await _runUaTest(info);
    return;
  }

  // ── 模式 1：正常下载流程 ───────────────────────────────────────
  stdout.write('是否下载视频？[y/N] ');
  final answer = stdin.readLineSync()?.trim().toLowerCase() ?? '';
  if (answer != 'y' && answer != 'yes') {
    print('已取消下载');
    return;
  }

  // ── 5. 选择清晰度 ─────────────────────────────────────────────
  final qualities = info.availableQualities;
  VideoQuality selectedQuality;
  if (qualities.length == 1) {
    selectedQuality = qualities.first;
    print('清晰度: ${selectedQuality.ratio}');
  } else {
    print('\n可用清晰度:');
    for (var i = 0; i < qualities.length; i++) {
      final q = qualities[i];
      final marker = i == 0 ? ' (默认最高)' : '';
      print('  ${i + 1}. ${q.ratio}$marker');
    }
    stdout.write('请选择 [1-${qualities.length}，回车默认最高]: ');
    final choice = stdin.readLineSync()?.trim() ?? '';
    final idx = int.tryParse(choice);
    if (idx == null || idx < 1 || idx > qualities.length) {
      selectedQuality = qualities.first;
    } else {
      selectedQuality = qualities[idx - 1];
    }
    print('已选择: ${selectedQuality.ratio}');
  }

  // ── 6. 执行下载 ───────────────────────────────────────────────
  final downloader = DesktopDownloader();
  final defaultDir = await downloader.getDefaultDirectory();
  print('保存目录: $defaultDir');
  print('正在下载...');

  try {
    final savePath = await downloader.downloadVideo(
      info,
      quality: selectedQuality,
    );
    print('下载完成: $savePath');
  } catch (e) {
    stderr.writeln('下载失败: $e');
    exit(1);
  }
}

/// 用各 UA 对所有清晰度 ratio 发 HEAD 请求，对比 Content-Length
/// 注意：直接用 videoFileId 构造各 ratio URL，而非 urlFor() fallback
Future<void> _runUaTest(VideoInfo info) async {
  final qualities = [VideoQuality.p720, VideoQuality.p1080, VideoQuality.p2160];
  const playBase = 'https://aweme.snssdk.com/aweme/v1/play/';
  print('UA 清晰度对比测试（共 ${_testUAs.length} 个 UA × ${qualities.length} 个清晰度）');
  print('方法：HEAD 请求取 Content-Length，请求间隔 3s 避免限流\n');

  final uaLabels = _testUAs.map((u) => u.label).toList();
  const colW = 24;
  const qColW = 8;
  stdout.write('清晰度  '.padRight(qColW));
  for (final label in uaLabels) {
    stdout.write(label.padRight(colW));
  }
  print('');
  _printSeparator();

  final client = http.Client();
  try {
    for (final quality in qualities) {
      // 直接构造该 ratio 的真实 URL
      final downloadUrl =
          '$playBase?video_id=${info.videoFileId}&ratio=${quality.ratio}&line=0';
      stdout.write(quality.ratio.padRight(qColW));

      for (final entry in _testUAs) {
        final result = await _headRequest(client, downloadUrl, entry.ua);
        String label;
        if (result == null) {
          label = '(失败)';
        } else if (result.size != null && result.size! > 10240) {
          label = _formatBytes(result.size!);
        } else {
          // 文件很小说明是错误页，显示状态码
          label =
              'HTTP ${result.status} (${result.size != null ? _formatBytes(result.size!) : "?"})';
        }
        stdout.write(label.padRight(colW));
        // 每次请求后等待，避免 CDN 限流
        await Future.delayed(const Duration(milliseconds: 3000));
      }
      print('');
    }
  } finally {
    client.close();
  }

  _printSeparator();
  print('说明: 同 UA 不同 ratio 若大小相同，说明 CDN 只有一条码流。');
}

typedef _HeadResult = ({int status, int? size});

/// 发送 HEAD 请求，返回状态码和 Content-Length；彻底失败返回 null
Future<_HeadResult?> _headRequest(
  http.Client client,
  String url,
  String ua,
) async {
  try {
    // 跟随一次 302 重定向
    final ioClient = HttpClient();
    String finalUrl = url;
    try {
      final req = await ioClient.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader, ua);
      req.followRedirects = false;
      final resp = await req.close();
      await resp.drain<void>();
      if (resp.statusCode >= 300 && resp.statusCode < 400) {
        finalUrl = resp.headers.value(HttpHeaders.locationHeader) ?? url;
      }
    } finally {
      ioClient.close();
    }

    final request = http.Request('HEAD', Uri.parse(finalUrl));
    request.headers[HttpHeaders.userAgentHeader] = ua;
    final resp = await client.send(request);
    final cl = resp.headers['content-length'];
    return (
      status: resp.statusCode,
      size: cl != null ? int.tryParse(cl) : null,
    );
  } catch (_) {
    return null;
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}

void _printSeparator() => print('─' * 50);
