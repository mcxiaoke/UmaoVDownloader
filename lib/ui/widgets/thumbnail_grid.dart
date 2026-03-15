import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../services/parser_common.dart';

/// 缩略图横向滚动列表（图文作品 / 实况图）
class ThumbnailGrid extends StatelessWidget {
  final VideoInfo videoInfo;
  final ScrollController scrollController;
  final Map<int, double> singleProgress;
  final Map<int, bool> singleDownloading;
  final void Function(int index) onDownloadImage;
  final void Function(int index) onDownloadLivePhoto;

  const ThumbnailGrid({
    super.key,
    required this.videoInfo,
    required this.scrollController,
    required this.singleProgress,
    required this.singleDownloading,
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
    final itemCount = imageUrls.length;

    // 固定缩略图尺寸（统一卡片高度为120）
    const itemWidth = 80.0;
    const itemHeight = 116.0; // 约3:4比例，统一高度

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        height: itemHeight + 4, // 120总高度
        child: Listener(
          // 桌面端：鼠标滚轮转为横向滚动
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              // 将垂直滚轮事件转为横向滚动
              final newOffset = scrollController.offset + event.scrollDelta.dy;
              if (newOffset >= 0 &&
                  newOffset <= scrollController.position.maxScrollExtent) {
                scrollController.jumpTo(newOffset);
              }
            }
          },
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
              },
            ),
            child: ListView.separated(
              controller: scrollController,
              scrollDirection: Axis.horizontal,
              physics: const AlwaysScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: itemCount,
              separatorBuilder: (context, index) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final thumbUrl = imageThumbUrls[index];
                // 判断当前图片是否为实况图
                final hasLivePhoto = isLivePhotoType &&
                    index < livePhotoUrls.length &&
                    livePhotoUrls[index].isNotEmpty;
                final isDownloading = singleDownloading[index] == true;
                final progress = singleProgress[index];
                final isDone = (progress ?? 0) >= 0.99;

                return Stack(
                  children: [
                    // 缩略图
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: itemWidth,
                        height: itemHeight,
                        child: Image.network(
                          thumbUrl,
                          fit: BoxFit.cover,
                          headers: thumbUrl.contains('xhscdn.com')
                              ? const {
                                  'Referer': 'https://www.xiaohongshu.com/',
                                }
                              : null,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              color: Colors.grey.shade200,
                              child: const Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Colors.grey.shade300,
                              child: const Icon(
                                Icons.broken_image,
                                color: Colors.grey,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    // Live Photo 标识（右上角）- 仅显示在实况图上
                    if (hasLivePhoto)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(179),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.videocam,
                                size: 10,
                                color: Colors.white,
                              ),
                              SizedBox(width: 2),
                              Text(
                                'LIVE',
                                style: TextStyle(
                                  fontSize: 8,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    // 下载按钮（底部中央）
                    Positioned(
                      bottom: 4,
                      left: 4,
                      right: 4,
                      child: SizedBox(
                        height: 24,
                        child: ElevatedButton(
                          onPressed: isDownloading || isDone
                              ? null
                              : () => hasLivePhoto
                                    ? onDownloadLivePhoto(index)
                                    : onDownloadImage(index),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDone
                                ? Colors.green
                                : Colors.black.withAlpha(179),
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          child: isDownloading
                              ? SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    value: progress != null &&
                                            progress > 0 &&
                                            progress < 1
                                        ? progress
                                        : null,
                                    color: Colors.white,
                                  ),
                                )
                              : isDone
                                  ? const Icon(Icons.check, size: 14)
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.download,
                                          size: 12,
                                        ),
                                        const SizedBox(width: 2),
                                        Text(
                                          hasLivePhoto ? 'MP4' : '图片',
                                          style: const TextStyle(fontSize: 10),
                                        ),
                                      ],
                                    ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
