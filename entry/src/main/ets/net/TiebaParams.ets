import { CreateForumDraft, createForumDraftError } from '../model/CreateForum';
import { ImageUploadChunk, imageUploadChunkError } from '../model/ImageUpload';
import { FollowKind } from '../model/FollowOperation';
import { MessageSettingField, validMessageSetting } from '../model/MessageSettings';
import { TailAction, TailChange, tailChangeError } from '../model/Tails';
import { PrivacyMarkField, validPrivacyMark } from '../model/PrivacyMarks';
import { AtCandidateKind, validAtKind } from '../model/AtCandidates';
import { VideoFeedEnvironment } from '../model/VideoFeed';
/**
 * 贴吧请求的公共参数与客户端身份。
 *
 * 参数构成依据公开协议资料：
 * - 客户端版本、域名常量来自 aiotieba 的 const 定义
 * - 设备指纹字段的格式来自 aiotieba 的 Account 契约说明
 *
 * 重要：本文件只负责"装参数的容器"，不负责生成设备指纹。
 * c3_aid / cuid_galaxy2 / enuid 这类字段依赖与官方实现一致的算法，
 * 未验证前不要伪造随机值 —— 服务端会校验失败。相关生成逻辑见 utils/DeviceUtil（待实现）。
 */

import { CryptoUtil, SignParam, SignSalt } from '../utils/CryptoUtil';
import { ProtoWriter } from '../proto/ProtoWire';
import { encodeUtf8 } from '../utils/TextCodec';
import { TransferStats, TransferStatsSnapshot } from './TransferStats';

/** 客户端版本常量。不同端点要求不同版本，用错版本服务端会返回格式错误。 */
export class TiebaVersion {
  /** 大部分 API 使用此版本 */
  static readonly LATEST: string = '22.6.5.1';
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

/** B-04当前原生创建/验证码；创建参数仅准备，无写API/UI调用。 */
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

/** E-01 NetWork.uploadImage：普通头像pic全图，独立于帖子分片。 */
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

/** D-02 普通帖图分片，当前 c27/NetWork/f8 契约；不复用头像上传。 */
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
  /** 当前 APK f8：UTF-8文本，chunk文件名file，不给文件片单独加Content-Type。 */
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

/** 当前 APK pwb/cxb.makeHttpParam；普通首屏/续页，无已读位置 ids 和筛选。 */
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

/** 当前 APK s66→in6 资源类型23；普通下载无签名、凭据或 play_from 参数。 */
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

/** 当前 SettingStatic/OfficialAccountPushRequestMessage：cmd309620，只有 common。 */
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

/**
 * 设备与身份参数。
 *
 * 这些字段决定服务端把请求当成"哪个设备上的哪个客户端"，
 * 缺失或格式不符会导致鉴权失败或返回降级内容。
 * 各字段的长度与字符集在协议侧有明确约束，构造时不要随意截断或补位。
 */
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
  /** 客户端版本号，默认取 LATEST */
  clientVersion: string = TiebaVersion.LATEST;
  /** _os_version 使用 deviceInfo.sdkApiVersion，空串不发送。 */
  osVersion: string = '';
  /** net_type 当前固定为 1，尚无官方取值证据；空串不发送。 */
  netType: string = '';
  /** model 使用 deviceInfo.model，空串不发送。 */
  model: string = '';

  /** 该设备的身份参数是否已经具备发出请求的最低条件 */
  isUsable(): boolean {
    return this.androidId.length > 0 && this.uuid.length > 0 && this.cuid.length > 0;
  }
}

