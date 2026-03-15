# Douyin_TikTok_Download_API 项目代码分析报告

> 分析对象: `temp/Douyin_TikTok_Download_API-main` 目录下的核心代码
> 
> 分析时间: 2026-03-14
>
> 用途: 为本项目（DViewer）的抖音/TikTok解析功能提供参考

## 目录

1. [项目概述](#1-项目概述)
2. [核心架构](#2-核心架构)
3. [抖音模块详解](#3-抖音模块详解)
4. [加密算法分析](#4-加密算法分析)
5. [Hybrid混合解析](#5-hybrid混合解析)
6. [关键发现与借鉴](#6-关键发现与借鉴)

---

## 1. 项目概述

这是一个功能强大的多平台视频下载API项目，支持：
- **抖音 Web** - 网页版数据抓取
- **TikTok Web** - 网页版数据抓取
- **TikTok App** - App接口数据抓取（更稳定）
- **Bilibili** - B站视频抓取
- **混合解析** - 自动识别URL来源并调用对应解析器

### 项目特点
- FastAPI 构建的 RESTful API
- 纯 Python 实现，无需 Node.js 环境
- 支持多种加密算法（XBogus/ABogus）
- 完整的异常处理机制
- Cookie 管理和自动更新

---

## 2. 核心架构

```
crawlers/
├── base_crawler.py           # 基础爬虫类
├── douyin/
│   └── web/
│       ├── web_crawler.py    # 抖音Web爬虫主类
│       ├── endpoints.py      # API端点定义
│       ├── models.py         # 请求参数模型(Pydantic)
│       ├── utils.py          # 工具函数
│       ├── xbogus.py         # XBogus算法
│       └── abogus.py         # ABogus算法(纯Python)
├── tiktok/
│   ├── web/
│   │   └── web_crawler.py    # TikTok Web爬虫
│   └── app/
│       └── app_crawler.py    # TikTok App爬虫
├── bilibili/
│   └── web/
│       └── web_crawler.py    # B站爬虫
└── hybrid/
    └── hybrid_crawler.py     # 混合解析器

app/
├── api/
│   ├── router.py             # API路由
│   └── endpoints/
│       ├── douyin_web.py     # 抖音API端点
│       ├── tiktok_web.py     # TikTok API端点
│       └── hybrid_parsing.py # 混合解析端点
└── web/
    └── views/                # Web界面
```

---

## 3. 抖音模块详解

### 3.1 API端点定义 (`endpoints.py`)

| 端点名称 | URL | 用途 |
|---|---|---|
| POST_DETAIL | `/aweme/v1/web/aweme/detail/` | 作品详情 |
| USER_POST | `/aweme/v1/web/aweme/post/` | 用户作品列表 |
| USER_FAVORITE_A | `/aweme/v1/web/aweme/favorite/` | 用户喜欢列表 |
| USER_COLLECTION | `/aweme/v1/web/aweme/listcollection/` | 用户收藏列表 |
| POST_COMMENT | `/aweme/v1/web/comment/list/` | 评论列表 |
| LIVE_INFO | `/webcast/room/web/enter/` | 直播间信息 |
| GENERAL_SEARCH | `/aweme/v1/web/general/search/single/` | 综合搜索 |
| DOUYIN_HOT_SEARCH | `/aweme/v1/web/hot/search/list/` | 抖音热榜 |

### 3.2 请求参数模型 (`models.py`)

**BaseRequestModel** - 基础请求参数：
```python
class BaseRequestModel(BaseModel):
    device_platform: str = "webapp"
    aid: str = "6383"
    channel: str = "channel_pc_web"
    version_code: str = "290100"
    browser_name: str = "Chrome"
    browser_version: str = "130.0.0.0"
    os_name: str = "Windows"
    os_version: str = "10"
    # ... 更多设备指纹参数
```

**关键发现 - 设备指纹参数**：
- `aid=6383` - 抖音Web应用ID
- `device_platform=webapp` - 设备平台标识
- `browser_name/version` - 浏览器信息
- `os_name/version` - 操作系统信息
- `cpu_core_num/device_memory` - 硬件信息

### 3.3 URL解析工具 (`utils.py`)

**SecUserIdFetcher** - 提取用户ID：
```python
class SecUserIdFetcher:
    _DOUYIN_URL_PATTERN = re.compile(r"user/([^/?]*)")
    _REDIRECT_URL_PATTERN = re.compile(r"sec_uid=([^&]*)")
    
    @classmethod
    async def get_sec_user_id(cls, url: str) -> str:
        # 短链重定向后提取sec_uid
        # 长链直接匹配 user/xxxxx
```

**AwemeIdFetcher** - 提取作品ID：
```python
class AwemeIdFetcher:
    _DOUYIN_VIDEO_URL_PATTERN = re.compile(r"video/([^/?]*)")
    _DOUYIN_NOTE_URL_PATTERN = re.compile(r"note/([^/?]*)")
    _DOUYIN_DISCOVER_URL_PATTERN = re.compile(r"modal_id=([0-9]+)")
    
    @classmethod
    async def get_aweme_id(cls, url: str) -> str:
        # 按顺序尝试匹配：video/ -> vid= -> note/ -> modal_id=
```

**关键发现 - URL匹配优先级**：
1. `video/([0-9]+)` - 视频链接
2. `[?&]vid=(\d+)` - 带vid参数
3. `note/([0-9]+)` - 图文链接
4. `modal_id=([0-9]+)` - 发现页链接

### 3.4 Token管理 (`utils.py`)

**msToken 生成**：
```python
class TokenManager:
    @classmethod
    def gen_real_msToken(cls) -> str:
        """通过抖音官方接口获取真实msToken"""
        payload = {
            "magic": 538969122,
            "version": 1,
            "dataType": 8,
            "strData": "...",  # 固定的加密字符串
            "tspFromClient": get_timestamp(),
        }
        # POST到 https://mssdk.bytedance.com/web/report
        # 从响应Cookie中提取msToken
    
    @classmethod
    def gen_false_msToken(cls) -> str:
        """生成虚假msToken作为fallback"""
        return gen_random_str(126) + "=="
```

**ttwid 生成**：
```python
@classmethod
def gen_ttwid(cls) -> str:
    """生成直播请求必需的ttwid"""
    data = '{"region":"cn","aid":1768,...}'
    # POST到 https://ttwid.bytedance.com/ttwid/union/register/
    # 从响应Cookie中提取ttwid
```

**verifyFp 生成**：
```python
class VerifyFpManager:
    @classmethod
    def gen_verify_fp(cls) -> str:
        """生成verifyFp与s_v_web_id"""
        # 基于时间戳的base36编码 + UUID格式
        # 格式: verify_{timestamp}_{uuid}
```

---

## 4. 加密算法分析

### 4.1 XBogus算法 (`xbogus.py`)

**用途**：早期抖音Web API请求签名
**现状**：2024年6月后已失效，被ABogus取代

```python
class XBogus:
    def getXBogus(self, endpoint: str) -> tuple:
        # 基于请求参数和User-Agent生成签名
        # 返回 (完整URL, xbogus值)
```

### 4.2 ABogus算法 (`abogus.py`)

**关键发现 - 纯Python实现**：
```python
class ABogus:
    __version = [1, 0, 1, 5]  # 算法版本
    __browser = "1536|742|1536|864|0|0|0|0|1536|864|1536|864|1536|742|24|24|MacIntel"
    
    def get_value(self, params: dict) -> str:
        """生成a_bogus签名"""
        # 1. 编码请求参数
        # 2. 结合User-Agent编码
        # 3. 时间戳和随机数
        # 4. SM3哈希计算
        # 5. 自定义编码输出
```

**ABogus生成流程**：
1. 将请求参数字典转为URL编码字符串
2. 添加时间戳和随机数
3. 使用User-Agent编码
4. SM3哈希计算
5. 自定义Base64编码输出

**使用示例**：
```python
# 生成带ABogus的URL
params_dict = params.dict()
params_dict["msToken"] = ''
a_bogus = BogusManager.ab_model_2_endpoint(params_dict, user_agent)
endpoint = f"{DouyinAPIEndpoints.POST_DETAIL}?{urlencode(params_dict)}&a_bogus={a_bogus}"
```

### 4.3 加密管理器 (`utils.py`)

```python
class BogusManager:
    # XBogus - 已废弃但保留兼容
    @classmethod
    def xb_model_2_endpoint(cls, base_endpoint: str, params: dict, user_agent: str) -> str:
        xb_value = XB(user_agent).getXBogus(param_str)
        return f"{base_endpoint}?{param_str}&X-Bogus={xb_value[1]}"
    
    # ABogus - 当前使用
    @classmethod
    def ab_model_2_endpoint(cls, params: dict, user_agent: str) -> str:
        ab_value = AB().get_value(params)
        return quote(ab_value, safe='')
```

---

## 5. Hybrid混合解析

### 5.1 核心设计 (`hybrid_crawler.py`)

**自动平台识别**：
```python
class HybridCrawler:
    async def hybrid_parsing_single_video(self, url: str, minimal: bool = False):
        if "douyin" in url:
            platform = "douyin"
            aweme_id = await self.DouyinWebCrawler.get_aweme_id(url)
            data = await self.DouyinWebCrawler.fetch_one_video(aweme_id)
        elif "tiktok" in url:
            platform = "tiktok"
            aweme_id = await self.TikTokWebCrawler.get_aweme_id(url)
            data = await self.TikTokAPPCrawler.fetch_one_video(aweme_id)
        elif "bilibili" in url or "b23.tv" in url:
            platform = "bilibili"
            aweme_id = await self.get_bilibili_bv_id(url)
            data = await self.BilibiliWebCrawler.fetch_one_video(aweme_id)
```

### 5.2 统一类型映射

**aweme_type 跨平台映射**：
```python
url_type_code_dict = {
    # 通用
    0: 'video',
    # 抖音
    2: 'image',      # 图文
    4: 'video',      # 视频
    68: 'image',     # 长视频/图集
    # TikTok
    51: 'video',
    55: 'video',
    58: 'video',
    61: 'video',
    150: 'image',    # 图片
}
```

### 5.3 统一数据结构

**标准化输出格式**：
```python
result_data = {
    'type': url_type,          # 'video' | 'image'
    'platform': platform,      # 'douyin' | 'tiktok' | 'bilibili'
    'video_id': aweme_id,      # 平台唯一ID
    'desc': data.get("desc"),  # 标题/描述
    'create_time': data.get("create_time"),
    'author': data.get("author"),
    'music': data.get("music"),
    'statistics': data.get("statistics"),
    'cover_data': {},          # 封面信息
    'hashtags': data.get('text_extra'),
}
```

### 5.4 抖音视频数据处理

**无水印视频URL构造**：
```python
if url_type == 'video':
    uri = data['video']['play_addr']['uri']
    wm_video_url_HQ = data['video']['play_addr']['url_list'][0]
    
    # 有水印视频
    wm_video_url = f"https://aweme.snssdk.com/aweme/v1/playwm/?video_id={uri}&radio=1080p&line=0"
    
    # 无水印视频 - 替换playwm为play
    nwm_video_url_HQ = wm_video_url_HQ.replace('playwm', 'play')
    nwm_video_url = f"https://aweme.snssdk.com/aweme/v1/play/?video_id={uri}&ratio=1080p&line=0"
```

**重要发现 - 无水印URL规律**：
- 有水印: `.../playwm/...` 或包含 `watermark`
- 无水印: 将 `playwm` 替换为 `play`

### 5.5 抖音图片数据处理

**图文作品URL提取**：
```python
elif url_type == 'image':
    no_watermark_image_list = []
    watermark_image_list = []
    
    for i in data['images']:
        no_watermark_image_list.append(i['url_list'][0])
        watermark_image_list.append(i['download_url_list'][0])
```

**数据结构**：
```json
{
  "images": [
    {
      "url_list": ["https://..."],           // 无水印原图
      "download_url_list": ["https://..."]   // 有水印图
    }
  ]
}
```

---

## 6. 关键发现与借鉴

### 6.1 aweme_type 确认

| 平台 | 值 | 类型 |
|---|---|---|
| 抖音 | 2 | 图文 (Note) |
| 抖音 | 4 | 视频 (Video) |
| 抖音 | 68 | 图集/长视频 |
| TikTok | 150 | 图片 |
| TikTok | 51/55/58/61 | 视频 |

**我们的代码改进建议**：
```dart
String getMediaType(dynamic awemeType) {
  switch (awemeType) {
    case 2:
    case 68:
      return 'image';
    case 4:
    case 0:
      return 'video';
    default:
      return 'unknown';
  }
}
```

### 6.2 无水印URL生成

**抖音无水印视频URL构造**：
```dart
String getNoWatermarkUrl(String watermarkUrl, String videoUri) {
  // 方法1: 替换playwm为play
  if (watermarkUrl.contains('playwm')) {
    return watermarkUrl.replaceAll('playwm', 'play');
  }
  
  // 方法2: 使用uri构造
  return 'https://aweme.snssdk.com/aweme/v1/play/?video_id=$videoUri&ratio=1080p&line=0';
}
```

### 6.3 请求头配置

**关键请求头**：
```yaml
headers:
  Accept-Language: zh-CN,zh;q=0.8,zh-TW;q=0.7,zh-HK;q=0.5,en-US;q=0.3,en;q=0.2
  User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36...
  Referer: https://www.douyin.com/
  Cookie: # 需要包含: ttwid, msToken, verify_fp 等
```

### 6.4 Cookie管理策略

**Token刷新机制**：
```python
# config.yaml 中配置
cookie_components:
  - __ac_nonce       # 防爬验证
  - __ac_signature   # 签名
  - ttwid           # 设备指纹
  - msToken         # 请求令牌
  - verify_fp       # 浏览器指纹
  - s_v_web_id      # Session ID
```

### 6.5 异常处理分类

**API异常类型**：
```python
class APIError(Exception): pass
class APIConnectionError(APIError): pass      # 网络错误
class APIResponseError(APIError): pass        # 响应格式错误
class APIUnauthorizedError(APIError): pass    # 401未授权
class APINotFoundError(APIError): pass        # 404未找到
class APIUnavailableError(APIError): pass     # 503服务不可用
```

### 6.6 文件命名模板

**命名字段**：
```python
fields = {
    "create": aweme_data.get("create_time", ""),    # 发布时间
    "nickname": aweme_data.get("nickname", ""),      # 作者昵称
    "aweme_id": aweme_data.get("aweme_id", ""),      # 作品ID
    "desc": aweme_data.get("desc", ""),              # 作品描述
    "uid": aweme_data.get("uid", ""),                # 作者UID
}

# 模板示例: "{create}_{nickname}_{aweme_id}_{desc}.mp4"
# 输出示例: "20240314_张三_1234567890_这是一个有趣的视频.mp4"
```

### 6.7 与F2项目对比

| 特性 | Douyin_TikTok_Download_API | F2 |
|---|---|---|
| 架构 | FastAPI服务 | CLI工具 |
| 平台支持 | 抖音+TikTok+B站 | 抖音为主 |
| 加密算法 | 纯Python实现 | Python实现 |
| ABogus | 支持 | 支持 |
| TikTok支持 | App+Web接口 | 有限支持 |
| B站支持 | 支持 | 不支持 |
| 混合解析 | 自动识别 | 需手动指定 |

---

## 附录：核心代码参考

### A.1 完整的URL解析流程

```python
async def get_aweme_id(cls, url: str) -> str:
    # 1. 重定向短链到完整链接
    response = await client.get(url, follow_redirects=True)
    response_url = str(response.url)
    
    # 2. 按优先级匹配
    patterns = [
        re.compile(r"video/([^/?]*)"),      # 视频
        re.compile(r"[?&]vid=(\d+)"),       # vid参数
        re.compile(r"note/([^/?]*)"),       # 图文
        re.compile(r"modal_id=([0-9]+)"),   # 发现页
    ]
    
    for pattern in patterns:
        match = pattern.search(response_url)
        if match:
            return match.group(1)
```

### A.2 请求签名生成流程

```python
async def fetch_one_video(self, aweme_id: str):
    # 1. 获取请求头
    kwargs = await self.get_douyin_headers()
    
    # 2. 创建基础爬虫
    base_crawler = BaseCrawler(proxies=kwargs["proxies"], crawler_headers=kwargs["headers"])
    
    async with base_crawler as crawler:
        # 3. 创建请求参数
        params = PostDetail(aweme_id=aweme_id)
        params_dict = params.dict()
        params_dict["msToken"] = ''
        
        # 4. 生成ABogus签名
        a_bogus = BogusManager.ab_model_2_endpoint(params_dict, kwargs["headers"]["User-Agent"])
        
        # 5. 构造完整URL
        endpoint = f"{DouyinAPIEndpoints.POST_DETAIL}?{urlencode(params_dict)}&a_bogus={a_bogus}"
        
        # 6. 发送请求
        response = await crawler.fetch_get_json(endpoint)
    
    return response
```

### A.3 平台自动识别逻辑

```python
def detect_platform(url: str) -> str:
    url = url.lower()
    if "douyin" in url:
        return "douyin"
    elif "tiktok" in url:
        return "tiktok"
    elif "bilibili" in url or "b23.tv" in url:
        return "bilibili"
    else:
        raise ValueError(f"Unsupported platform: {url}")
```

---

## 参考链接

- 项目地址: https://github.com/Evil0ctal/Douyin_TikTok_Download_API
- ABogus来源: https://github.com/JoeanAmier/TikTokDownloader
- F2项目: https://github.com/Johnserf-Seed/f2

---

*报告生成时间: 2026-03-14*
*分析工具: Kimi K2.5 + 人工代码审查*
