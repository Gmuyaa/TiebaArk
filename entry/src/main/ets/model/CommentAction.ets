import { ContentKind, ContentPiece, PostItem, SubPostItem, UserBrief } from './ThreadDetail';

/** 长按操作的真实目标，楼中楼保留所属一级评论 ID。 */
export class CommentTarget {
  tid: number = 0;
  pid: number = 0;
  parentPid: number = 0;
  title: string = '';
  author: UserBrief = new UserBrief();
  contents: ContentPiece[] = [];
  replyToName: string = '';
}

export function postCommentTarget(post: PostItem, tid: number, title: string): CommentTarget {
  const target: CommentTarget = new CommentTarget();
  target.tid = tid;
  target.pid = post.pid;
  target.title = title;
  target.author = post.author;
  target.contents = post.contents;
  return target;
}

export function subCommentTarget(sub: SubPostItem, tid: number, parentPid: number,
  title: string): CommentTarget {
  const target: CommentTarget = new CommentTarget();
  target.tid = tid;
  target.pid = sub.pid;
  target.parentPid = parentPid;
  target.title = title;
  target.author = sub.author;
  target.contents = sub.contents;
  target.replyToName = sub.replyToName;
  return target;
}

export function commentText(target: CommentTarget): string {
  let text: string = target.replyToName.length > 0 ? `回复 ${target.replyToName}：` : '';
  for (const piece of target.contents) {
    if (piece.kind === ContentKind.IMAGE) {
      continue;
    } else if (piece.kind === ContentKind.EMOJI) {
      text += `[${piece.emojiName.length > 0 ? piece.emojiName : piece.text}]`;
    } else if (piece.kind === ContentKind.LINK) {
      text += piece.text;
      if (piece.link.length > 0 && piece.text !== piece.link) { text += ` (${piece.link})`; }
    } else {
      text += piece.text;
    }
  }
  return text.trim();
}

export function commentLink(target: CommentTarget): string {
  if (!Number.isSafeInteger(target.tid) || target.tid <= 0 ||
    !Number.isSafeInteger(target.pid) || target.pid <= 0) { return ''; }
  if (target.parentPid > 0) {
    if (!Number.isSafeInteger(target.parentPid)) { return ''; }
    return `https://tieba.baidu.com/p/${target.tid}?pid=${target.parentPid}&cid=${target.pid}#${target.pid}`;
  }
  return `https://tieba.baidu.com/p/${target.tid}?pid=${target.pid}#${target.pid}`;
}
