import { ProtoReader, WireType } from '../proto/ProtoWire';

export class AuthorBlockScope {
  follow: boolean = false;
  interact: boolean = false;
  chat: boolean = false;

  static all(): AuthorBlockScope {
    const scope: AuthorBlockScope = new AuthorBlockScope();
    scope.follow = true;
    scope.interact = true;
    scope.chat = true;
    return scope;
  }

  static none(): AuthorBlockScope {
    return new AuthorBlockScope();
  }

  static fromFlags(follow: boolean, interact: boolean, chat: boolean): AuthorBlockScope {
    const scope: AuthorBlockScope = new AuthorBlockScope();
    scope.follow = follow;
    scope.interact = interact;
    scope.chat = chat;
    return scope;
  }

  static fromResult(result: AuthorBlockResult): AuthorBlockScope {
    return AuthorBlockScope.fromFlags(result.follow === 1, result.interact === 1, result.chat === 1);
  }

  any(): boolean {
    return this.follow || this.interact || this.chat;
  }

  equals(other: AuthorBlockScope): boolean {
    return this.follow === other.follow && this.interact === other.interact && this.chat === other.chat;
  }

  clone(): AuthorBlockScope {
    return AuthorBlockScope.fromFlags(this.follow, this.interact, this.chat);
  }
}

/** 按官方顺序格式化拉黑范围；未读回或无任何限制时返回空串，避免伪造状态。 */
export function authorBlockScopeLabel(scope: AuthorBlockScope | undefined): string {
  if (scope === undefined) { return ''; }
  const parts: string[] = [];
  if (scope.follow) { parts.push('关注'); }
  if (scope.interact) { parts.push('互动'); }
  if (scope.chat) { parts.push('私信'); }
  return parts.length > 0 ? `禁止${parts.join('、')}` : '';
}

export class AuthorBlockResult {
  code: number = -1;
  message: string = '';
  hasPermissions: boolean = false;
  follow: number = 0;
  interact: number = 0;
  chat: number = 0;
  blocked(): boolean { return this.interact === 1; }
  scope(): AuthorBlockScope { return AuthorBlockScope.fromResult(this); }
}

/** SetUserBlack／GetUserBlackInfo 官方响应：1=Error、2=DataRes。 */
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

export class ImBlacklistUser {
  uid: number = 0;
  uidText: string = '';
  name: string = '';
  nameShow: string = '';
  portrait: string = '';
  scopeKnown: boolean = false;
  follow: boolean = false;
  interact: boolean = false;
  chat: boolean = false;

  displayName(): string {
    if (this.nameShow.length > 0) { return this.nameShow; }
    if (this.name.length > 0) { return this.name; }
    return this.uidText.length > 0 ? `用户 ${this.uidText}` : `用户 ${this.uid}`;
  }

  scope(): AuthorBlockScope {
    return AuthorBlockScope.fromFlags(this.follow, this.interact, this.chat);
  }

  applyScope(scope: AuthorBlockScope): void {
    this.scopeKnown = true;
    this.follow = scope.follow;
    this.interact = scope.interact;
    this.chat = scope.chat;
  }

  scopeLabel(): string {
    return this.scopeKnown ? authorBlockScopeLabel(this.scope()) : '';
  }

  scopeKey(): string {
    if (!this.scopeKnown) { return '?'; }
    return `${this.follow ? 1 : 0}${this.interact ? 1 : 0}${this.chat ? 1 : 0}`;
  }
}

export class ImBlacklistResult {
  code: number = -1;
  message: string = '';
  isMask: number = 0;
  listRaw: string = '';
  users: ImBlacklistUser[] = [];
}

export class ImMaskUpdateResult {
  code: number = -1;
  message: string = '';
}

/** 读取 IM `protobuf.Error`（tag 1=errorno、tag 2=usermsg）；只有 errorno!=0 才算错。 */
function readImMaskError(reader: ProtoReader): ImMaskUpdateResult {
  const out: ImMaskUpdateResult = new ImMaskUpdateResult();
  out.code = 0;
  while (reader.hasMore()) {
    const tag: number = reader.readTag();
    if (tag === 1 && reader.wireType === WireType.VARINT) {
      out.code = reader.readInt32();
    } else if (tag === 2 && reader.wireType === WireType.LENGTH_DELIMITED) {
      out.message = reader.readString();
    } else {
      reader.skipField();
    }
  }
  return out;
}