/** 登录态。凭证只应存在于内存与安全存储中，不得写入日志或源码。 */
export class TiebaSession {
  /**
   * BDUSS。客户端接口的鉴权载体。
   * 这是账号凭证，日志与异常信息中必须脱敏。
   */
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
 * 点赞对象类型（`obj_type`）。
 *
 * 取值来自 aiotieba `api/agree/_api.py` 的三分支：
 * 传了 `post_id` 时按"是不是楼中楼"分 1/2，**没传 `post_id`** 才是"赞主题本身"（3）。
 * 也就是说主帖点赞与首楼点赞不是一回事：前者 `obj_type=3` 且 `post_id=0`。
 */
export enum AgreeObjType {
  /** 主题帖（主帖、底栏点赞）：`obj_type=3`，`post_id` 必须为 0 */
  THREAD = 3,
  /** 普通楼层：`obj_type=1`，`post_id=<pid>` */
  POST = 1,
  /** 楼中楼（楼层内的评论）：`obj_type=2`，`post_id=<pid>` */
  SUB_POST = 2
}

/** 写请求统计参数依据官方 NetWork.addStatisticsDataParam 与 NetWorkState。耗时与响应字节数由 HttpClient 测量；本实现只保留最近一条统计、不自动重试，stTimesNum=0、stMode=1。无可用统计时仅发送 timestamp 与 stErrorNums，失败时回填统计与错误数。 */
export class AntiSpamParams {
  /** 取用本项目自己测到的统计生成一次（生产路径走这个） */
  static generate(nowMs: number): SignParam[] {
    const stats: TransferStatsSnapshot | undefined = TransferStats.take();
    const errorNums: number = TransferStats.takeErrorNums();
    return AntiSpamParams.compose(nowMs, stats, errorNums);
  }

  /** 固定取值版本，**只给用例锁签名用**（实测值随网络变化，无法与独立算出的期望值比对） */
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

  /** 日志用：只取时间戳与传输统计（都不是凭据） */
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

/** opAgree 的字段与签名依据官方 TbConfig、HttpRequest、CommonReq 和 NetWork。签名对未编码原值按 key 排序拼接后加盐取 MD5，最后追加 sign。当前 mini 域、12.52.1.0、ka=open 和客户端标识格式尚无完整官方取值证据，不应视为已确认协议。 */
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

  /**
   * 拼出**已按 key 排序**的待签名参数表（不含 `sign`）。
   *
   * 排序是有意的：本项目签名前先按 key 升序排，所以 body 的字节顺序也是排序序。
   * 调用方拿到后直接 `appendSign` 即可。
   */
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

    // ② 账号（官方公共字段，字段名见类注释）
    params.push(new SignParam('BDUSS', session.bduss));
    /** STOKEN 非空时才加入参数和签名输入，空值不发送。 */
    if (session.stoken.length > 0) {
      params.push(new SignParam('STOKEN', session.stoken));
    }
    params.push(new SignParam('tbs', session.tbs));

    // ③ 设备身份（官方公共字段，取值形态见类注释）
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

  /**
   * 本项目当前请求头组（**尚无官方取证，待定**）。
   *
   * UA 由 `_client_version` 拼出（`bdtb for Android ` + 版本）；
   * `client_user_token` 是账号 uid。
   */
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

    // 客户端标识
    params.push(new SignParam('_client_type', '2'));
    params.push(new SignParam('_client_version', device.clientVersion));
    params.push(new SignParam('_phone_imei', device.androidId));
    params.push(new SignParam('from', '1020011'));
    params.push(new SignParam('model', 'HarmonyOS'));

    /** 设备身份字段包括 cuid、cuid_galaxy2、_client_id、_os_version 与 net_type；与请求头及客户端版本保持一致。 */
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
    /** 仅在非空时发送 STOKEN，其余参数保持公共参数表定义。 */
    if (session.stoken.length > 0) {
      params.push(new SignParam('STOKEN', session.stoken));
    }
    if (session.tbs.length > 0) {
      params.push(new SignParam('tbs', session.tbs));
    }

    return params;
  }

  /** 把参数列表序列化为 application/x-www-form-urlencoded 请求体 */
  static encodeForm(params: SignParam[]): string {
    const parts: string[] = [];
    for (let i = 0; i < params.length; i++) {
      parts.push(`${encodeURIComponent(params[i].key)}=${encodeURIComponent(params[i].value)}`);
    }
    return parts.join('&');
  }
}

/** 用户资料使用 multipart protobuf，请求头 x_bd_data_type: protobuf，part 名 data、filename=file。封装形态参考 aiotieba core/http.py pack_proto_request（Unlicense）。 */
export class SelfProfileParams {
  static readonly PATH: string = '/c/u/user/profile';
  /** aiotieba `api/profile/_const.py` 的 `CMD` */
  static readonly CMD: string = '303012';
  /** multipart 分隔符（沿用 aiotieba 的固定值） */
  static readonly BOUNDARY: string = '-*_r1999';
  static readonly PROTO_HEADER: string = 'x_bd_data_type';
  static readonly PROTO_HEADER_VALUE: string = 'protobuf';

