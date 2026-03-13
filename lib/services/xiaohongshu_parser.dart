import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'douyin_parser.dart';

/// 小红书解析器（当前仅支持 WebView 注入解析）
/// 后端解析暂未实现，预留接口供后续扩展
class XiaohongshuParser {
  static const _timeout = Duration(seconds: 15);
  static const _mobileUserAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1';

  final _client = http.Client();

  /// 解析小红书分享链接
  /// 当前仅返回错误，提醒使用 WebView 解析
  Future<VideoInfo> parse(String input) async {
    // 小红书需要 WebView 执行 JS 提取 window.__INITIAL_STATE__
    // 纯 Dart 解析需要模拟完整浏览器环境，目前不实现
    throw Exception('小红书请使用 WebView 解析模式');
  }

  void dispose() {
    _client.close();
  }
}
