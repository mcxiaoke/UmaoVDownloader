import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as wvwin;

import 'douyin_parser.dart';

/// 支持的平台类型
enum ParserPlatform {
  douyin,
  xiaohongshu,
  unknown;

  static ParserPlatform fromUrl(String url) {
    if (url.contains('douyin.com') || url.contains('iesdouyin.com')) {
      return ParserPlatform.douyin;
    }
    if (url.contains('xiaohongshu.com') || url.contains('xhslink.com')) {
      return ParserPlatform.xiaohongshu;
    }
    return ParserPlatform.unknown;
  }
}

typedef WebViewParserLog = void Function(String message);

/// JS 执行函数签名
typedef JsExecutor = Future<String?> Function(String script);

class WebViewParser {
  static const _timeout = Duration(seconds: 15);
  static const _douyinScriptPath = 'assets/js/extract_douyin_payload.js';
  static const _xhsScriptPath = 'assets/js/extract_xiaohongshu_payload.js';
  static const _androidUserAgent =
      'Mozilla/5.0 (Linux; Android 16; 23456PN2CC Build/BP2A.250605.031.A3; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/142.0.7444.173 Mobile Safari/537.36 MMWEBID/3396 MicroMessenger/8.0.69.3040(0x28004553) WeChat/arm64 Weixin NetType/WIFI Language/zh_CN ABI/arm64';
  static const _xhsUserAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1';
  static const _extractMaxRetries = 2;
  static const _extractRetryDelay = Duration(milliseconds: 500);
  static final Map<String, String?> _scriptCache = {};

  Future<VideoInfo?> tryParse(String input, {WebViewParserLog? log}) async {
    final url = RegExp(r'https?://[^\s，,。]+').firstMatch(input)?.group(0);
    if (url == null || url.isEmpty) {
      log?.call('WebView 解析输入中无有效 URL');
      return null;
    }

    final platform = ParserPlatform.fromUrl(url);
    if (platform == ParserPlatform.unknown) {
      log?.call('WebView 不支持的平台: $url');
      return null;
    }

    log?.call('WebView 解析平台: ${platform.name}');

    if (Platform.isWindows) {
      return _tryParseOnWindows(url, platform: platform, log: log);
    }

    if (!Platform.isAndroid) {
      log?.call('WebView 解析当前仅实现 Android/Windows');
      return null;
    }

    // 根据平台选择 UA
    final ua = platform == ParserPlatform.xiaohongshu
        ? _xhsUserAgent
        : _androidUserAgent;

    log?.call('WebView 使用 ${platform.name} UA 解析');
    final info = await _tryParseWithUserAgent(
      url,
      platform: platform,
      ua: ua,
      log: log,
    );
    if (info != null) {
      log?.call('WebView 解析成功: itemId=${info.itemId}');
      return info;
    }

    log?.call('WebView 解析失败');
    return null;
  }

