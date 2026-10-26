import { Inject, Injectable } from '@nestjs/common';
import { err } from '../common/errors/business.exception';
import { PostEntity, UserEntity } from '../common/store/data-store';
import { STORE_DRIVER, StoreDriver } from '../common/store/store-driver';
import { newId, payloadHash } from '../common/utils/id.util';
import { clampPageLimit } from '../common/utils/pagination.util';
import { StreakService } from '../streak/streak.service';
import { ContentModerationService } from './moderation/content-moderation.service';
import { allowedPostImageUrls, CreatePostDto, ReviewPostDto } from './social.dto';

const FEED_PAGE_MAX = 50;

/** 管理端队列筛选口径（reported=被举报待处理：reportCount>0 且当前 rejected） */
export type AdminPostFilter = 'pending' | 'approved' | 'rejected' | 'reported';

/**
 * 社区打卡（M5 P1 / 契约 §3.9）：
 * - 图片帖先 pending 人工审核，批准后上架；纯文字保持直接发布。
 *   举报下架/人工复核队列链路保留；此处不将占位机审当作真实审核。
 * - 打卡流：游标分页倒序，UGC 不分语言圈混排（D-15）。
 * - 点赞/举报幂等；举报即下架并转人工复核（PRD M5 异常与边界）。
 *
 * 持久化统一走 StoreDriver：流可见集/审核队列的筛选与排序、点赞计数（驱动
 * 事务内维护 likeCount/version）均由驱动承担，Service 只管状态机与视图组装。
 */
@Injectable()
export class SocialService {
  constructor(
    @Inject(STORE_DRIVER) private readonly driver: StoreDriver,
    private readonly streak: StreakService,
    private readonly moderation: ContentModerationService,
  ) {}

  /** C1 发布打卡：图片先人工审核；纯文字延续开放模式。 */
  async create(userId: string, dto: CreatePostDto) {
    const endpoint = 'posts';
    const hash = payloadHash({
      text: dto.text,
      imageUrls: dto.imageUrls ?? [],
      anonymous: dto.anonymous ?? false,
      avatarId: dto.avatarId ?? null,
    });
    return this.driver.runInTransaction(
      [`post-create:${userId}:${dto.clientRequestId}`, `streak:${userId}`],
      async (tx) => {
        const hit = await tx.findIdempotencyRecord(userId, endpoint, dto.clientRequestId);
        if (hit) {
          if (hit.payloadHash !== hash) throw err.payloadMismatch();
          const cached = hit.responseBody;
          if (cached !== null && typeof cached === 'object' && 'imageUrls' in cached) {
            return { ...cached, imageUrls: allowedPostImageUrls(cached.imageUrls) };
          }
          return cached;
        }

        // 供应商未接入前不把图片当作已机审；发布、入队和回执必须一起提交。
        const needsImageReview = (dto.imageUrls?.length ?? 0) > 0;
        const streakDays = (await this.streak.recompute(userId, tx)).currentStreak;
        const now = new Date();
        const post: PostEntity = {
          id: newId(),
          userId,
          clientRequestId: dto.clientRequestId,
          text: dto.text,
          imageUrls: dto.imageUrls ?? [],
          streakDaysAtPost: streakDays,
          anonymous: dto.anonymous ?? false,
          avatarId: dto.anonymous ? (dto.avatarId ?? null) : null,
          likeCount: 0,
          auditStatus: needsImageReview ? 'pending' : 'approved',
          auditReason: needsImageReview
            ? {
                zh: '图片等待人工审核，通过后公开展示',
                en: 'Images are awaiting manual review and will be public after approval',
              }
            : null,
          reportCount: 0,
          reportedAt: null,
          visibility: 'public',
          version: 1,
          createdAt: now,
          updatedAt: now,
          deletedAt: null,
        };
        await tx.savePost(post);
        if (needsImageReview) {
          await tx.enqueueModerationItem({
            postId: post.id,
            source: 'auto',
            reason: 'IMAGE_REVIEW_REQUIRED',
            createdAt: now,
          });
        }
        const [response] = await this.postViews([post], userId, tx);
        await tx.saveIdempotencyRecord({
          userId,
          clientRequestId: dto.clientRequestId,
          endpoint,
          payloadHash: hash,
          responseBody: response,
          createdAt: now,
        });
        return response;
      },
    );
  }

