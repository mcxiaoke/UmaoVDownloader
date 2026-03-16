/// 单个下载项的状态
///
/// 用于追踪单个图片或视频的下载进度。
class SingleDownloadState {
  /// 下载进度 (0.0 - 1.0)
  final double progress;

  /// 是否正在下载中
  final bool downloading;

  /// 是否已完成
  final bool done;

  const SingleDownloadState({
    this.progress = 0.0,
    this.downloading = false,
    this.done = false,
  });

  /// 初始状态：未开始下载
  const SingleDownloadState.initial()
      : progress = 0.0,
        downloading = false,
        done = false;

  /// 创建下载中的状态
  SingleDownloadState copyWithDownloading({double? progress}) =>
      SingleDownloadState(
        progress: progress ?? this.progress,
        downloading: true,
        done: false,
      );

  /// 创建完成状态
  SingleDownloadState copyWithDone() => const SingleDownloadState(
        progress: 1.0,
        downloading: false,
        done: true,
      );

  @override
  String toString() =>
      'SingleDownloadState(progress: $progress, downloading: $downloading, done: $done)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SingleDownloadState &&
        other.progress == progress &&
        other.downloading == downloading &&
        other.done == done;
  }

  @override
  int get hashCode => Object.hash(progress, downloading, done);
}

/// 下载状态
///
/// 包含所有下载相关的状态信息：
/// - [downloading]: 主下载任务是否进行中
/// - [downloadProgress]: 主下载任务进度
/// - [downloadingMusic]: 音乐下载是否进行中
/// - [downloadingLiveVideos]: 动图视频批量下载是否进行中
/// - [liveVideoProgress]: 动图视频批量下载进度
/// - [singleDownloads]: 单个下载项的状态映射（索引 -> 状态）
class DownloadState {
  /// 主下载任务是否进行中
  final bool downloading;

  /// 主下载任务进度 (0.0 - 1.0)，null 表示未开始或已完成
  final double? downloadProgress;

  /// 音乐下载是否进行中
  final bool downloadingMusic;

  /// 动图视频批量下载是否进行中
  final bool downloadingLiveVideos;

  /// 动图视频批量下载进度 (0.0 - 1.0)
  final double? liveVideoProgress;

  /// 单个下载项的状态映射
  /// key: 图片/视频索引
  /// value: 该索引对应的下载状态
  final Map<int, SingleDownloadState> singleDownloads;

  /// 用于详细日志的进度分桶值（避免重复输出日志）
  final int? lastVerboseProgressBucket;

  const DownloadState({
    this.downloading = false,
    this.downloadProgress,
    this.downloadingMusic = false,
    this.downloadingLiveVideos = false,
    this.liveVideoProgress,
    this.singleDownloads = const {},
    this.lastVerboseProgressBucket,
  });

  /// 初始状态：无下载任务
  const DownloadState.initial()
      : downloading = false,
        downloadProgress = null,
        downloadingMusic = false,
        downloadingLiveVideos = false,
        liveVideoProgress = null,
        singleDownloads = const {},
        lastVerboseProgressBucket = null;

  /// 创建开始主下载的状态
  DownloadState copyWithStartDownload() => DownloadState(
        downloading: true,
        downloadProgress: 0.0,
        downloadingMusic: downloadingMusic,
        downloadingLiveVideos: downloadingLiveVideos,
        liveVideoProgress: liveVideoProgress,
        singleDownloads: singleDownloads,
        lastVerboseProgressBucket: null,
      );

  /// 更新主下载进度
  DownloadState copyWithDownloadProgress(double? progress,
          {int? verboseBucket}) =>
      DownloadState(
        downloading: downloading,
        downloadProgress: progress,
        downloadingMusic: downloadingMusic,
        downloadingLiveVideos: downloadingLiveVideos,
        liveVideoProgress: liveVideoProgress,
        singleDownloads: singleDownloads,
        lastVerboseProgressBucket: verboseBucket ?? lastVerboseProgressBucket,
      );

  /// 主下载完成
  DownloadState copyWithDownloadComplete() => DownloadState(
        downloading: false,
        downloadProgress: 1.0,
        downloadingMusic: downloadingMusic,
        downloadingLiveVideos: downloadingLiveVideos,
        liveVideoProgress: liveVideoProgress,
        singleDownloads: singleDownloads,
        lastVerboseProgressBucket: lastVerboseProgressBucket,
      );

