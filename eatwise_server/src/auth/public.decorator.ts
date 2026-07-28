import { SetMetadata } from '@nestjs/common';

export const IS_PUBLIC_KEY = 'isPublic';
/** 公开接口标记：/auth/sms/send、/auth/login/*、/auth/refresh、/health（契约 §1.2） */
export const Public = () => SetMetadata(IS_PUBLIC_KEY, true);
