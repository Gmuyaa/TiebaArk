import { common } from '@kit.AbilityKit';
import { AppTheme } from '../theme/Theme';
import { ComposeDraft } from '../viewmodel/ComposeVM';
import { ComposeForumOption, ComposeOptionsVM } from '../viewmodel/ComposeOptionsVM';
import { HotTopicItem, hotDiscussLabel } from '../model/HotTopic';
import { AvatarComponent } from './AvatarComponent';
import { ForumLevelBadge } from './ForumLevelBadge';
import { GlassCircleButton } from './GlassCircleButton';
import { SearchField } from './SearchField';

@ComponentV2
export struct ComposeOptionSheet {
  @Param kind: string = '';
  @Param draft: ComposeDraft = new ComposeDraft();
  @Event onClose: () => void = (): void => {};
  @Local vm: ComposeOptionsVM = new ComposeOptionsVM();

  aboutToAppear(): void {
    if (this.kind === '选择的吧') {
      void this.vm.loadForums(this.getUIContext().getHostContext() as common.UIAbilityContext);
    } else if (this.kind === '添加话题') { void this.vm.loadTopics(); }
  }
  aboutToDisappear(): void { this.vm.dispose(); }

  private forumStats(item: ComposeForumOption): string {
    const parts: string[] = [];
    if (item.followers.length > 0) { parts.push(`关注 ${item.followers}`); }
    if (item.posts.length > 0) { parts.push(`帖子 ${item.posts}`); }
    return parts.join('  ');
  }

  private chooseForum(item: ComposeForumOption): void {
    this.draft.forum = item.name; this.draft.forumId = item.id; this.onClose();
  }

  @Builder
  Header() {
    Row() {
      GlassCircleButton({ symbol: $r('sys.symbol.xmark'), diameter: 36, iconSize: 22, iconWeight: FontWeight.Regular,
        accessibilityLabel: '关闭' + this.kind, onTap: (): void => { this.onClose(); } })
      Text(this.kind).fontSize(20).fontWeight(FontWeight.Bold).fontColor(AppTheme.TEXT_MAIN)
        .layoutWeight(1).textAlign(TextAlign.Center)
      Blank().width(36)
    }.width('100%').height(56).padding({ left: 16, right: 16 })
  }

  @Builder
  Status(message: string, retry: () => void) {
    Column({ space: 10 }) {
      Text(message).fontSize(14).fontColor(AppTheme.TEXT_SUB).textAlign(TextAlign.Center)
      Button('重试').height(32).fontSize(13).fontColor(AppTheme.ACCENT_DARK)
        .backgroundColor(AppTheme.ACCENT_LIGHT).onClick(retry)
    }.width('100%').padding(20)
  }

  @Builder
  ForumRow(item: ComposeForumOption) {
    Row({ space: 12 }) {
      AvatarComponent({ url: item.avatar, avatarSize: 44, fallbackName: item.name })
      Column({ space: 5 }) {
        Row({ space: 5 }) {
          Text(item.name).fontSize(17).fontColor(AppTheme.TEXT_MAIN).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: '62%' })
          if (item.level > 0 && item.level <= 18) { ForumLevelBadge({ level: item.level }) }
          if (item.source.length > 0) {
            Text(item.source).fontSize(10).fontColor(AppTheme.ACCENT_DARK).maxLines(1)
              .padding({ left: 4, right: 4, top: 2, bottom: 2 }).backgroundColor(AppTheme.ACCENT_LIGHT)
          }
        }.width('100%')
        if (this.forumStats(item).length > 0) {
          Text(this.forumStats(item)).fontSize(12).fontColor(AppTheme.TEXT_SUB).maxLines(1)
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (this.draft.forum === item.name) {
        SymbolGlyph($r('sys.symbol.checkmark')).fontSize(18).fontColor([AppTheme.ACCENT])
      }
    }.width('100%').constraintSize({ minHeight: 56 }).padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .accessibilityGroup(true).accessibilityText('选择' + item.name + '吧')
      .onClick((): void => { this.chooseForum(item); })
  }

  private rowsOf(group: string): ComposeForumOption[] {
    if (group === 'search') { return this.vm.searchRows; }
    return this.vm.forumTab === 0 ? this.vm.recent : this.vm.followed;
  }

