import fs from 'fs';
import path from 'path';
import { pipeline } from 'stream/promises';

const USER_AGENT = 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1';

const extractUrl = (text) => text.match(/(https?:\/\/v\.douyin\.com\/[a-zA-Z0-9/]+)/)?.[0];

async function getVideoId(shortUrl) {
    const res = await fetch(shortUrl, { redirect: 'manual', headers: { 'User-Agent': USER_AGENT } });
    const location = res.headers.get('location');
    return location?.match(/\/video\/(\d+)/)?.[1];
}

async function getHighestQualityVideo(videoId) {
    // 切换为更加开放的 api.amemv.com 接口 (常用于小程序/移动分享)
    const apiUrl = `https://www.iesdouyin.com/aweme/v1/web/aweme/detail/?aweme_id=${videoId}&aid=1128&version_name=23.5.0&device_platform=webapp`;

    const res = await fetch(apiUrl, {
        headers: {
            'User-Agent': USER_AGENT,
            'Referer': 'https://www.douyin.com/'
        }
    });

    const data = await res.json();
    const detail = data.aweme_detail;
    if (!detail) {
        console.log('数据结构:', JSON.stringify(data).substring(0, 100));
        throw new Error('接口未返回有效详情，可能是 IP 频率限制。');
    }

    // 获取码率列表
    let bitRates = detail.video?.bit_rate || [];
    
    // 如果没有 bit_rate，尝试从 play_addr 直接获取
    if (bitRates.length === 0 && detail.video?.play_addr) {
        bitRates = [{
            bit_rate: 0,
            gear_name: '默认高清',
            play_addr: detail.video.play_addr
        }];
    }

    // 降序排序
    bitRates.sort((a, b) => b.bit_rate - a.bit_rate);

    console.log('\n--- 发现可选清晰度 ---');
    bitRates.forEach((item, index) => {
        console.log(`[${index}] 标签: ${item.gear_name || '自动'} | 码率: ${(item.bit_rate / 1024).toFixed(0)}kbps`);
    });

    // 选择最高码率
    const bestMatch = bitRates[0];
    let finalUrl = bestMatch.play_addr?.url_list[0];

    // 抖音关键步骤：将播放地址中的 playwm 替换为 play 即可实现无水印
    finalUrl = finalUrl.replace('playwm', 'play');
    // 同时强制使用 HTTPS
    finalUrl = finalUrl.replace(/^http:/, 'https:');

    return {
        title: detail.desc || videoId,
        url: finalUrl,
        quality: bestMatch.gear_name
    };
}

async function download(url, filename) {
    const filePath = path.join(process.cwd(), `${filename.substring(0, 30).replace(/[\\/:*?"<>|]/g, '')}.mp4`);
    
    // 第一次请求获取重定向后的真实 CDN 地址
    const headRes = await fetch(url, { 
        headers: { 'User-Agent': USER_AGENT },
        method: 'GET' 
    });

    console.log(`\n🚀 正在从节点下载: ${headRes.url.substring(0, 50)}...`);
    
    const fileStream = fs.createWriteStream(filePath);
    await pipeline(headRes.body, fileStream);
    console.log(`\n✅ 下载完成！\n文件存放在: ${filePath}`);
}

async function main() {
    const input = process.argv[2];
    if (!input) return console.log('使用方法: node dydownloader.js "抖音分享链接"');

    try {
        console.log('🔍 正在解析链接...');
        const shortUrl = extractUrl(input);
        const videoId = await getVideoId(shortUrl);
        if (!videoId) throw new Error('无法解析视频 ID');

        console.log(`🆔 视频 ID: ${videoId}`);
        const video = await getHighestQualityVideo(videoId);
        
        await download(video.url, video.title);
    } catch (err) {
        console.error('❌ 出错了:', err.message);
        console.log('\n💡 提示: 如果持续失败，说明抖音对你的 IP 开启了验证码挑战。建议在浏览器里打开一次抖音官网，通过验证后再试。');
    }
}

main();