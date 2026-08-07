# ============================================================
# 00_theme_palette.R
# ------------------------------------------------------------
# 统一配色方案与 Times New Roman 字体设置
# 在每个分析脚本开头 source 本文件，
# 以确保所有图形的样式保持一致。
#
# 本文件满足期刊编辑的两项要求：
#   1. 统一所有配色方案（热图、多系列图等）
#   2. 所有图形文字使用 Times New Roman 字体
# ============================================================

# ---- 1. Times New Roman 字体设置 ---------------------------
# 使用 extrafont 注册并加载 Times New Roman。
# 若 Times New Roman 不可用，则回退到 "serif"
# （大多数操作系统下系统默认衬线字体即 Times）。

suppressPackageStartupMessages({
  if (!requireNamespace("extrafont", quietly = TRUE)) {
    install.packages("extrafont", dependencies = TRUE)
  }
  library(extrafont)
})

# 尝试导入 Times New Roman 字体（每台机器只需执行一次）
tryCatch({
  if (!("Times New Roman" %in% fonts())) {
    # 仅导入 Times 系列字体以加快速度
    font_import(pattern = "Times", prompt = FALSE)
  }
  loadfonts(quiet = TRUE)
}, error = function(e) {
  message("[00_theme_palette] extrafont import skipped: ",
          conditionMessage(e),
          "\n  -> Falling back to 'serif' family.")
})

# 全局使用的字体族名称
# 在 Windows 上为 "Times New Roman"；在 macOS 上可能为 "Times"；
# 此处自动检测当前可用的最佳选项。
TIMES_FONT <- if ("Times New Roman" %in% fonts()) {
  "Times New Roman"
} else if ("Times" %in% fonts()) {
  "Times"
} else {
  "serif"
}

cat("[00_theme_palette] Using font family:", TIMES_FONT, "\n")

# ---- 2. 统一 NPG（Nature Publishing Group）配色方案 --
# 这是主分类配色板。所有脚本均从此处取用分类颜色，
# 使每一张图都共享相同的视觉标识。
NPG_COLORS <- c(
  "#E64B35",  # 1. Red        (Jiazhuo / Up / Phenotype)
  "#4DBBD5",  # 2. Cyan       (CM104 / Down / Metabolite)
  "#00A087",  # 3. Green      (TF / Structural)
  "#3C5488",  # 4. Blue       (Transcriptome / negative-cor heat)
  "#F39B7F",  # 5. Orange     (Flavonoids)
  "#8491B4",  # 6. Purple
  "#91D1C2",  # 7. Light green
  "#DC0000",  # 8. Bright red
  "#7E6148",  # 9. Brown
  "#B09C85"   # 10. Tan
)

# ---- 3. 品种（折线）颜色 -------------------------------
# 用于：01.R、02.R、03.R、analysis.R、07.R
LINE_COLORS <- c(
  "Jiazhuo" = NPG_COLORS[1],   # Red
  "CM104"   = NPG_COLORS[2]    # Cyan
)

# ---- 4. 时间点颜色（顺序暖色）-----------------
# 用于：01.R、02.R、analysis.R
TIME_COLORS <- c(
  "10" = "#FDB462",   # Light orange
  "20" = "#FB8072",   # Coral
  "30" = "#B3262E"    # Dark red
)

# ---- 5. 发散型热图配色（蓝 -> 白 -> 红）----
# 在所有热图中统一使用：
#   - 样本相关性热图（01.R）
#   - 代谢物 Z-score 热图（02.R）
#   - 模块-性状热图（04.R）
#   - 通路基因热图（06.R）
#   - 差异代谢物热图（analysis.R）
#   - 路径系数 / 间接效应 / 载荷热图（visual.R）
HEATMAP_COLORS <- colorRampPalette(
  c(NPG_COLORS[4], "white", NPG_COLORS[1])
)(100)

# 便捷函数：以 3 元素向量形式返回相同的发散型配色，
# 供 scale_fill_gradient2() 使用
HEATMAP_GRADIENT <- c(low = NPG_COLORS[4], mid = "white", high = NPG_COLORS[1])

# ---- 6. 多组学层级颜色（用于 PLS-PM / 网络）-----
# 用于：visual.R、06.R（三层网络）
LAYER_COLORS <- c(
  "rnaseq"     = NPG_COLORS[4],   # Blue   - Transcriptome
  "protein"    = NPG_COLORS[3],   # Green  - Proteome
  "flavone"    = NPG_COLORS[5],   # Orange - Flavonoids
  "phenotype"  = NPG_COLORS[1]    # Red    - Phenotype
)

LAYER_LABELS <- c(
  "rnaseq"     = "Transcriptome",
  "protein"    = "Proteome",
  "flavone"    = "Flavonoids",
  "phenotype"  = "Phenotype"
)

