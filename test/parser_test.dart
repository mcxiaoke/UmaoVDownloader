import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:umao_vdownloader/services/parser_common.dart';

/// 测试缓存目录（相对于项目根目录）
const cacheDir = 'backend/tests/cache';

void main() {
  group('Douyin Parser Tests (Local Cache)', () {
    test('视频：等三秒', () async {
      final json = await _readCache('dy_KbpvKx0EIEY.json');
      final item = jsonDecode(json) as Map<String, dynamic>;

      expect(item['aweme_type'], equals(4)); // 视频类型
      expect(item['desc'], contains('等三秒'));
      expect(item['author']?['nickname'], equals('么凹猫 ੭'));
      expect(item['video']?['play_addr'], isNotNull);
    });

    test('视频：长视频 - 撒哈拉', () async {
      final json = await _readCache('dy_maVLO1IQhXI.json');
      final item = jsonDecode(json) as Map<String, dynamic>;

      expect(item['aweme_type'], equals(4));
      expect(item['desc'], contains('深入撒哈拉地底'));
      expect(item['author']?['nickname'], equals('老马哄睡宇宙'));

      final duration = (item['video']?['duration'] as int?) ?? 0;
      expect(duration ~/ 1000, greaterThan(1000)); // 长视频 > 1000秒
    });

    test('图文：春日JK甜妹（6张图）', () async {
      final json = await _readCache('dy_4YVImZUFrHQ.json');
      final item = jsonDecode(json) as Map<String, dynamic>;

      expect(item['aweme_type'], equals(2)); // 图文类型
      expect(item['desc'], contains('杳杳春时来'));
      expect(item['images'], isA<List>());
      expect((item['images'] as List).length, equals(6));
    });

    test('图文：穿搭分享（4张图）', () async {
      final json = await _readCache('dy_Emsjx8zX81k.json');
      final item = jsonDecode(json) as Map<String, dynamic>;

      expect(item['aweme_type'], equals(2));
      expect(item['images'], isA<List>());
      expect((item['images'] as List).length, equals(4));
    });
  });

  group('Xiaohongshu Parser Tests (Local Cache)', () {
    test('视频：cos流萤', () async {
      final json = await _readCache('xhs_5NUDXVKC8Pm.json');
      final note = jsonDecode(json) as Map<String, dynamic>;

      expect(note['type'], equals('video'));
      expect(note['title'], contains('白菜对我笑'));
      expect(note['user']?['nickName'], equals('是月辉大人🌙'));
      expect(note['video']?['media']?['stream'], isNotNull);
    });

    test('视频：MMD爻光', () async {
      final json = await _readCache('xhs_5PFClcBVSjg.json');
      final note = jsonDecode(json) as Map<String, dynamic>;

      expect(note['type'], equals('video'));
      expect(note['title'], contains('爻老板'));
    });

    test('实况图：秋冬幸福小记（7张图，1张实况）', () async {
      final json = await _readCache('xhs_1YCJtCHOnmf.json');
      final note = jsonDecode(json) as Map<String, dynamic>;

      expect(note['type'], equals('normal'));
      expect(note['title'], contains('用live实况打开'));

      final images = note['imageList'] as List;
      expect(images.length, equals(7));

      final livePhotos = images.where((img) => img['livePhoto'] == true);
      expect(livePhotos.length, equals(1));
    });

    test('静态图：明日方舟终末地（3张图）', () async {
      final json = await _readCache('xhs_5VgHFbkL9Ou.json');
      final note = jsonDecode(json) as Map<String, dynamic>;

      expect(note['type'], equals('normal'));
      final images = note['imageList'] as List;
      expect(images.length, equals(3));

      // 没有实况图
      final livePhotos = images.where((img) => img['livePhoto'] == true);
      expect(livePhotos.length, equals(0));
    });
  });
}

Future<String> _readCache(String filename) async {
  final file = File('$cacheDir/$filename');
  if (!await file.exists()) {
    throw Exception('Cache file not found: $cacheDir/$filename');
  }
  return file.readAsString();
}
