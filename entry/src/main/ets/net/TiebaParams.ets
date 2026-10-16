import { CreateForumDraft, createForumDraftError } from '../model/CreateForum';
import { ImageUploadChunk, imageUploadChunkError } from '../model/ImageUpload';
import { FollowKind } from '../model/FollowOperation';
import { MessageSettingField, validMessageSetting } from '../model/MessageSettings';
import { TailAction, TailChange, tailChangeError } from '../model/Tails';
import { PrivacyMarkField, validPrivacyMark } from '../model/PrivacyMarks';
import { AtCandidateKind, validAtKind } from '../model/AtCandidates';
import { VideoFeedEnvironment } from '../model/VideoFeed';
/* 协议参考：lumina37/aiotieba（Unlicense）。 */

import { CryptoUtil, SignParam, SignSalt } from '../utils/CryptoUtil';
import { ProtoWriter } from '../proto/ProtoWire';
import { encodeUtf8 } from '../utils/TextCodec';
import { TransferStats, TransferStatsSnapshot } from './TransferStats';

export class TiebaVersion {

  static readonly LATEST: string = '22.6.5.1';

  static readonly LEGACY: string = '12.64.1.1';
  static readonly CHAT: string = '12.68.1.0';

  static readonly TIEBA_V12: string = '12.52.1.0';
}

export class TiebaHost {

  static readonly APP: string = 'tiebac.baidu.com';

  static readonly WEB: string = 'tieba.baidu.com';

}

export class CreateForumParams {
  static readonly CHALLENGE_PATH: string = '/c/f/anti/vcode';
  static readonly CREATE_PATH: string = '/c/c/forum/create';
  static challenge(device: TiebaDevice, session: TiebaSession): SignParam[] {
    const params: SignParam[] = TiebaCommonParams.build(device, session).filter((p: SignParam): boolean => p.key !== 'tbs');
    params.push(new SignParam('fid', '0'), new SignParam('pub_type', '0'), new SignParam('fname', ''), new SignParam('tid', '0'));
    return params;
  }
  static create(device: TiebaDevice, session: TiebaSession, draft: CreateForumDraft): SignParam[] {
    if (session.tbs.length === 0 || createForumDraftError(draft).length > 0) { return []; }
    const params: SignParam[] = TiebaCommonParams.build(device, session);
    params.push(new SignParam('kw', draft.name.trim()), new SignParam('vcode', draft.vcode.trim()),
      new SignParam('vcode_md5', draft.token), new SignParam('name_show', draft.nameShow));
    return params;
  }
}

export class AvatarUploadParams {
  static readonly PATH: string = '/c/c/img/portrait';
  static readonly BOUNDARY: string = '--------7da3d81520810*';
  static build(device: TiebaDevice, session: TiebaSession): SignParam[] {

    return TiebaCommonParams.build(device, session).filter((p: SignParam): boolean => p.key !== 'tbs');
  }
  static multipart(params: SignParam[], bytes: Uint8Array): Uint8Array {
    const marker: string = `--${AvatarUploadParams.BOUNDARY}`;
    const prefix: Uint8Array = encodeUtf8(marker);
    for (let i: number = 0; i <= bytes.length - prefix.length; i++) {
      let match: boolean = true;
      for (let j: number = 0; j < prefix.length; j++) { if (bytes[i + j] !== prefix[j]) { match = false; break; } }
      if (match) { return new Uint8Array(0); }
    }
    let text: string = '';
    for (const p of params) {
      if (!/^[a-zA-Z0-9_]+$/.test(p.key) || p.value.includes(marker)) { return new Uint8Array(0); }
      text += `${marker}\r\nContent-Disposition: form-data; name="${p.key}"\r\n\r\n${p.value}\r\n`;
    }
    const head: Uint8Array = encodeUtf8(text + `${marker}\r\nContent-Disposition: form-data; name="pic"; filename="file"\r\n\r\n`);
    const tail: Uint8Array = encodeUtf8(`\r\n${marker}--\r\n`);
    const out: Uint8Array = new Uint8Array(head.length + bytes.length + tail.length);
    out.set(head); out.set(bytes, head.length); out.set(tail, head.length + bytes.length); return out;
  }
}

export class ImageUploadParams {
  static readonly PATH: string = '/c/s/uploadPicture';
  static readonly BOUNDARY: string = '--------7da3d81520810*';
  static build(device: TiebaDevice, session: TiebaSession, chunk: ImageUploadChunk): SignParam[] {
    if (imageUploadChunkError(chunk).length > 0) { return []; }
    const params: SignParam[] = TiebaCommonParams.build(device, session);
    params.push(new SignParam('resourceId', `${chunk.digest.toUpperCase()}${chunk.chunkSize}`),
      new SignParam('chunkNo', String(chunk.chunkNo)), new SignParam('isFinish', chunk.finish() ? '1' : '0'),
      new SignParam('is_bjh', '0'), new SignParam('size', String(chunk.totalSize)),
      new SignParam('width', String(chunk.width)), new SignParam('height', String(chunk.height)),
      new SignParam('groupId', '1'), new SignParam('alt', 'json'), new SignParam('saveOrigin', '0'));
    if (chunk.watermarkType !== 0) { params.push(new SignParam('pic_water_type', String(chunk.watermarkType))); }
    if (chunk.watermarkType === 1) { params.push(new SignParam('user_name', chunk.userName)); }
    if (chunk.watermarkType === 2) { params.push(new SignParam('forum_name', chunk.forumName)); }
    if (chunk.forumName.length > 0) { params.push(new SignParam('small_flow_fname', chunk.forumName)); }
    return params;
  }

  static multipart(params: SignParam[], bytes: Uint8Array): Uint8Array {
    const marker: string = `--${ImageUploadParams.BOUNDARY}`;
    const prefix: Uint8Array = encodeUtf8(marker);
    for (let i: number = 0; i <= bytes.length - prefix.length; i++) {
      let match: boolean = true;
      for (let j: number = 0; j < prefix.length; j++) { if (bytes[i + j] !== prefix[j]) { match = false; break; } }
      if (match) { return new Uint8Array(0); }
    }
    let text: string = '';
    for (const param of params) {
      if (!/^[a-zA-Z0-9_]+$/.test(param.key) || param.value.includes(marker)) { return new Uint8Array(0); }
      text += `${marker}\r\nContent-Disposition: form-data; name="${param.key}"\r\n\r\n${param.value}\r\n`;
    }
    const head: Uint8Array = encodeUtf8(text + `${marker}\r\nContent-Disposition: form-data; name="chunk"; filename="file"\r\n\r\n`);
    const tail: Uint8Array = encodeUtf8(`\r\n${marker}--\r\n`);
    const out: Uint8Array = new Uint8Array(head.length + bytes.length + tail.length);
    out.set(head); out.set(bytes, head.length); out.set(tail, head.length + bytes.length); return out;
  }
}

