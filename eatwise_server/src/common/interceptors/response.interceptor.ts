import { CallHandler, ExecutionContext, Injectable, NestInterceptor } from '@nestjs/common';
import { Request } from 'express';
import { Observable, map } from 'rxjs';
import { newRequestId } from '../utils/id.util';

/**
 * 统一成功响应（契约 §1.3）：{ data, meta: { serverTime, requestId } }。
 * serverTime 供客户端校准时钟漂移（配合 D-07）。
 */
@Injectable()
export class ResponseInterceptor implements NestInterceptor {
  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const req = context.switchToHttp().getRequest<Request>();
    return next.handle().pipe(
      map((data) => ({
        data: data ?? {},
        meta: {
          serverTime: new Date().toISOString(),
          requestId: (req.headers['x-request-id'] as string) ?? newRequestId(),
        },
      })),
    );
  }
}