  @Builder
  ForumRows(group: string) {
    // 稳定分组标识进入Builder，在内部读取观察状态，避免初次空数组被捕获为快照。
    ForEach(this.rowsOf(group), (item: ComposeForumOption) => { this.ForumRow(item) },
      (item: ComposeForumOption): string => JSON.stringify(
        [item.name, item.id, item.avatar, item.level, item.followers, item.posts, item.source]))
  }

  @Builder
  ForumContent() {
    Column({ space: 12 }) {
      Row() {
        SearchField({ text: this.vm.query, placeholder: '搜索吧', minimumHeight: 40,
          onChange: (value: string): void => { this.vm.changeQuery(value); },
          onSubmit: (): void => { void this.vm.search(); } }).layoutWeight(1)
      }.padding({ left: 12, right: 12 })
      Scroll() {
        Column({ space: 12 }) {
          if (this.vm.query.trim().length > 0) {
            this.ForumRows('search')
            if (this.vm.searchLoading) { LoadingProgress().width(28).height(28).color(AppTheme.ACCENT) }
            if (this.vm.searchError.length > 0) {
              this.Status(this.vm.searchError, (): void => { void this.vm.search(this.vm.searchRows.length > 0); })
            } else if (!this.vm.searchLoading && !this.vm.searched) {
              Text('输入关键词后搜索').fontSize(14).fontColor(AppTheme.TEXT_SUB).padding(24)
            } else if (!this.vm.searchLoading && this.vm.searchRows.length === 0) {
              Text('没有找到相关吧').fontSize(14).fontColor(AppTheme.TEXT_SUB).padding(24)
            }
            if (this.vm.searchMore && !this.vm.searchLoading) {
              Button('加载更多').fontColor(AppTheme.ACCENT_DARK).backgroundColor(AppTheme.ACCENT_LIGHT)
                .onClick((): void => { void this.vm.search(true); })
            }
          } else {
            Column() {
              Row({ space: 24 }) {
                ForEach(['最近在逛', '我的关注'], (title: string, index: number) => {
                  Column({ space: 5 }) {
                    Text(title).fontSize(16).fontColor(this.vm.forumTab === index ? AppTheme.TEXT_MAIN : AppTheme.TEXT_SUB)
                    Row().width(14).height(3).borderRadius(2)
                      .backgroundColor(this.vm.forumTab === index ? AppTheme.ACCENT : Color.Transparent)
                  }.padding({ top: 14, bottom: 10 }).onClick((): void => { this.vm.forumTab = index; })
                }, (title: string): string => title)
              }.width('100%').padding({ left: 12 })
              this.ForumRows('personal')
              if (this.vm.forumsLoading) { LoadingProgress().width(28).height(28).color(AppTheme.ACCENT) }
              if (!this.vm.forumsLoading && this.vm.forumError.length === 0 &&
                (this.vm.forumTab === 0 ? this.vm.recent.length : this.vm.followed.length) === 0) {
                Text(this.vm.forumTab === 0 ? '还没有最近浏览的吧' : '暂无关注的吧')
                  .fontSize(14).fontColor(AppTheme.TEXT_SUB).padding(20)
              }
              if (this.vm.forumError.length > 0) {
                this.Status(this.vm.forumError, (): void => {
                  void this.vm.loadForums(this.getUIContext().getHostContext() as common.UIAbilityContext);
                })
              }
            }.width('100%').backgroundColor(AppTheme.CARD).borderRadius(16)
          }
        }.width('100%').padding({ left: 12, right: 12 })
      }.width('100%').layoutWeight(1).align(Alignment.TopStart).scrollBar(BarState.Off)
    }.width('100%').layoutWeight(1)
  }

