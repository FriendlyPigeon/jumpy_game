export function subscribe(onResize, onHidden) {
  const reportSize = () => onResize(window.innerWidth, window.innerHeight);

  reportSize();
  window.addEventListener("resize", reportSize, { passive: true });
  window.addEventListener("orientationchange", reportSize, { passive: true });
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "hidden") {
      onHidden();
    } else {
      reportSize();
    }
  });
}
