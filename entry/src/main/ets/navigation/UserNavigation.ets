import { profilePortrait } from '../model/PageDirectory';
import { NavigationService } from './AppNavigation';

export function openUserByIdentity(uid: number, portrait: string, name: string, ui: UIContext): void {
  const token: string = profilePortrait(portrait);
  if (uid <= 0 && token.length === 0) {
    ui.getPromptAction().showToast({ message: '没有取得用户身份，暂时无法打开主页' });
    return;
  }
  NavigationService.openUser({ uid, portrait: token, name });
}
