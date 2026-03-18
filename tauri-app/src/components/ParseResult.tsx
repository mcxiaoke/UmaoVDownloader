import { useState, useRef } from 'react'
import { download } from '@tauri-apps/plugin-upload'
import { open, save } from '@tauri-apps/plugin-dialog'
import { writeFile, mkdir } from '@tauri-apps/plugin-fs'
import { join } from '@tauri-apps/api/path'
import type { ParseInfo } from '../api'

// 后端服务器地址（Tauri 下载需要完整 URL）
const BACKEND_URL = import.meta.env.VITE_API_BASE || 'http://localhost:3333'

// 缓存下载目录
let cachedDownloadDir: string | null = null

interface Props {
  info: ParseInfo
  apiBase: string
}

function escHtml(s: string) {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')
}

function dlUrl(apiBase: string, url: string, name: string) {
  const baseUrl = apiBase || ''
  return `${baseUrl}/download?url=${encodeURIComponent(url)}&name=${encodeURIComponent(name)}`
}

// 检查是否在 Tauri 环境中运行
const isTauri = typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window

// 获取下载目录（首次会弹出选择框）
async function getDownloadDir(): Promise<string | null> {
  if (cachedDownloadDir) {
    return cachedDownloadDir
  }

  // 首次选择目录
  const selectedDir = await open({
    directory: true,
    multiple: false,
    title: '选择下载保存目录',
  })

  if (selectedDir && typeof selectedDir === 'string') {
    cachedDownloadDir = selectedDir
    return selectedDir
  }

  return null
}

// Tauri 下载函数（保存到缓存目录）
async function tauriDownload(url: string, filename: string): Promise<boolean> {
  if (!isTauri) {
    // 非Tauri环境，使用传统方式
    const a = document.createElement('a')
    a.href = url
    a.download = filename
    document.body.appendChild(a)
    a.click()
    a.remove()
    return true
  }

  // 获取下载目录
  const downloadDir = await getDownloadDir()
  if (!downloadDir) {
    return false // 用户取消
  }

  // 构建完整保存路径
  const savePath = await join(downloadDir, filename)

  try {
    // Tauri 下载需要完整的后端 URL
    let fullUrl = url
    if (url.startsWith('/')) {
      fullUrl = BACKEND_URL + url
    }

    console.log('Downloading:', fullUrl, 'to', savePath)
    await download(fullUrl, savePath, (progress) => {
      console.log(`Downloaded ${progress.transfered} of ${progress.total} bytes`)
    })
    return true
  } catch (err: any) {
    console.error('Download error:', err)
    throw new Error(err?.message || err?.toString() || '下载失败')
  }
}

// 下载 Blob 到文件（用于 ZIP）
async function downloadBlob(blob: Blob, filename: string): Promise<boolean> {
  if (!isTauri) {
    const a = document.createElement('a')
    a.href = URL.createObjectURL(blob)
    a.download = filename
    document.body.appendChild(a)
    a.click()
    a.remove()
    URL.revokeObjectURL(a.href)
    return true
  }

  const downloadDir = await getDownloadDir()
  if (!downloadDir) {
    return false
  }

  const savePath = await join(downloadDir, filename)
  const arrayBuffer = await blob.arrayBuffer()
  const uint8Array = new Uint8Array(arrayBuffer)

  await writeFile(savePath, uint8Array)
  console.log('Saved blob to:', savePath)
  return true
}

function ParseResult({ info, apiBase }: Props) {
  const [downloadingIdx, setDownloadingIdx] = useState<number | null>(null)
  const [zipLoading, setZipLoading] = useState(false)
  const [videoLoading, setVideoLoading] = useState(false)
  const [musicLoading, setMusicLoading] = useState(false)

  if (info.type === 'video') {
    return (
      <VideoResult
        info={info}
        apiBase={apiBase}
        videoLoading={videoLoading}
        setVideoLoading={setVideoLoading}
      />
    )
  }

  return (
    <ImageResult
      info={info}
      apiBase={apiBase}
      downloadingIdx={downloadingIdx}
      setDownloadingIdx={setDownloadingIdx}
      zipLoading={zipLoading}
      setZipLoading={setZipLoading}
      musicLoading={musicLoading}
      setMusicLoading={setMusicLoading}
    />
  )
}

