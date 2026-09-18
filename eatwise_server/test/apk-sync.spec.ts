import {
  APK_FILE_NAME,
  decideSync,
  selectApkAsset,
  staleApkFiles,
} from '../scripts/apk-sync-core.js';

describe('apk-sync 核心判定（选资产 / 幂等比对 / 历史清理）', () => {
  it('selectApkAsset：挑第一个 .apk 资产，无视其它类型', () => {
    const assets = [
      { name: 'checksums.txt', url: 'u1' },
      { name: 'app-release.apk', url: 'u2' },
      { name: 'app2.apk', url: 'u3' },
    ];
    expect(selectApkAsset(assets)?.name).toBe('app-release.apk');
  });

  it('selectApkAsset：无 APK / 非数组 → null', () => {
    expect(selectApkAsset([{ name: 'app-release.aab' }])).toBeNull();
    expect(selectApkAsset([])).toBeNull();
    expect(selectApkAsset(undefined)).toBeNull();
  });

  it('decideSync：tag 一致且 APK 在场 → 跳过（幂等）', () => {
    expect(decideSync({ latestTag: 'v1.8.9', recordedTag: 'v1.8.9', apkExists: true })).toEqual({
      action: 'skip',
      reason: 'up-to-date',
    });
  });

  it('decideSync：tag 变了 → 下载', () => {
    expect(decideSync({ latestTag: 'v1.8.9', recordedTag: 'v1.8.8', apkExists: true }).action).toBe(
      'download',
    );
  });

  it('decideSync：tag 一致但 APK 缺失 → 补下载', () => {
    expect(decideSync({ latestTag: 'v1.8.9', recordedTag: 'v1.8.9', apkExists: false })).toEqual({
      action: 'download',
      reason: 'apk-missing',
    });
  });

  it('decideSync：无 latestTag → 跳过', () => {
    expect(decideSync({ latestTag: '', recordedTag: 'v1', apkExists: false }).action).toBe('skip');
  });

  it('staleApkFiles：清理其它 APK 与 tmp 残留，保留固定名', () => {
    const files = [
      APK_FILE_NAME,
      'eatwise-v1.8.8.apk',
      'eatwise-latest.apk.tmp',
      '.version',
      'notes.txt',
    ];
    expect(staleApkFiles(files)).toEqual(['eatwise-v1.8.8.apk', 'eatwise-latest.apk.tmp']);
  });
});