export class ImageWatermarkParams {
  static readonly READ_PATH: string = '/c/u/user/getWatermark';
  static build(device: TiebaDevice, session: TiebaSession): SignParam[] {
    return TiebaCommonParams.build(device, session);
  }
}

export class MessageSettingsParams {
  static readonly READ_PATH: string = '/c/u/user/getMsgMask';
  static readonly WRITE_PATH: string = '/c/c/friend/setMsgMask';

  static build(device: TiebaDevice, session: TiebaSession,
    field: MessageSettingField | undefined = undefined, value: number = -1): SignParam[] {
    if (field !== undefined && !validMessageSetting(field, value)) { return []; }
    const params: SignParam[] = TiebaCommonParams.build(device, session);
    if (field !== undefined) { params.push(new SignParam(field, String(value))); }
    return params;
  }
}

export class AtCandidatesParams {
  static path(kind: AtCandidateKind): string {
    return '/c/u/follow/atSearchUserList';
  }
  static build(device: TiebaDevice, session: TiebaSession, kind: AtCandidateKind, word: string): SignParam[] {
    if (!validAtKind(kind)) { return []; }
    const params: SignParam[] = TiebaCommonParams.build(device, session);
    params.push(new SignParam('rn', '100'));
    if (word.trim().length > 0) { params.push(new SignParam('word', word.trim())); }
    return params;
  }
}

export class AtMentionsParams {
  static readonly PATH: string = '/c/u/feed/atme';
  static build(device: TiebaDevice, session: TiebaSession, uid: number, page: number): SignParam[] {
    if (!Number.isSafeInteger(uid) || uid <= 0 || !Number.isSafeInteger(page) || page < 1) { return []; }
    const params: SignParam[] = TiebaCommonParams.build(device, session);
    params.push(new SignParam('uid', String(uid)), new SignParam('pn', String(page)),
      new SignParam('time', '0'), new SignParam('tid', '0'), new SignParam('is_first', '0'),
      new SignParam('call_from', ''), new SignParam('q_type', '0'));
    return params;
  }
}

export class VoiceAudioParams {
  static url(id: string): string {
    if (id.length === 0 || id.trim() !== id || /[\s\u0000-\u001f\u007f]/.test(id)) { return ''; }
    if (id.includes('://')) {

      return /^https:\/\/(?:[a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}(?::443)?(?:\/[^\s]*)?$/.test(id) ? id : '';
    }
    return `https://${TiebaHost.APP}/c/p/voice?voice_md5=${encodeURIComponent(id)}`;
  }
}

export class VideoFeedParams {
  static readonly PATH: string = '/c/f/video/feed';
  static valid(environment: VideoFeedEnvironment, loadType: number): boolean {
    return (loadType === 1 || loadType === 2) && Number.isSafeInteger(environment.width) && environment.width > 0 &&
      Number.isSafeInteger(environment.height) && environment.height > 0 && Number.isFinite(environment.density) && environment.density > 0 &&
      Number.isInteger(environment.newNetType) && environment.newNetType >= -1 && environment.newNetType <= 5;
  }
  static build(device: TiebaDevice, session: TiebaSession, environment: VideoFeedEnvironment, loadType: number): SignParam[] {
    const params: SignParam[] = TiebaCommonParams.build(device, session);
    params.push(new SignParam('scr_w', `${environment.width}`), new SignParam('scr_h', `${environment.height}`),
      new SignParam('scr_dip', `${environment.density}`), new SignParam('load_type', `${loadType}`));
    if (environment.newNetType >= 0) { params.push(new SignParam('new_net_type', `${environment.newNetType}`)); }
    return params;
  }
}

export class OfficialMessagesParams {
  static url(): string { return `https://${TiebaHost.APP}/c/u/user/getOfficialSwitch?cmd=309620`; }
  static build(device: TiebaDevice, session: TiebaSession): Uint8Array {
    const common: ProtoWriter = new ProtoWriter();
    common.writeInt32(1, 2); common.writeString(2, device.clientVersion);
    common.writeString(3, device.clientId); common.writeString(7, device.cuid);
    common.writeInt64(8, BigInt(Date.now())); common.writeString(9, device.model.length > 0 ? device.model : 'HarmonyOS');
    common.writeString(10, session.bduss);
    if (session.tbs.length > 0) { common.writeString(11, session.tbs); }
    common.writeInt32(12, 1);
    if (device.osVersion.length > 0) { common.writeString(25, device.osVersion); }
    if (session.stoken.length > 0) { common.writeString(30, session.stoken); }
    if (device.cuidGalaxy2.length > 0) { common.writeString(32, device.cuidGalaxy2); }
    if (device.c3Aid.length > 0) { common.writeString(35, device.c3Aid); }
    const data: ProtoWriter = new ProtoWriter(); data.writeMessage(1, common.toUint8Array());
    const root: ProtoWriter = new ProtoWriter(); root.writeMessage(1, data.toUint8Array());
    return SelfProfileParams.wrapMultipart(root.toUint8Array());
  }
}

export class TiebaDevice {

  androidId: string = '';

  uuid: string = '';

  cuid: string = '';

  cuidGalaxy2: string = '';

  c3Aid: string = '';

  clientId: string = '';

  clientVersion: string = TiebaVersion.LATEST;

  osVersion: string = '';

  netType: string = '';

  model: string = '';

  isUsable(): boolean {
    return this.androidId.length > 0 && this.uuid.length > 0 && this.cuid.length > 0;
  }
}

export class TiebaSession {

  bduss: string = '';

  stoken: string = '';

  tbs: string = '';

  hasBduss(): boolean {
    return this.bduss.length > 0;
  }
}

/* 协议参考：lumina37/aiotieba（Unlicense）。 */
export enum AgreeObjType {