  /** 构造 ProfileReqIdl。早期字段参考公开 proto，请求形态参考 aiotieba（Unlicense）；字段号另经官方 ProfileReqIdl、DataReq 与 CommonReq 核对。查询本人使用 friend_uid_portrait，open_uid 不等于贴吧 User.id。 */
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
    // 不发送 passport uid（字段 1）；使用头像标识或真实贴吧 friend_uid 定位。
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

  /** 把 protobuf 字节包成 multipart body（分界符同上） */
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

  /**
   * 请求头。**必须含 `x_bd_data_type: protobuf`**，否则服务端回 110001。
   * Cookie 带 BDUSS/STOKEN —— pb 通道**不签名**，身份靠 Cookie。
   */
  static headers(session: TiebaSession): Record<string, string> {
    const h: Record<string, string> = {};
    h['Content-Type'] = `multipart/form-data; boundary=${SelfProfileParams.BOUNDARY}`;
    h[SelfProfileParams.PROTO_HEADER] = SelfProfileParams.PROTO_HEADER_VALUE;
    h['Cookie'] = `BDUSS=${session.bduss}; STOKEN=${session.stoken}`;
    return h;
  }
}

/** 用户内容请求参考 aiotieba get_user_contents（Unlicense），字段号另经官方 UserPostReqIdl、DataReq 与 CommonReq 核对。is_thread=1 为主题、0 为回复；无签名，BDUSS 放入 common。 */
export class UserPostParams {
  static readonly PATH: string = '/c/u/feed/userpost';
  /** aiotieba `get_user_contents/_const.py` 的 `CMD` */
  static readonly CMD: string = '303002';

  /**
   * 构造 `UserPostReqIdl` 请求体。
   *
   * @param uid       目标用户 uid（真实贴吧 uid，**不是** `json_userinfo.open_uid`）
   * @param isThread  1 = 我发布的主题帖，0 = 我发布的回复
   */
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

  /** multipart 包装：与 profile 通道同一套分隔符与字段名，直接复用 */
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

/** 个性化推荐使用 multipart protobuf，无签名，以 Cookie 鉴权。端点与 cmd 依据官方 TbConfig 与 RecPersonalizePageModel；请求形态曾参考 aiotieba pack_proto_request。字段号已核对官方 PersonalizedReqIdl、DataReq 与 CommonReq；load_type=1 刷新、2 续页，时间戳使用毫秒。 */
export class PersonalizedParams {
  static readonly PATH: string = '/c/f/excellent/personalized';
  /** 推荐流的接口 cmd。 */
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

  /** multipart 包装：与 profile / userpost 通道同一套分隔符与字段名，直接复用 */
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

/** 收藏载荷依据官方 MarkModel 与 fv7。data 为 JSON 数组字符串，原值参与签名、发送时才编码；取消收藏发送 user_id、tid、fid。当前 tid/pid 使用字符串、status 使用数字、取消 fid 使用字面量 null；这些具体取值尚未完整核实官方语义。 */
export class StoreParams {
  static readonly ADD_PATH: string = '/c/c/post/addstore';
  static readonly RM_PATH: string = '/c/c/post/rmstore';
  /** 待定：本项目 `fid` 当前占位值为字面字符串 `"null"`，尚无官方取值证据；保留现值 */
  static readonly FID_PLACEHOLDER: string = 'null';

  /** addstore 的 `data` 字段值。tid/pid 转字符串、status 保持数字 1 */
  static addData(tid: number, pid: number): string {
    return `[{"tid":"${tid}","pid":"${pid}","status":1}]`;
  }

  /** addstore 的完整待签字段表（公共参数 + data） */
  static buildAdd(device: TiebaDevice, session: TiebaSession, tid: number,
    pid: number): SignParam[] {
    const params: SignParam[] = TiebaCommonParams.build(device, session);
    params.push(new SignParam('data', StoreParams.addData(tid, pid)));
    return params;
  }

