/** 点赞请求诊断日志，仅记录请求结构与状态，不输出认证凭据。 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { sha256Hex } from './RequestOptionsTrace';
import { SignParam } from '../utils/CryptoUtil';
import { TiebaCommonParams } from './TiebaParams';

const DOMAIN: number = 0x0000;
const TAG: string = 'AgreeTrace';

/** 反爬组 + sign：body 全量哈希必变的字段，core 哈希要剔除 */
function isVolatileKey(key: string): boolean {
  if (key === 'sign' || key === 'timestamp') {
    return true;
  }
  return key.startsWith('st') && key.length > 2;
}

function valueOf(params: SignParam[], key: string): string {
  for (let i = 0; i < params.length; i++) {
    if (params[i].key === key) {
      return params[i].value;
    }
  }
  return '<missing>';
}

export class AgreeTrace {
  private static seq: number = 0;

  /** 发送前调用；`signed` 是已含 sign 的最终字段表（顺序即 body 字节顺序） */
  static logOpAgree(signed: SignParam[]): void {
    AgreeTrace.seq++;
    const bodyForm: string = TiebaCommonParams.encodeForm(signed);

    // core：剔除 timestamp/st*/sign 后按 key 重排再哈希
    const core: SignParam[] = [];
    for (let i = 0; i < signed.length; i++) {
      if (!isVolatileKey(signed[i].key)) {
        core.push(signed[i]);
      }
    }
    core.sort((a: SignParam, b: SignParam): number => {
      if (a.key < b.key) {
        return -1;
      }
      if (a.key > b.key) {
        return 1;
      }
      return 0;
    });
    const coreForm: string = TiebaCommonParams.encodeForm(core);

    hilog.info(DOMAIN, TAG,
      'opAgreeTrace seq=%{public}d wall=%{public}d thread_id=%{public}s post_id=%{public}s'
        + ' obj_type=%{public}s op_type=%{public}s agree_type=%{public}s'
        + ' timestamp=%{public}s stErrorNums=%{public}s stMethod=%{public}s stMode=%{public}s'
        + ' stTimesNum=%{public}s stTime=%{public}s stSize=%{public}s'
        + ' bodyLen=%{public}d bodySha256=%{public}s coreSha256=%{public}s sign=%{public}s',
      AgreeTrace.seq, Date.now(), valueOf(signed, 'thread_id'), valueOf(signed, 'post_id'),
      valueOf(signed, 'obj_type'), valueOf(signed, 'op_type'), valueOf(signed, 'agree_type'),
      valueOf(signed, 'timestamp'), valueOf(signed, 'stErrorNums'), valueOf(signed, 'stMethod'),
      valueOf(signed, 'stMode'), valueOf(signed, 'stTimesNum'), valueOf(signed, 'stTime'),
      valueOf(signed, 'stSize'), bodyForm.length, sha256Hex(bodyForm), sha256Hex(coreForm),
      valueOf(signed, 'sign'));
  }
}