  THREAD = 3,

  POST = 1,

  SUB_POST = 2
}

export class AntiSpamParams {

  static generate(nowMs: number): SignParam[] {
    const stats: TransferStatsSnapshot | undefined = TransferStats.take();
    const errorNums: number = TransferStats.takeErrorNums();
    return AntiSpamParams.compose(nowMs, stats, errorNums);
  }

  static fixed(nowMs: number, stTime: number, stSize: number): SignParam[] {
    const stats: TransferStatsSnapshot = new TransferStatsSnapshot();
    stats.elapsedMs = stTime;
    stats.bytes = stSize;
    return AntiSpamParams.compose(nowMs, stats, 0);
  }

  private static compose(nowMs: number, stats: TransferStatsSnapshot | undefined,
    errorNums: number): SignParam[] {
    const params: SignParam[] = [];
    params.push(new SignParam('timestamp', String(nowMs)));
    let errors: number = errorNums;
    if (errors === 0 && stats !== undefined) {
      errors = stats.retry;
    }
    params.push(new SignParam('stErrorNums', String(errors)));
    if (stats !== undefined) {
      params.push(new SignParam('stMethod', '1'));
      params.push(new SignParam('stMode', String(stats.mode)));
      params.push(new SignParam('stTimesNum', String(stats.retry)));
      params.push(new SignParam('stTime', String(stats.elapsedMs)));
      params.push(new SignParam('stSize', String(stats.bytes)));
    }
    return params;
  }

  static describe(params: SignParam[]): string {
    let out: string = '';
    for (let i = 0; i < params.length; i++) {
      const k: string = params[i].key;
      if (k === 'stTime' || k === 'stSize' || k === 'timestamp') {
        out += `${out.length === 0 ? '' : ' '}${k}=${params[i].value}`;
      }
    }
    return out;
  }
}

export class AgreeParams {

  static readonly HOST: string = 'c.tieba.baidu.com';

  static readonly PATH: string = '/c/c/agree/opAgree';

  static readonly CLIENT_VERSION: string = '12.52.1.0';

  static readonly PHONE_IMEI: string = '000000000000000';

  static readonly NET_TYPE: string = '1';

  static readonly COOKIE: string = 'ka=open';

  static build(device: TiebaDevice, session: TiebaSession, uid: number, tid: number,
    pid: number, opType: string, objType: AgreeObjType, antiSpam: SignParam[],
    forumId: number = 0): SignParam[] {
    const params: SignParam[] = [];

    params.push(new SignParam('thread_id', String(tid)));
    params.push(new SignParam('post_id', objType === AgreeObjType.THREAD ? '0' : String(pid)));
    params.push(new SignParam('op_type', opType));
    params.push(new SignParam('agree_type', '2'));
    params.push(new SignParam('obj_type', String(objType)));

    if (objType === AgreeObjType.POST && forumId > 0) {
      params.push(new SignParam('forum_id', String(forumId)));
      params.push(new SignParam('is_long_press_agree', '0'));
      params.push(new SignParam('z_id', '000'));
    }

    params.push(new SignParam('BDUSS', session.bduss));

    if (session.stoken.length > 0) {
      params.push(new SignParam('STOKEN', session.stoken));
    }
    params.push(new SignParam('tbs', session.tbs));

    params.push(new SignParam('cuid', device.cuid));
    params.push(new SignParam('cuid_galaxy2', device.cuidGalaxy2));
    params.push(new SignParam('_client_id', device.clientId));
    params.push(new SignParam('_client_type', '2'));
    params.push(new SignParam('_client_version', AgreeParams.CLIENT_VERSION));
    params.push(new SignParam('_os_version', device.osVersion));
    params.push(new SignParam('model', device.model));
    params.push(new SignParam('net_type', AgreeParams.NET_TYPE));
    params.push(new SignParam('_phone_imei', AgreeParams.PHONE_IMEI));

    for (let i = 0; i < antiSpam.length; i++) {
      params.push(antiSpam[i]);
    }

    params.sort((a: SignParam, b: SignParam): number => {
      if (a.key < b.key) {
        return -1;
      }
      if (a.key > b.key) {
        return 1;
      }
      return 0;
    });
    return params;
  }

  static headers(uid: number): Record<string, string> {
    const h: Record<string, string> = {};
    h['Content-Type'] = 'application/x-www-form-urlencoded';
    h['User-Agent'] = `bdtb for Android ${AgreeParams.CLIENT_VERSION}`;
    h['Accept'] = 'application/json, text/plain, */*';
    h['Accept-Language'] = 'zh-CN,en-US;q=0.9';
    h['Cookie'] = AgreeParams.COOKIE;
    h['Connection'] = 'Keep-Alive';
    h['client_user_token'] = String(uid);
    return h;
  }
}

export class TiebaCommonParams {

  static build(device: TiebaDevice, session: TiebaSession): SignParam[] {
    const params: SignParam[] = [];

    params.push(new SignParam('_client_type', '2'));
    params.push(new SignParam('_client_version', device.clientVersion));
    params.push(new SignParam('_phone_imei', device.androidId));
    params.push(new SignParam('from', '1020011'));
    params.push(new SignParam('model', 'HarmonyOS'));

    if (device.cuid.length > 0) {
      params.push(new SignParam('cuid', device.cuid));
    }
    if (device.cuidGalaxy2.length > 0) {
      params.push(new SignParam('cuid_galaxy2', device.cuidGalaxy2));
    }
    if (device.c3Aid.length > 0) {
      params.push(new SignParam('c3_aid', device.c3Aid));
    }

    if (device.clientId.length > 0) {
      params.push(new SignParam('_client_id', device.clientId));
    }
    if (device.osVersion.length > 0) {
      params.push(new SignParam('_os_version', device.osVersion));
    }
    if (device.netType.length > 0) {
      params.push(new SignParam('net_type', device.netType));
    }

    if (session.hasBduss()) {
      params.push(new SignParam('BDUSS', session.bduss));
    }

    if (session.stoken.length > 0) {
      params.push(new SignParam('STOKEN', session.stoken));
    }
    if (session.tbs.length > 0) {
      params.push(new SignParam('tbs', session.tbs));
    }

    return params;
  }

