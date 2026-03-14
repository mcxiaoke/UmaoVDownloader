/// 批量测试脚本 — 读取 test/urls.txt 或 test/xhs.txt，逐条解析并打印摘要
///
/// 用法：
///   dart run tool/run_tests.dart [urls.txt|xhs.txt] [--debug]
///
/// 功能：
///   • 对每条 URL 调用对应 Parser 解析
///   • 将分享页 HTML 保存到 test/cache/<platform>/<id>.html，供手动分析
///   • 控制台输出对齐摘要表格，含 PASS / FAIL 标记
library;

import 'dart:io' as io;

import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'package:umao_vdownloader/services/douyin_parser.dart';
import 'package:umao_vdownloader/services/xiaohongshu_parser.dart';

// ── 平台类型 ──────────────────────────────────────────────────────────────────
enum Platform { douyin, xiaohongshu }

extension PlatformExt on Platform {
  String get displayName => switch (this) {
    Platform.douyin => '抖音',
    Platform.xiaohongshu => '小红书',
  };
}

// ── HTML 拦截 Client ──────────────────────────────────────────────────────────
/// 包装 http.Client，将每次 GET 响应 body 写入 [cacheDir]/<platform>/<id>.html
class _CachingClient extends http.BaseClient {
  _CachingClient(this._inner, this._cacheDir, this._platform, this._id);

  final http.Client _inner;
  final io.Directory _cacheDir;
  final Platform _platform;
  final String _id;

  // 最近一次 GET 请求的保存路径（供外部读取日志用）
  String? lastSavedPath;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request);

  @override
  Future<http.Response> get(Uri url, {Map<String, String>? headers}) async {
    final resp = await _inner.get(url, headers: headers);
    if (resp.statusCode == 200) {
      // 创建平台子目录
      final platformDir = io.Directory(
        path.join(_cacheDir.path, _platform.name),
      );
      if (!platformDir.existsSync()) {
        platformDir.createSync(recursive: true);
      }

      // 保存 HTML
      final htmlName = '${_id}.html';
      final htmlFile = io.File(path.join(platformDir.path, htmlName));
      await htmlFile.writeAsString(resp.body);
      lastSavedPath = htmlFile.path;

      // 提取并保存 __INITIAL_STATE__ JSON
      final jsonData = _extractInitialState(resp.body);
      if (jsonData != null) {
        final jsonName = '${_id}.json';
        final jsonFile = io.File(path.join(platformDir.path, jsonName));
        await jsonFile.writeAsString(jsonData);
      }
    }
    return resp;
  }

  // 从 HTML 中提取 __INITIAL_STATE__ JSON
  String? _extractInitialState(String html) {
    // 匹配 window.__INITIAL_STATE__ = {...}
    final reg = RegExp(
      r'window\.__INITIAL_STATE__\s*=\s*({.+?});?\s*</script>',
      caseSensitive: false,
      dotAll: true,
    );
    final match = reg.firstMatch(html);
    if (match != null) {
      var jsonStr = match.group(1)!;
      // 将 JavaScript undefined 替换为 null，使其成为合法 JSON
      // 使用 replaceAllMapped 来正确处理捕获组
      jsonStr = jsonStr.replaceAllMapped(
        RegExp(r':\s*undefined\s*([,}\]])'),
        (m) => ':null${m.group(1)}',
      );
      return jsonStr;
    }
    return null;
  }
}

