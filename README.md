# Vibelsland Free

Vibelsland Free 是一个本机自用的 macOS 原生浮岛工具，用于展示 Claude Code、Codex CLI 和 Codex Desktop 的会话状态、工具调用、多智能体活动与审批请求。项目目标是清洁重建类似浮岛体验：不复制原应用图标、图片、完整文案、专有名称、二进制代码或完整视觉素材。

## 当前进度

更新时间：2026-05-07。

当前代码已经形成可运行的本机版本，重点能力包括：

- macOS 菜单栏应用，无 Dock 图标，主界面由 `NSPanel` + SwiftUI 绘制。
- 顶部浮岛支持空闲圆形、任务紧凑药丸和展开态三种形态；展开态会按内容自适应高度，最多显示 5 个近期会话；健康提示只在异常时显示。
- 支持 Claude Code、Codex CLI、Codex Desktop 三类来源。
- 支持 Hook 安装、设置窗口、自动启动、声音开关、勿扰、显示位置、退出和重启入口。
- 支持右键菜单，浮岛上可快速打开设置、安装 Hooks、重启和退出。
- 启动动画已经改为独立过渡层：屏幕中间黑点逐步放大成黑色药丸，淡出后显示真实浮岛。
- UI 使用 macOS 系统磨砂玻璃材质；边缘保留主状态 RGB 光效，其他背景和列表行保持低对比。
- 展开和收起都使用短窗口过渡动画；主动进度环接近屏幕刷新节奏，呼吸灯使用更平滑的刷新 cadence。
- 声音系统支持多种主题，包括柔和、玻璃、系统、8bit；不同事件有不同提示音。
- 设置页已经改为健康检查中心，集中展示 Bridge、Claude Code、Codex CLI 和 Codex Desktop 的状态。

源码仓库只跟踪项目源码、测试、脚本和文档；本机构建缓存与发布产物通过 `.gitignore` 排除。

## 已实现模块

### 应用外壳

- `AppDelegate` 负责菜单栏、设置窗口、浮岛窗口、启动动画、Hook 安装、重启和退出。
- `IslandWindow` 负责浮岛窗口定位、透明背景、点击外部收起、展开和收起动画。
- `LaunchIntroWindow` 负责启动过渡动画，独立于真实浮岛，避免主 UI 被拉伸或闪烁。
- `SettingsView` 提供 Claude、Codex CLI、Codex Desktop、声音、勿扰、位置、自动启动、健康检查、重新检测、打开日志和 Hook 卸载入口。

### 状态与数据

- `SessionStore` 是主状态协调器，合并 Hook、Codex Desktop、本地 transcript 和 app-server 事件。
- `Models` 定义 `AgentEvent`、`AgentSession`、`ActivityItem`、`ApprovalRequest`、`UsageSnapshot` 等内部模型。
- `SessionDeduper` 合并同一任务的 Codex CLI / Codex Desktop 重复状态，避免同一个任务显示两条。
- `ConversationTranscriptReader` 从 Claude / Codex 会话文件中提取真实用户输入、AI 回复、工具调用、完成状态和 token 用量。
- `SessionStatusResolver` 和 `SessionDisplaySnapshot` 负责将原始事件整理成适合浮岛展示的状态，并标记实时连接、Hook 事件、转录推断和时间推断等可信度。
- Codex Desktop 只有收到本轮 `task_complete` 后才显示完成；如果完成事件之后又出现用户、AI 或工具活动，会重新显示为处理中。
- `DashboardSessionPolicy` 控制展开态会话筛选：已完成、失败或空闲超过 30 分钟不显示，活动态超过 2 小时无更新也不占位。

### Claude Code / Codex CLI

- `HookInstaller` 安装本机 bridge helper，并合并现有 `~/.claude/settings.json`、`~/.codex/hooks.json` 和 `~/.codex/config.toml`。
- `BridgeServer` 监听本机 Unix socket，接收 Hook payload。
- `EventParser` 将 Claude / Codex hook payload 解析为统一的 `AgentEvent`。
- Hook 写入前会在内容变化时生成备份，不覆盖用户已有无关配置。

### Codex Desktop

- `CodexDesktopStateReader` 读取 `~/.codex/state_5.sqlite` 和 Codex rollout JSONL，用于获取线程、目录、标题、状态、工具调用、AI 回复和用量。
- `CodexDesktopLiveClient` 探测 Codex app-server / IPC 可用性。
- `CodexAppServerLiveClient` 保持 JSON-RPC 长连接，接收真实审批请求并回传审批结果。
- Codex Desktop 窗口聚焦通过系统激活应用完成，优先使用 bundle id，必要时回退到常见应用路径。

