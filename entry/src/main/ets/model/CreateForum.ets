
interface ChallengeExtra { textimg?: string; slideimg?: string; endpoint?: string; successimg?: string; slideendpoint?: string; }
interface ChallengeInfo { vcode_md5?: string; vcode_pic_url?: string; vcode_type?: string | number; vcode_extra?: ChallengeExtra; }

export class CreateForumChallengeExtra {
  textImage: string = ''; slideImage: string = ''; endPoint: string = ''; successImage: string = ''; slideEndPoint: string = '';
}

export function usesNewVcode(type: string): boolean { return type === '4' || type === '5' || type === '6'; }
interface ChallengeError { errno?: number | string; errmsg?: string; }
interface ChallengeEnvelope {
  error_code?: number | string; error_msg?: string; errno?: number | string; errmsg?: string;
  error?: ChallengeError; info?: ChallengeInfo; anti?: ChallengeInfo;
}
export class CreateForumChallenge {
  code: number = -1;
  message: string = '创建吧验证码响应未确认';
  token: string = '';
  imageUrl: string = '';
  type: string = '';
  extra: CreateForumChallengeExtra = new CreateForumChallengeExtra();
  available(): boolean { return this.code === 0 && this.token.length > 0 && this.imageUrl.length > 0; }
}
function resultCode(value: number | string | undefined): number {
  if (typeof value !== 'number' && (typeof value !== 'string' || !/^-?\d+$/.test(value))) { return -1; }
  const n: number = Number(value);
  return Number.isInteger(n) && n >= -2147483648 && n <= 2147483647 ? n : -1;
}

function challengeImageUrl(value: string | undefined): string {
  if (typeof value !== 'string' || value.length > 4096 || /[\s\u0000-\u001f\u007f\\]/.test(value)) { return ''; }
  return /^https?:\/\/(?:[a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}(?::[0-9]{1,5})?(?:[/?#][^\s]*)?$/.test(value) ? value : '';
}
export function parseCreateForumChallenge(text: string): CreateForumChallenge {
  const result: CreateForumChallenge = new CreateForumChallenge();
  try {
    const raw: ChallengeEnvelope = JSON.parse(text) as ChallengeEnvelope;
    if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) { return result; }
    let message: string | undefined = undefined;
    if (raw.error !== undefined && raw.error !== null && typeof raw.error === 'object' && !Array.isArray(raw.error)) {
      result.code = resultCode(raw.error.errno); message = raw.error.errmsg;
    } else {
      result.code = resultCode(raw.errno !== undefined ? raw.errno : raw.error_code);
      message = raw.errmsg !== undefined ? raw.errmsg : raw.error_msg;
    }
    if (typeof message === 'string' && message.length > 0) { result.message = message; }
    if (result.code !== 0) { return result; }

    const info: ChallengeInfo | undefined = raw.info !== undefined && raw.info !== null &&
      typeof raw.info === 'object' && !Array.isArray(raw.info) ? raw.info : raw.anti;
    if (info === undefined || info === null || typeof info !== 'object' || Array.isArray(info)) { return result; }
    if (typeof info.vcode_md5 === 'string' && info.vcode_md5.length > 0 && info.vcode_md5.length <= 1024 &&
      !/[\s\u0000-\u001f\u007f]/.test(info.vcode_md5)) { result.token = info.vcode_md5; }
    result.imageUrl = challengeImageUrl(info.vcode_pic_url);
    if (typeof info.vcode_type === 'string') { result.type = info.vcode_type; }
    else if (typeof info.vcode_type === 'number' && Number.isFinite(info.vcode_type)) { result.type = String(info.vcode_type); }
    const extra: ChallengeExtra | undefined = info.vcode_extra;
    if (extra !== undefined && extra !== null && typeof extra === 'object' && !Array.isArray(extra)) {
      if (typeof extra.textimg === 'string') { result.extra.textImage = extra.textimg; }
      if (typeof extra.slideimg === 'string') { result.extra.slideImage = extra.slideimg; }
      if (typeof extra.endpoint === 'string') { result.extra.endPoint = extra.endpoint; }
      if (typeof extra.successimg === 'string') { result.extra.successImage = extra.successimg; }
      if (typeof extra.slideendpoint === 'string') { result.extra.slideEndPoint = extra.slideendpoint; }
    }
    if (result.available()) { result.message = ''; }
  } catch (err) {  }
  return result;
}
export class CreateForumDraft { name: string = ''; vcode: string = ''; token: string = ''; nameShow: string = ''; }
export function createForumDraftError(draft: CreateForumDraft): string {
  const name: string = draft.name.trim();
  if (name.length === 0 || name.length >= 32 || /[\u0000-\u001f\u007f]/.test(name)) { return '吧名需为1至31个字符'; }
  if (draft.vcode.trim().length === 0 || draft.vcode.length > 1024 || /[\u0000-\u001f\u007f]/.test(draft.vcode)) { return '验证码输入未确认'; }
  if (draft.token.length === 0 || draft.token.length > 1024 || /[\s\u0000-\u001f\u007f]/.test(draft.token)) { return '验证码标识未确认'; }
  return '';
}
