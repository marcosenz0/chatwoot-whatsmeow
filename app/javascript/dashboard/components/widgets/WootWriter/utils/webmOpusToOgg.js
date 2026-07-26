/* eslint-disable no-bitwise */
/**
 * Remuxes the WebM/Opus container produced by Chromium into OGG/Opus.
 * WhatsApp Cloud API accepts a native voice note only when the audio is
 * Opus inside an OGG container.
 */

const EBML_IDS = {
  Segment: 0x18538067,
  SegmentInfo: 0x1549a966,
  Tracks: 0x1654ae6b,
  TrackEntry: 0xae,
  CodecPrivate: 0x63a2,
  Audio: 0xe1,
  SamplingFrequency: 0xb5,
  Channels: 0x9f,
  Cluster: 0x1f43b675,
  SimpleBlock: 0xa3,
  BlockGroup: 0xa0,
  Block: 0xa1,
};

const MASTER_ELEMENTS = new Set([
  0x1a45dfa3,
  EBML_IDS.Segment,
  EBML_IDS.SegmentInfo,
  EBML_IDS.Tracks,
  EBML_IDS.TrackEntry,
  EBML_IDS.Audio,
  EBML_IDS.Cluster,
  EBML_IDS.BlockGroup,
]);

function readVint(data, pos) {
  if (pos >= data.length || data[pos] === 0) return null;
  const first = data[pos];
  let length = 1;
  let mask = 0x80;
  while (length <= 8 && !(first & mask)) {
    length += 1;
    mask >>= 1;
  }
  if (length > 8 || pos + length > data.length) return null;

  let value = first & (mask - 1);
  for (let index = 1; index < length; index += 1) {
    value = value * 256 + data[pos + index];
  }
  return { value, length };
}

function readElementId(data, pos) {
  if (pos >= data.length || data[pos] === 0) return null;
  const first = data[pos];
  let length = 1;
  let mask = 0x80;
  while (length <= 4 && !(first & mask)) {
    length += 1;
    mask >>= 1;
  }
  if (length > 4 || pos + length > data.length) return null;

  let id = first;
  for (let index = 1; index < length; index += 1) {
    id = id * 256 + data[pos + index];
  }
  return { id, length };
}

function readUintBE(data, offset, length) {
  let value = 0;
  for (let index = 0; index < length; index += 1) {
    value = value * 256 + data[offset + index];
  }
  return value;
}

function readFloatBE(data, offset, length) {
  if (length !== 4 && length !== 8) return NaN;
  const buffer = new ArrayBuffer(length);
  const bytes = new Uint8Array(buffer);
  for (let index = 0; index < length; index += 1) {
    bytes[index] = data[offset + index];
  }
  const view = new DataView(buffer);
  return length === 4 ? view.getFloat32(0) : view.getFloat64(0);
}

function extractFrameFromBlock(data, offset, end) {
  const track = readVint(data, offset);
  if (!track) return null;

  let pos = offset + track.length + 2;
  const flags = data[pos];
  const lacingBits = (flags >> 1) & 0x03;
  if (lacingBits !== 0) {
    throw new Error('Laced WebM audio blocks are not supported');
  }
  pos += 1;
  return pos < end ? data.slice(pos, end) : null;
}

function parseWebM(buffer) {
  const data = new Uint8Array(buffer);
  const result = {
    channels: 1,
    sampleRate: 48000,
    codecPrivate: null,
    frames: [],
  };

  function walk(start, end) {
    let pos = start;
    while (pos < end) {
      const idResult = readElementId(data, pos);
      if (!idResult) break;
      pos += idResult.length;

      const sizeResult = readVint(data, pos);
      if (!sizeResult) break;
      pos += sizeResult.length;

      const maxVint = 2 ** (7 * sizeResult.length) - 1;
      const elementEnd =
        sizeResult.value === maxVint
          ? end
          : Math.min(pos + sizeResult.value, end);

      if (MASTER_ELEMENTS.has(idResult.id)) {
        walk(pos, elementEnd);
      } else {
        switch (idResult.id) {
          case EBML_IDS.Channels:
            result.channels = readUintBE(data, pos, sizeResult.value);
            break;
          case EBML_IDS.SamplingFrequency:
            result.sampleRate = readFloatBE(data, pos, sizeResult.value);
            break;
          case EBML_IDS.CodecPrivate:
            result.codecPrivate = data.slice(pos, elementEnd);
            break;
          case EBML_IDS.SimpleBlock:
          case EBML_IDS.Block: {
            const frame = extractFrameFromBlock(data, pos, elementEnd);
            if (frame?.length) result.frames.push(frame);
            break;
          }
          default:
            break;
        }
      }
      pos = elementEnd;
    }
  }

  walk(0, data.length);
  return result;
}

const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let index = 0; index < 256; index += 1) {
    let crc = index << 24;
    for (let bit = 0; bit < 8; bit += 1) {
      crc = ((crc << 1) ^ (crc & 0x80000000 ? 0x04c11db7 : 0)) >>> 0;
    }
    table[index] = crc;
  }
  return table;
})();

function oggCrc32(bytes) {
  let crc = 0;
  for (let index = 0; index < bytes.length; index += 1) {
    crc = (CRC_TABLE[((crc >>> 24) ^ bytes[index]) & 0xff] ^ (crc << 8)) >>> 0;
  }
  return crc;
}

