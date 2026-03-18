/**
 * 抖音 __ac_signature 签名生成模块
 * 
 * __ac_signature 是抖音 Cookie 中的一个签名字段，用于验证请求的合法性。
 * 格式示例: _02B4Z6wo00f01XXXXXXXXXXXX
 * 
 * 参考: sources/dynew/DouyinLiveWebFetcher-main/ac_signature.py
 * 
 * 使用方法:
 *   import { generateAcSignature } from './abogus/ac_signature.js';
 *   const signature = generateAcSignature('www.douyin.com', 'abc123', 'Mozilla/5.0...');
 */

/**
 * 计算字符串的哈希值 (方法1)
 * 使用 XOR 和乘法进行哈希计算
 * 
 * @param {string} str - 输入字符串
 * @param {number} iv - 初始向量
 * @returns {number} 32位无符号整数哈希值
 */
function hashString1(str, iv) {
  let k = iv >>> 0; // 确保是无符号32位整数
  for (let i = 0; i < str.length; i++) {
    const charCode = str.charCodeAt(i);
    // 模拟 JavaScript 的 >>> 0 (无符号右移0位，确保32位无符号)
    k = ((k ^ charCode) * 65599) >>> 0;
  }
  return k;
}

/**
 * 计算字符串的哈希值 (方法2)
 * 使用字符串长度和索引进行哈希计算
 * 
 * @param {string} str - 输入字符串
 * @param {number} iv - 初始向量
 * @returns {number} 32位无符号整数哈希值
 */
function hashString2(str, iv) {
  let k = iv >>> 0;
  const len = str.length;
  
  // 32次迭代计算
  for (let i = 0; i < 32; i++) {
    // 使用 k % len 作为索引确保在字符串范围内
    const charIndex = k % len;
    k = ((k * 65599) + str.charCodeAt(charIndex)) >>> 0;
  }
  return k;
}

/**
 * 计算字符串的哈希值 (方法3)
 * 使用纯乘法进行哈希计算
 * 
 * @param {string} str - 输入字符串
 * @param {number} iv - 初始向量
 * @returns {number} 32位无符号整数哈希值
 */
function hashString3(str, iv) {
  let k = iv >>> 0;
  for (let i = 0; i < str.length; i++) {
    k = ((k * 65599) + str.charCodeAt(i)) >>> 0;
  }
  return k;
}

/**
 * 将数字编码转换为字符
 * 
 * 编码规则:
 * - 0-25  -> A-Z (大写字母)
 * - 26-51 -> a-z (小写字母)
 * - 52-61 -> 0-9 (数字)
 * - 62-63 -> + / (特殊字符)
 * 
 * @param {number} code - 编码值 (0-63)
 * @returns {string} 对应的字符
 */
function encodeChar(code) {
  if (code < 26) {
    // A-Z (ASCII 65-90)
    return String.fromCharCode(code + 65);
  } else if (code < 52) {
    // a-z (ASCII 97-122)
    // 71 = 97 - 26
    return String.fromCharCode(code + 71);
  } else if (code < 62) {
    // 0-9 (ASCII 48-57)
    // -4 = 48 - 52
    return String.fromCharCode(code - 4);
  } else {
    // + / (ASCII 43, 47)
    // -17 = 43 - 60, -17 = 47 - 64
    return String.fromCharCode(code - 17);
  }
}

/**
 * 将32位整数编码为4字符字符串
 * 
 * 将32位整数分成4组，每组6位 (共24位)，然后编码为字符
 * 
 * @param {number} num - 32位无符号整数
 * @returns {string} 4字符编码字符串
 */
function encodeNumToStr(num) {
  let result = '';
  // 从高位到低位，每次取6位
  for (let i = 24; i >= 0; i -= 6) {
    // 提取6位数据 (& 0x3F = & 63)
    const bits = (num >>> i) & 0x3F;
    result += encodeChar(bits);
  }
  return result;
}

/**
 * 生成 __ac_signature 签名
 * 
 * @param {string} site - 网站域名 (如 'www.douyin.com')
 * @param {string} nonce - 随机字符串 (通常使用随机生成的字符串)
 * @param {string} userAgent - User-Agent 字符串
 * @param {number} [timestamp] - 时间戳 (可选，默认为当前时间)
 * @returns {string} __ac_signature 签名字符串
 * 
 * @example
 * const sig = generateAcSignature(
 *   'www.douyin.com',
 *   'abc123randomstring',
 *   'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/126.0.0.0'
 * );
 * // 输出类似: _02B4Z6wo00f01XXXXXXXXXXXX
 */
