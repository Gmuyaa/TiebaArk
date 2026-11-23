import { CreateForumDraft, createForumDraftError } from '../model/CreateForum';
import { ImageUploadChunk, imageUploadChunkError } from '../model/ImageUpload';
import { FollowKind } from '../model/FollowOperation';
import { MessageSettingField, validMessageSetting } from '../model/MessageSettings';
import { TailAction, TailChange, tailChangeError } from '../model/Tails';
import { PrivacyMarkField, validPrivacyMark } from '../model/PrivacyMarks';
import { AtCandidateKind, validAtKind } from '../model/AtCandidates';
import { VideoFeedEnvironment } from '../model/VideoFeed';
/**
 * 贴吧请求的公共参数与客户端身份；客户端版本与域名常量取自 aiotieba 的 const。
 *
 * 本文件只负责装参数，不生成设备指纹：c3_aid / cuid_galaxy2 等依赖与官方一致的算法，
 * 未验证前不要伪造随机值，服务端会校验失败（生成逻辑见 utils/DeviceUtil）。
 */

import { CryptoUtil, SignParam, SignSalt } from '../utils/CryptoUtil';
import { ProtoWriter } from '../proto/ProtoWire';
import { encodeUtf8 } from '../utils/TextCodec';
import { TransferStats, TransferStatsSnapshot } from './TransferStats';

/** 客户端版本常量。不同端点要求不同版本，用错版本服务端会返回格式错误。 */
export class TiebaVersion {
  static readonly LATEST: string = '22.6.5.1';
  /** 楼中楼图片要求此版本；22.6.5.1 会把 type=3 降级为 [图片] 文本。 */
  static readonly SUB_POST: string = '22.11.1.0';
  /** 帖子详情 `/c/f/pb/page`。低版本（22.6.5.1）会把内联楼中楼的图片降级成 `[图片]` 文本，必须用 22.11.1.0。 */
  static readonly DETAIL: string = '22.11.1.0';
  /** 部分依赖旧版响应格式的 API（如帖子列表）使用此版本 */
  static readonly LEGACY: string = '12.64.1.1';
  static readonly CHAT: string = '12.68.1.0';
  /** 点赞接口客户端版本，取值尚无官方证据；UA 由 AgreeParams.CLIENT_VERSION 构造。 */
  static readonly TIEBA_V12: string = '12.52.1.0';
}

export class TiebaHost {
  /** 客户端接口域名（protobuf 与 form 请求） */
  static readonly APP: string = 'tiebac.baidu.com';
  /** 网页接口域名（登录、Cookie 相关） */
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
  /** 建吧参数；没有生产写入口，唯一消费者是 `CreateForum.test`。 */
  static create(device: TiebaDevice, session: TiebaSession, draft: CreateForumDraft): SignParam[] {
    if (session.tbs.length === 0 || createForumDraftError(draft).length > 0) { return []; }
    const params: SignParam[] = TiebaCommonParams.build(device, session);
    params.push(new SignParam('kw', draft.name.trim()), new SignParam('vcode', draft.vcode.trim()),
      new SignParam('vcode_md5', draft.token), new SignParam('name_show', draft.nameShow));
    return params;
  }
}

