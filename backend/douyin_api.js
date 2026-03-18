/**
 * douyin_api.js — 抖音扩展 API 接口
 *
 * 功能概述：
 * 提供抖音平台的扩展 API 接口，包括用户信息、作品列表、评论、关注等。
 * 这些接口不影响现有解析功能，作为独立模块存在。
 *
 * 参考：
 * - sources/dynew/douyin-api-main/api/user.py
 * - sources/dynew/douyin-api-main/api/video.py
 * - sources/dynew/douyin-api-main/utils/request.py
 */

import { DouyinAPI, BDMS_VERSION, APP_ID, PAGE_ID } from "./constants.js";
import { generateABogus } from "./abogus/index.js";
import { getCookie, checkSidGuardExpiry, checkDouyinCookieExpiry } from "./cookies.js";
import { DEFAULT_HEADERS, fetchWithRetry } from "./parsers/common.js";

// ── 常量定义 ─────────────────────────────────────────────────────────────

// Web2 域名 (敏感接口专用)
const WEB2_HOST = "https://www-hj.douyin.com";

// 需要 web2 域名的敏感接口
const WEB2_URIS = [
  "/aweme/v1/web/aweme/favorite/",
  "/aweme/v1/web/locate/post/",
  "/aweme/v1/web/commit/item/digg/",
];

// 基础请求参数
const BASE_PARAMS = {
  device_platform: "webapp",
  aid: String(APP_ID.PC),
  channel: "channel_pc_web",
  update_version_code: "170400",
  pc_client_type: "1",
  version_code: "190500",
  version_name: "19.5.0",
  cookie_enabled: "true",
  screen_width: "2560",
  screen_height: "1440",
  browser_language: "zh-CN",
  browser_platform: "Win32",
  browser_name: "Chrome",
  browser_version: "126.0.0.0",
  browser_online: "true",
  engine_name: "Blink",
  engine_version: "126.0.0.0",
  os_name: "Windows",
  os_version: "10",
  cpu_core_num: "24",
  device_memory: "8",
  platform: "PC",
  downlink: "10",
  effective_type: "4g",
  round_trip_time: "50",
};

// 请求头
const API_HEADERS = {
  ...DEFAULT_HEADERS,
  "sec-fetch-site": "same-origin",
  "sec-fetch-mode": "cors",
  "sec-fetch-dest": "empty",
  accept: "application/json, text/plain, */*",
  "accept-language": "zh-CN,zh;q=0.9,en;q=0.8",
};

// 条件日志
let log = () => {};

// ── 工具函数 ─────────────────────────────────────────────────────────────

/**
 * 从 Cookie 字符串中提取指定键的值
 */
function getCookieValue(cookieStr, key) {
  if (!cookieStr) return null;
  const match = cookieStr.match(new RegExp(`${key}=([^;]+)`));
  return match ? match[1] : null;
}

/**
 * 生成随机 msToken
 */
function generateMsToken(length = 120) {
  const chars = "ABCDEFGHIGKLMNOPQRSTUVWXYZabcdefghigklmnopqrstuvwxyz0123456789=";
  let result = "";
  for (let i = 0; i < length; i++) {
    result += chars[Math.floor(Math.random() * chars.length)];
  }
  return result;
}

/**
 * 构建完整的请求参数
 */
async function buildParams(customParams = {}) {
  const cookie = await getCookie("douyin");

  const params = {
    ...BASE_PARAMS,
    ...customParams,
  };

  // 从 Cookie 提取动态参数
  if (cookie) {
    params.screen_width = getCookieValue(cookie, "dy_swidth") || "2560";
    params.screen_height = getCookieValue(cookie, "dy_sheight") || "1440";
    params.cpu_core_num = getCookieValue(cookie, "device_web_cpu_core") || "24";
    params.device_memory = getCookieValue(cookie, "device_web_memory_size") || "8";
    params.verifyFp = getCookieValue(cookie, "s_v_web_id") || "";
    params.fp = getCookieValue(cookie, "s_v_web_id") || "";
    params.uifid = getCookieValue(cookie, "UIFID") || "";
    params.msToken = getCookieValue(cookie, "msToken") || generateMsToken();
  } else {
    params.msToken = generateMsToken();
  }

  return params;
}

/**
 * 生成 a_bogus 签名
 */
function signParams(params, userAgent) {
  const queryString = Object.entries(params)
    .map(([k, v]) => `${k}=${encodeURIComponent(String(v))}`)
    .join("&");
  return generateABogus(queryString, userAgent);
}

