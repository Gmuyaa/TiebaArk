/** 个人资料解析。基础资料与社交资料分别读取，合并时只覆盖服务端实际返回的字段。 */

import { ProtoReader } from '../proto/ProtoWire';

export function avatarIdentity(portrait: string): string {
  const raw: string = portrait.trim();
  if (raw.length === 0) {
    return '';
  }
  const query: number = raw.indexOf('?');
  const head: string = query < 0 ? raw : raw.substring(0, query);
  const slash: number = head.lastIndexOf('/');
  const token: string = slash < 0 ? head : head.substring(slash + 1);
  return /^[A-Za-z0-9_.-]+$/.test(token) ? token : '';
}

/** `/c/u/user/profile` 的 `user.user_growth` 段 */
interface RawUserGrowth {
  /** 成长等级 */
  level_id?: number | string;
  /** 当前成长值 */
  score?: number | string;
  /** 升级所需成长值 */
  target_score?: number | string;
  /** T 豆 */
  tmoney?: number | string;
}

/** `/c/u/user/profile` 的 `user` 段（只声明用得到的字段，其余忽略） */
interface RawSelfUser {
  id?: number | string;
  name?: string;
  name_show?: string;
  portrait?: string;
  concern_num?: number | string;
  fans_num?: number | string;
  post_num?: number | string;
  total_agree_num?: number | string;
  tb_age?: string;
  tieba_uid?: string;
  user_growth?: RawUserGrowth;
}

interface RawSelfEnvelope {
  user?: RawSelfUser;
  error_code?: number | string;
  error_msg?: string;
}

/** `/f/user/json_userinfo` 的 `data` 段 */
interface RawUserInfoData {
  open_uid?: number | string;
  user_name_show?: string;
  user_portrait?: string;
  user_itieba_id?: string;
}

interface RawUserInfoEnvelope {
  no?: number;
  error?: string;
  data?: RawUserInfoData;
}

/** 可空数值 → number。解析不出来一律 0，不抛异常 */
function toNum(value: number | string | undefined): number {
  if (value === undefined || value === null) {
    return 0;
  }
  if (typeof value === 'number') {
    return Number.isNaN(value) ? 0 : value;
  }
  const parsed: number = Number.parseInt(value, 10);
  return Number.isNaN(parsed) ? 0 : parsed;
}

/** 可空字符串 → string */
function toStr(value: number | string | undefined): string {
  if (value === undefined || value === null) {
    return '';
  }
  return String(value);
}

/**
 * 当前账号的展示资料。
 *
 * 一个对象同时承载两个接口的结果：`mergeProfile()` 负责把"只在某一个接口里有的字段"
 * 合到一起，界面只认这一个类型（不必知道字段来自哪个端点）。
 */
export class UserProfileInfo {
  followed: boolean = false;
  intro: string = '';
  forums: ProfileForum[] = [];
  /** 账号 uid（数字）。0 表示未知 */
  uid: number = 0;
  /** 用户名（@名）。未设置时为空串 */
  userName: string = '';
  /** 昵称。未设置时为空串 */
  nickName: string = '';
  /** 头像 hash（需经 `portraitUrl()` 拼成完整 URL） */
  portrait: string = '';
  /** 关注的用户数 */
  concernNum: number = 0;
  /** 粉丝数 */
  fansNum: number = 0;
  /** 成长等级 */
  levelId: number = 0;
  /** 当前成长值 */
  levelScore: number = 0;
  /** 升级所需成长值 */
  levelTargetScore: number = 0;
  /** 发帖数 */
  postNum: number = 0;
  /** 获赞数 */
  totalAgreeNum: number = 0;

  likeForumNum: number = 0;

  tbAge: string = '';

  /** 是否至少拿到了一项可用资料。全空说明两个接口都没成功，界面应显示占位而非一堆 0 */
  hasAny(): boolean {
    return this.uid > 0 || this.nickName.length > 0 || this.portrait.length > 0
      || this.concernNum > 0 || this.fansNum > 0 || this.levelId > 0;
  }
}

