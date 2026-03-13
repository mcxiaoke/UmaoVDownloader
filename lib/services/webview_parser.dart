import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'douyin_parser.dart';

typedef WebViewParserLog = void Function(String message);

class WebViewParser {
  static const _timeout = Duration(seconds: 15);
  static const _extractScriptAssetPath = 'assets/js/extract_douyin_payload.js';
  static const _androidUserAgent =
      'Mozilla/5.0 (Linux; Android 16; 23456PN2CC Build/BP2A.250605.031.A3; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/142.0.7444.173 Mobile Safari/537.36 MMWEBID/3396 MicroMessenger/8.0.69.3040(0x28004553) WeChat/arm64 Weixin NetType/WIFI Language/zh_CN ABI/arm64';
  static String? _extractScriptCache;

  Future<VideoInfo?> tryParse(String input, {WebViewParserLog? log}) async {
    if (!Platform.isAndroid) {
      log?.call('WebView 解析当前仅实现 Android');
      return null;
    }

    final url = RegExp(r'https?://[^\s，,。]+').firstMatch(input)?.group(0);
    if (url == null || url.isEmpty) {
      log?.call('WebView 解析输入中无有效 URL');
      return null;
    }

    log?.call('WebView 使用固定 UA 解析');
    final info = await _tryParseWithUserAgent(
      url,
      ua: _androidUserAgent,
      log: log,
    );
    if (info != null) {
      log?.call('WebView 解析成功: id=${info.videoId}');
      return info;
    }

    log?.call('WebView 解析失败');
    return null;
  }

  Future<VideoInfo?> _tryParseWithUserAgent(
    String url, {
    required String ua,
    WebViewParserLog? log,
  }) async {
    final controller = WebViewController();
    final finished = Completer<void>();

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (u) => log?.call('WebView onPageStarted: $u'),
          onPageFinished: (u) {
            log?.call('WebView onPageFinished: $u');
            if (!finished.isCompleted) finished.complete();
          },
          onWebResourceError: (e) {
            if ((e.description).contains('ERR_UNKNOWN_URL_SCHEME')) {
              log?.call('WebView 资源错误(可忽略): ${e.description}');
            } else {
              log?.call('WebView 资源错误: ${e.description}');
            }
          },
        ),
      )
      ..setUserAgent(ua);

    log?.call('WebView 开始加载: $url');
    await controller.loadRequest(Uri.parse(url));

    try {
      await finished.future.timeout(_timeout);
    } on TimeoutException {
      log?.call('WebView 加载超时');
      return null;
    }

    final extractScript = await _loadExtractScript(log: log);
    if (extractScript == null) return null;

    final raw = await controller.runJavaScriptReturningResult(extractScript);
    final jsonText = _normalizeJsResult(raw);
    if (jsonText == null || jsonText.isEmpty) {
      log?.call('WebView JS 返回为空');
      return null;
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(jsonText);
    } catch (e) {
      log?.call('WebView JSON 解析失败: $e');
      return null;
    }
    if (decoded is! Map) return null;

    final data = Map<String, dynamic>.from(decoded.cast<String, dynamic>());
    if (data['ok'] != true) {
      log?.call('WebView 提取失败: ${data['reason'] ?? 'unknown'}');
      return null;
    }

    return _mapToVideoInfo(data);
  }

  Future<String?> _loadExtractScript({WebViewParserLog? log}) async {
    if (_extractScriptCache != null && _extractScriptCache!.isNotEmpty) {
      return _extractScriptCache;
    }
    try {
      final script = await rootBundle.loadString(_extractScriptAssetPath);
      if (script.trim().isEmpty) {
        log?.call('WebView JS 资源为空: $_extractScriptAssetPath');
        return null;
      }
      _extractScriptCache = script;
      return script;
    } catch (e) {
      log?.call('加载 WebView JS 资源失败: $e');
      return null;
    }
  }

  String? _normalizeJsResult(Object? raw) {
    if (raw == null) return null;
    if (raw is String) {
      final s = raw.trim();
      if (s.isEmpty) return null;
      if (s.startsWith('{') && s.endsWith('}')) return s;
      // Android may wrap JS string return as JSON string literal.
      try {
        final inner = jsonDecode(s);
        if (inner is String) return inner;
      } catch (_) {
        return s;
      }
      return s;
    }
    return raw.toString();
  }

  VideoInfo _mapToVideoInfo(Map<String, dynamic> data) {
    final type = data['type']?.toString() ?? 'video';
    final id = data['id']?.toString() ?? '';
    final title = data['title']?.toString() ?? '作品_$id';

    final width = int.tryParse(data['width']?.toString() ?? '');
    final height = int.tryParse(data['height']?.toString() ?? '');

    if (type == 'image') {
      final imageUrls = (data['imageUrls'] is List)
          ? (data['imageUrls'] as List)
                .map((e) => e.toString())
                .where((e) => e.isNotEmpty)
                .toList()
          : const <String>[];
      final musicUrl = data['musicUrl']?.toString();
      return VideoInfo(
        videoId: id,
        title: title,
        videoFileId: '',
        qualityUrls: const {},
        coverUrl: data['coverUrl']?.toString(),
        shareId: data['shareId']?.toString(),
        width: width,
        height: height,
        imageUrls: imageUrls,
        musicUrl: (musicUrl != null && musicUrl.isNotEmpty) ? musicUrl : null,
        musicTitle: data['musicTitle']?.toString(),
      );
    }

    final qualityUrls = <VideoQuality, String>{};
    final q = data['qualityUrls'];
    if (q is Map) {
      for (final e in q.entries) {
        final quality = VideoQuality.fromRatio(e.key.toString());
        final u = e.value?.toString();
        if (quality != null && u != null && u.isNotEmpty) {
          qualityUrls[quality] = u;
        }
      }
    }

    final fileId = _pickBestVideoFileId(qualityUrls);
    return VideoInfo(
      videoId: id,
      title: title,
      videoFileId: fileId,
      qualityUrls: qualityUrls,
      coverUrl: data['coverUrl']?.toString(),
      shareId: data['shareId']?.toString(),
      width: width,
      height: height,
    );
  }

  String _pickBestVideoFileId(Map<VideoQuality, String> qualityUrls) {
    for (final q in [
      VideoQuality.p2160,
      VideoQuality.p1080,
      VideoQuality.p720,
      VideoQuality.p480,
      VideoQuality.p360,
    ]) {
      final u = qualityUrls[q];
      if (u == null) continue;
      final id = Uri.tryParse(u)?.queryParameters['video_id'];
      if (id != null && id.isNotEmpty) return id;
    }
    return '';
  }
}
