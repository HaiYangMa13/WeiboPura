<div align="center">

# Fluo

**轻盈地刷微博，原生地用鸿蒙。**

一款使用 ArkTS / ArkUI 构建的 HarmonyOS 原生微博第三方客户端。

以鼠尾草绿、沉浸式界面和流畅的内容浏览，让注意力回到微博本身。

[功能特性](#功能特性) · [界面预览](#界面预览) · [构建与运行](#构建与运行) · [隐私说明](docs/PRIVACY.md) · [反馈问题](https://github.com/HaiYangMa13/fluo/issues)

</div>

> Fluo 正在持续开发中，尚不保证所有微博接口与设备场景均可用。它是独立的第三方项目，与微博及其关联方无关，也不是微博官方客户端。

## 功能特性

### 浏览与发现

- **推荐与关注**：双时间线浏览，支持刷新、分页加载与图文卡片。
- **热搜与搜索**：查看热搜榜，使用关键词搜索微博内容。
- **微博详情**：阅读长文、查看评论与楼中楼回复，切换评论排序。
- **图片与视频**：图片预览、视频播放，以及视频内的播放进度和倍速控制。
- **用户主页**：查看用户资料与其发布的微博。

### 互动与账户

- 登录后进行点赞、收藏、关注、评论、回复和转发。
- 发布文字与图片微博，使用表情面板和图片附件。
- 查看消息入口，以及个人微博、收藏与点赞记录。
- 通过系统分享面板分享内容，使用应用内浏览器打开网页链接。

上述功能是否可用取决于账户权限、微博接口及网络状态。**写操作只响应用户明确发起的操作，不提供自动点赞、定时发布或批量互动。**

### 鸿蒙原生体验

- **ArkTS / ArkUI 原生界面**：不是把微博网页包装成应用；登录和网页链接使用内嵌 Web 页面。
- **HDS 悬浮底栏**：信息流导航与详情评论栏共用原生材质配置及渐变背板。
- **主题与阅读设置**：深浅色模式、可切换的强调色与字体缩放。
- **多形态布局**：按窗口宽度调整内容与导航布局，面向手机、折叠屏及平板持续适配。

原生材质、键盘交互与不同设备形态仍在持续打磨；实现了相应能力，不代表所有设备上的表现都已验收。

## 界面预览

以下是已有版本的真机截图，供了解页面结构；当前配色、底栏与部分交互已更新，请以实际运行版本为准。

<p align="center">
  <img src="docs/images/01-home-feed.jpg" alt="推荐信息流" width="19%" />
  <img src="docs/images/02-hot-search.jpg" alt="热搜榜" width="19%" />
  <img src="docs/images/03-search-results.jpg" alt="微博搜索结果" width="19%" />
  <img src="docs/images/04-post-detail.jpg" alt="微博详情与评论" width="19%" />
  <img src="docs/images/05-system-share.jpg" alt="HarmonyOS 系统分享面板" width="19%" />
</p>

## 开始使用

1. 首次启动时阅读并确认隐私说明。
2. 在首页浏览推荐内容，在热搜页查看榜单或输入关键词搜索。
3. 在「我的」中打开微博登录页，由你自行完成登录。应用检测到登录态后，返回使用关注流和账户相关功能。
4. 点击微博进入详情，阅读正文、查看媒体与评论；需要互动时主动点击对应操作。

公开内容可以尝试以访客身份访问，但并不保证免登录始终可用。遇到验证码、登录失效或访问限制时，请按微博的提示处理。

## 构建与运行

目前以源码构建和真机调试为主。

### 环境

| 项目 | 要求 |
| --- | --- |
| 开发工具 | DevEco Studio，配套 OHPM、Hvigor 和 HarmonyOS SDK |
| 目标 SDK | `26.0.0` |
| 兼容 SDK | `6.1.0(23)` |
| 开发语言 | ArkTS |
| UI | ArkUI、HDS（UIDesignKit） |
| 设备 | 满足兼容 SDK 要求的 HarmonyOS 手机或平板 |

SDK 的精确要求以 [`build-profile.json5`](build-profile.json5) 为准，不能仅凭系统营销版本号判断是否兼容。

### 使用 DevEco Studio

```bash
git clone https://github.com/HaiYangMa13/fluo.git
cd fluo
```

1. 用 DevEco Studio 打开工程并完成 OHPM 依赖同步。
2. 确认已安装工程要求的 SDK，选择 `default` 产品与 `entry` 模块。
3. **配置自己的调试签名**。仓库现有签名配置中包含历史开发机路径，不可直接用于你的设备；请通过 DevEco Studio 重新配置，不要上传证书、私钥或密码。
4. 连接并授权调试设备，执行构建和运行。

HAP 构建产物位于 `entry/build/default/outputs/default/`。同包名应用的覆盖安装需要兼容的签名；不要为解决签名问题直接卸载现有应用，以免丢失本地数据。

### 回归检查

项目提供 Node.js 测试，覆盖数据处理、会话边界、交互状态逻辑和部分 ArkUI 源码约束：

```bash
node --test tests/weibo-regression.test.cjs tests/weibo-fulltext-binding.test.cjs tests/weibo-native-dock.test.cjs tests/weibo-hotsearch-hit-test.test.cjs
```

测试加载器需要 DevEco SDK 中的 TypeScript 编译器。请通过 `WEIBO_TEST_TYPESCRIPT` 指向本机编译器模块，或通过 `DEVECO_SDK_HOME` 配置 SDK 根目录；具体路径规则见 [`tests/ets-loader.cjs`](tests/ets-loader.cjs)。

**测试通过不等于真机交互验证通过。** ArkUI 布局、材质、状态刷新与键盘行为仍需在设备上检查，相关结果记录在 `docs/verification-*.md`。

## 工程结构

```text
AppScope/                      应用元信息、图标与全局资源
entry/src/main/
├── ets/
│   ├── entryability/          应用入口与窗口事件
│   ├── pages/                 信息流、热搜、详情、用户主页等页面
│   ├── components/            富文本、视频、发布与表情等组件
│   ├── service/               微博业务、登录态、媒体与应用设置
│   ├── network/               网络请求与会话边界
│   ├── common/                主题、原生底栏、文本与交互工具
│   ├── model/                 数据模型
│   └── cache/                 本地存储与图片缓存
└── resources/                 文案、媒体与表情数据
tests/                         回归测试与 ArkTS 加载器
docs/                          隐私说明、设计原型及验证记录
```

## 数据与隐私

- 登录由用户在可见的微博登录页自行完成，所需登录态保存在本机应用存储中。
- 登录凭据仅用于向微博服务发起授权请求，不向本项目控制的第三方上传或共享。
- 访客会话与账户会话分离，网络请求设有节流；应用不绕过验证码或微博访问限制。
- 微博内容及媒体可能由微博及其相关 CDN 提供，请同时了解对应服务的隐私政策。
- 接口字段、风控策略与服务可用性可能变化，部分功能可能暂时失效。

详细说明见 [隐私政策](docs/PRIVACY.md)。权限声明以 [`entry/src/main/module.json5`](entry/src/main/module.json5) 为准。

## 反馈与贡献

欢迎通过 [Issues](https://github.com/HaiYangMa13/fluo/issues) 报告问题或提出建议。为了便于复现，请尽量提供：

- 应用版本或提交编号；
- 设备型号、系统版本及折叠 / 展开状态；
- 操作步骤、预期结果与实际表现；
- 已脱敏的截图或日志。

**不要提交 Cookie、Token、登录二维码、私信内容或签名文件。** 提交代码前请运行相关测试；涉及界面的改动，请说明是否完成真机验证。

## 致谢与许可证

本项目在已有 TiebaPura / WeiboPura 工程基础上持续演进，保留原有开源许可证。第三方素材与相关说明见 [`docs/third-party`](docs/third-party/README.md)。

源代码采用 [GPL-3.0](LICENSE) 许可证。微博商标、用户内容及第三方素材的权利归各自权利人所有。
