import { test } from 'node:test';
import assert from 'node:assert/strict';
import { health } from './health.ts';

test('health reports ok with rounded uptime', () => {
  assert.deepEqual(health(12.6), { status: 'ok', uptime: 13 });
});
