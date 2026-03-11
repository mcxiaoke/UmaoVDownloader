// 这是一个基于现代 Node.js (推荐 Node.js 18+，以使用原生的 fetch API) 实现的抖音分享链接解析、最高清晰度无水印视频提取与下载工具。

// 由于抖音的接口和反爬策略（如 X-Bogus 签名验证）会不定期更新，以下代码提供的是目前业界通用的解析逻辑。

// 核心实现逻辑
// 正则提取：从用户复制的分享文本中提取出短链接（如 https://v.douyin.com/xxxx/）。

// 获取真实ID：请求短链接，获取重定向后的真实 URL，从中提取出 19 位的视频 ID (aweme_id)。

// 请求接口数据：调用抖音的公开数据接口获取视频详细信息。

// 筛选最高画质：遍历返回的 bit_rate（码率/清晰度列表），按码率降序排序，选取最高码率的无水印播放地址。

// 流式下载：使用 Node.js 的原生 stream 和 fs 模块将视频保存到本地。



import fs from 'fs';
import path from 'path';
import { pipeline } from 'stream/promises';

// 模拟常见的 User-Agent，防止被简单的反爬拦截
const USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

/**
 * 1. 从分享文本中提取短链接
 */
function extractUrl(text) {
    const urlRegex = /(https?:\/\/v\.douyin\.com\/[a-zA-Z0-9]+)/;
    const match = text.match(urlRegex);
    return match ? match[0] : null;
}

/**
 * 2. 获取短链接重定向后的视频 ID
 */
async function getVideoId(shortUrl) {
    try {
        const response = await fetch(shortUrl, {
            redirect: 'manual', // 拦截重定向以获取目标 URL
            headers: { 'User-Agent': USER_AGENT }
        });

        // 抖音短链可能会返回 301/302，目标 URL 在 location 响应头中
        const location = response.headers.get('location');
        if (!location) throw new Error('未能获取到重定向地址');

        // 正则匹配 URL 中的视频 ID (通常紧跟在 /video/ 后面)
        const idMatch = location.match(/\/video\/(\d+)/);
        return idMatch ? idMatch[1] : null;
    } catch (error) {
        console.error('获取视频 ID 失败:', error.message);
        return null;
    }
}

/**
 * 3. 获取视频详细数据并筛选最高清晰度
 */
async function getVideoDataAndUrl(videoId) {
    // 使用移动端 Feed 接口，避开 Web 端的 X-Bogus 校验
    // iid 和 device_id 可以是随机数字，此处模拟一个常用值
    const apiUrl = `https://aweme.snssdk.com/aweme/v1/feed/?aweme_id=${videoId}&device_type=iPhone&device_platform=iphone&iid=1568344901594247&device_id=4133171350438138&aid=1128&version_name=23.5.0`;

    try {
        const response = await fetch(apiUrl, {
            headers: {
                // 必须使用手机端的 User-Agent
                'User-Agent': 'TikTok 26.2.0 rv:262018 (iPhone; iOS 14.4.2; en_US) Cronet',
                'Accept': 'application/json'
            }
        });

        const data = await response.json();
        
        // 移动端接口返回的是列表，我们需要匹配对应的 aweme_id
        const awemeList = data.aweme_list || [];
        const videoInfo = awemeList.find(item => item.aweme_id === videoId) || awemeList[0];

        if (!videoInfo) throw new Error('接口未返回视频数据');

        const title = videoInfo.desc || videoId;
        
        // 关键：获取最高清晰度
        // 移动端返回的 bit_rate 列表通常包含 720p, 1080p 等不同档位
        let playUrl = '';
        if (videoInfo.video?.bit_rate?.length > 0) {
            // 按码率从大到小排序
            const sortedRates = videoInfo.video.bit_rate.sort((a, b) => b.bit_rate - a.bit_rate);
            playUrl = sortedRates[0].play_addr?.url_list[0];
            console.log(`[清晰度] 自动匹配最高码率: ${sortedRates[0].bit_rate}`);
        } else {
            playUrl = videoInfo.video?.play_addr?.url_list[0];
        }

        if (!playUrl) throw new Error('未找到播放地址');

        // 依然执行去水印操作 (将 playwm 换成 play)
        const finalUrl = playUrl.replace('playwm', 'play');

        return { title, url: finalUrl };

    } catch (error) {
        console.error('解析视频数据失败:', error.message);
        return null;
    }
}

/**
 * 4. 下载视频文件
 */
async function downloadVideo(url, filename) {
    try {
        console.log(`开始下载: ${filename}.mp4...`);
        const response = await fetch(url, {
            headers: { 'User-Agent': USER_AGENT }
        });

        if (!response.ok) throw new Error(`HTTP 状态码: ${response.status}`);

        const filePath = path.join(process.cwd(), `${filename.replace(/[\\/:*?"<>|]/g, '')}.mp4`);
        const fileStream = fs.createWriteStream(filePath);
        
        // 使用 pipeline 进行流式下载，防止大文件占用过多内存
        await pipeline(response.body, fileStream);
        console.log(`✅ 下载完成！已保存到: ${filePath}`);
    } catch (error) {
        console.error('下载失败:', error.message);
    }
}

/**
 * 主执行函数
 */
async function main() {
    // 读取命令行传入的第二个参数（即你的分享文本）
    // process.argv[0] 是 node，process.argv[1] 是脚本路径，process.argv[2] 是传入的参数
    const shareText = process.argv[2];
    
    if (!shareText) {
        return console.log('❌ 错误: 请在运行命令时传入抖音分享文本！\n示例: node douyin-downloader.js "你的分享链接"');
    }

    console.log('1. 正在解析分享文本...');
    const shortUrl = extractUrl(shareText);
    if (!shortUrl) return console.log('❌ 未在文本中找到有效的抖音分享链接。请检查格式。');

    console.log(`2. 提取到短链接: ${shortUrl}，正在获取视频ID...`);
    const videoId = await getVideoId(shortUrl);
    if (!videoId) return console.log('❌ 获取视频 ID 失败。可能链接已失效，或触发了反爬验证。');
    
    console.log(`3. 成功获取视频ID: ${videoId}，正在获取最高清晰度无水印地址...`);
    const videoData = await getVideoDataAndUrl(videoId);
    if (!videoData) return console.log('❌ 解析视频数据失败。');

    console.log(`4. 获取成功！视频标题: ${videoData.title}`);
    await downloadVideo(videoData.url, videoData.title);
}

// 运行
main();