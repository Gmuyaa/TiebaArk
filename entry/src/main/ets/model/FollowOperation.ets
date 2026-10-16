export type FollowKind = 'user' | 'forum';

export class FollowWriteResult {
  code: number = -1;
  message: string = '关注响应格式无效';
}

interface RawFollowError { errno?: number | string; errmsg?: string; }
interface RawFollowWrite { error_code?: number | string; error_msg?: string; error?: RawFollowError; }

function validCode(value: number | string | undefined): boolean {
  return (typeof value === 'number' && Number.isInteger(value)) ||
    (typeof value === 'string' && /^-?\d+$/.test(value) && Number.isInteger(Number(value)));
}

export function parseFollowWrite(text: string): FollowWriteResult {
  const result: FollowWriteResult = new FollowWriteResult();
  try {
    const raw: RawFollowWrite = JSON.parse(text) as RawFollowWrite;
    if (raw === null || !validCode(raw.error_code)) { return result; }
    const code: number = Number(raw.error_code);
    if (!Number.isInteger(code)) { return result; }
    result.code = code;
    result.message = raw.error_msg || '';
    if (code === 0 && raw.error !== undefined) {
      const nested: number = Number(raw.error?.errno);
      if (!validCode(raw.error?.errno)) { result.code = -1; result.message = '关注响应格式无效'; }
      else { result.code = nested; result.message = raw.error?.errmsg || ''; }
    }
    return result;
  } catch (err) { return result; }
}
