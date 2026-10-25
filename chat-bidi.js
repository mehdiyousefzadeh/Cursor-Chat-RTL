/*
 * Cursor chat direction.
 * Each paragraph follows its first letter:
 *   Persian/Arabic -> right aligned
 *   Latin          -> left aligned
 * Marker: __cursorChatBidiInstalled
 */
(function () {
  "use strict";

  function firstScript(text) {
    if (!text) return null;
    var i = 0;
    while (i < text.length) {
      var cp = text.codePointAt(i);
      if (isLetterRtl(cp)) return "rtl";
      if (isLetterLtr(cp)) return "ltr";
      i += cp > 0xffff ? 2 : 1;
    }
    return null;
  }

  function isLetterLtr(cp) {
    return (
      (cp >= 0x41 && cp <= 0x5a) ||
      (cp >= 0x61 && cp <= 0x7a) ||
      (cp >= 0xc0 && cp <= 0x24f) ||
      (cp >= 0x400 && cp <= 0x52f)
    );
  }

  function isLetterRtl(cp) {
    if (cp >= 0x05d0 && cp <= 0x05ea) return true;
    if (cp >= 0x0621 && cp <= 0x063a) return true;
    if (cp >= 0x0641 && cp <= 0x064a) return true;
    if (cp >= 0x0671 && cp <= 0x06d3) return true;
    if (cp === 0x06d5) return true;
    if (cp >= 0x06fa && cp <= 0x06ff) return true;
    if (cp >= 0x0750 && cp <= 0x077f) return true;
    if (cp >= 0x08a0 && cp <= 0x08ff) return true;
    if (cp >= 0xfb50 && cp <= 0xfdff) return true;
    if (cp >= 0xfe70 && cp <= 0xfefc) return true;
    return false;
  }

  if (typeof globalThis !== "undefined" && globalThis.__CURSOR_BIDI_TEST__) {
    globalThis.__CURSOR_BIDI_API__ = { firstScript: firstScript, isLetterRtl: isLetterRtl };
  }

  if (typeof document === "undefined") return;
  if (globalThis.__cursorChatBidiInstalled) return;
  globalThis.__cursorChatBidiInstalled = true;

  var ROOT_SELECTOR = [
    ".markdown-root",
    ".anysphere-markdown-container-root",
    ".markdown-section",
    ".composer-human-message",
    ".composer-rendered-message",
    ".aislash-editor-input",
    ".composer-input",
    ".ui-prompt-input",
    ".ProseMirror",
    "[class*='markdown-root']",
    "[class*='markdown-section']",
    "[class*='anysphere-markdown']",
    "[class*='composer-human-message']",
    "[class*='human-message']",
    "[class*='composer-rendered-message']",
    "[class*='aislash-editor']",
    "[class*='composer-input']",
    "[class*='ui-prompt-input']",
    "[class*='streamdown']",
    "[data-lexical-editor='true']"
  ].join(",");

  var BLOCK_TAGS = {
    P: 1, LI: 1, H1: 1, H2: 1, H3: 1, H4: 1, H5: 1, H6: 1,
    BLOCKQUOTE: 1, PRE: 1, TD: 1, TH: 1, DD: 1, DT: 1, FIGCAPTION: 1, TEXTAREA: 1
  };

  var NEST_TAGS = { LI: 1, BLOCKQUOTE: 1, TD: 1, TH: 1, DD: 1 };
  var DIVE_TAGS = { UL: 1, OL: 1, TABLE: 1, THEAD: 1, TBODY: 1, TR: 1, SECTION: 1, ARTICLE: 1, HEADER: 1 };

  var composing = false;
  var scheduled = false;
  var shadows = new Set();
  var observer = new MutationObserver(function (mutations) {
    for (var i = 0; i < mutations.length; i++) {
      var node = mutations[i].target;
      if (node && node.nodeType === 3) node = node.parentElement;
      if (!node || !node.closest) continue;
      if (node.closest(".monaco-editor, .monaco-diff-editor, .xterm")) continue;
      schedule();
      return;
    }
  });

  function classText(el) {
    if (!el || el.className == null) return "";
    if (typeof el.className === "string") return el.className;
    if (el.className.baseVal) return String(el.className.baseVal);
    return "";
  }

  function isEditor(el) {
    if (!el || el.nodeType !== 1) return false;
    if (el.getAttribute("contenteditable") === "true") return true;
    if (el.getAttribute("data-lexical-editor") === "true") return true;
    var c = classText(el);
    return c.indexOf("aislash-editor-input") >= 0 || c.indexOf("ProseMirror") >= 0;
  }

  function looksLikeChatClass(text) {
    return /markdown-root|markdown-section|anysphere-markdown|composer-human-message|human-message|composer-rendered-message|aislash-editor|composer-input|streamdown|ai-message|assistant-message|ui-prompt-input/i.test(text);
  }

  function ancestorLooksLikeChat(el) {
    var n = el;
    for (var i = 0; i < 10 && n; i++) {
      if (looksLikeChatClass(classText(n) + " " + (n.id || ""))) return true;
      if (/composer|aislash|aichat|prompt-input|agent-chat/i.test(classText(n))) return true;
      n = n.parentElement;
    }
    return false;
  }

  function isChatRoot(el) {
    if (!el || el.nodeType !== 1) return false;
    if (looksLikeChatClass(classText(el))) return true;
    if (el.matches && el.matches("[data-lexical-editor='true']") && ancestorLooksLikeChat(el)) return true;
    if (classText(el).indexOf("ProseMirror") >= 0 && ancestorLooksLikeChat(el)) return true;
    return false;
  }

  function isSkipped(el) {
    if (!el || el.nodeType !== 1) return true;
    if (el.closest(".monaco-editor, .monaco-diff-editor, .xterm")) return true;
    if (el.getAttribute("contenteditable") === "true") return false;
    if (el.closest("[contenteditable='true']")) return false;
    if (el.closest("button, [role='button'], [role='menu'], [role='menuitem'], [role='listbox'], [role='option'], [role='tab']")) return true;
    if (el.closest("[class*='toolbar'], [class*='tooltip']")) return true;
    return false;
  }

  function lineDirections(text) {
    var parts = String(text || "").split(/\n+/);
    var dirs = [];
    for (var i = 0; i < parts.length; i++) {
      var dir = firstScript(parts[i]);
      if (dir) dirs.push(dir);
    }
    return dirs;
  }

  function isMixedLines(el, text) {
    if (el.querySelector("p, div, ul, ol, li, pre, table, blockquote, h1, h2, h3, h4, h5, h6")) return false;
    var broken = !!el.querySelector("br") || String(text).indexOf("\n") >= 0;
    if (!broken) return false;
    var dirs = lineDirections(text);
    for (var i = 1; i < dirs.length; i++) {
      if (dirs[i] !== dirs[0]) return true;
    }
    return false;
  }

  function shouldDefer(el) {
    if (!composing) return false;
    var editor = el.getAttribute("contenteditable") === "true" ? el : el.closest("[contenteditable='true']");
    if (!editor) return false;
    return el.hasAttribute("data-cursor-bidi");
  }

  function applyExplicit(el, dir) {
    if (shouldDefer(el)) return;
    if (el.getAttribute("data-cursor-bidi") === dir && el.style.getPropertyValue("direction") === dir) return;
    el.setAttribute("data-cursor-bidi", dir);
    el.setAttribute("dir", dir);
    el.style.setProperty("direction", dir, "important");
    el.style.setProperty("text-align", dir === "rtl" ? "right" : "left", "important");
    el.style.setProperty("unicode-bidi", "isolate", "important");
  }

  function applyPlaintext(el) {
    if (shouldDefer(el)) return;
    if (el.getAttribute("data-cursor-bidi") === "auto" && el.style.getPropertyValue("unicode-bidi") === "plaintext") return;
    el.setAttribute("data-cursor-bidi", "auto");
    el.setAttribute("dir", "auto");
    el.style.setProperty("unicode-bidi", "plaintext", "important");
    el.style.setProperty("text-align", "start", "important");
    el.style.removeProperty("direction");
  }

  function clearDir(el) {
    if (!el.hasAttribute("data-cursor-bidi")) return;
    if (shouldDefer(el)) return;
    el.removeAttribute("data-cursor-bidi");
    el.removeAttribute("dir");
    el.style.removeProperty("direction");
    el.style.removeProperty("text-align");
    el.style.removeProperty("unicode-bidi");
    el.style.removeProperty("padding-left");
    el.style.removeProperty("padding-right");
    el.style.removeProperty("padding-inline-start");
    el.style.removeProperty("padding-inline-end");
  }

  function isCodeBlock(el) {
    if (!el || el.nodeType !== 1) return false;
    if (el.tagName === "PRE" || el.tagName === "CODE") return true;
    if (el.closest("pre, .monaco-editor, .markdown-code-outer-container, [data-streamdown='code-block']")) return true;
    var c = classText(el);
    return c.indexOf("ui-code-block") >= 0 || c.indexOf("cursor-code-block") >= 0;
  }

  function applyBlock(el) {
    if (isCodeBlock(el)) {
      applyExplicit(el, "ltr");
      return;
    }
    var text = el.innerText != null ? el.innerText : el.value || "";
    if (isMixedLines(el, text)) {
      applyPlaintext(el);
      return;
    }
    var dir = firstScript(text);
    if (dir) applyExplicit(el, dir);
    else clearDir(el);
  }

  function applyList(el, dir) {
    applyExplicit(el, dir);
    if (dir === "rtl") {
      el.style.setProperty("padding-left", "0", "important");
      el.style.setProperty("padding-right", "1.25em", "important");
    } else {
      el.style.setProperty("padding-left", "1.25em", "important");
      el.style.setProperty("padding-right", "0", "important");
    }
    el.style.setProperty("padding-inline-start", "1.25em", "important");
    el.style.setProperty("padding-inline-end", "0", "important");
  }

  function collect(root, out) {
    var kids = root.children;
    if (!kids) return;
    for (var i = 0; i < kids.length; i++) {
      var el = kids[i];
      if (isSkipped(el)) continue;
      if (el.shadowRoot) watchRoot(el.shadowRoot);
      if (BLOCK_TAGS[el.tagName]) {
        out.push(el);
        if (NEST_TAGS[el.tagName]) collect(el, out);
        continue;
      }
      if (DIVE_TAGS[el.tagName]) {
        collect(el, out);
        continue;
      }
      if (el.tagName === "DIV") {
        var nested = el.querySelector("p, div, ul, ol, li, pre, table, blockquote, h1, h2, h3, h4, h5, h6, textarea");
        if (nested) collect(el, out);
        else if (String(el.innerText || "").trim()) out.push(el);
        continue;
      }
      if (el.children && el.children.length) collect(el, out);
    }
  }

  function styleLists(root) {
    var lists = [];
    if (root.tagName === "UL" || root.tagName === "OL") lists.push(root);
    var found = root.querySelectorAll ? root.querySelectorAll("ul, ol") : [];
    for (var i = 0; i < found.length; i++) lists.push(found[i]);
    for (var j = 0; j < lists.length; j++) {
      var list = lists[j];
      if (isSkipped(list)) continue;
      var li = null;
      var children = list.children;
      for (var k = 0; k < children.length; k++) {
        if (children[k].tagName === "LI") {
          li = children[k];
          break;
        }
      }
      var dir = li && li.getAttribute("data-cursor-bidi");
      if (dir === "rtl" || dir === "ltr") applyList(list, dir);
      else clearDir(list);
    }
  }

  function bindEditor(el) {
    if (!el || el.__ccbBound) return;
    el.__ccbBound = true;
    el.addEventListener("input", schedule, true);
    el.addEventListener("compositionstart", function () { composing = true; }, true);
    el.addEventListener("compositionend", function () { composing = false; schedule(); }, true);
  }

  function processRoot(root) {
    if (!root || root.nodeType !== 1) return;
    if (isSkipped(root) && !isEditor(root)) return;
    var blocks = [];
    collect(root, blocks);
    for (var i = 0; i < blocks.length; i++) applyBlock(blocks[i]);

    if (isEditor(root)) {
      bindEditor(root);
      var dir = null;
      for (var b = 0; b < blocks.length; b++) {
        dir = firstScript(blocks[b].innerText != null ? blocks[b].innerText : "");
        if (dir) break;
      }
      if (!dir) dir = firstScript(root.innerText || root.value || "");
      if (dir) applyExplicit(root, dir);
      else clearDir(root);
    } else if (!blocks.length) {
      applyBlock(root);
    }
    styleLists(root);
  }

  function scanRoot(base) {
    if (!base || !base.querySelectorAll) return;
    var nodes;
    try { nodes = base.querySelectorAll(ROOT_SELECTOR); }
    catch (e) { return; }
    for (var i = 0; i < nodes.length; i++) {
      var el = nodes[i];
      if (!isChatRoot(el)) continue;
      if (classText(el).indexOf("ProseMirror") >= 0 && !ancestorLooksLikeChat(el)) continue;
      processRoot(el);
    }
    var edits;
    try { edits = base.querySelectorAll("[contenteditable='true'], textarea"); }
    catch (e) { return; }
    for (var j = 0; j < edits.length; j++) {
      var editor = edits[j];
      if (isSkipped(editor)) continue;
      if (!ancestorLooksLikeChat(editor) && !isChatRoot(editor)) continue;
      processRoot(editor);
    }
  }

  function watchRoot(root) {
    if (!root || shadows.has(root)) return;
    shadows.add(root);
    try { observer.observe(root, { subtree: true, childList: true, characterData: true }); }
    catch (e) {}
    var all;
    try { all = root.querySelectorAll ? root.querySelectorAll("*") : []; }
    catch (e) { all = []; }
    for (var i = 0; i < all.length; i++) {
      if (all[i].shadowRoot) watchRoot(all[i].shadowRoot);
    }
  }

  function scan() {
    if (document.hidden) return;
    scanRoot(document);
    shadows.forEach(function (root) { scanRoot(root); });
  }

  function schedule() {
    if (scheduled) return;
    scheduled = true;
    requestAnimationFrame(function () {
      scheduled = false;
      scan();
    });
  }

  try {
    if (Element.prototype.attachShadow && !Element.prototype.attachShadow.__ccb) {
      var origAttach = Element.prototype.attachShadow;
      var wrapped = function (init) {
        var shadow = origAttach.apply(this, arguments);
        watchRoot(shadow);
        schedule();
        return shadow;
      };
      wrapped.__ccb = true;
      Element.prototype.attachShadow = wrapped;
    }

    document.documentElement.setAttribute("data-cursor-chat-bidi", "1");
    document.addEventListener("compositionstart", function () { composing = true; }, true);
    document.addEventListener("compositionend", function () { composing = false; schedule(); }, true);
    watchRoot(document.documentElement);
    if (document.body) watchRoot(document.body);
    scan();
    setInterval(scan, 1000);
  } catch (e) {}
})();