/** LikeForumInfo 只返回名称和 ID；头像由页面 VM 从真实吧资料补齐。 */
export class ProfileForum {
  avatar: string = '';
  id: number = 0;
  name: string = '';
}

/**
 * 解析 `POST /c/u/user/profile` 的响应。
 *
 * 只看顶层 `user`；信封里的 `error_code` 由调用方（`TiebaApi`）先行判定，
 * 这里不做业务成败判断——解析器只负责"从文本里读出什么"，不负责"该不该读"。
 */
export function parseSelfProfile(jsonText: string): UserProfileInfo {
  const out: UserProfileInfo = new UserProfileInfo();
  if (jsonText.length === 0) {
    return out;
  }
  let envelope: RawSelfEnvelope;
  try {
    envelope = JSON.parse(jsonText) as RawSelfEnvelope;
  } catch (err) {
    return out;
  }
  const user: RawSelfUser | undefined = envelope.user;
  if (user === undefined || user === null) {
    return out;
  }

  out.uid = toNum(user.id);
  out.userName = toStr(user.name);
  out.nickName = toStr(user.name_show);
  out.portrait = toStr(user.portrait);
  out.concernNum = toNum(user.concern_num);
  out.fansNum = toNum(user.fans_num);
  out.postNum = toNum(user.post_num);
  out.totalAgreeNum = toNum(user.total_agree_num);
  out.tbAge = toStr(user.tb_age);
  /** tieba_uid 仅在非空时采用，避免覆盖已有标识。 */
  const tiebaUid: string = toStr(user.tieba_uid);
  if (tiebaUid.length > 0 && out.uid === 0) {
    // tieba_uid 是**另一套**编号（实测 ≠ user.id），**不能**当 uid 用
    out.uid = toNum(tiebaUid);
  }

  const growth: RawUserGrowth | undefined = user.user_growth;
  if (growth !== undefined && growth !== null) {
    out.levelId = toNum(growth.level_id);
    out.levelScore = toNum(growth.score);
    out.levelTargetScore = toNum(growth.target_score);
  }
  return out;
}

/** 个人资料 protobuf 响应解析。早期公开协议参考包含 aiotieba，初始版本与提交未留存；当前字段及嵌套结构另经官方 DEX 注解核对，后续核对不替代历史来源或授权。 */

/** `ProfileResIdl` 顶层 */
const RES_ERROR: number = 1;
const RES_DATA: number = 2;
/** `ProfileResIdl.DataRes` */
const DATA_USER: number = 1;
const DATA_USER_AGREE: number = 14;
/** `DataRes.UserAgreeInfo` */
const AGREE_TOTAL: number = 1;
/** `Error` 消息里的错误码 */
const ERROR_ERRNO: number = 1;
/** `User` 当前读取的字段号已直接复核基准 APK 的 DEX 注解；早期参考版本仍未定位。 */
const U_ID: number = 2;
const U_NAME: number = 3;
const U_NAME_SHOW: number = 4;
const U_PORTRAIT: number = 5;
/**
 * `my_like_num` —— **关注的吧总数**。
 *
 * 这才是"关注吧"那一格的正确来源：`likeForum`(47) 那个 repeated 列表**会分页**
 * （实测某账号 `my_like_num=7` 而列表只回了 6 条），拿条目数当总数会少。
 */
const U_MY_LIKE_NUM: number = 33;
const U_FANS: number = 30;
const U_CONCERN: number = 31;
const U_POST: number = 37;
const U_TB_AGE: number = 38;
const U_LIKE_FORUM: number = 47;
const U_TIEBA_UID: number = 120;
const U_GROWTH: number = 137;
/** `User.UserGrowth` */
const GROWTH_LEVEL: number = 1;

