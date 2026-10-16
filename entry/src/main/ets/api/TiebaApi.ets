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
import { SearchPostPage, searchScopeForum } from '../model/SearchPost';
import { parseSignStats } from '../model/SignStats';
import { TailChange, TailList, parseTailWrite, parseTails, tailChangeError } from '../model/Tails';
import { ReplySortType, SubPostPage, ThreadDetail } from '../model/ThreadDetail';
import { ThreadListResult } from '../model/ThreadList';
import { UserProfileInfo, parseProtoErrorno, parseSelfProfileProto, parseUserInfo } from '../model/UserProfile';
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
import { RawFrsPage } from './RawFrsPage';
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
  AvatarUploadResponse, CreateForumChallengeResponse
} from './ApiResponses';

export {
  ApiResult, ThreadListResponse, ThreadDetailResponse, SubPostResponse, StoredThreadsResponse,
  UserPostsResponse, PersonalizedFeedResponse, SearchPostResponse, ForumSearchResponse, HotTopicsResponse,
  FollowForumsResponse, SignForumResponse, TbsResponse, AgreeResponse, StoreOpResponse, MemeEmojiResponse,
  MemeCollectResponse, ReplyResponse, DirectoryResponse, PublicProfileResponse, AuthorBlockResponse,
  ForumMemberResponse, BawuTeamResponse, NotifyResponse, MessageSettingsResponse, PrivacyMarksResponse,
  AtCandidatesResponse, VoiceAudioResponse, ImageUploadChunkResponse, ImageWatermarkResponse,
  OfficialMessagesResponse, VideoFeedResponse, ForbiddenForumsResponse, ForumBlockResponse, TailsResponse,
  TailWriteResponse, AvatarUploadResponse, CreateForumChallengeResponse
};

const ERROR_OK: number = 0;

const ERROR_UNKNOWN: number = -2;

export const ERRNO_THREAD_DELETED: number = 4;

const BROWSER_UA: string = 'Mozilla/5.0 (Linux; Android 14; HarmonyOS) AppleWebKit/537.36';
const USERINFO_URL: string = 'https://tieba.baidu.com/f/user/json_userinfo';

interface ApiEnvelope {
  error_code?: number | string;
  error_msg?: string;
}

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

function valueOf(params: SignParam[], key: string): string {
  for (let i = 0; i < params.length; i++) {
    if (params[i].key === key) {
      return params[i].value;
    }
  }
  return '<missing>';
}

function briefValue(value: string): string {
  if (value.length === 0) {
    return '(empty)';
  }
  return `${value.length > 12 ? value.slice(0, 12) : value}…(len=${value.length})`;
}

interface TbsEnvelope {
  error_code?: number | string;
  error_msg?: string;
  anti?: LoginAnti;
  user?: LoginUser;
}
interface LoginAnti { tbs?: string; }
interface LoginUser { id?: number | string; }

interface SignForumUserInfo {
  sign_bonus_point?: string | number;
}

interface SignForumEnvelope {
  user_info?: SignForumUserInfo;
}

interface PassportInfoData {
  uid?: number;
  uname?: string;
  displayName?: string;

  portrait?: string;
}

interface PassportInfo {
  errorCode?: number;
  errorMsg?: string;
  data?: PassportInfoData;
}

export class TiebaApi {

