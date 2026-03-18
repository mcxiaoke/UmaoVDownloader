import { useState, useCallback } from 'react'
import SettingsModal from './components/SettingsModal'
import ParseResult from './components/ParseResult'
import { parseUrl, fetchCookies, saveCookies, deleteCookies, type ParseInfo } from './api'

const API_BASE = import.meta.env.VITE_API_BASE || ''

function App() {
  const [urlInput, setUrlInput] = useState('')
  const [status, setStatus] = useState('')
  const [isError, setIsError] = useState(false)
  const [isParsing, setIsParsing] = useState(false)
  const [resultInfo, setResultInfo] = useState<ParseInfo | null>(null)
  const [showSettings, setShowSettings] = useState(false)
  const [abogusEnabled, setAbogusEnabled] = useState(() => {
    return localStorage.getItem('options.abogusEnabled') === 'true'
  })

  const extractUrl = (text: string): string | null => {
    const douyinMatch =
      text.match(/https?:\/\/(?:v\.|www\.)?douyin\.com\/[A-Za-z0-9_-]+(?:\/[^\s，,。]*)?/) ||
      text.match(/https?:\/\/[^\s]*iesdouyin\.com\/[^\s，,。]+/)
    if (douyinMatch) return douyinMatch[0].replace(/[，。、\s]+$/, '')

    const xhsMatch =
      text.match(/https?:\/\/(?:www\.)?xhslink\.com\/[^\s，,。]+/) ||
      text.match(/https?:\/\/[^\s]*xiaohongshu\.com\/(?:explore|discovery|user)\/[^\s，,。]+/)
    if (xhsMatch) return xhsMatch[0].replace(/[，。、\s]+$/, '')

    return null
  }

  const getFriendlyError = (error: string): string => {
    const msg = (error || '').toLowerCase()
    if (msg.includes('不存在') || msg.includes('已删除') || msg.includes('404')) {
      return '作品不存在或已被删除'
    }
    if (msg.includes('403') || msg.includes('被拒绝') || msg.includes('私密')) {
      return '访问被拒绝，作品可能已设为私密'
    }
    if (msg.includes('401') || msg.includes('未授权') || msg.includes('登录')) {
      return '需要登录才能访问此内容'
    }
    if (msg.includes('风控') || msg.includes('挑战') || msg.includes('waf')) {
      return '触发风控，请稍后重试或更换网络'
    }
    if (msg.includes('network') || msg.includes('timeout') || msg.includes('网络')) {
      return '网络连接失败，请检查网络后重试'
    }
    if (msg.includes('无法提取') || msg.includes('未找到') || msg.includes('解析')) {
      return '解析失败，页面结构可能已变更'
    }
    return error || '解析失败，请稍后重试'
  }

  const handleParse = useCallback(async () => {
    const raw = urlInput.trim()
    if (!raw) {
      setStatus('请输入链接')
      setIsError(true)
      return
    }
    const url = extractUrl(raw)
    if (!url) {
      setStatus('未识别到支持的链接，支持抖音(v.douyin.com)和小红书(xiaohongshu.com)')
      setIsError(true)
      return
    }
    setUrlInput(url)
    setIsParsing(true)
    setResultInfo(null)
    setStatus('正在解析…')
    setIsError(false)

    try {
      const abogusParam = abogusEnabled ? '&abogus=1' : ''
      const info = await parseUrl(`${API_BASE}/parse?url=${encodeURIComponent(url)}${abogusParam}`)
      setStatus('')
      setResultInfo(info)
    } catch (e: any) {
      const friendlyMsg = getFriendlyError(e.message || '网络请求失败')
      setStatus(friendlyMsg)
      setIsError(true)
    } finally {
      setIsParsing(false)
    }
  }, [urlInput, abogusEnabled, API_BASE])

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !isParsing) {
      handleParse()
    }
  }

  const handleSaveCookies = async (xhs: string, douyin: string) => {
    await saveCookies(`${API_BASE}/api/cookies`, xhs, douyin)
  }

  const handleFetchCookies = async () => {
    return fetchCookies(`${API_BASE}/api/cookies`)
  }

  const handleDeleteCookies = async () => {
    await deleteCookies(`${API_BASE}/api/cookies`)
  }

  return (
    <>
      <header>
        <h1 onClick={() => window.location.reload()} style={{ cursor: 'pointer' }} title="点击刷新页面">
          Umao VDownloader
        </h1>
        <p>粘贴抖音/小红书分享链接，一键解析下载（无水印）</p>
      </header>

      <div className="card">
        <div className="input-row">
          <input
            type="text"
            placeholder="抖音: https://v.douyin.com/xxxxxx/  小红书: https://www.xiaohongshu.com/explore/xxxxx"
            autoFocus
            value={urlInput}
            onChange={(e) => setUrlInput(e.target.value)}
            onKeyDown={handleKeyDown}
          />
          <button onClick={handleParse} disabled={isParsing}>
            {isParsing ? '解析中...' : '解析'}
          </button>
        </div>
        <div className={isError ? 'error' : ''} id="status">
          {status}
        </div>
        {resultInfo && <ParseResult info={resultInfo} apiBase={API_BASE} />}
      </div>

      <footer>仅供个人学习使用，请勿用于侵权行为</footer>

      <div className="kookie-bar">
        <button className="kookie-btn" onClick={() => setShowSettings(true)} title="设置 Cookie 和解析选项">
          ⚙️ 设置
        </button>
      </div>

      {showSettings && (
        <SettingsModal
          onClose={() => setShowSettings(false)}
          abogusEnabled={abogusEnabled}
          onAbogusChange={(v) => {
            setAbogusEnabled(v)
            localStorage.setItem('options.abogusEnabled', String(v))
          }}
          onSaveCookies={handleSaveCookies}
          onFetchCookies={handleFetchCookies}
          onDeleteCookies={handleDeleteCookies}
        />
      )}
    </>
  )
}

export default App
