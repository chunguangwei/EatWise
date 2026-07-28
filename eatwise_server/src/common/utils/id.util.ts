import { createHash, randomBytes, randomUUID } from 'crypto';

export function newId(): string {
  return randomUUID();
}

export function newRequestId(): string {
  return `req_${randomBytes(8).toString('hex')}`;
}

export function newRefreshToken(): string {
  return `rt_${randomBytes(24).toString('hex')}`;
}

export function hashToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

export function payloadHash(obj: unknown): string {
  return createHash('sha256')
    .update(JSON.stringify(obj ?? null))
    .digest('hex');
}
