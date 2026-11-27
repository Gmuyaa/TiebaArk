/** 设置页关于分卷的说明子页与扩展面板：免责声明、数据使用说明、版本详情、第三方库、反馈与联系。 */

import { SettingsLayout } from '../common/appearance/SettingsLayout';
import {
  SupportGroup, ThirdPartyLibrary, supportGroups, thirdPartyLibraries
} from '../model/AboutInfo';
import { DisclaimerSection, disclaimerSections } from '../model/LaunchDisclaimer';
import { SettingsAboutItem, aboutItems, aboutNotes } from '../model/SettingsModel';
import { AppTheme } from '../theme/Theme';
import {
  SettingsCard, SettingsEntryRow, SettingsGroupTitle, SettingsInfoRow
} from './SettingsComponents';

@ComponentV2
export struct SettingsDisclaimerPane {
  build() {
    SettingsCard({
      content: (): void => { this.Rows(); }
    })
  }

  @Builder
  private Rows() {
    Column({ space: 16 }) {
      ForEach(disclaimerSections(), (section: DisclaimerSection, secIndex: number) => {
        Column({ space: 8 }) {
          Text(section.title)
            .fontSize(SettingsLayout.VALUE_SIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.TEXT_MAIN)
            .width('100%')
          ForEach(section.paragraphs, (paragraph: string, pIndex: number) => {
            Text(paragraph)
              .fontSize(SettingsLayout.SUB_SIZE)
              .fontColor(AppTheme.NOTE_TEXT)
              .lineHeight(20)
              .width('100%')
          }, (_p: string, pIndex: number) => `disclaimer_${secIndex}_${pIndex}`)
        }
        .width('100%')
      }, (section: DisclaimerSection, secIndex: number) => `disclaimer_sec_${secIndex}`)
    }
    .width('100%')
    .padding(SettingsLayout.ROW_PAD_L)
  }
}

@ComponentV2
export struct SettingsDataUsePane {
  build() {
    SettingsCard({
      content: (): void => { this.Rows(); }
    })
  }

  @Builder
  private Rows() {
    Column({ space: 14 }) {
      ForEach(aboutNotes(), (note: string, index: number) => {
        Text(note)
          .fontSize(SettingsLayout.SUB_SIZE)
          .fontColor(AppTheme.NOTE_TEXT)
          .lineHeight(20)
          .width('100%')
      }, (note: string, index: number) => `data_use_${index}`)
    }
    .width('100%')
    .padding(SettingsLayout.ROW_PAD_L)
  }
}

@ComponentV2
export struct SettingsVersionPane {
  build() {
    SettingsCard({
      content: (): void => { this.Rows(); }
    })
  }

  @Builder
  private Rows() {
    ForEach(aboutItems(), (item: SettingsAboutItem, index: number) => {
      SettingsInfoRow({
        label: item.label,
        value: item.value,
        showDivider: index < aboutItems().length - 1
      })
    }, (item: SettingsAboutItem) => `version_${item.label}`)
  }
}

@ComponentV2
export struct SettingsThirdPartyLibsPane {
  @Event onOpenLibrary: (lib: ThirdPartyLibrary) => void = (_lib: ThirdPartyLibrary): void => {};
  private readonly libraries: ThirdPartyLibrary[] = thirdPartyLibraries();

  private indexLabel(index: number): string {
    const num: number = index + 1;
    return num < 10 ? `0${num}` : `${num}`;
  }

  private countLabel(): string {
    const count: number = this.libraries.length;
    return count < 10 ? `0${count} 项` : `${count} 项`;
  }

  private accentBg(index: number): Resource {
    const slot: number = index % 4;
    if (slot === 0) { return AppTheme.MSG_BADGE_BLUE_BG; }
    if (slot === 1) { return AppTheme.MSG_BADGE_ORANGE_BG; }
    if (slot === 2) { return AppTheme.MSG_BADGE_GREEN_BG; }
    return AppTheme.MSG_BADGE_RED_BG;
  }

  private accentFg(index: number): Resource {
    const slot: number = index % 4;
    if (slot === 0) { return AppTheme.MSG_BADGE_BLUE_FG; }
    if (slot === 1) { return AppTheme.MSG_BADGE_ORANGE_FG; }
    if (slot === 2) { return AppTheme.MSG_BADGE_GREEN_FG; }
    return AppTheme.MSG_BADGE_RED_FG;
  }

