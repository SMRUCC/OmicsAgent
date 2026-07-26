# =============================================================================
# Module4 Step3: Publication-grade Visualizations
# =============================================================================
# (3a) Volcano plots x3 (FE_vs_CD, CD_vs_NC, FE_vs_NC) - top5 labels
# (3b) Venn diagram -3 comparison overlap
# (3c) Heatmap - differential metabolites, class row annotation, Z-score
# (3d) PDF + PNG (300 dpi), English labels, theme_bw
# (3e) CSV results already exist from Step2
# =============================================================================

# ---------------------------------------------------------------------------
#0. Configuration
# ---------------------------------------------------------------------------
WORK_DIR <- "G:/OmicsWorks/test/metabolism/demo/tmp/4_limma_differential_analysis"
TABLES_DIR <- file.path(WORK_DIR, "tables")
FIGURES_DIR <- "G:/OmicsWorks/test/metabolism/demo/analysis/4_limma_differential_analysis/figures"
AGENT_RSCRIPT <- "G:/OmicsWorks/agent/rscript"

PREPROCESSED_EXPR <- "G:/OmicsWorks/test/metabolism/demo/tmp/preprocessed_expression.csv"
SAMPLE_INFO <- "G:/OmicsWorks/test/metabolism/sampleinfo.csv"
METABOLITES_ANNO <- "G:/OmicsWorks/test/metabolism/metabolites.csv"

DE_FILES <- list(
 FE_vs_CD = file.path(TABLES_DIR, "limma_FE_vs_CD.csv"),
 CD_vs_NC = file.path(TABLES_DIR, "limma_CD_vs_NC.csv"),
 FE_vs_NC = file.path(TABLES_DIR, "limma_FE_vs_NC.csv")
)

dir.create(FIGURES_DIR, recursive = TRUE, showWarnings = FALSE)

sep_line <- paste(rep("=",63), collapse = "")

# ---------------------------------------------------------------------------
#1. Package Loading
# ---------------------------------------------------------------------------
cat(sep_line, "\n")
cat("Module4 Step3: Publication-grade Visualizations\n")
cat(sep_line, "\n\n")

cat("[1] Loading packages...\n")
cran_pkgs <- c("ggplot2", "ggrepel", "ggVennDiagram", "pheatmap",
 "RColorBrewer", "jsonlite")
for (pkg in cran_pkgs) {
 if (!requireNamespace(pkg, quietly = TRUE))
 install.packages(pkg, repos = "https://cloud.r-project.org", quiet = TRUE)
 library(pkg, character.only = TRUE)
}
library(grDevices)
library(stats)
cat(" Packages loaded.\n\n")

# ---------------------------------------------------------------------------
#2. Data Loading
# ---------------------------------------------------------------------------
cat("[2] Loading data...\n")

# Load expression matrix
expr_raw <- read.csv(PREPROCESSED_EXPR, check.names = FALSE, stringsAsFactors = FALSE)
rownames(expr_raw) <- expr_raw[,1]
expr_raw <- expr_raw[,-1]
expr_raw <- as.matrix(expr_raw)
mode(expr_raw) <- "numeric"
cat(" Expression matrix:", nrow(expr_raw), "x", ncol(expr_raw), "\n")

# Load sample metadata
sample_meta_all <- read.csv(SAMPLE_INFO, stringsAsFactors = FALSE, check.names = FALSE)
sample_meta_all$ID <- as.character(sample_meta_all$ID)
sample_meta_all$sample_info <- as.factor(sample_meta_all$sample_info)

# Filter QC samples
bio_samples <- intersect(colnames(expr_raw), sample_meta_all$ID)
expr_raw <- expr_raw[, bio_samples, drop = FALSE]
sample_meta <- sample_meta_all[sample_meta_all$ID %in% bio_samples, , drop = FALSE]
sample_meta <- sample_meta[match(colnames(expr_raw), sample_meta$ID), , drop = FALSE]
rownames(sample_meta) <- NULL
sample_meta$sample_info <- droplevels(sample_meta$sample_info)
cat(" Biological samples:", ncol(expr_raw), "\n")

