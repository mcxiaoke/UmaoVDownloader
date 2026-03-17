/**
 * A-Bogus 依赖函数库
 * 包含 SM3 哈希、RC4 加密、Base64 编码等核心算法
 */

// ============================================================
// 辅助函数（用于类定义和类型检查）
// ============================================================

/**
 * 获取值的类型
 * @param {*} t - 要检查的值
 * @returns {string} 类型字符串
 */
function getType(t) {
  return "function" == typeof Symbol && "symbol" == typeof Symbol.iterator
    ? function (t) { return typeof t; }
    : function (t) {
        return t && "function" == typeof Symbol && t.constructor === Symbol && t !== Symbol.prototype
          ? "symbol"
          : typeof t;
      }(t);
}

/**
 * 转换为属性键名
 * @param {*} t - 要转换的值
 * @returns {string|symbol} 属性键
 */
function toPropertyKey(t) {
  var r = function (t, r) {
    if ("object" != getType(t) || !t) return t;
    var e = t[Symbol.toPrimitive];
    if (void 0 !== e) {
      var n = e.call(t, r || "default");
      if ("object" != getType(n)) return n;
      throw new TypeError("@@toPrimitive must return a primitive value.");
    }
    return ("string" === r ? String : Number)(t);
  }(t, "string");
  return "symbol" == getType(r) ? r : r + "";
}

/**
 * 定义类的属性（用于 ES5 类模拟）
 * @param {Object} target - 目标对象
 * @param {Array} descriptors - 属性描述符数组
 */
function defineClassProperties(target, descriptors) {
  for (var i = 0; i < descriptors.length; i++) {
    var desc = descriptors[i];
    desc.enumerable = desc.enumerable || false;
    desc.configurable = true;
    "value" in desc && (desc.writable = true);
    Object.defineProperty(target, toPropertyKey(desc.key), desc);
  }
}

// ============================================================
// SM3 哈希算法
// 中国国家密码标准（GB/T 32905-2016）
// ============================================================

/**
 * 循环左移
 * @param {number} value - 要移位的值
 * @param {number} bits - 移位位数
 * @returns {number} 移位后的值
 */
function rotateLeft(value, bits) {
  return (value << (bits %= 32) | value >>> 32 - bits) >>> 0;
}

/**
 * SM3 常量 Tj
 * @param {number} j - 轮次 (0-63)
 * @returns {number} 常量值
 */
function getConstantTj(j) {
  return 0 <= j && j < 16 ? 2043430169 : 16 <= j && j < 64 ? 2055708042 : void console.error("invalid j for constant Tj");
}

/**
 * SM3 布尔函数 FFj
 * @param {number} j - 轮次
 * @param {number} a, b, c - 输入值
 * @returns {number} 计算结果
 */
function boolFunctionFF(j, a, b, c) {
  return 0 <= j && j < 16 ? (a ^ b ^ c) >>> 0 : 16 <= j && j < 64 ? (a & b | a & c | b & c) >>> 0 : (console.error("invalid j for bool function FF"), 0);
}

/**
 * SM3 布尔函数 GGj
 * @param {number} j - 轮次
 * @param {number} a, b, c - 输入值
 * @returns {number} 计算结果
 */
function boolFunctionGG(j, a, b, c) {
  return 0 <= j && j < 16 ? (a ^ b ^ c) >>> 0 : 16 <= j && j < 64 ? (a & b | ~a & c) >>> 0 : (console.error("invalid j for bool function GG"), 0);
}

/**
 * SM3 哈希算法类
 * 用于计算消息的 SM3 哈希值
 */
