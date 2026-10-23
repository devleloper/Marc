// Runs in Marc's isolated content world in the main frame. Reports hovered links, page icons,
// theme color and media playback state to the browser. Page scripts cannot see this code or
// post to its message handler.
(() => {
  const post = (message) => {
    try {
      window.webkit.messageHandlers.marcPage.postMessage(message);
    } catch (_) {}
  };

  let hoveredHref = null;
  const updateHover = (href) => {
    if (href === hoveredHref) return;
    hoveredHref = href;
    post({ type: "hover", href });
  };
  document.addEventListener(
    "mouseover",
    (event) => {
      const anchor = event.target instanceof Element ? event.target.closest("a[href]") : null;
      updateHover(anchor ? anchor.href : null);
    },
    true
  );
  document.addEventListener("mouseleave", () => updateHover(null), true);
  window.addEventListener("blur", () => updateHover(null));

  let iconTimer = null;
  const collectIcons = () => {
    iconTimer = null;
    const selector = 'link[rel~="icon"], link[rel="shortcut icon"], link[rel~="apple-touch-icon"], link[rel~="apple-touch-icon-precomposed"]';
    const icons = Array.from(document.querySelectorAll(selector))
      .filter((link) => link.href)
      .map((link) => ({
        href: link.href,
        sizes: link.getAttribute("sizes") || "",
        rel: link.rel || "",
        type: link.type || "",
      }));
    const themeColor = document.querySelector('meta[name="theme-color"]');
    post({ type: "icons", icons, themeColor: themeColor ? themeColor.content : null });
  };
  const scheduleIcons = () => {
    if (iconTimer === null) iconTimer = setTimeout(collectIcons, 250);
  };
  const observeHead = () => {
    collectIcons();
    const head = document.head || document.documentElement;
    new MutationObserver(scheduleIcons).observe(head, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ["href", "content", "rel"],
    });
  };
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", observeHead, { once: true });
  } else {
    observeHead();
  }

  // A video is in Picture in Picture through the standard API or WebKit's presentation modes.
  const pictureInPictureVideo = () =>
    document.pictureInPictureElement ||
    Array.from(document.querySelectorAll("video")).find((video) => video.webkitPresentationMode === "picture-in-picture");

  const reportMedia = () => {
    const media = Array.from(document.querySelectorAll("video, audio"));
    const active = media.filter((element) => !element.paused && !element.ended);
    const metadata = navigator.mediaSession ? navigator.mediaSession.metadata : null;
    const artwork = metadata && metadata.artwork && metadata.artwork.length ? metadata.artwork[metadata.artwork.length - 1].src : null;
    post({
      type: "media",
      isPlaying: active.length > 0,
      isAudible: active.some((element) => !element.muted && element.volume > 0),
      isMuted: media.length > 0 && media.every((element) => element.muted),
      hasVideo: media.some((element) => element.tagName === "VIDEO" && element.readyState > 0),
      hasMedia: media.length > 0,
      isInPictureInPicture: Boolean(pictureInPictureVideo()),
      title: metadata && metadata.title ? metadata.title : null,
      artist: metadata && metadata.artist ? metadata.artist : null,
      artwork,
    });
  };
  let mediaTimer = null;
  const scheduleMedia = () => {
    if (mediaTimer === null) {
      mediaTimer = setTimeout(() => {
        mediaTimer = null;
        reportMedia();
      }, 50);
    }
  };
  const mediaEvents = ["play", "playing", "pause", "ended", "volumechange", "emptied", "loadedmetadata",
    "enterpictureinpicture", "leavepictureinpicture", "webkitpresentationmodechanged"];
  for (const name of mediaEvents) {
    document.addEventListener(name, scheduleMedia, true);
  }

  // Muting applies to media elements added later as well.
  let muteObserver = null;
  window.__marcSetMuted = (muted) => {
    const apply = () => document.querySelectorAll("video, audio").forEach((element) => (element.muted = muted));
    apply();
    if (muteObserver) muteObserver.disconnect();
    muteObserver = null;
    if (muted) {
      muteObserver = new MutationObserver(apply);
      muteObserver.observe(document.documentElement, { childList: true, subtree: true });
    }
    scheduleMedia();
  };

  window.__marcTogglePlayback = () => {
    const media = Array.from(document.querySelectorAll("video, audio"));
    const playing = media.find((element) => !element.paused && !element.ended);
    if (playing) {
      playing.pause();
      return "paused";
    }
    const candidate = media.find((element) => element.currentTime > 0) || media[0];
    if (candidate) {
      candidate.play().catch(() => {});
      return "playing";
    }
    return "none";
  };

  // The video worth showing: a playing one first, otherwise the largest one with data.
  const pictureInPictureCandidate = () => {
    const videos = Array.from(document.querySelectorAll("video")).filter((video) => video.readyState > 0);
    const area = (video) => video.clientWidth * video.clientHeight;
    return videos.find((video) => !video.paused && !video.ended) || videos.sort((a, b) => area(b) - area(a))[0];
  };

  // mode: "toggle", "enter" or "exit". Returns what happened, for Marc's log.
  window.__marcPictureInPicture = async (mode) => {
    const current = pictureInPictureVideo();
    if (current) {
      if (mode === "enter") return "already";
      if (document.pictureInPictureElement) await document.exitPictureInPicture();
      else current.webkitSetPresentationMode("inline");
      return "exited";
    }
    if (mode === "exit") return "none";
    const video = pictureInPictureCandidate();
    if (!video) return "no-video";
    video.removeAttribute("disablepictureinpicture");
    try {
      if (document.pictureInPictureEnabled && typeof video.requestPictureInPicture === "function") {
        await video.requestPictureInPicture();
        return "entered";
      }
    } catch (error) {
      // Fall back to WebKit's presentation modes, which don't require the standard API.
    }
    if (typeof video.webkitSupportsPresentationMode === "function" && video.webkitSupportsPresentationMode("picture-in-picture")) {
      video.webkitSetPresentationMode("picture-in-picture");
      return "entered";
    }
    return "unsupported";
  };

  window.__marcPageText = (limit) => {
    const root = document.querySelector("article, main, [role=main]") || document.body;
    const text = root ? root.innerText : "";
    return { title: document.title, url: location.href, text: text.slice(0, limit) };
  };

  window.__marcCountMatches = (query) => {
    if (!query || !document.body) return 0;
    const needle = query.toLocaleLowerCase();
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
      acceptNode(node) {
        const parent = node.parentElement;
        if (!parent || ["SCRIPT", "STYLE", "NOSCRIPT", "TEXTAREA"].includes(parent.tagName)) return NodeFilter.FILTER_REJECT;
        return parent.getClientRects().length ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
      },
    });
    let count = 0;
    while (walker.nextNode()) {
      const haystack = walker.currentNode.nodeValue.toLocaleLowerCase();
      let index = haystack.indexOf(needle);
      while (index !== -1) {
        count += 1;
        index = haystack.indexOf(needle, index + needle.length);
      }
    }
    return count;
  };
})();
