# Vibelsland Free Maintainer Release Checklist

这是维护者用于下一次发布执行的清单，不是 v0.1.0 的公开就绪状态。v0.1.0 的下载包、SHA-256、源码 tag、安装说明、隐私页和支持入口已经公开；清单中的未勾选项用于避免后续重新打包、正式域名切换或 notarized 分发时漏项。

GitHub 免费发布或后续 notarized 分发前，必须同时完成自动验证和真实人工回归。本清单记录自动脚本不能可靠覆盖的发布阻塞项。

## 自动验证

- [ ] 运行隔离窗口验证前，确认日常 >_ - island 实例已经退出；若确实需要同时显示临时测试窗口，显式设置 `VIBELSLAND_ALLOW_VISIBLE_TEST_WINDOWS=1`。
- [ ] 运行 `zsh scripts/verify-app.sh` 并确认通过。
- [ ] 运行 `zsh scripts/package-release.sh` 并确认生成 zip 与 sha256；如果脚本提示本地产物与 `docs/release.json` 不一致，只能作为未发布候选包处理，不能单独更新官网 hash。
- [ ] 运行 `VIBELSLAND_VERIFY_DIST=1 zsh scripts/verify-docs-site.sh`，确认本地 zip、`.sha256` 文件、文件大小和 `docs/release.json` 的公开发布元数据完全一致。
- [ ] 运行 `zsh scripts/verify-docs-site.sh`，确认官网本地链接、manifest 图标、sitemap、robots、canonical/hreflang、发布文案和 sha256 文件格式通过。
- [ ] 运行 `zsh scripts/verify-docs-live.sh`，确认 GitHub Pages、`security.txt`、`llms.txt`、版本化 CSS/JS 和线上 Release checksum 都能访问且一致。
- [ ] 运行 `VIBELSLAND_VERIFY_DIST=1 zsh scripts/verify-docs-live.sh`，确认本地 `dist/`、官网 `release.json` 和线上 GitHub Release 包是同一个产物。
- [ ] 确认 GitHub Pages workflow `Docs site` 已通过；若绑定正式域名，确认仓库变量 `VIBELSLAND_SITE_URL` 和 `VIBELSLAND_CUSTOM_DOMAIN` 与正式域名一致，并在 DNS 生效后运行 `VIBELSLAND_SITE_URL=https://你的域名/ zsh scripts/verify-docs-live.sh`。
- [ ] 若绑定正式域名，运行 `VIBELSLAND_SITE_URL=https://你的域名/ VIBELSLAND_CUSTOM_DOMAIN=你的域名 zsh scripts/build-docs-site.sh /tmp/vibelsland-docs-site`，确认输出目录里的 canonical、OG、JSON-LD、sitemap、robots、security.txt、manifest 和 `CNAME` 都指向正式域名。
- [ ] 运行 `zsh scripts/verify-runtime.sh`，确认应用启动后无新错误、Bridge/socket 已刷新、CPU 和 RSS 内存在阈值内。
- [ ] 运行 `zsh scripts/verify-idle-window.sh`，确认隔离冷启动后 Bridge/socket/log 正常，且无任务状态不显示浮岛窗口。
- [ ] 运行 `zsh scripts/verify-single-instance.sh`，确认通过系统重复打开同一个 `.app` 时只保留旧实例，新实例不会再创建第二套浮岛。
- [ ] 运行 `zsh scripts/verify-menu-settings.sh`，确认隔离冷启动后状态栏“设置...”能打开设置窗口，且设置窗口截图不是空白。
- [ ] 运行 `zsh scripts/verify-menu-open-logs.sh`，确认隔离冷启动后状态栏“打开日志”能在 Finder 中打开当前日志目录，且当前日志文件存在。
- [ ] 运行 `zsh scripts/verify-restart-recovery.sh`，确认隔离进程重启后 Bridge/socket/log 能恢复，且无任务状态保持隐藏。
- [ ] 运行 `zsh scripts/verify-app-internal-restart.sh`，确认应用内部重启路径会先退出旧实例、再恢复新实例，过程中不会留下两个浮岛进程。
- [ ] 运行 `zsh scripts/verify-menu-restart.sh`，确认状态栏菜单里的“重启 >_ - island”会触发同一条重启恢复路径。
- [ ] 运行 `zsh scripts/verify-system-overview-restore.sh`，确认展开面板收到隔离 Mission Control 通知后会隐藏并自动恢复。
- [ ] 运行 `zsh scripts/verify-menu-open-panel-restore.sh`，确认隔离隐藏态下状态栏“打开面板”能主动恢复浮岛。
- [ ] 运行 `zsh scripts/verify-stale-events-idle-window.sh`，确认过期 Claude / Codex Hook 事件会被记录但不会唤醒任务药丸。
- [ ] 运行 `zsh scripts/verify-long-task-window.sh`，确认工具结束和子智能体结束不会让长任务误缩回空闲隐藏态。
- [ ] 运行 `zsh scripts/verify-expand-collapse-visibility.sh`，确认任务药丸展开再收起期间保持单实例、窗口不中断，且收起采样能观察到连续中间帧。
- [ ] 运行 `zsh scripts/verify-visual-snapshots.sh`，确认无任务隐藏态不会显示窗口，任务药丸和展开态截图都有实际内容，不是空白或透明残影。
- [ ] 运行 `zsh scripts/verify-session-card-click.sh`，确认展开态下真实鼠标点击任务卡会进入打开会话路径。
- [ ] 运行 `zsh scripts/verify-approval-window.sh`，确认隔离审批事件会展开审批窗口。
- [ ] 运行 `zsh scripts/verify-approval-response.sh`，确认隔离审批事件的允许一次、本轮始终允许、拒绝、取消任务都会向 Bridge 返回审批结果，且不会误记为超时。
- [ ] 运行 `zsh scripts/verify-codex-cli-approval-response.sh`，确认 Codex CLI 隔离审批事件的允许一次、拒绝会向 Bridge 返回审批结果。
- [ ] 运行 `zsh scripts/verify-codex-desktop-approval-response.sh`，确认 Codex Desktop 隔离审批请求的允许一次、本轮始终允许、拒绝、取消任务会按 request id 返回给 app-server proxy 并标记完成。
- [ ] 运行 `zsh scripts/verify-approval-timeout.sh`，确认隔离审批请求超时后不会向原工具返回允许结果。
- [ ] 运行 `zsh scripts/verify-bridge-events.sh`，确认 Claude / Codex 测试事件能通过真实 Bridge helper 进入应用。
- [ ] 运行 `zsh scripts/verify-release-readiness.sh --github`，确认 GitHub 免费发布门禁会先阻止本地 dist / 官网元数据 / 线上 Release 不一致，再明确列出未完成的人工回归；如果日常实例正在运行，应先提示退出而不是制造第二个浮岛；所有人工项完成后再要求该脚本通过。
- [ ] 若走 Developer ID/notarization 分发线，运行 `zsh scripts/verify-release-readiness.sh --notarized`，确认正式签名、notarization 和下载后首次启动验证已经完成。
- [ ] 确认产物位于 `dist/>_ - island.app`。
- [ ] 确认下载包位于 `dist/Vibelsland-Free-0.2.0-macos.zip`。
- [ ] 确认 GitHub 免费发布包的 ad-hoc 签名、Gatekeeper 首次打开说明、SHA-256 校验、源码和 Release 说明保持一致；如果本地重新打包产生不同 hash，必须同时上传匹配的 GitHub Release 资产、更新 `docs/release.json`、同步下载页/README 后再发布；如果要走 notarized 分发线，再另行完成 Developer ID 签名和 notarization。