function createOggPage(
  headerType,
  granulePosition,
  serialNumber,
  pageSequence,
  packets
) {
  const segmentTable = [];
  let dataLength = 0;
  packets.forEach(packet => {
    let remaining = packet.length;
    while (remaining >= 255) {
      segmentTable.push(255);
      remaining -= 255;
    }
    segmentTable.push(remaining);
    dataLength += packet.length;
  });

  const headerLength = 27 + segmentTable.length;
  const page = new Uint8Array(headerLength + dataLength);
  const view = new DataView(page.buffer);
  page.set([0x4f, 0x67, 0x67, 0x53]);
  page[4] = 0;
  page[5] = headerType;
  view.setUint32(6, granulePosition & 0xffffffff, true);
  view.setUint32(
    10,
    Math.floor(granulePosition / 0x100000000) & 0xffffffff,
    true
  );
  view.setUint32(14, serialNumber, true);
  view.setUint32(18, pageSequence, true);
  view.setUint32(22, 0, true);
  page[26] = segmentTable.length;
  segmentTable.forEach((segment, index) => {
    page[27 + index] = segment;
  });

  let offset = headerLength;
  packets.forEach(packet => {
    page.set(packet, offset);
    offset += packet.length;
  });
  view.setUint32(22, oggCrc32(page), true);
  return page;
}

const OPUS_FRAME_MS = [
  10, 20, 40, 60, 10, 20, 40, 60, 10, 20, 40, 60, 10, 20, 10, 20, 2.5, 5, 10,
  20, 2.5, 5, 10, 20, 2.5, 5, 10, 20, 2.5, 5, 10, 20,
];

function opusPacketSamples(packet) {
  if (!packet?.length) return 960;
  const tableOfContents = packet[0];
  const config = (tableOfContents >> 3) & 0x1f;
  const code = tableOfContents & 0x03;
  const samplesPerFrame = ((OPUS_FRAME_MS[config] || 20) * 48000) / 1000;
  let frameCount;
  if (code <= 1) frameCount = code + 1;
  else if (code === 2) frameCount = 2;
  else frameCount = packet.length >= 2 ? packet[1] & 0x3f : 1;
  return samplesPerFrame * frameCount;
}

function buildOpusHead(channels, sampleRate, preSkip) {
  const buffer = new Uint8Array(19);
  const view = new DataView(buffer.buffer);
  buffer.set(new TextEncoder().encode('OpusHead'));
  buffer[8] = 1;
  buffer[9] = channels;
  view.setUint16(10, preSkip, true);
  view.setUint32(12, sampleRate, true);
  view.setInt16(16, 0, true);
  buffer[18] = 0;
  return buffer;
}

function buildOpusTags() {
  const vendor = new TextEncoder().encode('chatwoot');
  const buffer = new Uint8Array(8 + 4 + vendor.length + 4);
  const view = new DataView(buffer.buffer);
  buffer.set(new TextEncoder().encode('OpusTags'));
  view.setUint32(8, vendor.length, true);
  buffer.set(vendor, 12);
  view.setUint32(12 + vendor.length, 0, true);
  return buffer;
}

const MAX_FRAMES_PER_PAGE = 50;
const MAX_SEGMENTS_PER_PAGE = 255;

export async function remuxWebmToOgg(webmBlob) {
  const arrayBuffer = await webmBlob.arrayBuffer();
  const bytes = new Uint8Array(arrayBuffer);
  const alreadyOgg =
    bytes.length >= 4 &&
    bytes[0] === 0x4f &&
    bytes[1] === 0x67 &&
    bytes[2] === 0x67 &&
    bytes[3] === 0x53;
  if (alreadyOgg) return new Blob([bytes], { type: 'audio/ogg' });

  const { channels, sampleRate, codecPrivate, frames } = parseWebM(arrayBuffer);
  if (frames.length === 0) {
    throw new Error('No Opus frames found in the browser recording');
  }

  let preSkip = 312;
  if (codecPrivate?.length >= 12) {
    const magic = new TextDecoder().decode(codecPrivate.slice(0, 8));
    if (magic === 'OpusHead') {
      preSkip = new DataView(
        codecPrivate.buffer,
        codecPrivate.byteOffset,
        codecPrivate.length
      ).getUint16(10, true);
    }
  }

  const serial = (Math.random() * 0x100000000) >>> 0;
  const pages = [];
  let pageSequence = 0;
  pages.push(
    createOggPage(0x02, 0, serial, pageSequence, [
      buildOpusHead(channels, sampleRate, preSkip),
    ])
  );
  pageSequence += 1;
  pages.push(createOggPage(0x00, 0, serial, pageSequence, [buildOpusTags()]));
  pageSequence += 1;

  let granule = 0;
  let frameIndex = 0;
  while (frameIndex < frames.length) {
    const packets = [];
    let segmentCount = 0;
    while (frameIndex < frames.length && packets.length < MAX_FRAMES_PER_PAGE) {
      const packet = frames[frameIndex];
      const packetSegments = Math.floor(packet.length / 255) + 1;
      if (
        segmentCount + packetSegments > MAX_SEGMENTS_PER_PAGE &&
        packets.length > 0
      ) {
        break;
      }
      packets.push(packet);
      segmentCount += packetSegments;
      granule += opusPacketSamples(packet);
      frameIndex += 1;
    }
    const isLast = frameIndex >= frames.length;
    pages.push(
      createOggPage(
        isLast ? 0x04 : 0x00,
        granule,
        serial,
        pageSequence,
        packets
      )
    );
    pageSequence += 1;
  }

  const totalLength = pages.reduce((total, page) => total + page.length, 0);
  const output = new Uint8Array(totalLength);
  let offset = 0;
  pages.forEach(page => {
    output.set(page, offset);
    offset += page.length;
  });
  return new Blob([output], { type: 'audio/ogg' });
}