  Future<VideoInfo?> _tryParseOnWindows(
    String url, {
    required ParserPlatform platform,
    WebViewParserLog? log,
  }) async {
    log?.call('WebView(Windows) 开始初始化');

    final runtimeVersion = await wvwin.WebviewController.getWebViewVersion();
    if (runtimeVersion == null || runtimeVersion.trim().isEmpty) {
      log?.call('WebView2 Runtime 未安装，跳过 Windows WebView 解析');
      return null;
    }
    log?.call('WebView2 Runtime: $runtimeVersion');

    final controller = wvwin.WebviewController();
    StreamSubscription<wvwin.LoadingState>? loadingSub;
    StreamSubscription<String>? urlSub;
    Completer<void>? navCompleted;
    String? currentUrl;

    // 根据平台选择 UA
    final ua = platform == ParserPlatform.xiaohongshu
        ? _xhsUserAgent
        : _androidUserAgent;

    try {
      await controller.initialize();
      await controller.setPopupWindowPolicy(
        wvwin.WebviewPopupWindowPolicy.deny,
      );
      await controller.setUserAgent(ua);

      urlSub = controller.url.listen((u) {
        currentUrl = u;
      });

      loadingSub = controller.loadingState.listen((state) {
        if (state == wvwin.LoadingState.loading) {
          log?.call('WebView(Windows) loading...');
        } else if (state == wvwin.LoadingState.navigationCompleted) {
          log?.call('WebView(Windows) navigationCompleted');
          if (navCompleted != null && !navCompleted!.isCompleted) {
            navCompleted!.complete();
          }
        }
      });

      Future<bool> loadAndWait(
        String targetUrl, {
        required String phase,
      }) async {
        navCompleted = Completer<void>();
        log?.call('WebView(Windows) $phase: $targetUrl');
        await controller.loadUrl(targetUrl);
        try {
          await navCompleted!.future.timeout(_timeout);
          return true;
        } on TimeoutException {
          log?.call('WebView(Windows) $phase超时');
          return false;
        }
      }

      if (!await loadAndWait(url, phase: '开始加载')) return null;

      final extractScript = await _loadExtractScript(platform, log: log);
      if (extractScript == null) return null;

      // 从原始 URL 提取 shareId（跳转后会丢失）
      final shareId = _extractShareId(url);

      final data = await _tryExtractWithFallback(
        initialUrl: url,
        currentUrl: currentUrl ?? url,
        platform: platform,
        extractScript: extractScript,
        shareId: shareId,
        executeJs: (script) async {
          final raw = await controller.executeScript(script);
          return _normalizeJsResult(raw);
        },
        loadUrl: (targetUrl) => loadAndWait(targetUrl, phase: '回退加载'),
        log: (msg) => log?.call('WebView(Windows) $msg'),
      );

      if (data == null) return null;

      final info = _mapToVideoInfo(data);
      log?.call('WebView(Windows) 解析成功: itemId=${info.itemId}');
      return info;
    } on PlatformException catch (e) {
      log?.call('WebView(Windows) 平台错误: ${e.code} ${e.message ?? ''}');
      return null;
    } catch (e) {
      log?.call('WebView(Windows) 异常: $e');
      return null;
    } finally {
      await loadingSub?.cancel();
      await urlSub?.cancel();
      await controller.dispose();
    }
  }

  String? _buildIesShareFallbackUrl(String sourceUrl) {
    final uri = Uri.tryParse(sourceUrl);
    if (uri == null) return null;

    final awemeId = RegExp(
      r'/(?:video|note|slides|detail)/(\d+)',
    ).firstMatch(uri.path)?.group(1);
    if (awemeId == null || awemeId.isEmpty) return null;

    final query = uri.hasQuery ? '?${uri.query}' : '';
    return 'https://www.iesdouyin.com/share/video/$awemeId/$query';
  }

  Future<VideoInfo?> _tryParseWithUserAgent(
    String url, {
    required ParserPlatform platform,
    required String ua,
    WebViewParserLog? log,
  }) async {
    final controller = WebViewController();
    final finished = Completer<void>();
    String? currentUrl;

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (u) => log?.call('WebView onPageStarted: $u'),
          onPageFinished: (u) {
            log?.call('WebView onPageFinished: $u');
            currentUrl = u;
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

    final extractScript = await _loadExtractScript(platform, log: log);
    if (extractScript == null) return null;

    Future<bool> loadUrl(String targetUrl) async {
      final retryFinished = Completer<void>();
      controller.setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (u) => log?.call('WebView onPageStarted: $u'),
          onPageFinished: (u) {
            log?.call('WebView onPageFinished: $u');
            currentUrl = u;
            if (!retryFinished.isCompleted) retryFinished.complete();
          },
          onWebResourceError: (e) {
            if ((e.description).contains('ERR_UNKNOWN_URL_SCHEME')) {
              log?.call('WebView 资源错误(可忽略): ${e.description}');
            } else {
              log?.call('WebView 资源错误: ${e.description}');
            }
          },
        ),
      );
      await controller.loadRequest(Uri.parse(targetUrl));
      try {
        await retryFinished.future.timeout(_timeout);
        return true;
      } on TimeoutException {
        log?.call('WebView 回退页加载超时');
        return false;
      }
    }