  @Builder
  TopicRow(item: HotTopicItem) {
    Row({ space: 10 }) {
      AvatarComponent({ url: item.imageUrl, avatarSize: 34, fallbackName: item.name })
      Column({ space: 5 }) {
        Text('#' + item.name.replace(/^#|#$/g, '') + '#').fontSize(15).fontColor(AppTheme.TEXT_MAIN)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(hotDiscussLabel(item.discussCount)).fontSize(12).fontColor(AppTheme.TEXT_SUB)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Button(this.draft.topicId === item.id ? '已添加' : '添加').height(30).fontSize(13)
        .backgroundColor(AppTheme.ACCENT_LIGHT).fontColor(AppTheme.ACCENT_DARK)
        .onClick((): void => {
          this.draft.topic = item.name; this.draft.topicId = item.id; this.onClose();
        })
    }.width('100%').padding({ left: 12, right: 12, top: 10, bottom: 10 })
  }

  @Builder
  Topics() {
    Scroll() {
      Column() {
        Row({ space: 8 }) {
          Text('贴吧热榜').fontSize(18).fontWeight(FontWeight.Bold).fontColor(AppTheme.TEXT_MAIN).layoutWeight(1)
          if (!this.vm.allTopics && this.vm.topics.length > 10) {
            Text('全部 ›').fontSize(13).fontColor(AppTheme.TEXT_SUB)
              .onClick((): void => { this.vm.allTopics = true; })
          }
        }.width('100%').padding(14)
        ForEach(this.vm.allTopics ? this.vm.topics : this.vm.topics.slice(0, 10),
          (item: HotTopicItem) => { this.TopicRow(item) }, (item: HotTopicItem): string => String(item.id))
        if (this.vm.topicsLoading) { LoadingProgress().width(28).height(28).color(AppTheme.ACCENT) }
        if (this.vm.topicError.length > 0) {
          this.Status(this.vm.topicError, (): void => { void this.vm.loadTopics(); })
        } else if (!this.vm.topicsLoading && this.vm.topics.length === 0) {
          Text('暂无热榜话题').fontSize(14).fontColor(AppTheme.TEXT_SUB).padding(24)
        }
      }.width('100%').backgroundColor(AppTheme.CARD).borderRadius(16)
    }.width('100%').layoutWeight(1).align(Alignment.TopStart).scrollBar(BarState.Off)
      .padding({ left: 12, right: 12 })
  }

  @Builder
  RadioRow(title: string, description: string, selected: boolean, action: () => void) {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(title).fontSize(17).fontColor(AppTheme.TEXT_MAIN)
        if (description.length > 0) { Text(description).fontSize(13).fontColor(AppTheme.TEXT_SUB) }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Stack() {
        Circle().width(20).height(20).fill(selected ? AppTheme.ACCENT : Color.Transparent)
          .stroke(selected ? AppTheme.ACCENT : AppTheme.DIVIDER).strokeWidth(1)
        if (selected) { SymbolGlyph($r('sys.symbol.checkmark')).fontSize(13).fontColor([AppTheme.ON_ACCENT]) }
      }.width(24).height(24)
    }.width('100%').constraintSize({ minHeight: description.length > 0 ? 70 : 56 })
      .padding({ left: 20, right: 20, top: 10, bottom: 10 })
      .border({ width: { bottom: 0.5 }, color: AppTheme.DIVIDER })
      .accessibilityGroup(true).accessibilityText(title).accessibilitySelected(selected).onClick(action)
  }

  @Builder
  SmallOptions() {
    Column() {
      if (this.kind === '内容声明') {
        Text('内容声明').fontSize(19).fontWeight(FontWeight.Medium).fontColor(AppTheme.TEXT_MAIN).height(48)
        ForEach(['帖子含AI内容', '帖子原创声明'], (title: string) => {
          this.RadioRow(title, '', this.draft.declaration === title, (): void => {
            this.draft.declaration = this.draft.declaration === title ? '' : title; this.onClose();
          })
        }, (title: string): string => title)
      } else {
        this.RadioRow('全场景可见', '吧内、个人主页均可见', this.draft.visibility === '全场景可见', (): void => {
          this.draft.visibility = '全场景可见'; this.onClose();
        })
        this.RadioRow('个人主页不可见', '个人主页中该贴对其他用户不展示', this.draft.visibility === '个人主页不可见', (): void => {
          this.draft.visibility = '个人主页不可见'; this.onClose();
        })
      }
      Row().width('100%').height(8).backgroundColor(AppTheme.BG)
      Text('取消').fontSize(17).fontColor(AppTheme.TEXT_MAIN).width('100%').height(54).textAlign(TextAlign.Center)
        .onClick((): void => { this.onClose(); })
    }.width('100%').backgroundColor(AppTheme.CARD)
  }

  build() {
    Column() {
      if (this.kind === '设置展示范围' || this.kind === '内容声明') { this.SmallOptions() }
      else {
        this.Header()
        if (this.kind === '选择的吧') { this.ForumContent() }
        else { this.Topics() }
      }
    }.width('100%').height('100%').backgroundColor(
      this.kind === '设置展示范围' || this.kind === '内容声明' ? AppTheme.CARD : AppTheme.BG)
  }
}
