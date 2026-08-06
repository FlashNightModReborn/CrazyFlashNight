"use strict";

const zlib = require("zlib");
const { fail, sha256Bytes } = require("./common");

const PNG_SIGNATURE = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
const MINIMUM_WIDTH = 320;
const MINIMUM_HEIGHT = 180;
const MAXIMUM_DIMENSION = 8192;
const MAXIMUM_PIXELS = 32 * 1024 * 1024;
const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let index = 0; index < 256; index += 1) {
    let value = index;
    for (let bit = 0; bit < 8; bit += 1) {
      value = (value & 1) ? (0xEDB88320 ^ (value >>> 1)) : (value >>> 1);
    }
    table[index] = value >>> 0;
  }
  return table;
})();

function crc32(bytes) {
  let value = 0xFFFFFFFF;
  for (let index = 0; index < bytes.length; index += 1) {
    value = CRC_TABLE[(value ^ bytes[index]) & 0xFF] ^ (value >>> 8);
  }
  return (value ^ 0xFFFFFFFF) >>> 0;
}

function paeth(left, above, upperLeft) {
  const estimate = left + above - upperLeft;
  const leftDistance = Math.abs(estimate - left);
  const aboveDistance = Math.abs(estimate - above);
  const upperLeftDistance = Math.abs(estimate - upperLeft);
  if (leftDistance <= aboveDistance && leftDistance <= upperLeftDistance) return left;
  return aboveDistance <= upperLeftDistance ? above : upperLeft;
}