# ---- 7. 网络节点 / 边颜色（06.R）-------------------
# 节点类型：基因 vs 代谢物（用 NPG 蓝与红形成对比）
NODE_COLORS <- c(
  "Gene"       = NPG_COLORS[4],   # Blue
  "Metabolite" = NPG_COLORS[1]    # Red
)

# 边类型：正相关 vs 负相关
EDGE_COLORS <- c(
  "Positive" = NPG_COLORS[1],     # Red
  "Negative" = NPG_COLORS[4]      # Blue
)

# 三层网络（转录因子 TF / 结构基因 Structural / 代谢物 Metabolite）
THREE_LAYER_COLORS <- c(
  "TF"         = NPG_COLORS[3],   # Green
  "Structural" = NPG_COLORS[1],   # Red
  "Metabolite" = NPG_COLORS[2]    # Cyan
)

# ---- 8. 火山图颜色 --------------------------------
# 上调 / 下调 / 不显著（NS）——在 03.R 与 analysis.R 中保持一致
VOLCANO_COLORS <- c(
  "Up"              = NPG_COLORS[1],   # Red
  "Down"            = NPG_COLORS[2],   # Cyan
  "NS"              = "grey70",
  "Up in Jiazhuo"   = NPG_COLORS[1],
  "Up in CM104"     = NPG_COLORS[2],
  "Not significant" = "grey80"
)

# ---- 9. 模型质量指标颜色（visual.R 图 4）-------
METRIC_COLORS <- c(
  "R^2"         = NPG_COLORS[1],   # Red
  "Communality" = NPG_COLORS[4],   # Blue
  "Redundancy"  = NPG_COLORS[3]    # Green
)

# 效应分解（visual.R 图 6）
EFFECT_COLORS <- c(
  "Direct"   = NPG_COLORS[1],      # Red
  "Indirect" = NPG_COLORS[4]       # Blue
)

# ---- 10. 辅助函数：任意长度的 NPG 配色 -----------
# 用于需要多种颜色的类别注释（02.R、analysis.R）
get_npg_palette <- function(n) {
  if (n <= length(NPG_COLORS)) {
    return(NPG_COLORS[seq_len(n)])
  } else {
    return(colorRampPalette(NPG_COLORS)(n))
  }
}

# ---- 11. 统一 ggplot2 主题（Times New Roman）------------
# 一个可直接用于发表的，应用于每张 ggplot 图形的主题。
theme_pub <- function(base_size = 13) {
  theme_bw(base_size = base_size, base_family = TIMES_FONT) +
    theme(
      panel.grid         = element_blank(),
      panel.border       = element_rect(color = "black", linewidth = 0.6),
      plot.title         = element_text(face = "bold", hjust = 0.5,
                                        size = base_size + 1,
                                        family = TIMES_FONT),
      plot.subtitle      = element_text(hjust = 0.5, family = TIMES_FONT),
      plot.caption       = element_text(hjust = 0, family = TIMES_FONT),
      axis.text          = element_text(color = "black", family = TIMES_FONT),
      axis.text.x        = element_text(color = "black", family = TIMES_FONT),
      axis.text.y        = element_text(color = "black", family = TIMES_FONT),
      axis.title         = element_text(family = TIMES_FONT),
      axis.title.x       = element_text(family = TIMES_FONT),
      axis.title.y       = element_text(family = TIMES_FONT),
      legend.title       = element_text(face = "bold", family = TIMES_FONT),
      legend.text        = element_text(family = TIMES_FONT),
      strip.text         = element_text(face = "bold", family = TIMES_FONT),
      strip.background   = element_rect(fill = "grey92"),
      legend.key         = element_blank()
    )
}

# 设为后续所有 ggplot 调用的默认主题
theme_set(theme_pub())

# ---- 12. 辅助函数：为 base-R 图形设置 Times New Roman -----
# 在 pheatmap() / labeledHeatmap() / plot() 之前调用，
# 使 base 图形中的文字也使用 Times New Roman。
setup_base_font <- function() {
  par(family = TIMES_FONT)
}

# ---- 13. 辅助函数：统一保存函数 ----------------------
# 同时保存 PDF（通过 cairo_pdf 内嵌字体）与 PNG。
# 所有基于 ggplot 的图形均使用本函数保存。
save_plot_unified <- function(plot, filename, width = 8, height = 6,
                              dpi = 600, out_dir = ".") {
  pdf_path  <- file.path(out_dir, paste0(filename, ".pdf"))
  png_path  <- file.path(out_dir, paste0(filename, ".png"))
  # cairo_pdf embeds fonts properly for journal submission
  ggsave(pdf_path, plot, width = width, height = height,
         device = cairo_pdf)
  ggsave(png_path, plot, width = width, height = height,
         dpi = dpi, type = "cairo")
}

cat("[00_theme_palette] Unified palette and Times New Roman theme loaded.\n")
