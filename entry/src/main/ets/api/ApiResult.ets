/** 通用请求结果与失败说明，不依赖平台传输。 */

/** 本地参数校验失败码，与服务端错误码区间区分开。 */
const ERROR_LOCAL: number = -1;

/** 请求结果基类：传输失败与业务失败必须分开报告，两者的排查方向不同。 */
export class ApiResult {
  ok: boolean = false;
  errorCode: number = 0;
  errorMessage: string = '';
  transportError: string = '';
  localMessage: string = '';

  describeFailure(): string {
    if (this.ok) {
      return '';
    }
    if (this.transportError.length > 0) {
      return `网络请求失败：${this.transportError}`;
    }
    if (this.errorCode === ERROR_LOCAL) {
      return this.localMessage;
    }
    return `贴吧返回错误 ${this.errorCode}：${this.errorMessage}`;
  }

  /** 本地校验失败：统一走这里，保证展示文案一致 */
  failLocal(message: string): void {
    this.errorCode = ERROR_LOCAL;
    this.localMessage = message;
  }

  failBusiness(code: number, message: string): void {
    this.errorCode = code;
    this.errorMessage = message;
  }
}
