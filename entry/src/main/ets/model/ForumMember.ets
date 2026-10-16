
import { ProtoReader, WireType } from '../proto/ProtoWire';
import { portraitUrl } from './ThreadDetail';

export class ForumMemberItem {
  userId: number = 0;
  userName: string = '';
  nameShow: string = '';

  portrait: string = '';

  avatar: string = '';
  userLevel: number = 0;
  levelName: string = '';
  roleId: number = 0;

  roleName: string = '';

  displayName(): string {
    if (this.nameShow.length > 0) { return this.nameShow; }
    if (this.userName.length > 0) { return this.userName; }
    return '贴吧用户';
  }
}

export class ForumMemberGroup {

  type: string = '';

  total: number = 0;
  members: ForumMemberItem[] = [];
}

export class ForumMemberResult {
  code: number = -1;
  message: string = '';
  groups: ForumMemberGroup[] = [];
}

export function groupTitle(type: string): string {
  const clean: string = type.trim();
  if (clean.length === 0) { return '吧成员'; }
  const match: RegExpMatchArray | null = clean.match(/^\d+_(.*)$/);
  if (match === null) { return clean; }
  const rest: string = match[1].trim();
  return rest.length > 0 ? rest : clean;
}

export function previewNote(total: number, shown: number): string {
  const all: number = Number.isFinite(total) && total > 0 ? Math.floor(total) : 0;
  const count: number = Number.isFinite(shown) && shown > 0 ? Math.floor(shown) : 0;
  if (all > count && count > 0) {
    return `共 ${all} 人，这里显示前 ${count} 位`;
  }
  if (all > count && count === 0) {
    return `共 ${all} 人`;
  }
  return '';
}

export function roleLabel(role: string): string {
  const clean: string = role.trim();
  if (clean.length === 0) { return ''; }
  if (clean === 'manager') { return '吧主'; }
  if (clean === 'assist') { return '小吧主'; }
  if (clean === 'forum_helper') { return '贴吧助手'; }
  return /^[A-Za-z_]+$/.test(clean) ? '吧务成员' : clean;
}

export class BawuTeamResult {
  code: number = -1;
  message: string = '';

  total: number = 0;

  roles: ForumMemberGroup[] = [];
}

export function isBawuPreviewGroup(type: string): boolean {
  return groupTitle(type).indexOf('吧务') >= 0;
}

export function composeMemberGroups(groups: ForumMemberGroup[], team: BawuTeamResult): ForumMemberGroup[] {
  if (team.roles.length === 0) {
    return groups;
  }
  const out: ForumMemberGroup[] = [];
  for (let i = 0; i < team.roles.length; i++) {
    out.push(team.roles[i]);
  }
  for (let i = 0; i < groups.length; i++) {
    if (!isBawuPreviewGroup(groups[i].type)) {
      out.push(groups[i]);
    }
  }
  return out;
}

export function parseBawuTeam(bytes: Uint8Array): BawuTeamResult {
  const out: BawuTeamResult = new BawuTeamResult();
  try {
    const root: ProtoReader = new ProtoReader(bytes);
    while (root.hasMore()) {
      const field: number = root.readTag();
      if (field === 1 && root.wireType === WireType.LENGTH_DELIMITED) {
        readBawuData(root.readMessageView(), out);
      } else if (field === 2 && root.wireType === WireType.LENGTH_DELIMITED) {
        const error: ForumMemberResult = new ForumMemberResult();
        readError(root.readMessageView(), error);
        out.code = error.code;
        out.message = error.message;
      } else {
        root.skipField();
      }
    }
  } catch (err) {
    return new BawuTeamResult();
  }
  return out;
}

function readBawuData(reader: ProtoReader, out: BawuTeamResult): void {
  while (reader.hasMore()) {
    const tag: number = reader.readTag();
    if (tag === 1 && reader.wireType === WireType.LENGTH_DELIMITED) {
      readBawuTeam(reader.readMessageView(), out);
    } else {
      reader.skipField();
    }
  }
}