### 审批能力

审批目标是“不改变 Claude / Codex 原有策略，只替代审批展示和点击入口”。

已实现的审批决策：

- 允许一次
- 本轮始终允许
- 拒绝
- 取消任务

协议映射：

- Claude Code：映射到 Claude hook 支持的 permission / pre-tool-use response。
- Codex CLI：通过 hook bridge socket 回传给 CLI。
- Codex Desktop：通过 app-server JSON-RPC 使用原 request id 回 response。

安全行为：

- 审批 UI 最多等待 30 秒。
- 底层 hook 超时为 35 秒。
- 超时、断连或无法绑定 request id 时，不自动允许或拒绝。
- 不保存完整敏感命令输出，日志默认只记录事件类型、时间和错误。

## UI 状态

当前 UI 方向已经从大面板改为更紧凑的浮岛体验：

- 空闲态收缩为圆形，只显示应用图标。
- 任务紧凑态展示当前最重要任务、状态和入口。
- 展开态展示当前审批和最多 5 个近期关键会话；普通状态保持紧凑高度，审批或异常健康提示出现时才增高。
- 外壳和列表行使用系统磨砂玻璃材质，RGB 灯条作为唯一明显动效保留。
- 会话卡片优先显示真实 AI 回复和工具调用，而不是低价值 telemetry 字段。
- 任务正在运行时显示动态边缘高亮。
- 任务完成时边缘转绿色。
- 任务失败时边缘转橙色。
- 点击空白处会自动收起展开面板。
- 审批卡片支持摘要和详情两态，详情中可查看完整命令或变更说明，并显示协议支持的全部按钮。
- 会话卡片显示状态可信度，包括实时连接、Hook 事件、转录推断和时间推断。

仍在调整的 UI 细节：

- 启动动画的最终观感仍需要继续按实际观感微调。
- Claude 与 Codex 并行任务展示已经使用结构化来源字段做去重和合并；真实长任务和真实审批请求仍需要持续回归。

## Runtime Paths

- Bridge: `~/.vibelsland-free/bin/vibelsland-bridge`
- Socket: `~/.vibelsland-free/run/vibelsland.sock`
- Config: `~/Library/Application Support/VibelslandFree/config.json`
- Logs: `~/Library/Logs/VibelslandFree/app.log`

## Build

```sh
swift build
```

## Package Local App

```sh
zsh scripts/build-app.sh
```

打包产物位于：

```text
dist/Vibelsland Free.app
```

应用使用 ad-hoc codesign，适合本机自用。`codesign --verify` 会通过；因为没有 Developer ID 和 notarization，Gatekeeper 的 `spctl` 分发评估会拒绝，这是本机自用构建的预期限制。

## Package Local Release

```sh
zsh scripts/package-release.sh
```

该脚本会完成完整验证，重新打包 `.app`，并生成：

```text
dist/Vibelsland-Free-0.1.0-macos.zip
dist/Vibelsland-Free-0.1.0-macos.zip.sha256
```

对外售卖或分发前仍需要正式 Developer ID 签名、notarization，以及下载后的首次启动验证。

## Test

测试入口是 Swift Package 的标准测试命令：

```sh
swift test
```

项目脚本也会调用同一个测试入口：

```sh
zsh scripts/run-tests.sh
```

完整本地验证：

```sh
zsh scripts/verify-app.sh
```

该脚本会运行 `swift build`、`swift test`，重新打包 `.app`，并检查：

- ad-hoc codesign 验证通过。
- bundle id 是 `free.vibelsland.macos`。
- `LSUIElement` 为 `true`，应用不显示 Dock 图标。
- `CFBundleIconFile` 指向 `AppIcon`，且 `AppIcon.icns` 存在。
- `CFBundlePackageType`、`CFBundleExecutable`、应用分类、版本号和可执行文件路径符合当前打包结构。

运行态验证：

```sh
zsh scripts/verify-runtime.sh
```

该脚本会重启 `dist/Vibelsland Free.app`，等待应用启动，然后检查：

