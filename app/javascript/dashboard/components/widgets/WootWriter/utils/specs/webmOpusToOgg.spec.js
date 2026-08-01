import { remuxWebmToOgg } from '../webmOpusToOgg';

describe('remuxWebmToOgg', () => {
  const blobBytes = blob =>
    new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(new Uint8Array(reader.result));
      reader.onerror = reject;
      reader.readAsArrayBuffer(blob);
    });

  it('packages an Opus WebM block into an OGG/Opus stream', async () => {
    // Minimal EBML SimpleBlock: one track, zero timecode, no lacing, one
    // single-frame Opus packet. The remuxer only needs these fields.
    const input = Uint8Array.from([0xa3, 0x85, 0x81, 0x00, 0x00, 0x00, 0xf8]);
    const webm = {
      type: 'audio/webm',
      arrayBuffer: async () => input.buffer,
    };

    const ogg = await remuxWebmToOgg(webm);
    const bytes = await blobBytes(ogg);
    const text = new TextDecoder().decode(bytes);

    expect(ogg.type).toBe('audio/ogg');
    expect(text.startsWith('OggS')).toBe(true);
    expect(text).toContain('OpusHead');
    expect(text).toContain('OpusTags');
  });

  it('rejects recordings without Opus frames', async () => {
    const input = Uint8Array.from([0x1a, 0x45, 0xdf, 0xa3]);
    const invalidWebm = {
      type: 'audio/webm',
      arrayBuffer: async () => input.buffer,
    };

    await expect(remuxWebmToOgg(invalidWebm)).rejects.toThrow(
      'No Opus frames found'
    );
  });
});
