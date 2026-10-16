import { hilog } from '@kit.PerformanceAnalysisKit';
import { AddPostResult } from '../model/AddPostResult';
import { AtCandidateKind, AtCandidates, parseAtCandidates, validAtKind } from '../model/AtCandidates';
import { parseAtMentions } from '../model/AtMentions';
import { parseAuthorBlock } from '../model/AuthorBlock';
import {
  AvatarUploadInput, avatarUploadEnvelopeShape, avatarUploadInputError, parseAvatarUpload
} from '../model/AvatarUpload';
import { parseCreateForumChallenge } from '../model/CreateForum';
import { FollowForumList } from '../model/FollowForum';
import { FollowKind, parseFollowWrite } from '../model/FollowOperation';
import { ForbiddenForums, forbiddenForumsContain, parseForbiddenForums } from '../model/ForbiddenForums';
import { ForumHeadlineResult, parseForumHeadlineJson } from '../model/ForumHeadline';
import { BawuTeamResult, ForumMemberResult, parseBawuTeam, parseForumMembers } from '../model/ForumMember';
import { ForumSearchPage } from '../model/ForumSearch';
import { RawHotTopicResponse, parseHotTopics } from '../model/HotTopic';
import { ImageUploadChunk, imageUploadChunkError, parseImageUpload } from '../model/ImageUpload';
import { parseImageWatermark } from '../model/ImageWatermark';
import { MemeEmojiData } from '../model/MemeEmoji';
import { MessageSettingField, parseMessageSettings, validMessageSetting } from '../model/MessageSettings';
import {
  RawStoredThreadResponse, StoredThreadList, UserPostItem, expandUserReplies, parseUserPostErrorno,
  parseUserPostProto
} from '../model/MyContent';
import { NotifyKind, NotifyResult, parseNotifyAgree, parseNotifyReply } from '../model/Notify';
import { OfficialMessageSettings, parseOfficialMessages } from '../model/OfficialMessages';
import { DirectoryData, DirectoryKind, parseDirectory } from '../model/PageDirectory';
import { parsePersonalizedErrorno, parsePersonalizedFeed } from '../model/PersonalizedFeed';
import {
  PrivacyMarkField, PrivacyMarks, parsePrivacyMarks, privacyWriteConfirmed, validPrivacyMark
} from '../model/PrivacyMarks';
import { SearchPostPage, searchScopeForum, searchAuthorAvatar } from '../model/SearchPost';
import { parseSignStats } from '../model/SignStats';
import { TailChange, TailList, parseTailWrite, parseTails, tailChangeError } from '../model/Tails';
import { ReplySortType, SubPostPage, ThreadDetail } from '../model/ThreadDetail';
import { ForumBrief, ForumTab, ThreadListResult } from '../model/ThreadList';
import { UserProfileInfo, parseProtoErrorno, parseSelfProfileProto, parseUserInfo } from '../model/UserProfile';
import { parseUserSearch, UserSearchParseResult } from '../model/UserSearch';
import { VideoFeedEnvironment, VideoFeedResult, parseVideoFeed } from '../model/VideoFeed';
import { voicePayloadError } from '../model/VoiceClip';
import { AgreeTrace } from '../net/AgreeTrace';
import { HttpClient, HttpResult } from '../net/HttpClient';
import {
  AddPostParams, AddPostTarget, AgreeMeParams, AgreeObjType, AgreeParams, AntiSpamParams, AtCandidatesParams,
  AtMentionsParams, AuthorBlockParams, AvatarUploadParams, BawuTeamParams, CancelForbiddenForumParams,
  CreateForumParams, FollowParams, ForbiddenForumsParams, ForumMemberParams, FrsHeadlineParams,
  ImageUploadParams, ImageWatermarkParams, MemeEmojiParams, MessageSettingsParams, OfficialMessagesParams,
  PersonalizedParams, PrivacyMarksParams, ReplyMeParams, SelfProfileParams, StoreParams, SubmitDislikeParams,
  TailsParams, TiebaCommonParams, TiebaDevice, TiebaHost, TiebaSession, TiebaVersion, UserPostParams,
  VideoFeedParams, VoiceAudioParams
} from '../net/TiebaParams';
import { PC_SEARCH_REFERER, WebPcSign } from '../net/WebPcSign';
import { avatarTracePhase, avatarUptimeMs } from '../utils/AvatarTrace';
import { CryptoUtil, SignParam, SignSalt } from '../utils/CryptoUtil';
import { decodeUtf8 } from '../utils/TextCodec';
import { RawForumGuideResponse } from './RawForumGuide';
import { RawForumSearchResponse } from './RawForumSearch';
import { RawFrsPage, RawGeneralTabList } from './RawFrsPage';
import { RawSearchPostResponse } from './RawSearchPost';
import { RawSubPostPageResponse, RawThreadPage } from './RawThreadPage';
import { ApiResult } from './ApiResult';
import {
  ThreadListResponse, ThreadDetailResponse, SubPostResponse, StoredThreadsResponse, UserPostsResponse,
  PersonalizedFeedResponse, SearchPostResponse, ForumSearchResponse, HotTopicsResponse, FollowForumsResponse,
  SignForumResponse, TbsResponse, AgreeResponse, StoreOpResponse, MemeEmojiResponse, MemeCollectResponse,
  ReplyResponse, DirectoryResponse, PublicProfileResponse, AuthorBlockResponse, ForumMemberResponse,
  BawuTeamResponse, NotifyResponse, MessageSettingsResponse, PrivacyMarksResponse, AtCandidatesResponse,
  VoiceAudioResponse, ImageUploadChunkResponse, ImageWatermarkResponse, OfficialMessagesResponse,
  VideoFeedResponse, ForbiddenForumsResponse, ForumBlockResponse, TailsResponse, TailWriteResponse,
  AvatarUploadResponse, CreateForumChallengeResponse, UserSearchResponse
} from './ApiResponses';

// 保留既有导入路径；响应类型集中维护在独立模块。
export {
  ApiResult, ThreadListResponse, ThreadDetailResponse, SubPostResponse, StoredThreadsResponse,
  UserPostsResponse, PersonalizedFeedResponse, SearchPostResponse, ForumSearchResponse, HotTopicsResponse,
  FollowForumsResponse, SignForumResponse, TbsResponse, AgreeResponse, StoreOpResponse, MemeEmojiResponse,
  MemeCollectResponse, ReplyResponse, DirectoryResponse, PublicProfileResponse, AuthorBlockResponse,
  ForumMemberResponse, BawuTeamResponse, NotifyResponse, MessageSettingsResponse, PrivacyMarksResponse,
  AtCandidatesResponse, VoiceAudioResponse, ImageUploadChunkResponse, ImageWatermarkResponse,
  OfficialMessagesResponse, VideoFeedResponse, ForbiddenForumsResponse, ForumBlockResponse, TailsResponse,
  TailWriteResponse, AvatarUploadResponse, CreateForumChallengeResponse, UserSearchResponse
};

/** 贴吧接口编排：参数、签名、传输、业务错误检查与模型解析。HTTP 200 仍可能携带业务错误；frs/page 和 pb/page 使用 JSON 解析。 */

/** 业务成功码 */
const ERROR_OK: number = 0;
/** `error_code` 存在但无法解析成数字时的兜底码；宁可判失败也不猜成成功 */
const ERROR_UNKNOWN: number = -2;
/** 帖子不存在或已删除的业务码。 */
export const ERRNO_THREAD_DELETED: number = 4;
/** client_user_token 使用账号标识，userinfo 请求需同时携带 BDUSS 与 STOKEN。 */
const BROWSER_UA: string = 'Mozilla/5.0 (Linux; Android 14; HarmonyOS) AppleWebKit/537.36';
const USERINFO_URL: string = 'https://tieba.baidu.com/f/user/json_userinfo';

/** 个人资料 JSON 接口使用签名 POST，请求路径为 /c/u/user/profile。 */
/** 社交资料走 protobuf 通道，由 SelfProfileParams 打包、parseSelfProfileProto 解析。 */

/** 业务错误在模型解析前检查。error_code 可能为数字或字符串，统一归一后比较。 */
interface ApiEnvelope {
  error_code?: number | string;
  error_msg?: string;
}

/**
 * 把 `error_code` 归一到数字。
 *
 * 服务端两种形态都出现过（数字 / 字符串），必须都认：
 * 无值视为成功码 0；非数字字符串按"未知非零错误"处理（保守判失败，不猜成成功）。
 */
function normalizeErrorCode(raw: number | string | undefined): number {
  if (raw === undefined) {
    return ERROR_OK;
  }
  if (typeof raw === 'number') {
    return raw;
  }
  const parsed: number = Number.parseInt(raw, 10);
  return Number.isNaN(parsed) ? ERROR_UNKNOWN : parsed;
}

/**
 * 取参数值；不存在返回 `'<missing>'`。仅供诊断日志使用。
 */
function valueOf(params: SignParam[], key: string): string {
  for (let i = 0; i < params.length; i++) {
    if (params[i].key === key) {
      return params[i].value;
    }
  }
  return '<missing>';
}

/** 日志用短摘要：只留前缀与长度（设备指纹不是凭据，但也没必要整条打出来） */
function briefValue(value: string): string {
  if (value.length === 0) {
    return '(empty)';
  }
  return `${value.length > 12 ? value.slice(0, 12) : value}…(len=${value.length})`;
}

/**
 * HTTPS APP `/c/s/login` 的响应信封。
 * 除业务错误外还需读取 `anti.tbs` 与 `user.id`，用于确认凭据有效。
 */
interface TbsEnvelope {
  error_code?: number | string;
  error_msg?: string;
  anti?: LoginAnti;
  user?: LoginUser;
}
interface LoginAnti { tbs?: string; }
interface LoginUser { id?: number | string; }

/** `/c/c/forum/sign` 成功响应里取签到奖励用的最小信封 */
interface SignForumUserInfo {
  sign_bonus_point?: string | number;
}

interface SignForumEnvelope {
  user_info?: SignForumUserInfo;
}

/** passport.baidu.com/v3/api/user/info 响应 */
interface PassportInfoData {
  uid?: number;
  uname?: string;
  displayName?: string;
  /** 完整头像 URL（如 https://himg.bdimg.com/...） */
  portrait?: string;
}

interface PassportInfo {
  errorCode?: number;
  errorMsg?: string;
  data?: PassportInfoData;
}

export class TiebaApi {
  /** B-04验证码资料读取准备；不请求图片，不发送创建，类型未知不推断可完成。 */
  async fetchCreateForumChallenge(device: TiebaDevice, session: TiebaSession): Promise<CreateForumChallengeResponse> {
    const response: CreateForumChallengeResponse = new CreateForumChallengeResponse();
    if (!session.hasBduss()) { response.failLocal('登录后才能读取创建吧验证码'); return response; }
    const check: string = TiebaApi.checkDevice(device);
    if (check.length > 0) { response.failLocal(check); return response; }
    const userAgent: string = `bdtb for Android ${device.clientVersion}`;
    const signed: SignParam[] = await CryptoUtil.appendSign(CreateForumParams.challenge(device, session), SignSalt.APP);
    // 当前NetWorkCoreByBdHttp.postNetData使用xa.c大写签名。
    for (const p of signed) { if (p.key === 'sign') { p.value = p.value.toUpperCase(); } }
    this.client.userAgent = userAgent;
    const transport: HttpResult = await this.client.postForm(`https://${TiebaHost.APP}${CreateForumParams.CHALLENGE_PATH}`,
      TiebaCommonParams.encodeForm(signed));
    if (!transport.ok) { response.transportError = transport.error; return response; }
    if (transport.code !== 200) { response.failLocal('创建吧验证码HTTP结果未确认'); return response; }
    response.data = parseCreateForumChallenge(decodeUtf8(transport.bytes));
    if (response.data.code === -1) { response.failLocal(response.data.message); return response; }
    if (response.data.code !== 0) { response.failBusiness(response.data.code, response.data.message); return response; }
    if (!response.data.available()) { response.failLocal(response.data.message); return response; }
    response.ok = true; return response;
  }

