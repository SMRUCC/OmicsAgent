"use strict";

/* ===================== 配置元数据（驱动渲染） ===================== */
const CONFIG_SCHEMA = {
  Analysis: {
    title: "分析参数",
    cardClass: "card--blue",
    dot: "var(--card-blue)",
    fields: [
      {
        key: "DiffPvalueCutoff",
        type: "number",
        step: "any",
        label: "差异检验 P 值阈值",
      },
      { key: "DiffTopCount", type: "number", step: "1", label: "差异条目上限" },
      {
        key: "MetaboliteVipCutoff",
        type: "number",
        step: "any",
        label: "代谢物 VIP 阈值",
      },
      {
        key: "WgcnaTopMAD",
        type: "number",
        step: "1",
        label: "WGCNA 高 MAD 上限",
      },
    ],
  },
  LLM: {
    title: "大模型",
    cardClass: "card--purple",
    dot: "var(--card-purple)",
    fields: [
      { key: "LLMApiKey", type: "password", label: "API Key" },
      { key: "LLMMaxRounds", type: "number", step: "1", label: "最大对话轮数" },
      { key: "LLMModelName", type: "text", label: "模型名称" },
      { key: "LLMServiceUrl", type: "text", label: "服务地址" },
    ],
  },
  Literature: {
    title: "文献检索",
    cardClass: "card--green",
    dot: "var(--card-green)",
    fields: [
      { key: "AutoSearchLiterature", type: "bool", label: "自动检索文献" },
      {
        key: "LiteratureSearchStrategy",
        type: "enum",
        options: ["none", "mysql", "ncbi"],
        label: "检索策略",
      },
      {
        key: "MaxLiteratureCount",
        type: "number",
        step: "1",
        label: "最大文献数量",
      },
    ],
  },
  MySql: {
    title: "MySQL 数据库",
    cardClass: "card--orange",
    dot: "var(--card-orange)",
    fields: [
      { key: "MySqlDatabase", type: "text", label: "数据库名" },
      { key: "MySqlHost", type: "text", label: "主机地址" },
      { key: "MySqlPassword", type: "password", label: "密码" },
      { key: "MySqlPort", type: "number", step: "1", label: "端口" },
      { key: "MySqlUser", type: "text", label: "用户名" },
    ],
  },
  Report: {
    title: "报告输出",
    cardClass: "card--teal",
    dot: "var(--card-teal)",
    fields: [
      {
        key: "OutputFormat",
        type: "enum",
        options: ["pdf", "docx", "both"],
        label: "输出格式",
      },
    ],
  },
  Tools: {
    title: "外部工具",
    cardClass: "card--pink",
    dot: "var(--card-pink)",
    fields: [
      { key: "PythonPath", type: "text", label: "Python 路径" },
      { key: "RscriptPath", type: "text", label: "Rscript 路径" },
      { key: "RsharpPath", type: "text", label: "R# 路径" },
      { key: "WkHtmlToPdfPath", type: "text", label: "wkhtmltopdf 路径" },
    ],
  },
};

/* 默认值（与用户给定 JSON 完全一致） */
const DEFAULT_CONFIG = {
  Analysis: {
    DiffPvalueCutoff: 0.05,
    DiffTopCount: 200,
    MetaboliteVipCutoff: 1,
    WgcnaTopMAD: 20000,
  },
  LLM: {
    LLMApiKey: "",
    LLMMaxRounds: 100,
    LLMModelName: "",
    LLMServiceUrl: "http://localhost:11434",
  },
  Literature: {
    AutoSearchLiterature: true,
    LiteratureSearchStrategy: "none",
    MaxLiteratureCount: 20,
  },
  MySql: {
    MySqlDatabase: "pubmed",
    MySqlHost: "localhost",
    MySqlPassword: "",
    MySqlPort: 3306,
    MySqlUser: "root",
  },
  Report: { OutputFormat: "pdf" },
  Tools: {
    PythonPath: "",
    RscriptPath: "",
    RsharpPath: "",
    WkHtmlToPdfPath: "",
  },
};

/* ===================== 工具函数 ===================== */
const $ = (sel, root = document) => root.querySelector(sel);

function esc(s) {
  return String(s).replace(/[&<>"]/g, (c) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;"
  }[c]));
}

function toast(message, kind) {
  const host = $("#toastHost");
  if (!host) return;
  const t = document.createElement("div");
  t.className = "toast" + (kind ? " " + kind : "");
  t.innerHTML = esc(message);
  host.appendChild(t);
  setTimeout(() => {
    t.classList.add("leaving");
    setTimeout(() => t.remove(), 320);
  }, 2600);
  return t;
}

