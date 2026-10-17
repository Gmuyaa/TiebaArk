/** 各接口的响应类型；请求和传输实现见 TiebaApi。 */
import { ApiResult } from './ApiResult';
import { AddPostResult } from '../model/AddPostResult';
import { AtCandidates } from '../model/AtCandidates';
import { AuthorBlockResult } from '../model/AuthorBlock';
import { AvatarUploadResult } from '../model/AvatarUpload';
import { CreateForumChallenge } from '../model/CreateForum';
import { FollowForumList } from '../model/FollowForum';
import { ForbiddenForums } from '../model/ForbiddenForums';
import { ForumMemberGroup } from '../model/ForumMember';
import { ForumSearchPage } from '../model/ForumSearch';
import { HotTopicItem } from '../model/HotTopic';
import { ImageUploadResult } from '../model/ImageUpload';
import { ImageWatermark } from '../model/ImageWatermark';
import { MemeEmojiData } from '../model/MemeEmoji';
import { MessageSettings } from '../model/MessageSettings';
import { StoredThread, UserPostItem } from '../model/MyContent';
import { NotifyItem } from '../model/Notify';
import { OfficialMessageSettings } from '../model/OfficialMessages';
import { OfficialSignResult, OfficialSignCapability } from '../model/OfficialSign';
import { DirectoryData } from '../model/PageDirectory';
import { PersonalizedThread } from '../model/PersonalizedFeed';
import { PrivacyMarks } from '../model/PrivacyMarks';
import { SearchPostPage } from '../model/SearchPost';
import { SignStats } from '../model/SignStats';
import { TailList } from '../model/Tails';
import { SubPostPage, ThreadDetail } from '../model/ThreadDetail';
import { ThreadListResult } from '../model/ThreadList';
import { UserProfileInfo } from '../model/UserProfile';
import { UserSearchPage } from '../model/UserSearch';
import { VideoFeedResult } from '../model/VideoFeed';

/** 拉取主题列表的结果 */
export class ThreadListResponse extends ApiResult {
  data: ThreadListResult = new ThreadListResult();
}

/** 拉取帖子详情的结果 */
export class ThreadDetailResponse extends ApiResult {
  data: ThreadDetail = new ThreadDetail();
}

/** 拉取楼中楼的结果 */
export class SubPostResponse extends ApiResult {
  data: SubPostPage = new SubPostPage();
}

export class StoredThreadsResponse extends ApiResult {
  data: StoredThread[] = [];
}

export class UserPostsResponse extends ApiResult {
  data: UserPostItem[] = [];
  /** userpost 没有显式分页标记；非空页允许探测下一页，列表在空页或重复页停止。 */
  hasMore: boolean = false;
}

export class PersonalizedFeedResponse extends ApiResult {
  data: PersonalizedThread[] = [];
}

export class SearchPostResponse extends ApiResult {
  data: SearchPostPage = new SearchPostPage();
}

export class ForumSearchResponse extends ApiResult {
  data: ForumSearchPage = new ForumSearchPage();
}

/** 公开网页搜人结果，无登录要求。 */
export class UserSearchResponse extends ApiResult {
  data: UserSearchPage = new UserSearchPage();
}

/** 网页首页热议话题榜（公开数据，无账号要求）。 */
export class HotTopicsResponse extends ApiResult {
  data: HotTopicItem[] = [];
}

export class FollowForumsResponse extends ApiResult {
  data: FollowForumList = new FollowForumList();
}

/** 吧签到的结果（`/c/c/forum/sign`）。bonusPoint 用于"签到成功 +N 经验"提示 */
export class SignForumResponse extends ApiResult {
  stats: SignStats = new SignStats();
  /** 签到奖励经验值；响应缺 user_info.sign_bonus_point 时为空串 */
  bonusPoint: string = '';
  /** 重复签到以业务码 160002 判断，不依赖可能过期的列表 is_sign。 */
  alreadySigned: boolean = false;
}

export class OfficialSignResponse extends ApiResult {
  data: OfficialSignResult = new OfficialSignResult();
}
export class OfficialSignCapabilityResponse extends ApiResult {
  data: OfficialSignCapability = new OfficialSignCapability();
}

