import { Injectable } from '@nestjs/common';
import { err } from '../common/errors/business.exception';
import { DataStore, PostEntity } from '../common/store/data-store';
import { newId, payloadHash } from '../common/utils/id.util';
import { StreakService } from '../streak/streak.service';
import { ContentModerationService } from './moderation/content-moderation.service';
import { CreatePostDto, ReviewPostDto } from './social.dto';

const FEED_PAGE_MAX = 50;

/** 管理端队列筛选口径（reported=被举报待处理：reportCount>0 且当前 rejected） */
export type AdminPostFilter = 'pending' | 'approved' | 'rejected' | 'reported';

/**
 * 社区打卡（M5 P1 / 契约 §3.9）：
 * - 先审后发（D-17）：发布时机审，approved 才上流；rejected 拒绝发布并返回
 *   明确错误码（双语 reason 在 details）；manual 转人工队列（pending，
 *   他人不可见，仅作者可见并带「审核中」标记）。
 * - 打卡流：游标分页倒序，UGC 不分语言圈混排（D-15）。
 * - 点赞/举报幂等；举报即下架并转人工复核（PRD M5 异常与边界）。
 */
@Injectable()
export class SocialService {
  constructor(
    private readonly store: DataStore,
    private readonly streak: StreakService,
    private readonly moderation: ContentModerationService,
  ) {}

  /** C1 发布打卡（幂等 clientRequestId） */
  async create(userId: string, dto: CreatePostDto) {
    const endpoint = 'posts';
    const hash = payloadHash({ text: dto.text, imageUrls: dto.imageUrls ?? [] });
    const idemKey = this.store.idemKey(userId, endpoint, dto.clientRequestId);
    const hit = this.store.idempotency.get(idemKey);
    if (hit) {
      if (hit.payloadHash !== hash) throw err.payloadMismatch();
      return hit.responseBody;
    }

    // 先审后发（D-17）：机审三态分流。
    const verdict = await this.moderation.moderate(dto.text, dto.imageUrls ?? []);
    if (verdict.verdict === 'rejected') {
      throw err.postContentRejected(verdict.reason);
    }

    // streak 服务端权威计算（D-12 口径），忽略客户端提示值。
    const streakDays = this.streak.recompute(userId).currentStreak;
    const now = new Date();
    const post: PostEntity = {
      id: newId(),
      userId,
      clientRequestId: dto.clientRequestId,
      text: dto.text,
      imageUrls: dto.imageUrls ?? [],
      streakDaysAtPost: streakDays,
      likeCount: 0,
      auditStatus: verdict.verdict === 'manual' ? 'pending' : 'approved',
      auditReason: verdict.reason ?? null,
      reportCount: 0,
      reportedAt: null,
      visibility: 'public',
      version: 1,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
    };
    this.store.posts.set(post.id, post);
    if (verdict.verdict === 'manual') {
      this.store.moderationQueue.push({
        postId: post.id,
        source: 'auto',
        reason: verdict.reason?.zh ?? 'manual',
        createdAt: now,
      });
    }

    const response = this.postView(post, userId);
    this.store.idempotency.set(idemKey, {
      userId,
      clientRequestId: dto.clientRequestId,
      endpoint,
      payloadHash: hash,
      responseBody: response,
      createdAt: now,
    });
    return response;
  }

