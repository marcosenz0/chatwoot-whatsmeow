export const getInstagramPreviewUrl = value => {
  try {
    const url = new URL(value?.trim());
    if (
      !['https:', 'http:'].includes(url.protocol) ||
      !['instagram.com', 'www.instagram.com'].includes(url.hostname) ||
      url.username ||
      url.password ||
      url.port
    ) {
      return null;
    }
    const mediaPath = url.pathname.match(
      /^\/(?:[\w.]+\/)?(p|reel|reels|tv)\/([\w-]+)\/?$/
    );
    if (mediaPath) {
      const type = mediaPath[1] === 'reels' ? 'reel' : mediaPath[1];
      const permalink = `https://www.instagram.com/${type}/${mediaPath[2]}/`;
      return { permalink, embedUrl: `${permalink}embed/`, kind: 'media' };
    }
    const profilePath = url.pathname.match(/^\/([\w.]{1,30})\/?$/);
    const reserved = [
      'accounts',
      'direct',
      'explore',
      'stories',
      'reels',
      'p',
      'reel',
      'tv',
      'about',
      'developer',
      'legal',
      'challenge',
    ];
    if (!profilePath || reserved.includes(profilePath[1].toLowerCase())) {
      return null;
    }
    return {
      permalink: `https://www.instagram.com/${profilePath[1]}/`,
      kind: 'profile',
      username: profilePath[1],
    };
  } catch {
    return null;
  }
};

export const getInstagramMediaUrl = value => {
  const target = getInstagramPreviewUrl(value);
  return target?.kind === 'media'
    ? { permalink: target.permalink, embedUrl: target.embedUrl }
    : null;
};
