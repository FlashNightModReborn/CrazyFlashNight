import type { PrimeMagicSeed } from "./types.js";

const HEADER_BYTES = 16;
const FORMAT_VERSION = 1;

export interface PrimeMagicSeedBankEntry {
  readonly index: number;
  readonly url: string;
  readonly binaryBytes: number;
  readonly binarySha256: string;
  readonly canonicalChecksum: string;
  readonly centerValue: number;
}

export interface PrimeMagicSeedBankManifest {
  readonly format: "prime-magic-runtime-bank/v1";
  readonly size: number;
  readonly magicSum: number;
  readonly seeds: readonly PrimeMagicSeedBankEntry[];
}

function normalizedSha256(value: string): string {
  const normalized = value.toLowerCase().replace(/^sha256:/, "");
  if (!/^[0-9a-f]{64}$/.test(normalized)) {
    throw new TypeError("expected a 64-hex SHA-256 digest");
  }
  return normalized;
}

function asByteView(data: ArrayBuffer | Uint8Array): Uint8Array {
  return data instanceof Uint8Array ? data : new Uint8Array(data);
}

/** Initialization-only PM19 decoder; all multibyte fields are little-endian. */
export function decodePrimeMagicBinary(
  data: ArrayBuffer | Uint8Array,
  canonicalChecksum: string,
): PrimeMagicSeed {
  const bytes = asByteView(data);
  if (bytes.byteLength < HEADER_BYTES) throw new RangeError("truncated PM19 header");
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (
    view.getUint8(0) !== 0x50 ||
    view.getUint8(1) !== 0x4d ||
    view.getUint8(2) !== 0x31 ||
    view.getUint8(3) !== 0x39
  ) {
    throw new TypeError("invalid PM19 binary magic");
  }
  const version = view.getUint16(4, true);
  if (version !== FORMAT_VERSION) throw new RangeError(`unsupported PM19 version ${version}`);
  const size = view.getUint16(6, true);
  if (size < 1) throw new RangeError("PM19 size must be positive");
  const magicSumBig = view.getBigUint64(8, true);
  if (magicSumBig > BigInt(Number.MAX_SAFE_INTEGER)) {
    throw new RangeError("PM19 magic sum exceeds Number.MAX_SAFE_INTEGER");
  }
  const cellCount = size * size;
  const expectedLength = HEADER_BYTES + cellCount * Uint32Array.BYTES_PER_ELEMENT;
  if (bytes.byteLength !== expectedLength) {
    throw new RangeError(`PM19 length ${bytes.byteLength} does not equal ${expectedLength}`);
  }

  const values = new Uint32Array(cellCount);
  let offset = HEADER_BYTES;
  for (let index = 0; index < cellCount; index += 1) {
    values[index] = view.getUint32(offset, true);
    offset += Uint32Array.BYTES_PER_ELEMENT;
  }

  return {
    size,
    magicSum: Number(magicSumBig),
    values,
    checksum: `sha256:${normalizedSha256(canonicalChecksum)}`,
  };
}

export async function sha256Hex(data: ArrayBuffer | Uint8Array): Promise<string> {
  if (globalThis.crypto?.subtle === undefined) {
    throw new Error("Web Crypto SHA-256 is unavailable");
  }
  const bytes = asByteView(data);
  // Copy a sliced view: SubtleCrypto's BufferSource typing excludes a generic
  // SharedArrayBuffer-backed view, and seed loading is not a hot path.
  const digestInput = new Uint8Array(bytes.byteLength);
  digestInput.set(bytes);
  const digest = new Uint8Array(await globalThis.crypto.subtle.digest("SHA-256", digestInput));
  let hex = "";
  for (let index = 0; index < digest.length; index += 1) {
    hex += digest[index]!.toString(16).padStart(2, "0");
  }
  return hex;
}

export async function loadPrimeMagicSeed(entry: PrimeMagicSeedBankEntry): Promise<PrimeMagicSeed> {
  const response = await fetch(entry.url, { cache: "force-cache" });
  if (!response.ok) throw new Error(`seed fetch failed: HTTP ${response.status}`);
  const data = await response.arrayBuffer();
  if (data.byteLength !== entry.binaryBytes) throw new RangeError("seed binary byte length mismatch");
  const digest = await sha256Hex(data);
  if (digest !== normalizedSha256(entry.binarySha256)) {
    throw new Error(`seed binary SHA-256 mismatch: expected ${entry.binarySha256}, got ${digest}`);
  }
  return decodePrimeMagicBinary(data, entry.canonicalChecksum);
}

export async function loadPrimeMagicSeedBank(
  manifestUrl: string,
): Promise<PrimeMagicSeedBankManifest> {
  const response = await fetch(manifestUrl, { cache: "force-cache" });
  if (!response.ok) throw new Error(`seed bank fetch failed: HTTP ${response.status}`);
  const manifest = await response.json() as PrimeMagicSeedBankManifest;
  if (
    manifest.format !== "prime-magic-runtime-bank/v1" ||
    !Number.isInteger(manifest.size) ||
    !Number.isSafeInteger(manifest.magicSum) ||
    !Array.isArray(manifest.seeds) ||
    manifest.seeds.length < 1
  ) {
    throw new TypeError("invalid prime-magic runtime seed bank manifest");
  }
  for (const entry of manifest.seeds) {
    if (
      !Number.isInteger(entry.index) ||
      typeof entry.url !== "string" ||
      entry.url.length === 0 ||
      !Number.isInteger(entry.binaryBytes) ||
      entry.binaryBytes < HEADER_BYTES ||
      !Number.isInteger(entry.centerValue) ||
      entry.centerValue < 0 ||
      entry.centerValue > 0xffff_ffff
    ) {
      throw new TypeError("invalid seed-bank entry");
    }
    normalizedSha256(entry.binarySha256);
    normalizedSha256(entry.canonicalChecksum);
  }
  return manifest;
}
