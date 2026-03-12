import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../douyin_parser.dart';
import 'video_downloader.dart';

/// 公共 UA 常量（供所有平台下载器引用）
const kUaEdge =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/145.0.0.0 Safari/537.36 Edg/145.0.0.0';

const kUaIosWechat =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6_2 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) '
    'Mobile/15E148 MicroMessenger/8.0.69(0x28004553) '
    'NetType/WIFI Language/zh_CN';

const kUaAndroidWechat =
    'Mozilla/5.0 (Linux; Android 16; 23127PN0CC Build/BP2A.250605.031.A3; wv) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Version/4.0 Chrome/142.0.7444.173 Mobile Safari/537.36 '
    'XWEB/1420273 MMWEBSDK/20260201 MMWEBID/3396 '
    'MicroMessenger/8.0.69.3040(0x28004553) WeChat/arm64 '
    'Weixin NetType/WIFI Language/zh_CN ABI/arm64';

/// 抖音 iOS App 自身 UA（aweme 是抖音内部代号，CDN 对自家 App 放行策略最宽松）
const kUaIosDouyin =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) '
    'Mobile/15E148 aweme_36.7.0 Region/CN AppTheme/light '
    'NetType/WIFI JsSdk/2.0 Channel/App ByteLocale/zh '
    'ByteFullLocale/zh-Hans-CN WKWebView/1 Bullet/1 aweme/36.7.0 '
    'BytedanceWebview/d8a21c6 AnnieX/1 Forest/1 ReqTrigger/renderEngine';

/// 各平台下载器的抽象基类。
///
/// 实现了通用的文件命名和带 UA 重试的流式下载循环，
/// 子类只需覆写 [downloadUserAgents]、[getDefaultDirectory]
/// 并根据需要覆写 [beforeDownload] / [afterDownload]。
abstract class BaseDownloader implements VideoDownloader {
  /// 下载时依次尝试的 UA 列表（优先级从高到低）
  List<String> get downloadUserAgents;

  /// 下载开始前的钩子，用于权限申请等（默认空实现）
  Future<void> beforeDownload() async {}

  /// 下载成功后的钩子，用于 MediaStore 通知等（默认空实现）
  Future<void> afterDownload(String filePath) async {}

