import jwt from 'jsonwebtoken';
import { randomUUID } from 'node:crypto';
import { sha256 } from '$lib/hash';
import { getClient } from '$lib/redis';
import 'dotenv/config';

export const AUTH_SECRET = process.env.AUTH_SECRET || sha256(randomUUID());

export async function generateToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const oneHour = 60 * 60;
  const token = jwt.sign(
    {
      ok: true,
      iat: now,
      exp: now + oneHour,
    },
    AUTH_SECRET,
  );
  const client = getClient();
  await client.setex(token, oneHour, '1');
  return token;
}

export async function verifyToken(token: string): Promise<boolean> {
  try {
    const decode = jwt.verify(token, AUTH_SECRET);
    if (!decode) return false;
    const client = getClient();
    const exists = await client.exists(token);
    return exists === 1;
  } catch (e) {
    return false;
  }
}

export async function revokeToken(token: string): Promise<void> {
  const client = getClient();
  await client.del(token);
}
