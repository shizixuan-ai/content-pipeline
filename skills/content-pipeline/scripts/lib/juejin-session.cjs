#!/usr/bin/env node
/**
 * juejin-session.cjs — Playwright-based juejin session management
 *
 * Depends on playwright-core (from @openclaw-cn/toutiao-ops's dependencies).
 *
 * Usage:
 *   node scripts/lib/juejin-session.cjs login           # Headed QR scan
 *   node scripts/lib/juejin-session.cjs get-cookies     # Headless cookie extraction
 *   node scripts/lib/juejin-session.cjs validate <cookie>  # Validate cookie
 *
 * User data dir: ~/.juejin/browser-data/
 */

const path = require('path');
const { realpathSync, existsSync, mkdirSync } = require('fs');
const { execSync } = require('child_process');
const { homedir } = require('os');
const https = require('https');

const USER_DATA_DIR = path.join(homedir(), '.juejin', 'browser-data');
const AUTH_URL = 'https://api.juejin.cn/user_api/v1/user/get';

// ─── Resolve playwright-core ──────────────────────────────────────
function resolvePlaywright() {
  try {
    const bin = execSync('command -v toutiao-ops', { encoding: 'utf8' }).trim();
    const realBin = realpathSync(bin);
    const pwPath = path.join(path.dirname(realBin), 'node_modules', 'playwright-core');
    if (existsSync(pwPath)) return pwPath;
  } catch {}
  try { return require.resolve('playwright-core'); } catch {}
  throw new Error('未找到 playwright-core');
}

const PW_PATH = resolvePlaywright();
const { chromium } = require(PW_PATH);

// ─── API validation (Node.js native https) ────────────────────────
function validateCookie(cookieStr) {
  return new Promise((resolve) => {
    const url = new URL(AUTH_URL);
    const opts = {
      hostname: url.hostname,
      path: url.pathname,
      method: 'GET',
      headers: {
        'Cookie': cookieStr,
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
        'Referer': 'https://juejin.cn/',
      },
      timeout: 10000,
    };
    const req = https.get(opts, (res) => {
      let body = '';
      res.on('data', (c) => body += c);
      res.on('end', () => {
        try {
          const d = JSON.parse(body);
          if (d.err_no === 0) resolve({ valid: true, user_name: d.data.user_name, user_id: d.data.user_id });
          else resolve({ valid: false, err: d.err_msg || 'unknown' });
        } catch (e) { resolve({ valid: false, err: 'parse: ' + e.message }); }
      });
    });
    req.on('error', (e) => resolve({ valid: false, err: e.message }));
    req.on('timeout', () => { req.destroy(); resolve({ valid: false, err: 'timeout' }); });
  });
}

// ─── Mode: login ──────────────────────────────────────────────────
async function modeLogin() {
  if (!existsSync(USER_DATA_DIR)) mkdirSync(USER_DATA_DIR, { recursive: true });

  const context = await chromium.launchPersistentContext(USER_DATA_DIR, {
    headless: false,
    args: ['--disable-blink-features=AutomationControlled'],
  });
  const page = context.pages()[0] || await context.newPage();
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.goto('https://juejin.cn', { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(3000);

  // Check if already logged in
  const hasAvatar = await page.$('.user-info-nav .avatar, [class*="user-info"] img, [class*="avatar"]');
  if (hasAvatar) {
    const cookies = await context.cookies();
    const str = cookies.map(c => `${c.name}=${c.value}`).join('; ');
    const info = await validateCookie(str);
    if (info.valid) {
      console.error('已登录:', info.user_name);
      await context.close();
      return;
    }
  }

  // Click login button to trigger QR
  try {
    const btn = await page.waitForSelector(
      '.login-button, .login-btn, button:has-text("登录"), a:has-text("登录")',
      { timeout: 5000 }
    );
    await btn.click();
  } catch {}

  console.error('请在浏览器窗口中扫码登录掘金...');
  const TIMEOUT = 120;
  for (let i = 0; i < TIMEOUT; i++) {
    await page.waitForTimeout(1000);
    try {
      const avatar = await page.$('.user-info-nav .avatar, [class*="user-info"] img, [class*="avatar"]');
      if (avatar) {
        const cookies = await context.cookies();
        const str = cookies.map(c => `${c.name}=${c.value}`).join('; ');
        const info = await validateCookie(str);
        if (info.valid) {
          console.error(`登录成功 (${i + 1}s) 用户:`, info.user_name);
          await context.close();
          return;
        }
      }
    } catch {}
    if ((i + 1) % 15 === 0) console.error(`等待扫码... (${i + 1}s)`);
  }
  console.error('登录超时');
  await context.close();
  process.exit(2);
}

// ─── Mode: get-cookies ────────────────────────────────────────────
async function modeGetCookies() {
  if (!existsSync(USER_DATA_DIR)) {
    console.error('未找到 session，请先运行: node scripts/lib/juejin-session.cjs login');
    process.exit(1);
  }

  const context = await chromium.launchPersistentContext(USER_DATA_DIR, {
    headless: true,
    args: ['--disable-blink-features=AutomationControlled'],
  });
  const page = context.pages()[0] || await context.newPage();
  await page.goto('https://juejin.cn', { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(2000);

  const cookies = await context.cookies();
  const cookieStr = cookies.map(c => `${c.name}=${c.value}`).join('; ');
  await context.close();

  if (!cookieStr) {
    console.error('未提取到 cookies');
    process.exit(1);
  }

  const info = await validateCookie(cookieStr);
  if (!info.valid) {
    console.error('Cookie 已过期，请重新运行 login');
    process.exit(1);
  }

  console.log(cookieStr);
}

// ─── Mode: validate ───────────────────────────────────────────────
async function modeValidate() {
  const cookieStr = process.argv[3];
  if (!cookieStr) { console.error('Usage: validate <cookie>'); process.exit(1); }
  const info = await validateCookie(cookieStr);
  console.log(JSON.stringify(info));
}

// ─── Main ─────────────────────────────────────────────────────────
async function main() {
  const mode = process.argv[2] || 'get-cookies';
  switch (mode) {
    case 'login': await modeLogin(); break;
    case 'get-cookies': await modeGetCookies(); break;
    case 'validate': await modeValidate(); break;
    default: console.error('Usage: login|get-cookies|validate'); process.exit(1);
  }
}

main().catch(e => { console.error(e.message || e); process.exit(1); });