  /** E-01独立头像传输准备；accepted不是资料读回成功，尚无UI调用。 */
  async uploadAvatar(device: TiebaDevice, session: TiebaSession, input: AvatarUploadInput,
    traceId: number = 0): Promise<AvatarUploadResponse> {
    const response: AvatarUploadResponse = new AvatarUploadResponse();
    if (!session.hasBduss()) { response.failLocal('登录后才能修改头像'); return response; }
    const check: string = TiebaApi.checkDevice(device);
    const invalid: string = avatarUploadInputError(input);
    if (check.length > 0 || invalid.length > 0) { response.failLocal(check.length > 0 ? check : invalid); return response; }
    const userAgent: string = `bdtb for Android ${device.clientVersion}`;
    const bytes: Uint8Array = input.bytes.slice();
    const params: SignParam[] = AvatarUploadParams.build(device, session);
    const signed: SignParam[] = await CryptoUtil.appendSign(params, SignSalt.APP);
    for (const p of signed) { if (p.key === 'sign') { p.value = p.value.toUpperCase(); } }
    const body: Uint8Array = AvatarUploadParams.multipart(signed, bytes);
    if (body.length === 0) { response.failLocal('头像内容与请求边界冲突'); return response; }
    this.client.userAgent = userAgent;
    // 只记传输耗时与请求体大小：正文含头像字节，绝不进日志。
    const startedMs: number = avatarUptimeMs();
    const transport: HttpResult = await this.client.postBinary(`https://${TiebaHost.APP}${AvatarUploadParams.PATH}`, body,
      { 'Content-Type': `multipart/form-data; boundary=${AvatarUploadParams.BOUNDARY}` });
    avatarTracePhase('upload-transport', traceId, startedMs,
      `ok=${transport.ok} code=${transport.code} body=${body.length} image=${bytes.length}`);
    if (!transport.ok) { response.transportError = transport.error; return response; }
    if (transport.code !== 200) { response.failLocal('头像上传HTTP结果未确认'); return response; }
    const rawBody: string = decodeUtf8(transport.bytes);
    response.data = parseAvatarUpload(rawBody);
    /*
     * 只记**形态**与业务码：字段名 + 类型 + 长度 + 服务端返回的业务文案（截断）。
     * 不记响应正文、头像 hash、URL 或图片字节 —— 正文可能含头像标识。
     * 目的：把"服务器明确拒绝"与"我们没认出成功字段"分开。
     */
    const message: string = response.data.message.length > 80
      ? response.data.message.substring(0, 80) : response.data.message;
    avatarTracePhase('upload-parse', traceId, startedMs,
      `code=${response.data.code} pending=${response.data.pendingReview()} len=${transport.bytes.length}`
        + ` msg=${message} ${avatarUploadEnvelopeShape(rawBody)}`);
    if (response.data.code === -1) { response.failLocal(response.data.message); return response; }
    /*
     * `code=0` 与 `code=300003`（头像已上传，审核中）都算**服务端已接收**：
     * 调用方据此发布本地预览并读回；其余非零码仍如实按业务失败处理。
     * 审核中不等于资料已更新，界面必须如实标注（见 AvatarEditVM.pendingReview）。
     */
    if (!response.data.received()) { response.failBusiness(response.data.code, response.data.message); return response; }
    response.ok = true; return response;
  }

  /** 单片传输准备；没有上传UI调用，不重试未知写结果，不把中间片当完整图片。 */
  async uploadImageChunk(device: TiebaDevice, session: TiebaSession, chunk: ImageUploadChunk): Promise<ImageUploadChunkResponse> {
    const response: ImageUploadChunkResponse = new ImageUploadChunkResponse();
    if (!session.hasBduss()) { response.failLocal('登录后才能上传图片'); return response; }
    const check: string = TiebaApi.checkDevice(device);
    const invalid: string = imageUploadChunkError(chunk);
    if (check.length > 0 || invalid.length > 0) { response.failLocal(check.length > 0 ? check : invalid); return response; }
    const userAgent: string = `bdtb for Android ${device.clientVersion}`;
    const finalChunk: boolean = chunk.finish();
    const params: SignParam[] = ImageUploadParams.build(device, session, chunk);
    // 在异步签名前拷贝本片；调用方后续改变缓冲区不能修改已经准备的请求。
    const bytes: Uint8Array = chunk.bytes.slice();
    const signed: SignParam[] = await CryptoUtil.appendSign(params, SignSalt.APP);
    // 当前 NetWork→xa.c 使用大写十六进制签名；仅上传通道按已取证格式转换。
    for (const param of signed) { if (param.key === 'sign') { param.value = param.value.toUpperCase(); } }
    const body: Uint8Array = ImageUploadParams.multipart(signed, bytes);
    if (body.length === 0) { response.failLocal('图片分片与请求边界冲突'); return response; }
    this.client.userAgent = userAgent;
    const transport: HttpResult = await this.client.postBinary(`https://${TiebaHost.APP}${ImageUploadParams.PATH}`, body,
      { 'Content-Type': `multipart/form-data; boundary=${ImageUploadParams.BOUNDARY}` });
    if (!transport.ok) { response.transportError = transport.error; return response; }
    response.data = parseImageUpload(decodeUtf8(transport.bytes));
    if (response.data.code === -1) { response.failLocal(response.data.message.length > 0 ? response.data.message : '图片上传响应未确认'); return response; }
    if (response.data.code !== 0) { response.failBusiness(response.data.code, response.data.message); return response; }
    if (finalChunk && !response.data.complete()) { response.failLocal(response.data.message); return response; }
    response.ok = true;
    return response;
  }

  async fetchImageWatermark(device: TiebaDevice, session: TiebaSession): Promise<ImageWatermarkResponse> {
    const response: ImageWatermarkResponse = new ImageWatermarkResponse();
    if (!session.hasBduss()) { response.failLocal('登录后才能读取图片水印设置'); return response; }
    const check: string = TiebaApi.checkDevice(device);
    if (check.length > 0) { response.failLocal(check); return response; }
    this.client.userAgent = `bdtb for Android ${device.clientVersion}`;
    const text: string | undefined = await this.postJsonText(ImageWatermarkParams.READ_PATH,
      ImageWatermarkParams.build(device, session), response);
    if (text === undefined) { return response; }
    response.data = parseImageWatermark(text);
    if (response.data.type < 0) { response.failLocal('图片水印设置响应未确认'); return response; }
    response.ok = true;
    return response;
  }

  async fetchMessageSettings(device: TiebaDevice, session: TiebaSession): Promise<MessageSettingsResponse> {
    const response: MessageSettingsResponse = new MessageSettingsResponse();
    if (!session.hasBduss()) { response.failLocal('登录后才能读取消息设置'); return response; }
    const check: string = TiebaApi.checkDevice(device);
    if (check.length > 0) { response.failLocal(check); return response; }
    this.client.userAgent = `bdtb for Android ${device.clientVersion}`;
    const text: string | undefined = await this.postJsonText(MessageSettingsParams.READ_PATH,
      MessageSettingsParams.build(device, session), response);
    if (text === undefined) { return response; }
    response.data = parseMessageSettings(text);
    if (response.data.maskType < 0 && response.data.pushType < 0) {
      response.failLocal('消息设置响应缺少已确认的字段'); return response;
    }
    response.ok = true;
    return response;
  }

  /** 写链路供后续取证与 VM mock 验证；未经过写接口取证前界面不开放。 */
  async setMessageSetting(device: TiebaDevice, session: TiebaSession,
    field: MessageSettingField, value: number): Promise<ApiResult> {
    const response: ApiResult = new ApiResult();
    if (!session.hasBduss() || !validMessageSetting(field, value)) {
      response.failLocal('未登录或消息设置值无效'); return response;
    }
    const check: string = TiebaApi.checkDevice(device);
    if (check.length > 0) { response.failLocal(check); return response; }
    this.client.userAgent = `bdtb for Android ${device.clientVersion}`;
    const text: string | undefined = await this.postJsonText(MessageSettingsParams.WRITE_PATH,
      MessageSettingsParams.build(device, session, field, value), response);
    if (text === undefined) { return response; }
    try {
      const envelope: ApiEnvelope = JSON.parse(text) as ApiEnvelope;
      response.ok = envelope.error_code === 0 || envelope.error_code === '0';
    } catch (err) { /* 成功必须有明确的 error_code。 */ }
    if (!response.ok) { response.failLocal('消息设置提交结果未确认，请重新读取'); }
    return response;
  }
  /**
   * 吧务团队**全量**名单（官方 `GetBawuInfo`，cmd 301007，A-01 补）。
   *
   * 与 `fetchForumMembers` 的分工：后者给的吧务组**只有预览**（实测 52 人回 5 个），
   * 这个端点给全量并按角色分组。两者都成功时由 `composeMemberGroups()` 用角色组替换预览组。
   */
  async fetchBawuTeam(device: TiebaDevice, session: TiebaSession,
    forumId: number): Promise<BawuTeamResponse> {
    const response: BawuTeamResponse = new BawuTeamResponse();
    if (!Number.isSafeInteger(forumId) || forumId <= 0) {
      response.failLocal('吧身份无效'); return response;
    }
    const check: string = TiebaApi.checkDevice(device);
    if (check.length > 0) { response.failLocal(check); return response; }
    this.client.userAgent = `bdtb for Android ${device.clientVersion}`;
    const transport: HttpResult = await this.client.postBinary(BawuTeamParams.url(),
      BawuTeamParams.build(device, session, forumId), SelfProfileParams.headers(session));
    if (!transport.ok) { response.transportError = transport.error; return response; }
    const parsed: BawuTeamResult = parseBawuTeam(transport.bytes);
    if (parsed.code !== 0) {
      response.failBusiness(parsed.code, parsed.message || '吧务团队请求失败'); return response;
    }
    response.total = parsed.total;
    response.roles = parsed.roles;
    response.ok = true;
    return response;
  }

  /** C-03：公开语音二进制读取，无凭据/签名，编码由平台实际解析后裁决。 */
  async fetchVoiceAudio(device: TiebaDevice, id: string): Promise<VoiceAudioResponse> {
    const response: VoiceAudioResponse = new VoiceAudioResponse();
    const source: string = VoiceAudioParams.url(id);
    if (source.length === 0) { response.failLocal('语音来源无效'); return response; }
    this.client.userAgent = `bdtb for Android ${device.clientVersion}`;
    const transport: HttpResult = await this.client.get(source);
    if (!transport.ok) { response.transportError = '语音下载失败，请重试'; return response; }
    const failure: string = voicePayloadError(transport.bytes);
    if (failure.length > 0) { response.failBusiness(-1, failure); return response; }
    response.bytes = transport.bytes; response.ok = true; return response;
  }

  async fetchOfficialMessages(device: TiebaDevice, session: TiebaSession): Promise<OfficialMessagesResponse> {
    const response: OfficialMessagesResponse = new OfficialMessagesResponse();
    if (!session.hasBduss()) { response.failLocal('登录后才能读取官方消息设置'); return response; }
    const check: string = TiebaApi.checkDevice(device);
    if (check.length > 0) { response.failLocal(check); return response; }
    this.client.userAgent = `bdtb for Android ${device.clientVersion}`;
    const transport: HttpResult = await this.client.postBinary(OfficialMessagesParams.url(),
      OfficialMessagesParams.build(device, session), SelfProfileParams.headers(session));
    if (!transport.ok) { response.transportError = transport.error; return response; }
    const data: OfficialMessageSettings = parseOfficialMessages(transport.bytes);
    if (data.code !== 0) { response.failBusiness(data.code, data.message || '官方消息设置读取失败'); return response; }
    response.data = data; response.ok = true; return response;
  }

  async fetchVideoFeed(device: TiebaDevice, session: TiebaSession, environment: VideoFeedEnvironment,
    loadType: number): Promise<VideoFeedResponse> {
    const response: VideoFeedResponse = new VideoFeedResponse();
    const check: string = TiebaApi.checkDevice(device);
    if (check.length > 0) { response.failLocal(check); return response; }
    if (!VideoFeedParams.valid(environment, loadType)) { response.failLocal('视频请求参数未确认'); return response; }
    this.client.userAgent = `bdtb for Android ${device.clientVersion}`;
    const source: string | undefined = await this.postJsonText(VideoFeedParams.PATH,
      VideoFeedParams.build(device, session, environment, loadType), response);
    if (source === undefined) { return response; }
    const data: VideoFeedResult = parseVideoFeed(source);
    if (data.code !== 0) { response.failBusiness(data.code, data.message); return response; }
    response.data = data; response.ok = true; return response;
  }

