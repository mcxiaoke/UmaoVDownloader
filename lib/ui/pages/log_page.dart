import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/log_service.dart';

/// 日志页面 - 独立页面/弹窗
///
/// Windows 平台作为 Dialog 弹窗显示，
/// Android 平台作为独立页面 push 到导航栈。
class LogPage extends StatefulWidget {
  final LogService log;

  const LogPage({
    super.key,
    required this.log,
  });

  /// Windows 平台：以 Dialog 形式打开日志
  static Future<void> showAsDialog(
    BuildContext context, {
    required LogService log,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => LogPage(log: log),
    );
  }

  /// Android 平台：以新页面形式打开日志
  static Future<void> pushAsPage(
    BuildContext context, {
    required LogService log,
  }) {
    return Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (ctx) => LogPage(log: log),
      ),
    );
  }

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _copyLogContent() {
    if (widget.log.entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('当前没有日志可复制'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final content = widget.log.entries.map((e) => e.toString()).join('\n');
    Clipboard.setData(ClipboardData(text: content));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制日志内容（${widget.log.entries.length} 条）'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _clearLog() {
    setState(() => widget.log.entries.clear());
  }

  @override
  Widget build(BuildContext context) {
    final isWindows = Platform.isWindows;

    // Windows: Dialog 形式
    if (isWindows) {
      return Dialog(
        child: SizedBox(
          width: 600,
          height: 500,
          child: _buildContent(context, showCloseButton: true),
        ),
      );
    }

    // Android: 独立页面
    return Scaffold(
      appBar: AppBar(
        title: const Text('日志'),
        actions: [
          IconButton(
            icon: const Icon(Icons.content_copy),
            tooltip: '复制',
            onPressed: _copyLogContent,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '清空',
            onPressed: _clearLog,
          ),
        ],
      ),
      body: _buildContent(context, showCloseButton: false),
    );
  }

  Widget _buildContent(BuildContext context, {required bool showCloseButton}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 标题栏（仅 Windows Dialog 需要）
        if (showCloseButton)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                const Icon(Icons.article_outlined, size: 22),
                const SizedBox(width: 8),
                const Text('日志', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.content_copy, size: 20),
                  tooltip: '复制',
                  onPressed: _copyLogContent,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  tooltip: '清空',
                  onPressed: _clearLog,
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        if (showCloseButton) const Divider(height: 1),
        // 日志列表
        Expanded(child: _buildLogListView()),
      ],
    );
  }

  Widget _buildLogListView() {
    return ListenableBuilder(
      listenable: widget.log,
      builder: (context, _) {
        final log = widget.log;

        // 空列表时显示占位内容
        if (log.entries.isEmpty) {
          return Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Center(
              child: Text(
                '暂无日志',
                style: TextStyle(
                  color: Color(0xFF78909C),
                  fontSize: 12,
                ),
              ),
            ),
          );
        }

        // 自动滚动到底部
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients &&
              _scrollController.position.maxScrollExtent > 0) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
            );
          }
        });

        final listView = ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(8),
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
                  LogLevel.debug => const Color(0xFF78909C),
                },
              ),
            );
          },
        );

        return Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(6),
          ),
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
                      controller: _scrollController,
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
