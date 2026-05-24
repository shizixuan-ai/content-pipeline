#!/usr/bin/env node
/**
 * zhihu-session.cjs — 知乎 session & publish
 *
 * Key insight: Zhihu anti-bot flags Playwright-launched browsers.
 * Solution: launch Chrome directly via child_process, connect via CDP.
 *
 * Usage:
 *   node scripts/lib/zhihu-session.cjs login              # QR scan login
 *   node scripts/lib/zhihu-session.cjs publish <title> <content_file>
 *
 * Profile dir: ~/.zhihu/browser-data/
 */

const path = require('path');
const { existsSync, mkdirSync, readFileSync, rmSync } = require('fs');
const { spawn } = require('child_process');
const http = require('http');
const { homedir } = require('os');

const USER_DATA_DIR = path.join(homedir(), '.zhihu', 'browser-data');
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const CDP_PORT = 9223;
const ZHIHU_EDITOR = 'https://zhuanlan.zhihu.com/write';

// ─── Resolve playwright-core ──────────────────────────────────────
function loadPlaywright() {
  const { execSync } = require('child_process');
  const { realpathSync } = require('fs');
  // Find playwright-core in the toutiao-ops dependency tree
  try {
    const bin = execSync('command -v toutiao-ops', { encoding: 'utf8' }).trim();
    const realBin = realpathSync(bin);
    // Walk up from the real bin to find node_modules/playwright-core
    let dir = path.dirname(realBin);
    for (let i = 0; i < 5; i++) {
      const candidate = path.join(dir, 'node_modules', 'playwright-core');
      if (existsSync(path.join(candidate, 'package.json'))) return require(candidate);
      const parent = path.dirname(dir);
      if (parent === dir) break;
      dir = parent;
    }
  } catch {}
  // Fallback
  try { return require('playwright-core'); } catch {}
  throw new Error('未找到 playwright-core。运行: npm install -g @openclaw-cn/toutiao-ops');
}

const { chromium } = loadPlaywright();

// ─── Start real Chrome (not via Playwright) ──────────────────────
function startChrome() {
  return new Promise((resolve, reject) => {
    if (!existsSync(USER_DATA_DIR)) mkdirSync(USER_DATA_DIR, { recursive: true });

    // Kill existing Chrome on our port
    try { require('child_process').execSync(`lsof -ti:${CDP_PORT} | xargs kill -9 2>/dev/null`); } catch {}

    const proc = spawn(CHROME, [
      `--user-data-dir=${USER_DATA_DIR}`,
      `--remote-debugging-port=${CDP_PORT}`,
      '--no-first-run',
      '--no-default-browser-check',
      '--window-size=1280,900',
    ], { stdio: ['ignore', 'pipe', 'pipe'], env: { ...process.env } });

    let resolved = false;
    const timeout = setTimeout(() => {
      if (!resolved) { resolved = true; reject(new Error('Chrome 启动超时')); }
    }, 15000);

    // Watch for DevTools listening message
    const checkOutput = (data) => {
      if (resolved) return;
      if (data.toString().includes('DevTools listening')) {
        resolved = true;
        clearTimeout(timeout);
        resolve(proc);
      }
    };
    proc.stderr.on('data', checkOutput);
    proc.stdout.on('data', checkOutput);
    proc.on('error', (e) => { if (!resolved) { resolved = true; clearTimeout(timeout); reject(e); } });
  });
}

// ─── Get CDP WebSocket URL from Chrome ──────────────────────────
async function getWSURL(retries = 20) {
  for (let i = 0; i < retries; i++) {
    try {
      const json = await httpGet(`http://127.0.0.1:${CDP_PORT}/json/version`);
      const info = JSON.parse(json);
      if (info.webSocketDebuggerUrl) return info.webSocketDebuggerUrl;
    } catch {}
    await sleep(500);
  }
  throw new Error('CDP 连接失败');
}

function httpGet(url) {
  return new Promise((resolve, reject) => {
    http.get(url, (res) => {
      let d = '';
      res.on('data', c => d += c);
      res.on('end', () => resolve(d));
    }).on('error', reject);
  });
}

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