    // 从原始 URL 提取 shareId（跳转后会丢失）
    final shareId = _extractShareId(url);

    final data = await _tryExtractWithFallback(
      initialUrl: url,
      currentUrl: currentUrl ?? url,
      platform: platform,
      extractScript: extractScript,
      shareId: shareId,
      executeJs: (script) async {
        final raw = await controller.runJavaScriptReturningResult(script);
        return _normalizeJsResult(raw);
      },
      loadUrl: loadUrl,
      log: log,
    );

    return data == null ? null : _mapToVideoInfo(data);
  }

  /// 从抖音/小红书 URL 中提取 shareId
  String? _extractShareId(String url) {
    // 抖音短链接: v.douyin.com/{shareId}
    final douyinMatch = RegExp(r'v\.douyin\.com/([A-Za-z0-9_-]+)').firstMatch(url);
    if (douyinMatch != null) return douyinMatch.group(1);

    // 小红书短链接: xhslink.com/o/{shareId}
    final xhsMatch = RegExp(r'xhslink\.com/o/([A-Za-z0-9_-]+)').firstMatch(url);
    if (xhsMatch != null) return xhsMatch.group(1);

    return null;
  }

  /// 统一提取和回退逻辑
  Future<Map<String, dynamic>?> _tryExtractWithFallback({
    required String initialUrl,
    required String currentUrl,
    required ParserPlatform platform,
    required String extractScript,
    String? shareId,
    required JsExecutor executeJs,
    required Future<bool> Function(String) loadUrl,
    required WebViewParserLog? log,
  }) async {
    var data = await _runExtractWithRetry(
      extractScript: extractScript,
      shareId: shareId,
      executeJs: executeJs,
      log: log,
    );

    // 抖音：某些短链会落到不含 _ROUTER_DATA 的壳页，回退到 iesdouyin share 页重试
    if (platform == ParserPlatform.douyin && data?['reason'] == 'no_router_data') {
      final fallback = _buildIesShareFallbackUrl(currentUrl);
      if (fallback != null && fallback != currentUrl) {
        log?.call('WebView 回退 share 页重试: $fallback');
        if (await loadUrl(fallback)) {
          data = await _runExtractWithRetry(
            extractScript: extractScript,
            shareId: shareId,
            executeJs: executeJs,
            log: log,
          );
        }
      }
    }

    if (data?['ok'] != true) {
      log?.call('WebView 提取失败: ${data?['reason'] ?? 'unknown'}');
      return null;
    }

    return data;
  }

  /// 统一的重试提取逻辑
  Future<Map<String, dynamic>?> _runExtractWithRetry({
    required String extractScript,
    String? shareId,
    required JsExecutor executeJs,
    required WebViewParserLog? log,
  }) async {
    Map<String, dynamic>? last;
    for (var i = 0; i < _extractMaxRetries; i++) {
      // 先注入 shareId 到全局变量，再执行提取脚本
      if (shareId != null) {
        await executeJs('window.__SHARE_ID__ = "$shareId";');
      }
      final jsonText = await executeJs(extractScript);
      if (jsonText == null || jsonText.isEmpty) {
        log?.call('JS 返回为空');
        return null;
      }

      dynamic decoded;
      try {
        decoded = jsonDecode(jsonText);
      } catch (e) {
        log?.call('JSON 解析失败: $e');
        return null;
      }
      if (decoded is! Map) return null;

      final data = Map<String, dynamic>.from(decoded.cast<String, dynamic>());
      last = data;
      if (data['ok'] == true) return data;
      if (data['reason'] != 'no_router_data') return data;
      if (i < _extractMaxRetries - 1) {
        await Future<void>.delayed(_extractRetryDelay);
      }
    }
    return last;
  }

  Future<String?> _loadExtractScript(
    ParserPlatform platform, {
    WebViewParserLog? log,
  }) async {
    final assetPath = platform == ParserPlatform.xiaohongshu
        ? _xhsScriptPath
        : _douyinScriptPath;

    // 检查缓存
    if (_scriptCache.containsKey(assetPath)) {
      return _scriptCache[assetPath];
    }

    try {
      final script = await rootBundle.loadString(assetPath);
      if (script.trim().isEmpty) {
        log?.call('WebView JS 资源为空: $assetPath');
        return null;
      }
      _scriptCache[assetPath] = script;
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

    // 提取通用字段 - 对齐 backend 字段
    final imageUrls = (data['imageUrls'] is List)
        ? (data['imageUrls'] as List)
              .map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList()
        : const <String>[];

    final imageThumbUrls = (data['imageThumbs'] is List)
        ? (data['imageThumbs'] as List)
              .map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList()
        : const <String>[];

    final livePhotoUrls = (data['livePhotoUrls'] is List)
        ? (data['livePhotoUrls'] as List)
              .map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList()
        : const <String>[];

    final musicUrl = data['musicUrl']?.toString();
    final musicTitle = data['musicTitle']?.toString();
    final musicAuthor = data['musicAuthor']?.toString();
    final videoUrl = data['videoUrl']?.toString() ?? '';

    // 提取视频码率 (bps -> kbps)
    final videoBitrate = int.tryParse(data['videoBitrate']?.toString() ?? '');
    final bitrateKbps = videoBitrate != null ? videoBitrate ~/ 1000 : null;

    // 根据类型构建结果
    return switch (type) {
      'image' => VideoInfo(
          itemId: id,
          title: title,
          videoFileId: '',
          videoUrl: '',
          mediaType: MediaType.image,
          coverUrl: data['coverUrl']?.toString(),
          shareId: data['shareId']?.toString(),
          width: width,
          height: height,
          bitrateKbps: bitrateKbps,
          imageUrls: imageUrls,
          imageThumbUrls: imageThumbUrls,
          musicUrl: (musicUrl != null && musicUrl.isNotEmpty) ? musicUrl : null,
          musicTitle: musicTitle,
          musicAuthor: musicAuthor,
          livePhotoUrls: const [],
        ),
      'livephoto' => VideoInfo(
          itemId: id,
          title: title,
          videoFileId: _pickBestVideoFileId(videoUrl),
          videoUrl: videoUrl,
          mediaType: MediaType.livePhoto,
          coverUrl: data['coverUrl']?.toString(),
          shareId: data['shareId']?.toString(),
          width: width,
          height: height,
          bitrateKbps: bitrateKbps,
          imageUrls: imageUrls,
          imageThumbUrls: imageThumbUrls.isNotEmpty ? imageThumbUrls : imageUrls,
          livePhotoUrls: livePhotoUrls,
        ),
      'video' => VideoInfo(
          itemId: id,
          title: title,
          videoFileId: _pickBestVideoFileId(videoUrl),
          videoUrl: videoUrl,
          mediaType: MediaType.video,
          coverUrl: data['coverUrl']?.toString(),
          shareId: data['shareId']?.toString(),
          width: width,
          height: height,
          bitrateKbps: bitrateKbps,
          livePhotoUrls: const [],
        ),
      _ => VideoInfo(
          // 默认按视频处理
          itemId: id,
          title: title,
          videoFileId: _pickBestVideoFileId(videoUrl),
          videoUrl: videoUrl,
          mediaType: MediaType.video,
          coverUrl: data['coverUrl']?.toString(),
          shareId: data['shareId']?.toString(),
          width: width,
          height: height,
          bitrateKbps: bitrateKbps,
          livePhotoUrls: const [],
        ),
    };
  }

  String _pickBestVideoFileId(String videoUrl) {
    if (videoUrl.isEmpty) return '';
    final id = Uri.tryParse(videoUrl)?.queryParameters['video_id'];
    return id ?? '';
  }
}
