import 'package:flutter/material.dart';

import '../../services/parser_common.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 共享小组件
// ─────────────────────────────────────────────────────────────────────────────

/// 主下载按钮
class DownloadButton extends StatelessWidget {
  final bool downloading;
  final String label;
  final VoidCallback onPressed;

  const DownloadButton({
    super.key,
    required this.downloading,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: downloading ? null : onPressed,
      icon: downloading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.download, size: 18),
      label: Text(downloading ? '下载中…' : label),
    );
  }
}

/// 音乐下载按钮
class MusicDownloadButton extends StatelessWidget {
  final bool downloading;
  final String label;
  final VoidCallback onPressed;
  final bool expanded;

  const MusicDownloadButton({
    super.key,
    required this.downloading,
    required this.label,
    required this.onPressed,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton.icon(
      onPressed: downloading ? null : onPressed,
      icon: downloading
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.deepPurple,
              ),
            )
          : const Icon(Icons.music_note, size: 16),
      label: Text(downloading ? '…' : label),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.deepPurple,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        visualDensity: VisualDensity.compact,
      ),
    );
    return expanded ? Expanded(child: button) : button;
  }
}

/// 动图视频下载按钮
class LiveVideoDownloadButton extends StatelessWidget {
  final bool downloading;
  final String label;
  final VoidCallback onPressed;
  final bool expanded;

  const LiveVideoDownloadButton({
    super.key,
    required this.downloading,
    required this.label,
    required this.onPressed,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton.icon(
      onPressed: downloading ? null : onPressed,
      icon: downloading
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.orange,
              ),
            )
          : const Icon(Icons.videocam, size: 16),
      label: Text(downloading ? '下载中…' : label),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.orange.shade800,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
    return expanded ? Expanded(child: button) : button;
  }
}

/// 视频类型标签
class VideoTypeBadge extends StatelessWidget {
  const VideoTypeBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.videocam, size: 12, color: Colors.blue.shade700),
          const SizedBox(width: 4),
          Text(
            '视频',
            style: TextStyle(fontSize: 11, color: Colors.blue.shade700),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 共享辅助方法
// ─────────────────────────────────────────────────────────────────────────────

/// 构建视频信息标签：分辨率 | 尺寸 | 文件大小
Widget buildResolutionInfoLabel({
  required String? resolutionLabel,
  required int? fileSizeBytes,
  required bool fetchingSize,
}) {
  final parts = <String>[];

  // 分辨率
  if (resolutionLabel != null) {
    parts.add(resolutionLabel);
  }

  // 尺寸（文件大小）
  if (fileSizeBytes != null) {
    final mb = fileSizeBytes / (1024 * 1024);
    final sizeLabel = mb >= 1
        ? '${mb.toStringAsFixed(1)} MB'
        : '${(fileSizeBytes / 1024).toStringAsFixed(0)} KB';
    parts.add(sizeLabel);
  } else if (fetchingSize) {
    parts.add('...');
  }

  final text = parts.join(' | ');
  if (text.isEmpty) return const SizedBox.shrink();

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.info_outline, size: 12, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
        ),
      ],
    ),
  );
}

/// 构建进度条区域
Widget buildProgressSection({
  required MediaType mediaType,
  required bool downloading,
  required double? downloadProgress,
  required bool downloadingLiveVideos,
  required double? liveVideoProgress,
  required int imageCount,
}) {
  final showDownloadProgress =
      downloading || (downloadProgress != null && downloadProgress < 1.0);
  final showLiveVideoProgress =
      downloadingLiveVideos ||
      (liveVideoProgress != null && liveVideoProgress < 1.0);

  if (!showDownloadProgress && !showLiveVideoProgress) {
    return const SizedBox.shrink();
  }

  return Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 主下载进度条
        if (showDownloadProgress)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(value: downloadProgress),
              if (mediaType != MediaType.video && downloadProgress != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '${(downloadProgress * imageCount).round()}/$imageCount',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
            ],
          ),
        // 动图视频进度条
        if (showLiveVideoProgress) ...[
          if (showDownloadProgress) const SizedBox(height: 8),
          LinearProgressIndicator(
            value: liveVideoProgress,
            backgroundColor: Colors.orange.shade50,
            color: Colors.orange,
          ),
        ],
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// 下载操作组件
// ─────────────────────────────────────────────────────────────────────────────

/// 下载操作区域组件（宽屏布局）
class DownloadActionsWide extends StatelessWidget {
  final VideoInfo videoInfo;
  final bool downloading;
  final double? downloadProgress;
  final bool downloadingMusic;
  final bool downloadingLiveVideos;
  final double? liveVideoProgress;
  final int? fileSizeBytes;
  final bool fetchingSize;
  final VoidCallback onDownload;
  final VoidCallback onDownloadMusic;
  final VoidCallback onDownloadLiveVideos;

  const DownloadActionsWide({
    super.key,
    required this.videoInfo,
    required this.downloading,
    required this.downloadProgress,
    required this.downloadingMusic,
    required this.downloadingLiveVideos,
    required this.liveVideoProgress,
    required this.fileSizeBytes,
    required this.fetchingSize,
    required this.onDownload,
    required this.onDownloadMusic,
    required this.onDownloadLiveVideos,
  });

