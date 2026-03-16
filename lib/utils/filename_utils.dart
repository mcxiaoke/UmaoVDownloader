// 文件名工具函数

/// 清理文件名：只保留安全字符，移除所有特殊字符
/// 避免在不同操作系统和文件系统上出现兼容性问题
String sanitizeFilename(String name, {int maxLen = 30}) {
  // 只保留：中文汉字、字母、数字、下划线、横杠
  var result = name.replaceAll(
    RegExp(
      r'[^\u4e00-\u9fff' // CJK 统一汉字
      r'\u3400-\u4dbf' // CJK 扩展 A
      r'a-zA-Z0-9' // ASCII 字母数字
      r'_\-]' // 下划线、横杠
    ),
    '',
  );
  if (result.length > maxLen) result = result.substring(0, maxLen);
  return result.isEmpty ? 'file' : result;
}

/// 格式化文件大小
String formatFileSize(int? bytes) {
  if (bytes == null) return 'unknown';
  final mb = bytes / (1024 * 1024);
  if (mb >= 1) return '${mb.toStringAsFixed(2)} MB';
  return '${(bytes / 1024).toStringAsFixed(1)} KB';
}