/**
 * 发送 API 请求
 */
async function callApi(uri, params, options = {}) {
  const { method = "GET", data = null, referer = null, debug = false } = options;
  log = debug ? (...args) => console.log("[DY_API]", ...args) : () => {};

  const cookie = await getCookie("douyin");
  const userAgent = API_HEADERS["User-Agent"];

  // 构建完整参数
  const fullParams = await buildParams(params);

  // 生成签名
  fullParams.a_bogus = signParams(fullParams, userAgent);
  log(`a_bogus: ${fullParams.a_bogus?.substring(0, 20)}...`);

  // 确定请求 URL
  const useWeb2 = WEB2_URIS.includes(uri);
  const baseUrl = useWeb2 ? WEB2_HOST : "https://www.douyin.com";
  const url = `${baseUrl}${uri}`;

  // 构建请求头
  const headers = { ...API_HEADERS };
  if (referer) {
    headers.referer = referer;
  }

  // web2 域名需要额外请求头
  if (useWeb2) {
    headers["sec-fetch-site"] = "same-site";
    headers["origin"] = "https://www.douyin.com";
    headers["uifid"] = fullParams.uifid || "";
    headers["x-secsdk-csrf-token"] = "DOWNGRADE";

    const bdClientData = getCookieValue(cookie, "bd_ticket_guard_client_data");
    if (bdClientData) {
      headers["bd-ticket-guard-client-data"] = bdClientData;
      headers["bd-ticket-guard-version"] = "2";
      headers["bd-ticket-guard-web-version"] = "1";
    }
  }

  // 添加 Cookie
  if (cookie) {
    headers.cookie = cookie;
  }

  log(`请求: ${method} ${uri}`);
  log(`useWeb2: ${useWeb2}`);

  // 发送请求
  const queryString = Object.entries(fullParams)
    .map(([k, v]) => `${k}=${encodeURIComponent(String(v))}`)
    .join("&");

  let response;
  if (method === "POST" || data) {
    headers["Content-Type"] = "application/x-www-form-urlencoded";
    response = await fetchWithRetry(`${url}?${queryString}`, {
      method: "POST",
      headers,
      body: data ? new URLSearchParams(data).toString() : "",
    });
  } else {
    response = await fetchWithRetry(`${url}?${queryString}`, {
      method: "GET",
      headers,
    });
  }

  const text = await response.text();
  log(`响应状态: ${response.status}, 长度: ${text.length}`);

  try {
    return JSON.parse(text);
  } catch {
    return { error: "Invalid JSON response", raw: text.substring(0, 500) };
  }
}

// ── API 接口函数 ─────────────────────────────────────────────────────────

/**
 * 获取用户信息
 * @param {string} secUserId - 用户 sec_user_id
 * @param {boolean} debug - 调试模式
 */
export async function getUserProfile(secUserId, debug = false) {
  if (!secUserId) {
    return { error: "缺少 sec_user_id 参数" };
  }

  return callApi(
    "/aweme/v1/web/user/profile/other/",
    {
      sec_user_id: secUserId,
      source: "channel_pc_web",
      publish_video_strategy_type: "2",
      personal_center_strategy: "1",
    },
    {
      referer: `https://www.douyin.com/user/${secUserId}`,
      debug,
    }
  );
}

/**
 * 获取用户作品列表
 * @param {string} secUserId - 用户 sec_user_id
 * @param {number} maxCursor - 分页游标
 * @param {number} count - 每页数量 (默认 35)
 * @param {boolean} debug - 调试模式
 */
export async function getUserPosts(secUserId, maxCursor = 0, count = 35, debug = false) {
  if (!secUserId) {
    return { error: "缺少 sec_user_id 参数" };
  }

  return callApi(
    "/aweme/v1/web/aweme/post/",
    {
      sec_user_id: secUserId,
      count: String(count),
      max_cursor: String(maxCursor),
      show_live_replay_strategy: "1",
      need_time_list: "0",
      time_list_query: "0",
      publish_video_strategy_type: "2",
    },
    {
      referer: `https://www.douyin.com/user/${secUserId}`,
      debug,
    }
  );
}

/**
 * 获取用户喜欢列表
 * @param {string} secUserId - 用户 sec_user_id
 * @param {number} maxCursor - 分页游标
 * @param {number} count - 每页数量 (默认 18)
 * @param {boolean} debug - 调试模式
 */
