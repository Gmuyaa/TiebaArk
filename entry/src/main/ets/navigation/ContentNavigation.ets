
import { common } from '@kit.AbilityKit';
import { ContentDestination, ContentDestinationKind, ContentPiece, contentDestination } from '../model/ThreadDetail';
import { NavigationService } from './AppNavigation';

export function openContentPiece(piece: ContentPiece, uiContext: UIContext): void {
  const target: ContentDestination = contentDestination(piece);
  if (target.kind === ContentDestinationKind.THREAD) {
    NavigationService.openThreadDetail({ tid: target.tid });
  } else if (target.kind === ContentDestinationKind.FORUM) {
    NavigationService.openForum({ forumName: target.word });
  } else if (target.kind === ContentDestinationKind.SEARCH) {
    NavigationService.openSearchResult({ word: target.word });
  } else if (target.kind === ContentDestinationKind.WEB) {
    const context: common.UIAbilityContext = uiContext.getHostContext() as common.UIAbilityContext;
    context.openLink(target.url).catch(() => {
      uiContext.getPromptAction().showToast({ message: '无法打开链接，请检查浏览器是否可用' });
    });
  } else {
    uiContext.getPromptAction().showToast({ message: '链接地址无效或暂不支持' });
  }
}
