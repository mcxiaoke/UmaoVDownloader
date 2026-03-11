/// 从任意文本中提取 HTTP/HTTPS 链接
///
/// 用于处理抖音分享内容，例如：
/// "复制这段内容后打开抖音，看看【xxx】的作品 https://v.douyin.com/xxxxxxxx/ 复制此链接..."
class UrlExtractor {
  // 匹配 HTTP/HTTPS URL，遇到空白或常见中文标点停止
  static final _urlRegex = RegExp(
    r'https?://[^\s，。！？、；：""'
    '【】《》（）…—]+',
    caseSensitive: false,
  );

  // 末尾可能粘连的西文标点
  static final _trailingPunct = RegExp(r'[.,;:!?)]+$');

  /// 提取文本中所有链接
  static List<String> extractAll(String text) {
    return _urlRegex.allMatches(text).map((m) => _clean(m.group(0)!)).toList();
  }

  /// 提取文本中第一个链接，未找到返回 null
  static String? extractFirst(String text) {
    final match = _urlRegex.firstMatch(text);
    if (match == null) return null;
    return _clean(match.group(0)!);
  }

  static String _clean(String url) => url.replaceAll(_trailingPunct, '').trim();
}
