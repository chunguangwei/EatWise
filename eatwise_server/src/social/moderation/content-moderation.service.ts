import { Injectable, Logger } from '@nestjs/common';

/** 机审三态（D-17 先审后发：approved 上流 / rejected 拒绝 / manual 转人工队列） */
export type ModerationVerdict = 'approved' | 'rejected' | 'manual';

export interface ModerationResult {
  verdict: ModerationVerdict;
  /** 双语原因（rejected 给作者看；manual/rejected 同时进审核队列） */
  reason?: { zh: string; en: string };
}

/**
 * 内容安全审核抽象（D-17：打卡图文先审后发，异常转人工队列）。
 *
 * 生产实现为第三方内容安全 API（阿里云/腾讯云，〔待外部确认〕M0 定）：
 * 新增一个实现本抽象类的适配器并在 SocialModule 中替换 provider 即可，
 * 调用方（SocialService）不感知具体厂商。机审目标耗时 ≤30s〔假设〕，
 * API 超时/异常应归一为 manual（转人工），不得阻塞发布主流程。
 */
export abstract class ContentModerationService {
  abstract moderate(text: string, imageUrls: string[]): Promise<ModerationResult>;
}

/**
 * 默认桩实现：关键词表模拟三态（〔假设〕关键词表仅用于本地联调与测试，
 * 上线前必须由真实内容安全 API 替换，词表不代表合规口径）。
 */
@Injectable()
export class StubModerationService extends ContentModerationService {
  private readonly logger = new Logger(StubModerationService.name);

  /** 〔假设〕违规词 → rejected（示例词表，非合规清单） */
  private readonly bannedWords = ['赌博', '诈骗', '色情', '暴恐', '毒品', 'casino', 'porn'];

  /** 〔假设〕疑似词 → manual 人工队列（示例词表，非合规清单） */
  private readonly reviewWords = ['加微信', '代购', '兼职', '刷单', '减肥药', 'wechat'];

  async moderate(text: string, imageUrls: string[]): Promise<ModerationResult> {
    const lower = text.toLowerCase();
    if (this.bannedWords.some((w) => lower.includes(w.toLowerCase()))) {
      return {
        verdict: 'rejected',
        reason: {
          zh: '内容包含违规信息，未通过审核',
          en: 'Content violates community guidelines and was not approved',
        },
      };
    }
    if (this.reviewWords.some((w) => lower.includes(w.toLowerCase()))) {
      return {
        verdict: 'manual',
        reason: {
          zh: '内容需人工复核',
          en: 'Content needs manual review',
        },
      };
    }
    // 〔假设〕图片审核未接：MVP 图片为 URL 占位，图片审核随上传链路（POST /uploads/images）
    // 与第三方 API 一并接入；当前仅记录日志，不阻塞文本已过审的帖子。
    if (imageUrls.length > 0) {
      this.logger.log('stub: image moderation skipped (TODO: third-party content safety API)');
    }
    return { verdict: 'approved' };
  }
}
