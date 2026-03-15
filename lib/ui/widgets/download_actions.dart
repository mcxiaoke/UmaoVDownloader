import 'package:flutter/material.dart';

import '../../services/parser_common.dart';

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
    final liveVideoCount = videoInfo.livePhotoUrls.where((u) => u.isNotEmpty).length;
    // 图片数量（用于按钮文字）
    final imageCount = videoInfo.imageUrls.length;

    // 根据媒体类型确定按钮文字
    final downloadLabel = switch (videoInfo.mediaType) {
      MediaType.image => '下载图片($imageCount)',
      MediaType.livePhoto => '下载图片($imageCount)',
      MediaType.video => '下载视频',
    };

    // 下载按钮公用部分
    final downloadBtn = FilledButton.icon(
      onPressed: downloading ? null : onDownload,
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
      label: Text(downloading ? '下载中…' : downloadLabel),
    );
    final doneLabel = downloadProgress == 1.0
        ? const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 18),
              SizedBox(width: 4),
              Text('下载完成', style: TextStyle(color: Colors.green, fontSize: 13)),
            ],
          )
        : const SizedBox.shrink();

    // 动图视频下载完成标签
    final liveVideoDoneLabel = liveVideoProgress == 1.0
        ? const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 18),
              SizedBox(width: 4),
              Text('视频完成', style: TextStyle(color: Colors.green, fontSize: 13)),
            ],
          )
        : const SizedBox.shrink();

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
                doneLabel,
                if (doneLabel is! SizedBox) const SizedBox(width: 8),
                if (videoInfo.musicUrl != null) ...[
                  OutlinedButton.icon(
                    onPressed: downloadingMusic ? null : onDownloadMusic,
                    icon: downloadingMusic
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.deepPurple,
                            ),
                          )
                        : const Icon(Icons.music_note, size: 16),
                    label: Text(downloadingMusic ? '下载中…' : '下载音乐'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.deepPurple,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                downloadBtn,
              ],
            ),
          MediaType.livePhoto => Row(
              children: [
                Text(
                  '实况图  $imageCount 张',
                  style: const TextStyle(fontSize: 13),
                ),
                const Spacer(),
                doneLabel,
                if (doneLabel is! SizedBox) const SizedBox(width: 8),
                // 动图视频按钮（仅当有动图时显示）
                if (liveVideoCount > 0) ...[
                  liveVideoDoneLabel,
                  if (liveVideoDoneLabel is! SizedBox) const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: downloadingLiveVideos ? null : onDownloadLiveVideos,
                    icon: downloadingLiveVideos
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.orange,
                            ),
                          )
                        : const Icon(Icons.videocam, size: 16),
                    label: Text(
                      downloadingLiveVideos
                          ? '下载中…'
                          : '下载视频($liveVideoCount)',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange.shade800,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                downloadBtn,
              ],
            ),
          MediaType.video => Row(
              children: [
                Container(
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
                ),
                const SizedBox(width: 8),
                _buildResolutionInfoLabel(),
                const Spacer(),
                doneLabel,
                if (doneLabel is! SizedBox) const SizedBox(width: 8),
                downloadBtn,
              ],
            ),
        },
        // 统一的进度条区域
        _buildProgressSection(imageCount),
      ],
    );
  }

  /// 构建进度条区域
  Widget _buildProgressSection(int imageCount) {
    final showDownloadProgress = downloading ||
        (downloadProgress != null && downloadProgress! < 1.0);
    final showLiveVideoProgress = downloadingLiveVideos ||
        (liveVideoProgress != null && liveVideoProgress! < 1.0);

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
                if (videoInfo.mediaType != MediaType.video &&
                    downloadProgress != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${(downloadProgress! * imageCount).round()}/$imageCount',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
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

  /// 构建视频信息标签：分辨率 | 尺寸 | 文件大小
  Widget _buildResolutionInfoLabel() {
    final parts = <String>[];

    // 分辨率
    if (videoInfo.resolutionLabel != null) {
      parts.add(videoInfo.resolutionLabel!);
    }

    // 尺寸（文件大小）
    if (fileSizeBytes != null) {
      final mb = fileSizeBytes! / (1024 * 1024);
      final sizeLabel = mb >= 1
          ? '${mb.toStringAsFixed(1)} MB'
          : '${(fileSizeBytes! / 1024).toStringAsFixed(0)} KB';
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
    final liveVideoCount = videoInfo.livePhotoUrls.where((u) => u.isNotEmpty).length;
    // 图片数量
    final imageCount = videoInfo.imageUrls.length;

    // 根据媒体类型确定按钮文字
    final downloadLabel = switch (videoInfo.mediaType) {
      MediaType.image => '图片($imageCount)',
      MediaType.livePhoto => '图片($imageCount)',
      MediaType.video => '下载视频',
    };

    final downloadBtn = FilledButton.icon(
      onPressed: downloading ? null : onDownload,
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
      label: Text(downloading ? '下载中…' : downloadLabel),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        switch (videoInfo.mediaType) {
          MediaType.image => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      '图文作品  $imageCount 张图片',
                      style: const TextStyle(fontSize: 13),
                    ),
                    if (downloadProgress == 1.0) ...const [
                      Spacer(),
                      Icon(Icons.check_circle, color: Colors.green, size: 18),
                      SizedBox(width: 4),
                      Text(
                        '下载完成',
                        style: TextStyle(color: Colors.green, fontSize: 13),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: downloadBtn),
                    if (videoInfo.musicUrl != null) ...[
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: downloadingMusic ? null : onDownloadMusic,
                        icon: downloadingMusic
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.deepPurple,
                                ),
                              )
                            : const Icon(Icons.music_note, size: 16),
                        label: Text(downloadingMusic ? '…' : '音乐'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.deepPurple,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          MediaType.livePhoto => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      '实况图  $imageCount 张',
                      style: const TextStyle(fontSize: 13),
                    ),
                    if (downloadProgress == 1.0) ...const [
                      Spacer(),
                      Icon(Icons.check_circle, color: Colors.green, size: 18),
                      SizedBox(width: 4),
                      Text(
                        '下载完成',
                        style: TextStyle(color: Colors.green, fontSize: 13),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: downloadBtn),
                    // 动图视频按钮
                    if (liveVideoCount > 0) ...[
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: downloadingLiveVideos ? null : onDownloadLiveVideos,
                        icon: downloadingLiveVideos
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.orange,
                                ),
                              )
                            : const Icon(Icons.videocam, size: 16),
                        label: Text(downloadingLiveVideos ? '…' : '视频($liveVideoCount)'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orange.shade800,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          MediaType.video => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
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
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildResolutionInfoLabel(),
                    if (downloadProgress == 1.0) ...const [
                      Spacer(),
                      Icon(Icons.check_circle, color: Colors.green, size: 18),
                      SizedBox(width: 4),
                      Text(
                        '下载完成',
                        style: TextStyle(color: Colors.green, fontSize: 13),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                downloadBtn,
              ],
            ),
        },
        // 统一的进度条区域
        _buildProgressSection(imageCount),
      ],
    );
  }

  /// 构建进度条区域
  Widget _buildProgressSection(int imageCount) {
    final showDownloadProgress = downloading ||
        (downloadProgress != null && downloadProgress! < 1.0);
    final showLiveVideoProgress = downloadingLiveVideos ||
        (liveVideoProgress != null && liveVideoProgress! < 1.0);

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
                if (videoInfo.mediaType != MediaType.video &&
                    downloadProgress != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${(downloadProgress! * imageCount).round()}/$imageCount',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
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

  /// 构建视频信息标签：分辨率 | 尺寸 | 文件大小
  Widget _buildResolutionInfoLabel() {
    final parts = <String>[];

    // 分辨率
    if (videoInfo.resolutionLabel != null) {
      parts.add(videoInfo.resolutionLabel!);
    }

    // 尺寸（文件大小）
    if (fileSizeBytes != null) {
      final mb = fileSizeBytes! / (1024 * 1024);
      final sizeLabel = mb >= 1
          ? '${mb.toStringAsFixed(1)} MB'
          : '${(fileSizeBytes! / 1024).toStringAsFixed(0)} KB';
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
}
