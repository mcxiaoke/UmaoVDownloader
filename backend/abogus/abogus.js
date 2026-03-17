/**
 * A-Bogus 签名算法
 * 用于抖音系 API 的请求签名验证
 * 
 * 算法流程：
 * 1. 计算请求参数、请求体、User-Agent 的 SM3 哈希
 * 2. 组合时间戳、随机种子、页面ID、应用ID等参数
 * 3. 计算校验字节
 * 4. RC4 加密 + 自定义 Base64 编码
 */

import {
  rc4Encrypt,
  SM3,
  base64Encode,
  objectToString,
  stringToByteArray,
  processVersionBytes,
  toArray,
  encryptUserAgent,
  generateRandomPrefix,
  getRandomFlags,
  obfuscateBytes
} from './deps.js';

// ============================================================
// 常量定义
// ============================================================

/**
 * SM3 哈希盐值
 * - "dhzx": 移动端/通用
 * - "cus": PC 端
 */
const HASH_SALT = "dhzx";

/**
 * 周期基准日期: 2024-07-25 00:00:00 UTC
 * 用于计算 14 天周期数
 */
const CYCLE_BASE_DATE = 1721836800000;

/**
 * 周期天数
 */
const CYCLE_DAYS = 14;

/**
 * 固定 XOR 值（用于校验计算）
 */
const FIXED_XOR_VALUE = 41;

/**
 * RC4 密钥字节
 */
const RC4_KEY_BYTE = 211;

// ============================================================
// 全局状态
// ============================================================

/**
 * 请求计数器
 * 用于确定签名版本类型
 */
var requestCounter = 0;

/**
 * 初始化时间戳
 */
var initTimestamp = Date.now();

// ============================================================
// 辅助函数
// ============================================================

/**
 * 根据请求次数确定签名版本类型
 * 返回值对应不同的签名算法版本
 * @returns {number} 版本类型 (3-6)
 */
function getVersionType() {
  if (requestCounter > 10745) return 3;
  if (requestCounter > 1283) return 4;
  if (requestCounter > 139) return 5;
  return 6;
}

/**
 * 取整函数
 * @param {number} n - 输入数值
 * @returns {number} 整数部分
 */
function floorInt(n) {
  return ~~n;
}

/**
 * 将整数拆分为字节数组
 * @param {number} value - 要拆分的值
 * @param {number} byteCount - 字节数 (1-6)
 * @returns {number[]} 字节数组
 */
function intToBytes(value, byteCount) {
  var bytes = [];
  for (var i = 0; i < byteCount; i++) {
    if (i < 4) {
      bytes.push((value >> (8 * i)) & 255);
    } else {
      // 超过 32 位，需要除法
      var divisor = Math.pow(256, i);
      bytes.push(Math.floor(value / divisor) & 255);
    }
  }
  return bytes;
}

// ============================================================
// BDMS 签名类
// ============================================================

/**
 * BDMS 签名计算器
 * 用于生成抖音 API 的 a_bogus 签名
 */
export class BDMS {

  /**
   * @param {string} userAgent - User-Agent 字符串
   * @param {Object} fingerprint - 浏览器指纹参数
   * @param {number} fingerprint.innerWidth - 内部窗口宽度
   * @param {number} fingerprint.innerHeight - 内部窗口高度
   * @param {number} fingerprint.outerWidth - 外部窗口宽度
   * @param {number} fingerprint.outerHeight - 外部窗口高度
   * @param {number} fingerprint.availWidth - 可用屏幕宽度
   * @param {number} fingerprint.availHeight - 可用屏幕高度
   * @param {number} fingerprint.sizeWidth - 屏幕宽度
   * @param {number} fingerprint.sizeHeight - 屏幕高度
   * @param {string} fingerprint.platform - 平台标识 (如 "Linux armv81", "Win32")
   */
  constructor(userAgent, fingerprint = null) {
    this.userAgent = userAgent;
    // 默认指纹 (Android Chrome 真机参数)
    this.fingerprint = fingerprint || {
      innerWidth: 980,
      innerHeight: 1762,
      outerWidth: 400,
      outerHeight: 890,
      availWidth: 400,
      availHeight: 890,
      sizeWidth: 400,
      sizeHeight: 890,
      platform: "Linux armv81"
    };
  }