function readBawuTeam(reader: ProtoReader, out: BawuTeamResult): void {
  while (reader.hasMore()) {
    const tag: number = reader.readTag();
    if (tag === 1 && reader.wireType === WireType.VARINT) {
      out.total = reader.readInt32();
    } else if (tag === 2 && reader.wireType === WireType.LENGTH_DELIMITED) {
      const group: ForumMemberGroup = new ForumMemberGroup();
      const role: ProtoReader = reader.readMessageView();
      while (role.hasMore()) {
        const field: number = role.readTag();
        if (field === 1 && role.wireType === WireType.LENGTH_DELIMITED) {
          group.type = role.readString();
        } else if (field === 2 && role.wireType === WireType.LENGTH_DELIMITED) {
          group.members.push(readMember(role.readMessageView()));
        } else {
          role.skipField();
        }
      }

      group.total = group.members.length;

      if (group.type.trim().length > 0) {
        for (let i = 0; i < group.members.length; i++) {
          group.members[i].roleName = group.type;
        }
      }
      out.roles.push(group);
    } else {
      reader.skipField();
    }
  }
}

function readMember(reader: ProtoReader): ForumMemberItem {
  const item: ForumMemberItem = new ForumMemberItem();
  while (reader.hasMore()) {
    const tag: number = reader.readTag();
    if (tag === 2 && reader.wireType === WireType.VARINT) {

      item.userId = Number(reader.readInt64());
    } else if (tag === 3 && reader.wireType === WireType.VARINT) {
      item.roleId = reader.readInt32();
    } else if (tag === 4 && reader.wireType === WireType.LENGTH_DELIMITED) {
      item.roleName = reader.readString();
    } else if (tag === 5 && reader.wireType === WireType.LENGTH_DELIMITED) {
      item.portrait = reader.readString();
      item.avatar = portraitUrl(item.portrait);
    } else if (tag === 6 && reader.wireType === WireType.VARINT) {
      item.userLevel = reader.readInt32();
    } else if (tag === 7 && reader.wireType === WireType.LENGTH_DELIMITED) {
      item.levelName = reader.readString();
    } else if (tag === 8 && reader.wireType === WireType.LENGTH_DELIMITED) {
      item.userName = reader.readString();
    } else if (tag === 9 && reader.wireType === WireType.LENGTH_DELIMITED) {
      item.nameShow = reader.readString();
    } else {
      reader.skipField();
    }
  }
  return item;
}

function readData(reader: ProtoReader, out: ForumMemberResult): void {
  while (reader.hasMore()) {
    const tag: number = reader.readTag();
    if (tag === 1 && reader.wireType === WireType.LENGTH_DELIMITED) {
      const group: ForumMemberGroup = new ForumMemberGroup();
      const body: ProtoReader = reader.readMessageView();
      while (body.hasMore()) {
        const field: number = body.readTag();
        if (field === 1 && body.wireType === WireType.LENGTH_DELIMITED) {
          group.type = body.readString();
        } else if (field === 2 && body.wireType === WireType.VARINT) {
          group.total = body.readInt32();
        } else if (field === 3 && body.wireType === WireType.LENGTH_DELIMITED) {
          group.members.push(readMember(body.readMessageView()));
        } else {
          body.skipField();
        }
      }
      out.groups.push(group);
    } else {
      reader.skipField();
    }
  }
}

function readError(reader: ProtoReader, out: ForumMemberResult): void {
  let message: string = '';
  while (reader.hasMore()) {
    const tag: number = reader.readTag();
    if (tag === 1 && reader.wireType === WireType.VARINT) {
      out.code = reader.readInt32();
    } else if ((tag === 2 || tag === 3) && reader.wireType === WireType.LENGTH_DELIMITED) {
      const text: string = reader.readString();
      if (text.length > 0 && (tag === 3 || message.length === 0)) { message = text; }
    } else {
      reader.skipField();
    }
  }
  out.message = message;
}

export function parseForumMembers(bytes: Uint8Array): ForumMemberResult {
  const out: ForumMemberResult = new ForumMemberResult();
  try {
    const root: ProtoReader = new ProtoReader(bytes);
    while (root.hasMore()) {
      const field: number = root.readTag();
      if (field === 1 && root.wireType === WireType.LENGTH_DELIMITED) {
        readData(root.readMessageView(), out);
      } else if (field === 2 && root.wireType === WireType.LENGTH_DELIMITED) {
        readError(root.readMessageView(), out);
      } else {
        root.skipField();
      }
    }
  } catch (err) {
    return new ForumMemberResult();
  }
  return out;
}
