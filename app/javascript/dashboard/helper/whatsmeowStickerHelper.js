export const stickerMeta = attachment => attachment?.meta || {};

export const isWhatsmeowSticker = attachment => {
  const meta = stickerMeta(attachment);
  return !!(meta.whatsmeowSticker || meta.whatsmeow_sticker);
};

export const stickerDataUrl = sticker => sticker?.dataUrl || sticker?.data_url;

export const stickerAttachmentId = sticker =>
  sticker?.attachmentId || sticker?.attachment_id;