  async fetchCreateForumChallenge(device: TiebaDevice, session: TiebaSession): Promise<CreateForumChallengeResponse> {
    const response: CreateForumChallengeResponse = new CreateForumChallengeResponse();
    if (!session.hasBduss()) { response.failLocal('登录后才能读取创建吧验证码'); return response; }
    const check: string = TiebaApi.checkDevice(device);
    if (check.length > 0) { response.failLocal(check); return response; }
    const userAgent: string = `bdtb for Android ${device.clientVersion}`;
    const signed: SignParam[] = await CryptoUtil.appendSign(CreateForumParams.challenge(device, session), SignSalt.APP);

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

    const startedMs: number = avatarUptimeMs();
    const transport: HttpResult = await this.client.postBinary(`https://${TiebaHost.APP}${AvatarUploadParams.PATH}`, body,
      { 'Content-Type': `multipart/form-data; boundary=${AvatarUploadParams.BOUNDARY}` });
    avatarTracePhase('upload-transport', traceId, startedMs,
      `ok=${transport.ok} code=${transport.code} body=${body.length} image=${bytes.length}`);
    if (!transport.ok) { response.transportError = transport.error; return response; }
    if (transport.code !== 200) { response.failLocal('头像上传HTTP结果未确认'); return response; }
    const rawBody: string = decodeUtf8(transport.bytes);
    response.data = parseAvatarUpload(rawBody);

    const message: string = response.data.message.length > 80
      ? response.data.message.substring(0, 80) : response.data.message;
    avatarTracePhase('upload-parse', traceId, startedMs,
      `code=${response.data.code} pending=${response.data.pendingReview()} len=${transport.bytes.length}`
        + ` msg=${message} ${avatarUploadEnvelopeShape(rawBody)}`);
    if (response.data.code === -1) { response.failLocal(response.data.message); return response; }

    if (!response.data.received()) { response.failBusiness(response.data.code, response.data.message); return response; }
    response.ok = true; return response;
  }

