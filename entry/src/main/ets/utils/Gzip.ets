/**
 * 纯 ArkTS 的 gzip 解压（RFC 1952 头 + RFC 1951 DEFLATE）。
 *
 * 为什么需要：官方 IM 端点回包无论客户端是否声明 Accept-Encoding 都带 gzip 位（flag & 0x40，
 * 见 tools/verify/probe-im-sync.ts），而 `@ohos.zlib` 只有文件级/低层流接口、没有内存 gzip 解压。
 * 支持 stored / 固定 Huffman / 动态 Huffman 与 gzip 可选头（FEXTRA/FNAME/FCOMMENT/FHCRC）；不校验 CRC32。
 * 输出超过 `MAX_OUTPUT` 抛错，避免畸形数据吃光内存。
 */

const MAX_OUTPUT: number = 8 * 1024 * 1024;

export class GzipError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'GzipError';
  }
}

/** 位读取器：DEFLATE 按 LSB-first 读位。 */
class BitReader {
  private data: Uint8Array;
  private bytePos: number = 0;
  private bitPos: number = 0;

  constructor(data: Uint8Array) {
    this.data = data;
  }

  /** 读 n 位（n <= 16），不足抛错。 */
  bits(n: number): number {
    let value: number = 0;
    for (let i = 0; i < n; i++) {
      if (this.bytePos >= this.data.length) {
        throw new GzipError('unexpected end of deflate stream');
      }
      const bit: number = (this.data[this.bytePos] >> this.bitPos) & 1;
      value |= bit << i;
      this.bitPos++;
      if (this.bitPos === 8) {
        this.bitPos = 0;
        this.bytePos++;
      }
    }
    return value;
  }

  /** 对齐到字节边界（stored 块前调用）。 */
  align(): void {
    if (this.bitPos !== 0) {
      this.bitPos = 0;
      this.bytePos++;
    }
  }

  readByte(): number {
    this.align();
    if (this.bytePos >= this.data.length) {
      throw new GzipError('unexpected end of stored block');
    }
    const value: number = this.data[this.bytePos];
    this.bytePos++;
    return value;
  }

  readUint16(): number {
    const low: number = this.readByte();
    const high: number = this.readByte();
    return low | (high << 8);
  }
}

/** 规范 Huffman 表：按码长计数 + 符号序列，解码时逐位累加。 */
class Huffman {
  counts: Int32Array = new Int32Array(16);
  symbols: Int32Array = new Int32Array(0);

  /** 由每个符号的码长构造（码长 0 表示不用）。 */
  static fromLengths(lengths: number[]): Huffman {
    const h: Huffman = new Huffman();
    for (let i = 0; i < lengths.length; i++) {
      if (lengths[i] > 0) { h.counts[lengths[i]]++; }
    }
    let total: number = 0;
    for (let len = 1; len < 16; len++) { total += h.counts[len]; }
    h.symbols = new Int32Array(total);
    const offsets: Int32Array = new Int32Array(16);
    let acc: number = 0;
    for (let len = 1; len < 16; len++) {
      offsets[len] = acc;
      acc += h.counts[len];
    }
    for (let symbol = 0; symbol < lengths.length; symbol++) {
      const len: number = lengths[symbol];
      if (len > 0) {
        h.symbols[offsets[len]] = symbol;
        offsets[len]++;
      }
    }
    return h;
  }

  /** 解码一个符号；遇到无效码抛错。 */
  decode(reader: BitReader): number {
    let code: number = 0;
    let first: number = 0;
    let index: number = 0;
    for (let len = 1; len < 16; len++) {
      code |= reader.bits(1);
      const count: number = this.counts[len];
      if (code - first < count) {
        return this.symbols[index + (code - first)];
      }
      index += count;
      first = (first + count) << 1;
      code <<= 1;
    }
    throw new GzipError('invalid huffman code');
  }
}

/** RFC 1951 §3.2.5 长度表（257..285）。 */
const LENGTH_BASE: number[] = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59,
  67, 83, 99, 115, 131, 163, 195, 227, 258];
const LENGTH_EXTRA: number[] = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4,
  5, 5, 5, 5, 0];
/** RFC 1951 §3.2.5 距离表（0..29）。 */
const DIST_BASE: number[] = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769,
  1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577];
const DIST_EXTRA: number[] = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10,
  11, 11, 12, 12, 13, 13];

class Output {
  private buffer: Uint8Array = new Uint8Array(4096);
  private length: number = 0;

  push(byte: number): void {
    if (this.length >= this.buffer.length) { this.grow(1); }
    this.buffer[this.length] = byte & 0xff;
    this.length++;
  }

  pushBytes(bytes: Uint8Array): void {
    if (this.length + bytes.length > this.buffer.length) { this.grow(bytes.length); }
    this.buffer.set(bytes, this.length);
    this.length += bytes.length;
  }

  copyBack(distance: number, count: number): void {
    if (distance <= 0 || distance > this.length) {
      throw new GzipError(`invalid back-reference distance ${distance}`);
    }
    if (this.length + count > this.buffer.length) { this.grow(count); }
    for (let i = 0; i < count; i++) {
      this.buffer[this.length] = this.buffer[this.length - distance];
      this.length++;
    }
  }

  private grow(extra: number): void {
    const wanted: number = this.length + extra;
    if (wanted > MAX_OUTPUT) { throw new GzipError('inflated output exceeds limit'); }
    let next: number = this.buffer.length * 2;
    while (next < wanted) { next *= 2; }
    const grown: Uint8Array = new Uint8Array(next);
    grown.set(this.buffer.subarray(0, this.length), 0);
    this.buffer = grown;
  }

