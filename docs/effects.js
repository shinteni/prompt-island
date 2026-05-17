(function () {
  const root = document.documentElement;
  const motionQuery = window.matchMedia("(prefers-reduced-motion: reduce)");
  let reduceMotion = motionQuery.matches;

  const onMotionChange = (callback) => {
    if (typeof motionQuery.addEventListener === "function") {
      motionQuery.addEventListener("change", callback);
    } else if (typeof motionQuery.addListener === "function") {
      motionQuery.addListener(callback);
    }
  };

  root.classList.add("js", "page-ready");

  const bottomNav = document.querySelector(".nav-links");
  const homeHero = document.querySelector(".home-hero");
  if (bottomNav && homeHero) {
    const syncBottomNav = () => {
      const navRect = bottomNav.getBoundingClientRect();
      const heroRect = homeHero.getBoundingClientRect();
      const isMobileNav = window.matchMedia("(max-width: 860px)").matches;
      const overlapsHero = heroRect.bottom > navRect.top;
      root.classList.toggle("mobile-nav-hidden", isMobileNav && window.scrollY < 80 && overlapsHero);
    };

    syncBottomNav();
    window.addEventListener("scroll", syncBottomNav, { passive: true });
    window.addEventListener("resize", syncBottomNav);
  }

  const revealItems = Array.from(document.querySelectorAll("[data-reveal]"));
  if (revealItems.length > 0) {
    const isNearViewport = (element) => {
      const rect = element.getBoundingClientRect();
      const viewport = window.innerHeight || document.documentElement.clientHeight;
      return rect.top < viewport * 1.08 && rect.bottom > viewport * -0.08;
    };

    const showRevealItems = () => {
      revealItems.forEach((element) => element.classList.add("is-visible"));
      root.classList.add("reveal-ready");
    };

    revealItems.forEach((element, index) => {
      element.style.setProperty("--reveal-delay", `${Math.min((index % 4) * 36, 108)}ms`);
    });

    if (reduceMotion || !("IntersectionObserver" in window)) {
      showRevealItems();
    } else {
      revealItems.forEach((element) => {
        if (isNearViewport(element)) element.classList.add("is-visible");
      });
      root.classList.add("reveal-ready");

      const observer = new IntersectionObserver(
        (entries) => {
          for (const entry of entries) {
            if (entry.isIntersecting) {
              entry.target.classList.add("is-visible");
              observer.unobserve(entry.target);
            }
          }
        },
        {
          rootMargin: "0px 0px 14% 0px",
          threshold: 0.04
        }
      );

      revealItems.forEach((element) => {
        if (!element.classList.contains("is-visible")) observer.observe(element);
      });
    }

    onMotionChange((event) => {
      reduceMotion = event.matches;
      if (reduceMotion) showRevealItems();
    });
  }

  const productStage = document.querySelector(".product-stage");
  const demoLabel = productStage?.querySelector(".status-float strong");
  const demoControls = Array.from(document.querySelectorAll("[data-demo-control]"));
  if (productStage && demoLabel) {
    const lang = document.documentElement.lang;
    const states = lang === "ja"
      ? [
          ["running", "デモ · ツール実行中"],
          ["approval", "デモ · 承認待ち"],
          ["idle", "デモ · 待機中"]
        ]
      : lang === "en"
        ? [
            ["running", "Demo · Tool running"],
            ["approval", "Demo · Approval"],
            ["idle", "Demo · Idle"]
          ]
        : [
            ["running", "示例 · 工具运行中"],
            ["approval", "示例 · 等待审批"],
          ["idle", "示例 · 空闲待命"]
        ];
    const stateIndexByName = new Map(states.map((state, stateIndex) => [state[0], stateIndex]));

    let index = 0;
    let demoTimer = 0;
    let resumeTimer = 0;
    const setDemoState = (nextState) => {
      const nextIndex = typeof nextState === "string"
        ? stateIndexByName.get(nextState) ?? 0
        : nextState;
      index = nextIndex;
      productStage.dataset.demoState = states[index][0];
      demoLabel.textContent = states[index][1];
      demoControls.forEach((control) => {
        const isActive = control.dataset.demoControl === states[index][0];
        control.classList.toggle("active", isActive);
        control.setAttribute("aria-pressed", isActive ? "true" : "false");
      });
    };
    const stopDemo = () => {
      if (demoTimer) window.clearInterval(demoTimer);
      demoTimer = 0;
    };
    const scheduleDemoResume = () => {
      if (resumeTimer) window.clearTimeout(resumeTimer);
      resumeTimer = window.setTimeout(() => {
        resumeTimer = 0;
        startDemo();
      }, 8000);
    };
    const startDemo = () => {
      stopDemo();
      if (reduceMotion) return;
      demoTimer = window.setInterval(() => {
        setDemoState((index + 1) % states.length);
      }, 4600);
    };

    setDemoState(0);
    demoControls.forEach((control) => {
      control.addEventListener("click", () => {
        setDemoState(control.dataset.demoControl || "running");
        stopDemo();
        if (!reduceMotion) scheduleDemoResume();
      });
    });
    startDemo();
    onMotionChange((event) => {
      reduceMotion = event.matches;
      if (reduceMotion) {
        stopDemo();
        setDemoState(0);
      } else {
        startDemo();
      }
    });
  }
})();
