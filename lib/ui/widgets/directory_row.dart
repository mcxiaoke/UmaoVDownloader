import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/settings_service.dart';

/// 下载目录行组件
class DirectoryRow extends StatelessWidget {
  final SettingsService settings;
  final VoidCallback onPickDirectory;
  final void Function(String path) onOpenDirectory;

  const DirectoryRow({
    super.key,
    required this.settings,
    required this.onPickDirectory,
    required this.onOpenDirectory,
  });

  @override
  Widget build(BuildContext context) {
    final isAndroid = Platform.isAndroid;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isAndroid
                    ? Icons.folder_special_outlined
                    : Icons.folder_outlined,
                size: 22,
                color: Colors.grey,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  settings.downloadDir.isEmpty
                      ? '（未设置下载目录）'
                      : settings.downloadDir,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!isAndroid) ...[
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: onPickDirectory,
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('更改', style: TextStyle(fontSize: 14)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                  ),
                ),
                if (settings.downloadDir.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  OutlinedButton.icon(
                    onPressed: () => onOpenDirectory(settings.downloadDir),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('打开', style: TextStyle(fontSize: 14)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
          // Android：快捷目录选择按钮（Movies / Downloads / App私有）
          if (isAndroid)
            FutureBuilder<List<AndroidQuickDir>>(
              future: SettingsService.androidQuickDirs(),
              builder: (context, snap) {
                if (!snap.hasData) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 6,
                    children: snap.data!.map((d) {
                      final selected = settings.downloadDir == d.path;
                      return ChoiceChip(
                        label: Text(
                          d.label,
                          style: const TextStyle(fontSize: 12),
                        ),
                        selected: selected,
                        onSelected: (_) async {
                          await settings.setDownloadDir(d.path);
                        },
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
