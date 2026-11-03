import { ForumCoverDetail, forumCoverDetail } from '../model/ForumCoverDetail';

/** 只接收已读取的像素；不导入UI、网络或页面状态，整段扫描在任务池执行。 */
@Concurrent
export function analyzeForumCover(buffer: ArrayBuffer, width: number, height: number, stride: number): ForumCoverDetail {
  return forumCoverDetail(new Uint8Array(buffer), width, height, stride);
}
