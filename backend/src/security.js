
import {
  createCipheriv,
  createDecipheriv,
  createHash,
  createHmac,
  randomBytes,
  timingSafeEqual,
} from 'node:crypto';

import argon2 from 'argon2';
import bcrypt from 'bcryptjs';

// -----------------------------------------------------------------------------
// USERNAME AND EMAIL VALIDATION
// -----------------------------------------------------------------------------

export function normalizeUsername(username) {
  return username.trim().toLowerCase();
}

export function validUsername(username) {
  return (
    typeof username === 'string' &&
    /^[A-Za-z0-9_]{3,30}$/.test(username.trim())
  );
}

export function normalizeEmail(email) {
  return email.trim().toLowerCase();
}

export function validEmail(email) {
  return (
    typeof email === 'string' &&
    /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())
  );
}

// -----------------------------------------------------------------------------
// DATE OF BIRTH VALIDATION
// -----------------------------------------------------------------------------

export function validDateOfBirth(dateString) {
  if (
    typeof dateString !== 'string' ||
    !/^\d{4}-\d{2}-\d{2}$/.test(dateString.trim())
  ) {
    return false;
  }

  const value = dateString.trim();
  const date = new Date(`${value}T00:00:00.000Z`);

  if (Number.isNaN(date.getTime())) return false;
  if (date.toISOString().slice(0, 10) !== value) return false;

  const today = new Date();
  today.setUTCHours(23, 59, 59, 999);

  return date <= today && date.getUTCFullYear() >= 1900;
}

// -----------------------------------------------------------------------------
// PASSWORD VALIDATION
// -----------------------------------------------------------------------------

export function validatePassword(password) {
  if (typeof password !== 'string' || password.length < 8) {
    return 'Password must be at least 8 characters long.';
  }

  if (
    !/[A-Z]/.test(password) ||
    !/[a-z]/.test(password) ||
    !/\d/.test(password) ||
    !/[^A-Za-z0-9]/.test(password)
  ) {
    return 'Password must include uppercase, lowercase, number, and symbol.';
  }

  return null;
}

export function passwordsMatch(p1, p2) {
  return (
    typeof p1 === 'string' &&
    typeof p2 === 'string' &&
    p1 === p2 &&
    p1.length > 0
  );
}

// -----------------------------------------------------------------------------
// PASSWORD HASHING
// -----------------------------------------------------------------------------

export async function hashPassword(password) {
  return await argon2.hash(password, {
    type: argon2.argon2id,
    memoryCost: 19456,
    timeCost: 2,
    parallelism: 1,
  });
}

export async function verifyPassword(password, storedHash) {
  if (
    typeof password !== 'string' ||
    typeof storedHash !== 'string' ||
    !storedHash
  ) {
    return false;
  }

  if (
    storedHash.startsWith('!') ||
    storedHash === 'legacy_placeholder'
  ) {
    return false;
  }

  if (storedHash.startsWith('$argon2')) {
    try {
      return await argon2.verify(storedHash, password);
    } catch {
      return false;
    }
  }

  if (storedHash.startsWith('$2')) {
    try {
      return await bcrypt.compare(password, storedHash);
    } catch {
      return false;
    }
  }

  return false;
}

// -----------------------------------------------------------------------------
// OPAQUE TOKENS AND HASHING
// -----------------------------------------------------------------------------

export function newOpaqueToken() {
  return randomBytes(32).toString('base64url');
}

export function sha256Hex(value) {
  return createHash('sha256')
    .update(value, 'utf8')
    .digest('hex');
}

export function hmacHex(secret, message) {
  return createHmac('sha256', secret)
    .update(message, 'utf8')
    .digest('hex');
}

export function constantTimeHexEqual(a, b) {
  if (
    typeof a !== 'string' ||
    typeof b !== 'string' ||
    a.length !== b.length ||
    a.length % 2 !== 0 ||
    !/^[0-9a-f]*$/i.test(a) ||
    !/^[0-9a-f]*$/i.test(b)
  ) {
    return false;
  }

  const bufA = Buffer.from(a, 'hex');
  const bufB = Buffer.from(b, 'hex');

  if (bufA.length !== bufB.length) return false;

  return timingSafeEqual(bufA, bufB);
}

// -----------------------------------------------------------------------------
// DATABASE JWT SIGNING
// -----------------------------------------------------------------------------