# Load metabolite annotation
metab_anno <- read.csv(METABOLITES_ANNO, stringsAsFactors = FALSE, check.names = FALSE)
colnames(metab_anno)[1] <- "ID"
metab_anno$ID <- as.character(metab_anno$ID)

# Match by compound name
name_to_anno <- metab_anno[match(rownames(expr_raw), metab_anno$name), , drop = FALSE]
rownames(name_to_anno) <- rownames(expr_raw)
cat(" Annotation match:", sum(!is.na(name_to_anno$ID)), "/", nrow(expr_raw), "\n")

name_map <- setNames(name_to_anno$name, rownames(expr_raw))
name_map[is.na(name_map)] <- rownames(expr_raw)[is.na(name_map)]

if ("class" %in% colnames(metab_anno)) {
 class_map <- setNames(name_to_anno$class, rownames(expr_raw))
} else {
 class_map <- setNames(rep("Unknown", nrow(expr_raw)), rownames(expr_raw))
}
class_map[is.na(class_map)] <- "Unknown"

# Load DE results
cat(" Loading DE results...\n")
de_results <- list()
for (nm in names(DE_FILES)) {
 de_results[[nm]] <- read.csv(DE_FILES[[nm]], stringsAsFactors = FALSE, check.names = FALSE)
 cat(" ", nm, ":", DE_FILES[[nm]], "-", sum(de_results[[nm]]$significant), "DE metabolites\n")
}

GROUP_CD <- "Clostridium difficile infection"
GROUP_FE <- "high iron diet before"
GROUP_NC <- "Standard (control)"

comparison_titles <- list(
 FE_vs_CD = "FE (High-Iron + CDI) vs CD (CDI only)",
 CD_vs_NC = "CD (CDI only) vs NC (Healthy Control)",
 FE_vs_NC = "FE (High-Iron + CDI) vs NC (Healthy Control)"
)

cat(" Data ready.\n\n")

# ===========================================================================
#3. (3a) Volcano Plots
# ===========================================================================
cat("[3] (3a) Generating Volcano Plots...\n")

for (nm in names(DE_FILES)) {
 res <- de_results[[nm]]
 cat(" ", nm, "...\n")

 pd <- res
 pd$neg_log10_p <- -log10(pmax(pd$pvalue_adj,1e-300))

 pd$color_group <- "Not Significant"
 pd$color_group[pd$direction == "Up"] <- "Up"
 pd$color_group[pd$direction == "Down"] <- "Down"
 pd$color_group <- factor(pd$color_group, levels = c("Up", "Down", "Not Significant"))

 # Top5 by |logFC| * -log10(p) among significant
 sidx <- which(pd$significant)
 if (length(sidx) >0) {
 pd$score <- abs(pd$logFC) * pd$neg_log10_p
 t5 <- sidx[order(-pd$score[sidx])][1:min(5, length(sidx))]
 } else {
 t5 <- integer(0)
 }

 nu <- sum(pd$direction == "Up", na.rm = TRUE)
 nd <- sum(pd$direction == "Down", na.rm = TRUE)
 ns <- sum(pd$significant, na.rm = TRUE)

 p <- ggplot(pd, aes(x = logFC, y = neg_log10_p, color = color_group)) +
 geom_point(alpha =0.6, size =1.5) +
 scale_color_manual(
 values = c("Up" = "#E64B35", "Down" = "#4DBBD5", "Not Significant" = "grey75"),
 labels = c(
 "Up" = paste0("Up (", nu, ")"),
 "Down" = paste0("Down (", nd, ")"),
 "Not Significant" = paste0("NS (", nrow(pd) - ns, ")")
 )) +
 geom_hline(yintercept = -log10(0.05), linetype = "dashed",
 color = "grey50", linewidth =0.5) +
 labs(
 title = comparison_titles[[nm]],
 subtitle = paste0("p.adj <0.05 + VIP >1 | ", ns, " DE metabolites"),
 x = expression(log[2]~Fold~Change),
 y = expression(-log[10]~(adjusted~P~value)),
 color = "Regulation"
 ) +
 theme_bw(base_size =12) +
 theme(
 plot.title = element_text(hjust =0.5, size =14, face = "bold"),
 plot.subtitle = element_text(hjust =0.5, size =10, color = "grey40"),
 legend.position = "right",
 panel.grid.minor = element_blank()
 )

 if (length(t5) >0) {
 p <- p + geom_text_repel(
 data = pd[t5, ],
 aes(label = name),
 size =3.2, max.overlaps =15, color = "black",
 box.padding =0.5, point.padding =0.3,
 fontface = "italic",
 segment.color = "grey50", segment.size =0.3
 )
 }

 pf <- file.path(FIGURES_DIR, paste0("Volcano_", nm, ".pdf"))
 pn <- file.path(FIGURES_DIR, paste0("Volcano_", nm, ".png"))

 pdf(pf, width =9, height =7)
 print(p)
 dev.off()

 png(pn, width =2700, height =2100, res =300)
 print(p)
 dev.off()

 cat(" Saved: ", basename(pf), " & ", basename(pn), "\n")
}
cat("\n")