  static encodeForm(params: SignParam[]): string {
    const parts: string[] = [];
    for (let i = 0; i < params.length; i++) {
      parts.push(`${encodeURIComponent(params[i].key)}=${encodeURIComponent(params[i].value)}`);
    }
    return parts.join('&');
  }
}

/* 协议参考：lumina37/aiotieba（Unlicense）。 */
export class SelfProfileParams {
  static readonly PATH: string = '/c/u/user/profile';
  /* 协议参考：lumina37/aiotieba（Unlicense）。 */
  static readonly CMD: string = '303012';
  /* 协议参考：lumina37/aiotieba（Unlicense）。 */
  static readonly BOUNDARY: string = '-*_r1999';
  static readonly PROTO_HEADER: string = 'x_bd_data_type';
  static readonly PROTO_HEADER_VALUE: string = 'protobuf';

  /* 协议参考：lumina37/aiotieba（Unlicense）。 */
  static buildRequest(portrait: string, device: TiebaDevice): Uint8Array {
    return SelfProfileParams.buildForUser(0, portrait, device, 1);
  }

  static buildForUser(uid: number, portrait: string, device: TiebaDevice, page: number): Uint8Array {
    const common: ProtoWriter = new ProtoWriter();
    common.writeInt32(1, 2);
    common.writeString(2, device.clientVersion);
    if (device.clientId.length > 0) {
      common.writeString(3, device.clientId);
    }
    if (device.androidId.length > 0) {
      common.writeString(5, device.androidId);
    }
    if (device.cuid.length > 0) {
      common.writeString(7, device.cuid);
    }
    common.writeString(9, device.model.length > 0 ? device.model : 'HarmonyOS');
    const netType: number = Number.parseInt(device.netType, 10);
    if (!Number.isNaN(netType) && netType > 0) {
      common.writeInt32(12, netType);
    }
    if (device.osVersion.length > 0) {
      common.writeString(25, device.osVersion);
    }
    if (device.cuidGalaxy2.length > 0) {
      common.writeString(32, device.cuidGalaxy2);
    }
    if (device.c3Aid.length > 0) {
      common.writeString(35, device.c3Aid);
    }

    const data: ProtoWriter = new ProtoWriter();

    if (portrait.length > 0) {
      data.writeString(16, portrait);
    } else if (uid > 0) {
      data.writeInt64(3, BigInt(uid));
    }
    data.writeInt32(2, 1);
    data.writeInt32(6, page);
    data.writeMessage(9, common.toUint8Array());

    const root: ProtoWriter = new ProtoWriter();
    root.writeMessage(1, data.toUint8Array());
    return root.toUint8Array();
  }

  static wrapMultipart(pb: Uint8Array): Uint8Array {
    const head: Uint8Array = encodeUtf8(
      `--${SelfProfileParams.BOUNDARY}\r\nContent-Disposition: form-data;`
        + ` name="data"; filename="file"\r\n\r\n`);
    const tail: Uint8Array = encodeUtf8(`\r\n--${SelfProfileParams.BOUNDARY}--\r\n`);
    const out: Uint8Array = new Uint8Array(head.length + pb.length + tail.length);
    out.set(head, 0);
    out.set(pb, head.length);
    out.set(tail, head.length + pb.length);
    return out;
  }

  static url(host: string): string {
    return `https://${host}${SelfProfileParams.PATH}?cmd=${SelfProfileParams.CMD}`;
  }

  static headers(session: TiebaSession): Record<string, string> {
    const h: Record<string, string> = {};
    h['Content-Type'] = `multipart/form-data; boundary=${SelfProfileParams.BOUNDARY}`;
    h[SelfProfileParams.PROTO_HEADER] = SelfProfileParams.PROTO_HEADER_VALUE;
    h['Cookie'] = `BDUSS=${session.bduss}; STOKEN=${session.stoken}`;
    return h;
  }
}

/* 协议参考：lumina37/aiotieba（Unlicense）。 */
export class UserPostParams {
  static readonly PATH: string = '/c/u/feed/userpost';
  /* 协议参考：lumina37/aiotieba（Unlicense）。 */
  static readonly CMD: string = '303002';

  static buildRequest(uid: number, isThread: number, pn: number, rn: number,
    device: TiebaDevice, session: TiebaSession): Uint8Array {
    const common: ProtoWriter = new ProtoWriter();
    common.writeInt32(1, 2);
    common.writeString(2, device.clientVersion);
    if (device.clientId.length > 0) {
      common.writeString(3, device.clientId);
    }
    if (device.androidId.length > 0) {
      common.writeString(5, device.androidId);
    }
    if (device.cuid.length > 0) {
      common.writeString(7, device.cuid);
    }
    common.writeString(9, device.model.length > 0 ? device.model : 'HarmonyOS');
    if (session.bduss.length > 0) {
      common.writeString(10, session.bduss);
    }
    const netType: number = Number.parseInt(device.netType, 10);
    if (!Number.isNaN(netType) && netType > 0) {
      common.writeInt32(12, netType);
    }
    if (device.osVersion.length > 0) {
      common.writeString(25, device.osVersion);
    }
    if (device.cuidGalaxy2.length > 0) {
      common.writeString(32, device.cuidGalaxy2);
    }
    if (device.c3Aid.length > 0) {
      common.writeString(35, device.c3Aid);
    }

    const data: ProtoWriter = new ProtoWriter();
    data.writeInt64(1, BigInt(uid));
    data.writeInt32(2, rn);
    data.writeInt32(4, isThread);
    data.writeInt32(5, 1);
    data.writeInt32(26, pn);
    data.writeInt32(33, 1);
    data.writeMessage(27, common.toUint8Array());

    const root: ProtoWriter = new ProtoWriter();
    root.writeMessage(1, data.toUint8Array());
    return root.toUint8Array();
  }

  static wrapMultipart(pb: Uint8Array): Uint8Array {
    return SelfProfileParams.wrapMultipart(pb);
  }

  static url(host: string): string {
    return `https://${host}${UserPostParams.PATH}?cmd=${UserPostParams.CMD}`;
  }

  static headers(session: TiebaSession): Record<string, string> {
    return SelfProfileParams.headers(session);
  }
}

/* 协议参考：lumina37/aiotieba（Unlicense）。 */
export class PersonalizedParams {
  static readonly PATH: string = '/c/f/excellent/personalized';

  static readonly CMD: string = '309264';

