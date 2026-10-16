/**
 * 贴吧 Protobuf wire format 读写原语。
 *
 * 为什么手写而不用现成库：
 * - ArkTS 无反射，protobuf 官方运行时与 Wire 类代码生成方案在此不可用
 * - 贴吧接口只用到 wire format 的一个子集，手写可精确控制且便于用真实样本回归
 *
 * 设计约定：
 * - 只有本文件触碰字节级读写，上层 Proto 类只声明字段编号并调用这里的方法
 * - 所有越界与非法编码统一抛 ProtoError，由协议层转为业务错误，不向上冒泡崩溃
 * - 读取端不做字段名推断；字段编号的具体依据由上层模型与参数类记录。
 *   已复核部分使用固定基准客户端的反编译 wire 类（`@ProtoField(tag = N)`，
 *   基准包 22.11.1.0）；开源参考与尚待补证部分见 `THIRD_PARTY_NOTICES.md`。
 */

import { decodeUtf8, encodeUtf8 } from '../utils/TextCodec';

/** Protobuf 的 wire type。贴吧接口实际只用到 0/1/2/5。 */
export enum WireType {
  VARINT = 0,
  FIXED64 = 1,
  LENGTH_DELIMITED = 2,
  START_GROUP = 3,
  END_GROUP = 4,
  FIXED32 = 5
}

/** 协议层解码异常。上层必须捕获并转为可理解的业务错误。 */
export class ProtoError extends Error {
  constructor(message: string) {
    super(message);
  }
}

const VARINT_MAX_BYTES: number = 10;

/**
 * 写入端。按字段逐个 append，最后 toUint8Array() 取结果。
 * 内部缓冲按需倍增，避免每次写入都重新分配。
 */
export class ProtoWriter {
  private buffer: Uint8Array = new Uint8Array(256);
  private pos: number = 0;

  /** 当前已写入的字节数 */
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

  /** 写入 tag：field_number 左移 3 位后与 wire type 做或运算 */
  writeTag(fieldNumber: number, wireType: WireType): void {
    this.writeUint64(BigInt(fieldNumber) * BigInt(8) + BigInt(wireType));
  }

  /** varint 编码，最多 10 字节 */
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

  /** zigzag 编码，用于 sint32/sint64 */
  writeSint64(value: bigint): void {
    const zigzag: bigint = (value << BigInt(1)) ^ (value >> BigInt(63));
    this.writeUint64(zigzag);
  }

  /** int32 字段：负数按补码写满 10 字节，与 protobuf 规范一致 */
  writeInt32(fieldNumber: number, value: number): void {
    this.writeTag(fieldNumber, WireType.VARINT);
    const v: bigint = BigInt(value);
    if (v < BigInt(0)) {
      this.writeUint64(BigInt.asUintN(64, v));
    } else {
      this.writeUint64(v);
    }
  }

  /** int64 字段 */
  writeInt64(fieldNumber: number, value: bigint): void {
    this.writeTag(fieldNumber, WireType.VARINT);
    if (value < BigInt(0)) {
      this.writeUint64(BigInt.asUintN(64, value));
    } else {
      this.writeUint64(value);
    }
  }

  /** bool 字段 */
  writeBool(fieldNumber: number, value: boolean): void {
    this.writeInt32(fieldNumber, value ? 1 : 0);
  }

  /** string 字段，UTF-8 编码后按 length-delimited 写入 */
  writeString(fieldNumber: number, value: string): void {
    const bytes: Uint8Array = encodeUtf8(value);
    this.writeBytes(fieldNumber, bytes);
  }

  /** bytes 字段 */
  writeBytes(fieldNumber: number, value: Uint8Array): void {
    this.writeTag(fieldNumber, WireType.LENGTH_DELIMITED);
    this.writeUint64(BigInt(value.length));
    this.ensureCapacity(value.length);
    this.buffer.set(value, this.pos);
    this.pos += value.length;
  }

  /** 嵌套消息字段：先写入已序列化的子消息 */
  writeMessage(fieldNumber: number, value: Uint8Array): void {
    this.writeBytes(fieldNumber, value);
  }

  /**
   * fixed32 字段：定长 4 字节，小端序。
   * 与 skipField 的 FIXED32 分支对称——读端能跳过，写端就必须能写出。
   */
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

  /** fixed64 字段：定长 8 字节，小端序 */
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

  /** 取出完整结果。返回副本，避免后续写入影响已取出的数据。 */
  toUint8Array(): Uint8Array {
    return this.buffer.slice(0, this.pos);
  }
}

/**
 * 读取端。构造时给定完整响应体，按字段推进。
 *
 * 使用方式：
 *   const reader = new ProtoReader(bytes);
 *   while (reader.hasMore()) {
 *     const field = reader.readTag();
 *     switch (field) { ... }
 *   }
 */
export class ProtoReader {
  private buf: Uint8Array;
  private pos: number = 0;
  private limit: number = 0;
  private lastWireType: WireType = WireType.VARINT;

  constructor(buffer: Uint8Array) {
    this.buf = buffer;
    this.limit = buffer.length;
  }

  /** 以子视图构造，用于解析嵌套消息而不复制字节 */
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

  /** 读取 varint，返回 bigint 以免丢失 int64 精度 */
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

  /** 读取 tag，记录 wire type，返回字段编号 */
  readTag(): number {
    const tag: bigint = this.readVarint();
    const fieldNumber: number = Number(tag >> BigInt(3));
    if (fieldNumber <= 0) {
      throw new ProtoError(`invalid field number ${fieldNumber}`);
    }
    this.lastWireType = Number(tag & BigInt(7)) as WireType;
    return fieldNumber;
  }

  /** 上一步 readTag 得到的 wire type */
  get wireType(): WireType {
    return this.lastWireType;
  }

  readInt32(): number {
    const v: bigint = this.readVarint();
    // 负数会被编码为 10 字节的补码形式，取低 32 位还原
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

  /** fixed32 字段：定长 4 字节，小端序，按无符号数返回 */
  readFixed32(): number {
    this.require(4);
    const p: number = this.pos;
    this.pos += 4;
    return (this.buf[p] | (this.buf[p + 1] << 8) | (this.buf[p + 2] << 16)
      | (this.buf[p + 3] << 24)) >>> 0;
  }

  /** fixed64 字段：定长 8 字节，小端序，用 bigint 保精度 */
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

  /** 读取 length-delimited 的原始字节 */
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

  /** 读取嵌套消息，返回其原始字节，交由对应的 Proto 类再解析 */
  readMessageBytes(): Uint8Array {
    return this.readBytes();
  }

  /**
   * 读取嵌套消息并返回一个零拷贝的子读取器——解析嵌套消息的推荐入口。
   *
   * 必须用这个方法而不是自己算偏移：readTag() 之后的 position 指向的是
   * 长度前缀，直接 fromSlice(position, len) 会从长度字节本身开始解析，
   * 导致整个子消息错位。fromSlice 只适合调用方已确知载荷起点的场景。
   */
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

  /** 读取 string */
  readString(): string {
    return decodeUtf8(this.readBytes());
  }

  /** 跳过当前字段。遇到未知字段编号时必须调用，否则会读串位。 */
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
