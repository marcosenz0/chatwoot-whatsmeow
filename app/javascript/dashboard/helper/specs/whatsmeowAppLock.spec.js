import { webcrypto } from 'node:crypto';
import { createAppLock, verifyAppLock } from '../whatsmeowAppLock';

describe('Whatsmeow browser lock', () => {
  beforeEach(() => vi.stubGlobal('crypto', webcrypto));
  afterEach(() => vi.unstubAllGlobals());

  it('stores a salted verifier and accepts only the matching PIN', async () => {
    const config = await createAppLock('731926');
    expect(JSON.stringify(config)).not.toContain('731926');
    expect(await verifyAppLock('731926', config)).toBe(true);
    expect(await verifyAppLock('731927', config)).toBe(false);
    expect((await createAppLock('731926')).hash).not.toEqual(config.hash);
  });
});
