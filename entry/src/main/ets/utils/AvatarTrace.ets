/** 头像链路计时日志，只记录阶段与耗时，不记录凭据、头像 URL 或原始账号资料。 */
import { systemDateTime } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'AvatarTrace';

/** 模块级 trace 计数：跨 VM 实例唯一，用来把一次操作的全链路日志串起来。 */
let traceCounter: number = 0;

/** 自启动单调毫秒；取不到时返回 -1（**不退回墙钟**，否则两种时间会混算）。 */
export function avatarUptimeMs(): number {
  try {
    return systemDateTime.getUptime(systemDateTime.TimeType.STARTUP);
  } catch (err) {
    return -1;
  }
}

/** 开一次头像操作的 traceId。连续两次修改、换 VM 实例都会得到不同的值。 */
export function avatarTraceNextId(): number {
  traceCounter++;
  return traceCounter;
}

/** 事件点：只记绝对单调时刻，跨阶段可直接相减。 */
export function avatarTrace(stage: string, traceId: number, detail: string = ''): void {
  hilog.info(DOMAIN, TAG, 'avatar trace: trace=%{public}d at=%{public}d stage=%{public}s %{public}s',
    traceId, avatarUptimeMs(), stage, detail);
}

/** 阶段耗时：`startedMs` 必须是**该阶段自己**的起点，`ms=` 才是这一段的时间。 */
export function avatarTracePhase(stage: string, traceId: number, startedMs: number,
  detail: string = ''): void {
  const now: number = avatarUptimeMs();
  const elapsed: number = startedMs >= 0 && now >= 0 ? now - startedMs : -1;
  hilog.info(DOMAIN, TAG, 'avatar trace: trace=%{public}d at=%{public}d ms=%{public}d stage=%{public}s %{public}s',
    traceId, now, elapsed, stage, detail);
}

/** 一次图片加载的归属：在**启动加载时**捕获，回调只允许使用这一份。 */
export class AvatarImageLoad {
  traceId: number = 0;
  /** 捕获时的展示版本（远端图）：迟到回调据此被拒。 */
  revision: number = 0;
  /** preview | remote */
  source: string = '';
}

/**
 * 捕获一次图片加载的归属。
 * 只按形态区分来源（本地预览 / 远端地址），不记录地址本身。
 */
export function avatarImageLoadFor(url: string, traceId: number, revision: number): AvatarImageLoad {
  const load: AvatarImageLoad = new AvatarImageLoad();
  load.traceId = traceId;
  load.revision = revision;
  load.source = url.startsWith('data:image/png;base64,') ? 'preview' : 'remote';
  return load;
}