export async function getUserFavorites(secUserId, maxCursor = 0, count = 18, debug = false) {
  if (!secUserId) {
    return { error: "缺少 sec_user_id 参数" };
  }

  return callApi(
    "/aweme/v1/web/aweme/favorite/",
    {
      sec_user_id: secUserId,
      count: String(count),
      max_cursor: String(maxCursor),
      min_cursor: "0",
      whale_cut_token: "",
      cut_version: "1",
      publish_video_strategy_type: "2",
    },
    {
      referer: "https://www.douyin.com/",
      debug,
    }
  );
}

/**
 * 获取视频评论列表
 * @param {string} awemeId - 视频 ID
 * @param {number} cursor - 分页游标
 * @param {number} count - 每页数量 (默认 20)
 * @param {boolean} debug - 调试模式
 */
export async function getComments(awemeId, cursor = 0, count = 20, debug = false) {
  if (!awemeId) {
    return { error: "缺少 aweme_id 参数" };
  }

  return callApi(
    "/aweme/v1/web/comment/list/",
    {
      aweme_id: awemeId,
      cursor: String(cursor),
      count: String(count),
    },
    {
      referer: `https://www.douyin.com/video/${awemeId}`,
      debug,
    }
  );
}

/**
 * 获取评论回复列表
 * @param {string} itemId - 视频 ID
 * @param {string} commentId - 评论 ID
 * @param {number} cursor - 分页游标
 * @param {number} count - 每页数量 (默认 10)
 * @param {boolean} debug - 调试模式
 */
export async function getCommentReplies(itemId, commentId, cursor = 0, count = 10, debug = false) {
  if (!itemId || !commentId) {
    return { error: "缺少 item_id 或 comment_id 参数" };
  }

  return callApi(
    "/aweme/v1/web/comment/list/reply/",
    {
      item_id: itemId,
      comment_id: commentId,
      cursor: String(cursor),
      count: String(count),
    },
    {
      referer: `https://www.douyin.com/video/${itemId}`,
      debug,
    }
  );
}

/**
 * 获取用户关注列表
 * @param {string} secUserId - 用户 sec_user_id
 * @param {number} offset - 偏移量
 * @param {number} count - 每页数量 (默认 20)
 * @param {string} sourceType - 排序类型 (1: 最近关注, 3: 最早关注, 4: 综合排序)
 * @param {boolean} debug - 调试模式
 */
export async function getFollowing(secUserId, offset = 0, count = 20, sourceType = "4", debug = false) {
  if (!secUserId) {
    return { error: "缺少 sec_user_id 参数" };
  }

  return callApi(
    "/aweme/v1/web/user/following/list/",
    {
      sec_user_id: secUserId,
      count: String(count),
      offset: String(offset),
      source_type: sourceType,
      gps_access: "0",
      address_book_access: "0",
    },
    {
      referer: "https://www.douyin.com/user/",
      debug,
    }
  );
}

/**
 * 获取用户粉丝列表
 * @param {string} secUserId - 用户 sec_user_id
 * @param {number} offset - 偏移量
 * @param {number} count - 每页数量 (默认 20)
 * @param {boolean} debug - 调试模式
 */
export async function getFollowers(secUserId, offset = 0, count = 20, debug = false) {
  if (!secUserId) {
    return { error: "缺少 sec_user_id 参数" };
  }

  return callApi(
    "/aweme/v1/web/user/follower/list/",
    {
      sec_user_id: secUserId,
      count: String(count),
      offset: String(offset),
      gps_access: "0",
      address_book_access: "0",
      is_top: "1",
    },
    {
      referer: "https://www.douyin.com/user/",
      debug,
    }
  );
}

/**
 * 获取观看历史
 * @param {number} maxCursor - 分页游标
 * @param {number} count - 每页数量 (默认 20)
 * @param {boolean} debug - 调试模式
 */
export async function getHistory(maxCursor = 0, count = 20, debug = false) {
  return callApi(
    "/aweme/v1/web/history/read/",
    {
      count: String(count),
      max_cursor: String(maxCursor),
    },
    {
      referer: "https://www.douyin.com/",
      debug,
    }
  );
}

/**
 * 获取收藏夹列表
 * @param {number} cursor - 分页游标
 * @param {number} count - 每页数量 (默认 18)
 * @param {boolean} debug - 调试模式
 */
