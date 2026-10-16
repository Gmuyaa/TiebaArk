

export interface RawHotTopic {
  topic_id?: number | string;
  topic_name?: string;
  discuss_num?: number | string;
  long_pic_url?: string;
  tag?: number | string;
}

export interface RawHotTopicData {
  hot_topic_list?: RawHotTopic[];
}

export interface RawHotTopicResponse {
  error_code?: number | string;
  error_msg?: string;
  data?: RawHotTopicData;
}

export class HotTopicItem {
  id: number = 0;
  name: string = '';
  discussCount: number = 0;
  imageUrl: string = '';
  tag: number = 0;
}

function nonNegativeInteger(value: number | string | undefined): number {
  const n: number = typeof value === 'string' ? Number(value) : (value === undefined ? 0 : value);
  return Number.isFinite(n) && n >= 0 ? Math.trunc(n) : 0;
}

export function parseHotTopics(data: RawHotTopicData | undefined): HotTopicItem[] {
  const raw: RawHotTopic[] = data?.hot_topic_list ?? [];
  const items: HotTopicItem[] = [];
  for (const topic of raw) {
    const id: number = nonNegativeInteger(topic.topic_id);
    const name: string = typeof topic.topic_name === 'string' ? topic.topic_name.trim() : '';
    if (id === 0 || name.length === 0) {
      continue;
    }
    const item: HotTopicItem = new HotTopicItem();
    item.id = id;
    item.name = name;
    item.discussCount = nonNegativeInteger(topic.discuss_num);
    item.imageUrl = typeof topic.long_pic_url === 'string' &&
      topic.long_pic_url.startsWith('https://') ? topic.long_pic_url : '';
    item.tag = nonNegativeInteger(topic.tag);
    items.push(item);
  }
  return items;
}

export function hotTopicUrl(item: HotTopicItem): string {
  return `https://tieba.baidu.com/hottopic/browse/hottopic?topic_id=${item.id}` +
    `&topic_name=${encodeURIComponent(item.name)}`;
}

export function hotDiscussLabel(count: number): string {
  if (count < 10000) {
    return `${count} 讨论`;
  }
  const wan: number = Math.round(count / 1000) / 10;
  return `${wan}万讨论`;
}
