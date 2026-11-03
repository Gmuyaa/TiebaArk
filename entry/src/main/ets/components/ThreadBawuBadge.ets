interface ThreadBawuBadgeParams {
  text: string;
  textColor: ResourceColor;
  backgroundColor: ResourceColor;
  borderColor: ResourceColor;
}

/** 详情作者与一级回复共用吧务标签几何，调用方保留各自语义色板。 */
@Builder
export function ThreadBawuBadge($$: ThreadBawuBadgeParams) {
  Text($$.text)
    .fontSize(10)
    .fontColor($$.textColor)
    .backgroundColor($$.backgroundColor)
    .border({ width: 1, color: $$.borderColor })
    .borderRadius(5)
    .padding({ left: 5, right: 5, top: 2, bottom: 2 })
}
