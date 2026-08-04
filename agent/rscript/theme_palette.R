# ============================================================
# 00_theme_palette.R
# ------------------------------------------------------------
# Unified color palette and Times New Roman font setup
# Source this file at the beginning of each analysis script
# to ensure consistent styling across all figures.
#
# This file addresses two journal editor requirements:
#   1. Unify all color schemes (heatmaps, multi-series plots, etc.)
#   2. Use Times New Roman for all figure text
# ============================================================

# ---- 1. Times New Roman font setup ---------------------------
# Use extrafont to register and load Times New Roman.
# Falls back to "serif" (system default serif = Times on most OS)
# if Times New Roman is not available.
suppressPackageStartupMessages({
  if (!requireNamespace("extrafont", quietly = TRUE)) {
    install.packages("extrafont", dependencies = TRUE)
  }
  library(extrafont)
})

# Attempt to import Times New Roman fonts (only needed once per machine)
tryCatch({
  if (!("Times New Roman" %in% fonts())) {
    # Import only Times-family fonts to keep it fast
    font_import(pattern = "Times", prompt = FALSE)
  }
  loadfonts(quiet = TRUE)
}, error = function(e) {
  message("[00_theme_palette] extrafont import skipped: ",
          conditionMessage(e),
          "\n  -> Falling back to 'serif' family.")
})

# The font family string to use everywhere
# On Windows this is "Times New Roman"; on macOS it may be "Times";
# we detect the best available option.
TIMES_FONT <- if ("Times New Roman" %in% fonts()) {
  "Times New Roman"
} else if ("Times" %in% fonts()) {
  "Times"
} else {
  "serif"
}

cat("[00_theme_palette] Using font family:", TIMES_FONT, "\n")

# ---- 2. Unified NPG (Nature Publishing Group) color palette --
# This is the master categorical palette. All scripts draw
# their categorical colors from here so that every figure
# shares the same visual identity.
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

# ---- 3. Variety (line) colors -------------------------------
# Used in: 01.R, 02.R, 03.R, analysis.R, 07.R
LINE_COLORS <- c(
  "Jiazhuo" = NPG_COLORS[1],   # Red
  "CM104"   = NPG_COLORS[2]    # Cyan
)

# ---- 4. Time-point colors (sequential warm) -----------------
# Used in: 01.R, 02.R, analysis.R
TIME_COLORS <- c(
  "10" = "#FDB462",   # Light orange
  "20" = "#FB8072",   # Coral
  "30" = "#B3262E"    # Dark red
)

# ---- 5. Diverging heatmap palette (Blue -> White -> Red) ----
# Unified across ALL heatmaps:
#   - Sample correlation heatmap (01.R)
#   - Metabolite Z-score heatmap (02.R)
#   - Module-trait heatmap (04.R)
#   - Pathway genes heatmap (06.R)
#   - DE metabolite heatmap (analysis.R)
#   - Path coefficient / indirect effect / loadings heatmaps (visual.R)
HEATMAP_COLORS <- colorRampPalette(
  c(NPG_COLORS[4], "white", NPG_COLORS[1])
)(100)

# Convenience function: returns the same diverging palette
# as a 3-element vector for use with scale_fill_gradient2()
HEATMAP_GRADIENT <- c(low = NPG_COLORS[4], mid = "white", high = NPG_COLORS[1])

# ---- 6. Multi-omics layer colors (for PLS-PM / network) -----
# Used in: visual.R, 06.R (three-layer network)
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

# ---- 7. Network node / edge colors (06.R) -------------------
# Node types: Gene vs Metabolite (use NPG blue & red for contrast)
NODE_COLORS <- c(
  "Gene"       = NPG_COLORS[4],   # Blue
  "Metabolite" = NPG_COLORS[1]    # Red
)

# Edge types: Positive vs Negative correlation
EDGE_COLORS <- c(
  "Positive" = NPG_COLORS[1],     # Red
  "Negative" = NPG_COLORS[4]      # Blue
)

# Three-layer network (TF / Structural / Metabolite)
THREE_LAYER_COLORS <- c(
  "TF"         = NPG_COLORS[3],   # Green
  "Structural" = NPG_COLORS[1],   # Red
  "Metabolite" = NPG_COLORS[2]    # Cyan
)

# ---- 8. Volcano plot colors --------------------------------
# Up / Down / NS - consistent across 03.R and analysis.R
VOLCANO_COLORS <- c(
  "Up"              = NPG_COLORS[1],   # Red
  "Down"            = NPG_COLORS[2],   # Cyan
  "NS"              = "grey70",
  "Up in Jiazhuo"   = NPG_COLORS[1],
  "Up in CM104"     = NPG_COLORS[2],
  "Not significant" = "grey80"
)

# ---- 9. Model-quality metric colors (visual.R Fig 4) -------
METRIC_COLORS <- c(
  "R^2"         = NPG_COLORS[1],   # Red
  "Communality" = NPG_COLORS[4],   # Blue
  "Redundancy"  = NPG_COLORS[3]    # Green
)

# Effect decomposition (visual.R Fig 6)
EFFECT_COLORS <- c(
  "Direct"   = NPG_COLORS[1],      # Red
  "Indirect" = NPG_COLORS[4]       # Blue
)

# ---- 10. Helper: NPG palette of arbitrary length -----------
# For Class annotations (02.R, analysis.R) that need many colors
get_npg_palette <- function(n) {
  if (n <= length(NPG_COLORS)) {
    return(NPG_COLORS[seq_len(n)])
  } else {
    return(colorRampPalette(NPG_COLORS)(n))
  }
}

# ---- 11. Unified ggplot2 theme (Times New Roman) ------------
# A publication-ready theme applied to every ggplot figure.
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

# Set as the default theme for all subsequent ggplot calls
theme_set(theme_pub())

# ---- 12. Helper: set Times New Roman for base-R graphics -----
# Call this BEFORE pheatmap() / labeledHeatmap() / plot() so
# that base-graphics text also uses Times New Roman.
setup_base_font <- function() {
  par(family = TIMES_FONT)
}

# ---- 13. Helper: unified save function ----------------------
# Saves both PDF (with embedded fonts via cairo_pdf) and PNG.
# Use this for all ggplot-based figures.
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