  /** rmstore 的完整待签字段表（公共参数 + tid/fid/user_id） */
  static buildRemove(device: TiebaDevice, session: TiebaSession, tid: number,
    uid: number): SignParam[] {
    const params: SignParam[] = TiebaCommonParams.build(device, session);
    params.push(new SignParam('tid', String(tid)));
    params.push(new SignParam('fid', StoreParams.FID_PLACEHOLDER));
    params.push(new SignParam('user_id', String(uid)));
    return params;
  }
}

/** 收藏表情接口使用公共参数与签名。getAllMeme 无业务参数；collect 的 pics 为 pic_id 对象数组的 JSON 字符串，按全量替换处理，清空使用 all_delete。 */
export class MemeEmojiParams {
  static readonly ALL_PATH: string = '/c/e/meme/getAllMeme';
  static readonly COLLECT_PATH: string = '/c/e/meme/collect';
  /** 清空收藏时 `pics` 字段的字面量（照抄官方 UserCollectModel） */
  static readonly ALL_DELETE: string = 'all_delete';

  /** getAllMeme 的完整待签字段表 = 纯公共参数 */
  static buildAll(device: TiebaDevice, session: TiebaSession): SignParam[] {
    return TiebaCommonParams.build(device, session);
  }

  /** collect 的完整待签字段表（公共参数 + pics + pic_update_time） */
  static buildCollect(device: TiebaDevice, session: TiebaSession, pics: string,
    picUpdateTimeMs: number): SignParam[] {
    const params: SignParam[] = TiebaCommonParams.build(device, session);
    params.push(new SignParam('pics', pics));
    params.push(new SignParam('pic_update_time', String(picUpdateTimeMs)));
    return params;
  }
}

/** 回复使用 multipart protobuf，无签名，需要 Cookie、BDUSS 与 tbs。端点与 cmd 依据官方 AddPostRequest，字段号依据 AddPostDataReq。当前字段 44、45、46、49 的取值语义尚未逐项确认；修改映射须以发布后读回验证，不能只依赖成功回执。 */
export class AddPostParams {
  static readonly PATH: string = '/c/c/post/add';
  /** cmd：官方 `AddPostRequest` 的 309731（类注释有取证行号） */
  static readonly CMD: string = '309731';

  /** `post_from`：一级评论（对主帖发言）的取值 */
  static readonly POST_FROM_THREAD: string = '13';
  /** `post_from`：回复某个楼层（非楼中楼）的取值 */
  static readonly POST_FROM_POST: string = '0';
  /** `data(16)`：本项目当前固定填 `"12"`；官方取值与具体语义尚未举证，待定 */
  static readonly CLIENT_TYPE_TAG: string = '12';

  /**
   * 构造 `AddPostReqIdl` 请求体。
   *
   * @param content   正文（纯文本）
   * @param fid       吧 id（字符串形式，`fid` 的详情来自 `ThreadDetail.forumId`）
   * @param forumName 吧名
   * @param tid       帖子 id
   * @param target    可选：回复目标。都不给 = 对主帖发表一级评论
   */
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
    // 当前22.11.1 AddPost.DataReq.with_tail=76 uint32；独立于正文内容。
    // 未指定保留既有请求，明确选择时才发送0/1，不从管理页is_selected推断。
    if (withTail !== undefined) { data.writeInt32(76, withTail ? 1 : 0); }

    const root: ProtoWriter = new ProtoWriter();
    root.writeMessage(1, data.toUint8Array());      // data
    return root.toUint8Array();
  }

  /** multipart 包装：与 profile / userpost / personalized 同一套分隔符与字段名 */
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

/**
 * `AddPostParams.buildRequest` 的**可选回复目标**（独立取值，不塞进必填参数里）。
 *
 * `postId` 为空 = 对主帖发表一级评论；给了 = 回复该楼层；`subPostId` 再给 = 回复楼中楼。
 */
export class AddPostTarget {
  postId: string = '';
  subPostId: string = '';
  replyUid: string = '';
}

/** PC 吧头图接口返回 activityhead.head_imgs[].img_url。签名前先对 kw 做一次 URL 编码，再对完整表单编码；使用 SignSalt.PC。 */
export class FrsHeadlineParams {
  static readonly PATH: string = '/c/f/frs/frsBottom_pc';

  /**
   * 构造签名后的 form body。
   *
   * 签名细节：`kw` 参数值 = `encodeURIComponent(吧名)`（单编码形态）参与 MD5；
   * `TiebaCommonParams.encodeForm` 发送时整体再编码一次 → 服务端收到双编码值，
   * decode 两次得到吧名 —— 与浏览器 HAR 逐字节一致。`tbs` 传空（实测可通）。
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

/** GetMemberInfo API cmd 为 301004；请求 data{forum_id=1, common=2}，响应 data=1、error=2，与常用 error=1 的信封不同。依据官方 ForumMemberRequestMessage 与 GetMemberInfo proto。 */
export class ForumMemberParams {
  static readonly PATH: string = '/c/f/forum/getMemberInfo';
  static readonly CMD: string = '301004';