- `VibelslandFree` 进程存在。
- CPU 使用率低于阈值。
- RSS 内存低于阈值，默认上限为 `300000KB`，可用 `VIBELSLAND_RSS_MAX_KB` 调整。
- Bridge helper 已刷新，且保留 Codex CLI 跳转所需的 `thread_id` / `threadId`，以及 Desktop 内部 CLI 去重所需的 `codex_session_start_source`。
- Bridge socket 存在，归当前用户所有，权限为 `600`。
- 本次启动后的新增日志没有 `[error]` 或 `codex.sqlite.read.failed`。

如果只想检查当前正在运行的实例，不重启应用：

```sh
VIBELSLAND_RUNTIME_RESTART=0 zsh scripts/verify-runtime.sh
```

无任务小圆窗口验证：

```sh
zsh scripts/verify-idle-window.sh
zsh scripts/verify-single-instance.sh
zsh scripts/verify-menu-settings.sh
zsh scripts/verify-menu-open-logs.sh
```

`verify-idle-window.sh` 会使用隔离的临时 HOME 启动应用，关闭 Claude / Codex 来源，等待启动动画结束后检查 Bridge helper、socket、冷启动日志和浮岛窗口尺寸。`verify-single-instance.sh` 会通过系统重复打开同一个 `.app`，并确认第二个实例交给旧实例后退出，不再创建第二套浮岛。`verify-menu-settings.sh` 会通过状态栏菜单点击“设置...”，确认设置窗口能从冷启动后的菜单入口打开，并对设置窗口截图做像素检查。`verify-menu-open-logs.sh` 会通过状态栏菜单点击“打开日志”，确认 Finder 能打开隔离环境里的日志目录且 `app.log` 存在。它们用于捕捉空冷启动被误显示成任务药丸或展开面板、冷启动时 Bridge 没有正常起来、重复启动出现双 UI、菜单设置入口失效、日志入口失效，以及设置页空白的回归。

重启恢复验证：

```sh
zsh scripts/verify-restart-recovery.sh
zsh scripts/verify-app-internal-restart.sh
zsh scripts/verify-menu-restart.sh
```

`verify-restart-recovery.sh` 会使用同一个隔离临时 HOME 启动应用、停止进程、再启动一次，并确认新进程、Bridge helper、socket、日志和无任务小圆窗口都恢复正常。`verify-app-internal-restart.sh` 会通过验证专用通知触发应用内部 `restart()` 路径，确认旧实例先退出、新实例再恢复，过程中不会同时留下两个 VibelslandFree 实例。`verify-menu-restart.sh` 会通过系统辅助功能点击状态栏菜单里的“重启 Vibelsland Free”，覆盖真实菜单入口。

系统概览恢复验证：

```sh
zsh scripts/verify-system-overview-restore.sh
zsh scripts/verify-menu-open-panel-restore.sh
```

`verify-system-overview-restore.sh` 会使用隔离的临时 HOME 启动应用，发送 Mission Control 同类系统通知，并检查浮岛先进入隐藏态、随后自动恢复到无任务小圆尺寸。`verify-menu-open-panel-restore.sh` 会在隐藏态下通过状态栏菜单点击“打开面板”，确认菜单入口能主动恢复浮岛。它们用于捕捉切换系统概览后小圆不再出现的回归。

过期事件空闲验证：

```sh
zsh scripts/verify-stale-events-idle-window.sh
```

该脚本会使用隔离的临时 HOME 启动应用，通过真实 Bridge helper 发送一天前的 Claude / Codex Hook 事件，并确认事件进入日志但浮岛仍保持无任务小圆。它用于捕捉旧会话或过期 Hook 事件把闲置状态误撑成任务列表的回归。

长任务窗口验证：

```sh
zsh scripts/verify-long-task-window.sh
```

该脚本会使用隔离的临时 HOME 启动应用，通过真实 Bridge helper 发送 `UserPromptSubmit`、`PreToolUse`、`PostToolUse` 和 `SubagentStop`，并检查工具结束和子智能体结束后浮岛仍保持任务药丸尺寸，避免中途误显示为已完成。

审批窗口验证：

```sh
zsh scripts/verify-approval-window.sh
```

该脚本会使用隔离的临时 HOME 启动应用，通过真实 Bridge helper 发送 Claude `PermissionRequest`，并检查浮岛会展开到审批窗口尺寸。它不自动点击允许或拒绝，真实审批回传仍需要人工回归。

审批回传验证：

```sh
zsh scripts/verify-approval-response.sh
```

