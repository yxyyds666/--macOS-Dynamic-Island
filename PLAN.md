# Yu灵动岛 — 重构计划与上下文交接

> 本文件用于跨会话/跨模型交接，防止上下文丢失。写于第 4 轮重构开始前。
> 语言：与用户用中文沟通。项目是 macOS 刘海灵动岛 App（SwiftUI + AppKit），
> 部署目标 macOS 26.0，只支持内建刘海屏。

---

## 0. 当前仓库状态（重构开始前）

- 分支：`main`
- 工作区有 **17 个已修改文件全部未提交**（前三轮的稳定性 + UI 改动）。
- Debug / Release 均可编译，`./build.sh` 可打包出 `dist/Yu灵动岛.app`（ad-hoc 签名）。
- 参考项目已克隆到 `/tmp/boring.notch`（TheBoredTeam/boring.notch）。

### 打包/编译命令
```bash
# Debug 编译（无签名）
xcodebuild -project YuLingDongDao.xcodeproj -scheme YuLingDongDao \
  -configuration Debug -sdk macosx build CODE_SIGNING_ALLOWED=NO

# Release 打包（脚本内含 xcodegen generate + ad-hoc 签名 + 校验 MediaRemote adapter）
./build.sh   # 产物: dist/Yu灵动岛.app
```
> 注意：`build.sh` 会先跑 `xcodegen generate` 重新生成 `.xcodeproj`（工程由 `project.yml` 定义）。

---

## 1. 前三轮已完成的改动（保留，勿回退）

### Round 1 — 稳定性修复
- `AdapterMediaService.swift`：MediaRemote 流生命周期用串行队列 + generation 保护；
  停止/重启不再发布旧进程幽灵数据；退出后不自动重启；修正 next/previous 命令 ID。
- `LyricsService.swift`：同 key 强制刷新用唯一 token，旧请求不清新请求/不写缓存；
  provider 循环响应取消。修正网易云/QQ/酷狗/LRCLIB 字段解析。
- `AppDelegate.swift`：持有 `lyricFetchTask`，切歌/清空/重试/退出时取消；用完整
  identity(title|artist|album) + generation 防过期结果落 UI。
- `FileItem.swift`：可失败构造，bookmark 跟随同卷改名/移动。
- `SystemAudio.swift` / `AppState.swift`：音量写入回读实际值（后在 Round 2 改为乐观更新）。
- `LyricLine.swift`：LRC `[offset]` 支持。

### Round 2 — 刘海覆盖 / 下拉动画 / 设置修复
- `IslandView.swift`：所有状态改用实心 `NotchShape` 覆盖整个刘海（删掉 cutout 分支）。
- `NotchShape.swift`：顶边改成平直 + 直角顶角（去掉向内凹肩），只保留底部圆角。
- `MenuBarManager.swift`：设置窗口延迟到下一 runloop 打开；`setActivationPolicy(.regular)`
  + activate + makeKeyAndOrderFront + orderFrontRegardless；关闭时 `windowWillClose` 切回 `.accessory`。
- `AppState.setVolume`：改为乐观更新（写成功直接用拖动值，失败才回读），解决滑块跟手打架。
- `YuLingDongDaoApp.swift`：`Settings { EmptyView() }`（占位，见下方重构注意）。

### Round 3 — 动画性能（GPU 化，本轮将被架构重构取代部分逻辑）
- `NotchWindow.swift`：`Timer` → `CADisplayLink`（vsync 对齐），真实帧时长推进弹簧；
  容器 `wantsLayer=true` + `layerContentsRedrawPolicy=.onSetNeedsDisplay`；动画中
  `setFrame(display:false)` 靠 Core Animation GPU 合成，末帧 `display:true` 落定。
  **⚠️ 这仍是"逐帧 resize 窗口"架构，是抖动根源，Round 4 要改掉。**

---

## 2. 关键对比结论：boring.notch 为什么流畅

对比 `/tmp/boring.notch`：