# ===========================================================================
#4. (3b) Venn Diagram
# ===========================================================================
cat("[4] (3b) Generating Venn Diagram...\n")

venn_sets <- list()
for (nm in names(DE_FILES)) {
 feats <- de_results[[nm]]$Feature[de_results[[nm]]$significant]
 if (length(feats) >0) {
 venn_sets[[nm]] <- feats
 }
}

cat(" Set sizes:", paste(names(venn_sets), sapply(venn_sets, length), sep = "=", collapse = ", "), "\n")

if (length(venn_sets) >=2 && length(venn_sets) <=3) {
 display_names <- c(
 FE_vs_CD = "FE vs CD",
 CD_vs_NC = "CD vs NC",
 FE_vs_NC = "FE vs NC"
 )
 names(venn_sets) <- display_names[names(venn_sets)]

 pv <- ggVennDiagram(venn_sets, label = "count", label_geom = "text") +
 scale_fill_gradient(low = "white", high = "steelblue") +
 labs(title = "Differential Metabolites Overlap Across Comparisons") +
 theme_bw() +
 theme(
 plot.title = element_text(hjust =0.5, size =14, face = "bold"),
 legend.position = "none"
 )

 pdf(file.path(FIGURES_DIR, "Venn_diagram.pdf"), width =8, height =7)
 print(pv)
 dev.off()

 png(file.path(FIGURES_DIR, "Venn_diagram.png"), width =2400, height =2100, res =300)
 print(pv)
 dev.off()

 cat(" Saved: Venn_diagram.pdf & Venn_diagram.png\n")
} else {
 cat(" Skipped (need2-3 non-empty sets).\n")
}
cat("\n")

# ===========================================================================
#5. (3c) Heatmap
# ===========================================================================
cat("[5] (3c) Generating Heatmap...\n")

# Collect all unique significant features
all_sig <- unique(unlist(lapply(de_results, function(x) x$Feature[x$significant])))
cat(" Unique significant metabolites:", length(all_sig), "\n")

