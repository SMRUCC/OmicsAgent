---
name: metabolomics_superclass_manhattan
overview: 在 demo_metabolomics.R 中新增曼哈顿图步骤：以 super_class 为 x 轴分类、PLS-DA 的 VIP 值为 y 轴，绘制每类下 VIP 分布的分类曼哈顿 jitter 图，全英文图注，导出 PDF（矢量）+ PNG（300dpi）论文插图。
design:
  architecture:
    framework: html
  styleKeywords:
    - Publication
    - Clean
    - Minimalist
    - Academic
  fontSystem:
    fontFamily: Helvetica
    heading:
      size: 14px
      weight: .nan
    subheading:
      size: 12px
      weight: 600
    body:
      size: 11px
      weight: 400
  colorSystem:
    primary:
      - "#1B9E77"
      - "#D95F02"
      - "#7570B3"
    background:
      - "#FFFFFF"
      - "#F5F5F5"
    text:
      - "#000000"
      - "#333333"
    functional:
      - "#D7191C"
      - "#1B9E77"
todos:
  - id: add-step26-manhattan
    content: 在 demo_metabolomics.R 的 Step 25 后新增 Step 26：合并 VIP 与 super_class 绘制分类曼哈顿 jitter 图并 export_plot 导出 PNG+PDF
    status: completed
  - id: update-summary-manhattan
    content: 在 demo_metabolomics.R 末尾 Summary 追加 VIP 曼哈顿图完成提示
    status: completed
    dependencies:
      - add-step26-manhattan
---

## 用户需求

在现有代谢组学分析流程 `test/omics_flow/demo_metabolomics.R` 中新增一个曼哈顿图（分类曼哈顿图 / jitter 分布图），用作论文插图。

## 产品概述

以代谢物的 `super_class` 注释作为横轴分类（类比曼哈顿图的染色体），以 PLS-DA 计算得到的 VIP 值作为纵轴，在同一张图中按 x 轴顺序排列各个 super_class 类别，绘制每个类别下所有代谢物 VIP 值的 jitter 分布，并叠加分布轮廓（boxplot/violin）与 VIP 阈值参考线。导出的图片需清晰美观、图注全英文，同时输出 PNG（300dpi）与 PDF（矢量）两种格式。

## 核心功能

- 复用 Step 8 已生成的 PLS-DA VIP 值（`plsda_result$vip`）。
- 按 `super_class` 分组，横轴排列各类别，纵轴为 VIP 值。
- 每类下绘制 jitter 点展示单个代谢物 VIP 分布，并叠加半透明框线/小提琴展示整体分布。
- 标注 VIP 阈值线（y=1.0），红色虚线。
- 全英文图注：坐标轴、标题、图例均为英文。
- x 轴文本旋转 45° 避免重叠；论文级主题与字号。
- 导出 PNG（300dpi cairo）与 PDF（矢量），文件名 `vip_manhattan_superclass`。
- 鲁棒处理：PLS-DA 未运行（无 mixOmics）或 super_class 为空时安全跳过。
- 在流程 Summary 区块追加完成提示。

## 技术栈

- 语言/环境：R（Rscript），沿用现有管线约定。
- 已有依赖：`export_plot()`（`agent/rscript/utils/export.R`，同时导出 PDF 矢量 + PNG 300dpi）、ggplot2（脚本第 24 行已加载）、RColorBrewer（已加载）。
- 数据来源：`plsda_result$vip`（Step 8 全局变量）、`feat_info`（含 `name`、`super_class` 列，Step 1 加载）。

## 实现方案

### 总体策略

保持现有 25 个 Step 不变，在 Step 25 之后追加 Step 26。在 Step 26 中：将 PLS-DA 的 VIP 数据框（rownames 为 feature id）与 `feat_info` 按 feature id 合并取 `super_class`，过滤空类别后，用 ggplot2 绘制分类曼哈顿 jitter 图，通过现有 `export_plot()` 同时导出 PDF 与 PNG。全程 `tryCatch` 包裹，与 Step 19/21-25 一致。

### 关键技术决策

1. **复用 VIP 而非重算**：直接取 `plsda_result$vip`，避免重复运行 PLS-DA，降低开销与回归风险。
2. **x 轴排序**：按各 `super_class` 的 VIP 中位数降序排列因子水平，使图形由高 VIP 类别向低 VIP 类别过渡，视觉更有序（曼哈顿图常见做法）。
3. **jitter + 分布轮廓**：`geom_jitter`（width≈0.2, alpha≈0.7, size≈1.5）展示单点；叠加 `geom_boxplot`（outlier.shape=NA, alpha≈0.3）展示中位数与四分位，避免点完全遮挡。不强制用 violin，boxplot 更简洁、论文常用。
4. **阈值线**：`geom_hline(yintercept=1.0, linetype="dashed", color="red")` 标注 VIP 显著性经验阈值。
5. **全英文 + 论文级样式**：所有 label/title/legend 英文；`theme_bw(base_size=12)`；x 轴 `element_text(angle=45, hjust=1, vjust=1)`；配色 `scale_color_brewer(palette="Set2")` 或按类别离散色。
6. **导出**：`export_plot(manhattan_plot, fig_dir, "vip_manhattan_superclass", width=10, height=6, dpi=300)`，复用现有函数保证 PDF(矢量)+PNG(300dpi cairo)。
7. **鲁棒性**：