export const SM3 = function () {
  function SM3Hash() {
    if (!(this instanceof SM3Hash)) return new SM3Hash();
    this.reg = new Array(8);   // 8 个 32 位寄存器
    this.chunk = [];            // 数据块缓冲区
    this.size = 0;              // 已处理数据大小
    this.reset();
  }

  defineClassProperties(SM3Hash.prototype, [{
    key: "reset",
    value: function () {
      // 初始向量 IV
      this.reg[0] = 0x7380166f;  // 1937774191
      this.reg[1] = 0x4914b2b9;  // 1226093241
      this.reg[2] = 0x172442d7;  // 388252375
      this.reg[3] = 0xda8a0600;  // 3666478592
      this.reg[4] = 0xa96f30bc;  // 2842636476
      this.reg[5] = 0x163138aa;  // 372324522
      this.reg[6] = 0xe38dee4d;  // 3817729613
      this.reg[7] = 0xb0fb0e4e;  // 2969243214
      this.chunk = [];
      this.size = 0;
    }
  }, {
    key: "write",
    value: function (data) {
      // 字符串转字节数组
      var bytes = "string" == typeof data ? function (str) {
        var encoded = encodeURIComponent(str).replace(/%([0-9A-F]{2})/g, function (match, hex) {
          return String.fromCharCode("0x" + hex);
        });
        var arr = new Array(encoded.length);
        Array.prototype.forEach.call(encoded, function (char, i) {
          arr[i] = char.charCodeAt(0);
        });
        return arr;
      }(data) : data;

      this.size += bytes.length;
      var remaining = 64 - this.chunk.length;

      if (bytes.length < remaining) {
        this.chunk = this.chunk.concat(bytes);
      } else {
        for (this.chunk = this.chunk.concat(bytes.slice(0, remaining)); this.chunk.length >= 64;) {
          this._compress(this.chunk);
          if (remaining < bytes.length) {
            this.chunk = bytes.slice(remaining, Math.min(remaining + 64, bytes.length));
          } else {
            this.chunk = [];
          }
          remaining += 64;
        }
      }
    }
  }, {
    key: "sum",
    value: function (data, outputFormat) {
      if (data) {
        this.reset();
        this.write(data);
      }
      this._fill();

      for (var i = 0; i < this.chunk.length; i += 64) {
        this._compress(this.chunk.slice(i, i + 64));
      }

      var result = null;
      if ("hex" == outputFormat) {
        // 十六进制输出
        result = "";
        for (i = 0; i < 8; i++) {
          var hex = this.reg[i].toString(16);
          result += hex.length >= 8 ? hex : "0".repeat(8 - hex.length) + hex;
        }
      } else {
        // 字节数组输出
        result = new Array(32);
        for (i = 0; i < 8; i++) {
          var val = this.reg[i];
          result[4 * i + 3] = (255 & val) >>> 0;
          val >>>= 8;
          result[4 * i + 2] = (255 & val) >>> 0;
          val >>>= 8;
          result[4 * i + 1] = (255 & val) >>> 0;
          val >>>= 8;
          result[4 * i] = (255 & val) >>> 0;
        }
      }
      this.reset();
      return result;
    }
  }, {
    key: "_compress",
    value: function (block) {
      if (block < 64) {
        console.error("compress error: not enough data");
        return;
      }

      // 扩展消息
      var extended = function (block) {
        var w = new Array(132);

        // W0-W15: 从块中加载
        for (var i = 0; i < 16; i++) {
          w[i] = block[4 * i] << 24;
          w[i] |= block[4 * i + 1] << 16;
          w[i] |= block[4 * i + 2] << 8;
          w[i] |= block[4 * i + 3];
          w[i] >>>= 0;
        }

        // W16-W67: 消息扩展
        for (var j = 16; j < 68; j++) {
          var tmp = w[j - 16] ^ w[j - 9] ^ rotateLeft(w[j - 3], 15);
          tmp = tmp ^ rotateLeft(tmp, 15) ^ rotateLeft(tmp, 23);
          w[j] = (tmp ^ rotateLeft(w[j - 13], 7) ^ w[j - 6]) >>> 0;
        }

        // W'0-W'63
        for (j = 0; j < 64; j++) {
          w[j + 68] = (w[j] ^ w[j + 4]) >>> 0;
        }
        return w;
      }(block);

      // 压缩函数
      var regs = this.reg.slice(0);
      for (var n = 0; n < 64; n++) {
        var ss1 = rotateLeft(regs[0], 12) + regs[4] + rotateLeft(getConstantTj(n), n);
        ss1 = rotateLeft((4294967295 & ss1) >>> 0, 7);
        var tt1 = ((ss1 ^ rotateLeft(regs[0], 12)) >>> 0);
        var ff = boolFunctionFF(n, regs[0], regs[1], regs[2]);
        ff = (4294967295 & (ff + regs[3] + tt1 + extended[n + 68])) >>> 0;
        var gg = boolFunctionGG(n, regs[4], regs[5], regs[6]);
        gg = (4294967295 & (gg + regs[7] + ss1 + extended[n])) >>> 0;

        regs[3] = regs[2];
        regs[2] = rotateLeft(regs[1], 9);
        regs[1] = regs[0];
        regs[0] = ff;
        regs[7] = regs[6];
        regs[6] = rotateLeft(regs[5], 19);
        regs[5] = regs[4];
        regs[4] = (gg ^ rotateLeft(gg, 9) ^ rotateLeft(gg, 17)) >>> 0;
      }

      // 更新寄存器
      for (var c = 0; c < 8; c++) {
        this.reg[c] = (this.reg[c] ^ regs[c]) >>> 0;
      }
    }
  }, {
    key: "_fill",
    value: function () {
      var bitLength = 8 * this.size;
      var padPos = this.chunk.push(128) % 64;

      // 填充到 56 字节（留 8 字节给长度）
      if (64 - padPos < 8) padPos -= 64;
      for (; padPos < 56; padPos++) {
        this.chunk.push(0);
      }

      // 追加 64 位长度值
      for (var i = 0; i < 4; i++) {
        var highBits = Math.floor(bitLength / 4294967296);
        this.chunk.push(highBits >>> 8 * (3 - i) & 255);
      }
      for (i = 0; i < 4; i++) {
        this.chunk.push(bitLength >>> 8 * (3 - i) & 255);
      }
    }
  }]);

  return SM3Hash;
}();

