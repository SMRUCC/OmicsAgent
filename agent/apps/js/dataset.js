"use strict";

/* ==========================================================================
 * dataset.js — 组学数据集定义文件（dataset.json）可视化编辑器
 *
 * 产物契约来源：
 *   src/AppRuntime/DatasetManifest.vb  （DatasetManifest / DatasetEntry / SampleAlignmentSpec）
 *   src/Program.vb                     （HelpText 中的格式示例）
 *
 * 宿主交互：
 *   WebView2 宿主对象注册名为 "win32"（win32/Application/JavaScript/BasePage.vb）
 *   JS 侧访问路径 chrome.webview.hostObjects.win32，全部为异步代理。
 *   宿主方法缺失时自动降级，保证浏览器直开亦完全可用。
 *
 * 宿主可调用的全局函数：
 *   run(baseUrl) / toggleTheme() / setMode(m) / setBaseDir(dir)
 *   loadManifestJson(text) / getManifestJson() / saveManifest()
 * ========================================================================== */

var toggleTheme = null;

(function () {

  /* ===================== 小工具 ===================== */

  const $ = (sel) => document.querySelector(sel);
  const $$ = (sel) => Array.prototype.slice.call(document.querySelectorAll(sel));

  const el = (tag, cls, html) => {
    const n = document.createElement(tag);
    if (cls) n.className = cls;
    if (html != null) n.innerHTML = html;
    return n;
  };

  const esc = (s) =>
    String(s == null ? "" : s).replace(/[&<>"']/g, (c) => ({
      "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
    })[c]);

  const trim = (s) => String(s == null ? "" : s).trim();

  function debounce(fn, ms) {
    let t = 0;
    return function () {
      const args = arguments;
      clearTimeout(t);
      t = setTimeout(() => fn.apply(null, args), ms);
    };
  }

  /* ===================== 常量与预设 ===================== */

  const OMICS_TYPES = [
    { value: "transcriptome", label: "转录组 transcriptome" },
    { value: "proteome", label: "蛋白组 proteome" },
    { value: "metabolome", label: "代谢组 metabolome" },
    { value: "lipidome", label: "脂质组 lipidome" },
    { value: "genome", label: "基因组 genome" },
    { value: "epigenome", label: "表观基因组 epigenome" },
    { value: "microbiome", label: "微生物组 microbiome" },
  ];

  const UNIT_SUGGESTIONS = ["TPM", "FPKM", "RPKM", "counts", "LFQ intensity", "peak area", "log2 ratio"];

  const SUBJECT_ID = "subject_id";     // SampleAlignment.SubjectIdColumn
  const THEME_KEY = "kb-theme";        // 与 kb.html / viewer.html 保持一致
  const DRAFT_KEY = "dataset-editor-draft";
  const MAX_INLINE_ROWS = 500;

  /* ===================== 状态：唯一数据源 ===================== */

  function newEntry(seed) {
    return Object.assign({
      id: "", type: "", label: "",
      expression: "", annotation: "", sampleinfo: "", unit: "",
      sampleNames: [],          // 由宿主读取 expression 表头得到，不参与序列化
      fileState: {},            // path -> 'ok' | 'miss'，不参与序列化
    }, seed || {});
  }

  /** @type {{mode:string,datasets:Array,activeIndex:number,alignment:Object,baseDir:string,useRelativePath:boolean,manifestPath:string,filter:string,errors:Array}} */
  let state = {
    mode: "multi",
    datasets: [newEntry({ id: "rna", type: "transcriptome" })],
    activeIndex: 0,
    alignment: {
      kind: "none",          // none | file | inline | extract
      mappingFile: "",
      rows: [],              // [{ subject_id: 'P001', rna: 'S1_R', ... }]
    },
    baseDir: "",
    useRelativePath: true,
    manifestPath: "",
    filter: "",
    errors: [],
  };

  /* ===================== 主题 ===================== */

  function applyTheme(theme) {
    document.documentElement.setAttribute("data-theme", theme);
    const dark = theme === "dark";
    const i = $("#themeIcon"), l = $("#themeLabel");
    if (i) i.textContent = dark ? "☀️" : "🌙";
    if (l) l.textContent = dark ? "亮色" : "暗色";
    try { localStorage.setItem(THEME_KEY, theme); } catch (e) { }
  }

  function initTheme() {
    let t = null;
    try { t = localStorage.getItem(THEME_KEY); } catch (e) { }
    if (!t) {
      t = window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches
        ? "dark" : "light";
    }
    applyTheme(t);
  }

  toggleTheme = function () {
    const cur = document.documentElement.getAttribute("data-theme");
    applyTheme(cur === "dark" ? "light" : "dark");
  };

  /* ===================== 吐司提示 ===================== */

  function toast(msg, kind) {
    const host = $("#toastHost");
    if (!host) return;
    const t = el("div", "toast" + (kind ? " " + kind : ""), esc(msg));
    host.appendChild(t);
    setTimeout(() => {
      t.classList.add("leaving");
      setTimeout(() => t.remove(), 320);
    }, 2500);
  }

  /* ===================== 路径工具 ===================== */

  const PathUtil = {
    sep: "\\",

    isAbsolute(p) {
      p = trim(p);
      return /^[a-zA-Z]:[\\/]/.test(p) || /^\\\\/.test(p) || /^\//.test(p);
    },

    normalizeSlash(p) {
      return String(p || "").replace(/\//g, "\\");
    },

    fileName(p) {
      p = trim(p).replace(/[\\/]+$/, "");
      if (!p) return "";
      const i = Math.max(p.lastIndexOf("\\"), p.lastIndexOf("/"));
      return i >= 0 ? p.slice(i + 1) : p;
    },

    dirName(p) {
      p = trim(p);
      const i = Math.max(p.lastIndexOf("\\"), p.lastIndexOf("/"));
      return i > 0 ? p.slice(0, i) : "";
    },

    splitParts(p) {
      return PathUtil.normalizeSlash(p).split("\\").filter((s) => s.length > 0);
    },

    /**
     * 把绝对路径相对化到 baseDir。跨盘符或无公共前缀时原样返回绝对路径。
     * DatasetManifest.ResolvePath 以清单文件所在目录为基准解析相对路径。
     */
    toRelative(abs, baseDir) {
      abs = trim(abs);
      baseDir = trim(baseDir);
      if (!abs || !baseDir || !PathUtil.isAbsolute(abs)) return abs;

      const a = PathUtil.splitParts(abs);
      const b = PathUtil.splitParts(baseDir);
      if (!a.length || !b.length) return abs;

      // 盘符大小写不敏感比较；跨盘符直接放弃相对化
      if (a[0].toLowerCase() !== b[0].toLowerCase()) return abs;

      let i = 0;
      while (i < a.length && i < b.length && a[i].toLowerCase() === b[i].toLowerCase()) i++;

      const up = new Array(b.length - i).fill("..");
      const rest = a.slice(i);
      if (!rest.length && !up.length) return ".";
      const parts = up.concat(rest);
      const joined = parts.join("/");
      return up.length ? joined : "./" + joined;
    },

    /** 相对路径 → 绝对路径（以 baseDir 为基准） */
    toAbsolute(rel, baseDir) {
      rel = trim(rel);
      baseDir = trim(baseDir);
      if (!rel || PathUtil.isAbsolute(rel) || !baseDir) return rel;

      const b = PathUtil.splitParts(baseDir);
      const r = PathUtil.normalizeSlash(rel).split("\\").filter((s) => s.length > 0);
      for (const seg of r) {
        if (seg === ".") continue;
        else if (seg === "..") b.pop();
        else b.push(seg);
      }
      return b.join("\\");
    },
  };

  /* ===================== 宿主桥接层 ===================== */

  const HostBridge = {
    _host: null,
    available: false,

    init() {
      try {
        const h = window.chrome && window.chrome.webview
          && window.chrome.webview.hostObjects
          && window.chrome.webview.hostObjects.win32;
        if (h) { HostBridge._host = h; HostBridge.available = true; }
      } catch (e) {
        HostBridge._host = null;
        HostBridge.available = false;
      }
      return HostBridge.available;
    },

    /**
     * 统一调用入口。宿主方法约定 String -> String，
     * 返回 {"ok":true,"data":...} 或 {"ok":false,"error":"..."}。
     * 方法不存在 / COM 抛错时返回 null，由调用方走降级路径。
     */
    async call(method, payload) {
      if (!HostBridge._host) return null;
      try {
        const fn = HostBridge._host[method];
        if (!fn) return null;
        const raw = await HostBridge._host[method](payload == null ? "" : String(payload));
        if (raw == null || raw === "") return null;
        const res = typeof raw === "string" ? JSON.parse(raw) : raw;
        if (!res || res.ok !== true) {
          if (res && res.error) throw new Error(res.error);
          return null;
        }
        return res.data == null ? {} : res.data;
      } catch (e) {
        console.warn("[HostBridge] " + method + " 调用失败：", e);
        return null;
      }
    },

    async openFile(opts) {
      const data = await HostBridge.call("OpenFileDialog", JSON.stringify(Object.assign({
        title: "选择文件", filter: "所有文件|*.*", multiselect: false, initialDir: state.baseDir,
      }, opts || {})));
      if (!data) return null;
      const paths = data.paths || (data.path ? [data.path] : []);
      return paths.length ? paths : null;
    },

    async saveFile(opts) {
      const data = await HostBridge.call("SaveFileDialog", JSON.stringify(Object.assign({
        title: "保存文件", filter: "所有文件|*.*", defaultName: "", initialDir: state.baseDir,
      }, opts || {})));
      if (!data || !data.path) return null;
      return data.path;
    },

    async writeText(path, content) {
      const data = await HostBridge.call("WriteTextFile",
        JSON.stringify({ path: path, content: content, encoding: "utf-8" }));
      return data ? (data.path || path) : null;
    },

    async readText(path) {
      const data = await HostBridge.call("ReadTextFile", path);
      return data ? (data.content == null ? "" : data.content) : null;
    },

    async readCsvHeader(path) {
      const data = await HostBridge.call("ReadCsvHeader", path);
      if (!data) return null;
      return Array.isArray(data.columns) ? data.columns : null;
    },

    async fileExists(path) {
      const data = await HostBridge.call("FileExists", path);
      if (!data) return null;
      return !!data.exists;
    },
  };

  /* ---------- 降级：浏览器本地文件选取 / 下载 ---------- */

  function pickLocalFile(accept) {
    return new Promise((resolve) => {
      const inp = el("input");
      inp.type = "file";
      if (accept) inp.accept = accept;
      inp.style.display = "none";
      document.body.appendChild(inp);
      inp.addEventListener("change", () => {
        const f = inp.files && inp.files[0];
        inp.remove();
        resolve(f || null);
      });
      inp.click();
    });
  }

  function readFileText(file) {
    return new Promise((resolve, reject) => {
      const r = new FileReader();
      r.onload = () => resolve(String(r.result || ""));
      r.onerror = () => reject(r.error);
      r.readAsText(file, "utf-8");
    });
  }

  function downloadText(name, content, mime) {
    try {
      const blob = new Blob(["\ufeff" + content], { type: (mime || "text/plain") + ";charset=utf-8" });
      const url = URL.createObjectURL(blob);
      const a = el("a");
      a.href = url;
      a.download = name;
      document.body.appendChild(a);
      a.click();
      setTimeout(() => { URL.revokeObjectURL(url); a.remove(); }, 0);
      return true;
    } catch (e) {
      console.warn("下载失败", e);
      return false;
    }
  }

  async function copyText(content) {
    try {
      if (navigator.clipboard && navigator.clipboard.writeText) {
        await navigator.clipboard.writeText(content);
        return true;
      }
    } catch (e) { /* 继续走 execCommand 兜底 */ }
    try {
      const ta = el("textarea");
      ta.value = content;
      ta.style.position = "fixed";
      ta.style.opacity = "0";
      document.body.appendChild(ta);
      ta.select();
      const ok = document.execCommand("copy");
      ta.remove();
      return ok;
    } catch (e) {
      return false;
    }
  }

  /* ===================== CSV 解析 / 生成 ===================== */

  /** 解析 CSV 文本为二维数组，支持双引号包裹、内嵌逗号与转义引号 */
  function parseCsv(text) {
    const rows = [];
    let row = [], cell = "", inQuote = false;
    const s = String(text || "").replace(/^\ufeff/, "");

    for (let i = 0; i < s.length; i++) {
      const c = s[i];
      if (inQuote) {
        if (c === '"') {
          if (s[i + 1] === '"') { cell += '"'; i++; }
          else inQuote = false;
        } else cell += c;
      } else if (c === '"') {
        inQuote = true;
      } else if (c === ",") {
        row.push(cell); cell = "";
      } else if (c === "\n") {
        row.push(cell); cell = "";
        rows.push(row); row = [];
      } else if (c === "\r") {
        /* 忽略，等待 \n */
      } else {
        cell += c;
      }
    }
    if (cell.length > 0 || row.length > 0) { row.push(cell); rows.push(row); }
    return rows.filter((r) => r.length && !(r.length === 1 && trim(r[0]) === ""));
  }

  function csvCell(v) {
    const s = String(v == null ? "" : v);
    return /[",\r\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
  }

  function buildCsv(header, rows) {
    const lines = [header.map(csvCell).join(",")];
    for (const r of rows) lines.push(header.map((h) => csvCell(r[h])).join(","));
    return lines.join("\r\n");
  }

  /* ===================== 序列化：state -> DatasetManifest ===================== */

  /** 输出路径形态转换 */
  function outPath(p) {
    p = trim(p);
    if (!p) return "";
    if (state.useRelativePath && state.baseDir) return PathUtil.toRelative(p, state.baseDir);
    return p;
  }

  /** 当前参与序列化的数据集（单组学模式只取第一条） */
  function effectiveDatasets() {
    return state.mode === "single" ? state.datasets.slice(0, 1) : state.datasets;
  }

  /** 宽表列定义：始终派生自 datasets[].id，不冗余存储 */
  function alignColumns() {
    const seen = new Set();
    const cols = [];
    for (const d of effectiveDatasets()) {
      const id = trim(d.id);
      if (id && !seen.has(id.toLowerCase())) { seen.add(id.toLowerCase()); cols.push(id); }
    }
    return cols;
  }

  /**
   * 纯函数：把 state 序列化为 DatasetManifest 契约对象。
   * 空字段一律剔除，保持产物整洁（后端允许这些字段为空）。
   */
  function buildManifest() {
    const manifest = { datasets: [] };

    for (const d of effectiveDatasets()) {
      const entry = {};
      const id = trim(d.id);
      if (id) entry.id = id;
      if (trim(d.type)) entry.type = trim(d.type);
      if (trim(d.label)) entry.label = trim(d.label);
      if (trim(d.expression)) entry.expression = outPath(d.expression);
      if (trim(d.annotation)) entry.annotation = outPath(d.annotation);
      if (trim(d.sampleinfo)) entry.sampleinfo = outPath(d.sampleinfo);
      if (trim(d.unit)) entry.unit = trim(d.unit);
      manifest.datasets.push(entry);
    }

    const a = state.alignment;
    if (a.kind === "file" && trim(a.mappingFile)) {
      manifest.sample_alignment = { mapping_file: outPath(a.mappingFile) };
    } else if ((a.kind === "inline" || a.kind === "extract") && a.rows.length) {
      const cols = alignColumns();
      const rows = [];
      for (const r of a.rows) {
        const o = {};
        o[SUBJECT_ID] = trim(r[SUBJECT_ID]);
        // 只投影当前存在的数据集 id，孤儿键保留在 state 中但不序列化
        for (const c of cols) o[c] = trim(r[c]);
        // 整行全空则跳过
        if (Object.keys(o).some((k) => o[k] !== "")) rows.push(o);
      }
      if (rows.length) manifest.sample_alignment = { subject_map: rows };
    }
    // kind === 'none' 时整个节点不写入

    return manifest;
  }

  function manifestJson() {
    return JSON.stringify(buildManifest(), null, 2);
  }

  /* ===================== 校验：同构复刻 DatasetManifest.Validate ===================== */

  /**
   * 返回 [{path, level, message}]。
   * level: 'error' 阻断保存；'warn' 仅提示。
   * 「文件是否存在」不在此处判定（需文件系统访问），由宿主异步探测后以 warn 呈现。
   */
  function validate() {
    const issues = [];
    const list = effectiveDatasets();

    if (!list.length) {
      issues.push({ path: "datasets", level: "error", message: "清单未声明任何数据集（datasets 数组为空）。" });
      return issues;
    }

    const seen = new Map();   // lower(id) -> 首次出现的索引
    list.forEach((d, i) => {
      const id = trim(d.id);
      if (!id) {
        issues.push({ path: `datasets[${i}].id`, level: "error", message: `datasets[${i}] 缺少必填的 id 字段。` });
      } else {
        const key = id.toLowerCase();     // StringComparer.OrdinalIgnoreCase
        if (seen.has(key)) {
          issues.push({
            path: `datasets[${i}].id`, level: "error",
            message: `datasets[${i}] 使用了重复的 id '${id}'，该 id 已由 datasets[${seen.get(key)}] 声明。`,
          });
        } else {
          seen.set(key, i);
        }
      }

      if (!trim(d.expression)) {
        issues.push({ path: `datasets[${i}].expression`, level: "error", message: `datasets[${i}] 缺少必填的 expression 表达矩阵路径。` });
      } else if (d.fileState[trim(d.expression)] === "miss") {
        issues.push({ path: `datasets[${i}].expression`, level: "warn", message: `datasets[${i}] 的 expression 文件在本地未找到。` });
      }

      ["annotation", "sampleinfo"].forEach((k) => {
        const p = trim(d[k]);
        if (p && d.fileState[p] === "miss") {
          issues.push({ path: `datasets[${i}].${k}`, level: "warn", message: `datasets[${i}] 的 ${k} 文件在本地未找到。` });
        }
      });
    });

    // sample_alignment：mapping_file 与 subject_map 互斥
    const a = state.alignment;
    if (a.kind === "file") {
      if (!trim(a.mappingFile)) {
        issues.push({ path: "sample_alignment.mapping_file", level: "error", message: "已选择「引用 CSV」但未指定 mapping_file 路径。" });
      }
    } else if (a.kind === "inline" || a.kind === "extract") {
      const cols = alignColumns();
      a.rows.forEach((r, i) => {
        const has = Object.keys(r).some((k) => trim(r[k]) !== "");
        if (!has) {
          issues.push({ path: `sample_alignment.subject_map[${i}]`, level: "error", message: `subject_map[${i}] 为空行，请填写或删除。` });
          return;
        }
        if (!trim(r[SUBJECT_ID])) {
          issues.push({ path: `sample_alignment.subject_map[${i}].${SUBJECT_ID}`, level: "error", message: `subject_map[${i}] 缺少必需的 ${SUBJECT_ID} 键。` });
        }
        cols.forEach((c) => {
          if (!trim(r[c])) {
            issues.push({ path: `sample_alignment.subject_map[${i}].${c}`, level: "warn", message: `subject_map[${i}] 的 '${c}' 列为空，该组学在此受试者上将无法配对。` });
          }
        });
      });
      if (a.rows.length > MAX_INLINE_ROWS) {
        issues.push({ path: "sample_alignment.subject_map", level: "warn", message: `内联行数为 ${a.rows.length}，超过 ${MAX_INLINE_ROWS} 行建议改用 mapping_file 引用外部 CSV。` });
      }
    }

    if (state.useRelativePath && !trim(state.baseDir)) {
      issues.push({ path: "baseDir", level: "warn", message: "已启用相对路径输出，但尚未设置清单文件基准目录，当前将按绝对路径输出。" });
    }

    return issues;
  }

  const hasError = () => state.errors.some((e) => e.level === "error");

  /* ===================== 状态更新入口 ===================== */

  let renderScheduled = false;

  function setState(patch, opts) {
    if (patch) Object.assign(state, patch);
    state.errors = validate();
    opts = opts || {};
    if (opts.silent) return;

    if (!renderScheduled) {
      renderScheduled = true;
      requestAnimationFrame(() => {
        renderScheduled = false;
        render(opts.scope);
      });
    }
    schedulePreview();
    saveDraft();
  }

  /* ===================== 渲染 ===================== */

  function activeEntry() {
    if (!state.datasets.length) return null;
    const i = Math.min(Math.max(state.activeIndex, 0), state.datasets.length - 1);
    state.activeIndex = i;
    return state.datasets[i];
  }

  function render(scope) {
    document.getElementById("app").classList.toggle("mode-single", state.mode === "single");
    $$("#modeSwitch button").forEach((b) => b.classList.toggle("active", b.dataset.mode === state.mode));

    if (!scope || scope === "all" || scope === "sidebar") renderSidebar();
    if (!scope || scope === "all" || scope === "form") { renderBasic(); renderPaths(); }
    if (!scope || scope === "all" || scope === "align") renderAlignment();
    renderValidation();
    renderTopic();
  }

  function renderTopic() {
    const n = PathUtil.fileName(state.manifestPath) || "未命名";
    const count = effectiveDatasets().length;
    $("#topicLine").textContent = `${n} · ${state.mode === "single" ? "单组学" : "多组学"} · ${count} 个数据集`;
  }

  /* ---------- 侧栏 ---------- */

  function renderSidebar() {
    const host = $("#datasetList");
    host.innerHTML = "";
    const kw = trim(state.filter).toLowerCase();

    let shown = 0;
    state.datasets.forEach((d, i) => {
      const hay = (d.id + " " + d.label + " " + d.type).toLowerCase();
      if (kw && hay.indexOf(kw) < 0) return;
      shown++;

      const item = el("div", "doc-item" + (i === state.activeIndex ? " active" : ""));
      item.dataset.index = String(i);
      item.innerHTML =
        `<div class="fname">${esc(d.id || "(未命名 id)")}</div>` +
        `<div class="title">${esc(d.label || "未命名数据集")}</div>` +
        `<div class="src">${esc(d.type || "未指定类型")}</div>`;

      const ops = el("div", "row-ops");
      ops.appendChild(iconBtn("up", "上移", i === 0,
        '<polyline points="18 15 12 9 6 15"/>'));
      ops.appendChild(iconBtn("down", "下移", i === state.datasets.length - 1,
        '<polyline points="6 9 12 15 18 9"/>'));
      ops.appendChild(iconBtn("dup", "复制", false,
        '<rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>'));
      const del = iconBtn("del", "删除", state.datasets.length <= 1,
        '<polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/>');
      del.classList.add("danger");
      ops.appendChild(del);
      item.appendChild(ops);

      host.appendChild(item);
    });

    if (!shown) {
      host.appendChild(el("div", "empty",
        `<div class="big">🔍</div><div>${kw ? "没有匹配的数据集" : "尚未添加数据集"}</div>`));
    }
  }

  function iconBtn(act, title, disabled, svgInner) {
    const b = el("button", "icon-btn",
      `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${svgInner}</svg>`);
    b.type = "button";
    b.title = title;
    b.dataset.act = act;
    if (disabled) b.disabled = true;
    return b;
  }

  /* ---------- 基本信息卡 ---------- */

  function errFor(path) {
    return state.errors.find((e) => e.path === path && e.level === "error");
  }

  function renderBasic() {
    const d = activeEntry();
    const host = $("#basicBody");
    if (!d) { host.innerHTML = `<div class="empty"><div class="big">📦</div><div>请先添加一个数据集</div></div>`; return; }

    const i = state.activeIndex;
    const idErr = errFor(`datasets[${i}].id`);

    host.innerHTML =
      `<div class="sub-note">` +
      (state.mode === "single"
        ? `单组学模式：将生成仅含 1 个元素的 <code>datasets</code> 数组，可直接作为 <code>--dataset</code> 参数使用。`
        : `多组学模式：每个数据集的 <code>id</code> 必须唯一（大小写不敏感），它同时会作为样本对齐宽表的列名。`) +
      `</div>` +
      `<div class="grid-2">` +

      `<div class="field${idErr ? " has-error" : ""}">` +
      `<label><span class="req"></span>id<span class="hint">组学唯一标识 / 宽表列名</span></label>` +
      `<input type="text" class="input mono" data-fld="id" value="${esc(d.id)}" placeholder="例如 rna / prot / metab" spellcheck="false" />` +
      (idErr ? `<div class="field-err">${esc(idErr.message)}</div>` : "") +
      `</div>` +

      `<div class="field">` +
      `<label>type<span class="hint">组学类型</span></label>` +
      `<input type="text" class="input" data-fld="type" value="${esc(d.type)}" list="omicsTypeList" placeholder="transcriptome" spellcheck="false" />` +
      `</div>` +

      `<div class="field">` +
      `<label>label<span class="hint">中文展示名称</span></label>` +
      `<input type="text" class="input" data-fld="label" value="${esc(d.label)}" placeholder="例如 肝脏转录组" />` +
      `</div>` +

      `<div class="field">` +
      `<label>unit<span class="hint">数据单位</span></label>` +
      `<input type="text" class="input" data-fld="unit" value="${esc(d.unit)}" placeholder="例如 TPM" spellcheck="false" />` +
      `<div class="suggest-row">` +
      UNIT_SUGGESTIONS.map((u) => `<span class="tag" data-unit="${esc(u)}">${esc(u)}</span>`).join("") +
      `</div>` +
      `</div>` +

      `</div>` +
      `<datalist id="omicsTypeList">` +
      OMICS_TYPES.map((t) => `<option value="${esc(t.value)}">${esc(t.label)}</option>`).join("") +
      `</datalist>`;
  }

  /* ---------- 文件路径卡 ---------- */

  const PATH_FIELDS = [
    { key: "expression", label: "expression", hint: "表达矩阵 CSV（行=分子，列=样本）", required: true },
    { key: "annotation", label: "annotation", hint: "分子注释表 CSV ['id','type','name','kegg']", required: false },
    { key: "sampleinfo", label: "sampleinfo", hint: "样本元数据 CSV ['id','sample_name','sample_info']", required: false },
  ];

  function renderPaths() {
    const d = activeEntry();
    const host = $("#pathBody");
    if (!d) { host.innerHTML = ""; return; }
    const i = state.activeIndex;

    let html = `<div class="stack">`;
    for (const f of PATH_FIELDS) {
      const val = d[f.key] || "";
      const e = errFor(`datasets[${i}].${f.key}`);
      const st = val ? (d.fileState[trim(val)] || "") : "";
      const stCls = st === "ok" ? "ok" : (st === "miss" ? "miss" : "");
      const stTxt = !val ? "" : (st === "ok" ? "文件存在" : (st === "miss" ? "文件未找到" : "未验证"));

      html +=
        `<div class="field${e ? " has-error" : ""}" data-pathfield="${f.key}">` +
        `<label>${f.required ? '<span class="req"></span>' : ""}${esc(f.label)}<span class="hint">${esc(f.hint)}</span></label>` +
        `<div class="path-row">` +
        `<input type="text" class="input mono" data-fld="${f.key}" value="${esc(val)}" placeholder="请选择或输入 CSV 文件路径" spellcheck="false" />` +
        `<button type="button" class="btn btn-mini" data-browse="${f.key}">浏览…</button>` +
        `<button type="button" class="btn btn-mini" data-clear="${f.key}" title="清除">✕</button>` +
        `</div>` +
        `<div class="path-meta">` +
        (val ? `<span class="state-dot ${stCls}"></span><span>${esc(stTxt)}</span><span class="fname">${esc(PathUtil.fileName(val))}</span>` : `<span class="dim">尚未选择文件</span>`) +
        `</div>` +
        (e ? `<div class="field-err">${esc(e.message)}</div>` : "") +
        `</div>`;
    }
    html += `</div><hr class="field-sep" />`;

    html +=
      `<div class="switch-row">` +
      `<label><input type="checkbox" id="relPathChk" ${state.useRelativePath ? "checked" : ""} />输出相对路径</label>` +
      `<span class="dim">基准目录：</span>` +
      `<input type="text" class="input mono" id="baseDirInput" style="flex:1 1 240px;min-width:180px" value="${esc(state.baseDir)}" placeholder="清单 JSON 文件所在目录" spellcheck="false" />` +
      `<button type="button" class="btn btn-mini" id="pickBaseDirBtn">选择…</button>` +
      `<button type="button" class="btn btn-mini" id="verifyFilesBtn">校验文件存在性</button>` +
      `</div>`;

    host.innerHTML = html;
  }

  /* ---------- 样本对齐卡 ---------- */

  const ALIGN_KINDS = [
    { k: "none", t: "省略" },
    { k: "file", t: "引用 CSV" },
    { k: "inline", t: "内联编辑" },
    { k: "extract", t: "从矩阵提取" },
  ];

  function renderAlignment() {
    const host = $("#alignmentBody");
    const a = state.alignment;

    let html =
      `<div class="segmented segmented--block" id="alignSwitch" style="margin-bottom:14px">` +
      ALIGN_KINDS.map((x) => `<button type="button" data-kind="${x.k}"${a.kind === x.k ? ' class="active"' : ""}>${x.t}</button>`).join("") +
      `</div>`;

    if (a.kind === "none") {
      html +=
        `<div class="sub-note">不写入 <code>sample_alignment</code> 节点。适用于各组学的样本 ID 已完全一致的情形，` +
        `分析流程将按同名一一匹配。</div>`;
    } else if (a.kind === "file") {
      const e = errFor("sample_alignment.mapping_file");
      html +=
        `<div class="sub-note">引用一个现成的宽表 CSV：首列为 <code>${SUBJECT_ID}</code>，其余列名需与各数据集的 <code>id</code> 对应。</div>` +
        `<div class="field${e ? " has-error" : ""}">` +
        `<label>mapping_file<span class="hint">样本对齐宽表 CSV</span></label>` +
        `<div class="path-row">` +
        `<input type="text" class="input mono" id="mappingFileInput" value="${esc(a.mappingFile)}" placeholder="请选择 subject_map.csv" spellcheck="false" />` +
        `<button type="button" class="btn btn-mini" id="browseMappingBtn">浏览…</button>` +
        `<button type="button" class="btn btn-mini" id="importMappingBtn" title="读取该 CSV 并转为内联编辑">导入为内联</button>` +
        `</div>` +
        (a.mappingFile ? `<div class="path-meta"><span class="fname">${esc(PathUtil.fileName(a.mappingFile))}</span></div>` : "") +
        (e ? `<div class="field-err">${esc(e.message)}</div>` : "") +
        `</div>`;
    } else if (a.kind === "extract") {
      html += renderExtractPanel();
    } else {
      html += renderInlineTable();
    }

    host.innerHTML = html;
  }

  function renderExtractPanel() {
    const list = effectiveDatasets();
    let html =
      `<div class="sub-note">读取各数据集 <code>expression</code> 矩阵的表头，抽取样本列名作为候选。` +
      `随后可「按同名自动配对」快速生成对齐宽表。</div>` +
      `<div class="toolbar">` +
      `<button type="button" class="btn btn-mini" id="extractAllBtn">读取全部表头</button>` +
      `<button type="button" class="btn btn-mini" id="autoPairBtn">按同名自动配对</button>` +
      `<button type="button" class="btn btn-mini" id="gotoInlineBtn">前往内联编辑</button>` +
      `<span class="spacer"></span>` +
      `<span class="count">${a_rowCount()} 行已生成</span>` +
      `</div><div class="sample-pool">`;

    for (const d of list) {
      const names = d.sampleNames || [];
      html +=
        `<div class="pool-item">` +
        `<div class="pool-head">` +
        `<span class="pid">${esc(d.id || "(未命名)")}</span>` +
        `<span class="dim">${esc(d.label || "")}</span>` +
        `<span class="spacer"></span>` +
        `<span class="count">${names.length} 个样本</span>` +
        `<button type="button" class="btn btn-mini" data-extract="${esc(d.id)}">读取表头</button>` +
        `</div>` +
        (names.length
          ? `<div class="pool-names">${names.map((n) => `<span class="tag">${esc(n)}</span>`).join("")}</div>`
          : `<div class="dim" style="font-size:12px">尚未读取。${trim(d.expression) ? "" : "请先设置 expression 路径。"}</div>`) +
        `</div>`;
    }
    html += `</div>`;
    return html;
  }

  function a_rowCount() { return state.alignment.rows.length; }

  function renderInlineTable() {
    const cols = alignColumns();
    const rows = state.alignment.rows;

    let html =
      `<div class="sub-note">内联宽表将写入 <code>subject_map</code>。首列 <code>${SUBJECT_ID}</code> 为受试者标识，` +
      `其余列自动跟随各数据集的 <code>id</code>；单元格填写该组学中对应的样本 ID。</div>` +
      `<div class="toolbar">` +
      `<button type="button" class="btn btn-mini" id="addRowBtn">+ 添加行</button>` +
      `<button type="button" class="btn btn-mini" id="pasteRowsBtn">批量粘贴</button>` +
      `<button type="button" class="btn btn-mini" id="autoPairBtn2">按同名自动配对</button>` +
      `<button type="button" class="btn btn-mini" id="clearRowsBtn">清空</button>` +
      `<button type="button" class="btn btn-mini" id="exportCsvBtn">导出 CSV</button>` +
      `<span class="spacer"></span>` +
      `<span class="count">${rows.length} 行 × ${cols.length + 1} 列</span>` +
      `</div>`;

    if (!cols.length) {
      return html + `<div class="empty"><div class="big">🧬</div><div>请先为数据集填写 id，宽表列会自动生成。</div></div>`;
    }

    html +=
      `<div class="align-wrap"><table class="align-table" id="alignTable"><thead><tr>` +
      `<th class="rownum">#</th>` +
      `<th class="locked"><span class="col-id">${esc(SUBJECT_ID)}</span><span class="col-sub">🔒 受试者标识</span></th>` +
      cols.map((c) => {
        const d = effectiveDatasets().find((x) => trim(x.id) === c);
        return `<th><span class="col-id">${esc(c)}</span><span class="col-sub">${esc((d && d.label) || "")}</span></th>`;
      }).join("") +
      `<th class="ops"></th>` +
      `</tr></thead><tbody>`;

    if (!rows.length) {
      html += `<tr><td class="rownum">–</td><td colspan="${cols.length + 2}" style="padding:14px" class="dim">暂无数据行，点击「+ 添加行」或「批量粘贴」开始。</td></tr>`;
    } else {
      rows.forEach((r, ri) => {
        html += `<tr data-row="${ri}">` + `<td class="rownum">${ri + 1}</td>`;
        const sv = trim(r[SUBJECT_ID]);
        html += `<td class="cell locked-col${sv ? "" : " cell-empty"}">` +
          `<input class="cell-input" data-row="${ri}" data-col="${esc(SUBJECT_ID)}" value="${esc(r[SUBJECT_ID] || "")}" spellcheck="false" /></td>`;
        for (const c of cols) {
          const v = trim(r[c]);
          html += `<td class="cell${v ? "" : " cell-empty"}">` +
            `<input class="cell-input" data-row="${ri}" data-col="${esc(c)}" value="${esc(r[c] || "")}" spellcheck="false" list="pool-${esc(c)}" /></td>`;
        }
        html += `<td class="ops"><button type="button" class="icon-btn danger" data-delrow="${ri}" title="删除该行">` +
          `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>` +
          `</button></td></tr>`;
      });
    }

    html += `</tbody></table></div>`;

    // 各列样本名候选
    for (const c of cols) {
      const d = effectiveDatasets().find((x) => trim(x.id) === c);
      const names = (d && d.sampleNames) || [];
      if (names.length) {
        html += `<datalist id="pool-${esc(c)}">` + names.map((n) => `<option value="${esc(n)}"></option>`).join("") + `</datalist>`;
      }
    }
    return html;
  }

  /* ---------- 校验结果卡 ---------- */

  function renderValidation() {
    const host = $("#validationBody");
    const card = $("#validationCard");
    const errs = state.errors.filter((e) => e.level === "error");
    const warns = state.errors.filter((e) => e.level === "warn");

    card.className = "card " + (errs.length ? "card--orange" : (warns.length ? "card--teal" : "card--green"));

    let html = "";
    if (!errs.length) {
      html +=
        `<div class="ok-line">` +
        `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round">` +
        `<path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><polyline points="22 4 12 14.01 9 11.01"/></svg>` +
        `<span>校验通过，可以保存${warns.length ? `（另有 ${warns.length} 条提示）` : ""}。</span></div>`;
    }

    const all = errs.concat(warns);
    if (all.length) {
      html += `<div class="issue-list" ${errs.length ? "" : 'style="margin-top:12px"'}>` +
        all.map((e) =>
          `<div class="issue ${e.level}">` +
          `<span class="ipath" data-goto="${esc(e.path)}">${esc(e.path)}</span>` +
          `<span>${esc(e.message)}</span></div>`).join("") +
        `</div>`;
    }

    host.innerHTML = html;
    $("#saveBtn").disabled = errs.length > 0;
  }

  /* ---------- JSON 预览 ---------- */

  function highlightJson(json) {
    return esc(json).replace(
      /("(\\u[a-zA-Z0-9]{4}|\\[^u]|[^\\"])*"(\s*:)?|\b(true|false|null)\b|-?\d+(?:\.\d*)?(?:[eE][+\-]?\d+)?)/g,
      (m) => {
        let cls = "tok-num";
        if (/^"/.test(m)) cls = /:$/.test(m) ? "tok-key" : "tok-str";
        else if (/true|false/.test(m)) cls = "tok-bool";
        else if (/null/.test(m)) cls = "tok-null";
        return `<span class="${cls}">${m}</span>`;
      });
  }

  function renderPreview() {
    const panel = $("#previewPanel");
    if (!panel.classList.contains("open")) return;
    const json = manifestJson();
    $("#previewCode").innerHTML = highlightJson(json);
    $("#previewStat").textContent = `${json.length} 字符 · ${json.split("\n").length} 行`;
  }

  const schedulePreview = debounce(renderPreview, 150);

  /* ===================== 草稿持久化 ===================== */

  const saveDraft = debounce(function () {
    try {
      localStorage.setItem(DRAFT_KEY, JSON.stringify({
        mode: state.mode, datasets: state.datasets, alignment: state.alignment,
        baseDir: state.baseDir, useRelativePath: state.useRelativePath,
        manifestPath: state.manifestPath, activeIndex: state.activeIndex,
      }));
    } catch (e) { /* 容量超限静默失败，不影响主流程 */ }
  }, 400);

  function loadDraft() {
    try {
      const raw = localStorage.getItem(DRAFT_KEY);
      if (!raw) return false;
      const d = JSON.parse(raw);
      if (!d || !Array.isArray(d.datasets) || !d.datasets.length) return false;
      state.mode = d.mode === "single" ? "single" : "multi";
      state.datasets = d.datasets.map((x) => newEntry(x));
      state.alignment = Object.assign({ kind: "none", mappingFile: "", rows: [] }, d.alignment || {});
      state.baseDir = d.baseDir || "";
      state.useRelativePath = d.useRelativePath !== false;
      state.manifestPath = d.manifestPath || "";
      state.activeIndex = Math.min(d.activeIndex || 0, state.datasets.length - 1);
      return true;
    } catch (e) { return false; }
  }

  /* ===================== 载入已有 JSON ===================== */

  function loadManifestObject(obj, srcPath) {
    if (!obj || typeof obj !== "object") throw new Error("JSON 根节点不是对象。");
    if (!Array.isArray(obj.datasets)) throw new Error("缺少 datasets 数组。");
    if (!obj.datasets.length) throw new Error("datasets 数组为空。");

    const baseDir = srcPath ? PathUtil.dirName(srcPath) : state.baseDir;
    let sawRelative = false;

    const datasets = obj.datasets.map((raw) => {
      const e = newEntry();
      e.id = trim(raw && raw.id);
      e.type = trim(raw && raw.type);
      e.label = trim(raw && raw.label);
      e.unit = trim(raw && raw.unit);
      ["expression", "annotation", "sampleinfo"].forEach((k) => {
        const p = trim(raw && raw[k]);
        if (!p) { e[k] = ""; return; }
        if (!PathUtil.isAbsolute(p)) {
          sawRelative = true;
          e[k] = baseDir ? PathUtil.toAbsolute(p, baseDir) : p;
        } else {
          e[k] = PathUtil.normalizeSlash(p);
        }
      });
      return e;
    });

    const alignment = { kind: "none", mappingFile: "", rows: [] };
    const sa = obj.sample_alignment;
    if (sa && typeof sa === "object") {
      const mf = trim(sa.mapping_file);
      const sm = sa.subject_map;
      if (mf && Array.isArray(sm) && sm.length) {
        throw new Error("sample_alignment 同时声明了 mapping_file 与 subject_map，请只保留其中一个。");
      }
      if (mf) {
        alignment.kind = "file";
        alignment.mappingFile = PathUtil.isAbsolute(mf)
          ? PathUtil.normalizeSlash(mf)
          : (baseDir ? PathUtil.toAbsolute(mf, baseDir) : mf);
        if (!PathUtil.isAbsolute(mf)) sawRelative = true;
      } else if (Array.isArray(sm) && sm.length) {
        alignment.kind = "inline";
        alignment.rows = sm.map((r) => {
          const o = {};
          if (r && typeof r === "object") {
            for (const k of Object.keys(r)) {
              // subject_id 键大小写不敏感，统一规范化
              o[k.toLowerCase() === SUBJECT_ID ? SUBJECT_ID : k] = String(r[k] == null ? "" : r[k]);
            }
          }
          return o;
        });
      }
    }

    state.datasets = datasets;
    state.alignment = alignment;
    state.activeIndex = 0;
    state.mode = datasets.length > 1 ? "multi" : "single";
    if (srcPath) { state.manifestPath = srcPath; state.baseDir = baseDir; }
    if (sawRelative) state.useRelativePath = true;

    setState(null, { scope: "all" });
    return datasets.length;
  }

  /* ===================== 保存与导出 ===================== */

  async function doSaveManifest() {
    if (hasError()) { toast("存在校验错误，请先修正后再保存。", "err"); return false; }
    const json = manifestJson();

    if (HostBridge.available) {
      const p = await HostBridge.saveFile({
        title: "保存数据集定义文件",
        filter: "JSON 文件|*.json|所有文件|*.*",
        defaultName: PathUtil.fileName(state.manifestPath) || "dataset.json",
      });
      if (p) {
        // 基准目录随保存位置更新后需重新序列化，保证相对路径正确
        state.manifestPath = p;
        state.baseDir = PathUtil.dirName(p);
        setState(null, { silent: true });
        const written = await HostBridge.writeText(p, manifestJson());
        if (written) {
          setState(null, { scope: "all" });
          toast("已保存到 " + PathUtil.fileName(p), "ok");
          return true;
        }
        toast("宿主写入失败，已改为浏览器下载。", "err");
      } else {
        return false;   // 用户取消
      }
    }

    if (downloadText("dataset.json", json, "application/json")) {
      toast("已通过浏览器下载 dataset.json", "ok");
      return true;
    }
    const ok = await copyText(json);
    toast(ok ? "已复制 JSON 到剪贴板" : "保存失败，请手动复制预览内容", ok ? "ok" : "err");
    return ok;
  }

  async function doExportAlignCsv() {
    const cols = alignColumns();
    const rows = state.alignment.rows;
    if (!rows.length) { toast("宽表为空，无可导出内容。", "err"); return; }

    const header = [SUBJECT_ID].concat(cols);
    const csv = buildCsv(header, rows);
    const defName = "subject_map.csv";

    if (HostBridge.available) {
      const p = await HostBridge.saveFile({
        title: "导出样本对齐宽表", filter: "CSV 文件|*.csv|所有文件|*.*", defaultName: defName,
      });
      if (!p) return;
      const written = await HostBridge.writeText(p, csv);
      if (written) {
        // 导出后自动切为 mapping_file 引用形式（二者互斥）
        state.alignment.kind = "file";
        state.alignment.mappingFile = p;
        setState(null, { scope: "align" });
        toast("已导出并切换为 mapping_file 引用", "ok");
        return;
      }
      toast("宿主写入失败，已改为浏览器下载。", "err");
    }
    downloadText(defName, csv, "text/csv");
    toast("已通过浏览器下载 " + defName, "ok");
  }

  /* ===================== 样本名提取与配对 ===================== */

  async function extractHeader(entry) {
    const p = trim(entry.expression);
    if (!p) { toast(`数据集 '${entry.id || "?"}' 尚未设置 expression 路径。`, "err"); return; }

    let cols = null;
    if (HostBridge.available) cols = await HostBridge.readCsvHeader(p);

    if (!cols) {
      // 降级：让用户在本地挑选同一个 CSV，前端自行读取表头
      const f = await pickLocalFile(".csv,.tsv,.txt");
      if (!f) return;
      const text = await readFileText(f);
      const firstLine = text.split(/\r?\n/)[0] || "";
      const rows = parseCsv(firstLine);
      cols = rows.length ? rows[0] : [];
    }

    // 首列通常是分子 ID 列，其余为样本列
    entry.sampleNames = cols.slice(1).map(trim).filter(Boolean);
    setState(null, { scope: "align" });
    toast(`'${entry.id}' 提取到 ${entry.sampleNames.length} 个样本名`, "ok");
  }

  /** 按同名自动配对：以样本名交集/并集生成宽表行 */
  function autoPair() {
    const list = effectiveDatasets().filter((d) => trim(d.id));
    if (!list.length) { toast("请先为数据集填写 id。", "err"); return; }

    const pools = list.map((d) => ({ id: trim(d.id), names: (d.sampleNames || []).slice() }));
    if (!pools.some((p) => p.names.length)) { toast("尚无样本名，请先读取表头。", "err"); return; }

    // 以样本名（大小写不敏感）为受试者键做并集
    const order = [];
    const index = new Map();
    for (const p of pools) {
      for (const n of p.names) {
        const k = n.toLowerCase();
        if (!index.has(k)) { index.set(k, { subject: n, hit: {} }); order.push(k); }
        index.get(k).hit[p.id] = n;
      }
    }

    const rows = order.map((k) => {
      const it = index.get(k);
      const r = {};
      r[SUBJECT_ID] = it.subject;
      for (const p of pools) r[p.id] = it.hit[p.id] || "";
      return r;
    });

    state.alignment.rows = rows;
    state.alignment.kind = "inline";
    setState(null, { scope: "align" });
    toast(`已生成 ${rows.length} 行对齐记录`, "ok");
  }

  function pasteRows() {
    const text = window.prompt(
      `粘贴宽表文本（支持制表符 / 逗号分隔，首行可为表头）：\n列顺序为 ${[SUBJECT_ID].concat(alignColumns()).join(", ")}`);
    if (!text) return;

    const cols = alignColumns();
    const header = [SUBJECT_ID].concat(cols);
    const lines = String(text).split(/\r?\n/).filter((l) => trim(l) !== "");
    if (!lines.length) return;

    const split = (l) => (l.indexOf("\t") >= 0 ? l.split("\t") : parseCsv(l)[0] || []);

    // 首行若与表头高度重合则视为表头跳过
    const first = split(lines[0]).map((s) => trim(s).toLowerCase());
    const isHeader = first.length > 0 && first[0] === SUBJECT_ID;
    const body = isHeader ? lines.slice(1) : lines;

    const rows = body.map((l) => {
      const cells = split(l);
      const r = {};
      header.forEach((h, i) => { r[h] = trim(cells[i] || ""); });
      return r;
    });

    state.alignment.rows = state.alignment.rows.concat(rows);
    state.alignment.kind = "inline";
    setState(null, { scope: "align" });
    toast(`已导入 ${rows.length} 行`, "ok");
  }

  /* ===================== 文件存在性探测 ===================== */

  async function verifyFiles() {
    if (!HostBridge.available) { toast("宿主不可用，无法校验文件存在性。", "err"); return; }
    let checked = 0, missing = 0;
    for (const d of state.datasets) {
      for (const k of ["expression", "annotation", "sampleinfo"]) {
        const p = trim(d[k]);
        if (!p) continue;
        const abs = PathUtil.isAbsolute(p) ? p : PathUtil.toAbsolute(p, state.baseDir);
        const ex = await HostBridge.fileExists(abs);
        if (ex === null) continue;      // 宿主未实现该方法，保持「未验证」
        d.fileState[p] = ex ? "ok" : "miss";
        checked++;
        if (!ex) missing++;
      }
    }
    setState(null, { scope: "form" });
    toast(checked ? `已校验 ${checked} 个文件，${missing} 个未找到` : "没有可校验的路径", missing ? "err" : "ok");
  }

  /* ===================== 事件绑定 ===================== */

  function bindEvents() {

    $("#themeBtn").addEventListener("click", () => toggleTheme());

    // 模式切换
    $("#modeSwitch").addEventListener("click", (ev) => {
      const b = ev.target.closest("button[data-mode]");
      if (b) setMode(b.dataset.mode);
    });

    // 侧栏筛选
    $("#searchInput").addEventListener("input", (ev) => {
      state.filter = ev.target.value;
      renderSidebar();
    });

    // 添加数据集
    $("#addDatasetBtn").addEventListener("click", () => {
      const n = state.datasets.length + 1;
      state.datasets.push(newEntry({ id: "omics" + n }));
      state.activeIndex = state.datasets.length - 1;
      setState(null, { scope: "all" });
    });

    // 侧栏列表：选中 / 行操作
    $("#datasetList").addEventListener("click", (ev) => {
      const opBtn = ev.target.closest("button[data-act]");
      const item = ev.target.closest(".doc-item");
      if (!item) return;
      const i = parseInt(item.dataset.index, 10);

      if (opBtn) {
        ev.stopPropagation();
        const act = opBtn.dataset.act;
        if (act === "up" && i > 0) {
          const t = state.datasets[i - 1]; state.datasets[i - 1] = state.datasets[i]; state.datasets[i] = t;
          state.activeIndex = i - 1;
        } else if (act === "down" && i < state.datasets.length - 1) {
          const t = state.datasets[i + 1]; state.datasets[i + 1] = state.datasets[i]; state.datasets[i] = t;
          state.activeIndex = i + 1;
        } else if (act === "dup") {
          const c = newEntry(JSON.parse(JSON.stringify(state.datasets[i])));
          c.id = c.id ? c.id + "_copy" : "";
          state.datasets.splice(i + 1, 0, c);
          state.activeIndex = i + 1;
        } else if (act === "del" && state.datasets.length > 1) {
          state.datasets.splice(i, 1);
          if (state.activeIndex >= state.datasets.length) state.activeIndex = state.datasets.length - 1;
        }
        setState(null, { scope: "all" });
        return;
      }

      state.activeIndex = i;
      setState(null, { scope: "all" });
      closeDrawer();
    });

    // 表单输入（基本信息 + 路径），事件委托
    $("#content").addEventListener("input", (ev) => {
      const t = ev.target;
      const d = activeEntry();
      if (!d) return;

      if (t.dataset.fld) {
        const key = t.dataset.fld;
        const oldId = d.id;
        d[key] = t.value;

        if (key === "id") {
          // 数据集改名：宽表列键迁移，旧键值搬到新键
          const from = trim(oldId), to = trim(t.value);
          if (from && to && from !== to) {
            for (const r of state.alignment.rows) {
              if (Object.prototype.hasOwnProperty.call(r, from)) { r[to] = r[from]; delete r[from]; }
            }
          }
          setState(null, { scope: "all" });
        } else if (key === "expression" || key === "annotation" || key === "sampleinfo") {
          // 路径手工编辑：只做静默校验，避免每次按键都重绘输入框导致光标跳动
          setState(null, { silent: true });
          renderValidation();
          schedulePreview();
          saveDraft();
        } else {
          setState(null, { silent: true });
          renderSidebar();
          renderValidation();
          renderTopic();
          schedulePreview();
          saveDraft();
        }
        return;
      }

      if (t.id === "baseDirInput") {
        state.baseDir = t.value;
        setState(null, { silent: true });
        renderValidation();
        schedulePreview();
        saveDraft();
        return;
      }

      if (t.id === "mappingFileInput") {
        state.alignment.mappingFile = t.value;
        setState(null, { silent: true });
        renderValidation();
        schedulePreview();
        saveDraft();
        return;
      }

      // 宽表单元格
      if (t.classList.contains("cell-input")) {
        const ri = parseInt(t.dataset.row, 10);
        const col = t.dataset.col;
        if (!isNaN(ri) && state.alignment.rows[ri]) {
          state.alignment.rows[ri][col] = t.value;
          t.parentElement.classList.toggle("cell-empty", trim(t.value) === "");
          setState(null, { silent: true });
          renderValidation();
          schedulePreview();
          saveDraft();
        }
      }
    });

    $("#content").addEventListener("change", (ev) => {
      if (ev.target.id === "relPathChk") {
        state.useRelativePath = ev.target.checked;
        setState(null, { scope: "form" });
      }
    });

    // 主内容区点击：按钮族
    $("#content").addEventListener("click", async (ev) => {
      const t = ev.target;
      const d = activeEntry();

      // 单位快捷标签
      const tag = t.closest(".suggest-row .tag");
      if (tag && d) { d.unit = tag.dataset.unit; setState(null, { scope: "form" }); return; }

      // 路径浏览 / 清除
      const br = t.closest("[data-browse]");
      if (br && d) {
        const key = br.dataset.browse;
        const paths = await HostBridge.openFile({
          title: "选择 " + key + " CSV 文件", filter: "CSV 文件|*.csv|文本文件|*.txt;*.tsv|所有文件|*.*",
        });
        if (paths && paths[0]) {
          d[key] = PathUtil.normalizeSlash(paths[0]);
          if (!state.baseDir) state.baseDir = PathUtil.dirName(d[key]);
          setState(null, { scope: "form" });
        } else if (!HostBridge.available) {
          toast("宿主不可用，请直接在输入框中手工填写完整路径。", "err");
        }
        return;
      }
      const cl = t.closest("[data-clear]");
      if (cl && d) { d[cl.dataset.clear] = ""; setState(null, { scope: "form" }); return; }

      if (t.id === "pickBaseDirBtn") {
        const paths = await HostBridge.openFile({
          title: "选择清单文件所在目录（选中该目录下任意文件即可）", filter: "所有文件|*.*",
        });
        if (paths && paths[0]) { state.baseDir = PathUtil.dirName(PathUtil.normalizeSlash(paths[0])); setState(null, { scope: "form" }); }
        else if (!HostBridge.available) toast("宿主不可用，请手工填写基准目录。", "err");
        return;
      }

      if (t.id === "verifyFilesBtn") { await verifyFiles(); return; }

      // 样本对齐模式切换
      const kindBtn = t.closest("#alignSwitch button[data-kind]");
      if (kindBtn) { state.alignment.kind = kindBtn.dataset.kind; setState(null, { scope: "align" }); return; }

      if (t.id === "browseMappingBtn") {
        const paths = await HostBridge.openFile({ title: "选择样本对齐宽表 CSV", filter: "CSV 文件|*.csv|所有文件|*.*" });
        if (paths && paths[0]) { state.alignment.mappingFile = PathUtil.normalizeSlash(paths[0]); setState(null, { scope: "align" }); }
        else if (!HostBridge.available) toast("宿主不可用，请手工填写 CSV 路径。", "err");
        return;
      }

      if (t.id === "importMappingBtn") { await importMappingCsv(); return; }

      // 提取面板
      const ex = t.closest("[data-extract]");
      if (ex) {
        const entry = effectiveDatasets().find((x) => trim(x.id) === ex.dataset.extract);
        if (entry) await extractHeader(entry);
        return;
      }
      if (t.id === "extractAllBtn") {
        for (const e of effectiveDatasets()) { if (trim(e.expression)) await extractHeader(e); }
        return;
      }
      if (t.id === "autoPairBtn" || t.id === "autoPairBtn2") { autoPair(); return; }
      if (t.id === "gotoInlineBtn") { state.alignment.kind = "inline"; setState(null, { scope: "align" }); return; }

      // 宽表工具条
      if (t.id === "addRowBtn") {
        const r = {}; r[SUBJECT_ID] = "";
        for (const c of alignColumns()) r[c] = "";
        state.alignment.rows.push(r);
        setState(null, { scope: "align" });
        return;
      }
      if (t.id === "pasteRowsBtn") { pasteRows(); return; }
      if (t.id === "clearRowsBtn") {
        if (state.alignment.rows.length && window.confirm("确定清空全部对齐行？")) {
          state.alignment.rows = [];
          setState(null, { scope: "align" });
        }
        return;
      }
      if (t.id === "exportCsvBtn") { await doExportAlignCsv(); return; }

      const dr = t.closest("[data-delrow]");
      if (dr) {
        state.alignment.rows.splice(parseInt(dr.dataset.delrow, 10), 1);
        setState(null, { scope: "align" });
        return;
      }

      // 校验项定位
      const gt = t.closest("[data-goto]");
      if (gt) { gotoPath(gt.dataset.goto); return; }
    });

    // 顶栏按钮
    $("#loadBtn").addEventListener("click", doLoad);
    $("#saveBtn").addEventListener("click", () => { doSaveManifest(); });

    $("#previewBtn").addEventListener("click", () => {
      const p = $("#previewPanel");
      const open = p.classList.toggle("open");
      p.setAttribute("aria-hidden", open ? "false" : "true");
      if (open) renderPreview();
    });
    $("#closePreviewBtn").addEventListener("click", () => {
      $("#previewPanel").classList.remove("open");
      $("#previewPanel").setAttribute("aria-hidden", "true");
    });
    $("#copyJsonBtn").addEventListener("click", async () => {
      const ok = await copyText(manifestJson());
      toast(ok ? "已复制到剪贴板" : "复制失败", ok ? "ok" : "err");
    });
    $("#downloadJsonBtn").addEventListener("click", () => {
      downloadText("dataset.json", manifestJson(), "application/json");
    });

    // 抽屉（移动端）
    $("#drawerToggle").addEventListener("click", () => {
      $("#sidebar").classList.toggle("open");
      $("#scrim").classList.toggle("show");
    });
    $("#scrim").addEventListener("click", closeDrawer);
  }

  function closeDrawer() {
    $("#sidebar").classList.remove("open");
    $("#scrim").classList.remove("show");
  }

  /** 点击校验项定位到对应字段 */
  function gotoPath(path) {
    const m = /^datasets\[(\d+)\]\.(\w+)$/.exec(path);
    if (m) {
      state.activeIndex = parseInt(m[1], 10);
      setState(null, { scope: "all" });
      setTimeout(() => {
        const inp = $(`#content [data-fld="${m[2]}"]`);
        if (inp) { inp.focus(); inp.select && inp.select(); }
      }, 60);
      return;
    }
    if (path.indexOf("sample_alignment") === 0) {
      $("#alignmentCard").scrollIntoView({ behavior: "smooth", block: "start" });
      return;
    }
    if (path === "baseDir") {
      const i = $("#baseDirInput");
      if (i) { i.focus(); i.scrollIntoView({ behavior: "smooth", block: "center" }); }
    }
  }

  /* ---------- 载入 ---------- */

  async function doLoad() {
    let text = null, srcPath = "";

    if (HostBridge.available) {
      const paths = await HostBridge.openFile({
        title: "选择数据集定义文件", filter: "JSON 文件|*.json|所有文件|*.*",
      });
      if (paths && paths[0]) {
        srcPath = PathUtil.normalizeSlash(paths[0]);
        text = await HostBridge.readText(srcPath);
      } else {
        return;
      }
    }

    if (text == null) {
      const f = await pickLocalFile(".json,application/json");
      if (f) { text = await readFileText(f); srcPath = ""; }
    }
    if (text == null) {
      text = window.prompt("粘贴 dataset.json 内容：");
      if (!text) return;
    }

    try {
      const n = loadManifestObject(JSON.parse(text), srcPath);
      toast(`已载入 ${n} 个数据集`, "ok");
    } catch (e) {
      toast("载入失败：" + (e && e.message ? e.message : e), "err");
    }
  }

  async function importMappingCsv() {
    const p = trim(state.alignment.mappingFile);
    let text = null;
    if (p && HostBridge.available) text = await HostBridge.readText(p);
    if (text == null) {
      const f = await pickLocalFile(".csv,.txt,.tsv");
      if (!f) return;
      text = await readFileText(f);
    }

    const rows = parseCsv(text);
    if (rows.length < 2) { toast("CSV 内容为空或只有表头。", "err"); return; }

    const header = rows[0].map(trim);
    const si = header.findIndex((h) => h.toLowerCase() === SUBJECT_ID);
    const out = rows.slice(1).map((cells) => {
      const r = {};
      header.forEach((h, i) => {
        r[i === si ? SUBJECT_ID : h] = trim(cells[i] || "");
      });
      if (si < 0) r[SUBJECT_ID] = trim(cells[0] || "");   // 首列兜底为 subject_id
      return r;
    });

    state.alignment.rows = out;
    state.alignment.kind = "inline";
    state.alignment.mappingFile = "";
    setState(null, { scope: "align" });
    toast(`已导入 ${out.length} 行为内联编辑`, "ok");
  }

  /* ===================== 全局 API（供宿主 ExecuteScriptAsync 调用） ===================== */

  function setMode(m) {
    state.mode = m === "single" ? "single" : "multi";
    if (state.mode === "single") state.activeIndex = 0;
    setState(null, { scope: "all" });
    return state.mode;
  }

  window.setMode = setMode;

  window.setBaseDir = function (dir) {
    state.baseDir = PathUtil.normalizeSlash(trim(dir));
    setState(null, { scope: "form" });
    return state.baseDir;
  };

  window.loadManifestJson = function (text) {
    try {
      loadManifestObject(JSON.parse(String(text)), "");
      return true;
    } catch (e) {
      toast("载入失败：" + (e && e.message ? e.message : e), "err");
      return false;
    }
  };

  window.getManifestJson = function () { return manifestJson(); };

  window.saveManifest = function () { return doSaveManifest(); };

  window.run = function (baseUrl) {
    // 与现有页面保持一致的初始化入口；本页面无需远端数据，仅作占位与重绘
    if (baseUrl) state.baseUrl = baseUrl;
    setState(null, { scope: "all" });
  };

  /* ===================== 启动 ===================== */

  function boot() {
    initTheme();
    HostBridge.init();
    loadDraft();
    bindEvents();
    setState(null, { scope: "all" });

    if (!HostBridge.available) {
      console.info("[dataset] 未检测到 WebView2 宿主对象 win32，已启用浏览器降级模式。");
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }

})();