function decodePng(bytes, phase) {
  const label = phase || "capture_png";
  if (!Buffer.isBuffer(bytes) || bytes.length < 57 || bytes.length > 64 * 1024 * 1024
      || !bytes.subarray(0, PNG_SIGNATURE.length).equals(PNG_SIGNATURE)) {
    fail("capture_png_invalid", label, "capture is not one bounded PNG stream");
  }
  let offset = PNG_SIGNATURE.length;
  let ihdr = null;
  let sawIdat = false;
  let idatEnded = false;
  let sawIend = false;
  const idat = [];
  const chunkTypes = [];
  while (offset < bytes.length) {
    if (bytes.length - offset < 12) {
      fail("capture_png_truncated", label, "PNG chunk framing is truncated");
    }
    const length = bytes.readUInt32BE(offset);
    const type = bytes.toString("ascii", offset + 4, offset + 8);
    const dataStart = offset + 8;
    const dataEnd = dataStart + length;
    const crcOffset = dataEnd;
    if (!/^[A-Za-z]{4}$/.test(type) || dataEnd + 4 > bytes.length) {
      fail("capture_png_chunk_invalid", label, "PNG chunk type or length is invalid", { type, length });
    }
    const expectedCrc = bytes.readUInt32BE(crcOffset);
    const actualCrc = crc32(bytes.subarray(offset + 4, dataEnd));
    if (actualCrc !== expectedCrc) {
      fail("capture_png_crc_invalid", label, "PNG chunk CRC differs from its exact bytes", { type });
    }
    const data = bytes.subarray(dataStart, dataEnd);
    chunkTypes.push(type);
    if (type === "IHDR") {
      if (ihdr || chunkTypes.length !== 1 || length !== 13) {
        fail("capture_png_ihdr_invalid", label, "PNG requires one first 13-byte IHDR");
      }
      ihdr = {
        width: data.readUInt32BE(0), height: data.readUInt32BE(4),
        bitDepth: data[8], colorType: data[9], compression: data[10],
        filter: data[11], interlace: data[12],
      };
    } else if (type === "IDAT") {
      if (!ihdr || idatEnded || sawIend || length < 1) {
        fail("capture_png_idat_invalid", label, "PNG IDAT sequence is empty or non-contiguous");
      }
      sawIdat = true;
      idat.push(data);
    } else if (type === "IEND") {
      if (!sawIdat || sawIend || length !== 0) {
        fail("capture_png_iend_invalid", label, "PNG requires one zero-length IEND after IDAT");
      }
      sawIend = true;
      offset = dataEnd + 4;
      if (offset !== bytes.length) {
        fail("capture_png_trailing_bytes", label, "PNG contains bytes after the exact IEND");
      }
      break;
    } else {
      if (sawIdat) idatEnded = true;
      if ((type.charCodeAt(0) & 0x20) === 0 && type !== "PLTE") {
        fail("capture_png_critical_chunk_unknown", label,
          "PNG contains an unsupported critical chunk", { type });
      }
    }
    offset = dataEnd + 4;
  }
  if (!ihdr || !sawIdat || !sawIend || offset !== bytes.length) {
    fail("capture_png_structure_invalid", label, "PNG IHDR/IDAT/IEND closure is incomplete");
  }
  const channels = ihdr.colorType === 2 ? 3 : ihdr.colorType === 6 ? 4 : 0;
  const pixels = ihdr.width * ihdr.height;
  if (ihdr.width < MINIMUM_WIDTH || ihdr.height < MINIMUM_HEIGHT
      || ihdr.width > MAXIMUM_DIMENSION || ihdr.height > MAXIMUM_DIMENSION
      || !Number.isSafeInteger(pixels) || pixels > MAXIMUM_PIXELS
      || ihdr.bitDepth !== 8 || channels === 0 || ihdr.compression !== 0
      || ihdr.filter !== 0 || ihdr.interlace !== 0) {
    fail("capture_png_geometry_invalid", label,
      "PNG must be a visible-size non-interlaced 8-bit RGB/RGBA capture", ihdr);
  }
  const stride = ihdr.width * channels;
  const expectedInflatedBytes = ihdr.height * (stride + 1);
  const compressed = Buffer.concat(idat);
  let inflated;
  let bytesConsumed;
  try {
    const result = zlib.inflateSync(compressed, { info: true, maxOutputLength: expectedInflatedBytes });
    inflated = result.buffer;
    bytesConsumed = result.engine && result.engine.bytesWritten;
  } catch (error) {
    fail("capture_png_inflate_invalid", label, "PNG IDAT stream cannot be completely inflated", {
      message: error.message,
    });
  }
  if (!Buffer.isBuffer(inflated) || inflated.length !== expectedInflatedBytes
      || bytesConsumed !== compressed.length) {
    fail("capture_png_inflate_length_invalid", label,
      "PNG inflated bytes or compressed-stream consumption are not exact", {
        expectedInflatedBytes, actualInflatedBytes: inflated && inflated.length,
        compressedBytes: compressed.length, bytesConsumed,
      });
  }
  const decoded = Buffer.alloc(ihdr.height * stride);
  let sourceOffset = 0;
  for (let row = 0; row < ihdr.height; row += 1) {
    const filterType = inflated[sourceOffset++];
    if (filterType > 4) fail("capture_png_filter_invalid", label,
      "PNG scanline uses an unknown filter", { row, filterType });
    const rowOffset = row * stride;
    const priorOffset = rowOffset - stride;
    for (let column = 0; column < stride; column += 1) {
      const raw = inflated[sourceOffset++];
      const left = column >= channels ? decoded[rowOffset + column - channels] : 0;
      const above = row > 0 ? decoded[priorOffset + column] : 0;
      const upperLeft = row > 0 && column >= channels
        ? decoded[priorOffset + column - channels] : 0;
      let predictor = 0;
      if (filterType === 1) predictor = left;
      else if (filterType === 2) predictor = above;
      else if (filterType === 3) predictor = Math.floor((left + above) / 2);
      else if (filterType === 4) predictor = paeth(left, above, upperLeft);
      decoded[rowOffset + column] = (raw + predictor) & 0xFF;
    }
  }
  return { width: ihdr.width, height: ihdr.height, bitDepth: ihdr.bitDepth,
    colorType: ihdr.colorType, channels, interlace: ihdr.interlace, pixels,
    compressedBytes: compressed.length, decodedBytes: decoded.length,
    pixelSha256: sha256Bytes(decoded), chunkTypes };
}

function pngChunk(type, data) {
  const typeBytes = Buffer.from(type, "ascii");
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length, 0);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([typeBytes, data])), 0);
  return Buffer.concat([length, typeBytes, data, crc]);
}

function createSolidPngForFixture(width, height, rgba) {
  if (!Number.isInteger(width) || !Number.isInteger(height)
      || !Array.isArray(rgba) || rgba.length !== 4
      || rgba.some((value) => !Number.isInteger(value) || value < 0 || value > 255)) {
    fail("fixture_png_input_invalid", "fixture", "solid fixture PNG input is malformed");
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  const row = Buffer.alloc(1 + width * 4);
  row[0] = 0;
  for (let column = 0; column < width; column += 1) {
    for (let channel = 0; channel < 4; channel += 1) row[1 + column * 4 + channel] = rgba[channel];
  }
  const raw = Buffer.concat(Array.from({ length: height }, () => row));
  const bytes = Buffer.concat([PNG_SIGNATURE, pngChunk("IHDR", ihdr),
    pngChunk("IDAT", zlib.deflateSync(raw)), pngChunk("IEND", Buffer.alloc(0))]);
  decodePng(bytes, "fixture_png");
  return bytes;
}

module.exports = {
  MAXIMUM_DIMENSION,
  MAXIMUM_PIXELS,
  MINIMUM_HEIGHT,
  MINIMUM_WIDTH,
  createSolidPngForFixture,
  decodePng,
};
