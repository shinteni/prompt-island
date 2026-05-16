(function () {
  const root = document.documentElement;
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  root.classList.add("js", "page-ready");

  const revealItems = Array.from(document.querySelectorAll("[data-reveal]"));
  if (revealItems.length > 0) {
    root.classList.add("reveal-ready");

    revealItems.forEach((element, index) => {
      element.style.setProperty("--reveal-delay", `${Math.min((index % 4) * 36, 108)}ms`);
    });

    if (reduceMotion || !("IntersectionObserver" in window)) {
      revealItems.forEach((element) => element.classList.add("is-visible"));
    } else {
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
          rootMargin: "0px 0px -10% 0px",
          threshold: 0.12
        }
      );

      revealItems.forEach((element) => observer.observe(element));
    }
  }

  const isModifiedClick = (event) =>
    event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || event.button !== 0;

  document.addEventListener("click", (event) => {
    if (reduceMotion || isModifiedClick(event)) return;

    const link = event.target.closest("a[href]");
    if (!link || link.target || link.hasAttribute("download")) return;

    const url = new URL(link.getAttribute("href"), window.location.href);
    const sameHost = url.protocol === window.location.protocol && url.host === window.location.host;
    const isPage = url.pathname.endsWith(".html") || url.pathname.endsWith("/");
    const isSameHash = url.pathname === window.location.pathname && url.hash;

    if (!sameHost || !isPage || isSameHash) return;

    event.preventDefault();
    root.classList.add("page-leaving");
    window.setTimeout(() => {
      window.location.href = url.href;
    }, 120);
  });
})();