  /// 主下载失败
  DownloadState copyWithDownloadFailed() => DownloadState(
        downloading: false,
        downloadProgress: null,
        downloadingMusic: downloadingMusic,
        downloadingLiveVideos: downloadingLiveVideos,
        liveVideoProgress: liveVideoProgress,
        singleDownloads: singleDownloads,
        lastVerboseProgressBucket: lastVerboseProgressBucket,
      );

  /// 开始音乐下载
  DownloadState copyWithStartMusic() => DownloadState(
        downloading: downloading,
        downloadProgress: downloadProgress,
        downloadingMusic: true,
        downloadingLiveVideos: downloadingLiveVideos,
        liveVideoProgress: liveVideoProgress,
        singleDownloads: singleDownloads,
        lastVerboseProgressBucket: lastVerboseProgressBucket,
      );

  /// 音乐下载完成/失败
  DownloadState copyWithMusicComplete() => DownloadState(
        downloading: downloading,
        downloadProgress: downloadProgress,
        downloadingMusic: false,
        downloadingLiveVideos: downloadingLiveVideos,
        liveVideoProgress: liveVideoProgress,
        singleDownloads: singleDownloads,
        lastVerboseProgressBucket: lastVerboseProgressBucket,
      );

  /// 开始动图视频批量下载
  DownloadState copyWithStartLiveVideos() => DownloadState(
        downloading: downloading,
        downloadProgress: downloadProgress,
        downloadingMusic: downloadingMusic,
        downloadingLiveVideos: true,
        liveVideoProgress: 0.0,
        singleDownloads: singleDownloads,
        lastVerboseProgressBucket: null,
      );

  /// 更新动图视频下载进度
  DownloadState copyWithLiveVideoProgress(double? progress,
          {int? verboseBucket}) =>
      DownloadState(
        downloading: downloading,
        downloadProgress: downloadProgress,
        downloadingMusic: downloadingMusic,
        downloadingLiveVideos: downloadingLiveVideos,
        liveVideoProgress: progress,
        singleDownloads: singleDownloads,
        lastVerboseProgressBucket: verboseBucket ?? lastVerboseProgressBucket,
      );

  /// 动图视频下载完成
  DownloadState copyWithLiveVideoComplete() => DownloadState(
        downloading: downloading,
        downloadProgress: downloadProgress,
        downloadingMusic: downloadingMusic,
        downloadingLiveVideos: false,
        liveVideoProgress: 1.0,
        singleDownloads: singleDownloads,
        lastVerboseProgressBucket: lastVerboseProgressBucket,
      );

  /// 动图视频下载失败
  DownloadState copyWithLiveVideoFailed() => DownloadState(
        downloading: downloading,
        downloadProgress: downloadProgress,
        downloadingMusic: downloadingMusic,
        downloadingLiveVideos: false,
        liveVideoProgress: null,
        singleDownloads: singleDownloads,
        lastVerboseProgressBucket: lastVerboseProgressBucket,
      );

  /// 开始单个下载
  DownloadState copyWithStartSingleDownload(int index) {
    final newMap = Map<int, SingleDownloadState>.from(singleDownloads);
    newMap[index] = const SingleDownloadState(downloading: true, progress: 0.0);
    return DownloadState(
      downloading: downloading,
      downloadProgress: downloadProgress,
      downloadingMusic: downloadingMusic,
      downloadingLiveVideos: downloadingLiveVideos,
      liveVideoProgress: liveVideoProgress,
      singleDownloads: newMap,
      lastVerboseProgressBucket: lastVerboseProgressBucket,
    );
  }

  /// 更新单个下载进度
  DownloadState copyWithSingleProgress(int index, double progress) {
    final newMap = Map<int, SingleDownloadState>.from(singleDownloads);
    final current = newMap[index] ?? const SingleDownloadState.initial();
    newMap[index] = current.copyWithDownloading(progress: progress);
    return DownloadState(
      downloading: downloading,
      downloadProgress: downloadProgress,
      downloadingMusic: downloadingMusic,
      downloadingLiveVideos: downloadingLiveVideos,
      liveVideoProgress: liveVideoProgress,
      singleDownloads: newMap,
      lastVerboseProgressBucket: lastVerboseProgressBucket,
    );
  }