  build() {
    Column() {
      Column({ space: 6 }) {
        Row() {
          Text('开源社区致谢')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.ACCENT_DARK)
            .layoutWeight(1)
          Text(this.countLabel())
            .fontSize(SettingsLayout.SUB_SIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.ACCENT_DARK)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text('贴吧Ark 使用或参考了以下开源项目，许可条款以各项目原始声明为准，点击卡片可前往开源主页。')
          .fontSize(SettingsLayout.SUB_SIZE)
          .fontColor(AppTheme.NOTE_TEXT)
          .lineHeight(20)
          .width('100%')
      }
      .width('100%')
      .padding(SettingsLayout.ROW_PAD_L)
      .backgroundColor(AppTheme.ACCENT_LIGHT)
      .borderRadius(SettingsLayout.CARD_RADIUS)

      ForEach(this.libraries, (lib: ThirdPartyLibrary, index: number) => {
        SettingsCard({
          marginTop: SettingsLayout.GROUP_GAP,
          content: (): void => { this.LibraryCardContent(lib, index); }
        })
      }, (lib: ThirdPartyLibrary) => `third_party_${lib.id}`)
    }
    .width('100%')
  }

  @Builder
  private LibraryCardContent(lib: ThirdPartyLibrary, index: number) {
    Row({ space: 12 }) {
      Column({ space: 6 }) {
        Text(this.indexLabel(index))
          .fontSize(SettingsLayout.SUB_SIZE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.accentFg(index))
        Column()
          .width(3)
          .height(56)
          .borderRadius(2)
          .backgroundColor(this.accentBg(index))
      }
      .alignItems(HorizontalAlign.Center)
      .padding({ top: 2 })

      Column({ space: 6 }) {
        Row({ space: 8 }) {
          Text(lib.name)
            .fontSize(SettingsLayout.LABEL_SIZE)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.TEXT_MAIN)
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.arrow_up_right'))
            .fontSize(15)
            .maxFontScale(1)
            .fontColor([AppTheme.CHEVRON_TINT])
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(lib.description)
          .fontSize(SettingsLayout.VALUE_SIZE)
          .fontColor(AppTheme.NOTE_TEXT)
          .lineHeight(20)
          .width('100%')

        Text(lib.author)
          .fontSize(SettingsLayout.SUB_SIZE)
          .fontColor(AppTheme.TEXT_MUTED)
          .width('100%')

        Flex({ wrap: FlexWrap.Wrap }) {
          Text(lib.version)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.accentFg(index))
            .backgroundColor(this.accentBg(index))
            .borderRadius(8)
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .margin({ right: 8, bottom: 4 })
          Text(lib.license)
            .fontSize(12)
            .fontColor(AppTheme.NOTE_TEXT)
            .backgroundColor(AppTheme.SURFACE_MUTED)
            .borderRadius(8)
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .margin({ bottom: 4 })
        }
        .width('100%')
        .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding(SettingsLayout.ROW_PAD_L)
    .onClick((): void => {
      this.onOpenLibrary(lib);
    })
  }
}

@ComponentV2
export struct SettingsFeedbackSection {
  @Event onTapIssues: () => void = (): void => {};
  @Event onOpenGroup: (group: SupportGroup) => void = (_group: SupportGroup): void => {};
  private readonly groups: SupportGroup[] = supportGroups();

  build() {
    Column() {
      SettingsGroupTitle({ title: '反馈与联系' })
      SettingsCard({
        content: (): void => { this.FeedbackRows(); }
      })
    }
    .width('100%')
  }

  @Builder
  private FeedbackRows() {
    SettingsEntryRow({
      label: 'GitHub Issues',
      showDivider: this.groups.length > 0,
      onTap: (): void => {
        this.onTapIssues();
      }
    })
    ForEach(this.groups, (group: SupportGroup, index: number) => {
      SettingsEntryRow({
        label: group.label,
        showDivider: index < this.groups.length - 1,
        onTap: (): void => {
          this.onOpenGroup(group);
        }
      })
    }, (group: SupportGroup) => `support_group_${group.id}`)
  }
}
