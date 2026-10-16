/** 官方安卓版 22.11.1.0 的吧资料、吧规、吧务与社交列表；字段经只读接口核对。 */
import { RawContentItem } from '../api/RawThreadPage';
import { ContentPiece, portraitUrl } from './ThreadDetail';

export type DirectoryKind = 'forum' | 'rules' | 'team' | 'fans' | 'following';

/** 列表头像常是完整 URL；只提取百度头像路径，不能把任意网页地址当用户标识。 */
export function profilePortrait(value: string): string {
  const raw: string = value.trim();
  const token: RegExpMatchArray | null = raw.match(/^([A-Za-z0-9_.-]+)(?:\?[^#]*)?$/);
  if (token !== null) { return token[1]; }
  const match: RegExpMatchArray | null = raw.match(
    /^https?:\/\/(?:himg\.bdimg\.com|tb\.himg\.baidu\.com)\/sys\/portrait\/item\/([A-Za-z0-9_.-]+)(?:\?|$)/);
  return match === null ? '' : match[1];
}

export class DirectoryUser {
  uid: number = 0;
  name: string = '';
  portrait: string = '';
  avatar: string = '';
  intro: string = '';
  role: string = '';
}

export class ForumRuleSection {
  title: string = '';
  paragraphs: ContentPiece[][] = [];
}

export class ForumInformation {
  id: number = 0;
  name: string = '';
  avatar: string = '';
  slogan: string = '';
  description: string = '';
  descriptionPieces: ContentPiece[] = [];
  category: string = '';
  members: number = 0;
  threads: number = 0;
}

export class DirectoryData {
  forum: ForumInformation = new ForumInformation();
  users: DirectoryUser[] = [];
  rules: ForumRuleSection[] = [];
  title: string = '';
  preface: string = '';
  hasMore: boolean = false;
  total: number = 0;
}

interface RawDirectoryUser {
  id?: number | string;
  user_id?: number | string;
  name?: string;
  user_name?: string;
  name_show?: string;
  portrait?: string;
  intro?: string;
  role_name?: string;
}
interface RawTeam {
  role_name?: string;
  role_info?: RawDirectoryUser[];
}
interface RawRuleParagraph { content?: RawContentItem[]; }
interface RawRule { title?: string; content_list?: RawRuleParagraph[]; }
interface RawDirectoryPage { has_more?: number | string; total_count?: number | string; }
interface RawBawuTeam { bawu_team_list?: RawTeam[]; total_num?: number | string; }
interface RawForumIntroPiece { type?: number | string; text?: string; link?: string; }
interface RawInformation {
  forum_id?: number | string;
  forum_name?: string;
  avatar?: string;
  slogan?: string;
  content?: string | RawForumIntroPiece[];
  lv1_name?: string;
  lv2_name?: string;
  member_count?: number | string;
  thread_count?: number | string;
}
interface RawDirectory {
  error_code?: number | string;
  forum_info?: RawInformation;
  forum?: RawInformation;
  title?: string;
  preface?: string;
  new_rules?: RawRule[];
  default_rules?: RawRule[];
  rules?: RawRule[];
  user_list?: RawDirectoryUser[];
  follow_list?: RawDirectoryUser[];
  has_more?: number | string;
  tips_text?: string;
  total_follow_num?: number | string;
  follow_list_switch?: number | string;
  page?: RawDirectoryPage;
  bawu_team_info?: RawBawuTeam;
}

function numberValue(value: number | string | undefined): number {
  const parsed: number = Number(value);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : 0;
}

function userFromRaw(raw: RawDirectoryUser, role: string = ''): DirectoryUser {
  const user: DirectoryUser = new DirectoryUser();
  user.uid = numberValue(raw.user_id ?? raw.id);
  user.name = raw.name_show || raw.user_name || raw.name || '贴吧用户';
  user.portrait = raw.portrait ?? '';
  user.avatar = portraitUrl(user.portrait);
  user.intro = raw.intro ?? '';
  user.role = raw.role_name || role;
  return user;
}

/** 非法信封或缺少该页面的数据结构返回 undefined，不能把协议失败伪装成空列表。 */
export function parseDirectory(text: string, kind: DirectoryKind): DirectoryData | undefined {
  try {
    const raw: RawDirectory = JSON.parse(text) as RawDirectory;
    if (raw === null || raw === undefined || Number(raw.error_code) !== 0) {
      return undefined;
    }
    const out: DirectoryData = new DirectoryData();
    if (kind === 'fans' || kind === 'following') {
      let rows: RawDirectoryUser[] | undefined = kind === 'fans' ? raw.user_list : raw.follow_list;
      const unavailable: boolean = rows === undefined && Number(raw.follow_list_switch) === 0;
      if (rows === undefined && ((raw.tips_text ?? '').length > 0 || unavailable)) { rows = []; }
      if (!Array.isArray(rows)) { return undefined; }
      for (const row of rows) {
        if (row !== null && row !== undefined) { out.users.push(userFromRaw(row)); }
      }
      out.hasMore = Number(kind === 'fans' ? raw.page?.has_more : raw.has_more) === 1;
      out.total = numberValue(kind === 'fans' ? raw.page?.total_count : raw.total_follow_num);
      // 隐私或折叠提示由服务端下发；空列表也保留这段说明。
      out.preface = raw.tips_text || (unavailable ? '该用户的列表暂不可见' : '');
    } else if (kind === 'team') {
      const team = raw.bawu_team_info;
      if (team === undefined || !Array.isArray(team.bawu_team_list)) { return undefined; }
      for (const group of team.bawu_team_list) {
        for (const row of group.role_info ?? []) {
          if (row !== null && row !== undefined) { out.users.push(userFromRaw(row, group.role_name ?? '')); }
        }
      }
      out.total = numberValue(team.total_num);
    } else if (kind === 'rules') {
      if (raw.forum === undefined) { return undefined; }
      out.title = raw.title ?? '';
      out.preface = raw.preface ?? '';
      // new_rules 是自定义吧规，default_rules 是官方默认吧规，两部分均保留原顺序。
      const rules: RawRule[] = (raw.new_rules ?? raw.rules ?? []).concat(raw.default_rules ?? []);
      for (const rule of rules) {
        const section: ForumRuleSection = new ForumRuleSection();
        section.title = rule.title ?? '';
        for (const paragraph of rule.content_list ?? []) {
          const pieces: ContentPiece[] = ContentPiece.listFromRaw(
            (paragraph.content ?? []).filter((piece: RawContentItem) => piece !== null && piece !== undefined));
          if (pieces.length > 0) { section.paragraphs.push(pieces); }
        }
        out.rules.push(section);
      }
    } else {
      const forum = raw.forum_info;
      if (forum === undefined || numberValue(forum.forum_id) <= 0) { return undefined; }
      out.forum.id = numberValue(forum.forum_id);
      out.forum.name = forum.forum_name ?? '';
      out.forum.avatar = forum.avatar ?? '';
      out.forum.slogan = forum.slogan ?? '';
      if (typeof forum.content === 'string') {
        out.forum.description = forum.content;
      } else if (Array.isArray(forum.content)) {
        const pieces: RawContentItem[] = [];
        for (const piece of forum.content) {
          if (piece !== null && piece !== undefined) {
            pieces.push({ type: Number(piece.type ?? 0), text: piece.text ?? '', link: piece.link ?? '' });
          }
        }
        out.forum.descriptionPieces = ContentPiece.listFromRaw(pieces);
        out.forum.description = pieces.map((piece: RawContentItem) => piece.text ?? '').join('');
      }
      out.forum.category = [forum.lv1_name ?? '', forum.lv2_name ?? ''].filter(
        (value: string) => value.length > 0).join(' · ');
      out.forum.members = numberValue(forum.member_count);
      out.forum.threads = numberValue(forum.thread_count);
    }
    return out;
  } catch (err) {
    return undefined;
  }
}

export function mergeDirectoryUsers(current: DirectoryUser[], incoming: DirectoryUser[]): DirectoryUser[] {
  const result: DirectoryUser[] = current.slice();
  const keys: Set<string> = new Set<string>();
  for (const row of current) { keys.add(`${row.uid}-${row.portrait}-${row.role}`); }
  for (const row of incoming) {
    const key: string = `${row.uid}-${row.portrait}-${row.role}`;
    if (!keys.has(key)) { result.push(row); keys.add(key); }
  }
  return result;
}

export class DirectoryRoleGroup {
  /** 角色名（服务端 `role_name` 原值；展示文案由页面用 `roleLabel()` 映射） */
  role: string = '';
  users: DirectoryUser[] = [];
}

/**
 * 把平铺的成员按 `role` 分组（**保持服务端给出的人物顺序**，组按首次出现顺序排）。
 *
 * 为什么放在模型层：吧务团队页要按角色分区展示（与吧成员页同视觉），
 * 分组规则要能被 Node 用例锁住 —— 规则只有一条：首现顺序，不排序、不合并同名角色。
 */
export function groupUsersByRole(users: DirectoryUser[]): DirectoryRoleGroup[] {
  const out: DirectoryRoleGroup[] = [];
  const indexOf: Map<string, number> = new Map<string, number>();
  for (let i = 0; i < users.length; i++) {
    const role: string = users[i].role;
    const at: number | undefined = indexOf.get(role);
    if (at === undefined) {
      const group: DirectoryRoleGroup = new DirectoryRoleGroup();
      group.role = role;
      group.users.push(users[i]);
      indexOf.set(role, out.length);
      out.push(group);
    } else {
      out[at].users.push(users[i]);
    }
  }
  return out;
}
