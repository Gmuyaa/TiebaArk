

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

interface RawUserGrowth {

  level_id?: number | string;

  score?: number | string;

  target_score?: number | string;

  tmoney?: number | string;
}

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

function toStr(value: number | string | undefined): string {
  if (value === undefined || value === null) {
    return '';
  }
  return String(value);
}

export class UserProfileInfo {
  followed: boolean = false;
  intro: string = '';
  forums: ProfileForum[] = [];

  uid: number = 0;

  userName: string = '';

  nickName: string = '';

  portrait: string = '';

  concernNum: number = 0;

  fansNum: number = 0;

  levelId: number = 0;

  levelScore: number = 0;

  levelTargetScore: number = 0;

  postNum: number = 0;

  totalAgreeNum: number = 0;

  likeForumNum: number = 0;

  tbAge: string = '';

  hasAny(): boolean {
    return this.uid > 0 || this.nickName.length > 0 || this.portrait.length > 0
      || this.concernNum > 0 || this.fansNum > 0 || this.levelId > 0;
  }
}

export class ProfileForum {
  avatar: string = '';
  id: number = 0;
  name: string = '';
}

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

  const tiebaUid: string = toStr(user.tieba_uid);
  if (tiebaUid.length > 0 && out.uid === 0) {

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

/* 协议参考：lumina37/aiotieba（Unlicense）。 */

const RES_ERROR: number = 1;
const RES_DATA: number = 2;

const DATA_USER: number = 1;
const DATA_USER_AGREE: number = 14;

const AGREE_TOTAL: number = 1;

const ERROR_ERRNO: number = 1;

const U_ID: number = 2;
const U_NAME: number = 3;
const U_NAME_SHOW: number = 4;
const U_PORTRAIT: number = 5;

const U_MY_LIKE_NUM: number = 33;
const U_FANS: number = 30;
const U_CONCERN: number = 31;
const U_POST: number = 37;
const U_TB_AGE: number = 38;
const U_LIKE_FORUM: number = 47;
const U_TIEBA_UID: number = 120;
const U_GROWTH: number = 137;

const GROWTH_LEVEL: number = 1;

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

  out.userName = toStr(data.user_itieba_id);
  return out;
}

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

export function displayName(profile: UserProfileInfo, fallback: string): string {
  if (profile.nickName.length > 0) {
    return profile.nickName;
  }
  if (profile.userName.length > 0) {
    return profile.userName;
  }
  return fallback;
}

export function accountIdText(profile: UserProfileInfo): string {
  if (profile.userName.length > 0) {
    return profile.userName;
  }
  if (profile.uid > 0) {
    return String(profile.uid);
  }
  return '';
}

export function formatCount(value: number): string {
  if (value >= 10000) {
    const wan: number = Math.floor(value / 1000) / 10;
    return `${wan}万`;
  }
  return String(value);
}
