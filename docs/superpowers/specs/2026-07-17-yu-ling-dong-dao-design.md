# Yu灵动岛 设计文档

> macOS 26+ MacBook Pro 刘海区域灵动岛应用

## 概述

Yu灵动岛是一个运行在 macOS 26+ MacBook Pro（带刘海）上的系统级工具应用。它在刘海区域覆盖一个常驻的交互窗口（灵动岛），支持音乐控制和文件中转两大功能。通过 SwiftUI + AppKit 原生开发，使用 MediaRemote.framework 实现系统级媒体控制。

**项目定位：** 开源项目，GitHub 发布，用户自行编译。

**目标平台：** macOS 26+，仅限带刘海的 MacBook Pro。

---

## 架构设计

### 系统架构图

```
┌─────────────────────────────────────────────────┐
│                   Yu灵动岛                       │
├─────────────────────────────────────────────────┤
│                                                 │
│  ┌──────────┐    ┌──────────────────────────┐   │
│  │ 主窗口   │    │     浮动面板 (NSPanel)    │   │
│  │ (Notch)  │◄──►│  ┌────────┐ ┌────────┐  │   │
│  │ 常驻覆盖 │    │  │音乐模块 │ │文件模块│  │   │
│  │ 点击切换 │    │  └────────┘ └────────┘  │   │
│  └──────────┘    └──────────────────────────┘   │
│       │                      │                  │
│  ┌────▼──────────────────────▼────┐             │
│  │         服务层                  │             │
│  │  ┌─────────┐  ┌──────────────┐│             │
│  │  │媒体服务  │  │ 文件拖拽服务  ││             │
│  │  │MediaRmt │  │ NSPasteboard ││             │
│  │  └─────────┘  └──────────────┘│             │
│  └────────────────────────────────┘             │
│       │                                         │
│  ┌────▼────────────────────┐                    │
│  │    状态管理 (Observable) │                    │
│  │  @Observable objects     │                    │
│  └─────────────────────────┘                    │
│                                                 │
│  ┌─────────────────────────────────┐            │
│  │  菜单栏 (Status Bar)            │            │
│  │  图标 → 点击展开菜单            │            │
│  │  ├─ 设置 (偏好设置)             │            │
│  │  ├─ 关于                        │            │
│  │  ├─ 退出                        │            │
│  │  └─ 模块快捷切换               │            │
│  └─────────────────────────────────┘            │
└─────────────────────────────────────────────────┘
```

### 核心模块

| 模块 | 职责 |
|------|------|
| `NotchWindow` | 覆盖刘海的主窗口，检测刘海尺寸，管理模块切换 |
| `MusicModule` | 音乐控制 UI + MediaRemote 集成 |
| `FileModule` | 文件拖拽中转 UI + NSPasteboard 管理 |
| `ExpandPanel` | 浮动展开面板，显示当前激活模块的详细内容 |
| `MediaService` | 封装 MediaRemote.framework，提供播放状态/控制/歌词 |
| `AppState` | Observable 全局状态，管理模块切换、展开/收起、数据流 |
| `MenuBarManager` | 管理状态栏图标、菜单项（设置/关于/退出） |
| `SettingsView` | 设置窗口：开机启动、模块开关、快捷键配置等 |

---

## 主窗口（NotchWindow）

### 刘海检测

macOS 26+ MacBook Pro 的刘海区域约 124pt 宽 x 37pt 高，位于屏幕顶部中央。通过 `NSScreen.main` 的 `safeAreaInsets` 计算刘海位置和尺寸。

### 窗口属性

- 类型：`NSWindow`，无标题栏、无关闭按钮、透明背景
- 层级：`level = .statusBar + 1`（高于菜单栏，但低于弹窗）
- 不可拖动：`isMovableByWindowBackground = false`
- 接收点击：`ignoresMouseEvents = false`
- 精确对齐刘海区域

### 迷你状态（默认）

- 显示当前激活模块的迷你信息
- 音乐：歌曲名 + 控制按钮
- 文件：文件数量
- 背景为半透明毛玻璃，圆角匹配刘海形状
- 点击任意位置 → 触发展开浮动面板

### 点击与模块切换

- 点击主窗口（迷你状态）→ 展开浮动面板，显示当前模块详情
- 模块切换通过菜单栏菜单操作（音乐控制 / 文件中转站）
- 无其他手势交互，仅支持点击

### 动画

- 模块切换：水平滑动过渡（类似 iOS Dynamic Island）
- 展开/收起：窗口从刘海向下"生长"

---

## 音乐模块（MusicModule）

### 数据流

```
MediaRemote.framework → MediaService → AppState → MusicModule UI
```

### 核心能力

| 功能 | 实现方式 |
|------|---------|
| 播放状态监听 | `MRMediaRemoteRegisterForNowPlayingNotifications` |
| 获取当前歌曲信息 | `MRMediaRemoteGetNowPlayingInfo` → 标题/艺术家/专辑/封面 |
| 播放/暂停 | `MRMediaRemoteSendCommand(kMRPlay/kMRPause)` |
| 上一首/下一首 | `MRMediaRemoteSendCommand(kMRNextTrack/kMRPreviousTrack)` |
| 进度条 | 定时轮询 + 用户拖拽 seek |
| 歌词 | 检查播放器是否提供歌词（Apple Music 有） |

### UI 布局

