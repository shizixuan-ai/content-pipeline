#!/usr/bin/env node
/**
 * jianshu-session.cjs — Playwright-based jianshu session management
 *
 * Usage:
 *   node scripts/lib/jianshu-session.cjs login           # Headed login
 *   node scripts/lib/jianshu-session.cjs get-cookies     # Headless cookie extraction
 *
 * User data dir: ~/.jianshu/browser-data/
 */

const path = require('path');
const { existsSync, mkdirSync } = require('fs');
const { execSync } = require('child_process');
const { realpathSync } = require('fs');
const { homedir } = require('os');

const USER_DATA_DIR = path.join(homedir(), '.jianshu', 'browser-data');

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

async function validateCookie(page) {
  try {
    const resp = await page.goto('https://www.jianshu.com/author/notebooks', { waitUntil: 'domcontentloaded', timeout: 15000 });
    // 检查是否被重定向到登录页
    if (resp.url().includes('sign_in')) return { valid: false, err: 'redirected to login' };
    const body = await page.evaluate(() => document.body.textContent.trim());
    const data = JSON.parse(body);
    if (Array.isArray(data)) return { valid: true };
    return { valid: false, err: `not an array: ${JSON.stringify(data).slice(0, 200)}` };
  } catch (e) {
    return { valid: false, err: e.message };
  }
}

async function modeLogin() {
  if (!existsSync(USER_DATA_DIR)) mkdirSync(USER_DATA_DIR, { recursive: true });

  const context = await chromium.launchPersistentContext(USER_DATA_DIR, {
    headless: false,
    args: ['--disable-blink-features=AutomationControlled'],
  });
  const page = context.pages()[0] || await context.newPage();
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.goto('https://www.jianshu.com/sign_in', { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(3000);

  const LOGIN_PAGE = 'jianshu.com/sign_in';
  console.error('请在浏览器中登录简书...');
  const TIMEOUT = 180;
  for (let i = 0; i < TIMEOUT; i++) {
    await page.waitForTimeout(1000);
    const currentUrl = page.url();
    if (!currentUrl.includes(LOGIN_PAGE)) {
      // 如果在 /sessions 中间页，导航到首页让 session 真正建立
      if (currentUrl.includes('/sessions')) {
        console.error(`检测到中间页，导航到首页... (${i + 1}s)`);
        await page.goto('https://www.jianshu.com', { waitUntil: 'domcontentloaded', timeout: 15000 }).catch(() => {});
        await page.waitForTimeout(2000);
      }
      const info = await validateCookie(page);
      if (info.valid) {
        console.error(`登录成功 (${i + 1}s)`);
        await context.close();
        return;
      }
    }
    if ((i + 1) % 15 === 0) console.error(`等待登录... (${i + 1}s)`);
  }
  console.error('登录超时');
  await context.close();
  process.exit(2);
}

async function modeGetCookies() {
  if (!existsSync(USER_DATA_DIR)) {
    console.error('未找到 session，请先运行: node scripts/lib/jianshu-session.cjs login');
    process.exit(1);
  }

  const context = await chromium.launchPersistentContext(USER_DATA_DIR, {
    headless: true,
    args: ['--disable-blink-features=AutomationControlled'],
  });
  const page = context.pages()[0] || await context.newPage();
  await page.goto('https://www.jianshu.com', { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(2000);

  const cookies = await context.cookies();
  const cookieStr = cookies.map(c => `${c.name}=${c.value}`).join('; ');

  if (!cookieStr) {
    console.error('未提取到 cookies');
    await context.close();
    process.exit(1);
  }

  const info = await validateCookie(page);
  await context.close();

  if (!info.valid) {
    console.error('Cookie 已过期，请重新运行 login');
    process.exit(1);
  }

  console.log(cookieStr);
}

async function main() {
  const mode = process.argv[2] || 'get-cookies';
  switch (mode) {
    case 'login': await modeLogin(); break;
    case 'get-cookies': await modeGetCookies(); break;
    default: console.error('Usage: login|get-cookies'); process.exit(1);
  }
}

main().catch(e => { console.error(e.message || e); process.exit(1); });