export function generateAcSignature(site, nonce, userAgent, timestamp = Math.floor(Date.now() / 1000)) {
  // 签名固定头部
  const SIGN_HEAD = '_02B4Z6wo00f01';
  
  // 将时间戳转为字符串
  const timestampStr = String(timestamp);
  
  // ── 步骤1: 计算 a ─────────────────────────────────────────────────────
  // a = hash(time_str, 0) -> hash(site, result) % 65521
  // 65521 是最大的小于 65536 的质数
  const a = hashString1(site, hashString1(timestampStr, 0)) % 65521;
  
  // ── 步骤2: 计算 b ─────────────────────────────────────────────────────
  // 创建二进制字符串: "10000000110000" + 32位二进制字符串
  // 异或值: timestamp ^ (a * 65521)
  const xorValue = timestamp ^ (a * 65521);
  const binStr = xorValue.toString(2).padStart(32, '0');
  const b = parseInt('10000000110000' + binStr, 2);
  const bStr = String(b);
  
  // ── 步骤3: 计算 c ─────────────────────────────────────────────────────
  const c = hashString1(bStr, 0);
  
  // ── 步骤4: 计算 d, e, f, g, h, i ───────────────────────────────────────
  // d: 编码 b >> 2
  const d = encodeNumToStr(b >>> 2);
  
  // e: b 的高位部分 (模拟 64 位右移)
  // JavaScript 中 Number 最大安全整数是 2^53-1，这里直接计算
  const e = Math.floor(b / 4294967296) >>> 0;
  
  // f: 编码 (b << 28) | (e >> 4)
  // 注意: JavaScript 中 << 会先转为 32 位，需要特殊处理
  const f = encodeNumToStr(((b << 28) >>> 0) | (e >>> 4));
  
  // g: 异或值
  const g = 582085784 ^ b;
  
  // h: 编码 (e << 26) | (g >> 6)
  const h = encodeNumToStr(((e << 26) >>> 0) | (g >>> 6));
  
  // i: g 的低6位编码
  const i = encodeChar(g & 0x3F);
  
  // ── 步骤5: 计算 j, k, l, m ─────────────────────────────────────────────
  // j: 组合 UA 和 nonce 的哈希值
  const uaHash = hashString1(userAgent, c) % 65521;
  const nonceHash = hashString1(nonce, c) % 65521;
  const j = ((uaHash << 16) | nonceHash) >>> 0;
  
  // k: 编码 j >> 2
  const k = encodeNumToStr(j >>> 2);
  
  // l: 编码 (j << 28) | ((524576 ^ b) >> 4)
  const l = encodeNumToStr(((j << 28) >>> 0) | ((524576 ^ b) >>> 4));
  
  // m: 编码 a
  const m = encodeNumToStr(a);
  
  // ── 步骤6: 组合各部分 ─────────────────────────────────────────────────
  const n = SIGN_HEAD + d + f + h + i + k + l + m;
  
  // ── 步骤7: 计算校验位 ─────────────────────────────────────────────────
  // 计算最终签名的哈希值，取最后两位作为校验
  const finalHash = hashString3(n, 0);
  const hashHex = finalHash.toString(16);
  const o = hashHex.slice(-2).padStart(2, '0');
  
  // 最终签名
  return n + o;
}

/**
 * 生成随机 nonce 字符串
 * 用于 __ac_signature 签名
 * 
 * @param {number} length - 字符串长度 (默认 16)
 * @returns {string} 随机字符串
 */
export function generateNonce(length = 16) {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  let result = '';
  for (let i = 0; i < length; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return result;
}

/**
 * 生成完整的 __ac_signature Cookie 值
 * 
 * @param {string} userAgent - User-Agent 字符串
 * @param {string} [site] - 网站域名 (默认 'www.douyin.com')
 * @returns {string} __ac_signature Cookie 值
 */
export function generateAcSignatureCookie(userAgent, site = 'www.douyin.com') {
  const nonce = generateNonce();
  return generateAcSignature(site, nonce, userAgent);
}
