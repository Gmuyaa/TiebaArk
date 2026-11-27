import { ThreadPollInfo, ThreadPollOption } from '../model/ThreadDetail';
import { AppTheme } from '../theme/Theme';

@ComponentV2
export struct ThreadPollCard {
  @Param @Require poll: ThreadPollInfo;
  @Param pending: boolean = false;
  @Param loggedIn: boolean = false;
  @Param onVote: (optionIds: number[]) => void = (): void => {};
  @Param onOpenImage: (url: string) => void = (): void => {};

  @Local selectedIds: number[] = [];

  private showResult(): boolean {
    return this.poll.isPolled || this.poll.isEnded();
  }

  private toggleOption(optionId: number): void {
    if (this.showResult() || this.pending) { return; }
    if (this.poll.isMulti) {
      const idx: number = this.selectedIds.indexOf(optionId);
      if (idx >= 0) {
        const next: number[] = this.selectedIds.slice();
        next.splice(idx, 1);
        this.selectedIds = next;
      } else {
        this.selectedIds = this.selectedIds.concat([optionId]);
      }
    } else {
      this.selectedIds = [optionId];
    }
  }

  private isSelected(optionId: number): boolean {
    return this.selectedIds.indexOf(optionId) >= 0;
  }

  private denominator(): number {
    let sum: number = 0;
    for (let i: number = 0; i < this.poll.options.length; i++) {
      sum += this.poll.options[i].num;
    }
    if (sum > 0) { return sum; }
    return this.poll.totalPoll > 0 ? this.poll.totalPoll : Math.max(1, this.poll.totalNum);
  }

  private percentOf(option: ThreadPollOption): number {
    const total: number = this.denominator();
    if (total <= 0 || option.num <= 0) { return 0; }
    return Math.min(100, Math.round((option.num * 100) / total));
  }

  private statusLabel(): string {
    const mode: string = this.poll.isMulti ? '多选' : '单选';
    if (this.poll.isEnded()) { return `${mode} · 已结束`; }
    if (this.poll.isPolled) { return `${mode} · 已投票`; }
    return mode;
  }

