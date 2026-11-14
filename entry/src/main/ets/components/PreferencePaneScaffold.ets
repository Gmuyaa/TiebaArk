/**
 * 设置子页的公共渲染脚手架：说明文字 + 设置卡片 + 读取/保存失败行。
 *
 * 6 个偏好子页（个人资料、官方消息、隐私标记、小尾巴、图片水印等）原本各写一遍
 * 同样的「卡片 + 错误行 + 重试」，文案与 `kind` 容易改一处漏一处。行内容仍由各页自己的
 * `@Builder` 提供（`rows` 尾随闭包），本组件只管外壳。
 *
 * 不适用的两个：
 * - `MessageSettingsPane`：说明文字位于卡片与错误行**之间**；
 * - `AppPermissionsPane`：两张卡片、两条各自重试的错误行。
 * 这两处保留自己的布局，不做硬套。
 */
import { SettingsCard, SettingsNote, SettingsStatusKind, SettingsStatusLine } from './SettingsComponents';

@ComponentV2
export struct PreferencePaneScaffold {
  /** 卡片上/下方的说明；空串不渲染 */
  @Param note: string = '';
  /** true = 说明放在卡片与错误行之后 */
  @Param noteAfter: boolean = false;
  /** 失败提示；空串不渲染 */
  @Param message: string = '';
  /** 失败行按钮文案：读取失败用「重新读取」，保存失败用「重试」 */
  @Param retryLabel: string = '重试';
  /** 失败行点击：由各页决定重读还是重存 */
  @Event onRetry: () => void = (): void => {};

  @BuilderParam rows: () => void = this.EmptyRows;

  @Builder
  EmptyRows() {
  }

  build() {
    Column() {
      if (!this.noteAfter && this.note.length > 0) {
        SettingsNote({ text: this.note })
      }
      SettingsCard({
        content: (): void => { this.rows() }
      })
      if (this.message.length > 0) {
        SettingsStatusLine({
          kind: SettingsStatusKind.ERROR,
          message: this.message,
          retryLabel: this.retryLabel,
          onRetry: (): void => {
            this.onRetry();
          }
        })
      }
      if (this.noteAfter && this.note.length > 0) {
        SettingsNote({ text: this.note })
      }
    }
    .width('100%')
  }
}
