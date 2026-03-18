import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../providers/providers.dart';
import '../services/log_service.dart';
import '../services/parser_common.dart';
import '../services/settings_service.dart';
import '../utils/platform_utils.dart';
import 'mixins/permission_mixin.dart';
import 'pages/log_page.dart';
import 'widgets/directory_row.dart';
import 'widgets/input_row.dart';
import 'widgets/result_card.dart';
import 'widgets/settings_dialog.dart';

/// 主页
///
/// 使用 ConsumerStatefulWidget 以支持 Riverpod 的响应式状态管理。
/// 状态通过 Provider 管理，UI 监听状态变化并响应。
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> with PermissionMixin {
  final _inputCtrl = TextEditingController();
  final _thumbScrollCtrl = ScrollController();
  bool _screenSizeLogged = false;
  String _appVersion = '';

  // 服务 getter - 直接从 Provider 获取
  LogService get _log => ref.read(logServiceProvider);
  SettingsService get _settings => ref.read(settingsServiceProvider);

  @override
  void initState() {
    super.initState();
    _initAppVersion();
    if (Platform.isAndroid) {
      checkStoragePermission();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_screenSizeLogged) {
      _screenSizeLogged = true;
      final mediaQuery = MediaQuery.of(context);
      final screenWidth = mediaQuery.size.width;
      final screenHeight = mediaQuery.size.height;
      final devicePixelRatio = mediaQuery.devicePixelRatio;
      _log.info(
        '屏幕: ${screenWidth.toStringAsFixed(0)} x ${screenHeight.toStringAsFixed(0)} '
        '逻辑像素, 设备像素比: ${devicePixelRatio.toStringAsFixed(2)}',
      );
    }
  }

  Future<void> _initAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = info.version;
      });
    }
  }

  // ─── 解析逻辑 ─────────────────────────────────────────────────────

  /// 解析输入
  Future<void> _parse() async {
    // 让输入框失去焦点，隐藏键盘
    FocusScope.of(context).unfocus();

    final input = _inputCtrl.text.trim();
    if (input.isEmpty) return;

    final result =
        await ref.read(videoNotifierProvider.notifier).parse(input);

    // 处理需要 UI 反馈的结果
    if (result.shouldShowErrorSnack && mounted) {
      final message = switch (result.type) {
        ParseResultType.invalidUrl => '未找到有效的链接，请粘贴抖音/小红书分享文本或链接',
        ParseResultType.unsupportedPlatform => '目前仅支持抖音/小红书链接',
        ParseResultType.error => result.errorMessage ?? '解析失败，请稍后重试',
        _ => '解析失败',
      };

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    // 解析成功：重置下载状态
    if (result.isSuccess) {
      ref.read(downloadNotifierProvider.notifier).reset();
    }
  }

  // ─── 下载逻辑 ─────────────────────────────────────────────────────

  /// 下载主内容
  Future<void> _download() async {
    final result = await ref.read(downloadNotifierProvider.notifier).download();
    _handleDownloadResult(result);
  }

  /// 下载单个图片
  Future<void> _downloadSingleImage(int index) async {
    final result =
        await ref.read(downloadNotifierProvider.notifier).downloadSingleImage(index);
    _handleDownloadResult(result, index: index, type: '图片');
  }

  /// 下载单个实况视频
  Future<void> _downloadSingleLivePhoto(int index) async {
    final result =
        await ref.read(downloadNotifierProvider.notifier).downloadSingleLivePhoto(index);
    _handleDownloadResult(result, index: index, type: '实况视频');
  }

  /// 下载背景音乐
  Future<void> _downloadMusic() async {
    final result = await ref.read(downloadNotifierProvider.notifier).downloadMusic();
    _handleDownloadResult(result, type: '背景音乐');
  }

  /// 下载动图视频
  Future<void> _downloadLiveVideos() async {
    final result = await ref.read(downloadNotifierProvider.notifier).downloadLiveVideos();
    _handleDownloadResult(result, type: '动图视频');
  }

  /// 处理下载结果
  void _handleDownloadResult(DownloadResult result, {int? index, String? type}) {
    if (!mounted) return;

    // 权限被拒绝
    if (result.shouldShowPermissionDialog) {
      showPermissionDeniedDialog();
      return;
    }

    // 成功
    if (result.isSuccess) {
      // 清空输入
      _inputCtrl.clear();

      // 显示成功提示
      final message = _buildSuccessMessage(result, index: index, type: type);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
        ),
      );

      // 单个下载：延迟清除进度
      if (index != null) {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            ref.read(downloadNotifierProvider.notifier).clearSingleProgress(index);
          }
        });
      }
    }

    // 失败
    if (result.type == DownloadResultType.error && result.errorMessage != null) {
      final label = type != null && index != null ? '$type ${index + 1}' : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$label 下载失败'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// 构建成功消息
  String _buildSuccessMessage(DownloadResult result, {int? index, String? type}) {
    if (type != null && index != null) {
      return '$type ${index + 1} 已保存';
    }
    if (result.count != null) {
      return '动图视频已保存（${result.count} 个）';
    }
    return '已保存到 ${result.path}';
  }

  // ─── 构建界面 ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // 监听状态
    final videoState = ref.watch(videoNotifierProvider);
    final downloadState = ref.watch(downloadNotifierProvider);

    final isAndroid = Platform.isAndroid;

    return Scaffold(
      appBar: AppBar(
        title: LayoutBuilder(
          builder: (context, constraints) {
            // 小屏用短标题
            return Text(
              MediaQuery.of(context).size.width <= 420
                  ? 'Umao 视频下载'
                  : 'Umao VDownloader - 短视频下载',
            );
          },
        ),
        actions: [
          // 设置按钮
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: '设置',
            onPressed: _openLogSettingsPanel,
          ),
          // 日志按钮
          IconButton(
            icon: const Icon(Icons.article_outlined),
            tooltip: '查看日志',
            onPressed: _openLogPanel,
          ),
          const SizedBox(width: 8),
        ],
      ),
      // Android 允许输入法覆盖
      resizeToAvoidBottomInset: isAndroid,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          child: _buildMainContent(videoState, downloadState),
        ),
      ),
    );
  }

  /// 主内容区
  Widget _buildMainContent(VideoState videoState, DownloadState downloadState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 顶部输入行（固定）
        InputRow(
          controller: _inputCtrl,
          parsing: videoState.parsing,
          onParse: _parse,
        ),
        const SizedBox(height: 10),
        // 中间结果区域（可滚动）
        Expanded(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: _buildResultCard(videoState, downloadState),
          ),
        ),
        const SizedBox(height: 10),
        // 底部目录行（固定）
        DirectoryRow(
          settings: _settings,
          onPickDirectory: _pickDirectory,
          onOpenDirectory: _openDirectory,
        ),
      ],
    );
  }

  /// 打开日志面板
  Future<void> _openLogPanel() async {
    if (Platform.isWindows) {
      // Windows: Dialog 形式
      await LogPage.showAsDialog(context, log: _log);
    } else {
      // Android: 新页面
      await LogPage.pushAsPage(context, log: _log);
    }
  }

  // ── 解析结果卡片 ──────────────────────────────────────────────

  Widget _buildResultCard(VideoState videoState, DownloadState downloadState) {
    // 空状态
    if (videoState.videoInfo == null && !videoState.parsing) {
      return const EmptyResultPlaceholder();
    }

    // 加载中
    if (videoState.parsing) {
      return const LoadingPlaceholder();
    }

    // 显示结果
    return ResultCard(
      videoInfo: videoState.videoInfo!,
      scrollController: _thumbScrollCtrl,
      downloading: downloadState.downloading,
      downloadProgress: downloadState.downloadProgress,
      downloadingMusic: downloadState.downloadingMusic,
      downloadingLiveVideos: downloadState.downloadingLiveVideos,
      liveVideoProgress: downloadState.liveVideoProgress,
      singleProgressMap: downloadState.singleProgressMap,
      singleDownloadingMap: downloadState.singleDownloadingMap,
      singleDoneMap: downloadState.singleDoneMap,
      fetchingSize: videoState.fetchingSize,
      fileSizeBytes: videoState.fileSizeBytes,
      onDownload: _download,
      onDownloadMusic: _downloadMusic,
      onDownloadLiveVideos: _downloadLiveVideos,
      onDownloadImage: _downloadSingleImage,
      onDownloadLivePhoto: _downloadSingleLivePhoto,
    );
  }

  /// 打开设置对话框
  Future<void> _openLogSettingsPanel() async {
    await SettingsDialog.show(
      context,
      settings: _settings,
      log: _log,
      appVersion: _appVersion,
      onOpenUrl: PlatformUtils.openUrl,
    );
  }

  // ─── 目录操作 ────────────────────────────────────────────────

  Future<void> _pickDirectory() async {
    final savedDir = _settings.downloadDir;
    final initialDir = savedDir.isNotEmpty && await Directory(savedDir).exists()
        ? savedDir
        : null;
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择下载目录',
      initialDirectory: initialDir,
    );
    if (result != null) {
      await _settings.setDownloadDir(result);
      _log.info('下载目录已更改为：$result');
    }
  }

  void _openDirectory(String path) {
    PlatformUtils.openDirectory(path);
  }

  // ─── 生命周期 ────────────────────────────────────────────────

  @override
  void dispose() {
    _inputCtrl.dispose();
    _thumbScrollCtrl.dispose();
    super.dispose();
  }
}
