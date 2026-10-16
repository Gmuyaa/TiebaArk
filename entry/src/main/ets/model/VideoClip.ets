import { RawVideoInfo } from '../api/RawThreadPage';

export class VideoClip {
  url: string = '';
  cover: string = '';
  md5: string = '';
  width: number = -1;
  height: number = -1;

  durationRaw: number = -1;
}

export function videoSourceUrl(value: string | undefined): string {
  if (typeof value !== 'string' || value.trim() !== value || /[\s\u0000-\u001f\u007f]/.test(value)) { return ''; }
  return /^https?:\/\/(?:[a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}(?::(?:80|443))?(?:\/[^\s]*)?$/.test(value) ? value : '';
}
function videoNumber(value: number | string | undefined): number {
  if (typeof value !== 'number' && (typeof value !== 'string' || !/^\d+$/.test(value))) { return -1; }
  const number: number = Number(value);
  return Number.isSafeInteger(number) && number >= 0 && number <= 4294967295 ? number : -1;
}
export function parseVideoClip(raw: RawVideoInfo | undefined): VideoClip | undefined {
  if (raw === undefined || raw === null) { return undefined; }
  const url: string = videoSourceUrl(raw.video_url);
  if (url.length === 0) { return undefined; }
  const clip: VideoClip = new VideoClip(); clip.url = url; clip.cover = videoSourceUrl(raw.thumbnail_url);
  clip.md5 = typeof raw.video_md5 === 'string' && !/[\u0000-\u001f\u007f]/.test(raw.video_md5) ? raw.video_md5 : '';
  clip.width = videoNumber(raw.video_width); clip.height = videoNumber(raw.video_height);
  clip.durationRaw = videoNumber(raw.video_duration); return clip;
}
