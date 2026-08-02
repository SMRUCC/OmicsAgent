"use strict";

/* ================================================================
 *  配置
 * ================================================================ */
const MODULES_URL = "/tmp/modules.txt";
const getConclusionUrl = function (m) {
  return "/analysis/" + m + "/conclusion.md";
};

/* ================================================================
 *  DOM 引用
 * ================================================================ */
var app = document.getElementById("app");
var sidebar = document.getElementById("sidebar");
var sidebarToggle = document.getElementById("sidebarToggle");
var sidebarRestore = document.getElementById("sidebarRestore");
var themeToggle = document.getElementById("themeToggle");
var searchInput = document.getElementById("searchInput");
var moduleList = document.getElementById("moduleList");
var view = document.getElementById("view");
var currentModuleLabel = document.getElementById("currentModule");
var scrim = document.getElementById("scrim");

/* ================================================================
 *  状态
 * ================================================================ */
var modules = [];
var currentModule = null;
var abortController = null;

/* ================================================================
 *  SVG 图标
 * ================================================================ */
var moonSvg =
  '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>';
var sunSvg =
  '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="5"/><line x1="12" y1="1" x2="12" y2="3"/><line x1="12" y1="21" x2="12" y2="23"/><line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/><line x1="1" y1="12" x2="3" y2="12"/><line x1="21" y1="12" x2="23" y2="12"/><line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/></svg>';
var panelLeftSvg =
  '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="2"/><line x1="9" y1="3" x2="9" y2="21"/></svg>';

/* ================================================================
 *  主题
 * ================================================================ */
function initTheme() {
  var saved = localStorage.getItem("omics-theme");
  if (saved === "light" || saved === "dark") {
    document.documentElement.setAttribute("data-theme", saved);
  } else if (
    window.matchMedia &&
    window.matchMedia("(prefers-color-scheme: dark)").matches
  ) {
    document.documentElement.setAttribute("data-theme", "dark");
  }
  updateThemeIcon();
}

function toggleTheme() {
  var current = document.documentElement.getAttribute("data-theme") || "light";
  var next = current === "dark" ? "light" : "dark";
  document.documentElement.setAttribute("data-theme", next);
  localStorage.setItem("omics-theme", next);
  updateThemeIcon();
}

function updateThemeIcon() {
  var isDark = document.documentElement.getAttribute("data-theme") === "dark";
  themeToggle.innerHTML = isDark ? sunSvg : moonSvg;
  themeToggle.title = isDark ? "切换到亮色主题" : "切换到暗色主题";
}

/* ================================================================
 *  侧栏折叠 / 展开
 * ================================================================ */
function isMobile() {
  return window.innerWidth <= 860;
}

function toggleSidebar() {
  if (isMobile()) {
    var willOpen = !sidebar.classList.contains("open");
    sidebar.classList.toggle("open", willOpen);
    scrim.classList.toggle("show", willOpen);
    sidebarToggle.title = willOpen ? "收起侧栏" : "展开侧栏";
  } else {
    app.classList.toggle("sidebar-collapsed");
    var collapsed = app.classList.contains("sidebar-collapsed");
    sidebarToggle.title = collapsed ? "展开侧栏" : "折叠侧栏";
  }
}

/* ================================================================
 *  模块工具函数
 * ================================================================ */

// 自然数字排序：按模块名开头的数字排序（1, 2, ..., 9, 10, 11）
function naturalSort(a, b) {
  var na = parseInt(a, 10);
  var nb = parseInt(b, 10);
  if (!isNaN(na) && !isNaN(nb)) {
    if (na !== nb) return na - nb;
    return a.localeCompare(b);
  }
  if (!isNaN(na)) return -1;
  if (!isNaN(nb)) return 1;
  return a.localeCompare(b);
}

// 将模块名拆分为数字前缀和可读标题
function formatModule(name) {
  var match = name.match(/^(\d+)_(.+)/);
  if (match) {
    return { num: match[1], title: match[2].replace(/_/g, " ") };
  }
  return { num: "", title: name.replace(/_/g, " ") };
}

// 转义 HTML，防止 XSS
function escapeHtml(str) {
  var div = document.createElement("div");
  div.textContent = str;
  return div.innerHTML;
}

/* ================================================================
 *  加载模块列表
 * ================================================================ */
async function fetchModules() {
  try {
    var resp = await fetch(MODULES_URL);
    if (!resp.ok) throw new Error("HTTP " + resp.status);
    var text = await resp.text();
    modules = text
      .split("\n")
      .map(function (s) {
        return s.trim();
      })
      .filter(function (s) {
        return s.length > 0;
      });
    modules.sort(naturalSort);

    renderModuleList(modules);

    if (modules.length > 0) {
      loadModule(modules[0]);
    } else {
      moduleList.innerHTML = '<div class="no-results">模块列表为空</div>';
    }
  } catch (err) {
    moduleList.innerHTML =
      '<div class="banner err">无法加载模块列表：<br><code>' +
      escapeHtml(err.message) +
      "</code></div>";
  }
}

/* ================================================================
 *  渲染侧栏模块列表
 * ================================================================ */
function renderModuleList(list) {
  moduleList.innerHTML = "";

  if (list.length === 0) {
    moduleList.innerHTML = '<div class="no-results">没有匹配的模块</div>';
    return;
  }

  list.forEach(function (name) {
    var info = formatModule(name);
    var item = document.createElement("div");
    item.className = "doc-item";
    item.dataset.module = name;
    if (name === currentModule) item.classList.add("active");

    var badgeHtml = info.num
      ? '<span class="badge">' + escapeHtml(info.num) + "</span>"
      : "";

    item.innerHTML =
      '<div class="item-head">' +
      badgeHtml +
      '<span class="title">' +
      escapeHtml(info.title) +
      "</span></div>" +
      '<span class="fname">' +
      escapeHtml(name) +
      "</span>";

    item.addEventListener("click", function () {
      loadModule(name);
      // 移动端点击后自动收起侧栏
      if (isMobile()) {
        sidebar.classList.remove("open");
        scrim.classList.remove("show");
      }
    });

    moduleList.appendChild(item);
  });
}

