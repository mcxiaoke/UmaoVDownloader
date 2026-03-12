/// 探针工具：抓取 iesdouyin 分享页并打印所有 url_list 内容
///
/// 用途：
///   确认页面 HTML 里除 aweme.snssdk.com 重定向器之外是否包含直连 CDN URL
///   以及是否存在 play_addr_4k / play_addr_h265 等高清字段
///
/// 用法：
///   dart run tool/probe_urls.dart <抖音分享链接>
library;

import 'dart:io';

import 'package:dviewer/services/url_extractor.dart';
import 'package:http/http.dart' as http;

// iesdouyin 分享页需要手机 UA
const _mobileUA =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

const _referer = 'https://www.douyin.com/';

// 匹配形如 "play_addr_xxx" : { ... "url_list" : ["url1", "url2", ...] }
// 同时捕获字段名和整个 url_list 数组内容
final _urlListRe = RegExp(
  r'"(play_addr[^"]*?)"\s*:\s*\{[^{}]*"url_list"\s*:\s*\[([^\]]*)\]',
  dotAll: true,
);

// bit_rate 数组：MediaCrawler 发现 Web API 会在 bit_rate[x].play_addr 里
// 放直连 CDN URL，iesdouyin 页面的 render_data 可能也包含相同结构
final _bitRatePlayAddrRe = RegExp(
  r'"bit_rate"\s*:\s*\[(.+?)\]\s*(?:,|\})',
  dotAll: true,
);