  static readonly LOAD_REFRESH: number = 1;
  static readonly LOAD_MORE: number = 2;

  static readonly PAGE_THREAD_COUNT: number = 11;

  static buildRequest(loadType: number, pn: number, pageThreadCount: number,
    device: TiebaDevice, session: TiebaSession, requestTimes: number = 0): Uint8Array {
    const common: ProtoWriter = new ProtoWriter();
    common.writeInt32(1, 2);
    common.writeString(2, device.clientVersion);
    if (device.cuid.length > 0) {
      common.writeString(7, device.cuid);
    }
    common.writeInt64(8, BigInt(Date.now()));
    if (session.bduss.length > 0) {
      common.writeString(10, session.bduss);
    }
    common.writeInt32(12, 1);
    if (session.stoken.length > 0) {
      common.writeString(30, session.stoken);
    }

    const data: ProtoWriter = new ProtoWriter();
    data.writeMessage(1, common.toUint8Array());
    data.writeInt32(4, loadType);
    data.writeInt32(5, pageThreadCount);
    data.writeInt32(6, pn);
    data.writeInt32(11, 1);
    data.writeInt32(22, 0);
    data.writeInt32(23, 1);
    data.writeInt32(27, 0);
    data.writeInt32(28, requestTimes);

    const root: ProtoWriter = new ProtoWriter();
    root.writeMessage(1, data.toUint8Array());
    return root.toUint8Array();
  }

  static wrapMultipart(pb: Uint8Array): Uint8Array {
    return SelfProfileParams.wrapMultipart(pb);
  }

  static url(host: string): string {
    return `https://${host}${PersonalizedParams.PATH}?cmd=${PersonalizedParams.CMD}`;
  }

  static headers(session: TiebaSession): Record<string, string> {
    return SelfProfileParams.headers(session);
  }
}

export class StoreParams {
  static readonly ADD_PATH: string = '/c/c/post/addstore';
  static readonly RM_PATH: string = '/c/c/post/rmstore';

  static readonly FID_PLACEHOLDER: string = 'null';

  static addData(tid: number, pid: number): string {
    return `[{"tid":"${tid}","pid":"${pid}","status":1}]`;
  }

  static buildAdd(device: TiebaDevice, session: TiebaSession, tid: number,
    pid: number): SignParam[] {
    const params: SignParam[] = TiebaCommonParams.build(device, session);
    params.push(new SignParam('data', StoreParams.addData(tid, pid)));
    return params;
  }

  static buildRemove(device: TiebaDevice, session: TiebaSession, tid: number,
    uid: number): SignParam[] {
    const params: SignParam[] = TiebaCommonParams.build(device, session);
    params.push(new SignParam('tid', String(tid)));
    params.push(new SignParam('fid', StoreParams.FID_PLACEHOLDER));
    params.push(new SignParam('user_id', String(uid)));
    return params;
  }
}

export class MemeEmojiParams {
  static readonly ALL_PATH: string = '/c/e/meme/getAllMeme';
  static readonly COLLECT_PATH: string = '/c/e/meme/collect';

  static readonly ALL_DELETE: string = 'all_delete';

  static buildAll(device: TiebaDevice, session: TiebaSession): SignParam[] {
    return TiebaCommonParams.build(device, session);
  }

  static buildCollect(device: TiebaDevice, session: TiebaSession, pics: string,
    picUpdateTimeMs: number): SignParam[] {
    const params: SignParam[] = TiebaCommonParams.build(device, session);
    params.push(new SignParam('pics', pics));
    params.push(new SignParam('pic_update_time', String(picUpdateTimeMs)));
    return params;
  }
}

export class AddPostParams {
  static readonly PATH: string = '/c/c/post/add';

  static readonly CMD: string = '309731';

  static readonly POST_FROM_THREAD: string = '13';

  static readonly POST_FROM_POST: string = '0';

  static readonly CLIENT_TYPE_TAG: string = '12';

  static buildRequest(content: string, fid: string, forumName: string, tid: string,
    device: TiebaDevice, session: TiebaSession,
    target?: AddPostTarget, nickname?: string, withTail?: boolean): Uint8Array {
    if (withTail !== undefined && typeof withTail !== 'boolean') { throw new Error('小尾巴附加选项无效'); }
    const nowMs: number = Date.now();
    const nowSec: number = Math.floor(nowMs / 1000);
    const common: ProtoWriter = new ProtoWriter();
    common.writeInt32(1, 2);
    common.writeString(2, device.clientVersion);
    if (device.clientId.length > 0) {
      common.writeString(3, device.clientId);
    }
    if (device.cuid.length > 0) {
      common.writeString(7, device.cuid);
    }
    common.writeInt64(8, BigInt(nowMs));
    common.writeString(9, device.model.length > 0 ? device.model : 'HarmonyOS');
    if (session.bduss.length > 0) {
      common.writeString(10, session.bduss);
    }
    if (session.tbs.length > 0) {
      common.writeString(11, session.tbs);
    }
    common.writeInt32(12, 1);
    if (device.osVersion.length > 0) {
      common.writeString(25, device.osVersion);
    }
    if (session.stoken.length > 0) {
      common.writeString(30, session.stoken);
    }
    if (device.cuidGalaxy2.length > 0) {
      common.writeString(32, device.cuidGalaxy2);
    }

    const data: ProtoWriter = new ProtoWriter();
    data.writeMessage(1, common.toUint8Array());
    data.writeString(16, AddPostParams.CLIENT_TYPE_TAG);
    data.writeString(19, content);
    data.writeString(26, fid);
    data.writeString(30, forumName);
    data.writeString(44, fid);
    data.writeString(45, tid);
    if (target !== undefined && target.postId.length > 0) {
      data.writeString(46, target.postId);
      data.writeString(49, target.postId);
    }
    if (target !== undefined && target.subPostId.length > 0) {
      data.writeString(50, target.subPostId);
    }
    if (target !== undefined && target.replyUid.length > 0) {
      data.writeString(20, target.replyUid);
    }
    if (nickname !== undefined && nickname.length > 0) {
      data.writeString(58, nickname);
    }
    if (target === undefined || target.postId.length === 0) {

      data.writeString(55, AddPostParams.POST_FROM_THREAD);
      data.writeString(32, '0');
    } else if (target.subPostId.length === 0) {

      data.writeString(55, AddPostParams.POST_FROM_POST);
    }
    data.writeInt64(64, BigInt(0));
    data.writeInt64(67, BigInt(0));

    if (withTail !== undefined) { data.writeInt32(76, withTail ? 1 : 0); }

    const root: ProtoWriter = new ProtoWriter();
    root.writeMessage(1, data.toUint8Array());
    return root.toUint8Array();
  }

