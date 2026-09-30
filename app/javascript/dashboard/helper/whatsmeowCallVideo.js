export const isH264KeyFrame = bytes => {
  for (let i = 0; i + 3 < bytes.length; i += 1) {
    let offset = -1;
    if (bytes[i] === 0 && bytes[i + 1] === 0 && bytes[i + 2] === 1) {
      offset = i + 3;
    } else if (
      bytes[i] === 0 &&
      bytes[i + 1] === 0 &&
      bytes[i + 2] === 0 &&
      bytes[i + 3] === 1
    ) {
      offset = i + 4;
    }
    // SPS describes the stream; only an IDR picture can restart the decoder.
    if (offset >= 0 && bytes[offset] % 32 === 5) return true;
  }
  return false;
};

export const drawCallVideoFrame = (canvas, frame, orientation) => {
  const width = frame.displayWidth;
  const height = frame.displayHeight;
  const quarterTurns = orientation % 4;
  const rotated = quarterTurns % 2 === 1;
  const outputWidth = rotated ? height : width;
  const outputHeight = rotated ? width : height;
  // Changing the backing size every frame resets the drawing context unnecessarily.
  if (canvas.width !== outputWidth) canvas.width = outputWidth;
  if (canvas.height !== outputHeight) canvas.height = outputHeight;
  const context = canvas.getContext('2d');
  context.setTransform(1, 0, 0, 1, outputWidth / 2, outputHeight / 2);
  context.rotate((quarterTurns * Math.PI) / 2);
  context.drawImage(frame, -width / 2, -height / 2, width, height);
};