  /**
   * 计算 a_bogus 签名
   * @param {number} _arg0 - 固定值 1（未使用）
   * @param {number} _arg1 - 固定值 0（未使用）
   * @param {number} _arg2 - 固定值 8（未使用）
   * @param {string} queryString - 请求参数字符串
   * @param {string} requestBody - 请求体，默认为空字符串
   * @param {string} _userAgent - User-Agent（未使用，从构造函数获取）
   * @param {number} pageId - 页面ID
   *   - 9999: 移动端 H5 页面
   *   - 6241: PC 端页面
   * @param {number} appId - 应用ID
   *   - 1128: 抖音移动端
   *   - 6383: 抖音 PC 端
   * @param {string} version - bdms 版本号，如 "1.0.1.19-fix.01"
   * @returns {string} a_bogus 签名字符串
   */
  calculateABogus(_arg0, _arg1, _arg2, queryString, requestBody, _userAgent, pageId, appId, version) {
    // 更新请求计数器
    requestCounter = requestCounter + 1;

    // --------------------------------------------------------
    // 第一阶段：计算基础参数
    // --------------------------------------------------------

    // 当前时间戳（毫秒）
    const timestamp = Date.now();

    // Mock 版本类型（实际应从 getVersionType() 获取）
    const mockVersionType = 3;

    // SM3 哈希实例
    const sm3 = new SM3();

    // RC4 加密种子参数
    const rc4Seed1 = 1;
    const rc4Seed2 = 14;

    // --------------------------------------------------------
    // 第二阶段：计算各类哈希值
    // --------------------------------------------------------

    // 请求参数的 SM3 哈希（双重哈希 + 盐值）
    const paramsHash = sm3.sum(sm3.sum(queryString + HASH_SALT));

    // 请求体的 SM3 哈希
    const bodyHash = sm3.sum(sm3.sum((requestBody || '') + HASH_SALT));

    // User-Agent 的 SM3 哈希
    // 步骤：RC4加密 -> Base64编码(s3) -> SM3哈希
    const uaEncrypted = encryptUserAgent(rc4Seed1, rc4Seed2, this.userAgent);
    const uaBase64 = base64Encode(uaEncrypted, 's3');
    const uaHash = sm3.sum(uaBase64);

    // Mock 时间戳（用于混淆）
    const mockTimestamp = Date.now();

    // --------------------------------------------------------
    // 第三阶段：准备参数字节
    // --------------------------------------------------------

    // Base64 前缀随机种子
    const prefixSeed = [3, 82];

    // 当前版本类型
    const versionType = getVersionType();

    // 计算日期周期数（从基准日期起，每14天一个周期）
    const dateCycle = Math.floor((timestamp - CYCLE_BASE_DATE) / (1000 * 60 * 60 * 24 * CYCLE_DAYS));

    // 时间戳偏移量
    const timestampOffset = initTimestamp > 0 
      ? (timestamp - initTimestamp + 3) & 255 
      : 2;

    // 时间戳各字节（6 字节）
    const tsBytes = intToBytes(timestamp, 6);

    // RC4 种子1的字节表示
    const seed1Bytes = intToBytes(rc4Seed1, 2);

    // 获取随机指纹参数
    const randomFlags = getRandomFlags();

    // 指纹参数的字节表示
    const flagBytes = [
      randomFlags[4] & 255,        // flag byte 0
      (randomFlags[4] >> 8) & 255, // flag byte 1
      randomFlags[0],
      randomFlags[1],
      randomFlags[2],
      randomFlags[3]
    ];

    // RC4 种子2的字节表示（4 字节）
    const seed2Bytes = intToBytes(rc4Seed2, 4);

    // --------------------------------------------------------
    // 第四阶段：从哈希中提取索引
    // --------------------------------------------------------

    // 从请求参数哈希提取
    let paramsIndex = paramsHash[9];
    let paramsIndexAlt = paramsHash[18];
    let paramsSearchIdx = 3;
    let paramsSearchVal = paramsHash[3];

    // 跳过值为 11 的位置
    while (paramsSearchVal === 11) {
      paramsSearchIdx++;
      paramsSearchVal = paramsSearchIdx < paramsHash.length ? paramsHash[paramsSearchIdx] : 12;
    }

    // 根据标志位选择索引
    const paramsFinalIndex = (randomFlags[4] & 2) ? 11 : paramsSearchVal;

    // 从请求体哈希提取
    let bodyIndex = bodyHash[10];
    let bodyIndexAlt = bodyHash[19];
    let bodySearchIdx = 4;
    let bodySearchVal = bodyHash[4];

    // 跳过值为 8 的位置
    while (bodySearchVal === 8) {
      bodySearchIdx++;
      bodySearchVal = bodySearchIdx < bodyHash.length ? bodyHash[bodySearchIdx] : 9;
    }

    const bodyFinalIndex = (randomFlags[4] & 4) ? 8 : bodySearchVal;

    // 从 UA 哈希提取
    let uaIndex = uaHash[11];
    let uaIndexAlt = uaHash[21];
    let uaSearchIdx = 5;
    let uaSearchVal = uaHash[5];

    // 跳过值为 12 的位置
    while (uaSearchVal === 12) {
      uaSearchIdx++;
      uaSearchVal = uaSearchIdx < uaHash.length ? uaHash[uaSearchIdx] : 13;
    }

    const uaFinalIndex = (randomFlags[4] & 8) ? 12 : uaSearchVal;

    // --------------------------------------------------------
    // 第五阶段：准备 ID 和指纹字节
    // --------------------------------------------------------

    // Mock 时间戳字节
    const mockTsBytes = intToBytes(mockTimestamp, 6);

    // pageId 字节
    const pageIdBytes = intToBytes(pageId, 4);

    // appId 字节
    const appIdBytes = intToBytes(appId, 4);

    // 浏览器指纹转字节数组
    const fingerprintStr = objectToString(this.fingerprint);
    const fingerprintBytes = stringToByteArray(fingerprintStr);
    const fingerprintLen = fingerprintBytes.length;
    const fingerprintLenBytes = intToBytes(fingerprintLen, 2);

    // 时间数组
    const timeArrStr = ((timestamp + 3) & 255) + ',';
    const timeArrBytes = stringToByteArray(timeArrStr);
    const timeArrLen = timeArrBytes.length;
    const timeArrLenBytes = intToBytes(timeArrLen, 2);

    // --------------------------------------------------------
    // 第六阶段：计算校验字节
    // --------------------------------------------------------

    // 处理版本号
    const versionBytes = processVersionBytes(version);

    // 版本号异或值
    const versionXor = versionBytes[0] ^ versionBytes[1] ^ versionBytes[2] ^ versionBytes[3] 
                     ^ versionBytes[4] ^ versionBytes[5];

    // 计算最终校验字节
    let checksum = versionXor ^ versionBytes[6] ^ versionBytes[7] 
                  ^ FIXED_XOR_VALUE ^ dateCycle ^ versionType ^ timestampOffset;

    checksum = checksum ^ tsBytes[0] ^ tsBytes[1] ^ tsBytes[2] ^ tsBytes[3] ^ tsBytes[4] ^ tsBytes[5]
             ^ seed1Bytes[0] ^ seed1Bytes[1];

    checksum = checksum ^ flagBytes[0] ^ flagBytes[1] ^ flagBytes[2] ^ flagBytes[3] ^ flagBytes[4] ^ flagBytes[5]
             ^ seed2Bytes[0] ^ seed2Bytes[1];

    checksum = checksum ^ seed2Bytes[2] ^ seed2Bytes[3] ^ paramsIndex ^ paramsIndexAlt ^ paramsFinalIndex
             ^ bodyIndex ^ bodyIndexAlt ^ bodyFinalIndex;

    checksum = checksum ^ uaIndex ^ uaIndexAlt ^ uaFinalIndex 
             ^ mockTsBytes[0] ^ mockTsBytes[1] ^ mockTsBytes[2] ^ mockTsBytes[3] ^ mockTsBytes[4] ^ mockTsBytes[5];

    checksum = checksum ^ mockVersionType 
             ^ pageIdBytes[0] ^ pageIdBytes[1] ^ pageIdBytes[2] ^ pageIdBytes[3]
             ^ appIdBytes[0] ^ appIdBytes[1];

    // --------------------------------------------------------
    // 第七阶段：构建参数数组（50 字节）
    // --------------------------------------------------------

    const paramArray = new Array(50);
    paramArray[0] = tsBytes[5];              // 时间戳字节5
    paramArray[1] = seed2Bytes[0];           // 种子2字节0
    paramArray[2] = uaIndex;                 // UA哈希索引
    paramArray[3] = mockTsBytes[1];          // Mock时间戳字节1
    paramArray[4] = appIdBytes[2];           // appId字节2
    paramArray[5] = tsBytes[0];              // 时间戳字节0
    paramArray[6] = pageIdBytes[3];          // pageId字节3
    paramArray[7] = seed2Bytes[1];           // 种子2字节1
    paramArray[8] = seed1Bytes[0];           // 种子1字节0
    paramArray[9] = paramsIndexAlt;          // 参数哈希索引
    paramArray[10] = flagBytes[0];           // 标志字节0
    paramArray[11] = mockVersionType;        // Mock版本类型
    paramArray[12] = paramsFinalIndex;       // 参数最终索引
    paramArray[13] = pageIdBytes[1];         // pageId字节1
    paramArray[14] = timestampOffset;        // 时间戳偏移
    paramArray[15] = paramsIndex;            // 参数哈希索引
    paramArray[16] = mockTsBytes[4];         // Mock时间戳字节4
    paramArray[17] = seed2Bytes[3];          // 种子2字节3
    paramArray[18] = tsBytes[1];             // 时间戳字节1
    paramArray[19] = appIdBytes[0];          // appId字节0
    paramArray[20] = dateCycle;              // 日期周期数
    paramArray[21] = bodyFinalIndex;         // 请求体最终索引
    paramArray[22] = tsBytes[2];             // 时间戳字节2
    paramArray[23] = pageIdBytes[2];         // pageId字节2
    paramArray[24] = uaFinalIndex;           // UA最终索引
    paramArray[25] = flagBytes[2];           // 标志字节2
    paramArray[26] = mockTsBytes[2];         // Mock时间戳字节2
    paramArray[27] = mockTsBytes[3];         // Mock时间戳字节3
    paramArray[28] = versionType;            // 版本类型
    paramArray[29] = appIdBytes[1];          // appId字节1
    paramArray[30] = flagBytes[3];           // 标志字节3
    paramArray[31] = appIdBytes[3];          // appId字节3
    paramArray[32] = uaIndexAlt;             // UA哈希索引备选
    paramArray[33] = bodyIndex;              // 请求体哈希索引
    paramArray[34] = flagBytes[4];           // 标志字节4
    paramArray[35] = flagBytes[1];           // 标志字节1
    paramArray[36] = tsBytes[4];             // 时间戳字节4
    paramArray[37] = pageIdBytes[0];         // pageId字节0
    paramArray[38] = bodyIndexAlt;           // 请求体哈希索引备选
    paramArray[39] = flagBytes[5];           // 标志字节5
    paramArray[40] = mockTsBytes[5];         // Mock时间戳字节5
    paramArray[41] = seed2Bytes[2];          // 种子2字节2
    paramArray[42] = seed1Bytes[1];          // 种子1字节1
    paramArray[43] = FIXED_XOR_VALUE;        // 固定XOR值
    paramArray[44] = mockTsBytes[0];         // Mock时间戳字节0
    paramArray[45] = tsBytes[3];             // 时间戳字节3
    paramArray[46] = fingerprintLenBytes[0]; // 指纹长度字节0
    paramArray[47] = fingerprintLenBytes[1]; // 指纹长度字节1
    paramArray[48] = timeArrLenBytes[0];     // 时间数组长度字节0
    paramArray[49] = timeArrLenBytes[1];     // 时间数组长度字节1

    // --------------------------------------------------------
    // 第八阶段：最终加密和编码
    // --------------------------------------------------------

    // 最终校验字节数组
    const finalChecksum = new Array(1);
    finalChecksum[0] = checksum ^ appIdBytes[2] ^ appIdBytes[3] 
                      ^ fingerprintLenBytes[0] ^ fingerprintLenBytes[1] 
                      ^ timeArrLenBytes[0] ^ timeArrLenBytes[1];

    // 构建数据块
    const dataBlock = toArray(versionBytes)
      .concat(toArray(obfuscateBytes(paramArray.concat(
        toArray(fingerprintBytes),
        toArray(timeArrBytes),
        finalChecksum
      ))));

    // RC4 加密
    const rc4Key = String.fromCharCode(RC4_KEY_BYTE);
    const rc4Data = String.fromCharCode.apply(null, dataBlock);
    const encrypted = rc4Encrypt(rc4Key, rc4Data);

    // 生成前缀
    const prefixBytes = generateRandomPrefix(prefixSeed, 1);
    const prefixStr = String.fromCharCode.apply(String, toArray(prefixBytes));

    // Base64 编码（使用 s4 字符表）
    const finalBase64 = base64Encode(prefixStr + encrypted, 's4');

    return finalBase64;
  }
}
