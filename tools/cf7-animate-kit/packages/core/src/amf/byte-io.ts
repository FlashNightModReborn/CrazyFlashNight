/** Big-endian byte reader over a Node Buffer with a moving cursor. */
export class ByteReader {
  pos = 0;
  constructor(private readonly buf: Buffer) {}

  get length(): number {
    return this.buf.length;
  }
  get eof(): boolean {
    return this.pos >= this.buf.length;
  }
  remaining(): number {
    return this.buf.length - this.pos;
  }

  private need(n: number): void {
    if (this.pos + n > this.buf.length) {
      throw new RangeError(
        `AMF0 read past end: need ${n} byte(s) at offset ${this.pos}, only ${this.remaining()} left`,
      );
    }
  }

  u8(): number {
    this.need(1);
    const v = this.buf.readUInt8(this.pos);
    this.pos += 1;
    return v;
  }
  u16(): number {
    this.need(2);
    const v = this.buf.readUInt16BE(this.pos);
    this.pos += 2;
    return v;
  }
  u32(): number {
    this.need(4);
    const v = this.buf.readUInt32BE(this.pos);
    this.pos += 4;
    return v;
  }
  i16(): number {
    this.need(2);
    const v = this.buf.readInt16BE(this.pos);
    this.pos += 2;
    return v;
  }
  double(): number {
    this.need(8);
    const v = this.buf.readDoubleBE(this.pos);
    this.pos += 8;
    return v;
  }
  /** Read `len` bytes as UTF-8. `len` is a byte count (handles multibyte names). */
  utf8(len: number): string {
    this.need(len);
    const v = this.buf.toString('utf8', this.pos, this.pos + len);
    this.pos += len;
    return v;
  }
  /** Read `len` raw bytes as a copy. */
  raw(len: number): Uint8Array {
    this.need(len);
    const v = Uint8Array.from(this.buf.subarray(this.pos, this.pos + len));
    this.pos += len;
    return v;
  }
}

/** Big-endian byte writer accumulating chunks. */
export class ByteWriter {
  private readonly chunks: Buffer[] = [];

  u8(v: number): this {
    this.chunks.push(Buffer.from([v & 0xff]));
    return this;
  }
  u16(v: number): this {
    const b = Buffer.allocUnsafe(2);
    b.writeUInt16BE(v & 0xffff, 0);
    this.chunks.push(b);
    return this;
  }
  u32(v: number): this {
    const b = Buffer.allocUnsafe(4);
    b.writeUInt32BE(v >>> 0, 0);
    this.chunks.push(b);
    return this;
  }
  i16(v: number): this {
    const b = Buffer.allocUnsafe(2);
    b.writeInt16BE(v, 0);
    this.chunks.push(b);
    return this;
  }
  double(v: number): this {
    const b = Buffer.allocUnsafe(8);
    b.writeDoubleBE(v, 0);
    this.chunks.push(b);
    return this;
  }
  utf8(s: string): this {
    this.chunks.push(Buffer.from(s, 'utf8'));
    return this;
  }
  raw(b: Uint8Array): this {
    this.chunks.push(Buffer.from(b));
    return this;
  }

  /** Number of bytes written so far. */
  get size(): number {
    let n = 0;
    for (const c of this.chunks) n += c.length;
    return n;
  }

  toBuffer(): Buffer {
    return Buffer.concat(this.chunks);
  }
}

/** UTF-8 byte length of a string (for choosing short vs long string markers / name lengths). */
export function utf8ByteLength(s: string): number {
  return Buffer.byteLength(s, 'utf8');
}
