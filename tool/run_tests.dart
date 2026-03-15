/// 批量测试脚本 — 读取 test/urls.txt 或 test/xhs.txt，逐条解析并验证字段
///
/// 用法：
///   dart run tool/run_tests.dart [urls.txt|xhs.txt] [--debug] [--validate]
///
/// 功能：
///   • 对每条 URL 调用对应 Parser 解析
///   • 验证解析结果字段（id, title, type, url字段是否合法）
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

// ── 验证结果类型 ──────────────────────────────────────────────────────────────
enum ValidationStatus { pass, fail, skip }

class FieldValidation {
  final String field;
  final bool exists;
  final bool isValid;
  final String? error;

  FieldValidation({
    required this.field,
    required this.exists,
    required this.isValid,
    this.error,
  });

  bool get ok => exists && isValid;
}

class ValidationReport {
  final String id;
  final String type; // video, image, livephoto
  final List<FieldValidation> fields;
  final List<String> errors;

  ValidationReport({
    required this.id,
    required this.type,
    required this.fields,
    required this.errors,
  });

  bool get allOk => errors.isEmpty && fields.every((f) => f.ok);
  int get passCount => fields.where((f) => f.ok).length;
  int get totalCount => fields.length;
}

// ── HTML 拦截 Client ──────────────────────────────────────────────────────────
class _CachingClient extends http.BaseClient {
  _CachingClient(this._inner, this._cacheDir, this._platform, this._id);

  final http.Client _inner;
  final io.Directory _cacheDir;
  final Platform _platform;
  final String _id;
  String? lastSavedPath;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request);

  @override
  Future<http.Response> get(Uri url, {Map<String, String>? headers}) async {
    final resp = await _inner.get(url, headers: headers);
    if (resp.statusCode == 200) {
      final platformDir = io.Directory(
        path.join(_cacheDir.path, _platform.name),
      );
      if (!platformDir.existsSync()) {
        platformDir.createSync(recursive: true);
      }

      final htmlName = '${_id}.html';
      final htmlFile = io.File(path.join(platformDir.path, htmlName));
      await htmlFile.writeAsString(resp.body);
      lastSavedPath = htmlFile.path;

      final jsonData = _extractInitialState(resp.body);
      if (jsonData != null) {
        final jsonName = '${_id}.json';
        final jsonFile = io.File(path.join(platformDir.path, jsonName));
        await jsonFile.writeAsString(jsonData);
      }
    }
    return resp;
  }

  String? _extractInitialState(String html) {
    final reg = RegExp(
      r'window\.__INITIAL_STATE__\s*=\s*({.+?});?\s*</script>',
      caseSensitive: false,
      dotAll: true,
    );
    final match = reg.firstMatch(html);
    if (match != null) {
      var jsonStr = match.group(1)!;
      jsonStr = jsonStr.replaceAllMapped(
        RegExp(r':\s*undefined\s*([,}\]])'),
        (m) => ':null${m.group(1)}',
      );
      return jsonStr;
    }
    return null;
  }
}

// ── URL 验证工具 ─────────────────────────────────────────────────────────────
bool isValidUrl(String? url) {
  if (url == null || url.isEmpty) return false;
  try {
    final uri = Uri.parse(url);
    return uri.isAbsolute && (uri.scheme == 'http' || uri.scheme == 'https');
  } catch (_) {
    return false;
  }
}

