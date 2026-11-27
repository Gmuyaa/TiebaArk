/**
 * 私信 IM 通道的请求参数与消息号；字段号与命令号的取证见 `docs/协议/协议证据-私信.md`。
 *
 * 只负责把参数写成字节，不建连接、不解析响应；连接与加解密在 `net/ImSocket.ets`。
 */

import { ProtoWriter } from '../proto/ProtoWire';

/** IM 通道命令号（帧头里的 cmd，与 HTTP 的 cmd 不是一套）。 */
export class ImCmd {
  /** UpdateClientInfo：登录/上报会话密钥（握手）。 */
  static readonly UPDATE_CLIENT_INFO: number = 1001;
  /** UpdateMaskInfo：增删黑名单等屏蔽关系。 */
  static readonly UPDATE_MASK_INFO: number = 104102;
  /** GetMaskInfo：读取黑名单等屏蔽列表。 */
  static readonly GET_MASK_INFO: number = 104103;
  /** GetGroupMsg：会话增量同步。 */
  static readonly GET_GROUP_MSG: number = 202003;
  /** CommitPersonalMsg：发送私信。 */
  static readonly COMMIT_PERSONAL_MSG: number = 205001;
  /** CommitReceivedPmsg：上报已读。 */
  static readonly COMMIT_RECEIVED_PMSG: number = 205006;
  /** PushNotify：新消息推送（服务端→客户端，JSON 体）。 */
  static readonly PUSH_NOTIFY: number = 202006;
  /** 服务端推送消息（订阅用）。 */
  static readonly PUSH_MSG: number = 202009;
}

/** 私信通道使用的客户端版本：官方 `TiebaIMConfig` 未给出该值，此处取 aiotieba 的 CHAT_VERSION（服务端接受过的已知值），被拒时只改这一处。 */
export const IM_CLIENT_VERSION: string = '22.13.1.0';
/** 用户黑名单对应的 maskType（APK `BlackListModel.MASK_TYPE = 10`）。 */
export const IM_MASK_TYPE_BLACKLIST: number = 10;

/** 会话游标：每条会话已读到的最后一条 msgId。 */
export class ImGroupCursor {
  groupIdText: string = '';
  groupId: bigint = BigInt(0);
  lastMsgIdText: string = '0';
  lastMsgId: bigint = BigInt(0);
}

/** 一个 IM 请求的组装结果：命令号 + 明文 body（是否加密由连接层决定）。 */
export class ImRequest {
  cmd: number = 0;
  body: Uint8Array = new Uint8Array(0);
}

/** 仅含 `_client_type` / `_client_version` 的设备串（与公开实现的最小模式一致）。 */
function minimalDeviceJson(clientVersion: string): string {
  return `{"_client_type":"2","_client_version":"${clientVersion}"}`;
}

/**
 * 完整设备串（公开实现的 full 模式）。
 *
 * 最小模式只报两个字段、`cuid` 是占位串，服务端风控会把它当可疑客户端；这里只填本机真实标识，
 * 型号等拿不到的一律留空，不伪造。参数是散字符串而不是 `TiebaDevice`：本文件要同步到 Node 测试镜像。
 */