  @override
  Future<String> downloadVideo(
    VideoInfo info, {
    VideoQuality? quality,
    String? directory,
    String? filename,
    void Function(int received, int? total)? onProgress,
    void Function(String message)? onLog,
  }) async {
    await beforeDownload();

    final dir = directory?.isNotEmpty == true
        ? directory!
        : await getDefaultDirectory();
    final resolvedQuality = quality ?? VideoQuality.p1080;
    final qualityLabel = resolvedQuality.ratio;

    final prefix = info.shareId ?? info.videoId;
    // 先清理标题，再截断到 30 字符，然后拼前缀
    final cleanTitle = _sanitizeFilename(info.title);
    final baseName = filename != null && filename.isNotEmpty
        ? _sanitizeFilename(filename)
        : '${prefix}_$cleanTitle';
    // 默认不加时间后缀；文件名冲突时才追加时间戳
    final basePath =
        '$dir${Platform.pathSeparator}${baseName}_$qualityLabel.mp4';
    final String filePath;
    if (File(basePath).existsSync()) {
      final now = DateTime.now();
      final stamp =
          '${now.year}${_p2(now.month)}${_p2(now.day)}'
          '_${_p2(now.hour)}${_p2(now.minute)}${_p2(now.second)}';
      filePath =
          '$dir${Platform.pathSeparator}${baseName}_${qualityLabel}_$stamp.mp4';
    } else {
      filePath = basePath;
    }

    final partPath = '$filePath.part';
    final partFile = File(partPath);
    await partFile.parent.create(recursive: true);

    // 预解析 aweme 重定向，获取 line=0 和 line=1 两个直连 CDN 节点
    final awemeUrl = info.urlFor(resolvedQuality);
    onLog?.call('正在解析 CDN 节点…');
    final cdnUrls = await _resolveCdnUrls(awemeUrl, onLog);
    onLog?.call('获得 ${cdnUrls.length} 个 CDN 节点，开始下载');

    const chunkTimeout = Duration(seconds: 30);
    final client = http.Client();
    try {
      for (int lineIdx = 0; lineIdx < cdnUrls.length; lineIdx++) {
        final cdnUrl = cdnUrls[lineIdx];
        if (lineIdx > 0) {
          onLog?.call('切换至备用 CDN 节点 #${lineIdx + 1}…');
          await Future.delayed(const Duration(seconds: 3));
        }

        bool skipToNextCdn = false;

        for (
          int uaIdx = 0;
          !skipToNextCdn && uaIdx < downloadUserAgents.length;
          uaIdx++
        ) {
          if (uaIdx > 0) {
            await Future.delayed(const Duration(seconds: 3));
          }
          final uaShort = downloadUserAgents[uaIdx]
              .split(' ')
              .take(4)
              .join(' ');
          onLog?.call('CDN #${lineIdx + 1} UA #${uaIdx + 1}：$uaShort …');

          final request = http.Request('GET', Uri.parse(cdnUrl));
          request.headers[HttpHeaders.userAgentHeader] =
              downloadUserAgents[uaIdx];
          // 不发送 Referer：douyinvod CDN 对 douyin.com Referer 做防盗链拦截

          final streamed = await client.send(request);
          final statusCode = streamed.statusCode;
          if (statusCode >= 300) {
            onLog?.call('HTTP $statusCode，切换 UA 重试');
            await streamed.stream.drain<void>();
            if (await partFile.exists()) await partFile.delete();
            continue;
          }

          // 逐块写入，支持进度上报
          final total = streamed.contentLength == -1
              ? null
              : streamed.contentLength;
          final totalMb = total != null
              ? '${(total / 1024 / 1024).toStringAsFixed(2)} MB'
              : '未知';
          onLog?.call('HTTP $statusCode，Content-Length: $totalMb，开始写入…');

          final sink = partFile.openWrite();
          int received = 0;
          int lastLoggedPercent = -1;
          bool streamOk = false;

          try {
            await for (final chunk in streamed.stream.timeout(chunkTimeout)) {
              sink.add(chunk);
              received += chunk.length;
              onProgress?.call(received, total);
              if (total != null && total > 0) {
                final pct = (received * 100 ~/ total);
                if (pct >= lastLoggedPercent + 10) {
                  lastLoggedPercent = pct - pct % 10;
                  final recvMb = (received / 1024 / 1024).toStringAsFixed(2);
                  onLog?.call(
                    '下载进度 $lastLoggedPercent%（$recvMb MB / $totalMb）',
                  );
                }
              }
            }
            streamOk = true;
          } on TimeoutException {
            // CDN 节点挂起：换节点比换 UA 更有效
            final recvMb = (received / 1024 / 1024).toStringAsFixed(2);
            onLog?.call('连接超时（已接收 $recvMb MB），切换 CDN 节点');
            skipToNextCdn = true;
          } catch (e) {
            final recvMb = (received / 1024 / 1024).toStringAsFixed(2);
            onLog?.call('流中断（已接收 $recvMb MB）：$e，切换 UA 重试');
          } finally {
            await sink.close();
          }

          if (streamOk) {
            // 下载完成后原子重命名为最终文件名，避免中途断开留下损坏文件
            await partFile.rename(filePath);
            await afterDownload(filePath);
            return filePath;
          }

          // 失败：清理残留 .part 文件
          if (await partFile.exists()) await partFile.delete();
        }
      }
      throw Exception(
        '下载失败，已尝试 ${cdnUrls.length} 个 CDN 节点 × ${downloadUserAgents.length} 个 UA',
      );
    } catch (_) {
      // 异常时清理未完成的 .part 文件
      if (await partFile.exists()) await partFile.delete();
      rethrow;
    } finally {
      client.close();
    }
  }

