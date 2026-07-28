import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import { Request, Response } from 'express';
import { BusinessException } from '../errors/business.exception';
import { resolveLocale, translate } from '../i18n/messages';
import { newRequestId } from '../utils/id.util';

/**
 * 统一错误响应（契约 §1.3）：三段式 error.code / message / details，
 * message 按 Accept-Language 本地化（D-15）。
 */
@Catch()
export class GlobalExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger('Exception');

  catch(exception: unknown, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const res = ctx.getResponse<Response>();
    const req = ctx.getRequest<Request>();
    const locale = resolveLocale(req.headers['accept-language']);

    let status = HttpStatus.INTERNAL_SERVER_ERROR;
    let code = 'INTERNAL_ERROR';
    let details: Record<string, unknown> | undefined;

    if (exception instanceof BusinessException) {
      status = exception.getStatus();
      code = exception.code;
      details = exception.details;
    } else if (exception instanceof HttpException) {
      status = exception.getStatus();
      const body = exception.getResponse() as { message?: string | string[] };
      if (status === HttpStatus.TOO_MANY_REQUESTS) {
        code = 'RATE_LIMITED';
        details = { retryAfterSec: 60 };
      } else if (status === HttpStatus.BAD_REQUEST) {
        code = 'VALIDATION_ERROR';
        const msgs = Array.isArray(body?.message)
          ? body.message
          : body?.message
            ? [body.message]
            : [];
        if (msgs.length) details = { fields: msgs };
      } else if (status === HttpStatus.UNAUTHORIZED) {
        code = 'AUTH_TOKEN_INVALID';
      } else if (status === HttpStatus.NOT_FOUND) {
        code = 'NOT_FOUND';
      }
    } else {
      this.logger.error(exception);
    }

    res.status(status).json({
      error: { code, message: translate(code, locale), ...(details ? { details } : {}) },
      meta: {
        serverTime: new Date().toISOString(),
        requestId: (req.headers['x-request-id'] as string) ?? newRequestId(),
      },
    });
  }
}