// ─── Login mode ──────────────────────────────────────────────────
async function modeLogin() {
  console.error('启动 Chrome（请扫码登录知乎）...');
  const proc = await startChrome();

  const wsURL = await getWSURL();
  console.error('CDP 已就绪，请在打开的浏览器中扫码登录');

  const browser = await chromium.connectOverCDP(wsURL);
  const page = browser.contexts()[0]?.pages()[0] || await browser.newPage();

  await page.goto('https://www.zhihu.com/signin', { waitUntil: 'networkidle', timeout: 30000 });
  await page.waitForTimeout(3000);

  if (!page.url().includes('/signin')) {
    console.error('已登录');
    await browser.close();
    proc.kill('SIGKILL');
    return;
  }

  // Poll for login (URL redirect away from /signin)
  for (let i = 0; i < 180; i++) {
    await sleep(1000);
    if (!page.url().includes('/signin')) {
      console.error(`登录成功 (${i + 1}s)`);
      await browser.close();
      proc.kill('SIGKILL');
      return;
    }
    if ((i + 1) % 15 === 0) console.error(`等待扫码... (${i + 1}s)`);
  }
  console.error('登录超时');
  process.exit(2);
}

// ─── Publish mode ────────────────────────────────────────────────
async function modePublish() {
  const title = process.argv[3];
  const contentFile = process.argv[4];

  if (!title || !contentFile) {
    console.error('Usage: publish <title> <content_file>');
    process.exit(1);
  }

  let content;
  try { content = readFileSync(contentFile, 'utf-8'); }
  catch (e) { console.error('读取内容文件失败:', e.message); process.exit(1); }

  console.error('启动 Chrome...');
  const proc = await startChrome();
  const wsURL = await getWSURL();

  console.error('连接 CDP...');
  const browser = await chromium.connectOverCDP(wsURL);
  const defaultContext = browser.contexts()[0];
  const page = defaultContext?.pages()[0] || await browser.newPage();

  try {
    // Navigate to editor
    console.error('打开知乎编辑器...');
    await page.goto(ZHIHU_EDITOR, { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForTimeout(3000);

    const url = page.url();
    if (url.includes('signin')) { console.error('未登录'); process.exit(2); }
    if (url.includes('unhuman')) { console.error('反爬验证，请重新运行 login'); process.exit(2); }
    if (!url.includes('/write')) {
      console.error('意外 URL:', url);
      process.exit(2);
    }
    console.error('✅ 编辑器加载成功');

    // Wait for editor DOM (textarea + contenteditable) to be rendered
    let editorReady = false;
    for (let i = 0; i < 15; i++) {
      const ready = await page.evaluate(() => {
        return !!(document.querySelector('textarea') && document.querySelector('[contenteditable="true"]'));
      });
      if (ready) { editorReady = true; break; }
      await page.waitForTimeout(1000);
    }
    if (!editorReady) {
      console.error('编辑器 DOM 未渲染');
      process.exit(2);
    }
    console.error('编辑器 DOM 就绪');

    // Fill title
    console.error('填写标题...');
    await page.evaluate((t) => {
      // Try textarea first (most common zhihu editor pattern)
      const ta = document.querySelector('textarea[placeholder*="标题"], textarea');
      if (ta) {
        const set = Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value').set;
        set.call(ta, t);
        ta.dispatchEvent(new Event('input', { bubbles: true }));
        return;
      }
      // Fallback: input elements with title-related placeholder
      const input = document.querySelector('input[placeholder*="标题"]');
      if (input) {
        const set = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
        set.call(input, t);
        input.dispatchEvent(new Event('input', { bubbles: true }));
        return;
      }
    }, title);
    await page.waitForTimeout(1000);

    // Fill content
    console.error('填写内容...');
    // Use keyboard.type() to trigger proper React/Draft.js change detection
    await page.click('[contenteditable="true"]');
    await page.waitForTimeout(300);
    await page.keyboard.type(content, { delay: 0 });
    console.error(`内容已输入 (${content.length} 字符)`);
    await page.waitForTimeout(3000);

    // Wait for publish button to become enabled (after content is filled)
    console.error('等待发布按钮可用...');
    let publishClicked = false;
    for (let i = 0; i < 20; i++) {
      await page.waitForTimeout(500);
      const btnState = await page.evaluate(() => {
        // 找蓝色 primary 发布按钮（非禁用）
        const btns = document.querySelectorAll('button.Button--primary.Button--blue');
        for (const b of btns) {
          if (!b.disabled && (b.textContent || '').trim() === '发布') {
            b.click();
            return 'clicked';
          }
        }
        // 也检查含"发布"的按钮
        const allBtns = document.querySelectorAll('button');
        for (const b of allBtns) {
          if (!b.disabled && b.offsetParent !== null && (b.textContent || '').trim() === '发布') {
            b.click();
            return 'clicked';
          }
        }
        return 'not_ready';
      });
      if (btnState === 'clicked') {
        publishClicked = true;
        console.error('发布按钮已点击');
        break;
      }
    }

    if (!publishClicked) {
      console.error('发布按钮始终不可用');
      process.exit(3);
    }

    // Wait for publish settings dialog or redirect
    console.error('等待发布完成...');
    await page.waitForTimeout(3000);

    // Check for confirmation dialog (发布设置弹窗中的"发布"按钮)
    try {
      const confirmBtn = await page.waitForSelector('button:has-text("发布")', { timeout: 5000 });
      if (confirmBtn) {
        const isDisabled = await confirmBtn.evaluate(el => el.disabled);
        if (!isDisabled) {
          await confirmBtn.click();
          console.error('确认发布');
          await page.waitForTimeout(5000);
        }
      }
    } catch {}

    const finalUrl = page.url();
    const match = finalUrl.match(/zhuanlan\.zhihu\.com\/p\/(\d+)/);
    if (match) {
      const articleUrl = `https://zhuanlan.zhihu.com/p/${match[1]}`;
      console.error('发布成功:', articleUrl);
      console.log(articleUrl);
    } else {
      console.error('发布完成，URL:', finalUrl);
      console.log(finalUrl);
    }
  } finally {
    await browser.close().catch(() => {});
    proc.kill('SIGKILL');
  }
}

// ─── Get cookies mode (for auth-zhihu.sh) ──────────────────────
async function modeGetCookies() {
  console.error('启动 Chrome 验证 session...');
  const proc = await startChrome();
  const wsURL = await getWSURL();

  const browser = await chromium.connectOverCDP(wsURL);
  const defaultContext = browser.contexts()[0];
  const page = defaultContext?.pages()[0] || await browser.newPage();

  try {
    await page.goto('https://www.zhihu.com', { waitUntil: 'domcontentloaded', timeout: 15000 });
    await page.waitForTimeout(2000);

    const url = page.url();
    if (url.includes('signin')) {
      console.error('未登录');
      await browser.close();
      proc.kill('SIGKILL');
      process.exit(1);
    }

    // Extract cookies for zhihu domains
    const cookies = await defaultContext.cookies();
    const zhihuCookies = cookies.filter(c =>
      c.domain.includes('zhihu.com') || c.domain.includes('zhuanlan.zhihu.com')
    );

    if (zhihuCookies.length === 0) {
      console.error('未找到知乎 Cookie');
      await browser.close();
      proc.kill('SIGKILL');
      process.exit(1);
    }

    // Format as semicolon-separated cookie string (Netscape style)
    const cookieStr = zhihuCookies.map(c => `${c.name}=${c.value}`).join('; ');
    console.error(`Session 有效 (${zhihuCookies.length} cookies)`);
    console.log(cookieStr);
  } finally {
    await browser.close().catch(() => {});
    proc.kill('SIGKILL');
  }
}

// ─── Main ─────────────────────────────────────────────────────────
async function main() {
  if (!existsSync(CHROME)) {
    console.error('未找到 Google Chrome:', CHROME);
    process.exit(1);
  }

  const mode = process.argv[2] || 'publish';
  switch (mode) {
    case 'login': await modeLogin(); break;
    case 'publish': await modePublish(); break;
    case 'get-cookies': await modeGetCookies(); break;
    default: console.error('Usage: login|publish|get-cookies'); process.exit(1);
  }
}

main().catch(e => { console.error(e.message || e); process.exit(1); });
