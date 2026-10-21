// Records how long the page has been hidden, so the harness can tell whether
// it stayed on screen for the whole measurement. No timers: costs nothing.
(() => {
  let hiddenSince = document.hidden ? performance.now() : null;
  let hidden = 0;
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) {
      hiddenSince = performance.now();
    } else if (hiddenSince !== null) {
      hidden += performance.now() - hiddenSince;
      hiddenSince = null;
    }
  });
  window.__hiddenMs = () => hidden + (hiddenSince === null ? 0 : performance.now() - hiddenSince);
})();
