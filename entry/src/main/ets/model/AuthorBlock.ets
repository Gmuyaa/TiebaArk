import { ProtoReader, WireType } from '../proto/ProtoWire';

export class AuthorBlockResult {
  code: number = -1;
  message: string = '';
  hasPermissions: boolean = false;
  follow: number = 0;
  interact: number = 0;
  chat: number = 0;
  blocked(): boolean { return this.interact === 1; }
}

export function parseAuthorBlock(bytes: Uint8Array, read: boolean): AuthorBlockResult {
  const out: AuthorBlockResult = new AuthorBlockResult();
  try {
    const root: ProtoReader = new ProtoReader(bytes);
    while (root.hasMore()) {
      const field: number = root.readTag();
      if (field === 1 && root.wireType === WireType.LENGTH_DELIMITED) {
        const error: ProtoReader = root.readMessageView();
        while (error.hasMore()) {
          const tag: number = error.readTag();
          if (tag === 1 && error.wireType === WireType.VARINT) { out.code = error.readInt32(); }
          else if ((tag === 2 || tag === 3) && error.wireType === WireType.LENGTH_DELIMITED) {
            const message: string = error.readString();
            if (message.length > 0 && (tag === 3 || out.message.length === 0)) { out.message = message; }
          }
          else { error.skipField(); }
        }
      } else if (read && field === 2 && root.wireType === WireType.LENGTH_DELIMITED) {
        const data: ProtoReader = root.readMessageView();
        while (data.hasMore()) {
          const tag: number = data.readTag();
          if (tag === 2 && data.wireType === WireType.LENGTH_DELIMITED) {
            const permissions: ProtoReader = data.readMessageView();
            out.hasPermissions = true;
            while (permissions.hasMore()) {
              const key: number = permissions.readTag();
              if (key >= 1 && key <= 3 && permissions.wireType === WireType.VARINT) {
                const value: number = permissions.readInt32();
                if (value !== 0 && value !== 1) { return new AuthorBlockResult(); }
                if (key === 1) { out.follow = value; }
                else if (key === 2) { out.interact = value; }
                else { out.chat = value; }
              } else { permissions.skipField(); }
            }
          } else { data.skipField(); }
        }
      } else { root.skipField(); }
    }
    if (read && out.code === 0 && !out.hasPermissions) { out.code = -1; }
  } catch (err) { return new AuthorBlockResult(); }
  return out;
}
