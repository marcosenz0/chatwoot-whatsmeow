export const attachmentFileName = attachment => {
  const url = attachment.data_url || attachment.dataUrl || '';
  const name = url.split(/[?#]/)[0].split('/').pop();
  return name ? decodeURIComponent(name) : '';
};

export const isPdfAttachment = attachment => {
  const contentType = attachment.content_type || attachment.contentType;
  return (
    contentType === 'application/pdf' ||
    attachment.extension?.toLowerCase() === 'pdf' ||
    /\.pdf$/i.test(attachmentFileName(attachment))
  );
};
