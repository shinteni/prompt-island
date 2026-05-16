(function () {
  const root = document.documentElement;
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  root.classList.add("js", "page-ready");

  const revealItems = Array.from(document.querySelectorAll("[data-reveal]"));
  if (revealItems.length > 0) {
    const isNearViewport = (element) => {
      const rect = element.getBoundingClientRect();
      const viewport = window.innerHeight || document.documentElement.clientHeight;
      return rect.top < viewport * 1.08 && rect.bottom > viewport * -0.08;
    };

    revealItems.forEach((element, index) => {
      element.style.setProperty("--reveal-delay", `${Math.min((index % 4) * 36, 108)}ms`);
    });

    if (reduceMotion || !("IntersectionObserver" in window)) {
      revealItems.forEach((element) => element.classList.add("is-visible"));
      root.classList.add("reveal-ready");
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
  }

  const productStage = document.querySelector(".product-stage");
  const demoLabel = productStage?.querySelector(".status-float strong");
  if (productStage && demoLabel && !reduceMotion) {
    const lang = document.documentElement.lang;
    const states = lang === "ja"
      ? [
          ["running", "ツール実行中"],
          ["approval", "承認待ち"],
          ["idle", "待機中"]
        ]
      : lang === "en"
        ? [
            ["running", "Tool running"],
            ["approval", "Approval needed"],
            ["idle", "Idle"]
          ]
        : [
            ["running", "工具运行中"],
            ["approval", "等待审批"],
            ["idle", "空闲待命"]
          ];
    let index = 0;
    productStage.dataset.demoState = states[index][0];
    demoLabel.textContent = states[index][1];
    window.setInterval(() => {
      index = (index + 1) % states.length;
      productStage.dataset.demoState = states[index][0];
      demoLabel.textContent = states[index][1];
    }, 2200);
  }

})();