function base64UrlEncode(value) {
  return Buffer.from(value)
    .toString('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

export function signDatabaseJwt({
  userId,
  sessionId,
  email,
  secret,
  expiresInSeconds = 60,
}) {
  if (
    typeof userId !== 'string' ||
    typeof sessionId !== 'string' ||
    typeof secret !== 'string' ||
    !secret
  ) {
    throw new TypeError('Valid user, session, and JWT secret are required.');
  }

  if (
    !Number.isInteger(expiresInSeconds) ||
    expiresInSeconds < 1
  ) {
    throw new TypeError('JWT expiry must be a positive integer.');
  }

  const header = {
    alg: 'HS256',
    typ: 'JWT',
  };

  const now = Math.floor(Date.now() / 1000);

  const payload = {
    aud: 'authenticated',
    role: 'authenticated',
    sub: userId,
    sid: sessionId,
    email: email || '',
    iat: now,
    exp: now + expiresInSeconds,
  };

  const encodedHeader = base64UrlEncode(JSON.stringify(header));
  const encodedPayload = base64UrlEncode(JSON.stringify(payload));

  const signature = createHmac('sha256', secret)
    .update(`${encodedHeader}.${encodedPayload}`)
    .digest('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');

  return `${encodedHeader}.${encodedPayload}.${signature}`;
}

// -----------------------------------------------------------------------------
// AES-256-GCM ENCRYPTION KEY VALIDATION
// -----------------------------------------------------------------------------

export function parseAndValidateEncryptionKey(hexKey) {
  if (typeof hexKey !== 'string' || !hexKey.trim()) {
    throw new Error(
      'GOOGLE_CALENDAR_ENCRYPTION_KEY is required and must be a 64-character hex string.'
    );
  }

  const trimmed = hexKey.trim();

  if (!/^[0-9a-fA-F]{64}$/.test(trimmed)) {
    throw new Error(
      'GOOGLE_CALENDAR_ENCRYPTION_KEY must be exactly 32 bytes (64 hexadecimal characters).'
    );
  }

  return Buffer.from(trimmed, 'hex');
}

// -----------------------------------------------------------------------------
// AES-256-GCM ENCRYPTION
// Output format: IV:AUTH_TAG:CIPHERTEXT
// -----------------------------------------------------------------------------

export function encryptAes256Gcm(plaintext, keyBuffer) {
  if (typeof plaintext !== 'string') {
    throw new TypeError('Plaintext to encrypt must be a string.');
  }

  const key = Buffer.isBuffer(keyBuffer)
    ? keyBuffer
    : parseAndValidateEncryptionKey(keyBuffer);

  if (key.length !== 32) {
    throw new Error('AES-256-GCM requires a 32-byte key.');
  }

  const iv = randomBytes(12);

  const cipher = createCipheriv('aes-256-gcm', key, iv);

  const encrypted = Buffer.concat([
    cipher.update(plaintext, 'utf8'),
    cipher.final(),
  ]);

  return [
    iv.toString('hex'),
    cipher.getAuthTag().toString('hex'),
    encrypted.toString('hex'),
  ].join(':');
}

// -----------------------------------------------------------------------------
// AES-256-GCM DECRYPTION
// -----------------------------------------------------------------------------

export function decryptAes256Gcm(ciphertextString, keyBuffer) {
  if (
    typeof ciphertextString !== 'string' ||
    !ciphertextString
  ) {
    throw new TypeError('Invalid encrypted value.');
  }

  const parts = ciphertextString.split(':');

  if (parts.length !== 3) {
    throw new Error('Invalid encrypted value format.');
  }

  const [ivHex, authTagHex, encryptedHex] = parts;

  if (
    !/^[0-9a-f]{24}$/i.test(ivHex) ||
    !/^[0-9a-f]{32}$/i.test(authTagHex) ||
    !/^(?:[0-9a-f]{2})*$/i.test(encryptedHex)
  ) {
    throw new Error('Invalid encrypted value encoding.');
  }

  const key = Buffer.isBuffer(keyBuffer)
    ? keyBuffer
    : parseAndValidateEncryptionKey(keyBuffer);

  if (key.length !== 32) {
    throw new Error('AES-256-GCM requires a 32-byte key.');
  }

  const decipher = createDecipheriv(
    'aes-256-gcm',
    key,
    Buffer.from(ivHex, 'hex'),
  );

  decipher.setAuthTag(Buffer.from(authTagHex, 'hex'));

  const decrypted = Buffer.concat([
    decipher.update(Buffer.from(encryptedHex, 'hex')),
    decipher.final(),
  ]);

  return decrypted.toString('utf8');
}
