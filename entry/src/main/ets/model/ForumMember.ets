/** 吧成员与吧务资料解析，不包含网络与平台存储。 */
import { ProtoReader, WireType } from '../proto/ProtoWire';
import { portraitUrl } from './ThreadDetail';

/** 一个成员（官方 `BawuRoleInfoPub`） */
export class ForumMemberItem {
  userId: number = 0;
  userName: string = '';
  nameShow: string = '';
  /** 头像标识（列表接口给的是 portrait 路径，与 `DirectoryUser` 同一口径） */
  portrait: string = '';
  /** 可直接给 `Image` 的头像地址 */
  avatar: string = '';
  userLevel: number = 0;
  levelName: string = '';
  roleId: number = 0;
  /** 该成员在本组里的角色名（如"吧主""小吧"），服务端可能给空串 */
  roleName: string = '';

  /** 展示名：优先 `name_show`（改过昵称的展示名），再退用户名，最后兜底文案 */
  displayName(): string {
    if (this.nameShow.length > 0) { return this.nameShow; }
    if (this.userName.length > 0) { return this.userName; }
    return '贴吧用户';
  }
}

/** 一组成员（官方 `MemberGroupInfo`） */
export class ForumMemberGroup {
  /** 服务端原始组标识，形如 `1_吧务管理团队` */
  type: string = '';
  /** 服务端声明的**总人数**（可能大于 `members` 长度，见文件头"预览"说明） */
  total: number = 0;
  members: ForumMemberItem[] = [];
}

export class ForumMemberResult {
  code: number = -1;
  message: string = '';
  groups: ForumMemberGroup[] = [];
}

/**
 * 组标题：剥掉服务端下发的 `<数字>_` 序号前缀。
 * `"1_吧务管理团队"` → `"吧务管理团队"`；空串回退成中性标题（**不编具体组名**）。
 */
export function groupTitle(type: string): string {
  const clean: string = type.trim();
  if (clean.length === 0) { return '吧成员'; }
  const match: RegExpMatchArray | null = clean.match(/^\d+_(.*)$/);
  if (match === null) { return clean; }
  const rest: string = match[1].trim();
  return rest.length > 0 ? rest : clean;
}

/**
 * 预览说明：服务端只回一部分成员时**如实标注**。
 * 返回空串 = 返回的就是全部（不显示多余文字）。
 */
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

/**
 * 角色文案：服务端在 `role_name` 里给的是**协议原值**（实测 `manager`／`assist`），
 * 直接画出来就是"界面出现实现术语"。映射规则与 `pages/DirectoryPage.ets` 里那份私有实现一致
 * （那边是 `role_label` 的 JSON 口径，这边是 pb 口径；统一到一处等下次碰 DirectoryPage 时再做）。
 *
 * 认不出来的值：纯 ASCII 的按"吧务成员"兜底（那多半是另一个协议标识），
 * 含中文的原样展示（服务端已经给了可读角色名）。
 */
export function roleLabel(role: string): string {
  const clean: string = role.trim();
  if (clean.length === 0) { return ''; }
  if (clean === 'manager') { return '吧主'; }
  if (clean === 'assist') { return '小吧主'; }
  if (clean === 'forum_helper') { return '贴吧助手'; }
  return /^[A-Za-z_]+$/.test(clean) ? '吧务成员' : clean;
}

// ── 吧务团队全量（`GetBawuInfo`，cmd 301007）────────────────────────────────
//
// 为什么需要它：`getMemberInfo` 的 `member_group_list` **只回预览**（实测 52 人的组只回 5 个，
// 且 `DataReq` 里没有 pn/rn）。吧务的**全量**名单在另一个端点：反编译
// `com/baidu/tieba/forumMember/bawu/BawuTeamRequestMessage.java` 得到 `super(1001705, 301007)`。
// 真机实测：`total_num=52`，四个角色 吧主 1／小吧主 45／语音小编 5／吧主助手 1，合计与预览组的
// `member_group_num` 一致 —— 也就是说这两个端点讲的是同一批人，只是一个给预览、一个给全量。

/** `GetBawuInfo` 的结果：按角色分组，**每组都是全量** */
export class BawuTeamResult {
  code: number = -1;
  message: string = '';
  /** 团队总人数（服务端 `total_num`） */
  total: number = 0;
  /** 每个角色一组：组标题 = 服务端角色名，`total` = 该角色实际人数（就是全量，不再有"只看前 N 位"） */
  roles: ForumMemberGroup[] = [];
}

/** 组名里带"吧务"的，视为 `getMemberInfo` 给的**吧务预览组**（全量由 `getBawuInfo` 提供） */
export function isBawuPreviewGroup(type: string): boolean {
  return groupTitle(type).indexOf('吧务') >= 0;
}

/**
 * 拼最终展示列表（纯函数，Node 可测）：
 * 有全量吧务角色组时，用**角色组**替代 `getMemberInfo` 里的吧务预览组，其余组原样保留。
 * 团队为空（请求失败或该吧没有吧务数据）时**原样返回**，让页面继续显示预览并带上"只看前 N 位"的说明。
 */
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

/** 读 `GetBawuInfoResIdl`：`root{ data=1, error=2 }` → `data.bawu_team_info=1` →
 *  `BawuTeam{ total_num=1, bawu_team_list=2:[BawuRoleDes{ role_name=1, role_info=2:[成员] }] }` */
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

/** 读 `BawuTeam{ total_num=1, bawu_team_list=2 }` */
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
      // 这一组就是全量：total 取实际人数，页面上的"只看前 N 位"随之消失
      group.total = group.members.length;
      /*
       * 行内角色文案统一用**组名**：`BawuRoleDes.role_name` 就是这一组人的角色
       * （实测组名"语音小编"里的成员，自带 `role_name` 反而是认不出的 ASCII 码，
       *  `roleLabel()` 会兜底成"吧务成员"，画出来就是"组名说语音小编、行里说吧务成员"）。
       * 组名为空时不动成员自带的值。
       */
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

/** 读 `MemberGroupInfo.member_group_list` 里的一个成员 */
function readMember(reader: ProtoReader): ForumMemberItem {
  const item: ForumMemberItem = new ForumMemberItem();
  while (reader.hasMore()) {
    const tag: number = reader.readTag();
    if (tag === 2 && reader.wireType === WireType.VARINT) {
      /** user_id 按 64 位读取，避免 int32 截断。 */
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

/** 读 `data`：`member_group_info = 1`（repeated） */
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

/** 读 `Error`：errorno=1、errmsg=2、usermsg=3（优先展示非空 usermsg） */
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

/**
 * 解析 `GetMemberInfoResIdl`。**布局与黑名单相反**：`data = 1`、`error = 2`。
 * 解析失败一律回一个空结果（`code = -1`），由调用方按业务错误处理 ——
 * 不能把解析失败伪装成"这个吧没有成员"。
 */
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
