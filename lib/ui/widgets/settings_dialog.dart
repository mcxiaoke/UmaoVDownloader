import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../services/app_logger.dart';
import '../../services/log_service.dart';
import '../../services/settings_service.dart';

/// 设置对话框
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({
    super.key,
    required this.settings,
    required this.log,
    required this.appVersion,
    this.onOpenUrl,
  });

  final SettingsService settings;
  final LogService log;
  final String appVersion;
  final void Function(String url)? onOpenUrl;

  /// 显示设置对话框的便捷方法
  static Future<void> show(
    BuildContext context, {
    required SettingsService settings,
    required LogService log,
    required String appVersion,
    void Function(String url)? onOpenUrl,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => SettingsDialog(
        settings: settings,
        log: log,
        appVersion: appVersion,
        onOpenUrl: onOpenUrl,
      ),
    );
  }

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late bool _verbose;

  @override
  void initState() {
    super.initState();
    _verbose = widget.settings.verboseLog;
  }

  Future<void> _toggleVerbose(bool value) async {
    setState(() => _verbose = value);
    await widget.settings.setVerboseLog(value);
    AppLogger.setVerbose(value);
    widget.log.info(value ? '已开启详细日志输出' : '已关闭详细日志输出');
  }

  void _openUrl(String url) {
    widget.onOpenUrl?.call(url);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.tune),
          SizedBox(width: 8),
          Text('设置'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile.adaptive(
            value: _verbose,
            onChanged: _toggleVerbose,
            title: const Text('详细日志'),
          ),
          const Divider(height: 24),
          // 关于信息
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                    'Umao VDownloader v${widget.appVersion.isNotEmpty ? widget.appVersion : "..."}'),
                const Text('mcxiaoke'),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () => _openUrl(kGitHubUrl),
                  child: Text(
                    kGitHubUrl,
                    style: TextStyle(
                      color: Theme.of(context).primaryColor,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
