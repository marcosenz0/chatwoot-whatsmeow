export const stickerMeta = attachment => attachment?.meta || {};

export const isWhatsmeowSticker = attachment => {
  const meta = stickerMeta(attachment);
  return !!(meta.whatsmeowSticker || meta.whatsmeow_sticker);
};

export const stickerDataBase64 = sticker => {
  const meta = stickerMeta(sticker);
  return (
    sticker?.dataBase64 ||
    sticker?.data_base64 ||
    meta.dataBase64 ||
    meta.data_base64
  );
};

export const stickerContentType = sticker => {
  const meta = stickerMeta(sticker);
  return (
    sticker?.contentType ||
    sticker?.content_type ||
    meta.contentType ||
    meta.content_type ||
    'image/webp'
  );
};

export const stickerDataUrl = sticker => {
  const dataBase64 = stickerDataBase64(sticker);
  if (dataBase64) {
    return `data:${stickerContentType(sticker)};base64,${dataBase64}`;
  }

  return sticker?.dataUrl || sticker?.data_url || '';
};

export const stickerFullUrl = sticker =>
  stickerDataUrl(sticker) ||
  sticker?.downloadUrl ||
  sticker?.download_url ||
  sticker?.fileUrl ||
  sticker?.file_url ||
  '';

export const stickerPreviewUrl = sticker =>
  sticker?.previewUrl ||
  sticker?.preview_url ||
  sticker?.thumbUrl ||
  sticker?.thumb_url ||
  stickerFullUrl(sticker);

export const stickerAttachmentId = sticker =>
  sticker?.attachmentId || sticker?.attachment_id;
