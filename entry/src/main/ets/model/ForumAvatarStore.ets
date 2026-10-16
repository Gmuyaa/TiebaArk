

const MAX_ENTRIES: number = 512;

const avatars: Map<string, string> = new Map();

const fetched: Set<string> = new Set();

export function putForumAvatar(forumName: string, avatarUrl: string): void {
  const name: string = forumName.trim();
  const url: string = avatarUrl.trim();
  if (name.length === 0 || url.length === 0) {
    return;
  }
  if (!avatars.has(name) && avatars.size >= MAX_ENTRIES) {

    const oldest: IteratorResult<string> = avatars.keys().next();
    if (!oldest.done) {
      avatars.delete(oldest.value);
    }
  }
  avatars.set(name, url);
}

export function getForumAvatar(forumName: string): string {
  const name: string = forumName.trim();
  if (name.length === 0) {
    return '';
  }
  return avatars.get(name) ?? '';
}

export function forumAvatarCount(): number {
  return avatars.size;
}

export function markForumAvatarFetched(forumName: string): void {
  const name: string = forumName.trim();
  if (name.length > 0) { fetched.add(name); }
}

export function isForumAvatarFetched(forumName: string): boolean {
  const name: string = forumName.trim();
  return name.length > 0 && fetched.has(name);
}

export function clearForumAvatars(): void {
  avatars.clear();
  fetched.clear();
}
