import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../utils/filename_utils.dart';
import '../parser_common.dart';
import 'video_downloader.dart';
import '../../constants/app_constants.dart';

/// 公共 UA 常量（供所有平台下载器引用）



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

  /// 获取音乐保存目录（子类可覆写）
  /// Android 返回 Music/umaovd，其他平台返回默认目录
  Future<String> getMusicDirectory() async {
    return await getDefaultDirectory();
  }

  @override
  Future<String> downloadVideo(
    VideoInfo info, {
    String? directory,
    String? filename,
    bool downloadMusic = false,
    void Function(int received, int? total)? onProgress,
    void Function(String message)? onLog,
  }) async {
    await beforeDownload();

    final dir = directory?.isNotEmpty == true
        ? directory!
        : await getDefaultDirectory();

    final prefix = info.shareId ?? info.itemId;
    final cleanTitle = sanitizeFilename(info.title);
    final platformPrefix = info.platform.filePrefix;
    // 添加日期后缀（格式：20260317）
    final now = DateTime.now();
    final dateSuffix = '${now.year}${_p2(now.month)}${_p2(now.day)}';
    final baseName = filename != null && filename.isNotEmpty
        ? sanitizeFilename(filename)
        : '$platformPrefix${prefix}_${cleanTitle}_$dateSuffix';

    // ── 图文作品：批量下载图片 ──────────────────────────────────
    if (info.mediaType == MediaType.image) {
      return await _downloadImages(info, dir, baseName, onProgress, onLog);
    }

    // ── 实况图：默认批量下载图片（动图视频只能单独下载）──────────────
    // 原因：实况图可能包含混合的静态图+动图，livePhotoUrls 中会有空字符串
    if (info.mediaType == MediaType.livePhoto) {
      return await _downloadImages(info, dir, baseName, onProgress, onLog);
    }

    // ── 视频作品 ─────────────────────────────────────────────
    // 默认不加时间后缀；文件名冲突时才追加时间戳
    final basePath = '$dir${Platform.pathSeparator}${baseName}_video.mp4';
    final String filePath;
    if (File(basePath).existsSync()) {
      final now = DateTime.now();
      final stamp =
          '${now.year}${_p2(now.month)}${_p2(now.day)}'
          '_${_p2(now.hour)}${_p2(now.minute)}${_p2(now.second)}';
      filePath = '$dir${Platform.pathSeparator}${baseName}_video_$stamp.mp4';
    } else {
      filePath = basePath;
    }

    final partPath = '$filePath.part';
    final partFile = File(partPath);
    await partFile.parent.create(recursive: true);

    // 优先尝试无水印 URL，失败时回退到有水印 URL
    final urlsToTry = <String>[];
    if (info.videoUrlNoWatermark != null &&
        info.videoUrlNoWatermark!.isNotEmpty) {
      urlsToTry.add(info.videoUrlNoWatermark!);
      onLog?.call('将优先尝试无水印 URL');
    }
    urlsToTry.add(info.videoUrl);

    // 尝试下载（优先无水印，失败回退）
    for (int urlIdx = 0; urlIdx < urlsToTry.length; urlIdx++) {
      final currentUrl = urlsToTry[urlIdx];
      final isNoWatermark = urlIdx == 0 && urlsToTry.length > 1;

      if (urlIdx > 0) {
        onLog?.call('无水印 URL 下载失败，回退到有水印 URL...');
        // 清理之前的残留文件
        if (await partFile.exists()) await partFile.delete();
      }

      onLog?.call(isNoWatermark ? '正在使用无水印 URL 解析 CDN 节点…' : '正在解析 CDN 节点…');
      final cdnUrls = await _resolveCdnUrls(currentUrl, onLog);
      onLog?.call('获得 ${cdnUrls.length} 个 CDN 节点，开始下载');

      final success = await _downloadWithCdnAndUa(
        cdnUrls,
        partFile,
        filePath,
        onProgress,
        onLog,
      );

      if (success) {
        return filePath;
      }

      // 如果这是最后一个 URL，抛出异常
      if (urlIdx == urlsToTry.length - 1) {
        throw Exception(
          '下载失败，已尝试 ${urlsToTry.length} 个 URL × ${cdnUrls.length} 个 CDN 节点 × ${downloadUserAgents.length} 个 UA',
        );
      }
    }

    // 理论上不会执行到这里
    throw Exception('下载失败：所有 URL 均不可用');
  }

  /// 使用 CDN 和 UA 循环下载视频
  /// 返回是否下载成功
  Future<bool> _downloadWithCdnAndUa(
    List<String> cdnUrls,
    File partFile,
    String filePath,
    void Function(int received, int? total)? onProgress,
    void Function(String message)? onLog,
  ) async {
    const chunkTimeout = kDownloadChunkTimeout;
    const speedCheckInterval = Duration(seconds: 15);
    const minSpeedBytesPerSec = 200 * 1024; // 200 KB/s

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

          // Content-Length < 10 KB 一定是错误响应（如解析出音乐 URL 被当成视频地址）
          // 换 UA / 换 CDN 均无效，直接抛异常告知用户
          if (total != null && total < kMinVideoFileSizeBytes) {
            await streamed.stream.drain<void>();
            if (await partFile.exists()) await partFile.delete();
            throw Exception('Content-Length 异常（$total 字节），视频地址可能解析有误，请重新解析后再试');
          }

          final totalMb = total != null
              ? '${(total / 1024 / 1024).toStringAsFixed(2)} MB'
              : '未知';
          onLog?.call('HTTP $statusCode，Content-Length: $totalMb，开始写入…');

          final sink = partFile.openWrite();
          int received = 0;
          bool streamOk = false;
          
          // 速度检测相关变量
          final downloadStart = DateTime.now();
          DateTime lastSpeedCheck = downloadStart;
          int receivedAtLastCheck = 0;

          try {
            await for (final chunk in streamed.stream.timeout(chunkTimeout)) {
              sink.add(chunk);
              received += chunk.length;
              onProgress?.call(received, total);

              // 速度检测：每15秒检查一次
              final now = DateTime.now();
              if (now.difference(lastSpeedCheck) >= speedCheckInterval) {
                final elapsed = now.difference(lastSpeedCheck).inMilliseconds;
                final bytesReceived = received - receivedAtLastCheck;
                final speed = elapsed > 0 ? (bytesReceived * 1000 / elapsed) : 0.0;
                final speedKb = (speed / 1024).toStringAsFixed(1);

                onLog?.call('下载速度: ${speedKb}KB/s（已接收 ${(received / 1024 / 1024).toStringAsFixed(2)} MB）');

                // 如果速度低于 200KB/s，切换 CDN
                if (speed < minSpeedBytesPerSec) {
                  onLog?.call('速度过慢（${speedKb}KB/s < 200KB/s），切换 CDN 节点');
                  skipToNextCdn = true;
                  break;
                }

                lastSpeedCheck = now;
                receivedAtLastCheck = received;
              }
            }
            streamOk = !skipToNextCdn;
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
            return true;
          }

          // 失败：清理残留 .part 文件
          if (await partFile.exists()) await partFile.delete();
        }
      }
      // 所有 CDN 和 UA 都失败了
      return false;
    } catch (_) {
      // 异常时清理未完成的 .part 文件
      if (await partFile.exists()) await partFile.delete();
      return false;
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
              onLog?.call('已获取 CDN 节点 #$lineParam');
              continue;
            }
          }
          // 未重定向（直接 200）：URL 本身就是 CDN 地址
          resolved.add(candidate);
        } catch (e) {
          onLog?.call('CDN 预解析失败: $e');
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

  /// 图文作品：按序下载每张图片，保存为 {baseName}_001.webp / _002.webp … (扩展名由 URL 决定)
  /// 返回第一张图片的完整路径（方便 UI 显示结果）
  Future<String> _downloadImages(
    VideoInfo info,
    String dir,
    String baseName,
    void Function(int received, int? total)? onProgress,
    void Function(String message)? onLog,
  ) async {
    final total = info.imageUrls.length;
    onLog?.call('图文作品，共 $total 张图片，开始下载…');

    String firstPath = '';
    final client = http.Client();
    try {
      for (int i = 0; i < total; i++) {
        final url = info.imageUrls[i];
        final idx = _p3(i + 1);
        final ext = _imageExtension(url);
        final basePath = '$dir${Platform.pathSeparator}${baseName}_$idx$ext';
        final String imgPath;
        if (File(basePath).existsSync()) {
          final now = DateTime.now();
          final stamp =
              '${now.year}${_p2(now.month)}${_p2(now.day)}'
              '_${_p2(now.hour)}${_p2(now.minute)}${_p2(now.second)}';
          imgPath =
              '$dir${Platform.pathSeparator}${baseName}_${idx}_$stamp$ext';
        } else {
          imgPath = basePath;
        }

        final partFile = File('$imgPath.part');
        await partFile.parent.create(recursive: true);

        bool saved = false;
        for (final ua in downloadUserAgents) {
          final req = http.Request('GET', Uri.parse(url));
          req.headers[HttpHeaders.userAgentHeader] = ua;
          final streamed = await client.send(req);
          if (streamed.statusCode >= 300) {
            await streamed.stream.drain<void>();
            continue;
          }
          final sink = partFile.openWrite();
          try {
            await for (final chunk in streamed.stream.timeout(
              const Duration(seconds: 30),
            )) {
              sink.add(chunk);
            }
            saved = true;
          } on TimeoutException {
            // 超时：换 UA 重试
          } catch (_) {
            // 其他流错误：换 UA
          } finally {
            await sink.close();
          }
          if (saved) break;
          // 此 UA 下载失败，清理残留并换下一个 UA
          if (await partFile.exists()) await partFile.delete();
        }

        if (!saved) {
          if (await partFile.exists()) await partFile.delete();
          onLog?.call('图片 ${i + 1} 下载失败，跳过');
          continue;
        }

        await partFile.rename(imgPath);
        await afterDownload(imgPath);
        onProgress?.call(i + 1, total);
        if (i == 0) firstPath = imgPath;
      }
    } finally {
      client.close();
    }

    if (firstPath.isEmpty) throw Exception('所有图片下载失败');
    return firstPath;
  }

  /// 下载单个图片
  /// 用于 UI 中单独下载某一张图片
  @override
  Future<String> downloadSingleImage(
    String url, {
    required String directory,
    required String filename,
    void Function(int received, int? total)? onProgress,
    void Function(String message)? onLog,
  }) async {
    final dir = directory;
    final ext = _imageExtension(url);
    final basePath = '$dir${Platform.pathSeparator}$filename$ext';
    final String filePath;
    if (File(basePath).existsSync()) {
      final now = DateTime.now();
      final stamp =
          '${now.year}${_p2(now.month)}${_p2(now.day)}'
          '_${_p2(now.hour)}${_p2(now.minute)}${_p2(now.second)}';
      filePath = '$dir${Platform.pathSeparator}${filename}_$stamp$ext';
    } else {
      filePath = basePath;
    }

    onLog?.call('下载单个图片 $url');

    final partFile = File('$filePath.part');
    await partFile.parent.create(recursive: true);

    final client = http.Client();
    try {
      bool saved = false;
      for (final ua in downloadUserAgents) {
        final req = http.Request('GET', Uri.parse(url));
        req.headers[HttpHeaders.userAgentHeader] = ua;
        // 小红书图片CDN需要Referer
        if (url.contains('xhscdn.com')) {
          req.headers[HttpHeaders.refererHeader] =
              'https://www.xiaohongshu.com/';
        }
        final streamed = await client.send(req);
        if (streamed.statusCode >= 300) {
          await streamed.stream.drain<void>();
          continue;
        }
        final total = streamed.contentLength == -1
            ? null
            : streamed.contentLength;
        final sink = partFile.openWrite();
        int received = 0;
        try {
          await for (final chunk in streamed.stream.timeout(
            const Duration(seconds: 30),
          )) {
            sink.add(chunk);
            received += chunk.length;
            onProgress?.call(received, total);
          }
          saved = true;
        } on TimeoutException {
          // 超时：换 UA 重试
        } catch (_) {
          // 其他流错误：换 UA
        } finally {
          await sink.close();
        }
        if (saved) break;
        if (await partFile.exists()) await partFile.delete();
      }

      if (!saved) {
        if (await partFile.exists()) await partFile.delete();
        throw Exception('图片下载失败: $url');
      }

      await partFile.rename(filePath);
      await afterDownload(filePath);
      return filePath;
    } finally {
      client.close();
    }
  }

  /// 下载单个 Live Photo 视频
  /// 用于 UI 中单独下载某一个实况图视频
  @override
  Future<String> downloadSingleLivePhoto(
    String url, {
    required String directory,
    required String filename,
    void Function(int received, int? total)? onProgress,
    void Function(String message)? onLog,
  }) async {
    final dir = directory;
    final basePath = '$dir${Platform.pathSeparator}$filename.mp4';
    final String filePath;
    if (File(basePath).existsSync()) {
      final now = DateTime.now();
      final stamp =
          '${now.year}${_p2(now.month)}${_p2(now.day)}'
          '_${_p2(now.hour)}${_p2(now.minute)}${_p2(now.second)}';
      filePath = '$dir${Platform.pathSeparator}${filename}_$stamp.mp4';
    } else {
      filePath = basePath;
    }

    onLog?.call('下载单个实况 $url');

    final partFile = File('$filePath.part');
    await partFile.parent.create(recursive: true);

    final client = http.Client();
    try {
      bool saved = false;
      for (final ua in downloadUserAgents) {
        final req = http.Request('GET', Uri.parse(url));
        req.headers[HttpHeaders.userAgentHeader] = ua;
        // 小红书图片CDN需要Referer
        if (url.contains('xhscdn.com')) {
          req.headers[HttpHeaders.refererHeader] =
              'https://www.xiaohongshu.com/';
        }
        final streamed = await client.send(req);
        if (streamed.statusCode >= 300) {
          await streamed.stream.drain<void>();
          continue;
        }
        final total = streamed.contentLength == -1
            ? null
            : streamed.contentLength;
        final sink = partFile.openWrite();
        int received = 0;
        try {
          await for (final chunk in streamed.stream.timeout(
            const Duration(seconds: 30),
          )) {
            sink.add(chunk);
            received += chunk.length;
            onProgress?.call(received, total);
          }
          saved = true;
        } on TimeoutException {
          // 超时：换 UA 重试
        } catch (_) {
          // 其他流错误：换 UA
        } finally {
          await sink.close();
        }
        if (saved) break;
        if (await partFile.exists()) await partFile.delete();
      }

      if (!saved) {
        if (await partFile.exists()) await partFile.delete();
        throw Exception('实况视频下载失败: $url');
      }

      await partFile.rename(filePath);
      await afterDownload(filePath);
      return filePath;
    } finally {
      client.close();
    }
  }

  /// 实况图：按序下载每个视频，  /// 注意：目前已改为默认下载图片，此方法仅用于单独下载动图视频
  /// 保存为 {baseName}_001.mp4 / _002.mp4 …
  /// 返回第一个视频的完整路径（方便 UI 显示结果）
  /// 批量下载实况图的视频
  /// 返回第一个成功下载的视频路径
  Future<String> downloadLivePhotos(
    VideoInfo info, {
    String? directory,
    void Function(int received, int? total)? onProgress,
    void Function(String message)? onLog,
  }) async {
    await beforeDownload();
    final dir = directory?.isNotEmpty == true
        ? directory!
        : await getDefaultDirectory();
    final prefix = info.shareId ?? info.itemId;
    final cleanTitle = sanitizeFilename(info.title);
    final platformPrefix = info.platform.filePrefix;
    // 添加日期后缀
    final now = DateTime.now();
    final dateSuffix = '${now.year}${_p2(now.month)}${_p2(now.day)}';
    final baseName = '$platformPrefix${prefix}_${cleanTitle}_$dateSuffix';
    return await _downloadLivePhotos(info, dir, baseName, onProgress, onLog);
  }

  Future<String> _downloadLivePhotos(
    VideoInfo info,
    String dir,
    String baseName,
    void Function(int received, int? total)? onProgress,
    void Function(String message)? onLog,
  ) async {
    // 过滤掉空 URL，只下载有效的动图视频
    final validUrls = <String>[];
    final urlIndexMap = <int, int>{}; // 原始索引 -> 有效索引
    for (int i = 0; i < info.livePhotoUrls.length; i++) {
      final url = info.livePhotoUrls[i];
      if (url.isNotEmpty) {
        urlIndexMap[validUrls.length] = i;
        validUrls.add(url);
      }
    }

    if (validUrls.isEmpty) {
      onLog?.call('没有有效的动图视频可下载');
      return '';
    }

    final total = validUrls.length;
    onLog?.call('实况图作品，共 $total 个视频，开始下载…');

    String firstPath = '';
    int successCount = 0;
    final client = http.Client();
    try {
      for (int i = 0; i < total; i++) {
        final url = validUrls[i];
        final originalIndex = urlIndexMap[i]!;
        final idx = _p3(originalIndex + 1);
        final basePath = '$dir${Platform.pathSeparator}${baseName}_$idx.mp4';
        final String videoPath;
        if (File(basePath).existsSync()) {
          final now = DateTime.now();
          final stamp =
              '${now.year}${_p2(now.month)}${_p2(now.day)}'
              '_${_p2(now.hour)}${_p2(now.minute)}${_p2(now.second)}';
          videoPath =
              '$dir${Platform.pathSeparator}${baseName}_${idx}_$stamp.mp4';
        } else {
          videoPath = basePath;
        }

        final partFile = File('$videoPath.part');
        await partFile.parent.create(recursive: true);

        bool saved = false;
        for (final ua in downloadUserAgents) {
          final req = http.Request('GET', Uri.parse(url));
          req.headers[HttpHeaders.userAgentHeader] = ua;
          final streamed = await client.send(req);
          if (streamed.statusCode >= 300) {
            await streamed.stream.drain<void>();
            continue;
          }
          final sink = partFile.openWrite();
          try {
            await for (final chunk in streamed.stream.timeout(
              const Duration(seconds: 30),
            )) {
              sink.add(chunk);
            }
            saved = true;
          } on TimeoutException {
            // 超时：换 UA 重试
          } catch (_) {
            // 其他流错误：换 UA
          } finally {
            await sink.close();
          }
          if (saved) break;
          // 此 UA 下载失败，清理残留并换下一个 UA
          if (await partFile.exists()) await partFile.delete();
        }

        if (!saved) {
          if (await partFile.exists()) await partFile.delete();
          onLog?.call('实况视频 ${originalIndex + 1} 下载失败，跳过');
          continue;
        }

        await partFile.rename(videoPath);
        await afterDownload(videoPath);
        successCount++;
        onProgress?.call(successCount, total);
        if (successCount == 1) firstPath = videoPath;
      }
    } finally {
      client.close();
    }

    if (firstPath.isEmpty) {
      return '';
    }
    return firstPath;
  }

  String _p2(int n) => n.toString().padLeft(2, '0');
  String _p3(int n) => n.toString().padLeft(3, '0');

  /// 从图片 URL 路径部分（? 号前）提取文件后缀，未识别时回退 .jpg
  String _imageExtension(String url) {
    final path = url.split('?').first.toLowerCase();
    if (path.endsWith('.webp')) return '.webp';
    if (path.endsWith('.png')) return '.png';
    if (path.endsWith('.gif')) return '.gif';
    if (path.endsWith('.jpeg')) return '.jpeg';
    return '.jpg';
  }

  /// 单独下载背景音乐
  /// Android 固定保存到 Music/umaovd，其他平台使用指定目录
  @override
  Future<String?> downloadMusicFile(
    String url, {
    String? directory,
    required String filename,
    void Function(int received, int? total)? onProgress,
    void Function(String message)? onLog,
  }) async {
    await beforeDownload();

    // 使用音乐专用目录
    final dir = await getMusicDirectory();
    final baseName = sanitizeFilename(filename);
    final basePath = '$dir${Platform.pathSeparator}$baseName.mp3';
    final String filePath;
    if (File(basePath).existsSync()) {
      final now = DateTime.now();
      final stamp =
          '${now.year}${_p2(now.month)}${_p2(now.day)}'
          '_${_p2(now.hour)}${_p2(now.minute)}${_p2(now.second)}';
      filePath = '$dir${Platform.pathSeparator}${baseName}_$stamp.mp3';
    } else {
      filePath = basePath;
    }

    onLog?.call('开始下载背景音乐…');

    final partFile = File('$filePath.part');
    await partFile.parent.create(recursive: true);

    final client = http.Client();
    bool saved = false;
    try {
      for (final ua in downloadUserAgents) {
        final req = http.Request('GET', Uri.parse(url));
        req.headers[HttpHeaders.userAgentHeader] = ua;
        final streamed = await client.send(req);
        if (streamed.statusCode >= 300) {
          await streamed.stream.drain<void>();
          continue;
        }
        final total = streamed.contentLength == -1
            ? null
            : streamed.contentLength;
        final sink = partFile.openWrite();
        int received = 0;
        try {
          await for (final chunk in streamed.stream.timeout(
            const Duration(seconds: 30),
          )) {
            sink.add(chunk);
            received += chunk.length;
            onProgress?.call(received, total);
          }
          saved = true;
        } on TimeoutException {
          // 超时换 UA
        } catch (_) {
          // 其他错误换 UA
        } finally {
          await sink.close();
        }
        if (saved) break;
        if (await partFile.exists()) await partFile.delete();
      }

      if (!saved) {
        if (await partFile.exists()) await partFile.delete();
        onLog?.call('背景音乐下载失败');
        return null;
      }

      await partFile.rename(filePath);
      await afterDownload(filePath);
      return filePath;
    } finally {
      client.close();
    }
  }
}