  /// 预解析 [awemeUrl]（aweme.snssdk.com 重定向器）到直连 CDN URL。
  ///
  /// 分别对 line=0 和 line=1 发不跟重定向的 HEAD-like GET，
  /// 捕获 Location 头得到两个不同的 CDN 节点 URL，供下载循环按序尝试。
  Future<List<String>> _resolveCdnUrls(
    String awemeUrl,
    void Function(String)? onLog,
  ) async {
    final uri = Uri.parse(awemeUrl);
    // 若 URL 含 line= 参数，生成 line=0 和 line=1 两个候选；否则只用原始 URL
    final List<String> candidates;
    if (uri.queryParameters.containsKey('line')) {
      candidates = ['0', '1'].map((l) {
        final params = Map<String, String>.from(uri.queryParameters)
          ..['line'] = l;
        return uri.replace(queryParameters: params).toString();
      }).toList();
    } else {
      candidates = [awemeUrl];
    }

    final resolved = <String>[];
    final ioClient = HttpClient();
    try {
      for (final candidate in candidates) {
        try {
          final req = await ioClient.getUrl(Uri.parse(candidate));
          req.headers.set(HttpHeaders.userAgentHeader, kUaIosDouyin);
          req.followRedirects = false;
          final resp = await req.close();
          await resp.drain<void>();
          if (resp.statusCode >= 300 && resp.statusCode < 400) {
            final loc = resp.headers.value(HttpHeaders.locationHeader);
            if (loc != null) {
              resolved.add(loc);
              final lineParam =
                  Uri.parse(candidate).queryParameters['line'] ?? '?';
              // 显示 scheme://host + path 前段，参数省略（URL 完整但过长）
              final locUri = Uri.parse(loc);
              final locPath = locUri.path.length > 50
                  ? '${locUri.path.substring(0, 50)}…'
                  : locUri.path;
              onLog?.call(
                'CDN 节点 line=$lineParam → ${locUri.scheme}://${locUri.host}$locPath',
              );
              continue;
            }
          }
          // 未重定向（直接 200）：URL 本身就是 CDN 地址
          resolved.add(candidate);
        } catch (e) {
          onLog?.call('CDN 预解析失败（$candidate）：$e');
        }
      }
    } finally {
      ioClient.close();
    }

    if (resolved.isEmpty) {
      // 全部预解析失败，回退到原始 URL（http.Client 会自动跟重定向）
      onLog?.call('CDN 预解析全部失败，使用原始重定向 URL');
      resolved.add(awemeUrl);
    }
    return resolved;
  }

  /// 只保留白名单字符（CJK + ASCII 字母数字 + 常见标点），去除 emoji
  /// 及其他非常用 Unicode，截断到 [maxLen] 字符（默认 30）。
  String _sanitizeFilename(String name, {int maxLen = 30}) {
    // 白名单：CJK 统一汉字 / 扩展 A / CJK 标点 / 全角标点 / ASCII 字母数字与常见标点
    var result = name.replaceAll(
      RegExp(
        r'[^\u4e00-\u9fff' // CJK 统一汉字
        r'\u3400-\u4dbf' // CJK 扩展 A
        r'\u3000-\u303f' // CJK 符号与标点（、。《》【】…）
        r'\uff01-\uffe6' // 全角半角形式（！，。？（）等）
        r'a-zA-Z0-9' // ASCII 字母数字
        r' .,_\-!?()'
        r']',
      ),
      '',
    );
    // 合并多余空白
    result = result.replaceAll(RegExp(r'\s+'), ' ').trim();
    // 截断
    if (result.length > maxLen) result = result.substring(0, maxLen).trim();
    return result.isEmpty ? 'video' : result;
  }

  String _p2(int n) => n.toString().padLeft(2, '0');
}
