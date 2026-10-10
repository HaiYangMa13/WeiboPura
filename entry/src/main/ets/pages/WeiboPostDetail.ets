import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { curves, window } from '@kit.ArkUI';
import { WeiboComment, WeiboCommentSort, WeiboPost, WeiboUser } from '../model/WeiboModel';
import { WeiboAuthManager } from '../service/WeiboAuthManager';
import { WeiboService } from '../service/WeiboService';
import { ImmBlur, ImmMaterial, MaterialManager, Radius, Spacing, Theme, fs, isDarkMode } from '../common/Theme';
import { ShareUtil } from '../common/ShareUtil';
import { Haptic } from '../common/Haptic';
import { WeiboVideoPlayer } from '../components/WeiboVideoPlayer';
import { DividerShowType, HdsNavDestination, HdsNavDestinationTitleMode, HdsTabs, HdsTabsController, HdsTabsModifier, HdsAnimationMode, hdsMaterial, ScrollEffectType } from '@kit.UIDesignKit';
import { createWeiboDockStyle } from '../common/WeiboDockStyle';
import { DEFAULT_HOME_TAB_MATERIAL_LEVEL } from '../service/AppSettingsStore';
import { deviceInfo } from '@kit.BasicServicesKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { harmonyShare, systemShare } from '@kit.ShareKit';
import { syncWeiboSplitNavigation } from '../common/WeiboNavigationLayout';
import { WeiboRichTextView } from '../components/WeiboRichTextView';
import { WeiboSearchResultRouteParam } from './WeiboSearchResult';
import { WeiboUserProfileRouteParam } from './WeiboUserProfile';
import { WeiboComposeDialog } from '../components/WeiboComposeDialog';
import { WeiboEmojiPanel } from '../components/WeiboEmojiPanel';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { CommentComposerScrollState } from '../common/CommentComposerScrollState';
import { getWeiboEmoji, loadWeiboEmojiAssets } from '../common/WeiboText';

/**
 * Routed post detail. It deliberately owns its scroll, comments, and bottom
 * composer so a timeline card never expands in place.
 */
export interface WeiboPostDetailRouteParam {
  postId: string;
}

// Pass an object literal so PostBody observes replacement of the post state.
interface PostBodyParams {
  post: WeiboPost;
}

interface CommentLikeMutation {
  liked: boolean;
  version: number;
}

interface QuickReactionEmoji {
  char: string;
  token: string;
  name: string;
}

const QUICK_REACTION_EMOJIS: QuickReactionEmoji[] = [
  { char: '😆', token: '😆', name: '哈哈' },
  { char: '😮', token: '😮', name: '吃惊' },
  { char: '🥺', token: '🥺', name: '委屈' },
  { char: '😭', token: '😭', name: '大哭' },
  { char: '😋', token: '😋', name: '馋' },
  { char: '😚', token: '😚', name: '亲亲' },
  { char: '🙂', token: '🙂', name: '微笑' },
  { char: '🥴', token: '🥴', name: '晕' },
  { char: '😍', token: '😍', name: '色' }
];

@Builder
export function WeiboPostDetailBuilder(): void {
  WeiboPostDetail()
}

@Component
export struct WeiboPostDetail {
  @State isDark: boolean = isDarkMode();
  @State postId: string = '';
  @State post: WeiboPost | null = null;
  @State comments: WeiboComment[] = [];
  @State @Watch('syncComposerDockVisibility') loading: boolean = true;
  @State commentsLoading: boolean = false;
  @State commentsPage: number = 1;
  @State commentsSort: WeiboCommentSort = WeiboCommentSort.Hot;
  @State commentsNextMaxId: string = '0';
  @State commentsError: string = '';
  @State commentsNoProgressPages: number = 0;
  private commentsEpoch: number = 0;
  @State hasMoreComments: boolean = true;
  @State loadingMoreComments: boolean = false;
  @State replyTargetComment: WeiboComment | null = null;
  @State expandedReplyIds: string[] = [];
  @State replyLoadingIds: string[] = [];
  private replyCursors: Map<string, string> = new Map();
  private replyEpochs: Map<string, number> = new Map();
  @State errorMessage: string = '';
  @State longTextLoading: boolean = false;
  @State favoriting: boolean = false;
  @State liking: boolean = false;
  @State commentLikingIds: string[] = [];
  private commentLikeVersion: number = 0;
  private commentLikeMutations: Map<string, CommentLikeMutation> = new Map();
  @State commentDraft: string = '';
  @State @Watch('syncComposerDockVisibility') commentComposerHidden: boolean = false;
  @State @Watch('syncComposerDockVisibility') commentEditorOpen: boolean = false;
  private composerTabsController: HdsTabsController = new HdsTabsController();
  @State composerTabsModifier: HdsTabsModifier = new HdsTabsModifier();
  @StorageLink('homeTabMaterialLevel') @Watch('configureComposerDock')
  homeTabMaterialLevel: number = DEFAULT_HOME_TAB_MATERIAL_LEVEL;
  @StorageLink('appAccentColor') @Watch('configureComposerDock') accentColor: string = '#4EAA78';
  private commentInputFocused: boolean = false;
  private commentEditorController: TextAreaController = new TextAreaController();
  private commentSelectionStart: number = 0;
  private commentSelectionEnd: number = 0;
  @State quickCommentEmojis: string[] = [];
  private composerScrollState: CommentComposerScrollState = new CommentComposerScrollState();
  private commentsSectionTop: number = Number.POSITIVE_INFINITY;
  private detailViewportBottom: number = 0;
  @State commentSending: boolean = false;
  @State commentImage: string = '';
  @State pickingCommentImage: boolean = false;
  @State showCommentEmoji: boolean = false;
  @State commentUploadHint: string = '';
  private commentPictureId: string = '';
  private commentPictureCookie: string = '';
  @State accountAvatarUrl: string = '';
  @State accountName: string = '';
  /** One-shot entrance for the post and conversation after data becomes available. */
  @State contentOpacity: number = 0;
  @State contentTranslateY: number = 18;
  @State contentScale: number = 0.985;
  @StorageLink('fontScale') fontScale: number = 1.0;
  @StorageLink('weibo.status_bar_height') statusBarHeight: number = 0;
  @StorageLink('weibo.navigation_indicator_height') navigationIndicatorHeight: number = 0;
  @StorageProp('keyboardHeight') keyboardHeight: number = 0;
  @StorageLink('weiboAuthTick') @Watch('onWeiboAuthTick') weiboAuthTick: number = 0;
  @Consume('weiboNavStack') weiboNavStack: NavPathStack;
  private detailScroller: Scroller = new Scroller();
  private videoController: VideoController = new VideoController();
  private gestureShareListening: boolean = false;
  private gestureSharing: boolean = false;
  private gestureSharePreviewPostId: string = '';
  private gestureSharePreviewUri: string = '';
  private gestureSharePreviewContentKey: string = '';
  private gesturesShareCallback: (target: harmonyShare.SharableTarget) => void =
    (target: harmonyShare.SharableTarget): void => {
      this.sharePostByGesture(target);
    };
  @State videoLoadFailed: boolean = false;

  async aboutToAppear(): Promise<void> {
    this.configureComposerDock();
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    await WeiboAuthManager.getInstance().init(context);
    loadWeiboEmojiAssets(context);
    this.quickCommentEmojis = ['笑cry', '微笑', '泪', '害羞', '亲亲', '哈哈', '可爱']
      .filter((name: string): boolean => getWeiboEmoji(name) !== undefined);
    await this.loadCurrentAccountProfile();
    this.registerGesturesShare();
    try {
      const win: window.Window | undefined = AppStorage.get<window.Window>('mainWindow');
      if (win !== undefined) {
        win.on('keyboardHeightChange', (heightPx: number): void => {
          this.keyboardHeight = this.getUIContext().px2vp(heightPx);
        });
      }
    } catch (_err) {
    }
    setTimeout((): void => {
      this.loadRoutePost();
    }, 50);
  }

  aboutToDisappear(): void {
    this.closeCommentEditor();
    this.commentsEpoch++;
    this.unregisterGesturesShare();
    try {
      const win: window.Window | undefined = AppStorage.get<window.Window>('mainWindow');
      if (win !== undefined) {
        win.off('keyboardHeightChange');
      }
    } catch (_err) {
    }
  }

  /** HDS destinations receive their argument from the shared NavPathStack. */
  private async loadRoutePost(): Promise<void> {
    const params: WeiboPostDetailRouteParam[] =
      this.weiboNavStack.getParamByName('WeiboPostDetail') as WeiboPostDetailRouteParam[];
    if (params === undefined || params === null || params.length === 0) {
      this.loading = false;
      this.errorMessage = '该微博信息暂不可用';
      return;
    }
    const routeParam: WeiboPostDetailRouteParam = params[params.length - 1];
    this.postId = routeParam.postId;
    if (this.postId.length === 0) {
      this.loading = false;
      this.errorMessage = '该微博信息暂不可用';
      return;
    }
    const cached: WeiboPost | null = WeiboService.getInstance().getRememberedPost(this.postId);
    if (cached !== null) {
      this.post = cached;
      this.loading = false;
      this.presentPostContent();
      await this.prepareGestureSharePreview();
      await this.loadComments();
      if (cached.isLongText) {
        this.expandLongText();
      }
      return;
    }
    await this.loadPost();
  }

