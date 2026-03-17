import 'package:flutter/material.dart';

import '../../services/parser_common.dart';
import 'download_actions.dart';
import 'thumbnail_grid.dart';
import 'video_cover.dart';

/// 解析结果卡片
class ResultCard extends StatelessWidget {
  const ResultCard({
    super.key,
    required this.videoInfo,
    required this.onDownload,
    required this.onDownloadMusic,
    required this.onDownloadLiveVideos,
    required this.onDownloadImage,
    required this.onDownloadLivePhoto,
    required this.downloading,
    required this.downloadProgress,
    required this.downloadingMusic,
    required this.downloadingLiveVideos,
    required this.liveVideoProgress,
    required this.singleProgressMap,
    required this.singleDownloadingMap,
    required this.singleDoneMap,
    required this.fetchingSize,
    required this.fileSizeBytes,
    this.scrollController,
  });

  final VideoInfo videoInfo;
  final VoidCallback onDownload;
  final VoidCallback onDownloadMusic;
  final VoidCallback onDownloadLiveVideos;
  final void Function(int index) onDownloadImage;
  final void Function(int index) onDownloadLivePhoto;
  final bool downloading;
  final double? downloadProgress;
  final bool downloadingMusic;
  final bool downloadingLiveVideos;
  final double? liveVideoProgress;
  final Map<int, double> singleProgressMap;
  final Map<int, bool> singleDownloadingMap;
  final Map<int, bool> singleDoneMap;
  final bool fetchingSize;
  final int? fileSizeBytes;
  final ScrollController? scrollController;

  /// 默认滚动控制器（用于 scrollController 为空时）
  static final _defaultScrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 400;
        return Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 标题（可复制，截断到80字符）
                SelectableText(
                  _truncateTitle(videoInfo.title),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _buildMetaInfo(videoInfo),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                // 封面图/缩略图
                if (videoInfo.mediaType != MediaType.video &&
                    videoInfo.imageUrls.isNotEmpty)
                  ThumbnailGrid(
                    videoInfo: videoInfo,
                    scrollController: scrollController ?? _defaultScrollController,
                    singleProgress: singleProgressMap,
                    singleDownloading: singleDownloadingMap,
                    singleDone: singleDoneMap,
                    onDownloadImage: onDownloadImage,
                    onDownloadLivePhoto: onDownloadLivePhoto,
                  ),
                // 普通视频显示封面
                if (videoInfo.mediaType == MediaType.video &&
                    videoInfo.coverUrl != null)
                  VideoCover(coverUrl: videoInfo.coverUrl!),
                const SizedBox(height: 12),
                // 操作区
                if (narrow)
                  DownloadActionsNarrow(
                    videoInfo: videoInfo,
                    downloading: downloading,
                    downloadProgress: downloadProgress,
                    downloadingMusic: downloadingMusic,
                    downloadingLiveVideos: downloadingLiveVideos,
                    liveVideoProgress: liveVideoProgress,
                    fileSizeBytes: fileSizeBytes,
                    fetchingSize: fetchingSize,
                    onDownload: onDownload,
                    onDownloadMusic: onDownloadMusic,
                    onDownloadLiveVideos: onDownloadLiveVideos,
                  )
                else
                  DownloadActionsWide(
                    videoInfo: videoInfo,
                    downloading: downloading,
                    downloadProgress: downloadProgress,
                    downloadingMusic: downloadingMusic,
                    downloadingLiveVideos: downloadingLiveVideos,
                    liveVideoProgress: liveVideoProgress,
                    fileSizeBytes: fileSizeBytes,
                    fetchingSize: fetchingSize,
                    onDownload: onDownload,
                    onDownloadMusic: onDownloadMusic,
                    onDownloadLiveVideos: onDownloadLiveVideos,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 截断标题到指定长度（默认80字符）
  String _truncateTitle(String title, [int maxLen = 80]) {
    final text = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length <= maxLen) return text;
    return '${text.substring(0, maxLen)}...';
  }

  /// 构建元信息文本：ID · 类型 · 数量
  String _buildMetaInfo(VideoInfo info) {
    final id = info.shareId ?? info.itemId;
    final (type, count) = switch (info.mediaType) {
      MediaType.image => ('图文', '${info.imageUrls.length}'),
      MediaType.livePhoto => ('实况图', '${info.livePhotoUrls.length}'),
      MediaType.video => ('视频', '1'),
    };
    return 'ID: $id · 类型: $type · 数量: $count';
  }
}

/// 空结果占位
class EmptyResultPlaceholder extends StatelessWidget {
  const EmptyResultPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 280,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(
        child: Text('解析结果将显示在这里', style: TextStyle(color: Colors.grey)),
      ),
    );
  }
}

/// 加载中占位
class LoadingPlaceholder extends StatelessWidget {
  const LoadingPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 280,
      child: Center(child: CircularProgressIndicator()),
    );
  }
}
