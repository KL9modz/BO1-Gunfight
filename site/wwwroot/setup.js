// Copy-to-clipboard for the one-line console command block.
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

  document.addEventListener("DOMContentLoaded", function () {
    var btns = document.querySelectorAll(".copy-btn[data-copy-target]");
    for (var i = 0; i < btns.length; i++) wire(btns[i]);
  });
})();
