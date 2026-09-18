'use strict';

/**
 * apk-sync 核心纯函数（CommonJS，供 scripts/apk-sync.mjs 与 jest 单测共用；
 * .mjs 为 ESM，jest 29 的 CJS 管线无法直接 import，故逻辑落在此文件）。
 */

/** APK 固定文件名（天然只保留最新包）与版本记录文件。 */
const APK_FILE_NAME = 'eatwise-latest.apk';
const VERSION_FILE_NAME = '.version';

/** 从 release assets 中挑 APK 资产（第一个以 .apk 结尾的），没有返回 null。 */
function selectApkAsset(assets) {
  if (!Array.isArray(assets)) return null;
  return assets.find((a) => a && typeof a.name === 'string' && a.name.endsWith('.apk')) ?? null;
}

/**
 * 是否需要下载：记录 tag 与最新 tag 一致且 APK 文件在场 → 跳过（幂等）；
 * tag 一致但文件缺失 → 补下载；tag 变了 → 下载。
 */
function decideSync({ latestTag, recordedTag, apkExists }) {
  if (!latestTag) return { action: 'skip', reason: 'no-latest-tag' };
  if (recordedTag === latestTag && apkExists) {
    return { action: 'skip', reason: 'up-to-date' };
  }
  return { action: 'download', reason: recordedTag === latestTag ? 'apk-missing' : 'tag-changed' };
}

/**
 * 下载前需要清理的历史文件：其它 .apk（如 eatwise-v*.apk）与 .apk.tmp 残留；
 * 固定名 eatwise-latest.apk 与 .version 不在其列。
 */
function staleApkFiles(fileNames) {
  return fileNames.filter(
    (name) => (name.endsWith('.apk') && name !== APK_FILE_NAME) || name.endsWith('.apk.tmp'),
  );
}

module.exports = {
  APK_FILE_NAME,
  VERSION_FILE_NAME,
  selectApkAsset,
  decideSync,
  staleApkFiles,
};
