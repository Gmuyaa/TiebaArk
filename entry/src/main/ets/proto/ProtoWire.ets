

import { decodeUtf8, encodeUtf8 } from '../utils/TextCodec';

export enum WireType {
  VARINT = 0,
  FIXED64 = 1,
  LENGTH_DELIMITED = 2,
  START_GROUP = 3,
  END_GROUP = 4,
  FIXED32 = 5
}

export class ProtoError extends Error {
  constructor(message: string) {
    super(message);
  }
}

const VARINT_MAX_BYTES: number = 10;

export class ProtoWriter {
  private buffer: Uint8Array = new Uint8Array(256);
  private pos: number = 0;

  get length(): number {
    return this.pos;
  }

  private ensureCapacity(extra: number): void {
    const required: number = this.pos + extra;
    if (required <= this.buffer.length) {
      return;
    }
    let next: number = this.buffer.length;
    while (next < required) {
      next = next * 2;
    }
    const grown: Uint8Array = new Uint8Array(next);
    grown.set(this.buffer.subarray(0, this.pos), 0);
    this.buffer = grown;
  }

  private putByte(value: number): void {
    this.ensureCapacity(1);
    this.buffer[this.pos] = value & 0xff;
    this.pos += 1;
  }

  writeTag(fieldNumber: number, wireType: WireType): void {
    this.writeUint64(BigInt(fieldNumber) * BigInt(8) + BigInt(wireType));
  }

  writeUint64(value: bigint): void {
    if (value < BigInt(0)) {
      throw new ProtoError('varint cannot encode a negative value; use writeSint64 for signed');
    }
    let remaining: bigint = value;
    const mask: bigint = BigInt(0x7f);
    const highBit: bigint = BigInt(0x80);
    const seven: bigint = BigInt(7);
    for (let i = 0; i < VARINT_MAX_BYTES; i++) {
      if (remaining < highBit) {
        this.putByte(Number(remaining));
        return;
      }
      this.putByte(Number((remaining & mask) | highBit));
      remaining = remaining >> seven;
    }
    throw new ProtoError('varint exceeds 10 bytes');
  }

  writeSint64(value: bigint): void {
    const zigzag: bigint = (value << BigInt(1)) ^ (value >> BigInt(63));
    this.writeUint64(zigzag);
  }

  writeInt32(fieldNumber: number, value: number): void {
    this.writeTag(fieldNumber, WireType.VARINT);
    const v: bigint = BigInt(value);
    if (v < BigInt(0)) {
      this.writeUint64(BigInt.asUintN(64, v));
    } else {
      this.writeUint64(v);
    }
  }

  writeInt64(fieldNumber: number, value: bigint): void {
    this.writeTag(fieldNumber, WireType.VARINT);
    if (value < BigInt(0)) {
      this.writeUint64(BigInt.asUintN(64, value));
    } else {
      this.writeUint64(value);
    }
  }

  writeBool(fieldNumber: number, value: boolean): void {
    this.writeInt32(fieldNumber, value ? 1 : 0);
  }

  writeString(fieldNumber: number, value: string): void {
    const bytes: Uint8Array = encodeUtf8(value);
    this.writeBytes(fieldNumber, bytes);
  }

  writeBytes(fieldNumber: number, value: Uint8Array): void {
    this.writeTag(fieldNumber, WireType.LENGTH_DELIMITED);
    this.writeUint64(BigInt(value.length));
    this.ensureCapacity(value.length);
    this.buffer.set(value, this.pos);
    this.pos += value.length;
  }

  writeMessage(fieldNumber: number, value: Uint8Array): void {
    this.writeBytes(fieldNumber, value);
  }

  writeFixed32(fieldNumber: number, value: number): void {
    this.writeTag(fieldNumber, WireType.FIXED32);
    this.ensureCapacity(4);
    const v: number = value >>> 0;
    this.buffer[this.pos] = v & 0xff;
    this.buffer[this.pos + 1] = (v >>> 8) & 0xff;
    this.buffer[this.pos + 2] = (v >>> 16) & 0xff;
    this.buffer[this.pos + 3] = (v >>> 24) & 0xff;
    this.pos += 4;
  }

  writeFixed64(fieldNumber: number, value: bigint): void {
    this.writeTag(fieldNumber, WireType.FIXED64);
    this.ensureCapacity(8);
    const v: bigint = BigInt.asUintN(64, value);
    const mask: bigint = BigInt(0xff);
    for (let i = 0; i < 8; i++) {
      this.buffer[this.pos + i] = Number((v >> BigInt(i * 8)) & mask);
    }
    this.pos += 8;
  }

