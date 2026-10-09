import { Theme } from '../common/Theme';
import { loadWeiboEmojiAssets } from '../common/WeiboText';
import { parseWeiboText, WeiboRichToken } from '../common/WeiboRichTokens';
import { common } from '@kit.AbilityKit';

@Component
export struct WeiboRichTextView {
  @Prop @Watch('onTextChange') text: string = '';
  @Prop fontSize: number = 15;
  @Prop fontColor: ResourceColor = '#E6000000';
  @Prop lineHeight: number = 22;
  @Prop maxLines: number = 0;
  @Consume('weiboNavStack') weiboNavStack: NavPathStack;
  onTopicClick: (topic: string) => void = () => {};
  onMentionClick: (username: string) => void = () => {};
  onLinkClick?: (url: string) => void;
  @State tokens: WeiboRichToken[] = [];

  aboutToAppear(): void {
    loadWeiboEmojiAssets(this.getUIContext().getHostContext() as common.UIAbilityContext);
    this.onTextChange();
  }
  private onTextChange(): void { this.tokens = parseWeiboText(this.text); }
  private openUrl(url: string): void {
    if (!/^https?:\/\//i.test(url)) { return; }
    if (this.onLinkClick !== undefined) {
      this.onLinkClick(url);
    } else {
      this.weiboNavStack.pushPathByName('WeiboBrowser', url);
    }
  }

  build() {
    Text() {
      ForEach(this.tokens, (token: WeiboRichToken): void => {
        if (token.type === 'emoji' && token.emojiUrl !== undefined) {
          ImageSpan(token.emojiUrl).width(this.fontSize + 4).height(this.fontSize + 4)
            .verticalAlign(ImageSpanAlignment.CENTER)
        } else if (token.type === 'topic') {
          Span(token.text).fontColor(Theme.brand()).fontWeight(FontWeight.Medium)
            .onClick((): void => { this.onTopicClick(token.value ?? token.text); })
        } else if (token.type === 'mention') {
          Span(token.text).fontColor(Theme.brand()).fontWeight(FontWeight.Medium)
            .onClick((): void => { this.onMentionClick(token.value ?? token.text); })
        } else if (token.type === 'link') {
          Span(' 网页链接 ↗ ').fontColor(Theme.brand())
            .onClick((): void => { this.openUrl(token.value ?? token.text); })
        } else {
          Span(token.text).fontColor(this.fontColor)
        }
      }, (token: WeiboRichToken, idx: number): string => `${idx}_${token.text}`)
    }.fontSize(this.fontSize).fontColor(this.fontColor).lineHeight(this.lineHeight)
      .maxLines(this.maxLines > 0 ? this.maxLines : undefined)
      .textOverflow(this.maxLines > 0 ? { overflow: TextOverflow.Ellipsis } : undefined)
  }
}