  private onWeiboAuthTick(): void {
    this.commentsEpoch++;
    this.commentEditorOpen = false;
    this.commentInputFocused = false;
    this.setComposerVisible(true);
    this.commentsError = '';
    this.commentsNextMaxId = '0';
    this.commentPictureId = '';
    this.commentImage = '';
    this.commentDraft = '';
    this.replyTargetComment = null;
    this.commentSending = false;
    this.pickingCommentImage = false;
    this.commentUploadHint = '';
    this.showCommentEmoji = false;
    this.post = null;
    this.comments = [];
    this.accountAvatarUrl = '';
    this.accountName = '';
    this.commentsLoading = false;
    this.loadingMoreComments = false;
    this.longTextLoading = false;
    this.liking = false;
    this.favoriting = false;
    this.commentLikingIds = [];
    this.commentLikeVersion = 0;
    this.commentLikeMutations.clear();
    this.replyLoadingIds = [];
    this.replyCursors.clear();
    this.replyEpochs.clear();
    this.commentsNoProgressPages = 0;
    if (!WeiboAuthManager.getInstance().isSessionChanging()) {
      this.loadCurrentAccountProfile();
      if (this.postId.length > 0) { this.loadPost(); }
    }
  }

  private isCurrentSession(revision: number): boolean {
    const auth: WeiboAuthManager = WeiboAuthManager.getInstance();
    return revision === auth.getSessionRevision() && !auth.isSessionChanging();
  }

  /** The reply capsule shows the actual account avatar represented by the saved Cookie. */
  private async loadCurrentAccountProfile(): Promise<void> {
    const revision: number = WeiboAuthManager.getInstance().getSessionRevision();
    if (!WeiboAuthManager.getInstance().hasCookie()) {
      this.accountAvatarUrl = '';
      this.accountName = '';
      return;
    }
    try {
      const account: WeiboUser = await WeiboService.getInstance().fetchCurrentUserProfile();
      if (!this.isCurrentSession(revision)) { return; }
      this.accountAvatarUrl = account.avatarUrl;
      this.accountName = account.screenName;
    } catch (error) {
      if (!this.isCurrentSession(revision)) { return; }
      this.accountAvatarUrl = '';
      this.accountName = '';
    }
  }

  private async loadPost(): Promise<void> {
    const revision: number = WeiboAuthManager.getInstance().getSessionRevision();
    this.loading = true;
    this.errorMessage = '';
    this.contentOpacity = 0;
    this.contentTranslateY = 18;
    this.contentScale = 0.985;
    try {
      const post: WeiboPost = await WeiboService.getInstance().fetchPost(this.postId);
      if (!this.isCurrentSession(revision)) { return; }
      this.post = post;
      this.presentPostContent();
      await this.prepareGestureSharePreview();
      if (!this.isCurrentSession(revision)) { return; }
      await this.loadComments();
      if (this.post !== null && this.post.isLongText) {
        this.expandLongText();
      }
    } catch (error) {
      if (!this.isCurrentSession(revision)) { return; }
      this.errorMessage = (error as Error).message ?? '帖子详情加载失败，请稍后重试';
    } finally {
      if (this.isCurrentSession(revision)) { this.loading = false; }
    }
  }

  private presentPostContent(): void {
    this.getUIContext().animateTo({ curve: curves.interpolatingSpring(0, 1, 360, 34) }, (): void => {
      this.contentOpacity = 1;
      this.contentTranslateY = 0;
      this.contentScale = 1;
    });
  }

  private popRoute(): void {
    this.weiboNavStack.pop();
    syncWeiboSplitNavigation(this.weiboNavStack);
  }

  private openSearchTopic(topic: string): void {
    const trimmed: string = topic.trim();
    if (trimmed.length === 0) {
      return;
    }
    const param: WeiboSearchResultRouteParam = { query: trimmed };
    this.weiboNavStack.pushPath({ name: 'WeiboSearchResult', param: param });
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

  private openOriginalPost(original: WeiboPost): void {
    if (original.id.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.weibo_post_unavailable') });
      return;
    }
    const service: WeiboService = WeiboService.getInstance();
    service.rememberPost(original);
    service.prefetchComments(original.id);
    const param: WeiboPostDetailRouteParam = { postId: original.id };
    this.weiboNavStack.pushPath({ name: 'WeiboPostDetail', param: param });
  }

  private copyPostWithText(source: WeiboPost, text: string): WeiboPost {
    return {
      id: source.id,
      userId: source.userId,
      userName: source.userName,
      userAvatar: source.userAvatar,
      text: text,
      isLongText: false,
      pictures: source.pictures,
      pictureVideos: source.pictureVideos,
      videoAspectRatio: source.videoAspectRatio,
      isFavorited: source.isFavorited, isFollowed: source.isFollowed,
      videoUrl: source.videoUrl,
      videoCoverUrl: source.videoCoverUrl,
      createdAt: source.createdAt,
      source: source.source,
      likeCount: source.likeCount,
      commentCount: source.commentCount,
      repostCount: source.repostCount,
      isLiked: source.isLiked,
      repost: source.repost,
    };
  }

  private async expandLongText(): Promise<void> {
    const source: WeiboPost | null = this.post;
    hilog.info(0x0001, 'FluoLongText', 'enter id=%{public}s pending=%{public}s busy=%{public}s chars=%{public}d',
      source?.id ?? '', source?.isLongText ?? false, this.longTextLoading, source?.text.length ?? 0);
    if (source === null || !source.isLongText || this.longTextLoading) {
      return;
    }
    const revision: number = WeiboAuthManager.getInstance().getSessionRevision();
    this.longTextLoading = true;
    try {
      const text: string = await WeiboService.getInstance().fetchLongText(source.id);
      if (!this.isCurrentSession(revision)) { return; }
      if (this.post !== null && this.post.id === source.id) {
        const updated: WeiboPost = this.copyPostWithText(this.post, text);
        this.post = updated;
        hilog.info(0x0001, 'FluoLongText', 'applied id=%{public}s before=%{public}d after=%{public}d',
          source.id, source.text.length, updated.text.length);
        WeiboService.getInstance().rememberPost(updated);
        await this.prepareGestureSharePreview();
      }
    } catch (error) {
      const message: string = (error as Error).message ?? '全文加载失败，请稍后重试';
      this.getUIContext().getPromptAction().showToast({ message: message });
    } finally {
      if (this.isCurrentSession(revision)) { this.longTextLoading = false; }
    }
  }

  private isCurrentCommentRequest(epoch: number, revision: number): boolean {
    return epoch === this.commentsEpoch && this.isCurrentSession(revision);
  }

  private switchCommentSort(sort: WeiboCommentSort): void {
    if (this.commentsSort === sort) { return; }
    this.commentsSort = sort;
    this.comments = [];
    this.commentsPage = 1;
    this.commentsNextMaxId = '0';
    this.expandedReplyIds = [];
    this.replyLoadingIds = [];
    this.replyCursors.clear();
    Haptic.light();
    this.loadComments(true);
  }

  private async loadComments(force: boolean = false): Promise<void> {
    if (this.postId.length === 0 || (this.commentsLoading && !force)) { return; }
    const epoch: number = ++this.commentsEpoch;
    const revision: number = WeiboAuthManager.getInstance().getSessionRevision();
    const sort: WeiboCommentSort = this.commentsSort;
    const readLikeVersion: number = this.commentLikeVersion;
    this.commentsLoading = true;
    this.loadingMoreComments = false;
    this.commentsNoProgressPages = 0;
    this.replyEpochs.clear();
    this.commentsError = '';
    try {
      const page = await WeiboService.getInstance().fetchComments(this.postId, 1, sort);
      if (!this.isCurrentCommentRequest(epoch, revision)) { return; }
      this.applyConcurrentCommentLikes(page.items, readLikeVersion);
      this.comments = page.items;
      this.commentsPage = 1;
      this.commentsNextMaxId = page.nextMaxId;
      this.hasMoreComments = page.hasMore;
      this.expandedReplyIds = [];
      this.replyLoadingIds = [];
      this.replyCursors.clear();
    } catch (error) {
      if (!this.isCurrentCommentRequest(epoch, revision)) { return; }
      this.commentsError = (error as Error).message ?? '评论加载失败，请重试';
    } finally {
      if (this.isCurrentCommentRequest(epoch, revision)) { this.commentsLoading = false; }
    }
  }

  private async loadMoreComments(automatic: boolean = false): Promise<void> {
    if (this.commentsLoading || this.loadingMoreComments || !this.hasMoreComments || this.commentsNextMaxId === '0'
      || (automatic && this.commentsNoProgressPages >= 3)) { return; }
    const epoch: number = this.commentsEpoch;
    const revision: number = WeiboAuthManager.getInstance().getSessionRevision();
    const sort: WeiboCommentSort = this.commentsSort;
    const readLikeVersion: number = this.commentLikeVersion;
    const nextPage: number = this.commentsPage + 1;
    this.loadingMoreComments = true;
    try {
      const page = await WeiboService.getInstance().fetchComments(this.postId, nextPage, sort, this.commentsNextMaxId);
      if (!this.isCurrentCommentRequest(epoch, revision)) { return; }
      this.applyConcurrentCommentLikes(page.items, readLikeVersion);
      const added: WeiboComment[] = page.items.filter((item: WeiboComment): boolean =>
        !this.comments.some((existing: WeiboComment): boolean => existing.id === item.id));
      this.comments = this.comments.concat(added);
      this.commentsPage = nextPage;
      this.commentsNextMaxId = page.nextMaxId;
      this.hasMoreComments = page.hasMore;
      this.commentsNoProgressPages = added.length === 0 ? this.commentsNoProgressPages + 1 : 0;
    } catch (error) {
      if (!this.isCurrentCommentRequest(epoch, revision)) { return; }
      this.getUIContext().getPromptAction().showToast({ message: (error as Error).message ?? '评论加载失败，请重试' });
    } finally {
      if (this.isCurrentCommentRequest(epoch, revision)) { this.loadingMoreComments = false; }
    }
  }

  private configureComposerDock(): void {
    const modifier: HdsTabsModifier = new HdsTabsModifier();
    modifier.vertical(false).barPosition(BarPosition.End).barHeight(56)
      .barFloatingStyle(createWeiboDockStyle(this.homeTabMaterialLevel, this.accentColor, 400));
    this.composerTabsModifier = modifier;
  }

  private syncComposerDockVisibility(): void {
    if (this.loading || this.commentComposerHidden || this.commentEditorOpen || this.post === null) {
      this.composerTabsController.applyHideAnimation(HdsAnimationMode.SCROLL_ANIMATION);
    } else {
      this.composerTabsController.applyShowAnimation(HdsAnimationMode.SCROLL_ANIMATION);
    }
  }

  private setComposerVisible(visible: boolean): void {
    if (visible) { this.composerScrollState.reset(); }
    if (this.commentComposerHidden === !visible) { return; }
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, (): void => {
      this.commentComposerHidden = !visible;
    });
  }

