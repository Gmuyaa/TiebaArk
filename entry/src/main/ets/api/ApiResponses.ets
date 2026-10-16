
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
import { DirectoryData } from '../model/PageDirectory';
import { PersonalizedThread } from '../model/PersonalizedFeed';
import { PrivacyMarks } from '../model/PrivacyMarks';
import { SearchPostPage } from '../model/SearchPost';
import { SignStats } from '../model/SignStats';
import { TailList } from '../model/Tails';
import { SubPostPage, ThreadDetail } from '../model/ThreadDetail';
import { ThreadListResult } from '../model/ThreadList';
import { UserProfileInfo } from '../model/UserProfile';
import { VideoFeedResult } from '../model/VideoFeed';

export class ThreadListResponse extends ApiResult {
  data: ThreadListResult = new ThreadListResult();
}

export class ThreadDetailResponse extends ApiResult {
  data: ThreadDetail = new ThreadDetail();
}

export class SubPostResponse extends ApiResult {
  data: SubPostPage = new SubPostPage();
}

export class StoredThreadsResponse extends ApiResult {
  data: StoredThread[] = [];
}

export class UserPostsResponse extends ApiResult {
  data: UserPostItem[] = [];

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

export class HotTopicsResponse extends ApiResult {
  data: HotTopicItem[] = [];
}

export class FollowForumsResponse extends ApiResult {
  data: FollowForumList = new FollowForumList();
}

export class SignForumResponse extends ApiResult {
  stats: SignStats = new SignStats();

  bonusPoint: string = '';

  alreadySigned: boolean = false;
}

export class TbsResponse extends ApiResult {

  tbs: string = '';

  isLogin: boolean = false;
}

export class AgreeResponse extends ApiResult {

  agreeScore: string = '';

  isFirstAgree: string = '';
}

export class StoreOpResponse extends ApiResult {
}

export class MemeEmojiResponse extends ApiResult {
  data: MemeEmojiData = new MemeEmojiData();
}

export class MemeCollectResponse extends ApiResult {
}

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

  hasMore: boolean = false;

  nextAgreeId: number = 0;

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
