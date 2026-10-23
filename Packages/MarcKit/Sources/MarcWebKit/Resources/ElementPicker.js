// Injected on demand into Marc's isolated world when the user zaps elements for a Boost.
// Highlights the element under the pointer; a click reports a selector that uniquely
// identifies it, Escape cancels.
(() => {
  if (window.__marcPickerActive) return;
  window.__marcPickerActive = true;

  const post = (message) => {
    try {
      window.webkit.messageHandlers.marcBoost.postMessage(message);
    } catch (_) {}
  };

  const overlay = document.createElement("div");
  Object.assign(overlay.style, {
    position: "fixed",
    zIndex: "2147483647",
    pointerEvents: "none",
    background: "rgba(255, 80, 80, 0.18)",
    outline: "2px solid rgba(255, 80, 80, 0.9)",
    borderRadius: "3px",
    transition: "all 60ms ease-out",
  });
  document.documentElement.appendChild(overlay);

  const escape = (value) => (window.CSS && CSS.escape ? CSS.escape(value) : value.replace(/[^a-zA-Z0-9_-]/g, "\\$&"));
  const isUnique = (selector) => {
    try {
      return document.querySelectorAll(selector).length === 1;
    } catch (_) {
      return false;
    }
  };

  const describe = (element) => {
    if (element.id && isUnique(`#${escape(element.id)}`)) return `#${escape(element.id)}`;
    const path = [];
    let current = element;
    while (current && current.nodeType === Node.ELEMENT_NODE && current !== document.documentElement) {
      let part = current.tagName.toLowerCase();
      const classes = Array.from(current.classList).filter((name) => !/\d{3,}|^(is|has)-|active|hover|focus/.test(name)).slice(0, 2);
      if (classes.length) part += classes.map((name) => `.${escape(name)}`).join("");
      const parent = current.parentElement;
      if (parent) {
        const siblings = Array.from(parent.children).filter((child) => child.tagName === current.tagName);
        if (siblings.length > 1) part += `:nth-of-type(${siblings.indexOf(current) + 1})`;
      }
      path.unshift(part);
      const selector = path.join(" > ");
      if (isUnique(selector)) return selector;
      if (current.id) {
        const anchored = `#${escape(current.id)} > ${path.slice(1).join(" > ")}`.replace(/ > $/, "");
        if (isUnique(anchored)) return anchored;
      }
      current = parent;
    }
    return path.join(" > ");
  };

  let target = null;
  const move = (event) => {
    target = event.target instanceof Element ? event.target : null;
    if (!target) return;
    const rect = target.getBoundingClientRect();
    Object.assign(overlay.style, {
      left: `${rect.left}px`,
      top: `${rect.top}px`,
      width: `${rect.width}px`,
      height: `${rect.height}px`,
    });
  };

  const cleanup = () => {
    document.removeEventListener("mousemove", move, true);
    document.removeEventListener("click", click, true);
    document.removeEventListener("keydown", key, true);
    overlay.remove();
    window.__marcPickerActive = false;
  };

  const click = (event) => {
    event.preventDefault();
    event.stopPropagation();
    if (!target) return;
    const selector = describe(target);
    target.style.setProperty("display", "none", "important");
    post({ type: "picked", selector });
  };

  const key = (event) => {
    if (event.key === "Escape") {
      event.preventDefault();
      cleanup();
      post({ type: "pickerFinished" });
    }
  };

  window.__marcStopPicker = () => {
    cleanup();
    post({ type: "pickerFinished" });
  };

  document.addEventListener("mousemove", move, true);
  document.addEventListener("click", click, true);
  document.addEventListener("keydown", key, true);
})();