  static wrapMultipart(pb: Uint8Array): Uint8Array {
    return SelfProfileParams.wrapMultipart(pb);
  }

  static url(host: string): string {
    return `https://${host}${AddPostParams.PATH}?cmd=${AddPostParams.CMD}`;
  }

  static headers(session: TiebaSession): Record<string, string> {
    return SelfProfileParams.headers(session);
  }
}

export class AddPostTarget {
  postId: string = '';
  subPostId: string = '';
  replyUid: string = '';
}

export class FrsHeadlineParams {
  static readonly PATH: string = '/c/f/frs/frsBottom_pc';

  static async buildBody(kw: string): Promise<string> {
    const params: SignParam[] = [
      new SignParam('kw', encodeURIComponent(kw)),
      new SignParam('tbs', ''),
      new SignParam('subapp_type', 'pc'),
      new SignParam('_client_type', '20')
    ];
    const signed: SignParam[] = await CryptoUtil.appendSign(params, SignSalt.PC);
    return TiebaCommonParams.encodeForm(signed);
  }

  static url(): string {
    return `https://${TiebaHost.WEB}${FrsHeadlineParams.PATH}`;
  }
}

export class FollowParams {
  static path(kind: FollowKind, following: boolean): string {
    return kind === 'user' ? (following ? '/c/c/user/follow' : '/c/c/user/unfollow')
      : (following ? '/c/c/forum/like' : '/c/c/forum/unfavolike');
  }
  static build(device: TiebaDevice, session: TiebaSession, kind: FollowKind,
    id: number, portrait: string): SignParam[] {
    const params: SignParam[] = TiebaCommonParams.build(device, session);
    params.push(new SignParam(kind === 'user' ? 'portrait' : 'fid', kind === 'user' ? portrait : String(id)));
    return params;
  }
}

export class ForumMemberParams {
  static readonly PATH: string = '/c/f/forum/getMemberInfo';
  static readonly CMD: string = '301004';

  static url(): string {
    return `https://${TiebaHost.APP}${ForumMemberParams.PATH}?cmd=${ForumMemberParams.CMD}`;
  }

  static build(device: TiebaDevice, session: TiebaSession, forumId: number): Uint8Array {
    const common: ProtoWriter = new ProtoWriter();
    common.writeInt32(1, 2);
    common.writeString(2, device.clientVersion);
    common.writeString(3, device.clientId);
    common.writeString(7, device.cuid);
    common.writeInt64(8, BigInt(Date.now()));
    common.writeString(9, device.model.length > 0 ? device.model : 'HarmonyOS');
    common.writeString(10, session.bduss);
    if (session.tbs.length > 0) { common.writeString(11, session.tbs); }
    common.writeInt32(12, 1);
    if (device.osVersion.length > 0) { common.writeString(25, device.osVersion); }
    if (session.stoken.length > 0) { common.writeString(30, session.stoken); }
    if (device.cuidGalaxy2.length > 0) { common.writeString(32, device.cuidGalaxy2); }

    const data: ProtoWriter = new ProtoWriter();
    data.writeInt64(1, BigInt(forumId));
    data.writeMessage(2, common.toUint8Array());

    const root: ProtoWriter = new ProtoWriter();
    root.writeMessage(1, data.toUint8Array());
    return SelfProfileParams.wrapMultipart(root.toUint8Array());
  }
}

export class BawuTeamParams {
  static readonly PATH: string = '/c/f/forum/getBawuInfo';
  static readonly CMD: string = '301007';

  static url(): string {
    return `https://${TiebaHost.APP}${BawuTeamParams.PATH}?cmd=${BawuTeamParams.CMD}`;
  }

  static build(device: TiebaDevice, session: TiebaSession, forumId: number): Uint8Array {
    const common: ProtoWriter = new ProtoWriter();
    common.writeInt32(1, 2);
    common.writeString(2, device.clientVersion);
    common.writeString(3, device.clientId);
    common.writeString(7, device.cuid);
    common.writeInt64(8, BigInt(Date.now()));
    common.writeString(9, device.model.length > 0 ? device.model : 'HarmonyOS');
    common.writeString(10, session.bduss);
    if (session.tbs.length > 0) { common.writeString(11, session.tbs); }
    common.writeInt32(12, 1);
    if (device.osVersion.length > 0) { common.writeString(25, device.osVersion); }
    if (session.stoken.length > 0) { common.writeString(30, session.stoken); }
    if (device.cuidGalaxy2.length > 0) { common.writeString(32, device.cuidGalaxy2); }

    const data: ProtoWriter = new ProtoWriter();
    data.writeMessage(1, common.toUint8Array());
    data.writeInt64(2, BigInt(forumId));

    const root: ProtoWriter = new ProtoWriter();
    root.writeMessage(1, data.toUint8Array());
    return SelfProfileParams.wrapMultipart(root.toUint8Array());
  }
}

export class AuthorBlockParams {
  static url(write: boolean): string {
    return write ? `https://${TiebaHost.APP}/c/c/user/setUserBlack?cmd=309697`
      : `https://${TiebaHost.APP}/c/u/user/getUserBlackInfo?cmd=309698`;
  }
  static build(device: TiebaDevice, session: TiebaSession, uid: number, blocked?: boolean): Uint8Array {
    const common: ProtoWriter = new ProtoWriter();
    common.writeInt32(1, 2);
    common.writeString(2, device.clientVersion);
    common.writeString(3, device.clientId);
    common.writeString(7, device.cuid);
    common.writeInt64(8, BigInt(Date.now()));
    common.writeString(9, device.model.length > 0 ? device.model : 'HarmonyOS');
    common.writeString(10, session.bduss);
    if (session.tbs.length > 0) { common.writeString(11, session.tbs); }
    common.writeInt32(12, 1);
    if (device.osVersion.length > 0) { common.writeString(25, device.osVersion); }
    if (session.stoken.length > 0) { common.writeString(30, session.stoken); }
    if (device.cuidGalaxy2.length > 0) { common.writeString(32, device.cuidGalaxy2); }
    const data: ProtoWriter = new ProtoWriter();
    data.writeMessage(1, common.toUint8Array());
    data.writeInt64(2, BigInt(uid));
    if (blocked !== undefined) {
      const permissions: ProtoWriter = new ProtoWriter();
      for (let field: number = 1; field <= 3; field++) { permissions.writeInt32(field, blocked ? 1 : 0); }
      data.writeMessage(3, permissions.toUint8Array());
    }
    const root: ProtoWriter = new ProtoWriter();
    root.writeMessage(1, data.toUint8Array());
    return SelfProfileParams.wrapMultipart(root.toUint8Array());
  }
}

export class ReplyMeParams {
  static readonly PATH: string = '/c/u/feed/replyme';
  static readonly CMD: string = '303007';

