import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  hashPassword,
  newOpaqueToken,
  normalizeEmail,
  normalizeUsername,
  passwordsMatch,
  sha256Hex,
  signDatabaseJwt,
  validDateOfBirth,
  validEmail,
  validatePassword,
  validUsername,
  verifyPassword,
} from '../src/security.js';

test('Username validation & normalization', () => {
  assert.equal(normalizeUsername('  John_Doe '), 'john_doe');
  assert.equal(validUsername('john_doe'), true);
  assert.equal(validUsername('ab'), false); // too short
  assert.equal(validUsername('user@invalid'), false); // invalid characters
  assert.equal(validUsername('valid_123'), true);
});

test('Email validation & normalization', () => {
  assert.equal(normalizeEmail('  TEST@Example.COM '), 'test@example.com');
  assert.equal(validEmail('test@example.com'), true);
  assert.equal(validEmail('invalid-email'), false);
  assert.equal(validEmail('missing@domain'), false);
});

test('Date of Birth validation', () => {
  assert.equal(validDateOfBirth('2000-01-15'), true);
  assert.equal(validDateOfBirth('1995-12-31'), true);
  assert.equal(validDateOfBirth('2099-01-01'), false); // future date rejected
  assert.equal(validDateOfBirth('invalid'), false);
  assert.equal(validDateOfBirth('01-01-2000'), false); // wrong format
});

test('Password policy validation', () => {
  assert.equal(validatePassword('Weak1!'), 'Password must be at least 8 characters long.');
  assert.equal(validatePassword('alllowercase1!'), 'Password must include uppercase, lowercase, number, and symbol.');
  assert.equal(validatePassword('ALLUPPERCASE1!'), 'Password must include uppercase, lowercase, number, and symbol.');
  assert.equal(validatePassword('NoSymbol123'), 'Password must include uppercase, lowercase, number, and symbol.');
  assert.equal(validatePassword('ValidPass123!'), null); // valid
  assert.equal(passwordsMatch('ValidPass123!', 'ValidPass123!'), true);
  assert.equal(passwordsMatch('ValidPass123!', 'Mismatch123!'), false);
});

test('Argon2id password hashing & verification', async () => {
  const password = 'StrongPassword123#';
  const hash = await hashPassword(password);
  assert.equal(hash.startsWith('$argon2id$'), true);

  const isMatch = await verifyPassword(password, hash);
  assert.equal(isMatch, true);

  const isWrong = await verifyPassword('WrongPassword123#', hash);
  assert.equal(isWrong, false);
});

test('Safe handling of missing or placeholder hashes', async () => {
  assert.equal(await verifyPassword('AnyPassword123!', null), false);
  assert.equal(await verifyPassword('AnyPassword123!', ''), false);
  assert.equal(await verifyPassword('AnyPassword123!', 'legacy_placeholder'), false);
  assert.equal(await verifyPassword('AnyPassword123!', '!UNSET!'), false);
});

test('Opaque token and SHA-256 hashing', () => {
  const token = newOpaqueToken();
  assert.equal(typeof token, 'string');
  assert.equal(token.length >= 40, true);

  const hash = sha256Hex(token);
  assert.equal(/^[0-9a-f]{64}$/.test(hash), true);
  assert.equal(sha256Hex(token), hash); // deterministic
});

test('Short-lived database JWT generation', () => {
  const secret = 'kCh5uBCq3/plHHjdgCeMfu6gQaTbwA4g197eH6GAJTF/jRKyzO5ujFNCgOa21pHfdfnSdl9r6tr8iiB2nCu6Nw==';
  const jwt = signDatabaseJwt({
    userId: '11111111-1111-1111-1111-111111111111',
    sessionId: '22222222-2222-2222-2222-222222222222',
    email: 'user@example.com',
    secret,
  });

  const parts = jwt.split('.');
  assert.equal(parts.length, 3);

  const payload = JSON.parse(Buffer.from(parts[1], 'base64').toString('utf8'));
  assert.equal(payload.sub, '11111111-1111-1111-1111-111111111111');
  assert.equal(payload.sid, '22222222-2222-2222-2222-222222222222');
  assert.equal(payload.role, 'authenticated');
  assert.equal(payload.aud, 'authenticated');
  assert.equal(payload.exp > payload.iat, true);
});
