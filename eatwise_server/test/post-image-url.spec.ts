import { randomUUID } from 'crypto';
import { DataStore } from '../src/common/store/data-store';
import { MemoryStoreDriver } from '../src/common/store/store-driver';
import { StubModerationService } from '../src/social/moderation/content-moderation.service';
import { SocialService } from '../src/social/social.service';
import { StreakService } from '../src/streak/streak.service';

const CDN_ORIGIN = 'https://cdn.posts.example.com';
const UPLOAD_URL = '/v1/uploads/legacy-image.jpg';
const CDN_URL = `${CDN_ORIGIN}/legacy-image.png`;

describe('Post image URL outbound filtering', () => {
  let store: DataStore;
  let social: SocialService;
  let userId: string;
  let viewerId: string;
  let previousCdnBaseUrl: string | undefined;

  beforeEach(() => {
    previousCdnBaseUrl = process.env.CDN_BASE_URL;
    process.env.CDN_BASE_URL = CDN_ORIGIN;
    store = new DataStore();
    const driver = new MemoryStoreDriver(store);
    social = new SocialService(driver, new StreakService(driver), new StubModerationService());
    userId = store.createUser({ phone: '+8613800138000', nickname: '作者' }).id;
    viewerId = store.createUser({ phone: '+8613800138001', nickname: '读者' }).id;
  });

  afterEach(() => {
    if (previousCdnBaseUrl === undefined) {
      delete process.env.CDN_BASE_URL;
    } else {
      process.env.CDN_BASE_URL = previousCdnBaseUrl;
    }
  });

  it('历史非法 URL 在创建/详情/feed/管理端视图全部过滤，存量数组不被改写', async () => {
    const legacyUrls = [
      UPLOAD_URL,
      'https://evil.example.com/token-harvester.jpg',
      CDN_URL,
      '//cdn.posts.example.com/protocol-relative.jpg',
      'https://user:pass@cdn.posts.example.com/credentials.jpg',
      'https://cdn.posts.example.com/%ZZ.jpg',
    ];
    const created = (await social.create(userId, {
      clientRequestId: randomUUID(),
      text: '历史帖子',
      imageUrls: legacyUrls,
    })) as { id: string; imageUrls: string[] };
    const expected = [UPLOAD_URL, CDN_URL];

    expect(created.imageUrls).toEqual(expected);
    expect(store.posts.get(created.id)?.imageUrls).toEqual(legacyUrls);

    await social.adminReview(created.id, { action: 'approve' });
    const detail = (await social.getById(viewerId, created.id)) as { imageUrls: string[] };
    expect(detail.imageUrls).toEqual(expected);

    const feed = await social.feed(viewerId);
    const feedItem = feed.items.find((item) => item.id === created.id) as { imageUrls: string[] };
    expect(feedItem.imageUrls).toEqual(expected);

    const admin = await social.adminList('approved');
    const adminItem = admin.items.find((item) => item.id === created.id) as {
      imageUrls: string[];
    };
    expect(adminItem.imageUrls).toEqual(expected);
    expect(store.posts.get(created.id)?.imageUrls).toEqual(legacyUrls);
  });

  it('旧幂等缓存响应同样过滤，缓存记录本身不回写', async () => {
    const dto = {
      clientRequestId: randomUUID(),
      text: '旧幂等响应',
      imageUrls: [UPLOAD_URL],
    };
    await social.create(userId, dto);
    const record = store.idempotency.get(store.idemKey(userId, 'posts', dto.clientRequestId));
    const cached = record?.responseBody as { imageUrls: string[] };
    cached.imageUrls = [UPLOAD_URL, 'https://evil.example.com/cached.jpg'];

    const replay = (await social.create(userId, dto)) as { imageUrls: string[] };

    expect(replay.imageUrls).toEqual([UPLOAD_URL]);
    expect(cached.imageUrls).toEqual([UPLOAD_URL, 'https://evil.example.com/cached.jpg']);
  });
});