  done(): Uint8Array {
    return this.buffer.slice(0, this.length);
  }
}

/** 跳过 gzip 头，返回 deflate 数据起点。 */
function deflateOffset(bytes: Uint8Array): number {
  if (bytes.length < 18 || bytes[0] !== 0x1f || bytes[1] !== 0x8b) {
    throw new GzipError('not a gzip stream');
  }
  if (bytes[2] !== 8) { throw new GzipError(`unsupported gzip method ${bytes[2]}`); }
  const flags: number = bytes[3];
  let pos: number = 10;
  if ((flags & 0x04) !== 0) { // FEXTRA
    if (pos + 2 > bytes.length) { throw new GzipError('truncated gzip extra'); }
    const xlen: number = bytes[pos] | (bytes[pos + 1] << 8);
    pos += 2 + xlen;
  }
  if ((flags & 0x08) !== 0) { // FNAME
    while (pos < bytes.length && bytes[pos] !== 0) { pos++; }
    pos++;
  }
  if ((flags & 0x10) !== 0) { // FCOMMENT
    while (pos < bytes.length && bytes[pos] !== 0) { pos++; }
    pos++;
  }
  if ((flags & 0x02) !== 0) { pos += 2; } // FHCRC
  if (pos >= bytes.length) { throw new GzipError('truncated gzip header'); }
  return pos;
}

function fixedTables(): Huffman[] {
  const litLengths: number[] = [];
  for (let i = 0; i < 288; i++) {
    if (i < 144) { litLengths.push(8); }
    else if (i < 256) { litLengths.push(9); }
    else if (i < 280) { litLengths.push(7); }
    else { litLengths.push(8); }
  }
  const distLengths: number[] = [];
  for (let i = 0; i < 30; i++) { distLengths.push(5); }
  return [Huffman.fromLengths(litLengths), Huffman.fromLengths(distLengths)];
}

function dynamicTables(reader: BitReader): Huffman[] {
  const hlit: number = reader.bits(5) + 257;
  const hdist: number = reader.bits(5) + 1;
  const hclen: number = reader.bits(4) + 4;
  const order: number[] = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15];
  const codeLengths: number[] = new Array<number>(19).fill(0);
  for (let i = 0; i < hclen; i++) {
    codeLengths[order[i]] = reader.bits(3);
  }
  const codeTree: Huffman = Huffman.fromLengths(codeLengths);
  const lengths: number[] = [];
  while (lengths.length < hlit + hdist) {
    const symbol: number = codeTree.decode(reader);
    if (symbol < 16) {
      lengths.push(symbol);
      continue;
    }
    if (symbol === 16) {
      if (lengths.length === 0) { throw new GzipError('repeat with no previous length'); }
      const previous: number = lengths[lengths.length - 1];
      const repeat: number = 3 + reader.bits(2);
      for (let i = 0; i < repeat; i++) { lengths.push(previous); }
      continue;
    }
    if (symbol === 17) {
      const repeat: number = 3 + reader.bits(3);
      for (let i = 0; i < repeat; i++) { lengths.push(0); }
      continue;
    }
    const repeat: number = 11 + reader.bits(7);
    for (let i = 0; i < repeat; i++) { lengths.push(0); }
  }
  if (lengths.length !== hlit + hdist) {
    throw new GzipError('code length overflow');
  }
  const litLengths: number[] = lengths.slice(0, hlit);
  const distLengths: number[] = lengths.slice(hlit);
  // 距离树可能只有 1 个码；补一个 0 长度符号避免空树
  while (distLengths.length < 2) { distLengths.push(0); }
  return [Huffman.fromLengths(litLengths), Huffman.fromLengths(distLengths)];
}

function inflateBlocks(reader: BitReader, out: Output): void {
  let final: boolean = false;
  while (!final) {
    final = reader.bits(1) === 1;
    const type: number = reader.bits(2);
    if (type === 0) {
      reader.align();
      const len: number = reader.readUint16();
      const nlen: number = reader.readUint16();
      if (((len ^ 0xffff) & 0xffff) !== nlen) { throw new GzipError('stored block length mismatch'); }
      for (let i = 0; i < len; i++) { out.push(reader.readByte()); }
      continue;
    }
    if (type === 3) { throw new GzipError('invalid block type 3'); }
    const tables: Huffman[] = type === 1 ? fixedTables() : dynamicTables(reader);
    const litTree: Huffman = tables[0];
    const distTree: Huffman = tables[1];
    while (true) {
      const symbol: number = litTree.decode(reader);
      if (symbol < 256) {
        out.push(symbol);
        continue;
      }
      if (symbol === 256) { break; }
      const lengthIndex: number = symbol - 257;
      if (lengthIndex < 0 || lengthIndex >= LENGTH_BASE.length) {
        throw new GzipError(`invalid length symbol ${symbol}`);
      }
      const length: number = LENGTH_BASE[lengthIndex] + reader.bits(LENGTH_EXTRA[lengthIndex]);
      const distSymbol: number = distTree.decode(reader);
      if (distSymbol < 0 || distSymbol >= DIST_BASE.length) {
        throw new GzipError(`invalid distance symbol ${distSymbol}`);
      }
      const distance: number = DIST_BASE[distSymbol] + reader.bits(DIST_EXTRA[distSymbol]);
      out.copyBack(distance, length);
    }
  }
}

export class Gzip {
  /** 解压 gzip 字节流；不修改入参。 */
  static inflate(bytes: Uint8Array): Uint8Array {
    const offset: number = deflateOffset(bytes);
    const reader: BitReader = new BitReader(bytes.subarray(offset));
    const out: Output = new Output();
    inflateBlocks(reader, out);
    return out.done();
  }
}
