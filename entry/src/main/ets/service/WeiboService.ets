import { formatWeiboTime, stripHtml } from '../common/Constants';
import { normalizeWeiboText, midToBid, bidToMid } from '../common/WeiboText';
import { weiboLivePhotoTracks } from '../common/WeiboMediaMetadata';
import { rcp } from '@kit.RemoteCommunicationKit';
import { WeiboHttpClient } from '../network/WeiboHttpClient';
import { WeiboComment, WeiboCommentSort, WeiboCommentsPage, WeiboHotTopic, WeiboNotification, WeiboPost, WeiboSuggestion, WeiboTimelinePage, WeiboUser } from '../model/WeiboModel';
import { WeiboAuthManager } from './WeiboAuthManager';
import { WeiboVisitorSession } from './WeiboVisitorSession';
import { prepareWeiboImage, WeiboUploadImage } from './WeiboMedia';

interface WeiboUploadResponse {
  ok?: number;
  msg?: string;
  pic_id?: string;
  data?: WeiboUploadedPicture;
}
interface WeiboUploadedPicture { pic_id?: string; }

interface WeiboApiResponse {
  ok?: number;
  msg?: string;
  url?: string;
  data?: WeiboResponseData;
}

/** The mobile status endpoint returns a post directly in its data field. */
interface WeiboStatusApiResponse {
  ok?: number;
  data?: WeiboPostJson;
}

/** Authenticated mobile configuration exposes the UID for the current Cookie. */
interface WeiboConfigResponse {
  ok?: number;
  msg?: string;
  data?: WeiboConfigData;
}

interface WeiboConfigData {
  login?: boolean;
  uid?: string;
}

/** Desktop web's authenticated friends feed is not wrapped in a `data` object. */
interface WeiboFollowingTimelineResponse {
  ok?: number;
  msg?: string;
  statuses?: WeiboPostJson[];
  max_id?: string | number;
}

interface WeiboResponseData {
  cards?: WeiboCardJson[];
  userInfo?: WeiboUserJson;
  /** Full HTML body returned by `statuses/extend` for long posts. */
  longTextContent?: string;
  data?: WeiboCommentJson[];
  max_id?: string;
  realtime?: WeiboHotTopicJson[];
  hotquery?: WeiboSuggestionJson[];
}

interface WeiboHotTopicJson {
  rank?: number;
  realpos?: number;
  word?: string;
  num?: number;
  label_name?: string;
  word_scheme?: string;
  note?: string;
}

interface WeiboSuggestionJson {
  suggestion?: string;
  count?: number;
  top_flag?: number;
}

interface WeiboCardJson {
  card_type?: number;
  mblog?: WeiboPostJson;
  card_group?: WeiboCardJson[];
  user?: WeiboUserJson;
}

interface WeiboUserJson {
  /** Weibo returns numeric IDs on some timeline surfaces and strings on others. */
  idstr?: string;
  id?: string | number;
  screen_name?: string;
  description?: string;
  avatar_hd?: string;
  profile_image_url?: string;
  cover_image_phone?: string;
  followers_count?: string | number;
  follow_count?: string | number;
  statuses_count?: string | number;
  verified?: boolean;
  verified_reason?: string;
  following?: boolean;
}

interface WeiboPictureJson {
  type?: string;
  videoSrc?: string;
  video?: string;
  url?: string;
  large?: WeiboPictureSizeJson;
  largest?: WeiboPictureSizeJson;
  mw2000?: WeiboPictureSizeJson;
  original?: WeiboPictureSizeJson;
}

interface WeiboPictureSizeJson {
  url?: string;
}

/** Desktop surfaces return one of these per picture inside the `pic_infos` map. */
interface WeiboPictureInfoJson {
  type?: string;
  video?: string;
  videoSrc?: string;
  thumbnail?: WeiboPictureSizeJson;
  bmiddle?: WeiboPictureSizeJson;
  large?: WeiboPictureSizeJson;
  original?: WeiboPictureSizeJson;
  largest?: WeiboPictureSizeJson;
  mw2000?: WeiboPictureSizeJson;
  largecover?: WeiboPictureSizeJson;
}

/** The video URL variants used by the mobile status API. */
interface WeiboVideoUrlsJson {
  mp4_1080p_60fps?: string;
  mp4_1080p_mp4?: string;
  mp4_hd_mp4?: string;
  mp4_720p_mp4?: string;
  mp4_sd_mp4?: string;
  mp4_ld_mp4?: string;
}

interface WeiboVideoMediaInfoJson {
  stream_url_hd?: string;
  stream_url?: string;
  stream_url_h5?: string;
  width?: string | number;
  height?: string | number;
  video_width?: string | number;
  video_height?: string | number;
  mp4_hd_mp4?: string;
  mp4_720p_mp4?: string;
  /** Desktop video pages carry the full-size poster here. */
  big_pic_info?: WeiboPagePictureInfoJson;
}

interface WeiboPagePictureJson {
  url?: string;
  width?: string | number;
  height?: string | number;
}

/** One size entry of a video poster, used by `pic_info` and `big_pic_info`. */
interface WeiboPagePictureSizeJson {
  url?: string;
  width?: string | number;
  height?: string | number;
}

/** Video posters ship as three named sizes instead of one flat url. */
interface WeiboPagePictureInfoJson {
  pic_big?: WeiboPagePictureSizeJson;
  pic_middle?: WeiboPagePictureSizeJson;
  pic_small?: WeiboPagePictureSizeJson;
}

interface WeiboPageInfoJson {
  type?: string;
  object_type?: string;
  urls?: WeiboVideoUrlsJson;
  media_info?: WeiboVideoMediaInfoJson;
  /**
   * Mobile containers nest the poster as `{ url }`, desktop pages send a bare
   * url string. Reading only the nested form leaves every desktop video card
   * without a poster.
   */
  page_pic?: WeiboPagePictureJson | string;
  pic_info?: WeiboPagePictureInfoJson;
}

interface WeiboLongTextJson {
  longTextContent?: string;
}

interface WeiboUrlStructJson {
  url_title?: string;
  url_type_pic?: string;
  ori_url?: string;
  short_url?: string;
  long_url?: string;
  url_type?: number | string;
}

interface WeiboPostJson {
  /** Prefer string IDs over JSON numbers to preserve precision. */
  idstr?: string;
  id?: string | number;
  mid?: string | number;
  text?: string;
  /** Desktop responses often include the same body without presentation markup. */
  text_raw?: string;
  /** Mobile and desktop feeds mark a shortened timeline body with this field. */
  isLongText?: boolean;
  longText?: WeiboLongTextJson;
  created_at?: string;
  source?: string;
  attitudes_count?: number;
  comments_count?: number;
  reposts_count?: number;
  attitudes_status?: number;
  favorited?: boolean;
  user?: WeiboUserJson;
  /** Mobile containers ship a ready-made picture list. */
  pics?: WeiboPictureJson[];
  /** Desktop surfaces ship ordered ids plus a `pic_infos` map and no `pics`. */
  pic_ids?: string[];
  pic_infos?: Record<string, WeiboPictureInfoJson>;
  page_info?: WeiboPageInfoJson;
  video_url?: string;
  url_struct?: WeiboUrlStructJson[];
  /** Legacy pre-`pic_ids` picture fields. */
  original_pic?: string;
  bmiddle_pic?: string;
  thumbnail_pic?: string;
  retweeted_status?: WeiboPostJson;
}

interface WeiboRepliesResponse {
  ok?: number;
  msg?: string;
  data?: WeiboCommentJson[];
  max_id?: string | number;
}

interface WeiboCommentJson {
  idstr?: string;
  id?: string | number;
  text?: string;
  created_at?: string;
  like_count?: number;
  like_counts?: number;
  liked?: boolean | number;
  user?: WeiboUserJson;
  comments?: WeiboCommentJson[];
  total_number?: number;
  reply_comment?: WeiboCommentJson;
  pic?: WeiboPictureJson;
  pics?: WeiboPictureJson[];
}

