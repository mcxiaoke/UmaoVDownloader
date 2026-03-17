import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Android 权限处理 Mixin
///
/// 处理存储权限的检查和请求，适用于需要存储权限的页面。
mixin PermissionMixin<T extends StatefulWidget> on State<T> {
  /// 检查存储权限，未授权则弹窗引导用户授权
  Future<void> checkStoragePermission() async {
    if (!Platform.isAndroid) return;

    // 延迟一帧执行，确保 context 可用
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    final sdkInt = await _androidSdkVersion();
    final permission = sdkInt >= 30
        ? Permission.manageExternalStorage
        : Permission.storage;

    final status = await permission.status;
    if (status.isGranted || status.isLimited) return;

    // 未授权：弹窗引导用户授权
    _showPermissionRequiredDialog(permission);
  }

  /// 读取 Android SDK 版本
  Future<int> _androidSdkVersion() async {
    try {
      final result = await Process.run('getprop', ['ro.build.version.sdk']);
      return int.tryParse((result.stdout as String).trim()) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// 显示必须授权的对话框
  void _showPermissionRequiredDialog(Permission permission) {
    showDialog<void>(
      context: context,
      barrierDismissible: false, // 点击外部不关闭
      builder: (ctx) => AlertDialog(
        title: const Text('需要存储权限'),
        content: const Text('此应用需要存储权限才能保存下载的文件。\n\n请授权后使用。'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              SystemNavigator.pop(); // 退出应用
            },
            child: const Text('退出'),
          ),
          FilledButton(
            onPressed: () async {
              final result = await permission.request();
              final recheck = await permission.status;
              if (result.isGranted || recheck.isGranted || recheck.isLimited) {
                if (ctx.mounted) Navigator.pop(ctx);
              } else if (result.isPermanentlyDenied ||
                  recheck.isPermanentlyDenied) {
                // 永久拒绝，引导去设置
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  openAppSettings();
                  // 返回后再次检查
                  Future.delayed(const Duration(milliseconds: 500), () {
                    if (mounted) checkStoragePermission();
                  });
                }
              }
            },
            child: const Text('授权'),
          ),
        ],
      ),
    );
  }

  /// 显示权限被永久拒绝的对话框
  void showPermissionDeniedDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('需要存储权限'),
        content: const Text('存储权限已被永久拒绝，请在系统设置中手动开启后重试。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }
}
