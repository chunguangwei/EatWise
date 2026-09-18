import { ConfigService } from '@nestjs/config';
import { AppVersionService } from '../src/app-version/app-version.service';
import { compareSemver, parseSemver } from '../src/app-version/semver.util';

describe('semver.util（x.y.z[+build] 解析与比较）', () => {
  it('解析完整版本号与 build 元数据', () => {
    expect(parseSemver('1.2.3+45')).toEqual({
      major: 1,
      minor: 2,
      patch: 3,
      build: '45',
    });
  });

  it('容忍前导 v 与缺省 minor/patch', () => {
    expect(parseSemver('v2.0')).toMatchObject({ major: 2, minor: 0, patch: 0 });
    expect(parseSemver('3')).toMatchObject({ major: 3, minor: 0, patch: 0 });
  });

  it('非法版本号抛 TypeError', () => {
    expect(() => parseSemver('abc')).toThrow(TypeError);
    expect(() => parseSemver('1.2.x')).toThrow(TypeError);
  });

  it.each([
    ['1.0.0', '1.0.0', 0],
    ['1.0.0+1', '1.0.0+2', 0], // build 元数据不参与比较
    ['1.2.3', '1.2.10', -1],
    ['1.10.0', '1.9.9', 1],
    ['2.0.0', '1.9.9', 1],
    ['1.0.0', '1.0.1', -1],
    ['v1.2.3', '1.2.3', 0],
  ])('compareSemver(%s, %s) = %i', (a, b, expected) => {
    expect(compareSemver(a, b)).toBe(expected);
  });
});