export function fullDeviceJson(cuid: string, androidId: string, clientId: string,
  osVersion: string, netType: string, model: string, clientVersion: string): string {
  const now: number = Date.now();
  const date: Date = new Date(now);
  const month: string = date.getMonth() + 1 < 10 ? `0${date.getMonth() + 1}` : `${date.getMonth() + 1}`;
  const day: string = date.getDate() < 10 ? `0${date.getDate()}` : `${date.getDate()}`;
  const eventDay: string = `${date.getFullYear()}${month}${day}`;
  return '{'
    + `"model":"${model}",`
    + '"brand":"",'
    + '"_phone_imei":"",'
    + `"_os_version":"${osVersion}",`
    + `"android_id":"${androidId}",`
    + '"mac":"",'
    + '"_client_type":"2",'
    + `"_client_version":"${clientVersion}",`
    + `"user_agent":"bdtb for Android ${clientVersion}",`
    + `"_client_id":"${clientId}",`
    + `"net_type":"${netType}",`
    + '"net":"1",'
    + `"cuid":"${cuid}",`
    + `"cuid_galaxy2":"${cuid}",`
    + '"c3_aid":"",'
    + '"cuid_gid":"",'
    + `"timestamp":"${now}",`
    + '"sample_id":"",'
    + '"z_id":"",'
    + '"baiduid":"",'
    + '"sdk_ver":"3.36.0",'
    + '"framework_ver":"",'
    + '"news_game_ver":"",'
    + '"_phone_screen":"1080,2340",'
    + '"_msg_status":"0",'
    + '"_pic_quality":"0",'
    + '"pversion":"1.0.3",'
    + '"q_type":"0",'
    + '"scr_h":"2340",'
    + '"scr_w":"1080",'
    + '"scr_dip":"2.75",'
    + `"active_timestamp":"${now}",`
    + `"first_install_time":"${now - 86400000}",`
    + `"update_time":"${now - 3600000}",`
    + `"event_day":"${eventDay}",`
    + '"cmode":"1",'
    + '"extra":"",'
    + '"personalized_rec_switch":"1",'
    + '"ad_context":"",'
    + '"start_type":"99",'
    + '"start_scheme":""'
    + '}';
}

/**
 * 拼 `UpdateClientInfoReqIdl{cuid=1, data=2}`。
 *
 * 最小模式：`cuid = "-|com.baidu.tieba{版本}"`，data 只带 bduss、device、secretKey；
 * 不带 STOKEN（非必需，少一个凭据上送面）。`deviceJson`/`cuid` 为空即走最小模式。
 */
export class ImUpdateClientParams {
  static build(bduss: string, encryptedSecret: Uint8Array,
    clientVersion: string = IM_CLIENT_VERSION,
    deviceJson: string = '', cuid: string = '', stoken: string = ''): ImRequest {
    const data: ProtoWriter = new ProtoWriter();
    const full: boolean = deviceJson.length > 0 && cuid.length > 0;
    const effectiveJson: string = full ? deviceJson : minimalDeviceJson(clientVersion);
    const effectiveCuid: string = full ? cuid : `-|com.baidu.tieba${clientVersion}`;
    if (bduss.length > 0) {
      data.writeString(1, bduss);                       // bduss
    }
    data.writeString(2, effectiveJson);                 // device（JSON 串）
    data.writeBytes(3, encryptedSecret);                // secretKey（RSA 加密的会话密钥）
    if (full && stoken.length > 0) {
      data.writeString(12, stoken);                     // stoken（仅 full 模式；tag 12）
    }
    const root: ProtoWriter = new ProtoWriter();
    root.writeString(1, effectiveCuid);                 // cuid
    root.writeMessage(2, data.toUint8Array());          // data
    const req: ImRequest = new ImRequest();
    req.cmd = ImCmd.UPDATE_CLIENT_INFO;
    req.body = root.toUint8Array();
    return req;
  }
}

/** 拼 `GetGroupMsgReqIdl{data=2}`（202003）。 */
export class ImGroupSyncParams {
  /** `getType` 取值 1 = 私信会话增量（与公开实现一致）。 */
  static readonly GET_TYPE_PRIVATE: number = 1;

  static build(cursors: ImGroupCursor[], getType: number = ImGroupSyncParams.GET_TYPE_PRIVATE): ImRequest {
    const data: ProtoWriter = new ProtoWriter();
    // 图片尺寸协商（官方 GetGroupMsg.DataReq tag 1-4）；缺少时服务端可能不下发私信图片 URL。
    data.writeInt32(1, 1080);
    data.writeInt32(2, 1920);
    data.writeInt32(3, 360);
    data.writeInt32(4, 360);
    for (let i = 0; i < cursors.length; i++) {
      const item: ProtoWriter = new ProtoWriter();
      item.writeInt64(1, cursors[i].groupId);   // groupId
      item.writeInt64(2, cursors[i].lastMsgId); // lastMsgId
      // 字段 6 = groupMids（repeated GroupLastId）
      data.writeMessage(6, item.toUint8Array());
    }
    data.writeString(7, String(getType));        // gettype
    const root: ProtoWriter = new ProtoWriter();
    root.writeMessage(2, data.toUint8Array());
    const req: ImRequest = new ImRequest();
    req.cmd = ImCmd.GET_GROUP_MSG;
    req.body = root.toUint8Array();
    return req;
  }
}