  /** C2 打卡流：他人仅 approved；本人 pending/approved 也可见（带审核中标记）。
   * UGC 屏蔽（App Store 条例 1.2）：我屏蔽的作者不出现在我的信息流（单向过滤）。 */
  async feed(viewerId: string, limit = 20, cursor?: string) {
    limit = clampPageLimit(limit, 20, FEED_PAGE_MAX); // 非法 limit（负数/NaN）回落默认，防游标死循环
    const after = this.parseCursor(cursor);

    // 可见集 + 倒序（createdAt, id）由驱动给出口径（未删除 && (approved || 本人)）。
    const all = await this.driver.findFeedPosts(viewerId);
    const blockedIds = new Set(await this.driver.listUserBlockedIds(viewerId));
    const visible = blockedIds.size === 0 ? all : all.filter((p) => !blockedIds.has(p.userId));

    let start = 0;
    if (after) {
      start = visible.findIndex(
        (p) =>
          p.createdAt.toISOString() < after.t ||
          (p.createdAt.toISOString() === after.t && p.id < after.id),
      );
      if (start === -1) start = visible.length;
    }
    const page = visible.slice(start, start + limit);
    const hasMore = start + limit < visible.length;
    const last = page[page.length - 1];
    return {
      items: await this.postViews(page, viewerId),
      pageInfo: {
        nextCursor:
          hasMore && last
            ? Buffer.from(
                JSON.stringify({ t: last.createdAt.toISOString(), id: last.id }),
              ).toString('base64')
            : null,
        hasMore,
      },
    };
  }

  /** C3 单帖详情：pending/rejected 仅作者可见，他人 404；我屏蔽的作者帖 404。 */
  async getById(viewerId: string, id: string) {
    const post = await this.driver.findPostById(id);
    if (!post || post.deletedAt) throw err.notFound();
    if (post.userId !== viewerId && post.auditStatus !== 'approved') {
      throw err.notFound();
    }
    if (await this.isBlockedBetween(viewerId, post.userId)) throw err.notFound();
    const [view] = await this.postViews([post], viewerId);
    return view;
  }

  /** C4 删除本人打卡（幂等），待审图片同时退出人工队列。 */
  async remove(userId: string, id: string) {
    return this.driver.runInTransaction([`post:${id}`], async (tx) => {
      const post = await tx.findPostById(id);
      if (!post || post.userId !== userId) throw err.notFound();
      if (post.deletedAt) return { deleted: true };
      post.deletedAt = new Date();
      post.updatedAt = post.deletedAt;
      post.version += 1;
      await tx.savePost(post);
      await tx.removeModerationByPost(post.id);
      return { deleted: true };
    });
  }

  /** C5 点赞（幂等键 postId+userId，重复点赞返回 200 不重复计数）。 */
  async like(userId: string, id: string) {
    return this.driver.runInTransaction([`post:${id}`], async (tx) => {
      const post = await this.visibleForInteract(userId, id, tx);
      // 与审核/删除共用锁，避免整行保存覆盖计数；锁内先判幂等，避免 PG
      // 唯一冲突使外层事务中止（捕获冲突并不能恢复 PostgreSQL 事务）。
      if (!(await tx.hasPostLike(post.id, userId))) await tx.likePost(post.id, userId);
      const fresh = await tx.findPostById(post.id);
      if (!fresh) throw err.notFound();
      return { id: fresh.id, likeCount: fresh.likeCount, likedByMe: true };
    });
  }

  /** C6 取消点赞（幂等）。 */
  async unlike(userId: string, id: string) {
    return this.driver.runInTransaction([`post:${id}`], async (tx) => {
      const post = await this.visibleForInteract(userId, id, tx);
      await tx.unlikePost(post.id, userId);
      const fresh = await tx.findPostById(post.id);
      if (!fresh) throw err.notFound();
      return { id: fresh.id, likeCount: fresh.likeCount, likedByMe: false };
    });
  }