  private onDetailScroll(yOffset: number, state: ScrollState): void {
    if (state !== ScrollState.Scroll && state !== ScrollState.Fling) { return; }
    const visible: boolean = this.detailScroller.currentOffset().yOffset + this.detailViewportBottom >= this.commentsSectionTop;
    const editing: boolean = this.commentEditorOpen || this.commentInputFocused || this.pickingCommentImage || this.commentSending || this.showCommentEmoji;
    const hidden: boolean = this.composerScrollState.update(yOffset, visible, editing);
    if (this.commentComposerHidden !== hidden) { this.setComposerVisible(!hidden); }
  }

  private openCommentEditor(): void {
    if (this.commentSending) { return; }
    this.setComposerVisible(true);
    this.commentSelectionStart = this.commentDraft.length;
    this.commentSelectionEnd = this.commentDraft.length;
    this.commentEditorOpen = true;
  }

  private closeCommentEditor(): void {
    this.commentEditorOpen = false;
    this.showCommentEmoji = false;
    this.commentInputFocused = false;
    this.replyTargetComment = null;
    try {
      this.commentEditorController.stopEditing();
    } catch (_error) {
    }
    this.setComposerVisible(true);
  }

  private focusCommentEditor(): void {
    setTimeout((): void => {
      if (!this.commentEditorOpen || this.commentSending || this.pickingCommentImage || this.showCommentEmoji) { return; }
      this.getUIContext().getFocusController().requestFocus(`weibo-comment-editor-${this.postId}`);
      this.commentEditorController.caretPosition(this.commentSelectionEnd);
    }, 120);
  }

  private insertCommentToken(token: string): void {
    if (this.commentSending) { return; }
    const start: number = Math.max(0, Math.min(this.commentSelectionStart, this.commentDraft.length));
    const end: number = Math.max(start, Math.min(this.commentSelectionEnd, this.commentDraft.length));
    this.commentDraft = this.commentDraft.substring(0, start) + token + this.commentDraft.substring(end);
    this.commentSelectionStart = start + token.length;
    this.commentSelectionEnd = this.commentSelectionStart;
    const caret: number = this.commentSelectionEnd;
    setTimeout((): void => {
      if (this.commentEditorOpen && !this.commentSending) { this.commentEditorController.caretPosition(caret); }
    }, 0);
  }

  private toggleCommentEmoji(): void {
    if (!this.commentEditorOpen) { this.openCommentEditor(); }
    this.showCommentEmoji = !this.showCommentEmoji;
    if (this.showCommentEmoji) { this.commentEditorController.stopEditing(); }
    else { this.focusCommentEditor(); }
  }

  private cancelCommentReply(): void {
    if (this.commentSending || this.pickingCommentImage) { return; }
    this.replyTargetComment = null;
    this.focusCommentEditor();
  }

  private beginCommentReply(comment: WeiboComment): void {
    this.replyTargetComment = comment;
    this.openCommentEditor();
  }

  private reconcileCommentLike(items: WeiboComment[], id: string, liked: boolean): void {
    for (const item of items) {
      if (item.id === id && item.isLiked !== liked) {
        item.isLiked = liked;
        item.likeCount = Math.max(0, item.likeCount + (liked ? 1 : -1));
      }
      if (item.replies !== undefined) { this.reconcileCommentLike(item.replies, id, liked); }
    }
  }

  private applyConcurrentCommentLikes(items: WeiboComment[], readVersion: number): void {
    this.commentLikeMutations.forEach((mutation: CommentLikeMutation, id: string): void => {
      // Only override reads that began before this acknowledged write. Later reads
      // remain authoritative, including changes from another device.
      if (mutation.version > readVersion) { this.reconcileCommentLike(items, id, mutation.liked); }
    });
  }

  private async toggleCommentLike(comment: WeiboComment): Promise<void> {
    if (this.commentLikingIds.includes(comment.id)) { return; }
    const revision: number = WeiboAuthManager.getInstance().getSessionRevision();
    const liked: boolean = !comment.isLiked;
    this.commentLikingIds = this.commentLikingIds.concat([comment.id]);
    try {
      await WeiboService.getInstance().setCommentLike(comment.id, liked);
      if (!this.isCurrentSession(revision)) { return; }
      this.commentLikeMutations.set(comment.id, { liked: liked, version: ++this.commentLikeVersion });
      this.reconcileCommentLike(this.comments, comment.id, liked);
      WeiboService.getInstance().invalidateComments(this.postId);
      this.comments = this.comments.slice();
      Haptic.light();
    } catch (error) {
      if (!this.isCurrentSession(revision)) { return; }
      this.getUIContext().getPromptAction().showToast({ message: (error as Error).message ?? '点赞失败' });
    } finally {
      if (this.isCurrentSession(revision)) { this.commentLikingIds = this.commentLikingIds.filter((id: string): boolean => id !== comment.id); }
    }
  }

  private collapseReplies(commentId: string): void {
    this.replyEpochs.set(commentId, (this.replyEpochs.get(commentId) ?? 0) + 1);
    this.expandedReplyIds = this.expandedReplyIds.filter((id: string): boolean => id !== commentId);
    this.replyLoadingIds = this.replyLoadingIds.filter((id: string): boolean => id !== commentId);
    this.replyCursors.delete(commentId);
  }

  private isCurrentReplyRequest(epoch: number, revision: number, commentId: string, threadEpoch: number): boolean {
    return this.isCurrentCommentRequest(epoch, revision) && this.replyEpochs.get(commentId) === threadEpoch;
  }

  private async loadReplies(comment: WeiboComment): Promise<void> {
    if (this.replyLoadingIds.includes(comment.id)) {
      return;
    }
    const cursor: string | undefined = this.replyCursors.get(comment.id);
    if (cursor === '0') {
      return;
    }
    const revision: number = WeiboAuthManager.getInstance().getSessionRevision();
    const epoch: number = this.commentsEpoch;
    const threadEpoch: number = (this.replyEpochs.get(comment.id) ?? 0) + 1;
    const readLikeVersion: number = this.commentLikeVersion;
    this.replyEpochs.set(comment.id, threadEpoch);
    this.replyLoadingIds = this.replyLoadingIds.concat([comment.id]);
    try {
      const page = await WeiboService.getInstance().fetchCommentReplies(comment.id, cursor ?? '0');
      if (!this.isCurrentReplyRequest(epoch, revision, comment.id, threadEpoch)) { return; }
      this.applyConcurrentCommentLikes(page.items, readLikeVersion);
      const previous: WeiboComment[] = cursor === undefined ? [] : (comment.replies ?? []);
      comment.replies = previous.concat(page.items.filter((item: WeiboComment): boolean =>
        !previous.some((existing: WeiboComment): boolean => existing.id === item.id)));
      this.replyCursors.set(comment.id, page.hasMore ? page.nextMaxId : '0');
      if (!this.expandedReplyIds.includes(comment.id)) {
        this.expandedReplyIds = this.expandedReplyIds.concat([comment.id]);
      }
      this.comments = this.comments.slice();
    } catch (error) {
      if (!this.isCurrentReplyRequest(epoch, revision, comment.id, threadEpoch)) { return; }
      this.getUIContext().getPromptAction().showToast({ message: (error as Error).message ?? '回复加载失败，请重试' });
    } finally {
      if (this.isCurrentReplyRequest(epoch, revision, comment.id, threadEpoch)) { this.replyLoadingIds = this.replyLoadingIds.filter((id: string): boolean => id !== comment.id); }
    }
  }

  private copyPostWithLike(source: WeiboPost, liked: boolean): WeiboPost {
    return {
      id: source.id,
      userId: source.userId,
      userName: source.userName,
      userAvatar: source.userAvatar,
      text: source.text,
      isLongText: source.isLongText,
      pictures: source.pictures,
      pictureVideos: source.pictureVideos,
      videoAspectRatio: source.videoAspectRatio,
      isFavorited: source.isFavorited, isFollowed: source.isFollowed,
      videoUrl: source.videoUrl,
      videoCoverUrl: source.videoCoverUrl,
      createdAt: source.createdAt,
      source: source.source,
      likeCount: source.isLiked === liked ? source.likeCount : (liked ? source.likeCount + 1 : Math.max(0, source.likeCount - 1)),
      commentCount: source.commentCount,
      repostCount: source.repostCount,
      isLiked: liked,
      repost: source.repost,
    };
  }

