#!/usr/bin/env node
/**
 * csdn-session.cjs — Playwright-based CSDN session management
 *
 * Usage:
 *   node scripts/lib/csdn-session.cjs login           # Headed login
 *   node scripts/lib/csdn-session.cjs get-cookies     # Headless cookie extraction
 *   node scripts/lib/csdn-session.cjs publish <title> <content_file> [tags]
 *
 * User data dir: ~/.csdn/browser-data/
 */

const path = require('path');
const { existsSync, mkdirSync } = require('fs');
const { execSync } = require('child_process');
const { realpathSync } = require('fs');
const { homedir } = require('os');
const https = require('https');

const USER_DATA_DIR = path.join(homedir(), '.csdn', 'browser-data');
const AUTH_URL = 'https://bizapi.csdn.net/blog-console-api/v3/editor/getUserInfo';

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

async function checkRedirect(page) {
  await page.goto('https://passport.csdn.net/account/login', { waitUntil: 'domcontentloaded', timeout: 15000 });
  await page.waitForTimeout(2000);
  return { valid: !page.url().includes('login') };
}

async function modeLogin() {
  if (!existsSync(USER_DATA_DIR)) mkdirSync(USER_DATA_DIR, { recursive: true });

  const context = await chromium.launchPersistentContext(USER_DATA_DIR, {
    headless: false,
    args: ['--disable-blink-features=AutomationControlled'],
  });
  const page = context.pages()[0] || await context.newPage();
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.goto('https://passport.csdn.net/login', { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(3000);

  const LOGIN_PAGE = 'passport.csdn.net/login';
  console.error('请在浏览器中登录 CSDN...');
  const TIMEOUT = 180;
  for (let i = 0; i < TIMEOUT; i++) {
    await page.waitForTimeout(1000);
    if (!page.url().includes(LOGIN_PAGE)) {
      const info = await checkRedirect(page);
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

async function selectTag(page, tagName) {
  const addTagBtn = await page.$('button.tag__btn-tag');
  if (!addTagBtn) { console.error('未找到添加标签按钮'); return false; }
  await addTagBtn.click();
  await page.waitForTimeout(1000);

  // 用搜索框搜标签
  const searchInput = await page.$('.mark_selection_box_header input');
  if (searchInput) {
    await searchInput.fill(tagName);
    await page.waitForTimeout(1000);
    // 从建议列表选第一个，或按 Enter 添加自定义标签
    const suggestion = await page.$('.el-autocomplete-suggestion__list li');
    if (suggestion) {
      await suggestion.click();
    } else {
      await page.keyboard.press('Enter');
    }
    await page.waitForTimeout(800);
  } else {
    // fallback: 点分类再点标签
    const cats = await page.$$('ul.mark_add_tag_left li');
    for (const cat of cats) {
      const t = (await cat.textContent()).trim();
      if (t === '后端') { await cat.click(); break; }
    }
    await page.waitForTimeout(800);
    const tagEls = await page.$$('span.el-tag');
    let found = false;
    for (const el of tagEls) {
      const t = (await el.textContent()).trim().toLowerCase();
      if (t === tagName.toLowerCase()) { await el.click(); found = true; break; }
    }
    if (!found && tagEls.length > 0) await tagEls[0].click();
    await page.waitForTimeout(500);
  }

  // 关标签弹窗 — 只点标签弹窗内的关闭按钮，不影响发布对话框
  const popupClose = await page.$('.mark_selection_box_body .modal__close-button');
  if (popupClose) await popupClose.click();
  await page.waitForTimeout(800);
  return true;
}

async function modePublish() {
  const title = process.argv[3];
  const contentFile = process.argv[4];
  const tags = (process.argv[5] || 'golang').split(',').map(t => t.trim());
  if (!title || !contentFile) { console.error('Usage: publish <title> <content_file> [tags]'); process.exit(1); }

  let content;
  try { content = require('fs').readFileSync(contentFile, 'utf-8'); }
  catch (e) { console.error('读取内容文件失败:', e.message); process.exit(1); }

  if (!existsSync(USER_DATA_DIR)) {
    console.error('未找到 session，请先运行 login');
    process.exit(1);
  }

  const context = await chromium.launchPersistentContext(USER_DATA_DIR, {
    headless: false,
    args: ['--disable-blink-features=AutomationControlled'],
  });
  const page = context.pages()[0] || await context.newPage();
  await page.setViewportSize({ width: 1400, height: 900 });

  // 打开 Markdown 编辑器
  console.error('打开 CSDN Markdown 编辑器...');
  await page.goto('https://editor.csdn.net/md/?not_checkout=1', { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(5000);

  if (page.url().includes('login') || page.url().includes('passport')) {
    console.error('未登录'); process.exit(1);
  }
  console.error('编辑器加载成功');

  // 关闭模版选择弹窗
  const modalCloseBtn = await page.$('.modal__close-button');
  if (modalCloseBtn) {
    console.error('关闭模版选择弹窗...');
    await modalCloseBtn.click();
    await page.waitForTimeout(1000);
  }

  // 填写标题（input 默认 display:none，用 native setter 触发 React）
  console.error('填写标题...');
  await page.evaluate((t) => {
    const input = document.querySelector('input.article-bar__title--input');
    if (!input) return;
    input.style.display = '';
    input.removeAttribute('aria-hidden');
    input.focus();
    const ns = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
    ns.call(input, t);
    input.dispatchEvent(new Event('input', { bubbles: true }));
    input.dispatchEvent(new Event('change', { bubbles: true }));
  }, title);
  await page.waitForTimeout(500);

  // 填写正文
  console.error('填写正文...');
  const editorEl = await page.$('.editor__inner.markdown-highlighting');
  if (editorEl) {
    await editorEl.evaluate((el, md) => {
      el.textContent = md;
      el.dispatchEvent(new Event('input', { bubbles: true }));
    }, content);
    console.error('内容已写入 MD 编辑区');
  } else {
    console.error('未找到 MD 编辑区');
  }
  await page.waitForTimeout(1000);

  // 点击发布按钮，打开发布设置对话框
  console.error('打开发布设置...');
  await page.click('button.btn-publish');
  await page.waitForTimeout(2000);

  // 选择标签
  if (tags.length > 0 && tags[0]) {
    console.error(`选择标签: ${tags[0]}...`);
    await selectTag(page, tags[0]);
  }

  // 点击最终发布按钮
  console.error('发布文章...');
  const finalBtn = await page.$('button.btn-b-red.ml16');
  if (finalBtn) {
    await finalBtn.click();
    await page.waitForTimeout(5000);
    const url = page.url();
    if (url.includes('success')) {
      console.error('✅ 发布成功');
    } else {
      const errMsg = await page.evaluate(() => {
        const err = document.querySelector('.el-message--error, .el-alert--error');
        return err ? err.textContent.trim() : '';
      });
      if (errMsg) console.error(`❌ ${errMsg}`);
      else console.error(`⚠️ 发布后 URL: ${url}`);
    }
  } else {
    console.error('未找到发布确认按钮');
  }

  await context.close();
  console.error('浏览器已关闭');
}

async function modeGetCookies() {
  if (!existsSync(USER_DATA_DIR)) {
    console.error('未找到 session，请先运行: node scripts/lib/csdn-session.cjs login');
    process.exit(1);
  }

  const context = await chromium.launchPersistentContext(USER_DATA_DIR, {
    headless: true,
    args: ['--disable-blink-features=AutomationControlled'],
  });
  const page = context.pages()[0] || await context.newPage();
  await page.goto('https://blog.csdn.net', { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(2000);

  const info = await checkRedirect(page);

  const cookies = await context.cookies();
  const cookieStr = cookies.map(c => `${c.name}=${c.value}`).join('; ');
  await context.close();

  if (!cookieStr || !info.valid) {
    console.error('Cookie 已过期，请重新运行 login');
    process.exit(1);
  }

  console.log(cookieStr);
}

async function main() {
  const mode = process.argv[2] || 'get-cookies';
  switch (mode) {
    case 'login': await modeLogin(); break;
    case 'publish': await modePublish(); break;
    case 'get-cookies': await modeGetCookies(); break;
    default: console.error('Usage: login|publish|get-cookies'); process.exit(1);
  }
}

main().catch(e => { console.error(e.message || e); process.exit(1); });