// ============================================================
// RC4 加密算法
// ============================================================

/**
 * RC4 流加密算法
 * @param {string} key - 加密密钥
 * @param {string} data - 要加密的数据
 * @returns {string} 加密后的字符串
 */
export function rc4Encrypt(key, data) {
  // 初始化 S 盒
  var sbox = [];
  for (var i = 0; i < 256; i++) {
    sbox[255 - i] = i;
  }

  // 密钥调度算法 (KSA)
  var j = 0;
  for (var i = 0; i < 256; i++) {
    j = (j * sbox[i] + j + key.charCodeAt(i % key.length)) % 256;
    // 交换 S[i] 和 S[j]
    var tmp = sbox[i];
    sbox[i] = sbox[j];
    sbox[j] = tmp;
  }

  // 伪随机生成算法 (PRGA)
  var i = 0, j2 = 0;
  var result = '';
  for (var k = 0; k < data.length; k++) {
    i = (i + 1) % 256;
    j2 = (j2 + sbox[i]) % 256;
    // 交换 S[i] 和 S[j]
    var tmp = sbox[i];
    sbox[i] = sbox[j2];
    sbox[j2] = tmp;
    // XOR 加密
    result += String.fromCharCode(data.charCodeAt(k) ^ sbox[(sbox[i] + sbox[j2]) % 256]);
  }
  return result;
}

// 别名（兼容旧代码）
export const Ht = rc4Encrypt;
export const RC4Like = rc4Encrypt;

// ============================================================
// 自定义 Base64 编码
// ============================================================

/**
 * Base64 字符表映射
 * s0: 标准 Base64
 * s1-s4: 抖音 a_bogus 专用字符表
 */
