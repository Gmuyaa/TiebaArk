/** 删除成功后的进程内失效通知，不保存帖子、账号或凭据。 */
let revision: number = 0;

export function contentDeletionRevision(): number { return revision; }

export function noteContentDeleted(): void { revision++; }