  @override
  Widget build(BuildContext context) {
    // 动图视频数量
    final liveVideoCount = videoInfo.livePhotoUrls
        .where((u) => u.isNotEmpty)
        .length;
    // 图片数量（用于按钮文字）
    final imageCount = videoInfo.imageUrls.length;

    // 根据媒体类型确定按钮文字
    final downloadLabel = switch (videoInfo.mediaType) {
      MediaType.image => '下载图片($imageCount)',
      MediaType.livePhoto => '下载图片($imageCount)',
      MediaType.video => '下载视频',
    };

    final downloadBtn = DownloadButton(
      downloading: downloading,
      label: downloadLabel,
      onPressed: onDownload,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        switch (videoInfo.mediaType) {
          MediaType.image => Row(
            children: [
              Text(
                '图文作品  $imageCount 张图片',
                style: const TextStyle(fontSize: 13),
              ),
              const Spacer(),
              if (videoInfo.musicUrl != null) ...[
                MusicDownloadButton(
                  downloading: downloadingMusic,
                  label: '下载音乐',
                  onPressed: onDownloadMusic,
                ),
                const SizedBox(width: 8),
              ],
              downloadBtn,
            ],
          ),
          MediaType.livePhoto => Row(
            children: [
              Text('实况图  $imageCount 张', style: const TextStyle(fontSize: 13)),
              const Spacer(),
              // 动图视频按钮（仅当有动图时显示）
              if (liveVideoCount > 0)
                LiveVideoDownloadButton(
                  downloading: downloadingLiveVideos,
                  label: '下载视频($liveVideoCount)',
                  onPressed: onDownloadLiveVideos,
                ),
              const SizedBox(width: 8),
              downloadBtn,
            ],
          ),
          MediaType.video => Row(
            children: [
              const VideoTypeBadge(),
              const SizedBox(width: 8),
              buildResolutionInfoLabel(
                resolutionLabel: videoInfo.resolutionLabel,
                fileSizeBytes: fileSizeBytes,
                fetchingSize: fetchingSize,
              ),
              const Spacer(),
              downloadBtn,
            ],
          ),
        },
        // 统一的进度条区域
        buildProgressSection(
          mediaType: videoInfo.mediaType,
          downloading: downloading,
          downloadProgress: downloadProgress,
          downloadingLiveVideos: downloadingLiveVideos,
          liveVideoProgress: liveVideoProgress,
          imageCount: imageCount,
        ),
      ],
    );
  }
}

/// 下载操作区域组件（窄屏布局）
class DownloadActionsNarrow extends StatelessWidget {
  final VideoInfo videoInfo;
  final bool downloading;
  final double? downloadProgress;
  final bool downloadingMusic;
  final bool downloadingLiveVideos;
  final double? liveVideoProgress;
  final int? fileSizeBytes;
  final bool fetchingSize;
  final VoidCallback onDownload;
  final VoidCallback onDownloadMusic;
  final VoidCallback onDownloadLiveVideos;

  const DownloadActionsNarrow({
    super.key,
    required this.videoInfo,
    required this.downloading,
    required this.downloadProgress,
    required this.downloadingMusic,
    required this.downloadingLiveVideos,
    required this.liveVideoProgress,
    required this.fileSizeBytes,
    required this.fetchingSize,
    required this.onDownload,
    required this.onDownloadMusic,
    required this.onDownloadLiveVideos,
  });

  @override
  Widget build(BuildContext context) {
    // 动图视频数量
    final liveVideoCount = videoInfo.livePhotoUrls
        .where((u) => u.isNotEmpty)
        .length;
    // 图片数量
    final imageCount = videoInfo.imageUrls.length;

    // 根据媒体类型确定按钮文字
    final downloadLabel = switch (videoInfo.mediaType) {
      MediaType.image => '图片($imageCount)',
      MediaType.livePhoto => '图片($imageCount)',
      MediaType.video => '下载视频',
    };

    final downloadBtn = DownloadButton(
      downloading: downloading,
      label: downloadLabel,
      onPressed: onDownload,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        switch (videoInfo.mediaType) {
          MediaType.image => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '图文作品  $imageCount 张图片',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (videoInfo.musicUrl != null) ...[
                    MusicDownloadButton(
                      downloading: downloadingMusic,
                      label: '音乐',
                      onPressed: onDownloadMusic,
                      expanded: true,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(child: downloadBtn),
                ],
              ),
            ],
          ),
          MediaType.livePhoto => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '实况图  $imageCount 张',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  // 动图视频按钮
                  if (liveVideoCount > 0) ...[
                    LiveVideoDownloadButton(
                      downloading: downloadingLiveVideos,
                      label: '视频($liveVideoCount)',
                      onPressed: onDownloadLiveVideos,
                      expanded: true,
                    ),
                    const SizedBox(width: 8),
                  ],
                  // 图片按钮
                  Expanded(child: downloadBtn),
                ],
              ),
            ],
          ),
          MediaType.video => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const VideoTypeBadge(),
                  const SizedBox(width: 8),
                  buildResolutionInfoLabel(
                    resolutionLabel: videoInfo.resolutionLabel,
                    fileSizeBytes: fileSizeBytes,
                    fetchingSize: fetchingSize,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              downloadBtn,
            ],
          ),
        },
        // 统一的进度条区域
        buildProgressSection(
          mediaType: videoInfo.mediaType,
          downloading: downloading,
          downloadProgress: downloadProgress,
          downloadingLiveVideos: downloadingLiveVideos,
          liveVideoProgress: liveVideoProgress,
          imageCount: imageCount,
        ),
      ],
    );
  }
}
