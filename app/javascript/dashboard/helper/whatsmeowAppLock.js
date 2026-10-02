const ITERATIONS = 210000;
const encode = bytes => btoa(String.fromCharCode(...bytes));
const decode = value =>
  Uint8Array.from(atob(value), char => char.charCodeAt(0));

async function derive(pin, salt) {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(pin),
    'PBKDF2',
    false,
    ['deriveBits']
  );
  return encode(
    new Uint8Array(
      await crypto.subtle.deriveBits(
        { name: 'PBKDF2', salt, iterations: ITERATIONS, hash: 'SHA-256' },
        key,
        256
      )
    )
  );
}
export async function createAppLock(pin) {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  return { salt: encode(salt), hash: await derive(pin, salt) };
}
export async function verifyAppLock(pin, config) {
  return (await derive(pin, decode(config.salt))) === config.hash;
}
