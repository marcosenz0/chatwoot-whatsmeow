// Crop coordinates use the source image's pixels. The viewport always remains covered.
export const clampCrop = ({ width, height, zoom, x, y }) => {
  const side = Math.min(width, height) / zoom;
  return {
    side,
    x: Math.max(side / 2, Math.min(width - side / 2, x)),
    y: Math.max(side / 2, Math.min(height - side / 2, y)),
  };
};

export const cropToJpeg = (image, crop, size = 640) => {
  const canvas = document.createElement('canvas');
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext('2d');
  ctx.fillStyle = '#ffffff';
  ctx.fillRect(0, 0, size, size);
  ctx.drawImage(
    image,
    crop.x - crop.side / 2,
    crop.y - crop.side / 2,
    crop.side,
    crop.side,
    0,
    0,
    size,
    size
  );
  return canvas.toDataURL('image/jpeg', 0.9).split(',')[1];
};
