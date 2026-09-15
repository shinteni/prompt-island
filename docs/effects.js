(() => {
  const root = document.documentElement;
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  const revealItems = [...document.querySelectorAll("[data-reveal]")];
  const motionItems = [...document.querySelectorAll("[data-motion]")];

  const syncMotion = () => {
    root.classList.toggle("motion-paused", document.hidden || reducedMotion.matches);
    if (reducedMotion.matches) revealItems.forEach((item) => item.classList.add("is-visible"));
  };
  syncMotion();
  document.addEventListener("visibilitychange", syncMotion);
  reducedMotion.addEventListener("change", syncMotion);

  if ("IntersectionObserver" in window) {
    const revealObserver = new IntersectionObserver((entries) => {
      entries.forEach(({ target, isIntersecting }) => {
        if (!isIntersecting) return;
        target.classList.add("is-visible");
        revealObserver.unobserve(target);
      });
    }, { threshold: 0.08 });
    revealItems.forEach((item) => revealObserver.observe(item));
    root.classList.add("reveal-ready");

    const motionObserver = new IntersectionObserver((entries) => {
      entries.forEach(({ target, isIntersecting }) => target.classList.toggle("motion-active", isIntersecting));
    });
    motionItems.forEach((item) => motionObserver.observe(item));
  } else {
    revealItems.forEach((item) => item.classList.add("is-visible"));
    motionItems.forEach((item) => item.classList.add("motion-active"));
  }
  root.classList.add("js", "page-ready");

  const playground = document.querySelector(".island-playground");
  if (!playground) return;
  const tabs = [...playground.querySelectorAll("[data-demo-state]")];
  const panels = [...playground.querySelectorAll('[role="tabpanel"]')];
  const feedback = playground.querySelector(".demo-feedback");
  const caption = playground.querySelector(".demo-caption");
  const selectState = (tab, focus = false) => {
    playground.dataset.state = tab.dataset.demoState;
    tabs.forEach((item) => {
      item.setAttribute("aria-selected", String(item === tab));
      item.tabIndex = item === tab ? 0 : -1;
    });
    panels.forEach((panel) => { panel.hidden = panel.id !== tab.getAttribute("aria-controls"); });
    caption.hidden = tab.dataset.demoState !== "running";
    feedback.textContent = "";
    if (focus) tab.focus();
  };
  tabs.forEach((tab, index) => {
    tab.addEventListener("click", () => selectState(tab));
    tab.addEventListener("keydown", (event) => {
      let next;
      if (event.key === "ArrowRight") next = (index + 1) % tabs.length;
      if (event.key === "ArrowLeft") next = (index + tabs.length - 1) % tabs.length;
      if (event.key === "Home") next = 0;
      if (event.key === "End") next = tabs.length - 1;
      if (next === undefined) return;
      event.preventDefault();
      selectState(tabs[next], true);
    });
  });
  playground.querySelectorAll("[data-demo-decision]").forEach((button) => {
    button.addEventListener("click", () => {
      feedback.textContent = button.dataset.demoDecision === "allow" ? feedback.dataset.allowed : feedback.dataset.denied;
    });
  });
  playground.querySelector("[data-demo-expand]").addEventListener("click", () => selectState(tabs[0], true));
})();
