import {
  Ht,
  SM3,
  qt,
  m_731,
  m_732,
  m_733,
  m_734,
  m_728, m_718, nr, m_735
} from './deps.js'

// ============================================================
// A-Bogus 签名算法
// 用于抖音系 API 的请求签名验证
// ============================================================

// 请求计数器（用于确定返回值类型）
var requestCounter = 0;

// 固定请求参数（SM3 哈希的 salt 值）
const FIX_REQ_PARAMS = "dhzx";

// 初始时间戳
var initTimestamp = Date.now();

// 根据请求次数确定返回值类型
// 返回值 3/4/5/6 对应不同的签名版本
const getVersionType = function fn_149() {
  if (requestCounter > 10745) return 3;
  if (requestCounter > 1283) return 4;
  if (requestCounter > 139) return 5;
  return 6;
};

export class BDMS {

  /**
   * @param {string} ua - User-Agent 字符串
   * @param {Object} fingerprint - 浏览器指纹
   *   - innerWidth, innerHeight: 内部窗口尺寸
   *   - outerWidth, outerHeight: 外部窗口尺寸
   *   - availWidth, availHeight: 可用屏幕尺寸
   *   - sizeWidth, sizeHeight: 屏幕尺寸
   *   - platform: 平台标识 (如 "Linux armv81", "Win32")
   */
  constructor(ua, fingerprint = null) {
    this.ua = ua;
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
   * @param {number} a_0 - 固定值 1（未使用）
   * @param {number} a_1 - 固定值 0（未使用）
   * @param {number} a_2 - 固定值 8（未使用）
   * @param {string} queryString - 请求参数字符串
   * @param {string} body - 请求体，默认为空字符串
   * @param {string} userAgent - User-Agent（未使用，从构造函数获取）
   * @param {number} pageId - 页面ID
   *   - 9999: 移动端 H5 页面
   *   - 6241: PC 端页面
   * @param {number} appId - 应用ID
   *   - 1128: 抖音移动端
   *   - 6383: 抖音 PC 端
   * @param {string} version - bdms 版本号，如 "1.0.1.19-fix.01"
   */
  calculateABogus(a_0, a_1, a_2, queryString, body, userAgent, pageId, appId, version) {
    var v_0, v_1, v_2, v_3, v_4, v_5, v_6, v_7, v_8, v_9, v_10, v_11, v_12, v_13, v_14, v_15, v_16, v_17, v_18, v_19, v_20, v_21, v_22, v_23, v_24, v_25, v_26, v_27, v_28, v_29, v_30, v_31, v_32, v_33, v_34, v_35, v_36, v_37, v_38, v_39, v_40, v_41, v_42, v_43, v_44, v_45, v_46, v_47, v_48, v_49, v_50, v_51, v_52, v_53, v_54, v_55, v_56, v_57, v_58, v_59, v_60, v_61, v_62, v_63, v_64, v_65, v_66, v_67;
    
    requestCounter = requestCounter + 1;
    
    // Mock 值：版本类型标识（实际应由 getVersionType() 返回）
    v_0 = 3; // Mock
    
    // 当前时间戳
    v_1 = Date.now();
    
    // SM3 哈希实例
    v_2 = new SM3();
    
    // Mock 值：随机种子相关参数
    v_3 = 1;  // Mock: randomSeed1
    v_4 = 14; // Mock: randomSeed2
    
    // 计算请求参数的 SM3 哈希（加盐）
    // reqParamsArr = SM3(SM3(queryString + FIX_REQ_PARAMS))
    v_5 = v_2.sum(v_2.sum(queryString + FIX_REQ_PARAMS));
    
    // 计算请求体的 SM3 哈希
    v_6 = v_2.sum(v_2.sum(body + FIX_REQ_PARAMS));
    
    // 计算 User-Agent 的 SM3 哈希
    // 步骤：RC4加密 -> Base64编码 -> SM3哈希
    v_7 = v_2.sum(qt(m_728(v_3, v_4, this.ua), 's3'));
    
    // Mock 值：应该是时间相关（实际未使用）
    v_8 = Date.now(); // Mock
    
    // Base64 前缀随机数种子
    v_2 = new Array(2);
    v_2[0] = 3;
    v_2[1] = 82;
    
    // 取整函数
    v_9 = function fn_151(a_0) {
      return ~~a_0;
    };
    
    // 当前时间戳（毫秒）
    v_10 = new Date().getTime();
    
    // 计算日期时间周期数
    // 基准日期: 2024-07-25 00:00:00 UTC (1721836800000)
    // 每14天为一个周期
    v_11 = (v_10 - 1721836800000) / 1000 / 60 / 60 / 24 / 14 >> 0;
    
    // 版本类型
    v_10 = getVersionType();
    
    // 时间戳偏移量（用于时间数组）
    v_12 = initTimestamp > 0 ? v_1 - initTimestamp + 3 & 255 : 2;
    
    // 时间戳各字节
    v_13 = v_1 & 255;           // timestamp byte 0
    v_14 = v_1 >> 8 & 255;      // timestamp byte 1
    v_15 = v_1 >> 16 & 255;     // timestamp byte 2
    v_16 = v_1 >> 24 & 255;     // timestamp byte 3
    v_17 = v_1 / 256 / 256 / 256 / 256 & 255;        // timestamp byte 4
    v_18 = v_1 / 256 / 256 / 256 / 256 / 256 & 255;  // timestamp byte 5
    
    // 随机种子的字节表示
    v_19 = v_3 % 256 & 255;
    v_20 = v_3 / 256 & 255;
    
    // 获取随机指纹参数（屏幕尺寸、平台等）
    v_3 = nr();
    
    // 指纹参数的字节表示（用于校验计算）
    v_21 = v_3['4'] & 255;
    v_22 = v_3['4'] >> 8 & 255;
    v_23 = v_3['0'];
    v_24 = v_3['1'];
    v_25 = v_3['2'];
    v_26 = v_3['3'];
    
    // 随机种子2的字节表示
    v_27 = v_4 & 255;
    v_28 = v_4 >> 8 & 255;
    v_29 = v_4 >> 16 & 255;
    v_30 = v_4 >> 24 & 255;
    
    // 从请求参数哈希中提取的索引值
    v_4 = v_5['9'];
    v_31 = v_5['18'];
    v_32 = 3;
    v_33 = v_5[3];
    
    // 查找特殊索引位置（处理数组中的特定值）
    while (true) {
      if (!(v_33 === 11))
        break;
      v_63 = v_32 + 1;
      v_33 = v_63 < v_6.length ? v_5[v_63] : 12;
      v_32 = v_63;
      continue;
    }
    
    // 条件选择索引
    v_34 = v_3['4'] & 2 ? 11 : v_33;
    
    // 从 body 哈希中提取的索引值
    v_35 = v_6['10'];
    v_36 = v_6['19'];
    v_37 = 4;
    v_38 = v_6[4];
    
    while (true) {
      if (!(v_38 === 8))
        break;
      v_63 = v_37 + 1;
      v_38 = v_63 < v_6.length ? v_6[v_63] : 9;
      v_37 = v_63;
      continue;
    }
    
    v_39 = v_3['4'] & 4 ? 8 : v_38;
    
    // 从 UA 哈希中提取的索引值
    v_40 = v_7['11'];
    v_41 = v_7['21'];
    v_42 = 5;
    v_43 = v_7[5];
    
    while (true) {
      if (v_43 === 12) {
        v_63 = v_42 + 1;
        v_43 = v_63 < v_7.length ? v_7[v_63] : 13;
        v_42 = v_63;
        continue;
      }
      
      v_44 = v_3['4'] & 8 ? 12 : v_43;
      
      // Mock 时间戳的字节表示（v_8 是 Mock 值）
      v_45 = v_8 & 255;
      v_46 = v_8 >> 8 & 255;
      v_47 = v_8 >> 16 & 255;
      v_48 = v_8 >> 24 & 255;
      v_49 = v_8 / 256 / 256 / 256 / 256 & 255;
      v_50 = v_8 / 256 / 256 / 256 / 256 / 256 & 255;
      
      // pageId 各字节
      v_51 = pageId & 255;
      v_52 = pageId >> 8 & 255;
      v_53 = pageId >> 16 & 255;
      v_54 = pageId >> 24 & 255;
      
      // appId 各字节
      v_55 = appId & 255;
      v_56 = appId >> 8 & 255;
      v_57 = appId >> 16 & 255;
      v_58 = appId >> 24 & 255;
      
      // 系统指纹参数（屏幕尺寸、平台等）
      // 格式: innerWidth|innerHeight|outerWidth|outerHeight|availWidth|availHeight|sizeWidth|sizeHeight|platform
      v_59 = this.fingerprint;
      
      // 转换为字符数组
      v_60 = m_732(m_731(v_59));
      v_59 = v_60.length;
      
      // 系统参数长度
      v_61 = v_59 & 255;
      v_62 = v_59 >> 8 & 255;
      
      // 时间数组
      v_59 = m_732((v_1 + 3 & 255) + ',');
      v_63 = v_59.length;
      
      // 时间数组长度
      v_64 = v_63 & 255;
      v_65 = v_63 >> 8 & 255;
      
      // 版本号各部分异或值
      v_63 = m_733(version.split('.').map(v_9));
      v_66 = v_63['0'] ^ v_63['1'] ^ v_63['2'] ^ v_63['3'] ^ v_63['4'] ^ v_63['5'];
      
      // 计算校验位（XOR 所有相关参数）
      // getLastNumArr: 对所有参数进行异或运算得到校验字节
      v_67 = v_66 ^ v_63['6'] ^ v_63['7'] ^ 41 ^ v_11 ^ v_10 ^ v_12;
      v_66 = v_67 ^ v_13 ^ v_14 ^ v_15 ^ v_16 ^ v_17 ^ v_18 ^ v_19 ^ v_20;
      v_67 = v_66 ^ v_21 ^ v_22 ^ v_23 ^ v_24 ^ v_25 ^ v_26 ^ v_27 ^ v_28;
      v_66 = v_67 ^ v_29 ^ v_30 ^ v_4 ^ v_31 ^ v_34 ^ v_35 ^ v_36 ^ v_39;
      v_67 = v_66 ^ v_40 ^ v_41 ^ v_44 ^ v_45 ^ v_46 ^ v_47 ^ v_48 ^ v_49;
      v_66 = v_67 ^ v_50 ^ v_0 ^ v_51 ^ v_52 ^ v_53 ^ v_54 ^ v_55 ^ v_56;
      
      // 构建 50 字节的参数数组
      // getLen50Arr: 按特定顺序排列各参数字节
      v_67 = new Array(50);
      v_67[0] = v_18;  // timestamp byte 5
      v_67[1] = v_27;  // seed2 byte 0
      v_67[2] = v_40;  // uaHash[11]
      v_67[3] = v_46;  // mockTimestamp byte 1
      v_67[4] = v_57;  // appId byte 2
      v_67[5] = v_13;  // timestamp byte 0
      v_67[6] = v_54;  // pageId byte 3
      v_67[7] = v_28;  // seed2 byte 1
      v_67[8] = v_19;  // seed1 byte 0
      v_67[9] = v_31;  // reqParamsHash[18]
      v_67[10] = v_21; // fingerprint[4] byte 0
      v_67[11] = v_0;  // versionType (Mock)
      v_67[12] = v_34; // conditional index
      v_67[13] = v_52; // pageId byte 1
      v_67[14] = v_12; // timestamp offset
      v_67[15] = v_4;  // reqParamsHash[9]
      v_67[16] = v_49; // mockTimestamp byte 4
      v_67[17] = v_30; // seed2 byte 3
      v_67[18] = v_14; // timestamp byte 1
      v_67[19] = v_55; // appId byte 0
      v_67[20] = v_11; // dateTimeCycle (14天周期数)
      v_67[21] = v_39; // conditional index
      v_67[22] = v_15; // timestamp byte 2
      v_67[23] = v_53; // pageId byte 2
      v_67[24] = v_44; // uaHash conditional
      v_67[25] = v_23; // fingerprint[0]
      v_67[26] = v_47; // mockTimestamp byte 2
      v_67[27] = v_48; // mockTimestamp byte 3
      v_67[28] = v_10; // versionType
      v_67[29] = v_56; // appId byte 1
      v_67[30] = v_24; // fingerprint[1]
      v_67[31] = v_58; // appId byte 3
      v_67[32] = v_41; // uaHash[21]
      v_67[33] = v_35; // bodyHash[10]
      v_67[34] = v_25; // fingerprint[2]
      v_67[35] = v_22; // fingerprint[4] byte 1
      v_67[36] = v_17; // timestamp byte 4
      v_67[37] = v_51; // pageId byte 0
      v_67[38] = v_36; // bodyHash[19]
      v_67[39] = v_26; // fingerprint[3]
      v_67[40] = v_50; // mockTimestamp byte 5
      v_67[41] = v_29; // seed2 byte 2
      v_67[42] = v_20; // seed1 byte 1
      v_67[43] = 41;   // 固定值
      v_67[44] = v_45; // mockTimestamp byte 0
      v_67[45] = v_16; // timestamp byte 3
      v_67[46] = v_61; // systemParams length byte 0
      v_67[47] = v_62; // systemParams length byte 1
      v_67[48] = v_64; // timeArr length byte 0
      v_67[49] = v_65; // timeArr length byte 1
      
      // 校验字节数组（1字节）
      v_46 = new Array(1);
      v_46[0] = v_66 ^ v_57 ^ v_58 ^ v_61 ^ v_62 ^ v_64 ^ v_65;
      
      v_66 = String.fromCharCode;
      v_65 = m_734;  // RC4 扩展函数
      v_64 = Ht;     // RC4 加密
      v_62 = String.fromCharCode;
      
      // RC4 密钥（固定值 211 = 0xD3 = 'Ó'）
      v_61 = new Array(1);
      v_61[0] = 211;
      
      v_58 = String.fromCharCode;
      v_57 = [];
      v_54 = v_57.concat;
      
      // 构建加密数据块
      v_52 = new Array(2);
      v_52[0] = m_734(v_63);  // 版本号处理
      v_52[1] = m_734(m_735(v_67.concat(m_734(v_60), m_734(v_59), v_46)));  // 参数块
      
      // RC4 加密
      v_63 = v_64(v_62.apply(null, v_61), v_58.apply(null, v_54.apply(v_57, v_52)));
      
      // 最终 Base64 编码
      v_52 = qt(v_66.apply(String, v_65(m_718(v_2, 1))) + v_63, 's4');
      
      return v_52;
    }
  }

}