/**
 * Adapter for public mobile containers and user-initiated post actions.
 * Endpoint responses are deliberately mapped to small app-owned models, so UI
 * code is insulated from undocumented response-shape changes.
 */
export class WeiboService {
  private static instance: WeiboService | null = null;
  private recentPost: WeiboPost | null = null;
  private cacheRevision: number = -1;
  /** One detail page can consume the comment request already started by its card. */
  private recentCommentsPostId: string = '';
  private recentComments: WeiboCommentsPage | null = null;
  private recentCommentsSort: WeiboCommentSort = WeiboCommentSort.Hot;
  private pendingCommentsPostId: string = '';
  private pendingCommentsSort: WeiboCommentSort = WeiboCommentSort.Hot;
  private pendingComments: Promise<WeiboCommentsPage> | null = null;
  private commentsGeneration: number = 0;

  static getInstance(): WeiboService {
    if (WeiboService.instance === null) {
      WeiboService.instance = new WeiboService();
    }
    WeiboService.instance.syncSessionCache();
    return WeiboService.instance;
  }

  private syncSessionCache(): void {
    const revision: number = WeiboAuthManager.getInstance().getSessionRevision();
    if (this.cacheRevision === revision) { return; }
    this.cacheRevision = revision;
    this.commentsGeneration++;
    this.recentPost = null;
    this.recentComments = null;
    this.recentCommentsPostId = '';
    this.pendingComments = null;
    this.pendingCommentsPostId = '';
  }

  /** Warms the API 24 RCP connection while local auth/settings initialization is running. */
  preconnectTimeline(): void {
    WeiboHttpClient.preconnectMobile();
  }

  async resolveUserIdByName(name: string): Promise<string> {
    const clean: string = name.trim();
    if (clean.length === 0) {
      return '';
    }
    try {
      const raw: string = await this.get(
        `https://m.weibo.cn/api/container/getIndex?containerid=100103type%3D3%26q%3D${encodeURIComponent(clean)}&page_type=searchall`);
      const parsed: WeiboApiResponse = this.parseResponse(raw);
      const cards: WeiboCardJson[] = parsed.data?.cards ?? [];
      for (let i: number = 0; i < cards.length; i++) {
        const card: WeiboCardJson = cards[i];
        if (card.card_group !== undefined) {
          for (let j: number = 0; j < card.card_group.length; j++) {
            const sub: WeiboCardJson = card.card_group[j];
            if (sub.user?.screen_name === clean && (sub.user.idstr !== undefined || sub.user.id !== undefined)) {
              return `${sub.user.idstr ?? sub.user.id}`;
            }
          }
        }
        if (card.user?.screen_name === clean && (card.user.idstr !== undefined || card.user.id !== undefined)) {
          return `${card.user.idstr ?? card.user.id}`;
        }
      }
    } catch (_e) {}
    return '';
  }

  async followUser(userId: string): Promise<void> {
    const id: string = userId.trim();
    const cookie: string = this.requireAccountCookie();
    if (id.length === 0) {
      throw new Error('用户 ID 不能为空');
    }
    const form: rcp.Form = new rcp.Form({ uid: id });
    form.keys = ['uid'];
    const raw: string = await WeiboHttpClient.postForm('https://m.weibo.cn/api/friendships/create', cookie, form);
    this.parseResponse(raw);
  }

  async unfollowUser(userId: string): Promise<void> {
    const id: string = userId.trim();
    const cookie: string = this.requireAccountCookie();
    if (id.length === 0) {
      throw new Error('用户 ID 不能为空');
    }
    const form: rcp.Form = new rcp.Form({ uid: id });
    form.keys = ['uid'];
    // Mobile Weibo really spells this endpoint `destory`. Never replay an
    // ambiguous mutation failure against another endpoint.
    const raw: string = await WeiboHttpClient.postForm('https://m.weibo.cn/api/friendships/destory', cookie, form);
    this.parseResponse(raw);
  }

  async fetchUserProfile(userId: string): Promise<WeiboUser> {
    const escapedUserId: string = encodeURIComponent(userId.trim());
    const raw: string = await this.get(`https://m.weibo.cn/api/container/getIndex?containerid=100505${escapedUserId}`);
    const response: WeiboApiResponse = this.parseResponse(raw);
    const user: WeiboUserJson | undefined = response.data?.userInfo;
    if (user === undefined) {
      throw new Error('微博没有返回用户资料');
    }
    return this.toUser(user);
  }

  /** Resolve the profile, including the HD avatar, for the account in the saved Cookie. */
  async fetchCurrentUserProfile(): Promise<WeiboUser> {
    const cookie: string = this.requireAccountCookie();
    const raw: string = await WeiboHttpClient.get('https://m.weibo.cn/api/config', cookie);
    let config: WeiboConfigResponse;
    try {
      config = JSON.parse(raw) as WeiboConfigResponse;
    } catch (error) {
      throw new Error('微博返回了无法解析的登录资料');
    }
    const data: WeiboConfigData | undefined = config.data;
    const uid: string = data?.uid?.trim() ?? '';
    if (config.ok !== 1 || data === undefined || !data.login || uid.length === 0) {
      const message: string = config.msg?.trim() ?? '';
      throw new Error(message.length > 0 ? message : '微博未接受当前登录态，请重新登录后再试');
    }
    return await this.fetchUserProfile(uid);
  }

  async fetchUserTimeline(userId: string, page: number): Promise<WeiboPost[]> {
    const escapedUserId: string = encodeURIComponent(userId.trim());
    const safePage: number = page < 1 ? 1 : page;
    const raw: string = await this.get(
      `https://m.weibo.cn/api/container/getIndex?containerid=230413${escapedUserId}&page=${safePage}&count=20`);
    const response: WeiboApiResponse = this.parseResponse(raw);
    const cards: WeiboCardJson[] = response.data?.cards ?? [];
    const posts: WeiboPost[] = [];
    for (let index: number = 0; index < cards.length; index++) {
      const card: WeiboCardJson = cards[index];
      if (card.card_type === 9 && card.mblog !== undefined) {
        posts.push(this.toPost(card.mblog));
      }
    }
    return posts;
  }

  async fetchFavorites(page: number, userId: string = ''): Promise<WeiboPost[]> {
    const cookie: string = this.requireAccountCookie();
    const safePage: number = Math.max(1, page);
    let url: string = `https://weibo.com/ajax/favorites/all_fav?page=${safePage}`;
    if (userId.trim().length > 0) {
      url += `&uid=${encodeURIComponent(userId.trim())}`;
    }
    try {
      const raw: string = await WeiboHttpClient.getDesktop(url, cookie);
      const trimmed: string = raw.trim();
      if (trimmed.startsWith('<!DOCTYPE') || trimmed.startsWith('<html') || trimmed.includes('passport.weibo.com') || trimmed.includes('visitor.passport.weibo.cn')) {
        throw new Error('微博未接受当前登录态，请重新登录后再试');
      }
      const parsed: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
      if (parsed['ok'] !== undefined && Number(parsed['ok']) !== 1) {
        const msg: string = `${parsed['msg'] ?? '获取收藏列表失败'}`;
        throw new Error(msg);
      }
      const dataObj: Record<string, Object> = (typeof parsed['data'] === 'object' && parsed['data'] !== null && !Array.isArray(parsed['data']))
        ? parsed['data'] as Record<string, Object> : {};
      const list: Object[] = (Array.isArray(parsed['data']) ? parsed['data'] :
        (dataObj['list'] ?? dataObj['data'] ?? [])) as Object[];
      if (!Array.isArray(list)) { throw new Error('收藏列表数据格式异常，请稍后重试'); }
      const posts: WeiboPost[] = [];
      for (const entry of list) {
        const item: Record<string, Object> = entry as Record<string, Object>;
        const mblog: WeiboPostJson = (item['mblog'] ?? item['status'] ?? item) as WeiboPostJson;
        if (mblog && (mblog.id !== undefined || mblog.idstr !== undefined || mblog.mid !== undefined)) {
          const post: WeiboPost = this.toPost(mblog);
          post.isFavorited = true;
          posts.push(post);
        }
      }
      return posts;
    } catch (desktopError) {
      // Fallback: Mobile endpoint
      try {
        const mobileRaw: string = await this.get(`https://m.weibo.cn/api/favorites/all_fav?page=${safePage}`);
        return this.postsFromResponse(mobileRaw);
      } catch (_mobileError) {
        if (desktopError instanceof Error) {
          throw desktopError;
        }
        throw new Error('获取收藏列表失败，请稍后重试');
      }
    }
  }