const BASE64_ALPHABETS = {
  s0: 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=',  // 标准
  s1: 'Dkdpgh4ZKsQB80/Mfvw36XI1R25+WUAlEi7NLboqYTOPuzmFjJnryx9HVGcaStCe=',  // abogus v1
  s2: 'Dkdpgh4ZKsQB80/Mfvw36XI1R25-WUAlEi7NLboqYTOPuzmFjJnryx9HVGcaStCe=',  // abogus v2
  s3: 'ckdp1h4ZKsUB80/Mfvw36XIgR25+WQAlEi7NLboqYTOPuzmFjJnryx9HVGDaStCe',   // abogus v3 (无填充)
  s4: 'Dkdpgh2ZmsQB80/MfvV36XI1R45-WUAlEixNLwoqYTOPuzKFjJnry79HbGcaStCe'    // abogus v4
};

/**
 * 自定义 Base64 编码
 * @param {string} data - 要编码的数据
 * @param {string} alphabetKey - 字符表键名 (s0-s4)
 * @returns {string} Base64 编码结果
 */
export function base64Encode(data, alphabetKey) {
  var alphabet = BASE64_ALPHABETS[alphabetKey] || BASE64_ALPHABETS.s0;
  var result = '';

  // 每 3 字节编码为 4 个字符
  for (var i = 0; i + 3 <= data.length; i += 3) {
    var b0 = data.charCodeAt(i) & 255;
    var b1 = data.charCodeAt(i + 1) & 255;
    var b2 = data.charCodeAt(i + 2) & 255;
    var triplet = (b0 << 16) | (b1 << 8) | b2;

    result += alphabet.charAt((triplet & 16515072) >> 18);  // 前 6 位
    result += alphabet.charAt((triplet & 258048) >> 12);    // 中 6 位
    result += alphabet.charAt((triplet & 4032) >> 6);       // 后 6 位
    result += alphabet.charAt(triplet & 63);                // 最后 6 位
  }

  // 处理剩余字节
  if (data.length - i > 0) {
    var b0 = data.charCodeAt(i) & 255;
    var triplet = (b0 << 16) | (i + 1 < data.length ? (data.charCodeAt(i + 1) & 255) << 8 : 0);

    result += alphabet.charAt((triplet & 16515072) >> 18);
    result += alphabet.charAt((triplet & 258048) >> 12);
    result += (i + 1 < data.length) ? alphabet.charAt((triplet & 4032) >> 6) : '=';
    result += '=';
  }

  return result;
}

// 别名（兼容旧代码）
export const qt = base64Encode;
export const Base64Like = base64Encode;

// ============================================================
// User-Agent 加密
// ============================================================

/**
 * RC4 加密 User-Agent 字符串
 * @param {number} seed1 - 种子值1（通常为 1）
 * @param {number} seed2 - 种子值2（通常为 14）
 * @param {string} userAgent - User-Agent 字符串
 * @returns {string} 加密后的字符串
 */
export function encryptUserAgent(seed1, seed2, userAgent) {
  // 构建密钥数组
  var keyBytes = new Array(3);
  keyBytes[0] = seed1 / 256;      // 高位字节
  keyBytes[1] = seed1 % 256;      // 低位字节
  keyBytes[2] = seed2 % 256;      // 种子2

  // RC4 加密
  return rc4Encrypt(String.fromCharCode.apply(null, keyBytes), userAgent.trim());
}

// 别名（兼容旧代码）
export const m_728 = encryptUserAgent;

// ============================================================
// 随机标志位生成
// ============================================================

/**
 * 获取随机标志位数组
 * 用于签名计算中的随机性参数
 * @returns {number[]} 5 字节的标志位数组
 */
export function getRandomFlags() {
  // [flag0, flag1, flag2, flag3, flag4]
  // flag4 包含配置标志 (129 = 0b10000001)
  return [0, 0, 0, 0, 129];
}

// 别名（兼容旧代码）
export const nr = getRandomFlags;

// ============================================================
// 对象序列化
// ============================================================

/**
 * 将对象转换为管道分隔的字符串
 * @param {Object} obj - 要序列化的对象
 * @returns {string} 序列化后的字符串
 * @example
 * objectToString({ a: 1, b: 2 }) => "1|2"
 */