| 维度 | 本项目（现状） | boring.notch |
|---|---|---|
| 窗口 | 每帧 `setFrame` 改大小 | **固定大窗口，一次定死为最大展开尺寸，永不 resize** |
| 动画驱动 | 手写弹簧 + CADisplayLink 逐帧算 setFrame | `withAnimation(.spring)` 声明式，SwiftUI/系统驱动 |
| 渲染 | 每帧缩放窗口+图层，过窗口服务器、重算阴影/命中 | 纯 SwiftUI 内部 frame 动画，全程 GPU |
| 尺寸变化 | 窗口边界变 | 只改 `@Published notchSize` 枚举状态，视图内部 `.frame(height:)` 过渡 |
| 元素连续变形 | 无 | `matchedGeometryEffect`（封面等） |

关键源码位置（参考用）：
- `/tmp/boring.notch/boringNotch/sizing/matters.swift:17` — `windowSize = openNotchSize + shadowPadding`（固定）
- `/tmp/boring.notch/boringNotch/boringNotchApp.swift:234` — `createBoringNotchWindow`，窗口 rect 用固定 windowSize
- `/tmp/boring.notch/boringNotch/ContentView.swift:121-128` — `mainLayout.frame(height: open ? notchSize.height : nil)` + spring 动画
  - openAnimation = `.spring(response:0.42, dampingFraction:0.8)`
  - closeAnimation = `.spring(response:0.45, dampingFraction:1.0)`
- `/tmp/boring.notch/boringNotch/models/BoringViewModel.swift:192-207` — `open()/close()` 只改 notchSize + notchState
- 频谱条组件：`/tmp/boring.notch/boringNotch/components/Music/MusicVisualizer.swift`

---

## 3. 本轮（Round 4）用户确认的需求与决策

用户原话要点：
1. 借鉴 boring.notch 的**渲染方式和窗口动画**。当前实现动画"从右往左有空隙"、不同步。
2. **音乐播放、鼠标未滑过（常驻/不展开状态）** → 用 boring.notch 的样子。
3. **鼠标滑过的状态** → 和当前项目一样（左封面、右歌词）。
4. **点击打开后的音乐组件** → 和 boring.notch 一样。
5. 先实现这些（音乐相关文件）；**文件中转站后续再做**。
6. **开新分支提交**。

AskUserQuestion 已确认的四个决策：
- **窗口架构**：完全改成固定窗口（永不 resize），动画全部搬进 SwiftUI 内部。✅
- **常驻播放态（鼠标未滑过）样式**：**封面 + 跳动的音频频谱条**（boring.notch 风格）。✅
- **封面跨状态**：**要 `matchedGeometryEffect` 连续变形**（平滑移动/缩放）。✅
- **分支策略**：**新分支；先把现有 17 个未提交改动作为一个提交，再做重构**。✅

### 状态 → 视觉映射（Round 4 目标）
| IslandMode | 触发 | 视觉 |
|---|---|---|
| idle（未播放） | 静止 | 实心黑刘海 pill |
| playing（播放中，鼠标未滑过） | 常驻 | **封面（左）+ 音频频谱跳动条（右）**，绕刘海（boring.notch 风） |
| hover/activity（鼠标滑过播放中） | 悬停 | **左封面 + 右歌词**（保留当前项目实现） |
| peek（点击一次） | 单击 | 音乐面板下拉（横向长、纵向薄） |
| expanded（再点击/点击打开） | 展开 | **boring.notch 风格音乐组件**（封面 + 标题 + 控制 + 进度 + 频谱/歌词） |

> 封面在 playing → hover → peek → expanded 间用 `matchedGeometryEffect` 连续移动缩放。

---

## 4. Round 4 实现步骤

### 第 0 步：分支 + 提交现有改动
```bash
git checkout -b feature/boring-notch-animation
git add -A
git commit   # 提交前三轮全部改动，信息说明是稳定性+UI+GPU三轮成果
```
提交信息末尾加：
```
Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
```

### 第 1 步：窗口改固定尺寸（不再逐帧 resize）
- `NotchWindow.swift`：
  - 窗口创建时 frame 固定为**最大展开尺寸 + 阴影 padding**（参考 boring.notch windowSize）。
  - 顶边贴屏幕顶、水平居中于刘海。切换显示器时才 `setFrame`（`relocateToBuiltInDisplay`）。
  - **删除 CADisplayLink 逐帧动画、双轴弹簧 stepAnimation、setFrame 动画那套**。
  - 保留 `canBecomeKey`、层级、collectionBehavior。
  - `IslandContainerView` 的 tracking area 覆盖固定窗口；命中判断改为基于**逻辑 notchSize**
    （鼠标是否落在当前视觉形状内），而不是窗口边界。参考 BoringViewModel:183-186 的 baseX/baseY 判断。