  /** D-03：候选人读取；普通选人契约，发送文本与界面仍待证实。 */
  async fetchAtCandidates(device: TiebaDevice, session: TiebaSession, kind: AtCandidateKind,
    word: string = ''): Promise<AtCandidatesResponse> {
    const response: AtCandidatesResponse = new AtCandidatesResponse();
    if (!session.hasBduss() || !validAtKind(kind)) { response.failLocal('未登录或选人类型无效'); return response; }
    const check: string = TiebaApi.checkDevice(device);
    if (check.length > 0) { response.failLocal(check); return response; }
    this.client.userAgent = `bdtb for Android ${device.clientVersion}`;
    const text: string | undefined = await this.postJsonText(AtCandidatesParams.path(kind),
      AtCandidatesParams.build(device, session, kind, word), response);
    if (text === undefined) { return response; }
    const data: AtCandidates = parseAtCandidates(text);
    if (data.code !== 0) { response.failBusiness(data.code, data.message || '选人读取失败'); return response; }
    response.data = data; response.ok = true; return response;
  }

  /** E-04/G-02：账号吧务隐私标记读取；当前 APK 静态契约，服务端待验收。 */
  async fetchPrivacyMarks(device: TiebaDevice, session: TiebaSession, uid: number): Promise<PrivacyMarksResponse> {
    const response: PrivacyMarksResponse = new PrivacyMarksResponse();
    if (!session.hasBduss()) { response.failLocal('登录后才能读取隐私标记'); return response; }
    const check: string = TiebaApi.checkDevice(device);
    if (check.length > 0) { response.failLocal(check); return response; }
    if (!Number.isSafeInteger(uid) || uid <= 0) { response.failLocal('隐私标记账号参数无效'); return response; }
    this.client.userAgent = `bdtb for Android ${device.clientVersion}`;
    const transport = await this.client.postBinary(PrivacyMarksParams.url(), PrivacyMarksParams.build(device, session, uid),
      SelfProfileParams.headers(session));
    if (!transport.ok) { response.transportError = transport.error; return response; }
    const data: PrivacyMarks = parsePrivacyMarks(transport.bytes);
    if (data.code !== 0) { response.failBusiness(data.code, data.message || '隐私标记读取失败'); return response; }
    response.data = data; response.ok = true;
    return response;
  }

  /** E-04/G-02：写契约准备；UI 未开放，动态写/回读取证待执行。 */
  async setPrivacyMark(device: TiebaDevice, session: TiebaSession, field: PrivacyMarkField, value: number): Promise<ApiResult> {
    const response: ApiResult = new ApiResult();
    if (!session.hasBduss() || session.tbs.length === 0 || !validPrivacyMark(field, value)) {
      response.failLocal('登录凭据或隐私标记值无效'); return response;
    }
    const check: string = TiebaApi.checkDevice(device);
    if (check.length > 0) { response.failLocal(check); return response; }
    this.client.userAgent = `bdtb for Android ${device.clientVersion}`;
    const text: string | undefined = await this.postJsonText(PrivacyMarksParams.WRITE_PATH,
      PrivacyMarksParams.buildChange(device, session, field, value), response);
    if (text === undefined) { return response; }
    response.ok = privacyWriteConfirmed(text);
    if (!response.ok) { response.failLocal('隐私标记提交结果未确认，请重新读取'); }
    return response;
  }

  /** E-04：账号屏蔽吧读取；当前 APK 静态契约已核对，服务端待验收。 */
  async fetchForbiddenForums(device: TiebaDevice, session: TiebaSession, uid: number,
    page: number): Promise<ForbiddenForumsResponse> {
    const response: ForbiddenForumsResponse = new ForbiddenForumsResponse();
    if (!session.hasBduss()) { response.failLocal('登录后才能读取屏蔽吧'); return response; }
    const check: string = TiebaApi.checkDevice(device);
    if (check.length > 0) { response.failLocal(check); return response; }
    if (!Number.isSafeInteger(uid) || uid <= 0 || !Number.isInteger(page) || page < 1 || page > 2147483647) {
      response.failLocal('屏蔽吧请求参数无效'); return response;
    }
    this.client.userAgent = `bdtb for Android ${device.clientVersion}`;
    const transport = await this.client.postBinary(ForbiddenForumsParams.url(),
      ForbiddenForumsParams.build(device, session, uid, page), SelfProfileParams.headers(session));
    if (!transport.ok) { response.transportError = transport.error; return response; }
    const data: ForbiddenForums = parseForbiddenForums(transport.bytes);
    if (data.code !== 0) { response.failBusiness(data.code, data.message || '屏蔽吧读取失败'); return response; }
    response.data = data; response.ok = true;
    return response;
  }

  async blockForum(device: TiebaDevice, session: TiebaSession, uid: number, tid: number,
    forumId: number, forumName: string): Promise<ForumBlockResponse> {
    const response: ForumBlockResponse = new ForumBlockResponse();
    if (!session.hasBduss()) { response.failLocal('登录后才能屏蔽贴吧'); return response; }
    if (!Number.isSafeInteger(uid) || uid <= 0) { response.failLocal('账号身份无效，无法屏蔽'); return response; }
    if (!Number.isSafeInteger(tid) || tid <= 0) { response.failLocal('帖子身份无效，无法屏蔽'); return response; }
    if (!Number.isSafeInteger(forumId) || forumId <= 0) {
      response.failLocal('未取得吧 id，无法屏蔽该吧'); return response;
    }
    const check: string = TiebaApi.checkDevice(device);
    if (check.length > 0) { response.failLocal(check); return response; }
    this.client.userAgent = `bdtb for Android ${device.clientVersion}`;
    const body: string = SubmitDislikeParams.buildBody(tid, forumId,
      SubmitDislikeParams.DISLIKE_ID_BLOCK_FORUM, SubmitDislikeParams.FROM_FRS);
    const params: SignParam[] = SubmitDislikeParams.build(device, session, body,
      SubmitDislikeParams.FROM_FRS);
    const text: string | undefined = await this.postJsonText(SubmitDislikeParams.PATH, params, response);
    if (text === undefined) { return response; }

    const readBack: ForbiddenForumsResponse = await this.fetchForbiddenForums(device, session, uid, 1);
    if (!readBack.ok) {
      response.failLocal(`反馈已提交，但读回屏蔽吧列表失败：${readBack.describeFailure()}`);
      return response;
    }
    response.confirmed = forbiddenForumsContain(readBack.data.items, forumId, forumName);
    if (!response.confirmed) {
      response.failLocal('服务端未确认该吧已加入屏蔽列表');
      return response;
    }
    response.ok = true;
    return response;
  }

  /**
   * 「解除屏蔽吧」——官方屏蔽吧列表页的取消动作（`submitCancelDislike`，只发 `forum_id`）。
   * 需要有效 tbs：调用方拿不到就显式刷新一次（与 `AuthorBlockVM.set` 同一处理）。
   */
  async unblockForum(device: TiebaDevice, session: TiebaSession, forumId: string): Promise<ApiResult> {
    const result: ApiResult = new ApiResult();
    if (!session.hasBduss() || session.tbs.length === 0) {
      result.failLocal('需要登录并取得有效验证信息'); return result;
    }
    const check: string = TiebaApi.checkDevice(device);
    if (check.length > 0) { result.failLocal(check); return result; }
    let params: SignParam[];
    try {
      params = CancelForbiddenForumParams.build(device, session, forumId);
    } catch (err) {
      result.failLocal('解除屏蔽吧的参数无效'); return result;
    }
    this.client.userAgent = `bdtb for Android ${device.clientVersion}`;
    const text: string | undefined = await this.postJsonText(CancelForbiddenForumParams.PATH, params, result);
    if (text === undefined) { return result; }
    result.ok = true;
    return result;
  }

  /** D-08：普通小尾巴读取，静态契约已核对；动态服务端待验收。 */
  async fetchTails(device: TiebaDevice, session: TiebaSession): Promise<TailsResponse> {
    const response: TailsResponse = new TailsResponse();
    if (!session.hasBduss()) { response.failLocal('登录后才能读取小尾巴'); return response; }
    const check: string = TiebaApi.checkDevice(device);
    if (check.length > 0) { response.failLocal(check); return response; }
    this.client.userAgent = `bdtb for Android ${device.clientVersion}`;
    const transport = await this.client.postBinary(TailsParams.url(), TailsParams.build(device, session),
      SelfProfileParams.headers(session));
    if (!transport.ok) { response.transportError = transport.error; return response; }
    const data: TailList = parseTails(transport.bytes);
    if (data.code !== 0) { response.failBusiness(data.code, data.message || '小尾巴读取失败'); return response; }
    response.data = data;
    response.ok = true;
    return response;
  }

  async addTail(device: TiebaDevice, session: TiebaSession, content: string, fontColor: string,
    fontKeyName: string): Promise<TailWriteResponse> {
    const change: TailChange = new TailChange();
    change.content = content; change.fontColor = fontColor; change.fontKeyName = fontKeyName;
    return this.submitTailChange(device, session, change);
  }

  async updateTail(device: TiebaDevice, session: TiebaSession, id: number, content: string,
    fontColor: string, fontKeyName: string): Promise<TailWriteResponse> {
    const change: TailChange = new TailChange();
    change.action = 'update'; change.id = id; change.content = content;
    change.fontColor = fontColor; change.fontKeyName = fontKeyName;
    return this.submitTailChange(device, session, change);
  }

  async setTail(device: TiebaDevice, session: TiebaSession, id: number, type: number): Promise<TailWriteResponse> {
    const change: TailChange = new TailChange();
    change.action = 'set'; change.id = id; change.type = type;
    return this.submitTailChange(device, session, change);
  }

  async deleteTail(device: TiebaDevice, session: TiebaSession, id: number): Promise<TailWriteResponse> {
    const change: TailChange = new TailChange();
    change.action = 'delete'; change.id = id;
    return this.submitTailChange(device, session, change);
  }

  /** 写 UI 待取证；返回成功仅表示受理，VM 必须回读核对。 */
  private async submitTailChange(device: TiebaDevice, session: TiebaSession,
    change: TailChange): Promise<TailWriteResponse> {
    const response: TailWriteResponse = new TailWriteResponse();
    const error: string = tailChangeError(change) || TiebaApi.checkDevice(device);
    if (error.length > 0) { response.failLocal(error); return response; }
    if (!session.hasBduss() || session.tbs.length === 0) {
      response.failLocal('登录状态未准备好，无法修改小尾巴'); return response;
    }
    this.client.userAgent = `bdtb for Android ${device.clientVersion}`;
    const transport = await this.client.postBinary(TailsParams.changeUrl(change.action),
      TailsParams.buildChange(device, session, change), SelfProfileParams.headers(session));
    if (!transport.ok) { response.transportError = transport.error; return response; }
    const result = parseTailWrite(transport.bytes);
    if (result.code !== 0) { response.failBusiness(result.code, result.message || '小尾巴提交未确认'); return response; }
    response.id = result.id;
    response.ok = true;
    return response;
  }

  async fetchNotifyFeed(device: TiebaDevice, session: TiebaSession, kind: NotifyKind,
    page: number, agreeCursor: number, uid: number = 0): Promise<NotifyResponse> {
    const response: NotifyResponse = new NotifyResponse();
    const check: string = TiebaApi.checkDevice(device);
    if (check.length > 0) { response.failLocal(check); return response; }
    this.client.userAgent = `bdtb for Android ${device.clientVersion}`;
    if (kind === 'at') {
      const params: SignParam[] = AtMentionsParams.build(device, session, uid, page);
      if (!session.hasBduss() || params.length === 0) { response.failLocal('登录或通知页码无效'); return response; }
      const text: string | undefined = await this.postJsonText(AtMentionsParams.PATH, params, response);
      if (text === undefined) { return response; }
      const parsed: NotifyResult = parseAtMentions(text);
      if (parsed.code !== 0) { response.failBusiness(parsed.code, parsed.message); return response; }
      response.items = parsed.items; response.hasMore = parsed.hasMore; response.page = parsed.page;
      response.ok = true; return response;
    }
    const body: Uint8Array = kind === 'reply'
      ? ReplyMeParams.build(device, session, page)
      : AgreeMeParams.build(device, session, agreeCursor, 20);
    const url: string = kind === 'reply' ? ReplyMeParams.url() : AgreeMeParams.url();
    const transport: HttpResult = await this.client.postBinary(url, body, SelfProfileParams.headers(session));
    if (!transport.ok) { response.transportError = transport.error; return response; }
    const parsed: NotifyResult = kind === 'reply'
      ? parseNotifyReply(transport.bytes) : parseNotifyAgree(transport.bytes);
    if (parsed.code !== 0) {
      response.failBusiness(parsed.code, parsed.message || '通知请求失败'); return response;
    }
    response.items = parsed.items;
    response.hasMore = parsed.hasMore;
    response.nextAgreeId = parsed.nextAgreeId;
    response.agreeHasMore = parsed.agreeHasMore;
    response.ok = true;
    return response;
  }

