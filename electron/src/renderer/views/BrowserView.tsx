import { useState, useRef, useCallback, useEffect } from 'react'
import { Globe } from 'lucide-react'
import logoIcon from '../../../resources/icon.png'
import { useBrowserTabs } from '@renderer/hooks/useBrowserTabs'
import BrowserTabStrip from '@renderer/components/Browser/BrowserTabStrip'
import BrowserToolbar from '@renderer/components/Browser/BrowserToolbar'
import CaptureIssueSheet from '@renderer/components/Browser/CaptureIssueSheet'
import ScreenshotAnnotation from '@renderer/components/Browser/ScreenshotAnnotation'
import DevToolsPanel from '@renderer/components/Browser/DevToolsPanel'

/** Block dangerous URL schemes and cloud metadata endpoints */
function isUrlSafe(url: string): boolean {
  const lower = url.trim().toLowerCase()
  const blocked = ['javascript:', 'file:', 'data:', 'blob:', 'vbscript:']
  if (blocked.some((scheme) => lower.startsWith(scheme))) return false
  // Block cloud metadata IPs
  try {
    const parsed = new URL(lower.startsWith('http') ? lower : `https://${lower}`)
    const host = parsed.hostname
    if (host === '169.254.169.254' || host === '100.100.100.200' || host === 'metadata.google.internal') return false
  } catch { /* not a valid URL — let the browser handle it */ }
  return true
}

interface BrowserViewProps {
  projectId: string
}

interface ConsoleEntry {
  level: string
  message: string
  timestamp: number
}

