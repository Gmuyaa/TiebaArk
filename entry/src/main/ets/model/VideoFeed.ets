import { RawVideoInfo, RawUser } from '../api/RawThreadPage';
import { VideoClip, parseVideoClip } from './VideoClip';

interface VideoFeedRow {
  id?: number | string;
  title?: string;
  first_post_id?: number | string;
  video_info?: RawVideoInfo;
  forum_info?: VideoFeedForum;
  fname?: string;
  author?: RawUser;
}
interface VideoFeedForum { name?: string; }
interface VideoFeedEnvelope { error_code?: number | string; error_msg?: string; thread_list?: (VideoFeedRow | string)[]; }
export class VideoFeedEnvironment { width: number = 0; height: number = 0; density: number = 0; newNetType: number = -1; }
export class VideoFeedItem { id: string = ''; title: string = ''; forumName: string = ''; authorName: string = ''; clip: VideoClip = new VideoClip(); }
export class VideoFeedResult { code: number = -1; message: string = ''; items: VideoFeedItem[] = []; sourceCount: number = 0; }

export function videoThreadId(value: number | string | undefined): string {
  if (typeof value === 'number' && (!Number.isSafeInteger(value) || value <= 0)) { return ''; }
  if (typeof value !== 'number' && typeof value !== 'string') { return ''; }
  const text: string = String(value);
  return /^[1-9]\d*$/.test(text) && BigInt(text) <= BigInt('9223372036854775807') ? text : '';
}
function text(value: string | undefined): string { return typeof value === 'string' ? value : ''; }
export function parseVideoFeed(source: string): VideoFeedResult {
  const result: VideoFeedResult = new VideoFeedResult();
  try {
    const raw: VideoFeedEnvelope = JSON.parse(source) as VideoFeedEnvelope;
    if (raw.error_code !== 0 && raw.error_code !== '0') {
      if (typeof raw.error_code === 'number' && Number.isSafeInteger(raw.error_code)) { result.code = raw.error_code; }
      result.message = text(raw.error_msg) || '视频列表响应未确认'; return result;
    }
    if (!Array.isArray(raw.thread_list)) { throw new Error('视频列表缺失'); }
    result.sourceCount = raw.thread_list.length; const seen: Set<string> = new Set<string>();
    for (const value of raw.thread_list) {
      const row: VideoFeedRow = typeof value === 'string' ? JSON.parse(value) as VideoFeedRow : value;
      if (row === undefined || row === null) { throw new Error('视频条目无效'); }
      const id: string = videoThreadId(row.id); const clip: VideoClip | undefined = parseVideoClip(row.video_info);
      if (id.length === 0 || clip === undefined || seen.has(id)) { continue; }
      const item: VideoFeedItem = new VideoFeedItem(); item.id = id; item.clip = clip; item.title = text(row.title);
      item.forumName = text(row.forum_info?.name) || text(row.fname);
      item.authorName = text(row.author?.name_show) || text(row.author?.name);
      seen.add(id); result.items.push(item);
    }
    if (result.sourceCount > 0 && result.items.length === 0) { throw new Error('尚无可展示的视频条目'); }
    result.code = 0;
  } catch (err) { result.code = -1; result.message = '视频列表数据未确认，请重试'; result.items = []; }
  return result;
}
export function appendVideoFeed(current: VideoFeedItem[], incoming: VideoFeedItem[]): VideoFeedItem[] {
  const result: VideoFeedItem[] = current.slice(); const seen: Set<string> = new Set<string>(current.map((item) => item.id));
  for (const item of incoming) { if (!seen.has(item.id)) { seen.add(item.id); result.push(item); } }
  return result;
}
