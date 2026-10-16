/** 帖子文字层级：正文 15 fp，昵称比正文小 2 fp，标题比正文大 2 fp。 */
export const POST_BODY_SIZE: number = 15;
export const POST_NICKNAME_SIZE: number = POST_BODY_SIZE - 2;
export const POST_TITLE_SIZE: number = POST_BODY_SIZE + 2;

/** 评论区试调：一级评论清晰，楼中楼保持紧凑。 */
export const COMMENT_BODY_SIZE: number = 16;
export const COMMENT_NICKNAME_SIZE: number = 14;
export const SUB_REPLY_BODY_SIZE: number = 14;
export const SUB_REPLY_LINE_HEIGHT: number = 21;
