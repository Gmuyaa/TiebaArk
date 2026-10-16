

const ERROR_LOCAL: number = -1;

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

  failLocal(message: string): void {
    this.errorCode = ERROR_LOCAL;
    this.localMessage = message;
  }

  failBusiness(code: number, message: string): void {
    this.errorCode = code;
    this.errorMessage = message;
  }
}