该脚本会使用隔离的临时 HOME 启动应用，并仅在该验证环境中启用本地测试动作。它通过真实 Bridge helper 发送 Claude `PermissionRequest`，依次触发 `允许一次`、`本轮始终允许`、`拒绝`、`取消任务`，然后确认 Bridge 收到对应审批返回且日志记录为已处理，不应误记为超时。正常应用不会启用这个测试动作。

Codex CLI 审批回传验证：

```sh
zsh scripts/verify-codex-cli-approval-response.sh
```

该脚本会使用隔离的临时 HOME 启动应用，通过真实 Bridge helper 发送 Codex CLI `PermissionRequest`，依次触发当前协议支持的 `允许一次` 和 `拒绝`，确认 Bridge 收到对应审批返回且日志记录为已处理。

Codex Desktop 审批回传验证：

```sh
zsh scripts/verify-codex-desktop-approval-response.sh
```

该脚本会使用隔离的临时 HOME 启动应用，并用验证专用的假 Codex app-server proxy 发送 Desktop 审批请求。它依次触发 `允许一次`、`本轮始终允许`、`拒绝`、`取消任务`，确认应用按原 request id 写回结果，并收到 resolved 通知后标记审批完成。正常应用不会使用假 proxy。

审批超时验证：

```sh
zsh scripts/verify-approval-timeout.sh
```

该脚本会使用隔离的临时 HOME 和测试专用超时覆盖启动应用，通过真实 Bridge helper 发送 Claude `PermissionRequest`，确认请求超时后 Bridge 不会收到任何允许结果，并且应用日志记录 `approval.timedOut`。正常应用配置仍保留 60 秒到 7200 秒的审批超时范围。

上述隔离窗口和系统概览恢复验证脚本共用 `scripts/window-check.swift` 检查可见窗口尺寸，避免各脚本维护重复的 CoreGraphics 扫描逻辑。
这些脚本会启动一个临时可见的隔离应用实例。若已有 Vibelsland Free 正在运行，脚本会默认停止并提示先退出应用；只有明确设置 `VIBELSLAND_ALLOW_VISIBLE_TEST_WINDOWS=1` 时，才允许临时出现第二个浮岛窗口。

Bridge 事件烟雾验证：

```sh
zsh scripts/verify-bridge-events.sh
```

该脚本会通过真实 Bridge helper 和本机 socket 发送过期的 Claude / Codex 测试事件，并检查应用日志中出现对应 `event.ingest` 记录。测试事件使用旧时间戳，不会作为当前活动任务留在浮岛里。

发布门禁：

```sh
zsh scripts/verify-release-readiness.sh
```

该门禁会先检查是否已有 Vibelsland Free 正在运行，避免后续隔离窗口验证制造第二个浮岛。若确实要在日常实例运行时执行完整门禁，可使用 `--allow-visible-test-windows`。

该脚本会运行自动验证、检查发布包、校验 checksum，并读取 `RELEASE_CHECKLIST.md` 中仍未完成的人工项。默认按公开售卖模式检查，因此当前本机 ad-hoc 构建和未确认人工回归会让脚本返回阻塞状态。只检查本机自用门禁时使用：

```sh
zsh scripts/verify-release-readiness.sh --local
```

## 最近验证结果

最近一次验证通过：

```sh
swift build
swift test
zsh scripts/run-tests.sh
zsh scripts/verify-app.sh
zsh scripts/package-release.sh
zsh scripts/verify-runtime.sh
zsh scripts/verify-idle-window.sh
zsh scripts/verify-single-instance.sh
zsh scripts/verify-menu-settings.sh
zsh scripts/verify-menu-open-logs.sh
zsh scripts/verify-restart-recovery.sh
zsh scripts/verify-app-internal-restart.sh
zsh scripts/verify-menu-restart.sh
zsh scripts/verify-system-overview-restore.sh
zsh scripts/verify-menu-open-panel-restore.sh
zsh scripts/verify-stale-events-idle-window.sh
zsh scripts/verify-long-task-window.sh
zsh scripts/verify-expand-collapse-visibility.sh
zsh scripts/verify-visual-snapshots.sh
zsh scripts/verify-session-card-click.sh
zsh scripts/verify-approval-window.sh
zsh scripts/verify-approval-timeout.sh
zsh scripts/verify-bridge-events.sh
zsh scripts/verify-release-readiness.sh --local --allow-pending-manual
```

验证内容包括：