function readImBlacklistUser(reader: ProtoReader): ImBlacklistUser {
  const user: ImBlacklistUser = new ImBlacklistUser();
  while (reader.hasMore()) {
    const tag: number = reader.readTag();
    if (tag === 1 && reader.wireType === WireType.LENGTH_DELIMITED) {
      user.name = reader.readString();
    } else if (tag === 2 && reader.wireType === WireType.LENGTH_DELIMITED) {
      user.portrait = reader.readString();
    } else if (tag === 3 && reader.wireType === WireType.VARINT) {
      const id: bigint = reader.readInt64();
      if (id > BigInt(0)) {
        user.uidText = id.toString();
        const num: number = Number(id);
        if (Number.isSafeInteger(num)) { user.uid = num; }
      }
    } else if (tag === 4 && reader.wireType === WireType.LENGTH_DELIMITED) {
      user.nameShow = reader.readString();
    } else {
      reader.skipField();
    }
  }
  return user;
}

/** 解析 IM `GetMaskInfoResIdl`（104103）：1=Error、2=DataRes{isMask(1), list(2), users(3)}。 */
export function parseImBlacklist(bytes: Uint8Array): ImBlacklistResult {
  const out: ImBlacklistResult = new ImBlacklistResult();
  if (bytes.length === 0) { return out; }
  let hasError: boolean = false;
  let hasData: boolean = false;
  const seen: Set<string> = new Set<string>();
  try {
    const root: ProtoReader = new ProtoReader(bytes);
    while (root.hasMore()) {
      const field: number = root.readTag();
      if (field === 1 && root.wireType === WireType.LENGTH_DELIMITED) {
        const err: ImMaskUpdateResult = readImMaskError(root.readMessageView());
        hasError = true;
        out.code = err.code;
        out.message = err.message;
      } else if (field === 2 && root.wireType === WireType.LENGTH_DELIMITED) {
        hasData = true;
        const data: ProtoReader = root.readMessageView();
        while (data.hasMore()) {
          const tag: number = data.readTag();
          if (tag === 1 && data.wireType === WireType.VARINT) {
            out.isMask = data.readInt32();
          } else if (tag === 2 && data.wireType === WireType.LENGTH_DELIMITED) {
            out.listRaw = data.readString();
          } else if (tag === 3 && data.wireType === WireType.LENGTH_DELIMITED) {
            const user: ImBlacklistUser = readImBlacklistUser(data.readMessageView());
            if (user.uidText.length > 0 && !seen.has(user.uidText)) {
              seen.add(user.uidText);
              out.users.push(user);
            }
          } else {
            data.skipField();
          }
        }
      } else {
        root.skipField();
      }
    }
    if (!hasError && !hasData) { return new ImBlacklistResult(); }
    if (!hasError && hasData) { out.code = 0; }
  } catch (err) {
    return new ImBlacklistResult();
  }
  return out;
}

/** 解析 IM `UpdateMaskInfoResIdl`（104102）：1=Error。 */
export function parseImMaskUpdate(bytes: Uint8Array): ImMaskUpdateResult {
  const out: ImMaskUpdateResult = new ImMaskUpdateResult();
  if (bytes.length === 0) { return out; }
  let hasError: boolean = false;
  try {
    const root: ProtoReader = new ProtoReader(bytes);
    while (root.hasMore()) {
      const field: number = root.readTag();
      if (field === 1 && root.wireType === WireType.LENGTH_DELIMITED) {
        const err: ImMaskUpdateResult = readImMaskError(root.readMessageView());
        hasError = true;
        out.code = err.code;
        out.message = err.message;
      } else {
        root.skipField();
      }
    }
    if (!hasError) { return new ImMaskUpdateResult(); }
  } catch (err) {
    return new ImMaskUpdateResult();
  }
  return out;
}