  /** C7 举报（幂等）：记录 → 下架 → 转人工复核队列（PRD M5：举报后下架）。 */
  async report(userId: string, id: string, reason?: string) {
    return this.driver.runInTransaction([`post:${id}`], async (tx) => {
      const post = await tx.findPostById(id);
      if (!post) throw err.notFound();
      if (post.deletedAt) throw err.resourceGone();
      // 幂等前置：首报即下架后，重放仍返回 200（此时帖对该用户已不可见）。
      if (await tx.hasPostReport(post.id, userId)) return { reported: true };
      if (post.userId !== userId && post.auditStatus !== 'approved') {
        throw err.notFound();
      }
      // 屏蔽关系存在时不允许举报（被屏蔽者不能借举报下架我的帖；同一 404 口径防探测）
      if (await this.isBlockedBetween(userId, post.userId, tx)) throw err.notFound();
      await tx.createPostReport(post.id, userId, reason ?? null);
      // 回执、计数、下架和入队共提交；与删除/审核共用锁，旧快照不得复活帖子。
      await tx.incrementPostReportCount(post.id);
      // 〔假设〕MVP 举报成立判定后置人工：先下架止血，复核后可恢复（人工队列处理）。
      const reported = await tx.findPostById(post.id);
      if (!reported) throw err.notFound();
      reported.auditStatus = 'rejected';
      reported.auditReason = {
        zh: '该内容被举报，已暂时下架等待复核',
        en: 'This post was reported and temporarily taken down pending review',
      };
      reported.updatedAt = new Date();
      reported.version += 1;
      await tx.savePost(reported);
      await tx.enqueueModerationItem({
        postId: post.id,
        source: 'report',
        reason: reason ?? 'report',
        createdAt: new Date(),
      });
      return { reported: true };
    });
  }

  /**
   * 管理端：审核队列查询（x-admin-token 端点 /v1/admin/posts）。
   * 状态口径：pending=图片待人工审核；approved=已上架；rejected=已拒绝（不含举报）；
   * reported=被举报待处理（reportCount>0 且当前 rejected，举报即下架后的复核队列）。
   */
  async adminList(status: AdminPostFilter | undefined, limit = 20, cursor?: string) {
    limit = clampPageLimit(limit, 20, FEED_PAGE_MAX);
    const after = this.parseCursor(cursor);

    // 队列筛选（含 reported 口径）与倒序由驱动承担
    const visible = await this.driver.listPostsForAdmin(status);

    let start = 0;
    if (after) {
      start = visible.findIndex(
        (p) =>
          p.createdAt.toISOString() < after.t ||
          (p.createdAt.toISOString() === after.t && p.id < after.id),
      );
      if (start === -1) start = visible.length;
    }
    const page = visible.slice(start, start + limit);
    const hasMore = start + limit < visible.length;
    const last = page[page.length - 1];
    const names = await this.authorNames(page);
    return {
      items: page.map((p) => this.adminPostView(p, names)),
      pageInfo: {
        nextCursor:
          hasMore && last
            ? Buffer.from(
                JSON.stringify({ t: last.createdAt.toISOString(), id: last.id }),
              ).toString('base64')
            : null,
        hasMore,
      },
    };
  }

  /**
   * 管理端：审核决定（version+1，auditReason 记录操作原因）。
   * approve：pending/rejected（含 reported）→ approved 上架恢复；
   * reject：pending/approved → rejected 下架（reason 透传给作者，〔假设〕双语同文案）。
   * 同状态重复审核 → 409 CONFLICT；已删除帖 → 410。
   */
  async adminReview(id: string, dto: ReviewPostDto) {
    return this.driver.runInTransaction([`post:${id}`], async (tx) => {
      const post = await tx.findPostById(id);
      if (!post) throw err.notFound();
      if (post.deletedAt) throw err.resourceGone();
      if (dto.action === 'approve' && post.auditStatus === 'approved') {
        throw err.conflict({ auditStatus: post.auditStatus });
      }
      if (dto.action === 'reject' && post.auditStatus === 'rejected') {
        throw err.conflict({ auditStatus: post.auditStatus });
      }

      post.auditStatus = dto.action === 'approve' ? 'approved' : 'rejected';
      post.auditReason = dto.reason
        ? { zh: dto.reason, en: dto.reason }
        : dto.action === 'reject'
          ? { zh: '内容未通过人工审核，已下架', en: 'Content did not pass manual review' }
          : null;
      post.updatedAt = new Date();
      post.version += 1;
      await tx.savePost(post);
      // 决定与出队同事务；清队列失败不得出现已公开但仍待审的半提交。
      await tx.removeModerationByPost(post.id);
      return this.adminPostView(post, await this.authorNames([post], tx));
    });
  }

