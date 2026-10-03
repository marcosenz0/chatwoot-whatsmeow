export const getInstagramMediaUrl = value => {
  try {
    const url = new URL(value);
    if (
      !['https:', 'http:'].includes(url.protocol) ||
      !['instagram.com', 'www.instagram.com'].includes(url.hostname)
    ) {
      return null;
    }
    const path = url.pathname.match(/^\/(p|reel|tv)\/([\w-]+)\/?$/);
    if (!path) return null;
    const permalink = `https://www.instagram.com/${path[1]}/${path[2]}/`;
    return { permalink, embedUrl: `${permalink}embed/` };
  } catch {
    return null;
  }
};
