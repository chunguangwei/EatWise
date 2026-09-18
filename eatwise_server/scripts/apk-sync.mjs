#!/usr/bin/env node
// APK 自托管同步：从 GitHub 最新 release 拉 APK 到 downloads/，固定名
// eatwise-latest.apk（只保留最新一个包），.version 记录已同步的 tag。
// 任何失败只告警、退出码恒 0——不阻断 compose 启动链，维持现状文件。
// env：GITHUB_RELEASE_TOKEN（私有仓必填，缺失则跳过）、
// GITHUB_REPOSITORY（缺省 chunguangwei/EatWise）、
// DOWNLOADS_DIR（缺省 /downloads，即 compose 挂载点）。

import { createRequire } from 'node:module';
import { createWriteStream, promises as fs } from 'node:fs';
import path from 'node:path';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';

const require = createRequire(import.meta.url);
const { APK_FILE_NAME, VERSION_FILE_NAME, selectApkAsset, decideSync, staleApkFiles } =
  require('./apk-sync-core.js');

// 核心判定逻辑同时在 scripts/apk-sync-core.js（CJS）导出供 jest 单测。
export { selectApkAsset, decideSync, staleApkFiles };

const repo = process.env.GITHUB_REPOSITORY || 'chunguangwei/EatWise';
const token = process.env.GITHUB_RELEASE_TOKEN || '';
const downloadsDir = process.env.DOWNLOADS_DIR || '/downloads';

const log = (msg) => console.log(`[apk-sync] ${msg}`);
const warn = (msg) => console.warn(`[apk-sync] WARN ${msg}`);

function headers(extra = {}) {
  const h = {
    Accept: 'application/vnd.github+json',
    'User-Agent': 'eatwise-apk-sync',
    'X-GitHub-Api-Version': '2022-11-28',
    ...extra,
  };
  if (token) h.Authorization = `Bearer ${token}`;
  return h;
}

const exists = (p) => fs.stat(p).then(() => true).catch(() => false);

async function main() {
  await fs.mkdir(downloadsDir, { recursive: true });

  if (!token) {
    warn('未配置 GITHUB_RELEASE_TOKEN，跳过同步（维持现状文件）');
    return;
  }

  const res = await fetch(`https://api.github.com/repos/${repo}/releases/latest`, {
    headers: headers(),
  });
  if (!res.ok) {
    warn(`查询最新 release 失败：GitHub API ${res.status}（维持现状文件）`);
    return;
  }
  const release = await res.json();

  const asset = selectApkAsset(release.assets);
  if (!asset) {
    warn(`release ${release.tag_name} 无 APK 资产（维持现状文件）`);
    return;
  }

  const apkPath = path.join(downloadsDir, APK_FILE_NAME);
  const versionPath = path.join(downloadsDir, VERSION_FILE_NAME);
  const recordedTag = await fs
    .readFile(versionPath, 'utf8')
    .then((s) => s.trim())
    .catch(() => '');
  const decision = decideSync({
    latestTag: release.tag_name,
    recordedTag,
    apkExists: await exists(apkPath),
  });
  if (decision.action === 'skip') {
    log(`已是最新 ${release.tag_name}（${decision.reason}），跳过下载`);
    return;
  }

  // 清掉历史 eatwise-v*.apk 与 .tmp 残留，只留最新包。
  for (const name of staleApkFiles(await fs.readdir(downloadsDir))) {
    await fs.rm(path.join(downloadsDir, name), { force: true });
    log(`清理历史文件 ${name}`);
  }

  log(`下载 ${release.tag_name}（资产 ${asset.name}）→ ${APK_FILE_NAME} ...`);
  const tmpPath = `${apkPath}.tmp`;
  const dl = await fetch(asset.url, {
    headers: headers({ Accept: 'application/octet-stream' }),
  });
  if (!dl.ok || !dl.body) {
    warn(`APK 下载失败：GitHub API ${dl.status}（维持现状文件）`);
    return;
  }
  await pipeline(Readable.fromWeb(dl.body), createWriteStream(tmpPath));

  const { size } = await fs.stat(tmpPath);
  if (size === 0) {
    await fs.rm(tmpPath, { force: true });
    warn('下载结果为空文件，已丢弃（维持现状文件）');
    return;
  }
  // 原子替换：caddy 任何时候读到的都是完整文件。
  await fs.rename(tmpPath, apkPath);
  await fs.writeFile(versionPath, `${release.tag_name}\n`);
  log(`完成 ${release.tag_name}（${(size / 1024 / 1024).toFixed(1)}MB）→ ${apkPath}`);
}

main().catch((err) => {
  warn(`同步异常：${err?.stack ?? err}（维持现状文件）`);
  // 退出码恒 0：不阻断 compose 启动链。
});