/** 拼 `CommitPersonalMsgReqIdl{data=1}`（205001）。 */
export class ImSendParams {
  static readonly MSG_TYPE_TEXT: number = 1;
  static readonly MSG_TYPE_IMAGE: number = 2;

  /**
   * @param groupId 已有会话的真实 groupId；0 表示首次开聊（服务端按 toUid 找/建组）。
   */
  static build(toUid: bigint, content: string, recordId: bigint,
    msgType: number = ImSendParams.MSG_TYPE_TEXT, groupId: bigint = BigInt(0)): ImRequest {
    const data: ProtoWriter = new ProtoWriter();
    if (groupId > BigInt(0)) {
      data.writeInt64(1, groupId);    // groupId（定位会话用；私信组实测必须与 toUid 自洽）
    }
    data.writeInt64(2, toUid);        // toUid
    data.writeString(4, content);     // content
    data.writeInt32(3, msgType);      // msgType
    data.writeInt64(6, recordId);     // recordId（本地消息号，回执原样带回）
    const root: ProtoWriter = new ProtoWriter();
    root.writeMessage(1, data.toUint8Array());
    const req: ImRequest = new ImRequest();
    req.cmd = ImCmd.COMMIT_PERSONAL_MSG;
    req.body = root.toUint8Array();
    return req;
  }
}

/** 拼 `CommitReceivedPmsgReqIdl{data=1}`（205006）：把一条私信标为已读。 */
export class ImReadParams {
  static build(groupId: bigint, toUid: bigint, msgId: bigint, msgType: number,
    toUserType: number): ImRequest {
    const data: ProtoWriter = new ProtoWriter();
    data.writeInt64(1, groupId);         // groupId
    data.writeInt64(2, toUid);           // toUid
    data.writeInt32(3, msgType);         // msgType
    data.writeInt64(4, msgId);           // msgId
    data.writeInt32(5, toUserType);      // toUserType
    const root: ProtoWriter = new ProtoWriter();
    root.writeMessage(1, data.toUint8Array());
    const req: ImRequest = new ImRequest();
    req.cmd = ImCmd.COMMIT_RECEIVED_PMSG;
    req.body = root.toUint8Array();
    return req;
  }
}

/** `GetMaskInfoReqIdl{data(1): {type(1)}}`（104103）。 */
export class ImGetMaskInfoParams {
  static build(maskType: number = IM_MASK_TYPE_BLACKLIST): ImRequest {
    const data: ProtoWriter = new ProtoWriter();
    data.writeInt32(1, maskType);
    const root: ProtoWriter = new ProtoWriter();
    root.writeMessage(1, data.toUint8Array());
    const req: ImRequest = new ImRequest();
    req.cmd = ImCmd.GET_MASK_INFO;
    req.body = root.toUint8Array();
    return req;
  }
}

/** `UpdateMaskInfoReqIdl{data(1): {type(1), isMask(2), list(3), g_id(4), call_from(5)}}`（104102）。 */
export class ImUpdateMaskInfoParams {
  static readonly CALL_FROM_DEFAULT: number = 1;

  static build(uid: bigint, masked: boolean, maskType: number = IM_MASK_TYPE_BLACKLIST,
    callFrom: number = ImUpdateMaskInfoParams.CALL_FROM_DEFAULT): ImRequest {
    const data: ProtoWriter = new ProtoWriter();
    data.writeInt32(1, maskType);
    data.writeInt32(2, masked ? 1 : 0);
    data.writeString(3, uid.toString());
    data.writeInt64(4, BigInt(0));
    data.writeInt32(5, callFrom);
    const root: ProtoWriter = new ProtoWriter();
    root.writeMessage(1, data.toUint8Array());
    const req: ImRequest = new ImRequest();
    req.cmd = ImCmd.UPDATE_MASK_INFO;
    req.body = root.toUint8Array();
    return req;
  }
}