/** 读取 `User` 消息并填充 `out`。未知字段一律 `skipField()`，不能读串位。 */
function readUserMessage(r: ProtoReader, out: UserProfileInfo): void {
  while (r.hasMore()) {
    const f: number = r.readTag();
    if (f === U_ID) {
      out.uid = Number(r.readInt64());
    } else if (f === U_NAME) {
      out.userName = r.readString();
    } else if (f === U_NAME_SHOW) {
      out.nickName = r.readString();
    } else if (f === U_PORTRAIT) {
      out.portrait = r.readString();
    } else if (f === 35) {
      out.followed = r.readInt32() > 0;
    } else if (f === U_FANS) {
      out.fansNum = r.readInt32();
    } else if (f === U_CONCERN) {
      out.concernNum = r.readInt32();
    } else if (f === U_POST) {
      out.postNum = r.readInt32();
    } else if (f === U_TB_AGE) {
      out.tbAge = r.readString();
    } else if (f === U_MY_LIKE_NUM) {
      // "关注吧"总数走这个字段：`likeForum` 列表会分页，条目数 ≠ 总数
      out.likeForumNum = r.readInt32();
    } else if (f === U_LIKE_FORUM) {
      const forum: ProfileForum = new ProfileForum();
      const reader: ProtoReader = r.readMessageView();
      while (reader.hasMore()) {
        const field: number = reader.readTag();
        if (field === 1) { forum.name = reader.readString(); }
        else if (field === 2) { forum.id = Number(reader.readInt64()); }
        else { reader.skipField(); }
      }
      if (forum.name.length > 0) { out.forums.push(forum); }
    } else if (f === 34) {
      out.intro = r.readString();
    } else if (f === U_TIEBA_UID) {
      // 新版贴吧号本项目暂不使用（未设置时为空串）；读掉即可，别读串位
      r.readString();
    } else if (f === U_GROWTH) {
      const g: ProtoReader = r.readMessageView();
      while (g.hasMore()) {
        const gf: number = g.readTag();
        if (gf === GROWTH_LEVEL) {
          out.levelId = g.readInt32();
        } else {
          g.skipField();
        }
      }
    } else {
      r.skipField();
    }
  }
}

/**
 * 解析 protobuf 形态的用户资料。
 *
 * 只做解析，**不做业务成败判断** —— 错误码由调用方先经 `parseProtoErrorno()` 看。
 * 解析失败返回空对象（`hasAny() === false`），不抛异常：与 JSON 两族同一约定。
 */
export function parseSelfProfileProto(bytes: Uint8Array): UserProfileInfo {
  const out: UserProfileInfo = new UserProfileInfo();
  if (bytes.length === 0) {
    return out;
  }
  try {
    const root: ProtoReader = new ProtoReader(bytes);
    while (root.hasMore()) {
      const f: number = root.readTag();
      if (f === RES_DATA) {
        const data: ProtoReader = root.readMessageView();
        while (data.hasMore()) {
          const df: number = data.readTag();
          if (df === DATA_USER) {
            readUserMessage(data.readMessageView(), out);
          } else if (df === DATA_USER_AGREE) {
            const agree: ProtoReader = data.readMessageView();
            while (agree.hasMore()) {
              const af: number = agree.readTag();
              if (af === AGREE_TOTAL) {
                out.totalAgreeNum = Number(agree.readInt64());
              } else {
                agree.skipField();
              }
            }
          } else {
            data.skipField();
          }
        }
      } else {
        root.skipField();
      }
    }
  } catch (err) {
    return new UserProfileInfo();
  }
  return out;
}

/**
 * 取 pb 响应里的业务错误码（`ProfileResIdl.error.errorno`）。
 *
 * 拿不到时返回 `-1`（本地伪码）—— 与"服务端明确回 0（成功）"区分开，
 * 避免把"解析失败"当成"业务成功"。
 */
export function parseProtoErrorno(bytes: Uint8Array): number {
  if (bytes.length === 0) {
    return -1;
  }
  try {
    const root: ProtoReader = new ProtoReader(bytes);
    while (root.hasMore()) {
      const f: number = root.readTag();
      if (f === RES_ERROR) {
        const err: ProtoReader = root.readMessageView();
        while (err.hasMore()) {
          const ef: number = err.readTag();
          if (ef === ERROR_ERRNO) {
            return err.readInt32();
          }
          err.skipField();
        }
      } else {
        root.skipField();
      }
    }
  } catch (err) {
    return -1;
  }
  return -1;
}

