/** 通用请求结果与失败说明，不依赖平台传输。 */

/** 本地参数校验失败码，与服务端错误码区间区分开。 */
const ERROR_LOCAL: number = -1;

/**
 * 请求结果基类。
 *
 * 区分"传输失败"与"业务失败"——两者的排查方向完全不同，混在一起会误导。
 * 三个端点（列表 / 详情 / 楼中楼）的这部分逻辑一字不差，抽出来免得改一处漏两处。
 */
export class ApiResult {
  /** 是否拿到了可用数据 */
  ok: boolean = false;
  /** 服务端业务错误码；0 表示无业务错误 */
  errorCode: number = 0;
  errorMessage: string = '';
  /** 传输层错误描述，仅网络失败时非空 */
  transportError: string = '';
  /** 本地校验失败的说明，仅 errorCode === ERROR_LOCAL 时有意义 */
  localMessage: string = '';

  /** 给界面直接展示的一句话失败原因 */
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

  /** 业务错误：HTTP 已成功，但响应体里 error_code 非 0 */
  failBusiness(code: number, message: string): void {
    this.errorCode = code;
    this.errorMessage = message;
  }
}