  private async toggleFavorite(): Promise<void> {
    if (this.post === null || this.favoriting) { return; }
    const id: string = this.post.id;
    const favorite: boolean = !this.post.isFavorited;
    const revision: number = WeiboAuthManager.getInstance().getSessionRevision();
    this.favoriting = true;
    try {
      await WeiboService.getInstance().setFavorite(id, favorite);
      if (!this.isCurrentSession(revision)) { return; }
      if (this.post !== null && this.post.id === id) {
        const updated: WeiboPost = this.copyPostWithLike(this.post, this.post.isLiked);
        updated.isFavorited = favorite;
        this.post = updated;
        WeiboService.getInstance().rememberPost(updated);
      }
      Haptic.light();
      this.getUIContext().getPromptAction().showToast({ message: favorite ? '已收藏' : '已取消收藏' });
    } catch (error) {
      if (!this.isCurrentSession(revision)) { return; }
      this.getUIContext().getPromptAction().showToast({ message: (error as Error).message ?? '收藏操作失败，请重试' });
    } finally { if (this.isCurrentSession(revision)) { this.favoriting = false; } }
  }

  private async toggleLike(): Promise<void> {
    if (this.post === null || this.liking) {
      return;
    }
    const source: WeiboPost = this.post;
    const liked: boolean = !source.isLiked;
    const revision: number = WeiboAuthManager.getInstance().getSessionRevision();
    this.liking = true;
    try {
      Haptic.light();
      await WeiboService.getInstance().setLike(source.id, liked);
      if (!this.isCurrentSession(revision)) { return; }
      if (this.post === null || this.post.id !== source.id) { return; }
      const updated: WeiboPost = this.copyPostWithLike(this.post, liked);
      this.post = updated;
      WeiboService.getInstance().rememberPost(updated);
      this.getUIContext().getPromptAction().showToast({
        message: liked ? $r('app.string.weibo_like_success') : $r('app.string.weibo_unlike_success')
      });
    } catch (error) {
      if (!this.isCurrentSession(revision)) { return; }
      const message: string = (error as Error).message ?? '微博操作失败';
      this.getUIContext().getPromptAction().showToast({ message: message });
    } finally { if (this.isCurrentSession(revision)) { this.liking = false; } }
  }

  private repostDialogController: CustomDialogController | null = null;

  private openRepostDialog(): void {
    if (this.post === null) {
      return;
    }
    if (!WeiboAuthManager.getInstance().hasCookie()) {
      this.getUIContext().getPromptAction().showToast({ message: '请先在“我的”页面登录微博' });
      return;
    }
    this.repostDialogController = new CustomDialogController({
      builder: WeiboComposeDialog({
        mode: 'repost',
        targetPost: this.post,
        onSuccess: (): void => {
          if (this.post !== null) {
            this.post.repostCount++;
          }
        }
      }),
      alignment: DialogAlignment.Bottom,
      customStyle: true,
      offset: { dx: 0, dy: -20 }
    });
    this.repostDialogController.open();
  }

  private sharePost(): void {
    if (this.post === null) {
      return;
    }
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    ShareUtil.shareLink(this.getUIContext(), context, `https://m.weibo.cn/detail/${this.post.id}`,
      this.post.userName, this.post.text);
  }

  /** Mobile link sent when the user performs HarmonyOS' one-grab-one-release gesture. */
  private postShareUrl(post: WeiboPost): string {
    return `https://m.weibo.cn/detail/${post.id}`;
  }

  /** Register only while this detail is visible so another page can own the same system gesture. */
  private registerGesturesShare(): void {
    if (this.gestureShareListening || !canIUse('SystemCapability.Collaboration.HarmonyShare')) {
      return;
    }
    try {
      harmonyShare.on('gesturesShare', this.gesturesShareCallback);
      this.gestureShareListening = true;
    } catch {
      this.gestureShareListening = false;
    }
  }

  private unregisterGesturesShare(): void {
    if (!this.gestureShareListening) {
      return;
    }
    try {
      harmonyShare.off('gesturesShare', this.gesturesShareCallback);
    } catch {
      // The page is leaving; discarding the local registration state is safe.
    }
    this.gestureShareListening = false;
  }

  private createGestureShareData(post: WeiboPost, thumbnailUri: string): systemShare.SharedData {
    if (thumbnailUri.length > 0) {
      return new systemShare.SharedData({
        utd: utd.UniformDataType.HYPERLINK,
        content: this.postShareUrl(post),
        thumbnailUri: thumbnailUri,
        title: post.userName + ' 的微博',
        description: post.text
      });
    }
    return new systemShare.SharedData({
      utd: utd.UniformDataType.HYPERLINK,
      content: this.postShareUrl(post),
      title: post.userName + ' 的微博',
      description: post.text
    });
  }