  async fetchLikes(userId: string, page: number): Promise<WeiboPost[]> {
    const cookie: string = this.requireAccountCookie();
    const uid: string = userId.trim();
    if (uid.length === 0) { throw new Error('当前账号资料未就绪，请重新登录'); }
    const safePage: number = Math.max(1, page);
    // Lowercase `likelist` is the account's liked-post history, not a post's likers.
    const raw: string = await WeiboHttpClient.getDesktop(
      `https://weibo.com/ajax/statuses/likelist?uid=${encodeURIComponent(uid)}&page=${safePage}&with_total=true`, cookie);
    const trimmed: string = raw.trim();
    if (trimmed.startsWith('<!DOCTYPE') || trimmed.startsWith('<html') || trimmed.includes('passport.weibo.com') || trimmed.includes('visitor.passport.weibo.cn')) {
      throw new Error('微博未接受当前登录态，请重新登录后再试');
    }
    const parsed: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
    if (parsed['ok'] !== undefined && Number(parsed['ok']) !== 1) {
      const msg: string = `${parsed['msg'] ?? '获取点赞列表失败'}`;
      throw new Error(msg);
    }
    const dataObj: Record<string, Object> = (typeof parsed['data'] === 'object' && parsed['data'] !== null && !Array.isArray(parsed['data']))
      ? parsed['data'] as Record<string, Object> : {};
    const list: WeiboPostJson[] = (Array.isArray(parsed['data']) ? parsed['data'] :
      (dataObj['statuses'] ?? dataObj['list'] ?? dataObj['data'] ?? [])) as WeiboPostJson[];
    if (!Array.isArray(list)) { throw new Error('点赞列表数据格式异常，请稍后重试'); }
    const posts: WeiboPost[] = [];
    for (const mblog of list) {
      if (mblog && (mblog.id !== undefined || mblog.idstr !== undefined || mblog.mid !== undefined)) {
        const post: WeiboPost = this.toPost(mblog);
        post.isLiked = true;
        posts.push(post);
      }
    }
    return posts;
  }

  /** Public recommendation timeline used by the first tab. */
  async fetchRecommendTimeline(page: number): Promise<WeiboPost[]> {
    const safePage: number = page < 1 ? 1 : page;
    const raw: string = await this.get(
      `https://m.weibo.cn/api/container/getIndex?containerid=102803&page=${safePage}`);
    return this.postsFromResponse(raw);
  }

  /**
   * The logged-in account's following timeline. The mobile `231093` container
   * lists followed users, while this desktop feed returns their actual posts.
   */
  async fetchFollowingTimeline(maxId: string): Promise<WeiboTimelinePage> {
    const cookie: string = this.requireAccountCookie();
    const cursor: string = maxId.trim().length > 0 ? maxId.trim() : '0';
    const raw: string = await WeiboHttpClient.getDesktop(
      `https://weibo.com/ajax/feed/friendstimeline?count=20&max_id=${encodeURIComponent(cursor)}`, cookie);
    return this.followingPageFromResponse(raw, cursor);
  }

  async fetchNotifications(type: 'all' | 'mention' | 'comment' | 'like', page: number = 1): Promise<WeiboNotification[]> {
    if (type === 'all') {
      try {
        const results: WeiboNotification[][] = await Promise.all([
          this.fetchNotifications('mention', page).catch((): WeiboNotification[] => []),
          this.fetchNotifications('comment', page).catch((): WeiboNotification[] => []),
          this.fetchNotifications('like', page).catch((): WeiboNotification[] => [])
        ]);
        const mentions: WeiboNotification[] = results[0];
        const comments: WeiboNotification[] = results[1];
        const likes: WeiboNotification[] = results[2];
        const merged: WeiboNotification[] = mentions.concat(comments).concat(likes);
        merged.sort((a: WeiboNotification, b: WeiboNotification): number =>
          (b.createdAt || '').localeCompare(a.createdAt || ''));
        return merged;
      } catch (_e) {
        return this.fetchNotifications('comment', page);
      }
    }
    const cookie: string = this.requireAccountCookie();
    let url: string = '';
    const safePage: number = Math.max(1, page);
    if (type === 'mention') {
      url = `https://weibo.com/ajax/statuses/mentions?page=${safePage}`;
    } else if (type === 'comment') {
      url = `https://weibo.com/ajax/comments/to_me?page=${safePage}`;
    } else {
      url = `https://weibo.com/ajax/statuses/attitude?page=${safePage}`;
    }
    const raw: string = await WeiboHttpClient.getDesktop(url, cookie);
    const trimmed: string = raw.trim();
    if (trimmed.startsWith('<!DOCTYPE') || trimmed.startsWith('<html') || trimmed.includes('passport.weibo.com') || trimmed.includes('visitor.passport.weibo.cn')) {
      throw new Error('微博未接受当前登录态，请重新登录后再试');
    }
    const parsed: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
    if (parsed['ok'] !== undefined && Number(parsed['ok']) !== 1) {
      const msg: string = `${parsed['msg'] ?? '获取消息通知失败'}`;
      throw new Error(msg);
    }
    const data: Object = parsed['data'] ?? [];
    const dataObj: Record<string, Object> = (typeof data === 'object' && data !== null && !Array.isArray(data))
      ? data as Record<string, Object> : {};
    const list: Record<string, Object>[] = (Array.isArray(data) ? data :
      (dataObj['data'] ?? dataObj['messages'] ?? dataObj['list'] ?? parsed['statuses'] ?? parsed['comments'] ?? parsed['attitudes'] ?? [])) as Record<string, Object>[];
    if (!Array.isArray(list)) { return []; }
    const result: WeiboNotification[] = [];
    for (let i = 0; i < list.length; i++) {
      const item: Record<string, Object> = list[i];
      const userObj: Record<string, Object> = (item['user'] ?? {}) as Record<string, Object>;
      const rawId: Object = item['idstr'] ?? item['id'] ?? `${page}_${i}`;
      const senderId: string = `${userObj['idstr'] ?? userObj['id'] ?? ''}`;
      const senderName: string = `${userObj['screen_name'] ?? '微博用户'}`;
      const senderAvatar: string = `${userObj['profile_image_url'] ?? userObj['avatar_hd'] ?? ''}`;
      const text: string = normalizeWeiboText(`${item['text'] ?? item['text_raw'] ?? item['content'] ?? ''}`);
      const statusObj: Record<string, Object> = (item['status'] ?? item['reply_comment'] ?? item['mblog'] ??
        (type === 'mention' ? item : {})) as Record<string, Object>;
      const targetSnippet: string = normalizeWeiboText(`${statusObj['text'] ?? statusObj['text_raw'] ?? statusObj['content'] ?? ''}`);
      const targetPostId: string = `${statusObj['idstr'] ?? statusObj['id'] ?? statusObj['mid'] ?? ''}`;
      const createdAt: string = formatWeiboTime(`${item['created_at'] ?? ''}`);
      let titleDesc: string = '与你互动';
      if (type === 'mention') {
        titleDesc = '提到了你';
      } else if (type === 'comment') {
        titleDesc = '评论了你';
      } else if (type === 'like') {
        titleDesc = '赞了你的微博';
      }
      result.push({
        id: `${type}_${rawId}`,
        senderId: senderId,
        senderName: senderName,
        senderAvatar: senderAvatar,
        type: type,
        title: titleDesc,
        content: text,
        targetSnippet: targetSnippet,
        targetPostId: targetPostId,
        createdAt: createdAt
      });
    }
    return result;
  }