- 用 `exists("plsda_result") && !is.null(plsda_result$scores)` 判断 PLS-DA 是否成功运行；否则 `cat` 跳过。
- 合并后过滤 `super_class` 为 NA/""/"NULL" 的行；若过滤后无数据则跳过。
- `tryCatch` 捕获绘图错误并打印 `conditionMessage(e)`。

### 性能与可靠性

- 仅做一次 data.frame 合并与一次 ggplot 构建，数据规模（数百特征 × 数十类别）开销可忽略。
- 不引入新依赖，复用已加载库与导出函数。
- 风险点：部分化合物 `super_class` 为空（如 KEGG=NULL 行），已在合并后显式过滤。
- 风险点：PLS-DA 跳过时 `plsda_result$vip` 可能不存在，已用 `exists` + `!is.null(scores)` 双重保护。

## 实现说明（防止回归）

- 仅追加 Step 26 与 Summary 打印项，不改动任何既有 Step。
- 新增 step 使用与 Step 25 相同的 `cat` 日志风格与 `tryCatch` 结构。
- 导出文件名遵循现有约定（`tables/` 与 `figures/`）。
- 图注、坐标、标题一律英文，满足论文插图要求。

## 架构设计

- 数据流：`plsda_result$vip` + `feat_info`（super_class）→ 合并过滤 → ggplot（分类曼哈顿 jitter+boxplot+阈值线）→ `export_plot()` → `figures/vip_manhattan_superclass.png` + `.pdf`。
- 复用现有函数层与导出层，无新架构模式引入。

## 目录结构

```
test/omics_flow/
└── demo_metabolomics.R          # [MODIFY] 在 Step 25 后新增 Step 26（构建 VIP×super_class 数据 → 绘制分类曼哈顿 jitter 图 → export_plot 导出 PNG+PDF，tryCatch 包裹）；在 Summary 区块追加完成提示。
```

## 关键代码结构（新增 Step 26 核心片段）

```
# Step 26: VIP Manhattan plot by super class
manhattan_ok <- tryCatch({
  if (!exists("plsda_result") || is.null(plsda_result$scores)) {
    cat("  PLS-DA not available. Skipping VIP manhattan plot.\n")
    FALSE
  } else {
    vip_df <- data.frame(feature_id = rownames(plsda_result$vip),
                         vip = plsda_result$vip$vip, stringsAsFactors = FALSE)
    vip_df <- merge(vip_df, feat_info[, c("name", "super_class")],
                    by.x = "feature_id", by.y = "name", all.x = TRUE)
    vip_df <- vip_df[!is.na(vip_df$super_class) &
                       vip_df$super_class != "" & vip_df$super_class != "NULL", ]
    # order x axis by median VIP per super class
    ord <- with(vip_df, tapply(vip, super_class, median, na.rm = TRUE))
    vip_df$super_class <- factor(vip_df$super_class,
                                 levels = names(sort(ord, decreasing = TRUE)))
    p <- ggplot(vip_df, aes(x = super_class, y = vip, color = super_class)) +
      geom_boxplot(outlier.shape = NA, alpha = 0.3, color = "black",
                   fill = "grey90") +
      geom_jitter(width = 0.2, size = 1.5, alpha = 0.7) +
      geom_hline(yintercept = 1.0, linetype = "dashed", color = "red") +
      scale_color_brewer(palette = "Set2") +
      labs(x = "Super Class", y = "VIP score (PLS-DA)",
           title = "VIP Distribution by Super Class",
           color = "Super Class") +
      theme_bw(base_size = 12) +
      theme(axis.text.x = element_text(angle = 45, hjust = 1, vjust = 1))
    export_plot(p, fig_dir, "vip_manhattan_superclass", width = 10, height = 6, dpi = 300)
    TRUE
  }
}, error = function(e) {
  cat("  VIP manhattan plot error:", conditionMessage(e), "\n")
  FALSE
})
```

本任务为在已有 R 分析流程中新增一张用于论文插图的分类曼哈顿 jitter 图，输出为静态 PNG/PDF 图片，不涉及交互式 Web/APP UI，因此不另设前端框架与组件库。图形本身采用 ggplot2 论文级主题（theme_bw，base_size=12，x 轴标签旋转 45° 防止重叠），配色使用 ColorBrewer Set2 离散调色板，叠加半透明 boxplot 轮廓与红色虚线 VIP 阈值，确保清晰、专业、可直接用于出版。