export function objectToString(obj) {
  var result = '';
  var isFirst = true;

  Object.keys(obj).forEach(function (key) {
    if (isFirst) {
      result += obj[key];
      isFirst = false;
    } else {
      result += '|' + obj[key];
    }
  });

  return result;
}

// 别名（兼容旧代码）
export const m_731 = objectToString;

// ============================================================
// 字符串转字节数组
// ============================================================

/**
 * 将字符串转换为字节数组
 * 处理 UTF-8 多字节字符
 * @param {string} str - 输入字符串
 * @returns {number[]} 字节数组
 */
export function stringToByteArray(str) {
  var bytes = [];

  for (var i = 0; i < str.length; i++) {
    var charCode = str.charCodeAt(i);

    if (charCode & 65280) {  // 多字节字符 (> 255)
      bytes.push(charCode >> 8);      // 高字节
      bytes.push(charCode & 255);     // 低字节
    } else {
      bytes.push(charCode);
    }
  }

  return bytes;
}

// 别名（兼容旧代码）
export const m_732 = stringToByteArray;

// ============================================================
// 随机数生成器
// ============================================================

/**
 * 生成随机字节值（用于前缀）
 * 根据标志位生成不同范围的随机数
 * @returns {number} 随机字节值 (0-255)
 */
export function generateRandomByte() {
  var flags = getRandomFlags();

  if (flags[4] & 64) {
    // 模式1: 110-328 范围
    var r = Math.random() * 109 >> 0;
    return r + 110 + r % 2;
  } else {
    // 模式2: 0-240 范围
    var r = Math.random() * 240 >> 0;
    if (r > 109) {
      return r + r % 2 + 1;
    }
    return r;
  }
}

// 别名（兼容旧代码）
export const m_716 = generateRandomByte;

/**
 * 获取 Mock 时间戳值
 * @returns {number} 固定时间戳值
 */
export function getMockTimestamp() {
  return 179;
}

// 别名（兼容旧代码）
export const m_717 = getMockTimestamp;

/**
 * 获取 Mock 浏览器名称
 * @returns {string} 浏览器名称
 */
export function getMockBrowserName() {
  return "Chrome";
}

// 别名（兼容旧代码）
export const m_715 = getMockBrowserName;

/**
 * 生成随机前缀字节
 * 用于 Base64 编码前的混淆
 * @param {number[]} seedBytes - 2 字节的种子数组
 * @param {number} mode - 生成模式 (0, 1, 2)
 * @returns {number[]} 4 字节的前缀数组
 */
export function generateRandomPrefix(seedBytes, mode) {
  mode = mode || 0;
  var randomVal = Math.random() * 65535;
  var b0, b1;

  if (mode === 2) {
    // 模式2: 使用随机字节生成器
    b0 = generateRandomByte();
    b1 = getMockTimestamp();
  } else {
    // 模式0/1: 使用随机值
    b0 = randomVal & 255;
    b1 = mode === 1 ? getMockBrowserName() : (randomVal >> 8) & 255;
  }

  // 混合种子和随机值
  return [
    b0 & 170 | seedBytes[0] & 85,
    b0 & 85 | seedBytes[0] & 170,
    b1 & 170 | seedBytes[1] & 85,
    b1 & 85 | seedBytes[1] & 170
  ];
}

// 别名（兼容旧代码）
export const m_718 = generateRandomPrefix;

// ============================================================
// 版本号处理
// ============================================================

/**
 * 处理版本号字符串为字节数组
 * 将版本号各部分转换为混淆后的字节
 * @param {string} versionStr - 版本号字符串 (如 "1.0.1.19-fix.01")
 * @returns {number[]} 8 字节的版本号数组
 */
