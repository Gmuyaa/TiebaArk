/**
 * 页面级请求收口。
 *
 * 首页吧头像与热榜卡原先各自在组件/页面里 `new TiebaApi()`，并在闭包里拼设备身份、
 * 会话与账号比对——「怎么发」被写进了「画什么」的层。这里收成两个函数：UI 只表达
 * 「我要这张图 / 这张卡」。并发、冷却、去重仍由调用方决定（`model/ForumAvatarQueue`
 * 的限额队列、`HotTopicCardsVM` 的两槽补取），本模块不持有任何请求状态。
 */
import { common } from '@kit.AbilityKit';
import { TiebaApi } from '../api/TiebaApi';
import { authSession } from '../auth/AuthSession';
import { HotTopicCardInfo } from '../model/HotTopicCard';
import { TiebaDevice } from '../net/TiebaParams';
import { DeviceIdentity } from '../utils/DeviceIdentity';

/** 无状态实例：设备身份与会话每次调用时取当前值，不缓存账号。 */
const api: TiebaApi = new TiebaApi();

/**
 * 按吧名（可选 fid）取吧头像。
 * 双路取图（getforumdetail 优先、frs/page 回退）与失败兜底在 `TiebaApi.fetchForumAvatar` 内。
 */
export async function fetchForumAvatarForPage(context: common.UIAbilityContext, name: string,
  forumId: number, tag: string): Promise<string> {
  const device: TiebaDevice = await DeviceIdentity.ensure(context);
  return api.fetchForumAvatar(device, authSession.session(), name, forumId, tag);
}

/**
 * 取热榜卡片的补充字段；非 200 与失败都返回 undefined，由调用方保留原列表。
 * 账号在设备身份解析之后比对一次：解析期间换号的结果不能落到新账号的列表上。
 */
export async function fetchHotTopicCardForPage(context: common.UIAbilityContext, tid: number,
  account: string): Promise<HotTopicCardInfo | undefined> {
  const device: TiebaDevice = await DeviceIdentity.ensure(context);
  if (account !== authSession.sessionKey()) { return undefined; }
  const response = await api.fetchHotTopicCard(device, authSession.session(), tid);
  return response.ok ? response.data : undefined;
}