/* ================================================================
 *  搜索过滤
 * ================================================================ */
function filterModules(query) {
  var q = query.toLowerCase().trim();
  var filtered = q
    ? modules.filter(function (m) {
        return m.toLowerCase().indexOf(q) !== -1;
      })
    : modules;
  renderModuleList(filtered);
}

/* ================================================================
 *  加载模块结论
 * ================================================================ */
async function loadModule(name) {
  // 取消上一个正在进行的请求
  if (abortController) {
    abortController.abort();
  }
  abortController = new AbortController();

  currentModule = name;
  currentModuleLabel.textContent = name;
  currentModuleLabel.title = name;

  // 更新侧栏高亮
  var items = moduleList.querySelectorAll(".doc-item");
  items.forEach(function (el) {
    el.classList.toggle("active", el.dataset.module === name);
  });

  // 显示骨架屏
  showSkeleton();

  try {
    var resp = await fetch(getConclusionUrl(name), {
      signal: abortController.signal,
    });
    if (!resp.ok) throw new Error("HTTP " + resp.status);
    var md = await resp.text();
    renderMarkdown(md, name);
  } catch (err) {
    if (err.name === "AbortError") return;
    showError(name, err);
  }
}

/* ================================================================
 *  Markdown 预处理
 * ================================================================ */

// 修复 ATX 标题缺少空格的问题（如 "##一、" → "## 一、"）
function preprocessMarkdown(md) {
  return md.replace(/^(#{1,6})([^\s#])/gm, "$1 $2");
}

/* ================================================================
 *  渲染 Markdown
 * ================================================================ */
function renderMarkdown(md, moduleName) {
  if (typeof marked === "undefined") {
    view.innerHTML =
      '<div class="banner err">marked.js 加载失败，请检查网络连接后刷新页面。</div>';
    return;
  }

  // 配置 marked
  marked.setOptions({
    gfm: true,
    breaks: true,
  });

  var processed = preprocessMarkdown(md);
  var html = marked.parse(processed);

  view.innerHTML = '<div class="markdown-body">' + html + "</div>";

  // 重写相对图片路径为绝对路径
  var imgs = view.querySelectorAll("img");
  imgs.forEach(function (img) {
    var src = img.getAttribute("src");
    if (
      src &&
      !src.startsWith("http") &&
      !src.startsWith("/") &&
      !src.startsWith("data:")
    ) {
      img.setAttribute("src", "/analysis/" + moduleName + "/" + src);
    }
    // 图片加载失败时隐藏
    img.addEventListener("error", function () {
      this.style.opacity = "0.3";
    });
  });

  // 滚动到顶部
  var content = document.getElementById("content");
  if (content) content.scrollTop = 0;
}

/* ================================================================
 *  骨架屏
 * ================================================================ */
function showSkeleton() {
  view.innerHTML =
    '<div class="skeleton-wrap">' +
    '<div class="skeleton" style="width: 55%; height: 30px; margin-bottom: 22px;"></div>' +
    '<div class="skeleton" style="width: 100%;"></div>' +
    '<div class="skeleton" style="width: 96%;"></div>' +
    '<div class="skeleton" style="width: 88%;"></div>' +
    '<div class="skeleton" style="width: 92%;"></div>' +
    '<div class="skeleton" style="width: 75%;"></div>' +
    '<div class="skeleton" style="width: 100%; height: 22px; margin-top: 24px;"></div>' +
    '<div class="skeleton" style="width: 60%;"></div>' +
    '<div class="skeleton" style="width: 90%;"></div>' +
    '<div class="skeleton" style="width: 82%;"></div>' +
    "</div>";
}

/* ================================================================
 *  错误提示
 * ================================================================ */
function showError(name, err) {
  view.innerHTML =
    '<div class="banner err">' +
    "<strong>无法加载模块结论</strong><br>" +
    "模块 <code>" +
    escapeHtml(name) +
    "</code> 的 conclusion.md 请求失败：<code>" +
    escapeHtml(err.message) +
    "</code>" +
    "</div>";
}

/* ================================================================
 *  事件绑定
 * ================================================================ */
themeToggle.addEventListener("click", toggleTheme);
sidebarToggle.addEventListener("click", toggleSidebar);
sidebarRestore.addEventListener("click", toggleSidebar);
searchInput.addEventListener("input", function (e) {
  filterModules(e.target.value);
});

// 移动端点击遮罩关闭侧栏
scrim.addEventListener("click", function () {
  sidebar.classList.remove("open");
  scrim.classList.remove("show");
});

// 监听系统主题变化（仅当用户未手动设置时）
if (window.matchMedia) {
  var mql = window.matchMedia("(prefers-color-scheme: dark)");
  if (mql.addEventListener) {
    mql.addEventListener("change", function (e) {
      if (!localStorage.getItem("omics-theme")) {
        document.documentElement.setAttribute(
          "data-theme",
          e.matches ? "dark" : "light",
        );
        updateThemeIcon();
      }
    });
  }
}

// 初始化侧栏切换按钮图标
sidebarToggle.innerHTML = panelLeftSvg;

/* ================================================================
 *  启动
 * ================================================================ */
initTheme();
fetchModules();
