"use strict";

/* ===================================================================
 * viewer.js · 多格式文件查看器
 *
 * 宿主契约（WebView2 · FormFolderWorkspace）：
 *   run(BASE_URL)      —— 页面 NavigationCompleted 后调用，初始化查看器
 *   openFile(path)     —— 文件树选中节点后调用，path 为相对 BASE_URL 的路径
 *   toggleTheme()      —— Ribbon 主题按钮调用
 *
 * 说明：openFile 可能早于 run 被调用（TreeView.AfterSelect 先于
 * NavigationCompleted），故未初始化时先缓存 pendingPath，待 run 完成后补打开。
 * =================================================================== */

var openFile = null;
var toggleTheme = null;

/* 未初始化时的调用缓存 */
var __pendingPath = null;
var __ready = false;

openFile = function (path) {
  // run() 尚未执行：先记下来，初始化后自动打开
  __pendingPath = path;
};

function run(BASE_URL) {
  /* ===================== 常量 ===================== */
  var MAX_TABLE_ROWS = 2000; // 表格首批渲染行数
  var TREE_AUTO_EXPAND_DEPTH = 2; // 树形默认展开层级
  var PDF_WORKER_URL =
    "https://cdn.jsdelivr.net/npm/pdfjs-dist@3.11.174/build/pdf.worker.min.js";

  /* ===================== 工具函数（对齐 kb.js） ===================== */
  var $ = function (sel) {
    return document.querySelector(sel);
  };

  var el = function (tag, cls, html) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (html != null) n.innerHTML = html;
    return n;
  };

  var esc = function (s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return {
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        '"': "&quot;",
        "'": "&#39;",
      }[c];
    });
  };

  /* ===================== 主题（与现有页面共享 kb-theme） ===================== */
  function applyTheme(theme) {
    document.documentElement.setAttribute("data-theme", theme);
    var dark = theme === "dark";
    var icon = $("#themeIcon");
    var label = $("#themeLabel");
    if (icon) icon.textContent = dark ? "☀️" : "🌙";
    if (label) label.textContent = dark ? "亮色" : "暗色";
    try {
      localStorage.setItem("kb-theme", theme);
    } catch (e) {}
  }

  function initTheme() {
    var t = null;
    try {
      t = localStorage.getItem("kb-theme");
    } catch (e) {}
    if (!t)
      t =
        window.matchMedia &&
        window.matchMedia("(prefers-color-scheme: dark)").matches
          ? "dark"
          : "light";
    applyTheme(t);
  }

  toggleTheme = function () {
    var cur = document.documentElement.getAttribute("data-theme");
    applyTheme(cur === "dark" ? "light" : "dark");
  };

  var themeBtn = $("#themeBtn");
  if (themeBtn)
    themeBtn.addEventListener("click", function () {
      toggleTheme();
    });

  /* ===================== 路径工具 ===================== */
  function normalizePath(p) {
    return String(p == null ? "" : p)
      .replace(/\\/g, "/")
      .replace(/\/{2,}/g, "/") // 折叠重复分隔符（如 \\ 转换后的 //）
      .replace(/^\/+/, "");
  }

  function baseName(p) {
    var n = normalizePath(p);
    var i = n.lastIndexOf("/");
    return i >= 0 ? n.slice(i + 1) : n;
  }

  function getExt(p) {
    var n = baseName(p);
    var i = n.lastIndexOf(".");
    return i >= 0 ? n.slice(i + 1).toLowerCase() : "";
  }

  /* 逐段编码，兼容中文 / 空格路径；先解码再编码，避免重复编码 */
  function joinUrl(base, path) {
    var b = String(base || "").replace(/\/+$/, "");
    var segs = normalizePath(path)
      .split("/")
      .filter(function (s) {
        return s.length > 0;
      })
      .map(function (s) {
        try {
          return encodeURIComponent(decodeURIComponent(s));
        } catch (e) {
          return encodeURIComponent(s);
        }
      });
    return b + "/" + segs.join("/");
  }

  /* ===================== DOM 引用 ===================== */
  var stage = $("#stage");
  var toolbar = $("#toolbar");
  var fileNameEl = $("#fileName");
  var filePathEl = $("#filePath");
  var fileBadgeEl = $("#fileBadge");

  /* ===================== 运行时状态 ===================== */
  var activeToken = 0; // 竞态令牌
  var abortController = null; // 在途请求
  var disposers = []; // 当前视图的资源清理器

  function addDisposer(fn) {
    if (typeof fn === "function") disposers.push(fn);
  }

  /* 切换文件前释放上一个视图占用的资源（objectURL / pdf 文档 / 定时器等） */
  function disposeCurrent() {
    for (var i = 0; i < disposers.length; i++) {
      try {
        disposers[i]();
      } catch (e) {
        console.warn("释放查看器资源失败", e);
      }
    }
    disposers = [];
  }

  /* ===================== 网络层 ===================== */
  function fetchRes(url, signal) {
    return fetch(url, { cache: "no-store", signal: signal }).then(function (
      res,
    ) {
      if (!res.ok) throw new Error("HTTP " + res.status + " · " + url);
      return res;
    });
  }

  function fetchText(url, signal) {
    return fetchRes(url, signal).then(function (r) {
      return r.text();
    });
  }

  function fetchBlob(url, signal) {
    return fetchRes(url, signal).then(function (r) {
      return r.blob();
    });
  }

  function fetchArrayBuffer(url, signal) {
    return fetchRes(url, signal).then(function (r) {
      return r.arrayBuffer();
    });
  }

  /* ===================== 状态视图（复用 kb.css 类） ===================== */
  function showSkeleton() {
    setToolbar(null);
    stage.innerHTML =
      '<div class="stage-pad">' +
      '<div class="skeleton" style="width:42%"></div>' +
      '<div class="skeleton" style="width:88%"></div>' +
      '<div class="skeleton" style="width:76%"></div>' +
      '<div class="skeleton" style="width:83%"></div>' +
      "</div>";
  }

  function showError(msg, url) {
    setToolbar(null);
    // 错误信息中可能已包含地址（如 "HTTP 404 · <url>"），避免重复展示
    var extra =
      url && String(msg).indexOf(url) < 0
        ? "<br/>地址：<code>" + esc(url) + "</code>"
        : "";
    stage.innerHTML =
      '<div class="stage-pad"><div class="banner err"><b>加载失败：</b>' +
      esc(msg) +
      extra +
      "</div></div>";
  }

  function showEmpty() {
    setToolbar(null);
    stage.innerHTML =
      '<div class="empty"><div class="big">📂</div>' +
      "<div>请从左侧文件树中选择一个文件</div></div>";
  }

  /* ===================== 顶栏信息 ===================== */
  var KIND_LABEL = {
    table: "table",
    image: "image",
    pdf: "pdf",
    text: "text",
    tree: "data",
    web: "web",
    doc: "doc",
  };

  function setHeader(ctx, kind) {
    if (fileNameEl) fileNameEl.textContent = ctx.name || "文件查看器";
    if (filePathEl) filePathEl.textContent = ctx.path || "";
    if (fileBadgeEl) {
      if (ctx.ext) {
        fileBadgeEl.hidden = false;
        fileBadgeEl.textContent = ctx.ext;
        fileBadgeEl.className =
          "file-badge k-" + (KIND_LABEL[kind] ? kind : "text");
      } else {
        fileBadgeEl.hidden = true;
      }
    }
  }

  /* ===================== 工具栏 ===================== */
  function setToolbar(nodes) {
    toolbar.innerHTML = "";
    if (!nodes || !nodes.length) {
      toolbar.hidden = true;
      return;
    }
    toolbar.hidden = false;
    for (var i = 0; i < nodes.length; i++) toolbar.appendChild(nodes[i]);
  }

  function mkBtn(label, title, onClick, iconSvg) {
    var b = el("button", "tool-btn");
    b.type = "button";
    b.title = title || label;
    b.innerHTML =
      (iconSvg || "") + '<span class="lbl">' + esc(label) + "</span>";
    b.addEventListener("click", onClick);
    return b;
  }

  function mkSep() {
    return el("span", "tool-sep");
  }

  function mkInfo(text) {
    var s = el("span", "tool-info");
    s.textContent = text;
    return s;
  }

  /* 下载 / 新窗口打开（降级兜底） */
  function mkOpenExternal(url, name) {
    var a = el("a", "tool-btn");
    a.href = url;
    a.download = name || "";
    a.textContent = "下载文件";
    return a;
  }

  /* ===================== ① CSV / TSV ===================== */

  /**
   * RFC 4180 状态机解析：单次扫描，正确处理引号包裹字段、
   * 字段内分隔符 / 换行、"" 转义与 CRLF。
   */
  function parseDelimited(text, delim) {
    var rows = [];
    var row = [];
    var field = "";
    var inQuotes = false;
    var i = 0;
    var n = text.length;

    // 去除 UTF-8 BOM
    if (n > 0 && text.charCodeAt(0) === 0xfeff) i = 1;

    while (i < n) {
      var c = text.charAt(i);

      if (inQuotes) {
        if (c === '"') {
          if (i + 1 < n && text.charAt(i + 1) === '"') {
            field += '"';
            i += 2;
            continue;
          }
          inQuotes = false;
          i++;
          continue;
        }
        field += c;
        i++;
        continue;
      }

      if (c === '"') {
        inQuotes = true;
        i++;
        continue;
      }
      if (c === delim) {
        row.push(field);
        field = "";
        i++;
        continue;
      }
      if (c === "\r") {
        // CRLF 或单独 CR 均视为行结束
        row.push(field);
        field = "";
        rows.push(row);
        row = [];
        i += i + 1 < n && text.charAt(i + 1) === "\n" ? 2 : 1;
        continue;
      }
      if (c === "\n") {
        row.push(field);
        field = "";
        rows.push(row);
        row = [];
        i++;
        continue;
      }
      field += c;
      i++;
    }

    // 收尾：避免末尾空行产生一个空记录
    if (field.length > 0 || row.length > 0) {
      row.push(field);
      rows.push(row);
    }
    return rows;
  }

  function renderTable(text, ctx) {
    var delim = ctx.ext === "tsv" ? "\t" : ",";
    var rows = parseDelimited(text, delim);

    var wrap = el("div", "stage-pad");
    if (!rows.length) {
      wrap.innerHTML =
        '<div class="banner info">文件为空，没有可显示的表格数据。</div>';
      return { node: wrap, toolbar: [] };
    }

    var header = rows[0];
    var body = rows.slice(1);
    var colCount = header.length;
    for (var r = 0; r < body.length; r++)
      if (body[r].length > colCount) colCount = body[r].length;

    var box = el("div", "vtable-wrap");
    var table = el("table", "vtable");

    // 表头
    var thead = el("thead");
    var htr = el("tr");
    htr.appendChild(el("th", "rownum", "#"));
    for (var c = 0; c < colCount; c++) {
      var th = el("th");
      th.textContent = header[c] != null ? header[c] : "";
      htr.appendChild(th);
    }
    thead.appendChild(htr);
    table.appendChild(thead);

    // 表体：DocumentFragment 批量插入，避免逐行 reflow
    var tbody = el("tbody");
    var shown = 0;

    function appendRows(from, to) {
      var frag = document.createDocumentFragment();
      for (var k = from; k < to; k++) {
        var tr = el("tr");
        var tdn = el("td", "rownum");
        tdn.textContent = String(k + 1);
        tr.appendChild(tdn);
        for (var j = 0; j < colCount; j++) {
          var td = el("td");
          td.textContent = body[k][j] != null ? body[k][j] : "";
          tr.appendChild(td);
        }
        frag.appendChild(tr);
      }
      tbody.appendChild(frag);
      shown = to;
    }

    appendRows(0, Math.min(MAX_TABLE_ROWS, body.length));
    table.appendChild(tbody);
    box.appendChild(table);
    wrap.appendChild(box);

    var bar = [
      mkInfo(body.length + " 行 × " + colCount + " 列"),
    ];

    // 超量时提供「加载更多」
    if (body.length > shown) {
      var moreInfo = mkInfo("已显示 " + shown + " 行");
      var moreBtn = mkBtn("加载更多", "继续渲染后续行", function () {
        appendRows(shown, Math.min(shown + MAX_TABLE_ROWS, body.length));
        moreInfo.textContent = "已显示 " + shown + " 行";
        if (shown >= body.length) {
          moreBtn.disabled = true;
          moreBtn.style.opacity = "0.5";
          moreBtn.style.cursor = "default";
        }
      });
      bar.push(mkSep(), moreInfo, moreBtn);
    }

    return { node: wrap, toolbar: bar };
  }

  /* ===================== ② 纯文本 txt / log ===================== */
  function renderPlainText(text, _ctx) {
    var wrap = el("div", "stage-pad");
    var pre = el("div", "plain-text wrap");

    var lines = text.split(/\r\n|\r|\n/);
    var frag = document.createDocumentFragment();
    for (var i = 0; i < lines.length; i++) {
      var line = el("div", "pt-line");
      var ln = el("span", "pt-ln");
      ln.textContent = String(i + 1);
      var tx = el("span", "pt-tx");
      tx.textContent = lines[i];
      line.appendChild(ln);
      line.appendChild(tx);
      frag.appendChild(line);
    }
    pre.appendChild(frag);
    wrap.appendChild(pre);

    var wrapBtn = mkBtn("自动换行", "切换长行是否折行", function () {
      var on = pre.classList.toggle("wrap");
      wrapBtn.classList.toggle("active", on);
    });
    wrapBtn.classList.add("active");

    return {
      node: wrap,
      toolbar: [mkInfo(lines.length + " 行"), mkSep(), wrapBtn],
    };
  }

  /* ===================== ③ Markdown ===================== */
  function markdownToHtml(md) {
    if (md == null || md === "") return "";
    if (typeof marked !== "undefined" && marked.parse) {
      try {
        return marked.parse(md);
      } catch (e) {
        console.warn("marked 解析失败，降级为纯文本", e);
      }
    }
    // 降级：保留换行与基础转义
    return "<pre>" + esc(md) + "</pre>";
  }

  function renderMarkdown(text, _ctx) {
    var wrap = el("div", "stage-pad");
    var offline = typeof marked === "undefined" || !marked.parse;
    if (offline) {
      wrap.appendChild(
        el(
          "div",
          "banner info",
          "Markdown 渲染库（marked.js）不可用，当前以纯文本显示。",
        ),
      );
    }
    var view = el("div", "md-view markdown-body");
    view.innerHTML = markdownToHtml(text);
    wrap.appendChild(view);

    // 源码 / 渲染切换
    var srcMode = false;
    var toggleBtn = mkBtn("源码", "在渲染视图与源码之间切换", function () {
      srcMode = !srcMode;
      toggleBtn.classList.toggle("active", srcMode);
      if (srcMode) {
        view.classList.remove("markdown-body");
        view.innerHTML = "";
        var pre = el("pre");
        pre.style.whiteSpace = "pre-wrap";
        pre.style.fontFamily = "var(--font-code)";
        pre.style.fontSize = "13px";
        pre.textContent = text;
        view.appendChild(pre);
      } else {
        view.classList.add("markdown-body");
        view.innerHTML = markdownToHtml(text);
      }
    });

    return { node: wrap, toolbar: [toggleBtn] };
  }

  /* ===================== ④ JSON / JSONL 折叠树 ===================== */

  /* jsonl：逐行解析后合并为数组；容忍空行 */
  function parseJsonl(text) {
    var lines = text.split(/\r\n|\r|\n/);
    var arr = [];
    for (var i = 0; i < lines.length; i++) {
      var s = lines[i].trim();
      if (!s) continue;
      try {
        arr.push(JSON.parse(s));
      } catch (e) {
        throw new Error("第 " + (i + 1) + " 行 JSON 解析失败：" + e.message);
      }
    }
    return arr;
  }

  function jsonScalarSpan(v) {
    var s;
    if (v === null) return el("span", "tk-null", "null");
    switch (typeof v) {
      case "string":
        s = el("span", "tk-str");
        s.textContent = JSON.stringify(v);
        return s;
      case "number":
        s = el("span", "tk-num");
        s.textContent = String(v);
        return s;
      case "boolean":
        s = el("span", "tk-bool");
        s.textContent = String(v);
        return s;
      default:
        s = el("span");
        s.textContent = String(v);
        return s;
    }
  }

  /**
   * 惰性展开：折叠状态的子树不建 DOM，展开时才构建并缓存。
   * 将首屏复杂度从 O(全部节点) 降为 O(可见节点)。
   */
  function buildJsonNode(key, value, depth) {
    var isArr = Array.isArray(value);
    var isObj = value !== null && typeof value === "object";

    var node = el("div", "jt-node");
    var row = el("div", "jt-row");

    if (!isObj) {
      row.appendChild(el("span", "jt-spacer"));
      if (key !== null) {
        var k = el("span", "tk-key");
        k.textContent = typeof key === "number" ? key : JSON.stringify(key);
        row.appendChild(k);
        row.appendChild(el("span", "tk-punct", ":"));
      }
      row.appendChild(jsonScalarSpan(value));
      node.appendChild(row);
      return node;
    }

    var keys = isArr ? null : Object.keys(value);
    var count = isArr ? value.length : keys.length;
    var open = isArr ? "[" : "{";
    var close = isArr ? "]" : "}";

    var toggle = el("span", "jt-toggle");
    row.appendChild(toggle);

    if (key !== null) {
      var kk = el("span", "tk-key");
      kk.textContent = typeof key === "number" ? key : JSON.stringify(key);
      row.appendChild(kk);
      row.appendChild(el("span", "tk-punct", ":"));
    }
    row.appendChild(el("span", "tk-punct", open));
    row.appendChild(
      el(
        "span",
        "jt-summary",
        "… " + count + (isArr ? " items" : " keys") + " " + close,
      ),
    );

    node.appendChild(row);

    var children = el("div", "jt-children");
    node.appendChild(children);
    var tail = el("div", "jt-row");
    tail.appendChild(el("span", "jt-spacer"));
    tail.appendChild(el("span", "tk-punct", close));
    node.appendChild(tail);

    var built = false;
    function build() {
      if (built) return;
      built = true;
      var frag = document.createDocumentFragment();
      if (isArr) {
        for (var i = 0; i < value.length; i++)
          frag.appendChild(buildJsonNode(i, value[i], depth + 1));
      } else {
        for (var j = 0; j < keys.length; j++)
          frag.appendChild(buildJsonNode(keys[j], value[keys[j]], depth + 1));
      }
      children.appendChild(frag);
    }

    var collapsed = depth >= TREE_AUTO_EXPAND_DEPTH || count === 0;
    if (collapsed) {
      node.classList.add("collapsed");
      tail.style.display = "none";
    } else {
      build();
    }

    node.__setCollapsed = function (c) {
      if (c) {
        node.classList.add("collapsed");
        tail.style.display = "none";
      } else {
        build();
        node.classList.remove("collapsed");
        tail.style.display = "";
      }
    };

    toggle.addEventListener("click", function (ev) {
      ev.stopPropagation();
      node.__setCollapsed(!node.classList.contains("collapsed"));
    });

    return node;
  }

  function walkSetCollapsed(root, collapsed) {
    if (collapsed) {
      var nodes = root.querySelectorAll(".jt-node");
      for (var i = 0; i < nodes.length; i++) {
        if (nodes[i].__setCollapsed) nodes[i].__setCollapsed(true);
      }
      return;
    }

    // 展开：惰性构建会不断产生新的子节点，需迭代至不再出现折叠节点。
    // 每轮只处理仍处于折叠态的节点，故总处理次数与节点数同阶。
    var guard = 0;
    while (guard++ < 1000) {
      var pending = root.querySelectorAll(".jt-node.collapsed");
      if (!pending.length) break;
      for (var j = 0; j < pending.length; j++) {
        if (pending[j].__setCollapsed) pending[j].__setCollapsed(false);
      }
    }
  }

  function renderJson(text, ctx) {
    var wrap = el("div", "stage-pad");
    var data;
    try {
      data = ctx.ext === "jsonl" ? parseJsonl(text) : JSON.parse(text);
    } catch (e) {
      console.warn("JSON 解析失败，降级为纯文本", e);
      wrap.appendChild(
        el("div", "banner err", "<b>JSON 解析失败：</b>" + esc(e.message)),
      );
      var fb = renderPlainText(text, ctx);
      wrap.appendChild(fb.node.firstChild);
      return { node: wrap, toolbar: fb.toolbar };
    }

    var tree = el("div", "code-tree");
    tree.appendChild(buildJsonNode(null, data, 0));
    if (ctx.ext === "jsonl") {
      wrap.appendChild(
        el(
          "div",
          "banner info",
          "JSON Lines 文档已合并为 JSON 数组显示，共 " +
            data.length +
            " 条记录。",
        ),
      );
    }
    wrap.appendChild(tree);

    var bar = [
      mkBtn("全部展开", "展开所有节点", function () {
        walkSetCollapsed(tree, false);
      }),
      mkBtn("全部折叠", "折叠所有节点", function () {
        walkSetCollapsed(tree, true);
      }),
      mkSep(),
      mkBtn("复制", "复制 JSON 文本", function () {
        copyText(JSON.stringify(data, null, 2));
      }),
    ];

    return { node: wrap, toolbar: bar };
  }

  function copyText(s) {
    try {
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(s);
        return;
      }
    } catch (e) {}
    try {
      var ta = document.createElement("textarea");
      ta.value = s;
      ta.style.position = "fixed";
      ta.style.opacity = "0";
      document.body.appendChild(ta);
      ta.select();
      // 已废弃 API，仅作为 navigator.clipboard 不可用（非安全上下文）时的兜底
      document.execCommand("copy");
      document.body.removeChild(ta);
    } catch (e) {
      console.warn("复制到剪贴板失败", e);
    }
  }

  /* ===================== ⑤ XML 折叠树 ===================== */
  function buildXmlNode(elem, depth) {
    var node = el("div", "jt-node");
    var row = el("div", "jt-row");

    // 文本 / 注释 / CDATA
    if (elem.nodeType === 3) {
      var t = elem.nodeValue;
      if (!t || !t.trim()) return null;
      row.appendChild(el("span", "jt-spacer"));
      var tx = el("span");
      tx.textContent = t.trim();
      row.appendChild(tx);
      node.appendChild(row);
      return node;
    }
    if (elem.nodeType === 8) {
      row.appendChild(el("span", "jt-spacer"));
      var cm = el("span", "tk-comment");
      cm.textContent = "<!--" + elem.nodeValue + "-->";
      row.appendChild(cm);
      node.appendChild(row);
      return node;
    }
    if (elem.nodeType === 4) {
      row.appendChild(el("span", "jt-spacer"));
      var cd = el("span", "tk-str");
      cd.textContent = "<![CDATA[" + elem.nodeValue + "]]>";
      row.appendChild(cd);
      node.appendChild(row);
      return node;
    }
    if (elem.nodeType !== 1) return null;

    // 收集有效子节点
    var kids = [];
    for (var i = 0; i < elem.childNodes.length; i++) {
      var cn = elem.childNodes[i];
      if (cn.nodeType === 3 && (!cn.nodeValue || !cn.nodeValue.trim()))
        continue;
      kids.push(cn);
    }

    // 属性串
    function attrsFrag(target) {
      for (var a = 0; a < elem.attributes.length; a++) {
        var at = elem.attributes[a];
        target.appendChild(document.createTextNode(" "));
        var an = el("span", "tk-attr");
        an.textContent = at.name;
        target.appendChild(an);
        target.appendChild(el("span", "tk-punct", "="));
        var av = el("span", "tk-str");
        av.textContent = '"' + at.value + '"';
        target.appendChild(av);
      }
    }

    // 叶子元素：单行显示 <tag attr="v">text</tag>
    var onlyText =
      kids.length === 0 ||
      (kids.length === 1 && kids[0].nodeType === 3);

    if (onlyText) {
      row.appendChild(el("span", "jt-spacer"));
      row.appendChild(el("span", "tk-punct", "<"));
      var tn0 = el("span", "tk-tag");
      tn0.textContent = elem.nodeName;
      row.appendChild(tn0);
      attrsFrag(row);
      if (kids.length === 0) {
        row.appendChild(el("span", "tk-punct", " />"));
      } else {
        row.appendChild(el("span", "tk-punct", ">"));
        var vt = el("span");
        vt.textContent = kids[0].nodeValue.trim();
        row.appendChild(vt);
        row.appendChild(el("span", "tk-punct", "</"));
        var tn1 = el("span", "tk-tag");
        tn1.textContent = elem.nodeName;
        row.appendChild(tn1);
        row.appendChild(el("span", "tk-punct", ">"));
      }
      node.appendChild(row);
      return node;
    }

    // 容器元素：可折叠
    var toggle = el("span", "jt-toggle");
    row.appendChild(toggle);
    row.appendChild(el("span", "tk-punct", "<"));
    var tname = el("span", "tk-tag");
    tname.textContent = elem.nodeName;
    row.appendChild(tname);
    attrsFrag(row);
    row.appendChild(el("span", "tk-punct", ">"));
    row.appendChild(
      el("span", "jt-summary", "… " + kids.length + " nodes </" + elem.nodeName + ">"),
    );
    node.appendChild(row);

    var children = el("div", "jt-children");
    node.appendChild(children);

    var tail = el("div", "jt-row");
    tail.appendChild(el("span", "jt-spacer"));
    tail.appendChild(el("span", "tk-punct", "</"));
    var tn2 = el("span", "tk-tag");
    tn2.textContent = elem.nodeName;
    tail.appendChild(tn2);
    tail.appendChild(el("span", "tk-punct", ">"));
    node.appendChild(tail);

    var built = false;
    function build() {
      if (built) return;
      built = true;
      var frag = document.createDocumentFragment();
      for (var k = 0; k < kids.length; k++) {
        var sub = buildXmlNode(kids[k], depth + 1);
        if (sub) frag.appendChild(sub);
      }
      children.appendChild(frag);
    }

    var collapsed = depth >= TREE_AUTO_EXPAND_DEPTH;
    if (collapsed) {
      node.classList.add("collapsed");
      tail.style.display = "none";
    } else {
      build();
    }

    node.__setCollapsed = function (c) {
      if (c) {
        node.classList.add("collapsed");
        tail.style.display = "none";
      } else {
        build();
        node.classList.remove("collapsed");
        tail.style.display = "";
      }
    };

    toggle.addEventListener("click", function (ev) {
      ev.stopPropagation();
      node.__setCollapsed(!node.classList.contains("collapsed"));
    });

    return node;
  }

  function renderXml(text, ctx) {
    var wrap = el("div", "stage-pad");
    var doc = null;
    var parseErr = null;

    try {
      doc = new DOMParser().parseFromString(text, "application/xml");
      var perr = doc.querySelector("parsererror");
      if (perr) parseErr = perr.textContent || "XML 格式错误";
    } catch (e) {
      parseErr = e.message;
    }

    if (parseErr) {
      console.warn("XML 解析失败，降级为纯文本", parseErr);
      wrap.appendChild(
        el("div", "banner err", "<b>XML 解析失败：</b>" + esc(parseErr)),
      );
      var fb = renderPlainText(text, ctx);
      wrap.appendChild(fb.node.firstChild);
      return { node: wrap, toolbar: fb.toolbar };
    }

    var tree = el("div", "code-tree");
    var rootEl = doc.documentElement;
    var built = buildXmlNode(rootEl, 0);
    if (built) tree.appendChild(built);
    wrap.appendChild(tree);

    var bar = [
      mkBtn("全部展开", "展开所有标签", function () {
        walkSetCollapsed(tree, false);
      }),
      mkBtn("全部折叠", "折叠所有标签", function () {
        walkSetCollapsed(tree, true);
      }),
      mkSep(),
      mkBtn("复制", "复制 XML 文本", function () {
        copyText(text);
      }),
    ];

    return { node: wrap, toolbar: bar };
  }

  /* ===================== ⑥ 图像 / SVG ===================== */
  var ICON = {
    zoomIn:
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><line x1="21" y1="21" x2="16.65" y2="16.65"/><line x1="11" y1="8" x2="11" y2="14"/><line x1="8" y1="11" x2="14" y2="11"/></svg>',
    zoomOut:
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><line x1="21" y1="21" x2="16.65" y2="16.65"/><line x1="8" y1="11" x2="14" y2="11"/></svg>',
    rotL:
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="1 4 1 10 7 10"/><path d="M3.51 15a9 9 0 1 0 2.13-9.36L1 10"/></svg>',
    rotR:
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="23 4 23 10 17 10"/><path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"/></svg>',
    flipH:
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v18"/><path d="M8 7L3 12l5 5z"/><path d="M16 7l5 5-5 5z"/></svg>',
    flipV:
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12h18"/><path d="M7 8L12 3l5 5z"/><path d="M7 16l5 5 5-5z"/></svg>',
    fit:
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 3h6v6"/><path d="M9 21H3v-6"/><path d="M21 3l-7 7"/><path d="M3 21l7-7"/></svg>',
    reset:
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12a9 9 0 1 0 9-9 9 9 0 0 0-6.36 2.64L3 8"/><polyline points="3 3 3 8 8 8"/></svg>',
  };

  function renderImage(url, ctx) {
    var host = el("div", "image-stage");
    var img = el("img");
    img.alt = ctx.name;
    // 加载失败兜底（tiff 等浏览器不支持的格式）
    img.onerror = function () {
      host.innerHTML = "";
      var box = el("div", "stage-pad");
      box.innerHTML =
        '<div class="banner info"><b>无法在浏览器中显示该图像。</b><br/>' +
        "格式 <code>" +
        esc(ctx.ext) +
        "</code> 可能不被当前浏览器内核支持（如 TIFF）。" +
        "可下载后使用本地图像工具查看。</div>";
      var row = el("div", "dl-row");
      row.appendChild(mkOpenExternal(url, ctx.name));
      box.appendChild(row);
      host.appendChild(box);
      setToolbar(null);
    };
    img.src = url;
    host.appendChild(img);

    // 变换状态：单一状态对象 → CSS transform 合成
    var st = { scale: 1, rotate: 0, flipX: false, flipY: false, tx: 0, ty: 0 };

    function apply() {
      var sx = st.scale * (st.flipX ? -1 : 1);
      var sy = st.scale * (st.flipY ? -1 : 1);
      img.style.transform =
        "translate(" +
        st.tx +
        "px," +
        st.ty +
        "px) rotate(" +
        st.rotate +
        "deg) scale(" +
        sx +
        "," +
        sy +
        ")";
      if (zoomInfo)
        zoomInfo.textContent = Math.round(st.scale * 100) + "%";
    }

    function zoom(f) {
      st.scale = Math.min(16, Math.max(0.05, st.scale * f));
      apply();
    }

    function fit() {
      var cw = host.clientWidth - 40;
      var ch = host.clientHeight - 40;
      var iw = img.naturalWidth || img.clientWidth;
      var ih = img.naturalHeight || img.clientHeight;
      if (!iw || !ih || cw <= 0 || ch <= 0) return;
      // 旋转 90/270 度时宽高互换
      var rot = ((st.rotate % 360) + 360) % 360;
      if (rot === 90 || rot === 270) {
        var t = iw;
        iw = ih;
        ih = t;
      }
      st.scale = Math.min(cw / iw, ch / ih, 1);
      st.tx = 0;
      st.ty = 0;
      apply();
    }

    function reset() {
      st = { scale: 1, rotate: 0, flipX: false, flipY: false, tx: 0, ty: 0 };
      apply();
    }

    img.addEventListener("load", function () {
      if (sizeInfo)
        sizeInfo.textContent =
          img.naturalWidth + " × " + img.naturalHeight + " px";
      fit();
    });

    // 滚轮缩放
    host.addEventListener(
      "wheel",
      function (e) {
        e.preventDefault();
        zoom(e.deltaY < 0 ? 1.12 : 1 / 1.12);
      },
      { passive: false },
    );

    // 拖拽平移
    var dragging = false;
    var sx0 = 0;
    var sy0 = 0;
    host.addEventListener("mousedown", function (e) {
      dragging = true;
      sx0 = e.clientX - st.tx;
      sy0 = e.clientY - st.ty;
      host.classList.add("dragging");
      e.preventDefault();
    });
    var onMove = function (e) {
      if (!dragging) return;
      st.tx = e.clientX - sx0;
      st.ty = e.clientY - sy0;
      apply();
    };
    var onUp = function () {
      dragging = false;
      host.classList.remove("dragging");
    };
    window.addEventListener("mousemove", onMove);
    window.addEventListener("mouseup", onUp);
    addDisposer(function () {
      window.removeEventListener("mousemove", onMove);
      window.removeEventListener("mouseup", onUp);
    });

    var zoomInfo = mkInfo("100%");
    var sizeInfo = mkInfo("");

    var bar = [
      mkBtn("放大", "放大（滚轮上）", function () {
        zoom(1.25);
      }, ICON.zoomIn),
      mkBtn("缩小", "缩小（滚轮下）", function () {
        zoom(1 / 1.25);
      }, ICON.zoomOut),
      zoomInfo,
      mkSep(),
      mkBtn("左旋", "逆时针旋转 90°", function () {
        st.rotate -= 90;
        apply();
      }, ICON.rotL),
      mkBtn("右旋", "顺时针旋转 90°", function () {
        st.rotate += 90;
        apply();
      }, ICON.rotR),
      mkSep(),
      mkBtn("水平翻转", "左右镜像", function () {
        st.flipX = !st.flipX;
        apply();
      }, ICON.flipH),
      mkBtn("垂直翻转", "上下镜像", function () {
        st.flipY = !st.flipY;
        apply();
      }, ICON.flipV),
      mkSep(),
      mkBtn("适应窗口", "缩放至完整显示", fit, ICON.fit),
      mkBtn("1:1", "原始尺寸", function () {
        st.scale = 1;
        st.tx = 0;
        st.ty = 0;
        apply();
      }),
      mkBtn("重置", "恢复初始状态", reset, ICON.reset),
      mkSep(),
      sizeInfo,
    ];

    apply();
    return { node: host, toolbar: bar, fullBleed: true };
  }

  /* ===================== ⑦ PDF ===================== */
  function renderPdf(buf, ctx) {
    var host = el("div", "pdf-stage");

    var pdfjs = typeof pdfjsLib !== "undefined" ? pdfjsLib : null;
    if (!pdfjs || window.__pdfjsFailed) {
      // 降级：交给浏览器内置 PDF 查看器
      console.warn("pdf.js 不可用，降级为浏览器内置查看器");
      var wrap = el("div");
      wrap.style.cssText = "position:absolute;inset:0;display:flex;flex-direction:column";
      var tip = el(
        "div",
        "banner info",
        "PDF 渲染库（pdf.js）不可用，已切换为浏览器内置查看器。",
      );
      tip.style.margin = "12px 16px 0";
      var frame = el("iframe", "html-frame");
      frame.src = ctx.url;
      frame.style.flex = "1";
      wrap.appendChild(tip);
      wrap.appendChild(frame);
      return { node: wrap, toolbar: [mkOpenExternal(ctx.url, ctx.name)], fullBleed: true };
    }

    try {
      pdfjs.GlobalWorkerOptions.workerSrc = PDF_WORKER_URL;
    } catch (e) {
      console.warn("配置 pdf.js worker 失败", e);
    }

    var scale = 1.2;
    var pdfDoc = null;
    var pageInput = el("input", "tool-input");
    pageInput.type = "text";
    pageInput.value = "1";
    var pageInfo = mkInfo("/ -");
    var zoomInfo = mkInfo("120%");

    // 渲染代次：缩放会重新触发 renderAll，需让上一轮在途渲染自行终止，
    // 否则旧任务会把页面重复追加到已清空的容器中，导致页序错乱。
    var renderGen = 0;

    function renderPage(num, gen) {
      return pdfDoc.getPage(num).then(function (page) {
        if (gen !== renderGen) return; // 本轮已作废
        var dpr = window.devicePixelRatio || 1;
        var viewport = page.getViewport({ scale: scale });
        var canvas = el("canvas");
        var cctx = canvas.getContext("2d");
        canvas.width = Math.floor(viewport.width * dpr);
        canvas.height = Math.floor(viewport.height * dpr);
        canvas.style.width = Math.floor(viewport.width) + "px";
        canvas.style.height = Math.floor(viewport.height) + "px";

        var pageBox = el("div", "pdf-page");
        pageBox.dataset.page = String(num);
        pageBox.appendChild(canvas);
        host.appendChild(pageBox);

        var task = page.render({
          canvasContext: cctx,
          viewport: viewport,
          transform: dpr !== 1 ? [dpr, 0, 0, dpr, 0, 0] : null,
        });
        return task.promise.catch(function (e) {
          if (e && e.name === "RenderingCancelledException") return;
          throw e;
        });
      });
    }

    function renderAll() {
      var gen = ++renderGen;
      host.innerHTML = "";
      var chain = Promise.resolve();
      for (var i = 1; i <= pdfDoc.numPages; i++) {
        (function (n) {
          chain = chain.then(function () {
            if (gen !== renderGen) return; // 已被新一轮取代，停止后续页
            return renderPage(n, gen);
          });
        })(i);
      }
      return chain;
    }

    function gotoPage(n) {
      var box = host.querySelector('.pdf-page[data-page="' + n + '"]');
      if (box) box.scrollIntoView({ behavior: "smooth", block: "start" });
    }

    var current = 1;

    // pdf.js 会转移（detach）传入的 ArrayBuffer，这里传副本，
    // 避免原始 buffer 失效后无法用于降级下载等后续用途。
    pdfjs
      .getDocument({ data: new Uint8Array(buf) })
      .promise.then(function (doc) {
        pdfDoc = doc;
        addDisposer(function () {
          try {
            doc.destroy();
          } catch (e) {}
        });
        pageInfo.textContent = "/ " + doc.numPages;
        return renderAll();
      })
      .catch(function (err) {
        console.error("PDF 渲染失败", err);
        host.innerHTML = "";
        var box = el("div", "stage-pad");
        box.innerHTML =
          '<div class="banner err"><b>PDF 渲染失败：</b>' +
          esc(err.message) +
          "</div>";
        var row = el("div", "dl-row");
        row.appendChild(mkOpenExternal(ctx.url, ctx.name));
        box.appendChild(row);
        host.appendChild(box);
      });

    function reflow() {
      if (!pdfDoc) return;
      zoomInfo.textContent = Math.round(scale * 100) + "%";
      renderAll();
    }

    pageInput.addEventListener("change", function () {
      var n = parseInt(pageInput.value, 10);
      if (!isNaN(n) && pdfDoc && n >= 1 && n <= pdfDoc.numPages) {
        current = n;
        gotoPage(n);
      } else {
        pageInput.value = String(current);
      }
    });

    var bar = [
      mkBtn("上一页", "上一页", function () {
        if (!pdfDoc) return;
        current = Math.max(1, current - 1);
        pageInput.value = String(current);
        gotoPage(current);
      }),
      pageInput,
      pageInfo,
      mkBtn("下一页", "下一页", function () {
        if (!pdfDoc) return;
        current = Math.min(pdfDoc.numPages, current + 1);
        pageInput.value = String(current);
        gotoPage(current);
      }),
      mkSep(),
      mkBtn("放大", "放大", function () {
        scale = Math.min(4, scale * 1.25);
        reflow();
      }, ICON.zoomIn),
      mkBtn("缩小", "缩小", function () {
        scale = Math.max(0.25, scale / 1.25);
        reflow();
      }, ICON.zoomOut),
      zoomInfo,
    ];

    return { node: host, toolbar: bar, fullBleed: true };
  }

  /* ===================== ⑧ HTML（沙箱） ===================== */
  function renderHtmlDoc(text, ctx) {
    var host = el("div");
    host.style.cssText = "position:absolute;inset:0;display:flex;flex-direction:column";

    var frame = el("iframe", "html-frame");
    // 不授予 allow-same-origin / allow-scripts：
    // 科研工作站可能打开来源不明的产物文件，需阻断脚本执行与同源访问
    frame.setAttribute("sandbox", "");
    frame.srcdoc = text;
    frame.style.flex = "1";
    host.appendChild(frame);

    var srcMode = false;
    var srcView = null;

    var toggleBtn = mkBtn("源码", "在渲染视图与源码之间切换", function () {
      srcMode = !srcMode;
      toggleBtn.classList.toggle("active", srcMode);
      if (srcMode) {
        frame.style.display = "none";
        if (!srcView) {
          srcView = el("div", "stage-pad");
          srcView.style.cssText =
            "flex:1;overflow:auto;position:relative";
          var r = renderPlainText(text, ctx);
          srcView.appendChild(r.node.firstChild);
          host.appendChild(srcView);
        }
        srcView.style.display = "";
      } else {
        frame.style.display = "";
        if (srcView) srcView.style.display = "none";
      }
    });

    return {
      node: host,
      toolbar: [
        toggleBtn,
        mkSep(),
        mkInfo("已在沙箱中隔离渲染（禁用脚本）"),
      ],
      fullBleed: true,
    };
  }

  /* ===================== ⑨ 不支持的格式 ===================== */
  function renderUnsupported(_data, ctx) {
    var wrap = el("div", "stage-pad");
    wrap.innerHTML =
      '<div class="banner info"><b>暂不支持该文件格式：</b><code>' +
      esc(ctx.ext || "（无扩展名）") +
      "</code><br/>" +
      "当前支持 csv/tsv、bmp/jpg/jpeg/png/gif/tiff、svg、pdf、txt/log、" +
      "json/jsonl、xml、html、md。</div>";
    var row = el("div", "dl-row");
    row.appendChild(mkOpenExternal(ctx.url, ctx.name));
    wrap.appendChild(row);
    return { node: wrap, toolbar: [] };
  }

  /* ===================== 渲染器注册表 =====================
   * 新增格式只需在此注册一项，调度逻辑无需改动（开闭原则）。
   *   load : "text" | "blob" | "arrayBuffer" | "url"
   *   kind : 徽标与配色类别
   *   render(data, ctx) -> { node, toolbar?, fullBleed? }
   * ======================================================= */
  var RENDERERS = {};

  function register(exts, spec) {
    for (var i = 0; i < exts.length; i++) RENDERERS[exts[i]] = spec;
  }

  register(["csv", "tsv"], {
    load: "text",
    kind: "table",
    render: renderTable,
  });

  register(["txt", "log"], {
    load: "text",
    kind: "text",
    render: renderPlainText,
  });

  register(["md"], { load: "text", kind: "doc", render: renderMarkdown });

  register(["json", "jsonl"], {
    load: "text",
    kind: "tree",
    render: renderJson,
  });

  register(["xml"], { load: "text", kind: "tree", render: renderXml });

  register(["html", "htm"], {
    load: "text",
    kind: "web",
    render: renderHtmlDoc,
  });

  register(["bmp", "jpg", "jpeg", "png", "gif", "tiff", "tif", "webp"], {
    load: "url",
    kind: "image",
    render: renderImage,
  });

  // SVG 走 blob URL 挂 <img>，既复用图像工具栏，又天然禁用内嵌脚本
  register(["svg"], {
    load: "url",
    kind: "image",
    render: renderImage,
  });

  register(["pdf"], {
    load: "arrayBuffer",
    kind: "pdf",
    render: renderPdf,
  });

  /* ===================== 调度器 ===================== */
  function doOpenFile(rawPath) {
    if (rawPath == null || rawPath === "") {
      showEmpty();
      return;
    }

    var path = normalizePath(rawPath);
    var ext = getExt(path);
    var name = baseName(path);
    var url = joinUrl(BASE_URL, path);

    // 中止在途请求 + 递增令牌，避免快速切换时旧内容覆盖新内容
    if (abortController) {
      try {
        abortController.abort();
      } catch (e) {}
    }
    abortController =
      typeof AbortController !== "undefined" ? new AbortController() : null;
    var signal = abortController ? abortController.signal : undefined;
    var token = ++activeToken;

    disposeCurrent();

    var spec = RENDERERS[ext] || {
      load: "none",
      kind: "text",
      render: renderUnsupported,
    };

    var ctx = {
      path: path,
      ext: ext,
      name: name,
      url: url,
      signal: signal,
    };

    setHeader(ctx, spec.kind);
    stage.scrollTop = 0;

    // url / none 模式无需预取，直接渲染
    if (spec.load === "url" || spec.load === "none") {
      var payload = spec.load === "url" ? url : null;
      try {
        mount(spec.render(payload, ctx), token);
      } catch (err) {
        console.error("渲染失败", path, err);
        showError(err.message, url);
      }
      return;
    }

    showSkeleton();

    var loader =
      spec.load === "arrayBuffer"
        ? fetchArrayBuffer
        : spec.load === "blob"
          ? fetchBlob
          : fetchText;

    loader(url, signal)
      .then(function (data) {
        if (token !== activeToken) return; // 已切换，丢弃过期结果
        mount(spec.render(data, ctx), token);
      })
      .catch(function (err) {
        if (err && err.name === "AbortError") return; // 主动中止，静默
        if (token !== activeToken) return; // 过期请求的错误不覆盖当前视图
        console.error("加载文件失败", path, err);
        showError(err.message, url);
      });
  }

  /* 挂载渲染结果 */
  function mount(result, token) {
    if (!result) return;
    if (token !== activeToken) return; // 渲染前再次校验
    setToolbar(result.toolbar);
    stage.innerHTML = "";
    // fullBleed：图像 / PDF / 网页等需要铺满且自管理滚动
    stage.style.overflow = result.fullBleed ? "hidden" : "auto";
    stage.appendChild(result.node);
  }

  /* ===================== 暴露宿主接口 ===================== */
  openFile = function (path) {
    doOpenFile(path);
  };

  /* ===================== 启动 ===================== */
  function init() {
    initTheme();
    __ready = true;
    // 补打开 run() 之前宿主已请求的文件
    if (__pendingPath != null) {
      var p = __pendingPath;
      __pendingPath = null;
      doOpenFile(p);
    }
  }

  init();
}

/* ===================== 宿主调用示例 =====================
 * VB (FormFolderWorkspace.vb)：
 *
 *   ' NavigationCompleted 后初始化
 *   Await WebView21.CoreWebView2.ExecuteScriptAsync(
 *       $"run('http://127.0.0.1:{port}/');")
 *
 *   ' TreeView1_AfterSelect 中按扩展名打开文件（相对路径）
 *   Dim rel As String = fsNode.FullName.Replace(Folder, "").Replace("\", "/")
 *   Await WebView21.CoreWebView2.ExecuteScriptAsync(
 *       $"openFile({JsonConvert.SerializeObject(rel)});")
 *
 *   ' Ribbon 主题按钮
 *   Await WebView21.CoreWebView2.ExecuteScriptAsync("toggleTheme();")
 *
 * 本地调试：
 *   run("http://localhost:8080");
 *   openFile("data/example.csv");
 * ======================================================= */
