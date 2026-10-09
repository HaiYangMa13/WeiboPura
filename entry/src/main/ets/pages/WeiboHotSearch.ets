import { WeiboHotTopic } from '../model/WeiboModel';
import { curves } from '@kit.ArkUI';
import { WeiboService } from '../service/WeiboService';
import { ImmBlur, ImmMaterial, Radius, Spacing, Theme, fs, isDarkMode } from '../common/Theme';
import { EmptyView, ErrorView, LoadingView } from '../components/CommonComponents';
import { Haptic } from '../common/Haptic';

enum HotLoadState {
  Idle = 0,
  Loading = 1,
  Success = 2,
  Error = 3,
}

type TabAnimationDirection = 'left' | 'right';

/** Public Weibo hot-search board; no account cookie or visitor-session creation is needed. */
@Component
export struct WeiboHotSearch {
  pageScroller: Scroller = new Scroller();
  @Prop topInset: number = 64;
  @StorageLink('weibo.status_bar_height') statusBarHeight: number = 0;
  @Prop @Watch('onEnter') animationTrigger: number = 0;
  @Prop exitTrigger: number = 0;
  onSelectTopic: (topic: WeiboHotTopic) => void = () => {};
  onScrollDirection: (visible: boolean) => void = () => {};
  @State searchKeyword: string = '';
  @State isDark: boolean = isDarkMode();
  @State isRefreshing: boolean = false;
  @State state: HotLoadState = HotLoadState.Idle;
  @State topics: WeiboHotTopic[] = [];
  @State errorMessage: string = '';
  @StorageLink('fontScale') fontScale: number = 1.0;
  @StorageLink('darkTick') @Watch('onDarkTick') darkTick: number = 0;

  aboutToAppear(): void {
    this.loadTopics();
  }

  private onDarkTick(): void {
    this.isDark = isDarkMode();
  }

  private onEnter(): void {
    if (this.topics.length === 0 || this.state === HotLoadState.Error) {
      this.loadTopics();
    }
  }

  private async loadTopics(isRefresh: boolean = false): Promise<void> {
    if (!isRefresh) {
      this.state = HotLoadState.Loading;
    }
    this.errorMessage = '';
    try {
      const result: WeiboHotTopic[] = await WeiboService.getInstance().fetchHotTopics(30);
      this.topics = result;
      this.state = HotLoadState.Success;
    } catch (error) {
      if (!isRefresh || this.topics.length === 0) {
        this.topics = [];
        this.errorMessage = (error as Error).message ?? '微博热搜加载失败，请稍后重试';
        this.state = HotLoadState.Error;
      }
    } finally {
      this.isRefreshing = false;
      if (isRefresh) {
        setTimeout((): void => {
          try {
            this.pageScroller.scrollEdge(Edge.Top);
          } catch (_e) {}
        }, 100);
      }
    }
  }

  private formatHeat(heat: number): string {
    if (heat <= 0) {
      return '';
    }
    if (heat >= 100000000) {
      return `${(heat / 100000000).toFixed(1)}亿`;
    }
    if (heat >= 10000) {
      return `${(heat / 10000).toFixed(1)}万`;
    }
    return `${heat}`;
  }

  private labelBgColor(label: string): ResourceColor {
    if (label === '爆' || label === '热' || label === '沸') {
      return Theme.brand();
    }
    if (label === '新') {
      return '#FFF58220';
    }
    if (label === '荐' || label === '商') {
      return '#FF2E75B6';
    }
    return Theme.brand();
  }