  /**
   * Search posts through Weibo's mobile search container. It uses the same
   * account-or-visitor session as the timeline, so public results work before
   * login and a saved Cookie can return the user's normal search results.
   */
  async fetchSearchPosts(query: string, page: number): Promise<WeiboPost[]> {
    const cleanQuery: string = query.trim();
    if (cleanQuery.length === 0) {
      return [];
    }
    const safePage: number = page < 1 ? 1 : page;
    const containerId: string = `100103type%3D1%26q%3D${encodeURIComponent(cleanQuery)}`;
    const raw: string = await this.get(
      `https://m.weibo.cn/api/container/getIndex?containerid=${containerId}&page_type=searchall&page=${safePage}`);
    return this.postsFromResponse(raw);
  }

  /**
   * Resolves a single post for a routed detail page. The in-memory copy makes
   * the transition immediate; this endpoint is the fallback after recreation.
   */
  async fetchPost(postId: string): Promise<WeiboPost> {
    const id: string = postId.trim();
    if (id.length === 0) {
      throw new Error('微博信息不完整，无法打开详情');
    }
    const auth: WeiboAuthManager = WeiboAuthManager.getInstance();
    const revision: number = auth.getSessionRevision();

    // 1. Try mobile statuses/show
    try {
      const raw: string = await this.get(`https://m.weibo.cn/statuses/show?id=${encodeURIComponent(id)}`);
      auth.assertSession(revision);
      this.parseResponse(raw);
      const response: WeiboStatusApiResponse = JSON.parse(raw) as WeiboStatusApiResponse;
      if (response.data !== undefined) {
        const post: WeiboPost = this.toPost(response.data);
        this.rememberPost(post);
        return post;
      }
    } catch (error) {
      if (error instanceof Error && error.message.includes('账号会话')) {
        throw error;
      }
    }

    // 2. Fallback to desktop statuses/show
    try {
      const cookie: string = auth.getCookie().length > 0 ? auth.getCookie() : WeiboVisitorSession.getInstance().getCookie();
      const raw: string = await WeiboHttpClient.getDesktop(
        `https://weibo.com/ajax/statuses/show?id=${encodeURIComponent(id)}`, cookie);
      auth.assertSession(revision);
      const trimmed: string = raw.trim();
      if (!trimmed.startsWith('<!DOCTYPE') && !trimmed.startsWith('<html') && !trimmed.includes('passport.weibo.com') && !trimmed.includes('visitor.passport.weibo.cn')) {
        const parsed: WeiboPostJson = JSON.parse(raw) as WeiboPostJson;
        if (parsed.id !== undefined || parsed.idstr !== undefined || parsed.mid !== undefined) {
          const post: WeiboPost = this.toPost(parsed);
          this.rememberPost(post);
          return post;
        }
      }
    } catch (error) {
      if (error instanceof Error && error.message.includes('账号会话')) {
        throw error;
      }
    }

    throw new Error('微博没有返回帖子详情');
  }

  /** Resolve the complete body behind a timeline's inert HTML “展开” anchor. */
  async fetchLongText(postId: string): Promise<string> {
    const id: string = postId.trim();
    if (id.length === 0) {
      throw new Error('微博信息不完整，无法展开全文');
    }
    const numericId: string = /^\d+$/.test(id) ? id : bidToMid(id);
    const bid: string = /^\d+$/.test(id) ? midToBid(id) : id;
    const auth: WeiboAuthManager = WeiboAuthManager.getInstance();
    const revision: number = auth.getSessionRevision();
    const cookie: string = auth.getCookie().length > 0 ? auth.getCookie() : WeiboVisitorSession.getInstance().getCookie();

    // 1. Mobile statuses/extend endpoint (most reliable across networks and visitor sessions)
    const mobileTargets: string[] = [numericId];
    if (bid.length > 0 && bid !== numericId) {
      mobileTargets.push(bid);
    }
    for (let i: number = 0; i < mobileTargets.length; i++) {
      const targetId: string = mobileTargets[i];
      try {
        const referer: string = `https://m.weibo.cn/detail/${targetId}`;
        const raw: string = await this.get(`https://m.weibo.cn/statuses/extend?id=${encodeURIComponent(targetId)}`, referer);
        auth.assertSession(revision);
        const trimmed: string = raw.trim();
        if (!trimmed.startsWith('<!DOCTYPE') && !trimmed.startsWith('<html')) {
          const response: WeiboApiResponse = JSON.parse(raw) as WeiboApiResponse;
          const content: string = response.data?.longTextContent ?? '';
          const text: string = normalizeWeiboText(content).trim();
          if (text.length > 0) {
            return text;
          }
        }
      } catch (error) {
        if (error instanceof Error && error.message.includes('账号会话')) {
          throw error;
        }
      }
    }

    // 2. Desktop ajax/statuses/longtext endpoint with bid (Weibo desktop requires mblogid / bid)
    const desktopTargets: string[] = bid.length > 0 && bid !== numericId ? [bid, numericId] : [numericId];
    for (let i: number = 0; i < desktopTargets.length; i++) {
      const targetId: string = desktopTargets[i];
      try {
        const raw: string = await WeiboHttpClient.getDesktop(
          `https://weibo.com/ajax/statuses/longtext?id=${encodeURIComponent(targetId)}`, cookie);
        auth.assertSession(revision);
        const trimmed: string = raw.trim();
        if (!trimmed.startsWith('<!DOCTYPE') && !trimmed.startsWith('<html') && !trimmed.includes('passport.weibo.com') && !trimmed.includes('visitor.passport.weibo.cn')) {
          const response: WeiboApiResponse = JSON.parse(raw) as WeiboApiResponse;
          const content: string = response.data?.longTextContent ?? '';
          const text: string = normalizeWeiboText(content).trim();
          if (text.length > 0) {
            return text;
          }
        }
      } catch (error) {
        if (error instanceof Error && error.message.includes('账号会话')) {
          throw error;
        }
      }
    }

    // 3. Desktop ajax/statuses/show endpoint - ONLY return if longText is explicitly present
    for (let i: number = 0; i < desktopTargets.length; i++) {
      const targetId: string = desktopTargets[i];
      try {
        const raw: string = await WeiboHttpClient.getDesktop(
          `https://weibo.com/ajax/statuses/show?id=${encodeURIComponent(targetId)}`, cookie);
        auth.assertSession(revision);
        const trimmed: string = raw.trim();
        if (!trimmed.startsWith('<!DOCTYPE') && !trimmed.startsWith('<html') && !trimmed.includes('passport.weibo.com') && !trimmed.includes('visitor.passport.weibo.cn')) {
          const parsed: WeiboPostJson = JSON.parse(raw) as WeiboPostJson;
          const longContent: string = parsed.longText?.longTextContent ?? '';
          if (longContent.length > 0) {
            return normalizeWeiboText(longContent).trim();
          }
        }
      } catch (error) {
        if (error instanceof Error && error.message.includes('账号会话')) {
          throw error;
        }
      }
    }

    // 4. Mobile statuses/show endpoint with detail Referer - ONLY return if longText is explicitly present
    for (let i: number = 0; i < mobileTargets.length; i++) {
      const targetId: string = mobileTargets[i];
      try {
        const referer: string = `https://m.weibo.cn/detail/${targetId}`;
        const raw: string = await this.get(`https://m.weibo.cn/statuses/show?id=${encodeURIComponent(targetId)}`, referer);
        auth.assertSession(revision);
        const trimmed: string = raw.trim();
        if (!trimmed.startsWith('<!DOCTYPE') && !trimmed.startsWith('<html')) {
          const parsed: WeiboStatusApiResponse = JSON.parse(raw) as WeiboStatusApiResponse;
          if (parsed.data !== undefined) {
            const longContent: string = parsed.data.longText?.longTextContent ?? '';
            if (longContent.length > 0) {
              return normalizeWeiboText(longContent).trim();
            }
          }
        }
      } catch (error) {
        if (error instanceof Error && error.message.includes('账号会话')) {
          throw error;
        }
      }
    }

    throw new Error('未能获取到完整微博内容，请稍后重试');
  }