  async fetchForumMembers(device: TiebaDevice, session: TiebaSession,
    forumId: number): Promise<ForumMemberResponse> {
    const response: ForumMemberResponse = new ForumMemberResponse();
    if (!Number.isSafeInteger(forumId) || forumId <= 0) {
      response.failLocal('吧身份无效'); return response;
    }
    const check: string = TiebaApi.checkDevice(device);
    if (check.length > 0) { response.failLocal(check); return response; }
    this.client.userAgent = `bdtb for Android ${device.clientVersion}`;
    const transport: HttpResult = await this.client.postBinary(ForumMemberParams.url(),
      ForumMemberParams.build(device, session, forumId), SelfProfileParams.headers(session));
    if (!transport.ok) { response.transportError = transport.error; return response; }
    const parsed: ForumMemberResult = parseForumMembers(transport.bytes);
    if (parsed.code !== 0) {
      response.failBusiness(parsed.code, parsed.message || '吧成员请求失败'); return response;
    }
    response.groups = parsed.groups;
    response.ok = true;
    return response;
  }

  /** 官方 protobuf 拉黑接口；不把传输成功或缺错误码当作业务成功。 */  async authorBlock(device: TiebaDevice, session: TiebaSession, uid: number,
    blocked?: boolean): Promise<AuthorBlockResponse> {
    const response: AuthorBlockResponse = new AuthorBlockResponse();
    if (!session.hasBduss() || (blocked !== undefined && session.tbs.length === 0)) {
      response.failLocal('需要登录并取得有效验证信息'); return response;
    }
    if (!Number.isSafeInteger(uid) || uid <= 0) { response.failLocal('作者身份无效'); return response; }
    const check: string = TiebaApi.checkDevice(device);
    if (check.length > 0) { response.failLocal(check); return response; }
    this.client.userAgent = `bdtb for Android ${device.clientVersion}`;
    const transport: HttpResult = await this.client.postBinary(AuthorBlockParams.url(blocked !== undefined),
      AuthorBlockParams.build(device, session, uid, blocked), SelfProfileParams.headers(session));
    if (!transport.ok) { response.transportError = transport.error; return response; }
    response.result = parseAuthorBlock(transport.bytes, blocked === undefined);
    if (response.result.code !== 0) {
      response.failBusiness(response.result.code, response.result.message || '拉黑状态请求失败'); return response;
    }
    response.ok = true;
    return response;
  }

  /** 客户端关注写接口；严格业务成功后更新关系，调用方可后台读回核对。 */
  async setFollow(device: TiebaDevice, session: TiebaSession, kind: FollowKind,
    id: number, portrait: string, following: boolean): Promise<ApiResult> {
    const result: ApiResult = new ApiResult();
    if (!session.hasBduss() || session.tbs.length === 0) {
      result.failLocal('需要登录并取得有效验证信息'); return result;
    }
    if ((kind === 'forum' && (!Number.isSafeInteger(id) || id <= 0))
      || (kind === 'user' && !/^[A-Za-z0-9_.-]+$/.test(portrait))) {
      result.failLocal('关注对象身份无效'); return result;
    }
    const check: string = TiebaApi.checkDevice(device);
    if (check.length > 0) { result.failLocal(check); return result; }
    this.client.userAgent = `bdtb for Android ${device.clientVersion}`;
    const text: string | undefined = await this.postJsonText(FollowParams.path(kind, following),
      FollowParams.build(device, session, kind, id, portrait), result);
    if (text === undefined) { return result; }
    const parsed = parseFollowWrite(text);
    if (parsed.code !== 0) { result.failBusiness(parsed.code, parsed.message || '关注操作失败'); return result; }
    result.ok = true;
    return result;
  }

  /** 公开页面只读接口，复用签名、业务错误判断与当前会话；不要求用户登录。 */
  async fetchDirectory(device: TiebaDevice, session: TiebaSession, kind: DirectoryKind,
    id: number, page: number = 1): Promise<DirectoryResponse> {
    const response: DirectoryResponse = new DirectoryResponse();
    if (!Number.isSafeInteger(id) || id <= 0 || !Number.isInteger(page) || page < 1) {
      response.failLocal('页面参数无效');
      return response;
    }
    const check: string = TiebaApi.checkDevice(device);
    if (check.length > 0) { response.failLocal(check); return response; }
    let path: string = '/c/f/forum/getforumdetail';
    if (kind === 'rules') { path = '/c/f/forum/forumRuleDetail'; }
    else if (kind === 'team') { path = '/c/f/forum/getBawuInfo'; }
    else if (kind === 'fans') { path = '/c/u/fans/page'; }
    else if (kind === 'following') { path = '/c/u/follow/followList'; }
    const params: SignParam[] = TiebaCommonParams.build(device, session);
    params.push(new SignParam(kind === 'fans' || kind === 'following' ? 'uid' : 'forum_id', String(id)));
    params.push(new SignParam('pn', String(page)));
    params.push(new SignParam('rn', '20'));
    const text: string | undefined = await this.postJsonText(path, params, response);
    if (text === undefined) { return response; }
    const data: DirectoryData | undefined = parseDirectory(text, kind);
    if (data === undefined) { response.failLocal('页面数据格式无效'); return response; }
    response.data = data;
    response.ok = true;
    return response;
  }

  async fetchPublicProfile(device: TiebaDevice, session: TiebaSession, uid: number,
    portrait: string, page: number = 1): Promise<PublicProfileResponse> {
    const response: PublicProfileResponse = new PublicProfileResponse();
    if ((!Number.isSafeInteger(uid) || uid <= 0) && portrait.length === 0) {
      response.failLocal('未取得用户身份'); return response;
    }
    const check: string = TiebaApi.checkDevice(device);
    if (check.length > 0) { response.failLocal(check); return response; }
    const body: Uint8Array = SelfProfileParams.wrapMultipart(
      SelfProfileParams.buildForUser(uid, portrait, device, page));
    const transport: HttpResult = await this.client.postBinary(
      SelfProfileParams.url(TiebaHost.APP).replace('http:', 'https:'), body, SelfProfileParams.headers(session));
    if (!transport.ok) { response.transportError = transport.error; return response; }
    const code: number = parseProtoErrorno(transport.bytes);
    if (code !== 0) { response.failBusiness(code, '无法读取用户资料'); return response; }
    const data: UserProfileInfo = parseSelfProfileProto(transport.bytes);
    if (!data.hasAny()) { response.failLocal('用户资料为空或格式无效'); return response; }
    response.ok = true;
    response.data = data;
    return response;
  }
  private client: HttpClient = new HttpClient();

  /** 网页首页侧栏的真实热议榜。HAR 核对过这三个 GET 参数及 PC 签名。 */
  async fetchHotTopics(): Promise<HotTopicsResponse> {
    const response: HotTopicsResponse = new HotTopicsResponse();
    this.client.userAgent = BROWSER_UA;
    const params: SignParam[] = [
      new SignParam('subapp_type', 'pc'),
      new SignParam('_client_type', '20')
    ];
    const sign: string = await WebPcSign.sign(params);
    const url: string = `https://tieba.baidu.com/c/f/pc/homeSidebarRight?` +
      `subapp_type=pc&_client_type=20&sign=${encodeURIComponent(sign)}`;
    const transport: HttpResult = await this.client.getWithCookie(url, '', {
      'Referer': 'https://tieba.baidu.com/',
      'X-Requested-With': 'XMLHttpRequest'
    });
    if (!transport.ok) {
      response.transportError = transport.error;
      return response;
    }
    let envelope: RawHotTopicResponse;
    try {
      envelope = JSON.parse(decodeUtf8(transport.bytes)) as RawHotTopicResponse;
    } catch (err) {
      response.failLocal('热榜响应不是合法 JSON');
      return response;
    }
    const code: number = normalizeErrorCode(envelope.error_code);
    if (code !== ERROR_OK) {
      response.failBusiness(code, envelope.error_msg ?? '');
      return response;
    }
    if (!Array.isArray(envelope.data?.hot_topic_list)) {
      response.failLocal('热榜响应缺少话题列表');
      return response;
    }
    response.data = parseHotTopics(envelope.data);
    response.ok = true;
    return response;
  }

  private async postJsonText(path: string, params: SignParam[], out: ApiResult,
    host: string = TiebaHost.APP,
    extraHeaders?: Record<string, string>): Promise<string | undefined> {
    const signed: SignParam[] = await CryptoUtil.appendSign(params, SignSalt.APP);
    if (path === '/c/c/agree/opAgree') {
      // UI 点赞失效定位：每笔 opAgree 发送前记一行脱敏指纹（seq/时间/字段/body 哈希/sign）
      AgreeTrace.logOpAgree(signed);
    }
    const url: string = `https://${host}${path}`;
    const transport: HttpResult =
      await this.client.postForm(url, TiebaCommonParams.encodeForm(signed), extraHeaders);

    if (!transport.ok) {
      out.transportError = transport.error;
      return undefined;
    }

    const text: string = decodeUtf8(transport.bytes);

    // 先用最小信封查业务错误：出错时响应体不是预期结构，
    // 直接按具体类型解析会得到一片 undefined，看起来像"空数据"而非"被拒"
    let envelope: ApiEnvelope;
    try {
      envelope = JSON.parse(text) as ApiEnvelope;
    } catch (err) {
      const e: Error = err as Error;
      out.failLocal(`响应不是合法 JSON：${e.message}`);
      return undefined;
    }

    /*
     * 归一后再比较：服务端 `error_code` 有数字（frs/page）与字符串（agree/opAgree）两种形态，
     * 直接把字符串和 0 比较会让**成功响应被误判为失败**。详见 ApiEnvelope 注释。
     */
    const code: number = normalizeErrorCode(envelope.error_code);

    if (code !== ERROR_OK) {
      out.failBusiness(code, envelope.error_msg === undefined ? '' : envelope.error_msg);
      hilog.info(0x0000, 'TiebaApi',
        'postJsonText business error: path=%{public}s error_code=%{public}s error_msg=%{public}s',
        path, String(code), envelope.error_msg === undefined ? '(none)' : envelope.error_msg);
      return undefined;
    }
    return text;
  }

  /** 公共前置校验：设备身份。返回空串表示通过 */
  private static checkDevice(device: TiebaDevice): string {
    if (!device.isUsable()) {
      return '设备身份不完整，无法构造请求';
    }
    return '';
  }

  /** 缓存的账号 uid，用于本项目请求头 `client_user_token`，会话切换后作废 */
  private cachedUid: number = 0;

  resetUidCache(): void {
    this.cachedUid = 0;
  }

  async accountUid(session: TiebaSession): Promise<number> {
    if (this.cachedUid > 0) {
      return this.cachedUid;
    }
    if (!session.hasBduss()) {
      return 0;
    }
    const previousUa: string = this.client.userAgent;
    this.client.userAgent = BROWSER_UA;
    try {
      const res: HttpResult = await this.client.getWithCookie(
        USERINFO_URL, `BDUSS=${session.bduss}; STOKEN=${session.stoken}`);
      if (!res.ok) {
        hilog.warn(0x0000, 'TiebaApi', 'account uid: userinfo not ok (code=%{public}d)', res.code);
        return 0;
      }
      // 复用同一份解析（`model/UserProfile.ets`，Node 侧有同一套用例锁着）。
      // 不再自己 JSON.parse：键名一改就要改两处，是这类"静默解析成空"的经典来源
      const safe: number = parseUserInfo(decodeUtf8(res.bytes)).uid;
      if (safe > 0) {
        this.cachedUid = safe;
      }
      hilog.info(0x0000, 'TiebaApi', 'account uid resolved: %{public}s',
        safe > 0 ? 'yes' : 'no (falls back to 0)');
      return safe;
    } catch (err) {
      const e: Error = err as Error;
      hilog.warn(0x0000, 'TiebaApi', 'account uid fetch failed: %{public}s', e.message);
      return 0;
    } finally {
      this.client.userAgent = previousUa;
    }
  }

