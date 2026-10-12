# Fluo 界面展示页

本目录用于 README 的界面展示，不是应用 Web 版，也不是实机截图。所有用户名、发言和互动数量均为虚构，风景是页面内绘制的 SVG 插画。应用图标取自项目资源，导航符号用内联 SVG 绘制。

## 查看

直接用浏览器打开 `index.html`，无需联网或安装依赖。三个场景分别展示首页、搜索与详情，支持明暗主题、五种搜索分类和转发/评论/赞切换。其余入口只作外观示意，不会发起微博请求或执行账号操作。

也可以从仓库根目录启动本地服务：

```powershell
python -m http.server 8788 --bind 127.0.0.1
```

打开 `http://127.0.0.1:8788/docs/showcase/index.html`。

## 导出图片

Windows 安装 Microsoft Edge 后，在仓库根目录执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File docs/showcase/render.ps1
```

输出到 `docs/images/`：

- `fluo-overview-light.png` / `fluo-overview-dark.png`：三个场景的浅色、深色总览，1600 × 1120。
- `fluo-home.png`：首页单页展示，1600 × 1040。
- `fluo-search.png`：搜索单页展示，1600 × 1040。
- `fluo-detail-dark.png`：深色详情单页展示，1600 × 1040。

导出模式可通过 `?export=1&scene=home&theme=light` 指定，`scene` 支持 `home`、`search`、`detail`、`overview`，`theme` 支持 `light`、`dark`。导出使用单独的临时浏览器配置，不使用个人浏览器登录态。

## 使用边界

本页不用于验证 ArkUI 布局、HDS 原生材质、手势、性能或折叠屏适配。后续补充真机截图时，应单独标明来源，不能去掉现有示意图上的说明后将其用作实机证据。