  toUint8Array(): Uint8Array {
    return this.buffer.slice(0, this.pos);
  }
}

export class ProtoReader {
  private buf: Uint8Array;
  private pos: number = 0;
  private limit: number = 0;
  private lastWireType: WireType = WireType.VARINT;

  constructor(buffer: Uint8Array) {
    this.buf = buffer;
    this.limit = buffer.length;
  }

  static fromSlice(buffer: Uint8Array, start: number, length: number): ProtoReader {
    const sub: Uint8Array = buffer.subarray(start, start + length);
    return new ProtoReader(sub);
  }

  get position(): number {
    return this.pos;
  }

  get size(): number {
    return this.limit;
  }

  hasMore(): boolean {
    return this.pos < this.limit;
  }

  private require(count: number): void {
    if (this.pos + count > this.limit) {
      throw new ProtoError(`unexpected end of message: need ${count} byte(s) at offset ${this.pos}`);
    }
  }

  private readByte(): number {
    this.require(1);
    const b: number = this.buf[this.pos];
    this.pos += 1;
    return b;
  }

  readVarint(): bigint {
    let result: bigint = BigInt(0);
    let shift: bigint = BigInt(0);
    for (let i = 0; i < VARINT_MAX_BYTES; i++) {
      const b: number = this.readByte();
      result = result | (BigInt(b & 0x7f) << shift);
      if ((b & 0x80) === 0) {
        return result;
      }
      shift = shift + BigInt(7);
    }
    throw new ProtoError('varint exceeds 10 bytes');
  }

  readTag(): number {
    const tag: bigint = this.readVarint();
    const fieldNumber: number = Number(tag >> BigInt(3));
    if (fieldNumber <= 0) {
      throw new ProtoError(`invalid field number ${fieldNumber}`);
    }
    this.lastWireType = Number(tag & BigInt(7)) as WireType;
    return fieldNumber;
  }

  get wireType(): WireType {
    return this.lastWireType;
  }

  readInt32(): number {
    const v: bigint = this.readVarint();

    return Number(BigInt.asIntN(32, v));
  }

  readInt64(): bigint {
    return BigInt.asIntN(64, this.readVarint());
  }

  readUint64(): bigint {
    return this.readVarint();
  }

  readBool(): boolean {
    return this.readVarint() !== BigInt(0);
  }

  readSint64(): bigint {
    const v: bigint = this.readVarint();
    return (v >> BigInt(1)) ^ -(v & BigInt(1));
  }

  readFixed32(): number {
    this.require(4);
    const p: number = this.pos;
    this.pos += 4;
    return (this.buf[p] | (this.buf[p + 1] << 8) | (this.buf[p + 2] << 16)
      | (this.buf[p + 3] << 24)) >>> 0;
  }

  readFixed64(): bigint {
    this.require(8);
    const p: number = this.pos;
    let out: bigint = BigInt(0);
    for (let i = 7; i >= 0; i--) {
      out = (out << BigInt(8)) | BigInt(this.buf[p + i]);
    }
    this.pos += 8;
    return out;
  }

  readBytes(): Uint8Array {
    const len: number = Number(this.readVarint());
    if (len < 0) {
      throw new ProtoError(`negative length ${len}`);
    }
    this.require(len);
    const out: Uint8Array = this.buf.slice(this.pos, this.pos + len);
    this.pos += len;
    return out;
  }

  readMessageBytes(): Uint8Array {
    return this.readBytes();
  }

  readMessageView(): ProtoReader {
    const len: number = Number(this.readVarint());
    if (len < 0) {
      throw new ProtoError(`negative length ${len}`);
    }
    this.require(len);
    const view: ProtoReader = ProtoReader.fromSlice(this.buf, this.pos, len);
    this.pos += len;
    return view;
  }

  readString(): string {
    return decodeUtf8(this.readBytes());
  }

  skipField(): void {
    switch (this.lastWireType) {
      case WireType.VARINT:
        this.readVarint();
        break;
      case WireType.FIXED64:
        this.require(8);
        this.pos += 8;
        break;
      case WireType.LENGTH_DELIMITED:
        this.readBytes();
        break;
      case WireType.FIXED32:
        this.require(4);
        this.pos += 4;
        break;
      case WireType.START_GROUP:
      case WireType.END_GROUP:
        throw new ProtoError('group wire type is not supported by Tieba endpoints');
      default:
        throw new ProtoError(`cannot skip unknown wire type ${this.lastWireType}`);
    }
  }
}
