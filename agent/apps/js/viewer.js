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
  var SCI_DIGITS = 4; // 科学计数法保留有效数字位数
  var NUM_SAMPLE_LIMIT = 500; // 列类型推断的采样行数上限
  var NUMERIC_RATIO = 0.8; // 判定为数值列所需的可解析比例
  var ZSCORE_CLAMP = 2; // 行 Z-score 热图的映射区间 ±N
  var FILTER_DEBOUNCE = 200; // 筛选输入防抖（毫秒）
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
    return fetch(url, { cache: "no-store", signal: signal }).then(
      function (res) {
        if (!res.ok) throw new Error("HTTP " + res.status + " · " + url);
        return res;
      },
    );
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

  /* 文本输入框（宽度可定制，供表格筛选等场景复用） */
  function mkInput(placeholder, width, title) {
    var i = el("input", "tool-input");
    i.type = "text";
    if (placeholder) i.placeholder = placeholder;
    if (width) i.style.width = width;
    if (title) i.title = title;
    return i;
  }

  /**
   * 下拉选择框。
   * options 为 [{ value, label, group }]，带 group 时自动生成 optgroup。
   */
  function mkSelect(options, title, onChange) {
    var s = el("select", "tool-select");
    if (title) s.title = title;
    var groups = {};
    for (var i = 0; i < options.length; i++) {
      var o = options[i];
      var opt = el("option");
      opt.value = o.value;
      opt.textContent = o.label;
      if (o.group) {
        if (!groups[o.group]) {
          groups[o.group] = el("optgroup");
          groups[o.group].label = o.group;
          s.appendChild(groups[o.group]);
        }
        groups[o.group].appendChild(opt);
      } else {
        s.appendChild(opt);
      }
    }
    if (onChange) s.addEventListener("change", onChange);
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

  /* ===================== 表格工具：数值解析与列类型推断 ===================== */

  /* 常见缺失值标记（小写比对），一律视为无数值 */
  var NA_TOKENS = {
    "": 1,
    na: 1,
    "n/a": 1,
    "#n/a": 1,
    nan: 1,
    null: 1,
    nil: 1,
    none: 1,
    "-": 1,
    "--": 1,
    ".": 1,
    "?": 1,
  };

  /**
   * 宽松数值解析：可解析返回有限数字，否则返回 NaN。
   * 支持前后空白、科学计数法、正负号；allowComma 时剥离千分位逗号。
   */
  function parseNum(s, allowComma) {
    if (s == null) return NaN;
    if (typeof s === "number") return isFinite(s) ? s : NaN;
    var t = String(s).replace(/^\s+|\s+$/g, "");
    if (NA_TOKENS[t.toLowerCase()] === 1) return NaN;
    if (allowComma && t.indexOf(",") >= 0) t = t.replace(/,/g, "");
    // 严格形状校验：避免 "1abc" / "12%" / "3-4" 被 parseFloat 误判
    if (!/^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$/.test(t)) return NaN;
    var v = parseFloat(t);
    return isFinite(v) ? v : NaN;
  }

  /**
   * 列类型推断：对每列采样统计可解析为数值的非空单元格比例。
   * 返回 colMeta 数组，数值列附带 Float64Array 缓存与 min/max。
   * 数值缓存是本模块最重要的性能优化——筛选 / 排序 / 热图三处共享，
   * 避免对同一单元格重复做字符串解析。
   */
  function inferColumnTypes(body, rowCount, colCount, allowComma) {
    var meta = [];
    var sampleEnd = Math.min(rowCount, NUM_SAMPLE_LIMIT);

    for (var c = 0; c < colCount; c++) {
      var candidate = 0; // 参与判定的单元格（排除空值与 NA 等缺失标记）
      var numeric = 0;
      for (var r = 0; r < sampleEnd; r++) {
        var raw = body[r][c];
        var t = raw == null ? "" : String(raw).replace(/^\s+|\s+$/g, "");
        // 空值与公认的缺失标记不计入分母，否则含 NA 的数值列会被误判为文本列
        if (t === "" || NA_TOKENS[t.toLowerCase()] === 1) continue;
        candidate++;
        if (!isNaN(parseNum(raw, allowComma))) numeric++;
      }
      var isNum = candidate > 0 && numeric / candidate >= NUMERIC_RATIO;
      meta.push({
        numeric: isNum,
        nums: isNum ? new Float64Array(rowCount) : null,
        min: NaN,
        max: NaN,
        filled: 0, // 已填充进 nums 的行数，供「加载更多」增量扩充
      });
    }

    fillColumnNums(meta, body, 0, rowCount, colCount, allowComma);
    return meta;
  }

  /**
   * 增量填充数值缓存并更新 min/max。
   * 「加载更多」时只处理新增区间 [from, to)，不做全量重算。
   */
  function fillColumnNums(meta, body, from, to, colCount, allowComma) {
    for (var c = 0; c < colCount; c++) {
      var m = meta[c];
      if (!m.numeric) continue;

      // 扩容：Float64Array 定长，需重建后拷贝已有数据
      if (m.nums.length < to) {
        var bigger = new Float64Array(to);
        bigger.set(m.nums);
        m.nums = bigger;
      }

      var min = m.min;
      var max = m.max;
      for (var r = from; r < to; r++) {
        var v = parseNum(body[r][c], allowComma);
        m.nums[r] = v;
        if (isNaN(v)) continue;
        if (isNaN(min) || v < min) min = v;
        if (isNaN(max) || v > max) max = v;
      }
      m.min = min;
      m.max = max;
      m.filled = to;
    }
  }

  /**
   * 4 位有效数字的科学计数法。
   * 0 直接返回 "0"；非有限值原样退回。
   */
  function formatSci(v) {
    if (!isFinite(v)) return String(v);
    if (v === 0) return "0";
    var s = v.toExponential(SCI_DIGITS - 1); // toExponential 参数为小数位数
    // 规整指数：去掉 e+05 这类前导零，统一为 e+5
    return s.replace(/e([+-])0*(\d)/, "e$1$2");
  }

  /* ===================== 表格工具：调色板 ===================== */

  /**
   * 调色板以锚点 RGB 数组定义，运行时分段线性插值。
   * 相比 256 级查表，常量体积小两个数量级且插值为 O(1)。
   */
  var PALETTES = {
    viridis: {
      name: "Viridis",
      group: "连续型",
      diverging: false,
      anchors: [
        [68, 1, 84],
        [72, 40, 120],
        [62, 74, 137],
        [49, 104, 142],
        [38, 130, 142],
        [31, 158, 137],
        [53, 183, 121],
        [109, 205, 89],
        [180, 222, 44],
        [253, 231, 37],
      ],
    },
    magma: {
      name: "Magma",
      group: "连续型",
      diverging: false,
      anchors: [
        [0, 0, 4],
        [28, 16, 68],
        [79, 18, 123],
        [129, 37, 129],
        [181, 54, 122],
        [229, 80, 100],
        [251, 135, 97],
        [254, 194, 135],
        [252, 253, 191],
      ],
    },
    plasma: {
      name: "Plasma",
      group: "连续型",
      diverging: false,
      anchors: [
        [13, 8, 135],
        [84, 2, 163],
        [139, 10, 165],
        [185, 50, 137],
        [219, 92, 104],
        [244, 136, 73],
        [254, 188, 43],
        [240, 249, 33],
      ],
    },
    rdbu: {
      name: "RdBu 红-蓝",
      group: "发散型",
      diverging: true,
      anchors: [
        [103, 0, 31],
        [178, 24, 43],
        [214, 96, 77],
        [244, 165, 130],
        [253, 219, 199],
        [247, 247, 247],
        [209, 229, 240],
        [146, 197, 222],
        [67, 147, 195],
        [33, 102, 172],
        [5, 48, 97],
      ],
    },
    rdylbu: {
      name: "RdYlBu 红-黄-蓝",
      group: "发散型",
      diverging: true,
      anchors: [
        [165, 0, 38],
        [215, 48, 39],
        [244, 109, 67],
        [253, 174, 97],
        [254, 224, 144],
        [255, 255, 191],
        [224, 243, 248],
        [171, 217, 233],
        [116, 173, 209],
        [69, 117, 180],
        [49, 54, 149],
      ],
    },
    bwr: {
      name: "蓝-白-红",
      group: "发散型",
      diverging: true,
      anchors: [
        [5, 48, 97],
        [67, 147, 195],
        [247, 247, 247],
        [214, 96, 77],
        [103, 0, 31],
      ],
    },
    blues: {
      name: "Blues 蓝",
      group: "单色",
      diverging: false,
      anchors: [
        [247, 251, 255],
        [222, 235, 247],
        [198, 219, 239],
        [158, 202, 225],
        [107, 174, 214],
        [66, 146, 198],
        [33, 113, 181],
        [8, 81, 156],
        [8, 48, 107],
      ],
    },
    greens: {
      name: "Greens 绿",
      group: "单色",
      diverging: false,
      anchors: [
        [247, 252, 245],
        [229, 245, 224],
        [199, 233, 192],
        [161, 217, 155],
        [116, 196, 118],
        [65, 171, 93],
        [35, 139, 69],
        [0, 109, 44],
        [0, 68, 27],
      ],
    },
    oranges: {
      name: "Oranges 橙",
      group: "单色",
      diverging: false,
      anchors: [
        [255, 245, 235],
        [254, 230, 206],
        [253, 208, 162],
        [253, 174, 107],
        [253, 141, 60],
        [241, 105, 19],
        [217, 72, 1],
        [166, 54, 3],
        [127, 39, 4],
      ],
    },
    jet: {
      name: "Jet",
      group: "经典",
      diverging: false,
      anchors: [
        [0, 0, 131],
        [0, 60, 170],
        [5, 255, 255],
        [255, 255, 0],
        [250, 0, 0],
        [128, 0, 0],
      ],
    },
    rainbow: {
      name: "Rainbow 彩虹",
      group: "经典",
      diverging: false,
      anchors: [
        [110, 64, 170],
        [76, 110, 219],
        [35, 171, 216],
        [29, 223, 163],
        [110, 245, 99],
        [191, 231, 49],
        [255, 191, 60],
        [255, 124, 89],
        [255, 74, 130],
      ],
    },
    hot: {
      name: "热力 红-黄",
      group: "经典",
      diverging: false,
      anchors: [
        [10, 0, 0],
        [140, 0, 0],
        [230, 60, 0],
        [255, 150, 0],
        [255, 220, 60],
        [255, 255, 224],
      ],
    },
  };

  var PALETTE_KEYS = [
    "viridis",
    "magma",
    "plasma",
    "rdbu",
    "rdylbu",
    "bwr",
    "blues",
    "greens",
    "oranges",
    "jet",
    "rainbow",
    "hot",
  ];

  /* 锚点分段线性插值，t 会被 clamp 到 [0,1] */
  function paletteColor(anchors, t) {
    if (isNaN(t)) t = 0.5;
    if (t < 0) t = 0;
    if (t > 1) t = 1;
    var last = anchors.length - 1;
    var pos = t * last;
    var i = Math.floor(pos);
    if (i >= last) return [anchors[last][0], anchors[last][1], anchors[last][2]];
    var f = pos - i;
    var a = anchors[i];
    var b = anchors[i + 1];
    return [
      Math.round(a[0] + (b[0] - a[0]) * f),
      Math.round(a[1] + (b[1] - a[1]) * f),
      Math.round(a[2] + (b[2] - a[2]) * f),
    ];
  }

  /* 感知亮度（ITU-R BT.601 加权），用于自动挑选对比文字色 */
  function luminance(rgb) {
    return 0.299 * rgb[0] + 0.587 * rgb[1] + 0.114 * rgb[2];
  }

  function rgbCss(rgb) {
    return "rgb(" + rgb[0] + "," + rgb[1] + "," + rgb[2] + ")";
  }

  /* 生成调色板预览用的 CSS 渐变（下拉选项旁的色带条） */
  function paletteGradient(key) {
    var anchors = PALETTES[key].anchors;
    var stops = [];
    for (var i = 0; i < anchors.length; i++) {
      var pct = Math.round((i / (anchors.length - 1)) * 100);
      stops.push(rgbCss(anchors[i]) + " " + pct + "%");
    }
    return "linear-gradient(to right," + stops.join(",") + ")";
  }

  /* ===================== 表格工具：筛选与排序 ===================== */

  /**
   * 依据 filter 配置生成谓词。
   * 正则在设置阶段已预编译并存于 f.re，此处绝不重复 new RegExp。
   * 返回 function(rowIdx, rawText) -> Boolean。
   */
  function makeFilterPredicate(f, meta) {
    if (f.mode === "num") {
      var hasMin = f.min != null && !isNaN(f.min);
      var hasMax = f.max != null && !isNaN(f.max);
      var nums = meta && meta.nums;
      return function (idx, raw) {
        var v = nums ? nums[idx] : parseNum(raw, false);
        if (isNaN(v)) return false; // 缺失值不落在任何数值区间内
        if (hasMin && v < f.min) return false;
        if (hasMax && v > f.max) return false;
        return true;
      };
    }

    if (f.mode === "regex") {
      var re = f.re;
      if (!re) {
        return function () {
          return true;
        };
      }
      return function (idx, raw) {
        re.lastIndex = 0; // 防御 g 标志导致的 test 状态残留
        var hit = re.test(raw == null ? "" : raw);
        return f.negate ? !hit : hit;
      };
    }

    // mode === "text"
    var needle = f.caseSensitive ? f.value : String(f.value).toLowerCase();
    var op = f.op;
    return function (idx, raw) {
      var s = raw == null ? "" : String(raw);
      if (!f.caseSensitive) s = s.toLowerCase();
      switch (op) {
        case "notContains":
          return s.indexOf(needle) < 0;
        case "equals":
          return s === needle;
        case "notEquals":
          return s !== needle;
        case "startsWith":
          return s.lastIndexOf(needle, 0) === 0;
        case "endsWith":
          return (
            needle.length <= s.length &&
            s.indexOf(needle, s.length - needle.length) >= 0
          );
        default:
          return s.indexOf(needle) >= 0;
      }
    };
  }

  /**
   * 多列比较器。
   * 全等时回退比较原始行下标，使排序结果确定且稳定
   * （ES5 不保证 Array.prototype.sort 稳定，显式回退最可靠）。
   */
  function makeComparator(sortKeys, colMeta, body) {
    return function (ia, ib) {
      for (var k = 0; k < sortKeys.length; k++) {
        var key = sortKeys[k];
        var c = key.col;
        var m = colMeta[c];
        var d = 0;

        if (m && m.numeric) {
          var va = m.nums[ia];
          var vb = m.nums[ib];
          var na = isNaN(va);
          var nb = isNaN(vb);
          // 缺失值恒沉底，与排序方向无关
          if (na && nb) d = 0;
          else if (na) return 1;
          else if (nb) return -1;
          else d = va < vb ? -1 : va > vb ? 1 : 0;
        } else {
          var sa = body[ia][c];
          var sb = body[ib][c];
          sa = sa == null ? "" : String(sa);
          sb = sb == null ? "" : String(sb);
          if (sa === "" && sb === "") d = 0;
          else if (sa === "") return 1;
          else if (sb === "") return -1;
          else d = sa.localeCompare(sb);
        }

        if (d !== 0) return d * key.dir;
      }
      return ia - ib;
    };
  }

  /* ===================== 表格工具：列筛选浮层 ===================== */

  var TEXT_OPS = [
    { value: "contains", label: "包含" },
    { value: "notContains", label: "不包含" },
    { value: "equals", label: "等于" },
    { value: "notEquals", label: "不等于" },
    { value: "startsWith", label: "开头是" },
    { value: "endsWith", label: "结尾是" },
  ];

  /* 当前打开的浮层（同一时刻只允许一个），关闭函数存于此 */
  var openPopClose = null;

  function closeFilterPopover() {
    if (openPopClose) {
      var fn = openPopClose;
      openPopClose = null;
      fn();
    }
  }

  /**
   * 打开列筛选浮层。
   *
   * 浮层挂载到 body 并用 fixed 定位——.viewer-stage 与 .vtable-wrap 是两层
   * overflow:auto 容器，absolute 定位会被裁剪。
   *
   * opts: { anchor, colIndex, colName, numeric, current, onApply, onClear, scrollEl }
   */
  function openFilterPopover(opts) {
    closeFilterPopover();

    var cur = opts.current || null;
    var mode = cur ? cur.mode : opts.numeric ? "num" : "text";

    var pop = el("div", "vfilter-pop");
    pop.setAttribute("role", "dialog");

    var title = el("div", "vfp-title");
    title.textContent = opts.colName || "第 " + (opts.colIndex + 1) + " 列";
    pop.appendChild(title);

    /* — 模式切换分段按钮组 — */
    var tabs = el("div", "vfp-tabs");
    var modes = [
      { key: "text", label: "文本" },
      { key: "regex", label: "正则" },
      { key: "num", label: "数值" },
    ];
    var tabBtns = {};
    var panels = {};

    function selectMode(k) {
      mode = k;
      for (var mk in tabBtns) {
        if (!tabBtns.hasOwnProperty(mk)) continue;
        tabBtns[mk].classList.toggle("active", mk === k);
        panels[mk].hidden = mk !== k;
      }
      err.textContent = "";
      var first = panels[k].querySelector("input");
      if (first) first.focus();
    }

    for (var i = 0; i < modes.length; i++) {
      (function (m) {
        var b = el("button", "vfp-tab");
        b.type = "button";
        b.textContent = m.label;
        b.addEventListener("click", function () {
          selectMode(m.key);
        });
        tabBtns[m.key] = b;
        tabs.appendChild(b);
      })(modes[i]);
    }
    pop.appendChild(tabs);

    var body = el("div", "vfp-body");
    pop.appendChild(body);

    /* — 文本模式 — */
    var pText = el("div", "vfp-panel");
    var opSel = mkSelect(TEXT_OPS, "匹配方式");
    opSel.className = "vfp-select";
    var textInput = mkInput("输入关键字", "100%");
    var csLabel = el("label", "vfp-check");
    var csBox = el("input");
    csBox.type = "checkbox";
    csLabel.appendChild(csBox);
    csLabel.appendChild(document.createTextNode("区分大小写"));
    pText.appendChild(opSel);
    pText.appendChild(textInput);
    pText.appendChild(csLabel);
    body.appendChild(pText);
    panels.text = pText;

    /* — 正则模式 — */
    var pRe = el("div", "vfp-panel");
    var reRow = el("div", "vfp-row");
    var reInput = mkInput("正则表达式，如 ^ENSG", "100%");
    var reFlags = mkInput("标志", "58px", "正则标志位，如 i / g / m");
    reRow.appendChild(reInput);
    reRow.appendChild(reFlags);
    var reNegLabel = el("label", "vfp-check");
    var reNeg = el("input");
    reNeg.type = "checkbox";
    reNegLabel.appendChild(reNeg);
    reNegLabel.appendChild(document.createTextNode("反选（排除匹配项）"));
    pRe.appendChild(reRow);
    pRe.appendChild(reNegLabel);
    body.appendChild(pRe);
    panels.regex = pRe;

    /* — 数值范围模式 — */
    var pNum = el("div", "vfp-panel");
    var numRow = el("div", "vfp-row");
    var minInput = mkInput("最小值", "100%", "留空表示不限下界");
    var maxInput = mkInput("最大值", "100%", "留空表示不限上界");
    numRow.appendChild(minInput);
    numRow.appendChild(el("span", "vfp-tilde", "~"));
    numRow.appendChild(maxInput);
    pNum.appendChild(numRow);
    var numHint = el("div", "vfp-hint");
    numHint.textContent = opts.numeric
      ? "仅保留区间内的数值行，缺失值会被过滤"
      : "该列非数值列，数值筛选可能过滤掉全部行";
    pNum.appendChild(numHint);
    body.appendChild(pNum);
    panels.num = pNum;

    var err = el("div", "vfp-err");
    pop.appendChild(err);

    /* — 回填当前已有条件 — */
    if (cur) {
      if (cur.mode === "text") {
        opSel.value = cur.op;
        textInput.value = cur.value;
        csBox.checked = !!cur.caseSensitive;
      } else if (cur.mode === "regex") {
        reInput.value = cur.source;
        reFlags.value = cur.flags || "";
        reNeg.checked = !!cur.negate;
      } else if (cur.mode === "num") {
        if (cur.min != null && !isNaN(cur.min)) minInput.value = String(cur.min);
        if (cur.max != null && !isNaN(cur.max)) maxInput.value = String(cur.max);
      }
    }

    /* — 底部操作区 — */
    var actions = el("div", "vfp-actions");
    var clearBtn = el("button", "vfp-btn");
    clearBtn.type = "button";
    clearBtn.textContent = "清除本列";
    var applyBtn = el("button", "vfp-btn primary");
    applyBtn.type = "button";
    applyBtn.textContent = "应用";
    actions.appendChild(clearBtn);
    actions.appendChild(applyBtn);
    pop.appendChild(actions);

    /* 收集表单为 filter 配置；非法输入返回 null 并写入错误提示 */
    function collect() {
      err.textContent = "";

      if (mode === "text") {
        if (textInput.value === "") return null;
        return {
          mode: "text",
          op: opSel.value,
          value: textInput.value,
          caseSensitive: csBox.checked,
        };
      }

      if (mode === "regex") {
        var src = reInput.value;
        if (src === "") return null;
        var flags = reFlags.value.replace(/[^gimsuy]/g, "");
        var re;
        try {
          re = new RegExp(src, flags);
        } catch (e) {
          // 非法正则：提示并保留原有筛选状态，不破坏当前视图
          console.warn("正则表达式无效", e);
          err.textContent = "正则无效：" + e.message;
          return false;
        }
        return {
          mode: "regex",
          source: src,
          flags: flags,
          negate: reNeg.checked,
          re: re,
        };
      }

      var mn = minInput.value.replace(/^\s+|\s+$/g, "");
      var mx = maxInput.value.replace(/^\s+|\s+$/g, "");
      if (mn === "" && mx === "") return null;
      var nmin = mn === "" ? null : parseNum(mn, true);
      var nmax = mx === "" ? null : parseNum(mx, true);
      if ((mn !== "" && isNaN(nmin)) || (mx !== "" && isNaN(nmax))) {
        err.textContent = "请输入合法数字";
        return false;
      }
      if (nmin != null && nmax != null && nmin > nmax) {
        err.textContent = "最小值不能大于最大值";
        return false;
      }
      return { mode: "num", min: nmin, max: nmax };
    }

    function apply() {
      var f = collect();
      if (f === false) return; // 校验失败，浮层保持打开
      if (f === null) opts.onClear();
      else opts.onApply(f);
      closeFilterPopover();
    }

    applyBtn.addEventListener("click", apply);
    clearBtn.addEventListener("click", function () {
      opts.onClear();
      closeFilterPopover();
    });

    // 回车即应用
    pop.addEventListener("keydown", function (e) {
      if (e.key === "Enter") {
        e.preventDefault();
        apply();
      }
    });

    document.body.appendChild(pop);
    selectMode(mode);

    /* — 定位：跟随列头，越界时翻转 — */
    function place() {
      var r = opts.anchor.getBoundingClientRect();
      var pw = pop.offsetWidth;
      var ph = pop.offsetHeight;
      var gap = 4;

      var left = r.left;
      if (left + pw > window.innerWidth - 8) left = window.innerWidth - pw - 8;
      if (left < 8) left = 8;

      var top = r.bottom + gap;
      if (top + ph > window.innerHeight - 8) {
        var flipped = r.top - ph - gap;
        top = flipped >= 8 ? flipped : Math.max(8, window.innerHeight - ph - 8);
      }

      pop.style.left = left + "px";
      pop.style.top = top + "px";
    }
    place();

    /* — 生命周期：所有监听器统一注销，防止 WebView2 长跑泄漏 — */
    function onDocDown(e) {
      if (!pop.contains(e.target) && e.target !== opts.anchor)
        closeFilterPopover();
    }
    function onKey(e) {
      if (e.key === "Escape") closeFilterPopover();
    }
    function onScrollOrResize() {
      closeFilterPopover();
    }

    // 延后注册，避免触发本次打开的这一次 mousedown
    var t = setTimeout(function () {
      document.addEventListener("mousedown", onDocDown, true);
    }, 0);
    document.addEventListener("keydown", onKey, true);
    window.addEventListener("resize", onScrollOrResize);
    if (opts.scrollEl)
      opts.scrollEl.addEventListener("scroll", onScrollOrResize);

    var closed = false;
    function destroy() {
      if (closed) return;
      closed = true;
      clearTimeout(t);
      document.removeEventListener("mousedown", onDocDown, true);
      document.removeEventListener("keydown", onKey, true);
      window.removeEventListener("resize", onScrollOrResize);
      if (opts.scrollEl)
        opts.scrollEl.removeEventListener("scroll", onScrollOrResize);
      if (pop.parentNode) pop.parentNode.removeChild(pop);
      if (opts.onClose) opts.onClose();
    }

    openPopClose = destroy;
    // 切换文件时若浮层仍开着，由 disposeCurrent 兜底清理
    addDisposer(destroy);
  }

  /* 列头图标（漏斗 / 排序），16px 线性风格与工具栏保持一致 */
  var ICON_FILTER =
    '<svg viewBox="0 0 16 16" width="12" height="12" aria-hidden="true">' +
    '<path d="M1.5 2.5h13l-5 5.6v4.6l-3 1.8V8.1z" fill="none" ' +
    'stroke="currentColor" stroke-width="1.4" stroke-linejoin="round"/></svg>';

  /**
   * 表格渲染器（csv / tsv）。
   *
   * 采用「数据模型 → 视图状态 → 声明式重绘」三层结构：
   *   body（原始行） → loadedCount 切片 → filters 过滤 → sortKeys 排序
   *   → viewIdx（原始行下标数组） → 格式化 + 着色 → 一次性替换 tbody
   *
   * 关键决策：始终以 viewIdx 索引数组表达视图，不拷贝行数据。
   * 既省内存，也让行号列能回溯到原始行号（排序后行号语义仍正确）。
   *
   * 约定：排序与筛选只作用于「当前已加载的行」，保持既有分批语义。
   */
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

    // 行长度对齐，省去后续所有取值处的越界判断
    for (var r2 = 0; r2 < body.length; r2++) {
      var rowArr = body[r2];
      for (var pad = rowArr.length; pad < colCount; pad++) rowArr[pad] = "";
    }

    // 千分位逗号仅在 tsv 中放行；csv 里逗号是分隔符，避免误判
    var allowComma = delim === "\t";

    /* ---------- 视图状态：唯一数据源，任何变更后调用 refresh() ---------- */
    var state = {
      loadedCount: Math.min(MAX_TABLE_ROWS, body.length),
      sortKeys: [], // [{ col, dir }]，顺序即优先级
      filters: {}, // { [col]: filter }，多列 AND
      sciMode: false, // 4 位有效数字科学计数法
      heatMode: "off", // off | col（列 min/max） | row（行 Z-score）
      palette: "viridis",
    };

    var colMeta = inferColumnTypes(
      body,
      state.loadedCount,
      colCount,
      allowComma,
    );
    var rowStats = {}; // 行 Z-score 统计量缓存 { [origIdx]: { mean, sd } }
    var viewIdx = []; // 当前视图的原始行下标序列

    /* ---------- DOM 骨架 ---------- */
    var box = el("div", "vtable-wrap");
    var table = el("table", "vtable");
    var thead = el("thead");
    var htr = el("tr");
    htr.appendChild(el("th", "rownum", "#"));
    var thNodes = [];
    var sortMarks = [];
    var filterBtns = [];

    for (var c = 0; c < colCount; c++) {
      (function (ci) {
        var th = el("th", "sortable");
        if (colMeta[ci].numeric) th.className += " num";

        var inner = el("div", "vth-inner");
        var label = el("span", "vth-label");
        label.textContent = header[ci] != null ? header[ci] : "";
        label.title = label.textContent;

        var mark = el("span", "vth-sort");
        var fbtn = el("button", "vth-filter", ICON_FILTER);
        fbtn.type = "button";
        fbtn.title = "筛选此列";

        inner.appendChild(label);
        inner.appendChild(mark);
        inner.appendChild(fbtn);
        th.appendChild(inner);

        // 点击列头排序；Shift 追加为次级排序键
        th.addEventListener("click", function (e) {
          if (fbtn.contains(e.target)) return;
          toggleSort(ci, e.shiftKey);
        });

        fbtn.addEventListener("click", function (e) {
          e.stopPropagation();
          openColumnFilter(ci, fbtn);
        });

        thNodes.push(th);
        sortMarks.push(mark);
        filterBtns.push(fbtn);
        htr.appendChild(th);
      })(c);
    }

    thead.appendChild(htr);
    table.appendChild(thead);

    var tbody = el("tbody");
    table.appendChild(tbody);
    box.appendChild(table);
    wrap.appendChild(box);

    var emptyTip = el("div", "vtable-empty");
    emptyTip.textContent = "没有符合当前筛选条件的行";
    emptyTip.hidden = true;
    wrap.appendChild(emptyTip);

    /* ---------- 排序 ---------- */
    function findSortKey(col) {
      for (var i = 0; i < state.sortKeys.length; i++)
        if (state.sortKeys[i].col === col) return i;
      return -1;
    }

    /* 三态循环：升序 → 降序 → 无序 */
    function toggleSort(col, additive) {
      var at = findSortKey(col);
      if (!additive) {
        if (at >= 0 && state.sortKeys.length === 1) {
          var d = state.sortKeys[0].dir;
          state.sortKeys = d === 1 ? [{ col: col, dir: -1 }] : [];
        } else {
          state.sortKeys = [{ col: col, dir: 1 }];
        }
      } else if (at >= 0) {
        if (state.sortKeys[at].dir === 1) state.sortKeys[at].dir = -1;
        else state.sortKeys.splice(at, 1);
      } else {
        state.sortKeys.push({ col: col, dir: 1 });
      }
      refresh();
    }

    function syncHeader() {
      for (var i = 0; i < colCount; i++) {
        var at = findSortKey(i);
        var mark = sortMarks[i];
        if (at < 0) {
          mark.textContent = "";
          mark.classList.remove("on");
          thNodes[i].classList.remove("sorted");
        } else {
          var k = state.sortKeys[at];
          // 多列排序时标注优先级序号
          mark.textContent =
            (k.dir === 1 ? "▲" : "▼") +
            (state.sortKeys.length > 1 ? String(at + 1) : "");
          mark.classList.add("on");
          thNodes[i].classList.add("sorted");
        }
        var active = !!state.filters[i];
        filterBtns[i].classList.toggle("on", active);
        filterBtns[i].title = active ? "已筛选，点击修改" : "筛选此列";
      }
    }

    /* ---------- 筛选 ---------- */
    function openColumnFilter(col, anchor) {
      // 点同一个按钮时作为关闭操作
      if (anchor.classList.contains("popping")) {
        closeFilterPopover();
        return;
      }
      anchor.classList.add("popping");
      openFilterPopover({
        anchor: anchor,
        colIndex: col,
        colName: header[col],
        numeric: colMeta[col].numeric,
        current: state.filters[col] || null,
        scrollEl: box,
        onApply: function (f) {
          state.filters[col] = f;
          refresh();
        },
        onClear: function () {
          delete state.filters[col];
          refresh();
        },
        onClose: function () {
          anchor.classList.remove("popping");
        },
      });
    }

    function clearAllFilters() {
      state.filters = {};
      refresh();
    }

    /* ---------- 视图计算：筛选 → 排序 ---------- */
    function computeView() {
      var preds = [];
      for (var key in state.filters) {
        if (!state.filters.hasOwnProperty(key)) continue;
        var ci = parseInt(key, 10);
        preds.push({
          col: ci,
          fn: makeFilterPredicate(state.filters[key], colMeta[ci]),
        });
      }

      var out = [];
      var n = state.loadedCount;
      for (var i = 0; i < n; i++) {
        var ok = true;
        for (var p = 0; p < preds.length; p++) {
          if (!preds[p].fn(i, body[i][preds[p].col])) {
            ok = false;
            break;
          }
        }
        if (ok) out.push(i);
      }

      if (state.sortKeys.length)
        out.sort(makeComparator(state.sortKeys, colMeta, body));

      viewIdx = out;
    }

    /* ---------- 热图 ---------- */
    /* 行 Z-score 统计量（惰性计算并缓存） */
    function getRowStat(idx) {
      var s = rowStats[idx];
      if (s) return s;
      var sum = 0;
      var cnt = 0;
      var i;
      for (i = 0; i < colCount; i++) {
        if (!colMeta[i].numeric) continue;
        var v = colMeta[i].nums[idx];
        if (isNaN(v)) continue;
        sum += v;
        cnt++;
      }
      var mean = cnt ? sum / cnt : NaN;
      var acc = 0;
      for (i = 0; i < colCount; i++) {
        if (!colMeta[i].numeric) continue;
        var v2 = colMeta[i].nums[idx];
        if (isNaN(v2)) continue;
        acc += (v2 - mean) * (v2 - mean);
      }
      // 总体标准差（非样本），行内全等时为 0
      var sd = cnt ? Math.sqrt(acc / cnt) : NaN;
      s = { mean: mean, sd: sd, count: cnt };
      rowStats[idx] = s;
      return s;
    }

    /* 把数值映射为 [0,1]；无法归一化时返回 NaN（不着色） */
    function heatT(rowIdx, col, v) {
      if (isNaN(v)) return NaN;
      if (state.heatMode === "col") {
        var m = colMeta[col];
        if (isNaN(m.min) || isNaN(m.max)) return NaN;
        if (m.max === m.min) return 0.5; // 常数列取中性色
        return (v - m.min) / (m.max - m.min);
      }
      // row：按行 Z-score，clamp 到 ±ZSCORE_CLAMP 后线性映射
      var st = getRowStat(rowIdx);
      if (!st.count || isNaN(st.mean)) return NaN;
      if (!st.sd) return 0.5; // 行内数值全相等
      var z = (v - st.mean) / st.sd;
      var t = (z + ZSCORE_CLAMP) / (2 * ZSCORE_CLAMP);
      return t < 0 ? 0 : t > 1 ? 1 : t;
    }

    /* ---------- 表体重建 ---------- */
    function renderBody() {
      var anchors = PALETTES[state.palette].anchors;
      var heatOn = state.heatMode !== "off";
      var frag = document.createDocumentFragment();

      for (var i = 0; i < viewIdx.length; i++) {
        var idx = viewIdx[i];
        var row = body[idx];
        var tr = el("tr");

        var tdn = el("td", "rownum");
        tdn.textContent = String(idx + 1); // 始终显示原始行号
        tr.appendChild(tdn);

        for (var c2 = 0; c2 < colCount; c2++) {
          var m = colMeta[c2];
          var td = el("td");
          var raw = row[c2];

          if (m.numeric) {
            td.className = "num";
            var v = m.nums[idx];
            if (state.sciMode && !isNaN(v)) td.textContent = formatSci(v);
            else td.textContent = raw == null ? "" : raw;

            if (heatOn) {
              var t = heatT(idx, c2, v);
              if (!isNaN(t)) {
                var rgb = paletteColor(anchors, t);
                td.style.backgroundColor = rgbCss(rgb);
                // 依背景亮度切换文字色，保证任意配色下可读
                td.className +=
                  luminance(rgb) < 140 ? " hm-dark" : " hm-light";
              }
            }
          } else {
            td.textContent = raw == null ? "" : raw;
          }

          tr.appendChild(td);
        }
        frag.appendChild(tr);
      }

      // 单次替换，全程只触发一次 reflow
      var fresh = el("tbody");
      fresh.appendChild(frag);
      table.replaceChild(fresh, tbody);
      tbody = fresh;

      table.classList.toggle("heatmap-on", heatOn);
      emptyTip.hidden = viewIdx.length > 0;
    }

    /* ---------- 统一刷新入口（同帧内多次调用自动合并） ---------- */
    var rafId = 0;
    function refresh() {
      if (rafId) return;
      rafId = window.requestAnimationFrame(function () {
        rafId = 0;
        computeView();
        renderBody();
        syncHeader();
        syncInfo();
      });
    }
    addDisposer(function () {
      if (rafId) window.cancelAnimationFrame(rafId);
      rafId = 0;
    });

    /* ---------- 工具栏 ---------- */
    var totalInfo = mkInfo(body.length + " 行 × " + colCount + " 列");
    var viewInfo = mkInfo("");

    var sciBtn = mkBtn(
      "科学计数",
      "数值列在原始文本与 4 位有效数字科学计数法之间切换",
      function () {
        state.sciMode = !state.sciMode;
        sciBtn.classList.toggle("active", state.sciMode);
        refresh();
      },
    );

    var colHeatBtn = mkBtn(
      "列热图",
      "按每列 min / max 归一化，为数值单元格着色",
      function () {
        state.heatMode = state.heatMode === "col" ? "off" : "col";
        syncHeatBtns();
        refresh();
      },
    );

    var rowHeatBtn = mkBtn(
      "全局热图",
      "按每行 Z-score 标准化着色，适合跨列比较行内模式",
      function () {
        state.heatMode = state.heatMode === "row" ? "off" : "row";
        syncHeatBtns();
        refresh();
      },
    );

    function syncHeatBtns() {
      colHeatBtn.classList.toggle("active", state.heatMode === "col");
      rowHeatBtn.classList.toggle("active", state.heatMode === "row");
      palSel.disabled = state.heatMode === "off";
      palSwatch.style.opacity = state.heatMode === "off" ? "0.4" : "1";
    }

    var palOpts = [];
    for (var pi = 0; pi < PALETTE_KEYS.length; pi++) {
      var pk = PALETTE_KEYS[pi];
      palOpts.push({
        value: pk,
        label: PALETTES[pk].name,
        group: PALETTES[pk].group,
      });
    }

    var palSwatch = el("span", "pal-swatch");
    var palSel = mkSelect(palOpts, "热图调色板", function () {
      state.palette = palSel.value;
      palSwatch.style.background = paletteGradient(state.palette);
      refresh();
    });
    palSel.value = state.palette;
    palSwatch.style.background = paletteGradient(state.palette);

    var clearBtn = mkBtn("清除筛选", "清除所有列的筛选条件", function () {
      clearAllFilters();
    });
    var unsortBtn = mkBtn("清除排序", "恢复为原始行顺序", function () {
      state.sortKeys = [];
      refresh();
    });

    var moreInfo = mkInfo("");
    var moreBtn = mkBtn("加载更多", "继续加载后续行并套用当前排序 / 筛选", function () {
      var from = state.loadedCount;
      var to = Math.min(from + MAX_TABLE_ROWS, body.length);
      if (to <= from) return;
      state.loadedCount = to;
      // 增量扩充数值缓存；min/max 随之更新，行统计缓存无需失效
      fillColumnNums(colMeta, body, from, to, colCount, allowComma);
      refresh();
    });

    function syncInfo() {
      var loaded = state.loadedCount;
      var shownRows = viewIdx.length;
      var hasFilter = false;
      for (var k in state.filters) {
        if (state.filters.hasOwnProperty(k)) {
          hasFilter = true;
          break;
        }
      }
      viewInfo.textContent = hasFilter
        ? "筛选后 " + shownRows + " / 已加载 " + loaded + " 行"
        : "已加载 " + loaded + " 行";

      var done = loaded >= body.length;
      moreInfo.textContent = done ? "" : "剩余 " + (body.length - loaded) + " 行";
      moreBtn.disabled = done;
      moreBtn.style.opacity = done ? "0.5" : "";
      moreBtn.style.cursor = done ? "default" : "";
      clearBtn.classList.toggle("active", hasFilter);
      unsortBtn.classList.toggle("active", state.sortKeys.length > 0);
    }

    var bar = [
      totalInfo,
      mkSep(),
      viewInfo,
      mkSep(),
      sciBtn,
      colHeatBtn,
      rowHeatBtn,
      palSwatch,
      palSel,
      mkSep(),
      unsortBtn,
      clearBtn,
    ];

    if (body.length > state.loadedCount) bar.push(mkSep(), moreInfo, moreBtn);

    syncHeatBtns();

    // 首屏同步渲染，避免 rAF 造成一帧空白
    computeView();
    renderBody();
    syncHeader();
    syncInfo();

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
      kids.length === 0 || (kids.length === 1 && kids[0].nodeType === 3);

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
      el(
        "span",
        "jt-summary",
        "… " + kids.length + " nodes </" + elem.nodeName + ">",
      ),
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
    rotL: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="1 4 1 10 7 10"/><path d="M3.51 15a9 9 0 1 0 2.13-9.36L1 10"/></svg>',
    rotR: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="23 4 23 10 17 10"/><path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"/></svg>',
    flipH:
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v18"/><path d="M8 7L3 12l5 5z"/><path d="M16 7l5 5-5 5z"/></svg>',
    flipV:
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12h18"/><path d="M7 8L12 3l5 5z"/><path d="M7 16l5 5 5-5z"/></svg>',
    fit: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 3h6v6"/><path d="M9 21H3v-6"/><path d="M21 3l-7 7"/><path d="M3 21l7-7"/></svg>',
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
      if (zoomInfo) zoomInfo.textContent = Math.round(st.scale * 100) + "%";
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
      mkBtn(
        "放大",
        "放大（滚轮上）",
        function () {
          zoom(1.25);
        },
        ICON.zoomIn,
      ),
      mkBtn(
        "缩小",
        "缩小（滚轮下）",
        function () {
          zoom(1 / 1.25);
        },
        ICON.zoomOut,
      ),
      zoomInfo,
      mkSep(),
      mkBtn(
        "左旋",
        "逆时针旋转 90°",
        function () {
          st.rotate -= 90;
          apply();
        },
        ICON.rotL,
      ),
      mkBtn(
        "右旋",
        "顺时针旋转 90°",
        function () {
          st.rotate += 90;
          apply();
        },
        ICON.rotR,
      ),
      mkSep(),
      mkBtn(
        "水平翻转",
        "左右镜像",
        function () {
          st.flipX = !st.flipX;
          apply();
        },
        ICON.flipH,
      ),
      mkBtn(
        "垂直翻转",
        "上下镜像",
        function () {
          st.flipY = !st.flipY;
          apply();
        },
        ICON.flipV,
      ),
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
      wrap.style.cssText =
        "position:absolute;inset:0;display:flex;flex-direction:column";
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
      return {
        node: wrap,
        toolbar: [mkOpenExternal(ctx.url, ctx.name)],
        fullBleed: true,
      };
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
      mkBtn(
        "放大",
        "放大",
        function () {
          scale = Math.min(4, scale * 1.25);
          reflow();
        },
        ICON.zoomIn,
      ),
      mkBtn(
        "缩小",
        "缩小",
        function () {
          scale = Math.max(0.25, scale / 1.25);
          reflow();
        },
        ICON.zoomOut,
      ),
      zoomInfo,
    ];

    return { node: host, toolbar: bar, fullBleed: true };
  }

  /* ===================== ⑧ HTML（沙箱） ===================== */
  function renderHtmlDoc(text, ctx) {
    var host = el("div");
    host.style.cssText =
      "position:absolute;inset:0;display:flex;flex-direction:column";

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
          srcView.style.cssText = "flex:1;overflow:auto;position:relative";
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
      toolbar: [toggleBtn, mkSep(), mkInfo("已在沙箱中隔离渲染（禁用脚本）")],
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
