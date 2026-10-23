// Runs in Marc's isolated content world in the main frame only. Detects login forms, reports
// focused credential fields (so the browser can offer saved logins) and submitted credentials
// (so it can offer to save them). Filling happens only when the browser calls __marcFill after
// an explicit user choice.
(() => {
  const post = (message) => {
    try {
      window.webkit.messageHandlers.marcAutofill.postMessage(message);
    } catch (_) {}
  };

  const isVisible = (element) => {
    const rect = element.getBoundingClientRect();
    const style = getComputedStyle(element);
    return rect.width > 0 && rect.height > 0 && style.visibility !== "hidden" && style.display !== "none";
  };

  const passwordFields = () => Array.from(document.querySelectorAll('input[type="password"]')).filter(isVisible);

  const usernameField = (password) => {
    const scope = password.form || document;
    const candidates = Array.from(
      scope.querySelectorAll('input:not([type]), input[type="text"], input[type="email"], input[type="tel"]')
    ).filter(isVisible);
    const preceding = candidates.filter((candidate) => candidate.compareDocumentPosition(password) & Node.DOCUMENT_POSITION_FOLLOWING);
    const hinted = candidates.find((candidate) =>
      /user|login|email|account|identifier/i.test(`${candidate.name} ${candidate.id} ${candidate.autocomplete}`)
    );
    return preceding.pop() || hinted || null;
  };

  const isNewPasswordField = (field) => /new-password/i.test(field.autocomplete || "");

  const rectOf = (element) => {
    const rect = element.getBoundingClientRect();
    return { x: rect.left, y: rect.top, width: rect.width, height: rect.height };
  };

  document.addEventListener(
    "focusin",
    (event) => {
      const target = event.target;
      if (!(target instanceof HTMLInputElement)) return;
      const passwords = passwordFields();
      if (!passwords.length) return;
      const isPassword = target.type === "password";
      const isUsername = !isPassword && passwords.some((password) => usernameField(password) === target);
      if (!isPassword && !isUsername) return;
      post({
        type: "fieldFocused",
        kind: isPassword ? "password" : "username",
        isNewPassword: isPassword && isNewPasswordField(target),
        rect: rectOf(target),
      });
    },
    true
  );

  document.addEventListener(
    "focusout",
    (event) => {
      if (event.target instanceof HTMLInputElement) post({ type: "fieldBlurred" });
    },
    true
  );

  let lastSubmission = null;
  const captureSubmission = () => {
    const password = passwordFields().find((field) => field.value);
    if (!password) return;
    const user = usernameField(password);
    const submission = { username: user ? user.value : "", password: password.value };
    const key = `${submission.username}\u0000${submission.password}`;
    if (key === lastSubmission) return;
    lastSubmission = key;
    post({ type: "submitted", username: submission.username, password: submission.password });
  };

  document.addEventListener("submit", captureSubmission, true);
  document.addEventListener(
    "click",
    (event) => {
      const button = event.target instanceof Element ? event.target.closest('button, input[type="submit"], [role="button"]') : null;
      if (button && passwordFields().length) setTimeout(captureSubmission, 0);
    },
    true
  );
  document.addEventListener(
    "keydown",
    (event) => {
      if (event.key === "Enter" && event.target instanceof HTMLInputElement && passwordFields().length) captureSubmission();
    },
    true
  );

  const setValue = (field, value) => {
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set;
    field.focus();
    setter.call(field, value);
    field.dispatchEvent(new Event("input", { bubbles: true }));
    field.dispatchEvent(new Event("change", { bubbles: true }));
  };

  window.__marcFill = (username, password, generated) => {
    const passwords = passwordFields();
    if (!passwords.length) return false;
    if (generated) {
      passwords.filter(isNewPasswordField).concat(passwords.length === 1 ? passwords : []).forEach((field) => setValue(field, password));
      return true;
    }
    const target = passwords[0];
    const user = usernameField(target);
    if (user && username) setValue(user, username);
    setValue(target, password);
    return true;
  };

  const report = () => post({ type: "formsDetected", count: passwordFields().length });
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", report, { once: true });
  } else {
    report();
  }
})();
