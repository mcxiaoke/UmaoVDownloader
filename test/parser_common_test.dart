import 'package:flutter_test/flutter_test.dart';
import 'package:umao_vdownloader/services/parser_common.dart';
import 'package:umao_vdownloader/services/url_extractor.dart';

void main() {
  group('UrlExtractor', () {
    test('提取单个链接', () {
      const text = '打开抖音 https://v.douyin.com/abc123/ 复制此链接';
      final url = UrlExtractor.extractFirst(text);
      expect(url, 'https://v.douyin.com/abc123/');
    });

    test('提取多个链接', () {
      const text = '第一个 https://v.douyin.com/abc/ 第二个 https://xhslink.com/xyz';
      final urls = UrlExtractor.extractAll(text);
      expect(urls, hasLength(2));
      expect(urls[0], 'https://v.douyin.com/abc/');
      expect(urls[1], 'https://xhslink.com/xyz');
    });

    test('清理末尾标点', () {
      const text = '链接 https://v.douyin.com/abc/。';
      final url = UrlExtractor.extractFirst(text);
      expect(url, 'https://v.douyin.com/abc/');
    });

    test('中文标点后停止', () {
      const text = '链接 https://v.douyin.com/abc/，后面是中文';
      final url = UrlExtractor.extractFirst(text);
      expect(url, 'https://v.douyin.com/abc/');
    });

    test('无链接返回null', () {
      const text = '没有链接的文本';
      final url = UrlExtractor.extractFirst(text);
      expect(url, isNull);
    });
  });

  group('JsonExtractor', () {
    test('提取简单JSON对象', () {
      const html = '''
        <script>
        window._ROUTER_DATA = {"name": "test", "value": 123};
        </script>
      ''';
      final json = JsonExtractor.extractJsonObject(html, 'window._ROUTER_DATA = ');
      expect(json, isNotNull);
      expect(json!['name'], 'test');
      expect(json['value'], 123);
    });

    test('提取嵌套JSON对象', () {
      const html = '''
        <script>
        var data = {"user": {"name": "Alice", "age": 30}};
        </script>
      ''';
      final json = JsonExtractor.extractJsonObject(html, 'var data = ');
      expect(json, isNotNull);
      expect(json!['user'], isMap);
      expect(json['user']['name'], 'Alice');
    });

    test('处理undefined替换为null', () {
      const html = '''
        <script>
        var data = {"value": undefined, "list": [undefined, 1]};
        </script>
      ''';
      final json = JsonExtractor.extractJsonObject(
        html,
        'var data = ',
        cleanUndefined: true,
      );
      expect(json, isNotNull);
      expect(json!['value'], isNull);
      expect(json['list'][0], isNull);
      expect(json['list'][1], 1);
    });

    test('使用正则提取JSON', () {
      const html = '''
        <script id="__NEXT_DATA__">{"page": "home", "props": {}}</script>
      ''';
      final result = JsonExtractor.extractJsonWithRegex(
        html,
        r'<script id="__NEXT_DATA__">([\s\S]*?)</script>',
      );
      expect(result.data, isNotNull);
      expect(result.data!['page'], 'home');
    });
  });

  group('VideoInfo', () {
    test('创建VideoInfo实例', () {
      final info = VideoInfo(
        itemId: '123',
        title: '测试视频',
        videoFileId: 'v0200fg10000',
        videoUrl: 'https://example.com/video.mp4',
        mediaType: MediaType.video,
        platform: ParserPlatform.douyin,
      );
      expect(info.itemId, '123');
      expect(info.title, '测试视频');
      expect(info.mediaType, MediaType.video);
      expect(info.platform, ParserPlatform.douyin);
    });

    test('从JSON创建VideoInfo', () {
      final json = {
        'id': '123',
        'title': '测试视频',
        'videoUrl': 'https://example.com/video.mp4?video_id=v0200fg10000',
        'type': 'video',
        'platform': 'douyin',
        'coverUrl': 'https://example.com/cover.jpg',
        'width': '1920',
        'height': '1080',
      };
      final info = VideoInfo.fromJson(json);
      expect(info.itemId, '123');
      expect(info.title, '测试视频');
      expect(info.videoFileId, 'v0200fg10000');
      expect(info.mediaType, MediaType.video);
      expect(info.platform, ParserPlatform.douyin);
      expect(info.width, 1920);
      expect(info.height, 1080);
    });

    test('分辨率标签计算', () {
      final info1 = VideoInfo(
        itemId: '1',
        title: '4K视频',
        videoFileId: 'vid',
        videoUrl: 'url',
        mediaType: MediaType.video,
        platform: ParserPlatform.douyin,
        width: 3840,
        height: 2160,
      );
      expect(info1.resolutionLabel, '3840×2160 (4K)');

      final info2 = VideoInfo(
        itemId: '2',
        title: '2K视频',
        videoFileId: 'vid',
        videoUrl: 'url',
        mediaType: MediaType.video,
        platform: ParserPlatform.douyin,
        width: 2560,
        height: 1440,
      );
      expect(info2.resolutionLabel, '2560×1440 (2K)');

      final info3 = VideoInfo(
        itemId: '3',
        title: '1080p视频',
        videoFileId: 'vid',
        videoUrl: 'url',
        mediaType: MediaType.video,
        platform: ParserPlatform.douyin,
        width: 1920,
        height: 1080,
      );
      expect(info3.resolutionLabel, '1920×1080');
    });

    test('图片URL列表解析', () {
      final json = {
        'id': '123',
        'title': '图文',
        'videoUrl': '',
        'type': 'image',
        'platform': 'douyin',
        'imageUrls': ['url1', 'url2'],
      };
      final info = VideoInfo.fromJson(json);
      expect(info.imageUrls, hasLength(2));
      expect(info.imageUrls[0], 'url1');
      expect(info.mediaType, MediaType.image);
    });

    test('实况图URL列表解析', () {
      final json = {
        'id': '123',
        'title': '实况图',
        'videoUrl': '',
        'type': 'livephoto',
        'platform': 'xiaohongshu',
        'livePhotoUrls': ['', 'video2', ''],
      };
      final info = VideoInfo.fromJson(json);
      expect(info.livePhotoUrls, hasLength(3));
      expect(info.livePhotoUrls[0], '');
      expect(info.livePhotoUrls[1], 'video2');
      expect(info.mediaType, MediaType.livePhoto);
    });
  });

  group('ParserPlatform', () {
    test('从URL识别平台', () {
      expect(ParserPlatform.fromUrl('https://v.douyin.com/abc'), ParserPlatform.douyin);
      expect(ParserPlatform.fromUrl('https://www.douyin.com/video'), ParserPlatform.douyin);
      expect(ParserPlatform.fromUrl('https://xiaohongshu.com/note'), ParserPlatform.xiaohongshu);
      expect(ParserPlatform.fromUrl('https://xhslink.com/xyz'), ParserPlatform.xiaohongshu);
      expect(ParserPlatform.fromUrl('https://unknown.com'), ParserPlatform.unknown);
    });

    test('文件名前缀', () {
      expect(ParserPlatform.douyin.filePrefix, 'DY_');
      expect(ParserPlatform.xiaohongshu.filePrefix, 'XHS_');
      expect(ParserPlatform.unknown.filePrefix, '');
    });
  });

  group('VideoQuality', () {
    test('从字符串解析', () {
      expect(VideoQuality.fromRatio('720p'), VideoQuality.p720);
      expect(VideoQuality.fromRatio('1080p'), VideoQuality.p1080);
      expect(VideoQuality.fromRatio('2160p'), VideoQuality.p2160);
      expect(VideoQuality.fromRatio('480p'), isNull);
    });

    test('枚举值转字符串', () {
      expect(VideoQuality.p720.toString(), '720p');
      expect(VideoQuality.p1080.toString(), '1080p');
    });
  });
}