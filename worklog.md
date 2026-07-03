# Worklog

Vibelsland Free 的开发工作日志。记录项目进程、当前进度和待办事项。

- 产品：**Vibelsland Free**（仓库 `shinteni/prompt-island`，MIT 开源）
- 平台：macOS 14+ / Apple Silicon (arm64)
- 形态：零第三方依赖的 Swift Package，双 target（`VibelslandFreeCore` 逻辑层 + `VibelslandFree` 界面层）
- 官网：<https://shinteni.github.io/prompt-island/>

> 记录规范见文末「如何维护本文件」。

---

## 当前状态（2026-07-04）

- **已发布版本**：v0.1.0（2026-05-14），GitHub Releases 提供 ad-hoc 签名的 macOS zip + SHA-256 校验。
- **代码状态**：`main` 与 `origin/main` 同步，工作区干净；共 72 次提交。
- **阶段**：v0.1.0 发布后打磨期，正在为下一个版本（暂定 v0.2.0）积累变更（见 CHANGELOG 的 Unreleased）。

---

## 进度记录

### v0.1.0 — 已发布（2026-05-14）

首个公开发布版本，核心能力齐备：

- 顶部浮岛 UI：空闲隐藏 → 任务中紧凑药丸 → 需处理时展开面板；RGB 光环区分运行/完成/失败/待审批。
- 三工具统一视图：Claude Code、Codex CLI、Codex Desktop 的会话状态、工具调用、token 摘要、最近活动。
- 审批集中处理：允许 / 拒绝 / 继续 / 取消可直接在浮岛操作。
- 设置页、Hook 安装、运行状态健康检查、单实例保护、重启恢复。
- 发布闭环：打包脚本、SHA-256 校验、GitHub Pages 官网、安装信任说明、隐私说明。

### Unreleased — 已完成、待打包进下一版本

- 新增日语 README 与日语文档页面。
- 新增 GitHub Actions 的 Swift 构建与测试目标发现检查。
- 维护者发布 gate 改进，更清晰的 ad-hoc 签名说明。
- 改进 Codex Desktop 从 Finder 启动的 macOS App 环境下的实时连接。
- 限制 `app.log` 大小并对日志中的 home 路径做脱敏。
- 修复终端审批状态在快照中的显示。
- CI：升级 checkout action 到 v5、串行执行 Swift 测试、测试隔离性改进。

---

## 待办（TODO）

### 分发 / 发布
- [ ] 规划并发布 v0.2.0：把 Unreleased 内容整理为正式 release（更新 `docs/release.json`、CHANGELOG、重新打包并同步三方 SHA-256）。
- [ ] 评估 Developer ID 签名 + notarization，降低首次打开的 Gatekeeper 摩擦。

### 进行中 / 待清理
- [ ] 清理本地分支 `codex/fix-codex-desktop-live-path`（确认是否已并入 Unreleased 的 Codex Desktop 连接改进）。
- [ ] 确认远程分支 `feat/log-rotation-and-path-redaction` 是否已合并，未合并则收尾。

### 后续可选
- [ ] 补充更多 `verify-*.sh` 覆盖场景 / 视觉快照基线。
- [ ] 官网与文档随发布同步更新（release-notes、download、install 页）。

---

## 如何维护本文件

- 每完成一个有意义的改动，在「进度记录」追加条目，并勾选/移除「待办」中对应项。
- 发布新版本时，把该版本从 Unreleased 提升为独立小节，并与 `CHANGELOG.md` 保持一致。
- 日期用绝对日期（如 `2026-07-04`），不要用「今天 / 上周」等相对表述。
- 本文件面向开发过程记录；面向用户的变更说明仍以 `CHANGELOG.md` 为准。
