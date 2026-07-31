"use strict";

/* ===================== 配置 ===================== */
const BASE_URL = "http://localhost"; // 知识库服务根地址（CORS 已开启）
let activeToken = 0; // 异步请求令牌：防止快速切换文献/汇总时的竞态覆盖

/* ===================== 缓存 ===================== */
const cache = {
  docList: null,
  perDoc: new Map(), // jsonName -> per_doc 对象
  txt: new Map(), // sourceFile -> 解析后的 {title, meta, references, body}
  kb: null,
  titles: new Map(), // jsonName -> 文献标题（用于侧栏显示）
};

const $ = (sel) => document.querySelector(sel);
const el = (tag, cls, html) => {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (html != null) n.innerHTML = html;
  return n;
};
const esc = (s) =>
  String(s == null ? "" : s).replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ],
  );

/* ===================== 主题 ===================== */
function applyTheme(theme) {
  document.documentElement.setAttribute("data-theme", theme);
  const dark = theme === "dark";
  $("#themeIcon").textContent = dark ? "☀️" : "🌙";
  $("#themeLabel").textContent = dark ? "亮色" : "暗色";
  try {
    localStorage.setItem("kb-theme", theme);
  } catch (e) {}
}
function initTheme() {
  let t = null;
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

function toggleTheme() {
  const cur = document.documentElement.getAttribute("data-theme");
  applyTheme(cur === "dark" ? "light" : "dark");
}

$("#themeBtn").addEventListener("click", () => toggleTheme());

/* ===================== 网络层 ===================== */
async function getText(path) {
  const res = await fetch(BASE_URL + "/" + path, { cache: "no-store" });
  if (!res.ok) throw new Error("HTTP " + res.status + " · " + path);
  return await res.text();
}
async function getJson(path) {
  const txt = await getText(path);
  return JSON.parse(txt);
}

/* 解析 files.txt：兼容 JSON 数组 与 换行文本 两种格式 */
function parseFileList(raw) {
  raw = raw.trim();
  if (!raw) return [];
  try {
    const j = JSON.parse(raw);
    if (Array.isArray(j)) return j.map((x) => String(x).trim()).filter(Boolean);
  } catch (e) {
    /* 不是 JSON，按换行解析 */
  }
  return raw
    .split(/\r?\n/)
    .map((s) => s.trim())
    .filter(Boolean);
}

/* 解析 txt 原文（前 4 行结构化，其后为 markdown 全文） */
function parseDocTxt(raw) {
  const lines = raw.split(/\r?\n/);
  const title = (lines[0] || "").trim();
  let meta = {};
  try {
    meta = JSON.parse(lines[1] || "{}");
  } catch (e) {
    meta = { raw: lines[1] || "" };
  }
  let references = [];
  try {
    references = JSON.parse(lines[2] || "[]");
  } catch (e) {
    references = [];
  }
  let bodyStart = lines.length > 3 && lines[3].trim() === "" ? 4 : 3;
  const body = lines.slice(bodyStart).join("\n").trim();
  return {
    title,
    meta: {
      doi: meta.doi || "",
      year: meta.year || "",
      journal: meta.journal || "",
      keywords: Array.isArray(meta.keywords) ? meta.keywords : [],
    },
    references: Array.isArray(references) ? references : [],
    body,
  };
}

/* ===================== Markdown ===================== */
function renderMarkdown(md) {
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

/* ===================== 侧栏 ===================== */
function renderDocList(list) {
  const box = $("#docList");
  box.innerHTML = "";
  list.forEach((name) => {
    const item = el("button", "doc-item");
    item.dataset.name = name;
    const title = cache.titles.get(name);
    let html = '<span class="fname">' + esc(name) + "</span>";
    if (title) html += '<span class="title">' + esc(title) + "</span>";
    item.innerHTML = html;
    item.addEventListener("click", () => selectDoc(name));
    box.appendChild(item);
  });
}

function updateDocItemTitle(name, title) {
  cache.titles.set(name, title);
  const item = document.querySelector(
    '.doc-item[data-name="' + CSS.escape(name) + '"]',
  );
  if (item) {
    let t = item.querySelector(".title");
    if (!t) {
      t = document.createElement("span");
      t.className = "title";
      item.appendChild(t);
    }
    t.textContent = title;
  }
}

/* ===================== 知识点渲染 ===================== */
// 通用：根据字段渲染（per_doc 与 kb.json 共用，因字段同名）
// modClass: 彩色分类修饰类（card--blue 等），用于区分知识点类型
function tagSection(titleText, arr, modClass) {
  if (!Array.isArray(arr) || arr.length === 0) return "";
  const mod = modClass ? " " + modClass : "";
  const tags = arr
    .map((x) => '<span class="tag">' + esc(x) + "</span>")
    .join("");
  return (
    '<div class="card' + mod + '"><h3><span class="dot"></span>' +
    esc(titleText) +
    "（" +
    arr.length +
    "）</h3>" +
    '<div class="tags">' +
    tags +
    "</div></div>"
  );
}

function mechanismsSection(arr) {
  if (!Array.isArray(arr) || arr.length === 0) return "";
  const cards = arr
    .map((m) => {
      const mech = m && m.mechanism ? m.mechanism : "";
      const ev = m && m.evidence ? m.evidence : "";
      return (
        '<div class="mech"><div class="m">' +
        esc(mech) +
        "</div>" +
        (ev ? '<div class="e"><b>证据：</b>' + esc(ev) + "</div>" : "") +
        "</div>"
      );
    })
    .join("");
  return (
    '<div class="card card--orange"><h3><span class="dot"></span>生物机制（' +
    arr.length +
    "）</h3>" +
    cards +
    "</div>"
  );
}

/* 仅 kb.json 汇总包含：对比设计建议 */
function comparisonSection(arr) {
  if (!Array.isArray(arr) || arr.length === 0) return "";
  const cards = arr
    .map((c) => {
      const comp = c && c.comparison ? c.comparison : "";
      const purp = c && c.purpose ? c.purpose : "";
      return (
        '<div class="mech"><div class="m">' +
        esc(comp) +
        "</div>" +
        (purp ? '<div class="e"><b>目的：</b>' + esc(purp) + "</div>" : "") +
        "</div>"
      );
    })
    .join("");
  return (
    '<div class="card card--pink"><h3><span class="dot"></span>对比设计建议（' +
    arr.length +
    "）</h3>" +
    cards +
    "</div>"
  );
}

/* 仅 kb.json 汇总包含：预期发现 */
function expectedFindingsSection(arr) {
  if (!Array.isArray(arr) || arr.length === 0) return "";
  const items = arr
    .map((x) => '<div class="ref"><div class="m">' + esc(x) + "</div></div>")
    .join("");
  return (
    '<div class="card card--purple"><h3><span class="dot"></span>预期发现（' +
    arr.length +
    '）</h3><div class="ref-list">' +
    items +
    "</div></div>"
  );
}

/* 仅 kb.json 汇总包含：核心参考文献（含关键发现） */
function kbReferencesSection(arr) {
  if (!Array.isArray(arr) || arr.length === 0) return "";
  const refs = arr
    .map(
      (r) =>
        '<div class="ref"><div class="rt">' +
        esc((r && r.title) || "（无标题）") +
        "</div>" +
        (r && r.key_finding
          ? '<div class="rm" style="margin-top:4px"><b style="color:var(--primary-3)">关键发现：</b>' +
            esc(r.key_finding) +
            "</div>"
          : "") +
        "</div>",
    )
    .join("");
  return (
    '<div class="card card--gray"><h3><span class="dot"></span>核心参考文献（' +
    arr.length +
    '）</h3><div class="ref-list">' +
    refs +
    "</div></div>"
  );
}

function renderKnowledge(obj) {
  let html = "";
  // 概览字段（kb.json 汇总包含；per_doc 不含）
  const overview = [
    ["research_topic", "研究主题"],
    ["disease_or_phenotype", "疾病 / 表型"],
    ["organism", "物种"],
    ["tissue", "组织 / 样本"],
  ];
  const ov = overview.filter(([k]) => obj[k]);
  if (ov.length) {
    const pills = ov
      .map(
        ([k, label]) =>
          '<div class="kv-pill"><div class="k">' +
          esc(label) +
          '</div><div class="v">' +
          esc(obj[k]) +
          "</div></div>",
      )
      .join("");
    html +=
      '<div class="card"><h3><span class="dot"></span>概览</h3><div class="pill-row">' +
      pills +
      "</div></div>";
  }
  // 列表型知识点
  html += tagSection("关键基因 / 蛋白", obj.key_genes_proteins, "card--blue");
  html += tagSection("关键通路", obj.key_pathways, "card--purple");
  html += tagSection("关键代谢物", obj.key_metabolites, "card--teal");
  html += tagSection("关键发现", obj.key_findings, "card--green");
  // 机制
  html += mechanismsSection(obj.biological_mechanisms);
  // 相关性
  if (obj.relevance_to_research_topic) {
    html +=
      '<div class="card card--blue relevance"><h3><span class="dot"></span>与研究主题相关性</h3><p>' +
      esc(obj.relevance_to_research_topic) +
      "</p></div>";
  }
  // 仅 kb.json 汇总包含的三类区块（per_doc 无这些字段，依存在性跳过）
  html += comparisonSection(obj.comparison_design_suggestions);
  html += expectedFindingsSection(obj.expected_findings);
  html += kbReferencesSection(obj.references);
  return html;
}

/* ===================== 文献详情视图 ===================== */
async function selectDoc(name) {
  document
    .querySelectorAll(".doc-item")
    .forEach((d) => d.classList.toggle("active", d.dataset.name === name));
  closeDrawer();
  const main = $("#content");
  main.scrollTop = 0; // 切换时重置滚动位置
  const token = ++activeToken; // 本次请求的令牌
  main.innerHTML =
    '<div class="view"><div class="skeleton" style="width:60%"></div><div class="skeleton" style="width:90%"></div><div class="skeleton" style="width:80%"></div></div>';

  try {
    // 惰性加载 per_doc 知识点 json（带缓存）
    let perDoc;
    if (cache.perDoc.has(name)) {
      perDoc = cache.perDoc.get(name);
    } else {
      perDoc = await getJson(name);
      if (token !== activeToken) return; // 已切换，丢弃过期结果
      cache.perDoc.set(name, perDoc);
    }

    // 惰性加载关联的 txt 全文（带缓存）
    const src = perDoc.source_file;
    let parsed;
    if (cache.txt.has(src)) {
      parsed = cache.txt.get(src);
    } else {
      const raw = await getText(src);
      if (token !== activeToken) return; // 已切换，丢弃过期结果
      parsed = parseDocTxt(raw);
      cache.txt.set(src, parsed);
    }
    updateDocItemTitle(name, parsed.title);

    let view = '<div class="view">';
    // 元数据卡片
    view +=
      '<div class="card"><h3><span class="dot"></span>' +
      esc(parsed.title || name) +
      "</h3>" +
      '<div class="meta-grid">' +
      '<div class="meta-cell"><div class="k">DOI</div><div class="v">' +
      (parsed.meta.doi
        ? '<a href="https://doi.org/' +
          esc(parsed.meta.doi) +
          '" target="_blank" rel="noopener">' +
          esc(parsed.meta.doi) +
          "</a>"
        : "—") +
      "</div></div>" +
      '<div class="meta-cell"><div class="k">年份</div><div class="v">' +
      esc(parsed.meta.year || "—") +
      "</div></div>" +
      '<div class="meta-cell"><div class="k">期刊</div><div class="v">' +
      esc(parsed.meta.journal || "—") +
      "</div></div>" +
      '<div class="meta-cell"><div class="k">来源文件</div><div class="v">' +
      esc(src) +
      "</div></div>" +
      "</div>" +
      (parsed.meta.keywords.length
        ? '<div style="margin-top:14px"><div class="k" style="font-size:11px;color:var(--text-muted);text-transform:uppercase;letter-spacing:.8px">关键词</div><div class="tags" style="margin-top:6px">' +
          parsed.meta.keywords
            .map((k) => '<span class="tag">' + esc(k) + "</span>")
            .join("") +
          "</div></div>"
        : "") +
      "</div>";

    // 参考文献
    if (parsed.references.length) {
      const refs = parsed.references
        .map(
          (r) =>
            '<div class="ref"><div class="rt">' +
            esc(r.title || "（无标题）") +
            "</div>" +
            '<div class="rm">' +
            esc([r.year, r.journal, r.doi].filter(Boolean).join(" · ")) +
            "</div></div>",
        )
        .join("");
      view +=
        '<div class="card"><h3><span class="dot"></span>参考文献（' +
        parsed.references.length +
        '）</h3><div class="ref-list">' +
        refs +
        "</div></div>";
    }

    // 全文
    view +=
      '<div class="card"><h3><span class="dot"></span>全文（Markdown）</h3><div class="markdown-body">' +
      renderMarkdown(parsed.body) +
      "</div></div>";

    // 关联知识点（per_doc）
    view +=
      '<div style="margin:22px 0 6px;font-size:13px;letter-spacing:1px;color:var(--text-muted);text-transform:uppercase">提炼知识点 · ' +
      esc(name) +
      "</div>";
    view += renderKnowledge(perDoc);

    view += "</div>";
    if (token !== activeToken) return; // 渲染前再次校验，避免竞态覆盖
    main.innerHTML = view;
    bindTagToggle();
  } catch (err) {
    if (token !== activeToken) return; // 过期请求的错误不覆盖当前视图
    console.error("加载文献失败", name, err);
    main.innerHTML =
      '<div class="view"><div class="banner err"><b>加载失败：</b>' +
      esc(err.message) +
      "<br/>请确认服务已启动（serve_kb.py）且地址为 " +
      esc(BASE_URL) +
      "。</div></div>";
  }
}

/* ===================== 汇总视图 (kb.json) ===================== */
async function showSummary() {
  document
    .querySelectorAll(".doc-item")
    .forEach((d) => d.classList.remove("active"));
  closeDrawer();
  const main = $("#content");
  main.scrollTop = 0; // 切换时重置滚动位置
  const token = ++activeToken; // 本次请求的令牌
  main.innerHTML =
    '<div class="view"><div class="skeleton" style="width:50%"></div><div class="skeleton" style="width:85%"></div><div class="skeleton" style="width:75%"></div></div>';
  try {
    const kb = cache.kb || (cache.kb = await getJson("kb.json"));
    if (token !== activeToken) return; // 已切换，丢弃过期结果
    if (kb.research_topic)
      $("#topicLine").textContent = "主题：" + kb.research_topic;
    let view = '<div class="view">';
    view +=
      '<div class="card"><h3><span class="dot"></span>知识库汇总（kb.json）</h3>' +
      '<div style="color:var(--text-soft);font-size:14px;line-height:1.7">' +
      (kb.research_topic ? "研究主题：" + esc(kb.research_topic) : "") +
      "</div></div>";
    view += renderKnowledge(kb);
    view += "</div>";
    if (token !== activeToken) return; // 渲染前再次校验，避免竞态覆盖
    main.innerHTML = view;
    bindTagToggle();
  } catch (err) {
    if (token !== activeToken) return; // 过期请求的错误不覆盖当前视图
    console.error("加载 kb.json 失败", err);
    main.innerHTML =
      '<div class="view"><div class="banner err"><b>加载 kb.json 失败：</b>' +
      esc(err.message) +
      "</div></div>";
  }
}
$("#summaryBtn").addEventListener("click", showSummary);

/* 标签点击高亮 */
function bindTagToggle() {
  document.querySelectorAll(".tag").forEach((t) => {
    t.addEventListener("click", () => t.classList.toggle("active"));
  });
}

/* ===================== 抽屉（移动端） ===================== */
function openDrawer() {
  $("#sidebar").classList.add("open");
  $("#scrim").classList.add("show");
}
function closeDrawer() {
  $("#sidebar").classList.remove("open");
  $("#scrim").classList.remove("show");
}
$("#drawerToggle").addEventListener("click", openDrawer);
$("#scrim").addEventListener("click", closeDrawer);

/* ===================== 搜索筛选 ===================== */
$("#searchInput").addEventListener("input", (e) => {
  const q = e.target.value.trim().toLowerCase();
  document.querySelectorAll(".doc-item").forEach((it) => {
    const hay = (
      it.dataset.name +
      " " +
      (cache.titles.get(it.dataset.name) || "")
    ).toLowerCase();
    it.style.display = !q || hay.includes(q) ? "" : "none";
  });
});

/* ===================== 启动 ===================== */
async function init() {
  initTheme();
  try {
    const raw = await getText("files.txt");
    const list = parseFileList(raw);
    cache.docList = list;
    renderDocList(list);
  } catch (err) {
    console.error("加载 files.txt 失败", err);
    $("#content").innerHTML =
      '<div class="view"><div class="banner err"><b>无法获取文献列表（/files.txt）：</b>' +
      esc(err.message) +
      "<br/>请确认已启动 serve_kb.py 且该目录下存在 files.txt。</div></div>";
  }
}

init();
