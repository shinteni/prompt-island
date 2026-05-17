(() => {
  const supported = ["zh", "en", "ja"];
  const params = new URLSearchParams(window.location.search);
  const requested = params.get("lang");
  const pathSegments = window.location.pathname.split("/").filter(Boolean);
  const pathLang = pathSegments.find((segment) => supported.includes(segment));
  const file = window.location.pathname.split("/").pop() || "index.html";
  const explicitPage = document.body?.dataset.page || "";
  const page = explicitPage || file.replace(".html", "") || "index";
  const singleFilePage = page === "404";
  const lang = supported.includes(requested)
    ? requested
    : supported.includes(pathLang)
      ? pathLang
      : "zh";
  const rootPrefix = pathLang && pathLang !== "zh" ? "../" : "";
  const pathLanguage = supported.includes(pathLang) ? pathLang : "zh";

  const routeFor = (targetLang, targetFile = file, hash = "") => {
    const normalizedFile = targetFile || "index.html";
    if (singleFilePage && targetFile === file) {
      const query = targetLang === "zh" ? "" : `?lang=${targetLang}`;
      return `404.html${query}${hash}`;
    }
    if (singleFilePage) {
      if (targetLang === "zh") return `${normalizedFile}${hash}`;
      return `${targetLang}/${normalizedFile}${hash}`;
    }
    if (targetLang === "zh") return `${rootPrefix}${normalizedFile}${hash}`;
    if (pathLang === targetLang) return `${normalizedFile}${hash}`;
    return `${rootPrefix}${targetLang}/${normalizedFile}${hash}`;
  };

  if (!singleFilePage && supported.includes(requested) && requested !== pathLanguage) {
    window.location.replace(routeFor(requested, file, window.location.hash));
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
          ogDescription: "为重度 AI 编程工作流提供低干扰的本地状态显示。"
        },
        download: {
          title: "下载 macOS 版 | Vibelsland Free",
          description: "下载 Vibelsland Free v0.1.0，查看 macOS 14+ 系统要求、首次打开说明、SHA-256 校验、源码和隐私边界。",
          ogTitle: "下载 Vibelsland Free",
          ogDescription: "macOS 14+ 本地优先 AI 编程状态显示，源码、校验和隐私边界公开。"
        },
        privacy: {
          title: "隐私与本地数据 | Vibelsland Free",
          description: "Vibelsland Free 不创建账号，不上传遥测，只读取本机 Claude Code、Codex CLI 和 Codex Desktop 状态用于展示浮岛。",
          ogTitle: "Vibelsland Free 隐私与本地数据",
          ogDescription: "本地优先，无账号，无遥测，无远程会话同步。"
        },
        faq: {
          title: "常见问题 | Vibelsland Free",
          description: "了解 Vibelsland Free 的免费分发、macOS 首次打开、SHA-256 校验、本地数据、支持工具和卸载方式。",
          ogTitle: "Vibelsland Free 常见问题",
          ogDescription: "免费、安装、隐私、校验和支持工具的常见问题。"
        },
        support: {
          title: "支持与排障 | Vibelsland Free",
          description: "Vibelsland Free 支持与排障：处理 macOS 首次打开确认、SHA-256 校验、本地数据位置、卸载、报告问题以及工具状态不显示。",
          ogTitle: "Vibelsland Free 支持与排障",
          ogDescription: "安装、校验、本地数据、卸载和状态显示问题的排障说明。"
        },
        install: {
          title: "安装与信任 | Vibelsland Free",
          description: "Vibelsland Free 下载后的第一步：了解 Gatekeeper 首次打开、ad-hoc 签名、SHA-256 校验、源码与 Release 对照、本地权限和数据边界。",
          ogTitle: "Vibelsland Free 安装与信任",
          ogDescription: "下载后先确认首次打开、签名、校验、源码、Release 和本地数据边界。"
        },
        "release-notes": {
          title: "版本历史 | Vibelsland Free",
          description: "Vibelsland Free 版本历史：v0.1.0 的下载、SHA-256 校验、主要功能、安装说明、产品边界和相关支持入口。",
          ogTitle: "Vibelsland Free 版本历史",
          ogDescription: "查看 Vibelsland Free v0.1.0 的发布内容、下载包、校验文件、安装说明和产品边界。"
        },
        404: {
          title: "页面未找到 | Vibelsland Free",
          description: "这个页面不存在或已经移动。返回 Vibelsland Free 首页、产品优势、下载或隐私说明。",
          ogTitle: "页面未找到 | Vibelsland Free",
          ogDescription: "返回 Vibelsland Free 官网继续了解这个 macOS AI 编程浮岛。"
        }
      },
      strings: {
        "aria.mainNav": "主导航",
        "aria.pageNav": "页面导航",
        "aria.language": "语言切换",
        "aria.homeSteps": "三步开始",
        "aria.notFoundPages": "可访问页面",
        "shared.skip": "跳到正文",
        "shared.nav.home": "首页",
        "shared.nav.advantages": "优势",
        "shared.nav.download": "下载",
        "shared.nav.privacy": "隐私",
        "shared.nav.faq": "FAQ",
        "shared.nav.support": "支持",
        "shared.nav.install": "安装",
        "shared.nav.release": "版本历史",
        "shared.nav.home.short": "首页",
        "shared.nav.advantages.short": "优势",
        "shared.nav.download.short": "下载",
        "shared.nav.install.short": "安装",
        "shared.nav.privacy.short": "隐私",
        "shared.nav.faq.short": "FAQ",
        "shared.nav.support.short": "支持",
        "shared.cta": "下载 macOS 版",
        "shared.footer.tagline": "面向 macOS 的本地优先 AI 编程状态显示。",

        "home.hero.title": "开始使用 Vibelsland Free",
        "home.hero.copy": "如果下载没有自动开始，请点击下方。",
        "home.hero.primary": "下载 macOS 版",
        "home.step1.title": "下载 zip",
        "home.step1.copy": "获取 v0.1.0 macOS 包。",
        "home.step1.link": "查看下载详情",
        "home.step2.title": "校验下载",
        "home.step2.copy": "用 SHA-256 确认文件一致。",
        "home.step2.link": "查看安装与信任",
        "home.step3.title": "打开应用",
        "home.step3.copy": "让状态留在 macOS 顶部。",
        "home.step3.link": "查看支持",

        "advantages.hero.eyebrow": "产品优势",
        "advantages.hero.title": "状态可见，工作不断。",
        "advantages.hero.copy": "Vibelsland Free 把会话进度、工具调用和审批请求整理成可扫视的状态显示。它停留在屏幕顶部，让你继续写代码，同时保留关键上下文。",
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
        "advantages.compare.title": "把状态可见性接入你的现有工作流。",
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
        "advantages.cta.eyebrow": "下一步",
        "advantages.cta.title": "准备开始使用。",
        "advantages.cta.copy": "下载 v0.1.0 后，按安装与信任说明完成首次打开、SHA-256 校验和 hooks 健康检查。",
        "advantages.cta.primary": "下载 macOS 版",
        "advantages.cta.secondary": "查看安装与信任",

        "download.hero.eyebrow": "下载",
        "download.hero.title": "下载 macOS 版",
        "download.hero.copy": "v0.1.0，macOS 14+，Apple Silicon / arm64。",
        "download.hero.primary": "下载 v0.1.0",
        "download.hero.secondary": "查看安装与信任",
        "download.card.label": "当前版本",
        "download.card.version": "v0.1.0",
        "download.card.system.label": "系统",
        "download.card.system.value": "macOS 14+",
        "download.card.arch.label": "架构",
        "download.card.arch.value": "Apple Silicon / arm64",
        "download.card.package.label": "安装包",
        "download.card.package.value": "Vibelsland-Free-0.1.0-macos.zip",
        "download.card.app.label": "应用名",
        "download.card.app.value": ">_ - island.app",
        "download.card.size.label": "大小",
        "download.card.size.value": "约 2.3 MB",
        "download.card.signing.label": "签名状态",
        "download.card.signing.value": "ad-hoc 签名",
        "download.card.source.label": "源码版本",
        "download.install.eyebrow": "安装",
        "download.install.title": "三步安装。",
        "download.install.step1.title": "下载 zip",
        "download.install.step1.copy": "把 zip 和同名 .sha256 文件下载到同一目录，例如 Downloads。",
        "download.install.step2.title": "校验 SHA-256",
        "download.install.step2.copy": "运行 <code>cd ~/Downloads &amp;&amp; shasum -a 256 -c Vibelsland-Free-0.1.0-macos.zip.sha256</code>。",
        "download.install.step3.title": "解压并启动",
        "download.install.step3.copy": "把应用拖入 Applications，Control 点按打开，再安装 hooks 并查看设置页健康检查。",
        "download.security.eyebrow": "签名与校验",
        "download.security.title": "校验下载。",
        "download.security.copy": "当前包使用 ad-hoc 签名，不是 Developer ID notarization。SHA-256 只确认文件与 GitHub Release 资产一致，不证明开发者身份；ad-hoc 包的 spctl 可能显示 rejected 或 not accepted。",
        "download.security.hash.label": "SHA-256",
        "download.security.zip": "下载 zip",
        "download.security.sha": "下载 .sha256 文件",
        "download.security.verify": "查看校验命令",
        "download.security.source": "查看源码",
        "download.install.guide": "继续查看完整安装与信任说明",
        "download.install.privacy": "查看本地数据边界",

        "privacy.hero.eyebrow": "本地优先",
        "privacy.hero.title": "默认留在本机。",
        "privacy.hero.copy": "Vibelsland Free 只读取本机已有的 Claude Code、Codex CLI 和 Codex Desktop 状态，用于展示浮岛和处理审批。它不创建账号，不上传遥测，不同步会话内容到远程服务器。",
        "privacy.hero.primary": "查看安装与信任说明",
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
        "privacy.retention.eyebrow": "保留与删除",
        "privacy.retention.title": "本地 token、日志和删除路径说清楚。",
        "privacy.retention.copy": "本地桥接 token 只用于认证本机 socket；日志用于排障，不会主动上传。卸载 hooks 后，可以手动删除运行目录、配置和日志。",
        "privacy.retention.bridge.title": "本地桥接 token",
        "privacy.retention.bridge.item1": "运行文件保存在 <code>~/.vibelsland-free</code>，包含本地 Unix socket 和本地 bridge token。",
        "privacy.retention.bridge.item2": "token 只用于本机进程之间确认请求来源，不是线上账号凭证。",
        "privacy.retention.bridge.item3": "删除 <code>~/.vibelsland-free</code> 会清除运行 token；应用或 hooks 下次启动时会重新建立需要的运行文件。",
        "privacy.retention.logs.title": "日志与删除",
        "privacy.retention.logs.item1": "日志位于 <code>~/Library/Logs/VibelslandFree/app.log</code>，用于记录连接状态、事件类型、时间戳、本地路径和错误原因。",
        "privacy.retention.logs.item2": "应用不会主动上传日志；分享日志前请删除敏感路径、提示词、令牌和会话内容。",
        "privacy.retention.logs.item3": "不再使用时，可以删除 <code>~/Library/Application Support/VibelslandFree</code>、<code>~/Library/Logs/VibelslandFree</code> 和 <code>~/.vibelsland-free</code>。",
        "privacy.control.eyebrow": "用户控制",
        "privacy.control.title": "Hook 只在你选择时修改。",
        "privacy.control.copy": "应用只会在你安装、修复或卸载 hooks 时修改对应配置。Hook payload 会先过滤，只保留会话 ID、事件类型、工作区、审批 ID、工具名、路径和命令等必要元数据。",
        "privacy.network.eyebrow": "网络边界",
        "privacy.network.title": "核心功能不需要互联网连接。",
        "privacy.network.copy": "Vibelsland Free 的状态显示、来源控制和本地审批桥接都在本机完成。Claude Code、Codex CLI 和 Codex Desktop 可能有各自的网络连接，但它们独立于本应用。",

        "notFound.hero.eyebrow": "404",
        "notFound.hero.title": "这个页面暂时不存在",
        "notFound.hero.copy": "链接可能已经移动，或者输入的地址有误。可以回到首页，继续了解 Vibelsland Free 的功能、下载方式和隐私边界。",
        "notFound.hero.primary": "返回首页",
        "notFound.hero.secondary": "下载 macOS 版",
        "notFound.card.label": "可访问页面",
        "notFound.card.product.title": "产品介绍",
        "notFound.card.product.link": "优势",
        "notFound.card.download.title": "获取应用",
        "notFound.card.download.link": "下载",
        "notFound.card.install.title": "安装信任",
        "notFound.card.install.link": "安装",
        "notFound.card.release.title": "版本记录",
        "notFound.card.release.link": "版本历史",
        "notFound.card.privacy.title": "数据边界",
        "notFound.card.privacy.link": "隐私",
        "notFound.card.faq.title": "常见问题",
        "notFound.card.faq.link": "FAQ",
        "notFound.card.support.title": "支持排障",
        "notFound.card.support.link": "支持"
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
          ogDescription: "A low-interruption local status display for intensive AI coding workflows."
        },
        download: {
          title: "Download for macOS | Vibelsland Free",
          description: "Download Vibelsland Free v0.1.0 and review macOS 14+ requirements, first-launch notes, SHA-256 checksum, source code, and privacy boundaries.",
          ogTitle: "Download Vibelsland Free",
          ogDescription: "A local-first macOS AI coding status display with open source, checksum, and privacy boundaries."
        },
        privacy: {
          title: "Privacy and Local Data | Vibelsland Free",
          description: "Vibelsland Free creates no account, uploads no telemetry, and reads only local Claude Code, Codex CLI, and Codex Desktop state to render the island.",
          ogTitle: "Vibelsland Free Privacy and Local Data",
          ogDescription: "Local-first. No account. No telemetry. No remote session sync."
        },
        faq: {
          title: "FAQ | Vibelsland Free",
          description: "Learn about Vibelsland Free pricing, macOS first launch, SHA-256 checksums, local data, supported tools, and uninstall boundaries.",
          ogTitle: "Vibelsland Free FAQ",
          ogDescription: "Common questions about pricing, install, privacy, checksums, and supported tools."
        },
        support: {
          title: "Support and Troubleshooting | Vibelsland Free",
          description: "Support and troubleshooting for Vibelsland Free: first-launch confirmation, SHA-256 verification, local data locations, uninstalling, issue reports, and missing tool status.",
          ogTitle: "Vibelsland Free Support and Troubleshooting",
          ogDescription: "Troubleshoot install, checksum, local data, uninstall, and missing status display issues."
        },
        install: {
          title: "Install & Trust | Vibelsland Free",
          description: "The first step after downloading Vibelsland Free: Gatekeeper first launch, ad-hoc signing, SHA-256 verification, source and Release checks, local permissions, and data boundaries.",
          ogTitle: "Vibelsland Free Install & Trust",
          ogDescription: "Confirm first launch, signing, checksum, source, Release, and local data boundaries after download."
        },
        "release-notes": {
          title: "Release Notes | Vibelsland Free",
          description: "Vibelsland Free release notes for v0.1.0, including downloads, SHA-256 verification, key features, install guidance, product boundaries, and support links.",
          ogTitle: "Vibelsland Free Release Notes",
          ogDescription: "Review Vibelsland Free v0.1.0 features, download assets, checksum file, install guidance, and product boundaries."
        },
        404: {
          title: "Page Not Found | Vibelsland Free",
          description: "This page does not exist or has moved. Return to Vibelsland Free overview, advantages, download, or privacy pages.",
          ogTitle: "Page Not Found | Vibelsland Free",
          ogDescription: "Return to the Vibelsland Free website to continue exploring this macOS AI coding island."
        }
      },
      strings: {
        "aria.mainNav": "Main navigation",
        "aria.pageNav": "Page navigation",
        "aria.language": "Language switch",
        "aria.homeSteps": "Three steps to start",
        "aria.notFoundPages": "Available pages",
        "shared.skip": "Skip to content",
        "shared.nav.home": "Home",
        "shared.nav.advantages": "Advantages",
        "shared.nav.download": "Download",
        "shared.nav.privacy": "Privacy",
        "shared.nav.faq": "FAQ",
        "shared.nav.support": "Support",
        "shared.nav.install": "Install",
        "shared.nav.release": "Release Notes",
        "shared.nav.home.short": "Home",
        "shared.nav.advantages.short": "Value",
        "shared.nav.download.short": "Get",
        "shared.nav.install.short": "Install",
        "shared.nav.privacy.short": "Privacy",
        "shared.nav.faq.short": "FAQ",
        "shared.nav.support.short": "Help",
        "shared.cta": "Download for macOS",
        "shared.footer.tagline": "A local-first AI coding status display for macOS.",

        "home.hero.title": "Start using Vibelsland Free",
        "home.hero.copy": "If the download does not start automatically, click below.",
        "home.hero.primary": "Download for macOS",
        "home.step1.title": "Download zip",
        "home.step1.copy": "Get the v0.1.0 macOS package.",
        "home.step1.link": "View download details",
        "home.step2.title": "Verify the file",
        "home.step2.copy": "Use SHA-256 to confirm the download.",
        "home.step2.link": "Read install and trust",
        "home.step3.title": "Open the app",
        "home.step3.copy": "Keep AI coding status at the top of macOS.",
        "home.step3.link": "View support",

        "advantages.hero.eyebrow": "Product advantages",
        "advantages.hero.title": "Status visible. Work uninterrupted.",
        "advantages.hero.copy": "Vibelsland Free turns progress, tool activity, and approvals into a glanceable status display. It stays at the top of the screen so you can keep coding without losing context.",
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
        "advantages.compare.title": "Bring state visibility into your existing workflow.",
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
        "advantages.cta.eyebrow": "Next step",
        "advantages.cta.title": "Ready to start.",
        "advantages.cta.copy": "After downloading v0.1.0, follow install and trust guidance for first launch, SHA-256 verification, and hooks health checks.",
        "advantages.cta.primary": "Download for macOS",
        "advantages.cta.secondary": "Install & trust",

        "download.hero.eyebrow": "Download",
        "download.hero.title": "Download for macOS",
        "download.hero.copy": "v0.1.0, macOS 14+, Apple Silicon / arm64.",
        "download.hero.primary": "Download v0.1.0",
        "download.hero.secondary": "Install & trust",
        "download.card.label": "Current version",
        "download.card.version": "v0.1.0",
        "download.card.system.label": "System",
        "download.card.system.value": "macOS 14+",
        "download.card.arch.label": "Architecture",
        "download.card.arch.value": "Apple Silicon / arm64",
        "download.card.package.label": "Package",
        "download.card.package.value": "Vibelsland-Free-0.1.0-macos.zip",
        "download.card.app.label": "App name",
        "download.card.app.value": ">_ - island.app",
        "download.card.size.label": "Size",
        "download.card.size.value": "About 2.3 MB",
        "download.card.signing.label": "Signing",
        "download.card.signing.value": "ad-hoc signed",
        "download.card.source.label": "Source commit",
        "download.install.eyebrow": "Install",
        "download.install.title": "Install in three steps.",
        "download.install.step1.title": "Download zip",
        "download.install.step1.copy": "Download the zip and matching .sha256 file into the same folder, such as Downloads.",
        "download.install.step2.title": "Verify SHA-256",
        "download.install.step2.copy": "Run <code>cd ~/Downloads &amp;&amp; shasum -a 256 -c Vibelsland-Free-0.1.0-macos.zip.sha256</code>.",
        "download.install.step3.title": "Unzip and launch",
        "download.install.step3.copy": "Move the app to Applications, Control-click Open, then install hooks and check Settings health.",
        "download.security.eyebrow": "Signing and checksum",
        "download.security.title": "Verify the download.",
        "download.security.copy": "The current package is ad-hoc signed, not Developer ID notarized. SHA-256 only confirms the file matches the GitHub Release asset; it does not prove developer identity. spctl may show rejected or not accepted for this ad-hoc package.",
        "download.security.hash.label": "SHA-256",
        "download.security.zip": "Download zip",
        "download.security.sha": "Download .sha256",
        "download.security.verify": "Show verify command",
        "download.security.source": "View source",
        "download.install.guide": "Continue to full install and trust guidance",
        "download.install.privacy": "View local data boundary",

        "privacy.hero.eyebrow": "Local-first",
        "privacy.hero.title": "Local by default.",
        "privacy.hero.copy": "Vibelsland Free reads local Claude Code, Codex CLI, and Codex Desktop state only to render the island and handle approvals. It creates no account, uploads no telemetry, and does not sync session content to a remote server.",
        "privacy.hero.primary": "Read install and trust notes",
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
        "privacy.retention.eyebrow": "Retention and deletion",
        "privacy.retention.title": "Local tokens, logs, and removal paths are explicit.",
        "privacy.retention.copy": "The local bridge token authenticates the app-local socket only. Logs are for troubleshooting and are not uploaded by the app. After uninstalling hooks, runtime files, config, and logs can be deleted manually.",
        "privacy.retention.bridge.title": "Local bridge token",
        "privacy.retention.bridge.item1": "Runtime files live in <code>~/.vibelsland-free</code>, including the local Unix socket and local bridge token.",
        "privacy.retention.bridge.item2": "The token is used only for local process-to-process request authentication. It is not an online account credential.",
        "privacy.retention.bridge.item3": "Deleting <code>~/.vibelsland-free</code> removes the runtime token; the app or hooks recreate the required runtime files on the next launch.",
        "privacy.retention.logs.title": "Logs and deletion",
        "privacy.retention.logs.item1": "Logs live at <code>~/Library/Logs/VibelslandFree/app.log</code> and record connection state, event types, timestamps, local paths, and error reasons.",
        "privacy.retention.logs.item2": "The app does not upload logs. Before sharing logs, remove sensitive paths, prompts, tokens, and session content.",
        "privacy.retention.logs.item3": "When you stop using the app, you can delete <code>~/Library/Application Support/VibelslandFree</code>, <code>~/Library/Logs/VibelslandFree</code>, and <code>~/.vibelsland-free</code>.",
        "privacy.control.eyebrow": "Control",
        "privacy.control.title": "Hooks change only when you choose.",
        "privacy.control.copy": "The app modifies hook configuration only when you install, repair, or uninstall hooks. Hook payloads are filtered first and keep only necessary metadata such as session id, event type, workspace, approval id, tool name, path, and command.",
        "privacy.network.eyebrow": "Network",
        "privacy.network.title": "Core features do not require internet access.",
        "privacy.network.copy": "Vibelsland Free status display, source controls, and the local approval bridge work on your Mac. Claude Code, Codex CLI, and Codex Desktop may have their own network connections independently of this app.",

        "notFound.hero.eyebrow": "404",
        "notFound.hero.title": "This page is not available",
        "notFound.hero.copy": "The link may have moved, or the address may be incorrect. Return to the overview to continue exploring Vibelsland Free features, download options, and privacy boundaries.",
        "notFound.hero.primary": "Return home",
        "notFound.hero.secondary": "Download for macOS",
        "notFound.card.label": "Available pages",
        "notFound.card.product.title": "Product overview",
        "notFound.card.product.link": "Advantages",
        "notFound.card.download.title": "Get the app",
        "notFound.card.download.link": "Download",
        "notFound.card.install.title": "Install trust",
        "notFound.card.install.link": "Install",
        "notFound.card.release.title": "Release history",
        "notFound.card.release.link": "Release notes",
        "notFound.card.privacy.title": "Data boundary",
        "notFound.card.privacy.link": "Privacy",
        "notFound.card.faq.title": "Common questions",
        "notFound.card.faq.link": "FAQ",
        "notFound.card.support.title": "Support",
        "notFound.card.support.link": "Support"
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
          ogDescription: "AI コーディング向けの低干渉なローカル状態表示。"
        },
        download: {
          title: "macOS 版ダウンロード | Vibelsland Free",
          description: "Vibelsland Free v0.1.0 をダウンロード。macOS 14+ 要件、初回起動、SHA-256、ソース、プライバシー境界を確認できます。",
          ogTitle: "Vibelsland Free をダウンロード",
          ogDescription: "ソース、チェックサム、プライバシー境界を公開した macOS 向けローカルファースト AI コーディングの状態表示。"
        },
        privacy: {
          title: "プライバシーとローカルデータ | Vibelsland Free",
          description: "Vibelsland Free はアカウントを作成せず、テレメトリを送信せず、Mac 内の Claude Code、Codex CLI、Codex Desktop 状態だけを使います。",
          ogTitle: "Vibelsland Free プライバシーとローカルデータ",
          ogDescription: "ローカルファースト。アカウントなし。テレメトリなし。リモート同期なし。"
        },
        faq: {
          title: "FAQ | Vibelsland Free",
          description: "Vibelsland Free の無料配布、macOS 初回起動、SHA-256、ローカルデータ、対応ツール、アンインストール境界を確認できます。",
          ogTitle: "Vibelsland Free FAQ",
          ogDescription: "価格、インストール、プライバシー、チェックサム、対応ツールのよくある質問。"
        },
        support: {
          title: "サポートとトラブルシューティング | Vibelsland Free",
          description: "Vibelsland Free のサポートとトラブルシューティング。macOS の初回起動確認、SHA-256 確認、ローカルデータの場所、アンインストール、問題報告、ツール状態が出ない場合を確認できます。",
          ogTitle: "Vibelsland Free サポートとトラブルシューティング",
          ogDescription: "インストール、チェックサム、ローカルデータ、アンインストール、状態表示の問題を確認できます。"
        },
        install: {
          title: "インストールと信頼 | Vibelsland Free",
          description: "Vibelsland Free をダウンロードした後の最初の手順。Gatekeeper 初回起動、ad-hoc 署名、SHA-256、ソースと Release、ローカル権限、データ境界を確認できます。",
          ogTitle: "Vibelsland Free インストールと信頼",
          ogDescription: "ダウンロード後に初回起動、署名、チェックサム、ソース、Release、ローカルデータ境界を確認します。"
        },
        "release-notes": {
          title: "リリースノート | Vibelsland Free",
          description: "Vibelsland Free v0.1.0 のリリースノート。ダウンロード、SHA-256 確認、主要機能、インストール、製品範囲、サポートリンクを確認できます。",
          ogTitle: "Vibelsland Free リリースノート",
          ogDescription: "Vibelsland Free v0.1.0 の機能、ダウンロード、チェックサム、インストール、製品範囲を確認できます。"
        },
        404: {
          title: "ページが見つかりません | Vibelsland Free",
          description: "このページは存在しないか移動しました。Vibelsland Free のホーム、強み、ダウンロード、プライバシーへ戻れます。",
          ogTitle: "ページが見つかりません | Vibelsland Free",
          ogDescription: "Vibelsland Free のサイトへ戻り、この macOS AI コーディングアイランドを確認できます。"
        }
      },
      strings: {
        "aria.mainNav": "メインナビゲーション",
        "aria.pageNav": "ページナビゲーション",
        "aria.language": "言語切替",
        "aria.homeSteps": "開始する三つの手順",
        "aria.notFoundPages": "利用できるページ",
        "shared.skip": "本文へ移動",
        "shared.nav.home": "ホーム",
        "shared.nav.advantages": "強み",
        "shared.nav.download": "ダウンロード",
        "shared.nav.privacy": "プライバシー",
        "shared.nav.faq": "FAQ",
        "shared.nav.support": "サポート",
        "shared.nav.install": "インストール",
        "shared.nav.release": "リリースノート",
        "shared.nav.home.short": "ホーム",
        "shared.nav.advantages.short": "強み",
        "shared.nav.download.short": "入手",
        "shared.nav.install.short": "導入",
        "shared.nav.privacy.short": "個人情報",
        "shared.nav.faq.short": "FAQ",
        "shared.nav.support.short": "支援",
        "shared.cta": "macOS 版をダウンロード",
        "shared.footer.tagline": "macOS 向けローカルファースト AI コーディングの状態表示。",

        "home.hero.title": "Vibelsland Free を開始",
        "home.hero.copy": "ダウンロードが自動で始まらない場合は、下をクリックしてください。",
        "home.hero.primary": "macOS 版をダウンロード",
        "home.step1.title": "zip をダウンロード",
        "home.step1.copy": "v0.1.0 の macOS パッケージを取得します。",
        "home.step1.link": "ダウンロード詳細を見る",
        "home.step2.title": "ファイルを確認",
        "home.step2.copy": "SHA-256 でダウンロードを確認します。",
        "home.step2.link": "インストールと信頼を見る",
        "home.step3.title": "アプリを開く",
        "home.step3.copy": "AI コーディング状態を macOS 上部に表示します。",
        "home.step3.link": "サポートを見る",

        "advantages.hero.eyebrow": "製品の強み",
        "advantages.hero.title": "状態は見えるまま、作業は止めない。",
        "advantages.hero.copy": "Vibelsland Free は進行状況、ツール実行、承認リクエストを見やすい状態表示にまとめます。画面上部に残るため、文脈を保ったまま作業を続けられます。",
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
        "advantages.compare.title": "既存のワークフローに状態の見え方を加えます。",
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
        "advantages.cta.eyebrow": "次のステップ",
        "advantages.cta.title": "使い始める準備。",
        "advantages.cta.copy": "v0.1.0 をダウンロードした後、インストールと信頼の手順で初回起動、SHA-256 確認、hooks のヘルスチェックを確認できます。",
        "advantages.cta.primary": "macOS 版をダウンロード",
        "advantages.cta.secondary": "インストールと信頼",

        "download.hero.eyebrow": "ダウンロード",
        "download.hero.title": "macOS 版をダウンロード",
        "download.hero.copy": "v0.1.0、macOS 14+、Apple Silicon / arm64。",
        "download.hero.primary": "v0.1.0 をダウンロード",
        "download.hero.secondary": "インストールと信頼",
        "download.card.label": "現在の版",
        "download.card.version": "v0.1.0",
        "download.card.system.label": "システム",
        "download.card.system.value": "macOS 14+",
        "download.card.arch.label": "アーキテクチャ",
        "download.card.arch.value": "Apple Silicon / arm64",
        "download.card.package.label": "パッケージ",
        "download.card.package.value": "Vibelsland-Free-0.1.0-macos.zip",
        "download.card.app.label": "アプリ名",
        "download.card.app.value": ">_ - island.app",
        "download.card.size.label": "サイズ",
        "download.card.size.value": "約 2.3 MB",
        "download.card.signing.label": "署名",
        "download.card.signing.value": "ad-hoc 署名",
        "download.card.source.label": "ソース commit",
        "download.install.eyebrow": "インストール",
        "download.install.title": "三つの手順でインストール。",
        "download.install.step1.title": "zip をダウンロード",
        "download.install.step1.copy": "zip と同名の .sha256 ファイルを Downloads など同じフォルダに保存します。",
        "download.install.step2.title": "SHA-256 を確認",
        "download.install.step2.copy": "<code>cd ~/Downloads &amp;&amp; shasum -a 256 -c Vibelsland-Free-0.1.0-macos.zip.sha256</code> を実行します。",
        "download.install.step3.title": "解凍して起動",
        "download.install.step3.copy": "Applications に移動し、Control クリックで開き、hooks を入れて設定画面のヘルスチェックを確認します。",
        "download.security.eyebrow": "署名とチェックサム",
        "download.security.title": "ダウンロードを確認。",
        "download.security.copy": "現在のパッケージは ad-hoc 署名で、Developer ID notarization ではありません。SHA-256 は GitHub Release の配布物と一致することだけを確認し、開発者本人性を証明するものではありません。ad-hoc パッケージでは spctl が rejected または not accepted を示すことがあります。",
        "download.security.hash.label": "SHA-256",
        "download.security.zip": "zip をダウンロード",
        "download.security.sha": ".sha256 をダウンロード",
        "download.security.verify": "確認コマンドを見る",
        "download.security.source": "ソースを見る",
        "download.install.guide": "完全なインストールと信頼の手順を見る",
        "download.install.privacy": "ローカルデータ境界を見る",

        "privacy.hero.eyebrow": "ローカルファースト",
        "privacy.hero.title": "標準で Mac 内に。",
        "privacy.hero.copy": "Vibelsland Free は Claude Code、Codex CLI、Codex Desktop の Mac 内の状態だけを読み取り、アイランド表示と承認処理に使います。アカウントを作らず、テレメトリを送らず、セッション内容をリモートサーバーへ同期しません。",
        "privacy.hero.primary": "インストールと信頼の説明を見る",
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
        "privacy.data.write.item3": "ローカルブリッジのランタイムファイル: ~/.vibelsland-free。",
        "privacy.no.eyebrow": "テレメトリなし",
        "privacy.no.title": "行わないこと。",
        "privacy.no.item1.label": "アカウント",
        "privacy.no.item1.value": "オンラインアカウントの作成やログイン要求はありません。",
        "privacy.no.item2.label": "アップロード",
        "privacy.no.item2.value": "テレメトリ、分析イベント、セッション内容のリモート同期はありません。",
        "privacy.no.item3.label": "第三者",
        "privacy.no.item3.value": "このアプリは新しい外部送信先を追加しません。",
        "privacy.retention.eyebrow": "保持と削除",
        "privacy.retention.title": "ローカル token、ログ、削除場所を明確にします。",
        "privacy.retention.copy": "ローカル bridge token は Mac 内の socket 認証だけに使われます。ログはトラブルシューティング用で、アプリがアップロードすることはありません。hooks をアンインストールした後、実行ファイル、設定、ログは手動で削除できます。",
        "privacy.retention.bridge.title": "ローカル bridge token",
        "privacy.retention.bridge.item1": "実行ファイルは <code>~/.vibelsland-free</code> にあり、ローカル Unix socket とローカル bridge token を含みます。",
        "privacy.retention.bridge.item2": "token は Mac 内のプロセス間でリクエスト元を確認するためだけに使われ、オンラインアカウントの認証情報ではありません。",
        "privacy.retention.bridge.item3": "<code>~/.vibelsland-free</code> を削除すると実行 token は消えます。次回起動時にアプリまたは hooks が必要な実行ファイルを作り直します。",
        "privacy.retention.logs.title": "ログと削除",
        "privacy.retention.logs.item1": "ログは <code>~/Library/Logs/VibelslandFree/app.log</code> にあり、接続状態、イベント種別、時刻、ローカルパス、エラー理由を記録します。",
        "privacy.retention.logs.item2": "アプリはログをアップロードしません。ログを共有する前に、機密性のあるパス、プロンプト、token、セッション内容を削除してください。",
        "privacy.retention.logs.item3": "使用をやめる場合は、<code>~/Library/Application Support/VibelslandFree</code>、<code>~/Library/Logs/VibelslandFree</code>、<code>~/.vibelsland-free</code> を削除できます。",
        "privacy.control.eyebrow": "ユーザー制御",
        "privacy.control.title": "Hooks は選択したときだけ変更します。",
        "privacy.control.copy": "アプリは hooks のインストール、修復、アンインストール時だけ設定を変更します。Hook payload は先にフィルタリングされ、セッション ID、イベント種別、ワークスペース、承認 ID、ツール名、パス、コマンドなど必要なメタデータだけを保持します。",
        "privacy.network.eyebrow": "ネットワーク境界",
        "privacy.network.title": "主要機能にインターネット接続は不要です。",
        "privacy.network.copy": "Vibelsland Free のステータス表示、ソース制御、ローカル承認ブリッジは Mac 内で動作します。Claude Code、Codex CLI、Codex Desktop はそれぞれ独自にネットワーク接続を使う場合があります。",

        "notFound.hero.eyebrow": "404",
        "notFound.hero.title": "このページはありません",
        "notFound.hero.copy": "リンクが移動したか、入力したアドレスが正しくない可能性があります。ホームに戻り、Vibelsland Free の機能、ダウンロード、プライバシー境界を確認できます。",
        "notFound.hero.primary": "ホームへ戻る",
        "notFound.hero.secondary": "macOS 版をダウンロード",
        "notFound.card.label": "利用できるページ",
        "notFound.card.product.title": "製品紹介",
        "notFound.card.product.link": "強み",
        "notFound.card.download.title": "アプリ入手",
        "notFound.card.download.link": "ダウンロード",
        "notFound.card.install.title": "インストール信頼",
        "notFound.card.install.link": "インストール",
        "notFound.card.release.title": "バージョン履歴",
        "notFound.card.release.link": "リリースノート",
        "notFound.card.privacy.title": "データ境界",
        "notFound.card.privacy.link": "プライバシー",
        "notFound.card.faq.title": "よくある質問",
        "notFound.card.faq.link": "FAQ",
        "notFound.card.support.title": "サポート",
        "notFound.card.support.link": "サポート"
      }
    }
  };

  const activeCopy = copy[lang] || copy.zh;
  const meta = activeCopy.meta[page];
  const socialMeta = {
    zh: {
      locale: "zh_CN",
      imageAlt: "Vibelsland Free macOS AI 编程状态界面"
    },
    en: {
      locale: "en_US",
      imageAlt: "Vibelsland Free macOS AI coding status interface"
    },
    ja: {
      locale: "ja_JP",
      imageAlt: "Vibelsland Free macOS AI コーディング状態インターフェイス"
    }
  }[lang] || {
    locale: "zh_CN",
    imageAlt: "Vibelsland Free macOS AI 编程状态界面"
  };

  document.documentElement.lang = activeCopy.htmlLang;

  if (meta) {
    document.title = meta.title;
    document.querySelector('meta[name="description"]')?.setAttribute("content", meta.description);
    document.querySelector('meta[property="og:title"]')?.setAttribute("content", meta.ogTitle);
    document.querySelector('meta[property="og:description"]')?.setAttribute("content", meta.ogDescription);
    document.querySelector('meta[property="og:locale"]')?.setAttribute("content", socialMeta.locale);
    document.querySelector('meta[property="og:image:alt"]')?.setAttribute("content", socialMeta.imageAlt);
    document.querySelector('meta[name="twitter:image:alt"]')?.setAttribute("content", socialMeta.imageAlt);
  }

  document.querySelectorAll("[data-i18n]").forEach((node) => {
    const key = node.getAttribute("data-i18n");
    const value = activeCopy.strings[key];
    if (value && node.hasAttribute("data-i18n-html")) {
      node.innerHTML = value;
    } else if (value) {
      node.textContent = value;
    }
    const mobileValue = activeCopy.strings[`${key}.short`];
    if (mobileValue) node.setAttribute("data-mobile-label", mobileValue);
  });

  document.querySelectorAll("[data-i18n-aria-label]").forEach((node) => {
    const key = node.getAttribute("data-i18n-aria-label");
    const value = activeCopy.strings[key];
    if (value) node.setAttribute("aria-label", value);
  });

  document.querySelectorAll(".nav-links a").forEach((link) => {
    if (link.classList.contains("active")) {
      link.setAttribute("aria-current", "page");
    } else {
      link.removeAttribute("aria-current");
    }
  });
  document.querySelector(".nav-links a.active")?.scrollIntoView({
    block: "nearest",
    inline: "center"
  });

  document.querySelectorAll("[data-lang-option]").forEach((link) => {
    const option = link.getAttribute("data-lang-option");
    link.classList.toggle("active", option === lang);
    link.setAttribute("aria-current", option === lang ? "true" : "false");
    link.setAttribute("href", routeFor(option, file, window.location.hash));
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