function coerceValue(field, raw) {
  if (raw === undefined || raw === null) return raw;
  if (field.type === "number") {
    const n = Number(raw);
    return Number.isNaN(n) ? raw : n;
  }
  if (field.type === "bool") return Boolean(raw);
  return raw;
}

/* ===================== 渲染卡片与控件 ===================== */
function renderCards() {
  const cardsHost = $("#cards");
  const navHost = $("#navList");
  cardsHost.innerHTML = "";
  navHost.innerHTML = "";

  Object.entries(CONFIG_SCHEMA).forEach(([group, def]) => {
    // 主区卡片
    const card = document.createElement("section");
    card.className = "card " + def.cardClass;
    card.id = "card-" + group;

    const h3 = document.createElement("h3");
    h3.innerHTML = '<span class="dot"></span>' + def.title;
    card.appendChild(h3);

    const grid = document.createElement("div");
    grid.className = "form-grid";

    def.fields.forEach((field) => {
      const wrap = document.createElement("div");
      wrap.className = "field";

      const label = document.createElement("label");
      label.setAttribute("for", "f-" + group + "-" + field.key);
      label.innerHTML =
        field.label + '<span class="code-key">' + field.key + "</span>";
      wrap.appendChild(label);

      let ctrl;
      if (field.type === "bool") {
        const sw = document.createElement("label");
        sw.className = "switch";
        ctrl = document.createElement("input");
        ctrl.type = "checkbox";
        ctrl.id = "f-" + group + "-" + field.key;
        const state = document.createElement("span");
        state.className = "state";
        state.textContent = "false";
        ctrl.addEventListener("change", () => {
          state.textContent = ctrl.checked ? "true" : "false";
        });
        sw.appendChild(ctrl);
        sw.appendChild(state);
        wrap.appendChild(sw);
      } else if (field.type === "enum") {
        ctrl = document.createElement("select");
        ctrl.className = "ctrl";
        ctrl.id = "f-" + group + "-" + field.key;
        (field.options || []).forEach((opt) => {
          const o = document.createElement("option");
          o.value = opt;
          o.textContent = opt;
          ctrl.appendChild(o);
        });
        wrap.appendChild(ctrl);
      } else if (field.type === "number") {
        ctrl = document.createElement("input");
        ctrl.type = "number";
        ctrl.className = "ctrl";
        ctrl.id = "f-" + group + "-" + field.key;
        if (field.step) ctrl.step = field.step;
        wrap.appendChild(ctrl);
      } else {
        ctrl = document.createElement("input");
        ctrl.type = field.type === "password" ? "password" : "text";
        ctrl.className = "ctrl";
        ctrl.id = "f-" + group + "-" + field.key;
        wrap.appendChild(ctrl);
      }
      ctrl.dataset.group = group;
      ctrl.dataset.key = field.key;
      ctrl.dataset.ftype = field.type;

      grid.appendChild(wrap);
    });

    card.appendChild(grid);
    cardsHost.appendChild(card);

    // 侧栏导航
    const nav = document.createElement("button");
    nav.className = "nav-item";
    nav.dataset.group = group;
    nav.innerHTML =
      '<span class="dot" style="background:' +
      def.dot +
      '"></span>' +
      '<span class="t">' +
      def.title +
      "</span>" +
      '<span class="k">' +
      group +
      "</span>";
    nav.addEventListener("click", () => {
      const target = $("#card-" + group);
      if (target) target.scrollIntoView({ behavior: "smooth", block: "start" });
    });
    navHost.appendChild(nav);
  });
}

/* ===================== 读取 / 写入控件值 ===================== */
function readConfig() {
  const out = {};
  Object.keys(CONFIG_SCHEMA).forEach((group) => {
    out[group] = {};
    CONFIG_SCHEMA[group].fields.forEach((field) => {
      const ctrl = $("#f-" + group + "-" + field.key);
      if (!ctrl) return;
      if (field.type === "bool") {
        out[group][field.key] = ctrl.checked;
      } else if (field.type === "number") {
        const v = ctrl.value === "" ? "" : Number(ctrl.value);
        out[group][field.key] = v;
      } else {
        out[group][field.key] = ctrl.value;
      }
    });
  });
  return out;
}