  /** C2 打卡流：他人仅 approved；本人 pending/approved 也可见（带审核中标记）。 */
  feed(viewerId: string, limit = 20, cursor?: string) {
    if (limit > FEED_PAGE_MAX) limit = FEED_PAGE_MAX;
    let after: { t: string; id: string } | null = null;
    if (cursor) {
      try {
        after = JSON.parse(Buffer.from(cursor, 'base64').toString('utf8'));
        if (typeof after?.t !== 'string' || typeof after?.id !== 'string') {
          throw new Error('bad cursor');
        }
      } catch {
        throw err.invalidCursor();
      }
    }

    const visible = [...this.store.posts.values()]
      .filter((p) => !p.deletedAt)
      .filter((p) => p.auditStatus === 'approved' || p.userId === viewerId)
      .sort((a, b) => this.compareDesc(a, b));

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
      items: page.map((p) => this.postView(p, viewerId)),
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

  /** C3 单帖详情：pending/rejected 仅作者可见，他人 404。 */
  getById(viewerId: string, id: string) {
    const post = this.store.posts.get(id);
    if (!post || post.deletedAt) throw err.notFound();
    if (post.userId !== viewerId && post.auditStatus !== 'approved') {
      throw err.notFound();
    }
    return this.postView(post, viewerId);
  }

  /** C4 删除本人打卡（幂等：已删除 → 200）。 */
  remove(userId: string, id: string) {
    const post = this.store.posts.get(id);
    if (!post || post.userId !== userId) throw err.notFound();
    if (post.deletedAt) return { deleted: true };
    post.deletedAt = new Date();
    post.updatedAt = post.deletedAt;
    post.version += 1;
    return { deleted: true };
  }

  /** C5 点赞（幂等键 postId+userId，重复点赞返回 200 不重复计数）。 */
  like(userId: string, id: string) {
    const post = this.visibleForInteract(userId, id);
    const key = this.store.postLikeKey(post.id, userId);
    if (!this.store.postLikes.has(key)) {
      this.store.postLikes.add(key);
      post.likeCount += 1;
      post.updatedAt = new Date();
      post.version += 1;
    }
    return { id: post.id, likeCount: post.likeCount, likedByMe: true };
  }

  /** C6 取消点赞（幂等）。 */
  unlike(userId: string, id: string) {
    const post = this.visibleForInteract(userId, id);
    const key = this.store.postLikeKey(post.id, userId);
    if (this.store.postLikes.delete(key)) {
      post.likeCount = Math.max(0, post.likeCount - 1);
      post.updatedAt = new Date();
      post.version += 1;
    }
    return { id: post.id, likeCount: post.likeCount, likedByMe: false };
  }

  /** C7 举报（幂等）：记录 → 下架 → 转人工复核队列（PRD M5：举报后下架）。 */
  report(userId: string, id: string, reason?: string) {
    const post = this.store.posts.get(id);
    if (!post) throw err.notFound();
    if (post.deletedAt) throw err.resourceGone();
    const key = this.store.postLikeKey(post.id, userId);
    // 幂等前置：首报即下架后，重放仍返回 200（此时帖对该用户已不可见）。
    if (this.store.postReports.has(key)) return { reported: true };
    if (post.userId !== userId && post.auditStatus !== 'approved') {
      throw err.notFound();
    }
    this.store.postReports.set(key, { reason: reason ?? null, createdAt: new Date() });
    // 〔假设〕MVP 举报成立判定后置人工：先下架止血，复核后可恢复（人工队列处理）。
    post.reportCount += 1;
    post.reportedAt = new Date();
    post.auditStatus = 'rejected';
    post.auditReason = {
      zh: '该内容被举报，已暂时下架等待复核',
      en: 'This post was reported and temporarily taken down pending review',
    };
    post.updatedAt = new Date();
    post.version += 1;
    this.store.moderationQueue.push({
      postId: post.id,
      source: 'report',
      reason: reason ?? 'report',
      createdAt: new Date(),
    });
    return { reported: true };
  }

  /**
   * 管理端：审核队列查询（x-admin-token 端点 /v1/admin/posts）。
   * 状态口径：pending=机审转人工待审；approved=已上架；rejected=已拒绝（不含举报）；
   * reported=被举报待处理（reportCount>0 且当前 rejected，举报即下架后的复核队列）。
   */
  adminList(status: AdminPostFilter | undefined, limit = 20, cursor?: string) {
    if (limit > FEED_PAGE_MAX) limit = FEED_PAGE_MAX;
    let after: { t: string; id: string } | null = null;
    if (cursor) {
      try {
        after = JSON.parse(Buffer.from(cursor, 'base64').toString('utf8'));
        if (typeof after?.t !== 'string' || typeof after?.id !== 'string') {
          throw new Error('bad cursor');
        }
      } catch {
        throw err.invalidCursor();
      }
    }

    const match = (p: PostEntity): boolean => {
      switch (status) {
        case 'pending':
          return p.auditStatus === 'pending';
        case 'approved':
          return p.auditStatus === 'approved';
        case 'rejected':
          return p.auditStatus === 'rejected' && p.reportCount === 0;
        case 'reported':
          return p.auditStatus === 'rejected' && p.reportCount > 0;
        default:
          return true;
      }
    };
    const visible = [...this.store.posts.values()]
      .filter((p) => !p.deletedAt)
      .filter(match)
      .sort((a, b) => this.compareDesc(a, b));

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
      items: page.map((p) => this.adminPostView(p)),
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
  adminReview(id: string, dto: ReviewPostDto) {
    const post = this.store.posts.get(id);
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
    // 审核决定落地后清出人工队列（机审转人工与举报复核共用该队列）
    for (let i = this.store.moderationQueue.length - 1; i >= 0; i--) {
      if (this.store.moderationQueue[i].postId === post.id) {
        this.store.moderationQueue.splice(i, 1);
      }
    }
    return this.adminPostView(post);
  }

  /** 管理端视图：含举报计数与审核原因（管理端可见，不受作者可见性约束）。 */
  private adminPostView(post: PostEntity) {
    const author = this.store.users.get(post.userId);
    return {
      id: post.id,
      text: post.text,
      imageUrls: post.imageUrls,
      author: {
        id: post.userId,
        nickname: author?.nickname ?? null,
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

  /** 互动前置：存在、未删除（410）、对当前用户可见。 */
  private visibleForInteract(userId: string, id: string): PostEntity {
    const post = this.store.posts.get(id);
    if (!post) throw err.notFound();
    if (post.deletedAt) throw err.resourceGone();
    if (post.userId !== userId && post.auditStatus !== 'approved') {
      throw err.notFound();
    }
    return post;
  }

  private compareDesc(a: PostEntity, b: PostEntity): number {
    const t = b.createdAt.getTime() - a.createdAt.getTime();
    return t !== 0 ? t : b.id.localeCompare(a.id);
  }

  /** 视图：含作者摘要（〔假设〕契约未列 author 字段，按设计稿单列卡片所需补充）。 */
  postView(post: PostEntity, viewerId: string) {
    const author = this.store.users.get(post.userId);
    const isAuthor = post.userId === viewerId;
    return {
      id: post.id,
      text: post.text,
      imageUrls: post.imageUrls,
      streakDaysAtPost: post.streakDaysAtPost,
      likeCount: post.likeCount,
      likedByMe: this.store.postLikes.has(this.store.postLikeKey(post.id, viewerId)),
      auditStatus: post.auditStatus,
      // 审核原因仅作者可见（契约 §3.9 状态机）
      auditReason: isAuthor ? post.auditReason : null,
      isAuthor,
      author: {
        id: post.userId,
        nickname: author?.nickname ?? null,
        avatarUrl: null,
      },
      createdAt: post.createdAt.toISOString(),
    };
  }
}