if (length(all_sig) >0) {
 hmx <- expr_raw[all_sig, , drop = FALSE]

 # Z-score by row
 hmz <- t(scale(t(hmx)))
 hmz[is.nan(hmz)] <-0

 # Order samples: NC -> CD -> FE
 go <- c(GROUP_NC, GROUP_CD, GROUP_FE)
 so <- unlist(lapply(go, function(g) sample_meta$ID[sample_meta$sample_info == g]))
 so <- intersect(so, colnames(hmz))
 hmz <- hmz[, so, drop = FALSE]

 # Column annotation
 ca <- data.frame(
 Group = factor(sample_meta$sample_info[match(so, sample_meta$ID)], levels = go),
 row.names = so
 )

 group_colors <- c(
 "Standard (control)" = "#4DBBD5",
 "Clostridium difficile infection" = "#E64B35",
 "high iron diet before" = "#00A087"
 )
 ac <- list(Group = group_colors)

 # Row annotation (class)
 rc <- class_map[rownames(hmz)]
 rc[is.na(rc)] <- "Unknown"
 uc <- unique(rc)
 nc <- length(uc)

 if (nc <=12) {
 cp <- RColorBrewer::brewer.pal(max(nc,3), "Set3")[1:nc]
 } else {
 cp <- rainbow(nc)
 }
 names(cp) <- uc

 ra <- data.frame(Class = factor(rc), row.names = rownames(hmz))
 rac <- list(Class = cp)

 # Row labels
 rl <- name_map[rownames(hmz)]

 # Determine if we show rownames
 show_rn <- length(all_sig) <=100
 fsize_row <- ifelse(show_rn,7,1)

 # Colors
 hcol <- colorRampPalette(c("#4DBBD5", "white", "#E64B35"))(100)
 hh <- max(6, min(30, nrow(hmz) *0.25 +3))

 cat(" Heatmap dimensions:", nrow(hmz), "features x", ncol(hmz), "samples\n")
 cat(" Height:", round(hh,1), "inches\n")

 pdf(file.path(FIGURES_DIR, "Heatmap_diff_metabolites.pdf"), width =10, height = hh)
 pheatmap(
 hmz, annotation_col = ca, annotation_row = ra,
 annotation_colors = c(ac, rac),
 cluster_rows = TRUE, cluster_cols = FALSE,
 show_rownames = show_rn, show_colnames = TRUE,
 labels_row = rl,
 color = hcol,
 fontsize_row = fsize_row, fontsize_col =8,
 border_color = NA,
 main = "Differential Metabolites Heatmap (Z-score)",
 scale = "none"
 )
 dev.off()

 png(file.path(FIGURES_DIR, "Heatmap_diff_metabolites.png"),
 width =3000, height = hh *300, res =300)
 pheatmap(
 hmz, annotation_col = ca, annotation_row = ra,
 annotation_colors = c(ac, rac),
 cluster_rows = TRUE, cluster_cols = FALSE,
 show_rownames = show_rn, show_colnames = TRUE,
 labels_row = rl,
 color = hcol,
 fontsize_row = fsize_row, fontsize_col =8,
 border_color = NA,
 main = "Differential Metabolites Heatmap (Z-score)",
 scale = "none"
 )
 dev.off()

 cat(" Saved: Heatmap_diff_metabolites.pdf & Heatmap_diff_metabolites.png\n")
} else {
 cat(" No significant metabolites. Skipping heatmap.\n")
}
cat("\n")

# ===========================================================================
#6. Summary
# ===========================================================================
cat(sep_line, "\n")
cat("Step3 COMPLETED SUCCESSFULLY\n")
cat(sep_line, "\n\n")

cat("Output figures in:", FIGURES_DIR, "\n\n")
cat(" Volcano plots (PDF+PNG,300 dpi, top5 labeled):\n")
for (nm in names(DE_FILES)) {
 ns <- sum(de_results[[nm]]$significant)
 cat(" - Volcano_", nm, ".pdf/png (", ns, " DE metabolites)\n", sep = "")
}
cat(" - Venn_diagram.pdf/png (3-comparison overlap)\n")
cat(" - Heatmap_diff_metabolites.pdf/png (", length(all_sig), " features x18 samples, class annotation)\n", sep = "")

cat("\nData tables already exist:\n")
for (nm in names(DE_FILES)) {
 cat(" - ", basename(DE_FILES[[nm]]), "\n")
}
cat(" - limma_multifactor_anova.csv\n")
cat(" - limma_overall_ftest.csv\n")
cat(" - limma_all_comparisons_consolidated.csv\n")

cat("\nReady for downstream modules:\n")
cat(" Module5: KEGG Enrichment Analysis\n")
cat(" Module10: Tables\n")
cat(" Module11: Report\n")
cat(sep_line, "\n")