export async function getCollectionList(cursor = 0, count = 18, debug = false) {
  return callApi(
    "/aweme/v1/web/aweme/listcollection/",
    {
      count: String(count),
      cursor: String(cursor),
    },
    {
      method: "POST",
      referer: "https://www.douyin.com/user/self?from_tab_name=main&showTab=favorite_collection",
      debug,
    }
  );
}

/**
 * 获取收藏夹详情
 * @param {string} collectsId - 收藏夹 ID
 * @param {number} cursor - 分页游标
 * @param {number} count - 每页数量 (默认 18)
 * @param {boolean} debug - 调试模式
 */
export async function getCollectsVideo(collectsId, cursor = 0, count = 18, debug = false) {
  if (!collectsId) {
    return { error: "缺少 collects_id 参数" };
  }

  return callApi(
    "/aweme/v1/web/collects/video/list/",
    {
      collects_id: collectsId,
      count: String(count),
      cursor: String(cursor),
    },
    {
      referer: "https://www.douyin.com/user/self?from_tab_name=main&showTab=favorite_collection",
      debug,
    }
  );
}

/**
 * 获取用户合集列表
 * @param {string} secUserId - 用户 sec_user_id
 * @param {number} cursor - 分页游标
 * @param {number} count - 每页数量 (默认 10)
 * @param {boolean} debug - 调试模式
 */
export async function getMixList(secUserId, cursor = 0, count = 10, debug = false) {
  if (!secUserId) {
    return { error: "缺少 sec_user_id 参数" };
  }

  return callApi(
    "/aweme/v1/web/mix/list/",
    {
      sec_user_id: secUserId,
      count: String(count),
      cursor: String(cursor),
      req_from: "channel_pc_web",
    },
    {
      referer: `https://www.douyin.com/user/${secUserId}`,
      debug,
    }
  );
}

/**
 * 获取合集详情
 * @param {string} mixId - 合集 ID
 * @param {number} cursor - 分页游标
 * @param {number} count - 每页数量 (默认 20)
 * @param {boolean} debug - 调试模式
 */
export async function getMixAweme(mixId, cursor = 0, count = 20, debug = false) {
  if (!mixId) {
    return { error: "缺少 mix_id 参数" };
  }

  return callApi(
    "/aweme/v1/web/mix/aweme/",
    {
      mix_id: mixId,
      count: String(count),
      cursor: String(cursor),
    },
    {
      referer: "https://www.douyin.com/",
      debug,
    }
  );
}

/**
 * 获取视频详情 (通过 API)
 * @param {string} awemeId - 视频 ID
 * @param {boolean} debug - 调试模式
 */
export async function getVideoDetail(awemeId, debug = false) {
  if (!awemeId) {
    return { error: "缺少 aweme_id 参数" };
  }

  return callApi(
    "/aweme/v1/web/aweme/detail/",
    {
      aweme_id: awemeId,
    },
    {
      referer: `https://www.douyin.com/video/${awemeId}`,
      debug,
    }
  );
}

/**
 * 获取相关推荐
 * @param {string} awemeId - 视频 ID
 * @param {number} count - 每页数量 (默认 20)
 * @param {number} refreshIndex - 刷新索引
 * @param {boolean} debug - 调试模式
 */
export async function getRelated(awemeId, count = 20, refreshIndex = 1, debug = false) {
  if (!awemeId) {
    return { error: "缺少 aweme_id 参数" };
  }

  return callApi(
    "/aweme/v1/web/aweme/related/",
    {
      aweme_id: awemeId,
      count: String(count),
      refresh_index: String(refreshIndex),
      awemePcRecRawData: '{"is_client":false}',
      sub_channel_id: "0",
      "Seo-Flag": "0",
    },
    {
      referer: `https://www.douyin.com/video/${awemeId}`,
      debug,
    }
  );
}

/**
 * 获取首页 Feed
 * @param {number} count - 每页数量 (默认 20)
 * @param {number} refreshIndex - 刷新索引
 * @param {boolean} debug - 调试模式
 */
export async function getFeed(count = 20, refreshIndex = 1, debug = false) {
  return callApi(
    "/aweme/v1/web/tab/feed/",
    {
      count: String(count),
      video_type_select: "1",
      aweme_pc_rec_raw_data:
        '{"is_client":false,"ff_danmaku_status":1,"danmaku_switch_status":1,"is_auto_play":0,"is_full_screen":0,"is_full_webscreen":0,"is_mute":0,"is_speed":1,"is_visible":1,"related_recommend":1}',
      refresh_index: String(refreshIndex),
    },
    {
      referer: "https://www.douyin.com/?recommend=1",
      debug,
    }
  );
}