// ── 字段验证 ─────────────────────────────────────────────────────────────────
ValidationReport validateVideoInfo(VideoInfo info, Platform platform) {
  final fields = <FieldValidation>[];
  final errors = <String>[];

  // 基础字段验证
  fields.add(FieldValidation(
    field: 'itemId',
    exists: info.itemId.isNotEmpty,
    isValid: info.itemId.isNotEmpty,
    error: info.itemId.isEmpty ? 'itemId为空' : null,
  ));

  fields.add(FieldValidation(
    field: 'title',
    exists: info.title.isNotEmpty,
    isValid: info.title.isNotEmpty,
    error: info.title.isEmpty ? 'title为空' : null,
  ));

  // 类型判断
  String type;
  if (info.livePhotoUrls.isNotEmpty) {
    type = 'livephoto';
  } else if (info.isImagePost) {
    type = 'image';
  } else {
    type = 'video';
  }

  // 根据类型验证对应字段
  if (type == 'video') {
    // 视频字段验证
    fields.add(FieldValidation(
      field: 'videoUrl',
      exists: info.videoUrl.isNotEmpty,
      isValid: isValidUrl(info.videoUrl),
      error: info.videoUrl.isEmpty ? 'videoUrl为空' : !isValidUrl(info.videoUrl) ? 'videoUrl格式无效' : null,
    ));

    fields.add(FieldValidation(
      field: 'videoFileId',
      exists: info.videoFileId.isNotEmpty,
      isValid: info.videoFileId.isNotEmpty,
      error: info.videoFileId.isEmpty ? 'videoFileId为空' : null,
    ));

    if (info.coverUrl != null) {
      fields.add(FieldValidation(
        field: 'coverUrl',
        exists: true,
        isValid: isValidUrl(info.coverUrl),
        error: !isValidUrl(info.coverUrl) ? 'coverUrl格式无效' : null,
      ));
    }
  } else if (type == 'livephoto') {
    // 实况图字段验证
    fields.add(FieldValidation(
      field: 'livePhotoUrls',
      exists: info.livePhotoUrls.isNotEmpty,
      isValid: info.livePhotoUrls.every(isValidUrl),
      error: info.livePhotoUrls.isEmpty ? 'livePhotoUrls为空' : 
             !info.livePhotoUrls.every(isValidUrl) ? 'livePhotoUrls包含无效URL' : null,
    ));

    fields.add(FieldValidation(
      field: 'videoUrl',
      exists: info.videoUrl.isNotEmpty,
      isValid: isValidUrl(info.videoUrl),
      error: info.videoUrl.isEmpty ? 'videoUrl为空(首视频)' : !isValidUrl(info.videoUrl) ? 'videoUrl格式无效' : null,
    ));

    fields.add(FieldValidation(
      field: 'imageUrls',
      exists: info.imageUrls.isNotEmpty,
      isValid: info.imageUrls.every(isValidUrl),
      error: info.imageUrls.isEmpty ? 'imageUrls为空' :
             !info.imageUrls.every(isValidUrl) ? 'imageUrls包含无效URL' : null,
    ));

    if (info.imageThumbUrls.isNotEmpty) {
      fields.add(FieldValidation(
        field: 'imageThumbUrls',
        exists: true,
        isValid: info.imageThumbUrls.every(isValidUrl),
        error: !info.imageThumbUrls.every(isValidUrl) ? 'imageThumbUrls包含无效URL' : null,
      ));
    }
  } else if (type == 'image') {
    // 图文字段验证
    fields.add(FieldValidation(
      field: 'imageUrls',
      exists: info.imageUrls.isNotEmpty,
      isValid: info.imageUrls.every(isValidUrl),
      error: info.imageUrls.isEmpty ? 'imageUrls为空' :
             !info.imageUrls.every(isValidUrl) ? 'imageUrls包含无效URL' : null,
    ));

    if (info.imageThumbUrls.isNotEmpty) {
      fields.add(FieldValidation(
        field: 'imageThumbUrls',
        exists: true,
        isValid: info.imageThumbUrls.every(isValidUrl),
        error: !info.imageThumbUrls.every(isValidUrl) ? 'imageThumbUrls包含无效URL' : null,
      ));
    }

    // 背景音乐可选
    if (info.musicUrl != null) {
      fields.add(FieldValidation(
        field: 'musicUrl',
        exists: true,
        isValid: isValidUrl(info.musicUrl),
        error: !isValidUrl(info.musicUrl) ? 'musicUrl格式无效' : null,
      ));
    }
  }

  // 通用可选字段验证
  if (info.shareId != null) {
    fields.add(FieldValidation(
      field: 'shareId',
      exists: true,
      isValid: info.shareId!.isNotEmpty,
    ));
  }

  // 收集错误
  for (final f in fields) {
    if (!f.ok && f.error != null) {
      errors.add('${f.field}: ${f.error}');
    }
  }

  return ValidationReport(
    id: info.itemId,
    type: type,
    fields: fields,
    errors: errors,
  );
}

// ── 解析一条 URL ─────────────────────────────────────────────────────────────
class _ParseResult {
  final String id;
  final bool ok;
  final Platform platform;
  final String? title;
  final String type;
  final int imageCount;
  final int? livePhotoCount;
  final String? error;
  final String? htmlPath;
  final ValidationReport? validation;

  _ParseResult({
    required this.id,
    required this.ok,
    required this.platform,
    this.title,
    this.type = 'unknown',
    this.imageCount = 0,
    this.livePhotoCount,
    this.error,
    this.htmlPath,
    this.validation,
  });
}

Future<_ParseResult> _testOne(
  String url,
  io.Directory cacheDir,
  Platform platform, {
  bool debug = false,
  bool validate = false,
}) async {
  String id;
  if (platform == Platform.douyin) {
    id = RegExp(r'v\.douyin\.com/([A-Za-z0-9_-]+)').firstMatch(url)?.group(1) ??
        RegExp(r'/(?:video|note|slides)/(\d+)').firstMatch(url)?.group(1) ??
        'unknown';
  } else {
    id = RegExp(r'xhslink\.com/o/([A-Za-z0-9_-]+)').firstMatch(url)?.group(1) ??
        RegExp(r'/explore/(\w+)').firstMatch(url)?.group(1) ??
        RegExp(r'/discovery/item/(\w+)').firstMatch(url)?.group(1) ??
        'unknown';
  }

  final inner = http.Client();
  final caching = _CachingClient(inner, cacheDir, platform, id);

  try {
    VideoInfo info;
    if (platform == Platform.douyin) {
      final parser = DouyinParser(httpClient: caching);
      info = await parser.parse(url);
    } else {
      final parser = XiaohongshuParser(client: caching);
      info = await parser.parse(url, debug: debug);
    }

    // 验证字段
    ValidationReport? validation;
    if (validate) {
      validation = validateVideoInfo(info, platform);
    }

    // 判断类型
    String type;
    int? livePhotoCount;
    if (info.livePhotoUrls.isNotEmpty) {
      type = 'livephoto';
      livePhotoCount = info.livePhotoUrls.length;
    } else if (info.isImagePost) {
      type = 'image';
    } else {
      type = 'video';
    }

    return _ParseResult(
      id: id,
      ok: true,
      platform: platform,
      title: info.title,
      type: type,
      imageCount: info.imageUrls.length,
      livePhotoCount: livePhotoCount,
      htmlPath: caching.lastSavedPath,
      validation: validation,
    );
  } catch (e) {
    return _ParseResult(
      id: id,
      ok: false,
      platform: platform,
      error: e.toString(),
      htmlPath: caching.lastSavedPath,
    );
  } finally {
    inner.close();
  }
}

