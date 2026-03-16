import '../services/parser_common.dart';

/// 视频解析状态
///
/// 包含解析过程中的所有状态信息：
/// - [parsing]: 是否正在解析
/// - [videoInfo]: 解析成功后的视频信息
/// - [fileSizeBytes]: 视频文件大小（仅视频类型）
/// - [fetchingSize]: 是否正在获取文件大小
/// - [error]: 解析错误信息
class VideoState {
  /// 是否正在解析中
  final bool parsing;

  /// 解析后的视频信息，null 表示尚未解析或解析失败
  final VideoInfo? videoInfo;

  /// 视频文件大小（字节），仅对视频类型有效
  final int? fileSizeBytes;

  /// 是否正在获取文件大小
  final bool fetchingSize;

  /// 解析错误信息，null 表示无错误
  final String? error;

  const VideoState({
    this.parsing = false,
    this.videoInfo,
    this.fileSizeBytes,
    this.fetchingSize = false,
    this.error,
  });

  /// 初始状态：未解析
  const VideoState.initial()
      : parsing = false,
        videoInfo = null,
        fileSizeBytes = null,
        fetchingSize = false,
        error = null;

  /// 创建正在解析的状态
  VideoState copyWithParsing() => VideoState(
        parsing: true,
        videoInfo: null,
        fileSizeBytes: null,
        fetchingSize: false,
        error: null,
      );

  /// 创建解析成功的状态
  VideoState copyWithSuccess(VideoInfo info) => VideoState(
        parsing: false,
        videoInfo: info,
        fileSizeBytes: null,
        fetchingSize: false,
        error: null,
      );

  /// 创建解析失败的状态
  VideoState copyWithError(String error) => VideoState(
        parsing: false,
        videoInfo: null,
        fileSizeBytes: null,
        fetchingSize: false,
        error: error,
      );

  /// 更新文件大小信息
  VideoState copyWithFileSize(int? size, {bool fetching = false}) => VideoState(
        parsing: parsing,
        videoInfo: videoInfo,
        fileSizeBytes: size,
        fetchingSize: fetching,
        error: error,
      );

  /// 清除错误信息
  VideoState clearError() => VideoState(
        parsing: parsing,
        videoInfo: videoInfo,
        fileSizeBytes: fileSizeBytes,
        fetchingSize: fetchingSize,
        error: null,
      );

  /// 重置为初始状态
  VideoState reset() => const VideoState.initial();

  @override
  String toString() {
    return 'VideoState(parsing: $parsing, videoInfo: ${videoInfo?.itemId}, '
        'fileSizeBytes: $fileSizeBytes, fetchingSize: $fetchingSize, error: $error)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VideoState &&
        other.parsing == parsing &&
        other.videoInfo == videoInfo &&
        other.fileSizeBytes == fileSizeBytes &&
        other.fetchingSize == fetchingSize &&
        other.error == error;
  }

  @override
  int get hashCode {
    return Object.hash(parsing, videoInfo, fileSizeBytes, fetchingSize, error);
  }
}
