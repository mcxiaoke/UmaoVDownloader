/**
 * 抖音 API 端点常量
 * 来源: f2-main/f2/apps/douyin/api.py, Douyin_TikTok_Download_API-main/crawlers/douyin/web/endpoints.py
 */

// 抖音域名
const DOUYIN_DOMAIN = "https://www.douyin.com";
const IESDOUYIN_DOMAIN = "https://www.iesdouyin.com";
const LIVE_DOMAIN = "https://live.douyin.com";
const LIVE_DOMAIN2 = "https://webcast.amemv.com";
const SSO_DOMAIN = "https://sso.douyin.com";

// WSS 弹幕域名
const WEBCAST_WSS_DOMAIN = "wss://webcast5-ws-web-lf.douyin.com";

/**
 * 抖音 API 端点
 */
export const DouyinAPI = {
  // ==================== 作品相关 ====================
  
  // 作品详情 (视频/图文信息)
  POST_DETAIL: `${DOUYIN_DOMAIN}/aweme/v1/web/aweme/detail/`,
  
  // 图集作品 (Live Photo)
  SLIDES_AWEME: `${IESDOUYIN_DOMAIN}/web/api/v2/aweme/slidesinfo/`,
  
  // 用户作品列表
  USER_POST: `${DOUYIN_DOMAIN}/aweme/v1/web/aweme/post/`,
  
  // 合集作品
  MIX_AWEME: `${DOUYIN_DOMAIN}/aweme/v1/web/mix/aweme/`,
  
  // 相关推荐
  POST_RELATED: `${DOUYIN_DOMAIN}/aweme/v1/web/aweme/related/`,
  
  // 作品状态 (点赞/收藏状态)
  POST_STATS: `${DOUYIN_DOMAIN}/aweme/v2/web/aweme/stats/`,
  
  // ==================== 用户相关 ====================
  
  // 用户详细信息
  USER_DETAIL: `${DOUYIN_DOMAIN}/aweme/v1/web/user/profile/other/`,
  
  // 用户短信息
  USER_SHORT_INFO: `${DOUYIN_DOMAIN}/aweme/v1/web/im/user/info/`,
  
  // 用户喜欢 (方案A)
  USER_FAVORITE_A: `${DOUYIN_DOMAIN}/aweme/v1/web/aweme/favorite/`,
  
  // 用户喜欢 (方案B)
  USER_FAVORITE_B: `${IESDOUYIN_DOMAIN}/web/api/v2/aweme/like/`,
  
  // 关注列表
  USER_FOLLOWING: `${DOUYIN_DOMAIN}/aweme/v1/web/user/following/list/`,
  
  // 粉丝列表
  USER_FOLLOWER: `${DOUYIN_DOMAIN}/aweme/v1/web/user/follower/list/`,
  
  // 用户历史
  USER_HISTORY: `${DOUYIN_DOMAIN}/aweme/v1/web/history/read/`,
  
  // 用户收藏
  USER_COLLECTION: `${DOUYIN_DOMAIN}/aweme/v1/web/aweme/listcollection/`,
  
  // 用户收藏夹
  USER_COLLECTS: `${DOUYIN_DOMAIN}/aweme/v1/web/collects/list/`,
  
  // 收藏夹作品
  USER_COLLECTS_VIDEO: `${DOUYIN_DOMAIN}/aweme/v1/web/collects/video/list/`,
  
  // 用户音乐收藏
  USER_MUSIC_COLLECTION: `${DOUYIN_DOMAIN}/aweme/v1/web/music/listcollection/`,
  
  // 查询用户
  QUERY_USER: `${DOUYIN_DOMAIN}/aweme/v1/web/query/user/`,
  
  // ==================== 搜索相关 ====================
  
  // 综合搜索
  GENERAL_SEARCH: `${DOUYIN_DOMAIN}/aweme/v1/web/general/search/single/`,
  
  // 视频搜索
  VIDEO_SEARCH: `${DOUYIN_DOMAIN}/aweme/v1/web/search/item/`,
  
  // 用户搜索
  USER_SEARCH: `${DOUYIN_DOMAIN}/aweme/v1/web/discover/search/`,
  
  // 直播间搜索
  LIVE_SEARCH: `${DOUYIN_DOMAIN}/aweme/v1/web/live/search/`,
  
  // 推荐搜索词
  SUGGEST_WORDS: `${DOUYIN_DOMAIN}/aweme/v1/web/api/suggest_words/`,
  
  // 抖音热榜
  DOUYIN_HOT_SEARCH: `${DOUYIN_DOMAIN}/aweme/v1/web/hot/search/list/`,
  
  // ==================== 评论相关 ====================
  
  // 作品评论
  POST_COMMENT: `${DOUYIN_DOMAIN}/aweme/v1/web/comment/list/`,
  
  // 评论回复
  POST_COMMENT_REPLY: `${DOUYIN_DOMAIN}/aweme/v1/web/comment/list/reply/`,
  
  // 发布评论
  POST_COMMENT_PUBLISH: `${DOUYIN_DOMAIN}/aweme/v1/web/comment/publish`,
  
  // 删除评论
  POST_COMMENT_DELETE: `${DOUYIN_DOMAIN}/aweme/v1/web/comment/delete/`,
  
  // 点赞评论
  POST_COMMENT_DIGG: `${DOUYIN_DOMAIN}/aweme/v1/web/comment/digg`,
  
  // ==================== 直播相关 ====================
  
  // 直播信息 (通过 web_rid)
  LIVE_INFO: `${LIVE_DOMAIN}/webcast/room/web/enter/`,
  
  // 直播信息 (通过 room_id)
  LIVE_INFO_ROOM_ID: `${LIVE_DOMAIN2}/webcast/room/reflow/info/`,
  
  // 直播弹幕初始化
  LIVE_IM_FETCH: `${LIVE_DOMAIN}/webcast/im/fetch/`,
  
  // 直播弹幕 (WSS)
  LIVE_IM_WSS: `${WEBCAST_WSS_DOMAIN}/webcast/im/push/v2/`,
  
  // 直播用户信息
  LIVE_USER_INFO: `${LIVE_DOMAIN}/webcast/user/me/`,
  
  // 用户直播状态
  USER_LIVE_STATUS: `${LIVE_DOMAIN}/webcast/distribution/check_user_live_status/`,
  
  // 直播间送礼用户排行榜
  LIVE_GIFT_RANK: `${LIVE_DOMAIN}/webcast/ranklist/audience/`,
  
  // 关注用户直播
  FOLLOW_USER_LIVE: `${DOUYIN_DOMAIN}/webcast/web/feed/follow/`,
  
  // ==================== Feed 相关 ====================
  
  // 首页 Feed
  TAB_FEED: `${DOUYIN_DOMAIN}/aweme/v1/web/tab/feed/`,
  
  // 关注 Feed
  FOLLOW_FEED: `${DOUYIN_DOMAIN}/aweme/v1/web/follow/feed/`,
  
  // 朋友 Feed
  FRIEND_FEED: `${DOUYIN_DOMAIN}/aweme/v1/web/familiar/feed/`,
  
  // 视频频道
  DOUYIN_VIDEO_CHANNEL: `${DOUYIN_DOMAIN}/aweme/v1/web/channel/feed/`,
  
  // ==================== 登录相关 ====================
  
  // 获取登录二维码
  SSO_LOGIN_GET_QR: `${SSO_DOMAIN}/get_qrcode/`,
  
  // 检查二维码状态
  SSO_LOGIN_CHECK_QR: `${SSO_DOMAIN}/check_qrconnect/`,
  
  // 检查登录状态
  SSO_LOGIN_CHECK_LOGIN: `${SSO_DOMAIN}/check_login/`,
  
  // 登录重定向
  SSO_LOGIN_REDIRECT: `${DOUYIN_DOMAIN}/login/`,
  
  // 登录回调
  SSO_LOGIN_CALLBACK: `${DOUYIN_DOMAIN}/passport/sso/login/callback/`,
};

/**
 * 视频播放 URL 基础地址
 * 用法: ${PLAY_BASE}?video_id=${vid}&ratio=1080p&line=0
 */
export const PLAY_BASE = "https://aweme.snssdk.com/aweme/v1/play/";

/**
 * bdms 版本号 (不同平台使用不同版本)
 * - douyin (抖音): 1.0.1.19-fix
 * - tuan (团长): 1.0.1.15
 * - ju (巨量百应): 1.0.1.20
 * - doudian (抖店): 1.0.1.1
 * - qc (巨量千川): 1.0
 */
export const BDMS_VERSION = "1.0.1.19-fix.01";

/**
 * 应用 ID
 * - 1128: 抖音移动端
 * - 6383: 抖音 PC 端
 */
export const APP_ID = {
  MOBILE: 1128,
  PC: 6383,
};

/**
 * 页面 ID
 * - 9999: 移动端 H5 页面
 * - 6241: PC 端页面
 */
export const PAGE_ID = {
  MOBILE: 9999,
  PC: 6241,
};