// ── 解析一条 URL ─────────────────────────────────────────────────────────────
Future<_Result> _testOne(
  String url,
  io.Directory cacheDir,
  Platform platform, {
  bool debug = false,
}) async {
  String id;
  if (platform == Platform.douyin) {
    id = RegExp(r'v\.douyin\.com/([A-Za-z0-9_-]+)').firstMatch(url)?.group(1) ??
        RegExp(r'/(?:video|note|slides)/(\d+)').firstMatch(url)?.group(1) ??
        'unknown';
  } else {
    // xhslink.com/o/xxx 或 xiaohongshu.com/explore/xxx 或 /discovery/item/xxx
    id = RegExp(r'xhslink\.com/o/([A-Za-z0-9_-]+)').firstMatch(url)?.group(1) ??
        RegExp(r'/explore/(\w+)').firstMatch(url)?.group(1) ??
        RegExp(r'/discovery/item/(\w+)').firstMatch(url)?.group(1) ??
        'unknown';
  }

  final inner = http.Client();
  final caching = _CachingClient(inner, cacheDir, platform, id);

  try {
    if (platform == Platform.douyin) {
      final parser = DouyinParser(httpClient: caching);
      final info = await parser.parse(url);
      return _Result(
        id: id,
        ok: true,
        title: info.title,
        isImage: info.imageUrls.isNotEmpty,
        imageCount: info.imageUrls.length,
        quality: info.videoUrl.isNotEmpty ? 'video' : '',
        htmlPath: caching.lastSavedPath,
        platform: platform,
      );
    } else {
      final parser = XiaohongshuParser(client: caching);
      final info = await parser.parse(url, debug: debug);
      return _Result(
        id: id,
        ok: true,
        title: info.title,
        isImage: info.imageUrls.isNotEmpty && info.videoUrl.isEmpty,
        imageCount: info.imageUrls.length,
        quality: info.videoUrl.isNotEmpty ? 'video' : '',
        htmlPath: caching.lastSavedPath,
        platform: platform,
      );
    }
  } catch (e) {
    return _Result(
      id: id,
      ok: false,
      error: e.toString(),
      htmlPath: caching.lastSavedPath,
      platform: platform,
    );
  } finally {
    if (platform == Platform.douyin) {
      (inner as http.Client).close();
    } else {
      inner.close();
    }
  }
}

// ── 数据类 ───────────────────────────────────────────────────────────────────
class _Result {
  _Result({
    required this.id,
    required this.ok,
    required this.platform,
    this.title,
    this.isImage = false,
    this.imageCount = 0,
    this.quality = '',
    this.error,
    this.htmlPath,
  });

  final String id;
  final bool ok;
  final Platform platform;
  final String? title;
  final bool isImage;
  final int imageCount;
  final String quality;
  final String? error;
  final String? htmlPath;
}

// ── 主入口 ───────────────────────────────────────────────────────────────────
Future<void> main(List<String> args) async {
  // 解析参数
  String urlsFileName = 'urls.txt';
  bool debug = false;

  for (final arg in args) {
    if (arg == '--debug') {
      debug = true;
    } else if (arg.endsWith('.txt')) {
      urlsFileName = arg;
    }
  }

  final urlsFile = io.File(path.join('test', urlsFileName));
  if (!urlsFile.existsSync()) {
    print('找不到 ${urlsFile.path}');
    io.exit(1);
  }

  // 根据文件名或内容判断平台
  Platform detectPlatform(String fileName, List<String> lines) {
    if (fileName.contains('xhs')) return Platform.xiaohongshu;
    // 检查文件内容中的 URL 特征
    for (final line in lines) {
      if (line.contains('xhslink.com') || line.contains('xiaohongshu.com')) {
        return Platform.xiaohongshu;
      }
      if (line.contains('douyin.com') || line.contains('v.douyin.com')) {
        return Platform.douyin;
      }
    }
    return Platform.douyin; // 默认
  }

  final lines = urlsFile.readAsLinesSync();
  final platform = detectPlatform(urlsFileName, lines);

  // 解析 urls.txt，跳过空行和纯注释行
  final entries = <({String url, String label})>[];
  for (final line in lines) {
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
    print('${urlsFile.path} 中没有有效 URL');
    io.exit(1);
  }

  // 确保 cache 目录存在
  final cacheDir = io.Directory(path.join('test', 'cache'));
  await cacheDir.create(recursive: true);

  print('平台: ${platform.displayName}');
  print('文件: ${urlsFile.path}');
  print('共 ${entries.length} 条 URL，开始测试…\n');

  const delayMs = 6000;
  final results = <(String label, _Result result)>[];
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    if (i > 0) {
      await Future<void>.delayed(const Duration(milliseconds: delayMs));
    }
    io.stdout.write('  测试 ${e.label.padRight(20)} ${e.url} … ');
    final r = await _testOne(e.url, cacheDir, platform, debug: debug);
    io.stdout.writeln(r.ok ? 'OK' : 'FAIL');
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
        '${label.padRight(22)}  ${r.id.padRight(16)}  ${status.padRight(7)} $detail  $titleShort',
      );
    } else {
      print(
        '${label.padRight(22)}  ${r.id.padRight(16)}  ${status.padRight(7)} ${r.error ?? ""}',
      );
    }
    if (r.htmlPath != null) {
      print('${' ' * 42}→ ${r.htmlPath}');
    }
  }

  print('─' * 80);
  print('结果：$passed / ${results.length} 通过\n');

  if (passed < results.length) io.exit(1);
}