  async uploadImageChunk(device: TiebaDevice, session: TiebaSession, chunk: ImageUploadChunk): Promise<ImageUploadChunkResponse> {
    const response: ImageUploadChunkResponse = new ImageUploadChunkResponse();
    if (!session.hasBduss()) { response.failLocal('登录后才能上传图片'); return response; }
    const check: string = TiebaApi.checkDevice(device);
    const invalid: string = imageUploadChunkError(chunk);
    if (check.length > 0 || invalid.length > 0) { response.failLocal(check.length > 0 ? check : invalid); return response; }
    const userAgent: string = `bdtb for Android ${device.clientVersion}`;
    const finalChunk: boolean = chunk.finish();
    const params: SignParam[] = ImageUploadParams.build(device, session, chunk);

    const bytes: Uint8Array = chunk.bytes.slice();
    const signed: SignParam[] = await CryptoUtil.appendSign(params, SignSalt.APP);

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
    } catch (err) {  }
    if (!response.ok) { response.failLocal('消息设置提交结果未确认，请重新读取'); }
    return response;
  }

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

    async authorBlock(device: TiebaDevice, session: TiebaSession, uid: number,
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

    let envelope: ApiEnvelope;
    try {
      envelope = JSON.parse(text) as ApiEnvelope;
    } catch (err) {
      const e: Error = err as Error;
      out.failLocal(`响应不是合法 JSON：${e.message}`);
      return undefined;
    }

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

  private static checkDevice(device: TiebaDevice): string {
    if (!device.isUsable()) {
      return '设备身份不完整，无法构造请求';
    }
    return '';
  }

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

      if (parsed.errorCode !== 0 || parsed.data === undefined) {
        hilog.info(0x0000, 'TiebaApi', 'passport api: errorCode=%{public}d', parsed.errorCode);
        return;
      }
      if (profile.nickName.length === 0) {
        profile.nickName = parsed.data.displayName ?? parsed.data.uname ?? '';
      }
      if (profile.portrait.length === 0 && (parsed.data.portrait ?? '').length > 0) {

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

  async fetchForumHeadline(device: TiebaDevice, session: TiebaSession,
    forumName: string): Promise<ForumHeadlineResult> {
    const empty: ForumHeadlineResult = new ForumHeadlineResult();
    const name: string = forumName.trim();
    if (name.length === 0) {
      return empty;
    }

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

  /* 协议参考：lumina37/aiotieba（Unlicense）。 */
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

  /* 协议参考：lumina37/aiotieba（Unlicense）。 */
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

  async fetchUserPosts(device: TiebaDevice, session: TiebaSession, uid: number,
    isThread: number, page: number, pageSize: number): Promise<UserPostsResponse> {
    if (!session.hasBduss()) {
      const response: UserPostsResponse = new UserPostsResponse();
      response.failLocal('未登录，无法获取帖子列表');
      return response;
    }
    return this.fetchPublicUserPosts(device, session, uid, isThread, page, pageSize);
  }

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

  /* 协议参考：lumina37/aiotieba（Unlicense）。 */
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

      if (response.errorCode === 160002) {
        response.alreadySigned = true;
        response.ok = true;
        return response;
      }
      return response;
    }

    response.stats = parseSignStats(text);
    /* 协议参考：lumina37/aiotieba（Unlicense）。 */
    try {
      const parsed = JSON.parse(text) as SignForumEnvelope;
      if (parsed.user_info !== undefined && parsed.user_info.sign_bonus_point !== undefined) {
        response.bonusPoint = String(parsed.user_info.sign_bonus_point);
      }
    } catch {

    }

    response.ok = true;
    return response;
  }

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

  /* 协议参考：lumina37/aiotieba（Unlicense）。 */
  async fetchTbsWithBduss(bduss: string): Promise<TbsResponse> {
    const response: TbsResponse = new TbsResponse();
    if (bduss.length === 0) { response.failLocal('缺少 BDUSS'); return response; }
    /* 协议参考：lumina37/aiotieba（Unlicense）。 */

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

  /* 协议参考：lumina37/aiotieba（Unlicense）。 */
  async agreePost(device: TiebaDevice, session: TiebaSession, tid: number, pid: number,
    agree: boolean, objType: AgreeObjType = AgreeObjType.POST,
    forumId: number = 0): Promise<AgreeResponse> {
    const response: AgreeResponse = new AgreeResponse();

    if (tid <= 0) {
      response.failLocal('帖子 id 无效');
      return response;
    }

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

    const text: string | undefined = await this.postJsonText(
      AgreeParams.PATH, params, response, AgreeParams.HOST, headers);

    if (text === undefined) {

      hilog.info(0x0000, 'TiebaApi',
        'agree result: path=/c/c/agree/opAgree agree_type=2 op_type=%{public}s obj_type=%{public}s'
          + ' identity[%{public}s] responded=false ok=false errorCode=%{public}s errorMsg=%{public}s'
          + ' transportErr=%{public}s',
        agree ? '0' : '1', objTypeText, identityText, String(response.errorCode), response.errorMessage,
        response.transportError.length === 0 ? '(none)' : response.transportError);
      return response;
    }

    response.ok = true;

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
    } catch (_) {  }

    hilog.info(0x0000, 'TiebaApi',
      'agree result: path=/c/c/agree/opAgree agree_type=2 op_type=%{public}s obj_type=%{public}s'
        + ' identity[%{public}s] responded=true ok=true bodyBytes=%{public}s'
        + ' agreeScore=%{public}s isFirstAgree=%{public}s',
      agree ? '0' : '1', objTypeText, identityText, String(text.length),
      response.agreeScore, response.isFirstAgree);
    return response;
  }

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

      response.failBusiness(parsed.errorCode,
        parsed.errorMsg.length > 0 ? parsed.errorMsg : `服务端错误 ${parsed.errorCode}`);
      hilog.warn(0x0000, 'TiebaApi',
        'reply rejected tid=%{public}d errorCode=%{public}d msg=%{public}s',
        tid, parsed.errorCode, parsed.errorMsg);
      return response;
    }

    response.ok = true;
    hilog.info(0x0000, 'TiebaApi',
      'reply accepted tid=%{public}d fid=%{public}d pid=%{public}d targetPid=%{public}s',
      tid, fid, parsed.pid, String(target !== undefined && target.postId.length > 0));
    return response;
  }
}
