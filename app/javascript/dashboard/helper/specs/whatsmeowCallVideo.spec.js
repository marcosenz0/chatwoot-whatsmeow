import { drawCallVideoFrame, isH264KeyFrame } from '../whatsmeowCallVideo';

describe('Whatsmeow call video', () => {
  it('requires an IDR picture, rather than an SPS, to restart decoding', () => {
    expect(isH264KeyFrame(new Uint8Array([0, 0, 1, 0x67]))).toBe(false);
    expect(isH264KeyFrame(new Uint8Array([0, 0, 1, 0x65]))).toBe(true);
    expect(isH264KeyFrame(new Uint8Array([0, 0, 0, 1, 0x65]))).toBe(true);
    expect(isH264KeyFrame(new Uint8Array([0, 0, 0, 1, 0x41]))).toBe(false);
  });

  it.each([0, 1, 2, 3])(
    'renders quarter turn %i with the correct aspect ratio',
    orientation => {
      const context = {
        setTransform: vi.fn(),
        rotate: vi.fn(),
        drawImage: vi.fn(),
      };
      const canvas = { width: 640, height: 480, getContext: () => context };
      const frame = { displayWidth: 640, displayHeight: 480 };
      drawCallVideoFrame(canvas, frame, orientation);
      expect([canvas.width, canvas.height]).toEqual(
        orientation % 2 ? [480, 640] : [640, 480]
      );
      expect(context.setTransform).toHaveBeenCalledWith(
        1,
        0,
        0,
        1,
        canvas.width / 2,
        canvas.height / 2
      );
      expect(context.rotate).toHaveBeenCalledWith((orientation * Math.PI) / 2);
      expect(context.drawImage).toHaveBeenCalledWith(
        frame,
        -320,
        -240,
        640,
        480
      );
    }
  );
});