  /** 游标解码：{t, id} base64；非法 → 400 INVALID_CURSOR */
  private parseCursor(cursor?: string): { t: string; id: string } | null {
    if (!cursor) return null;
    try {
      const after = JSON.parse(Buffer.from(cursor, 'base64').toString('utf8'));
      if (typeof after?.t !== 'string' || typeof after?.id !== 'string') {
        throw new Error('bad cursor');
      }
      return after;
    } catch {
      throw err.invalidCursor();
    }
  }

  /** 作者摘要（U5 匿名化帖子 userId='' 无作者行） */
  private async authorNames(
    posts: PostEntity[],
    driver: StoreDriver = this.driver,
  ): Promise<Map<string, string | null>> {
    const names = new Map<string, string | null>();
    for (const id of new Set(posts.map((p) => p.userId).filter(Boolean))) {
      const author: UserEntity | null = await driver.findUserById(id);
      names.set(id, author?.nickname ?? null);
    }
    return names;
  }

  /** 管理端视图：含举报计数与审核原因（管理端可见，不受作者可见性约束）。 */
  private adminPostView(post: PostEntity, names: Map<string, string | null>) {
    return {
      id: post.id,
      text: post.text,
      imageUrls: allowedPostImageUrls(post.imageUrls),
      author: {
        id: post.userId,
        nickname: names.get(post.userId) ?? null,
      },
      likeCount: post.likeCount,
      auditStatus: post.auditStatus,
      auditReason: post.auditReason,
      reportCount: post.reportCount,
      reportedAt: post.reportedAt ? post.reportedAt.toISOString() : null,
      version: post.version,
      createdAt: post.createdAt.toISOString(),
      updatedAt: post.updatedAt.toISOString(),
    };
  }

  /** 互动前置：存在、未删除（410）、对当前用户可见、无双向屏蔽。 */
  private async visibleForInteract(
    userId: string,
    id: string,
    driver: StoreDriver = this.driver,
  ): Promise<PostEntity> {
    const post = await driver.findPostById(id);
    if (!post) throw err.notFound();
    if (post.deletedAt) throw err.resourceGone();
    if (post.userId !== userId && post.auditStatus !== 'approved') {
      throw err.notFound();
    }
    // UGC 屏蔽（App Store 条例 1.2）：我屏蔽的作者帖互动 404；
    // 被屏蔽者也不能再给我发的帖点赞/举报（双向拦截，同一 404 口径防探测）。
    if (await this.isBlockedBetween(userId, post.userId, driver)) throw err.notFound();
    return post;
  }

  /** 双向屏蔽判定：任一方屏蔽另一方即视为隔离（匿名化帖 userId='' 恒不命中）。 */
  private async isBlockedBetween(
    a: string,
    b: string,
    driver: StoreDriver = this.driver,
  ): Promise<boolean> {
    if (!a || !b || a === b) return false;
    return (await driver.hasUserBlock(a, b)) || (await driver.hasUserBlock(b, a));
  }

  /** 视图组装（详情/打卡流共用）：作者摘要按作者去重查询，likedByMe 逐帖判定。 */
  private async postViews(
    posts: PostEntity[],
    viewerId: string,
    driver: StoreDriver = this.driver,
  ) {
    const names = await this.authorNames(posts, driver);
    return Promise.all(
      posts.map(async (post) => {
        const isAuthor = post.userId === viewerId;
        // 匿名帖遮蔽：非作者查看不下发 author.id/nickname（昵称泄漏面在服务端收口）；
        // 作者本人保留真实昵称，便于区分自己的匿名帖。avatarId 恒下发（客户端预设头像库渲染）。
        const masked = post.anonymous && !isAuthor;
        return {
          id: post.id,
          text: post.text,
          imageUrls: allowedPostImageUrls(post.imageUrls),
          streakDaysAtPost: post.streakDaysAtPost,
          likeCount: post.likeCount,
          likedByMe: await driver.hasPostLike(post.id, viewerId),
          auditStatus: post.auditStatus,
          // 审核原因仅作者可见（契约 §3.9 状态机）
          auditReason: isAuthor ? post.auditReason : null,
          isAuthor,
          anonymous: post.anonymous,
          avatarId: post.avatarId,
          author: masked
            ? { id: null, nickname: null, avatarUrl: null }
            : {
                id: post.userId,
                nickname: names.get(post.userId) ?? null,
                avatarUrl: null,
              },
          createdAt: post.createdAt.toISOString(),
        };
      }),
    );
  }
}