  rememberPost(post: WeiboPost): void {
    this.syncSessionCache();
    this.recentPost = post;
  }

  getRememberedPost(postId: string): WeiboPost | null {
    this.syncSessionCache();
    if (this.recentPost === null || this.recentPost.id !== postId) {
      return null;
    }
    return this.recentPost;
  }

  invalidateComments(postId: string): void {
    this.commentsGeneration++;
    if (this.recentCommentsPostId === postId) {
      this.recentComments = null;
      this.recentCommentsPostId = '';
    }
    if (this.pendingCommentsPostId === postId) {
      this.pendingComments = null;
      this.pendingCommentsPostId = '';
    }
  }

  async fetchCommentReplies(commentId: string, maxId: string = '0'): Promise<WeiboCommentsPage> {
    const raw: string = await this.get(`https://m.weibo.cn/comments/hotFlowChild?cid=${encodeURIComponent(commentId)}&max_id=${encodeURIComponent(maxId)}&max_id_type=0`);
    const response: WeiboRepliesResponse = this.parseCommentResponse(raw);
    if (response.ok === 0) {
      throw new Error(response.msg ?? '回复加载失败');
    }
    const items: WeiboComment[] = [];
    for (const source of response.data ?? []) {
      items.push(this.toComment(source));
    }
    const cursor: string = `${response.max_id ?? '0'}`;
    return { items: items, nextMaxId: cursor, hasMore: cursor !== '0' && cursor !== maxId && items.length > 0 };
  }

  async fetchComments(postId: string, page: number, sort: WeiboCommentSort = WeiboCommentSort.Hot,
    maxId: string = '0'): Promise<WeiboCommentsPage> {
    this.syncSessionCache();
    const revision: number = this.cacheRevision;
    const generation: number = this.commentsGeneration;
    const id: string = postId.trim();
    const safePage: number = page < 1 ? 1 : page;
    if (safePage > 1 && (maxId.length === 0 || maxId === '0')) { throw new Error('评论分页游标已失效，请重新加载'); }
    if (safePage === 1 && this.recentComments !== null && this.recentCommentsPostId === id && this.recentCommentsSort === sort) {
      return this.recentComments;
    }
    if (safePage === 1 && this.pendingComments !== null && this.pendingCommentsPostId === id && this.pendingCommentsSort === sort) {
      return await this.pendingComments;
    }
    const request: Promise<WeiboCommentsPage> = this.fetchCommentsPage(id, sort, safePage === 1 ? '0' : maxId);
    if (safePage !== 1) {
      return await request;
    }
    this.pendingCommentsPostId = id;
    this.pendingCommentsSort = sort;
    this.pendingComments = request;
    try {
      const result: WeiboCommentsPage = await request;
      WeiboAuthManager.getInstance().assertSession(revision);
      if (generation === this.commentsGeneration && this.pendingComments === request) {
        this.recentCommentsPostId = id;
        this.recentCommentsSort = sort;
        this.recentComments = result;
      }
      return result;
    } finally {
      if (this.pendingComments === request) {
        this.pendingCommentsPostId = '';
        this.pendingComments = null;
      }
    }
  }

  /** Starts comments during the route transition; failures remain silent until the detail page needs them. */
  prefetchComments(postId: string, sort: WeiboCommentSort = WeiboCommentSort.Hot): void {
    this.syncSessionCache();
    const id: string = postId.trim();
    if (id.length === 0 || (this.recentComments !== null && this.recentCommentsPostId === id && this.recentCommentsSort === sort)
      || (this.pendingComments !== null && this.pendingCommentsPostId === id && this.pendingCommentsSort === sort)) {
      return;
    }
    const task: Promise<WeiboCommentsPage> = this.fetchComments(id, 1, sort);
    task.then(
      (): void => {},
      (): void => {}
    );
  }

