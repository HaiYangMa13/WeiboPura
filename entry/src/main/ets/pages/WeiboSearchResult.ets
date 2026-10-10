import { WeiboPost, WeiboSearchCompositeResult, WeiboSearchType, WeiboUser } from '../model/WeiboModel';
import { WeiboService } from '../service/WeiboService';
import { WeiboAuthManager } from '../service/WeiboAuthManager';
import { withWeiboLike } from '../common/WeiboPostState';
import { EmptyView, ErrorView, LoadingView, ThreadCard, ThreadItemData, ThreadSharePayload } from '../components/CommonComponents';
import { ImmMaterial, Radius, Spacing, Theme, fs, isDarkMode } from '../common/Theme';
import { ShareUtil } from '../common/ShareUtil';
import { Haptic } from '../common/Haptic';
import { common } from '@kit.AbilityKit';
import { DividerShowType, HdsNavDestination, HdsNavDestinationTitleMode, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { WeiboPostDetailRouteParam } from './WeiboPostDetail';
import { WeiboUserProfileRouteParam } from './WeiboUserProfile';

export interface WeiboSearchResultRouteParam {
  query: string;
}

@Builder
export function WeiboSearchResultBuilder(): void {
  WeiboSearchResult()
}

@Component
export struct WeiboSearchResult {
  @State isDark: boolean = isDarkMode();
  @State query: string = '';
  @State searchInput: string = '';
  @State posts: WeiboPost[] = [];
  @State users: WeiboUser[] = [];
  @State highlightUser: WeiboUser | null = null;
  @State currentTab: number = 0;
  private readonly tabs: string[] = ['综合', '实时', '用户', '视频', '图片'];
  private readonly tabTypes: WeiboSearchType[] = [
    WeiboSearchType.All,
    WeiboSearchType.Realtime,
    WeiboSearchType.User,
    WeiboSearchType.Video,
    WeiboSearchType.Image
  ];
  @State loading: boolean = true;
  @State isRefreshing: boolean = false;
  @State isLoadingMore: boolean = false;
  @State hasMore: boolean = true;
  @State currentPage: number = 1;
  @State errorMessage: string = '';
  @State moreError: string = '';
  @State likingIds: string[] = [];
  private searchEpoch: number = 0;
  @StorageLink('weiboAuthTick') @Watch('onWeiboAuthTick') weiboAuthTick: number = 0;
  @StorageLink('fontScale') fontScale: number = 1.0;
  @StorageLink('weibo.status_bar_height') statusBarHeight: number = 0;
  @Consume('weiboNavStack') weiboNavStack: NavPathStack;
  private searchScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    setTimeout((): void => {
      this.loadRouteParam();
    }, 50);
  }

  private loadRouteParam(): void {
    const params: WeiboSearchResultRouteParam[] =
      this.weiboNavStack.getParamByName('WeiboSearchResult') as WeiboSearchResultRouteParam[];
    if (params !== undefined && params !== null && params.length > 0) {
      const routeParam: WeiboSearchResultRouteParam = params[params.length - 1];
      this.query = typeof routeParam.query === 'string' ? routeParam.query.trim() : '';
      this.searchInput = this.query;
    }
    if (this.query.length > 0) {
      this.executeSearch(this.query, 1, false);
    } else {
      this.loading = false;
    }
  }

  private onWeiboAuthTick(): void {
    this.searchEpoch++;
    this.posts = [];
    this.users = [];
    this.highlightUser = null;
    this.likingIds = [];
    this.isLoadingMore = false;
    this.isRefreshing = false;
    if (!WeiboAuthManager.getInstance().isSessionChanging() && this.query.length > 0) { this.executeSearch(this.query, 1, false); }
  }

  private switchTab(index: number): void {
    if (this.currentTab === index) {
      return;
    }
    this.currentTab = index;
    Haptic.light();
    this.posts = [];
    this.users = [];
    this.highlightUser = null;
    this.currentPage = 1;
    this.hasMore = true;
    this.errorMessage = '';
    this.moreError = '';
    if (this.query.length > 0) {
      this.executeSearch(this.query, 1, false);
    }
  }

  private isContentEmpty(): boolean {
    if (this.currentTab === 2) {
      return this.users.length === 0;
    }
    return this.posts.length === 0 && this.highlightUser === null;
  }

  private async toggleFollowUser(user: WeiboUser): Promise<void> {
    const nextFollowed: boolean = !user.following;
    try {
      Haptic.light();
      if (nextFollowed) {
        await WeiboService.getInstance().followUser(user.id);
      } else {
        await WeiboService.getInstance().unfollowUser(user.id);
      }
      user.following = nextFollowed;
      this.users = this.users.slice();
      if (this.highlightUser !== null && this.highlightUser.id === user.id) {
        this.highlightUser.following = nextFollowed;
      }
      this.getUIContext().getPromptAction().showToast({
        message: nextFollowed ? `已关注 @${user.screenName}` : `已取消关注 @${user.screenName}`
      });
    } catch (error) {
      const msg: string = (error as Error).message ?? '关注操作未完成';
      this.getUIContext().getPromptAction().showToast({ message: msg });
    }
  }

  private async executeSearch(query: string, page: number, isRefresh: boolean): Promise<void> {
    if (query.trim().length === 0) {
      return;
    }
    const epoch: number = page === 1 ? ++this.searchEpoch : this.searchEpoch;
    this.moreError = '';
    if (page === 1) {
      if (!isRefresh) {
        this.loading = true;
      }
      this.errorMessage = '';
    } else {
      this.isLoadingMore = true;
    }

    const type: WeiboSearchType = this.tabTypes[this.currentTab] ?? WeiboSearchType.All;

    try {
      if (type === WeiboSearchType.User) {
        const results: WeiboUser[] = await WeiboService.getInstance().fetchSearchUsers(query, page);
        if (epoch !== this.searchEpoch) { return; }
        if (page === 1) {
          this.users = results;
          this.currentPage = 1;
          this.hasMore = results.length > 0;
        } else {
          const added: WeiboUser[] = results.filter((item: WeiboUser): boolean =>
            !this.users.some((old: WeiboUser): boolean => old.id === item.id));
          if (added.length > 0) {
            this.users = this.users.concat(added);
            this.currentPage = page;
          } else {
            this.hasMore = false;
          }
        }
      } else {
        const composite: WeiboSearchCompositeResult =
          await WeiboService.getInstance().fetchSearchComposite(query, page, type);
        if (epoch !== this.searchEpoch) { return; }
        if (page === 1) {
          this.posts = composite.posts;
          this.highlightUser = composite.highlightUser;
          this.currentPage = 1;
          this.hasMore = composite.hasMore;
        } else {
          const added: WeiboPost[] = composite.posts.filter((item: WeiboPost): boolean =>
            !this.posts.some((old: WeiboPost): boolean => old.id === item.id));
          if (added.length > 0) {
            this.posts = this.posts.concat(added);
            this.currentPage = page;
          } else {
            this.hasMore = false;
          }
        }
      }
    } catch (error) {
      if (epoch !== this.searchEpoch) { return; }
      if (page === 1) {
        this.posts = [];
        this.users = [];
        this.highlightUser = null;
        this.errorMessage = (error as Error).message ?? '微博搜索加载失败，请稍后重试';
      } else {
        this.moreError = (error as Error).message ?? '加载下一页失败，请重试';
      }
    } finally {
      if (epoch === this.searchEpoch) {
        this.loading = false;
        this.isRefreshing = false;
        this.isLoadingMore = false;
        if (page === 1) {
          setTimeout((): void => {
            try {
              this.searchScroller.scrollEdge(Edge.Top);
            } catch (_e) {}
          }, 100);
        }
      }
    }
  }

  private loadMore(): void {
    if (this.loading || this.isLoadingMore || !this.hasMore || this.query.length === 0) {
      return;
    }
    this.executeSearch(this.query, this.currentPage + 1, false);
  }

  private popRoute(): void {
    this.weiboNavStack.pop();
  }

  private openPost(post: WeiboPost): void {
    if (post.id.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.weibo_post_unavailable') });
      return;
    }
    const param: WeiboPostDetailRouteParam = { postId: post.id };
    this.weiboNavStack.pushPath({ name: 'WeiboPostDetail', param: param });
  }

  private openOriginalPost(post: WeiboPost): void {
    const original: WeiboPost | null = post.repost;
    if (original === null || original.id.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.weibo_post_unavailable') });
      return;
    }
    this.openPost(original);
  }

  private openUserProfile(userId: string, userName: string): void {
    const id: string = typeof userId === 'string' ? userId.trim() : '';
    const name: string = typeof userName === 'string' ? userName.trim() : '';
    if (id.length === 0 && name.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.weibo_profile_unavailable') });
      return;
    }
    const param: WeiboUserProfileRouteParam = { userId: id, userName: name };
    this.weiboNavStack.pushPath({ name: 'WeiboUserProfile', param: param });
  }

  private openImagePreview(urls: string[], index: number, post: WeiboPost): void {
    if (urls.length === 0) {
      return;
    }
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/ImagePreview',
      params: { urls: urls, index: index, pictureVideos: (post.pictures.length > 0 ? post : post.repost)?.pictureVideos ?? {} }
    }).catch((): void => {
      this.getUIContext().getPromptAction().showToast({ message: '原图预览打开失败，请稍后重试' });
    });
  }

  private openTopic(topic: string): void {
    const param: WeiboSearchResultRouteParam = { query: topic };
    this.weiboNavStack.pushPath({ name: 'WeiboSearchResult', param: param });
  }

  private async togglePostLike(post: WeiboPost): Promise<void> {
    if (this.likingIds.includes(post.id)) { return; }
    const revision: number = WeiboAuthManager.getInstance().getSessionRevision();
    this.likingIds = this.likingIds.concat([post.id]);
    try {
      await WeiboService.getInstance().setLike(post.id, !post.isLiked);
      WeiboAuthManager.getInstance().assertSession(revision);
      const updated: WeiboPost = withWeiboLike(post, !post.isLiked);
      this.posts = this.posts.map((item: WeiboPost): WeiboPost => item.id === post.id ? updated : item);
      Haptic.light();
    } catch (error) {
      if (revision === WeiboAuthManager.getInstance().getSessionRevision()) {
        this.getUIContext().getPromptAction().showToast({ message: (error as Error).message ?? '点赞失败，请重试' });
      }
    } finally {
      if (revision === WeiboAuthManager.getInstance().getSessionRevision()) {
        this.likingIds = this.likingIds.filter((id: string): boolean => id !== post.id);
      }
    }
  }

  private onShare(data: ThreadSharePayload): void {
    const url: string = `https://m.weibo.cn/detail/${data.tid}`;
    const abstract: string = data.abstract.length > 0 ? data.abstract : data.title;
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    ShareUtil.shareLink(this.getUIContext(), context, url, data.author, abstract);
  }

  private toThreadCard(post: WeiboPost): ThreadItemData {
    const original: WeiboPost | null = post.repost;
    const mediaPost: WeiboPost = (post.pictures.length > 0 || post.videoUrl.length > 0 || original === null)
      ? post : original;
    const firstImage: string = mediaPost.pictures.length > 0 ? mediaPost.pictures[0] : '';
    const titleText: string = post.text.length > 0 ? post.text : post.userName;
    return {
      tid: post.id,
      postId: post.id,
      forumId: '',
      title: titleText,
      forumName: post.source.length > 0 ? post.source : '微博',
      forumAvatar: '',
      author: post.userName,
      authorId: post.userId,
      authorAvatar: post.userAvatar,
      replyNum: post.commentCount,
      likeCount: post.likeCount,
      isLiked: post.isLiked,
      abstract: original === null ? '' : original.text,
      repostAuthor: original === null ? '' : original.userName,
      isSocialPost: true,
      firstImage: firstImage,
      images: mediaPost.pictures,
      videoUrl: mediaPost.videoUrl,
      videoCoverUrl: mediaPost.videoCoverUrl,
      videoAspectRatio: mediaPost.videoAspectRatio,
      createTime: post.createdAt,
      isTop: false,
      isGood: false,
    };
  }

  @Builder
  HighlightUserCard(user: WeiboUser) {
    Row({ space: Spacing.md }) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        if (user.avatarUrl.length > 0) {
          Image(user.avatarUrl)
            .width(44)
            .height(44)
            .borderRadius(Radius.full)
            .objectFit(ImageFit.Cover)
            .backgroundColor(Theme.bgSubCard(this.isDark))
        } else {
          Stack() {
            Text(user.screenName.length > 0 ? user.screenName.substring(0, 1) : '微')
              .fontSize(fs(18, this.fontScale))
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
          }
          .width(44)
          .height(44)
          .borderRadius(Radius.full)
          .backgroundColor(Theme.brand())
          .alignContent(Alignment.Center)
        }
        if (user.verified) {
          Text('V')
            .fontSize(8)
            .fontWeight(FontWeight.Bolder)
            .fontColor(Color.White)
            .backgroundColor(user.verifiedReason.includes('官方') ? '#3880E8' : '#E8A838')
            .borderRadius(Radius.full)
            .width(13)
            .height(13)
            .textAlign(TextAlign.Center)
            .border({ width: 1.5, color: Theme.bgCard(this.isDark) })
            .offset({ x: 2, y: 2 })
        }
      }
      .width(44)
      .height(44)

      Column({ space: 2 }) {
        Row({ space: Spacing.xs }) {
          Text(user.screenName)
            .fontSize(fs(14, this.fontScale))
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.textPrimary(this.isDark))
          if (user.verifiedReason.length > 0) {
            Text(user.verifiedReason)
              .fontSize(fs(11, this.fontScale))
              .fontColor(user.verifiedReason.includes('官方') ? '#7BA8FF' : '#E8A838')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .width('100%')

        if (user.followersCount.length > 0 || user.statusesCount > 0) {
          Text(`粉丝 ${user.followersCount}${user.statusesCount > 0 ? ` · 微博 ${user.statusesCount}` : ''}`)
            .fontSize(fs(11, this.fontScale))
            .fontColor(Theme.textTertiary(this.isDark))
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Button(user.following ? '已关注' : '+ 关注')
        .height(28)
        .fontSize(fs(11.5, this.fontScale))
        .fontWeight(user.following ? FontWeight.Normal : FontWeight.Bold)
        .fontColor(user.following ? Theme.textSecondary(this.isDark) : Color.White)
        .backgroundColor(user.following ? Theme.bgSubCard(this.isDark) : Theme.brand())
        .borderRadius(Radius.full)
        .padding({ left: 10, right: 10 })
        .onClick((): void => {
          this.toggleFollowUser(user);
        })
    }
    .width('100%')
    .padding(Spacing.md)
    .backgroundColor(Theme.bgCard(this.isDark))
    .borderRadius(Radius.lg)
    .border({ width: 0.5, color: Theme.cardBorder(this.isDark) })
    .onClick((): void => {
      this.openUserProfile(user.id, user.screenName);
    })
  }

  @Builder
  UserListItem(user: WeiboUser) {
    Row({ space: Spacing.md }) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        if (user.avatarUrl.length > 0) {
          Image(user.avatarUrl)
            .width(48)
            .height(48)
            .borderRadius(Radius.full)
            .objectFit(ImageFit.Cover)
            .backgroundColor(Theme.bgSubCard(this.isDark))
        } else {
          Stack() {
            Text(user.screenName.length > 0 ? user.screenName.substring(0, 1) : '微')
              .fontSize(fs(20, this.fontScale))
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
          }
          .width(48)
          .height(48)
          .borderRadius(Radius.full)
          .backgroundColor(Theme.brand())
          .alignContent(Alignment.Center)
        }
        if (user.verified) {
          Text('V')
            .fontSize(9)
            .fontWeight(FontWeight.Bolder)
            .fontColor(Color.White)
            .backgroundColor(user.verifiedReason.includes('官方') ? '#3880E8' : '#E8A838')
            .borderRadius(Radius.full)
            .width(14)
            .height(14)
            .textAlign(TextAlign.Center)
            .border({ width: 1.5, color: Theme.bgCard(this.isDark) })
            .offset({ x: 2, y: 2 })
        }
      }
      .width(48)
      .height(48)

      Column({ space: 3 }) {
        Row({ space: Spacing.xs }) {
          Text(user.screenName)
            .fontSize(fs(14.5, this.fontScale))
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.textPrimary(this.isDark))
          if (user.verifiedReason.length > 0) {
            Text(user.verifiedReason)
              .fontSize(fs(11, this.fontScale))
              .fontColor(user.verifiedReason.includes('官方') ? '#7BA8FF' : '#E8A838')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .width('100%')

        if (user.description.length > 0) {
          Text(user.description)
            .fontSize(fs(12, this.fontScale))
            .fontColor(Theme.textSecondary(this.isDark))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }

        Row({ space: Spacing.md }) {
          if (user.followersCount.length > 0) {
            Text(`粉丝 ${user.followersCount}`)
              .fontSize(fs(11, this.fontScale))
              .fontColor(Theme.textTertiary(this.isDark))
          }
          if (user.statusesCount > 0) {
            Text(`微博 ${user.statusesCount}`)
              .fontSize(fs(11, this.fontScale))
              .fontColor(Theme.textTertiary(this.isDark))
          }
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Button(user.following ? '已关注' : '+ 关注')
        .height(30)
        .fontSize(fs(12, this.fontScale))
        .fontWeight(user.following ? FontWeight.Normal : FontWeight.Bold)
        .fontColor(user.following ? Theme.textSecondary(this.isDark) : Color.White)
        .backgroundColor(user.following ? Theme.bgSubCard(this.isDark) : Theme.brand())
        .borderRadius(Radius.full)
        .padding({ left: 12, right: 12 })
        .onClick((): void => {
          this.toggleFollowUser(user);
        })
    }
    .width('100%')
    .padding(Spacing.md)
    .backgroundColor(Theme.bgCard(this.isDark))
    .borderRadius(Radius.lg)
    .border({ width: 0.5, color: Theme.cardBorder(this.isDark) })
    .onClick((): void => {
      this.openUserProfile(user.id, user.screenName);
    })
  }

  @Builder
  SearchTitleBar() {
    Column() {
      Row({ space: Spacing.sm }) {
        Button() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(fs(28, this.fontScale))
            .fontColor([$r('sys.color.icon_primary')])
        }
        .width(44)
        .height(44)
        .backgroundColor(Color.Transparent)
        .systemMaterial(ImmMaterial.control())
        .borderRadius(Radius.full)
        .accessibilityText($r('app.string.weibo_back'))
        .onClick((): void => { this.popRoute(); })

        Search({
          value: this.searchInput,
          placeholder: $r('app.string.weibo_search_placeholder')
        })
          .layoutWeight(1)
          .height(38)
          .backgroundColor(Color.Transparent)
          .fontColor(Theme.textPrimary(this.isDark))
          .systemMaterial(ImmMaterial.seg(false))
          .borderRadius(Radius.full)
          .clip(true)
          .onChange((value: string): void => {
            this.searchInput = value;
          })
          .onSubmit((value: string): void => {
            const trimmed: string = value.trim();
            if (trimmed.length > 0) {
              this.query = trimmed;
              this.executeSearch(trimmed, 1, false);
            }
          })

        Button() {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(fs(20, this.fontScale))
            .fontColor([Theme.brand()])
        }
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .borderRadius(Radius.full)
        .onClick((): void => {
          const trimmed: string = this.searchInput.trim();
          if (trimmed.length > 0) {
            this.query = trimmed;
            this.executeSearch(trimmed, 1, false);
          }
        })
      }
      .width('100%')
      .height(56)
      .padding({ left: Spacing.sm, right: Spacing.md })

      Scroll() {
        Row({ space: Spacing.xs }) {
          ForEach(this.tabs, (tab: string, index: number): void => {
            Button(tab)
              .height(28)
              .padding({ left: 12, right: 12 })
              .fontSize(fs(12.5, this.fontScale))
              .fontColor(this.currentTab === index ? Color.White : Theme.textSecondary(this.isDark))
              .fontWeight(this.currentTab === index ? FontWeight.Medium : FontWeight.Normal)
              .backgroundColor(this.currentTab === index ? Theme.brand() : Color.Transparent)
              .borderRadius(Radius.full)
              .onClick((): void => {
                this.switchTab(index);
              })
          }, (tab: string): string => tab)
        }
        .padding({ left: Spacing.sm, right: Spacing.sm, bottom: 6 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
    }
  }

  @Builder
  SearchContent() {
    Refresh({ refreshing: $$this.isRefreshing, promptText: '正在刷新…' }) {
      Scroll(this.searchScroller) {
        Column({ space: Spacing.sm }) {
          if (this.loading) {
            LoadingView({ message: $r('app.string.weibo_loading') })
              .height(360)
          } else if (this.errorMessage.length > 0) {
            ErrorView({
              message: this.errorMessage,
              onRetry: (): void => { this.executeSearch(this.query, 1, false); }
            })
              .height(360)
          } else if (this.isContentEmpty()) {
            EmptyView({ message: $r('app.string.weibo_search_empty'), icon: '⌕' })
              .height(360)
          } else {
            if (this.currentTab === 1) {
              Row() {
                Text('按发布时间倒序排列')
                  .fontSize(fs(11, this.fontScale))
                  .fontColor(Theme.textTertiary(this.isDark))
              }
              .width('100%')
              .padding({ left: 4, bottom: 2 })
            }

            if (this.currentTab === 0 && this.highlightUser !== null) {
              this.HighlightUserCard(this.highlightUser)
            }

            if (this.currentTab === 2) {
              ForEach(this.users, (user: WeiboUser): void => {
                this.UserListItem(user)
              }, (user: WeiboUser): string => `${user.id}:${user.following}`)
            } else {
              ForEach(this.posts, (post: WeiboPost): void => {
                ThreadCard({
                  item: this.toThreadCard(post),
                  onTap: (_id: string): void => { this.openPost(post); },
                  onAbstractTap: (): void => { this.openOriginalPost(post); },
                  abstractIsLink: post.repost !== null,
                  onComment: (_id: string): void => { this.openPost(post); },
                  onAvatarTap: (id: string, name: string): void => { this.openUserProfile(id, name); },
                  onTopicTap: (topic: string): void => { this.openTopic(topic); },
                  onMentionTap: (name: string): void => { this.openUserProfile('', name); },
                  onLike: (_id: string): void => { this.togglePostLike(post); },
                  onImageTap: (urls: string[], index: number): void => { this.openImagePreview(urls, index, post); },
                  onShare: (payload: ThreadSharePayload): void => { this.onShare(payload); },
                  skipImageCache: true,
                })
              }, (post: WeiboPost): string => post.id)
            }

            if (this.moreError.length > 0) {
              Text(this.moreError).fontSize(fs(13, this.fontScale)).fontColor(Theme.danger())
              Button('重试加载更多').height(44).onClick((): void => { this.loadMore(); })
            }
            if (this.isLoadingMore) {
              Row({ space: Spacing.sm }) {
                LoadingProgress().width(20).height(20)
                Text('正在加载更多…')
                  .fontSize(fs(12, this.fontScale))
                  .fontColor(Theme.textTertiary(this.isDark))
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
              .padding({ top: Spacing.md, bottom: Spacing.md })
            } else if (!this.hasMore && !this.isContentEmpty()) {
              Text('已加载全部内容')
                .width('100%')
                .fontSize(fs(12, this.fontScale))
                .fontColor(Theme.textTertiary(this.isDark))
                .textAlign(TextAlign.Center)
                .padding({ top: Spacing.md, bottom: Spacing.md })
            }
          }
        }
        .width('100%')
        .padding({
          left: Spacing.lg,
          right: Spacing.lg,
          top: this.statusBarHeight + 100,
          bottom: Spacing.xl
        })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .onScrollEdge((edge: Edge): void => {
        if (edge === Edge.Bottom) {
          this.loadMore();
        }
      })
    }
    .onRefreshing((): void => {
      Haptic.light();
      this.executeSearch(this.query, 1, true);
    })
    .width('100%')
    .height('100%')
  }

  build() {
    HdsNavDestination() {
      this.SearchContent()
    }
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .hideBackButton(true)
    .onBackPressed((): boolean => {
      this.popRoute();
      return true;
    })
    .bindToScrollable([this.searchScroller])
    .titleBar({
      avoidLayoutSafeArea: true,
      content: {
        stackBuilder: (): void => this.SearchTitleBar(),
        divider: { showType: DividerShowType.OFF }
      },
      style: {
        scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.GRADIENT_BLUR },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.EXQUISITE
        }
      }
    })
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg(this.isDark))
  }
}
