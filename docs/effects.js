(function () {
  const root = document.documentElement;

  root.classList.add("js", "page-ready");

  const revealItems = Array.from(document.querySelectorAll("[data-reveal]"));
  if (revealItems.length > 0) {
    revealItems.forEach((element) => element.classList.add("is-visible"));
    root.classList.add("reveal-ready");
  }
})();
