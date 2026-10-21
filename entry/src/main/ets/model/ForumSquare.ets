/** 当前官方广场前端 getForumSquare：目录、二级分类和列表来自同一响应。 */
interface RawSquareForum {
  forum_id?: string | number;
  forum_name?: string;
  avatar?: string;
  member_count?: string | number;
  thread_count?: string | number;
  is_like?: string | number;
}
interface RawSquarePage {
  current_page?: string | number;
  has_more?: string | number;
}
interface RawSquare {
  page_structure?: string[];
  class_name?: string;
  second_class_list?: string[];
  forum_info?: RawSquareForum[];
  page?: RawSquarePage;
}
export class SquareForum {
  id: string = '';
  name: string = '';
  avatar: string = '';
  members: string = '';
  threads: string = '';
  following: boolean | undefined = undefined;
  followId(): number {
    const id: number = Number(this.id);
    return Number.isSafeInteger(id) && id > 0 ? id : 0;
  }
}
export class SquareCategory {
  id: string = '';
  name: string = '';
}
export class ForumSquareData {
  categories: SquareCategory[] = [];
  subcategories: string[] = [];
  category: string = '';
  page: number = 0;
  forums: SquareForum[] = [];
  hasMore: boolean = false;
  error: string = '';
  schema: string = '';
}
function parseForums(raw: RawSquareForum[]): SquareForum[] {
  const seen: Set<string> = new Set();
  const result: SquareForum[] = [];
  for (const row of raw) {
    const item: SquareForum = new SquareForum();
    item.id = String(row.forum_id ?? '');
    item.name = row.forum_name?.trim() ?? '';
    if (!/^\d+$/.test(item.id) || item.id === '0' || item.name.length === 0 || seen.has(item.id)) { continue; }
    seen.add(item.id);
    item.avatar = row.avatar ?? '';
    item.members = row.member_count === undefined ? '' : String(row.member_count);
    item.threads = row.thread_count === undefined ? '' : String(row.thread_count);
    item.following = String(row.is_like) === '1' ? true : String(row.is_like) === '0' ? false : undefined;
    result.push(item);
  }
  return result;
}
export function parseForumSquare(text: string, requested: string, page: number): ForumSquareData {
  const raw: RawSquare = JSON.parse(text) as RawSquare;
  const result: ForumSquareData = new ForumSquareData();
  result.schema = `keys=${Object.keys(raw).join(',')} page=${String(raw.page?.current_page)} ` +
    `more=${String(raw.page?.has_more)} class=${raw.class_name ?? ''} forums=${Array.isArray(raw.forum_info) ? raw.forum_info.length : -1}`;
  if (!Array.isArray(raw.forum_info) || !Array.isArray(raw.page_structure) ||
    !Array.isArray(raw.second_class_list) || !raw.page ||
    !['0', '1'].includes(String(raw.page.has_more)) ||
    (raw.page.current_page === undefined ? raw.class_name !== '推荐' : Number(raw.page.current_page) !== page)) {
    result.error = '广场响应不完整'; return result;
  }
  result.category = raw.class_name ?? '';
  // 匿名推荐可能被服务端明确转为热门；仅首屏接受此回显，并同步选中真实分类。
  if (result.category !== requested && !(requested === '推荐' && page === 1 && result.category === '热门')) {
    result.error = '服务端未确认广场分类'; return result;
  }
  result.forums = parseForums(raw.forum_info);
  result.hasMore = String(raw.page.has_more) === '1';
  result.page = page;
  const seen: Set<string> = new Set();
  for (const name of raw.page_structure) {
    if (typeof name !== 'string' || name.trim().length === 0 || seen.has(name)) { continue; }
    const item: SquareCategory = new SquareCategory();
    item.id = name; item.name = name;
    seen.add(name); result.categories.push(item);
  }
  if (!seen.has(result.category)) { result.error = '广场目录缺少当前分类'; return result; }
  result.subcategories = raw.second_class_list.filter((name: string): boolean =>
    typeof name === 'string' && name.trim().length > 0 && name !== '全部');
  result.subcategories = Array.from(new Set(result.subcategories));
  if (result.subcategories.length > 0) { result.subcategories.unshift('全部'); }
  return result;
}