  static url(): string {
    return `https://${TiebaHost.APP}${ForumMemberParams.PATH}?cmd=${ForumMemberParams.CMD}`;
  }

  /** `root{ data{ forum_id, common } }`，再走与其它 pb 端点相同的 multipart 封装 */
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
 * 官方 `GetBawuInfo`（A-01 补：吧务全量名单）：消息 id 1001705，**API cmd = 301007**。
 * 同样来自反编译：`com/baidu/tieba/forumMember/bawu/BawuTeamRequestMessage` 的 `super(1001705, 301007)`。
 *
 * ⚠️ 字段顺序与 `GetMemberInfo` **相反**：`GetBawuInfo/DataReq{ common=1, forum_id=2 }`
 * （成员端点是 `forum_id=1, common=2`）。响应 `GetBawuInfoResIdl{ data=1, error=2 }`，
 * `DataRes.bawu_team_info=1` 才是 `BawuTeam{ total_num=1, bawu_team_list=2 }`（**多一层**，
 * 真机首轮就把这层数错了，探针里已留注释）。
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

  /** `root{ data{ pn=1, common=2 } }`；官方还发屏幕尺寸等，此处只发被服务端需要的最小集（探针已验证可用） */
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

/** 屏蔽贴吧使用官方 submitDislike 负反馈接口，dislike 为 JSON 数组，原因 ID 为 7。成功与否仍需读取屏蔽列表核对；请求已接收不等于已落库。 */
export class SubmitDislikeParams {
  static readonly PATH: string = '/c/c/excellent/submitDislike';
  /** 负反馈来源：首页推荐流（官方 `FrsFragment.java:6453` 传的就是 "frs"） */
  static readonly FROM_FRS: string = 'frs';

  static readonly DISLIKE_ID_BLOCK_FORUM: string = '7';

  static url(): string { return `https://${TiebaHost.APP}${SubmitDislikeParams.PATH}`; }

  /**
   * 构造 `dislike` 数组（单元素）。字段顺序与官方一致，便于抓包对照。
   *
   * `fid` / `tid` 传 0 时**不写该字段**（官方是"有值才写"，不写空串）。
   */
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

  /** 待签名参数：common 一组 + `dislike` / `dislike_from` */
  static build(device: TiebaDevice, session: TiebaSession, body: string, from: string): SignParam[] {
    const params: SignParam[] = TiebaCommonParams.build(device, session);
    params.push(new SignParam('dislike', body));
    params.push(new SignParam('dislike_from', from));
    return params;
  }
}

/** 取消屏蔽使用 submitCancelDislike，参数为 forum_id，需有效 tbs。依据官方 ml8.java 的 HttpMessage(1003487)。 */
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
 * 官方「赞我」（F-01）：消息 id 1002211，**API cmd = 309593**。
 *
 * 证据：`ij7.java` 静态注册 `ur8.c(309593, 1002211, "c/u/feed/agreeme", …)`；
 * 请求 `AgreeMeRequestMessage.id` = **上一批最后一条的 `AgreeList.id`**（游标分页，
 * `ij7.i()` 里 `this.c = 最后一条.k()`，首屏游标为 0）；`rn` 是每页条数。
 * 字段号来自官方 proto：`AgreeMeReqIdl{ data=1 }`、`DataReq{ common=1, id=2(uint64), rn=3 }`、
 * `AgreeMeResIdl{ error=1, data=2 }`、`DataRes{ has_more=1, agree_list=2 }`。
 * 真机实测（`NotifyProbe`）：游标 0 拿到 13 条、has_more=0、末条 id=65474625（游标有效）。
 */
export class AgreeMeParams {
  static readonly PATH: string = '/c/u/feed/agreeme';
  static readonly CMD: string = '309593';

  static url(): string {
    return `https://${TiebaHost.APP}${AgreeMeParams.PATH}?cmd=${AgreeMeParams.CMD}`;
  }

  /** `root{ data{ common=1, id=2, rn=3 } }`；`cursor` 首屏传 0 */
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