  static url(): string {
    return `https://${TiebaHost.APP}${ReplyMeParams.PATH}?cmd=${ReplyMeParams.CMD}`;
  }

  static build(device: TiebaDevice, session: TiebaSession, page: number): Uint8Array {
    const common: ProtoWriter = new ProtoWriter();
    common.writeInt32(1, 2);
    common.writeString(2, device.clientVersion);
    common.writeString(3, device.clientId);
    common.writeString(7, device.cuid);
    common.writeInt64(8, BigInt(Date.now()));
    common.writeString(9, device.model.length > 0 ? device.model : 'HarmonyOS');
    common.writeString(10, session.bduss);
    if (session.tbs.length > 0) { common.writeString(11, session.tbs); }
    common.writeInt32(12, 1);
    if (device.osVersion.length > 0) { common.writeString(25, device.osVersion); }
    if (session.stoken.length > 0) { common.writeString(30, session.stoken); }
    if (device.cuidGalaxy2.length > 0) { common.writeString(32, device.cuidGalaxy2); }

    const data: ProtoWriter = new ProtoWriter();
    data.writeInt32(1, page);
    data.writeMessage(2, common.toUint8Array());

    const root: ProtoWriter = new ProtoWriter();
    root.writeMessage(1, data.toUint8Array());
    return SelfProfileParams.wrapMultipart(root.toUint8Array());
  }
}

export class PrivacyMarksParams {
  static readonly WRITE_PATH: string = '/c/c/thread/setPrivacy';
  static buildChange(device: TiebaDevice, session: TiebaSession, field: PrivacyMarkField, value: number): SignParam[] {
    if (!validPrivacyMark(field, value)) { return []; }
    const params: SignParam[] = TiebaCommonParams.build(device, session);
    params.push(new SignParam('opt', field)); params.push(new SignParam('val', String(value)));
    return params;
  }
  static url(): string { return `https://${TiebaHost.APP}/c/u/user/getPrivateInfo?cmd=303016`; }
  static build(device: TiebaDevice, session: TiebaSession, uid: number): Uint8Array {
    if (!Number.isSafeInteger(uid) || uid <= 0) { throw new Error('隐私标记账号参数无效'); }
    const common: ProtoWriter = new ProtoWriter();
    common.writeInt32(1, 2); common.writeString(2, device.clientVersion); common.writeString(3, device.clientId);
    common.writeString(7, device.cuid); common.writeInt64(8, BigInt(Date.now()));
    common.writeString(9, device.model.length > 0 ? device.model : 'HarmonyOS'); common.writeString(10, session.bduss);
    if (session.tbs.length > 0) { common.writeString(11, session.tbs); }
    common.writeInt32(12, 1);
    if (device.osVersion.length > 0) { common.writeString(25, device.osVersion); }
    if (session.stoken.length > 0) { common.writeString(30, session.stoken); }
    if (device.cuidGalaxy2.length > 0) { common.writeString(32, device.cuidGalaxy2); }
    if (device.c3Aid.length > 0) { common.writeString(35, device.c3Aid); }
    const data: ProtoWriter = new ProtoWriter(); data.writeInt64(1, BigInt(uid)); data.writeMessage(2, common.toUint8Array());
    const root: ProtoWriter = new ProtoWriter(); root.writeMessage(1, data.toUint8Array());
    return SelfProfileParams.wrapMultipart(root.toUint8Array());
  }
}

export class ForbiddenForumsParams {
  static url(): string { return `https://${TiebaHost.APP}/c/u/user/getDislikeList?cmd=309692`; }
  static build(device: TiebaDevice, session: TiebaSession, uid: number, page: number): Uint8Array {
    if (!Number.isSafeInteger(uid) || uid <= 0 || !Number.isInteger(page) || page < 1 || page > 2147483647) {
      throw new Error('屏蔽吧请求参数无效');
    }
    const common: ProtoWriter = new ProtoWriter();
    common.writeInt32(1, 2);
    common.writeString(2, device.clientVersion);
    common.writeString(3, device.clientId);
    common.writeString(7, device.cuid);
    common.writeInt64(8, BigInt(Date.now()));
    common.writeString(9, device.model.length > 0 ? device.model : 'HarmonyOS');
    common.writeString(10, session.bduss);
    if (session.tbs.length > 0) { common.writeString(11, session.tbs); }
    common.writeInt32(12, 1);
    if (device.osVersion.length > 0) { common.writeString(25, device.osVersion); }
    if (session.stoken.length > 0) { common.writeString(30, session.stoken); }
    if (device.cuidGalaxy2.length > 0) { common.writeString(32, device.cuidGalaxy2); }
    if (device.c3Aid.length > 0) { common.writeString(35, device.c3Aid); }
    const data: ProtoWriter = new ProtoWriter();
    data.writeMessage(1, common.toUint8Array());
    data.writeInt64(2, BigInt(uid)); data.writeInt32(3, page); data.writeInt32(4, 20);
    const root: ProtoWriter = new ProtoWriter(); root.writeMessage(1, data.toUint8Array());
    return SelfProfileParams.wrapMultipart(root.toUint8Array());
  }
}

export class SubmitDislikeParams {
  static readonly PATH: string = '/c/c/excellent/submitDislike';

  static readonly FROM_FRS: string = 'frs';

  static readonly DISLIKE_ID_BLOCK_FORUM: string = '7';

  static url(): string { return `https://${TiebaHost.APP}${SubmitDislikeParams.PATH}`; }