  private async captureGestureSharePreview(post: WeiboPost): Promise<string> {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const previewPath: string = context.filesDir + '/weibo-gesture-share-' + post.id + '.png';
    try {
      const pixelMap: image.PixelMap = await this.getUIContext().getComponentSnapshot().createFromBuilder(
        (): void => {
          this.GestureSharePreview();
        }, 0, true, { scale: 1, waitUntilRenderFinished: true });
      const packer: image.ImagePacker = image.createImagePacker();
      const data: ArrayBuffer = await packer.packToData(pixelMap, { format: 'image/png', quality: 100 });
      const file: fileIo.File = fileIo.openSync(previewPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      try {
        fileIo.writeSync(file.fd, data);
      } finally {
        fileIo.closeSync(file.fd);
      }
      return fileUri.getUriFromPath(previewPath);
    } catch {
      return '';
    }
  }

  private async prepareGestureSharePreview(): Promise<void> {
    const currentPost: WeiboPost | null = this.post;
    if (currentPost === null) {
      return;
    }
    const contentKey: string = this.gestureSharePreviewKey(currentPost);
    if (this.gestureSharePreviewPostId === currentPost.id && this.gestureSharePreviewContentKey === contentKey) {
      return;
    }
    const previewUri: string = await this.captureGestureSharePreview(currentPost);
    if (this.post !== null && this.post.id === currentPost.id &&
      this.gestureSharePreviewKey(this.post) === contentKey) {
      this.gestureSharePreviewPostId = currentPost.id;
      this.gestureSharePreviewUri = previewUri;
      this.gestureSharePreviewContentKey = contentKey;
    }
  }

  private gestureSharePreviewKey(post: WeiboPost): string {
    const mediaUrl: string = post.pictures.length > 0 ? post.pictures[0] : post.videoCoverUrl;
    return `${post.id}|${post.userName}|${post.userAvatar}|${post.text}|${post.createdAt}|${post.source}|` +
      `${post.repostCount}|${post.commentCount}|${post.likeCount}|${mediaUrl}`;
  }

  private async sharePostByGesture(target: harmonyShare.SharableTarget): Promise<void> {
    const currentPost: WeiboPost | null = this.post;
    if (currentPost === null || this.gestureSharing) {
      return;
    }
    this.gestureSharing = true;
    try {
      if (this.gestureSharePreviewPostId !== currentPost.id ||
        this.gestureSharePreviewContentKey !== this.gestureSharePreviewKey(currentPost)) {
        await this.prepareGestureSharePreview();
      }
      const shareData: systemShare.SharedData = this.createGestureShareData(currentPost, this.gestureSharePreviewUri);
      await target.share(shareData);
    } catch {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.weibo_gesture_share_failed') });
    }
    this.gestureSharing = false;
  }

  @Builder
  GestureSharePreview() {
    if (this.post !== null) {
      Column({ space: Spacing.sm }) {
        Row({ space: Spacing.sm }) {
          if (this.post.userAvatar.length > 0) {
            Image(this.post.userAvatar)
              .width(42)
              .height(42)
              .objectFit(ImageFit.Cover)
              .borderRadius(Radius.full)
              .clip(true)
          } else {
            Stack() {
              Text(this.post.userName.substring(0, 1))
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
            }
            .width(42)
            .height(42)
            .backgroundColor(Theme.brand())
            .borderRadius(Radius.full)
            .alignContent(Alignment.Center)
          }
          Column({ space: 2 }) {
            Text(this.post.userName)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.textPrimary(this.isDark))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(`${this.post.createdAt}${this.post.source.length > 0 ? ' · ' + this.post.source : ''}`)
              .fontSize(12)
              .fontColor(Theme.textSecondary(this.isDark))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        Text(this.post.text)
          .width('100%')
          .fontSize(16)
          .lineHeight(24)
          .fontColor(Theme.textPrimary(this.isDark))
          .maxLines(5)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.post.pictures.length > 0) {
          Image(this.post.pictures[0])
            .width('100%')
            .height(148)
            .objectFit(ImageFit.Cover)
            .borderRadius(Radius.md)
        } else if (this.post.videoCoverUrl.length > 0) {
          Image(this.post.videoCoverUrl)
            .width('100%')
            .height(148)
            .objectFit(ImageFit.Cover)
            .borderRadius(Radius.md)
        }
        Row({ space: Spacing.md }) {
          Text($r('app.string.weibo_gesture_share_reposts'))
            .fontSize(12)
            .fontColor(Theme.textSecondary(this.isDark))
          Text(`${this.post.repostCount}`)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.textPrimary(this.isDark))
          Text($r('app.string.weibo_gesture_share_comments'))
            .fontSize(12)
            .fontColor(Theme.textSecondary(this.isDark))
          Text(`${this.post.commentCount}`)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.textPrimary(this.isDark))
          Text($r('app.string.weibo_gesture_share_likes'))
            .fontSize(12)
            .fontColor(Theme.textSecondary(this.isDark))
          Text(`${this.post.likeCount}`)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.textPrimary(this.isDark))
        }
        .width('100%')
        Text(this.postShareUrl(this.post))
          .width('100%')
          .fontSize(11)
          .fontColor(Theme.brand())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width(320)
      .padding(Spacing.lg)
      .backgroundColor(Theme.bgCard(this.isDark))
      .border({ width: 1, color: Theme.manualGlassBorder() })
      .borderRadius(Radius.postCard)
    }
  }

  private async selectCommentImage(): Promise<void> {
    if (this.commentSending || this.pickingCommentImage) { return; }
    const revision: number = WeiboAuthManager.getInstance().getSessionRevision();
    this.pickingCommentImage = true;
    try {
      const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      const result: photoAccessHelper.PhotoSelectResult = await picker.select({
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE, maxSelectNumber: 1
      });
      if (!this.isCurrentSession(revision)) { return; }
      if (result.photoUris.length > 0) { this.commentImage = result.photoUris[0]; this.commentPictureId = ''; }
    } catch (_error) {
      this.getUIContext().getPromptAction().showToast({ message: '选图未完成，请重试' });
    } finally {
      if (this.isCurrentSession(revision)) { this.pickingCommentImage = false; this.focusCommentEditor(); }
    }
  }

  private async sendComment(): Promise<void> {
    if (this.commentSending || this.pickingCommentImage || (this.commentDraft.trim().length === 0 && this.commentImage.length === 0) || this.postId.length === 0) {
      return;
    }
    this.commentSending = true;
    const postId: string = this.postId;
    const content: string = this.commentDraft;
    const replyId: string | undefined = this.replyTargetComment?.id;
    const uri: string = this.commentImage;
    const cookie: string = WeiboAuthManager.getInstance().getCookie();
    const revision: number = WeiboAuthManager.getInstance().getSessionRevision();
    try {
      const service: WeiboService = WeiboService.getInstance();
      if (uri.length > 0) {
        if (cookie !== this.commentPictureCookie) { this.commentPictureId = ''; this.commentPictureCookie = cookie; }
        this.commentUploadHint = '正在上传评论配图…';
        if (this.commentPictureId.length === 0) { this.commentPictureId = await service.uploadPicture(uri); }
      }
      WeiboAuthManager.getInstance().assertSession(revision);
      this.commentUploadHint = '正在发送评论…';
      await service.publishComment(postId, content, replyId, uri.length > 0 ? this.commentPictureId : '');
      if (!this.isCurrentSession(revision)) { return; }
      this.commentDraft = '';
      this.commentImage = '';
      this.commentPictureId = '';
      this.showCommentEmoji = false;
      this.closeCommentEditor();
      Haptic.light();
      this.replyTargetComment = null;
      await this.loadComments(true);
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.weibo_comment_success') });
    } catch (error) {
      if (!this.isCurrentSession(revision)) { return; }
      const message: string = (error as Error).message ?? '评论发送失败';
      this.getUIContext().getPromptAction().showToast({ message: message });
    } finally {
      if (this.isCurrentSession(revision)) { this.commentSending = false; this.commentUploadHint = ''; }
    }
  }

  private visiblePictureCount(pictures: string[]): number {
    return pictures.length > 9 ? 9 : pictures.length;
  }

  private pictureColumns(pictures: string[]): number {
    const count: number = this.visiblePictureCount(pictures);
    return count === 2 || count === 4 ? 2 : 3;
  }

  private pictureCellHeight(pictures: string[]): number {
    const count: number = this.visiblePictureCount(pictures);
    return count === 2 || count === 4 ? 150 : 106;
  }

  private pictureGridHeight(pictures: string[]): number {
    const count: number = this.visiblePictureCount(pictures);
    const columns: number = this.pictureColumns(pictures);
    const rows: number = Math.ceil(count / columns);
    return rows * this.pictureCellHeight(pictures) + (rows - 1) * Spacing.sm;
  }

  private openImagePreview(urls: string[], index: number, pictureVideos: Record<string, string> = {}): void {
    if (urls.length === 0) {
      return;
    }
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/ImagePreview',
      params: { urls: urls, index: index, pictureVideos: pictureVideos }
    }).catch((): void => {
      this.getUIContext().getPromptAction().showToast({ message: '原图预览打开失败，请稍后重试' });
    });
  }

  @Builder
  DetailTitleBar() {
    Column() {
      Row() {
        Button() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontColor([$r('sys.color.icon_primary')])
            .fontSize(fs(28, this.fontScale))
        }
        .width(44)
        .height(44)
        .backgroundColor(Color.Transparent)
        .systemMaterial(ImmMaterial.control())
        .borderRadius(Radius.full)
        .accessibilityText($r('app.string.weibo_back'))
        .onClick((): void => { this.popRoute(); })

        Text($r('app.string.weibo_post_detail_title'))
          .layoutWeight(1)
          .fontSize(fs(17, this.fontScale))
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary(this.isDark))
          .textAlign(TextAlign.Center)

        // 占位对称，保持标题居中且精简顶栏
        Row().width(44).height(44)
      }
      .width('100%')
      .height(64)
      .padding({ left: Spacing.lg, right: Spacing.lg })
    }
    .width('100%')
  }

  private isGifOrLive(url: string, pictureVideos: Record<string, string>): string {
    if ((pictureVideos[url] ?? '').length > 0) { return '实况'; }
    const lower: string = url.toLowerCase();
    if (lower.includes('.gif')) {
      return 'GIF';
    }
    return '';
  }

  @Builder
  PictureGrid(pictures: string[], pictureVideos: Record<string, string> = {}) {
    if (this.visiblePictureCount(pictures) === 1) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Image(pictures[0])
          .width('100%')
          .height(260)
          .constraintSize({ maxWidth: 460 })
          .objectFit(ImageFit.Cover)
          .borderRadius(Radius.md)

        if (this.isGifOrLive(pictures[0], pictureVideos).length > 0) {
          Text(this.isGifOrLive(pictures[0], pictureVideos))
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .backgroundColor('#80000000')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(4)
            .margin(8)
        }
      }
      .hitTestBehavior(HitTestMode.Default)
      .onClick((): void => { this.openImagePreview(pictures, 0, pictureVideos); })
    } else if (this.visiblePictureCount(pictures) > 1) {
      Grid() {
        ForEach(pictures.slice(0, this.visiblePictureCount(pictures)), (picture: string, index: number): void => {
          GridItem() {
            Stack({ alignContent: Alignment.BottomEnd }) {
              Image(picture)
                .width('100%')
                .height(this.pictureCellHeight(pictures))
                .objectFit(ImageFit.Cover)
                .borderRadius(Radius.md)

              if (this.isGifOrLive(picture, pictureVideos).length > 0) {
                Text(this.isGifOrLive(picture, pictureVideos))
                  .fontSize(10)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Color.White)
                  .backgroundColor('#80000000')
                  .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                  .borderRadius(3)
                  .margin(4)
              }
            }
            .hitTestBehavior(HitTestMode.Default)
            .onClick((): void => { this.openImagePreview(pictures, index, pictureVideos); })
          }
        }, (picture: string, index: number): string => `${index}`)
      }
      .columnsTemplate(this.pictureColumns(pictures) === 2 ? '1fr 1fr' : '1fr 1fr 1fr')
      .columnsGap(Spacing.sm)
      .rowsGap(Spacing.sm)
      .width('100%')
      .height(this.pictureGridHeight(pictures))
      .constraintSize({ maxWidth: 460 })
      .enableScrollInteraction(false)
    }
  }

  @Builder
  VideoPlayer(currentPost: WeiboPost) {
    if (currentPost.videoUrl.length > 0) {
      WeiboVideoPlayer({ src: currentPost.videoUrl, cover: currentPost.videoCoverUrl, videoRatio: currentPost.videoAspectRatio ?? 16 / 9 })
    }
  }

  @Builder
  RepostCard(repost: WeiboPost) {
    Column({ space: Spacing.sm }) {
      WeiboRichTextView({
        text: `@${repost.userName}：${repost.text}`,
        fontSize: fs(14, this.fontScale), lineHeight: fs(21, this.fontScale),
        fontColor: Theme.textPrimary(this.isDark),
        onTopicClick: (topic: string): void => { this.openSearchTopic(topic); },
        onMentionClick: (name: string): void => { this.openUserProfile('', name); }
      }).width('100%')
      if (repost.pictures.length > 0) {
        this.PictureGrid(repost.pictures, repost.pictureVideos ?? {})
      }
      Row({ space: 3 }) {
        Text('查看原微博')
          .fontSize(fs(12, this.fontScale))
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.brand())
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(fs(12, this.fontScale))
          .fontColor([Theme.brand()])
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
    .padding(Spacing.md)
    .backgroundColor(Theme.brandBg(this.isDark))
    .borderRadius(Radius.md)
    .accessibilityText(`查看@${repost.userName}的原微博`)
    .onClick((): void => { this.openOriginalPost(repost); })
  }

  @Builder
  PostBody(params: PostBodyParams) {
    Column({ space: Spacing.md }) {
      Row({ space: Spacing.sm }) {
        if (params.post.userAvatar.length > 0) {
          Image(params.post.userAvatar)
            .width(44)
            .height(44)
            .borderRadius(Radius.full)
            .objectFit(ImageFit.Cover)
        } else {
          Stack() {
            Text(params.post.userName.substring(0, 1))
              .fontSize(fs(17, this.fontScale))
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.brand())
          }
          .width(44)
          .height(44)
          .backgroundColor(Theme.brandBg(this.isDark))
          .borderRadius(Radius.full)
          .alignContent(Alignment.Center)
        }
        Column({ space: 2 }) {
          Text(params.post.userName)
            .fontSize(fs(16, this.fontScale))
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.textPrimary(this.isDark))
          Text(`${params.post.createdAt}${params.post.source.length > 0 ? ' · ' + params.post.source : ''}`)
            .fontSize(fs(12, this.fontScale))
            .fontColor(Theme.textSecondary(this.isDark))
            .maxLines(1)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .onClick((): void => {
        this.openUserProfile(params.post.userId, params.post.userName);
      })
      WeiboRichTextView({
        text: params.post.text,
        fontSize: fs(17, this.fontScale),
        lineHeight: fs(27, this.fontScale),
        fontColor: Theme.textPrimary(this.isDark),
        onTopicClick: (topic: string): void => { this.openSearchTopic(topic); },
        onMentionClick: (username: string): void => { this.openUserProfile('', username); }
      })
        .width('100%')
      if (params.post.isLongText) {
        Row({ space: 4 }) {
          if (this.longTextLoading) {
            LoadingProgress()
              .width(16)
              .height(16)
              .color(Theme.brand())
          }
          Text(this.longTextLoading ? '正在展开全文…' : '… 查看全文')
            .fontSize(fs(15, this.fontScale))
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.brand())
        }
        .height(36)
        .alignSelf(ItemAlign.Start)
        .hitTestBehavior(HitTestMode.Default)
        .accessibilityText('展开微博全文')
        .enabled(!this.longTextLoading)
        .onClick((): void => { this.expandLongText(); })
      }
      this.VideoPlayer(params.post)
      if (params.post.pictures.length > 0) {
        this.PictureGrid(params.post.pictures, params.post.pictureVideos ?? {})
      }
      if (params.post.repost !== null) {
        this.RepostCard(params.post.repost)
      }
      Row({ space: Spacing.md }) {
        Text(`转发 ${params.post.repostCount}`)
          .fontSize(fs(13, this.fontScale))
          .fontColor(Theme.textSecondary(this.isDark))
          .layoutWeight(1)
        Text(`评论 ${params.post.commentCount}`)
          .fontSize(fs(13, this.fontScale))
          .fontColor(Theme.textSecondary(this.isDark))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text(`${params.post.isLiked ? '♥' : '♡'} ${params.post.likeCount}`)
          .fontSize(fs(13, this.fontScale))
          .fontColor(Theme.brand())
          .layoutWeight(1)
          .textAlign(TextAlign.End)
      }
      .width('100%')
    }
    .width('100%')
    .padding(Spacing.lg)
    .backgroundColor(Theme.bgCard(this.isDark))
    .borderRadius(Radius.postCard)
  }

  @Builder
  CommentItem(comment: WeiboComment) {
    Row({ space: Spacing.sm }) {
      if (comment.userAvatar.length > 0) {
        Image(comment.userAvatar)
          .width(34).height(34).borderRadius(Radius.full).objectFit(ImageFit.Cover)
          .onClick((): void => { this.openUserProfile(comment.userId, comment.userName); })
      }
      Column({ space: 5 }) {
        Row() {
          Text(comment.userName)
            .fontSize(fs(13, this.fontScale)).fontWeight(FontWeight.Medium)
            .fontColor(Theme.textPrimary(this.isDark)).layoutWeight(1)
            .onClick((): void => { this.openUserProfile(comment.userId, comment.userName); })
          Row({ space: 4 }) {
            SymbolGlyph(comment.isLiked ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
              .fontSize(fs(14, this.fontScale))
              .fontColor([comment.isLiked ? Theme.brand() : Theme.textTertiary(this.isDark)])
            if (comment.likeCount > 0) {
              Text(`${comment.likeCount}`)
                .fontSize(fs(12, this.fontScale))
                .fontColor(comment.isLiked ? Theme.brand() : Theme.textSecondary(this.isDark))
            }
          }
          .height(32)
          .padding({ left: 6, right: 6 })
          .hitTestBehavior(HitTestMode.Default)
          .onClick((): void => { this.toggleCommentLike(comment); })
        }.width('100%')
        WeiboRichTextView({
          text: comment.text,
          fontSize: fs(14, this.fontScale),
          lineHeight: fs(21, this.fontScale),
          fontColor: Theme.textPrimary(this.isDark),
          onTopicClick: (topic: string): void => { this.openSearchTopic(topic); },
          onMentionClick: (username: string): void => { this.openUserProfile('', username); }
        }).width('100%')
        if ((comment.pictures ?? []).length > 0) {
          this.PictureGrid(comment.pictures ?? [])
        }
        Text(comment.createdAt).fontSize(fs(11, this.fontScale)).fontColor(Theme.textSecondary(this.isDark))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      // 回复入口：点击评论本身进入回复。原独立红色「回复」按钮已移除（用户明确要求）。
      // 头像 / 昵称 / 点赞 / 评论配图各自持有 onClick，会自行消费点击，
      // 因此点这些子区域不会误触发回复（同 PostCard 外层 openPost + 内层点赞按钮的既有行为）。
      .onClick((): void => { this.beginCommentReply(comment); })
      .accessibilityText(`回复 ${comment.userName}`)
    }.width('100%').alignItems(VerticalAlign.Top)
  }

  @Builder
  CommentSortButton(label: string, sort: WeiboCommentSort) {
    Button(label).height(44).fontSize(fs(13, this.fontScale))
      .fontWeight(this.commentsSort === sort ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.commentsSort === sort ? Theme.brand() : Theme.textSecondary(this.isDark))
      .backgroundColor(Theme.segGlass(this.isDark, this.commentsSort === sort))
      .borderRadius(Radius.full).padding({ left: 12, right: 12 })
      .accessibilityText(`${label}${this.commentsSort === sort ? '，已选中' : ''}`)
      .onClick((): void => { this.switchCommentSort(sort); })
  }

  @Builder
  CommentsSection() {
    Column({ space: Spacing.md }) {
      Row({ space: 8 }) {
        Text($r('app.string.weibo_post_comments_title'))
          .fontSize(fs(18, this.fontScale)).fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary(this.isDark)).layoutWeight(1)
        this.CommentSortButton('按热度', WeiboCommentSort.Hot)
        this.CommentSortButton('按实时', WeiboCommentSort.Latest)
      }.width('100%')
      if (this.commentsLoading) {
        Row({ space: Spacing.sm }) {
          LoadingProgress().width(18).height(18)
          Text($r('app.string.weibo_comments_loading'))
            .fontSize(fs(13, this.fontScale))
            .fontColor(Theme.textSecondary(this.isDark))
        }
      } else if (this.commentsError.length > 0) {
        Text(this.commentsError).fontSize(fs(13, this.fontScale)).fontColor(Theme.danger())
        Button('重新加载评论').height(44).backgroundColor(Color.Transparent).fontColor(Theme.brand())
          .onClick((): void => { this.loadComments(true); })
      } else if (this.comments.length === 0) {
        Text($r('app.string.weibo_no_comments'))
          .fontSize(fs(13, this.fontScale))
          .fontColor(Theme.textSecondary(this.isDark))
      } else {
        ForEach(this.comments, (comment: WeiboComment): void => {
          Column({ space: Spacing.sm }) {
            this.CommentItem(comment)
            if (this.expandedReplyIds.includes(comment.id)) {
              Column({ space: Spacing.sm }) {
                ForEach(comment.replies ?? [], (reply: WeiboComment): void => {
                  this.CommentItem(reply)
                }, (reply: WeiboComment): string => reply.id)
              }.width('100%').padding({ left: 36 })
            }
            if ((comment.replyCount ?? 0) > 0 || (comment.replies ?? []).length > 0) {
              Row({ space: Spacing.sm }) {
                if (this.replyLoadingIds.includes(comment.id)) {
                  LoadingProgress().width(18).height(18)
                } else if (this.replyCursors.get(comment.id) !== '0') {
                  Button(this.expandedReplyIds.includes(comment.id) ? '加载更多回复' : `查看 ${comment.replyCount ?? 0} 条回复`)
                    .height(32).fontSize(fs(12, this.fontScale)).fontColor(Theme.brand())
                    .backgroundColor(Color.Transparent)
                    .onClick((): void => { this.loadReplies(comment); })
                }
                if (this.expandedReplyIds.includes(comment.id)) {
                  Button('收起').height(32).fontSize(fs(12, this.fontScale))
                    .backgroundColor(Color.Transparent)
                    .onClick((): void => {
                      this.collapseReplies(comment.id);
                    })
                }
              }.padding({ left: 36 })
            }
          }.width('100%')
            .padding({ top: Spacing.sm, bottom: Spacing.md })
            .border({ width: { bottom: 0.5 }, color: Theme.manualGlassBorder() })
        }, (comment: WeiboComment): string => comment.id)
        if (this.loadingMoreComments) {
          LoadingProgress().width(24).height(24)
        } else if (this.hasMoreComments) {
          Button('加载更多评论')
            .backgroundColor(Color.Transparent).fontColor(Theme.brand())
            .onClick((): void => { this.loadMoreComments(); })
        } else {
          Text('已加载全部评论').fontSize(12).fontColor(Theme.textSecondary(this.isDark))
        }
      }
    }
    .width('100%')
    .padding(Spacing.lg)
    .backgroundColor(Theme.bgCard(this.isDark))
    .borderRadius(Radius.postCard)
    .margin({ top: Spacing.md })
    .onAreaChange((_old: Area, area: Area): void => {
      this.commentsSectionTop = Number(area.globalPosition.y) + this.detailScroller.currentOffset().yOffset;
    })
  }

  @Builder
  CommentAvatar() {
    if (this.accountAvatarUrl.length > 0) {
      Image(this.accountAvatarUrl)
        .width(40)
        .height(40)
        .objectFit(ImageFit.Cover)
        .borderRadius(20)
        .clip(true)
    } else if (this.accountName.length > 0) {
      Text(this.accountName.substring(0, 1).toUpperCase())
        .width(40)
        .height(40)
        .fontSize(fs(16, this.fontScale))
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .backgroundColor(Theme.brand())
        .borderRadius(20)
        .textAlign(TextAlign.Center)
    } else {
      SymbolGlyph($r('sys.symbol.person'))
        .width(40)
        .height(40)
        .fontSize(fs(20, this.fontScale))
        .fontColor([$r('sys.color.icon_primary')])
        .backgroundColor(Theme.segGlass(this.isDark, false))
        .borderRadius(20)
    }
  }

  private formatCount(num: number): string {
    if (num <= 0) { return ''; }
    if (num >= 10000) { return (num / 10000).toFixed(1) + 'w'; }
    return `${num}`;
  }

  private scrollToComments(): void {
    if (this.commentsSectionTop < Number.POSITIVE_INFINITY && this.commentsSectionTop > 0) {
      this.detailScroller.scrollTo({
        xOffset: 0,
        yOffset: Math.max(0, this.commentsSectionTop - 80),
        animation: { duration: 250, curve: Curve.EaseOut }
      });
    } else {
      this.detailScroller.scrollPage({ next: true });
    }
  }

  // Content only: the native HdsTabs slot owns the material and gradient backplate.
  @Builder
  BottomComposer() {
    Row({ space: 10 }) {
      // 1. 左侧沉降输入胶囊（说点什么...）
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.square_and_pencil'))
          .fontSize(fs(16, this.fontScale))
          .fontColor([Theme.textTertiary(this.isDark)])
        Text(this.commentDraft.length > 0 ? this.commentDraft : '说点什么...')
          .fontSize(fs(13.5, this.fontScale))
          .fontColor(this.commentDraft.length > 0 ? Theme.textPrimary(this.isDark) : Theme.textSecondary(this.isDark))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .layoutWeight(1)
      .height(38)
      .padding({ left: 14, right: 14 })
      .borderRadius(19)
      .backgroundColor(this.isDark ? 'rgba(255, 255, 255, 0.08)' : 'rgba(0, 0, 0, 0.04)')
      .accessibilityText('写评论')
      .onClick((): void => {
        this.replyTargetComment = null;
        this.openCommentEditor();
      })

      // 2. 右侧三个功能项（横向并列：点赞、收藏、评论）
      Row({ space: 4 }) {
        // 点赞 (Heart + count)
        Row({ space: 3 }) {
          SymbolGlyph((this.post !== null && this.post.isLiked) ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
            .fontSize(fs(20, this.fontScale))
            .fontColor([(this.post !== null && this.post.isLiked) ? '#E05252' : Theme.textPrimary(this.isDark)])
          Text(this.post !== null && this.post.likeCount > 0 ? this.formatCount(this.post.likeCount) : '赞')
            .fontSize(fs(12.5, this.fontScale))
            .fontWeight(FontWeight.Medium)
            .fontColor((this.post !== null && this.post.isLiked) ? '#E05252' : Theme.textPrimary(this.isDark))
        }
        .height(38)
        .padding({ left: 6, right: 6 })
        .borderRadius(19)
        .alignItems(VerticalAlign.Center)
        .hitTestBehavior(HitTestMode.Default)
        .accessibilityText((this.post !== null && this.post.isLiked) ? '取消点赞' : '点赞')
        .onClick((): void => {
          if (this.post !== null) {
            this.toggleLike();
          }
        })

        // 收藏 (Star + count)
        Row({ space: 3 }) {
          SymbolGlyph((this.post !== null && this.post.isFavorited) ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'))
            .fontSize(fs(20, this.fontScale))
            .fontColor([(this.post !== null && this.post.isFavorited) ? '#F59E0B' : Theme.textPrimary(this.isDark)])
          Text(this.post !== null && this.post.repostCount > 0 ? this.formatCount(this.post.repostCount) : (this.post?.isFavorited ? '已藏' : '收藏'))
            .fontSize(fs(12.5, this.fontScale))
            .fontWeight(FontWeight.Medium)
            .fontColor((this.post !== null && this.post.isFavorited) ? '#F59E0B' : Theme.textPrimary(this.isDark))
        }
        .height(38)
        .padding({ left: 6, right: 6 })
        .borderRadius(19)
        .alignItems(VerticalAlign.Center)
        .hitTestBehavior(HitTestMode.Default)
        .accessibilityText((this.post !== null && this.post.isFavorited) ? '取消收藏' : '收藏')
        .onClick((): void => {
          this.toggleFavorite();
        })

        // 评论 (Message + count)
        Row({ space: 3 }) {
          SymbolGlyph($r('sys.symbol.message'))
            .fontSize(fs(20, this.fontScale))
            .fontColor([Theme.textPrimary(this.isDark)])
          Text(this.post !== null && this.post.commentCount > 0 ? this.formatCount(this.post.commentCount) : '评论')
            .fontSize(fs(12.5, this.fontScale))
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.textPrimary(this.isDark))
        }
        .height(38)
        .padding({ left: 6, right: 6 })
        .borderRadius(19)
        .alignItems(VerticalAlign.Center)
        .hitTestBehavior(HitTestMode.Default)
        .accessibilityText('查看评论')
        .onClick((): void => {
          this.scrollToComments();
        })
      }
    }
    .height(56)
    .padding({ left: 12, right: 8 })
    .alignItems(VerticalAlign.Center)
    .width('100%')
    .enabled(this.post !== null && !this.loading && !this.commentEditorOpen && !this.commentComposerHidden)
  }

  @Builder
  ComposerAttachments() {
    Column() {
      if (this.commentUploadHint.length > 0) {
        Text(this.commentUploadHint)
          .fontSize(fs(13, this.fontScale))
          .fontColor(Theme.brand())
          .padding(8)
          .backgroundColor(Theme.bgCard(this.isDark))
          .borderRadius(Radius.md)
          .margin({ bottom: 6 })
      }
      if (this.commentImage.length > 0) {
        Row({ space: 8 }) {
          Image(this.commentImage).width(48).height(48).objectFit(ImageFit.Cover).borderRadius(8)
          Text('评论配图').fontSize(fs(12.5, this.fontScale)).fontColor(Theme.textSecondary(this.isDark)).layoutWeight(1)
          Button('移除').height(32).fontSize(fs(12, this.fontScale)).backgroundColor(Color.Transparent)
            .fontColor(Theme.textSecondary(this.isDark))
            .enabled(!this.commentSending)
            .onClick((): void => { this.commentImage = ''; this.commentPictureId = ''; })
        }
        .padding(8)
        .width('100%')
        .backgroundColor(this.isDark ? 'rgba(28, 34, 30, 0.85)' : 'rgba(255, 255, 255, 0.88)')
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
        .border({ width: 0.5, color: Theme.manualGlassBorder() })
        .borderRadius(14)
        .margin({ bottom: 6 })
      }

    }
    .width('100%')
    .constraintSize({ maxWidth: 400 })
    .padding({ left: 16, right: 16 })
    .margin({ bottom: this.navigationIndicatorHeight + 96 })
  }

  /** 鸿蒙原生沉浸式微质感悬浮回复卡片 */
  @Builder
  ExpandedCommentEditor() {
    Column() {
      Column({ space: 10 }) {
        // 1. 无边框通透多行文本输入
        TextArea({ text: this.commentDraft,
          placeholder: this.replyTargetComment === null ? $r('app.string.weibo_comment_placeholder') : `回复 @${this.replyTargetComment.userName}`,
          controller: this.commentEditorController })
          .id(`weibo-comment-editor-${this.postId}`)
          .constraintSize({ minHeight: 56, maxHeight: 110 })
          .width('100%')
          .fontSize(fs(16, this.fontScale))
          .fontColor(Theme.textPrimary(this.isDark))
          .placeholderColor(this.isDark ? '#64748B' : '#8FA0A9')
          .backgroundColor(Color.Transparent)
          .padding({ left: 4, right: 4, top: 4, bottom: 2 })
          .enabled(!this.commentSending && !this.pickingCommentImage)
          .onChange((value: string): void => { this.commentDraft = value; })
          .onTextSelectionChange((start: number, end: number): void => {
            this.commentSelectionStart = start; this.commentSelectionEnd = end;
          })
          .onFocus((): void => { this.commentInputFocused = true; this.setComposerVisible(true); })
          .onBlur((): void => { this.commentInputFocused = false; })

        // 选图预览
        if (this.commentImage.length > 0) {
          Row({ space: 8 }) {
            Image(this.commentImage).width(48).height(48).objectFit(ImageFit.Cover).borderRadius(8)
            Text('评论配图').fontSize(fs(12, this.fontScale)).fontColor(Theme.textSecondary(this.isDark)).layoutWeight(1)
            Button('移除').height(32).fontSize(fs(12, this.fontScale)).backgroundColor(Color.Transparent)
              .fontColor(Theme.textSecondary(this.isDark))
              .enabled(!this.commentSending && !this.pickingCommentImage)
              .onClick((): void => { this.commentImage = ''; this.commentPictureId = ''; })
          }.width('100%')
        }
        if (this.commentUploadHint.length > 0) {
          Text(this.commentUploadHint).fontSize(fs(12, this.fontScale)).fontColor(Theme.brand()).width('100%')
        }

        // 2. 中部操作工具栏 (😊, 🖼️, @, #, 更多) + 鼠尾草绿/薄荷绿发布胶囊
        Row() {
          Row({ space: 14 }) {
            // 表情按钮
            Button({ type: ButtonType.Normal }) {
              SymbolGlyph($r('sys.symbol.face_smiling'))
                .fontSize(22)
                .fontColor([this.showCommentEmoji ? Theme.brand() : Theme.textSecondary(this.isDark)])
            }
            .width(32).height(32).backgroundColor(Color.Transparent)
            .enabled(!this.commentSending && !this.pickingCommentImage).accessibilityText('选择微博表情')
            .onClick((): void => { this.toggleCommentEmoji(); })

            // 相册选图
            Button({ type: ButtonType.Normal }) {
              SymbolGlyph($r('sys.symbol.picture'))
                .fontSize(22)
                .fontColor([Theme.textSecondary(this.isDark)])
            }
            .width(32).height(32).backgroundColor(Color.Transparent)
            .enabled(!this.commentSending && !this.pickingCommentImage).accessibilityText('添加评论图片')
            .onClick((): void => { this.selectCommentImage(); })

            // @ 提及
            Button({ type: ButtonType.Normal }) {
              Text('@').fontSize(fs(20, this.fontScale)).fontWeight(FontWeight.Medium)
                .fontColor(Theme.textSecondary(this.isDark))
            }
            .width(32).height(32).backgroundColor(Color.Transparent)
            .enabled(!this.commentSending && !this.pickingCommentImage).accessibilityText('插入 @ 提及')
            .onClick((): void => { this.insertCommentToken('@'); this.focusCommentEditor(); })

            // # 话题
            Button({ type: ButtonType.Normal }) {
              Text('#').fontSize(fs(19, this.fontScale)).fontWeight(FontWeight.Medium)
                .fontColor(Theme.textSecondary(this.isDark))
            }
            .width(32).height(32).backgroundColor(Color.Transparent)
            .enabled(!this.commentSending && !this.pickingCommentImage).accessibilityText('插入 # 话题')
            .onClick((): void => { this.insertCommentToken('#输入话题# '); this.focusCommentEditor(); })

            // 更多/取消回复选项（支持取消指定人回复，保留测试覆盖）
            Button() {
              SymbolGlyph($r('sys.symbol.plus')).fontSize(22).fontColor([Theme.textSecondary(this.isDark)])
            }
            .width(32).height(32).borderRadius(16).backgroundColor(Color.Transparent)
            .enabled(!this.commentSending && !this.pickingCommentImage).accessibilityText('更多评论选项')
            .bindMenu([
              { value: '评论当前微博（取消回复）', action: (): void => { this.cancelCommentReply(); } },
              { value: '收起编辑面板', action: (): void => { this.closeCommentEditor(); } }
            ])
          }

          Blank()

          // 鼠尾草绿/薄荷绿“发布”胶囊按钮
          Button(this.commentSending ? '发送中…' : '发布')
            .height(32)
            .padding({ left: 16, right: 16 })
            .borderRadius(16)
            .fontSize(fs(13, this.fontScale))
            .fontWeight(FontWeight.Bold)
            .backgroundColor((this.commentDraft.trim().length > 0 || this.commentImage.length > 0)
              ? Theme.brand()
              : (this.isDark ? '#2D4A39' : '#97CAA2'))
            .fontColor(Color.White)
            .enabled(!this.commentSending && !this.pickingCommentImage && (this.commentDraft.trim().length > 0 || this.commentImage.length > 0))
            .onClick((): void => { this.sendComment(); })
        }
        .width('100%')

        // 3. 底部 9 颗高频快捷表情横向栏
        if (this.showCommentEmoji) {
          WeiboEmojiPanel({ onSelect: (name: string): void => {
            this.insertCommentToken(`[${name}]`); this.showCommentEmoji = false; this.focusCommentEditor();
          } })
        } else {
          Row() {
            ForEach(QUICK_REACTION_EMOJIS, (item: QuickReactionEmoji): void => {
              Button({ type: ButtonType.Normal }) {
                Text(item.char).fontSize(24).textAlign(TextAlign.Center)
              }
              .width(34).height(34).backgroundColor(Color.Transparent)
              .enabled(!this.commentSending && !this.pickingCommentImage).accessibilityText(item.name)
              .onClick((): void => {
                this.insertCommentToken(item.token);
                this.focusCommentEditor();
              })
            }, (item: QuickReactionEmoji): string => item.name)
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .borderRadius(26)
      .backgroundColor(Theme.sheetGlass(this.isDark))
      .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
      .border({ width: 1, color: this.isDark ? '#1FFFFFFF' : '#66FFFFFF' })
      .shadow({ radius: 28, color: this.isDark ? '#4D000000' : '#1F000000', offsetY: 8 })
    }
    .width('100%')
    .padding({ left: 12, right: 12, bottom: 8 })
    .onAppear((): void => { this.focusCommentEditor(); })
  }

  @Builder
  DetailContent() {
    Stack({ alignContent: Alignment.Bottom }) {
      HdsTabs({ controller: this.composerTabsController }) {
        TabContent() {
        Scroll(this.detailScroller) {
          Column() {
            if (this.loading) {
              LoadingProgress().width(28).height(28).margin({ top: 120 })
            } else if (this.errorMessage.length > 0) {
              Column({ space: Spacing.md }) {
                Text(this.errorMessage)
                  .fontSize(fs(14, this.fontScale))
                  .fontColor(Theme.danger())
                  .textAlign(TextAlign.Center)
                Button($r('app.string.weibo_load'))
                  .fontSize(fs(14, this.fontScale))
                  .onClick(() => { this.loadPost(); })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Center)
              .margin({ top: 120 })
            } else if (this.post !== null) {
              Column() {
                this.PostBody({ post: this.post })
                this.CommentsSection()
              }
              .width('100%')
              .opacity(this.contentOpacity)
              .translate({ y: this.contentTranslateY })
              .scale({ x: this.contentScale, y: this.contentScale })
              .renderGroup(true)
            }
          }
          .width('100%')
          .padding({
            left: 12,
            right: 12,
            top: this.statusBarHeight + 64,
            bottom: this.navigationIndicatorHeight + 92 + (this.commentImage.length > 0 ? 80 : 0)
          })
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .onAreaChange((_old: Area, area: Area): void => {
          this.detailViewportBottom = Number(area.globalPosition.y) + Number(area.height);
        })
        .onDidScroll((_xOffset: number, yOffset: number, state: ScrollState): void => { this.onDetailScroll(yOffset, state); })
        .onScrollEdge((edge: Edge): void => { if (edge === Edge.Bottom) { this.loadMoreComments(true); } })
        }
        .tabBar(this.BottomComposer())
      }
      .width('100%')
      .height('100%')
      .barPosition(BarPosition.End)
      .barOverlap(true)
      .scrollable(false)
      .animationDuration(0)
      .attributeModifier(this.composerTabsModifier)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .onAppear((): void => {
        this.composerTabsController.bindScroller(0, this.detailScroller);
        this.syncComposerDockVisibility();
      })
      .onDisAppear((): void => { this.composerTabsController.unbindScroller(this.detailScroller); })
      if (!this.commentComposerHidden && !this.commentEditorOpen && this.post !== null && !this.loading) {
        this.ComposerAttachments()
      }

      // 华为官方最佳实践键盘避让沉浸式弹窗层：Stack + expandSafeArea + keyboardHeight 自适应抬升
      if (this.commentEditorOpen) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#66000000')
          .onClick((): void => {
            if (!this.commentSending && !this.pickingCommentImage) {
              this.closeCommentEditor();
            }
          })
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))

        Column() {
          this.ExpandedCommentEditor()
          // 软键盘/底部手势条避让占位：键盘弹起时抬升对应高度，键盘收起时紧贴手势条上方
          Column()
            .height(this.keyboardHeight > 0 ? this.keyboardHeight : (this.navigationIndicatorHeight + 12))
            .animation({ duration: 180, curve: Curve.FastOutSlowIn })
        }
        .width('100%')
        .hitTestBehavior(HitTestMode.Default)
        .transition(TransitionEffect.asymmetric(
          TransitionEffect.OPACITY.combine(TransitionEffect.move(TransitionEdge.BOTTOM)).animation({ duration: 200, curve: Curve.EaseOut }),
          TransitionEffect.OPACITY.combine(TransitionEffect.move(TransitionEdge.BOTTOM)).animation({ duration: 180, curve: Curve.EaseIn })
        ))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg(this.isDark))
    .expandSafeArea([SafeAreaType.KEYBOARD], [SafeAreaEdge.BOTTOM])
  }

  build() {
    HdsNavDestination() {
      this.DetailContent()
    }
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .hideBackButton(true)
    .onBackPressed((): boolean => {
      if (this.commentEditorOpen) {
        if (!this.commentSending && !this.pickingCommentImage) {
          this.closeCommentEditor();
        }
        return true;
      }
      this.popRoute();
      return true;
    })
    .bindToScrollable([this.detailScroller])
    .titleBar({
      avoidLayoutSafeArea: true,
      content: {
        stackBuilder: (): void => this.DetailTitleBar(),
        divider: { showType: DividerShowType.OFF }
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.EXQUISITE
        }
      }
    })
    .backgroundColor(Theme.bg(this.isDark))
  }
}
