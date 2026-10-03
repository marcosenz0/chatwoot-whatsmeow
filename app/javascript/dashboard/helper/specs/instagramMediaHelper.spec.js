import { getInstagramMediaUrl } from '../instagramMediaHelper';

describe('Instagram shared media URLs', () => {
  it.each(['p', 'reel', 'tv'])(
    'normalizes %s links for embedded previews',
    type => {
      expect(
        getInstagramMediaUrl(
          `https://instagram.com/${type}/AbC_123-/?igsh=test`
        )
      ).toEqual({
        permalink: `https://www.instagram.com/${type}/AbC_123-/`,
        embedUrl: `https://www.instagram.com/${type}/AbC_123-/embed/`,
      });
    }
  );

  it.each([
    undefined,
    '',
    'https://lookaside.fbsbx.com/ig_messaging_cdn/file',
    'https://www.instagram.com/user/',
    'https://www.instagram.com.evil.example/reel/123/',
    'https://example.com/reel/123/',
    'data:text/html,test',
    'https://www.instagram.com/reel/123/embed/',
  ])('keeps non-post or untrusted URLs out of embedded frames: %s', url => {
    expect(getInstagramMediaUrl(url)).toBeNull();
  });
});
