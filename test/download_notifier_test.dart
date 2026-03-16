import 'package:flutter_test/flutter_test.dart';
import 'package:umao_vdownloader/providers/download_notifier.dart';
import 'package:umao_vdownloader/providers/download_state.dart';
import 'package:umao_vdownloader/providers/video_state.dart';
import 'package:umao_vdownloader/services/parser_common.dart';

void main() {
  group('DownloadState 类', () {
    test('初始状态', () {
      const state = DownloadState.initial();
      expect(state.downloading, false);
      expect(state.downloadProgress, isNull);
      expect(state.downloadingMusic, false);
      expect(state.downloadingLiveVideos, false);
      expect(state.liveVideoProgress, isNull);
      expect(state.singleDownloads, isEmpty);
    });

    test('copyWithStartDownload 开始下载', () {
      const state = DownloadState.initial();
      final newState = state.copyWithStartDownload();
      expect(newState.downloading, true);
      expect(newState.downloadProgress, 0.0);
      expect(newState.lastVerboseProgressBucket, isNull);
    });

    test('copyWithDownloadProgress 更新进度', () {
      const state = DownloadState.initial();
      final newState = state.copyWithDownloadProgress(0.5, verboseBucket: 5);
      expect(newState.downloadProgress, 0.5);
      expect(newState.lastVerboseProgressBucket, 5);
    });

    test('copyWithDownloadComplete 下载完成', () {
      const state = DownloadState.initial();
      final newState = state.copyWithDownloadComplete();
      expect(newState.downloading, false);
      expect(newState.downloadProgress, 1.0);
    });

    test('copyWithStartSingleDownload 开始单个下载', () {
      const state = DownloadState.initial();
      final newState = state.copyWithStartSingleDownload(0);
      expect(newState.singleDownloads, hasLength(1));
      expect(newState.singleDownloads[0]?.downloading, true);
      expect(newState.singleDownloads[0]?.progress, 0.0);
    });

    test('copyWithSingleProgress 更新单个下载进度', () {
      const state = DownloadState.initial();
      final startedState = state.copyWithStartSingleDownload(0);
      final progressedState = startedState.copyWithSingleProgress(0, 0.75);
      expect(progressedState.singleDownloads[0]?.progress, 0.75);
      expect(progressedState.singleDownloads[0]?.downloading, true);
    });

    test('copyWithSingleComplete 单个下载完成', () {
      const state = DownloadState.initial();
      final startedState = state.copyWithStartSingleDownload(0);
      final completedState = startedState.copyWithSingleComplete(0);
      expect(completedState.singleDownloads[0]?.progress, 1.0);
      expect(completedState.singleDownloads[0]?.downloading, false);
      expect(completedState.singleDownloads[0]?.done, true);
    });

    test('copyWithSingleFailed 单个下载失败', () {
      const state = DownloadState.initial();
      final startedState = state.copyWithStartSingleDownload(0);
      final failedState = startedState.copyWithSingleFailed(0);
      expect(failedState.singleDownloads, isEmpty);
    });

    test('removeSingleProgress 移除单个下载进度', () {
      const state = DownloadState.initial();
      final startedState = state.copyWithStartSingleDownload(0);
      final completedState = startedState.copyWithSingleComplete(0);
      final removedState = completedState.removeSingleProgress(0);
      expect(removedState.singleDownloads[0]?.done, true);
      expect(removedState.singleDownloads[0]?.progress, 0.0);
      expect(removedState.singleDownloads[0]?.downloading, false);
    });

    test('便捷 getter 方法', () {
      const state = DownloadState.initial();
      final startedState = state.copyWithStartSingleDownload(0);
      final progressedState = startedState.copyWithSingleProgress(0, 0.5);

      expect(progressedState.getSingleProgress(0), 0.5);
      expect(progressedState.isSingleDownloading(0), true);
      expect(progressedState.isSingleDone(0), false);

      expect(progressedState.getSingleProgress(1), isNull);
      expect(progressedState.isSingleDownloading(1), false);
    });

    test('singleProgressMap 映射', () {
      const state = DownloadState.initial();
      final newState = state.copyWithStartSingleDownload(0);
      final progressedState = newState.copyWithSingleProgress(0, 0.3);
      final map = progressedState.singleProgressMap;
      expect(map[0], 0.3);
    });

    test('reset 重置状态', () {
      const state = DownloadState(
        downloading: true,
        downloadProgress: 0.5,
        downloadingMusic: true,
        downloadingLiveVideos: true,
        liveVideoProgress: 0.3,
        singleDownloads: {0: SingleDownloadState(progress: 0.8, downloading: true)},
      );
      final resetState = state.reset();
      expect(resetState, const DownloadState.initial());
    });
  });

  group('SingleDownloadState 类', () {
    test('初始状态', () {
      const state = SingleDownloadState.initial();
      expect(state.progress, 0.0);
      expect(state.downloading, false);
      expect(state.done, false);
    });

    test('copyWithDownloading 开始下载', () {
      const state = SingleDownloadState.initial();
      final newState = state.copyWithDownloading(progress: 0.2);
      expect(newState.progress, 0.2);
      expect(newState.downloading, true);
      expect(newState.done, false);
    });

    test('copyWithDone 下载完成', () {
      const state = SingleDownloadState.initial();
      final newState = state.copyWithDone();
      expect(newState.progress, 1.0);
      expect(newState.downloading, false);
      expect(newState.done, true);
    });
  });

  group('DownloadResult 类', () {
    test('成功结果', () {
      final result = DownloadResult.success(path: '/path/to/file');
      expect(result.type, DownloadResultType.success);
      expect(result.path, '/path/to/file');
      expect(result.isSuccess, true);
      expect(result.shouldShowPermissionDialog, false);
    });

    test('批量下载成功', () {
      final result = DownloadResult.success(
        path: '/download/dir',
        isBatch: true,
        count: 5,
      );
      expect(result.isBatch, true);
      expect(result.count, 5);
    });

    test('单个下载成功', () {
      final result = DownloadResult.success(path: '/path/to/file', index: 2);
      expect(result.index, 2);
    });

    test('错误结果', () {
      final result = DownloadResult.error('下载失败', index: 1);
      expect(result.type, DownloadResultType.error);
      expect(result.errorMessage, '下载失败');
      expect(result.index, 1);
      expect(result.isSuccess, false);
    });

    test('预定义结果类型', () {
      expect(DownloadResult.noVideoInfo.type, DownloadResultType.noVideoInfo);
      expect(DownloadResult.noMusic.type, DownloadResultType.noMusic);
      expect(DownloadResult.noLiveVideos.type, DownloadResultType.noLiveVideos);
      expect(DownloadResult.alreadyDownloading.type, DownloadResultType.alreadyDownloading);
      expect(DownloadResult.permissionDenied.type, DownloadResultType.permissionDenied);
    });

    test('权限被拒对话框显示', () {
      expect(DownloadResult.permissionDenied.shouldShowPermissionDialog, true);
      expect(DownloadResult.noVideoInfo.shouldShowPermissionDialog, false);
    });
  });
}