  /** 当前账号的昵称、头像与 uid 来自 /f/user/json_userinfo；社交资料由 fetchSelfProfile 单独读取。 */
  async fetchUserInfo(session: TiebaSession): Promise<UserProfileInfo> {
    if (session.bduss.length === 0) {
      return new UserProfileInfo();
    }
    const previousUa: string = this.client.userAgent;
    this.client.userAgent = BROWSER_UA;
    try {
      const res: HttpResult = await this.client.getWithCookie(
        USERINFO_URL, `BDUSS=${session.bduss}; STOKEN=${session.stoken}`);
      if (!res.ok) {
        hilog.warn(0x0000, 'TiebaApi', 'json_userinfo not ok: code=%{public}d', res.code);
        return new UserProfileInfo();
      }
      const info: UserProfileInfo = parseUserInfo(decodeUtf8(res.bytes));

      // 第二兜底：json_userinfo 缺昵称或头像时，仍试一次 passport（保持既有行为）
      if (info.nickName.length === 0 || info.portrait.length === 0) {
        await this.tryPassportApi(session, info);
      }
      hilog.info(0x0000, 'TiebaApi',
        'json_userinfo: uid=%{public}s nick=%{public}s portrait=%{public}s',
        info.uid > 0 ? 'yes' : 'no',
        info.nickName.length > 0 ? 'yes' : 'no',
        info.portrait.length > 0 ? 'yes' : 'no');
      return info;
    } catch (err) {
      const e: Error = err as Error;
      hilog.warn(0x0000, 'TiebaApi', 'json_userinfo failed: %{public}s', e.message);
      return new UserProfileInfo();
    } finally {
      this.client.userAgent = previousUa;
    }
  }

  /** 读取当前账号的社交资料，包括关注、粉丝、等级与关注贴吧。使用 multipart protobuf 请求。 */
  async fetchSelfProfile(session: TiebaSession, device: TiebaDevice,
    portrait: string = ''): Promise<UserProfileInfo | undefined> {
    if (session.bduss.length === 0) {
      return undefined;
    }
    const check: string = TiebaApi.checkDevice(device);
    if (check.length > 0) {
      hilog.warn(0x0000, 'TiebaApi', 'self profile skipped: %{public}s', check);
      return undefined;
    }
    if (portrait.length === 0) {
      // 没有头像 hash 就定位不到本人 —— `uid` 那条路已被证伪（见 SelfProfileParams 的方法注释）
      hilog.warn(0x0000, 'TiebaApi', 'self profile skipped: portrait unavailable');
      return undefined;
    }

    const body: Uint8Array =
      SelfProfileParams.wrapMultipart(SelfProfileParams.buildRequest(portrait, device));
    const transport: HttpResult = await this.client.postBinary(
      SelfProfileParams.url(TiebaHost.APP), body, SelfProfileParams.headers(session));
    if (!transport.ok) {
      hilog.warn(0x0000, 'TiebaApi', 'self profile transport failed: %{public}s',
        transport.error);
      return undefined;
    }
    // pb 通道的业务错误码在响应体里（error.errorno），**不是** HTTP 状态码
    const errorno: number = parseProtoErrorno(transport.bytes);
    if (errorno !== 0) {
      hilog.warn(0x0000, 'TiebaApi', 'self profile errorno=%{public}d', errorno);
      return undefined;
    }
    const info: UserProfileInfo = parseSelfProfileProto(transport.bytes);
    hilog.info(0x0000, 'TiebaApi',
      'self profile(pb): concern=%{public}d fans=%{public}d level=%{public}d'
        + ' likeForum=%{public}d post=%{public}d',
      info.concernNum, info.fansNum, info.levelId, info.likeForumNum, info.postNum);
    return info;
  }

  /**
   * 尝试从 passport 获取用户昵称与头像。
   *
   * 现在它是**第二兜底**：`json_userinfo` 实测已能给出昵称（`user_name_show`）
   * 与头像（`user_portrait`），只有那次请求失败时才走到这里。
   */
  private async tryPassportApi(session: TiebaSession, profile: UserProfileInfo): Promise<void> {
    const PASSPORT_URL: string = 'https://passport.baidu.com/v3/api/user/info';
    try {
      const res: HttpResult = await this.client.getWithCookie(
        PASSPORT_URL, `BDUSS=${session.bduss}; STOKEN=${session.stoken}`);
      if (!res.ok) {
        hilog.info(0x0000, 'TiebaApi', 'passport api: not ok (code=%{public}d)', res.code);
        return;
      }
      const raw: string = decodeUtf8(res.bytes);
      if (raw.length === 0) {
        return;
      }
      const parsed: PassportInfo = JSON.parse(raw) as PassportInfo;
      // passport 返回格式：{ errorCode: 0, data: { uname, displayName, portrait, uid } }
      if (parsed.errorCode !== 0 || parsed.data === undefined) {
        hilog.info(0x0000, 'TiebaApi', 'passport api: errorCode=%{public}d', parsed.errorCode);
        return;
      }
      if (profile.nickName.length === 0) {
        profile.nickName = parsed.data.displayName ?? parsed.data.uname ?? '';
      }
      if (profile.portrait.length === 0 && (parsed.data.portrait ?? '').length > 0) {
        // passport 返回完整 URL，需提取 hash
        const fullUrl: string = parsed.data.portrait ?? '';
        const lastSlash: number = fullUrl.lastIndexOf('/');
        profile.portrait = lastSlash >= 0 ? fullUrl.substring(lastSlash + 1) : fullUrl;
      }
      const puid: number = parsed.data.uid ?? 0;
      if (profile.uid === 0 && puid > 0) {
        profile.uid = puid;
      }
      hilog.info(0x0000, 'TiebaApi', 'passport api: resolved nick=%{public}s portrait=%{public}s',
        profile.nickName.length > 0 ? 'yes' : 'no',
        profile.portrait.length > 0 ? 'yes' : 'no');
    } catch (err) {
      hilog.warn(0x0000, 'TiebaApi', 'passport api fetch failed: %{public}s', (err as Error).message);
    }
  }

  async fetchThreadList(device: TiebaDevice, session: TiebaSession, forumName: string,
    page: number, pageSize: number, tabId: number = 0): Promise<ThreadListResponse> {
    const response: ThreadListResponse = new ThreadListResponse();

    if (forumName.length === 0 || forumName.trim().length === 0) {
      response.failLocal('吧名不能为空');
      return response;
    }
    const deviceError: string = TiebaApi.checkDevice(device);
    if (deviceError.length > 0) {
      response.failLocal(deviceError);
      return response;
    }

    device.clientVersion = TiebaVersion.LATEST;
    this.client.userAgent = `bdtb for Android ${TiebaVersion.LATEST}`;

    const params: SignParam[] = TiebaCommonParams.build(device, session);
    params.push(new SignParam('kw', forumName));
    params.push(new SignParam('pn', String(page)));
    params.push(new SignParam('rn', String(pageSize)));
    params.push(new SignParam('st_type', 'frs'));
    if (tabId > 0) {
      params.push(new SignParam('tab_id', String(tabId)));
    }

    const text: string | undefined = await this.postJsonText('/c/f/frs/page', params, response);
    if (text === undefined) {
      return response;
    }

    response.ok = true;
    response.data = ThreadListResult.fromRaw(JSON.parse(text) as RawFrsPage);
    return response;
  }

  /** 吧内视频通用分类；tab_id 来自本吧导航，分页/排序以接口真实字段为准。 */
  async fetchForumVideos(device: TiebaDevice, session: TiebaSession, forum: ForumBrief,
    tab: ForumTab, page: number, sortType: number = 0): Promise<ThreadListResponse> {
    const response: ThreadListResponse = new ThreadListResponse();
    if (!tab.isVideo || tab.id <= 0 || forum.id <= 0 || forum.name.length === 0 || page < 1 || (sortType !== 0 && sortType !== 1)) {
      response.failLocal('视频分类参数不完整'); return response;
    }
    const check: string = TiebaApi.checkDevice(device);
    if (check.length > 0) { response.failLocal(check); return response; }
    const params: SignParam[] = TiebaCommonParams.build(device, session);
    params.push(new SignParam('forum_id', String(forum.id)), new SignParam('forum_name', forum.name),
      new SignParam('tab_id', String(tab.id)), new SignParam('tab_name', tab.name),
      new SignParam('is_general_tab', '1'), new SignParam('is_video_doublerow', '1'),
      new SignParam('pn', String(page)), new SignParam('rn', '20'), new SignParam('sort_type', String(sortType)));
    const text: string | undefined = await this.postJsonText('/c/f/frs/generalTabList', params, response);
    if (text === undefined) { return response; }
    const raw: RawGeneralTabList = JSON.parse(text) as RawGeneralTabList;
    if (!Array.isArray(raw.general_list) || (String(raw.has_more) !== '0' && String(raw.has_more) !== '1')) {
      response.failLocal('视频分类响应不完整'); return response;
    }
    if (Number(raw.sort_type) !== sortType) { response.failLocal('服务端未确认视频排序'); return response; }
    response.data = ThreadListResult.fromRaw({ thread_list: raw.general_list, user_list: raw.user_list });
    response.data.forum = forum; response.data.selectedTabId = tab.id;
    response.data.page.currentPage = page; response.data.page.hasMore = String(raw.has_more) === '1';
    response.ok = true; return response;
  }

  async fetchForumHeadline(device: TiebaDevice, session: TiebaSession,
    forumName: string): Promise<ForumHeadlineResult> {
    const empty: ForumHeadlineResult = new ForumHeadlineResult();
    const name: string = forumName.trim();
    if (name.length === 0) {
      return empty;
    }

    // 网页端接口：浏览器 UA + form 签名（SignSalt.PC）。与登录态无关，未登录也发。
    this.client.userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
      '(KHTML, like Gecko) Chrome/153.0.0.0 Safari/537.36';
    const body: string = await FrsHeadlineParams.buildBody(name);
    const transport: HttpResult = await this.client.postForm(FrsHeadlineParams.url(), body);
    if (!transport.ok || transport.bytes.length === 0) {
      hilog.warn(0x0000, 'TiebaApi',
        'forum headline transport failed forum=%{public}s error=%{public}s',
        name, transport.error ?? '');
      return empty;
    }

    const text: string = decodeUtf8(transport.bytes);
    const parsed: ForumHeadlineResult = parseForumHeadlineJson(text);
    hilog.info(0x0000, 'TiebaApi',
      'forum headline forum=%{public}s errorno=%{public}d hasImg=%{public}s',
      name, parsed.errorno, parsed.imgUrl.length > 0 ? 'yes' : 'no');
    return parsed;
  }

  /** 搜帖子；forumName 非空时添加 kw 参数进行吧内搜索。 */
  async searchPosts(device: TiebaDevice, session: TiebaSession, word: string,
    page: number, pageSize: number, forumName?: string): Promise<SearchPostResponse> {
    const response: SearchPostResponse = new SearchPostResponse();

    const clean: string = word.trim();
    if (clean.length === 0) {
      response.failLocal('搜索词不能为空');
      return response;
    }
    const deviceError: string = TiebaApi.checkDevice(device);
    if (deviceError.length > 0) {
      response.failLocal(deviceError);
      return response;
    }

    device.clientVersion = TiebaVersion.LATEST;
    this.client.userAgent = `bdtb for Android ${TiebaVersion.LATEST}`;

    const params: SignParam[] = TiebaCommonParams.build(device, session);
    params.push(new SignParam('word', clean));
    params.push(new SignParam('pn', String(page)));
    params.push(new SignParam('rn', String(pageSize)));
    // 吧内搜索：只多这一个参数（证据见方法头；空串不发，避免把空 kw 当成查询条件）
    const scope: string = searchScopeForum(forumName);
    if (scope.length > 0) {
      params.push(new SignParam('kw', scope));
    }

    const text: string | undefined = await this.postJsonText('/c/s/searchpost', params, response);
    if (text === undefined) {
      return response;
    }

    response.ok = true;
    response.data = SearchPostPage.fromRaw(JSON.parse(text) as RawSearchPostResponse);
    return response;
  }