/**
 * 搜索用户
 * @param {string} keyword - 搜索关键词
 * @param {number} offset - 偏移量
 * @param {number} count - 每页数量 (默认 20)
 * @param {boolean} debug - 调试模式
 */
export async function searchUser(keyword, offset = 0, count = 20, debug = false) {
  if (!keyword) {
    return { error: "缺少 keyword 参数" };
  }

  return callApi(
    "/aweme/v1/web/discover/search/",
    {
      keyword: keyword,
      offset: String(offset),
      count: String(count),
      search_source: "normal_search",
      search_id: "",
      query_correct_type: "1",
      is_filter_search: "0",
    },
    {
      referer: `https://www.douyin.com/search/${encodeURIComponent(keyword)}`,
      debug,
    }
  );
}

/**
 * 搜索视频
 * @param {string} keyword - 搜索关键词
 * @param {number} offset - 偏移量
 * @param {number} count - 每页数量 (默认 20)
 * @param {boolean} debug - 调试模式
 */
export async function searchVideo(keyword, offset = 0, count = 20, debug = false) {
  if (!keyword) {
    return { error: "缺少 keyword 参数" };
  }

  return callApi(
    "/aweme/v1/web/search/item/",
    {
      keyword: keyword,
      offset: String(offset),
      count: String(count),
      search_source: "normal_search",
      search_id: "",
      query_correct_type: "1",
      is_filter_search: "0",
    },
    {
      referer: `https://www.douyin.com/search/${encodeURIComponent(keyword)}`,
      debug,
    }
  );
}

// ── Cookie 状态检查 ─────────────────────────────────────────────────────────

/**
 * 检查抖音 Cookie 状态（包含过期检测）
 * @returns {Promise<{isValid: boolean, warnings: string[], expiredFields: string[], details: object}>}
 */
export async function checkCookieStatus() {
  const cookie = await getCookie("douyin");

  if (!cookie) {
    return {
      isValid: false,
      warnings: ["未设置 Cookie"],
      expiredFields: [],
      details: {},
    };
  }

  const result = checkDouyinCookieExpiry(cookie);

  // 提取关键 Cookie 值用于详情展示
  const details = {};
  const cookiePairs = cookie.split(";").map((p) => p.trim());
  const keyFields = [
    "sid_guard",
    "sid_tt",
    "sessionid",
    "sessionid_ss",
    "passport_csrf_token",
    "msToken",
    "s_v_web_id",
    "UIFID",
  ];

  for (const field of keyFields) {
    const pair = cookiePairs.find((p) => p.startsWith(`${field}=`));
    if (pair) {
      const value = pair.split("=")[1];
      if (field === "sid_guard" || field === "sid_tt") {
        // 解析并显示过期信息
        const status = checkSidGuardExpiry(value);
        details[field] = {
          exists: true,
          isExpired: status.isExpired,
          remainingSeconds: status.remainingSeconds,
        };
      } else {
        details[field] = { exists: true };
      }
    } else {
      details[field] = { exists: false };
    }
  }

  return {
    ...result,
    details,
  };
}

// ═══════════════════════════════════════════════════════════════════════════════
// iesdouyin.com 域名 API (移动端接口，需要 a_bogus)
// 参考: sources/dy/A-Bogus-Reverse-main/test_slidesinfo.js
//       sources/dy2/datnndddouyin-download-main/src/douyin/urls.py
// 注意: 这些是备选接口，原有 parsers/douyin.js 中的实现保持不变
// ═══════════════════════════════════════════════════════════════════════════════

// iesdouyin.com 基础域名
const IESDOUYIN_HOST = "https://www.iesdouyin.com";

// 移动端参数配置
const MOBILE_CONFIG = {
  appId: 1128,        // 抖音移动端
  pageId: 9999,       // H5 页面
};

/**
 * 调用 iesdouyin.com API (移动端接口)
 * @param {string} uri - API URI
 * @param {Object} params - 请求参数
 * @param {Object} options - 选项
 * @returns {Promise<Object>}
 */