  private parseCommentResponse(raw: string): WeiboRepliesResponse {
    // Root comments, child replies and cursors all use IDs beyond JSON's safe integer range.
    const exact: string = raw.replace(/"(id|max_id)"\s*:\s*(\d{16,})(?=\s*[,}])/g, '"$1":"$2"');
    return JSON.parse(exact) as WeiboRepliesResponse;
  }

  private async fetchCommentsPage(postId: string, sort: WeiboCommentSort, maxId: string): Promise<WeiboCommentsPage> {
    const auth: WeiboAuthManager = WeiboAuthManager.getInstance();
    const revision: number = auth.getSessionRevision();
    const cookie: string = auth.getCookie() || WeiboVisitorSession.getInstance().getCookie();
    // flow=0 is heat, flow=1 is reverse chronological order. Preserve server order.
    const raw: string = await WeiboHttpClient.getDesktop(
      `https://weibo.com/ajax/statuses/buildComments?id=${encodeURIComponent(postId)}&flow=${sort}`
        + `&is_reload=1&is_show_bulletin=2&is_mix=0&count=20&max_id=${encodeURIComponent(maxId)}`, cookie);
    auth.assertSession(revision);
    this.parseResponse(raw);
    const response: WeiboRepliesResponse = this.parseCommentResponse(raw);
    if (!Array.isArray(response.data)) { throw new Error('微博返回了无法解析的评论列表'); }
    const items: WeiboComment[] = [];
    for (const source of response.data) { items.push(this.toComment(source)); }
    const nextMaxId: string = `${response.max_id ?? '0'}`;
    return { items: items, nextMaxId: nextMaxId, hasMore: items.length > 0 && nextMaxId !== '0' && nextMaxId !== maxId };
  }

  /** Like or cancel a like. This is never called automatically. */
  async setLike(postId: string, like: boolean): Promise<void> {
    const id: string = postId.trim();
    const cookie: string = this.requireAccountCookie();
    if (id.length === 0) {
      throw new Error('微博信息不完整，无法点赞');
    }
    const form: rcp.Form = new rcp.Form({ id: id });
    form.keys = ['id'];
    const endpoint: string = like
      ? 'https://weibo.com/ajax/statuses/setLike'
      : 'https://weibo.com/ajax/statuses/cancelLike';
    const raw: string = await WeiboHttpClient.postForm(endpoint, cookie, form);
    this.parseResponse(raw);
  }

  async setFavorite(postId: string, favorite: boolean): Promise<void> {
    const cookie: string = this.requireAccountCookie();
    if (postId.trim().length === 0) { throw new Error('微博信息不完整，无法收藏'); }
    const form: rcp.Form = new rcp.Form({ id: postId.trim() });
    form.keys = ['id'];
    const url: string = favorite ? 'https://m.weibo.cn/api/statuses/createfav' : 'https://m.weibo.cn/api/statuses/destroyfav';
    this.parseResponse(await WeiboHttpClient.postForm(url, cookie, form));
  }

  /** Like or cancel like on a specific comment. */
  async setCommentLike(commentId: string, like: boolean): Promise<void> {
    const id: string = commentId.trim();
    const cookie: string = this.requireAccountCookie();
    if (id.length === 0) {
      throw new Error('评论信息不完整，无法点赞');
    }
    const form: rcp.Form = new rcp.Form({ id: id, type: 'comment' });
    form.keys = ['id', 'type'];
    const endpoint: string = like
      ? 'https://m.weibo.cn/api/likes/update'
      : 'https://m.weibo.cn/api/likes/destroy';
    // Do not retry a mutation on another endpoint after an ambiguous failure.
    this.parseResponse(await WeiboHttpClient.postForm(endpoint, cookie, form));
  }

  /** Publish one user-authored comment after the user presses Send. */
  async publishComment(postId: string, content: string, replyCommentId?: string, pictureId: string = ''): Promise<void> {
    const id: string = postId.trim();
    const cleanContent: string = content.trim().length > 0 ? content.trim() : (pictureId.length > 0 ? '[图片]' : '');
    const cookie: string = this.requireAccountCookie();
    if (id.length === 0 || cleanContent.length === 0) {
      throw new Error('评论内容不能为空');
    }
    const formValues: rcp.FormFields = { id: id, mid: id, content: cleanContent };
    const formKeys: string[] = ['id', 'mid', 'content'];
    if (pictureId.length > 0) { formValues['picId'] = pictureId; formKeys.push('picId'); }
    if (replyCommentId !== undefined && replyCommentId.trim().length > 0) {
      formValues['cid'] = replyCommentId.trim();
      formValues['reply'] = replyCommentId.trim();
      formKeys.push('cid', 'reply');
    }
    const form: rcp.Form = new rcp.Form(formValues);
    form.keys = formKeys;
    const endpoint: string = replyCommentId === undefined
      ? 'https://m.weibo.cn/api/comments/create' : 'https://m.weibo.cn/api/comments/reply';
    const raw: string = await WeiboHttpClient.postForm(endpoint, cookie, form);
    this.parseResponse(raw);
    this.invalidateComments(id);
  }

  /** Publish a new status/weibo. */
  async uploadPicture(uri: string): Promise<string> {
    const cookie: string = this.requireAccountCookie();
    const revision: number = WeiboAuthManager.getInstance().getSessionRevision();
    const picture: WeiboUploadImage = await prepareWeiboImage(uri);
    WeiboAuthManager.getInstance().assertSession(revision);
    const form: rcp.MultipartForm = new rcp.MultipartForm({
      type: 'json',
      pic: { contentType: picture.mimeType, remoteFileName: picture.fileName, contentOrPath: { content: picture.data } }
    });
    form.keys = ['type', 'pic'];
    const raw: string = await WeiboHttpClient.postForm('https://m.weibo.cn/api/statuses/uploadPic', cookie, form);
    const result: WeiboUploadResponse = JSON.parse(raw) as WeiboUploadResponse;
    const id: string = result.pic_id ?? result.data?.pic_id ?? '';
    if (result.ok === 0 || id.length === 0) { throw new Error(result.msg ?? '图片上传失败，请重试'); }
    return id;
  }

  async publishPost(content: string, pictureIds: string[] = []): Promise<void> {
    const cleanContent: string = content.trim();
    const cookie: string = this.requireAccountCookie();
    if (cleanContent.length === 0) {
      throw new Error('微博内容不能为空');
    }
    if (pictureIds.length > 9) { throw new Error('最多发布 9 张图片'); }
    const formValues: rcp.FormFields = { content: cleanContent };
    if (pictureIds.length > 0) { formValues['picId'] = pictureIds.join(','); }
    const form: rcp.Form = new rcp.Form(formValues);
    form.keys = Object.keys(formValues);
    // Never replay publishing on a second endpoint after an ambiguous network failure.
    const raw: string = await WeiboHttpClient.postForm('https://m.weibo.cn/api/statuses/update', cookie, form);
    this.parseResponse(raw);
  }

  /** Repost an existing weibo with optional text and whether to also comment. */
  async repostPost(postId: string, content: string, commentAlso: boolean = false): Promise<void> {
    const id: string = postId.trim();
    const cleanContent: string = content.trim();
    const cookie: string = this.requireAccountCookie();
    if (id.length === 0) {
      throw new Error('原微博信息不完整，无法转发');
    }
    const formValues: rcp.FormFields = {
      id: id,
      content: cleanContent.length > 0 ? cleanContent : '转发微博',
      dualPost: commentAlso ? '1' : '0'
    };
    const form: rcp.Form = new rcp.Form(formValues);
    form.keys = ['id', 'content', 'dualPost'];
    const raw: string = await WeiboHttpClient.postForm('https://m.weibo.cn/api/statuses/repost', cookie, form);
    this.parseResponse(raw);
  }

  /**
   * Public hot-search board. It is intentionally kept separate from the mobile
   * session endpoints, so it can work without the user's account cookie.
   */
  async fetchHotTopics(limit: number): Promise<WeiboHotTopic[]> {
    const raw: string = await WeiboHttpClient.getDesktop('https://weibo.com/ajax/side/hotSearch');
    const trimmed: string = raw.trim();
    if (trimmed.startsWith('<!DOCTYPE') || trimmed.startsWith('<html')) {
      throw new Error('微博热搜接口暂不可用，请稍后重试');
    }
    const response: WeiboApiResponse = JSON.parse(raw) as WeiboApiResponse;
    const source: WeiboHotTopicJson[] = response.data?.realtime ?? [];
    const result: WeiboHotTopic[] = [];
    const safeLimit: number = limit > 0 ? limit : source.length;
    for (let index: number = 0; index < source.length && index < safeLimit; index++) {
      const item: WeiboHotTopicJson = source[index];
      const word: string = (item.word?.trim() ?? '').length > 0
        ? (item.word?.trim() ?? '')
        : (item.note?.trim() ?? '');
      if (word.length === 0) {
        continue;
      }
      let queryText: string = item.word_scheme?.trim() ?? word;
      if (queryText.startsWith('#') && queryText.endsWith('#') && queryText.length > 2) {
        queryText = queryText.substring(1, queryText.length - 1);
      }
      result.push({
        rank: item.rank ?? item.realpos ?? index + 1,
        word: word,
        heat: item.num ?? 0,
        label: item.label_name ?? '',
        query: queryText,
      });
    }
    return result;
  }

  /** Public search autocomplete. A full result page still requires a user session. */
  async fetchSuggestions(query: string, limit: number): Promise<WeiboSuggestion[]> {
    const cleanQuery: string = query.trim();
    if (cleanQuery.length === 0) {
      return [];
    }
    const raw: string = await WeiboHttpClient.getDesktop(
      `https://weibo.com/ajax/side/search?q=${encodeURIComponent(cleanQuery)}`);
    const response: WeiboApiResponse = this.parseResponse(raw);
    const source: WeiboSuggestionJson[] = response.data?.hotquery ?? [];
    const result: WeiboSuggestion[] = [];
    const safeLimit: number = limit > 0 ? limit : source.length;
    for (let index: number = 0; index < source.length && index < safeLimit; index++) {
      const item: WeiboSuggestionJson = source[index];
      const word: string = item.suggestion?.trim() ?? '';
      if (word.length > 0) {
        result.push({ word: word, count: item.count ?? 0, isHot: item.top_flag === 2 });
      }
    }
    return result;
  }

  private async get(url: string, referer?: string): Promise<string> {
    const auth: WeiboAuthManager = WeiboAuthManager.getInstance();
    const revision: number = auth.getSessionRevision();
    const accountCookie: string = auth.getCookie();
    const visitorCookie: string = WeiboVisitorSession.getInstance().getCookie();
    const cookie: string = accountCookie.length > 0 ? accountCookie : visitorCookie;
    const raw: string = await WeiboHttpClient.get(url, cookie, referer);
    auth.assertSession(revision);
    return raw;
  }

  private postsFromResponse(raw: string): WeiboPost[] {
    const response: WeiboApiResponse = this.parseResponse(raw);
    const cards: WeiboCardJson[] = response.data?.cards ?? [];
    const posts: WeiboPost[] = [];
    this.appendPostsFromCards(cards, posts);
    return posts;
  }

  private followingPageFromResponse(raw: string, requestedMaxId: string): WeiboTimelinePage {
    const trimmed: string = raw.trim();
    if (trimmed.startsWith('<!DOCTYPE') || trimmed.startsWith('<html') || trimmed.includes('passport.weibo.com')) {
      throw new Error('微博未接受当前登录态，请重新登录后再试');
    }
    let response: WeiboFollowingTimelineResponse;
    try {
      response = JSON.parse(raw) as WeiboFollowingTimelineResponse;
    } catch (error) {
      throw new Error('微博返回了无法解析的关注动态');
    }
    if (response.ok !== 1) {
      const message: string = response.msg?.trim() ?? '';
      throw new Error(message.length > 0 ? message : '微博关注动态接口暂不可用，请稍后重试');
    }
    const source: WeiboPostJson[] = response.statuses ?? [];
    const items: WeiboPost[] = [];
    for (let index: number = 0; index < source.length; index++) {
      items.push(this.toPost(source[index]));
    }
    const cursorValue: string | number | undefined = response.max_id;
    const nextMaxId: string = cursorValue === undefined ? '' : `${cursorValue}`;
    const hasMore: boolean = items.length > 0 && nextMaxId.length > 0
      && nextMaxId !== '0' && nextMaxId !== requestedMaxId;
    return { items: items, nextMaxId: nextMaxId, hasMore: hasMore };
  }

  private appendPostsFromCards(cards: WeiboCardJson[], posts: WeiboPost[]): void {
    for (let index: number = 0; index < cards.length; index++) {
      const card: WeiboCardJson = cards[index];
      if (card.mblog !== undefined && (card.card_type === 9 || card.card_type === undefined)) {
        posts.push(this.toPost(card.mblog));
      }
      const group: WeiboCardJson[] | undefined = card.card_group;
      if (group !== undefined) {
        this.appendPostsFromCards(group, posts);
      }
    }
  }

  private requireAccountCookie(): string {
    const cookie: string = WeiboAuthManager.getInstance().getCookie();
    WeiboAuthManager.getInstance().assertSession(WeiboAuthManager.getInstance().getSessionRevision());
    if (!WeiboAuthManager.getInstance().hasCookie()) {
      throw new Error('请先在“我的”中登录微博账号');
    }
    return cookie;
  }

  private parseResponse(raw: string): WeiboApiResponse {
    const trimmed: string = raw.trim();
    if (trimmed.startsWith('<!DOCTYPE') || trimmed.startsWith('<html') || trimmed.includes('visitor.passport.weibo.cn')) {
      throw new Error('微博未接受当前登录态，请重新登录后再试');
    }
    let response: WeiboApiResponse;
    try {
      response = JSON.parse(raw) as WeiboApiResponse;
    } catch (error) {
      throw new Error('微博返回了无法解析的数据');
    }
    if (response.ok !== 1) {
      const message: string = response.msg?.trim() ?? '';
      const url: string = response.url ?? '';
      if (url.includes('captcha')) {
        throw new Error('微博要求验证码，请在设置中更新 Cookie 后重试');
      }
      throw new Error(message.length > 0 ? message : '微博接口暂不可用，请稍后重试');
    }
    return response;
  }

  private toUser(source: WeiboUserJson): WeiboUser {
    const hdAvatar: string = source.avatar_hd?.trim() ?? '';
    const avatar: string = hdAvatar.length > 0 ? hdAvatar : (source.profile_image_url?.trim() ?? '');
    const rawId: string | number | undefined = source.idstr ?? source.id;
    const rawFollowersCount: string | number | undefined = source.followers_count;
    const rawFollowingCount: string | number | undefined = source.follow_count;
    const rawStatusesCount: string | number | undefined = source.statuses_count;
    const userId: string = rawId === undefined ? '' : `${rawId}`;
    const followersCount: string = rawFollowersCount === undefined ? '' : `${rawFollowersCount}`;
    const followingCount: number = rawFollowingCount === undefined ? 0 : Number(rawFollowingCount);
    const statusesCount: number = rawStatusesCount === undefined ? 0 : Number(rawStatusesCount);
    return {
      id: userId,
      screenName: source.screen_name ?? '',
      description: source.description ?? '',
      avatarUrl: avatar,
      coverUrl: source.cover_image_phone ?? '',
      followersCount: followersCount,
      followingCount: followingCount,
      statusesCount: statusesCount,
      verified: source.verified ?? false,
      verifiedReason: source.verified_reason ?? '',
      following: source.following ?? false,
    };
  }

  /**
   * Picture URLs for one post. The mobile containers ship a `pics` array, while
   * the desktop web endpoints (the following timeline reads
   * `weibo.com/ajax/feed/friendstimeline`) ship `pic_ids` plus a `pic_infos` map
   * and never include `pics`. Reading only `pics` silently drops every picture
   * from the desktop feed, so both shapes are parsed here.
   */
  private pictureUrls(source: WeiboPostJson): string[] {
    const pictures: string[] = [];
    const seen: Record<string, boolean> = {};
    const pictureSource: WeiboPictureJson[] = source.pics ?? [];
    for (let index: number = 0; index < pictureSource.length; index++) {
      const picture: WeiboPictureJson = pictureSource[index];
      // The mobile endpoint normally returns the original file in `original`.
      // Keep high-quality fallbacks for cards whose original field is omitted.
      this.pushPictureUrl(pictures, seen, picture.original?.url
        ?? picture.largest?.url
        ?? picture.mw2000?.url
        ?? picture.large?.url
        ?? picture.url
        ?? '');
    }
    if (pictures.length === 0) {
      const infos: Record<string, WeiboPictureInfoJson> | undefined = source.pic_infos;
      if (infos !== undefined) {
        // `pic_ids` preserves the author's order; the map alone has no order.
        const ids: string[] = source.pic_ids ?? Object.keys(infos);
        for (let index: number = 0; index < ids.length; index++) {
          const info: WeiboPictureInfoJson | undefined = infos[ids[index]];
          if (info === undefined) {
            continue;
          }
          this.pushPictureUrl(pictures, seen, info.original?.url
            ?? info.largest?.url
            ?? info.mw2000?.url
            ?? info.large?.url
            ?? info.largecover?.url
            ?? info.bmiddle?.url
            ?? info.thumbnail?.url
            ?? '');
        }
      }
    }
    if (pictures.length === 0) {
      // Legacy picture fields predate `pic_ids`. `thumbnail_pic` is left out on
      // purpose: it doubles as the video cover, and using it here would turn a
      // video post into a still picture card.
      this.pushPictureUrl(pictures, seen, source.original_pic ?? source.bmiddle_pic ?? '');
    }
    return pictures;
  }

  private pushPictureUrl(pictures: string[], seen: Record<string, boolean>, url: string): void {
    const clean: string = url.trim();
    if (clean.length === 0 || seen[clean] === true) {
      return;
    }
    seen[clean] = true;
    pictures.push(clean);
  }

  /** `page_pic` is a bare url string on desktop pages and `{ url }` on mobile. */
  private pagePictureUrl(pagePic: WeiboPagePictureJson | string | undefined): string {
    if (pagePic === undefined) {
      return '';
    }
    if (typeof pagePic === 'string') {
      return pagePic.trim();
    }
    return pagePic.url?.trim() ?? '';
  }

  /**
   * Poster image for a video card. Desktop pages expose the full-size poster as
   * `media_info.big_pic_info.pic_big`, a middle one as `pic_info.pic_big` and a
   * small one as the string `page_pic`; mobile pages only have `page_pic`. The
   * largest available wins so the card and its preview stay sharpest.
   */
  private videoCoverUrl(source: WeiboPostJson): string {
    const pageInfo: WeiboPageInfoJson | undefined = source.page_info;
    const mediaInfo: WeiboVideoMediaInfoJson | undefined = pageInfo?.media_info;
    const candidates: string[] = [
      mediaInfo?.big_pic_info?.pic_big?.url ?? '',
      pageInfo?.pic_info?.pic_big?.url ?? '',
      this.pagePictureUrl(pageInfo?.page_pic),
      source.thumbnail_pic ?? '',
    ];
    for (let index: number = 0; index < candidates.length; index++) {
      const candidate: string = candidates[index].trim();
      if (candidate.length > 0) {
        return candidate;
      }
    }
    return '';
  }

  private isLongPost(source: WeiboPostJson): boolean {
    if (source.longText?.longTextContent !== undefined && source.longText.longTextContent.length > 0) {
      return false;
    }
    if (source.isLongText === true) {
      return true;
    }
    const rawText: string = source.text ?? source.text_raw ?? '';
    if (/(?:展开|查看全文|全文)(?:<\/[as][^>]*>|$)/i.test(rawText) || /<span[^>]*class="[^"]*expand[^"]*"/i.test(rawText)) {
      return true;
    }
    if (source.url_struct && Array.isArray(source.url_struct)) {
      for (const u of source.url_struct) {
        if (u.url_title === '展开' || u.url_title === '全文' || u.url_title === '查看全文') {
          return true;
        }
      }
    }
    return false;
  }

  private postText(source: WeiboPostJson): string {
    if (source.longText?.longTextContent !== undefined && source.longText.longTextContent.length > 0) {
      return normalizeWeiboText(source.longText.longTextContent).trim();
    }
    const isLongText: boolean = this.isLongPost(source);
    const rawText: string = source.text_raw ?? source.text ?? '';
    let text: string = normalizeWeiboText(rawText).trim();
    if (isLongText) {
      // The API's HTML action becomes inert plain text after sanitizing. Render a
      // real ArkUI “查看全文” control instead of leaving that fake link in place.
      text = text.replace(/(?:\.{3}|…)?\s*(?:展开|查看全文|全文)\s*$/i, '').trim();
    }
    // Clean up trailing video short links if this post has a video attached
    const hasVideo: boolean = (source.page_info?.type === 'video' ||
      source.page_info?.media_info !== undefined ||
      Boolean(source.video_url));
    if (hasVideo) {
      // In Weibo, video posts append the video's t.cn link at the end of the text.
      // Since Fluo renders the native video player directly beneath the text,
      // displaying “网页链接 ↗” is confusing and redundant.
      text = text.replace(/\s*(?:https?:\/\/(?:t\.cn|weibo\.cn|weibo\.com)\/[a-zA-Z0-9_-]+|网页链接\s*↗?)\s*$/i, '').trim();
    }
    if (source.url_struct && Array.isArray(source.url_struct)) {
      for (const u of source.url_struct) {
        if (u.url_title === '展开' || u.url_title === '全文' || u.url_title === '查看全文') {
          if (u.short_url) {
            text = text.replace(u.short_url, '').trim();
          }
        } else if (hasVideo && (u.url_type === 39 || u.url_type === '39' || (u.long_url && u.long_url.includes('video.weibo.com')))) {
          if (u.short_url) {
            text = text.replace(u.short_url, '').trim();
          }
        }
      }
    }
    return text.replace(/[\u200b\ufeff]+$/g, '').trim();
  }

  private toPost(source: WeiboPostJson): WeiboPost {
    const author: WeiboUser = this.toUser(source.user ?? {});
    const pictures: string[] = this.pictureUrls(source);
    const pageInfo: WeiboPageInfoJson | undefined = source.page_info;
    const mediaInfo: WeiboVideoMediaInfoJson | undefined = pageInfo?.media_info;
    const videoUrls: WeiboVideoUrlsJson | undefined = pageInfo?.urls;
    const videoUrl: string = mediaInfo?.stream_url_hd
      ?? mediaInfo?.stream_url
      ?? videoUrls?.mp4_1080p_60fps
      ?? videoUrls?.mp4_1080p_mp4
      ?? videoUrls?.mp4_hd_mp4
      ?? mediaInfo?.mp4_hd_mp4
      ?? videoUrls?.mp4_720p_mp4
      ?? mediaInfo?.mp4_720p_mp4
      ?? mediaInfo?.stream_url_h5
      ?? videoUrls?.mp4_sd_mp4
      ?? videoUrls?.mp4_ld_mp4
      ?? source.video_url
      ?? '';
    const videoCoverUrl: string = this.videoCoverUrl(source);
    const poster: WeiboPagePictureSizeJson | undefined = source.page_info?.media_info?.big_pic_info?.pic_big ?? source.page_info?.pic_info?.pic_big;
    const pagePicture: WeiboPagePictureJson | undefined = typeof pageInfo?.page_pic === 'string' ? undefined : pageInfo?.page_pic;
    const mediaWidth: number = Number(mediaInfo?.video_width ?? mediaInfo?.width ?? 0);
    const mediaHeight: number = Number(mediaInfo?.video_height ?? mediaInfo?.height ?? 0);
    const width: number = mediaWidth > 0 && mediaHeight > 0 ? mediaWidth : Number(poster?.width ?? pagePicture?.width ?? 0);
    const height: number = mediaWidth > 0 && mediaHeight > 0 ? mediaHeight : Number(poster?.height ?? pagePicture?.height ?? 0);
    const repostSource: WeiboPostJson | undefined = source.retweeted_status;
    const rawPostId: string | number | undefined = source.idstr ?? source.id ?? source.mid;
    const postId: string = rawPostId === undefined ? '' : `${rawPostId}`;
    return {
      id: postId,
      userId: author.id,
      userName: author.screenName,
      userAvatar: author.avatarUrl,
      text: this.postText(source),
      isLongText: this.isLongPost(source),
      pictures: pictures,
      pictureVideos: weiboLivePhotoTracks(source.pics ?? [], source.pic_infos),
      videoUrl: videoUrl,
      videoCoverUrl: videoCoverUrl,
      videoAspectRatio: width > 0 && height > 0 ? width / height : 16 / 9,
      createdAt: formatWeiboTime(source.created_at ?? ''),
      source: stripHtml(source.source ?? ''),
      likeCount: source.attitudes_count ?? 0,
      commentCount: source.comments_count ?? 0,
      repostCount: source.reposts_count ?? 0,
      isLiked: source.attitudes_status === 1,
      isFavorited: source.favorited ?? false,
      repost: repostSource === undefined ? null : this.toPost(repostSource),
    };
  }

  private toComment(source: WeiboCommentJson): WeiboComment {
    const author: WeiboUser = this.toUser(source.user ?? {});
    const replies: WeiboComment[] = [];
    if (source.comments !== undefined && Array.isArray(source.comments)) {
      for (let i = 0; i < source.comments.length; i++) {
        replies.push(this.toComment(source.comments[i]));
      }
    }
    const pictures: string[] = [];
    const imageSources: WeiboPictureJson[] = source.pics ?? (source.pic === undefined ? [] : [source.pic]);
    for (const image of imageSources) {
      const url: string = image.large?.url ?? image.url ?? '';
      if (url.length > 0) {
        pictures.push(url);
      }
    }
    const rawId: string | number | undefined = source.idstr ?? source.id;
    const commentId: string = rawId === undefined ? '' : `${rawId}`;
    return {
      id: commentId,
      userId: author.id,
      userName: author.screenName,
      userAvatar: author.avatarUrl,
      text: normalizeWeiboText(source.text ?? ''),
      createdAt: formatWeiboTime(source.created_at ?? ''),
      likeCount: source.like_counts ?? source.like_count ?? 0,
      isLiked: source.liked === true || source.liked === 1,
      replyCount: source.total_number ?? replies.length,
      replies: replies,
      pictures: pictures,
    };
  }
}