  /** 网页搜吧使用 GET /mo/q/search/forum，业务码为 no，page 从 1 开始；网页签名参考 lumina37/aiotieba（Unlicense）。 */
  async searchForums(word: string, page: number, pageSize: number): Promise<ForumSearchResponse> {
    const response: ForumSearchResponse = new ForumSearchResponse();

    const clean: string = word.trim();
    if (clean.length === 0) {
      response.failLocal('搜索词不能为空');
      return response;
    }

    this.client.userAgent = BROWSER_UA;

    const params: SignParam[] = [
      new SignParam('_client_type', '20'),
      new SignParam('pn', String(page)),
      new SignParam('rn', String(pageSize)),
      new SignParam('st', '0'),
      new SignParam('subapp_type', 'pc'),
      new SignParam('tt', '1'),
      new SignParam('word', clean)
    ];
    const sign: string = await WebPcSign.sign(params);
    const pairs: string[] = [];
    for (const p of params) {
      pairs.push(`${encodeURIComponent(p.key)}=${encodeURIComponent(p.value)}`);
    }
    pairs.push(`sign=${encodeURIComponent(sign)}`);
    const url: string = `https://tieba.baidu.com/mo/q/search/forum?${pairs.join('&')}`;

    const transport: HttpResult =
      await this.client.getWithCookie(url, '', { 'Referer': PC_SEARCH_REFERER });
    if (!transport.ok) {
      response.transportError = transport.error;
      return response;
    }

    const text: string = decodeUtf8(transport.bytes);
    let envelope: RawForumSearchResponse;
    try {
      envelope = JSON.parse(text) as RawForumSearchResponse;
    } catch (err) {
      const e: Error = err as Error;
      response.failLocal(`响应不是合法 JSON：${e.message}`);
      return response;
    }

    // web 端信封：业务码叫 no（0 成功），错误信息在 error
    const code: number = envelope.no === undefined ? 0 : envelope.no;
    if (code !== ERROR_OK) {
      response.failBusiness(code, envelope.error === undefined ? '' : envelope.error);
      hilog.info(0x0000, 'TiebaApi', 'searchForums business error: no=%{public}s error=%{public}s',
        String(code), envelope.error === undefined ? '(none)' : envelope.error);
      return response;
    }

    response.ok = true;
    response.data = ForumSearchPage.fromRaw(envelope);
    return response;
  }

  async fetchSearchAuthorAvatar(account: string): Promise<string> {
    const name: string = account.trim();
    if (name.length === 0) { return ''; }
    // 该端点遇到 Android/HarmonyOS UA 会返回移动网页而非 JSON；匿名实测桌面形态可用。
    this.client.userAgent = 'Mozilla/5.0';
    const transport: HttpResult = await this.client.getWithCookie(
      `https://tieba.baidu.com/home/get/panel?ie=utf-8&un=${encodeURIComponent(name)}`,
      '', { 'Referer': 'https://tieba.baidu.com/' });
    return transport.ok ? searchAuthorAvatar(decodeUtf8(transport.bytes), name) : '';
  }

  /** 与搜吧同族的公开搜人接口；当前真实响应 has_more=0，不猜测更多页。 */
  async searchUsers(word: string, page: number, pageSize: number): Promise<UserSearchResponse> {
    const response: UserSearchResponse = new UserSearchResponse();
    const query: string = word.trim();
    if (query.length === 0 || !Number.isInteger(page) || page < 1
      || !Number.isInteger(pageSize) || pageSize < 1 || pageSize > 100) {
      response.failLocal('搜索参数无效'); return response;
    }
    this.client.userAgent = BROWSER_UA;
    const params: SignParam[] = [
      new SignParam('_client_type', '20'), new SignParam('pn', String(page)),
      new SignParam('rn', String(pageSize)), new SignParam('st', '0'),
      new SignParam('subapp_type', 'pc'), new SignParam('tt', '1'), new SignParam('word', query)
    ];
    const sign: string = await WebPcSign.sign(params);
    const pairs: string[] = params.map((param: SignParam) =>
      `${encodeURIComponent(param.key)}=${encodeURIComponent(param.value)}`);
    pairs.push(`sign=${encodeURIComponent(sign)}`);
    const transport: HttpResult = await this.client.getWithCookie(
      `https://tieba.baidu.com/mo/q/search/user?${pairs.join('&')}`, '', { 'Referer': PC_SEARCH_REFERER });
    if (!transport.ok) { response.transportError = transport.error; return response; }
    const parsed: UserSearchParseResult = parseUserSearch(decodeUtf8(transport.bytes));
    if (!parsed.ok) {
      if (parsed.errorCode === -1) { response.failLocal(parsed.error); }
      else { response.failBusiness(parsed.errorCode, parsed.error); }
      return response;
    }
    response.data = parsed.data;
    response.ok = true;
    return response;
  }

  /** 读取关注贴吧，协议参考 aiotieba get_self_follow_forums（Unlicense）。使用 Cookie、tbs 与 Subapp-Type: hybrid，不加客户端签名。 */
  async fetchFollowForums(session: TiebaSession, page: number, pageSize: number): Promise<FollowForumsResponse> {
    const response: FollowForumsResponse = new FollowForumsResponse();

    if (!session.hasBduss()) {
      response.failLocal('未登录，无法获取关注吧列表');
      return response;
    }
    if (session.tbs.length === 0) {
      response.failLocal('缺少 tbs，无法获取关注吧列表');
      return response;
    }

    this.client.userAgent = BROWSER_UA;
    const params: SignParam[] = [
      new SignParam('tbs', session.tbs),
      new SignParam('sort_type', '3'),
      new SignParam('call_from', '3'),
      new SignParam('page_no', String(page)),
      new SignParam('res_num', String(pageSize))
    ];
    const body: string = TiebaCommonParams.encodeForm(params);
    const transport: HttpResult = await this.client.postForm(
      `https://${TiebaHost.WEB}/c/f/forum/forumGuide`, body,
      {
        'Cookie': `BDUSS=${session.bduss}; STOKEN=${session.stoken}`,
        'Subapp-Type': 'hybrid'
      });

    if (!transport.ok) {
      response.transportError = transport.error;
      return response;
    }

    const text: string = decodeUtf8(transport.bytes);
    let envelope: RawForumGuideResponse;
    try {
      envelope = JSON.parse(text) as RawForumGuideResponse;
    } catch (err) {
      const e: Error = err as Error;
      response.failLocal(`响应不是合法 JSON：${e.message}`);
      return response;
    }

    const code: number = normalizeErrorCode(envelope.error_code);
    if (code !== ERROR_OK) {
      response.failBusiness(code, envelope.error_msg === undefined ? '' : envelope.error_msg);
      return response;
    }

    response.ok = true;
    response.data = FollowForumList.fromRaw(envelope);
    return response;
  }

  async fetchStoredThreads(device: TiebaDevice, session: TiebaSession, uid: number,
    page: number, pageSize: number): Promise<StoredThreadsResponse> {
    const response: StoredThreadsResponse = new StoredThreadsResponse();
    if (!session.hasBduss()) {
      response.failLocal('未登录，无法获取收藏');
      return response;
    }

    this.client.userAgent = `bdtb for Android ${device.clientVersion}`;
    const params: SignParam[] = TiebaCommonParams.build(device, session);
    params.push(new SignParam('user_id', String(uid)));
    params.push(new SignParam('pn', String(page)));
    params.push(new SignParam('rn', String(pageSize)));
    const signed: SignParam[] = await CryptoUtil.appendSign(params, SignSalt.APP);
    const transport: HttpResult = await this.client.postForm(
      `https://${TiebaHost.APP}/c/f/post/threadstore`,
      TiebaCommonParams.encodeForm(signed));

    if (!transport.ok) {
      response.transportError = transport.error;
      return response;
    }
    const text: string = decodeUtf8(transport.bytes);
    let envelope: RawStoredThreadResponse;
    try {
      envelope = JSON.parse(text) as RawStoredThreadResponse;
    } catch (err) {
      const e: Error = err as Error;
      response.failLocal(`响应不是合法 JSON：${e.message}`);
      return response;
    }
    const list: StoredThreadList = StoredThreadList.fromRaw(envelope);
    if (list.errorCode !== ERROR_OK) {
      response.failBusiness(list.errorCode, list.errorMsg);
      return response;
    }
    response.ok = true;
    response.data = list.items;
    return response;
  }

  /**
   * 我的回复 / 我的主题（pb `POST /c/u/feed/userpost?cmd=303002`）。
   *
   * `isThread = 0` → 回复；`1` → 主题帖。同一个端点同一个 cmd，只差这个开关。
   * 请求体构造见 `UserPostParams`；响应解析在 `model/MyContent.ets`（Node 侧同测）。
   *
   * **不签名**（pb 通道的规矩），身份靠 Cookie 与 `common.BDUSS`。
   */
  async fetchUserPosts(device: TiebaDevice, session: TiebaSession, uid: number,
    isThread: number, page: number, pageSize: number): Promise<UserPostsResponse> {
    if (!session.hasBduss()) {
      const response: UserPostsResponse = new UserPostsResponse();
      response.failLocal('未登录，无法获取帖子列表');
      return response;
    }
    return this.fetchPublicUserPosts(device, session, uid, isThread, page, pageSize);
  }

  /** 他人主页的公开帖子；登录会话可选，服务端隐私/权限拒绝仍按业务失败处理。 */
  async fetchPublicUserPosts(device: TiebaDevice, session: TiebaSession, uid: number,
    isThread: number, page: number, pageSize: number): Promise<UserPostsResponse> {
    const response: UserPostsResponse = new UserPostsResponse();
    if (!Number.isSafeInteger(uid) || uid <= 0 || page < 1 || pageSize < 1) {
      response.failLocal('用户帖子参数无效'); return response;
    }
    const check: string = TiebaApi.checkDevice(device);
    if (check.length > 0) {
      response.failLocal(check);
      return response;
    }

    const body: Uint8Array = UserPostParams.wrapMultipart(
      UserPostParams.buildRequest(uid, isThread, page, pageSize, device, session));
    const transport: HttpResult = await this.client.postBinary(
      UserPostParams.url(TiebaHost.APP), body, UserPostParams.headers(session));
    if (!transport.ok) {
      response.transportError = transport.error;
      return response;
    }
    const errorno: number = parseUserPostErrorno(transport.bytes);
    if (errorno !== 0) {
      response.failBusiness(errorno, `服务端错误 ${errorno}`);
      hilog.warn(0x0000, 'TiebaApi', 'userpost errorno=%{public}d isThread=%{public}d',
        errorno, isThread);
      return response;
    }
    response.ok = true;
    const groups: UserPostItem[] = parseUserPostProto(transport.bytes);
    response.hasMore = groups.length > 0;
    response.data = isThread === 0 ? expandUserReplies(groups) : groups;
    return response;
  }

  async fetchPersonalizedFeed(device: TiebaDevice, session: TiebaSession,
    loadType: number, pn: number, pageThreadCount: number): Promise<PersonalizedFeedResponse> {
    const response: PersonalizedFeedResponse = new PersonalizedFeedResponse();
    if (!session.hasBduss()) {
      response.failLocal('未登录，无法获取推荐流');
      return response;
    }
    const check: string = TiebaApi.checkDevice(device);
    if (check.length > 0) {
      response.failLocal(check);
      return response;
    }

    const body: Uint8Array = PersonalizedParams.wrapMultipart(
      PersonalizedParams.buildRequest(loadType, pn, pageThreadCount, device, session));
    const transport: HttpResult = await this.client.postBinary(
      PersonalizedParams.url(TiebaHost.APP), body, PersonalizedParams.headers(session));
    if (!transport.ok) {
      response.transportError = transport.error;
      return response;
    }
    const errorno: number = parsePersonalizedErrorno(transport.bytes);
    if (errorno !== 0) {
      response.failBusiness(errorno, `服务端错误 ${errorno}`);
      hilog.warn(0x0000, 'TiebaApi',
        'personalized errorno=%{public}d loadType=%{public}d pn=%{public}d',
        errorno, loadType, pn);
      return response;
    }
    response.ok = true;
    response.data = parsePersonalizedFeed(transport.bytes);
    return response;
  }

