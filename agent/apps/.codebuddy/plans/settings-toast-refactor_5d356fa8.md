---
name: settings-toast-refactor
overview: 将 settings.html 的提示方式由顶部 banner 改为右下角 toast 气泡，复用 dataset.css 的 toast 样式与 dataset.js 的 toast 调用约定。
todos:
  - id: add-toast-style
    content: 在 settings.html 的 style 中追加 toast-host/toast 相关样式
    status: completed
  - id: add-toast-host
    content: 在 body 末尾新增 toastHost 容器并移除 bannerHost
    status: completed
  - id: replace-banner-logic
    content: 用 toast() 替换 showBanner() 及所有调用点
    status: completed
    dependencies:
      - add-toast-style
      - add-toast-host
---

## 用户需求

将 settings.html 的提示方式从当前顶部 banner 消息提示，改为与 dataset.html 一致的右下角 toast 气泡。

## 产品概述

保持 settings.html 现有布局与配置功能不变，仅替换消息提示的呈现形式：移除顶部 banner 容器与逻辑，新增固定在页面右下角的 toast 宿主容器，并以气泡形式展示操作反馈。视觉样式与 dataset.html 的 toast 完全一致。

## 核心功能

- 页面右下角固定显示 toast 气泡，多条消息纵向堆叠、自动消失。
- 成功类消息左侧绿条（ok），失败类左侧橙条（err），普通提示左侧蓝色条（info）。
- 所有原有提示场景（加载成功/失败、复制成功/失败、下载成功、文件读取失败）均迁移为 toast，文案与业务逻辑不变。

## 技术栈

- 纯 HTML + 原生 JavaScript（与 settings.html 现状一致），不引入框架或构建。
- 样式：沿用 kb.css 的设计令牌；toast 专用样式直接内联在 settings.html 的 `<style>` 中（源自 dataset.css 的 toast 片段，仅依赖 kb.css 变量），不引入 dataset.css 以避免无关样式污染。

## 实现方案

采用与 dataset.js 完全一致的 `toast(msg, kind)` 调用约定与 DOM 结构，确保视觉与行为对齐：

1. 在 `<head>` 现有 `<style>` 内追加 toast 样式：`.toast-host`（fixed 右下、z-index:90、flex 列、pointer-events:none）、`.toast`（卡片外观、rise 入场）、`.toast.leaving`（toastOut 离场）、`.toast.ok`（绿条）、`.toast.err`（橙条）、`@keyframes toastOut`。
2. 在 `<body>` 末尾新增 `<div class="toast-host" id="toastHost" aria-live="polite"></div>`，移除 `<main>` 内的 `#bannerHost` 容器。
3. 删除 `showBanner()`，新增 `toast(msg, kind)`：`el("div","toast"+kind, esc(msg))` 追加到 `#toastHost`，停留 2600ms 后加 `leaving`，再 320ms 移除；提供 `el()`/`esc()` 辅助。
4. 将所有 `showBanner(...)` 调用替换为 `toast(...)`：成功场景用 `"ok"`，失败用 `"err"`，普通提示用 `""`（info，蓝色左边条）。

## 实现说明（执行细节）

- 复用 kb.css 已有 `rise` 动画与 `--ui-*`/`--card-*`/`--shadow-lg`/`--radius-sm` 令牌，toast 视觉与 dataset 完全一致。
- 不改动任何配置渲染、加载、生成、复制、下载、主题切换逻辑，仅替换提示通道，降低回归风险。
- `esc()` 对消息文本做 HTML 转义，避免注入与样式破坏。
- 停留时长 2600ms + 离场 320ms，与 dataset.js 一致，避免消息堆积。

## 架构设计

单文件内变更，结构层注入 toast-host 容器，样式层追加 toast CSS，逻辑层以 `toast()` 替代 `showBanner()`。无新增模块或依赖。

## 目录结构

```
g:/OmicsWorks/agent/apps/
└── settings.html   # [MODIFY] 移除 #bannerHost 与 showBanner()；新增 toast-host 容器、toast CSS、toast() 函数；所有提示调用改为 toast()。
```