- Swift 编译通过。
- `swift test` 通过。
- `.app` 本地打包完成。
- 本地发布 zip 和 sha256 可生成。
- ad-hoc codesign 验证通过。
- `LSUIElement`、bundle id、图标、package type、应用分类、版本号和可执行文件检查通过。
- 应用启动后的新增日志无错误，Bridge helper 已刷新，运行态 CPU 采样正常。
- 设置页 Bridge 健康检查会确认 socket 是真实 Unix socket，且属主和权限正确。
- 隔离冷启动下，Bridge/socket/log 正常，无任务状态保持小圆窗口尺寸。
- 隔离冷启动下，状态栏“设置...”能打开设置窗口，且设置窗口截图不是空白。
- 隔离冷启动下，状态栏“打开日志”能在 Finder 中打开当前日志目录，且当前日志文件存在。
- 隔离进程重启后，Bridge/socket/log 和无任务小圆窗口能恢复。
- 隔离应用内部重启后，旧实例会退出，新实例恢复 Bridge/socket/log 和无任务小圆窗口，过程中不会留下双实例。
- 隔离状态栏菜单重启后，真实菜单入口会触发同一条重启恢复路径。
- 隔离系统概览通知后，浮岛会隐藏并自动恢复到小圆窗口尺寸。
- 隔离系统概览隐藏态下，状态栏“打开面板”能主动恢复浮岛。
- 隔离过期 Hook 事件下，事件能进入日志但不会唤醒任务药丸。
- 隔离长任务事件下，工具结束和子智能体结束不会把任务药丸误缩回小圆。
- 工具结束后的展示快照不会显示“已完成”或“可能已完成”，避免把中间工具调用误判为整轮结束。
- 隔离展开再收起任务药丸时，收起过程中保持单实例、可见窗口不中断。
- 隔离小圆、任务药丸和展开态窗口截图通过像素检查，不是空白或透明残影。
- 展开/收起过渡使用 core 动效参数控制，收起验证会连续采样窗口尺寸并确认存在中间帧。
- 隔离展开态下，真实鼠标点击任务卡会触发 `session.open.request`，避免卡片点击只收起不处理。
- 隔离审批事件下，Claude 权限请求会展开到审批窗口尺寸。
- 隔离审批超时下，Bridge 不会收到允许结果，应用会记录审批超时。
- Bridge helper 能把 Claude prompt、Claude tool、Codex session 事件送到正在运行的应用。
- 发布门禁能明确列出仍未完成的人工回归和正式签名阻塞项。
- 应用内重启入口的命令构造有单元测试覆盖；隔离内部重启脚本和状态栏菜单点击脚本覆盖同一条 `restart()` 路径。
- 无任务小圆和任务药丸的展示形态由 core 策略统一判断；旧完成会话和过期活动不会让浮岛保持任务药丸形态。
- 窗口布局现在用 core 签名判断尺寸相关变化；普通内容刷新不会反复重排窗口，过期活动会通过可见性刷新缩回小圆。
- 任务卡点击目标由 core 策略统一判断；Codex Desktop、Codex CLI、Claude CLI 和未知来源的分流已有单元测试覆盖。
- Claude CLI 跳转只会聚焦真实运行中的 Claude CLI 父终端；没有匹配进程时不会跳到 Claude Desktop 或随机终端。

## 已知问题与后续检查点

- 启动动画已经可见，但动效观感仍以实际使用反馈为准，需要继续微调时长、透明度、阴影和最终浮岛出现时机。
- Codex Desktop 实际审批依赖当前 app-server / IPC 协议；如果 Codex 更新协议，需要集中修改 `CodexAppServerLiveClient` 和审批映射。
- Claude Code、Codex CLI、Codex Desktop 三端真实审批都已有代码路径，但仍应在真实长任务和真实审批请求中周期性回归。
- Mission Control / Space 切换已经加入隐藏和强制恢复保护；应用内重启命令构造、无任务小圆状态策略、窗口布局签名和任务卡跳转目标已有自动测试。真实前台跳转、无任务小圆视觉、长任务中不显示已完成、冷启动和真实重启恢复仍属于售卖前人工回归阻塞项，详见 `RELEASE_CHECKLIST.md`。
- 当前日志策略偏保守，不记录完整敏感命令输出；排查复杂协议问题时可能需要临时打开更详细的本机日志。
- 本项目只面向当前用户本机自用，不包含账号、订阅、许可证、远程同步、云服务和付费检查。