// 解析 JSON 字符串转义（\uXXXX, \\, \/, \" 等）
String _unescape(String s) {
  return s
      .replaceAllMapped(
        RegExp(r'\\u([0-9a-fA-F]{4})'),
        (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
      )
      .replaceAll(r'\/', '/')
      .replaceAll(r'\\', r'\')
      .replaceAll(r'\"', '"')
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\r', '')
      .replaceAll(r'\t', '\t');
}

// 从 url_list JSON 片段里提取所有 URL
List<String> _extractUrls(String arrayContent) {
  final urls = <String>[];
  final re = RegExp(r'"((?:[^"\\]|\\.)*)"');
  for (final m in re.allMatches(arrayContent)) {
    final raw = m.group(1)!;
    if (raw.startsWith('http')) {
      urls.add(_unescape(raw));
    }
  }
  return urls;
}

void _printSep() => print('─' * 70);

Future<void> main(List<String> args) async {
  final input = args.isNotEmpty
      ? args.join(' ')
      : () {
          stdout.write('请输入抖音链接或分享文本：');
          return stdin.readLineSync() ?? '';
        }();

  final url = UrlExtractor.extractFirst(input);
  if (url == null) {
    print('未找到有效链接');
    exit(1);
  }

  // ── 短链跳转 ──────────────────────────────────────────────────
  final ioClient = HttpClient();
  var currentUri = Uri.parse(url);
  for (var i = 0; i < 8; i++) {
    final req = await ioClient.getUrl(currentUri);
    req.headers.set(HttpHeaders.userAgentHeader, _mobileUA);
    req.followRedirects = false;
    final resp = await req.close();
    await resp.drain<void>();
    if (resp.statusCode >= 300 && resp.statusCode < 400) {
      final loc = resp.headers.value(HttpHeaders.locationHeader);
      if (loc == null) break;
      currentUri = currentUri.resolve(loc);
    } else {
      break;
    }
  }
  ioClient.close();

  final videoId = RegExp(
    r'/(?:video|note)/(\d+)',
  ).firstMatch(currentUri.toString())?.group(1);
  if (videoId == null) {
    print('无法提取视频 ID，最终 URL: $currentUri');
    exit(1);
  }
  print('视频 ID: $videoId');

  // ── 抓取分享页 ──────────────────────────────────────────────
  print('正在抓取分享页…');
  final shareUrl = Uri.parse('https://www.iesdouyin.com/share/video/$videoId/');
  final resp = await http.get(
    shareUrl,
    headers: {HttpHeaders.userAgentHeader: _mobileUA, 'Referer': _referer},
  );
  if (resp.statusCode != 200) {
    print('分享页请求失败：${resp.statusCode}');
    exit(1);
  }
  final html = resp.body;
  print('页面长度：${html.length} 字符');
  _printSep();

  // ── 打印所有 url_list 字段 ──────────────────────────────────
  final matches = _urlListRe.allMatches(html).toList();
  if (matches.isEmpty) {
    print('未找到任何 url_list 字段');
    exit(0);
  }

  print('共找到 ${matches.length} 个 url_list 字段：\n');
  for (final m in matches) {
    final fieldName = m.group(1)!;
    final arrayContent = m.group(2)!;
    final urls = _extractUrls(arrayContent);
    print('  字段: $fieldName  (${urls.length} 个 URL)');
    for (int i = 0; i < urls.length; i++) {
      final u = urls[i];
      // 分类标注
      String tag;
      if (u.contains('aweme.snssdk.com')) {
        tag = '[重定向器]';
      } else if (u.contains('365yg.com') ||
          u.contains('douyinvod.com') ||
          u.contains('bytecdn.cn')) {
        tag = '[直连CDN]';
      } else {
        tag = '[其他]';
      }
      print('    [$i] $tag');
      print('        ${u.length > 120 ? "${u.substring(0, 120)}…" : u}');
    }
    _printSep();
  }

  // ── 搜索 bit_rate 数组里的嵌套 play_addr ─────────────────────
  // MediaCrawler 从 Web API 的 bit_rate[x].play_addr.url_list 取直连 CDN URL
  // 如果 iesdouyin 页面也包含此结构，可直接用，无需经过 aweme.snssdk.com 重定向
  _printSep();
  print('── bit_rate 嵌套 play_addr 探测 ──');
  final bitRateMatch = _bitRatePlayAddrRe.firstMatch(html);
  if (bitRateMatch == null) {
    print('  未找到 bit_rate 数组（iesdouyin 页面未包含此字段）');
  } else {
    final bitRateContent = bitRateMatch.group(1)!;
    // 在 bit_rate 块内搜 url_list
    final nestedUrls = _urlListRe.allMatches(bitRateContent).toList();
    if (nestedUrls.isEmpty) {
      print('  bit_rate 数组存在但内部没有 url_list 字段');
    } else {
      print('  ✅ bit_rate 内发现 ${nestedUrls.length} 个 url_list（可直接作为 CDN URL）：');
      for (final m in nestedUrls) {
        final fieldName = m.group(1)!;
        final urls = _extractUrls(m.group(2)!);
        print('    字段: $fieldName  (${urls.length} 个 URL)');
        for (int i = 0; i < urls.length; i++) {
          final u = urls[i];
          String tag;
          if (u.contains('aweme.snssdk.com')) {
            tag = '[重定向器]';
          } else if (u.contains('douyinvod.com') ||
              u.contains('365yg.com') ||
              u.contains('bytecdn.cn')) {
            tag = '[直连CDN ✅]';
          } else {
            tag = '[其他]';
          }
          print(
            '      [$i] $tag  ${u.length > 110 ? "${u.substring(0, 110)}…" : u}',
          );
        }
      }
    }
  }
  _printSep();

  // ── 搜索 4K 相关字段名 ─────────────────────────────────────
  final qualityFields = RegExp(
    r'"(play_addr_4k|play_addr_h265|play_addr_hdr|bitrateInfo|urlList|url_list_hdr)",',
  ).allMatches(html).map((m) => m.group(1)!).toSet();
  if (qualityFields.isNotEmpty) {
    print('⚠️  发现高清相关字段名：${qualityFields.join(", ")}');
  } else {
    print('未发现 4K/HDR/H265 专用字段（当前数据源限制）');
  }
}
