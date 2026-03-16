import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/parser_common.dart';
import 'rate_limited_image.dart';

/// 缩略图网格（图文作品 / 实况图）- 自动换行自适应
class ThumbnailGrid extends StatelessWidget {
  final VideoInfo videoInfo;
  final ScrollController scrollController;
  final Map<int, double> singleProgress;
  final Map<int, bool> singleDownloading;
  final Map<int, bool> singleDone;
  final void Function(int index) onDownloadImage;
  final void Function(int index) onDownloadLivePhoto;

  const ThumbnailGrid({
    super.key,
    required this.videoInfo,
    required this.scrollController,
    required this.singleProgress,
    required this.singleDownloading,
    required this.singleDone,
    required this.onDownloadImage,
    required this.onDownloadLivePhoto,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrls = videoInfo.imageUrls;
    final imageThumbUrls = videoInfo.imageThumbUrls.isNotEmpty
        ? videoInfo.imageThumbUrls
        : videoInfo.imageUrls;
    if (imageUrls.isEmpty) return const SizedBox.shrink();

    final isLivePhotoType = videoInfo.mediaType == MediaType.livePhoto;
    final livePhotoUrls = videoInfo.livePhotoUrls;

    return LayoutBuilder(
      builder: (context, constraints) {
        final containerWidth = constraints.maxWidth;
        final isSmallScreen = containerWidth <= 420;

        // 小屏：固定每行3个，宽度自适应
        // 大屏：桌面用150x210，其他用100x140
        final int crossAxisCount;
        final double childAspectRatio;

        if (isSmallScreen) {
          // 小屏：固定3列，高度按1.4比例
          crossAxisCount = 3;
          childAspectRatio = 1 / 1.4;
        } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
          // 桌面：150x210
          crossAxisCount = (containerWidth / (150 + 8)).floor().clamp(1, 10);
          childAspectRatio = 150 / 210;
        } else {
          // 移动端大屏：100x140
          crossAxisCount = (containerWidth / (100 + 8)).floor().clamp(1, 10);
          childAspectRatio = 100 / 140;
        }

        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: childAspectRatio,
            ),
            itemCount: imageUrls.length,
            itemBuilder: (context, index) {
              final thumbUrl = imageThumbUrls[index];
              final hasLivePhoto = isLivePhotoType &&
                  index < livePhotoUrls.length &&
                  livePhotoUrls[index].isNotEmpty;
              final isDownloading = singleDownloading[index] == true;
              final progress = singleProgress[index];
              final isDone = (progress ?? 0) >= 0.99;
              final isSingleDone = singleDone[index] == true;

              return Stack(
                children: [
                  // 缩略图
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: RateLimitedImage(
                        url: thumbUrl,
                        fit: BoxFit.cover,
                        headers: thumbUrl.contains('xhscdn.com')
                            ? const {'Referer': 'https://www.xiaohongshu.com/'}
                            : null,
                      ),
                    ),
                  ),
                  // Live Photo 标识（右上角）
                  if (hasLivePhoto)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(179),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.videocam, size: 12, color: Colors.white),
                            SizedBox(width: 2),
                            Text(
                              'LIVE',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // 下载按钮（底部）- 下载完成后隐藏
                  if (!isSingleDone)
                    Positioned(
                      bottom: 6,
                      left: 6,
                      right: 6,
                      child: _DownloadButton(
                        label: hasLivePhoto ? 'MP4' : '图片',
                        isDownloading: isDownloading,
                        isDone: isDone,
                        progress: progress,
                        onPressed: hasLivePhoto
                            ? () => onDownloadLivePhoto(index)
                            : () => onDownloadImage(index),
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// 下载按钮组件
class _DownloadButton extends StatelessWidget {
  final String label;
  final bool isDownloading;
  final bool isDone;
  final double? progress;
  final VoidCallback onPressed;

  const _DownloadButton({
    required this.label,
    required this.isDownloading,
    required this.isDone,
    required this.progress,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: ElevatedButton(
        onPressed: isDownloading || isDone ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isDone ? Colors.green : Colors.black.withAlpha(179),
          foregroundColor: Colors.white,
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        child: isDownloading
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: (progress ?? 0) > 0 && (progress ?? 1) < 1
                      ? progress
                      : null,
                  color: Colors.white,
                ),
              )
            : isDone
                ? const Icon(Icons.check, size: 16)
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.download, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        label,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
      ),
    );
  }
}