export function processVersionBytes(versionStr) {
  var parts = versionStr.split('.').map(function (p) { return ~~p; });  // 取整

  // 前两部分的随机前缀
  var prefix1 = generateRandomPrefix([parts[0], parts[1]]);
  // 后两部分的随机前缀（模式2）
  var prefix2 = generateRandomPrefix([parts[2], parts[3]], 2);

  return [
    prefix1[0], prefix1[1], prefix1[2], prefix1[3],
    prefix2[0], prefix2[1], prefix2[2], prefix2[3]
  ];
}

// 别名（兼容旧代码）
export const m_733 = processVersionBytes;

// ============================================================
// 数组转换工具
// ============================================================

/**
 * 将输入转换为数组
 * 支持数组、可迭代对象、类数组对象
 * @param {*} input - 输入值
 * @returns {Array} 数组
 */
export function toArray(input) {
  // 尝试作为可迭代对象
  var result = tryGetIterator(input);
  if (result) return result;

  // 尝试作为数组
  result = tryGetArray(input);
  if (result) return result;

  // 尝试作为类数组
  result = tryGetArrayLike(input);
  if (result) return result;

  // 失败则抛出错误
  throw new TypeError('Invalid attempt to spread non-iterable instance.\nIn order to be iterable, non-array objects must have a [Symbol.iterator]() method.');
}

/**
 * 尝试从可迭代对象获取数组
 */
function tryGetIterator(input) {
  var hasIterator = 'undefined' != typeof Symbol && null != input[Symbol.iterator] || null != input['@@iterator'];
  if (hasIterator) return Array.from(input);
}

/**
 * 尝试从数组获取副本
 */
function tryGetArray(input) {
  if (Array.isArray(input)) return copyArray(input);
}

/**
 * 复制数组
 */
function copyArray(arr, len) {
  len = null == len || len > arr.length ? arr.length : len;
  var result = Array(len);
  for (var i = 0; i < len; i++) {
    result[i] = arr[i];
  }
  return result;
}

/**
 * 尝试从类数组对象获取数组
 */
function tryGetArrayLike(input) {
  if (!input) return;

  if ('string' == typeof input) return copyArray(input);

  var typeName = {}.toString.call(input).slice(8, -1);
  var constructorName = 'Object' === typeName && input.constructor ? input.constructor.name : typeName;

  if ('Map' === constructorName || 'Set' === constructorName) {
    return Array.from(input);
  }

  if ('Arguments' === constructorName || /^(?:Ui|I)nt(?:8|16|32)(?:Clamped)?Array$/.test(constructorName)) {
    return copyArray(input);
  }
}

// 别名（兼容旧代码）
export const m_734 = toArray;
export const m_706 = tryGetIterator;
export const m_705 = tryGetArray;
export const m_709 = copyArray;
export const m_707 = tryGetArrayLike;
export const m_708 = function () { throw new TypeError('Invalid attempt to spread non-iterable instance.'); };

// ============================================================
// 字节混淆
// ============================================================

/**
 * 字节混淆函数
 * 将每 3 字节扩展为 4 字节，增加随机性
 * @param {number[]} inputBytes - 输入字节数组
 * @returns {number[]} 混淆后的字节数组
 */
export function obfuscateBytes(inputBytes) {
  var output = [];

  for (var i = 0; i < inputBytes.length; i += 3) {
    if (i + 2 < inputBytes.length) {
      // 每 3 字节扩展为 4 字节
      var randomByte = Math.random() * 1000 & 255;
      var b0 = inputBytes[i];
      var b1 = inputBytes[i + 1];
      var b2 = inputBytes[i + 2];

      // 混合原始字节和随机字节
      output.push(
        randomByte & 145 | b0 & 110,
        randomByte & 66 | b1 & 189,
        randomByte & 44 | b2 & 211,
        b0 & 145 | b1 & 66 | b2 & 44  // 校验字节
      );
    } else {
      // 剩余不足 3 字节，直接输出
      output.push(inputBytes[i]);
      if (inputBytes[i + 1] !== undefined) {
        output.push(inputBytes[i + 1]);
      }
    }
  }

  return output;
}

// 别名（兼容旧代码）
export const m_735 = obfuscateBytes;
