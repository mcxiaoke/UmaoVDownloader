/// 应用常量管理
///
/// 集中管理应用中的所有常量，包括：
/// - 应用信息
/// - 平台域名和URL
/// - 用户代理字符串
/// - 设置键名
/// - 网络超时
/// - 数值限制
/// - 方法通道名称
/// - 错误消息
library;

// ============================================================================
// 应用信息常量
// ============================================================================

/// GitHub 项目地址
const String kGitHubUrl = 'https://github.com/mcxiaoke/UmaoVDownloader';

// ============================================================================
// 平台常量
// ============================================================================

/// 抖音平台域名
const String kDouyinDomain = 'douyin.com';
const String kIesDouyinDomain = 'iesdouyin.com';

/// 小红书平台域名
const String kXiaohongshuDomain = 'xiaohongshu.com';
const String kXhslinkDomain = 'xhslink.com';

/// 抖音视频播放基础URL
const String kDouyinPlayBaseUrl = 'https://aweme.snssdk.com/aweme/v1/play/';

/// 抖音路由数据标记
const String kDouyinRouterDataMarker = 'window._ROUTER_DATA = ';

/// 抖音 Referer
const String kRefererDouyin = 'https://www.douyin.com/';

/// 小红书 Referer
const String kRefererXiaohongshu = 'https://www.xiaohongshu.com/';

// ============================================================================
// 用户代理常量
// ============================================================================

/// iPhone Safari UA（默认推荐，兼容性最好）
const kUaIphoneSafari =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) '
    'Version/16.6 Mobile/15E148 Safari/604.1';

/// Edge 浏览器 UA
const kUaEdge =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/145.0.0.0 Safari/537.36 Edg/145.0.0.0';

/// iOS 微信 UA
const kUaIosWechat =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6_2 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) '
    'Mobile/15E148 MicroMessenger/8.0.69(0x28004553) '
    'NetType/WIFI Language/zh_CN';

/// Android 微信 UA
const kUaAndroidWechat =
    'Mozilla/5.0 (Linux; Android 16; 23127PN0CC Build/BP2A.250605.031.A3; wv) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Version/4.0 Chrome/142.0.7444.173 Mobile Safari/537.36 '
    'XWEB/1420273 MMWEBSDK/20260201 MMWEBID/3396 '
    'MicroMessenger/8.0.69.3040(0x28004553) WeChat/arm64 '
    'Weixin NetType/WIFI Language/zh_CN ABI/arm64';

/// 抖音 iOS App 自身 UA（aweme 是抖音内部代号，CDN 对自家 App 放行策略最宽松）
const kUaIosDouyin =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) '
    'Mobile/15E148 aweme_36.7.0 Region/CN AppTheme/light '
    'NetType/WIFI JsSdk/2.0 Channel/App ByteLocale/zh '
    'ByteFullLocale/zh-Hans-CN WKWebView/1 Bullet/1 aweme/36.7.0 '
    'BytedanceWebview/d8a21c6 AnnieX/1 Forest/1 ReqTrigger/renderEngine';

/// 移动端 Safari UA（用于小红书解析）
const kUserAgentMobileSafari = kUaIphoneSafari;

// ============================================================================
// 设置键常量
// ============================================================================

/// 下载目录设置键名
const String kSettingKeyDownloadDir = 'download_dir';

/// 详细日志设置键名
const String kSettingKeyVerboseLog = 'verbose_log';

// ============================================================================
// 网络常量
// ============================================================================

/// 网络请求超时时间（秒）
const int kNetworkTimeoutSeconds = 15;

/// 网络请求超时 Duration
const kNetworkTimeout = Duration(seconds: kNetworkTimeoutSeconds);

/// 下载块超时时间（秒）
const int kDownloadChunkTimeoutSeconds = 30;

/// 下载块超时 Duration
const kDownloadChunkTimeout = Duration(seconds: kDownloadChunkTimeoutSeconds);

/// 最大重定向次数
const int kMaxRedirects = 8;

// ============================================================================
// 数值常量
// ============================================================================

/// 日志服务内存中最大日志条目数
const int kLogMaxInMemory = 500;

/// 图片加载最大并发数
const int kImageLoadingMaxConcurrent = 4;

/// 最小视频文件大小（10 KB），小于此值视为无效视频
const int kMinVideoFileSizeBytes = 10 * 1024;

// ============================================================================
// 方法通道常量
// ============================================================================

/// 媒体文件扫描方法通道名称
const String kMethodChannelMedia = 'org.umao.tkdownloader/media';

// ============================================================================
// 路径常量
// ============================================================================

/// Android 存储基础路径
const String kAndroidStorageBase = '/storage/emulated/0';

/// Android 默认图片目录
const String kAndroidDefaultPicturesDir =
    '$kAndroidStorageBase/Pictures/umaovd';

/// Android 默认下载目录
const String kAndroidDefaultDownloadsDir =
    '$kAndroidStorageBase/Download/umaovd';

/// Android 默认音乐目录
const String kAndroidDefaultMusicDir = '$kAndroidStorageBase/Music/umaovd';

// ============================================================================
// 抖音类型常量（aweme_type 值集合）
// ============================================================================

/// 抖音视频类型 aweme_type 值集合
const Set<int> kDouyinVideoTypes = {0, 4, 51, 55, 58, 61, 109, 201};

/// 抖音图文类型 aweme_type 值集合
const Set<int> kDouyinImageTypes = {2, 68, 150};

// ============================================================================
// 错误消息常量
// ============================================================================

/// 作品不存在或已被删除的错误消息
const String kErrorMessageContentNotFound = '作品不存在或已被删除（链接返回404）';

/// 解析器通用错误消息
const String kErrorMessageParserGeneric = '解析失败，请检查链接是否正确';

/// 下载器通用错误消息
const String kErrorMessageDownloadGeneric = '下载失败，请检查网络和存储权限';

/// 权限拒绝错误消息
const String kErrorMessagePermissionDenied = '存储权限被拒绝，请授予权限后重试';

// ============================================================================
// 服务端配置
// ============================================================================

/// Backend 服务基础 URL（用于抖音图文动图视频获取）
const String kBackendBaseUrl = 'http://192.168.1.118:3333';

/// Backend 请求超时时间（秒）
const int kBackendTimeoutSeconds = 10;
