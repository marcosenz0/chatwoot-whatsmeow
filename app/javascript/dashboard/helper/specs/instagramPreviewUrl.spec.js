import { getInstagramPreviewUrl } from '../instagramMediaHelper';

describe('Instagram profile and alternate media links', () => {
  it('normalizes profile links', () => {
    expect(
      getInstagramPreviewUrl('https://instagram.com/example.user/?igsh=test')
    ).toEqual({
      permalink: 'https://www.instagram.com/example.user/',
      kind: 'profile',
      username: 'example.user',
    });
  });
  it.each(['reels/AbC123', 'example/reel/AbC123'])('normalizes %s', path => {
    expect(
      getInstagramPreviewUrl(`https://www.instagram.com/${path}/`).permalink
    ).toBe('https://www.instagram.com/reel/AbC123/');
  });
  it.each([
    'https://instagram.com/direct/',
    'https://user:pass@instagram.com/profile/',
    'https://instagram.com:444/profile/',
  ])('rejects %s', url => {
    expect(getInstagramPreviewUrl(url)).toBeNull();
  });
});