- `NotchDetector.swift`：新增/调整"最大展开尺寸"计算，供窗口固定尺寸使用。

### 第 2 步：SwiftUI 内部动画（核心）
- `IslandView.swift`：
  - 顶层 `.frame(width:height:)` 绑定到 `appState.islandMode` 派生的逻辑尺寸。
  - 用 `.animation(.spring(response:0.42, dampingFraction:0.8), value: mode)`（展开）
    和 `.spring(response:0.45, dampingFraction:1.0)`（收起）；参数先照抄 boring.notch 再微调。
  - 顶部贴齐、内容随 frame 过渡；用 `.clipShape(NotchShape)` 保持实心刘海覆盖（Round 2 成果保留）。
  - **不再有从右往左的斜向位移**：因为不再逐帧 resize 窗口，SwiftUI 从上边缘对齐生长即纯下拉。

### 第 3 步：常驻播放态（封面 + 频谱条）
- 新组件（建议 `Yu灵动岛/Windows/PlaybackBars.swift` 已存在，可复用/新建 `MusicVisualizer` 类似）：
  - 左：专辑封面（小尺寸，带 `matchedGeometryEffect(id:"albumArt")`）。
  - 右：音频频谱跳动条。**注意**：本项目无法读真实音频频谱（MediaRemote 不给频谱数据），
    用**伪随机/正弦驱动的装饰性跳动条**（播放时动、暂停时静止），和 boring.notch 视觉一致即可。
  - 绕刘海布局：封面在左翼、频谱在右翼、中间是实心刘海。
- 替换现有 `CollapsedPlaybackActivity`（playing 态内容）。

### 第 4 步：hover 态（保留当前左封面右歌词）
- `ActivityCapsule`（现有）：保持左封面 + 右歌词。封面加同一个 `matchedGeometryEffect(id:"albumArt")`
  以便和 playing 态之间平滑过渡。

### 第 5 步：expanded 音乐组件（boring.notch 风格）
- 参考 `/tmp/boring.notch/boringNotch/components/Notch/NotchHomeView.swift` 和 ContentView 的 mainLayout：
  - 大封面（左）+ 标题/艺术家 + 播放控制 + 进度条；右侧频谱或歌词。
  - 封面继续 `matchedGeometryEffect(id:"albumArt")` 从小态放大到大态。
- 保留 Round 1/2 的音量乐观更新、歌词逻辑。

### 第 6 步：中转站（文件模块）— **本轮不做**
- expanded 的文件 wing 暂时保留现有实现或占位，等音乐部分验收后再单独重构。

---

## 5. 不要动 / 保留的东西
- 媒体、歌词、拖放、设置窗口、音量的**业务逻辑**（前三轮成果）全部保留。
- 实心 `NotchShape` 覆盖刘海（不要退回 cutout 空隙）。
- 设置窗口 activation policy 修复。
- `MediaRemoteAdapter` perl 方案（见 memory: mediaremote-macos-15.4-block）。

## 6. 验收标准（Round 4）
1. `git diff --check` 干净；Debug 编译过；`./build.sh` 出包，MediaRemote adapter 资源在。
2. 窗口不再逐帧 resize（只在切显示器时动）；动画在 SwiftUI 内部跑，无掉帧、无从右往左空隙、无刘海周围缝隙。
3. 播放中鼠标未滑过 = 封面+频谱条；滑过 = 左封面右歌词；点开 = boring.notch 风格音乐组件；封面全程连续变形。
4. 命中：点刘海中央/左右翼都能唤醒；非 key 窗口首击有效；expanded 内控件可点、不误折叠。
5. 只保留本轮相关改动；提交在新分支 `feature/boring-notch-animation`。

---

## 7. 已确认（Round 4 追加决策）
- **频谱条**：用装饰性跳动动画（无真实频谱数据，MediaRemote 不提供）。播放时动、暂停时静止。✅
- **expanded 右侧内容**：放**歌词**（不是频谱）。✅
- **peek 态**：**保留**。四态维持 idle/playing → hover/activity → peek → expanded，两段式点击不变。✅
