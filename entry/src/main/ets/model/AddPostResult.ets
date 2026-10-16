

import { ProtoReader } from '../proto/ProtoWire';

const RES_ERROR: number = 1;
const RES_DATA: number = 2;

const ERR_NO: number = 1;
const ERR_MSG: number = 2;

const DATA_TID: number = 2;
const DATA_PID: number = 3;

/** 没解析出 error 段时的哨兵值 —— **不能当成功**（缺少 errno 视为未知） */
const ERR_UNKNOWN: number = -1;

export class AddPostResult {
  /**
   * 服务端错误码。`-1` 表示**响应里没有 error 段**（异常 body / 空响应），
   * 调用方必须当成失败，不能因为"不是正数"就放行。
   */
  errorCode: number = ERR_UNKNOWN;
  errorMsg: string = '';
  /** 服务端给的帖子 id（发一级评论时回显 tid） */
  tid: number = 0;
  /** 服务端给的新楼层 pid（这是后续"读回核对"的钥匙） */
  pid: number = 0;

  /** 只有当 error 段存在且 errorno 为 0 时才算"服务端受理" */
  accepted(): boolean {
    return this.errorCode === 0;
  }

  /** 无论受理与否，pid > 0 都说明服务端口头给了楼层号 */
  hasPostId(): boolean {
    return this.pid > 0;
  }

  static unknown(): AddPostResult {
    return new AddPostResult();
  }

  /**
   * 解析响应字节。
   *
   * 空 / 畸形字节**安静返回**（`errorCode` 保持 `-1`），不抛异常：
   * 这个端点是写操作，解析炸会把"已发出"的事实掩盖掉，宁可上面看到 `-1`。
   */
  static fromBytes(bytes: Uint8Array): AddPostResult {
    const out: AddPostResult = new AddPostResult();
    if (bytes.length === 0) {
      return out;
    }
    const reader: ProtoReader = new ProtoReader(bytes);
    while (reader.hasMore()) {
      const field: number = reader.readTag();
      if (field === RES_ERROR) {
        AddPostResult.readError(reader.readMessageView(), out);
      } else if (field === RES_DATA) {
        AddPostResult.readData(reader.readMessageView(), out);
      } else {
        reader.skipField();
      }
    }
    return out;
  }

  private static readError(view: ProtoReader, out: AddPostResult): void {
    while (view.hasMore()) {
      const field: number = view.readTag();
      if (field === ERR_NO) {
        out.errorCode = view.readInt32();
      } else if (field === ERR_MSG) {
        out.errorMsg = view.readString();
      } else {
        view.skipField();
      }
    }
  }

  private static readData(view: ProtoReader, out: AddPostResult): void {
    while (view.hasMore()) {
      const field: number = view.readTag();
      if (field === DATA_TID) {
        out.tid = AddPostResult.toNumber(view);
      } else if (field === DATA_PID) {
        out.pid = AddPostResult.toNumber(view);
      } else {
        view.skipField();
      }
    }
  }

  /** tid/pid 兼容 varint 与字符串；varint 按 64 位读取，避免 int32 截断。 */
  private static toNumber(view: ProtoReader): number {
    if (view.wireType === 0) {
      return Number(view.readInt64());
    }
    if (view.wireType === 2) {
      const raw: string = view.readString();
      const parsed: number = Number.parseInt(raw, 10);
      return Number.isNaN(parsed) ? 0 : parsed;
    }
    view.skipField();
    return 0;
  }
}
