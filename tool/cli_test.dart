/// CLI 测试入口
///
/// 用法：
///   dart run tool/cli_test.dart <抖音分享文本或链接>
///   dart run tool/cli_test.dart          # 交互式输入
///
/// 示例：
///   dart run tool/cli_test.dart "4.88 复制这段内容... https://v.douyin.com/xxxxxxxx/"
library;

import 'dart:io';

import 'package:dviewer/services/douyin_parser.dart';
import 'package:dviewer/services/downloader/desktop_downloader.dart';
import 'package:dviewer/services/url_extractor.dart';

Future<void> main(List<String> args) async {
  // ── 1. 获取输入 ──────────────────────────────────────────────
  String input;
  if (args.isNotEmpty) {
    input = args.join(' ');
  } else {
    stdout.write('请输入抖音分享内容或链接: ');
    input = stdin.readLineSync() ?? '';
  }

  if (input.trim().isEmpty) {
    stderr.writeln('错误: 输入不能为空');
    exit(1);
  }

  // ── 2. 提取链接 ───────────────────────────────────────────────
  final url = UrlExtractor.extractFirst(input);
  if (url == null) {
    stderr.writeln('错误: 未找到有效的 HTTP/HTTPS 链接');
    exit(1);
  }
  print('提取链接: $url');

  // ── 3. 解析视频信息 ───────────────────────────────────────────
  final parser = DouyinParser();
  VideoInfo? info;
  try {
    print('正在解析视频信息...');
    info = await parser.parse(url);
  } on DouyinParseException catch (e) {
    stderr.writeln('解析失败: $e');
    exit(1);
  } catch (e) {
    stderr.writeln('未知错误: $e');
    exit(1);
  } finally {
    parser.dispose();
  }

  _printSeparator();
  print('视频ID   : ${info.videoId}');
  print('标题     : ${info.title}');
  print('视频地址 : ${info.videoUrl}');
  print('封面地址 : ${info.coverUrl ?? "无"}');
  _printSeparator();

  // ── 4. 询问是否下载 ───────────────────────────────────────────
  stdout.write('是否下载视频？[y/N] ');
  final answer = stdin.readLineSync()?.trim().toLowerCase() ?? '';
  if (answer != 'y' && answer != 'yes') {
    print('已取消下载');
    return;
  }

  // ── 5. 执行下载 ───────────────────────────────────────────────
  final downloader = DesktopDownloader();
  final defaultDir = await downloader.getDefaultDirectory();
  print('保存目录: $defaultDir');
  print('正在下载...');

  try {
    final savePath = await downloader.downloadVideo(info);
    print('下载完成: $savePath');
  } catch (e) {
    stderr.writeln('下载失败: $e');
    exit(1);
  }
}

void _printSeparator() => print('─' * 50);
