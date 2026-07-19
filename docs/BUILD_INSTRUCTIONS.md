# 构建说明

Yu灵动岛使用 XcodeGen 生成 Xcode 工程，并通过 `MediaRemoteAdapter` 访问 macOS 15.4+ 的系统媒体信息。当前实现不需要 Objective-C bridging header，也不需要直接链接私有 `MediaRemote.framework`。

## 环境要求

- macOS 26+
- Xcode 16+
- XcodeGen 2.x：`brew install xcodegen`
- 带刘海的 MacBook Pro（应用启动时会检查刘海）

## 构建

在仓库根目录执行：

```bash
./build.sh
```

脚本会：

1. 根据 `project.yml` 生成 `YuLingDongDao.xcodeproj`。
2. 构建 Release app。
3. 将 `Resources/MediaRemoteAdapter` 复制到 app bundle 的 Resources 中。
4. 对 adapter framework 和 app 做 ad-hoc 签名。
5. 输出 `dist/Yu灵动岛.app`。

也可以直接在 Xcode 中打开生成的工程并 Build。工程 build phase 会在 Debug/Release 产物中复制并签名 `MediaRemoteAdapter`，因此普通 Xcode build 也能使用音乐服务。

## 媒体适配器

macOS 15.4+ 对直接加载 MediaRemote 有私有 entitlement 限制。当前服务链路是：

```text
AdapterMediaService
  -> /usr/bin/perl
  -> Resources/MediaRemoteAdapter/mediaremote-adapter.pl
  -> Resources/MediaRemoteAdapter/MediaRemoteAdapter.framework
```

不要设置 `MediaRemoteBridge.h`，也不要添加 `-framework MediaRemote`。这些属于旧实现，当前工程不再使用。

## 运行限制

- 只支持带刘海的 MacBook Pro。
- 媒体控制依赖系统当前播放器是否提供 Now Playing 信息。
- 歌词从 LRCLIB 网络服务获取，只发送歌曲标题、艺人、专辑和时长。
- 文件中转内容默认只保存在当前运行期间的内存中。