/**
 * 解析 `GET /f/user/json_userinfo` 的响应。
 *
 * 注意 `open_uid` 实测是**字符串**，`user_name_show` 才是昵称（没有 `nickname` 键）。
 */
export function parseUserInfo(jsonText: string): UserProfileInfo {
  const out: UserProfileInfo = new UserProfileInfo();
  if (jsonText.length === 0) {
    return out;
  }
  let envelope: RawUserInfoEnvelope;
  try {
    envelope = JSON.parse(jsonText) as RawUserInfoEnvelope;
  } catch (err) {
    return out;
  }
  const data: RawUserInfoData | undefined = envelope.data;
  if (data === undefined || data === null) {
    return out;
  }
  out.uid = toNum(data.open_uid);
  out.nickName = toStr(data.user_name_show);
  out.portrait = toStr(data.user_portrait);
  // user_itieba_id 是"贴吧号"，与用户名不是一回事；未设置时为空串
  out.userName = toStr(data.user_itieba_id);
  return out;
}

/**
 * 合并两份资料：`primary` 优先，逐字段"主对象非空才覆盖"。
 *
 * 与 `ThreadDetail.mergeAuthorFallback` 同一约定：**两边都空就保持空，不造数据**。
 * 顺序很重要——昵称来自 `json_userinfo`（primary 用它的那份），
 * 关注/粉丝/等级来自 `profile`（primary 用它的那份），调用方各取所长。
 */
export function mergeProfile(primary: UserProfileInfo, fallback: UserProfileInfo): UserProfileInfo {
  const out: UserProfileInfo = new UserProfileInfo();
  out.uid = primary.uid > 0 ? primary.uid : fallback.uid;
  out.userName = primary.userName.length > 0 ? primary.userName : fallback.userName;
  out.nickName = primary.nickName.length > 0 ? primary.nickName : fallback.nickName;
  out.portrait = primary.portrait.length > 0 ? primary.portrait : fallback.portrait;
  out.concernNum = primary.concernNum > 0 ? primary.concernNum : fallback.concernNum;
  out.fansNum = primary.fansNum > 0 ? primary.fansNum : fallback.fansNum;
  out.levelId = primary.levelId > 0 ? primary.levelId : fallback.levelId;
  out.levelScore = primary.levelScore > 0 ? primary.levelScore : fallback.levelScore;
  out.levelTargetScore = primary.levelTargetScore > 0
    ? primary.levelTargetScore : fallback.levelTargetScore;
  out.postNum = primary.postNum > 0 ? primary.postNum : fallback.postNum;
  out.totalAgreeNum = primary.totalAgreeNum > 0 ? primary.totalAgreeNum : fallback.totalAgreeNum;
  out.likeForumNum = primary.likeForumNum > 0 ? primary.likeForumNum : fallback.likeForumNum;
  out.tbAge = primary.tbAge.length > 0 ? primary.tbAge : fallback.tbAge;
  out.intro = primary.intro.length > 0 ? primary.intro : fallback.intro;
  out.forums = primary.forums.length > 0 ? primary.forums : fallback.forums;
  return out;
}

/** 主标题按昵称、用户名、兜底文案依次选择。 */
export function displayName(profile: UserProfileInfo, fallback: string): string {
  if (profile.nickName.length > 0) {
    return profile.nickName;
  }
  if (profile.userName.length > 0) {
    return profile.userName;
  }
  return fallback;
}

/** 账号标识优先显示贴吧号，缺失时回退数字 uid；均缺失则返回空串。 */
export function accountIdText(profile: UserProfileInfo): string {
  if (profile.userName.length > 0) {
    return profile.userName;
  }
  if (profile.uid > 0) {
    return String(profile.uid);
  }
  return '';
}

/**
 * 数字的展示格式：10000 以上折成"x.x万"，其余原样。
 *
 * 关注/粉丝数在贴吧动辄上万，直接铺满会撑坏那三个等宽格子。
 * **不做四舍五入到整数**（"1.0万"会被误读成 1 万整），保留一位小数。
 */
export function formatCount(value: number): string {
  if (value >= 10000) {
    const wan: number = Math.floor(value / 1000) / 10;
    return `${wan}万`;
  }
  return String(value);
}
