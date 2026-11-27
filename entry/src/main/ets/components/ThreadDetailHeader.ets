import { openUserByIdentity } from '../navigation/UserNavigation';
import { POST_NICKNAME_SIZE } from '../common/appearance/PostTypography';
import { forumLevelStore } from '../common/appearance/ForumLevelStore';
import { ReplySortType, UserBrief } from '../model/ThreadDetail';
import { AppTheme as BrandTheme, DetailTheme as AppTheme } from '../theme/Theme';
import { AvatarComponent } from './AvatarComponent';
import { FollowButton } from './FollowButton';
import { ForumLevelBadge } from './ForumLevelBadge';
import { ThreadBawuBadge } from './ThreadBawuBadge';

@ComponentV2
export struct ThreadAuthorBar {
  @Param @Require author: UserBrief;
  @Param levelText: string = '';
  @Param metaLine: string = '';

  @Builder
  LevelChip(text: string) {
    Text(text)
      .fontSize(10)
      .fontColor(AppTheme.ACCENT_DARK)
      .backgroundColor(AppTheme.ACCENT_LIGHT)
      .borderRadius(5)
      .padding({ left: 5, right: 5, top: 2, bottom: 2 })
      .margin({ right: 6 })
  }

  build() {
    Row({ space: 10 }) {
      AvatarComponent({ url: this.author.portraitUrl, avatarSize: 40, fallbackName: this.author.displayName })
        .id('thread-author-avatar').flexShrink(0)
        .onClick(() => {
          openUserByIdentity(this.author.id, this.author.portraitUrl, this.author.displayName, this.getUIContext());
        })

      Column({ space: 4 }) {
        Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
          Text(this.author.displayName.length > 0 ? this.author.displayName : '匿名用户')
            .fontSize(POST_NICKNAME_SIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.TEXT_MAIN)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .id('thread-author-name')
            .onClick(() => {
              openUserByIdentity(this.author.id, this.author.portraitUrl, this.author.displayName, this.getUIContext());
            })
            .margin({ right: 6 })

          if (this.levelText.length > 0) {
            if (forumLevelStore.style === 1 && this.author.level > 0) {
              ForumLevelBadge({ level: this.author.level, levelName: this.author.levelName })
            } else {
              this.LevelChip(this.levelText)
            }
          }
          if (this.author.isBawu) {
            Row() {
              ThreadBawuBadge({
                text: this.author.bawuTitle.length > 0 ? this.author.bawuTitle : '吧务',
                textColor: AppTheme.ACCENT_DARK,
                backgroundColor: AppTheme.ACCENT_LIGHT,
                borderColor: AppTheme.ACCENT
              })
            }
            .margin({ right: 6 })
          }
        }
        .width('100%')
        .id('thread-author-identities')

        if (this.metaLine.length > 0) {
          Text(this.metaLine)
            .fontSize(12)
            .fontColor(AppTheme.TEXT_SUB)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .id('thread-author-meta')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .id('thread-author-info')

      FollowButton({
        kind: 'user',
        targetId: this.author.id,
        portrait: this.author.portraitUrl,
        targetName: this.author.displayName
      })
        .id('thread-author-follow').flexShrink(0)
    }
    .width('100%')
    .padding({ bottom: 2 })
    .alignItems(VerticalAlign.Center)
  }
}

@ComponentV2
export struct ThreadMoreMenu {
  @Param sortType: ReplySortType = ReplySortType.ASC;
  @Param canManageReplyPermission: boolean = false;
  @Param canDeleteThread: boolean = false;
  @Param deletePending: boolean = false;
  @Event onToggleOnlyAuthor: () => void = (): void => {};
  @Event onJumpFloor: () => void = (): void => {};
  @Event onJumpTop: () => void = (): void => {};
  @Event onShare: () => void = (): void => {};
  @Event onCommentPermission: () => void = (): void => {};
  @Event onDeleteThread: () => void = (): void => {};

  build() {
    Column({ space: 2 }) {
      Text(this.sortType === ReplySortType.ONLY_AUTHOR ? '显示全部回复' : '只看楼主')
        .fontSize(14)
        .textAlign(TextAlign.Center)
        .fontColor(AppTheme.TEXT_MAIN)
        .width('100%')
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .onClick((): void => { this.onToggleOnlyAuthor(); })

      Text('跳转楼层')
        .fontSize(14)
        .textAlign(TextAlign.Center)
        .fontColor(AppTheme.TEXT_MAIN)
        .width('100%')
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .onClick((): void => { this.onJumpFloor(); })

      Text('回到顶部')
        .fontSize(14)
        .textAlign(TextAlign.Center)
        .fontColor(AppTheme.TEXT_MAIN)
        .width('100%')
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .onClick((): void => { this.onJumpTop(); })

      Text('分享')
        .fontSize(14)
        .textAlign(TextAlign.Center)
        .fontColor(AppTheme.TEXT_MAIN)
        .width('100%')
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .onClick((): void => { this.onShare(); })

      if (this.canManageReplyPermission) {
        Text('评论权限')
          .fontSize(14)
          .textAlign(TextAlign.Center)
          .fontColor(AppTheme.TEXT_MAIN)
          .width('100%')
          .padding({ left: 14, right: 14, top: 12, bottom: 12 })
          .enabled(!this.deletePending)
          .id('thread-comment-permission-entry')
          .onClick((): void => { this.onCommentPermission(); })
      }
      if (this.canDeleteThread) {
        Text(this.deletePending ? '正在删除…' : '删除帖子')
          .fontSize(14)
          .textAlign(TextAlign.Center)
          .fontColor(BrandTheme.DANGER_TEXT)
          .width('100%')
          .padding({ left: 14, right: 14, top: 12, bottom: 12 })
          .enabled(!this.deletePending)
          .id('thread-delete-entry')
          .onClick((): void => { this.onDeleteThread(); })
      }
    }
    .width(120)
    .padding({ top: 4, bottom: 4 })
    .id('thread-more-menu')
  }
}
