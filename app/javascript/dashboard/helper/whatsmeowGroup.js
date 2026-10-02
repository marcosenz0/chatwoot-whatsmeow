export const whatsmeowGroupJid = chat =>
  chat?.meta?.sender?.additional_attributes?.whatsmeow_group_jid ||
  chat?.meta?.sender?.additional_attributes?.group_jid ||
  chat?.additional_attributes?.group_jid ||
  (chat?.contact_inbox?.source_id?.endsWith('@g.us')
    ? chat.contact_inbox.source_id
    : '');

export async function groupPhoto(file) {
  const bitmap = await createImageBitmap(file);
  const canvas = document.createElement('canvas');
  canvas.width = 640;
  canvas.height = 640;
  const side = Math.min(bitmap.width, bitmap.height);
  canvas
    .getContext('2d')
    .drawImage(
      bitmap,
      (bitmap.width - side) / 2,
      (bitmap.height - side) / 2,
      side,
      side,
      0,
      0,
      640,
      640
    );
  bitmap.close();
  return canvas.toDataURL('image/jpeg', 0.85).split(',')[1];
}