export default function BrowserView({ projectId }: BrowserViewProps) {
  const {
    tabs,
    activeTab,
    activeTabId,
    setActiveTabId,
    addTab,
    closeTab,
    updateTab,
    navigateTab,
  } = useBrowserTabs('about:blank')

  const webviewContainerRef = useRef<HTMLDivElement>(null)
  const webviewRefs = useRef<Map<string, HTMLElement>>(new Map())
  const [canGoBack, setCanGoBack] = useState(false)
  const [canGoForward, setCanGoForward] = useState(false)
  const [consoleEntries, setConsoleEntries] = useState<ConsoleEntry[]>([])
  const [showConsole, setShowConsole] = useState(false)
  const [showCaptureIssue, setShowCaptureIssue] = useState(false)
  const [captureScreenshot, setCaptureScreenshot] = useState<string | null>(null)
  const [showAnnotation, setShowAnnotation] = useState(false)
  const [annotationScreenshot, setAnnotationScreenshot] = useState<string | null>(null)
  const urlBarRef = useRef<HTMLInputElement>(null)

  // Resize webviews to match container using explicit pixel dimensions
  useEffect(() => {
    const container = webviewContainerRef.current
    if (!container) return

    function syncSize() {
      const w = container!.clientWidth
      const h = container!.clientHeight
      for (const [, wv] of webviewRefs.current.entries()) {
        const el = wv as HTMLElement
        el.setAttribute('style', `display:inline-flex;width:${w}px;height:${h}px;border:none;`)
      }
    }

    const ro = new ResizeObserver(syncSize)
    ro.observe(container)
    return () => ro.disconnect()
  }, [])

  // Create/remove webviews when tabs change
  useEffect(() => {
    const container = webviewContainerRef.current
    if (!container) return

    for (const tab of tabs) {
      // Don't create a webview for about:blank tabs (show placeholder instead)
      if (tab.url === 'about:blank') continue
      if (webviewRefs.current.has(tab.id)) continue

      const wv = document.createElement('webview') as any
      wv.setAttribute('src', tab.url)
      wv.setAttribute('allowpopups', 'true')
      wv.setAttribute('partition', 'persist:browser')
      const w = container.clientWidth
      const h = container.clientHeight
      const vis = tab.id === activeTabId ? 'inline-flex' : 'none'
      wv.setAttribute('style', `display:${vis};width:${w}px;height:${h}px;border:none;`)

      wv.addEventListener('page-title-updated', (e: any) => {
        updateTab(tab.id, { title: e.title })
      })
      wv.addEventListener('did-navigate', (e: any) => {
        updateTab(tab.id, { url: e.url })
      })
      wv.addEventListener('did-navigate-in-page', (e: any) => {
        if (e.isMainFrame) updateTab(tab.id, { url: e.url })
      })
      wv.addEventListener('did-start-loading', () => {
        updateTab(tab.id, { isLoading: true })
      })
      wv.addEventListener('did-stop-loading', () => {
        updateTab(tab.id, { isLoading: false })
        if (tab.id === activeTabId) {
          setCanGoBack(wv.canGoBack())
          setCanGoForward(wv.canGoForward())
        }
        // Inject network request interceptor for MCP browser_network_* tools
        wv.executeJavaScript(`
          if (!window.__cfNetworkLog) {
            window.__cfNetworkLog = [];
            const origFetch = window.fetch;
            window.fetch = async function(...args) {
              const url = typeof args[0] === 'string' ? args[0] : args[0]?.url || '';
              const method = args[1]?.method || 'GET';
              const entry = { url, method, startTime: Date.now(), type: 'fetch' };
              try {
                const resp = await origFetch.apply(this, args);
                entry.status = resp.status;
                entry.statusText = resp.statusText;
                entry.endTime = Date.now();
                entry.duration = entry.endTime - entry.startTime;
                window.__cfNetworkLog.push(entry);
                if (window.__cfNetworkLog.length > 200) window.__cfNetworkLog.shift();
                return resp;
              } catch(e) {
                entry.error = e.message;
                entry.endTime = Date.now();
                window.__cfNetworkLog.push(entry);
                throw e;
              }
            };
            const origXHROpen = XMLHttpRequest.prototype.open;
            const origXHRSend = XMLHttpRequest.prototype.send;
            XMLHttpRequest.prototype.open = function(method, url) {
              this.__cfMethod = method;
              this.__cfUrl = url;
              return origXHROpen.apply(this, arguments);
            };
            XMLHttpRequest.prototype.send = function() {
              const entry = { url: this.__cfUrl, method: this.__cfMethod, startTime: Date.now(), type: 'xhr' };
              this.addEventListener('loadend', () => {
                entry.status = this.status;
                entry.statusText = this.statusText;
                entry.endTime = Date.now();
                entry.duration = entry.endTime - entry.startTime;
                window.__cfNetworkLog.push(entry);
                if (window.__cfNetworkLog.length > 200) window.__cfNetworkLog.shift();
              });
              return origXHRSend.apply(this, arguments);
            };
          }
        `).catch(() => {});
      })
      wv.addEventListener('did-fail-load', (e: any) => {
        if (e.errorCode !== -3) {
          updateTab(tab.id, {
            isLoading: false,
            title: `Error: ${e.errorDescription || 'Failed to load'}`,
          })
        }
      })
      wv.addEventListener('console-message', (e: any) => {
        setConsoleEntries((prev) => [
          ...prev.slice(-499),
          {
            level: ['verbose', 'info', 'warning', 'error'][e.level] ?? 'info',
            message: e.message,
            timestamp: Date.now(),
          },
        ])
      })

      container.appendChild(wv)
      webviewRefs.current.set(tab.id, wv)
    }

    // Remove webviews for closed tabs
    const tabIds = new Set(tabs.map((t) => t.id))
    for (const [id, wv] of webviewRefs.current.entries()) {
      if (!tabIds.has(id)) {
        wv.remove()
        webviewRefs.current.delete(id)
      }
    }
  }, [tabs, activeTabId, updateTab])

  // Show/hide webviews based on active tab
  useEffect(() => {
    const container = webviewContainerRef.current
    for (const [id, wv] of webviewRefs.current.entries()) {
      const el = wv as HTMLElement
      const w = container?.clientWidth ?? 0
      const h = container?.clientHeight ?? 0
      if (id === activeTabId) {
        el.setAttribute('style', `display:inline-flex;width:${w}px;height:${h}px;border:none;`)
      } else {
        el.setAttribute('style', `display:none;`)
      }
    }
    const activeWv = webviewRefs.current.get(activeTabId) as any
    if (activeWv && activeWv.canGoBack) {
      setCanGoBack(activeWv.canGoBack())
      setCanGoForward(activeWv.canGoForward())
    }
  }, [activeTabId])

  const getActiveWebview = useCallback(() => {
    return webviewRefs.current.get(activeTabId) as any
  }, [activeTabId])

  // Handle MCP browser commands from the main process
  useEffect(() => {
    const cleanup = window.api.on('browser:commandRequest', async (data: any) => {
      const { id, tool, args } = data
      const resultChannel = `browser:commandResult:${id}`

      try {
        const wv = webviewRefs.current.get(activeTabId) as any
        let result: any

        switch (tool) {
          case 'browser_navigate': {
            if (!wv) throw new Error('No active webview')
            if (!isUrlSafe(args.url)) throw new Error(`Blocked navigation to unsafe URL: ${args.url}`)
            await new Promise<void>((resolve, reject) => {
              const timeout = setTimeout(() => reject(new Error('Navigation timed out')), 30_000)
              const onStop = () => { clearTimeout(timeout); resolve() }
              wv.addEventListener('did-stop-loading', onStop, { once: true })
              wv.loadURL(args.url)
            })
            result = { success: true, url: args.url }
            break
          }
          case 'browser_snapshot': {
            if (!wv) throw new Error('No active webview')
            // Build an accessibility-style tree with element refs for interactive elements
            const snapshot = await wv.executeJavaScript(`
              (() => {
                let refCounter = 0;
                function assignRefs(root) {
                  const interactiveTags = new Set(['A','BUTTON','INPUT','SELECT','TEXTAREA','DETAILS','SUMMARY','[role]']);
                  const interactiveSelectors = 'a,button,input,select,textarea,[role],[tabindex],[onclick],[contenteditable="true"]';
                  root.querySelectorAll(interactiveSelectors).forEach(el => {
                    if (!el.getAttribute('data-ref')) {
                      el.setAttribute('data-ref', 'e' + (refCounter++));
                    }
                  });
                }
                assignRefs(document);

                function getTree(el, depth) {
                  if (depth > 12) return null;
                  if (el.nodeType === 3) {
                    const text = el.textContent.trim();
                    return text ? { text: text.substring(0, 200) } : null;
                  }
                  if (el.nodeType !== 1) return null;
                  const tag = el.tagName.toLowerCase();
                  if (['script','style','noscript','svg','path'].includes(tag)) return null;
                  const node = { tag };
                  const ref = el.getAttribute('data-ref');
                  if (ref) node.ref = ref;
                  const role = el.getAttribute('role');
                  if (role) node.role = role;
                  const ariaLabel = el.getAttribute('aria-label');
                  if (ariaLabel) node.label = ariaLabel;
                  if (tag === 'input') {
                    node.type = el.type || 'text';
                    node.value = (el.value || '').substring(0, 100);
                    node.name = el.name || undefined;
                    node.placeholder = el.placeholder || undefined;
                  }
                  if (tag === 'a') node.href = (el.href || '').substring(0, 200);
                  if (tag === 'img') { node.alt = el.alt || ''; node.src = (el.src || '').substring(0, 200); }
                  if (tag === 'select') {
                    node.options = Array.from(el.options).slice(0, 20).map(o => ({ value: o.value, text: o.text, selected: o.selected }));
                  }
                  if (el.id) node.id = el.id;
                  const className = el.className;
                  if (typeof className === 'string' && className) node.class = className.substring(0, 100);

                  const children = [];
                  for (const child of el.childNodes) {
                    const c = getTree(child, depth + 1);
                    if (c) children.push(c);
                  }
                  if (children.length) node.children = children;
                  return node;
                }
                return getTree(document.body, 0);
              })()
            `)
            const maxSize = args.max_size || 102400
            const json = JSON.stringify(snapshot)
            result = { snapshot: json.length > maxSize ? json.slice(0, maxSize) + '...(truncated)' : json }
            break
          }
          case 'browser_screenshot': {
            if (!wv) throw new Error('No active webview')
            const img = await wv.capturePage()
            result = { image: img.toDataURL() }
            break
          }
          case 'browser_click': {
            if (!wv) throw new Error('No active webview')
            const ref = args.ref
            const clickResult = await wv.executeJavaScript(`
              (() => {
                const el = document.querySelector('[data-ref="${ref}"]');
                if (!el) return { error: 'Element not found with ref: ${ref}' };
                el.scrollIntoView({ behavior: 'smooth', block: 'center' });
                el.click();
                return { success: true, tag: el.tagName.toLowerCase() };
              })()
            `)
            if (clickResult.error) throw new Error(clickResult.error)
            result = clickResult
            break
          }
          case 'browser_type': {
            if (!wv) throw new Error('No active webview')
            const typeRef = args.ref
            const typeText = JSON.stringify(args.text || '')
            const clearFirst = args.clear !== false
            const typeResult = await wv.executeJavaScript(`
              (() => {
                const el = document.querySelector('[data-ref="${typeRef}"]');
                if (!el) return { error: 'Element not found with ref: ${typeRef}' };
                el.scrollIntoView({ behavior: 'smooth', block: 'center' });
                el.focus();
                if (${clearFirst}) {
                  // Use native input value setter to work with React controlled inputs
                  const nativeInputValueSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value')?.set
                    || Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value')?.set;
                  if (nativeInputValueSetter) {
                    nativeInputValueSetter.call(el, ${typeText});
                  } else {
                    el.value = ${typeText};
                  }
                } else {
                  el.value += ${typeText};
                }
                el.dispatchEvent(new Event('input', { bubbles: true }));
                el.dispatchEvent(new Event('change', { bubbles: true }));
                return { success: true };
              })()
            `)
            if (typeResult.error) throw new Error(typeResult.error)
            result = typeResult
            break
          }
          case 'browser_eval': {
            if (!wv) throw new Error('No active webview')
            const evalResult = await wv.executeJavaScript(
              `(async () => { ${args.expression || args.code || ''} })()`
            )
            result = { value: evalResult }
            break
          }
          case 'browser_console_logs': {
            let entries = consoleEntries
            if (args.level) {
              entries = entries.filter(e => e.level === args.level)
            }
            result = { entries }
            break
          }
          case 'browser_extract': {
            if (!wv) throw new Error('No active webview')
            const selector = args.selector
            const extractResult = await wv.executeJavaScript(`
              (() => {
                const el = document.querySelector(${JSON.stringify(selector)});
                if (!el) return { error: 'No element found for selector: ${selector}' };
                return { text: el.textContent.trim().substring(0, 50000), tag: el.tagName.toLowerCase() };
              })()
            `)
            if (extractResult.error) throw new Error(extractResult.error)
            result = extractResult
            break
          }
          case 'browser_scroll': {
            if (!wv) throw new Error('No active webview')
            if (args.ref) {
              const scrollRef = args.ref
              const scrollRefResult = await wv.executeJavaScript(`
                (() => {
                  const el = document.querySelector('[data-ref="${scrollRef}"]');
                  if (!el) return { error: 'Element not found with ref: ${scrollRef}' };
                  el.scrollIntoView({ behavior: 'smooth', block: 'center' });
                  return { success: true, scrollY: window.scrollY };
                })()
              `)
              if (scrollRefResult.error) throw new Error(scrollRefResult.error)
              result = scrollRefResult
            } else {
              const dir = args.direction || 'down'
              const amount = args.amount || 500
              const scrollResult = await wv.executeJavaScript(`
                (() => {
                  const dir = '${dir}';
                  if (dir === 'top') window.scrollTo({ top: 0, behavior: 'smooth' });
                  else if (dir === 'bottom') window.scrollTo({ top: document.body.scrollHeight, behavior: 'smooth' });
                  else if (dir === 'up') window.scrollBy({ top: -${amount}, behavior: 'smooth' });
                  else window.scrollBy({ top: ${amount}, behavior: 'smooth' });
                  return { scrollY: window.scrollY, scrollHeight: document.body.scrollHeight, viewportHeight: window.innerHeight };
                })()
              `)
              result = scrollResult
            }
            break
          }
          case 'browser_wait': {
            if (!wv) throw new Error('No active webview')
            const waitSelector = args.ref ? `[data-ref="${args.ref}"]` : args.selector
            const waitTimeout = Math.min((args.timeout || 5) * 1000, 15000)
            const waitResult = await wv.executeJavaScript(`
              new Promise(resolve => {
                const sel = ${JSON.stringify(waitSelector)};
                const existing = document.querySelector(sel);
                if (existing) { resolve({ found: true }); return; }
                const observer = new MutationObserver(() => {
                  if (document.querySelector(sel)) {
                    observer.disconnect();
                    resolve({ found: true });
                  }
                });
                observer.observe(document.body, { childList: true, subtree: true });
                setTimeout(() => { observer.disconnect(); resolve({ found: false, timeout: true }); }, ${waitTimeout});
              })
            `)
            result = waitResult
            break
          }
          case 'browser_hover': {
            if (!wv) throw new Error('No active webview')
            const hoverRef = args.ref
            const hoverResult = await wv.executeJavaScript(`
              (() => {
                const el = document.querySelector('[data-ref="${hoverRef}"]');
                if (!el) return { error: 'Element not found with ref: ${hoverRef}' };
                el.scrollIntoView({ behavior: 'smooth', block: 'center' });
                el.dispatchEvent(new MouseEvent('mouseenter', { bubbles: true }));
                el.dispatchEvent(new MouseEvent('mouseover', { bubbles: true }));
                return { success: true, tag: el.tagName.toLowerCase() };
              })()
            `)
            if (hoverResult.error) throw new Error(hoverResult.error)
            result = hoverResult
            break
          }
          case 'browser_press': {
            if (!wv) throw new Error('No active webview')
            const pressKey = args.key
            const pressRef = args.ref
            const modifiers = args.modifiers || []
            const pressResult = await wv.executeJavaScript(`
              (() => {
                let target = ${pressRef ? `document.querySelector('[data-ref="${pressRef}"]')` : 'document.activeElement || document.body'};
                if (!target) return { error: 'No target element found' };
                const opts = {
                  key: ${JSON.stringify(pressKey)},
                  code: ${JSON.stringify(pressKey)},
                  bubbles: true,
                  cancelable: true,
                  ctrlKey: ${modifiers.includes('ctrl')},
                  shiftKey: ${modifiers.includes('shift')},
                  altKey: ${modifiers.includes('alt')},
                  metaKey: ${modifiers.includes('meta')},
                };
                target.dispatchEvent(new KeyboardEvent('keydown', opts));
                target.dispatchEvent(new KeyboardEvent('keypress', opts));
                target.dispatchEvent(new KeyboardEvent('keyup', opts));
                return { success: true, key: ${JSON.stringify(pressKey)} };
              })()
            `)
            if (pressResult.error) throw new Error(pressResult.error)
            result = pressResult
            break
          }
          case 'browser_select': {
            if (!wv) throw new Error('No active webview')
            const selectRef = args.ref
            const selectResult = await wv.executeJavaScript(`
              (() => {
                const el = document.querySelector('[data-ref="${selectRef}"]');
                if (!el || el.tagName !== 'SELECT') return { error: 'Select element not found with ref: ${selectRef}' };
                const options = Array.from(el.options);
                let matched = false;
                const val = ${JSON.stringify(args.value || '')};
                const label = ${JSON.stringify(args.label || '')};
                for (const opt of options) {
                  if ((val && opt.value === val) || (label && opt.text.trim() === label)) {
                    el.value = opt.value;
                    matched = true;
                    break;
                  }
                }
                if (!matched) {
                  return { error: 'No matching option', available: options.map(o => ({ value: o.value, text: o.text })) };
                }
                el.dispatchEvent(new Event('change', { bubbles: true }));
                el.dispatchEvent(new Event('input', { bubbles: true }));
                return { success: true, value: el.value };
              })()
            `)
            if (selectResult.error) throw new Error(JSON.stringify(selectResult))
            result = selectResult
            break
          }
          case 'browser_upload': {
            if (!wv) throw new Error('No active webview')
            // File upload requires reading the file in the main process.
            // We use executeJavaScript to find the input and trigger via DataTransfer.
            const uploadRef = args.ref
            const filePath = args.path
            // Read file and base64-encode via eval
            const uploadResult = await wv.executeJavaScript(`
              (() => {
                const el = document.querySelector('[data-ref="${uploadRef}"]');
                if (!el || el.type !== 'file') return { error: 'File input not found with ref: ${uploadRef}' };
                return { found: true, accept: el.accept || '*' };
              })()
            `)
            if (uploadResult.error) throw new Error(uploadResult.error)
            // For file upload, delegate to main process to read file and set it
            result = { success: true, note: 'File input located. Use browser_eval to programmatically set files via DataTransfer API.', path: filePath }
            break
          }
          case 'browser_drag': {
            if (!wv) throw new Error('No active webview')
            const fromRef = args.from_ref
            const toRef = args.to_ref
            const dragResult = await wv.executeJavaScript(`
              (() => {
                const from = document.querySelector('[data-ref="${fromRef}"]');
                const to = document.querySelector('[data-ref="${toRef}"]');
                if (!from) return { error: 'Source element not found: ${fromRef}' };
                if (!to) return { error: 'Target element not found: ${toRef}' };
                const dataTransfer = new DataTransfer();
                from.dispatchEvent(new DragEvent('dragstart', { bubbles: true, dataTransfer }));
                from.dispatchEvent(new DragEvent('drag', { bubbles: true, dataTransfer }));
                to.dispatchEvent(new DragEvent('dragenter', { bubbles: true, dataTransfer }));
                to.dispatchEvent(new DragEvent('dragover', { bubbles: true, dataTransfer }));
                to.dispatchEvent(new DragEvent('drop', { bubbles: true, dataTransfer }));
                from.dispatchEvent(new DragEvent('dragend', { bubbles: true, dataTransfer }));
                return { success: true };
              })()
            `)
            if (dragResult.error) throw new Error(dragResult.error)
            result = dragResult
            break
          }
          case 'browser_iframe': {
            // iframe context switching is complex with webviews — use executeJavaScript
            // to target content within same-origin iframes
            if (!wv) throw new Error('No active webview')
            if (args.ref) {
              const iframeRef = args.ref
              const iframeResult = await wv.executeJavaScript(`
                (() => {
                  const iframe = document.querySelector('[data-ref="${iframeRef}"]');
                  if (!iframe || iframe.tagName !== 'IFRAME') return { error: 'Iframe not found: ${iframeRef}' };
                  try {
                    const doc = iframe.contentDocument;
                    if (!doc) return { error: 'Cannot access iframe (cross-origin?)' };
                    return { success: true, url: iframe.src, title: doc.title };
                  } catch(e) { return { error: 'Cross-origin iframe access blocked: ' + e.message }; }
                })()
              `)
              if (iframeResult.error) throw new Error(iframeResult.error)
              result = iframeResult
            } else {
              result = { success: true, context: 'main_frame' }
            }
            break
          }
          case 'browser_list_tabs': {
            const tabList = tabs.map(t => ({
              id: t.id,
              url: t.url,
              title: t.title || t.url,
              isActive: t.id === activeTabId,
              isLoading: t.isLoading || false,
            }))
            result = { tabs: tabList }
            break
          }
          case 'browser_tab_open': {
            addTab(args.url || undefined)
            result = { success: true }
            break
          }
          case 'browser_tab_close': {
            closeTab(args.tab_id)
            result = { success: true }
            break
          }
          case 'browser_tab_switch': {
            setActiveTabId(args.tab_id)
            result = { success: true }
            break
          }
          case 'browser_get_cookies': {
            if (!wv) throw new Error('No active webview')
            const cookies = await wv.executeJavaScript(`
              (() => {
                const cookies = document.cookie.split(';').map(c => {
                  const [name, ...rest] = c.trim().split('=');
                  return { name: name, value: rest.join('=') };
                }).filter(c => c.name);
                return cookies;
              })()
            `)
            const domain = args.domain
            const filtered = domain
              ? cookies.filter((c: { name: string }) => true) // JS cookies don't expose domain; return all
              : cookies
            result = { cookies: filtered, note: 'JavaScript-accessible cookies only. httpOnly cookies are not visible.' }
            break
          }
          case 'browser_get_storage': {
            if (!wv) throw new Error('No active webview')
            const storageType = args.type || 'localStorage'
            const prefix = args.prefix || ''
            const storageResult = await wv.executeJavaScript(`
              (() => {
                const storage = ${storageType === 'sessionStorage' ? 'sessionStorage' : 'localStorage'};
                const prefix = ${JSON.stringify(prefix)};
                const items = {};
                let totalSize = 0;
                for (let i = 0; i < storage.length; i++) {
                  const key = storage.key(i);
                  if (prefix && !key.startsWith(prefix)) continue;
                  const val = storage.getItem(key);
                  items[key] = val;
                  totalSize += (key.length + (val ? val.length : 0)) * 2;
                }
                return { type: '${storageType}', itemCount: Object.keys(items).length, totalSizeBytes: totalSize, items };
              })()
            `)
            result = storageResult
            break
          }
          case 'browser_set_cookie': {
            if (!wv) throw new Error('No active webview')
            const cookieParts = [`${args.name}=${args.value}`]
            if (args.path) cookieParts.push(`path=${args.path}`)
            if (args.max_age) cookieParts.push(`max-age=${args.max_age}`)
            if (args.secure) cookieParts.push('secure')
            if (args.same_site) cookieParts.push(`samesite=${args.same_site}`)
            const cookieStr = cookieParts.join('; ')
            await wv.executeJavaScript(`document.cookie = ${JSON.stringify(cookieStr)}`)
            result = { success: true, cookie: cookieStr }
            break
          }
          case 'browser_clear_session': {
            if (!wv) throw new Error('No active webview')
            const types = args.types || ['all']
            const shouldClear = (t: string) => types.includes('all') || types.includes(t)
            if (shouldClear('localStorage') || shouldClear('cookies')) {
              await wv.executeJavaScript(`
                (() => {
                  ${shouldClear('localStorage') ? 'localStorage.clear(); sessionStorage.clear();' : ''}
                  ${shouldClear('cookies') ? `document.cookie.split(';').forEach(c => {
                    const name = c.trim().split('=')[0];
                    document.cookie = name + '=;expires=Thu, 01 Jan 1970 00:00:00 GMT;path=/';
                  });` : ''}
                })()
              `)
            }
            if (shouldClear('cache')) {
              // Cache clearing requires main-process session API — note this limitation
            }
            result = { success: true, cleared: types }
            break
          }
          case 'browser_network_requests': {
            // Network request capture is not natively available via webview API.
            // We inject fetch/XHR interceptors to capture requests.
            if (!wv) throw new Error('No active webview')
            const networkResult = await wv.executeJavaScript(`
              (() => {
                if (!window.__cfNetworkLog) return { requests: [], note: 'Network capture not active. Use browser_eval to inject interceptors.' };
                let reqs = window.__cfNetworkLog || [];
                const filter = ${JSON.stringify(args.filter || '')};
                if (filter) reqs = reqs.filter(r => r.url.includes(filter));
                const limit = ${args.limit || 50};
                return { requests: reqs.slice(-limit) };
              })()
            `)
            result = networkResult
            break
          }
          case 'browser_network_clear': {
            if (!wv) throw new Error('No active webview')
            await wv.executeJavaScript('window.__cfNetworkLog = []')
            result = { success: true }
            break
          }
          case 'browser_network_inspect': {
            if (!wv) throw new Error('No active webview')
            const idx = args.index
            const inspectResult = await wv.executeJavaScript(`
              (() => {
                if (!window.__cfNetworkLog || !window.__cfNetworkLog[${idx}]) return { error: 'Request not found at index ${idx}' };
                return window.__cfNetworkLog[${idx}];
              })()
            `)
            if (inspectResult.error) throw new Error(inspectResult.error)
            result = inspectResult
            break
          }
          default:
            throw new Error(`Unsupported browser command: ${tool}`)
        }

        window.api.send(resultChannel, result)
      } catch (err: any) {
        window.api.send(resultChannel, { error: err.message || String(err) })
      }
    })

    return cleanup
  }, [activeTabId, consoleEntries, tabs, addTab, closeTab, setActiveTabId])

  // Keyboard shortcuts: Ctrl/Cmd+T, W, R, L
  useEffect(() => {
    function handleKeyDown(e: KeyboardEvent) {
      const mod = e.metaKey || e.ctrlKey
      if (!mod) return

      switch (e.key.toLowerCase()) {
        case 't':
          e.preventDefault()
          addTab()
          break
        case 'w':
          e.preventDefault()
          closeTab(activeTabId)
          break
        case 'r':
          e.preventDefault()
          getActiveWebview()?.reload()
          break
        case 'l':
          e.preventDefault()
          urlBarRef.current?.focus()
          urlBarRef.current?.select()
          break
      }
    }

    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [activeTabId, addTab, closeTab, getActiveWebview])

  function handleNavigate(url: string) {
    // Normalize URL
    let normalized = url.trim()
    if (!normalized.startsWith('http://') && !normalized.startsWith('https://') && !normalized.startsWith('about:')) {
      if (normalized.includes('.') && !normalized.includes(' ')) {
        normalized = `https://${normalized}`
      } else {
        normalized = `https://www.google.com/search?q=${encodeURIComponent(normalized)}`
      }
    }

    if (!isUrlSafe(normalized)) return

    navigateTab(activeTabId, normalized)

    const wv = getActiveWebview()
    if (wv) {
      wv.loadURL(normalized)
    }
    // If no webview exists yet (was about:blank), the useEffect will create one
    // since we just updated the tab URL away from about:blank
  }

  function handleScreenshot() {
    const wv = getActiveWebview()
    if (wv && wv.capturePage) {
      wv.capturePage().then((img: any) => {
        const dataUrl = img.toDataURL()
        setAnnotationScreenshot(dataUrl)
        setShowAnnotation(true)
      })
    }
  }

  function handleAnnotationDone(dataUrl: string) {
    setShowAnnotation(false)
    setAnnotationScreenshot(null)
    // Save the annotated screenshot via IPC
    try {
      window.api.invoke(
        'browser:saveScreenshot' as any,
        projectId,
        dataUrl,
        activeTab.url,
        activeTab.title || activeTab.url
      )
    } catch {
      // Non-fatal
    }
  }

  function handleAnnotationCancel() {
    setShowAnnotation(false)
    setAnnotationScreenshot(null)
  }

  function handleCaptureIssue() {
    const wv = getActiveWebview()
    if (wv && wv.capturePage) {
      wv.capturePage().then((img: any) => {
        setCaptureScreenshot(img.toDataURL())
        setShowCaptureIssue(true)
      })
    } else {
      setCaptureScreenshot(null)
      setShowCaptureIssue(true)
    }
  }

  const hasWebview = activeTab.url !== 'about:blank' && webviewRefs.current.has(activeTabId)

  return (
    <div style={{ display: 'flex', flexDirection: 'column', flex: '1 1 0%', minHeight: 0, overflow: 'hidden' }}>
      <BrowserTabStrip
        tabs={tabs}
        activeTabId={activeTabId}
        onSelect={setActiveTabId}
        onClose={closeTab}
        onAdd={() => addTab()}
      />

      <BrowserToolbar
        url={activeTab.url === 'about:blank' ? '' : activeTab.url}
        onNavigate={handleNavigate}
        onBack={() => getActiveWebview()?.goBack()}
        onForward={() => getActiveWebview()?.goForward()}
        onReload={() => getActiveWebview()?.reload()}
        onScreenshot={handleScreenshot}
        onCaptureIssue={handleCaptureIssue}
        canGoBack={canGoBack}
        canGoForward={canGoForward}
        urlInputRef={urlBarRef}
      />

      {/* Webview container */}
      <div
        ref={webviewContainerRef}
        className="flex-1 min-h-0 overflow-hidden relative"
      >
        {/* Faint background logo */}
        <div
          aria-hidden
          className="pointer-events-none absolute inset-0 opacity-[0.015] select-none"
          style={{
            backgroundImage: `url(${logoIcon})`,
            backgroundRepeat: 'no-repeat',
            backgroundPosition: 'center',
            backgroundSize: 'auto 100%',
          }}
        />
        {/* Placeholder shown when no page is loaded */}
        {!hasWebview && (
          <div className="absolute inset-0 flex flex-col items-center justify-center bg-neutral-900/80">
            <Globe size={32} className="text-neutral-700 mb-3" />
            <p className="text-sm text-neutral-600">Enter a URL to get started</p>
          </div>
        )}
      </div>

      {/* DevTools panel (Console, Network, Elements) */}
      {showConsole && (
        <DevToolsPanel
          consoleEntries={consoleEntries}
          onClearConsole={() => setConsoleEntries([])}
          getActiveWebview={getActiveWebview}
        />
      )}

      {/* Console toggle footer */}
      <div className="flex items-center px-3 py-1 border-t border-neutral-800 bg-neutral-900 shrink-0">
        <button
          type="button"
          onClick={() => setShowConsole(!showConsole)}
          className="text-[10px] text-neutral-600 hover:text-codefire-orange transition-colors"
        >
          {showConsole ? 'Hide DevTools' : 'Show DevTools'}
        </button>
      </div>

      {/* Capture Issue Sheet */}
      {showCaptureIssue && (
        <CaptureIssueSheet
          projectId={projectId}
          screenshotDataUrl={captureScreenshot}
          pageUrl={activeTab.url}
          pageTitle={activeTab.title || activeTab.url}
          consoleEntries={consoleEntries}
          onClose={() => setShowCaptureIssue(false)}
        />
      )}

      {/* Screenshot Annotation Overlay */}
      {showAnnotation && annotationScreenshot && (
        <ScreenshotAnnotation
          imageDataUrl={annotationScreenshot}
          onDone={handleAnnotationDone}
          onCancel={handleAnnotationCancel}
        />
      )}
    </div>
  )
}