  /// 单个下载完成
  DownloadState copyWithSingleComplete(int index, {bool removeProgress = false}) {
    final newMap = Map<int, SingleDownloadState>.from(singleDownloads);
    newMap[index] = const SingleDownloadState(progress: 1.0, done: true);
    return DownloadState(
      downloading: downloading,
      downloadProgress: downloadProgress,
      downloadingMusic: downloadingMusic,
      downloadingLiveVideos: downloadingLiveVideos,
      liveVideoProgress: liveVideoProgress,
      singleDownloads: newMap,
      lastVerboseProgressBucket: lastVerboseProgressBucket,
    );
  }

  /// 单个下载失败
  DownloadState copyWithSingleFailed(int index) {
    final newMap = Map<int, SingleDownloadState>.from(singleDownloads);
    newMap.remove(index);
    return DownloadState(
      downloading: downloading,
      downloadProgress: downloadProgress,
      downloadingMusic: downloadingMusic,
      downloadingLiveVideos: downloadingLiveVideos,
      liveVideoProgress: liveVideoProgress,
      singleDownloads: newMap,
      lastVerboseProgressBucket: lastVerboseProgressBucket,
    );
  }

  /// 移除单个下载的进度显示
  DownloadState removeSingleProgress(int index) {
    final newMap = Map<int, SingleDownloadState>.from(singleDownloads);
    final current = newMap[index];
    if (current != null && current.done) {
      // 已完成的保留 done 标记，只清除进度
      newMap[index] = const SingleDownloadState(done: true);
    }
    return DownloadState(
      downloading: downloading,
      downloadProgress: downloadProgress,
      downloadingMusic: downloadingMusic,
      downloadingLiveVideos: downloadingLiveVideos,
      liveVideoProgress: liveVideoProgress,
      singleDownloads: newMap,
      lastVerboseProgressBucket: lastVerboseProgressBucket,
    );
  }

  /// 重置所有下载状态（新解析时调用）
  DownloadState reset() => const DownloadState.initial();

  // ─────────────────────────────────────────────────────────────────────
  // 便捷 getter（兼容现有 UI）
  // ─────────────────────────────────────────────────────────────────────

  /// 获取单个下载的进度
  double? getSingleProgress(int index) => singleDownloads[index]?.progress;

  /// 获取单个下载是否进行中
  bool isSingleDownloading(int index) =>
      singleDownloads[index]?.downloading ?? false;

  /// 获取单个下载是否已完成
  bool isSingleDone(int index) => singleDownloads[index]?.done ?? false;

  /// 获取所有单个下载的进度映射（兼容现有 UI）
  Map<int, double> get singleProgressMap =>
      {for (final e in singleDownloads.entries) e.key: e.value.progress};

  /// 获取所有正在下载的索引映射（兼容现有 UI）
  Map<int, bool> get singleDownloadingMap =>
      {for (final e in singleDownloads.entries) if (e.value.downloading) e.key: true};

  /// 获取所有已完成的索引映射（兼容现有 UI）
  Map<int, bool> get singleDoneMap =>
      {for (final e in singleDownloads.entries) if (e.value.done) e.key: true};

  @override
  String toString() {
    return 'DownloadState(downloading: $downloading, progress: $downloadProgress, '
        'music: $downloadingMusic, liveVideos: $downloadingLiveVideos, '
        'liveProgress: $liveVideoProgress, singles: ${singleDownloads.length})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DownloadState &&
        other.downloading == downloading &&
        other.downloadProgress == downloadProgress &&
        other.downloadingMusic == downloadingMusic &&
        other.downloadingLiveVideos == downloadingLiveVideos &&
        other.liveVideoProgress == liveVideoProgress &&
        _mapEquals(other.singleDownloads, singleDownloads) &&
        other.lastVerboseProgressBucket == lastVerboseProgressBucket;
  }

  @override
  int get hashCode {
    return Object.hash(
      downloading,
      downloadProgress,
      downloadingMusic,
      downloadingLiveVideos,
      liveVideoProgress,
      Object.hashAll(singleDownloads.entries),
      lastVerboseProgressBucket,
    );
  }

  static bool _mapEquals(Map<int, SingleDownloadState> a, Map<int, SingleDownloadState> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (a[key] != b[key]) return false;
    }
    return true;
  }
}
