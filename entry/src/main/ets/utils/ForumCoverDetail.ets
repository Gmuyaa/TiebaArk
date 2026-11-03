import { image } from '@kit.ImageKit';
import { UIContext } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { taskpool } from '@kit.ArkTS';
import { ForumCoverDetail, FORUM_COVER_SAMPLE_PIXELS, FORUM_COVER_SAMPLE_WIDTH } from '../model/ForumCoverDetail';
import { analyzeForumCover } from './ForumCoverAnalysis';

/** 接管并释放临时PixelMap；失败或过期一律不允许缩短。 */
export async function readForumCoverDetail(pixels: image.PixelMap, current: () => boolean): Promise<ForumCoverDetail> {
  let result: ForumCoverDetail = new ForumCoverDetail();
  try {
    if (!current()) { return result; }
    const info: image.ImageInfo = await pixels.getImageInfo();
    if (!current() || (info.pixelFormat !== image.PixelMapFormat.RGBA_8888 &&
      info.pixelFormat !== image.PixelMapFormat.BGRA_8888) ||
      info.size.width * info.size.height > FORUM_COVER_SAMPLE_PIXELS) { return result; }
    const length: number = pixels.getPixelBytesNumber();
    if (!Number.isSafeInteger(length) || length <= 0 || length > FORUM_COVER_SAMPLE_PIXELS * 4 + 4096) { return result; }
    const buffer: ArrayBuffer = new ArrayBuffer(length);
    await pixels.readPixelsToBuffer(buffer);
    if (!current()) { return result; }
    const stride: number = length === info.size.width * info.size.height * 4 ? info.size.width * 4 : info.stride;
    const task: taskpool.Task = new taskpool.Task(analyzeForumCover, buffer, info.size.width, info.size.height, stride);
    // 一次性移交缓冲区，避免界面线程复制像素；失败时保留原高度，不回退到主线程计算。
    task.setTransferList([buffer]);
    result = await taskpool.execute(task, taskpool.Priority.LOW) as ForumCoverDetail;
  } catch (err) {
    hilog.warn(0x0, 'ForumCoverDetail', 'pixel inspection unavailable; keep full cover');
  } finally {
    try { await pixels.release(); }
    catch (err) {
      result.compact = false;
      hilog.warn(0x0, 'ForumCoverDetail', 'temporary pixel release failed; keep full cover');
    }
  }
  if (!current()) { result.compact = false; }
  return result;
}

/** 离屏完整Contain帧复用已加载的图片，不切换屏幕上的objectFit，不保存图片副本。 */
export async function inspectForumCover(ui: UIContext, builder: CustomBuilder, widthVp: number,
  current: () => boolean): Promise<ForumCoverDetail> {
  if (!current() || !Number.isFinite(widthVp) || widthVp <= 0) { return new ForumCoverDetail(); }
  try {
    const scale: number = Math.min(1, FORUM_COVER_SAMPLE_WIDTH / ui.vp2px(widthVp));
    const pixels: image.PixelMap = await ui.getComponentSnapshot().createFromBuilder(builder, 0, true,
      { scale: scale, waitUntilRenderFinished: true });
    return await readForumCoverDetail(pixels, current);
  } catch (err) {
    hilog.warn(0x0, 'ForumCoverDetail', 'image snapshot unavailable; keep full cover');
    return new ForumCoverDetail();
  }
}
