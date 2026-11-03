/** H-05：扫码只接受可在应用内打开的贴吧帖子/吧链接，不打开其他二维码内容。 */
import { ContentDestination, ContentDestinationKind, ContentKind, ContentPiece,
  contentDestination } from './ThreadDetail';

export function scanDestination(value: string): ContentDestination {
  const invalid: ContentDestination = new ContentDestination();
  const text: string = value.trim();
  if (text.length === 0 || text.length > 4096 || /[\u0000-\u001f\u007f]/.test(text)) {
    return invalid;
  }
  const piece: ContentPiece = new ContentPiece();
  piece.kind = ContentKind.LINK;
  piece.link = text;
  const target: ContentDestination = contentDestination(piece);
  return target.kind === ContentDestinationKind.THREAD || target.kind === ContentDestinationKind.FORUM ?
    target : invalid;
}

/** 不展示扫码原文或系统异常原文，取消与失败分开。SDK startScanForResult 错误码。 */
export function scanFailureMessage(code: number): string {
  if (code === 1000500002) { return '已取消扫码'; }
  if (code === 201) { return '扫码权限不可用，请在系统设置中检查权限'; }
  if (code === 801) { return '当前设备不支持扫码'; }
  return '扫码失败，请重试';
}
