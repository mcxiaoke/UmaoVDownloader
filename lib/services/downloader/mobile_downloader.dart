import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'base_downloader.dart';

/// 用户永久拒绝存储权限时抛出此异常（仅 Android 9 及以下可能触发）
class StoragePermissionDeniedException implements Exception {
  const StoragePermissionDeniedException();

  @override
  String toString() => '存储权限被永久拒绝，请在系统设置中手动开启';
}

/// Android / iOS 移动端下载器
///
/// 采用流式下载避免大文件占用过多内存。
/// Android 10+ 访问 App 私有外部目录无需权限；
/// Android 9 及以下需要 WRITE_EXTERNAL_STORAGE 权限。
class MobileDownloader extends BaseDownloader {
  @override
  List<String> get downloadUserAgents => const [
    kUaIosDouyin,
    kUaAndroidWechat,
    kUaEdge,
    kUaIosWechat,
  ];

  @override
  Future<void> beforeDownload() => _ensureStoragePermission();

  @override
  Future<void> afterDownload(String filePath) async {
    if (Platform.isAndroid) await _scanMediaFile(filePath);
  }

  @override
  Future<String> getDefaultDirectory() async {
    // Android：优先 App 私有外部存储（不需要权限，用户可在文件管理器 Android/data 下访问）
    // 路径示例：/storage/emulated/0/Android/data/org.umao.tkdownloader/files/umaov
    try {
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        return '${externalDir.path}${Platform.pathSeparator}umaov';
      }
    } catch (_) {}
    // Fallback：App 内部文档目录
    return (await getApplicationDocumentsDirectory()).path;
  }

  /// 申请存储权限
  /// - Android 11+（API 30+）：申请 manageExternalStorage，可写 Movies/Downloads
  /// - Android 10 及以下：申请 storage，可写外部存储
  Future<void> _ensureStoragePermission() async {
    if (!Platform.isAndroid) return;

    // 判断 Android 版本：SDK 30 = Android 11
    final sdkInt = await _androidSdkVersion();

    final Permission perm = sdkInt >= 30
        ? Permission.manageExternalStorage
        : Permission.storage;

    final status = await perm.status;
    if (status.isGranted || status.isLimited) return;

    if (status.isPermanentlyDenied) {
      throw const StoragePermissionDeniedException();
    }

    final result = await perm.request();
    // manageExternalStorage 在模拟器/某些机型上弹系统设置页，
    // 用户返回后结果仍为 denied，但实际可能已授权，再检查一次
    if (result.isDenied || result.isPermanentlyDenied) {
      final recheck = await perm.status;
      if (!recheck.isGranted) {
        if (recheck.isPermanentlyDenied) {
          throw const StoragePermissionDeniedException();
        }
        // Android 11+ 未授权 manageExternalStorage 时降级用 App 私有目录继续下载
        // （已在 getDefaultDirectory fallback 里处理）
      }
    }
  }

  /// 读取 Android SDK 版本，失败时返回 0（当做旧版本处理）
  Future<int> _androidSdkVersion() async {
    try {
      final result = await Process.run('getprop', ['ro.build.version.sdk']);
      return int.tryParse((result.stdout as String).trim()) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// 通知 Android MediaStore 扫描新文件，使其出现在相册等媒体库中
  Future<void> _scanMediaFile(String path) async {
    try {
      const channel = MethodChannel('org.umao.tkdownloader/media');
      await channel.invokeMethod('scanFile', {'path': path});
    } catch (_) {}
  }
}