## 人工回归

- [ ] 公众下载信任链：在干净目录下载 zip 和 `.sha256`，运行 `cd ~/Downloads && shasum -a 256 -c Vibelsland-Free-0.2.0-macos.zip.sha256`，解压后拖入 Applications；若出现 Apple 无法验证提示，点“完成”，到“系统设置 → 隐私与安全性”点“仍要打开”，再安装或修复 hooks，并确认设置页健康检查正常。
- [ ] ad-hoc 签名说明：下载页、安装页、FAQ 和 README 都明确当前包不是 Developer ID notarized；SHA-256 只证明文件匹配 GitHub Release 资产，不证明开发者身份；`spctl` 对 ad-hoc 包显示 rejected 或 not accepted 不应被解释成 checksum 失败。
- [ ] 公开报告边界：支持页和 `security.txt` 明确普通 bug 走公开 issue 且必须脱敏；安全漏洞不在公开 issue 中发布利用细节、token、路径、prompt、会话内容或完整日志。
- [ ] 404 与移动端站点体验：真实访问根路径、`/en/not-found-*.html`、`/ja/not-found-*.html` 均返回站点 404；360px、390px 和 1024px 宽度下主导航、下载首屏、FAQ/隐私首屏不遮挡正文。
- [ ] Claude Code 审批：隔离脚本已覆盖审批事件会展开窗口、允许一次、本轮始终允许、拒绝、取消任务会回传、超时不自动允许；仍需触发真实工具审批，确认四类按钮在真实 Claude Code 流程中都能正确回传。
- [ ] Codex CLI 审批：隔离脚本已覆盖允许一次、拒绝会回传；仍需触发真实 CLI hook 审批，确认按钮结果能回到当前 CLI 任务；Codex Desktop 内部拉起的 CLI 子任务不应单独显示为新任务；任务卡目标策略、Claude CLI 终端目标选择和展开态真实点击路径已有自动覆盖，仍需确认真实前台跳转。
- [ ] Codex Desktop 审批：隔离 fake app-server 脚本已覆盖 request id 绑定和四类按钮回传；仍需触发真实 Desktop app-server 审批，确认真实 Codex Desktop 请求和本机流程一致，超时或断连不会自动允许。
- [ ] Mission Control：隔离脚本已覆盖系统概览通知后的隐藏、自动恢复，以及隐藏态下状态栏“打开面板”主动恢复；仍需真实打开 Mission Control、切换 Space、切换全屏应用，确认浮岛会隐藏并在恢复后重新出现。
- [ ] 无任务隐藏态：隔离脚本已覆盖冷启动、活动过期、旧 Hook 事件不撑开任务药丸，且无任务状态不显示浮岛窗口；仍需人工确认真实桌面视觉观感。
- [ ] 长任务中不显示已完成：隔离窗口脚本已覆盖工具调用结束和子智能体结束后仍保持任务药丸，展开再收起期间窗口不中断，且任务药丸/展开态截图非空白；单元测试已覆盖工具结束后的展示文案不会显示“已完成/可能已完成”；仍需真实长任务中人工确认展开态不显示超过策略窗口的旧会话。
- [ ] 冷启动：隔离脚本已覆盖 Bridge/socket/log、无任务隐藏态、状态栏“设置...”打开设置窗口、设置窗口截图非空白，以及状态栏“打开日志”打开日志目录；仍需完全退出应用后重新打开，人工确认日常桌面视觉观感。
- [ ] 重启：隔离脚本已覆盖进程重启后的 Bridge/socket/log、无任务隐藏态恢复、应用内部 `restart()` 路径和状态栏菜单点击重启不会留下双实例；仍需人工确认日常桌面环境中的视觉观感。

## 发布阻塞

- [x] README 中的构建、测试、已知问题与当前版本一致。
- [x] `PRIVACY.md` 与当前本地数据读取、日志和 Hook 写入行为一致。
- [ ] 若走 notarized 分发线，完成正式签名、notarization、下载后首次启动验证。
