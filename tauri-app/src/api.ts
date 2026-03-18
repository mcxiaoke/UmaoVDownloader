export interface ParseInfo {
  type: 'video' | 'image' | 'livephoto'
  title: string
  itemId?: string
  id?: string
  shareId?: string
  // Video
  videoUrl?: string
  videoSize?: number
  videoBitrate?: number
  width?: number
  height?: number
  duration?: number
  coverUrl?: string
  // Images
  imageCount?: number
  imageUrls?: string[]
  imageThumbs?: string[]
  imageList?: Array<{
    thumb?: string
    full?: string
    videoUrl?: string
    isLivePhoto?: boolean
  }>
  // Music
  musicUrl?: string
  musicTitle?: string
  musicAuthor?: string
}

export async function parseUrl(url: string): Promise<ParseInfo> {
  const resp = await fetch(url)
  const info = await resp.json()
  if (!resp.ok) {
    throw new Error(info.error || '解析失败')
  }
  return info
}

export async function fetchCookies(url: string): Promise<{ xiaohongshu: string; douyin: string }> {
  const resp = await fetch(url)
  return resp.json()
}

export async function saveCookies(url: string, xiaohongshu: string, douyin: string): Promise<void> {
  const resp = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ xiaohongshu, douyin }),
  })
  const data = await resp.json()
  if (!resp.ok) {
    throw new Error(data.error || '保存失败')
  }
}

export async function deleteCookies(url: string): Promise<void> {
  const resp = await fetch(url, { method: 'DELETE' })
  if (!resp.ok) {
    throw new Error('删除失败')
  }
}