interface VideoResultProps extends Props {
  videoLoading: boolean
  setVideoLoading: (v: boolean) => void
}

function VideoResult({ info, apiBase, videoLoading, setVideoLoading }: VideoResultProps) {
  const ext = '.mp4'
  const idPart = info.shareId || info.itemId || info.id || ''
  const titlePart = (info.title || info.shareId || '').replace(/[\\/:"*?<>|]/g, '_').substring(0, 40)
  const safeName = idPart ? `${idPart}_${titlePart}` : titlePart

  const width = info.width ?? '?'
  const height = info.height ?? '?'
  const sizeMB = info.videoSize ? (info.videoSize / 1024 / 1024).toFixed(1) : null
  const bitrate = info.videoBitrate ? Math.round(info.videoBitrate / 1000) : null
  const duration = info.duration ? `${info.duration}s` : null

  let btnText = '↓ 下载视频'
  if (sizeMB) btnText += ` ${sizeMB}MB`
  if (duration) btnText += ` ${duration}`
  if (bitrate) btnText += ` ${bitrate}kb/s`
  if (width !== '?' && height !== '?') btnText += ` ${width}×${height}`

  const coverProxyUrl = info.coverUrl
    ? `${apiBase}/download?url=${encodeURIComponent(info.coverUrl)}&name=cover.jpg`
    : null

  const metaInfo = `ID: ${info.itemId || info.id || '-'} · 类型: 视频 · 数量: 1`

  const handleDownload = async () => {
    setVideoLoading(true)
    try {
      const url = dlUrl(apiBase, info.videoUrl!, `${safeName}${ext}`)
      await tauriDownload(url, `${safeName}${ext}`)
    } catch (e: any) {
      alert('下载失败：' + e.message)
    } finally {
      setVideoLoading(false)
    }
  }

  return (
    <div className="result-container">
      <div className="info-title">{info.title || info.shareId || ''}</div>
      <div className="info-meta">{metaInfo}</div>
      {coverProxyUrl && (
        <img className="video-cover" src={coverProxyUrl} loading="lazy" style={{ marginTop: '0.6rem' }} alt="cover" />
      )}
      <div className="action-btns">
        <button
          className="btn-dl primary full-width"
          onClick={handleDownload}
          disabled={videoLoading}
        >
          {videoLoading ? '下载中...' : btnText}
        </button>
        <a
          className="btn-dl secondary full-width"
          href={info.videoUrl}
          target="_blank"
          rel="noreferrer"
          title="提示：右键另存为的文件名无法控制，如需自定义文件名请使用上面的下载按钮"
        >
          新标签页打开视频（右键另存为） ↗
        </a>
      </div>
    </div>
  )
}

interface ImageResultProps extends Props {
  downloadingIdx: number | null
  setDownloadingIdx: (idx: number | null) => void
  zipLoading: boolean
  setZipLoading: (v: boolean) => void
  musicLoading: boolean
  setMusicLoading: (v: boolean) => void
}

function ImageResult({ info, apiBase, downloadingIdx, setDownloadingIdx, zipLoading, setZipLoading, musicLoading, setMusicLoading }: ImageResultProps) {
  const idPart = info.shareId || info.itemId || info.id || ''
  const titlePart = (info.title || '').replace(/[\\/:"*?<>|]/g, '_').substring(0, 40)
  const safeName = idPart ? `${idPart}_${titlePart}` : titlePart

  const imageList = info.imageList || []
  const imageUrls = info.imageUrls || []
  const imageThumbs = info.imageThumbs || []

  const handleDownloadImage = async (url: string, idx: number) => {
    setDownloadingIdx(idx)
    try {
      const name = `${safeName}_${String(idx + 1).padStart(2, '0')}.webp`
      const downloadUrl = dlUrl(apiBase, url, name)
      await tauriDownload(downloadUrl, name)
    } catch (e: any) {
      alert('下载失败：' + e.message)
    } finally {
      setDownloadingIdx(null)
    }
  }

  const handleDownloadVideo = async (videoUrl: string, idx: number) => {
    setDownloadingIdx(idx)
    try {
      const name = `${safeName}_${String(idx + 1).padStart(2, '0')}_live.mp4`
      const downloadUrl = dlUrl(apiBase, videoUrl, name)
      await tauriDownload(downloadUrl, name)
    } catch (e: any) {
      alert('视频下载失败：' + e.message)
    } finally {
      setDownloadingIdx(null)
    }
  }

  const handleZipDownload = async () => {
    setZipLoading(true)
    try {
      const filename = `${safeName}.zip`
      const resp = await fetch(`${apiBase}/zip`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          urls: imageUrls,
          names: imageUrls.map((_, i) => `${safeName}_${String(i + 1).padStart(2, '0')}.webp`),
          filename,
        }),
      })
      if (!resp.ok) {
        const err = await resp.json().catch(() => ({}))
        throw new Error(err.error ?? resp.status)
      }

      const blob = await resp.blob()
      const success = await downloadBlob(blob, filename)
      if (!success) {
        console.log('ZIP download cancelled')
      }
    } catch (e: any) {
      alert('打包失败：' + e.message)
    } finally {
      setZipLoading(false)
    }
  }

  const handleMusicDownload = async () => {
    setMusicLoading(true)
    try {
      const musicFileName =
        info.musicAuthor && info.musicTitle
          ? `${idPart}_${escHtml(info.musicAuthor).replace(/[\\/:"*?<>|]/g, '_')} - ${escHtml(info.musicTitle).replace(/[\\/:"*?<>|]/g, '_')}.mp3`
          : `${safeName}_music.mp3`
      const url = dlUrl(apiBase, info.musicUrl!, musicFileName)
      await tauriDownload(url, musicFileName)
    } catch (e: any) {
      alert('下载失败：' + e.message)
    } finally {
      setMusicLoading(false)
    }
  }

  const typeText = info.type === 'livephoto' ? '实况' : '图片'
  const metaInfo = `ID: ${info.itemId || info.id || '-'} · 类型: ${typeText} · 数量: ${info.imageCount || 0}`

  return (
    <div className="result-container">
      <div className="info-title">{info.title}</div>
      <div className="info-meta">{metaInfo}</div>
      <div className="image-grid">
        {imageUrls.map((url, i) => {
          const imgData = imageList[i] || {}
          const thumbUrl = imageThumbs[i] || url
          return (
            <div key={i} className="image-item">
              <img
                src={`${apiBase}/download?url=${encodeURIComponent(thumbUrl)}&name=thumb_${i}.webp`}
                loading="lazy"
                alt={`img-${i}`}
              />
              <button
                className="img-dl-btn"
                onClick={() => handleDownloadImage(url, i)}
                disabled={downloadingIdx === i}
              >
                {downloadingIdx === i ? '下载中...' : '↓ WebP'}
              </button>
              {imgData.isLivePhoto && imgData.videoUrl && (
                <button
                  className="img-video-btn"
                  onClick={() => handleDownloadVideo(imgData.videoUrl!, i)}
                  disabled={downloadingIdx === i}
                >
                  🎬 MP4
                </button>
              )}
            </div>
          )
        })}
      </div>
      <div className="action-btns">
        <button className="btn-dl primary full-width" onClick={handleZipDownload} disabled={zipLoading}>
          {zipLoading ? '打包中...' : `📦 打包下载全部 WebP（${info.imageCount} 张）`}
        </button>
        {info.musicUrl && (
          <button
            className="btn-dl secondary full-width"
            onClick={handleMusicDownload}
            disabled={musicLoading}
          >
            {musicLoading ? '下载中...' : `♪ 下载背景音乐${info.musicTitle ? ' · ' + info.musicTitle.substring(0, 20) : ''}`}
          </button>
        )}
      </div>
    </div>
  )
}

export default ParseResult
