/** 无 Cookie 的官方公开话题数据：移动页元信息 + PC 热门/最新帖子流。 */
import { ApiResult } from './ApiResult';
import { HttpClient, HttpResult } from '../net/HttpClient';
import { decodeUtf8 } from '../utils/TextCodec';
import {
  HotTopicDetail, HotTopicDetailPage, RawHotTopicInfoResponse, RawHotTopicMobileArea, RawHotTopicThreadResponse,
  applyHotTopicSupplements, hotTopicErrorCode, hotTopicRequestError, parseHotTopicInfo, parseHotTopicThreads
} from '../model/HotTopicDetail';

export class HotTopicDetailResponse extends ApiResult {
  data: HotTopicDetailPage = new HotTopicDetailPage();
}

const TOPIC_ORIGIN: string = 'https://tieba.baidu.com';
const TOPIC_UA: string = 'Mozilla/5.0 (Linux; Android 14; HarmonyOS) AppleWebKit/537.36';

export class HotTopicDetailApi {
  private client: HttpClient = new HttpClient();

  async fetch(topicId: number, topicName: string, sort: number,
    page: number, lastId: string): Promise<HotTopicDetailResponse> {
    const response: HotTopicDetailResponse = new HotTopicDetailResponse();
    const parameterError: string = hotTopicRequestError(topicId, topicName, sort, page, lastId);
    if (parameterError.length > 0) { response.failLocal(parameterError); return response; }
    this.client.userAgent = TOPIC_UA;
    let detail: HotTopicDetail = new HotTopicDetail();
    let supplementAreas: RawHotTopicMobileArea[] | undefined = undefined;
    let requestName: string = topicName;
    if (page === 1) {
      const infoTransport: HttpResult = await this.client.get(`${TOPIC_ORIGIN}/c/f/hottopic/topicDetail?` +
        `topic_id=${topicId}&is_new=1&pn=1&rn=15&offset=0&last_id=0&is_share=1&_client_type=2`);
      if (!infoTransport.ok) { response.transportError = infoTransport.error; return response; }
      let info: RawHotTopicInfoResponse;
      try { info = JSON.parse(decodeUtf8(infoTransport.bytes)) as RawHotTopicInfoResponse; }
      catch (_) { response.failLocal('话题信息响应不是合法 JSON'); return response; }
      if (info === null || typeof info !== 'object' || Array.isArray(info)) {
        response.failLocal('话题信息响应格式无效'); return response;
      }
      const infoCode: number | undefined = hotTopicErrorCode(info.error_code);
      if (infoCode === undefined) { response.failLocal('话题信息响应缺少有效业务状态'); return response; }
      if (infoCode !== 0) {
        response.failBusiness(infoCode, typeof info.error_msg === 'string' ? info.error_msg : '话题信息读取失败');
        return response;
      }
      const parsedInfo: HotTopicDetail | undefined = parseHotTopicInfo(info.topic_info, topicId);
      if (parsedInfo === undefined) { response.failLocal('话题信息缺失或与当前话题不符'); return response; }
      detail = parsedInfo;
      requestName = detail.title;
      supplementAreas = info.area_card_list;
    }
    // 官方 PC 脚本以名称和 ID 一起查询；缺名称虽可能返回帖子，但 last_id 会退成 0。
    const cursor: string = page === 1 ? '0' : lastId;
    const url: string = `${TOPIC_ORIGIN}/hottopic/browse/getTopicRelateThread?` +
      `topic_name=${encodeURIComponent(requestName)}&page_no=${page}&last_id=${cursor}` +
      `&topic_id=${topicId}&sort_type=${sort}`;
    const transport: HttpResult = await this.client.get(url);
    if (!transport.ok) { response.transportError = transport.error; return response; }
    let envelope: RawHotTopicThreadResponse;
    try { envelope = JSON.parse(decodeUtf8(transport.bytes)) as RawHotTopicThreadResponse; }
    catch (_) { response.failLocal('话题帖子响应不是合法 JSON'); return response; }
    if (envelope === null || typeof envelope !== 'object' || Array.isArray(envelope)) {
      response.failLocal('话题帖子响应格式无效'); return response;
    }
    const code: number | undefined = hotTopicErrorCode(envelope.errno);
    if (code === undefined) { response.failLocal('话题帖子响应缺少有效业务状态'); return response; }
    if (code !== 0) {
      response.failBusiness(code, typeof envelope.errmsg === 'string' ? envelope.errmsg : '话题帖子读取失败');
      return response;
    }
    const parsed: HotTopicDetailPage | undefined = parseHotTopicThreads(envelope.data, page);
    if (parsed === undefined) { response.failLocal('话题帖子或分页信息无效，请重试'); return response; }
    applyHotTopicSupplements(parsed.items, supplementAreas);
    parsed.detail = detail;
    response.data = parsed;
    response.ok = true;
    return response;
  }
}