/** 普通头像整图上传（官方 NetWork.uploadImage），与帖子分片上传是两条链路。 */
export class AvatarUploadParams {
  static readonly PATH: string = '/c/c/img/portrait';
  static readonly BOUNDARY: string = '--------7da3d81520810*';
  static build(device: TiebaDevice, session: TiebaSession): SignParam[] {
    // 当前头像NetWork未开启mIsNeedTbs；不发送帖图业务字段。
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

/** 普通帖图分片上传（官方 NetWork/f8 契约）；multipart 形态与头像上传不同，不能复用。 */
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
  /** 官方 f8：UTF-8 文本，文件片字段名 chunk、filename=file，不给文件片单独加 Content-Type。 */
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

/** 官方 GetImageWatermarkTypeModel：只读请求没有业务参数。 */
export class ImageWatermarkParams {
  static readonly READ_PATH: string = '/c/u/user/getWatermark';
  static build(device: TiebaDevice, session: TiebaSession): SignParam[] {
    return TiebaCommonParams.build(device, session);
  }
}

/** 官方 FriendAndStrangerReqMsg：每次只发 maskType 或非零 pushType，不混发。 */
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

/** AtListActivity 的普通选人分支；聊天/百家号的 follow/list 分支不可当作关注/粉丝。 */
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

/** 官方 pwb/cxb.makeHttpParam：普通首屏/续页，没有已读位置 ids 与筛选参数。 */
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

/** 官方 s66→in6 资源类型 23：普通下载不带签名、凭据或 play_from 参数。 */
export class VoiceAudioParams {
  static url(id: string): string {
    if (id.length === 0 || id.trim() !== id || /[\s\u0000-\u001f\u007f]/.test(id)) { return ''; }
    if (id.includes('://')) {
      // 原加载器支持 HTTPS 地址；拒绝凭据、非 HTTPS、IP/本机和不规范地址。
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

/** 官方 SettingStatic/OfficialAccountPushRequestMessage：cmd=309620，请求体只有 common。 */
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

/** 设备与身份参数：决定服务端把请求当成哪台设备上的哪个客户端，缺失或格式不符会鉴权失败或返回降级内容；字段长度与字符集有协议约束，不要随意截断或补位。 */
export class TiebaDevice {
  /** 16 位小写十六进制，8 字节。例：91be894d01799c49 */
  androidId: string = '';
  /** 设备 UUID，含 16 字节信息。例：e4200716-58a8-4170-af15-ea7edeb8e513 */
  uuid: string = '';
  /** cuid，形如 baidutiebaapp<uuid> */
  cuid: string = '';
  /** 42 字符，形如 A3ED2D7B9CFC28E8934A3FBD3A9579C7|VZ5FKB5XS */
  cuidGalaxy2: string = '';
  /** 45 字符，形如 A00-ZNU3O3EP74D727LMQY745CZSGZQJQZGP-3JXCKC7X */
  c3Aid: string = '';
  /** 形如 wappc_1653660000000_123 */
  clientId: string = '';
  clientVersion: string = TiebaVersion.LATEST;
  /** _os_version 使用 deviceInfo.sdkApiVersion，空串不发送。 */
  osVersion: string = '';
  /** net_type 固定为 1（尚无官方取值证据）；空串不发送。 */
  netType: string = '';
  /** model 使用 deviceInfo.model，空串不发送。 */
  model: string = '';

  isUsable(): boolean {
    return this.androidId.length > 0 && this.uuid.length > 0 && this.cuid.length > 0;
  }
}

/** 登录态。凭证只应存在于内存与安全存储中，不得写入日志或源码。 */
export class TiebaSession {
  /** BDUSS，客户端接口的鉴权载体；属账号凭证，日志与异常信息中必须脱敏。 */
  bduss: string = '';
  /** 网页 STOKEN。仅部分网页接口需要。 */
  stoken: string = '';
  /** tbs，26 位小写十六进制。发帖/签到等写操作需要。 */
  tbs: string = '';

  hasBduss(): boolean {
    return this.bduss.length > 0;
  }
}

/**
 * 点赞对象类型（`obj_type`），取值来自 aiotieba `api/agree/_api.py` 的三分支。
 *
 * 主帖点赞与首楼点赞不是一回事：主题是 `obj_type=3` 且 `post_id=0`；传了 `post_id` 才按楼层/楼中楼分 1/2。
 */
export enum AgreeObjType {
  /** 主题帖（主帖、底栏点赞）：`obj_type=3`，`post_id` 必须为 0 */
  THREAD = 3,
  /** 普通楼层：`obj_type=1`，`post_id=<pid>` */
  POST = 1,
  /** 楼中楼（楼层内的评论）：`obj_type=2`，`post_id=<pid>` */
  SUB_POST = 2
}

/** 写请求的反爬统计参数，依据官方 NetWork.addStatisticsDataParam 与 NetWorkState：只保留最近一条统计、不自动重试（stTimesNum=0、stMode=1）；无可用统计时只发 timestamp 与 stErrorNums，失败时回填统计与错误数。 */
export class AntiSpamParams {
  /** 取用实际传输统计生成一次（生产路径走这个） */
  static generate(nowMs: number): SignParam[] {
    const stats: TransferStatsSnapshot | undefined = TransferStats.take();
    const errorNums: number = TransferStats.takeErrorNums();
    return AntiSpamParams.compose(nowMs, stats, errorNums);
  }

  /** 固定取值版本，**只给用例锁签名用**（真实统计随网络变化，无法与独立算出的期望值比对） */
  static fixed(nowMs: number, stTime: number, stSize: number): SignParam[] {
    const stats: TransferStatsSnapshot = new TransferStatsSnapshot();
    stats.elapsedMs = stTime;
    stats.bytes = stSize;
    return AntiSpamParams.compose(nowMs, stats, 0);
  }

  /** 按官方取值顺序组装；`stats` 为空表示本次没有统计可用 */
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

  /** 日志用：只取时间戳与传输统计，两者都不是凭据。 */
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

/** opAgree 的字段与签名依据官方 TbConfig、HttpRequest、CommonReq 与 NetWork：未编码原值按 key 排序拼接后加盐取 MD5，最后追加 sign。mini 域、12.52.1.0、ka=open 尚无完整官方证据，不应视为已确认协议。 */
export class AgreeParams {
  /** 待定：官方缺省 host 是 `tiebac.baidu.com`，当前为本项目沿用的 mini 域取值 */
  static readonly HOST: string = 'c.tieba.baidu.com';
  /** 与官方 `PB_FLOOR_AGREE_URL` 一致（官方写作相对路径，无前导斜杠） */
  static readonly PATH: string = '/c/c/agree/opAgree';
  /** 待定：本项目沿用的客户端版本号，尚无官方取值 */
  static readonly CLIENT_VERSION: string = '12.52.1.0';
  /** 官方设备标识回退值：固定 15 个 0（`DeviceInfoHelper.java:36-37`） */
  static readonly PHONE_IMEI: string = '000000000000000';
  /** 待定：本项目沿用的网络类型值，尚无官方取证 */
  static readonly NET_TYPE: string = '1';
  /** 待定：本项目沿用的 Cookie，尚无官方取证 */
  static readonly COOKIE: string = 'ka=open';

  /** 拼出已按 key 排序的待签名参数表（不含 `sign`）：本项目签名前按 key 升序排，所以 body 的字节顺序也是排序序。 */
  static build(device: TiebaDevice, session: TiebaSession, uid: number, tid: number,
    pid: number, opType: string, objType: AgreeObjType, antiSpam: SignParam[],
    forumId: number = 0): SignParam[] {
    const params: SignParam[] = [];

    // ① opAgree 自带的 5 个
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

    // ② 账号（官方公共字段）
    params.push(new SignParam('BDUSS', session.bduss));
    // STOKEN 只在非空时进参数表与签名输入
    if (session.stoken.length > 0) {
      params.push(new SignParam('STOKEN', session.stoken));
    }
    params.push(new SignParam('tbs', session.tbs));

    // ③ 设备身份（官方公共字段）
    params.push(new SignParam('cuid', device.cuid));
    params.push(new SignParam('cuid_galaxy2', device.cuidGalaxy2));
    params.push(new SignParam('_client_id', device.clientId));
    params.push(new SignParam('_client_type', '2'));
    params.push(new SignParam('_client_version', AgreeParams.CLIENT_VERSION));
    params.push(new SignParam('_os_version', device.osVersion));
    params.push(new SignParam('model', device.model));
    params.push(new SignParam('net_type', AgreeParams.NET_TYPE));
    params.push(new SignParam('_phone_imei', AgreeParams.PHONE_IMEI));

    // ④ 反爬组（本项目自己测量的传输统计，见 AntiSpamParams）
    for (let i = 0; i < antiSpam.length; i++) {
      params.push(antiSpam[i]);
    }

    // ⑤ 排序（本项目签名口径：先排序再拼 body）
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

  /** 本项目当前请求头组（尚无官方取证）：UA 由 `_client_version` 拼出，`client_user_token` 是账号 uid。 */
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

/** 公共参数构造器：把设备、会话、版本拼成待签名参数表 */
export class TiebaCommonParams {

  /** 构造待签名的公共参数；调用方使用 CryptoUtil.appendSign 追加签名。 */
  static build(device: TiebaDevice, session: TiebaSession): SignParam[] {
    const params: SignParam[] = [];

    params.push(new SignParam('_client_type', '2'));
    params.push(new SignParam('_client_version', device.clientVersion));
    params.push(new SignParam('_phone_imei', device.androidId));
    params.push(new SignParam('from', '1020011'));
    params.push(new SignParam('model', 'HarmonyOS'));

    // 设备身份字段要与请求头、客户端版本保持一致
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

    // 登录态：BDUSS 存在才带上，未登录请求不加此字段
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

/** 用户资料走 multipart protobuf：请求头 `x_bd_data_type: protobuf`，part 名 data、filename=file（形态参考 aiotieba core/http.py pack_proto_request，Unlicense）。 */
export class SelfProfileParams {
  static readonly PATH: string = '/c/u/user/profile';
  /** aiotieba `api/profile/_const.py` 的 `CMD` */
  static readonly CMD: string = '303012';
  /** multipart 分隔符（沿用 aiotieba 的固定值） */
  static readonly BOUNDARY: string = '-*_r1999';
  static readonly PROTO_HEADER: string = 'x_bd_data_type';
  static readonly PROTO_HEADER_VALUE: string = 'protobuf';

  /** 构造 ProfileReqIdl；查询本人用 friend_uid_portrait，passport 的 open_uid 不等于贴吧 User.id。字段号依据官方 ProfileReqIdl、DataReq 与 CommonReq。 */
  static buildRequest(portrait: string, device: TiebaDevice): Uint8Array {
    return SelfProfileParams.buildForUser(0, portrait, device, 1);
  }

  /** 官方 Profile.DataReq：16=portrait、3=friend_uid；不使用 passport 的 open_uid。 */
  static buildForUser(uid: number, portrait: string, device: TiebaDevice, page: number): Uint8Array {
    const common: ProtoWriter = new ProtoWriter();
    common.writeInt32(1, 2);                       // _client_type = 2（客户端）
    common.writeString(2, device.clientVersion);   // _client_version
    if (device.clientId.length > 0) {
      common.writeString(3, device.clientId);      // _client_id
    }
    if (device.androidId.length > 0) {
      common.writeString(5, device.androidId);     // _phone_imei
    }
    if (device.cuid.length > 0) {
      common.writeString(7, device.cuid);          // cuid
    }
    common.writeString(9, device.model.length > 0 ? device.model : 'HarmonyOS'); // model
    const netType: number = Number.parseInt(device.netType, 10);
    if (!Number.isNaN(netType) && netType > 0) {
      common.writeInt32(12, netType);              // net_type
    }
    if (device.osVersion.length > 0) {
      common.writeString(25, device.osVersion);    // _os_version
    }
    if (device.cuidGalaxy2.length > 0) {
      common.writeString(32, device.cuidGalaxy2);  // cuid_galaxy2
    }
    if (device.c3Aid.length > 0) {
      common.writeString(35, device.c3Aid);        // c3_aid
    }

    const data: ProtoWriter = new ProtoWriter();
    if (portrait.length > 0) {
      data.writeString(16, portrait);              // friend_uid_portrait 优先定位
    } else if (uid > 0) {
      data.writeInt64(3, BigInt(uid));             // friend_uid，真实贴吧 uid
    }
    data.writeInt32(2, 1);                         // need_post_count = 1
    data.writeInt32(6, page);                      // pn
    data.writeMessage(9, common.toUint8Array());   // common

    const root: ProtoWriter = new ProtoWriter();
    root.writeMessage(1, data.toUint8Array());     // data
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

  /** 完整请求 URL（携带凭据的请求只使用 HTTPS） */
  static url(host: string): string {
    return `https://${host}${SelfProfileParams.PATH}?cmd=${SelfProfileParams.CMD}`;
  }

  /** 必须含 `x_bd_data_type: protobuf`，否则服务端回 110001；pb 通道不签名，身份靠 Cookie（BDUSS/STOKEN）。 */
  static headers(session: TiebaSession): Record<string, string> {
    const h: Record<string, string> = {};
    h['Content-Type'] = `multipart/form-data; boundary=${SelfProfileParams.BOUNDARY}`;
    h[SelfProfileParams.PROTO_HEADER] = SelfProfileParams.PROTO_HEADER_VALUE;
    h['Cookie'] = `BDUSS=${session.bduss}; STOKEN=${session.stoken}`;
    return h;
  }
}

/** 用户内容请求（aiotieba get_user_contents，Unlicense；字段号经官方 UserPostReqIdl、DataReq 与 CommonReq 核对）：is_thread=1 主题、0 回复；不签名，BDUSS 放入 common。 */
export class UserPostParams {
  static readonly PATH: string = '/c/u/feed/userpost';
  /** aiotieba `get_user_contents/_const.py` 的 `CMD` */
  static readonly CMD: string = '303002';

  /** `uid` 必须是真实贴吧 uid，**不是** `json_userinfo.open_uid`；`isThread` 1 = 主题帖，0 = 回复。 */
  static buildRequest(uid: number, isThread: number, pn: number, rn: number,
    device: TiebaDevice, session: TiebaSession): Uint8Array {
    const common: ProtoWriter = new ProtoWriter();
    common.writeInt32(1, 2);                       // _client_type = 2（客户端）
    common.writeString(2, device.clientVersion);   // _client_version
    if (device.clientId.length > 0) {
      common.writeString(3, device.clientId);      // _client_id
    }
    if (device.androidId.length > 0) {
      common.writeString(5, device.androidId);     // _phone_imei
    }
    if (device.cuid.length > 0) {
      common.writeString(7, device.cuid);          // cuid
    }
    common.writeString(9, device.model.length > 0 ? device.model : 'HarmonyOS'); // model
    if (session.bduss.length > 0) {
      common.writeString(10, session.bduss);       // BDUSS
    }
    const netType: number = Number.parseInt(device.netType, 10);
    if (!Number.isNaN(netType) && netType > 0) {
      common.writeInt32(12, netType);              // net_type
    }
    if (device.osVersion.length > 0) {
      common.writeString(25, device.osVersion);    // _os_version
    }
    if (device.cuidGalaxy2.length > 0) {
      common.writeString(32, device.cuidGalaxy2);  // cuid_galaxy2
    }
    if (device.c3Aid.length > 0) {
      common.writeString(35, device.c3Aid);        // c3_aid
    }

    const data: ProtoWriter = new ProtoWriter();
    data.writeInt64(1, BigInt(uid));               // uid
    data.writeInt32(2, rn);                        // rn
    data.writeInt32(4, isThread);                  // is_thread
    data.writeInt32(5, 1);                         // need_content = 1（要正文）
    data.writeInt32(26, pn);                       // pn
    data.writeInt32(33, 1);                        // is_view_card
    data.writeMessage(27, common.toUint8Array());  // common

    const root: ProtoWriter = new ProtoWriter();
    root.writeMessage(1, data.toUint8Array());     // data
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

/** 个性化推荐流：multipart protobuf、不签名、Cookie 鉴权（端点与 cmd 依据官方 TbConfig 与 RecPersonalizePageModel，字段号已核对 PersonalizedReqIdl、DataReq 与 CommonReq）；load_type=1 刷新、2 续页，时间戳用毫秒。 */
export class PersonalizedParams {
  static readonly PATH: string = '/c/f/excellent/personalized';
  static readonly CMD: string = '309264';
  /** 官方 load_type 语义：1 = 刷新（首屏/下拉刷新），2 = 加载更多（翻页） */
  static readonly LOAD_REFRESH: number = 1;
  static readonly LOAD_MORE: number = 2;
  /** 官方默认每页 11 条（存档 page_thread_count） */
  static readonly PAGE_THREAD_COUNT: number = 11;

  static buildRequest(loadType: number, pn: number, pageThreadCount: number,
    device: TiebaDevice, session: TiebaSession, requestTimes: number = 0): Uint8Array {
    const common: ProtoWriter = new ProtoWriter();
    common.writeInt32(1, 2);                       // _client_type = 2（客户端）
    common.writeString(2, device.clientVersion);   // _client_version
    if (device.cuid.length > 0) {
      common.writeString(7, device.cuid);          // cuid
    }
    common.writeInt64(8, BigInt(Date.now()));      // _timestamp（毫秒）
    if (session.bduss.length > 0) {
      common.writeString(10, session.bduss);       // BDUSS（V12 必传）
    }
    common.writeInt32(12, 1);                      // net_type = 1
    if (session.stoken.length > 0) {
      common.writeString(30, session.stoken);      // stoken（可选，非空才发）
    }

    const data: ProtoWriter = new ProtoWriter();
    data.writeMessage(1, common.toUint8Array());   // common
    data.writeInt32(4, loadType);                  // load_type：1=刷新 / 2=加载更多
    data.writeInt32(5, pageThreadCount);           // page_thread_count
    data.writeInt32(6, pn);                        // pn
    data.writeInt32(11, 1);                        // q_type
    data.writeInt32(22, 0);                        // need_forumlist
    data.writeInt32(23, 1);                        // new_net_type
    data.writeInt32(27, 0);                        // new_install
    data.writeInt32(28, requestTimes);

    const root: ProtoWriter = new ProtoWriter();
    root.writeMessage(1, data.toUint8Array());     // data
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

/** 收藏载荷（官方 MarkModel 与 fv7）：data 是 JSON 数组字符串，原值参与签名、发送时才编码；取消收藏发 user_id、tid、fid。tid/pid 用字符串、status 用数字、取消时 fid 用字面量 null 的取值尚未完整核实官方语义。 */
export class StoreParams {
  static readonly ADD_PATH: string = '/c/c/post/addstore';
  static readonly RM_PATH: string = '/c/c/post/rmstore';
  /** 待定：本项目 `fid` 当前占位值为字面字符串 `"null"`，尚无官方取值证据；保留现值 */
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

/** 收藏表情：公共参数 + 签名。getAllMeme 无业务参数；collect 的 pics 是 pic_id 对象数组的 JSON 字符串，按全量替换处理，清空用 all_delete。 */
export class MemeEmojiParams {
  static readonly ALL_PATH: string = '/c/e/meme/getAllMeme';
  static readonly COLLECT_PATH: string = '/c/e/meme/collect';
  /** 清空收藏时 `pics` 字段的字面量（照抄官方 UserCollectModel） */
  static readonly ALL_DELETE: string = 'all_delete';

  static buildAll(device: TiebaDevice, session: TiebaSession): SignParam[] {
    return TiebaCommonParams.build(device, session);
  }

  static buildCollect(device: TiebaDevice, session: TiebaSession, pics: string,
    picUpdateTimeMs: number): SignParam[] {
    const params: SignParam[] = TiebaCommonParams.build(device, session);
    // 官方 UserCollectModel 先把 JSON 交给 wp4.t 编码再进签名层；all_delete 原样透传。
    const encoded: string = pics === MemeEmojiParams.ALL_DELETE ? pics : encodeURIComponent(pics)
      .replace(/[!'()~]/g, (char: string): string => '%' + char.charCodeAt(0).toString(16).toUpperCase())
      .replace(/%20/g, '+');
    params.push(new SignParam('pics', encoded));
    params.push(new SignParam('pic_update_time', String(picUpdateTimeMs)));
    return params;
  }
}

/** 回复走 multipart protobuf，不签名，需要 Cookie、BDUSS 与 tbs（端点依据官方 AddPostRequest，字段号依据 AddPostDataReq）。字段 44/45/46/49 的取值语义尚未逐项确认，改动须靠发布后读回验证。 */
export class AddPostParams {
  static readonly PATH: string = '/c/c/post/add';
  /** cmd：官方 `AddPostRequest` 的 309731。 */
  static readonly CMD: string = '309731';

  /** `post_from`：一级评论（对主帖发言）的取值 */
  static readonly POST_FROM_THREAD: string = '13';
  /** `post_from`：回复某个楼层（非楼中楼）的取值 */
  static readonly POST_FROM_POST: string = '0';
  /** `data(16)`：本项目当前固定填 `"12"`；官方取值与具体语义尚未举证，待定 */
  static readonly CLIENT_TYPE_TAG: string = '12';

  static buildRequest(content: string, fid: string, forumName: string, tid: string,
    device: TiebaDevice, session: TiebaSession,
    target?: AddPostTarget, nickname?: string, withTail?: boolean): Uint8Array {
    if (withTail !== undefined && typeof withTail !== 'boolean') { throw new Error('小尾巴附加选项无效'); }
    const nowMs: number = Date.now();
    const nowSec: number = Math.floor(nowMs / 1000);
    const common: ProtoWriter = new ProtoWriter();
    common.writeInt32(1, 2);                        // _client_type = 2（客户端）
    common.writeString(2, device.clientVersion);    // _client_version
    if (device.clientId.length > 0) {
      common.writeString(3, device.clientId);       // _client_id
    }
    if (device.cuid.length > 0) {
      common.writeString(7, device.cuid);           // cuid
    }
    common.writeInt64(8, BigInt(nowMs));            // _timestamp（毫秒）
    common.writeString(9, device.model.length > 0 ? device.model : 'HarmonyOS'); // model
    if (session.bduss.length > 0) {
      common.writeString(10, session.bduss);        // BDUSS（pb 通道的身份载体）
    }
    if (session.tbs.length > 0) {
      common.writeString(11, session.tbs);          // tbs（写操作必传）
    }
    common.writeInt32(12, 1);                       // net_type = 1
    if (device.osVersion.length > 0) {
      common.writeString(25, device.osVersion);     // _os_version
    }
    if (session.stoken.length > 0) {
      common.writeString(30, session.stoken);       // stoken（可选）
    }
    if (device.cuidGalaxy2.length > 0) {
      common.writeString(32, device.cuidGalaxy2);   // cuid_galaxy2
    }

    const data: ProtoWriter = new ProtoWriter();
    data.writeMessage(1, common.toUint8Array());    // common
    data.writeString(16, AddPostParams.CLIENT_TYPE_TAG); // 本项目当前固定值，尚无官方取值证据
    data.writeString(19, content);                  // content = 19（正文）
    data.writeString(26, fid);                      // fid = 26（吧 id）
    data.writeString(30, forumName);                // kw = 30（官方名 kw；本项目填吧名）
    data.writeString(44, fid);                      // from_fourm_id = 44（官方名；本项目当前与 26 同值）
    data.writeString(45, tid);                      // tag = 45（官方名；本项目填 tid，语义未对账）
    if (target !== undefined && target.postId.length > 0) {
      data.writeString(46, target.postId);          // quote_id = 46（官方名；本项目填楼层 pid）
      data.writeString(49, target.postId);          // repostid = 49（官方名；同上）
    }
    if (target !== undefined && target.subPostId.length > 0) {
      data.writeString(50, target.subPostId);       // sub_post_id（回复楼中楼）
    }
    if (target !== undefined && target.replyUid.length > 0) {
      data.writeString(20, target.replyUid);        // reply_uid（回复某人）
    }
    if (nickname !== undefined && nickname.length > 0) {
      data.writeString(58, nickname);               // name_show = 58（官方名；本项目填昵称）
    }
    if (target === undefined || target.postId.length === 0) {
      // 一级评论（对主帖发言）
      data.writeString(55, AddPostParams.POST_FROM_THREAD); // post_from = 13
      data.writeString(32, '0');
    } else if (target.subPostId.length === 0) {
      // 回复某个楼层
      data.writeString(55, AddPostParams.POST_FROM_POST);   // post_from = 0
    }
    data.writeInt64(64, BigInt(0));
    data.writeInt64(67, BigInt(0));
    // with_tail = 76（22.11.1 的 AddPost.DataReq，uint32），独立于正文；未指定就不发 0/1，不从管理页状态推断。
    if (withTail !== undefined) { data.writeInt32(76, withTail ? 1 : 0); }

    const root: ProtoWriter = new ProtoWriter();
    root.writeMessage(1, data.toUint8Array());      // data
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

/** 回复目标：`postId` 为空 = 对主帖发一级评论，给了 = 回复该楼层，`subPostId` 再给 = 回复楼中楼。 */
export class AddPostTarget {
  postId: string = '';
  subPostId: string = '';
  replyUid: string = '';
}

/**
 * 发**主题帖**走 form 表单 `POST /c/c/thread/add`，与回复用的 protobuf `AddPostParams` 是两条链路。
 *
 * 选表单是因为响应是 JSON、字段名可读，且本站已有 `forumGuide` 这类带 Cookie 的表单写接口先例；
 * protobuf 版（`?cmd=309730`）还缺 DataReq 字段编号取证。只发有来源的项：`z_id` 没有数据源就不发，
 * 服务端若回报缺参再按真实报错补。取证见 `docs/协议/APK分析/023-D-01 发主题帖与 C-02 投票（REA 取证补充）.md`。
 */
export class AddThreadParams {
  static readonly PATH: string = '/c/c/thread/add';


  /**
   * 构造待签名表单参数：`TiebaCommonParams` 打底（含 BDUSS/STOKEN/tbs），再追加发帖字段；
   * 签名由调用方 `CryptoUtil.appendSign(..., SignSalt.APP)` 追加。
   *
   * 不能走免签 web 表单：只发 Cookie + `client_user_token` 会稳定回 `error_code=110001`（参数/签名校验失败）。
   */
  static build(device: TiebaDevice, session: TiebaSession, title: string, content: string,
    fid: number, forumName: string, nickname: string, topicId: number,
    isHide: string, contentStatement: string): SignParam[] {
    const params: SignParam[] = TiebaCommonParams.build(device, session);
    params.push(new SignParam('content', content));
    params.push(new SignParam('kw', forumName));
    params.push(new SignParam('fid', String(fid)));
    params.push(new SignParam('title', title));
    params.push(new SignParam('is_hide', isHide));
    params.push(new SignParam('is_ntitle', title.length > 0 ? '1' : '0'));
    params.push(new SignParam('is_feedback', '0'));
    // 参考实现原样发字符串 'null'（不是空串）；服务端按"无回复目标"处理
    params.push(new SignParam('reply_uid', 'null'));
    params.push(new SignParam('takephoto_num', '0'));
    params.push(new SignParam('entrance_type', '1'));
    params.push(new SignParam('vcode_tag', '12'));
    params.push(new SignParam('new_vcode', '1'));
    params.push(new SignParam('anonymous', '1'));
    params.push(new SignParam('call_from', '2'));
    params.push(new SignParam('can_no_forum', '0'));
    params.push(new SignParam('cuid_gid', ''));
    /* 话题：官方写帖 Model 与 proto AddThreadRequest.encode 都用同一个键 `topic_id`，值是不带前缀的整数 id；只有选了话题才发。 */
    if (topicId > 0) { params.push(new SignParam('topic_id', String(topicId))); }
    /*
     * 展示范围与内容声明，取证自 PC 发帖页 bundle `tb3.bdstatic.com/tb/pc/pc-main-core/static/js/publish.<hash>.js`：
     * `is_hide` 取 '0'（全场景可见）或 '1'（个人主页不可见）；`content_statement` 传声明文案本身，不传下标，
     * `ext` 里同时带这两个字段。旧实现把展示范围当成 `is_repost_to_dynamic`（form 通道从不发该键），已废弃。
     */
    const statement: string = contentStatement.trim();
    if (statement.length > 0) {
      params.push(new SignParam('content_statement', statement));
    }
    const ext: string = statement.length > 0
      ? `{"is_hide":"${isHide}","needImage":"1","content_statement":${JSON.stringify(statement)}}`
      : `{"is_hide":"${isHide}","needImage":"1"}`;
    params.push(new SignParam('ext', ext));
    if (nickname.length > 0) { params.push(new SignParam('name_show', nickname)); }
    return params;
  }
}

/** PC 吧头图接口，响应取 activityhead.head_imgs[].img_url；签名前先对 kw 做一次 URL 编码，用 SignSalt.PC。 */
export class FrsHeadlineParams {
  static readonly PATH: string = '/c/f/frs/frsBottom_pc';

  /**
   * `kw` 先 `encodeURIComponent` 再参与 MD5，发送时 `encodeForm` 又编码一次 → 服务端收到双编码值，
   * decode 两次得到吧名，与浏览器 HAR 逐字节一致。`tbs` 传空也能通。
   */
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

/** 关注写操作复用公共签名参数，BDUSS/tbs 只由公共容器加入一次。 */
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

/** GetMemberInfo（cmd 301004）：请求 data{forum_id=1, common=2}，响应 data=1、error=2，与常用 error=1 的信封不同。依据官方 ForumMemberRequestMessage 与 GetMemberInfo proto。 */
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

/**
 * 官方 `GetBawuInfo`（吧务全量名单）：消息 id 1001705，API cmd = 301007
 * （`BawuTeamRequestMessage` 的 `super(1001705, 301007)` 反编译证据）。
 *
 * ⚠️ 字段顺序与 `GetMemberInfo` 相反：`DataReq{ common=1, forum_id=2 }`；响应 `DataRes.bawu_team_info=1`
 * 才是 `BawuTeam{ total_num=1, bawu_team_list=2 }`，比成员端点多一层。
 */
export class BawuTeamParams {
  static readonly PATH: string = '/c/f/forum/getBawuInfo';
  static readonly CMD: string = '301007';

  static url(): string {
    return `https://${TiebaHost.APP}${BawuTeamParams.PATH}?cmd=${BawuTeamParams.CMD}`;
  }

  /** `root{ data{ common=1, forum_id=2 } }` */
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

/** 官方 UserBlockSetModel：309697 写，309698 读；权限 1 表示选中拉黑。 */export class AuthorBlockParams {
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

  /** `ReplyMeReqIdl.DataReq`：`pn=1`、`ids=2`、`common=3`；不能把 `common` 写进 2，否则服务端按旧版客户端裁剪最新回复。 */
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
    data.writeMessage(3, common.toUint8Array());

    const root: ProtoWriter = new ProtoWriter();
    root.writeMessage(1, data.toUint8Array());
    return SelfProfileParams.wrapMultipart(root.toUint8Array());
  }
}

/** 独立的消息计数读取；bookmark=1 与消息列表读取分离。 */
export class NotifyUnreadParams {
  static readonly PATH: string = '/c/s/msg';
  static build(device: TiebaDevice, session: TiebaSession): SignParam[] {
    const params: SignParam[] = TiebaCommonParams.build(device, session);
    params.push(new SignParam('bookmark', '1'));
    return params;
  }
}

/** 移除单个粉丝；只改变TA对我的关注，不执行拉黑或取消我对TA的关注。 */
export class RemoveFanParams {
  static readonly PATH: string = '/c/c/user/removeFans';
  static build(device: TiebaDevice, session: TiebaSession, uid: number): SignParam[] {
    if (!session.hasBduss() || session.tbs.length === 0 || !Number.isSafeInteger(uid) || uid <= 0) { return []; }
    const params: SignParam[] = TiebaCommonParams.build(device, session);
    params.push(new SignParam('fans_uid', String(uid)));
    return params;
  }
}

/** 本人内容：主题主页可见权限，以及主题、普通回复、楼中楼的删除参数。 */
export class MyThreadParams {
  static readonly VISIBILITY_PATH: string = '/c/c/thread/setPrivacy';
  static readonly DELETE_PATH: string = '/c/c/bawu/delthread';
  static readonly DELETE_POST_PATH: string = '/c/c/bawu/delpost';
  static readonly REPLY_PERMISSION_PATH: string = '/c/c/friend/setprivate';

  /** 官方 PrivacySettingMessage(opt="reply", val=1/5/6/7) + setTid：缺 tid 会改账号全局权限，必须带正整数 tid。 */
  static replyPermission(device: TiebaDevice, session: TiebaSession, tid: number, writeValue: number): SignParam[] {
    if (!Number.isSafeInteger(tid) || tid <= 0 ||
      (writeValue !== 1 && writeValue !== 5 && writeValue !== 6 && writeValue !== 7)) {
      return [];
    }
    const params: SignParam[] = TiebaCommonParams.build(device, session);
    params.push(new SignParam('opt', 'reply'), new SignParam('val', String(writeValue)),
      new SignParam('tid', String(tid)));
    return params;
  }

  /** 官方 SetPrivacyModel：帖子级范围，不使用全局 opt/val。 */
  static visibility(device: TiebaDevice, session: TiebaSession, uid: number, fid: number,
    tid: number, pid: number, hidden: boolean): SignParam[] {
    const params: SignParam[] = TiebaCommonParams.build(device, session);
    params.push(new SignParam('user_id', String(uid)), new SignParam('forum_id', String(fid)),
      new SignParam('thread_id', String(tid)), new SignParam('post_id', String(pid)),
      new SignParam('is_hide', hidden ? '1' : '0'));
    return params;
  }

  /** 单主题删除；is_frs_mask=0 为删除，不能用主页隐藏替代。 */
  static deleteThread(device: TiebaDevice, session: TiebaSession, fid: number, tid: number): SignParam[] {
    const params: SignParam[] = TiebaCommonParams.build(device, session);
    params.push(new SignParam('fid', String(fid)), new SignParam('z', String(tid)),
      new SignParam('is_frs_mask', '0'));
    return params;
  }

  /** 官方 ForumManageModel 本人回复分支；楼中楼传子回复 pid，不传所属楼层 pid。 */
  static deletePost(device: TiebaDevice, session: TiebaSession, fid: number, tid: number,
    pid: number, isSubPost: boolean): SignParam[] {
    const params: SignParam[] = TiebaCommonParams.build(device, session);
    params.push(new SignParam('fid', String(fid)), new SignParam('z', String(tid)),
      new SignParam('pid', String(pid)), new SignParam('isfloor', isSubPost ? '1' : '0'),
      new SignParam('src', isSubPost ? '3' : '1'), new SignParam('delete_my_post', '1'),
      new SignParam('is_vipdel', '0'));
    return params;
  }
}

/** 官方 PrivateInfoNetMessage：当前账号 uid，GetPrivateInfoReq data=1{uid=1,common=2}。 */
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

/** 官方 ForbiddenForumReqMsg / ule：当前账号 uid，pn 从 1 起，rn=20。 */
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

/** 屏蔽贴吧走官方 submitDislike 负反馈接口：dislike 是 JSON 数组，原因 ID 为 7。请求被接收不等于已落库，成功与否要读屏蔽列表核对。 */
export class SubmitDislikeParams {
  static readonly PATH: string = '/c/c/excellent/submitDislike';
  /** 负反馈来源：首页推荐流（官方 `FrsFragment.java:6453` 传的就是 "frs"） */
  static readonly FROM_FRS: string = 'frs';

  static readonly DISLIKE_ID_BLOCK_FORUM: string = '7';


  /** 构造单元素 `dislike` 数组；`fid`/`tid` 传 0 时不写该字段（官方是有值才写，不写空串）。 */
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

/** 取消屏蔽走 submitCancelDislike，参数为 forum_id，需有效 tbs；依据官方 ml8.java 的 HttpMessage(1003487)。 */
export class CancelForbiddenForumParams {
  static readonly PATH: string = '/c/c/excellent/submitCancelDislike';


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
  /** 官方管理页传 st_type="stat"；GetTailsReqIdl{data=1{st_type=1,common=2}}。 */
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

/**
 * 官方「赞我」：消息 id 1002211，API cmd = 309593
 * （`ij7.java` 静态注册 `ur8.c(309593, 1002211, "c/u/feed/agreeme", …)`）。
 *
 * 请求 `AgreeMeRequestMessage.id` 是上一批最后一条的 `AgreeList.id`（游标分页，首屏传 0），`rn` 是每页条数。
 * 字段号：`AgreeMeReqIdl{ data=1 }`、`DataReq{ common=1, id=2(uint64), rn=3 }`、
 * `AgreeMeResIdl{ error=1, data=2 }`、`DataRes{ has_more=1, agree_list=2 }`。
 */
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