**展开状态：**
```
┌──────────────────────────────────┐
│  [专辑封面]  Song Title          │
│              Artist Name         │
│  ◀◀   ▶/❚❚   ▶▶   🔊━━━━●━━━  │
│  ━━━━━━━━━━━━●━━━━━━━━━━━━━━  │
│  01:23 ───────────────── 03:45  │
│                                  │
│  ┌─ 歌词 ─────────────────────┐ │
│  │  这是一行歌词               │ │
│  │  这是当前正在播放的歌词     │ │
│  │  这是下一行歌词             │ │
│  └────────────────────────────┘ │
└──────────────────────────────────┘
```

**迷你状态（刘海）：**
```
┌──────────────────────────┐
│  🎵  Song Title  ▶ ⏭   │
└──────────────────────────┘
```

### 无媒体状态

当没有媒体播放时：
- 迷你状态显示 "未在播放" + 音乐图标
- 展开面板显示空白状态提示："打开任意音乐 App 开始播放"
- 控制按钮置灰不可用

### 支持的播放器

通过 MediaRemote 自动发现，支持：
- Apple Music
- Spotify
- 网易云音乐
- QQ音乐
- 任何使用系统媒体控制的播放器

---

## 文件中转模块（FileModule）

### 交互流程

1. 用户从任意 App 拖拽文件到灵动岛主窗口
2. 主窗口高亮显示 "可放置" 状态
3. 文件放入后，灵动岛显示文件图标/缩略图 + 文件名
4. 用户点击灵动岛 → 展开浮动面板，显示所有暂存文件
5. 用户从浮动面板拖拽文件到目标 App
6. 或者直接从灵动岛迷你状态拖拽到目标 App

### 数据存储

- 暂存的文件使用 `NSFilePromise` 或 `NSURL` 引用
- 不复制文件内容，仅存储文件路径/引用
- 暂存文件列表保存在内存中（退出清空）
- 最大暂存数量：10 个文件（防止内存占用过多）

### UI 布局

**迷你状态（刘海）：**
```
┌──────────────────────────────┐
│  📁  3 个文件  [拖拽此处]    │
└──────────────────────────────┘
```

**展开状态（浮动面板）：**
```
┌──────────────────────────────────┐
│  📁 文件中转站                   │
│                                  │
│  ┌────┐  ┌────┐  ┌────┐        │
│  │ 📄 │  │ 🖼️ │  │ 📁 │        │
│  │文档 │  │图片 │  │文件夹│        │
│  └────┘  └────┘  └────┘        │
│                                  │
│  [全部清除]   [全部导出]         │
└──────────────────────────────────┘
```

### 技术要点

- 使用 `NSDraggingDestination` 协议处理拖拽进入
- 使用 `NSPasteboardWriting` 协议提供拖拽输出
- 支持从 Finder、Safari、邮件等任意支持拖拽的 App 拖入

---

## 菜单栏与设置

### 菜单栏图标

- 使用 SF Symbols 图标（如 `circle.fill` 或自定义图标）
- 位于状态栏右侧，与系统图标排列

### 菜单结构

```
┌─────────────────────────┐
│ 🎵 正在播放: Song Name  │
├─────────────────────────┤
│ 音乐控制                 │
│ 文件中转站              │
├─────────────────────────┤
│ 设置...                  │
│ 关于 Yu灵动岛            │
├─────────────────────────┤
│ 退出                     │
└─────────────────────────┘
```

### 设置窗口（SettingsView）

| 设置项 | 类型 | 说明 |
|--------|------|------|
| 开机启动 | Toggle | LaunchAgent 注册 |
| 显示音乐模块 | Toggle | 灵动岛显示/隐藏音乐 |
| 显示文件中转 | Toggle | 灵动岛显示/隐藏文件 |
| 默认模块 | Picker | 启动时显示哪个模块 |
| 动画速度 | Slider | 展开/收起动画快慢 |
| 快捷键 | HotKey | 全局快捷键切换模块 |

---

## 项目结构

```
Yu灵动岛/
├── App/
│   ├── YuLingDongDaoApp.swift      # App 入口，注册 MenuBar + NotchWindow
│   └── AppDelegate.swift            # NSApplicationDelegate
├── Windows/
│   ├── NotchWindow.swift            # 覆盖刘海的主窗口
│   └── ExpandPanel.swift            # 浮动展开面板
├── Modules/
│   ├── Music/
│   │   ├── MusicView.swift          # 音乐迷你/展开 UI
│   │   ├── LyricsView.swift         # 歌词滚动 UI
│   │   └── NowPlayingInfo.swift     # 当前播放数据模型
│   └── File/
│       ├── FileTransferView.swift   # 文件中转 UI
│       └── FileItem.swift           # 文件数据模型
├── Services/
│   ├── MediaService.swift           # MediaRemote 封装
│   ├── NotchDetector.swift          # 刘海尺寸检测
│   └── DragDropService.swift        # 拖拽服务封装
├── State/
│   └── AppState.swift               # 全局状态管理
├── Settings/
│   ├── SettingsView.swift           # 设置窗口 UI
│   └── SettingsManager.swift        # UserDefaults 读写
├── MenuBar/
│   └── MenuBarManager.swift         # 状态栏菜单管理
├── Utilities/
│   ├── Constants.swift              # 常量定义
│   └── Extensions.swift             # 扩展工具
└── Resources/
    └── Assets.xcassets              # 图标/颜色资源
```

---

## 技术要求

- **平台：** macOS 26+，仅限带刘海的 MacBook Pro
- **语言：** Swift 6.0+
- **框架：** SwiftUI + AppKit
- **状态管理：** `@Observable` 宏
- **媒体控制：** MediaRemote.framework（私有框架，需手动链接）
- **权限：** 辅助功能权限（部分功能需要）

---

## 发布方式

- 开源 GitHub 仓库
- 提供 Xcode 工程，用户自行编译
- README 包含使用说明和权限配置指南