  private deadlineText(): string {
    if (this.poll.tips.length > 0) { return this.poll.tips; }
    if (this.poll.isEnded()) { return '投票已截止'; }
    if (this.poll.endTimeSec > 0) {
      const d: Date = new Date(this.poll.endTimeSec * 1000);
      const mm: string = String(d.getMonth() + 1).padStart(2, '0');
      const dd: string = String(d.getDate()).padStart(2, '0');
      const hh: string = String(d.getHours()).padStart(2, '0');
      const min: string = String(d.getMinutes()).padStart(2, '0');
      return `${d.getFullYear()}-${mm}-${dd} ${hh}:${min} 截止`;
    }
    return '';
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text(this.poll.title.length > 0 ? this.poll.title : '投票')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_MAIN)
          .layoutWeight(1)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.statusLabel())
          .fontSize(11)
          .fontColor(this.poll.isEnded() ? AppTheme.TEXT_MUTED : AppTheme.ACCENT)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .backgroundColor(this.poll.isEnded() ? AppTheme.DIVIDER : AppTheme.ACCENT_LIGHT)
          .borderRadius(999)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Column({ space: 8 }) {
        ForEach(this.poll.options, (option: ThreadPollOption) => {
          this.OptionRow(option)
        }, (option: ThreadPollOption) => `${option.id}_${option.num}_${option.isPolled ? 1 : 0}`)
      }
      .width('100%')

      Row({ space: 8 }) {
        Text(`${this.poll.totalNum} 人参与${this.deadlineText().length > 0 ? ` · ${this.deadlineText()}` : ''}`)
          .fontSize(12)
          .fontColor(AppTheme.TEXT_MUTED)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (!this.showResult()) {
          Text(this.pending ? '提交中...' : (this.loggedIn ? '投票' : '登录后投票'))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.selectedIds.length > 0 && !this.pending ? Color.White : AppTheme.TEXT_MUTED)
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            .backgroundColor(this.selectedIds.length > 0 && !this.pending ? AppTheme.ACCENT : AppTheme.DIVIDER)
            .borderRadius(999)
            .onClick((): void => {
              if (this.pending || this.selectedIds.length === 0) { return; }
              this.onVote(this.selectedIds.slice());
            })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(12)
    .backgroundColor(AppTheme.SURFACE_MUTED)
    .border({ width: 0.5, color: AppTheme.DIVIDER })
    .borderRadius(12)
  }

  @Builder
  OptionRow(option: ThreadPollOption) {
    if (this.showResult()) {
      Column({ space: 6 }) {
        Row({ space: 8 }) {
          if (option.image.length > 0) {
            Image(option.image)
              .width(36)
              .height(36)
              .objectFit(ImageFit.Cover)
              .borderRadius(6)
              .onClick((): void => { this.onOpenImage(option.image); })
          }
          Row({ space: 6 }) {
            Text(option.text.length > 0 ? option.text : `选项 ${option.id}`)
              .fontSize(14)
              .fontWeight(option.isPolled ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(option.isPolled ? AppTheme.ACCENT : AppTheme.TEXT_MAIN)
              .layoutWeight(1)
            if (option.isPolled) {
              Text('已选')
                .fontSize(11)
                .fontColor(AppTheme.ACCENT)
            }
          }
          .layoutWeight(1)

          Text(`${this.percentOf(option)}% · ${option.num}票`)
            .fontSize(12)
            .fontWeight(option.isPolled ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(option.isPolled ? AppTheme.ACCENT : AppTheme.TEXT_SUB)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Row() {
          Row()
            .width(`${this.percentOf(option)}%`)
            .height(4)
            .borderRadius(2)
            .backgroundColor(option.isPolled ? AppTheme.ACCENT : AppTheme.TEXT_MUTED)
        }
        .width('100%')
        .height(4)
        .borderRadius(2)
        .backgroundColor(AppTheme.DIVIDER)
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      .backgroundColor(AppTheme.CARD)
      .border({
        width: option.isPolled ? 1 : 0.5,
        color: option.isPolled ? AppTheme.ACCENT : AppTheme.DIVIDER
      })
      .borderRadius(8)
    } else {
      Row({ space: 10 }) {
        Stack({ alignContent: Alignment.Center }) {
          if (this.isSelected(option.id)) {
            Row()
              .width(8)
              .height(8)
              .borderRadius(this.poll.isMulti ? 2 : 4)
              .backgroundColor(Color.White)
          }
        }
        .width(18)
        .height(18)
        .borderRadius(this.poll.isMulti ? 4 : 9)
        .backgroundColor(this.isSelected(option.id) ? AppTheme.ACCENT : Color.Transparent)
        .border({
          width: 1.5,
          color: this.isSelected(option.id) ? AppTheme.ACCENT : AppTheme.TEXT_MUTED
        })

        if (option.image.length > 0) {
          Image(option.image)
            .width(36)
            .height(36)
            .objectFit(ImageFit.Cover)
            .borderRadius(6)
            .onClick((): void => { this.onOpenImage(option.image); })
        }

        Text(option.text.length > 0 ? option.text : `选项 ${option.id}`)
          .fontSize(14)
          .fontColor(this.isSelected(option.id) ? AppTheme.ACCENT : AppTheme.TEXT_MAIN)
          .layoutWeight(1)
      }
      .width('100%')
      .constraintSize({ minHeight: 42 })
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      .backgroundColor(this.isSelected(option.id) ? AppTheme.ACCENT_LIGHT : AppTheme.CARD)
      .border({
        width: this.isSelected(option.id) ? 1 : 0.5,
        color: this.isSelected(option.id) ? AppTheme.ACCENT : AppTheme.DIVIDER
      })
      .borderRadius(8)
      .alignItems(VerticalAlign.Center)
      .onClick((): void => { this.toggleOption(option.id); })
    }
  }
}
