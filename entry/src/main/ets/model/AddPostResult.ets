

import { ProtoReader } from '../proto/ProtoWire';

const RES_ERROR: number = 1;
const RES_DATA: number = 2;

const ERR_NO: number = 1;
const ERR_MSG: number = 2;

const DATA_TID: number = 2;
const DATA_PID: number = 3;

const ERR_UNKNOWN: number = -1;

export class AddPostResult {

  errorCode: number = ERR_UNKNOWN;
  errorMsg: string = '';

  tid: number = 0;

  pid: number = 0;

  accepted(): boolean {
    return this.errorCode === 0;
  }

  hasPostId(): boolean {
    return this.pid > 0;
  }

  static unknown(): AddPostResult {
    return new AddPostResult();
  }

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