function applyConfig(cfg) {
  if (!cfg || typeof cfg !== "object") throw new Error("配置不是有效的对象");
  Object.keys(CONFIG_SCHEMA).forEach((group) => {
    const grp = cfg[group];
    if (!grp) return;
    CONFIG_SCHEMA[group].fields.forEach((field) => {
      const ctrl = $("#f-" + group + "-" + field.key);
      if (!ctrl || !(field.key in grp)) return;
      const val = coerceValue(field, grp[field.key]);
      if (field.type === "bool") {
        ctrl.checked = Boolean(val);
        const st = ctrl.parentElement.querySelector(".state");
        if (st) st.textContent = ctrl.checked ? "true" : "false";
      } else if (field.type === "enum") {
        ctrl.value = String(val);
      } else {
        ctrl.value = val === undefined || val === null ? "" : val;
      }
    });
  });
}

/* ===================== 生成 JSON ===================== */
function generateJson() {
  const cfg = readConfig();
  const text = JSON.stringify(cfg, null, 2);
  $("#jsonOut").textContent = text;
  $("#jsonMeta").textContent = text.length + " 字符";
  return text;
}

/* ===================== 加载 JSON（文本/文件） ===================== */
function loadFromText(text) {
  try {
    const cfg = JSON.parse(text);
    applyConfig(cfg);
    generateJson();
    toast("配置已成功加载并回填。", "ok");
  } catch (e) {
    toast("JSON 解析失败：" + e.message, "err");
  }
}

/* ===================== 复制 / 下载 ===================== */
async function copyJson() {
  generateJson();
  const text = $("#jsonOut").textContent;
  if (!text || text.startsWith("点击")) {
    toast("请先生成 JSON 再复制。", "err");
    return;
  }

  const h =
    window.chrome &&
    window.chrome.webview &&
    window.chrome.webview.hostObjects &&
    window.chrome.webview.hostObjects.win32;

  if (h) {
    h.Save(text);
    toast("已经保存参数配置到文件。", "ok");
  } else {
    toast("无法保存配置为文件，将会复制到剪切板！", "err");

    try {
      if (navigator.clipboard && window.isSecureContext) {
        await navigator.clipboard.writeText(text);
      } else {
        const ta = document.createElement("textarea");
        ta.value = text;
        document.body.appendChild(ta);
        ta.select();
        document.execCommand("copy");
        ta.remove();
      }
      toast("已复制到剪贴板。", "ok");
    } catch (e) {
      toast("复制失败：" + e.message, "err");
    }
  }
}

function downloadJson() {
  const text = $("#jsonOut").textContent;
  if (!text || text.startsWith("点击")) {
    toast("请先生成 JSON 再下载。", "err");
    return;
  }
  const blob = new Blob([text], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = "app-config.json";
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
  toast("已导出 app-config.json。", "ok");
}

/* ===================== 主题切换 ===================== */
function toggleTheme() {
  const html = document.documentElement;
  const next = html.getAttribute("data-theme") === "dark" ? "light" : "dark";
  html.setAttribute("data-theme", next);
  $("#themeIcon").textContent = next === "dark" ? "☀️" : "🌙";
  $("#themeLabel").textContent = next === "dark" ? "亮色" : "暗色";
}

/* ===================== 侧栏筛选 ===================== */
function bindNavFilter() {
  const search = $("#navSearch");
  search.addEventListener("input", () => {
    const q = search.value.trim().toLowerCase();
    let shown = 0;
    document.querySelectorAll(".nav-item").forEach((it) => {
      const hay = (
        it.dataset.group +
        " " +
        it.querySelector(".t").textContent
      ).toLowerCase();
      const ok = !q || hay.includes(q);
      it.classList.toggle("hidden", !ok);
      if (ok) shown++;
    });
    $("#navEmpty").classList.toggle("hidden", shown > 0);
  });
}

/* ===================== 初始化 ===================== */
function init() {
  renderCards();
  bindNavFilter();
  applyConfig(DEFAULT_CONFIG);
  generateJson();

  $("#genBtn").addEventListener("click", generateJson);
  $("#copyBtn").addEventListener("click", copyJson);
  $("#downloadBtn").addEventListener("click", downloadJson);
  $("#themeBtn").addEventListener("click", toggleTheme);

  $("#loadBtn").addEventListener("click", () => $("#fileInput").click());
  $("#fileInput").addEventListener("change", (e) => {
    const file = e.target.files && e.target.files[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = () => loadFromText(String(reader.result));
    reader.onerror = () => toast("文件读取失败。", "err");
    reader.readAsText(file);
    e.target.value = "";
  });
}

document.addEventListener("DOMContentLoaded", init);
