# F2 抖音爬虫项目代码分析报告

> 分析对象: `temp/f2-main/f2/apps/douyin/` 目录下的核心代码
> 
> 分析时间: 2026-03-14
>
> 用途: 为本项目（DViewer）的抖音解析功能提供参考

## 目录

1. [项目概述](#1-项目概述)
2. [核心文件结构](#2-核心文件结构)
3. [关键发现](#3-关键发现)
4. [数据模型分析](#4-数据模型分析)
5. [视频/图文解析逻辑](#5-视频图文解析逻辑)
6. [URL 解析模式](#6-url-解析模式)
7. [加密算法](#7-加密算法)
8. [可借鉴的改进建议](#8-可借鉴的改进建议)

---

## 1. 项目概述

F2 是一个功能完善的抖音数据采集项目，采用 Python 异步架构，支持：
- 用户作品/喜欢/收藏列表获取
- 作品详情解析（视频 + 图文）
- 直播信息获取与弹幕监听
- 评论数据获取
- 完整的请求加密（XBogus/ABogus）

---

## 2. 核心文件结构

```
f2/apps/douyin/
├── __init__.py
├── api.py              # API 端点定义
├── crawler.py          # 爬虫核心类 (DouyinCrawler)
├── filter.py           # 数据过滤器/提取器
├── handler.py          # 数据处理逻辑
├── model.py            # 请求参数模型 (Pydantic)
├── utils.py            # 工具函数 (加密、URL解析等)
├── protobuf/           # Protobuf 定义文件
│   └── douyin_webcast_pb2.py
├── proto/              # 协议缓冲区定义
└── cli.py              # 命令行接口
```

---

## 3. 关键发现

### 3.1 aweme_type 字段规律

通过代码分析和缓存数据验证，确认 `aweme_type` 字段用于区分作品类型：

| 值 | 类型 | 特征 |
|---|---|---|
| `2` | 图文作品 (Note) | 包含 `images` 数组，每个元素可能含 `video`（实况照片）|
| `4` | 普通视频 (Video) | `images` 字段为 `null` 或空数组 |
| `68` | 长视频 | 特殊类型，需要额外处理 |

**代码中的使用方式** (`filter.py`):

```python
@property
def aweme_type(self):
    """获取作品类型"""
    return self._get_attr_value("$.aweme_detail.aweme_type")
```

**我们的应用建议**:

```dart
// 判断图文作品
bool isImagePost = item['aweme_type'] == 2 || 
                   (item['images'] != null && 
                    item['images'] is List && 
                    (item['images'] as List).isNotEmpty);

// 判断视频作品  
bool isVideo = item['aweme_type'] == 4 || item['images'] == null;
```

### 3.2 视频 URL 提取逻辑

**F2 的提取路径** (`filter.py:267-269`):

```python
@property
def video_play_addr(self):
    return self._get_list_attr_value(
        "$.aweme_list[*].video.bit_rate[0].play_addr.url_list"
    )
```

**关键点**:
- 取 `bit_rate[0]` - 最高质量的视频流
- `play_addr.url_list` 是一个数组，包含多个 CDN 地址
- 第一个地址通常是主 CDN，失效时可以 fallback

**我们的当前逻辑对比**:

```dart
// 当前代码
final bitRate = videoData['bit_rate'] as List<dynamic>?;
if (bitRate != null && bitRate.isNotEmpty) {
  final playAddr = bitRate[0]['play_addr'];
  if (playAddr != null && playAddr['url_list'] != null) {
    urls.addAll((playAddr['url_list'] as List).cast<String>());
  }
}
```

**结论**: 我们的逻辑与 F2 一致，正确！

### 3.3 图文作品的视频提取 (LivePhoto)

F2 提供了一个重要的提取逻辑 (`filter.py:285-300`):

```python
@property
def images_video(self):
    """
    提取图文作品中的动态视频 (LivePhoto/实况照片)
    """
    images_video_list = self._get_list_attr_value("$.aweme_list[*].images")
    return [
        (
            [
                live["video"]["play_addr"]["url_list"][0]
                for live in images_video
                if isinstance(live, dict) and live.get("video") is not None
            ]
            if images_video
            else []
        )
        for images_video in images_video_list
    ]
```

**重要发现**:
- 图文作品的每个图片项可能包含 `video` 字段
- 这是实况照片（LivePhoto）的视频数据
- 对于 iOS 用户拍摄的实况照片，这个字段会有值

**数据结构示例**:

```json
{
  "images": [
    {
      "url_list": ["https://...", "https://..."],
      "video": {
        "play_addr": {
          "url_list": ["https://..."]
        }
      }
    }
  ]
}
```

**我们的改进建议**:

```dart
// 提取图文作品的 LivePhoto 视频
List<String> extractLivePhotoVideos(Map<String, dynamic> item) {
  final images = item['images'] as List<dynamic>?;
  if (images == null) return [];
  
  final videos = <String>[];
  for (final image in images) {
    if (image is Map<String, dynamic>) {
      final video = image['video'];
      if (video != null && video['play_addr'] != null) {
        final urlList = video['play_addr']['url_list'] as List?;
        if (urlList != null && urlList.isNotEmpty) {
          videos.add(urlList[0] as String);
        }
      }
    }
  }
  return videos;
}
```

### 3.4 音乐 URL 提取

**F2 的提取方式** (`filter.py:325-326`):

```python
@property
def music_play_url(self):
    return self._get_list_attr_value("$.aweme_list[*].music.play_url.url_list[0]")
```

**数据结构路径**:
```
music.play_url.url_list[0]
```

**我们的当前代码** (`douyin_parser.dart:291-300`):

```dart
// 提取音乐信息
String? musicUrl;
final music = item['music'] as Map<String, dynamic>?;
if (music != null) {
  final playUrl = music['play_url'] as Map<String, dynamic>?;
  if (playUrl != null) {
    final urlList = playUrl['url_list'] as List<dynamic>?;
    if (urlList != null && urlList.isNotEmpty) {
      musicUrl = urlList[0] as String;
    }
  }
}
```

**结论**: 逻辑一致，正确！

### 3.5 封面图提取

**F2 提取路径**:

```python
# 视频封面
"$.aweme_list[*].video.cover.url_list[0]"

# 动态封面 (动图/GIF)
"$.aweme_list[*].video.dynamic_cover.url_list[0]"

# 图文的封面
"$.aweme_list[*].images[0].url_list[0]"
```

**建议**: 优先使用 `dynamic_cover`（动态封面），用户体验更好。

---

## 4. 数据模型分析

### 4.1 请求参数模型 (`model.py`)

F2 使用 Pydantic 定义了完整的请求参数模型：

| 模型类 | 用途 | 关键字段 |
|---|---|---|
| `PostDetail` | 作品详情 | `aweme_id` |
| `UserPost` | 用户作品列表 | `sec_uid`, `max_cursor` |
| `UserProfile` | 用户信息 | `sec_uid` |
| `UserLive` | 直播信息 | `web_rid` |
| `HomePostSearch` | 作品搜索 | `query`, `search_source` |

**PostDetail 模型示例**:

```python
class PostDetail(BaseRequestModel):
    aweme_id: str                    # 作品ID
    msToken: Optional[str] = None    # 加密Token
    # ... 设备指纹信息等
```

### 4.2 设备指纹参数

F2 请求中使用的设备指纹参数：

```python
{
    "os": "mac",
    "browser": "Chrome",
    "device_platform": "webapp",
    "aid": "6383",
    "version_name": "Chrome/120.0.0.0",
    # ... 更多参数
}
```

---

## 5. 视频/图文解析逻辑

### 5.1 解析流程

根据 `filter.py` 和 `handler.py` 分析，F2 的解析流程：

```
原始数据 → Filter提取 → Handler处理 → 输出结构化数据
```

### 5.2 Filter 类结构

| Filter 类 | 用途 |
|---|---|
| `UserPostFilter` | 用户作品列表过滤 |
| `PostDetailFilter` | 作品详情过滤 |
| `UserProfileFilter` | 用户信息过滤 |
| `CommentFilter` | 评论过滤 |
| `LiveFilter` | 直播信息过滤 |

### 5.3 数据字段映射

**作品字段提取**:

| 字段 | JSON Path | 说明 |
|---|---|---|
| aweme_id | `$.aweme_detail.aweme_id` | 作品唯一ID |
| desc | `$.aweme_detail.desc` | 作品描述/标题 |
| create_time | `$.aweme_detail.create_time` | 创建时间戳 |
| author.nickname | `$.aweme_detail.author.nickname` | 作者昵称 |
| author.sec_uid | `$.aweme_detail.author.sec_uid` | 作者UID |
| video.duration | `$.aweme_detail.video.duration` | 视频时长(毫秒) |
| statistics.digg_count | `$.aweme_detail.statistics.digg_count` | 点赞数 |
| statistics.comment_count | `$.aweme_detail.statistics.comment_count` | 评论数 |
| statistics.share_count | `$.aweme_detail.statistics.share_count` | 分享数 |

---

## 6. URL 解析模式

### 6.1 URL 正则表达式 (`utils.py`)

F2 定义的完整 URL 匹配模式：

```python
# 视频链接 - https://www.douyin.com/video/123456
_VIDEO_URL_PATTERN = re.compile(r"video/([^/?]*)")

# 图文链接 - https://www.douyin.com/note/123456
_NOTE_URL_PATTERN = re.compile(r"note/([^/?]*)")

# 用户主页 - https://www.douyin.com/user/xxx
_USER_URL_PATTERN = re.compile(r"user/([^/?]*)")

# 合集链接 - https://www.douyin.com/collection/123
_MIX_URL_PATTERN = re.compile(r"collection/([^/?]*)")

# 直播链接 - https://www.douyin.com/live/123
_LIVE_URL_PATTERN = re.compile(r"live/([^/?]*)")
_LIVE_URL_PATTERN2 = re.compile(r"http[s]?://live.douyin.com/(\d+)")

# 短链接重定向 - 用于从短链提取 sec_uid
_REDIRECT_URL_PATTERN = re.compile(r"sec_uid=([^&]*)")
```

### 6.2 分享链接处理

**短链接重定向逻辑**:

```python
# v.douyin.com/xxxxx 短链会 302 跳转到长链接
# 从长链接中提取 sec_uid
sec_uid_match = re.search(r"sec_uid=([^&]*)", redirected_url)
```

---

## 7. 加密算法

### 7.1 XBogus / ABogus

F2 实现了抖音的请求签名算法 (`utils.py`):

```python
class XBogusManager:
    """XBogus 签名算法管理器"""
    @staticmethod
    def model_2_endpoint(user_agent: str, endpoint: str, params: dict):
        # 生成 XBogus 签名参数
        # 附加到 URL 查询参数中
        pass

class ABogusManager:
    """ABogus 签名算法管理器 (新版本)"""
    # 类似的实现
```

### 7.2 msToken

F2 生成 msToken 的方式:

```python
class TokenManager:
    @staticmethod
    def gen_ms_token(length: int = 107) -> str:
        """生成随机的 msToken"""
        characters = string.ascii_letters + string.digits
        return ''.join(random.choice(characters) for _ in range(length))
```

### 7.3 ttwid

直播 WebSocket 连接需要的 ttwid:

```python
@staticmethod
def gen_ttwid() -> str:
    """生成 ttwid Cookie"""
    # 通过特定接口获取
```

---

## 8. 可借鉴的改进建议

### 8.1 类型判断增强

**当前代码**:
```dart
final isImagePost = item['images'] != null && 
                    item['images'] is List && 
                    (item['images'] as List).isNotEmpty;
```

**建议增强**:
```dart
bool isImagePost(Map<String, dynamic> item) {
  // 优先使用 aweme_type 判断
  final awemeType = item['aweme_type'];
  if (awemeType == 2) return true;
  if (awemeType == 4) return false;
  
  // 兜底用 images 字段判断
  final images = item['images'];
  return images != null && images is List && images.isNotEmpty;
}
```

### 8.2 LivePhoto 支持

新增 LivePhoto 视频提取功能：

```dart
Future<List<VideoItem>> extractLivePhotos(Map<String, dynamic> item) async {
  final images = item['images'] as List<dynamic>?;
  if (images == null) return [];
  
  final videos = <VideoItem>[];
  for (int i = 0; i < images.length; i++) {
    final image = images[i];
    if (image is! Map<String, dynamic>) continue;
    
    final video = image['video'];
    if (video == null) continue;
    
    final playAddr = video['play_addr'];
    if (playAddr == null) continue;
    
    final urlList = playAddr['url_list'] as List?;
    if (urlList == null || urlList.isEmpty) continue;
    
    videos.add(VideoItem(
      url: urlList[0],
      quality: 'livephoto_$i',
      type: VideoType.livePhoto,
    ));
  }
  return videos;
}
```

### 8.3 错误处理增强

参考 F2 的异常分类：

```dart
enum DouyinError {
  rateLimited,      // 请求频率限制
  invalidResponse,  // 响应格式错误
  networkError,     // 网络错误
  notFound,         // 作品不存在
  private,          // 私密作品
}

class DouyinParseException implements Exception {
  final DouyinError error;
  final String message;
  
  DouyinParseException(this.error, this.message);
}
```

### 8.4 文件命名模板

F2 的文件命名字段（`utils.py:1469-1476`）:

```python
fields = {
    "create": aweme_data.get("create_time", ""),
    "nickname": aweme_data.get("nickname", ""),
    "aweme_id": aweme_data.get("aweme_id", ""),
    "desc": split_filename(aweme_data.get("desc", ""), os_limit),
    "caption": aweme_data.get("caption", ""),
    "uid": aweme_data.get("uid", ""),
}
```

**建议下载文件命名格式**:
```
{create}_{nickname}_{aweme_id}_{desc}.{ext}
```

示例:
```
20240314_张三_1234567890_这是一个有趣的视频.mp4
```

### 8.5 统计数据展示

F2 提取的统计字段建议加入 UI 展示：

| 字段 | 说明 | 展示位置 |
|---|---|---|
| `digg_count` | 点赞数 | 作品卡片 |
| `comment_count` | 评论数 | 作品卡片 |
| `share_count` | 分享数 | 详情页 |
| `play_count` | 播放数 | 详情页 |
| `collect_count` | 收藏数 | 详情页 |

---

## 附录：关键代码片段

### A.1 完整的视频 URL 提取逻辑

```python
# F2 filter.py 中的提取逻辑

# 1. 视频播放地址 (最高质量)
video_play_addr = "$.aweme_list[*].video.bit_rate[0].play_addr.url_list"

# 2. 视频封面
video_cover = "$.aweme_list[*].video.cover.url_list[0]"

# 3. 动态封面
video_dynamic_cover = "$.aweme_list[*].video.dynamic_cover.url_list[0]"

# 4. 音乐播放地址
music_play_url = "$.aweme_list[*].music.play_url.url_list[0]"

# 5. 图文图片列表
images = "$.aweme_list[*].images"

# 6. 图文中的视频 (LivePhoto)
images_video = "$.aweme_list[*].images[*].video.play_addr.url_list[0]"
```

### A.2 Crawler 类方法列表

```python
class DouyinCrawler:
    # 用户信息
    async def fetch_user_profile(self, params: UserProfile)
    
    # 作品列表
    async def fetch_user_post(self, params: UserPost)
    async def fetch_user_like(self, params: UserLike)
    async def fetch_user_collection(self, params: UserCollection)
    
    # 作品详情
    async def fetch_post_detail(self, params: PostDetail)
    
    # 评论
    async def fetch_post_comment(self, params: PostComment)
    async def fetch_post_comment_reply(self, params: PostCommentReply)
    
    # 直播
    async def fetch_live(self, params: UserLive)
    async def fetch_live_room_id(self, params: UserLive2)
    
    # 搜索
    async def fetch_home_post_search(self, params: HomePostSearch)
```

---

## 参考链接

- F2 项目: https://github.com/Johnserf-Seed/f2
- 抖音 Web API 文档 (逆向): 通过 F2 代码分析得出

---

*报告生成时间: 2026-03-14*
*分析工具: Kimi K2.5 + 人工代码审查*
