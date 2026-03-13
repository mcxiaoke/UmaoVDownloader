/// 批量测试脚本 — 读取 test/urls.txt，逐条解析并打印摘要
///
/// 用法：
///   dart run tool/run_tests.dart
///
/// 功能：
///   • 对每条 URL 调用 DouyinParser 解析
///   • 将分享页 HTML 保存到 test/cache/<shortId>.html，供手动分析
///   • 控制台输出对齐摘要表格，含 PASS / FAIL 标记
library;

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:umao_vdownloader/services/douyin_parser.dart';

// ── HTML 拦截 Client ──────────────────────────────────────────────────────────
/// 包装 http.Client，将每次 GET 响应 body 写入 [cacheDir]/<host+path>.html
class _CachingClient extends http.BaseClient {
  _CachingClient(this._inner, this._cacheDir, this._shortId);

  final http.Client _inner;
  final Directory _cacheDir;
  final String _shortId;

  // 最近一次 GET 请求的保存路径（供外部读取日志用）
  String? lastSavedPath;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request);

  @override
  Future<http.Response> get(Uri url, {Map<String, String>? headers}) async {
    final resp = await _inner.get(url, headers: headers);
    if (resp.statusCode == 200) {
      // 用 shortId + URL path 作文件名，方便对照 urls.txt
      final seg = url.pathSegments.where((s) => s.isNotEmpty).join('_');
      final name = '${_shortId}_$seg.html';
      final file = File('${_cacheDir.path}${Platform.pathSeparator}$name');
      await file.writeAsString(resp.body);
      lastSavedPath = file.path;
    }
    return resp;
  }
}

// ── 解析一条 URL ─────────────────────────────────────────────────────────────
Future<_Result> _testOne(String url, Directory cacheDir) async {
  final shortId =
      RegExp(r'v\.douyin\.com/([A-Za-z0-9_-]+)').firstMatch(url)?.group(1) ??
      RegExp(r'/(?:video|note|slides)/(\d+)').firstMatch(url)?.group(1) ??
      'unknown';
  final inner = http.Client();
  final caching = _CachingClient(inner, cacheDir, shortId);
  final parser = DouyinParser(httpClient: caching);

  try {
    final info = await parser.parse(url);
    return _Result(
      shortId: shortId,
      ok: true,
      title: info.title,
      isImage: info.imageUrls.isNotEmpty,
      imageCount: info.imageUrls.length,
      quality: info.availableQualities.map((q) => q.ratio).join('/'),
      htmlPath: caching.lastSavedPath,
    );
  } catch (e) {
    return _Result(
      shortId: shortId,
      ok: false,
      error: e.toString(),
      htmlPath: caching.lastSavedPath,
    );
  } finally {
    parser.dispose();
  }
}

// ── 数据类 ───────────────────────────────────────────────────────────────────
class _Result {
  _Result({
    required this.shortId,
    required this.ok,
    this.title,
    this.isImage = false,
    this.imageCount = 0,
    this.quality = '',
    this.error,
    this.htmlPath,
  });

  final String shortId;
  final bool ok;
  final String? title;
  final bool isImage;
  final int imageCount;
  final String quality;
  final String? error;
  final String? htmlPath;
}

// ── 主入口 ───────────────────────────────────────────────────────────────────
Future<void> main() async {
  final urlsFile = File('test/urls.txt');
  if (!urlsFile.existsSync()) {
    print('找不到 test/urls.txt');
    exit(1);
  }

  // 解析 urls.txt，跳过空行和纯注释行
  final entries = <({String url, String label})>[];
  for (final line in urlsFile.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

    // 兼容两种格式：
    // 1) <url> # label
    // 2) <url> label（遗漏 # 也能继续测试）
    final urlMatch = RegExp(r'https?://\S+').firstMatch(trimmed);
    if (urlMatch == null) continue;
    final url = urlMatch.group(0)!;

    String label = '';
    if (trimmed.contains('#')) {
      final parts = trimmed.split('#');
      label = parts.length > 1 ? parts.sublist(1).join('#').trim() : '';
    } else {
      label = trimmed.substring(urlMatch.end).trim();
    }

    if (url.isNotEmpty) entries.add((url: url, label: label));
  }

  if (entries.isEmpty) {
    print('test/urls.txt 中没有有效 URL');
    exit(1);
  }

  // 确保 cache 目录存在
  final cacheDir = Directory('test${Platform.pathSeparator}cache');
  await cacheDir.create(recursive: true);

  print('共 ${entries.length} 条 URL，开始测试…\n');

  const delayMs = 6000;
  final results = <(String label, _Result result)>[];
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    if (i > 0) {
      await Future<void>.delayed(const Duration(milliseconds: delayMs));
    }
    stdout.write('  测试 ${e.label.padRight(20)} ${e.url} … ');
    final r = await _testOne(e.url, cacheDir);
    stdout.writeln(r.ok ? 'OK' : 'FAIL');
    results.add((e.label, r));
  }

  // ── 输出汇总表 ─────────────────────────────────────────────────
  print('\n${'─' * 80}');
  print('${'类型'.padRight(22)}  ${'ID'.padRight(16)}  ${'结果'.padRight(5)}  详情');
  print('─' * 80);

  int passed = 0;
  for (final (label, r) in results) {
    final status = r.ok ? '✓ OK' : '✗ FAIL';
    if (r.ok) {
      passed++;
      final detail = r.isImage ? '图文 ${r.imageCount} 张' : '视频 [${r.quality}]';
      final titleShort = (r.title ?? '').length > 28
          ? '${r.title!.substring(0, 27)}…'
          : (r.title ?? '');
      print(
        '${label.padRight(22)}  ${r.shortId.padRight(16)}  ${status.padRight(7)} $detail  $titleShort',
      );
    } else {
      print(
        '${label.padRight(22)}  ${r.shortId.padRight(16)}  ${status.padRight(7)} ${r.error ?? ""}',
      );
    }
    if (r.htmlPath != null) {
      print('${' ' * 42}→ ${r.htmlPath}');
    }
  }

  print('─' * 80);
  print('结果：$passed / ${results.length} 通过\n');

  if (passed < results.length) exit(1);
}