// ── 主入口 ───────────────────────────────────────────────────────────────────
Future<void> main(List<String> args) async {
  String urlsFileName = 'urls.txt';
  bool debug = false;
  bool validate = false;

  for (final arg in args) {
    if (arg == '--debug') {
      debug = true;
    } else if (arg == '--validate') {
      validate = true;
    } else if (arg.endsWith('.txt')) {
      urlsFileName = arg;
    }
  }

  final urlsFile = io.File(path.join('test', urlsFileName));
  if (!urlsFile.existsSync()) {
    print('找不到 ${urlsFile.path}');
    io.exit(1);
  }

  Platform detectUrlPlatform(String url) {
    if (url.contains('xhslink.com') || url.contains('xiaohongshu.com')) {
      return Platform.xiaohongshu;
    }
    if (url.contains('douyin.com') || url.contains('v.douyin.com')) {
      return Platform.douyin;
    }
    return Platform.douyin;
  }

  final lines = urlsFile.readAsLinesSync();

  final entries = <({String url, String label})>[];
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

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

  final cacheDir = io.Directory(path.join('test', 'cache'));
  await cacheDir.create(recursive: true);

  print('文件: ${urlsFile.path}');
  print('验证模式: ${validate ? "开启" : "关闭"}');
  print('共 ${entries.length} 条 URL，开始测试…\n');

  const delayMs = 6000;
  final results = <(String label, _ParseResult result)>[];
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    final platform = detectUrlPlatform(e.url);
    if (i > 0) {
      await Future<void>.delayed(const Duration(milliseconds: delayMs));
    }
    io.stdout.write('  测试 ${e.label.padRight(20)} ${e.url} … ');
    final r = await _testOne(e.url, cacheDir, platform, debug: debug, validate: validate);
    io.stdout.writeln(r.ok ? 'OK' : 'FAIL');
    results.add((e.label, r));
  }

  // ── 输出汇总表 ─────────────────────────────────────────────────
  print('\n${'─' * 100}');
  print('${'类型'.padRight(20)}  ${'ID'.padRight(14)}  ${'平台'.padRight(6)}  ${'结果'.padRight(6)}  ${'内容类型'.padRight(10)}  详情');
  print('─' * 100);

  int passed = 0;
  int validationPassed = 0;
  
  for (final (label, r) in results) {
    final status = r.ok ? (r.validation?.allOk ?? true ? '✓ PASS' : '⚠ WARN') : '✗ FAIL';
    
    if (r.ok) {
      passed++;
      if (r.validation?.allOk ?? true) validationPassed++;
      
      String contentType;
      if (r.type == 'livephoto') {
        contentType = '实况图(${r.livePhotoCount})';
      } else if (r.type == 'image') {
        contentType = '图文(${r.imageCount})';
      } else {
        contentType = '视频';
      }
      
      final titleShort = (r.title ?? '').length > 25
          ? '${r.title!.substring(0, 24)}…'
          : (r.title ?? '');
      
      final platformShort = r.platform == Platform.douyin ? '抖音' : '小红书';
      
      print(
        '${label.padRight(20)}  ${r.id.padRight(14)}  ${platformShort.padRight(6)}  ${status.padRight(6)}  ${contentType.padRight(10)}  $titleShort',
      );

      // 显示验证详情
      if (validate && r.validation != null && !r.validation!.allOk) {
        for (final error in r.validation!.errors) {
          print('${' ' * 58}  ! $error');
        }
      }
    } else {
      final platformShort = r.platform == Platform.douyin ? '抖音' : '小红书';
      print(
        '${label.padRight(20)}  ${r.id.padRight(14)}  ${platformShort.padRight(6)}  ${status.padRight(6)}  ${r.error ?? ""}',
      );
    }
    
    if (r.htmlPath != null) {
      print('${' ' * 50}  → ${r.htmlPath}');
    }
  }

  print('─' * 100);
  print('解析结果: $passed / ${results.length} 通过');
  if (validate) {
    print('字段验证: $validationPassed / ${results.where((r) => r.$2.ok).length} 通过');
  }
  print('');

  if (passed < results.length || (validate && validationPassed < results.where((r) => r.$2.ok).length)) {
    io.exit(1);
  }
}
