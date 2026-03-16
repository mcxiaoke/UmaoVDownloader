import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/log_service.dart';
import '../../services/settings_service.dart';

/// 将 LogService 适配为 Flutter ChangeNotifier
class _LogServiceAdapter extends ChangeNotifier {
  final LogService _logService;
  late final void Function() _listener;

  _LogServiceAdapter(this._logService) {
    _listener = notifyListeners;
    _logService.addListener(_listener);
  }

  LogService get log => _logService;

  @override
  void dispose() {
    _logService.removeListener(_listener);
    super.dispose();
  }
}

/// 日志面板组件
class LogPanel extends StatefulWidget {
  final LogService log;
  final SettingsService settings;
  final ScrollController scrollController;
  final VoidCallback onCopyTap;
  final VoidCallback onClearTap;

  const LogPanel({
    super.key,
    required this.log,
    required this.settings,
    required this.scrollController,
    required this.onCopyTap,
    required this.onClearTap,
  });

  @override
  State<LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<LogPanel> {
  late final _LogServiceAdapter _logAdapter;

  @override
  void initState() {
    super.initState();
    _logAdapter = _LogServiceAdapter(widget.log);
  }

  @override
  void dispose() {
    _logAdapter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 430;

          final actionStyle = TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            minimumSize: const Size(56, 34),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          );

          final actions = [
            TextButton.icon(
              onPressed: widget.onCopyTap,
              icon: const Icon(Icons.content_copy, size: 17),
              label: Text(
                '复制日志',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
              ),
              style: actionStyle,
            ),
            TextButton.icon(
              onPressed: widget.onClearTap,
              icon: const Icon(Icons.delete_outline, size: 17),
              label: Text(
                '清空',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
              ),
              style: actionStyle,
            ),
          ];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 标题栏
              if (narrow)
                Wrap(
                  runSpacing: 4,
                  spacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.terminal, size: 15, color: Colors.grey),
                        SizedBox(width: 4),
                        Text(
                          '日志',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                    ...actions,
                  ],
                )
              else
                Row(
                  children: [
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.terminal, size: 15, color: Colors.grey),
                        SizedBox(width: 4),
                        Text(
                          '日志',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                    const Spacer(),
                    ...actions,
                  ],
                ),
              const Divider(height: 4),
              // 日志列表占满剩余空间
              Expanded(child: _buildLogListView()),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLogListView() {
    return ListenableBuilder(
      listenable: _logAdapter,
      builder: (context, _) {
        final log = _logAdapter.log;
        // 自动滚动到底部
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (widget.scrollController.hasClients) {
            widget.scrollController.animateTo(
              widget.scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
            );
          }
        });

        final listView = ListView.builder(
          controller: widget.scrollController,
          itemCount: log.entries.length,
          itemBuilder: (_, i) {
            final e = log.entries[i];
            return Text(
              e.toString(),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: Platform.isAndroid ? 10 : 11,
                height: 1.4,
                color: switch (e.level) {
                  LogLevel.error => const Color(0xFFFF6B6B),
                  LogLevel.warn => const Color(0xFFFFD93D),
                  LogLevel.info => const Color(0xFFB0BEC5),
                },
              ),
            );
          },
        );

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.all(8),
          child: SelectionArea(
            // Windows 平台显示滚动条
            child: Platform.isWindows
                ? ScrollbarTheme(
                    data: ScrollbarThemeData(
                      thumbColor: WidgetStateProperty.all(Colors.grey.shade500),
                      thickness: const WidgetStatePropertyAll(4.0),
                      radius: const Radius.circular(4),
                    ),
                    child: Scrollbar(
                      controller: widget.scrollController,
                      thumbVisibility: true,
                      child: listView,
                    ),
                  )
                : listView,
          ),
        );
      },
    );
  }
}