  static buildBody(tid: number, fid: number, dislikeIds: string, from: string): string {
    const fields: string[] = [];
    if (tid > 0) { fields.push(`"tid":"${tid}"`); }
    if (fid > 0) { fields.push(`"fid":"${fid}"`); }
    fields.push(`"click_time":${Date.now()}`);
    if (dislikeIds.length > 0) { fields.push(`"dislike_ids":"${dislikeIds}"`); }
    fields.push('"extra":""');
    fields.push(`"dislike_from":"${from}"`);
    return `[{${fields.join(',')}}]`;
  }

  static build(device: TiebaDevice, session: TiebaSession, body: string, from: string): SignParam[] {
    const params: SignParam[] = TiebaCommonParams.build(device, session);
    params.push(new SignParam('dislike', body));
    params.push(new SignParam('dislike_from', from));
    return params;
  }
}

export class CancelForbiddenForumParams {
  static readonly PATH: string = '/c/c/excellent/submitCancelDislike';
  static url(): string { return `https://${TiebaHost.APP}${CancelForbiddenForumParams.PATH}`; }

  static build(device: TiebaDevice, session: TiebaSession, forumId: string): SignParam[] {
    if (forumId.length === 0 || !/^[0-9]+$/.test(forumId)) {
      throw new Error('解除屏蔽吧的参数无效');
    }
    const params: SignParam[] = TiebaCommonParams.build(device, session);
    params.push(new SignParam('forum_id', forumId));
    return params;
  }
}

export class TailsParams {
  static readonly PATH: string = '/c/u/tail/getTails';
  static readonly CMD: string = '305001';
  static url(): string { return `https://${TiebaHost.APP}${TailsParams.PATH}?cmd=${TailsParams.CMD}`; }

  static build(device: TiebaDevice, session: TiebaSession): Uint8Array {
    const data: ProtoWriter = new ProtoWriter();
    data.writeString(1, 'stat');
    data.writeMessage(2, TailsParams.commonBytes(device, session));
    return TailsParams.wrapData(data);
  }

  private static commonBytes(device: TiebaDevice, session: TiebaSession): Uint8Array {
    const common: ProtoWriter = new ProtoWriter();
    common.writeInt32(1, 2);
    common.writeString(2, device.clientVersion);
    common.writeString(3, device.clientId);
    common.writeString(7, device.cuid);
    common.writeInt64(8, BigInt(Date.now()));
    common.writeString(9, device.model.length > 0 ? device.model : 'HarmonyOS');
    common.writeString(10, session.bduss);
    if (session.tbs.length > 0) { common.writeString(11, session.tbs); }
    common.writeInt32(12, 1);
    if (device.osVersion.length > 0) { common.writeString(25, device.osVersion); }
    if (session.stoken.length > 0) { common.writeString(30, session.stoken); }
    if (device.cuidGalaxy2.length > 0) { common.writeString(32, device.cuidGalaxy2); }
    if (device.c3Aid.length > 0) { common.writeString(35, device.c3Aid); }
    return common.toUint8Array();
  }

  private static wrapData(data: ProtoWriter): Uint8Array {
    const root: ProtoWriter = new ProtoWriter();
    root.writeMessage(1, data.toUint8Array());
    return SelfProfileParams.wrapMultipart(root.toUint8Array());
  }

  static changeUrl(action: TailAction): string {
    const name: string = action === 'add' ? 'addTail' : action === 'update' ? 'updateTail'
      : action === 'set' ? 'setTail' : 'deleteTail';
    const cmd: string = action === 'add' ? '305101' : action === 'update' ? '305102'
      : action === 'set' ? '305104' : '305103';
    return `https://${TiebaHost.APP}/c/u/tail/${name}?cmd=${cmd}`;
  }

  static buildChange(device: TiebaDevice, session: TiebaSession, change: TailChange): Uint8Array {
    const error: string = tailChangeError(change);
    if (error.length > 0) { throw new Error(error); }
    const data: ProtoWriter = new ProtoWriter();
    let commonField: number = 2;
    if (change.action === 'add' || change.action === 'update') {
      data.writeString(1, change.content);
      const offset: number = change.action === 'update' ? 1 : 0;
      if (offset === 1) { data.writeInt64(2, BigInt(change.id)); }
      data.writeString(2 + offset, change.fontColor);
      data.writeString(3 + offset, change.fontKeyName);
      commonField = 4 + offset;
    } else if (change.action === 'set') {
      data.writeInt32(1, change.type);
      data.writeInt64(2, BigInt(change.id));
      commonField = 3;
    } else { data.writeInt64(1, BigInt(change.id)); }
    data.writeMessage(commonField, TailsParams.commonBytes(device, session));
    return TailsParams.wrapData(data);
  }
}

export class AgreeMeParams {
  static readonly PATH: string = '/c/u/feed/agreeme';
  static readonly CMD: string = '309593';

  static url(): string {
    return `https://${TiebaHost.APP}${AgreeMeParams.PATH}?cmd=${AgreeMeParams.CMD}`;
  }

  static build(device: TiebaDevice, session: TiebaSession, cursor: number, rn: number): Uint8Array {
    const common: ProtoWriter = new ProtoWriter();
    common.writeInt32(1, 2);
    common.writeString(2, device.clientVersion);
    common.writeString(3, device.clientId);
    common.writeString(7, device.cuid);
    common.writeInt64(8, BigInt(Date.now()));
    common.writeString(9, device.model.length > 0 ? device.model : 'HarmonyOS');
    common.writeString(10, session.bduss);
    if (session.tbs.length > 0) { common.writeString(11, session.tbs); }
    common.writeInt32(12, 1);
    if (device.osVersion.length > 0) { common.writeString(25, device.osVersion); }
    if (session.stoken.length > 0) { common.writeString(30, session.stoken); }
    if (device.cuidGalaxy2.length > 0) { common.writeString(32, device.cuidGalaxy2); }

    const data: ProtoWriter = new ProtoWriter();
    data.writeMessage(1, common.toUint8Array());
    data.writeInt64(2, BigInt(cursor));
    data.writeInt32(3, rn);

    const root: ProtoWriter = new ProtoWriter();
    root.writeMessage(1, data.toUint8Array());
    return SelfProfileParams.wrapMultipart(root.toUint8Array());
  }
}
