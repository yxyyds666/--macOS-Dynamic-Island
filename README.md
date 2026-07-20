# 岛一下

一款 macOS 刘海屏「灵动岛」应用。把 MacBook 顶部的物理刘海变成一个可交互的岛：常驻显示正在播放的音乐、鼠标滑过看歌词、点开展开成完整的音乐控制面板和文件中转站。

> 灵感来自 [boring.notch](https://github.com/TheBoredTeam/boring.notch)，动画与展开布局参考了它的设计。

## 功能特性

- **音乐控制** — 读取系统正在播放的媒体信息（标题、艺术家、专辑、封面、进度），支持播放/暂停、上一首/下一首、进度拖拽、音量调节。
- **歌词** — 自动匹配当前歌曲的逐行同步歌词，展开时居中滚动跟随播放进度，可点击某行跳转。
- **多状态灵动岛**：
  - **常驻播放态**：不打扰时缩在刘海两侧，左侧专辑封面 + 右侧跳动的频谱条。
  - **悬停态**：鼠标滑过时展开，左封面 + 右歌词预览。
  - **展开态**：点击后下拉成完整面板，顶部标签在「音乐控制 / 文件中转站」之间切换，右上角有设置和关闭。
  - 专辑封面在各状态间用 `matchedGeometryEffect` 平滑变形。
- **文件中转站** — 把文件拖进岛里临时暂存，横向排列的文件磁贴，可再拖出到任意位置、双击打开、右键菜单（打开 / Finder 显示 / 复制路径 / 移除）。
- **设置** — 开机启动、模块显隐、默认模块、动画速度。
- **菜单栏图标** — 快速切换模块、打开设置、查看正在播放。

## 系统要求

- **macOS 26.0 及以上**
- **带物理刘海的内建屏幕**（MacBook Pro / Air 刘海机型）。没有检测到内建刘海屏时应用会直接退出。

## 构建与运行

项目使用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 从 `project.yml` 生成工程。

```bash
# 安装 xcodegen（若未安装）
brew install xcodegen

# 一键构建 + 打包（Release）
./build.sh
```

`build.sh` 会：
1. `xcodegen generate` 生成 `.xcodeproj`
2. Release 编译
3. 打包到 `dist/岛一下.app`
4. 对 app 做 ad-hoc 签名

产物在 `dist/岛一下.app`，双击即可运行。

### 关于签名

音乐信息通过一个私有的 MediaRemote 框架读取（随包内置了一个 perl 适配器 `Resources/MediaRemoteAdapter`）。为了能 `dlopen` 这个私有框架，构建配置里关闭了库校验（`disable-library-validation`），并对 app 做 ad-hoc 签名。这也是打包必须走 `build.sh` 而不是直接从 Xcode 拖出的原因。

## 项目结构

```
Yu灵动岛/
├── App/                    应用入口、AppDelegate（媒体绑定、歌词拉取、显示器切换）
├── MenuBar/                菜单栏图标与菜单、设置窗口的打开/激活策略
├── Windows/
│   ├── NotchWindow         固定尺寸的岛窗口 + 命中/穿透/悬停几何判断
│   ├── IslandView          岛的 SwiftUI 内容与状态动画
│   ├── IslandPanels        音乐面板、文件面板、歌词面板、活动胶囊
│   ├── AudioSpectrum       频谱条、共享封面组件、常驻播放胶囊
│   └── NotchShape          实心贴合刘海的形状
├── Services/
│   ├── AdapterMediaService MediaRemote 适配器进程的生命周期与数据流
│   ├── LyricsService       歌词聚合（网易云 / QQ / 酷狗 / LRCLIB）
│   ├── NotchDetector       内建刘海屏检测与窗口定位
│   ├── DragDropService     文件拖放接收
│   └── SystemAudio         系统音量读写
├── State/AppState          单一状态源（播放、歌词、文件、交互状态）
├── Settings/               设置存储与设置界面
├── Modules/                文件项、歌词行、正在播放信息模型
└── Utilities/              常量与扩展
```

### 架构要点

窗口一次性创建为最大展开尺寸后**不再逐帧 resize**，所有状态尺寸变化都发生在 SwiftUI 内部（`.frame` + spring 动画），由 GPU 合成。窗口大部分透明，命中测试和悬停判断基于**当前岛的几何区域**：岛区域内接收点击，区域外让事件穿透到下层（菜单栏、其它应用）。

## 歌词数据源

按顺序尝试，命中同步歌词即用：网易云音乐 → QQ 音乐 → 酷狗音乐 → [LRCLIB](https://lrclib.net)。均使用公开客户端接口，不发送任何账号凭据。

## 隐私说明

- 正在播放的媒体信息仅在本机读取，用于岛内显示，不上传。
- 歌词查询会用歌曲的标题 / 艺术家 / 专辑 / 时长向上述公开歌词服务发起请求。
- 文件中转站仅在本机暂存文件引用，不做任何上传。

## 致谢

- [boring.notch](https://github.com/TheBoredTeam/boring.notch) — 灵动岛动画与展开布局的设计参考。
- [LRCLIB](https://lrclib.net) — 开放歌词库。