async function callMobileApi(uri, params = {}, options = {}) {
  const { referer = IESDOUYIN_HOST, debug = false } = options;
  const cookie = await getCookie("douyin");

  // 生成随机 device_id (19位)
  const deviceId = generateDeviceId();
  const webId = deviceId;

  // 合并基础参数
  const fullParams = {
    reflow_source: "reflow_page",
    web_id: webId,
    device_id: deviceId,
    aid: String(MOBILE_CONFIG.appId),
    ...params,
  };

  // 构建 query string
  const queryString = Object.entries(fullParams)
    .map(([k, v]) => `${k}=${encodeURIComponent(v)}`)
    .join("&");

  // 生成 a_bogus (使用移动端 UA)
  const mobileUA = "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36";
  const aBogus = generateABogus(queryString, mobileUA);

  if (debug) {
    console.log("[MobileAPI] URI:", uri);
    console.log("[MobileAPI] Params:", fullParams);
    console.log("[MobileAPI] a_bogus:", aBogus);
  }

  // 构建完整 URL
  const apiUrl = `${IESDOUYIN_HOST}${uri}?${queryString}&a_bogus=${encodeURIComponent(aBogus)}`;

  // 发送请求
  const headers = {
    accept: "application/json, text/plain, */*",
    "accept-language": "zh-CN,zh;q=0.9,en;q=0.8",
    "agw-js-conv": "str",
    cookie: cookie || "",
    Referer: referer,
    "User-Agent": mobileUA,
  };

  const resp = await fetchWithRetry(apiUrl, {
    method: "GET",
    headers,
  });

  const text = await resp.text();

  try {
    const json = JSON.parse(text);
    if (json.status_code !== 0) {
      return {
        error: json.status_msg || `API 错误: status_code=${json.status_code}`,
        status_code: json.status_code,
      };
    }
    return json;
  } catch (e) {
    return { error: "响应解析失败", raw: text.substring(0, 500) };
  }
}

/**
 * 生成随机 19 位数字 ID
 */
function generateDeviceId() {
  let id = "";
  for (let i = 0; i < 19; i++) {
    id += Math.floor(Math.random() * 10);
  }
  return id;
}

/**
 * 获取图集详情 (包含动图视频)
 * 这是 parsers/douyin.js 中 fetchSlidesInfo 的备选实现
 *
 * @param {string} awemeId - 作品 ID
 * @param {boolean} debug - 调试模式
 * @returns {Promise<Object>}
 */
export async function getSlidesInfo(awemeId, debug = false) {
  if (!awemeId) {
    return { error: "缺少 aweme_id 参数" };
  }

  return callMobileApi(
    "/web/api/v2/aweme/slidesinfo/",
    {
      aweme_ids: `[${awemeId}]`,
      request_source: "200",
    },
    {
      referer: `${IESDOUYIN_HOST}/share/video/${awemeId}/`,
      debug,
    }
  );
}

/**
 * 获取用户作品列表 (移动端接口)
 * 这是 getUserPosts 的备选实现，使用 iesdouyin.com 域名
 *
 * @param {string} secUserId - 用户 sec_user_id
 * @param {number} maxCursor - 分页游标
 * @param {number} count - 每页数量
 * @param {boolean} debug - 调试模式
 * @returns {Promise<Object>}
 */
export async function getUserPostsMobile(secUserId, maxCursor = 0, count = 15, debug = false) {
  if (!secUserId) {
    return { error: "缺少 sec_user_id 参数" };
  }

  return callMobileApi(
    "/web/api/v2/aweme/post/",
    {
      sec_uid: secUserId,
      count: String(count),
      max_cursor: String(maxCursor),
    },
    {
      referer: `${IESDOUYIN_HOST}/share/user/${secUserId}`,
      debug,
    }
  );
}

/**
 * 获取用户喜欢列表 (移动端接口 - 方案B)
 * 这是 getUserFavorites 的备选实现，使用 iesdouyin.com 域名
 * 注意: 这个接口可能需要特定的 Cookie 字段 (如 ttwid)
 *
 * @param {string} secUserId - 用户 sec_user_id
 * @param {number} maxCursor - 分页游标
 * @param {number} count - 每页数量
 * @param {boolean} debug - 调试模式
 * @returns {Promise<Object>}
 */
export async function getUserLikesMobile(secUserId, maxCursor = 0, count = 15, debug = false) {
  if (!secUserId) {
    return { error: "缺少 sec_user_id 参数" };
  }

  return callMobileApi(
    "/web/api/v2/aweme/like/",
    {
      sec_uid: secUserId,
      count: String(count),
      max_cursor: String(maxCursor),
    },
    {
      referer: `${IESDOUYIN_HOST}/share/user/${secUserId}`,
      debug,
    }
  );
}
