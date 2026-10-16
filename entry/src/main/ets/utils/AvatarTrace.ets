
import { systemDateTime } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'AvatarTrace';

let traceCounter: number = 0;

export function avatarUptimeMs(): number {
  try {
    return systemDateTime.getUptime(systemDateTime.TimeType.STARTUP);
  } catch (err) {
    return -1;
  }
}

export function avatarTraceNextId(): number {
  traceCounter++;
  return traceCounter;
}

export function avatarTrace(stage: string, traceId: number, detail: string = ''): void {
  hilog.info(DOMAIN, TAG, 'avatar trace: trace=%{public}d at=%{public}d stage=%{public}s %{public}s',
    traceId, avatarUptimeMs(), stage, detail);
}

export function avatarTracePhase(stage: string, traceId: number, startedMs: number,
  detail: string = ''): void {
  const now: number = avatarUptimeMs();
  const elapsed: number = startedMs >= 0 && now >= 0 ? now - startedMs : -1;
  hilog.info(DOMAIN, TAG, 'avatar trace: trace=%{public}d at=%{public}d ms=%{public}d stage=%{public}s %{public}s',
    traceId, now, elapsed, stage, detail);
}

export class AvatarImageLoad {
  traceId: number = 0;

  revision: number = 0;

  source: string = '';
}

export function avatarImageLoadFor(url: string, traceId: number, revision: number): AvatarImageLoad {
  const load: AvatarImageLoad = new AvatarImageLoad();
  load.traceId = traceId;
  load.revision = revision;
  load.source = url.startsWith('data:image/png;base64,') ? 'preview' : 'remote';
  return load;
}
