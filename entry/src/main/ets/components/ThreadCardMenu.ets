

import { UIContext } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { normalizeForumName } from '../model/ThreadBlock';
import { ThreadBrief } from '../model/ThreadList';
import { threadBlockActions } from '../viewmodel/ThreadBlockActions';

function forumMenuLabel(forumName: string): string {
  const value: string = normalizeForumName(forumName);
  return value.length > 0 ? `屏蔽：${value}吧` : '屏蔽该吧';
}

function toast(ui: UIContext, message: string): void {
  ui.getPromptAction().showToast({ message });
}

export function buildThreadCardMenu(ui: UIContext, thread: ThreadBrief): MenuElement[] {
  const context: common.UIAbilityContext = ui.getHostContext() as common.UIAbilityContext;
  const menu: MenuElement[] = [];
  menu.push({
    value: forumMenuLabel(thread.sourceForum),
    action: (): void => { void confirmBlockForum(ui, context, thread); }
  });
  menu.push({
    value: '屏蔽该用户',
    action: (): void => { void confirmBlockAuthor(ui, context, thread); }
  });
  menu.push({
    value: '隐藏该贴',
    action: (): void => { void confirmHideThread(ui, context, thread); }
  });
  return menu;
}

async function confirmBlockForum(ui: UIContext, context: common.UIAbilityContext,
  thread: ThreadBrief): Promise<void> {
  const name: string = normalizeForumName(thread.sourceForum);
  const confirm = await ui.getPromptAction().showDialog({
    title: forumMenuLabel(thread.sourceForum),
    message: '该吧的帖子不再出现在本机列表里。屏蔽优先写服务端（官方客户端同步生效）；'
      + '服务端未确认时会退回本机屏蔽并明确提示。',
    buttons: [{ text: '取消', color: $r('app.color.detail_text_secondary') },
      { text: '屏蔽', color: $r('app.color.detail_accent') }]
  });
  if (confirm.index !== 1) { return; }
  const message: string = await threadBlockActions.blockForum(context, thread);
  toast(ui, message.length > 0 ? message : (name.length > 0 ? `已屏蔽${name}吧` : '已屏蔽该吧'));
}

async function confirmBlockAuthor(ui: UIContext, context: common.UIAbilityContext,
  thread: ThreadBrief): Promise<void> {
  const who: string = thread.authorName.length > 0 ? thread.authorName : '该用户';
  const confirm = await ui.getPromptAction().showDialog({
    title: `屏蔽该用户`,
    message: `将${who}加入贴吧黑名单（拉黑）：限制关注、互动和私信，并隐藏其内容。`,
    buttons: [{ text: '取消', color: $r('app.color.detail_text_secondary') },
      { text: '屏蔽', color: $r('app.color.detail_accent') }]
  });
  if (confirm.index !== 1) { return; }
  const message: string = await threadBlockActions.blockAuthor(context, thread);
  toast(ui, message.length > 0 ? message : '已屏蔽该用户');
}

async function confirmHideThread(ui: UIContext, context: common.UIAbilityContext,
  thread: ThreadBrief): Promise<void> {
  const confirm = await ui.getPromptAction().showDialog({
    title: '隐藏该贴',
    message: '仅在本机隐藏这一条帖子（不写服务端）。可在「设置 → 隐私设置 → 拉黑与隐藏」里恢复。',
    buttons: [{ text: '取消', color: $r('app.color.detail_text_secondary') },
      { text: '隐藏', color: $r('app.color.detail_accent') }]
  });
  if (confirm.index !== 1) { return; }
  const message: string = await threadBlockActions.hideThread(context, thread);
  toast(ui, message.length > 0 ? message : '已隐藏该贴');
}
