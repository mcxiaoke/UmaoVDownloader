import 'dart:io';
import 'dart:convert';

// 使用标准库,不依赖任何 Flutter 包
const ua =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

Future<void> main() async {
  // ── 1. 跟随重定向 ──────────────────────────────────────────────
  final shortUrl = 'https://v.douyin.com/dSw-yoH9MhI/';
  var currentUri = Uri.parse(shortUrl);
  final ioClient = HttpClient();
  String finalUrl = shortUrl;

  for (var i = 0; i < 8; i++) {
    final req = await ioClient.getUrl(currentUri);
    req.headers.set(HttpHeaders.userAgentHeader, ua);
    req.followRedirects = false;
    final resp = await req.close();
    await resp.drain<void>();

    print('[$i] ${resp.statusCode}  $currentUri');
    if (resp.statusCode >= 300 && resp.statusCode < 400) {
      final loc = resp.headers.value(HttpHeaders.locationHeader);
      print('     → $loc');
      if (loc == null) break;
      currentUri = currentUri.resolve(loc);
      finalUrl = currentUri.toString();
    } else {
      finalUrl = currentUri.toString();
      break;
    }
  }
  ioClient.close();
  print('\n最终 URL: $finalUrl');

  // ── 2. 提取 videoId ─────────────────────────────────────────────
  final matchVideo = RegExp(r'/video/(\d+)').firstMatch(finalUrl);
  final matchNote = RegExp(r'/note/(\d+)').firstMatch(finalUrl);
  final videoId = matchVideo?.group(1) ?? matchNote?.group(1);
  print('videoId: $videoId');
  if (videoId == null) {
    print('无法提取 videoId，终止');
    return;
  }

  // ── 3. 调用 iesdouyin API ────────────────────────────────────────
  final apiUrl =
      'https://www.iesdouyin.com/web/api/v2/aweme/iteminfo/?item_ids=$videoId';
  print('\n调用 API: $apiUrl');

  final apiClient = HttpClient();
  final apiReq = await apiClient.getUrl(Uri.parse(apiUrl));
  apiReq.headers.set(HttpHeaders.userAgentHeader, ua);
  apiReq.headers.set('Referer', 'https://www.douyin.com/');
  final apiResp = await apiReq.close();
  final apiBody = await apiResp.transform(utf8.decoder).join();
  apiClient.close();

  print('API 状态码: ${apiResp.statusCode}');
  print(
    'API 响应体(前 500 字符): ${apiBody.substring(0, apiBody.length.clamp(0, 500))}',
  );

  // ── 4. 解析分享页面 HTML 中的内嵌 JSON ─────────────────────────
  print('\n--- 解析分享页 HTML ---');
  final shareUrl = 'https://www.iesdouyin.com/share/video/$videoId/';
  print('请求: $shareUrl');
  final c2 = HttpClient();
  final r2 = await c2.getUrl(Uri.parse(shareUrl));
  r2.headers.set(HttpHeaders.userAgentHeader, ua);
  r2.headers.set('Referer', 'https://www.douyin.com/');
  final resp2 = await r2.close();
  final body2 = await resp2.transform(utf8.decoder).join();
  c2.close();
  print('状态码: ${resp2.statusCode}, body 长度: ${body2.length}');

  // 1) __NEXT_DATA__
  final nextData = RegExp(
    r'<script id="__NEXT_DATA__"[^>]*>([\s\S]*?)</script>',
  ).firstMatch(body2)?.group(1);
  if (nextData != null) {
    print('找到 __NEXT_DATA__ (${nextData.length} 字符):');
    print(nextData.substring(0, nextData.length.clamp(0, 600)));
  }

  // 2) RENDER_DATA (URL-encoded JSON embedded in <script>)
  final renderData = RegExp(
    r'self\.__RENDER_DATA__\s*=\s*decodeURIComponent\("([^"]+)"\)',
  ).firstMatch(body2)?.group(1);
  if (renderData != null) {
    final decoded = Uri.decodeFull(renderData);
    print('\n找到 RENDER_DATA (${decoded.length} 字符):');
    print(decoded.substring(0, decoded.length.clamp(0, 600)));
  }

  // 3) 直接搜索 douyinvod CDN 视频 URL
  final cdnUrls = RegExp(
    "https?://[a-z0-9\\-]+\\.douyinvod\\.com/[^\"'> \\s]+",
  ).allMatches(body2).map((m) => m.group(0)!).toSet();
  if (cdnUrls.isNotEmpty) {
    print('\n找到视频 CDN 地址:');
    for (final u in cdnUrls.take(3)) print('  $u');
  } else {
    print('\n未找到 douyinvod CDN 地址');
  }

  // 4) 搜索 play_addr 附近内容
  final playAddrIdx = body2.indexOf('play_addr');
  if (playAddrIdx >= 0) {
    print('\nbody 中找到 play_addr，上下文:');
    final start = (playAddrIdx - 50).clamp(0, body2.length);
    final end = (playAddrIdx + 300).clamp(0, body2.length);
    print(body2.substring(start, end));
  } else {
    print('\nbody 中无 play_addr 字段');
  }

  // 5) 打印所有 <script src> 外链以便后续分析
  final scriptSrcs = RegExp(r'<script[^>]+src="([^"]+)"')
      .allMatches(body2)
      .map((m) => m.group(1)!)
      .where((s) => !s.contains('analytics') && !s.contains('monitor'))
      .toList();
  print('\nscript 外链 (前10个):');
  for (final s in scriptSrcs.take(10)) print('  $s');
}
