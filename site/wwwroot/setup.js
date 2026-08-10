// Copy-to-clipboard for the one-line console command block, plus auto-expand
// for the collapsible <details class="fold"> sections when linked to directly.
// External file (not inline) so it works under the site's script-src 'self' CSP.
(function () {
  "use strict";

  function copyText(text) {
    // Preferred path: async Clipboard API (needs a secure context - gunfight.us is https).
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(text);
    }
    // Fallback for older / non-secure contexts: a temporary textarea + execCommand.
    return new Promise(function (resolve, reject) {
      try {
        var ta = document.createElement("textarea");
        ta.value = text;
        ta.setAttribute("readonly", "");
        ta.style.position = "absolute";
        ta.style.left = "-9999px";
        document.body.appendChild(ta);
        ta.select();
        var ok = document.execCommand("copy");
        document.body.removeChild(ta);
        ok ? resolve() : reject();
      } catch (e) {
        reject(e);
      }
    });
  }

  function wire(btn) {
    var targetId = btn.getAttribute("data-copy-target");
    var target = targetId && document.getElementById(targetId);
    if (!target) return;
    var codeEl = target.querySelector("code") || target;
    var original = btn.textContent;
    var resetTimer;

    btn.addEventListener("click", function () {
      copyText(codeEl.textContent).then(
        function () {
          btn.textContent = "Copied!";
          btn.classList.add("copied");
        },
        function () {
          btn.textContent = "Press Ctrl+C";
        }
      );
      clearTimeout(resetTimer);
      resetTimer = setTimeout(function () {
        btn.textContent = original;
        btn.classList.remove("copied");
      }, 1600);
    });
  }

  // Collapsible <details class="fold"> sections: closed by default, but a TOC
  // or in-page link pointing at one (or at content inside one) opens it so the
  // reader always lands on visible content.
  function openFoldFor(id) {
    if (!id) return;
    var target;
    try {
      target = document.getElementById(decodeURIComponent(id));
    } catch (e) {
      return;
    }
    if (!target) return;
    var fold = target.closest ? target.closest("details.fold") : null;
    if (fold && !fold.open) fold.open = true;
  }

  function openFoldForHash() {
    if (location.hash && location.hash.length > 1) {
      openFoldFor(location.hash.slice(1));
    }
  }

  document.addEventListener("DOMContentLoaded", function () {
    var btns = document.querySelectorAll(".copy-btn[data-copy-target]");
    for (var i = 0; i < btns.length; i++) wire(btns[i]);

    // Open before the browser scrolls: catch same-page anchor clicks directly
    // (a repeat click on the current hash fires no hashchange event).
    document.addEventListener("click", function (ev) {
      var a = ev.target && ev.target.closest ? ev.target.closest('a[href^="#"]') : null;
      if (a) openFoldFor(a.getAttribute("href").slice(1));
    });

    // Arriving with a hash in the URL (shared link / reload).
    openFoldForHash();
  });

  window.addEventListener("hashchange", openFoldForHash);
})();
