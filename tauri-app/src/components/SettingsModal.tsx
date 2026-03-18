import { useState, useEffect } from 'react'

interface Props {
  onClose: () => void
  abogusEnabled: boolean
  onAbogusChange: (v: boolean) => void
  onSaveCookies: (xhs: string, douyin: string) => Promise<void>
  onFetchCookies: () => Promise<{ xiaohongshu: string; douyin: string }>
  onDeleteCookies: () => Promise<void>
}

function SettingsModal({ onClose, abogusEnabled, onAbogusChange, onSaveCookies, onFetchCookies, onDeleteCookies }: Props) {
  const [activeTab, setActiveTab] = useState<'xhs' | 'douyin'>('xhs')
  const [xhsCookie, setXhsCookie] = useState('')
  const [douyinCookie, setDouyinCookie] = useState('')
  const [xhsStatus, setXhsStatus] = useState('')
  const [douyinStatus, setDouyinStatus] = useState('')
  const [showHelp, setShowHelp] = useState(false)
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    loadCookieStatus()
  }, [])

  const loadCookieStatus = async () => {
    try {
      const data = await onFetchCookies()
      if (data.xiaohongshu) {
        setXhsStatus('✓ 已设置 Cookie')
      }
      if (data.douyin) {
        setDouyinStatus('✓ 已设置 Cookie')
      }
    } catch (e) {
      console.error('加载 Cookie 状态失败:', e)
    }
  }

  const handleSave = async () => {
    setSaving(true)
    try {
      await onSaveCookies(xhsCookie.trim(), douyinCookie.trim())
      if (xhsCookie.trim()) {
        setXhsStatus('✓ 小红书 Cookie 已保存')
      }
      if (douyinCookie.trim()) {
        setDouyinStatus('✓ 抖音 Cookie 已保存')
      }
      setXhsCookie('')
      setDouyinCookie('')
      setTimeout(onClose, 500)
    } catch (e: any) {
      setXhsStatus('✗ 保存失败: ' + e.message)
    } finally {
      setSaving(false)
    }
  }

  const handleClear = async () => {
    if (!confirm('确定要清除所有 Cookie 吗？')) return
    try {
      await onDeleteCookies()
      setXhsCookie('')
      setDouyinCookie('')
      setXhsStatus('✓ 已清除')
      setDouyinStatus('✓ 已清除')
      setTimeout(onClose, 500)
    } catch (e) {
      console.error('清除失败:', e)
    }
  }

  const handleBackdropClick = (e: React.MouseEvent) => {
    if (e.target === e.currentTarget) {
      onClose()
    }
  }

  return (
    <div className="modal show" onClick={handleBackdropClick}>
      <div className="modal-content">
        <div className="modal-header">
          <h3>⚙️ 设置</h3>
          <button className="modal-close" onClick={onClose}>
            ×
          </button>
        </div>
        <div className="modal-body">
          <div className="settings-section">
            <h4 className="settings-section-title">解析选项</h4>
            <label className="settings-switch">
              <input
                type="checkbox"
                checked={abogusEnabled}
                onChange={(e) => onAbogusChange(e.target.checked)}
              />
              <span className="settings-slider"></span>
              <div className="settings-switch-info">
                <span className="settings-switch-label">使用加密签名</span>
                <span className="settings-switch-desc">启用后可获取抖音动图视频（实况图）</span>
              </div>
            </label>
          </div>

          <div className="settings-divider"></div>

          <div className="settings-section">
            <h4 className="settings-section-title">Cookie 设置</h4>
            <p className="kookie-hint">
              设置 Cookie 后可获取高清原图和视频。Cookie 仅存储在本地服务器，不会上传到其他位置。
              <a href="#" onClick={(e) => { e.preventDefault(); setShowHelp(!showHelp) }}>
                如何获取 Cookie？
              </a>
            </p>

            <div className="kookie-tabs">
              <button
                className={`kookie-tab ${activeTab === 'xhs' ? 'active' : ''}`}
                onClick={() => setActiveTab('xhs')}
              >
                小红书
              </button>
              <button
                className={`kookie-tab ${activeTab === 'douyin' ? 'active' : ''}`}
                onClick={() => setActiveTab('douyin')}
              >
                抖音
              </button>
            </div>

            <div className={`kookie-tab-content ${activeTab === 'xhs' ? 'active' : ''}`}>
              <textarea
                placeholder="请粘贴小红书的 Cookie 字符串...&#10;支持格式：name=value; name2=value2&#10;或 Netscape HTTP Cookie File 格式（从浏览器扩展导出）"
                value={xhsCookie}
                onChange={(e) => setXhsCookie(e.target.value)}
              />
              <div className={`kookie-status ${xhsStatus.includes('✓') ? 'success' : ''}`}>{xhsStatus}</div>
            </div>

            <div className={`kookie-tab-content ${activeTab === 'douyin' ? 'active' : ''}`}>
              <textarea
                placeholder="请粘贴抖音的 Cookie 字符串...&#10;支持格式：name=value; name2=value2&#10;或 Netscape HTTP Cookie File 格式（从浏览器扩展导出）"
                value={douyinCookie}
                onChange={(e) => setDouyinCookie(e.target.value)}
              />
              <div className={`kookie-status ${douyinStatus.includes('✓') ? 'success' : ''}`}>{douyinStatus}</div>
            </div>

            {showHelp && (
              <div className="kookie-help">
                <h4>如何获取 Cookie：</h4>
                <h5>方法 1：使用浏览器扩展（推荐）</h5>
                <ol>
                  <li>安装 Cookie 导出扩展（如 "Get cookies.txt" 或 "Cookie-Editor"）</li>
                  <li>在浏览器中打开 <strong>小红书</strong> 或 <strong>抖音</strong> 网站并登录</li>
                  <li>点击扩展图标，选择导出/复制 Cookie</li>
                  <li>直接粘贴到上面的输入框（支持 Netscape 格式自动转换）</li>
                </ol>
                <h5>方法 2：手动从开发者工具复制</h5>
                <ol>
                  <li>在浏览器中打开 <strong>小红书</strong> 或 <strong>抖音</strong> 网站并登录</li>
                  <li>按 <kbd>F12</kbd> 打开开发者工具，切换到 Network（网络）标签</li>
                  <li>刷新页面，点击任意一个请求</li>
                  <li>在右侧找到 Headers（请求头），复制 Cookie 字段的值</li>
                </ol>
                <p>
                  提示：支持两种格式：1) <code>name=value; name2=value2</code> 2) Netscape HTTP Cookie File 格式
                </p>
              </div>
            )}
          </div>
        </div>
        <div className="modal-footer">
          <button className="btn-secondary" onClick={handleClear}>
            清除 Cookie
          </button>
          <button className="btn-primary" onClick={handleSave} disabled={saving}>
            {saving ? '保存中...' : '保存'}
          </button>
        </div>
      </div>
    </div>
  )
}

export default SettingsModal