/**
 * 拉取 tbs 的结果。
 *
 * HTTPS APP `/c/s/login` 返回 `anti.tbs` 与 `user.id`。
 * `isLogin` 由响应校验得出，用于判断当前凭据是否有效。
 */
export class TbsResponse extends ApiResult {
  /** 写操作令牌；未取到为空串 */
  tbs: string = '';
  /** 服务端是否认可当前凭据 */
  isLogin: boolean = false;
}

/** 一级回复点赞的结果。写接口没有数据体，只需要成败与原因 */
export class AgreeResponse extends ApiResult {
  /** data.agree.score 仅作诊断，不能替代写后读取 has_agree 与 agree_num。 */
  agreeScore: string = '';
  /** `data.agree.is_first_agree`：`"1"`=首次点赞, `"0"`=非首次 */
  isFirstAgree: string = '';
}

/** 收藏与取消收藏接口的业务结果。 */
export class StoreOpResponse extends ApiResult {
}

export class MemeEmojiResponse extends ApiResult {
  data: MemeEmojiData = new MemeEmojiData();
}

/** 收藏表情全量推送（`/c/e/meme/collect`）的结果。写端点没有数据体 */
export class MemeCollectResponse extends ApiResult {
}

/** 回复回执包含新楼层 pid，可用于重新读取详情确认发布结果。 */
export class ReplyResponse extends ApiResult {
  result: AddPostResult = new AddPostResult();
}

export class DirectoryResponse extends ApiResult {
  data: DirectoryData = new DirectoryData();
}

export class PublicProfileResponse extends ApiResult {
  data: UserProfileInfo = new UserProfileInfo();
}

export class AuthorBlockResponse extends ApiResult {
  result: AuthorBlockResult = new AuthorBlockResult();
}

export class ForumMemberResponse extends ApiResult {
  groups: ForumMemberGroup[] = [];
}

export class BawuTeamResponse extends ApiResult {
  total: number = 0;
  roles: ForumMemberGroup[] = [];
}

export class NotifyResponse extends ApiResult {
  page: number = 0;
  items: NotifyItem[] = [];
  /** reply：是否还有下一页 */
  hasMore: boolean = false;
  /** agree：下一页游标（0 = 无） */
  nextAgreeId: number = 0;
  /** agree：服务端是否声明还有更多 */
  agreeHasMore: boolean = false;
}

export class MessageSettingsResponse extends ApiResult {
  data: MessageSettings = new MessageSettings();
}

export class PrivacyMarksResponse extends ApiResult {
  data: PrivacyMarks = new PrivacyMarks();
}

export class AtCandidatesResponse extends ApiResult {
  data: AtCandidates = new AtCandidates();
}
export class VoiceAudioResponse extends ApiResult {
  bytes: Uint8Array = new Uint8Array(0);
}
export class ImageUploadChunkResponse extends ApiResult {
  data: ImageUploadResult = new ImageUploadResult();
}
export class ImageWatermarkResponse extends ApiResult {
  data: ImageWatermark = new ImageWatermark();
}
export class OfficialMessagesResponse extends ApiResult {
  data: OfficialMessageSettings = new OfficialMessageSettings();
}
export class VideoFeedResponse extends ApiResult {
  data: VideoFeedResult = new VideoFeedResult();
}

export class ForbiddenForumsResponse extends ApiResult {
  data: ForbiddenForums = new ForbiddenForums();
}

/**
 * 「屏蔽吧」写入结果。
 *
 * `confirmed` 是**读回核对**的结论：`false` 表示这次反馈提交没有得到服务端确认
 * （列表里没有该吧），此时 `ok` 也是 `false` —— 界面据此退回本机屏蔽并如实说明。
 */
export class ForumBlockResponse extends ApiResult {
  confirmed: boolean = false;
}

export class TailsResponse extends ApiResult {
  data: TailList = new TailList();
}

export class TailWriteResponse extends ApiResult {
  id: string = '';
}

export class AvatarUploadResponse extends ApiResult {
  data: AvatarUploadResult = new AvatarUploadResult();
}

export class CreateForumChallengeResponse extends ApiResult {
  data: CreateForumChallenge = new CreateForumChallenge();
}