  /**
   * 吧签到（`/c/c/forum/sign`）。
   *
   * 端点来源：aiotieba `sign_forum`（Unlicense）——客户端签名 POST，
   * 参数 BDUSS + _client_version + kw + tbs（公共参数已含前两类，补 kw 即可；
   * 公共参数在 session.tbs 非空时自带 tbs）。成功响应含 `user_info.sign_bonus_point`
   * （本次签到奖励经验），用于界面提示。
   */
  async signForum(device: TiebaDevice, session: TiebaSession, fname: string): Promise<SignForumResponse> {
    const response: SignForumResponse = new SignForumResponse();

    const clean: string = fname.trim();
    if (clean.length === 0) {
      response.failLocal('吧名不能为空');
      return response;
    }
    if (!session.hasBduss()) {
      response.failLocal('未登录，无法签到');
      return response;
    }
    if (session.tbs.length === 0) {
      response.failLocal('缺少 tbs，无法签到');
      return response;
    }
    const deviceError: string = TiebaApi.checkDevice(device);
    if (deviceError.length > 0) {
      response.failLocal(deviceError);
      return response;
    }

    device.clientVersion = TiebaVersion.LATEST;
    this.client.userAgent = `bdtb for Android ${TiebaVersion.LATEST}`;

    const params: SignParam[] = TiebaCommonParams.build(device, session);
    params.push(new SignParam('kw', clean));

    const text: string | undefined = await this.postJsonText('/c/c/forum/sign', params, response);
    if (text === undefined) {
      // 160002 = "已经签过了"：不是失败，按成功返回让界面把状态改成已签到
      if (response.errorCode === 160002) {
        response.alreadySigned = true;
        response.ok = true;
        return response;
      }
      return response;
    }

    response.stats = parseSignStats(text);
    // sign_bonus_point 拿不到不判失败（aiotieba 把 0 当异常，这里宽松处理：提示语降级）
    try {
      const parsed = JSON.parse(text) as SignForumEnvelope;
      if (parsed.user_info !== undefined && parsed.user_info.sign_bonus_point !== undefined) {
        response.bonusPoint = String(parsed.user_info.sign_bonus_point);
      }
    } catch {
      // 解析失败只影响提示语，不影响成功判定
    }

    response.ok = true;
    return response;
  }

  /**
   * 拉取帖子详情（主题 + 一页楼层）。
   *
   * `kz` 是帖子 id，`pn` 是**楼层页**页码（不是主题列表页）。
   * `r=0/1/2` 分别表示正序、倒序、热门序；`lz=1` 表示只看楼主。
   *
   * 注意本响应**不含楼中楼**：即使某楼 `sub_post_number > 0`，`sub_post_list` 也是空的，
   * 要看楼中楼得再调 `fetchSubPosts`。这是实测结论，不是解析漏了。
   */
  async fetchThreadDetail(device: TiebaDevice, session: TiebaSession, tid: number,
    page: number, pageSize: number, sortType: ReplySortType = ReplySortType.ASC,
    targetPid: number = 0): Promise<ThreadDetailResponse> {
    const response: ThreadDetailResponse = new ThreadDetailResponse();

    if (tid <= 0) {
      response.failLocal('帖子 id 无效');
      return response;
    }
    const deviceError: string = TiebaApi.checkDevice(device);
    if (deviceError.length > 0) {
      response.failLocal(deviceError);
      return response;
    }

    device.clientVersion = TiebaVersion.LATEST;
    this.client.userAgent = `bdtb for Android ${TiebaVersion.LATEST}`;

    const params: SignParam[] = TiebaCommonParams.build(device, session);
    params.push(new SignParam('kz', String(tid)));
    // 真机读回：pid 定位需要 pn=0；pn=1 会得到空 post_list。
    params.push(new SignParam('pn', String(targetPid > 0 ? 0 : page)));
    params.push(new SignParam('rn', String(pageSize)));
    if (targetPid > 0) {
      params.push(new SignParam('pid', String(targetPid)));
    }
    const onlyAuthor: boolean = sortType === ReplySortType.ONLY_AUTHOR;
    const serverSort: number = onlyAuthor ? ReplySortType.ASC : sortType;
    params.push(new SignParam('r', String(serverSort)));
    params.push(new SignParam('lz', onlyAuthor ? '1' : '0'));

    const text: string | undefined = await this.postJsonText('/c/f/pb/page', params, response);
    if (text === undefined) {
      return response;
    }

    response.ok = true;
    response.data = ThreadDetail.fromRaw(JSON.parse(text) as RawThreadPage, tid, Date.now());
    return response;
  }

  async isThreadDeleted(device: TiebaDevice, session: TiebaSession, tid: number): Promise<boolean> {
    if (tid <= 0) {
      return false;
    }
    const res: ThreadDetailResponse =
      await this.fetchThreadDetail(device, session, tid, 1, 1);
    return !res.ok && res.errorCode === ERRNO_THREAD_DELETED;
  }

  /**
   * 拉取某楼的楼中楼。
   *
   * 端点是 `/c/f/pb/floor`（实测；`/c/f/pb/lfloor` 返回空体，不是它）。
   * `pid` 是楼层 id（楼层列表里的 `id`，不是 tid）。
   * `threadAuthorId` 用来标记"楼主"——楼中楼响应里带内联作者，但没有主题作者 id，
   * 只能由调用方从详情页拿过来。
   */
  async fetchSubPosts(device: TiebaDevice, session: TiebaSession, tid: number, pid: number,
    threadAuthorId: number, page: number, pageSize: number): Promise<SubPostResponse> {
    const response: SubPostResponse = new SubPostResponse();

    if (tid <= 0 || pid <= 0) {
      response.failLocal('帖子 id 或楼层 id 无效');
      return response;
    }
    const deviceError: string = TiebaApi.checkDevice(device);
    if (deviceError.length > 0) {
      response.failLocal(deviceError);
      return response;
    }

    device.clientVersion = TiebaVersion.LATEST;
    this.client.userAgent = `bdtb for Android ${TiebaVersion.LATEST}`;

    const params: SignParam[] = TiebaCommonParams.build(device, session);
    params.push(new SignParam('kz', String(tid)));
    params.push(new SignParam('pid', String(pid)));
    params.push(new SignParam('pn', String(page)));
    params.push(new SignParam('rn', String(pageSize)));

    const text: string | undefined = await this.postJsonText('/c/f/pb/floor', params, response);
    if (text === undefined) {
      return response;
    }

    response.ok = true;
    response.data = SubPostPage.fromRaw(JSON.parse(text) as RawSubPostPageResponse,
      threadAuthorId, Date.now());
    return response;
  }

  /** HTTPS 校验裸 BDUSS 并获取 anti.tbs；不将待校验凭据发布到当前会话。
   * 协议来源：https://github.com/lumina37/aiotieba/blob/master/src/aiotieba/api/login/_api.py
   * 旧网页 dc/common/tbs 的 HTTPS 分流返回未登录，当前改走已真机验证的客户端路径。
   */
  async fetchTbsWithBduss(bduss: string): Promise<TbsResponse> {
    const response: TbsResponse = new TbsResponse();
    if (bduss.length === 0) { response.failLocal('缺少 BDUSS'); return response; }
    // aiotieba api/login/_api.py：两个参数 APP 签名，HTTPS /c/s/login，anti.tbs。

    const signed: SignParam[] = await CryptoUtil.appendSign([
      new SignParam('_client_version', TiebaVersion.LATEST), new SignParam('bdusstoken', bduss)
    ], SignSalt.APP);
    this.client.userAgent = `bdtb for Android ${TiebaVersion.LATEST}`;
    const transport: HttpResult = await this.client.postForm(
      `https://${TiebaHost.APP}/c/s/login`, TiebaCommonParams.encodeForm(signed));
    if (!transport.ok) { response.transportError = transport.error; return response; }
    try {
      const parsed: TbsEnvelope = JSON.parse(decodeUtf8(transport.bytes)) as TbsEnvelope;
      if (parsed === null || parsed.error_code === undefined ||
        !/^[0-9]+$/.test(String(parsed.error_code))) {
        response.failLocal('登录校验响应缺少有效状态码'); return response;
      }
      const code: number = Number(parsed.error_code);
      if (code !== ERROR_OK) { response.failBusiness(code, parsed.error_msg ?? '登录校验失败'); return response; }
      const uid: string = String(parsed.user?.id ?? '');
      const tbs: string = parsed.anti?.tbs ?? '';
      if (!/^[1-9][0-9]*$/.test(uid) || typeof tbs !== 'string' || tbs.length === 0) {
        response.failLocal('登录校验响应缺少账号或 tbs'); return response;
      }
      response.ok = true; response.isLogin = true; response.tbs = tbs;
    } catch (err) { response.failLocal('登录校验响应无法解析'); }
    return response;
  }

  /** 点赞与取消点赞共用 opAgree，由 op_type 区分。obj_type：主题=3、楼层=1、楼中楼=2；主题状态读 thread.agree。签名覆盖最终全部字段，CUID 使用持久化设备标识。协议参考 aiotieba api/agree/_api.py（Unlicense）。 */
  async agreePost(device: TiebaDevice, session: TiebaSession, tid: number, pid: number,
    agree: boolean, objType: AgreeObjType = AgreeObjType.POST,
    forumId: number = 0): Promise<AgreeResponse> {
    const response: AgreeResponse = new AgreeResponse();

    if (tid <= 0) {
      response.failLocal('帖子 id 无效');
      return response;
    }
    // 主帖发 post_id=0，本来就没有 pid；楼层/楼中楼没有 pid 才是真的没得点
    if (objType !== AgreeObjType.THREAD && pid <= 0) {
      response.failLocal('楼层 id 无效');
      return response;
    }
    if (!session.hasBduss()) {
      response.failLocal('需要登录后才能点赞');
      return response;
    }
    if (session.tbs.length === 0) {
      response.failLocal('缺少 tbs，无法提交点赞');
      return response;
    }
    const deviceError: string = TiebaApi.checkDevice(device);
    if (deviceError.length > 0) {
      response.failLocal(deviceError);
      return response;
    }

    const uid: number = await this.accountUid(session);
    const antiSpam: SignParam[] = AntiSpamParams.generate(Date.now());
    const params: SignParam[] = AgreeParams.build(
      device, session, uid, tid, pid, agree ? '0' : '1', objType, antiSpam, forumId);
    const headers: Record<string, string> = AgreeParams.headers(uid);

    // 日志只记非凭据字段（agree_type/op_type/obj_type、身份与结果），绝不记 BDUSS/STOKEN/tbs
    const objTypeText: string = String(objType);
    const identityText: string = `host=${AgreeParams.HOST} uid=${uid > 0 ? 'set' : '(unknown)'}`
      + ` _client_version=${AgreeParams.CLIENT_VERSION}`
      + ` cuid=${briefValue(valueOf(params, 'cuid'))}`
      + ` cuid_galaxy2=${valueOf(params, 'cuid_galaxy2') === '<missing>' ? '(absent)' : 'present(same-as-cuid)'}`
      + ` _client_id=${valueOf(params, '_client_id') === '<missing>' ? '(absent)' : 'present'}`
      + ` _os_version=${valueOf(params, '_os_version')}`
      + ` model=${briefValue(valueOf(params, 'model'))}`
      + ` net_type=${valueOf(params, 'net_type')}`
      + ` _phone_imei=${valueOf(params, '_phone_imei')}`
      + ` from=${valueOf(params, 'from') === '<missing>' ? '(absent)' : 'PRESENT(!)'}`
      + ` stoken=${session.stoken.length > 0 ? 'present' : '(empty)'}`
      + ` cookie=${AgreeParams.COOKIE} client_user_token=${uid > 0 ? 'present' : 'empty'}`;

    // 成功必须拿到 JSON 且 error_code 为 0；空体/非 JSON 一律判失败
    const text: string | undefined = await this.postJsonText(
      AgreeParams.PATH, params, response, AgreeParams.HOST, headers);

    if (text === undefined) {
      /*
       * 诊断日志放在**判定之后**：此处 ok 必然是 false。
       * 早先把它放在 `response.ok = true` 之前，日志会打印赋值前的旧值，
       * 于是"成功响应"被日志显示成 ok=false —— 日志必须反映最终状态，否则比没有更误导。
       */
      hilog.info(0x0000, 'TiebaApi',
        'agree result: path=/c/c/agree/opAgree agree_type=2 op_type=%{public}s obj_type=%{public}s'
          + ' identity[%{public}s] responded=false ok=false errorCode=%{public}s errorMsg=%{public}s'
          + ' transportErr=%{public}s',
        agree ? '0' : '1', objTypeText, identityText, String(response.errorCode), response.errorMessage,
        response.transportError.length === 0 ? '(none)' : response.transportError);
      return response;
    }

    response.ok = true;

    /* 解析 data.agree.score / is_first_agree，用于客户端即时判定点赞是否落账 */
    try {
      const obj: object = JSON.parse(text);
      if (typeof obj === 'object' && obj !== null) {
        const data: Record<string, object> = obj as Record<string, object>;
        const agreeRaw: object | undefined = (data['data'] as Record<string, object> | undefined)?.['agree'];
        if (agreeRaw !== undefined) {
          const agree: Record<string, string> = agreeRaw as Record<string, string>;
          response.agreeScore = typeof agree['score'] === 'string' ? agree['score'] : '';
          response.isFirstAgree = typeof agree['is_first_agree'] === 'string' ? agree['is_first_agree'] : '';
        }
      }
    } catch (_) { /* 解析失败不阻塞：沿用空串，后续靠确认读回调回服务端状态 */ }

    hilog.info(0x0000, 'TiebaApi',
      'agree result: path=/c/c/agree/opAgree agree_type=2 op_type=%{public}s obj_type=%{public}s'
        + ' identity[%{public}s] responded=true ok=true bodyBytes=%{public}s'
        + ' agreeScore=%{public}s isFirstAgree=%{public}s',
      agree ? '0' : '1', objTypeText, identityText, String(text.length),
      response.agreeScore, response.isFirstAgree);
    return response;
  }

