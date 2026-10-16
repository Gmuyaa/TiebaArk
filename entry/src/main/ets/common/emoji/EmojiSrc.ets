/** 在渲染边界将 rawfile://emoji 标识转换为 ArkUI 资源；模型层保持平台无关，其他 URL 原样透传。 */

/** model 层表情图源的内置协议前缀（与 model/ThreadDetail.ets 的 EMOJI_RAW_PREFIX 同值） */
const RAW_PROTOCOL: string = 'rawfile://';

/**
 * 表情图源翻译：`rawfile://emoji/x.png` → `$rawfile('emoji/x.png')`；
 * 其它（https / 空串）原样返回。返回类型 ResourceStr 兼容 Image /
 * ImageSpan / RichEditorController.addImageSpan 三类消费点。
 */
export function emojiSrc(src: string): ResourceStr {
  if (src.startsWith(RAW_PROTOCOL)) {
    return $rawfile(src.substring(RAW_PROTOCOL.length));
  }
  return src;
}