  @Builder
  TopicRow(topic: WeiboHotTopic, isLast: boolean = false) {
    Row({ space: Spacing.md }) {
      Text(`${topic.rank}`)
        .width(26)
        .fontSize(fs(15, this.fontScale))
        .fontWeight(topic.rank <= 3 ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(topic.rank === 1 ? Theme.brand() : (topic.rank === 2 ? '#FFF58220' : (topic.rank === 3 ? '#FFEDB322' : Theme.textSecondary(this.isDark))))
        .textAlign(TextAlign.Center)
      Column({ space: 4 }) {
        Row({ space: Spacing.sm }) {
          Text(topic.word)
            .fontSize(fs(15, this.fontScale))
            .fontColor(Theme.textPrimary(this.isDark))
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (topic.label.length > 0) {
            Text(topic.label)
              .fontSize(fs(10, this.fontScale))
              .fontColor(Color.White)
              .fontWeight(FontWeight.Bold)
              .backgroundColor(this.labelBgColor(topic.label))
              .borderRadius(4)
              .padding({ left: 5, right: 5, top: 1, bottom: 1 })
          }
        }
        .width('100%')
        if (topic.heat > 0) {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.flame'))
              .fontSize(fs(11, this.fontScale))
              .fontColor([Theme.textTertiary(this.isDark)])
            Text(this.formatHeat(topic.heat))
              .fontSize(fs(11, this.fontScale))
              .fontColor(Theme.textTertiary(this.isDark))
          }
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(fs(14, this.fontScale))
        .fontColor([Theme.textTertiary(this.isDark)])
    }
    .width('100%')
    .padding({ left: Spacing.lg, right: Spacing.lg, top: 12, bottom: 12 })
    .border(isLast ? { width: 0 } : { width: { bottom: 0.5 }, color: Theme.manualGlassBorder() })
    .onClick((): void => {
      this.onSelectTopic(topic);
    })
  }

  build() {
    Refresh({ refreshing: $$this.isRefreshing, promptText: '正在刷新…' }) {
      Scroll(this.pageScroller) {
        Column({ space: Spacing.md }) {
          // 顶部快捷搜索栏 (对齐原型第二页顶部搜索交互)
          Row({ space: Spacing.sm }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(fs(18, this.fontScale))
              .fontColor([Theme.textTertiary(this.isDark)])
            TextInput({ placeholder: '搜索微博、话题、用户', text: this.searchKeyword })
              .layoutWeight(1)
              .height(40)
              .backgroundColor(Color.Transparent)
              .fontSize(fs(14, this.fontScale))
              .fontColor(Theme.textPrimary(this.isDark))
              .placeholderColor(Theme.textTertiary(this.isDark))
              .onChange((val: string) => { this.searchKeyword = val; })
              .onSubmit(() => {
                if (this.searchKeyword.trim().length > 0) {
                  const customTopic: WeiboHotTopic = {
                    rank: 0,
                    word: this.searchKeyword.trim(),
                    heat: 0,
                    label: '',
                    query: this.searchKeyword.trim()
                  };
                  this.onSelectTopic(customTopic);
                }
              })
            if (this.searchKeyword.length > 0) {
              Button() {
                SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
                  .fontSize(fs(16, this.fontScale))
                  .fontColor([Theme.textTertiary(this.isDark)])
              }
              .width(28)
              .height(28)
              .backgroundColor(Color.Transparent)
              .onClick(() => { this.searchKeyword = ''; })
            }
          }
          .width('calc(100% - 32vp)')
          .height(46)
          .margin({ left: Spacing.lg, right: Spacing.lg })
          .padding({ left: Spacing.md, right: Spacing.md })
          .backgroundColor(Theme.bgCard(this.isDark))
          .borderRadius(Radius.full)
          .border({ width: 0.5, color: Theme.cardBorder(this.isDark) })
          .shadow(Theme.feedCardShadow(this.isDark))

          if (this.state === HotLoadState.Loading) {
            LoadingView({ message: $r('app.string.weibo_loading') })
              .height(360)
          } else if (this.state === HotLoadState.Error) {
            ErrorView({ message: this.errorMessage, onRetry: (): void => { this.loadTopics(false); } })
              .height(360)
          } else if (this.state === HotLoadState.Success && this.topics.length === 0) {
            EmptyView({ message: $r('app.string.weibo_hot_empty'), icon: '○' })
              .height(360)
          } else if (this.state === HotLoadState.Success) {
            Column() {
              Row() {
                Row({ space: 6 }) {
                  SymbolGlyph($r('sys.symbol.flame_fill'))
                    .fontSize(fs(16, this.fontScale))
                    .fontColor([Theme.brand()])
                  Text('实时热搜榜')
                    .fontSize(fs(15, this.fontScale))
                    .fontWeight(FontWeight.Bold)
                    .fontColor(Theme.textPrimary(this.isDark))
                  Text('实时')
                    .fontSize(fs(10, this.fontScale))
                    .fontWeight(FontWeight.Bold)
                    .fontColor(Color.White)
                    .backgroundColor(Theme.brand())
                    .borderRadius(Radius.full)
                    .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                }
              }
              .width('100%')
              .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.md, bottom: Spacing.sm })
              .border({ width: { bottom: 0.5 }, color: Theme.manualGlassBorder() })

              ForEach(this.topics, (topic: WeiboHotTopic, index: number): void => {
                this.TopicRow(topic, index === this.topics.length - 1)
              }, (topic: WeiboHotTopic): string => `${topic.rank}_${topic.word}`)
            }
            .width('100%')
            .backgroundColor(Theme.bgCard(this.isDark))
            .borderRadius({ topLeft: Radius.postCard, topRight: Radius.postCard })
            .shadow(Theme.glassShadowStyle())
          } else {
            EmptyView({ message: $r('app.string.weibo_hot_empty'), icon: '○' })
              .height(360)
          }
        }
        .width('100%')
        .padding({ top: Math.max(this.topInset, this.statusBarHeight + 10), bottom: 120 })
      }
      .width('100%')
      .height('100%')
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .onDidScroll((xOffset: number, yOffset: number, scrollState: ScrollState): void => {
        if (scrollState !== ScrollState.Scroll) { return; }
        if (this.pageScroller.currentOffset().yOffset <= 0) {
          this.onScrollDirection(true);
          return;
        }
        if (yOffset > 8) { this.onScrollDirection(false); }
        else if (yOffset < -8) { this.onScrollDirection(true); }
      })
    }
    .onRefreshing((): void => {
      Haptic.light();
      this.loadTopics(true);
    })
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .backgroundColor(Theme.bg(this.isDark))
  }
}
