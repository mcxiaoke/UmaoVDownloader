import 'package:flutter_test/flutter_test.dart';
import 'package:umao_vdownloader/providers/video_notifier.dart';
import 'package:umao_vdownloader/providers/video_state.dart';
import 'package:umao_vdownloader/services/parser_common.dart';

void main() {
  group('VideoState 类', () {
    test('初始状态', () {
      const state = VideoState.initial();
      expect(state.parsing, false);
      expect(state.videoInfo, isNull);
      expect(state.fileSizeBytes, isNull);
      expect(state.fetchingSize, false);
      expect(state.error, isNull);
    });

    test('copyWithParsing 创建解析中状态', () {
      const state = VideoState.initial();
      final parsingState = state.copyWithParsing();
      expect(parsingState.parsing, true);
      expect(parsingState.videoInfo, isNull);
      expect(parsingState.error, isNull);
    });

    test('copyWithSuccess 创建解析成功状态', () {
      const state = VideoState.initial();
      final videoInfo = VideoInfo(
        itemId: '123',
        title: '测试视频',
        videoFileId: 'v0200fg10000',
        videoUrl: 'https://example.com/video.mp4',
        mediaType: MediaType.video,
        platform: ParserPlatform.douyin,
      );
      final successState = state.copyWithSuccess(videoInfo);
      expect(successState.parsing, false);
      expect(successState.videoInfo, videoInfo);
      expect(successState.error, isNull);
    });

    test('copyWithError 创建解析失败状态', () {
      const state = VideoState.initial();
      final errorState = state.copyWithError('解析失败');
      expect(errorState.parsing, false);
      expect(errorState.videoInfo, isNull);
      expect(errorState.error, '解析失败');
    });

    test('copyWithFileSize 更新文件大小', () {
      const state = VideoState.initial();
      final sizeState = state.copyWithFileSize(1024 * 1024);
      expect(sizeState.fileSizeBytes, 1024 * 1024);
      expect(sizeState.fetchingSize, false);

      final fetchingState = state.copyWithFileSize(null, fetching: true);
      expect(fetchingState.fetchingSize, true);
    });

    test('clearError 清除错误信息', () {
      const state = VideoState(error: '错误信息');
      final clearedState = state.clearError();
      expect(clearedState.error, isNull);
    });

    test('reset 重置为初始状态', () {
      const state = VideoState(
        parsing: true,
        error: '错误',
        fileSizeBytes: 1000,
        fetchingSize: true,
      );
      final resetState = state.reset();
      expect(resetState, const VideoState.initial());
    });

    test('相等性判断', () {
      const state1 = VideoState(parsing: true, error: 'err');
      const state2 = VideoState(parsing: true, error: 'err');
      const state3 = VideoState(parsing: false, error: 'err');
      expect(state1, state2);
      expect(state1, isNot(state3));
    });
  });

  group('ParseResult 类', () {
    test('成功结果', () {
      final videoInfo = VideoInfo(
        itemId: '123',
        title: '测试视频',
        videoFileId: 'vid',
        videoUrl: 'url',
        mediaType: MediaType.video,
        platform: ParserPlatform.douyin,
      );
      final result = ParseResult.success(videoInfo);
      expect(result.type, ParseResultType.success);
      expect(result.videoInfo, videoInfo);
      expect(result.isSuccess, true);
      expect(result.shouldShowErrorSnack, false);
    });

    test('错误结果', () {
      final result = ParseResult.error('解析失败');
      expect(result.type, ParseResultType.error);
      expect(result.errorMessage, '解析失败');
      expect(result.isSuccess, false);
      expect(result.shouldShowErrorSnack, true);
    });

    test('预定义结果类型', () {
      expect(ParseResult.empty.type, ParseResultType.empty);
      expect(ParseResult.invalidUrl.type, ParseResultType.invalidUrl);
      expect(ParseResult.unsupportedPlatform.type, ParseResultType.unsupportedPlatform);
    });

    test('shouldShowErrorSnack 判断', () {
      expect(ParseResult.empty.shouldShowErrorSnack, false);
      expect(ParseResult.invalidUrl.shouldShowErrorSnack, true);
      expect(ParseResult.unsupportedPlatform.shouldShowErrorSnack, true);
      expect(ParseResult.error('test').shouldShowErrorSnack, true);
    });
  });
}