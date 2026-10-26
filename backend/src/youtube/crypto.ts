import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';

export function tokenKey(): Buffer {
  const value = process.env.YOUTUBE_TOKEN_KEY ?? '';
  if (!/^[a-f0-9]{64}$/i.test(value)) {
    throw new Error('YOUTUBE_TOKEN_KEY must be 32 random bytes encoded as hex');
  }
  return Buffer.from(value, 'hex');
}
export function encryptSecret(value: string): string {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', tokenKey(), iv);
  const encrypted = Buffer.concat([
    cipher.update(value, 'utf8'),
    cipher.final(),
  ]);
  return [iv, cipher.getAuthTag(), encrypted]
    .map((part) => part.toString('base64url'))
    .join('.');
}
export function decryptSecret(value: string): string {
  const parts = value.split('.');
  if (parts.length !== 3) throw new Error('Invalid encrypted credential');
  const [iv, tag, data] = parts.map((part) => Buffer.from(part, 'base64url'));
  const cipher = createDecipheriv('aes-256-gcm', tokenKey(), iv);
  cipher.setAuthTag(tag);
  return Buffer.concat([cipher.update(data), cipher.final()]).toString('utf8');
}