describe('AppVersionService（GitHub Releases 代理 + 降级兜底 + 缓存）', () => {
  const releasePayload = {
    tag_name: 'v1.2.0',
    body: '- 新增更新检查',
    published_at: '2026-07-29T00:00:00Z',
    assets: [
      {
        name: 'app-release.apk',
        browser_download_url: 'https://github.com/x/app-release.apk',
      },
    ],
  };

  let fetchMock: jest.Mock;
  const realFetch = global.fetch;

  beforeEach(() => {
    fetchMock = jest.fn();
    global.fetch = fetchMock as unknown as typeof fetch;
  });

  afterEach(() => {
    global.fetch = realFetch;
  });

  const jsonResponse = (status: number, body: unknown) =>
    ({
      ok: status >= 200 && status < 300,
      status,
      json: () => Promise.resolve(body),
    }) as Response;

  it('GitHub 成功：tag 去 v 前缀、APK 附件取 download_url、双语 notes 同填', async () => {
    fetchMock.mockResolvedValue(jsonResponse(200, releasePayload));
    const service = new AppVersionService(new ConfigService());
    const view = await service.getLatest('android');
    expect(view).toEqual({
      latestVersion: '1.2.0',
      minSupportedVersion: '1.0.0',
      releaseNotes: { zh: '- 新增更新检查', en: '- 新增更新检查' },
      apkUrl: 'https://github.com/x/app-release.apk',
      publishedAt: '2026-07-29T00:00:00Z',
      source: 'github',
    });
  });

  it('GitHub 成功且已配 APP_APK_URL：apkUrl 用自托管地址，版本/notes 仍取 GitHub', async () => {
    fetchMock.mockResolvedValue(jsonResponse(200, releasePayload));
    const service = new AppVersionService(
      new ConfigService({ APP_APK_URL: 'https://wcg.polin.tech:8443/downloads/eatwise-v1.2.0.apk' }),
    );
    const view = await service.getLatest('android');
    expect(view.source).toBe('github');
    expect(view.apkUrl).toBe('https://wcg.polin.tech:8443/downloads/eatwise-v1.2.0.apk');
    expect(view.latestVersion).toBe('1.2.0');
    expect(view.releaseNotes.zh).toBe('- 新增更新检查');
    expect(view.publishedAt).toBe('2026-07-29T00:00:00Z');
  });

  it('GitHub 成功但未配 APP_APK_URL：apkUrl 维持 release asset 地址', async () => {
    fetchMock.mockResolvedValue(jsonResponse(200, releasePayload));
    const service = new AppVersionService(new ConfigService());
    const view = await service.getLatest('android');
    expect(view.apkUrl).toBe('https://github.com/x/app-release.apk');
  });

  it('GitHub 成功且 APP_APK_URL 为空串：视为未配，维持 release asset 地址', async () => {
    fetchMock.mockResolvedValue(jsonResponse(200, releasePayload));
    const service = new AppVersionService(new ConfigService({ APP_APK_URL: '' }));
    const view = await service.getLatest('android');
    expect(view.apkUrl).toBe('https://github.com/x/app-release.apk');
  });

  it('携带 GITHUB_RELEASE_TOKEN 时请求带 Authorization 头', async () => {
    fetchMock.mockResolvedValue(jsonResponse(200, releasePayload));
    const service = new AppVersionService(new ConfigService({ GITHUB_RELEASE_TOKEN: 'tok-1' }));
    await service.getLatest('android');
    const headers = fetchMock.mock.calls[0][1].headers as Record<string, string>;
    expect(headers.Authorization).toBe('Bearer tok-1');
  });

  it('iOS 平台不返回 apkUrl（走 App Store）', async () => {
    fetchMock.mockResolvedValue(jsonResponse(200, releasePayload));
    const service = new AppVersionService(new ConfigService());
    const view = await service.getLatest('ios');
    expect(view.apkUrl).toBeNull();
    expect(view.latestVersion).toBe('1.2.0');
  });

  it('GitHub 404（私有仓库匿名）→ 降级 env 静态配置并标注 source=fallback', async () => {
    fetchMock.mockResolvedValue(jsonResponse(404, { message: 'Not Found' }));
    const service = new AppVersionService(
      new ConfigService({
        APP_LATEST_VERSION: '1.1.0',
        APP_APK_URL: 'https://cdn.example.com/app.apk',
        APP_RELEASE_NOTES_ZH: '修复若干问题',
      }),
    );
    const view = await service.getLatest('android');
    expect(view.source).toBe('fallback');
    expect(view.latestVersion).toBe('1.1.0');
    expect(view.apkUrl).toBe('https://cdn.example.com/app.apk');
    expect(view.releaseNotes.zh).toBe('修复若干问题');
    expect(view.releaseNotes.en).toBe('修复若干问题'); // 未配 EN 时回退 ZH
  });

  it('GitHub 网络异常 → 同样降级兜底；minSupportedVersion 走 env 覆盖', async () => {
    fetchMock.mockRejectedValue(new Error('socket hang up'));
    const service = new AppVersionService(
      new ConfigService({ APP_MIN_SUPPORTED_VERSION: '0.9.0' }),
    );
    const view = await service.getLatest('android');
    expect(view.source).toBe('fallback');
    expect(view.minSupportedVersion).toBe('0.9.0');
    // 未配 APP_LATEST_VERSION 时回退 minSupportedVersion
    expect(view.latestVersion).toBe('0.9.0');
  });

  it('缓存 5 分钟内命中：第二次调用不再请求 GitHub', async () => {
    fetchMock.mockResolvedValue(jsonResponse(200, releasePayload));
    const service = new AppVersionService(new ConfigService());
    const first = await service.getLatest('android');
    const second = await service.getLatest('android');
    expect(second).toEqual(first);
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('缓存按平台隔离：android/ios 各自查询', async () => {
    fetchMock.mockResolvedValue(jsonResponse(200, releasePayload));
    const service = new AppVersionService(new ConfigService());
    await service.getLatest('android');
    await service.getLatest('ios');
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('缓存过期后重新拉取', async () => {
    jest.useFakeTimers();
    try {
      fetchMock.mockResolvedValue(jsonResponse(200, releasePayload));
      const service = new AppVersionService(new ConfigService());
      await service.getLatest('android');
      jest.setSystemTime(Date.now() + 5 * 60 * 1000 + 1);
      await service.getLatest('android');
      expect(fetchMock).toHaveBeenCalledTimes(2);
    } finally {
      jest.useRealTimers();
    }
  });
});