  /** 收藏主题，发送 POST /c/c/post/addstore。 */
  async addStoreThread(device: TiebaDevice, session: TiebaSession, tid: number,
    pid: number): Promise<StoreOpResponse> {
    const response: StoreOpResponse = new StoreOpResponse();

    if (tid <= 0) {
      response.failLocal('帖子 id 无效');
      return response;
    }
    if (pid <= 0) {
      response.failLocal('首楼 id 无效，无法提交收藏');
      return response;
    }
    if (!session.hasBduss()) {
      response.failLocal('需要登录后才能收藏');
      return response;
    }
    if (session.tbs.length === 0) {
      response.failLocal('缺少 tbs，无法提交收藏');
      return response;
    }
    const deviceError: string = TiebaApi.checkDevice(device);
    if (deviceError.length > 0) {
      response.failLocal(deviceError);
      return response;
    }

    this.client.userAgent = `bdtb for Android ${device.clientVersion}`;
    const params: SignParam[] = StoreParams.buildAdd(device, session, tid, pid);
    const text: string | undefined = await this.postJsonText(StoreParams.ADD_PATH, params, response);
    /*
     * 成功判定：postJsonText 只负责标记失败（transport/JSON/业务错误），
     * 拿到响应文本且没被标记失败就是成功——**必须显式置 ok=true**，
     * 否则"服务端已收藏成功、客户端却报失败"，首轮真机实测就抓到过这个漏洞。
     */
    if (text !== undefined) {
      response.ok = true;
    }
    hilog.info(0x0000, 'TiebaApi',
      'store result: path=%{public}s op=add tid=%{public}d pid=%{public}d'
        + ' responded=%{public}s ok=%{public}s errorCode=%{public}s errorMsg=%{public}s',
      StoreParams.ADD_PATH, tid, pid, String(text !== undefined), String(response.ok),
      String(response.errorCode), response.errorMessage);
    return response;
  }

  async removeStoreThread(device: TiebaDevice, session: TiebaSession,
    tid: number): Promise<StoreOpResponse> {
    const response: StoreOpResponse = new StoreOpResponse();

    if (tid <= 0) {
      response.failLocal('帖子 id 无效');
      return response;
    }
    if (!session.hasBduss()) {
      response.failLocal('需要登录后才能操作收藏');
      return response;
    }
    if (session.tbs.length === 0) {
      response.failLocal('缺少 tbs，无法提交收藏');
      return response;
    }
    const deviceError: string = TiebaApi.checkDevice(device);
    if (deviceError.length > 0) {
      response.failLocal(deviceError);
      return response;
    }

    this.client.userAgent = `bdtb for Android ${device.clientVersion}`;
    const uid: number = await this.accountUid(session);
    const params: SignParam[] = StoreParams.buildRemove(device, session, tid, uid);
    const text: string | undefined = await this.postJsonText(StoreParams.RM_PATH, params, response);
    // 同 addstore：拿到响应文本即成功（postJsonText 已把失败标好），必须显式置 ok
    if (text !== undefined) {
      response.ok = true;
    }
    hilog.info(0x0000, 'TiebaApi',
      'store result: path=%{public}s op=rm tid=%{public}d uid=%{public}s'
        + ' responded=%{public}s ok=%{public}s errorCode=%{public}s errorMsg=%{public}s',
      StoreParams.RM_PATH, tid, uid > 0 ? 'resolved' : '0(fallback)',
      String(text !== undefined), String(response.ok),
      String(response.errorCode), response.errorMessage);
    return response;
  }

  async fetchAllMeme(device: TiebaDevice, session: TiebaSession): Promise<MemeEmojiResponse> {
    const response: MemeEmojiResponse = new MemeEmojiResponse();
    if (!session.hasBduss()) {
      response.failLocal('需要登录后才能看到收藏表情');
      return response;
    }
    if (session.tbs.length === 0) {
      response.failLocal('缺少 tbs，无法拉取收藏表情');
      return response;
    }
    const deviceError: string = TiebaApi.checkDevice(device);
    if (deviceError.length > 0) {
      response.failLocal(deviceError);
      return response;
    }
    this.client.userAgent = `bdtb for Android ${device.clientVersion}`;
    const params: SignParam[] = MemeEmojiParams.buildAll(device, session);
    const text: string | undefined = await this.postJsonText(
      MemeEmojiParams.ALL_PATH, params, response);
    if (text !== undefined) {
      response.ok = true;
      try {
        response.data = MemeEmojiData.fromEnvelope(JSON.parse(text) as Record<string, Object>);
      } catch (err) {
        response.ok = false;
        response.failLocal(`收藏表情响应解析失败：${(err as Error).message}`);
      }
    }
    hilog.info(0x0000, 'TiebaApi',
      'meme result: path=%{public}s responded=%{public}s ok=%{public}s'
        + ' pics=%{public}d diy=%{public}d errorCode=%{public}s errorMsg=%{public}s',
      MemeEmojiParams.ALL_PATH, String(text !== undefined), String(response.ok),
      response.data.pics.length, response.data.diyPics.length,
      String(response.errorCode), response.errorMessage);
    return response;
  }

  /**
   * 收藏表情全量推送（`POST /c/e/meme/collect`）—— 协议在 `MemeEmojiParams` 注释里。
   *
   * ⚠️ **全量语义 + 未知响应形状**：调用方必须自己保证 `pics` 是"当前云端收藏
   * 的完整目标态"。一期只允许 `MemeProbe` 在**空收藏账号**上探测
   * （`all_delete` 无数据可损）；给真实用户启用增删前，先做"拉取 → 原样推回"
   * 的不变性验证。
   */
  async pushMemeCollect(device: TiebaDevice, session: TiebaSession, pics: string,
    picUpdateTimeMs: number): Promise<MemeCollectResponse> {
    const response: MemeCollectResponse = new MemeCollectResponse();
    if (!session.hasBduss()) {
      response.failLocal('需要登录后才能管理收藏表情');
      return response;
    }
    if (session.tbs.length === 0) {
      response.failLocal('缺少 tbs，无法提交收藏表情');
      return response;
    }
    const deviceError: string = TiebaApi.checkDevice(device);
    if (deviceError.length > 0) {
      response.failLocal(deviceError);
      return response;
    }
    if (pics.length === 0) {
      response.failLocal('pics 为空串：全量推送要么给 JSON 数组、要么给 all_delete');
      return response;
    }
    this.client.userAgent = `bdtb for Android ${device.clientVersion}`;
    const params: SignParam[] = MemeEmojiParams.buildCollect(device, session, pics, picUpdateTimeMs);
    const text: string | undefined = await this.postJsonText(
      MemeEmojiParams.COLLECT_PATH, params, response);

    if (text !== undefined) {
      response.ok = true;
    }
    hilog.info(0x0000, 'TiebaApi',
      'meme result: path=%{public}s op=collect picsLen=%{public}d'
        + ' responded=%{public}s ok=%{public}s errorCode=%{public}s errorMsg=%{public}s',
      MemeEmojiParams.COLLECT_PATH, pics.length, String(text !== undefined), String(response.ok),
      String(response.errorCode), response.errorMessage);
    return response;
  }

  /** 发表回复或楼层评论，使用 protobuf /c/c/post/add?cmd=309731。 */
  async replyToThread(device: TiebaDevice, session: TiebaSession, tid: number, fid: number,
    forumName: string, content: string, target?: AddPostTarget, withTail?: boolean): Promise<ReplyResponse> {
    const response: ReplyResponse = new ReplyResponse();
    const text: string = content.trim();
    if (withTail !== undefined && typeof withTail !== 'boolean') {
      response.failLocal('小尾巴附加选项无效'); return response;
    }

    if (tid <= 0) {
      response.failLocal('帖子 id 无效');
      return response;
    }
    if (fid <= 0) {
      response.failLocal('吧 id 无效，无法发表回复');
      return response;
    }
    if (forumName.length === 0) {
      response.failLocal('吧名缺失，无法发表回复');
      return response;
    }
    if (text.length === 0) {
      response.failLocal('回复内容为空');
      return response;
    }
    if (!session.hasBduss()) {
      response.failLocal('需要登录后才能发表回复');
      return response;
    }
    if (session.tbs.length === 0) {
      response.failLocal('缺少 tbs，无法发表回复');
      return response;
    }
    const check: string = TiebaApi.checkDevice(device);
    if (check.length > 0) {
      response.failLocal(check);
      return response;
    }

    this.client.userAgent = `bdtb for Android ${device.clientVersion}`;
    const body: Uint8Array = AddPostParams.wrapMultipart(
      AddPostParams.buildRequest(text, String(fid), forumName, String(tid), device, session, target, undefined, withTail));
    const transport: HttpResult = await this.client.postBinary(
      AddPostParams.url(TiebaHost.APP), body, AddPostParams.headers(session));
    if (!transport.ok) {
      response.transportError = transport.error;
      return response;
    }

    const parsed: AddPostResult = AddPostResult.fromBytes(transport.bytes);
    response.result = parsed;
    if (!parsed.accepted()) {
      // 逐个字段从服务端来，缺 error 段时 errorCode 是哨兵 -1，同样按失败处理
      response.failBusiness(parsed.errorCode,
        parsed.errorMsg.length > 0 ? parsed.errorMsg : `服务端错误 ${parsed.errorCode}`);
      hilog.warn(0x0000, 'TiebaApi',
        'reply rejected tid=%{public}d errorCode=%{public}d msg=%{public}s',
        tid, parsed.errorCode, parsed.errorMsg);
      return response;
    }
    // 拿到 bytes 且 errorno=0 才算成功——必须显式置位，理由见方法注释
    response.ok = true;
    hilog.info(0x0000, 'TiebaApi',
      'reply accepted tid=%{public}d fid=%{public}d pid=%{public}d targetPid=%{public}s',
      tid, fid, parsed.pid, String(target !== undefined && target.postId.length > 0));
    return response;
  }
}
