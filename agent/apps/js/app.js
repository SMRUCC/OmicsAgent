"use strict";

function run(BASE_URL) {
  /* ================================================================
   *  配置
   * ================================================================ */
  const MODULES_URL = BASE_URL + "/tmp/modules.txt";
  const getConclusionUrl = function (m) {
    return BASE_URL + "/analysis/" + m + "/conclusion.md";
  };
  const getPlanUrl = function (m) {
    return BASE_URL + "/tmp/" + m + "/plan.json";
  };
  const getResultUrl = function (m) {
    return BASE_URL + "/tmp/" + m + "/result.json";
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
  var tabBar = document.getElementById("tabBar");
  var currentModuleLabel = document.getElementById("currentModule");
  var scrim = document.getElementById("scrim");

  /* ================================================================
   *  状态
   * ================================================================ */
  var modules = [];
  var currentModule = null;
  var abortController = null;
  var activeTab = "conclusion"; // "conclusion" | "plan" | "result"
  // 缓存：每个模块加载过的数据，避免重复请求
  // cache[moduleName] = { conclusion: {ok, data, error}, plan: {...}, result: {...} }
  var cache = {};

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
    var current =
      document.documentElement.getAttribute("data-theme") || "light";
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
   *  标签页切换
   * ================================================================ */
  function switchTab(tabName) {
    activeTab = tabName;

    // 更新标签按钮状态
    var tabs = tabBar.querySelectorAll(".tab");
    tabs.forEach(function (btn) {
      btn.classList.toggle("active", btn.dataset.tab === tabName);
    });

    // 渲染对应内容
    renderTabContent();
  }

  // 根据当前激活标签渲染内容（使用缓存数据）
  function renderTabContent() {
    if (!currentModule) return;
    var cached = cache[currentModule];
    if (!cached) {
      showSkeleton();
      return;
    }

    if (activeTab === "conclusion") {
      renderConclusionTab(cached.conclusion);
    } else if (activeTab === "plan") {
      renderPlanTab(cached.plan);
    } else if (activeTab === "result") {
      renderResultTab(cached.result);
    }

    // 滚动到顶部
    var content = document.getElementById("content");
    if (content) content.scrollTop = 0;
  }

  /* ================================================================
   *  加载模块（并行拉取三个文件）
   * ================================================================ */
  async function loadModule(name) {
    // 取消上一个正在进行的请求
    if (abortController) {
      abortController.abort();
    }
    abortController = new AbortController();
    var signal = abortController.signal;

    currentModule = name;
    currentModuleLabel.textContent = name;
    currentModuleLabel.title = name;

    // 更新侧栏高亮
    var items = moduleList.querySelectorAll(".doc-item");
    items.forEach(function (el) {
      el.classList.toggle("active", el.dataset.module === name);
    });

    // 显示标签栏
    tabBar.style.display = "flex";

    // 重置到 conclusion 标签
    activeTab = "conclusion";
    var tabs = tabBar.querySelectorAll(".tab");
    tabs.forEach(function (btn) {
      btn.classList.toggle("active", btn.dataset.tab === "conclusion");
    });

    // 如果该模块已缓存，直接渲染
    if (cache[name]) {
      renderTabContent();
      return;
    }

    // 显示骨架屏
    showSkeleton();

    // 初始化缓存条目
    cache[name] = {
      conclusion: { status: "pending" },
      plan: { status: "pending" },
      result: { status: "pending" },
    };

    // 并行拉取三个文件
    fetchFile(getConclusionUrl(name), signal).then(
      function (result) {
        cache[name].conclusion = result;
        if (activeTab === "conclusion") renderConclusionTab(result);
      },
      function (err) {
        if (err.name === "AbortError") return;
        cache[name].conclusion = {
          status: "error",
          error: err.message,
        };
        if (activeTab === "conclusion")
          renderConclusionTab(cache[name].conclusion);
      },
    );

    fetchFile(getPlanUrl(name), signal).then(
      function (result) {
        cache[name].plan = result;
        if (activeTab === "plan") renderPlanTab(result);
      },
      function (err) {
        if (err.name === "AbortError") return;
        cache[name].plan = { status: "error", error: err.message };
        if (activeTab === "plan") renderPlanTab(cache[name].plan);
      },
    );

    fetchFile(getResultUrl(name), signal).then(
      function (result) {
        cache[name].result = result;
        if (activeTab === "result") renderResultTab(result);
      },
      function (err) {
        if (err.name === "AbortError") return;
        cache[name].result = { status: "error", error: err.message };
        if (activeTab === "result")
          renderResultTab(cache[name].result);
      },
    );
  }

  // 通用文件拉取：返回 {status, data, error}
  async function fetchFile(url, signal) {
    try {
      var resp = await fetch(url, { signal: signal });
      if (!resp.ok) throw new Error("HTTP " + resp.status);
      var text = await resp.text();
      return { status: "ok", data: text };
    } catch (err) {
      if (err.name === "AbortError") throw err;
      return { status: "error", error: err.message };
    }
  }

  /* ================================================================
   *  渲染：分析结论标签（conclusion.md）
   * ================================================================ */
  function renderConclusionTab(result) {
    if (result.status === "pending") {
      showSkeleton();
      return;
    }
    if (result.status === "error") {
      view.innerHTML =
        '<div class="banner err">' +
        "<strong>无法加载分析结论</strong><br>" +
        "conclusion.md 请求失败：<code>" +
        escapeHtml(result.error) +
        "</code>" +
        "</div>";
      return;
    }
    renderMarkdown(result.data, currentModule);
  }

  /* ================================================================
   *  渲染：分析计划标签（plan.json）
   * ================================================================ */
  function renderPlanTab(result) {
    if (result.status === "pending") {
      showSkeleton();
      return;
    }
    if (result.status === "error") {
      view.innerHTML =
        '<div class="banner err">' +
        "<strong>无法加载分析计划</strong><br>" +
        "plan.json 请求失败：<code>" +
        escapeHtml(result.error) +
        "</code>" +
        "</div>";
      return;
    }

    // 尝试解析 JSON
    var parsed;
    try {
      parsed = JSON.parse(result.data);
    } catch (e) {
      view.innerHTML =
        '<div class="banner err">' +
        "<strong>plan.json 解析失败</strong><br>" +
        "<code>" +
        escapeHtml(e.message) +
        "</code>" +
        "</div>";
      return;
    }

    view.innerHTML = renderPlanStructured(parsed, result.data);
    bindJsonToggle();
    bindCollapsible();

    // 滚动到顶部
    var content = document.getElementById("content");
    if (content) content.scrollTop = 0;
  }

  /* ================================================================
   *  渲染：分析结果标签（result.json）
   * ================================================================ */
  function renderResultTab(result) {
    if (result.status === "pending") {
      showSkeleton();
      return;
    }
    if (result.status === "error") {
      view.innerHTML =
        '<div class="banner err">' +
        "<strong>无法加载分析结果</strong><br>" +
        "result.json 请求失败：<code>" +
        escapeHtml(result.error) +
        "</code>" +
        "</div>";
      return;
    }

    var parsed;
    try {
      parsed = JSON.parse(result.data);
    } catch (e) {
      view.innerHTML =
        '<div class="banner err">' +
        "<strong>result.json 解析失败</strong><br>" +
        "<code>" +
        escapeHtml(e.message) +
        "</code>" +
        "</div>";
      return;
    }

    view.innerHTML = renderResultStructured(parsed, result.data);
    bindJsonToggle();
    bindCollapsible();

    var content = document.getElementById("content");
    if (content) content.scrollTop = 0;
  }

  /* ================================================================
   *  plan.json 结构化渲染
   * ================================================================ */
  function renderPlanStructured(data, rawJson) {
    var html = '<div class="json-viewer">';

    // 头部：模块名称
    var moduleName = data.module_name || data.ModuleName || data.name || "";
    if (moduleName) {
      html +=
        '<div class="jv-header">' +
        '<div class="jv-icon jv-icon-plan">📋</div>' +
        '<div>' +
        '<div class="jv-title">' +
        escapeHtml(moduleName) +
        "</div>" +
        '<div class="jv-subtitle">分析计划 (plan.json)</div>' +
        "</div></div>";
    }

    // 目标
    var goal = data.goal || data.Goal || "";
    if (goal) {
      html += renderSection("🎯 分析目标", goal, "jv-goal");
    }

    // 输入文件
    var inputFiles = data.input_files || data.InputFiles;
    if (inputFiles && inputFiles.length > 0) {
      html += renderFileList("📥 输入文件", inputFiles, "input");
    }

    // 输出文件
    var outputFiles = data.output_files || data.OutputFiles;
    if (outputFiles && outputFiles.length > 0) {
      html += renderFileList("📤 输出文件", outputFiles, "output");
    }

    // 执行步骤
    var steps = data.execution_steps || data.ExecutionSteps;
    if (steps && steps.length > 0) {
      html += '<div class="jv-section">';
      html += '<div class="jv-section-title">📝 执行步骤</div>';
      steps.forEach(function (step, i) {
        var action = step.action || step.Action || "";
        var stepGoal = step.goal || step.Goal || "";
        var rscript = step.rscript_path || step.RScriptPath || "";

        html += '<div class="jv-step">';
        html +=
          '<div class="jv-step-num">' + (i + 1) + "</div>";
        html += '<div class="jv-step-body">';
        if (action) {
          html +=
            '<div class="jv-step-action">' +
            escapeHtml(action) +
            "</div>";
        }
        if (stepGoal) {
          html +=
            '<div class="jv-step-goal"><span class="jv-label">目标：</span>' +
            escapeHtml(stepGoal) +
            "</div>";
        }
        if (rscript) {
          html +=
            '<div class="jv-step-meta"><span class="jv-label">脚本：</span><code>' +
            escapeHtml(rscript) +
            "</code></div>";
        }
        html += "</div></div>";
      });
      html += "</div>";
    }

    // 备注
    var notes = data.notes || data.Notes || "";
    if (notes) {
      html += renderSection("💡 备注", notes, "jv-notes");
    }

    // 比较组（如果有）
    var comparisons = data.comparisons;
    if (comparisons) {
      var compStr =
        typeof comparisons === "string"
          ? comparisons
          : JSON.stringify(comparisons, null, 2);
      if (compStr && compStr !== "null") {
        html += renderSection("🔬 比较组设计", compStr, "jv-comparisons");
      }
    }

    // 结论（折叠）
    var conclusion = data.conclusion || data.Conclusion || "";
    if (conclusion) {
      html +=
        '<div class="jv-section jv-collapsible">' +
        '<div class="jv-section-title jv-collapse-toggle">' +
        '<span class="jv-collapse-icon">▼</span>分析结论预览</div>' +
        '<div class="jv-collapse-body jv-conclusion-text">' +
        escapeHtml(conclusion) +
        "</div></div>";
    }

    // LLM 回复（折叠）
    var llmResp = data.llm_response || data.LlmResponse || "";
    if (llmResp) {
      html +=
        '<div class="jv-section jv-collapsible">' +
        '<div class="jv-section-title jv-collapse-toggle">' +
        '<span class="jv-collapse-icon">▼</span>LLM 回复</div>' +
        '<div class="jv-collapse-body jv-llm-text">' +
        escapeHtml(llmResp) +
        "</div></div>";
    }

    // Raw JSON 切换
    html +=
      '<div class="jv-raw-toggle">' +
      '<button class="jv-raw-btn" data-raw="plan">查看原始 JSON</button>' +
      "</div>";

    html += "</div>"; // json-viewer

    // 隐藏的 raw JSON 预格式化块（切换时显示）
    html +=
      '<pre class="jv-raw-pre" id="raw-plan" style="display:none;"><code>' +
      escapeHtml(prettyJson(rawJson)) +
      "</code></pre>";

    return html;
  }

  /* ================================================================
   *  result.json 结构化渲染
   * ================================================================ */
  function renderResultStructured(data, rawJson) {
    var html = '<div class="json-viewer">';

    // 头部：模块名称 + 序号
    var moduleName = data.ModuleName || data.module_name || data.name || "";
    var moduleIndex = data.ModuleIndex || data.module_index;

    if (moduleName) {
      var indexBadge = moduleIndex != null
        ? '<span class="jv-index-badge">模块 ' + escapeHtml(String(moduleIndex)) + "</span>"
        : "";
      html +=
        '<div class="jv-header">' +
        '<div class="jv-icon jv-icon-result">📊</div>' +
        '<div>' +
        '<div class="jv-title">' +
        indexBadge +
        escapeHtml(moduleName) +
        "</div>" +
        '<div class="jv-subtitle">分析结果 (result.json)</div>' +
        "</div></div>";
    }

    // 目标
    var goal = data.Goal || data.goal || "";
    if (goal) {
      html += renderSection("🎯 分析目标", goal, "jv-goal");
    }

    // 结论（长文本，折叠）
    var conclusion = data.Conclusion || data.conclusion || "";
    if (conclusion) {
      html +=
        '<div class="jv-section jv-collapsible">' +
        '<div class="jv-section-title jv-collapse-toggle">' +
        '<span class="jv-collapse-icon">▼</span>分析结论</div>' +
        '<div class="jv-collapse-body jv-conclusion-text">' +
        escapeHtml(conclusion) +
        "</div></div>";
    }

    // 输出目录
    var outputDir = data.OutputDir || data.output_dir || "";
    if (outputDir) {
      html += renderKeyValue("📂 输出目录", outputDir);
    }

    // 工作目录
    var workdir = data.Workdir || data.workdir || "";
    if (workdir) {
      html += renderKeyValue("🔧 工作目录", workdir);
    }

    // 输出文件（如果有）
    var outputFiles = data.OutputFiles || data.output_files;
    if (outputFiles && outputFiles.length > 0) {
      html += renderFileList("📤 输出文件", outputFiles, "output");
    }

    // 输入文件（如果有）
    var inputFiles = data.InputFiles || data.input_files;
    if (inputFiles && inputFiles.length > 0) {
      html += renderFileList("📥 输入文件", inputFiles, "input");
    }

    // 比较组（如果有）
    var comparisons = data.comparisons || data.Comparisons;
    if (comparisons) {
      var compStr =
        typeof comparisons === "string"
          ? comparisons
          : JSON.stringify(comparisons, null, 2);
      if (compStr && compStr !== "null") {
        html += renderSection("🔬 比较组设计", compStr, "jv-comparisons");
      }
    }

    // Raw JSON 切换
    html +=
      '<div class="jv-raw-toggle">' +
      '<button class="jv-raw-btn" data-raw="result">查看原始 JSON</button>' +
      "</div>";

    html += "</div>"; // json-viewer

    html +=
      '<pre class="jv-raw-pre" id="raw-result" style="display:none;"><code>' +
      escapeHtml(prettyJson(rawJson)) +
      "</code></pre>";

    return html;
  }

  /* ================================================================
   *  JSON 渲染辅助函数
   * ================================================================ */

  // 渲染一个文本段落区块
  function renderSection(title, text, extraClass) {
    return (
      '<div class="jv-section ' + (extraClass || "") + '">' +
      '<div class="jv-section-title">' + title + "</div>" +
      '<div class="jv-section-text">' +
      escapeHtml(text) +
      "</div></div>"
    );
  }

  // 渲染键值对
  function renderKeyValue(label, value) {
    return (
      '<div class="jv-section jv-kv">' +
      '<span class="jv-section-label">' + label + "</span>" +
      '<code class="jv-section-code">' +
      escapeHtml(value) +
      "</code></div>"
    );
  }

  // 渲染文件列表
  function renderFileList(title, files, type) {
    var html = '<div class="jv-section">';
    html += '<div class="jv-section-title">' + title + "</div>";
    html += '<ul class="jv-file-list jv-file-' + type + '">';
    files.forEach(function (f) {
      // 提取文件名部分用于显示
      var display = f;
      var sep = f.lastIndexOf("/");
      var sep2 = f.lastIndexOf("\\");
      var lastSep = Math.max(sep, sep2);
      if (lastSep >= 0 && lastSep < f.length - 1) {
        display = f.substring(lastSep + 1);
      }
      html +=
        '<li title="' +
        escapeHtml(f) +
        '"><span class="jv-file-icon">' +
        (type === "input" ? "▸" : "▹") +
        "</span>" +
        escapeHtml(display) +
        "</li>";
    });
    html += "</ul></div>";
    return html;
  }

  // 美化 JSON 字符串（如果解析失败则返回原始）
  function prettyJson(rawStr) {
    try {
      return JSON.stringify(JSON.parse(rawStr), null, 2);
    } catch (e) {
      return rawStr;
    }
  }

  /* ================================================================
   *  交互绑定：Raw JSON 切换
   * ================================================================ */
  function bindJsonToggle() {
    var btns = view.querySelectorAll(".jv-raw-btn");
    btns.forEach(function (btn) {
      btn.addEventListener("click", function () {
        var key = btn.dataset.raw; // "plan" or "result"
        var pre = document.getElementById("raw-" + key);
        var viewer = view.querySelector(".json-viewer");
        if (!pre || !viewer) return;

        if (pre.style.display === "none") {
          pre.style.display = "block";
          viewer.style.display = "none";
          btn.textContent = "查看结构化视图";
        } else {
          pre.style.display = "none";
          viewer.style.display = "block";
          btn.textContent = "查看原始 JSON";
        }
      });
    });
  }

  /* ================================================================
   *  交互绑定：折叠区块
   * ================================================================ */
  function bindCollapsible() {
    var toggles = view.querySelectorAll(".jv-collapse-toggle");
    toggles.forEach(function (toggle) {
      toggle.addEventListener("click", function () {
        var section = toggle.parentElement;
        section.classList.toggle("collapsed");
        var icon = toggle.querySelector(".jv-collapse-icon");
        if (icon) {
          icon.textContent = section.classList.contains("collapsed")
            ? "▶"
            : "▼";
        }
      });
    });
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
        img.setAttribute(
          "src",
          BASE_URL + "/analysis/" + moduleName + "/" + src,
        );
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
   *  事件绑定
   * ================================================================ */
  themeToggle.addEventListener("click", toggleTheme);
  sidebarToggle.addEventListener("click", toggleSidebar);
  sidebarRestore.addEventListener("click", toggleSidebar);
  searchInput.addEventListener("input", function (e) {
    filterModules(e.target.value);
  });

  // 标签页切换
  tabBar.addEventListener("click", function (e) {
    var btn = e.target.closest(".tab");
    if (!btn) return;
    switchTab(btn.dataset.tab);
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
}
