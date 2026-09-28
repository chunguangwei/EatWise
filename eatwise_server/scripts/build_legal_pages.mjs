#!/usr/bin/env node
/**
 * 法务静态页生成器（App Store Connect 要求公网可访问的隐私政策/用户协议 URL）：
 * 把 docs/compliance/ 两份中英全文 md 转成 public/*.html（单页中英双文，锚点切换）。
 *
 * 文本三处同步：App 内 i18n legal.* ↔ docs/compliance/*.md ↔ 本脚本产物 public/*.html。
 * 改动任一处后重跑：node scripts/build_legal_pages.mjs
 */
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const repoRoot = join(root, '..');

const PAGES = [
  {
    md: join(repoRoot, 'docs/compliance/隐私政策-海外版-v2.0.md'),
    out: join(root, 'public/privacy.html'),
    titleZh: '隐私政策',
    titleEn: 'Privacy Policy',
    description: 'EatWise 隐私政策 / Privacy Policy',
  },
  {
    md: join(repoRoot, 'docs/compliance/用户协议-海外版-v2.0.md'),
    out: join(root, 'public/terms.html'),
    titleZh: '用户协议',
    titleEn: 'Terms of Use',
    description: 'EatWise 用户协议 / Terms of Use',
  },
];

const CONTACT = 'chunguangwee@gmail.com';

function escapeHtml(s) {
  return s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}

function inline(s) {
  return escapeHtml(s).replaceAll(
    CONTACT,
    `<a href="mailto:${CONTACT}">${CONTACT}</a>`,
  );
}

/** md → HTML 片段：# 标题 / - 列表 / 其余按行成段；开发同步注（> 引用行）不上公网页。 */
function sectionToHtml(lines) {
  const out = [];
  let list = [];
  const flushList = () => {
    if (list.length > 0) {
      out.push(`<ul>${list.map((i) => `<li>${i}</li>`).join('')}</ul>`);
      list = [];
    }
  };
  for (const raw of lines) {
    const line = raw.trim();
    if (line === '' || line === '---') {
      flushList();
      continue;
    }
    if (line.startsWith('>')) continue; // 同步注（i18n 同源说明），非公网内容
    if (line.startsWith('# ')) {
      flushList();
      out.push(`<h1>${inline(line.slice(2))}</h1>`);
      continue;
    }
    if (line.startsWith('- ')) {
      list.push(inline(line.slice(2)));
      continue;
    }
    flushList();
    out.push(`<p>${inline(line)}</p>`);
  }
  flushList();
  return out.join('\n');
}

/** 中英全文 md：zh 半部 + `---` + en 半部（第二个 `# ` 标题为英文起始）。 */
function splitBilingual(md) {
  const lines = md.split('\n');
  const h1Idx = lines
    .map((l, i) => (l.startsWith('# ') ? i : -1))
    .filter((i) => i >= 0);
  if (h1Idx.length !== 2) {
    throw new Error(`expected exactly 2 H1 headings (zh/en), got ${h1Idx.length}`);
  }
  return { zh: lines.slice(0, h1Idx[1]), en: lines.slice(h1Idx[1]) };
}

function renderPage(page, zhHtml, enHtml) {
  return `<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="description" content="${escapeHtml(page.description)}">
<title>EatWise ${escapeHtml(page.titleZh)} · ${escapeHtml(page.titleEn)}</title>
<style>
  :root { color-scheme: light; }
  body {
    margin: 0; padding: 24px 16px 64px;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC",
      "Hiragino Sans GB", "Microsoft YaHei", Roboto, sans-serif;
    line-height: 1.75; color: #1f2933; background: #fafafa;
  }
  main { max-width: 760px; margin: 0 auto; }
  nav.lang { margin-bottom: 24px; font-size: 15px; }
  nav.lang a { color: #0d7a5f; text-decoration: none; margin-right: 16px; }
  h1 { font-size: 24px; line-height: 1.35; margin: 0 0 16px; }
  section { background: #fff; border-radius: 12px; padding: 24px 20px; margin-bottom: 24px; }
  hr { border: none; border-top: 1px solid #e4e7eb; margin: 32px 0; }
  a { color: #0d7a5f; }
  footer { font-size: 14px; color: #6b7280; }
</style>
</head>
<body>
<main>
  <nav class="lang">
    <a href="#zh">中文</a>
    <a href="#en">English</a>
  </nav>
  <section id="zh" lang="zh-CN">
${zhHtml}
  </section>
  <hr>
  <section id="en" lang="en">
${enHtml}
  </section>
  <footer>
    <p>EatWise · <a href="mailto:${CONTACT}">${CONTACT}</a></p>
  </footer>
</main>
</body>
</html>
`;
}

mkdirSync(join(root, 'public'), { recursive: true });
for (const page of PAGES) {
  const { zh, en } = splitBilingual(readFileSync(page.md, 'utf8'));
  const html = renderPage(page, sectionToHtml(zh), sectionToHtml(en));
  writeFileSync(page.out, html);
  console.log(`built ${page.out} (${html.length} bytes)`);
}
