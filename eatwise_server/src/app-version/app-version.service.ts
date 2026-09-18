import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

/** 支持的平台。 */
export type AppPlatform = 'android' | 'ios';

/** GET /v1/app/version/latest 响应体。 */
export interface LatestVersionView {
  latestVersion: string;
  minSupportedVersion: string;
  releaseNotes: { zh: string; en: string };
  /** Android APK 下载地址；iOS 为 null（走 App Store，占位见客户端）。 */
  apkUrl: string | null;
  publishedAt: string | null;
  /** 数据来源：github（Releases 实时）/ fallback（env 静态兜底）。 */
  source: 'github' | 'fallback';
}

interface GitHubAsset {
  name: string;
  browser_download_url: string;
}

interface GitHubRelease {
  tag_name: string;
  body: string | null;
  published_at: string | null;
  assets: GitHubAsset[];
}

interface CacheEntry {
  view: LatestVersionView;
  expiresAt: number;
}

const GITHUB_LATEST_RELEASE_URL =
  'https://api.github.com/repos/chunguangwei/EatWise/releases/latest';

/** 缓存 5 分钟防 GitHub API 限流（匿名 60 次/小时/IP）。 */
const CACHE_TTL_MS = 5 * 60 * 1000;

/**
 * 应用版本查询（私有仓库故由服务端代理 GitHub Releases，App 不持 token）。
 *
 * 数据源优先级：
 * 1. GitHub API `releases/latest`（token 从 env `GITHUB_RELEASE_TOKEN` 读；
 *    不设则匿名请求——私有仓库会 404）；版本号/更新说明/发布时间以此为准，
 *    但 android 的 apkUrl 优先取 env `APP_APK_URL`（自托管地址，非空才覆盖）——
 *    私有仓 release asset 的 browser_download_url 匿名访问 404，客户端拿不到 APK；
 * 2. 失败时降级 env 静态配置兜底（`APP_LATEST_VERSION`/`APP_APK_URL` 等，
 *    〔假设〕发版流水线/运维同步维护该配置）。
 *
 * 〔假设〕Release body 为单语文案，zh/en 同填；双语分发的排版约定待定。
 */
@Injectable()
export class AppVersionService {
  private readonly logger = new Logger(AppVersionService.name);
  private readonly cache = new Map<AppPlatform, CacheEntry>();

  constructor(private readonly config: ConfigService) {}

  async getLatest(platform: AppPlatform): Promise<LatestVersionView> {
    const now = Date.now();
    const cached = this.cache.get(platform);
    if (cached && cached.expiresAt > now) {
      return cached.view;
    }
    const view = await this.fetchLatest(platform);
    this.cache.set(platform, { view, expiresAt: now + CACHE_TTL_MS });
    return view;
  }

  private async fetchLatest(platform: AppPlatform): Promise<LatestVersionView> {
    const minSupportedVersion = this.config.get<string>('APP_MIN_SUPPORTED_VERSION') ?? '1.0.0';
    try {
      const release = await this.fetchGitHubLatestRelease();
      const version = release.tag_name.replace(/^v/i, '');
      // 〔假设〕Release body 单语，双语同填。
      const notes = release.body ?? '';
      const apkAsset =
        platform === 'android' ? release.assets.find((a) => a.name.endsWith('.apk')) : undefined;
      // 私有仓 asset 匿名 404：android 优先用 env 自托管地址覆盖下载链接
      // （版本号/说明/发布时间仍来自 GitHub）。
      const selfHostedApkUrl = this.config.get<string>('APP_APK_URL');
      const apkUrl =
        platform === 'android' && selfHostedApkUrl
          ? selfHostedApkUrl
          : (apkAsset?.browser_download_url ?? null);
      return {
        latestVersion: version,
        minSupportedVersion,
        releaseNotes: { zh: notes, en: notes },
        apkUrl,
        publishedAt: release.published_at,
        source: 'github',
      };
    } catch (error) {
      // 降级：私有仓库匿名 404 / 限流 / 网络异常 → env 静态配置兜底。
      this.logger.warn(`GitHub Releases 查询失败，降级 env 静态配置: ${String(error)}`);
      return this.fallbackFromEnv(platform, minSupportedVersion);
    }
  }

  private async fetchGitHubLatestRelease(): Promise<GitHubRelease> {
    const token = this.config.get<string>('GITHUB_RELEASE_TOKEN');
    const headers: Record<string, string> = {
      Accept: 'application/vnd.github+json',
      'User-Agent': 'eatwise-server',
      'X-GitHub-Api-Version': '2022-11-28',
    };
    if (token) headers.Authorization = `Bearer ${token}`;
    const res = await fetch(GITHUB_LATEST_RELEASE_URL, { headers });
    if (!res.ok) {
      throw new Error(`GitHub API ${res.status}`);
    }
    return (await res.json()) as GitHubRelease;
  }

  private fallbackFromEnv(platform: AppPlatform, minSupportedVersion: string): LatestVersionView {
    const latestVersion = this.config.get<string>('APP_LATEST_VERSION') ?? minSupportedVersion;
    const notesZh = this.config.get<string>('APP_RELEASE_NOTES_ZH') ?? '';
    const notesEn = this.config.get<string>('APP_RELEASE_NOTES_EN') ?? notesZh;
    return {
      latestVersion,
      minSupportedVersion,
      releaseNotes: { zh: notesZh, en: notesEn },
      apkUrl: platform === 'android' ? (this.config.get<string>('APP_APK_URL') ?? null) : null,
      publishedAt: null,
      source: 'fallback',
    };
  }
}
