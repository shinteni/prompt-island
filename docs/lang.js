(() => {
  const supported = ["zh", "en", "ja"];
  const params = new URLSearchParams(window.location.search);
  const requested = params.get("lang");
  const pathSegments = window.location.pathname.split("/").filter(Boolean);
  const pathLang = pathSegments.find((segment) => supported.includes(segment));
  let stored = "";
  try {
    stored = window.localStorage.getItem("vibelsland-lang") || "";
  } catch (error) {
    stored = "";
  }
  const lang = supported.includes(requested)
    ? requested
    : supported.includes(pathLang)
      ? pathLang
      : supported.includes(stored)
        ? stored
        : "zh";
  const file = window.location.pathname.split("/").pop() || "index.html";
  const page = file.replace(".html", "") || "index";
  const rootPrefix = pathLang && pathLang !== "zh" ? "../" : "";

  const routeFor = (targetLang, targetFile = file, hash = "") => {
    const normalizedFile = targetFile || "index.html";
    if (targetLang === "zh") return `${rootPrefix}${normalizedFile}${hash}`;
    if (pathLang === targetLang) return `${normalizedFile}${hash}`;
    return `${rootPrefix}${targetLang}/${normalizedFile}${hash}`;
  };

  if (!supported.includes(requested) && !supported.includes(pathLang) && supported.includes(stored) && stored !== "zh") {
    window.location.replace(routeFor(stored, file, window.location.hash));
    return;
  }

  try {
    window.localStorage.setItem("vibelsland-lang", lang);
  } catch (error) {
    // Keep language switching usable when storage is blocked.
  }

  const copy = {
    zh: {
      htmlLang: "zh-CN",
      meta: {
        index: {
          title: "Vibelsland Free | AI 编程浮岛",
          description: "Vibelsland Free 把 Claude Code、Codex CLI 和 Codex Desktop 的本地状态、工具调用和审批请求留在 macOS 顶部浮岛中。",
          ogTitle: "Vibelsland Free | AI 编程浮岛",
          ogDescription: "把 Claude Code、Codex CLI 和 Codex Desktop 的本地状态留在 macOS 顶部。"
        },
        advantages: {
          title: "产品优势 | Vibelsland Free",
          description: "了解 Vibelsland Free 如何让 Claude Code、Codex CLI 和 Codex Desktop 的会话状态、审批请求和工具调用保持可见。",
          ogTitle: "Vibelsland Free 产品优势",
          ogDescription: "为重度 AI 编程工作流提供低干扰的本地状态层。"
        },
        download: {
          title: "下载 macOS 版 | Vibelsland Free",
          description: "下载 Vibelsland Free v0.1.0，查看 macOS 14+ 系统要求、首次打开说明、SHA-256 校验、源码和隐私边界。",
          ogTitle: "下载 Vibelsland Free",
          ogDescription: "macOS 14+ 本地优先 AI coding 状态层，源码、校验和隐私边界公开。"
        },
        privacy: {
          title: "隐私与本地数据 | Vibelsland Free",
          description: "Vibelsland Free 不创建账号，不上传遥测，只读取本机 Claude Code、Codex CLI 和 Codex Desktop 状态用于展示浮岛。",
          ogTitle: "Vibelsland Free 隐私与本地数据",
          ogDescription: "本地优先，无账号，无遥测，无远程会话同步。"
        }
      },
      strings: {
        "shared.skip": "跳到正文",
        "shared.nav.home": "首页",
        "shared.nav.advantages": "优势",
        "shared.nav.download": "下载",
        "shared.nav.privacy": "隐私",
        "shared.cta": "下载 macOS 版",
        "shared.footer.tagline": "面向 macOS 的本地优先 AI coding 状态层。",

        "home.hero.eyebrow": "Vibelsland Free · macOS 14+ · 本地优先",
        "home.hero.title": "Vibelsland Free",
        "home.hero.kicker": "本地优先的 AI coding 状态层。",
        "home.hero.copy": "在一个低干扰浮岛里查看 Claude Code、Codex CLI 和 Codex Desktop 的会话进度、工具调用、token 摘要和审批请求。无需账号，不上传遥测。",
        "home.hero.primary": "下载 macOS 版",
        "home.hero.secondary": "查看隐私边界",
        "home.hero.status": "工具运行中 · 等待审批",
        "home.spec.system.label": "系统",
        "home.spec.system.value": "macOS 14+",
        "home.spec.tools.label": "覆盖工具",
        "home.spec.tools.value": "Claude Code / Codex CLI / Codex Desktop",
        "home.spec.data.label": "数据策略",
        "home.spec.data.value": "Local-first",
        "home.spec.version.label": "当前版本",
        "home.spec.version.value": "v0.1.0",
        "home.focus.eyebrow": "状态焦点",
        "home.focus.title": "AI 编程时，最容易漏看的信息都在这里。",
        "home.focus.item1.title": "会话是否还在推进",
        "home.focus.item1.copy": "长任务、搜索、构建和子任务运行时，顶部浮岛保留最近状态，让你不用反复回到终端确认。",
        "home.focus.item2.title": "工具调用正在做什么",
        "home.focus.item2.copy": "把工具名、路径、命令和 token 摘要压缩成可扫视的状态，不打断当前编辑流程。",
        "home.focus.item3.title": "审批请求是否需要处理",
        "home.focus.item3.copy": "允许、拒绝、继续和取消集中在 macOS 原生窗口里，减少漏看和误点。",
        "home.surface.eyebrow": "浮岛形态",
        "home.surface.title": "常驻，但不抢屏。",
        "home.surface.copy": "空闲时收成一个安静的小状态点，任务进行时变成紧凑药丸，遇到审批和关键状态时再展开。视觉节奏接近系统通知，而不是新的工作台。",
        "home.surface.link": "了解产品优势",
        "home.workflow.eyebrow": "工作流",
        "home.workflow.title": "为重度 AI 编程的日常节奏设计。",
        "home.workflow.item1.title": "并行运行多个会话",
        "home.workflow.item1.copy": "Claude Code、Codex CLI 和 Codex Desktop 的活动状态统一显示，减少上下文切换。",
        "home.workflow.item2.title": "等待长任务时继续工作",
        "home.workflow.item2.copy": "任务标题、最近工具调用和 token 摘要保持可见，当前窗口不必让位。",
        "home.workflow.item3.title": "在一个地方处理确认",
        "home.workflow.item3.copy": "审批出现时给出明确动作和上下文，让关键决定更容易被正确处理。",
        "home.trust.eyebrow": "信任边界",
        "home.trust.title": "本地优先，是产品边界的一部分。",
        "home.trust.copy": "Vibelsland Free 不创建账号，不上传遥测，不把会话内容同步到远程服务器。它只读取本机已有状态，并让你按来源控制显示内容。",
        "home.trust.read.label": "读取",
        "home.trust.read.value": "本机会话状态",
        "home.trust.write.label": "写入",
        "home.trust.write.value": "本地配置与日志",
        "home.trust.network.label": "网络",
        "home.trust.network.value": "核心功能无需联网",
        "home.cta.eyebrow": "下载",
        "home.cta.title": "把 AI 编程状态放回视线范围内。",
        "home.cta.copy": "免费下载 macOS 版。源码、隐私边界和安装说明全部公开。",
        "home.cta.primary": "下载 macOS 版",
        "home.cta.secondary": "查看源码",

        "advantages.hero.eyebrow": "产品优势",
        "advantages.hero.title": "状态可见，工作不断。",
        "advantages.hero.copy": "Vibelsland Free 把会话进度、工具调用和审批请求压缩成可扫视的状态层。它停留在屏幕顶部，让你继续写代码，同时保留关键上下文。",
        "advantages.hero.primary": "下载 macOS 版",
        "advantages.hero.secondary": "查看本地数据边界",
        "advantages.problems.eyebrow": "价值",
        "advantages.problems.title": "AI 编程时最容易漏看的三件事。",
        "advantages.problems.item1.title": "长任务是否还在推进",
        "advantages.problems.item1.copy": "构建、搜索和工具调用常常持续数分钟。浮岛把最近状态留在屏幕顶部，不需要反复切回终端。",
        "advantages.problems.item2.title": "审批请求在哪里出现",
        "advantages.problems.item2.copy": "允许、拒绝、继续、取消等关键动作集中处理，减少分散在多个工具中的确认成本。",
        "advantages.problems.item3.title": "多个 AI 工具谁在活动",
        "advantages.problems.item3.copy": "Claude Code、Codex CLI 和 Codex Desktop 的状态统一呈现，更适合多会话并行工作。",
        "advantages.compare.eyebrow": "定位",
        "advantages.compare.title": "它补齐状态可见性，而不是改变你的工作流。",
        "advantages.compare.before.title": "没有浮岛时",
        "advantages.compare.before.item1": "状态散在终端、桌面客户端和日志里。",
        "advantages.compare.before.item2": "长任务只能靠不断切窗口判断。",
        "advantages.compare.before.item3": "审批请求出现时容易漏掉上下文。",
        "advantages.compare.after.title": "使用 Vibelsland Free",
        "advantages.compare.after.item1": "顶部保留一个低干扰状态入口。",
        "advantages.compare.after.item2": "任务、工具调用和审批请求统一呈现。",
        "advantages.compare.after.item3": "空闲时收起，关键状态出现时展开。",
        "advantages.native.eyebrow": "macOS 原生",
        "advantages.native.title": "像系统状态一样出现。",
        "advantages.native.copy": "浮岛、设置页、审批窗口和来源开关都围绕 macOS 的使用节奏设计。它可以长期常驻，也能在你不需要时安静隐藏。",
        "advantages.native.item1.label": "形态",
        "advantages.native.item1.value": "小圆点 / 药丸 / 面板",
        "advantages.native.item2.label": "位置",
        "advantages.native.item2.value": "屏幕顶部常驻",
        "advantages.native.item3.label": "控制",
        "advantages.native.item3.value": "按来源启用或关闭",

        "download.hero.eyebrow": "下载",
        "download.hero.title": "下载 macOS 版",
        "download.hero.copy": "当前版本 v0.1.0，适用于 macOS 14+。安装包通过 GitHub Releases 分发，源码、隐私说明和 SHA-256 校验全部公开。",
        "download.hero.primary": "下载 v0.1.0",
        "download.hero.secondary": "查看源码",
        "download.card.label": "当前版本",
        "download.card.version": "v0.1.0",
        "download.card.system.label": "系统要求",
        "download.card.system.value": "macOS 14+",
        "download.card.package.label": "安装包",
        "download.card.package.value": "Vibelsland-Free-0.1.0-macos.zip",
        "download.card.size.label": "大小",
        "download.card.size.value": "约 2.3 MB",
        "download.card.signing.label": "签名状态",
        "download.card.signing.value": "ad-hoc 签名",
        "download.install.eyebrow": "安装",
        "download.install.title": "三步完成安装。",
        "download.install.step1.title": "下载压缩包",
        "download.install.step1.copy": "从 GitHub Releases 下载 Vibelsland-Free-0.1.0-macos.zip。",
        "download.install.step2.title": "拖入 Applications",
        "download.install.step2.copy": "解压后把应用拖到 Applications，再像普通 macOS 应用一样启动。",
        "download.install.step3.title": "启用本地来源",
        "download.install.step3.copy": "打开设置页，按需启用 Claude Code、Codex CLI 和 Codex Desktop 的本地状态来源。",
        "download.security.eyebrow": "签名与校验",
        "download.security.title": "安装前需要知道的事项。",
        "download.security.copy": "当前 v0.1.0 使用 ad-hoc 签名，尚未完成 Developer ID 签名和 Apple notarization。首次打开时如被 macOS 拦截，请按住 Control 点按应用并选择 Open。下载包提供 SHA-256 校验，源码可在 GitHub 查看。",
        "download.security.hash.label": "SHA-256",
        "download.links.eyebrow": "开源透明",
        "download.links.title": "下载、源码、隐私边界放在同一条信任链里。",
        "download.links.release.label": "Release",
        "download.links.release.title": "查看 v0.1.0 发布页",
        "download.links.release.copy": "获取 macOS zip 安装包、SHA-256 文件和发布说明。",
        "download.links.source.label": "Source",
        "download.links.source.title": "查看源码",
        "download.links.source.copy": "确认实现、构建脚本和发布产物。",
        "download.links.privacy.label": "Privacy",
        "download.links.privacy.title": "查看隐私边界",
        "download.links.privacy.copy": "了解应用读取、写入和不会上传的内容。",

        "privacy.hero.eyebrow": "本地优先",
        "privacy.hero.title": "默认留在本机。",
        "privacy.hero.copy": "Vibelsland Free 只读取本机已有的 Claude Code、Codex CLI 和 Codex Desktop 状态，用于展示浮岛和处理审批。它不创建账号，不上传遥测，不同步会话内容到远程服务器。",
        "privacy.hero.primary": "下载前查看安装说明",
        "privacy.hero.secondary": "查看源码中的隐私文件",
        "privacy.summary.account.label": "账号",
        "privacy.summary.account.value": "不需要",
        "privacy.summary.telemetry.label": "遥测",
        "privacy.summary.telemetry.value": "不上传",
        "privacy.summary.sync.label": "同步",
        "privacy.summary.sync.value": "不依赖云端",
        "privacy.data.eyebrow": "数据边界",
        "privacy.data.title": "读取什么，写入什么。",
        "privacy.data.read.title": "会读取",
        "privacy.data.read.item1": "Claude Code、Codex CLI 和 Codex Desktop 的本机状态。",
        "privacy.data.read.item2": "用于展示活动状态、工具调用、token 摘要和审批请求的本机会话信息。",
        "privacy.data.read.item3": "Claude 与 Codex 的本地 hook 配置、会话文件路径和本地运行状态。",
        "privacy.data.write.title": "会写入",
        "privacy.data.write.item1": "应用配置：~/Library/Application Support/VibelslandFree/config.json。",
        "privacy.data.write.item2": "应用日志：~/Library/Logs/VibelslandFree/app.log。",
        "privacy.data.write.item3": "本地桥接运行文件：~/.vibelsland-free。",
        "privacy.no.eyebrow": "无遥测",
        "privacy.no.title": "不会做的事。",
        "privacy.no.item1.label": "账号",
        "privacy.no.item1.value": "不创建线上账号，也不要求登录。",
        "privacy.no.item2.label": "上传",
        "privacy.no.item2.value": "不上传遥测、分析事件或远程同步会话内容。",
        "privacy.no.item3.label": "第三方",
        "privacy.no.item3.value": "本应用不会新增外发目的地。",
        "privacy.control.eyebrow": "用户控制",
        "privacy.control.title": "Hook 只在你选择时修改。",
        "privacy.control.copy": "应用只会在你安装、修复或卸载 hooks 时修改对应配置。Hook payload 会先过滤，只保留会话 ID、事件类型、工作区、审批 ID、工具名、路径和命令等必要元数据。",
        "privacy.network.eyebrow": "网络边界",
        "privacy.network.title": "核心功能不需要互联网连接。",
        "privacy.network.copy": "Vibelsland Free 的状态显示、来源控制和本地审批桥接都在本机完成。Claude Code、Codex CLI 和 Codex Desktop 可能有各自的网络连接，但它们独立于本应用。"
      }
    },
    en: {
      htmlLang: "en",
      meta: {
        index: {
          title: "Vibelsland Free | AI Coding Island",
          description: "Vibelsland Free keeps local Claude Code, Codex CLI, and Codex Desktop status, tool activity, and approvals at the top of macOS.",
          ogTitle: "Vibelsland Free | AI Coding Island",
          ogDescription: "Keep Claude Code, Codex CLI, and Codex Desktop local status at the top of macOS."
        },
        advantages: {
          title: "Advantages | Vibelsland Free",
          description: "See how Vibelsland Free keeps Claude Code, Codex CLI, and Codex Desktop sessions, approvals, and tool activity visible.",
          ogTitle: "Vibelsland Free Advantages",
          ogDescription: "A low-interruption local status layer for intensive AI coding workflows."
        },
        download: {
          title: "Download for macOS | Vibelsland Free",
          description: "Download Vibelsland Free v0.1.0 and review macOS 14+ requirements, first-launch notes, SHA-256 checksum, source code, and privacy boundaries.",
          ogTitle: "Download Vibelsland Free",
          ogDescription: "A local-first macOS AI coding status layer with open source, checksum, and privacy boundaries."
        },
        privacy: {
          title: "Privacy and Local Data | Vibelsland Free",
          description: "Vibelsland Free creates no account, uploads no telemetry, and reads only local Claude Code, Codex CLI, and Codex Desktop state to render the island.",
          ogTitle: "Vibelsland Free Privacy and Local Data",
          ogDescription: "Local-first. No account. No telemetry. No remote session sync."
        }
      },
      strings: {
        "shared.skip": "Skip to content",
        "shared.nav.home": "Home",
        "shared.nav.advantages": "Advantages",
        "shared.nav.download": "Download",
        "shared.nav.privacy": "Privacy",
        "shared.cta": "Download for macOS",
        "shared.footer.tagline": "A local-first AI coding status layer for macOS.",

        "home.hero.eyebrow": "Vibelsland Free · macOS 14+ · Local-first",
        "home.hero.title": "Vibelsland Free",
        "home.hero.kicker": "A local-first status layer for AI coding.",
        "home.hero.copy": "See Claude Code, Codex CLI, and Codex Desktop session progress, tool activity, token summaries, and approval requests in one low-interruption island. No account. No telemetry.",
        "home.hero.primary": "Download for macOS",
        "home.hero.secondary": "View privacy boundaries",
        "home.hero.status": "Tool running · Approval ready",
        "home.spec.system.label": "System",
        "home.spec.system.value": "macOS 14+",
        "home.spec.tools.label": "Tools",
        "home.spec.tools.value": "Claude Code / Codex CLI / Codex Desktop",
        "home.spec.data.label": "Data model",
        "home.spec.data.value": "Local-first",
        "home.spec.version.label": "Version",
        "home.spec.version.value": "v0.1.0",
        "home.focus.eyebrow": "Focus",
        "home.focus.title": "The easy-to-miss signals in AI coding, kept in view.",
        "home.focus.item1.title": "Whether a session is still moving",
        "home.focus.item1.copy": "During long tasks, searches, builds, and subtasks, the island keeps recent status visible so you do not need to return to the terminal.",
        "home.focus.item2.title": "What a tool call is doing",
        "home.focus.item2.copy": "Tool names, paths, commands, and token summaries become glanceable signals without interrupting your editor.",
        "home.focus.item3.title": "Whether an approval needs action",
        "home.focus.item3.copy": "Allow, deny, continue, and cancel actions are handled in one native macOS surface to reduce missed prompts and mistakes.",
        "home.surface.eyebrow": "Surface",
        "home.surface.title": "Always present. Never loud.",
        "home.surface.copy": "It rests as a quiet dot when idle, becomes a compact pill while work is running, and expands only for approvals or important state. The rhythm is closer to a system status surface than a new workspace.",
        "home.surface.link": "Explore advantages",
        "home.workflow.eyebrow": "Workflow",
        "home.workflow.title": "Designed for the daily rhythm of intensive AI coding.",
        "home.workflow.item1.title": "Run multiple sessions in parallel",
        "home.workflow.item1.copy": "Claude Code, Codex CLI, and Codex Desktop activity appears together, reducing window switching.",
        "home.workflow.item2.title": "Keep working while long tasks run",
        "home.workflow.item2.copy": "Task title, recent tool calls, and token summaries remain visible without displacing your current window.",
        "home.workflow.item3.title": "Handle approvals in one place",
        "home.workflow.item3.copy": "When approvals appear, the island provides clear actions and context for better decisions.",
        "home.trust.eyebrow": "Trust",
        "home.trust.title": "Local-first is part of the product boundary.",
        "home.trust.copy": "Vibelsland Free creates no account, uploads no telemetry, and does not sync session content to a remote server. It reads existing local state and lets you control what appears by source.",
        "home.trust.read.label": "Reads",
        "home.trust.read.value": "Local session state",
        "home.trust.write.label": "Writes",
        "home.trust.write.value": "Local config and logs",
        "home.trust.network.label": "Network",
        "home.trust.network.value": "Core features work offline",
        "home.cta.eyebrow": "Download",
        "home.cta.title": "Put AI coding status back in view.",
        "home.cta.copy": "Download for macOS. Source, privacy boundaries, and install notes are public.",
        "home.cta.primary": "Download for macOS",
        "home.cta.secondary": "View source",

        "advantages.hero.eyebrow": "Product advantages",
        "advantages.hero.title": "Status visible. Work uninterrupted.",
        "advantages.hero.copy": "Vibelsland Free compresses progress, tool activity, and approvals into a glanceable status layer. It stays at the top of the screen so you can keep coding without losing context.",
        "advantages.hero.primary": "Download for macOS",
        "advantages.hero.secondary": "View local data boundary",
        "advantages.problems.eyebrow": "Why it matters",
        "advantages.problems.title": "Three things AI coding makes easy to miss.",
        "advantages.problems.item1.title": "Whether long tasks are still moving",
        "advantages.problems.item1.copy": "Builds, searches, and tool calls can run for minutes. The island keeps recent status visible without repeated terminal checks.",
        "advantages.problems.item2.title": "Where approvals appear",
        "advantages.problems.item2.copy": "Allow, deny, continue, and cancel actions are gathered together, reducing confirmation cost across tools.",
        "advantages.problems.item3.title": "Which AI tool is active",
        "advantages.problems.item3.copy": "Claude Code, Codex CLI, and Codex Desktop status is presented together for parallel-session work.",
        "advantages.compare.eyebrow": "Positioning",
        "advantages.compare.title": "It adds state visibility without changing your workflow.",
        "advantages.compare.before.title": "Without the island",
        "advantages.compare.before.item1": "Status is scattered across terminals, desktop clients, and logs.",
        "advantages.compare.before.item2": "Long tasks require repeated window switching.",
        "advantages.compare.before.item3": "Approval requests can appear without enough context.",
        "advantages.compare.after.title": "With Vibelsland Free",
        "advantages.compare.after.item1": "A quiet status surface stays at the top.",
        "advantages.compare.after.item2": "Tasks, tool calls, and approvals appear together.",
        "advantages.compare.after.item3": "It contracts while idle and expands for important state.",
        "advantages.native.eyebrow": "macOS native",
        "advantages.native.title": "It appears like system status.",
        "advantages.native.copy": "The island, settings, approval window, and source controls are designed around macOS habits. It can stay resident, and it can stay quiet when you do not need it.",
        "advantages.native.item1.label": "Shape",
        "advantages.native.item1.value": "Dot / pill / panel",
        "advantages.native.item2.label": "Position",
        "advantages.native.item2.value": "Resident at the top",
        "advantages.native.item3.label": "Control",
        "advantages.native.item3.value": "Enable sources individually",

        "download.hero.eyebrow": "Download",
        "download.hero.title": "Download for macOS",
        "download.hero.copy": "Current version v0.1.0 for macOS 14+. The package is distributed through GitHub Releases with public source, privacy notes, and a SHA-256 checksum.",
        "download.hero.primary": "Download v0.1.0",
        "download.hero.secondary": "View source",
        "download.card.label": "Current version",
        "download.card.version": "v0.1.0",
        "download.card.system.label": "System",
        "download.card.system.value": "macOS 14+",
        "download.card.package.label": "Package",
        "download.card.package.value": "Vibelsland-Free-0.1.0-macos.zip",
        "download.card.size.label": "Size",
        "download.card.size.value": "About 2.3 MB",
        "download.card.signing.label": "Signing",
        "download.card.signing.value": "ad-hoc signed",
        "download.install.eyebrow": "Install",
        "download.install.title": "Install in three steps.",
        "download.install.step1.title": "Download the zip",
        "download.install.step1.copy": "Download Vibelsland-Free-0.1.0-macos.zip from GitHub Releases.",
        "download.install.step2.title": "Move to Applications",
        "download.install.step2.copy": "Unzip it, drag the app into Applications, then launch it like a normal macOS app.",
        "download.install.step3.title": "Enable local sources",
        "download.install.step3.copy": "Open Settings and enable the Claude Code, Codex CLI, and Codex Desktop sources you need.",
        "download.security.eyebrow": "Signing and checksum",
        "download.security.title": "What to know before installing.",
        "download.security.copy": "v0.1.0 uses ad-hoc signing and is not yet Developer ID signed or Apple notarized. If macOS blocks first launch, right-click and choose Open. The download includes a SHA-256 checksum and the source is available on GitHub.",
        "download.security.hash.label": "SHA-256",
        "download.links.eyebrow": "Open source",
        "download.links.title": "Download, source, and privacy stay in one trust chain.",
        "download.links.release.label": "Release",
        "download.links.release.title": "View v0.1.0 release",
        "download.links.release.copy": "Get the macOS zip package, SHA-256 file, and release notes.",
        "download.links.source.label": "Source",
        "download.links.source.title": "View source",
        "download.links.source.copy": "Review implementation, build scripts, and packaged output.",
        "download.links.privacy.label": "Privacy",
        "download.links.privacy.title": "View privacy boundary",
        "download.links.privacy.copy": "Understand what the app reads, writes, and never uploads.",

        "privacy.hero.eyebrow": "Local-first",
        "privacy.hero.title": "Local by default.",
        "privacy.hero.copy": "Vibelsland Free reads local Claude Code, Codex CLI, and Codex Desktop state only to render the island and handle approvals. It creates no account, uploads no telemetry, and does not sync session content to a remote server.",
        "privacy.hero.primary": "Read install notes",
        "privacy.hero.secondary": "View privacy file in source",
        "privacy.summary.account.label": "Account",
        "privacy.summary.account.value": "Not required",
        "privacy.summary.telemetry.label": "Telemetry",
        "privacy.summary.telemetry.value": "Not uploaded",
        "privacy.summary.sync.label": "Sync",
        "privacy.summary.sync.value": "No cloud dependency",
        "privacy.data.eyebrow": "Data boundary",
        "privacy.data.title": "What it reads and writes.",
        "privacy.data.read.title": "It reads",
        "privacy.data.read.item1": "Local Claude Code, Codex CLI, and Codex Desktop state.",
        "privacy.data.read.item2": "Local session information used to show activity, tool calls, token summaries, and approvals.",
        "privacy.data.read.item3": "Local hook configuration, session file paths, and local runtime state for Claude and Codex.",
        "privacy.data.write.title": "It writes",
        "privacy.data.write.item1": "App config: ~/Library/Application Support/VibelslandFree/config.json.",
        "privacy.data.write.item2": "App logs: ~/Library/Logs/VibelslandFree/app.log.",
        "privacy.data.write.item3": "Local bridge runtime files: ~/.vibelsland-free.",
        "privacy.no.eyebrow": "No telemetry",
        "privacy.no.title": "What it does not do.",
        "privacy.no.item1.label": "Account",
        "privacy.no.item1.value": "No online account and no login requirement.",
        "privacy.no.item2.label": "Upload",
        "privacy.no.item2.value": "No telemetry, analytics events, or remote session sync.",
        "privacy.no.item3.label": "Third party",
        "privacy.no.item3.value": "This app adds no new outbound destination.",
        "privacy.control.eyebrow": "Control",
        "privacy.control.title": "Hooks change only when you choose.",
        "privacy.control.copy": "The app modifies hook configuration only when you install, repair, or uninstall hooks. Hook payloads are filtered first and keep only necessary metadata such as session id, event type, workspace, approval id, tool name, path, and command.",
        "privacy.network.eyebrow": "Network",
        "privacy.network.title": "Core features do not require internet access.",
        "privacy.network.copy": "Vibelsland Free status display, source controls, and the local approval bridge work on your Mac. Claude Code, Codex CLI, and Codex Desktop may have their own network connections independently of this app."
      }
    },
    ja: {
      htmlLang: "ja",
      meta: {
        index: {
          title: "Vibelsland Free | AI コーディングアイランド",
          description: "Vibelsland Free は Claude Code、Codex CLI、Codex Desktop の Mac 内の状態、ツール実行、承認リクエストを macOS 上部に表示します。",
          ogTitle: "Vibelsland Free | AI コーディングアイランド",
          ogDescription: "Claude Code、Codex CLI、Codex Desktop のローカル状態を macOS 上部に表示します。"
        },
        advantages: {
          title: "強み | Vibelsland Free",
          description: "Vibelsland Free が Claude Code、Codex CLI、Codex Desktop のセッション状態、承認、ツール実行を見える場所に保つ方法を紹介します。",
          ogTitle: "Vibelsland Free の強み",
          ogDescription: "AI コーディング向けの低干渉なローカルステータスレイヤー。"
        },
        download: {
          title: "macOS 版ダウンロード | Vibelsland Free",
          description: "Vibelsland Free v0.1.0 をダウンロード。macOS 14+ 要件、初回起動、SHA-256、ソース、プライバシー境界を確認できます。",
          ogTitle: "Vibelsland Free をダウンロード",
          ogDescription: "ソース、チェックサム、プライバシー境界を公開した macOS 向けローカルファースト AI coding ステータスレイヤー。"
        },
        privacy: {
          title: "プライバシーとローカルデータ | Vibelsland Free",
          description: "Vibelsland Free はアカウントを作成せず、テレメトリを送信せず、Mac 内の Claude Code、Codex CLI、Codex Desktop 状態だけを使います。",
          ogTitle: "Vibelsland Free プライバシーとローカルデータ",
          ogDescription: "ローカルファースト。アカウントなし。テレメトリなし。リモート同期なし。"
        }
      },
      strings: {
        "shared.skip": "本文へ移動",
        "shared.nav.home": "ホーム",
        "shared.nav.advantages": "強み",
        "shared.nav.download": "ダウンロード",
        "shared.nav.privacy": "プライバシー",
        "shared.cta": "macOS 版をダウンロード",
        "shared.footer.tagline": "macOS 向けローカルファースト AI coding ステータスレイヤー。",

        "home.hero.eyebrow": "Vibelsland Free · macOS 14+ · ローカルファースト",
        "home.hero.title": "Vibelsland Free",
        "home.hero.kicker": "AI coding のためのローカルファーストなステータスレイヤー。",
        "home.hero.copy": "Claude Code、Codex CLI、Codex Desktop のセッション進行、ツール実行、token サマリー、承認リクエストを低干渉なアイランドで確認できます。アカウント不要、テレメトリなし。",
        "home.hero.primary": "macOS 版をダウンロード",
        "home.hero.secondary": "プライバシー境界を見る",
        "home.hero.status": "ツール実行中 · 承認待ち",
        "home.spec.system.label": "システム",
        "home.spec.system.value": "macOS 14+",
        "home.spec.tools.label": "対応ツール",
        "home.spec.tools.value": "Claude Code / Codex CLI / Codex Desktop",
        "home.spec.data.label": "データ方針",
        "home.spec.data.value": "Local-first",
        "home.spec.version.label": "現在の版",
        "home.spec.version.value": "v0.1.0",
        "home.focus.eyebrow": "フォーカス",
        "home.focus.title": "AI コーディングで見落としやすい情報を、見える場所に。",
        "home.focus.item1.title": "セッションが進んでいるか",
        "home.focus.item1.copy": "長いタスク、検索、ビルド、サブタスクの実行中も、最近の状態を画面上部で確認できます。",
        "home.focus.item2.title": "ツール実行が何をしているか",
        "home.focus.item2.copy": "ツール名、パス、コマンド、token サマリーを見やすい信号に圧縮し、エディタ作業を邪魔しません。",
        "home.focus.item3.title": "承認が必要かどうか",
        "home.focus.item3.copy": "許可、拒否、続行、キャンセルを macOS ネイティブの画面にまとめ、見落としや誤操作を減らします。",
        "home.surface.eyebrow": "表示形態",
        "home.surface.title": "常駐しても、主張しすぎない。",
        "home.surface.copy": "待機中は静かな点、実行中は小さなピル、承認や重要な状態のときだけ展開します。新しい作業台ではなく、システム状態表示に近いリズムです。",
        "home.surface.link": "製品の強みを見る",
        "home.workflow.eyebrow": "ワークフロー",
        "home.workflow.title": "AI コーディングを多用する日常に合わせて設計。",
        "home.workflow.item1.title": "複数セッションを並行実行",
        "home.workflow.item1.copy": "Claude Code、Codex CLI、Codex Desktop の活動をまとめて表示し、ウィンドウ切り替えを減らします。",
        "home.workflow.item2.title": "長いタスク中も作業を続ける",
        "home.workflow.item2.copy": "タスク名、最近のツール実行、token サマリーが見えるため、今のウィンドウを明け渡す必要がありません。",
        "home.workflow.item3.title": "承認を一か所で処理",
        "home.workflow.item3.copy": "承認が必要なとき、明確な操作と文脈を表示し、判断しやすくします。",
        "home.trust.eyebrow": "信頼境界",
        "home.trust.title": "ローカルファーストは、製品の境界です。",
        "home.trust.copy": "Vibelsland Free はアカウントを作らず、テレメトリを送信せず、セッション内容をリモートサーバーへ同期しません。Mac 内の状態を読み取り、表示内容をソースごとに制御できます。",
        "home.trust.read.label": "読み取り",
        "home.trust.read.value": "Mac 内のセッション状態",
        "home.trust.write.label": "書き込み",
        "home.trust.write.value": "ローカル設定とログ",
        "home.trust.network.label": "ネットワーク",
        "home.trust.network.value": "主要機能はオフライン対応",
        "home.cta.eyebrow": "ダウンロード",
        "home.cta.title": "AI コーディング状態を視界に戻す。",
        "home.cta.copy": "macOS 版を無料でダウンロード。ソース、プライバシー境界、インストール説明を公開しています。",
        "home.cta.primary": "macOS 版をダウンロード",
        "home.cta.secondary": "ソースを見る",

        "advantages.hero.eyebrow": "製品の強み",
        "advantages.hero.title": "状態は見えるまま、作業は止めない。",
        "advantages.hero.copy": "Vibelsland Free は進行状況、ツール実行、承認リクエストを見やすいステータスレイヤーにまとめます。画面上部に残るため、文脈を失わずに作業を続けられます。",
        "advantages.hero.primary": "macOS 版をダウンロード",
        "advantages.hero.secondary": "ローカルデータ境界を見る",
        "advantages.problems.eyebrow": "価値",
        "advantages.problems.title": "AI コーディングで見落としやすい三つのこと。",
        "advantages.problems.item1.title": "長いタスクが進んでいるか",
        "advantages.problems.item1.copy": "ビルド、検索、ツール実行は数分続くことがあります。アイランドは最近の状態を画面上部に保ちます。",
        "advantages.problems.item2.title": "承認がどこに出るか",
        "advantages.problems.item2.copy": "許可、拒否、続行、キャンセルをまとめ、複数ツールに散らばる確認コストを減らします。",
        "advantages.problems.item3.title": "どの AI ツールが動いているか",
        "advantages.problems.item3.copy": "Claude Code、Codex CLI、Codex Desktop の状態をまとめて表示し、複数セッションの並行作業に合います。",
        "advantages.compare.eyebrow": "位置づけ",
        "advantages.compare.title": "作業流れは変えず、状態の見え方を補います。",
        "advantages.compare.before.title": "アイランドがない場合",
        "advantages.compare.before.item1": "状態がターミナル、デスクトップアプリ、ログに散らばります。",
        "advantages.compare.before.item2": "長いタスクは何度もウィンドウを切り替えて確認します。",
        "advantages.compare.before.item3": "承認リクエストの文脈を見落としやすくなります。",
        "advantages.compare.after.title": "Vibelsland Free を使う場合",
        "advantages.compare.after.item1": "低干渉なステータス表示が画面上部に残ります。",
        "advantages.compare.after.item2": "タスク、ツール実行、承認をまとめて確認できます。",
        "advantages.compare.after.item3": "待機中は小さく、重要な状態だけ展開します。",
        "advantages.native.eyebrow": "macOS ネイティブ",
        "advantages.native.title": "システム状態のように現れます。",
        "advantages.native.copy": "アイランド、設定、承認画面、ソース制御は macOS の使い方に合わせて設計されています。常駐でき、不要なときは静かに隠れます。",
        "advantages.native.item1.label": "形",
        "advantages.native.item1.value": "点 / ピル / パネル",
        "advantages.native.item2.label": "位置",
        "advantages.native.item2.value": "画面上部に常駐",
        "advantages.native.item3.label": "制御",
        "advantages.native.item3.value": "ソースごとに有効化",

        "download.hero.eyebrow": "ダウンロード",
        "download.hero.title": "macOS 版をダウンロード",
        "download.hero.copy": "現在のバージョンは v0.1.0、macOS 14+ 対応。パッケージは GitHub Releases で配布し、ソース、プライバシー説明、SHA-256 チェックサムを公開しています。",
        "download.hero.primary": "v0.1.0 をダウンロード",
        "download.hero.secondary": "ソースを見る",
        "download.card.label": "現在の版",
        "download.card.version": "v0.1.0",
        "download.card.system.label": "システム",
        "download.card.system.value": "macOS 14+",
        "download.card.package.label": "パッケージ",
        "download.card.package.value": "Vibelsland-Free-0.1.0-macos.zip",
        "download.card.size.label": "サイズ",
        "download.card.size.value": "約 2.3 MB",
        "download.card.signing.label": "署名",
        "download.card.signing.value": "ad-hoc 署名",
        "download.install.eyebrow": "インストール",
        "download.install.title": "三つの手順でインストール。",
        "download.install.step1.title": "zip をダウンロード",
        "download.install.step1.copy": "GitHub Releases から Vibelsland-Free-0.1.0-macos.zip をダウンロードします。",
        "download.install.step2.title": "Applications へ移動",
        "download.install.step2.copy": "解凍してアプリを Applications に移動し、通常の macOS アプリとして起動します。",
        "download.install.step3.title": "ローカルソースを有効化",
        "download.install.step3.copy": "設定画面で必要な Claude Code、Codex CLI、Codex Desktop のソースを有効化します。",
        "download.security.eyebrow": "署名とチェックサム",
        "download.security.title": "インストール前に知っておくこと。",
        "download.security.copy": "v0.1.0 は ad-hoc 署名で、Developer ID 署名と Apple notarization にはまだ対応していません。初回起動時に macOS が止めた場合は、Control キーを押しながらアプリをクリックし、Open を選んでください。ダウンロードには SHA-256 チェックサムがあり、ソースは GitHub で確認できます。",
        "download.security.hash.label": "SHA-256",
        "download.links.eyebrow": "オープンソース",
        "download.links.title": "ダウンロード、ソース、プライバシーを一つの信頼線に。",
        "download.links.release.label": "Release",
        "download.links.release.title": "v0.1.0 リリースを見る",
        "download.links.release.copy": "macOS zip パッケージ、SHA-256 ファイル、リリースノートを確認できます。",
        "download.links.source.label": "Source",
        "download.links.source.title": "ソースを見る",
        "download.links.source.copy": "実装、ビルドスクリプト、配布物を確認できます。",
        "download.links.privacy.label": "Privacy",
        "download.links.privacy.title": "プライバシー境界を見る",
        "download.links.privacy.copy": "アプリが読み取り、書き込み、送信しない内容を確認できます。",

        "privacy.hero.eyebrow": "ローカルファースト",
        "privacy.hero.title": "標準で Mac 内に。",
        "privacy.hero.copy": "Vibelsland Free は Claude Code、Codex CLI、Codex Desktop の Mac 内の状態だけを読み取り、アイランド表示と承認処理に使います。アカウントを作らず、テレメトリを送らず、セッション内容をリモートサーバーへ同期しません。",
        "privacy.hero.primary": "インストール説明を見る",
        "privacy.hero.secondary": "ソース内のプライバシーファイルを見る",
        "privacy.summary.account.label": "アカウント",
        "privacy.summary.account.value": "不要",
        "privacy.summary.telemetry.label": "テレメトリ",
        "privacy.summary.telemetry.value": "送信しない",
        "privacy.summary.sync.label": "同期",
        "privacy.summary.sync.value": "クラウド非依存",
        "privacy.data.eyebrow": "データ境界",
        "privacy.data.title": "読み取るもの、書き込むもの。",
        "privacy.data.read.title": "読み取るもの",
        "privacy.data.read.item1": "Claude Code、Codex CLI、Codex Desktop の Mac 内の状態。",
        "privacy.data.read.item2": "活動状態、ツール実行、token サマリー、承認を表示するためのローカルセッション情報。",
        "privacy.data.read.item3": "Claude と Codex のローカル hook 設定、セッションファイルのパス、実行状態。",
        "privacy.data.write.title": "書き込むもの",
        "privacy.data.write.item1": "アプリ設定: ~/Library/Application Support/VibelslandFree/config.json。",
        "privacy.data.write.item2": "アプリログ: ~/Library/Logs/VibelslandFree/app.log。",
        "privacy.data.write.item3": "ローカルブリッジ実行ファイル: ~/.vibelsland-free。",
        "privacy.no.eyebrow": "テレメトリなし",
        "privacy.no.title": "行わないこと。",
        "privacy.no.item1.label": "アカウント",
        "privacy.no.item1.value": "オンラインアカウントの作成やログイン要求はありません。",
        "privacy.no.item2.label": "アップロード",
        "privacy.no.item2.value": "テレメトリ、分析イベント、セッション内容のリモート同期はありません。",
        "privacy.no.item3.label": "第三者",
        "privacy.no.item3.value": "このアプリは新しい外部送信先を追加しません。",
        "privacy.control.eyebrow": "ユーザー制御",
        "privacy.control.title": "Hooks は選択したときだけ変更します。",
        "privacy.control.copy": "アプリは hooks のインストール、修復、アンインストール時だけ設定を変更します。Hook payload は先にフィルタリングされ、セッション ID、イベント種別、ワークスペース、承認 ID、ツール名、パス、コマンドなど必要なメタデータだけを保持します。",
        "privacy.network.eyebrow": "ネットワーク境界",
        "privacy.network.title": "主要機能にインターネット接続は不要です。",
        "privacy.network.copy": "Vibelsland Free のステータス表示、ソース制御、ローカル承認ブリッジは Mac 内で動作します。Claude Code、Codex CLI、Codex Desktop はそれぞれ独自にネットワーク接続を使う場合があります。"
      }
    }
  };

  const activeCopy = copy[lang] || copy.zh;
  const meta = activeCopy.meta[page];

  document.documentElement.lang = activeCopy.htmlLang;

  if (meta) {
    document.title = meta.title;
    document.querySelector('meta[name="description"]')?.setAttribute("content", meta.description);
    document.querySelector('meta[property="og:title"]')?.setAttribute("content", meta.ogTitle);
    document.querySelector('meta[property="og:description"]')?.setAttribute("content", meta.ogDescription);
  }

  document.querySelectorAll("[data-i18n]").forEach((node) => {
    const key = node.getAttribute("data-i18n");
    const value = activeCopy.strings[key];
    if (value) node.textContent = value;
  });

  document.querySelectorAll("[data-lang-option]").forEach((link) => {
    const option = link.getAttribute("data-lang-option");
    link.classList.toggle("active", option === lang);
    link.setAttribute("aria-current", option === lang ? "true" : "false");
    link.setAttribute("href", routeFor(option));
    link.addEventListener("click", () => {
      if (!supported.includes(option)) return;
      try {
        window.localStorage.setItem("vibelsland-lang", option);
      } catch (error) {
        // Keep the link navigation working even when storage is unavailable.
      }
    });
  });

  document.querySelectorAll('a[href$=".html"], a[href*=".html?"], a[href*=".html#"]').forEach((link) => {
    if (link.hasAttribute("data-lang-option")) return;
    const href = link.getAttribute("href");
    if (!href || href.startsWith("http") || href.startsWith("#")) return;
    const url = new URL(href, window.location.href);
    if (url.origin !== window.location.origin || !url.pathname.endsWith(".html")) return;
    const targetFile = url.pathname.split("/").pop() || "index.html";
    link.setAttribute("href", routeFor(lang, targetFile, url.hash));
  });
})();
